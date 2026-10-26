/*
Omni 通用图形库阴影模块：阴影相机投影、边缘压缩、屏幕空间阴影、PCSS 软阴影、级联选择。
调用位置：任何需要方向光阴影贴图或屏幕空间阴影的程序；Minecraft 光影由 `/omni-gfx/shadow.glsl` 引入。
可复制示例：
    float3 c = ogxShadowScreenPosDistorted(worldPos, lightView, lightProjection, 0.9); // 带边缘压缩的阴影坐标。
    float v = ogxPcssVisibility(shadowMap, c, c.z, texel, 12.0, 24.0, 0.0016, 8, 12); // 一张贴图的软阴影。
    OgxCascadeSelect s = ogxSelectCascade(viewDepth, float3(32.0, 64.0, 128.0), 6.0); // 选级联与过渡权重。
设计原因与取舍：
    矩阵、纹理、分辨率与选项全部由调用方传入，库不读取引擎状态；深度图的格式由调用方决定。
    算式与旧 `shaders/gfx/shadow.glsl` 逐项一致，迁移只改名字和语法，默认画面因此不变。
    PCSS 与级联是阶段三新增能力：半影宽度由遮挡物距离推出，级联交界做线性过渡，避免硬边。
    矩阵乘法在 Slang 与 GLSL 的行列解释不同，这里统一走数学模块的列展开入口，不直接乘矩阵。
*/
#ifndef OGX_SHADOW_INCLUDED
#define OGX_SHADOW_INCLUDED

// 饱和、矩阵列展开与圆周常数来自数学模块。
#include "math.slang"

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

// 黄金角的正弦与余弦：螺旋采样每步旋转这个角度，样本才不会排成放射状条纹。
static const float OGX_SHADOW_GOLDEN_COS = -0.737368878;
static const float OGX_SHADOW_GOLDEN_SIN = 0.675490294;

// 阴影相机空间里的位置：先做视图变换，再按正交投影缩放并把深度折半。
// 为什么深度取半：阴影图存的是裁剪空间到零到一的压缩值，后面所有比较都按同一尺度进行。
float3 ogxShadowViewPos(float3 worldPos, float4x4 shadowView, float4x4 shadowProjection)
{
    float3 shadowPos = ogxMatrixMulPoint(shadowView, worldPos) + ogxMatrixTranslation(shadowView); // 世界位置转到阴影相机空间。
    float scale = shadowProjection[0][0]; // 正交投影的水平缩放，横纵相同。
    shadowPos *= float3(scale, scale, -scale * 0.5); // 按投影缩放，深度取半。
    return shadowPos; // 返回阴影相机空间的坐标。
}

// 投到阴影图，不做边缘压缩：坐标范围仍是负一到一。
float3 ogxShadowScreenPos(float3 worldPos, float4x4 shadowView, float4x4 shadowProjection)
{
    return ogxShadowViewPos(worldPos, shadowView, shadowProjection) * 0.5 + 0.5; // 负一到一转成零到一。
}

// 投到阴影图并做边缘压缩：离中心越远压得越紧，边缘纹素因此覆盖更小的实际范围。
float3 ogxShadowScreenPosDistorted(float3 worldPos, float4x4 shadowView, float4x4 shadowProjection, float bias)
{
    float3 shadowPos = ogxShadowViewPos(worldPos, shadowView, shadowProjection); // 先转到阴影相机空间。
    float dist = length(shadowPos.xy); // 到阴影图中心的距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数，中心为一。
    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩，零点九五留出边界余量。
    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一。
}

// 读取端补一次边缘压缩：写入端压过的坐标，读取时必须按同一系数还原。
float2 ogxDistortShadowPos(float2 shadowPos, float bias)
{
    shadowPos = shadowPos * 2.0 - 1.0; // 零到一先转回负一到一。
    float dist = length(shadowPos.xy); // 到中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 与写入端同一压缩系数。
    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
    return shadowPos * 0.5 + 0.5; // 再转回零到一。
}

// 屏幕深度换米制距离：逆投影里只有深度那一列参与，两个系数就是全部信息。
// 为什么不用整矩阵乘：这一步在每条步进的射线上都要算，取两个系数最省。
float ogxShadowLinearDepth(float depth, float4x4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 射线是否还在可靠深度范围内：近处像素的深度图只有半个屏幕可用。
bool ogxInsideDepthRange(float3 samplePos)
{
    return ogxEqual(samplePos.xy, ogxSaturate(samplePos.xy)); // 横纵都在零到一才算有效。
}

// 屏幕空间阴影：从表面沿光源方向在屏幕里步进，走到比射线更近的几何就判为遮挡。
// 为什么起点要沿法线抬一点：贴近表面的光源不抬会刚出发就打到自己，整片出现自阴影。
// 为什么用抖动：固定采样会在光斑边缘留下规则条纹，配合时间抗锯齿后条纹消失。
// 步数由调用方按画质给，八步与十六步对应原来的低、高质量。
float ogxScreenSpaceShadow(float3 viewPos, float3 viewDir, float3 normal, float3 shadowDir,
    Sampler2D depthTexture, Sampler2D dhDepthTexture, float4x4 projection, float4x4 projectionInverse,
    float4x4 dhProjectionInverse, float pixelScale, float2 offsetCoord, float noise, bool hasDh, int steps, float strength)
{
    shadowDir.z = max(shadowDir.z, 1e-5); // 深度分量保证不太小，避免除法把射线推到无穷远。
    float rayLength = -0.04 * viewPos.z / shadowDir.z; // 一步射线的长度，按当前深度与光源方向缩放。
    float3 viewRayDir = shadowDir * rayLength; // 视空间里的射线方向。
    float3 start = viewPos; // 射线起点就是当前表面。
    float ndotl = ogxSaturate(dot(shadowDir, normal)); // 光源方向与法线的夹角余弦。
    float fov = atan(1.0 / projection[1][1]) * 360.0 * OGX_INV_PI; // 由投影反推视角，供偏移按视野缩放。
    start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿射线先跳过一段，掠射时跳得更多。
    start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(ndotl, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
    float3 end = start + viewRayDir; // 一步的终点。
    start = float3(float2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
    end = float3(float2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
    float3 screenRayDir = end - start; // 这一步在裁剪空间的位移。
    screenRayDir.xy *= 0.5; // 横纵方向换算到零到一坐标。
    start.xy += float2(projection[3][0], projection[3][1]); // 补上投影的平移项。
    start.xy *= 0.5; // 裁剪空间转到零到一。
    float minDist = ogxShadowLinearDepth(0.7, projectionInverse); // 深度小于这个值的像素在前面，不再作为遮挡。
    float shadow = 1.0; // 可见度，初值全亮。
    float stepLength = 1.0; // 步长，逐步增大。
    for (int i = 0; i < steps; i++, start += screenRayDir * stepLength, stepLength += 0.3) // 步长递增覆盖更远。
    {
        float3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
        if (samplePos.z < minDist) // 已经走到相机很近的地方，后面没有可靠深度。
        {
            break;
        }
        samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。
        if (!ogxInsideDepthRange(samplePos)) // 出了屏幕就停止，屏幕外没有可靠深度。
        {
            break;
        }
        float sampleDepth = depthTexture.SampleLevel(samplePos.xy, 0.0).x; // 读该点的不透明深度。
        if (sampleDepth < 0.7) // 近处已有几何挡住，后面不必再看。
        {
            break;
        }
        // 参考实现会再读一次同一像素，用第二次结果算距离；保留两次采样以对齐采样顺序。
        float sampleDepthAgain = depthTexture.SampleLevel(samplePos.xy, 0.0).x;
        float sampleDist; // 采样点到相机的米制距离。
        if (hasDh && sampleDepth == 1.0) // 近景是天空时改读远景深度。
        {
            sampleDepth = dhDepthTexture.SampleLevel(samplePos.xy, 0.0).x; // 改读远景深度。
            sampleDist = ogxShadowLinearDepth(sampleDepth, dhProjectionInverse); // 远景深度换成距离。
        }
        else
        {
            sampleDist = ogxShadowLinearDepth(sampleDepthAgain, projectionInverse); // 近景深度换成距离。
        }
        if (samplePos.z - sampleDist > 0.0) // 射线深度超过几何深度，说明几何在前面。
        {
            shadow = 0.0; // 记为完全遮挡。
            break; // 结束步进。
        }
    }
    // 参考的固定底光是暗部 0.15、亮部 0.85；选项强度零点八五时两者完全一致。
    // 强度作为遮挡量的缩放，零点八五保持参考值，零表示完全不压暗。
    float occluded = (1.0 - shadow) * (strength / 0.85);
    shadow = 1.0 - occluded;
    return shadow * 0.85 + 0.15;
}

// 阳光的屏幕空间阴影：在屏幕里沿阳光方向步进，撞到比当前更近的几何就按吸收量削弱。
// 为什么叶片先用饱和放大：叶片材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
// `fov` 由调用方按材质选择（草和叶片用较大视野估计），`absorption` 是每次遮挡的吸收量。
float ogxSunScreenShadow(float3 viewPos, float3 viewDir, float3 normal, float3 shadowVector, float fov,
    float absorption, float softness, float grass, Sampler2D depthTexture, Sampler2D dhDepthTexture,
    float4x4 projection, float4x4 projectionInverse, float4x4 dhProjectionInverse, float pixelScale, float minStep,
    float2 offsetCoord, float noise, bool hasDh, int steps)
{
    float3 viewRayDir = shadowVector * max(-viewPos.z * 3e-5 * fov, minStep); // 每一步在屏幕上的推进量。
    float3 start = viewPos; // 步进起点。
    if (softness < 0.1) // 普通表面才做偏移，草和叶片的画面已经足够软。
    {
        float ndotl = ogxSaturate(dot(shadowVector, normal)); // 阳光与法线的夹角。
        start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿光线先跳过一段。
        start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(ndotl, 0.01)); // 再沿法线抬一点。
    }
    float3 end = start + viewRayDir; // 一步的终点。
    start = float3(float2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
    end = float3(float2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
    float3 screenRayDir = end - start; // 这一步在裁剪空间的位移。
    screenRayDir.xy *= 0.5; // 换算到零到一坐标。
    start.xy += float2(projection[3][0], projection[3][1]); // 补上投影的平移项。
    start.xy *= 0.5; // 转到零到一。
    start += screenRayDir * grass; // 草的原点再前进一小段，减少草自身投出的错误阴影。
    float shadow = 1.0; // 阴影可见度，初值全亮。
    float stepLength = 1.0; // 步长，逐步增大。
    float zThickness = 0.025 + 0.0125 * -viewPos.z; // 遮挡厚度阈值，距离越远越厚，避免远处噪点。
    for (int i = 0; i < steps; i++, start += screenRayDir * stepLength, stepLength += 0.3) // 步长递增覆盖更远。
    {
        float3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
        samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。
        if (!ogxInsideDepthRange(samplePos)) // 出了屏幕就停止。
        {
            break;
        }
        float sampleDepth = depthTexture.SampleLevel(samplePos.xy, 0.0).x; // 近景深度。
        float sampleDist; // 采样点到相机的米制距离。
        if (hasDh && sampleDepth == 1.0) // 近景是天空时才查远景。
        {
            sampleDepth = dhDepthTexture.SampleLevel(samplePos.xy, 0.0).x; // 改读远景深度。
            sampleDist = ogxShadowLinearDepth(sampleDepth, dhProjectionInverse); // 远景深度换成距离。
        }
        else
        {
            sampleDist = ogxShadowLinearDepth(sampleDepth, projectionInverse); // 近景深度换成距离。
        }
        float depthDiff = samplePos.z - sampleDist; // 射线深度与几何深度之差，为正说明几何在前面。
        if (depthDiff > 0.0 && depthDiff < zThickness) // 落在厚度阈值内才算遮挡。
        {
            shadow *= absorption; // 按吸收量削弱。
        }
        if (shadow < 0.01) // 已经足够暗，提前结束。
        {
            break;
        }
    }
    return shadow; // 返回可见度。
}

// 阴影图里一段视线的遮挡距离：沿线段采样，统计被实心几何挡住的样本比例并折算成米。
// 为什么把线段长度传进来：样本比例要乘实际长度才是米，调用方已经知道这段有多长。
float ogxShadowSegmentOcclusion(float3 shadowStart, float3 shadowEnd, Sampler2D shadowTexture, int steps,
    float noise, float bias, float segmentLength)
{
    float rSteps = 1.0 / float(steps); // 采样数倒数。
    float3 increment = (shadowEnd - shadowStart) * rSteps; // 阴影图里的步进。
    float3 position = increment * noise + shadowStart; // 起点加抖动。
    float occluded = 0.0; // 被挡住的样本数。
    for (int i = 0; i < steps; i++, position += increment) // 沿视线段采样。
    {
        float3 shadowPos = position; // 当前采样坐标。
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, bias); // 补边缘压缩。
        if (ogxInsideDepthRange(shadowPos) && shadowPos.z < 1.0) // 落在阴影图内。
        {
            float solidDepth = shadowTexture.SampleLevel(shadowPos.xy, 0.0).x; // 读遮挡深度。
            occluded += step(solidDepth, shadowPos.z); // 遮挡物在射线前面才算被挡。
        }
    }
    return occluded * (segmentLength * rSteps); // 按样本比例折算成被遮挡的米数。
}

// 不透明表面阴影：可变半影、彩色半透明阴影与次表面散射，三者共用同一次阴影图采样。
// 为什么先做透光散射：叶片、草这类薄片本身就透光，先算透光再把阳光按比例削弱，阴影才不会过硬。
// 为什么阴影图外坐标直接放弃采样：半影采样会跑出阴影图边界，硬读边界会把边界压成一条黑线。
float3 ogxVariablePenumbraShadow(float3 worldPos, float3 worldNormal, float sunlight, float3 albedo,
    float scatteringStrength, float hand, float leaves, float grass, float3 cameraWorldPosition, float3 viewAxisZ,
    float4x4 shadowView, float4x4 shadowProjection, Sampler2D shadowDepth0, Sampler2DShadow shadowDepth1,
    Sampler2D shadowColor0, float shadowMapResolution, float shadowDistance, float farPlane, float bias,
    float2 noise, bool variablePenumbra, bool coloredShadows, bool sssDirectional, float sssBrightness,
    float sssPhase, float sssQuality, float vpsQuality, float vpsSpread, float basicBlur, out float3 sss)
{
    worldPos += cameraWorldPosition; // 相机相对世界位置补上相机位置，换成阴影相机能用的世界坐标。
    worldPos -= viewAxisZ * 0.5 * hand; // 手持物抬高半格，避免手贴脸时投出错误的自阴影。
    float3 shadowNormal = ogxMatrixMulPoint(shadowView, worldNormal); // 世界法线转到阴影相机空间。
    shadowNormal.z = -shadowNormal.z; // 深度轴与视空间相反，翻转过来比较方向才正确。
    float3 shadowScreenPos = ogxShadowViewPos(worldPos, shadowView, shadowProjection); // 按投影缩放、深度取半。
    float zScale = 1.0 / shadowProjection[0][0]; // 深度缩放倒数，把深度差还原成实际距离。
    float dist = length(shadowScreenPos.xy); // 到阴影图中心的距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数，与坐标变换一致。
    float3 result = float3(1.0); // 阴影可见度，初值全亮。
    sss = float3(0.0); // 次表面散射初值为零。
    if (scatteringStrength > 0.0) // 只有透光材质才走散射，普通表面直接跳过整段。
    {
        float3 shadowScreenPosRaw = shadowScreenPos; // 未压缩坐标，散射采样要用。
        shadowScreenPosRaw.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
        shadowScreenPosRaw = shadowScreenPosRaw * 0.5 + 0.5; // 转成零到一纹理坐标。
        float spread = (scatteringStrength * 0.12 + 0.05) / (distortFactor * shadowDistance) + basicBlur / shadowMapResolution; // 散射采样半径。
        float3 scatteringDensity = 15.0 / (scatteringStrength * albedo + 0.1); // 散射密度：底色越亮越容易透过。
        float rSteps = 1.0 / sssQuality; // 次数倒数，用来归一化半径与结果。
        float angle = noise.x * 6.28318530718; // 初始角度取随机，避免所有像素从同一方向起步。
        float2 rot = float2(cos(angle), sin(angle)); // 当前旋转方向。
        float scatteringDepth = 0.0; // 累计散射深度。
        for (float i = 0.0; i < sssQuality; i++) // 逐次采样阴影图，累计遮挡厚度。
        {
            rot = float2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                         -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
            float radius = (i + noise.y) * rSteps; // 半径从随机相位起步，样本不重叠。
            float2 offset = rot * spread * radius; // 当前采样偏移。
            float sampleDepth = shadowDepth0.SampleLevel(shadowScreenPosRaw.xy + offset, 0.0).x; // 读取该点遮挡深度。
            scatteringDepth += max(shadowScreenPosRaw.z - sampleDepth, 1e-5); // 累加接收点到遮挡物的距离。
        }
        scatteringDepth *= rSteps * zScale; // 取平均并还原成实际距离。
        float3 scattering = exp2(-scatteringDepth * scatteringDensity); // 厚度越大透光越弱。
        float distFalloff = ogxSaturate(((min(shadowDistance, farPlane) - length(worldPos)) * 0.05 - 1.0)); // 超出阴影范围就淡出透光。
        if (sssDirectional) // 开启朝向透光时按观察角计算。
        {
            sss = scattering * (sssBrightness * distFalloff * (sssPhase * 0.5 + 0.15)); // 逆光方向更亮。
        }
        else
        {
            sss = scattering * (sssBrightness * distFalloff * 0.2); // 固定占比，不随角度变化。
        }
        scatteringStrength *= distFalloff; // 阳光也按同一淡出缩放，远处不再额外透光。
    }
    if (sunlight > 0.0) // 没有阳光时不必采样阴影。
    {
        shadowScreenPos += shadowNormal * (0.002 * (1.0 - leaves) * distortFactor); // 沿法线抬一点减少自身条纹，叶片不抬以免漏光。
        shadowScreenPos.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
        shadowScreenPos = shadowScreenPos * 0.5 + 0.5; // 转成零到一纹理坐标。
        if (ogxInsideDepthRange(shadowScreenPos)) // 只在阴影图内采样，图外保持全亮。
        {
            result = float3(0.0); // 从全暗开始累加可见样本。
            float spread = vpsSpread * 200.0 / (distortFactor * shadowDistance); // 半影搜索半径。
            float avgDiff = 0.0; // 遮挡物与接收点的平均深度差，用来放大半影。
            if (variablePenumbra) // 可变半影：先估遮挡物距离再决定边缘宽度。
            {
                float spreadLod = log2(shadowMapResolution / 512.0); // 高分辨率用更粗层级抑制噪点。
                for (int i = -1; i <= 1; i++) // 三乘三邻域估计遮挡物距离。
                {
                    for (int j = -1; j <= 1; j++)
                    {
                        float2 lookupCoord = shadowScreenPos.xy + float2(i, j) * spread * 0.0039; // 邻域采样坐标。
                        float depthDiff = shadowScreenPos.z - shadowDepth0.SampleLevel(lookupCoord, spreadLod).x; // 接收点深度减去遮挡物深度。
                        depthDiff = clamp(depthDiff * zScale * 0.0035, 0.0, 0.025); // 归一化并限制范围。
                        avgDiff += depthDiff * depthDiff; // 平方累加，后面开根得到均方根。
                    }
                }
                avgDiff /= 9.0; // 求九个样本的平均。
                avgDiff = sqrt(avgDiff); // 开根得到平均深度差。
            }
            avgDiff = max(avgDiff, 0.015 * leaves + 0.01 * grass); // 叶片与草至少给一点半影，避免薄片边缘过硬。
            float sampleSpread = avgDiff * 0.2 * spread + basicBlur / shadowMapResolution; // 最终采样半径。
            shadowScreenPos.z -= (2e-6 + noise.y * 2e-6) * (dist + 0.03) * (1.0 - 0.9 * leaves) * shadowDistance; // 深度偏移随距离增大。
            float rSteps = 1.0 / vpsQuality; // 次数倒数。
            float angle = noise.y * 6.28318530718; // 初始角度取随机。
            float2 rot = float2(cos(angle), sin(angle)); // 当前旋转方向。
            for (float i = 0.0; i < vpsQuality; i++) // 逐次采样阴影图求未遮挡比例。
            {
                rot = float2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                             -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
                float radius = sqrt((i + noise.x) * rSteps); // 平方根半径让样本在圆面上均匀分布。
                float2 offset = rot * radius * sampleSpread; // 当前采样偏移。
                float3 sampleCoord = float3(shadowScreenPos.xy + offset, shadowScreenPos.z); // 采样坐标。
                if (coloredShadows) // 彩色阴影：半透明层用自身颜色，实心层只按遮挡。
                {
                    float translucentShadow = step(sampleCoord.z, shadowDepth0.SampleLevel(sampleCoord.xy, 0.0).x); // 深度更远即未遮挡。
                    result += float3(translucentShadow); // 半透明部分累加可见度。
                    float solidShadow = shadowDepth1.SampleCmpLevelZero(sampleCoord.xy, sampleCoord.z); // 实心阴影贴图含彩色合成结果。
                    float3 shadowColorSample = ogxGammaToLinear(shadowColor0.SampleLevel(sampleCoord.xy, 0.0).rgb); // 该点半透明颜色转线性。
                    result += shadowColorSample * (solidShadow - translucentShadow); // 实心与半透明之差乘颜色。
                }
                else // 关闭彩色阴影时只按实心遮挡。
                {
                    result += float3(shadowDepth1.SampleCmpLevelZero(sampleCoord.xy, sampleCoord.z)); // 直接累加可见度。
                }
            }
            result *= rSteps; // 取平均得到最终可见度。
        }
    }
    if (sssDirectional) // 开启朝向透光时，用透光比例把阴影往亮处提一点。
    {
        return result * (ogxSaturate(0.4 - scatteringStrength * 0.4) + 0.6); // 透光越强整体越亮。
    }
    return result * (ogxSaturate(0.5 - scatteringStrength * 0.5) + 0.5); // 关闭时提亮幅度更小。
}

// --- 阶段三新增：级联选择与 PCSS ---

// 级联选择结果：当前级的编号、过渡到的下一级编号与过渡权重。
// 为什么返回编号而不是矩阵：级联矩阵在调用方的缓冲区里，库只决定用哪一级。
struct OgxCascadeSelect
{
    int index; // 视深度所在的级联编号，零为最近。
    int next; // 过渡目标级联编号，没有过渡时等于当前级。
    float weight; // 下一级的混合权重，零表示完全使用当前级。
};

// 选择级联：`splits` 是三级的分界距离，`blendWidth` 是交界处的过渡宽度（米）。
// 为什么交界要做过渡：两级阴影贴图分辨率不同，硬切换会在交界出现一圈密度跳变。
OgxCascadeSelect ogxSelectCascade(float viewDepth, float3 splits, float blendWidth)
{
    OgxCascadeSelect result; // 待填的选择结果。
    result.index = 0; // 默认用最近一级。
    if (viewDepth > splits.x) // 超过第一级分界。
    {
        result.index = 1;
    }
    if (viewDepth > splits.y) // 超过第二级分界。
    {
        result.index = 2;
    }
    if (viewDepth > splits.z) // 超过最远分界时仍用最远一级，避免画面出现完全没有阴影的洞。
    {
        result.index = 2;
    }
    float farSplit = result.index == 0 ? splits.x : (result.index == 1 ? splits.y : splits.z); // 当前级的分界距离。
    result.weight = result.index < 2 ? ogxSaturate((viewDepth - (farSplit - blendWidth)) / max(blendWidth, 1e-4)) : 0.0; // 靠近分界时渐入下一级。
    result.next = min(result.index + 1, 2); // 过渡目标是下一级，最远级没有下一级。
    return result; // 返回可直接用于两次采样的结果。
}

// PCSS 半影半径：遮挡物离接收点越远，半影越宽；这是软阴影看起来有距离感的原因。
// `lightSize` 是光源在阴影图平面的相对尺寸，`projectorScale` 把世界尺寸换算成纹素。
float ogxPcssFilterRadius(float blockerDepth, float receiverDepth, float lightSize, float projectorScale)
{
    float gap = max(receiverDepth - blockerDepth, 0.0); // 遮挡物与接收点的深度差。
    return ogxSaturate(gap * projectorScale) * lightSize; // 深度差越大半影越宽，上限由光源尺寸给出。
}

// PCSS 软阴影：先用少量样本找遮挡物平均深度，再按半影宽度做百分比过滤。
// 为什么分两步：固定核宽会让远处的阴影过硬、近处的阴影过软，遮挡物搜索让核宽随距离变化。
// 采样用黄金角螺旋，样本分布均匀；`dither` 让相邻像素的旋转角不同，配合时间抗锯齿消除噪点。
float ogxPcssVisibility(Sampler2D shadowMap, float3 shadowCoord, float texelSize,
    float searchRadiusTexels, float filterRadiusTexels, float bias, int searchSteps, int filterSteps, float dither)
{
    float2 rot = float2(cos(dither * 6.28318530718), sin(dither * 6.28318530718)); // 起始旋转角按抖动错开。
    float blockerSum = 0.0; // 遮挡物深度累加。
    float blockerCount = 0.0; // 遮挡物样本数。
    float searchRadius = searchRadiusTexels * texelSize; // 遮挡物搜索半径，换算到纹理坐标。
    for (int i = 0; i < searchSteps; i++) // 第一步：找遮挡物。
    {
        rot = float2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                     -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
        float radius = sqrt((float(i) + 0.5) / float(searchSteps)) * searchRadius; // 圆面均匀分布的半径。
        float sampleDepth = shadowMap.SampleLevel(shadowCoord.xy + rot * radius, 0.0).x; // 读该点的最近深度。
        if (sampleDepth < shadowCoord.z - bias) // 只有比接收点更近的样本才是遮挡物。
        {
            blockerSum += sampleDepth; // 累加遮挡物深度。
            blockerCount += 1.0; // 计数。
        }
    }
    if (blockerCount < 0.5) // 没有遮挡物，说明这一点完全受光。
    {
        return 1.0;
    }
    float blockerDepth = blockerSum / blockerCount; // 平均遮挡物深度。
    float penumbra = ogxPcssFilterRadius(blockerDepth, shadowCoord.z, filterRadiusTexels, 40.0); // 半影宽度，纹素为单位。
    float filterRadius = max(penumbra, 1.0) * texelSize; // 至少一个纹素，避免完全退化成硬阴影。
    float visible = 0.0; // 受光样本数。
    for (int i = 0; i < filterSteps; i++) // 第二步：按半影宽度做百分比过滤。
    {
        rot = float2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                     -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 继续旋转同一个螺旋。
        float radius = sqrt((float(i) + 0.5) / float(filterSteps)) * filterRadius; // 过滤半径。
        float sampleDepth = shadowMap.SampleLevel(shadowCoord.xy + rot * radius, 0.0).x; // 读深度。
        visible += step(shadowCoord.z - bias, sampleDepth); // 接收点不深于该样本就算受光。
    }
    return visible / float(filterSteps); // 平均得到可见度。
}

#endif
