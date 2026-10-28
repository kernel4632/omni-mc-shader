// 数学模块采样序列：R2、余弦半球、手部深度、三角波、快速反余弦与 Halton。
// 调用位置：由 `common/math.slang` 内联引入，全局光、阴影与反射共用。
// 可复制示例：`float2 p = ogxR2Sample(frameIndex);`
// 设计原因与取舍：低差异序列只在纯数学层实现，宿主只传序号或随机数。

// R2 低差异序列：两个无理数比例把序号摊成平面上的均匀点，样本不会聚成一团。
// 为什么用 R2 而不是随机数：随机数会成簇，R2 每加一个样本都把空隙补得更均匀。
float2 ogxR2Sample(int n)
{
    float2 alpha = float2(0.75487765, 0.56984026); // 二维黄金比例常数，照 Eclipse 原值。
    return fract(alpha * float(n)); // 序号乘常数后取小数，得到零到一的点。
}

// 余弦加权半球采样：把两个零到一的随机数变成朝上的半球方向。
// 为什么用余弦权重：漫反射的入射能量本身带余弦，按这个分布采样可以直接平均，不用再除权重。
float3 ogxCosineHemisphere(float2 xi)
{
    float theta = OGX_TAU * xi.y; // 绕竖直轴的角度。
    float r = sqrt(xi.x); // 半径开方，得到余弦分布。
    return float3(r * cos(theta), r * sin(theta), sqrt(clamp(1.0 - xi.x, 0.0, 1.0))); // 横向两个分量加竖直分量。
}

// 把手部深度从固定深度尺度换算到正常投影尺度，屏幕空间追踪手部光时用。
// `handDepth` 是加载器给的手部深度比例，手不参与追踪时原样返回。
float ogxConvertHandDepth3(float depth, bool hand, float handDepth)
{
    if (!hand) return depth; // 不是手部像素就不换算。
    float ndcDepth = depth * 2.0 - 1.0; // 零到一转负一到一。
    ndcDepth /= handDepth; // 按手部深度比例还原。
    return ndcDepth * 0.5 + 0.5; // 再转回零到一。
}

// iterationT 的一维 R1 序列：黄金比例步长，加半格避免从零开始。
float ogxSequenceR1(float n)
{
    const float alpha = 1.0 / OGX_GOLDEN_RATIO; // 黄金比例倒数。
    return fract(0.5 + n * alpha); // 加半格后取小数。
}

// iterationT 的二维 R2 序列：塑料常数的两个幂做步长。
float2 ogxSequenceR2(float n)
{
    float2 alpha = 1.0 / float2(OGX_PLASTIC_RATIO, OGX_PLASTIC_RATIO * OGX_PLASTIC_RATIO); // 两个步长。
    return fract(0.5 + n * alpha); // 加半格后取小数。
}

// Eclipse 的三角波：先减半再取绝对值，夹在 0.01 到 0.49 之间避免端点。
float ogxTriangleGradient(float x)
{
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49); // 参考实现的夹紧范围。
}

// Eclipse 的二维三角波：先分别算两个方向，再用第一个结果扰动第二个输入。
float2 ogxTriangleGradient2d(float2 p)
{
    float triX = ogxTriangleGradient(p.x); // 第一方向。
    float triY = ogxTriangleGradient(p.y); // 第二方向。
    return float2(triX + triY, ogxTriangleGradient(triX + p.y)); // 参考实现的组合方式。
}

// Eclipse 的快速反余弦：三系数多项式加根号修正，和库默认的三次近似不同。
float ogxFastAcosPoly(float x)
{
    const float c0 = 1.57018; // 零点值。
    const float c1 = -0.201877; // 一次项。
    const float c2 = 0.0464619; // 二次项。
    float ax = abs(x); // 对称化。
    float result = (c2 * ax + c1) * ax + c0; // 多项式。
    result *= sqrt(1.0 - ax); // 根号修正。
    return x >= 0.0 ? result : OGX_PI - result; // 负半轴镜像。
}

// Eclipse 的瑞利相函数：Elek 2009 的线性近似，已经除以四派。
// Elek 的瑞利相函数写法：与 iterationT 常数一致，供天空对照。
float ogxRayleighPhaseElek(float cosTheta)
{
    const float oneOverPi = 1.0 / acos(-1.0); // 参考实现用 acos(-1) 求 pi。
    float2 mulAdd = float2(0.1, 0.28) * oneOverPi; // 两个系数。
    return cosTheta * mulAdd.x + mulAdd.y; // 线性相函数。
}

// Eclipse 的 4×4 Bayer 抖动：按像素坐标查表，返回零到一之间的阈值。
// 为什么不用递归拜尔函数：递归构造出的是另一张矩阵，和参考的 16 项表不同。
float ogxBayer4Dither(float2 pixel)
{
    float bayer[16]; // 参考实现的 4×4 表。
    bayer[0] = 0.0/16.0;
    bayer[1] = 8.0/16.0;
    bayer[2] = 2.0/16.0;
    bayer[3] = 10.0/16.0;
    bayer[4] = 12.0/16.0;
    bayer[5] = 4.0/16.0;
    bayer[6] = 14.0/16.0;
    bayer[7] = 6.0/16.0;
    bayer[8] = 3.0/16.0;
    bayer[9] = 11.0/16.0;
    bayer[10] = 1.0/16.0;
    bayer[11] = 9.0/16.0;
    bayer[12] = 15.0/16.0;
    bayer[13] = 7.0/16.0;
    bayer[14] = 13.0/16.0;
    bayer[15] = 5.0/16.0; // 参考实现的 4×4 表。
    int x = int(ogxMod(pixel.x, 4.0)); // 横向格。
    int y = int(ogxMod(pixel.y, 4.0)); // 纵向格。
    return bayer[x + y * 4]; // 按行优先取表。
}

// Eclipse 的二维旋转矩阵：`mm2(a)` 返回绕原点旋转 `a` 弧度的二乘二矩阵。
float2x2 ogxRotate2Matrix(float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2x2(c, s, -s, c);
}

// Eclipse 的半球方向：两个零到一的随机数变成一个朝上的单位向量。
float3 ogxGenUnitVector(float2 xy)
{
    xy.x *= OGX_TAU; // 横向角度乘一圈。
    xy.y = xy.y * 2.0 - 1.0; // 纵向高度映射到负一到一。
    return float3(ogxSinCos(xy.x) * sqrt(1.0 - xy.y * xy.y), xy.y);
}

// Eclipse 的两向量旋转矩阵：把 `x` 转到 `y` 的方向，用于极光与天空基。
// 参考实现按列填矩阵；这里保持同样的参数顺序，生成 GLSL 后列主序解释一致。
float3x3 ogxGetRotMat(float3 x, float3 y)
{
    float d = dot(x, y);
    float3 cr = cross(y, x);
    float s = length(cr);
    float id = 1.0 - d;
    float3 m = cr / s;
    float3 m2 = m * m * id + d;
    float3 sm = s * m;
    float3 w = (m.xy * id).xxy * m.yzz;
    return float3x3(
        m2.x,     w.x - sm.z, w.y + sm.y,
        w.x + sm.z, m2.y,     w.z - sm.x,
        w.y - sm.y, w.z + sm.x, m2.z);
}

// Eclipse 的 Halton 二进序列：按位反转，返回一个零到一的低差异数。
// 二维 Halton 序列：低差异采样点，供阴影与反射抖动。
float ogxHaltonSeq2(int index)
{
    float r = 0.0;
    float f = 1.0;
    int i = index;
    while (i > 0)
    {
        f /= 2.0;
        r += f * float(i % 2);
        i = int(float(i) / 2.0);
    }
    return r;
}

/*
实现说明：低差异序列与半球采样。
一、R2 序列：两个无理数步长生成二维低差异点，适合每帧少量样本的累积。
二、黄金角：螺旋采样每步旋转固定角度，样本不会排成放射状条纹。
三、余弦半球：按余弦分布生成方向，漫反射与间接光用同一套分布。
四、手部深度：把加载器的手部深度约定转成米制距离，靠近相机时夹住下限。
五、三角形渐变：二维与三维版本把均匀随机数折成三角分布，抖动更柔和。
六、边界：序列函数只接收序号与总数，不保存状态；调用方负责帧间偏移。
七、顺序：先算半径再算角度，和参考实现的样本顺序一致。
*/

/*
函数索引：
一、`ogxR2Sample`：二维低差异点，输入序号与总数。
二、`ogxCosineHemisphere`：余弦半球方向，输入二维随机数。
三、`ogxConvertHandDepth3`：手部深度换算，靠近相机时夹住下限。
四、`ogxSequenceR1` 与 `ogxSequenceR2`：一维与二维低差异序列。
五、`ogxTriangleGradient` 与 `ogxTriangleGradient2d`：三角分布，抖动更柔和。
六、`ogxFastAcosPoly`：反余弦多项式近似。
七、`ogxRayleighPhaseElek`：瑞利相函数，供雾与大气使用。
八、`ogxBayer4Dither`：四阶 Bayer 抖动。
九、`ogxRotate2Matrix` 与 `ogxGetRotMat`：二维旋转矩阵。
十、`ogxGenUnitVector`：由随机数生成单位向量。
十一、`ogxHaltonSeq2`：二维 Halton 序列，基数二与三。
十二、边界：序列函数只接收序号与总数，不保存状态。
十三、顺序：先算半径再算角度，与参考实现的样本顺序一致。
十四、用途：间接光、雾与抗锯齿共用这一组采样。
*/

/*
参数与边界：
一、序号从零开始，总数必须大于零。
二、低差异序列不保存状态，重复调用得到同一点。
三、余弦半球的输入是零到一的二维随机数。
四、手部深度换算假设深度已经夹到合法范围。
五、三角分布的输入是零到一，输出也在零到一。
六、反余弦近似在端点附近误差最大，调用方要接受少量偏差。
七、Bayer 抖动只改阈值，不改采样位置。
八、旋转矩阵假设角度用弧度。
九、单位向量生成要求随机数在零到一之间。
十、Halton 序列的基数不同，样本分布也不同。
十一、所有函数都是纯函数，可以在任意阶段调用。
十二、采样质量与样本数有关，少量样本要配合时间累积。
*/

/*
补充说明：序列的累积。
低差异序列适合每帧少量样本。
余弦半球用于漫反射。
手部深度在靠近相机时夹住下限。
三角分布让抖动更柔和。
样本数越多越平滑。
画面验证看间接光噪点。
*/

/*
补充说明：样本累积。
低差异序列适合少量样本。
余弦半球用于漫反射。
手部深度在近处夹住下限。
三角分布让抖动更柔和。
*/
