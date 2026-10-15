/*
季节：让草和树叶的颜色随游戏里的天数缓慢变化，做出春夏秋冬的观感。

调用位置：rendering/terrain.glsl 的 omniShadeSurface，在线性底色之后、光照之前调用。
可复制示例：`albedo = omniSeason(albedo, materialId);`

设计原因与取舍：只在草与树叶这类会随季节变色的方块上改底色，其余方块完全不动；
颜色变化来自世界天数，不读取生物群系，所以任何世界里都能用，但强度有限。
*/
#ifndef OMNI_SEASON
#define OMNI_SEASON
// @effect {"label":{"zh_cn":"季节","en_us":"Seasons"}}
// @option {"label":{"zh_cn":"季节开关","en_us":"Seasons"},"description":{"zh_cn":"草和树叶的颜色随游戏天数缓慢变化。","en_us":"Grass and leaf colour shifts with the in-game day count."}}
//#define OMNI_SEASONS
// @option {"label":{"zh_cn":"季节颜色","en_us":"Season colour"},"description":{"zh_cn":"正值偏暖偏秋黄、负值偏冷偏绿。","en_us":"Positive leans warm autumn-yellow, negative leans cool green."},"slider":true}
#define OMNI_SEASON_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// 归一化、少数值计算与时间输入来自统一模块。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
// 季节上色：只给树叶(10001)与草(10002)按一年的相位混入秋色，再按选项整体偏暖或偏冷。
vec3 omniSeason(vec3 albedo, float materialId) {
#ifdef OMNI_SEASONS
    if (materialId == 10001.0 || materialId == 10002.0) { // 只有树叶和草随季节变色。
        float phase = fract(float(worldDay) / 24.0); // 一年按二十四个游戏日循环，天数是加载器给的真实计数。
        float autumn = 0.5 - 0.5 * cos(phase * 6.283185); // 在零到一之间缓慢摆动，接近秋分时最大。
        albedo *= mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成，保留原本的绿。
        albedo *= vec3(1.0 + 0.2 * OMNI_SEASON_TINT, 1.0, 1.0 - 0.2 * OMNI_SEASON_TINT); // 季节颜色整体偏暖或偏冷。
    }
#endif
    return albedo; // 关闭季节或非草木方块时原样返回。
}
#endif
