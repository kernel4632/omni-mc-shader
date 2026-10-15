// 远景几何：处理加载器额外送来的 `Distant Horizons`（下文简称 DH）远景地形与水面。
// 管什么：本文件只管远景这一条路径——顶点变换、类别与自发光映射、水波，以及按缓冲协议写附件；
//   它不安排绘制顺序，也不复制近景地形的算法，顺序由世界目录里成对的入口决定。
// 调用位置：
//   主世界、下界、末地三个维度目录下的 dh_terrain.vsh 声明 OMNI_VERTEX 后引入，dh_terrain.fsh 声明 OMNI_FRAGMENT 后引入，
//   dh_water.vsh 与 dh_water.fsh 再额外声明 OMNI_WATER_PASS；顶点与片元各取所需，共用本文件。
// 可复制示例（一对薄入口里）：
//   #define OMNI_VERTEX
//   #define OMNI_FRAGMENT
//   #include "/rendering/distant.glsl"
// 设计原因与取舍：
//   近景与远景各用各自的投影与深度：远景由加载器在极远处生成，坐标落在普通近远裁剪面之外，
//   所以顶点用 dhProjection 投影、重建时用 dhProjectionInverse；普通地形那边用 gl_ProjectionMatrix 与普通逆投影，两者不能混用。
//   远景不读普通地形贴图：加载器只给一个小编号（例如水、岩浆）加顶点色，材质因此是保守的默认值，不做 labPBR 解码。
//   内部数据互相信任：本文件只信任加载器已经给好的输入，不在层与层之间重复检查。
// 顶点抖动来自抗锯齿文件，统一光照来自光照文件，水波来自水面文件，行星曲率来自世界文件，四者都显式引入。
#include "/effects/antialiasing.glsl"
#include "/effects/sunlight.glsl"
#include "/effects/water.glsl"
#include "/effects/world.glsl"
#ifdef OMNI_VERTEX
out vec3 viewPosition, viewNormal; // 传给片元的视空间位置与法线。
out vec4 tint; out vec2 lightUv; // 传给片元的顶点色与原版光照坐标。
flat out int materialId; // 远景小编号不插值，按整数原样传到片元。
// --- 顶点阶段：把加载器给的原版顶点转到视空间，再按远景投影写出坐标 ---
void main() {
    viewPosition = (gl_ModelViewMatrix*gl_Vertex).xyz; // 用兼容内置矩阵进入视空间，远景顶点同样适用。
    viewNormal = omniNormalize(gl_NormalMatrix*gl_Normal); // 远景面法线，归一化后交给照明。
    tint = gl_Color; lightUv = clamp(gl_MultiTexCoord2.xy/240.0,0.0,1.0); // 远景没有底色纹理，光照坐标按原版等级换算到零一。
#ifdef DISTANT_HORIZONS
    materialId = dhMaterialId; // 加载器自动声明的小编号，标记这块远景是什么。
#if defined OMNI_WATER_PASS
    if (materialId==DH_BLOCK_WATER && viewNormal.y>0.9) { // 远景顶面水按近景同一海浪抬升，近远交界处水面才不断开。
        vec3 waterWorld = omniWorld(viewPosition); // 位移前的相机相对世界位置。
        waterWorld.y += omniOceanHeight((waterWorld+cameraPosition).xz); // 与近景共用同一海浪高度函数，只抬朝上的面。
        viewPosition = (gbufferModelView*vec4(waterWorld,1.0)).xyz; // 世界位移后再变回视空间，投影前完成。
    }
#endif
    viewPosition = omniPlanetCurve(viewPosition); // 远景按水平距离下沉，做出地平线弧度。
    gl_Position = dhProjection*vec4(viewPosition,1.0); // 远景很远，必须用加载器的远景投影，不能用普通近远裁剪面。
#else
    materialId = 0; viewPosition = omniPlanetCurve(viewPosition); gl_Position = gl_ProjectionMatrix*vec4(viewPosition,1.0); // 未启用远景的离线基础路径仍能编译，运行时不会被调用。
#endif
#ifdef OMNI_AA_ENABLED
    gl_Position.xy += omniJitter(frameCounter)*2.0/vec2(viewWidth,viewHeight)*gl_Position.w; // 和近景用同一像素抖动，时间合成才能对齐。
#endif
}
#endif
#ifdef OMNI_FRAGMENT
in vec3 viewPosition, viewNormal; // 顶点传下来的视空间位置与法线。
in vec4 tint; in vec2 lightUv; // 顶点色与原版光照坐标。
flat in int materialId; // 远景小编号，不插值。
#ifdef OMNI_WATER_PASS
/* RENDERTARGETS: 0,7,8 */
#else
/* RENDERTARGETS: 0,1,2,7 */
#endif
layout(location=0) out vec4 scene; // 远景线性颜色。
#ifndef OMNI_WATER_PASS
layout(location=1) out vec4 normalsOut; // 远景法线与类别。
layout(location=2) out vec4 materialOut; // 远景基础材质。
layout(location=3) out vec4 lightOut; // 远景光照记录。
#else
layout(location=1) out vec4 overlayMarker; // 远景透明物不改底层类别。
layout(location=2) out vec4 waterSurface; // 水面的独立法线与实际视深度。
#endif
// --- 把加载器小编号映射成远景类别与自发光 ---
// 做什么：把小号翻译成本项目统一的表面类别（正常、水），并判断是否自发光。
// 为什么单独成函数：映射只在这一处定义，造波和写附件都读同一结果，不会两边不一致。
// 考虑点：没有加载器编号（离线编译）时返回普通类别、无自发光，保证基础路径能编译。
void omniDistantCategory(out float category, out float emission) {
    category = 3.0; // 默认普通远景类别，和近景普通表面区分开。
    emission = 0.0; // 默认没有自发光。
#ifdef DISTANT_HORIZONS
    if (materialId==DH_BLOCK_LAVA || materialId==DH_BLOCK_ILLUMINATED) emission = 1.0; // 岩浆与发光方块按自发光处理。
#endif
#if defined DISTANT_HORIZONS && defined OMNI_WATER_PASS
    if (materialId==DH_BLOCK_WATER) category = 1.0; // 只有水面通道才把远景水当成水类别。
#endif
}
// --- 让远景水面也起波 ---
// 做什么：片元属于水类别时，用本项目的统一波浪给远景水重建法线。
// 为什么复用近景造波：近远水面在同一世界里，波参数必须一致，否则近远景交界处水面会断开。
// 考虑点：只改水类别的法线，远景瀑布与水流的侧面保留原始法线；没有加载器编号时不动法线。
void omniDistantWaterNormal(inout vec3 normal, vec3 world, float category) {
#if defined DISTANT_HORIZONS && defined OMNI_WATER_PASS
    if (category==1.0) normal = omniWaterNormal(world,normal); // 远景水也保留侧面原始法线。
#endif
}
// --- 按缓冲协议写入远景附件 ---
// 做什么：所有远景片元都写线性颜色；不透明通道再写类别、材质和光照，水面通道改写法线与实际视深度。
// 为什么单独成函数：附件协议集中在一条直线上，主流程只剩"算表面再写结果"，接手者一屏读完。
// 考虑点：水在颜色透明通道里存不透明快照，避免水下与水面重叠；非水表面拒绝匹配，保留底层类别。
void omniDistantWrite(vec3 lit, vec3 normal, vec3 materialParams, float category) {
    scene = vec4(lit,1.0); // 所有路径都写颜色，透明通道先按不透明。
#ifndef OMNI_WATER_PASS
    normalsOut = vec4(normal*0.5+0.5,category); // 法线编码到零一，类别写在透明通道。
    materialOut = vec4(materialParams,lightUv.y); // 基础材质和原版光照强度。
    lightOut = vec4(lightUv,0.0,1.0); // 真实光照输入，标记几何有效。
#else
    scene.a = category==1.0 ? 1.0 : tint.a; // 水用不透明快照，非水沿用顶点透明度。
    overlayMarker = vec4(0.0); waterSurface = vec4(0.0); // 先默认非水：拒绝匹配、无独立水面。
    if (category==1.0) { overlayMarker = vec4(lightUv,2.0,1.0); waterSurface = vec4(normal*0.5+0.5,viewPosition.z); } // 水标记来源为远景，并写自身法线与实际视深度。
#endif
}
// --- 片元主流程：先算远景表面，再写结果 ---
void main() {
    if (tint.a<0.01) discard; // 完全透明的远景片元直接丢弃，不写颜色与元数据。
    vec3 world = omniWorld(viewPosition); // 相机相对世界位置，波浪按它锚定。
    vec3 normal = omniNormalize(viewNormal); // 统一视空间法线。
    float category, emission; // 远景类别与自发光。
    omniDistantCategory(category,emission); // 小编号映射到类别与自发光。
    omniDistantWaterNormal(normal,world,category); // 只有水类别才造波。
    vec3 materialParams = vec3(category==1.0?0.06:0.85,0.04,emission); // 远景基础材质：水更光滑，其余偏粗糙。
    vec3 lit = omniLighting(omniLinear(tint.rgb),normal,world,lightUv,materialParams,1.0); // 复用统一光照算远景颜色。
    omniDistantWrite(lit,normal,materialParams,category); // 按协议写全部附件。
}
#endif
