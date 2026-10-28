/* 层状体积云的五层合成：按参考顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合；由 `cloud/layers/march.slang` 内联引入。
可复制示例：`float4 cloud = ogxLayersGetVolumetricClouds(settings, viewPos, dither, ...);`
设计取舍：每层重算步长与起点，天空盒只在起点查一次，采样位置与参考一致。 */

// 五层体积云总入口：按参考实现的顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合。
// 天空色由本函数在步进起点处查天空盒，与参考 GetVolumetricClouds 的采样位置一致。
float4 ogxLayersGetVolumetricClouds(OgxLayersCloudSettings s, float3 viewPos, float2 dither, float3 sunVector,
    float3 moonVector, float3 directLightCol, float3 directLightCol2, float3 indirectLightCol,
    inout float cloudPlaneDistance, inout float2 cloudDistance, float3 cameraPos, Sampler2D skyTexture, float2 texelSize,
    float farPlane, float dhFarPlane, float4x4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, Sampler2D noiseTexture,
    Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort)
{
    float3 color = float3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 累积透过率。
    float4 cloudColor = float4(color, totalAbsorbance); // 当前层结果。
    float4 cloudColorOriginal = cloudColor; // 每层重置用。
    float cloudheight = s.layers[0].tallness / s.layers[0].scale; // 第一层厚度。
    float minHeight = s.layers[0].height; // 第一层云底。
    float maxHeight = cloudheight + minHeight; // 第一层云顶。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - minHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层的高度。
    float maxdist = dhFarPlane > 0.0 ? dhFarPlane - 16.0 : farPlane + 16.0 * 5.0; // 最大可见距离。
    float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 1.0e8; // 参考实现的距离哨兵。
    float4 normPlayerPos = float4(ogxMatrixMulPoint(modelViewInverse, viewPos) + ogxMatrixTranslation(modelViewInverse), 1.0); // 视空间转世界。
    normPlayerPos = normalize(normPlayerPos); // 单位视线方向。
    float sdotv = dot(sunVector, normPlayerPos.xyz); // 太阳与视线夹角。
    float sdotv2 = dot(moonVector, normPlayerPos.xyz); // 月亮与视线夹角。
    if (skyGround) normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点，避免云压到地平线。
    float cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
        clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 相机在层内时水平步长更小。
    float3 cloudDist = float3(1.0); // 水平与竖直步长。
    cloudDist.xz = lerp(float2(255.0), float2(5.5), cloudMix); // 层内 5.5，层外 255。
    float3 rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / min(cloudDist, float3(0.05 * lViewPosM))) / float(samples)); // 一层走完的步长。
    float3 rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点压到云层平面。
    float3 sampledSkyCol = ogxSkyGradientLookup(normalize(rayPosition - cameraPos), skyTexture, texelSize) / 1200.0; // 参考在第一步后查天空盒。
    if (skyGround) // 参考 SKY_GROUND 分支：地面视角把天空色混向间接光。
    {
        if (s.cumulonimbus > 1.0) heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - 6000.0, 0.0) / 100.0, 0.0, 1.0); // 积雨云开启时改用六千米基准。
        sampledSkyCol = lerp(sampledSkyCol, indirectLightCol, heightRelativeToClouds); // 与参考相同的混合。
    }
    sampledSkyCol *= skyBrightness; // 天空亮度。
    float3 playerPos = ogxMatrixMulPoint4(modelViewInverse, float4(viewPos, 1.0)).xyz; // 相机相对世界位置。
    float maxLength = min(length(playerPos), farPlane) / max(length(playerPos), 1e-4); // 限制到远平面。
    playerPos *= maxLength; // 截断。
    float startDistance = length(playerPos); // 到像素的距离。
    float sunVis = smoothstep(-0.06, 0.1, s.sunElevation); // 太阳可见度。
    float moonVis = smoothstep(0.0, 0.075, -s.moonElevation); // 月亮可见度。
    float backScatterPhase = 0.0; // 太阳后向散射。
    float4 phaseLevels = float4(0.0); // 太阳四档相函数。
    if (sunVis > 0.0) // 太阳在地平线上才算。
    {
        backScatterPhase = ogxLayersPhaseCloud(-sdotv, 0.25, 0) * 2.0; // 后向。
        phaseLevels = float4(ogxLayersPhaseCloud(sdotv, 0.80, 0), ogxLayersPhaseCloud(sdotv, 0.55, 0),
            ogxLayersPhaseCloud(sdotv, 0.35, 0), ogxLayersPhaseCloud(sdotv, 0.10, 0)); // 四档前向。
    }
    float backScatterPhase2 = 0.0; // 月亮后向。
    float4 phaseLevels2 = float4(0.0); // 月亮四档。
    if (moonVis > 0.0) // 月亮在地平线上才算。
    {
        backScatterPhase2 = ogxLayersPhaseCloud(-sdotv2, 0.25, 0) * 2.0; // 后向。
        phaseLevels2 = float4(ogxLayersPhaseCloud(sdotv2, 0.80, 0), ogxLayersPhaseCloud(sdotv2, 0.55, 0),
            ogxLayersPhaseCloud(sdotv2, 0.35, 0), ogxLayersPhaseCloud(sdotv2, 0.10, 0)); // 四档前向。
    }
    float3 sunScattering = directLightCol * sunVis * sunVis; // 太阳散射。
    float3 moonScattering = directLightCol2 * moonVis * moonVis * (1.0 - sunVis * sunVis); // 月亮散射。
    float3 skyScattering = indirectLightCol * (1.0 + sunVis); // 天空散射。
    bool mixBelowLayer0 = cameraPos.y < s.layers[0].height + s.layers[0].tallness; // 相机是否在小积云下方。
    bool mixBelowLayer1 = cameraPos.y < s.layers[1].height; // 相机是否在大积云下方。
    float4 smallCumulusClouds = cloudColorOriginal; // 小积云结果。
    float2 cloudLayer0Distance = float2(startDistance, 1.0); // 小积云距离。
    smallCumulusClouds = ogxLayersRaymarchCloud(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer0Distance,
        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
        shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 小积云。
    cloudColor.a *= smallCumulusClouds.a; // 更新透过率。
    float smallCumulusDistance = length(rayPosition - cameraPos); // 小积云命中距离。
    float4 largeCumulusClouds = cloudColorOriginal; // 大积云结果。
    float2 cloudLayer1Distance = float2(startDistance, 1.0); // 大积云距离。
    if (cloudColor.a > 1e-5 || !mixBelowLayer1) // 有剩余光且相机位置合适。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
            clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 重算混合。
        cloudDist.xz = lerp(float2(255.0), float2(5.0), cloudMix); // 大积云水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(samples)); // 重算步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        largeCumulusClouds = ogxLayersRaymarchCloud(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer1Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 大积云。
        cloudColor.a *= largeCumulusClouds.a; // 更新透过率。
    }
    float largeCumulusDistance = length(rayPosition - cameraPos); // 大积云命中距离。
    float4 cumulonimbusClouds = cloudColorOriginal; // 积雨云结果。
    float2 cloudLayer4Distance = float2(startDistance, 1.0); // 积雨云距离。
    if (s.cumulonimbus > 0 && (cloudColor.a > 1e-5 || !mixBelowLayer0)) // 开启积雨云。
    {
        cloudheight = 4000.0; // 积雨云厚度。
        minHeight = 600.0; // 积雨云底。
        maxHeight = cloudheight + minHeight; // 积雨云顶。
        int cumulonimbusSamples = 2 * samples; // 两倍样本。
        cloudDist.xz = float2(8.0); // 固定水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(cumulonimbusSamples)); // 重算步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        cumulonimbusClouds = ogxLayersRaymarchCloud(s, 2, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol,
            cloudLayer4Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds,
            deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 积雨云。
        cloudColor.a *= cumulonimbusClouds.a; // 更新透过率。
    }
    float cumulonimbusDistance = length(rayPosition - cameraPos); // 积雨云命中距离。
    float4 altoStratusClouds = cloudColorOriginal; // 高层云结果。
    float2 cloudLayer2Distance = float2(startDistance, 1.0); // 高层云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画高层云。
    {
        cloudheight = 5.0; // 高层云很薄。
        minHeight = s.layers[3].height; // 高层云底。
        maxHeight = cloudheight + minHeight; // 高层云顶。
        cloudDist.xz = lerp(float2(255.0), float2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        altoStratusClouds = ogxLayersRaymarchCloud(s, 3, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer2Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 高层云。
        cloudColor.a *= altoStratusClouds.a; // 更新透过率。
    }
    float4 cirrusClouds = cloudColorOriginal; // 卷云结果。
    float2 cloudLayer3Distance = float2(startDistance, 1.0); // 卷云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画卷云。
    {
        cloudheight = 5.0; // 卷云很薄。
        minHeight = s.layers[4].height; // 卷云底。
        maxHeight = cloudheight + minHeight; // 卷云顶。
        cloudDist.xz = lerp(float2(255.0), float2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        cirrusClouds = ogxLayersRaymarchCloud(s, 4, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer3Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 卷云。
        cloudColor.a *= cirrusClouds.a; // 更新透过率。
    }
    if (cameraPos.y > s.layers[1].height) // 相机在大积云上方时交换远近层。
    {
        float2 temp = cloudLayer1Distance;
        cloudLayer1Distance = cloudLayer0Distance;
        cloudLayer0Distance = temp;
    }
    float tempDistance = lerp(cloudLayer2Distance.x, cloudLayer3Distance.x, cloudLayer2Distance.y); // 高层与卷云按权重混合。
    tempDistance = lerp(cloudLayer1Distance.x, tempDistance, cloudLayer1Distance.y); // 大积云再混合。
    cloudPlaneDistance = lerp(cloudLayer0Distance.x, tempDistance, cloudLayer0Distance.y); // 小积云再混合。
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
    return float4(color, totalAbsorbance); // 交回云颜色与透过率。
}
