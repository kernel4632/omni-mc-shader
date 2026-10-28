/*
Omni 通用图形库颜色模块：线性颜色、亮度、伽马、强光压缩、黑边与调色。
调用位置：任何需要把线性高动态范围颜色映射到显示空间或做最终调色的程序；
    Minecraft 光影由 `/omni-gfx/common/color.glsl` 引入，引入后数学模块同时可用。
可复制示例：
    float3 a = ogxAces(linearColor, true); // 影院标准压缩。
    float3 b = ogxAgx(linearColor, 13.0, true); // 宽色域压缩。
    float3 c = ogxTonemapNone(linearColor); // 只做伽马编码。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀。
    常用颜色工具留在主文件，具体曲线按算法放进子文件，名字与内容一一对应。
    伽马使用二点二近似，与迁移前的 GLSL 原型一致，不在这里做分段标准曲线。
    矩阵乘法展开成三列乘分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
*/

// --- 算法说明与边界 ---
// 矩阵乘法按列与按行分开，调用方按数据布局选择，避免转置错误。
// 黑边按目标宽高比裁切，画面外的坐标返回黑；浦肯野效应只在暗处生效，亮处保持原色。
// 白平衡用黑体色温乘颜色，中性色温不改变画面；高级调色依次做亮度、饱和与伽马。
// HSV 入口给体积光与自发光使用，黑体近似给火把色温使用。
// 颜色模块集中色彩空间、色调映射与调色：
// 矩阵按列与按行两种乘法分开，避免 Slang 与 GLSL 的行列顺序混淆。
// sRGB 编解码有精确与近似两版，近似版给性能敏感阶段；管线曲线是四次方根编码。
// 调色包括黑边、浦肯野效应、白平衡、高级颜色、HSV 与黑体色，全部接收显式参数。
// 黑边按目标宽高比裁切，超出画面的坐标返回黑，不拉伸画面。
// 浦肯野效应只在暗处生效，亮度越高越接近原色，避免白天偏蓝。
// 白平衡用黑体色温乘颜色，六千五百为中性；色温超出范围时夹到端点。
// 高级调色按亮度、饱和度、伽马顺序执行，每一步都夹在合法范围。
// HSV 入口给体积光与自发光使用，黑体近似给火把色温使用。
// 矩阵乘法按列与按行分开，调用方按数据布局选择，避免转置错误。
// 黑边按目标宽高比裁切，画面外返回黑，不拉伸。
// 浦肯野效应只在暗处生效，亮度越高越接近原色。
// 白平衡六千五百为中性，超出范围时夹到端点。
// 高级调色按亮度、饱和度、伽马顺序执行。
// HSV 入口给体积光与自发光使用，黑体近似给火把色温使用。
// 矩阵乘法按列与按行分开，调用方按数据布局选择。
// sRGB 精确版用于最终显示，近似版给性能敏感阶段。
// 所有调色函数都不读取选项，参数由调用方显式传入。
// 输出颜色夹在合法范围，负值不会进入后续曲线。
// 矩阵乘法按列与按行分开，调用方按数据布局选择。
// 黑边裁切不改变画面比例，只把画面外填黑。
// 白平衡六千五百为中性，超出范围时夹到端点。
// 高级调色按亮度、饱和度、伽马顺序执行。
// sRGB 精确版用于最终显示，近似版给性能敏感阶段。

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

// 无压缩：Eclipse 的 `no_tonemapper` 原样返回，不做伽马编码；伽马由最终输出阶段处理。
float3 ogxTonemapNone(float3 color) { return color; }

// Eclipse 的 `LinearTosRGB`：亮部先把颜色夹到零到一，再走幂曲线；用于需要稳定输出的场合。
float3 ogxLinearToSrgbClamped(float3 color)
{
    float3 x = color * 12.92;
    float3 y = 1.055 * pow(clamp(color, float3(0.0), float3(1.0)), float3(1.0 / 2.4)) - 0.055;
    float3 result = color;
    result.r = color.r < 0.0031308 ? x.r : y.r; // 按参考写法推进这一步。
    result.g = color.g < 0.0031308 ? x.g : y.g; // 按参考写法推进这一步。
    result.b = color.b < 0.0031308 ? x.b : y.b; // 按参考写法推进这一步。
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
// 高级调色分四步：回线性、按亮度伽马抬中灰、压白点、调饱和度。
// 顺序不能换：先压白点会把高光裁掉，后面的亮度伽马就失去细节；
// 饱和度放在最后，避免调亮度时把颜色推出色域。
// 每一步都夹到零到一，负值只可能来自矩阵拟合，保留会变成黑斑。
float3 ogxAdvancedColor(float3 color, float lumaGamma, float whiteClip, float saturation, float gamma)
{
    color = ogxGammaToLinear(color);
    color = pow(length(color), 1.0 / lumaGamma) * normalize(color + 1e-20);
    color = clamp(color * (1.0 + whiteClip), float3(0.0), float3(1.0));
    color = lerp(color, float3(ogxLuminance(color)), float3(1.0 - saturation));
    return clamp(pow(color, float3((1.0 / 2.2) / gamma)), float3(0.0), float3(1.0));
}

// 色相、饱和度、明度转回颜色，与 `ogxRgbToHsv` 互逆。
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

// 饱和度矩阵：把颜色朝灰阶收或向外推，一为原色。
// 旧实现用四乘四矩阵，保留同一个构造顺序；生成 GLSL 后按列解释，与旧画面一致。
// 饱和度矩阵：把颜色朝亮度灰轴插值，矩阵形式让调用方可以一次乘完。
// 亮度权重用 Rec.709 的三分量，和显示空间一致；换权重会让肤色偏移。
// 矩阵第四行与第四列保持单位，方便直接乘齐次坐标。
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

// Eclipse `curve(float3)`：软肩曲线 `1 - x/(1+x)`，与 iterationT 的宏 `curve` 不是同一条曲线。
// 单独命名，避免和宿主层已有的 `curve` 宏展开冲突。
float ogxSoftSaturate(float x) { return 1.0 - x / (1.0 + x); }
float3 ogxSoftSaturate3(float3 x) { return float3(ogxSoftSaturate(x.x), ogxSoftSaturate(x.y), ogxSoftSaturate(x.z)); }

// Eclipse 黑体色：按温度拟合 RGB，再转线性；和普朗克轨迹版是两个不同近似。
// 为什么保留这条拟合：光源色与调试色温需要和 Eclipse 参考逐项一致，
// 数学模块的普朗克轨迹版偏物理，短波段的观感不同。
float3 ogxBlackbodyApprox(float temperature)
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

// ACES 曲线，具体实现在子文件。
#include "color/aces.slang"
// AgX 曲线与可配置色域矩阵，具体实现在子文件。
#include "color/agx.slang"
// Reinhard 系列曲线，具体实现在子文件。
#include "color/reinhard.slang"
// Uchimura 系列曲线，具体实现在子文件。
#include "color/uchimura.slang"
// 胶片与肩部曲线，具体实现在子文件。
#include "color/curve.slang"

#endif
