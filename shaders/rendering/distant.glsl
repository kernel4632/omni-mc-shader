// 远景：依照官方独立投影与材质小编号，不读取普通地形贴图；示例 dh_terrain 引入。
// 抖动与共用照明。
#include "/effects/antialiasing.glsl"
#include "/effects/sunlight.glsl"
#include "/effects/water.glsl"
#ifdef OMNI_VERTEX
out vec3 viewPosition, viewNormal; // 远景真实几何。
out vec4 tint; out vec2 lightUv; // 原版远景颜色与光照。
flat out int materialId; // 远景小编号由加载器自动提供。
void main() {
    viewPosition = (gl_ModelViewMatrix*gl_Vertex).xyz; // 官方支持的内置变换。
    viewNormal = omniNormalize(gl_NormalMatrix*gl_Normal); // 远景面法线。
    tint = gl_Color; lightUv = clamp(gl_MultiTexCoord2.xy/240.0,0.0,1.0); // 远景没有底色纹理，光照坐标按原版等级转换。
#ifdef DISTANT_HORIZONS
    materialId = dhMaterialId; // 官方自动声明的属性。
    gl_Position = dhProjection*vec4(viewPosition,1.0); // 远景不能使用普通近远裁剪面。
#else
    materialId = 0; gl_Position = gl_ProjectionMatrix*vec4(viewPosition,1.0); // 离线基础路径仍可编译，加载器未启用远景则不会调用。
#endif
#if OMNI_AA_MODE == 2
    gl_Position.xy += omniJitter(frameCounter)*2.0/vec2(viewWidth,viewHeight)*gl_Position.w; // 和近景同一像素抖动。
#endif
}
#endif
#ifdef OMNI_FRAGMENT
in vec3 viewPosition, viewNormal; // 远景几何依据。
in vec4 tint; in vec2 lightUv; // 远景颜色与原版光照。
flat in int materialId; // 远景编号不插值。
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
void main() {
    if (tint.a<0.01) discard; // 完全透明远景片元不写颜色与元数据。
    vec3 world = omniWorld(viewPosition), normal = omniNormalize(viewNormal); // 同一视空间与世界空间协议。
    float kind = 3.0, emission = 0.0; // 远景没有实验室材质贴图。
#ifdef DISTANT_HORIZONS
    if (materialId==DH_BLOCK_LAVA || materialId==DH_BLOCK_ILLUMINATED) emission = 1.0; // 官方发光小编号。
#ifdef OMNI_WATER_PASS
    if (materialId==DH_BLOCK_WATER) { normal = omniWaterNormal(world,normal); kind = 1.0; } // 远景水也保留侧面原始法线。
#endif
#endif
    vec3 props = vec3(kind==1.0?0.06:0.85,0.04,emission); // 远景基础材质参数。
    scene = vec4(omniLighting(omniLinear(tint.rgb),normal,world,lightUv,props,1.0),1.0); // DH没有材质AO，使用线性一作为环境遮蔽。
#ifndef OMNI_WATER_PASS
    normalsOut = vec4(normal*0.5+0.5,kind); // 深度重建由远景深度判定。
    materialOut = vec4(props,lightUv.y); // 明确基础材质回退。
    lightOut = vec4(lightUv,0.0,1.0); // 真实光照输入。
#else
    scene.a = kind==1.0 ? 1.0 : tint.a; // DH 水与近景水同样使用不透明快照法。
    overlayMarker = vec4(0.0); waterSurface = vec4(0.0); // 非水表面拒绝匹配，保留底层类别。
    if (kind==1.0) { overlayMarker = vec4(lightUv,2.0,1.0); waterSurface = vec4(normal*0.5+0.5,viewPosition.z); } // 远景水写明独立投影来源。
#endif
}
#endif
