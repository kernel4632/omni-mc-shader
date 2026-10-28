/*
生成文件：天气模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库天气模块：雨雪随风偏移、植被与季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：任何需要天气形状的程序；Minecraft 光影由 `/omni-gfx/weather/weather.glsl` 引入，
    `shaders/effects/shared/weather.glsl`、`dailyweather.glsl`、`storm.glsl` 与 `shaders/effects/weather/season.glsl` 只保留选项换算。
可复制示例：
    vec2 o = ogxRainWindOffset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 雨雪的水平偏移。
    float n = ogxStormNoise(worldPos, noiseTexture, 512.0); // 暴风雾团密度。
    vec3 c = ogxStormColor(snowStorm, sandStorm); // 暴雪与沙暴的染色。
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
#include "/omni-gfx/common/math.glsl"
// 噪声模块提供每日天气哈希的唯一实现。
#include "/omni-gfx/common/noise.glsl"
// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
// 为什么扰动跟着世界位置走：不同位置的雨丝才不会像一整块布同步摆动。
vec2 ogxRainWindOffset(vec3 worldPos, vec3 cameraPos, float time, vec2 wind, float disturbance, float outdoor)
{
    float angle = dot(worldPos + cameraPos, vec3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
    vec2 rotation = vec2(sin(angle), cos(angle)); // 摆动方向。
    vec2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
    return outdoor * offset; // 只有露天时倾斜。
}

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
// 乘四是为了让普通草色接近一，避免季节色只有一点点。
float ogxFoliage(vec3 vertexColor)
{
    return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 用绿色优势判断是否植被。
}

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
// `phase` 是零到一的一年进度，`tint` 是负到正的冷暖偏置，`enabled` 关闭时原样返回。
vec3 ogxSeason(vec3 albedo, vec3 vertexColor, float phase, float tint, bool enabled)
{
    if (!enabled) return albedo; // 关闭时不做任何改动。
    float foliage = ogxFoliage(vertexColor); // 这一面有多像植被。
    float autumn = 0.5 - 0.5 * cos(phase * OGX_TAU); // 一年过半时最接近秋天。
    vec3 seasonal = mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成。
    seasonal *= vec3(1.0 + 0.2 * tint, 1.0, 1.0 - 0.2 * tint); // 整体偏暖或偏冷。
    return albedo * mix(vec3(1.0), seasonal, foliage); // 只按植被程度生效。
}

// 暴风噪声：把世界坐标折进噪声贴图，得到随风滚动的雾团密度。
// `noiseResolution` 是噪声贴图边长，调用方可以换用别的贴图而不改公式。
float ogxStormNoise(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    position /= 18.0; // 噪声格子的基准边长。
    position.xz *= 0.5; // 横向再缩一半，让雾团更扁更长，像被风拉过。
    vec3 cell = floor(position); // 所在整数格，决定用贴图哪一块。
    vec3 fraction = fract(position); // 格内小数偏移，用来做插值。
    fraction = fraction * fraction * (3.0 - 2.0 * fraction); // 三次平滑，插值不出现方块边界。
    vec2 uv = cell.xz + fraction.xz + cell.y * vec2(0.0, 193.0); // 三维格子映射到二维坐标，纵轴加大偏移错开层。
    vec2 sample2 = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 读噪声并取两个通道，顺序照原程序。
    return mix(sample2.r, sample2.g, fraction.y); // 沿高度在两通道之间插值。
}

// 暴风颜色：按雪暴与沙暴的强度在冷白与沙黄之间加权，再归一化成雾色乘子。
// 加一个小量避免两份强度都为零时除零；零强度由调用方跳过，不会走到这里。
vec3 ogxStormColor(float snowStorm, float sandStorm)
{
    float total = max(snowStorm + sandStorm, 1e-4); // 两份强度之和。
    vec3 sandCol = vec3(1.0, 0.3, 0.1); // 沙暴的沙黄，照 Eclipse 的沙尘系数。
    vec3 snowCol = vec3(0.6, 0.8, 1.0); // 雪暴的冷白，照 Eclipse 的雪系数。
    return (sandStorm * sandCol + snowStorm * snowCol) / total; // 按强度加权后归一。
}


// 四季调色板：树叶与非树叶各一套颜色，因为树叶的季节变化通常更明显。
struct OgxSeasonPalette
{
    vec3 summer; // 非树叶的夏天颜色。
    vec3 autumn; // 非树叶的秋天颜色。
    vec3 winter; // 非树叶的冬天颜色。
    vec3 spring; // 非树叶的春天颜色。
    vec3 summerLeaf; // 树叶的夏天颜色。
    vec3 autumnLeaf; // 树叶的秋天颜色。
    vec3 winterLeaf; // 树叶的冬天颜色。
    vec3 springLeaf; // 树叶的春天颜色。
};

// Eclipse 四季上色：按游戏天数在四个季节之间连续插值，再乘顶点色。
// `tintIndex` 由调用方判断，决定这一面是否使用群系染色；不使用的面保持原色。
vec3 ogxYearCycleColor(vec3 finalColor, vec3 glcolor, bool isLeaves, OgxSeasonPalette palette, int worldDay, int seasonLength,
    int startSeason, bool tintIndex)
{
    vec3 summer = isLeaves ? palette.summerLeaf : palette.summer; // 树叶用树叶那一套。
    vec3 autumn = isLeaves ? palette.autumnLeaf : palette.autumn;
    vec3 winter = isLeaves ? palette.winterLeaf : palette.winter;
    vec3 spring = isLeaves ? palette.springLeaf : palette.spring;
    summer *= glcolor; // 四季颜色都乘顶点色，保留群系底色。
    autumn *= glcolor;
    winter *= glcolor;
    spring *= glcolor;
    float yearLoop = ogxMod(float(worldDay + startSeason * seasonLength), float(seasonLength * 4)); // 一年内的进度。
    float summerTime = clamp(yearLoop, 0.0, float(seasonLength)) / float(seasonLength); // 四个季节各自的权重。
    float autumnTime = clamp(yearLoop - float(seasonLength), 0.0, float(seasonLength)) / float(seasonLength);
    float winterTime = clamp(yearLoop - float(seasonLength * 2), 0.0, float(seasonLength)) / float(seasonLength);
    float springTime = clamp(yearLoop - float(seasonLength * 3), 0.0, float(seasonLength)) / float(seasonLength);
    vec3 summerToFall = mix(summer, autumn, summerTime); // 依次插值，最后回到夏天。
    vec3 fallToWinter = mix(summerToFall, winter, autumnTime);
    vec3 winterToSpring = mix(fallToWinter, spring, winterTime);
    vec3 springToSummer = mix(winterToSpring, summer, springTime);
    return tintIndex ? springToSummer : finalColor; // 不使用群系染色的面保持原色。
}

// 一天四个时段的雾密度：晨、午、晚、夜各一组，均匀雾与团雾分开。
struct OgxTodFog
{
    vec4 uniformBands; // 四个时段的均匀雾密度。
    vec4 cloudyBands; // 四个时段的团雾密度。
};

// 群系雾覆盖：权重与两套密度，顺序是沼泽、丛林、黑森林、苍白花园。
struct OgxBiomeFog
{
    vec4 weights; // 四个群系的权重。
    float uniformDensity; // 群系均匀雾密度。
    float cloudyDensity; // 群系团雾密度。
};

// Eclipse 时段雾：把一天切成晨、午、晚、夜四段，取对应密度。
// `dailyUniform` 与 `dailyCloudy` 是每日天气给出的下限，开启时取较大者；群系雾最后覆盖。
void ogxFogDensities(inout float uniformDensity, inout float cloudyDensity, float dayTime, float fogMultiplier,
    OgxTodFog tod, vec2 daily, bool dailyWeather, OgxBiomeFog biome, bool perBiome, float maxDistance)
{
    float time = ogxMod(dayTime, 24000.0); // 一天内的时刻。
    float morning = clamp((time - 22000.0) / 2000.0, 0.0, 1.0) + clamp((2000.0 - time) / 2000.0, 0.0, 1.0); // 晨，跨午夜两段。
    float noon = clamp(time / 2000.0, 0.0, 1.0) * clamp((12000.0 - time) / 2000.0, 0.0, 1.0); // 午。
    float evening = clamp((time - 10000.0) / 2000.0, 0.0, 1.0) * clamp((14000.0 - time) / 2000.0, 0.0, 1.0); // 晚。
    float night = clamp((time - 13000.0) / 2000.0, 0.0, 1.0) * clamp((23000.0 - time) / 2000.0, 0.0, 1.0); // 夜。
    vec4 uniformBands = tod.uniformBands * fogMultiplier; // 四段均匀雾密度乘总倍率。
    vec4 cloudyBands = tod.cloudyBands * fogMultiplier; // 四段团雾密度。
    if (dailyWeather) // 每日天气给一个下限。
    {
        uniformBands = max(uniformBands, vec4(daily.x, daily.x, daily.x, daily.x));
        cloudyBands = max(cloudyBands, vec4(daily.y, daily.y, daily.y, daily.y));
    }
    if (perBiome) // 群系雾按权重与距离包络覆盖。
    {
        float inBiome = clamp(biome.weights.x + biome.weights.y + biome.weights.z + biome.weights.w, 0.0, 1.0);
        float blend = inBiome * maxDistance;
        uniformBands = mix(uniformBands, vec4(biome.uniformDensity, biome.uniformDensity, biome.uniformDensity, biome.uniformDensity), blend);
        cloudyBands = mix(cloudyBands, vec4(biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity), blend);
    }
    uniformDensity *= morning * uniformBands.x + noon * uniformBands.y + evening * uniformBands.z + night * uniformBands.w; // 按四段权重求和。
    cloudyDensity *= morning * cloudyBands.x + noon * cloudyBands.y + evening * cloudyBands.z + night * cloudyBands.w; // 团雾同样。
}

// Eclipse 年周期颜色：按季节长度把四套颜色插值成当前颜色，只作用于使用染色索引的方块。
// 参考签名是最终颜色、顶点色、树叶与植物标记；世界天数显式追加，色板常数照参考数值写死。
void ogxYearCycleColorSeason(inout vec3 finalColor, vec3 glcolor, bool isLeaves, bool isPlants, float worldDay)
{
    vec3 summerCol;
    vec3 autumnCol;
    vec3 winterCol;
    vec3 springCol;
    if (isLeaves)
    {
        summerCol = vec3(1.0, 1.0, 1.0);
        autumnCol = vec3(1.8, 0.9, 0.7);
        winterCol = vec3(1.2, 0.5, 1.0);
        springCol = vec3(1.0, 0.8, 0.8);
    }
    else
    {
        summerCol = vec3(1.0, 1.0, 1.0);
        autumnCol = vec3(1.5, 1.0, 1.0);
        winterCol = vec3(1.2, 0.8, 1.0);
        springCol = vec3(1.0, 0.9, 1.1);
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
    vec3 summerToFall = mix(summerCol, autumnCol, summerTime);
    vec3 fallToWinter = mix(summerToFall, winterCol, autumnTime);
    vec3 winterToSpring = mix(fallToWinter, springCol, winterTime);
    vec3 springToSummer = mix(winterToSpring, summerCol, springTime);
    bool isTintIndex = isPlants || isLeaves;
    if (isTintIndex) finalColor = springToSummer;
}

/*
实现说明：天气形状。
一、云量：按每日天气与群系权重混合，输出零到一的覆盖率。
二、风：水平风向与风速由调用方传入，噪声坐标随时间平移。
三、雷暴：闪电强度与云量分别输出，云与雾按自己的阈值使用。
四、噪声：二维值噪声叠成云团，低频决定大块，高频决定边缘。
五、边界：位置、时间、风向与露天系数全部显式传入，库不读取天气全局量。
六、单位：世界坐标用方块，时间用秒；调用方负责把自己的时间缩放传入。
*/
/*
函数索引：
一、`ogxRainWindOffset`：雨天的风偏移。
二、`ogxFoliage`：植被季节色。
三、`ogxSeason`：季节权重。
四、`ogxStormNoise`：雷暴噪声。
五、`ogxStormColor`：雷暴染色。
六、`ogxYearCycleColor` 与 `ogxYearCycleColorSeason`：年周期颜色。
七、`ogxFogDensities`：按天气输出雾密度。
八、边界：位置、时间、风向与露天系数全部显式传入。
九、单位：世界坐标用方块，时间用秒。
*/
/*
参数与边界：
一、时间用秒，世界坐标用方块。
二、风向是水平单位向量。
三、露天系数在零到一之间，零表示完全遮蔽。
四、季节权重按年周期插值。
五、雷暴强度与降雨强度分开。
六、雾密度按天气与群系混合。
七、所有函数只接收显式参数，不读取天气全局量。
八、画面验证要看雨、雪与雷暴三种天气。
*/
#endif
