/*
生成文件：iterationT 3.2.0 严格 profile。
源文件是 omni-gfx 的生成模块与两个 profile 的严格函数集合，请勿手工修改。
用途：不启动 Minecraft、不依赖具体引擎，验证两个 profile 的 GLSL 能独立编译。
重新生成：python omni-gfx/build.py profiles
*/
#version 330 compatibility
#define OGX_PROFILE_ITERATIONT 1

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
/*
生成文件：颜色模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库颜色模块：线性颜色、亮度、伽马、强光压缩、黑边与调色。
调用位置：任何需要把线性高动态范围颜色映射到显示空间或做最终调色的程序；
    Minecraft 光影由 `/omni-gfx/color.glsl` 引入，引入后数学模块同时可用。
可复制示例：
    vec3 a = ogxAces(linearColor, true); // 影院标准压缩。
    vec3 b = ogxAgx(linearColor, 13.0, true); // 宽色域压缩。
    vec3 c = ogxTonemapNone(linearColor); // 只做伽马编码。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀。
    伽马使用二点二近似，与旧 `shaders/gfx/color.glsl` 一致，不在这里做分段标准曲线。
    矩阵乘法展开成三列乘分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
*/
#ifndef OGX_COLOR_INCLUDED
#define OGX_COLOR_INCLUDED

// 数学模块提供亮度权重、夹紧与编码函数。

// 三列矩阵乘向量：GLSL 的矩阵乘向量就是三列分别乘分量再相加，这里照同一顺序展开。
vec3 ogxApplyColumns(vec3 c0, vec3 c1, vec3 c2, vec3 v)
{
    return c0 * v.x + c1 * v.y + c2 * v.z;
}

// 向量乘矩阵：旧库把颜色放在左边乘矩阵，结果每个分量是向量与一列的点积。
vec3 ogxApplyRows(vec3 c0, vec3 c1, vec3 c2, vec3 v)
{
    return vec3(dot(v, c0), dot(v, c1), dot(v, c2));
}

// 线性颜色转显示伽马空间；二点二伽马，和原管线一致。
vec3 ogxLinearToGamma2(vec3 color) { return pow(color, vec3(1.0 / 2.2)); }

// 显示伽马空间转回线性，与上一函数互为逆运算。
vec3 ogxGammaToLinear2(vec3 color) { return pow(color, vec3(2.2)); }

// ACES 压缩曲线里的有理式：中间亮度拉直，两端压住。
vec3 ogxRrtOdtFit(vec3 value)
{
    vec3 a = value * (value + 0.0245786) - 0.000090537;
    vec3 b = value * (value + 0.4329510) + 0.238081;
    return a / b;
}

// 阿布尼校正矩阵的三列，抵消加亮造成的色相偏移。
const vec3 OGX_ABNEY_0 = vec3(0.99999976, -1.26657e-7, -1.29064e-9);
const vec3 OGX_ABNEY_1 = vec3(1.67316e-8, 0.99999976, -5.32026e-9);
const vec3 OGX_ABNEY_2 = vec3(-0.00725587, 6.47740e-9, 1.00725580);

// 转 AP1 工作色域的三列。
const vec3 OGX_AP1_0 = vec3(0.59719, 0.35458, 0.04823);
const vec3 OGX_AP1_1 = vec3(0.07600, 0.90834, 0.01566);
const vec3 OGX_AP1_2 = vec3(0.02840, 0.13383, 0.83777);

// 从 AP1 转回显示色域的三列。
const vec3 OGX_AP1_BACK_0 = vec3(1.60475, -0.53108, -0.07367);
const vec3 OGX_AP1_BACK_1 = vec3(-0.10208, 1.10813, -0.00605);
const vec3 OGX_AP1_BACK_2 = vec3(-0.00327, -0.07276, 1.07602);

// 影院标准 ACES 近似：提亮、转工作色域、压缩、再转回显示色域。
// `abney` 为真时附加一次很小的色域修正，抵消加亮造成的色相偏移。
vec3 ogxAces(vec3 color, bool abney)
{
    color *= 1.4;
    if (abney)
    {
        color = ogxApplyRows(OGX_ABNEY_0, OGX_ABNEY_1, OGX_ABNEY_2, color);
    }
    color = ogxApplyRows(OGX_AP1_0, OGX_AP1_1, OGX_AP1_2, color);
    color = ogxRrtOdtFit(color);
    color = ogxApplyRows(OGX_AP1_BACK_0, OGX_AP1_BACK_1, OGX_AP1_BACK_2, color);
    return ogxLinearToGamma2(color);
}

// AgX 对比度曲线：用六次多项式近似原查找表，省掉一张纹理。
vec3 ogxAgxContrast(vec3 x)
{
    return (((((15.5 * x - 40.14) * x + 31.96) * x - 6.868) * x + 0.4298) * x + 0.1191) * x - 0.00232;
}

// 转 AgX 宽色域工作空间的三列。
const vec3 OGX_AGX_0 = vec3(0.842479062253094, 0.0784335999999992, 0.0792237451477643);
const vec3 OGX_AGX_1 = vec3(0.0423282422610123, 0.878468636469772, 0.0791661274605434);
const vec3 OGX_AGX_2 = vec3(0.0423756549057051, 0.0784336, 0.879142973793104);

// 从 AgX 宽色域转回显示原色的三列。
const vec3 OGX_AGX_BACK_0 = vec3(1.19687900512017, -0.0980208811401368, -0.0990297440797205);
const vec3 OGX_AGX_BACK_1 = vec3(-0.0528968517574562, 1.15190312990417, -0.0989611768448433);
const vec3 OGX_AGX_BACK_2 = vec3(-0.0529716355144438, -0.0980434501171241, 1.15107367264116);

// AgX 强光压缩：先按中间灰取对数并夹进承认范围，再用 S 曲线成形，尽量保住高光色相。
// `ev` 是承认的动态范围，`abney` 与 ACES 版本含义相同。
vec3 ogxAgx(vec3 color, float ev, bool abney)
{
    color *= 2.3;
    if (abney)
    {
        color = ogxApplyRows(OGX_ABNEY_0, OGX_ABNEY_1, OGX_ABNEY_2, color);
    }
    color = ogxApplyRows(OGX_AGX_0, OGX_AGX_1, OGX_AGX_2, color);
    float hev = ev * 0.5;
    const float MIDDLE_GREY = 0.18;
    color = clamp(log2(color / MIDDLE_GREY), vec3(-hev), vec3(hev));
    color = (color + hev) / ev;
    color = ogxAgxContrast(color);
    color = ogxApplyRows(OGX_AGX_BACK_0, OGX_AGX_BACK_1, OGX_AGX_BACK_2, color);
    return color;
}

// 无压缩：只做伽马编码，保留全部高光，代价是容易硬剪切。
vec3 ogxTonemapNone(vec3 color) { return pow(color, vec3(1.0 / 2.2)); }

// 线性到标准 sRGB 的分段编码：暗部走直线，亮部走二点四分之一幂，与二点二近似不同。
vec3 ogxLinearToSrgb(vec3 color)
{
    vec3 low = color * 12.92; // 暗部直线段。
    vec3 high = 1.055 * pow(ogxSaturate(color), vec3(1.0 / 2.4)) - 0.055; // 亮部幂曲线。
    return mix(low, high, step(vec3(0.0031308), color)); // 按阈值逐通道选择，接缝处两侧取值相同。
}

// 经济版电影曲线：一条有理式，成本低于 ACES 拟合，观感更硬、更亮。
vec3 ogxTonemapAcesFilm(vec3 color)
{
    vec3 x = color * 0.9; // 先压一点曝光。
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.95) + 0.12); // 分子分母都是二次式。
}

// `Hejl` 2015 胶片曲线：先加一点偏移让纯黑离开零，再用两个有理式的比值压肩部。
vec3 ogxTonemapHejl(vec3 color)
{
    vec4 vh = vec4(color * 0.85, 3.0); // 三个颜色通道加一个白点参考。
    vec4 va = 1.75 * vh + 0.05; // 肩部斜率随亮度增加。
    vec4 vf = ((vh * va + 0.004) / (vh * (va + 0.55) + 0.0491)) - 0.0821 + 0.000633604888; // 有理式压缩，末尾常数把黑点抬回零。
    return vf.xyz / vf.w; // 用白点参考归一，最亮处回到一。
}

// `Hable` 胶片曲线：六个常数分别控制肩部、线性段与趾部，白点十一做归一。
vec3 ogxTonemapHable(vec3 color)
{
    vec3 x = color * 2.0; // 先放大两倍，让中间灰落在曲线中段。
    vec3 mapped = ((x * (0.6 * x + 0.1 * 0.5) + 0.5 * 0.01) / (x * (0.6 * x + 0.5) + 0.5 * 0.3)) - 0.01 / 0.3; // 肩部强度零点六、线性强度零点五、线性角度零点一、趾部强度零点五、趾部两项零点零一与零点三。
    float w = 11.0; // 白点。
    float white = ((w * (0.6 * w + 0.1 * 0.5) + 0.5 * 0.01) / (w * (0.6 * w + 0.5) + 0.5 * 0.3)) - 0.01 / 0.3; // 同一条曲线在白点处的值。
    return mapped / white; // 归一后最亮处正好到一。
}

// `Reinhard` 简单曲线：先放大一点六六倍再除以一加自身，暗部提得最明显。
vec3 ogxTonemapReinhard(vec3 color)
{
    vec3 x = color * 1.66; // 放大让中间灰更亮。
    return x / (1.0 + x); // 双曲线压缩，结果永远不会超过一。
}

// `Lottes` 2016 曲线：指数控制对比度，肩部由输入中间灰与显示白点反推。
// 为什么斜率和偏移写成普通变量：它们由幂函数算出，GLSL 的常量初始化不保证能折叠。
vec3 ogxTonemapLottes(vec3 color)
{
    float a = 1.6; // 对比度指数。
    float d = 0.977; // 肩部指数。
    float hdrMax = 8.0; // 输入白点。
    float midIn = 0.23; // 输入中间灰。
    float midOut = 0.267; // 输出中间灰。
    float b = (-pow(midIn, a) + pow(hdrMax, a) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut); // 肩部斜率。
    float c = (pow(hdrMax, a * d) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, a * d) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut); // 肩部偏移。
    return pow(color, vec3(a)) / (pow(color, vec3(a * d)) * b + c); // 两段幂函数之比。
}

// `Uchimura` 2017 曲线：分成趾部、线性段与肩部三截，再用平滑权重拼接。
// 参考实现把平滑曲线的两个边界写反了，那样权重会出现负数；这里按边界在前的正确顺序写。
vec3 ogxTonemapUchimura(vec3 color)
{
    float peak = 1.0; // 显示上限。
    float contrast = 1.0; // 线性段斜率。
    float mid = 0.12; // 线性段起点。
    float length = 0.22; // 线性段折算长度。
    float black = 1.0; // 趾部形状指数。
    float l0 = ((peak - mid) * length) / contrast; // 折算后的线性段长度。
    float s0 = mid + l0; // 肩部起点。
    float s1 = mid + contrast * l0; // 肩部终点。
    float c2 = (contrast * peak) / (peak - s1); // 肩部曲率。
    float cp = c2 / peak; // 按显示上限归一。
    vec3 w0 = 1.0 - smoothstep(vec3(0.0), vec3(mid), color); // 趾部权重。
    vec3 w2 = step(vec3(s0), color); // 肩部权重。
    vec3 w1 = 1.0 - w0 - w2; // 线性段权重，三者之和为一。
    vec3 toe = mid * pow(color / mid, vec3(black)); // 趾部幂曲线。
    vec3 shoulder = peak - (peak - s1) / (1.0 + cp * (color - s0)); // 肩部有理曲线，越亮越贴近显示上限。
    vec3 linear = mid + contrast * (color - mid); // 中间直线段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, vec3(0.0), vec3(1.0)); // 三段按权重拼接并夹紧。
}

// `Xonk` 曲线：先抬高三成伽马，再用一条有理式压肩部，暗部比 `Reinhard` 更亮。
// 它是一条独立拟合，和 `ACES`、`AgX`、`Reinhard` 都不是同一条曲线，不能互相替代。
vec3 ogxTonemapXonk(vec3 color)
{
    color = pow(color, vec3(1.3)); // 先抬伽马，暗部细节更容易看见。
    return color / (0.333 + color); // 有理式软肩，最亮处趋近于一。
}

// 十六位打包值拆成两个分量：按整数与小数部分各取一次，绕开位运算。
// 参考实现用它存放方块贴图坐标；与 `ogxUnpack2x16` 的区别是这里不依赖浮点位模式，
// 因此数值可以跨后端逐位复现。`value` 必须落在零到一之间。
vec2 ogxDecodeVec2x16(float value)
{
    const vec2 constant1 = 4294967294.0 / vec2(65536.0, 4294967295.0); // 两个分量的步长倒数。
    const float constant2 = 65536.0 / 65535.0; // 补回零到一的上界误差。
    return fract(value * constant1) * constant2; // 先取小数部分再缩放。
}

// 黑边：按目标宽高比在画面上下或左右画黑边，返回该像素是否落在画面内。
float ogxBlackBar(vec2 coord, float aspect, float targetRatio)
{
    if (targetRatio == 0.0)
    {
        return 1.0;
    }
    vec2 aCoord = abs(coord - 0.5) * 2.0;
    float width = min(targetRatio / aspect, 1.0);
    float height = min(aspect / targetRatio, 1.0);
    return step(aCoord.x, width) * step(aCoord.y, height);
}

// 浦肯野效应：亮度低于阈值时把颜色混向偏蓝的暗视觉，越暗混入越多。
vec3 ogxPurkinje(vec3 color, float threshold, float strength)
{
    float luminance = ogxLuminance(color);
    float mixAmount = clamp((threshold - luminance) * strength / threshold, 0.0, 1.0);
    return mix(color, luminance * vec3(0.7777, 1.0004, 1.6190), mixAmount);
}

// 白平衡：把调用方给的色温颜色乘在线性颜色上，中性时颜色为一、不改动。
vec3 ogxWhiteBalance(vec3 color, vec3 tint) { return color * tint; }

// 高级调色：白光裁剪、亮度伽马与饱和度，全部在线性空间处理后再回显示空间。
vec3 ogxAdvancedColor(vec3 color, float lumaGamma, float whiteClip, float saturation, float gamma)
{
    color = ogxGammaToLinear2(color);
    color = pow(length(color), 1.0 / lumaGamma) * normalize(color + 1e-20);
    color = clamp(color * (1.0 + whiteClip), vec3(0.0), vec3(1.0));
    color = mix(color, vec3(ogxLuminance(color)), vec3(1.0 - saturation));
    return clamp(pow(color, vec3((1.0 / 2.2) / gamma)), vec3(0.0), vec3(1.0));
}

// 色相、饱和度、明度转回颜色，与数学模块的 `ogxRgbToHsv` 互逆。
vec3 ogxHsvToRgb(vec3 color)
{
    const vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(color.xxx + vec3(K.x, K.y, K.z)) * 6.0 - vec3(K.w, K.w, K.w));
    return color.z * mix(vec3(K.x, K.x, K.x), clamp(p - vec3(K.x, K.x, K.x), vec3(0.0), vec3(1.0)), color.y);
}

// sRGB 到线性：三次多项式近似，供方块光表复原颜色。
vec3 ogxSrgbToLinear(vec3 s) { return s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878); }

// Eclipse 的亮度权重：旧电视标准 0.299/0.587/0.114，和库默认的现代权重不同。
// 单独成函数，避免把两种颜色空间混进同一个 `ogxLuminance`。
float ogxLuminanceRec601(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }

// Eclipse 全范围 Reinhard：白点 10、提亮 0.5，保留完整有理式。
vec3 ogxTonemapReinhardFull(vec3 color)
{
    float whitepoint = 10.0; // 参考实现固定白点。
    float lighten = 0.5; // 参考实现固定提亮量。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Eclipse 可编辑 Reinhard：先把颜色抬 1.2 次方，再用更低的提亮 0.333。
vec3 ogxTonemapReinhardEdit(vec3 color)
{
    color = pow(color, vec3(1.2)); // 抬暗部，保持高光不动。
    float whitepoint = 10.0; // 与全范围版相同的白点。
    float lighten = 0.333; // 更低的提亮量，画面更亮。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Reinhard-Jodie：同时算亮度压缩与逐通道压缩，再按逐通道结果混回去。
vec3 ogxTonemapReinhardJodie(vec3 color)
{
    color *= 1.5; // 参考实现的曝光抬升。
    vec3 tonemapLuminance = color / (1.0 + dot(color, vec3(0.21, 0.72, 0.07))); // 保色相的亮度压缩。
    vec3 tonemapRgb = color / (1.0 + color); // 逐通道压缩，高光更容易去饱和。
    return mix(tonemapLuminance, tonemapRgb, tonemapRgb * 0.8 + 0.2); // 亮部更多采用逐通道结果。
}

// Eclipse 的 AgX look：默认零偏移、单位斜率与幂，只把饱和度推到 1.25。
vec3 ogxAgxLook(vec3 value)
{
    float luma = dot(value, vec3(0.2126, 0.7152, 0.0722)); // 参考实现固定 Rec.709 亮度。
    value = pow(value, vec3(1.0)); // 参考实现默认幂为一，保留这一步便于逐行对照。
    return luma + 1.25 * (value - luma); // 围绕亮度拉开饱和度。
}

// Eclipse 的 AgX 完整版：插入矩阵、动态范围 -12.47393 到 4.026069，再用 AGX look。
vec3 ogxToneMapAgx(vec3 color)
{
    vec3 in0 = vec3(0.856627153315983, 0.137318972929847, 0.11189821299995); // 插入矩阵第一列。
    vec3 in1 = vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903); // 第二列。
    vec3 in2 = vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859); // 第三列。
    vec3 out0 = vec3(1.1271005818144368, -0.1413297634984383, -0.14132976349843826); // 输出矩阵第一列。
    vec3 out1 = vec3(-0.11060664309660323, 1.157823702216272, -0.11060664309660294); // 第二列。
    vec3 out2 = vec3(-0.016493938717834573, -0.016493938717834257, 1.2519364065950405); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入 AgX 工作空间。
    color = clamp(log2(color), vec3(-12.47393), vec3(4.026069)); // 夹进承认的动态范围。
    color = (color + 12.47393) / (4.026069 + 12.47393); // 归一化到零到一。
    color = ogxAgxContrast(color); // AgX 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回到显示原色。
    color = pow(max(color, vec3(0.0)), vec3(2.2)); // 线性化。
    return clamp(color, vec3(0.0), vec3(1.0)); // 最后夹到显示范围。
}

// Eclipse 的 AgX 精简版：端点与完整版相同，但使用另一组插入/输出矩阵。
vec3 ogxToneMapAgxMinimal(vec3 color)
{
    vec3 in0 = vec3(0.842479062253094, 0.0423282422610123, 0.0423756549057051); // 精简插入矩阵第一列。
    vec3 in1 = vec3(0.0784335999999992, 0.878468636469772, 0.0784336); // 第二列。
    vec3 in2 = vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 第三列。
    vec3 out0 = vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    vec3 out1 = vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 第二列。
    vec3 out2 = vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), vec3(-12.47393), vec3(4.026069)); // 与完整版相同的端点。
    color = (color + 12.47393) / (4.026069 + 12.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, vec3(2.2)); // 线性化。
    return clamp(color, vec3(0.0), vec3(1.0)); // 夹紧。
}

// Eclipse 的 AgX Merlin 版：矩阵同上，端点整体上移一档，动态范围更窄。
vec3 ogxToneMapAgxMerlin(vec3 color)
{
    vec3 in0 = vec3(0.842479062253094, 0.0423282422610123, 0.0423756549057051); // 精简插入矩阵第一列。
    vec3 in1 = vec3(0.0784335999999992, 0.878468636469772, 0.0784336); // 第二列。
    vec3 in2 = vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 第三列。
    vec3 out0 = vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    vec3 out1 = vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 第二列。
    vec3 out2 = vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 第三列。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), vec3(-11.47393), vec3(3.226069)); // Merlin 的端点比精简版高 1。
    color = (color + 11.47393) / (3.226069 + 11.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, vec3(2.2)); // 线性化。
    return clamp(color, vec3(0.0), vec3(1.0)); // 夹紧。
}

// Eclipse 的 Uchimura 指数肩部版：肩部用 exp，参考实现保留反向 smoothstep 参数顺序。
vec3 ogxTonemapUchimuraExp(vec3 x, float P, float a, float m, float l, float c, float b)
{
    float l0 = ((P - m) * l) / a; // 线性段折算长度。
    float s0 = m + l0; // 肩部起点。
    float s1 = m + a * l0; // 肩部终点。
    float c2 = (a * P) / (P - s1); // 肩部曲率。
    float cp = -c2 / P; // 指数肩部用的负曲率。
    vec3 w0 = 1.0 - smoothstep(x, vec3(0.0), vec3(m)); // 保持参考实现的参数顺序，不改成正确顺序。
    vec3 w2 = step(m + l0, x); // 肩部权重。
    vec3 w1 = 1.0 - w0 - w2; // 线性段权重。
    vec3 toe = m * pow(x / m, vec3(c)) + b; // 趾部幂曲线。
    vec3 shoulder = P - (P - s1) * exp(cp * (x - s0)); // 指数肩部。
    vec3 linear = m + a * (x - m); // 线性段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, vec3(0.0), vec3(1.0)); // 三段拼接。
}

// Eclipse 的 Uchimura 修改版：肩部改成 smoothstep 曲线，其余参数与指数版相同。
vec3 ogxTonemapUchimuraModified(vec3 x, float P, float a, float m, float l, float c, float b)
{
    float l0 = ((P - m) * l) / a; // 线性段折算长度。
    float s0 = m + l0; // 肩部起点。
    float s1 = m + a * l0; // 肩部终点。
    float c2 = (a * P) / (P - s1); // 肩部曲率。
    float cp = c2 / P; // 曲线肩部的正曲率。
    vec3 w0 = 1.0 - smoothstep(x, vec3(0.0), vec3(m)); // 保持参考实现的参数顺序。
    vec3 w2 = step(m + l0, x); // 肩部权重。
    vec3 w1 = 1.0 - w0 - w2; // 线性段权重。
    vec3 toe = m * pow(x / m, vec3(c)) + b; // 趾部幂曲线。
    vec3 t = clamp(cp * (x - s0), vec3(0.0), vec3(1.0)); // 参考曲线函数的输入先夹紧。
    vec3 shoulder = P - (P - s1) * (t * t * (3.0 - 2.0 * t)); // 平滑曲线肩部。
    vec3 linear = m + a * (x - m); // 线性段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, vec3(0.0), vec3(1.0)); // 三段拼接。
}

// Eclipse 黑体色：按温度拟合 RGB，再转线性；和普朗克轨迹版是两个不同近似。
vec3 ogxBlackbodyEclipse(float temperature)
{
    float t = pow(temperature, -1.5); // 高温项。
    float lt = log(temperature); // 对数项。
    vec3 col = vec3(0.0); // 逐通道拟合结果。
    col.x = 220000.0 * t + 0.58039215686; // 红通道。
    col.y = 0.39231372549 * lt - 2.44549019608; // 绿通道低温段。
    col.y = temperature > 6500.0 ? 138039.215686 * t + 0.72156862745 : col.y; // 高温段换拟合。
    col.z = 0.76078431372 * lt - 5.68078431373; // 蓝通道。
    col = clamp(col, vec3(0.0), vec3(1.0)); // 先夹紧到零到一。
    col = temperature < 1000.0 ? col * temperature * 0.001 : col; // 极低温按比例压暗。
    return ogxSrgbToLinear(col); // 最后转线性。
}

// 三列矩阵：用三个列向量表示，避开 Slang 与 GLSL 的行列顺序差异。
struct OgxAgxMat3
{
    vec3 c0; // 第一列。
    vec3 c1; // 第二列。
    vec3 c2; // 第三列。
};

// 矩阵乘向量：三列分别乘分量再相加，和 GLSL 的 `mat3 * vec3` 完全一致。
vec3 ogxAgxMulVec(OgxAgxMat3 m, vec3 v)
{
    return m.c0 * v.x + m.c1 * v.y + m.c2 * v.z;
}

// 向量乘矩阵：结果的每个分量是向量与一列的点积，对应 GLSL 的 `vec3 * mat3`。
vec3 ogxAgxVecMul(OgxAgxMat3 m, vec3 v)
{
    return vec3(dot(v, m.c0), dot(v, m.c1), dot(v, m.c2));
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
    vec3 a = m.c0; // 第一列。
    vec3 b = m.c1; // 第二列。
    vec3 c = m.c2; // 第三列。
    vec3 r0 = vec3(b.y * c.z - b.z * c.y, a.z * c.y - a.y * c.z, a.y * b.z - a.z * b.y); // 伴随矩阵第一行。
    vec3 r1 = vec3(b.z * c.x - b.x * c.z, a.x * c.z - a.z * c.x, a.z * b.x - a.x * b.z); // 第二行。
    vec3 r2 = vec3(b.x * c.y - b.y * c.x, a.y * c.x - a.x * c.y, a.x * b.y - a.y * b.x); // 第三行。
    float determinant = dot(a, r0); // 行列式。
    OgxAgxMat3 result;
    result.c0 = vec3(r0.x, r1.x, r2.x) / determinant; // 伴随矩阵转置后按列写入。
    result.c1 = vec3(r0.y, r1.y, r2.y) / determinant;
    result.c2 = vec3(r0.z, r1.z, r2.z) / determinant;
    return result;
}

// 色度坐标到 XYZ：Y 归一为一，X 与 Z 由 xy 反推。
vec3 ogxAgxUnproject(vec2 xy)
{
    if (xy.y == 0.0) return vec3(0.0); // 参考实现对零分母直接返回零。
    float x = xy.x / xy.y; // X 分量。
    float z = (1.0 - xy.x - xy.y) / xy.y; // Z 分量。
    return vec3(x, 1.0, z); // Y 固定为一。
}

// 由三原色与白点色度构造 RGB 到 XYZ 的矩阵；列顺序与参考实现一致。
OgxAgxMat3 ogxAgxPrimariesToMatrix(vec2 xyRed, vec2 xyGreen, vec2 xyBlue, vec2 xyWhite)
{
    vec3 xyzRed = ogxAgxUnproject(xyRed); // 红原色 XYZ。
    vec3 xyzGreen = ogxAgxUnproject(xyGreen); // 绿原色 XYZ。
    vec3 xyzBlue = ogxAgxUnproject(xyBlue); // 蓝原色 XYZ。
    vec3 xyzWhite = ogxAgxUnproject(xyWhite); // 白点 XYZ。
    OgxAgxMat3 temp;
    temp.c0 = vec3(xyzRed.x, xyzGreen.x, xyzBlue.x); // 第一行：三个 X。
    temp.c1 = vec3(1.0, 1.0, 1.0); // 第二行：三个 Y。
    temp.c2 = vec3(xyzRed.z, xyzGreen.z, xyzBlue.z); // 第三行：三个 Z。
    OgxAgxMat3 inverse = ogxAgxInverse(temp); // 参考实现对临时矩阵求逆。
    vec3 scale = ogxAgxVecMul(inverse, xyzWhite); // 白点乘逆矩阵，得到三原色缩放。
    OgxAgxMat3 result;
    result.c0 = vec3(scale.x * xyzRed.x, scale.y * xyzGreen.x, scale.z * xyzBlue.x); // 第一行乘缩放。
    result.c1 = vec3(scale.x * xyzRed.y, scale.y * xyzGreen.y, scale.z * xyzBlue.y); // 第二行。
    result.c2 = vec3(scale.x * xyzRed.z, scale.y * xyzGreen.z, scale.z * xyzBlue.z); // 第三行。
    return result;
}

// 主色滑动量：按角度正负选择邻居，返回侧向位移与邻居距离的比。
float ogxAgxRotationToSlide(vec2 primary, vec2 neighborA, vec2 neighborB, float angle)
{
    vec2 neighbor = mix(neighborB, neighborA, float(angle >= 0.0)); // 角度非负时取 A。
    float distanceToNeighbor = distance(primary, neighbor); // 到邻居的距离。
    float distanceToCenter = length(primary); // 到白点的距离。
    float side = sin(angle / 180.0 * OGX_PI) * distanceToCenter; // 侧向位移。
    return side / distanceToNeighbor; // 归一化滑动量。
}

// 主色滑动：按滑动量在原色与邻居之间插值，滑动量先取绝对值再夹紧。
vec2 ogxAgxSlidePrimary(vec2 primary, vec2 neighborA, vec2 neighborB, float amount)
{
    return mix(primary, mix(neighborB, neighborA, float(amount >= 0.0)), ogxSaturate(abs(amount))); // 保留参考顺序。
}

// 压缩矩阵：先按旋转量滑动三原色，再按压缩量缩放，最后重建 RGB 到 XYZ。
OgxAgxMat3 ogxAgxComputeCompressionMatrix(vec2 xyRed, vec2 xyGreen, vec2 xyBlue, vec2 xyWhite)
{
    vec2 offsetRed = xyRed - xyWhite; // 红原色相对白点。
    vec2 offsetGreen = xyGreen - xyWhite; // 绿原色相对白点。
    vec2 offsetBlue = xyBlue - xyWhite; // 蓝原色相对白点。
    vec3 slide = vec3(0.0); // 三个通道的滑动量。
    slide.r = ogxAgxRotationToSlide(offsetRed, offsetBlue, offsetGreen, 0.0); // 参考实现的 rotation.r 为零。
    slide.g = ogxAgxRotationToSlide(offsetGreen, offsetRed, offsetBlue, 0.0); // 参考实现的 rotation.g 为零。
    slide.b = ogxAgxRotationToSlide(offsetBlue, offsetGreen, offsetRed, -2.0); // 参考实现的 rotation.b 为负二。
    vec3 scaleFactor = 1.0 / (1.0 - vec3(0.0)); // 参考实现的 compression 为零。
    vec2 red = ogxAgxSlidePrimary(offsetRed, offsetBlue, offsetGreen, slide.r) * scaleFactor.r + xyWhite; // 红原色新位置。
    vec2 green = ogxAgxSlidePrimary(offsetGreen, offsetRed, offsetBlue, slide.g) * scaleFactor.g + xyWhite; // 绿原色新位置。
    vec2 blue = ogxAgxSlidePrimary(offsetBlue, offsetGreen, offsetRed, slide.b) * scaleFactor.b + xyWhite; // 蓝原色新位置。
    return ogxAgxPrimariesToMatrix(red, green, blue, xyWhite); // 重建矩阵。
}

// 开放域转归一化对数：先除中间灰取 log2，再夹到动态范围并归一。
vec3 ogxAgxOpenDomainToNormalizedLog2(vec3 openDomain, float minimumEv, float maximumEv)
{
    const float middleGrey = 0.18; // 参考实现的中间灰。
    float totalExposure = maximumEv - minimumEv; // 动态范围宽度。
    vec3 outputLog = clamp(log2(openDomain / middleGrey), minimumEv, maximumEv); // 夹到承认范围。
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
    float scaleXPivot = mix(xPivot, 1.0 - xPivot, bpivot); // 支点按左右翻转。
    float scaleYPivot = mix(yPivot, 1.0 - yPivot, bpivot); // 输出支点同样翻转。
    float toeScale = ogxAgxEquationScale(scaleXPivot, scaleYPivot, slopePivot, toePower); // 趾部尺度。
    float shoulderScale = ogxAgxEquationScale(scaleXPivot, scaleYPivot, slopePivot, shoulderPower); // 肩部尺度。
    float scale = mix(-toeScale, shoulderScale, bpivot); // 左右选择正负尺度。
    float term = (slopePivot * (x - xPivot)) / scale; // 曲线内部项。
    float power = mix(toePower, shoulderPower, float(scale >= 0.0)); // 按尺度选择幂。
    float hyperbolic = term / pow(1.0 + pow(term, power), 1.0 / power); // 双曲压缩。
    return scale * hyperbolic + yPivot; // 还原到输出范围。
}

// iterationT 的可配置 AgX：把 RGB 转到调整后的工作空间，再走完整曲线。
vec3 ogxAgxConfigurable(vec3 rgb)
{
    vec2 xyRed = vec2(0.64, 0.33); // 红原色色度。
    vec2 xyGreen = vec2(0.3, 0.6); // 绿原色色度。
    vec2 xyBlue = vec2(0.15, 0.06); // 蓝原色色度。
    vec2 xyWhite = vec2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    OgxAgxMat3 xyzToAdjusted = ogxAgxInverse(adjustedToXyz); // 逆矩阵。
    vec3 xyz = ogxAgxVecMul(srgbToXyz, rgb); // 参考实现用行向量乘矩阵。
    vec3 adjustedRgb = ogxAgxVecMul(xyzToAdjusted, xyz); // 转到调整后 RGB。
    float minimumEv = -6.0; // 参考实现的最小曝光。
    float maximumEv = 6.0; // 最大曝光。
    float xPivot = abs(minimumEv) / (maximumEv - minimumEv); // 支点位置。
    float yPivot = 0.5; // 输出支点。
    float slope = 2.3; // 参考斜率。
    float toePower = 1.9; // 趾部幂。
    float shoulderPower = 2.5; // 肩部幂。
    vec3 logValue = ogxAgxOpenDomainToNormalizedLog2(adjustedRgb, minimumEv, maximumEv); // 归一化对数。
    float outputRed = ogxAgxEquationFullCurve(logValue.r, xPivot, yPivot, slope, toePower, shoulderPower); // 红通道曲线。
    float outputGreen = ogxAgxEquationFullCurve(logValue.g, xPivot, yPivot, slope, toePower, shoulderPower); // 绿通道曲线。
    float outputBlue = ogxAgxEquationFullCurve(logValue.b, xPivot, yPivot, slope, toePower, shoulderPower); // 蓝通道曲线。
    return vec3(outputRed, outputGreen, outputBlue); // 逐通道输出。
}

// iterationT 的 AgX 调整矩阵：只返回从 sRGB 到调整后空间的组合矩阵。
OgxAgxMat3 ogxAgxConfigurable1()
{
    vec2 xyRed = vec2(0.64, 0.33); // 红原色色度。
    vec2 xyGreen = vec2(0.3, 0.6); // 绿原色色度。
    vec2 xyBlue = vec2(0.15, 0.06); // 蓝原色色度。
    vec2 xyWhite = vec2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    return ogxAgxMulMat(srgbToXyz, ogxAgxInverse(adjustedToXyz)); // 组合成 sRGB 到调整后空间。
}

// 饱和度矩阵：把颜色朝灰阶收或向外推，一为原色。
// 旧实现用四乘四矩阵，保留同一个构造顺序；生成 GLSL 后按列解释，与旧画面一致。
mat4 ogxSaturationMatrix(float saturation)
{
    const vec3 luminance = vec3(0.3086, 0.6094, 0.0820); // 饱和度用的亮度权重。
    vec3 lumSat = luminance * (1.0 - saturation); // 去饱和时混入的灰分量。
    vec2 satZero = vec2(saturation, 0.0); // 原色保留量。
    return mat4(
        vec4(lumSat.r + satZero.xyy, 0.0),
        vec4(lumSat.g + satZero.yxy, 0.0),
        vec4(lumSat.b + satZero.yyx, 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)); // 三个颜色通道加一行齐次坐标。
}

#endif
/*
生成文件：采样模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库采样模块：蓝噪声、时间抖动、拜尔抖动、纹理平滑过滤、旋转网格超采样与抗锯齿抖动序列。
调用位置：任何需要每像素或每帧不同采样偏移的程序；Minecraft 光影由 `/omni-gfx/sampling.glsl` 引入。
可复制示例：
    vec2 n = ogxBlueNoise(noiseTexture, ivec2(pixel)); // 取一张蓝噪声。
    float d = ogxBayerTemporal(ivec2(pixel), 0); // 取每帧变化的拜尔值。
    vec4 c = ogxSmoothFilter(albedo, uv, textureSize); // 平滑过滤后的取样。
    vec2 j = ogxTaaJitter(frame, true); // 四帧一循环的抗锯齿抖动。
设计原因与取舍：
    噪声纹理、像素坐标和帧号全部由调用方传入，库不依赖任何引擎全局量。
    静态蓝噪声按六十四像素平铺；时间偏移用黄金比与塑料比错开，避免相邻帧重叠。
    取像素只用显式整数坐标，不用硬件过滤，因此同一份源能直接生成 SPIR-V 与 GLSL。
    超采样需要屏幕空间导数，参考实现直接调用导数内置函数；这里改成由调用方传进来，
    库因此仍然是纯函数，也能在没有屏幕导数的程序里复用。
*/
#ifndef OGX_SAMPLING_INCLUDED
#define OGX_SAMPLING_INCLUDED

// 数学模块提供拜尔矩阵与两个时间步长。

// 显式取一个像素；Slang 的 `Load` 在生成 GLSL 时换成 `texelFetch`，两边语义相同。
vec4 ogxTexelFetch(sampler2D tex, ivec2 pixel, int level)
{
    return texelFetch(tex, pixel, level);
}

// 从蓝噪声纹理取当前像素的二维偏移；纹理边长六十四，按像素坐标取模平铺。
vec2 ogxBlueNoise(sampler2D noiseTexture, ivec2 pixel)
{
    return ogxTexelFetch(noiseTexture, pixel % 64, 0).xy;
}

// 加上帧号偏移，得到每帧变化、六十四帧一循环的二维抖动。
vec2 ogxBlueNoiseTemporal(sampler2D noiseTexture, ivec2 pixel, int frame)
{
    vec2 base = ogxBlueNoise(noiseTexture, pixel);
    return fract(base + vec2(OGX_GOLDEN_RATIO, OGX_PLASTIC_RATIO) * float(frame % 64));
}

// 每帧平移的拜尔抖动，一百二十八帧一循环，适合需要低差异序列的场合。
// 黄金比步进让相邻帧的偏移不重复，同时保持单帧内的空间分布。
float ogxBayerTemporal(ivec2 pixel, int frame)
{
    return fract(ogxBayer64(vec2(pixel)) + OGX_GOLDEN_RATIO * float(frame % 128));
}

// 平滑过滤：先在纹素坐标里用平滑曲线重排采样点，再回纹理坐标取样。
// 为什么先转纹素坐标：平滑曲线必须落在相邻两个纹素的中心之间，直接对零到一的纹理坐标做会随尺寸漂移。
// 纹理采样走显式层级零，调用方不用保证导数存在。
vec4 ogxSmoothFilter(sampler2D tex, vec2 uv, vec2 resolution)
{
    vec2 texel = uv * resolution + 0.5; // 转成纹素坐标，并把中心挪到半像素。
    vec2 whole = floor(texel); // 采样点所在纹素的整数部分。
    vec2 fraction = fract(texel); // 纹素内的小数位置。
    texel = whole + (fraction * fraction) * (3.0 - 2.0 * fraction); // 平滑曲线把小数位置推向两端。
    texel = texel / resolution - 0.5 / resolution; // 换回纹理坐标，并补偿半纹素。
    return textureLod(tex, texel, 0.0); // 读回过滤后的颜色。
}

// 阴影贴图的平滑过滤：坐标是三分量，第三分量是比较值；其余步骤与上一函数相同。
// 为什么阴影要单独一份：阴影采样器带比较，取回的是零到一的可见度而不是颜色。
float ogxShadowSmoothFilter(sampler2DShadow tex, vec3 uv, float resolution)
{
    vec2 texel = uv.xy * resolution + 0.5; // 水平两分量转纹素坐标。
    vec2 whole = floor(texel); // 所在纹素。
    vec2 fraction = fract(texel); // 纹素内位置。
    texel = whole + (fraction * fraction) * (3.0 - 2.0 * fraction); // 平滑重排采样点。
    texel = texel / resolution - 0.5 / resolution; // 换回纹理坐标。
    return textureLod(tex, vec3(texel, uv.z), 0.0); // 按比较值取可见度。
}

// 最近点取样：把纹理坐标拉回纹素中心附近，再按屏幕上的纹素大小决定拉回多少。
// 为什么按屏幕纹素缩放：贴图在远处时一个屏幕像素覆盖多个纹素，完全拉回中心会闪；
// 按覆盖率插值才能让细节平滑消失，而不是逐帧跳动。
vec4 ogxSampleNearest(sampler2D tex, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv, vec2 texelScreenSize)
{
    vec2 texelCoords = uv / pixelSize; // 转成纹素坐标。
    vec2 texelCenter = round(texelCoords) - 0.5; // 最近纹素的中心。
    vec2 texelOffset = texelCoords - texelCenter; // 离中心的偏移。
    texelOffset = (texelOffset - 0.5) * pixelSize / texelScreenSize + 0.5; // 按屏幕纹素大小缩放偏移。
    texelOffset = clamp(texelOffset, vec2(0.0), vec2(1.0)); // 夹在纹素内。
    return textureGrad(tex, (texelCenter + texelOffset) * pixelSize, du, dv); // 用屏幕导数选层级，避免摩尔纹。
}

// 旋转网格的四个子样本位置：绕纹素中心转四十五度，坐标范围在正负零点三七五之间。
vec2 ogxRgssOffset(int index)
{
    if (index == 0) return vec2(0.125, 0.375); // 右下。
    if (index == 1) return vec2(-0.125, -0.375); // 左上。
    if (index == 2) return vec2(0.375, -0.125); // 右上。
    return vec2(-0.375, 0.125); // 左下。
}

// 旋转网格超采样：四个旋转四十五度的子样本，再按贴图缩放程度与最近点取样混合。
// 为什么按缩放混合：缩小时子样本能压住闪烁，放大时最近点更锐利，两者切换要平滑。
vec4 ogxRgssSample(sampler2D tex, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv)
{
    vec2 texelScreenSize = sqrt(du * du + dv * dv); // 一个屏幕像素在各方向的纹素覆盖量。
    float maxTexelSize = max(texelScreenSize.x, texelScreenSize.y); // 较大的那个方向。
    float minPixelSize = min(pixelSize.x, pixelSize.y); // 贴图最小纹素边长。
    float blendFactor = smoothstep(minPixelSize, minPixelSize * 2.0, maxTexelSize); // 缩得越多越偏向超采样。
    float minDerivative = min(length(du), length(dv)); // 两个方向的导数长度。
    float maxDerivative = max(length(du), length(dv));
    float mipLevel = max(0.0, log2(sqrt(minDerivative * maxDerivative) / minPixelSize)); // 按几何平均选层级。
    vec4 rgss = vec4(0.0); // 四个子样本的累加。
    for (int i = 0; i < 4; i++)
    {
        vec2 corner = ogxRgssOffset(i); // 旋转网格上的第 i 个子样本。
        rgss += textureLod(tex, uv + corner * pixelSize, mipLevel); // 带层级采样。
    }
    rgss *= 0.25; // 四个样本取平均。
    vec4 nearest = ogxSampleNearest(tex, uv, pixelSize, du, dv, texelScreenSize); // 最近点结果。
    return mix(nearest, rgss, blendFactor); // 按缩放程度混合。
}

// 抗锯齿抖动序列：`responsive` 为真时用四帧循环，否则用八帧的哈尔顿序列。
// 为什么两套：快速移动的画面需要更短的历史，静止画面用八帧能把边缘修得更平。
vec2 ogxTaaJitter(int frame, bool responsive)
{
    if (responsive)
    {
        int index = frame % 4; // 四帧一循环。
        if (index == 0) return vec2(-0.125, -0.875); // 左上。
        if (index == 1) return vec2(0.875, -0.125); // 右上。
        if (index == 2) return vec2(0.125, 0.875); // 右下。
        return vec2(-0.875, 0.125); // 左下。
    }
    int index = frame % 8; // 八帧一循环。
    if (index == 0) return vec2(1.0, -3.0) / 8.0; // 第一点。
    if (index == 1) return vec2(-1.0, 3.0) / 8.0; // 第二点。
    if (index == 2) return vec2(5.0, 1.0) / 8.0; // 第三点。
    if (index == 3) return vec2(-3.0, -5.0) / 8.0; // 第四点。
    if (index == 4) return vec2(-5.0, 5.0) / 8.0; // 第五点。
    if (index == 5) return vec2(-7.0, -1.0) / 8.0; // 第六点。
    if (index == 6) return vec2(3.0, 7.0) / 8.0; // 第七点。
    return vec2(7.0, 7.0) / 8.0; // 第八点。
}
// 两个互质基数：二与三，和参考包的低差异序列一致。
// 哈尔顿序列：把序号写成给定基数的小数，逐位排在小数点之后，得到低差异采样。
// 用途与蓝噪声相同，但不需要贴图；二分与三分基数的二维版本分布最均匀。
float ogxHalton2(int index)
{
    float result = 0.0;
    float fraction = 0.5;
    int i = max(index, 1);
    while (i > 0)
    {
        result += fraction * float(i & 1);
        i >>= 1;
        fraction *= 0.5;
    }
    return result;
}

float ogxHalton3(int index)
{
    float result = 0.0;
    float fraction = 1.0 / 3.0;
    int i = max(index, 1);
    while (i > 0)
    {
        result += fraction * float(i % 3);
        i /= 3;
        fraction /= 3.0;
    }
    return result;
}

#endif

/*
生成文件：噪声模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库噪声模块：整数哈希、二维与三维值噪声、分形叠加。
调用位置：云、雾、水面细节与测试世界的地形着色；Minecraft 光影由 `/omni-gfx/noise.glsl` 引入。
可复制示例：
    float n = ogxValueNoise3(position * 0.1); // 取一个平滑的三维噪声。
    float f = ogxFbm2(uv * 4.0, 4); // 四层二维分形噪声。
设计原因与取舍：
    全部用整数哈希与插值生成，不读取噪声贴图，因此同一份源能生成 GLSL 与 SPIR-V，
    也能在不启动 Minecraft 的测试世界里重复出图。常数来自旧测试世界的 `noise.glsl`，
    迁移只改名字与类型写法，画面保持一致。
*/
#ifndef OGX_NOISE_INCLUDED
#define OGX_NOISE_INCLUDED

// 数学模块提供夹紧、重映射与圆周率等基础函数。

// 三维整数哈希：把格点坐标与种子混成一个零到一的伪随机数。
float ogxHash13(vec3 p)
{
    p = fract(p * 0.1031); // 先压到小数范围，减少大坐标的精度损失。
    p += dot(p, p.yzx + 33.33); // 三个分量互相混合。
    return fract((p.x + p.y) * p.z); // 取小数部分作为结果。
}

// 二维整数哈希：只需要平面坐标时比三维版本少一半计算。
float ogxHash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 33.33); // 互相混合，打散相邻格点的规律。
    return fract((p3.x + p3.y) * p3.z); // 零到一的伪随机数。
}

// 二维向量哈希：把平面格点变成一个二维随机方向，供旋度噪声与雨点涟漪定位。
// 与标量哈希共用同一组无理数，三个分量互相混合后再取两次小数部分。
vec2 ogxHash22(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973)); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 19.19); // 三个分量互相打散。
    return fract((vec2(p3.x, p3.x) + vec2(p3.y, p3.z)) * vec2(p3.z, p3.y)); // 取出两个独立的小数。
}

// 二维梯度噪声：四个角点各取一个随机方向，与格内偏移点乘后按平滑曲线插值。
// 返回的是解析梯度，不是噪声值；旋度噪声只关心梯度方向，所以这里直接给出两个分量的偏导。
vec2 ogxPerlinGradient2(vec2 coord)
{
    vec2 i = floor(coord); // 格子角点。
    vec2 f = fract(coord); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 插值权重。
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 梯度权重，照 Eclipse 的写法保留。
    vec2 g0 = normalize(ogxHash22(i) - vec2(0.5)); // 左下方向。
    vec2 g1 = normalize(ogxHash22(i + vec2(1.0, 0.0)) - vec2(0.5)); // 右下方向。
    vec2 g2 = normalize(ogxHash22(i + vec2(0.0, 1.0)) - vec2(0.5)); // 左上方向。
    vec2 g3 = normalize(ogxHash22(i + vec2(1.0, 1.0)) - vec2(0.5)); // 右上方向。
    float v0 = dot(g0, f); // 四个角点与偏移的点乘。
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));
    vec2 omu = vec2(1.0) - u; // 反向权重。
    return vec2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的偏导。
}

// 二维旋度：把梯度旋转九十度，得到无散度的矢量场，卷云的丝状弯曲靠它。
vec2 ogxCurl2D(vec2 coord)
{
    vec2 gradient = ogxPerlinGradient2(coord); // 先取梯度。
    return vec2(gradient.y, -gradient.x); // 旋转九十度就是旋度。
}

// 白噪声：两个坐标点乘一组无理数后取正弦，成本只有一个点乘与一次正弦。
// 为什么不用哈希：需要连续坐标上的随机值时，正弦哈希不会在整数格上出现明显的方块。
float ogxWhiteNoise(vec2 coord)
{
    return fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453);
}

// 随时间滚动的白噪声：每帧给坐标加一个小偏移，静止画面上不会留下固定花纹。
float ogxWhiteNoiseTemporal(vec2 coord, float time)
{
    return ogxWhiteNoise(coord + 0.07 * fract(time));
}

// 三角分布噪声：把均匀分布先开方再减符号，取值集中在零附近，两端衰减。
// 抖动要的是这种“多数很小、少数较大”的分布，均匀分布会让画面出现均匀的沙粒感。
float ogxTriangleNoise(vec2 coord, float time)
{
    float center = ogxWhiteNoiseTemporal(coord, time) * 2.0 - 1.0;
    float shaped = center * inversesqrt(max(abs(center), 1e-10));
    shaped = max(-1.0, shaped);
    return shaped - sign(center);
}

// 整数哈希：三次“右移异或再乘常数”，把整数格打散成不相关的三个分量。
// 写法来自 `Inigo Quilez` 的整数哈希；末地雾按整数格重复取样，需要每个显卡逐位一致的结果。
uvec3 ogxIntegerHash3(uvec3 x)
{
    const uint k = 1103515245u; // 线性同余发生器常用的乘数，异或后能把相邻格彻底打散。
    x = ((x >> 8u) ^ x.yzx) * k; // 第一次：每个分量掺入下一个分量的高二十四位。
    x = ((x >> 8u) ^ x.yzx) * k; // 第二次：再打散一轮，消除一轮不够时的相关性。
    x = ((x >> 8u) ^ x.yzx) * k; // 第三次：三轮之后三个分量的每一位都互相影响。
    return x; // 返回三个独立的整数随机值。
}

// 三维值噪声：八个格点各取哈希，再按平滑曲线插值。
float ogxValueNoise3(vec3 p)
{
    vec3 i = floor(p); // 所在格子的整数角。
    vec3 f = fract(p); // 格子内的小数位置。
    f = f * f * (3.0 - 2.0 * f); // 平滑曲线让格子边界没有折线。
    float n000 = ogxHash13(i + vec3(0.0, 0.0, 0.0)); // 八个角点。
    float n100 = ogxHash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = ogxHash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = ogxHash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = ogxHash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = ogxHash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = ogxHash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = ogxHash13(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x); // 先沿横向插值。
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y); // 再沿纵向插值。
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z); // 最后沿深度插值。
}

// 二维值噪声：四个角点插值，适合云层的平面形状与水面细节。
float ogxValueNoise2(vec2 p)
{
    vec2 i = floor(p); // 格子角点。
    vec2 f = fract(p); // 格内位置。
    f = f * f * (3.0 - 2.0 * f); // 平滑曲线。
    float a = ogxHash12(i); // 四个角。
    float b = ogxHash12(i + vec2(1.0, 0.0));
    float c = ogxHash12(i + vec2(0.0, 1.0));
    float d = ogxHash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); // 双线性插值。
}

// 二维分形叠加：每层频率翻倍、权重减半，得到自然起伏。
float ogxFbm2(vec2 p, int octaves)
{
    float sum = 0.0; // 累加结果。
    float amplitude = 0.5; // 当前层权重。
    for (int i = 0; i < octaves; i++) // 层数由调用方控制。
    {
        sum += ogxValueNoise2(p) * amplitude; // 加入当前层。
        p = p * 2.03 + vec2(17.0, 31.0); // 频率翻倍并偏移，减少层间重合。
        amplitude *= 0.5; // 高层权重减半。
    }
    return sum; // 零到一附近。
}

// 三维分形叠加：每层频率翻倍、权重减半，供云的细节与雾团使用。
float ogxFbm3(vec3 p, int octaves)
{
    float sum = 0.0; // 累加结果。
    float amplitude = 0.5; // 当前层权重。
    for (int i = 0; i < octaves; i++) // 固定上限，避免不同显卡的循环次数差异。
    {
        sum += ogxValueNoise3(p) * amplitude; // 加入当前层。
        p = p * 2.03 + vec3(17.0, 9.0, 31.0); // 频率翻倍并偏移。
        amplitude *= 0.5; // 高层权重减半。
    }
    return sum; // 大致零到一之间。
}

// 三维扭曲：用三个低频噪声把采样坐标推开，打断值噪声的网格重复。
vec3 ogxWarp3(vec3 p, float strength)
{
    vec3 offset = vec3(ogxValueNoise3(p + vec3(0.0, 0.0, 0.0)), // 横向偏移。
                           ogxValueNoise3(p + vec3(31.4, 17.2, 5.7)), // 纵向偏移。
                           ogxValueNoise3(p + vec3(7.9, 43.1, 23.6))) - 0.5; // 深度偏移。
    return p + offset * strength; // 偏移量按强度缩放后加到原坐标。
}

// 三维噪声查表：把三维格点映射到二维噪声图，再用高度做一次插值。
// 为什么用查表：噪声图的纹素已经做过低差异处理，比现场算哈希更均匀，也更快。
// 该函数被雾、降水高光与水面共用，因此放在噪声模块，而不是某一个效果里。
float ogxFogNoise(vec3 position, sampler2D noiseTexture)
{
    vec3 p = floor(position); // 整数格。
    vec3 f = position - p; // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 三次曲线平滑小数部分。
    vec2 uv = 17.0 * p.z + p.xy + f.xy; // 把三维格点映射到二维噪声坐标。
    vec2 n = textureLod(noiseTexture, uv * 0.015625 + 0.0078125, 0.0).zw; // 读取噪声图的后两个通道。
    return mix(n.x, n.y, f.z); // 按高度做一次插值。
}

#endif

/*
生成文件：大气模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库大气模块：球面几何、密度剖面、单次散射与空气透视。
调用位置：天空、地形远景、水面与云的环境光；Minecraft 光影由 `/omni-gfx/atmosphere.glsl` 引入。
可复制示例：
    OgxAtmosphere a = ogxAtmosphereEarth(); // 取一组地球常数。
    vec3 s = ogxAtmosphereSky(a, 0.03, viewDir, sunDir, 10); // 算天空颜色。
    vec3 h = ogxAerialPerspective(a, 0.03, viewDir, 1.5, sunDir, 5, t2); // 算远景空气散射。
设计原因与取舍：
    公式来自旧 `shaders/gfx/atmosphere.glsl` 的球面几何与密度剖面，并补上可独立运行的单次散射积分。
    不读取预计算贴图，换机器与不启动 Minecraft 都能得到同一片天空；代价是每像素多几次指数运算。
    长度单位统一为公里，避免行星半径用米时 float 精度不足；调用方把米乘零点零零一。
    太阳与月亮方向、散射系数、行星半径全部由调用方传入，库不读取任何引擎状态。
*/
#ifndef OGX_ATMOSPHERE_INCLUDED
#define OGX_ATMOSPHERE_INCLUDED

// 数学模块提供相函数、射线求交与夹紧。

// 一次大气计算需要的全部常数；不同星球换一组字段即可，不必改算法。
struct OgxAtmosphere
{
    float planetRadius; // 行星底半径，公里。
    float atmosphereRadius; // 大气层顶半径，公里。
    float rayleighHeight; // 瑞利密度衰减高度，公里。
    float mieHeight; // 米氏密度衰减高度，公里。
    vec3 rayleighScattering; // 瑞利散射系数，每公里。
    vec3 mieScattering; // 米氏散射系数，每公里。
    vec3 ozoneAbsorption; // 臭氧吸收系数，每公里。
    float mieG; // 米氏相位的前向集中程度。
    float sunIntensity; // 太阳辐照度的整体倍率。
};

// 地球参数：海平面半径六千三百六十公里，层顶八十公里，数值与旧库一致。
OgxAtmosphere ogxAtmosphereEarth()
{
    OgxAtmosphere air; // 先声明再逐项填写，Slang 与 GLSL 都支持这种写法。
    air.planetRadius = 6360.0; // 地球半径，公里。
    air.atmosphereRadius = 6440.0; // 大气层顶，海平面以上八十公里。
    air.rayleighHeight = 8.0; // 瑞利散射主要由低空空气造成。
    air.mieHeight = 1.2; // 米氏散射集中在更低的雾霾层。
    air.rayleighScattering = vec3(5.8e-3, 13.5e-3, 33.1e-3); // 蓝光散射最强，天空因此偏蓝。
    air.mieScattering = vec3(1.0e-3, 1.0e-3, 1.0e-3); // 气溶胶散射近似中性灰，压低地平线白雾。
    air.ozoneAbsorption = vec3(0.65e-3, 1.881e-3, 0.085e-3); // 臭氧吸收少量红光与蓝光。
    air.mieG = 0.62; // 前向散射明显，太阳附近出现白晕。
    air.sunIntensity = 13.0; // 与测试世界的曝光配合，保持高动态范围。
    return air; // 返回一组可直接使用的常数。
}

// 臭氧剖面：十公里以下没有，二十五公里最浓，四十公里以上消失。
float ogxAtmosphereOzoneProfile(float altitude)
{
    float x = (altitude - 10.0) / 30.0; // 把十到四十公里映射到零到一。
    return max(1.0 - abs(x * 2.0 - 1.0), 0.0); // 三角形剖面，峰值在二十五公里。
}

// 瑞利密度：高度越高越稀薄，指数衰减。
float ogxAtmosphereDensityRayleigh(OgxAtmosphere air, float altitude)
{
    return exp(-max(altitude, 0.0) / air.rayleighHeight); // 负高度按海平面处理。
}

// 米氏密度：同样指数衰减，但衰减高度更短。
float ogxAtmosphereDensityMie(OgxAtmosphere air, float altitude)
{
    return exp(-max(altitude, 0.0) / air.mieHeight); // 气溶胶集中在低空。
}

// 视线到球面远交点的距离；相机在球内时取正根。
float ogxAtmosphereDistanceToTop(vec3 origin, vec3 direction, float radius)
{
    float b = dot(origin, direction); // 球面方程的中间项。
    float c = dot(origin, origin) - radius * radius; // 常数项。
    float discriminant = b * b - c; // 判别式。
    if (discriminant < 0.0) // 没有交点说明视线完全在球外。
    {
        return 0.0; // 返回零，调用方据此跳过。
    }
    return max(-b + sqrt(discriminant), 0.0); // 远交点，负值夹到零。
}

// 视线到行星地面的距离；没有打到地面时通过 `hit` 交回假。
float ogxAtmosphereDistanceToGround(vec3 origin, vec3 direction, float radius, out bool hit)
{
    float b = dot(origin, direction); // 球面方程中间项。
    float c = dot(origin, origin) - radius * radius; // 常数项。
    float discriminant = b * b - c; // 判别式。
    if (discriminant < 0.0) // 没有交点。
    {
        hit = false; // 告诉调用方没有地面。
        return 0.0; // 距离无意义。
    }
    float near = -b - sqrt(discriminant); // 近交点。
    if (near < 0.0) // 相机在地面以下或交点在身后。
    {
        hit = false; // 不把背后的地面算进来。
        return 0.0;
    }
    hit = true; // 真正打到前方地面。
    return near; // 返回近交点距离。
}

// 一段视线上的光学厚度：分别累加瑞利、米氏与臭氧三组密度。
vec3 ogxAtmosphereOpticalDepth(OgxAtmosphere air, vec3 origin, vec3 direction, float distance)
{
    vec3 depth = vec3(0.0); // 三组光学厚度。
    if (distance <= 0.0) // 零长度不产生遮挡。
    {
        return depth; // 直接返回零。
    }
    const int steps = 8; // 固定八段，保证不同显卡的耗时接近。
    float stepLength = distance / float(steps); // 每段长度。
    vec3 position = origin + direction * (stepLength * 0.5); // 从第一段中点开始。
    for (int i = 0; i < steps; i++) // 逐段累加。
    {
        float altitude = length(position) - air.planetRadius; // 这一段所在高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float ozone = ogxAtmosphereOzoneProfile(altitude); // 臭氧密度。
        depth += vec3(rayleigh, mie, ozone) * stepLength; // 密度乘段长。
        position += direction * stepLength; // 前进到下一段。
    }
    return depth; // 返回三组光学厚度。
}

// 由光学厚度算透过率：散射系数与臭氧吸收共同消光。
vec3 ogxAtmosphereTransmittance(OgxAtmosphere air, vec3 opticalDepth)
{
    vec3 extinction = air.rayleighScattering * opticalDepth.x // 瑞利消光。
                      + air.mieScattering * opticalDepth.y // 米氏消光。
                      + air.ozoneAbsorption * opticalDepth.z; // 臭氧吸收。
    return exp(-extinction); // 比尔-朗伯定律。
}

// 某点朝太阳方向到层顶的透过率；太阳贴地时自然变暗。
vec3 ogxAtmosphereSunTransmittance(OgxAtmosphere air, vec3 position, vec3 sunDirection, int steps)
{
    float distanceToTop = ogxAtmosphereDistanceToTop(position, sunDirection, air.atmosphereRadius); // 到层顶的距离。
    if (distanceToTop <= 0.0) // 太阳在地平线以下或视线没有交点。
    {
        return vec3(0.0); // 没有直射阳光。
    }
    const int maxSteps = 4; // 固定上限，调用方只能在这个范围内减少。
    int count = min(max(steps, 1), maxSteps); // 至少一段，最多四段。
    vec3 depth = vec3(0.0); // 太阳方向的光学厚度。
    float stepLength = distanceToTop / float(count); // 每段长度。
    vec3 samplePosition = position + sunDirection * (stepLength * 0.5); // 第一段中点。
    for (int i = 0; i < maxSteps; i++) // 固定循环上限。
    {
        if (i >= count) // 超过调用方要求的段数就停止。
        {
            break; // 提前结束，避免多做指数运算。
        }
        float altitude = length(samplePosition) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float ozone = ogxAtmosphereOzoneProfile(altitude); // 臭氧密度。
        depth += vec3(rayleigh, mie, ozone) * stepLength; // 累加密度乘段长。
        samplePosition += sunDirection * stepLength; // 前进。
    }
    return ogxAtmosphereTransmittance(air, depth); // 换成透过率。
}

// 天空辐射：沿视线做单次散射积分，包含地面遮挡与地面反弹。
vec3 ogxAtmosphereSky(OgxAtmosphere air, float cameraAltitude, vec3 viewDirection, vec3 sunDirection, int steps)
{
    vec3 origin = vec3(0.0, air.planetRadius + max(cameraAltitude, 0.0), 0.0); // 相机放在行星正上方。
    float distanceToTop = ogxAtmosphereDistanceToTop(origin, viewDirection, air.atmosphereRadius); // 到层顶的距离。
    bool groundHit; // 视线是否打到地面。
    float distanceToGround = ogxAtmosphereDistanceToGround(origin, viewDirection, air.planetRadius, groundHit); // 到地面的距离。
    float maxDistance = distanceToTop; // 默认积到层顶。
    if (groundHit && distanceToGround < maxDistance) // 地面比层顶更近时积到地面。
    {
        maxDistance = distanceToGround; // 地面挡住后面的空气。
    }
    if (maxDistance <= 0.0) // 视线没有穿过大气。
    {
        return vec3(0.0); // 返回黑色。
    }
    const int maxSteps = 12; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = maxDistance / float(count); // 每段长度。
    vec3 scattered = vec3(0.0); // 累积的散射光。
    vec3 transmittance = vec3(1.0); // 到当前段为止的透过率。
    vec3 position = origin + viewDirection * (stepLength * 0.5); // 第一段中点。
    float nu = dot(viewDirection, sunDirection); // 视线与太阳夹角余弦。
    float rayleighPhase = ogxRayleighPhase(nu); // 瑞利相函数。
    float miePhase = ogxMiePhase(air.mieG, nu); // 米氏相函数。
    for (int i = 0; i < maxSteps; i++) // 逐段积分。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float altitude = length(position) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        vec3 sunTransmittance = ogxAtmosphereSunTransmittance(air, position, sunDirection, 3); // 阳光到这里还剩多少。
        vec3 extinction = air.rayleighScattering * rayleigh + air.mieScattering * mie; // 这一段的消光系数。
        vec3 inScatter = (air.rayleighScattering * (rayleigh * rayleighPhase) // 瑞利散射。
                          + air.mieScattering * (mie * miePhase)) // 米氏散射。
                          * sunTransmittance * air.sunIntensity; // 乘阳光透过率与强度。
        scattered += inScatter * transmittance * stepLength; // 按剩余透过率累加。
        transmittance *= exp(-extinction * stepLength); // 更新剩余透过率。
        position += viewDirection * stepLength; // 前进到下一段。
    }
    if (groundHit) // 视线落到地面时补一层地面反射。
    {
        vec3 groundPosition = origin + viewDirection * maxDistance; // 地面交点。
        vec3 groundNormal = normalize(groundPosition); // 球面法线。
        vec3 sunTransmittance = ogxAtmosphereSunTransmittance(air, groundPosition, sunDirection, 3); // 地面处的阳光。
        float groundLight = max(dot(groundNormal, sunDirection), 0.0); // 地面受光余弦。
        scattered += air.sunIntensity * sunTransmittance * groundLight * 0.02; // 低反照率地面，避免抢走地形。
    }
    return max(scattered, vec3(0.0)); // 数值误差不产生负颜色。
}

// 空气透视：相机到某个世界点的散射与透过率；地形、水面与云的远景都调用它。
vec3 ogxAerialPerspective(OgxAtmosphere air, float cameraAltitude, vec3 viewDirection, float distance,
                            vec3 sunDirection, int steps, out vec3 transmittance)
{
    transmittance = vec3(1.0); // 默认没有遮挡。
    if (distance <= 0.0) // 零距离不产生空气透视。
    {
        return vec3(0.0); // 没有散射。
    }
    vec3 origin = vec3(0.0, air.planetRadius + max(cameraAltitude, 0.0), 0.0); // 相机在行星正上方。
    const int maxSteps = 6; // 固定循环上限，远景不需要天空那么细。
    int count = min(max(steps, 1), maxSteps); // 按调用方要求减少段数。
    float stepLength = distance / float(count); // 每段长度。
    vec3 scattered = vec3(0.0); // 累积散射。
    vec3 position = origin + viewDirection * (stepLength * 0.5); // 第一段中点。
    float nu = dot(viewDirection, sunDirection); // 视线与太阳夹角。
    float rayleighPhase = ogxRayleighPhase(nu); // 瑞利相函数。
    float miePhase = ogxMiePhase(air.mieG, nu); // 米氏相函数。
    for (int i = 0; i < maxSteps; i++) // 逐段积分。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float altitude = length(position) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        vec3 sunTransmittance = ogxAtmosphereSunTransmittance(air, position, sunDirection, 2); // 阳光到这里的透过率。
        vec3 extinction = air.rayleighScattering * rayleigh + air.mieScattering * mie; // 消光系数。
        vec3 inScatter = (air.rayleighScattering * (rayleigh * rayleighPhase) // 瑞利散射。
                          + air.mieScattering * (mie * miePhase)) // 米氏散射。
                          * sunTransmittance * air.sunIntensity; // 阳光强度。
        scattered += inScatter * transmittance * stepLength; // 按剩余透过率累加。
        transmittance *= exp(-extinction * stepLength); // 更新透过率。
        position += viewDirection * stepLength; // 前进。
    }
    return max(scattered, vec3(0.0)); // 返回这段空气的散射色。
}

// 太阳圆盘：视线越接近太阳方向越亮，边缘用平滑曲线收口。
float ogxSunDisc(vec3 viewDirection, vec3 sunDirection, float size, float hardness)
{
    float d = dot(viewDirection, sunDirection); // 与太阳方向的夹角余弦。
    float x = ogxSaturate((d - (1.0 - size)) * hardness); // 从中心到边缘的遮罩。
    float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
    return disc * disc; // 平方让边缘更收。
}

// iterationT 太阳圆盘：在圆盘遮罩上乘参考实现的暖白色，供原样对照。
vec3 ogxItxSunDisc(vec3 worldDir, vec3 sunDir)
{
    float d = dot(worldDir, sunDir); // 与太阳方向的夹角余弦。
    float size = 5e-5; // 太阳角半径。
    float hardness = 4e4; // 边缘斜率。
    float disc = ogxCurve01(ogxSaturate((d - (1.0 - size)) * hardness)); // 参考实现的平滑曲线。
    disc *= disc; // 平方收边。
    return vec3(1.1114, 0.9756, 0.9133) * disc; // 太阳的暖白色。
}

// 球面几何的另一种写法：只给半径与高度角余弦，省掉每次重建起点向量。
// 与旧 `shaders/gfx/atmosphere.glsl` 的算式逐项一致，供预计算查表的坐标映射使用。
float ogxSphereDistanceToTop(float r, float mu, float topRadius)
{
    float discriminant = r * r * (mu * mu - 1.0) + topRadius * topRadius; // 交点判别式。
    return max(-r * mu + sqrt(max(discriminant, 0.0)), 0.0); // 取朝向层顶一侧的根。
}

// 视线到大气层底的距离，解球面方程取近根。
float ogxSphereDistanceToBottom(float r, float mu, float bottomRadius)
{
    float discriminant = r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius; // 球面交点判别式。
    return max(-r * mu - sqrt(max(discriminant, 0.0)), 0.0); // 取靠近相机一侧的根。
}

// 判断一条朝下的视线是否真的打到地面球。
bool ogxSphereRayIntersectsGround(float r, float mu, float bottomRadius)
{
    return mu < 0.0 && r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius >= 0.0; // 朝下且判别式非负才相交。
}

// 瑞利与米氏密度剖面：以二为底的指数衰减。
float ogxExponentialDensity(float expScale, float altitude)
{
    return exp2(expScale * altitude); // 高度越高密度越低。
}

// 臭氧密度剖面：转折高度以下一段斜线，以上另一段斜线。
float ogxAbsorptionDensity(float width, vec4 profile, float altitude)
{
    return altitude < width ? profile.x * altitude + profile.y : profile.z * altitude + profile.w; // 两段线性剖面。
}

// 把零到一的比例映射到贴图像素中心，避免采到子图交界。
float ogxTexelCenterCoord(float x, float textureSize)
{
    return 0.5 / textureSize + x * (1.0 - 1.0 / textureSize); // 内缩半像素。
}

// 把子图内部比例映射到拼合大图坐标，子图在大图里也内缩半像素。
float ogxSubTextureCoord(float x, float originalSize, float combinedSize)
{
    return 0.5 / combinedSize + x * (originalSize / combinedSize - 1.0 / combinedSize); // 按子图尺寸缩放。
}

// 月亮轨道：由游戏时间、纬度与轨道倾角闭式算出月亮的世界方向，y 轴朝天。
vec3 ogxMoonDirection(float time, float latitude, float pathRotation, float monthLength)
{
    float phi = radians(-latitude); // 观测点纬度，换算成弧度。
    float del = radians(pathRotation); // 月亮轨道相对天赤道的倾角。
    float t = time / 24000.0; // 时间换算成天。
    t *= 1.0 + 1.0 / monthLength; // 月亮每天比太阳多走一点，长期累积才产生月相与对齐。
    float h = t * 2.0 * OGX_PI - OGX_PI; // 时角，一整天转一圈。
    float sinH = sin(phi) * sin(del) + cos(phi) * cos(del) * cos(h); // 高度角正弦。
    float elevation = asin(clamp(sinH, -1.0, 1.0)); // 高度角；钳一下避免浮点误差让反正弦出非数。
    float cosH = cos(elevation); // 高度角余弦。
    float cosA = (sin(del) - sin(phi) * sinH) / max(cos(phi) * cosH, 1e-4); // 方位角余弦；分母加下限，避免两极附近除零。
    cosA = clamp(cosA, -1.0, 1.0); // 同样钳一下，防止浮点误差越界。
    float A = acos(cosA); // 方位角。
    if (sin(h) > 0.0) // 时角过午时镜像到另一半球。
    {
        A = 2.0 * OGX_PI - A;
    }
    return vec3(cosH * sin(A), sinH, cosH * cos(A)); // 单位方向，y 轴朝天。
}

// 圆盘剖面：由阈值与斜率构成边缘平滑的圆盘，平方后边界更清楚。
float ogxDiscProfile(float a, float s, float h)
{
    float x = ogxSaturate((a - (1.0 - s)) * h); // 由阈值与斜率构成的圆盘剖面。
    float disc = x * x * (3.0 - 2.0 * x); // 平滑收口。
    return disc * disc; // 平方拉开明暗边界。
}

// 把半径夹进大气层范围内，越界时按最近的边界算。
float ogxClampRadius(float r, float bottomRadius, float topRadius)
{
    return clamp(r, bottomRadius, topRadius); // 下不低于地面、上不超过层顶。
}

// 安全开方：负零以下一律当零，避免浮点误差算出非数。
float ogxSafeSqrt(float a)
{
    return sqrt(max(a, 0.0)); // 负数开到零。
}

// 星场散列：把一个方向格打散成零到一的随机数。
// 与噪声模块的通用哈希只差搅动常数（三十一点三二），为保持旧星场分布而单独保留。
float ogxStarHash13(vec3 p3)
{
    p3 = fract(p3 * 0.1031); // 先乘一个小数再取小数部分，打散整数格的规律。
    p3 += dot(p3, p3.zyx + 31.32); // 三个分量互相掺入，避免相邻格出现相近的值。
    return fract((p3.x + p3.y) * p3.z); // 合并三个分量，得到零到一。
}

// 噪声星场：把散列值低于阈值的格子压成零，剩下的当作星点原始亮度。
float ogxStarNoisyField(vec3 samplePos, float threshold)
{
    float starVal = ogxStarHash13(samplePos); // 先取这个格的随机值。
    starVal = clamp(starVal / (1.0 - threshold) - threshold / (1.0 - threshold), 0.0, 1.0); // 阈值以下压到零，剩下归一化到零到一。
    return starVal; // 返回星点亮度。
}

// 稳定星场：只在整数格上取值，再用双线性插值平滑，避免相机移动时星点闪烁。
// 已知代价（Eclipse 原注释承认）：双线性插值会把单个星点拉成十字，这里按合同保留原写法。
float ogxStarStableField(vec3 samplePos, float threshold)
{
    float fractX = fract(samplePos.x); // 当前点在横方向的格内偏移。
    float fractY = fract(samplePos.y); // 当前点在纵方向的格内偏移。
    vec3 floorSample = floor(samplePos.xyz); // 所在整数格。
    float v1 = ogxStarNoisyField(floorSample, threshold); // 左下格的星点亮度。
    float v2 = ogxStarNoisyField(floorSample + vec3(0.0, 1.0, 0.0), threshold); // 左上格。
    float v3 = ogxStarNoisyField(floorSample + vec3(1.0, 0.0, 0.0), threshold); // 右下格。
    float v4 = ogxStarNoisyField(floorSample + vec3(1.0, 1.0, 0.0), threshold); // 右上格。
    float starVal = v1 * (1.0 - fractX) * (1.0 - fractY) // 四角按格内偏移加权求和。
                  + v2 * (1.0 - fractX) * fractY // 左上权重。
                  + v3 * fractX * (1.0 - fractY) // 右下权重。
                  + v4 * fractX * fractY; // 右上权重。
    return starVal; // 平滑后的星点亮度。
}

// 彩色星场散列：只用二维坐标，正弦放大再取小数。
float ogxStarHash12(vec2 co)
{
    return fract(sin(2.0 * OGX_PI * fract(dot(co.xy, vec2(12.9898, 78.233)))) * 43758.5453); // 最常见的二维散列写法。
}

// 星温：把零到一的散列映射成色温，三次方让多数星星偏冷白、少数偏暖。
float ogxStarTemperature(float hash)
{
    return hash * hash * hash * (19000.0 - 5500.0) + 5500.0; // 色温范围五千五到一万九开尔文。
}

// 星面：把方向投到立方体的一面按格撒星，输出该方向的亮度与颜色。
float ogxStarPlane(vec3 dir, out vec3 starColor)
{
    float scale = 1.0 / 600.0; // 格子大小，越小星点越密。
    vec2 basePos = dir.xy * (0.4 / scale) / max(1e-3, abs(dir.z)); // 投到这个面上并按深度缩放。
    starColor = vec3(0.0); // 这个面的星色初值。
    vec2 pos = floor(basePos); // 所在整数格。
    vec2 center = pos + vec2(0.5); // 格中心，用来算到星心的距离。
    float d = distance(basePos, center); // 当前采样点到星心的距离。
    basePos = floor(basePos); // 锁定到格，保证相机移动时星点不飘。
    float color = 0.0; // 这个面的星点亮度。
    if (ogxStarHash12(basePos.xy * scale) > 0.997) // 只有极少数格子有星。
    {
        float radius = 0.4; // 星点半径，越大越胖。
        float brightness = exp(-(d * d) / (2.0 * radius * radius)); // 高斯衰减，星心最亮。
        float r = ogxStarHash12(basePos.xy * 0.5); // 这颗星的随机亮度因子。
        color = r * (0.3 * sin(1.0 * (r * 5.0) + r) + 0.7) * brightness; // 亮度带一点随机起伏。
        starColor = 2.0 * ogxBlackbody(ogxStarTemperature(ogxStarHash12(center))); // 按格中心的散列取色温上色。
    }
    return color * pow(abs(dir.z), 2); // 按该面朝向加权，面边界处平滑过渡。
}

// 星盒：把方向分别当立方体三轴投影，叠出完整六面星场。
float ogxStarBox(vec3 dir, out vec3 starColor)
{
    vec3 starColor1 = vec3(0.0); // 第一组投影的星色。
    vec3 starColor2 = vec3(0.0); // 第二组投影的星色。
    vec3 starColor3 = vec3(0.0); // 第三组投影的星色。
    float color = ogxStarPlane(dir.xyz, starColor1) + ogxStarPlane(dir.yzx, starColor2) + ogxStarPlane(dir.zxy, starColor3); // 三组投影叠亮度。
    starColor = starColor1 + starColor2 + starColor3; // 三组投影叠星色。
    return sqrt(color); // 开方压一下亮度分布，与 Eclipse 一致。
}

// 白色稳定星场：返回星场亮度；星色固定为白，由调用方直接使用。
float ogxStarsStable(vec3 viewPos, float brightness, float amount)
{
    float s = max(1.0 - ogxStarStableField(viewPos * 300.0, 0.99), 0.0); // 采样密度三百、阈值零点九九与 Eclipse 相同。
    return brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 彩色星盒星场：返回亮度并由 `starColor` 回填星色，调用方按需要相乘。
float ogxStarsColored(vec3 viewPos, float brightness, float amount, out vec3 starColor)
{
    starColor = vec3(1.0); // 星色由星盒回填，这里先给初值。
    float s = max(1.0 - ogxStarBox(viewPos, starColor), 0.0); // 彩色星盒星场。
    return 75.0 * brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 把视线方向绕太阳轴旋转对齐天球：罗德里格旋转公式，太阳方向由调用方传入。
// 这样星场会跟着太阳的年周期转，而不是固定在天球上。
vec3 ogxAlignToSunAxis(vec3 worldDir, vec3 sunVector)
{
    float cosine = dot(sunVector, vec3(0.0, 0.0, 1.0)); // 太阳轴与参考轴夹角余弦。
    vec3 axis = cross(sunVector, vec3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
    return cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式对齐星场。
}

// 真实月亮圆盘：角半径由尺寸档位换算，档位越大圆盘越大。
float ogxMoonDiscReal(vec3 worldDir, vec3 moonDir, float sizeSetting)
{
    float moonSize = 0.999 + (10.0 - sizeSetting) * 0.0001; // 档位越大圆盘越大。
    return ogxDiscProfile(dot(worldDir, moonDir), 1.0 - moonSize, 1.0 / (1.0 - moonSize)); // 用圆盘剖面收边。
}

// 默认月亮圆盘：比太阳更硬、更小的圆盘。
float ogxMoonDiscDefault(vec3 worldDir, vec3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 5e-5, 1e5); // 默认月亮更硬更小。
}

// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float ogxMoonDiscReflection(vec3 worldDir, vec3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 0.0025, 300.0); // 反射用更大的角半径与更软的边缘。
}

// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ogxSkyProject` 互为逆。
// `tileSize` 是单张面的边长；结果不带屏幕偏移，由调用方按自己的贴图布局追加。
vec3 ogxSkyUnproject(vec2 texel, float tileSize)
{
    float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
    vec3 direction = vec3(0.0); // 待求的世界方向。
    if (texel.x < tileSize) // 第一张面，朝横轴正负。
    {
        direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else if (texel.x < 2.0 * tileSize) // 第二张面，朝纵轴正负。
    {
        direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else // 第三张面，朝深度轴正负。
    {
        direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
        direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
    }
    return normalize(direction); // 单位世界方向。
}

// 把一个世界方向投到天空盒三维贴图上，与 `ogxSkyUnproject` 互为逆。
vec2 ogxSkyProject(vec3 dir, float tileSize)
{
    float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
    vec3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
    vec2 texel; // 待求的纹素坐标。
    if (adir.x > adir.y && adir.x > adir.z) // 横分量最大时用第一张面。
    {
        dir /= adir.x; // 归一化主轴分量。
        texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
    }
    else if (adir.y > adir.x && adir.y > adir.z) // 纵分量最大时用第二张面。
    {
        dir /= adir.y; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
    }
    else // 否则用第三张面。
    {
        dir /= adir.z; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
        texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
    }
    return texel; // 返回纹素坐标，屏幕偏移由调用方追加。
}

// 等距圆柱投影：把世界方向换成经纬度贴图坐标。
// 与 `ogxSkyProject` 的差别是贴图布局不同：这里是左右铺经度、上下铺纬度的整张天球图，
// 六面天空盒用的是 3×2 的瓦片图集；两套布局不能混用。`y` 零在正下方、一在正上方。
vec2 ogxSkyEquirect(vec3 direction)
{
    float longitude = clamp(ogxAtan2(vec2(-direction.z, -direction.x)), -OGX_PI, OGX_PI); // 绕竖直轴的角度，正面为零。
    float latitude = asin(clamp(direction.y, -1.0, 1.0)); // 高度角，正上为正。
    return vec2(longitude * (0.5 / OGX_PI) + 0.5, latitude * (1.0 / OGX_PI) + 0.5); // 归一到零到一。
}

// 天空云图坐标：经纬坐标先夹进贴图，再按调用方给的子图布局换成纹素坐标。
// 为什么布局要显式传入：参考光影把云图塞在整屏缓冲的一个小角落里，位置与边长随分辨率变化；
// 库里只保留“方向到子图坐标”的换算，具体放在哪由宿主决定，换布局不必改算法。
// `texelSize` 是整张贴图的纹素大小，`origin` 是子图左上角的纹素坐标，`tile` 是子图边长。
vec2 ogxSkyCloudAtlasCoord(vec3 direction, vec2 texelSize, vec2 origin, float tile)
{
    vec2 p = clamp(ogxSkyEquirect(direction), vec2(0.0), vec2(1.0)); // 经纬坐标夹进子图范围。
    return p * tile * texelSize + origin * texelSize; // 子图内部按纹素换算到整图坐标。
}

// 读天空云图：按方向取对应经纬度的云颜色与覆盖率，四个通道原样返回。
// `skyTex` 是显式传入的采样器，库不绑定任何宿主纹理；过滤方式由调用方设置。
vec4 ogxSkyCloudsFromTex(sampler2D skyTex, vec3 direction, vec2 texelSize, vec2 origin, float tile)
{
    vec2 uv = ogxSkyCloudAtlasCoord(direction, texelSize, origin, tile); // 方向换成子图内的纹理坐标。
    return textureLod(skyTex, uv, 0.0); // 零号层级，不做各向异性过滤。
}

// 按粗糙度收拢的天空云图采样：粗糙度越大，靠近天顶的云越向观测方向压缩。
// 为什么按高度分界：地平线附近的云本来就叠在一起，粗糙度只该影响头顶那片，
// 否则远处的云会被整片抹平。`roughness` 零到一，由材质粗糙度或模糊强度给出。
vec4 ogxSkyCloudsFromTexLod(sampler2D skyTex, vec3 direction, vec2 texelSize, vec2 origin, float tile,
    float roughness)
{
    vec2 p = ogxSkyEquirect(direction); // 经纬坐标。
    roughness = 1.0 - pow(1.0 - roughness, 3.0); // 三次曲线让低粗糙度变化更细。
    float high = min(max(p.y - 0.5, 0.0) * 50.0, 1.0); // 只有天顶那半边的云参与收拢。
    p = mix(p, (p - 0.5) * (1.0 - roughness) + 0.5, high); // 按粗糙度把坐标朝中心压缩。
    p = clamp(p * 2.0 - 1.0, vec2(-1.0), vec2(1.0)) * 0.5 + 0.5; // 压缩后再夹一次，边缘不越界。
    return textureLod(skyTex, p * tile * texelSize + origin * texelSize, 0.0); // 取子图内的颜色。
}

// 极光：夜晚高空的缓慢帘幕，雨天被云遮挡；`tint` 为正偏绿、为负偏蓝紫。
vec3 ogxAurora(vec3 color, vec3 direction, vec3 sunDirection, float time, float wetness, float tint, float strength)
{
    float night = 1.0 - smoothstep(-0.2, 0.1, sunDirection.y); // 太阳越低夜色越浓，极光越亮。
    float ripple = 0.5 + 0.5 * sin(direction.x * 6.0 + time * 0.02) * sin(direction.z * 5.0 - time * 0.015); // 两个方向的正弦交叉出缓慢起伏。
    float curtain = pow(max(0.0, sin(direction.x * 18.0 + ripple * 3.0)), 8.0); // 帘幕随位置起伏、随时间缓慢移动。
    vec3 auroraColor = mix(vec3(0.12, 0.16, 0.50), vec3(0.08, 0.35, 0.20), 0.5 + 0.5 * tint); // 极光颜色：正值偏绿、负值偏蓝紫。
    return color + auroraColor * curtain * smoothstep(0.1, 0.5, direction.y) * (1.0 - wetness) * night * strength; // 帘幕只露在高空，雨云之下熄灭。
}

// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
vec3 ogxRainbow(vec3 color, vec3 direction, vec3 sunDirection, float wetness, float strength)
{
    float angle = acos(clamp(dot(direction, -sunDirection), -1.0, 1.0)); // 与背太阳方向的夹角。
    float offset = (angle - 0.733) / 0.018; // 相对约四十二度彩虹角的偏移。
    float band = exp(-offset * offset); // 窄带：只用乘法构成，避开对负数取幂的未定义结果。
    vec3 spectrum = 0.5 + 0.5 * cos((angle - 0.72) * 120.0 + vec3(0.0, 2.1, 4.2)); // 角度到红橙黄绿的彩色谱。
    return color + spectrum * band * wetness * (1.0 - wetness) * smoothstep(0.0, 0.1, direction.y) * strength; // 只在雨停后仍湿润时出现。
}

// 钱德拉塞卡近似：各项同性散射的倍增因子，反照率越高、余弦越大越亮。
vec3 ogxChandrasekharH(vec3 albedo, float a)
{
    vec3 R = sqrt(vec3(1.0) - albedo); // 单次散射反照率的平方根。
    vec3 r = (1.0 - R) / (1.0 + R); // 反射率比值。
    vec3 h = r + (0.5 - r * a) * log((1.0 + a) / a); // 钱德拉塞卡近似。
    h *= albedo * a; // 乘反照率与余弦项。
    return 1.0 / (1.0 - h); // 取倒数得到倍增。
}

// 行星表面双向反射：入射与出射两侧各算一次钱德拉塞卡近似，再除以相函数分母。
vec3 ogxPlanetBrdf(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir)
{
    float NdotL = dot(normal, lightDir); // 法线与光方向夹角余弦。
    float NdotV = dot(normal, eyeDir); // 法线与视线夹角余弦。
    albedo *= clamp(NdotL, 0.0, 1.0) * clamp(NdotL, 0.0, 1.0) * (3.0 - 2.0 * clamp(NdotL, 0.0, 1.0)); // 反照率按入射角衰减。
    vec3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 两侧近似与相函数分母。
    return clamp(color, 0.0, 1.0); // 夹到合理范围。
}

// 行星环带噪声：五层噪声叠出环带细缝，返回已经去掉偏移的累加值。
float ogxPlanetRingNoise(float position, sampler2D noiseTexture)
{
    const float octAlpha = 0.5; // 每层噪声的权重衰减。
    const float octScale = 4.0; // 每层频率放大。
    const float octShift = (octAlpha / octScale) / 5.0; // 层间偏移。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 当前层权重。
    for (int i = 0; i < 5; i++) // 五层噪声叠出环带细缝。
    {
        accum += alpha * textureLod(noiseTexture, vec2(position, 0.0), 0.0).z; // 读噪声的第三通道。
        position = position * octScale; // 抬高频率。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift - 0.1; // 加上层间偏移并减去阈值。
}

// Eclipse 的瑞利相函数：Elek 2009 的线性近似，已经除以四派做能量守恒。
float ogxEclipseSkyRayleighPhase(float cosTheta)
{
    return cosTheta * (0.1 * OGX_INV_PI) + 0.28 * OGX_INV_PI; // 参考实现把两个常数都乘 1/pi。
}

// Eclipse 的米氏相函数：用 g 的平方与 1.5 次幂，和 Henyey-Greenstein 不是同一公式。
float ogxEclipseSkyMiePhase(float cosTheta, float g)
{
    float gg = g * g; // 先算 g 的平方。
    return (gg * -0.25 + 0.25) * OGX_INV_PI * pow(-(2.0 * g) * cosTheta + (gg + 1.0), -1.5); // 参考实现的负指数。
}

// Eclipse 的相函数对：第一分量瑞利，第二分量米氏。
vec2 ogxEclipseSkyPhase(float cosTheta, float g)
{
    return vec2(ogxEclipseSkyRayleighPhase(cosTheta), ogxEclipseSkyMiePhase(cosTheta, g));
}

// Eclipse 的大气密度：瑞利与米氏共用一条指数，臭氧用两段指数围出峰值。
// `planetRadius` 与 `scaleHeights` 由调用方给出，默认是 6731 公里与 8/1.2 公里。
vec3 ogxEclipseSkyDensity(float centerDistance, float planetRadius, vec2 scaleHeights)
{
    vec2 inverseScaleHeights = 1.0 / scaleHeights; // 标高倒数。
    vec2 rayleighMie = exp(centerDistance * -inverseScaleHeights + planetRadius * inverseScaleHeights); // 瑞利与米氏。
    float ozone = exp(-max(0.0, (35000.0 - centerDistance) - planetRadius) * (1.0 / 5000.0)) // 臭氧上边界。
                * exp(-max(0.0, (centerDistance - 35000.0) - planetRadius) * (1.0 / 15000.0)); // 臭氧下边界。
    return vec3(rayleighMie, ozone); // 三个分量对应三种介质。
}

// Eclipse 的大气质量：沿视线固定步数积分密度，步长由射线长度决定。
vec3 ogxEclipseSkyAirmass(vec3 position, vec3 direction, float rayLength, float steps,
    float planetRadius, vec2 scaleHeights)
{
    float stepSize = rayLength * (1.0 / steps); // 每步长度。
    vec3 increment = direction * stepSize; // 每步位移。
    position += increment * 0.5; // 从半步处开始，避开端点。
    vec3 airmass = vec3(0.0); // 累积密度。
    for (int i = 0; i < steps; ++i, position += increment) // 固定步数。
    {
        airmass += ogxEclipseSkyDensity(length(position), planetRadius, scaleHeights); // 逐点累积密度。
    }
    return airmass * stepSize; // 乘步长得到光学路径。
}

// Eclipse 的大气质量射线版：先求与大气顶层的交点，再调用固定步数版。
vec3 ogxEclipseSkyAirmassRay(vec3 position, vec3 direction, float steps,
    float planetRadius, vec2 scaleHeights, float atmosphereRadius)
{
    float rayLength = dot(position, direction); // 投影长度。
    rayLength = rayLength * rayLength + atmosphereRadius * atmosphereRadius - dot(position, position); // 判别式。
    if (rayLength < 0.0) return vec3(0.0); // 射线不碰大气。
    rayLength = sqrt(rayLength) - dot(position, direction); // 到交点的距离。
    return ogxEclipseSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 交给固定步数版。
}

// Eclipse 的光学厚度：三种介质的消光系数乘各自的大气质量。
vec3 ogxEclipseSkyOpticalDepth(vec3 position, vec3 direction, float rayLength, float steps,
    float planetRadius, vec2 scaleHeights,
    vec3 coefficientRayleigh, vec3 coefficientMie, vec3 coefficientOzone)
{
    vec3 airmass = ogxEclipseSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 三种介质的路径。
    return coefficientRayleigh * airmass.x + coefficientMie * airmass.y + coefficientOzone * airmass.z; // 按介质加权。
}

// Eclipse 的透过率：把光学厚度换成以二为底的指数，和参考实现的 `exp(-od/ln2)` 等价。
vec3 ogxEclipseSkyTransmittance(vec3 position, vec3 direction, float rayLength, float steps,
    float planetRadius, vec2 scaleHeights,
    vec3 coefficientRayleigh, vec3 coefficientMie, vec3 coefficientOzone)
{
    vec3 depth = ogxEclipseSkyOpticalDepth(position, direction, rayLength, steps, planetRadius, scaleHeights,
        coefficientRayleigh, coefficientMie, coefficientOzone); // 先算光学厚度。
    return exp2(-depth); // exp(-depth/ln2) 与 exp2(-depth) 等价。
}

// Eclipse 星场：用星盒三角投影得到星点，再按亮度与数量做指数强化。
float ogxEclipseStars(vec3 viewPos, float brightness, float amount, out vec3 starColor)
{
    float stars = max(1.0 - ogxStarBox(viewPos, starColor), 0.0); // 星盒投影。
    return 75.0 * brightness * exp(stars * -20.0 * (1.0 / max(amount, 1e-6))); // 参考实现的亮度曲线。
}

#endif

/*
生成文件：大气查表模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库预计算大气查表模块：坐标映射、透过率、组合散射、辐照度与天空辐射。
调用位置：任何使用论文式预计算大气贴图的程序；Minecraft 光影由
    `/omni-gfx/atmosphere_model.glsl` 引入，`rendering/sky/atmosphere_model.glsl` 只填常数与贴图。
可复制示例：`OgxAtmosphereModel model = ...;` 由调用方填好行星常数与贴图尺寸，再调用
    `ogxAtmoSkyRadiance` 查某个方向的天空辐射。
设计原因与取舍：
    本模块不读加载器输入、选项宏与中间画面；大气常数由调用方填进结构体，预计算贴图由采样器参数传入。
    读表而不是实时积分，代价与分辨率无关；所有函数只做几何与查表，公式与 iterationT 逐行一致。
    结构体字段沿用旧适配层的下划线命名：宿主有几十处逐字段赋值，改名会把风险推到调用点。
*/
#ifndef OGX_ATMOSPHERE_MODEL_INCLUDED
#define OGX_ATMOSPHERE_MODEL_INCLUDED

// 球面几何与相位函数来自大气模块，亮度与夹紧来自数学模块，色适应矩阵的按行乘法来自颜色模块。



// 一次查表需要的全部常数与贴图尺寸；数值由宿主按原程序填写，本模块不保存默认值。
struct OgxAtmosphereModel
{
    float bottom_radius; // 行星底半径，越过它就算被地面挡住。
    float top_radius; // 大气层顶半径，视线到这里离开大气。
    float sun_angular_radius; // 太阳视半径，日落时用它对太阳方向做渐隐。
    float mie_phase_g; // 米氏相位的前向集中程度。
    float mu_s_min; // 太阳高度角的查表下限。
    vec3 solar_irradiance; // 太阳辐照度，决定大气散射的基准亮度。
    vec3 rayleigh_scattering; // 瑞利散射系数，蓝光最强，天空因此偏蓝。
    vec3 mie_scattering; // 米氏散射系数，气溶胶造成太阳附近的白晕。
    vec3 absorption_extinction; // 臭氧吸收系数，只影响透过率，不发光。
    float density_rayleigh; // 瑞利密度剖面的指数系数。
    float density_mie; // 米氏密度剖面的指数系数。
    float absorption_width; // 臭氧三角剖面的转折高度。
    vec4 density_absorption; // 臭氧剖面分段线性系数。
    float transmittance_width; // 透过率子图宽度，单位像素。
    float transmittance_height; // 透过率子图高度。
    float scattering_r; // 散射子图的半径方向尺寸。
    float scattering_mu; // 散射子图的高度角方向尺寸。
    float scattering_mu_s; // 散射子图的太阳高度角方向尺寸。
    float scattering_nu; // 散射子图的视线与太阳夹角方向尺寸。
    float combined_width; // 拼合后大图宽度。
    float combined_height; // 拼合后大图高度。
    float combined_depth; // 拼合后大图深度。
    float irradiance_width; // 辐照度子图宽度。
    float irradiance_height; // 辐照度子图高度。
};

// 色适应矩阵：把物理辐照度的三刺激值转到本项目使用的原色空间；与 iterationT 一致。
const mat3 OGX_ATMO_LMS = mat3(1.6858, -0.4624, -0.0069, -0.0374, 1.0598, -0.0742, -0.0283, -0.1119, 1.0491);

// 把半径夹进大气层范围内，越界时按最近的边界算。
float ogxAtmoClampRadius(OgxAtmosphereModel m, float r)
{
    return ogxClampRadius(r, m.bottom_radius, m.top_radius); // 边界由调用方提供。
}

// 视线到大气层顶的距离，解视线与顶球面的方程取远根。
float ogxAtmoDistanceToTop(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereDistanceToTop(r, mu, m.top_radius); // 球面几何在通用库，层顶半径在这里传入。
}

// 视线到大气层底的距离，解视线与底球面的方程取近根。
float ogxAtmoDistanceToBottom(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereDistanceToBottom(r, mu, m.bottom_radius); // 层底半径在这里传入。
}

// 判断一条朝下的视线是否真的打到地面球。
bool ogxAtmoRayIntersectsGround(OgxAtmosphereModel m, float r, float mu)
{
    return ogxSphereRayIntersectsGround(r, mu, m.bottom_radius); // 与地面球的相交判断在通用库。
}

// 瑞利与米氏密度剖面：以二为底的指数衰减，系数已经积分好。
float ogxAtmoDensityRayleighMie(float expScale, float altitude)
{
    return ogxExponentialDensity(expScale, altitude); // 指数密度剖面在通用库。
}

// 臭氧密度剖面：在转折高度以下是一段斜线，以上是另一段斜线。
float ogxAtmoDensityAbsorption(float width, vec4 profile, float altitude)
{
    return ogxAbsorptionDensity(width, profile, altitude); // 两段线性剖面在通用库。
}

// 把零到一的比例映射到贴图坐标的像素中心，避免采到子图交界。
float ogxAtmoTextureCoord(float x, float textureSize)
{
    return ogxTexelCenterCoord(x, textureSize); // 像素中心换算在通用库。
}

// 把子图内部的比例映射到拼合大图上的坐标，子图在大图里也内缩半像素。
float ogxAtmoCombinedTextureCoord(float x, float originalTextureSize, float combinedTextureSize)
{
    return ogxSubTextureCoord(x, originalTextureSize, combinedTextureSize); // 拼图坐标换算在通用库。
}

// 把半径与几个角度换成散射三维贴图的四维坐标：前三维是坐标，第四维留给上层插值。
vec4 ogxAtmoScatteringUvwz(OgxAtmosphereModel m, float r, float mu, float mu_s, float nu, bool rayRMuIntersectsGround)
{
    float H = sqrt(m.top_radius * m.top_radius - m.bottom_radius * m.bottom_radius); // 大气层顶相对地面的水平距离。
    float rho = ogxSafeSqrt(r * r - m.bottom_radius * m.bottom_radius); // 相机到地心的水平投影。
    float u_r = ogxAtmoCombinedTextureCoord(rho / H, m.scattering_r, m.combined_depth); // 半径方向落到深度坐标。
    float r_mu = r * mu; // 半径乘高度角余弦，判别式里反复用到。
    float discriminant = r_mu * r_mu - r * r + m.bottom_radius * m.bottom_radius; // 是否打到地面的判别式。
    float u_mu; // 高度角方向的坐标，下面分两种情形算。
    if (rayRMuIntersectsGround) // 打到地面：用近根，坐标落在下半段。
    {
        float d = -r_mu - ogxSafeSqrt(discriminant); // 到地面的距离。
        float d_min = r - m.bottom_radius; // 距离下限。
        float d_max = rho; // 距离上限。
        u_mu = 0.5 - 0.5 * ogxAtmoTextureCoord(float(d_max != d_min) * (d - d_min) / (d_max - d_min), m.scattering_mu / 2.0); // 映射到下半张子图。
    }
    else // 没打到地面：用远根，坐标落在上半段。
    {
        float d = -r_mu + ogxSafeSqrt(discriminant + H * H); // 到层顶的距离。
        float d_min = m.top_radius - r; // 距离下限。
        float d_max = rho + H; // 距离上限。
        u_mu = 0.5 + 0.5 * ogxAtmoTextureCoord((d - d_min) / (d_max - d_min), m.scattering_mu / 2.0); // 映射到上半张子图。
    }
    float d = ogxAtmoDistanceToTop(m, m.bottom_radius, mu_s); // 太阳高度角对应的层顶距离。
    float d_min = m.top_radius - m.bottom_radius; // 距离下限。
    float d_max = H; // 距离上限。
    float a = (d - d_min) / (d_max - d_min); // 太阳高度角的归一化距离。
    float D = ogxAtmoDistanceToTop(m, m.bottom_radius, m.mu_s_min); // 查表下限对应的距离。
    float A = (D - d_min) / (d_max - d_min); // 下限的归一化距离。
    float u_mu_s = ogxAtmoTextureCoord(max(1.0 - a / A, 0.0) / (1.0 + a), m.scattering_mu_s); // 非线性映射到太阳高度角坐标。
    float u_nu = (nu + 1.0) / 2.0; // 视线与太阳夹角从负一到一转成零到一。
    return vec4(u_nu, u_mu_s, u_mu, u_r); // 返回四维坐标，供上层做夹角方向插值。
}

// 把半径与高度角换成透过率子图坐标。
vec2 ogxAtmoTransmittanceUv(OgxAtmosphereModel m, float r, float mu)
{
    float H = sqrt(m.top_radius * m.top_radius - m.bottom_radius * m.bottom_radius); // 大气层顶相对地面的水平距离。
    float rho = ogxSafeSqrt(r * r - m.bottom_radius * m.bottom_radius); // 相机到地心的水平投影。
    float d = ogxAtmoDistanceToTop(m, r, mu); // 到层顶的距离。
    float d_min = m.top_radius - r; // 距离下限。
    float d_max = rho + H; // 距离上限。
    float x_mu = (d - d_min) / (d_max - d_min); // 高度角方向的归一化位置。
    float x_r = rho / H; // 半径方向的归一化位置。
    return vec2(ogxAtmoCombinedTextureCoord(x_mu, m.transmittance_width, m.combined_width), // 横坐标是高度角方向。
                  ogxAtmoCombinedTextureCoord(x_r, m.transmittance_height, m.combined_height)); // 纵坐标是半径方向。
}

// 查到层顶的透过率：透过率存在拼合大图的同一深度层上。
vec3 ogxAtmoTransmittanceToTop(OgxAtmosphereModel m, sampler3D lut, float r, float mu)
{
    vec2 uv = ogxAtmoTransmittanceUv(m, r, mu); // 先算子图坐标。
    float depthCoord = 32.5 / 33.0; // 透过率固定存在靠后的深度层。
    vec3 lutCoord = vec3(uv.x, uv.y, depthCoord); // 三维坐标先算好，避免采样调用里嵌构造。
    vec4 sample = textureLod(lut, lutCoord, 0.0); // 三维纹理采样返回四通道。
    return sample.rgb; // 只取颜色三通道。
}

// 两点之间的透过率：由两端到层顶的透过率相除得到，地面相交时用镜像方向。
vec3 ogxAtmoTransmittance(OgxAtmosphereModel m, sampler3D lut, float r, float mu, float d, bool rayRMuIntersectsGround)
{
    float r_d = ogxAtmoClampRadius(m, sqrt(d * d + 2.0 * r * mu * d + r * r)); // 终点相对地心的半径。
    float mu_d = clamp((r * mu + d) / r_d, -1.0, 1.0); // 终点处的高度角余弦。
    if (rayRMuIntersectsGround) // 打到地面时用负高度角镜像。
    {
        return min(ogxAtmoTransmittanceToTop(m, lut, r_d, -mu_d) / ogxAtmoTransmittanceToTop(m, lut, r, -mu), vec3(1.0)); // 两端相除并封顶到一。
    }
    return min(ogxAtmoTransmittanceToTop(m, lut, r, mu) / ogxAtmoTransmittanceToTop(m, lut, r_d, mu_d), vec3(1.0)); // 没打到地面直接用正高度角。
}

// 从某点朝太阳方向到层顶的透过率，太阳贴地时按太阳视半径留一段过渡。
vec3 ogxAtmoTransmittanceToSun(OgxAtmosphereModel m, sampler3D lut, float r, float mu_s)
{
    float sin_theta_h = m.bottom_radius / r; // 地平线方向的俯角正弦。
    float cos_theta_h = -sqrt(max(1.0 - sin_theta_h * sin_theta_h, 0.0)); // 地平线方向的余弦。
    return ogxAtmoTransmittanceToTop(m, lut, r, mu_s) * // 基础透过率。
        smoothstep(-sin_theta_h * m.sun_angular_radius, // 过渡带下沿。
                   sin_theta_h * m.sun_angular_radius, // 过渡带上沿。
                   mu_s - cos_theta_h); // 过渡带半宽由太阳视半径决定。
}

// 从拼合散射数据反推单次米氏散射：按通道比例还原。
vec3 ogxAtmoExtrapolatedMie(OgxAtmosphereModel m, vec4 scattering)
{
    if (scattering.r <= 0.0) return vec3(0.0); // 红通道为零说明没有数据。
    return scattering.rgb * scattering.a / scattering.r * // 按红通道比例缩放。
        (m.rayleigh_scattering.r / m.mie_scattering.r) * // 瑞利与米氏红通道比例。
        (m.mie_scattering / m.rayleigh_scattering); // 逐通道还原米氏散射。
}

// 查组合散射：先在夹角方向插值两片，再拆出单次米氏散射。
vec3 ogxAtmoCombinedScattering(OgxAtmosphereModel m, sampler3D lut, float r, float mu, float mu_s, float nu,
    bool rayRMuIntersectsGround, out vec3 singleMieScattering)
{
    vec4 uvwz = ogxAtmoScatteringUvwz(m, r, mu, mu_s, nu, rayRMuIntersectsGround); // 四维查表坐标。
    float tex_coord_x = uvwz.x * (m.scattering_nu - 1.0); // 夹角方向落在第几片。
    float tex_x = floor(tex_coord_x); // 前一片的编号。
    float frac = tex_coord_x - tex_x; // 两片之间的插值比例。
    vec3 uvw0 = vec3((tex_x + uvwz.y) / m.scattering_nu, uvwz.z, uvwz.w); // 前一片的三维坐标。
    vec3 uvw1 = vec3((tex_x + 1.0 + uvwz.y) / m.scattering_nu, uvwz.z, uvwz.w); // 后一片的三维坐标。
    vec4 combined = textureLod(lut, uvw0, 0.0) * (1.0 - frac) + textureLod(lut, uvw1, 0.0) * frac; // 两片之间线性插值。
    singleMieScattering = ogxAtmoExtrapolatedMie(m, combined); // 第四通道还原单次米氏散射。
    return combined.rgb; // 前三通道是组合散射。
}

// 查辐照度：给出某个高度朝上接到的太阳与环境辐照度。
vec3 ogxAtmoIrradiance(OgxAtmosphereModel m, sampler3D lut, float r, float mu_s)
{
    float x_r = (r - m.bottom_radius) / (m.top_radius - m.bottom_radius); // 半径方向归一化。
    float x_mu_s = mu_s * 0.5 + 0.5; // 太阳高度角从负一到一转成零到一。
    vec2 uv = vec2(ogxAtmoCombinedTextureCoord(x_mu_s, m.irradiance_width, m.combined_width), // 横坐标是高度角方向。
                       ogxAtmoCombinedTextureCoord(x_r, m.irradiance_height, m.combined_height) + m.transmittance_height / m.combined_height); // 纵坐标要跳过透过率子图。
    float depthCoord = 32.5 / 33.0; // 辐照度与透过率在同一深度层的不同子图。
    vec3 lutCoord = vec3(uv.x, uv.y, depthCoord); // 三维坐标先算好，避免采样调用里嵌构造。
    vec4 sample = textureLod(lut, lutCoord, 0.0); // 三维纹理采样返回四通道。
    return sample.rgb; // 只取颜色三通道。
}

// 算某点的太阳、月亮与天空辐照度：太阳和月亮各出一份直射与一份环境。
vec3 ogxAtmoSunSkyIrradiance(OgxAtmosphereModel m, sampler3D lut, vec3 point, vec3 sunDirection, vec3 moonDirection,
    float nightBrightness, vec3 sunTint, out vec3 moonIrradiance,
    out vec3 sunSkyIrradiance, out vec3 moonSkyIrradiance)
{
    float r = length(point); // 点到地心的距离。
    float sun_mu_s = dot(point, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float moon_mu_s = dot(point, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    sunSkyIrradiance = ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], ogxAtmoIrradiance(m, lut, r, sun_mu_s)); // 太阳侧的环境辐照度，乘色适应矩阵。
    moonSkyIrradiance = ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], ogxAtmoIrradiance(m, lut, r, moon_mu_s) * nightBrightness); // 月亮侧环境辐照度，按夜间亮度缩放。
    vec3 sunIrradiance = m.solar_irradiance; // 太阳直射从标准辐照度出发。
    moonIrradiance = ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], sunIrradiance * ogxAtmoTransmittanceToSun(m, lut, r, moon_mu_s) * nightBrightness); // 月亮直射等于太阳辐照度乘月光透过率，再按夜间亮度缩放。
    sunIrradiance *= ogxAtmoTransmittanceToSun(m, lut, r, sun_mu_s); // 太阳直射乘它自己的透过率。
    return ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], sunIrradiance) * sunTint; // 只染太阳直射：月亮直射有独立的色温，若在这里染色会把月亮一起带偏。
}

// 算某个视线方向的天空辐射亮度：日月散射、可选的地面反弹，再乘天气修正。
vec3 ogxAtmoSkyRadiance(OgxAtmosphereModel m, sampler3D lut, vec3 camera, vec3 viewRay, vec3 sunDirection,
    vec3 moonDirection, bool horizon, vec3 rayleighTint, vec3 mieTint,
    float nightBrightness, float wetness, float skyBrightness, bool groundBounce,
    out vec3 transmittance, out bool rayRMuIntersectsGround)
{
    float r = length(camera); // 相机到地心的距离。
    float rmu = dot(camera, viewRay); // 相机位置与视线的点积。
    float distance_to_top = -rmu - sqrt(rmu * rmu - r * r + m.top_radius * m.top_radius); // 相机到层顶的负距离，正数表示相机在上方。
    if (distance_to_top > 0.0) // 相机在大气内部时把起点推到层顶。
    {
        camera = camera + viewRay * distance_to_top; // 沿视线外推到层顶。
        r = m.top_radius; // 起点半径等于层顶。
        rmu += distance_to_top; // 同步更新点积。
    }
    else if (r > m.top_radius) // 相机在层顶之外时没有大气。
    {
        transmittance = vec3(1.0); // 透过率为一。
        return vec3(0.0); // 没有散射。
    }
    float mu = rmu / r; // 起点的高度角余弦。
    float sun_mu_s = dot(camera, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float sun_nu = dot(viewRay, sunDirection); // 视线与太阳夹角余弦。
    float moon_mu_s = dot(camera, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    float moon_nu = dot(viewRay, moonDirection); // 视线与月亮夹角余弦。
    rayRMuIntersectsGround = ogxAtmoRayIntersectsGround(m, r, mu); // 视线是否打到地面。
    transmittance = rayRMuIntersectsGround ? vec3(0.0) : ogxAtmoTransmittanceToTop(m, lut, r, mu); // 打到地面时透过率为零。
    vec3 sunSingleMieScattering; // 太阳侧的单次米氏散射。
    vec3 moonSingleMieScattering; // 月亮侧的单次米氏散射。
    horizon = horizon && rayRMuIntersectsGround; // 只有打到地面才考虑地平线处理。
    vec3 sunScattering = ogxAtmoCombinedScattering(m, lut, r, mu, sun_mu_s, sun_nu, horizon, sunSingleMieScattering); // 查太阳侧组合散射。
    vec3 moonScattering = ogxAtmoCombinedScattering(m, lut, r, mu, moon_mu_s, moon_nu, horizon, moonSingleMieScattering); // 查月亮侧组合散射。
    vec3 groundDiffuse = vec3(0.0); // 地面反弹的散射。
    if (groundBounce && horizon) // 只有开启地平线且视线打到地面才算。
    {
        vec3 planetSurface = camera + viewRay * ogxAtmoDistanceToBottom(m, r, mu); // 视线与地面的交点。
        float planet_r = length(planetSurface); // 交点到地心的距离。
        float planet_sun_mu_s = dot(planetSurface, sunDirection) / planet_r; // 交点处的太阳高度角余弦。
        float planet_moon_mu_s = dot(planetSurface, moonDirection) / planet_r; // 交点处的月亮高度角余弦。
        vec3 skyIrradiance = ogxAtmoIrradiance(m, lut, planet_r, planet_sun_mu_s); // 交点处的太阳侧环境辐照度。
        skyIrradiance += ogxAtmoIrradiance(m, lut, planet_r, planet_moon_mu_s) * nightBrightness; // 加上月亮侧环境辐照度。
        vec3 sunIrradiance = m.solar_irradiance * ogxAtmoTransmittanceToSun(m, lut, planet_r, planet_sun_mu_s); // 交点处的太阳直射辐照度。
        float d = distance(camera, planetSurface); // 相机到交点的距离。
        vec3 surfaceTransmittance = ogxAtmoTransmittance(m, lut, r, mu, d, rayRMuIntersectsGround); // 这段距离的透过率。
        groundDiffuse = mix(skyIrradiance * 0.1, sunIrradiance * 0.008, wetness * 0.6) * surfaceTransmittance; // 地面反弹按干湿在环境与直射之间插值。
    }
    vec3 rayleigh = (sunScattering * ogxRayleighPhase(sun_nu) // 太阳侧瑞利散射乘瑞利相位。
                     + moonScattering * ogxRayleighPhase(moon_nu) * nightBrightness) // 月亮侧同理并按夜间亮度缩放。
                     * rayleighTint; // 再按散射系数逐通道缩放瑞利散射，默认全一不改画面。
    vec3 mie = (sunSingleMieScattering * ogxMiePhase(m.mie_phase_g, sun_nu) // 太阳侧米氏散射乘米氏相位。
                + moonSingleMieScattering * ogxMiePhase(m.mie_phase_g, moon_nu) * nightBrightness) // 月亮侧同理。
                * mieTint; // 再按散射系数逐通道缩放米氏散射，默认全一不改画面。
    rayleigh = mix(rayleigh, vec3(ogxLuminance(rayleigh)) * m.solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色并按太阳谱重新染色。
    return ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], (rayleigh + mie + groundDiffuse) * (1.0 - wetness * 0.4)) * skyBrightness; // 合成后按雨天压暗、转色适应空间，再乘天空亮度。
}

// 算相机到某个世界点之间的天空辐射亮度，体积云与平面云算空气透视时用。
vec3 ogxAtmoSkyRadianceToPoint(OgxAtmosphereModel m, sampler3D lut, vec3 camera, vec3 point, vec3 sunDirection,
    vec3 moonDirection, bool localLighting, vec3 rayleighTint, vec3 mieTint,
    float nightBrightness, float wetness, float skyBrightness, out vec3 transmittance)
{
    vec3 viewRay = normalize(point - camera); // 从相机指向目标点的方向。
    float r = length(camera); // 相机到地心的距离。
    float rmu = dot(camera, viewRay); // 相机位置与视线的点积。
    float distance_to_top = -rmu - sqrt(rmu * rmu - r * r + m.top_radius * m.top_radius); // 相机到层顶的负距离。
    if (distance_to_top > 0.0) // 相机在大气内部时把起点推到层顶。
    {
        camera = camera + viewRay * distance_to_top; // 沿视线外推到层顶。
        r = m.top_radius; // 起点半径等于层顶。
        rmu += distance_to_top; // 同步更新点积。
    }
    float mu = rmu / r; // 起点的高度角余弦。
    float sun_mu_s = dot(camera, sunDirection) / r; // 太阳方向相对当地向上的余弦。
    float sun_nu = dot(viewRay, sunDirection); // 视线与太阳夹角余弦。
    float moon_mu_s = dot(camera, moonDirection) / r; // 月亮方向相对当地向上的余弦。
    float moon_nu = dot(viewRay, moonDirection); // 视线与月亮夹角余弦。
    float d = length(point - camera); // 起点到目标点的距离。
    bool rayRMuIntersectsGround = localLighting ? ogxAtmoRayIntersectsGround(m, r, mu) : false; // 云局部光照开启时才考虑地面相交。
    transmittance = ogxAtmoTransmittance(m, lut, r, mu, d, rayRMuIntersectsGround); // 起点到目标点的透过率。
    vec3 sunSingleMieScattering; // 太阳侧单次米氏散射。
    vec3 sunScattering = ogxAtmoCombinedScattering(m, lut, r, mu, sun_mu_s, sun_nu, rayRMuIntersectsGround, sunSingleMieScattering); // 起点处太阳侧组合散射。
    vec3 moonSingleMieScattering; // 月亮侧单次米氏散射。
    vec3 moonScattering = ogxAtmoCombinedScattering(m, lut, r, mu, moon_mu_s, moon_nu, rayRMuIntersectsGround, moonSingleMieScattering); // 起点处月亮侧组合散射。
    float r_p = ogxAtmoClampRadius(m, sqrt(d * d + 2.0 * r * mu * d + r * r)); // 目标点相对地心的半径。
    float mu_p = (r * mu + d) / r_p; // 目标点处的高度角余弦。
    float sun_mu_s_p = (r * sun_mu_s + d * sun_nu) / r_p; // 目标点处的太阳高度角余弦。
    float moon_mu_s_p = (r * moon_mu_s + d * moon_nu) / r_p; // 目标点处的月亮高度角余弦。
    vec3 sunSingleMieScatteringP; // 目标点处太阳侧单次米氏散射。
    vec3 sunScatteringP = ogxAtmoCombinedScattering(m, lut, r_p, mu_p, sun_mu_s_p, sun_nu, rayRMuIntersectsGround, sunSingleMieScatteringP); // 目标点处太阳侧组合散射。
    vec3 moonSingleMieScatteringP; // 目标点处月亮侧单次米氏散射。
    vec3 moonScatteringP = ogxAtmoCombinedScattering(m, lut, r_p, mu_p, moon_mu_s_p, moon_nu, rayRMuIntersectsGround, moonSingleMieScatteringP); // 目标点处月亮侧组合散射。
    sunScattering = sunScattering - transmittance * sunScatteringP; // 两点之差的散射是这段空气的贡献。
    sunSingleMieScattering = sunSingleMieScattering - transmittance * sunSingleMieScatteringP; // 米氏散射同样相减。
    moonScattering = moonScattering - transmittance * moonScatteringP; // 月亮侧同理。
    moonSingleMieScattering = moonSingleMieScattering - transmittance * moonSingleMieScatteringP; // 月亮侧米氏同样相减。
    sunSingleMieScattering = sunSingleMieScattering * smoothstep(0.0, 0.01, sun_mu_s); // 太阳很贴地时淡出米氏散射，避免出现断带。
    moonSingleMieScattering = moonSingleMieScattering * smoothstep(0.0, 0.01, moon_mu_s); // 月亮同样处理。
    vec3 rayleigh = (sunScattering * ogxRayleighPhase(sun_nu) // 太阳侧瑞利散射。
                     + moonScattering * ogxRayleighPhase(moon_nu) * nightBrightness) // 月亮侧瑞利散射。
                     * rayleighTint; // 按散射系数逐通道缩放，默认全一不改画面。
    vec3 mie = (sunSingleMieScattering * ogxMiePhase(m.mie_phase_g, sun_nu) // 太阳侧米氏散射。
                + moonSingleMieScattering * ogxMiePhase(m.mie_phase_g, moon_nu) * nightBrightness) // 月亮侧米氏散射。
                * mieTint; // 按散射系数逐通道缩放，默认全一不改画面。
    rayleigh = mix(rayleigh, vec3(ogxLuminance(rayleigh)) * m.solar_irradiance, wetness * 0.5); // 雨天把瑞利散射去色重染。
    return ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], (rayleigh + mie) * (1.0 - wetness * 0.4)) * skyBrightness; // 合成后按雨天压暗并转色适应空间，再乘天空亮度。
}

// 简化的单次散射：沿阳光方向取四段估光学厚度，算出这段空气加到视线上的散射色。
// 输入是相机、视线方向、散射距离、受光距离与光源方向；返回叠加的散射颜色。
// 为什么用球面求交取段长：每段沿阳光走多远由大气层厚度决定，固定步长会在高处取样过密、低处过疏。
vec3 ogxAtmoSimpleScattering(OgxAtmosphereModel m, vec3 camera, vec3 worldDir, float dist, float shadowDist, vec3 lightVector)
{
    float ds = ogxRaySphereIntersection(camera, lightVector, m.top_radius).y * 0.25; // 沿阳光到大气层顶的距离，取四分之一为每段长度。
    vec3 opticalLength = ds * lightVector; // 每段的光程矢量。
    camera += 0.5 * opticalLength; // 相机先前移到第一段中点。
    vec3 opticalDepth = vec3(0.0); // 累加的光学厚度，三通道分别是瑞利、米氏与吸收。
    for (int i = 0; i < 4; i++, camera += opticalLength) // 四段累加。
    {
        float altitude = length(camera) - m.bottom_radius; // 该段所在高度。
        opticalDepth += vec3(ogxExponentialDensity(m.density_rayleigh, altitude), // 瑞利密度。
                               ogxExponentialDensity(m.density_mie, altitude), // 米氏密度。
                               ogxAbsorptionDensity(m.absorption_width, m.density_absorption, altitude)); // 臭氧密度。
    }
    opticalDepth = opticalDepth * ds + dist; // 乘段长并加上视线本身的距离。
    vec3 attenuation = exp2(-opticalDepth.x * m.rayleigh_scattering // 瑞利消光。
                              - opticalDepth.y * m.mie_scattering // 米氏消光。
                              - opticalDepth.z * m.absorption_extinction); // 臭氧吸收。
    float nu = dot(worldDir, lightVector); // 视线与阳光的夹角。
    vec3 scattering = ogxRayleighPhase(nu) * m.rayleigh_scattering * (dist * 0.25 + shadowDist * 0.75) // 瑞利散射，四分之一取距离、四分之三取受光距离。
                      + ogxMiePhase(0.6, nu) * m.mie_scattering * shadowDist; // 米氏散射只算受光的部分。
    return ogxApplyRows(OGX_ATMO_LMS[0], OGX_ATMO_LMS[1], OGX_ATMO_LMS[2], scattering * m.solar_irradiance * attenuation); // 乘太阳辐照度、透过率与色适应矩阵。
}

#endif
/*
生成文件：云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库云模块：球壳求交、程序化密度、朝阳光照与沿视线步进。
调用位置：天空与水面反射里的云；Minecraft 光影由 `/omni-gfx/cloud.glsl` 引入。
可复制示例：
    OgxCloudLayer l = ogxCloudLayerDefault(); // 取默认云层。
    vec4 c = ogxCloudMarch(l, camKm, viewDir, sunDir, sunColor, skyColor, j, 24); // 步进一层云。
    float k = ogxCloudShadow(l, groundKm, sunDir); // 取地面云影。
设计原因与取舍：
    形状来自旧 `shaders/gfx/cloud_volume.glsl` 的球面云坐标、云量重映射与光照步进，
    把纹理采样换成程序化值噪声，因此不需要额外贴图也能独立出图。
    只用一层云，但加入低频云量图、域扭曲和随高度剪切，专门消除平面云层的重复条纹。
    密度与光照步数全部由调用方传入，库不读取天气、选项或宿主状态。
*/
#ifndef OGX_CLOUD_INCLUDED
#define OGX_CLOUD_INCLUDED

// 噪声提供云团与细节，数学提供球面求交与相函数。


// 一层体积云的参数；不同云层换字段即可复用同一套步进。
struct OgxCloudLayer
{
    float bottom; // 云底高度，公里。
    float top; // 云顶高度，公里。
    float planetRadius; // 行星半径，公里，用来把平面云层弯成球壳。
    float coverage; // 云量，零到一。
    float density; // 密度倍率。
    float detail; // 边缘侵蚀强度，零到一。
    vec3 wind; // 水平风向与速度，公里。
};

// 默认云层：一百二十米到二百四十米，地球半径，云量零点四五。
OgxCloudLayer ogxCloudLayerDefault()
{
    OgxCloudLayer layer; // 先声明再填写字段。
    layer.bottom = 0.75; // 云底七百五十米，从岛上仰望时云在头顶，不压住地平线。
    layer.top = 2.20; // 云顶两千二百米，厚一千四百多米，积云有足够的竖向结构。
    layer.planetRadius = 6360.0; // 与大气模块使用同一颗行星。
    layer.coverage = 0.30; // 中等云量，保留清晰的蓝天缝隙。
    layer.density = 1.5; // 密度倍率：太厚会让整层云变成灰色的天花板。
    layer.detail = 1.0; // 默认开启边缘侵蚀。
    layer.wind = vec3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    return layer; // 返回可直接修改的默认值。
}

// 降雨对云量的加成：雨与雷暴各叠一成，超过一的部分截掉。
// 为什么单独一个函数：降雨强度与雷暴强度来自天气，云层本身不知道下雨，加成必须在边界一次算完。
float ogxCloudRainDensity(float density, float rain, float thunder)
{
    return min(density + rain * 0.1 + thunder * 0.1, 1.0);
}

// 云密度：低频云量图决定哪里长云，域扭曲与高度剪切打断重复。
float ogxCloudDensity(OgxCloudLayer layer, vec3 position, bool withDetail)
{
    float curvature = dot(position.xz, position.xz) / (2.0 * layer.planetRadius); // 球面相对切面的高度亏损。
    float altitude = position.y - curvature; // 修正后的真实高度。
    // 云底高度用低频噪声起伏几十米：云底因此不是一条笔直的水平线，远看更像真实的积云底。
    float baseWobble = (ogxFbm2(position.xz * 0.42 + layer.wind.xz, 2) - 0.5) * 0.16;
    float bottom = layer.bottom + baseWobble; // 本列的云底高度。
    float height = (altitude - bottom) / max(layer.top - bottom, 1e-4); // 层内归一化高度。
    if (height <= 0.0 || height >= 1.0) // 云层外没有密度。
    {
        return 0.0; // 直接跳过，省掉后面的噪声。
    }
    vec2 wind = layer.wind.xz; // 只取水平风。
    vec2 base = position.xz + wind; // 随风平移的平面坐标。
    // 域扭曲：一层次级噪声把值噪声的方格打散，云团边缘不再沿着坐标轴。
    // 只用两层目的是一次密度取样控制在十次噪声以内：云的代价主要在密度函数里。
    vec2 warp = vec2(ogxFbm2(base * 1.05 + vec2(3.7, 1.9), 2),
                         ogxFbm2(base * 1.05 + vec2(9.2, 5.4), 2)) - 0.5;
    vec2 plane = base + warp * 2.4; // 扭曲后的平面坐标。
    plane += vec2(height * 0.62, -height * 0.38); // 随高度剪切，云有斜向层次而不是竖直柱子。
    // 两个尺度定形状：六百米级的大团决定云块位置，一百八十米级的中团给圆顶。
    float large = ogxFbm2(plane * 1.55, 3); // 大团块。
    float medium = ogxFbm3(vec3(plane * 5.0, altitude * 5.0), 2); // 中团块；纵向用同一频率，否则会出现横向薄片。
    float shape = large * 0.55 + medium * 0.45; // 合在一起。
    shape = pow(ogxSaturate(shape), 0.85); // 略微推高亮的部位，圆顶更鼓。
    float coverageNoise = ogxValueNoise2(base * 0.085); // 几公里尺度的云量变化，一层就够。
    float threshold = mix(0.62, 0.40, ogxSaturate(layer.coverage)); // 云量越大，阈值越低。
    threshold -= (coverageNoise - 0.5) * 0.14; // 成片与空窗交替。
    float density = smoothstep(threshold, threshold + 0.05, shape); // 边缘过渡收窄，云块轮廓更清楚。
    // 竖向轮廓：底部收得快、顶部慢慢收，形成平底圆顶的积云形状。
    float vertical = smoothstep(0.0, 0.12, height) * (1.0 - smoothstep(0.55, 1.0, height) * 0.85);
    density *= vertical; // 竖向包络。
    if (withDetail && layer.detail > 0.0 && density > 0.002) // 只有确实有云时才叠细节。
    {
        // 高频侵蚀：三个方向同尺度，否则竖向格距过密，逆光时会出现一丝丝划痕。
        float erosion = ogxFbm3(vec3(plane * 14.0, altitude * 14.0) + vec3(wind * 6.0, 0.0), 1);
        density *= mix(1.0, smoothstep(0.18, 0.68, erosion), ogxSaturate(layer.detail) * 0.72); // 只在边缘削薄。
    }
    return ogxSaturate(density) * layer.density; // 乘以密度倍率后返回。
}

// 朝太阳方向在云里短步进，估计还有多少阳光能到当前点。
float ogxCloudLight(OgxCloudLayer layer, vec3 position, vec3 sunDirection, int steps)
{
    const int maxSteps = 6; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float opticalDepth = 0.0; // 沿阳光累积的云密度。
    float stepLength = 0.012; // 起始步长，公里。
    vec3 samplePosition = position; // 从当前点出发。
    for (int i = 0; i < maxSteps; i++) // 逐步朝太阳前进。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        samplePosition += sunDirection * stepLength; // 前进一段。
        opticalDepth += ogxCloudDensity(layer, samplePosition, false) * stepLength; // 累加路径上的云。
        stepLength *= 1.75; // 越远步长越大，覆盖更厚的云。
    }
    float direct = exp(-opticalDepth * 11.0); // 直接的比尔-朗伯透射率。
    // 多次散射：光子会在云滴之间反复弹射，真实的厚云背光面是灰色而不是黑色。
    // 用一个更慢衰减的指数近似这部分能量，系数偏小，只负责把暗部托起来。
    float multiple = exp(-opticalDepth * 2.2) * 0.34;
    return direct + multiple; // 两者相加，上限交给调用方压。
}

// 沿视线步进云层：返回云的普通颜色与覆盖率，供天空合成。
vec4 ogxCloudMarch(OgxCloudLayer layer, vec3 camera, vec3 viewDirection, vec3 sunDirection,
                     vec3 sunColor, vec3 skyColor, float jitter, int steps)
{
    vec3 origin = vec3(0.0, layer.planetRadius + max(camera.y, 0.0), 0.0); // 相机在行星正上方。
    vec2 bottomHit = ogxRaySphereIntersection(origin, viewDirection, layer.planetRadius + layer.bottom); // 与云底的交点。
    vec2 topHit = ogxRaySphereIntersection(origin, viewDirection, layer.planetRadius + layer.top); // 与云顶的交点。
    float startDistance = 0.0; // 步进起点。
    float endDistance = 0.0; // 步进终点。
    if (camera.y < layer.bottom) // 相机在云下：先碰到云底。
    {
        startDistance = bottomHit.y; // 云底远交点。
        endDistance = topHit.y; // 云顶远交点。
    }
    else if (camera.y > layer.top) // 相机在云上：先碰到云顶。
    {
        startDistance = topHit.x; // 云顶近交点。
        endDistance = bottomHit.x; // 云底近交点。
    }
    else // 相机在云层内部。
    {
        startDistance = 0.0; // 从相机开始。
        endDistance = topHit.y; // 到云顶为止。
    }
    if (endDistance <= startDistance || endDistance <= 0.0) // 没有穿过云层。
    {
        return vec4(0.0, 0.0, 0.0, 0.0); // 完全透明。
    }
    endDistance = min(endDistance, 2.8); // 远处云淡出：步长在掠射方向拉得很长，再远也只会被空气透视洗掉。
    const int maxSteps = 32; // 固定循环上限。
    int count = min(max(steps, 4), maxSteps); // 至少四步，最多三十二步。
    float stepLength = (endDistance - startDistance) / float(count); // 每步长度。
    float distanceAlongRay = startDistance + stepLength * ogxSaturate(jitter); // 抖动起点，减轻层状条纹。
    vec3 scattered = vec3(0.0); // 累积散射光。
    float transmittance = 1.0; // 还剩多少背景光能穿过。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    // 双瓣相函数：前向散射给银边，瑞利项托住侧光。前向峰值必须夹住，
    // 否则正对低阳的云会被推到几十倍亮度，泛光一开就成一片白斑。
    float phase = ogxMiePhase(0.62, nu) * 0.85 + ogxRayleighPhase(nu) * 0.30;
    phase = min(phase, 3.2);
    for (int i = 0; i < maxSteps; i++) // 逐步穿过云层。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        vec3 position = camera + viewDirection * distanceAlongRay; // 当前采样点。
        float density = ogxCloudDensity(layer, position, true); // 当前密度。
        if (density > 0.002) // 空区域跳过光照步进。
        {
            float light = min(ogxCloudLight(layer, position, sunDirection, 4), 1.20); // 朝太阳的透射率，厚云也保留多次散射。
            float height = ogxSaturate((position.y - layer.bottom) / max(layer.top - layer.bottom, 1e-4)); // 层内高度。
            // 粉末效应：正对阳光看薄云边缘时，能看到云滴把光散回来，边缘因此发亮。
            float powder = 1.0 - exp(-density * 7.0);
            vec3 sun = sunColor * light * (phase * 0.95 + 0.50) * (0.40 + 0.60 * powder); // 太阳直射。
            // 环境光按高度与密度变化：云底比云顶暗，薄处比厚处亮。
            // 强度要足够，否则背光面会发灰发脏，看起来像一层烟。
            vec3 ambient = skyColor * (0.26 + 0.34 * (1.0 - ogxSaturate(density * 0.5))) * (0.42 + 0.58 * height); // 天空环境光。
            float extinction = exp(-density * stepLength * 26.0); // 这一段的透过率。
            scattered += (sun + ambient) * transmittance * (1.0 - extinction); // 按剩余透过率累加。
            transmittance *= extinction; // 更新剩余透过率。
        }
        distanceAlongRay += stepLength; // 前进一段。
        if (transmittance < 0.02) // 几乎不透明就不再采样。
        {
            break; // 提前结束。
        }
    }
    float alpha = 1.0 - transmittance; // 云的覆盖率。
    vec3 color = scattered / max(alpha, 1e-4); // 预乘颜色还原成普通颜色。
    return vec4(color, alpha); // 供天空按覆盖率合成。
}

// 云影：把地面点沿阳光投到云层中部，取那里的密度换成透过率。
float ogxCloudShadow(OgxCloudLayer layer, vec3 groundPosition, vec3 sunDirection)
{
    if (sunDirection.y <= 0.0) // 太阳在地平线以下没有云影。
    {
        return 1.0; // 不压暗。
    }
    float targetHeight = layer.bottom + (layer.top - layer.bottom) * 0.5; // 云层中部高度。
    float distance = (targetHeight - groundPosition.y) / max(sunDirection.y, 0.15); // 沿阳光到云层的距离。
    vec3 position = groundPosition + sunDirection * distance; // 投影点。
    float density = ogxCloudDensity(layer, position, false); // 投影点的云密度。
    return mix(1.0, exp(-density * 1.5), 0.35); // 密度换成柔和云影，避免地面全黑。
}

// 亨耶-格林斯坦相函数：`g` 越大越向前集中，云的向阳边缘因此更亮。
// 与旧 `shaders/gfx/cloud.glsl` 的算式一致，供平面云与体积云共用。
float ogxHenyeyGreenstein(float cosAngle, float g)
{
    float num = 1.0 - g * g; // 分子，决定整体强度。
    float denom = 1.0 + g * g - 2.0 * g * cosAngle; // 分母，越靠前越小。
    float inverse = inversesqrt(denom); // 分母的平方根倒数。
    return num * inverse * inverse * inverse * (0.25 * OGX_INV_PI); // 合成一次散射的相函数。
}

// 云顶曲线：把归一化高度换成边缘压低的圆顶，用来让云的顶部看起来是弧面。
float ogxCloudTopCurve(float x)
{
    x = x - 1.0; // 平移到零点。
    return 1.0 - x * x; // 开口向下的抛物线。
}

// 双线性噪声取样：平面云用同一张噪声图，按世界尺度的万分之一缩放。
float ogxBilinearNoise(vec2 position, sampler2D noiseTexture)
{
    return textureLod(noiseTexture, position * 1.2e-4, 0.0).w; // 第四个通道当同一张图。
}

// 三次模糊噪声取样：先算十六像素的三次核，再做四次双线性采样，云团边缘因此更软。
float ogxBicubicBlurNoise(vec2 coord, sampler2D noiseTexture)
{
    coord = coord * (1.2e-4 * 64.0) - 0.5; // 噪声图每个纹素对应一万二千分之一的尺度。
    vec2 p = floor(coord); // 整数纹素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 前两个权重。
    vec4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的三次方。
    w1.yw = ff * f; // 第四个权重是偏移的三次方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为一推出。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= 1.0 / 64.0; // 换算到零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return mix(mix(textureLod(noiseTexture, vec2(c.y, c.w), 0.0).w, textureLod(noiseTexture, vec2(c.x, c.w), 0.0).w, m.x),
                mix(textureLod(noiseTexture, vec2(c.y, c.z), 0.0).w, textureLod(noiseTexture, vec2(c.x, c.z), 0.0).w, m.x), m.y); // 四次采样合成一层模糊噪声。
}

// 平面云扭曲：三层不同频率的噪声叠出大尺度扭曲量，云团因此不是规整的圆。
float ogxPlanarDistortion(vec2 position, vec2 windDirection, sampler2D noiseTexture)
{
    float density = ogxBilinearNoise(position - windDirection, noiseTexture); // 第一层。
    float scale = 4.0; // 起始频率。
    for (int i = 0; i < 3; i++, scale *= 3.0) // 三层，频率逐级乘三。
    {
        density += ogxBilinearNoise(scale * (position - windDirection * ogxFastSqrt(scale)), noiseTexture) * pow(scale, -1.3); // 高频层衰减后叠加。
    }
    return density; // 返回扭曲量。
}

// 平面云密度：扭曲后的位置叠六层噪声，再按云量抬阈值并压边缘。
float ogxPlanarDensity(vec2 position, vec2 windDirection, sampler2D noiseTexture, float noiseScale, float coverage)
{
    position *= noiseScale; // 按调用方给的空间尺度缩放。
    float distortion = ogxPlanarDistortion(position, windDirection, noiseTexture); // 取扭曲量。
    position += distortion * 50.0; // 用扭曲量偏移位置。
    float octScale = 2.8; // 每层频率倍数。
    float density = ogxBicubicBlurNoise(position - windDirection, noiseTexture); // 第一层密度。
    float weights = 1.0; // 权重和。
    for (float i = 1.0; i <= 6.0; i++) // 六层。
    {
        float scale = ogxFastSqrt(i); // 每层频率取平方根。
        float turn = -2.39996322973 * i; // 累积旋转角：每层再转一个黄金角，方向为负。
        float grow = pow(octScale, i); // 累积缩放：层间矩阵每次都乘上频率倍数。
        vec2 v = position - windDirection * scale; // 本层的偏移位置。
        vec2 noisePosition = grow * vec2(cos(turn) * v.x - sin(turn) * v.y, sin(turn) * v.x + cos(turn) * v.y); // 旋转并放大，与逐层乘矩阵的结果一致。
        noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 横向压扁，纵向拉伸。
        float weight = pow(octScale, -0.85 * i); // 每层权重按频率衰减。
        density += ogxBicubicBlurNoise(noisePosition, noiseTexture) * weight; // 累加这一层。
        weights += weight; // 累加权重。
    }
    density /= weights; // 平均到零到一。
    density = clamp(density + coverage - 1.0, 0.0, 1.0); // 按云量抬高阈值。
    density *= exp(-distortion); // 扭曲强的地方压暗。
    return density * density; // 平方让边缘收口。
}

// 平面云光照密度：层数更少，供云影与光照估计使用，便宜但不改变形状。
float ogxPlanarLightingDensity(vec2 position, vec2 windDirection, sampler2D noiseTexture, float noiseScale, float coverage)
{
    position *= noiseScale; // 按空间尺度缩放。
    float distortion = ogxPlanarDistortion(position, windDirection, noiseTexture); // 取扭曲量。
    position += distortion * 50.0; // 用扭曲量偏移位置。
    float octScale = 2.8; // 每层频率倍数。
    float density = ogxBicubicBlurNoise(position - windDirection, noiseTexture); // 第一层。
    float weights = 1.0; // 权重和。
    for (float i = 1.0; i <= 3.0; i++) // 三层。
    {
        float scale = ogxFastSqrt(i); // 每层频率。
        float turn = -2.39996322973 * i; // 累积旋转角。
        float grow = pow(octScale, i); // 累积缩放。
        vec2 v = position - windDirection * scale; // 本层的偏移位置。
        vec2 noisePosition = grow * vec2(cos(turn) * v.x - sin(turn) * v.y, sin(turn) * v.x + cos(turn) * v.y); // 旋转并放大。
        noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 横向压扁，纵向拉伸。
        float weight = pow(octScale, -0.85 * i); // 每层权重。
        density += ogxBilinearNoise(noisePosition, noiseTexture) * weight; // 用更便宜的取样累加。
        weights += weight; // 累加权重。
    }
    density /= weights; // 平均。
    density = clamp(density + coverage - 1.0, 0.0, 1.0); // 按云量抬高阈值。
    density *= exp(-distortion); // 扭曲强的地方压暗。
    return density * density; // 平方收口。
}

// 平面云的光照遮挡：沿光方向按逐步放大的步长走几步，累加光照密度乘步长。
// 为什么步长逐次放大：离采样点越远云越稀，放大步长能用同样多的样本覆盖更远，
// 原程序用四步、每步乘一点五；步数与增长交给调用方，库不预设画质档位。
float ogxPlanarCloudLightingDepth(vec2 samplePosition, vec2 lightDirection, vec2 windDirection,
    float dither, float firstStep, float stepGrowth, int steps,
    sampler2D noiseTexture, float noiseScale, float coverage)
{
    vec2 position = samplePosition + firstStep * dither * lightDirection; // 起点先沿光方向抖一下，打散条带。
    float stepLength = firstStep; // 当前步长。
    float depth = 0.0; // 沿光方向累积的遮挡密度。
    for (int i = 0; i < steps; i++) // 逐步前进。
    {
        depth += ogxPlanarLightingDensity(position, windDirection, noiseTexture, noiseScale, coverage) * stepLength; // 这一段的密度乘长度才是遮挡量。
        position += lightDirection * stepLength; // 前进一整步。
        stepLength *= stepGrowth; // 下一步更长。
    }
    return depth; // 交回累积遮挡，调用方取倒数得到阳光能量。
}

// 云影投影坐标：把世界点沿光方向投到云影所在的水平面，再换成零到一贴图坐标。
// 为什么先加相机高度：云影贴图跟着相机平移，投影必须用相机相对的高度，否则走动时影子会漂。
vec2 ogxCloudShadowCoord(vec3 worldPos, vec3 lightDir, float cameraY, float range)
{
    vec2 coord = worldPos.xz - lightDir.xz * ((worldPos.y + cameraY) / lightDir.y); // 沿光方向落到云影平面。
    return coord * (1.0 / range) + 0.5; // 换成贴图坐标。
}

// 十六像素三次模糊：四次双线性采样合成，返回红通道；云影贴图只有红通道有意义。
// 两次双线性之间按权重比例混合，效果等价于四次三次采样，但纹理读取次数减半。
float ogxCloudShadowBicubic(sampler2D shadowTex, vec2 coord, vec2 texSize)
{
    vec2 texPixel = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize - 0.5; // 换成以像素为单位的坐标。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 两个方向的前两个权重。
    vec4 w1; // 两个方向的后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
    w1.yw = ff * f; // 第四个权重是偏移立方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= texPixel.xxyy; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return mix(mix(textureLod(shadowTex, c.yw, 0.0).x, textureLod(shadowTex, c.xw, 0.0).x, m.x),
                mix(textureLod(shadowTex, c.yz, 0.0).x, textureLod(shadowTex, c.xz, 0.0).x, m.x),
                m.y); // 四次双线性采样得到十六像素的三次模糊，取红通道。
}

// 云影取样：按天气在晴天与雨天两档之间混合，`wetness` 是降雨湿润度。
float ogxCloudShadowSample(sampler2D shadowTex, vec3 worldPos, vec3 lightDir, float cameraY, float range,
    vec2 screenExtent, vec2 pixelSize, float texSize, float wetness, float rainShadow, bool fadeAngle)
{
    vec2 coord = ogxCloudShadowCoord(worldPos, lightDir, cameraY, range); // 投到云影贴图坐标。
    float cloudShadow = 1.0 - wetness; // 雨天默认的云影底值。
    if (ogxEqual(ogxSaturate(coord), coord)) // 只有落在贴图范围内才采样。
    {
        vec2 shadowTexel = screenExtent - coord * texSize; // 贴图贴在画面右上角，坐标要翻转。
        vec2 fade = ogxSaturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
        cloudShadow = mix(cloudShadow, ogxCloudShadowBicubic(shadowTex, shadowTexel * pixelSize, screenExtent), fade.x * fade.y); // 三次采样并淡出。
    }
    if (fadeAngle) // 太阳越贴地云影越淡。
    {
        float fade = smoothstep(0.06, 0.18, abs(lightDir.y)); // 光方向越平越淡。
        cloudShadow = mix(1.0 - wetness, cloudShadow, fade * fade); // 按淡出权重混合。
    }
    return ((rainShadow - 1.0) * wetness + 1.0) * cloudShadow + (wetness - rainShadow * wetness); // 晴天与雨天两档之间插值。
}

// 全局云影：从云影贴图顶行的统计像素取一个粗粒度值；没有贴图时按天气估。
float ogxGlobalCloudShadow(sampler2D shadowTex, ivec2 statTexel, float wetness, float rainShadow, bool fromTexture)
{
    if (fromTexture) return mix(texelFetch(shadowTex, statTexel, 0).a, 1.0, 0.03 - wetness * 0.015); // 统计像素存全局云影。
    return 1.0 - wetness * (rainShadow * 0.985); // 纯天气估计。
}

// 云影横向或纵向高斯模糊：权重固定，轴由参数给；其余通道原样带过。
// 只模糊红通道，因为绿蓝通道存的是别的统计量，混进来会污染后续读取。
vec4 ogxCloudShadowBlur(sampler2D shadowTex, ivec2 texel, ivec2 axis, ivec2 borderMin, ivec2 borderMax)
{
    vec4 blur = vec4(0.0); // 模糊结果。
    ivec2 sampleCoord = clamp(texel - 3 * axis, borderMin, borderMax); // 第三个负向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.054543; // 按高斯权重累加。
    sampleCoord = clamp(texel - 2 * axis, borderMin, borderMax); // 第二个负向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.099384; // 累加。
    sampleCoord = clamp(texel - 1 * axis, borderMin, borderMax); // 第一个负向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.181090; // 累加。
    vec4 center = texelFetch(shadowTex, texel, 0); // 中心样本。
    blur.r += center.r * 0.329966; // 中心权重最大。
    blur.gba += center.gba; // 其余通道原样带过。
    sampleCoord = clamp(texel + 1 * axis, borderMin, borderMax); // 第一个正向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.181090; // 累加。
    sampleCoord = clamp(texel + 2 * axis, borderMin, borderMax); // 第二个正向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.099384; // 累加。
    sampleCoord = clamp(texel + 3 * axis, borderMin, borderMax); // 第三个正向样本。
    blur.r += texelFetch(shadowTex, sampleCoord, 0).r * 0.054543; // 累加。
    return blur; // 返回模糊后的云影贴图。
}

// Eclipse 的云相函数：和 Henyey-Greenstein 不是同一公式，分母固定除以 3.14。
float ogxCloudPhaseEclipse(float x, float g)
{
    float gg = g * g; // g 的平方。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现直接写 3.14。
}

// Eclipse 的云密度三线性取样：不做平滑，直接用小数部分在两层噪声之间插值。
// 与 `ogxStormNoise` 的区别是后者先把小数部分做了 smoothstep，两者不能互换。
float ogxCloudDensityAtPos(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    position /= 18.0; // 参考实现的世界尺度。
    position.xz *= 0.5; // 横向再压一半。
    vec3 cell = floor(position); // 整数格。
    vec3 fraction = fract(position); // 小数部分。
    vec2 uv = cell.xz + fraction.xz + cell.y * vec2(0.0, 193.0); // 三维转二维噪声坐标。
    vec2 sample2 = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 取两个通道。
    return mix(sample2.r, sample2.g, fraction.y); // 按纵向小数插值。
}

#endif

/*
生成文件：体积云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体积云模块：Nubis / Hillaire 风格的积云形状、光照、步进与云影。
调用位置：任何需要体积云的程序；Minecraft 光影由 `/omni-gfx/cloud_volume.glsl` 引入，
    `rendering/cloud/volumetric.glsl` 只把选项、天气与纹理换成参数。
可复制示例：
    OgxCumulusMedia media = ...; // 填好云底、云顶、风与光照强度。
    vec3 hit; // 平均命中位置，供大气淡出使用。
    vec4 cloud = ogxCumulusMarch(viewDir, media, jitter, hit, baseTex, detailTex, curlTex,
                                   40.0, 1.0, sunDir, 1.0, 0.0, 3.0, 1.2);
    // cloud.rgb 是预乘散射颜色，cloud.a 是透射率；调用方按 1 - cloud.a 合成覆盖率。
设计原因与取舍：
    形状来自三维 Perlin-Worley 基础噪声与高频 Worley 侵蚀。基础噪声先决定云块位置，
    高频噪声再从边缘往里削，云边因此是一簇簇花椰菜状的小鼓包，不是光滑的椭球。
    云底用快速收口的竖直包络压平，云顶用圆滑曲线收圆；没有固定的塔身或砧状遮罩，
    所以同一套参数不会生成窄柱状轮廓，云形完全由风、云量与噪声决定。
    光照沿太阳方向步进，单次散射与三档多次散射分开：厚云内部靠慢衰减的多次散射托起，
    薄边再加逆光透射，云底不会黑成纸片，云顶与向阳面保持亮白。
    纹理、云层高度、风、天气与太阳方向全部由调用方传入，库不读取选项或宿主状态。
    结构体字段沿用旧名字：宿主有几十处逐字段赋值，改名会把风险推到调用点。
*/
#ifndef OGX_CLOUD_VOLUME_INCLUDED
#define OGX_CLOUD_VOLUME_INCLUDED

// 云模块提供顶部曲线与相位函数，数学提供球面求交与夹紧。


// 体积云的一层参数；不同云层换字段即可复用同一套步进。
struct OgxCumulusMedia
{
    vec3 wind; // 风的位移，单位与云坐标一致。
    vec3 camera_position; // 相机绝对世界位置，供云影与闪电使用。
    vec3 light_color; // 直射光颜色。
    vec3 sky_color; // 天空环境光颜色。
    vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
    vec2 altitude; // 云层底与顶的高度，米。
    vec2 lighting_strength; // 直射与环境强度。
    float planet_radius; // 行星半径，米。
    float cloud_scale; // 世界坐标到云坐标的倍率；一表示直接用米。
    float density_option; // 密度倍率。
    float coverage; // 这一层的云量下限，越大云越多。
    float wetness; // 零到一的湿润度。
    float bottom_brightness; // 云底保留的直射亮度。
    float outscatter_factor; // 外散射指数，薄处与云顶更亮。
    float lightning_intensity; // 闪电事件强度，零表示没有闪电。
    float lightning_strength; // 闪电亮度选项。
};

// 三次平滑曲线：把零到一压成两端缓、中间快的过渡。
float ogxCumulusCurve(float x)
{
    return x * x * (3.0 - 2.0 * x); // 两端导数为零，云的口沿不会出现折线。
}

// NUBIS 的顶部曲线：以 1 为顶点、在 0 与 2 处落到零的抛物线，用来把云顶收圆。
float ogxCumulusCurveTop(float x)
{
    x = x - 1.0; // 把顶点移到一。
    return 1.0 - x * x; // 二次曲线在两端降到零。
}

// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向随高度剪切。
// 曲率修正让远处的云跟着地球弧度下沉，否则云层会像一块硬板挂在天边。
// 为什么保留 `cloud_scale`：Minecraft 侧用公里，测试世界用米；调用方乘一次就能统一，
// 库内不再猜单位，也不会把覆盖率的低频坐标压成常数。
vec4 ogxCumulusSetPos(vec3 marchingPos, OgxCumulusMedia media)
{
    vec4 cloudPos = vec4(marchingPos, 0.0); // 前三通道是位置，第四通道是层内高度。
    cloudPos.y = length(cloudPos.xyz + vec3(0.0, media.planet_radius, 0.0)) - media.planet_radius; // 球面距离。
    cloudPos.w = ogxRemapSaturate(cloudPos.y, media.altitude.x, media.altitude.y); // 层内归一化高度。
    cloudPos.xyz = cloudPos.xyz * media.cloud_scale + vec3(30.0 * cloudPos.w, 0.0, -12.0 * cloudPos.w); // 高度剪切。
    return cloudPos; // 返回米制世界坐标或调用方指定的云坐标。
}

// 采样云密度：三维 Perlin-Worley 决定云块，高频 Worley 削出花椰菜边缘。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sampleDetail` 为假时跳过高频侵蚀。
vec2 ogxCumulusSampleDensity(vec4 cloudPos, OgxCumulusMedia media, bool sampleDetail, float coverage,
    sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise, float baseScale, float coverageOffset,
    float detailScale, float detailStrength)
{
    // 与 iterationT 的 NUBIS 逐行一致：yzw 三种 Worley 作为阈值，x 通道作为 Perlin-Worley 形状，
    // 再乘竖直包络。128 立方纹理的通道分布与这套公式直接对应，云块边缘才有细碎的花椰菜鼓包。
    vec4 baseSample = textureLod(baseNoise, cloudPos.xyz * baseScale + media.wind * 10.0, 0.0);
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2;
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0);
    // 竖直包络：底部快速到达满密度形成平底，顶部用两段曲线收圆，云不会长成蘑菇柄。
    float shapeCurve = ogxCumulusCurveTop(ogxSaturate(1.0 - cloudPos.w)) * 0.5;
    shapeCurve += ogxCumulusCurve(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5;
    baseDensity *= shapeCurve;
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8;
    baseDensity *= mix(1.0, ogxCumulusCurveTop(ogxSaturate(cloudPos.w * 3.0)), media.wetness);
    // 云量：同一纵列从云底到云顶共享同一份覆盖，积云才会从平底往上长。
    // 噪声低的地方阈值接近一，整列都是蓝天；噪声高的地方阈值下降，只留下被三维噪声填满的云块。
    float coverageNoise = textureLod(baseNoise, cloudPos.xyz * vec3(8.5e-5, -1.0e-5, 8.5e-5)
        + media.wind + vec3(coverageOffset, coverageOffset, coverageOffset), 0.0).x;
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage);
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0);
    // 密度控制：中段最厚，顶部收薄，底部保留平底；这两条曲线也决定云顶的亮边宽度。
    baseDensity *= ogxCumulusCurve(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0;
    baseDensity *= ogxCumulusCurveTop(ogxSaturate(cloudPos.w * 1.8));
    baseDensity = ogxSaturate(baseDensity);
    float detailedDensity = 0.0; // 高频侵蚀后的密度。
    if (baseDensity > 1.0e-6 && sampleDetail) // 只有基础密度存在才付细节成本。
    {
        float curl = textureLod(curlNoise, cloudPos.xy * 0.0001, 0.0).w; // 水平扭曲。
        cloudPos.xy += curl * (100.0 - cloudPos.w * 100.0); // 越靠云底扭曲越大，底部有翻滚感。
        // 三张 Worley 从大到小削掉云边：通道权重 0.625、0.25、0.125 与 iterationT 相同。
        vec3 detailedNoise = textureLod(detailNoise, cloudPos.xyz * detailScale + media.wind * 140.0, 0.0).xyz;
        detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125;
        detailedDensity *= (0.21 - media.wetness * 0.11) * detailStrength; // 晴天边缘更碎，雨天更实。
        detailedDensity = ogxRemapSaturate(baseDensity, detailedDensity, 1.0); // 侵蚀不能超过基础密度。
    }
    else // 不需要细节时直接用基础密度。
    {
        detailedDensity = baseDensity;
    }
    return vec2(baseDensity, detailedDensity); // 返回两份密度。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱，云采样点离柱越近越亮。
vec3 ogxCumulusLightning(vec3 relativePos, OgxCumulusMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
    vec3 boltPos = vec3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z);
    float boltDistance = length(relativePos - boltPos); // 介质到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return vec3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength);
}

// 云的光照：沿太阳方向五次取样，单次散射、宽相位与底光按 NUBIS 的权重组合。
// 为什么分为直射与环境两部分：厚云内部直射衰减极快，如果没有缓慢衰减的宽相位，
// 云底会黑成纸片；环境项同时给出天空色，背光面才不会只剩灰。
vec3 ogxCumulusLighting(vec3 marchingPos, OgxCumulusMedia media, vec2 cloudDensity, vec4 cloudPos, float noise,
    float vdotl, float coverage, vec3 worldLight, sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise,
    float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    // 与 iterationT 相同：起始 28 米，五步，每步乘 1.5；前三步带高频细节。
    float stepLength = 28.0; // 起始步长，米。
    float lightingDensity = 0.0; // 沿太阳方向累积的密度乘距离。
    for (int i = 0; i < 5; i++) // 五次取样覆盖约三百米。
    {
        vec4 checkPos = ogxCumulusSetPos(marchingPos + worldLight * stepLength * noise, media); // 取样点。
        lightingDensity += ogxCumulusSampleDensity(checkPos, media, i < 3, coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength).y * stepLength; // 累加消光。
        marchingPos += worldLight * stepLength; // 沿光方向推进。
        stepLength *= 1.5; // 远处步长更大，因为云的细节在远处会合并。
    }
    // 单次散射：两档相位相加，再乘底部亮度与高度外散射。
    float hg = ogxHenyeyGreenstein(vdotl, 0.7); // 强前向相位，逆光时出现银边。
    float direct = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - media.wetness * 0.8); // 单次散射。
    direct += (1.0 / (lightingDensity * 0.2 + 1.0)) * (ogxHenyeyGreenstein(vdotl, 0.2) + 0.1); // 多次散射的宽相位。
    direct *= hg * 2.0 + 1.0; // 逆光侧整体提升。
    direct *= mix(media.bottom_brightness, 0.005 + pow(cloudDensity.y, media.outscatter_factor),
        ogxCumulusCurve(ogxSaturate(cloudPos.w * 3.333 - 0.333))); // 云底到云顶的亮度分配。
    direct *= pow(max(cloudPos.w, 0.05), 0.75); // 云顶更受光。
    vec3 lightColor = media.light_color * (direct * media.lighting_strength.x * 36.0); // 直射项，系数与 iterationT 相同。
    // 天光：薄处与云顶接收更多环境光，云底保留蓝灰底色。
    float ambient = 1.0 - cloudDensity.x;
    ambient *= ogxFastSqrt(cloudPos.w);
    lightColor += media.sky_color * (ambient * media.lighting_strength.y * 0.35);
    lightColor += ogxCumulusLightning(marchingPos - media.camera_position, media, 400.0, -10.0);
    return lightColor; // 返回这一段的云颜色。
}

// 体积云步进核心：沿视线在云层里步进，返回预乘散射颜色与透射率；平均命中位置通过 `hitOffset` 交回。
// 为什么把空气透视留给调用方：天空散射属于大气效果，通用库只负责云本身的密度与光照。
vec4 ogxCumulusMarch(vec3 worldDir, OgxCumulusMedia media, vec2 noise, out vec3 hitOffset,
    sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise, float cloudSamples, float cloudQuality,
    vec3 worldLight, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    vec3 rayStart = vec3(0.0, media.planet_radius + media.camera_position.y, 0.0); // 相机在行星球上的位置。
    vec2 bottom = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.x); // 云底交点。
    vec2 top = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.y); // 云顶交点。
    vec2 marching = media.camera_position.y > media.altitude.y ? vec2(top.x, bottom.x) : vec2(bottom.y, top.y); // 进出顺序。
    vec3 marchingStart = marching.x * worldDir; // 相对相机的起点。
    vec3 marchingEnd = marching.y * worldDir; // 相对相机的终点。
    float inCloud = (1.0 - ogxSaturate((media.camera_position.y - media.altitude.y) * 0.005)) *
        (1.0 - ogxSaturate((media.altitude.x - media.camera_position.y) * 0.005)); // 相机在云层内时的权重。
    float inner = bottom.y >= 0.0 && media.camera_position.y > media.altitude.x ? bottom.x : top.y; // 云内起点。
    inner = min(inner, 5000.0);
    marchingStart = marchingStart * (1.0 - inCloud) + media.camera_position; // 相机在云内时从相机开始。
    marchingEnd = mix(marchingEnd, inner * worldDir, inCloud) + media.camera_position; // 云内只走五公里。
    // 视线越接近地平线，云层法向长度越长；超过六十公里后云的细节已经小于一个像素，
    // 再步进只会把远处压成一条硬带，所以在这里截断，交给空气透视淡出。
    float span = length(marchingEnd - marchingStart);
    if (span > 60000.0)
    {
        marchingEnd = marchingStart + normalize(marchingEnd - marchingStart) * 60000.0;
    }
    float steps = cloudSamples - ogxSaturate(ogxFastSqrt(abs(worldDir.y)) * 1.4 - 0.4) * 8.0; // 朝上时省几步。
    steps = max(floor(steps * cloudQuality), 1.0);
    float stepSize = 1.0 / steps;
    vec3 increment = (marchingEnd - marchingStart) * stepSize;
    vec3 marchingPos = marchingStart + increment * noise.x; // 抖动起点，消除层状条纹。
    float densityMul = media.density_option * (media.altitude.y - media.altitude.x) * stepSize; // 消光系数。
    float vdotl = dot(worldDir, worldLight);
    vec3 accum = vec3(0.0);
    float transmittance = 1.0;
    vec3 rayHit = vec3(0.0);
    float sumTransmit = 0.0;
    for (int i = 0; i < int(steps); i++, marchingPos += increment)
    {
        vec4 cloudPos = ogxCumulusSetPos(marchingPos, media);
        vec2 cloudDensity = ogxCumulusSampleDensity(cloudPos, media, true, media.coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength);
        if (cloudDensity.y < 1.0e-6) continue; // 空区域跳过光照。
        vec3 cloudColor = ogxCumulusLighting(marchingPos, media, cloudDensity, cloudPos, noise.y, vdotl, media.coverage,
            worldLight, baseNoise, detailNoise, curlNoise, baseScale, coverageOffset, detailScale, detailStrength);
        float absorption = exp2(-cloudDensity.y * densityMul); // 这一段的透过率。
        accum += cloudColor * (transmittance - absorption * transmittance);
        rayHit += marchingPos * transmittance;
        sumTransmit += transmittance;
        transmittance *= absorption;
        if (transmittance < 1.0e-4) break;
    }
    hitOffset = rayHit / max(sumTransmit, 1.0e-4) - media.camera_position;
    return vec4(accum, transmittance);
}

// 云影贴图：从地面坐标沿太阳方向投到云层，取两处云密度合成阴影值。
// 为什么先算世界坐标再调用 `ogxCumulusSetPos`：主视线步进用的是同一条云坐标变换，
// 直接拿米制坐标去采样噪声会把云影裁成另一种尺度，地面阴影和天上的云块对不上。
float ogxCumulusShadowTex(vec2 coord, OgxCumulusMedia media, vec3 worldLight, float range, sampler3D baseNoise,
    sampler2D curlNoise, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    coord = coord * range - (range * 0.5); // 贴图坐标换回相对相机的地表坐标。
    vec3 groundPos = vec3(coord.x + media.camera_position.x, 0.0, coord.y + media.camera_position.z); // 地面点。
    float thickness = media.altitude.y - media.altitude.x; // 云层厚度。
    float invLightY = 1.0 / max(worldLight.y, 0.05); // 低阳时限制投影距离。
    vec3 samplePos = groundPos + worldLight * ((media.altitude.x + thickness * 0.25) * invLightY); // 投到云层下段。
    vec4 cloudPos = ogxCumulusSetPos(samplePos, media);
    float cloudDensity = ogxCumulusSampleDensity(cloudPos, media, false, media.coverage, baseNoise, baseNoise, curlNoise,
        baseScale, coverageOffset, detailScale, detailStrength).y; // 下段密度。
    samplePos = groundPos + worldLight * ((media.altitude.x + thickness * 0.50) * invLightY); // 再往上一段。
    cloudPos = ogxCumulusSetPos(samplePos, media);
    cloudDensity = max(cloudDensity, ogxCumulusSampleDensity(cloudPos, media, false, media.coverage, baseNoise, baseNoise,
        curlNoise, baseScale, coverageOffset, detailScale, detailStrength).y); // 两块取较厚的那块。
    return exp2(-cloudDensity * 20.0); // 密度换成透过率；系数与 iterationT 的云影一致。
}

#endif

/*
生成文件：水面模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库水面模块：方向波法线、菲涅尔、吸收、折射偏移、太阳高光与岸线泡沫。
调用位置：水面着色与任何需要程序化水面的程序；Minecraft 光影由 `/omni-gfx/water.glsl` 引入。
可复制示例：
    OgxWater w = ogxWaterDefault(); // 取默认水体。
    vec3 n = ogxWaterNormal(p.xz, t, d, 1.0, 1.0); // 算波法线。
    vec3 c = ogxWaterShade(w, n, viewDir, sunDir, sunColor, r1, r2, depthM, foamAmt, alphaOut); // 算水面颜色。
    `OgxOceanWaveSum sum = ogxOceanWaveSum(vec2(0.0), t, ogxOceanWavesDefault());` 迭代正弦海洋。
    `float h = ogxOceanWaveHeight(sum, 13.0, 1.0);` 归一化后的波高。
设计原因与取舍：
    波形来自旧 `shaders/gfx/water.glsl` 的六层噪声叠加思路，换成解析方向波，省掉噪声贴图。
    只做单层水面，但保留长波、斜波、短波与细波纹四级，远处自动淡出高频，避免闪烁。
    反射与折射颜色由调用方传入，库不读取立方体贴图或屏幕纹理，因此能同时服务 Iris 与独立测试世界。
*/
#ifndef OGX_WATER_INCLUDED
#define OGX_WATER_INCLUDED

// 数学模块提供菲涅尔、GGX 高光与夹紧，噪声模块打散规则波列。


// 一组水面光学参数；不同水体换字段即可，不必改波形与着色顺序。
struct OgxWater
{
    vec3 shallowColor; // 浅水颜色，线性空间。
    vec3 deepColor; // 深水颜色，线性空间。
    vec3 absorption; // 逐通道吸收系数，每米。
    float waveScale; // 波形空间缩放。
    float waveHeight; // 波形坡度倍率。
    float roughness; // 太阳高光粗糙度。
    float refraction; // 屏幕折射偏移强度。
};

// 默认水体：偏青的浅水、深蓝的深水，红光吸收最快。
OgxWater ogxWaterDefault()
{
    OgxWater water; // 先声明再填写字段。
    water.shallowColor = vec3(0.10, 0.34, 0.36); // 浅水偏青绿。
    water.deepColor = vec3(0.008, 0.045, 0.120); // 深水偏蓝。
    water.absorption = vec3(0.18, 0.075, 0.035); // 红光最先被吸收，深水因此偏蓝。
    water.waveScale = 1.0; // 默认波形密度。
    water.waveHeight = 1.0; // 默认坡度。
    water.roughness = 0.08; // 水面比较光滑，高光集中。
    water.refraction = 0.035; // 折射偏移不要太大，避免岸边拉扯。
    return water; // 返回可直接修改的默认值。
}

// 水面法线：四组方向波的解析梯度相加，再转成朝上的法线。
vec3 ogxWaterNormal(vec2 position, float time, float distance, float waveScale, float waveHeight)
{
    vec2 p = position * waveScale; // 按波形密度缩放空间坐标。
    vec2 gradient = vec2(0.0); // 高度场的水平梯度。
    vec2 direction0 = vec2(0.62, 0.28); // 长波方向。
    vec2 direction1 = vec2(-0.31, 0.74); // 斜向波方向。
    float nearFade = 1.0 - smoothstep(20.0, 120.0, distance); // 近处保留高频细节。
    gradient = direction0 * (0.320 * 0.035 * cos(dot(p, direction0) * 0.035 + time * 0.55)); // 一百八十米级长波，远处也不会闪。
    gradient += direction1 * (0.220 * 0.060 * cos(dot(p, direction1) * 0.060 + time * 0.85)); // 一百米级斜向波。
    vec2 direction2 = vec2(0.88, -0.41); // 短波方向。
    gradient += direction2 * (0.080 * 0.180 * cos(dot(p, direction2) * 0.180 + time * 1.2)) * nearFade; // 三十米级短波只在近处。
    vec2 direction3 = vec2(-0.67, -0.55); // 细波纹方向。
    gradient += direction3 * (0.040 * 0.450 * cos(dot(p, direction3) * 0.450 + time * 1.7)) * nearFade * nearFade; // 十米级细波纹只在近处。
    gradient *= waveHeight; // 按坡度倍率缩放。
    float breakup = 0.75 + 0.5 * ogxValueNoise2(position * 0.015 + vec2(time * 0.02, time * 0.013)); // 低频噪声打散规则波列。
    gradient *= breakup; // 避免整片水面出现同一条亮带。
    float distanceFade = 1.0 - smoothstep(200.0, 900.0, distance) * 0.85; // 远处压平法线，减少像素级闪烁。
    return normalize(vec3(-gradient.x * distanceFade, 1.0, -gradient.y * distanceFade)); // 高度场梯度转成朝上的法线。
}

// 单个 Gerstner 波对水面坡度的贡献：方向乘坡度余弦，波长决定传播速度。
// 为什么不用贴图：解析波列的相位永远连续，远处压平后不会像滚动噪声那样闪烁；
// 振幅已经折进 `steepness`，所以这里只交回水平梯度，调用方直接转成法线。
vec2 ogxGerstnerGradient(vec2 position, vec2 direction, float wavelength, float steepness, float time, float phase)
{
    float waveNumber = 6.28318530718 / max(wavelength, 0.05); // 每米多少个弧度。
    float angularSpeed = sqrt(9.81 * waveNumber); // 深水色散关系，长波跑得快、短波跑得慢。
    float angle = waveNumber * dot(direction, position) - angularSpeed * time + phase; // 当前相位。
    return direction * (steepness * cos(angle)); // 正弦波高度的水平导数。
}

// 水面 Gerstner 波法线：五组不同波长与方向的波叠加，再补一层细碎风纹。
// 为什么用五组：一组是规则条纹，两组会互相拍成十字，五组不同方向和波长才有湖面的随机感。
// 距离越远，短波越早淡出；否则一个像素覆盖多个波长，画面会闪成噪点。
vec3 ogxGerstnerNormal(vec2 position, float time, float distance, float scale, float amplitude)
{
    vec2 p = position * scale; // 按波形密度缩放世界坐标。
    vec2 gradient = vec2(0.0); // 五组波的水平梯度之和。
    gradient += ogxGerstnerGradient(p, vec2(0.86, 0.51), 13.0, 0.090, time, 0.0); // 十三米长波。
    gradient += ogxGerstnerGradient(p, vec2(-0.42, 0.91), 8.2, 0.072, time, 1.7); // 八米斜波。
    float nearFade = 1.0 - smoothstep(45.0, 260.0, distance); // 四米以下的波在远处淡出。
    gradient += ogxGerstnerGradient(p, vec2(0.97, -0.24), 5.1, 0.052, time, 3.1) * nearFade; // 五米碎波。
    float closeFade = 1.0 - smoothstep(20.0, 110.0, distance); // 两米级波纹只在近处。
    gradient += ogxGerstnerGradient(p, vec2(-0.71, -0.70), 3.3, 0.038, time, 5.2) * closeFade; // 三米波纹。
    gradient += ogxGerstnerGradient(p, vec2(0.32, 0.95), 2.1, 0.026, time, 0.9) * closeFade; // 两米细波。
    // 风纹：用两个相差半步的值噪声差分，补上解析波没有的碎小起伏。
    float rippleFade = 1.0 - smoothstep(12.0, 70.0, distance);
    float eps = 0.12; // 差分步长，米。
    float height0 = ogxValueNoise2(p * 2.3 + vec2(time * 0.16, -time * 0.11));
    float heightX = ogxValueNoise2((p + vec2(eps, 0.0)) * 2.3 + vec2(time * 0.16, -time * 0.11));
    float heightZ = ogxValueNoise2((p + vec2(0.0, eps)) * 2.3 + vec2(time * 0.16, -time * 0.11));
    gradient += vec2(height0 - heightX, height0 - heightZ) * (0.55 * rippleFade / eps);
    gradient *= amplitude; // 统一坡度倍率。
    return normalize(vec3(-gradient.x, 1.0, -gradient.y)); // 高度场梯度转成朝上的法线。
}

// 菲涅尔：正对时只剩基础反射率，掠射时接近全反射。
float ogxWaterFresnel(float NdotV, float f0)
{
    float x = 1.0 - ogxSaturate(NdotV); // 掠射程度。
    float x2 = x * x; // 平方。
    return f0 + (1.0 - f0) * x2 * x2 * x; // 五次方近似。
}

// 水的吸收：按水深逐通道衰减，红光最快，所以深水偏蓝。
vec3 ogxWaterAbsorption(OgxWater water, float depth)
{
    return exp(-water.absorption * max(depth, 0.0)); // 比尔-朗伯定律。
}

// 屏幕折射偏移：水越深、越靠近相机，偏移越明显；远处收小避免整片扭曲。
vec2 ogxWaterRefractionOffset(vec3 normal, float depth, float distance, float strength)
{
    vec2 offset = normal.xz * strength * ogxSaturate(depth * 0.12) / (1.0 + distance * 0.015); // 按深度与距离缩放。
    return offset; // 返回屏幕坐标偏移。
}

// 岸线泡沫：水很浅时出现，噪声让泡沫边缘不整齐。
float ogxWaterFoam(float depth, float noise)
{
    float edge = 1.0 - smoothstep(0.0, 0.9, max(depth, 0.0)); // 只在浅水出现。
    return edge * ogxSaturate(noise * 1.6 - 0.3); // 噪声把泡沫打散。
}

// 水面着色：折射色乘吸收，再按菲涅尔混入反射，最后叠太阳高光与泡沫。
vec3 ogxWaterShade(OgxWater water, vec3 normal, vec3 viewDirection, vec3 sunDirection, vec3 sunColor,
                     vec3 reflectionColor, vec3 refractionColor, float depth, float foam, out float alpha)
{
    float facing = ogxSaturate(dot(normal, viewDirection)); // 正对程度。
    float fresnel = ogxWaterFresnel(facing, 0.02); // 水的菲涅尔基础反射率约零点零二。
    vec3 transmitted = refractionColor * ogxWaterAbsorption(water, depth); // 水下颜色被水吸收。
    // 深水会彻底吸收掉水底的颜色，只剩水本身的体色；不补这一步，深海会变成一块黑。
    transmitted = mix(water.deepColor, transmitted, exp(-depth * 0.32)); // 越深越接近深水体色。
    transmitted = mix(water.shallowColor, transmitted, ogxSaturate(depth * 0.25)); // 浅水保留更多水色。
    vec3 color = mix(transmitted, reflectionColor, fresnel); // 折射与反射按菲涅尔混合。
    color += ogxSpecularGGX(normal, viewDirection, sunDirection, water.roughness, 0.02) * sunColor * 1.5; // 太阳高光。
    color += foam * water.shallowColor * 0.8; // 岸线泡沫。
    alpha = ogxSaturate(fresnel * 0.85 + 0.22 + ogxSaturate(depth * 0.08)); // 深水更不透明。
    return color; // 返回线性水面颜色。
}

// 平滑噪声取样：先把坐标吸到最近的纹素中心，再用三次曲线改写小数部分，得到不会闪的平滑噪声。
// 与旧 `shaders/gfx/water.glsl` 的算式一致，波纹形状因此不变。
vec4 ogxTextureSmooth(sampler2D noiseTexture, vec2 coord)
{
    coord *= 64.0; // 放大到六十四格，再按格取平滑。
    coord += 0.5; // 移到格子中心。
    vec2 whole = floor(coord); // 整数格。
    vec2 part = coord - whole; // 小数部分。
    coord = whole + part * part * (3.0 - 2.0 * part); // 三次曲线改写小数部分。
    coord -= 0.5; // 移回格子角。
    coord *= 0.015625; // 缩回六十四分之一，换算到零到一坐标。
    return textureLod(noiseTexture, coord, 0.0); // 读取平滑后的噪声通道。
}

// 几乎恒等函数：只在靠近中间的一段把值重写成更平的曲线，用来压掉最亮和最暗的水波。
float ogxAlmostIdentity(float x, float m, float n)
{
    x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值。
    if (x <= m) // 只在该区间中间改写。
    {
        float a = 2.0 * n - m; // 三次项系数。
        float b = 2.0 * m - 3.0 * n; // 二次项系数。
        float t = x / m; // 归一化到零到一。
        x = (a * t + b) * t * t + n; // 三次多项式保持端点连续。
    }
    return 1.0 - x; // 再翻转回来。
}

// 水面高度：六层不同尺度与速度的噪声叠加，按权重和归一化。
float ogxWaves(vec3 position, sampler2D noiseTexture, float time, float waveScale)
{
    float wavesTime = time * 0.0035; // 波浪时间比真实时间慢很多。
    position *= waveScale; // 按波浪尺度缩放空间坐标。
    vec2 p = position.xz - position.y; // 取水平坐标，减去高度让波浪跟着高度错动。
    p += -3.875 * wavesTime; // 整片波浪一起平移。
    p.x = -p.x; // 翻转一个轴，打散方向。
    float waves = 0.0; // 累积高度。
    float weight = 0.0; // 累积权重。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(2.0, 1.2) + vec2(0.0, p.x * 2.1)).w; weight += 1.0; // 第一层大浪。
    p = p * 0.475; // 缩小坐标，频率升高。
    p += vec2(-5.16, -7.75) * wavesTime; // 这一层被风推着走。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(2.0, 1.4) + vec2(0.0, -p.x * 2.1)).w * 4.0; weight += 4.0; // 第二层。
    p *= 0.67; // 再抬高频率。
    p.x += 7.75 * wavesTime; // 反向移动。
    waves += ogxTextureSmooth(noiseTexture, p + vec2(0.0, p.x * 1.1)).z * 8.0; weight += 8.0; // 第三层。
    p *= 0.7; // 继续抬高频率。
    p.x += -2.82 * wavesTime; // 顺风移动。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.75) + vec2(0.0, -p.x * 1.7)).w * 16.0; weight += 16.0; // 第四层。
    p *= 0.45; // 高频细节。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, -p.x * 1.7)).z, 0.2, 0.1) * 30.0; weight += 30.0; // 第五层。
    p *= 0.5; // 最高频一层。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, p.x * 1.7)).w, 0.2, 0.1) * 20.0; weight += 20.0; // 第六层。
    return waves / weight; // 高度除以权重和，归一化到零到一。
}

// 波法线：用中心与两个邻点的高度差构成法线，再按波高与陡度缩放。
vec3 ogxWavesNormal(vec3 position, sampler2D noiseTexture, float time, float waveScale, float waveHeight, float heightScale)
{
    float sampleDistance = 12.0; // 切线差分采样的距离。
    position.xz -= 0.005 * sampleDistance; // 把采样点整体挪一点，让差分落在波浪内部。
    float center = ogxWaves(position, noiseTexture, time, waveScale); // 中心高度。
    float left = ogxWaves(position + vec3(0.01 * sampleDistance, 0.0, 0.0), noiseTexture, time, waveScale); // 横向偏移。
    float up = ogxWaves(position + vec3(0.0, 0.0, 0.01 * sampleDistance), noiseTexture, time, waveScale); // 纵向偏移。
    vec3 normal = vec3(center - left, center - up, 1.0); // 用两个方向的高度差构成法线。
    normal.xy *= waveHeight * (heightScale / sampleDistance); // 乘波高与陡度，控制倾斜。
    return normal; // 返回未归一化的法线。
}

// 水面视差：沿视线在波浪高度场里步进，找到视线与浪面的交点。
vec3 ogxWaterParallax(vec3 position, vec3 viewVector, sampler2D noiseTexture, float time, float waveScale, float heightScale)
{
    vec3 stepSize = vec3(heightScale * 0.8, heightScale * 0.8, 0.6); // 每步大小，按波高缩放。
    float waveHeight = ogxWaves(position, noiseTexture, time, waveScale); // 起点波高。
    vec3 pCoord = vec3(0.0, 0.0, 1.0); // 以当前点为参考向前推进的距离。
    vec3 steps = viewVector * stepSize; // 每步步进。
    float sampleHeight = waveHeight; // 当前步的波高。
    for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i) // 最多十二步。
    {
        pCoord.xy += steps.xy * clamp((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2), 0.0, 1.0); // 按剩余深度推进水平偏移。
        pCoord.z += steps.z; // 步进向前。
        sampleHeight = ogxWaves(position + vec3(pCoord.x, 0.0, pCoord.y), noiseTexture, time, waveScale); // 读取新位置的波高。
    }
    return position + vec3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

// 折射坐标：水面按两种法线的差做偏移，玻璃与冰按折射方向投影到屏幕。
vec2 ogxWaterRefractionCoord(bool isWater, vec3 normal, vec3 viewPos, vec3 waveNormal,
    mat3 modelView, mat4 projection, float waterDeep, float waterDist, vec2 screenInput)
{
    vec2 coord = screenInput; // 默认不变，返回原屏幕坐标。
    if (isWater) // 水面：用波法线与平水面法线的差做偏移。
    {
        vec3 waveView = normalize(ogxMatrix3MulPoint(modelView, waveNormal)); // 波法线转到视空间。
        vec3 flatView = normalize(ogxMatrix3MulPoint(modelView, vec3(0.0, 1.0, 0.0))); // 平水面法线转到视空间。
        coord = flatView.xy - waveView.xy; // 两种法线的差就是偏移方向。
        coord *= ogxSaturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深偏得越远，远处收敛到零。
        coord += screenInput; // 叠到原坐标上。
    }
    else // 玻璃与冰：按折射方向投影到屏幕。
    {
        vec3 direction = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
        direction /= ogxSaturate(dot(direction, -normal)); // 归一化到视线方向，避免分母让角度爆炸。
        direction *= ogxSaturate(waterDeep * 2.0) * 0.125; // 按深度缩放。
        vec4 position = ogxMatrixMul(projection, vec4(viewPos + direction, 0.0)); // 投影到裁剪空间。
        coord = position.xy / position.w * 0.5 + 0.5; // 转到屏幕坐标。
    }
    return coord; // 返回采样用的屏幕坐标。
}

// 水洼覆盖：只有湿度超过噪声阈值的地方才积水，五次方让边缘收得很快。
float ogxPuddleCoverage(float halfWet, float noise, float size)
{
    float puddles = max(halfWet - noise, 0.0); // 只算湿度超过噪声阈值的部分。
    puddles = clamp(halfWet - exp(-25.0 * puddles * puddles * puddles * puddles * puddles * size), 0.0, 1.0); // 指数衰减得到积水比例。
    return puddles; // 返回零到一的积水覆盖。
}

// 降水高光：三层噪声叠出雨点打在物体表面的细碎高光。
float ogxRainSpecular(vec3 pos, sampler2D noiseTexture)
{
    pos.y *= 0.2; // 压扁竖直方向，让高光沿竖直变化更慢。
    float n = 0.0; // 累积噪声。
    n += ogxFogNoise(pos, noiseTexture); // 第一层。
    n += ogxFogNoise(pos * 0.5, noiseTexture) * 2.0; // 第二层，缩小坐标并放大权重。
    n += ogxFogNoise(pos * 0.25, noiseTexture) * 4.0; // 第三层，更细的权重更高。
    n /= 7.0; // 平均到零到一。
    return clamp(n, 0.0, 1.0) * 0.7 + 0.3; // 留一个下限，避免完全没有高光。
}

// 水体雾：把水下的吸收、散射与全反射合成一段颜色，再按可见度混回场景。
vec3 ogxWaterFog(vec3 color, vec3 viewDir, float opaqueDist, float waterDist, vec3 normal,
    float ice, float stainedGlass, float hand, float occludedWater, float waterSkylight, float totalInternal,
    vec3 lightDir, vec3 lightColor, vec3 skyColor, vec3 upView, float eyeWaterDepth, float wetness,
    float refractIor, float fogDensityOption, bool underwater)
{
    float distDiff = opaqueDist - waterDist; // 水面到水底的真实距离。
    waterDist = underwater ? mix(waterDist, opaqueDist, stainedGlass) : mix(distDiff, min(distDiff * 0.3, 6.0), occludedWater); // 按遮挡与玻璃修正厚度。
    waterDist = max(waterDist, totalInternal * eyeWaterDepth * 50.0); // 全反射时按眼睛水深拉长光程。
    vec3 shadowRefracted = refract(-lightDir, upView, 1.0 / refractIor); // 太阳经过水面的折射方向。
    vec3 fogColor = mix(vec3(0.05, 0.6, 1.0), vec3(0.3, 0.9, 1.5), ice); // 冰偏青，普通水偏蓝。
    fogColor = mix(fogColor, vec3(0.5), wetness * 0.6); // 越湿颜色越灰。
    fogColor *= dot(vec3(0.33333), skyColor); // 水雾颜色随环境色变化。
    if (!underwater) // 水面之上看水下。
    {
        fogColor *= 0.04 - wetness * 0.032; // 水面之上的散射只占很小一部分。
        fogColor *= waterSkylight; // 再乘该处水面的天光。
        vec3 l = normalize(reflect(viewDir, normal)); // 视线在水面的反射方向。
        vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
        float fresnel = ogxSaturate(dot(normal, l)) * ogxSaturate(dot(l, h) * 1.5 - 0.5); // 简化的反射权重。
        float scatter = 3.0 * fresnel * pow(dot(shadowRefracted, viewDir) * 5.0 + 5.2, -1.4); // 逆光时的散射强度。
        fogColor = mix(fogColor, lightColor * fogColor * 3.0, scatter * ogxSaturate(1.0 - wetness - occludedWater)); // 按散射叠进光色。
    }
    else // 眼睛在水里。
    {
        fogColor *= 0.02 - wetness * 0.012; // 水下的散射更暗。
        float scatter = 1.0 / (dot(shadowRefracted, viewDir) * 5.0 + 5.1); // 水下的前向散射。
        vec3 sunScatter = lightColor * scatter * fogColor * 2.0; // 太阳在水下的散射色。
        fogColor *= dot(viewDir, upView) * 0.4 + 0.6; // 向上看更亮。
        fogColor += sunScatter * (eyeWaterDepth * (1.0 - wetness * 0.6)); // 加上太阳散射。
    }
    float density = underwater ? ice * 0.96 + 0.04 : 0.29; // 水下密度更高。
    float visibility = exp2(-waterDist * density * fogDensityOption); // 按光程指数衰减得到可见度。
    visibility = clamp(visibility, 0.35 * ice, 1.0); // 冰给出一个可见度下限。
    visibility = mix(visibility, 0.7, hand); // 手里的东西只受轻微影响。
    vec3 attenuation = underwater ? vec3(0.1, 0.6, 1.0) : vec3(0.2, 0.5, 0.7); // 分通道衰减色，水底偏蓝。
    color *= pow(attenuation * 0.99, vec3(waterDist * (0.21 * float(!underwater) + 0.04) * fogDensityOption)); // 按光程衰减，长波先掉。
    return mix(fogColor, color, visibility); // 用可见度在水雾色与场景色之间混合。
}

// 雨点动画法线：读一张雨点动画贴图并转成带符号的法线，指数控制边缘锐度。
// 只取红绿两通道：这张贴图存的是法线的横纵分量，蓝色在写入端舍弃。
vec2 ogxRainAnimationNormal(sampler2D rainTexture, vec2 coord, float exponent)
{
    vec2 n = textureLod(rainTexture, coord, 0.0).rg; // 读红绿两通道。
    n = n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 零到一转成负一到一，并翻转纵轴。
    n = pow(abs(n), vec2(exponent)) * sign(n); // 按指数压形状，符号保留。
    return n; // 返回法线横纵分量。
}

// 波法线方块读取：把世界位置按折射方向投到七号画面左下角的波法线方块，解出世界空间法线。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
vec3 ogxWavesNormalFromTex(vec3 position, vec3 lightDir, sampler2D normalTexture, vec2 pixelSize,
    vec2 screenExtent, float maxResolution, float refractIor)
{
    vec3 refracted = refract(lightDir, vec3(0.0, 1.0, 0.0), 1.0 / refractIor); // 阳光按水面折射率弯折。
    vec2 coord = position.xz; // 先取水平坐标。
    coord.x += position.y * refracted.x / refracted.y; // 按高度沿光线横移横坐标。
    coord.y += position.y * refracted.z / refracted.y; // 按高度沿光线横移纵坐标。
    coord *= 0.02; // 缩到波法线图的空间尺度。
    coord = fract(coord); // 平铺到零到一。
    coord *= pixelSize * min(screenExtent.y, maxResolution); // 折算成方块里的像素坐标。
    return ogxDecodeNormal(textureLod(normalTexture, coord, 0.0).xy); // 从方块里读八面体编码法线。
}

// 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
// `cameraOffset` 用来还原绝对世界坐标，`underwater` 决定是否往全亮靠。
float ogxWaterCaustics(vec3 worldPos, vec3 lightDir, vec3 cameraOffset, sampler2D normalTexture,
    vec2 pixelSize, vec2 screenExtent, float maxResolution, float refractIor, vec2 dither,
    bool underwater, float brightness, float power)
{
    vec3 position = worldPos + cameraOffset; // 换成绝对世界坐标。
    vec3 lookupCenter = position + vec3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。
    float caustics = 0.0; // 累计焦散强度。
    for (float i = -1.0; i <= 1.0; i++) // 三乘三抖动采样。
    {
        for (float j = -1.0; j <= 1.0; j++)
        {
            vec2 offset = dither + vec2(i, j); // 当前采样偏移。
            vec3 lookupPoint = lookupCenter; // 这一处的波面查询点。
            lookupPoint.xz += offset * 0.1; // 按偏移横移。
            vec3 wavesNormal = ogxWavesNormalFromTex(lookupPoint, lightDir, normalTexture, pixelSize,
                screenExtent, maxResolution, refractIor).xzy; // 读取波法线并换到竖直轴朝上的坐标。
            vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
            vec3 collision = lookupPoint - refractVector / refractVector.y; // 光线与水平面的交点。
            collision -= position; // 相对当前位置。
            float dist = dot(collision, collision) * 7.1; // 交点距离的平方，放大差距。
            caustics += 1.0 - ogxSaturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
        }
    }
    float finalCaustics = mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(underwater)); // 拼成焦散亮度，水下再往全亮靠一点。
    return pow(finalCaustics * brightness, power); // 按亮度倍率与对比指数重整。
}

// 迭代正弦海洋的参数：换水体只改字段，不必再抄一遍循环。
// 这些数就是 iterationT 海洋扩展的取值，举个例子：每层频率乘一点一八、权重乘零点八，
// 于是低频波大而慢、高频波小而快，叠出来才是海面而不是规则条纹。
struct OgxOceanWaves
{
    int iterations; // 叠几层波形，层数越多越细也越贵。
    float drag; // 每层把采样点往波前进方向拖多少，形成剪切与卷曲。
    float timeScale; // 时间缩放，让相位推进速度跟上原程序。
    float detail; // 细节权重指数，只影响累加出来的方向。
    float frequency; // 起始频率。
    float speed; // 起始相位速度。
    float weightFalloff; // 每层权重衰减，越高越偏向低频波。
    float frequencyGain; // 每层频率放大。
    float speedGain; // 每层相位速度放大。
    float angleStep; // 每层方向角增量，让各层方向错开。
};

// 默认参数：iterationT 海洋扩展的常数，调用方只改真正要变的那几个字段。
OgxOceanWaves ogxOceanWavesDefault()
{
    OgxOceanWaves waves;
    waves.iterations = 13; // 层数的基础值，原程序的迭代偏移量。
    waves.drag = 0.048; // 拖拽量小一点，避免波形自己卷起来。
    waves.timeScale = 0.45; // 时间放慢，海面起伏看起来更沉。
    waves.detail = 0.75; // 细节指数，原程序取值。
    waves.frequency = 6.0; // 起始频率。
    waves.speed = 2.0; // 起始相位速度。
    waves.weightFalloff = 0.8; // 每层权重乘零点八，低频占主导。
    waves.frequencyGain = 1.18; // 每层频率乘一点一八。
    waves.speedGain = 1.07; // 每层速度乘一点零七。
    waves.angleStep = 12.0; // 每层方向转十二弧度，等效于错开一圈多，视觉上方向不重复。
    return waves;
}

// 逐层叠加的结果：都是未归一化的和，调用方按自己的用法再除权重和。
struct OgxOceanWaveSum
{
    float height; // 波高和，未除权重。
    float weightSum; // 权重和，用来归一化。
    vec2 detail; // 按细节指数累加的方向，泡沫与法线要用。
    vec2 position; // 被波形拖拽后的采样点。
};

// 迭代正弦：每层的频率、速度都放大，权重衰减，采样点被波形拖着走。
// 为什么方向累加也放在同一个循环里：一处调用只取波高、另一处还要方向，
// 多算一次加法不影响波高，却省掉第二份一模一样的循环，两边不会再各自漂移。
OgxOceanWaveSum ogxOceanWaveSum(vec2 position, float time, OgxOceanWaves waves)
{
    float iter = 0.0; // 每层方向角。
    float frequency = waves.frequency; // 当前层频率。
    float speed = waves.speed; // 当前层速度。
    float weight = 1.0; // 当前层权重，从一整份开始衰减。
    float height = 0.0; // 累加波高。
    float weightSum = 0.0; // 累加权重。
    vec2 detail = vec2(0.0); // 累加方向。
    float modifiedTime = time * waves.timeScale; // 缩放后的时间。
    for (int i = 0; i < waves.iterations; i++) // 逐层叠加。
    {
        vec2 direction = vec2(sin(iter), cos(iter)); // 当前层方向。
        float x = dot(direction, position) * frequency + modifiedTime * speed; // 当前层的相位。
        float wave = exp(sin(x) - 1.0); // 波峰更尖的包络，海面才有尖顶。
        float result = wave * cos(x); // 波形值。
        vec2 force = result * weight * direction; // 对采样点的拖拽力。
        detail += force / pow(weight, waves.detail); // 权重越小的层贡献越大，细节层因此不会被低频淹没。
        position -= force * waves.drag; // 采样点被拖拽，形成剪切。
        height += wave * weight; // 累加波高。
        iter += waves.angleStep; // 方向角前进。
        weightSum += weight; // 累加权重。
        weight *= waves.weightFalloff; // 权重衰减。
        frequency *= waves.frequencyGain; // 频率放大。
        speed *= waves.speedGain; // 速度放大。
    }
    OgxOceanWaveSum sum;
    sum.height = height; // 交回未归一化的波高。
    sum.weightSum = weightSum; // 交回权重和。
    sum.detail = detail; // 交回方向累加。
    sum.position = position; // 交回拖拽后的位置。
    return sum;
}

// 归一化波高并按海面高度缩放、居中：两处调用共用这一条换算式。
float ogxOceanWaveHeight(OgxOceanWaveSum sum, float oceanHeight, float factor)
{
    return sum.height / sum.weightSum * oceanHeight * factor - oceanHeight * factor * 0.5; // 居中让海面在基准高度上下对称。
}

// 波形空间：把世界水平坐标按原点偏移与横向缩放换成迭代正弦使用的坐标。
// 为什么单独成一个函数：波高、方向与像素数据必须用同一个空间，三处各写一遍迟早会漂移。
vec2 ogxOceanWaveSpace(vec2 position, vec2 offset, float xzScale, float horizontalScale)
{
    return (position - offset) * xzScale * horizontalScale; // 先减原点再乘两级缩放。
}

// 海洋波方向：把逐层累加的方向除以权重和，取负后指向波前进方向。
vec2 ogxOceanWaveDirection(OgxOceanWaveSum sum, float detailWeight)
{
    return -sum.detail / pow(sum.weightSum, 1.0 - detailWeight); // 与参考实现的归一化逐项相同。
}

// 海洋波形法线：横纵方向乘上海面高度与波高倍率，再补一个固定的竖直强度。
vec3 ogxOceanWaveNormal(vec2 direction, float oceanHeight, float factor, float normalStrength)
{
    float oceanHeightFactor = oceanHeight / 13.0; // 海面高度相对基础值十三的倍率。
    float totalFactor = oceanHeightFactor * factor; // 总倍率。
    return normalize(vec3(direction.x * totalFactor, normalStrength, direction.y * totalFactor)); // 由方向构造法线。
}

// 波形法线与涟漪法线的混合：涟漪越强，法线越偏向贴图给出的细节。
// `totalEffect` 是四邻高度和，开方后作为混合权重，照参考实现。
vec3 ogxOceanNormalWithRipple(vec2 position, vec2 direction, float factor, float oceanHeight, float normalStrength,
    vec2 modelOffset, sampler2D rippleTexture, float rippleRange, vec2 texel)
{
    vec3 waveNormal = ogxOceanWaveNormal(direction, oceanHeight, factor, normalStrength); // 先算波形法线。
    vec2 eyePosition = position + modelOffset; // 加上模型偏移，定位涟漪。
    vec2 fetch = (eyePosition + vec2(rippleRange, rippleRange)) / (rippleRange * 2.0); // 涟漪贴图坐标。
    float left = textureLod(rippleTexture, fetch - vec2(texel.x, 0.0), 0.0).r; // 左侧高度。
    float right = textureLod(rippleTexture, fetch + vec2(texel.x, 0.0), 0.0).r; // 右侧高度。
    float top = textureLod(rippleTexture, fetch - vec2(0.0, texel.x), 0.0).r; // 上侧高度。
    float bottom = textureLod(rippleTexture, fetch + vec2(0.0, texel.x), 0.0).r; // 下侧高度。
    float totalEffect = left + right + top + bottom; // 四邻合计。
    vec3 rippleNormal = normalize(vec3(left - right, 1.0, top - bottom)); // 涟漪法线。
    return normalize(mix(waveNormal, rippleNormal, pow(totalEffect, 0.5))); // 按涟漪强度混合。
}

// 海洋泡沫：三层三维噪声相乘得到泡沫形状，再按波峰高度与细胞噪声调制。
// `waveAmplitude` 是已经乘过法线竖直分量的波峰振幅，函数只负责把它夹到零到一。
float ogxOceanFoam(sampler3D foamTexture, vec2 waterUV, float time, float foamAmount, float foamOpacity,
    float waveAmplitude)
{
    vec2 s1 = textureLod(foamTexture, vec3(waterUV * 0.26, time / 360.0), 0.0).rg; // 第一层泡沫噪声。
    vec2 s2 = textureLod(foamTexture, vec3(waterUV * 0.02, time / 360.0 + 0.5), 0.0).rg; // 第二层。
    vec2 s3 = textureLod(foamTexture, vec3(waterUV * 0.1, time / 360.0 + 1.0), 0.0).rg; // 第三层。
    float surfaceNoise = s1.r * s2.r * s3.r * 2.8 * foamAmount; // 三层相乘得到泡沫形状。
    waveAmplitude = clamp(waveAmplitude * 1.2, 0.0, 1.0); // 波峰处的振幅。
    surfaceNoise = (1.0 - waveAmplitude) * surfaceNoise + waveAmplitude * foamAmount; // 波峰处泡沫更强。
    float worleyNoise = 0.2 + 0.8 * s1.g * (1.0 - s2.g); // 细胞状调制。
    surfaceNoise = smoothstep(0.45, 1.0, surfaceNoise) * worleyNoise; // 阈值平滑并乘调制。
    return clamp(2.0 * surfaceNoise * foamOpacity, 0.0, 1.0); // 乘不透明度得到最终泡沫。
}

// 海面像素：一次算出方向、还原位置、法线、泡沫与波高，片元阶段只取一次。
struct OgxOceanPixel
{
    vec2 direction; // 波形方向。
    vec2 worldPos; // 还原后的世界位置。
    vec3 normal; // 混合涟漪后的法线。
    float foam; // 泡沫强度。
    float height; // 波高。
};

// 完整海面像素：把波形迭代、空间换算、涟漪贴图与泡沫噪声放在同一处，宿主只传数据。
// `texel` 是涟漪贴图的横向纹素大小；`iterations` 是浮点层数，内部向上取整，与参考实现一致。
OgxOceanPixel ogxOceanPixel(vec2 position, float factor, float iterations, float time,
    vec2 waveOffset, float xzScale, float horizontalScale, float oceanHeight, vec2 modelOffset,
    sampler2D rippleTexture, float rippleRange, vec2 texel,
    sampler3D foamTexture, float globalTime, float foamAmount, float foamOpacity, float normalStrength)
{
    vec2 wavePos = ogxOceanWaveSpace(position, waveOffset, xzScale, horizontalScale); // 换到波形空间。
    OgxOceanWaves waves = ogxOceanWavesDefault(); // 参考实现的默认常数。
    waves.iterations = int(ceil(iterations)); // 层数向上取整，与原来的整数比较等价。
    OgxOceanWaveSum sum = ogxOceanWaveSum(wavePos, time, waves); // 逐层累加。
    OgxOceanPixel pixel; // 待填充。
    pixel.direction = ogxOceanWaveDirection(sum, waves.detail); // 波形方向。
    pixel.worldPos = sum.position / horizontalScale / xzScale; // 还原世界位置。
    pixel.height = ogxOceanWaveHeight(sum, oceanHeight, factor); // 归一化波高。
    pixel.normal = ogxOceanNormalWithRipple(position, pixel.direction, factor, oceanHeight, normalStrength,
        modelOffset, rippleTexture, rippleRange, texel); // 波形法线混入涟漪。
    float waveAmplitude = pixel.height * pow(max(pixel.normal.y, 0.0), 4.0); // 波峰振幅。
    vec2 waterUV = mix(position - waveOffset, pixel.worldPos, clamp(factor * 2.0, 0.2, 1.0)); // 泡沫坐标在原始与波后位置间混合。
    pixel.foam = ogxOceanFoam(foamTexture, waterUV, globalTime, foamAmount, foamOpacity, waveAmplitude); // 泡沫强度。
    return pixel; // 交回完整数据。
}

// 涟漪专用标量哈希：与 Eclipse `ripples.glsl` 的 `hash12` 保持同一组常数。
// 为什么不用噪声模块的 `ogxHash12`：那个哈希混入了另一组偏移，值噪声依赖它；涟漪要照原图逐项复现，不能换。
float ogxRippleHash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 19.19); // 三个分量互相混合。
    return fract((p3.x + p3.y) * p3.z); // 取小数部分。
}

// Eclipse 雨点涟漪：九个格子的雨滴各自扩散出圆环，取梯度得到法线。
// `intensity` 控制每格大小，`time` 是累积秒数；九个方向相加后归一，结果与参考实现相同。
vec3 ogxRainRipples(vec2 fragCoord, float time, float intensity)
{
    float cellDensity = 5.0 * intensity; // 每米几个雨点。
    float sizeCompensation = cellDensity / 5.0; // 密度改变时补偿圆环半径。
    vec2 uv = fragCoord * cellDensity; // 换到格子坐标。
    vec2 p0 = floor(uv); // 当前格子。
    vec2 circles = vec2(0.0); // 累加梯度。
    for (int j = -1; j <= 1; j++) // 三乘三邻格。
    {
        for (int i = -1; i <= 1; i++)
        {
            vec2 pi = p0 + vec2(float(i), float(j)); // 邻格坐标。
            vec2 p = pi + ogxHash22(pi); // 雨点落在格内随机位置。
            float t = fract(0.9 * time + ogxRippleHash12(pi)); // 这一滴的扩散相位。
            vec2 v = p - uv; // 从雨点到当前像素。
            float d = length(v) - 2.0 * t * sizeCompensation; // 圆环半径随时间扩大。
            float d1 = d - 0.01; // 前后两个采样点。
            float d2 = d + 0.01;
            float p1 = sin(21.0 * d1) * smoothstep(-0.6, -0.3, d1) * (1.0 - smoothstep(-0.3, 0.0, d1)); // 前一点的高度。
            float p2 = sin(21.0 * d2) * smoothstep(-0.6, -0.3, d2) * (1.0 - smoothstep(-0.3, 0.0, d2)); // 后一点的高度。
            circles += 0.5 * normalize(v) * ((p2 - p1) / 0.02 * (1.0 - t) * (1.0 - t)); // 中心差分得到坡度。
        }
    }
    circles /= 9.0; // 九个方向取平均。
    return vec3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0))); // 参考实现不做归一化，保持原幅度。
}

// Eclipse 水面焦散：沿太阳方向把水面位置投到水底，用噪声图三层旋转采样得到汇聚花纹。
// `time` 是累积秒数，`waveSpeed` 与 `patchyBlend` 是水面选项，噪声图由调用方给出。
float ogxWaterBumpCaustics(vec3 worldPos, vec3 sunVec, float surfacePos, float time, float waveSpeed,
    float patchyBlend, sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    vec2 projected = worldPos.xz + (sunVec.xz / abs(sunVec.y)) * surfacePos; // 沿阳光投到水底。
    vec2 pos = projected; // 当前采样坐标。
    float largeWaves = textureLod(noiseTexture, pos / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = mix(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float heightSum = 0.0; // 三层高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    vec2 rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    float sample0 = textureLod(noiseTexture, pos / vec2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层，横向拉长。
    heightSum += pow(abs(abs(sample0 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 折线整形后累加。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    float sample1 = textureLod(noiseTexture, pos / vec2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层，纵向拉长。
    heightSum += pow(abs(abs(sample1 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第二层。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    float sample2 = textureLod(noiseTexture, pos / vec2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层，正方形。
    heightSum += pow(abs(abs(sample2 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第三层。
    return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5)); // 汇聚成焦散亮度。
}

// Eclipse 水面高度：三层噪声按旋转叠加，再乘大波曲线。
float ogxWaterBumpHeightmap(vec2 position, float largeWavesCurved, float time, float waveSpeed, sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    vec2 pos = position; // 当前采样坐标。
    float heightSum = 0.0; // 高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    vec2 rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层高度。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层高度。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层高度。
    return (heightSum / 4.5) * max(largeWavesCurved, 0.3); // 归一化并留一个下限。
}

// Eclipse 水面法线：中心与横纵两个邻点的高度差构成法线，采样距离随距离与画质变化。
vec3 ogxWaterBumpNormal(vec3 waterPos, vec3 playerPos, float time, float waveSpeed, float patchyBlend,
    float wavesARadius, float wavesBRadius, bool hyperDetailed, sampler2D noiseTexture)
{
    float largeWaves = textureLod(noiseTexture, waterPos.xy / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = mix(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float deltaPos = 0.025; // 超高质量用固定小步长。
    if (!hyperDetailed) // 普通质量按大波曲线与距离选步长。
    {
        deltaPos = mix(wavesARadius, wavesBRadius, largeWavesCurved); // 两个半径之间插值。
        deltaPos += min(length(playerPos) / (16.0 * 24.0), 3.0); // 远处加大步长，减少闪烁。
    }
    float h0 = ogxWaterBumpHeightmap(waterPos.xy, largeWavesCurved, time, waveSpeed, noiseTexture); // 中心高度。
    float h1 = ogxWaterBumpHeightmap(waterPos.xy + vec2(deltaPos, 0.0), largeWavesCurved, time, waveSpeed, noiseTexture); // 横向邻点。
    float h3 = ogxWaterBumpHeightmap(waterPos.xy + vec2(0.0, deltaPos), largeWavesCurved, time, waveSpeed, noiseTexture); // 纵向邻点。
    float xDelta = (h1 - h0) / deltaPos; // 横向坡度。
    float yDelta = (h3 - h0) / deltaPos; // 纵向坡度。
    return normalize(vec3(xDelta, yDelta, 1.0 - pow(abs(xDelta + yDelta), 2.0))); // 高度场法线。
}

#endif

/*
生成文件：雾模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库雾模块：高度衰减、噪声雾团、粉末效应、混合相位与沿视线积分。
调用位置：地形、水面与低空空气的雾；Minecraft 光影由 `/omni-gfx/fog.glsl` 引入。
可复制示例：
    OgxFog f = ogxFogDefault(); // 取默认雾。
    vec4 r = ogxFogMarch(f, camKm, worldKm, sunDir, sunColor, j, 10); // 沿视线积分雾。
    c = ogxFogApply(c, r); // 把雾合成到颜色。
设计原因与取舍：
    密度剖面与相位来自旧 `shaders/gfx/fog.glsl` 的 `gfx_fog_density_height`、`gfx_fog_density_noise`
    与 `gfx_fog_phase`，把纹理噪声换成程序化值噪声，保持雾团边缘与高度衰减的手感。
    步数与抖动由调用方给出，库不读取天气、选项或宿主时间；返回预乘散射色与剩余透过率，
    调用方按自己的混合顺序合成，避免和大气散射重复叠加。
*/
#ifndef OGX_FOG_INCLUDED
#define OGX_FOG_INCLUDED

// 数学提供相函数，噪声提供雾团形状。


// 一层低空雾的参数；不同群系或天气换字段即可。
struct OgxFog
{
    vec3 color; // 雾的环境色，线性空间。
    float density; // 基础高度处的密度，每公里。
    float heightFalloff; // 离开基础高度后的衰减距离，公里。
    float baseHeight; // 最浓的高度，公里。
    float noiseScale; // 雾团的水平尺度，每公里。
    float noiseStrength; // 噪声对密度的调制强度，零到一。
    vec3 wind; // 水平风向，公里。
    float sunStrength; // 阳光在雾里的散射强度。
};

// 默认低空雾：贴地薄雾，密度适中，云影下会自然变暗。
OgxFog ogxFogDefault()
{
    OgxFog fog; // 先声明再填写字段。
    fog.color = vec3(0.55, 0.68, 0.82); // 偏冷的天空色。
    fog.density = 0.18; // 每公里密度，远景能看到空气感。
    fog.heightFalloff = 0.06; // 六十米高度衰减，雾贴在低空。
    fog.baseHeight = 0.0; // 海平面最浓。
    fog.noiseScale = 9.0; // 百米级雾团。
    fog.noiseStrength = 0.75; // 噪声明显但不把雾打碎。
    fog.wind = vec3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    fog.sunStrength = 1.0; // 阳光散射默认全强。
    return fog; // 返回可直接修改的默认值。
}

// 雾密度：高度指数衰减乘三维噪声，得到会流动的雾团。
float ogxFogDensity(OgxFog fog, vec3 position)
{
    float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
    vec3 noisePosition = (position + fog.wind) * fog.noiseScale; // 换到雾坐标并叠加风。
    float noise = ogxFbm3(noisePosition, 3); // 三层次雾团。
    return fog.density * height * mix(1.0, noise * 1.6, ogxSaturate(fog.noiseStrength)); // 噪声只调制密度，不改变高度剖面。
}

// 混合相位：三成后向、七成前向，逆光和顺光都不会过曝。
float ogxFogPhase(float nu)
{
    return ogxMiePhase(-0.4, nu) * 0.3 + ogxMiePhase(0.5, nu) * 0.7; // 与旧雾模块相同的权重。
}

// 粉末效应：薄雾在背光方向略微增亮，模拟多次散射。
float ogxFogPowder(float density, float nu)
{
    float powder = 1.0 - exp(-max(density, 0.0) * 4.0); // 密度越低越明显。
    return mix(1.0, powder, ogxSaturate(0.5 - 0.5 * nu)); // 只影响背光方向。
}

// 沿视线积分雾：返回预乘散射色与剩余透过率。
vec4 ogxFogMarch(OgxFog fog, vec3 camera, vec3 worldPosition, vec3 sunDirection,
                   vec3 sunColor, float jitter, int steps)
{
    vec3 delta = worldPosition - camera; // 相机到目标点的向量。
    float distance = length(delta); // 视线长度，公里。
    if (distance <= 1e-5) // 零长度不产生雾。
    {
        return vec4(0.0, 0.0, 0.0, 1.0); // 完全透明。
    }
    vec3 viewDirection = delta / distance; // 单位视线方向。
    const int maxSteps = 24; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = distance / float(count); // 每步长度。
    float distanceAlongRay = stepLength * ogxSaturate(jitter); // 抖动起点，减少层状条纹。
    float transmittance = 1.0; // 初始完全透明。
    vec3 scattered = vec3(0.0); // 累积散射光。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    float phase = ogxFogPhase(nu); // 混合相位。
    for (int i = 0; i < maxSteps; i++) // 逐步穿过雾层。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        vec3 position = camera + viewDirection * distanceAlongRay; // 当前采样点。
        float density = ogxFogDensity(fog, position); // 当前密度。
        if (density > 0.001) // 空区域跳过。
        {
            float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
            float powder = ogxFogPowder(density, nu); // 薄雾的多次散射。
            vec3 sun = sunColor * fog.sunStrength * (phase * 2.0 + 0.15) * height * powder; // 阳光散射。
            vec3 ambient = fog.color * (0.30 + 0.70 * height); // 环境光。
            float extinction = exp(-density * stepLength * 1.2); // 这一段的透过率。
            scattered += (sun + ambient) * transmittance * (1.0 - extinction); // 按剩余透过率累加。
            transmittance *= extinction; // 更新透过率。
        }
        distanceAlongRay += stepLength; // 前进一段。
        if (transmittance < 0.02) // 几乎不透明就不再采样。
        {
            break; // 提前结束。
        }
    }
    return vec4(scattered, transmittance); // 返回预乘散射色与剩余透过率。
}

// 把雾应用到已经着色的颜色：先乘剩余透过率，再加散射色。
vec3 ogxFogApply(vec3 color, vec4 fog)
{
    return color * fog.a + fog.rgb; // 预乘散射色直接相加。
}

// 按比例淡出一层预乘雾：只缩放散射色，并把透过率朝一插值。
// 为什么不能直接把四个分量一起乘小：透过率被乘小以后，颜色会被一起抹掉，
// 在“远处收敛到天空色、同时淡出雾”的接缝处就会压出一条黑线。
// `amount` 零表示完全不要这层雾，一表示保留原样。
vec4 ogxFogFade(vec4 fog, float amount)
{
    amount = ogxSaturate(amount); // 比例夹在零到一。
    return vec4(fog.rgb * amount, mix(1.0, fog.a, amount)); // 散射按比例缩放，透过率朝完全透明靠近。
}

// 粉末效应：背光时气溶胶把光往前推，边缘因此更亮，正对时补偿回去。
float ogxLegacyPowder(float absorption, float lightingAbsorption, float VdotL)
{
    return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越强效果越强。
}

// 混合相位：后向与前向两个米氏相位加权，雾的轮廓在逆光时仍有层次。
float ogxLegacyFogPhase(float VdotL)
{
    return ogxMiePhase(-0.4, VdotL) * 0.3 + ogxMiePhase(0.5, VdotL) * 0.7; // 前向占七成。
}

// 多次散射相位：四个衰减档各给一个相位，用来叠出体积雾的多层散射。
// 返回四分量的原因是 GLSL 的数组参数在 Slang 里没有等价写法，四档直接装进一个向量。
vec4 ogxMultiScatteringPhases(float VdotL)
{
    return vec4(ogxLegacyFogPhase(VdotL), ogxLegacyFogPhase(VdotL * 0.5),
                  ogxLegacyFogPhase(VdotL * 0.25), ogxLegacyFogPhase(VdotL * 0.125)); // 四档角度逐次减半，与旧实现的循环一致。
}

// 雾密度的高度剖面：两层高度之间的空气最浓，离开这段距离按指数下降，夜间更浓。
float ogxFogDensityHeight(vec3 fogPos, float heightA, float heightB, float falloff, float timeMidnight)
{
    float maxHeight = max(heightA, heightB); // 两层里较高的。
    float minHeight = min(heightA, heightB); // 两层里较低的。
    float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到浓度层的距离。
    dh *= 2.0 / falloff; // 按衰减距离归一化。
    float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢。
    return density * 0.1; // 乘基础密度。
}

// 噪声雾密度：高度包络乘四层噪声，平方两次让雾团边界清楚。
float ogxFogDensityNoise(vec3 fogPos, vec3 wind, float heightA, float heightB, float falloff,
    float timeMidnight, sampler2D noiseTexture)
{
    float dh = abs(fogPos.y - max(heightA, heightB)); // 到浓度层的距离。
    dh *= 1.0 / falloff; // 按衰减距离归一化。
    float envelope = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
    float density = 0.0; // 累积的雾密度。
    fogPos = fogPos * 0.02 + wind; // 缩放坐标并叠加风向。
    for (float alpha = 0.5; alpha >= 0.125; alpha *= 0.5) // 四层不同频率的噪声。
    {
        density += alpha * ogxFogNoise(fogPos, noiseTexture); // 按权重累加。
        fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
    }
    density *= envelope; // 乘高度衰减。
    density = density * density; // 平方让雾团更实。
    return density * density * 3.0; // 再平方并放大，得到清楚的边界。
}

// 三维噪声：把世界坐标折成三维格子，再用一张二维噪声图的上下两层按高度插值。
// 为什么能这样降维：噪声图本身是二维的，用格子的纵坐标错开贴图里的一行，
// 再把两个通道当成上下两层，就能在不增加纹理的情况下得到三维手感。
float ogxEnd3dNoise(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    vec3 p = floor(position); // 整数格决定用贴图哪一块。
    vec3 b = fract(position); // 格内偏移用于插值。
    b = b * b * (3.0 - 2.0 * b); // 三次平滑，格与格之间不出现硬边。
    vec2 uv = 17.0 * p.z + p.xy + b.xy; // 把三层格子压到二维坐标，十七是原程序打散层数的常数。
    vec2 rg = textureLod(noiseTexture, (uv + 0.5) / noiseResolution, 0.0).zx; // 取两张通道，零号层级与原来的即时采样一致。
    return mix(rg.x, rg.y, b.z); // 按格内高度在两层之间插值。
}

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
// `shift` 是每层之间的时间位移，让细节缓慢流动而不是整块平移。
float ogxCloudFbm(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution)
{
    const int octaves = 4; // 四层就够，再多在远景里看不出来。
    const float octAlpha = 0.87; // 每层权重只衰减一成多，细节保留得多。
    const float octScale = 2.5; // 每层频率放大二点五倍，避免相邻层太像。
    const float octShift = (octAlpha / octScale) / float(octaves); // 层间偏移，把结果抬回零附近。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 第一层权重。
    for (int i = 0; i < octaves; i++) // 逐层叠加。
    {
        accum += alpha * ogxEnd3dNoise(position, noiseTexture, noiseResolution); // 加这一层。
        position = (position + shift) * octScale; // 抬高频率并错开时间。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift; // 返回归一化后的噪声。
}

// 云状分形噪声的低质量版本：三层、每层权重衰减零点九、频率乘二，供远景或低画质使用。
// 与 `ogxCloudFbm` 分开保留，因为层数和衰减常数不同，不能用一个参数偷偷替换参考路径。
float ogxCloudFbmLq(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution)
{
    const int octaves = 3; // 三层。
    const float octAlpha = 0.9; // 每层权重衰减。
    const float octScale = 2.0; // 每层频率倍数。
    const float octShift = (octAlpha / octScale) / float(octaves); // 层间偏移。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 第一层权重。
    for (int i = 0; i < octaves; i++) // 逐层叠加。
    {
        accum += alpha * ogxEnd3dNoise(position, noiseTexture, noiseResolution); // 加这一层。
        position = (position + shift) * octScale; // 抬高频率并错开时间。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift; // 返回归一化后的噪声。
}

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float ogxNetherFogDensityAt(vec3 pos, sampler2D noiseTexture)
{
    pos /= 18.0; // 整体缩小，让格子更大。
    pos.xz *= 0.5; // 水平再压一半，雾团更扁。
    vec3 p = floor(pos); // 整数格坐标。
    vec3 f = fract(pos); // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 平滑小数。
    vec2 uv = p.xz + f.xz + p.y * vec2(0.0, 193.0); // 三维格子映射到二维图，纵轴加大偏移错开层。
    vec2 xy = textureLod(noiseTexture, uv / 512.0, 0.0).yx; // 读两通道并交换，零号层级与旧实现一致。
    return mix(xy.r, xy.g, f.y); // 按高度插值。
}

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
// 羽流给竖直烟柱，贴地烟给低处一层，两者取较大者，避免叠加过曝。
float ogxNetherFogCloudVolume(vec3 pos, float time, sampler2D noiseTexture)
{
    vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直拉伸，烟柱显得更高。
    float wind = pow(max(pos.y - 30.0, 0.0) / 15.0, 2.1); // 越高风偏移越大。
    float plumes = textureLod(noiseTexture, (samplePos.xz + wind) / 256.0, 0.0).b; // 噪声蓝通道当羽流形状。
    float floorPlumes = clamp(0.3 - exp(plumes * -6.0), 0.0, 1.0); // 贴地烟的量。
    plumes *= plumes; // 平方拉开烟与空的差别。
    float erosion = ogxNetherFogDensityAt(samplePos * 400.0 - time * 10.0 - wind * 10.0, noiseTexture) * 0.7 + 0.3; // 随时间的侵蚀。
    float roofToFloor = exp(max(100.0 - pos.y, 0.0) / -15.0); // 从天花板到地面变淡。
    float floorFalloff = pow(exp(max(pos.y - 31.0, 0.0) / -3.0), 2.0); // 离地越高越淡。
    return max((roofToFloor - plumes * (1.0 - erosion)) * 2.0, clamp((floorFalloff - floorPlumes * 0.5) * erosion, 0.0, 1.0)); // 两种形状取大者。
}

// 末地涡旋噪声：与下界单格密度同样的降维思路，但贴图边长由调用方给出。
float ogxEndVortexNoise(vec3 pos, sampler2D noiseTexture, float noiseResolution)
{
    pos /= 18.0; // 世界坐标缩到十八分之一，决定颗粒稀密。
    pos.xz *= 0.5; // 水平再压一半，雾团沿竖直拉长。
    vec3 cell = floor(pos); // 所在整数格。
    vec3 f = fract(pos); // 格内偏移。
    f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，格与格之间不出现硬边。
    vec2 uv = cell.xz + f.xz + cell.y * vec2(0.0, 193.0); // 三维到二维的分配，一百九十三打散高度。
    vec2 xy = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 读上下两层并交换通道。
    return mix(xy.r, xy.g, f.y); // 按格内高度插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// 先算旋转后与原始坐标的混合比例，再插值，避免远处雾团被整片拧动。
void ogxEndVortexSwirl(inout vec3 alteredOrigin, vec3 origin, float time)
{
    float radiance = 2.39996 + alteredOrigin.y / 1.5 + time / 50.0; // 旋转角随时间与高度推进。
    float cosine = cos(radiance); // 旋转角的余弦，下面用显式公式代替矩阵。
    float sine = sin(radiance); // 旋转角的正弦。
    vec2 rotated = vec2(cosine * alteredOrigin.x + sine * alteredOrigin.z, cosine * alteredOrigin.z - sine * alteredOrigin.x); // 与旧实现的「行向量乘矩阵」逐项相同。
    float swirlBounds = clamp(sqrt(max(length(vec3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转。
    alteredOrigin.xz = mix(rotated, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void ogxEndVortexBounds(inout float volume, vec3 origin)
{
    vec3 origin2 = origin - vec3(0.0, 100.0, 0.0); // 相对高度一百的中心。
    origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
    float center = length(origin2); // 到中心的距离。
    float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
    float radius = 150.0; // 主岛圆环的半径。
    float thickness = 25.0 * radius; // 圆环判定的厚度尺度，取大得到平缓边缘。
    float torus = (thickness - clamp(pow(length(vec2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
    volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 末地雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float ogxEndVortexShape(vec3 pos, float time, sampler2D noiseTexture, float noiseResolution)
{
    float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距原点三百格内为涡旋核心。
    vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直压扁，得到分层云感。
    float voidZone = max(exp2(-sqrt(max(pos.y + 60.0, 0.0))), 0.0); // 主岛下方六十格起逐渐发白。
    ogxEndVortexSwirl(samplePos, pos, time); // 把采样坐标按漩涡旋转。
    float noise = ogxEndVortexNoise(samplePos * 12.0, noiseTexture, noiseResolution); // 基础噪声决定浓淡。
    float erosion = 1.0 - ogxEndVortexNoise((samplePos - time / 18.0) * (124.0 + (1.0 - noise) * 7.0), noiseTexture, noiseResolution); // 随时间上升的侵蚀噪声。
    float clumpyFog = max(exp(noise * -mix(10.0, 4.0, vortexBounds)) * mix(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
    ogxEndVortexBounds(clumpyFog, pos); // 按体积限制减薄。
    return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float ogxEndVortexLightPhase(vec3 lightPos)
{
    float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一。
    return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
vec3 ogxEndVortexLighting(vec3 startPos, vec3 lightPos, float density, vec3 lightColor, float time, sampler2D noiseTexture, float noiseResolution)
{
    float phase = ogxEndVortexLightPhase(lightPos); // 到光柱中心的相位。
    float shadow = 0.0; // 沿光方向累积的遮挡。
    for (int j = 0; j < 3; j++) // 三步采样雾的遮挡。
    {
        vec3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * 0.25); // 从当前点向光柱中心退回采样。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution); // 累加遮挡。
    }
    vec3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
    lighting += lightColor * phase * phase * (1.0 - exp(-shadow * vec3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
    return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// 步数、步长分布、密度颜色与输出缩放全由参数给出，因为远景开关与画质选项属于宿主。
vec4 ogxEndVortexFog(vec3 cameraPos, vec3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist,
    vec3 vortexColor, vec3 ambientColor, float stormScale, float hazeDensity, float time,
    sampler2D noiseTexture, float noiseResolution, float outputScale)
{
    vec3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
    float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
    float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
    rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
    float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
    vec3 color = vec3(0.0); // 累积的雾发光。
    float absorbance = 1.0; // 累积的透过率，用来给后面的光正确留出通道。
    float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
    float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
    for (int i = 0; i < sampleCount; i++) // 逐步前进。
    {
        float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
        float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
        vec3 progressW = cameraPos + d * rayWorld; // 这一步的世界位置。
        vec3 lightPos = progressW - vec3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处。
        float volumeDensity = ogxEndVortexShape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
        float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPos) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
        float stormDensity = min(volumeDensity, clearArea * clearArea * stormScale); // 风暴部分按贴脸留空与密度封顶。
        float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
        vec3 lightsources = ogxEndVortexLighting(progressW, lightPos, volumeDensity, vortexColor, time, noiseTexture, noiseResolution); // 这一步的雾内光柱发光。
        vec3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
        vec3 stormLighting = indirect + lightsources; // 这一步的总发光。
        color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
        absorbance *= volumeCoeff; // 透过率继续衰减。
        vec3 hazeLighting = vec3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
        color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
    }
    return vec4(color * outputScale, absorbance); // 散射色换算到管线单位，剩余透射率一并交回。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分，最后乘风暴与雾霭两层密度。
// `VdotL` 是视线与光方向余弦，`angleX`、`angleY` 是行星相位角，`planetShadow` 是行星遮挡权重。
float ogxEndFogDensity(vec3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale)
{
    mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
    mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
    mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。
    vec3 dir = ogxMatrix3MulPoint(eyeRoataionMatrix, worldDir); // 视线转到相位坐标系。
    dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
    float h = abs(dir.z) * dist * 0.03; // 沿视线方向的等效高度。
    float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。
    float storm = ogxMiePhase(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分。
    float haze = 0.25; // 不带方向的雾霭基准部分。
    float density = fogDepth * (storm * stormScale + haze * hazeScale); // 两层分别缩放后相加。
    density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。
    return density; // 交回未换算单位的密度。
}

// 下界群系自发光：五个群系各给一种基色与强度，按平滑权重相加后再乘整体亮度。
// 为什么每个群系单独一项：下界没有太阳，画面亮度全靠这组写死的基色撑着，群系之间差别很大。
vec3 ogxNetherBiomeLighting(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness)
{
    vec3 lighting = netherWastes * vec3(0.99, 0.34, 0.10) * 4.5e-4; // 荒地偏橙红，最弱。
    lighting += soulSandValley * vec3(0.60, 0.77, 1.00) * 2e-4; // 灵魂沙峡谷偏青蓝，更暗。
    lighting += crimsonForest * vec3(1.00, 0.80, 0.57) * 4e-4; // 绯红森林偏暖白。
    lighting += warpedForest * vec3(0.79, 0.82, 1.00) * 2.5e-4; // 诡异森林偏冷蓝。
    lighting += basaltDeltas * vec3(1.00, 0.78, 0.62) * 1e-3; // 玄武岩三角洲最亮。
    return lighting * brightness; // 按整体亮度缩放。
}

// 下界群系雾色：前三个分量是颜色，第四个分量是密度，五个群系按同一套权重混合。
// 为什么密度也按群系混合：玄武岩三角洲的灰雾最浓、诡异森林最淡，颜色和浓度本来就该一起变。
vec4 ogxNetherBiomeFogColor(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness, float density)
{
    vec4 fog = vec4(0.990, 0.170, 0.005, 0.010) * netherWastes; // 荒地橙红、中等密度。
    fog += vec4(0.010, 0.035, 0.060, 0.007) * soulSandValley; // 灵魂沙峡谷近乎黑青。
    fog += vec4(0.200, 0.020, 0.000, 0.010) * crimsonForest; // 绯红森林暗红。
    fog += vec4(0.030, 0.100, 0.130, 0.007) * warpedForest; // 诡异森林暗青。
    fog += vec4(0.400, 0.400, 0.400, 0.014) * basaltDeltas; // 玄武岩三角洲灰色、最浓。
    return fog * vec4(brightness, brightness, brightness, density); // 颜色乘亮度、密度乘雾浓度。
}

// Eclipse 群系雾色：四个群系各给一组红绿蓝基色，按权重相加；返回本群系颜色与覆盖程度。
// 为什么颜色分量分开写：与参考文件一行对一行，之后核对某个群系的颜色不会看错列。
vec3 ogxBiomeFogColor(vec4 weights, vec3 paleGarden, vec3 swamp, vec3 jungle, vec3 darkForest, out float coverage)
{
    coverage = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 四个群系权重之和就是覆盖程度。
    vec3 color = vec3(0.0); // 默认不在任何群系内，颜色为零。
    color.r = weights.w * paleGarden.r + weights.x * swamp.r + weights.y * jungle.r + weights.z * darkForest.r; // 红色分量。
    color.g = weights.w * paleGarden.g + weights.x * swamp.g + weights.y * jungle.g + weights.z * darkForest.g; // 绿色分量。
    color.b = weights.w * paleGarden.b + weights.x * swamp.b + weights.y * jungle.b + weights.z * darkForest.b; // 蓝色分量。
    return color; // 交回群系雾色。
}

// Eclipse 群系雾密度：把高度衰减雾与团雾两套密度朝当前群系混合，远处按包络退回原值。
// `weights` 顺序是沼泽、丛林、黑森林、苍白花园；`maxDistance` 是随距离收敛的包络。
void ogxBiomeFogDensity(vec4 weights, inout float uniformDensity, inout float cloudyDensity,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 落在任一已启用群系内的程度。
    float biomeUniform = weights.x * swampUniform + weights.y * jungleUniform + weights.z * darkForestUniform + weights.w * paleGardenUniform; // 高度衰减雾密度加权和。
    float biomeCloudy = weights.x * swampCloudy + weights.y * jungleCloudy + weights.z * darkForestCloudy + weights.w * paleGardenCloudy; // 团雾密度加权和。
    float blend = inBiome * maxDistance; // 群系内且靠近相机时才替换。
    uniformDensity = mix(uniformDensity, biomeUniform, blend); // 高度衰减雾朝群系值混合。
    cloudyDensity = mix(cloudyDensity, biomeCloudy, blend); // 团雾朝群系值混合。
}

// Eclipse 的群系雾密度：把沼泽、丛林、黑森林、苍白花园、沙暴、雪暴六类分开加权。
// 参考实现先算总权重，再分别写密度两个分量；沙暴高度密度为零，雪暴固定 0.01。
void ogxBiomeFogDensityEclipse(inout vec4 uniformDensity, inout vec4 cloudyDensity,
    float paleGarden, float jungles, float swamps, float darkForests, float sandStorm, float snowStorm,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(paleGarden + jungles + swamps + darkForests + sandStorm + snowStorm, 0.0, 1.0); // 六类群系的总权重。
    vec2 density = vec2(0.0); // 高度密度与团雾密度。
    density.x = swamps * swampUniform + jungles * jungleUniform + darkForests * darkForestUniform
              + sandStorm * 0.0 + snowStorm * 0.01; // 高度密度里沙暴为零、雪暴固定 0.01。
    density.y = paleGarden * paleGardenCloudy + swamps * swampCloudy + jungles * jungleCloudy
              + darkForests * darkForestCloudy + sandStorm * 0.5 + snowStorm * 0.5; // 团雾密度六类都参与。
    uniformDensity = mix(uniformDensity, vec4(density.x), inBiome * maxDistance); // 高度密度混合。
    cloudyDensity = mix(cloudyDensity, vec4(density.y), inBiome * maxDistance); // 团雾密度混合。
}

// Eclipse 末地雾的相函数：与云相函数同形，但常数用 3.14 而不是 pi，保留参考精度。
float ogxEndFogPhaseEclipse(float x, float g)
{
    float gg = g * g; // g 的平方。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现直接写 3.14。
}

// iterationT 的原版雾叠加：黑暗、失明、水下与岩浆四种状态分别压暗画面。
// 为什么按状态分开：每种状态的距离范围与目标颜色不同，合并会改变边界。
vec3 ogxVanillaFog(vec3 color, float dist, float farPlane, float darkness, float blindness,
    int eyeInWater, float torchBrightness)
{
    if (darkness > 0.0) // 黑暗效果：远处逐步变黑。
    {
        color = mix(color, vec3(0.0), smoothstep(5.0, mix(farPlane, 15.0, darkness), dist) * darkness);
    }
    if (blindness > 0.0) // 失明效果：更近距离变黑。
    {
        color = mix(color, vec3(0.0), smoothstep(1.5, mix(farPlane, 4.5, blindness), dist) * blindness);
    }
    if (eyeInWater == 3) // 细雪或粉雪：近处压成深灰。
    {
        color = mix(color, vec3(0.03), smoothstep(0.0, 2.0, dist));
    }
    if (eyeInWater == 2) // 岩浆：近处压成暖橙。
    {
        color = mix(color, vec3(0.3721, 0.0775, 0.0024) * torchBrightness, smoothstep(0.0, 1.0, dist));
    }
    return color; // 返回叠加后的颜色。
}

// iterationT 的选择框：选中方块时用贴图色乘曝光统计值，覆盖原画面。
vec3 ogxSelectionBox(vec3 color, vec3 albedo, bool isSelection, float exposureEncoded, float exposureOutputFactor)
{
    if (!isSelection) return color; // 没有选中就不改。
    float exposure = exposureEncoded * exposureEncoded * exposureEncoded * exposureEncoded; // CurveToLinear 的标量版。
    exposure *= 1500.0 / exposureOutputFactor; // 参考实现的曝光缩放。
    return albedo * exposure; // 选中框用贴图色乘曝光。
}

#endif

/*
生成文件：体积雾模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；Minecraft 光影由 `/omni-gfx/fog_volume.glsl` 引入，
    `rendering/fog/volumetric.glsl` 只把选项、天气、群系与阴影贴图换成参数。
可复制示例：先填好一层雾的参数，再调用一次 `ogxVolumetricFog` 完成整段步进。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明与水下手持光属于可选的宿主能力，用两个钩子宏留给效果层注入；不定义时是完全的空操作。
    钩子宏沿用旧名字：宿主在包含本文件之前就定义它们，改名需要同时改宿主，收益只有名字统一。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
*/
#ifndef OGX_FOG_VOLUME_INCLUDED
#define OGX_FOG_VOLUME_INCLUDED

// 可选的雾照明钩子：效果层在包含本文件前定义，不定义时完全为空。
// 它接受当前雾点、这一步的吸收量、累计颜色与提前结束标记，由宿主决定是否采样体积光。
#ifndef GFX_FOG_LPV_STEP
#define GFX_FOG_LPV_STEP(fog_pos, integral, accum, done)
#endif

// 可选的水下手持光钩子：效果层把物品光采样接到这里，不定义时不加任何光。
#ifndef GFX_UNDERWATER_HAND_LIGHT
#define GFX_UNDERWATER_HAND_LIGHT(world_pos) vec3(0.0)
#endif

// 雾密度、相位与粉末效应来自雾模块；暴风噪声来自天气，波法线与阴影坐标来自水面与阴影模块。

/*
生成文件：天气模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库天气模块：雨雪随风偏移、植被与季节上色、暴风噪声与颜色、每日天气哈希。
调用位置：任何需要天气形状的程序；Minecraft 光影由 `/omni-gfx/weather.glsl` 引入，
    `rendering/weather/*` 的四个文件只保留选项换算并转发到这里。
可复制示例：
    vec2 o = ogxRainWindOffset(worldPos, cameraPos, seconds, wind, 0.05, 1.0); // 雨雪的水平偏移。
    float n = ogxStormNoise(worldPos, noiseTexture, 512.0); // 暴风雾团密度。
    vec3 c = ogxStormColor(snowStorm, sandStorm); // 暴雪与沙暴的染色。
    float h = ogxWeatherHash11(day); // 每日天气的随机取档。
设计原因与取舍：
    位置、时间、风向、扰动和露天系数全部由调用方传入，库不读取相机或天气全局量。
    倾斜随高度放大，露天系数为零时雨雪保持竖直，因此室内不会被风推斜。
    噪声贴图采样固定用零号层级：旧实现的即时采样在单层噪声图上等价，
    固定层级还能让同一份源在 Vulkan 探针里编译。
*/
#ifndef OGX_WEATHER_INCLUDED
#define OGX_WEATHER_INCLUDED

// 数学模块提供取模与夹紧，季节循环与时段划分要用。

// 雨雪随风摆动：固定风向叠一个缓慢旋转的扰动，再按高度放大。
// 为什么扰动跟着世界位置走：不同位置的雨丝才不会像一整块布同步摆动。
vec2 ogxRainWindOffset(vec3 worldPos, vec3 cameraPos, float time, vec2 wind, float disturbance, float outdoor)
{
    float angle = dot(worldPos + cameraPos, vec3(3.0, 0.5, 3.0)) + time * 0.2; // 位置与时间决定的摆动相位。
    vec2 rotation = vec2(sin(angle), cos(angle)); // 摆动方向。
    vec2 offset = (wind + rotation * disturbance) * worldPos.y; // 固定风向加摆动，按高度放大。
    return outdoor * offset; // 只有露天时倾斜。
}

// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被。
// 乘四是为了让普通草色接近一，避免季节色只有一点点。
float ogxFoliage(vec3 vertexColor)
{
    return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 用绿色优势判断是否植被。
}

// 季节上色：植被按一年相位混入秋色，再按色调参数整体偏暖或偏冷。
// `phase` 是零到一的一年进度，`tint` 是负到正的冷暖偏置，`enabled` 关闭时原样返回。
vec3 ogxSeason(vec3 albedo, vec3 vertexColor, float phase, float tint, bool enabled)
{
    if (!enabled) return albedo; // 关闭时不做任何改动。
    float foliage = ogxFoliage(vertexColor); // 这一面有多像植被。
    float autumn = 0.5 - 0.5 * cos(phase * 6.28318530718); // 一年过半时最接近秋天。
    vec3 seasonal = mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成。
    seasonal *= vec3(1.0 + 0.2 * tint, 1.0, 1.0 - 0.2 * tint); // 整体偏暖或偏冷。
    return albedo * mix(vec3(1.0), seasonal, foliage); // 只按植被程度生效。
}

// 暴风噪声：把世界坐标折进噪声贴图，得到随风滚动的雾团密度。
// `noiseResolution` 是噪声贴图边长，调用方可以换用别的贴图而不改公式。
float ogxStormNoise(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    position /= 18.0; // 噪声格子的基准边长。
    position.xz *= 0.5; // 横向再缩一半，让雾团更扁更长，像被风拉过。
    vec3 cell = floor(position); // 所在整数格，决定用贴图哪一块。
    vec3 fraction = fract(position); // 格内小数偏移，用来做插值。
    fraction = fraction * fraction * (3.0 - 2.0 * fraction); // 三次平滑，插值不出现方块边界。
    vec2 uv = cell.xz + fraction.xz + cell.y * vec2(0.0, 193.0); // 三维格子映射到二维坐标，纵轴加大偏移错开层。
    vec2 sample2 = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 读噪声并取两个通道，顺序照原程序。
    return mix(sample2.r, sample2.g, fraction.y); // 沿高度在两通道之间插值。
}

// 暴风颜色：按雪暴与沙暴的强度在冷白与沙黄之间加权，再归一化成雾色乘子。
// 加一个小量避免两份强度都为零时除零；零强度由调用方跳过，不会走到这里。
vec3 ogxStormColor(float snowStorm, float sandStorm)
{
    float total = max(snowStorm + sandStorm, 1e-4); // 两份强度之和。
    vec3 sandCol = vec3(1.0, 0.3, 0.1); // 沙暴的沙黄，照 Eclipse 的沙尘系数。
    vec3 snowCol = vec3(0.6, 0.8, 1.0); // 雪暴的冷白，照 Eclipse 的雪系数。
    return (sandStorm * sandCol + snowStorm * snowCol) / total; // 按强度加权后归一。
}

// 每日天气哈希：把整数天数打散成零到一的小数，照 Eclipse 的 `hash11`。
// 三步混合让相邻天数看起来毫无关系，同时保持完全确定的重复性。
float ogxWeatherHash11(float p)
{
    p = fract(p * 0.1031); // 先乘一个无理近似再取小数，打散相邻整数。
    p *= p + 33.33; // 加偏移后再平方，让输入的小变化放大。
    p *= p + p; // 再乘自身的两倍，进一步拉开分布。
    return fract(p); // 取小数，得到零到一的哈希值。
}

// 四季调色板：树叶与非树叶各一套颜色，因为树叶的季节变化通常更明显。
struct OgxSeasonPalette
{
    vec3 summer; // 非树叶的夏天颜色。
    vec3 autumn; // 非树叶的秋天颜色。
    vec3 winter; // 非树叶的冬天颜色。
    vec3 spring; // 非树叶的春天颜色。
    vec3 summerLeaf; // 树叶的夏天颜色。
    vec3 autumnLeaf; // 树叶的秋天颜色。
    vec3 winterLeaf; // 树叶的冬天颜色。
    vec3 springLeaf; // 树叶的春天颜色。
};

// Eclipse 四季上色：按游戏天数在四个季节之间连续插值，再乘顶点色。
// `tintIndex` 由调用方判断，决定这一面是否使用群系染色；不使用的面保持原色。
vec3 ogxYearCycleColor(vec3 finalColor, vec3 glcolor, bool isLeaves, OgxSeasonPalette palette, int worldDay, int seasonLength,
    int startSeason, bool tintIndex)
{
    vec3 summer = isLeaves ? palette.summerLeaf : palette.summer; // 树叶用树叶那一套。
    vec3 autumn = isLeaves ? palette.autumnLeaf : palette.autumn;
    vec3 winter = isLeaves ? palette.winterLeaf : palette.winter;
    vec3 spring = isLeaves ? palette.springLeaf : palette.spring;
    summer *= glcolor; // 四季颜色都乘顶点色，保留群系底色。
    autumn *= glcolor;
    winter *= glcolor;
    spring *= glcolor;
    float yearLoop = ogxMod(float(worldDay + startSeason * seasonLength), float(seasonLength * 4)); // 一年内的进度。
    float summerTime = clamp(yearLoop, 0.0, float(seasonLength)) / float(seasonLength); // 四个季节各自的权重。
    float autumnTime = clamp(yearLoop - float(seasonLength), 0.0, float(seasonLength)) / float(seasonLength);
    float winterTime = clamp(yearLoop - float(seasonLength * 2), 0.0, float(seasonLength)) / float(seasonLength);
    float springTime = clamp(yearLoop - float(seasonLength * 3), 0.0, float(seasonLength)) / float(seasonLength);
    vec3 summerToFall = mix(summer, autumn, summerTime); // 依次插值，最后回到夏天。
    vec3 fallToWinter = mix(summerToFall, winter, autumnTime);
    vec3 winterToSpring = mix(fallToWinter, spring, winterTime);
    vec3 springToSummer = mix(winterToSpring, summer, springTime);
    return tintIndex ? springToSummer : finalColor; // 不使用群系染色的面保持原色。
}

// 一天四个时段的雾密度：晨、午、晚、夜各一组，均匀雾与团雾分开。
struct OgxTodFog
{
    vec4 uniformBands; // 四个时段的均匀雾密度。
    vec4 cloudyBands; // 四个时段的团雾密度。
};

// 群系雾覆盖：权重与两套密度，顺序是沼泽、丛林、黑森林、苍白花园。
struct OgxBiomeFog
{
    vec4 weights; // 四个群系的权重。
    float uniformDensity; // 群系均匀雾密度。
    float cloudyDensity; // 群系团雾密度。
};

// Eclipse 时段雾：把一天切成晨、午、晚、夜四段，取对应密度。
// `dailyUniform` 与 `dailyCloudy` 是每日天气给出的下限，开启时取较大者；群系雾最后覆盖。
void ogxFogDensities(inout float uniformDensity, inout float cloudyDensity, float dayTime, float fogMultiplier,
    OgxTodFog tod, vec2 daily, bool dailyWeather, OgxBiomeFog biome, bool perBiome, float maxDistance)
{
    float time = ogxMod(dayTime, 24000.0); // 一天内的时刻。
    float morning = clamp((time - 22000.0) / 2000.0, 0.0, 1.0) + clamp((2000.0 - time) / 2000.0, 0.0, 1.0); // 晨，跨午夜两段。
    float noon = clamp(time / 2000.0, 0.0, 1.0) * clamp((12000.0 - time) / 2000.0, 0.0, 1.0); // 午。
    float evening = clamp((time - 10000.0) / 2000.0, 0.0, 1.0) * clamp((14000.0 - time) / 2000.0, 0.0, 1.0); // 晚。
    float night = clamp((time - 13000.0) / 2000.0, 0.0, 1.0) * clamp((23000.0 - time) / 2000.0, 0.0, 1.0); // 夜。
    vec4 uniformBands = tod.uniformBands * fogMultiplier; // 四段均匀雾密度乘总倍率。
    vec4 cloudyBands = tod.cloudyBands * fogMultiplier; // 四段团雾密度。
    if (dailyWeather) // 每日天气给一个下限。
    {
        uniformBands = max(uniformBands, vec4(daily.x, daily.x, daily.x, daily.x));
        cloudyBands = max(cloudyBands, vec4(daily.y, daily.y, daily.y, daily.y));
    }
    if (perBiome) // 群系雾按权重与距离包络覆盖。
    {
        float inBiome = clamp(biome.weights.x + biome.weights.y + biome.weights.z + biome.weights.w, 0.0, 1.0);
        float blend = inBiome * maxDistance;
        uniformBands = mix(uniformBands, vec4(biome.uniformDensity, biome.uniformDensity, biome.uniformDensity, biome.uniformDensity), blend);
        cloudyBands = mix(cloudyBands, vec4(biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity, biome.cloudyDensity), blend);
    }
    uniformDensity *= morning * uniformBands.x + noon * uniformBands.y + evening * uniformBands.z + night * uniformBands.w; // 按四段权重求和。
    cloudyDensity *= morning * cloudyBands.x + noon * cloudyBands.y + evening * cloudyBands.z + night * cloudyBands.w; // 团雾同样。
}

#endif

/*
生成文件：阴影模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库阴影模块：阴影相机投影、边缘压缩、屏幕空间阴影、PCSS 软阴影、级联选择。
调用位置：任何需要方向光阴影贴图或屏幕空间阴影的程序；Minecraft 光影由 `/omni-gfx/shadow.glsl` 引入。
可复制示例：
    vec3 c = ogxShadowScreenPosDistorted(worldPos, lightView, lightProjection, 0.9); // 带边缘压缩的阴影坐标。
    float v = ogxPcssVisibility(shadowMap, c, c.z, texel, 12.0, 24.0, 0.0016, 8, 12); // 一张贴图的软阴影。
    OgxCascadeSelect s = ogxSelectCascade(viewDepth, vec3(32.0, 64.0, 128.0), 6.0); // 选级联与过渡权重。
设计原因与取舍：
    矩阵、纹理、分辨率与选项全部由调用方传入，库不读取引擎状态；深度图的格式由调用方决定。
    算式与旧 `shaders/gfx/shadow.glsl` 逐项一致，迁移只改名字和语法，默认画面因此不变。
    PCSS 与级联是阶段三新增能力：半影宽度由遮挡物距离推出，级联交界做线性过渡，避免硬边。
    矩阵乘法在 Slang 与 GLSL 的行列解释不同，这里统一走数学模块的列展开入口，不直接乘矩阵。
*/
#ifndef OGX_SHADOW_INCLUDED
#define OGX_SHADOW_INCLUDED

// 饱和、矩阵列展开与圆周常数来自数学模块。

// Eclipse 的阴影修补：按相机距离把世界坐标抬离表面一点点，抵消阴影图的彼得潘效应。
// 为什么用小数抖动而不是固定偏移：固定偏移会在不同距离留下阶梯，按世界坐标取小数能让误差散开。
// `transition` 是阴影过渡量，越小越靠近阴影边缘，偏移越强；`flatNormal` 为保持原签名而保留，原程序未使用。
void ogxGriAndEminShadowFix(inout vec3 worldPos, vec3 flatNormal, float transition, vec3 cameraWorldPos, bool eyeInWater)
{
    transition = 1.0 - transition; // 过渡量取反，边缘处为一。
    transition *= transition * transition * transition * transition * transition * transition; // 六次方，只让最边缘一段生效。
    float zoomLevel = mix(0.0, 0.5, transition); // 边缘处偏移半个格子。
    if (zoomLevel > 0.001 && !eyeInWater) // 水下不做偏移，原程序同样跳过。
    {
        worldPos = worldPos - (fract(worldPos + cameraWorldPos - worldPos * 0.0001) * zoomLevel - zoomLevel * 0.5); // 按位置小数把坐标推到格子中心附近。
    }
}

// Eclipse 的阴影偏差：按一个阴影像素对应一个方块的尺度，沿几何法线把投影坐标推出表面。
// `shadowNormal` 是法线经过阴影相机旋转后的方向，`shadowDistance` 与 `shadowMapResolution` 决定纹素大小。
void ogxApplyShadowBias(inout vec3 projectedShadowPosition, vec3 shadowNormal, float shadowDistance, float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个纹素对应的世界尺度，再放大一倍。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远，斜投影误差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 按距离放大偏差。
    projectedShadowPosition += shadowNormal * biasSize * 0.15 * biasDistanceFactor; // 沿法线推出表面。
}

// 黄金角的正弦与余弦：螺旋采样每步旋转这个角度，样本才不会排成放射状条纹。
const float OGX_SHADOW_GOLDEN_COS = -0.737368878;
const float OGX_SHADOW_GOLDEN_SIN = 0.675490294;

// 阴影相机空间里的位置：先做视图变换，再按正交投影缩放并把深度折半。
// 为什么深度取半：阴影图存的是裁剪空间到零到一的压缩值，后面所有比较都按同一尺度进行。
vec3 ogxShadowViewPos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    vec3 shadowPos = ogxMatrixMulPoint(shadowView, worldPos) + ogxMatrixTranslation(shadowView); // 世界位置转到阴影相机空间。
    float scale = shadowProjection[0][0]; // 正交投影的水平缩放，横纵相同。
    shadowPos *= vec3(scale, scale, -scale * 0.5); // 按投影缩放，深度取半。
    return shadowPos; // 返回阴影相机空间的坐标。
}

// 投到阴影图，不做边缘压缩：坐标范围仍是负一到一。
vec3 ogxShadowScreenPos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    return ogxShadowViewPos(worldPos, shadowView, shadowProjection) * 0.5 + 0.5; // 负一到一转成零到一。
}

// 投到阴影图并做边缘压缩：离中心越远压得越紧，边缘纹素因此覆盖更小的实际范围。
vec3 ogxShadowScreenPosDistorted(vec3 worldPos, mat4 shadowView, mat4 shadowProjection, float bias)
{
    vec3 shadowPos = ogxShadowViewPos(worldPos, shadowView, shadowProjection); // 先转到阴影相机空间。
    float dist = length(shadowPos.xy); // 到阴影图中心的距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数，中心为一。
    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩，零点九五留出边界余量。
    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一。
}

// 读取端补一次边缘压缩：写入端压过的坐标，读取时必须按同一系数还原。
vec2 ogxDistortShadowPos(vec2 shadowPos, float bias)
{
    shadowPos = shadowPos * 2.0 - 1.0; // 零到一先转回负一到一。
    float dist = length(shadowPos.xy); // 到中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 与写入端同一压缩系数。
    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
    return shadowPos * 0.5 + 0.5; // 再转回零到一。
}

// 屏幕深度换米制距离：逆投影里只有深度那一列参与，两个系数就是全部信息。
// 为什么不用整矩阵乘：这一步在每条步进的射线上都要算，取两个系数最省。
float ogxShadowLinearDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 射线是否还在可靠深度范围内：近处像素的深度图只有半个屏幕可用。
bool ogxInsideDepthRange(vec3 samplePos)
{
    return ogxEqual(samplePos.xy, ogxSaturate(samplePos.xy)); // 横纵都在零到一才算有效。
}

// 屏幕空间阴影：从表面沿光源方向在屏幕里步进，走到比射线更近的几何就判为遮挡。
// 为什么起点要沿法线抬一点：贴近表面的光源不抬会刚出发就打到自己，整片出现自阴影。
// 为什么用抖动：固定采样会在光斑边缘留下规则条纹，配合时间抗锯齿后条纹消失。
// 步数由调用方按画质给，八步与十六步对应原来的低、高质量。
float ogxScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, vec3 shadowDir,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise, bool hasDh, int steps, float strength)
{
    shadowDir.z = max(shadowDir.z, 1e-5); // 深度分量保证不太小，避免除法把射线推到无穷远。
    float rayLength = -0.04 * viewPos.z / shadowDir.z; // 一步射线的长度，按当前深度与光源方向缩放。
    vec3 viewRayDir = shadowDir * rayLength; // 视空间里的射线方向。
    vec3 start = viewPos; // 射线起点就是当前表面。
    float ndotl = ogxSaturate(dot(shadowDir, normal)); // 光源方向与法线的夹角余弦。
    float fov = atan(1.0 / projection[1][1]) * 360.0 * OGX_INV_PI; // 由投影反推视角，供偏移按视野缩放。
    start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿射线先跳过一段，掠射时跳得更多。
    start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(ndotl, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
    vec3 end = start + viewRayDir; // 一步的终点。
    start = vec3(vec2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
    end = vec3(vec2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
    vec3 screenRayDir = end - start; // 这一步在裁剪空间的位移。
    screenRayDir.xy *= 0.5; // 横纵方向换算到零到一坐标。
    start.xy += vec2(projection[3][0], projection[3][1]); // 补上投影的平移项。
    start.xy *= 0.5; // 裁剪空间转到零到一。
    float minDist = ogxShadowLinearDepth(0.7, projectionInverse); // 深度小于这个值的像素在前面，不再作为遮挡。
    float shadow = 1.0; // 可见度，初值全亮。
    float stepLength = 1.0; // 步长，逐步增大。
    for (int i = 0; i < steps; i++, start += screenRayDir * stepLength, stepLength += 0.3) // 步长递增覆盖更远。
    {
        vec3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
        if (samplePos.z < minDist) // 已经走到相机很近的地方，后面没有可靠深度。
        {
            break;
        }
        samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。
        if (!ogxInsideDepthRange(samplePos)) // 出了屏幕就停止，屏幕外没有可靠深度。
        {
            break;
        }
        float sampleDepth = textureLod(depthTexture, samplePos.xy, 0.0).x; // 读该点的不透明深度。
        if (sampleDepth < 0.7) // 近处已有几何挡住，后面不必再看。
        {
            break;
        }
        float sampleDist; // 采样点到相机的米制距离。
        if (hasDh && sampleDepth == 1.0) // 近景是天空时改读远景深度。
        {
            sampleDepth = textureLod(dhDepthTexture, samplePos.xy, 0.0).x; // 改读远景深度。
            sampleDist = ogxShadowLinearDepth(sampleDepth, dhProjectionInverse); // 远景深度换成距离。
        }
        else
        {
            sampleDist = ogxShadowLinearDepth(sampleDepth, projectionInverse); // 近景深度换成距离。
        }
        if (samplePos.z - sampleDist > 0.0) // 射线深度超过几何深度，说明几何在前面。
        {
            shadow = 0.0; // 记为完全遮挡。
            break; // 结束步进。
        }
    }
    return max(shadow, 1.0 - strength); // 按强度给阴影压到下限，强度零点八五时与原来的零点一五底光一致。
}

// 阳光的屏幕空间阴影：在屏幕里沿阳光方向步进，撞到比当前更近的几何就按吸收量削弱。
// 为什么叶片先用饱和放大：叶片材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
// `fov` 由调用方按材质选择（草和叶片用较大视野估计），`absorption` 是每次遮挡的吸收量。
float ogxSunScreenShadow(vec3 viewPos, vec3 viewDir, vec3 normal, vec3 shadowVector, float fov,
    float absorption, float softness, float grass, sampler2D depthTexture, sampler2D dhDepthTexture,
    mat4 projection, mat4 projectionInverse, mat4 dhProjectionInverse, float pixelScale, float minStep,
    vec2 offsetCoord, float noise, bool hasDh, int steps)
{
    vec3 viewRayDir = shadowVector * max(-viewPos.z * 3e-5 * fov, minStep); // 每一步在屏幕上的推进量。
    vec3 start = viewPos; // 步进起点。
    if (softness < 0.1) // 普通表面才做偏移，草和叶片的画面已经足够软。
    {
        float ndotl = ogxSaturate(dot(shadowVector, normal)); // 阳光与法线的夹角。
        start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿光线先跳过一段。
        start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(ndotl, 0.01)); // 再沿法线抬一点。
    }
    vec3 end = start + viewRayDir; // 一步的终点。
    start = vec3(vec2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
    end = vec3(vec2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
    vec3 screenRayDir = end - start; // 这一步在裁剪空间的位移。
    screenRayDir.xy *= 0.5; // 换算到零到一坐标。
    start.xy += vec2(projection[3][0], projection[3][1]); // 补上投影的平移项。
    start.xy *= 0.5; // 转到零到一。
    start += screenRayDir * grass; // 草的原点再前进一小段，减少草自身投出的错误阴影。
    float shadow = 1.0; // 阴影可见度，初值全亮。
    float stepLength = 1.0; // 步长，逐步增大。
    float zThickness = 0.025 + 0.0125 * -viewPos.z; // 遮挡厚度阈值，距离越远越厚，避免远处噪点。
    for (int i = 0; i < steps; i++, start += screenRayDir * stepLength, stepLength += 0.3) // 步长递增覆盖更远。
    {
        vec3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
        samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。
        if (!ogxInsideDepthRange(samplePos)) // 出了屏幕就停止。
        {
            break;
        }
        float sampleDepth = textureLod(depthTexture, samplePos.xy, 0.0).x; // 近景深度。
        float sampleDist; // 采样点到相机的米制距离。
        if (hasDh && sampleDepth == 1.0) // 近景是天空时才查远景。
        {
            sampleDepth = textureLod(dhDepthTexture, samplePos.xy, 0.0).x; // 改读远景深度。
            sampleDist = ogxShadowLinearDepth(sampleDepth, dhProjectionInverse); // 远景深度换成距离。
        }
        else
        {
            sampleDist = ogxShadowLinearDepth(sampleDepth, projectionInverse); // 近景深度换成距离。
        }
        float depthDiff = samplePos.z - sampleDist; // 射线深度与几何深度之差，为正说明几何在前面。
        if (depthDiff > 0.0 && depthDiff < zThickness) // 落在厚度阈值内才算遮挡。
        {
            shadow *= absorption; // 按吸收量削弱。
        }
        if (shadow < 0.01) // 已经足够暗，提前结束。
        {
            break;
        }
    }
    return shadow; // 返回可见度。
}

// 阴影图里一段视线的遮挡距离：沿线段采样，统计被实心几何挡住的样本比例并折算成米。
// 为什么把线段长度传进来：样本比例要乘实际长度才是米，调用方已经知道这段有多长。
float ogxShadowSegmentOcclusion(vec3 shadowStart, vec3 shadowEnd, sampler2D shadowTexture, int steps,
    float noise, float bias, float segmentLength)
{
    float rSteps = 1.0 / float(steps); // 采样数倒数。
    vec3 increment = (shadowEnd - shadowStart) * rSteps; // 阴影图里的步进。
    vec3 position = increment * noise + shadowStart; // 起点加抖动。
    float occluded = 0.0; // 被挡住的样本数。
    for (int i = 0; i < steps; i++, position += increment) // 沿视线段采样。
    {
        vec3 shadowPos = position; // 当前采样坐标。
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, bias); // 补边缘压缩。
        if (ogxInsideDepthRange(shadowPos) && shadowPos.z < 1.0) // 落在阴影图内。
        {
            float solidDepth = textureLod(shadowTexture, shadowPos.xy, 0.0).x; // 读遮挡深度。
            occluded += step(solidDepth, shadowPos.z); // 遮挡物在射线前面才算被挡。
        }
    }
    return occluded * (segmentLength * rSteps); // 按样本比例折算成被遮挡的米数。
}

// 不透明表面阴影：可变半影、彩色半透明阴影与次表面散射，三者共用同一次阴影图采样。
// 为什么先做透光散射：叶片、草这类薄片本身就透光，先算透光再把阳光按比例削弱，阴影才不会过硬。
// 为什么阴影图外坐标直接放弃采样：半影采样会跑出阴影图边界，硬读边界会把边界压成一条黑线。
vec3 ogxVariablePenumbraShadow(vec3 worldPos, vec3 worldNormal, float sunlight, vec3 albedo,
    float scatteringStrength, float hand, float leaves, float grass, vec3 cameraWorldPosition, vec3 viewAxisZ,
    mat4 shadowView, mat4 shadowProjection, sampler2D shadowDepth0, sampler2DShadow shadowDepth1,
    sampler2D shadowColor0, float shadowMapResolution, float shadowDistance, float farPlane, float bias,
    vec2 noise, bool variablePenumbra, bool coloredShadows, bool sssDirectional, float sssBrightness,
    float sssPhase, float sssQuality, float vpsQuality, float vpsSpread, float basicBlur, out vec3 sss)
{
    worldPos += cameraWorldPosition; // 相机相对世界位置补上相机位置，换成阴影相机能用的世界坐标。
    worldPos -= viewAxisZ * 0.5 * hand; // 手持物抬高半格，避免手贴脸时投出错误的自阴影。
    vec3 shadowNormal = ogxMatrixMulPoint(shadowView, worldNormal); // 世界法线转到阴影相机空间。
    shadowNormal.z = -shadowNormal.z; // 深度轴与视空间相反，翻转过来比较方向才正确。
    vec3 shadowScreenPos = ogxShadowViewPos(worldPos, shadowView, shadowProjection); // 按投影缩放、深度取半。
    float zScale = 1.0 / shadowProjection[0][0]; // 深度缩放倒数，把深度差还原成实际距离。
    float dist = length(shadowScreenPos.xy); // 到阴影图中心的距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数，与坐标变换一致。
    vec3 result = vec3(1.0); // 阴影可见度，初值全亮。
    sss = vec3(0.0); // 次表面散射初值为零。
    if (scatteringStrength > 0.0) // 只有透光材质才走散射，普通表面直接跳过整段。
    {
        vec3 shadowScreenPosRaw = shadowScreenPos; // 未压缩坐标，散射采样要用。
        shadowScreenPosRaw.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
        shadowScreenPosRaw = shadowScreenPosRaw * 0.5 + 0.5; // 转成零到一纹理坐标。
        float spread = (scatteringStrength * 0.12 + 0.05) / (distortFactor * shadowDistance) + basicBlur / shadowMapResolution; // 散射采样半径。
        vec3 scatteringDensity = 15.0 / (scatteringStrength * albedo + 0.1); // 散射密度：底色越亮越容易透过。
        float rSteps = 1.0 / sssQuality; // 次数倒数，用来归一化半径与结果。
        float angle = noise.x * 6.28318530718; // 初始角度取随机，避免所有像素从同一方向起步。
        vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。
        float scatteringDepth = 0.0; // 累计散射深度。
        for (float i = 0.0; i < sssQuality; i++) // 逐次采样阴影图，累计遮挡厚度。
        {
            rot = vec2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                         -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
            float radius = (i + noise.y) * rSteps; // 半径从随机相位起步，样本不重叠。
            vec2 offset = rot * spread * radius; // 当前采样偏移。
            float sampleDepth = textureLod(shadowDepth0, shadowScreenPosRaw.xy + offset, 0.0).x; // 读取该点遮挡深度。
            scatteringDepth += max(shadowScreenPosRaw.z - sampleDepth, 1e-5); // 累加接收点到遮挡物的距离。
        }
        scatteringDepth *= rSteps * zScale; // 取平均并还原成实际距离。
        vec3 scattering = exp2(-scatteringDepth * scatteringDensity); // 厚度越大透光越弱。
        float distFalloff = ogxSaturate(((min(shadowDistance, farPlane) - length(worldPos)) * 0.05 - 1.0)); // 超出阴影范围就淡出透光。
        if (sssDirectional) // 开启朝向透光时按观察角计算。
        {
            sss = scattering * (sssBrightness * distFalloff * (sssPhase * 0.5 + 0.15)); // 逆光方向更亮。
        }
        else
        {
            sss = scattering * (sssBrightness * distFalloff * 0.2); // 固定占比，不随角度变化。
        }
        scatteringStrength *= distFalloff; // 阳光也按同一淡出缩放，远处不再额外透光。
    }
    if (sunlight > 0.0) // 没有阳光时不必采样阴影。
    {
        shadowScreenPos += shadowNormal * (0.002 * (1.0 - leaves) * distortFactor); // 沿法线抬一点减少自身条纹，叶片不抬以免漏光。
        shadowScreenPos.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
        shadowScreenPos = shadowScreenPos * 0.5 + 0.5; // 转成零到一纹理坐标。
        if (ogxInsideDepthRange(shadowScreenPos)) // 只在阴影图内采样，图外保持全亮。
        {
            result = vec3(0.0); // 从全暗开始累加可见样本。
            float spread = vpsSpread * 200.0 / (distortFactor * shadowDistance); // 半影搜索半径。
            float avgDiff = 0.0; // 遮挡物与接收点的平均深度差，用来放大半影。
            if (variablePenumbra) // 可变半影：先估遮挡物距离再决定边缘宽度。
            {
                float spreadLod = log2(shadowMapResolution / 512.0); // 高分辨率用更粗层级抑制噪点。
                for (int i = -1; i <= 1; i++) // 三乘三邻域估计遮挡物距离。
                {
                    for (int j = -1; j <= 1; j++)
                    {
                        vec2 lookupCoord = shadowScreenPos.xy + vec2(i, j) * spread * 0.0039; // 邻域采样坐标。
                        float depthDiff = shadowScreenPos.z - textureLod(shadowDepth0, lookupCoord, spreadLod).x; // 接收点深度减去遮挡物深度。
                        depthDiff = clamp(depthDiff * zScale * 0.0035, 0.0, 0.025); // 归一化并限制范围。
                        avgDiff += depthDiff * depthDiff; // 平方累加，后面开根得到均方根。
                    }
                }
                avgDiff /= 9.0; // 求九个样本的平均。
                avgDiff = sqrt(avgDiff); // 开根得到平均深度差。
            }
            avgDiff = max(avgDiff, 0.015 * leaves + 0.01 * grass); // 叶片与草至少给一点半影，避免薄片边缘过硬。
            float sampleSpread = avgDiff * 0.2 * spread + basicBlur / shadowMapResolution; // 最终采样半径。
            shadowScreenPos.z -= (2e-6 + noise.y * 2e-6) * (dist + 0.03) * (1.0 - 0.9 * leaves) * shadowDistance; // 深度偏移随距离增大。
            float rSteps = 1.0 / vpsQuality; // 次数倒数。
            float angle = noise.y * 6.28318530718; // 初始角度取随机。
            vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。
            for (float i = 0.0; i < vpsQuality; i++) // 逐次采样阴影图求未遮挡比例。
            {
                rot = vec2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                             -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
                float radius = sqrt((i + noise.x) * rSteps); // 平方根半径让样本在圆面上均匀分布。
                vec2 offset = rot * radius * sampleSpread; // 当前采样偏移。
                vec3 sampleCoord = vec3(shadowScreenPos.xy + offset, shadowScreenPos.z); // 采样坐标。
                if (coloredShadows) // 彩色阴影：半透明层用自身颜色，实心层只按遮挡。
                {
                    float translucentShadow = step(sampleCoord.z, textureLod(shadowDepth0, sampleCoord.xy, 0.0).x); // 深度更远即未遮挡。
                    result += vec3(translucentShadow); // 半透明部分累加可见度。
                    float solidShadow = textureLod(shadowDepth1, vec3(sampleCoord.xy, sampleCoord.z), 0.0); // 实心阴影贴图含彩色合成结果。
                    vec3 shadowColorSample = ogxGammaToLinear(textureLod(shadowColor0, sampleCoord.xy, 0.0).rgb); // 该点半透明颜色转线性。
                    result += shadowColorSample * (solidShadow - translucentShadow); // 实心与半透明之差乘颜色。
                }
                else // 关闭彩色阴影时只按实心遮挡。
                {
                    result += vec3(textureLod(shadowDepth1, vec3(sampleCoord.xy, sampleCoord.z), 0.0)); // 直接累加可见度。
                }
            }
            result *= rSteps; // 取平均得到最终可见度。
        }
    }
    if (sssDirectional) // 开启朝向透光时，用透光比例把阴影往亮处提一点。
    {
        return result * (ogxSaturate(0.4 - scatteringStrength * 0.4) + 0.6); // 透光越强整体越亮。
    }
    return result * (ogxSaturate(0.5 - scatteringStrength * 0.5) + 0.5); // 关闭时提亮幅度更小。
}

// --- 阶段三新增：级联选择与 PCSS ---

// 级联选择结果：当前级的编号、过渡到的下一级编号与过渡权重。
// 为什么返回编号而不是矩阵：级联矩阵在调用方的缓冲区里，库只决定用哪一级。
struct OgxCascadeSelect
{
    int index; // 视深度所在的级联编号，零为最近。
    int next; // 过渡目标级联编号，没有过渡时等于当前级。
    float weight; // 下一级的混合权重，零表示完全使用当前级。
};

// 选择级联：`splits` 是三级的分界距离，`blendWidth` 是交界处的过渡宽度（米）。
// 为什么交界要做过渡：两级阴影贴图分辨率不同，硬切换会在交界出现一圈密度跳变。
OgxCascadeSelect ogxSelectCascade(float viewDepth, vec3 splits, float blendWidth)
{
    OgxCascadeSelect result; // 待填的选择结果。
    result.index = 0; // 默认用最近一级。
    if (viewDepth > splits.x) // 超过第一级分界。
    {
        result.index = 1;
    }
    if (viewDepth > splits.y) // 超过第二级分界。
    {
        result.index = 2;
    }
    if (viewDepth > splits.z) // 超过最远分界时仍用最远一级，避免画面出现完全没有阴影的洞。
    {
        result.index = 2;
    }
    float farSplit = result.index == 0 ? splits.x : (result.index == 1 ? splits.y : splits.z); // 当前级的分界距离。
    result.weight = result.index < 2 ? ogxSaturate((viewDepth - (farSplit - blendWidth)) / max(blendWidth, 1e-4)) : 0.0; // 靠近分界时渐入下一级。
    result.next = min(result.index + 1, 2); // 过渡目标是下一级，最远级没有下一级。
    return result; // 返回可直接用于两次采样的结果。
}

// PCSS 半影半径：遮挡物离接收点越远，半影越宽；这是软阴影看起来有距离感的原因。
// `lightSize` 是光源在阴影图平面的相对尺寸，`projectorScale` 把世界尺寸换算成纹素。
float ogxPcssFilterRadius(float blockerDepth, float receiverDepth, float lightSize, float projectorScale)
{
    float gap = max(receiverDepth - blockerDepth, 0.0); // 遮挡物与接收点的深度差。
    return ogxSaturate(gap * projectorScale) * lightSize; // 深度差越大半影越宽，上限由光源尺寸给出。
}

// PCSS 软阴影：先用少量样本找遮挡物平均深度，再按半影宽度做百分比过滤。
// 为什么分两步：固定核宽会让远处的阴影过硬、近处的阴影过软，遮挡物搜索让核宽随距离变化。
// 采样用黄金角螺旋，样本分布均匀；`dither` 让相邻像素的旋转角不同，配合时间抗锯齿消除噪点。
float ogxPcssVisibility(sampler2D shadowMap, vec3 shadowCoord, float texelSize,
    float searchRadiusTexels, float filterRadiusTexels, float bias, int searchSteps, int filterSteps, float dither)
{
    vec2 rot = vec2(cos(dither * 6.28318530718), sin(dither * 6.28318530718)); // 起始旋转角按抖动错开。
    float blockerSum = 0.0; // 遮挡物深度累加。
    float blockerCount = 0.0; // 遮挡物样本数。
    float searchRadius = searchRadiusTexels * texelSize; // 遮挡物搜索半径，换算到纹理坐标。
    for (int i = 0; i < searchSteps; i++) // 第一步：找遮挡物。
    {
        rot = vec2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                     -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 每步旋转黄金角。
        float radius = sqrt((float(i) + 0.5) / float(searchSteps)) * searchRadius; // 圆面均匀分布的半径。
        float sampleDepth = textureLod(shadowMap, shadowCoord.xy + rot * radius, 0.0).x; // 读该点的最近深度。
        if (sampleDepth < shadowCoord.z - bias) // 只有比接收点更近的样本才是遮挡物。
        {
            blockerSum += sampleDepth; // 累加遮挡物深度。
            blockerCount += 1.0; // 计数。
        }
    }
    if (blockerCount < 0.5) // 没有遮挡物，说明这一点完全受光。
    {
        return 1.0;
    }
    float blockerDepth = blockerSum / blockerCount; // 平均遮挡物深度。
    float penumbra = ogxPcssFilterRadius(blockerDepth, shadowCoord.z, filterRadiusTexels, 40.0); // 半影宽度，纹素为单位。
    float filterRadius = max(penumbra, 1.0) * texelSize; // 至少一个纹素，避免完全退化成硬阴影。
    float visible = 0.0; // 受光样本数。
    for (int i = 0; i < filterSteps; i++) // 第二步：按半影宽度做百分比过滤。
    {
        rot = vec2(OGX_SHADOW_GOLDEN_COS * rot.x + OGX_SHADOW_GOLDEN_SIN * rot.y,
                     -OGX_SHADOW_GOLDEN_SIN * rot.x + OGX_SHADOW_GOLDEN_COS * rot.y); // 继续旋转同一个螺旋。
        float radius = sqrt((float(i) + 0.5) / float(filterSteps)) * filterRadius; // 过滤半径。
        float sampleDepth = textureLod(shadowMap, shadowCoord.xy + rot * radius, 0.0).x; // 读深度。
        visible += step(shadowCoord.z - bias, sampleDepth); // 接收点不深于该样本就算受光。
    }
    return visible / float(filterSteps); // 平均得到可见度。
}

#endif



// 一帧体积雾需要的相机、光照与天气参数。
struct OgxFogMedia
{
    vec3 camera_position; // 相机绝对世界位置。
    vec3 light_vector; // 指向光源的单位向量。
    vec3 light_color; // 直射光色。
    vec3 sky_color; // 天空环境光色。
    vec3 storm_color; // 暴风染色。
    vec3 biome_color; // 群系雾色。
    vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
    mat4 shadow_view; // 阴影相机视图。
    mat4 shadow_projection; // 阴影相机投影。
    vec2 cloud_shadow_screen; // 云影贴图所在画面的尺寸。
    vec2 cloud_shadow_texel; // 云影贴图画面的像素大小。
    float wetness; // 零到一的湿润度。
    float eye_skylight; // 天空光平滑值。
    float time_midnight; // 午夜强度。
    float time_factor; // 雾的时间因子。
    float density_scale; // 时段与每日天气给出的密度标度。
    float base_density; // 基础密度，已由效果层按远裁剪面或远景距离换算。
    float storm_strength; // 雪暴与沙暴的总强度。
    float snow_storm; // 雪暴强度，决定暴风雾是否随高度变淡。
    float daily_fog; // 每日天气的匀雾密度。
    float storm_density; // 暴风雾浓度选项。
    float storm_height; // 暴风雾起始高度。
    float storm_time; // 暴风噪声的滚动时间，单位秒。
    float wind_time; // 团雾随风移动的时间，已按云速换算。
    float global_cloud_shadow; // 整个场景共用的粗粒度云影。
    float shadow_map_resolution; // 阴影图像素边长。
    float shadow_bias; // 阴影坐标边缘压缩强度。
    float cloud_shadow_range; // 云影贴图覆盖范围，米。
    float cloud_shadow_tex_size; // 云影贴图最大边长。
    float rain_shadow; // 雨天的云影底值。
    float biome_coverage; // 落在已启用群系内的程度。
    float biome_height; // 群系高度衰减雾密度。
    float biome_cloudy; // 群系团雾密度。
    float lightning_intensity; // 闪电事件强度。
    float lightning_strength; // 闪电亮度选项。
    float sky_intensity; // 天光强度选项。
    float sun_intensity; // 阳光强度选项。
    float fog_density_option; // 环境雾强度选项。
    float sun_density_option; // 散射强度选项。
};

// 云影贴图的三次采样：取红通道，与云影写入端同一套模糊。
// 四次双线性采样合成十六像素三次模糊，纹理读取次数只有逐像素方案的四分之一。
float ogxFogCloudBicubic(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个纹素的大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 前两个权重。
    vec4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return mix(mix(textureLod(source, c.yw, 0.0).x, textureLod(source, c.xw, 0.0).x, m.x),
                mix(textureLod(source, c.yz, 0.0).x, textureLod(source, c.xz, 0.0).x, m.x), m.y); // 四次采样合成模糊。
}

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float ogxFogCloudShadow(vec3 worldPos, OgxFogMedia media, sampler2D cloudShadowTex, bool fadeByAngle)
{
    vec2 coord = worldPos.xz - media.light_vector.xz * ((worldPos.y + media.camera_position.y) / media.light_vector.y); // 沿光方向投到云影贴图平面。
    coord = coord * (1.0 / media.cloud_shadow_range) + 0.5; // 换成零到一的贴图坐标。
    float cloudShadow = 1.0 - media.wetness; // 雨天默认的云影底值。
    if (ogxEqual(ogxSaturate(coord), coord)) // 只有落在贴图范围内才采样。
    {
        float shadowTexSize = floor(min(media.cloud_shadow_screen.y * 0.45, media.cloud_shadow_tex_size)); // 云影贴图实际边长。
        vec2 shadowTexel = media.cloud_shadow_screen - coord * shadowTexSize; // 贴图贴在画面右上角，坐标要翻转。
        vec2 fade = ogxSaturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
        cloudShadow = mix(cloudShadow, ogxFogCloudBicubic(cloudShadowTex, shadowTexel * media.cloud_shadow_texel, media.cloud_shadow_screen), fade.x * fade.y); // 三次采样并淡出。
    }
    if (fadeByAngle) // 太阳越贴地云影越淡。
    {
        float fadeAngle = smoothstep(0.06, 0.18, abs(media.light_vector.y)); // 光方向越平越淡。
        cloudShadow = mix(1.0 - media.wetness, cloudShadow, fadeAngle * fadeAngle); // 按淡出权重混合。
    }
    return ((media.rain_shadow - 1.0) * media.wetness + 1.0) * cloudShadow + (media.wetness - media.rain_shadow * media.wetness); // 晴天与雨天两档之间插值。
}

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
float ogxFogStormDensity(vec3 worldPos, OgxFogMedia media, sampler2D noiseTexture)
{
    vec3 scroll = vec3(media.storm_time, 0.0, media.storm_time) * 15.0; // 随时间在横纵方向滚动。
    vec3 samplePos = (worldPos * vec3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量。
    float noise = 1.0 - ogxStormNoise(samplePos, noiseTexture, 512.0); // 取反，让噪声高的地方雾更浓。
    float heightFade = exp2(-0.06 * max(worldPos.y - (media.storm_height + 3.0), 0.0)); // 起始高度以上缓慢变淡。
    float denseCloud = noise * noise * mix(1.0, heightFade, media.snow_storm); // 噪声雾团。
    return 1.0 + denseCloud + media.daily_fog; // 低空层与噪声雾团相加。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
vec3 ogxFogLightning(vec3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
    vec3 boltPos = vec3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
    float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return vec3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
float ogxFogDensity(vec3 fogPos, vec3 wind, bool noisy, float heightA, float heightB, float falloff, float timeMidnight, sampler2D noiseTexture)
{
    return noisy
        ? ogxFogDensityNoise(fogPos, wind, heightA, heightB, falloff, timeMidnight, noiseTexture)
        : ogxFogDensityHeight(fogPos, heightA, heightB, falloff, timeMidnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
float ogxFogLightMarch(inout vec3 fogPos, vec3 wind, OgxFogMedia media, bool noisy, float heightA, float heightB, float falloff, sampler2D noiseTexture, int steps, float stepLength)
{
    float lightingDensity = 0.0; // 沿光方向累计的密度。
    for (int i = 0; i < steps; i++, fogPos += media.light_vector * stepLength, stepLength *= 1.5) // 沿光方向步进，步长逐步放大。
    {
        lightingDensity += ogxFogDensity(fogPos, wind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture) * stepLength; // 累加这一段密度。
    }
    return lightingDensity; // 返回累计密度。
}

// 体积雾主体：沿视线步进，同时沿光方向估遮挡，累加雾色与阳光散射。
// `dither` 是这一步的抖动；`volumetricLighting` 由效果层按体积光照开关选择单级或多级散射。
void ogxVolumetricFog(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir, OgxFogMedia media,
    sampler2D noiseTexture, sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0,
    sampler2D cloudShadowTex, bool noisy, bool volumetricLighting, bool useCloudShadow, bool useStained, bool useSolidShadow, bool indoor, bool caveMode,
    float heightA, float heightB, float falloff, float sunAbsorption, int steps, int lightSteps, float lightStepLength, float dither,
    out float transmittance)
{
    float timeFactor = media.time_factor * (noisy ? 1.0 : media.time_midnight * 2.0 + 1.0); // 仅高度衰减模式夜晚雾更浓。
    vec3 start = startPos + media.camera_position; // 起点换成绝对世界坐标。
    vec3 end = endPos + media.camera_position; // 终点同样换成绝对世界坐标。
    vec3 rayVector = end - start; // 从起点到终点的矢量。
    float rayLength = length(rayVector) / float(steps) * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。
    vec3 shadowStart = ogxShadowScreenPos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
    vec3 shadowEnd = ogxShadowScreenPos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
    vec3 shadowVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。
    vec3 stormWind = noisy ? vec3(-1.0, -0.05, 0.6) * media.wind_time : vec3(0.0); // 团雾按风移动。
    transmittance = 1.0; // 透射率从全透开始。
    float fogDensity = 0.0; // 环境雾累计量。
    float rayDensity = 0.0; // 阳光散射累计量。
    vec3 lightningFog = vec3(0.0); // 闪电点亮的空气。
    vec3 lpvFog = vec3(0.0); // 雾照明累计量，由宏注入。
    vec3 translucent = vec3(0.0); // 透过半透明方块的染色光。
    for (int i = 0; i < steps; i++) // 沿视线逐步前进。
    {
        float exponential = pow(11.0, (float(i) + dither) / float(steps)); // 指数步长因子。
        float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
        float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度。
        vec3 fogPos = start + stepLength * rayVector; // 这一步的雾采样位置。
        vec3 shadowPos = shadowStart + stepLength * shadowVector; // 这一步的阴影图坐标。
        vec3 lightningStep = ogxFogLightning(fogPos - media.camera_position, media, 150.0, -15.0); // 闪电照亮空气。
        float biomeDistance = length((stepLength * rayVector).xz); // 这一步相对起点的水平距离。
        float biomeEnvelope = min(max(1.0 - biomeDistance / 256.0, 0.0) * 2.0, 1.0); // 二百五十六米内替换最明显。
        float densityScale = mix(media.density_scale, media.biome_height, media.biome_coverage * biomeEnvelope); // 群系高度雾密度。
        if (noisy) densityScale = mix(media.density_scale, media.biome_cloudy, media.biome_coverage * biomeEnvelope); // 团雾取多云那套。
        float density = ogxFogDensity(fogPos, stormWind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture); // 这一点的雾密度。
        density = (density * densityScale + media.base_density) * timeFactor; // 乘密度标度与时间因子。
        density += ogxFogStormDensity(fogPos, media, noiseTexture) * media.storm_strength * media.storm_density; // 暴风额外浓雾。
        float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。
        float stepRayDensity = 0.0; // 这一步的阳光散射量。
        if (volumetricLighting) // 沿阳光方向估吸收。
        {
            float lightingDensity = ogxFogLightMarch(fogPos, stormWind, media, noisy, heightA, heightB, falloff, noiseTexture, lightSteps, lightStepLength); // 沿光方向累计密度。
            lightingDensity = (lightingDensity * sunAbsorption * densityScale + media.base_density) * timeFactor; // 乘吸收率与密度标度。
            float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。
            vec4 phases = ogxMultiScatteringPhases(dot(worldDir, media.light_vector)); // 一次算好四级相位。
            float order = 1.0; // 多级相位的权重。
            for (int j = 0; j < 4; j++, order *= 0.5) stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 四级散射加权求和。
            stepRayDensity *= ogxLegacyPowder(absorption, lightingAbsorption, dot(worldDir, media.light_vector)); // 乘粉末效应。
        }
        else // 单级前向相位。
        {
            stepRayDensity = ogxMiePhase(0.5, dot(worldDir, media.light_vector)) * 0.7 + 0.05;
        }
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, media.shadow_bias); // 阴影图坐标补上边缘压缩。
        float shadow = 1.0; // 这一点受不受阳光。
        vec3 shadowColorSample = vec3(1.0); // 该点半透明染色。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 坐标落在阴影图内才采样。
        {
            ivec2 shadowTexel = ivec2(shadowPos.xy * media.shadow_map_resolution); // 换成阴影图纹素。
            float solidDepth = useSolidShadow ? texelFetch(shadowDepth1, shadowTexel, 0).x : texelFetch(shadowDepth0, shadowTexel, 0).x; // 按显卡能力选深度图。
            shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
            if (useStained) // 半透明染色。
            {
                float transparentDepth = texelFetch(shadowDepth0, shadowTexel, 0).x; // 读半透明深度。
                shadowColorSample = ogxGammaToLinear(texelFetch(shadowColor0, shadowTexel, 0).rgb); // 读半透明颜色。
                float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。
                shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
                shadow -= transparentShadow; // 从受光里扣掉半透明遮挡。
            }
        }
        float cloudShadow = 1.0; // 云影默认不压暗。
        if (useCloudShadow) cloudShadow = ogxFogCloudShadow(fogPos - media.camera_position, media, cloudShadowTex, false); // 读该点云影。
        float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
        stepRayDensity *= integral; // 散射量按吸收缩放。
        if (useCloudShadow) // 有云影时雾色也按云影压暗。
        {
            stepRayDensity *= mix(cloudShadow, 1.0, media.wetness * 0.1 + 0.03); // 散射按云影压暗。
            fogDensity += integral * mix(cloudShadow, 1.0, media.wetness * 0.3 + 0.7); // 环境雾按云影压暗。
        }
        else // 没有云影时直接累加。
        {
            fogDensity += integral; // 直接累加。
        }
        rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。
        if (useStained) translucent += stepRayDensity * shadowColorSample; // 累加染色散射。
        transmittance *= absorption; // 透射率逐步衰减。
        lightningFog += lightningStep * integral; // 闪电按吸收量累加。
        bool lpvDone = false; // 雾照明走出体积时提前结束。
        GFX_FOG_LPV_STEP(fogPos, integral, lpvFog, lpvDone) // 由效果层决定是否采样体积光。
        if (lpvDone) break; // 走出体积就不再步进。
    }
    vec3 skylight = media.sky_color; // 雾的环境色以天光为主。
    vec3 skySun = media.light_color * 0.03; // 雾里的一点点直射光。
    skylight += skySun * (1.0 + (1.0 - media.global_cloud_shadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
    skylight = mix(skylight, skySun, media.wetness * 0.7); // 雨天偏向直射色。
    vec3 fogColor = skylight * fogDensity; // 环境雾色。
    vec3 rayColor = media.light_color * rayDensity; // 阳光散射色。
    fogColor *= media.storm_color; // 暴风染色。
    rayColor *= media.storm_color; // 阳光散射同样染色。
    vec3 biomeTint = mix(vec3(1.0), media.biome_color, media.biome_coverage); // 群系雾色。
    fogColor *= biomeTint; // 环境雾染成群系色。
    rayColor *= biomeTint; // 阳光散射同样染色。
    rayColor += media.light_color * translucent; // 叠上透过半透明方块的染色光。
    fogColor *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
    rayColor *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
    if (!useCloudShadow) rayColor *= mix(media.global_cloud_shadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
    if (!indoor) // 体积雾随天空光等级衰减。
    {
        fogColor *= media.eye_skylight; // 环境雾按天空光衰减。
        if (caveMode) rayColor *= media.eye_skylight; // 洞穴模式下散射也衰减。
        lightningFog *= media.eye_skylight; // 闪电来自天空。
        transmittance = mix(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
    }
    color = transmittance * color + fogColor + rayColor + lightningFog + lpvFog; // 场景色先被吸收，再叠上雾与散射。
}

// 水下焦散：从当前位置向上找水面，按波法线折射后取交点距离，距离越近光柱越强。
// 为什么单独一份：它与水面焦散的三乘三采样用途不同，这里只要一份范围很窄的值来收窄光柱。
float ogxUnderwaterCaustics(vec3 worldPos, vec3 shadowLightVector, sampler2D normalTexture,
    vec2 pixelSize, vec2 screenExtent, float maxResolution, float refractIor)
{
    vec3 lookupCenter = worldPos; // 从当前位置向上找波面。
    lookupCenter.y += 1.0; // 抬高一米到水面上方。
    vec3 wavesNormal = ogxWavesNormalFromTex(lookupCenter, shadowLightVector, normalTexture,
        pixelSize, screenExtent, maxResolution, refractIor).xzy; // 读波法线并换到竖直轴朝上的坐标。
    vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal, 1.0); // 竖直光线被波面折射后的方向。
    vec3 collisionPoint = lookupCenter - refractVector / refractVector.y; // 光线与水平面的交点。
    float dist = distance(collisionPoint, worldPos); // 交点到当前点的距离。
    return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}

// 水下体积雾：沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向、云影、相机位置、阴影图与波法线图；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
vec3 ogxUnderwaterFog(vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow,
    vec3 cameraOffset, vec3 shadowLightVector, sampler2D shadowDepth0, sampler2D shadowDepth1,
    bool useSolidShadow, mat4 shadowView, mat4 shadowProjection, float shadowBias,
    sampler2D waveNormalTexture, vec2 pixelSize, vec2 screenExtent, float causticsResolution, float causticsIor,
    vec3 sunColor, float sunIntensity, float underwaterDensity, int steps, float dither,
    bool waterAbsorption, float waterDensity, float handLightScale)
{
    const float range = 40.0; // 光柱的累积范围。
    float startDist = length(startPos); // 起点到相机的距离。
    if (startDist > range) return vec3(0.0); // 起点已经在范围外，不画光柱。
    endPos = mix(worldDir * range, endPos, step(length(endPos), range)); // 终点超过范围就截断到范围内。
    float rayDist = distance(startPos, endPos); // 这条射线在范围里的长度。
    vec3 rayDir = (endPos - startPos) / rayDist; // 射线方向。
    float stepLength = range / float(steps); // 每段长度。
    vec3 result = vec3(0.0); // 累加的光柱颜色。
    vec3 handFog = vec3(0.0); // 累加的手持光颜色。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float rayLength = (i + dither) * stepLength; // 当前位置，起点加抖动量。
        vec3 rayPos = startPos + rayDir * rayLength; // 相机相对世界位置。
        if (startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停止。
        vec3 shadowPos = ogxShadowScreenPosDistorted(rayPos + cameraOffset, shadowView, shadowProjection, shadowBias); // 投到阴影图，含边缘压缩。
        float shadowDepth = useSolidShadow ? textureLod(shadowDepth1, shadowPos.xy, 0.0).x : textureLod(shadowDepth0, shadowPos.xy, 0.0).x; // 按显卡能力选深度图。
        vec3 shadow = vec3(step(shadowPos.z + 1e-06, shadowDepth)); // 受光则由深度图判定。
        rayLength += startDist; // 距离补上起点偏移。
        float caustics = ogxUnderwaterCaustics(rayPos + cameraOffset, shadowLightVector, waveNormalTexture,
            pixelSize, screenExtent, causticsResolution, causticsIor); // 该点焦散强度。
        shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
        shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
        if (waterAbsorption) shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * waterDensity)); // 红衰减最快，光柱因此偏蓝。
        result += shadow; // 累加。
        vec3 handLight = GFX_UNDERWATER_HAND_LIGHT(rayPos); // 手持光源在该点留下的光，由效果层注入。
        if (waterAbsorption) handLight *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * waterDensity)); // 与光柱同一套分波段吸收。
        handFog += handLight; // 累加。
    }
    result *= range / float(steps); // 取平均。
    vec3 lightVector = refract(shadowLightVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
    float lightDotView = dot(lightVector, worldDir); // 光方向与视线的夹角。
    float phase = ogxMiePhase(0.7, lightDotView); // 前向相位，正对阳光时更亮。
    result *= sunColor * (0.04 * phase * sunIntensity * underwaterDensity); // 乘直射光色、相位与强度。
    if (waterAbsorption) result *= vec3(0.2, 0.65, 1.0); // 有水下雾时把光柱染成水色。
    result *= globalCloudShadow; // 按全局云影压暗。
    result += handFog * (range / float(steps)) * handLightScale; // 手持光不随阳光相位与云影变化，最后叠上。
    return result; // 返回光柱颜色。
}

// Eclipse 下界三段体积雾：羽流、雾霭与顶部烟在同一条视线上分开累加。
// 为什么分三段：羽流发光、雾霭只加色不吸光、顶部烟贴天花板，三者的密度来源与混合方式都不同。
// `cameraOffset` 是相机相对世界的原点，`cameraWorldPos` 是绝对世界位置，雾噪声需要绝对坐标。
// `maxDist` 是步进距离上限，`farPlane` 是羽流随距离淡出用的远裁剪面，两者在参考实现里不是同一个值。
// `hazeColor` 由调用方按当前下界雾色给出，`outputScale` 把散射换算到目标管线单位。
vec4 ogxNetherVolumetricFog(vec3 rayDirection, vec3 cameraOffset, vec3 cameraWorldPos,
    float startDist, float endDist, float ditherA, float ditherB, int samples, float expFactor, float maxDist, float farPlane,
    float plumeDensityScale, float hazeDensityScale, float ceilingDensityScale, vec3 hazeColor,
    float outputScale, float time, sampler2D noiseTexture)
{
    endDist = min(endDist, maxDist); // 最远只步进到参考实现的距离上限。
    float rayLength = endDist - startDist; // 这一段视线的长度。
    if (rayLength <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0); // 空段或反向段直接返回。
    vec3 segment = rayDirection * rayLength; // 整段的相机相对世界向量。
    float dL = rayLength; // 光学厚度的段长。
    vec3 base = cameraOffset + rayDirection * startDist; // 相机相对世界里的起点。
    vec3 color = vec3(0.0); // 累加的散射色。
    float absorbance = 1.0; // 剩余透射率，从全透开始。
    for (int i = 0; i < samples; i++) // 沿这一段逐步前进。
    {
        float d = (pow(expFactor, (float(i) + ditherB) / float(samples)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 指数步长在段上的位置。
        float dd = pow(expFactor, (float(i) + ditherA) / float(samples)) * log(expFactor) / float(samples) / (expFactor - 1.0); // 这一步的厚度权重。
        vec3 relPos = base + d * segment; // 采样点的相机相对位置。
        float dist = length(relPos); // 到相机的距离。
        vec3 worldPos = relPos + cameraWorldPos; // 绝对世界位置，体积噪声要它。
        float densityVol = ogxNetherFogCloudVolume(worldPos, time, noiseTexture); // 这一点的原始体积密度。
        float clearArea = 1.0 - min(max(1.0 - dist / 24.0, 0.0), 1.0); // 相机二十四米内淡出。
        float plume = min(densityVol * pow(min(max(100.0 - worldPos.y, 0.0) / 30.0, 1.0), 4.0), pow(clamp(1.0 - dist / farPlane, 0.0, 1.0), 5.0)); // 越低越浓、越远越淡。
        plume *= plumeDensityScale; // 乘羽流密度选项。
        float plumeCoeff = exp(-plume * dd * dL); // 羽流吸收掉的光。
        vec3 plumeLight = vec3(1.0, 0.4, 0.2) * 0.25 * exp(-15.0 * densityVol) * (clearArea * clearArea * 0.9 + 0.1); // 暖橙色，密度高处压暗。
        color += (plumeLight - plumeLight * plumeCoeff) * absorbance; // 叠上羽流散射。
        absorbance *= plumeCoeff; // 透射率下降。
        float hazeDensity = 0.001 * hazeDensityScale; // 很低的均匀密度。
        float hazeCoeff = exp(-hazeDensity * dd * dL); // 雾霭吸收。
        color += (hazeColor - hazeColor * hazeCoeff) * absorbance; // 只加散射，不回乘透射率。
        float ceilingDensity = 0.001 * pow(min(max(worldPos.y - 40.0, 0.0) / 50.0, 1.0), 3.0) * ceilingDensityScale; // 越高越浓。
        float ceilingCoeff = exp(-ceilingDensity * dd * dL); // 顶部烟吸收。
        vec3 ceilingSmoke = vec3(0.1); // 固定灰烟颜色。
        color += (ceilingSmoke - ceilingSmoke * ceilingCoeff) * (absorbance * 0.5 + 0.5); // 半强度叠加。
        absorbance *= ceilingCoeff; // 透射率继续下降。
    }
    return vec4(color * outputScale, absorbance); // 返回换算后的散射色与剩余透射率。
}

#endif


/*
生成文件：全局光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库全局光模块：地平线遮蔽、反射阴影图反弹、历史重投影、时间与空间滤波。
调用位置：任何需要屏幕空间全局光或环境遮蔽的程序；Minecraft 光影由 `/omni-gfx/gi.glsl` 引入。
可复制示例：
    `float ao = ogxGroundTruthAo(viewPos, viewDir, normal, coord, aspect, depthTex, dhTex, projection, projectionInverse, dhInverse, params, noise);` 一帧的地平线遮蔽。
    `vec3 bounce = ogxAoMultiBounce(ao, albedo);` 给遮蔽补一次多弹射。
    `vec3 filtered = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);` 七乘七空间滤波。
设计原因与取舍：
    纹理、矩阵、相机位置与选项全部由调用方传入，库不读取引擎状态；`OgxGiView` 把同一帧的
    相机与屏幕参数打包，避免每个函数重复十几项。算法与旧 `shaders/gfx/gi.glsl` 逐项一致，
    迁移只改名字和语法，默认画面因此不变；地平线遮蔽的采样仍由调用方负责，这里只做纯数学。
*/
#ifndef OGX_GI_INCLUDED
#define OGX_GI_INCLUDED

// 饱和、快速反余弦、曲线编码与噪声来自数学模块；阴影投影来自阴影模块。


// 螺旋采样的黄金角正余弦：每步旋转这个角度，样本沿螺旋均匀铺开。
const float OGX_GI_GOLDEN_COS = -0.737368878;
const float OGX_GI_GOLDEN_SIN = 0.675490294;

// 一帧全局光需要的相机、投影与屏幕参数；字段名保持普通图形术语，不绑定任何宿主。
struct OgxGiView
{
    mat4 projection_inverse; // 近景逆投影。
    mat4 previous_projection; // 上一帧投影。
    mat4 model_view_inverse; // 视空间转世界。
    mat4 previous_model_view; // 上一帧世界转视空间。
    mat4 model_view; // 本帧世界转视空间。
    mat4 shadow_view; // 阴影相机视图。
    mat4 shadow_projection; // 阴影相机投影。
    mat4 dh_projection_inverse; // 远景逆投影；没有远景时填近景值占位。
    mat3 shadow_normal; // 法线从世界转到阴影相机。
    vec3 camera_position; // 本帧相机世界位置。
    vec3 previous_camera_position; // 上一帧相机世界位置。
    vec2 screen_size; // 画面像素尺寸。
    vec2 texel_size; // 一个像素的屏幕坐标大小。
};

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。
vec3 ogxAoMultiBounce(float ao, vec3 albedo)
{
    vec3 a = 2.0404 * albedo - 0.3324; // 一次项系数。
    vec3 b = -4.7951 * albedo + 0.6417; // 二次项系数。
    vec3 c = 2.7552 * albedo + 0.6903; // 三次项系数。
    return max(vec3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}

// 双边升采样：把半分辨率的遮蔽（或任何四通道画面）放大到全分辨率。
// 四个相邻纹素先按深度筛一次：只有与参考深度相差不超过阈值的样本参与，物体边界不会被糊开。
// 为什么不用普通双线性：半分辨率的一格盖住全分辨率两格，边界处会把前景与背景混成一条灰边。
// `pixel` 是全分辨率像素坐标，`upscale` 是遮蔽图相对全分辨率的倍数（通常为二）；
// `referenceDepth` 与 `sourceDepth` 必须用同一套深度单位，阈值也按这套单位给出。
vec4 ogxBilateralUpscale(sampler2D source, sampler2D sourceDepth, ivec2 pixel, int upscale,
    float referenceDepth, float depthThreshold)
{
    ivec2 base = pixel / upscale; // 当前像素落在遮蔽图的哪一格。
    vec4 result = vec4(0.0); // 加权颜色。
    float sum = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 四个相邻格，正好围住这一格。
    {
        ivec2 offset = ivec2(i < 2 ? -1 : 0, (i == 0 || i == 3) ? -1 : 0); // 四个格子的相对位置。
        ivec2 cell = base + offset; // 邻格坐标。
        float sampleDepth = texelFetch(sourceDepth, cell, 0).r; // 邻格的深度。
        float weight = abs(sampleDepth - referenceDepth) < depthThreshold ? 1.0 : 1e-5; // 深度相近才参与。
        result += texelFetch(source, cell, 0) * weight; // 累加颜色。
        sum += weight; // 累加权重。
    }
    return result / sum; // 归一化；四个样本全被拒绝时权重和仍然大于零。
}

// 屏幕坐标与深度还原视空间位置，不撤销抖动；重投影需要原始位置。
vec3 ogxGiViewPos(vec2 coord, float depth, mat4 projection_inverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec3 pos = vec3(vec2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projection_inverse); // 只用逆投影的非零项与平移列。
    return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 远景屏幕坐标与深度还原视空间位置；没有远景时调用方不会走到这里。
vec3 ogxGiViewPosDh(vec2 coord, float depth, mat4 dh_projection_inverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec4 pos = ogxMatrixMul(dh_projection_inverse, vec4(ndc, 1.0)); // 远景逆投影整矩阵乘法。
    return pos.xyz / pos.w; // 透视除法。
}

// 地平线遮蔽的参数：画质、半径模式、远景能力与强度都由调用方给出。
struct OgxGtaoParams
{
    float steps; // 环绕视线的切片数。
    float slice_steps; // 每个切片的搜索步数。
    float falloff_start; // 衰减起点，占半径的比例。
    float max_sample_radius; // 屏幕半径上限。
    float world_radius; // 世界半径模式下的起始半径。
    float screen_radius; // 屏幕半径模式下的固定半径。
    float strength; // 遮蔽强度，零为无遮蔽、一为全遮蔽。
    int radius_mode; // 零为世界半径，其他为屏幕半径。
    bool has_dh; // 是否有远景深度，决定世界半径随距离衰减的快慢。
    bool dh_ao; // 是否把远景样本当作遮挡物。
    bool falloff_z_offset; // 是否用深度加权的衰减距离。
};

// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 深度图、投影矩阵、画面坐标、比例与噪声全部由调用方传入，库不读取任何引擎画面。
float ogxGroundTruthAo(vec3 viewPos, vec3 viewDir, vec3 normal, vec2 coord, float aspect,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projection_inverse,
    mat4 dh_projection_inverse, OgxGtaoParams params, vec2 noise)
{
    float rSteps = 1.0 / params.steps; // 切片数倒数。
    float rSliceSteps = 1.0 / params.slice_steps; // 步数倒数。
    float projFactor = 0.125 * projection[1][1]; // 投影缩放系数。
    float radius; // 世界半径或屏幕半径。
    float sampleRadiusRaw; // 换算后的屏幕半径。
    float sampleRadius; // 夹紧后的屏幕半径。
    float falloff; // 衰减距离。
    if (params.radius_mode == 0) // 世界半径模式。
    {
        radius = params.world_radius - viewPos.z * (params.has_dh ? 0.02 : 0.01); // 有远景时衰减更慢。
        sampleRadiusRaw = radius * projFactor / -viewPos.z; // 换成屏幕半径。
        sampleRadius = min(sampleRadiusRaw, params.max_sample_radius); // 上限。
        falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
    }
    else // 屏幕半径模式。
    {
        sampleRadius = params.screen_radius; // 固定屏幕半径。
        falloff = sampleRadius / projFactor * -viewPos.z; // 换算成世界衰减距离。
    }
    float ao = 0.0; // 累积的遮蔽。
    float slice_steps = params.slice_steps; // 每个切片的搜索步数。
    for (float i = 0.0; i < params.steps; i++) // 逐切片。
    {
        float sliceAngle = (i + noise.x) * rSteps * OGX_PI; // 切片角度，只扫半圈因为两侧对称。
        vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        vec3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 切片方向正交到视线的分量。
        vec3 axis = cross(sliceDir, viewDir); // 切片平面法向。
        vec3 projNormal = normal - dot(normal, axis) * axis; // 法线投影到切片平面。
        float rProjNormalLength = inversesqrt(dot(projNormal, projNormal)); // 投影长度倒数。
        float cosNormalAngle = ogxSaturate(dot(projNormal, viewDir) * rProjNormalLength); // 投影法线与视线夹角余弦。
        float normalAngle = sign(dot(orthoSliceDir, projNormal)) * ogxFastAcos(cosNormalAngle); // 带符号的法线角。
        vec2 minCosHorizonAngle = cos(vec2(normalAngle + OGX_HALF_PI, normalAngle - OGX_HALF_PI)); // 两侧地平线角的下限。
        vec2 maxCosHorizonAngle = minCosHorizonAngle; // 两侧可见地平线角的初值。
        for (float j = 0.0; j < slice_steps; j++) // 逐搜索步。
        {
            float stepNoise = (i + j * slice_steps) * 0.61803399; // 用黄金比错开各步。
            stepNoise = fract(stepNoise + noise.y); // 加噪声后取小数。
            float offset = (j + stepNoise) * rSliceSteps; // 归一化搜索距离。
            offset *= offset; // 平方让近处更密。
            vec2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
            sampleOffset.y *= aspect; // 修正宽高比。
            {
                vec2 sampleCoord = coord + sampleOffset; // 正向采样坐标。
                float sampleDepth = textureLod(depthTexture, sampleCoord, 0.0).x; // 采样深度。
                vec3 sampleVector; // 采样点相对当前点。
                if (params.has_dh && params.dh_ao && sampleDepth == 1.0) // 天空样本改读远景深度。
                {
                    sampleDepth = textureLod(dhDepthTexture, sampleCoord, 0.0).x; // 远景深度。
                    sampleVector = ogxGiViewPosDh(sampleCoord, sampleDepth, dh_projection_inverse) - viewPos; // 远景还原。
                }
                else // 近景样本正常还原。
                {
                    sampleVector = ogxGiViewPos(sampleCoord, sampleDepth, projection_inverse) - viewPos; // 近景还原。
                }
                float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
                float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
                float falloffWeight; // 衰减权重。
                if (params.falloff_z_offset) // 可选的深度加权。
                {
                    float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * 1.7)); // 加权距离。
                    falloffWeight = ogxRemapSaturate(offsetDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                else // 默认按距离加权。
                {
                    falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.x, falloffWeight); // 远处回落到下限。
                maxCosHorizonAngle.x = max(cosHorizonAngle, maxCosHorizonAngle.x); // 取可见地平线角。
            }
            {
                vec2 sampleCoord = coord - sampleOffset; // 反向采样坐标。
                float sampleDepth = textureLod(depthTexture, sampleCoord, 0.0).x; // 采样深度。
                vec3 sampleVector; // 采样点相对当前点。
                if (params.has_dh && params.dh_ao && sampleDepth == 1.0) // 天空样本改读远景深度。
                {
                    sampleDepth = textureLod(dhDepthTexture, sampleCoord, 0.0).x; // 远景深度。
                    sampleVector = ogxGiViewPosDh(sampleCoord, sampleDepth, dh_projection_inverse) - viewPos; // 远景还原。
                }
                else // 近景样本正常还原。
                {
                    sampleVector = ogxGiViewPos(sampleCoord, sampleDepth, projection_inverse) - viewPos; // 近景还原。
                }
                float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
                float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
                float falloffWeight; // 衰减权重。
                if (params.falloff_z_offset) // 可选的深度加权。
                {
                    float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * 1.7)); // 加权距离。
                    falloffWeight = ogxRemapSaturate(offsetDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                else // 默认按距离加权。
                {
                    falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.y, falloffWeight); // 远处回落到下限。
                maxCosHorizonAngle.y = max(cosHorizonAngle, maxCosHorizonAngle.y); // 取可见地平线角。
            }
        }
        maxCosHorizonAngle = vec2(-ogxFastAcos(maxCosHorizonAngle.y), ogxFastAcos(maxCosHorizonAngle.x)) * 2.0; // 两侧换成开口角。
        float horizonAngleIntegra = 2.0 * cosNormalAngle + (maxCosHorizonAngle.x + maxCosHorizonAngle.y) * sin(normalAngle) - cos(maxCosHorizonAngle.x - normalAngle) - cos(maxCosHorizonAngle.y - normalAngle); // 这一片的半球可见缺口。
        ao += horizonAngleIntegra / rProjNormalLength; // 累加。
    }
    ao *= 0.25 * rSteps; // 平均。
    return ogxSaturate(mix(1.0, ao, params.strength)); // 按强度在无遮蔽与遮蔽之间插值。
}

// 历史法线与深度采样：四个角按法线、距离和双线性权重混合，返回未归一化的历史反弹。
vec3 ogxGiHistorySample(vec3 currNormal, float currDist, vec3 cameraVelocity, vec2 prevCoord, float renderScale,
    sampler2D historyTexture, sampler2D normalTexture, vec2 screen_size, out float weightSum)
{
    vec2 prevTexel = floor(prevCoord); // 历史纹素整数部分。
    vec3 prevGi = vec3(0.0); // 累积历史反弹。
    weightSum = 0.0; // 权重和。
    for (int k = 0; k < 4; k++) // 左下、右下、左上、右上四个历史纹素。
    {
        vec2 sampleTexel = prevTexel + vec2(float(k >> 1), float(k & 1)); // 按下标拼出四个角。
        vec4 prevData = texelFetch(normalTexture, ivec2(sampleTexel.x + renderScale * screen_size.x, sampleTexel.y), 0); // 读历史法线深度。
        vec3 prevNormal = prevData.xyz * 2.0 - 1.0; // 还原历史法线。
        float normalWeight = float(dot(currNormal, prevNormal) > 0.5); // 法线相近才参与。
        float prevDist = prevData.a * 1000.0; // 历史距离。
        float depthWeight = max(abs(currDist - prevDist - cameraVelocity.z), 0.0); // 距离差。
        depthWeight = exp(-depthWeight / (currDist * 0.1 + 0.1)); // 差距越大权重越低。
        depthWeight = ogxSaturate(depthWeight * 2.0); // 放大后再收敛。
        float bilinearWeight = (1.0 - abs(prevCoord.x - sampleTexel.x)) * (1.0 - abs(prevCoord.y - sampleTexel.y)); // 双线性权重。
        bilinearWeight *= normalWeight * depthWeight; // 总权重。
        prevGi += ogxCurveToLinear3(texelFetch(historyTexture, ivec2(sampleTexel), 0).rgb) * bilinearWeight; // 累加解码后的历史反弹。
        weightSum += bilinearWeight; // 累加权重。
    }
    return prevGi; // 交回加权历史反弹。
}

// 反射阴影图反弹：从阴影图里可见的表面取底色，按法线朝向与距离给当前点补一份光。
// `useSolidShadow` 对应支持遮挡贴图的显卡，`leakFix` 对应主世界的阳光泄漏修正，`underwater` 是眼睛在水下。
vec3 ogxGiRsm(vec3 viewPos, vec3 normal, OgxGiView view,
    sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0, sampler2D shadowColor1,
    float radius, int steps, float falloff, float shadowMapResolution, float shadowBias, vec2 noise,
    bool useSolidShadow, bool leakFix, bool underwater)
{
    vec3 worldPos = ogxMatrixMulPoint(view.model_view_inverse, viewPos) + ogxMatrixTranslation(view.model_view_inverse); // 视空间位置换世界空间。
    vec3 shadowPosition = ogxShadowScreenPos(worldPos, view.shadow_view, view.shadow_projection); // 投到阴影图。
    vec3 shadow_normal = ogxMatrix3MulPoint(view.shadow_normal, normal); // 法线转到阴影相机空间；三乘三矩阵在调用方已经组合好。
    float pixelOffset = radius * view.shadow_projection[0][0]; // 搜索半径换成阴影图像素。
    float zScale = 1.0 / view.shadow_projection[0][0]; // 阴影深度的缩放系数。
    float angle = noise.x * 6.28318530718; // 起始旋转角。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    float rSteps = 1.0 / float(steps); // 采样次数倒数。
    vec3 rsm = vec3(0.0); // 累积的反弹颜色。
    for (int i = 0; i < steps; i++) // 螺旋逐点采样。
    {
        rot = vec2(OGX_GI_GOLDEN_COS * rot.x + OGX_GI_GOLDEN_SIN * rot.y,
                     -OGX_GI_GOLDEN_SIN * rot.x + OGX_GI_GOLDEN_COS * rot.y); // 每步旋转黄金角。
        float r = (float(i) + noise.y) * rSteps; // 归一化半径。
        vec2 offset = rot * r * pixelOffset; // 屏幕偏移。
        vec2 offsetPosition = shadowPosition.xy + offset; // 采样点的阴影图坐标。
        vec2 sampleCoord = ogxDistortShadowPos(offsetPosition, shadowBias); // 还原压缩后的坐标。
        ivec2 sampleTexel = ivec2(shadowMapResolution * sampleCoord); // 换成纹素。
        float sampleDepth = useSolidShadow ? texelFetch(shadowDepth1, sampleTexel, 0).x : texelFetch(shadowDepth0, sampleTexel, 0).x; // 按显卡能力选深度图。
        if (sampleDepth == 0.0 || sampleDepth >= 1.0) // 没有几何或超出范围就跳过。
        {
            continue;
        }
        vec3 sampleVector = vec3(offsetPosition, sampleDepth) - shadowPosition; // 采样点相对当前点。
        sampleVector *= vec3(zScale, zScale, -zScale * 2.0); // 修正到统一的深度尺度。
        vec3 sampleDir = normalize(sampleVector); // 采样方向。
        float nDotV = dot(sampleDir, shadow_normal); // 当前点法线与采样方向的夹角余弦。
        if (nDotV <= 0.0) // 背对采样点不接收。
        {
            continue;
        }
        vec4 sampleData = texelFetch(shadowColor1, sampleTexel, 0); // 读阴影图里的法线与天光。
        vec3 sampleNormal = sampleData.rgb * 2.0 - 1.0; // 还原采样点法线。
        float snDotV = dot(-sampleDir, sampleNormal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
        if (snDotV < 0.0) // 背对方向不发光。
        {
            continue;
        }
        vec3 sampleAlbedo = ogxGammaToLinear(texelFetch(shadowColor0, sampleTexel, 0).rgb); // 采样点底色转线性。
        sampleVector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
        float sampleDist = length(sampleVector); // 采样距离。
        float distFalloff = pow(sampleDist + 0.035, -falloff) * ogxFastSqrt(1.0 - r); // 距离衰减与中心加权。
        float lightMask = leakFix ? ogxSaturate(sampleData.a * 15.0 + float(underwater)) : 1.0; // 主世界只给接到天光或水里的点补光。
        rsm += sampleAlbedo * (nDotV * snDotV * distFalloff * lightMask); // 累加一份反弹。
    }
    rsm *= rSteps * radius * 0.1; // 平均并按半径缩放。
    return rsm; // 返回反弹颜色。
}

// 相机速度：区分远景与近景、手与世界，算出当前像素相对上一帧的屏幕位移。
vec2 ogxGiCameraVelocity(vec2 coord, float depth, bool isDh, float materialIds, OgxGiView view,
    bool disableHand, bool disablePlayer, float handDepth, float playerMaterial)
{
    vec3 screenPos = vec3(coord, depth); // 屏幕坐标加深度。
    vec3 projection = vec3(0.0); // 上一帧投影结果。
    if (isDh) // 远景像素用远景矩阵。
    {
        projection = vec3(vec2(view.dh_projection_inverse[0].x, view.dh_projection_inverse[1].y) * (screenPos * 2.0 - 1.0).xy, 0.0) + ogxMatrixTranslation(view.dh_projection_inverse); // 逆投影到视空间。
        projection /= view.dh_projection_inverse[2].w * (screenPos.z * 2.0 - 1.0) + view.dh_projection_inverse[3].w; // 透视除法。
        projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
        projection += view.camera_position - view.previous_camera_position; // 加相机世界位移。
        projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 世界转上一帧视空间。
    }
    else // 近景像素。
    {
        vec3 ndc = screenPos * 2.0 - 1.0; // 转负一到一。
        projection = vec3(vec2(view.projection_inverse[0].x, view.projection_inverse[1].y) * ndc.xy, 0.0) + ogxMatrixTranslation(view.projection_inverse); // 逆投影到视空间。
        projection /= view.projection_inverse[2].w * ndc.z + view.projection_inverse[3].w; // 透视除法。
        bool isPlayer = materialIds == playerMaterial; // 玩家像素标记。
        if (disableHand && disablePlayer) // 手和玩家都不参与重投影。
        {
            if (depth >= 0.7 && !isPlayer) // 非玩家且较远。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disableHand) // 只有手不参与。
        {
            if (depth >= 0.7) // 较远像素才重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disablePlayer) // 只有玩家不参与。
        {
            if (!isPlayer) // 非玩家像素。
            {
                if (depth < 0.7) // 手部固定深度偏移。
                {
                    projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
                }
                else // 其他近景像素正常重投影。
                {
                    projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                    projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                    projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
                }
            }
        }
        else // 都参与重投影。
        {
            if (depth < 0.7) // 手部固定位移。
            {
                projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
            }
            else // 其他近景像素正常重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
    }
    vec3 previousScreen = vec3(view.previous_projection[0].x, view.previous_projection[1].y, view.previous_projection[2].z) * projection + ogxMatrixTranslation(view.previous_projection); // 上一帧投影的缩放与平移项。
    previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 透视除法与零到一换算，除数用投影前的深度。
    return coord - previousScreen.xy; // 返回屏幕位移。
}

// 全局光时间滤波：本帧反弹与历史帧按法线、深度和运动量混合，同时把法线与距离写回历史图。
vec4 ogxGiTemporalFilter(vec2 coord, ivec2 texelCoord, OgxGiView view,
    sampler2D historyTexture, sampler2D normalTexture, sampler2D materialTexture, sampler2D depthTexture, sampler2D dhDepthTexture,
    sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0, sampler2D shadowColor1,
    float renderScale, bool has_dh, bool useDhAo, bool newVersion, bool leakFix, bool underwater,
    bool useSolidShadow, bool disableHand, bool disablePlayer, float handDepth, float playerMaterial,
    float radius, float falloff, int steps, float shadowMapResolution, float shadowBias, vec2 noise)
{
    vec4 prev = texelFetch(historyTexture, texelCoord, 0); // 先取历史像素。
    vec2 local = coord / renderScale; // 全局光渲染分辨率下的坐标。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        ivec2 texel = ivec2(local * view.screen_size); // 对应的屏幕纹素。
        float currDepth = texelFetch(depthTexture, texel, 0).x; // 本帧不透明深度。
        bool isDh = false; // 是否远景像素。
        if (has_dh && useDhAo && currDepth == 1.0) // 天空像素改读远景深度。
        {
            currDepth = texelFetch(dhDepthTexture, texel, 0).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (currDepth < 1.0) // 有几何才算反弹。
        {
            vec4 data3 = texelFetch(normalTexture, texel, 0); // 读法线光照图。
            vec3 currNormal = ogxDecodeNormal(data3.xy); // 解出本帧法线。
            vec3 currViewPos = ogxGiViewPos(local, currDepth, view.projection_inverse); // 还原视空间位置。
            if (isDh) // 远景用远景逆投影。
            {
                currViewPos = ogxGiViewPosDh(local, currDepth, view.dh_projection_inverse);
            }
            vec3 gi = vec3(0.0); // 本帧反弹。
            bool applyRsm = true; // 默认所有像素都反弹。
            if (newVersion) // 新版本按天光标记决定。
            {
                if (leakFix) // 只有接到天光或在水里才反弹。
                {
                    applyRsm = data3.w > 0.0 || underwater;
                }
            }
            else // 旧版本还要求像素足够远。
            {
                if (leakFix) // 较远且接到天光。
                {
                    applyRsm = currDepth > 0.7 && (data3.w > 0.0 || underwater);
                }
                else // 只要求较远。
                {
                    applyRsm = currDepth > 0.7;
                }
            }
            if (applyRsm) // 只有需要反弹的像素才采样阴影图。
            {
                gi = ogxGiRsm(currViewPos, currNormal, view, shadowDepth0, shadowDepth1, shadowColor0, shadowColor1,
                    radius, steps, falloff, shadowMapResolution, shadowBias, noise, useSolidShadow, leakFix, underwater); // 算一次反弹。
            }
            float materialIds = floor(texelFetch(materialTexture, texel, 0).b * 255.0); // 读材质编号。
            vec2 velocity = ogxGiCameraVelocity(local, currDepth, isDh, materialIds, view, disableHand, disablePlayer, handDepth, playerMaterial); // 屏幕位移。
            vec2 prevCoord = local - velocity; // 映射到上一帧坐标。
            vec2 clamped = clamp(prevCoord, vec2(0.0), vec2(1.0) - view.texel_size * 2.0); // 夹到画面内。
            if (ogxEqual(clamped, prevCoord)) // 历史坐标有效才做滤波。
            {
                vec2 prevTexelCoord = prevCoord * renderScale * view.screen_size - 0.5; // 换成历史纹素坐标。
                float currDist = min(-currViewPos.z, 1000.0); // 本帧到相机的距离，限长避免远处权重异常。
                vec3 cameraVelocity = ogxMatrixMulPoint(view.model_view, view.camera_position - view.previous_camera_position); // 相机速度转到视空间。
                float weightSum = 0.0; // 权重和。
                vec3 prevGi = ogxGiHistorySample(currNormal, currDist, cameraVelocity, prevTexelCoord, renderScale,
                    historyTexture, normalTexture, view.screen_size, weightSum); // 取上一帧加权历史反弹。
                gi = mix(gi, prevGi, 0.95 * weightSum); // 与历史混合。
            }
            prev = vec4(ogxLinearToCurve3(gi), 0.0); // 编码回历史格式。
        }
    }
    local.x -= 1.0; // 顶行左侧一格存法线与距离。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        ivec2 texel = ivec2(floor(local * view.screen_size)); // 对应的屏幕纹素。
        float depth = texelFetch(depthTexture, texel, 0).x; // 不透明深度。
        bool isDh = false; // 远景标记。
        if (has_dh && useDhAo && depth == 1.0) // 天空像素改读远景深度。
        {
            depth = texelFetch(dhDepthTexture, texel, 0).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (depth < 1.0) // 有几何才写历史数据。
        {
            vec3 normal = ogxDecodeNormal(texelFetch(normalTexture, texel, 0).xy); // 解法线。
            float dist = 1.0 / ((depth * 2.0 - 1.0) * view.projection_inverse[2][3] + view.projection_inverse[3][3]); // 深度换米制距离。
            if (isDh) // 远景换算。
            {
                dist = 1.0 / ((depth * 2.0 - 1.0) * view.dh_projection_inverse[2][3] + view.dh_projection_inverse[3][3]);
            }
            prev = vec4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
        }
        else // 天空像素没有有效历史。
        {
            prev = vec4(vec3(0.5), 0.0); // 写入中性值。
        }
    }
    return prev; // 返回本帧要写回历史图的数据。
}

// 七乘七邻域偏移按行列下标现算：x 从负三到三，y 同样，按行优先排列。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
vec3 ogxGiSpatialFilter(vec2 coord, float dist, vec3 normal, vec3 viewDir, OgxGiView view, sampler2D historyTexture, float renderScale)
{
    vec2 local = coord * renderScale; // 全局光分辨率下的坐标。
    float weights = 0.0; // 权重和。
    vec3 gi = vec3(0.0); // 累积的反弹颜色。
    float clampedDist = min(dist, 1000.0); // 距离限长。
    float b = clampedDist * 0.001 + 0.025; // 深度阈值里的中间量。
    float depthThreshold = min(0.1 + clampedDist * 0.05, 1.1) + ogxSaturate(1.0 - abs(dot(normal, viewDir)) / b) * 10.0; // 掠射角放宽深度阈值。
    vec2 border = vec2(renderScale) - view.texel_size * 2.0; // 边界。
    vec2 offsetScale = view.texel_size * 4.0 * renderScale; // 邻域步长。
    for (int i = 0; i < 49; i++) // 遍历四十九个邻点。
    {
        vec2 sampleCoord = clamp(local + vec2(float((i % 7) - 3), float((i / 7) - 3)) * offsetScale, vec2(0.0), border); // 采样坐标。
        float weight = length(vec2(float((i % 7) - 3), float((i / 7) - 3))); // 按到中心的距离算权重。
        weight = exp2(-weight * weight * 0.1); // 高斯权重。
        vec4 sampleData = textureLod(historyTexture, sampleCoord + vec2(renderScale, 0.0), 0.0); // 读历史法线深度。
        vec3 sampleNormal = sampleData.xyz * 2.0 - 1.0; // 还原法线。
        float normalWeight = abs(dot(normal, sampleNormal)); // 法线相近度。
        normalWeight = pow(normalWeight, 64.0); // 高次方只保留很接近的。
        float depthWeight = ogxSaturate(-abs(sampleData.w * 1000.0 - clampedDist) + depthThreshold); // 深度相近度。
        weight = weight * normalWeight * depthWeight + 1e-20; // 总权重，加极小值避免全零。
        gi += ogxCurveToLinear3(textureLod(historyTexture, sampleCoord, 0.0).rgb) * weight; // 累加解码后的反弹。
        weights += weight; // 累加权重。
    }
    return ogxLinearToCurve3(gi / weights); // 平均后编码返回。
}

#endif

/*
生成文件：反射模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库反射模块：可见法线采样、屏幕空间追踪、反射方向、菲涅耳合并与小波滤波。
调用位置：任何需要屏幕空间反射的程序；Minecraft 光影由 `/omni-gfx/reflection.glsl` 引入。
可复制示例：
    `vec3 d = ogxSampleGgxVndf(viewVector, roughness, noise);` 生成一条模糊反射方向。
    `bool ok = ogxScreenSpaceTrace(origin, dir, ndotv, noise, minLength, false, screenPos, depthTex, handTex, dhTex, projection, projectionInverse, dhInverse, 0.05, true, false, false, 24, 4, 0.02);` 屏幕空间追踪。
    `ogxReflectionAtrousFilter(data, viewPos, viewDir, normal, roughness, 40.0, noise, uv, reflTex, depthTex, normalTex, pixelSize, projectionInverse);` 九点降噪。
设计原因与取舍：
    深度图、投影、光色与天空都由参数传入，库不读取引擎状态；主机特有的天空兜底、体素回退与
    反射雾仍留在 `shaders/gfx/reflection.glsl` 的合成流程里，那里只做开关组合，不再含采样循环。
    公式与旧实现逐项一致；矩阵乘法在 Slang 与 GLSL 的行列解释不同，统一走数学模块的显式展开。
*/
#ifndef OGX_REFLECTION_INCLUDED
#define OGX_REFLECTION_INCLUDED

// 饱和、曲线编码、菲涅耳与法线解码来自数学模块。

// 一个完整圆周，采样角度与旋转都用它。
const float OGX_TAU = 6.28318530718;

// 可见法线分布采样：按粗糙度把反射方向散开，得到模糊反射。
vec3 ogxSampleGgxVndf(vec3 viewVector, float roughness, vec2 noise)
{
    vec3 orthoNormal = normalize(vec3(roughness * viewVector.xy, viewVector.z)); // 把视线按粗糙度压成一个辅助轴。
    float length2 = dot(orthoNormal.xy, orthoNormal.xy); // 水平分量的长度平方。
    vec3 orthoTangent = length2 > 0.0 ? vec3(-orthoNormal.y, orthoNormal.x, 0.0) * inversesqrt(length2) : vec3(1.0, 0.0, 0.0); // 水平切线。
    vec3 orthoBitangent = cross(orthoNormal, orthoTangent); // 副切线。
    float radius = sqrt(noise.y * 0.7); // 采样半径，取平方根让样本落在圆内。
    float angle = OGX_TAU * noise.x; // 采样角度。
    vec2 samplePos = vec2(cos(angle), sin(angle)) * radius; // 圆上的采样位置。
    float scaling = orthoNormal.z * 0.5 + 0.5; // 沿竖直方向把圆压成椭圆。
    samplePos.y = (1.0 - scaling) * sqrt(1.0 - samplePos.x * samplePos.x) + scaling * samplePos.y; // 投影到椭圆上。
    vec3 sampleVector = samplePos.x * orthoTangent + samplePos.y * orthoBitangent + sqrt(max(0.0, 1.0 - dot(samplePos, samplePos))) * orthoNormal; // 合成三维方向。
    return normalize(vec3(roughness * sampleVector.xy, max(sampleVector.z, 0.0))); // 按粗糙度压扁并归一化。
}

// 屏幕坐标与深度还原视空间位置；屏幕空间追踪算射线起点与命中点时用。
vec3 ogxReflectionViewPos(vec2 coord, float depth, mat4 projectionInverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec3 pos = vec3(vec2(projectionInverse[0][0], projectionInverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projectionInverse); // 只用逆投影的非零项与平移列。
    return pos / (projectionInverse[2][3] * ndc.z + projectionInverse[3][3]); // 透视除法。
}

// 视空间位置投到屏幕，不补抖动；追踪射线用原始投影。
vec3 ogxReflectionScreenPos(vec3 viewPos, mat4 projection)
{
    vec3 pos = vec3(projection[0][0], projection[1][1], projection[2][2]) * viewPos + ogxMatrixTranslation(projection); // 投影矩阵的非零项与平移列。
    return pos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
}

// 屏幕深度换米制距离。
float ogxReflectionLinearDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度。
float ogxReflectionScreenDepth(float depth, mat4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景深度换成同一距离在近景投影下的深度。
float ogxReflectionDhToScreenDepth(float depth, mat4 dhProjectionInverse, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 远景深度转到负一到一。
    depth = 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 先换成米。
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 再用近景投影换回深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 读追踪采样点的深度：手部优先手部图，近景是天空时按开关改读远景。
float ogxReflectionSampleDepth(vec2 coord, bool isHand, bool handSupported, sampler2D depthTexture, sampler2D handDepthTexture,
    sampler2D dhDepthTexture, bool hasDh, bool dhSsr, mat4 dhProjectionInverse, mat4 projectionInverse)
{
    if (handSupported && isHand) // 手部读不含玩家的深度。
    {
        return textureLod(handDepthTexture, coord, 0.0).x;
    }
    float depth = textureLod(depthTexture, coord, 0.0).x; // 其他像素读普通不透明深度。
    if (hasDh && dhSsr && depth == 1.0) // 天空像素按开关改读远景。
    {
        depth = ogxReflectionDhToScreenDepth(textureLod(dhDepthTexture, coord, 0.0).x, dhProjectionInverse, projectionInverse); // 远景深度换到近景尺度。
    }
    return depth; // 返回该坐标的深度。
}

// 屏幕空间追踪：从起点沿反射方向在屏幕里步进，撞到比射线更近的几何就命中。
// 命中后二分细化，避免粗步长跨过薄几何；屏幕外的方向没有可靠深度，直接停止。
bool ogxScreenSpaceTrace(vec3 viewRayOri, vec3 viewRayDir, float ndotv, float noise, float minLength, bool isHand, inout vec3 screenPos,
    sampler2D depthTexture, sampler2D handDepthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float nearPlane, bool handSupported, bool hasDh, bool dhSsr, int quality, int refinementSteps, float zDiffThreshold)
{
    float rSteps = 1.0 / float(quality); // 步数的倒数，用作归一化步长。
    float viewRayLength = (-nearPlane - viewRayOri.z) / viewRayDir.z + step(viewRayDir.z, 0.0) * 1e20; // 射线到近裁剪面的长度，背向时给极远值。
    vec3 rayDir = normalize(ogxReflectionScreenPos(viewRayOri + viewRayDir * viewRayLength, projection) - screenPos); // 屏幕坐标下的射线方向。
    float minStepLength = minLength * rSteps; // 最小步长按质量缩放。
    float stepLength = mix(minStepLength, rSteps, ndotv); // 正对视线时步长更大，掠射时更小。
    float zScaling = abs(1.0 / rayDir.z); // 深度方向的缩放。
    bool hit = false; // 命中标记。
    float maxDepth = hasDh ? ogxReflectionScreenDepth(ogxReflectionLinearDepth(1.0, dhProjectionInverse), projectionInverse) : 1.0; // 有远景时步进上限是远景最远距离。
    screenPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少规则条纹。
    float depth = ogxReflectionSampleDepth(screenPos.xy, false, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
        hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 读起始点深度。
    for (int i = 0; i < quality + 3; i++) // 最多走质量加三次，多出的几次用于边界收尾。
    {
        if (!ogxEqual(ogxSaturate(screenPos.xy), screenPos.xy)) // 出了屏幕就停止。
        {
            break;
        }
        if (screenPos.z >= maxDepth) // 射线到达最远处。
        {
            hit = depth >= maxDepth; // 该处也是尽头才算命中。
            break;
        }
        else if (screenPos.z < 0.7 && !isHand) // 射线跑到相机很近的地方，后面没有可靠深度。
        {
            break;
        }
        if (depth < screenPos.z) // 几何深度比射线更近，说明可能撞上几何。
        {
            vec3 refineDir = rayDir * stepLength * 0.5; // 细化步长，从半步开始逐次减半。
            for (int j = 0; j < refinementSteps; j++, refineDir *= 0.5) // 二分细化交点。
            {
                screenPos += refineDir * (step(screenPos.z, depth) * 2.0 - 1.0); // 越过就回退半步，没越过就前进半步。
                depth = ogxReflectionSampleDepth(screenPos.xy, isHand, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
                    hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 重读该点深度。
            }
            if (depth > screenPos.z) // 细化后几何又跑到后面，这一步不算命中。
            {
                continue;
            }
            float stepDist = ogxReflectionLinearDepth(screenPos.z, projectionInverse); // 射线点的米制距离。
            float sampleDist = ogxReflectionLinearDepth(depth, projectionInverse); // 几何点的米制距离。
            float distDiff = abs(sampleDist - stepDist) / stepDist; // 两点的相对深度差。
            if (distDiff < zDiffThreshold && screenPos.z > 0.0 && screenPos.z < maxDepth) // 差足够小且深度有效才算命中。
            {
                hit = true;
                break;
            }
        }
        stepLength = clamp(abs(depth - screenPos.z) * zScaling, minStepLength, rSteps); // 按深度差自适应下一步长度。
        screenPos += rayDir * stepLength; // 前进一步。
        depth = ogxReflectionSampleDepth(screenPos.xy, false, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
            hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 读新位置的深度。
    }
    return hit; // 返回是否命中。
}

// 生成反射方向：光滑面直接反射，粗糙面先按可见法线抽样再反射。
vec3 ogxReflectionDir(vec3 viewDir, vec3 normal, float roughness, vec2 noise, bool isSmooth)
{
    if (isSmooth) // 镜面方向。
    {
        return reflect(viewDir, normal);
    }
    vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
    vec3 tangentAxis = cross(normalUp, normal); // 切线基第一列。
    vec3 bitangentAxis = normalUp; // 切线基第二列。
    vec3 viewTangent = vec3(dot(viewDir, tangentAxis), dot(viewDir, bitangentAxis), dot(viewDir, normal)); // 视线转到切线空间。
    vec3 visibleNormal = ogxSampleGgxVndf(-viewTangent, roughness, noise); // 抽样一个可见法线。
    vec3 worldNormal = tangentAxis * visibleNormal.x + bitangentAxis * visibleNormal.y + normal * visibleNormal.z; // 换回世界空间。
    return reflect(viewDir, worldNormal); // 沿可见法线反射。
}

// 读场景颜色并换回线性；反射颜色统一用这个入口，编码格式只有一处。
vec3 ogxReflectionSceneColor(sampler2D sceneTexture, vec2 coord)
{
    return ogxCurveToLinear3(textureLod(sceneTexture, coord, 0.0).rgb); // 曲线编码转线性。
}

// 天空回退的朝向权重：面越朝上，接收的天空越多；朝下时保留四分之一，避免全黑。
float ogxReflectionSkyFacing(float normalUp)
{
    return ogxSaturate((normalUp + 0.7) * 2.0) * 0.75 + 0.25; // 与天空光在地面的分布一致。
}

// 命中点到表面的距离：命中点深度从深度图或射线深度取，单位是米。
float ogxReflectionHitLength(vec3 viewPos, vec3 hitViewPos)
{
    return distance(hitViewPos, viewPos); // 命中点与表面之间隔着多少空气。
}

// 把反射颜色按菲涅耳、金属度与水吸收混进场景色；`notTotal` 为假时是全反射像素，直接取反射色。
void ogxSpecularReflectionMix(inout vec3 color, vec3 viewDir, vec3 normal, vec3 albedo, float waterAbsorption, vec3 reflection,
    bool notTotal, float metalness, float roughness, float f0, float reflectionStrength, bool overworld)
{
    if (!notTotal) // 全反射像素直接取反射色。
    {
        color = reflection; // 表面看不到外面的东西。
        return;
    }
    reflection *= mix(vec3(1.0), albedo, vec3(metalness)); // 金属面用底色给反射染色。
    vec3 l = normalize(reflect(viewDir, normal) + normal * roughness); // 反射方向按粗糙度偏一点。
    vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
    float lDotH = ogxSaturate(dot(l, h)); // 反射与半程夹角。
    float nDotL = ogxSaturate(dot(normal, l)); // 反射方向的入射余弦。
    float nDotV = ogxSaturate(dot(normal, -viewDir)); // 视线方向的入射余弦。
    float specular = ogxFresnelSchlick(lDotH, f0, 1.0); // 菲涅耳。
    specular *= ogxVisibilitySchlick(nDotL, nDotV + 0.8, roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
    specular *= reflectionStrength; // 乘材质允许的反射强度。
    specular = mix(specular, 1.0, metalness); // 金属面反射权重拉满。
    vec3 temp = color; // 记下原底色，金属面要再加一份。
    float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
    diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
    specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。
    if (overworld) // 主世界按水吸收缩反射权重。
    {
        color = mix(color, reflection, ogxSaturate(specular * waterAbsorption)); // 混合反射。
        color += temp * (metalness * waterAbsorption); // 金属面再加一份底色。
    }
    else // 下界末地按反射权重混合。
    {
        color = mix(color, reflection, ogxSaturate(specular)); // 混合反射。
        color += temp * metalness; // 金属面再加一份底色。
    }
}

// 反射小波滤波：九点邻域按反射方向与深度相似度加权，抹掉追踪噪点同时保住反射边界。
// 为什么按法线与深度加权：命中点落在不同法线或不同深度的邻居属于别的物体，混进来会把反射糊成一片。
// 为什么先按亮度幂次重整再还原：高动态范围的反射点会盖住整片邻域，先压一下亮度再合并，边界更干净。
void ogxReflectionAtrousFilter(inout vec4 reflectionData, vec3 viewPos, vec3 viewDir, vec3 normal,
    float roughness, float radius, vec2 noise, vec2 texCoord, sampler2D reflectionTexture,
    sampler2D depthTexture, sampler2D normalTexture, vec2 pixelSize, mat4 projectionInverse)
{
    float linearDepth = -viewPos.z; // 表面的米制深度。
    float ndotv = ogxSaturate(dot(-viewDir, normal)); // 视线与法线夹角余弦。
    roughness = max(roughness, 1e-4); // 粗糙度给一个下限，避免除以零。
    radius *= min(roughness * 20.0, 1.0); // 越粗糙反射越糊，滤波半径越大。
    radius *= reflectionData.a * 0.9 + 0.1; // 命中距离越远半径越大。
    vec2 tangent = normalize(cross(normal, viewDir).xy) * radius; // 沿表面切向的采样步长。
    vec2 bitangent = vec2(tangent.y, -tangent.x); // 副切向：旋转九十度，写法与旧矩阵乘法等价。
    tangent *= mix(0.1075, 0.5, ndotv) * pixelSize; // 切向按视角缩放并换成屏幕坐标。
    bitangent *= mix(0.7, 0.5, ndotv) * pixelSize; // 副切向同理。
    vec3 reflectedDir = reflect(-viewDir, normal); // 当前像素的反射方向。
    float normalThreshold = 75.0 / roughness; // 法线相似度的幂次，越粗糙越严。
    float luminanceThreshold = reflectionData.a * 0.95 + 0.05; // 亮度重整的幂次，按命中距离变化。
    vec4 accum = vec4(0.0); // 加权累加的反射数据。
    float weights = 0.0; // 累加权重。
    for (int i = 0; i < 9; i++) // 遍历九个邻点。
    {
        vec2 offset = vec2(float((i % 3) - 1), float((i / 3) - 1)); // 三乘三邻域偏移，按行优先排列。
        vec2 sampleCoord = texCoord + tangent * (offset + noise.x) + bitangent * (offset + noise.y); // 邻点坐标，按抖动微调。
        vec4 sampleData = textureLod(reflectionTexture, sampleCoord, 0.0); // 读邻点反射数据。
        if (sampleData.a < 0.0001) // 邻点没有反射，跳过。
        {
            continue;
        }
        float sampleDepth = ogxReflectionLinearDepth(textureLod(depthTexture, sampleCoord, 0.0).x, projectionInverse); // 邻点米制深度。
        vec3 sampleReflected = reflect(-viewDir, ogxDecodeNormal(textureLod(normalTexture, sampleCoord, 0.0).xy)); // 邻点反射方向。
        float normalWeight = pow(ogxSaturate(dot(sampleReflected, reflectedDir)), normalThreshold); // 反射方向越接近权重越大。
        float depthWeight = exp2(-(abs(sampleDepth - linearDepth) * 1.58)); // 深度越接近权重越大。
        float sampleWeight = normalWeight * depthWeight; // 两个权重相乘。
        sampleData.rgb += 1e-13; // 避免零亮度在下面除法里出问题。
        float luminance = length(sampleData.rgb); // 邻点亮度。
        sampleData.rgb *= pow(luminance, luminanceThreshold) / luminance; // 按幂次重整亮度。
        accum += sampleData * sampleWeight; // 按权重累加。
        weights += sampleWeight; // 累加权重。
    }
    if (weights > 1e-13) // 有有效邻点才写回。
    {
        accum /= weights; // 取加权平均。
        accum.rgb += 1e-13; // 同样避免零亮度。
        float luminance = length(accum.rgb); // 平均后的亮度。
        accum.rgb *= pow(luminance, 1.0 / luminanceThreshold) / luminance; // 还原亮度重整。
        reflectionData = accum; // 写回滤波结果。
    }
}

#endif

/*
生成文件：后期模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库后期模块：泛光降采样与模糊、三次升采样、亮度曲线、暗角、颗粒、景深与测光统计。
调用位置：任何需要多级泛光、景深或最终画面处理的程序；Minecraft 光影由 `/omni-gfx/post.glsl` 引入。
可复制示例：
    `vec3 c = ogxBloomDownsample(source, uv, texel);` 十三样本降采样。
    `vec3 c = ogxBloomChainCopy(chain, uv, size);` 链上某级原样拷贝。
    `vec3 b = ogxAxialGaussianBlur(source, uv, scale, origin, size, axis, 0.12, 6.0, texel);` 一维高斯。
    `float r = ogxCocRadius(focus, depth, aperture);` 薄透镜弥散圆半径。
    `float avg = ogxExposureTileAverage(sceneTexture, params);` 加权平均亮度。
设计原因与取舍：
    纹理、像素大小、子图范围与模糊参数全部由调用方传入，库不读取引擎画面或屏幕尺寸。
    伽马编码沿用管线的四次方根近似，保证与原程序相同的亮度；五级泛光的子图排布属于宿主布局，
    仍留在 `shaders/gfx/post.glsl` 的组合函数里，这里只提供每一级的核与统计公式。
*/
#ifndef OGX_POST_INCLUDED
#define OGX_POST_INCLUDED

// 亮度权重、四次方根编码与区间重映射来自数学模块。

// 抖动要用噪声模块里的三角分布噪声。

// 十三样本降采样：中心小、四角大，权重和为四，输出乘四分之一保持亮度。
vec3 ogxBloomDownsample(sampler2D source, vec2 coord, vec2 texel)
{
    vec3 blur = ogxCurveToLinear3(textureLod(source, coord, 0.0).rgb) * 0.125; // 中心样本。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(texel.x, texel.y), 0.0).rgb) * 0.5; // 右下对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(texel.x, -texel.y), 0.0).rgb) * 0.5; // 右上对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(-texel.x, texel.y), 0.0).rgb) * 0.5; // 左下对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + vec2(-texel.x, -texel.y), 0.0).rgb) * 0.5; // 左上对角。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, 0.0), 0.0).rgb) * 0.25; // 右两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(0.0, texel.y), 0.0).rgb) * 0.25; // 上两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, 0.0), 0.0).rgb) * 0.25; // 左两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(0.0, -texel.y), 0.0).rgb) * 0.25; // 下两像素。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, texel.y), 0.0).rgb) * 0.125; // 远处右下。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处右上。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, texel.y), 0.0).rgb) * 0.125; // 远处左下。
    blur += ogxCurveToLinear3(textureLod(source, coord + 2.0 * vec2(-texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处左上。
    return ogxLinearToCurve3(blur * 0.25); // 权重和为四，乘四分之一保持亮度。
}

// 泛光链某一级的原样拷贝：坐标夹在这级子图范围里，零号层级读取后换回线性。
// 为什么单独成一个函数：链上第二级的边界判断由宿主决定，但“夹紧后读一次”是纯计算，
// 原程序在每个方向上各写一遍，迁进库后只保留一份。
vec3 ogxBloomChainCopy(sampler2D chain, vec2 local, vec2 originSize)
{
    vec2 coord = clamp(local, vec2(0.0), originSize); // 先夹紧，再把结果交给取样。
    return ogxCurveToLinear3(textureLod(chain, coord, 0.0).rgb); // 零号层级读取后换回线性。
}

// 沿一个方向做长条高斯，横竖各一次等价于二维高斯，样本数从平方降到线性。
vec3 ogxAxialGaussianBlur(sampler2D source, vec2 coord, vec2 coordScale, float sampleOrigin, vec2 sampleSize, vec2 axis,
    float alpha, float steps, vec2 texel)
{
    vec3 blur = vec3(0.0); // 累积颜色。
    float weights = 0.0; // 累积权重。
    for (float i = -steps; i <= steps; i++) // 从负步长到正步长。
    {
        float sampleWeight = exp2(-i * i * alpha * 5.77); // 高斯权重。
        vec2 sampleCoord = coord + axis / coordScale * texel * i * 2.0; // 当前方向的取样坐标。
        vec2 original = sampleCoord; // 记录原始坐标，用来判断是否越界。
        sampleCoord = clamp(sampleCoord, vec2(sampleOrigin, 0.0), vec2(sampleOrigin + sampleSize.x, sampleSize.y)); // 夹在当前级范围。
        sampleWeight *= float(ogxEqual(original, sampleCoord)) + 1e-20; // 被夹过的样本不参与。
        sampleCoord *= coordScale; // 还原成读取该级的坐标。
        blur += ogxCurveToLinear3(textureLod(source, sampleCoord, 0.0).rgb) * sampleWeight; // 累加样本。
        weights += sampleWeight; // 累加权重。
    }
    return blur / weights; // 归一化，样本少时亮度不变。
}

// 三次升采样：四次双线性采样合成十六像素的三次模糊。
vec4 ogxBloomBicubic(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 前两个权重。
    vec4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样的混合比例。
    return mix(mix(textureLod(source, vec2(c.y, c.w), 0.0), textureLod(source, vec2(c.x, c.w), 0.0), m.x),
                mix(textureLod(source, vec2(c.y, c.z), 0.0), textureLod(source, vec2(c.x, c.z), 0.0), m.x), m.y); // 四次采样合成模糊。
}

// 亮度曲线：暗部与亮部各一条抛物线，通道独立处理避免串色。
float ogxLowerCurve(float x)
{
    return clamp(16.0 * x * (0.5 - x) * 0.1, 0.0, 1.0); // 峰在四分之一附近。
}

// 亮部曲线：在亮端抬起一段抛物线。
float ogxUpperCurve(float x)
{
    return clamp(16.0 * (0.5 - x) * (x - 1.0) * 0.1, 0.0, 1.0); // 峰在四分之三附近。
}

// 把暗部与亮部修正同时加到三个通道，系数由调用方传入。
vec3 ogxLuminanceCurve(vec3 color, float lower, float upper)
{
    color.r += lower * ogxLowerCurve(color.r) + upper * ogxUpperCurve(color.r); // 红通道。
    color.g += lower * ogxLowerCurve(color.g) + upper * ogxUpperCurve(color.g); // 绿通道。
    color.b += lower * ogxLowerCurve(color.b) + upper * ogxUpperCurve(color.b); // 蓝通道。
    return color;
}

// 把三个通道归一化成染色方向；接近零时返回零，避免除零。
vec3 ogxGradeTarget(float red, float green, float blue)
{
    vec3 target = vec3(red, green, blue); // 原始目标向量。
    return length(target) < 0.001 ? vec3(0.0) : normalize(target); // 太短就没有方向。
}

// 暗角：按到画面中心的距离压暗四角，圆度控制椭圆与圆形之间的形状。
float ogxVignette(vec2 coord, float falloff, float roundness, float aspect)
{
    vec2 p = coord * 2.0 - 1.0; // 转负一到一。
    p.x *= mix(1.0, aspect, roundness); // 按圆度修正横坐标。
    float rf = dot(p, p) * falloff * falloff + 1.0; // 距离平方乘强度。
    return 1.0 / (rf * rf); // 二次衰减。
}

// 胶片颗粒：把屏幕坐标与时间合成种子，折成一个正负各半的细噪点加在颜色上。
vec3 ogxFilmGrain(vec3 color, vec2 coord, float time, float strength)
{
    float seed = (coord.x + 4.0) * (coord.y + 4.0) * (time * 10.0); // 屏幕坐标与时间合成种子，时间项让它逐帧变化。
    float flicker = ogxMod((ogxMod(seed, 13.0) + 1.0) * (ogxMod(seed, 123.0) + 1.0), 0.01) - 0.005; // 两次取模相乘再折叠成一个很小的数。
    return color + vec3(flicker) * strength; // 三个通道同量叠加，颗粒不改变颜色比例。
}

// 弥散圆半径：按薄透镜公式估算一个点离对焦平面越远时散焦多大。
float ogxCocRadius(float focus, float depth, float aperture)
{
    return abs(aperture * (depth - focus) / (depth * focus)); // 薄透镜近似。
}

// 浮点输出抖动：按目标格式的尾数位数，把三角噪声缩放到相邻两个可表示值之间。
// 为什么按指数缩放：浮点数的间隔随数值变大，固定步长会在大值处看不见、小值处过重。
vec3 ogxDitherFloat(vec3 color, vec2 coord, float time, vec3 mantissaBits)
{
    float dither = ogxTriangleNoise(coord, time);
    vec3 exponent = floor(log2(max(color, vec3(1e-20))));
    return color + dither * exp2(-mantissaBits) * exp2(exponent);
}

// 整数输出抖动：按目标格式的小数位数取固定步长，适合十六位或十位定点的中间画面。
vec3 ogxDitherFixed(vec3 color, vec2 coord, float time, float bits)
{
    return color + ogxTriangleNoise(coord, time) * exp2(-bits);
}

// 多边形光圈：把散焦偏移换成到多边形边的归一化距离，零在中心、一到边界。
// 为什么用角度求半径：多边形每条边的半径随角度变化，直接取到边的距离比圆形核更接近真实光圈。
float ogxBokehAperture(vec2 offset, int blades, float rotation)
{
    vec2 p = vec2(offset.x * cos(rotation) - offset.y * sin(rotation), offset.x * sin(rotation) + offset.y * cos(rotation)); // 先按光圈转角旋转。
    float radius = length(p); // 到中心的距离。
    if (radius < 1e-6) return 1.0; // 中心点始终在光圈内。
    float angle = ogxAtan2(p) + OGX_PI; // 角度换到零到二圆周率。
    float sector = OGX_PI * 2.0 / float(max(blades, 3)); // 每条边对应的圆心角。
    float edge = cos(sector * 0.5) / max(cos(ogxMod(angle, sector) - sector * 0.5), 1e-4); // 该角度上正多边形的半径。
    return ogxSaturate(radius / edge); // 归一到零到一，边界之外大于一。
}

// 景深镜头倍数：焦距平方乘口径倍数，焦距与光圈取基准值时正好为一。
float ogxDofLensFactor(float focalLength, float aperture, float referenceFocal, float referenceAperture)
{
    float focalRatio = focalLength / referenceFocal; // 焦距相对基准的倍数，越长越大。
    float apertureRatio = referenceAperture / aperture; // f 值越小口径越大，取倒数表示反比。
    return focalRatio * focalRatio * apertureRatio; // 焦距平方乘口径倍数，得到模糊倍数。
}

// 米制距离换回非线性屏幕深度；景深写回下界历史时需要这个反向换算。
float ogxScreenDepthFromLinearDepth(float depth, mat4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一的深度。
    return depth * 0.5 + 0.5; // 再转回零到一。
}

// 读一个坐标的米制深度；`useDh` 为真且近景没有几何时改读远景深度，再统一到近景尺度。
// 为什么把下限夹在换米制之前：近处深度趋近于零时薄透镜公式会爆炸，先夹屏幕深度最稳。
float ogxDofLinearDepth(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse,
    mat4 dhProjectionInverse, bool useDh)
{
    float depth = textureLod(depthTexture, coord, 0.0).x; // 读含半透明的近景深度。
    if (useDh && depth == 1.0) // 只有启用远景且近景是天空时才改读远景。
    {
        float dhDepth = textureLod(dhDepthTexture, coord, 0.0).x; // 读远景深度。
        float meters = 1.0 / ((dhDepth * 2.0 - 1.0) * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景深度换米制。
        depth = (1.0 / meters - projectionInverse[3][3]) / projectionInverse[2][3]; // 米制换到近景投影的负一到一深度。
        depth = clamp(depth * 0.5 + 0.5, 0.0, 1.0); // 转回零到一并夹紧。
    }
    depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
    return 1.0 / ((depth * 2.0 - 1.0) * projectionInverse[2][3] + projectionInverse[3][3]); // 换成米制距离。
}

// 前景弥散范围：在螺旋上找更近且弥散更大的样本，把它们的弥散并进当前点。
// 输入是当前点、焦距、模糊量、投影缩放、镜头倍数、最大弥散、画面比例与搜索次数；输出归一化弥散范围。
float ogxDofCocSpread(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse,
    mat4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale, float lensFactor,
    float maxCoc, float aspect, int steps, vec2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数：模糊量乘投影缩放与镜头倍数。
    float rMaxCoc = 1.0 / maxCoc; // 最大弥散的倒数，用来归一化。
    float rAspect = 1.0 / aspect; // 宽高比倒数，让椭圆散景在像素上是圆的。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点米制深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散半径。
    float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
    startRadius *= startRadius; // 平方，让搜索从中心附近开始。
    float spreadCoc = currCoc; // 弥散范围初值为当前点。
    float rSteps = 1.0 / float(steps); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角由噪声给出，避免固定图案。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < steps; i++) // 螺旋逐点搜索。
    {
        rot = vec2(-0.737368878 * rot.x + 0.675490294 * rot.y, -0.675490294 * rot.x - 0.737368878 * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt(startRadius + (float(i) + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
        vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        sampleOffset.x *= rAspect; // 按宽高比修正成圆。
        float sampleDepth = ogxDofLinearDepth(coord + sampleOffset, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        if (sampleCoc >= sampleRadius && sampleDepth <= currDepth) // 更近且弥散够大才并进来。
        {
            spreadCoc = max(spreadCoc, sampleCoc);
        }
    }
    return min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
}

// 景深散焦：按存下来的弥散范围在螺旋上取样，让更近且弥散够大的样本散到当前像素上。
// `storeDepth` 为真时把散焦后的深度一起写进透明度，供下界历史使用；屏幕深度由调用方投影矩阵换算。
vec4 ogxDepthOfField(vec2 coord, sampler2D colorTexture, sampler2D depthTexture, sampler2D dhDepthTexture,
    mat4 projectionInverse, mat4 dhProjectionInverse, bool useDh, float focus, float blur, float projectionScale,
    float lensFactor, float maxCoc, vec2 texel, float aspect, int quality, bool catEye, float catEyeMidpoint,
    float catEyeStrength, float anamorphic, float dispersion, bool storeDepth, vec2 noise)
{
    float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数，与弥散统计共用同一换算。
    float minCoc = 0.5641895835 * texel.y; // 一个像素大小的最小弥散，避免零半径时除零。
    float rAspect = 1.0 / aspect; // 宽高比倒数。
    float currDepth = ogxDofLinearDepth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点深度。
    float currCoc = ogxCocRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
    currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
    vec4 currData = textureLod(colorTexture, coord, 0.0); // 当前点的曲线编码颜色与弥散范围。
    float spreadCoc = currData.a * maxCoc; // 把存下来的范围还原成半径。
    float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
    centerWeight = mix(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点很清晰时把它自己压到极小。
    vec2 catEyeOffset = vec2(0.0); // 猫眼裁剪半径；关闭时保持零。
    if (catEye) // 只有开启猫眼效应才算裁剪。
    {
        catEyeOffset = coord * 2.0 - 1.0; // 从中心指向当前点。
        catEyeOffset.x *= aspect; // 按宽高比修正成圆。
        float catEyeDist = length(catEyeOffset); // 到中心的距离。
        catEyeDist = max(catEyeDist - catEyeMidpoint, 0.0); // 超过中点才开始裁剪。
        catEyeDist *= spreadCoc * catEyeStrength; // 按弥散与强度缩放。
        catEyeOffset = normalize(catEyeOffset) * catEyeDist; // 得到裁剪半径。
    }
    vec3 dof = vec3(0.0); // 散焦进来的颜色累加。
    float weights = 0.0; // 样本权重累加。
    vec3 selfColor = ogxCurveToLinear3(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
    float selfSamples = 1e-20; // 自计入样本数初值极小。
    float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
    float blendedDepth = 0.0; // 散焦后的深度累加。
    float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
    float rSteps = 1.0 / float(quality); // 步数倒数。
    float angle = noise.x * 6.28318530718; // 起始角。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    for (int i = 0; i < quality; i++) // 螺旋采样。
    {
        rot = vec2(-0.737368878 * rot.x + 0.675490294 * rot.y, -0.675490294 * rot.x - 0.737368878 * rot.y); // 每步旋转黄金角。
        float sampleRadius = sqrt((float(i) + noise.y) * rSteps) * spreadCoc; // 样本半径。
        vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
        if (catEye && distance(catEyeOffset, sampleOffset) > spreadCoc) // 超出猫眼裁剪半径就不采。
        {
            continue;
        }
        sampleOffset.x *= rAspect * anamorphic; // 按宽高比修正后再按变形比横向拉伸。
        vec2 sampleCoord = coord + sampleOffset; // 样本坐标。
        float sampleDepth = ogxDofLinearDepth(sampleCoord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
        float sampleCoc = ogxCocRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
        sampleCoc = clamp(sampleCoc, minCoc, maxCoc); // 夹到范围。
        vec3 sampleColor; // 样本线性颜色。
        if (dispersion != 1.0) // 色散开启时红蓝通道沿到中心的方向错开。
        {
            vec2 dispersionOffset = (coord - 0.5) * sampleRadius * (dispersion - 1.0); // 错开量随半径与到中心距离增大。
            sampleColor.r = ogxCurveToLinear(textureLod(colorTexture, sampleCoord + dispersionOffset, 0.0).r); // 红通道向外。
            sampleColor.g = ogxCurveToLinear(textureLod(colorTexture, sampleCoord, 0.0).g); // 绿通道不动。
            sampleColor.b = ogxCurveToLinear(textureLod(colorTexture, sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内。
        }
        else // 默认无色散只取一次样本。
        {
            sampleColor = ogxCurveToLinear3(textureLod(colorTexture, sampleCoord, 0.0).rgb); // 样本线性颜色。
        }
        float sampleWeight = max(1.0, currCoc / sampleCoc); // 近处前方样本权重更高。
        sampleWeight *= sampleWeight; // 平方加强。
        bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
        bool isBlurredSample = sampleCoc >= sampleRadius && sampleDepth < currDepth; // 更近且弥散够大，散焦进来。
        if (isSelfSample) // 属于当前点自己。
        {
            selfColor += sampleColor; // 记为自贡献。
            selfSamples += 1.0; // 自贡献样本数。
        }
        else if (isBlurredSample) // 散焦进来。
        {
            dof += sampleColor * sampleWeight; // 累加散焦颜色。
            weights += sampleWeight; // 累加权重。
        }
        else // 不满足条件，记进中心权重。
        {
            selfWeights += centerWeight; // 累加中心权重。
        }
        if (isSelfSample) // 自己的样本累加深度。
        {
            selfDepth += sampleDepth;
        }
        else if (isBlurredSample) // 散焦样本按权重累加深度。
        {
            blendedDepth += sampleDepth * sampleWeight;
        }
    }
    dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
    dof /= weights + selfSamples + selfWeights; // 归一化。
    if (!storeDepth) // 主世界与末地不写深度。
    {
        return vec4(ogxLinearToCurve3(dof), 0.0);
    }
    blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 下界把深度按同一套补偿。
    blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
    return vec4(ogxLinearToCurve3(dof), ogxScreenDepthFromLinearDepth(blendedDepth, projectionInverse)); // 返回颜色与换回的屏幕深度。
}

// 相机动态模糊：沿两帧之间的屏幕位移，在历史画面上取一串样本求平均。
// 为什么只做相机运动：没有实体速度缓冲，硬算会把静止物体也拖出鬼影，所以只处理整屏位移。
vec3 ogxMotionBlur(sampler2D colorTexture, vec2 coord, ivec2 texel, vec2 pixel, vec2 velocity,
    float shutterAngle, int quality, bool dither)
{
    if (length(velocity) < 5e-7) // 位移极小说明相机没动，直接取当前画面。
    {
        return ogxCurveToLinear3(texelFetch(colorTexture, texel, 0).rgb);
    }
    float shutter = shutterAngle / 720.0; // 快门角换算成拖影长度。
    velocity = clamp(velocity * shutter, vec2(-0.1), vec2(0.1)); // 限制单帧拖影上限。
    float steps = float(quality); // 一侧的采样步数。
    float samples = 0.0; // 有效样本计数。
    float offset = 0.0; // 采样抖动。
    if (dither) // 交错梯度噪声打散条纹。
    {
        offset = ogxInterleavedGradientNoise(pixel);
    }
    vec3 color = vec3(0.0); // 输出颜色。
    for (float i = -steps; i <= steps; i++) // 沿快门方向对称取样。
    {
        vec2 sampleCoord = coord + velocity / (steps + 1.0) * (i + offset); // 这个样本的坐标。
        if (ogxEqual(ogxSaturate(sampleCoord), sampleCoord)) // 坐标在画面内才采。
        {
            color += ogxCurveToLinear3(textureLod(colorTexture, sampleCoord, 0.0).rgb); // 累加历史颜色。
            samples++; // 计数。
        }
    }
    return color / samples; // 按有效样本数平均。
}

// 自动曝光分块统计的参数：屏幕尺寸、块大小、测光方式与亮度计权都由调用方给出。
// 字段名沿用光影侧写法，适配层因此只需要一次类型别名，不产生结构体拷贝。
struct OgxExposureParams
{
    vec2 screen_size; // 画面像素尺寸。
    vec2 pixel_size; // 一个像素在零到一坐标里的大小。
    int lod; // 多级纹理层级，决定一块覆盖多少像素。
    float luma_scale; // 管线亮度换算系数。
    float average; // 用一张粗样本估出的整体亮度，供亮度计权使用。
    int mode; // 测光方式：零默认、一中心权重、二只看中心、三全屏平均。
    int luminance_mode; // 亮度计权方式：零关闭，一到四对应四种曲线。
    float luminance_strength; // 亮度计权的强度。
    bool end_dimension; // 是否末地，末地默认测光不看中心。
    bool nether; // 是否下界，亮度计权在下界用固定指数。
    bool cave_mode; // 是否洞穴模式，洞穴按偏离整体亮度计权。
    bool overworld; // 是否主世界，亮度计权的指数范围与末地不同。
};

// 返回加权平均亮度，单位与输入画面一致；调用方再乘曝光输出系数并编码。
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
float ogxExposureTileAverage(sampler2D sceneTexture, OgxExposureParams params)
{
    float tileScale = exp2(float(params.lod)); // 一个块覆盖多少像素。
    vec2 tileCount = floor(params.screen_size / tileScale); // 每行每列有多少块。
    vec2 tileCenter = tileCount * 0.5; // 块网格的中心。
    float exposure = 0.0; // 加权亮度累加。
    float weights = 0.0; // 权重累加。
    for (int x = 0; x < int(tileCount.x); x++) // 逐列遍历块。
    {
        for (int y = 0; y < int(tileCount.y); y++) // 逐行遍历块。
        {
            float tileExposure = ogxLuminance(ogxCurveToLinear3(texelFetch(sceneTexture, ivec2(x, y), params.lod).rgb)) * params.luma_scale; // 这个块的亮度。
            vec2 tileDistance = (tileCenter - vec2(x, y) + 0.5) * params.pixel_size * tileScale * 2.0; // 块中心到画面中心的屏幕距离。
            float centerDistance = length(tileDistance); // 到画面中心的距离。
            float tileWeight = 1.0; // 块权重，先给等权。
            if (params.mode == 0) // 默认测光。
            {
                tileWeight = params.end_dimension ? 1.0 : ogxRemapSaturate(centerDistance, 0.6, 0.4); // 末地等权，其他维度越靠中心越高。
            }
            else if (params.mode == 1) // 中心权重较强。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.7, 0.0); // 中心权重曲线。
                tileWeight *= tileWeight; // 再平方，中心更突出。
            }
            else if (params.mode == 2) // 只看中心。
            {
                tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 与默认相同的曲线。
            }
            tileExposure = max(6.4e-9, tileExposure); // 避免全黑块把权重推到无穷。
            if (params.cave_mode && params.overworld) // 洞穴模式且在主世界时按偏离程度计权。
            {
                float caveWeight = params.average / tileExposure; // 相对整体亮度的比例。
                tileWeight *= pow(caveWeight, 0.7); // 越偏离整体亮度权重越大，适应洞穴。
            }
            else if (params.luminance_mode > 0) // 其他情况按亮度计权方式。
            {
                float lumaWeight = 1.0; // 相对亮度权重。
                if (params.luminance_mode == 1) // 预设一。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    if (params.nether) // 下界用固定指数。
                    {
                        lumaWeight = pow(lumaWeight, 0.7);
                    }
                    else if (params.overworld) // 主世界按整体亮度调指数。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.7); // 暗环境更偏向亮块。
                    }
                    else // 末地指数范围不同。
                    {
                        lumaWeight = pow(lumaWeight, ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地曲线。
                    }
                }
                else if (params.luminance_mode == 2) // 预设二。
                {
                    lumaWeight = params.average / tileExposure; // 相对亮度。
                    lumaWeight = pow(lumaWeight, params.nether ? 0.7 : ogxRemapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 下界固定，其余用较平的曲线。
                }
                else if (params.luminance_mode == 3) // 偏向暗部。
                {
                    lumaWeight = pow(params.average / tileExposure, params.luminance_strength); // 用选项给的强度。
                }
                else // 偏向高光。
                {
                    lumaWeight = pow(tileExposure / params.average, params.luminance_strength); // 比例取反。
                }
                tileWeight *= lumaWeight; // 把亮度权重乘进块权重。
            }
            exposure += tileExposure * tileWeight; // 累加加权亮度。
            weights += tileWeight; // 累加权重。
        }
    }
    return exposure / weights; // 加权平均。
}

// 镜头眩光：求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
// 先把偏移抬到三维再绕与中心垂直的轴旋转，最后取回二维，等价于绕画面中心弯折。
vec2 ogxGlareDistOffset(vec2 uv, vec2 pxoffset, float barrel)
{
    vec2 tocenter = uv.xy; // 当前点到中心的方向。
    vec3 prep = normalize(vec3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
    float angle = length(tocenter.xy) * 2.221 * barrel; // 旋转角随距离增大。
    vec3 oldoffset = vec3(pxoffset, 0.0); // 把偏移抬到三维。
    vec3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 取回二维偏移。
}

// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点。
// 色散量同时改变三个通道的半径，蓝光偏得最多，边缘因此出现彩边。
vec3 ogxGlareFlare(vec2 uv, vec2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxGlareDistOffset(uv, pos, barrel); // 先对鬼影位置做桶形畸变。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
    return vec3(r, g, b); // 返回带色散的光点颜色。
}

// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
// 越靠后的光斑越小、越暗，模拟镜头内部多次反射的能量损失。
vec3 ogxGlareOrb(vec2 uv, vec2 pos, float dist, float size, float barrel)
{
    float orbCount = 6.0; // 一组鬼影包含几个圆形光斑。
    vec3 c = vec3(0.0); // 累加结果。
    for (float i = 0.0; i < orbCount; i++) // 逐个光斑。
    {
        float j = i + 1.0; // 从一起数的序号。
        float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
        float colOffset = j / orbCount * 0.5; // 颜色偏移。
        float ss = size / (j + 1.0); // 越靠后的光斑越小。
        c += ogxGlareFlare(uv, pos, dist + offset, ss * 2.0, ss, barrel) * vec3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
    }
    c += ogxGlareFlare(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 末尾再补一个大的柔和光斑。
    return c; // 返回光斑颜色。
}

// 画一个环状光环，三个通道同样做色散。
// 坐标先乘自身长度，圆点就被拉成环；分母里的二百五十控制环的锐度。
vec3 ogxGlareRing(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur)
{
    vec2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿色通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
    return vec3(r, g, b); // 返回光环颜色。
}

#endif

/*
生成文件：抗锯齿模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库抗锯齿模块：YCoCg 颜色空间、历史邻域裁剪、三次采样与时间重投影。
调用位置：任何需要时间抗锯齿的程序；Minecraft 光影由 `/omni-gfx/antialias.glsl` 引入。
可复制示例：
    `vec3 y = ogxRgbToYCoCg(color);` 转到亮度与色差空间，亮度单独处理。
    `vec3 c = ogxClipAabb(avg, variance, history, true);` 把历史裁进当前邻域。
    `vec4 r = ogxTaaReproject(coord, velocity, depth, current, history, viewport, texel, projectionInverse, farPlane, jitter, 0.9, 1.0, 1e-4, false, false, true, false, false, referenceDepth);` 时间重投影。
设计原因与取舍：
    只做纯计算与显式采样，不读取历史画面或深度缓冲的全局名字；重投影的位移由调用方算好。
    YCoCg 让亮度与色差分开裁剪，避免高对比边缘出现彩边；算式与旧 `shaders/gfx/antialias.glsl` 一致。
    Slang 没有 GLSL 的按分量选择 `mix`，裁剪改成逐分量三元表达式，结果完全相同。
*/
#ifndef OGX_ANTIALIAS_INCLUDED
#define OGX_ANTIALIAS_INCLUDED

// 饱和、位打包与反余弦来自数学模块。

// 把线性颜色转到亮度与色差空间，亮度单独处理。
vec3 ogxRgbToYCoCg(vec3 color)
{
    return vec3(color.r * 0.25 + color.g * 0.5 + color.b * 0.25,
                  color.r * 0.5 - color.b * 0.5,
                  -color.r * 0.25 + color.g * 0.5 - color.b * 0.25); // 亮度与两个色差。
}

// 从亮度与色差空间换回线性颜色。
vec3 ogxYCoCgToRgb(vec3 color)
{
    float y = color.x; // 亮度。
    float co = color.y; // 橙到青的色差。
    float cg = color.z; // 绿到品红的色差。
    return vec3(y + co - cg, y + cg, y - co - cg); // 逆变换。
}

// 把历史颜色裁进当前三乘三邻域；`toCenter` 为真时朝中心拉，否则按分量分别裁剪。
vec3 ogxClipAabb(vec3 average, vec3 variance, vec3 history, bool toCenter)
{
    if (toCenter) // 朝邻域中心方向拉回，边缘不会出现单通道色斑。
    {
        float eps = 1e-20; // 极小量，避免除零。
        vec3 extent = variance - eps; // 范围半径。
        vec3 offset = history - average; // 历史相对中心的偏移。
        vec3 unit = abs(offset / extent); // 各通道越界比例。
        float maxUnit = max(unit.x, max(unit.y, unit.z)); // 最大越界比例。
        return maxUnit > 1.0 ? average + offset / maxUnit : history; // 沿原方向拉回边界。
    }
    vec3 diff = history - average; // 历史相对中心的偏移。
    vec3 clipMax = vec3(diff.x > variance.x ? variance.x / diff.x : 1.0,
                            diff.y > variance.y ? variance.y / diff.y : 1.0,
                            diff.z > variance.z ? variance.z / diff.z : 1.0); // 超出上界的比例。
    vec3 clipMin = vec3(diff.x < -variance.x ? -variance.x / diff.x : 1.0,
                            diff.y < -variance.y ? -variance.y / diff.y : 1.0,
                            diff.z < -variance.z ? -variance.z / diff.z : 1.0); // 超出下界的比例。
    diff *= clipMax.x * clipMax.y * clipMax.z * clipMin.x * clipMin.y * clipMin.z; // 一次缩到范围内。
    return average + diff; // 返回裁剪后的历史。
}

// 三次采样的五个支撑点：中心行列各取一次，比双线性更锐，代价是五次取样。
// `coord` 与 `texSize` 都是零到一坐标口径，返回四分量，透明度原样带回。
vec4 ogxBicubicTexture4(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个纹素的大小。
    coord = coord * texSize; // 换到像素坐标。
    vec2 p = floor(coord - 0.5) + 0.5; // 采样核中心。
    vec2 f = coord - p; // 中心偏移。
    vec2 f2 = f * f; // 平方。
    vec2 f3 = f * f2; // 立方。
    float c = 0.5; // 三次核系数。
    vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 最左权重。
    vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 左权重。
    vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 右权重。
    vec2 w3 = c * f3 - c * f2; // 最右权重。
    vec2 w12 = w1 + w2; // 左右权重和。
    vec2 tc12 = texel * (p + w2 / w12); // 中间采样坐标。
    vec2 tc0 = texel * (p - 1.0); // 最左采样点。
    vec2 tc3 = texel * (p + 2.0); // 最右采样点。
    vec4 color = textureLod(source, vec2(tc12.x, tc0.y), 0.0) * (w12.x * w0.y)
                 + textureLod(source, vec2(tc0.x, tc12.y), 0.0) * (w0.x * w12.y)
                 + textureLod(source, tc12, 0.0) * (w12.x * w12.y)
                 + textureLod(source, vec2(tc3.x, tc12.y), 0.0) * (w3.x * w12.y)
                 + textureLod(source, vec2(tc12.x, tc3.y), 0.0) * (w12.x * w3.y); // 五个采样点加权。
    return color / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y); // 归一化。
}

// 屏幕深度换米制距离；时间抗锯齿的深度比较与参考深度都用这一套。
float ogxTaaLinearDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度，写历史参考深度时用。
float ogxTaaScreenDepth(float depth, mat4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 读当前帧颜色；`packedDepth` 为真时透明度是屏幕深度，读完换成米制，供下界历史使用。
vec4 ogxTaaSampleCurrent(sampler2D colorTexture, vec2 coord, vec2 viewport, mat4 projectionInverse, bool packedDepth, bool bicubic)
{
    if (packedDepth) // 下界把颜色与深度放在同一张图。
    {
        vec4 data = bicubic ? ogxBicubicTexture4(colorTexture, coord, viewport) : textureLod(colorTexture, coord, 0.0); // 取颜色与深度。
        data.rgb = ogxRgbToYCoCg(data.rgb); // 颜色转亮度色差空间。
        data.a = ogxTaaLinearDepth(data.a, projectionInverse); // 深度换米制。
        return data; // 交回四分量。
    }
    vec3 color = bicubic ? ogxBicubicTexture4(colorTexture, coord, viewport).rgb : textureLod(colorTexture, coord, 0.0).rgb; // 取当前帧颜色。
    return vec4(ogxRgbToYCoCg(color), 0.0); // 深度占位为零。
}

// 精确读当前帧纹素；邻域方差统计用，整数坐标不会混入邻居颜色。
vec4 ogxTaaFetchCurrent(sampler2D colorTexture, ivec2 coord, mat4 projectionInverse, bool packedDepth)
{
    vec4 data = texelFetch(colorTexture, coord, 0); // 精确读取。
    if (packedDepth) // 下界连深度一起读。
    {
        data.rgb = ogxRgbToYCoCg(data.rgb); // 颜色转亮度色差空间。
        data.a = ogxTaaLinearDepth(data.a, projectionInverse); // 深度换米制。
        return data; // 四分量带深度。
    }
    return vec4(ogxRgbToYCoCg(data.rgb), 0.0); // 主世界与末地只要颜色。
}

// 双线性读历史里打包的两个参考深度，返回两个分量的双线性插值。
vec2 ogxTaaPrevDepthBilinear(sampler2D historyTexture, vec2 coord, vec2 viewport)
{
    coord = coord * viewport - 0.5; // 换到纹素坐标并移到纹素中心。
    vec2 f = fract(coord); // 纹素内小数偏移。
    ivec2 texel = ivec2(coord); // 左上角纹素。
    vec2 s0 = ogxUnpack2x16(texelFetch(historyTexture, texel, 0).a); // 左上角两个参考深度。
    vec2 s1 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(1, 0), 0).a); // 右上角。
    vec2 s2 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(0, 1), 0).a); // 左下角。
    vec2 s3 = ogxUnpack2x16(texelFetch(historyTexture, texel + ivec2(1, 1), 0).a); // 右下角。
    return mix(mix(s0, s1, f.x), mix(s2, s3, f.x), f.y); // 双向插值。
}

// 读上一帧历史颜色与参考深度；`packedDepth` 为真时从透明度解包参考深度。
vec4 ogxTaaSamplePrevious(sampler2D historyTexture, vec2 coord, vec2 viewport, mat4 projectionInverse, bool packedDepth, bool bicubic)
{
    if (packedDepth) // 下界历史带参考深度。
    {
        vec3 color = bicubic ? ogxBicubicTexture4(historyTexture, coord, viewport).rgb : textureLod(historyTexture, coord, 0.0).rgb; // 取历史颜色。
        float prevDepth = ogxTaaPrevDepthBilinear(historyTexture, coord, viewport).x; // 解包上一帧参考深度。
        return vec4(ogxRgbToYCoCg(color), ogxTaaLinearDepth(prevDepth, projectionInverse)); // 颜色与米制参考深度。
    }
    vec3 color = bicubic ? ogxBicubicTexture4(historyTexture, coord, viewport).rgb : textureLod(historyTexture, coord, 0.0).rgb; // 取历史颜色。
    return vec4(ogxRgbToYCoCg(color), 0.0); // 参考深度占位。
}

// 读上一帧某个纹素的参考深度；普通维度存在透明度，下界从打包值里取第二个分量。
float ogxTaaPrevDepthFetch(sampler2D historyTexture, ivec2 coord, bool packedDepth)
{
    return packedDepth ? ogxUnpack2x16(texelFetch(historyTexture, coord, 0).a).y : texelFetch(historyTexture, coord, 0).w; // 按存储方式取深度。
}

// 取上一帧三乘三邻域的参考深度最小与最大值，供深度一致性判断。
vec2 ogxTaaPrevDepthMinmax(sampler2D historyTexture, vec2 prevCoord, vec2 viewport, bool packedDepth)
{
    ivec2 nearest = ivec2(prevCoord * viewport); // 上一帧坐标换成最近纹素。
    float d0 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, -1), packedDepth); // 左上。
    float d1 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, -1), packedDepth); // 上方。
    float d2 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, -1), packedDepth); // 右上。
    float d3 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, 0), packedDepth); // 左侧。
    float d4 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, 0), packedDepth); // 中心。
    float d5 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, 0), packedDepth); // 右侧。
    float d6 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(-1, 1), packedDepth); // 左下。
    float d7 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(0, 1), packedDepth); // 下方。
    float d8 = ogxTaaPrevDepthFetch(historyTexture, nearest + ivec2(1, 1), packedDepth); // 右下。
    float minDepth = min(d0, min(d1, min(d2, min(d3, min(d4, min(d5, min(d6, min(d7, d8)))))))); // 九点最小值。
    float maxDepth = max(d0, max(d1, max(d2, max(d3, max(d4, max(d5, max(d6, max(d7, d8)))))))); // 九点最大值。
    return vec2(minDepth, maxDepth); // 返回范围。
}

// 当前帧三乘三邻域：求颜色均值、十字均值、方差范围；`packedDepth` 为真时同时给出参考深度范围。
vec3 ogxTaaVariance3x3(ivec2 coord, vec3 currColor, sampler2D colorTexture, mat4 projectionInverse, bool packedDepth,
    float aggression, out vec3 avgColor, out vec3 crossAvg, out vec2 referenceMinmax)
{
    vec4 data0 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, -1), projectionInverse, packedDepth); // 左上。
    vec4 data1 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, -1), projectionInverse, packedDepth); // 上方。
    vec4 data2 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, -1), projectionInverse, packedDepth); // 右上。
    vec4 data3 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, 0), projectionInverse, packedDepth); // 左侧。
    vec4 data4 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, 0), projectionInverse, packedDepth); // 中心。
    vec4 data5 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, 0), projectionInverse, packedDepth); // 右侧。
    vec4 data6 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(-1, 1), projectionInverse, packedDepth); // 左下。
    vec4 data7 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(0, 1), projectionInverse, packedDepth); // 下方。
    vec4 data8 = ogxTaaFetchCurrent(colorTexture, coord + ivec2(1, 1), projectionInverse, packedDepth); // 右下。
    crossAvg = data1.rgb + data3.rgb + data4.rgb + data5.rgb + data7.rgb; // 十字五点之和。
    avgColor = (crossAvg + data0.rgb + data2.rgb + data6.rgb + data8.rgb) / 9.0; // 九点均值。
    crossAvg *= 0.2; // 十字均值。
    vec3 m2 = (data0.rgb * data0.rgb + data1.rgb * data1.rgb + data2.rgb * data2.rgb + data3.rgb * data3.rgb + data4.rgb * data4.rgb
        + data5.rgb * data5.rgb + data6.rgb * data6.rgb + data7.rgb * data7.rgb + data8.rgb * data8.rgb) / 9.0; // 二阶矩。
    vec3 variance = sqrt(m2 - avgColor * avgColor) * aggression; // 标准差乘裁剪强度得到范围半径。
    vec3 minColor = min(avgColor - variance, currColor) * 0.5; // 范围下界，至少包住当前颜色。
    vec3 maxColor = max(avgColor + variance, currColor) * 0.5; // 范围上界。
    if (packedDepth) // 下界还要邻域参考深度范围。
    {
        referenceMinmax = vec2(min(data0.a, min(data1.a, min(data2.a, min(data3.a, min(data4.a, min(data5.a, min(data6.a, min(data7.a, data8.a)))))))),
            max(data0.a, max(data1.a, max(data2.a, max(data3.a, max(data4.a, max(data5.a, max(data6.a, max(data7.a, data8.a))))))))); // 九点深度范围。
    }
    else // 普通维度没有参考深度。
    {
        referenceMinmax = vec2(0.0); // 占位。
    }
    avgColor = minColor + maxColor; // 输出范围中心。
    return maxColor - minColor; // 输出范围半径。
}

// 时间重投影：当前帧与历史帧按邻域范围、运动量、深度一致性混合；返回颜色与代表深度。
// `packedDepth` 为真时按上下界打包参考深度，`referenceDepth` 回传换回屏幕深度的参考值。
vec4 ogxTaaReproject(vec2 coord, vec3 velocity, float currDepthMin, sampler2D currentTexture, sampler2D historyTexture,
    vec2 viewport, ivec2 texelCoord, mat4 projectionInverse, float farPlane, vec2 jitter,
    float blendWeight, float aggression, float depthThreshold, bool bicubicCurrent, bool bicubicPrevious,
    bool clipToCenter, bool depthCompare, bool microBlur, bool packedDepth, out float referenceDepth)
{
    vec2 unjitter = coord + jitter * 0.5; // 撤销本帧抖动，取样才落在真实位置。
    vec4 currData = ogxTaaSampleCurrent(currentTexture, unjitter, viewport, projectionInverse, packedDepth, bicubicCurrent); // 当前帧样本。
    vec3 currColor = currData.rgb; // 当前帧颜色。
    vec3 avgColor = currColor; // 邻域均值初值。
    vec3 crossAvg = currColor; // 十字均值初值。
    vec2 referenceMinmax = vec2(0.0); // 参考深度范围初值。
    vec3 variance = ogxTaaVariance3x3(texelCoord, currColor, currentTexture, projectionInverse, packedDepth, aggression, avgColor, crossAvg, referenceMinmax); // 求邻域范围。
    vec2 prevCoord = coord - velocity.xy; // 退回上一帧位置。
    vec4 prevData = ogxTaaSamplePrevious(historyTexture, prevCoord, viewport, projectionInverse, packedDepth, bicubicPrevious); // 读上一帧历史。
    vec3 prevColor = ogxClipAabb(avgColor, variance, prevData.rgb, clipToCenter); // 把历史夹进当前范围。
    if (packedDepth) // 下界把参考深度夹到邻域范围。
    {
        float depthTolerance = 2e-5; // 参考深度容差，极小，避免抖出条纹。
        prevData.a = clamp(prevData.a + velocity.z, referenceMinmax.x - depthTolerance, referenceMinmax.y + depthTolerance); // 夹到邻域深度范围。
    }
    float blend = blendWeight; // 历史基础权重。
    vec2 pixelVelocity = abs(fract(velocity.xy * viewport) - 0.5) * 2.0; // 像素为单位的运动量。
    blend *= sqrt(pixelVelocity.x * pixelVelocity.y) * 0.25 + 0.75; // 运动越大历史权重越低。
    blend *= float(ogxEqual(ogxSaturate(coord), coord)); // 上一帧坐标出屏时不用历史。
    if (depthCompare) // 深度比较通过才保留历史权重。
    {
        vec2 prevDepth = ogxTaaPrevDepthMinmax(historyTexture, prevCoord, viewport, packedDepth); // 上一帧深度范围。
        float currDist = ogxTaaLinearDepth(currDepthMin, projectionInverse); // 当前帧换成米制。
        float threshold = max(depthThreshold - currDist / farPlane * 0.2 * depthThreshold, 1e-5); // 越远阈值越小。
        blend *= step(prevDepth.x - currDepthMin + velocity.z, threshold); // 历史更深一侧的一致性判断。
        blend *= step(currDepthMin - velocity.z - prevDepth.y, threshold); // 历史更浅一侧的一致性判断。
    }
    if (microBlur) // 权重低时更倾向十字均值，抑制闪烁。
    {
        currColor = mix(crossAvg, currColor, ogxSaturate(blend * 5.0 - 0.5));
    }
    currColor = mix(currColor, prevColor, blend); // 按权重把历史混进当前帧。
    if (packedDepth) // 下界参考深度也按权重混合。
    {
        referenceDepth = mix(currData.a, prevData.a, blend); // 混合参考深度。
        referenceDepth = ogxTaaScreenDepth(referenceDepth, projectionInverse); // 换回屏幕深度再打包。
    }
    else // 普通维度不需要参考深度。
    {
        referenceDepth = 0.0; // 占位。
    }
    return vec4(ogxYCoCgToRgb(currColor), currDepthMin); // 返回颜色与代表深度。
}

// iterationT 的 TAA 当前深度取格：直接从深度纹理读一个像素，不插值。
float ogxTaaSampleDepthFetch(sampler2D depthTexture, ivec2 coord)
{
    return texelFetch(depthTexture, coord, 0).x; // 深度纹理的红色通道。
}

#endif


/*
生成文件：表面模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库表面模块：方块光曲线、材质法线、遮蔽换算与自发光。
调用位置：任何需要把方块光等级、法线贴图和材质遮蔽变成光照输入，或按贴图色算自发光的程序；
    Minecraft 光影由 `/omni-gfx/surface.glsl` 引入，`rendering/lighting/emissive.glsl`
    与地形材质代码只保留选项换算。
可复制示例：
    float c = ogxCurveBlockLightSky(blockLight); // 天光等级曲线。
    vec3 n = ogxMaterialNormalScale(tangentNormal, 1.0); // 法线起伏倍率。
    vec4 m = ogxMaterialNormal(normalTexRGB, true, 1.0); // 法线加遮蔽。
    float e = ogxOreEmission(albedo); // 矿石发光。
设计原因与取舍：
    选项值由调用方作为参数传入，库不读取任何 `OMNI_*` 宏，因此同一份算法能脱离光影使用。
    曲线常数照 iterationT 与 Eclipse 原程序保留，迁移只改名字与参数位置，默认画面不变。
    自发光按底色长度缩放：贴图越亮的部位越亮，暗贴图不会凭空发光。
*/
#ifndef OGX_SURFACE_INCLUDED
#define OGX_SURFACE_INCLUDED

// 数学模块提供法线解码、夹紧、湿面粗糙度与色相转换。

// 天光曲线：先抬高低等级，再压暗高等级，等级越高越接近饱和。
float ogxCurveBlockLightSky(float blockLight)
{
    blockLight = 1.0 - pow(1.0 - blockLight * 0.9, 0.7); // 抬高低等级并保留低端细节。
    blockLight = clamp(blockLight * blockLight * blockLight * 1.95, 0.0, 1.0); // 三次方拉开对比后夹紧。
    return blockLight; // 返回零到一的天光强度。
}

// 方块光曲线：按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float ogxCurveBlockLightTorch(float blockLight)
{
    float dist = (1.0 - blockLight) * 15.0 + 1.0; // 把等级转成米制距离。
    dist = dist * dist; // 距离平方，衰减更快。
    float boost = clamp(blockLight * 2.0 - 1.0, 0.0, 1.0); // 只有高等级才有的提升量。
    blockLight = blockLight + boost * boost; // 先加提升，突出光源附近的亮度。
    blockLight /= dist; // 再按距离平方衰减。
    return blockLight; // 返回重整后的方块光。
}

// 材质遮蔽：资源包把遮蔽存在法线贴图蓝通道，启用时映射到零点五到一。
float ogxMaterialAo(vec3 normalTexRGB, bool enabled)
{
    return enabled ? normalTexRGB.b * 0.5 + 0.5 : 1.0; // 未启用时不做任何遮蔽。
}

// 法线倍率：围绕朝外方向缩放起伏，倍率为一时保持原样。
// 先把倍率差补到 z 再单位化，这样倍率为零时正好是平坦的朝外法线。
vec3 ogxMaterialNormalScale(vec3 tangentNormal, float multiplier)
{
    return normalize(tangentNormal * multiplier + vec3(0.0, 0.0, 1.0 - multiplier)); // z 补齐后重新单位化。
}

// 一次解出切线空间法线与遮蔽，返回前三个分量为法线、第四个分量为遮蔽。
vec4 ogxMaterialNormal(vec3 normalTexRGB, bool aoEnabled, float multiplier)
{
    vec3 normal = ogxMaterialNormalScale(ogxDecodeNormalTex(normalTexRGB), multiplier); // 先解码再缩放。
    return vec4(normal, ogxMaterialAo(normalTexRGB, aoEnabled)); // 把遮蔽一起交回。
}

// 方块光：按光等级、遮蔽与光源标记算出火把照亮周围的颜色。
// 为什么先按光等级压低遮蔽：光源附近本身亮，遮蔽不该把那里压黑，所以接近满级时把遮蔽推向全亮。
// 为什么先给光源方块限一个上限等级：发光方块自己贴图上不该出现高亮方块光，限一档避免过曝。
// 参数 `sourceMask` 由调用方把各类发光方块与受光实体合成为一个零到一的标记。
vec3 ogxBlockLight(float lightmap, vec3 ao, float sourceMask, vec3 torchColor, float brightness, bool overworld)
{
    ao = mix(ao, vec3(1.0), ogxSaturate(lightmap * 5.0 - 4.2)); // 光等级接近满值时遮蔽趋向全亮。
    lightmap = min(lightmap, 1.0 - 0.13 * sourceMask); // 光源方块自身把方块光等级压一档。
    lightmap = ogxCurveBlockLightTorch(lightmap); // 按距离平方曲线重整等级，得到火把那样集中的光。
    float scale = overworld ? 0.015 : 0.15; // 下界末地没有阳光，常数放大十倍。
    return torchColor * ao * (lightmap * brightness * scale); // 火把光色乘遮蔽与强度。
}

// 纹理自发光：按模式把硬编码发光与资源包发光相加或二选一。
// 参数 `hardcodedMask` 是调用方按方块类型加权得到的强度，`emissive` 已乘过整体亮度。
// 为什么硬编码发光要乘底色长度：贴图越亮的部位自发光越强，避免暗贴图凭空发光。
vec3 ogxTextureEmissive(vec3 albedo, float emissive, float hardcodedMask, bool torchTinted, vec3 torchColor, float torchBrightness,
    float textureBrightness, int mode, bool overworld)
{
    if (mode == 1) // 仅资源包：只用自发光强度，不看方块类型。
    {
        float scale = overworld ? 0.01 : 0.1; // 下界末地放大十倍。
        return vec3(emissive * torchBrightness * scale); // 自发光强度乘亮度。
    }
    vec3 lightingColor = torchTinted ? torchColor : vec3(1.0); // 出现火把类光源才染成火把光色。
    hardcodedMask *= length(albedo); // 用底色亮度缩放，暗贴图不发光。
    float darkScale = overworld ? 1.0 : 10.0; // 下界末地的整体倍率。
    if (mode == 2) return lightingColor * (max(hardcodedMask * textureBrightness, emissive * 0.005) * torchBrightness * darkScale); // 相加模式取较大者。
    return lightingColor * (hardcodedMask * textureBrightness * torchBrightness * darkScale); // 仅硬编码模式。
}

// 矿石发光：鲜艳又明亮的矿物颗粒才发光，灰色石底几乎不亮。
float ogxOreEmission(vec3 albedo)
{
    vec3 hsv = ogxRgbToHsv(albedo); // 拆出饱和度与明度。
    return smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5) * 0.5; // 饱和度当门槛，明度拉对比，再乘 Eclipse 的半值。
}

// 纹饰发光：只看明度，越亮的纹路越亮；明度开方让暗纹也保留一部分发光。
float ogxTrimEmission(vec3 albedo)
{
    vec3 hsv = ogxRgbToHsv(albedo); // 拆出明度。
    return sqrt(hsv.z); // 明度开方，照 Eclipse。
}

// 从表面贴图解出的一整套物理材质参数；字段与光影包的材质结构一一对应，调用方逐个复制即可。
struct OgxPbrMaterial
{
    float roughness; // 粗糙度，越大高光越散。
    float metalness; // 金属度，越大底色越偏反射。
    float f0; // 正射反射率，非金属约零点零四。
    float emissiveness; // 资源包给出的自发光强度。
    float scattering; // 次表面散射强度。
    float reflectionStrength; // 这份表面允许反射的强度。
};

// 从 labPBR 表面贴图解出材质：蓝色通道兼作孔隙率与散射，红绿通道是平滑度与金属度。
// 参数全部显式传入，库不读取资源包格式选项；`baseTex` 会被吸水压暗，所以是输入输出参数。
// 为什么先算孔隙率：它同时决定吸水暗化与湿润后的平滑度，两处必须用同一个值。
OgxPbrMaterial ogxPbrMaterialFromTex(inout vec3 baseTex, vec4 specTex, float wet, bool usePorosity,
    int pbrFormat, float defaultPorosity, float porosityAbsorption, bool roughnessClamp,
    float emissivenessGamma, float sssStrength, float sssOffset, float puddleSharpness)
{
    float porosity = defaultPorosity; // 默认孔隙率。
    if (usePorosity && pbrFormat < 2) // 资源包自带孔隙率时才按高六位解码。
    {
        porosity = ogxSaturate(specTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specTex.b)); // 蓝通道高六位表示孔隙率。
    }
    baseTex *= 1.0 - wet * ogxFastSqrt(porosity) * porosityAbsorption; // 吸水越多的表面越暗，开方让差异平缓。
    OgxPbrMaterial material; // 下面逐项填写。
    float rawSmoothness = mix(specTex.r, 1.0, ogxSaturate(wet * (1.7 - porosity * 0.7))); // 湿润把表面拉向光滑。
    material.roughness = 1.0 - rawSmoothness; // 平滑度取反得到粗糙度。
    material.roughness *= material.roughness; // 平方让光滑面更集中。
    material.roughness = ogxPuddleRoughness(material.roughness, 0.5, wet, puddleSharpness); // 湿面锐度按选项混合。
    float rawMetalness = specTex.g; // 绿通道是金属度。
    if (pbrFormat == 0) rawMetalness = ogxSaturate(rawMetalness + step(0.9, rawMetalness)); // labPBR 预设金属位拉满。
    material.metalness = roughnessClamp ? ogxSaturate(rawMetalness * 1.1 - 0.1) : rawMetalness; // 限制模式先放大再平移。
    material.f0 = rawMetalness * 0.96 + 0.04; // 金属度高时反射率接近底色。
    material.reflectionStrength = roughnessClamp ? ogxSaturate(2.0 - material.roughness * 5.0) : ogxSaturate(2.0 - material.roughness * 2.0); // 限制模式更快去掉粗糙面的反射。
    material.reflectionStrength = ogxSaturate(material.reflectionStrength + material.metalness * 1e10 + wet * 3.0); // 金属与湿面全反射。
    material.emissiveness = specTex.a; // 透明通道是自发光。
    if (pbrFormat < 2) material.emissiveness -= step(1.0, material.emissiveness); // 满值表示没有自发光。
    material.emissiveness = pow(material.emissiveness, emissivenessGamma); // 按选项重整亮暗对比。
    material.scattering = pbrFormat < 2 ? ogxSaturate((specTex.b * 255.0 - 64.0) / 191.0) * sssStrength + sssOffset : 0.0; // 蓝通道其余位是散射。
    return material; // 交回解码好的材质。
}

// Eclipse 方块光曲线：先把等级转成亮斑，再在平方曲线与固定高值之间混合。
// 为什么亮斑单独算：原版光照图在最高几档突然变亮，直接平方会让灯下反而没有层次。
vec3 ogxBlockLightCurveEclipse(vec3 lightColor, float lightmap)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 输入先夹到合法范围。
    float brightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 只取最高三成作为亮斑。
    brightspot *= brightspot * brightspot; // 三次方让亮斑收得更紧。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 开方曲线，低等级抬得更快。
    lightmapLight *= lightmapLight; // 再平方，高等级更亮。
    float curve = mix(lightmapLight, 2.5, brightspot); // 亮斑处直接推到固定高值。
    return curve * lightColor; // 乘光色得到方块光。
}

// 手电筒光斑：按光线与光束指向的夹角给出一束光的强度分布。
// 主瓣给中心亮区，副瓣给一点点外圈余晖，再乘一圈暗环，让边界更像手电筒。
float ogxSpotShape(float r, float fov)
{
    float shape = ogxCurve01(ogxSaturate(r * 2.0 - (2.0 - fov))); // 中心主瓣，夹角越小越亮。
    shape += ogxCurve01(ogxSaturate(r * 1.25 - (1.0 - fov))) * 0.01; // 很弱的外圈余晖。
    float ringSize = 8.0 / fov; // 暗环宽度随光束角度缩放。
    shape *= 1.0 - ogxCurve01(ogxSaturate(1.0 - abs(r * ringSize - ringSize + 1.0))) * 0.25; // 主瓣外压一圈暗环。
    return shape; // 零到一的光斑强度。
}

// 手电筒指向：打开相机平滑时按两个平滑角度滞后于视角，否则始终朝相机正前方。
// 为什么单独成函数：光照与高光两处要同一个方向，分开写容易在改动时只改到一处。
vec3 ogxFlashlightAimDirection(float eyeRx, float eyeRy, float smoothTime, bool cameraSmooth)
{
    if (!cameraSmooth) return vec3(0.0, 0.0, -1.0); // 不平滑时始终朝相机正前方。
    float angleRx = eyeRx * -smoothTime; // 俯仰角按过渡时长滞后。
    float angleRy = eyeRy * -smoothTime; // 偏航角按过渡时长滞后。
    mat3 rx = mat3(1.0, 0.0, 0.0, 0.0, cos(angleRx), sin(angleRx), 0.0, -sin(angleRx), cos(angleRx)); // 俯仰旋转。
    mat3 ry = mat3(cos(angleRy), 0.0, -sin(angleRy), 0.0, 1.0, 0.0, sin(angleRy), 0.0, cos(angleRy)); // 偏航旋转。
    return ogxMatrix3MulPoint(ry, ogxMatrix3MulPoint(rx, vec3(0.0, 0.0, -1.0))); // 合成旋转后的光束指向。
}

// 手持光：按物品的光色、照明半径与到相机的距离算一个球形光源。
// `relativeEye` 是相机小数偏移，`playerPos` 是相机相对位置；两者相加才是到光源的真实距离。
vec3 ogxHandLight(vec3 lightColor, float lightRange, vec3 playerPos, vec3 relativeEye)
{
    float dist = length(playerPos + relativeEye); // 到手持光源的距离。
    float falloff = pow(1.0 - dist / lightRange, 3.0); // 线性衰减再取三次方。
    return lightColor * max(falloff, 0.0); // 范围外为零。
}

// Eclipse 间接光：天光按一条抬高次方的曲线缩放，再混入最低环境光。
// `minAmount` 与 `minAmountInside` 分别是室外、室内的最低光比例，`nightVision` 是夜视附加量。
vec3 ogxDoIndirectLighting(vec3 lightColor, vec3 minimumLightColor, float lightmap,
    float ambientBrightness, float minAmount, float minAmountInside, float nightVision)
{
    float curve = (pow(lightmap, 15.0) * 2.0 + lightmap * lightmap) / 3.0; // 低等级压暗、高等级抬高。
    vec3 indirect = lightColor * curve * ambientBrightness; // 天光按曲线缩放。
    indirect += mix(minimumLightColor * (minAmount * 0.004 + nightVision * 0.02),
                     minimumLightColor * (minAmountInside * 0.004 + nightVision * 0.02), 1.0 - lightmap); // 室外室内两档最低光按天光混合。
    return indirect; // 交回间接光。
}

// iterationT 的纹理自发光：硬编码方块光权重逐项固定，资源包模式与硬编码模式分开。
// 参数 `mode`：0 只硬编码，1 只资源包，2 两者取较大；`overworld` 为假时整体乘十。
vec3 ogxItxTextureLighting(vec3 albedo, float lightmap, float emissive, float glowstone,
    float torch, float fire, float lava, float redstoneTorch, float oxidizedBulb, float soulFire,
    float amethyst, float endPortal, float litHigh, float litMedium, float litLow, float particleLit,
    float redstone, float emissiveBrightness, float textureBrightness, float torchBrightness,
    vec3 torchColor, int mode, bool overworld)
{
    emissive *= emissiveBrightness; // 参考实现先把资源包自发光乘整体亮度。
    if (mode == 1) // 只用资源包自发光。
    {
        float scale = overworld ? 0.01 : 0.1; // 下界末地放大十倍。
        return vec3(emissive * torchBrightness * scale);
    }
    float hardcoded = glowstone * 0.016; // 荧石权重。
    hardcoded += torch * 0.03; // 火把权重。
    hardcoded += fire * 0.004; // 火焰权重。
    hardcoded += lava * 0.012; // 岩浆权重。
    hardcoded += redstoneTorch * 0.001; // 红石火把权重。
    hardcoded += oxidizedBulb * 0.0002; // 氧化铜灯权重。
    vec3 lightColor = hardcoded > 0.0 ? torchColor : vec3(1.0); // 只有前六类光源染成火把色。
    hardcoded += soulFire * 0.001; // 灵魂火权重。
    hardcoded += amethyst * 0.0003; // 紫水晶权重。
    hardcoded += endPortal * 4.0; // 末地传送门权重。
    hardcoded += litHigh * 0.02; // 高亮实体。
    hardcoded += litMedium * 0.005; // 中亮实体。
    hardcoded += litLow * 0.002; // 低亮实体。
    hardcoded += particleLit * 0.01; // 受光粒子。
    hardcoded += redstone * 0.2 * emissive; // 红石按自发光缩放。
    hardcoded *= length(albedo); // 贴图越亮，硬编码发光越强。
    float darkScale = overworld ? 1.0 : 10.0; // 下界末地的整体倍率。
    if (mode == 2) return lightColor * (max(hardcoded * textureBrightness, emissive * 0.005) * torchBrightness * darkScale); // 两者取较大。
    return lightColor * (hardcoded * textureBrightness * torchBrightness * darkScale); // 只用硬编码。
}

// iterationT 的材质覆盖：水、彩色玻璃、冰按优先级替换整套材质参数，并标记为光滑。
// 为什么先水后玻璃再冰：参考实现按这个顺序覆盖，后写的一方获胜；不要改成 else-if。
void ogxApplyMaterialOverride(inout OgxPbrMaterial material, float water, float glass, float ice, inout bool isSmooth)
{
    if (water > 0.5) // 水材质：粗糙度与金属度为零，反射率 0.02，全反射。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.02;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
    if (glass > 0.5) // 彩色玻璃：反射率 0.042。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.042;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
    if (ice > 0.5) // 冰：反射率 0.018。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.018;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
}

// iterationT 的 labPBR 材质解码：与 `ogxPbrMaterialFromTex` 相同，但不叠加 Omni 的水洼粗糙度。
// 为什么单独保留：参考实现的每一行常数都是画面合同的一部分，水洼混合属于额外功能，
// 不能悄悄改变参考路径的粗糙度。
OgxPbrMaterial ogxItxMaterialFromTex(inout vec3 baseTex, vec4 specTex, float wet,
    bool usePorosity, int pbrFormat, float defaultPorosity, float porosityAbsorption,
    bool roughnessClamp, float emissivenessGamma, float sssStrength, float sssOffset)
{
    float porosity = defaultPorosity; // 默认孔隙率。
    if (usePorosity && pbrFormat < 2) // 资源包自带孔隙率时才解码高六位。
    {
        porosity = ogxSaturate(specTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specTex.b));
    }
    baseTex *= 1.0 - wet * ogxFastSqrt(porosity) * porosityAbsorption; // 吸水压暗。
    OgxPbrMaterial material; // 逐项填写。
    float rawSmoothness = mix(specTex.r, 1.0, ogxSaturate(wet * (1.7 - porosity * 0.7))); // 湿面更光滑。
    material.roughness = 1.0 - rawSmoothness; // 平滑度取反。
    material.roughness *= material.roughness; // 平方集中高光。
    float rawMetalness = specTex.g; // 绿通道金属度。
    if (pbrFormat == 0) rawMetalness = ogxSaturate(rawMetalness + step(0.9, rawMetalness)); // labPBR 金属位拉满。
    material.metalness = roughnessClamp ? ogxSaturate(rawMetalness * 1.1 - 0.1) : rawMetalness; // 限制模式。
    material.f0 = rawMetalness * 0.96 + 0.04; // 反射率。
    material.reflectionStrength = roughnessClamp ? ogxSaturate(2.0 - material.roughness * 5.0) : ogxSaturate(2.0 - material.roughness * 2.0); // 粗糙面反射衰减。
    material.reflectionStrength = ogxSaturate(material.reflectionStrength + material.metalness * 1e10 + wet * 3.0); // 金属与湿面全反射。
    material.emissiveness = specTex.a; // 透明通道自发光。
    if (pbrFormat < 2) material.emissiveness -= step(1.0, material.emissiveness); // 满值表示无自发光。
    material.emissiveness = pow(material.emissiveness, emissivenessGamma); // 对比重整。
    material.scattering = pbrFormat < 2 ? ogxSaturate((specTex.b * 255.0 - 64.0) / 191.0) * sssStrength + sssOffset : 0.0; // 蓝通道剩余位是散射。
    return material; // 交回材质。
}

#endif

/*
生成文件：体素模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体素追踪模块：在规则三维网格里沿射线逐格前进，撞到实心方格时用存下的颜色与光照着色。
调用位置：任何有三维方块编号图与颜色图的程序；Minecraft 光影由 `/omni-gfx/voxel.glsl` 引入，
    `rendering/reflection/voxel.glsl` 只保留选项换算与坐标平移。
可复制示例：ogxVoxelReflection 返回反射颜色与归一化命中距离，并带回命中点。
设计原因与取舍：
    网格偏移、边长、两张三维纹理、光色、太阳方向、追踪距离与强度全部由调用方传入，库不读取任何引擎状态。
    水、冰、玻璃按半透明处理，只给后面的画面染色后继续走；铁块按镜面弹射，最多弹四次，
    防止两面镜子互相拖满循环。追踪用标准的三维逐格步进：每步选最近的一根格子边界，撞到实心方块就停。
    方块编号是方块的业务数据，用 `uint` 直接传入，库不假设它来自哪张方块表。
    三维纹理取格写成 `Load(ivec4(cell, level))`：Slang 把细节层级放在坐标的第四个分量，
    生成器再把它还原成 GLSL 的 `texelFetch(tex, cell, level)`，两边算式不变。
*/
#ifndef OGX_VOXEL_INCLUDED
#define OGX_VOXEL_INCLUDED

// 数学提供夹紧与向量单位化，颜色提供 sRGB 到线性的转换。


// 半透明方块：水、冰、玻璃，光线穿过后只给后面的画面染色，不停下。
bool ogxVoxelIsTranslucent(uint id) { return id == 8u || id == 79u || id == 95u; }

// 植物：草、花、树叶等，不挡光也不算实体，直接穿过。
bool ogxVoxelIsPlant(uint id)
{
    return id == 12u || id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7030u || id == 7040u; // 编号与方块映射表一致。
}

// 铁块：反射撞到它时当镜子处理；编号 504 与方块映射表一致。
bool ogxVoxelIsIron(uint id) { return id == 504u; }

// 半透明方块的染色强度：水最清、冰居中、玻璃最浓。
// 为什么按编号分档：颜色图没有存透明度，只能按方块种类近似；玻璃本身有色，染色就重一些。
float ogxVoxelTintStrength(uint id)
{
    if (id == 8u) return 0.4; // 水：多数是清水，只带一点生物群系颜色。
    if (id == 79u) return 0.6; // 冰：本身偏蓝。
    return 0.8; // 玻璃与染色玻璃：颜色最重。
}

// 算一层半透明染色：把方块底色归一化成方向色（保留色相、去掉亮度），再按强度与无色混合。
// 为什么归一化：只用色相给后面的画面染色，避免水太亮把反射整个提白。
vec3 ogxVoxelTranslucentTint(uint id, vec3 albedo)
{
    return mix(vec3(1.0), ogxNormalize(albedo), ogxVoxelTintStrength(id)); // 按方块种类决定染色深度。
}

// 给命中的体素面上色：底色乘（方块光加天光的间接光，再加直射太阳光）。
// `packedLight` 是写入端打包的方块光与天光，`voxelNormal` 是进入面朝外的法线。
vec3 ogxVoxelShade(vec3 albedo, vec3 voxelNormal, float packedLight, vec3 torchColor, vec3 skyColor,
    vec3 sunColor, vec3 sunDirection, float strength)
{
    float packed = floor(packedLight * 255.0 + 0.5); // 还原成整数位的打包光照。
    float blockLevel = floor(packed / 16.0) / 15.0; // 高四位是方块光等级。
    float skyLevel = ogxMod(packed, 16.0) / 15.0; // 低四位是天光等级。
    vec3 indirect = torchColor * blockLevel + skyColor * skyLevel; // 方块光与天光一起给环境亮度。
    vec3 direct = sunColor * ogxSaturate(dot(voxelNormal, sunDirection)); // 直射按体素面朝太阳的余弦。
    return albedo * (indirect + direct) * strength; // 底色乘光照与玩家强度。
}

// 判断体素下标是否落在边长 `side` 的立方体里，越界就没有编号。
// 逐分量比较而不是向量比较：GLSL 330 的整数向量不支持大于等于运算符。
bool ogxVoxelInside(ivec3 cell, int side)
{
    return cell.x >= 0 && cell.y >= 0 && cell.z >= 0 && cell.x < side && cell.y < side && cell.z < side; // 三个轴都要在零到边长之间。
}

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// `originWorld` 是表面相机相对世界位置，`rayDirWorld` 是世界空间反射方向，`surfaceNormal` 是表面法线；
// `voxelOffset` 是相机相对位置到体积坐标的平移，`side` 是每边单元数。
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。
vec4 ogxVoxelReflection(vec3 originWorld, vec3 rayDirWorld, vec3 surfaceNormal, vec3 voxelOffset, int side,
    usampler3D voxelIdTexture, sampler3D voxelColorTexture, vec3 torchColor, vec3 skyColor,
    vec3 sunColor, vec3 sunDirection, float maxDistance, float strength, out vec3 hitWorldPos)
{
    hitWorldPos = originWorld; // 先给一个占位，命中时才被真正赋值。
    if (dot(rayDirWorld, surfaceNormal) <= 0.0) return vec4(0.0, 0.0, 0.0, -1.0); // 射线朝表面内侧，追踪没有意义。
    const int maxSteps = 320; // 每根射线最多走的格数，覆盖整条体积对角线还有余量。
    const int ironBounces = 4; // 铁块镜面最多弹射几次，防止两面镜子互相反射把循环拖满。
    float maxDist = min(maxDistance, float(side)); // 追踪距离不超过体积边长。
    vec3 accumTint = vec3(1.0); // 半透明方块累积的染色，最后乘到后面的画面上。
    float traveled = 0.0; // 已经走过的米数，跨镜面弹射累加，用来对总距离封顶。
    vec3 posWorld = originWorld + surfaceNormal * 0.05; // 起点沿法线抬起一点，避开表面自身那一格。
    vec3 dir = rayDirWorld; // 当前这段射线的方向，铁块弹射后会被改掉。
    for (int bounce = 0; bounce <= ironBounces; bounce++) // 每多弹一次镜面就多跑一段直线步进。
    {
        vec3 gridPos = posWorld + voxelOffset; // 转成体素网格坐标，整数边界就是体素边界。
        ivec3 cell = ivec3(floor(gridPos)); // 起点所在体素下标。
        if (!ogxVoxelInside(cell, side)) return vec4(0.0, 0.0, 0.0, -1.0); // 起点不在体积内，无法追踪。
        ivec3 stepDir = ivec3(sign(dir)); // 每轴前进方向，正负一或零。
        vec3 invDir = 1.0 / dir; // 方向倒数，用来算跨边界的参数距离。
        vec3 tDelta = abs(invDir); // 跨过一整格所需的参数距离。
        vec3 tMax = vec3(1e30); // 到下一个边界的参数距离；方向为零的轴保持极大值，不会被先选中。
        if (dir.x != 0.0) tMax.x = (float(cell.x) + max(sign(dir.x), 0.0) - gridPos.x) * invDir.x; // 横轴到边界的距离。
        if (dir.y != 0.0) tMax.y = (float(cell.y) + max(sign(dir.y), 0.0) - gridPos.y) * invDir.y; // 纵轴到边界的距离。
        if (dir.z != 0.0) tMax.z = (float(cell.z) + max(sign(dir.z), 0.0) - gridPos.z) * invDir.z; // 深度轴到边界的距离。
        bool mirrored = false; // 这一段是否以击中铁块镜面结束。
        for (int i = 0; i < maxSteps; i++)
        {
            float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近的一次跨格距离。
            if (traveled + tMin > maxDist) return vec4(0.0, 0.0, 0.0, -1.0); // 总距离超出上限，没有命中。
            vec3 faceNormal = vec3(0.0); // 本次进入体素的朝向；沿哪个轴走就从它的对面进入。
            if (tMax.x <= tMin) { cell.x += stepDir.x; tMax.x += tDelta.x; faceNormal.x = -float(stepDir.x); } // 走横轴这一格。
            else if (tMax.y <= tMin) { cell.y += stepDir.y; tMax.y += tDelta.y; faceNormal.y = -float(stepDir.y); } // 走纵轴这一格。
            else { cell.z += stepDir.z; tMax.z += tDelta.z; faceNormal.z = -float(stepDir.z); } // 走深度轴这一格。
            if (!ogxVoxelInside(cell, side)) return vec4(0.0, 0.0, 0.0, -1.0); // 走出体积，后面的格子没有编号。
            uint voxelId = texelFetch(voxelIdTexture, cell, 0).r; // 读这一格的方块编号。
            if (voxelId == 0u) continue; // 空气，继续走。
            if (ogxVoxelIsPlant(voxelId)) continue; // 植物不挡光，继续走。
            vec4 stored = texelFetch(voxelColorTexture, cell, 0); // 读这一格的颜色与光照。
            vec3 albedo = ogxSrgbToLinear(stored.rgb); // 贴图色从 sRGB 换回线性，与场景单位一致。
            if (ogxVoxelIsTranslucent(voxelId)) { accumTint *= ogxVoxelTranslucentTint(voxelId, albedo); continue; } // 水冰玻璃按彩色水染色后继续。
            vec3 hitPoint = posWorld + dir * tMin; // 本次刚跨进来的边界点，就是命中面所在位置。
            if (ogxVoxelIsIron(voxelId) && bounce < ironBounces) // 铁块镜面：弹开再追，铁块自己不上色。
            {
                traveled += tMin; // 把这一段长度计入总距离。
                hitWorldPos = hitPoint; // 先记住镜面位置，后续万一没命中仍有合理取值。
                posWorld = hitPoint + faceNormal * 0.01; // 起点抬离镜面，避免下一次步进又落回同一格。
                dir = reflect(dir, faceNormal); // 按进入面法线弹射。
                mirrored = true; // 标记本段以镜面结束，去跑下一段。
                break; // 退出内层，外层用新的起点与方向重设步进状态。
            }
            hitWorldPos = hitPoint; // 命中点的相机相对世界位置，调用方用它算雾段。
            vec3 shaded = ogxVoxelShade(albedo, faceNormal, stored.a, torchColor, skyColor, sunColor, sunDirection, strength) * accumTint; // 按体素面法线着色并乘上半透明染色。
            return vec4(shaded, ogxSaturate((traveled + tMin) / maxDist)); // 归一化总命中距离放进 a，供反射滤波使用。
        }
        if (!mirrored) return vec4(0.0, 0.0, 0.0, -1.0); // 走到步数上限还没命中，交给调用方走天空回退。
    }
    return vec4(0.0, 0.0, 0.0, -1.0); // 镜面弹射次数用尽仍未命中，交给调用方走天空回退。
}

// 体素编号：从三维掩码直接取格，并按参考实现取两千以内的编号。
uint ogxGetVoxelBlock(usampler3D voxelMask, ivec3 voxelPos)
{
    return texelFetch(voxelMask, voxelPos, 0).r % 2000u; // 参考实现的编号掩码。
}

// 体素写入格：把方块位置加上相机小数偏移，再落到以体积中心为原点的整数格。
// `center` 是体积半边长，调用方按自己的网格尺寸给出，库不假设固定边长。
ivec3 ogxVoxelWriteIndex(vec3 playerPos, vec3 cameraOffset, ivec3 center)
{
    return ivec3(floor(playerPos + cameraOffset)) + center; // 与 Eclipse `GetVoxelIndex` 的取整顺序一致。
}

// 体素写入是否在体积内：三个轴都必须在零到边长减一之间，越界写会被丢弃。
bool ogxVoxelWriteInBounds(ivec3 voxelPos, int size)
{
    return voxelPos.x >= 0 && voxelPos.y >= 0 && voxelPos.z >= 0
        && voxelPos.x < size && voxelPos.y < size && voxelPos.z < size; // 逐轴判断，避免夹紧后写错格。
}

// 写入格：把玩家相对位置加上相机小数偏移，再平移到体积中心；`side` 是每边格数。
ivec3 ogxGetVoxelIndex(vec3 playerPos, vec3 cameraOffset, int side)
{
    return ivec3(floor(playerPos + cameraOffset)) + ivec3(side / 2); // 参考实现按体积半边长平移。
}

// 体素下标：三轴按行优先展开成一维下标，供六面数据数组使用。
int ogxVoxelIndex(ivec3 voxelPos, int size)
{
    return voxelPos.x + voxelPos.y * size + voxelPos.z * size * size; // 与参考实现的展开顺序一致。
}

// 体素面编号：按法线主轴与正负方向映射到零到五，零到五分别对应六个面。
int ogxVoxelNormalIndex(vec3 voxelNormal)
{
    return clamp(int(abs(voxelNormal.x) * (voxelNormal.x * 0.5 + 0.5)
        + abs(voxelNormal.y) * (voxelNormal.y * 0.5 + 2.5)
        + abs(voxelNormal.z) * (voxelNormal.z * 0.5 + 4.5) + 0.5), 0, 5); // 参考实现的连续映射。
}

// 解包两个十六位小数：把一个浮点数的低位与高位拆回两个零到一的值。
vec2 ogxDecodeVec2_16(float a)
{
    const vec2 constant1 = 4294967294.0 / vec2(65536.0, 4294967295.0); // 两个通道的缩放。
    const float constant2 = 65536.0 / 65535.0; // 端点修正。
    return fract(a * constant1) * constant2; // 拆包并修正。
}

// 解包两个八位颜色：参考实现把颜色压进一个浮点数，读回时按两位十六进制拆开。
vec2 ogxDecodeVec2(float a)
{
    return vec2(fract(a * 256.0), fract(a * 65536.0)); // 低字节与高字节。
}

// 解码一个体素面的贴图坐标、光照与染色：六面数据里每个面存同样布局。
void ogxDecodeVoxelFace(vec4 blockTexture, out vec2 texcoord, out vec2 lightmap, out vec3 tintColor)
{
    texcoord = ogxDecodeVec2_16(blockTexture.x); // 第一个分量是贴图坐标。
    lightmap = ogxDecodeVec2(blockTexture.y); // 第二个分量是光照图。
    lightmap = min(max(lightmap - 0.05, 0.0) * 1.06, 1.0); // 参考实现先压暗再放大，去掉底部一段。
    vec2 rgTint = ogxDecodeVec2(blockTexture.b); // 第三个分量是红绿染色。
    tintColor = vec3(rgTint.r, blockTexture.a, rgTint.g); // 蓝染色在第四分量。
}

// 只取体素面的贴图坐标，供不需要光照的反射采样。
void ogxGetVoxelTexCoord(vec4 blockTexture, out vec2 texcoord)
{
    texcoord = ogxDecodeVec2_16(blockTexture.x); // 与完整解码使用同一拆包。
}

// 体素自发光：鲜艳又明亮的像素才发光，返回零到零点五。
float ogxGetVoxelEmission(vec3 albedo)
{
    vec3 hsv = ogxRgbToHsv(albedo); // 拆出饱和度与明度。
    float emissive = smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5); // 饱和度当门槛，明度拉对比。
    return emissive * 0.5; // 参考实现的半值。
}

// 把体素自发光混进光照：发光强度接近满值时表示没有自发光，否则按曲线混向底色。
void ogxVoxelEmission(inout vec3 lighting, vec3 albedo, float emission, float emissiveBrightness, float emissiveCurve)
{
    if (emission < 254.5 / 255.0) // 接近满值表示不发光。
    {
        lighting = mix(lighting, albedo * 5.0 * emissiveBrightness, pow(emission, emissiveCurve)); // 按强度与曲线混入。
    }
}

// 阴影体素写入：判断这一笔是否该写入并算出格号；方块编号与实体枚举由调用方在边界决定。
// `shouldWrite` 为假时不写；`voxelId` 为零时按空气处理；返回值是最终写入的编号。
uint ogxPopulateShadowVoxelIndex(vec3 playerPos, vec3 cameraOffset, ivec3 midBlockOffset, int side,
    bool shouldWrite, uint voxelId, float renderedItemId, float entityId, uint itemOffset, out ivec3 voxelPos)
{
    voxelPos = ogxGetVoxelIndex(playerPos + vec3(midBlockOffset) / 64.0, cameraOffset, side); // 中点偏移后算格号。
    if (!shouldWrite) return 0u; // 不写入的绘制阶段直接返回。
    if (voxelId == 0u) voxelId = 1u; // 参考实现把无编号地形当成实心方块。
    if (renderedItemId > 100.0 && renderedItemId < 276.0) voxelId = uint(renderedItemId) + itemOffset; // 手持物品按偏移写入，避免与草互动。
    else if (entityId > 0.0) voxelId = uint(entityId) + itemOffset; // 实体编号同样加偏移。
    return voxelId; // 交回最终编号。
}

#endif

/*
生成文件：放大模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库放大与锐化模块：边缘方向重采样、对比度自适应锐化与放大后锐化。
调用位置：任何把低分辨率画面放大到目标分辨率并恢复清晰度的程序；Minecraft 光影由
    `/omni-gfx/upscale.glsl` 引入，`rendering/clarity/upscale.glsl` 只保留选项换算。
可复制示例：ogxFsrEasu 把输入画面放大，ogxCas 再做对比度自适应锐化。
设计原因与取舍：采样器与画面尺寸由调用方传入，本模块不声明采样器、不读选项；
    公式与 iterationT 的边缘方向重采样和对比度自适应锐化逐行一致。
    旧实现直接用了宿主的 `saturate` 宏，这里改成库自己的夹紧函数，算式完全相同，
    但模块可以脱离光影单独编译。
*/
#ifndef OGX_UPSCALE_INCLUDED
#define OGX_UPSCALE_INCLUDED

// 数学模块提供亮度、夹紧与单位化。

// 单个采样点按离重采样中心的距离给权重，超出钳位半径的样本不再增加贡献。
// 两层权重相乘让核在中心为一、边缘平滑收零，避免放大后出现一圈硬边。
void ogxFsrEasuTap(inout vec3 aC, inout float aW, vec2 off, vec2 dir, vec2 len, float lob, float clp, vec3 c)
{
    vec2 rotOff = vec2(dot(off, dir), dot(off, vec2(-dir.y, dir.x))); // 把偏移转到与边缘对齐的坐标系。
    rotOff *= len; // 按边缘方向拉伸，让各向异性核沿边缘铺得更长。
    float d2 = min(dot(rotOff, rotOff), clp); // 到中心的距离平方，夹在钳位半径内。
    float wB = 0.4 * d2 - 1.0; // 外层权重多项式的一步。
    float wA = lob * d2 - 1.0; // 内层权重多项式的一步。
    wB *= wB; // 外层权重取平方。
    wA *= wA; // 内层权重取平方。
    wB = 1.5625 * wB - 0.5625; // 外层权重成形。
    float w = wB * wA; // 内外层权重相乘得到最终权重。
    aC += c * w; // 累加颜色。
    aW += w; // 累加权重。
}

// 用四组邻域估计边缘方向与长度，四组是四个子像素象限，权重是子像素面积。
void ogxFsrEasuSet(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE)
{
    float lenX = 1.0 / max(abs(lD - lC), abs(lC - lB)); // 水平方向长度倒数，由相邻亮度差决定。
    float dirX = lD - lB; // 水平亮度梯度。
    dir.x += dirX * w; // 按子像素面积加权累加水平方向。
    lenX = ogxSaturate(abs(dirX) * lenX); // 梯度越大越像边缘。
    lenX *= lenX; // 平方让弱边缘更快衰减。
    len += lenX * w; // 累加水平长度。
    float lenY = 1.0 / max(abs(lE - lC), abs(lC - lA)); // 竖直方向长度倒数。
    float dirY = lE - lA; // 竖直亮度梯度。
    dir.y += dirY * w; // 按子像素面积加权累加竖直方向。
    lenY = ogxSaturate(abs(dirY) * lenY); // 梯度越大越像边缘。
    lenY *= lenY; // 平方。
    len += lenY * w; // 累加竖直长度。
}

// 把输入画面按边缘方向重采样放大到目标分辨率，返回放大后的颜色。
// `fragCoord` 是输出像素坐标，`inputScreenSize` 是输入画面尺寸，`outputScreenSize` 是输出尺寸。
vec3 ogxFsrEasu(sampler2D inputTex, vec2 fragCoord, vec2 inputScreenSize, vec2 outputScreenSize)
{
    vec2 sizeRatio = inputScreenSize / outputScreenSize; // 输入相对输出的比例，用于把输出坐标映射回输入。
    vec2 subPixelOffset = fragCoord * sizeRatio - 0.5; // 输出像素落在输入像素网格里的位置。
    vec2 sampleCenter = floor(subPixelOffset); // 最近的低分辨率整数像素。
    subPixelOffset -= sampleCenter; // 去掉整数部分，只留子像素偏移。
    ivec2 texelCoordF = ivec2(sampleCenter); // 中心纹素坐标。
    vec3 sampleB = texelFetch(inputTex, texelCoordF + ivec2(0, -1), 0).rgb; // 上方邻域样本。
    vec3 sampleC = texelFetch(inputTex, texelCoordF + ivec2(1, -1), 0).rgb; // 右上邻域。
    vec3 sampleE = texelFetch(inputTex, texelCoordF + ivec2(-1, 0), 0).rgb; // 左侧邻域。
    vec3 sampleF = texelFetch(inputTex, texelCoordF + ivec2(0, 0), 0).rgb; // 中心样本。
    vec3 sampleG = texelFetch(inputTex, texelCoordF + ivec2(1, 0), 0).rgb; // 右侧邻域。
    vec3 sampleH = texelFetch(inputTex, texelCoordF + ivec2(2, 0), 0).rgb; // 右侧隔一个的邻域。
    vec3 sampleI = texelFetch(inputTex, texelCoordF + ivec2(-1, 1), 0).rgb; // 左下邻域。
    vec3 sampleJ = texelFetch(inputTex, texelCoordF + ivec2(0, 1), 0).rgb; // 下方邻域。
    vec3 sampleK = texelFetch(inputTex, texelCoordF + ivec2(1, 1), 0).rgb; // 右下邻域。
    vec3 sampleL = texelFetch(inputTex, texelCoordF + ivec2(2, 1), 0).rgb; // 右下隔一个的邻域。
    vec3 sampleN = texelFetch(inputTex, texelCoordF + ivec2(0, 2), 0).rgb; // 下方隔一个的邻域。
    vec3 sampleO = texelFetch(inputTex, texelCoordF + ivec2(1, 2), 0).rgb; // 右下再隔一个的邻域。
    float luminanceB = ogxLuminance(sampleB); // 各邻域亮度，用于估计边缘。
    float luminanceC = ogxLuminance(sampleC); // 右上亮度。
    float luminanceE = ogxLuminance(sampleE); // 左侧亮度。
    float luminanceF = ogxLuminance(sampleF); // 中心亮度。
    float luminanceG = ogxLuminance(sampleG); // 右侧亮度。
    float luminanceH = ogxLuminance(sampleH); // 右二亮度。
    float luminanceI = ogxLuminance(sampleI); // 左下亮度。
    float luminanceJ = ogxLuminance(sampleJ); // 下方亮度。
    float luminanceK = ogxLuminance(sampleK); // 右下亮度。
    float luminanceL = ogxLuminance(sampleL); // 右二下亮度。
    float luminanceN = ogxLuminance(sampleN); // 下二亮度。
    float luminanceO = ogxLuminance(sampleO); // 右下二亮度。
    vec2 dir = vec2(0.0); // 边缘方向。
    float len = 0.0; // 边缘长度。
    ogxFsrEasuSet(dir, len, (1.0 - subPixelOffset.x) * (1.0 - subPixelOffset.y), luminanceB, luminanceE, luminanceF, luminanceG, luminanceJ); // 左下子像素象限。
    ogxFsrEasuSet(dir, len, subPixelOffset.x * (1.0 - subPixelOffset.y), luminanceC, luminanceF, luminanceG, luminanceH, luminanceK); // 右下子像素象限。
    ogxFsrEasuSet(dir, len, (1.0 - subPixelOffset.x) * subPixelOffset.y, luminanceF, luminanceI, luminanceJ, luminanceK, luminanceN); // 左上子像素象限。
    ogxFsrEasuSet(dir, len, subPixelOffset.x * subPixelOffset.y, luminanceG, luminanceJ, luminanceK, luminanceL, luminanceO); // 右上子像素象限。
    vec2 dir2 = dir * dir; // 方向各分量平方。
    float dirR = dir2.x + dir2.y; // 方向长度平方。
    bool zro = dirR < (1.0 / 32768.0); // 极小的方向视为没有边缘。
    dirR = inversesqrt(dirR); // 方向长度倒数。
    dirR = zro ? 1.0 : dirR; // 没有边缘时用一，避免除零。
    dir.x = zro ? 1.0 : dir.x; // 没有边缘时默认水平方向。
    dir *= vec2(dirR); // 归一化方向。
    len = len * 0.5; // 长度取一半。
    len *= len; // 平方。
    float stretch = dot(dir, dir) / (max(abs(dir.x), abs(dir.y))); // 边缘各向异性比例。
    vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len); // 沿边缘与垂直方向的不同拉伸。
    float lob = 0.5 - 0.29 * len; // 核宽度参数。
    float clp = 1.0 / lob; // 核钳位半径。
    vec3 min4 = min(min(sampleF, sampleG), min(sampleJ, sampleK)); // 中心四邻最小值，限制重采样范围。
    vec3 max4 = max(max(sampleF, sampleG), max(sampleJ, sampleK)); // 中心四邻最大值。
    vec3 aC = vec3(0.0); // 加权颜色。
    float aW = 0.0; // 权重和。
    ogxFsrEasuTap(aC, aW, vec2(0.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleB); // 上方样本。
    ogxFsrEasuTap(aC, aW, vec2(1.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleC); // 右上样本。
    ogxFsrEasuTap(aC, aW, vec2(-1.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleE); // 左侧样本。
    ogxFsrEasuTap(aC, aW, vec2(0.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleF); // 中心样本。
    ogxFsrEasuTap(aC, aW, vec2(1.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleG); // 右侧样本。
    ogxFsrEasuTap(aC, aW, vec2(2.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleH); // 右二样本。
    ogxFsrEasuTap(aC, aW, vec2(-1.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleI); // 左下样本。
    ogxFsrEasuTap(aC, aW, vec2(0.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleJ); // 下方样本。
    ogxFsrEasuTap(aC, aW, vec2(1.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleK); // 右下样本。
    ogxFsrEasuTap(aC, aW, vec2(2.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleL); // 右二下样本。
    ogxFsrEasuTap(aC, aW, vec2(0.0, 2.0) - subPixelOffset, dir, len2, lob, clp, sampleN); // 下二样本。
    ogxFsrEasuTap(aC, aW, vec2(1.0, 2.0) - subPixelOffset, dir, len2, lob, clp, sampleO); // 右下二样本。
    return min(max4, max(min4, aC / aW)); // 归一化后夹在中心四邻范围内，抑制过冲。
}

// 对比度自适应锐化：按十字邻域的对比度决定锐化强度，平坦处几乎不动。
// `sharpness` 是百分制锐化量，`denoise` 打开时按十字噪声再压低一次。
vec3 ogxCas(sampler2D colorTex, vec3 sampleE, ivec2 texelCoord, float sharpness, bool denoise)
{
    vec3 sampleB = texelFetch(colorTex, texelCoord + ivec2(0, -1), 0).rgb; // 上方样本。
    vec3 sampleD = texelFetch(colorTex, texelCoord + ivec2(-1, 0), 0).rgb; // 左侧样本。
    vec3 sampleF = texelFetch(colorTex, texelCoord + ivec2(1, 0), 0).rgb; // 右侧样本。
    vec3 sampleH = texelFetch(colorTex, texelCoord + ivec2(0, 1), 0).rgb; // 下方样本。
    float luminanceB = ogxLuminance(sampleB); // 上方亮度。
    float luminanceD = ogxLuminance(sampleD); // 左侧亮度。
    float luminanceE = ogxLuminance(sampleE); // 中心亮度。
    float luminanceF = ogxLuminance(sampleF); // 右侧亮度。
    float luminanceH = ogxLuminance(sampleH); // 下方亮度。
    float minCross = min(min(luminanceB, luminanceD), min(luminanceE, min(luminanceF, luminanceH))); // 十字邻域最小亮度。
    float maxCross = max(max(luminanceB, luminanceD), max(luminanceE, max(luminanceF, luminanceH))); // 十字邻域最大亮度。
    float weight = sqrt(ogxSaturate(min(minCross, 2.0 - maxCross) / maxCross)) * (-0.1 - sharpness * 0.01); // 对比度越低权重越接近零，锐化越弱。
    if (denoise) // 开启降噪时按十字噪声再压低一次。
    {
        float noise = luminanceB * 0.25 + luminanceD * 0.25 + luminanceF * 0.25 + luminanceH * 0.25 - luminanceE; // 中心与四邻均值之差就是噪声估计。
        noise = ogxSaturate(abs(noise) / (maxCross - minCross)); // 归一化成零到一。
        weight *= 1.0 - 0.5 * noise; // 噪声越大锐化越弱。
    }
    vec3 sharpen = (sampleB * weight + sampleD * weight + sampleF * weight + sampleH * weight + sampleE) / (1.0 + 4.0 * weight); // 用中心减去的邻域平均做锐化。
    return max(sharpen, vec3(0.0)); // 去掉负值。
}

// 放大后的锐化：邻域布局与上面相同，样本取自放大输出画面，用于压低放大带来的软边。
vec3 ogxFsr1(sampler2D upscaledTex, ivec2 texelCoord, float sharpness, bool denoise)
{
    vec3 sampleE = texelFetch(upscaledTex, texelCoord + ivec2(0, 0), 0).rgb; // 中心样本。
    return ogxCas(upscaledTex, sampleE, texelCoord, sharpness, denoise); // 十字对比度判断与上面共用一份。
}

#endif

/*
生成文件：视差模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库视差模块：在地表材质的高度图上沿视线找可见交点，并算视差自阴影与法线。
调用位置：任何使用方块图集高度图做视差的几何片元程序；Minecraft 光影由
    `/omni-gfx/parallax.glsl` 引入，`rendering/parallax.glsl` 只保留选项换算。
可复制示例：调用 ogxParallaxSmooth 传入坐标、切线基与画质参数，返回最终采样像素。
设计原因与取舍：
    方块图集、高度图、切线基、视线位置、分辨率与全部画质参数由调用方传入，库不读取任何引擎状态。
    平滑模式用双线性高度采样加二分细化，锐利模式逐像素穿越图块；两种外观差别明显，所以保留两套函数。
    高度为零表示没有视差数据，统一补成完整高度，避免出现空洞；这一条在所有读取高度的地方都要执行。
*/
#ifndef OGX_PARALLAX_INCLUDED
#define OGX_PARALLAX_INCLUDED

// 数学模块提供法线解码、夹紧与位运算近似。

// 把向量转到切线空间：显式按切线基的三个列向量点乘。
// 为什么不用矩阵乘：Slang 与 GLSL 的行列顺序不同，写成矩阵会在两个后端得到不同结果；
// 三个点乘在两种语言里语义完全相同，也不会触发后端的矩阵类型限制。
vec3 ogxParallaxToTangent(vec3 vector, vec3 tangent, vec3 bitangent, vec3 normal)
{
    return vec3(dot(vector, tangent), dot(vector, bitangent), dot(vector, normal)); // 每一列就是一个基向量。
}

// 双线性高度采样：在图块内跨格子读四角高度并插值，越界处用一层薄壳把空隙补平。
// `tilesBaseTexel` 是图块左上角在图集里的像素坐标，`resolutionMask` 是图块边长的按位掩码。
// `isBlock` 表示是否按方块图集回绕：地形恒为真，实体由调用方判断。
float ogxParallaxHeightBilinear(sampler2D normals, vec2 coord, ivec2 tilesBaseTexel,
    float textureResolution, int resolutionMask, bool isBlock)
{
    ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
    ivec2 texelW = texelX + 1; // 右上角像素。
    vec2 fraction = coord - vec2(texelX); // 到左下角的小数偏移。
    if (isBlock) // 方块图集按图块回绕。
    {
        texelX = tilesBaseTexel + (texelX & resolutionMask); // 左下角回绕到本图块内。
        texelW = tilesBaseTexel + (texelW & resolutionMask); // 右上角同理。
    }
    vec4 heights = vec4(texelFetch(normals, texelX, 0).a, // 左下角高度。
        texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a, // 右下角高度。
        texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a, // 左上角高度。
        texelFetch(normals, texelW, 0).a); // 右上角高度。
    heights += ogxSaturate(1.0 - heights * 1e20); // 高度为零表示没有视差数据，补成完整高度，避免出现空洞。
    return mix(mix(heights.x, heights.y, fraction.x), // 先沿横轴插值两对。
        mix(heights.z, heights.w, fraction.x), // 再沿横轴插值另外两对。
        fraction.y); // 最后沿纵轴插值得到高度。
}

// 用高度差直接生成法线：平滑模式可以只用高度场求梯度，得到与视差一致的法线。
// `mode` 为二时用中心差分，否则用带边缘压平的梯度；两种曲线照原程序保留。
vec3 ogxParallaxHeightNormal(sampler2D normals, vec2 coord, ivec2 tilesBaseTexel,
    float textureResolution, int resolutionMask, bool isBlock, float depth, int mode)
{
    coord -= 0.5; // 把坐标移到像素中心。
    ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
    ivec2 texelW = texelX + 1; // 右上角像素。
    vec2 fraction = coord - vec2(texelX); // 小数偏移。
    if (isBlock) // 方块图集按图块回绕。
    {
        texelX = tilesBaseTexel + (texelX & resolutionMask); // 左下角回绕。
        texelW = tilesBaseTexel + (texelW & resolutionMask); // 右上角同理。
    }
    vec4 heights = vec4(texelFetch(normals, texelX, 0).a, // 四角高度。
        texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a,
        texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a,
        texelFetch(normals, texelW, 0).a);
    if (mode == 2) // 平滑模式：直接由四角高度差得到梯度。
    {
        heights.w = heights.y + heights.z - heights.x - heights.w; // 把四角合成一个中心差分量。
        return vec3(heights.w * fraction.yx + (heights.x - heights.yz), (8.0 / depth) / textureResolution); // 梯度乘深度再归一化，深度越大法线越陡。
    }
    const float eps = 0.01; // 靠近像素边缘时梯度会突变，用一个小阈值把它压平。
    fraction -= 0.5; // 偏移改到像素中心附近。
    float dx = mix(heights.x - heights.y, heights.z - heights.w, ogxSaturate(fraction.y * 1e20)) * ogxSaturate((eps - abs(fraction.x)) * 1e20); // 横向梯度，越靠边越弱。
    float dy = mix(heights.x - heights.z, heights.y - heights.w, ogxSaturate(fraction.x * 1e20)) * ogxSaturate((eps - abs(fraction.y)) * 1e20); // 纵向梯度同理。
    return vec3(dx, dy, step(abs(dx) + abs(dy), 0.0)); // 没有梯度的地方朝外。
}

// 锐利模式的命中法线处理：按「由凹凸生成法线」的取值决定是否换回贴图法线或远处淡出。
vec3 ogxParallaxHitNormal(sampler2D normals, ivec2 parallaxTexel, vec3 hitNormal, float fade,
    bool fadeEnabled, int basedNormal)
{
    if (basedNormal == 1) // 仅侧面：只有步进里命中侧面时才用视差法线。
    {
        if (fadeEnabled) // 远处淡出到贴图法线。
        {
            hitNormal = mix(ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb), hitNormal, fade * (1.0 - hitNormal.z));
        }
        else if (hitNormal.z == 1.0) // 没命中侧面时用贴图法线。
        {
            hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb);
        }
    }
    else if (basedNormal == 2 && fadeEnabled) // 全部用视差法线且需淡出时。
    {
        hitNormal = mix(vec3(0.0, 0.0, 1.0), hitNormal, fade); // 远处淡出到朝外法线。
    }
    return hitNormal; // 交回处理后的法线。
}

// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
// `tbn` 是切线基，`shadowVector` 是视空间阳光方向，`duv1`、`duv2` 是纹理坐标的屏幕导数。
// `normalTex` 与 `parallaxShadow` 是输入输出：前者带回法线，后者带回被遮挡后的受光比例。
ivec2 ogxParallaxSmooth(vec2 coord, vec3 tangent, vec3 bitangent, vec3 normal, vec3 shadowVector, vec2 duv1, vec2 duv2, vec3 viewPos,
    sampler2D normals, vec2 atlasSize, float textureResolution, bool isBlock,
    float depth, int quality, int refinements, int shadowQuality, bool shadowEnabled, bool taa,
    bool fadeEnabled, float dither, int basedNormal, inout vec3 normalTex, inout float parallaxShadow)
{
    vec2 atlasTiles = atlasSize / textureResolution; // 图集里横纵各有多少个图块。
    float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
    if (fadeEnabled) // 需要淡出时先算这一处的淡出因子。
    {
        vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
        fade = ogxSaturate(pow(max(duvMax.x, duvMax.y), -0.1) * (1.0 / 1.4)); // 像素越小越淡出，避免远处闪烁。
    }
    vec2 tilesBaseCoord = floor(coord * atlasTiles); // 当前坐标落在哪个图块。
    ivec2 tilesBaseTexel = ivec2(tilesBaseCoord * textureResolution); // 该图块左上角的像素坐标。
    int resolutionMask = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
    vec3 parallaxCoord = vec3(coord * atlasSize, 1.0); // 换成图集像素坐标并把深度放到一。
    float sampleHeight = ogxParallaxHeightBilinear(normals, parallaxCoord.xy - 0.5, tilesBaseTexel,
        textureResolution, resolutionMask, isBlock); // 先读起始高度。
    if (sampleHeight > 0.0 && sampleHeight < 1.0) // 只有处在表面内部的像素才需要偏移。
    {
        parallaxCoord.xy -= 0.5; // 坐标移到像素中心。
        vec3 viewVector = ogxParallaxToTangent(normalize(viewPos), tangent, bitangent, normal); // 视线方向转到切线空间。
        viewVector /= -viewVector.z; // 归一化到单位深度步长。
        vec3 stepDir = viewVector / float(quality); // 每一步的方向。
        stepDir.xy *= textureResolution * depth * 0.25; // 横向步长按图块尺寸与深度缩放。
        float stepLength = 2.0 / float(quality); // 逐步加深的初始步长。
        for (int i = 0; i < quality; i++, stepLength += 2.0 / float(quality)) // 线性步进找交点。
        {
            parallaxCoord += stepDir * stepLength; // 前进一小步。
            sampleHeight = ogxParallaxHeightBilinear(normals, parallaxCoord.xy, tilesBaseTexel,
                textureResolution, resolutionMask, isBlock); // 读这一步的高度。
            if (sampleHeight > parallaxCoord.z) break; // 表面高度超过步进深度就找到了交点。
        }
        for (int i = 0; i < refinements; i++) // 二分细化交点。
        {
            if (sampleHeight > parallaxCoord.z) // 越过交点就回退半步。
            {
                parallaxCoord -= stepDir * stepLength; // 回退。
                stepLength *= 0.5; // 步长减半。
            }
            parallaxCoord += stepDir * stepLength; // 再前进一个更小的步。
            sampleHeight = ogxParallaxHeightBilinear(normals, parallaxCoord.xy, tilesBaseTexel,
                textureResolution, resolutionMask, isBlock); // 读高度。
        }
        if (sampleHeight <= parallaxCoord.z) parallaxCoord += stepDir * stepLength * 2.0; // 最后仍未越界就多走两步，避免停在表面下。
        if (shadowEnabled && parallaxShadow > 0.0) // 只有原先允许受光的像素才算阴影。
        {
            vec3 shadowDir = ogxParallaxToTangent(shadowVector, tangent, bitangent, normal); // 阳光方向转到切线空间。
            shadowDir /= shadowDir.z * 0.9 + 0.1; // 归一化到单位深度步长，避免水平方向过大。
            vec3 shadowCoord = parallaxCoord; // 从交点出发。
            vec3 stepSize = shadowDir / float(shadowQuality); // 阴影步进方向。
            stepSize.xy *= textureResolution * depth * 0.25; // 横向步长按图块与深度缩放。
            if (taa) shadowCoord += stepSize * dither; // 开时间抗锯齿时用蓝噪声抖动起点。
            else shadowCoord += stepSize; // 不开时只多走一步。
            for (int i = 0; i < shadowQuality; i++, shadowCoord += stepSize) // 沿光方向步进找遮挡。
            {
                if (shadowCoord.z > 1.0) break; // 超出表面顶部就不再遮挡。
                sampleHeight = ogxParallaxHeightBilinear(normals, shadowCoord.xy, tilesBaseTexel,
                    textureResolution, resolutionMask, isBlock); // 读遮挡候选的高度。
                float diff = shadowCoord.z - sampleHeight; // 光线高度减去表面高度，负得越多遮挡越强。
                parallaxShadow *= ogxSaturate(diff * 40.0 + 1.0); // 逐步累积遮蔽。
                if (parallaxShadow < 0.003) break; // 已经足够黑就提前结束。
            }
            if (fadeEnabled) parallaxShadow = mix(1.0, parallaxShadow, fade); // 远处淡出阴影，避免闪烁。
        }
        parallaxCoord.xy += 0.5; // 坐标移回像素角。
        if (basedNormal == 2) normalTex = ogxParallaxHeightNormal(normals, parallaxCoord.xy,
            tilesBaseTexel, textureResolution, resolutionMask, isBlock, depth, 2); // 由高度场求法线。
        parallaxCoord.xy = (fract(parallaxCoord.xy / textureResolution) + tilesBaseCoord) * textureResolution; // 把偏移后的坐标折回原本的图块。
    }
    ivec2 parallaxTexel = ivec2(parallaxCoord.xy); // 最终要采样到的像素。
    if (basedNormal < 2) // 不是全部用视差法线时，照常从法线贴图取。
    {
        normalTex = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 解出切线空间法线。
    }
    else if (fadeEnabled) // 全部用视差法线时按淡出因子回落到朝外法线。
    {
        normalTex = mix(vec3(0.0, 0.0, 1.0), normalTex, fade); // 远处淡出到朝外法线。
    }
    return parallaxTexel; // 交回被遮挡后的采样像素。
}

// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
// 与平滑模式的区别是每步都跨到下一个纹素边界，边缘更硬，适合像素风材质。
ivec2 ogxParallaxSharp(vec2 coord, vec3 tangent, vec3 bitangent, vec3 normal, vec3 shadowVector, vec2 duv1, vec2 duv2, vec3 viewPos,
    sampler2D normals, vec2 atlasSize, float textureResolution, bool isBlock,
    float depth, int quality, int shadowQuality, bool shadowEnabled, bool fadeEnabled,
    int basedNormal, inout vec3 hitNormal, inout float parallaxShadow)
{
    vec2 atlasTiles = atlasSize / textureResolution; // 图集里横纵各有多少个图块。
    vec2 pixelCoord = coord * atlasSize; // 当前坐标换算成图集像素。
    ivec2 parallaxTexel = ivec2(floor(pixelCoord)); // 起始像素。
    int resolutionMask = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
    float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
    if (fadeEnabled) // 需要淡出时先算这一处的淡出因子。
    {
        vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
        fade = ogxSaturate(pow(max(duvMax.x, duvMax.y), -0.4) * 0.2); // 像素越小越淡出。
    }
    float sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 起始高度。
    sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
    bool exit = false; // 是否命中了表面。
    if (sampleHeight > 0.0 && sampleHeight < 1.0) // 只有处在表面内部才穿越。
    {
        ivec2 tilesPixelBase = ivec2(floor(coord * atlasTiles) * textureResolution); // 当前图块左上角的像素。
        vec3 viewVector = ogxParallaxToTangent(normalize(viewPos), tangent, bitangent, normal); // 视线方向转到切线空间。
        vec3 stepDir = normalize(vec3(viewVector.xy * depth * textureResolution * 0.25, -viewVector.z)); // 每像素前进方向，横向按深度缩放。
        vec2 ardir = abs(1.0 / stepDir.xy); // 每走一个像素在横纵方向各需要多远。
        ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 横纵方向的符号，用位运算取正负一。
        vec2 totalStep = (vec2(sdir) * (0.5 - (pixelCoord - vec2(parallaxTexel))) + 0.5) * ardir; // 到下一个像素边界的距离。
        float stepLength = 0.0; // 这一步走过的深度。
        float stepHeight = 1.0; // 这一步光线所在的高度。
        float prevStepHeight = 1.0; // 上一步高度，用于判断交点落在哪一列。
        ivec2 stepNext = ivec2(0); // 这一步往哪个方向跨像素。
        for (int i = 0; i < quality; i++) // 逐像素前进。
        {
            stepLength = min(totalStep.x, totalStep.y); // 先碰到哪一侧边界就按哪一侧走。
            stepHeight = 1.0 - stepLength * stepDir.z; // 这一步光线到达的高度。
            if (sampleHeight > stepHeight) // 表面高过光线，说明这一段遮挡了像素。
            {
                if (sampleHeight > prevStepHeight) // 交点落在上一步与这一步之间时用上一步的法线。
                {
                    hitNormal = vec3(-stepNext * sdir, 0.0); // 由跨步方向估计侧面法线。
                    sampleHeight = prevStepHeight; // 高度取上一步，便于后续阴影。
                }
                exit = true; // 标记命中。
                break; // 结束步进。
            }
            stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 判断这一步跨的是哪一侧。
            parallaxTexel += stepNext * sdir; // 前进到下一个像素。
            totalStep += vec2(stepNext) * ardir; // 累加边界距离。
            prevStepHeight = stepHeight; // 记下这一步高度。
            if (isBlock) parallaxTexel = tilesPixelBase + (parallaxTexel & resolutionMask); // 方块图集折回本图块。
            sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 读新像素的高度。
            sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
        }
        if (shadowEnabled) // 需要自阴影时。
        {
            vec3 shadowDir = ogxParallaxToTangent(shadowVector, tangent, bitangent, normal); // 阳光方向转到切线空间。
            float shadow = 1.0; // 阴影透过率从全透开始。
            if (dot(shadowDir, hitNormal) * parallaxShadow > 0.0 && exit) // 命中的侧面朝向阳光才需要阴影。
            {
                float currHeight = sampleHeight; // 当前高度。
                stepLength = (1.0 - currHeight) / stepDir.z; // 先走到表面顶部。
                vec2 shadowCoord2d = pixelCoord + stepLength * stepDir.xy; // 到达顶部时的像素坐标。
                ivec2 shadowTexel = ivec2(floor(shadowCoord2d)); // 取整。
                stepDir = normalize(vec3(shadowDir.xy * depth * textureResolution * 0.25, shadowDir.z)); // 换成沿光方向的前进方向。
                vec2 ardirShadow = abs(1.0 / stepDir.xy); // 每像素的边界距离。
                ivec2 sdirShadow = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 方向符号。
                totalStep = (vec2(sdirShadow) * (0.5 - (shadowCoord2d - vec2(shadowTexel))) + 0.5) * ardirShadow; // 到下一像素边界的距离。
                stepNext = ivec2(0); // 复位跨步方向。
                for (int i = 0; i < shadowQuality; i++) // 沿光方向逐像素找遮挡。
                {
                    stepLength = min(totalStep.x, totalStep.y); // 先碰到的边界。
                    stepHeight = currHeight + stepLength * stepDir.z; // 这一步的高度。
                    stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 跨哪一侧。
                    shadowTexel += stepNext * sdirShadow; // 前进到下一个像素。
                    totalStep += vec2(stepNext) * ardirShadow; // 累加边界距离。
                    if (isBlock) shadowTexel = tilesPixelBase + (shadowTexel & resolutionMask); // 方块图集折回本图块。
                    sampleHeight = texelFetch(normals, shadowTexel, 0).a; // 读高度。
                    sampleHeight += ogxSaturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
                    if (sampleHeight > stepHeight) // 表面高过光线，说明被遮挡。
                    {
                        parallaxShadow = 0.0; // 直接判为阴影。
                        break; // 结束。
                    }
                }
                parallaxShadow *= fadeEnabled ? mix(1.0, shadow, fade) : shadow; // 远处淡出阴影，未开淡出时原样。
            }
        }
        hitNormal = ogxParallaxHitNormal(normals, parallaxTexel, hitNormal, fade, fadeEnabled, basedNormal); // 命中后按当前模式处理法线。
    }
    else if (basedNormal == 1) // 没命中侧面就退回贴图法线。
    {
        hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中时直接用贴图法线。
    }
    if (basedNormal == 0) hitNormal = ogxDecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 不用视差法线时一律取贴图法线。
    return parallaxTexel; // 交回最终采样像素。
}

#endif

/*
生成文件：行星模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库行星模块：用解析射线画出整颗行星、光环与大气，不依赖任何宿主状态。
调用位置：末地天空与末地反射；Minecraft 光影由 `/omni-gfx/planet.glsl` 引入，
    `rendering/world/planet.glsl` 只保留时间与阴影强度的换算。
可复制示例：`ogxPlanetEnd(color, eye, rayDir, lightDir, shadowVector, time, planetShadow, noiseTex);`
设计原因与取舍：行星半径、相机高度、时间、阴影强度与噪声贴图全部由调用方传入，库只做纯计算；
    星场与吸积盘不在这里，行星本体只负责地表、环带与大气这三段。
    旋转矩阵沿用原程序的扁平构造参数顺序，生成 GLSL 后由 GLSL 的列主序规则解释，
    与旧实现逐位一致；不要在 Slang 侧改成按列传入。
*/
#ifndef OGX_PLANET_INCLUDED
#define OGX_PLANET_INCLUDED

// 数学提供求交、圆盘剖面与色温，大气提供米氏相位与行星双向反射。


// 画一整颗行星：先与地表球求交，再叠光环与大气，最后把环带的遮挡乘回天空。
// `eye` 是相机在行星坐标系里的位置，`rayDir` 是视线，`lightDir` 是光方向。
// `shadowVector` 只用于米氏相位的观察方向，`time` 驱动行星与光环的缓慢摆动。
// `planetShadow` 是行星落在天空上的阴影强度，`noiseTex` 提供环带细缝的五层噪声。
void ogxPlanetEnd(inout vec3 color, vec3 eye, vec3 rayDir, vec3 lightDir,
    vec3 shadowVector, float time, float planetShadow, sampler2D noiseTex)
{
    const float Rground = 20e6; // 行星半径。
    const float Ratmo = 20.1e6; // 大气层顶半径。
    eye.y += Rground; // 相机抬到行星表面之上。
    eye.y += 15e6; // 再抬高，模拟远离行星的视角。
    float VdotL = dot(shadowVector, rayDir); // 视线与阳光夹角余弦，供相位使用。
    float mie = ogxMiePhase(0.8, VdotL); // 米氏相位。
    float angleX = -1.57079633 + (0.2 * sin(time + 3.0) - 0.1); // 俯仰角随时间摆动。
    float angleY = time; // 偏航角随时间转动。
    mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转矩阵。
    mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转矩阵。
    mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。
    float ringAngle = 0.008 * sin(time + 4.6); // 光环的倾角随时间轻微摆动。
    mat3 ringRoataionMatrix = mat3(1.0, 0.0, 0.0,
                                           0.0, cos(ringAngle), sin(ringAngle),
                                           0.0, -sin(ringAngle), cos(ringAngle)); // 光环旋转矩阵。
    mat3 ringRoataionMatrixInverse = transpose(ringRoataionMatrix); // 光环旋转的逆。
    rayDir = ogxMatrix3MulPoint(eyeRoataionMatrix, rayDir); // 视线转到行星坐标系。
    lightDir = ogxMatrix3MulPoint(eyeRoataionMatrix, lightDir); // 光方向同样转过去。
    vec3 rayDirRing = ogxMatrix3MulPoint(ringRoataionMatrix, rayDir); // 视线转到光环坐标系。
    vec3 lightDirRing = ogxMatrix3MulPoint(ringRoataionMatrix, lightDir); // 光方向转到光环坐标系。
    vec3 ringOrigin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 光环所在平面的原点。
    vec2 ringRadius = vec2(1.6, 2.6); // 光环内外半径。
    vec3 surface = vec3(0.0); // 行星表面与光环累积的颜色。
    float LdotR = dot(rayDir, -lightDir); // 光线与视线夹角余弦。
    vec2 groundIntersection = ogxRaySphereIntersection(eye, rayDir, Rground); // 与行星地表求交。
    vec2 topAtmoIntersection = ogxRaySphereIntersection(eye, rayDir, Ratmo); // 与大气层顶求交。
    vec3 surfacePos = rayDir * groundIntersection.x; // 地表交点位置。
    vec3 surfaceNormal = normalize(surfacePos + vec3(0.0, eye.y, 0.0)); // 地表法线，由球心指向交点。
    if (groundIntersection.y > 0.0) // 射线打到行星本体。
    {
        color *= 0.0; // 本体完全遮住后面的天光。
        vec3 surfaceAlbedo = vec3(0.98, 0.87, 0.55); // 行星表面底色，偏暖白。
        surface = ogxPlanetBrdf(surfaceAlbedo, surfaceNormal, -rayDir, lightDir); // 算地表着色。
        vec3 origin = ringOrigin + surfacePos / Rground; // 光环采样的起点。
        vec3 rayPos = ogxRayPlaneIntersection(origin, lightDirRing, vec3(0.0, 0.0, 1.0)); // 沿光方向与光环平面求交。
        float rayRadius = length(rayPos); // 交点到光环中心的半径。
        if (rayRadius > ringRadius.x && rayRadius < ringRadius.y && dot(rayPos - origin, lightDirRing) > 0.0) // 落在环带内且朝光一侧。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            surface *= exp(-pow(ogxSaturate(ringNoise) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius)); // 噪声把环带压出缝隙。
        }
        float UdotN = ogxSaturate(dot(ringRoataionMatrixInverse[2], surfaceNormal)); // 光环上表面法线与地表法线夹角。
        float DdotN = ogxSaturate(dot(-ringRoataionMatrixInverse[2], surfaceNormal)); // 光环下表面同理。
        float OLdotN = ogxSaturate(dot(ogxMatrix3MulPoint(ringRoataionMatrixInverse, normalize(vec3(-lightDir.xy, 0.0))), surfaceNormal)); // 光线在环面上的投影与法线夹角。
        float ringLighting = ogxDiscProfile(UdotN, 1.2, 1.5) * (1.0 - ogxDiscProfile(UdotN, 3.4, 0.3)); // 上表面环带光照。
        ringLighting += ogxDiscProfile(DdotN, 1.2, 1.5) * (1.0 - ogxDiscProfile(DdotN, 3.4, 0.3)); // 下表面环带光照。
        ringLighting *= 1.0 - ogxDiscProfile(OLdotN, 0.7, 1.3); // 被行星自身挡住的部分去掉。
        surface += surfaceAlbedo * (1.5e-4 + ringLighting * 0.01); // 环带光叠到地表上。
    }
    if (topAtmoIntersection.y > 0.0) // 射线经过大气层。
    {
        float isGround = step(0.0, groundIntersection.y); // 是否打到地面。
        float thickness = (topAtmoIntersection.y - topAtmoIntersection.x - (groundIntersection.y - groundIntersection.x) * isGround) * 1e-7; // 大气层内的光学厚度。
        float topAtmoMie = mie * thickness * thickness; // 米氏散射。
        topAtmoMie *= mix(1.0, smoothstep(0.9, 0.4, dot(surfaceNormal, normalize(eye))), isGround); // 打到地面时按视线角度衰减。
        surface += topAtmoMie * vec3(0.65, 0.7, 1.0); // 大气偏冷蓝。
    }
    color += surface * 0.6; // 地表与大气叠加到画面。
    float inRing = ogxSaturate(abs(ringAngle) * 3000.0 - 0.8); // 当前是否正对环面。
    float ring = 0.0; // 环带的亮度。
    float transmittance = 1.0; // 环带留下的透过率。
    if (rayDirRing.z * ringAngle < 0.0) // 视线穿过环面。
    {
        vec3 origin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 环面原点。
        vec3 ringPos = ogxRayPlaneIntersection(origin, rayDirRing, vec3(0.0, 0.0, 1.0)); // 视线与环面求交。
        float rayRadius = length(ringPos); // 交点到环心半径。
        vec2 ringRadius2 = vec2(1.6, 2.6); // 环带内外半径。
        if (rayRadius > ringRadius2.x && rayRadius < ringRadius2.y) // 落在环带内。
        {
            float ringNoise = ogxPlanetRingNoise(rayRadius * 0.5 + 0.69, noiseTex); // 五层噪声叠出环带细缝。
            ring += pow(ogxSaturate(ringNoise) * 1.5, 3.0); // 噪声得到环带形状。
            ring *= smoothstep(ringRadius2.x, ringRadius2.x * 1.1, rayRadius); // 内边缘渐入。
            if (ringPos.y < 0.0 && groundIntersection.y > 0.0) // 交点在环面下方且视线打到地面。
            {
                ring *= 0.0; // 被行星本体挡住，环带不显示。
            }
            else
            {
                transmittance *= exp2(-ring * 3.0); // 否则环带按厚度吃掉一部分透过。
            }
            float d = length(cross(lightDirRing, ringPos)); // 交点到光方向的垂距。
            ring *= 0.98 * max(smoothstep(0.8, 1.2, d), step(0.0, dot(lightDirRing, ringPos))) + 0.02; // 朝光一侧更亮，加一点底亮。
        }
    }
    ring = mix(planetShadow * 0.49 + 0.01, ring, inRing); // 正对环面时用环带亮度，否则用行星阴影的固定暗带。
    transmittance = mix(0.7, transmittance, inRing); // 透过率同样按是否正对环面切换。
    color *= transmittance; // 环带吃掉一部分天光。
    ring *= 1.0 + mie * 10.0 * planetShadow; // 正对时叠一份米氏散射。
    color += ring * 0.012 * vec3(1.0, 0.85, 0.60); // 环带偏暖黄叠到画面。
}

// iterationT 末地天空的 p 曲线：四次方乘一次线性衰减，末端回到零。
float ogxEndSkyPCurve(float x)
{
    float x2 = x * x; // 平方。
    return 12.207 * x2 * x2 * (1.0 - x); // 四次方乘剩余量。
}

#endif

/*
生成文件：吸积盘模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库吸积盘模块：沿视线在黑洞附近步进，累加盘的颜色与透过率。
调用位置：任何需要画黑洞吸积盘的程序；Minecraft 光影由 `/omni-gfx/accretion.glsl` 引入，
    `rendering/world/end_disc.glsl` 的天空版与反射版只差参数，不再各写一份积分。
可复制示例：`vec4 d = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, seconds, 50, 3.0, 4, false, true);`
    返回 `rgb` 为盘颜色、`a` 为透过率。
设计原因与取舍：
    天空版与反射版只差步数、起点、噪声指数与是否叠星空；积分、空间扭曲与盘着色完全共用，所以放进通用库。
    星空仍由效果层叠加，因为那是末地天空的业务；本模块只依赖方向、噪声纹理与时间。
    写法与常数照 iterationT 原程序保留，包括圆环辉光、黑体色温与多普勒调制。
    方位角用库自己的 `ogxAtan2`，不再借用宿主的同名包装，保证模块可以单独编译。
*/
#ifndef OGX_ACCRETION_INCLUDED
#define OGX_ACCRETION_INCLUDED

// 数学提供黑体、旋转、径向轮廓与空间扭曲，雾模块提供分形噪声。


// 吸积盘积分：`steps` 是步数，`startOffset` 是起始位置离黑洞的距离，
// `densityPower` 是噪声幂次（天空版四、反射版五），`detailAlongLongitude` 决定细节是否沿方位角分布，
// `doppler` 打开后按方位角调制亮度。返回 rgb 盘颜色与 a 透过率。
vec4 ogxAccretionDisc(vec3 rayDir, vec3 lightDir, float noise, sampler2D noiseTexture, float seconds,
    int steps, float startOffset, int densityPower, bool detailAlongLongitude, bool doppler)
{
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 吸积盘半径。
    const float discWidth = 3.5; // 吸积盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内半径。
    float rSteps = 1.0 / float(steps); // 步数倒数，最后做平均。
    vec3 eye = -lightDir * 8.0; // 视线起点。
    vec3 rayPos = eye + rayDir * startOffset; // 起始步进位置。
    mat3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 吸积盘的固定倾角。
    vec3 result = vec3(0.0); // 累积的盘颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少步进条纹。
    for (int i = 0; i < steps; i++) // 逐步前进。
    {
        if (transmittance < 0.0001) break; // 已被遮满就停止。
        ogxWarpSpace(rayDir, rayPos); // 靠近黑洞时光线被拉弯。
        rayPos += rayDir * stepLength; // 前进一步。
        vec3 discPos = ogxMatrix3MulPoint(rotation, rayPos); // 转到吸积盘坐标系。
        float r = length(discPos); // 到盘中心的半径。
        float p = ogxAtan2(-discPos.zx); // 盘面上的方位角。
        float h = discPos.y; // 离盘面的高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向衰减。
        float dist = abs(h); // 到盘面的距离。
        float discThickness = 0.1 * radialGradient; // 盘的厚度随半径变化。
        float fr = abs(r - discInner) + 0.4; // 到内边缘的距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 亮度衰减。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 靠近盘面的辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 只在盘厚范围内。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxRadialCurve(radialGradient); // 径向轮廓。
        float density = dr; // 当前密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 按离盘面距离衰减。
        density = ogxSaturate(density * 0.7); // 整体缩放。
        density = ogxSaturate(density + bloomFactor * 0.1); // 叠上辉光。
        if (density > 0.0001) // 有密度才算这一步的颜色。
        {
            vec3 discCoord; // 噪声采样坐标。
            vec3 shift; // 噪声随时间流动的方向。
            if (detailAlongLongitude) // 细节沿纬度分布时用方位角。
            {
                discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5;
                shift = seconds * vec3(0.1, 0.07, 0.0);
            }
            else // 默认细节只沿半径与高度分布。
            {
                discCoord = vec3(r, 0.0, h * 0.1) * 3.5;
                shift = seconds * vec3(0.03, 0.05, 0.0);
            }
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, 64.0); // 高质量云噪声。
            if (densityPower == 4) // 天空版：噪声四次方。
            {
                fbm = fbm * fbm;
                fbm = fbm * fbm;
                density *= fbm * dr;
            }
            else // 反射版：噪声五次方，写法与原程序一致。
            {
                float fbm2 = fbm * fbm;
                density *= fbm2 * fbm2 * fbm;
                density *= dr;
            }
            float gr = 1.0 - radialGradient; // 反径向。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮的辉光。
            vec3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应：一侧更亮。
            float stepTransmittance = exp2(-density * 7.0); // 这一步的透过率。
            float integral = 1.0 - stepTransmittance; // 这一步吸收掉的量。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 按透过率累加颜色。
        }
        vec2 t = vec2(1.0, 0.01); // 圆环截面参数。
        float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        vec3 ringColor = ogxBlackbody(12000.0); // 高色温的冷白。
        bloomDisc *= step(0.5, r); // 只在盘外缘以外。
        result += ringColor * bloomDisc * 0.1 * transmittance; // 叠上圆环辉光。
    }
    result *= rSteps; // 步数平均。
    return vec4(result, transmittance); // 交回盘颜色与剩余透过率。
}

#endif

/*
生成文件：光传播体积模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库光传播体积模块：三维彩色间接光的取样、编码与边缘淡出。
调用位置：任何把体素网格里的彩色间接光取回表面的程序；Minecraft 光影由 `shaders/rendering/lighting/lpv.glsl` 调用。
可复制示例：
    `vec4 texel = ogxLpvDecodeSample(stored, vec2(15.0, 24.0));` 解码存下的色相与亮度。
    `vec3 block = ogxLpvBlockLight(texel);` 取回彩色方块光。
    `float sky = ogxLpvSkyLight(texel);` 取回天光。
设计原因与取舍：
    纹理句柄、帧号奇偶与网格尺寸全部由调用方传入，库只收已经取到的四分量样本，
    因此同一份算式能同时用于 GLSL 330 与 SPIR-V，不绑定任何引擎的三维纹理约定。
    编码沿用“色相照原样存、饱和度与天光取对数”的方案，解码必须与编码逐项对齐，
    否则一进一出之后光色会偏，这也是这对函数放在同一个文件里的原因。
*/
#ifndef OGX_LPV_INCLUDED
#define OGX_LPV_INCLUDED

// 光色与解码都要用颜色换算，直接引入颜色模块，它已经带上数学模块。

// 方块光的亮度系数：存下的颜色取值零到十五，除以十五得到零到一。
const float OGX_LPV_BLOCK_BRIGHTNESS = 0.066666;

// 体积光的亮度曲线：平方放大，让弱光抬起来、强光更快饱和。
// 与解码端的曲线必须一致，改一处就要同步另一处，否则光强会整体漂移。
float ogxLpvCurve(float value) { return value * value; }

// 把归一化坐标换成三维纹理坐标：体积边长由调用方给出。
vec3 ogxLpvUvw(vec3 lpvPos, float side) { return lpvPos / side; }

// 把相机相对位置搬进体积中心：加上相机所在格的小数部分，玩家走动时体积按整格平移。
vec3 ogxLpvPosition(vec3 playerPos, vec3 cameraFract, float halfSide)
{
    return playerPos + cameraFract + halfSide;
}

// 解码一个已经取到的体积样本：先按色相还原颜色，再按平方曲线放大亮度并归一到零到一。
// 为什么先当颜色再转 HSV：写入端把亮度压进饱和度通道，读回来必须走同一条逆路径。
// 参数名不用 `sample`：它在 GLSL 4.0 以后是插值限定符，430 的计算程序会直接报语法错误。
vec4 ogxLpvDecodeSample(vec4 texel, vec2 blockSkyRange)
{
    vec3 hsv = ogxRgbToHsv(texel.rgb);
    hsv.z = ogxLpvCurve(hsv.b) * blockSkyRange.x;
    texel.rgb = ogxHsvToRgb(hsv);
    texel.rgb = ogxSaturate(texel.rgb / 15.0);
    return texel;
}

// 彩色方块光：亮度系数乘解码后的颜色，供表面照明使用。
vec3 ogxLpvBlockLight(vec4 texel) { return OGX_LPV_BLOCK_BRIGHTNESS * texel.rgb; }

// 天光：先夹到零到一，再平方，暗处变化更柔和。
float ogxLpvSkyLight(vec4 texel)
{
    float skyLight = ogxSaturate(texel.a);
    return skyLight * skyLight;
}

// 写入端的编码：色相照原样，饱和度与天光取对数，压住八位图存不下的动态范围。
vec4 ogxLpvEncode(vec4 value, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(value.rgb), value.a);
    hsvSky.zw = log2(hsvSky.zw + 1.0) / blockSkyRange;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 传播阶段读回上一步结果的解码：与编码严格互逆，指数还原后再减一。
vec4 ogxLpvDecode(vec4 stored, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(stored.rgb), stored.a);
    hsvSky.zw = exp2(hsvSky.zw * blockSkyRange) - 1.0;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 体积边缘淡出：先算到六个面的距离比，三轴相乘后中心满值、边缘归零。
// 为什么要再压一次曲线：直接相乘在角上掉得太快，会看到明显的方形边界。
float ogxLpvRangeFalloff(vec3 lpvPos, float side, float fadeLength)
{
    vec3 cubicRadius = clamp(min((vec3(side) - 1.0 - lpvPos) / fadeLength, lpvPos / fadeLength), vec3(0.0), vec3(1.0));
    float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z;
    return 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0);
}

// 把体积光混回原来的方块光：淡出乘强度当权重，零强度时原样返回。
vec3 ogxLpvApply(vec3 blockLight, vec4 texel, float falloff, float strength)
{
    return mix(blockLight, texel.rgb, ogxSaturate(falloff * strength));
}

#endif

/*
生成文件：延迟缓冲模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 G-buffer 解码模块：把多张中间画面还原成表面数据、材质与光源标记。
调用位置：需要读取延迟着色中间画面的程序；Minecraft 光影由 `/omni-gfx/gbuffer.glsl` 引入。
可复制示例：
    OgxGbufferData d = ogxGetGbufferData(g0, g3, g4, g5, g6, depth1, depth0, texel, true, ...);
    OgxMaterialMask m = ogxCalculateMasks(d.materialIDL, ids);
设计原因与取舍：
    参考实现直接读取 colortex 与固定材质编号。库改成显式传入纹理、像素坐标、编号表与选项，
    这样算法本身不依赖 Minecraft，调用方仍可按自己的缓冲布局填写。
    `GetGbufferData` 的每一行读取顺序与参考实现一致；材质编号只通过 `OgxMaterialIdTable`
    传入，避免把资源包的编号约定写死进通用库。
*/
#ifndef OGX_GBUFFER_INCLUDED
#define OGX_GBUFFER_INCLUDED

// 表面模块提供 labPBR 材质解码，数学模块提供解包与法线解码。


// 材质编号表：参考实现的 MATID 常量由宿主资源包决定，这里集中成一个显式结构。
struct OgxMaterialIdTable
{
    float sky; // 天空。
    float land; // 普通陆地。
    float beaconBeam; // 信标光束，多个分支会额外匹配它。
    float grass; // 草。
    float leaves; // 树叶。
    float hand; // 手部。
    float water; // 水。
    float stainedGlass; // 染色玻璃。
    float ice; // 冰。
    float entitiesPlayer; // 玩家实体。
    float entitiesLitHigh; // 高亮实体。
    float entitiesLitMedium; // 中亮实体。
    float entitiesLitLow; // 低亮实体。
    float lightning; // 闪电。
    float entitiesSnow; // 积雪实体。
    float torch; // 火把。
    float lava; // 岩浆。
    float glowstone; // 荧石。
    float fire; // 火焰。
    float redstoneTorch; // 红石火把。
    float redstone; // 红石元件。
    float soulFire; // 灵魂火。
    float amethyst; // 紫水晶。
    float oxidizedBulb; // 氧化铜灯。
    float particle; // 普通粒子。
    float particleLit; // 受光粒子。
    float endPortal; // 末地传送门。
    float selection; // 选择框。
};

// 光源标记：每一项都是零或一，表示该像素属于哪类发光体或特殊表面。
struct OgxMaterialMask
{
    float sky; // 天空。
    float land; // 普通陆地。
    float grass; // 草。
    float leaves; // 树叶。
    float hand; // 手部。
    float entityPlayer; // 玩家实体。
    float water; // 水。
    float stainedGlass; // 染色玻璃。
    float ice; // 冰。
    float entitiesLitHigh; // 高亮实体。
    float entitiesLitMedium; // 中亮实体。
    float entitiesLitLow; // 低亮实体。
    float lightning; // 闪电。
    float entitiesSnow; // 积雪实体。
    float torch; // 火把。
    float lava; // 岩浆。
    float glowstone; // 荧石。
    float fire; // 火焰。
    float redstoneTorch; // 红石火把。
    float redstone; // 红石元件。
    float soulFire; // 灵魂火。
    float amethyst; // 紫水晶。
    float oxidizedBulb; // 氧化铜灯。
    float particle; // 普通粒子。
    float particleLit; // 受光粒子。
    float endPortal; // 末地传送门。
    float selection; // 选择框。
};

// G-buffer 解码结果：字段与参考实现一一对应，调用方按需读取。
struct OgxGbufferData
{
    vec3 albedo; // 近景线性底色。
    vec4 albedoW; // 远景线性底色，第四个分量保留解包值。
    vec3 normalL; // 近景视空间法线。
    vec3 normalW; // 远景视空间法线。
    float depthL; // 近景屏幕深度。
    float depthW; // 远景屏幕深度。
    vec2 lightmapL; // 近景方块光与天光。
    vec2 lightmapW; // 远景方块光与天光。
    float materialIDL; // 近景材质编号，已归一化。
    float materialIDW; // 远景材质编号，已归一化。
    float waterMask; // 水面覆盖。
    float rainAlpha; // 雨幕透明度。
    float parallaxShadow; // 视差阴影。
    OgxPbrMaterial material; // labPBR 材质参数。
};

// 把材质编号还原成光源标记：与参考实现逐项比较，顺序一致。
// 为什么用显式编号表：不同资源包对同一方块的编号可能不同，表由调用方在边界填写。
OgxMaterialMask ogxCalculateMasks(float materialIDs, OgxMaterialIdTable ids)
{
    OgxMaterialMask mask; // 待填的标记。
    materialIDs = floor(materialIDs * 255.0); // 参考实现把零到一编码还原成整数编号。
    mask.sky = float(materialIDs == ids.sky); // 天空。
    mask.land = float(materialIDs == ids.land); // 普通陆地。
    mask.grass = float(materialIDs == ids.grass || materialIDs == ids.beaconBeam); // 草与信标光束共用同一分支。
    mask.leaves = float(materialIDs == ids.leaves); // 树叶。
    mask.hand = float(materialIDs == ids.hand); // 手部。
    mask.water = float(materialIDs == ids.water); // 水。
    mask.stainedGlass = float(materialIDs == ids.stainedGlass); // 染色玻璃。
    mask.ice = float(materialIDs == ids.ice); // 冰。
    mask.entityPlayer = float(materialIDs == ids.entitiesPlayer); // 玩家实体。
    mask.entitiesLitHigh = float(materialIDs == ids.entitiesLitHigh || materialIDs == ids.beaconBeam); // 高亮实体与信标共用分支。
    mask.entitiesLitMedium = float(materialIDs == ids.entitiesLitMedium); // 中亮实体。
    mask.entitiesLitLow = float(materialIDs == ids.entitiesLitLow); // 低亮实体。
    mask.entitiesSnow = float(materialIDs == ids.entitiesSnow || materialIDs == ids.beaconBeam); // 积雪实体与信标共用分支。
    mask.lightning = float(materialIDs == ids.lightning); // 闪电。
    mask.torch = float(materialIDs == ids.torch); // 火把。
    mask.lava = float(materialIDs == ids.lava); // 岩浆。
    mask.glowstone = float(materialIDs == ids.glowstone); // 荧石。
    mask.fire = float(materialIDs == ids.fire); // 火焰。
    mask.redstoneTorch = float(materialIDs == ids.redstoneTorch); // 红石火把。
    mask.redstone = float(materialIDs == ids.redstone); // 红石元件。
    mask.soulFire = float(materialIDs == ids.soulFire); // 灵魂火。
    mask.amethyst = float(materialIDs == ids.amethyst); // 紫水晶。
    mask.oxidizedBulb = float(materialIDs == ids.oxidizedBulb); // 氧化铜灯。
    mask.particle = float(materialIDs == ids.particle); // 普通粒子。
    mask.particleLit = float(materialIDs == ids.particleLit); // 受光粒子。
    mask.endPortal = float(materialIDs == ids.endPortal); // 末地传送门。
    mask.selection = float(materialIDs == ids.selection); // 选择框。
    return mask; // 交回全部标记。
}

// 修正粒子覆盖：粒子层本身不写入水面与玻璃标记，要把固体层的标记压掉并让深度统一。
// `modernVersion` 对应参考实现的 MC_VERSION >= 11500 条件；旧版本保留原标记。
void ogxFixParticleMask(inout OgxMaterialMask solidMask, inout OgxMaterialMask mask, inout float depthL, float depthW, bool modernVersion)
{
    if (modernVersion && (solidMask.particle > 0.5 || solidMask.particleLit > 0.5)) // 固体层确实有粒子才修正。
    {
        mask.particle = 1.0; // 标记为粒子。
        mask.water = 0.0; // 粒子不继承水。
        mask.stainedGlass = 0.0; // 也不继承染色玻璃。
        mask.ice = 0.0; // 也不继承冰。
        mask.sky = 0.0; // 有粒子就不是天空。
        depthL = depthW; // 深度改用远景，避免粒子被近景深度裁掉。
    }
}

// 只修标记、不改深度的重载，供不需要深度修正的绘制阶段使用。
void ogxFixParticleMaskNoDepth(inout OgxMaterialMask solidMask, inout OgxMaterialMask mask, bool modernVersion)
{
    if (modernVersion && (solidMask.particle > 0.5 || solidMask.particleLit > 0.5)) // 与上一函数同一判据。
    {
        mask.particle = 1.0; // 标记为粒子。
        mask.water = 0.0; // 清掉水标记。
        mask.stainedGlass = 0.0; // 清掉玻璃标记。
        mask.ice = 0.0; // 清掉冰标记。
        mask.sky = 0.0; // 清掉天空标记。
    }
}

// 解码整套 G-buffer：读取顺序、通道分配与参考实现一致，所有纹理由调用方传入。
// `pbr` 关闭时使用空气材质；`mcBefore11605` 对应旧版本把远景反射强度乘上深度阈值。
OgxGbufferData ogxGetGbufferData(sampler2D gbuffer0, sampler2D gbuffer3, sampler2D gbuffer4, sampler2D gbuffer5,
    sampler2D gbuffer6, sampler2D depthTex1, sampler2D depthTex0, ivec2 texelCoord, bool pbr, bool usePorosity,
    int pbrFormat, float defaultPorosity, float porosityAbsorption, bool roughnessClamp, float emissivenessGamma,
    float sssStrength, float sssOffset, float wet, bool mcBefore11605)
{
    OgxGbufferData data; // 待填的结果。
    vec4 g0 = texelFetch(gbuffer0, texelCoord, 0); // 第一张：近景底色与雨幕。
    vec4 g3 = texelFetch(gbuffer3, texelCoord, 0); // 第三张：近景法线与光照图。
    vec4 g4 = texelFetch(gbuffer4, texelCoord, 0); // 第四张：远景法线与光照图。
    vec4 g5 = texelFetch(gbuffer5, texelCoord, 0); // 第五张：近景材质与视差。
    vec4 g6 = texelFetch(gbuffer6, texelCoord, 0); // 第六张：远景材质与水面。
    data.albedo = ogxGammaToLinear(g0.rgb); // 近景底色从伽马空间换到线性。
    data.albedoW = vec4(ogxUnpack2x8(g6.r), ogxUnpack2x8(g6.g)); // 远景底色由两个八位打包值解开。
    data.albedoW.rgb = ogxGammaToLinear(data.albedoW.rgb); // 远景底色同样转线性。
    data.normalL = ogxDecodeNormal(g3.rg); // 近景法线由两个八位编码还原。
    data.normalW = ogxDecodeNormal(g4.rg); // 远景法线同样还原。
    data.depthL = texelFetch(depthTex1, texelCoord, 0).x; // 近景屏幕深度。
    data.depthW = texelFetch(depthTex0, texelCoord, 0).x; // 远景屏幕深度。
    data.lightmapL = g3.ba; // 近景方块光与天光。
    data.lightmapW = g4.ba; // 远景方块光与天光。
    data.lightmapL = vec2(data.lightmapL.r, ogxCurveBlockLightSky(data.lightmapL.g)); // 天光走同一条曲线。
    data.lightmapW = vec2(data.lightmapW.r, ogxCurveBlockLightSky(data.lightmapW.g)); // 远景同样处理。
    data.materialIDL = g5.b; // 近景材质编号。
    data.materialIDW = g6.b; // 远景材质编号。
    data.waterMask = g6.a; // 远景第四通道是水面覆盖。
    data.rainAlpha = 1.0 - g0.a; // 近景第四通道是雨幕。
    vec2 g5a = ogxUnpack2x8(g5.a); // 第五张透明通道打包了湿润度与视差阴影。
    data.parallaxShadow = g5a.y; // 第二个分量是视差阴影。
    if (pbr) // 开启 labPBR 才解码材质。
    {
        vec4 specTex = vec4(ogxUnpack2x8(g5.r), ogxUnpack2x8(g5.g)); // 红绿通道拆成四字节材质图。
        data.material = ogxItxMaterialFromTex(data.albedo, specTex, g5a.x, usePorosity, pbrFormat,
            defaultPorosity, porosityAbsorption, roughnessClamp, emissivenessGamma, sssStrength, sssOffset); // 复用同一套材质解码。
        if (mcBefore11605) data.material.reflectionStrength *= float(data.depthW >= 0.7); // 旧版本远景才允许反射。
    }
    else // 没有 PBR 时退到空气材质。
    {
        data.material.roughness = 1.0; // 空气没有高光。
        data.material.metalness = 0.0; // 不是金属。
        data.material.f0 = 0.0; // 没有反射率。
        data.material.emissiveness = 0.0; // 不发光。
        data.material.scattering = 0.0; // 不散射。
        data.material.reflectionStrength = 0.0; // 不反射。
    }
    return data; // 交回解码结果。
}

#endif

/*
生成文件：手持光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库手持光模块：把玩家手持光源与手电筒照到表面，并给出高光。
调用位置：需要动态手持光照的程序；Minecraft 光影由 `/omni-gfx/heldlight.glsl` 引入。
可复制示例：
    vec3 held = ogxHeldLighting(viewPos, viewDir, normal, 0.4, ao, false, ...);
    ogxTorchSpecularHighlight(color, viewPos, viewDir, dist, albedo, normal, material, ...);
设计原因与取舍：
    参考实现用编译期开关选择手电筒或火把两种模型。库把开关变成显式参数，两条公式都保留，
    调用方按自己的设置走其中一条，不会因缺少宏而得到另一种画面。
    屏幕空间阴影、投影矩阵、光色与强度全部显式传入；模块本身不读取任何相机或世界状态。
*/
#ifndef OGX_HELDLIGHT_INCLUDED
#define OGX_HELDLIGHT_INCLUDED

// 表面模块提供手电筒光斑与指向，阴影模块提供屏幕空间阴影，数学模块提供漫反射与高光。



// 手电筒模型的手持光：两个光源分别位于左右手，按光斑、距离衰减与漫反射累加。
// `aimDir` 是光束指向，`heldLightShadow` 为真时每个光斑再乘屏幕空间阴影。
vec3 ogxHeldLightingSpot(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    float heldBlockLightValue, float heldBlockLightValue2, vec3 aimDir, vec3 lightColor, float brightness,
    float posRX, float posRY, float posLX, float posLY, float fov, float falloff, bool overworld, bool heldLightShadow,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise, bool hasDh, int shadowSteps)
{
    float heldLightFalloff = 0.0; // 两个光源累加后的强度。
    if (isHand) // 手部不参与光束，只给一个很弱的底光。
    {
        heldLightFalloff = 0.01 * max(heldBlockLightValue, heldBlockLightValue2); // 参考实现的固定系数。
    }
    else
    {
        if (heldBlockLightValue > 0.0) // 右手光源。
        {
            vec3 spotPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源在视空间的位置。
            float spotDistR = length(spotPosR); // 到光源的距离。
            vec3 shadowDirR = spotPosR / spotDistR; // 从光源指向表面的方向。
            float spotR = pow(max(spotDistR, 0.6), -falloff); // 距离衰减，近处限幅避免爆亮。
            spotR *= ogxSpotShape(dot(shadowDirR, aimDir), fov); // 乘光斑形状。
            if (heldLightShadow) // 开关打开才采样屏幕空间阴影。
            {
                spotR *= ogxScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirR, depthTexture, dhDepthTexture,
                    projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                    shadowSteps, 0.85); // 强度零点八五与参考的乘零点八五加零点一五一致。
            }
            spotR *= ogxDiffuseBurley(normal, -viewDir, -shadowDirR, roughness) * 1.7 + 0.05; // 漫反射权重。
            heldLightFalloff += heldBlockLightValue * spotR; // 按光源等级累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手光源。
        {
            vec3 spotPosL = viewPos - vec3(posLX, posLY, 0.0); // 左手位置。
            float spotDistL = length(spotPosL); // 到光源距离。
            vec3 shadowDirL = spotPosL / spotDistL; // 光源到表面方向。
            float spotL = pow(max(spotDistL, 0.6), -falloff); // 距离衰减。
            spotL *= ogxSpotShape(dot(shadowDirL, aimDir), fov); // 光斑形状。
            if (heldLightShadow) // 同样可开阴影。
            {
                spotL *= ogxScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirL, depthTexture, dhDepthTexture,
                    projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                    shadowSteps, 0.85); // 与右手相同。
            }
            spotL *= ogxDiffuseBurley(normal, -viewDir, -shadowDirL, roughness) * 1.7 + 0.05; // 漫反射权重。
            heldLightFalloff += heldBlockLightValue2 * spotL; // 累加左手贡献。
        }
    }
    float scale = overworld ? 0.02 : 0.2; // 下界末地放大十倍。
    return lightColor * (ao * 0.5 + 0.5) * (heldLightFalloff * (brightness * scale)); // 乘遮蔽与整体亮度。
}

// 火把模型的手持光：光源贴近相机，用距离曲线给一个柔和球状光。
// 开启阴影时按左右手分别做屏幕空间阴影与漫反射，否则只按相机距离衰减。
vec3 ogxHeldLightingTorch(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    float heldBlockLightValue, float heldBlockLightValue2, vec3 lightColor, float brightness,
    float posRX, float posRY, float posLX, float posLY, float falloff, bool overworld, bool heldLightShadow,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise, bool hasDh, int shadowSteps)
{
    float heldLightFalloff = 0.0; // 累加强度。
    if (isHand) // 手部只给弱底光。
    {
        heldLightFalloff = 0.2 * max(heldBlockLightValue, heldBlockLightValue2); // 参考实现的固定系数。
    }
    else if (heldLightShadow) // 开阴影时左右手分别计算。
    {
        if (heldBlockLightValue > 0.0) // 右手。
        {
            vec3 torchPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源位置。
            float torchDistR = length(torchPosR); // 距离。
            torchDistR += 4.0 / (torchDistR + 2.0); // 近处的软核，避免距离趋于零时过亮。
            float torchR = pow(torchDistR, -falloff); // 距离衰减。
            vec3 shadowDirR = -normalize(viewPos - vec3(posRX, posRY, 0.0)); // 光源到表面方向。
            torchR *= ogxScreenSpaceShadow(viewPos, viewDir, normal, shadowDirR, depthTexture, dhDepthTexture,
                projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                shadowSteps, 0.85); // 屏幕空间阴影。
            torchR *= ogxDiffuseBurley(normal, -viewDir, shadowDirR, roughness) * 1.7 + 0.05; // 漫反射。
            heldLightFalloff += heldBlockLightValue * torchR; // 累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手。
        {
            vec3 torchPosL = viewPos - vec3(posLX, posLY, 0.0); // 光源位置。
            float torchDistL = length(torchPosL); // 距离。
            torchDistL += 4.0 / (torchDistL + 2.0); // 近处软核。
            float torchL = pow(torchDistL, -falloff); // 距离衰减。
            vec3 shadowDirL = -normalize(viewPos - vec3(posLX, posLY, 0.0)); // 光源到表面方向。
            torchL *= ogxScreenSpaceShadow(viewPos, viewDir, normal, shadowDirL, depthTexture, dhDepthTexture,
                projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                shadowSteps, 0.85); // 屏幕空间阴影。
            torchL *= ogxDiffuseBurley(normal, -viewDir, shadowDirL, roughness) * 1.7 + 0.05; // 漫反射。
            heldLightFalloff += heldBlockLightValue2 * torchL; // 累加。
        }
    }
    else // 没开阴影时用相机距离的解析衰减。
    {
        float torchDist = length(viewPos); // 到相机距离。
        torchDist += 4.0 / (torchDist + 2.0); // 近处软核。
        heldLightFalloff = pow(torchDist, -falloff); // 距离衰减。
        heldLightFalloff *= ogxDiffuseBurley(normal, -viewDir, -viewDir, roughness) + 0.3; // 漫反射加固定底光。
        heldLightFalloff *= heldBlockLightValue + heldBlockLightValue2; // 两个光源等级相加。
    }
    float scale = overworld ? 0.0015 : 0.015; // 下界末地放大十倍。
    return lightColor * (ao * 0.5 + 0.5) * (heldLightFalloff * (brightness * scale)); // 乘遮蔽与亮度。
}

// 手持光总入口：按 `heldLightMode` 在两种参考模型之间选择，两条路径都不丢参数。
vec3 ogxHeldLighting(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    int heldLightMode, float heldBlockLightValue, float heldBlockLightValue2, vec3 aimDir, vec3 lightColor,
    float brightness, float posRX, float posRY, float posLX, float posLY, float fov, float falloff, bool overworld,
    bool heldLightShadow, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection,
    mat4 projectionInverse, mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise,
    bool hasDh, int shadowSteps)
{
    if (heldLightMode > 0) // 手电筒模型。
    {
        return ogxHeldLightingSpot(viewPos, viewDir, normal, roughness, ao, isHand, heldBlockLightValue,
            heldBlockLightValue2, aimDir, lightColor, brightness, posRX, posRY, posLX, posLY, fov, falloff,
            overworld, heldLightShadow, depthTexture, dhDepthTexture, projection, projectionInverse,
            dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh, shadowSteps); // 走光斑路径。
    }
    return ogxHeldLightingTorch(viewPos, viewDir, normal, roughness, ao, isHand, heldBlockLightValue,
        heldBlockLightValue2, lightColor, brightness, posRX, posRY, posLX, posLY, falloff, overworld,
        heldLightShadow, depthTexture, dhDepthTexture, projection, projectionInverse, dhProjectionInverse,
        pixelScale, offsetCoord, noise, hasDh, shadowSteps); // 走火把路径。
}

// 手持光高光：手电筒模型按光斑给镜面高光，火把模型按相机距离给一个柔和镜面。
// `materialRoughness` 会先夹到零点零零二，避免完全光滑时的高光除零。
void ogxTorchSpecularHighlight(inout vec3 color, vec3 viewPos, vec3 viewDir, float dist, vec3 albedo,
    vec3 normal, float materialRoughness, float materialF0, int heldLightMode, float heldBlockLightValue,
    float heldBlockLightValue2, vec3 aimDir, vec3 lightColor, float brightness, float posRX, float posRY,
    float posLX, float posLY, float fov, float falloff, bool overworld)
{
    materialRoughness = max(materialRoughness, 0.002); // 参考实现的粗糙度下限。
    if (heldLightMode > 0) // 手电筒模型。
    {
        float heldHighlight = 0.0; // 高光累加。
        if (heldBlockLightValue > 0.0) // 右手。
        {
            vec3 spotPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源位置。
            float spotDistR = length(spotPosR); // 距离。
            vec3 shadowDirR = spotPosR / spotDistR; // 光源到表面方向。
            float spotR = pow(max(spotDistR, 0.6), -falloff); // 距离衰减。
            spotR *= ogxSpotShape(dot(shadowDirR, aimDir), fov); // 光斑形状。
            spotR *= ogxSpecularGGX(normal, -viewDir, -shadowDirR, materialRoughness, materialF0); // 镜面高光。
            heldHighlight += heldBlockLightValue * spotR; // 累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手。
        {
            vec3 spotPosL = viewPos - vec3(posLX, posLY, 0.0); // 光源位置。
            float spotDistL = length(spotPosL); // 距离。
            vec3 shadowDirL = spotPosL / spotDistL; // 光源到表面方向。
            float spotL = pow(max(spotDistL, 0.6), -falloff); // 距离衰减。
            spotL *= ogxSpotShape(dot(shadowDirL, aimDir), fov); // 光斑形状。
            spotL *= ogxSpecularGGX(normal, -viewDir, -shadowDirL, materialRoughness, materialF0); // 镜面高光。
            heldHighlight += heldBlockLightValue2 * spotL; // 累加。
        }
        if (heldHighlight > 0.001) // 只有明显高光才写回颜色。
        {
            float scale = overworld ? 0.0025 : 0.025; // 下界末地放大十倍。
            color += lightColor * albedo * (heldHighlight * (brightness * scale)); // 叠到颜色上。
        }
    }
    else // 火把模型。
    {
        float heldHighlight = ogxSpecularGGX(normal, -viewDir, -viewDir, materialRoughness, materialF0); // 视线方向的镜面。
        if (heldHighlight > 0.001) // 明显高光才继续。
        {
            dist += 4.0 / (dist + 2.0); // 近处软核。
            heldHighlight *= pow(dist, -falloff); // 距离衰减。
            heldHighlight *= (heldBlockLightValue + heldBlockLightValue2); // 两个光源等级相加。
            float scale = overworld ? 0.0002 : 0.002; // 下界末地放大十倍。
            color += lightColor * albedo * (heldHighlight * (brightness * scale)); // 叠到颜色上。
        }
    }
}

#endif

/*
生成文件：补充后期模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 iterationT 补充模块：对焦、曝光、泛光合并、FXAA、镜头光斑与各向异性采样。
调用位置：需要复现 iterationT 后期与地形取样细节的程序；Minecraft 光影由 `/omni-gfx/itx_extra.glsl` 引入。
可复制示例：
    float focus = ogxGetFocus(colortex2, screenExtent, 0, 8.0, projectionInverse);
    vec3 tone = ogxMergeBloom(color, 1.0 - data.a, ...);
    vec3 sharp = ogxFxaa(color, texCoord, pixelSize, colortex1);
设计原因与取舍：
    参考实现把这些步骤写成程序入口的一部分，直接依赖缓冲编号与宏。库把缓冲、选项与常量
    全部改为参数，函数体仍逐行保留原来的条件分支与常数，调用方按自己的管线填写即可。
    所有纹理由参数传入，模块不读取游戏状态，因此同一份算法可以用于测试世界或别的引擎。
*/
#ifndef OGX_ITX_EXTRA_INCLUDED
#define OGX_ITX_EXTRA_INCLUDED

// 数学与颜色模块提供曲线转换、曝光与相位，大气模块提供平面云的空气透视。






// 对焦距离：参考实现从第二张缓冲左下角取一个对比度统计值，或直接使用手动焦距。
float ogxGetFocus(sampler2D focusTexture, ivec2 screenExtent, int focusMode, float focalPoint, mat4 projectionInverse)
{
    float focus; // 对焦距离，米。
    if (focusMode == 0) // 自动对焦：读取统计像素。
    {
        vec4 stat = texelFetch(focusTexture, ivec2(60, screenExtent.y - 1), 0); // 固定取横向第六十个像素。
        focus = ogxShadowLinearDepth(stat.a * 0.125 + 0.875, projectionInverse); // 编码值还原成米。
    }
    else // 手动对焦。
    {
        focus = focalPoint; // 直接使用调用方给的焦距。
    }
    return focus; // 交回对焦距离。
}

// 镜头光斑的桶形偏移：把二维偏移按到画面中心的距离旋转，得到弯曲的光斑轨迹。
vec2 ogxLensDistOffset(vec2 uv, vec2 pxOffset, float barrel)
{
    vec2 toCenter = uv; // 画面中心到当前点的方向。
    vec3 prep = normalize(vec3(toCenter.y, -toCenter.x, 0.0)); // 旋转轴。
    float angle = length(toCenter) * 2.221 * barrel; // 偏移角随距离增长。
    vec3 oldOffset = vec3(pxOffset, 0.0); // 原始二维偏移抬成三维。
    vec3 rotated = oldOffset * cos(angle) + cross(prep, oldOffset) * sin(angle) + prep * dot(prep, oldOffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 只取二维结果。
}

// 单个彩色光斑：三个颜色通道用略微不同的距离，形成色散边缘。
vec3 ogxLensFlareSpot(vec2 uv, vec2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxLensDistOffset(uv, pos, barrel); // 先做桶形弯曲。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝通道。
    return vec3(r, g, b); // 合成彩色光斑。
}

// 一串小光斑：六层逐渐变小的光斑沿同一条轨迹排开，再补一个大光斑。
vec3 ogxLensOrb(vec2 uv, vec2 pos, float dist, float size, float barrel)
{
    vec3 color = vec3(0.0); // 累加结果。
    const float orbCount = 6.0; // 参考实现的固定层数。
    for (float i = 0.0; i < orbCount; i++) // 逐层累加。
    {
        float j = i + 1.0; // 从第一层开始。
        float offset = j / (j + 0.1); // 沿轨迹的偏移。
        float colorOffset = j / orbCount * 0.5; // 颜色偏移。
        float spotSize = size / (j + 1.0); // 越往后越小。
        color += ogxLensFlareSpot(uv, pos, dist + offset, spotSize * 2.0, spotSize, barrel) * vec3(1.0 - colorOffset, 1.0, 0.5 + colorOffset) * j; // 按层号加权。
    }
    color += ogxLensFlareSpot(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 最外层大光斑。
    return color; // 交回整串光斑。
}

// 环形光斑：用反比曲线给出一圈柔和的色散环。
vec3 ogxLensRing(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur, float barrel)
{
    vec2 uvd = uv * length(uv); // 径向拉长，环才不是正圆。
    pos = ogxLensDistOffset(uv, pos, barrel); // 同样做桶形弯曲。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝通道。
    return vec3(r, g, b); // 合成彩色环。
}

// 镜头光斑与眩光：先按到太阳的屏幕距离算一圈眩光，再叠两层环与多个彩色光斑。
// `lensGlare` 与 `lensFlare` 对应参考实现的两个独立开关，两者可以同时打开。
vec3 ogxLensFlare(vec2 texCoord, vec2 sunCoord, float aspectRatio, float projectionYY, bool lensGlare,
    bool lensFlare, float glareBrightness, float flareBrightness, vec3 colorSunlight, float sunVisibility,
    float vfogDensity, float mainOutputFactor)
{
    vec3 result = vec3(0.0); // 累加结果。
    vec2 coord = texCoord - 0.5; // 以画面中心为原点。
    vec2 sunPos = sunCoord - 0.5; // 太阳的屏幕位置。
    coord.x *= aspectRatio; // 横纵比修正，光斑不会被拉扁。
    sunPos.x *= aspectRatio; // 太阳位置同样修正。
    float fovFactor = max(projectionYY, 2.0); // 视野越大，光斑尺度越大。
    const float barrel = 1.0; // 参考实现的桶形畸变强度。
    if (lensGlare) // 眩光：沿太阳方向的放射状亮纹。
    {
        vec2 v = coord - sunPos; // 到太阳的屏幕向量。
        float dist = length(v); // 距离。
        float glareDist = dist * 13.0 / fovFactor; // 按视野归一化。
        float phase = atan(v.y, v.x) + 0.131; // 方向角加固定相位。
        float glare = 2.0 - clamp(glareDist, 0.0, 1.0) + sin(phase * 12.0) * clamp(glareDist * 2.5 - 0.2, 0.0, 1.0); // 放射条纹。
        glare = glare * glare; // 平方让亮纹更集中。
        glareDist = glareDist * glareDist; // 距离平方。
        glare *= 8e-5 / (glareDist * glareDist); // 反比衰减。
        glare = min(glare, 200.0); // 上限防止爆亮。
        result += vec3(glare * glareBrightness); // 叠到结果。
    }
    if (lensFlare) // 光斑：多层圆斑、环与彩色鬼影。
    {
        float size = 0.5 * fovFactor; // 光斑基准尺寸。
        vec3 flareColor = vec3(0.0); // 光斑累加。
        flareColor += ogxLensOrb(coord, sunPos, 0.0, size * 0.01, barrel) * 0.1; // 主光斑串。
        flareColor += ogxLensRing(coord, sunPos, 1.0, 0.02, 1.4, barrel) * 0.01; // 正向环。
        flareColor += ogxLensRing(coord, sunPos, -1.0, 0.02, 1.4, barrel) * 0.01; // 反向环。
        flareColor += ogxLensFlareSpot(coord, sunPos, -2.00, 0.05, size * 0.05, barrel) * 0.5; // 远端鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.90, 0.02, size * 0.03, barrel) * 0.3; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.70, 0.01, size * 0.06, barrel) * 0.5; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.55, 0.02, size * 0.02, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.35, 0.02, size * 0.04, barrel) * 0.7; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.01, size * 0.15, barrel) * vec3(0.3, 0.4, 0.38); // 彩色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.02, size * 0.08, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.05, 0.01, size * 0.03, barrel) * 0.1; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.30, 0.02, size * 0.20, barrel) * vec3(0.2, 0.18, 0.14); // 暖色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 1.20, 0.03, size * 0.10, barrel) * 0.2; // 远端鬼影。
        result += flareColor * (flareBrightness * 0.3); // 按强度叠到结果。
    }
    result *= colorSunlight * (sunVisibility * clamp(exp2(1.0 - vfogDensity * 20.0), 0.0, 1.0) / mainOutputFactor); // 按阳光与雾衰减。
    return ogxLinearToCurve3(result); // 转回曲线编码。
}

// 自动曝光的 tile 统计：把画面缩到六十四像素一格，逐格算亮度并按距离与夜视加权。
// `aeMode` 与 `luminanceWeightMode` 对应参考实现的对应宏，`caveMode` 与 `dimension` 决定分支。
float ogxGetExposureTiles(sampler2D exposureTexture, int viewWidth, int viewHeight, vec2 screenExtent,
    vec2 pixelSize, float mainOutputFactor, float exposureOutputFactor, int aeMode, int dimension,
    bool aeClamp, bool caveMode, int luminanceWeightMode, float luminanceWeightStrength)
{
    float averageLod = floor(log2(min(viewWidth, viewHeight))); // 按较短边选层级。
    float avg = ogxLuminance(ogxCurveToLinear3(textureLod(exposureTexture, vec2(0.65, 0.65), averageLod).rgb)) * (mainOutputFactor / 128.0); // 整幅画面的平均亮度。
    int lod = 6; // 六十四像素一格的层级。
    float tileScale = exp2(float(lod)); // 一格对应的像素数。
    vec2 tileCount = floor(screenExtent / tileScale); // 横纵格数。
    vec2 tileCenter = tileCount * 0.5; // 画面中心在格坐标里的位置。
    float exposure = 0.0; // 加权曝光累加。
    float weights = 0.0; // 权重累加。
    for (int x = 0; x < int(tileCount.x); x++) // 逐列。
    {
        for (int y = 0; y < int(tileCount.y); y++) // 逐行。
        {
            float tileExposure = ogxLuminance(ogxCurveToLinear3(texelFetch(exposureTexture, ivec2(x, y), lod).rgb)) * (mainOutputFactor / 128.0); // 这一格的亮度。
            vec2 tileDistance = (tileCenter - vec2(x, y) + 0.5) * pixelSize * tileScale * 2.0; // 到中心的归一化距离。
            float centerDistance = length(tileDistance); // 距离。
            float tileWeight = 1.0; // 默认权重。
            if (aeMode == 0 && dimension != 2) tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 主世界与下界按中心加权。
            else if (aeMode == 1) { tileWeight = ogxRemapSaturate(centerDistance, 0.7, 0.0); tileWeight *= tileWeight; } // 中心权重更强。
            else if (aeMode == 2) tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 与零模式相同。
            if (aeMode == 3) tileWeight = 1.0; // 全画面平均。
            if (aeClamp) tileExposure = max(6.4e-9, tileExposure); // 防止零亮度。
            if (caveMode && dimension == 0) // 洞穴模式按与平均亮度的比值加权。
            {
                float lumaWeight = avg / tileExposure; // 亮度比。
                tileWeight *= pow(lumaWeight, 0.7); // 暗处权重更高。
            }
            else if (luminanceWeightMode > 0) // 普通亮度加权。
            {
                float lumaWeight = avg / tileExposure; // 亮度比。
                if (luminanceWeightMode == 1) // 模式一。
                {
                    if (dimension == 1) lumaWeight = pow(lumaWeight, 0.7); // 下界固定指数。
                    else if (dimension == 0) lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.7); // 主世界按平均亮度改指数。
                    else lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地略缓和。
                }
                else if (luminanceWeightMode == 2) // 模式二。
                {
                    if (dimension == 1) lumaWeight = pow(lumaWeight, 0.7); // 下界固定指数。
                    else lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 其他维度。
                }
                else if (luminanceWeightMode == 3) lumaWeight = pow(lumaWeight, luminanceWeightStrength); // 固定指数。
                else if (luminanceWeightMode == 4) lumaWeight = pow(tileExposure / avg, luminanceWeightStrength); // 反向权重。
                tileWeight *= lumaWeight; // 乘到格权重。
            }
            exposure += tileExposure * tileWeight; // 累加曝光。
            weights += tileWeight; // 累加权重。
        }
    }
    exposure /= weights; // 加权平均。
    exposure *= exposureOutputFactor; // 输出缩放。
    return ogxLinearToCurve(exposure); // 转回曲线编码。
}

// 曝光值：手动模式直接由 EV 算出，自动模式从曝光统计像素读取并按曲线、夜视与黑暗调整。
float ogxGetExposureValue(sampler2D exposureTexture, ivec2 screenExtent, bool manualExposure, float evValue,
    float mainOutputFactor, float exposureOutputFactor, float aeCurve, float nightVision, bool aeClamp,
    bool dimensionNether, float aeOffset, float darknessFactor, bool disableBlindness)
{
    if (manualExposure) // 手动曝光。
    {
        return 1.5e5 * mainOutputFactor * exp2(-evValue); // 参考实现的固定比例。
    }
    float ae = ogxCurveToLinear(texelFetch(exposureTexture, ivec2(0, screenExtent.y - 1), 0).a) * (5120.0 / exposureOutputFactor); // 统计像素还原。
    if (!disableBlindness) aeCurve = mix(aeCurve, 0.95, nightVision); // 夜视把曲线推平。
    if (aeClamp) aeCurve *= ogxRemapSaturate(ae, 2.0, 1.0) * 0.6 + 0.4; // 极暗时限制曲线。
    if (dimensionNether) aeCurve *= 0.83; // 下界整体压低。
    ae = pow(ae, -aeCurve); // 曲线调整。
    ae *= exp2(aeOffset); // 曝光偏移。
    if (!disableBlindness) ae *= 1.0 - min(darknessFactor * 2.0, 0.9); // 黑暗效果压暗。
    return 8.5 * mainOutputFactor * ae; // 最终曝光。
}

// 合并泛光：按维度、雨幕、视距与雾的可见度算出泛光量，再把模糊后的泛光混进颜色。
// 参考实现用多个宏选分支，这里用显式布尔参数保留同样的分支与常数。
vec3 ogxMergeBloom(vec3 color, float bloomGuide, vec2 texCoord, sampler2D bloomTexture,
    sampler2D gbuffer0, sampler2D gbuffer7, sampler2D depthTex0, sampler2D dhDepthTex0,
    ivec2 texelCoord, int dimension, float bloomAmount, float rainVisibility, float wetness,
    float eyeBrightnessCurved, bool indoorFog, bool underwaterFog, bool vfog, bool vfogBloom,
    float waterFogDensity, float netherFogDensity, float netherEndBloomBoost, vec4 netherBiomes,
    bool hasDh, float farPlane, mat4 projectionInverse, mat4 dhProjectionInverse, bool disableBlindness,
    float blindness, float darknessFactor, sampler2D fogTexture, vec2 taaJitter)
{
    float linearDepth = 0.0; // 线性深度，米。
    float rainAlpha = 0.0; // 雨幕透明度。
    if (dimension == 0) // 主世界。
    {
        rainAlpha = 1.0 - texelFetch(gbuffer0, texelCoord, 0).a; // 第一张缓冲记录雨幕。
        rainAlpha *= rainVisibility; // 按可见度缩放。
        float depth = texelFetch(depthTex0, texelCoord, 0).x; // 屏幕深度。
        linearDepth = ogxShadowLinearDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxShadowLinearDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
    }
    else if (dimension == 1) // 下界。
    {
        linearDepth = ogxShadowLinearDepth(ogxUnpack2x16(texelFetch(gbuffer7, texelCoord, 0).a).x, projectionInverse); // 第七张缓冲打包线性深度。
        if (!hasDh) linearDepth = min(linearDepth, farPlane); // 没有远景时限制到远平面。
    }
    else // 末地。
    {
        float depth = texelFetch(depthTex0, texelCoord, 0).x; // 屏幕深度。
        linearDepth = ogxShadowLinearDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxShadowLinearDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
    }
    vec3 bloom = ogxCurveToLinear3(textureLod(bloomTexture, texCoord * 0.5, 0.0).rgb); // 半分辨率泛光图。
    float amount = bloomAmount; // 泛光量。
    if (dimension == 2) amount *= 0.5 * netherEndBloomBoost + 1.0; // 末地增强。
    if (dimension == 1) // 下界按群系提高雾与泛光。
    {
        float biomeOffset = netherBiomes.x * 1.0;
        biomeOffset += netherBiomes.y * 0.75; // 绯红森林。
        biomeOffset += netherBiomes.z * 0.25; // 诡异森林。
        biomeOffset += netherBiomes.w * 0.5; // 玄武岩三角洲。
        biomeOffset = biomeOffset * netherEndBloomBoost + 1.0; // 按增强倍率缩放。
        float fogDensity = 0.008 * biomeOffset * netherEndBloomBoost * netherFogDensity; // 群系雾密度。
        if (underwaterFog) fogDensity = 0.7; // 水下固定浓雾。
        float visibility = 1.0 / exp2(linearDepth * fogDensity); // 可见度。
        float fogFactor = 1.1 - visibility; // 雾造成的泛光。
        fogFactor *= bloomGuide; // 按泛光引导缩放。
        amount = max(amount * biomeOffset, min(fogFactor, 0.92)); // 取较大者并封顶。
    }
    else // 主世界与末地。
    {
        float fogDensity = float(underwaterFog) * 0.7; // 水下雾。
        if (underwaterFog) fogDensity = float(waterFogDensity > 0.0) * 0.07 * waterFogDensity; // 参考实现的水下密度。
        float visibility = 1.0 / exp2(linearDepth * fogDensity); // 可见度。
        float fogFactor = 1.1 - visibility; // 雾泛光。
        fogFactor *= bloomGuide; // 按引导缩放。
        amount = max(amount, fogFactor); // 取较大者。
    }
    if (dimension == 0) // 主世界的雨幕与雾泛光。
    {
        float rainBloomAmount = wetness * (indoorFog ? 0.35 : (0.2 * eyeBrightnessCurved + 0.15)); // 雨天泛光。
        rainBloomAmount = clamp(rainBloomAmount + rainAlpha * 0.2, 0.0, 1.0); // 加上雨幕。
        amount = max(amount, rainBloomAmount); // 取较大者。
        if (vfog && !vfogBloom) amount = max(amount, 0.0); // 保留分支位置。
        if (vfog && vfogBloom) // 体积雾的泛光。
        {
            float fogTransmittance = textureLod(fogTexture, texCoord + taaJitter * 0.5, 0.0).a * bloomGuide; // 雾的透过率。
            amount = max(amount, fogTransmittance); // 取较大者。
        }
    }
    if (!disableBlindness) amount *= 1.0 - blindness - darknessFactor; // 黑暗与失明压暗泛光。
    return mix(color, bloom, clamp(amount, 0.0, 1.0)); // 混合泛光。
}

// FXAA：按四邻域亮度梯度找边缘方向，再沿边缘取四个样本做抗锯齿。
vec3 ogxFxaa(vec3 rgbM, vec2 coord, vec2 pixelSize, sampler2D colorTexture)
{
    const float reduceMin = 1.0 / 64.0; // 最小梯度。
    const float reduceMul = 1.0 / 8.0; // 梯度缩放。
    const float spanMax = 16.0; // 最大搜索跨度。
    vec3 rgbNW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, -0.5), 0.0).xyz; // 左上。
    vec3 rgbNE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, -0.5), 0.0).xyz; // 右上。
    vec3 rgbSW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, 0.5), 0.0).xyz; // 左下。
    vec3 rgbSE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, 0.5), 0.0).xyz; // 右下。
    vec3 luma = vec3(0.299, 0.587, 0.114); // 亮度权重。
    float lumaNW = dot(rgbNW, luma); // 左上亮度。
    float lumaNE = dot(rgbNE, luma); // 右上亮度。
    float lumaSW = dot(rgbSW, luma); // 左下亮度。
    float lumaSE = dot(rgbSE, luma); // 右下亮度。
    float lumaM = dot(rgbM, luma); // 中心亮度。
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE))); // 最小亮度。
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE))); // 最大亮度。
    vec2 dir; // 边缘方向。
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * reduceMul), reduceMin); // 方向衰减。
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce); // 方向归一化。
    dir = min(vec2(spanMax, spanMax), max(vec2(-spanMax, -spanMax), dir * rcpDirMin)) * pixelSize; // 限制跨度并换成像素。
    vec3 rgbA = (1.0 / 2.0) * (textureLod(colorTexture, coord + dir * vec2(1.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(2.0 / 3.0 - 0.5), 0.0).xyz); // 内侧两点。
    vec3 rgbB = rgbA * (1.0 / 2.0) + (1.0 / 4.0) * (textureLod(colorTexture, coord + dir * vec2(0.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(3.0 / 3.0 - 0.5), 0.0).xyz); // 外侧两点。
    float lumaB = dot(rgbB, luma); // 外侧亮度。
    if ((lumaB < lumaMin) || (lumaB > lumaMax)) return rgbA; // 外侧落在亮度范围外就用内侧。
    return rgbB; // 否则用更宽的平均。
}

// 远景地形噪点：按楼层量化坐标，再按亮度与材质给一个可正可负的亮度扰动。
vec3 ogxDhNoise(vec3 color, vec3 pos, float materialIDs, int leafId, float steps, float strength)
{
    pos = floor(pos * steps) / steps; // 坐标量化到固定楼层，远景纹素不会闪烁。
    float weight = ogxLuminance(color) * 2.0 - 1.0; // 亮度映射到负一到一。
    weight = 1.0 - weight * weight; // 中间亮度权重最大。
    weight *= float(materialIDs == float(leafId)) + 1.0; // 树叶噪点更强。
    weight *= strength; // 整体强度。
    float noise = fract(sin(dot(pos.xy + fract(sin(pos.z * 91.3458) * 47453.5453), vec2(12.9898, 78.233))) * 43758.5453); // 一维哈希。
    noise = (noise * 2.0 - 1.0) * weight; // 转成负一到一。
    return clamp(color - color * noise, 0.0, 1.0); // 按噪点压暗或提亮。
}

// 末地传送门层：每层一个旋转、缩放与平移，叠出会流动的传送门纹理。
mat4 ogxEndPortalLayer(float layer, float timeSeconds)
{
    mat4 translate = mat4(1.0, 0.0, 0.0, 17.0 / layer,
                                  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (timeSeconds * 0.0005),
                                  0.0, 0.0, 1.0, 0.0,
                                  0.0, 0.0, 0.0, 1.0); // 每层不同的平移。
    float angle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0); // 每层不同的旋转角。
    float s = (4.5 - layer / 4.0) * 2.0; // 与参考实现相同的均匀缩放。
    mat4 scaleRotate = mat4(s * cos(angle), -s * sin(angle), 0.0, 0.0,
                                    s * sin(angle), s * cos(angle), 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 0.0, 0.0, 1.0); // 按列填写的缩放旋转矩阵。
    mat4 uvScaleTranslate = mat4(0.5, 0.0, 0.0, 0.25,
                                         0.0, 0.5, 0.0, 0.25,
                                         0.0, 0.0, 1.0, 0.0,
                                         0.0, 0.0, 0.0, 1.0); // 贴图坐标从零到一压到四分之一到四分之三。
    mat4 scaledTranslate; // 缩放旋转乘平移。
    mat4 result; // 再乘贴图缩放。
    for (int column = 0; column < 4; column++) // 逐列展开矩阵乘法。
    {
        for (int row = 0; row < 4; row++) // 逐行点积。
        {
            scaledTranslate[column][row] = scaleRotate[0][row] * translate[column][0] + scaleRotate[1][row] * translate[column][1]
                + scaleRotate[2][row] * translate[column][2] + scaleRotate[3][row] * translate[column][3]; // 第一段乘积。
            result[column][row] = scaledTranslate[0][row] * uvScaleTranslate[column][0] + scaledTranslate[1][row] * uvScaleTranslate[column][1]
                + scaledTranslate[2][row] * uvScaleTranslate[column][2] + scaledTranslate[3][row] * uvScaleTranslate[column][3]; // 第二段乘积。
        }
    }
    return result; // 参考实现的乘法顺序。
}

// 各向异性采样：按屏幕导数构造椭圆核，沿长轴取多个样本做过滤，避免斜视时贴图糊成一片。
// `quality` 是每像素样本数，`normalSpecular` 为真时同时过滤法线与材质图。
vec4 ogxSampleAnisotropic(sampler2D tex, sampler2D normals, sampler2D specular, vec2 coord, vec2 duv1,
    vec2 duv2, vec2 atlasSize, float textureResolution, int quality, bool normalSpecular, bool useNormalMap,
    bool useSpecularMap, inout vec3 normalTex, inout vec4 specularTex)
{
    vec2 atlasTiles = atlasSize / textureResolution; // 一张贴图在 atlas 里占几格。
    vec2 tilesCoord = coord * atlasTiles; // 换到格坐标。
    mat2 qd = inverse(mat2(dFdx(tilesCoord), dFdy(tilesCoord))); // 屏幕导数矩阵的逆。
    qd = transpose(qd) * qd; // 逆矩阵的转置乘自身，得到椭圆核。
    float d = determinant(qd); // 行列式。
    float t = (qd[0][0] + qd[1][1]) * 0.5; // 迹的一半。
    float D = sqrt(abs(t * t - d)); // 判别式。
    float V = t - D; // 短轴。
    float v = t + D; // 长轴。
    vec2 A = vec2(-qd[0][1], qd[0][0] - V); // 长轴方向。
    A *= inversesqrt(V * dot(A, A) + 1e-20); // 归一化，避免除零。
    float lod = log2(inversesqrt(v) * textureResolution); // 采样层级由长轴决定。
    float steps = float(quality); // 样本数。
    float rSteps = 1.0 / float(quality); // 样本数倒数。
    A *= rSteps; // 每步的偏移。
    vec4 albedoSample = vec4(0.0); // 颜色累加。
    vec3 normalSample = vec3(0.0); // 法线累加。
    vec4 specularSample = vec4(0.0); // 材质累加。
    vec2 tilesBaseCoord = floor(tilesCoord); // 当前格。
    for (float i = 0.5 - steps * 0.5; i < steps * 0.5; i++) // 沿长轴逐样本。
    {
        vec2 sampleCoord = i * A; // 当前偏移。
        sampleCoord = (tilesBaseCoord + fract(tilesCoord + sampleCoord)) / atlasTiles; // 回到贴图坐标并保持在格内。
        vec4 sampleAlbedo = textureLod(tex, sampleCoord, lod); // 取颜色。
        albedoSample += vec4(sampleAlbedo.rgb * sampleAlbedo.a, sampleAlbedo.a); // 预乘透明度累加。
        if (normalSpecular) // 同时过滤法线与材质。
        {
            if (useNormalMap) normalSample += textureLod(normals, sampleCoord, lod).rgb * sampleAlbedo.a; // 法线按透明度加权。
            if (useSpecularMap) specularSample += textureLod(specular, sampleCoord, lod) * sampleAlbedo.a; // 材质按透明度加权。
        }
    }
    float weights = 1.0 / albedoSample.a; // 透明度总和倒数。
    if (normalSpecular) // 写回法线与材质。
    {
        if (useNormalMap) normalTex = ogxDecodeNormalTex(normalSample * weights); // 解出切线法线。
        if (useSpecularMap) specularTex = specularSample * weights; // 材质取加权平均。
    }
    else // 不过滤附加图时用梯度采样保持层级正确。
    {
        if (useNormalMap) normalTex = ogxDecodeNormalTex(textureGrad(normals, coord, duv1, duv2).rgb); // 法线用梯度采样。
        if (useSpecularMap) specularTex = textureGrad(specular, coord, duv1, duv2); // 材质用梯度采样。
    }
    return vec4(albedoSample.rgb * weights, textureLod(tex, coord, 0.0).a); // 颜色取平均，透明度保留原值。
}

// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
vec2 ogxRainAnimationTex(sampler2D texSampler, vec2 coord, float rp);

// 雨滴法线：三张动画噪声图按降水强度叠加，再按屏幕导数做层级衰减。
// `wet` 会被更新成新的湿润度，`strength` 已由调用方乘过雨强与群系系数。
vec2 ogxGetRainNormal(vec3 pos, float strength, inout float wet, sampler2D rainTex1, sampler2D rainTex2,
    sampler2D rainTex3, sampler2D noiseTexture, float timeSeconds, float rpBase)
{
    pos.xyz *= 0.5; // 世界坐标缩小，雨纹更大。
    float frame = fract(floor(timeSeconds * 60.0) / 60.0); // 每秒六十帧的离散时间，避免连续滚动。
    vec2 coord = vec2(pos.x, fract(pos.z / 60.0) - frame); // 沿深度方向滚动的坐标。
    float wet2 = wet * wet; // 湿润度平方。
    float rp = 2.0 - (wet2 * wet2) * 1.2; // 对比度随湿润度降低。
    vec2 n1 = ogxRainAnimationTex(rainTex1, coord, rp); // 第一层雨纹。
    vec2 n2 = ogxRainAnimationTex(rainTex2, coord, rp); // 第二层。
    vec2 n3 = ogxRainAnimationTex(rainTex3, coord, rp); // 第三层。
    pos.x -= timeSeconds * 0.5; // 噪声图随时间横向漂移。
    float downfall = textureLod(noiseTexture, pos.xz * 0.0025, 0.0).w; // 大尺度降水分布。
    downfall = clamp(downfall - 0.25, 0.0, 1.0); // 去掉低值。
    vec2 n = n1; // 第一层总是参与。
    n += n2 * clamp(downfall * 2.0, 0.0, 1.0); // 降水中等时叠第二层。
    n += n3 * clamp(downfall * 2.0 - 1.0, 0.0, 1.0); // 降水很强时叠第三层。
    float lod = dot(fwidth(pos.xz), vec2(1.0)); // 屏幕导数决定过滤强度。
    n /= lod * 5.0 + 1.0; // 远处减弱，避免闪烁。
    n *= strength; // 乘降水强度。
    wet = clamp(mix(downfall, wet, 1.0 - 0.4 * clamp(strength, 0.0, 1.0)), 0.0, 1.0); // 更新湿润度。
    return n; // 交回法线扰动。
}

// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
vec2 ogxRainAnimationTex(sampler2D texSampler, vec2 coord, float rp)
{
    vec2 n = textureLod(texSampler, coord, 0.0).rg; // 取红绿通道。
    n = n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 转成负一到一。
    n = pow(abs(n), vec2(rp)) * sign(n); // 按湿润度拉对比。
    return n; // 交回重整后的雨纹。
}

// 陆地大气散射：沿视线取一段空气，按高度密度与阴影长度算出附加的天空散射。
// `landStrength`、`distanceScale` 与阴影质量由调用方传入，其余大气常数来自模型。
vec3 ogxLandAtmosphericScattering(OgxAtmosphereModel model, vec3 color, float dist, vec3 startPos,
    vec3 endPos, vec3 worldDir, bool isSky, float landStrength, bool vfog, float timeNoon,
    float eyeBrightness, bool indoorFog, vec3 cameraWorldPos, float minAltitude, bool atmoHorizon,
    bool landscapeShadow, int shadowQuality, vec3 worldSunVector, float bayerNoise,
    mat4 shadowView, mat4 shadowProjection, sampler2D shadowTexture, float distanceScale,
    float wetness, bool overworld)
{
    float strength = max(landStrength - float(isSky), 0.0); // 天空像素不额外加陆地散射。
    if (vfog) strength *= timeNoon; // 体积雾开启时只在白天加。
    if (!indoorFog) strength *= eyeBrightness; // 室内按眼睛亮度淡出。
    if (strength > 0.001 && overworld) // 只有主世界且强度足够时才计算。
    {
        float altitude = atmoHorizon ? max(cameraWorldPos.y, minAltitude) * 0.001 + model.bottom_radius
                                     : max(cameraWorldPos.y, 63.0) * 0.001 + model.bottom_radius; // 相机在大气里的半径。
        vec3 camera = vec3(0.0, altitude, 0.0); // 参考实现把相机放在竖直轴上。
        float shadowDist = dist; // 阴影长度初值。
        if (landscapeShadow) // 开启阴影时沿阴影图采样。
        {
            float rSteps = 1.0 / float(shadowQuality); // 采样数倒数。
            vec3 shadowStart = ogxShadowScreenPos(startPos, shadowView, shadowProjection); // 起点投到阴影图。
            vec3 shadowEnd = ogxShadowScreenPos(endPos, shadowView, shadowProjection); // 终点投到阴影图。
            float noise = bayerNoise; // 抖动。
            vec3 shadowIncrement = (shadowEnd - shadowStart) * rSteps; // 每步增量。
            vec3 shadowRayPosition = shadowIncrement * noise + shadowStart; // 起点加抖动。
            float shadowLength = 0.0; // 被遮挡的样本数。
            for (int i = 0; i < shadowQuality; i++) // 沿阴影图采样。
            {
                vec3 shadowPos = shadowRayPosition; // 当前采样。
                shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, 0.9); // 补边缘压缩。
                if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 落在图内。
                {
                    float solidDepth = textureLod(shadowTexture, shadowPos.xy, 0.0).x; // 读遮挡深度。
                    shadowLength += step(solidDepth, shadowPos.z); // 遮挡计数。
                }
                shadowRayPosition += shadowIncrement; // 前进。
            }
            shadowDist = max(shadowDist - shadowLength * length((endPos - startPos) * rSteps), 0.0); // 按遮挡比例缩短。
        }
        dist *= distanceScale; // 距离缩放。
        shadowDist *= distanceScale; // 阴影距离同样缩放。
        vec3 scattering = ogxAtmoSimpleScattering(model, camera, worldDir, dist, shadowDist, worldSunVector); // 大气单次散射。
        color += scattering * (1.0 - wetness) * strength; // 雨天压低陆地散射。
    }
    return color; // 交回叠加后的颜色。
}

#endif

/*
生成文件：平面云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库平面云模块：在固定高度的一层云上取样、朝太阳求遮挡并合成空气透视。
调用位置：需要 iterationT 风格平面云的程序；Minecraft 光影由 `/omni-gfx/planar.glsl` 引入。
可复制示例：
    ogxPlanarClouds(color, worldDir, camera, dither, transmittance, ...);
设计原因与取舍：
    参考实现把噪声、风、云量与大气常数都写成全局宏。库把每一类输入显式传入，
    函数体仍保留原来的球面求交、四次光照步进与两次相函数，不改变画面手感。
    大气透视复用查表模型，避免在云模块里复制一套散射公式。
*/
#ifndef OGX_PLANAR_INCLUDED
#define OGX_PLANAR_INCLUDED

// 云模块提供平面密度，数学提供球面求交与相函数，大气模块提供空气透视。



// 平面云合成：沿视线与云层求交，取密度与朝阳光照，再把云和空气透视叠到背景。
// `cloudTransmittance` 进来时是上一层的剩余透过率，返回时已乘上这一层。
void ogxPlanarClouds(inout vec3 color, vec3 worldDir, vec3 camera, float dither,
    inout float cloudTransmittance, OgxAtmosphereModel model, sampler3D lut, vec3 cameraWorldPos,
    float timeSeconds, float cloudSpeed, float ftcOffset, vec3 worldShadowVector,
    vec3 colorShadowlight, vec3 colorSkylight, float wetness, float cloudAltitude, float cloudNoiseScale,
    float cloudCoverage, sampler2D noiseTexture, vec3 worldSunVector, vec3 rayleighTint,
    vec3 mieTint, float nightBrightness, float skyBrightness, bool volumetricClouds)
{
    float planetRadius = model.bottom_radius * 1e3; // 模型半径从公里换成米。
    vec3 rayStartPos = vec3(0.0, planetRadius + cameraWorldPos.y, 0.0); // 相机在行星正上方。
    vec2 hit = ogxRaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude); // 与云层求交。
    float intersection = hit.y; // 取远交点。
    if (intersection > 0.0) // 视线确实穿过云层才继续。
    {
        float wind = 2.5 * (timeSeconds * cloudSpeed + 10.0 * ftcOffset); // 风随时间推进。
        vec2 windDirection = vec2(-wind, wind * 0.2); // 风向略微斜向。
        float VdotL = dot(worldDir, worldShadowVector) * 0.5 + 0.5; // 视线与光的夹角映射到零到一。
        vec3 centerPosition = worldDir * intersection; // 云层交点。
        vec2 samplePosition = centerPosition.xz + cameraWorldPos.xz; // 交点换到世界水平坐标。
        cloudTransmittance = min(ogxPlanarDensity(samplePosition, windDirection, noiseTexture,
            cloudNoiseScale, cloudCoverage) * cloudTransmittance * 40.0, 0.9); // 这一层的遮挡。
        if (volumetricClouds) cloudTransmittance *= 1.0 - wetness; // 体积雾开启时雨天更薄。
        if (cloudTransmittance > 1e-5) // 有遮挡才做光照与合成。
        {
            float stepLength = mix(150.0, 0.0, worldShadowVector.z); // 朝太阳的步长，太阳越低步长越小。
            samplePosition += stepLength * dither * worldShadowVector.xy; // 起点按抖动错开。
            float lightingDepth = 0.0; // 朝太阳的遮挡量。
            for (int i = 0; i < 4; i++) // 四次光照步进。
            {
                lightingDepth += ogxPlanarLightingDensity(samplePosition, windDirection, noiseTexture,
                    cloudNoiseScale, cloudCoverage) * stepLength; // 累加这一步的密度。
                samplePosition += worldShadowVector.xy * stepLength; // 前进。
                stepLength *= 1.5; // 步长逐次放大。
            }
            float sunlightEnergy = 1.0 / (lightingDepth + 1.0); // 遮挡越少阳光越强。
            float powderFactor = exp2(-cloudTransmittance * (worldShadowVector.y * 5.0 + 0.5)); // 粉末效应。
            sunlightEnergy *= ogxMiePhase(powderFactor * 0.8, VdotL * 0.5 + 0.5); // 第一次相函数。
            sunlightEnergy *= ogxMiePhase(0.9, VdotL) * 0.4 + 1.0; // 第二次相函数补前向散射。
            vec3 cloudColor = colorShadowlight * (sunlightEnergy * 6.0); // 云被太阳照亮的颜色。
            float skylightEnergy = exp2(-cloudTransmittance * 0.15); // 天空光穿过的比例。
            cloudColor += colorSkylight * (skylightEnergy * 0.2); // 加天空环境光。
            cloudTransmittance *= exp2(-(length(centerPosition) + 2e3) * 4e-5); // 远处云逐渐融进空气。
            vec3 atmoPoint = camera + centerPosition * 0.001; // 交点从米换成公里。
            vec3 transmittance; // 相机到交点的透过率。
            vec3 aerialPerspective = ogxAtmoSkyRadianceToPoint(model, lut, camera, atmoPoint, worldSunVector,
                -worldSunVector, false, rayleighTint, mieTint, nightBrightness, 0.0, skyBrightness, transmittance); // 空气透视。
            color *= (1.0 - cloudTransmittance); // 背景先按云的遮挡压暗。
            color += (cloudColor * transmittance + aerialPerspective) * cloudTransmittance; // 再叠云与空气透视。
        }
    }
}

#endif

/*
生成文件：相机变换模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库相机变换模块：屏幕、视空间、世界空间、阴影空间与远景投影的显式换算。
调用位置：任何需要把深度图还原成位置、把世界点投到阴影图的程序；Minecraft 光影由 `/omni-gfx/camera.glsl` 引入。
可复制示例：
    vec3 viewPos = ogxViewPosFromScreenPos(coord, depth, jitter, 0.5, projectionInverse, true);
    vec3 shadowPos = ogxShadowScreenPosDistorted(worldPos, shadowView, shadowProjection, 0.9);
    vec3 clip = ogxProjectAndDivide(projection, viewPos);
设计原因与取舍：
    参考实现直接读 gbufferProjection 等全局变量。库把每个矩阵、抖动与是否处理抖动的开关都显式传入，
    调用方必须自己给出数据来源；这样同一套公式能用于主世界、远景与测试场景，也方便审查矩阵布局。
    所有函数只做坐标换算，不读取缓冲、不改写选项，因此不是宿主胶水。
*/
#ifndef OGX_CAMERA_INCLUDED
#define OGX_CAMERA_INCLUDED

// 数学模块提供夹紧与向量单位化。

// 屏幕坐标与深度还原视空间位置；`jitter` 为 TAA 抖动，`useJitter` 决定是否先减去半个像素。
vec3 ogxViewPosFromScreenPos(vec2 coord, float depth, vec2 jitter, float jitterScale, mat4 projectionInverse, bool useJitter)
{
    if (useJitter) coord -= jitter * jitterScale; // 参考实现只减半个抖动像素。
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec3 pos = vec3(vec2(projectionInverse[0][0], projectionInverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projectionInverse); // 逆投影对角项与平移列。
    return pos / (projectionInverse[2][3] * ndc.z + projectionInverse[3][3]); // 透视除法。
}

// 不做抖动修正的版本：追踪射线、历史重建等已经自行处理抖动的场合使用。
vec3 ogxViewPosFromScreenPosRaw(vec2 coord, float depth, mat4 projectionInverse)
{
    return ogxViewPosFromScreenPos(coord, depth, vec2(0.0), 0.0, projectionInverse, false); // 与上一函数共用同一算式。
}

// 视空间位置投到屏幕；`useJitter` 为真时把抖动加回横纵坐标。
vec3 ogxScreenPosFromViewPos(vec3 viewPos, vec2 jitter, float jitterScale, mat4 projection, bool useJitter)
{
    vec3 screenPos = vec3(projection[0][0], projection[1][1], projection[2][2]) * viewPos + ogxMatrixTranslation(projection); // 投影对角项与平移列。
    screenPos = screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
    if (useJitter) screenPos.xy += jitter * jitterScale; // 补回抖动。
    return screenPos;
}

// 不补抖动的投影：屏幕空间追踪的起点与终点都用这个版本，抖动只影响采样相位。
vec3 ogxScreenPosFromViewPosRaw(vec3 viewPos, mat4 projection)
{
    return ogxScreenPosFromViewPos(viewPos, vec2(0.0), 0.0, projection, false); // 共用同一算式。
}

// 屏幕深度换米制距离：只用到逆投影的深度列。
float ogxLinearDepthFromScreenDepth(float depth, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影深度部分。
}

// 米制距离换屏幕深度的函数在后期模块已有同式实现，这里不重复定义，避免同一编译单元重名。

// 远景屏幕坐标与深度还原远景视空间位置：用完整矩阵乘，远景投影不一定只有对角项。
vec3 ogxViewPosFromScreenPosDh(vec2 coord, float depth, vec2 jitter, float jitterScale, mat4 dhProjectionInverse, bool useJitter)
{
    if (useJitter) coord -= jitter * jitterScale; // 与近景相同的抖动修正。
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec4 clip = vec4(ndc, 1.0); // 齐次坐标。
    vec4 view = vec4(dhProjectionInverse[0][0] * clip.x + dhProjectionInverse[1][0] * clip.y + dhProjectionInverse[2][0] * clip.z + dhProjectionInverse[3][0] * clip.w,
                         dhProjectionInverse[0][1] * clip.x + dhProjectionInverse[1][1] * clip.y + dhProjectionInverse[2][1] * clip.z + dhProjectionInverse[3][1] * clip.w,
                         dhProjectionInverse[0][2] * clip.x + dhProjectionInverse[1][2] * clip.y + dhProjectionInverse[2][2] * clip.z + dhProjectionInverse[3][2] * clip.w,
                         dhProjectionInverse[0][3] * clip.x + dhProjectionInverse[1][3] * clip.y + dhProjectionInverse[2][3] * clip.z + dhProjectionInverse[3][3] * clip.w); // 完整矩阵乘。
    return view.xyz / view.w; // 透视除法。
}

// 不做抖动修正的远景逆投影。
vec3 ogxViewPosFromScreenPosRawDh(vec2 coord, float depth, mat4 dhProjectionInverse)
{
    return ogxViewPosFromScreenPosDh(coord, depth, vec2(0.0), 0.0, dhProjectionInverse, false); // 共用同一算式。
}

// 远景视空间位置投到屏幕，可选补抖动。
vec3 ogxScreenPosFromViewPosDh(vec3 viewPos, vec2 jitter, float jitterScale, mat4 dhProjection, bool useJitter)
{
    vec3 screenPos = vec3(dhProjection[0][0], dhProjection[1][1], dhProjection[2][2]) * viewPos + ogxMatrixTranslation(dhProjection); // 远景投影对角项与平移列。
    screenPos = screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法。
    if (useJitter) screenPos.xy += jitter * jitterScale; // 补回抖动。
    return screenPos;
}

// 不补抖动的远景投影。
vec3 ogxScreenPosFromViewPosRawDh(vec3 viewPos, mat4 dhProjection)
{
    return ogxScreenPosFromViewPosDh(viewPos, vec2(0.0), 0.0, dhProjection, false); // 共用同一算式。
}

// 远景屏幕深度换米制距离。
float ogxLinearDepthFromScreenDepthDh(float depth, mat4 dhProjectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景逆投影深度部分。
}

// 米制距离换远景屏幕深度。
float ogxScreenDepthFromLinearDepthDh(float depth, mat4 dhProjectionInverse)
{
    depth = (1.0 / depth - dhProjectionInverse[3][3]) / dhProjectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景屏幕深度换成同一距离在近景投影下的屏幕深度：先换米，再用近景投影换回。
float ogxScreenDepthFromDhScreenDepth(float depth, mat4 dhProjectionInverse, mat4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 远景零到一转负一到一。
    depth = 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 换成米。
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 近景深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 阴影相机空间位置：视图变换后按正交投影缩放，深度折半。
vec3 ogxShadowViewPosExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    vec3 shadowPos = ogxMatrixMulPoint(shadowView, worldPos) + ogxMatrixTranslation(shadowView); // 世界位置转阴影相机空间。
    float scale = shadowProjection[0][0]; // 正交投影的水平缩放。
    return shadowPos * vec3(scale, scale, -scale * 0.5); // 按投影缩放，深度折半。
}

// 世界位置投到阴影图，不做边缘压缩。
vec3 ogxShadowScreenPosExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection)
{
    return ogxShadowViewPosExplicit(worldPos, shadowView, shadowProjection) * 0.5 + 0.5; // 负一到一转零到一。
}

// 世界位置投到阴影图并做边缘压缩，`bias` 是压缩强度。
vec3 ogxShadowScreenPosDistortedExplicit(vec3 worldPos, mat4 shadowView, mat4 shadowProjection, float bias)
{
    vec3 shadowPos = ogxShadowViewPosExplicit(worldPos, shadowView, shadowProjection); // 先转到阴影相机空间。
    float dist = length(shadowPos.xy); // 到阴影图中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数。
    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩。
    return shadowPos * 0.5 + 0.5; // 转成零到一。
}

// 读取端补一次边缘压缩，与写入端使用同一个 `bias`。
vec2 ogxDistortShadowPosExplicit(vec2 shadowPos, float bias)
{
    shadowPos = shadowPos * 2.0 - 1.0; // 零到一转负一到一。
    float dist = length(shadowPos.xy); // 到中心距离。
    float distortFactor = (1.0 - bias) + dist * bias; // 同一压缩系数。
    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
    return shadowPos * 0.5 + 0.5; // 再转回零到一。
}

// 通用投影：取矩阵的对角项与最后两列，与参考实现的 `projMAD` 逐项一致。
vec4 ogxProject(mat4 m, vec3 pos)
{
    return vec4(m[0][0], m[1][1], m[2][2], m[2][3]) * pos.xyzz + m[3]; // 对角项乘坐标再加平移列。
}

// 投影并做齐次除法。
vec3 ogxProjectAndDivide(mat4 m, vec3 pos)
{
    vec4 homogenous = ogxProject(m, pos); // 先投影。
    return homogenous.xyz / homogenous.w; // 再除以齐次分量。
}

// 屏幕坐标转视空间：先转负一到一，再用逆投影。
vec3 ogxScreenToViewSpace(vec3 screenPos, mat4 projectionInverse)
{
    vec3 ndcPos = 2.0 * screenPos - 1.0; // 零到一转负一到一。
    return ogxProjectAndDivide(projectionInverse, ndcPos); // 逆投影。
}

// 视空间转屏幕：投影后除以齐次分量，再转零到一。
vec3 ogxViewToScreenSpace(vec3 viewPos, mat4 projection)
{
    vec3 ndcPos = ogxProjectAndDivide(projection, viewPos); // 投影并除齐次。
    return ndcPos * 0.5 + 0.5; // 转零到一。
}

// 视空间位置投到裁剪空间，深度不折半：Eclipse 的 `toClipSpace3`。
vec3 ogxToClipSpace3(vec3 viewSpacePosition, mat4 projection)
{
    return ogxProjectAndDivide(projection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5; // 参考实现的透视缩放。
}

// 屏幕坐标转视空间：Eclipse 的 `toScreenSpace`，与 PhotonGTAO 的版本只在命名上不同。
vec3 ogxToScreenSpace(vec3 p, mat4 projectionInverse)
{
    vec4 inverseDiag = vec4(projectionInverse[0][0], projectionInverse[1][1], projectionInverse[2][2], projectionInverse[2][3]); // 逆投影的对角项。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + projectionInverse[3]; // 对角项乘坐标再加平移。
    return fragPosition.xyz / fragPosition.w; // 齐次除法。
}

// 屏幕坐标转视空间方向，只保留方向不保留长度。
vec3 ogxToScreenSpaceVector(vec3 p, mat4 projectionInverse)
{
    vec4 inverseDiag = vec4(projectionInverse[0][0], projectionInverse[1][1], projectionInverse[2][2], projectionInverse[2][3]); // 逆投影对角项。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + projectionInverse[3]; // 逆投影。
    return normalize(fragPosition.xyz); // 只取方向。
}

// 视空间位置转相机相对世界位置。
vec3 ogxToWorldSpace(vec3 p3, mat4 modelViewInverse)
{
    return ogxMatrixMulPoint(modelViewInverse, p3) + ogxMatrixTranslation(modelViewInverse); // 视空间转世界。
}

// 视空间位置转绝对世界位置：再加相机世界坐标。
vec3 ogxToWorldSpaceCamera(vec3 p3, mat4 modelViewInverse, vec3 cameraWorldPos)
{
    return ogxToWorldSpace(p3, modelViewInverse) + cameraWorldPos; // 相机相对世界加相机位置。
}

// 视空间位置转阴影空间。
vec3 ogxToShadowSpace(vec3 p3, mat4 modelViewInverse, mat4 shadowView)
{
    p3 = ogxToWorldSpace(p3, modelViewInverse); // 先转世界。
    return ogxMatrixMulPoint(shadowView, p3) + ogxMatrixTranslation(shadowView); // 再转阴影相机。
}

// 视空间位置转阴影空间并乘投影：深度方向按参考实现只取对角项。
vec3 ogxToShadowSpaceProjected(vec3 p3, mat4 modelViewInverse, mat4 shadowView, mat4 shadowProjection)
{
    p3 = ogxToWorldSpace(p3, modelViewInverse); // 先转世界。
    p3 = ogxMatrixMulPoint(shadowView, p3) + ogxMatrixTranslation(shadowView); // 再转阴影相机。
    return vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * p3 + ogxMatrixTranslation(shadowProjection); // 乘投影对角项并加平移。
}

// 远景屏幕坐标还原视空间：近景深度与远景深度分两条路。
vec3 ogxToScreenSpaceDh(vec2 texcoord, float depth, float dhDepth, mat4 projectionInverse, mat4 dhProjectionInverse)
{
    if (depth < 1.0) // 近景像素用近景逆投影。
    {
        return ogxToScreenSpace(vec3(texcoord, depth), projectionInverse); // 与近景同一算式。
    }
    return ogxToScreenSpace(vec3(texcoord, dhDepth), dhProjectionInverse); // 远景像素用远景逆投影。
}

// 视空间位置投到裁剪空间，可按 `depthCheck` 选择远景矩阵。
vec3 ogxToClipSpace3Dh(vec3 viewSpacePosition, bool depthCheck, mat4 projection, mat4 dhProjection)
{
    mat4 projectionMatrix = depthCheck ? dhProjection : projection; // 按开关选矩阵。
    return ogxProjectAndDivide(projectionMatrix, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5; // 与近景同一算式。
}

// 远景阴影投影微调：把投影的远平面改成两倍远景距离，其余项保留。
mat4 ogxDhShadowProjectionTweak(mat4 projection, float farPlane, float dhFarPlane, bool enabled)
{
    if (!enabled) return projection; // 开关关闭时原样返回。
    float tweakFar = 3.0 * farPlane; // 近景默认远平面。
    tweakFar = 2.0 * dhFarPlane; // 远景按两倍距离。
    mat4 result = projection; // 复制一份再改。
    result[2][2] = -2.0 / tweakFar; // 只改深度缩放。
    result[3][2] = 0.0; // 清掉深度平移。
    return result; // 交回微调后的投影。
}

// 光传播体积坐标：世界位置减去体积原点，再落到体素格。
vec3 ogxGetLpvPosition(vec3 worldPos, vec3 lpvOrigin, float voxelSize)
{
    return (worldPos - lpvOrigin) / voxelSize; // 换到体积格坐标。
}

// 深度约定交换：参考实现只把屏幕深度转成线性距离，不做数值变换。
float ogxSwapperlinZ2(float depth, float nearPlane, float farPlane)
{
    return (2.0 * nearPlane) / (farPlane + nearPlane - depth * (farPlane - nearPlane)); // 参考实现的分式。
}

// 快速深度线性化：Eclipse 的屏幕深度转米制距离。
float ogxInvertLinearizeDepthFast(float z, float nearPlane, float farPlane)
{
    return (farPlane * (z - nearPlane)) / (z * (farPlane - nearPlane)); // 参考实现的分式。
}

// 屏幕坐标转视空间：Eclipse 的 `toScreenSpace2`，可按 `depthCheck` 选择远景逆投影。
vec3 ogxToScreenSpace2(vec3 p, bool depthCheck, mat4 projectionInverse, mat4 dhProjectionInverse)
{
    mat4 matrix = depthCheck ? dhProjectionInverse : projectionInverse; // 按开关选矩阵。
    vec4 inverseDiag = vec4(matrix[0][0], matrix[1][1], matrix[2][2], matrix[2][3]); // 逆投影的对角项与深度平移。
    vec3 p3 = p * 2.0 - 1.0; // 零到一转负一到一。
    vec4 fragPosition = inverseDiag * p3.xyzz + matrix[3]; // 对角项乘坐标再加平移。
    return fragPosition.xyz / fragPosition.w; // 齐次除法。
}

// 光传播体积坐标：玩家相对位置加相机小数偏移，再平移到体积中心。
vec3 ogxGetLpvPositionExplicit(vec3 playerPos, vec3 cameraOffset, float lpvSize)
{
    return playerPos + cameraOffset + vec3(lpvSize * 0.5); // 与参考实现的 `LpvSize3/2u` 相同。
}

#endif

/*
生成文件：时间取样模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 iterationT 时间抗锯齿取样模块：三乘三最近深度、远景深度与相机速度。
调用位置：需要复现 iterationT TAA 输入的程序；Minecraft 光影由 `/omni-gfx/itx_taa.glsl` 引入。
可复制示例：
    float depth = ogxItxSampleCurrDepthClosest3x3(depthTexture, texel);
    vec3 velocity = ogxItxCalculateCameraVelocity(depth0, depth1, texel, coord, ids, ...);
设计原因与取舍：
    参考实现用全局深度图与矩阵。库把纹理、像素坐标、材质编号与全部矩阵显式传入，
    这样三乘三取样与远近景切换可以单独测试，也不会把坐标约定藏在引擎里。
    采样顺序与参考实现一致：先按材质决定深度来源，再决定近景或远景重投影。
*/
#ifndef OGX_ITX_TAA_INCLUDED
#define OGX_ITX_TAA_INCLUDED

// 相机变换模块提供深度约定与投影，数学模块提供矩阵列展开。


// 读一个当前帧深度纹素。
float ogxItxSampleDepthFetch(sampler2D depthTexture, ivec2 coord)
{
    return texelFetch(depthTexture, coord, 0).x; // 精确读取，不插值。
}

// 当前帧三乘三最近深度：九个样本取最小值，用来避开前景薄片。
float ogxItxSampleCurrDepthClosest3x3(sampler2D depthTexture, ivec2 coord)
{
    float depth0 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxItxSampleDepthFetch(depthTexture, coord + ivec2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 读一个远景深度纹素。
float ogxItxSampleDhDepthFetch(sampler2D dhDepthTexture, ivec2 coord)
{
    return texelFetch(dhDepthTexture, coord, 0).x; // 远景深度图精确读取。
}

// 远景三乘三最近深度：与近景同样取九个样本的最小值。
float ogxItxSampleCurrDepthDhClosest3x3(sampler2D dhDepthTexture, ivec2 coord)
{
    float depth0 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(-1, -1)); // 左上。
    float depth1 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(0, -1)); // 上方。
    float depth2 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(1, -1)); // 右上。
    float depth3 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(-1, 0)); // 左侧。
    float depth4 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(0, 0)); // 中心。
    float depth5 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(1, 0)); // 右侧。
    float depth6 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(-1, 1)); // 左下。
    float depth7 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(0, 1)); // 下方。
    float depth8 = ogxItxSampleDhDepthFetch(dhDepthTexture, coord + ivec2(1, 1)); // 右下。
    return min(depth0, min(depth1, min(depth2, min(depth3, min(depth4, min(depth5, min(depth6, min(depth7, depth8)))))))); // 九点最小值。
}

// 相机速度：按材质与深度选择近景或远景重投影，返回当前像素相对上一帧的屏幕位移。
// `stainedGlassId`、`iceId`、`endPortalId` 是宿主材质编号，算法只做比较，不假设编号大小。
vec3 ogxItxCalculateCameraVelocity(sampler2D depthTexture0, sampler2D depthTexture1, sampler2D dhDepthTexture0,
    ivec2 texelCoord, vec2 texCoord, float materialIDs, bool closestDepth, float stainedGlassId, float iceId,
    float endPortalId, mat4 projectionInverse, mat4 dhProjectionInverse, mat4 modelView,
    mat4 modelViewInverse, mat4 previousModelView, mat4 previousProjection, vec3 cameraWorldPos,
    vec3 previousCameraPosition, float handDepth, out float depth)
{
    if (materialIDs == stainedGlassId || materialIDs == iceId) // 透明材质用完整深度，避免最近深度穿到后面。
    {
        depth = texelFetch(depthTexture1, texelCoord, 0).x; // 精确读取完整深度。
    }
    else if (closestDepth) // 开启最近深度时取三乘三最小值。
    {
        depth = ogxItxSampleCurrDepthClosest3x3(depthTexture0, texelCoord); // 近景最近深度。
    }
    else // 默认只取中心。
    {
        depth = ogxItxSampleDepthFetch(depthTexture0, texelCoord); // 中心深度。
    }
    vec3 velocity = vec3(0.0); // 默认没有位移。
    if (materialIDs != endPortalId) // 末地传送门不做重投影。
    {
        vec3 screenPos = vec3(texCoord, depth); // 当前屏幕坐标。
        vec3 projection = vec3(0.0); // 上一帧屏幕坐标。
        if (screenPos.z == 1.0) // 天空像素改用远景深度。
        {
            if (closestDepth) screenPos.z = ogxItxSampleCurrDepthDhClosest3x3(dhDepthTexture0, texelCoord); // 远景最近深度。
            else screenPos.z = ogxItxSampleDhDepthFetch(dhDepthTexture0, texelCoord); // 远景中心深度。
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(dhProjectionInverse, projection); // 远景逆投影到视空间。
            projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
            if (screenPos.z < 1.0) projection += cameraWorldPos - previousCameraPosition; // 有远景几何时加相机位移。
            projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
            screenPos.z = ogxScreenDepthFromDhScreenDepth(screenPos.z, dhProjectionInverse, projectionInverse); // 远景深度换成近景尺度。
            previousScreen.z = ogxScreenDepthFromDhScreenDepth(previousScreen.z, dhProjectionInverse, projectionInverse); // 上一帧深度同样换算。
            projection = previousScreen; // 交回上一帧屏幕坐标。
            depth = ogxSaturate(screenPos.z); // 输出近景尺度深度。
        }
        else // 近景像素。
        {
            projection = screenPos * 2.0 - 1.0; // 转负一到一。
            projection = ogxProjectAndDivide(projectionInverse, projection); // 逆投影到视空间。
            if (depth < 0.7) // 手部只加模型视图的位移。
            {
                projection += (ogxMatrixTranslation(previousModelView) - ogxMatrixTranslation(modelView)) * handDepth; // 参考实现的手部补偿。
            }
            else // 世界几何完整重投影。
            {
                projection = ogxMatrixMulPoint(modelViewInverse, projection) + ogxMatrixTranslation(modelViewInverse); // 转世界。
                projection += cameraWorldPos - previousCameraPosition; // 加相机位移。
                projection = ogxMatrixMulPoint(previousModelView, projection) + ogxMatrixTranslation(previousModelView); // 转上一帧视空间。
            }
            vec3 previousScreen = vec3(previousProjection[0][0], previousProjection[1][1], previousProjection[2][2]) * projection + ogxMatrixTranslation(previousProjection); // 上一帧投影。
            projection = previousScreen / -projection.z * 0.5 + 0.5; // 用投影前的深度做透视除法。
        }
        velocity = screenPos - projection; // 当前减上一帧得到屏幕位移。
    }
    return velocity; // 交回速度。
}

#endif

/*
生成文件：Eclipse 体积云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要 Eclipse 风格层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud_eclipse.glsl` 引入。
可复制示例：
    OgxEclipseCloudSettings s = ...; // 填云层高度、比例、覆盖与天气。
    vec4 cloud = ogxEclipseGetVolumetricClouds(viewPos, dither, sunVector, moonVector, ...);
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
*/
#ifndef OGX_CLOUD_ECLIPSE_INCLUDED
#define OGX_CLOUD_ECLIPSE_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数。


// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxEclipseCloudLayer
{
    float height; // 云底高度，米。
    float tallness; // 云层厚度，米。
    float scale; // 世界坐标到云坐标的比例。
    float distance; // 这一层的可见距离，米。
    float coverage; // 云量，零到一。
    float rainDensity; // 雨天密度。
    float detail; // 高频侵蚀尺度。
};

// 体积云的全部环境输入：层数据、天气、太阳与闪电。
struct OgxEclipseCloudSettings
{
    OgxEclipseCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
    float cloudMovement; // 云的水平位移，米。
    float rainAmount; // 降雨强度。
    float thunderStrength; // 雷暴强度。
    float sunElevation; // 太阳高度角正弦。
    float moonElevation; // 月亮高度角正弦。
    float cumulonimbusStrength; // 积雨云强度。
    float distanceFogScale; // 距离雾的指数系数，通常为负。
    float skyBrightness; // 天空亮度。
    float lightningFlash; // 当前闪电亮度。
    float lightningFade; // 闪电衰减。
    float cumulonimbusLightningBrightness; // 积雨云闪电亮度。
    float auroraAmount; // 极光强度，零表示没有极光。
    vec3 auroraLighting; // 极光颜色，调用方按自己的极光模型算好。
    vec4 lightningBoltPosition; // 普通闪电位置，第四个分量是强度。
    vec3 cumulonimbusLightningColor; // 积雨云闪电颜色。
    int cumulonimbus; // 是否启用积雨云，零关闭。
    int lightningEnabled; // 是否启用积雨云闪电。
};

// 二维哈希：把格坐标打散成两个零到一的随机数。
vec2 ogxEclipseHash2(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973)); // 三个不同频率的搅动。
    p3 += dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33); // 互相混合。
    return fract((vec2(p3.x, p3.x) + vec2(p3.y, p3.z)) * vec2(p3.z, p3.y)); // 取两个独立分量。
}

// 归一化哈希向量：把格坐标变成一个单位方向，供 Perlin 梯度使用。
vec2 ogxEclipseNormalizeHash(vec2 p)
{
    return normalize(ogxEclipseHash2(p) - 0.5); // 中心化后单位化。
}

// Perlin 梯度：返回解析梯度，供旋度噪声直接使用。
vec2 ogxEclipsePerlinGradient(vec2 coord)
{
    vec2 i = floor(coord); // 整数格。
    vec2 f = fract(coord); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 参考实现的导数，虽然不是严格数学导数但画面更自然。
    vec2 g0 = ogxEclipseNormalizeHash(i); // 左下梯度。
    vec2 g1 = ogxEclipseNormalizeHash(i + vec2(1.0, 0.0)); // 右下梯度。
    vec2 g2 = ogxEclipseNormalizeHash(i + vec2(0.0, 1.0)); // 左上梯度。
    vec2 g3 = ogxEclipseNormalizeHash(i + vec2(1.0, 1.0)); // 右上梯度。
    float v0 = dot(g0, f); // 左下贡献。
    float v1 = dot(g1, f - vec2(1.0, 0.0)); // 右下贡献。
    float v2 = dot(g2, f - vec2(0.0, 1.0)); // 左上贡献。
    float v3 = dot(g3, f - vec2(1.0, 1.0)); // 右上贡献。
    vec2 omu = 1.0 - u; // 反向平滑权重。
    return vec2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的梯度。
}

// 二维旋度：把梯度旋转九十度，得到无散度的流动场。
vec2 ogxEclipseCurl2D(vec2 coord)
{
    vec2 gradient = ogxEclipsePerlinGradient(coord); // 取梯度。
    return vec2(gradient.y, -gradient.x); // 旋转九十度。
}

// 极光的三维噪声：四个平移后的哈希值按距离加权，得到柔和的团块。
float ogxEclipseTriNoise2d(vec2 coord, float time)
{
    vec2 p = coord * 0.5; // 整体缩放。
    vec2 i = floor(p); // 整数格。
    vec2 f = fract(p); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑。
    float a = ogxEclipseHash2(i).x; // 左下。
    float b = ogxEclipseHash2(i + vec2(1.0, 0.0)).x; // 右下。
    float c = ogxEclipseHash2(i + vec2(0.0, 1.0)).x; // 左上。
    float d = ogxEclipseHash2(i + vec2(1.0, 1.0)).x; // 右上。
    float value = mix(mix(a, b, u.x), mix(c, d, u.x), u.y); // 双线性插值。
    float wave = sin(time + value * 6.28318530718) * 0.5 + 0.5; // 时间相位。
    return value * wave; // 噪声乘相位。
}

// 单层云形状：按层号走参考实现的分支，返回零到一的密度。
float ogxEclipseGetCloudShape(OgxEclipseCloudSettings s, int layerIndex, int lod, vec3 position,
    float minHeight, float maxHeight, sampler2D noiseTexture)
{
    float coverage = 0.0; // 云量。
    float shape = 0.0; // 形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    vec3 samplePos = position * vec3(0.25, 0.005, 0.25); // 形状取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    if (layerIndex == 4) // 卷云。
    {
        coverage = s.layers[4].coverage; // 卷云量。
        vec2 coord = position.zx + 6.0 * s.cloudMovement; // 卷云坐标。
        vec2 curl = ogxEclipseCurl2D(0.00002 * coord) * 0.5
                    + ogxEclipseCurl2D(0.00005 * coord) * 0.25
                    + ogxEclipseCurl2D(0.00018 * coord) * 0.125; // 三层旋度。
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 2.0) / 80000.0 * s.layers[4].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (0.000005 / s.layers[4].scale) * coord, 0.0).r; // 小尺度。
        float detailAmplitude = 0.3; // 初始细节振幅。
        float detailFrequency = 0.00002; // 初始细节频率。
        float curlStrength = 1.3; // 初始旋度强度。
        for (int i = 0; i < 3; ++i) // 三层细节。
        {
            float detail = textureLod(noiseTexture, coord * detailFrequency + curl * curlStrength, 0.0).r; // 取细节。
            smallCloud -= detail * detailAmplitude; // 从形状里削掉。
            detailAmplitude *= 0.5; // 振幅减半。
            detailFrequency *= 4.0; // 频率翻四倍。
            curlStrength *= 2.7; // 旋度增强。
        }
        smallCloud = abs(largeCloud * -0.4) + smallCloud; // 大尺度偏移。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖减去噪声。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 卷云不使用后面的通用包络。
    }
    if (layerIndex == 3) // 高层云。
    {
        coverage = s.layers[3].coverage + 0.0 * s.rainAmount + 0.0 * s.thunderStrength; // 高层云量。
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 20.0) / 100000.0 * s.layers[3].scale, 0.0).b; // 大尺度。
        vec2 altoCoord = (position.xz + vec2(-s.cloudMovement, s.cloudMovement) * 20.0) / 7500.0
            - vec2(1.0 - largeCloud, -largeCloud) / 5.0; // 高层云小尺度坐标。
        smallCloud = 1.0 - textureLod(noiseTexture, altoCoord * s.layers[3].scale, 0.0).b; // 小尺度。
        smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9 - largeCloud, 0.0, 1.0); // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
        shape *= shape; // 平方收边。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 高层云直接返回。
    }
    if (layerIndex == 1) // 大积云。
    {
        coverage = s.layers[1].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 雨天与雷暴增加云量。
        largeCloud = textureLod(noiseTexture, (samplePos.zx + s.cloudMovement * 3.0) / 10000.0 * s.layers[1].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (samplePos.zx - s.cloudMovement * 3.0) / 2500.0 * s.layers[1].scale, 0.0).b; // 小尺度。
        smallCloud = abs(largeCloud * -0.7) + smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    else if (layerIndex == 0) // 小积云。
    {
        coverage = s.layers[0].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 天气加成。
        largeCloud = textureLod(noiseTexture, (samplePos.xz + s.cloudMovement) / 5000.0 * s.layers[0].scale, 0.0).b; // 大尺度。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement) / 500.0 * s.layers[0].scale, 0.0).r; // 小尺度。
        smallCloud = abs(largeCloud - 0.6) + smallCloud * smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在层内。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 25.0, 1.0), 5.0); // 底部圆角。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-0.5 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 顶部圆角。
    shape = max((shape - 1.0) + topShape * bottomShape, 0.0); // 合成竖直包络。
    if (shape > 0.001) // 有形状才做侵蚀。
    {
        float erodeAmount = 0.5; // 侵蚀强度。
        if (lod < 1) return max(shape - 0.27 * erodeAmount, 0.0); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 侵蚀坐标随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 越高偏移越大。
        float erosion = 0.0; // 侵蚀量。
        float omShape = 1.0 - shape; // 反向形状。
        if (layerIndex == 0) // 小积云侵蚀。
        {
            erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale / 3.0, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
            float falloff = 1.0 - clamp(posToMax / (s.layers[0].tallness / s.layers[0].scale), 0.0, 1.0); // 高度衰减。
            erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale, noiseTexture, 512.0) - falloff)
                * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25); // 第二层侵蚀。
            erosion = erosion * erosion * erosion * erosion; // 四次方收边。
        }
        if (layerIndex == 1) // 大积云侵蚀。
        {
            erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale / 3.571428, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
            float falloff = 1.0 - clamp(posToMax / (s.layers[1].tallness / s.layers[1].scale), 0.0, 1.0); // 高度衰减。
            erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale, noiseTexture, 512.0) - falloff)
                * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5); // 第二层侵蚀。
            erosion = erosion * erosion * erosion * erosion; // 四次方收边。
        }
        return max(shape - erosion * erodeAmount, 0.0); // 减掉侵蚀。
    }
    return 0.0; // 没有形状。
}

// 积雨云形状：返回 `x` 为密度、`y` 为大云标记。
vec2 ogxEclipseGetCumulonimbusShape(OgxEclipseCloudSettings s, int lod, vec3 position, float minHeight, float maxHeight,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float largeCloud = 0.0; // 大尺度。
    float smallCloud = 0.0; // 小尺度。
    vec3 samplePos = position * vec3(1.0, 1.0 / 48.0, 1.0) / 4.0; // 取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶距离。
    largeCloud = max(sin((samplePos.x - s.cloudMovement * 10.0) / 2700.0) * cos((samplePos.z - s.cloudMovement * 10.0) / 2700.0), 0.0); // 大尺度波形。
    largeCloud = mix(max(min(largeCloud - 0.25, 0.5) * 2.0, 0.0), max(min(largeCloud, 0.25) * 4.0, 0.0), s.thunderStrength); // 雷暴时收窄。
    float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraPos)); // 远处才显示积雨云。
    float isLarge = smoothstep(0.0, 1.0, shape); // 大云标记。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 5.0, 1.0), 5.0); // 底部圆角。
    float smallMaxHeight = tallness * 0.45 + minHeight; // 小云顶。
    float shape2 = 0.0; // 第二层形状。
    if (position.y < smallMaxHeight) // 小云只在下半层。
    {
        float smallTallness = smallMaxHeight - minHeight; // 小云厚度。
        float posToMaxSmall = smallMaxHeight - position.y; // 小云到顶距离。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement * 4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r
            * smoothstep(smallMaxHeight, tallness * 0.2 + minHeight, position.y); // 小云噪声。
        shape2 = min(max(1.1 - smallCloud, 0.0) / sqrt(1.1), 1.0) * smoothstep(5000.0, 7000.0, length(position - cameraPos)); // 小云形状。
        shape2 = min(min(shape2, clamp(smallMaxHeight - position.y, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在小云内。
        float smallTopShape = min(max(posToMaxSmall, 0.0) / max(smallTallness, 1.0), 1.0); // 小云顶。
        smallTopShape = min(exp(23.0 * (1.0 - smallTopShape)), 1.0 - pow(1.0 - smallTopShape, 9.0)); // 圆角。
        shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0); // 合成。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在主层内。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-1.0 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 圆角。
    float topShape2 = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 第二顶部归一化。
    topShape2 = min(exp(-0.1 * (1.0 - topShape2)), 1.0 - pow(1.0 - topShape2, 7.0)); // 第二圆角。
    shape = max((shape - 1.0) + topShape * bottomShape + (1.0 - topShape2) * bottomShape, 0.0); // 合成主形状。
    shape = pow(shape, 1.0 + smoothstep(tallness * 0.4 + minHeight, tallness * 0.8 + minHeight, position.y)); // 越高越收。
    shape += shape2; // 加上小云。
    if (s.cumulonimbus == 1) shape *= pow(s.cumulonimbusStrength, mix(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y))); // 积雨云强度。
    if (shape > 0.001) // 有形状才侵蚀。
    {
        if (lod < 1) return vec2(max(shape - 0.27 * 0.5, 0.0), isLarge); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 高度偏移。
        float omShape = 1.0 - shape; // 反向形状。
        float erosion = (1.0 - ogxCloudDensityAtPos(samplePos * 190.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / 4600.0, 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * 580.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0) - falloff)
            * 0.65 * omShape * (1.0 - falloff * 0.5); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion * smoothstep(maxHeight + 40.0, tallness * 0.5 + minHeight, position.y); // 四次方并淡出。
        return vec2(max(shape - erosion * 0.5, 0.0), isLarge); // 返回密度与大云标记。
    }
    return vec2(0.0, isLarge); // 没有形状。
}

// 闪电位置：在云层半径内取一个随机方向，并确认那里确实有积雨云。
vec3 ogxEclipseGetLightningPosition(OgxEclipseCloudSettings s, float minHeight, float maxHeight, float cumulonimbusScale,
    vec3 cameraPos, sampler2D noiseTexture)
{
    float angle = fract(sin(dot(vec2(s.lightningBoltPosition.w), vec2(12.9898, 78.233))) * 43758.5453) * 6.28318530718; // 随机角。
    float rMin = 7000.0; // 内半径。
    float rMax = 13000.0; // 外半径。
    float radius = sqrt(mix(rMin * rMin, rMax * rMax, fract(sin(dot(vec2(s.lightningBoltPosition.w + 1.0), vec2(12.9898, 78.233))) * 43758.5453))); // 面积均匀的半径。
    vec3 lightningPos = vec3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 初始位置。
    float shapeAtLightning = ogxEclipseGetCumulonimbusShape(s, 0, lightningPos, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x; // 该处云密度。
    lightningPos.y = minHeight + (maxHeight - minHeight) * 0.48; // 参考实现把高度固定到 0.48。
    if (shapeAtLightning < 0.1) lightningPos = vec3(0.0); // 没有云就不闪。
    return lightningPos; // 交回相机相对位置。
}

// 行星阴影：太阳越低，主岛下方越暗。
float ogxEclipseGetPlanetShadow(vec3 playerPos, vec3 sunVector)
{
    float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / max(sunVector.y * 0.1, 0.0)), 0.0) / 100.0, 1.0); // 高度阈值。
    planetShadow = mix(pow(1.0 - pow(1.0 - planetShadow, 2.0), 2.0), 1.0, pow(max(sunVector.y, 0.0), 2.0)); // 太阳越高阴影越少。
    return planetShadow; // 交回阴影权重。
}

// 云影：把地面点沿太阳方向投到各层云，按层密度累加。
float ogxEclipseGetCloudShadow(OgxEclipseCloudSettings s, vec3 playerPos, vec3 sunVector, int cloudShadowAmount,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalShadow = ogxEclipseGetPlanetShadow(playerPos, sunVector); // 行星阴影。
    vec3 startPosition = playerPos; // 投影起点。
    vec3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向到单位高度的位移。
    if (cloudShadowAmount > 0) // 有云影才计算。
    {
        float cloudShadows = 0.0; // 云影累加。
        startPosition = playerPos + startOffset * max((s.layers[0].height + 20.0) - playerPos.y, 0.0); // 投到小积云下段。
        cloudShadows = ogxEclipseGetCloudShape(s, 0, 0, startPosition, s.layers[0].height,
            s.layers[0].height + s.layers[0].tallness / s.layers[0].scale, noiseTexture) * s.layers[0].rainDensity; // 小积云。
        startPosition = playerPos + startOffset * max((s.layers[1].height + 30.0) - playerPos.y, 0.0); // 投到大积云下段。
        cloudShadows += ogxEclipseGetCloudShape(s, 1, 0, startPosition, s.layers[1].height,
            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * s.layers[1].rainDensity; // 大积云。
        startPosition = playerPos + startOffset * max(s.layers[3].height - playerPos.y, 0.0); // 投到高层云。
        cloudShadows += ogxEclipseGetCloudShape(s, 3, 0, startPosition, s.layers[3].height, s.layers[3].height + 5.0,
            noiseTexture) * s.layers[3].rainDensity * (1.0 - abs(sunVector.y)); // 高层云。
        float distanceFactor = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), sunVector))), 45.0, 90.0) - 45.0; // 太阳角度。
        startPosition = playerPos + sunVector * mix(7000.0, 18000.0, distanceFactor / 45.0); // 投到积雨云。
        cloudShadows += ogxEclipseGetCumulonimbusShape(s, 0, startPosition, 600.0, 4600.0 + startPosition.y,
            cumulonimbusScale, cameraPos, noiseTexture).x; // 积雨云。
        cloudShadows *= float(cloudShadowAmount) / 100.0; // 按强度缩放。
        totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云越厚阴影越黑。
    }
    return totalShadow; // 交回总阴影。
}

// 步进起点：按相机在云层中的位置把射线压到平面，避免从错误的一侧开始。
vec3 ogxEclipseGetRayOrigin(vec3 rayStartPos, vec3 cameraPos, float dither, float minHeight, float maxHeight)
{
    vec3 cloudDist = vec3(1.0); // 水平与竖直的缩放。
    cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
        clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 越靠近云层水平步长越小。
    float flip = mix(max(cameraPos.y - maxHeight, 0.0), max(minHeight - cameraPos.y, 0.0), clamp(rayStartPos.y, 0.0, 1.0)); // 上下翻转。
    return rayStartPos * dither + cameraPos + (rayStartPos / length(rayStartPos / cloudDist)) * flip; // 压到平面并加抖动。
}

// 云的相函数：按 `mode` 选择 Henyey-Greenstein、Cornette-Shanks 或 HG-Draine。
float ogxEclipsePhaseCloud(float x, float g, int mode)
{
    if (mode == 1) // Cornette-Shanks。
    {
        return (3.0 * (1.0 - g * g) * (1.0 + x * x)) / (25.133 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * x, 1.5)); // 参考实现系数 25.133。
    }
    if (mode == 2) // HG-Draine。
    {
        const float a = 0.9; // 前向权重。
        float gg = g * g; // g 的平方。
        return ((1.0 - gg) * (1.0 + a * x * x)) / (4.0 * (1.0 + (a * (1.0 + 2.0 * gg)) / 3.0) * 3.1415926 * pow(1.0 + gg - 2.0 * g * x, 1.5)); // 参考实现公式。
    }
    float gg = g * g; // 默认 Henyey-Greenstein。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现除以 3.14。
}

// 朝光散射：沿光方向取几步云密度，层数与步长按层号决定。
float ogxEclipseGetCloudScattering(OgxEclipseCloudSettings s, int layerIndex, vec3 rayPosition, vec3 sunVector,
    vec3 moonVector, float dither, float minHeight, float maxHeight, float density, float cumulonimbusScale,
    float sunVisibility, float moonVisibility, vec3 cameraPos, sampler2D noiseTexture)
{
    int samples = 3; // 默认三步。
    if (layerIndex == 2) samples = 7; // 积雨云七步。
    if (layerIndex == 3 || layerIndex == 4) samples = 2; // 高层云与卷云两步。
    int lod = 0; // 光照取样用低细节。
    float shadow = 0.0; // 遮挡累加。
    vec3 shadowRayPosition = vec3(0.0); // 采样位置。
    float isLarge = 80.0; // 积雨云步长。
    vec3 lightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (layerIndex == 3 || layerIndex == 4) // 平面云沿日月方向。
        {
            shadowRayPosition = rayPosition + sunVector * sunVisibility * (0.25 + float(i) * dither) * 200.0
                + moonVector * moonVisibility * (0.25 + float(i) * dither) * 200.0; // 沿日月方向取样。
        }
        else if (layerIndex == 0 || layerIndex == 1) // 积云沿混合方向。
        {
            shadowRayPosition = rayPosition + lightVec * (0.25 + float(i) + dither) * 20.0; // 小步长。
        }
        else if (layerIndex == 2) // 积雨云大步长。
        {
            shadowRayPosition = rayPosition + lightVec * (0.5 + float(i) + dither) * isLarge; // 大步长。
            isLarge *= 1.374; // 每步放大。
        }
        if (layerIndex != 2) shadow += ogxEclipseGetCloudShape(s, layerIndex, lod, shadowRayPosition, minHeight, maxHeight, noiseTexture) * density; // 普通云。
        else shadow += ogxEclipseGetCumulonimbusShape(s, lod, shadowRayPosition, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x * density; // 积雨云。
    }
    return shadow; // 交回遮挡量。
}

// 云的光照：直射按 Beer 定律衰减，前后散射按粉末效应插值，间接光按形状抬升。
vec3 ogxEclipseGetCloudLighting(int layerIndex, float shape, float shapeFaded, float sunShadowMask, vec3 directLightCol,
    vec3 directLightCol2, float indirectShadowMask, vec3 indirectLightCol, vec3 rayPosition, float backScatterPhase,
    vec4 phaseLevels, float backScatterPhase2, vec4 phaseLevels2)
{
    vec3 heightScal = vec3(mix(1.0, 0.5, clamp(rayPosition.y, 0.0, 7000.0) / 7000.0)); // 高度对光色的压缩。
    directLightCol = pow(directLightCol, heightScal); // 直射颜色按高度压暗。
    directLightCol2 = pow(directLightCol2, heightScal); // 第二直射同样。
    float beerCoef = -4.0; // Beer 系数。
    float powder = min(exp(beerCoef * exp(beerCoef * shapeFaded)) * 3.5, 1.0); // 粉末效应。
    float backscatter = powder * backScatterPhase; // 后向散射。
    float forwardscatter = mix(mix(phaseLevels.x, phaseLevels.y, powder), mix(phaseLevels.z, phaseLevels.w, powder), powder); // 四档相函数插值。
    float backscatter2 = powder * backScatterPhase2; // 第二后向。
    float forwardscatter2 = mix(mix(phaseLevels2.x, phaseLevels2.y, powder), mix(phaseLevels2.z, phaseLevels2.w, powder), powder); // 第二前向。
    float expBeer = 6.28 * exp((beerCoef - 1.0) * sunShadowMask); // 直射透过率。
    vec3 directScattering = expBeer * directLightCol * (forwardscatter + backscatter); // 太阳直射。
    directScattering += expBeer * directLightCol2 * (forwardscatter2 + backscatter2); // 月亮直射。
    vec3 indirectScattering = indirectLightCol * mix(1.0, exp2(-5.0 * shape), indirectShadowMask * indirectShadowMask); // 间接光。
    return indirectScattering + directScattering; // 合成。
}

// 单层云的步进：参考实现的主循环，逐层处理平面云与积云两条路径。
// `cloudPlaneDistance` 的 `x` 是最近可见云的距离，`y` 是混合权重；由调用方按层合并。
vec4 ogxEclipseRaymarchCloud(OgxEclipseCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,
    float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,
    vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,
    inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,
    vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    vec3 color = vec3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 一步的世界长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex == 3 || layerIndex == 4) // 平面云路径。
    {
        float density = 0.0; // 这一层的密度。
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        if (layerIndex == 3) density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 高层云。
        else density = s.layers[4].rainDensity * smoothstep(s.layers[4].distance, s.layers[4].distance * 0.5, length(newPos)); // 卷云。
        if (density == 0.0) return vec4(color, totalAbsorbance); // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(cameraPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面的哪一侧。
        if (!deferred && length(newPos) > referenceDistance) return vec4(color, totalAbsorbance); // 世界几何挡住云。
        if (ifAboveOrBelowPlane) return vec4(color, totalAbsorbance); // 背向云层的一侧不步进。
        float shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 取样形状。
        float shapeWithDensity = shape * density; // 乘密度。
        if (shapeWithDensity > mix(1e-5, 0.06, dither)) // 记录最近可见云。
        {
            cloudPlaneDistance.x = length(newPos);
            cloudPlaneDistance.y = 0.0;
        }
        if (shapeWithDensity > 1e-5) // 有云才做光照。
        {
            float sunShadowMask = ogxEclipseGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture) * (1.0 - abs(sunVector.y)); // 朝光遮挡。
            float indirectShadowMask = 0.5; // 平面云间接光固定半量。
            vec3 lighting = ogxEclipseGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensity, sunShadowMask,
                sunScattering, moonScattering, indirectShadowMask, skyScattering, rayPosition, backScatterPhase, phaseLevels,
                backScatterPhase2, phaseLevels2); // 光照。
            newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视的距离压缩。
            float distancefog = exp2(0.4 * s.distanceFogScale * length(newPos.xz)); // 距离雾。
            vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
            lighting = lighting * distancefog + atmosphereHaze; // 混进雾。
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 这一段的透过率。
            color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 按剩余透过率累加。
            totalAbsorbance *= densityCoeff; // 更新透过率。
        }
        return vec4(color, totalAbsorbance); // 平面云只取一个样本。
    }
    if (layerIndex < 3) // 积云路径。
    {
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(newPos)); // 小积云距离淡出。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(newPos)); // 大积云距离淡出。
        if (layerIndex == 2) density = 0.8; // 积雨云固定密度。
        if (density < 0.01) return vec4(color, totalAbsorbance); // 密度太低跳过。
        float skylightOcclusion = 1.0; // 上层云对天空光的遮挡。
        if (layerIndex == 0) // 小积云会被大积云遮住天光。
        {
            float upperLayerOcclusion = ogxEclipseGetCloudShape(s, 1, 0, rayPosition + vec3(0.0, 1.0, 0.0)
                * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0), s.layers[1].height, s.layers[1].height + 100.0, noiseTexture); // 上层形状。
            skylightOcclusion = mix(mix(0.0, 0.2, densityLarge), 1.0, pow(1.0 - upperLayerOcclusion * densityLarge, 2.0)); // 混合天光。
        }
        vec3 lightningPos = vec3(0.0); // 积雨云闪电位置。
        if (s.lightningEnabled > 0 && layerIndex == 2) lightningPos = ogxEclipseGetLightningPosition(s, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 只有积雨云取闪电位。
        vec3 mainLightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
        float tallness = maxHeight - minHeight; // 层厚。
        bool maxFogDistReached = false; // 是否已经记录最近云。
        for (int i = 0; i < samples; i++) // 主步进循环。
        {
            newPos = rayPosition - cameraPos; // 更新相对位置。
            if (!deferred && length(newPos) > referenceDistance) break; // 世界几何挡住后面。
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 在云层包围盒内。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxEclipseGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云标记放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 按高度淡出。
                if (shapeWithDensityFaded > densityThresholdCheck && !maxFogDistReached) // 记录最近可见云。
                {
                    cloudPlaneDistance.x = length(newPos);
                    cloudPlaneDistance.y = 0.0;
                    maxFogDistReached = true;
                }
                if (shapeWithDensityFaded > 1e-5) // 有云才继续。
                {
                    vec3 shadow = vec3(1.0); // 地形阴影默认全亮。
                    if (terrainShadowOnClouds) // 开启地形阴影时投到阴影图。
                    {
                        vec3 fragPosition = ogxMatrixMulPoint(shadowView, newPos) + ogxMatrixTranslation(shadowView); // 阴影相机空间。
                        fragPosition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragPosition
                            + ogxMatrixTranslation(shadowProjection); // 阴影投影。
                        float distortFactor = shadowDistort > 0.0 ? 1.0 / (log(length(fragPosition.xy) * 0.61 + 1.0) * 1.8) : 1.0; // 参考实现的边缘压缩。
                        vec3 shadowPos = vec3(fragPosition.xy * distortFactor, fragPosition.z); // 压缩后的阴影坐标。
                        if (abs(shadowPos.x) < 1.0 - 0.5 / 2048.0 && abs(shadowPos.y) < 1.0 - 0.5 / 2048.0) // 在阴影图内。
                        {
                            shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 转零到一。
                            shadow = vec3(textureLod(shadowTexture, shadowPos.xy, 0.0).x); // 读阴影。
                        }
                    }
                    float indirectShadowMask = 1.0 - min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0); // 间接光遮挡。
                    float sunShadowMask = ogxEclipseGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                        minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture); // 朝光遮挡。
                    vec3 shadowStartPos = vec3(0.0); // 层间阴影起点。
                    if (layerIndex == 0) // 大积云投到小积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0); // 投到上层。
                        sunShadowMask += 3.0 * ogxEclipseGetCloudShape(s, 1, 0, shadowStartPos, s.layers[1].height,
                            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * densityLarge; // 上层遮挡。
                    }
                    if (layerIndex != 2 && s.cumulonimbus > 0) // 积雨云投到其他积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec * 9000.0; // 大步投到积雨云。
                        sunShadowMask += ogxEclipseGetCumulonimbusShape(s, 0, shadowStartPos, 600.0, 4600.0 + shadowStartPos.y, 1.0, cameraPos, noiseTexture).x * 3.0; // 积雨云遮挡。
                    }
                    shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max(s.layers[3].height - rayPosition.y, 0.0); // 投到高层云。
                    sunShadowMask += ogxEclipseGetCloudShape(s, 3, 0, shadowStartPos, s.layers[3].height, s.layers[3].height, noiseTexture)
                        * s.layers[3].rainDensity * (1.0 - abs(mainLightVec.y)); // 高层云遮挡。
                    vec3 lighting = ogxEclipseGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensityFaded, sunShadowMask,
                        sunScattering * shadow, moonScattering * shadow, indirectShadowMask, skyScattering * skylightOcclusion, rayPosition,
                        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2); // 光照。
                    float horizontalDist = length(newPos.xz - s.lightningBoltPosition.xz); // 普通闪电水平距离。
                    if (horizontalDist < 7500.0 && s.lightningBoltPosition.w > 0.0) // 普通闪电照亮云。
                    {
                        float lightningIntensity = exp(-horizontalDist * 0.006) * density * s.lightningFlash; // 闪电强度。
                        lighting = mix(lighting, vec3(1.3, 1.5, 3.0), lightningIntensity); // 混向冷白。
                    }
                    if (s.lightningEnabled > 0 && (layerIndex == 2 || s.thunderStrength > 0.0)) // 积雨云闪电。
                    {
                        float lightningDist = length(newPos - lightningPos); // 到闪电位距离。
                        if (lightningDist < 6000.0 && lightningPos != vec3(0.0)) // 在照明范围内。
                        {
                            float lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity)
                                * s.lightningFlash; // 距离与密度权重。
                            lightningIntensity *= 1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y); // 高度淡出。
                            lightningIntensity *= smoothstep(17000.0, 14000.0, horizontalDist); // 水平淡出。
                            lightningIntensity *= s.lightningFade; // 时间淡出。
                            vec3 lightningStrength = s.cumulonimbusLightningColor * s.cumulonimbusLightningBrightness * 0.125; // 闪电颜色。
                            lighting = mix(lighting, lightningStrength, lightningIntensity); // 混向闪电。
                        }
                    }
                    newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视距离压缩。
                    float distancefog = exp2(s.distanceFogScale * length(newPos.xz)); // 距离雾。
                    vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
                    lighting = lighting * distancefog + atmosphereHaze; // 混雾。
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded); // 这一段透过率。
                    color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 累加。
                    totalAbsorbance *= densityCoeff; // 更新透过率。
                    if (totalAbsorbance < 1e-5) break; // 已经完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
        return vec4(color, totalAbsorbance); // 交回这一层的颜色与透过率。
    }
    return vec4(color, totalAbsorbance); // 未知层号原样返回。
}

// 五层体积云总入口：按参考实现的顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合。
// `sampledSkyCol` 是调用方从天空查表取到的颜色，已经除以参考实现的 1200。
vec4 ogxEclipseGetVolumetricClouds(OgxEclipseCloudSettings s, vec3 viewPos, vec2 dither, vec3 sunVector,
    vec3 moonVector, vec3 directLightCol, vec3 directLightCol2, vec3 indirectLightCol,
    inout float cloudPlaneDistance, inout vec2 cloudDistance, vec3 cameraPos, vec3 sampledSkyCol,
    float farPlane, float dhFarPlane, mat4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, vec3 shadowCameraPos, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 累积透过率。
    vec4 cloudColor = vec4(color, totalAbsorbance); // 当前层结果。
    vec4 cloudColorOriginal = cloudColor; // 每层重置用。
    float cloudheight = s.layers[0].tallness / s.layers[0].scale; // 第一层厚度。
    float minHeight = s.layers[0].height; // 第一层云底。
    float maxHeight = cloudheight + minHeight; // 第一层云顶。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - minHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层的高度。
    float maxdist = dhFarPlane > 0.0 ? dhFarPlane - 16.0 : farPlane + 16.0 * 5.0; // 最大可见距离。
    float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 1.0e8; // 参考实现的距离哨兵。
    vec4 normPlayerPos = vec4(ogxMatrixMulPoint(modelViewInverse, viewPos) + ogxMatrixTranslation(modelViewInverse), 1.0); // 视空间转世界。
    normPlayerPos = normalize(normPlayerPos); // 单位视线方向。
    float sdotv = dot(sunVector, normPlayerPos.xyz); // 太阳与视线夹角。
    float sdotv2 = dot(moonVector, normPlayerPos.xyz); // 月亮与视线夹角。
    if (skyGround) normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点，避免云压到地平线。
    float cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
        clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 相机在层内时水平步长更小。
    vec3 cloudDist = vec3(1.0); // 水平与竖直步长。
    cloudDist.xz = mix(vec2(255.0), vec2(5.5), cloudMix); // 层内 5.5，层外 255。
    vec3 rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / min(cloudDist, vec3(0.05 * lViewPosM))) / float(samples)); // 一层走完的步长。
    vec3 rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点压到云层平面。
    sampledSkyCol *= skyBrightness; // 天空亮度。
    vec3 playerPos = ogxMatrixMulPoint(modelViewInverse, viewPos); // 相机相对世界位置。
    float maxLength = min(length(playerPos), farPlane) / max(length(playerPos), 1e-4); // 限制到远平面。
    playerPos *= maxLength; // 截断。
    float startDistance = length(playerPos); // 到像素的距离。
    float sunVis = smoothstep(-0.06, 0.1, s.sunElevation); // 太阳可见度。
    float moonVis = smoothstep(0.0, 0.075, -s.moonElevation); // 月亮可见度。
    float backScatterPhase = 0.0; // 太阳后向散射。
    vec4 phaseLevels = vec4(0.0); // 太阳四档相函数。
    if (sunVis > 0.0) // 太阳在地平线上才算。
    {
        backScatterPhase = ogxEclipsePhaseCloud(-sdotv, 0.25, 0) * 2.0; // 后向。
        phaseLevels = vec4(ogxEclipsePhaseCloud(sdotv, 0.80, 0), ogxEclipsePhaseCloud(sdotv, 0.55, 0),
            ogxEclipsePhaseCloud(sdotv, 0.35, 0), ogxEclipsePhaseCloud(sdotv, 0.10, 0)); // 四档前向。
    }
    float backScatterPhase2 = 0.0; // 月亮后向。
    vec4 phaseLevels2 = vec4(0.0); // 月亮四档。
    if (moonVis > 0.0) // 月亮在地平线上才算。
    {
        backScatterPhase2 = ogxEclipsePhaseCloud(-sdotv2, 0.25, 0) * 2.0; // 后向。
        phaseLevels2 = vec4(ogxEclipsePhaseCloud(sdotv2, 0.80, 0), ogxEclipsePhaseCloud(sdotv2, 0.55, 0),
            ogxEclipsePhaseCloud(sdotv2, 0.35, 0), ogxEclipsePhaseCloud(sdotv2, 0.10, 0)); // 四档前向。
    }
    vec3 sunScattering = directLightCol * sunVis * sunVis; // 太阳散射。
    vec3 moonScattering = directLightCol2 * moonVis * moonVis * (1.0 - sunVis * sunVis); // 月亮散射。
    vec3 skyScattering = indirectLightCol * (1.0 + sunVis); // 天空散射。
    bool mixBelowLayer0 = cameraPos.y < s.layers[0].height + s.layers[0].tallness; // 相机是否在小积云下方。
    bool mixBelowLayer1 = cameraPos.y < s.layers[1].height; // 相机是否在大积云下方。
    vec4 smallCumulusClouds = cloudColorOriginal; // 小积云结果。
    vec2 cloudLayer0Distance = vec2(startDistance, 1.0); // 小积云距离。
    smallCumulusClouds = ogxEclipseRaymarchCloud(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer0Distance,
        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
        shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 小积云。
    cloudColor.a *= smallCumulusClouds.a; // 更新透过率。
    float smallCumulusDistance = length(rayPosition - cameraPos); // 小积云命中距离。
    vec4 largeCumulusClouds = cloudColorOriginal; // 大积云结果。
    vec2 cloudLayer1Distance = vec2(startDistance, 1.0); // 大积云距离。
    if (cloudColor.a > 1e-5 || !mixBelowLayer1) // 有剩余光且相机位置合适。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
            clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 重算混合。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), cloudMix); // 大积云水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(samples)); // 重算步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        largeCumulusClouds = ogxEclipseRaymarchCloud(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer1Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 大积云。
        cloudColor.a *= largeCumulusClouds.a; // 更新透过率。
    }
    float largeCumulusDistance = length(rayPosition - cameraPos); // 大积云命中距离。
    vec4 cumulonimbusClouds = cloudColorOriginal; // 积雨云结果。
    vec2 cloudLayer4Distance = vec2(startDistance, 1.0); // 积雨云距离。
    if (s.cumulonimbus > 0 && (cloudColor.a > 1e-5 || !mixBelowLayer0)) // 开启积雨云。
    {
        cloudheight = 4000.0; // 积雨云厚度。
        minHeight = 600.0; // 积雨云底。
        maxHeight = cloudheight + minHeight; // 积雨云顶。
        int cumulonimbusSamples = 2 * samples; // 两倍样本。
        cloudDist.xz = vec2(8.0); // 固定水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist) / float(cumulonimbusSamples)); // 重算步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 重算起点。
        cumulonimbusClouds = ogxEclipseRaymarchCloud(s, 2, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol,
            cloudLayer4Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds,
            deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 积雨云。
        cloudColor.a *= cumulonimbusClouds.a; // 更新透过率。
    }
    float cumulonimbusDistance = length(rayPosition - cameraPos); // 积雨云命中距离。
    vec4 altoStratusClouds = cloudColorOriginal; // 高层云结果。
    vec2 cloudLayer2Distance = vec2(startDistance, 1.0); // 高层云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画高层云。
    {
        cloudheight = 5.0; // 高层云很薄。
        minHeight = s.layers[3].height; // 高层云底。
        maxHeight = cloudheight + minHeight; // 高层云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        altoStratusClouds = ogxEclipseRaymarchCloud(s, 3, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer2Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 高层云。
        cloudColor.a *= altoStratusClouds.a; // 更新透过率。
    }
    vec4 cirrusClouds = cloudColorOriginal; // 卷云结果。
    vec2 cloudLayer3Distance = vec2(startDistance, 1.0); // 卷云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画卷云。
    {
        cloudheight = 5.0; // 卷云很薄。
        minHeight = s.layers[4].height; // 卷云底。
        maxHeight = cloudheight + minHeight; // 卷云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        rayDirection = normPlayerPos.xyz * (cloudheight / length(normPlayerPos.xyz / cloudDist)); // 单步走到层顶。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, maxHeight); // 起点。
        cirrusClouds = ogxEclipseRaymarchCloud(s, 4, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer3Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 卷云。
        cloudColor.a *= cirrusClouds.a; // 更新透过率。
    }
    if (cameraPos.y > s.layers[1].height) // 相机在大积云上方时交换远近层。
    {
        vec2 temp = cloudLayer1Distance;
        cloudLayer1Distance = cloudLayer0Distance;
        cloudLayer0Distance = temp;
    }
    float tempDistance = mix(cloudLayer2Distance.x, cloudLayer3Distance.x, cloudLayer2Distance.y); // 高层与卷云按权重混合。
    tempDistance = mix(cloudLayer1Distance.x, tempDistance, cloudLayer1Distance.y); // 大积云再混合。
    cloudPlaneDistance = mix(cloudLayer0Distance.x, tempDistance, cloudLayer0Distance.y); // 小积云再混合。
    if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance; // 闪电检测用的小积云距离。
    if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance; // 大积云覆盖。
    if (cameraPos.y < s.layers[1].height) // 相机在下层时的顺序。
    {
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
    }
    else
    {
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
    }
    if (cumulonimbusClouds.a < 1.0) cloudDistance.g = cumulonimbusDistance; // 积雨云距离。
    if (cloudDistance.r > 15000.0) cloudDistance.r = 0.0; // 太远就不算闪电高度。
    if (cloudDistance.g > 15000.0) cloudDistance.g = 0.0;
    cloudColor.rgb = cirrusClouds.rgb; // 先放卷云。
    cloudColor.rgb *= altoStratusClouds.a; // 再乘高层云透过率。
    cloudColor.rgb += altoStratusClouds.rgb; // 加高层云。
    if (mixBelowLayer0) // 相机在小积云下方：从下往上合成。
    {
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
    }
    else if (mixBelowLayer1) // 相机在大积云下方。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
    }
    else // 相机在更高处。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
    }
    color = cloudColor.rgb; // 最终颜色。
    totalAbsorbance = cloudColor.a; // 最终透过率。
    return vec4(color, totalAbsorbance); // 交回云颜色与透过率。
}

// 云影步进：只算透过率，不算光照，供阴影程序低成本使用。
float ogxEclipseRaymarchCloudSimple(OgxEclipseCloudSettings s, int layerIndex, int samples, vec3 rayPosition,
    vec3 rayDirection, float dither, float minHeight, float maxHeight, vec3 startPos, vec3 cameraPos,
    sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 初始完全透明。
    float distanceFactor = length(rayDirection); // 一步长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3) densityThresholdCheck = 0.01; // 高层云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动插值。
    if (layerIndex == 3) // 高层云单样本。
    {
        vec3 newPos = rayPosition - startPos; // 相对起点。
        float density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 距离密度。
        if (density == 0.0) return totalAbsorbance; // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0))
            * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面哪一侧。
        if (ifAboveOrBelowPlane) return totalAbsorbance; // 背向不步进。
        float shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 形状。
        float shapeWithDensity = shape * density; // 密度。
        if (shapeWithDensity > 1e-5) totalAbsorbance *= exp(-distanceFactor * shapeWithDensity); // 乘透过率。
        return totalAbsorbance; // 交回透过率。
    }
    if (layerIndex < 3) // 积云。
    {
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(rayPosition - startPos)); // 小积云。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(rayPosition - startPos)); // 大积云。
        if (layerIndex == 2) density = 0.8; // 积雨云。
        if (density < 0.01) return totalAbsorbance; // 密度太低。
        float tallness = maxHeight - minHeight; // 层厚。
        for (int i = 0; i < samples; i++) // 主循环。
        {
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 包围盒。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxEclipseGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxEclipseGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 高度淡出。
                if (shapeWithDensityFaded > 1e-5) // 有云。
                {
                    totalAbsorbance *= exp(-distanceFactor * shapeWithDensityFaded); // 乘透过率。
                    if (totalAbsorbance < 1e-5) break; // 完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
    }
    return totalAbsorbance; // 交回透过率。
}

// 云影总入口：返回四个透过率，供阴影程序按层重建云影。
vec4 ogxEclipseGetVolumetricCloudsSimple(OgxEclipseCloudSettings s, vec2 dither, vec3 lightDir, vec2 offset,
    vec3 startPos, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - s.layers[0].height, 0.0) / 100.0, 0.0, 1.0); // 相机高度。
    vec3 normPlayerPos = lightDir; // 光线方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点。
    int samples = 5; // 固定五步。
    vec3 cloudDist = vec3(1.0); // 水平步长。
    float cloudheight = 5.0; // 高层云厚度。
    float minHeight = s.layers[3].height; // 高层云底。
    float maxHeight = cloudheight + minHeight; // 高层云顶。
    cloudDist.xz = vec2(255.0); // 平面云水平步长。
    vec3 rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步。
    vec3 rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
    rayPosition.xz += offset; // 阴影偏移。
    float altoStratusClouds = ogxEclipseRaymarchCloudSimple(s, 3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        startPos, cameraPos, noiseTexture); // 高层云。
    totalAbsorbance *= altoStratusClouds; // 更新透过率。
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        largeCumulusClouds = ogxEclipseRaymarchCloudSimple(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 大积云。
        totalAbsorbance *= largeCumulusClouds; // 更新透过率。
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[0].tallness / s.layers[0].scale; // 小积云厚度。
        minHeight = s.layers[0].height; // 小积云底。
        maxHeight = cloudheight + minHeight; // 小积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxEclipseGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        smallCumulusClouds = ogxEclipseRaymarchCloudSimple(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 小积云。
        totalAbsorbance *= smallCumulusClouds; // 更新透过率。
    }
    return vec4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四个透过率。
}

#endif

/*
生成文件：Eclipse 补充模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 补充模块：环境光遮蔽、阴影压缩、雾相位、颜色抖动与闪电。
调用位置：需要复现 Eclipse 小工具的后期与光照程序；Minecraft 光影由 `/omni-gfx/eclipse_extra.glsl` 引入。
可复制示例：
    float ao = ogxEclipseAmbientOcclusion(screenPos, viewPos, normal, dither, depthTex, viewport, viewPixel, handDepth);
    vec3 d = ogxEclipseFp10Dither(color, texCoord, frameTime);
设计原因与取舍：
    这些函数在原程序里直接依赖全局深度图、矩阵与天气。库把纹理、尺寸、阈值与噪声全部改为参数，
    函数体保留原来的常数与采样顺序。调试文字、实体枚举与菜单不在这里，仍留在宿主。
*/
#ifndef OGX_ECLIPSE_EXTRA_INCLUDED
#define OGX_ECLIPSE_EXTRA_INCLUDED

// 相机变换与数学提供投影、夹紧和反余弦。


// GTAO 的弧段积分：两个水平角之间覆盖的余弦积分。
float ogxEclipseIntegrateArc(vec2 h, float n, float cosN)
{
    vec2 tmp = cosN + 2.0 * h * sin(n) - cos(2.0 * h - n); // 参考实现的积分核。
    return 0.25 * (tmp.x + tmp.y); // 两个方向取平均。
}

// 单个切片的最大水平角：沿切片方向在深度图里找最高遮挡。
float ogxEclipseMaxHorizonAngle(vec3 viewSliceDir, vec3 viewerDir, vec3 screenPos, vec3 viewPos, float dither,
    float radius, int steps, vec3 viewPixelSize, vec2 viewRes, float renderScale, float handDepth,
    float falloffStart, sampler2D depthTexture, mat4 projection, mat4 projectionInverse)
{
    float stepSize = radius / float(steps); // 每步的视空间长度。
    float maxCosTheta = -1.0; // 最大遮挡角余弦。
    vec3 endScreen = ogxViewToScreenSpace(viewPos + viewSliceDir * stepSize, projection); // 一步后的屏幕坐标。
    vec2 rayStep = endScreen.xy - screenPos.xy; // 屏幕步长。
    float pixelScale = max(viewPixelSize.x, max(viewPixelSize.y, viewPixelSize.z)); // 最大像素尺度。
    vec2 rayPos = screenPos.xy + rayStep * (dither + pixelScale / max(length(rayStep), 1e-6)); // 起点加抖动与一个像素偏移。
    for (int i = 0; i < steps; ++i) // 逐步采样。
    {
        ivec2 pixel = ivec2(clamp(rayPos, 0.0, 1.0) * viewRes * renderScale - 0.5); // 屏幕比例换像素。
        float depth = texelFetch(depthTexture, pixel, 0).x; // 读深度。
        if (depth == 1.0 || depth < handDepth || depth == screenPos.z) // 天空、手与自身都跳过。
        {
            rayPos += rayStep;
            continue;
        }
        vec3 offset = ogxScreenToViewSpace(vec3(rayPos, depth), projectionInverse) - viewPos; // 采样点相对当前点的视空间偏移。
        float lenSq = dot(offset, offset); // 距离平方。
        float norm = inversesqrt(lenSq); // 距离倒数。
        float distanceFalloff = ogxSaturate((lenSq * norm - falloffStart * radius) / (radius - falloffStart * radius)); // 距离淡出。
        float cosTheta = dot(viewerDir, offset) * norm; // 夹角余弦。
        cosTheta = mix(cosTheta, -1.0, distanceFalloff); // 远处压到水平线以下。
        maxCosTheta = max(cosTheta, maxCosTheta); // 取最大。
        rayPos += rayStep;
    }
    return ogxFastAcos(clamp(maxCosTheta, -1.0, 1.0)); // 反余弦得到角度。
}

// GTAO 环境光遮蔽：沿多个切片各取两个最大水平角，再积分成遮蔽。
float ogxEclipseAmbientOcclusion(vec3 screenPos, vec3 viewPos, vec3 viewNormal, vec2 dither, int slices,
    float radius, int horizonSteps, float falloffStart, vec3 viewPixelSize, vec2 viewRes, float renderScale,
    float handDepth, sampler2D depthTexture, mat4 projection, mat4 projectionInverse)
{
    float ao = 0.0; // 累加遮蔽。
    vec3 viewerDir = normalize(-viewPos); // 视线方向。
    vec3 viewerRight = normalize(cross(vec3(0.0, 1.0, 0.0), viewerDir)); // 右方向。
    vec3 viewerUp = cross(viewerDir, viewerRight); // 上方向。
    mat3 localToView = mat3(viewerRight, viewerUp, viewerDir); // 局部到视空间。
    for (int i = 0; i < slices; ++i) // 逐切片。
    {
        float sliceAngle = (float(i) + dither.x) * (OGX_PI / float(slices)); // 切片角。
        vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        vec3 viewSliceDir = ogxMatrix3MulPoint(localToView, sliceDir); // 转到视空间。
        vec3 orthoDir = sliceDir - dot(sliceDir, viewerDir) * viewerDir; // 切片在视线垂直平面的投影。
        vec3 axis = cross(sliceDir, viewerDir); // 旋转轴。
        vec3 projectedNormal = viewNormal - axis * dot(viewNormal, axis); // 法线投影。
        float lenSq = dot(projectedNormal, projectedNormal); // 投影长度平方。
        float norm = inversesqrt(lenSq); // 倒数。
        float signGamma = sign(dot(orthoDir, projectedNormal)); // 法线在切片哪一侧。
        float cosGamma = ogxSaturate(dot(projectedNormal, viewerDir) * norm); // 法线与视线夹角余弦。
        float gamma = signGamma * ogxFastAcos(cosGamma); // 夹角。
        vec2 maxHorizonAngles; // 两个方向的最大水平角。
        maxHorizonAngles.x = ogxEclipseMaxHorizonAngle(-viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 负方向。
        maxHorizonAngles.y = ogxEclipseMaxHorizonAngle(viewSliceDir, viewerDir, screenPos, viewPos, dither.y, radius,
            horizonSteps, viewPixelSize, viewRes, renderScale, handDepth, falloffStart, depthTexture, projection, projectionInverse); // 正方向。
        maxHorizonAngles = gamma + clamp(vec2(-1.0, 1.0) * maxHorizonAngles - gamma, -OGX_HALF_PI, OGX_HALF_PI); // 限制在半球内。
        ao += ogxEclipseIntegrateArc(maxHorizonAngles, gamma, cosGamma) * lenSq * norm; // 积分这一段。
    }
    ao *= 1.0 / float(slices); // 取平均。
    return ao * (ao * 0.5 + 0.5); // 参考实现的对比度重整。
}

// Eclipse 阴影边缘压缩：按到阴影图中心的距离给一个放大系数。
float ogxEclipseCalcDistort(vec2 worldPos, float a, float b, float k)
{
    return 1.0 / (log(length(worldPos) * b + a) * k); // 参考实现对数的边缘压缩。
}

// Eclipse 阴影投影偏差：读入齐次阴影坐标，按同一压缩系数缩放横纵。
vec4 ogxEclipseBiasShadowProjection(vec4 projectedShadowSpacePosition, float a, float b, float k)
{
    float distortFactor = log(length(projectedShadowSpacePosition.xy) * b + a) * k; // 与读取端一致。
    projectedShadowSpacePosition.xy /= distortFactor; // 压缩横纵。
    return projectedShadowSpacePosition; // 交回坐标。
}

// 硬阴影：阴影图深度比接收点更远时返回零，否则一。
float ogxEclipseCalculateHardShadows(float shadowDepth, vec3 shadowPosition, float bias)
{
    if (shadowPosition.z >= 1.0) return 1.0; // 阴影图外保持全亮。
    return 1.0 - step(shadowDepth, shadowPosition.z - bias); // 参考实现的阶跃比较。
}

// 自定义旋转矩阵：绕倾斜轴旋转一天的时间角，供月亮轨道与阴影相机使用。
mat3 ogxEclipseCustomRotation(float rotationAngle, float timeOfDay)
{
    float radiance = timeOfDay / 24000.0 * 6.28319; // 一天转一圈。
    float sunRotRad = radians(rotationAngle); // 倾斜角。
    vec3 rotationAxis = vec3(0.0, sin(sunRotRad), cos(sunRotRad)); // 倾斜轴。
    float c = cos(radiance); // 旋转余弦。
    float s = sin(radiance); // 旋转正弦。
    float t = 1.0 - c; // 一减余弦。
    mat3 tiltRotation = mat3(
        t * rotationAxis.x * rotationAxis.x + c,
        t * rotationAxis.x * rotationAxis.y - s * rotationAxis.z,
        t * rotationAxis.x * rotationAxis.z + s * rotationAxis.y,
        t * rotationAxis.y * rotationAxis.x + s * rotationAxis.z,
        t * rotationAxis.y * rotationAxis.y + c,
        t * rotationAxis.y * rotationAxis.z - s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.x - s * rotationAxis.y,
        t * rotationAxis.z * rotationAxis.y + s * rotationAxis.x,
        t * rotationAxis.z * rotationAxis.z + c); // 按列填写的旋转矩阵。
    return tiltRotation; // 交回旋转。
}

// 法线夹紧：把背向视线的法线朝视线方向拉回，避免掠射高光发黑。
vec3 ogxEclipseClampNormal(vec3 n, vec3 v)
{
    float nDotV = ogxSaturate(dot(n, -v)); // 法线与视线夹角余弦。
    return normalize(nDotV * v + n); // 参考实现的混合。
}

// 笛卡尔坐标转球面纹理坐标。
vec3 ogxEclipseCartToSphere(vec2 coord)
{
    coord.y = 1.0 - coord.y; // 翻转纵轴。
    coord *= vec2(2.0 * OGX_PI, OGX_PI); // 换成角度。
    vec2 lon = vec2(sin(coord.x), cos(coord.x)) * sin(coord.y); // 经度方向。
    return vec3(lon.x, cos(coord.y), lon.y); // 单位球方向。
}

// 球面方向转笛卡尔纹理坐标。
vec2 ogxEclipseSphereToCart(vec3 dir)
{
    float lonlat = atan(-dir.x, -dir.z); // 经度。
    return vec2(lonlat / (2.0 * OGX_PI) + 0.5, 0.5 * dir.y + 0.5); // 与上一函数互逆。
}

// 雾相位：Eclipse 的指数相位，光线越正对越亮。
float ogxEclipseFogPhase(float lightPoint)
{
    float linear = clamp(-lightPoint * 0.5 + 0.5, 0.001, 1.0); // 线性项。
    float exponential = exp2(pow(linear, 0.3) * -15.0) * 1.5; // 指数项。
    exponential += sqrt(exp2(sqrt(linear) * -12.5)); // 开方项。
    return exponential; // 交回相位。
}

// 三角白噪声：中心化后开方，得到更适合抖动的分布。
float ogxEclipseTriangWhiteNoise(vec2 n, float frameTime)
{
    float t = fract(frameTime); // 帧内小数。
    float rnd = fract(sin(dot(n + 0.07 * t, vec2(12.9898, 78.233))) * 43758.5453); // 白噪声。
    float center = rnd * 2.0 - 1.0; // 中心化。
    rnd = center * inversesqrt(abs(center) + 1e-20); // 开方。
    rnd = max(-1.0, rnd); // 下限。
    return rnd - sign(center); // 三角分布。
}

// 按浮点尾数位抖动颜色：十位、十六位与整数八九十十六位各一版。
vec3 ogxEclipseDither(vec3 color, vec2 texCoord, float frameTime, int mode)
{
    float dither = ogxEclipseTriangWhiteNoise(texCoord, frameTime); // 抖动值。
    if (mode == 0) return color + dither * exp2(-vec3(6.0, 6.0, 5.0)) * exp2(floor(log2(color))); // 十位尾数。
    if (mode == 1) return color + dither * exp2(-10.0) * exp2(floor(log2(color))); // 十六位尾数。
    if (mode == 2) return color + dither * exp2(-8.0); // 八位整数。
    if (mode == 3) return color + dither * exp2(-10.0); // 十位整数。
    return color + dither * exp2(-16.0); // 十六位整数。
}

// 闪电照亮表面：距离衰减、次表面相位与法线朝向一起决定亮度。
vec3 ogxEclipseLightningFlash(vec3 feetPlayerPos, vec4 boltPosition, vec3 worldNormal, vec3 lightningEffect,
    inout float phase)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y + 16.0, boltPosition.y + 116.0), boltPosition.z); // 闪电到表面。
    float lightDistance = 300.0; // 照明半径。
    float lightningLight = max(1.0 - length(lightningPos) / lightDistance, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    vec3 phasePos = normalize(feetPlayerPos) + vec3(boltPosition.x, boltPosition.y + 60.0, boltPosition.z); // 相位方向。
    float phaseOrigin = 1.0 - ogxSaturate(dot(normalize(feetPlayerPos), normalize(phasePos))); // 相位夹角。
    phase = exp(sqrt(phaseOrigin) * -2.0) * 5.0 * lightningLight; // 次表面相位。
    float ndotl = ogxSaturate(dot(lightningPos, -worldNormal)); // 法线朝向。
    return lightningEffect * lightningLight * ndotl; // 最终闪电。
}

// 闪电照亮体积云：只按距离衰减。
vec3 ogxEclipseLightningCloud(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0) return vec3(0.0); // 没有闪电。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 400.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -10.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 闪电照亮体积雾：只在闪电强度大于一时生效。
vec3 ogxEclipseLightningFog(vec3 feetPlayerPos, vec4 boltPosition, vec3 lightningEffect)
{
    if (boltPosition.w <= 0.0 || boltPosition.w < 1.0) return vec3(0.0); // 弱闪电不照雾。
    vec3 lightningPos = feetPlayerPos - vec3(boltPosition.x, clamp(feetPlayerPos.y, boltPosition.y, boltPosition.y + 116.0), boltPosition.z); // 相对位置。
    float lightningLight = max(1.0 - length(lightningPos) / 150.0, 0.0); // 线性衰减。
    lightningLight = exp((1.0 - lightningLight) * -15.0); // 指数重整。
    return lightningEffect * lightningLight; // 交回闪电色。
}

// 末地光源位置：闪电位置吸到两百格网格，再按体积权重混向中心光柱。
vec3 ogxEclipseLightSourcePosition(vec3 worldPos, vec3 cameraPos, float vortexBounds, vec3 manualLightPos,
    vec3 randomOffset, bool theOrb)
{
    vec3 vortexPos = worldPos - vec3(0.0, 200.0, 0.0); // 中心光柱。
    vec3 lightningPos = worldPos - cameraPos - manualLightPos; // 闪电光。
    float cellSize = 200.0; // 网格大小。
    lightningPos += fract(cameraPos / cellSize) * cellSize - cellSize * 0.5; // 吸到网格。
    lightningPos -= randomOffset * 2.5; // 随机偏移。
    if (theOrb) return lightningPos; // 宝珠模式只看闪电位置。
    return mix(lightningPos, vortexPos, vortexBounds); // 按体积混合。
}

// 末地光源颜色：闪电色与光柱色按体积权重混合。
vec3 ogxEclipseLightSourceColors(float vortexBounds, float lightningflash, vec3 vortexColor, vec3 lightningColor,
    vec3 orbColor, float orbMult, bool theOrb)
{
    vec3 lightning = lightningColor * lightningflash; // 闪电色按强度缩放。
    if (theOrb) return orbColor * orbMult; // 宝珠模式。
    return mix(lightning, vortexColor, vortexBounds); // 按体积混合。
}

// Frisvad 切线基：由法线直接构造两个正交切向，避免叉乘退化。
mat3 ogxEclipseFrisvad(vec3 n)
{
    vec3 f; // 第一切向。
    vec3 r; // 第二切向。
    if (n.z < -0.9) // 法线接近负 z 时用固定基，避免除以接近零的数。
    {
        f = vec3(0.0, -1.0, 0.0);
        r = vec3(-1.0, 0.0, 0.0);
    }
    else
    {
        float a = 1.0 / (1.0 + n.z); // 参考实现的比例。
        float b = -n.x * n.y * a; // 交叉项。
        f = vec3(1.0 - n.x * n.x * a, b, -n.x);
        r = vec3(b, 1.0 - n.y * n.y * a, -n.y);
    }
    return mat3(f, r, n); // 三列依次是切向、副切向、法线。
}

// 可见法线 GGX 采样：把视线压到半球椭球，再采一个半程方向。
vec3 ogxEclipseSampleVndfGgx(vec3 viewerDirection, float alpha, vec2 xy)
{
    viewerDirection = normalize(vec3(alpha * 0.5 * viewerDirection.xy, viewerDirection.z)); // 压到半球配置。
    const float tau = 6.2831853; // 参考实现的两倍圆周。
    float phi = tau * xy.x; // 采样角。
    float cosTheta = (1.0 - xy.y) * (1.0 + viewerDirection.z) - viewerDirection.z; // 余弦。
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0)); // 正弦。
    sinTheta = clamp(sinTheta, 0.0, 1.0); // 参考实现的钳制。
    cosTheta = clamp(cosTheta, sinTheta * 0.5, 1.0); // 参考实现的钳制。
    vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta); // 反射方向。
    vec3 halfway = reflected + viewerDirection; // 半程方向。
    return normalize(vec3(alpha * halfway.xy, halfway.z)); // 回到椭球配置。
}

// Eclipse 的 GGX：粗糙度先取 2.5 次方，再算 D、F 与可见性。
vec3 ogxEclipseGgx(vec3 n, vec3 v, vec3 l, float r, vec3 f0, vec3 metalAlbedoTint)
{
    r = max(pow(r, 2.5), 0.0001); // 粗糙度重整与下限。
    vec3 h = normalize(l + v); // 半程方向。
    float hn = inversesqrt(dot(h, h)); // 半程长度倒数。
    float dotLH = clamp(dot(h, l) * hn, 0.0, 1.0); // 半程与光。
    float dotNH = clamp(dot(h, n) * hn, 0.0, 1.0); // 半程与法线。
    float dotNL = clamp(dot(n, l), 0.0, 1.0); // 法线与光。
    float dotNHsq = dotNH * dotNH; // 平方。
    float denom = dotNHsq * r - dotNHsq + 1.0; // 分母。
    float d = r / (3.141592653589793 * denom * denom); // 法线分布。
    vec3 f = (f0 + (1.0 - f0) * exp2((-5.55473 * dotLH - 6.98316) * dotLH)) * metalAlbedoTint; // 菲涅耳。
    float k2 = 0.25 * r; // 可见性系数。
    return dotNL * d * f / (dotLH * dotLH * (1.0 - k2) + k2); // 合成高光。
}

// Eclipse 的粗糙度菲涅耳：按粗糙度调整曲线与亮度。
float ogxEclipseShlickFresnelRoughness(float xDotN, float roughness)
{
    float shlickFresnel = clamp(1.0 + xDotN, 0.0, 1.0); // 基础菲涅耳。
    float curves = exp(-4.0 * pow(1.0 - roughness, 2.5)); // 曲线权重。
    float brightness = exp(-3.0 * pow(1.0 - sqrt(roughness), 3.50)); // 亮度权重。
    shlickFresnel = pow(1.0 - pow(1.0 - shlickFresnel, mix(1.0, 1.9, curves)), mix(5.0, 2.6, curves)); // 曲线重整。
    shlickFresnel = mix(0.0, mix(1.0, 0.065, brightness), clamp(shlickFresnel, 0.0, 1.0)); // 亮度重整。
    return shlickFresnel; // 交回菲涅耳。
}

// 体素平面求交：只接受落在两格以内且仍在同一格内的交点。
bool ogxEclipsePlaneIntersect(inout vec3 currPos, float worldOffset, inout vec3 voxelPos, vec3 reflectedVector,
    inout vec3 stepAxis, vec3 normal)
{
    float denom = dot(reflectedVector, normal); // 平面法线与射线。
    if (abs(denom) < 1e-6) return false; // 平行。
    float t = -(dot(currPos, normal) - worldOffset) / denom; // 交点参数。
    if (t > 0.0 && t < 2.0) // 只接受近处交点。
    {
        vec3 hitPos = currPos + t * reflectedVector; // 交点。
        if (all(equal(ivec3(voxelPos), ivec3(hitPos)))) // 仍在同一格。
        {
            currPos = hitPos;
            stepAxis = normal;
            return true;
        }
    }
    return false; // 没有有效交点。
}

// 体素包围盒求交：返回是否命中，并把位置推进到入口。
bool ogxEclipseAabbIntersection(inout vec3 currPos, vec3 reflectedVector, vec3 stepSizes, vec3 boxMin,
    vec3 boxMax, inout vec3 stepAxis)
{
    vec3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    vec3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    vec3 tmin = min(t1, t2); // 每轴入口。
    vec3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    vec3 entryDist = abs(tmin - vec3(tmin0)); // 哪一轴最先进入。
    vec3 normal = step(entryDist, vec3(0.0)); // 入口轴标记。
    stepAxis = mix(stepAxis, normal, fHit); // 命中时更新轴。
    currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return hit; // 交回命中。
}

// 体素采样螺旋：把样本序号变成单位圆上的螺旋点，2.26 是参考实现的关键常数。
vec2 ogxEclipseCleanVoxelSample(int samples, float totalSamples, float noise)
{
    float variance = noise * 0.897; // 每像素抖动。
    float variedSamples = float(samples) + variance; // 抖动后的样本号。
    float spiralShape = sqrt(variedSamples / (totalSamples + variance)); // 半径。
    float shape = 2.26; // 参考实现的关键旋转系数。
    float theta = variedSamples * (OGX_PI * shape); // 角度。
    return vec2(cos(theta) * spiralShape, sin(theta) * spiralShape); // 螺旋点。
}

#endif

/*
生成文件：Eclipse 天空模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 天空模块：太阳与月亮圆盘、球面投影、三次纹理采样、天空盒查表、大气积分与极光。
调用位置：需要复现 Eclipse `sky_gradient.glsl`、`ROBOBO_sky.glsl` 与 `aurora.glsl` 的天空程序；
    Minecraft 光影由 `/omni-gfx/eclipse_sky.glsl` 引入，当前只由严格 profile 与独立测试消费。
可复制示例：
    vec3 sun = ogxEclipseDrawSun(dot(viewDir, sunDir), sunlightColor);
    vec2 uv = ogxEclipseSphereMap(screenUv);
    vec3 sky = ogxEclipseCalculateAtmosphere(background, viewDir, up, sunDir, moonDir,
        eyeAltitude, cameraY, sunColor, moonColor, 32, noise, 6000.0, true, true, false,
        rayleigh, mie, ozone, pid, transmittance);
设计原因与取舍：
    参考实现直接读 `texelSize`、`cameraPosition`、`worldShadowVector` 与一堆菜单宏。库把纹理尺寸、
    相机高度、光方向、系数与开关全部改成显式参数；公式、常数、循环次数与采样顺序保持不变。
    这样同一套天空可以用于独立测试世界、严格 profile 与 Minecraft，而库本身不读取宿主状态。
    纹理函数只接收采样器与尺寸，不绑定缓冲编号；调用方决定把哪张图放在哪个槽位。
*/
#ifndef OGX_ECLIPSE_SKY_INCLUDED
#define OGX_ECLIPSE_SKY_INCLUDED

// 数学提供圆周率、夹紧与黑体色；大气提供射线求交与相函数。


// Eclipse 太阳圆盘：按视方向与太阳方向的余弦算柔边，再乘太阳颜色与固定亮度。
vec3 ogxEclipseDrawSun(float cosY, vec3 sunlight)
{
    return sunlight / 0.0008821203 * pow(smoothstep(cos(0.0093084168595 * 3.2), cos(0.0093084168595 * 2.2), cosY), 3.0) * 0.62; // 常数与参考实现逐项相同。
}

// Eclipse 球面屏幕映射：把正方形屏幕的每一个点投到球面经纬度。
// 圆外返回零：调用方读到的贴图坐标落在左上角，不会越界采样。
vec2 ogxEclipseSphereMap(vec2 uv)
{
    vec2 position = 2.0 * uv - 1.0; // 屏幕坐标转负一到一。
    float radius = dot(position, position); // 到中心的距离平方。
    if (radius > 1.0) return vec2(0.0); // 圆外没有球面方向。
    float z = sqrt(1.0 - radius); // 球面上的第三分量。
    float longitude = atan(position.x, z); // 经度。
    float latitude = acos(position.y); // 纬度。
    float u = (longitude + OGX_PI) / (2.0 * OGX_PI); // 经度映射到零到一。
    float v = latitude / OGX_PI; // 纬度映射到零到一。
    return vec2(u, v); // 交回贴图坐标。
}

// Eclipse 默认月亮：一个很小的软圆盘，并压暗它后面的星星。
// `occludeStars` 是输入输出参数：月亮越亮，返回时星星遮罩越小。
vec3 ogxEclipseDrawMoon(vec3 playerPos, vec3 worldSunVec, vec3 color, inout float occludeStars)
{
    float shape = min(max(dot(worldSunVec, playerPos) - 0.9994, 0.0) / (1.0 - 0.9994), 1.0); // 月亮圆盘的软边。
    occludeStars *= max(1.0 - shape * 5.0, 0.0); // 圆盘附近遮住星星。
    return shape * color * 40.0; // 参考实现的月亮亮度。
}

// Eclipse 真实月亮：尺寸可调，边缘比默认月亮更软，星星遮挡更强。
vec3 ogxEclipseDrawRealMoon(vec3 playerPos, vec3 worldSunVec, vec3 color, inout float occludeStars, float size)
{
    float shape = min(max(dot(worldSunVec, playerPos) - size, 0.0) / (1.0 - size), 1.0); // 圆盘软边。
    shape = pow(shape, 0.15); // 参考实现的幂次让边缘更宽。
    occludeStars *= max(1.0 - shape * 50.0, 0.0); // 真实月亮遮住更多星星。
    return color / 750.0 * shape; // 参考实现的亮度缩放。
}

// 三次卷积权重：Catmull-Rom 核的四个分段，供双三次采样复用。
float ogxEclipseBicubicW0(float a) { return (1.0 / 6.0) * (a * (a * (-a + 3.0) - 3.0) + 1.0); }
float ogxEclipseBicubicW1(float a) { return (1.0 / 6.0) * (a * a * (3.0 * a - 6.0) + 4.0); }
float ogxEclipseBicubicW2(float a) { return (1.0 / 6.0) * (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0); }
float ogxEclipseBicubicW3(float a) { return (1.0 / 6.0) * (a * a * a); }
float ogxEclipseBicubicG0(float a) { return ogxEclipseBicubicW0(a) + ogxEclipseBicubicW1(a); }
float ogxEclipseBicubicG1(float a) { return ogxEclipseBicubicW2(a) + ogxEclipseBicubicW3(a); }
float ogxEclipseBicubicH0(float a) { return -1.0 + ogxEclipseBicubicW1(a) / (ogxEclipseBicubicW0(a) + ogxEclipseBicubicW1(a)); }
float ogxEclipseBicubicH1(float a) { return 1.0 + ogxEclipseBicubicW3(a) / (ogxEclipseBicubicW2(a) + ogxEclipseBicubicW3(a)); }

// Eclipse 双三次纹理采样：四个角各取一次双线性，再按卷积权重合成。
// `pixelSize` 是一像素的贴图坐标；参考实现把同样的值同时用作像素和倒数。
vec4 ogxEclipseBicubicTexture(sampler2D tex, vec2 uv, vec2 pixelSize)
{
    vec4 texelSize = vec4(pixelSize, 1.0 / pixelSize); // 与参考实现的局部变量同名同含义。
    uv = uv * texelSize.zw; // 换到像素坐标。
    vec2 iuv = floor(uv); // 整数部分。
    vec2 fuv = fract(uv); // 小数部分。
    float g0x = ogxEclipseBicubicG0(fuv.x); // 横轴左权重。
    float g1x = ogxEclipseBicubicG1(fuv.x); // 横轴右权重。
    float h0x = ogxEclipseBicubicH0(fuv.x); // 横轴左偏移。
    float h1x = ogxEclipseBicubicH1(fuv.x); // 横轴右偏移。
    float h0y = ogxEclipseBicubicH0(fuv.y); // 纵轴上偏移。
    float h1y = ogxEclipseBicubicH1(fuv.y); // 纵轴下偏移。
    vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - 0.5) * texelSize.xy; // 左上样本。
    vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - 0.5) * texelSize.xy; // 右上样本。
    vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - 0.5) * texelSize.xy; // 左下样本。
    vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - 0.5) * texelSize.xy; // 右下样本。
    return ogxEclipseBicubicG0(fuv.y) * (g0x * textureLod(tex, p0, 0.0) + g1x * textureLod(tex, p1, 0.0))
         + ogxEclipseBicubicG1(fuv.y) * (g0x * textureLod(tex, p2, 0.0) + g1x * textureLod(tex, p3, 0.0)); // 参考实现的合成顺序。
}

// 带圆形噪声偏移的双三次采样：用于体积云或天空盒旋转采样。
vec4 ogxEclipseBicubicTextureOffset(sampler2D tex, vec2 uv, float noise, float scale, vec2 pixelSize)
{
    float offsets = noise * (2.0 * OGX_PI); // 噪声转角度。
    vec2 circleOffsets = vec2(sin(offsets), cos(offsets)) * scale; // 单位圆偏移。
    vec4 texelSize = vec4(pixelSize, 1.0 / pixelSize); // 与参考实现相同的局部变量。
    uv = (uv + texelSize.xy) * texelSize.zw; // 先加一像素再换到像素坐标。
    vec2 iuv = floor(uv + circleOffsets); // 整数部分加偏移。
    vec2 fuv = fract(uv + circleOffsets); // 小数部分加偏移。
    float g0x = ogxEclipseBicubicG0(fuv.x); // 横轴左权重。
    float g1x = ogxEclipseBicubicG1(fuv.x); // 横轴右权重。
    float h0x = ogxEclipseBicubicH0(fuv.x); // 横轴左偏移。
    float h1x = ogxEclipseBicubicH1(fuv.x); // 横轴右偏移。
    float h0y = ogxEclipseBicubicH0(fuv.y); // 纵轴上偏移。
    float h1y = ogxEclipseBicubicH1(fuv.y); // 纵轴下偏移。
    vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - 0.5) * texelSize.xy; // 左上样本。
    vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - 0.5) * texelSize.xy; // 右上样本。
    vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - 0.5) * texelSize.xy; // 左下样本。
    vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - 0.5) * texelSize.xy; // 右下样本。
    return ogxEclipseBicubicG0(fuv.y) * (g0x * textureLod(tex, p0, 0.0) + g1x * textureLod(tex, p1, 0.0))
         + ogxEclipseBicubicG1(fuv.y) * (g0x * textureLod(tex, p2, 0.0) + g1x * textureLod(tex, p3, 0.0)); // 与不带偏移版相同的合成顺序。
}

// Eclipse 球面方向转等距柱状坐标：经度用负方向，纬度用高度角。
vec2 ogxEclipseSphereToCarte(vec3 dir)
{
    float lonlat = clamp(atan(-dir.x, -dir.z), -OGX_PI, OGX_PI); // 经度。
    return vec2(lonlat * (0.5 / OGX_PI) + 0.5, asin(dir.y) * (1.0 / OGX_PI) + 0.5); // 映射到零到一。
}

// Eclipse 天空盒查表：先转经纬度，再压到天空盒左上角的一块 256 像素区域。
vec3 ogxEclipseSkyFromTex(vec3 pos, sampler2D tex, vec2 pixelSize)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 clampUV = vec2(1.0); // 允许的最大范围。
    p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5; // 压缩到合法范围。
    return textureLod(tex, p * pixelSize * 256.0 + vec2(18.5, 1.5) * pixelSize, 0.0).rgb; // 固定偏移与缩放。
}

// Eclipse 云层查表：从天空盒右侧的云图取颜色。
vec4 ogxEclipseSkyCloudsFromTex(vec3 pos, sampler2D tex, vec2 pixelSize)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 uv = clamp(p, 0.0, 1.0) * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图偏移。
    return textureLod(tex, uv, 0.0); // 双线性采样。
}

// Eclipse 模糊云层查表：接口保留 `scaler`，参考实现当前没有使用它。
vec4 ogxEclipseSkyCloudsFromTexBlur(vec3 pos, sampler2D tex, vec2 pixelSize, float scaler)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    vec2 scaleA = pixelSize * 256.0; // 天空盒区域缩放。
    vec2 scaleB = vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图偏移。
    vec2 uv = clamp(p, 0.0, 1.0) * scaleA + scaleB; // 与参考实现相同的采样位置。
    return textureLod(tex, uv, 0.0); // `scaler` 在原程序里也未参与计算。
}

// Eclipse 带粗糙度的云层查表：越粗糙，天顶附近的云越向中心压缩。
vec4 ogxEclipseSkyCloudsFromTexLod(vec3 pos, sampler2D tex, vec2 pixelSize, float roughness)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    roughness = 1.0 - pow(1.0 - roughness, 3.0); // 参考实现的粗糙度重整。
    float y = min(max(p.y - 0.5, 0.0) * 50.0, 1.0); // 只在天顶附近生效。
    p = mix(p, (p - 0.5) * (1.0 - roughness) + 0.5, y); // 向中心压缩。
    vec2 clampUV = vec2(1.0); // 合法范围。
    p = clamp(p * 2.0 - 1.0, -clampUV, clampUV) * 0.5 + 0.5; // 压缩到合法范围。
    vec2 uv = p * pixelSize * 256.0 + vec2(18.5 + 257.0, 1.5) * pixelSize; // 云图坐标。
    return textureLod(tex, uv, 0.0); // 双线性采样。
}

// Eclipse 体积雾查表：从天空盒中间偏右的区域取体积雾颜色。
vec4 ogxEclipseVolumetricsFromTex(vec3 pos, sampler2D tex, vec2 pixelSize, float lod)
{
    vec2 p = ogxEclipseSphereToCarte(pos); // 球面坐标。
    p = clamp(p, 0.0, 1.0); // 夹到合法范围。
    vec2 uv = p * pixelSize * 256.0 + vec2(256.0 - 256.0 * 0.12, 1.5) * pixelSize; // 体积雾区域偏移。
    return textureLod(tex, uv, lod); // 按粗糙度取层级。
}

// Eclipse 大气积分：沿视线固定步数积分瑞利、米氏与臭氧，输出日月散射与透过率。
// `pid` 返回行星交点参数，`transmittance` 返回视线透过率；两个输出都与参考实现相同。
vec3 ogxEclipseCalculateAtmosphere(vec3 background, vec3 viewVector, vec3 upVector, vec3 sunVector,
    vec3 moonVector, float eyeAltitude, float cameraY, vec3 sunColorBase, vec3 moonColorBase,
    vec3 coefficientRayleigh, vec3 coefficientMie, vec3 coefficientOzone,
    int iSteps, float noise, float groundReferenceHeight, bool skyGround, bool customMoonRotation,
    bool twilightForest, out vec2 pid, out vec3 transmittance)
{
    const int jSteps = 4; // 太阳与月亮阴影的固定步数。
    const float planetRadius = 6731e3; // 行星半径，米。
    const float atmosphereRadius = planetRadius + 110e3; // 大气顶半径。
    const float atmosphereRadiusSquared = atmosphereRadius * atmosphereRadius; // 大气顶半径平方。
    const vec2 scaleHeights = vec2(8.0e3, 1.2e3); // 瑞利与米氏标高。
    const vec2 inverseScaleHeights = 1.0 / scaleHeights; // 标高倒数。
    const vec2 scaledPlanetRadius = planetRadius * inverseScaleHeights; // 参考实现的缩放半径。

    float planetGround; // 行星地面在地平线附近的暗化。
    if (skyGround) // 使用与参考实现相同的云层参考高度暗化。
    {
        float heightRelativeToClouds = clamp(1.0 - max(cameraY - groundReferenceHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层高度。
        planetGround = mix(exp(-1.0 * pow(max(-viewVector.y * 10.0 + 0.1, 0.0), 2.0)),
            exp(-100.0 * pow(max(-viewVector.y * 5.0 + 0.1, 0.0), 2.0)), heightRelativeToClouds); // 两段指数的混合。
    }
    else
    {
        planetGround = pow(clamp(viewVector.y + 1.0, 0.0, 1.0), 2.0); // 没有云层时直接按视线高度压暗。
    }
    float groundDarkening = max(planetGround * 0.7 + 0.3, clamp(sunVector.y * 2.0, 0.0, 1.0)); // 地面与太阳高度的较大者。

    vec3 viewPos = (planetRadius + 1.0 + max(eyeAltitude - 300.0, 0.0)) * upVector; // 相机在大气里的位置。

    vec2 atmosphereHit = ogxRaySphereIntersection(viewPos, viewVector, atmosphereRadius); // 求大气顶交点。
    float atmosphereNear = atmosphereHit.x; // 到大气顶交点的近参数。
    float atmosphereFar = atmosphereHit.y; // 到大气顶交点的远参数。
    if (atmosphereFar < 0.0) // 视线完全离开大气。
    {
        transmittance = vec3(1.0); // 没有大气就没有衰减。
        pid = vec2(0.0); // 没有行星交点。
        return vec3(0.0); // 天空是黑的。
    }

    vec2 planetHit = ogxRaySphereIntersection(viewPos, viewVector, planetRadius * 0.998); // 求行星交点。
    float planetNear = planetHit.x; // 行星交点的近参数。
    float planetFar = planetHit.y; // 行星交点的远参数。
    bool planetIntersected = planetFar > 0.0; // 是否撞到行星。
    pid = vec2(planetNear, planetFar); // 返回行星交点参数。

    vec2 stepRange = vec2((planetIntersected && planetNear < 0.0) ? planetFar : max(atmosphereNear, 0.0),
        (planetIntersected && planetNear > 0.0) ? planetNear : atmosphereFar); // 参考实现的可见段。
    float stepSize = (stepRange.y - stepRange.x) * (1.0 / float(iSteps)); // 每步长度。
    vec3 increment = viewVector * stepSize; // 每步位移。
    vec3 position = viewVector * stepRange.x + viewPos; // 起点。
    position += increment * (0.34 * noise); // 抖动起点。

    vec2 phaseSun = ogxEclipseSkyPhase(dot(viewVector, sunVector), 0.8); // 太阳相函数。
    vec2 phaseMoon = ogxEclipseSkyPhase(dot(viewVector, moonVector), 0.8); // 月亮相函数。

    if (customMoonRotation) // 自定义月亮轨道会算月食暗化。
    {
        float eclipseDarkness = smoothstep(0.005, 0.08, length(sunVector - moonVector)); // 日月距离。
        phaseSun *= mix(1.0, eclipseDarkness, smoothstep(-1.0, 0.175, viewVector.y)); // 低空暗化更强。
    }

    vec3 scatteringSun = vec3(0.0); // 太阳散射。
    vec3 scatteringMoon = vec3(0.0); // 月亮散射。
    vec3 scatteringAmbient = vec3(0.0); // 环境散射。
    transmittance = vec3(1.0); // 视线透过率从全通开始。

    float highSun = clamp(pow(sunVector.y + 0.6, 5.0), 0.0, 1.0) * 3.0; // 高空太阳让日出少一点蓝。
    float lowSun = clamp(((1.0 - abs(sunVector.y)) * 3.0) - highSun, 1.0, 2.0); // 低空太阳让日落更蓝。

    if (twilightForest) lowSun = 2.5; // 暮色森林固定值，与参考实现相同。

    for (int i = 0; i < iSteps; ++i, position += increment) // 逐段积分。
    {
        vec3 density = ogxEclipseSkyDensity(length(position), planetRadius, scaleHeights); // 三种介质密度。
        if (density.y > 1e35) break; // 数值爆掉时提前停止。
        vec3 stepAirmass = density * stepSize; // 本段光学路径。
        vec3 stepOpticalDepth = coefficientRayleigh * stepAirmass.x + coefficientMie * stepAirmass.y + coefficientOzone * stepAirmass.z; // 本段光学厚度。
        vec3 stepTransmittance = exp2(-stepOpticalDepth / log(2.0)); // 本段透过率。
        vec3 stepTransmittedFraction = clamp((stepTransmittance - 1.0) / -stepOpticalDepth, 0.0, 1.0); // 本段可散射比例。
        vec3 stepScatteringVisible = transmittance * stepTransmittedFraction; // 可见散射。

        vec3 sunAirmass = ogxEclipseSkyAirmassRay(position, sunVector, float(jSteps), planetRadius, scaleHeights, atmosphereRadius); // 到太阳的三种介质路径。
        vec3 moonAirmass = ogxEclipseSkyAirmassRay(position, moonVector, float(jSteps), planetRadius, scaleHeights, atmosphereRadius); // 到月亮的三种介质路径。
        vec3 sunOpticalDepth = coefficientRayleigh * sunAirmass.x + coefficientMie * sunAirmass.y + coefficientOzone * sunAirmass.z; // 到太阳的光学厚度。
        vec3 moonOpticalDepth = coefficientRayleigh * moonAirmass.x + coefficientMie * moonAirmass.y + coefficientOzone * moonAirmass.z; // 到月亮的光学厚度。

        vec3 sunScattering = coefficientRayleigh * stepAirmass.x * phaseSun.x + coefficientMie * stepAirmass.y * phaseSun.y; // 太阳瑞利与米氏散射。
        vec3 moonScattering = coefficientRayleigh * stepAirmass.x * phaseMoon.x + coefficientMie * stepAirmass.y * phaseMoon.y; // 月亮瑞利与米氏散射。
        if (skyGround) // 参考实现的天空地面分支只影响太阳项。
        {
            scatteringSun += sunScattering * stepScatteringVisible * exp2(-sunOpticalDepth / log(2.0)) * planetGround;
        }
        else
        {
            scatteringSun += sunScattering * stepScatteringVisible * exp2(-sunOpticalDepth / log(2.0));
        }
        scatteringMoon += moonScattering * stepScatteringVisible * exp2(-moonOpticalDepth / log(2.0));
        scatteringAmbient += (coefficientRayleigh * stepAirmass.x + coefficientMie * stepAirmass.y) * stepScatteringVisible * lowSun;
        transmittance *= stepTransmittance; // 累积透过率。
    }

    return scatteringAmbient * background + scatteringSun * sunColorBase + scatteringMoon * moonColorBase * 0.5; // 参考实现的合成。
}

// Eclipse 极光哈希：一维输入打散成零到一。
float ogxEclipseAuroraHash(float p)
{
    p = fract(p * 0.1031); // 先压到小数。
    p *= p + 33.33; // 二次项。
    p *= p + p; // 再乘两倍。
    return fract(p); // 取小数。
}

// 极光二维旋转矩阵。
mat2 ogxEclipseAuroraRotation(float angle)
{
    float c = cos(angle); // 余弦。
    float s = sin(angle); // 正弦。
    return mat2(c, s, -s, c); // 按参考实现的列顺序。
}

// 三角波：把任意输入压到零点零一到零点四九之间。
float ogxEclipseAuroraTri(float x)
{
    return clamp(abs(fract(x) - 0.5), 0.01, 0.49); // 参考实现的范围。
}

// 二维三角波对：第二分量是第一分量与纵轴再次组合。
vec2 ogxEclipseAuroraTri2(vec2 p)
{
    float triX = ogxEclipseAuroraTri(p.x); // 横向三角波。
    float triY = ogxEclipseAuroraTri(p.y); // 纵向三角波。
    return vec2(triX + triY, ogxEclipseAuroraTri(triX + p.y)); // 参考实现的组合。
}

// 行向量乘矩阵：GLSL 的 `p *= m` 是行向量约定，和常见的矩阵乘向量相反。
vec2 ogxEclipseAuroraRowMul(vec2 p, mat2 m)
{
    return vec2(m[0].x * p.x + m[1].x * p.y, m[0].y * p.x + m[1].y * p.y); // 按列展开，避免转置错误。
}

// 极光分形噪声：三层三角波，逐层缩放与旋转。
float ogxEclipseAuroraTriNoise2d(vec2 p, float time)
{
    float z = 1.8; // 第一层缩放。
    float z2 = 2.5; // 第二层缩放。
    float rz = 0.0; // 累加结果。
    p = ogxEclipseAuroraRowMul(p, ogxEclipseAuroraRotation(p.x * 0.06)); // 初始旋转。
    vec2 bp = p; // 备份坐标。
    mat2 rotation = ogxEclipseAuroraRotation(time * 0.06); // 时间旋转。
    mat2 m2 = mat2(0.95534, 0.29552, -0.29552, 0.95534); // 参考实现的固定旋转。
    for (int i = 0; i < 3; i++) // 三层。
    {
        vec2 dg = ogxEclipseAuroraTri2(bp * 1.75) * 0.75; // 三角波偏移。
        dg = ogxEclipseAuroraRowMul(dg, rotation); // 旋转偏移。
        p -= dg / z2; // 坐标扰动。
        bp *= 1.3; // 频率放大。
        z2 *= 0.45; // 下一层缩放。
        z *= 0.42; // 权重衰减。
        p *= 1.21 + (rz - 1.0) * 0.02; // 参考实现的比例。
        rz += ogxEclipseAuroraTri(p.x + ogxEclipseAuroraTri(p.y)) * z; // 累加一层。
        p = ogxEclipseAuroraRowMul(p, mat2(-0.95534, -0.29552, 0.29552, -0.95534)); // 参考实现的 `p *= -m2`。
    }
    return clamp(1.0 / pow(rz * 29.0, 1.6), 0.0, 0.55); // 参考实现的收尾。
}

// Eclipse 极光主体：沿视线取样，用三角噪声生成幕帘与颜色。
// `moonY`/`sunY` 决定月亮与太阳对极光的压制，`lut` 选择是否使用六倍步长。
vec3 ogxEclipseAurora(vec3 dir, int samples, float noise, float moonY, float sunY, float time,
    vec3 background, float amount, float brightness, vec3 auroraColor, bool moonLight, bool lut)
{
    vec3 col = vec3(0.0); // 幕帘累加。
    vec3 avgCol = vec3(0.0); // 平均色。
    float hash = 0.05 * noise; // 每像素抖动。
    float fade = dir.y * 2.0 + 0.4; // 高度淡出。
    float atmosphereGround = 1.0 - exp2(-50.0 * pow(clamp(dir.y + 0.025, 0.0, 1.0), 2.0)); // 地平线附近压暗。
    float mult = lut ? 6.0 : 3.0; // LUT 模式采样更疏。
    for (int i = 0; i < samples; i++) // 逐层幕帘。
    {
        float mI = mult * float(i); // 当前层高度。
        float of = hash * smoothstep(0.0, 12.0, mI); // 抖动。
        float pt = (0.8 + pow(mI, 1.4) * 0.0016) / fade - of; // 采样半径。
        vec3 bpos = pt * dir; // 采样位置。
        float rzt = ogxEclipseAuroraTriNoise2d(bpos.zx, time); // 三角噪声。
        vec3 col2 = (sin(auroraColor + mI * 0.063) * 0.5 + 0.5) * rzt; // 当前层颜色。
        avgCol = mix(avgCol, col2, 0.1); // 参考实现的滑动平均。
        col += avgCol * exp2(-mI * 0.05 - 2.5); // 高度衰减。
    }
    vec3 aurora = 14.5 * pow(col, vec3(1.45)); // 参考实现的强化曲线。
    if (moonLight) aurora *= smoothstep(0.1, 0.0, moonY); // 月亮模式下被月光压制。
    aurora *= smoothstep(0.0, -0.1, sunY); // 太阳升起后消失。
    return aurora * atmosphereGround * amount * brightness; // 叠加到背景。
}

#endif

/*
生成文件：iterationT 末地模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 iterationT 末地补充模块：末地星空、行星 BRDF、黑洞吸积盘与云影查表。
调用位置：需要复现 iterationT `EndSky.glsl` 与 `NUBIS.glsl` 的末地程序；Minecraft 光影由
    `/omni-gfx/itx_end.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    vec3 stars = ogxItxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);
    vec3 disc = ogxItxBlackHoleStars(color, rayDir, lightDir, 0.5, frameTime, true, true, sunVector, 1, noiseTex, 512.0);
    float shadow = ogxItxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);
设计原因与取舍：
    参考实现直接读 `frameTimeCounter`、`worldSunVector`、`STAR_TYPE` 与云噪声选项。库把时间、光方向、
    纹理和开关全部改成显式参数，公式、常数、循环次数和采样顺序保持不变。
    噪点纹理只作为参数传入，库不假设它绑定在哪个缓冲；这样末地星空能独立测试，也能在光影里换槽位。
*/
#ifndef OGX_ITX_END_INCLUDED
#define OGX_ITX_END_INCLUDED

// 数学提供旋转、黑体色与夹紧；雾提供三维噪声与分形云；云提供顶部曲线；行星提供曲面曲线。




// iterationT 末地星空：按天球格子取哈希星点，星色用黑体温度。
// `starType` 为零时由调用方决定是否叠加；本函数只负责算出星点。
vec3 ogxItxEndStars(vec3 worldDir, vec3 worldSunVector, float time, int starType, float brightness, float amount)
{
    float angleY = time * 0.001; // 星空缓慢自转。
    mat3 eyeRotationY = mat3(cos(angleY), 0.0, sin(angleY),
                                     0.0, 1.0, 0.0,
                                     -sin(angleY), 0.0, cos(angleY)); // 绕纵轴旋转。
    worldDir = ogxMatrix3MulPoint(eyeRotationY, worldDir); // 转到星空坐标。
    const float scale = 384.0; // 星点密度。
    const float coverage = 0.007; // 星点覆盖率。
    const float maxLuminance = 0.04; // 单颗星最大亮度。
    const float minTemperature = 4000.0; // 最低色温。
    const float maxTemperature = 8000.0; // 最高色温。
    float cosine = dot(worldSunVector, vec3(0.0, 0.0, 1.0)); // 绕日轴对齐。
    vec3 axis = cross(worldSunVector, vec3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 轴长度倒数平方。
    worldDir = cosine * worldDir + cross(axis, worldDir)
        + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 参考实现的球面旋转。
    vec3 p = worldDir * scale; // 放大到格子。
    vec3 i = floor(p); // 格子下标。
    vec3 f = p - i; // 格内偏移。
    float r = dot(f - 0.5, f - 0.5); // 到格中心距离平方。
    vec3 i3 = fract(i * vec3(443.897, 441.423, 437.195)); // 三维哈希。
    i3 += dot(i3, i3.yzx + 19.19); // 二次混合。
    vec2 hash = fract((i3.xx + i3.yz) * i3.zy); // 两个哈希值。
    hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 亮度曲线。
    float c = ogxRemapSaturate(hash.x, 1.0 - coverage, 1.0); // 覆盖率阈值。
    return maxLuminance * ogxRemapSaturate(r, 0.25, 0.0) * c * c * ogxBlackbody(mix(minTemperature, maxTemperature, hash.y)); // 星点亮度乘色温。
}

// iterationT 行星 BRDF：用 Chandrasekhar H 函数与 Lambert 曲线近似行星表面。
vec3 ogxItxPpss(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir, float s)
{
    float NdotL = dot(normal, lightDir); // 光线与法线。
    float NdotV = dot(normal, eyeDir); // 视线与法线。
    albedo *= ogxCurve01(ogxSaturate(NdotL)); // 参考实现的曲线。
    vec3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 双向反射。
    return ogxSaturate(color); // 夹到合法范围。
}

// 黑洞吸积盘主函数：沿射线步进，累计盘面自发光与遮挡。
// `detailAlongLongitude`、`doppler` 与 `starType` 对应参考实现的三个菜单开关。
vec3 ogxItxBlackHoleStars(vec3 color, vec3 rayDir, vec3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, vec3 worldSunVector, int starType,
    sampler2D noiseTexture, float noiseResolution)
{
    const float steps = 50.0; // 固定步数。
    const float rSteps = 1.0 / steps; // 步数倒数。
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 盘半径。
    const float discWidth = 3.5; // 盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内缘。
    const float discOuter = discRadius + discWidth * 0.5; // 外缘。
    vec3 eye = -lightDir * 8.0; // 相机位置。
    vec3 rayPos = eye + rayDir * 3.0; // 起点。
    mat3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 固定盘面旋转。
    vec3 result = vec3(0.0); // 盘面颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 抖动起点。
    for (int i = 0; i < int(steps); i++) // 固定步数。
    {
        if (transmittance < 0.0001) break; // 全遮挡就停。
        ogxWarpSpace(rayDir, rayPos); // 空间扭曲。
        rayPos += rayDir * stepLength; // 前进一步。
        vec3 discPos = ogxMatrix3MulPoint(rotation, rayPos); // 盘面坐标。
        float r = length(discPos); // 半径。
        float p = ogxAtan2(vec2(-discPos.z, -discPos.x)); // 方位角。
        float h = discPos.y; // 高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向渐变。
        float dist = abs(h); // 到盘面的距离。
        float discThickness = 0.1 * radialGradient; // 盘厚度。
        float fr = abs(r - discInner) + 0.4; // 内缘距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 远处淡出。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 盘面辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 厚度内可见。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxEndSkyPCurve(radialGradient); // 径向曲线。
        float density = dr; // 密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 厚度衰减。
        density = ogxSaturate(density * 0.7); // 参考实现的强度。
        density = ogxSaturate(density + bloomFactor * 0.1); // 辉光贡献。
        if (density > 0.0001) // 只有足够密才发光。
        {
            vec3 discCoord = detailAlongLongitude
                ? vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5
                : vec3(r, 0.0, h * 0.1) * 3.5; // 经度细节开关。
            vec3 shift = detailAlongLongitude ? time * vec3(0.1, 0.07, 0.0) : time * vec3(0.03, 0.05, 0.0); // 流动方向。
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, noiseResolution); // 参考实现的分形云。
            fbm = fbm * fbm; // 平方。
            fbm = fbm * fbm; // 四次方。
            density *= fbm * dr; // 细节乘回密度。
            float gr = 1.0 - radialGradient; // 外缘渐变。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 外缘辉光强度。
            vec3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 黑体色乘强度。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应。
            float stepTransmittance = exp2(-density * 7.0); // 本段透过率。
            float integral = 1.0 - stepTransmittance; // 本段吸收。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 累积发光。
        }
        vec2 t = vec2(1.0, 0.01); // 圆环参数。
        float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        vec3 col = ogxBlackbody(12000.0); // 高温蓝白。
        bloomDisc *= step(0.5, r); // 内圈不发光。
        result += col * bloomDisc * 0.1 * transmittance; // 叠加圆环。
    }
    result *= rSteps; // 步长归一化。
    if (starType > 0) color += ogxItxEndStars(rayDir, worldSunVector, time, starType, 1.0, 1.0); // 参考实现的星空叠加。
    color *= transmittance; // 盘面遮挡背景。
    return color + result; // 最终颜色。
}

// 黑洞吸积盘反射版：步数更少，细节权重与主函数不同。
vec3 ogxItxBlackHoleReflection(vec3 color, vec3 rayDir, vec3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, sampler2D noiseTexture, float noiseResolution)
{
    const float steps = 30.0; // 反射只走三十步。
    const float rSteps = 1.0 / steps; // 步数倒数。
    const float stepLength = 0.2; // 每步长度。
    const float discRadius = 2.25; // 盘半径。
    const float discWidth = 3.5; // 盘宽度。
    const float discInner = discRadius - discWidth * 0.5; // 内缘。
    vec3 eye = -lightDir * 8.0; // 相机位置。
    vec3 rayPos = eye + rayDir * 4.0; // 起点更远。
    mat3 rotation = ogxRotateMatrix(0.1, 0.0, -0.35); // 固定盘面旋转。
    vec3 result = vec3(0.0); // 盘面颜色。
    float transmittance = 1.0; // 透过率。
    rayPos += rayDir * stepLength * noise; // 抖动起点。
    for (int i = 0; i < int(steps); i++) // 固定步数。
    {
        if (transmittance < 0.0001) break; // 全遮挡就停。
        ogxWarpSpace(rayDir, rayPos); // 空间扭曲。
        rayPos += rayDir * stepLength; // 前进一步。
        vec3 discPos = ogxMatrix3MulPoint(rotation, rayPos); // 盘面坐标。
        float r = length(discPos); // 半径。
        float p = ogxAtan2(vec2(-discPos.z, -discPos.x)); // 方位角。
        float h = discPos.y; // 高度。
        float radialGradient = 1.0 - ogxSaturate((r - discInner) / discWidth * 0.5); // 径向渐变。
        float dist = abs(h); // 到盘面距离。
        float discThickness = 0.1 * radialGradient; // 盘厚度。
        float fr = abs(r - discInner) + 0.4; // 内缘距离。
        fr = fr * fr; // 平方。
        float fade = fr * fr * 0.04; // 远处淡出。
        float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 盘面辉光。
        bloomFactor *= ogxSaturate(2.0 - abs(dist) / discThickness); // 厚度内可见。
        bloomFactor = bloomFactor * bloomFactor; // 平方增强。
        float dr = ogxEndSkyPCurve(radialGradient); // 径向曲线。
        float density = dr; // 密度。
        density *= ogxSaturate(1.0 - abs(dist) / discThickness); // 厚度衰减。
        density = ogxSaturate(density * 0.7); // 参考实现的强度。
        density = ogxSaturate(density + bloomFactor * 0.1); // 辉光贡献。
        if (density > 0.0001) // 只有足够密才发光。
        {
            vec3 discCoord = detailAlongLongitude
                ? vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5
                : vec3(r, 0.0, h * 0.1) * 3.5; // 经度细节开关。
            vec3 shift = detailAlongLongitude ? time * vec3(0.1, 0.07, 0.0) : time * vec3(0.03, 0.05, 0.0); // 流动方向。
            float fbm = ogxCloudFbm(discCoord, shift, noiseTexture, noiseResolution); // 参考实现的分形云。
            float fbm2 = fbm * fbm; // 平方。
            density *= fbm2 * fbm2 * fbm; // 五次方权重。
            density *= dr; // 乘径向曲线。
            float gr = 1.0 - radialGradient; // 外缘渐变。
            gr = gr * gr; // 平方。
            float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 外缘辉光强度。
            vec3 glow = ogxBlackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 黑体色乘强度。
            if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应。
            float stepTransmittance = exp2(-density * 7.0); // 本段透过率。
            float integral = 1.0 - stepTransmittance; // 本段吸收。
            transmittance *= stepTransmittance; // 累积透过率。
            result += integral * transmittance * glow; // 累积发光。
        }
        vec2 t = vec2(1.0, 0.01); // 圆环参数。
        float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
        float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
        vec3 col = ogxBlackbody(12000.0); // 高温蓝白。
        bloomDisc *= step(0.5, r); // 内圈不发光。
        result += col * bloomDisc * 0.1 * transmittance; // 叠加圆环。
    }
    result *= rSteps; // 步长归一化。
    color *= transmittance; // 盘面遮挡背景。
    return color + result; // 最终颜色。
}

// 云影密度函数的提前声明：云影查表会先调用它，定义放在文件末尾。
vec3 ogxItxCloudShadowDensity(vec4 cloudPos, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, vec3 windDirection);

// iterationT 云影查表：按太阳方向在云层高度取样两次，取较大密度后做指数衰减。
// `baseNoise` 是云形状噪声；`coverage` 与 `wetness` 由调用方按菜单填写。
float ogxItxCloudShadowTex(vec2 coord, vec2 cloudAltitude, vec3 windDirection, vec2 cameraXZ,
    vec3 worldShadowVector, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float shadowRange)
{
    coord = coord * shadowRange - shadowRange * 0.5; // 屏幕坐标转云影范围。
    vec4 checkPos = vec4(coord.x + cameraXZ.x, 0.0, coord.y + cameraXZ.y, 0.0); // 云影起点。
    float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
    checkPos += vec4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y), 0.25); // 沿太阳方向抬到云层。
    vec3 density = ogxItxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection); // 第一次取样。
    checkPos += vec4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y), 0.25); // 再抬四分之一层。
    density = max(density, ogxItxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection)); // 第二次取样。
    return exp2(-density.y * 20.0); // 参考实现的云影衰减。
}

// 云影密度：只算基础形状，不算细节层，和参考实现的 `sampleDetail=false` 一致。
vec3 ogxItxCloudShadowDensity(vec4 cloudPos, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, vec3 windDirection)
{
    vec4 baseSample = textureLod(baseNoise, cloudPos.xyz * baseScale + windDirection * 10.0, 0.0); // 基础噪声。
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2; // 三层混合。
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0); // 按形状重置。
    float shapeCurve = ogxCloudTopCurve(ogxSaturate(1.0 - cloudPos.w)) * 0.5; // 顶部曲线。
    shapeCurve += ogxCurve01(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 底部曲线。
    baseDensity *= shapeCurve; // 乘形状。
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 底部权重。
    baseDensity *= mix(1.0, ogxCloudTopCurve(ogxSaturate(cloudPos.w * 3.0)), wetness); // 雨天改顶部曲线。
    float coverageNoise = textureLod(baseNoise, cloudPos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + windDirection + coverageOffset, 0.0).x; // 覆盖噪声。
    float coverage = mix(clearCoverage, rainCoverage, wetness); // 晴雨覆盖。
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 覆盖阈值。
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0); // 覆盖裁剪。
    baseDensity *= ogxCurve01(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 密度控制。
    baseDensity *= ogxCloudTopCurve(ogxSaturate(cloudPos.w * 1.8)); // 顶部衰减。
    baseDensity = ogxSaturate(baseDensity); // 夹紧。
    return vec3(baseDensity); // 没有细节层。
}

#endif

/*
生成文件：Eclipse 间接光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 间接光模块：余弦半球采样、切线基、屏幕空间 GI、双边上采样与 SSGI 合成。
调用位置：需要复现 Eclipse `indirect_lighting_effects.glsl` 的程序；Minecraft 光影由
    `/omni-gfx/eclipse_indirect.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    vec3 dir = ogxEclipseTangentToWorld(normal, ogxEclipseCosineHemisphereSample(xi));
    vec3 hit = ogxEclipseRayTraceGi(rayDir, viewPos, dither, 5.0, nearPlane, farPlane, 1.0, depthTex, projection);
    vec3 gi = ogxEclipseApplySsrt(indirect, blockLight, minimumLight, viewPos, normal, noise, lightmap,
        false, false, pixel, frame, 8, 32, 1.0, sceneTex, depthTex, modelView, prevModelView,
        modelViewInverse, prevProjection, cameraPos - prevCameraPos, texelSize);
设计原因与取舍：
    参考实现直接读 `gl_FragCoord`、`frameCounter`、`gbufferModelView` 与缓冲编号。库把像素坐标、帧号、
    矩阵、纹理、射线数与开关全部改成显式参数；公式、循环顺序与分支条件保持参考实现。
    纹理只作为参数传入，库不绑定缓冲；调用方可以换分辨率、换历史缓冲，也可以独立测试。
*/
#ifndef OGX_ECLIPSE_INDIRECT_INCLUDED
#define OGX_ECLIPSE_INDIRECT_INCLUDED

// 相机提供投影与屏幕换算；数学提供夹紧与 R2 采样。



// 余弦半球采样：把二维均匀随机数变成半球上的余弦分布方向。
vec3 ogxEclipseCosineHemisphereSample(vec2 xi)
{
    float theta = 2.0 * 3.14159265359 * xi.y; // 方位角。
    float r = sqrt(xi.x); // 半径。
    float x = r * cos(theta); // 横坐标。
    float y = r * sin(theta); // 纵坐标。
    return vec3(x, y, sqrt(clamp(1.0 - xi.x, 0.0, 1.0))); // 半球上的方向。
}

// 切线空间转世界：用任意上向量构造一组正交基，再把半球方向转过去。
vec3 ogxEclipseTangentToWorld(vec3 N, vec3 H)
{
    vec3 upVector = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0); // 避免叉乘退化。
    vec3 T = normalize(cross(upVector, N)); // 切向。
    vec3 B = cross(N, T); // 副切向。
    return (T * H.x) + (B * H.y) + (N * H.z); // 参考实现的线性组合。
}

// Eclipse 线性深度：屏幕深度换米制距离。
float ogxEclipseLinZ(float depth, float nearPlane, float farPlane)
{
    return (2.0 * nearPlane) / (farPlane + nearPlane - depth * (farPlane - nearPlane)); // 参考实现的分式。
}

// Eclipse 线性深度反解：米制距离换屏幕深度。
float ogxEclipseInvLinZ(float linearDepth, float nearPlane, float farPlane)
{
    return -((2.0 * nearPlane / linearDepth) - farPlane - nearPlane) / (farPlane - nearPlane); // 参考实现的反解。
}

// Eclipse R2 采样：低差异序列，给每个像素不同的射线相位。
vec2 ogxEclipseR2Samples(int n)
{
    vec2 alpha = vec2(0.75487765, 0.56984026); // 参考实现的常数。
    return fract(alpha * float(n)); // 取小数。
}

// 取得纹理的像素尺寸：库需要显式尺寸，避免依赖宿主 `texelSize`。
vec2 texelFetchSize(sampler2D tex)
{
    return vec2(textureSize(tex, 0)); // GLSL 内建，返回整数尺寸。
}

// 取得纹理的像素尺寸：库需要显式尺寸，避免依赖宿主 `texelSize`。
// 屏幕空间 GI 追踪：从视空间位置沿方向步进，撞到深度图里的表面就返回命中点。
// `quarterRes` 为真时读取四分之一分辨率深度缓冲的 alpha 通道。
vec3 ogxEclipseRayTraceGi(vec3 dir, vec3 position, float dither, float quality,
    float nearPlane, float farPlane, float renderScale, sampler2D depthTexture, bool quarterRes,
    mat4 projection, mat4 projectionInverse)
{
    const float biasAmount = 0.0001; // 深度偏差。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点投到裁剪空间。
    float rayLength = ((position.z + dir.z * farPlane * sqrt(3.0)) > -nearPlane)
        ? (-nearPlane - position.z) / dir.z : farPlane * sqrt(3.0); // 射线到近平面的长度。
    vec3 direction = ogxToClipSpace3(position + dir * rayLength, projection) - clipPosition; // 裁剪空间方向。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到屏幕边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z); // 最短的一条。
    vec3 stepv = direction * mult / quality; // 每步长度。
    clipPosition.xy *= renderScale; // 渲染缩放。
    stepv.xy *= renderScale; // 步长同样缩放。
    vec3 spos = clipPosition + stepv * dither; // 起点加抖动。
    float minZ = spos.z - biasAmount / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        float sampleDepth = quarterRes
            ? sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture) / 4.0), 0).a / 65000.0)
            : ogxEclipseLinZ(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture)), 0).r, nearPlane, farPlane); // 读深度。
        float sp = ogxEclipseInvLinZ(sampleDepth, nearPlane, farPlane); // 反解屏幕深度。
        if ((sp < max(minZ, maxZ) && sp > min(minZ, maxZ))) return vec3(spos.xy / renderScale, sp); // 命中。
        minZ = maxZ - biasAmount / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 推进下界。
        maxZ += stepv.z; // 推进上界。
        spos += stepv; // 前进一步。
    }
    return vec3(1.1); // 没有命中。
}

// Eclipse 备用屏幕空间追踪：按屏幕距离决定步长，步数由参考实现的射线步数上限控制。
vec3 ogxEclipseRtAlternate(vec3 dir, vec3 position, float noise, float stepSizes, bool hand,
    inout float curve, int raySteps, float nearPlane, float farPlane, float renderScale,
    vec2 viewSize, vec2 texelSize, vec2 taaOffset, sampler2D depthTexture, bool quarterRes,
    mat4 projection, mat4 projectionInverse, mat4 modelViewInverse)
{
    vec3 worldPos = ogxToWorldSpace(position, modelViewInverse); // 转到相机相对世界。
    const float biasAmount = 0.00005; // 深度偏差。
    vec2 screenEdges = 2.0 / viewSize; // 屏幕边缘。
    float dist = 1.0 + length(worldPos) / farPlane; // 距离越远步长越大。
    float stepSize = stepSizes / dist; // 当前步长。
    int maxSteps = raySteps; // 最大步数。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点投到裁剪空间。
    float rayLength = ((position.z + dir.z * sqrt(3.0) * farPlane) > -sqrt(3.0) * nearPlane)
        ? (-sqrt(3.0) * nearPlane - position.z) / dir.z : sqrt(3.0) * farPlane; // 射线长度。
    vec3 end = ogxToClipSpace3(position + dir * rayLength, projection); // 终点。
    vec3 direction = end - clipPosition; // 裁剪空间方向。
    float len = max(abs(direction.x) / texelSize.x, abs(direction.y) / texelSize.y) / stepSize; // 屏幕步数。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到屏幕边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z) * 2000.0; // 参考实现的放大。
    vec3 stepv = direction / len; // 每步。
    int iterations = min(int(min(len, mult * len) - 2.0), maxSteps); // 实际步数。
    clipPosition.xy *= renderScale; // 渲染缩放。
    stepv.xy *= renderScale; // 步长缩放。
    vec3 spos = clipPosition + stepv * noise; // 起点加抖动。
    spos.xy += taaOffset * texelSize * 0.5 * renderScale; // 时间抗锯齿偏移。
    float minZ = spos.z - biasAmount / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    curve = 0.0; // 命中前曲线为零。
    for (int i = 0; i < iterations; i++) // 逐级步进。
    {
        spos.xy = clamp(spos.xy, screenEdges, 1.0 - screenEdges); // 夹到屏幕内。
        if (spos.x < 0.0 || spos.y < 0.0 || spos.z < 0.0 || spos.x > 1.0 || spos.y > 1.0 || spos.z > 1.0) return vec3(1.1); // 离开屏幕。
        float sp = quarterRes
            ? ogxEclipseInvLinZ(sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture) / 4.0), 0).a / 65000.0), nearPlane, farPlane)
            : texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture)), 0).r; // 读深度。
        float currZ = ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 当前米制深度。
        float nextZ = ogxEclipseLinZ(sp, nearPlane, farPlane); // 采样米制深度。
        if (nextZ < currZ && (sp <= max(minZ, maxZ) && sp >= min(minZ, maxZ))) return vec3(spos.xy / renderScale, sp); // 命中。
        minZ = maxZ - biasAmount / currZ; // 推进下界。
        maxZ += stepv.z; // 推进上界。
        spos += stepv; // 前进一步。
        curve += 1.0 / float(iterations); // 累积曲线。
    }
    return vec3(1.1); // 没有命中。
}

// 双边上采样 SSAO：四邻域按深度差加权，避免把远景遮蔽糊到近景。
vec4 ogxEclipseBilateralUpscaleSsao(sampler2D source, sampler2D sourceDepth, ivec2 pixel,
    int upscale, float referenceDepth, float depthThreshold, bool packedDepth, float nearPlane, float farPlane)
{
    ivec2 scaling = ivec2(1); // 参考实现的缩放。
    ivec2 posDepth = pixel * scaling; // 深度采样位置。
    ivec2 posColor = pixel; // 颜色采样位置。
    ivec2 pos = ivec2(vec2(pixel) * texelFetchSize(source) + vec2(1.0)); // 参考实现的偏移。
    ivec2 offsets[4] = ivec2[4](ivec2(-2, -2), ivec2(-2, 0), ivec2(0, 0), ivec2(0, -2)); // 四个邻域。
    vec4 result = vec4(0.0); // 颜色累加。
    float sum = 0.0; // 权重累加。
    for (int i = 0; i < 4; i++) // 四个邻域。
    {
        ivec2 radius = offsets[i]; // 当前偏移。
        float offsetDepth = packedDepth
            ? sqrt(texelFetch(sourceDepth, posDepth + radius * scaling + pos * scaling, 0).a / 65000.0)
            : ogxEclipseLinZ(texelFetch(sourceDepth, posDepth + radius * scaling + pos * scaling, 0).r, nearPlane, farPlane); // 读深度。
        float edges = abs(offsetDepth - referenceDepth) < depthThreshold ? 1.0 : 1e-5; // 深度边缘权重。
        result += texelFetch(source, posColor + radius + pos, 0) * edges; // 颜色加权。
        sum += edges; // 权重累加。
    }
    return result / sum; // 归一化。
}

// SSGI 合成：多根余弦半球射线，命中时读历史场景色，未命中时保留天空贡献。
vec3 ogxEclipseApplySsrt(vec3 unchangedIndirect, vec3 blockLightColor, vec3 minimumLightColor,
    vec3 viewPos, vec3 normal, vec3 noise, float lightmap, bool isGrass, bool isLod,
    ivec2 pixelCoord, int frameCounter, int rayCount, int raySteps, float giStrength,
    sampler2D sceneTexture, sampler2D depthTexture, vec2 texelSize,
    mat4 modelView, mat4 previousModelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 projection, mat4 projectionInverse,
    vec3 cameraDelta, float nearPlane, float farPlane, vec2 viewSize,
    bool quarterRes, bool highQuality, float giCurve)
{
    int nrays = rayCount; // 射线数。
    vec3 radiance = vec3(0.0); // 主辐射。
    vec3 occlusion = vec3(0.0); // 主遮蔽。
    vec3 skycontribution = unchangedIndirect; // 天空贡献。
    vec3 radiance2 = vec3(0.0); // 次辐射。
    vec3 occlusion2 = vec3(0.0); // 次遮蔽。
    vec3 skycontribution2 = unchangedIndirect; // 次天空。
    float curve = giCurve; // 命中曲线。
    vec3 bouncedLight = vec3(0.0); // 反弹光。
    for (int i = 0; i < nrays; i++) // 逐射线。
    {
        int seed = (frameCounter % 40000) * nrays + i; // 参考实现的帧序列。
        vec2 ij = fract(ogxEclipseR2Samples(seed) + noise.xy); // 采样点。
        vec3 rayDir = ogxEclipseTangentToWorld(normal, normalize(ogxEclipseCosineHemisphereSample(ij))); // 世界方向。
        vec3 rayHit = highQuality
            ? ogxEclipseRayTraceGi(ogxMatrix3MulPoint(mat3(modelView), rayDir), viewPos, noise.z, 5.0 * float(raySteps), nearPlane, farPlane, 1.0, depthTexture, quarterRes, projection, projectionInverse)
            : ogxEclipseRtAlternate(ogxMatrix3MulPoint(mat3(modelView), rayDir), viewPos, noise.z, float(raySteps), isLod, curve, raySteps, nearPlane, farPlane, 1.0, viewSize, texelSize, vec2(0.0), depthTexture, quarterRes, projection, projectionInverse, modelViewInverse); // 低质量版。
        curve = 1.0 - pow(1.0 - pow(1.0 - curve, 2.0), 5.0); // 参考实现的曲线重整。
        skycontribution = unchangedIndirect * (max(rayDir.y, pow(1.0 - lightmap, 2.0)) * 0.95 + 0.05) * 1.25; // 天空权重。
        radiance += skycontribution; // 累积天空。
        radiance2 += skycontribution2; // 累积次天空。
        if (rayHit.z < 0.9999 && distance(vec2(pixelCoord) * texelSize, rayHit.xy) > 0.001) // 命中且不是自身。
        {
            vec3 previousPosition = ogxToWorldSpace(ogxToScreenSpace(rayHit, projectionInverse), modelViewInverse) + cameraDelta; // 历史位置。
            previousPosition = ogxMatrix3MulPoint(mat3(previousModelView), previousPosition) + ogxMatrixTranslation(previousModelView); // 历史视空间。
            previousPosition.xy = ogxProject(previousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5; // 历史屏幕位置。
            if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0)
            {
                bouncedLight = texelFetch(sceneTexture, ivec2(previousPosition.xy / texelSize), 0).rgb * giStrength * curve; // 读历史颜色。
                radiance += bouncedLight; // 累积反弹。
                radiance2 += bouncedLight;
            }
            occlusion += skycontribution * curve; // 累积遮蔽。
            occlusion2 += skycontribution2 * curve;
        }
    }
    if (isLod) return max(radiance / float(nrays), vec3(0.0)); // 远景直接平均。
    return max((radiance - occlusion) / float(nrays), vec3(0.0)); // 参考实现的结果。
}

#endif

/*
生成文件：Eclipse 高光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 高光与反射模块：体素求交、WSR/Photonics 阴影、反射着色与屏幕空间高光。
调用位置：需要复现 Eclipse `specular.glsl`、`diffuse_lighting.glsl` 与 `indirect_lighting_effects.glsl`
    的程序；Minecraft 光影由 `/omni-gfx/eclipse_specular.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    OgxEclipseRayJob job = ogxEclipseRayJob(origin, direction);
    OgxEclipseTranslucentHit hits[10];
    int blockId; float sky;
    ogxEclipseTraceWsr(job, voxelIds, hits, blockId, sky);
    vec4 color = ogxEclipsePhotonicsReflection(job, hits, ...);
设计原因与取舍：
    参考实现直接读 `cb_array`、`imgVoxelMask`、`shadowtex0` 与大量菜单宏。库把体素图、阴影图、矩阵、
    光色、天空光与开关全部改成显式参数；遍历顺序、常数、采样次数和分支条件保持不变。
    体素世界用三维纹理代替原来的分层 SSBO：两者都按整数格取方块编号，语义相同，库因此不绑定 Minecraft。
    反射雾与 LPV 雾的密度由调用方传入三维纹理，库只负责步进、吸收和合成。
*/
#ifndef OGX_ECLIPSE_SPECULAR_INCLUDED
#define OGX_ECLIPSE_SPECULAR_INCLUDED

// 相机与数学提供投影、求交与夹紧；体素提供格号与法线编号；Eclipse 补充提供 GGX 与螺旋采样。







// 体素包围盒求交结果：命中、参数、位置与进入面轴。
struct OgxEclipseRayHit
{
    bool hit; // 是否命中。
    float t; // 射线参数。
    vec3 currPos; // 命中位置。
    vec3 stepAxis; // 进入面轴。
};

// 体素射线任务：起点、方向、结果。
struct OgxEclipseRayJob
{
    vec3 origin; // 起点，体积坐标。
    vec3 direction; // 方向。
    vec3 resultPosition; // 命中位置。
    vec3 resultColor; // 命中颜色。
    vec3 resultNormal; // 命中法线。
    bool resultHit; // 是否命中。
};

// 半透明命中：给反射链逐层染色。
struct OgxEclipseTranslucentHit
{
    vec3 hitNormal; // 命中面法线。
    vec3 hitPos; // 命中点。
    vec4 hitColor; // 颜色与透明度。
    int hitId; // 方块编号。
    float skylight; // 天光。
};

// 屏幕空间高光追踪的提前声明：环境反射函数会先调用它，定义放在文件后半段。
vec3 ogxEclipseRayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    sampler2D depthTexture, mat4 projection, mat4 projectionInverse);

// 构造一个体素射线任务。
OgxEclipseRayJob ogxEclipseRayJob(vec3 origin, vec3 direction){
    OgxEclipseRayJob job; // 逐字段赋值，避免结构体构造顺序出错。
    job.origin = origin;
    job.direction = direction;
    job.resultPosition = vec3(0.0);
    job.resultColor = vec3(0.0);
    job.resultNormal = vec3(0.0);
    job.resultHit = false;
    return job;
}

// 体素包围盒求交：返回结构体版本，和参考实现的 `AABBintersection2` 相同。
OgxEclipseRayHit ogxEclipseAabbIntersection2(vec3 currPos, vec3 reflectedVector, vec3 stepSizes,
    vec3 boxMin, vec3 boxMax, vec3 stepAxis)
{
    vec3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    vec3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    vec3 tmin = min(t1, t2); // 每轴入口。
    vec3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    OgxEclipseRayHit result; // 结果。
    result.hit = hit;
    result.t = tmin0;
    vec3 entryDist = abs(tmin - vec3(tmin0)); // 哪一轴最先进入。
    vec3 normal = step(entryDist, vec3(0.0)); // 入口轴标记。
    result.stepAxis = mix(stepAxis, normal, fHit); // 命中时更新轴。
    result.currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return result; // 交回结构体。
}

// 排序两个裁切体素交点：先取较近的，再用贴图 alpha 判断是否穿过去。
void ogxEclipseSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, vec3 stepDir,
    vec2 gtexSize, vec2 texCoordOffset, vec3 voxelPos, sampler2D gtexture,
    inout bool hit, inout vec3 shiftedCurrPos, inout vec3 stepAxis)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    OgxEclipseRayHit secondHit = useFirst ? hit2 : hit1; // 第二命中。
    vec2 texCoord; // 贴图坐标。
    vec3 voxelNormal = -firstHit.stepAxis * stepDir; // 进入面法线。
    ogxGetVoxelTexCoord(vec4(0.0), texCoord); // 占位，真实面数据由调用方替换。
    vec3 wPos = firstHit.currPos; // 世界位置。
    vec2 sampleDir = firstHit.stepAxis.x * fract(wPos.zy) + firstHit.stepAxis.y * fract(wPos.xz)
        + firstHit.stepAxis.z * fract(wPos.xy); // 进入面内的采样方向。
    texCoord = mix(texCoord + vec2(0.0, texCoordOffset.y), texCoord - vec2(0.0, texCoordOffset.y), sampleDir); // 纵向偏移。
    texCoord = mix(texCoord + vec2(texCoordOffset.x, 0.0), texCoord - vec2(texCoordOffset.x, 0.0), sampleDir); // 横向偏移。
    float sampleAlpha = textureLod(gtexture, texCoord, 0.0).a; // 参考实现的最近采样。
    firstHit = sampleAlpha > 0.1 ? firstHit : secondHit; // 透明就穿到第二命中。
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

// 排序两个不透明体素交点：只保留较近的一个。
void ogxEclipseSortIntersectionOpaque(inout OgxEclipseRayHit hit1, OgxEclipseRayHit hit2,
    inout bool hit, inout vec3 shiftedCurrPos, inout vec3 stepAxis)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    hit1 = firstHit;
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

// 栅栏包围盒：横杆加两根立柱，逐个求交后取最近。
void ogxEclipseFenceIntersection(inout vec3 shiftedCurrPos, vec3 reflectedVector, vec3 invReflectedVector,
    inout bool hit, vec3 floorOffsetWorldPos, vec3 floorOffsetWorldPos1, vec3 floorOffsetWorldPos2,
    inout vec3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + vec3(0.375, 0.001, 0.375), floorOffsetWorldPos + vec3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
}

// 双段栅栏：横杆加四根立柱。
void ogxEclipseFenceIntersection2(inout vec3 shiftedCurrPos, vec3 reflectedVector, vec3 invReflectedVector,
    inout bool hit, vec3 floorOffsetWorldPos, vec3 floorOffsetWorldPos1, vec3 floorOffsetWorldPos2,
    vec3 floorOffsetWorldPos3, vec3 floorOffsetWorldPos4, inout vec3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + vec3(0.375, 0.001, 0.375), floorOffsetWorldPos + vec3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    OgxEclipseRayHit hit4 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3, floorOffsetWorldPos4, stepAxis); // 第三立柱。
    OgxEclipseRayHit hit5 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos4 - vec3(0.0, 0.375, 0.0), stepAxis); // 第四立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
}

// 四分之一体素追踪：在低分辨率掩码里走到第一个非空格，返回是否命中。
bool ogxEclipseTraceQuarterVoxel(vec3 reflectedVector, vec3 invReflectedVector, vec3 stepSizes,
    vec3 voxelPos, vec3 stepDir, vec3 nextDist, vec3 currPos, usampler3D quarterVoxelMask, int side)
{
    vec3 quarterVoxelPos = voxelPos / 4.0; // 转四分之一格。
    vec3 originalQuarterVoxelPos = quarterVoxelPos; // 起点备份。
    vec3 quarterNextDist = 4.0 * ((stepDir * 0.5 + 0.5) - fract(quarterVoxelPos)) * invReflectedVector; // 下一边界。
    vec3 quarterCurrPos = currPos; // 当前位置。
    for (int i = 0; i < side / 4; i++) // 固定步数。
    {
        float closestDist = min(min(quarterNextDist.x, quarterNextDist.y), quarterNextDist.z); // 最近边界。
        quarterCurrPos += reflectedVector * closestDist; // 前进。
        vec3 stepAxis = step(quarterNextDist, vec3(closestDist)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x); // 参考实现的轴选择。
        stepAxis.z *= (1.0 - stepAxis.y);
        quarterVoxelPos += stepAxis * stepDir; // 走一格。
        if (clamp(quarterVoxelPos, vec3(0.0), vec3(side / 4)) != quarterVoxelPos) break; // 越界停止。
        uint blockID = texelFetch(quarterVoxelMask, ivec3(quarterVoxelPos), 0).r; // 读掩码。
        if (blockID > 0u && quarterVoxelPos != originalQuarterVoxelPos) return true; // 命中非空。
        quarterNextDist += 4.0 * stepSizes * stepAxis - closestDist; // 推进边界。
    }
    return false; // 没有命中。
}

// 体素阴影投影偏差：参考实现的 `applyShadowBias`。
vec3 ogxEclipseApplyShadowBias(vec3 projectedShadowPosition, vec3 shadowNormal, float shadowDistance,
    float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个阴影纹素对应的方块比例。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远偏差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 距离放大。
    return projectedShadowPosition + shadowNormal * biasSize * 0.15 * biasDistanceFactor; // 沿法线推离表面。
}

// 体素阴影主函数：参考实现的 `ComputeVoxelShadowMap`，用显式阴影图与矩阵。
float ogxEclipseComputeVoxelShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade,
    float noise, vec3 geoNormals, sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader, mat4 endShadowMatrix, mat4 endShadowPerspective)
{
    float distortFactor = 1.0; // 边缘压缩系数。
    vec3 projectedShadowPosition; // 阴影图坐标。
    if (!endShader) // 主世界与下界。
    {
        projectedShadowPosition = ogxMatrix3MulPoint(mat3(shadowView), playerPos) + ogxMatrixTranslation(shadowView); // 转到阴影相机。
        vec3 shadowNormal = ogxMatrix3MulPoint(mat3(shadowView), geoNormals); // 法线也转过去。
        projectedShadowPosition = ogxEclipseApplyShadowBias(projectedShadowPosition, shadowNormal, shadowDistance, shadowMapResolution); // 推离表面。
        projectedShadowPosition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * projectedShadowPosition
            + ogxMatrixTranslation(shadowProjection); // 乘投影。
        distortFactor = 1.0 / (log(length(projectedShadowPosition.xy) * distortB + distortA) * distortK); // 边缘压缩。
        projectedShadowPosition.xy *= distortFactor; // 压缩横纵。
        projectedShadowPosition.z += shadowProjection[3][2] * 0.0012; // 深度偏移。
    }
    else // 末地主岛光使用独立矩阵。
    {
        vec4 shadowPos = ogxMatrixMulPoint4(endShadowMatrix, vec4(playerPos, 1.0)); // 末地阴影矩阵。
        vec3 shadowNormal = ogxMatrix3MulPoint(mat3(endShadowMatrix), geoNormals); // 法线。
        shadowPos.xyz = vec4(ogxEclipseApplyShadowBias(shadowPos.xyz, shadowNormal, shadowDistance, shadowMapResolution), 1.0).xyz; // 推离。
        shadowPos = ogxMatrixMulPoint4(endShadowPerspective, shadowPos); // 透视投影。
        projectedShadowPosition = shadowPos.xyz / shadowPos.w; // 齐次除法。
        distortFactor = 1.0; // 末地不做压缩。
    }
    projectedShadowPosition = projectedShadowPosition * vec3(0.5, 0.5, 0.5 / 6.0) + vec3(0.5); // 参考实现的深度缩放。
    float shadowmap = 0.0; // 阴影累加。
    vec3 translucentTint = vec3(0.0); // 彩色半透明阴影。
    int samples = basicFilter ? shadowSampleCount / 2 : 1; // 滤波样本数。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (basicFilter) // 只有开启滤波时才加螺旋偏移。
        {
            float rdMul = (endShader ? 52.0 : 2.4 * distortFactor) * d0k; // 参考实现的半径。
            vec2 offsetS = ogxEclipseCleanVoxelSample(i, float(samples - 1), noise) * rdMul; // 螺旋偏移。
            projectedShadowPosition.xy += offsetS; // 累加偏移。
        }
        if (coloredShadows) // 彩色半透明阴影。
        {
            float shadowDepthDiff = pow(clamp((textureLod(translucentShadowMap, projectedShadowPosition.xy, 0.0).x - projectedShadowPosition.z) * 2.0, 0.0, 1.0), 2.0); // 不透明遮挡差。
            float opaqueShadow = textureLod(opaqueShadowMap, projectedShadowPosition.xy, 0.0).x; // 不透明阴影。
            shadowmap += max(opaqueShadow, shadowDepthDiff); // 取较大。
            vec4 translucentShadow = textureLod(shadowcolor0, projectedShadowPosition.xy, 0.0); // 半透明阴影。
            float shadowAlpha = pow(1.0 - pow(translucentShadow.a, 5.0), 0.2); // 参考实现的透明度曲线。
            translucentShadow.rgb = max(normalize(translucentShadow.rgb + 0.0001), max(opaqueShadow, 1.0 - shadowAlpha)) * shadowAlpha; // 保色相。
            translucentTint += mix(translucentShadow.rgb, vec3(1.0), opaqueShadow * shadowDepthDiff); // 累积染色。
        }
        else
        {
            shadowmap += textureLod(opaqueShadowMap, projectedShadowPosition.xy, 0.0).x; // 普通阴影。
        }
    }
    if (coloredShadows) directLightColor *= mix(vec3(1.0), translucentTint / float(samples), maxDistFade); // 光源染色。
    float shadowResult = shadowmap / float(samples); // 平均阴影。
    if (endShader) // 末地主岛光的圆形范围。
    {
        float r = length(projectedShadowPosition.xy - vec2(0.5)); // 到中心距离。
        if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) shadowResult *= smoothstep(0.5, 0.25, r); // 软边。
        else shadowResult = 0.0; // 圆外没有光。
    }
    return shadowResult; // 交回阴影。
}

// Photonics 阴影：和体素阴影相同的几何路径，但用 Photonics 采样曲线与固定样本数。
float ogxEclipseComputePhotonicsShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade,
    float noise, vec3 geoNormals, sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader)
{
    return ogxEclipseComputeVoxelShadowMap(directLightColor, playerPos, maxDistFade, noise, geoNormals,
        opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowDistance, shadowMapResolution,
        distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows, endShader,
        mat4(1.0), mat4(1.0)); // 末地矩阵在这里不用，传入单位矩阵。
}

// WSR 体素追踪：在三维方块编号图里逐格前进，记录半透明命中与最终不透明命中。
void ogxEclipseTraceWsr(inout OgxEclipseRayJob job, usampler3D voxelIds, sampler3D voxelColors,
    inout OgxEclipseTranslucentHit translucentHits[10], inout uint translucentHitsCount,
    out int blockId, out float skylightmap, int side, float worldOffset)
{
    job.direction = normalize(job.direction); // 方向单位化。
    blockId = -1; // 默认没有方块。
    skylightmap = 0.0; // 默认没有天光。
    vec3 position = job.origin; // 当前格坐标。
    vec3 raySign = sign(job.direction); // 每轴方向。
    vec3 invDir = 1.0 / job.direction; // 方向倒数。
    vec3 tMax = vec3(1e30); // 到下一格边界的参数。
    ivec3 cell = ivec3(floor(position)); // 当前格。
    ivec3 stepDir = ivec3(raySign); // 每轴步进。
    if (job.direction.x != 0.0) tMax.x = (float(cell.x) + max(raySign.x, 0.0) - position.x) * invDir.x; // 横轴边界。
    if (job.direction.y != 0.0) tMax.y = (float(cell.y) + max(raySign.y, 0.0) - position.y) * invDir.y; // 纵轴边界。
    if (job.direction.z != 0.0) tMax.z = (float(cell.z) + max(raySign.z, 0.0) - position.z) * invDir.z; // 深度轴边界。
    int previousBlock = -1; // 上一格方块，避免同一方块反复记半透明。
    for (int i = 0; i < 512; i++) // 固定步数。
    {
        if (!ogxVoxelInside(cell, side)) break; // 走出体积。
        float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近边界。
        vec3 stepAxis = step(tMax, vec3(tMin)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x);
        stepAxis.z *= (1.0 - stepAxis.y);
        cell += ivec3(stepAxis * raySign); // 走一格。
        position += job.direction * tMin; // 更新位置。
        tMax += stepAxis * abs(invDir) - tMin; // 更新边界。
        if (!ogxVoxelInside(cell, side)) break; // 越界停止。
        uint id = texelFetch(voxelIds, cell, 0).r; // 方块编号。
        if (id == 0u) continue; // 空气。
        blockId = int(id); // 记录编号。
        vec4 stored = texelFetch(voxelColors, cell, 0); // 颜色与光照。
        if ((stored.a > 0.01) && (previousBlock != blockId) && (translucentHitsCount < 10u)) // 半透明方块。
        {
            vec3 hitNormal = -stepAxis * raySign; // 进入面法线。
            translucentHits[translucentHitsCount].hitNormal = hitNormal;
            translucentHits[translucentHitsCount].hitPos = position + worldOffset; // 转回世界。
            translucentHits[translucentHitsCount].hitColor = stored;
            translucentHits[translucentHitsCount].hitId = blockId;
            translucentHits[translucentHitsCount].skylight = stored.a; // 体素颜色 alpha 当作天光。
            translucentHitsCount += 1u;
        }
        previousBlock = blockId;
        job.resultHit = true; // 命中不透明面。
        job.resultPosition = position + worldOffset;
        job.resultColor = stored.rgb;
        job.resultNormal = -stepAxis * raySign;
        skylightmap = stored.a;
        break; // 参考实现遇到第一个非空方块就停。
    }
}

// 方块光体素版：LPV 采样与手持光由调用方传入，曲线和边缘淡出与参考实现相同。
vec3 ogxEclipseDoBlockLightLightingVoxel(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightmapLight *= lightmapLight;
    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot); // 混合曲线。
    vec3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版光照图遮罩。
    vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
    float voxelRangeFalloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
    voxelRangeFalloff = 1.0 - pow(1.0 - pow(voxelRangeFalloff, 1.5), 3.0); // 参考实现的曲线。
    blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), voxelRangeFalloff); // 体积外回退。
    blockLight += handLight; // 手持光直接相加。
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 间接光：Eclipse 的 `doIndirectLighting`，把光照图曲线乘到环境光上。
vec3 ogxEclipseDoIndirectLighting(vec3 lightColor, vec3 minimumLightColor, float lightmap,
    float ambientBrightness, float minLightAmount, float minLightAmountInside, float nightVision)
{
    float lightmapCurve = (pow(lightmap, 15.0) * 2.0 + lightmap * lightmap) / 3.0; // 参考实现的曲线。
    vec3 indirectLight = lightColor * lightmapCurve * ambientBrightness; // 环境光。
    indirectLight += mix(minimumLightColor * (minLightAmount * 0.004 + nightVision * 0.02),
        minimumLightColor * (minLightAmountInside * 0.004 + nightVision * 0.02), 1.0 - lightmap); // 最低亮度。
    return indirectLight; // 交回间接光。
}

// Photonics 反射着色：间接光、方块光、阴影、云影与自发光一起决定命中面颜色。
void ogxEclipsePhotonicsReflectionShading(inout vec4 color, vec3 normal, vec3 worldPos, float noise,
    vec3 directLightColor, vec3 ambientLightColor, int blockID, float skylightmap, vec3 torchColor,
    vec3 lpvSample, vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount,
    bool vanillaMask, float shadowDistance, float ambientBrightness, float minLightAmount,
    float minLightAmountInside, float nightVision, float eyeBrightness, float cloudShadow, vec3 sunVector,
    sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount,
    bool basicFilter, bool coloredShadows, bool endShader, float emissiveBrightness, float emissiveCurve)
{
    float skyDir = normal.y * 0.5 + 0.5; // 法线朝上程度。
    vec2 lightmap = vec2(0.0, skylightmap); // 光照图。
    if (abs(blockID - 197) <= 1 || blockID == 242) lightmap.x = 1.0; // 岩浆块与海晶灯。
    float skylight = mix(0.08 + 0.92 * (1.0 - lightmap.y), 1.0, skyDir); // 天空光。
    vec3 indirectLighting = ogxEclipseDoIndirectLighting(ambientLightColor * skylight, vec3(1.0),
        lightmap.y, ambientBrightness, minLightAmount, minLightAmountInside, nightVision); // 间接光。
    vec3 playerPosition = worldPos; // 相机相对位置。
    indirectLighting += ogxEclipseDoBlockLightLightingVoxel(torchColor, lightmap.x, lpvSample, handLight,
        lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask); // 方块光。
    float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance + 16.0), 0.0) * 5.0, 1.0)); // 阴影距离淡出。
    float sh = 1.0; // 阳光阴影。
    if (!endShader) sh = ogxEclipseComputePhotonicsShadowMap(directLightColor, playerPosition, shadowMapFalloff,
        noise, normal, opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection,
        shadowDistance, shadowMapResolution, distortA, distortB, distortK, d0k, shadowSampleCount,
        basicFilter, coloredShadows, false); // 主世界阴影。
    float lightLeakFix = clamp(pow(eyeBrightness / 240.0 + lightmap.y, 2.0), 0.0, 1.0); // 漏光修正。
    sh *= lightLeakFix;
    sh *= cloudShadow; // 云影。
    float NdotL = endShader ? 1.0 : clamp((-15.0 + dot(normal, sunVector) * 255.0) / 240.0, 0.0, 1.0); // 参考实现的直射项。
    vec3 albedo = color.rgb; // 命中面底色。
    color.rgb *= indirectLighting + directLightColor * sh * NdotL; // 合成光照。
    float emissive = 0.0; // 自发光。
    if (blockID >= 100 && blockID < 282) // 普通光源方块。
    {
        emissive = 0.5;
        if (blockID == 266 || (blockID >= 276 && blockID <= 281)) emissive = 0.2; // 幽匿方块。
        else if (blockID == 195) emissive = 2.3; // 发光地衣。
        else if (blockID == 185) emissive = 1.5; // 哭泣的黑曜石。
        else if (blockID == 105) emissive = 2.0; // 酿造台。
        else if (blockID == 236) emissive = 1.0; // 重生锚。
        else if (blockID == 101) emissive = 0.7; // 紫水晶芽。
        else if (blockID == 103) emissive = 1.0; // 紫水晶簇。
        else if (blockID == 244) emissive = 1.5; // 灵魂火。
        emissive *= ogxGetVoxelEmission(albedo); // 自发光曲线。
        emissive = clamp(emissive, 0.0, 1.0); // 夹紧。
        ogxVoxelEmission(color.rgb, albedo, emissive, emissiveBrightness, emissiveCurve); // 混入自发光。
    }
}

// Photonics 反射：先追踪体素，再给半透明与不透明命中着色，最后按雾吸收。
vec4 ogxEclipsePhotonicsReflection(OgxEclipseRayJob job, OgxEclipseTranslucentHit translucentHits[10],
    uint translucentHitsCount, vec3 reflectedVector, vec3 flatNormal, vec2 noise,
    inout float backgroundReflectMask, inout vec3 backgroundTint,
    usampler3D voxelIds, sampler3D voxelColors, vec3 directLightColor, vec3 ambientLightColor,
    vec3 indirectLightColor, float ambientBrightness, float skyLightLevelSmooth, float nightVision,
    float minLightAmount, float minLightAmountInside, vec3 torchColor, vec3 lpvSample, vec3 handLight,
    vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask,
    float shadowDistance, float eyeBrightness, float cloudShadow, vec3 sunVector,
    sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0, mat4 shadowView, mat4 shadowProjection, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, float emissiveBrightness, float emissiveCurve, bool translucentInReflections)
{
    vec4 color = vec4(0.0); // 反射颜色。
    int blockID = 0; // 最终方块编号。
    float skylightmap = 0.0; // 最终天光。
    if (translucentInReflections) // 只有开启半透明反射时才逐层染色。
    {
        for (uint i = 0u; i < translucentHitsCount; i++) // 逐层半透明。
        {
            vec4 sampleColor = translucentHits[i].hitColor; // 半透明颜色。
            ogxEclipsePhotonicsReflectionShading(sampleColor, translucentHits[i].hitNormal,
                translucentHits[i].hitPos, noise.y, directLightColor, ambientLightColor,
                translucentHits[i].hitId, translucentHits[i].skylight, torchColor, lpvSample, handLight,
                lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask, shadowDistance, ambientBrightness,
                minLightAmount, minLightAmountInside, nightVision, eyeBrightness, cloudShadow, sunVector,
                opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowMapResolution,
                distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows,
                false, emissiveBrightness, emissiveCurve); // 给半透明命中着色。
            sampleColor.a *= (1.0 - color.a); // 预乘透明度。
            color.rgb += sampleColor.rgb * sampleColor.a; // 累积颜色。
            color.a += sampleColor.a; // 累积透明度。
            if (color.a > 0.995) return color; // 足够不透明就停止。
        }
        if (translucentHitsCount > 0u) backgroundTint = mix(normalize(translucentHits[0].hitColor.rgb + 1e-7),
            vec3(1.0), min(max(0.1 - translucentHits[0].hitColor.a, 0.0) * 10.0, 1.0)); // 背景染色。
    }
    if (job.resultHit) // 不透明命中。
    {
        vec4 sampleColor = vec4(job.resultColor, 1.0); // 命中颜色。
        ogxEclipsePhotonicsReflectionShading(sampleColor, job.resultNormal, job.resultPosition, noise.y,
            directLightColor, ambientLightColor, blockID, skylightmap, torchColor, lpvSample, handLight,
            lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask, shadowDistance, ambientBrightness,
            minLightAmount, minLightAmountInside, nightVision, eyeBrightness, cloudShadow, sunVector,
            opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowMapResolution,
            distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows,
            false, emissiveBrightness, emissiveCurve); // 给不透明命中着色。
        sampleColor.rgb *= backgroundTint; // 半透明背景染色。
        sampleColor.a *= (1.0 - color.a);
        color.rgb += sampleColor.rgb * sampleColor.a;
        color.a += sampleColor.a;
    }
    if (color.a < 0.999) backgroundReflectMask = 1.0; // 还有背景透出。
    return color; // 交回反射颜色。
}

// 反射可见度：按 f0 与粗糙度判断高光是否值得显示，避免粗糙金属被反射糊满。
float ogxEclipseGetReflectionVisibility(float f0, float roughness, float roughnessThreshold)
{
    if (roughnessThreshold < 1.0) return 0.0; // 阈值太低就没有反射。
    float thresholdValue = roughnessThreshold / 100.0; // 参考实现的百分比。
    float dialectrics = max(f0 * 255.0 - 26.0, 0.0) / 229.0; // 非金属比例。
    float value = 0.35; // 第一段阈值。
    float thresholdA = min(max((1.0 - dialectrics) - value, 0.0) / value, 1.0); // 第一段。
    float smoothness = 1.0 - sqrt(roughness); // 感知光滑度。
    value = thresholdValue; // 第二段阈值。
    float thresholdB = min(max(smoothness - value, 0.0) / value, 1.0); // 第二段。
    value = 0.1; // 超光滑材料保护。
    float thresholdC = 1.0 - min(max(value - (1.0 - smoothness), 0.0) / value, 1.0); // 第三段。
    float visibilityGradient = max(thresholdA * thresholdC - thresholdB, 0.0); // 合成梯度。
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    return visibilityGradient; // 交回可见度。
}

// 环境反射：屏幕空间追踪加历史重投影，天空回退由调用方在 `backgroundReflection` 里处理。
vec4 ogxEclipseGetEnvironmentReflections(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    vec3 viewPos, vec2 noise, bool isHand, float roughness, inout float backgroundReflectMask,
    inout vec3 backgroundTint, float quality, sampler2D sceneTexture, sampler2D depthTexture,
    mat4 projection, mat4 projectionInverse, mat4 modelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 previousModelView, float nearPlane, float farPlane,
    vec3 cameraDelta, float renderScale, vec2 texelSize, float usePhotonics)
{
    vec4 reflection = vec4(0.0); // 反射结果。
    float reflectionLength = 0.0; // 反射长度。
    if (usePhotonics > 0.5) // Photonics 路径。
    {
        if (dot(reflectedVector, flatNormal) < 0.0) return reflection; // 射线朝表面内侧。
        return reflection; // 体素追踪由单独的 Photonics 函数负责。
    }
    bool depthCheck = false; // 深度检查。
    vec3 raytracePos = ogxEclipseRayTraceSpeculars(ogxMatrix3MulPoint(mat3(modelView), reflectedVector), viewPos,
        noise.y, quality, isHand, reflectionLength, depthCheck, nearPlane, farPlane, renderScale,
        depthTexture, projection, projectionInverse); // 屏幕空间追踪。
    if (raytracePos.z > 1.00001) return reflection; // 没命中。
    reflectionLength = min(max(reflectionLength - 0.1, 0.0) / 0.9, 1.0); // 参考实现的长度重整。
    float lod = mix(0.0, 6.0 * (1.0 - exp(-15.0 * sqrt(roughness))), 1.0 - pow(1.0 - reflectionLength, 5.0)); // 粗糙度决定层级。
    vec3 previousPosition = ogxToWorldSpace(ogxToScreenSpace(raytracePos, projectionInverse), modelViewInverse) + cameraDelta; // 历史位置。
    previousPosition = ogxMatrix3MulPoint(mat3(previousModelView), previousPosition) + ogxMatrixTranslation(previousModelView);
    previousPosition.xy = ogxProject(previousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5; // 历史屏幕位置。
    if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0)
    {
        if (raytracePos.z > 0.9999999) backgroundReflectMask = 1.0; // 天空命中。
        reflection.a = raytracePos.z > 0.9999999 ? 1.0 : 1.0; // 参考实现的主世界分支。
        reflection.rgb = textureLod(sceneTexture, previousPosition.xy, lod).rgb; // 读历史颜色。
    }
    return reflection; // 交回反射。
}

// 屏幕空间高光追踪：参考实现的 `rayTraceSpeculars`，支持远景矩阵与手部跳过。
vec3 ogxEclipseRayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    sampler2D depthTexture, mat4 projection, mat4 projectionInverse)
{
    const float biasAmount = 0.0001; // 深度偏差。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点。
    float rayLength = ((position.z + dir.z * farPlane * sqrt(3.0)) > -nearPlane)
        ? (-nearPlane - position.z) / dir.z : farPlane * sqrt(3.0); // 射线长度。
    vec3 direction = ogxToClipSpace3(position + dir * rayLength, projection) - clipPosition; // 裁剪空间方向。
    vec3 reflectedTC = vec3((direction.xy + clipPosition.xy) * renderScale, 0.999999); // 参考实现的回退。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z); // 最短长度。
    vec3 stepv = direction * mult / quality; // 每步。
    clipPosition.xy *= renderScale;
    stepv.xy *= renderScale;
    vec3 spos = clipPosition + stepv * (dither * 0.5 + 0.5); // 起点加抖动。
    spos += vec3(0.5 * texelFetchSize(depthTexture), 0.0); // 半像素偏移。
    float minZ = spos.z - 0.00025 / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    vec3 hitPos = vec3(1.1); // 默认没有命中。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        if (!hand && (spos.x < 0.0 || spos.x > 1.0 || spos.y < 0.0 || spos.y > 1.0)) return vec3(1.1); // 手部允许出屏。
        float sp = texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture)), 0).r; // 读深度。
        if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) // 命中。
        {
            hitPos = vec3(spos.xy / renderScale, sp);
            break;
        }
        minZ = maxZ - biasAmount / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 推进下界。
        maxZ += stepv.z;
        spos += stepv;
        reflectionLength += 1.0 / quality; // 累积长度。
    }
    if (hand) return reflectedTC; // 手部回退到裁剪坐标。
    return hitPos; // 交回命中。
}

// 高光反射主函数：背景反射、环境反射、太阳 GGX 与手持光 GGX 的合成。
vec3 ogxEclipseSpecularReflections(vec3 viewPos, vec3 playerPos, vec3 NplayerPos, vec3 lightVec,
    vec2 noise, vec3 flatNormal, vec3 normal, float roughness, float f0, vec3 albedo,
    vec3 diffuseLighting, vec3 lightColor, float lightmap, bool isHand, bool isMetalPass,
    vec3 backgroundReflection, vec3 sunlightColor, float sunSpecularMultiplier,
    float roughnessThreshold, bool ssrEnabled, bool backgroundEnabled, vec3 flashlightColor,
    float flashlightIntensity, sampler2D sceneTexture, sampler2D depthTexture,
    mat4 projection, mat4 projectionInverse, mat4 modelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 previousModelView, float nearPlane, float farPlane,
    vec3 cameraDelta, float renderScale, vec2 texelSize)
{
    lightmap = min(max(lightmap - 0.9, 0.0) / 0.1, 1.0); // 光照图重整。
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    roughness = 1.0 - roughness; // 粗糙度反转。
    roughness *= roughness;
    f0 = f0 == 0.0 ? 0.02 : f0; // 默认介电常数。
    bool isMetal = f0 > 229.5 / 255.0; // 金属判定。
    mat3 basis = ogxEclipseFrisvad(normal); // 切线基。
    vec3 viewDir = ogxMatrix3MulPoint(basis, -NplayerPos); // 转到切线空间。
    vec3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), vec3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxEclipseShlickFresnelRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0); // 金属染色。
    vec3 hardCodedMetalsF0[8] = vec3[8](
        vec3(0.531228825312, 0.51235724246, 0.495828545714),
        vec3(0.944229966045, 0.77610211732, 0.373402004593),
        vec3(0.912298031535, 0.91385063144, 0.919680580954),
        vec3(0.55559681715, 0.55453707574, 0.554779427513),
        vec3(0.925952196272, 0.72090163805, 0.504154241735),
        vec3(0.632483812932, 0.62593707362, 0.641478899539),
        vec3(0.678849234658, 0.64240055565, 0.588409633571),
        vec3(0.961999998804, 0.94946811207, 0.922115710997)); // 参考实现的八种金属。
    vec3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    vec3 reflectance = isMetal ? hardCodedMetals : vec3(f0); // 反射率。
    vec3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    vec3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxEclipseGetReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    float backgroundReflectMask = lightmap; // 背景遮罩。
    vec4 environmentReflection = vec4(0.0); // 环境反射。
    vec3 backgroundTint = vec3(1.0); // 背景染色。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        vec3 darkened = isMetal ? diffuseLighting * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        if (backgroundEnabled) specular = mix(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        if (ssrEnabled) // 屏幕空间反射。
        {
            environmentReflection = ogxEclipseGetEnvironmentReflections(reflectedVector, flatNormal, normal,
                playerPos, viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint,
                1.0, sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
                previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale,
                texelSize, 0.0); // 不用 Photonics。
            specular = mix(specular, environmentReflection.rgb, environmentReflection.a); // 合并环境反射。
        }
        specular = mix(darkened, specular, F0); // 按菲涅耳混合。
        specular = mix(specular, darkened, visibility); // 按可见度回到漫反射。
    }
    if (sunSpecularMultiplier > 0.0) // 太阳高光。
    {
        vec3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * sunlightColor
            * ogxEclipseGgx(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // GGX。
        specular += lightSourceReflection * (1.0 - environmentReflection.a); // 环境反射占用后剩下的部分。
    }
    if (flashlightIntensity > 0.0) // 手电高光。
    {
        vec3 flashLightReflection = flashlightColor * flashlightIntensity
            * ogxEclipseGgx(normal, -normal, -normal, roughness, reflectance, metalAlbedoTint); // 参考实现的手电方向近似。
        specular += flashLightReflection;
    }
    return specular; // 交回高光。
}

// 体素反射的当前参考实现：追踪主体在原程序里被整段注释，只剩背景遮罩与清空颜色。
// 保留参数与输出，后续恢复追踪时调用方不用改接口。
vec4 ogxEclipseVoxelReflection(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    float noise, inout float backgroundReflectMask, vec3 directLightColor, vec3 ambientLightColor)
{
    backgroundReflectMask = 1.0; // 参考实现固定回到背景反射。
    return vec4(0.0); // 参考实现的当前颜色输出。
}

// WSR 的 LPV 体积雾：沿视线指数步进，用三维密度图与 LPV 图累积照明。
// 参考实现直接调 `cloudVol` 与 `SampleLpvLinear`；库用同样布局的三维纹理代替。
vec4 ogxEclipseRaymarchWsrLpv(vec3 origin, vec3 endPos, float dither, sampler3D densityTexture,
    sampler3D lpvTexture, vec3 cameraOffset, float lpvSize, float fadeLength, float minDensity,
    float mult, int sampleCount, float lpvBrightness, vec3 handLight, float torchAmount, bool vanillaMask)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    vec3 rayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float rayLength = length(rayStart); // 射线长度。
    rayStart *= min(rayLength, min(256.0, 1e6)) / max(rayLength, 1e-6); // 参考实现的距离上限。
    rayLength = length(rayStart);
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = cameraOffset + d * rayStart + origin; // 当前世界位置。
        float density = max(textureLod(densityTexture, progress, 0.0).r / 1000.0, minDensity) * mult; // 密度。
        float volumeCoeff = exp(-dd * density * rayLength); // 本段透过率。
        vec3 lpvPos = (progress - origin) / max(lpvSize, 1.0); // 体积坐标。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘。
        float fade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴淡出。
        if (fade < 0.01) break; // 体积外停止。
        vec3 sampleColor = textureLod(lpvTexture, lpvPos, 0.0).rgb; // LPV 光色。
        if (vanillaMask) sampleColor *= 1.0; // 原版遮罩由调用方预先乘进纹理。
        vec3 lighting = sampleColor * lpvBrightness * 25.0 * exp(-5.0 * (1.0 - ogxLuminance(sampleColor))); // 参考实现的亮度曲线。
        lighting += handLight * torchAmount * lpvBrightness * 0.04; // 手持光。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// WSR 的空气雾：固定指数步进，阴影图与密度图共同决定每段散射。
vec4 ogxEclipseRaymarchWsrFog(vec3 origin, vec3 endPos, vec2 dither, vec3 lightColor,
    vec3 ambientColor, vec3 averagedAmbient, int sampleCount, sampler3D densityTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float sunPhase,
    float skyPhase, vec3 sunVector, vec3 atmosphereAbsorption)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    vec3 dVWorld = endPos - origin; // 射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    dVWorld *= min(rayLength, 1e6) / max(rayLength, 1e-6); // 距离上限。
    float dL = length(dVWorld) / 8.0; // 每段长度。
    const float expFactor = 11.0; // 指数步长。
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 总透过率。
    vec3 atmosphere = vec3(1.0); // 大气透过率。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float rayL = ogxRayleighPhase(dot(sunVector, rayDir)); // 瑞利相位。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither.y) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.x) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = d * dVWorld + origin; // 当前世界位置。
        float shadow = 1.0; // 阳光阴影。
        vec3 shadowPos = ogxShadowScreenPos(progress, shadowView, shadowProjection); // 投到阴影图。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) shadow = textureLod(shadowTexture, shadowPos.xy, 0.0).x; // 读阴影。
        float density = textureLod(densityTexture, progress, 0.0).r; // 雾密度。
        float coeff = exp(-density * dd * dL); // 本段透过率。
        vec3 indirect = ambientColor * skyPhase; // 天空散射。
        vec3 direct = lightColor * sunPhase * shadow; // 太阳散射。
        vec3 lighting = direct + indirect; // 本段照明。
        color += (lighting - lighting * coeff) * totalAbsorbance; // 累积散射。
        totalAbsorbance *= coeff; // 累积透过率。
        if (totalAbsorbance < 0.01) break; // 足够浓就停。
        vec3 atmosphereCoeff = exp(-atmosphereAbsorption * dd * dL); // 大气吸收。
        vec3 haze = (lightColor * shadow * rayL + averagedAmbient) * (1.0 - atmosphereCoeff); // 空气透视。
        color += haze * atmosphere; // 叠加空气透视。
        atmosphere *= atmosphereCoeff; // 累积大气透过率。
    }
    return vec4(color, totalAbsorbance); // 交回雾。
}

// WSR 水下体积：水吸收、焦散与方向光一起决定水下光柱。
vec4 ogxEclipseWsrWaterVolumetrics(vec3 origin, vec3 endPos, vec2 dither, vec3 ambient,
    vec3 lightSource, vec3 lpv, vec3 waterAbsorption, vec3 dirtScatter, float waterAltitude,
    float sunElevation, float bubbleScale, float phaseScale)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有水体。
    const int sampleCount = 3; // 参考实现的固定三步。
    vec3 dVWorld = endPos - origin; // 射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    dVWorld *= min(rayLength, 1e6) / max(rayLength, 1e-6); // 距离上限。
    vec3 absorbance = vec3(1.0); // 累积吸收。
    vec3 result = vec3(0.0); // 累积颜色。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float vdotl = dot(vec3(0.0, 1.0, 0.0), rayDir); // 参考实现的太阳方向近似。
    float phase = ogxEclipseFogPhase(vdotl) * phaseScale; // 雾相位。
    float thing = -normalize(dVWorld).y; // 垂直方向。
    thing = clamp(thing + 0.333, 0.0, 1.0);
    thing = pow(1.0 - pow(1.0 - thing, 2.0), 2.0) * 15.0; // 参考实现的形状。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定三步。
    {
        float d = (pow(expFactor, float(i) + dither.x) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.y) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = d * dVWorld; // 相机相对位置。
        float distanceFromSurface = max(-(progress.y - waterAltitude), 0.0); // 到水面的距离。
        float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / bubbleScale, 0.0, 1.0)); // 气泡。
        float caustics = max(phase * 0.5 * mix(0.5, 1.5, bubble), phase); // 焦散。
        vec3 sunAbsorbance = exp(-waterAbsorption * (distanceFromSurface / max(abs(vec3(0.0, 1.0, 0.0).y), 1e-6))); // 太阳吸收。
        vec3 waterAbsorbance = exp(-waterAbsorption * (distanceFromSurface + thing)); // 水体吸收。
        vec3 direct = lightSource * phase * caustics * sunAbsorbance; // 直射。
        vec3 indirect = ambient * waterAbsorbance; // 间接。
        vec3 light = (indirect + direct + lpv) * dirtScatter; // 总光。
        vec3 volumeCoeff = exp(-waterAbsorption * length(dd * dVWorld)); // 本段吸收。
        result += (light - light * volumeCoeff) / max(waterAbsorption, vec3(1e-6)) * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积吸收。
    }
    return vec4(result, dot(absorbance, vec3(0.333333))); // 交回水体颜色与透过率。
}

#endif

/*
生成文件：Eclipse 漫反射模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 漫反射补充模块：手持光阴影、方块光合成与手电光。
调用位置：需要复现 Eclipse `diffuse_lighting.glsl` 的程序；Minecraft 光影由
    `/omni-gfx/eclipse_diffuse.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    float shadow = ogxEclipseSsrtHandlightShadows(viewPos, false, lightDir, noise, normal, false,
        modelViewInverse, nearPlane, farPlane, 1.0, depthTex, projection, 10.0, 0.0015, 0.3);
    vec3 flashlight = ogxEclipseCalculateFlashlight(texcoord, viewPos, albedo, normal,
        specularData, false, viewWidth, viewHeight, noiseTex, 0.5, 30.0, 0.2, 0.4, 0.7, 1.0, 0.5, 20.0, 1.0);
设计原因与取舍：
    参考实现直接读 `depthtex2`、`gbufferModelViewInverse` 与手电菜单。库把深度图、矩阵、尺寸与
    手电颜色全部改成显式参数；分支、常数和采样顺序保持参考实现。
    手电的镜头脏污只接噪声纹理参数，不绑定 `noisetex`；这样独立测试与光影可以换纹理。
*/
#ifndef OGX_ECLIPSE_DIFFUSE_INCLUDED
#define OGX_ECLIPSE_DIFFUSE_INCLUDED

// 相机提供投影与裁剪空间换算；数学提供夹紧与线性深度。


// 手持光屏幕空间阴影：沿光线方向在深度图里步进，撞到遮挡就压暗。
// `quality` 为 0 时用十步，否则二十步；步长与参考实现的固定除数相同。
vec2 ogxEclipseDiffuseTexelSize(sampler2D tex) { return vec2(textureSize(tex, 0)); }

float ogxEclipseSsrtHandlightShadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise,
    vec3 normals, bool hand, mat4 modelViewInverse, float nearPlane, float farPlane,
    float renderScale, sampler2D depthTexture, mat4 projection, mat4 projectionInverse,
    float samples, float divisor, float strength)
{
    if (hand) return 1.0; // 手部不投手持光阴影。
    vec3 worldLightDir = normalize(ogxMatrix3MulPoint(mat3(modelViewInverse), lightDir)); // 光方向转世界。
    float NdotL = smoothstep(0.0, 0.2, abs(dot(normals, worldLightDir))); // 法线朝向的软边。
    float shadows = 1.0; // 阴影结果。
    float sampleCount = samples > 10.0 ? 20.0 : 10.0; // 参考实现的质量档。
    float div = samples > 10.0 ? 0.0005 : 0.0015; // 固定步长除数。
    float _near = nearPlane; // 近平面。
    float _far = farPlane * 4.0; // 远平面放大四倍。
    if (depthCheck) // 远景使用远景矩阵。
    {
        _near = nearPlane;
        _far = farPlane;
    }
    vec3 position = ogxToClipSpace3(viewPos, projection); // 起点投到裁剪空间。
    float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.0)) > -_near)
        ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.0); // 射线长度。
    vec3 direction = ogxToClipSpace3(viewPos + lightDir * rayLength, projection) - position; // 裁剪空间方向。
    direction.xyz /= max(max(abs(direction.x) / div, abs(direction.y) / div), 400.0); // 固定步长。
    direction *= 6.0; // 参考实现的步数放大。
    position.xy *= renderScale;
    direction.xy *= renderScale;
    vec3 newPos = position + direction * noise; // 加抖动。
    for (int i = 0; i < int(sampleCount); i++) // 固定步数。
    {
        float samplePos = texelFetch(depthTexture, ivec2(newPos.xy / ogxEclipseDiffuseTexelSize(depthTexture)), 0).r; // 读深度。
        if (samplePos < newPos.z && samplePos > 0.0) // 被遮挡。
        {
            shadows = 0.0;
            break;
        }
        newPos += direction; // 前进一步。
    }
    return clamp(shadows * NdotL, 1.0 - strength, 1.0); // 参考实现的强度夹紧。
}

// 方块光合成：原版光照图曲线、LPV 体积、手持光与手电阴影一起决定最终方块光。
// `lpvSample` 与 `handLight` 由调用方先算好，库只负责曲线与混合。
vec3 ogxEclipseDoBlockLightLighting(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount,
    bool vanillaMask, bool useLpv)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float brightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    brightspot *= brightspot * brightspot; // 三次方。
    float lightCurve = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightCurve *= lightCurve;
    float lightmapCurve = mix(lightCurve, 2.5, brightspot); // 混合曲线。
    vec3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (useLpv) // 有 LPV 时才混合体积。
    {
        if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版遮罩。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
        float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        falloff = 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0); // 参考实现曲线。
        blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), falloff); // 体积外回退。
        blockLight += handLight; // 手持光相加。
    }
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 手电光：把屏幕位置换成手电筒锥，再按距离、圆斑与镜头脏污叠出光斑。
// `specularData` 返回方向与强度，供高光阶段复用。
vec3 ogxEclipseCalculateFlashlight(vec2 texcoord, vec3 viewPos, vec3 albedo, vec3 normal,
    out vec4 specularData, bool hand, float viewWidth, float viewHeight, sampler2D noiseTexture,
    float range, float brightnessFalloff, float size, float red, float green, float blue,
    float brightness, float centerDepth, float time)
{
    float forwardOffset = 0.5; // 参考实现的前向偏移。
    vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0); // 手电在视线左上方。
    vec3 shiftedPlayerPos = shiftedViewPos; // 相机相对位置。
    vec2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - forwardOffset, 1e-7); // 投到屏幕。
    float linearDistance = length(shiftedPlayerPos); // 到手电的距离。
    float shiftedLinearDistance = length(scaledViewPos); // 屏幕距离。
    float lightFalloff = 1.0 - clamp(1.0 - linearDistance / range, -0.999, 1.0); // 距离衰减。
    lightFalloff = max(exp(-10.0 * brightnessFalloff * lightFalloff), 0.0); // 指数衰减。
    float specular = lightFalloff * exp2(-7.0 * shiftedLinearDistance * shiftedLinearDistance) * brightness; // 高光强度。
    specularData = vec4(normalize(shiftedPlayerPos), specular); // 方向与强度。
    float projectedCircle = clamp(1.0 - shiftedLinearDistance * size, 0.0, 1.0); // 圆斑。
    float lensDirt = textureLod(noiseTexture, scaledViewPos * 0.2 + 0.1, 0.0).b; // 镜头脏污。
    float lensShape = (pow(abs(pow(abs(projectedCircle - 1.0), 2.0) * 2.0 - 0.5), 2.0) + lensDirt * 0.2) * 10.0; // 光斑形状。
    float offsetNdotL = clamp(dot(-normal, normalize(shiftedPlayerPos)), 0.0, 1.0); // 法线朝向。
    vec3 diffuse = vec3(1.0) * lightFalloff * offsetNdotL * pow(1.0 - pow(1.0 - projectedCircle, 2.0), 2.0) * lensShape * brightness; // 漫反射光斑。
    if (hand) // 手部不发光。
    {
        diffuse = vec3(0.0);
        specularData = vec4(0.0);
    }
    return diffuse * vec3(red, green, blue); // 按手电颜色输出。
}

#endif

/*
生成文件：Eclipse 场景模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 场景补充模块：受伤与入水画面效果、场景控制参数、末地雾阴影。
调用位置：需要复现 Eclipse `gameplay_effects.glsl`、`scene_controller.glsl` 与 `end_fog.glsl` 的程序；
    Minecraft 光影由 `/omni-gfx/eclipse_scene.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    ogxEclipseApplyGameplayEffects(color, texCoord, 0.5, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, false, false,
        sceneTex, noiseTex, 1.777, 20.0, 1.0, 1.0, 0.0);
    ogxEclipseApplySceneControllerParameters(...);
    float shadow = ogxEclipseGetEndFogShadow(worldPos, lightPos, fogShapeTex, 1.0);
设计原因与取舍：
    参考实现直接读血量、眼在水中、`colortex7` 与末地雾密度纹理。库把数值、纹理与尺寸改成显式参数，
    分支、常数与采样顺序保持不变；场景控制只是把输入默认值抄到输出，参数表来自菜单来源。
*/
#ifndef OGX_ECLIPSE_SCENE_INCLUDED
#define OGX_ECLIPSE_SCENE_INCLUDED

// 数学提供夹紧与取模；颜色提供亮度权重。

// 场景控制参数：没有自定义触发器时，把所有天气与云层参数原样输出。
void ogxEclipseApplySceneControllerParameters(float smallCumulusCoverage, float smallCumulusDensity,
    float largeCumulusCoverage, float largeCumulusDensity, float altostratusCoverage,
    float altostratusDensity, float cirrusCoverage, float cirrusDensity,
    out float outSmallCoverage, out float outSmallDensity, out float outLargeCoverage,
    out float outLargeDensity, out float outAltostratusCoverage, out float outAltostratusDensity,
    out float outCirrusCoverage, out float outCirrusDensity, out float fogA, out float fogB)
{
    outSmallCoverage = smallCumulusCoverage; // 小积云覆盖。
    outSmallDensity = smallCumulusDensity; // 小积云密度。
    outLargeCoverage = largeCumulusCoverage; // 大积云覆盖。
    outLargeDensity = largeCumulusDensity; // 大积云密度。
    outAltostratusCoverage = altostratusCoverage; // 高层云覆盖。
    outAltostratusDensity = altostratusDensity; // 高层云密度。
    outCirrusCoverage = cirrusCoverage; // 卷云覆盖。
    outCirrusDensity = cirrusDensity; // 卷云密度。
    fogA = 1.0; // 均匀雾倍率。
    fogB = 1.0; // 云雨雾倍率。
}

// 末地雾阴影：沿光源方向取三个密度样本，再按指数衰减成阴影。
float ogxEclipseGetEndFogShadow(vec3 worldPos, vec3 lightPos, sampler3D fogShape, float endStormDensity)
{
    float shadow = 0.0; // 密度累加。
    for (int i = 0; i < 3; i++) // 三个样本。
    {
        vec3 samplePos = worldPos - lightPos * (0.01 + pow(float(i), 0.75) * 0.25); // 参考实现的偏移。
        shadow += textureLod(fogShape, samplePos, 0.0).r * endStormDensity; // 取雾密度。
    }
    return clamp(exp2(shadow * -10.0), 0.0, 1.0); // 参考实现的衰减。
}

// 受伤、入水与着火画面效果：先算屏幕扭曲，再按血量与伤害上色。
// 开关用布尔参数表示，避免库读取菜单宏；未开启的分支保持零贡献。
void ogxEclipseApplyGameplayEffects(inout vec3 color, vec2 texcoord, float noise,
    float currentHealth, float maxHealth, float oneHeart, float threeHeart,
    float criticalDamage, float minorDamage, bool lowHealthEffect, bool damageTakenEffect,
    bool waterOnCamera, bool fireDistort, float exitWater, float enterWater, float exitLava,
    float isEyeInWater, sampler2D sceneTexture, sampler2D noiseTexture, float aspectRatio,
    float frameTime, float motionAmount, float fireStrength)
{
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float distortMask = 0.0; // 屏幕扭曲量。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    if (lowHealthEffect || damageTakenEffect) // 低血量与受伤。
    {
        float heartBeat = pow(sin(frameTime * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1; // 心跳。
        float damageDistortion = vignette * noise * heartBeat * threeHeart; // 低血量扭曲。
        damageDistortion = mix(damageDistortion, vignette * (0.5 + noise), criticalDamage) * motionAmount; // 暴击扭曲。
        distortMask = isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion; // 死亡扭曲。
    }
    if (waterOnCamera) // 出水与入水。
    {
        if (exitWater > 0.0) // 镜头带水。
        {
            vec3 scale = vec3(1.0, 1.0, 0.0);
            bool eyeInWater = isEyeInWater == 1.0;
            scale.xy = (eyeInWater ? vec2(0.3) : vec2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * vec2(aspectRatio, 1.0);
            scale.z = eyeInWater ? 0.0 : exitWater;
            float waterDrops = textureLod(noiseTexture, (texcoord - vec2(0.0, scale.z)) * scale.xy, 0.0).r; // 水珠噪声。
            if (eyeInWater) waterDrops = 0.0;
            if (isEyeInWater == 0.0 && exitWater > 0.0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3; // 出水水珠。
            distortMask = max(distortMask, waterDrops);
        }
        if (enterWater > 0.0) // 入水波纹。
        {
            vec2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0 - sqrt(1.0 - enterWater)));
            float waterSplash = textureLod(noiseTexture, zoomTC * vec2(aspectRatio, 1.0), 0.0).r * (1.0 - enterWater);
            distortMask = max(distortMask, waterSplash);
        }
    }
    if (fireDistort && exitLava > 0.0) // 着火扭曲。
    {
        vec2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - exitLava, 2.0));
        float flameDistort = textureLod(noiseTexture, zoomin * vec2(aspectRatio, 1.0) - vec2(0.0, frameTime * 0.3), 0.0).b
            * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * fireStrength * exitLava;
        distortMask = max(distortMask, flameDistort);
    }
    vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask); // 以中心缩放。
    vec3 distortedColor = textureLod(sceneTexture, zoomUV, 0.0).rgb; // 读扭曲后的场景。
    if ((waterOnCamera && exitWater > 0.01) || (fireDistort && exitLava > 0.01)) color = distortedColor; // 水或火覆盖时替换场景。
    if (lowHealthEffect || damageTakenEffect) // 颜色效果。
    {
        vec3 distortedLuma = vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07)); // 红色亮度。
        if (lowHealthEffect)
        {
            float colorLuma = dot(color, vec3(0.21, 0.72, 0.07));
            vec3 lumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 红色边缘。
            color = mix(color, lumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart)); // 低血量上色。
        }
        if (damageTakenEffect)
        {
            color = mix(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 小伤害。
            color = mix(color, distortedLuma, sqrt(criticalDamage)); // 暴击伤害。
        }
        if (isDead) color = distortedLuma * 0.35; // 死亡画面。
    }
}

#endif

vec3 ogxProfileTone(vec3 color)
{
    return ogxAces(color, true) + ogxAgxConfigurable(color);
}

vec3 ogxProfileSurface()
{
    return ogxItxTextureLighting(vec3(0.5), 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, vec3(1.0), 0, true);
}

void main()
{
    // 空入口只用于链接验证；函数体全部由编译器检查。
    vec3 color = ogxProfileTone(vec3(0.18));
    gl_FragColor = vec4(color, 1.0);
}
