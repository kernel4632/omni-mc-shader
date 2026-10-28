/*
全局光子文件：地平线遮蔽的参考实现、多弹射补偿、双边升采样与反射阴影图。
调用位置：由 `gi/gi.slang` 内联，全局光时间滤波与严格 profile 使用这里的入口。
可复制示例：`float ao = ogxGroundTruthAo(viewPos, viewDir, normal, coord, aspect, depthTex, farTex, proj, invProj, farInvProj, params, noise);`
设计原因与取舍：这是参考画质的多次切片遮蔽，供全局光内部使用；独立画面遮蔽的
低成本版本在 `gi/ambientocclusion.slang`，两者按用途分工，不互相包含，避免把重算法带进轻量阶段。
*/
// 环境光遮蔽的多重反弹近似：用反照率补偿被遮住的间接光。

// 双边升采样：把半分辨率的遮蔽（或任何四通道画面）放大到全分辨率。
// 四个相邻纹素先按深度筛一次：只有与参考深度相差不超过阈值的样本参与，物体边界不会被糊开。
// 为什么不用普通双线性：半分辨率的一格盖住全分辨率两格，边界处会把前景与背景混成一条灰边。
// `pixel` 是全分辨率像素坐标，`upscale` 是遮蔽图相对全分辨率的倍数（通常为二）；
// `referenceDepth` 与 `sourceDepth` 必须用同一套深度单位，阈值也按这套单位给出。
float4 ogxBilateralUpscale(Sampler2D source, Sampler2D sourceDepth, int2 pixel, int upscale,
    float referenceDepth, float depthThreshold)
{
    int2 base = pixel / upscale; // 当前像素落在遮蔽图的哪一格。
    float4 result = float4(0.0); // 加权颜色。
    float sum = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 四个相邻格，正好围住这一格。
    {
        int2 offset = int2(i < 2 ? -1 : 0, (i == 0 || i == 3) ? -1 : 0); // 四个格子的相对位置。
        int2 cell = base + offset; // 邻格坐标。
        float sampleDepth = sourceDepth.Load(int3(cell, 0)).r; // 邻格的深度。
        float weight = abs(sampleDepth - referenceDepth) < depthThreshold ? 1.0 : 1e-5; // 深度相近才参与。
        result += source.Load(int3(cell, 0)) * weight; // 累加颜色。
        sum += weight; // 累加权重。
    }
    return result / sum; // 归一化；四个样本全被拒绝时权重和仍然大于零。
}

// 屏幕坐标与深度还原视空间位置，不撤销抖动；重投影需要原始位置。
float3 ogxGiViewPos(float2 coord, float depth, float4x4 projection_inverse)
{
    float3 ndc = float3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    float3 pos = float3(float2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projection_inverse); // 只用逆投影的非零项与平移列。
    return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 远景屏幕坐标与深度还原视空间位置；没有远景时调用方不会走到这里。
float3 ogxGiViewPosDistant(float2 coord, float depth, float4x4 dh_projection_inverse)
{
    float3 ndc = float3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    float4 pos = ogxMatrixMul(dh_projection_inverse, float4(ndc, 1.0)); // 远景逆投影整矩阵乘法。
    return pos.xyz / pos.w; // 透视除法。
}

// 地平线遮蔽的参数：画质、半径模式、远景能力与强度都由调用方给出。
struct OgxGtaoParams
{
    float steps; // 环绕视线的切片数。
    float slice_steps; // 每个切片的搜索步数。
    float falloff_start; // 衰减起点，占半径的比例。
    float max_sample_radius; // 屏幕半径上限。
    float world_radius; // 世界半径模式下的起始半径。
    float screen_radius; // 屏幕半径模式下的固定半径。
    float strength; // 遮蔽强度，零为无遮蔽、一为全遮蔽。
    int radius_mode; // 零为世界半径，其他为屏幕半径。
    bool has_dh; // 是否有远景深度，决定世界半径随距离衰减的快慢。
    bool dh_ao; // 是否把远景样本当作遮挡物。
    bool falloff_z_offset; // 是否用深度加权的衰减距离。
};

// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 深度图、投影矩阵、画面坐标、比例与噪声全部由调用方传入，库不读取任何引擎画面。
// 一个地平线样本：按屏幕偏移取深度，天空样本改读远景，再按距离权重回落到地平线下限。
// 正反两个方向共用这一份，避免两段相同的采样与权重代码各自漂移。
float ogxAoHorizonSample(float2 coord, float2 sampleOffset, float3 viewPos, float3 viewDir, OgxGtaoParams params,
    float4x4 projectionInverse, float4x4 dhProjectionInverse, Sampler2D depthTexture, Sampler2D dhDepthTexture,
    float falloff, float lowerBound)
{
    float2 sampleCoord = coord + sampleOffset; // 采样坐标。
    float sampleDepth = depthTexture.SampleLevel(sampleCoord, 0.0).x; // 采样深度。
    float3 sampleVector; // 采样点相对当前点。
    if (params.has_dh && params.dh_ao && sampleDepth == 1.0) // 天空样本改读远景深度。
    {
        sampleDepth = dhDepthTexture.SampleLevel(sampleCoord, 0.0).x; // 远景深度。
        sampleVector = ogxGiViewPosDistant(sampleCoord, sampleDepth, dhProjectionInverse) - viewPos; // 远景还原。
    }
    else // 近景样本正常还原。
    {
        sampleVector = ogxGiViewPos(sampleCoord, sampleDepth, projectionInverse) - viewPos; // 近景还原。
    }
    float rSampleDist = rsqrt(dot(sampleVector, sampleVector)); // 距离倒数。
    float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
    float falloffWeight; // 衰减权重。
    if (params.falloff_z_offset) // 可选的深度加权。
    {
        float offsetDist = length(float3(sampleVector.xy, sampleVector.z * 1.7)); // 加权距离。
        falloffWeight = ogxRemapSaturate(offsetDist, falloff * params.falloff_start, falloff); // 衰减权重。
    }
    else // 默认按距离加权。
    {
        falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * params.falloff_start, falloff); // 衰减权重。
    }
    return lerp(cosHorizonAngle, lowerBound, falloffWeight); // 远处回落到下限。
}

// 地平线遮蔽：按切片方向搜索两侧可见地平线，再积分成遮蔽量。
float ogxGroundTruthAo(float3 viewPos, float3 viewDir, float3 normal, float2 coord, float aspect,
    Sampler2D depthTexture, Sampler2D dhDepthTexture, float4x4 projection, float4x4 projection_inverse,
    float4x4 dh_projection_inverse, OgxGtaoParams params, float2 noise)
{
    float rSteps = 1.0 / params.steps; // 切片数倒数。
    float rSliceSteps = 1.0 / params.slice_steps; // 步数倒数。
    float projFactor = 0.125 * projection[1][1]; // 投影缩放系数。
    float radius; // 世界半径或屏幕半径。
    float sampleRadiusRaw; // 换算后的屏幕半径。
    float sampleRadius; // 夹紧后的屏幕半径。
    float falloff; // 衰减距离。
    if (params.radius_mode == 0) // 世界半径模式。
    {
        radius = params.world_radius - viewPos.z * (params.has_dh ? 0.02 : 0.01); // 有远景时衰减更慢。
        sampleRadiusRaw = radius * projFactor / -viewPos.z; // 换成屏幕半径。
        sampleRadius = min(sampleRadiusRaw, params.max_sample_radius); // 上限。
        falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
    }
    else // 屏幕半径模式。
    {
        sampleRadius = params.screen_radius; // 固定屏幕半径。
        falloff = sampleRadius / projFactor * -viewPos.z; // 换算成世界衰减距离。
    }
    float ao = 0.0; // 累积的遮蔽。
    float slice_steps = params.slice_steps; // 每个切片的搜索步数。
    for (float i = 0.0; i < params.steps; i++) // 逐切片。
    {
        float sliceAngle = (i + noise.x) * rSteps * OGX_PI; // 切片角度，只扫半圈因为两侧对称。
        float3 sliceDir = float3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        float3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 切片方向正交到视线的分量。
        float3 axis = cross(sliceDir, viewDir); // 切片平面法向。
        float3 projNormal = normal - dot(normal, axis) * axis; // 法线投影到切片平面。
        float rProjNormalLength = rsqrt(dot(projNormal, projNormal)); // 投影长度倒数。
        float cosNormalAngle = ogxSaturate(dot(projNormal, viewDir) * rProjNormalLength); // 投影法线与视线夹角余弦。
        float normalAngle = sign(dot(orthoSliceDir, projNormal)) * ogxFastAcos(cosNormalAngle); // 带符号的法线角。
        float2 minCosHorizonAngle = cos(float2(normalAngle + OGX_HALF_PI, normalAngle - OGX_HALF_PI)); // 两侧地平线角的下限。
        float2 maxCosHorizonAngle = minCosHorizonAngle; // 两侧可见地平线角的初值。
        for (float j = 0.0; j < slice_steps; j++) // 逐搜索步。
        {
            float stepNoise = (i + j * slice_steps) * 0.61803399; // 用黄金比错开各步。
            stepNoise = fract(stepNoise + noise.y); // 加噪声后取小数。
            float offset = (j + stepNoise) * rSliceSteps; // 归一化搜索距离。
            offset *= offset; // 平方让近处更密。
            float2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
            sampleOffset.y *= aspect; // 修正宽高比。
            float cosHorizonAnglePos = ogxAoHorizonSample(coord, sampleOffset, viewPos, viewDir, params,
                projection_inverse, dh_projection_inverse, depthTexture, dhDepthTexture, falloff, minCosHorizonAngle.x); // 正向采样。
            maxCosHorizonAngle.x = max(cosHorizonAnglePos, maxCosHorizonAngle.x); // 取可见地平线角。
            float cosHorizonAngleNeg = ogxAoHorizonSample(coord, -sampleOffset, viewPos, viewDir, params,
                projection_inverse, dh_projection_inverse, depthTexture, dhDepthTexture, falloff, minCosHorizonAngle.y); // 反向采样。
            maxCosHorizonAngle.y = max(cosHorizonAngleNeg, maxCosHorizonAngle.y); // 取可见地平线角。
        }
        maxCosHorizonAngle = float2(-ogxFastAcos(maxCosHorizonAngle.y), ogxFastAcos(maxCosHorizonAngle.x)) * 2.0; // 两侧换成开口角。
        // 弧面积分由参考后端统一维护；输入完整开口角，与参考算式逐项一致。
        float horizonAngleIntegra = ogxGtaoHorizonGap(maxCosHorizonAngle, normalAngle, cosNormalAngle);
        ao += horizonAngleIntegra / rProjNormalLength; // 累加。
    }
    ao *= 0.25 * rSteps; // 平均。
    return ogxSaturate(lerp(1.0, ao, params.strength)); // 按强度在无遮蔽与遮蔽之间插值。
}

// 历史法线与深度采样：四个角按法线、距离和双线性权重混合，返回未归一化的历史反弹。
float3 ogxGiHistorySample(float3 currNormal, float currDist, float3 cameraVelocity, float2 prevCoord, float renderScale,
    Sampler2D historyTexture, Sampler2D normalTexture, float2 screen_size, out float weightSum)
{
    float2 prevTexel = floor(prevCoord); // 历史纹素整数部分。
    float3 prevGi = float3(0.0); // 累积历史反弹。
    weightSum = 0.0; // 权重和。
    for (int k = 0; k < 4; k++) // 左下、右下、左上、右上四个历史纹素。
    {
        float2 sampleTexel = prevTexel + float2(float(k >> 1), float(k & 1)); // 按下标拼出四个角。
        float4 prevData = normalTexture.Load(int3(int2(sampleTexel.x + renderScale * screen_size.x, sampleTexel.y), 0)); // 读历史法线深度。
        float3 prevNormal = prevData.xyz * 2.0 - 1.0; // 还原历史法线。
        float normalWeight = float(dot(currNormal, prevNormal) > 0.5); // 法线相近才参与。
        float prevDist = prevData.a * 1000.0; // 历史距离。
        float depthWeight = max(abs(currDist - prevDist - cameraVelocity.z), 0.0); // 距离差。
        depthWeight = exp(-depthWeight / (currDist * 0.1 + 0.1)); // 差距越大权重越低。
        depthWeight = ogxSaturate(depthWeight * 2.0); // 放大后再收敛。
        float bilinearWeight = (1.0 - abs(prevCoord.x - sampleTexel.x)) * (1.0 - abs(prevCoord.y - sampleTexel.y)); // 双线性权重。
        bilinearWeight *= normalWeight * depthWeight; // 总权重。
        prevGi += ogxCurveToLinear3(historyTexture.Load(int3(int2(sampleTexel), 0)).rgb) * bilinearWeight; // 累加解码后的历史反弹。
        weightSum += bilinearWeight; // 累加权重。
    }
    return prevGi; // 交回加权历史反弹。
}

// 反射阴影图反弹：从阴影图里可见的表面取底色，按法线朝向与距离给当前点补一份光。
// `useSolidShadow` 对应支持遮挡贴图的显卡，`leakFix` 对应主世界的阳光泄漏修正，`underwater` 是眼睛在水下。

// iterationT 的 RSM 入口：先取时间蓝噪声，再把同一帧参数交给反弹主循环。
// 为什么单独一层：参考函数内部自己取蓝噪声，主循环把噪声当参数；严格对照需要把
// 这次采样放回函数体内，采样顺序才对得上。
float3 ogxRsmReference(float3 viewPos, float3 normal, OgxGiView view,
    Sampler2D shadowDepth0, Sampler2D shadowDepth1, Sampler2D shadowColor0, Sampler2D shadowColor1,
    float radius, int steps, float falloff, float shadowMapResolution, float shadowBias,
    Sampler2D noiseTexture, int2 texelCoord, int frame, bool useSolidShadow, bool leakFix, bool underwater)
{
    float2 noise = ogxBlueNoiseTemporal(noiseTexture, texelCoord, frame); // 参考实现的时间蓝噪声。
    return ogxGiRsm(viewPos, normal, view, shadowDepth0, shadowDepth1, shadowColor0, shadowColor1,
        radius, steps, falloff, shadowMapResolution, shadowBias, noise,
        useSolidShadow, leakFix, underwater); // 主循环原样转发。
}

// iterationT 的地平线遮蔽：每个切片向两侧各取若干深度样本，求最大地平角后积分。
// 为什么单独一份：现有 `ogxGroundTruthAo` 用参数结构体控制循环，严格对照无法把
// 切片数与每片步数折叠成参考的常数；这里把它们作为显式整数参数接收。
float ogxGtaoSlices(float3 viewPos, float3 viewDir, float3 normal, float2 coord,
    Sampler2D depthTexture, float4x4 projectionInverse, float aspect, float projectionScale,
    Sampler2D noiseTexture, int2 texelCoord, int frame, float2 taaJitter,
    int quality, int sliceQuality, float falloffStart, float maxSampleRadius,
    float worldRadius, float strength)
{
    float2 noise = ogxBlueNoiseTemporal(noiseTexture, texelCoord, frame); // 时间蓝噪声。
    float steps = float(quality); // 切片数。
    float rSteps = 1.0 / steps; // 切片倒数。
    float sliceSteps = float(sliceQuality); // 每片单侧步数。
    float rSliceSteps = 1.0 / sliceSteps; // 单侧步数倒数。
    float projFactor = 0.125 * projectionScale; // 投影缩放换成屏幕半径。
    float radius = worldRadius - viewPos.z * 0.01; // 世界半径随深度略减。
    float sampleRadiusRaw = radius * projFactor / -viewPos.z; // 原始屏幕半径。
    float sampleRadius = min(sampleRadiusRaw, maxSampleRadius); // 夹到上限。
    float falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
    float ao = 0.0; // 遮蔽累加。
    for (float i = 0.0; i < steps; i++) // 逐切片。
    {
        float sliceAngle = (i + noise.x) * rSteps * OGX_PI; // 切片方向。
        float3 sliceDir = float3(cos(sliceAngle), sin(sliceAngle), 0.0); // 平面方向。
        float3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 投影到视线垂直面。
        float3 axis = cross(sliceDir, viewDir); // 旋转轴。
        float3 projNormal = normal - dot(normal, axis) * axis; // 法线投影。
        float rProjNormalLength = rsqrt(dot(projNormal, projNormal)); // 投影法线长度倒数。
        float cosNormalAngle = ogxSaturate(dot(projNormal, viewDir) * rProjNormalLength); // 法线与视线夹角余弦。
        float normalAngle = sign(dot(orthoSliceDir, projNormal)) * ogxFastAcos(cosNormalAngle); // 法线角。
        float2 minCosHorizonAngle = cos(float2(normalAngle + OGX_HALF_PI, normalAngle - OGX_HALF_PI)); // 初始地平角。
        float2 maxCosHorizonAngle = minCosHorizonAngle; // 最大地平角。
        for (float j = 0.0; j < sliceSteps; j++) // 逐单侧步。
        {
            float stepNoise = (i + j * sliceSteps) * 0.61803399; // 黄金比步进。
            stepNoise = fract(stepNoise + noise.y); // 加噪声。
            float offset = (j + stepNoise) * rSliceSteps; // 归一化偏移。
            offset *= offset; // 平方让近处更密。
            float2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
            sampleOffset.y *= aspect; // 按宽高比修正。
            float2 sampleCoord = coord + sampleOffset; // 一侧样本。
            float sampleDepth = depthTexture.SampleLevel(sampleCoord, 0.0).x; // 读深度。
            float3 sampleVector = ogxGiViewPos(sampleCoord - taaJitter * 0.5, sampleDepth, projectionInverse) - viewPos; // 样本视空间位置，先撤销抖动。
            float rSampleDist = rsqrt(dot(sampleVector, sampleVector)); // 距离倒数。
            float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 地平角余弦。
            float falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 距离衰减。
            cosHorizonAngle = lerp(cosHorizonAngle, minCosHorizonAngle.x, falloffWeight); // 混向初始角。
            maxCosHorizonAngle.x = max(cosHorizonAngle, maxCosHorizonAngle.x); // 取更大的一侧。
            sampleCoord = coord - sampleOffset; // 另一侧样本。
            sampleDepth = depthTexture.SampleLevel(sampleCoord, 0.0).x; // 读深度。
            sampleVector = ogxGiViewPos(sampleCoord - taaJitter * 0.5, sampleDepth, projectionInverse) - viewPos; // 样本视空间位置，先撤销抖动。
            rSampleDist = rsqrt(dot(sampleVector, sampleVector)); // 距离倒数。
            cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 地平角余弦。
            falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 距离衰减。
            cosHorizonAngle = lerp(cosHorizonAngle, minCosHorizonAngle.y, falloffWeight); // 混向初始角。
            maxCosHorizonAngle.y = max(cosHorizonAngle, maxCosHorizonAngle.y); // 取更大的一侧。
        }
        maxCosHorizonAngle = float2(-ogxFastAcos(maxCosHorizonAngle.y), ogxFastAcos(maxCosHorizonAngle.x)) * 2.0; // 转成角度。
        // 与上面的地平线遮蔽共用同一份完整角积分，常数与参考算式一致。
        float horizonAngleIntegra = ogxGtaoHorizonGap(maxCosHorizonAngle, normalAngle, cosNormalAngle);
        ao += horizonAngleIntegra / rProjNormalLength; // 累加。
    }
    ao *= 0.25 * rSteps; // 平均。
    return ogxSaturate(lerp(1.0, ao, strength)); // 按强度混向全亮。
}
