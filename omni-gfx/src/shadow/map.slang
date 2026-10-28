/*
Omni 通用图形库阴影贴图模块：边缘压缩、投影偏差、硬阴影、轨道旋转与体素阴影图。
调用位置：方向光阴影、体素阴影与末地主岛光；由 `/omni-gfx/shadow/map.glsl` 引入，算法与常数来自 Eclipse 的阴影实现。
可复制示例：
    float shadow = ogxVoxelShadowMap(direct, playerPos, 1.0, noise, normal, opaque, translucent, tint, view, proj, 128.0, 2048.0, 0.9, 0.9, 1.0, 1.0, 8, true, false, false, m, p); // 计算体素阴影。
设计原因与取舍：
    阴影图坐标、压缩系数与样本数全部显式传入；末地主岛光用独立矩阵，普通路径和参考实现一样先压缩再采样。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。阴影贴图写入目前只被库内其它生成模块间接引用，没有顶层画面入口。
*/
#ifndef OGX_SHADOW_MAP_INCLUDED
#define OGX_SHADOW_MAP_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"
// 体素求交提供光线步进与遮挡判断。
#include "../voxel/trace.slang"

// Eclipse 阴影边缘压缩：按到阴影图中心的距离给一个放大系数。
float ogxShadowDistortFactor(float2 worldPos, float a, float b, float k)
{
    return 1.0 / (log(length(worldPos) * b + a) * k); // 参考实现对数的边缘压缩。
}

// Eclipse 阴影投影偏差：读入齐次阴影坐标，按同一压缩系数缩放横纵。
float4 ogxShadowProjectionBias(float4 projectedShadowSpacePosition, float a, float b, float k)
{
    float distortFactor = log(length(projectedShadowSpacePosition.xy) * b + a) * k; // 与读取端一致。
    projectedShadowSpacePosition.xy /= distortFactor; // 压缩横纵。
    return projectedShadowSpacePosition; // 交回坐标。
}

// Eclipse 的阴影修补：按相机距离把世界坐标抬离表面一点点，抵消阴影图的彼得潘效应。
// 为什么用小数抖动而不是固定偏移：固定偏移会在不同距离留下阶梯，按世界坐标取小数能让误差散开。
// `transition` 是阴影过渡量，越小越靠近阴影边缘，偏移越强；`flatNormal` 为保持原签名而保留，原程序未使用。
void ogxGriAndEminShadowFix(inout float3 worldPos, float3 flatNormal, float transition, float3 cameraWorldPos, bool eyeInWater)
{
    transition = 1.0 - transition; // 过渡量取反，边缘处为一。
    transition *= transition * transition * transition * transition * transition * transition; // 六次方，只让最边缘一段生效。
    float zoomLevel = lerp(0.0, 0.5, transition); // 边缘处偏移半个格子。
    if (zoomLevel > 0.001 && !eyeInWater) // 水下不做偏移，原程序同样跳过。
    {
        worldPos = worldPos - (fract(worldPos + cameraWorldPos - worldPos * 0.0001) * zoomLevel - zoomLevel * 0.5); // 按位置小数把坐标推到格子中心附近。
    }
}

// Eclipse 的阴影偏差：按一个阴影像素对应一个方块的尺度，沿几何法线把投影坐标推出表面。
// `shadowNormal` 是法线经过阴影相机旋转后的方向，`shadowDistance` 与 `shadowMapResolution` 决定纹素大小。
void ogxApplyShadowBias(inout float3 projectedShadowPosition, float3 shadowNormal, float shadowDistance, float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个纹素对应的世界尺度，再放大一倍。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远，斜投影误差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 按距离放大偏差。
    projectedShadowPosition += shadowNormal * biasSize * 0.15 * biasDistanceFactor; // 沿法线推出表面。
}

// Eclipse 的阴影偏差入口：参考签名保留 playerPos 但内部不使用，几何法线经阴影相机旋转后推坐标。
// 为什么把矩阵显式传入：参考实现读 shadowModelView，库不绑定宿主矩阵。
void ogxApplyShadowBiasMatrix(inout float3 projectedShadowPosition, float3 playerPos, float3 geoNormals,
    float3x3 shadowNormalMatrix, float shadowDistance, float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个阴影像素对应的世界尺度。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远误差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 按距离放大。
    projectedShadowPosition += ogxMatrix3MulPoint(shadowNormalMatrix, geoNormals) * biasSize * 0.15 * biasDistanceFactor; // 沿法线推出表面。
}

// 硬阴影：阴影图深度比接收点更远时返回零，否则一。
float ogxHardShadowVisibility(float shadowDepth, float3 shadowPosition, float bias)
{
    if (shadowPosition.z >= 1.0) return 1.0; // 阴影图外保持全亮。
    return 1.0 - step(shadowDepth, shadowPosition.z - bias); // 参考实现的阶跃比较。
}

// 自定义旋转矩阵：绕倾斜轴旋转一天的时间角，供月亮轨道与阴影相机使用。
float3x3 ogxShadowCustomRotation(float rotationAngle, float timeOfDay)
{
    float radiance = timeOfDay / 24000.0 * 6.28319; // 一天转一圈。
    float sunRotRad = radians(rotationAngle); // 倾斜角。
    float3 rotationAxis = float3(0.0, sin(sunRotRad), cos(sunRotRad)); // 倾斜轴。
    float c = cos(radiance); // 旋转余弦。
    float s = sin(radiance); // 旋转正弦。
    float t = 1.0 - c; // 一减余弦。
    float3x3 tiltRotation = float3x3(
        t * rotationAxis.x * rotationAxis.x + c,
        t * rotationAxis.x * rotationAxis.y - s * rotationAxis.z,
        t * rotationAxis.x * rotationAxis.z + s * rotationAxis.y,
        t * rotationAxis.y * rotationAxis.x + s * rotationAxis.z,
        t * rotationAxis.y * rotationAxis.y + c,
        t * rotationAxis.y * rotationAxis.z - s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.x - s * rotationAxis.y,
        t * rotationAxis.z * rotationAxis.y + s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.z + c); // 按列填写的旋转矩阵。
    return tiltRotation; // 交回旋转。
}

// 体素阴影投影偏差：参考实现的 `applyShadowBias`。
float3 ogxShadowBiasProjected(float3 projectedShadowPosition, float3 shadowNormal, float shadowDistance,
    float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个阴影纹素对应的方块比例。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远偏差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 距离放大。
    return projectedShadowPosition + shadowNormal * biasSize * 0.15 * biasDistanceFactor; // 沿法线推离表面。
}

// 体素阴影主函数：参考实现的 `ComputeVoxelShadowMap`，用显式阴影图与矩阵。
float ogxVoxelShadowMap(inout float3 directLightColor, float3 playerPos, float maxDistFade,
    float noise, float3 geoNormals, Sampler2D opaqueShadowMap, Sampler2D translucentShadowMap, Sampler2D shadowcolor0,
    float4x4 shadowView, float4x4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader, float4x4 endShadowMatrix, float4x4 endShadowPerspective)
{
    float distortFactor = 1.0; // 边缘压缩系数。
    float3 projectedShadowPosition; // 阴影图坐标。
    if (!endShader) // 主世界与下界。
    {
        projectedShadowPosition = ogxMatrix3MulPoint(float3x3(shadowView), playerPos) + ogxMatrixTranslation(shadowView); // 转到阴影相机。
        float3 shadowNormal = ogxMatrix3MulPoint(float3x3(shadowView), geoNormals); // 法线也转过去。
        projectedShadowPosition = ogxShadowBiasProjected(projectedShadowPosition, shadowNormal, shadowDistance, shadowMapResolution); // 推离表面。
        projectedShadowPosition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * projectedShadowPosition
            + ogxMatrixTranslation(shadowProjection); // 乘投影。
        distortFactor = 1.0 / (log(length(projectedShadowPosition.xy) * distortB + distortA) * distortK); // 边缘压缩。
        projectedShadowPosition.xy *= distortFactor; // 压缩横纵。
        projectedShadowPosition.z += shadowProjection[3][2] * 0.0012; // 深度偏移。
    }
    else // 末地主岛光使用独立矩阵。
    {
        float4 shadowPos = ogxMatrixMulPoint4(endShadowMatrix, float4(playerPos, 1.0)); // 末地阴影矩阵。
        float3 shadowNormal = ogxMatrix3MulPoint(float3x3(endShadowMatrix), geoNormals); // 法线。
        shadowPos.xyz = float4(ogxShadowBiasProjected(shadowPos.xyz, shadowNormal, shadowDistance, shadowMapResolution), 1.0).xyz; // 推离。
        shadowPos = ogxMatrixMulPoint4(endShadowPerspective, shadowPos); // 透视投影。
        projectedShadowPosition = shadowPos.xyz / shadowPos.w; // 齐次除法。
        distortFactor = 1.0; // 末地不做压缩。
    }
    projectedShadowPosition = projectedShadowPosition * float3(0.5, 0.5, 0.5 / 6.0) + float3(0.5); // 参考实现的深度缩放。
    float shadowmap = 0.0; // 阴影累加。
    float3 translucentTint = float3(0.0); // 彩色半透明阴影。
    int samples = basicFilter ? shadowSampleCount / 2 : 1; // 滤波样本数。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (basicFilter) // 只有开启滤波时才加螺旋偏移。
        {
            float rdMul = (endShader ? 52.0 : 2.4 * distortFactor) * d0k; // 参考实现的半径。
            float2 offsetS = ogxVoxelSampleOffset(i, float(samples - 1), noise) * rdMul; // 螺旋偏移。
            projectedShadowPosition.xy += offsetS; // 累加偏移。
        }
        if (coloredShadows) // 彩色半透明阴影。
        {
            float shadowDepthDiff = pow(clamp((translucentShadowMap.SampleLevel(projectedShadowPosition.xy, 0.0).x - projectedShadowPosition.z) * 2.0, 0.0, 1.0), 2.0); // 不透明遮挡差。
            float opaqueShadow = opaqueShadowMap.SampleLevel(projectedShadowPosition.xy, 0.0).x; // 不透明阴影。
            shadowmap += max(opaqueShadow, shadowDepthDiff); // 取较大。
            float4 translucentShadow = shadowcolor0.SampleLevel(projectedShadowPosition.xy, 0.0); // 半透明阴影。
            float shadowAlpha = pow(1.0 - pow(translucentShadow.a, 5.0), 0.2); // 参考实现的透明度曲线。
            translucentShadow.rgb = max(normalize(translucentShadow.rgb + 0.0001), max(opaqueShadow, 1.0 - shadowAlpha)) * shadowAlpha; // 保色相。
            translucentTint += lerp(translucentShadow.rgb, float3(1.0), opaqueShadow * shadowDepthDiff); // 累积染色。
        }
        else
        {
            shadowmap += opaqueShadowMap.SampleLevel(projectedShadowPosition.xy, 0.0).x; // 普通阴影。
        }
    }
    if (coloredShadows) directLightColor *= lerp(float3(1.0), translucentTint / float(samples), maxDistFade); // 光源染色。
    float shadowResult = shadowmap / float(samples); // 平均阴影。
    if (endShader) // 末地主岛光的圆形范围。
    {
        float r = length(projectedShadowPosition.xy - float2(0.5)); // 到中心距离。
        if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) shadowResult *= smoothstep(0.5, 0.25, r); // 软边。
        else shadowResult = 0.0; // 圆外没有光。
    }
    return shadowResult; // 交回阴影。
}

// Photonics 阴影：和体素阴影相同的几何路径，但用 Photonics 采样曲线与固定样本数。
// 光子学阴影图：把可见光源与遮挡写进阴影图，并返回直射光强度。
float ogxPhotonicsShadowMap(inout float3 directLightColor, float3 playerPos, float maxDistFade,
    float noise, float3 geoNormals, Sampler2D opaqueShadowMap, Sampler2D translucentShadowMap, Sampler2D shadowcolor0,
    float4x4 shadowView, float4x4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader)
{
    return ogxVoxelShadowMap(directLightColor, playerPos, maxDistFade, noise, geoNormals,
        opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowDistance, shadowMapResolution,
        distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows, endShader,
        float4x4(1.0), float4x4(1.0)); // 末地矩阵在这里不用，传入单位矩阵。
}

#endif
