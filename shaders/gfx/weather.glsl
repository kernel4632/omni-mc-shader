/*
通用图形库天气模块：雨雪在风中的倾斜偏移。
调用位置：任何需要让雨雪随风摆动的程序；本仓库由 `effects/weather/weather.glsl` 转发调用。
可复制示例：
    vec2 o = gfx_rain_wind_offset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 返回水平偏移。
设计原因与取舍：
    位置、时间、风向、扰动和露天系数全部由调用方传入，库不读取相机或天气全局量。
    倾斜随高度放大，露天系数为零时雨雪保持竖直。
*/
#ifndef GFX_WEATHER_INCLUDED
#define GFX_WEATHER_INCLUDED

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
vec2 gfx_rain_wind_offset(vec3 worldPos, vec3 cameraPos, float time, vec2 wind, float disturbance, float outdoor){
	float angle = dot(worldPos + cameraPos, vec3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
	vec2 rotation = vec2(sin(angle), cos(angle)); // 摆动方向。
	vec2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
	return outdoor * offset; // 只有露天时倾斜。
}

#endif
