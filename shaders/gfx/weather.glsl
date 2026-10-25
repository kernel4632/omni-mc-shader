/*
天气模块适配层：雨雪偏移、植被与季节上色、暴风噪声与染色、每日天气哈希已迁到生成库。
调用位置：`rendering/weather/weather.glsl`、`season.glsl`、`storm.glsl` 与 `dailyweather.glsl`
    引用本文件；这些效果层只保留选项换算，算式只在 `omni-gfx/src/weather.slang` 一份。
可复制示例：`float n = gfx_storm_noise(worldPos, noisetex, 512.0);` 暴风雾团密度，实现在生成库。
设计原因与取舍：函数名与参数顺序保持原样，几百个调用点无需改动，默认画面不会漂移；
    噪声贴图与分辨率由调用方传入，库不绑定采样器，也不读取任何宿主宏。
*/
#ifndef GFX_WEATHER_INCLUDED
#define GFX_WEATHER_INCLUDED

// 迁移后的天气实现：雨雪偏移、季节、暴风与每日天气哈希。
#include "/omni-gfx/weather.glsl"

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
vec2 gfx_rain_wind_offset(vec3 worldPos, vec3 cameraPos, float time, vec2 wind, float disturbance, float outdoor){
	return ogxRainWindOffset(worldPos, cameraPos, time, wind, disturbance, outdoor); // 实现在生成库。
}

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
float gfx_foliage(vec3 vertexColor){
	return ogxFoliage(vertexColor); // 实现在生成库。
}

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
vec3 gfx_season(vec3 albedo, vec3 vertexColor, float phase, float tint, bool enabled){
	return ogxSeason(albedo, vertexColor, phase, tint, enabled); // 实现在生成库。
}

// 暴风噪声：把世界坐标折进噪声贴图，得到随风滚动的雾团密度。
float gfx_storm_noise(vec3 position, sampler2D noiseTexture, float noiseResolution){
	return ogxStormNoise(position, noiseTexture, noiseResolution); // 实现在生成库。
}

// 暴风颜色：按雪暴与沙暴的强度在冷白与沙黄之间加权，再归一化成雾色乘子。
vec3 gfx_storm_color(float snowStorm, float sandStorm){
	return ogxStormColor(snowStorm, sandStorm); // 实现在生成库。
}

// 每日天气哈希：把整数天数打散成零到一的小数。
float gfx_weather_hash11(float p){
	return ogxWeatherHash11(p); // 实现在生成库。
}

#endif
