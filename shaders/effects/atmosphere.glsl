// 氛围：在天空颜色上叠加极光、彩虹和解析大气散射，并提供全场闪电照明。
// 调用位置：rendering/lighting.glsl 绘制自定义天空时调用 `omniAtmosphere`；
//           rendering/composite.glsl 合成阶段对有真实深度与天空光的表面调用 `omniLightning`。
// 可复制示例：`color = omniAtmosphere(skyColor, worldDirection);` 先在天空上叠加氛围；
//             `color = omniLightning(color, worldPosition, skylight);` 再按真实闪电照明。
// 设计取舍：极光、彩虹、散射各自独立成一个函数并各自带开关，关闭的效果连采样都不生成；
//           闪电只在加载器给出真实事件时叠加，缺少输入就原样返回，不凭空制造天气事件。
#ifndef OMNI_ATMOSPHERE
#define OMNI_ATMOSPHERE
// @effect {"label":{"zh_cn":"氛围","en_us":"Atmosphere"}}
// @option {"label":{"zh_cn":"极光","en_us":"Aurora"}}
//#define OMNI_AURORA
// @option {"label":{"zh_cn":"彩虹","en_us":"Rainbow"}}
//#define OMNI_RAINBOW
// @option {"label":{"zh_cn":"闪电照明","en_us":"Lightning illumination"},"description":{"zh_cn":"读取加载器实际闪电强度；没有该输入时关闭，不生成虚假天气事件。","en_us":"Uses Iris lightning strength; disabled without the actual event input."},"page":"weather"}
#define OMNI_LIGHTNING
// @option {"label":{"zh_cn":"解析大气散射","en_us":"Analytic atmosphere"},"description":{"zh_cn":"用解析单次散射近似天空，不引入外部查找表纹理。","en_us":"Approximates the sky with analytic single scattering, no external lookup table."}}
#define OMNI_ATMOSPHERE_SCATTER 1 // [0 1]
// @option {"label":{"zh_cn":"极光强度","en_us":"Aurora strength"},"slider":true}
#define OMNI_AURORA_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"极光颜色","en_us":"Aurora colour"},"description":{"zh_cn":"正值偏绿、负值偏蓝紫。","en_us":"Positive leans green, negative leans blue-purple."},"slider":true}
#define OMNI_AURORA_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"彩虹强度","en_us":"Rainbow strength"},"slider":true}
#define OMNI_RAINBOW_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"散射强度","en_us":"Scatter strength"},"slider":true}
#define OMNI_SCATTER_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"闪电强度","en_us":"Lightning strength"},"slider":true,"page":"weather"}
#define OMNI_LIGHTNING_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// 共用颜色与天气输入：天空色、云与太阳方向都来自这里的定义。
#include "/effects/sky.glsl"
#ifdef IS_IRIS
uniform vec4 lightningBoltPosition; // 闪电的相机相对世界位置与强度。
#endif
// 解析大气散射：把天空当成一层空气，用单次散射近似它的颜色。
// 为什么不用查找表：外部纹理要额外的文件和采样，解析式只靠太阳方向就能出效果，基础路径更轻。
// 瑞利散射偏蓝、米氏散射偏暖，都随视角和太阳高度变化。
vec3 omniAirScattering(vec3 direction) {
    vec3 ray = omniNormalize(direction); // 视线方向；零向量交给安全归一化处理。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 转到世界空间的太阳方向。
    float mu = dot(ray,sun); // 视线与太阳夹角的余弦，正对太阳时为 1。
    float thickness = exp(-max(ray.y,0.0)*5.0); // 越贴近地平线，视线穿过的空气越厚。
    float daylight = smoothstep(-0.15,0.15,sun.y); // 太阳落到地平线以下就归零。
    vec3 rayleigh = vec3(0.0058,0.0135,0.0331)*(1.0+mu*mu)*thickness*daylight; // 瑞利散射偏蓝，随夹角变化。
    vec3 mie = vec3(1.0,0.9,0.75)*pow(max(mu,0.0),8.0)*thickness*daylight*0.15; // 前向米氏光晕偏暖白。
    return (rayleigh+mie)*0.5*OMNI_SCATTER_STRENGTH; // 半强度叠加，与现有天空量级匹配；散射强度可调。
}
// 极光：主世界夜晚高空的缓慢帘幕，雨天被云遮挡。
vec3 omniAurora(vec3 color, vec3 direction) {
#ifdef OMNI_AURORA
    float night = 1.0-smoothstep(-0.2,0.1,omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y); // 太阳越低夜色越浓，极光越亮。
    float curtain = pow(max(0.0,sin(direction.x*18.0+omniNoise(direction*8.0+frameTimeCounter*0.02)*6.0)),8.0); // 帘幕随位置起伏、随时间缓慢移动。
    vec3 auroraColor = mix(vec3(0.12,0.16,0.50),vec3(0.08,0.35,0.20),0.5+0.5*OMNI_AURORA_TINT); // 极光颜色：正值偏绿、负值偏蓝紫，取零为中间绿。
    color += auroraColor*curtain*smoothstep(0.1,0.5,direction.y)*(1.0-rainStrength)*night*OMNI_AURORA_STRENGTH; // 帘幕只露在高空，雨云之下熄灭；颜色与强度可调。
#endif
    return color; // 关闭时不改动颜色。
}
// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
vec3 omniRainbow(vec3 color, vec3 direction) {
#ifdef OMNI_RAINBOW
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 转到世界空间的太阳方向。
    float angle = acos(clamp(dot(direction,-sun),-1.0,1.0)); // 与背太阳方向的夹角，先钳住取值范围。
    float offset = (angle-0.733)/0.018; // 相对约四十二度彩虹角的偏移，单位是弧度。
    float band = exp(-offset*offset); // 窄带：只用乘法构成，避开对负数取幂的未定义结果。
    vec3 spectrum = 0.5+0.5*cos((angle-0.72)*120.0+vec3(0,2.1,4.2)); // 角度到红橙黄绿的彩色谱。
    color += spectrum*band*wetness*(1.0-rainStrength)*smoothstep(0.0,0.1,direction.y)*OMNI_RAINBOW_STRENGTH; // 只在雨停后仍湿润时出现；强度可调。
#endif
    return color; // 关闭时不改动颜色。
}
// 天空氛围：主世界按选项叠加极光、彩虹与散射，关闭的效果不生成计算。
// 为什么下界与末地不加：它们的天空已由天空色和雾接管，不需要太阳散射。
vec3 omniAtmosphere(vec3 color, vec3 direction) {
#if !defined OMNI_NETHER && !defined OMNI_END
    color = omniAurora(color,direction); // 叠加夜晚极光帘幕。
    color = omniRainbow(color,direction); // 叠加雨后彩虹。
#if OMNI_ATMOSPHERE_SCATTER == 1
    color += omniAirScattering(direction); // 解析单次散射近似天空。
#endif
#endif
    return color; // 关闭的效果不产生任何采样。
}
// 闪电照明：加载器给出真实闪电事件时，按到闪电的距离照亮附近表面。
// 天空可见度抑制洞穴闪光，避免不透光的洞里也发亮。
vec3 omniLightning(vec3 color, vec3 world, float skylight) {
#if defined OMNI_LIGHTNING && defined IS_IRIS
    float intensity = lightningBoltPosition.w; // 强度来自实际闪电事件，没有事件时为零。
    float boltDistance = length(world-lightningBoltPosition.xyz); // 表面到闪电的距离，越近越亮。
    color += vec3(0.55,0.65,0.9)*intensity*skylight/(1.0+boltDistance*0.01)*OMNI_LIGHTNING_STRENGTH; // 冷白色闪光，距离越远越弱；强度可调。
#endif
    return color; // 没有真实闪电输入时原样返回。
}
#endif
