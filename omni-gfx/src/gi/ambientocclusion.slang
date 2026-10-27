/*
Omni 通用图形库全局光环境光遮蔽模块：Eclipse GTAO 的弧段积分、最大水平角与多切片遮蔽。
调用位置：屏幕空间环境光遮蔽与间接光；由 `/omni-gfx/gi/ambientocclusion.glsl` 引入。
可复制示例：
    float ao = ogxEclipseAmbientOcclusion(screenPos, viewPos, normal, dither, 4, 1.0, 8, 0.2, pixelSize, viewSize, 1.0, 0.0, 1.5708, depthTex, proj, invProj); // 计算环境光遮蔽。
设计原因与取舍：
    沿切片搜索最近遮挡，切片数与步数由调用方给出；深度图、矩阵与手部深度显式传入，公式与参考实现逐项相同。
*/
#ifndef OGX_GI_AMBIENTOCCLUSION_INCLUDED
#define OGX_GI_AMBIENTOCCLUSION_INCLUDED

#include "../camera.slang"
#include "../math.slang"

// GTAO 的弧段积分：两个水平角之间覆盖的余弦积分。
// 在单位圆上积分一段弧的贡献，供天空环境光近似。
float ogxEclipseIntegrateArc(float2 h, float n, float cosN)
{
    float2 tmp = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n); // 参考实现的积分核。
    return 0.25 * (tmp.x + tmp.y); // 两个方向取平均。
}

// 单个切片的最大水平角：沿切片方向在深度图里找最高遮挡。
float ogxEclipseMaxHorizonAngle(float3 viewSliceDir, float3 viewerDir, float3 screenPos, float3 viewPos, float dither,
    float radius, int steps, float3 viewPixelSize, float2 viewRes, float renderScale, float handDepth,
    float falloffStart, Sampler2D depthTexture, float4x4 projection, float4x4 projectionInverse)
{
    float stepSize = radius / float(steps); // 每步的视空间长度。
    float maxCosTheta = -1.0; // 最大遮挡角余弦。
    float3 endScreen = ogxViewToScreenSpace(viewPos + viewSliceDir * stepSize, projection); // 一步后的屏幕坐标。
    float2 rayStep = endScreen.xy - screenPos.xy; // 屏幕步长。
    float pixelScale = max(viewPixelSize.x, max(viewPixelSize.y, viewPixelSize.z)); // 最大像素尺度。
    float2 rayPos = screenPos.xy + rayStep * (dither + pixelScale / length(rayStep)); // 起点加抖动与一个像素偏移。
    for (int i = 0; i < steps; ++i) // 逐步采样。
    {
        int2 pixel = int2(clamp(rayPos, 0.0, 1.0) * viewRes * renderScale - 0.5); // 屏幕比例换像素。
        float depth = depthTexture.Load(int3(pixel, 0)).x; // 读深度。
        if (depth == 1.0 || depth < handDepth || depth == screenPos.z) // 天空、手与自身都跳过。
        {
            rayPos += rayStep;
            continue;
        }
        float3 offset = ogxScreenToViewSpace(float3(rayPos, depth), projectionInverse) - viewPos; // 采样点相对当前点的视空间偏移。
        float lenSq = dot(offset, offset); // 距离平方。
        float norm = rsqrt(lenSq); // 距离倒数。
        float distanceFalloff = ogxSaturate((lenSq * norm - falloffStart * radius) / (radius - falloffStart * radius)); // 距离淡出。
        float cosTheta = dot(viewerDir, offset) * norm; // 夹角余弦。
        cosTheta = lerp(cosTheta, -1.0, distanceFalloff); // 远处压到水平线以下。
        maxCosTheta = max(cosTheta, maxCosTheta); // 取最大。
        rayPos += rayStep;
    }
    return ogxFastAcosEclipse(clamp(maxCosTheta, -1.0, 1.0)); // 反余弦得到角度。
}

// GTAO 环境光遮蔽：沿多个切片各取两个最大水平角，再积分成遮蔽。
// Eclipse 地平线遮蔽：沿多个方向搜索最近遮挡，返回零到一的可见度。
float ogxEclipseAmbientOcclusion(float3 screenPos, float3 viewPos, float3 viewNormal, float2 dither, int slices,
    float radius, int horizonSteps, float falloffStart, float3 viewPixelSize, float2 viewRes, float renderScale,
    float handDepth, float halfPi, Sampler2D depthTexture, float4x4 projection, float4x4 projectionInverse)
{
    float ao = 0.0; // 累加遮蔽。
    float3 viewerDir = normalize(-viewPos); // 视线方向。
    float3 viewerRight = normalize(cross(float3(0.0, 1.0, 0.0), viewerDir)); // 右方向。
    float3 viewerUp = cross(viewerDir, viewerRight); // 上方向。
    float3x3 localToView = float3x3(viewerRight, viewerUp, viewerDir); // 局部到视空间。
    for (int i = 0; i < slices; ++i) // 逐切片。
    {
        float sliceAngle = (float(i) + dither.x) * (OGX_PI / float(slices)); // 切片角。
        float3 sliceDir = float3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        float3 viewSliceDir = ogxMatrix3MulPoint(localToView, sliceDir); // 转到视空间。
        float3 orthoDir = sliceDir - dot(sliceDir, viewerDir) * viewerDir; // 切片在视线垂直平面的投影。
        float3 axis = cross(sliceDir, viewerDir); // 旋转轴。
        float3 projectedNormal = viewNormal - axis * dot(viewNormal, axis); // 法线投影。
        float lenSq = dot(projectedNormal, projectedNormal); // 投影长度平方。
        float norm = rsqrt(lenSq); // 倒数。
        float signGamma = sign(dot(orthoDir, projectedNormal)); // 法线在切片哪一侧。
        float cosGamma = ogxSaturate(dot(projectedNormal, viewerDir) * norm); // 法线与视线夹角余弦。
        float gamma = signGamma * ogxFastAcosEclipse(cosGamma); // 夹角。
        float2 maxHorizonAngles; // 两个方向的最大水平角。
        maxHorizonAngles.x = ogxEclipseMaxHorizonAngle(-viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 负方向。
        maxHorizonAngles.y = ogxEclipseMaxHorizonAngle(viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 正方向。
        maxHorizonAngles = gamma + clamp(float2(-1.0, 1.0) * maxHorizonAngles - gamma, -halfPi, halfPi); // 限制在半球内。
        ao += ogxEclipseIntegrateArc(maxHorizonAngles, gamma, cosGamma) * lenSq * norm; // 积分这一段。
    }
    ao *= 1.0 / float(slices); // 取平均。
    return ao * (ao * 0.5 + 0.5); // 参考实现的对比度重整。
}

#endif
