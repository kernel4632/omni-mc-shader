// 钱德拉塞卡近似：各项同性散射的倍增因子，反照率越高、余弦越大越亮。
float3 ogxChandrasekharH(float3 albedo, float a)
{
    float3 R = sqrt(float3(1.0) - albedo); // 单次散射反照率的平方根。
    float3 r = (1.0 - R) / (1.0 + R); // 反射率比值。
    float3 h = r + (0.5 - r * a) * log((1.0 + a) / a); // 钱德拉塞卡近似。
    h *= albedo * a; // 乘反照率与余弦项。
    return 1.0 / (1.0 - h); // 取倒数得到倍增。
}

// 行星表面双向反射：入射与出射两侧各算一次钱德拉塞卡近似，再除以相函数分母。
float3 ogxPlanetBrdf(float3 albedo, float3 normal, float3 eyeDir, float3 lightDir)
{
    float NdotL = dot(normal, lightDir); // 法线与光方向夹角余弦。
    float NdotV = dot(normal, eyeDir); // 法线与视线夹角余弦。
    albedo *= clamp(NdotL, 0.0, 1.0) * clamp(NdotL, 0.0, 1.0) * (3.0 - 2.0 * clamp(NdotL, 0.0, 1.0)); // 反照率按入射角衰减。
    float3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 两侧近似与相函数分母。
    return clamp(color, 0.0, 1.0); // 夹到合理范围。
}

// 行星环带噪声：五层噪声叠出环带细缝，返回已经去掉偏移的累加值。
float ogxPlanetRingNoise(float position, Sampler2D noiseTexture)
{
    const float octAlpha = 0.5; // 每层噪声的权重衰减。
    const float octScale = 4.0; // 每层频率放大。
    const float octShift = (octAlpha / octScale) / 5.0; // 层间偏移。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 当前层权重。
    for (int i = 0; i < 5; i++) // 五层噪声叠出环带细缝。
    {
        accum += alpha * noiseTexture.SampleLevel(float2(position, 0.0), 0.0).z; // 读噪声的第三通道。
        position = position * octScale; // 抬高频率。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift - 0.1; // 加上层间偏移并减去阈值。
}

// Eclipse 的瑞利相函数：Elek 2009 的线性近似，已经除以四派做能量守恒。
// Eclipse 天空的瑞利相函数：按视线与太阳夹角给出蓝光更强的散射比例。
float ogxSkyRayleighPhase(float cosTheta)
{
    return cosTheta * (0.1 * OGX_INV_PI) + 0.28 * OGX_INV_PI; // 参考实现把两个常数都乘 1/pi。
}

// Eclipse 的米氏相函数：用 g 的平方与 1.5 次幂，和 Henyey-Greenstein 不是同一公式。
// Eclipse 天空的米氏相函数：用 g 控制太阳附近的前向散射强度。
float ogxSkyMiePhase(float cosTheta, float g)
{
    float gg = g * g; // 先算 g 的平方。
    return (gg * -0.25 + 0.25) * OGX_INV_PI * pow(-(2.0 * g) * cosTheta + (gg + 1.0), -1.5); // 参考实现的负指数。
}

// Eclipse 的相函数对：第一分量瑞利，第二分量米氏。
float2 ogxSkyPhasePair(float cosTheta, float g)
{
    return float2(ogxSkyRayleighPhase(cosTheta), ogxSkyMiePhase(cosTheta, g));
}

// Eclipse 的大气密度：瑞利与米氏共用一条指数，臭氧用两段指数围出峰值。
// `planetRadius` 与 `scaleHeights` 由调用方给出，默认是 6731 公里与 8/1.2 公里。
float3 ogxSkyDensity(float centerDistance, float planetRadius, float2 scaleHeights)
{
    float2 inverseScaleHeights = 1.0 / scaleHeights; // 标高倒数。
    float2 rayleighMie = exp(centerDistance * -inverseScaleHeights + planetRadius * inverseScaleHeights); // 瑞利与米氏。
    float ozone = exp(-max(0.0, (35000.0 - centerDistance) - planetRadius) * (1.0 / 5000.0)) // 臭氧上边界。
                * exp(-max(0.0, (centerDistance - 35000.0) - planetRadius) * (1.0 / 15000.0)); // 臭氧下边界。
    return float3(rayleighMie, ozone); // 三个分量对应三种介质。
}

// Eclipse 的大气质量：沿视线固定步数积分密度，步长由射线长度决定。
float3 ogxSkyAirmass(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights)
{
    float stepSize = rayLength * (1.0 / steps); // 每步长度。
    float3 increment = direction * stepSize; // 每步位移。
    position += increment * 0.5; // 从半步处开始，避开端点。
    float3 airmass = float3(0.0); // 累积密度。
    for (int i = 0; i < steps; ++i, position += increment) // 固定步数。
    {
        airmass += ogxSkyDensity(length(position), planetRadius, scaleHeights); // 逐点累积密度。
    }
    return airmass * stepSize; // 乘步长得到光学路径。
}

// Eclipse 的大气质量射线版：先求与大气顶层的交点，再调用固定步数版。
float3 ogxSkyAirmassRay(float3 position, float3 direction, float steps,
    float planetRadius, float2 scaleHeights, float atmosphereRadius)
{
    float rayLength = dot(position, direction); // 投影长度。
    rayLength = rayLength * rayLength + atmosphereRadius * atmosphereRadius - dot(position, position); // 判别式。
    if (rayLength < 0.0) return float3(0.0); // 射线不碰大气。
    rayLength = sqrt(rayLength) - dot(position, direction); // 到交点的距离。
    return ogxSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 交给固定步数版。
}

// Eclipse 的光学厚度：三种介质的消光系数乘各自的大气质量。
float3 ogxSkyOpticalDepth(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights,
    float3 coefficientRayleigh, float3 coefficientMie, float3 coefficientOzone)
{
    float3 airmass = ogxSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 三种介质的路径。
    return coefficientRayleigh * airmass.x + coefficientMie * airmass.y + coefficientOzone * airmass.z; // 按介质加权。
}

// Eclipse 的透过率：把光学厚度换成以二为底的指数，和参考实现的 `exp(-od/ln2)` 等价。
float3 ogxSkyTransmittance(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights,
    float3 coefficientRayleigh, float3 coefficientMie, float3 coefficientOzone)
{
    float3 depth = ogxSkyOpticalDepth(position, direction, rayLength, steps, planetRadius, scaleHeights,
        coefficientRayleigh, coefficientMie, coefficientOzone); // 先算光学厚度。
    return exp2(-depth); // exp(-depth/ln2) 与 exp2(-depth) 等价。
}

// Eclipse 星场：用星盒三角投影得到星点，再按亮度与数量做指数强化。
float ogxSkyStarField(float3 viewPos, float brightness, float amount, out float3 starColor)
{
    float stars = max(1.0 - ogxStarBox(viewPos, starColor), 0.0); // 星盒投影。
    return 75.0 * brightness * exp(stars * -20.0 * (1.0 / max(amount, 1e-6))); // 参考实现的亮度曲线。
}
