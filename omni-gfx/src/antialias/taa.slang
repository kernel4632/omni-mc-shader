/*
Omni 通用图形库 iterationT 时间抗锯齿取样模块：三乘三最近深度、远景深度与相机速度。
调用位置：需要复现 iterationT TAA 输入的程序；Minecraft 光影由 `/omni-gfx/antialias/taa.glsl` 引入。
可复制示例：
    float depth = ogxItxSampleCurrDepthClosest3x3(depthTexture, texel);
    float3 velocity = ogxItxCalculateCameraVelocity(depth0, depth1, texel, coord, ids, ...);
设计原因与取舍：
    参考实现用全局深度图与矩阵。库把纹理、像素坐标、材质编号与全部矩阵显式传入，
    这样三乘三取样与远近景切换可以单独测试，也不会把坐标约定藏在引擎里。
    采样顺序与参考实现一致：先按材质决定深度来源，再决定近景或远景重投影。
*/
#ifndef OGX_ITX_TAA_INCLUDED
#define OGX_ITX_TAA_INCLUDED

// 相机变换模块提供深度约定与投影，数学模块提供矩阵列展开。
#include "../camera.slang"
#include "../math.slang"

// 读一个当前帧深度纹素。
float ogxItxSampleDepthFetch(Sampler2D depthTexture, int2 coord)
{
    return depthTexture.Load(int3(coord, 0)).x; // 精确读取，不插值。
}

// 当前帧三乘三最近深度：九个样本取最小值，用来避开前景薄片。
float ogxItxSampleCurrDepthClosest3x3(Sampler2D depthTexture, int2 coord)
{
    float depth0 = ogxItxSampleDepthFetch(depthTexture, coord + int2(-1, -1)); // 左上。
    float depth1 = ogxItxSampleDepthFetch(depthTexture, coord + int2(0, -1)); // 上方。
    float depth2 = ogxItxSampleDepthFetch(depthTexture, coord + int2(1, -1)); // 右上。
    float depth3 = ogxItxSampleDepthFetch(depthTexture, coord + int2(-1, 0)); // 左侧。
    float depth4 = ogxItxSampleDepthFetch(depthTexture, coord + int2(0, 0)); // 中心。
    float depth5 = ogxItxSampleDepthFetch(depthTexture, coord + int2(1, 0)); // 右侧。
    float depth6 = ogxItxSampleDepthFetch(depthTexture, coord + int2(-1, 1)); // 左下。
    float depth7 = ogxItxSampleDepthFetch(depthTexture, coord + int2(0, 1)); // 下方。
    float depth8 = ogxItxSampleDepthFetch(depthTexture, coord + int2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 读一个远景深度纹素。
float ogxItxSampleDhDepthFetch(Sampler2D dhDepthTexture, int2 coord)
{
    return dhDepthTexture.Load(int3(coord, 0)).x; // 远景深度图精确读取。
}

// 远景三乘三最近深度：与近景同样取九个样本的最小值。
float ogxItxSampleCurrDepthDhClosest3x3(Sampler2D dhDepthTexture, int2 coord)
{
    float depth0 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(-1, -1)); // 左上。
    float depth1 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(0, -1)); // 上方。
    float depth2 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(1, -1)); // 右上。
    float depth3 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(-1, 0)); // 左侧。
    float depth4 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(0, 0)); // 中心。
    float depth5 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(1, 0)); // 右侧。
    float depth6 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(-1, 1)); // 左下。
    float depth7 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(0, 1)); // 下方。
    float depth8 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + int2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 相机速度：按材质与深度选择近景或远景重投影，返回当前像素相对上一帧的屏幕位移。
// `stainedGlassId`、`iceId`、`endPortalId` 是宿主材质编号，算法只做比较，不假设编号大小。
float3 ogxItxCalculateCameraVelocity(Sampler2D depthTexture0, Sampler2D depthTexture1, Sampler2D dhDepthTexture0,
    int2 texelCoord, float2 texCoord, float materialIDs, bool closestDepth, float stainedGlassId, float iceId,
    float endPortalId, float4x4 projectionInverse, float4x4 dhProjectionInverse, float4x4 modelView,
    float4x4 modelViewInverse, float4x4 previousModelView, float4x4 previousProjection, float3 cameraWorldPos,
    float3 previousCameraPosition, float handDepth, out float depth)
{
    if (materialIDs == stainedGlassId || materialIDs == iceId) // 透明材质用完整深度，避免最近深度穿到后面。
    {
        depth = depthTexture1.Load(int3(texelCoord, 0)).x; // 精确读取完整深度。
    }
    else if (closestDepth) // 开启最近深度时取三乘三最小值。
    {
        depth = ogxItxSampleCurrDepthClosest3x3(depthTexture0, texelCoord); // 近景最近深度。
    }
    else // 默认只取中心。
    {
        depth = ogxItxSampleDepthFetch(depthTexture0, texelCoord); // 中心深度。
    }
    float3 velocity = float3(0.0); // 默认没有位移。
    if (materialIDs != endPortalId) // 末地传送门不做重投影。
    {
        float3 screenPos = float3(texCoord, depth); // 当前屏幕坐标。
        float3 projection = float3(0.0); // 上一帧屏幕坐标。
        if (screenPos.z == 1.0) // 天空像素改用远景深度。
        {
            if (closestDepth) screenPos.z = ogxItxSampleCurrDepthDhClosest3x3(dhDepthTexture0, texelCoord); // 远景最近深度。
            else screenPos.z = ogxItxSampleDhDepthFetch(dhDepthTexture0, texelCoord); // 远景中心深度。
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(dhProjectionInverse, projection); // 远景逆投影到视空间。
            projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
            if (screenPos.z < 1.0) projection += cameraWorldPos - previousCameraPosition; // 有远景几何时加相机位移。
            projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            float3 previousScreen = float3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
            screenPos.z = ogxScreenDepthFromDhScreenDepth(screenPos.z, dhProjectionInverse, projectionInverse); // 远景深度换成近景尺度。
            previousScreen.z = ogxScreenDepthFromDhScreenDepth(previousScreen.z, dhProjectionInverse, projectionInverse); // 上一帧深度同样换算。
            projection = previousScreen; // 交回上一帧屏幕坐标。
            depth = ogxSaturate(screenPos.z); // 输出近景尺度深度。
        }
        else // 近景像素。
        {
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(projectionInverse, projection); // 逆投影到视空间。
            if (depth < 0.7) // 手部只加模型视图的位移。
            {
                projection += (ogxMatrixTranslation(previousModelView) - ogxMatrixTranslation(modelView)) * handDepth; // 参考实现的手部补偿。
            }
            else // 世界几何完整重投影。
            {
                projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
                projection += cameraWorldPos - previousCameraPosition; // 加相机位移。
                projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            }
            float3 previousScreen = float3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            projection = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
        }
        velocity = screenPos - projection; // 当前减上一帧得到屏幕位移。
    }
    return velocity; // 交回速度。
}

#endif
