/*
水面子文件：默认水体参数、解析方向波、Gerstner 波、菲涅尔、吸收、折射与水面着色。
调用位置：由 `water.slang` 内联，水面效果与反射共用这里的法线和吸收曲线。
可复制示例：`vec3 n = ogxWaterNormal(position, time, distance, 1.0, 1.0);`
设计原因与取舍：波形是解析函数，不依赖噪声贴图；距离淡出与参考常数逐项一致。
*/
// 默认水体：偏青的浅水、深蓝的深水，红光吸收最快。
OgxWater ogxWaterDefault()
{
    OgxWater water; // 先声明再填写字段。
    water.shallowColor = float3(0.10, 0.34, 0.36); // 浅水偏青绿。
    water.deepColor = float3(0.008, 0.045, 0.120); // 深水偏蓝。
    water.absorption = float3(0.18, 0.075, 0.035); // 红光最先被吸收，深水因此偏蓝。
    water.waveScale = 1.0; // 默认波形密度。
    water.waveHeight = 1.0; // 默认坡度。
    water.roughness = 0.08; // 水面比较光滑，高光集中。
    water.refraction = 0.035; // 折射偏移不要太大，避免岸边拉扯。
    return water; // 返回可直接修改的默认值。
}

// 水面法线：四组方向波的解析梯度相加，再转成朝上的法线。
float3 ogxWaterNormal(float2 position, float time, float distance, float waveScale, float waveHeight)
{
    float2 p = position * waveScale; // 按波形密度缩放空间坐标。
    float2 gradient = float2(0.0); // 高度场的水平梯度。
    float2 direction0 = float2(0.62, 0.28); // 长波方向。
    float2 direction1 = float2(-0.31, 0.74); // 斜向波方向。
    float nearFade = 1.0 - smoothstep(20.0, 120.0, distance); // 近处保留高频细节。
    gradient = direction0 * (0.320 * 0.035 * cos(dot(p, direction0) * 0.035 + time * 0.55)); // 一百八十米级长波，远处也不会闪。
    gradient += direction1 * (0.220 * 0.060 * cos(dot(p, direction1) * 0.060 + time * 0.85)); // 一百米级斜向波。
    float2 direction2 = float2(0.88, -0.41); // 短波方向。
    gradient += direction2 * (0.080 * 0.180 * cos(dot(p, direction2) * 0.180 + time * 1.2)) * nearFade; // 三十米级短波只在近处。
    float2 direction3 = float2(-0.67, -0.55); // 细波纹方向。
    gradient += direction3 * (0.040 * 0.450 * cos(dot(p, direction3) * 0.450 + time * 1.7)) * nearFade * nearFade; // 十米级细波纹只在近处。
    gradient *= waveHeight; // 按坡度倍率缩放。
    float breakup = 0.75 + 0.5 * ogxValueNoise2(position * 0.015 + float2(time * 0.02, time * 0.013)); // 低频噪声打散规则波列。
    gradient *= breakup; // 避免整片水面出现同一条亮带。
    float distanceFade = 1.0 - smoothstep(200.0, 900.0, distance) * 0.85; // 远处压平法线，减少像素级闪烁。
    return normalize(float3(-gradient.x * distanceFade, 1.0, -gradient.y * distanceFade)); // 高度场梯度转成朝上的法线。
}

// 单个 Gerstner 波对水面坡度的贡献：方向乘坡度余弦，波长决定传播速度。
// 为什么不用贴图：解析波列的相位永远连续，远处压平后不会像滚动噪声那样闪烁；
// 振幅已经折进 `steepness`，所以这里只交回水平梯度，调用方直接转成法线。
float2 ogxGerstnerGradient(float2 position, float2 direction, float wavelength, float steepness, float time, float phase)
{
    float waveNumber = 6.28318530718 / max(wavelength, 0.05); // 每米多少个弧度。
    float angularSpeed = sqrt(9.81 * waveNumber); // 深水色散关系，长波跑得快、短波跑得慢。
    float angle = waveNumber * dot(direction, position) - angularSpeed * time + phase; // 当前相位。
    return direction * (steepness * cos(angle)); // 正弦波高度的水平导数。
}

// 水面 Gerstner 波法线：五组不同波长与方向的波叠加，再补一层细碎风纹。
// 为什么用五组：一组是规则条纹，两组会互相拍成十字，五组不同方向和波长才有湖面的随机感。
// 距离越远，短波越早淡出；否则一个像素覆盖多个波长，画面会闪成噪点。
float3 ogxGerstnerNormal(float2 position, float time, float distance, float scale, float amplitude)
{
    float2 p = position * scale; // 按波形密度缩放世界坐标。
    float2 gradient = float2(0.0); // 五组波的水平梯度之和。
    gradient += ogxGerstnerGradient(p, float2(0.86, 0.51), 13.0, 0.090, time, 0.0); // 十三米长波。
    gradient += ogxGerstnerGradient(p, float2(-0.42, 0.91), 8.2, 0.072, time, 1.7); // 八米斜波。
    float nearFade = 1.0 - smoothstep(45.0, 260.0, distance); // 四米以下的波在远处淡出。
    gradient += ogxGerstnerGradient(p, float2(0.97, -0.24), 5.1, 0.052, time, 3.1) * nearFade; // 五米碎波。
    float closeFade = 1.0 - smoothstep(20.0, 110.0, distance); // 两米级波纹只在近处。
    gradient += ogxGerstnerGradient(p, float2(-0.71, -0.70), 3.3, 0.038, time, 5.2) * closeFade; // 三米波纹。
    gradient += ogxGerstnerGradient(p, float2(0.32, 0.95), 2.1, 0.026, time, 0.9) * closeFade; // 两米细波。
    // 风纹：用两个相差半步的值噪声差分，补上解析波没有的碎小起伏。
    float rippleFade = 1.0 - smoothstep(12.0, 70.0, distance);
    float eps = 0.12; // 差分步长，米。
    float height0 = ogxValueNoise2(p * 2.3 + float2(time * 0.16, -time * 0.11));
    float heightX = ogxValueNoise2((p + float2(eps, 0.0)) * 2.3 + float2(time * 0.16, -time * 0.11));
    float heightZ = ogxValueNoise2((p + float2(0.0, eps)) * 2.3 + float2(time * 0.16, -time * 0.11));
    gradient += float2(height0 - heightX, height0 - heightZ) * (0.55 * rippleFade / eps);
    gradient *= amplitude; // 统一坡度倍率。
    return normalize(float3(-gradient.x, 1.0, -gradient.y)); // 高度场梯度转成朝上的法线。
}

// 菲涅尔：正对时只剩基础反射率，掠射时接近全反射。
float ogxWaterFresnel(float NdotV, float f0)
{
    float x = 1.0 - ogxSaturate(NdotV); // 掠射程度。
    float x2 = x * x; // 平方。
    return f0 + (1.0 - f0) * x2 * x2 * x; // 五次方近似。
}

// 水的吸收：按水深逐通道衰减，红光最快，所以深水偏蓝。
float3 ogxWaterAbsorption(OgxWater water, float depth)
{
    return exp(-water.absorption * max(depth, 0.0)); // 比尔-朗伯定律。
}

// 屏幕折射偏移：水越深、越靠近相机，偏移越明显；远处收小避免整片扭曲。
float2 ogxWaterRefractionOffset(float3 normal, float depth, float distance, float strength)
{
    float2 offset = normal.xz * strength * ogxSaturate(depth * 0.12) / (1.0 + distance * 0.015); // 按深度与距离缩放。
    return offset; // 返回屏幕坐标偏移。
}

// 岸线泡沫：水很浅时出现，噪声让泡沫边缘不整齐。
float ogxWaterFoam(float depth, float noise)
{
    float edge = 1.0 - smoothstep(0.0, 0.9, max(depth, 0.0)); // 只在浅水出现。
    return edge * ogxSaturate(noise * 1.6 - 0.3); // 噪声把泡沫打散。
}

// 水面着色：折射色乘吸收，再按菲涅尔混入反射，最后叠太阳高光与泡沫。
float3 ogxWaterShade(OgxWater water, float3 normal, float3 viewDirection, float3 sunDirection, float3 sunColor,
                     float3 reflectionColor, float3 refractionColor, float depth, float foam, out float alpha)
{
    float facing = ogxSaturate(dot(normal, viewDirection)); // 正对程度。
    float fresnel = ogxWaterFresnel(facing, 0.02); // 水的菲涅尔基础反射率约零点零二。
    float3 transmitted = refractionColor * ogxWaterAbsorption(water, depth); // 水下颜色被水吸收。
    // 深水会彻底吸收掉水底的颜色，只剩水本身的体色；不补这一步，深海会变成一块黑。
    transmitted = lerp(water.deepColor, transmitted, exp(-depth * 0.32)); // 越深越接近深水体色。
    transmitted = lerp(water.shallowColor, transmitted, ogxSaturate(depth * 0.25)); // 浅水保留更多水色。
    float3 color = lerp(transmitted, reflectionColor, fresnel); // 折射与反射按菲涅尔混合。
    color += ogxSpecularGGX(normal, viewDirection, sunDirection, water.roughness, 0.02) * sunColor * 1.5; // 太阳高光。
    color += foam * water.shallowColor * 0.8; // 岸线泡沫。
    alpha = ogxSaturate(fresnel * 0.85 + 0.22 + ogxSaturate(depth * 0.08)); // 深水更不透明。
    return color; // 返回线性水面颜色。
}

// 平滑噪声取样：先把坐标吸到最近的纹素中心，再用三次曲线改写小数部分，得到不会闪的平滑噪声。
// 与迁移前的 GLSL 原型算式一致，波纹形状因此不变。
float4 ogxTextureSmooth(Sampler2D noiseTexture, float2 coord)
{
    coord *= 64.0; // 放大到六十四格，再按格取平滑。
    coord += 0.5; // 移到格子中心。
    float2 whole = floor(coord); // 整数格。
    float2 part = coord - whole; // 小数部分。
    coord = whole + part * part * (3.0 - 2.0 * part); // 三次曲线改写小数部分。
    coord -= 0.5; // 移回格子角。
    coord *= 0.015625; // 缩回六十四分之一，换算到零到一坐标。
    return noiseTexture.SampleLevel(coord, 0.0); // 读取平滑后的噪声通道。
}

// 几乎恒等函数：只在靠近中间的一段把值重写成更平的曲线，用来压掉最亮和最暗的水波。
float ogxAlmostIdentity(float x, float m, float n)
{
    x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值。
    if (x <= m) // 只在该区间中间改写。
    {
        float a = 2.0 * n - m; // 三次项系数。
        float b = 2.0 * m - 3.0 * n; // 二次项系数。
        float t = x / m; // 归一化到零到一。
        x = (a * t + b) * t * t + n; // 三次多项式保持端点连续。
    }
    return 1.0 - x; // 再翻转回来。
}

// 水面高度：六层不同尺度与速度的噪声叠加，按权重和归一化。
float ogxWaves(float3 position, Sampler2D noiseTexture, float time, float waveScale)
{
    float wavesTime = time * 0.0035; // 波浪时间比真实时间慢很多。
    position *= waveScale; // 按波浪尺度缩放空间坐标。
    float2 p = position.xz - position.y; // 取水平坐标，减去高度让波浪跟着高度错动。
    p += -3.875 * wavesTime; // 整片波浪一起平移。
    p.x = -p.x; // 翻转一个轴，打散方向。
    float waves = 0.0; // 累积高度。
    float weight = 0.0; // 累积权重。
    waves += ogxTextureSmooth(noiseTexture, p * float2(2.0, 1.2) + float2(0.0, p.x * 2.1)).w; weight += 1.0; // 第一层大浪。
    p = p * 0.475; // 缩小坐标，频率升高。
    p += float2(-5.16, -7.75) * wavesTime; // 这一层被风推着走。
    waves += ogxTextureSmooth(noiseTexture, p * float2(2.0, 1.4) + float2(0.0, -p.x * 2.1)).w * 4.0; weight += 4.0; // 第二层。
    p *= 0.67; // 再抬高频率。
    p.x += 7.75 * wavesTime; // 反向移动。
    waves += ogxTextureSmooth(noiseTexture, p + float2(0.0, p.x * 1.1)).z * 8.0; weight += 8.0; // 第三层。
    p *= 0.7; // 继续抬高频率。
    p.x += -2.82 * wavesTime; // 顺风移动。
    waves += ogxTextureSmooth(noiseTexture, p * float2(1.0, 0.75) + float2(0.0, -p.x * 1.7)).w * 16.0; weight += 16.0; // 第四层。
    p *= 0.45; // 高频细节。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * float2(1.0, 0.8) + float2(0.0, -p.x * 1.7)).z, 0.2, 0.1) * 30.0; weight += 30.0; // 第五层。
    p *= 0.5; // 最高频一层。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * float2(1.0, 0.8) + float2(0.0, p.x * 1.7)).w, 0.2, 0.1) * 20.0; weight += 20.0; // 第六层。
    return waves / weight; // 高度除以权重和，归一化到零到一。
}

// 波法线：用中心与两个邻点的高度差构成法线，再按波高与陡度缩放。
float3 ogxWavesNormal(float3 position, Sampler2D noiseTexture, float time, float waveScale, float waveHeight, float heightScale)
{
    float sampleDistance = 12.0; // 切线差分采样的距离。
    position.xz -= 0.005 * sampleDistance; // 把采样点整体挪一点，让差分落在波浪内部。
    float center = ogxWaves(position, noiseTexture, time, waveScale); // 中心高度。
    float left = ogxWaves(position + float3(0.01 * sampleDistance, 0.0, 0.0), noiseTexture, time, waveScale); // 横向偏移。
    float up = ogxWaves(position + float3(0.0, 0.0, 0.01 * sampleDistance), noiseTexture, time, waveScale); // 纵向偏移。
    float3 normal = float3(center - left, center - up, 1.0); // 用两个方向的高度差构成法线。
    normal.xy *= waveHeight * (heightScale / sampleDistance); // 乘波高与陡度，控制倾斜。
    return normal; // 返回未归一化的法线。
}

// 水面视差：沿视线在波浪高度场里步进，找到视线与浪面的交点。
float3 ogxWaterParallax(float3 position, float3 viewVector, Sampler2D noiseTexture, float time, float waveScale, float heightScale)
{
    float3 stepSize = float3(heightScale * 0.8, heightScale * 0.8, 0.6); // 每步大小，按波高缩放。
    float waveHeight = ogxWaves(position, noiseTexture, time, waveScale); // 起点波高。
    float3 pCoord = float3(0.0, 0.0, 1.0); // 以当前点为参考向前推进的距离。
    float3 steps = viewVector * stepSize; // 每步步进。
    float sampleHeight = waveHeight; // 当前步的波高。
    for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i) // 最多十二步。
    {
        pCoord.xy += steps.xy * clamp((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2), 0.0, 1.0); // 按剩余深度推进水平偏移。
        pCoord.z += steps.z; // 步进向前。
        sampleHeight = ogxWaves(position + float3(pCoord.x, 0.0, pCoord.y), noiseTexture, time, waveScale); // 读取新位置的波高。
    }
    return position + float3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

// 折射坐标：水面按两种法线的差做偏移，玻璃与冰按折射方向投影到屏幕。
float2 ogxWaterRefractionCoord(bool isWater, float3 normal, float3 viewPos, float3 waveNormal,
    float3x3 modelView, float4x4 projection, float waterDeep, float waterDist, float2 screenInput)
{
    float2 coord = screenInput; // 默认不变，返回原屏幕坐标。
    if (isWater) // 水面：用波法线与平水面法线的差做偏移。
    {
        float3 waveView = normalize(ogxMatrix3MulPoint(modelView, waveNormal)); // 波法线转到视空间。
        float3 flatView = normalize(ogxMatrix3MulPoint(modelView, float3(0.0, 1.0, 0.0))); // 平水面法线转到视空间。
        coord = flatView.xy - waveView.xy; // 两种法线的差就是偏移方向。
        coord *= ogxSaturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深偏得越远，远处收敛到零。
        coord += screenInput; // 叠到原坐标上。
    }
    else // 玻璃与冰：按折射方向投影到屏幕。
    {
        float3 direction = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
        direction /= ogxSaturate(dot(direction, -normal)); // 归一化到视线方向，避免分母让角度爆炸。
        direction *= ogxSaturate(waterDeep * 2.0) * 0.125; // 按深度缩放。
        float4 position = ogxMatrixMul(projection, float4(viewPos + direction, 0.0)); // 投影到裁剪空间。
        coord = position.xy / position.w * 0.5 + 0.5; // 转到屏幕坐标。
    }
    return coord; // 返回采样用的屏幕坐标。
}
