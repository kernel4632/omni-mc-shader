/* 层状体积云的严格入口：按参考签名重排参数并填写参考默认常数；由 `cloud/layers.slang` 内联引入。
可复制示例：`float4 cloud = ogxLayersGetVolumetricCloudsExact(viewPos, dither, ...);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 严格参考签名的单层云步进入口：参考参数在前，云设置、相机与阴影资源追加在后。
// 主体仍由 `ogxCloudLayerMarch` 执行，入口只负责把显式参数重新排好。
// 五层云的高度、厚度与距离按参考默认配置传入，避免把宿主菜单常数藏进结构体。
float4 ogxCloudLayerMarchExact(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
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
    return ogxCloudLayerMarch(settings, layerIndex, samples, rayPosition, rayDirection, dither, minHeight,
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
