/*
生成文件：数学模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库数学模块：曲线、编码、材质、光线求交、噪声与切线基。
调用位置：任何需要纯数学函数的图形程序；Minecraft 光影由 `/omni-gfx/math.glsl` 引入。
可复制示例：
    vec3 n = ogxDecodeNormal(ogxEncodeNormal(worldNormal)); // 法线编码后再解回。
    vec3 c = ogxBlackbody(6500.0); // 用色温生成颜色。
    float ao = ogxRemapSaturate(distance, 0.0, 1.0); // 把距离映射到零到一。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀，避免和宿主重名。
    常数与算式逐项来自旧 `shaders/gfx/math.glsl`，迁移只改名字和语法，保证画面不变。
    贴图过滤函数需要宿主采样器状态，暂留在旧 GLSL；这里只收纯计算与显式取像素。
    本文件同时是 Slang 源和 GLSL 生成源，因此只用两边都认得的写法，矩阵乘法显式展开。
*/
#ifndef OGX_MATH_INCLUDED
#define OGX_MATH_INCLUDED

// 圆周率与常用倒数，和旧库保持同一精度。
const float OGX_PI = 3.14159265359;
const float OGX_HALF_PI = 1.57079632679;
const float OGX_INV_PI = 0.31830988618;

// 帧间抖动用的两个无理步长，让相邻帧的偏移尽量不重合。
const float OGX_GOLDEN_RATIO = 1.61803398875;
const float OGX_PLASTIC_RATIO = 1.32471795724;

// 把值夹到零到一，按标量和三种常用向量分别重载，GLSL 侧同样是函数重载。
float ogxSaturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 ogxSaturate(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
vec3 ogxSaturate(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
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

// 取倒数长度的安全版本：零向量返回零，避免除零产生 NaN 污染整条管线。
float ogxSafeInvLength(vec3 v) { float d = dot(v, v); return d > 1e-12 ? 1.0 / sqrt(d) : 0.0; }

// 三角波：把任意输入折回零到一，周期二；噪声与条纹图案常用它代替正弦。
float ogxTriangleWave(float x) { return 1.0 - abs((x * 0.5 - floor(x * 0.5)) * 2.0 - 1.0); }

// 二维乘加：常数项的写法与参考源码一致，便于逐行核对。
vec2 ogxFma2(vec2 a, vec2 b, vec2 c) { return a * b + c; }

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

// 三分量里最大的一个，和上一函数配对使用。
float ogxMaxVec3(vec3 value) { return max(value.x, max(value.y, value.z)); }

// 黄金角：圆周除以黄金比的平方，圆盘点列靠它错开方向，相邻两个点不会撞在一起。
const float OGX_GOLDEN_ANGLE = 2.39996322973;

// 圆盘内均匀分布的第 `index` 个采样点：角度按黄金角步进，半径取平方根保证面积均匀。
vec2 ogxCircleMap(float index, float count)
{
    float angle = index * count * OGX_GOLDEN_ANGLE;
    return vec2(sin(angle), cos(angle)) * sqrt(index);
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
    float y = index * float(steps) * 4096.0 * OGX_GOLDEN_ANGLE;
    float c = inversesqrt(x + 1.0);
    float s = sqrt(x) * c;
    return vec3(cos(y) * s, sin(y) * s, c);
}

// 单位化向量，长度极小时用一个小分母兜底，避免着色点出现除零后的无穷值。
// 比直接除以长度多一点开销，但水面与反射会在掠射角读到极短向量，必须兜底。
vec3 ogxNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }

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
vec4 ogxMatrixMulPoint4(mat4 m, vec4 v) { return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w; }

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

// 线性颜色转显示伽马；二点二近似，和原管线一致，不在这里改成分段标准曲线。
vec3 ogxLinearToGamma(vec3 color) { return pow(color, vec3(1.0 / 2.2)); }

// 显示伽马转回线性，与上一函数互逆。
vec3 ogxGammaToLinear(vec3 color) { return pow(color, vec3(2.2)); }

// 水洼粗糙度：湿润阶段按锐度在干湿之间插值；水面与材质解码共用这一条。
float ogxPuddleRoughness(float roughness, float wetRoughness, float wetnessStages, float sharpness)
{
    return mix(roughness, wetRoughness, wetnessStages * sharpness); // 湿润阶段乘锐度作为混合比例。
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
vec3 ogxLinearToCurve3(vec3 color) { return pow(color, vec3(0.25)); }

// 向量版本的四次方根解码，逐通道平方两次。
vec3 ogxCurveToLinear3(vec3 color)
{
    color = color * color;
    return color * color;
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

// 行星曲率下沉：水平距离平方乘强度，模拟球面相对切面的高度亏损。
float ogxPlanetCurvatureDrop(vec2 horizontal, float amount)
{
    float curvature = length(horizontal) / 128.0;
    return curvature * curvature * amount;
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

// 夜视：把颜色往偏蓝的亮度上拉一半，暗处看得清但保留一点原色。
void ogxDoNightEye(inout vec3 color)
{
    float luma = ogxLuminance(color); // 原色亮度。
    color = mix(color, luma * vec3(0.7771, 1.0038, 1.6190), vec3(0.5)); // 偏蓝亮度与原色各占一半。
}

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
    float theta = 6.28318530718 * xi.y; // 绕竖直轴的角度。
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
float ogxEclipseTri(float x)
{
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49); // 参考实现的夹紧范围。
}

// Eclipse 的二维三角波：先分别算两个方向，再用第一个结果扰动第二个输入。
vec2 ogxEclipseTri2(vec2 p)
{
    float triX = ogxEclipseTri(p.x); // 第一方向。
    float triY = ogxEclipseTri(p.y); // 第二方向。
    return vec2(triX + triY, ogxEclipseTri(triX + p.y)); // 参考实现的组合方式。
}

// Eclipse 的快速反余弦：三系数多项式加根号修正，和库默认的三次近似不同。
float ogxFastAcosEclipse(float x)
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
float ogxRayleighPhaseElek(float cosTheta)
{
    const float oneOverPi = 1.0 / OGX_PI; // 参考实现用 acos(-1) 求 pi。
    vec2 mulAdd = vec2(0.1, 0.28) * oneOverPi; // 两个系数。
    return cosTheta * mulAdd.x + mulAdd.y; // 线性相函数。
}

// Eclipse 的 4×4 Bayer 抖动：按像素坐标查表，返回零到一之间的阈值。
// 为什么不用递归拜尔函数：递归构造出的是另一张矩阵，和参考的 16 项表不同。
float ogxEclipseBayerDither(vec2 pixel)
{
    const float bayer[16] = float[16](
        0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
        12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
        3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
        15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0); // 参考实现的 4×4 表。
    int x = int(mod(pixel.x, 4.0)); // 横向格。
    int y = int(mod(pixel.y, 4.0)); // 纵向格。
    return bayer[x + y * 4]; // 按行优先取表。
}

#endif