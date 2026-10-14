// 水：几何波浪法线与合成吸收折射，示例 omniWater(color, view, normal, uv)。
#ifndef OMNI_WATER
#define OMNI_WATER
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"水波强度","en_us":"Wave strength"},"slider":true}
#define OMNI_WAVE_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"水折射","en_us":"Water refraction"}}
#define OMNI_WATER_REFRACTION
// @option {"label":{"zh_cn":"雨滴水纹","en_us":"Rain ripples"}}
#define OMNI_RAIN_RIPPLES
// @option {"label":{"zh_cn":"玩家互动水纹","en_us":"Player ripples"},"description":{"zh_cn":"相机靠近水面移动时生成解析圆环；不是物理模拟，不读取其他实体。","en_us":"Analytic rings near a moving camera, not a fluid simulation or other entity tracking."}}
//#define OMNI_PLAYER_RIPPLES
// @option {"label":{"zh_cn":"水波凹凸细节","en_us":"Water bump detail"},"description":{"zh_cn":"在解析波上叠加多层程序噪声，增加水面细碎起伏。","en_us":"Adds multi-octave procedural noise on top of the analytic waves for fine ripples."}}
#define OMNI_WATER_BUMP 1 // [0 1]
// 反射和坐标重建读取已保存的不透明画面。
#include "/effects/reflection.glsl"
float omniWave(vec2 p, float relativeHeight) {
    float t = frameTimeCounter; // 游戏暂停时由加载器时间行为决定。
    float wave = sin(dot(p,vec2(0.65,0.3))+t*1.2)*0.06 + sin(dot(p,vec2(-0.2,0.8))-t*0.9)*0.04; // 两个交叉水波。
#ifdef OMNI_RAIN_RIPPLES
    vec2 cell = floor(p*0.7); // 每个空间格有固定雨滴位置。
    vec2 center = (cell+vec2(omniHash(cell),omniHash(cell+8.2)))/0.7; // 可重复的落点。
    float age = fract(t*0.8+omniHash(cell+1.3)); // 雨滴周期分散。
    float radius = length(p-center); // 当前点到雨滴落点距离。
    wave += rainStrength*sin(radius*22.0-age*14.0)*exp(-radius*3.0)*(1.0-age)*0.025; // 扩散环随时间衰减。
#endif
#ifdef OMNI_PLAYER_RIPPLES
    float speed = length(cameraPosition-previousCameraPosition)/max(frameTime,0.001); // 输入来自实际相机运动。
    float r = length(p-cameraPosition.xz); // 玩家附近的圆环。
    float proximity = 1.0-smoothstep(0.5,2.5,abs(relativeHeight)); // 相机和水面垂直距离超过两米半时不再互动。
    wave += proximity*min(speed,2.0)*sin(r*8.0-t*4.0)*exp(-r)*0.025; // 解析圆环同时满足水平和高度距离。
#endif
    return wave*OMNI_WAVE_STRENGTH; // 零强度消除法线变化。
}
// 水面细碎凹凸：多层程序噪声提供高频涟漪细节。
float omniWaterDetail(vec2 p) {
    float t = frameTimeCounter; // 与解析波共享时间。
    float d = omniNoise(vec3(p*0.35,t*0.6))*0.02; // 中频涟漪。
    d += omniNoise(vec3(p*1.1,t*1.1))*0.008; // 高频细节。
    d += omniNoise(vec3(p*2.4,-t*1.4))*0.004; // 极细纹理。
    return d*OMNI_WAVE_STRENGTH; // 与波强度共同缩放。
}
// 水面高度：解析波与细碎凹凸共同提供法线梯度。
float omniWaterHeight(vec2 p, float relativeHeight) {
    float height = omniWave(p,relativeHeight); // 大尺度解析波。
#if OMNI_WATER_BUMP == 1
    height += omniWaterDetail(p); // 细碎凹凸细节。
#endif
    return height;
}
vec3 omniWaterNormal(vec3 world, vec3 originalNormal) {
    vec3 worldNormal = omniNormalize(mat3(gbufferModelViewInverse)*originalNormal); // 原表面朝向由真实几何提供。
    if (OMNI_WAVE_STRENGTH<=0.0 || worldNormal.y<0.9) return originalNormal; // 瀑布侧面和底面保留原法线，零强度不造波。
    vec2 p = (world+cameraPosition).xz; // 世界锚定的波浪。
    float center = omniWaterHeight(p,world.y); // 高度中心样本使用相机相对水面高度。
    vec3 n = omniNormalize(vec3((center-omniWaterHeight(p+vec2(0.08,0),world.y))/0.08,1.0,(center-omniWaterHeight(p+vec2(0,0.08),world.y))/0.08)); // 有限差分只扰动顶面。
    return omniNormalize(mat3(gbufferModelView)*n); // 合成使用视空间法线。
}
// 调用位置：rendering/composite.glsl；示例：omniWater(color, view, waterNormal, texcoord)。
vec3 omniWater(vec3 color, vec3 view, vec3 normal, vec2 uv) {
    vec2 refracted = uv; // 无折射时保持原位置。
    float thickness = max(length(omniSceneView(uv,true))-length(view),0.0); // 不透明底面与水面的真实距离。
#ifdef OMNI_WATER_REFRACTION
    vec2 candidate = clamp(uv+normal.xy*0.018*min(thickness,3.0),vec2(0.002),vec2(0.998)); // 浅水折射较弱。
    if (length(omniSceneView(candidate,true))>length(view)+0.05) refracted = candidate; // 前景不能被错误折进水里。
#endif
    vec3 transmitted = texture(colortex3,refracted).rgb; // 不透明快照包含底面辐射。
    vec3 absorption = exp(-vec3(0.19,0.065,0.035)*min(thickness,100.0)); // 红色更快被水吸收。
    transmitted = transmitted*absorption+vec3(0.015,0.075,0.095)*(1.0-absorption); // 深水趋近水体散射颜色。
    if (OMNI_REFLECTION_STRENGTH<=0.0) return transmitted; // 水面反射与其他材质共用同一个关闭选项。
    float fresnel = 0.02+0.98*pow(1.0-max(dot(normal,omniNormalize(-view)),0.0),5.0); // 水面反射随角度提高。
    return mix(transmitted,omniReflected(view,normal,0.06),fresnel*OMNI_REFLECTION_STRENGTH); // 水的吸收与反射独立于底色透明混合。
}
#endif
