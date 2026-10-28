// 基础标量工具：夹紧、亮度、符号、长度与插值，供所有模块复用。
float ogxSaturate(float x) { return clamp(x, 0.0, 1.0); }
float2 ogxSaturate(float2 x) { return clamp(x, float2(0.0), float2(1.0)); }
float3 ogxSaturate(float3 x) { return clamp(x, float3(0.0), float3(1.0)); }
// 四分量重载：逐分量夹到零到一，颜色与打包数据共用。
float4 ogxSaturate(float4 x) { return clamp(x, float4(0.0), float4(1.0)); }

// 人眼亮度权重，和显示管线一致；绿权重最高，蓝最低。
static const float3 OGX_LUMA_WEIGHTS = float3(0.2125, 0.7154, 0.0721);

// 按人眼权重求亮度，用于曝光、去饱和和暗视觉。
float ogxLuminance(float3 color) { return dot(color, OGX_LUMA_WEIGHTS); }

// 位运算取符号，支持标量；负数为负一，其余为正一。
float ogxSign(float x) { return asfloat((asuint(x) & 0x80000000u) | 0x3f800000u); }

// 向量版本的取符号：逐分量处理，法线折叠与八面体编码需要它。
float2 ogxSign(float2 x) { return asfloat((asuint(x) & uint2(0x80000000u)) | uint2(0x3f800000u)); }
float3 ogxSign(float3 x) { return asfloat((asuint(x) & uint3(0x80000000u)) | uint3(0x3f800000u)); }
float4 ogxSign(float4 x) { return asfloat((asuint(x) & uint4(0x80000000u)) | uint4(0x3f800000u)); }

// 位运算近似平方根，误差约百分之三，只用在不在乎精度的形状计算。
float ogxFastSqrt(float x) { return asfloat(uint(0x1fbd1df5 + (asint(x) >> 1))); }

// 平方：把乘方写成函数，几何求交与距离比较的公式能和参考源码逐行对上。
float ogxSquare(float x) { return x * x; }

// 长度的平方：比较远近时不需要开方，省掉一次 sqrt。
float ogxLengthSquared(float3 v) { return dot(v, v); }
// 二分量版本：参考包的光线求交与椭圆距离只用平面长度。
float ogxLengthSquared(float2 v) { return dot(v, v); }

// 取倒数长度：与 Eclipse `rcp_length` 相同，直接 inversesqrt(dot(v,v))；参考不接受零向量。
// 为什么用 Slang 的平方根倒数名字：生成器会把它换成 GLSL 的倒数平方根；
// 若直接写 GLSL 名字，Slang 探针会报未定义标识符。
float ogxSafeInvLength(float3 v) { return rsqrt(dot(v, v)); }
// 二分量版本，零向量同样退回零。
float ogxSafeInvLength(float2 v) { float d = dot(v, v); return d > 1e-12 ? 1.0 / sqrt(d) : 0.0; }

// 三角波：把任意输入折回零到一，周期二；噪声与条纹图案常用它代替正弦。
float ogxTriangleWave(float x) { return 1.0 - abs((x * 0.5 - floor(x * 0.5)) * 2.0 - 1.0); }

// 二维乘加：常数项的写法与参考源码一致，便于逐行核对。
float2 ogxFma2(float2 a, float2 b, float2 c) { return a * b + c; }
// 标量乘加：参考包的 `fma2` 只处理三个标量，保留同签名重载给旧调用点。
float ogxFma2(float a, float b, float c) { return a * b + c; }

// 同时给出正弦与余弦：极坐标采样需要两者，一次算出省掉一次三角函数。
float2 ogxSinCos(float angle) { return float2(sin(angle), cos(angle)); }

// 二维旋转：把点按角度绕原点转动，光斑与暗角图案用得到。
float2 ogxRotate2(float2 p, float angle)
{
    float2 sc = ogxSinCos(angle);
    return float2(p.x * sc.y - p.y * sc.x, p.x * sc.x + p.y * sc.y);
}

// 把值从一段区间线性映射到零到一，再夹紧；区间外不会越界。
float ogxRemapSaturate(float x, float e0, float e1) { return ogxSaturate((x - e0) / (e1 - e0)); }

// 把值从一段区间线性映射到另一段区间，两端都不夹紧；目标区间可以反向。
// 为什么保留不夹紧的版本：动画曲线与雾密度需要外插，提前夹紧会把远处的值压成一团。
float ogxRemap(float x, float minOrigin, float maxOrigin, float minNew, float maxNew)
{
    return (x - minOrigin) / (maxOrigin - minOrigin) * (maxNew - minNew) + minNew;
}

// 三分量版本的不夹紧映射，逐通道用同一组端点。
float3 ogxRemap(float3 x, float3 minOrigin, float3 maxOrigin, float3 minNew, float3 maxNew)
{
    return (x - minOrigin) / (maxOrigin - minOrigin) * (maxNew - minNew) + minNew;
}

// 三分量里最小的一个，等价于先两两取小再合并。
float ogxMinVec3(float3 value) { return min(value.x, min(value.y, value.z)); }

// 二分量的最小与最大：参考包对 2、3、4 分量各有一个同名重载，库补齐常用的两组。
float ogxMinVec2(float2 value) { return min(value.x, value.y); }
float ogxMaxVec2(float2 value) { return max(value.x, value.y); }
float ogxMinVec4(float4 value) { return min(min(value.x, value.y), min(value.z, value.w)); }
// 四分量最大值：曝光统计与亮度比较需要单个代表值。
float ogxMaxVec4(float4 value) { return max(max(value.x, value.y), max(value.z, value.w)); }

// 三分量里最大的一个，和上一函数配对使用。
float ogxMaxVec3(float3 value) { return max(value.x, max(value.y, value.z)); }

// 黄金角：圆周除以黄金比的平方，圆盘点列靠它错开方向，相邻两个点不会撞在一起。

// 圆盘内均匀分布的第 `index` 个采样点：角度按黄金角步进，半径取平方根保证面积均匀。
float2 ogxCircleMap(float index, float count)
{
    float angle = index * count * OGX_GOLDEN_ANGLE;
    return float2(sin(angle), cos(angle)) * sqrt(index);
}

// 圆盘采样的三分量版本：前两个分量是方向，第三个分量是半径。
// 为什么单独保留：Eclipse 的 `circlemapL` 用它直接取带长度的三维点，
// 与二维 `circlemap` 只差返回类型；混用会把半径丢掉。
float3 ogxCircleMapL(float index, float count)
{
    float angle = index * count * OGX_GOLDEN_ANGLE;
    return float3(sin(angle), cos(angle), sqrt(index));
}

// 把零到一的样本序号变成圆盘上的螺旋采样点，给环境光遮蔽与反射做低差异分布。
// 为什么先把下限抬到一点五毫：零半径的点全部重叠在圆心，等于白算一次采样。
float2 ogxSpiralSample(int samples, int totalSamples, float rotation, float xi)
{
    xi = max(xi, 0.0015);
    float alpha = float(samples + xi) * (1.0 / float(totalSamples));
    float theta = OGX_PI * 2.0 * alpha * rotation;
    return float2(sqrt(xi) * sin(theta), sqrt(xi) * cos(theta));
}

// 粗糙高光的方向估算：把半程向量的斜率换成固定的螺旋步进。
// 为什么用螺旋：没有真实法线分布时，按样本序号铺满锥面比随机抖动更不容易出闪点。
float3 ogxRoughSpecularDirection(float index, float alpha2, int steps)
{
    float x = (alpha2 * index) / (1.0 - index);
    float y = index * float(steps) * 64.0 * 64.0 * OGX_GOLDEN_ANGLE;
    float c = rsqrt(x + 1.0);
    float s = sqrt(x) * c;
    return float3(cos(y) * s, sin(y) * s, c);
}

// 单位化向量，长度极小时用一个小分母兜底，避免着色点出现除零后的无穷值。
// 比直接除以长度多一点开销，但水面与反射会在掠射角读到极短向量，必须兜底。
float3 ogxNormalize(float3 vector) { return vector * rsqrt(max(dot(vector, vector), 1e-10)); }
// 二分量版本的归一化，供屏幕空间与平面方向使用。
float2 ogxNormalize(float2 vector) { return vector * rsqrt(max(dot(vector, vector), 1e-10)); }

// GLSL 取模的语义：结果始终落在零到除数之间，负数也一样。
// 为什么不用机器附带的余数函数：它的符号跟随被除数，负数会得到负值，跟 GLSL 的取模不同。
float ogxMod(float x, float y) { return x - y * floor(x / y); }

// 逐分量判断两个向量是否完全相等。
// 为什么不用 `==` 加聚合函数：GLSL 的向量相等本来就返回一个布尔值，Slang 返回布尔向量，
// 两边写在一起会有一边报错；显式逐分量写，两种语言的语义完全相同。
bool ogxEqual(float2 a, float2 b) { return a.x == b.x && a.y == b.y; }
bool ogxEqual(float3 a, float3 b) { return a.x == b.x && a.y == b.y && a.z == b.z; }
bool ogxEqual(float4 a, float4 b) { return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w; }

// 四乘四矩阵乘四维向量：按四列加权求和。
// 为什么不用 `*`：Slang 与 GLSL 对矩阵乘法的行列解释不同，显式展开后两边结果一定相同。
float4 ogxMatrixMul(float4x4 m, float4 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w; }

// 四乘四矩阵的左上三阶乘以三维向量，等价于 GLSL 里的 `mat3(m) * v`。
// 只用来做旋转与缩放，平移由调用方单独加上，读代码时能一眼看出有没有平移。
float3 ogxMatrixMulPoint(float4x4 m, float3 v) { return m[0].xyz * v.x + m[1].xyz * v.y + m[2].xyz * v.z; }

// 完整四维矩阵乘四维向量：末地透视阴影需要保留齐次分量。
float4 ogxMatrixMulPoint4(float4x4 m, float4 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w; }

// 四乘四矩阵的平移列：GLSL 的第四列存放平移，Slang 与 GLSL 的下标指向同一块内存。
float3 ogxMatrixTranslation(float4x4 m) { return m[3].xyz; }

// 三乘三矩阵乘三维向量，展开成三列的加权和，与 GLSL 的 `mat3 * vec3` 完全一致。
float3 ogxMatrix3MulPoint(float3x3 m, float3 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z; }

// 两参数反正切：先处理竖直方向，再对左半平面补一个圆周率。
float ogxAtan2(float2 v)
{
    return v.x == 0.0 ?
        (1.0 - step(abs(v.y), 0.0)) * sign(v.y) * OGX_HALF_PI :
        atan(v.y / v.x) + step(v.x, 0.0) * sign(v.y) * OGX_PI;
}

// 反余弦的一次多项式近似：先按绝对值算，最后按符号翻转。
float ogxFastAcos(float x)
{
    float ax = abs(x);
    float result = -0.156583 * ax + OGX_HALF_PI;
    result *= ogxFastSqrt(1.0 - ax);
    return x >= 0.0 ? result : OGX_PI - result;
}

// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
float3 ogxLinearToGamma(float3 color) { return pow(color, float3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
float3 ogxGammaToLinear(float3 color) { return pow(color, float3(2.2)); }

// 水洼粗糙度：湿润阶段按锐度在干湿之间插值；水面与材质解码共用这一条。
float ogxPuddleRoughness(float roughness, float wetRoughness, float wetnessStages, float sharpness)
{
    return lerp(roughness, wetRoughness, wetnessStages * sharpness); // 湿润阶段乘锐度作为混合比例。
}

// 平滑曲线：把零到一映射成两端平、中间陡的零到一，投影光斑与柔边都用它。
// 与 iterationT 的 `curve(x)` 逐项相同，调用方自己保证输入已夹紧。
float ogxCurve01(float x)
{
    return x * x * (3.0 - 2.0 * x);
}

// 中间画面用的四次方根曲线，压缩高动态范围并保住暗部。
float ogxLinearToCurve(float color) { return pow(color, 0.25); }

// 四次方根曲线解码：平方两次得到原值。
float ogxCurveToLinear(float color)
{
    color = color * color;
    return color * color;
}

// 向量版本的四次方根编码，逐通道处理。
float3 ogxLinearToCurve3(float3 color) { return pow(color, float3(0.25)); }

// 向量版本的四次方根解码，逐通道平方两次。
float3 ogxCurveToLinear3(float3 color)
{
    color = color * color;
    return color * color;
}

// 把两个八位分量打包进一个浮点；高八位放第一个，低八位放第二个。
float ogxPack2x8(float2 value)
{
    uint2 bits = uint2(value * 255.0);
    return float((bits.x << 8u) | bits.y) / 65535.0;
}

// 从打包浮点还原两个八位分量，读取方必须按同一约定拆位。
float2 ogxUnpack2x8(float value)
{
    uint bits = uint(value * 65535.0);
    return float2(bits >> 8u, bits & 255u) / 255.0;
}

// 把两个十六位分量直接按位塞进浮点，不损失精度，但只能按位还原。
float ogxPack2x16(float2 value)
{
    uint2 bits = uint2(value * 65535.0);
    return asfloat((bits.x << 16u) | bits.y);
}

// 取回两个十六位分量并归一化；输入必须是 `ogxPack2x16` 的结果。
float2 ogxUnpack2x16(float value)
{
    uint bits = asuint(value);
    return float2(bits >> 16u, bits & 65535u) / 65535.0;
}

// 八面体折返：把下半球的分量交换并按符号放回外圈。
float2 ogxOctWrap(float2 v) { return (1.0 - abs(v.yx)) * float2(ogxSign(v.x), ogxSign(v.y)); }

// 把单位法线编码到零到一的二维坐标，八个象限各占一块。
float2 ogxEncodeNormal(float3 n)
{
    n.xy /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = n.z >= 0.0 ? n.xy : ogxOctWrap(n.xy);
    return n.xy * 0.5 + 0.5;
}

// 把八面体坐标解回单位法线，与上一函数互逆。
float3 ogxDecodeNormal(float2 encoded)
{
    float2 n = encoded * 2.0 - 1.0;
    float nz = 1.0 - abs(n.x) - abs(n.y);
    return normalize(float3(nz >= 0.0 ? n : ogxOctWrap(n), nz));
}

// 从贴图法线解出切线空间法线：全黑或全白不是法线数据，退回朝外。
float3 ogxDecodeNormalTex(float3 texNormal)
{
    float3 normal = float3(0.0, 0.0, 1.0);
    if (abs(texNormal.x + texNormal.y + texNormal.z - 1.5) < 1.488)
    {
        normal.xy = texNormal.xy * 2.0 - 1.0;
        normal.xy = max(abs(normal.xy) - 1.0 / 255.0, float2(0.0)) * float2(sign(normal.x), sign(normal.y));
        normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));
    }
    return normal;
}
