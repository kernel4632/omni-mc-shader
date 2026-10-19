/*
共用纯计算：照 iterationT `Lib/Utilities.glsl` 一比一移植，外加全管线共用的内部常数。
调用位置：每个绘制主体在 `common/uniforms.glsl` 之后引入；效果文件也可以直接引入。
可复制示例：
    `vec3 c = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb) * MAIN_OUTPUT_FACTOR;`  读回场景线性亮度
    `compositeOutput1 = vec4(LinearToCurve(color / MAIN_OUTPUT_FACTOR), 1.0);`              按管线单位写回
    `vec3 n = DecodeNormal(data.rg);`                                                      解八面体法线
设计原因与取舍：
    函数名、宏名、常数、写法全部保持原名原样，各效果文件按原名互相调用，便于逐行对照原程序。
    `PI`、`saturate` 这类宏和函数名不带前缀，所以别的文件不能再定义同名宏。
    原文件开头的版本号宏只是菜单装饰，按移植合同不移植。
    `MAIN_OUTPUT_FACTOR` 是整条管线的亮度单位：中间画面存 `LinearToCurve(x / 2048)`，最终阶段再乘回。
    单位链路任何一处不一致都会整片过曝，所以这些常数只在这里定义一次。
*/
#ifndef OMNI_MATH_INCLUDED // 只引入一次，避免宏和函数重复定义。
#define OMNI_MATH_INCLUDED // 置上标记。
// 纯数学函数放在通用库；这里只保留引擎常数与转发。
#include "/gfx/math.glsl"

// 本文件的 `BicubicBlurTexture` 直接读 `noisetex`，所以自己先引入加载器输入声明。
// 为什么放在文件内部而不是要求调用方先引入：引用顺序写错时只会报“未声明的标识符”，
// 很难一眼看出是顺序问题；这里自己保证一次，效果文件怎么排都能编译。
#include "/common/uniforms.glsl"

// --- 内部常数：原 `Settings.glsl` 里不进菜单的共用常数 ---
#define MAIN_OUTPUT_FACTOR 2048.0 // 场景亮度单位：中间画面颜色先除以它再做四次方根编码。
#define EXPOSURE_OUTPUT_FACTOR 128.0 // 曝光统计用的亮度单位。
#define ANIMATION_SPEED 1.0 // 植物摆动等动画速度倍率。
#define WATER_REFRACT_IOR 1.2 // 水面折射率，比真实水的一点三三小，避免折射拉伸过大。
#define CAUSTICS_TEX_RESOLUTION 500.0 // 焦散法线方块边长，单位像素，七号画面左下角。

// --- 数学常数：圆周率相关与两个低差异序列用的无理数 ---
#define PI           3.14159265359 // 圆周率。
#define hPI          1.57079632679 // 半个圆周率。
#define TAU          6.28318530718 // 两倍圆周率。
#define rPI          0.31830988618 // 圆周率的倒数。
#define goldenRatio  1.61803398875 // 黄金比，时间噪声逐帧偏移用。
#define plasticRatio 1.32471795724 // 塑料数，二维低差异序列用。
#define goldenAngle  2.39996322973 // 黄金角，螺旋采样用。

// --- 常用小工具宏 ---
// 原程序还有 `min3`，本项目没有一处调用，按“不留无人使用的代码”删掉，其余保持原名原样。
#define max3(a, b, c)                   max(a, max(b, c)) // 三个数取最大。
#define min4(a, b, c, d)                min(min(a, b), min(c, d)) // 四个数取最小。
#define max4(a, b, c, d)                max(max(a, b), max(c, d)) // 四个数取最大。
#define min5(a, b, c, d, e)             min(a, min(b, min(c, min(d, e)))) // 五个数取最小。
#define max5(a, b, c, d, e)             max(a, max(b, max(c, max(d, e)))) // 五个数取最大。
#define min9(a, b, c, d, e, f, g, h, i) min(a, min(b, min(c, min(d, min(e, min(f, min(g, min(h, i)))))))) // 九个数取最小，三乘三邻域用。
#define max9(a, b, c, d, e, f, g, h, i) max(a, max(b, max(c, max(d, max(e, max(f, max(g, max(h, i)))))))) // 九个数取最大。
#define saturate(x)                     clamp(x, 0.0, 1.0) // 夹到零到一。
#define curve(x)                        x * x * (3.0 - 2.0 * x) // 平滑曲线；原样不加括号，调用方须自己给参数加括号。
#define Luminance(c)                    dot(c, vec3(0.2125, 0.7154, 0.0721)) // 感知亮度，权重照原程序。
#define fsign(x)                        uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3f800000u) // 位运算取正负一，零也按正号。
#define fsqrt(x)                        intBitsToFloat(0x1fbd1df5 + (floatBitsToInt(x) >> 1)) // 位运算近似平方根，速度快、精度低。

// --- 区间重映射 ---
// 把落在 `e0` 到 `e1` 的值映射到零到一并夹紧。
float remapSaturate(float x, float e0, float e1){ return gfx_remapSaturate(x, e0, e1); }

// --- 角度近似 ---
// 两参数反正切：返回从横轴到向量的角度，横分量为零时单独处理避免除零。
float atan2(vec2 v){ return gfx_atan2(v); }

// 快速反余弦近似：一次多项式乘近似平方根，精度够光照用。
float facos(float x){ return gfx_facos(x); }

// --- 颜色曲线：伽马与管线四次方根编码 ---
// 线性转伽马空间，指数二点二。
vec3 LinearToGamma(vec3 c){ return gfx_LinearToGamma(c); }

// 伽马空间转线性，贴图颜色进入光照前用。
vec3 GammaToLinear(vec3 c){ return gfx_GammaToLinear(c); }

// 管线编码：取四次方根，让十六位定点画面在暗部有足够精度。
float LinearToCurve(float c){ return gfx_LinearToCurve(c); }

// 管线解码：四次方，用两次平方代替幂函数更快。
float CurveToLinear(float c){ return gfx_CurveToLinear(c); }

// 三维版本的管线编码。
vec3 LinearToCurve(vec3 c){ return gfx_LinearToCurve(c); }

// 三维版本的管线解码。
vec3 CurveToLinear(vec3 c){ return gfx_CurveToLinear(c); }

// 夜视色偏：暗处颜色向偏蓝的亮度混一半，模拟人眼暗视觉。
void DoNightEye(inout vec3 c){ gfx_DoNightEye(c); }

// --- 打包：把两个数塞进一个通道 ---
// 两个零到一的数各取八位，拼进一个十六位通道。
float Pack2x8(vec2 x){ return gfx_Pack2x8(x); }

// 从十六位通道拆回两个八位数。
vec2 Unpack2x8(float x){ return gfx_Unpack2x8(x); }

// 两个零到一的数各取十六位，按位拼进一个三十二位浮点通道。
float Pack2x16(vec2 x){ return gfx_Pack2x16(x); }

// 从三十二位浮点通道按位拆回两个数。
vec2 Unpack2x16(float x){ return gfx_Unpack2x16(x); }

// --- 法线编码 ---
// 解码法线贴图：三通道和接近一点五才认为是有效法线，否则按朝外法线处理。
vec3 DecodeNormalTex(vec3 texNormal){ return gfx_DecodeNormalTex(texNormal); }

// 八面体编码的折叠：把下半球翻到外圈。
vec2 OctWrap(vec2 v){ return gfx_OctWrap(v); }

// 单位法线压成两个零到一的数，存进画面的两个通道。
vec2 EncodeNormal(vec3 n){ return gfx_EncodeNormal(n); }

// 从两个通道解回单位法线，与上面互逆。
vec3 DecodeNormal(vec2 en){ return gfx_DecodeNormal(en); }

// --- 光照模型 ---
// 法线分布：微表面朝向半程向量的比例，粗糙度越大高光越散。
float D_Walter(float NdotH, float roughness){ return gfx_D_Walter(NdotH, roughness); }

// 菲涅尔近似：掠射角反射更强，五次方曲线。
float F_Schlick(float VdotH, float f0, float f90){ return gfx_F_Schlick(VdotH, f0, f90); }

// 可见性项：微表面互相遮挡的比例，已经乘了入射余弦。
float V_Schlick(float NdotL, float NdotV, float roughness){ return gfx_V_Schlick(NdotL, NdotV, roughness); }

// 漫反射：迪士尼模型，粗糙表面在掠射角更亮。
float Fd_Burley(vec3 n, vec3 v, vec3 l, float roughness){ return gfx_Fd_Burley(n, v, l, roughness); }

// 高光：菲涅尔、可见性、分布三项相乘。
float SpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0){ return gfx_SpecularGGX(n, v, l, roughness, f0); }

// --- 黑体颜色：按色温给出光源颜色，火把色温选项用 ---
// 普朗克轨迹的分段多项式拟合，先求色度坐标再转线性显示颜色。
vec3 Blackbody(float temperature){ return gfx_Blackbody(temperature); }

// --- 射线求交 ---
// 射线与过原点的平面求交；几乎平行时返回极远处的点。
vec3 RayPlaneIntersection(vec3 ori, vec3 dir, vec3 normal){ return gfx_RayPlaneIntersection(ori, dir, normal); }

// 射线与球心在原点的球求交，返回进出两个距离；不相交时返回近大远小的无效值。
vec2 RaySphereIntersection(vec3 ori, vec3 dir, float radius){ return gfx_RaySphereIntersection(ori, dir, radius); }

// --- 散射相位函数 ---
// 瑞利相位：小粒子散射，前后对称。
float RayleighPhaseFunction(float nu){ return gfx_RayleighPhaseFunction(nu); }

// 米氏相位：大粒子散射，`g` 越大越偏向前方。
float MiePhaseFunction(float g, float nu){ return gfx_MiePhaseFunction(g, nu); }

// --- 抖动噪声 ---
// 交错梯度噪声：按像素位置给出均匀分布的伪随机数。
float InterleavedGradientNoise(vec2 c){ return gfx_InterleavedGradientNoise(c); }

// 二乘二拜尔矩阵：下面更大的矩阵由它递归组合。
float bayer2(vec2 a){ return gfx_bayer2(a); }

float bayer4(vec2 a){ return gfx_bayer4(a); }
float bayer8(vec2 a){ return gfx_bayer8(a); }
float bayer64(vec2 a){ return gfx_bayer64(a); }

// --- 三次采样：原程序在两种时间抗锯齿里各写一份且逐字相同，按移植合同合并到这里一份 ---
// 五次采样近似卡特穆尔-罗姆三次插值，放大历史画面时比双线性更锐利。
// 为什么只采五次：四角的权重很小，省掉后画面差别看不出，采样数从九次降到五次。
vec3 BicubicTexture(sampler2D texSampler, vec2 coord, vec2 texSize){ return gfx_BicubicTexture(texSampler, coord, texSize); }

// --- 噪声贴图三次模糊：原程序地形顶点与阴影顶点各写一份且逐字相同，合并到这里一份 ---
// 调用前提：`common/uniforms.glsl` 已引入，函数固定读取六十四像素的 `noisetex`，`texSampler` 参数只为保持原签名。
// 泛光版与云影版参数和返回类型不同，分别留在 `effects/color/bloom.glsl` 与 `effects/cloud/shadow.glsl`，见移植合同偏离记录。
vec4 BicubicBlurTexture(sampler2D texSampler, vec2 coord){ return gfx_BicubicBlurTexture(texSampler, coord); }

// --- Omni 额外函数：原程序没有，保留文件仍在使用 ---
// 安全归一化：长度为零时普通归一化会得到无穷，光传播体积计算阶段用它算天体方向。
vec3 omniNormalize(vec3 vector){ return gfx_omniNormalize(vector); }
// 颜色转色相、饱和度、明度：体积光染色与矿石/纹饰自发光都要拆出这三个量，来源 Eclipse `lib/hsv.glsl`。
// 为什么放共用文件：两处以上效果（体积光、自发光矿石/纹饰）都要用，复制一份会与别处不一致。
vec3 omniRgbToHsv(vec3 c){ return gfx_omniRgbToHsv(c); }
#endif // 文件守卫结束。
