// 颜色模块 AgX：对比曲线、宽色域压缩、可配置色域矩阵与三套参考变体。
// 调用位置：由 `common/color.slang` 内联引入，默认强光压缩与可配置选项都走这里。
// 可复制示例：`float3 c = ogxAgx(linearColor, 13.0, true);`
// 设计原因与取舍：普通版与可配置版共用矩阵工具，避免三套色域转换各写一份。

// AgX 对比度曲线：用六次多项式近似原查找表，省掉一张纹理。
float3 ogxAgxContrast(float3 x)
{
    return (((((15.5 * x - 40.14) * x + 31.96) * x - 6.868) * x + 0.4298) * x + 0.1191) * x - 0.00232;
}

// 转 AgX 宽色域工作空间的三列。
static const float3 OGX_AGX_0 = float3(0.842479062253094, 0.0784335999999992, 0.0792237451477643);
static const float3 OGX_AGX_1 = float3(0.0423282422610123, 0.878468636469772, 0.0791661274605434);
static const float3 OGX_AGX_2 = float3(0.0423756549057051, 0.0784336, 0.879142973793104);

// 从 AgX 宽色域转回显示原色的三列。
static const float3 OGX_AGX_BACK_0 = float3(1.19687900512017, -0.0980208811401368, -0.0990297440797205);
static const float3 OGX_AGX_BACK_1 = float3(-0.0528968517574562, 1.15190312990417, -0.0989611768448433);
static const float3 OGX_AGX_BACK_2 = float3(-0.0529716355144438, -0.0980434501171241, 1.15107367264116);

// AgX 强光压缩：先按中间灰取对数并夹进承认范围，再用 S 曲线成形，尽量保住高光色相。
// `ev` 是承认的动态范围，`abney` 与 ACES 版本含义相同。
// AgX 宽色域压缩：参考的默认曝光是 13、半动态范围 6.5；显式传入两个常数，避免派生值丢失。
float3 ogxAgx(float3 color, float ev, float hev, bool abney)
{
    color *= 2.3;
    if (abney)
    {
        color = ogxApplyRows(OGX_ABNEY_0, OGX_ABNEY_1, OGX_ABNEY_2, color);
    }
    color = ogxApplyRows(OGX_AGX_0, OGX_AGX_1, OGX_AGX_2, color);
    static const float MIDDLE_GREY = 0.18;
    color = clamp(log2(color / MIDDLE_GREY), float3(-hev), float3(hev));
    color = (color + hev) / ev;
    color = ogxAgxContrast(color);
    color = ogxApplyRows(OGX_AGX_BACK_0, OGX_AGX_BACK_1, OGX_AGX_BACK_2, color);
    return color;
}

// 旧三参数入口：半动态范围由曝光派生，保持现有调用点不变。
float3 ogxAgx(float3 color, float ev, bool abney) { return ogxAgx(color, ev, ev * 0.5, abney); }

// Eclipse 的 AgX look：保留参考的偏移、斜率与幂变量，默认零偏移、单位斜率与幂，只把饱和度推到 1.25。
// AgX 的 look 曲线：在色调映射后做一次对比与饱和调整。
float3 ogxAgxLook(float3 value)
{
    const float3 lw = float3(0.2126, 0.7152, 0.0722); // 参考实现固定 Rec.709 亮度。
    float luma = dot(value, lw); // 先取亮度，饱和度围绕它展开。
    float3 offset = float3(0.0); // 参考默认零偏移。
    float3 slope = float3(1.0); // 参考默认单位斜率。
    float3 power = float3(1.0); // 参考默认单位幂。
    float sat = 1.25; // 对比度/饱和度。
    value = pow(value * slope + offset, power); // 逐通道应用偏移、斜率与幂。
    return luma + sat * (value - luma); // 围绕亮度拉开饱和度。
}

// Eclipse 的 AgX 完整版：插入矩阵、动态范围 -12.47393 到 4.026069，再用 AGX look。
// AgX 主映射：把线性场景色压进显示范围并保留高光层次。
float3 ogxToneMapAgx(float3 color)
{
    float3 in0 = float3(0.856627153315983, 0.137318972929847, 0.11189821299995); // 插入矩阵第一列。
    float3 in1 = float3(0.0951212405381588, 0.761241990602591, 0.0767994186031903); // 第二列。
    float3 in2 = float3(0.0482516061458583, 0.101439036467562, 0.811302368396859); // 第三列。
    float3 out0 = float3(1.1271005818144368, - 0.1413297634984383, - 0.14132976349843826); // 输出矩阵第一列。
    float3 out1 = float3(- 0.11060664309660323, 1.157823702216272, - 0.11060664309660294); // 第二列。
    float3 out2 = float3(- 0.016493938717834573, - 0.016493938717834257, 1.2519364065950405); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入 AgX 工作空间。
    color = clamp(log2(color), float3(- 12.47393), float3(4.026069)); // 夹进承认的动态范围。
    color = (color + 12.47393) / (4.026069 + 12.47393); // 归一化到零到一。
    color = ogxAgxContrast(color); // AgX 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回到显示原色。
    color = pow(max(color, float3(0.0)), float3(2.2)); // 线性化。
    return clamp(color, float3(0.0), float3(1.0)); // 最后夹到显示范围。
}

// Eclipse 的 AgX 精简版：端点与完整版相同，但使用另一组插入/输出矩阵。
float3 ogxToneMapAgxMinimal(float3 color)
{
    float3 in0 = float3(0.842479062253094, 0.0423282422610123, 0.0423756549057051); // 精简插入矩阵第一列。
    float3 in1 = float3(0.0784335999999992, 0.878468636469772, 0.0784336); // 第二列。
    float3 in2 = float3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 第三列。
    float3 out0 = float3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    float3 out1 = float3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 第二列。
    float3 out2 = float3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), float3(- 12.47393), float3(4.026069)); // 与完整版相同的端点。
    color = (color + 12.47393) / (4.026069 + 12.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, float3(2.2)); // 线性化。
    return clamp(color, float3(0.0), float3(1.0)); // 夹紧。
}

// Eclipse 的 AgX Merlin 版：矩阵同上，端点整体上移一档，动态范围更窄。
// AgX 的另一种拟合：用简化多项式逼近同一曲线，减少常数运算。
float3 ogxToneMapAgxCompact(float3 color)
{
    float3 in0 = float3(0.842479062253094, 0.0423282422610123, 0.0423756549057051); // 精简插入矩阵第一列。
    float3 in1 = float3(0.0784335999999992, 0.878468636469772, 0.0784336); // 第二列。
    float3 in2 = float3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 第三列。
    float3 out0 = float3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    float3 out1 = float3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 第二列。
    float3 out2 = float3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), float3(- 11.47393), float3(3.226069)); // Merlin 的端点比精简版高 1。
    color = (color + 11.47393) / (3.226069 + 11.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, float3(2.2)); // 线性化。
    return clamp(color, float3(0.0), float3(1.0)); // 夹紧。
}

// 三列矩阵：用三个列向量表示，避开 Slang 与 GLSL 的行列顺序差异。
struct OgxAgxMat3
{
    float3 c0; // 第一列。
    float3 c1; // 第二列。
    float3 c2; // 第三列。
};

// 矩阵乘向量：三列分别乘分量再相加，和 GLSL 的 `mat3 * vec3` 完全一致。
float3 ogxAgxMulVec(OgxAgxMat3 m, float3 v)
{
    return m.c0 * v.x + m.c1 * v.y + m.c2 * v.z;
}

// 向量乘矩阵：结果的每个分量是向量与一列的点积，对应 GLSL 的 `vec3 * mat3`。
float3 ogxAgxVecMul(OgxAgxMat3 m, float3 v)
{
    return float3(dot(v, m.c0), dot(v, m.c1), dot(v, m.c2));
}

// 两个三列矩阵相乘：结果的每一列是左矩阵乘右矩阵的对应列。
OgxAgxMat3 ogxAgxMulMat(OgxAgxMat3 a, OgxAgxMat3 b)
{
    OgxAgxMat3 result;
    result.c0 = ogxAgxMulVec(a, b.c0);
    result.c1 = ogxAgxMulVec(a, b.c1);
    result.c2 = ogxAgxMulVec(a, b.c2);
    return result;
}

// 三列矩阵求逆：按列展开伴随矩阵，避免依赖不同后端的 `inverse` 实现。
OgxAgxMat3 ogxAgxInverse(OgxAgxMat3 m)
{
    float3 a = m.c0; // 第一列。
    float3 b = m.c1; // 第二列。
    float3 c = m.c2; // 第三列。
    float3 r0 = float3(b.y * c.z - b.z * c.y, a.z * c.y - a.y * c.z, a.y * b.z - a.z * b.y); // 伴随矩阵第一行。
    float3 r1 = float3(b.z * c.x - b.x * c.z, a.x * c.z - a.z * c.x, a.z * b.x - a.x * b.z); // 第二行。
    float3 r2 = float3(b.x * c.y - b.y * c.x, a.y * c.x - a.x * c.y, a.x * b.y - a.y * b.x); // 第三行。
    float determinant = dot(a, r0); // 行列式。
    OgxAgxMat3 result;
    result.c0 = float3(r0.x, r1.x, r2.x) / determinant; // 伴随矩阵转置后按列写入。
    result.c1 = float3(r0.y, r1.y, r2.y) / determinant;
    result.c2 = float3(r0.z, r1.z, r2.z) / determinant;
    return result;
}

// 色度坐标到 XYZ：Y 归一为一，X 与 Z 由 xy 反推。
// AgX 反变换：从显示色回推线性值，供历史帧比较与调试。
float3 ogxAgxUnproject(float2 xy)
{
    if (xy.y == 0.0) return float3(0.0); // 参考实现对零分母直接返回零。
    float x = xy.x / xy.y; // X 分量。
    float z = (1.0 - xy.x - xy.y) / xy.y; // Z 分量。
    return float3(x, 1.0, z); // Y 固定为一。
}

// 由三原色与白点色度构造 RGB 到 XYZ 的矩阵；列顺序与参考实现一致。
OgxAgxMat3 ogxAgxPrimariesToMatrix(float2 xyRed, float2 xyGreen, float2 xyBlue, float2 xyWhite)
{
    float3 xyzRed = ogxAgxUnproject(xyRed); // 红原色 XYZ。
    float3 xyzGreen = ogxAgxUnproject(xyGreen); // 绿原色 XYZ。
    float3 xyzBlue = ogxAgxUnproject(xyBlue); // 蓝原色 XYZ。
    float3 xyzWhite = ogxAgxUnproject(xyWhite); // 白点 XYZ。
    OgxAgxMat3 temp;
    temp.c0 = float3(xyzRed.x, xyzGreen.x, xyzBlue.x); // 第一行：三个 X。
    temp.c1 = float3(1.0, 1.0, 1.0); // 第二行：三个 Y。
    temp.c2 = float3(xyzRed.z, xyzGreen.z, xyzBlue.z); // 第三行：三个 Z。
    OgxAgxMat3 inverse = ogxAgxInverse(temp); // 参考实现对临时矩阵求逆。
    float3 scale = ogxAgxVecMul(inverse, xyzWhite); // 白点乘逆矩阵，得到三原色缩放。
    OgxAgxMat3 result;
    result.c0 = float3(scale.x * xyzRed.x, scale.y * xyzGreen.x, scale.z * xyzBlue.x); // 第一行乘缩放。
    result.c1 = float3(scale.x * xyzRed.y, scale.y * xyzGreen.y, scale.z * xyzBlue.y); // 第二行。
    result.c2 = float3(scale.x * xyzRed.z, scale.y * xyzGreen.z, scale.z * xyzBlue.z); // 第三行。
    return result;
}

// 主色滑动量：按角度正负选择邻居，返回侧向位移与邻居距离的比。
float ogxAgxRotationToSlide(float2 primary, float2 neighborA, float2 neighborB, float angle)
{
    float2 neighbor = lerp(neighborB, neighborA, float(angle >= 0.0)); // 角度非负时取 A。
    float distanceToNeighbor = distance(primary, neighbor); // 到邻居的距离。
    float distanceToCenter = length(primary); // 到白点的距离。
    float side = sin(angle / 180.0 * OGX_PI) * distanceToCenter; // 侧向位移。
    return side / distanceToNeighbor; // 归一化滑动量。
}

// 主色滑动：按滑动量在原色与邻居之间插值，滑动量先取绝对值再夹紧。
float2 ogxAgxSlidePrimary(float2 primary, float2 neighborA, float2 neighborB, float amount)
{
    return lerp(primary, lerp(neighborB, neighborA, float(amount >= 0.0)), ogxSaturate(abs(amount))); // 保留参考顺序。
}

// 压缩矩阵：先按旋转量滑动三原色，再按压缩量缩放，最后重建 RGB 到 XYZ。
OgxAgxMat3 ogxAgxComputeCompressionMatrix(float2 xyRed, float2 xyGreen, float2 xyBlue, float2 xyWhite)
{
    float2 offsetRed = xyRed - xyWhite; // 红原色相对白点。
    float2 offsetGreen = xyGreen - xyWhite; // 绿原色相对白点。
    float2 offsetBlue = xyBlue - xyWhite; // 蓝原色相对白点。
    float3 slide = float3(0.0); // 三个通道的滑动量。
    slide.r = ogxAgxRotationToSlide(offsetRed, offsetBlue, offsetGreen, 0.0); // 参考实现的 rotation.r 为零。
    slide.g = ogxAgxRotationToSlide(offsetGreen, offsetRed, offsetBlue, 0.0); // 参考实现的 rotation.g 为零。
    slide.b = ogxAgxRotationToSlide(offsetBlue, offsetGreen, offsetRed, -2.0); // 参考实现的 rotation.b 为负二。
    float3 scaleFactor = 1.0 / (1.0 - float3(0.0)); // 参考实现的 compression 为零。
    float2 red = ogxAgxSlidePrimary(offsetRed, offsetBlue, offsetGreen, slide.r) * scaleFactor.r + xyWhite; // 红原色新位置。
    float2 green = ogxAgxSlidePrimary(offsetGreen, offsetRed, offsetBlue, slide.g) * scaleFactor.g + xyWhite; // 绿原色新位置。
    float2 blue = ogxAgxSlidePrimary(offsetBlue, offsetGreen, offsetRed, slide.b) * scaleFactor.b + xyWhite; // 蓝原色新位置。
    return ogxAgxPrimariesToMatrix(red, green, blue, xyWhite); // 重建矩阵。
}

// 开放域转归一化对数：先除中间灰取 log2，再夹到动态范围并归一。
float3 ogxAgxOpenDomainToNormalizedLog2(float3 openDomain, float minimumEv, float maximumEv)
{
    const float middleGrey = 0.18; // 参考实现的中间灰。
    float totalExposure = maximumEv - minimumEv; // 动态范围宽度。
    float3 outputLog = clamp(log2(openDomain / middleGrey), minimumEv, maximumEv); // 夹到承认范围。
    return (outputLog - minimumEv) / totalExposure; // 归一化。
}

// 曲线缩放：由支点、斜率与幂反推曲线在支点处需要的尺度。
float ogxAgxEquationScale(float xPivot, float yPivot, float slopePivot, float power)
{
    return pow(pow(slopePivot * xPivot, -power) * (pow(slopePivot * (xPivot / yPivot), power) - 1.0), -1.0 / power); // 参考公式。
}

// 完整曲线：按支点决定趾部或肩部，再用双曲函数连接两侧。
float ogxAgxEquationFullCurve(float x, float xPivot, float yPivot, float slopePivot, float toePower, float shoulderPower)
{
    float bpivot = float(x >= xPivot); // 是否在支点右侧。
    float scaleXPivot = lerp(xPivot, 1.0 - xPivot, bpivot); // 支点按左右翻转。
    float scaleYPivot = lerp(yPivot, 1.0 - yPivot, bpivot); // 输出支点同样翻转。
    float toeScale = ogxAgxEquationScale(scaleXPivot, scaleYPivot, slopePivot, toePower); // 趾部尺度。
    float shoulderScale = ogxAgxEquationScale(scaleXPivot, scaleYPivot, slopePivot, shoulderPower); // 肩部尺度。
    float scale = lerp(-toeScale, shoulderScale, bpivot); // 左右选择正负尺度。
    float term = (slopePivot * (x - xPivot)) / scale; // 曲线内部项。
    float power = lerp(toePower, shoulderPower, float(scale >= 0.0)); // 按尺度选择幂。
    float hyperbolic = term / pow(1.0 + pow(term, power), 1.0 / power); // 双曲压缩。
    return scale * hyperbolic + yPivot; // 还原到输出范围。
}

// 组合矩阵在前面定义，主入口先声明，避免依赖文件里的书写顺序。
float3x3 ogxAgxCustomGamutMatrix3();

// iterationT 的可配置 AgX：把 RGB 转到调整后的工作空间，再走完整曲线。
// 组合矩阵由 `ogxAgxCustomGamutMatrix3` 提供，和单独调用矩阵版本共用同一套原色常数。
float3 ogxAgxConfigurable(float3 rgb)
{
    float3x3 adjustedFromSrgb = ogxAgxCustomGamutMatrix3(); // sRGB 到调整后空间的组合矩阵。
    float3 adjustedRgb = adjustedFromSrgb[0] * rgb.x + adjustedFromSrgb[1] * rgb.y + adjustedFromSrgb[2] * rgb.z; // 三列加权，避免行列约定差异。
    float minimumEv = -6.0; // 参考实现的最小曝光。
    float maximumEv = 6.0; // 最大曝光。
    float xPivot = abs(minimumEv) / (maximumEv - minimumEv); // 支点位置。
    float yPivot = 0.5; // 输出支点。
    float slope = 2.3; // 参考斜率。
    float toePower = 1.9; // 趾部幂。
    float shoulderPower = 2.5; // 肩部幂。
    float3 logValue = ogxAgxOpenDomainToNormalizedLog2(adjustedRgb, minimumEv, maximumEv); // 归一化对数。
    float outputRed = ogxAgxEquationFullCurve(logValue.r, xPivot, yPivot, slope, toePower, shoulderPower); // 红通道曲线。
    float outputGreen = ogxAgxEquationFullCurve(logValue.g, xPivot, yPivot, slope, toePower, shoulderPower); // 绿通道曲线。
    float outputBlue = ogxAgxEquationFullCurve(logValue.b, xPivot, yPivot, slope, toePower, shoulderPower); // 蓝通道曲线。
    return float3(outputRed, outputGreen, outputBlue); // 逐通道输出。
}

// iterationT 的 AgX 调整矩阵：只返回从 sRGB 到调整后空间的组合矩阵。
OgxAgxMat3 ogxAgxCustomGamutMatrix()
{
    float2 xyRed = float2(0.64, 0.33); // 红原色色度。
    float2 xyGreen = float2(0.3, 0.6); // 绿原色色度。
    float2 xyBlue = float2(0.15, 0.06); // 蓝原色色度。
    float2 xyWhite = float2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    return ogxAgxMulMat(srgbToXyz, ogxAgxInverse(adjustedToXyz)); // 组合成 sRGB 到调整后空间。
}

// 把三列矩阵换成 GLSL 的 mat3：参考包的三原色函数返回 mat3，调用方按矩阵乘向量。
float3x3 ogxAgxMat3ToMat3(OgxAgxMat3 m)
{
    return float3x3(m.c0, m.c1, m.c2);
}

// 参考签名的三原色矩阵：内部仍用三列结构体，只在边界转成 mat3。
float3x3 ogxAgxPrimariesToMat3(float2 xyRed, float2 xyGreen, float2 xyBlue, float2 xyWhite)
{
    return ogxAgxMat3ToMat3(ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite));
}

// 参考签名的压缩矩阵，与上一函数配对。
float3x3 ogxAgxCompressionToMat3(float2 xyRed, float2 xyGreen, float2 xyBlue, float2 xyWhite)
{
    return ogxAgxMat3ToMat3(ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite));
}

// 参考签名的 AgX 组合矩阵：无参数，返回 sRGB 到调整后空间的矩阵。
float3x3 ogxAgxCustomGamutMatrix3()
{
    return ogxAgxMat3ToMat3(ogxAgxCustomGamutMatrix());
}

/*
实现说明：AgX 色调映射与可配置色域。
一、工作空间：先把显示原色转到 AgX 的宽色域，矩阵由三原色与白点算出。
二、对数压缩：把线性亮度转到以二为底的对数，端点由最小与最大曝光决定。
三、曲线：趾部、肩部与支点组成分段双曲曲线，参数改变对比与过渡。
四、look：对比、饱和与色相偏移在压缩后的空间里做，避免直接改线性颜色造成色偏。
五、色域：`ogxAgxPrimariesToMatrix` 与 `ogxAgxComputeCompressionMatrix` 用三原色构造矩阵，支持自定义色域。
六、紧凑版：`ogxToneMapAgxCompact` 用更窄的动态范围换更少的常数运算。
七、输出：逐通道曲线后再转回显示原色并夹紧。
八、取舍：矩阵乘法显式展开成三列，避免 Slang 与 GLSL 的行列顺序差异。
*/

/*
函数索引：
一、`ogxAgxContrast`：对比曲线，输入零到一。
二、`ogxAgx`：完整 AgX，输入线性颜色与曝光参数。
三、`ogxAgxLook`：对比、饱和与色相偏移。
四、`ogxToneMapAgx` 与 `ogxToneMapAgxMinimal`：完整与精简两条路径。
五、`ogxToneMapAgxCompact`：更窄动态范围的紧凑版。
六、矩阵工具：`ogxAgxMulVec`、`ogxAgxVecMul`、`ogxAgxMulMat` 与 `ogxAgxInverse`。
七、色度：`ogxAgxUnproject` 把色度坐标还原成 XYZ。
八、原色矩阵：`ogxAgxPrimariesToMatrix` 由三原色与白点构造 RGB 到 XYZ。
九、压缩矩阵：`ogxAgxComputeCompressionMatrix` 先滑动主色再缩放。
十、曲线：`ogxAgxEquationScale` 与 `ogxAgxEquationFullCurve` 组成分段双曲曲线。
十一、自定义色域：`ogxAgxCustomGamutMatrix` 与 `ogxAgxCustomGamutMatrix3` 返回组合矩阵。
十二、边界：矩阵乘法显式展开成三列，避免两个后端的行列顺序差异。
*/

/*
参数与边界：
一、最小与最大曝光决定对数端点，调用方要保证最小小于最大。
二、支点、斜率、趾部与肩部幂都按参考精度保留。
三、三原色与白点用色度坐标，不是 XYZ。
四、矩阵求逆在行列式为零时没有保护，调用方要保证色域有效。
五、自定义色域矩阵返回三列结构体，再转成 GLSL 的 mat3。
六、完整版与精简版的端点不同，不能混用。
七、紧凑版的动态范围更窄，适合低对比场景。
八、输出夹到零到一，调用方负责伽马编码。
九、矩阵乘法显式展开，避免两个后端的行列顺序差异。
十、所有函数只接收显式颜色与参数，不读取引擎状态。
*/

/*
补充说明：AgX 的端点。
最小与最大曝光决定对数端点。
端点改变会同时改变对比与色相。
自定义色域的矩阵在行列式为零时没有保护。
输出夹到零到一。
画面验证看高光与肤色。
*/
