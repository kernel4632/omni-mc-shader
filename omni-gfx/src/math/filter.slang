// 双线性取像素：自己取四个相邻纹素再插值，不依赖硬件的线性过滤。
// 为什么不用 `SampleLevel`：像素画风格的月亮贴图会把硬件过滤设成最近邻，画面上出现锯齿；
// 按纹素中心取四次再按小数偏移插值，既保留最近邻的锐利，又能随屏幕坐标平滑移动。
// `coord` 是零到一的贴图坐标，`texSize` 是贴图边长（纹素）。
float4 ogxBilinearTexture(Sampler2D tex, float2 coord, float2 texSize)
{
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    float2 p = floor(coord); // 左下最近纹素。
    float2 f = coord - p; // 到该纹素的小数偏移，就是插值权重。
    int2 texelX = int2(p); // 四个纹素里左下的整数坐标。
    int2 texelW = texelX + int2(1); // 右上的整数坐标。
    float4 bottom = lerp(tex.Load(int3(texelX, 0)), tex.Load(int3(int2(texelW.x, texelX.y), 0)), f.x); // 先横向插值下排。
    float4 top = lerp(tex.Load(int3(int2(texelX.x, texelW.y), 0)), tex.Load(int3(texelW, 0)), f.x); // 再横向插值上排。
    return lerp(bottom, top, f.y); // 最后纵向插值。
}

// 天空盒图集的双线性取像素：与上一函数相同，但每个采样都夹在自己那一格里。
// 为什么需要夹紧：天空盒把六张面拼成 3×2 的大图，横跨格边取样会读到隔壁面的像素，
// 地平线附近就会出现一条颜色突变的接缝。`coord` 是零到一的图集坐标。
float4 ogxBilinearTextureSkybox(Sampler2D tex, float2 coord, float2 texSize)
{
    int2 grid = int2(floor(coord * float2(3.0, 2.0))); // 当前落在 3×2 图集的哪一格。
    int gridSize = int(floor(texSize.y * 0.5)); // 每格是正方形，边长取总高的一半。
    grid *= gridSize; // 格号换成格子的左上角纹素坐标。
    int4 border = int4(grid, grid + gridSize - 1); // 该格的闭区间边界，左下与右上。
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    float2 p = floor(coord); // 左下最近纹素。
    float2 f = coord - p; // 插值权重。
    int2 texelX = clamp(int2(p), border.xy, border.zw); // 左下纹素夹进本格。
    int2 texelW = clamp(texelX + int2(1), border.xy, border.zw); // 右上纹素同样夹紧。
    float4 bottom = lerp(tex.Load(int3(texelX, 0)), tex.Load(int3(int2(texelW.x, texelX.y), 0)), f.x); // 下排横向插值。
    float4 top = lerp(tex.Load(int3(int2(texelX.x, texelW.y), 0)), tex.Load(int3(texelW, 0)), f.x); // 上排横向插值。
    return lerp(bottom, top, f.y); // 纵向插值得到最终像素。
}

// 三次 B 样条的第零个权重；四个权重之和恒为一，单独取用才不会有亮度漂移。
// 为什么和库里已有的双三次采样不同：这里是一点五阶核，放大后更柔，参考包的天空贴图用它，
// 而 `ogxBicubicTexture` 用的是更锐的卡特穆尔-罗姆核；两条曲线不能互相替代。
// `a` 是采样点到纹素的小数偏移，取值零到一。
float ogxCubicWeight0(float a) { return (1.0 / 6.0) * (a * (a * (-a + 3.0) - 3.0) + 1.0); }

// 三次 B 样条的第二个权重：离采样点向右一个纹素。
float ogxCubicWeight1(float a) { return (1.0 / 6.0) * (a * a * (3.0 * a - 6.0) + 4.0); }

// 三次 B 样条的第三个权重：离采样点向右两个纹素。
float ogxCubicWeight2(float a) { return (1.0 / 6.0) * (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0); }

// 三次 B 样条的第四个权重：离采样点向右三个纹素，偏移越远权重越小。
float ogxCubicWeight3(float a) { return (1.0 / 6.0) * (a * a * a); }

// 左侧两个权重的和：把两次采样合并成一次双线性采样时用它做分母。
float ogxCubicWeightLow(float a) { return ogxCubicWeight0(a) + ogxCubicWeight1(a); }

// 右侧两个权重的和，与上一函数配对。
float ogxCubicWeightHigh(float a) { return ogxCubicWeight2(a) + ogxCubicWeight3(a); }

// 合并后左采样点在像素坐标里的位置：负一为左端，零为像素中心。
// 两个采样点不对称，必须按右权重占总权重的比例往左挪，画面才不会整体偏移半像素。
float ogxCubicOffsetLow(float a) { return -1.0 + ogxCubicWeight1(a) / (ogxCubicWeight0(a) + ogxCubicWeight1(a)); }

// 合并后右采样点的位置：正一为右端，按左权重占比往右挪。
float ogxCubicOffsetHigh(float a) { return 1.0 + ogxCubicWeight3(a) / (ogxCubicWeight2(a) + ogxCubicWeight3(a)); }

// 卡特穆尔-罗姆双三次采样：五次采样拼出十六像素的平滑放大，权重总和归一。
// 中间两个像素先合并成一次双线性采样，省掉四次纹理读取，画面与逐像素版本一致。
float3 ogxBicubicTexture(Sampler2D texSampler, float2 coord, float2 texSize)
{
    float2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize; // 换成像素坐标。
    float2 p = floor(coord - 0.5) + 0.5; // 左下最近像素中心。
    float2 f = coord - p; // 到该中心的小数偏移。
    float2 f2 = f * f; // 偏移平方。
    float2 f3 = f * f2; // 偏移立方。
    const float c = 0.5; // 卡特穆尔-罗姆张力。
    float2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 第一个像素权重。
    float2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 第二个像素权重。
    float2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 第三个像素权重。
    float2 w3 = c * f3 - c * f2; // 第四个像素权重。
    float2 w12 = w1 + w2; // 中间两个像素合并成一次双线性采样。
    float2 tc12 = texPixelSize * (p + w2 / w12); // 合并采样的位置。
    float2 tc0 = texPixelSize * (p - 1.0); // 最左或最下像素位置。
    float2 tc3 = texPixelSize * (p + 2.0); // 最右或最上像素位置。
    float4 color = float4(texSampler.SampleLevel(float2(tc12.x, tc0.y), 0.0).rgb, 1.0) * (w12.x * w0.y) +
                   float4(texSampler.SampleLevel(float2(tc0.x, tc12.y), 0.0).rgb, 1.0) * (w0.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc12.x, tc12.y), 0.0).rgb, 1.0) * (w12.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc3.x, tc12.y), 0.0).rgb, 1.0) * (w3.x * w12.y) +
                   float4(texSampler.SampleLevel(float2(tc12.x, tc3.y), 0.0).rgb, 1.0) * (w12.x * w3.y); // 十字形五次采样，a 通道累计权重。
    return color.rgb / color.a; // 除以权重和，补偿省掉的四角。
}

// 十六像素三次模糊：四次双线性采样合成，专供六十四见方的噪声贴图。
float4 ogxBicubicBlurTexture(Sampler2D texSampler, float2 coord)
{
    const float texPixelSize = 1.0 / 64.0; // 噪声贴图一个像素的大小。
    coord = coord * 64.0 - 0.5; // 换成以像素中心为原点的坐标。
    float2 p = floor(coord); // 整数像素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 两个方向的前两个三次样条权重。
    float4 w1; // 两个方向的后两个三次样条权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
    w1.yw = ff * f; // 第四个权重是偏移立方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
    float4 s = w0 + w1; // 左右两对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= texPixelSize; // 换回零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return lerp(lerp(texSampler.SampleLevel(c.yw, 0.0), texSampler.SampleLevel(c.xw, 0.0), m.x),
                lerp(texSampler.SampleLevel(c.yz, 0.0), texSampler.SampleLevel(c.xz, 0.0), m.x), m.y); // 四次双线性采样得到十六像素的三次模糊。
}

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
    float theta = 6.28318530718 * xi.y; // 绕竖直轴的角度。
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

// iterationT 的实体旋转矩阵：只绕前后轴转，供法线与切线一起旋转。
float2x2 ogxMat2RotateZ(float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2x2(c, s, -s, c);
}

// Eclipse 的半球方向：两个零到一的随机数变成一个朝上的单位向量。
float3 ogxGenUnitVector(float2 xy)
{
    xy.x *= 6.28318530718; // 横向角度乘一圈。
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
