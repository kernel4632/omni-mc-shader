/*
Omni 通用图形库天气模块：雨雪随风偏移、植被与季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：任何需要天气形状的程序；Minecraft 光影由 `/omni-gfx/weather.glsl` 引入，
    `rendering/weather/*` 的四个文件只保留选项换算并转发到这里。
可复制示例：
    float2 o = ogxRainWindOffset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 雨雪的水平偏移。
    float n = ogxStormNoise(worldPos, noiseTexture, 512.0); // 暴风雾团密度。
    float3 c = ogxStormColor(snowStorm, sandStorm); // 暴雪与沙暴的染色。
    float h = ogxWeatherHash11(day); // 每日天气的随机取档。
设计原因与取舍：
    位置、时间、风向、扰动和露天系数全部由调用方传入，库不读取相机或天气全局量。
    倾斜随高度放大，露天系数为零时雨雪保持竖直，因此室内不会被风推斜。
    噪声贴图采样固定用零号层级：旧实现的即时采样在单层噪声图上等价，
    固定层级还能让同一份源在 Vulkan 探针里编译。
*/
#ifndef OGX_WEATHER_INCLUDED
#define OGX_WEATHER_INCLUDED

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
// 为什么扰动跟着世界位置走：不同位置的雨丝才不会像一整块布同步摆动。
float2 ogxRainWindOffset(float3 worldPos, float3 cameraPos, float time, float2 wind, float disturbance, float outdoor)
{
    float angle = dot(worldPos + cameraPos, float3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
    float2 rotation = float2(sin(angle), cos(angle)); // 摆动方向。
    float2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
    return outdoor * offset; // 只有露天时倾斜。
}

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
// 乘四是为了让普通草色接近一，避免季节色只有一点点。
float ogxFoliage(float3 vertexColor)
{
    return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 用绿色优势判断是否植被。
}

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
// `phase` 是零到一的一年进度，`tint` 是负到正的冷暖偏置，`enabled` 关闭时原样返回。
float3 ogxSeason(float3 albedo, float3 vertexColor, float phase, float tint, bool enabled)
{
    if (!enabled) return albedo; // 关闭时不做任何改动。
    float foliage = ogxFoliage(vertexColor); // 这一面有多像植被。
    float autumn = 0.5 - 0.5 * cos(phase * 6.28318530718); // 一年过半时最接近秋天。
    float3 seasonal = lerp(float3(1.0), float3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成。
    seasonal *= float3(1.0 + 0.2 * tint, 1.0, 1.0 - 0.2 * tint); // 整体偏暖或偏冷。
    return albedo * lerp(float3(1.0), seasonal, foliage); // 只按植被程度生效。
}

// 暴风噪声：把世界坐标折进噪声贴图，得到随风滚动的雾团密度。
// `noiseResolution` 是噪声贴图边长，调用方可以换用别的贴图而不改公式。
float ogxStormNoise(float3 position, Sampler2D noiseTexture, float noiseResolution)
{
    position /= 18.0; // 噪声格子的基准边长。
    position.xz *= 0.5; // 横向再缩一半，让雾团更扁更长，像被风拉过。
    float3 cell = floor(position); // 所在整数格，决定用贴图哪一块。
    float3 fraction = fract(position); // 格内小数偏移，用来做插值。
    fraction = fraction * fraction * (3.0 - 2.0 * fraction); // 三次平滑，插值不出现方块边界。
    float2 uv = cell.xz + fraction.xz + cell.y * float2(0.0, 193.0); // 三维格子映射到二维坐标，纵轴加大偏移错开层。
    float2 sample2 = noiseTexture.SampleLevel(uv / noiseResolution, 0.0).yx; // 读噪声并取两个通道，顺序照原程序。
    return lerp(sample2.r, sample2.g, fraction.y); // 沿高度在两通道之间插值。
}

// 暴风颜色：按雪暴与沙暴的强度在冷白与沙黄之间加权，再归一化成雾色乘子。
// 加一个小量避免两份强度都为零时除零；零强度由调用方跳过，不会走到这里。
float3 ogxStormColor(float snowStorm, float sandStorm)
{
    float total = max(snowStorm + sandStorm, 1e-4); // 两份强度之和。
    float3 sandCol = float3(1.0, 0.3, 0.1); // 沙暴的沙黄，照 Eclipse 的沙尘系数。
    float3 snowCol = float3(0.6, 0.8, 1.0); // 雪暴的冷白，照 Eclipse 的雪系数。
    return (sandStorm * sandCol + snowStorm * snowCol) / total; // 按强度加权后归一。
}

// 每日天气哈希：把整数天数打散成零到一的小数，照 Eclipse 的 `hash11`。
// 三步混合让相邻天数看起来毫无关系，同时保持完全确定的重复性。
float ogxWeatherHash11(float p)
{
    p = fract(p * 0.1031); // 先乘一个无理近似再取小数，打散相邻整数。
    p *= p + 33.33; // 加偏移后再平方，让输入的小变化放大。
    p *= p + p; // 再乘自身的两倍，进一步拉开分布。
    return fract(p); // 取小数，得到零到一的哈希值。
}

#endif
