/*
天气：把降雨强度转成画面整体明暗，给天空、地形和雾一个统一的雨天压暗入口。

调用位置：rendering/composite.glsl 的主流程末尾，对已经合成好的颜色调用 omniWeather。
可复制示例：`color = omniWeather(color);`

设计原因与取舍：雨天变暗只做一次整体乘算，简单、任何场景都不会出错；
代价是它不改变雨雪颗粒本身的形状，粒子的强弱仍由加载器和资源包决定。
*/
#ifndef OMNI_WEATHER
#define OMNI_WEATHER
// @effect {"label":{"zh_cn":"天气","en_us":"Weather"}}
// @option {"label":{"zh_cn":"雨天变暗","en_us":"Rain darkening"},"description":{"zh_cn":"下雨时画面整体压暗多少；取零完全不变。","en_us":"How much the scene darkens while it rains; zero keeps it unchanged."},"slider":true}
#define OMNI_RAIN_DARKEN 0.0 // [0.0 0.25 0.5 0.75 1.0]
// 降雨强度来自统一输入。
#include "/common/uniforms.glsl"
// 雨天整体变暗：按降雨强度乘一个不超过一的系数。
vec3 omniWeather(vec3 color) {
    return color * (1.0 - rainStrength * OMNI_RAIN_DARKEN); // 取零或没下雨时完全不变。
}
#endif
