/*
全局光子文件：七乘七空间滤波与参考签名版降噪。
调用位置：由 `gi/gi.slang` 内联，全局光在时间累积之后调用空间滤波。
可复制示例：`vec3 c = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);`
设计原因与取舍：邻域偏移显式列出，权重按法线与深度筛选；边界夹紧与参考实现一致。
*/
// 七乘七邻域偏移按行列下标现算：x 从负三到三，y 同样，按行优先排列。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
// 空间滤波为什么按法线与深度拒绝样本：全局光是低频信号，但几何边缘不是；
// 不拒绝会把前景的亮色抹到背景，出现一圈光晕。
// 七乘七核已经够大，再大只会增加成本；时间滤波负责补剩下的噪声。
// 权重用平方反比，近处样本话语权更高，远处只做平滑补充。
float3 ogxGiSpatialFilter(float2 coord, float dist, float3 normal, float3 viewDir, OgxGiView view, Sampler2D historyTexture, float renderScale) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float2 local = coord * renderScale; // 全局光分辨率下的坐标。
    float weights = 0.0; // 权重和。
    float3 gi = float3(0.0); // 累积的反弹颜色。
    float clampedDist = min(dist, 1000.0); // 距离限长。
    float b = clampedDist * 0.001 + 0.025; // 深度阈值里的中间量。
    float depthThreshold = min(0.1 + clampedDist * 0.05, 1.1) + ogxSaturate(1.0 - abs(dot(normal, viewDir)) / b) * 10.0; // 掠射角放宽深度阈值。
    float2 border = float2(renderScale) - view.texel_size * 2.0; // 边界。
    float2 offsetScale = view.texel_size * 4.0 * renderScale; // 邻域步长。
    // 七乘七偏移表与参考实现的数组逐项相同；显式列出而不是现算，常数集合才能逐项核对。
    float2 offsets[49]; // 四十九个空间采样偏移，覆盖七乘七邻域。
    offsets[0] = float2(-3.0, -3.0); // 当前步骤的中间量。
    offsets[1] = float2(-2.0, -3.0); // 当前步骤的中间量。
    offsets[2] = float2(-1.0, -3.0); // 当前步骤的中间量。
    offsets[3] = float2(0.0, -3.0); // 当前步骤的中间量。
    offsets[4] = float2(1.0, -3.0); // 当前步骤的中间量。
    offsets[5] = float2(2.0, -3.0); // 当前步骤的中间量。
    offsets[6] = float2(3.0, -3.0); // 当前步骤的中间量。
    offsets[7] = float2(-3.0, -2.0); // 当前步骤的中间量。
    offsets[8] = float2(-2.0, -2.0); // 当前步骤的中间量。
    offsets[9] = float2(-1.0, -2.0); // 当前步骤的中间量。
    offsets[10] = float2(0.0, -2.0); // 当前步骤的中间量。
    offsets[11] = float2(1.0, -2.0); // 当前步骤的中间量。
    offsets[12] = float2(2.0, -2.0); // 当前步骤的中间量。
    offsets[13] = float2(3.0, -2.0); // 当前步骤的中间量。
    offsets[14] = float2(-3.0, -1.0); // 当前步骤的中间量。
    offsets[15] = float2(-2.0, -1.0);
    offsets[16] = float2(-1.0, -1.0);
    offsets[17] = float2(0.0, -1.0);
    offsets[18] = float2(1.0, -1.0);
    offsets[19] = float2(2.0, -1.0);
    offsets[20] = float2(3.0, -1.0);
    offsets[21] = float2(-3.0, 0.0);
    offsets[22] = float2(-2.0, 0.0);
    offsets[23] = float2(-1.0, 0.0);
    offsets[24] = float2(0.0, 0.0);
    offsets[25] = float2(1.0, 0.0);
    offsets[26] = float2(2.0, 0.0);
    offsets[27] = float2(3.0, 0.0);
    offsets[28] = float2(-3.0, 1.0);
    offsets[29] = float2(-2.0, 1.0);
    offsets[30] = float2(-1.0, 1.0);
    offsets[31] = float2(0.0, 1.0);
    offsets[32] = float2(1.0, 1.0);
    offsets[33] = float2(2.0, 1.0);
    offsets[34] = float2(3.0, 1.0);
    offsets[35] = float2(-3.0, 2.0);
    offsets[36] = float2(-2.0, 2.0);
    offsets[37] = float2(-1.0, 2.0);
    offsets[38] = float2(0.0, 2.0);
    offsets[39] = float2(1.0, 2.0);
    offsets[40] = float2(2.0, 2.0);
    offsets[41] = float2(3.0, 2.0);
    offsets[42] = float2(-3.0, 3.0);
    offsets[43] = float2(-2.0, 3.0);
    offsets[44] = float2(-1.0, 3.0);
    offsets[45] = float2(0.0, 3.0);
    offsets[46] = float2(1.0, 3.0);
    offsets[47] = float2(2.0, 3.0);
    offsets[48] = float2(3.0, 3.0);
    for (int i = 0; i < 49; i++) // 遍历四十九个邻点。
    {
        float2 sampleCoord = clamp(local + offsets[i] * offsetScale, float2(0.0), border); // 采样坐标。
        float weight = length(offsets[i]); // 按到中心的距离算权重。
        weight = exp2(-weight * weight * 0.1); // 高斯权重。
        float4 sampleData = historyTexture.SampleLevel(sampleCoord + float2(renderScale, 0.0), 0.0); // 读历史法线深度。
        float3 sampleNormal = sampleData.xyz * 2.0 - 1.0; // 还原法线。
        float normalWeight = abs(dot(normal, sampleNormal)); // 法线相近度。
        normalWeight = pow(normalWeight, 64.0); // 高次方只保留很接近的。
        float depthWeight = ogxSaturate(-abs(sampleData.w * 1000.0 - clampedDist) + depthThreshold); // 深度相近度。
        weight = weight * normalWeight * depthWeight + 1e-20; // 总权重，加极小值避免全零。
        gi += ogxCurveToLinear3(historyTexture.SampleLevel(sampleCoord, 0.0).rgb) * weight; // 累加解码后的反弹。
        weights += weight; // 累加权重。
    }
    return ogxLinearToCurve3(gi / weights); // 平均后编码返回。
}

// iterationT 空间滤波入口：参考签名把距离、法线和视线方向放在前面，坐标与历史图由宿主提供。
// 只是为了保持参考参数顺序，算式仍走同一份七乘七循环。
float3 ogxGiSpatialFilterReference(float dist, float3 normal, float3 viewDir, float2 coord,
    OgxGiView view, Sampler2D historyTexture, float renderScale)
{
    return ogxGiSpatialFilter(coord, dist, normal, viewDir, view, historyTexture, renderScale);
}
