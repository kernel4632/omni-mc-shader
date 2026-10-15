// 基础几何：所有普通方块、实体和手持物的表面都从这里进入光照管线。
// 管什么：顶点阶段把模型坐标变成视空间几何，片元阶段把贴图读成一份表面、算成线性光照，再写进约定的附件。
// 调用位置：各维度的 gbuffers_terrain、gbuffers_entities、gbuffers_hand、gbuffers_water 等薄入口，
//   顶点阶段声明 OMNI_VERTEX 后引入一次，片元阶段声明 OMNI_FRAGMENT 后引入一次。
// 可复制示例：片元入口先 `#define OMNI_FRAGMENT`，再 `#include "/rendering/terrain.glsl"`，最后调用 `main()`；顶点入口同理改用 OMNI_VERTEX。
// 设计原因与取舍：
//   读取、着色、写入拆成三个函数，中间用一份表面结构传递：omniReadSurface 只管把输入整理成表面，
//   omniShadeSurface 只管把表面换成颜色，omniWriteSurface 只管把同一份表面写进附件，改一步不会波及其他步。
//   顶点和片元共用一份海浪高度：顶点抬升读 effects/water.glsl 的 omniOceanHeight，水面的物理高度和片元法线因此不会各算各的。
// 抖动与植物摆动是本文件引入的两个共用效果。
// 场景抗锯齿抖动。
#include "/effects/antialiasing.glsl"
// 植物顶点摆动。
#include "/effects/vegetation.glsl"
uniform sampler2D gtexture; // 当前物体的底色贴图，材质解码时还要乘上它。
#if defined OMNI_ENTITIES && !defined IRIS_FEATURE_ENTITY_TRANSLUCENT
#define OMNI_OVERLAY // 加载器没有透明实体分离能力时，只能把半透明实体当叠层处理，拒绝与深度配对的后处理。
#endif
// --- 顶点阶段 ---
#ifdef OMNI_VERTEX
in vec4 mc_Entity; // 加载器给的方块分类，整数存在 x 分量里。
in vec4 at_tangent; // 加载器给的切线与手性：前三分量是切线方向，w 分量记录模型是否镜像。
in vec4 mc_midTexCoord; // 当前图块在图集里的中心坐标，用来算图块边界。
out vec2 uv, lightUv; // 输出的贴图坐标和原版光照坐标。
out vec4 tint, bounds; // 输出的顶点色和图块边界。
out vec3 viewPosition, viewNormal, viewTangent; // 输出的视空间位置、法线和切线。
out float tangentSign; // 输出的切线手性。
flat out float materialId; // 输出的方块分类，同一三角形内不插值。
#if defined OMNI_WATER_PASS && defined OMNI_TERRAIN
// 水面顶点要按同样的波浪高度抬升，所以顶点阶段也要引入水效果。
#include "/effects/water.glsl"
#endif
void main() {
    uv=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy; // 贴图坐标先过纹理矩阵，保留资源包的缩放与平铺。
    lightUv=clamp((gl_TextureMatrix[1]*gl_MultiTexCoord1).xy,0.0,1.0); // 光照坐标同样过矩阵并夹到零到一，原版就靠这两组数。
    tint=gl_Color; materialId=mc_Entity.x; // 顶点色直接交给片元，方块分类取分类张量的第一个数。
    vec4 view=gl_ModelViewMatrix*gl_Vertex; // 模型坐标先进入相机空间。
#if defined OMNI_TERRAIN && !defined OMNI_HAND
    vec3 world=omniWorld(view.xyz); // 植物摆动按世界坐标计算，方块在世界里固定不动。
    world=omniVegetation(world,materialId,gl_MultiTexCoord0.y<mc_midTexCoord.y?1.0:0.0); // 只让草尖这类顶点摆动，图块下沿保持不动。
    view=gbufferModelView*vec4(world,1.0); // 位移后的世界坐标再变回相机空间，后面的投影才正确。
#endif
#if defined OMNI_WATER_PASS && defined OMNI_TERRAIN && !defined OMNI_HAND
    if (materialId==10000.0) {
        vec3 waterWorld=omniWorld(view.xyz); // 位移前的世界位置，用来判断这面水朝哪。
        vec3 waterNormalWorld=omniNormalize(mat3(gbufferModelViewInverse)*omniNormalize(gl_NormalMatrix*gl_Normal)); // 把面法线转到世界空间，只看它朝不朝上。
        if (waterNormalWorld.y>0.9) { waterWorld.y+=omniOceanHeight((waterWorld+cameraPosition).xz); view=gbufferModelView*vec4(waterWorld,1.0); } // 只抬升朝上的水面：侧面和瀑布竖直，抬了会和真实几何脱节。
    }
#endif
    viewPosition=view.xyz; viewNormal=omniNormalize(gl_NormalMatrix*gl_Normal); // 保存视空间位置和归一化法线。
    viewTangent=omniNormalize(gl_NormalMatrix*at_tangent.xyz); tangentSign=at_tangent.w; // 保存切线与手性，片元再拼成切线基。
    vec2 halfTile=abs(gl_MultiTexCoord0.xy-mc_midTexCoord.xy); // 当前贴图坐标离图块中心有多远。
    bounds=vec4(mc_midTexCoord.xy-halfTile+vec2(0.00001),mc_midTexCoord.xy+halfTile-vec2(0.00001)); // 把图块四角收进一点，视差采样就不会越到隔壁方块。
    gl_Position=gl_ProjectionMatrix*view; // 用兼容投影把相机空间位置投到裁剪空间。
#if OMNI_AA_MODE == 2 && !defined OMNI_HAND
    gl_Position.xy+=omniJitter(frameCounter)*2.0/vec2(viewWidth,viewHeight)*gl_Position.w; // 抗锯齿模式二下全场景共用同一像素偏移，手不抖以免糊掉。
#endif
}
#endif
// --- 片元阶段 ---
#ifdef OMNI_FRAGMENT // 调用位置：所有 gbuffers 程序的片元阶段。
in vec2 uv, lightUv; in vec4 tint, bounds; // 顶点传来的贴图坐标、光照坐标、顶点色、图块边界。
in vec3 viewPosition, viewNormal, viewTangent; in float tangentSign; flat in float materialId; // 顶点传来的视空间几何、切线手性和方块分类。
// 附件分配分三种阶段，同一个程序只走其中一条：
//   水阶段只写颜色和第 7、8 号附件（叠层标记、水面法线与深度），不动底层类别和材质，水面才不会盖掉它后面方块的信息。
//   叠层阶段（不写深度的半透明物）只写颜色和第 7 号附件，同样不碰底层。
//   不透明阶段才把颜色、法线类别、材质、光照四类附件写满。
#ifdef OMNI_WATER_PASS
/* RENDERTARGETS: 0,7,8 */
#elif defined OMNI_OVERLAY
/* RENDERTARGETS: 0,7 */
#else
/* RENDERTARGETS: 0,1,2,7 */
#endif
layout(location=0) out vec4 scene; // 线性颜色，所有阶段都写这一份。
#if !defined OMNI_OVERLAY && !defined OMNI_WATER_PASS
layout(location=1) out vec4 normalsOut; layout(location=2) out vec4 materialOut; layout(location=3) out vec4 lightOut; // 不透明阶段的三份额外表面数据。
#else
layout(location=1) out vec4 overlayMarker; // 叠层与水阶段的有效标记，合成阶段靠它判断这层能不能和深度配对。
#ifdef OMNI_WATER_PASS
layout(location=2) out vec4 waterSurface; // 水阶段专有的水面法线和视空间深度。
#endif
#endif
// 解码资源包材质贴图。
#include "/effects/material.glsl"
// 统一环境光、直接光和镜面。
#include "/effects/sunlight.glsl"
// 按世界位置给水面造波。
#include "/effects/water.glsl"
// 表面结构：读取阶段把输入填进它，着色和写入阶段只读它。
struct Surface {
    vec4 base; // 贴图底色和透明度。
    vec3 normal; // 视空间法线。
    vec3 materialParams; // 粗糙度、金属度、自发光。
    float materialAo; // 线性环境遮蔽。
    vec3 world, viewPosition; // 世界位置和视空间位置。
    vec2 lightUv; // 原版光照坐标。
    float category; // 类别：零普通、一水、二手、三远景。
};
// 由几何法线与加载器切线拼出切线基：切线基是给法线贴图用的三根互相垂直的轴。
// 为什么要有回退：加载器偶尔给出退化的切线，或者切线和法线几乎平行，直接叉乘会得到零向量，整张法线贴图都会翻。
// 为什么乘手性符号：模型镜像时副切线方向要跟着翻，否则凹凸会反。
mat3 omniTangentFrame(vec3 normal, vec3 tangent, float tangentSign) {
    vec3 aligned=tangent-normal*dot(normal,tangent); // 切掉切线里与法线平行的部分，只留切线平面内的分量。
    bool valid=dot(aligned,aligned)>1e-5; // 剩下的分量太短就是退化切线。
    vec3 fallback=cross(normal,abs(normal.y)<0.9?vec3(0,1,0):vec3(1,0,0)); // 退化时随便取一根与法线垂直的轴顶上。
    vec3 bitangent=omniNormalize(cross(normal,valid?aligned:fallback)); // 副切线由法线和切线叉乘得到。
    return mat3(omniNormalize(valid?aligned:fallback),bitangent*(tangentSign<0.0?-1.0:1.0),normal); // 三列依次是切线、副切线、法线。
}
// 读取表面：把顶点输入和贴图整理成一份表面，透明片元在这里丢弃。
Surface omniReadSurface() {
    Surface s; // 下面逐步填满它。
    s.base=tint; // 先用顶点色当底色，材质解码会继续乘上贴图。
    s.normal=dot(viewNormal,viewNormal)>1e-6?omniNormalize(viewNormal):vec3(0,0,1); // 几何法线退化时退到朝向相机的方向，避免后面除零。
    mat3 tangentFrame=omniTangentFrame(s.normal,viewTangent,tangentSign); // 给法线贴图用的切线基。
    s.materialParams=vec3(0.85,0.04,0.0); s.materialAo=1.0; vec2 tex=uv; // 普通表面默认：很粗糙、不金属、不发光、不遮蔽。
#if defined OMNI_BASIC
    // 线条没有可靠的图集边界，只保留上面的顶点色，不采样材质贴图。
#elif defined OMNI_TERRAIN
    omniMaterial(s.base,s.normal,s.materialParams,s.materialAo,tex,bounds,tangentFrame,viewPosition,true); // 地形有可靠图集，允许视差偏移。
#else
    omniMaterial(s.base,s.normal,s.materialParams,s.materialAo,tex,bounds,tangentFrame,viewPosition,false); // 实体和手没有可靠图集，只解码不偏移。
#endif
    if(s.base.a<0.01) discard; // 整体透明的片元没有表面，直接丢弃，不写任何附件。
#if !defined OMNI_WATER_PASS
    if(s.base.a<0.1) discard; // 不透明阶段把接近透明的裁切物也丢掉，它们不该写进不透明缓冲。
#endif
#ifdef OMNI_ENTITIES
    s.base.rgb=mix(s.base.rgb,entityColor.rgb,entityColor.a); // 保留实体受击闪红，只有实体自带这个颜色。
#endif
    s.viewPosition=viewPosition; s.world=omniWorld(viewPosition); s.lightUv=lightUv; s.category=0.0; // 保存位置、世界坐标、光照坐标，默认普通类别。
#ifdef OMNI_HAND
    s.category=2.0; // 手单独归类：它离相机太近，不参与世界历史与反射，否则会拖出一条假影子。
#endif
#ifdef OMNI_WATER_PASS
    if(materialId==10000.0) { s.normal=omniWaterNormal(s.world,s.normal); s.materialParams=vec3(0.06,0.02,0.0); s.category=1.0; s.base.a=1.0; } // 只让水面按世界位置造波并标成光滑不透光的水；侧面和瀑布保留原法线。
#endif
    return s; // 交回填满的表面。
}
// 计算光照：把底色转线性，叠加天气材质，再算环境光、直接光和自发光。
vec3 omniShadeSurface(inout Surface s) {
    vec3 albedo=omniLinear(s.base.rgb); // 底色只在这里转一次线性，之后的天气和光照都按线性值算。
    omniSurface(albedo,s.materialParams,s.normal,s.world,s.lightUv.y); // 按天气叠加湿润与积雪，就地改这处颜色和材质。
    vec3 lit=omniLighting(albedo,s.normal,s.world,s.lightUv,s.materialParams,s.materialAo); // 环境光、直接光和镜面一起算，遮蔽只影响环境光。
#ifdef OMNI_EMISSIVE
    lit=albedo*2.0; s.materialParams.z=1.0; // 自发光方块无视光照直接用自身颜色，并标记发光供后处理识别。
#endif
    return lit; // 显示编码留给后面的合成阶段，这里保持线性。
}
// 写附件：把同一份表面按当前阶段写进约定的附件。
// 附件编号由 rendering/buffers.glsl 统一约定，这里只写不读。
void omniWriteSurface(in Surface s,vec3 lit) {
    scene=vec4(lit,s.base.a); // 所有路径都写颜色附件，透明通道留给合成阶段判断叠加。
#if !defined OMNI_OVERLAY && !defined OMNI_WATER_PASS
    normalsOut=vec4(s.normal*0.5+0.5,s.category); materialOut=vec4(s.materialParams,s.lightUv.y); lightOut=vec4(s.lightUv,0.0,s.base.a>=0.999?1.0:0.0); // 不透明阶段写全法线、类别、材质、光照；透明通道拉满表示这层完全遮住背后。
#else
    overlayMarker=vec4(0); // 叠层默认不写有效标记，让合成阶段忽略它。
#ifdef OMNI_WATER_PASS
    waterSurface=vec4(0); if(s.category==1.0) { waterSurface=vec4(s.normal*0.5+0.5,s.viewPosition.z); overlayMarker=vec4(s.lightUv,1.0,1.0); } // 只有水写独立法线和真实视深度，其余面留零，合成时按非水处理。
#endif
#endif
}
void main() {
    Surface surface=omniReadSurface(); // 步骤一：把顶点输入和贴图读成一份表面。
    vec3 lit=omniShadeSurface(surface); // 步骤二：把表面算成线性光照颜色。
    omniWriteSurface(surface,lit); // 步骤三：把表面和颜色写进约定的附件。
}
#endif
