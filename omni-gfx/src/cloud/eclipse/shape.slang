// 二维哈希：把格坐标打散成两个零到一的随机数，供云形状使用。
float2 ogxEclipseHash2(float2 p)
{
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973)); // 三个不同频率的搅动。
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33); // 互相混合。
    return fract((float2(p3.x, p3.x) + float2(p3.y, p3.z)) * float2(p3.z, p3.y)); // 取两个独立分量。
}

// 归一化哈希向量：把格坐标变成一个单位方向，供 Perlin 梯度使用。
// 把二维哈希值归一到零到一，避免负值让噪声出现暗带。
float2 ogxEclipseNormalizeHash(float2 p)
{
    return normalize(ogxEclipseHash2(p) - 0.5); // 中心化后单位化。
}

// Perlin 梯度：返回解析梯度，供旋度噪声直接使用。
// 由哈希选二维梯度方向，供 Perlin 噪声生成云形状。
float2 ogxEclipsePerlinGradient(float2 coord)
{
    float2 i = floor(coord); // 整数格。
    float2 f = fract(coord); // 格内偏移。
    float2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 参考实现的导数，虽然不是严格数学导数但画面更自然。
    float2 g0 = ogxEclipseNormalizeHash(i); // 左下梯度。
    float2 g1 = ogxEclipseNormalizeHash(i + float2(1.0, 0.0)); // 右下梯度。
    float2 g2 = ogxEclipseNormalizeHash(i + float2(0.0, 1.0)); // 左上梯度。
    float2 g3 = ogxEclipseNormalizeHash(i + float2(1.0, 1.0)); // 右上梯度。
    float v0 = dot(g0, f); // 左下贡献。
    float v1 = dot(g1, f - float2(1.0, 0.0)); // 右下贡献。
    float v2 = dot(g2, f - float2(0.0, 1.0)); // 左上贡献。
    float v3 = dot(g3, f - float2(1.0, 1.0)); // 右上贡献。
    float2 omu = 1.0 - u; // 反向平滑权重。
    return float2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的梯度。
}

// 二维旋度：把梯度旋转九十度，得到无散度的流动场。
float2 ogxEclipseCurl2D(float2 coord)
{
    float2 gradient = ogxEclipsePerlinGradient(coord); // 取梯度。
    return float2(gradient.y, -gradient.x); // 旋转九十度。
}

// 极光的三维噪声：四个平移后的哈希值按距离加权，得到柔和的团块。
float ogxEclipseTriNoise2d(float2 coord, float time)
{
    float2 p = coord * 0.5; // 整体缩放。
    float2 i = floor(p); // 整数格。
    float2 f = fract(p); // 格内偏移。
    float2 u = f * f * (3.0 - 2.0 * f); // 平滑。
    float a = ogxEclipseHash2(i).x; // 左下。
    float b = ogxEclipseHash2(i + float2(1.0, 0.0)).x; // 右下。
    float c = ogxEclipseHash2(i + float2(0.0, 1.0)).x; // 左上。
    float d = ogxEclipseHash2(i + float2(1.0, 1.0)).x; // 右上。
    float value = lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y); // 双线性插值。
    float wave = sin(time + value * 6.28318530718) * 0.5 + 0.5; // 时间相位。
    return value * wave; // 噪声乘相位。
}

// 单层云形状：按层号走参考实现的分支，返回零到一的密度。
// 云层形状与云影的提前声明：入口放在定义之前。
float ogxEclipseGetCloudShape(OgxEclipseCloudSettings s, int layerIndex, int lod, float3 position,
    float minHeight, float maxHeight, Sampler2D noiseTexture);
float ogxEclipseGetCloudShadow(OgxEclipseCloudSettings s, float3 playerPos, float3 sunVector,
    int cloudShadowAmount, float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture);

// Eclipse 云层形状入口：参考签名只带层号、细节层级、位置与高度范围，云设置与噪声由宿主提供。
float ogxItxGetCloudShape(int layerIndex, int lod, float3 position, float minHeight, float maxHeight,
    OgxEclipseCloudSettings s, Sampler2D noiseTexture)
{
    return ogxEclipseGetCloudShape(s, layerIndex, lod, position, minHeight, maxHeight, noiseTexture);
}

// Eclipse 云影入口：参考签名只给世界位置与太阳方向，云设置、相机与噪声由宿主提供。
float ogxItxGetCloudShadow(float3 playerPos, float3 sunVector, OgxEclipseCloudSettings s,
    int cloudShadowAmount, float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture)
{
    return ogxEclipseGetCloudShadow(s, playerPos, sunVector, cloudShadowAmount, cumulonimbusScale,
        cameraPos, noiseTexture);
}

// 云形状的实际定义：把层号、覆盖率与上下界交给噪声采样，返回该层的密度。
float ogxEclipseGetCloudShape(OgxEclipseCloudSettings s, int layerIndex, int lod, float3 position,
    float minHeight, float maxHeight, Sampler2D noiseTexture)
{
    float coverage = 0.0; // 云量。
    float shape = 0.0; // 形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    float3 samplePos = position * float3(0.25, 0.005, 0.25); // 形状取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    if (layerIndex == 4) // 卷云。
    {
        coverage = s.layers[4].coverage; // 卷云量。
        float2 coord = position.zx + 6.0 * s.cloudMovement; // 卷云坐标。
        float2 curl = ogxEclipseCurl2D(0.00002 * coord) * 0.5
                    + ogxEclipseCurl2D(0.00005 * coord) * 0.25
                    + ogxEclipseCurl2D(0.00018 * coord) * 0.125; // 三层旋度。
        largeCloud = noiseTexture.SampleLevel((position.xz + s.cloudMovement * 2.0) / 80000.0 * s.layers[4].scale, 0.0).b; // 大尺度。
        smallCloud = noiseTexture.SampleLevel((0.000005 / s.layers[4].scale) * coord, 0.0).r; // 小尺度。
        float detailAmplitude = 0.3; // 初始细节振幅。
        float detailFrequency = 0.00002; // 初始细节频率。
        float curlStrength = 1.3; // 初始旋度强度。
        for (int i = 0; i < 3; ++i) // 三层细节。
        {
            float detail = noiseTexture.SampleLevel(coord * detailFrequency + curl * curlStrength, 0.0).r; // 取细节。
            smallCloud -= detail * detailAmplitude; // 从形状里削掉。
            detailAmplitude *= 0.5; // 振幅减半。
            detailFrequency *= 4.0; // 频率翻四倍。
            curlStrength *= 2.7; // 旋度增强。
        }
        smallCloud = abs(largeCloud * -0.4) + smallCloud; // 大尺度偏移。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖减去噪声。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 卷云不使用后面的通用包络。
    }
    if (layerIndex == 3) // 高层云。
    {
        coverage = s.layers[3].coverage + 0.0 * s.rainAmount + 0.0 * s.thunderStrength; // 高层云量。
        largeCloud = noiseTexture.SampleLevel((position.xz + s.cloudMovement * 20.0) / 100000.0 * s.layers[3].scale, 0.0).b; // 大尺度。
        float2 altoCoord = (position.xz + float2(-s.cloudMovement, s.cloudMovement) * 20.0) / 7500.0
            - float2(1.0 - largeCloud, -largeCloud) / 5.0; // 高层云小尺度坐标。
        smallCloud = 1.0 - noiseTexture.SampleLevel(altoCoord * s.layers[3].scale, 0.0).b; // 小尺度。
        smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9 - largeCloud, 0.0, 1.0); // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
        shape *= shape; // 平方收边。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 高层云直接返回。
    }
    if (layerIndex == 1) // 大积云。
    {
        coverage = s.layers[1].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 雨天与雷暴增加云量。
        largeCloud = noiseTexture.SampleLevel((samplePos.zx + s.cloudMovement * 3.0) / 10000.0 * s.layers[1].scale, 0.0).b; // 大尺度。
        smallCloud = noiseTexture.SampleLevel((samplePos.zx - s.cloudMovement * 3.0) / 2500.0 * s.layers[1].scale, 0.0).b; // 小尺度。
        smallCloud = abs(largeCloud * -0.7) + smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    else if (layerIndex == 0) // 小积云。
    {
        coverage = s.layers[0].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 天气加成。
        largeCloud = noiseTexture.SampleLevel((samplePos.xz + s.cloudMovement) / 5000.0 * s.layers[0].scale, 0.0).b; // 大尺度。
        smallCloud = 1.0 - noiseTexture.SampleLevel((samplePos.xz - s.cloudMovement) / 500.0 * s.layers[0].scale, 0.0).r; // 小尺度。
        smallCloud = abs(largeCloud - 0.6) + smallCloud * smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在层内。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 25.0, 1.0), 5.0); // 底部圆角。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-0.5 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 顶部圆角。
    shape = max((shape - 1.0) + topShape * bottomShape, 0.0); // 合成竖直包络。
    if (shape > 0.001) // 有形状才做侵蚀。
    {
        float erodeAmount = 0.5; // 侵蚀强度。
        if (lod < 1) return max(shape - 0.27 * erodeAmount, 0.0); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 侵蚀坐标随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 越高偏移越大。
        float erosion = 0.0; // 侵蚀量。
        float omShape = 1.0 - shape; // 反向形状。
        if (layerIndex == 0) // 小积云侵蚀。
        {
            erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale / 3.0, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
            float falloff = 1.0 - clamp(posToMax / (s.layers[0].tallness / s.layers[0].scale), 0.0, 1.0); // 高度衰减。
            erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale, noiseTexture, 512.0) - falloff)
                * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25); // 第二层侵蚀。
            erosion = erosion * erosion * erosion * erosion; // 四次方收边。
        }
        if (layerIndex == 1) // 大积云侵蚀。
        {
            erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale / 3.571428, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
            float falloff = 1.0 - clamp(posToMax / (s.layers[1].tallness / s.layers[1].scale), 0.0, 1.0); // 高度衰减。
            erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale, noiseTexture, 512.0) - falloff)
                * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5); // 第二层侵蚀。
            erosion = erosion * erosion * erosion * erosion; // 四次方收边。
        }
        return max(shape - erosion * erodeAmount, 0.0); // 减掉侵蚀。
    }
    return 0.0; // 没有形状。
}

// 积雨云形状：返回 `x` 为密度、`y` 为大云标记。
float2 ogxEclipseGetCumulonimbusShape(OgxEclipseCloudSettings s, int lod, float3 position, float minHeight, float maxHeight,
    float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture)
{
    float largeCloud = 0.0; // 大尺度。
    float smallCloud = 0.0; // 小尺度。
    float3 samplePos = position * float3(1.0, 1.0 / 48.0, 1.0) / 4.0; // 取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶距离。
    largeCloud = max(sin((samplePos.x - s.cloudMovement * 10.0) / 2700.0) * cos((samplePos.z - s.cloudMovement * 10.0) / 2700.0), 0.0); // 大尺度波形。
    largeCloud = lerp(max(min(largeCloud - 0.25, 0.5) * 2.0, 0.0), max(min(largeCloud, 0.25) * 4.0, 0.0), s.thunderStrength); // 雷暴时收窄。
    float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraPos)); // 远处才显示积雨云。
    float isLarge = smoothstep(0.0, 1.0, shape); // 大云标记。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 5.0, 1.0), 5.0); // 底部圆角。
    float smallMaxHeight = tallness * 0.45 + minHeight; // 小云顶。
    float shape2 = 0.0; // 第二层形状。
    if (position.y < smallMaxHeight) // 小云只在下半层。
    {
        float smallTallness = smallMaxHeight - minHeight; // 小云厚度。
        float posToMaxSmall = smallMaxHeight - position.y; // 小云到顶距离。
        smallCloud = 1.0 - noiseTexture.SampleLevel((samplePos.xz - s.cloudMovement * 4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r
            * smoothstep(smallMaxHeight, tallness * 0.2 + minHeight, position.y); // 小云噪声。
        shape2 = min(max(1.1 - smallCloud, 0.0) / sqrt(1.1), 1.0) * smoothstep(5000.0, 7000.0, length(position - cameraPos)); // 小云形状。
        shape2 = min(min(shape2, clamp(smallMaxHeight - position.y, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在小云内。
        float smallTopShape = min(max(posToMaxSmall, 0.0) / max(smallTallness, 1.0), 1.0); // 小云顶。
        smallTopShape = min(exp(23.0 * (1.0 - smallTopShape)), 1.0 - pow(1.0 - smallTopShape, 9.0)); // 圆角。
        shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0); // 合成。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在主层内。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-1.0 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 圆角。
    float topShape2 = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 第二顶部归一化。
    topShape2 = min(exp(-0.1 * (1.0 - topShape2)), 1.0 - pow(1.0 - topShape2, 7.0)); // 第二圆角。
    shape = max((shape - 1.0) + topShape * bottomShape + (1.0 - topShape2) * bottomShape, 0.0); // 合成主形状。
    shape = pow(shape, 1.0 + smoothstep(tallness * 0.4 + minHeight, tallness * 0.8 + minHeight, position.y)); // 越高越收。
    shape += shape2; // 加上小云。
    if (s.cumulonimbus == 1) shape *= pow(s.cumulonimbusStrength, lerp(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y))); // 积雨云强度。
    if (shape > 0.001) // 有形状才侵蚀。
    {
        if (lod < 1) return float2(max(shape - 0.27 * 0.5, 0.0), isLarge); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 高度偏移。
        float omShape = 1.0 - shape; // 反向形状。
        float erosion = (1.0 - ogxCloudDensityAtPos(samplePos * 190.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / 4600.0, 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * 580.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0) - falloff)
            * 0.65 * omShape * (1.0 - falloff * 0.5); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion * smoothstep(maxHeight + 40.0, tallness * 0.5 + minHeight, position.y); // 四次方并淡出。
        return float2(max(shape - erosion * 0.5, 0.0), isLarge); // 返回密度与大云标记。
    }
    return float2(0.0, isLarge); // 没有形状。
}
