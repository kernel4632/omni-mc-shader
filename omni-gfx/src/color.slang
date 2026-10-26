/*
Omni 通用图形库颜色模块：线性颜色、亮度、伽马、强光压缩、黑边与调色。
调用位置：任何需要把线性高动态范围颜色映射到显示空间或做最终调色的程序；
    Minecraft 光影由 `/omni-gfx/color.glsl` 引入，引入后数学模块同时可用。
可复制示例：
    float3 a = ogxAces(linearColor, true); // 影院标准压缩。
    float3 b = ogxAgx(linearColor, 13.0, true); // 宽色域压缩。
    float3 c = ogxTonemapNone(linearColor); // 只做伽马编码。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀。
    伽马使用二点二近似，与旧 `shaders/gfx/color.glsl` 一致，不在这里做分段标准曲线。
    矩阵乘法展开成三列乘分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
*/
#ifndef OGX_COLOR_INCLUDED
#define OGX_COLOR_INCLUDED

// 数学模块提供亮度权重、夹紧与编码函数。
#include "math.slang"

// 三列矩阵乘向量：GLSL 的矩阵乘向量就是三列分别乘分量再相加，这里照同一顺序展开。
float3 ogxApplyColumns(float3 c0, float3 c1, float3 c2, float3 v)
{
    return c0 * v.x + c1 * v.y + c2 * v.z;
}

// 向量乘矩阵：旧库把颜色放在左边乘矩阵，结果每个分量是向量与一列的点积。
float3 ogxApplyRows(float3 c0, float3 c1, float3 c2, float3 v)
{
    return float3(dot(v, c0), dot(v, c1), dot(v, c2));
}

// 线性颜色转显示伽马空间；二点二伽马，和原管线一致。
float3 ogxLinearToGamma2(float3 color) { return pow(color, float3(1.0 / 2.2)); }

// 显示伽马空间转回线性，与上一函数互为逆运算。
float3 ogxGammaToLinear2(float3 color) { return pow(color, float3(2.2)); }

// ACES 压缩曲线里的有理式：中间亮度拉直，两端压住。
float3 ogxRrtOdtFit(float3 value)
{
    float3 a = value * (value + 0.0245786) - 0.000090537;
    float3 b = value * (value + 0.4329510) + 0.238081;
    return a / b;
}

// 阿布尼校正矩阵的三列，抵消加亮造成的色相偏移。
static const float3 OGX_ABNEY_0 = float3(0.99999976, -1.26657e-7, -1.29064e-9);
static const float3 OGX_ABNEY_1 = float3(1.67316e-8, 0.99999976, -5.32026e-9);
static const float3 OGX_ABNEY_2 = float3(-0.00725587, 6.47740e-9, 1.00725580);

// 转 AP1 工作色域的三列。
static const float3 OGX_AP1_0 = float3(0.59719, 0.35458, 0.04823);
static const float3 OGX_AP1_1 = float3(0.07600, 0.90834, 0.01566);
static const float3 OGX_AP1_2 = float3(0.02840, 0.13383, 0.83777);

// 从 AP1 转回显示色域的三列。
static const float3 OGX_AP1_BACK_0 = float3(1.60475, -0.53108, -0.07367);
static const float3 OGX_AP1_BACK_1 = float3(-0.10208, 1.10813, -0.00605);
static const float3 OGX_AP1_BACK_2 = float3(-0.00327, -0.07276, 1.07602);

// 影院标准 ACES 近似：提亮、转工作色域、压缩、再转回显示色域。
// `abney` 为真时附加一次很小的色域修正，抵消加亮造成的色相偏移。
float3 ogxAces(float3 color, bool abney)
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

// 参考包的 `ACES` 默认开启 Abney 效应校正；单参数重载让旧调用点保持原签名。
float3 ogxAces(float3 color) { return ogxAces(color, true); }

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

// 无压缩：Eclipse 的 `no_tonemapper` 原样返回，不做伽马编码；伽马由最终输出阶段处理。
float3 ogxTonemapNone(float3 color) { return color; }

// Eclipse 的 `LinearTosRGB`：亮部先把颜色夹到零到一，再走幂曲线；用于需要稳定输出的场合。
float3 ogxLinearToSrgbClamped(float3 color)
{
    float3 x = color * 12.92;
    float3 y = 1.055 * pow(clamp(color, float3(0.0), float3(1.0)), float3(1.0 / 2.4)) - 0.055;
    float3 result = color;
    result.r = color.r < 0.0031308 ? x.r : y.r;
    result.g = color.g < 0.0031308 ? x.g : y.g;
    result.b = color.b < 0.0031308 ? x.b : y.b;
    return result;
}

// 线性到标准 sRGB 的分段编码：暗部走直线，亮部走二点四分之一幂，与二点二近似不同。
// 直接按 Eclipse `linearToSRGB` 的 mix 写法，不做额外夹紧：阈值外两段会自动选中正确的一侧。
float3 ogxLinearToSrgb(float3 color)
{
    float3 low = color * 12.92; // 暗部直线段。
    float3 high = pow(color, float3(1.0 / 2.4)) * 1.055 - 0.055; // 亮部幂曲线。
    return lerp(low, high, step(float3(0.0031308), color)); // 逐通道按阈值选择。
}

// 经济版电影曲线：一条有理式，成本低于 ACES 拟合，观感更硬、更亮。
float3 ogxTonemapAcesFilm(float3 color)
{
    float3 x = color * 0.9; // 先压一点曝光。
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.95) + 0.12); // 分子分母都是二次式。
}

// `Hejl` 2015 胶片曲线：先加一点偏移让纯黑离开零，再用两个有理式的比值压肩部。
float3 ogxTonemapHejl(float3 color)
{
    float4 vh = float4(color * 0.85, 3.0); // 三个颜色通道加一个白点参考。
    float4 va = 1.75 * vh + 0.05; // 肩部斜率随亮度增加。
    float4 vf = ((vh * va + 0.004) / (vh * (va + 0.55) + 0.0491)) - 0.0821 + 0.000633604888; // 有理式压缩，末尾常数把黑点抬回零。
    return vf.xyz / vf.w; // 用白点参考归一，最亮处回到一。
}

// `Hable` 胶片曲线：六个常数分别控制肩部、线性段与趾部，白点十一做归一。
float3 ogxTonemapHable(float3 color)
{
    float3 x = color * 2.0; // 先放大两倍，让中间灰落在曲线中段。
    float3 mapped = ((x * (0.6 * x + 0.1 * 0.5) + 0.5 * 0.01) / (x * (0.6 * x + 0.5) + 0.5 * 0.3)) - 0.01 / 0.3; // 肩部强度零点六、线性强度零点五、线性角度零点一、趾部强度零点五、趾部两项零点零一与零点三。
    float w = 11.0; // 白点。
    float white = ((w * (0.6 * w + 0.1 * 0.5) + 0.5 * 0.01) / (w * (0.6 * w + 0.5) + 0.5 * 0.3)) - 0.01 / 0.3; // 同一条曲线在白点处的值。
    return mapped / white; // 归一后最亮处正好到一。
}

// `Reinhard` 简单曲线：先放大一点六六倍再除以一加自身，暗部提得最明显。
float3 ogxTonemapReinhard(float3 color)
{
    float3 x = color * 1.66; // 放大让中间灰更亮。
    return x / (1.0 + x); // 双曲线压缩，结果永远不会超过一。
}

// `Lottes` 2016 曲线：指数控制对比度，肩部由输入中间灰与显示白点反推。
// 为什么斜率和偏移写成普通变量：它们由幂函数算出，GLSL 的常量初始化不保证能折叠。
float3 ogxTonemapLottes(float3 color)
{
    float a = 1.6; // 对比度指数。
    float d = 0.977; // 肩部指数。
    float hdrMax = 8.0; // 输入白点。
    float midIn = 0.23; // 输入中间灰。
    float midOut = 0.267; // 输出中间灰。
    float b = (-pow(midIn, a) + pow(hdrMax, a) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut); // 肩部斜率。
    float c = (pow(hdrMax, a * d) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, a * d) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut); // 肩部偏移。
    return pow(color, float3(a)) / (pow(color, float3(a * d)) * b + c); // 两段幂函数之比。
}

// `Uchimura` 2017 曲线：分成趾部、线性段与肩部三截，再用平滑权重拼接。
// 参考实现把平滑曲线的两个边界写反了，那样权重会出现负数；这里按边界在前的正确顺序写。
float3 ogxTonemapUchimura(float3 color)
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
    float3 w0 = 1.0 - smoothstep(float3(0.0), float3(mid), color); // 趾部权重。
    float3 w2 = step(float3(s0), color); // 肩部权重。
    float3 w1 = 1.0 - w0 - w2; // 线性段权重，三者之和为一。
    float3 toe = mid * pow(color / mid, float3(black)); // 趾部幂曲线。
    float3 shoulder = peak - (peak - s1) / (1.0 + cp * (color - s0)); // 肩部有理曲线，越亮越贴近显示上限。
    float3 linear = mid + contrast * (color - mid); // 中间直线段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, float3(0.0), float3(1.0)); // 三段按权重拼接并夹紧。
}

// `Xonk` 曲线：先抬高三成伽马，再用一条有理式压肩部，暗部比 `Reinhard` 更亮。
// 它是一条独立拟合，和 `ACES`、`AgX`、`Reinhard` 都不是同一条曲线，不能互相替代。
float3 ogxTonemapXonk(float3 color)
{
    color = pow(color, float3(1.3)); // 先抬伽马，暗部细节更容易看见。
    return color / (0.333 + color); // 有理式软肩，最亮处趋近于一。
}

// 十六位打包值拆成两个分量：按整数与小数部分各取一次，绕开位运算。
// 参考实现用它存放方块贴图坐标；与 `ogxUnpack2x16` 的区别是这里不依赖浮点位模式，
// 因此数值可以跨后端逐位复现。`value` 必须落在零到一之间。
float2 ogxDecodeVec2x16(float value)
{
    const float2 constant1 = 4294967294.0 / float2(65536.0, 4294967295.0); // 两个分量的步长倒数。
    const float constant2 = 65536.0 / 65535.0; // 补回零到一的上界误差。
    return fract(value * constant1) * constant2; // 先取小数部分再缩放。
}

// 黑边：按目标宽高比在画面上下或左右画黑边，返回该像素是否落在画面内。
float ogxBlackBar(float2 coord, float aspect, float targetRatio)
{
    if (targetRatio == 0.0)
    {
        return 1.0;
    }
    float2 aCoord = abs(coord - 0.5) * 2.0;
    float width = min(targetRatio / aspect, 1.0);
    float height = min(aspect / targetRatio, 1.0);
    return step(aCoord.x, width) * step(aCoord.y, height);
}

// 浦肯野效应：亮度低于阈值时把颜色混向偏蓝的暗视觉，越暗混入越多。
float3 ogxPurkinje(float3 color, float threshold, float strength)
{
    float luminance = ogxLuminance(color);
    float mixAmount = clamp((threshold - luminance) * strength / threshold, 0.0, 1.0);
    return lerp(color, luminance * float3(0.7777, 1.0004, 1.6190), mixAmount);
}

// 白平衡：把调用方给的色温颜色乘在线性颜色上，中性时颜色为一、不改动。
float3 ogxWhiteBalance(float3 color, float3 tint) { return color * tint; }

// 高级调色：白光裁剪、亮度伽马与饱和度，全部在线性空间处理后再回显示空间。
float3 ogxAdvancedColor(float3 color, float lumaGamma, float whiteClip, float saturation, float gamma)
{
    color = ogxGammaToLinear2(color);
    color = pow(length(color), 1.0 / lumaGamma) * normalize(color + 1e-20);
    color = clamp(color * (1.0 + whiteClip), float3(0.0), float3(1.0));
    color = lerp(color, float3(ogxLuminance(color)), float3(1.0 - saturation));
    return clamp(pow(color, float3((1.0 / 2.2) / gamma)), float3(0.0), float3(1.0));
}

// 色相、饱和度、明度转回颜色，与数学模块的 `ogxRgbToHsv` 互逆。
// HSV 转 RGB：照 Eclipse `hsv.glsl` 的 K 向量写法，色彩环由 fract 与绝对值折叠。
float3 ogxHsvToRgb(float3 color)
{
    const float4 K = float4(3.0, 2.0, 1.0, 9.0) / 3.0;
    float3 p = abs(fract(color.xxx + float3(K.x, K.y, K.z)) * 6.0 - float3(K.w, K.w, K.w));
    return color.z * lerp(float3(K.x, K.x, K.x), ogxSaturate(p - float3(K.x, K.x, K.x)), color.y);
}

// sRGB 到线性：Eclipse `util.glsl` 的分段标准曲线，暗部除以十二点九二，亮部走二点四幂。
float3 ogxSrgbToLinear(float3 s)
{
    return lerp(s / 12.92,
        pow(0.947867 * s + 0.0521327, float3(2.4)),
        step(float3(0.04045), s));
}

// sRGB 到线性：三次多项式近似，Eclipse 的 `toLinear` 使用这一条更便宜的曲线。
float3 ogxSrgbToLinearApprox(float3 s) { return s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878); }

// Eclipse 的亮度权重：旧电视标准 0.299/0.587/0.114，和库默认的现代权重不同。
// 单独成函数，避免把两种颜色空间混进同一个 `ogxLuminance`。
// 亮度权重：Eclipse 的 `luma` 在场景亮度里用 Rec.601 系数。
float ogxLuminanceRec601(float3 color) { return dot(color, float3(0.299, 0.587, 0.114)); }

// Eclipse `curve(float3)`：软肩曲线 `1 - x/(1+x)`，与 iterationT 的宏 `curve` 不是同一条曲线。
// 单独命名，避免和宿主层已有的 `curve` 宏展开冲突。
float3 ogxEclipseCurve(float3 x) { return 1.0 - x / (1.0 + x); }

// Eclipse 全范围 Reinhard：白点 10、提亮 0.5，保留完整有理式。
float3 ogxTonemapReinhardFull(float3 color)
{
    float whitepoint = 10.0; // 参考实现固定白点。
    float lighten = 0.5; // 参考实现固定提亮量。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Eclipse 可编辑 Reinhard：先把颜色抬 1.2 次方，再用更低的提亮 0.333。
float3 ogxTonemapReinhardEdit(float3 color)
{
    color = pow(color, float3(1.2)); // 抬暗部，保持高光不动。
    float whitepoint = 10.0; // 与全范围版相同的白点。
    float lighten = 0.333; // 更低的提亮量，画面更亮。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Reinhard-Jodie：同时算亮度压缩与逐通道压缩，再按逐通道结果混回去。
float3 ogxTonemapReinhardJodie(float3 color)
{
    color *= 1.5; // 参考实现的曝光抬升。
    float3 tonemapLuminance = color / (1.0 + dot(color, float3(0.21, 0.72, 0.07))); // 保色相的亮度压缩。
    float3 tonemapRgb = color / (1.0 + color); // 逐通道压缩，高光更容易去饱和。
    return lerp(tonemapLuminance, tonemapRgb, tonemapRgb * 0.8 + 0.2); // 亮部更多采用逐通道结果。
}

// Eclipse 的 AgX look：保留参考的偏移、斜率与幂变量，默认零偏移、单位斜率与幂，只把饱和度推到 1.25。
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
float3 ogxToneMapAgxMerlin(float3 color)
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

// Eclipse 的 Uchimura 指数肩部版：肩部用 exp，参考实现保留反向 smoothstep 参数顺序。
float3 ogxTonemapUchimuraExp(float3 x, float P, float a, float m, float l, float c, float b)
{
    float l0 = ((P - m) * l) / a; // 线性段折算长度。
    float s0 = m + l0; // 肩部起点。
    float s1 = m + a * l0; // 肩部终点。
    float c2 = (a * P) / (P - s1); // 肩部曲率。
    float cp = -c2 / P; // 指数肩部用的负曲率。
    float3 w0 = 1.0 - smoothstep(x, float3(0.0), float3(m)); // 保持参考实现的参数顺序，不改成正确顺序。
    float3 w2 = step(m + l0, x); // 肩部权重。
    float3 w1 = 1.0 - w0 - w2; // 线性段权重。
    float3 toe = m * pow(x / m, float3(c)) + b; // 趾部幂曲线。
    float3 shoulder = P - (P - s1) * exp(cp * (x - s0)); // 指数肩部。
    float3 linear = m + a * (x - m); // 线性段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, float3(0.0), float3(1.0)); // 三段拼接。
}

// Eclipse 的 Uchimura 修改版：肩部改成 smoothstep 曲线，其余参数与指数版相同。
float3 ogxTonemapUchimuraModified(float3 x, float P, float a, float m, float l, float c, float b)
{
    float l0 = ((P - m) * l) / a; // 线性段折算长度。
    float s0 = m + l0; // 肩部起点。
    float s1 = m + a * l0; // 肩部终点。
    float c2 = (a * P) / (P - s1); // 肩部曲率。
    float cp = c2 / P; // 曲线肩部的正曲率。
    float3 w0 = 1.0 - smoothstep(x, float3(0.0), float3(m)); // 保持参考实现的参数顺序。
    float3 w2 = step(m + l0, x); // 肩部权重。
    float3 w1 = 1.0 - w0 - w2; // 线性段权重。
    float3 toe = m * pow(x / m, float3(c)) + b; // 趾部幂曲线。
    float3 y = cp * (x - s0); // 参考 `curve` 的输入。
    float3 shoulder = P - (P - s1) * (1.0 - y / (1.0 + y)); // 参考 `curve` 是 1 - y/(1+y)，不是 smoothstep。
    float3 linear = m + a * (x - m); // 线性段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, float3(0.0), float3(1.0)); // 三段拼接。
}

// Eclipse 黑体色：按温度拟合 RGB，再转线性；和普朗克轨迹版是两个不同近似。
float3 ogxBlackbodyEclipse(float temperature)
{
    float t = pow(temperature, -1.5); // 高温项。
    float lt = log(temperature); // 对数项。
    float3 col = float3(0.0); // 逐通道拟合结果。
    col.x = 220000.0 * t + 0.58039215686; // 红通道。
    col.y = 0.39231372549 * lt - 2.44549019608; // 绿通道低温段。
    col.y = temperature > 6500.0 ? 138039.215686 * t + 0.72156862745 : col.y; // 高温段换拟合。
    col.z = 0.76078431372 * lt - 5.68078431373; // 蓝通道。
    col = ogxSaturate(col); // 先夹紧到零到一。
    col = temperature < 1000.0 ? col * temperature * 0.001 : col; // 极低温按比例压暗。
    return ogxSrgbToLinear(col); // 最后转线性。
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

// iterationT 的可配置 AgX：把 RGB 转到调整后的工作空间，再走完整曲线。
float3 ogxAgxConfigurable(float3 rgb)
{
    float2 xyRed = float2(0.64, 0.33); // 红原色色度。
    float2 xyGreen = float2(0.3, 0.6); // 绿原色色度。
    float2 xyBlue = float2(0.15, 0.06); // 蓝原色色度。
    float2 xyWhite = float2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    OgxAgxMat3 xyzToAdjusted = ogxAgxInverse(adjustedToXyz); // 逆矩阵。
    float3 xyz = ogxAgxVecMul(srgbToXyz, rgb); // 参考实现用行向量乘矩阵。
    float3 adjustedRgb = ogxAgxVecMul(xyzToAdjusted, xyz); // 转到调整后 RGB。
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
OgxAgxMat3 ogxAgxConfigurable1()
{
    float2 xyRed = float2(0.64, 0.33); // 红原色色度。
    float2 xyGreen = float2(0.3, 0.6); // 绿原色色度。
    float2 xyBlue = float2(0.15, 0.06); // 蓝原色色度。
    float2 xyWhite = float2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    return ogxAgxMulMat(srgbToXyz, ogxAgxInverse(adjustedToXyz)); // 组合成 sRGB 到调整后空间。
}

// 饱和度矩阵：把颜色朝灰阶收或向外推，一为原色。
// 旧实现用四乘四矩阵，保留同一个构造顺序；生成 GLSL 后按列解释，与旧画面一致。
float4x4 ogxSaturationMatrix(float saturation)
{
    const float3 luminance = float3(0.3086, 0.6094, 0.0820); // 饱和度用的亮度权重。
    float3 lumSat = luminance * (1.0 - saturation); // 去饱和时混入的灰分量。
    float2 satZero = float2(saturation, 0.0); // 原色保留量。
    return float4x4(
        float4(lumSat.r + satZero.xyy, 0.0),
        float4(lumSat.g + satZero.yxy, 0.0),
        float4(lumSat.b + satZero.yyx, 0.0),
        float4(0.0, 0.0, 0.0, 1.0)); // 三个颜色通道加一行齐次坐标。
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
float3x3 ogxAgxConfigurable1Mat3()
{
    return ogxAgxMat3ToMat3(ogxAgxConfigurable1());
}

#endif