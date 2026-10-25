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
#include "/omni-gfx/math.glsl"
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