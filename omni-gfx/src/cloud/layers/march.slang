/* 层状体积云的步进：五层主循环、低成本透过率与严格入口；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetVolumetricClouds(settings, viewPos, dither, sunVector, ...);`
设计取舍：五层按参考顺序步进再按相机高度合成，简单版只累计透过率，严格版只重排参考签名。 */

// 单层云的步进：参考实现的主循环，逐层处理平面云与积云两条路径。
// `cloudPlaneDistance` 的 `x` 是最近可见云的距离，`y` 是混合权重；由调用方按层合并。
float4 ogxLayersRaymarchCloud(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
    float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,
    float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,
    inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,
    float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,
    Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort)
{
    float3 color = float3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 一步的世界长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = lerp(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex == 3 || layerIndex == 4) // 平面云路径。
    {
        float density = 0.0; // 这一层的密度。
        float3 newPos = rayPosition - cameraPos; // 相机相对位置。
        if (layerIndex == 3) density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 高层云。
        else density = s.layers[4].rainDensity * smoothstep(s.layers[4].distance, s.layers[4].distance * 0.5, length(newPos)); // 卷云。
        if (density == 0.0) return float4(color, totalAbsorbance); // 距离外没有云。
        bool ifAboveOrBelowPlane = max(lerp(-1.0, 1.0, clamp(cameraPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面的哪一侧。
        if (!deferred && length(newPos) > referenceDistance) return float4(color, totalAbsorbance); // 世界几何挡住云。
        if (ifAboveOrBelowPlane) return float4(color, totalAbsorbance); // 背向云层的一侧不步进。
        float shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 取样形状。
        float shapeWithDensity = shape * density; // 乘密度。
        if (shapeWithDensity > lerp(1e-5, 0.06, dither)) // 记录最近可见云。
        {
            cloudPlaneDistance.x = length(newPos);
            cloudPlaneDistance.y = 0.0;
        }
        if (shapeWithDensity > 1e-5) // 有云才做光照。
        {
            float sunShadowMask = ogxLayersGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture) * (1.0 - abs(sunVector.y)); // 朝光遮挡。
            float indirectShadowMask = 0.5; // 平面云间接光固定半量。
            float3 lighting = ogxLayersGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensity, sunShadowMask,
                sunScattering, moonScattering, indirectShadowMask, skyScattering, rayPosition, backScatterPhase, phaseLevels,
                backScatterPhase2, phaseLevels2); // 光照。
            newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视的距离压缩。
            float distancefog = exp2(0.4 * s.distanceFogScale * length(newPos.xz)); // 距离雾。
            float3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
            lighting = lighting * distancefog + atmosphereHaze; // 混进雾。
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 这一段的透过率。
            color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 按剩余透过率累加。
            totalAbsorbance *= densityCoeff; // 更新透过率。
        }
        return float4(color, totalAbsorbance); // 平面云只取一个样本。
    }
    if (layerIndex < 3) // 积云路径。
    {
        float3 newPos = rayPosition - cameraPos; // 相机相对位置。
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(newPos)); // 小积云距离淡出。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(newPos)); // 大积云距离淡出。
        if (layerIndex == 2) density = 0.8; // 积雨云固定密度。
        if (density < 0.01) return float4(color, totalAbsorbance); // 密度太低跳过。
        float3 lightningPos = float3(0.0); // 积雨云闪电位置。
        if (s.lightningEnabled > 0 && layerIndex == 2) lightningPos = ogxLayersGetLightningPosition(s, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 只有积雨云取闪电位。
        float3 mainLightVec = normalize(lerp(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
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
                if (layerIndex != 2) shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    float2 cumulonimbusCloud = ogxLayersGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
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
                    float3 shadow = float3(1.0); // 地形阴影默认全亮。
                    if (terrainShadowOnClouds) // 开启地形阴影时投到阴影图。
                    {
                        float3 fragPosition = ogxMatrixMulPoint(shadowView, newPos) + ogxMatrixTranslation(shadowView); // 阴影相机空间。
                        fragPosition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragPosition
                            + ogxMatrixTranslation(shadowProjection); // 阴影投影。
                        float distortFactor = shadowDistort > 0.0 ? 1.0 / (log(length(fragPosition.xy) * 0.61 + 1.0) * 1.8) : 1.0; // 参考实现的边缘压缩。
                        float3 shadowPos = float3(fragPosition.xy * distortFactor, fragPosition.z); // 压缩后的阴影坐标。
                        if (abs(shadowPos.x) < 1.0 - 0.5 / 2048.0 && abs(shadowPos.y) < 1.0 - 0.5 / 2048.0) // 在阴影图内。
                        {
                            shadowPos = shadowPos * float3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 转零到一。
                            shadow = float3(shadowTexture.SampleLevel(shadowPos.xy, 0.0).x); // 读阴影。
                        }
                    }
                    float skylightOcclusion = 1.0; // 参考在极光开启时每个样本重算上层遮挡。
                    // 极光关闭（AURORA_LOCATION=0）的参考变体只算一次；这里按默认开启分支实现，
                    // 保证严格对照的 7621 次采样与默认配置一致。
                    if (layerIndex == 0) // 小积云会被大积云遮住天光。
                    {
                        float upperLayerOcclusion = ogxLayersGetCloudShape(s, 1, 0, rayPosition + float3(0.0, 1.0, 0.0)
                            * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0), s.layers[1].height,
                            s.layers[1].height + s.layers[1].height / s.layers[1].scale, noiseTexture); // 参考的层顶。
                        skylightOcclusion = lerp(lerp(0.0, 0.2, densityLarge), 1.0,
                            pow(1.0 - upperLayerOcclusion * densityLarge, 5.0)); // 参考极光分支用五次方。
                    }
                    float indirectShadowMask = 1.0 - min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0); // 间接光遮挡。
                    float sunShadowMask = ogxLayersGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                        minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture); // 朝光遮挡。
                    float3 shadowStartPos = float3(0.0); // 层间阴影起点。
                    if (layerIndex == 0) // 大积云投到小积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0); // 投到上层。
                        sunShadowMask += 3.0 * ogxLayersGetCloudShape(s, 1, 0, shadowStartPos, s.layers[1].height,
                            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * densityLarge; // 上层遮挡。
                    }
                    if (layerIndex != 2 && s.cumulonimbus > 0) // 积雨云投到其他积云。
                    {
                        float angle = clamp(degrees(acos(dot(float3(0.0, 1.0, 0.0), mainLightVec))), 45.0, 90.0) - 45.0; // 参考保留的角度项，当前不参与距离。
                        shadowStartPos = rayPosition + mainLightVec * 9000.0; // 大步投到积雨云。
                        sunShadowMask += ogxLayersGetCumulonimbusShape(s, 0, shadowStartPos, 600.0, 4600.0 + shadowStartPos.y, 1.0, cameraPos, noiseTexture).x * 3.0; // 积雨云遮挡。
                    }
                    shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max(s.layers[3].height - rayPosition.y, 0.0); // 投到高层云。
                    sunShadowMask += ogxLayersGetCloudShape(s, 3, 0, shadowStartPos, s.layers[3].height, s.layers[3].height, noiseTexture)
                        * s.layers[3].rainDensity * (1.0 - abs(mainLightVec.y)); // 高层云遮挡。
                    float3 lighting = ogxLayersGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensityFaded, sunShadowMask,
                        sunScattering * shadow, moonScattering * shadow, indirectShadowMask, skyScattering * skylightOcclusion, rayPosition,
                        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2); // 光照。
                    float horizontalDist = length(newPos.xz - s.lightningBoltPosition.xz); // 普通闪电水平距离。
                    if (horizontalDist < 7500.0 && s.lightningBoltPosition.w > 0.0) // 普通闪电照亮云。
                    {
                        float lightningIntensity = exp(-horizontalDist * 0.006) * density * s.lightningFlash; // 闪电强度。
                        lighting = lerp(lighting, float3(1.3, 1.5, 3.0), lightningIntensity); // 混向冷白。
                    }
                    if (s.lightningEnabled > 0 && (layerIndex == 2 || s.thunderStrength > 0.0)) // 积雨云闪电。
                    {
                        float lightningDist = length(newPos - lightningPos); // 到闪电位距离。
                        if (lightningDist < 6000.0 && length(lightningPos) > 0.0) // 在照明范围内。
                        {
                            float lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity)
                                * s.lightningFlash; // 距离与密度权重。
                            lightningIntensity *= 1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y); // 高度淡出。
                            lightningIntensity *= smoothstep(17000.0, 14000.0, horizontalDist); // 水平淡出。
                            lightningIntensity *= s.lightningFade; // 时间淡出。
                            float3 lightningStrength = s.cumulonimbusLightningColor * s.cumulonimbusLightningBrightness * 0.125; // 闪电颜色。
                            lighting = lerp(lighting, lightningStrength, lightningIntensity); // 混向闪电。
                        }
                    }
                    lighting += s.auroraLighting * min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0) * skylightOcclusion * skylightOcclusion; // 参考的极光按云内高度与天光遮挡叠加。
                    newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视距离压缩。
                    float distancefog = exp2(s.distanceFogScale * length(newPos.xz)); // 距离雾。
                    float3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
                    lighting = lighting * distancefog + atmosphereHaze; // 混雾。
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded); // 这一段透过率。
                    color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 累加。
                    totalAbsorbance *= densityCoeff; // 更新透过率。
                    if (totalAbsorbance < 1e-5) break; // 已经完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
        return float4(color, totalAbsorbance); // 交回这一层的颜色与透过率。
    }
    return float4(color, totalAbsorbance); // 未知层号原样返回。
}

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

// 云影步进：只算透过率，不算光照，供阴影程序低成本使用。
float ogxLayersRaymarchCloudSimple(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition,
    float3 rayDirection, float dither, float minHeight, float maxHeight, float3 startPos, float3 cameraPos,
    Sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 初始完全透明。
    float distanceFactor = length(rayDirection); // 一步长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3) densityThresholdCheck = 0.01; // 高层云。
    densityThresholdCheck = lerp(1e-5, densityThresholdCheck, dither); // 按抖动插值。
    if (layerIndex == 3) // 高层云单样本。
    {
        float3 newPos = rayPosition - startPos; // 相对起点。
        float density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 距离密度。
        if (density == 0.0) return totalAbsorbance; // 距离外没有云。
        bool ifAboveOrBelowPlane = max(lerp(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0))
            * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面哪一侧。
        if (ifAboveOrBelowPlane) return totalAbsorbance; // 背向不步进。
        float shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 形状。
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
                if (layerIndex != 2) shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    float2 cumulonimbusCloud = ogxLayersGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
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
float4 ogxLayersGetVolumetricCloudsSimple(OgxLayersCloudSettings s, float2 dither, float3 lightDir, float2 offset,
    float3 startPos, float3 cameraPos, Sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - s.layers[0].height, 0.0) / 100.0, 0.0, 1.0); // 相机高度。
    float3 normPlayerPos = lightDir; // 光线方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点。
    int samples = 5; // 固定五步。
    float3 cloudDist = float3(1.0); // 水平步长。
    float cloudheight = 5.0; // 高层云厚度。
    float minHeight = s.layers[3].height; // 高层云底。
    float maxHeight = cloudheight + minHeight; // 高层云顶。
    cloudDist.xz = float2(255.0); // 平面云水平步长。
    float3 rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步。
    float3 rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
    rayPosition.xz += offset; // 阴影偏移。
    float altoStratusClouds = ogxLayersRaymarchCloudSimple(s, 3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        startPos, cameraPos, noiseTexture); // 高层云。
    totalAbsorbance *= altoStratusClouds; // 更新透过率。
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudDist.xz = float2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        largeCumulusClouds = ogxLayersRaymarchCloudSimple(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 大积云。
        totalAbsorbance *= largeCumulusClouds; // 更新透过率。
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[0].tallness / s.layers[0].scale; // 小积云厚度。
        minHeight = s.layers[0].height; // 小积云底。
        maxHeight = cloudheight + minHeight; // 小积云顶。
        cloudDist.xz = float2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        smallCumulusClouds = ogxLayersRaymarchCloudSimple(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 小积云。
        totalAbsorbance *= smallCumulusClouds; // 更新透过率。
    }
    return float4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四个透过率。
}

// 层状云低成本步进：只累计透过率，不做光照，供云影与远景使用。
// 参考签名给层号、步数、位置与方向、抖动与上下界；噪声、天气与覆盖率显式追加。
float ogxLayersCloudAbsorbanceSimple(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
    float dither, float minHeight, float maxHeight, float3 startPos,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float rainAmount,
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage,
    float largeCumulusCoverage, float smallCumulusCoverage,
    float altostratusRain, float largeCumulusRain, float smallCumulusRain)
{
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 每步长度。
    float densityTresholdCheck = 0.0; // 密度阈值，按层选择。
    if (layerIndex == 0) densityTresholdCheck = 0.06;
    if (layerIndex == 1 || layerIndex == 2) densityTresholdCheck = 0.02;
    if (layerIndex == 3) densityTresholdCheck = 0.01;
    densityTresholdCheck = lerp(1e-5, densityTresholdCheck, dither); // 用抖动在极小值与阈值之间插值。
    if (layerIndex == 3) // 高层云只做一次平面近似。
    {
        float3 newPos = rayPosition - startPos;
        float density = altostratusRain;
        density *= smoothstep(150000.0, 150000.0 * 0.5, length(newPos)); // 超出距离后淡出。
        if (density == 0.0) return totalAbsorbance;
        bool ifAboveOrBelowPlane = max(lerp(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在云层上方或下方时就跳过。
        if (ifAboveOrBelowPlane) return totalAbsorbance;
        float shape = ogxLayersCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
            noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            rainAmount, thunderStrength, cloudMovement);
        float shapeWithDensity = shape * density;
        if (shapeWithDensity > 1e-5)
        {
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 单步吸收。
            totalAbsorbance *= densityCoeff;
        }
        return totalAbsorbance;
    }
    if (layerIndex < 3) // 积云与积雨云按步数前进。
    {
        float3 newPos = rayPosition - startPos;
        float densityLarge = ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength);
        float density = 0.0;
        if (layerIndex == 0) density = ogxLayersGetRainDensity(smallCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
        if (layerIndex == 1) density = ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
        if (layerIndex == 2) density = 0.8;
        if (density < 0.01) return totalAbsorbance;
        float tallness = maxHeight - minHeight;
        for (int i = 0; i < samples; i++)
        {
            newPos = rayPosition - startPos;
            float rayHeightInCloud = rayPosition.y - minHeight;
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 只处理云层内部的采样。
            {
                float shape = 0.0;
                float isLarge = 1.0;
                if (layerIndex != 2)
                {
                    shape = ogxLayersCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
                        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                        rainAmount, thunderStrength, cloudMovement);
                }
                else
                {
                    float2 cumulonimbusCloud = ogxLayersCumulonimbusShapeLayer(1, rayPosition, minHeight, maxHeight,
                        noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength);
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y;
                }
                float shapeWithDensity = shape * density * isLarge;
                float shapeWithDensityFaded = shape * density * pow(clamp((rayHeightInCloud) / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 底部淡出。
                if (shapeWithDensityFaded > 1e-5)
                {
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded);
                    totalAbsorbance *= densityCoeff;
                    if (totalAbsorbance < 1e-5) break; // 已经全黑就提前结束。
                }
            }
            rayPosition += rayDirection; // 前进一步。
        }
    }
    return totalAbsorbance; // 交回透过率。
}

// 层状云影总入口的简单版：三层云各走一次低成本步进，乘成总透过率。
// 参考签名是抖动、光照方向、偏移与起点；云噪声、天气、覆盖率与相机位置显式追加。
float4 ogxLayersCloudTransmittanceSimple(float2 dither, float3 lightDir, float2 offset, float3 startPos,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float rainAmount,
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage,
    float largeCumulusCoverage, float smallCumulusCoverage,
    float altostratusRain, float largeCumulusRain, float smallCumulusRain)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraWorldPos.y - 250.0, 0.0) / 100.0, 0.0, 1.0); // 相机离云底越近，抬高越少。
    float3 normPlayerPos = lightDir; // 光照方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角把光线抬高一点。
    int samples = 5; // 每层固定五步。
    float3 cloudDist = float3(1.0); // 水平步长。
    float3 rayDirection; // 步进方向。
    float3 rayPosition; // 步进起点。
    float cloudheight; // 云层厚度。
    float minHeight; // 云底。
    float maxHeight; // 云顶。
    float altoStratusClouds = 1.0; // 高层云透过率。
    cloudheight = 5.0;
    minHeight = 5000.0;
    maxHeight = cloudheight + minHeight;
    cloudDist.xz = float2(255.0);
    rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步长度。
    rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 找到进入云层的起点。
    rayPosition.xz += offset; // 阴影偏移。
    altoStratusClouds = ogxLayersCloudAbsorbanceSimple(3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
        noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
        altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        altostratusRain, largeCumulusRain, smallCumulusRain); // 高层云。
    totalAbsorbance *= altoStratusClouds;
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5)
    {
        cloudheight = 280.0;
        minHeight = 400.0;
        maxHeight = cloudheight + minHeight;
        cloudDist.xz = float2(255.0);
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 按步数均分厚度。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        largeCumulusClouds = ogxLayersCloudAbsorbanceSimple(1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 大积云。
        totalAbsorbance *= largeCumulusClouds;
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5)
    {
        cloudheight = 130.0 / 1.0;
        minHeight = 250.0;
        maxHeight = cloudheight + minHeight;
        minHeight = 250.0 - 350.0; // 参考把小积云底向下扩了三百五十米。
        maxHeight = cloudheight + minHeight;
        cloudDist.xz = float2(255.0);
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples));
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        smallCumulusClouds = ogxLayersCloudAbsorbanceSimple(0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 小积云。
        totalAbsorbance *= smallCumulusClouds;
    }
    return float4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四层透过率。
}

// 严格参考签名的单层云步进入口：参考参数在前，云设置、相机与阴影资源追加在后。
// 主体仍由 `ogxLayersRaymarchCloud` 执行，入口只负责把显式参数重新排好。
// 五层云的高度、厚度与距离按参考默认配置传入，避免把宿主菜单常数藏进结构体。
float4 ogxLayersRaymarchCloudExact(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
    float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,
    float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,
    inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,
    float4 phaseLevels2, OgxLayersCloudSettings settings, float3 cameraPos, bool terrainShadowOnClouds,
    bool deferred, Sampler2D noiseTexture, Sampler2D shadowTexture, float4x4 shadowView,
    float4x4 shadowProjection, float shadowResolution, float shadowDistort, float4 layer0Size,
    float4 layer1Size, float4 layer2Size, float3 layer3Size, float3 layer4Size, float3 auroraRgb,
    float auroraBrightness, float auroraAmount, float3 customLightningRgb)
{
    settings.layers[0].height = layer0Size.x; // 小积云高度。
    settings.layers[0].tallness = layer0Size.y; // 小积云厚度。
    settings.layers[0].scale = layer0Size.z; // 小积云水平尺度。
    settings.layers[0].distance = layer0Size.w; // 小积云可见距离。
    settings.layers[1].height = layer1Size.x; // 大积云高度。
    settings.layers[1].tallness = layer1Size.y; // 大积云厚度。
    settings.layers[1].scale = layer1Size.z; // 大积云水平尺度。
    settings.layers[1].distance = layer1Size.w; // 大积云可见距离。
    settings.layers[2].height = layer2Size.x; // 高层云高度。
    settings.layers[2].distance = layer2Size.y; // 高层云可见距离。
    settings.layers[2].scale = layer2Size.z; // 高层云水平尺度。
    settings.layers[3].height = layer3Size.x; // 卷云高度。
    settings.layers[3].distance = layer3Size.y; // 卷云可见距离。
    settings.layers[3].scale = layer3Size.z; // 卷云水平尺度。
    settings.layers[4].height = layer4Size.x; // 额外云层高度。
    settings.layers[4].distance = layer4Size.y; // 额外云层可见距离。
    settings.layers[4].scale = layer4Size.z; // 额外云层水平尺度。
    settings.auroraLighting = 0.015 * auroraBrightness * (sin(auroraRgb + 0.63) * 0.5 + 0.5) * auroraAmount
        * smoothstep(0.0, -0.1, sunVector.y) * smoothstep(0.1, 0.0, moonVector.y); // 参考的极光光照。
    settings.cumulonimbus = 1; // 参考默认 CUMULONIMBUS=1。
    settings.cumulonimbusLightningBrightness = 100.0; // 参考默认 CUMULONIMBUS_LIGHTNING_BRIGHTNESS。
    settings.cumulonimbusLightningColor = float3(customLightningRgb.x, 1.05 * customLightningRgb.y,
        1.22 * customLightningRgb.z); // 参考的积雨云闪电颜色。
    return ogxLayersRaymarchCloud(settings, layerIndex, samples, rayPosition, rayDirection, dither, minHeight,
        maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance,
        sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2,
        cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调同一份层步进。
}

// 严格参考签名的体积云总入口：参考参数在前，云层尺寸、极光与天空盒资源追加在后。
// 云层尺寸和极光参数在这里写成常数，参考的首页天空盒查表也在这里完成，采样顺序与参考一致。
float4 ogxLayersGetVolumetricCloudsExact(float3 viewPos, float2 dither, float3 sunVector, float3 moonVector,
    float3 directLightCol, float3 directLightCol2, float3 indirectLightCol, inout float cloudPlaneDistance,
    inout float2 cloudDistance, OgxLayersCloudSettings settings, float3 cameraPos, float farPlane,
    float dhFarPlane, float4x4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, float4 layer0Size, float4 layer1Size, float4 layer2Size,
    float3 layer3Size, float3 layer4Size, float3 auroraRgb, float auroraBrightness, float auroraAmount,
    float3 customLightningRgb, Sampler2D noiseTexture, Sampler2D shadowTexture, float4x4 shadowView,
    float4x4 shadowProjection, float shadowResolution, float shadowDistort, Sampler2D skyTexture, float2 texelSize)
{
    settings.layers[0].height = layer0Size.x; // 小积云高度。
    settings.layers[0].tallness = layer0Size.y; // 小积云厚度。
    settings.layers[0].scale = layer0Size.z; // 小积云水平尺度。
    settings.layers[0].distance = layer0Size.w; // 小积云可见距离。
    settings.layers[1].height = layer1Size.x; // 大积云高度。
    settings.layers[1].tallness = layer1Size.y; // 大积云厚度。
    settings.layers[1].scale = layer1Size.z; // 大积云水平尺度。
    settings.layers[1].distance = layer1Size.w; // 大积云可见距离。
    settings.layers[2].height = layer2Size.x; // 高层云高度。
    settings.layers[2].distance = layer2Size.y; // 高层云可见距离。
    settings.layers[2].scale = layer2Size.z; // 高层云水平尺度。
    settings.layers[3].height = layer3Size.x; // 卷云高度。
    settings.layers[3].distance = layer3Size.y; // 卷云可见距离。
    settings.layers[3].scale = layer3Size.z; // 卷云水平尺度。
    settings.layers[4].height = layer4Size.x; // 额外云层高度。
    settings.layers[4].distance = layer4Size.y; // 额外云层可见距离。
    settings.layers[4].scale = layer4Size.z; // 额外云层水平尺度。
    settings.auroraLighting = 0.015 * auroraBrightness * (sin(auroraRgb + 0.63) * 0.5 + 0.5) * auroraAmount
        * smoothstep(0.0, -0.1, sunVector.y) * smoothstep(0.1, 0.0, moonVector.y); // 参考的极光光照。
    settings.cumulonimbus = 1; // 参考默认 CUMULONIMBUS=1。
    settings.cumulonimbusLightningBrightness = 100.0; // 参考默认 CUMULONIMBUS_LIGHTNING_BRIGHTNESS。
    settings.cumulonimbusLightningColor = float3(customLightningRgb.x, 1.05 * customLightningRgb.y,
        1.22 * customLightningRgb.z); // 参考的积雨云闪电颜色。
    return ogxLayersGetVolumetricClouds(settings, viewPos, dither, sunVector, moonVector, directLightCol,
        directLightCol2, indirectLightCol, cloudPlaneDistance, cloudDistance, cameraPos, skyTexture, texelSize,
        farPlane, dhFarPlane, modelViewInverse, samples, deferred, skyGround, skyBrightness,
        terrainShadowOnClouds, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调五层总入口。
}
