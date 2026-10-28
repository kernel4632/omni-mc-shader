/*
Omni 通用图形库天气模块：雨雪随风偏移、植被与季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：任何需要天气形状的程序；Minecraft 光影由 `/omni-gfx/weather/weather.glsl` 引入，
    `shaders/effects/shared/weather.glsl`、`dailyweather.glsl`、`storm.glsl` 与 `shaders/effects/weather/season.glsl` 只保留选项换算。
可复制示例：
    float2 o = ogxRainWindOffset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 雨雪的水平偏移。
    float n = ogxStormNoise(worldPos, noiseTexture, 512.0); // 暴风雾团密度。
    float3 c = ogxStormColor(snowStorm, sandStorm); // 暴雪与沙暴的染色。
    float h = ogxHash11(day); // 每日天气的随机取档。
设计原因与取舍：
    位置、时间、风向、扰动和露天系数全部由调用方传入，库不读取相机或天气全局量。
    倾斜随高度放大，露天系数为零时雨雪保持竖直，因此室内不会被风推斜。
    噪声贴图采样固定用零号层级：旧实现的即时采样在单层噪声图上等价，
    固定层级还能让同一份源在 Vulkan 探针里编译。
*/
#ifndef OGX_WEATHER_INCLUDED
#define OGX_WEATHER_INCLUDED

// 数学模块提供取模与夹紧，季节循环与时段划分要用。
#include "../common/math.slang"
// 噪声模块提供每日天气哈希的唯一实现。
#include "../common/noise.slang"

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
// 为什么扰动跟着世界位置走：不同位置的雨丝才不会像一整块布同步摆动。
// 为什么按高度放大：雨丝从云底落到地面，越高的部分受风时间越长，偏移自然更大；
// 贴着地面的雨滴几乎竖直，屋檐与树下不会出现横向穿模的雨。
// 扰动用世界位置做相位，避免整片雨幕同步摆动；露天系数为零时整段归零，室内不受影响。
float2 ogxRainWindOffset(float3 worldPos, float3 cameraPos, float time, float2 wind, float disturbance, float outdoor) // 当前步骤的中间量。
{ // 按参考顺序推进。
    // 相位随世界位置变化：相邻雨丝不会同步摆动，整片雨幕才不像一块布。
    float angle = dot(worldPos + cameraPos, float3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
    // 单位圆上的方向：正弦与余弦一起给出旋转，不需要再归一化。
    float2 rotation = float2(sin(angle), cos(angle)); // 摆动方向。
    // 高度越高偏移越大，贴近地面的雨丝仍然近似竖直，屋檐下不会出现横向雨。
    float2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
    // 露天系数为零时整段偏移归零，室内雨雪保持竖直，不需要另写分支。
    return outdoor * offset; // 只有露天时倾斜。
} // 按参考顺序推进。

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
// 乘四是为了让普通草色接近一，避免季节色只有一点点。
float ogxFoliage(float3 vertexColor) // 当前步骤的中间量。
{ // 按参考顺序推进。
    return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 用绿色优势判断是否植被。
} // 按参考顺序推进。

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
// `phase` 是零到一的一年进度，`tint` 是负到正的冷暖偏置，`enabled` 关闭时原样返回。
float3 ogxSeason(float3 albedo, float3 vertexColor, float phase, float tint, bool enabled) // 当前步骤的中间量。
{
    if (!enabled) return albedo; // 关闭时不做任何改动。
    float foliage = ogxFoliage(vertexColor); // 这一面有多像植被。
    float autumn = 0.5 - 0.5 * cos(phase * OGX_TAU); // 一年过半时最接近秋天。
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
// 每日天气用日期做哈希：同一天所有玩家得到同一结果，跨天自然变化。
// 哈希只接受一个标量，输出零到一，调用方再按档位分段。
float3 ogxStormColor(float snowStorm, float sandStorm)
{
    float total = max(snowStorm + sandStorm, 1e-4); // 两份强度之和。
    float3 sandCol = float3(1.0, 0.3, 0.1); // 沙暴的沙黄，照 Eclipse 的沙尘系数。
    float3 snowCol = float3(0.6, 0.8, 1.0); // 雪暴的冷白，照 Eclipse 的雪系数。
    return (sandStorm * sandCol + snowStorm * snowCol) / total; // 按强度加权后归一。
}

// 四季调色板：树叶与非树叶各一套颜色，因为树叶的季节变化通常更明显。
struct OgxSeasonPalette
{
    float3 summer; // 非树叶的夏天颜色。
    float3 autumn; // 非树叶的秋天颜色。
    float3 winter; // 非树叶的冬天颜色。
    float3 spring; // 非树叶的春天颜色。
    float3 summerLeaf; // 树叶的夏天颜色。
    float3 autumnLeaf; // 树叶的秋天颜色。
    float3 winterLeaf; // 树叶的冬天颜色。
    float3 springLeaf; // 树叶的春天颜色。
};

// Eclipse 四季上色：按游戏天数在四个季节之间连续插值，再乘顶点色。
// `tintIndex` 由调用方判断，决定这一面是否使用群系染色；不使用的面保持原色。
float3 ogxYearCycleColor(float3 finalColor, float3 glcolor, bool isLeaves, OgxSeasonPalette palette, int worldDay, int seasonLength,
    int startSeason, bool tintIndex)
{
    float3 summer = isLeaves ? palette.summerLeaf : palette.summer; // 树叶用树叶那一套。
    float3 autumn = isLeaves ? palette.autumnLeaf : palette.autumn;
    float3 winter = isLeaves ? palette.winterLeaf : palette.winter;
    float3 spring = isLeaves ? palette.springLeaf : palette.spring;
    summer *= glcolor; // 四季颜色都乘顶点色，保留群系底色。
    autumn *= glcolor;
    winter *= glcolor;
    spring *= glcolor;
    float yearLoop = ogxMod(float(worldDay + startSeason * seasonLength), float(seasonLength * 4)); // 一年内的进度。
    float summerTime = clamp(yearLoop, 0.0, float(seasonLength)) / float(seasonLength); // 四个季节各自的权重。
    float autumnTime = clamp(yearLoop - float(seasonLength), 0.0, float(seasonLength)) / float(seasonLength);
    float winterTime = clamp(yearLoop - float(seasonLength * 2), 0.0, float(seasonLength)) / float(seasonLength);
    float springTime = clamp(yearLoop - float(seasonLength * 3), 0.0, float(seasonLength)) / float(seasonLength);
    float3 summerToFall = lerp(summer, autumn, summerTime); // 依次插值，最后回到夏天。
    float3 fallToWinter = lerp(summerToFall, winter, autumnTime);
    float3 winterToSpring = lerp(fallToWinter, spring, winterTime);
    float3 springToSummer = lerp(winterToSpring, summer, springTime);
    return tintIndex ? springToSummer : finalColor; // 不使用群系染色的面保持原色。
}

// 一天四个时段的雾密度：晨、午、晚、夜各一组，均匀雾与团雾分开。
struct OgxTodFog
{
    float4 uniformBands; // 四个时段的均匀雾密度。
    float4 cloudyBands; // 四个时段的团雾密度。
};

// 群系雾覆盖：权重与两套密度，顺序是沼泽、丛林、黑森林、苍白花园。
struct OgxBiomeFog
{
    float4 weights; // 四个群系的权重。
    float uniformDensity; // 群系均匀雾密度。
    float cloudyDensity; // 群系团雾密度。
};

// Eclipse 时段雾：把一天切成晨、午、晚、夜四段，取对应密度。
// `dailyUniform` 与 `dailyCloudy` 是每日天气给出的下限，开启时取较大者；群系雾最后覆盖。
void ogxFogDensities(inout float uniformDensity, inout float cloudyDensity, float dayTime, float fogMultiplier,
    OgxTodFog tod, float2 daily, bool dailyWeather, OgxBiomeFog biome, bool perBiome, float maxDistance)
{
    float time = ogxMod(dayTime, 24000.0); // 一天内的时刻。
    float morning = clamp((time - 22000.0) / 2000.0, 0.0, 1.0) + clamp((2000.0 - time) / 2000.0, 0.0, 1.0); // 晨，跨午夜两段。
    float noon = clamp(time / 2000.0, 0.0, 1.0) * clamp((12000.0 - time) / 2000.0, 0.0, 1.0); // 午。
    float evening = clamp((time - 10000.0) / 2000.0, 0.0, 1.0) * clamp((14000.0 - time) / 2000.0, 0.0, 1.0); // 晚。
    float night = clamp((time - 13000.0) / 2000.0, 0.0, 1.0) * clamp((23000.0 - time) / 2000.0, 0.0, 1.0); // 夜。
    float4 uniformBands = tod.uniformBands * fogMultiplier; // 四段均匀雾密度乘总倍率。
    float4 cloudyBands = tod.cloudyBands * fogMultiplier; // 四段团雾密度。
    if (dailyWeather) // 每日天气给一个下限。
    {
        uniformBands = max(uniformBands, float4(daily.x, daily.x, daily.x, daily.x));
        cloudyBands = max(cloudyBands, float4(daily.y, daily.y, daily.y, daily.y));
    }
    if (perBiome) // 群系雾按权重与距离包络覆盖。
    {
        float inBiome = clamp(biome.weights.x + biome.weights.y + biome.weights.z + biome.weights.w, 0.0, 1.0);
        float blend = inBiome * maxDistance;
        uniformBands = lerp(uniformBands, float4(biome.uniformDensity, biome.uniformDensity, biome.uniformDensity, biome.uniformDensity), blend);
        cloudyBands = lerp(cloudyBands, float4(biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity), blend);
    }
    uniformDensity *= morning * uniformBands.x + noon * uniformBands.y + evening * uniformBands.z + night * uniformBands.w; // 按四段权重求和。
    cloudyDensity *= morning * cloudyBands.x + noon * cloudyBands.y + evening * cloudyBands.z + night * cloudyBands.w; // 团雾同样。
}

// Eclipse 年周期颜色：按季节长度把四套颜色插值成当前颜色，只作用于使用染色索引的方块。
// 参考签名是最终颜色、顶点色、树叶与植物标记；世界天数显式追加，色板常数照参考数值写死。
void ogxYearCycleColorSeason(inout float3 finalColor, float3 glcolor, bool isLeaves, bool isPlants, float worldDay)
{
    float3 summerCol;
    float3 autumnCol;
    float3 winterCol;
    float3 springCol;
    if (isLeaves)
    {
        summerCol = float3(1.0, 1.0, 1.0);
        autumnCol = float3(1.8, 0.9, 0.7);
        winterCol = float3(1.2, 0.5, 1.0);
        springCol = float3(1.0, 0.8, 0.8);
    }
    else
    {
        summerCol = float3(1.0, 1.0, 1.0);
        autumnCol = float3(1.5, 1.0, 1.0);
        winterCol = float3(1.2, 0.8, 1.0);
        springCol = float3(1.0, 0.9, 1.1);
    }
    summerCol *= glcolor;
    autumnCol *= glcolor;
    winterCol *= glcolor;
    springCol *= glcolor;
    int seasonLength = 24;
    float yearLoop = ogxMod(worldDay + 0.0 * float(seasonLength), float(seasonLength) * 4.0);
    float summerTime = clamp(yearLoop, 0, float(seasonLength)) / float(seasonLength);
    float autumnTime = clamp(yearLoop - float(seasonLength), 0, float(seasonLength)) / float(seasonLength);
    float winterTime = clamp(yearLoop - float(seasonLength) * 2.0, 0, float(seasonLength)) / float(seasonLength);
    float springTime = clamp(yearLoop - float(seasonLength) * 3.0, 0, float(seasonLength)) / float(seasonLength);
    float3 summerToFall = lerp(summerCol, autumnCol, summerTime);
    float3 fallToWinter = lerp(summerToFall, winterCol, autumnTime);
    float3 winterToSpring = lerp(fallToWinter, springCol, winterTime);
    float3 springToSummer = lerp(winterToSpring, summerCol, springTime);
    bool isTintIndex = isPlants || isLeaves;
    if (isTintIndex) finalColor = springToSummer;
}


#endif
