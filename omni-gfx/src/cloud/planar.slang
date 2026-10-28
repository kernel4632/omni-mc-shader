/*
Omni 通用图形库平面云模块：扭曲、密度、光照密度、固定高度取样、朝太阳求遮挡并合成空气透视。
调用位置：需要 iterationT 风格平面云的程序；Minecraft 光影由 `/omni-gfx/cloud/planar.glsl` 引入。
可复制示例：`float density = ogxPlanarDensity(position, windDirection, noiseTexture, 0.01, 0.5);`
设计原因与取舍：
    参考实现把噪声、风、云量与大气常数都写成全局宏。库把每一类输入显式传入，
    函数体仍保留原来的球面求交、四次光照步进与两次相函数，不改变画面手感。
    大气透视复用查表模型，避免在云模块里复制一套散射公式。
*/
#ifndef OGX_PLANAR_INCLUDED
#define OGX_PLANAR_INCLUDED

// 云模块提供球面求交，数学提供相函数，大气模块提供空气透视；本文件自带平面云密度与光照。
#include "cloud.slang"
// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"
// 大气查表提供空气透视与日月辐照。
#include "../atmosphere/model.slang"

// 平面云合成：沿视线与云层求交，取密度与朝阳光照，再把云和空气透视叠到背景。
// 双线性噪声取样：平面云用同一张噪声图，按世界尺度的万分之一缩放。
float ogxBilinearNoise(float2 position, Sampler2D noiseTexture)
{
    return noiseTexture.SampleLevel(position * 1.2e-4, 0.0).w; // 第四个通道当同一张图。
}

// 三次模糊噪声取样：先算十六像素的三次核，再做四次双线性采样，云团边缘因此更软。
float ogxBicubicBlurNoise(float2 coord, Sampler2D noiseTexture)
{
    coord = coord * (1.2e-4 * 64.0) - 0.5; // 噪声图每个纹素对应一万二千分之一的尺度。
    float2 p = floor(coord); // 整数纹素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 前两个权重。
    float4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的三次方。
    w1.yw = ff * f; // 第四个权重是偏移的三次方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为一推出。
    float4 s = w0 + w1; // 每对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= 1.0 / 64.0; // 换算到零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return lerp(lerp(noiseTexture.SampleLevel(float2(c.y, c.w), 0.0).w, noiseTexture.SampleLevel(float2(c.x, c.w), 0.0).w, m.x),
                lerp(noiseTexture.SampleLevel(float2(c.y, c.z), 0.0).w, noiseTexture.SampleLevel(float2(c.x, c.z), 0.0).w, m.x), m.y); // 四次采样合成一层模糊噪声。
}

// 平面云扭曲：三层不同频率的噪声叠出大尺度扭曲量，云团因此不是规整的圆。
float ogxPlanarDistortion(float2 position, float2 windDirection, Sampler2D noiseTexture)
{
    float density = ogxBilinearNoise(position - windDirection, noiseTexture); // 第一层。
    float scale = 4.0; // 起始频率。
    for (int i = 0; i < 3; i++, scale *= 3.0) // 三层，频率逐级乘三。
    {
        density += ogxBilinearNoise(scale * (position - windDirection * ogxFastSqrt(scale)), noiseTexture) * pow(scale, -1.3); // 高频层衰减后叠加。
    }
    return density; // 返回扭曲量。
}

// 平面云密度：扭曲后的位置叠六层噪声，再按云量抬阈值并压边缘。
float ogxPlanarDensity(float2 position, float2 windDirection, Sampler2D noiseTexture, float noiseScale, float coverage)
{
    position *= noiseScale; // 按调用方给的空间尺度缩放。
    float distortion = ogxPlanarDistortion(position, windDirection, noiseTexture); // 取扭曲量。
    position += distortion * 50.0; // 用扭曲量偏移位置。
    float octScale = 2.8; // 每层频率倍数。
    float density = ogxBicubicBlurNoise(position - windDirection, noiseTexture); // 第一层密度。
    float weights = 1.0; // 权重和。
    for (float i = 1.0; i <= 6.0; i++) // 六层。
    {
        float scale = ogxFastSqrt(i); // 每层频率取平方根。
        float turn = 2.39996322973 * i; // 累积旋转角：每层再转一个黄金角，方向与参考一致。
        float grow = pow(octScale, i); // 累积缩放：层间矩阵每次都乘上频率倍数。
        float2 v = position - windDirection * scale; // 本层的偏移位置。
        float2 noisePosition = grow * float2(cos(turn) * v.x - sin(turn) * v.y, sin(turn) * v.x + cos(turn) * v.y); // 旋转并放大，与逐层乘矩阵的结果一致。
        noisePosition *= float2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 横向压扁，纵向拉伸。
        float weight = pow(octScale, -0.85 * i); // 每层权重按频率衰减。
        density += ogxBicubicBlurNoise(noisePosition, noiseTexture) * weight; // 累加这一层。
        weights += weight; // 累加权重。
    }
    density /= weights; // 平均到零到一。
    density = clamp(density + coverage - 1.0, 0.0, 1.0); // 按云量抬高阈值。
    density *= exp(-distortion); // 扭曲强的地方压暗。
    return density * density; // 平方让边缘收口。
}

// 平面云光照密度：层数更少，供云影与光照估计使用，便宜但不改变形状。
float ogxPlanarLightingDensity(float2 position, float2 windDirection, Sampler2D noiseTexture, float noiseScale, float coverage)
{
    position *= noiseScale; // 按空间尺度缩放。
    float distortion = ogxPlanarDistortion(position, windDirection, noiseTexture); // 取扭曲量。
    position += distortion * 50.0; // 用扭曲量偏移位置。
    float octScale = 2.8; // 每层频率倍数。
    float density = ogxBicubicBlurNoise(position - windDirection, noiseTexture); // 第一层。
    float weights = 1.0; // 权重和。
    for (float i = 1.0; i <= 3.0; i++) // 三层。
    {
        float scale = ogxFastSqrt(i); // 每层频率。
        float turn = 2.39996322973 * i; // 累积旋转角。
        float grow = pow(octScale, i); // 累积缩放。
        float2 v = position - windDirection * scale; // 本层的偏移位置。
        float2 noisePosition = grow * float2(cos(turn) * v.x - sin(turn) * v.y, sin(turn) * v.x + cos(turn) * v.y); // 旋转并放大。
        noisePosition *= float2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 横向压扁，纵向拉伸。
        float weight = pow(octScale, -0.85 * i); // 每层权重。
        density += ogxBilinearNoise(noisePosition, noiseTexture) * weight; // 用更便宜的取样累加。
        weights += weight; // 累加权重。
    }
    density /= weights; // 平均。
    density = clamp(density + coverage - 1.0, 0.0, 1.0); // 按云量抬高阈值。
    density *= exp(-distortion); // 扭曲强的地方压暗。
    return density * density; // 平方收口。
}

// 平面云的光照遮挡：沿光方向按逐步放大的步长走几步，累加光照密度乘步长。
// 为什么步长逐次放大：离采样点越远云越稀，放大步长能用同样多的样本覆盖更远，
// 原程序用四步、每步乘一点五；步数与增长交给调用方，库不预设画质档位。
float ogxPlanarCloudLightingDepth(float2 samplePosition, float2 lightDirection, float2 windDirection,
    float dither, float firstStep, float stepGrowth, int steps,
    Sampler2D noiseTexture, float noiseScale, float coverage)
{
    float2 position = samplePosition + firstStep * dither * lightDirection; // 起点先沿光方向抖一下，打散条带。
    float stepLength = firstStep; // 当前步长。
    float depth = 0.0; // 沿光方向累积的遮挡密度。
    for (int i = 0; i < steps; i++) // 逐步前进。
    {
        depth += ogxPlanarLightingDensity(position, windDirection, noiseTexture, noiseScale, coverage) * stepLength; // 这一段的密度乘长度才是遮挡量。
        position += lightDirection * stepLength; // 前进一整步。
        stepLength *= stepGrowth; // 下一步更长。
    }
    return depth; // 交回累积遮挡，调用方取倒数得到阳光能量。
}

// 云影投影坐标：把世界点沿光方向投到云影所在的水平面，再换成零到一贴图坐标。

// `cloudTransmittance` 进来时是上一层的剩余透过率，返回时已乘上这一层。
void ogxPlanarClouds(inout float3 color, float3 worldDir, float3 camera, float dither,
    inout float cloudTransmittance, OgxAtmosphereModel model, Sampler3D lut, float3 cameraWorldPos,
    float timeSeconds, float cloudSpeed, float ftcOffset, float3 worldShadowVector,
    float3 colorShadowlight, float3 colorSkylight, float wetness, float cloudAltitude, float cloudNoiseScale,
    float cloudCoverage, Sampler2D noiseTexture, float3 worldSunVector, float3 rayleighTint,
    float3 mieTint, float nightBrightness, float skyBrightness, bool volumetricClouds)
{
    float planetRadius = model.bottom_radius * 1e3; // 模型半径从公里换成米。
    float3 rayStartPos = float3(0.0, planetRadius + cameraWorldPos.y, 0.0); // 相机在行星正上方。
    float2 hit = ogxRaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude); // 与云层求交。
    float intersection = hit.y; // 取远交点。
    if (intersection > 0.0) // 视线确实穿过云层才继续。
    {
        float wind = 2.5 * (timeSeconds * cloudSpeed + 10.0 * ftcOffset); // 风随时间推进。
        float2 windDirection = float2(-wind, wind * 0.2); // 风向略微斜向。
        float VdotL = dot(worldDir, worldShadowVector) * 0.5 + 0.5; // 视线与光的夹角映射到零到一。
        float3 centerPosition = worldDir * intersection; // 云层交点。
        float2 samplePosition = centerPosition.xz + cameraWorldPos.xz; // 交点换到世界水平坐标。
        cloudTransmittance = min(ogxPlanarDensity(samplePosition, windDirection, noiseTexture,
            cloudNoiseScale, cloudCoverage) * cloudTransmittance * 40.0, 0.9); // 这一层的遮挡。
        if (volumetricClouds) cloudTransmittance *= 1.0 - wetness; // 体积雾开启时雨天更薄。
        if (cloudTransmittance > 1e-5) // 有遮挡才做光照与合成。
        {
            float stepLength = lerp(150.0, 0.0, worldShadowVector.z); // 朝太阳的步长，太阳越低步长越小。
            samplePosition += stepLength * dither * worldShadowVector.xy; // 起点按抖动错开。
            float lightingDepth = 0.0; // 朝太阳的遮挡量。
            for (int i = 0; i < 4; i++) // 四次光照步进。
            {
                lightingDepth += ogxPlanarLightingDensity(samplePosition, windDirection, noiseTexture,
                    cloudNoiseScale, cloudCoverage) * stepLength; // 累加这一步的密度。
                samplePosition += worldShadowVector.xy * stepLength; // 前进。
                stepLength *= 1.5; // 步长逐次放大。
            }
            float sunlightEnergy = 1.0 / (lightingDepth + 1.0); // 遮挡越少阳光越强。
            float powderFactor = exp2(-cloudTransmittance * (worldShadowVector.y * 5.0 + 0.5)); // 粉末效应。
            sunlightEnergy *= ogxMiePhase(powderFactor * 0.8, VdotL * 0.5 + 0.5); // 第一次相函数。
            sunlightEnergy *= ogxMiePhase(0.9, VdotL) * 0.4 + 1.0; // 第二次相函数补前向散射。
            float3 cloudColor = colorShadowlight * (sunlightEnergy * 6.0); // 云被太阳照亮的颜色。
            float skylightEnergy = exp2(-cloudTransmittance * 0.15); // 天空光穿过的比例。
            cloudColor += colorSkylight * (skylightEnergy * 0.2); // 加天空环境光。
            cloudTransmittance *= exp2(-(length(centerPosition) + 2e3) * 4e-5); // 远处云逐渐融进空气。
            float3 atmoPoint = camera + centerPosition * 0.001; // 交点从米换成公里。
            float3 transmittance; // 相机到交点的透过率。
            float3 aerialPerspective = ogxAtmoSkyRadianceToPoint(model, lut, camera, atmoPoint, worldSunVector,
                -worldSunVector, false, rayleighTint, mieTint, nightBrightness, 0.0, skyBrightness, transmittance); // 空气透视。
            color *= (1.0 - cloudTransmittance); // 背景先按云的遮挡压暗。
            color += (cloudColor * transmittance + aerialPerspective) * cloudTransmittance; // 再叠云与空气透视。
        }
    }
}

#endif
