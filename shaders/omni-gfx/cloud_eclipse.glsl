/*
生成文件：Eclipse 体积云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要 Eclipse 风格层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud_eclipse.glsl` 引入。
可复制示例：
    OgxEclipseCloudSettings s = ...; // 填云层高度、比例、覆盖与天气。
    vec4 cloud = ogxEclipseGetVolumetricClouds(viewPos, dither, sunVector, moonVector, ...);
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
*/
#ifndef OGX_CLOUD_ECLIPSE_INCLUDED
#define OGX_CLOUD_ECLIPSE_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/cloud.glsl"
// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxEclipseCloudLayer
{
    float height; // 云底高度，米。
    float tallness; // 云层厚度，米。
    float scale; // 世界坐标到云坐标的比例。
    float distance; // 这一层的可见距离，米。
    float coverage; // 云量，零到一。
    float rainDensity; // 雨天密度。
    float detail; // 高频侵蚀尺度。
};

// 体积云的全部环境输入：层数据、天气、太阳与闪电。
struct OgxEclipseCloudSettings
{
    OgxEclipseCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
    float cloudMovement; // 云的水平位移，米。
    float rainAmount; // 降雨强度。
    float thunderStrength; // 雷暴强度。
    float sunElevation; // 太阳高度角正弦。
    float moonElevation; // 月亮高度角正弦。
    float cumulonimbusStrength; // 积雨云强度。
    float distanceFogScale; // 距离雾的指数系数，通常为负。
    float skyBrightness; // 天空亮度。
    float lightningFlash; // 当前闪电亮度。
    float lightningFade; // 闪电衰减。
    float cumulonimbusLightningBrightness; // 积雨云闪电亮度。
    float auroraAmount; // 极光强度，零表示没有极光。
    vec3 auroraLighting; // 极光颜色，调用方按自己的极光模型算好。
    vec4 lightningBoltPosition; // 普通闪电位置，第四个分量是强度。
    vec3 cumulonimbusLightningColor; // 积雨云闪电颜色。
    int cumulonimbus; // 是否启用积雨云，零关闭。
    int lightningEnabled; // 是否启用积雨云闪电。
};

// 二维哈希：把格坐标打散成两个零到一的随机数。
vec2 ogxEclipseHash2(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973)); // 三个不同频率的搅动。
    p3 += dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33); // 互相混合。
    return fract((vec2(p3.x, p3.x) + vec2(p3.y, p3.z)) * vec2(p3.z, p3.y)); // 取两个独立分量。
}

// 归一化哈希向量：把格坐标变成一个单位方向，供 Perlin 梯度使用。
vec2 ogxEclipseNormalizeHash(vec2 p)
{
    return normalize(ogxEclipseHash2(p) - 0.5); // 中心化后单位化。
}

// Perlin 梯度：返回解析梯度，供旋度噪声直接使用。
vec2 ogxEclipsePerlinGradient(vec2 coord)
{
    vec2 i = floor(coord); // 整数格。
    vec2 f = fract(coord); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 参考实现的导数，虽然不是严格数学导数但画面更自然。
    vec2 g0 = ogxEclipseNormalizeHash(i); // 左下梯度。
    vec2 g1 = ogxEclipseNormalizeHash(i + vec2(1.0, 0.0)); // 右下梯度。
    vec2 g2 = ogxEclipseNormalizeHash(i + vec2(0.0, 1.0)); // 左上梯度。
    vec2 g3 = ogxEclipseNormalizeHash(i + vec2(1.0, 1.0)); // 右上梯度。
    float v0 = dot(g0, f); // 左下贡献。
    float v1 = dot(g1, f - vec2(1.0, 0.0)); // 右下贡献。
    float v2 = dot(g2, f - vec2(0.0, 1.0)); // 左上贡献。
    float v3 = dot(g3, f - vec2(1.0, 1.0)); // 右上贡献。
    vec2 omu = 1.0 - u; // 反向平滑权重。
    return vec2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的梯度。
}

// 二维旋度：把梯度旋转九十度，得到无散度的流动场。
vec2 ogxEclipseCurl2D(vec2 coord)
{
    vec2 gradient = ogxEclipsePerlinGradient(coord); // 取梯度。
    return vec2(gradient.y, -gradient.x); // 旋转九十度。
}

// 极光的三维噪声：四个平移后的哈希值按距离加权，得到柔和的团块。
float ogxEclipseTriNoise2d(vec2 coord, float time)
{
    vec2 p = coord * 0.5; // 整体缩放。
    vec2 i = floor(p); // 整数格。
    vec2 f = fract(p); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑。
    float a = ogxEclipseHash2(i).x; // 左下。
    float b = ogxEclipseHash2(i + vec2(1.0, 0.0)).x; // 右下。
    float c = ogxEclipseHash2(i + vec2(0.0, 1.0)).x; // 左上。
    float d = ogxEclipseHash2(i + vec2(1.0, 1.0)).x; // 右上。
    float value = mix(mix(a, b, u.x), mix(c, d, u.x), u.y); // 双线性插值。
    float wave = sin(time + value * 6.28318530718) * 0.5 + 0.5; // 时间相位。
    return value * wave; // 噪声乘相位。
}

// 单层云形状：按层号走参考实现的分支，返回零到一的密度。
float ogxEclipseGetCloudShape(OgxEclipseCloudSettings s, int layerIndex, int lod, vec3 position,
    float minHeight, float maxHeight, sampler2D noiseTexture)
{
    float coverage = 0.0; // 云量。
    float shape = 0.0; // 形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    vec3 samplePos = position * vec3(0.25, 0.005, 0.25); // 形状取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    if (layerIndex == 4) // 卷云。
    {
        coverage = s.layers[4].coverage; // 卷云量。
        vec2 coord = position.zx + 6.0 * s.cloudMovement; // 卷云坐标。
        vec2 curl = ogxEclipseCurl2D(0.00002 * coord) * 0.5
                    + ogxEclipseCurl2D(0.00005 * coord) * 0.25
                    + ogxEclipseCurl2D(0.00018 * coord) * 0.125; // 三层旋度。
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 2.0) / 80000.0 * s.layers[4].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (0.000005 / s.layers[4].scale) * coord, 0.0).r; // 小尺度。
        float detailAmplitude = 0.3; // 初始细节振幅。
        float detailFrequency = 0.00002; // 初始细节频率。
        float curlStrength = 1.3; // 初始旋度强度。
        for (int i = 0; i < 3; ++i) // 三层细节。
        {
            float detail = textureLod(noiseTexture, coord * detailFrequency + curl * curlStrength, 0.0).r; // 取细节。
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
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 20.0) / 100000.0 * s.layers[3].scale, 0.0).b; // 大尺度。
        vec2 altoCoord = (position.xz + vec2(-s.cloudMovement, s.cloudMovement) * 20.0) / 7500.0
            - vec2(1.0 - largeCloud, -largeCloud) / 5.0; // 高层云小尺度坐标。
        smallCloud = 1.0 - textureLod(noiseTexture, altoCoord * s.layers[3].scale, 0.0).b; // 小尺度。
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
        largeCloud = textureLod(noiseTexture, (samplePos.zx + s.cloudMovement * 3.0) / 10000.0 * s.layers[1].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (samplePos.zx - s.cloudMovement * 3.0) / 2500.0 * s.layers[1].scale, 0.0).b; // 小尺度。
        smallCloud = abs(largeCloud * -0.7) + smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    else if (layerIndex == 0) // 小积云。
    {
        coverage = s.layers[0].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 天气加成。
        largeCloud = textureLod(noiseTexture, (samplePos.xz + s.cloudMovement) / 5000.0 * s.layers[0].scale, 0.0).b; // 大尺度。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement) / 500.0 * s.layers[0].scale, 0.0).r; // 小尺度。
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
vec2 ogxEclipseGetCumulonimbusShape(OgxEclipseCloudSettings s, int lod, vec3 position, float minHeight, float maxHeight,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float largeCloud = 0.0; // 大尺度。
    float smallCloud = 0.0; // 小尺度。
    vec3 samplePos = position * vec3(1.0, 1.0 / 48.0, 1.0) / 4.0; // 取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶距离。
    largeCloud = max(sin((samplePos.x - s.cloudMovement * 10.0) / 2700.0) * cos((samplePos.z - s.cloudMovement * 10.0) / 2700.0), 0.0); // 大尺度波形。
    largeCloud = mix(max(min(largeCloud - 0.25, 0.5) * 2.0, 0.0), max(min(largeCloud, 0.25) * 4.0, 0.0), s.thunderStrength); // 雷暴时收窄。
    float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraPos)); // 远处才显示积雨云。
    float isLarge = smoothstep(0.0, 1.0, shape); // 大云标记。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 5.0, 1.0), 5.0); // 底部圆角。
    float smallMaxHeight = tallness * 0.45 + minHeight; // 小云顶。
    float shape2 = 0.0; // 第二层形状。
    if (position.y < smallMaxHeight) // 小云只在下半层。
    {
        float smallTallness = smallMaxHeight - minHeight; // 小云厚度。
        float posToMaxSmall = smallMaxHeight - position.y; // 小云到顶距离。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement * 4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r
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
    if (s.cumulonimbus == 1) shape *= pow(s.cumulonimbusStrength, mix(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y))); // 积雨云强度。
    if (shape > 0.001) // 有形状才侵蚀。
    {
        if (lod < 1) return vec2(max(shape - 0.27 * 0.5, 0.0), isLarge); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 高度偏移。
        float omShape = 1.0 - shape; // 反向形状。
        float erosion = (1.0 - ogxCloudDensityAtPos(samplePos * 190.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / 4600.0, 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * 580.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0) - falloff)
            * 0.65 * omShape * (1.0 - falloff * 0.5); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion * smoothstep(maxHeight + 40.0, tallness * 0.5 + minHeight, position.y); // 四次方并淡出。
        return vec2(max(shape - erosion * 0.5, 0.0), isLarge); // 返回密度与大云标记。
    }
    return vec2(0.0, isLarge); // 没有形状。
}

// 闪电位置：在云层半径内取一个随机方向，并确认那里确实有积雨云。
vec3 ogxEclipseGetLightningPosition(OgxEclipseCloudSettings s, float minHeight, float maxHeight, float cumulonimbusScale,
    vec3 cameraPos, sampler2D noiseTexture)
{
    float angle = fract(sin(dot(vec2(s.lightningBoltPosition.w), vec2(12.9898, 78.233))) * 43758.5453) * 6.28318530718; // 随机角。
    float rMin = 7000.0; // 内半径。
    float rMax = 13000.0; // 外半径。
    float radius = sqrt(mix(rMin * rMin, rMax * rMax, fract(sin(dot(vec2(s.lightningBoltPosition.w + 1.0), vec2(12.9898, 78.233))) * 43758.5453))); // 面积均匀的半径。
    vec3 lightningPos = vec3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 初始位置。
    float shapeAtLightning = ogxEclipseGetCumulonimbusShape(s, 0, lightningPos, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x; // 该处云密度。
    lightningPos.y = minHeight + (maxHeight - minHeight) * 0.48; // 参考实现把高度固定到 0.48。
    if (shapeAtLightning < 0.1) lightningPos = vec3(0.0); // 没有云就不闪。
    return lightningPos; // 交回相机相对位置。
}

// 行星阴影：太阳越低，主岛下方越暗。
float ogxEclipseGetPlanetShadow(vec3 playerPos, vec3 sunVector)
{
    float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / max(sunVector.y * 0.1, 0.0)), 0.0) / 100.0, 1.0); // 高度阈值。
    planetShadow = mix(pow(1.0 - pow(1.0 - planetShadow, 2.0), 2.0), 1.0, pow(max(sunVector.y, 0.0), 2.0)); // 太阳越高阴影越少。
    return planetShadow; // 交回阴影权重。
}

// 云影：把地面点沿太阳方向投到各层云，按层密度累加。
float ogxEclipseGetCloudShadow(OgxEclipseCloudSettings s, vec3 playerPos, vec3 sunVector, int cloudShadowAmount,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalShadow = ogxEclipseGetPlanetShadow(playerPos, sunVector); // 行星阴影。
    vec3 startPosition = playerPos; // 投影起点。
    vec3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向到单位高度的位移。
    if (cloudShadowAmount > 0) // 有云影才计算。
    {
        float cloudShadows = 0.0; // 云影累加。
        startPosition = playerPos + startOffset * max((s.layers[0].height + 20.0) - playerPos.y, 0.0); // 投到小积云下段。
        cloudShadows = ogxEclipseGetCloudShape(s, 0, 0, startPosition, s.layers[0].height,
            s.layers[0].height + s.layers[0].tallness / s.layers[0].scale, noiseTexture) * s.layers[0].rainDensity; // 小积云。
        startPosition = playerPos + startOffset * max((s.layers[1].height + 30.0) - playerPos.y, 0.0); // 投到大积云下段。
        cloudShadows += ogxEclipseGetCloudShape(s, 1, 0, startPosition, s.layers[1].height,
            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * s.layers[1].rainDensity; // 大积云。
        startPosition = playerPos + startOffset * max(s.layers[3].height - playerPos.y, 0.0); // 投到高层云。
        cloudShadows += ogxEclipseGetCloudShape(s, 3, 0, startPosition, s.layers[3].height, s.layers[3].height + 5.0,
            noiseTexture) * s.layers[3].rainDensity * (1.0 - abs(sunVector.y)); // 高层云。
        float distanceFactor = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), sunVector))), 45.0, 90.0) - 45.0; // 太阳角度。
        startPosition = playerPos + sunVector * mix(7000.0, 18000.0, distanceFactor / 45.0); // 投到积雨云。
        cloudShadows += ogxEclipseGetCumulonimbusShape(s, 0, startPosition, 600.0, 4600.0 + startPosition.y,
            cumulonimbusScale, cameraPos, noiseTexture).x; // 积雨云。
        cloudShadows *= float(cloudShadowAmount) / 100.0; // 按强度缩放。
        totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云越厚阴影越黑。
    }
    return totalShadow; // 交回总阴影。
}

// 步进起点：按相机在云层中的位置把射线压到平面，避免从错误的一侧开始。
vec3 ogxEclipseGetRayOrigin(vec3 rayStartPos, vec3 cameraPos, float dither, float minHeight, float maxHeight)
{
    vec3 cloudDist = vec3(1.0); // 水平与竖直的缩放。
    cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
        clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 越靠近云层水平步长越小。
    float flip = mix(max(cameraPos.y - maxHeight, 0.0), max(minHeight - cameraPos.y, 0.0), clamp(rayStartPos.y, 0.0, 1.0)); // 上下翻转。
    return rayStartPos * dither + cameraPos + (rayStartPos / length(rayStartPos / cloudDist)) * flip; // 压到平面并加抖动。
}

// 云的相函数：按 `mode` 选择 Henyey-Greenstein、Cornette-Shanks 或 HG-Draine。
float ogxEclipsePhaseCloud(float x, float g, int mode)
{
    if (mode == 1) // Cornette-Shanks。
    {
        return (3.0 * (1.0 - g * g) * (1.0 + x * x)) / (25.133 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * x, 1.5)); // 参考实现系数 25.133。
    }
    if (mode == 2) // HG-Draine。
    {
        const float a = 0.9; // 前向权重。
        float gg = g * g; // g 的平方。
        return ((1.0 - gg) * (1.0 + a * x * x)) / (4.0 * (1.0 + (a * (1.0 + 2.0 * gg)) / 3.0) * 3.1415926 * pow(1.0 + gg - 2.0 * g * x, 1.5)); // 参考实现公式。
    }
    float gg = g * g; // 默认 Henyey-Greenstein。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现除以 3.14。
}

// 朝光散射：沿光方向取几步云密度，层数与步长按层号决定。
float ogxEclipseGetCloudScattering(OgxEclipseCloudSettings s, int layerIndex, vec3 rayPosition, vec3 sunVector,
    vec3 moonVector, float dither, float minHeight, float maxHeight, float density, float cumulonimbusScale,
    float sunVisibility, float moonVisibility, vec3 cameraPos, sampler2D noiseTexture)
{
    int samples = 3; // 默认三步。
    if (layerIndex == 2) samples = 7; // 积雨云七步。
    if (layerIndex == 3 || layerIndex == 4) samples = 2; // 高层云与卷云两步。
    int lod = 0; // 光照取样用低细节。
    float shadow = 0.0; // 遮挡累加。
    vec3 shadowRayPosition = vec3(0.0); // 采样位置。
    float isLarge = 80.0; // 积雨云步长。
    vec3 lightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (layerIndex == 3 || layerIndex == 4) // 平面云沿日月方向。
        {
            shadowRayPosition = rayPosition + sunVector * sunVisibility * (0.25 + float(i) * dither) * 200.0
                + moonVector * moonVisibility * (0.25 + float(i) * dither) * 200.0; // 沿日月方向取样。
        }
        else if (layerIndex == 0 || layerIndex == 1) // 积云沿混合方向。
        {
            shadowRayPosition = rayPosition + lightVec * (0.25 + float(i) + dither) * 20.0; // 小步长。
        }
        else if (layerIndex == 2) // 积雨云大步长。
        {
            shadowRayPosition = rayPosition + lightVec * (0.5 + float(i) + dither) * isLarge; // 大步长。
            isLarge *= 1.374; // 每步放大。
        }
        if (layerIndex != 2) shadow += ogxEclipseGetCloudShape(s, layerIndex, lod, shadowRayPosition, minHeight, maxHeight, noiseTexture) * density; // 普通云。
        else shadow += ogxEclipseGetCumulonimbusShape(s, lod, shadowRayPosition, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x * density; // 积雨云。
    }
    return shadow; // 交回遮挡量。
}

// 云的光照：直射按 Beer 定律衰减，前后散射按粉末效应插值，间接光按形状抬升。
vec3 ogxEclipseGetCloudLighting(int layerIndex, float shape, float shapeFaded, float sunShadowMask, vec3 directLightCol,
    vec3 directLightCol2, float indirectShadowMask, vec3 indirectLightCol, vec3 rayPosition, float backScatterPhase,
    vec4 phaseLevels, float backScatterPhase2, vec4 phaseLevels2)
{
    vec3 heightScal = vec3(mix(1.0, 0.5, clamp(rayPosition.y, 0.0, 7000.0) / 7000.0)); // 高度对光色的压缩。
    directLightCol = pow(directLightCol, heightScal); // 直射颜色按高度压暗。
    directLightCol2 = pow(directLightCol2, heightScal); // 第二直射同样。
    float beerCoef = -4.0; // Beer 系数。
    float powder = min(exp(beerCoef * exp(beerCoef * shapeFaded)) * 3.5, 1.0); // 粉末效应。
    float backscatter = powder * backScatterPhase; // 后向散射。
    float forwardscatter = mix(mix(phaseLevels.x, phaseLevels.y, powder), mix(phaseLevels.z, phaseLevels.w, powder), powder); // 四档相函数插值。
    float backscatter2 = powder * backScatterPhase2; // 第二后向。
    float forwardscatter2 = mix(mix(phaseLevels2.x, phaseLevels2.y, powder), mix(phaseLevels2.z, phaseLevels2.w, powder), powder); // 第二前向。
    float expBeer = 6.28 * exp((beerCoef - 1.0) * sunShadowMask); // 直射透过率。
    vec3 directScattering = expBeer * directLightCol * (forwardscatter + backscatter); // 太阳直射。
    directScattering += expBeer * directLightCol2 * (forwardscatter2 + backscatter2); // 月亮直射。
    vec3 indirectScattering = indirectLightCol * mix(1.0, exp2(-5.0 * shape), indirectShadowMask * indirectShadowMask); // 间接光。
    return indirectScattering + directScattering; // 合成。
}

// 单层云的步进：参考实现的主循环，逐层处理平面云与积云两条路径。
// `cloudPlaneDistance` 的 `x` 是最近可见云的距离，`y` 是混合权重；由调用方按层合并。
vec4 ogxEclipseRaymarchCloud(OgxEclipseCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,
    float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,
    vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,
    inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,
    vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    vec3 color = vec3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 一步的世界长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex == 3 || layerIndex == 4) // 平面云路径。
    {
        float density = 0.0; // 这一层的密度。
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        if (layerIndex == 3) density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 高层云。
        else density = s.layers[4].rainDensity * smoothstep(s.layers[4].distance, s.layers[4].distance * 0.5, length(newPos)); // 卷云。
        if (density == 0.0) return vec4(color, totalAbsorbance); // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(cameraPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面的哪一侧。
        if (!deferred && length(newPos) > referenceDistance) return vec4(color, totalAbsorbance); // 世界几何挡住云。
        if (ifAboveOrBelowPlane) return vec4(color, totalAbsorbance); // 背向云层的一侧不步进。
        float shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 取样形状。
        float shapeWithDensity = shape * density; // 乘密度。
        if (shapeWithDensity > mix(1e-5, 0.06, dither)) // 记录最近可见云。
        {
            cloudPlaneDistance.x = length(newPos);
            cloudPlaneDistance.y = 0.0;
        }
        if (shapeWithDensity > 1e-5) // 有云才做光照。
        {
            float sunShadowMask = ogxEclipseGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture) * (1.0 - abs(sunVector.y)); // 朝光遮挡。
            float indirectShadowMask = 0.5; // 平面云间接光固定半量。
            vec3 lighting = ogxEclipseGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensity, sunShadowMask,
                sunScattering, moonScattering, indirectShadowMask, skyScattering, rayPosition, backScatterPhase, phaseLevels,
                backScatterPhase2, phaseLevels2); // 光照。
            newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视的距离压缩。
            float distancefog = exp2(0.4 * s.distanceFogScale * length(newPos.xz)); // 距离雾。
            vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
            lighting = lighting * distancefog + atmosphereHaze; // 混进雾。
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 这一段的透过率。
            color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 按剩余透过率累加。
            totalAbsorbance *= densityCoeff; // 更新透过率。
        }
        return vec4(color, totalAbsorbance); // 平面云只取一个样本。
    }
    if (layerIndex < 3) // 积云路径。
    {
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(newPos)); // 小积云距离淡出。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(newPos)); // 大积云距离淡出。
        if (layerIndex == 2) density = 0.8; // 积雨云固定密度。
        if (density < 0.01) return vec4(color, totalAbsorbance); // 密度太低跳过。
        float skylightOcclusion = 1.0; // 上层云对天空光的遮挡。
        if (layerIndex == 0) // 小积云会被大积云遮住天光。
        {
            float upperLayerOcclusion = ogxEclipseGetCloudShape(s, 1, 0, rayPosition + vec3(0.0, 1.0, 0.0)
                * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0), s.layers[1].height, s.layers[1].height + 100.0, noiseTexture); // 上层形状。
            skylightOcclusion = mix(mix(0.0, 0.2, densityLarge), 1.0, pow(1.0 - upperLayerOcclusion * densityLarge, 2.0)); // 混合天光。
        }
        vec3 lightningPos = vec3(0.0); // 积雨云闪电位置。
        if (s.lightningEnabled > 0 && layerIndex == 2) lightningPos = ogxEclipseGetLightningPosition(s, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 只有积雨云取闪电位。
        vec3 mainLightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
        float tallness = maxHeight - minHeight; // 层厚。
        bool maxFogDistReached = false; // 是否已经记录最近云。
        for (int i = 0; i < samples; i++) // 主步进循环。
        {
            newPos = rayPosition - cameraPos; // 更新相对位置。
            if (!deferred && length(newPos) > referenceDistance) break; // 世界几何挡住后面。
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 在云层包围盒内。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxEclipseGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云标记放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 按高度淡出。
                if (shapeWithDensityFaded > densityThresholdCheck && !maxFogDistReached) // 记录最近可见云。
                {
                    cloudPlaneDistance.x = length(newPos);
                    cloudPlaneDistance.y = 0.0;
                    maxFogDistReached = true;
                }
                if (shapeWithDensityFaded > 1e-5) // 有云才继续。
                {
                    vec3 shadow = vec3(1.0); // 地形阴影默认全亮。
                    if (terrainShadowOnClouds) // 开启地形阴影时投到阴影图。
                    {
                        vec3 fragPosition = ogxMatrixMulPoint(shadowView, newPos) + ogxMatrixTranslation(shadowView); // 阴影相机空间。
                        fragPosition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragPosition
                            + ogxMatrixTranslation(shadowProjection); // 阴影投影。
                        float distortFactor = shadowDistort > 0.0 ? 1.0 / (log(length(fragPosition.xy) * 0.61 + 1.0) * 1.8) : 1.0; // 参考实现的边缘压缩。
                        vec3 shadowPos = vec3(fragPosition.xy * distortFactor, fragPosition.z); // 压缩后的阴影坐标。
                        if (abs(shadowPos.x) < 1.0 - 0.5 / 2048.0 && abs(shadowPos.y) < 1.0 - 0.5 / 2048.0) // 在阴影图内。
                        {
                            shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 转零到一。
                            shadow = vec3(textureLod(shadowTexture, shadowPos.xy, 0.0).x); // 读阴影。
                        }
                    }
                    float indirectShadowMask = 1.0 - min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0); // 间接光遮挡。
                    float sunShadowMask = ogxEclipseGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                        minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture); // 朝光遮挡。
                    vec3 shadowStartPos = vec3(0.0); // 层间阴影起点。
                    if (layerIndex == 0) // 大积云投到小积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0); // 投到上层。
                        sunShadowMask += 3.0 * ogxEclipseGetCloudShape(s, 1, 0, shadowStartPos, s.layers[1].height,
                            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * densityLarge; // 上层遮挡。
                    }
                    if (layerIndex != 2 && s.cumulonimbus > 0) // 积雨云投到其他积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec * 9000.0; // 大步投到积雨云。
                        sunShadowMask += ogxEclipseGetCumulonimbusShape(s, 0, shadowStartPos, 600.0, 4600.0 + shadowStartPos.y, 1.0, cameraPos, noiseTexture).x * 3.0; // 积雨云遮挡。
                    }
                    shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max(s.layers[3].height - rayPosition.y, 0.0); // 投到高层云。
                    sunShadowMask += ogxEclipseGetCloudShape(s, 3, 0, shadowStartPos, s.layers[3].height, s.layers[3].height, noiseTexture)
                        * s.layers[3].rainDensity * (1.0 - abs(mainLightVec.y)); // 高层云遮挡。
                    vec3 lighting = ogxEclipseGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensityFaded, sunShadowMask,
                        sunScattering * shadow, moonScattering * shadow, indirectShadowMask, skyScattering * skylightOcclusion, rayPosition,
                        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2); // 光照。
                    float horizontalDist = length(newPos.xz - s.lightningBoltPosition.xz); // 普通闪电水平距离。
                    if (horizontalDist < 7500.0 && s.lightningBoltPosition.w > 0.0) // 普通闪电照亮云。
                    {
                        float lightningIntensity = exp(-horizontalDist * 0.006) * density * s.lightningFlash; // 闪电强度。
                        lighting = mix(lighting, vec3(1.3, 1.5, 3.0), lightningIntensity); // 混向冷白。
                    }
                    if (s.lightningEnabled > 0 && (layerIndex == 2 || s.thunderStrength > 0.0)) // 积雨云闪电。
                    {
                        float lightningDist = length(newPos - lightningPos); // 到闪电位距离。
                        if (lightningDist < 6000.0 && lightningPos != vec3(0.0)) // 在照明范围内。
                        {
                            float lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity)
                                * s.lightningFlash; // 距离与密度权重。
                            lightningIntensity *= 1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y); // 高度淡出。
                            lightningIntensity *= smoothstep(17000.0, 14000.0, horizontalDist); // 水平淡出。
                            lightningIntensity *= s.lightningFade; // 时间淡出。
                            vec3 lightningStrength = s.cumulonimbusLightningColor * s.cumulonimbusLightningBrightness * 0.125; // 闪电颜色。
                            lighting = mix(lighting, lightningStrength, lightningIntensity); // 混向闪电。
                        }
                    }
                    newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视距离压缩。
                    float distancefog = exp2(s.distanceFogScale * length(newPos.xz)); // 距离雾。
                    vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
                    lighting = lighting * distancefog + atmosphereHaze; // 混雾。
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded); // 这一段透过率。
                    color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 累加。
                    totalAbsorbance *= densityCoeff; // 更新透过率。
                    if (totalAbsorbance < 1e-5) break; // 已经完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
        return vec4(color, totalAbsorbance); // 交回这一层的颜色与透过率。
    }
    return vec4(color, totalAbsorbance); // 未知层号原样返回。
}

// 五层体积云总入口：按参考实现的顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合。
// `sampledSkyCol` 是调用方从天空查表取到的颜色，已经除以参考实现的 1200。
vec4 ogxEclipseGetVolumetricClouds(OgxEclipseCloudSettings s, vec3 viewPos, vec2 dither, vec3 sunVector,
    vec3 moonVector, vec3 directLightCol, vec3 directLightCol2, vec3 indirectLightCol,
    inout float cloudPlaneDistance, inout vec2 cloudDistance, vec3 cameraPos, vec3 sampledSkyCol,
    float farPlane, float dhFarPlane, mat4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, vec3 shadowCameraPos, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 累积透过率。
    vec4 cloudColor = vec4(color, totalAbsorbance); // 当前层结果。
    vec4 cloudColorOriginal = cloudColor; // 每层重置用。
    float cloudheight = s.layers[0].tallness / s.layers[0].scale; // 第一层厚度。
    float minHeight = s.layers[0].height; // 第一层云底。
    float maxHeight = cloudheight + minHeight; // 第一层云顶。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - minHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层的高度。
    float maxdist = dhFarPlane > 0.0 ? dhFarPlane - 16.0 : farPlane + 16.0 * 5.0; // 最大可见距离。
    float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 1.0e8; // 参考实现的距离哨兵。
    vec4 normPlayerPos = vec4(ogxMatrixMulPoint(modelViewInverse, viewPos) + ogxMatrixTranslation(modelViewInverse), 1.0); // 视空间转世界。
    normPlayerPos = normalize(normPlayerPos); // 单位视线方向。
    float sdotv = dot(sunVector, normPlayerPos.xyz); // 太阳与视线夹角。
    float sdotv2 = dot(moonVector, normPlayerPos.xyz); // 月亮与视线夹角。
    if (skyGround) normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点，避免云压到地平线。
    float cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
        clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 相机在层内时水平步长更小。
    vec3 cloudDist = vec3(1.0); // 水平与竖直步长。
    cloudDist.xz = mix(vec2(255.0), vec2(5.5), cloudMix); // 层内 5.5，层外 255。
    vec3 rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / min(cloudDist, vec3(0.05 * lViewPosM))) / float(samples)); // 一层走完的步长。
    vec3 rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点压到云层平面。
    sampledSkyCol *= skyBrightness; // 天空亮度。
    vec3 playerPos = ogxMatrixMulPoint(modelViewInverse, viewPos); // 相机相对世界位置。
    float maxLength = min(length(playerPos), farPlane) / max(length(playerPos), 1e-4); // 限制到远平面。
    playerPos *= maxLength; // 截断。
    float startDistance = length(playerPos); // 到像素的距离。
    float sunVis = smoothstep(-0.06, 0.1, s.sunElevation); // 太阳可见度。
    float moonVis = smoothstep(0.0, 0.075, -s.moonElevation); // 月亮可见度。
    float backScatterPhase = 0.0; // 太阳后向散射。
    vec4 phaseLevels = vec4(0.0); // 太阳四档相函数。
    if (sunVis > 0.0) // 太阳在地平线上才算。
    {
        backScatterPhase = ogxEclipsePhaseCloud(-sdotv, 0.25, 0) * 2.0; // 后向。
        phaseLevels = vec4(ogxEclipsePhaseCloud(sdotv, 0.80, 0), ogxEclipsePhaseCloud(sdotv, 0.55, 0),
            ogxEclipsePhaseCloud(sdotv, 0.35, 0), ogxEclipsePhaseCloud(sdotv, 0.10, 0)); // 四档前向。
    }
    float backScatterPhase2 = 0.0; // 月亮后向。
    vec4 phaseLevels2 = vec4(0.0); // 月亮四档。
    if (moonVis > 0.0) // 月亮在地平线上才算。
    {
        backScatterPhase2 = ogxEclipsePhaseCloud(-sdotv2, 0.25, 0) * 2.0; // 后向。
        phaseLevels2 = vec4(ogxEclipsePhaseCloud(sdotv2, 0.80, 0), ogxEclipsePhaseCloud(sdotv2, 0.55, 0),
            ogxEclipsePhaseCloud(sdotv2, 0.35, 0), ogxEclipsePhaseCloud(sdotv2, 0.10, 0)); // 四档前向。
    }
    vec3 sunScattering = directLightCol * sunVis * sunVis; // 太阳散射。
    vec3 moonScattering = directLightCol2 * moonVis * moonVis * (1.0 - sunVis * sunVis); // 月亮散射。
    vec3 skyScattering = indirectLightCol * (1.0 + sunVis); // 天空散射。
    bool mixBelowLayer0 = cameraPos.y < s.layers[0].height + s.layers[0].tallness; // 相机是否在小积云下方。
    bool mixBelowLayer1 = cameraPos.y < s.layers[1].height; // 相机是否在大积云下方。
    vec4 smallCumulusClouds = cloudColorOriginal; // 小积云结果。
    vec2 cloudLayer0Distance = vec2(startDistance, 1.0); // 小积云距离。
    smallCumulusClouds = ogxEclipseRaymarchCloud(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer0Distance,
        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
        shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 小积云。
    cloudColor.a *= smallCumulusClouds.a; // 更新透过率。
    float smallCumulusDistance = length(rayPosition - cameraPos); // 小积云命中距离。
    vec4 largeCumulusClouds = cloudColorOriginal; // 大积云结果。
    vec2 cloudLayer1Distance = vec2(startDistance, 1.0); // 大积云距离。
    if (cloudColor.a > 1e-5 || !mixBelowLayer1) // 有剩余光且相机位置合适。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
            clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 重算混合。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), cloudMix); // 大积云水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(samples)); // 重算步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        largeCumulusClouds = ogxEclipseRaymarchCloud(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer1Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 大积云。
        cloudColor.a *= largeCumulusClouds.a; // 更新透过率。
    }
    float largeCumulusDistance = length(rayPosition - cameraPos); // 大积云命中距离。
    vec4 cumulonimbusClouds = cloudColorOriginal; // 积雨云结果。
    vec2 cloudLayer4Distance = vec2(startDistance, 1.0); // 积雨云距离。
    if (s.cumulonimbus > 0 && (cloudColor.a > 1e-5 || !mixBelowLayer0)) // 开启积雨云。
    {
        cloudheight = 4000.0; // 积雨云厚度。
        minHeight = 600.0; // 积雨云底。
        maxHeight = cloudheight + minHeight; // 积雨云顶。
        int cumulonimbusSamples = 2 * samples; // 两倍样本。
        cloudDist.xz = vec2(8.0); // 固定水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(cumulonimbusSamples)); // 重算步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        cumulonimbusClouds = ogxEclipseRaymarchCloud(s, 2, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol,
            cloudLayer4Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds,
            deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 积雨云。
        cloudColor.a *= cumulonimbusClouds.a; // 更新透过率。
    }
    float cumulonimbusDistance = length(rayPosition - cameraPos); // 积雨云命中距离。
    vec4 altoStratusClouds = cloudColorOriginal; // 高层云结果。
    vec2 cloudLayer2Distance = vec2(startDistance, 1.0); // 高层云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画高层云。
    {
        cloudheight = 5.0; // 高层云很薄。
        minHeight = s.layers[3].height; // 高层云底。
        maxHeight = cloudheight + minHeight; // 高层云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        altoStratusClouds = ogxEclipseRaymarchCloud(s, 3, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer2Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 高层云。
        cloudColor.a *= altoStratusClouds.a; // 更新透过率。
    }
    vec4 cirrusClouds = cloudColorOriginal; // 卷云结果。
    vec2 cloudLayer3Distance = vec2(startDistance, 1.0); // 卷云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画卷云。
    {
        cloudheight = 5.0; // 卷云很薄。
        minHeight = s.layers[4].height; // 卷云底。
        maxHeight = cloudheight + minHeight; // 卷云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        cirrusClouds = ogxEclipseRaymarchCloud(s, 4, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer3Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 卷云。
        cloudColor.a *= cirrusClouds.a; // 更新透过率。
    }
    if (cameraPos.y > s.layers[1].height) // 相机在大积云上方时交换远近层。
    {
        vec2 temp = cloudLayer1Distance;
        cloudLayer1Distance = cloudLayer0Distance;
        cloudLayer0Distance = temp;
    }
    float tempDistance = mix(cloudLayer2Distance.x, cloudLayer3Distance.x, cloudLayer2Distance.y); // 高层与卷云按权重混合。
    tempDistance = mix(cloudLayer1Distance.x, tempDistance, cloudLayer1Distance.y); // 大积云再混合。
    cloudPlaneDistance = mix(cloudLayer0Distance.x, tempDistance, cloudLayer0Distance.y); // 小积云再混合。
    if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance; // 闪电检测用的小积云距离。
    if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance; // 大积云覆盖。
    if (cameraPos.y < s.layers[1].height) // 相机在下层时的顺序。
    {
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
    }
    else
    {
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
    }
    if (cumulonimbusClouds.a < 1.0) cloudDistance.g = cumulonimbusDistance; // 积雨云距离。
    if (cloudDistance.r > 15000.0) cloudDistance.r = 0.0; // 太远就不算闪电高度。
    if (cloudDistance.g > 15000.0) cloudDistance.g = 0.0;
    cloudColor.rgb = cirrusClouds.rgb; // 先放卷云。
    cloudColor.rgb *= altoStratusClouds.a; // 再乘高层云透过率。
    cloudColor.rgb += altoStratusClouds.rgb; // 加高层云。
    if (mixBelowLayer0) // 相机在小积云下方：从下往上合成。
    {
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
    }
    else if (mixBelowLayer1) // 相机在大积云下方。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
    }
    else // 相机在更高处。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
    }
    color = cloudColor.rgb; // 最终颜色。
    totalAbsorbance = cloudColor.a; // 最终透过率。
    return vec4(color, totalAbsorbance); // 交回云颜色与透过率。
}

// 云影步进：只算透过率，不算光照，供阴影程序低成本使用。
float ogxEclipseRaymarchCloudSimple(OgxEclipseCloudSettings s, int layerIndex, int samples, vec3 rayPosition,
    vec3 rayDirection, float dither, float minHeight, float maxHeight, vec3 startPos, vec3 cameraPos,
    sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 初始完全透明。
    float distanceFactor = length(rayDirection); // 一步长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3) densityThresholdCheck = 0.01; // 高层云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动插值。
    if (layerIndex == 3) // 高层云单样本。
    {
        vec3 newPos = rayPosition - startPos; // 相对起点。
        float density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 距离密度。
        if (density == 0.0) return totalAbsorbance; // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0))
            * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面哪一侧。
        if (ifAboveOrBelowPlane) return totalAbsorbance; // 背向不步进。
        float shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 形状。
        float shapeWithDensity = shape * density; // 密度。
        if (shapeWithDensity > 1e-5) totalAbsorbance *= exp(-distanceFactor * shapeWithDensity); // 乘透过率。
        return totalAbsorbance; // 交回透过率。
    }
    if (layerIndex < 3) // 积云。
    {
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(rayPosition - startPos)); // 小积云。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(rayPosition - startPos)); // 大积云。
        if (layerIndex == 2) density = 0.8; // 积雨云。
        if (density < 0.01) return totalAbsorbance; // 密度太低。
        float tallness = maxHeight - minHeight; // 层厚。
        for (int i = 0; i < samples; i++) // 主循环。
        {
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 包围盒。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxEclipseGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 高度淡出。
                if (shapeWithDensityFaded > 1e-5) // 有云。
                {
                    totalAbsorbance *= exp(-distanceFactor * shapeWithDensityFaded); // 乘透过率。
                    if (totalAbsorbance < 1e-5) break; // 完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
    }
    return totalAbsorbance; // 交回透过率。
}

// 云影总入口：返回四个透过率，供阴影程序按层重建云影。
vec4 ogxEclipseGetVolumetricCloudsSimple(OgxEclipseCloudSettings s, vec2 dither, vec3 lightDir, vec2 offset,
    vec3 startPos, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - s.layers[0].height, 0.0) / 100.0, 0.0, 1.0); // 相机高度。
    vec3 normPlayerPos = lightDir; // 光线方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点。
    int samples = 5; // 固定五步。
    vec3 cloudDist = vec3(1.0); // 水平步长。
    float cloudheight = 5.0; // 高层云厚度。
    float minHeight = s.layers[3].height; // 高层云底。
    float maxHeight = cloudheight + minHeight; // 高层云顶。
    cloudDist.xz = vec2(255.0); // 平面云水平步长。
    vec3 rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步。
    vec3 rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
    rayPosition.xz += offset; // 阴影偏移。
    float altoStratusClouds = ogxEclipseRaymarchCloudSimple(s, 3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        startPos, cameraPos, noiseTexture); // 高层云。
    totalAbsorbance *= altoStratusClouds; // 更新透过率。
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        largeCumulusClouds = ogxEclipseRaymarchCloudSimple(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 大积云。
        totalAbsorbance *= largeCumulusClouds; // 更新透过率。
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[0].tallness / s.layers[0].scale; // 小积云厚度。
        minHeight = s.layers[0].height; // 小积云底。
        maxHeight = cloudheight + minHeight; // 小积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        smallCumulusClouds = ogxEclipseRaymarchCloudSimple(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 小积云。
        totalAbsorbance *= smallCumulusClouds; // 更新透过率。
    }
    return vec4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四个透过率。
}

#endif
