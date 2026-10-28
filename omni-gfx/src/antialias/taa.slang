/*
Omni 通用图形库时间抗锯齿取样模块：三乘三最近深度、远景深度与相机速度。
调用位置：需要时间抗锯齿输入的程序，算法与常数来自 iterationT 的 TAA；Minecraft 光影由 `/omni-gfx/antialias/taa.glsl` 引入。
可复制示例：
    float depth = ogxTaaCurrentDepthClosest3x3(depthTexture, texel);
    float depth = ogxTaaCurrentDepthClosest3x3(depthTexture, ivec2(0));
设计原因与取舍：
    参考实现用全局深度图与矩阵。库把纹理、像素坐标、材质编号与全部矩阵显式传入，
    这样三乘三取样与远近景切换可以单独测试，也不会把坐标约定藏在引擎里。
    采样顺序与参考实现一致：先按材质决定深度来源，再决定近景或远景重投影。
当前状态：由 `shaders/effects/clarity/taa.glsl` 引入并编译；宿主 `TaaCameraVelocity` 的远景分支调用 `ogxTaaCameraVelocity`。
*/

// --- 算法说明与边界 ---
// 三乘三最近深度只在片元阶段使用，顶点与阴影程序不编译这一段。
// 远景深度换到近景尺度时保留原始深度用于比较，不把两张深度图的尺度混用。
// 相机速度只补偿平移，旋转由重投影矩阵处理，两者分开避免重复补偿。
// TAA 的深度辅助：当前帧取三乘三邻域里离相机最近的深度，避免前景边缘被背景深度误判。
// 有远景时先读取远景深度图，把远景深度换到近景尺度，再参与最近深度比较。
// 相机速度用两帧的相机位置差除以帧时，重投影时用它补偿相机自身移动。
// 这些函数只返回深度、速度这类纯数据，混合策略留在主时间抗锯齿文件。

#ifndef OGX_ANTIALIAS_TAA_INCLUDED
#define OGX_ANTIALIAS_TAA_INCLUDED

// 相机变换模块提供深度约定与投影，数学模块提供矩阵列展开。
#include "../common/camera.slang"
// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"

// 当前帧三乘三最近深度：九个样本取最小值，用来避开前景薄片。
float ogxTaaCurrentDepthClosest3x3(Sampler2D depthTexture, int2 coord)
{
    float depth0 = ogxSampleDepthFetch(depthTexture, coord + int2(-1, -1)); // 左上。
    float depth1 = ogxSampleDepthFetch(depthTexture, coord + int2(0, -1)); // 上方。
    float depth2 = ogxSampleDepthFetch(depthTexture, coord + int2(1, -1)); // 右上。
    float depth3 = ogxSampleDepthFetch(depthTexture, coord + int2(-1, 0)); // 左侧。
    float depth4 = ogxSampleDepthFetch(depthTexture, coord + int2(0, 0)); // 中心。
    float depth5 = ogxSampleDepthFetch(depthTexture, coord + int2(1, 0)); // 右侧。
    float depth6 = ogxSampleDepthFetch(depthTexture, coord + int2(-1, 1)); // 左下。
    float depth7 = ogxSampleDepthFetch(depthTexture, coord + int2(0, 1)); // 下方。
    float depth8 = ogxSampleDepthFetch(depthTexture, coord + int2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 读一个远景深度纹素。
float ogxTaaDistantDepthFetch(Sampler2D dhDepthTexture, int2 coord)
{
    return dhDepthTexture.Load(int3(coord, 0)).x; // 远景深度图精确读取。
}

// 远景三乘三最近深度：与近景同样取九个样本的最小值。
float ogxTaaDistantDepthClosest3x3(Sampler2D dhDepthTexture, int2 coord)
{
    float depth0 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(-1, -1)); // 左上。
    float depth1 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(0, -1)); // 上方。
    float depth2 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(1, -1)); // 右上。
    float depth3 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(-1, 0)); // 左侧。
    float depth4 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(0, 0)); // 中心。
    float depth5 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(1, 0)); // 右侧。
    float depth6 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(-1, 1)); // 左下。
    float depth7 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(0, 1)); // 下方。
    float depth8 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + int2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 相机速度为什么单独一个入口：深度选择、远景换算与手部补偿是同一件事的三个分支，
// 合在重投影里会让历史裁剪函数也背上矩阵参数。这里只算位移，裁剪与混合由调用方决定。
// 输出深度用 `out` 带回，是因为最近深度与速度必须来自同一个像素，分开再采样会错位。
// 相机速度：按材质与深度选择近景或远景重投影，返回当前像素相对上一帧的屏幕位移。
// `stainedGlassId`、`iceId`、`endPortalId` 是宿主材质编号，算法只做比较，不假设编号大小。
float3 ogxTaaCameraVelocity(Sampler2D depthTexture0, Sampler2D depthTexture1, Sampler2D dhDepthTexture0,
    int2 texelCoord, float2 texCoord, float materialIDs, bool closestDepth, float stainedGlassId, float iceId,
    float endPortalId, float4x4 projectionInverse, float4x4 dhProjectionInverse, float4x4 modelView,
    float4x4 modelViewInverse, float4x4 previousModelView, float4x4 previousProjection, float3 cameraWorldPos,
    float3 previousCameraPosition, float handDepth, out float depth)
{
    // 玻璃和冰的最近深度会穿到透明层后面，所以改用完整深度图；其他材质才按质量选项取最近深度。
    if (materialIDs == stainedGlassId || materialIDs == iceId) // 透明材质用完整深度，避免最近深度穿到后面。
    {
        depth = depthTexture1.Load(int3(texelCoord, 0)).x; // 精确读取完整深度。
    }
    else if (closestDepth) // 开启最近深度时取三乘三最小值。
    {
        depth = ogxTaaCurrentDepthClosest3x3(depthTexture0, texelCoord); // 近景最近深度。
    }
    else // 默认只取中心。
    {
        depth = ogxSampleDepthFetch(depthTexture0, texelCoord); // 中心深度。
    }
    // 默认零位移：末地传送门不参与重投影，材质不符时直接返回零，调用方不必再判断。
    float3 velocity = float3(0.0); // 默认没有位移。
    if (materialIDs != endPortalId) // 末地传送门不做重投影。
    {
        float3 screenPos = float3(texCoord, depth); // 当前屏幕坐标。
        float3 projection = float3(0.0); // 上一帧屏幕坐标。
        // 深度为一说明近景没有几何，重投影必须改用远景深度，否则天空会被当成无限远而拖影。
        if (screenPos.z == 1.0) // 天空像素改用远景深度。
        {
            if (closestDepth) screenPos.z = ogxTaaDistantDepthClosest3x3(dhDepthTexture0, texelCoord); // 远景最近深度。
            else screenPos.z = ogxTaaDistantDepthFetch(dhDepthTexture0, texelCoord); // 远景中心深度。
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(dhProjectionInverse, projection); // 远景逆投影到视空间。
            projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
            // 只有远景真的打到几何时才补相机位移；纯天空没有世界坐标，补了会让云层随相机滑动。
            if (screenPos.z < 1.0) projection += cameraWorldPos - previousCameraPosition; // 有远景几何时加相机位移。
            projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            float3 previousScreen = float3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
            screenPos.z = ogxScreenDepthFromDistantScreenDepth(screenPos.z, dhProjectionInverse, projectionInverse); // 远景深度换成近景尺度。
            previousScreen.z = ogxScreenDepthFromDistantScreenDepth(previousScreen.z, dhProjectionInverse, projectionInverse); // 上一帧深度同样换算。
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
        // 屏幕位移是当前坐标减上一帧坐标，正号表示这一帧向右下移动，历史采样要反着取。
        velocity = screenPos - projection; // 当前减上一帧得到屏幕位移。
    }
    return velocity; // 交回速度。
}

#endif
