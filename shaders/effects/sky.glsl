// 天空：背景与屏幕外反射共用；示例 omniSky(worldDirection)。
#ifndef OMNI_SKY
#define OMNI_SKY
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label":{"zh_cn":"星空强度","en_us":"Star brightness"},"slider":true}
#define OMNI_STAR_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"天空饱和度","en_us":"Sky saturation"},"slider":true}
#define OMNI_SKY_SATURATION 1.0 // [0.5 0.75 1.0 1.25]
// 天体输入转到世界空间再比较方向。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
vec3 omniSky(vec3 direction) {
    vec3 d = omniNormalize(direction); // 天空与反射输入统一归一化。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 相机旋转不会移动太阳。
    vec3 moon = omniNormalize(mat3(gbufferModelViewInverse) * moonPosition); // 月亮使用实际加载器方向。
    float day = smoothstep(-0.15, 0.1, sun.y); // 天体高度决定昼夜。
    float horizon = pow(1.0 - max(d.y, 0.0), 4.0); // 地平线较亮。
    vec3 color = mix(vec3(0.008,0.014,0.033), mix(vec3(0.10,0.28,0.62), vec3(0.62,0.72,0.82), horizon), day);
    float sunset = (1.0 - smoothstep(0.0,0.3,abs(sun.y))) * pow(max(dot(d,sun),0.0),8.0); // 日落只出现在太阳附近。
    color += vec3(0.8,0.22,0.06) * sunset * horizon; // 暖色日出日落。
    color += vec3(12.0,9.0,5.0) * smoothstep(0.9995,0.9998,dot(d,sun)) * day; // 太阳圆盘。
    color += vec3(0.6,0.7,1.0) * smoothstep(0.9993,0.9997,dot(d,moon)) * (1.0-day); // 月亮圆盘。
    vec2 starGrid = floor(vec2(atan(d.z,d.x), asin(clamp(d.y,-1.0,1.0))) * 700.0); // 星星锁定球面方向。
    float stars = step(0.998,omniHash(starGrid)) * pow(omniHash(starGrid+3.1),3.0); // 稀疏星点。
    color += stars * OMNI_STAR_STRENGTH * (1.0-day) * smoothstep(0.0,0.2,d.y); // 白天与地平线隐藏星点。
    color = mix(color, mix(vec3(0.025),vec3(0.22,0.25,0.29),day), rainStrength * 0.85); // 晴雨连续转换。
#ifdef OMNI_NETHER
    color = omniLinear(fogColor) * (0.5 + 0.5 * horizon); // 下界天空依照加载器雾色。
#elif defined OMNI_END
    color = vec3(0.018,0.008,0.034) + vec3(0.06,0.025,0.1) * omniNoise(d * 12.0); // 末地星云。
    color += stars * 0.3 * OMNI_STAR_STRENGTH; // 末地保留稀疏星空。
#endif
    return mix(vec3(omniLuminance(color)), color, OMNI_SKY_SATURATION); // 天空单独调饱和度。
}
#endif
