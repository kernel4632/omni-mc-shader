/* 下界的体积雾：羽流、雾霭与顶部烟在同一条视线上分开累加；由 `fog/volume.slang` 内联引入。
可复制示例：`float4 fog = ogxNetherVolumetricFog(rayDir, cameraOffset, cameraWorld, noiseTex, 1.0, 1.0, hazeColor, 1.0, 16, 8.0, 160.0, farPlane);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// Eclipse 下界三段体积雾：羽流、雾霭与顶部烟在同一条视线上分开累加。
// 为什么分三段：羽流发光、雾霭只加色不吸光、顶部烟贴天花板，三者的密度来源与混合方式都不同。
// `cameraOffset` 是相机相对世界的原点，`cameraWorldPos` 是绝对世界位置，雾噪声需要绝对坐标。
// `maxDist` 是步进距离上限，`farPlane` 是羽流随距离淡出用的远裁剪面，两者在参考实现里不是同一个值。
// `hazeColor` 由调用方按当前下界雾色给出，`outputScale` 把散射换算到目标管线单位。
float4 ogxNetherVolumetricFog(float3 rayDirection, float3 cameraOffset, float3 cameraWorldPos,
    float startDist, float endDist, float ditherA, float ditherB, int samples, float expFactor, float maxDist, float farPlane,
    float plumeDensityScale, float hazeDensityScale, float ceilingDensityScale, float3 hazeColor,
    float outputScale, float time, Sampler2D noiseTexture)
{
    endDist = min(endDist, maxDist); // 最远只步进到参考实现的距离上限。
    float rayLength = endDist - startDist; // 这一段视线的长度。
    if (rayLength <= 0.0) return float4(0.0, 0.0, 0.0, 1.0); // 空段或反向段直接返回。
    float3 segment = rayDirection * rayLength; // 整段的相机相对世界向量。
    float dL = rayLength; // 光学厚度的段长。
    float3 base = cameraOffset + rayDirection * startDist; // 相机相对世界里的起点。
    float3 color = float3(0.0); // 累加的散射色。
    float absorbance = 1.0; // 剩余透射率，从全透开始。
    for (int i = 0; i < samples; i++) // 沿这一段逐步前进。
    {
        float d = (pow(expFactor, (float(i) + ditherB) / float(samples)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 指数步长在段上的位置。
        float dd = pow(expFactor, (float(i) + ditherA) / float(samples)) * log(expFactor) / float(samples) / (expFactor - 1.0); // 这一步的厚度权重。
        float3 relPos = base + d * segment; // 采样点的相机相对位置。
        float dist = length(relPos); // 到相机的距离。
        float3 worldPos = relPos + cameraWorldPos; // 绝对世界位置，体积噪声要它。
        float densityVol = ogxNetherFogCloudVolume(worldPos, time, noiseTexture); // 这一点的原始体积密度。
        float clearArea = 1.0 - min(max(1.0 - dist / 24.0, 0.0), 1.0); // 相机二十四米内淡出。
        float plume = min(densityVol * pow(min(max(100.0 - worldPos.y, 0.0) / 30.0, 1.0), 4.0), pow(clamp(1.0 - dist / farPlane, 0.0, 1.0), 5.0)); // 越低越浓、越远越淡。
        plume *= plumeDensityScale; // 乘羽流密度选项。
        float plumeCoeff = exp(-plume * dd * dL); // 羽流吸收掉的光。
        float3 plumeLight = float3(1.0, 0.4, 0.2) * 0.25 * exp(-15.0 * densityVol) * (clearArea * clearArea * 0.9 + 0.1); // 暖橙色，密度高处压暗。
        color += (plumeLight - plumeLight * plumeCoeff) * absorbance; // 叠上羽流散射。
        absorbance *= plumeCoeff; // 透射率下降。
        float hazeDensity = 0.001 * hazeDensityScale; // 很低的均匀密度。
        float hazeCoeff = exp(-hazeDensity * dd * dL); // 雾霭吸收。
        color += (hazeColor - hazeColor * hazeCoeff) * absorbance; // 只加散射，不回乘透射率。
        float ceilingDensity = 0.001 * pow(min(max(worldPos.y - 40.0, 0.0) / 50.0, 1.0), 3.0) * ceilingDensityScale; // 越高越浓。
        float ceilingCoeff = exp(-ceilingDensity * dd * dL); // 顶部烟吸收。
        float3 ceilingSmoke = float3(0.1); // 固定灰烟颜色。
        color += (ceilingSmoke - ceilingSmoke * ceilingCoeff) * (absorbance * 0.5 + 0.5); // 半强度叠加。
        absorbance *= ceilingCoeff; // 透射率继续下降。
    }
    return float4(color * outputScale, absorbance); // 返回换算后的散射色与剩余透射率。
}
