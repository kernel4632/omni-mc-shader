// 直接与环境光：地形、实体、透明物共用；示例 omniLighting(albedo, normal, world, light, emission, ao)。
#ifndef OMNI_SUNLIGHT
#define OMNI_SUNLIGHT
// @effect {"label":{"zh_cn":"光照","en_us":"Lighting"}}
// @option {"label":{"zh_cn":"直接光强度","en_us":"Direct light"},"slider":true}
#define OMNI_SUNLIGHT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"环境光强度","en_us":"Ambient light"},"slider":true}
#define OMNI_AMBIENT_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"手持照明","en_us":"Held light"}}
#define OMNI_HELD_LIGHT
// 阴影与环境输入只有共同来源。
#include "/effects/shadow.glsl"
// 云影需要云密度，主世界直射光按云层衰减。
#include "/effects/cloud.glsl"
// 调用位置：rendering/terrain.glsl和rendering/distant.glsl；示例：omniLighting(albedo, normal, world, lightUv, emission, materialAo)。
vec3 omniLighting(vec3 albedo, vec3 normal, vec3 world, vec2 light, float emission, float materialAo) {
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
    float diffuse = max(dot(normal, sun), 0.0); // 没有直接光的维度不读取阴影图。
#if !defined OMNI_NETHER && !defined OMNI_END
    diffuse *= omniShadow(world, normal); // 主世界直接光和阴影共同控制亮面。
#endif
    vec3 lightColor = (ambient * materialAo + vec3(0.012)) * OMNI_AMBIENT_STRENGTH + vec3(1.15,0.55,0.20) * block; // 材质遮蔽只压低环境光，不削弱直接光。
#if OMNI_CLOUD_SHADOW == 1 && !defined OMNI_NETHER && !defined OMNI_END
    lightColor += direct * diffuse * sky * (1.0 - rainStrength * 0.65) * OMNI_SUNLIGHT_STRENGTH * omniCloudShadow(world); // 云影只遮挡主世界直射光。
#else
    lightColor += direct * diffuse * sky * (1.0 - rainStrength * 0.65) * OMNI_SUNLIGHT_STRENGTH; // 雨天削弱直射光。
#endif
    lightColor = mix(lightColor, max(lightColor, vec3(0.65)), nightVision); // 保留夜视能力。
    return albedo * lightColor + albedo * emission * 4.0; // 自发光不被材质遮蔽乘暗。
}
#endif
