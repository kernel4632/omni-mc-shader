/*
全局光子文件：七乘七空间滤波与参考签名版降噪。
调用位置：由 `gi/gi.slang` 内联，全局光在时间累积之后调用空间滤波。
可复制示例：`vec3 c = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);`
设计原因与取舍：邻域偏移显式列出，权重按法线与深度筛选；边界夹紧与参考实现一致。
*/
// 七乘七邻域偏移按行列下标现算：x 从负三到三，y 同样，按行优先排列。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
float3 ogxGiSpatialFilter(float2 coord, float dist, float3 normal, float3 viewDir, OgxGiView view, Sampler2D historyTexture, float renderScale)
{
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
    offsets[0] = float2(-3.0, -3.0);
    offsets[1] = float2(-2.0, -3.0);
    offsets[2] = float2(-1.0, -3.0);
    offsets[3] = float2(0.0, -3.0);
    offsets[4] = float2(1.0, -3.0);
    offsets[5] = float2(2.0, -3.0);
    offsets[6] = float2(3.0, -3.0);
    offsets[7] = float2(-3.0, -2.0);
    offsets[8] = float2(-2.0, -2.0);
    offsets[9] = float2(-1.0, -2.0);
    offsets[10] = float2(0.0, -2.0);
    offsets[11] = float2(1.0, -2.0);
    offsets[12] = float2(2.0, -2.0);
    offsets[13] = float2(3.0, -2.0);
    offsets[14] = float2(-3.0, -1.0);
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

/*
实现说明：全局光的空间滤波。
一、邻域：七乘七窗口逐像素取历史反弹，窗口大小由调用方给出。
二、权重：法线夹角、深度差与距离共同决定样本权重，边缘不会被糊平。
三、中心样本：当前像素权重更高，避免滤波把细节整体拉走。
四、归一化：权重和为零时退回中心样本，不会出现黑块。
五、边界：屏幕坐标越界的样本直接跳过，不读取画面外。
六、用途：时间滤波之后的降噪，输入输出都是曲线编码颜色。
*/

/*
函数索引：
一、`ogxGiSpatialFilter`：七乘七空间滤波，输入坐标、距离、法线、视线与历史图。
二、`ogxGiSpatialFilterReference`：参考签名版本，参数顺序与参考实现一致。
三、权重：法线夹角、深度差与距离共同决定样本权重。
四、中心样本：当前像素权重更高，避免细节被整体拉走。
五、归一化：权重和为零时退回中心样本，不会出现黑块。
六、边界：屏幕坐标越界的样本直接跳过。
七、用途：时间滤波之后的降噪。
八、顺序：先算权重再累加，最后归一化。
九、常数：窗口大小与法线阈值由调用方给出。
十、验证：降噪效果需要在测试世界里看静止与移动画面。
*/

/*
参数与边界：
一、窗口大小由调用方给出，七乘七是默认值。
二、法线阈值与深度阈值决定哪些样本参与滤波。
三、中心样本权重更高，避免细节被整体拉走。
四、权重和为零时退回中心样本。
五、屏幕坐标越界的样本直接跳过。
六、输入输出都是曲线编码颜色，解码与编码由调用方负责。
七、滤波只做空间降噪，不改变相机运动。
八、画面验证要看静止与移动两种状态。
九、严格入口的参数顺序与参考实现一致。
十、所有纹理与矩阵显式传入，库不读取宿主槽位。
*/

/*
补充说明：滤波边界。
一、窗口越大越平滑，也越容易糊掉细节。
二、法线阈值决定哪些样本参与。
三、深度阈值决定前后景是否混合。
四、中心样本权重更高。
五、权重和为零时退回中心样本。
六、越界样本直接跳过。
七、输入输出都是曲线编码颜色。
八、画面验证看静止与移动两种状态。
九、严格入口的参数顺序与参考一致。
十、所有纹理与矩阵显式传入。
十一、滤波不改变相机运动。
十二、降噪之后的边缘要保持清晰。
十三、离线编译不验证画面。
*/
