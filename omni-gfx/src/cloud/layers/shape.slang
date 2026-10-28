/* 层状体积云的形状：哈希、旋度噪声、逐层密度、积雨云与降雨加成；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetCloudShape(settings, 1, 1, position, minHeight, maxHeight, noise);`
设计取舍：每层的高度、厚度、比例与覆盖来自结构体，函数按层号分支，采样顺序与参考一致。 */

// 二维哈希：把格坐标打散成两个零到一的随机数，供云形状使用。
float2 ogxLayersHash2(float2 p)
{
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973)); // 三个不同频率的搅动。
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33); // 互相混合。
    return fract((float2(p3.x, p3.x) + float2(p3.y, p3.z)) * float2(p3.z, p3.y)); // 取两个独立分量。
}

// 归一化哈希向量：把格坐标变成一个单位方向，供 Perlin 梯度使用。
// 把二维哈希值归一到零到一，避免负值让噪声出现暗带。
float2 ogxLayersNormalizeHash(float2 p)
{
    return normalize(ogxLayersHash2(p) - 0.5); // 中心化后单位化。
}

// Perlin 梯度：返回解析梯度，供旋度噪声直接使用。
// 由哈希选二维梯度方向，供 Perlin 噪声生成云形状。
float2 ogxLayersPerlinGradient(float2 coord)
{
    float2 i = floor(coord); // 整数格。
    float2 f = fract(coord); // 格内偏移。
    float2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 参考实现的导数，虽然不是严格数学导数但画面更自然。
    float2 g0 = ogxLayersNormalizeHash(i); // 左下梯度。
    float2 g1 = ogxLayersNormalizeHash(i + float2(1.0, 0.0)); // 右下梯度。
    float2 g2 = ogxLayersNormalizeHash(i + float2(0.0, 1.0)); // 左上梯度。
    float2 g3 = ogxLayersNormalizeHash(i + float2(1.0, 1.0)); // 右上梯度。
    float v0 = dot(g0, f); // 左下贡献。
    float v1 = dot(g1, f - float2(1.0, 0.0)); // 右下贡献。
    float v2 = dot(g2, f - float2(0.0, 1.0)); // 左上贡献。
    float v3 = dot(g3, f - float2(1.0, 1.0)); // 右上贡献。
    float2 omu = 1.0 - u; // 反向平滑权重。
    return float2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的梯度。
}

// 二维旋度：把梯度旋转九十度，得到无散度的流动场。
float2 ogxLayersCurl2D(float2 coord)
{
    float2 gradient = ogxLayersPerlinGradient(coord); // 取梯度。
    return float2(gradient.y, -gradient.x); // 旋转九十度。
}

// 极光的三维噪声：四个平移后的哈希值按距离加权，得到柔和的团块。
float ogxLayersTriNoise2d(float2 coord, float time)
{
    float2 p = coord * 0.5; // 整体缩放。
    float2 i = floor(p); // 整数格。
    float2 f = fract(p); // 格内偏移。
    float2 u = f * f * (3.0 - 2.0 * f); // 平滑。
    float a = ogxLayersHash2(i).x; // 左下。
    float b = ogxLayersHash2(i + float2(1.0, 0.0)).x; // 右下。
    float c = ogxLayersHash2(i + float2(0.0, 1.0)).x; // 左上。
    float d = ogxLayersHash2(i + float2(1.0, 1.0)).x; // 右上。
    float value = lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y); // 双线性插值。
    float wave = sin(time + value * 6.28318530718) * 0.5 + 0.5; // 时间相位。
    return value * wave; // 噪声乘相位。
}

// 三维噪声采样：把云坐标折到 512 见方噪声图的一列，再按纵向小数插值两行。
// 参考把这一步写成独立函数；库版本把噪声图显式传入，算式与常数逐项保留。
float ogxLayersDensityAtPos(float3 pos, Sampler2D noiseTexture)
{
    pos /= 18.0; // 换成噪声格坐标。
    pos.xz *= 0.5; // 横向压缩，让云细节更宽。
    float3 p = floor(pos); // 所在格子的整数坐标。
    float3 f = fract(pos); // 格内小数位置。
    float2 uv = p.xz + f.xz + p.y * float2(0.0, 193.0); // 纵向每层错开一行，避免层间条纹。
    float2 coord = uv / 512.0; // 换成零到一纹理坐标。
    float2 xy = noiseTexture.SampleLevel(coord, 0.0).yx; // 图里存的是两层密度。
    return lerp(xy.r, xy.g, f.y); // 按纵向小数在两层之间插值。
}

// 单层云形状：按层号走参考实现的分支，返回零到一的密度。
// 云层形状与云影的提前声明：入口放在定义之前。
float ogxLayersGetCloudShape(OgxLayersCloudSettings s, int layerIndex, int lod, float3 position,
    float minHeight, float maxHeight, Sampler2D noiseTexture);
float ogxLayersGetCloudShadow(OgxLayersCloudSettings s, float3 playerPos, float3 sunVector,
    int cloudShadowAmount, float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture);

// 层状云层形状入口：参考签名只带层号、细节层级、位置与高度范围，云设置与噪声由宿主提供。
float ogxLayersGetCloudShapeReference(int layerIndex, int lod, float3 position, float minHeight, float maxHeight,
    OgxLayersCloudSettings s, Sampler2D noiseTexture)
{
    return ogxLayersGetCloudShape(s, layerIndex, lod, position, minHeight, maxHeight, noiseTexture);
}

// 层状云影入口：参考签名只给世界位置与太阳方向，云设置、相机与噪声由宿主提供。
float ogxLayersGetCloudShadowReference(float3 playerPos, float3 sunVector, OgxLayersCloudSettings s,
    int cloudShadowAmount, float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture)
{
    return ogxLayersGetCloudShadow(s, playerPos, sunVector, cloudShadowAmount, cumulonimbusScale,
        cameraPos, noiseTexture);
}

// 云形状的实际定义：把层号、覆盖率与上下界交给噪声采样，返回该层的密度。
float ogxLayersGetCloudShape(OgxLayersCloudSettings s, int layerIndex, int lod, float3 position,
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
        float2 curl = ogxLayersCurl2D(0.00002 * coord) * 0.5
                    + ogxLayersCurl2D(0.00005 * coord) * 0.25
                    + ogxLayersCurl2D(0.00018 * coord) * 0.125; // 三层旋度。
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
float2 ogxLayersGetCumulonimbusShape(OgxLayersCloudSettings s, int lod, float3 position, float minHeight, float maxHeight,
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

// 层状云形状：按云层选择覆盖率与噪声尺度，先算平面形状，再按高度裁剪与侵蚀。
// 参考签名是层号、细节层级、位置与上下界；噪声图、覆盖率与天气参数显式追加在末尾。
// 为什么用 switch：参考按层号分支，每层采样次数与顺序不同，合并会改变采样序列。
float ogxLayersCloudShapeLayer(int layerIndex, int lod, float3 position, float minHeight, float maxHeight,
    Sampler2D noiseTexture, float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage,
    float rainAmount, float thunderStrength, float cloudMovement)
{
    float coverage = 0.0; // 本层覆盖率。
    float shape = 0.0; // 平面形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    float3 samplePos = position * float3(0.25, 0.005, 0.25); // 细节采样用的压缩坐标。
    float tallness = maxHeight - minHeight; // 云层厚度。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    switch (layerIndex)
    {
        default: { break; } // 未知层不产生云。
        case 3: { // 高层云：大尺度覆盖加一层细节。
            coverage = altostratusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = noiseTexture.SampleLevel((position.xz + cloudMovement * 20.0) / 100000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - noiseTexture.SampleLevel(((position.xz + float2(-cloudMovement, cloudMovement) * 20.0) / 7500.0 - float2(1.0 - largeCloud, -largeCloud) / 5.0) * 1.0, 0.0).b;
            smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9 - largeCloud, 0.0, 1.0);
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            shape *= shape;
            if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部薄层压掉。
            return shape;
        }
        case 1: { // 大积云：两张大尺度噪声相加。
            coverage = largeCumulusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = noiseTexture.SampleLevel((samplePos.zx + cloudMovement * 3.0) / 10000.0 * 1.0, 0.0).b;
            smallCloud = noiseTexture.SampleLevel((samplePos.zx - cloudMovement * 3.0) / 2500.0 * 1.0, 0.0).b;
            smallCloud = abs(largeCloud * -0.7) + smallCloud;
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            break;
        }
        case 0: { // 小积云：大尺度边缘直接参与形状。
            coverage = smallCumulusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = noiseTexture.SampleLevel((samplePos.xz + cloudMovement) / 5000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - noiseTexture.SampleLevel((samplePos.xz - cloudMovement) / 500.0 * 1.0, 0.0).r;
            smallCloud = abs(largeCloud - 0.6) + smallCloud * smallCloud;
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            break;
        }
    }
    shape = min(min(shape, clamp(posToMax, 0, 1)), 1.0 - clamp(minHeight - position.y, 0, 1)); // 上下边界夹紧。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 25.0, 1.0), 5.0); // 底部圆角。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部收口。
    topShape = min(exp(-0.5 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0));
    shape = max((shape - 1.0) + topShape * bottomShape, 0.0); // 竖直包络。
    if (shape > 0.001) // 只在有云的位置做细节侵蚀。
    {
        float erodeAmount = 0.5; // 侵蚀强度。
        if (lod < 1) return max(shape - 0.27 * erodeAmount, 0.0); // 低细节层直接给均匀侵蚀。
        samplePos.xz -= cloudMovement / 4.0; // 细节层随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 越靠上越斜，云顶被吹偏。
        float erosion = 0.0; // 侵蚀量。
        float omShape = 1.0 - shape; // 形状的补值。
        switch (layerIndex)
        {
            default: { break; }
            case 0: { // 小积云细节。
                erosion += (1.0 - ogxLayersDensityAtPos(samplePos * 600.0 * 1.0 / 3.0, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (130.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxLayersDensityAtPos(samplePos * 600.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
            case 1: { // 大积云细节。
                erosion += (1.0 - ogxLayersDensityAtPos(samplePos * 250.0 * 1.0 / 3.571428, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (280.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxLayersDensityAtPos(samplePos * 250.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
        }
        return max(shape - erosion * erodeAmount, 0.0);
    }
    else return 0.0;
}

// 层状积雨云形状：大尺度正弦云团叠加很小的塔状云，输出形状与大云标记。
// 参考签名是细节层级、位置与上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加。
float2 ogxLayersCumulonimbusShapeLayer(int lod, float3 position, float minHeight, float maxHeight,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength)
{
	float largeCloud = 0.0;
	float smallCloud = 0.0;

	float3 samplePos = position*float3(1.0, 1.0/48.0, 1.0)/4.0;
	float tallness = maxHeight - minHeight;
	float posToMax = maxHeight - position.y;

	float cumulonimbusScale = 1.0;
	                                                                                                            
	
	                                     

	                                                 
	                                                                                                                              

	largeCloud = (max(sin((samplePos.x - cloudMovement*10.0)/2700) * cos((samplePos.z - cloudMovement*10.0)/2700), 0.0));
	largeCloud = lerp(max(min(largeCloud - 0.25, 0.5)*2.0, 0.0), max(min(largeCloud, 0.25)*4.0, 0.0), thunderStrength);
	float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraWorldPos));
	                           
	
	float isLarge = smoothstep(0.0, 1.0, shape);
	                 

	float bottomShape = 1.0-pow(1.0-min(max(position.y-minHeight,0.0) / 5.0, 1.0), 5.0);


	float smallMaxHeight = (tallness*0.45 + minHeight);

	float shape2 = 0.0;
	if (position.y < smallMaxHeight) {
	float smallTallness = smallMaxHeight - minHeight;
	float posToMaxSmall = smallMaxHeight - position.y;

	smallCloud = 1.0-noiseTexture.SampleLevel((samplePos.xz - cloudMovement*4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r * smoothstep(smallMaxHeight, tallness*0.2+minHeight, position.y);
	
	shape2 = min(max(1.1 - smallCloud,0.0)/sqrt(1.1),1.0)  * smoothstep(5000.0, 7000.0, length(position - cameraWorldPos));

	shape2 = min(min(shape2, clamp(smallMaxHeight - position.y,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float smallTopShape = min(max(posToMaxSmall,0.0) / max(smallTallness,1.0),1.0);
	smallTopShape = min(exp(23 * (1.0-smallTopShape)), 	1.0-pow(1.0-smallTopShape,9.0));

	shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0);
	}


	shape = min(min(shape, clamp(posToMax,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float topShape = min(max(posToMax,0.0) / max(tallness,1.0),1.0);
	topShape = min(exp(-1.0 * (1.0-topShape)), 	1.0-pow(1.0-topShape,5.0));

	float topShape2 = min(max(posToMax,0.0) / max(tallness,1.0),1.0); 

	topShape2 = min(exp(-0.1 * (1.0-topShape2)), 	1.0-pow(1.0-topShape2,7.0));
	
	shape = max((shape - 1.0) + topShape * bottomShape + (1- topShape2) * bottomShape, 0.0);

	shape = pow(shape, 1 + smoothstep(tallness*0.4+minHeight, tallness*0.8+minHeight, position.y));

	shape += shape2;


		shape *= pow(cumulonimbusStrength, lerp(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y)));


	if(shape > 0.001){
		if (lod < 1) return float2(max(shape - 0.27*0.5,0.0), isLarge);

		samplePos.xz -= cloudMovement/4.0;
		samplePos.xz += pow( max(position.y - (minHeight+20.0), 0.0) / (max(tallness,1.0)*0.20), 1.5);

		float omShape = 1.0 - shape;

		float erosion = (1.0 - ogxLayersDensityAtPos(samplePos * 190 * cumulonimbusScale*0.05, noiseTexture)) * sqrt(omShape);

		float falloff = 1.0 - clamp((posToMax)/4600.0,0.0,1.0);

		erosion += abs(ogxLayersDensityAtPos(samplePos * 580 * cumulonimbusScale*0.05, noiseTexture) - falloff) * 0.65 * (omShape) * (1.0-falloff*0.5);

		erosion = erosion*erosion*erosion*erosion*smoothstep(maxHeight+40.0, tallness*0.5+minHeight, position.y);
		

		return float2(max(shape - erosion*0.5,0.0), isLarge);
	} else return float2(0.0, isLarge);
}

// 层状云降雨加成：当前云量加上雨与雷带来的额外覆盖，限制在一以内。
// 参考把雨强与雷强当全局量；库版本显式接收，算式与常数不变。
float ogxLayersGetRainDensity(float currentDensity, float rainAmount, float thunderStrength)
{
    float extraDensity = min(currentDensity + rainAmount * 0.1 + thunderStrength * 0.1, 1.0); // 雨天云量更满。
    return extraDensity; // 交回夹紧后的覆盖率。
}
