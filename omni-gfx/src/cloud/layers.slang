/*
Omni 通用图形库层状体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud/layers.glsl` 引入。
可复制示例：`float phase = ogxLayersPhaseCloud(0.5, 0.8, 0);` 取一档云相函数。
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
当前状态：参考后端，当前没有画面选项选择它；只保留源码供严格对照，不生成 GLSL 或探针。
*/

// --- 算法说明与边界 ---
// 五层顺序固定为小积云、大积云、积雨云、高层云、卷云；前面的层更靠近相机，先合成能省掉被挡住的层。
// 层状体积云入口按小积云、大积云、积雨云、高层云、卷云的顺序逐层步进，每层独立高度与厚度。
// 单层步进前先算层内步长与起点：步长由层厚、视线方向与采样数决定，起点压到云底与云顶之间。
// 每层结果按透过率从远到近合成，先被前面云挡住的像素不再采样后面的层，省掉看不见的计算。

#ifndef OGX_CLOUD_LAYERS_INCLUDED
#define OGX_CLOUD_LAYERS_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数，天空提供云的环境色查表。
#include "../common/math.slang"
// 云提供球面求交、密度与单层步进。
#include "cloud.slang"
// 天空提供云环境色、星空与日月圆盘。
#include "../atmosphere/sky.slang"

// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxLayersCloudLayer
{
    float height; // 云底高度，米。
    float tallness; // 云层厚度，米。
    float scale; // 世界坐标到云坐标的比例。
    float distance; // 这一层的可见距离，米。
    float coverage; // 云量，零到一。
    float rainDensity; // 雨天密度。
    float detail; // 高频侵蚀尺度。
};

// 体积云的全部环境输入：层数据、天气、太阳与闪电。
struct OgxLayersCloudSettings
{
    OgxLayersCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
    float cloudMovement; // 云的水平位移，米。
    float rainAmount; // 降雨强度。
    float thunderStrength; // 雷暴强度。
    float sunElevation; // 太阳高度角正弦。
    float moonElevation; // 月亮高度角正弦。
    float cumulonimbusStrength; // 积雨云强度。
    float distanceFogScale; // 距离雾的指数系数，通常为负。
    float skyBrightness; // 天空亮度。
    float lightningFlash; // 当前闪电亮度。
    float lightningFade; // 闪电衰减。
    float cumulonimbusLightningBrightness; // 积雨云闪电亮度。
    float auroraAmount; // 极光强度，零表示没有极光。
    float3 auroraLighting; // 极光颜色，调用方按自己的极光模型算好。
    float4 lightningBoltPosition; // 普通闪电位置，第四个分量是强度。
    float3 cumulonimbusLightningColor; // 积雨云闪电颜色。
    int cumulonimbus; // 是否启用积雨云，零关闭。
    int lightningEnabled; // 是否启用积雨云闪电。
};

// 五层云总入口的提前声明：严格入口在子文件里先调用它，定义放在主文件末尾。
float4 ogxLayersGetVolumetricClouds(OgxLayersCloudSettings s, float3 viewPos, float2 dither, float3 sunVector,
    float3 moonVector, float3 directLightCol, float3 directLightCol2, float3 indirectLightCol,
    inout float cloudPlaneDistance, inout float2 cloudDistance, float3 cameraPos, Sampler2D skyTexture, float2 texelSize,
    float farPlane, float dhFarPlane, float4x4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, Sampler2D noiseTexture,
    Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float shadowResolution, float shadowDistort);

// 哈希、噪声、逐层形状、积雨云与降雨加成，具体实现在子文件。
#include "layers/shape.slang"
// 行星阴影、云影、闪电落点与步进起点，具体实现在子文件。
#include "layers/shadow.slang"
// 云相函数、散射与光照，具体实现在子文件。
#include "layers/lighting.slang"
// 主体积云步进、低成本透过率与严格入口，具体实现在子文件。
#include "layers/ray.slang"
// 层状云低成本步进提供云影与远景透过率。
#include "layers/simple.slang"
// 层状云参考签名步进提供天气参数入口。
#include "layers/transmittance.slang"
// 层状云严格入口提供参考默认常数。
#include "layers/exact.slang"

// 单层步进准备：层厚、水平步长与采样数决定一步的长度，起点压到该层云底与云顶之间。
// 五层原来各写两行同样的式子，抽成这个准备函数后改步长公式只改一处，层与层之间不会漂移。
void ogxLayersLayerRay(float3 viewDir, float thickness, float3 cloudDist, int samples, float2 dither,
    float3 cameraPos, float minHeight, out float3 rayDirection, out float3 rayPosition)
{
    rayDirection = viewDir * (thickness / length(viewDir / cloudDist) / float(samples)); // 一层走完的步长。
    rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, minHeight + thickness); // 起点压到云层平面。
}

// 五层体积云总入口：按参考实现的顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合。
// 为什么保留为单一入口：五层顺序、相机高度混合与距离合成共享同一份状态，拆开会让二十多个参数
// 在子函数之间来回传递，反而更难核对参考实现的顺序；其余超过一百行的函数已按算法拆分。
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
    float3 rayDirection; // 当前层的步长方向。
    float3 rayPosition; // 当前层的步进起点。
    ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, min(cloudDist, float3(0.05 * lViewPosM)), samples, dither,
        cameraPos, minHeight, rayDirection, rayPosition); // 小积云：层内步长更小。
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
    smallCumulusClouds = ogxCloudLayerMarch(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
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
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, samples, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 大积云：按当前层厚重算。
        largeCumulusClouds = ogxCloudLayerMarch(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
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
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, cumulonimbusSamples, dither, cameraPos,
            minHeight, rayDirection, rayPosition); // 积雨云：样本翻倍，步长相应缩短。
        cumulonimbusClouds = ogxCloudLayerMarch(s, 2, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight,
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
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, 1, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 高层云：单步走到层顶。
        altoStratusClouds = ogxCloudLayerMarch(s, 3, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
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
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, 1, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 卷云：单步走到层顶。
        cirrusClouds = ogxCloudLayerMarch(s, 4, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
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

#endif
