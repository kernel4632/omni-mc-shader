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

#define GFX_TWO_PI 6.28318530718 // 一个完整圆周，用于季节相位。

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
vec2 gfx_rain_wind_offset(vec3 worldPos, vec3 cameraPos, float time, vec2 wind, float disturbance, float outdoor){
	float angle = dot(worldPos + cameraPos, vec3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
	vec2 rotation = vec2(sin(angle), cos(angle)); // 摆动方向。
	vec2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
	return outdoor * offset; // 只有露天时倾斜。
}

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
float gfx_foliage(vec3 vertexColor){
	return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 乘四让普通草色接近一。
}

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
vec3 gfx_season(vec3 albedo, vec3 vertexColor, float phase, float tint, bool enabled){
	if (!enabled) return albedo; // 关闭时原样返回。
	float foliage = gfx_foliage(vertexColor); // 这一面有多像植被。
	float autumn = 0.5 - 0.5 * cos(phase * GFX_TWO_PI); // 一年过半时最接近秋天。
	vec3 seasonal = mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成。
	seasonal *= vec3(1.0 + 0.2 * tint, 1.0, 1.0 - 0.2 * tint); // 整体偏暖或偏冷。
	return albedo * mix(vec3(1.0), seasonal, foliage); // 只按植被程度生效。
}

#endif
