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
    float depth = ogxTaaCurrentDepthClosest3x3(depthTexture, ivec2(0));
设计原因与取舍：
    参考实现用全局深度图与矩阵。库把纹理、像素坐标、材质编号与全部矩阵显式传入，
    这样三乘三取样与远近景切换可以单独测试，也不会把坐标约定藏在引擎里。
    采样顺序与参考实现一致：先按材质决定深度来源，再决定近景或远景重投影。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。时间取样目前只被库内抗锯齿模块间接引用，没有顶层画面入口。
*/
#ifndef OGX_ANTIALIAS_TAA_INCLUDED
#define OGX_ANTIALIAS_TAA_INCLUDED

// 相机变换模块提供深度约定与投影，数学模块提供矩阵列展开。
#include "/omni-gfx/common/camera.glsl"
// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 当前帧三乘三最近深度：九个样本取最小值，用来避开前景薄片。
float ogxTaaCurrentDepthClosest3x3(sampler2D depthTexture, ivec2 coord)
{
    float depth0 = ogxSampleDepthFetch(depthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxSampleDepthFetch(depthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxSampleDepthFetch(depthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxSampleDepthFetch(depthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxSampleDepthFetch(depthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxSampleDepthFetch(depthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxSampleDepthFetch(depthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxSampleDepthFetch(depthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxSampleDepthFetch(depthTexture, coord + ivec2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 读一个远景深度纹素。
float ogxTaaDistantDepthFetch(sampler2D dhDepthTexture, ivec2 coord)
{
    return texelFetch(dhDepthTexture, coord, 0).x; // 远景深度图精确读取。
}

// 远景三乘三最近深度：与近景同样取九个样本的最小值。
float ogxTaaDistantDepthClosest3x3(sampler2D dhDepthTexture, ivec2 coord)
{
    float depth0 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxTaaDistantDepthFetch(dhDepthTexture, coord + ivec2(1, 1)); // 右下。
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
        depth = ogxSampleDepthFetch(depthTexture0, texelCoord); // 中心深度。
    }
    vec3 velocity = vec3(0.0); // 默认没有位移。
    if (materialIDs != endPortalId) // 末地传送门不做重投影。
    {
        vec3 screenPos = vec3(texCoord, depth); // 当前屏幕坐标。
        vec3 projection = vec3(0.0); // 上一帧屏幕坐标。
        if (screenPos.z == 1.0) // 天空像素改用远景深度。
        {
            if (closestDepth) screenPos.z = ogxTaaDistantDepthClosest3x3(dhDepthTexture0, texelCoord); // 远景最近深度。
            else screenPos.z = ogxTaaDistantDepthFetch(dhDepthTexture0, texelCoord); // 远景中心深度。
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(dhProjectionInverse, projection); // 远景逆投影到视空间。
            projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
            if (screenPos.z < 1.0) projection += cameraWorldPos - previousCameraPosition; // 有远景几何时加相机位移。
            projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
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
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            projection = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
        }
        velocity = screenPos - projection; // 当前减上一帧得到屏幕位移。
    }
    return velocity; // 交回速度。
}

/*
实现说明：时间抗锯齿的数据流。
一、深度取样：当前帧与上一帧各取三乘三邻域，先用最近深度挡住背景像素，避免前景边缘把背景颜色拖进来。
二、方差裁剪：邻域颜色求均值与方差，把历史颜色夹在均值加减若干倍方差内；这一步去掉鬼影，但保留真实的高光变化。
三、重投影：用相机速度与深度把当前像素映射到上一帧坐标，坐标越界或深度跳变时退回当前帧颜色。
四、双三次采样：历史颜色用四次双线性样本合成，减少旋转相机时的模糊。
五、输出：本帧颜色按历史权重混合，权重随运动量增大而降低，快速移动时更相信当前帧。
这些步骤都是纯函数，深度图、历史图、矩阵与像素坐标由调用方显式传入。
*/
/*
函数索引：
一、`ogxTaaCurrentDepthClosest3x3`：当前帧三乘三最近深度。
二、`ogxTaaDistantDepthFetch`：远景深度单点取样。
三、`ogxTaaDistantDepthClosest3x3`：远景三乘三最近深度。
四、`ogxTaaCameraVelocity`：用两帧深度与相机矩阵算像素速度。
五、边界：深度图、矩阵与像素坐标由调用方传入。
六、顺序：先取最近深度再算速度，避免背景像素拖前景。
*/
#endif
