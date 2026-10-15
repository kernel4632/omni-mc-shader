/*
天气：控制雨雪颗粒的显隐与斜度、水面雨点落点密度，并把降雨强度转成画面整体明暗。

调用位置：
  rendering/terrain.glsl 的 omniReadSurface：雨雪几何（`OMNI_WEATHER`）在这里读取可见度与斜度；
  effects/water.glsl 的 omniWave：雨点落点密度在这里读取；
  rendering/composite.glsl 的主流程：对已经合成好的颜色调用 omniWeather。
可复制示例：`s.base.rgb *= omniWeatherVisibility(s.world);` 与 `color = omniWeather(color);`

设计原因与取舍：雨雪颗粒的总显隐只能靠整体缩放颜色做，读不到真实降水类型，所以用温度估计在
雨的可见度与雪的可见度之间选择；这是近似，不改变颗粒形状本身。
*/
#ifndef OMNI_WEATHER
#define OMNI_WEATHER
// @effect {"label":{"zh_cn":"天气","en_us":"Weather"}}
// @option {"label":{"zh_cn":"雨的可见度","en_us":"Rain visibility"},"description":{"zh_cn":"雨丝多明显；取零等于关掉雨丝。","en_us":"How visible the rain streaks are; zero removes them."},"slider":true}
#define OMNI_RAIN_VISIBILITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雪的可见度","en_us":"Snow visibility"},"description":{"zh_cn":"雪花多明显；取零等于关掉雪花。","en_us":"How visible the snow is; zero removes it."},"slider":true}
#define OMNI_SNOW_VISIBILITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨的斜度","en_us":"Rain slant"},"description":{"zh_cn":"正值雨丝往右斜、负值往左斜。","en_us":"Positive leans rain to the right, negative to the left."},"slider":true}
#define OMNI_RAIN_WIND 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"落点密度","en_us":"Ripple density"},"description":{"zh_cn":"雨点砸在水面上多密；取零等于没有雨点圈。","en_us":"How dense the rain ripples on water are; zero removes them."},"slider":true}
#define OMNI_RAIN_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨天变暗","en_us":"Rain darkening"},"description":{"zh_cn":"下雨时画面整体压暗多少；取零完全不变。","en_us":"How much the scene darkens while it rains; zero keeps it unchanged."},"slider":true}
#define OMNI_RAIN_DARKEN 0.0 // [0.0 0.25 0.5 0.75 1.0]
// 噪声与相机位置来自共用模块与统一输入。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
// 雨点落点的空间频率：密度越高，格子越细，同样面积上的落点越多。
float omniRippleGrid() {
    return 0.7 * max(OMNI_RAIN_DENSITY, 0.05); // 取零附近时限制下限，避免格子无限大导致取整溢出。
}
// 雨还是雪：用高度和一片空间噪声粗略估计冷暖，冷处判为雪、暖处判为雨。
// 为什么不读真实降水类型：加载器不给雨雪区分，只能用位置估计，属于近似。
float omniSnowFactor(vec3 world) {
    vec3 p = world + cameraPosition; // 相机相对坐标加上相机位置才是稳定的绝对坐标。
    float altitude = (p.y - 64.0) / 256.0; // 越高越冷。
    float temperature = clamp(0.5 + (omniNoise(p * 0.01) - 0.5) * 0.8 - altitude, 0.0, 1.0); // 与气候同一口径的粗略温度。
    return 1.0 - smoothstep(0.25, 0.35, temperature); // 温度不高于零点二五判为雪，不低于零点三五判为雨。
}
// 颗粒可见度：冷的雨雪几何用雪的可见度，其余用雨的可见度。
float omniWeatherVisibility(vec3 world) {
    return mix(OMNI_RAIN_VISIBILITY, OMNI_SNOW_VISIBILITY, omniSnowFactor(world));
}
// 雨天整体变暗：按降雨强度乘一个不超过一的系数。
vec3 omniWeather(vec3 color) {
    return color * (1.0 - rainStrength * OMNI_RAIN_DARKEN); // 取零或没下雨时完全不变。
}
#endif
