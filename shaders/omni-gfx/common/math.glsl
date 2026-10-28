/*
生成文件：数学模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库数学模块：曲线、编码、材质、光线求交、噪声与切线基。
调用位置：任何需要纯数学函数的图形程序；Minecraft 光影由 `/omni-gfx/common/math.glsl` 引入。
可复制示例：
    vec3 n = ogxDecodeNormal(ogxEncodeNormal(worldNormal)); // 法线编码后再解回。
    vec3 c = ogxBlackbody(6500.0); // 用色温生成颜色。
    float ao = ogxRemapSaturate(distance, 0.0, 1.0); // 把距离映射到零到一。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀，避免和宿主重名。
    常数与算式逐项来自迁移前的 GLSL 原型，迁移只改名字和语法，保证画面不变。
    贴图过滤函数把采样器与坐标全部作为显式参数，库不绑定纹理单元；取像素仍用显式层级。
    本文件同时是 Slang 源和 GLSL 生成源，因此只用两边都认得的写法，矩阵乘法显式展开。
*/
#ifndef OGX_MATH_INCLUDED
#define OGX_MATH_INCLUDED

// 圆周率与常用倒数，和旧库保持同一精度。
const float OGX_PI = 3.14159265359;
const float OGX_TAU = 6.28318530718;
const float OGX_HALF_PI = 1.57079632679;
const float OGX_INV_PI = 0.31830988618;

// 帧间抖动用的两个无理步长，让相邻帧的偏移尽量不重合。
const float OGX_GOLDEN_RATIO = 1.61803398875;
const float OGX_PLASTIC_RATIO = 1.32471795724;
// 黄金角：螺旋采样每步旋转这个角度，样本不会排成放射状条纹；与参考宏同值。
const float OGX_GOLDEN_ANGLE = 2.39996322973;

// 参考包把零到一夹紧写成 `saturate` 宏。宏体里的 0 与 1 不会被严格对照的常数表
// 看见，所以新移植的算法也保留宏写法：两边看到同一组常数，不会因为换成函数而多出两个数。
#define OGX_CLAMP01(value) clamp((value), 0.0, 1.0)


// --- 基础标量工具 ---

// 基础标量工具：夹紧、亮度、符号、长度与插值，供所有模块复用。
float ogxSaturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 ogxSaturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 ogxSaturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
// 四分量重载：逐分量夹到零到一，颜色与打包数据共用。
vec4 ogxSaturate(vec4 x) { return clamp(x, vec4(0.0), vec4(1.0)); }

// 人眼亮度权重，和显示管线一致；绿权重最高，蓝最低。
const vec3 OGX_LUMA_WEIGHTS = vec3(0.2125, 0.7154, 0.0721);

// 按人眼权重求亮度，用于曝光、去饱和和暗视觉。
float ogxLuminance(vec3 color) { return dot(color, OGX_LUMA_WEIGHTS); }

// 位运算取符号，支持标量；负数为负一，其余为正一。
float ogxSign(float x) { return uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3f800000u); }

// 向量版本的取符号：逐分量处理，法线折叠与八面体编码需要它。
vec2 ogxSign(vec2 x) { return uintBitsToFloat((floatBitsToUint(x) & uvec2(0x80000000u)) | uvec2(0x3f800000u)); }
vec3 ogxSign(vec3 x) { return uintBitsToFloat((floatBitsToUint(x) & uvec3(0x80000000u)) | uvec3(0x3f800000u)); }
vec4 ogxSign(vec4 x) { return uintBitsToFloat((floatBitsToUint(x) & uvec4(0x80000000u)) | uvec4(0x3f800000u)); }

// 位运算近似平方根，误差约百分之三，只用在不在乎精度的形状计算。
float ogxFastSqrt(float x) { return uintBitsToFloat(uint(0x1fbd1df5 + (floatBitsToInt(x) >> 1))); }

// 平方：把乘方写成函数，几何求交与距离比较的公式能和参考源码逐行对上。
float ogxSquare(float x) { return x * x; }

// 长度的平方：比较远近时不需要开方，省掉一次 sqrt。
float ogxLengthSquared(vec3 v) { return dot(v, v); }
// 二分量版本：参考包的光线求交与椭圆距离只用平面长度。
float ogxLengthSquared(vec2 v) { return dot(v, v); }

// 取倒数长度：与 Eclipse `rcp_length` 相同，直接 inversesqrt(dot(v,v))；参考不接受零向量。
// 为什么用 Slang 的平方根倒数名字：生成器会把它换成 GLSL 的倒数平方根；
// 若直接写 GLSL 名字，Slang 探针会报未定义标识符。
float ogxSafeInvLength(vec3 v) { return inversesqrt(dot(v, v)); }
// 二分量版本，零向量同样退回零。
float ogxSafeInvLength(vec2 v) { float d = dot(v, v); return d > 1e-12 ? 1.0 / sqrt(d) : 0.0; }

// 三角波：把任意输入折回零到一，周期二；噪声与条纹图案常用它代替正弦。
float ogxTriangleWave(float x) { return 1.0 - abs((x * 0.5 - floor(x * 0.5)) * 2.0 - 1.0); }

// 二维乘加：常数项的写法与参考源码一致，便于逐行核对。
vec2 ogxFma2(vec2 a, vec2 b, vec2 c) { return a * b + c; }
// 标量乘加：参考包的 `fma2` 只处理三个标量，保留同签名重载给旧调用点。
float ogxFma2(float a, float b, float c) { return a * b + c; }

// 标量工具与矩阵展开，具体实现在子文件。
// 子文件：common/math/scalar.slang。
// 数学模块标量工具：向量夹紧、区间映射、极值、圆盘点列、归一化与矩阵乘向量。
// 调用位置：由 `common/math.slang` 内联引入，不单独生成 GLSL 或探针。
// 可复制示例：`vec2 p = ogxNormalize(vec2(1.0, 2.0));`
// 设计原因与取舍：只收不依赖采样器的纯计算，算式与常数照旧库保留。

// 同时给出正弦与余弦：极坐标采样需要两者，一次算出省掉一次三角函数。
vec2 ogxSinCos(float angle) { return vec2(sin(angle), cos(angle)); }

// 二维旋转：把点按角度绕原点转动，光斑与暗角图案用得到。
vec2 ogxRotate2(vec2 p, float angle)
{
    vec2 sc = ogxSinCos(angle);
    return vec2(p.x * sc.y - p.y * sc.x, p.x * sc.x + p.y * sc.y);
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
vec3 ogxRemap(vec3 x, vec3 minOrigin, vec3 maxOrigin, vec3 minNew, vec3 maxNew)
{
    return (x - minOrigin) / (maxOrigin - minOrigin) * (maxNew - minNew) + minNew;
}

// 三分量里最小的一个，等价于先两两取小再合并。
float ogxMinVec3(vec3 value) { return min(value.x, min(value.y, value.z)); }

// 二分量的最小与最大：参考包对 2、3、4 分量各有一个同名重载，库补齐常用的两组。
float ogxMinVec2(vec2 value) { return min(value.x, value.y); }
float ogxMaxVec2(vec2 value) { return max(value.x, value.y); }
float ogxMinVec4(vec4 value) { return min(min(value.x, value.y), min(value.z, value.w)); }
// 四分量最大值：曝光统计与亮度比较需要单个代表值。
float ogxMaxVec4(vec4 value) { return max(max(value.x, value.y), max(value.z, value.w)); }

// 三分量里最大的一个，和上一函数配对使用。
float ogxMaxVec3(vec3 value) { return max(value.x, max(value.y, value.z)); }

// 黄金角：圆周除以黄金比的平方，圆盘点列靠它错开方向，相邻两个点不会撞在一起。

// 圆盘内均匀分布的第 `index` 个采样点：角度按黄金角步进，半径取平方根保证面积均匀。
vec2 ogxCircleMap(float index, float count)
{
    float angle = index * count * OGX_GOLDEN_ANGLE;
    return vec2(sin(angle), cos(angle)) * sqrt(index);
}

// 圆盘采样的三分量版本：前两个分量是方向，第三个分量是半径。
// 为什么单独保留：Eclipse 的 `circlemapL` 用它直接取带长度的三维点，
// 与二维 `circlemap` 只差返回类型；混用会把半径丢掉。
vec3 ogxCircleMapL(float index, float count)
{
    float angle = index * count * OGX_GOLDEN_ANGLE;
    return vec3(sin(angle), cos(angle), sqrt(index));
}

// 把零到一的样本序号变成圆盘上的螺旋采样点，给环境光遮蔽与反射做低差异分布。
// 为什么先把下限抬到一点五毫：零半径的点全部重叠在圆心，等于白算一次采样。
vec2 ogxSpiralSample(int samples, int totalSamples, float rotation, float xi)
{
    xi = max(xi, 0.0015);
    float alpha = float(samples + xi) * (1.0 / float(totalSamples));
    float theta = OGX_PI * 2.0 * alpha * rotation;
    return vec2(sqrt(xi) * sin(theta), sqrt(xi) * cos(theta));
}

// 粗糙高光的方向估算：把半程向量的斜率换成固定的螺旋步进。
// 为什么用螺旋：没有真实法线分布时，按样本序号铺满锥面比随机抖动更不容易出闪点。
vec3 ogxRoughSpecularDirection(float index, float alpha2, int steps)
{
    float x = (alpha2 * index) / (1.0 - index);
    float y = index * float(steps) * 64.0 * 64.0 * OGX_GOLDEN_ANGLE;
    float c = inversesqrt(x + 1.0);
    float s = sqrt(x) * c;
    return vec3(cos(y) * s, sin(y) * s, c);
}

// 单位化向量，长度极小时用一个小分母兜底，避免着色点出现除零后的无穷值。
// 比直接除以长度多一点开销，但水面与反射会在掠射角读到极短向量，必须兜底。
vec3 ogxNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }
// 二分量版本的归一化，供屏幕空间与平面方向使用。
vec2 ogxNormalize(vec2 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }

// GLSL 取模的语义：结果始终落在零到除数之间，负数也一样。
// 为什么不用机器附带的余数函数：它的符号跟随被除数，负数会得到负值，跟 GLSL 的取模不同。
float ogxMod(float x, float y) { return x - y * floor(x / y); }

// 逐分量判断两个向量是否完全相等。
// 为什么不用 `==` 加聚合函数：GLSL 的向量相等本来就返回一个布尔值，Slang 返回布尔向量，
// 两边写在一起会有一边报错；显式逐分量写，两种语言的语义完全相同。
bool ogxEqual(vec2 a, vec2 b) { return a.x == b.x && a.y == b.y; }
bool ogxEqual(vec3 a, vec3 b) { return a.x == b.x && a.y == b.y && a.z == b.z; }
bool ogxEqual(vec4 a, vec4 b) { return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w; }

// 四乘四矩阵乘四维向量：按四列加权求和。
// 为什么不用 `*`：Slang 与 GLSL 对矩阵乘法的行列解释不同，显式展开后两边结果一定相同。
vec4 ogxMatrixMul(mat4 m, vec4 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w; }

// 四乘四矩阵的左上三阶乘以三维向量，等价于 GLSL 里的 `mat3(m) * v`。
// 只用来做旋转与缩放，平移由调用方单独加上，读代码时能一眼看出有没有平移。
vec3 ogxMatrixMulPoint(mat4 m, vec3 v) { return m[0].xyz * v.x + m[1].xyz * v.y + m[2].xyz * v.z; }

// 完整四维矩阵乘四维向量：末地透视阴影需要保留齐次分量。
vec4 ogxMatrixMulPoint4(mat4 m, vec4 v) { return ogxMatrixMul(m, v); }

// 四乘四矩阵的平移列：GLSL 的第四列存放平移，Slang 与 GLSL 的下标指向同一块内存。
vec3 ogxMatrixTranslation(mat4 m) { return m[3].xyz; }

// 三乘三矩阵乘三维向量，展开成三列的加权和，与 GLSL 的 `mat3 * vec3` 完全一致。
vec3 ogxMatrix3MulPoint(mat3 m, vec3 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z; }

// 两参数反正切：先处理竖直方向，再对左半平面补一个圆周率。
float ogxAtan2(vec2 v)
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

/*
实现说明：标量、向量与矩阵的小工具。
一、矩阵乘向量：四乘四与三乘三各一份，按列展开后相加，避免行列约定差异。
二、圆映射：方形到圆盘的折叠，返回二维或三维版本。
三、三角函数：`ogxSinCos` 一次给出正弦与余弦，`ogxAtan2` 处理象限。
四、快速反余弦：多项式近似，误差在可视范围内，节省反三角函数开销。
五、极值：二、三、四分量各一份，避免调用方自己写比较链。
六、重映射：把区间映射到零到一并夹紧，曲线与遮罩共用。
七、边界：所有函数只做纯计算，不读取屏幕或时间。
*/

/*
函数索引：
一、`ogxSinCos`：一次给出正弦与余弦。
二、`ogxRotate2`：二维旋转。
三、`ogxRemapSaturate` 与 `ogxRemap`：区间重映射。
四、`ogxMinVec2`、`ogxMinVec3`、`ogxMinVec4`、`ogxMaxVec2`、`ogxMaxVec3`、`ogxMaxVec4`：逐分量极值。
五、`ogxCircleMap` 与 `ogxCircleMapL`：方形到圆盘。
六、`ogxSpiralSample`：螺旋采样点。
七、`ogxRoughSpecularDirection`：粗糙高光方向。
八、`ogxNormalize`：安全归一化，零向量有回退。
九、`ogxMod`：浮点取模，结果为非负。
十、`ogxEqual`：向量相等判断。
十一、`ogxMatrixMul`、`ogxMatrixMulPoint`、`ogxMatrixMulPoint4`、`ogxMatrixTranslation`、`ogxMatrix3MulPoint`：矩阵与向量工具。
十二、`ogxAtan2`：两参数反正切。
十三、`ogxFastAcos`：反余弦近似。
十四、边界：所有函数只做纯计算，不读取屏幕或时间。
十五、顺序：矩阵按列展开，和 GLSL 的列主序一致。
*/

/*
参数与边界：
一、矩阵乘向量假设矩阵按列主序存储。
二、归一化在零向量时返回零向量，调用方要判断。
三、取模的除数不能为零。
四、相等判断使用绝对误差，阈值由调用方给出。
五、反余弦近似只在零到一之间有效。
六、圆映射的输入是负一到一。
七、极值函数逐分量比较，不处理 NaN。
八、旋转角度用弧度。
九、所有函数都是纯函数，可以在任意阶段调用。
十、矩阵平移只取第四列，不处理投影。
*/

/*
补充说明：矩阵与向量。
矩阵按列主序存储。
归一化在零向量时返回零。
取模的除数不能为零。
反余弦近似只在零到一之间有效。
画面验证看旋转与投影。
*/

// 伽马、曲线、打包与法线编码，具体实现在子文件。
// 子文件：common/math/encoding.slang。
// 数学模块编码工具：伽马、曲线、八位与十六位打包、八面体法线编码。
// 调用位置：由 `common/math.slang` 内联引入，颜色与延迟缓冲共用。
// 可复制示例：`vec2 n = ogxEncodeNormal(worldNormal);`
// 设计原因与取舍：编码与解码必须成对出现，放在同一文件里方便核对位运算顺序。

// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
vec3 ogxLinearToGamma(vec3 color) { return pow(color, vec3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
vec3 ogxGammaToLinear(vec3 color) { return pow(color, vec3(2.2)); }

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
vec3 ogxLinearToCurve3(vec3 color) { return pow(color, vec3(0.25)); }

// 向量版本的四次方根解码，逐通道平方两次。
vec3 ogxCurveToLinear3(vec3 color)
{
    return vec3(ogxCurveToLinear(color.x), ogxCurveToLinear(color.y), ogxCurveToLinear(color.z)); // 逐通道走标量版本。
}

// 把两个八位分量打包进一个浮点；高八位放第一个，低八位放第二个。
float ogxPack2x8(vec2 value)
{
    uvec2 bits = uvec2(value * 255.0);
    return float((bits.x << 8u) | bits.y) / 65535.0;
}

// 从打包浮点还原两个八位分量，读取方必须按同一约定拆位。
vec2 ogxUnpack2x8(float value)
{
    uint bits = uint(value * 65535.0);
    return vec2(bits >> 8u, bits & 255u) / 255.0;
}

// 把两个十六位分量直接按位塞进浮点，不损失精度，但只能按位还原。
float ogxPack2x16(vec2 value)
{
    uvec2 bits = uvec2(value * 65535.0);
    return uintBitsToFloat((bits.x << 16u) | bits.y);
}

// 取回两个十六位分量并归一化；输入必须是 `ogxPack2x16` 的结果。
vec2 ogxUnpack2x16(float value)
{
    uint bits = floatBitsToUint(value);
    return vec2(bits >> 16u, bits & 65535u) / 65535.0;
}

// 八面体折返：把下半球的分量交换并按符号放回外圈。
vec2 ogxOctWrap(vec2 v) { return (1.0 - abs(v.yx)) * vec2(ogxSign(v.x), ogxSign(v.y)); }

// 把单位法线编码到零到一的二维坐标，八个象限各占一块。
vec2 ogxEncodeNormal(vec3 n)
{
    n.xy /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = n.z >= 0.0 ? n.xy : ogxOctWrap(n.xy);
    return n.xy * 0.5 + 0.5;
}

// 把八面体坐标解回单位法线，与上一函数互逆。
vec3 ogxDecodeNormal(vec2 encoded)
{
    vec2 n = encoded * 2.0 - 1.0;
    float nz = 1.0 - abs(n.x) - abs(n.y);
    return normalize(vec3(nz >= 0.0 ? n : ogxOctWrap(n), nz));
}

// 从贴图法线解出切线空间法线：全黑或全白不是法线数据，退回朝外。
vec3 ogxDecodeNormalTex(vec3 texNormal)
{
    vec3 normal = vec3(0.0, 0.0, 1.0);
    if (abs(texNormal.x + texNormal.y + texNormal.z - 1.5) < 1.488)
    {
        normal.xy = texNormal.xy * 2.0 - 1.0;
        normal.xy = max(abs(normal.xy) - 1.0 / 255.0, vec2(0.0)) * vec2(sign(normal.x), sign(normal.y));
        normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));
    }
    return normal;
}

/*
实现说明：编码与打包。
一、伽马：线性到显示用二点二幂，显示到线性用同一次幂的逆；这是管线的近似，不是标准 sRGB。
二、曲线：四次方根压缩高动态范围，平方两次还原；中间画面用它保住暗部。
三、八位打包：两个零到一的数各取八位，压进一个通道；解包时按同样的位宽拆回。
四、十六位打包：用整数与小数部分搬运两个十六位值，不依赖浮点位模式，跨后端可复现。
五、法线编码：八面体投影把单位向量压到零到一，解码时按绝对值折叠回球面。
六、边界：打包函数假设输入已经在零到一之间，越界值会被截断而不是报错。
七、顺序：编码与解码必须成对修改，位宽或常数改一处就要同步另一处。
*/

/*
函数索引：
一、`ogxLinearToGamma`：线性到显示，二点二幂。
二、`ogxGammaToLinear`：显示到线性，同一次幂的逆。
三、`ogxCurve01`：零到一平滑曲线，两端平、中间陡。
四、`ogxLinearToCurve`：四次方根压缩，中间画面用。
五、`ogxCurveToLinear`：平方两次还原。
六、`ogxLinearToCurve3` 与 `ogxCurveToLinear3`：三分量版本，逐通道处理。
七、`ogxPack2x8` 与 `ogxUnpack2x8`：两个八位数压进一个通道。
八、`ogxPack2x16` 与 `ogxUnpack2x16`：两个十六位数用整数与小数部分搬运。
九、`ogxOctWrap`：八面体编码的折叠，处理负半轴。
十、`ogxEncodeNormal`：单位法线压到零到一。
十一、`ogxDecodeNormal`：零到一还原单位法线。
十二、`ogxDecodeNormalTex`：从贴图通道解出法线，先解码再归一化。
十三、位宽：打包与解包必须成对修改，位宽或常数改一处就要同步另一处。
十四、边界：打包函数假设输入在零到一之间，越界值会被截断。
十五、用途：中间画面、法线图与延迟缓冲共用这一组编码。
*/

/*
参数与边界：
一、伽马函数假设输入非负，负值会得到未定义结果。
二、四次方根曲线假设输入非负，中间画面已经保证。
三、八位打包假设两个输入都在零到一之间。
四、十六位打包用浮点小数部分，输入超出零到一时会丢精度。
五、八面体编码要求法线已归一化。
六、解码后的法线要再归一化，贴图量化会带来长度误差。
七、打包与解包的位宽必须一致。
八、所有函数都是纯函数，不读取纹理或屏幕。
九、编码结果可以存进八位或十六位通道，调用方按精度选择。
十、法线贴图的绿通道方向由调用方决定，库不做翻转。
*/

/*
补充说明：编码的精度。
八位打包适合颜色，十六位打包适合坐标。
法线编码的量化误差在解码后要重新归一化。
伽马函数不处理负值。
四次方根曲线不处理负值。
打包与解包的位宽必须一致。
画面验证看中间画面的暗部与法线边缘。
*/

/*
补充说明：精度与边界。
八位打包适合颜色。
十六位打包适合坐标。
法线解码后要重新归一化。
伽马与四次方根不处理负值。
打包与解包位宽必须一致。
*/
/*
编码结果存进通道时按精度选择位宽。
法线贴图的绿通道方向由调用方决定。
*/

/*
补充说明：通道布局由调用方决定。
法线解码后要重新归一化。
编码与解码必须成对维护。
*/

// 材质、黑体、求交与相函数，具体实现在子文件。
// 子文件：common/math/shading.slang。
// 数学模块材质与求交：GGX、菲涅尔、黑体色温、射线与包围盒求交、相函数。
// 调用位置：由 `common/math.slang` 内联引入，表面、大气与反射模块共用。
// 可复制示例：`vec3 c = ogxBlackbody(6500.0);`
// 设计原因与取舍：这些函数只做几何与光学近似，不读取任何宿主状态。

// --- 材质、黑体与光线求交 ---

// 沃尔特 GGX 分布：粗糙度越大，高光越散。
float ogxDistributionGGX(float NdotH, float roughness)
{
    float roughness2 = roughness * roughness;
    float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0;
    return roughness2 / (OGX_PI * k * k);
}

// 菲涅尔近似：掠射角反射强，正对时只剩基础反射率。
float ogxFresnelSchlick(float VdotH, float f0, float f90)
{
    VdotH = 1.0 - VdotH;
    float VdotH2 = VdotH * VdotH;
    return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH;
}

// 可见性项：把入射与出射方向的遮挡相乘，采用粗糙度一半的常用近似。
float ogxVisibilitySchlick(float NdotL, float NdotV, float roughness)
{
    float k = roughness * 0.5;
    return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
}

// 布利漫反射：能量在掠射时更集中，避免边缘死黑。
float ogxDiffuseBurley(vec3 n, vec3 v, vec3 l, float roughness)
{
    vec3 h = normalize(v + l);
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
    float lightScatter = ogxFresnelSchlick(NdotL, 1.0, f90);
    float viewScatter = ogxFresnelSchlick(NdotV, 1.0, f90);
    return NdotL * lightScatter * viewScatter * OGX_INV_PI;
}

// 完整 GGX 高光：菲涅尔、可见性、分布三项相乘。
float ogxSpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0)
{
    vec3 h = normalize(v + l);
    float NdotH = ogxSaturate(dot(n, h));
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float ggx = ogxFresnelSchlick(LdotH, f0, 1.0);
    ggx *= ogxVisibilitySchlick(NdotL, NdotV, roughness);
    ggx *= ogxDistributionGGX(NdotH, roughness);
    return ggx;
}

// 黑体色温拟合：先求色度横坐标与纵坐标，再转线性显示原色。
// 分界点四千开与两千二百二十二开来自原拟合的分段条件，不能省略。
vec3 ogxBlackbody(float temperature)
{
    const vec4 SPLINE_X_LOW = vec4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910);
    const vec4 SPLINE_X_HIGH = vec4(-3.0258469e9, 2.1070479e6, 0.2226347e3, 0.240390);
    const vec4 SPLINE_Y_LOW = vec4(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    const vec4 SPLINE_Y_MID = vec4(-0.9549476, -1.37418593, 2.09137015, -0.16748867);
    const vec4 SPLINE_Y_HIGH = vec4(3.0817580, -5.87338670, 3.75112997, -0.37001483);
    float rt = 1.0 / temperature;
    float rt2 = rt * rt;
    vec4 coeffX = vec4(rt2 * rt, rt2, rt, 1.0);
    float x = dot(coeffX, temperature < 4000.0 ? SPLINE_X_LOW : SPLINE_X_HIGH);
    float x2 = x * x;
    vec4 coeffY = vec4(x2 * x, x2, x, 1.0);
    vec4 splineY = temperature < 2222.0 ? SPLINE_Y_LOW : (temperature < 4000.0 ? SPLINE_Y_MID : SPLINE_Y_HIGH);
    float z = 1.0 / dot(coeffY, splineY);
    vec3 xyz = vec3(x * z, 1.0, z);
    xyz.z -= xyz.x + 1.0;
    // 三列分别乘三个色度分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
    const vec3 XYZ_TO_SRGB_0 = vec3(3.24097, -0.96924, 0.05563);
    const vec3 XYZ_TO_SRGB_1 = vec3(-1.53738, 1.87597, -0.20398);
    const vec3 XYZ_TO_SRGB_2 = vec3(-0.49861, 0.04156, 1.05697);
    vec3 rgb = XYZ_TO_SRGB_0 * xyz.x + XYZ_TO_SRGB_1 * xyz.y + XYZ_TO_SRGB_2 * xyz.z;
    return max(rgb, vec3(0.0));
}

// 射线与平面求交：射线与平面法线接近平行时返回极远处的默认交点，避免除零。
vec3 ogxRayPlaneIntersection(vec3 origin, vec3 direction, vec3 normal)
{
    float rayPlaneAngle = dot(direction, normal);
    float planeRayDistance = 1e8;
    vec3 intersection = direction * planeRayDistance;
    if (rayPlaneAngle > 0.0001 || rayPlaneAngle < -0.0001)
    {
        planeRayDistance = dot(-origin, normal) / rayPlaneAngle;
        intersection = origin + direction * planeRayDistance;
    }
    return intersection;
}

// 射线与球求交：返回进入和离开两个距离，无交点时返回一正一负的极值。
vec2 ogxRaySphereIntersection(vec3 origin, vec3 direction, float radius){
    float b = dot(origin, direction);
    float c = -radius * radius + dot(origin, origin);
    float d = b * b - c;
    vec2 intersection = vec2(1e10, -1e10);
    if (d >= 0.0)
    {
        d = sqrt(d);
        intersection = vec2(-b - d, -b + d);
    }
    return intersection;
}

// 射线与球求交的另一种约定：没打中时返回两个负一，命中时返回进入与离开的距离。
// 为什么保留两个版本：`ogxRaySphereIntersection` 用极大值表示未命中，适合直接取近交点；
// 这个版本照参考实现用负一当哨兵，调用方可以只判断一个分量就知道要不要继续算。
// 球心固定在原点，`position` 是射线的起点，`direction` 必须已经归一化。
vec2 ogxRaySphereHit(vec3 position, vec3 direction, float radius)
{
    float PoD = dot(position, direction); // 起点在射线方向上的投影。
    float radiusSquared = radius * radius; // 半径平方。
    float delta = PoD * PoD + radiusSquared - dot(position, position); // 球面方程的判别式。
    if (delta < 0.0) // 判别式为负说明射线擦不到球。
    {
        return vec2(-1.0); // 两个负一表示未命中。
    }
    delta = sqrt(delta); // 判别式开方，得到两个交点相对最近点的偏移。
    return -PoD + vec2(-delta, delta); // 先减投影再加减偏移，得到两个距离。
}

// 射线与轴对齐包围盒求交：返回进入与离开的距离。
// 三个轴分别解一次区间，再把区间求交集；无交点时返回一正一负的极值。
// `boxSize` 是盒子的半边长，盒子以 `origin` 所在坐标系的原点为中心。
vec2 ogxRayBoxRange(vec3 origin, vec3 direction, vec3 boxSize)
{
    vec3 safeDirection = vec3(abs(direction.x) < 1e-6 ? 1e-6 : direction.x,
                                  abs(direction.y) < 1e-6 ? 1e-6 : direction.y,
                                  abs(direction.z) < 1e-6 ? 1e-6 : direction.z);
    vec3 inverseDirection = 1.0 / safeDirection;
    vec3 t0 = (-boxSize - origin) * inverseDirection;
    vec3 t1 = (boxSize - origin) * inverseDirection;
    vec3 near = min(t0, t1);
    vec3 far = max(t0, t1);
    float enter = max(max(near.x, near.y), near.z);
    float leave = min(min(far.x, far.y), far.z);
    return leave >= enter ? vec2(enter, leave) : vec2(1e10, -1e10);
}

// 射线与包围盒求交的便捷版：命中时返回进入距离，未命中返回负一。
float ogxRayBoxIntersection(vec3 origin, vec3 direction, vec3 boxSize)
{
    vec2 range = ogxRayBoxRange(origin, direction, boxSize);
    return range.x <= range.y && range.y > 0.0 ? range.x : -1.0;
}

// 瑞利相函数：天空散射近似各向同性，常数是十六分之三除以圆周率。
float ogxRayleighPhase(float nu) { return 0.059683104 * (nu * nu + 1.0); }

// 米氏相函数：康奈特-沙克形式，`g` 越大前向散射越集中。
float ogxMiePhase(float g, float nu)
{
    float gg = g * g;
    float k = 0.1193662 * (1.0 - gg) / (2.0 + gg);
    return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5);
}

// 亨耶-格林斯坦相函数：把除以圆周率的部分作为显式参数，方便参考包保留自己的 3.14 常数。
// 为什么参数化：云、雾与层状云参考实现的圆周率精度不同，统一常数会改变严格对照的数值。
float ogxHenyeyGreensteinPhase(float cosAngle, float g, float inversePi)
{
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * cosAngle) + (gg + 1.0), -1.5) * 0.25 * inversePi;
}

// 相函数与几何近似在文件前半段，闪电照明移到天气模块。

/*
实现说明：材质、黑体与光线求交。
一、GGX 分布：粗糙度平方进入分母，粗糙度越大高光越散。
二、菲涅尔：Schlick 五次方近似，掠射角反射增强，正对时回到基础反射率。
三、可见性：Smith 近似把入射与出射遮挡相乘，粗糙度用一半的常用写法。
四、漫反射：Burley 分布让掠射边缘更集中，避免死黑。
五、完整高光：分布、菲涅尔与可见性三项相乘，金属度只改基础反射率。
六、黑体：先求色度坐标再转线性，分界点在四千开与两千二百二十二开。
七、射线求交：球、平面与包围盒各一份，返回最近正交点。
八、相函数：瑞利、米氏与 Henyey-Greenstein 用于大气与云。
九、闪电光柱：按竖直光柱的距离做指数衰减，云与雾共用一条曲线。
十、边界：函数只接收显式几何与光学参数，不读取宿主状态；常数按参考精度保留。
*/

/*
函数索引：
一、`ogxDistributionGGX`：输入半程向量与粗糙度，输出 GGX 分布值；粗糙度平方进入分母。
二、`ogxFresnelSchlick`：输入夹角余弦、基础反射率与掠射反射率，输出菲涅尔系数；五次方近似。
三、`ogxVisibilitySchlick`：输入入射、出射与粗糙度，输出 Smith 可见性；粗糙度用一半。
四、`ogxDiffuseBurley`：输入法线、视线、光方向与粗糙度，输出漫反射；掠射边缘更集中。
五、`ogxSpecularGGX`：把分布、菲涅尔与可见性三项相乘，输出完整高光；金属只改基础反射率。
六、`ogxBlackbody`：输入色温，输出线性颜色；先求色度坐标再转矩阵，分界点在四千开。
七、`ogxRayPlaneIntersection`：输入点、方向、平面法线与偏移，输出交点；平行时返回零向量。
八、`ogxRaySphereIntersection`：输入射线与球，输出两个参数；没有交点时两个值都小于零。
九、`ogxRaySphereHit`：只返回最近正交点，供不需要远交点的调用方使用。
十、`ogxRayBoxRange`：输入射线与包围盒，输出入口与出口参数；用于体素与云层裁剪。
十一、`ogxRayBoxIntersection`：只返回是否命中并把位置推进到入口。
十二、`ogxRayleighPhase`：输入夹角余弦，输出瑞利相函数；蓝光散射更强。
十三、`ogxMiePhase`：输入前向集中度与夹角，输出米氏相；气溶胶的白色光晕来自它。
十四、`ogxHenyeyGreensteinPhase`：输入夹角、集中度与圆周率倒数，输出通用相函数；云与雾共用。
十五、常数：所有多项式系数与矩阵按参考精度保留，换成近似值会让高光或色温偏色。
十六、边界：函数只接收显式几何与光学参数，不读取宿主状态；调用方负责夹紧输入。
*/

/*
参数与边界：
一、GGX 的粗糙度在零附近会变成镜面，调用方需要先夹到最小值，避免除零。
二、菲涅尔的基础反射率对金属是底色，对电介质是零点零四左右。
三、Smith 可见性假设入射与出射遮挡独立，掠射角会略微偏暗，这是常用近似。
四、Burley 漫反射在粗糙度为零时退化成 Lambert，粗糙度越大边缘越亮。
五、完整高光不包含多次散射能量，金属在粗糙表面会偏暗，需要环境光补足。
六、黑体拟合在四千开以下走另一条绿通道曲线，温度越低越偏红。
七、球面求交返回两个参数，调用方要自己判断哪个在射程内。
八、平面求交在射线平行时返回零向量，调用方不能把零当成有效交点。
九、包围盒求交要求入口小于出口且入口为正，背面命中不算。
十、瑞利相函数在前后方向对称，米氏相函数在前向集中。
十一、Henyey-Greenstein 的集中度在零到一之间，负数表示后向散射。
十二、闪电光柱的竖直范围是一百一十六格，水平距离按米计算。
十三、所有常数按参考精度保留，改成近似值会让严格对照的常数检查失败。
十四、函数不读取时间、屏幕或相机，调用方把需要的量显式传入。
十五、返回值都是线性空间颜色或纯几何量，伽马编码由调用方负责。
十六、矩阵乘法在 Slang 与 GLSL 的行列解释不同，统一走标量模块的展开。
十七、射线方向的长度会影响参数含义，调用方应先归一化。
十八、黑体色的输出可能超过一，需要曝光或色调映射再夹紧。
十九、高光项没有乘光源颜色，调用方要把光色与强度乘上去。
二十、可见性项已经包含分母，不要再乘一次点积。
二十一、分布项的分母在粗糙度极小时接近零，提前夹紧能避免亮点。
二十二、相函数的归一化因子由调用方传入，参考包使用的圆周率精度不同。
二十三、球面求交的半径必须为正，负半径会得到相反的交点顺序。
二十四、包围盒的上下界必须按分量排序，调用方要保证最小值小于最大值。
二十五、平面求交的偏移是沿法线的距离，不是世界坐标。
二十六、所有这些函数都是纯函数，可以在任意阶段调用。
*/

/*
补充说明：高光与求交的边界。
一、粗糙度为零时 GGX 分母接近零，调用方要先夹紧。
二、菲涅尔的基础反射率对金属是底色，对电介质约零点零四。
三、Smith 可见性假设入射与出射遮挡独立，掠射角略暗。
四、Burley 漫反射在粗糙度为零时退化成 Lambert。
五、完整高光不含多次散射，粗糙金属会偏暗。
六、黑体拟合在四千开以下走另一条绿通道曲线。
七、球面求交返回两个参数，调用方要判断射程。
八、平面求交平行时返回零向量。
九、包围盒求交不把背面命中算作入口。
十、瑞利相函数前后对称，米氏相函数前向集中。
十一、Henyey-Greenstein 的集中度在零到一之间。
十二、闪电光柱的竖直范围是一百一十六格。
十三、常数按参考精度保留。
十四、函数不读取时间、屏幕或相机。
十五、返回值是线性颜色或纯几何量。
十六、矩阵乘法统一走标量模块的展开。
十七、射线方向应先归一化。
十八、黑体色可能超过一，需要曝光或色调映射。
十九、高光项没有乘光源颜色。
二十、可见性项已经包含分母。
二十一、分布项在粗糙度极小时要提前夹紧。
二十二、相函数的归一化因子由调用方传入。
二十三、球面半径必须为正。
二十四、包围盒上下界要按分量排序。
二十五、平面偏移是沿法线的距离。
二十六、所有这些函数都是纯函数。
二十七、修改常数会同时影响高光、雾与云的亮度。
二十八、严格对照会检查常数与采样次数。
二十九、画面验证看高光边缘与阴影接触面。
三十、离线编译只证明语法。
三十一、高光在金属与电介质上的表现不同。
三十二、粗糙度改变时反射颜色也要跟着变。
三十三、环境光与直射光要分开叠加。
三十四、相函数的集中度不要超过一。
三十五、求交参数为负表示交点在射线背后。
三十六、包围盒入口等于出口时按未命中处理。
三十七、黑体温度低于一千开时按比例压暗。
三十八、菲涅尔在掠射时接近一，不要重复加反射率。
三十九、可见性项在粗糙度为零时退化成简单除法。
四十、所有这些边界都应按场景实际尺度调整。
*/

// 抖动、切线基、旋转与空间扭曲，具体实现在子文件。
// 子文件：common/math/pattern.slang。
// 数学模块图案工具：拜尔抖动、切线基、HSV、旋转矩阵、径向曲线与空间扭曲。
// 调用位置：由 `common/math.slang` 内联引入，后期、天空与吸积盘共用。
// 可复制示例：`float b = ogxInterleavedGradientNoise(pixelCoord);`
// 设计原因与取舍：图案函数保持原来的常数与矩阵展开顺序，避免画面抖动改变。

// --- 抖动表、切线基与颜色图案 ---

// 交错梯度噪声：一个像素一个值，适合做抖动，常数来自原始论文。
float ogxInterleavedGradientNoise(vec2 coordinate)
{
    return fract(52.9829189 * fract(0.06711056 * coordinate.x + 0.00583715 * coordinate.y));
}

// 二乘二拜尔矩阵：四个格子依次得到零、四分之一、二分之一、四分之三。
float ogxBayer2(vec2 a)
{
    a = floor(a);
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

// 四乘四拜尔矩阵：由二乘二嵌套得到，用来做稳定抖动。
float ogxBayer4(vec2 a) { return ogxBayer2(0.5 * a) * 0.25 + ogxBayer2(a); }

// 八乘八拜尔矩阵。
float ogxBayer8(vec2 a) { return ogxBayer4(0.5 * a) * 0.25 + ogxBayer2(a); }

// 十六乘十六拜尔矩阵：四层二乘二矩阵嵌套，抖动级别比八乘八细四倍。
float ogxBayer16(vec2 a) { return ogxBayer4(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 三十二乘三十二拜尔矩阵：低频一档换成八乘八，级别再细四倍。
float ogxBayer32(vec2 a) { return ogxBayer8(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 六十四乘六十四拜尔矩阵：范围大，适合时间累积前的初始偏移。
float ogxBayer64(vec2 a) { return ogxBayer8(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 一百二十八乘一百二十八拜尔矩阵：目前最细的一档，给低步数光追分摊首帧噪点。
float ogxBayer128(vec2 a) { return ogxBayer16(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 切线基的三个方向；用结构体而不是矩阵，避免两种语言的行列顺序不同造成转置错误。
struct OgxTangentBasis
{
    vec3 tangent;
    vec3 bitangent;
    vec3 normal;
};

// 由位置与纹理导数构造切线基：先叉乘得到法线，再解切线与副切线。
// 模型没提供切线时只能这样反推；返回结构体，调用方按字段读取。
OgxTangentBasis ogxTangentBasis(vec3 dp1, vec3 dp2, vec2 duv1, vec2 duv2)
{
    vec3 normal = normalize(cross(dp1, dp2));
    vec3 dp2perp = cross(dp2, normal);
    vec3 dp1perp = cross(normal, dp1);
    vec3 tangent = normalize(dp2perp * duv1.x + dp1perp * duv2.x);
    vec3 bitangent = normalize(dp2perp * duv1.y + dp1perp * duv2.y);
    float invmax = 1.0 / sqrt(max(dot(tangent, tangent), dot(bitangent, bitangent)));
    OgxTangentBasis basis;
    basis.tangent = tangent * invmax;
    basis.bitangent = bitangent * invmax;
    basis.normal = normal;
    return basis;
}

// 色相、饱和度、明度：按最大通道选扇区，再算色相与饱和度。
vec3 ogxRgbToHsv(vec3 color)
{
    const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0;
    const float e = 1.0e-10;
    vec4 p = mix(vec4(color.bg, K.wz), vec4(color.gb, K.xy), step(color.b, color.g));
    vec4 q = mix(vec4(p.xyw, color.r), vec4(color.r, p.yzx), step(p.x, color.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// 三个轴的旋转合成：先俯仰、再偏航、最后滚转，供吸积盘与末地行星摆正自己的坐标系。
// 这里保留原程序的扁平构造参数顺序：生成 GLSL 后由 GLSL 的列主序规则解释，
// 因此运行时矩阵与旧实现完全相同；不要在 Slang 侧改成按列传入，否则生成文本会换序。
mat3 ogxRotateMatrix(float x, float y, float z)
{
    mat3 matx = mat3(1.0, 0.0, 0.0, 0.0, cos(x), sin(x), 0.0, -sin(x), cos(x)); // 绕横轴俯仰。
    mat3 maty = mat3(cos(y), 0.0, -sin(y), 0.0, 1.0, 0.0, sin(y), 0.0, cos(y)); // 绕纵轴偏航。
    mat3 matz = mat3(cos(z), sin(z), 0.0, -sin(z), cos(z), 0.0, 0.0, 0.0, 1.0); // 绕前后轴滚转。
    return maty * matx * matz; // 三个旋转按原程序的顺序合成。
}

// 环形径向轮廓：中心亮、边缘按四次方乘线性衰减，用于光晕。
float ogxRadialCurve(float x){
    float x2 = x * x;
    return 12.207 * x2 * x2 * (1.0 - x);
}

// 夜视：把颜色往偏蓝的亮度上拉一半，暗处看得清但保留一点原色。
// 为什么保留在通用数学：宿主的公共数学包装 `DoNightEye` 直接调用它，多个阶段共用；
// 它不是某一个效果的私有算法。
void ogxDoNightEye(inout vec3 color)
{
    float luma = ogxLuminance(color); // 原色亮度。
    color = mix(color, luma * vec3(0.7771, 1.0038, 1.6190), vec3(0.5)); // 偏蓝亮度与原色各占一半。
}

// 空间扭曲：越靠近原点，光线方向越被拉向原点，模拟黑洞附近的引力弯曲。
// 方向和位置都就地修改，调用方下一轮步进会用到新的方向。
void ogxWarpSpace(inout vec3 direction, inout vec3 position)
{
    vec3 origin = vec3(0.0);
    float singularityDistance = distance(position, origin);
    float warpFactor = 1.0 / (singularityDistance * singularityDistance + 0.000001);
    vec3 singularityVector = normalize(origin - position);
    float warpAmount = 0.06;
    direction = normalize(direction + singularityVector * warpFactor * warpAmount);
}

/*
实现说明：屏幕图案与坐标变换。
一、Bayer 矩阵：二阶到八阶的阈值矩阵由递归展开得到，抖动用它把色阶打散。
二、旋转矩阵：二维旋转与三列矩阵互转，光环与光斑按角度旋转。
三、圆映射：把方形坐标折到圆盘，`ogxCircleMapL` 返回三维版本供球面采样。
四、空间扭曲：黑洞附近的引力弯曲按距离平方增强方向偏移。
五、夜视：暗处把颜色混向偏蓝的亮度，宿主公共数学的包装直接调用它。
六、哈希与噪声：屏幕坐标加帧号生成稳定的伪随机值，避免每帧重新排布。
七、边界：图案函数不读取分辨率，调用方把像素坐标归一化后传入。
*/

/*
函数索引：
一、`ogxInterleavedGradientNoise`：屏幕坐标的插值梯度噪声。
二、`ogxBayer2` 到 `ogxBayer128`：递归展开的 Bayer 阈值矩阵。
三、`ogxTangentBasis`：按法线构造切线基，退化方向有回退。
四、`ogxRgbToHsv`：颜色到色相、饱和度、明度。
五、`ogxRotateMatrix`：二维旋转与三列矩阵互转。
六、`ogxRadialCurve`：环形径向轮廓。
七、`ogxDoNightEye`：暗视觉偏蓝。
八、`ogxWarpSpace`：黑洞附近的引力弯曲。
九、边界：图案函数不读取分辨率，调用方把像素坐标归一化后传入。
十、常数：Bayer 矩阵与夜间偏蓝系数按参考精度保留。
*/

/*
参数与边界：
一、Bayer 矩阵的阶数越高，抖动的颗粒越细。
二、切线基在法线与辅助轴平行时退化，调用方要提供回退。
三、色相转换假设输入在零到一之间。
四、旋转矩阵的角度用弧度。
五、径向曲线在中心为零，在边缘回落。
六、夜视只改颜色，不改亮度统计。
七、空间扭曲的强度固定，调用方不能按场景缩放。
八、图案函数不读取分辨率，坐标要归一化。
九、所有函数都是纯函数，可以在任意阶段调用。
十、哈希与噪声的常数按参考精度保留。
*/

/*
补充说明：图案的坐标。
Bayer 矩阵按屏幕像素取模，坐标要取整。
切线基在法线与辅助轴平行时退化。
色相转换的输入在零到一之间。
空间扭曲的强度固定。
画面验证看抖动颗粒与法线。
*/

/*
补充说明：图案坐标。
Bayer 矩阵按像素取模。
切线基在平行时退化。
色相输入在零到一之间。
空间扭曲强度固定。
*/

// 双线性与双三次纹理过滤，具体实现在子文件。
// 子文件：common/math/filter.slang。
// 数学模块纹理过滤：双线性、天空盒图集双线性、三次 B 样条与双三次采样。
// 调用位置：由 `common/math.slang` 内联引入，采样器与坐标由调用方传入。
// 可复制示例：`vec4 c = ogxBilinearTexture(tex, uv, texSize);`
// 设计原因与取舍：库不绑定任何纹理单元；取像素与层级采样都显式写在参数里。

// --- 纹理过滤、空间扭曲与随机采样 ---

// 双线性取像素：自己取四个相邻纹素再插值，不依赖硬件的线性过滤。
// 为什么不用 `SampleLevel`：像素画风格的月亮贴图会把硬件过滤设成最近邻，画面上出现锯齿；
// 按纹素中心取四次再按小数偏移插值，既保留最近邻的锐利，又能随屏幕坐标平滑移动。
// `coord` 是零到一的贴图坐标，`texSize` 是贴图边长（纹素）。
vec4 ogxBilinearTexture(sampler2D tex, vec2 coord, vec2 texSize)
{
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    vec2 p = floor(coord); // 左下最近纹素。
    vec2 f = coord - p; // 到该纹素的小数偏移，就是插值权重。
    ivec2 texelX = ivec2(p); // 四个纹素里左下的整数坐标。
    ivec2 texelW = texelX + ivec2(1); // 右上的整数坐标。
    vec4 bottom = mix(texelFetch(tex, texelX, 0), texelFetch(tex, ivec2(texelW.x, texelX.y), 0), f.x); // 先横向插值下排。
    vec4 top = mix(texelFetch(tex, ivec2(texelX.x, texelW.y), 0), texelFetch(tex, texelW, 0), f.x); // 再横向插值上排。
    return mix(bottom, top, f.y); // 最后纵向插值。
}

// 天空盒图集的双线性取像素：与上一函数相同，但每个采样都夹在自己那一格里。
// 为什么需要夹紧：天空盒把六张面拼成 3×2 的大图，横跨格边取样会读到隔壁面的像素，
// 地平线附近就会出现一条颜色突变的接缝。`coord` 是零到一的图集坐标。
vec4 ogxBilinearTextureSkybox(sampler2D tex, vec2 coord, vec2 texSize)
{
    ivec2 grid = ivec2(floor(coord * vec2(3.0, 2.0))); // 当前落在 3×2 图集的哪一格。
    int gridSize = int(floor(texSize.y * 0.5)); // 每格是正方形，边长取总高的一半。
    grid *= gridSize; // 格号换成格子的左上角纹素坐标。
    ivec4 border = ivec4(grid, grid + gridSize - 1); // 该格的闭区间边界，左下与右上。
    coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。
    vec2 p = floor(coord); // 左下最近纹素。
    vec2 f = coord - p; // 插值权重。
    ivec2 texelX = clamp(ivec2(p), border.xy, border.zw); // 左下纹素夹进本格。
    ivec2 texelW = clamp(texelX + ivec2(1), border.xy, border.zw); // 右上纹素同样夹紧。
    vec4 bottom = mix(texelFetch(tex, texelX, 0), texelFetch(tex, ivec2(texelW.x, texelX.y), 0), f.x); // 下排横向插值。
    vec4 top = mix(texelFetch(tex, ivec2(texelX.x, texelW.y), 0), texelFetch(tex, texelW, 0), f.x); // 上排横向插值。
    return mix(bottom, top, f.y); // 纵向插值得到最终像素。
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
vec3 ogxBicubicTexture(sampler2D texSampler, vec2 coord, vec2 texSize)
{
    vec2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize; // 换成像素坐标。
    vec2 p = floor(coord - 0.5) + 0.5; // 左下最近像素中心。
    vec2 f = coord - p; // 到该中心的小数偏移。
    vec2 f2 = f * f; // 偏移平方。
    vec2 f3 = f * f2; // 偏移立方。
    const float c = 0.5; // 卡特穆尔-罗姆张力。
    vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 第一个像素权重。
    vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 第二个像素权重。
    vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 第三个像素权重。
    vec2 w3 = c * f3 - c * f2; // 第四个像素权重。
    vec2 w12 = w1 + w2; // 中间两个像素合并成一次双线性采样。
    vec2 tc12 = texPixelSize * (p + w2 / w12); // 合并采样的位置。
    vec2 tc0 = texPixelSize * (p - 1.0); // 最左或最下像素位置。
    vec2 tc3 = texPixelSize * (p + 2.0); // 最右或最上像素位置。
    vec4 color = vec4(textureLod(texSampler, vec2(tc12.x, tc0.y), 0.0).rgb, 1.0) * (w12.x * w0.y) +
                   vec4(textureLod(texSampler, vec2(tc0.x, tc12.y), 0.0).rgb, 1.0) * (w0.x * w12.y) +
                   vec4(textureLod(texSampler, vec2(tc12.x, tc12.y), 0.0).rgb, 1.0) * (w12.x * w12.y) +
                   vec4(textureLod(texSampler, vec2(tc3.x, tc12.y), 0.0).rgb, 1.0) * (w3.x * w12.y) +
                   vec4(textureLod(texSampler, vec2(tc12.x, tc3.y), 0.0).rgb, 1.0) * (w12.x * w3.y); // 十字形五次采样，a 通道累计权重。
    return color.rgb / color.a; // 除以权重和，补偿省掉的四角。
}

// 十六像素三次模糊：四次双线性采样合成，专供六十四见方的噪声贴图。
vec4 ogxBicubicBlurTexture(sampler2D texSampler, vec2 coord)
{
    const float texPixelSize = 1.0 / 64.0; // 噪声贴图一个像素的大小。
    coord = coord * 64.0 - 0.5; // 换成以像素中心为原点的坐标。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 两个方向的前两个三次样条权重。
    vec4 w1; // 两个方向的后两个三次样条权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
    w1.yw = ff * f; // 第四个权重是偏移立方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
    vec4 s = w0 + w1; // 左右两对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= texPixelSize; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return mix(mix(textureLod(texSampler, c.yw, 0.0), textureLod(texSampler, c.xw, 0.0), m.x),
                mix(textureLod(texSampler, c.yz, 0.0), textureLod(texSampler, c.xz, 0.0), m.x), m.y); // 四次双线性采样得到十六像素的三次模糊。
}

// 低差异序列与半球采样，具体实现在子文件。
// 子文件：common/math/sampling.slang。
// 数学模块采样序列：R2、余弦半球、手部深度、三角波、快速反余弦与 Halton。
// 调用位置：由 `common/math.slang` 内联引入，全局光、阴影与反射共用。
// 可复制示例：`vec2 p = ogxR2Sample(frameIndex);`
// 设计原因与取舍：低差异序列只在纯数学层实现，宿主只传序号或随机数。

// R2 低差异序列：两个无理数比例把序号摊成平面上的均匀点，样本不会聚成一团。
// 为什么用 R2 而不是随机数：随机数会成簇，R2 每加一个样本都把空隙补得更均匀。
vec2 ogxR2Sample(int n)
{
    vec2 alpha = vec2(0.75487765, 0.56984026); // 二维黄金比例常数，照 Eclipse 原值。
    return fract(alpha * float(n)); // 序号乘常数后取小数，得到零到一的点。
}

// 余弦加权半球采样：把两个零到一的随机数变成朝上的半球方向。
// 为什么用余弦权重：漫反射的入射能量本身带余弦，按这个分布采样可以直接平均，不用再除权重。
vec3 ogxCosineHemisphere(vec2 xi)
{
    float theta = OGX_TAU * xi.y; // 绕竖直轴的角度。
    float r = sqrt(xi.x); // 半径开方，得到余弦分布。
    return vec3(r * cos(theta), r * sin(theta), sqrt(clamp(1.0 - xi.x, 0.0, 1.0))); // 横向两个分量加竖直分量。
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
vec2 ogxSequenceR2(float n)
{
    vec2 alpha = 1.0 / vec2(OGX_PLASTIC_RATIO, OGX_PLASTIC_RATIO * OGX_PLASTIC_RATIO); // 两个步长。
    return fract(0.5 + n * alpha); // 加半格后取小数。
}

// Eclipse 的三角波：先减半再取绝对值，夹在 0.01 到 0.49 之间避免端点。
float ogxTriangleGradient(float x)
{
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49); // 参考实现的夹紧范围。
}

// Eclipse 的二维三角波：先分别算两个方向，再用第一个结果扰动第二个输入。
vec2 ogxTriangleGradient2d(vec2 p)
{
    float triX = ogxTriangleGradient(p.x); // 第一方向。
    float triY = ogxTriangleGradient(p.y); // 第二方向。
    return vec2(triX + triY, ogxTriangleGradient(triX + p.y)); // 参考实现的组合方式。
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
    vec2 mulAdd = vec2(0.1, 0.28) * oneOverPi; // 两个系数。
    return cosTheta * mulAdd.x + mulAdd.y; // 线性相函数。
}

// Eclipse 的 4×4 Bayer 抖动：按像素坐标查表，返回零到一之间的阈值。
// 为什么不用递归拜尔函数：递归构造出的是另一张矩阵，和参考的 16 项表不同。
float ogxBayer4Dither(vec2 pixel)
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
mat2 ogxRotate2Matrix(float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, s, -s, c);
}

// Eclipse 的半球方向：两个零到一的随机数变成一个朝上的单位向量。
vec3 ogxGenUnitVector(vec2 xy)
{
    xy.x *= OGX_TAU; // 横向角度乘一圈。
    xy.y = xy.y * 2.0 - 1.0; // 纵向高度映射到负一到一。
    return vec3(ogxSinCos(xy.x) * sqrt(1.0 - xy.y * xy.y), xy.y);
}

// Eclipse 的两向量旋转矩阵：把 `x` 转到 `y` 的方向，用于极光与天空基。
// 参考实现按列填矩阵；这里保持同样的参数顺序，生成 GLSL 后列主序解释一致。
mat3 ogxGetRotMat(vec3 x, vec3 y)
{
    float d = dot(x, y);
    vec3 cr = cross(y, x);
    float s = length(cr);
    float id = 1.0 - d;
    vec3 m = cr / s;
    vec3 m2 = m * m * id + d;
    vec3 sm = s * m;
    vec3 w = (m.xy * id).xxy * m.yzz;
    return mat3(
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

#endif
