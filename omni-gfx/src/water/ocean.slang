/*
水面子文件：海洋波参数、逐层波高与方向、海洋法线、泡沫与整像素着色。
调用位置：由 `water.slang` 内联，水面效果与测试世界直接调用这里的海洋入口。
可复制示例：`OgxOceanWaves waves = ogxOceanWavesDefault();`
设计原因与取舍：层数、拖拽与频率全部显式传入；累加顺序照参考保留，默认海面形状不变。
*/
// 默认参数：iterationT 海洋扩展的常数，调用方只改真正要变的那几个字段。
OgxOceanWaves ogxOceanWavesDefault()
{
    OgxOceanWaves waves;
    waves.iterations = 13; // 层数的基础值，原程序的迭代偏移量。
    waves.drag = 0.048; // 拖拽量小一点，避免波形自己卷起来。
    waves.timeScale = 0.45; // 时间放慢，海面起伏看起来更沉。
    waves.detail = 0.75; // 细节指数，原程序取值。
    waves.frequency = 6.0; // 起始频率。
    waves.speed = 2.0; // 起始相位速度。
    waves.weightFalloff = 0.8; // 每层权重乘零点八，低频占主导。
    waves.frequencyGain = 1.18; // 每层频率乘一点一八。
    waves.speedGain = 1.07; // 每层速度乘一点零七。
    waves.angleStep = 12.0; // 每层方向转十二弧度，等效于错开一圈多，视觉上方向不重复。
    return waves;
}

// 逐层叠加的结果：都是未归一化的和，调用方按自己的用法再除权重和。
struct OgxOceanWaveSum
{
    float height; // 波高和，未除权重。
    float weightSum; // 权重和，用来归一化。
    float2 detail; // 按细节指数累加的方向，泡沫与法线要用。
    float2 position; // 被波形拖拽后的采样点。
};

// 迭代正弦：每层的频率、速度都放大，权重衰减，采样点被波形拖着走。
// 为什么方向累加也放在同一个循环里：一处调用只取波高、另一处还要方向，
// 多算一次加法不影响波高，却省掉第二份一模一样的循环，两边不会再各自漂移。
OgxOceanWaveSum ogxOceanWaveSum(float2 position, float time, OgxOceanWaves waves)
{
    float iter = 0.0; // 每层方向角。
    float frequency = waves.frequency; // 当前层频率。
    float speed = waves.speed; // 当前层速度。
    float weight = 1.0; // 当前层权重，从一整份开始衰减。
    float height = 0.0; // 累加波高。
    float weightSum = 0.0; // 累加权重。
    float2 detail = float2(0.0); // 累加方向。
    float modifiedTime = time * waves.timeScale; // 缩放后的时间。
    for (int i = 0; i < waves.iterations; i++) // 逐层叠加。
    {
        float2 direction = float2(sin(iter), cos(iter)); // 当前层方向。
        float x = dot(direction, position) * frequency + modifiedTime * speed; // 当前层的相位。
        float wave = exp(sin(x) - 1.0); // 波峰更尖的包络，海面才有尖顶。
        float result = wave * cos(x); // 波形值。
        float2 force = result * weight * direction; // 对采样点的拖拽力。
        detail += force / pow(weight, waves.detail); // 权重越小的层贡献越大，细节层因此不会被低频淹没。
        position -= force * waves.drag; // 采样点被拖拽，形成剪切。
        height += wave * weight; // 累加波高。
        iter += waves.angleStep; // 方向角前进。
        weightSum += weight; // 累加权重。
        weight *= waves.weightFalloff; // 权重衰减。
        frequency *= waves.frequencyGain; // 频率放大。
        speed *= waves.speedGain; // 速度放大。
    }
    OgxOceanWaveSum sum;
    sum.height = height; // 交回未归一化的波高。
    sum.weightSum = weightSum; // 交回权重和。
    sum.detail = detail; // 交回方向累加。
    sum.position = position; // 交回拖拽后的位置。
    return sum;
}

// 归一化波高并按海面高度缩放、居中：两处调用共用这一条换算式。
float ogxOceanWaveHeight(OgxOceanWaveSum sum, float oceanHeight, float factor)
{
    return sum.height / sum.weightSum * oceanHeight * factor - oceanHeight * factor * 0.5; // 居中让海面在基准高度上下对称。
}

// 波形空间：把世界水平坐标按原点偏移与横向缩放换成迭代正弦使用的坐标。
// 为什么单独成一个函数：波高、方向与像素数据必须用同一个空间，三处各写一遍迟早会漂移。
float2 ogxOceanWaveSpace(float2 position, float2 offset, float xzScale, float horizontalScale)
{
    return (position - offset) * xzScale * horizontalScale; // 先减原点再乘两级缩放。
}

// 海洋波方向：把逐层累加的方向除以权重和，取负后指向波前进方向。
float2 ogxOceanWaveDirection(OgxOceanWaveSum sum, float detailWeight)
{
    return -sum.detail / pow(sum.weightSum, 1.0 - detailWeight); // 与参考实现的归一化逐项相同。
}

// 海洋波形法线：横纵方向乘上海面高度与波高倍率，再补一个固定的竖直强度。
float3 ogxOceanWaveNormal(float2 direction, float oceanHeight, float factor, float normalStrength)
{
    float oceanHeightFactor = oceanHeight / 13.0; // 海面高度相对基础值十三的倍率。
    float totalFactor = oceanHeightFactor * factor; // 总倍率。
    return normalize(float3(direction.x * totalFactor, normalStrength, direction.y * totalFactor)); // 由方向构造法线。
}

// 波形法线与涟漪法线的混合：涟漪越强，法线越偏向贴图给出的细节。
// `totalEffect` 是四邻高度和，开方后作为混合权重，照参考实现。
float3 ogxOceanNormalWithRipple(float2 position, float2 direction, float factor, float oceanHeight, float normalStrength,
    float2 modelOffset, Sampler2D rippleTexture, float rippleRange, float2 texel)
{
    float3 waveNormal = ogxOceanWaveNormal(direction, oceanHeight, factor, normalStrength); // 先算波形法线。
    float2 eyePosition = position + modelOffset; // 加上模型偏移，定位涟漪。
    float2 fetch = (eyePosition + float2(rippleRange, rippleRange)) / (rippleRange * 2.0); // 涟漪贴图坐标。
    float left = rippleTexture.SampleLevel(fetch - float2(texel.x, 0.0), 0.0).r; // 左侧高度。
    float right = rippleTexture.SampleLevel(fetch + float2(texel.x, 0.0), 0.0).r; // 右侧高度。
    float top = rippleTexture.SampleLevel(fetch - float2(0.0, texel.x), 0.0).r; // 上侧高度。
    float bottom = rippleTexture.SampleLevel(fetch + float2(0.0, texel.x), 0.0).r; // 下侧高度。
    float totalEffect = left + right + top + bottom; // 四邻合计。
    float3 rippleNormal = normalize(float3(left - right, 1.0, top - bottom)); // 涟漪法线。
    return normalize(lerp(waveNormal, rippleNormal, pow(totalEffect, 0.5))); // 按涟漪强度混合。
}

// 海洋泡沫：三层三维噪声相乘得到泡沫形状，再按波峰高度与细胞噪声调制。
// `waveAmplitude` 是已经乘过法线竖直分量的波峰振幅，函数只负责把它夹到零到一。
float ogxOceanFoam(Sampler3D foamTexture, float2 waterUV, float time, float foamAmount, float foamOpacity,
    float waveAmplitude)
{
    float2 s1 = foamTexture.SampleLevel(float3(waterUV * 0.26, time / 360.0), 0.0).rg; // 第一层泡沫噪声。
    float2 s2 = foamTexture.SampleLevel(float3(waterUV * 0.02, time / 360.0 + 0.5), 0.0).rg; // 第二层。
    float2 s3 = foamTexture.SampleLevel(float3(waterUV * 0.1, time / 360.0 + 1.0), 0.0).rg; // 第三层。
    float surfaceNoise = s1.r * s2.r * s3.r * 2.8 * foamAmount; // 三层相乘得到泡沫形状。
    waveAmplitude = clamp(waveAmplitude * 1.2, 0.0, 1.0); // 波峰处的振幅。
    surfaceNoise = (1.0 - waveAmplitude) * surfaceNoise + waveAmplitude * foamAmount; // 波峰处泡沫更强。
    float worleyNoise = 0.2 + 0.8 * s1.g * (1.0 - s2.g); // 细胞状调制。
    surfaceNoise = smoothstep(0.45, 1.0, surfaceNoise) * worleyNoise; // 阈值平滑并乘调制。
    return clamp(2.0 * surfaceNoise * foamOpacity, 0.0, 1.0); // 乘不透明度得到最终泡沫。
}

// 海面像素：一次算出方向、还原位置、法线、泡沫与波高，片元阶段只取一次。
struct OgxOceanPixel
{
    float2 direction; // 波形方向。
    float2 worldPos; // 还原后的世界位置。
    float3 normal; // 混合涟漪后的法线。
    float foam; // 泡沫强度。
    float height; // 波高。
};

// 完整海面像素：把波形迭代、空间换算、涟漪贴图与泡沫噪声放在同一处，宿主只传数据。
// `texel` 是涟漪贴图的横向纹素大小；`iterations` 是浮点层数，内部向上取整，与参考实现一致。
OgxOceanPixel ogxOceanPixel(float2 position, float factor, float iterations, float time,
    float2 waveOffset, float xzScale, float horizontalScale, float oceanHeight, float2 modelOffset,
    Sampler2D rippleTexture, float rippleRange, float2 texel,
    Sampler3D foamTexture, float globalTime, float foamAmount, float foamOpacity, float normalStrength)
{
    float2 wavePos = ogxOceanWaveSpace(position, waveOffset, xzScale, horizontalScale); // 换到波形空间。
    OgxOceanWaves waves = ogxOceanWavesDefault(); // 参考实现的默认常数。
    waves.iterations = int(ceil(iterations)); // 层数向上取整，与原来的整数比较等价。
    OgxOceanWaveSum sum = ogxOceanWaveSum(wavePos, time, waves); // 逐层累加。
    OgxOceanPixel pixel; // 待填充。
    pixel.direction = ogxOceanWaveDirection(sum, waves.detail); // 波形方向。
    pixel.worldPos = sum.position / horizontalScale / xzScale; // 还原世界位置。
    pixel.height = ogxOceanWaveHeight(sum, oceanHeight, factor); // 归一化波高。
    pixel.normal = ogxOceanNormalWithRipple(position, pixel.direction, factor, oceanHeight, normalStrength,
        modelOffset, rippleTexture, rippleRange, texel); // 波形法线混入涟漪。
    float waveAmplitude = pixel.height * pow(max(pixel.normal.y, 0.0), 4.0); // 波峰振幅。
    float2 waterUV = lerp(position - waveOffset, pixel.worldPos, clamp(factor * 2.0, 0.2, 1.0)); // 泡沫坐标在原始与波后位置间混合。
    pixel.foam = ogxOceanFoam(foamTexture, waterUV, globalTime, foamAmount, foamOpacity, waveAmplitude); // 泡沫强度。
    return pixel; // 交回完整数据。
}


// Eclipse 雨点涟漪：九个格子的雨滴各自扩散出圆环，取梯度得到法线。
// `intensity` 控制每格大小，`time` 是累积秒数；九个方向相加后归一，结果与参考实现相同。
float3 ogxRainRipples(float2 fragCoord, float time, float intensity)
{
    float cellDensity = 5.0 * intensity; // 每米几个雨点。
    float sizeCompensation = cellDensity / 5.0; // 密度改变时补偿圆环半径。
    float2 uv = fragCoord * cellDensity; // 换到格子坐标。
    float2 p0 = floor(uv); // 当前格子。
    float2 circles = float2(0.0); // 累加梯度。
    for (int j = -1; j <= 1; j++) // 三乘三邻格。
    {
        for (int i = -1; i <= 1; i++)
        {
            float2 pi = p0 + float2(float(i), float(j)); // 邻格坐标。
            float2 p = pi + ogxHash22(pi); // 雨点落在格内随机位置。
            float t = fract(0.9 * time + ogxHash12(pi)); // 这一滴的扩散相位。
            float2 v = p - uv; // 从雨点到当前像素。
            float d = length(v) - 2.0 * t * sizeCompensation; // 圆环半径随时间扩大。
            float d1 = d - 0.01; // 前后两个采样点。
            float d2 = d + 0.01;
            float p1 = sin(21.0 * d1) * smoothstep(-0.6, -0.3, d1) * (1.0 - smoothstep(-0.3, 0.0, d1)); // 前一点的高度。
            float p2 = sin(21.0 * d2) * smoothstep(-0.6, -0.3, d2) * (1.0 - smoothstep(-0.3, 0.0, d2)); // 后一点的高度。
            circles += 0.5 * normalize(v) * ((p2 - p1) / 0.02 * (1.0 - t) * (1.0 - t)); // 中心差分得到坡度。
        }
    }
    circles /= 9.0; // 九个方向取平均。
    return float3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0))); // 参考实现不做归一化，保持原幅度。
}

// Eclipse 水面焦散：沿太阳方向把水面位置投到水底，用噪声图三层旋转采样得到汇聚花纹。
// `time` 是累积秒数，`waveSpeed` 与 `patchyBlend` 是水面选项，噪声图由调用方给出。
float ogxWaterBumpCaustics(float3 worldPos, float3 sunVec, float surfacePos, float time, float waveSpeed,
    float patchyBlend, Sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    float2 projected = worldPos.xz + (sunVec.xz / abs(sunVec.y)) * surfacePos; // 沿阳光投到水底。
    float2 pos = projected; // 当前采样坐标。
    float largeWaves = noiseTexture.SampleLevel(pos / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = lerp(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float heightSum = 0.0; // 三层高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    float2 rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    float sample0 = noiseTexture.SampleLevel(pos / float2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层，横向拉长。
    heightSum += pow(abs(abs(sample0 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 折线整形后累加。
    rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    float sample1 = noiseTexture.SampleLevel(pos / float2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层，纵向拉长。
    heightSum += pow(abs(abs(sample1 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第二层。
    rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    float sample2 = noiseTexture.SampleLevel(pos / float2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层，正方形。
    heightSum += pow(abs(abs(sample2 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第三层。
    return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5)); // 汇聚成焦散亮度。
}

// Eclipse 水面高度：三层噪声按旋转叠加，再乘大波曲线。
float ogxWaterBumpHeightmap(float2 position, float largeWavesCurved, float time, float waveSpeed, Sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    float2 pos = position; // 当前采样坐标。
    float heightSum = 0.0; // 高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    float2 rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    heightSum += noiseTexture.SampleLevel(pos / float2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层高度。
    rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    heightSum += noiseTexture.SampleLevel(pos / float2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层高度。
    rotated = float2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    heightSum += noiseTexture.SampleLevel(pos / float2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层高度。
    return (heightSum / 4.5) * max(largeWavesCurved, 0.3); // 归一化并留一个下限。
}

// Eclipse 水面法线：中心与横纵两个邻点的高度差构成法线，采样距离随距离与画质变化。
float3 ogxWaterBumpNormal(float3 waterPos, float3 playerPos, float time, float waveSpeed, float patchyBlend,
    float wavesARadius, float wavesBRadius, bool hyperDetailed, Sampler2D noiseTexture)
{
    float largeWaves = noiseTexture.SampleLevel(waterPos.xy / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = lerp(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float deltaPos = 0.025; // 超高质量用固定小步长。
    if (!hyperDetailed) // 普通质量按大波曲线与距离选步长。
    {
        deltaPos = lerp(wavesARadius, wavesBRadius, largeWavesCurved); // 两个半径之间插值。
        deltaPos += min(length(playerPos) / (16.0 * 24.0), 3.0); // 远处加大步长，减少闪烁。
    }
    float h0 = ogxWaterBumpHeightmap(waterPos.xy, largeWavesCurved, time, waveSpeed, noiseTexture); // 中心高度。
    float h1 = ogxWaterBumpHeightmap(waterPos.xy + float2(deltaPos, 0.0), largeWavesCurved, time, waveSpeed, noiseTexture); // 横向邻点。
    float h3 = ogxWaterBumpHeightmap(waterPos.xy + float2(0.0, deltaPos), largeWavesCurved, time, waveSpeed, noiseTexture); // 纵向邻点。
    float xDelta = (h1 - h0) / deltaPos; // 横向坡度。
    float yDelta = (h3 - h0) / deltaPos; // 纵向坡度。
    return normalize(float3(xDelta, yDelta, 1.0 - pow(abs(xDelta + yDelta), 2.0))); // 高度场法线。
}
