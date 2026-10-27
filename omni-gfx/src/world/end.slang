/*
Omni 通用图形库 iterationT 末地补充模块：末地星空、行星 BRDF、黑洞吸积盘与云影查表。
调用位置：需要复现 iterationT `EndSky.glsl` 与 `NUBIS.glsl` 的末地程序；Minecraft 光影由
    `/omni-gfx/world/end.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    float3 stars = ogxItxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);
    float3 disc = ogxItxBlackHoleStars(color, rayDir, lightDir, 0.5, frameTime, true, true, sunVector, 1, noiseTex, 512.0);
    float shadow = ogxItxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);
设计原因与取舍：
    参考实现直接读 `frameTimeCounter`、`worldSunVector`、`STAR_TYPE` 与云噪声选项。库把时间、光方向、
    纹理和开关全部改成显式参数，公式、常数、循环次数和采样顺序保持不变。
    噪点纹理只作为参数传入，库不假设它绑定在哪个缓冲；这样末地星空能独立测试，也能在光影里换槽位。
*/
#ifndef OGX_ITX_END_INCLUDED
#define OGX_ITX_END_INCLUDED

// 数学提供旋转、黑体色与夹紧；雾提供三维噪声与分形云；云提供顶部曲线；行星提供曲面曲线。
#include "../math.slang"
#include "../fog/fog.slang"
#include "../cloud/cloud.slang"
#include "../planet.slang"

// iterationT 末地星空：按天球格子取哈希星点，星色用黑体温度。
// `starType` 为零时由调用方决定是否叠加；本函数只负责算出星点。
float3 ogxItxEndStars(float3 worldDir, float3 worldSunVector, float time, int starType, float brightness, float amount)
{
    float angleY = time * 0.001; // 星空缓慢自转。
    float3x3 eyeRotationY = float3x3(cos(angleY), 0.0, sin(angleY),
                                     0.0, 1.0, 0.0,
                                     -sin(angleY), 0.0, cos(angleY)); // 绕纵轴旋转。
    worldDir = ogxMatrix3MulPoint(eyeRotationY, worldDir); // 转到星空坐标。
    const float scale = 384.0; // 星点密度。
    const float coverage = 0.007; // 星点覆盖率。
    const float maxLuminance = 0.04; // 单颗星最大亮度。
    const float minTemperature = 4000.0; // 最低色温。
    const float maxTemperature = 8000.0; // 最高色温。
    float cosine = dot(worldSunVector, float3(0.0, 0.0, 1.0)); // 绕日轴对齐。
    float3 axis = cross(worldSunVector, float3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 轴长度倒数平方。
    worldDir = cosine * worldDir + cross(axis, worldDir)
        + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 参考实现的球面旋转。
    float3 p = worldDir * scale; // 放大到格子。
    float3 i = floor(p); // 格子下标。
    float3 f = p - i; // 格内偏移。
    float r = dot(f - 0.5, f - 0.5); // 到格中心距离平方。
    float3 i3 = fract(i * float3(443.897, 441.423, 437.195)); // 三维哈希。
    i3 += dot(i3, i3.yzx + 19.19); // 二次混合。
    float2 hash = fract((i3.xx + i3.yz) * i3.zy); // 两个哈希值。
    hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 亮度曲线。
    float c = ogxRemapSaturate(hash.x, 1.0 - coverage, 1.0); // 覆盖率阈值。
    return maxLuminance * ogxRemapSaturate(r, 0.25, 0.0) * c * c * ogxBlackbody(lerp(minTemperature, maxTemperature, hash.y)); // 星点亮度乘色温。
}

// iterationT 行星 BRDF：用 Chandrasekhar H 函数与 Lambert 曲线近似行星表面。
// iterationT 的次表面近似：按法线与光方向补透光，供末地植物使用。
float3 ogxItxPpss(float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float s)
{
    float NdotL = dot(normal, lightDir); // 光线与法线。
    float NdotV = dot(normal, eyeDir); // 视线与法线。
    albedo *= ogxCurve01(ogxSaturate(NdotL)); // 参考实现的曲线。
    float3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 双向反射。
    return ogxSaturate(color); // 夹到合法范围。
}

// 黑洞吸积盘主函数：沿射线步进，累计盘面自发光与遮挡。
// `detailAlongLongitude`、`doppler` 与 `starType` 对应参考实现的三个菜单开关。
float3 ogxItxBlackHoleStars(float3 color, float3 rayDir, float3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, float3 worldSunVector, int starType,
    Sampler2D noiseTexture, float noiseResolution)
{
    const float steps = 50.0; // 固定步数。
    const float rSteps = 1.0 / steps; // 步数倒数。
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 盘半径。
    const float discWidth = 3.5; // 盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内缘。
    const float discOuter = discRadius + discWidth * 0.5; // 外缘。
    float3 eye = -lightDir * 8.0; // 相机位置。
    float3 rayPos = eye + rayDir * 3.0; // 起点。
    float3x3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 固定盘面旋转。
    float3 result = float3(0.0); // 盘面颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 抖动起点。
    for (int i = 0; i < int(steps); i++) // 固定步数。
    {
        if (transmittance < 0.0001) break; // 全遮挡就停。
        ogxWarpSpace(rayDir, rayPos); // 空间扭曲。
        rayPos += rayDir * stepLength; // 前进一步。
        float3 discPos = ogxMatrix3MulPoint(rotation, rayPos); // 盘面坐标。
        float r = length(discPos); // 半径。
        float p = ogxAtan2(float2(-discPos.z, -discPos.x)); // 方位角。
        float h = discPos.y; // 高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向渐变。
        float dist = abs(h); // 到盘面的距离。
        float discThickness = 0.1 * radialGradient; // 盘厚度。
        float fr = abs(r - discInner) + 0.4; // 内缘距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 远处淡出。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 盘面辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 厚度内可见。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxEndSkyPCurve(radialGradient); // 径向曲线。
        float density = dr; // 密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 厚度衰减。
        density = ogxSaturate(density * 0.7); // 参考实现的强度。
        density = ogxSaturate(density + bloomFactor * 0.1); // 辉光贡献。
        if (density > 0.0001) // 只有足够密才发光。
        {
            float3 discCoord = detailAlongLongitude
                ? float3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5
                : float3(r, 0.0, h * 0.1) * 3.5; // 经度细节开关。
            float3 shift = detailAlongLongitude ? time * float3(0.1, 0.07, 0.0) : time * float3(0.03, 0.05, 0.0); // 流动方向。
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, noiseResolution); // 参考实现的分形云。
            fbm = fbm * fbm; // 平方。
            fbm = fbm * fbm; // 四次方。
            density *= fbm * dr; // 细节乘回密度。
            float gr = 1.0 - radialGradient; // 外缘渐变。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 外缘辉光强度。
            float3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 黑体色乘强度。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应。
            float stepTransmittance = exp2(-density * 7.0); // 本段透过率。
            float integral = 1.0 - stepTransmittance; // 本段吸收。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 累积发光。
        }
        float2 t = float2(1.0, 0.01); // 圆环参数。
        float torusDist = length(length(discPos + float3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        float3 col = ogxBlackbody(12000.0); // 高温蓝白。
        bloomDisc *= step(0.5, r); // 内圈不发光。
        result += col * bloomDisc * 0.1 * transmittance; // 叠加圆环。
    }
    result *= rSteps; // 步长归一化。
    if (starType > 0) color += ogxItxEndStars(rayDir, worldSunVector, time, starType, 1.0, 1.0); // 参考实现的星空叠加。
    color *= transmittance; // 盘面遮挡背景。
    return color + result; // 最终颜色。
}

// 黑洞吸积盘反射版：步数更少，细节权重与主函数不同。
float3 ogxItxBlackHoleReflection(float3 color, float3 rayDir, float3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, Sampler2D noiseTexture, float noiseResolution)
{
    const float steps = 30.0; // 反射只走三十步。
    const float rSteps = 1.0 / steps; // 步数倒数。
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 盘半径。
    const float discWidth = 3.5; // 盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内缘。
    float3 eye = -lightDir * 8.0; // 相机位置。
    float3 rayPos = eye + rayDir * 4.0; // 起点更远。
    float3x3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 固定盘面旋转。
    float3 result = float3(0.0); // 盘面颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 抖动起点。
    for (int i = 0; i < int(steps); i++) // 固定步数。
    {
        if (transmittance < 0.0001) break; // 全遮挡就停。
        ogxWarpSpace(rayDir, rayPos); // 空间扭曲。
        rayPos += rayDir * stepLength; // 前进一步。
        float3 discPos = ogxMatrix3MulPoint(rotation, rayPos); // 盘面坐标。
        float r = length(discPos); // 半径。
        float p = ogxAtan2(float2(-discPos.z, -discPos.x)); // 方位角。
        float h = discPos.y; // 高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向渐变。
        float dist = abs(h); // 到盘面距离。
        float discThickness = 0.1 * radialGradient; // 盘厚度。
        float fr = abs(r - discInner) + 0.4; // 内缘距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 远处淡出。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 盘面辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 厚度内可见。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxEndSkyPCurve(radialGradient); // 径向曲线。
        float density = dr; // 密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 厚度衰减。
        density = ogxSaturate(density * 0.7); // 参考实现的强度。
        density = ogxSaturate(density + bloomFactor * 0.1); // 辉光贡献。
        if (density > 0.0001) // 只有足够密才发光。
        {
            float3 discCoord = detailAlongLongitude
                ? float3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5
                : float3(r, 0.0, h * 0.1) * 3.5; // 经度细节开关。
            float3 shift = detailAlongLongitude ? time * float3(0.1, 0.07, 0.0) : time * float3(0.03, 0.05, 0.0); // 流动方向。
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, noiseResolution); // 参考实现的分形云。
            float fbm2 = fbm * fbm; // 平方。
            density *= fbm2 * fbm2 * fbm; // 五次方权重。
            density *= dr; // 乘径向曲线。
            float gr = 1.0 - radialGradient; // 外缘渐变。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 外缘辉光强度。
            float3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 黑体色乘强度。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应。
            float stepTransmittance = exp2(-density * 7.0); // 本段透过率。
            float integral = 1.0 - stepTransmittance; // 本段吸收。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 累积发光。
        }
        float2 t = float2(1.0, 0.01); // 圆环参数。
        float torusDist = length(length(discPos + float3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        float3 col = ogxBlackbody(12000.0); // 高温蓝白。
        bloomDisc *= step(0.5, r); // 内圈不发光。
        result += col * bloomDisc * 0.1 * transmittance; // 叠加圆环。
    }
    result *= rSteps; // 步长归一化。
    color *= transmittance; // 盘面遮挡背景。
    return color + result; // 最终颜色。
}

// 云影密度函数的提前声明：云影查表会先调用它，定义放在文件末尾。
float3 ogxItxCloudShadowDensity(float4 cloudPos, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float3 windDirection);

// iterationT 云影查表：按太阳方向在云层高度取样两次，取较大密度后做指数衰减。
// `baseNoise` 是云形状噪声；`coverage` 与 `wetness` 由调用方按菜单填写。
float ogxItxCloudShadowTex(float2 coord, float2 cloudAltitude, float3 windDirection, float2 cameraXZ,
    float3 worldShadowVector, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float shadowRange)
{
    coord = coord * shadowRange - shadowRange * 0.5; // 屏幕坐标转云影范围。
    float4 checkPos = float4(coord.x + cameraXZ.x, 0.0, coord.y + cameraXZ.y, 0.0); // 云影起点。
    float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
    checkPos += float4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y), 0.25); // 沿太阳方向抬到云层。
    float3 density = ogxItxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection); // 第一次取样。
    checkPos += float4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y), 0.25); // 再抬四分之一层。
    density = max(density, ogxItxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection)); // 第二次取样。
    return exp2(-density.y * 20.0); // 参考实现的云影衰减。
}

// 云影密度：只算基础形状，不算细节层，和参考实现的 `sampleDetail=false` 一致。
float3 ogxItxCloudShadowDensity(float4 cloudPos, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float3 windDirection)
{
    float4 baseSample = baseNoise.SampleLevel(cloudPos.xyz * baseScale + windDirection * 10.0, 0.0); // 基础噪声。
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2; // 三层混合。
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0); // 按形状重置。
    float shapeCurve = ogxCloudTopCurve(ogxSaturate(1.0 - cloudPos.w)) * 0.5; // 顶部曲线。
    shapeCurve += ogxCurve01(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 底部曲线。
    baseDensity *= shapeCurve; // 乘形状。
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 底部权重。
    baseDensity *= lerp(1.0, ogxCloudTopCurve(ogxSaturate(cloudPos.w * 3.0)), wetness); // 雨天改顶部曲线。
    float coverageNoise = baseNoise.SampleLevel(cloudPos.xyz * float3(8.5e-5, -1e-5, 8.5e-5) + windDirection + coverageOffset, 0.0).x; // 覆盖噪声。
    float coverage = lerp(clearCoverage, rainCoverage, wetness); // 晴雨覆盖。
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 覆盖阈值。
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0); // 覆盖裁剪。
    baseDensity *= ogxCurve01(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 密度控制。
    baseDensity *= ogxCloudTopCurve(ogxSaturate(cloudPos.w * 1.8)); // 顶部衰减。
    baseDensity = ogxSaturate(baseDensity); // 夹紧。
    return float3(baseDensity); // 没有细节层。
}

#endif
