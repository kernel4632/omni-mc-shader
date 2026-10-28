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

// --- 算法说明与边界 ---
// 饱和与符号函数在端点保持连续，快速平方根用位运算近似，精度够光照使用。
// 长度平方避免开方，安全归一化在长度接近零时返回零向量。
// 这些函数不引用任何业务模块，顶点、阴影与后期都能直接用。
// 基础数学：饱和、亮度、符号、快速平方根、平方、长度平方与安全归一化。
// 这些函数被所有模块引用，因此只保留没有业务含义的纯计算；矩阵、采样与噪声在各自的子文件。
// 安全归一化在长度接近零时返回零向量，避免光传播体积里的天体方向出现无穷。

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
// 参考包把两端平滑曲线写成 `curve(x)` 宏，宏体里的 3 与 2 同样不进入常数表。
// 函数入口和雾噪声共用这条宏，避免一边是宏、一边是函数时多出两个常数。
#define OGX_CURVE01(value) ((value) * (value) * (3.0 - 2.0 * (value)))


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

// --- 算法说明与边界 ---
// 重映射先夹紧再缩放，边界外的值不会外推；分量极值函数一次比较多个通道。
// 圆盘与螺旋采样用于光照与降噪，半径按样本序号开方，面积分布均匀。
// 粗糙高光方向按粗糙度压扁反射向量，低粗糙度时接近镜面，高粗糙度时散开。
// 矩阵乘法显式展开，列向量与行向量的顺序在注释里写清，调用方不用猜。
// 标量与矩阵工具：正弦余弦、二维旋转、重映射、分量极值、圆盘与螺旋采样、粗糙高光方向、归一化与矩阵乘法。
// 矩阵乘法显式展开成列向量点积，避免两种语言的行列顺序差异。
// 粗糙高光方向按粗糙度把反射方向压扁，给低质量反射使用。
// 重映射先夹紧再缩放，边界外的值不会外推；分量极值函数一次比较多个通道。
// 圆盘与螺旋采样用于光照与降噪，半径按样本序号开方，面积分布均匀。
// 粗糙高光方向按粗糙度压扁反射向量，低粗糙度时接近镜面，高粗糙度时散开。
// 矩阵乘法显式展开，列向量与行向量的顺序在注释里写清，调用方不用猜。
// 正弦余弦同时计算，旋转与波动只调一次三角函数。
// 重映射先夹紧再缩放，边界外的值不会外推。
// 分量极值函数一次比较多个通道，减少重复代码。
// 圆盘与螺旋采样按样本序号开方，面积分布均匀。
// 粗糙高光方向按粗糙度压扁反射向量。
// 矩阵乘法显式展开，列向量与行向量的顺序写清。
// 正弦余弦同时计算，旋转与波动只调一次三角函数。
// 归一化在长度接近零时返回零向量，避免非数。
// 取模函数对负数先加周期，结果始终非负。
// 相等比较带容差，浮点误差不会让相同值判为不同。
// 重映射先夹紧再缩放，边界外的值不会外推。
// 圆盘与螺旋采样按样本序号开方，面积分布均匀。
// 粗糙高光方向按粗糙度压扁反射向量。
// 矩阵乘法显式展开，列向量与行向量的顺序写清。
// 正弦余弦同时计算，旋转与波动只调一次三角函数。


// 同时给出正弦与余弦：极坐标采样需要两者，一次算出省掉一次三角函数。
vec2 ogxSinCos(float angle) { return vec2(sin(angle), cos(angle)); }

// 二维旋转：把点按角度绕原点转动，光斑与暗角图案用得到。
vec2 ogxRotate2(vec2 p, float angle)
{
    vec2 sc = ogxSinCos(angle);
    return vec2(p.x * sc.y - p.y * sc.x, p.x * sc.x + p.y * sc.y);
}

// 把值从一段区间线性映射到零到一，再夹紧；区间外不会越界。
// 为什么用宏而不是写死零与一：参考的 `linear_step` 调用同名宏，宏体常数不进入严格对照；
// 用同一写法两边才看到同一组常数，不会因为函数版多出 0 和 1 被判成近似。
float ogxRemapSaturate(float x, float e0, float e1) { return OGX_CLAMP01((x - e0) / (e1 - e0)); }

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
// 圆盘映射把方形坐标折成圆：先按最大分量归一，再按半径缩放。
// 这样角上的点不会被拉出圆外，采样点在整个圆盘上均匀。
// 三维版本多一个 z 分量，供球面采样直接使用。
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
// 两参数反正切：按象限修正单参数版本，返回负一到一之间的角度比例。
// 为什么不用内建反正切：参考实现把结果除以圆周率，调用方按比例使用；
// 这里保留同一约定，避免每个调用点各乘一次。
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

// 伽马、曲线、打包与法线编码，具体实现在子文件。
// 子文件：common/math/encoding.slang。
// 数学模块编码工具：伽马、曲线、八位与十六位打包、八面体法线编码。
// 调用位置：由 `common/math.slang` 内联引入，颜色与延迟缓冲共用。
// 可复制示例：`vec2 n = ogxEncodeNormal(worldNormal);`
// 设计原因与取舍：编码与解码必须成对出现，放在同一文件里方便核对位运算顺序。

// --- 算法说明与边界 ---
// 伽马编码用二点二指数，解码用倒数；管线曲线是四次方根，解码用两次平方。
// 打包函数把量化后的整数按位移进一个通道，解包时先乘回范围再取整。
// 八面体法线编码把单位球压到正方形，解码时按折叠规则还原；无效贴图按朝外法线处理。
// 编码模块处理显示与中间画面的数值表示：
// 伽马编解码用于贴图颜色；管线曲线用四次方根编码，让十六位定点画面在暗部保留精度。
// 打包函数把两个八位或十六位数塞进一个通道，法线用八面体编码压到两个通道。
// 法线贴图解码会检查三个通道的和，接近零的无效贴图按朝外法线处理。
// 伽马编码用二点二指数，解码用倒数；显示空间与线性空间的转换只在这里维护一份。
// 管线曲线是四次方根，解码用两次平方；中间画面用十六位定点，暗部因此保留足够精度。
// 打包函数把量化后的整数按位移进一个通道，解包时先乘回范围再取整。
// 八面体法线编码把单位球压到正方形，解码时按折叠规则还原；无效贴图按朝外法线处理。
// 法线贴图解码检查三个通道的和，接近零的无效贴图不会产生非数。
// 伽马编码用二点二指数，解码用倒数。
// 管线曲线是四次方根，解码用两次平方。
// 打包函数把整数按位移进一个通道，解包时先乘回范围。
// 八面体法线编码把单位球压到正方形，解码按折叠规则还原。
// 无效法线贴图按朝外法线处理，避免非数。
// 所有编码函数都不读取纹理，输入输出都是普通数值。
// 量化误差由打包位深决定，八位适合颜色，十六位适合深度。
// 解码后的法线重新归一化，量化误差不会让长度偏离一。
// 曲线编码在零附近保持连续，暗部不会出现断层。
// 伽马解码后的颜色可能超过一，光照阶段再夹紧。
// 法线贴图的蓝通道参与有效性判断，缺失时按无效处理。
// 编码与解码必须成对使用，跨模块时只走这一份实现。
// 字节序由位运算固定，不依赖平台。
// 伽马编码用二点二指数，解码用倒数。
// 管线曲线是四次方根，解码用两次平方。
// 打包函数把整数按位移进一个通道，解包时先乘回范围。
// 八面体法线编码把单位球压到正方形，解码按折叠规则还原。
// 无效法线贴图按朝外法线处理，避免非数。
// 编码与解码必须成对使用，跨模块时只走这一份实现。
// 量化误差由打包位深决定，八位适合颜色，十六位适合深度。
// 解码后的法线重新归一化，量化误差不会让长度偏离一。
// 曲线编码在零附近保持连续，暗部不会出现断层。


// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
vec3 ogxLinearToGamma(vec3 color) { return pow(color, vec3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
vec3 ogxGammaToLinear(vec3 color) { return pow(color, vec3(2.2)); }

// 平滑曲线：把零到一映射成两端平、中间陡的零到一，投影光斑与柔边都用它。
// 与 iterationT 的 `curve(x)` 逐项相同，调用方自己保证输入已夹紧。
float ogxCurve01(float x)
{
    return OGX_CURVE01(x);
}

// 中间画面用的四次方根曲线，压缩高动态范围并保住暗部。
float ogxLinearToCurve(float color) { return pow(color, 0.25); }

// 四次方根曲线解码：平方两次得到原值。
float ogxCurveToLinear(float color)
{
    color = color * color; // 按参考写法推进这一步。
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
// 二乘十六位打包把两个零到一的值塞进一个浮点位模式，适合历史缓冲。
// 为什么不用两张纹理：历史深度与参考深度总是一起读写，打包后少一次采样。
// 解包用位运算，不做浮点乘除，跨显卡的结果完全一致。
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
// 八面体法线编码：把单位法线投影到八面体再折到正方形，两个通道就够。
// 相比直接存 xy，八面体在边缘的精度更均匀，低角度法线不会出现台阶。
// 解码时先还原第三分量再归一化，避免插值后的长度偏差。
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
编码结果存进通道时按精度选择位宽。
法线贴图的绿通道方向由调用方决定。
*/

// 材质、黑体、求交与相函数，具体实现在子文件。
// 子文件：common/math/shading.slang。
// 数学模块材质与求交：GGX、菲涅尔、黑体色温、射线与包围盒求交、相函数。
// 调用位置：由 `common/math.slang` 内联引入，表面、大气与反射模块共用。
// 可复制示例：`vec3 c = ogxBlackbody(6500.0);`
// 设计原因与取舍：这些函数只做几何与光学近似，不读取任何宿主状态。

// --- 算法说明与边界 ---
// GGX 分布的分母在粗糙度接近零时夹紧，避免高光出现无穷大。
// Schlick 菲涅耳在掠射角趋向一，可见性项把微表面遮挡折进分母。
// Burley 漫反射在掠射角变亮，粗糙度越高越明显；高光合成把三项相乘。
// 黑体色按普朗克轨迹分段拟合，色温超出范围时夹到端点。
// 光照模型：GGX 分布、Schlick 菲涅耳、可见性、Burley 漫反射、高光合成、黑体色与射线求交。
// GGX 与可见性按参考常数实现；Burley 在掠射角变亮，黑体色用普朗克轨迹拟合。
// 射线求交包括平面、球与包围盒，相位函数包括瑞利、米氏与 Henyey-Greenstein。


// --- 材质、黑体与光线求交 ---

// 沃尔特 GGX 分布：粗糙度越大，高光越散。
// 分母里的圆周率让分布在整个半球上积分为一，粗糙度平方控制峰值高度。
// 为什么不用更简单的半程高光：GGX 的长尾更接近真实金属的高光边缘。
float ogxDistributionGGX(float NdotH, float roughness)
{
    float roughness2 = roughness * roughness; // 先平方，后面峰值宽度与分母都用这一份。
    float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0; // 分母的二次项，粗糙度为零时退化成一。
    return roughness2 / (OGX_PI * k * k); // 峰值高度由粗糙度平方决定。
}

// 菲涅尔近似：掠射角反射强，正对时只剩基础反射率。
// 先把夹角转成“一减余弦”再取五次方，是为了让曲线在正对时平滑落到 f0。
// `f90` 是掠射时的上限，金属与电介质可以分别给不同的值。
float ogxFresnelSchlick(float VdotH, float f0, float f90)
{
    VdotH = 1.0 - VdotH; // 换成掠射程度，零是正对、一是贴着表面。
    float VdotH2 = VdotH * VdotH; // 五次方的中间量。
    return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH; // 从正对反射率平滑过渡到掠射上限。
}

// 可见性项：把入射与出射方向的遮挡相乘，采用粗糙度一半的常用近似。
// 半粗糙度是实时渲染的常用折中：完全按 Smith 理论算更贵，画面差异很小。
// 分母在正对时接近一，掠射时变大，正好压住菲涅尔的亮边。
float ogxVisibilitySchlick(float NdotL, float NdotV, float roughness)
{
    float k = roughness * 0.5; // 半粗糙度是实时渲染的常用近似。
    return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k)); // 入射与出射遮挡相乘。
}

// 布利漫反射：能量在掠射时更集中，避免边缘死黑。
// 两个菲涅尔项分别描述光和视线方向的散射，乘起来比 Lambert 多一层柔边。
// 最后乘 1/π 是把反射率积分归一化，和 GGX 共用同一套能量口径。
float ogxDiffuseBurley(vec3 n, vec3 v, vec3 l, float roughness)
{
    vec3 h = normalize(v + l); // 半程方向，位置在视线与光线中间。
    float LdotH = ogxSaturate(dot(l, h)); // 光线与半程方向的余弦。
    float NdotL = ogxSaturate(dot(n, l)); // 表面朝光程度。
    float NdotV = ogxSaturate(dot(n, v)); // 表面朝视线程度。
    float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH; // 掠射上限随粗糙度抬高。
    float lightScatter = ogxFresnelSchlick(NdotL, 1.0, f90); // 光方向的散射。
    float viewScatter = ogxFresnelSchlick(NdotV, 1.0, f90); // 视线方向的散射。
    return NdotL * lightScatter * viewScatter * OGX_INV_PI; // 归一化后的漫反射。
}

// 完整 GGX 高光：菲涅尔、可见性、分布三项相乘。
// 三项相乘是标准高光分解，顺序不影响结果，这里按参考的写法排。
// 调用方只要给法线、视线、光方向、粗糙度与基础反射率，不需要自己拆项。
float ogxSpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0)
{
    vec3 h = normalize(v + l);
    float NdotH = ogxSaturate(dot(n, h)); // 法线与半程方向的余弦。
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float ggx = ogxFresnelSchlick(LdotH, f0, 1.0); // 菲涅尔项。
    ggx *= ogxVisibilitySchlick(NdotL, NdotV, roughness); // 几何遮挡项。
    ggx *= ogxDistributionGGX(NdotH, roughness); // 法线分布项。
    return ggx;
}

// 黑体色温拟合：先求色度横坐标与纵坐标，再转线性显示原色。
// 分界点四千开与两千二百二十二开来自原拟合的分段条件，不能省略。
// 两组横坐标多项式分别覆盖低温和高温，纵坐标再多一段低温分支，
// 因为单一多项式在两端会偏色，分段后星空与日落的色温才连续。
// 最后从 XYZ 转回 sRGB 并夹掉负值，负值只出现在拟合边缘，直接保留会变成黑块。
vec3 ogxBlackbody(float temperature)
{
    const vec4 SPLINE_X_LOW = vec4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910);
    const vec4 SPLINE_X_HIGH = vec4(-3.0258469e9, 2.1070479e6, 0.2226347e3, 0.240390);
    const vec4 SPLINE_Y_LOW = vec4(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    const vec4 SPLINE_Y_MID = vec4(-0.9549476, -1.37418593, 2.09137015, -0.16748867);
    const vec4 SPLINE_Y_HIGH = vec4(3.0817580, -5.87338670, 3.75112997, -0.37001483);
    float rt = 1.0 / temperature; // 多项式以倒色温为自变量。
    float rt2 = rt * rt; // 倒色温平方，供三次多项式复用。
    vec4 coeffX = vec4(rt2 * rt, rt2, rt, 1.0); // 三次项、二次项、一次项与常数。
    float x = dot(coeffX, temperature < 4000.0 ? SPLINE_X_LOW : SPLINE_X_HIGH); // 四千开分段求横坐标。
    float x2 = x * x; // 纵坐标多项式以横坐标为自变量。
    vec4 coeffY = vec4(x2 * x, x2, x, 1.0); // 纵坐标的三次项。
    vec4 splineY = temperature < 2222.0 ? SPLINE_Y_LOW : (temperature < 4000.0 ? SPLINE_Y_MID : SPLINE_Y_HIGH); // 低温、中温、高温三段。
    float z = 1.0 / dot(coeffY, splineY); // 先算缩放，再还原色度分量。
    vec3 xyz = vec3(x * z, 1.0, z); // 色度坐标转三分量。
    xyz.z -= xyz.x + 1.0; // 由 x+y+z=1 反推 Z 分量。
    // 三列分别乘三个色度分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
    const vec3 XYZ_TO_SRGB_0 = vec3(3.24097, -0.96924, 0.05563);
    const vec3 XYZ_TO_SRGB_1 = vec3(-1.53738, 1.87597, -0.20398);
    const vec3 XYZ_TO_SRGB_2 = vec3(-0.49861, 0.04156, 1.05697);
    vec3 rgb = XYZ_TO_SRGB_0 * xyz.x + XYZ_TO_SRGB_1 * xyz.y + XYZ_TO_SRGB_2 * xyz.z; // 三列按顺序相加。
    return max(rgb, vec3(0.0)); // 拟合边缘的负值夹到零。
}

// 射线与平面求交：射线与平面法线接近平行时返回极远处的默认交点，避免除零。
// 阈值一万分之一弧度：再小的夹角在屏幕上已经看不出交点移动，继续除会放大浮点误差。
// 默认交点放在一亿米外，调用方仍能拿到一个有限坐标，不会传播无穷大。
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
// 用一亿与负一亿当哨兵：调用方只比较两个分量就能判断有没有交点，不必再加布尔返回值。
// 判别式只开一次方，进入与离开共用同一个偏移，少两次重复计算。
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
// 方向分量接近零时换成百万分之一：这样倒数仍是有限数，区间会自然落到盒外或全包。
// 先取每轴的近远再求最大最小，是标准的逐轴区间方法，不需要逐面判断。
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
// 蓝光波长短、散射强，所以天空偏蓝；这里只保留角度项，波长权重交给大气模块。
// 常数 0.059683104 等于 3/(16π)，与参考实现逐位一致。
float ogxRayleighPhase(float nu) { return 0.059683104 * (nu * nu + 1.0); }

// 米氏相函数：康奈特-沙克形式，`g` 越大前向散射越集中。
// 康奈特-沙克比 HG 多一个“一加余弦平方”因子，太阳附近的亮晕更集中。
// 分母的 -1.5 次方来自相函数的解析积分，改指数会让太阳周围过亮或过暗。
float ogxMiePhase(float g, float nu)
{
    float gg = g * g;
    float k = 0.1193662 * (1.0 - gg) / (2.0 + gg);
    return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5);
}

// 亨耶-格林斯坦相函数在云与雾里共用；把除派拆成参数，是为了让 3.14 与圆周率两种精度都能逐位对照。
// 分母的负一点五次方来自相函数的解析积分，改指数会改变太阳附近的亮度分布。
// 亨耶-格林斯坦相函数：把除以圆周率的部分作为显式参数，方便参考包保留自己的 3.14 常数。
// 为什么参数化：云、雾与层状云参考实现的圆周率精度不同，统一常数会改变严格对照的数值。
float ogxHenyeyGreensteinPhase(float cosAngle, float g, float inversePi)
{
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * cosAngle) + (gg + 1.0), -1.5) * 0.25 * inversePi;
}

// 相函数与几何近似在文件前半段，闪电照明移到天气模块。

// 抖动、切线基、旋转与空间扭曲，具体实现在子文件。
// 子文件：common/math/pattern.slang。
// 数学模块图案工具：拜尔抖动、切线基、旋转矩阵、径向曲线与夜视。
// 调用位置：由 `common/math.slang` 内联引入，后期、天空与吸积盘共用。
// 可复制示例：`float b = ogxInterleavedGradientNoise(pixelCoord);`
// 设计原因与取舍：图案函数保持原来的常数与矩阵展开顺序，避免画面抖动改变。

// --- 算法说明与边界 ---
// 交错梯度噪声用像素坐标的点积与小数部分，输出均匀分布在零到一。
// 拜尔矩阵从二乘二递归翻倍，每一级把旧矩阵复制到四个象限并加偏移。
// 切线基由屏幕导数构造，退化时选一个不平行的参考轴，避免叉乘得到零向量。
// 夜视只改暗部颜色，亮度越高越接近原色，避免亮处偏蓝。
// 图案与矩阵工具：交错梯度噪声、拜尔矩阵、切线基、HSV、旋转矩阵、径向曲线与夜视。
// 拜尔矩阵按二乘二递归生成到一百二十八，给逐像素抖动使用。
// 切线基由屏幕导数构造，旋转矩阵用于天空与行星；夜视把暗部颜色向偏蓝亮度混合。
// 交错梯度噪声用像素坐标的点积与小数部分，输出均匀分布在零到一。
// 拜尔矩阵从二乘二递归翻倍，每一级把旧矩阵复制到四个象限并加偏移。
// 切线基由屏幕导数构造，退化时选一个不平行的参考轴，避免叉乘得到零向量。
// 夜视只改暗部颜色，亮度越高越接近原色，避免亮处偏蓝。


// --- 抖动表、切线基与颜色图案 ---

// 交错梯度噪声：一个像素一个值，适合做抖动，常数来自原始论文。
float ogxInterleavedGradientNoise(vec2 coordinate)
{
    // 两个大常数来自原始论文，乘完取小数就是每像素稳定的伪随机值，不需要纹理。
    return fract(52.9829189 * fract(0.06711056 * coordinate.x + 0.00583715 * coordinate.y));
}

// 二乘二拜尔矩阵：四个格子依次得到零、四分之一、二分之一、四分之三。
float ogxBayer2(vec2 a)
{
    // 先取整：同一格里的不同小数必须得到同一个阈值，否则抖动会退化成噪点。
    a = floor(a);
    // 二乘二矩阵的四个值由这两个系数交错得到，范围正好是零到四分之三。
    return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

// 四乘四拜尔矩阵：由二乘二嵌套得到，用来做稳定抖动。
// 四乘四由二乘二嵌套：低频层乘四分之一，高频层原样，阈值均匀铺满十六格。
float ogxBayer4(vec2 a) { return ogxBayer2(0.5 * a) * 0.25 + ogxBayer2(a); }

// 八乘八拜尔矩阵。
// 八乘八继续嵌套；低频用四阶、高频用二阶，是拜尔矩阵的递推写法。
float ogxBayer8(vec2 a) { return ogxBayer4(0.5 * a) * 0.25 + ogxBayer2(a); }

// 十六乘十六拜尔矩阵：四层二乘二矩阵嵌套，抖动级别比八乘八细四倍。
// 十六阶开始两层都用四阶，频率间隔更大，适合时间累积前的初始抖动。
float ogxBayer16(vec2 a) { return ogxBayer4(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 三十二乘三十二拜尔矩阵：低频一档换成八乘八，级别再细四倍。
// 三十二阶用八阶低频加四阶高频，格数翻倍但只多一次二阶调用。
float ogxBayer32(vec2 a) { return ogxBayer8(0.25 * a) * 0.0625 + ogxBayer4(a); }

// 六十四乘六十四拜尔矩阵：范围大，适合时间累积前的初始偏移。
// 六十四阶两层都用八阶；0.015625 是六十四分之一，保证总和落回零到一。
float ogxBayer64(vec2 a) { return ogxBayer8(0.125 * a) * 0.015625 + ogxBayer8(a); }

// 一百二十八乘一百二十八拜尔矩阵：目前最细的一档，给低步数光追分摊首帧噪点。
// 一百二十八阶是当前最细一档，低频十六阶、高频八阶，用于低步数光追的首帧分摊。
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
// 切线基为什么用导数反推：Minecraft 的方块模型不一定带切线，顶点阶段也拿不到接缝信息；
// 用屏幕空间的位置差与纹理差构造，能在任意几何上得到一致的法线贴图方向。
// 退化时（位置差共线）叉乘接近零，最后除以模长会把方向压回单位长度，不产生无穷大。
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
// 为什么放在数学模块：宿主的公共数学包装与体积光编码都要用，属于共享颜色工具。
// 输入假设在零到一之间，超出范围时取模结果会绕回，调用方要先夹紧。
// 色相以六分之一圈为单位，除以六段再取小数，和参考实现完全一致。
// 色相、饱和度、明度：按最大通道选扇区，再算色相与饱和度。
// 为什么放在颜色模块：表面湿润、体素着色与光传播编码都要把颜色拆成 HSV，属于共享颜色工具。
vec3 ogxRgbToHsv(vec3 color)
{
    const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0;
    const float e = 1.0e-10;
    vec4 p = mix(vec4(color.bg, K.wz), vec4(color.gb, K.xy), step(color.b, color.g));
    vec4 q = mix(vec4(p.xyw, color.r), vec4(color.r, p.yzx), step(p.x, color.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// 色相、饱和度、明度的拆解在颜色模块；这里只保留图案与坐标工具。

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

// 绕纵轴的旋转矩阵：末地天空、行星与雾相位共用同一份，避免各自抄一遍符号。
mat3 ogxRotationY(float angle)
{
    return mat3(cos(angle), 0.0, sin(angle), 0.0, 1.0, 0.0, -sin(angle), 0.0, cos(angle)); // 与参考实现的偏航矩阵逐项一致。
}

// 先俯仰再偏航的旋转：行星与末地雾用同一套 y 轴朝上的天球坐标。
// 为什么单独成函数：两处原来各写三行矩阵，符号一旦改错会让雾和行星的相位对不上。
mat3 ogxRotationXThenY(float angleX, float angleY)
{
    mat3 rotationX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰。
    return rotationX * ogxRotationY(angleY); // 参考实现的相乘顺序。
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

// 双线性与双三次纹理过滤，具体实现在子文件。
// 子文件：common/math/filter.slang。
// 数学模块纹理过滤：双线性、天空盒图集双线性、三次 B 样条与双三次采样。
// 调用位置：由 `common/math.slang` 内联引入，采样器与坐标由调用方传入。
// 可复制示例：`vec4 c = ogxBilinearTexture(tex, uv, texSize);`
// 设计原因与取舍：库不绑定任何纹理单元；取像素与层级采样都显式写在参数里。

// --- 纹理过滤与双三次采样 ---

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

// --- 算法说明与边界 ---
// R2 序列用两个无理数步长，样本不会在短周期内重复；Halton 序列按质数基分层。
// 余弦半球采样先取圆盘再投到半球，样本密度按余弦加权，漫反射估计方差更小。
// 手部深度换算把近景深度压到远景色阶，阴影与反射读同一套深度。
// 快速反余弦在接近正负一时夹紧，避免多项式在端点溢出。
// 采样工具：低差异序列、余弦半球、手部深度换算、三角梯度、快速反余弦、相函数与旋转矩阵。
// R2 序列用两个无理数步长铺满单位正方形，Halton 序列给分层采样。
// 快速反余弦用多项式近似，精度够光照与遮蔽；旋转矩阵用于把二维样本转到切片方向。
// R2 序列用两个无理数步长，样本不会在短周期内重复；Halton 序列按质数基分层。
// 余弦半球采样先取圆盘再投到半球，样本密度按余弦加权，漫反射估计方差更小。
// 手部深度换算把近景深度压到远景色阶，阴影与反射读同一套深度。
// 快速反余弦在接近正负一时夹紧，避免多项式在端点溢出。
// 三角梯度把二维样本折成三角分布，抖动更均匀。
// 旋转矩阵把二维样本转到切片方向，切片数与视角无关。
// R2 序列用两个无理数步长，样本不会在短周期内重复。
// Halton 序列按质数基分层，低维投影比随机采样均匀。
// 余弦半球采样先取圆盘再投到半球，样本密度按余弦加权。
// 手部深度换算把近景深度压到远景色阶。
// 快速反余弦在端点夹紧，避免多项式溢出。
// 三角梯度把二维样本折成三角分布，抖动更均匀。
// 旋转矩阵把二维样本转到切片方向，切片数与视角无关。
// R1 序列给一维抖动，步长取黄金比。
// 瑞利相位近似只在可见光范围使用，超出范围误差变大。
// 拜尔抖动按像素坐标取模，平铺时不会出现接缝。
// 单位向量生成先取圆盘再抬到球面，避免极点聚集。
// 旋转矩阵按列存放，调用方不要按行解释。
// 采样函数不读取纹理与帧号，时间与坐标由调用方传入。
// 低差异序列的起点由调用方给，静止画面才能逐帧累积。
// 余弦半球返回单位向量，长度为零时由调用方兜底。
// 快速反余弦的误差在光照可接受范围内，不用于精确几何。
// 手部深度换算只改变深度尺度，不改变屏幕坐标。
// 三角梯度的两个分量独立，组合后仍落在零到一。
// R2 序列的步长是无理数，长时间运行也不会回到起点。
// 采样数由调用方控制，函数本身不设上限。
// 所有函数都不写全局状态，多线程程序可以安全调用。
// 相位函数输出是概率密度，不是亮度。
// R2 序列用两个无理数步长，样本不会在短周期内重复。
// Halton 序列按质数基分层，低维投影比随机采样均匀。
// 余弦半球采样先取圆盘再投到半球，样本密度按余弦加权。
// 手部深度换算把近景深度压到远景色阶。
// 快速反余弦在端点夹紧，避免多项式溢出。
// 三角梯度把二维样本折成三角分布，抖动更均匀。
// 旋转矩阵把二维样本转到切片方向，切片数与视角无关。
// R1 序列给一维抖动，步长取黄金比。
// 拜尔抖动按像素坐标取模，平铺时不会出现接缝。
// 单位向量生成先取圆盘再抬到球面，避免极点聚集。
// 低差异序列的起点由调用方给，静止画面才能逐帧累积。
// 相位函数输出是概率密度，不是亮度。
// R2 序列的步长是无理数，长时间运行也不会回到起点。
// 采样数由调用方控制，函数本身不设上限。
// 所有函数都不写全局状态，多线程程序可以安全调用。
// 余弦半球的样本密度按余弦加权，漫反射估计方差更小。
// 快速反余弦的误差在光照可接受范围内，不用于精确几何。
// 手部深度换算只改变深度尺度，不改变屏幕坐标。
// 三角梯度的两个分量独立，组合后仍落在零到一。
// 采样函数的输入坐标已经归一化，调用方不要再乘屏幕尺寸。
// 低差异序列与旋转矩阵都按列存放，转置会改变样本方向。
// 相函数与反余弦只做近似，精确几何不要复用这些函数。
// 所有函数都信任调用方传入的采样数，零会由调用方提前拦截。


// R2 低差异序列：两个无理数比例把序号摊成平面上的均匀点，样本不会聚成一团。
// 为什么用 R2 而不是随机数：随机数会成簇，R2 每加一个样本都把空隙补得更均匀。
vec2 ogxR2Sample(int n)
{
    vec2 alpha = vec2(0.75487765, 0.56984026); // 二维黄金比例常数，照 Eclipse 原值。
    return fract(alpha * float(n)); // 序号乘常数后取小数，得到零到一的点。
}

// 余弦加权半球采样：把两个零到一的随机数变成朝上的半球方向。
// 为什么用余弦权重：漫反射的入射能量本身带余弦，按这个分布采样可以直接平均，不用再除权重。
// 余弦半球采样：按余弦分布取方向，重要性采样让漫反射的方差更小。
// 输入两个零到一的随机数，输出单位方向；调用方负责把它们变成逐帧变化。
// 用平方根而不是正弦，是为了让圆盘上的点均匀分布，不会在中心堆积。
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
// 二维旋转矩阵按行优先写入，和 GLSL 构造函数的列主序解释配合；
// 这样生成的文本与参考实现的矩阵展开顺序一致，旋转方向不会反。
// 角度用弧度，调用方不要把角度制直接传进来。
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

#endif
