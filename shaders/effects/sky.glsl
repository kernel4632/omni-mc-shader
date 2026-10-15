// 天空：主世界昼夜天空、星点与下界末地氛围色，供背景画面和屏幕外反射共用。
// 调用位置：由 effects/fog.glsl 与 effects/reflection.glsl 调用，并经 atmosphere.glsl、cloud.glsl 汇入 rendering/lighting.glsl 的背景绘制。
// 可复制示例：`vec3 sky = omniSky(worldDirection); vec3 reflected = omniSky(mat3(gbufferModelViewInverse) * ray);`
#ifndef OMNI_SKY
#define OMNI_SKY
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label":{"zh_cn":"星空强度","en_us":"Star brightness"},"slider":true}
#define OMNI_STAR_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"天空饱和度","en_us":"Sky saturation"},"slider":true}
#define OMNI_SKY_SATURATION 1.0 // [0.5 0.75 1.0 1.25]
// @option {"label":{"zh_cn":"下界氛围色","en_us":"Nether palette"},"description":{"zh_cn":"用程序化混合替代固定下界雾色，覆盖荒原、灵魂沙谷、绯红与诡异森林和玄武岩。","en_us":"Replaces a fixed nether fog colour with a procedural blend of nether biomes."}}
#define OMNI_NETHER_COLOR 1 // [0 1]
// 天体输入转到世界空间再比较方向。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
// 下界颜色：按方向噪声混合多种下界氛围，不使用固定加载器雾色。
vec3 omniNetherColor(vec3 direction, float horizon) {
    vec3 d = omniNormalize(direction); // 统一方向。
    float region = omniNoise(d*3.0); // 空间变化区分氛围片区。
    vec3 tone = mix(vec3(0.99,0.34,0.10),vec3(0.60,0.77,1.00),smoothstep(0.20,0.40,region)); // 荒原暖橙到灵魂沙谷冷蓝。
    tone = mix(tone,vec3(1.00,0.55,0.35),smoothstep(0.40,0.55,region)); // 绯红森林红橙。
    tone = mix(tone,vec3(0.50,0.85,0.90),smoothstep(0.55,0.70,region)); // 诡异森林青蓝。
    tone = mix(tone,vec3(0.70,0.66,0.62),smoothstep(0.70,0.85,region)); // 玄武岩灰。
    tone *= mix(1.0,0.6,horizon); // 地平线以下更暗。
    return tone*(0.5+0.5*horizon)*0.5; // 与加载器雾色同量级。
}
vec3 omniSky(vec3 direction) {
    vec3 d = omniNormalize(direction); // 天空与反射输入统一归一化。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 相机旋转不会移动太阳。
    vec3 moon = omniNormalize(mat3(gbufferModelViewInverse) * moonPosition); // 月亮使用实际加载器方向。
    float day = smoothstep(-0.15, 0.1, sun.y); // 天体高度决定昼夜。
    float horizon = pow(1.0 - max(d.y, 0.0), 4.0); // 地平线较亮。
    vec3 nightSky = vec3(0.008,0.014,0.033); // 夜空底色。
    vec3 daySky = mix(vec3(0.10,0.28,0.62), vec3(0.62,0.72,0.82), horizon); // 高天偏蓝，地平线泛白。
    vec3 color = mix(nightSky, daySky, day); // 昼夜连续过渡。
    float sunset = (1.0 - smoothstep(0.0,0.3,abs(sun.y))) * pow(max(dot(d,sun),0.0),8.0); // 日落只出现在太阳附近。
    color += vec3(0.8,0.22,0.06) * sunset * horizon; // 暖色日出日落。
    color += vec3(12.0,9.0,5.0) * smoothstep(0.9995,0.9998,dot(d,sun)) * day; // 太阳圆盘。
    color += vec3(0.6,0.7,1.0) * smoothstep(0.9993,0.9997,dot(d,moon)) * (1.0-day); // 月亮圆盘。
    float azimuth = (d.x == 0.0 && d.z == 0.0) ? 0.0 : atan(d.z, d.x); // 极点处方位角无定义，退化时取零避免 NaN 传播。
    vec2 starGrid = floor(vec2(azimuth, asin(clamp(d.y,-1.0,1.0))) * 700.0); // 星星锁定球面方向。
    float stars = step(0.998,omniHash(starGrid)) * pow(omniHash(starGrid+3.1),3.0); // 稀疏星点。
    color += stars * OMNI_STAR_STRENGTH * (1.0-day) * smoothstep(0.0,0.2,d.y); // 白天与地平线隐藏星点。
    color = mix(color, mix(vec3(0.025),vec3(0.22,0.25,0.29),day), rainStrength * 0.85); // 晴雨连续转换。
#ifdef OMNI_NETHER
#if OMNI_NETHER_COLOR == 1
    color = omniNetherColor(d,horizon); // 程序化下界氛围色。
#else
    color = omniLinear(fogColor) * (0.5 + 0.5 * horizon); // 下界天空依照加载器雾色。
#endif
#elif defined OMNI_END
    color = vec3(0.018,0.008,0.034) + vec3(0.06,0.025,0.1) * omniNoise(d * 12.0); // 末地星云。
    color += stars * 0.3 * OMNI_STAR_STRENGTH; // 末地保留稀疏星空。
#endif
    return mix(vec3(omniLuminance(color)), color, OMNI_SKY_SATURATION); // 天空单独调饱和度。
}
#endif
