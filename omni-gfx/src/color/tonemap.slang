// 矩阵按列加权：三列分别乘向量的三个分量，避免依赖矩阵行列约定。
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
// ACES 单参入口：保留旧调用方式，内部按默认白点走完整映射。
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
float3 ogxSoftSaturate3(float3 x) { return 1.0 - x / (1.0 + x); }
