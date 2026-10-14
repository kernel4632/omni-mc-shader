// 直接与环境光：地形、实体、透明物共用；示例 omniLighting(albedo, normal, world, light, props, ao)。
#ifndef OMNI_SUNLIGHT
#define OMNI_SUNLIGHT
// @effect {"label":{"zh_cn":"光照","en_us":"Lighting"}}
// @option {"label":{"zh_cn":"直接光强度","en_us":"Direct light"},"slider":true}
#define OMNI_SUNLIGHT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"环境光强度","en_us":"Ambient light"},"slider":true}
#define OMNI_AMBIENT_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"手持照明","en_us":"Held light"}}
#define OMNI_HELD_LIGHT
// @option {"label":{"zh_cn":"镜面高光","en_us":"Specular highlights"},"description":{"zh_cn":"GGX 分布与施利克菲涅耳提供直射镜面，粗糙度和金属来自材质。","en_us":"GGX distribution with Schlick Fresnel for direct specular, driven by material roughness and metal."}}
#define OMNI_SPECULAR 1 // [0 1]
// 阴影与环境输入只有共同来源。
#include "/effects/shadow.glsl"
// 云影需要云密度，主世界直射光按云层衰减。
#include "/effects/cloud.glsl"
// 镜面高光：GGX 法线分布、施利克菲涅耳与 Smith 可见性，输入来自材质的粗糙度和金属。
vec3 omniSpecular(vec3 normal, vec3 world, vec3 props, vec3 sun, float shadow) {
    vec3 n = omniNormalize(mat3(gbufferModelViewInverse)*normal); // 世界空间法线。
    vec3 l = omniNormalize(mat3(gbufferModelViewInverse)*sun); // 世界空间光方向。
    vec3 v = omniNormalize(-world); // 表面指向相机。
    vec3 h = omniNormalize(l+v); // 半程向量。
    float roughness = clamp(props.x,0.05,1.0); // 粗糙度下限避免除零。
    float a = roughness*roughness; // GGX 粗糙参数。
    float nh = max(dot(n,h),0.0); float nl = max(dot(n,l),0.0); float nv = max(dot(n,v),1e-4); // 三个夹角余弦。
    float denom = nh*nh*(a*a-1.0)+1.0; // 法线分布分母。
    float distribution = a*a/(3.14159265*denom*denom); // GGX 法线分布。
    vec3 f0 = mix(vec3(0.04),props.yyy,step(230.0/255.0,props.y)); // 介电或金属底色近似。
    vec3 fresnel = f0+(1.0-f0)*pow(1.0-max(dot(h,v),0.0),5.0); // 施利克近似。
    float k = a*0.5; // Smith 可见性参数。
    float visibility = (nv/(nv*(1.0-k)+k))*(nl/(nl*(1.0-k)+k)); // 几何可见性。
    return distribution*fresnel*visibility*nl*shadow; // 返回反射率与阴影。
}
// 调用位置：rendering/terrain.glsl和rendering/distant.glsl；示例：omniLighting(albedo, normal, world, lightUv, props, materialAo)。
vec3 omniLighting(vec3 albedo, vec3 normal, vec3 world, vec2 light, vec3 props, float materialAo) {
    vec3 sun = omniNormalize(shadowLightPosition); // 当前阴影天体可为太阳或月亮。
    float day = smoothstep(-0.15, 0.1, dot(omniNormalize(sunPosition), omniNormalize(upPosition))); // 黎明平滑过渡。
    vec3 direct = mix(vec3(0.16,0.22,0.34), vec3(1.4,1.23,1.0), day); // 日月能量分开。
    float sky = pow(clamp(light.y, 0.0, 1.0), 2.0); // 原版天空光限制洞穴中的天体照明。
    vec3 ambient = mix(vec3(0.035,0.047,0.075), vec3(0.24,0.32,0.43), day) * sky; // 原版光照提供遮挡依据。
    float block = pow(clamp(light.x, 0.0, 1.0), 3.0); // 方块光保留局部衰减。
#ifdef OMNI_HELD_LIGHT
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0; // 双手取实际较亮光源。
    block = max(block, held * max(1.0 - length(world) / 12.0, 0.0) * max(1.0 - length(world) / 12.0, 0.0)); // 无遮挡的手持近似，不声称局部阴影。
#endif
#if defined OMNI_NETHER
    ambient = vec3(0.16,0.065,0.04); // 下界无太阳，使用维度环境光。
    direct *= 0.0; // 下界不保留主世界天体照明。
#elif defined OMNI_END
    ambient = vec3(0.13,0.09,0.18); // 末地冷紫环境光。
    direct *= 0.0; // 末地不使用主世界日月。
#endif
    float shadow = 1.0; // 其他维度或关闭阴影时直接光不被遮挡。
#if !defined OMNI_NETHER && !defined OMNI_END
    shadow = omniShadow(world, normal); // 主世界直接光和阴影共同控制亮面。
#endif
    float diffuse = max(dot(normal, sun), 0.0) * shadow; // 没有直接光的维度不读取阴影图。
    float cloudShade = 1.0; // 没有云影时直射光不变。
#if OMNI_CLOUD_SHADOW == 1 && !defined OMNI_NETHER && !defined OMNI_END
    cloudShade = omniCloudShadow(world); // 云影同时衰减漫反射与镜面。
#endif
    vec3 lightColor = (ambient * materialAo + vec3(0.012)) * OMNI_AMBIENT_STRENGTH + vec3(1.15,0.55,0.20) * block; // 材质遮蔽只压低环境光，不削弱直接光。
    lightColor += direct * diffuse * sky * (1.0 - rainStrength * 0.65) * OMNI_SUNLIGHT_STRENGTH * cloudShade; // 漫反射。
#if OMNI_SPECULAR == 1
    lightColor += omniSpecular(normal,world,props,sun,shadow) * direct * sky * (1.0 - rainStrength * 0.65) * OMNI_SUNLIGHT_STRENGTH * cloudShade; // 直射镜面高光。
#endif
    lightColor = mix(lightColor, max(lightColor, vec3(0.65)), nightVision); // 保留夜视能力。
    return albedo * lightColor + albedo * props.z * 4.0; // 自发光不被材质遮蔽乘暗。
}
#endif
