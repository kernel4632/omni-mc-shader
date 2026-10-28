// 读一个坐标的米制深度；`useDh` 为真且近景没有几何时改读远景深度，再统一到近景尺度。
// 为什么把下限夹在换米制之前：近处深度趋近于零时薄透镜公式会爆炸，先夹屏幕深度最稳。
float ogxDofLinearDepth(float2 coord, Sampler2D depthTexture, Sampler2D dhDepthTexture, float4x4 projectionInverse,
    float4x4 dhProjectionInverse, bool useDh)
{
    float depth = depthTexture.SampleLevel(coord, 0.0).x; // 读含半透明的近景深度。
    if (useDh && depth == 1.0) // 只有启用远景且近景是天空时才改读远景。
    {
        float dhDepth = dhDepthTexture.SampleLevel(coord, 0.0).x; // 读远景深度。
        float meters = 1.0 / ((dhDepth * 2.0 - 1.0) * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景深度换米制。
        depth = (1.0 / meters - projectionInverse[3][3]) / projectionInverse[2][3]; // 米制换到近景投影的负一到一深度。
        depth = clamp(depth * 0.5 + 0.5, 0.0, 1.0); // 转回零到一并夹紧。
    }
    depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
    return 1.0 / ((depth * 2.0 - 1.0) * projectionInverse[2][3] + projectionInverse[3][3]); // 换成米制距离。
}

// 前景弥散范围：在螺旋上找更近且弥散更大的样本，把它们的弥散并进当前点。
// 输入是当前点、焦距、模糊量、投影缩放、镜头倍数、最大弥散、画面比例与搜索次数；输出归一化弥散范围。
float ogxDofCocSpread(float2 coord, Sampler2D depthTexture, Sampler2D dhDepthTexture, float4x4 projectionInverse,
    float4x4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale, float lensFactor,
    float maxCoc, float aspect, int steps, float2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数：模糊量乘投影缩放与镜头倍数。
    float rMaxCoc = 1.0 / maxCoc; // 最大弥散的倒数，用来归一化。
    float rAspect = 1.0 / aspect; // 宽高比倒数，让椭圆散景在像素上是圆的。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点米制深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散半径。
    float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
    startRadius *= startRadius; // 平方，让搜索从中心附近开始。
    float spreadCoc = currCoc; // 弥散范围初值为当前点。
    float rSteps = 1.0 / float(steps); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角由噪声给出，避免固定图案。
    float2 rot = float2(cos(angle), sin(angle)); // 起始方向。
    float2 golden = float2(cos(OGX_GOLDEN_ANGLE), sin(OGX_GOLDEN_ANGLE)); // 黄金角旋转，和参考宏同值。
    for (int i = 0; i < steps; i++) // 螺旋逐点搜索。
    {
        rot = float2(golden.x * rot.x + golden.y * rot.y, -golden.y * rot.x + golden.x * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt(startRadius + (float(i) + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
        float2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        sampleOffset.x *= rAspect; // 按宽高比修正成圆。
        float sampleDepth = ogxDofLinearDepth(coord + sampleOffset, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        if (sampleCoc >= sampleRadius && sampleDepth <= currDepth) // 更近且弥散够大才并进来。
        {
            spreadCoc = max(spreadCoc, sampleCoc);
        }
    }
    return min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
}

// iterationT 的弥散圆扩散：先取时间蓝噪声，再读当前深度与对焦距离，最后做十步螺旋搜索。
// 为什么单独一份：`ogxDofCocSpread` 把对焦距离与噪声都当参数，严格对照需要把
// 参考实现内部的那两次采样和固定统计像素显式接回来。
float ogxItxDofCocSpread(float2 coord, Sampler2D depthTexture, Sampler2D dhDepthTexture,
    Sampler2D focusTexture, Sampler2D noiseTexture, float4x4 projectionInverse,
    float4x4 dhProjectionInverse, int2 screenExtent, int2 texelCoord, int frame,
    int focusMode, float focalPoint, bool useDh, float blur, float projectionScale,
    float maxCoc, float aspect, int steps)
{
    float2 noise = ogxBlueNoiseTemporal(noiseTexture, texelCoord, frame); // 参考实现的时间蓝噪声。
    float cocRadiusfactor = blur * projectionScale; // 弥散半径系数。
    float rMaxCoc = 1.0 / maxCoc; // 最大弥散倒数。
    float rAspect = 1.0 / aspect; // 宽高比倒数。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse,
        dhProjectionInverse, useDh); // 当前米制深度。
    float focus; // 对焦距离。
    if (focusMode == 0) // 自动对焦：读统计缓冲左下角的固定像素。
    {
        float4 stat = focusTexture.Load(int3(int2(60, screenExtent.y - 1), 0));
        focus = ogxShadowLinearDepth(stat.a * 0.125 + 0.875, projectionInverse);
    }
    else // 手动对焦直接使用调用方给的距离。
    {
        focus = focalPoint;
    }
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前弥散。
    float startRadius = currCoc * rMaxCoc; // 起始半径比例。
    startRadius *= startRadius; // 平方后从中心附近起步。
    float spreadCoc = currCoc; // 弥散范围初值。
    float rSteps = 1.0 / float(steps); // 步数倒数。
    float2 golden = float2(cos(OGX_GOLDEN_ANGLE), sin(OGX_GOLDEN_ANGLE)); // 黄金角旋转。
    float angle = noise.x * 6.28318530718; // 起始角。
    float2 rot = float2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < steps; i++) // 十步螺旋搜索。
    {
        rot = float2(golden.x * rot.x + golden.y * rot.y,
                     -golden.y * rot.x + golden.x * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt(startRadius + (float(i) + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 样本半径。
        float2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        sampleOffset.x *= rAspect; // 修正成圆形散景。
        float sampleDepth = ogxDofLinearDepth(coord + sampleOffset, depthTexture, dhDepthTexture,
            projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        if (sampleCoc >= sampleRadius && sampleDepth <= currDepth) // 更近且够大才并进来。
        {
            spreadCoc = max(spreadCoc, sampleCoc);
        }
    }
    return min(spreadCoc, maxCoc) * rMaxCoc; // 归一化结果。
}

// iterationT 的景深主循环：先取蓝噪声、当前深度与对焦距离，再按十步螺旋混合前景与背景。
// 为什么单独一份：合并版支持猫眼、色散与下界深度打包，默认路径的采样顺序和参考不同；
// 严格对照只走参考的主世界分支。
float4 ogxItxDof(float2 coord, Sampler2D colorTexture, Sampler2D depthTexture,
    Sampler2D dhDepthTexture, Sampler2D focusTexture, Sampler2D noiseTexture,
    float4x4 projectionInverse, float4x4 dhProjectionInverse, int2 screenExtent,
    int2 texelCoord, int frame, int focusMode, float focalPoint, bool useDh, float blur,
    float projectionScale, float maxCoc, float2 pixelSize, float aspect, int quality)
{
    float2 noise = ogxBlueNoiseTemporal(noiseTexture, texelCoord, frame); // 参考实现的时间蓝噪声。
    float cocRadiusfactor = blur * projectionScale; // 弥散半径系数。
    float minCoc = 0.5641895835 * pixelSize.y; // 最小弥散，避免采样半径缩到零。
    float rAspect = 1.0 / aspect; // 宽高比倒数。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse,
        dhProjectionInverse, useDh); // 当前米制深度。
    float focus; // 对焦距离。
    if (focusMode == 0) // 自动对焦。
    {
        float4 stat = focusTexture.Load(int3(int2(60, screenExtent.y - 1), 0));
        focus = ogxShadowLinearDepth(stat.a * 0.125 + 0.875, projectionInverse);
    }
    else // 手动对焦。
    {
        focus = focalPoint;
    }
    float currCoc = clamp(ogxCocRadius(focus, currDepth, cocRadiusfactor), minCoc, maxCoc); // 当前弥散。
    float4 currData = colorTexture.SampleLevel(coord, 0.0); // 当前颜色与已存弥散。
    float spreadCoc = currData.a * maxCoc; // 本像素散射范围。
    float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重。
    centerWeight = lerp(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 前景越近中心权重越小。
    float3 dof = float3(0.0); // 背景颜色累加。
    float weights = 0.0; // 背景权重。
    float3 selfColor = ogxCurveToLinear3(currData.rgb) * 1e-20; // 当前点自计入。
    float selfSamples = 1e-20; // 自样本数。
    float selfWeights = 0.0; // 自权重。
    float rSteps = 1.0 / float(quality); // 步数倒数。
    float firstStepRadius = sqrt(rSteps); // 参考实现保留的首步半径声明。
    float2 golden = float2(cos(OGX_GOLDEN_ANGLE), sin(OGX_GOLDEN_ANGLE)); // 黄金角旋转。
    float angle = noise.x * 6.28318530718; // 起始角。
    float2 rot = float2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < quality; i++) // 十步螺旋采样。
    {
        rot = float2(golden.x * rot.x + golden.y * rot.y,
                     -golden.y * rot.x + golden.x * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt((float(i) + noise.y) * rSteps) * spreadCoc; // 样本半径。
        float2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        sampleOffset.x *= rAspect; // 修正成圆形散景。
        float2 sampleCoord = coord + sampleOffset; // 样本坐标。
        float sampleDepth = ogxDofLinearDepth(sampleCoord, depthTexture, dhDepthTexture,
            projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = clamp(ogxCocRadius(focus, sampleDepth, cocRadiusfactor), minCoc, maxCoc); // 样本弥散。
        float3 sampleColor = ogxCurveToLinear3(colorTexture.SampleLevel(sampleCoord, 0.0).rgb); // 样本颜色。
        if (currCoc >= sampleRadius && sampleDepth >= currDepth) // 当前点本身盖住样本。
        {
            selfColor += sampleColor;
            selfSamples += 1.0;
        }
        else if (sampleCoc >= sampleRadius && sampleDepth < currDepth) // 更近的样本散过来。
        {
            float sampleWeight = max(1.0, currCoc / sampleCoc);
            sampleWeight *= sampleWeight;
            dof += sampleColor * sampleWeight;
            weights += sampleWeight;
        }
        else // 更远且不够大的样本只增加自权重。
        {
            selfWeights += centerWeight;
        }
    }
    dof += selfColor * (1.0 + selfWeights / selfSamples); // 自样本补回。
    dof /= weights + selfSamples + selfWeights; // 归一化。
    return float4(ogxLinearToCurve3(dof), 0.0); // 回到曲线编码。
}

// 景深散焦：按存下来的弥散范围在螺旋上取样，让更近且弥散够大的样本散到当前像素上。
// `storeDepth` 为真时把散焦后的深度一起写进透明度，供下界历史使用；屏幕深度由调用方投影矩阵换算。
float4 ogxDepthOfField(float2 coord, Sampler2D colorTexture, Sampler2D depthTexture, Sampler2D dhDepthTexture,
    float4x4 projectionInverse, float4x4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale,
    float lensFactor, float maxCoc, float2 texel, float aspect, int quality, bool catEye, float catEyeMidpoint,
    float catEyeStrength, float anamorphic, float dispersion, bool storeDepth, float2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数，与弥散统计共用同一换算。
    float minCoc = 0.5641895835 * texel.y; // 一个像素大小的最小弥散，避免零半径时除零。
    float rAspect = 1.0 / aspect; // 宽高比倒数。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
    currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
    float4 currData = colorTexture.SampleLevel(coord, 0.0); // 当前点的曲线编码颜色与弥散范围。
    float spreadCoc = currData.a * maxCoc; // 把存下来的范围还原成半径。
    float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
    centerWeight = lerp(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点很清晰时把它自己压到极小。
    float2 catEyeOffset = float2(0.0); // 猫眼裁剪半径；关闭时保持零。
    if (catEye) // 只有开启猫眼效应才算裁剪。
    {
        catEyeOffset = coord * 2.0 - 1.0; // 从中心指向当前点。
        catEyeOffset.x *= aspect; // 按宽高比修正成圆。
        float catEyeDist = length(catEyeOffset); // 到中心的距离。
        catEyeDist = max(catEyeDist - catEyeMidpoint, 0.0); // 超过中点才开始裁剪。
        catEyeDist *= spreadCoc * catEyeStrength; // 按弥散与强度缩放。
        catEyeOffset = normalize(catEyeOffset) * catEyeDist; // 得到裁剪半径。
    }
    float3 dof = float3(0.0); // 散焦进来的颜色累加。
    float weights = 0.0; // 样本权重累加。
    float3 selfColor = ogxCurveToLinear3(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
    float selfSamples = 1e-20; // 自计入样本数初值极小。
    float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
    float blendedDepth = 0.0; // 散焦后的深度累加。
    float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
    float rSteps = 1.0 / float(quality); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角。
    float2 rot = float2(cos(angle), sin(angle)); // 起始方向。
    float2 golden = float2(cos(OGX_GOLDEN_ANGLE), sin(OGX_GOLDEN_ANGLE)); // 黄金角旋转，和参考宏同值。
    for (int i = 0; i < quality; i++) // 螺旋采样。
    {
        rot = float2(golden.x * rot.x + golden.y * rot.y, -golden.y * rot.x + golden.x * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt((float(i) + noise.y) * rSteps) * spreadCoc; // 样本半径。
        float2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        if (catEye && distance(catEyeOffset, sampleOffset) > spreadCoc) // 超出猫眼裁剪半径就不采。
        {
            continue;
        }
        sampleOffset.x *= rAspect * anamorphic; // 按宽高比修正后再按变形比横向拉伸。
        float2 sampleCoord = coord + sampleOffset; // 样本坐标。
        float sampleDepth = ogxDofLinearDepth(sampleCoord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        sampleCoc = clamp(sampleCoc, minCoc, maxCoc); // 夹到范围。
        float3 sampleColor; // 样本线性颜色。
        if (dispersion != 1.0) // 色散开启时红蓝通道沿到中心的方向错开。
        {
            float2 dispersionOffset = (coord - 0.5) * sampleRadius * (dispersion - 1.0); // 错开量随半径与到中心距离增大。
            sampleColor.r = ogxCurveToLinear(colorTexture.SampleLevel(sampleCoord + dispersionOffset, 0.0).r); // 红通道向外。
            sampleColor.g = ogxCurveToLinear(colorTexture.SampleLevel(sampleCoord, 0.0).g); // 绿通道不动。
            sampleColor.b = ogxCurveToLinear(colorTexture.SampleLevel(sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内。
        }
        else // 默认无色散只取一次样本。
        {
            sampleColor = ogxCurveToLinear3(colorTexture.SampleLevel(sampleCoord, 0.0).rgb); // 样本线性颜色。
        }
        float sampleWeight = max(1.0, currCoc / sampleCoc); // 近处前方样本权重更高。
        sampleWeight *= sampleWeight; // 平方加强。
        bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
        bool isBlurredSample = sampleCoc >= sampleRadius && sampleDepth < currDepth; // 更近且弥散够大，散焦进来。
        if (isSelfSample) // 属于当前点自己。
        {
            selfColor += sampleColor; // 记为自贡献。
            selfSamples += 1.0; // 自贡献样本数。
        }
        else if (isBlurredSample) // 散焦进来。
        {
            dof += sampleColor * sampleWeight; // 累加散焦颜色。
            weights += sampleWeight; // 累加权重。
        }
        else // 不满足条件，记进中心权重。
        {
            selfWeights += centerWeight; // 累加中心权重。
        }
        if (isSelfSample) // 自己的样本累加深度。
        {
            selfDepth += sampleDepth;
        }
        else if (isBlurredSample) // 散焦样本按权重累加深度。
        {
            blendedDepth += sampleDepth * sampleWeight;
        }
    }
    dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
    dof /= weights + selfSamples + selfWeights; // 归一化。
    if (!storeDepth) // 主世界与末地不写深度。
    {
        return float4(ogxLinearToCurve3(dof), 0.0);
    }
    blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 下界把深度按同一套补偿。
    blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
    return float4(ogxLinearToCurve3(dof), ogxScreenDepthFromLinearDepth(blendedDepth, projectionInverse)); // 返回颜色与换回的屏幕深度。
}
