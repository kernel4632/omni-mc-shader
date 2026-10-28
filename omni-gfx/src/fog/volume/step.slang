/* 体积雾的单步参数：密度模型选择与沿阳光方向的吸收步进；由 `fog/volume.slang` 内联引入。
可复制示例：`float density = ogxFogDensity(pos, wind, true, 0.3, 1.0, 0.06, midnight, noise);`
设计取舍：步长逐步放大，近处权重更高，避免远处几何把光吸干。 */

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
float ogxFogDensity(float3 fogPos, float3 wind, bool noisy, float heightA, float heightB, float falloff, float timeMidnight, Sampler2D noiseTexture)
{
    return noisy
        ? ogxFogDensityNoise(fogPos, wind, heightA, heightB, falloff, timeMidnight, noiseTexture)
        : ogxFogDensityHeight(fogPos, heightA, heightB, falloff, timeMidnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
float ogxFogLightMarch(inout float3 fogPos, float3 wind, OgxFogMedia media, bool noisy, float heightA, float heightB, float falloff, Sampler2D noiseTexture, int steps, float stepLength)
{
    float lightingDensity = 0.0; // 沿光方向累计的密度。
    for (int i = 0; i < steps; i++, fogPos += media.light_vector * stepLength, stepLength *= 1.5) // 沿光方向步进，步长逐步放大。
    {
        lightingDensity += ogxFogDensity(fogPos, wind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture) * stepLength; // 累加这一段密度。
    }
    return lightingDensity; // 返回累计密度。
}
