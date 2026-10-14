// 基础几何：顶点变换、表面读取、线性光照和附件写入；由所有gbuffers入口引入。
// 调用示例：gbuffers_terrain.fsh 声明 OMNI_FRAGMENT 后引入本文件。
#include "/effects/antialiasing.glsl"
#include "/effects/vegetation.glsl"
uniform sampler2D gtexture; // 当前物体底色贴图。
#if defined OMNI_ENTITIES && !defined IRIS_FEATURE_ENTITY_TRANSLUCENT
#define OMNI_OVERLAY // 没有透明实体分离能力时拒绝屏幕后处理。
#endif
#ifdef OMNI_VERTEX
in vec4 mc_Entity; // 方块分类。
in vec4 at_tangent; // 加载器切线与手性。
in vec4 mc_midTexCoord; // 图集图块中心。
out vec2 uv, lightUv; // 贴图和原版光照坐标。
out vec4 tint, bounds; // 顶点色和视差边界。
out vec3 viewPosition, viewNormal, viewTangent; // 视空间几何。
out float tangentSign; // 切线手性。
flat out float materialId; // 不插值的方块分类。
#if defined OMNI_WATER_PASS && defined OMNI_TERRAIN
// 顶点位移需要与片元相同的海浪高度来源。
#include "/effects/water.glsl"
#endif
void main() {
    uv=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy; // 保留贴图变换。
    lightUv=clamp((gl_TextureMatrix[1]*gl_MultiTexCoord1).xy,0.0,1.0); // 保留原版光照。
    tint=gl_Color; materialId=mc_Entity.x; // 保存顶点颜色和方块分类。
    vec4 view=gl_ModelViewMatrix*gl_Vertex; // 进入相机空间。
#if defined OMNI_TERRAIN && !defined OMNI_HAND
    vec3 world=omniWorld(view.xyz); // 植物摆动使用世界锚点。
    world=omniVegetation(world,materialId,gl_MultiTexCoord0.y<mc_midTexCoord.y?1.0:0.0); // 只移动允许的植物。
    view=gbufferModelView*vec4(world,1.0); // 变形后回到视空间。
#endif
#if defined OMNI_WATER_PASS && defined OMNI_TERRAIN && !defined OMNI_HAND
    if (materialId==10000.0) {
        vec3 waterWorld=omniWorld(view.xyz); // 位移前的世界位置。
        vec3 waterNormalWorld=omniNormalize(mat3(gbufferModelViewInverse)*omniNormalize(gl_NormalMatrix*gl_Normal)); // 世界法线判断顶面。
        if (waterNormalWorld.y>0.9) { waterWorld.y+=omniOceanHeight((waterWorld+cameraPosition).xz); view=gbufferModelView*vec4(waterWorld,1.0); } // 只抬升水顶面，侧面与瀑布不动。
    }
#endif
    viewPosition=view.xyz; viewNormal=omniNormalize(gl_NormalMatrix*gl_Normal); // 保存几何位置和法线。
    viewTangent=omniNormalize(gl_NormalMatrix*at_tangent.xyz); tangentSign=at_tangent.w; // 保存切线。
    vec2 halfTile=abs(gl_MultiTexCoord0.xy-mc_midTexCoord.xy); // 计算图块边界。
    bounds=vec4(mc_midTexCoord.xy-halfTile+vec2(0.00001),mc_midTexCoord.xy+halfTile-vec2(0.00001)); // 防止视差越过图块。
    gl_Position=gl_ProjectionMatrix*view; // 使用兼容投影。
#if OMNI_AA_MODE == 2 && !defined OMNI_HAND
    gl_Position.xy+=omniJitter(frameCounter)*2.0/vec2(viewWidth,viewHeight)*gl_Position.w; // 全场景共用抖动。
#endif
}
#endif
#ifdef OMNI_FRAGMENT // 调用位置：所有gbuffers_*片元阶段。
in vec2 uv, lightUv; in vec4 tint, bounds; // 贴图、光照、颜色和图块边界。
in vec3 viewPosition, viewNormal, viewTangent; in float tangentSign; flat in float materialId; // 表面输入。
#ifdef OMNI_WATER_PASS
/* RENDERTARGETS: 0,7,8 */
#elif defined OMNI_OVERLAY
/* RENDERTARGETS: 0,7 */
#else
/* RENDERTARGETS: 0,1,2,7 */
#endif
layout(location=0) out vec4 scene; // 线性颜色。
#if !defined OMNI_OVERLAY && !defined OMNI_WATER_PASS
layout(location=1) out vec4 normalsOut; layout(location=2) out vec4 materialOut; layout(location=3) out vec4 lightOut; // 不透明附件。
#else
layout(location=1) out vec4 overlayMarker; // 覆盖有效性。
#ifdef OMNI_WATER_PASS
layout(location=2) out vec4 waterSurface; // 水法线和视空间深度。
#endif
#endif
#include "/effects/material.glsl"
#include "/effects/sunlight.glsl"
#include "/effects/water.glsl"
struct Surface {
    vec4 base; // 贴图底色和透明度。
    vec3 normal; // 视空间法线。
    vec3 materialParams; // 粗糙、金属、自发光。
    float materialAo; // 线性环境遮蔽。
    vec3 world, viewPosition; // 世界和视空间位置。
    vec2 lightUv; // 原版光照。
    float category; // 普通、水、手、远景类别。
};
// 读取表面：构造切线、解码材质、裁切透明并决定水和手的类别。
Surface omniReadSurface() {
    Surface s; s.base=tint; s.normal=dot(viewNormal,viewNormal)>1e-6?omniNormalize(viewNormal):vec3(0,0,1); // 读取底色和有效法线。
    vec3 candidate=viewTangent-s.normal*dot(s.normal,viewTangent); vec3 fallback=cross(s.normal,abs(s.normal.y)<0.9?vec3(0,1,0):vec3(1,0,0)); // 准备切线回退。
    vec3 tangent=omniNormalize(dot(candidate,candidate)>1e-5?candidate:fallback); mat3 tangentFrame=mat3(tangent,omniNormalize(cross(s.normal,tangent))*(tangentSign<0.0?-1.0:1.0),s.normal); // 建立切线基。
    s.materialParams=vec3(0.85,0.04,0.0); s.materialAo=1.0; vec2 tex=uv; // 普通材质默认不遮蔽。
#if defined OMNI_BASIC
    s.base=tint; // 线条没有可靠图集。
#elif defined OMNI_TERRAIN
    omniMaterial(s.base,s.normal,s.materialParams,s.materialAo,tex,bounds,tangentFrame,viewPosition,true); // 地形解码并允许视差。
#else
    omniMaterial(s.base,s.normal,s.materialParams,s.materialAo,tex,bounds,tangentFrame,viewPosition,false); // 实体和手解码但不视差。
#endif
    if(s.base.a<0.01) discard; // 完全透明不写附件。
#if !defined OMNI_WATER_PASS
    if(s.base.a<0.1) discard; // 低透明裁切对象不写表面。
#endif
#ifdef OMNI_ENTITIES
    s.base.rgb=mix(s.base.rgb,entityColor.rgb,entityColor.a); // 保留实体受伤颜色。
#endif
    s.viewPosition=viewPosition; s.world=omniWorld(viewPosition); s.lightUv=lightUv; s.category=0.0; // 保存通用位置。
#ifdef OMNI_HAND
    s.category=2.0; // 手持物不参与世界历史。
#endif
#ifdef OMNI_WATER_PASS
    if(materialId==10000.0) { s.normal=omniWaterNormal(s.world,s.normal); s.materialParams=vec3(0.06,0.02,0.0); s.category=1.0; s.base.a=1.0; } // 水顶面造波，侧面保留原法线。
#endif
    return s; // 返回完整业务表面。
}
// 计算光照：贴图转线性，应用天气材质，再计算环境、直接光和自发光。
vec3 omniShadeSurface(inout Surface s) {
    vec3 albedo=omniLinear(s.base.rgb); // 颜色在这里唯一转线性。
    omniSurface(albedo,s.materialParams,s.normal,s.world,s.lightUv.y); // 应用湿润和积雪。
    vec3 lit=omniLighting(albedo,s.normal,s.world,s.lightUv,s.materialParams,s.materialAo); // AO仅进入环境光。
#ifdef OMNI_EMISSIVE
    lit=albedo*2.0; s.materialParams.z=1.0; // 发光保持自身颜色。
#endif
    return lit; // 仍是显示编码前的颜色。
}
// 写附件：把同一表面写入颜色、类别、材质、覆盖和水深协议。
void omniWriteSurface(in Surface s,vec3 lit) {
    scene=vec4(lit,s.base.a); // 所有路径写颜色。
#if !defined OMNI_OVERLAY && !defined OMNI_WATER_PASS
    normalsOut=vec4(s.normal*0.5+0.5,s.category); materialOut=vec4(s.materialParams,s.lightUv.y); lightOut=vec4(s.lightUv,0.0,s.base.a>=0.999?1.0:0.0); // 不透明附件精确配对。
#else
    overlayMarker=vec4(0); // 覆盖层拒绝底层匹配。
#ifdef OMNI_WATER_PASS
    waterSurface=vec4(0); if(s.category==1.0) { waterSurface=vec4(s.normal*0.5+0.5,s.viewPosition.z); overlayMarker=vec4(s.lightUv,1.0,1.0); } // 水保存自身法线与视深度。
#endif
#endif
}
void main() {
    Surface surface=omniReadSurface(); // 步骤一：读取表面。
    vec3 lit=omniShadeSurface(surface); // 步骤二：计算光照。
    omniWriteSurface(surface,lit); // 步骤三：写入统一附件。
}
#endif
