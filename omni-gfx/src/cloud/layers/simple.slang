/* 层状体积云的设置版低成本步进：只累计透过率，供云影与远景使用；由 `cloud/layers.slang` 内联引入。
可复制示例：`float4 t = ogxLayersGetVolumetricCloudsSimple(settings, dither, lightDir, offset, ...);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 云影步进：只算透过率，不算光照，供阴影程序低成本使用。
float ogxCloudLayerMarchSimple(OgxLayersCloudSettings s, int layerIndex, int samples, float3 rayPosition,
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
    float altoStratusClouds = ogxCloudLayerMarchSimple(s, 3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
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
        largeCumulusClouds = ogxCloudLayerMarchSimple(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight,
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
        smallCumulusClouds = ogxCloudLayerMarchSimple(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 小积云。
        totalAbsorbance *= smallCumulusClouds; // 更新透过率。
    }
    return float4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四个透过率。
}
