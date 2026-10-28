// Eclipse 低成本云步进：只累计透过率，不做光照，供云影与远景使用。
// 参考签名给层号、步数、位置与方向、抖动与上下界；噪声、天气与覆盖率显式追加。
float ogxEclipseCloudAbsorbanceSimple(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
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
        float shape = ogxEclipseCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
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
        float densityLarge = ogxEclipseGetRainDensity(largeCumulusRain, rainAmount, thunderStrength);
        float density = 0.0;
        if (layerIndex == 0) density = ogxEclipseGetRainDensity(smallCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
        if (layerIndex == 1) density = ogxEclipseGetRainDensity(largeCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
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
                    shape = ogxEclipseCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
                        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                        rainAmount, thunderStrength, cloudMovement);
                }
                else
                {
                    float2 cumulonimbusCloud = ogxEclipseCumulonimbusShapeLayer(1, rayPosition, minHeight, maxHeight,
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

// Eclipse 云影总入口的简单版：三层云各走一次低成本步进，乘成总透过率。
// 参考签名是抖动、光照方向、偏移与起点；云噪声、天气、覆盖率与相机位置显式追加。
float4 ogxEclipseCloudTransmittanceSimple(float2 dither, float3 lightDir, float2 offset, float3 startPos,
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
    rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 找到进入云层的起点。
    rayPosition.xz += offset; // 阴影偏移。
    altoStratusClouds = ogxEclipseCloudAbsorbanceSimple(3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
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
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        largeCumulusClouds = ogxEclipseCloudAbsorbanceSimple(1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
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
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        smallCumulusClouds = ogxEclipseCloudAbsorbanceSimple(0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 小积云。
        totalAbsorbance *= smallCumulusClouds;
    }
    return float4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四层透过率。
}

// 严格参考签名的单层云步进入口：参考参数在前，云设置、相机与阴影资源追加在后。
// 主体仍由 `ogxEclipseRaymarchCloud` 执行，入口只负责把显式参数重新排好。
// 五层云的高度、厚度与距离按参考默认配置传入，避免把宿主菜单常数藏进结构体。
float4 ogxEclipseRaymarchCloudExact(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
    float dither, float minHeight, float maxHeight, float3 sunVector, float3 moonVector, float3 sunScattering,
    float3 moonScattering, float3 skyScattering, float referenceDistance, float3 sampledSkyCol,
    inout float2 cloudPlaneDistance, float backScatterPhase, float4 phaseLevels, float backScatterPhase2,
    float4 phaseLevels2, OgxEclipseCloudSettings settings, float3 cameraPos, bool terrainShadowOnClouds,
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
    return ogxEclipseRaymarchCloud(settings, layerIndex, samples, rayPosition, rayDirection, dither, minHeight,
        maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance,
        sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2,
        cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调同一份层步进。
}

// 严格参考签名的体积云总入口：参考参数在前，云层尺寸、极光与天空盒资源追加在后。
// 云层尺寸和极光参数在这里写成常数，参考的首页天空盒查表也在这里完成，采样顺序与参考一致。
float4 ogxEclipseGetVolumetricCloudsExact(float3 viewPos, float2 dither, float3 sunVector, float3 moonVector,
    float3 directLightCol, float3 directLightCol2, float3 indirectLightCol, inout float cloudPlaneDistance,
    inout float2 cloudDistance, OgxEclipseCloudSettings settings, float3 cameraPos, float farPlane,
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
    return ogxEclipseGetVolumetricClouds(settings, viewPos, dither, sunVector, moonVector, directLightCol,
        directLightCol2, indirectLightCol, cloudPlaneDistance, cloudDistance, cameraPos, skyTexture, texelSize,
        farPlane, dhFarPlane, modelViewInverse, samples, deferred, skyGround, skyBrightness,
        terrainShadowOnClouds, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调五层总入口。
}
