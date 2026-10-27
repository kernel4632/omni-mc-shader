/*
生成文件：相机变换模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库相机变换模块：屏幕、视空间、世界空间、阴影空间与远景投影的显式换算。
调用位置：任何需要把深度图还原成位置、把世界点投到阴影图的程序；Minecraft 光影由 `/omni-gfx/camera.glsl` 引入。
可复制示例：
    vec3 viewPos = ogxViewPosFromScreenPos(coord, depth, jitter, 0.5, projectionInverse, true);
    vec3 shadowPos = ogxShadowScreenPosDistorted(worldPos, shadowView, shadowProjection, 0.9);
    vec3 clip = ogxProjectAndDivide(projection, viewPos);
设计原因与取舍：
    参考实现直接读 gbufferProjection 等全局变量。库把每个矩阵、抖动与是否处理抖动的开关都显式传入，
    调用方必须自己给出数据来源；这样同一套公式能用于主世界、远景与测试场景，也方便审查矩阵布局。
    所有函数只做坐标换算，不读取缓冲、不改写选项，因此不是宿主胶水。
*/
#ifndef OGX_CAMERA_INCLUDED
#define OGX_CAMERA_INCLUDED

// 数学模块提供夹紧与向量单位化。
#include "/omni-gfx/math.glsl"
// 屏幕坐标与深度还原视空间位置；`jitter` 为 TAA 抖动，`useJitter` 决定是否先减去半个像素。
vec3 ogxViewPosFromScreenPos(vec2 coord, float depth, vec2 jitter, float jitterScale, mat4 projectionInverse, bool useJitter)
{
    if (useJitter) coord -= jitter * jitterScale; // 参考实现只减半个抖动像素。
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec3 pos = vec3(vec2(projectionInverse[0][0], projectionInverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projectionInverse); // 逆投影对角项与平移列。
    return pos / (projectionInverse[2][3] * ndc.z + projectionInverse[3][3]); // 透视除法。
}

// 不做抖动修正的版本：追踪射线、历史重建等已经自行处理抖动的场合使用。
vec3 ogxViewPosFromScreenPosRaw(vec2 coord, float depth, mat4 projectionInverse)
{
    return ogxViewPosFromScreenPos(coord, depth, vec2(0.0), 0.0, projectionInverse, false); // 与上一函数共用同一算式。
}

// 视空间位置投到屏幕；`useJitter` 为真时把抖动加回横纵坐标。
vec3 ogxScreenPosFromViewPos(vec3 viewPos, vec2 jitter, float jitterScale, mat4 projection, bool useJitter)
{
    vec3 screenPos = vec3(projection[0][0], projection[1][1], projection[2][2]) * viewPos + ogxMatrixTranslation(projection); // 投影对角项与平移列。
    screenPos = screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
    if (useJitter) screenPos.xy += jitter * jitterScale; // 补回抖动。
    return screenPos;
}

// 不补抖动的投影：屏幕空间追踪的起点与终点都用这个版本，抖动只影响采样相位。
vec3 ogxScreenPosFromViewPosRaw(vec3 viewPos, mat4 projection)
{
    return ogxScreenPosFromViewPos(viewPos, vec2(0.0), 0.0, projection, false); // 共用同一算式。
}

// 屏幕深度换米制距离：只用到逆投影的深度列。
float ogxLinearDepthFromScreenDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影深度部分。
}

// 米制距离换屏幕深度的函数在后期模块已有同式实现，这里不重复定义，避免同一编译单元重名。

// 远景屏幕坐标与深度还原远景视空间位置：用完整矩阵乘，远景投影不一定只有对角项。
// 为什么用完整矩阵：远景投影可能带非对角项，只取对角项会在视野边缘把位置放大或缩小。
vec3 ogxViewPosFromScreenPosDh(vec2 coord, float depth, vec2 taaJitter, bool useJitter, mat4 dhProjectionInverse)
{
    if (useJitter) coord -= taaJitter * 0.5; // 参考只减半个抖动像素，与近景同一口径。
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec4 clip = vec4(ndc, 1.0); // 齐次坐标。
    vec4 view = vec4(dhProjectionInverse[0][0] * clip.x + dhProjectionInverse[1][0] * clip.y + dhProjectionInverse[2][0] * clip.z + dhProjectionInverse[3][0] * clip.w,
                         dhProjectionInverse[0][1] * clip.x + dhProjectionInverse[1][1] * clip.y + dhProjectionInverse[2][1] * clip.z + dhProjectionInverse[3][1] * clip.w,
                         dhProjectionInverse[0][2] * clip.x + dhProjectionInverse[1][2] * clip.y + dhProjectionInverse[2][2] * clip.z + dhProjectionInverse[3][2] * clip.w,
                         dhProjectionInverse[0][3] * clip.x + dhProjectionInverse[1][3] * clip.y + dhProjectionInverse[2][3] * clip.z + dhProjectionInverse[3][3] * clip.w); // 完整矩阵乘。
    return view.xyz / view.w; // 透视除法。
}

// 不做抖动修正的远景逆投影：屏幕空间追踪已经自己处理过抖动，这里不能再减。
vec3 ogxViewPosFromScreenPosRawDh(vec2 coord, float depth, mat4 dhProjectionInverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec4 clip = vec4(ndc, 1.0); // 齐次坐标。
    vec4 view = vec4(dhProjectionInverse[0][0] * clip.x + dhProjectionInverse[1][0] * clip.y + dhProjectionInverse[2][0] * clip.z + dhProjectionInverse[3][0] * clip.w,
                         dhProjectionInverse[0][1] * clip.x + dhProjectionInverse[1][1] * clip.y + dhProjectionInverse[2][1] * clip.z + dhProjectionInverse[3][1] * clip.w,
                         dhProjectionInverse[0][2] * clip.x + dhProjectionInverse[1][2] * clip.y + dhProjectionInverse[2][2] * clip.z + dhProjectionInverse[3][2] * clip.w,
                         dhProjectionInverse[0][3] * clip.x + dhProjectionInverse[1][3] * clip.y + dhProjectionInverse[2][3] * clip.z + dhProjectionInverse[3][3] * clip.w); // 与带抖动版本同一算式。
    return view.xyz / view.w; // 透视除法。
}

// 远景视空间位置投到屏幕，可选补抖动。
vec3 ogxScreenPosFromViewPosDh(vec3 viewPos, vec2 taaJitter, bool useJitter, mat4 dhProjection)
{
    vec3 screenPos = vec3(dhProjection[0][0], dhProjection[1][1], dhProjection[2][2]) * viewPos + ogxMatrixTranslation(dhProjection); // 远景投影对角项与平移列。
    screenPos = screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法。
    if (useJitter) screenPos.xy += taaJitter * 0.5; // 补回半个抖动像素。
    return screenPos;
}

// 不补抖动的远景投影：追踪结果要落在未抖动的像素格上。
vec3 ogxScreenPosFromViewPosRawDh(vec3 viewPos, mat4 dhProjection)
{
    vec3 screenPos = vec3(dhProjection[0][0], dhProjection[1][1], dhProjection[2][2]) * viewPos + ogxMatrixTranslation(dhProjection); // 远景投影对角项与平移列。
    return screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法后回到零到一。
}

// 远景屏幕深度换米制距离。
float ogxLinearDepthFromScreenDepthDh(float depth, mat4 dhProjectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景逆投影深度部分。
}

// 米制距离换远景屏幕深度。
float ogxScreenDepthFromLinearDepthDh(float depth, mat4 dhProjectionInverse)
{
    depth = (1.0 / depth - dhProjectionInverse[3][3]) / dhProjectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景屏幕深度换成同一距离在近景投影下的屏幕深度：先换米，再用近景投影换回。
float ogxScreenDepthFromDhScreenDepth(float depth, mat4 dhProjectionInverse, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 远景零到一转负一到一。
    depth = 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 换成米。
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 近景深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 阴影相机空间位置：视图变换后按正交投影缩放，深度折半。
vec3 ogxShadowViewPosExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    vec3 shadowPos = ogxMatrixMulPoint(shadowView, worldPos) + ogxMatrixTranslation(shadowView); // 世界位置转阴影相机空间。
    float scale = shadowProjection[0][0]; // 正交投影的水平缩放。
    return shadowPos * vec3(scale, scale, -scale * 0.5); // 按投影缩放，深度折半。
}

// 世界位置投到阴影图，不做边缘压缩。
vec3 ogxShadowScreenPosExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    return ogxShadowViewPosExplicit(worldPos, shadowView, shadowProjection) * 0.5 + 0.5; // 负一到一转零到一。
}

// 世界位置投到阴影图并做边缘压缩，`bias` 是压缩强度。
vec3 ogxShadowScreenPosDistortedExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection, float bias)
{
    vec3 shadowPos = ogxShadowViewPosExplicit(worldPos, shadowView, shadowProjection); // 先转到阴影相机空间。
    float dist = length(shadowPos.xy); // 到阴影图中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数。
    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩。
    return shadowPos * 0.5 + 0.5; // 转成零到一。
}

// 读取端补一次边缘压缩，与写入端使用同一个 `bias`。
vec2 ogxDistortShadowPosExplicit(vec2 shadowPos, float bias)
{
    shadowPos = shadowPos * 2.0 - 1.0; // 零到一转负一到一。
    float dist = length(shadowPos.xy); // 到中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 同一压缩系数。
    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
    return shadowPos * 0.5 + 0.5; // 再转回零到一。
}

// 通用投影：取矩阵的对角项与最后两列，与参考实现的 `projMAD` 逐项一致。
vec4 ogxProject(mat4 m, vec3 pos)
{
    return vec4(m[0][0], m[1][1], m[2][2], m[2][3]) * pos.xyzz + m[3]; // 对角项乘坐标再加平移列。
}

// 投影并做齐次除法。
vec3 ogxProjectAndDivide(mat4 m, vec3 pos)
{
    vec4 homogenous = ogxProject(m, pos); // 先投影。
    return homogenous.xyz / homogenous.w; // 再除以齐次分量。
}

// 屏幕坐标转视空间：先转负一到一，再用逆投影。
vec3 ogxScreenToViewSpace(vec3 screenPos, mat4 projectionInverse)
{
    vec3 ndcPos = 2.0 * screenPos - 1.0; // 零到一转负一到一。
    return ogxProjectAndDivide(projectionInverse, ndcPos); // 逆投影。
}

// 视空间转屏幕：投影后除以齐次分量，再转零到一。
vec3 ogxViewToScreenSpace(vec3 viewPos, mat4 projection)
{
    vec3 ndcPos = ogxProjectAndDivide(projection, viewPos); // 投影并除齐次。
    return ndcPos * 0.5 + 0.5; // 转零到一。
}

// 视空间位置投到裁剪空间，深度不折半：Eclipse 的 `toClipSpace3`。
vec3 ogxToClipSpace3(vec3 viewSpacePosition, mat4 projection)
{
    return ogxProjectAndDivide(projection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5; // 参考实现的透视缩放。
}

// 屏幕坐标转视空间：Eclipse 的 `toScreenSpace`，与 PhotonGTAO 的版本只在命名上不同。
vec3 ogxToScreenSpace(vec3 p, mat4 projectionInverse)
{
    vec4 inverseDiag = vec4(projectionInverse[0][0], projectionInverse[1][1], projectionInverse[2][2], projectionInverse[2][3]); // 逆投影的对角项。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + projectionInverse[3]; // 对角项乘坐标再加平移。
    return fragPosition.xyz / fragPosition.w; // 齐次除法。
}

// 屏幕坐标转视空间方向，只保留方向不保留长度。
vec3 ogxToScreenSpaceVector(vec3 p, mat4 projectionInverse)
{
    vec4 inverseDiag = vec4(projectionInverse[0][0], projectionInverse[1][1], projectionInverse[2][2], projectionInverse[2][3]); // 逆投影对角项。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + projectionInverse[3]; // 逆投影。
    return normalize(fragPosition.xyz); // 只取方向。
}

// 视空间位置转相机相对世界位置。
vec3 ogxToWorldSpace(vec3 p3, mat4 modelViewInverse)
{
    return ogxMatrixMulPoint(modelViewInverse, p3) + ogxMatrixTranslation(modelViewInverse); // 视空间转世界。
}

// 视空间位置转绝对世界位置：再加相机世界坐标。
vec3 ogxToWorldSpaceCamera(vec3 p3, mat4 modelViewInverse, vec3 cameraWorldPos)
{
    return ogxToWorldSpace(p3, modelViewInverse) + cameraWorldPos; // 相机相对世界加相机位置。
}

// 视空间位置转阴影空间。
vec3 ogxToShadowSpace(vec3 p3, mat4 modelViewInverse, mat4 shadowView)
{
    p3 = ogxToWorldSpace(p3, modelViewInverse); // 先转世界。
    return ogxMatrixMulPoint(shadowView, p3) + ogxMatrixTranslation(shadowView); // 再转阴影相机。
}

// 视空间位置转阴影空间并乘投影：深度方向按参考实现只取对角项。
vec3 ogxToShadowSpaceProjected(vec3 p3, mat4 modelViewInverse, mat4 shadowView, mat4 shadowProjection)
{
    p3 = ogxToWorldSpace(p3, modelViewInverse); // 先转世界。
    p3 = ogxMatrixMulPoint(shadowView, p3) + ogxMatrixTranslation(shadowView); // 再转阴影相机。
    return vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * p3 + ogxMatrixTranslation(shadowProjection); // 乘投影对角项并加平移。
}

// 远景屏幕坐标还原视空间：近景深度与远景深度分两条路。
vec3 ogxToScreenSpaceDh(vec2 texcoord, float depth, float dhDepth, mat4 projectionInverse, mat4 dhProjectionInverse)
{
    if (depth < 1.0) // 近景像素用近景逆投影。
    {
        return ogxToScreenSpace(vec3(texcoord, depth), projectionInverse); // 与近景同一算式。
    }
    return ogxToScreenSpace(vec3(texcoord, dhDepth), dhProjectionInverse); // 远景像素用远景逆投影。
}

// 视空间位置投到裁剪空间，可按 `depthCheck` 选择远景矩阵。
vec3 ogxToClipSpace3Dh(vec3 viewSpacePosition, bool depthCheck, mat4 projection, mat4 dhProjection)
{
    mat4 projectionMatrix = depthCheck ? dhProjection : projection; // 按开关选矩阵。
    return ogxProjectAndDivide(projectionMatrix, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5; // 与近景同一算式。
}

// 远景阴影投影微调：把投影的远平面改成两倍远景距离，其余项保留。
mat4 ogxDhShadowProjectionTweak(mat4 projection, float farPlane, float dhFarPlane, bool enabled)
{
    if (!enabled) return projection; // 开关关闭时原样返回。
    float tweakFar = 3.0 * farPlane; // 近景默认远平面。
    tweakFar = 2.0 * dhFarPlane; // 远景按两倍距离。
    mat4 result = projection; // 复制一份再改。
    result[2][2] = -2.0 / tweakFar; // 只改深度缩放。
    result[3][2] = 0.0; // 清掉深度平移。
    return result; // 交回微调后的投影。
}

// 光传播体积坐标：世界位置减去体积原点，再落到体素格。
vec3 ogxGetLpvPosition(vec3 worldPos, vec3 lpvOrigin, float voxelSize)
{
    return (worldPos - lpvOrigin) / voxelSize; // 换到体积格坐标。
}

// 深度约定交换：参考实现只把屏幕深度转成线性距离，不做数值变换。
float ogxSwapperlinZ2(float depth, float nearPlane, float farPlane)
{
    return (2.0 * nearPlane) / (farPlane + nearPlane - depth * (farPlane - nearPlane)); // 参考实现的分式。
}

// 快速深度线性化：Eclipse 的屏幕深度转米制距离。
float ogxInvertLinearizeDepthFast(float z, float nearPlane, float farPlane)
{
    return (farPlane * (z - nearPlane)) / (z * (farPlane - nearPlane)); // 参考实现的分式。
}

// 屏幕坐标转视空间：Eclipse 的 `toScreenSpace2`，可按 `depthCheck` 选择远景逆投影。
vec3 ogxToScreenSpace2(vec3 p, bool depthCheck, mat4 projectionInverse, mat4 dhProjectionInverse)
{
    mat4 matrix = depthCheck ? dhProjectionInverse : projectionInverse; // 按开关选矩阵。
    vec4 inverseDiag = vec4(matrix[0][0], matrix[1][1], matrix[2][2], matrix[2][3]); // 逆投影的对角项与深度平移。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + matrix[3]; // 对角项乘坐标再加平移。
    return fragPosition.xyz / fragPosition.w; // 齐次除法。
}

// 光传播体积坐标：玩家相对位置加相机小数偏移，再平移到体积中心。
vec3 ogxGetLpvPositionExplicit(vec3 playerPos, vec3 cameraOffset, float lpvSize)
{
    return playerPos + cameraOffset + vec3(lpvSize * 0.5); // 与参考实现的 `LpvSize3/2u` 相同。
}

#endif
