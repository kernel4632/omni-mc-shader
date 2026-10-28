// 数学模块标量工具：向量夹紧、区间映射、极值、圆盘点列、归一化与矩阵乘向量。
// 调用位置：由 `common/math.slang` 内联引入，不单独生成 GLSL 或探针。
// 可复制示例：`float2 p = ogxNormalize(float2(1.0, 2.0));`
// 设计原因与取舍：只收不依赖采样器的纯计算，算式与常数照旧库保留。

// 同时给出正弦与余弦：极坐标采样需要两者，一次算出省掉一次三角函数。
float2 ogxSinCos(float angle) { return float2(sin(angle), cos(angle)); } // 交回这一段的计算结果。

// 二维旋转：把点按角度绕原点转动，光斑与暗角图案用得到。
float2 ogxRotate2(float2 p, float angle) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float2 sc = ogxSinCos(angle); // 当前步骤的中间量。
    return float2(p.x * sc.y - p.y * sc.x, p.x * sc.x + p.y * sc.y); // 交回这一段的计算结果。
} // 按参考顺序推进。

// 把值从一段区间线性映射到零到一，再夹紧；区间外不会越界。
float ogxRemapSaturate(float x, float e0, float e1) { return ogxSaturate((x - e0) / (e1 - e0)); } // 交回这一段的计算结果。

// 把值从一段区间线性映射到另一段区间，两端都不夹紧；目标区间可以反向。
// 为什么保留不夹紧的版本：动画曲线与雾密度需要外插，提前夹紧会把远处的值压成一团。
float ogxRemap(float x, float minOrigin, float maxOrigin, float minNew, float maxNew) // 当前步骤的中间量。
{ // 按参考顺序推进。
    return (x - minOrigin) / (maxOrigin - minOrigin) * (maxNew - minNew) + minNew; // 交回这一段的计算结果。
} // 按参考顺序推进。

// 三分量版本的不夹紧映射，逐通道用同一组端点。
float3 ogxRemap(float3 x, float3 minOrigin, float3 maxOrigin, float3 minNew, float3 maxNew) // 当前步骤的中间量。
{ // 按参考顺序推进。
    return (x - minOrigin) / (maxOrigin - minOrigin) * (maxNew - minNew) + minNew; // 交回这一段的计算结果。
} // 按参考顺序推进。

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
// 圆盘映射把方形坐标折成圆：先按最大分量归一，再按半径缩放。
// 这样角上的点不会被拉出圆外，采样点在整个圆盘上均匀。
// 三维版本多一个 z 分量，供球面采样直接使用。
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
float4 ogxMatrixMulPoint4(float4x4 m, float4 v) { return ogxMatrixMul(m, v); }

// 四乘四矩阵的平移列：GLSL 的第四列存放平移，Slang 与 GLSL 的下标指向同一块内存。
float3 ogxMatrixTranslation(float4x4 m) { return m[3].xyz; }

// 三乘三矩阵乘三维向量，展开成三列的加权和，与 GLSL 的 `mat3 * vec3` 完全一致。
float3 ogxMatrix3MulPoint(float3x3 m, float3 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z; }

// 两参数反正切：先处理竖直方向，再对左半平面补一个圆周率。
// 两参数反正切：按象限修正单参数版本，返回负一到一之间的角度比例。
// 为什么不用内建反正切：参考实现把结果除以圆周率，调用方按比例使用；
// 这里保留同一约定，避免每个调用点各乘一次。
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
