/*
通用图形库天气模块：雨雪随风偏移、季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：任何需要天气形状的程序；本仓库由 `effects/weather/weather.glsl`、`season.glsl`、
    `storm.glsl` 与 `dailyweather.glsl` 转发调用。
可复制示例：
    vec2 o = gfx_rain_wind_offset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 返回水平偏移。
    float n = gfx_storm_noise(worldPos, noiseTexture, 512.0); // 暴风雾团密度。
    float h = gfx_weather_hash11(day); // 每日天气的随机取档。
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

// 暴风噪声：把世界坐标折进噪声贴图，得到随风滚动的雾团密度。
// `noiseResolution` 是噪声贴图边长，调用方传入可以换用别的贴图而不改公式。
float gfx_storm_noise(vec3 position, sampler2D noiseTexture, float noiseResolution){
	position /= 18.0; // 噪声格子的基准边长。
	position.xz *= 0.5; // 横向再缩一半，让雾团更扁更长，像被风拉过。
	vec3 cell = floor(position); // 所在整数格，决定用噪声贴图的哪一块。
	vec3 fraction = fract(position); // 格内小数偏移，用来做插值。
	fraction = fraction * fraction * (3.0 - 2.0 * fraction); // 三次平滑，插值不出现方块边界。
	vec2 uv = cell.xz + fraction.xz + cell.y * vec2(0.0, 193.0); // 三维格子映射到二维噪声坐标，纵轴加大偏移错开层。
	vec2 sample2 = texture(noiseTexture, uv / noiseResolution).yx; // 读噪声贴图并取两个通道，渠道顺序照原程序。
	return mix(sample2.r, sample2.g, fraction.y); // 沿高度在两通道之间插值，得到零到一的密度。
}

// 暴风颜色：按雪暴与沙暴的强度在冷白与沙黄之间加权，再归一化成雾色乘子。
vec3 gfx_storm_color(float snowStorm, float sandStorm){
	float total = max(snowStorm + sandStorm, 1e-4); // 两份强度之和，加一个小量避免除零。
	vec3 sandCol = vec3(1.0, 0.3, 0.1); // 沙暴的沙黄，照 Eclipse 的沙尘系数。
	vec3 snowCol = vec3(0.6, 0.8, 1.0); // 雪暴的冷白，照 Eclipse 的雪系数。
	return (sandStorm * sandCol + snowStorm * snowCol) / total; // 按强度加权后归一，得到最终染色乘子。
}

// 每日天气哈希：把整数天数打散成零到一的小数，照 Eclipse 的 `hash11`。
float gfx_weather_hash11(float p){
	p = fract(p * 0.1031); // 先乘一个无理近似再取小数，打散相邻整数。
	p *= p + 33.33; // 加偏移后再平方，让输入的小变化放大。
	p *= p + p; // 再乘自身的两倍，进一步拉开分布。
	return fract(p); // 取小数，得到零到一的哈希值。
}

#endif
