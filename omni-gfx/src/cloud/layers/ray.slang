/* 层状体积云的单层主步进：五层共用同一套循环与光照，按层号分支；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`float4 clouds = ogxCloudLayerMarch(settings, 1, 32, rayPosition, rayDirection, dither, 500.0, 2500.0, sunVector, moonVector, sunScattering, moonScattering, skyScattering, 10000.0, skyColor, cloudDistance, 0.0, phases, 0.0, phases, cameraPos, true, false, noiseTexture, shadowTexture, shadowView, shadowProjection, 2048.0, 1.0);` 参数逐项与签名对应。
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 单层云的步进：参考实现的主循环，逐层处理平面云与积云两条路径。
// `cloudPlaneDistance` 的 `x` 是最近可见云的距离，`y` 是混合权重；由调用方按层合并。
// 平面云分支的提前声明：主入口先分派，具体步进放在文件后半段。
float4 ogxCloudPlaneMarch(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,     float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,     float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,     inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,     float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,     Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck);
// 积云分支的提前声明：与平面云共用同一组输入，额外带上可见阈值。
float4 ogxCloudCumulusMarch(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,     float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,     float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,     inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,     float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,     Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck);

// 单层云入口：按层号分派到平面云或积云路径。
float4 ogxCloudLayerMarch(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,     float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,     float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,     inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,     float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,     Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort)
{
    float distanceFactor = length(rayDirection); // 一步的世界长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = lerp(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex >= 3) return ogxCloudPlaneMarch(s, layerIndex, samples, rayPosition, rayDirection, dither, minHeight, maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance, sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort, distanceFactor, densityThresholdCheck); // 平面云只取一个样本。
    return ogxCloudCumulusMarch(s, layerIndex, samples, rayPosition, rayDirection, dither, minHeight, maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance, sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort, distanceFactor, densityThresholdCheck); // 积云沿视线步进。
}

// 平面云路径：高层云与卷云只在视线穿过平面时取一个样本，不进入体积步进。
float4 ogxCloudPlaneMarch(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,     float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,     float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,     inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,     float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,     Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck)
{
    float3 color = float3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
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
}

// 地形阴影：把当前云样本投到阴影图，返回三通道受光系数。
// 为什么单独成函数：积云与平面云都需要同一套投影、边缘压缩和范围判断，复制会漂移。
float3 ogxCloudTerrainShadow(float3 relativePos, bool enabled, Sampler2D shadowTexture,
    float4x4 shadowView, float4x4 shadowProjection, float shadowDistort)
{
    float3 shadow = float3(1.0); // 默认全亮。
    if (!enabled) return shadow; // 关闭时不采样。
    float3 fragPosition = ogxMatrixMulPoint(shadowView, relativePos) + ogxMatrixTranslation(shadowView); // 阴影相机空间。
    fragPosition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragPosition
        + ogxMatrixTranslation(shadowProjection); // 阴影投影。
    float distortFactor = shadowDistort > 0.0 ? 1.0 / (log(length(fragPosition.xy) * 0.61 + 1.0) * 1.8) : 1.0; // 参考实现的边缘压缩。
    float3 shadowPos = float3(fragPosition.xy * distortFactor, fragPosition.z); // 压缩后的阴影坐标。
    if (abs(shadowPos.x) >= 1.0 - 0.5 / 2048.0 || abs(shadowPos.y) >= 1.0 - 0.5 / 2048.0) return shadow; // 不在阴影图内。
    shadowPos = shadowPos * float3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 转零到一。
    return float3(shadowTexture.SampleLevel(shadowPos.xy, 0.0).x); // 读阴影。
}

// 闪电照明：普通闪电按水平距离照亮云，积雨云闪电再按距离、密度、高度与时间淡出。
// 单独成函数是为了让主步进只保留光照合成顺序，闪电的两套参数不挤在循环里。
void ogxCloudLightningLighting(inout float3 lighting, OgxLayersCloudSettings s, int layerIndex,
    float3 newPos, float density, float shapeWithDensity, float minHeight, float maxHeight,
    float3 rayPosition, float3 lightningPos, float horizontalDist)
{
    if (horizontalDist < 7500.0 && s.lightningBoltPosition.w > 0.0) // 普通闪电照亮云。
    {
        float lightningIntensity = exp(-horizontalDist * 0.006) * density * s.lightningFlash; // 闪电强度。
        lighting = lerp(lighting, float3(1.3, 1.5, 3.0), lightningIntensity); // 混向冷白。
    }
    if (s.lightningEnabled <= 0 || (layerIndex != 2 && s.thunderStrength <= 0.0)) return; // 没有积雨云闪电。
    float lightningDist = length(newPos - lightningPos); // 到闪电位距离。
    if (lightningDist >= 6000.0 || length(lightningPos) <= 0.0) return; // 不在照明范围内。
    float lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity) * s.lightningFlash; // 距离与密度权重。
    lightningIntensity *= 1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y); // 高度淡出。
    lightningIntensity *= smoothstep(17000.0, 14000.0, horizontalDist); // 水平淡出。
    lightningIntensity *= s.lightningFade; // 时间淡出。
    float3 lightningStrength = s.cumulonimbusLightningColor * s.cumulonimbusLightningBrightness * 0.125; // 闪电颜色。
    lighting = lerp(lighting, lightningStrength, lightningIntensity); // 混向闪电。
}

// 积云路径：小积云、大积云与积雨云沿视线逐样本累积散射与透过率。
float4 ogxCloudCumulusMarch(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition, float3 rayDirection,     float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,     float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,     inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,     float4 phaseLevels2, float3 cameraPos, bool terrainShadowOnClouds, bool deferred, Sampler2D noiseTexture,     Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck)
{
    float3 color = float3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
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
                    float3 shadow = ogxCloudTerrainShadow(newPos, terrainShadowOnClouds, shadowTexture, shadowView, shadowProjection, shadowDistort); // 地形阴影。
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
                    ogxCloudLightningLighting(lighting, s, layerIndex, newPos, density, shapeWithDensity,
                        minHeight, maxHeight, rayPosition, lightningPos, horizontalDist); // 普通与积雨云闪电。
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
}
