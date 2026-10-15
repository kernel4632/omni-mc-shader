// 氛围：在天空颜色上叠加极光、彩虹和解析大气散射，并提供全场闪电照明。
// 调用位置：rendering/lighting.glsl 绘制自定义天空时调用 omniAtmosphere；
//           rendering/composite.glsl 合成阶段对有真实深度与天空光的表面调用 omniLightning。
// 可复制示例：`color = omniAtmosphere(skyColor, worldDirection);` 与 `color = omniLightning(color, worldPosition, skylight);`
#ifndef OMNI_ATMOSPHERE // 背景与场景共用天气事件定义。
#define OMNI_ATMOSPHERE
// @effect {"label":{"zh_cn":"氛围","en_us":"Atmosphere"}}
// @option {"label":{"zh_cn":"极光","en_us":"Aurora"}}
//#define OMNI_AURORA
// @option {"label":{"zh_cn":"彩虹","en_us":"Rainbow"}}
//#define OMNI_RAINBOW
// @option {"label":{"zh_cn":"闪电照明","en_us":"Lightning illumination"},"description":{"zh_cn":"读取加载器实际闪电强度；没有该输入时关闭，不生成虚假天气事件。","en_us":"Uses Iris lightning strength; disabled without the actual event input."}}
#define OMNI_LIGHTNING
// @option {"label":{"zh_cn":"解析大气散射","en_us":"Analytic atmosphere"},"description":{"zh_cn":"用解析单次散射近似天空，不引入外部查找表纹理。","en_us":"Approximates the sky with analytic single scattering, no external lookup table."}}
#define OMNI_ATMOSPHERE_SCATTER 1 // [0 1]
// 共用颜色与天气。
#include "/effects/sky.glsl"
#ifdef IS_IRIS
uniform vec4 lightningBoltPosition; // 相机相对世界位置与闪电强度。
#endif
// 解析大气散射：瑞利加米氏单次散射近似，无外部纹理依赖，太阳低于地平线时回退为零贡献。
vec3 omniAirScattering(vec3 direction) {
    vec3 d = omniNormalize(direction); // 视线方向，零向量也退化到安全值。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 世界空间太阳方向。
    float mu = dot(d,sun); // 视线与太阳夹角余弦。
    float thickness = exp(-max(d.y,0.0)*5.0); // 越接近地平线空气越厚。
    float daylight = smoothstep(-0.15,0.15,sun.y); // 太阳高度控制昼光，落山后归零。
    vec3 rayleigh = vec3(0.0058,0.0135,0.0331)*(1.0+mu*mu)*thickness*daylight; // 瑞利相函数近似。
    vec3 mie = vec3(1.0,0.9,0.75)*pow(max(mu,0.0),8.0)*thickness*daylight*0.15; // 前向米氏光晕。
    return (rayleigh+mie)*0.5; // 与现有天空量级匹配。
}
// 天空氛围：按选项叠加极光、彩虹与散射，任一效果关闭时对应计算与采样不引入。
vec3 omniAtmosphere(vec3 color, vec3 direction) {
#if !defined OMNI_NETHER && !defined OMNI_END
#ifdef OMNI_AURORA
    float night = 1.0-smoothstep(-0.2,0.1,omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y); // 只在夜晚发光。
    float curtain = pow(max(0.0,sin(direction.x*18.0+omniNoise(direction*8.0+frameTimeCounter*0.02)*6.0)),8.0); // 空间帘幕缓慢移动。
    color += vec3(0.08,0.35,0.20)*curtain*smoothstep(0.1,0.5,direction.y)*(1.0-rainStrength)*night; // 极光受雨云遮蔽。
#endif
#ifdef OMNI_RAINBOW
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 彩虹位于背太阳方向。
    float angle = acos(clamp(dot(direction,-sun),-1.0,1.0)); // 视线与背太阳方向的夹角，钳制后不产生非法值。
    float offset = (angle-0.733)/0.018; // 相对四十二度彩虹角的偏移。
    float band = exp(-offset*offset); // 窄带；用乘法取代负底数的幂，避免未定义结果。
    vec3 spectrum = 0.5+0.5*cos((angle-0.72)*120.0+vec3(0,2.1,4.2)); // 彩色谱带。
    color += spectrum*band*wetness*(1.0-rainStrength)*smoothstep(0.0,0.1,direction.y); // 雨后晴天才显示。
#endif
#if OMNI_ATMOSPHERE_SCATTER == 1
    color += omniAirScattering(direction); // 解析单次散射近似天空。
#endif
#endif
    return color; // 独立关闭不引入采样。
}
// 闪电照明：只有加载器提供真实事件且表面在世界内可见时才被照亮，否则原样返回。
vec3 omniLightning(vec3 color, vec3 world, float skylight) {
#if defined OMNI_LIGHTNING && defined IS_IRIS
    float intensity = lightningBoltPosition.w; // 强度来自实际闪电事件。
    float distance = length(world-lightningBoltPosition.xyz); // 近处增强照明。
    color += vec3(0.55,0.65,0.9)*intensity*skylight/(1.0+distance*0.01); // 天空可见性抑制洞穴闪光。
#endif
    return color; // 基础路径不依赖专有闪电输入。
}
#endif
