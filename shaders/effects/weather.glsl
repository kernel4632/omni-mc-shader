/*
天气：控制雨雪颗粒的显隐与斜度、水面雨点落点密度，并把降雨强度转成画面整体明暗。

调用位置：
  rendering/terrain.glsl 顶点阶段：雨雪几何（`OMNI_WEATHER_PASS`）调用 omniRainSlant 让雨丝倾斜；
  rendering/terrain.glsl 片元阶段：雨雪几何调用 omniWeatherVisibility 缩放颗粒透明度；
  effects/water.glsl 的 omniWave：调用 omniRippleGrid 读取雨点落点密度；
  rendering/composite.glsl 主流程：对已经合成好的颜色调用 omniWeather。
可复制示例：`world = omniRainSlant(world);`、`s.base.a *= omniWeatherVisibility();`、`color = omniWeather(color);`

设计原因与取舍：
  雨还是雪：读 Iris 给的 `biome_precipitation`（玩家所在生物群系的降水类型），不靠位置去猜；
  它描述的是玩家脚下的群系，远处跨群系的颗粒会沿用同一个值。
  可见度：缩放颗粒的透明度而不是颜色，取零时颗粒完全透明，不会变成黑条。
  斜度：在顶点阶段按高度水平推移整片雨雪几何，雨丝整体倾斜且不随时间漂移；只沿世界东西方向倾斜。
  防重复引入标记用 `_INCLUDED` 结尾，避免和绘制程序宏或选项同名而让整段代码被跳过。
*/
#ifndef OMNI_WEATHER_INCLUDED
#define OMNI_WEATHER_INCLUDED
// @effect {"label":{"zh_cn":"天气","en_us":"Weather"}}
// @option {"label":{"zh_cn":"雨的可见度","en_us":"Rain visibility"},"description":{"zh_cn":"雨丝多明显；取零等于关掉雨丝。","en_us":"How visible the rain streaks are; zero removes them."},"slider":true}
#define OMNI_RAIN_VISIBILITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雪的可见度","en_us":"Snow visibility"},"description":{"zh_cn":"雪花多明显；取零等于关掉雪花。","en_us":"How visible the snow is; zero removes it."},"slider":true}
#define OMNI_SNOW_VISIBILITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨的斜度","en_us":"Rain slant"},"description":{"zh_cn":"正值雨丝往东斜、负值往西斜，取零竖直下落。","en_us":"Positive leans rain towards east, negative towards west, zero falls straight."},"slider":true}
#define OMNI_RAIN_WIND 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"落点密度","en_us":"Ripple density"},"description":{"zh_cn":"雨点砸在水面上多密；取零等于没有雨点圈。","en_us":"How dense the rain ripples on water are; zero removes them."},"slider":true}
#define OMNI_RAIN_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨滴溅射强度","en_us":"Rain splash strength"},"description":{"zh_cn":"雨点砸在水面上溅起的圈有多明显；取零等于关掉雨点圈，但保留落点密度选项。","en_us":"How strong the splash rings from raindrops are; zero removes the rings while keeping the density option."},"slider":true}
#define OMNI_RAIN_SPLASH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"地表湿润响应","en_us":"Surface wetness response"},"description":{"zh_cn":"下雨时地面变湿的快慢与深浅；取零时地面不因下雨变湿。","en_us":"How quickly and deeply surfaces get wet in rain; zero leaves surfaces dry."},"slider":true}
#define OMNI_RAIN_WET_RESPONSE 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨天变暗","en_us":"Rain darkening"},"description":{"zh_cn":"下雨时画面整体压暗多少；取零完全不变。","en_us":"How much the scene darkens while it rains; zero keeps it unchanged."},"slider":true}
#define OMNI_RAIN_DARKEN 0.0 // [0.0 0.25 0.5 0.75 1.0]
// 降雨强度来自统一输入。
#include "/common/uniforms.glsl"
uniform int biome_precipitation; // Iris 给的玩家所在群系降水类型：零无、一雨、二雪；缺少该输入时为零，按雨处理。
// 雨点落点的空间频率：密度越高，格子越细，同样面积上的落点越多；取零时由调用方跳过雨点。
float omniRippleGrid() {
    return 0.7 * OMNI_RAIN_DENSITY; // 密度一时约一点四米一格，与原有手感一致。
}
// 雨滴溅射强度：乘在水面雨点圈的振幅上，单独控制圈多明显；取零仍保留落点密度，等价于关掉圈。
float omniRainSplash() {
    return max(OMNI_RAIN_SPLASH,0.0); // 越界配置收敛到非负，负值不会把圈翻成凹陷。
}
// 地表湿润响应：乘在加载器给的湿润度上，单独控制雨天地面变湿的快慢与深浅。
float omniRainWetResponse() {
    return max(OMNI_RAIN_WET_RESPONSE,0.0); // 越界配置收敛到非负，负值不会产生负的湿润量。
}
// 颗粒可见度：群系下雪用雪的可见度，其余用雨的可见度。
float omniWeatherVisibility() {
    return biome_precipitation == 2 ? OMNI_SNOW_VISIBILITY : OMNI_RAIN_VISIBILITY;
}
// 雨丝斜度：相机相对世界坐标里，越高的顶点向东推得越远，整片雨雪几何变成斜的平行四边形。
// 系数零点五：斜度取一时约二十七度，既看得出风向，又不会斜到贴图拉伸明显。
vec3 omniRainSlant(vec3 world) {
    world.x += world.y * OMNI_RAIN_WIND * 0.5; // 按高度水平推移，雨丝方向随之倾斜。
    return world;
}
// 雨天整体变暗：按降雨强度乘一个不超过一的系数；再乘头顶能看到的天空比例，洞穴和室内不跟着变暗。
vec3 omniWeather(vec3 color) {
    float exposed = float(eyeBrightnessSmooth.y) / 240.0; // 眼部天空光等级换算到零到一，地下接近零。
    return color * (1.0 - rainStrength * OMNI_RAIN_DARKEN * exposed); // 取零、没下雨或在地下时完全不变。
}
#endif
