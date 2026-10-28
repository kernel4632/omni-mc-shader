// 末地云影子文件：按太阳方向在云层高度取两次密度，再换成地面阴影。
// 调用位置：由 `world/end.slang` 内联；需要复现 iterationT 云影查表的程序调用 `ogxCloudShadowTex`。
// 设计原因与取舍：只算基础形状、不算细节层，和参考实现的 `sampleDetail=false` 一致；噪声贴图与画质由调用方给出。
// 可复制示例：`float s = ogxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);`

// 云影密度函数的提前声明：云影查表会先调用它，定义放在文件末尾。
float3 ogxCloudShadowDensity(float4 cloudPos, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float3 windDirection);

// iterationT 云影查表：按太阳方向在云层高度取样两次，取较大密度后做指数衰减。
// `baseNoise` 是云形状噪声；`coverage` 与 `wetness` 由调用方按菜单填写。
float ogxCloudShadowTex(float2 coord, float2 cloudAltitude, float3 windDirection, float2 cameraXZ,
    float3 worldShadowVector, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float shadowRange)
{
    coord = coord * shadowRange - shadowRange * 0.5; // 屏幕坐标转云影范围。
    float4 checkPos = float4(coord.x + cameraXZ.x, 0.0, coord.y + cameraXZ.y, 0.0); // 云影起点。
    float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
    checkPos += float4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y), 0.25); // 沿太阳方向抬到云层。
    float3 density = ogxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection); // 第一次取样。
    checkPos += float4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y), 0.25); // 再抬四分之一层。
    density = max(density, ogxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection)); // 第二次取样。
    return exp2(-density.y * 20.0); // 参考实现的云影衰减。
}

// 云影密度：只算基础形状，不算细节层，和参考实现的 `sampleDetail=false` 一致。
float3 ogxCloudShadowDensity(float4 cloudPos, Sampler3D baseNoise, float baseScale, float3 coverageOffset,
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
