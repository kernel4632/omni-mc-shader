/*
生成文件：时间取样模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库时间抗锯齿取样模块：三乘三最近深度、远景深度与相机速度。
调用位置：需要时间抗锯齿输入的程序，算法与常数来自 iterationT 的 TAA；Minecraft 光影由 `/omni-gfx/antialias/taa.glsl` 引入。
可复制示例：
    float depth = ogxTaaCurrentDepthClosest3x3(depthTexture, texel);
    vec3 velocity = ogxTaaCameraVelocity(depth0, depth1, texel, coord, ids, ...);
设计原因与取舍：
    参考实现用全局深度图与矩阵。库把纹理、像素坐标、材质编号与全部矩阵显式传入，
    这样三乘三取样与远近景切换可以单独测试，也不会把坐标约定藏在引擎里。
    采样顺序与参考实现一致：先按材质决定深度来源，再决定近景或远景重投影。
*/
#ifndef OGX_ANTIALIAS_TAA_INCLUDED
#define OGX_ANTIALIAS_TAA_INCLUDED

// 相机变换模块提供深度约定与投影，数学模块提供矩阵列展开。
#include "/omni-gfx/camera.glsl"
#include "/omni-gfx/math.glsl"
// 读一个当前帧深度纹素。
float ogxTaaCurrentDepthFetch(sampler2D depthTexture, ivec2 coord)
{
    return texelFetch(depthTexture, coord, 0).x; // 精确读取，不插值。
}

// 当前帧三乘三最近深度：九个样本取最小值，用来避开前景薄片。
float ogxTaaCurrentDepthClosest3x3(sampler2D depthTexture, ivec2 coord)
{
    float depth0 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxTaaCurrentDepthFetch(depthTexture, coord + ivec2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 读一个远景深度纹素。
float ogxTaaDhDepthFetch(sampler2D dhDepthTexture, ivec2 coord)
{
    return texelFetch(dhDepthTexture, coord, 0).x; // 远景深度图精确读取。
}

// 远景三乘三最近深度：与近景同样取九个样本的最小值。
float ogxTaaDhDepthClosest3x3(sampler2D dhDepthTexture, ivec2 coord)
{
    float depth0 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxTaaDhDepthFetch(dhDepthTexture, coord + ivec2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 相机速度：按材质与深度选择近景或远景重投影，返回当前像素相对上一帧的屏幕位移。
// `stainedGlassId`、`iceId`、`endPortalId` 是宿主材质编号，算法只做比较，不假设编号大小。
vec3 ogxTaaCameraVelocity(sampler2D depthTexture0, sampler2D depthTexture1, sampler2D dhDepthTexture0,
    ivec2 texelCoord, vec2 texCoord, float materialIDs, bool closestDepth, float stainedGlassId, float iceId,
    float endPortalId, mat4 projectionInverse, mat4 dhProjectionInverse, mat4 modelView,
    mat4 modelViewInverse, mat4 previousModelView, mat4 previousProjection, vec3 cameraWorldPos,
    vec3 previousCameraPosition, float handDepth, out float depth)
{
    if (materialIDs == stainedGlassId || materialIDs == iceId) // 透明材质用完整深度，避免最近深度穿到后面。
    {
        depth = texelFetch(depthTexture1, texelCoord, 0).x; // 精确读取完整深度。
    }
    else if (closestDepth) // 开启最近深度时取三乘三最小值。
    {
        depth = ogxTaaCurrentDepthClosest3x3(depthTexture0, texelCoord); // 近景最近深度。
    }
    else // 默认只取中心。
    {
        depth = ogxTaaCurrentDepthFetch(depthTexture0, texelCoord); // 中心深度。
    }
    vec3 velocity = vec3(0.0); // 默认没有位移。
    if (materialIDs != endPortalId) // 末地传送门不做重投影。
    {
        vec3 screenPos = vec3(texCoord, depth); // 当前屏幕坐标。
        vec3 projection = vec3(0.0); // 上一帧屏幕坐标。
        if (screenPos.z == 1.0) // 天空像素改用远景深度。
        {
            if (closestDepth) screenPos.z = ogxTaaDhDepthClosest3x3(dhDepthTexture0, texelCoord); // 远景最近深度。
            else screenPos.z = ogxTaaDhDepthFetch(dhDepthTexture0, texelCoord); // 远景中心深度。
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(dhProjectionInverse, projection); // 远景逆投影到视空间。
            projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
            if (screenPos.z < 1.0) projection += cameraWorldPos - previousCameraPosition; // 有远景几何时加相机位移。
            projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
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
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            projection = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
        }
        velocity = screenPos - projection; // 当前减上一帧得到屏幕位移。
    }
    return velocity; // 交回速度。
}

#endif
