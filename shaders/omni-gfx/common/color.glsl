/*
生成文件：颜色模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库颜色模块：线性颜色、亮度、伽马、强光压缩、黑边与调色。
调用位置：任何需要把线性高动态范围颜色映射到显示空间或做最终调色的程序；
    Minecraft 光影由 `/omni-gfx/common/color.glsl` 引入，引入后数学模块同时可用。
可复制示例：
    vec3 a = ogxAces(linearColor, true); // 影院标准压缩。
    vec3 b = ogxAgx(linearColor, 13.0, true); // 宽色域压缩。
    vec3 c = ogxTonemapNone(linearColor); // 只做伽马编码。
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
#include "/omni-gfx/common/math.glsl"
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

// 无压缩：Eclipse 的 `no_tonemapper` 原样返回，不做伽马编码；伽马由最终输出阶段处理。
vec3 ogxTonemapNone(vec3 color) { return color; }

// Eclipse 的 `LinearTosRGB`：亮部先把颜色夹到零到一，再走幂曲线；用于需要稳定输出的场合。
vec3 ogxLinearToSrgbClamped(vec3 color)
{
    vec3 x = color * 12.92;
    vec3 y = 1.055 * pow(clamp(color, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.4)) - 0.055;
    vec3 result = color;
    result.r = color.r < 0.0031308 ? x.r : y.r; // 按参考写法推进这一步。
    result.g = color.g < 0.0031308 ? x.g : y.g; // 按参考写法推进这一步。
    result.b = color.b < 0.0031308 ? x.b : y.b; // 按参考写法推进这一步。
    return result;
}

// 线性到标准 sRGB 的分段编码：暗部走直线，亮部走二点四分之一幂，与二点二近似不同。
// 直接按 Eclipse `linearToSRGB` 的 mix 写法，不做额外夹紧：阈值外两段会自动选中正确的一侧。
vec3 ogxLinearToSrgb(vec3 color)
{
    vec3 low = color * 12.92; // 暗部直线段。
    vec3 high = pow(color, vec3(1.0 / 2.4)) * 1.055 - 0.055; // 亮部幂曲线。
    return mix(low, high, step(vec3(0.0031308), color)); // 逐通道按阈值选择。
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
// 高级调色分四步：回线性、按亮度伽马抬中灰、压白点、调饱和度。
// 顺序不能换：先压白点会把高光裁掉，后面的亮度伽马就失去细节；
// 饱和度放在最后，避免调亮度时把颜色推出色域。
// 每一步都夹到零到一，负值只可能来自矩阵拟合，保留会变成黑斑。
vec3 ogxAdvancedColor(vec3 color, float lumaGamma, float whiteClip, float saturation, float gamma)
{
    color = ogxGammaToLinear(color);
    color = pow(length(color), 1.0 / lumaGamma) * normalize(color + 1e-20);
    color = clamp(color * (1.0 + whiteClip), vec3(0.0), vec3(1.0));
    color = mix(color, vec3(ogxLuminance(color)), vec3(1.0 - saturation));
    return clamp(pow(color, vec3((1.0 / 2.2) / gamma)), vec3(0.0), vec3(1.0));
}

// 色相、饱和度、明度转回颜色，与 `ogxRgbToHsv` 互逆。
// HSV 转 RGB：照 Eclipse `hsv.glsl` 的 K 向量写法，色彩环由 fract 与绝对值折叠。
vec3 ogxHsvToRgb(vec3 color)
{
    const vec4 K = vec4(3.0, 2.0, 1.0, 9.0) / 3.0;
    vec3 p = abs(fract(color.xxx + vec3(K.x, K.y, K.z)) * 6.0 - vec3(K.w, K.w, K.w));
    return color.z * mix(vec3(K.x, K.x, K.x), ogxSaturate(p - vec3(K.x, K.x, K.x)), color.y);
}

// sRGB 到线性：Eclipse `util.glsl` 的分段标准曲线，暗部除以十二点九二，亮部走二点四幂。
vec3 ogxSrgbToLinear(vec3 s)
{
    return mix(s / 12.92,
        pow(0.947867 * s + 0.0521327, vec3(2.4)),
        step(vec3(0.04045), s));
}

// sRGB 到线性：三次多项式近似，Eclipse 的 `toLinear` 使用这一条更便宜的曲线。
vec3 ogxSrgbToLinearApprox(vec3 s) { return s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878); }

// Eclipse 的亮度权重：旧电视标准 0.299/0.587/0.114，和库默认的现代权重不同。
// 单独成函数，避免把两种颜色空间混进同一个 `ogxLuminance`。
// 亮度权重：Eclipse 的 `luma` 在场景亮度里用 Rec.601 系数。
float ogxLuminanceRec601(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }

// 饱和度矩阵：把颜色朝灰阶收或向外推，一为原色。
// 旧实现用四乘四矩阵，保留同一个构造顺序；生成 GLSL 后按列解释，与旧画面一致。
// 饱和度矩阵：把颜色朝亮度灰轴插值，矩阵形式让调用方可以一次乘完。
// 亮度权重用 Rec.709 的三分量，和显示空间一致；换权重会让肤色偏移。
// 矩阵第四行与第四列保持单位，方便直接乘齐次坐标。
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

// Eclipse `curve(vec3)`：软肩曲线 `1 - x/(1+x)`，与 iterationT 的宏 `curve` 不是同一条曲线。
// 单独命名，避免和宿主层已有的 `curve` 宏展开冲突。
float ogxSoftSaturate(float x) { return 1.0 - x / (1.0 + x); }
vec3 ogxSoftSaturate3(vec3 x) { return vec3(ogxSoftSaturate(x.x), ogxSoftSaturate(x.y), ogxSoftSaturate(x.z)); }

// Eclipse 黑体色：按温度拟合 RGB，再转线性；和普朗克轨迹版是两个不同近似。
// 为什么保留这条拟合：光源色与调试色温需要和 Eclipse 参考逐项一致，
// 数学模块的普朗克轨迹版偏物理，短波段的观感不同。
vec3 ogxBlackbodyApprox(float temperature)
{
    float t = pow(temperature, -1.5); // 高温项。
    float lt = log(temperature); // 对数项。
    vec3 col = vec3(0.0); // 逐通道拟合结果。
    col.x = 220000.0 * t + 0.58039215686; // 红通道。
    col.y = 0.39231372549 * lt - 2.44549019608; // 绿通道低温段。
    col.y = temperature > 6500.0 ? 138039.215686 * t + 0.72156862745 : col.y; // 高温段换拟合。
    col.z = 0.76078431372 * lt - 5.68078431373; // 蓝通道。
    col = ogxSaturate(col); // 先夹紧到零到一。
    col = temperature < 1000.0 ? col * temperature * 0.001 : col; // 极低温按比例压暗。
    return ogxSrgbToLinear(col); // 最后转线性。
}

// ACES 曲线，具体实现在子文件。
// 子文件：common/color/aces.slang。
// 颜色模块 ACES：影院标准曲线、经济版电影曲线与 AP1 工作色域矩阵。
// 调用位置：由 `common/color.slang` 内联引入，后期色调映射按选项调用。
// 可复制示例：`vec3 c = ogxAces(linearColor, true);`
// 设计原因与取舍：矩阵与常数集中在一处，方便和参考实现逐行核对。

// --- 算法说明与边界 ---
// RRT 与 ODT 的拟合曲线按参考分段实现，输入先乘白点缩放，输出再乘显示矩阵。
// ACES 入口保留线性与显示两个版本：合成阶段要线性结果，最终显示要编码后的颜色。
// ACES 色调映射：先把线性颜色乘输入矩阵换到 ACES 空间，再用 RRT 与 ODT 的分段拟合压缩高光。
// 拟合曲线保持参考实现的常数，输出再换回显示空间；另一个入口直接返回线性结果给合成使用。
// ACES 的输入矩阵把线性 sRGB 换到 ACES 色域，输出矩阵再换回显示色域；两个矩阵都按列存放。
// RRT 与 ODT 的拟合分段在低亮度接近线性，高亮度压缩到一，避免太阳与高光直接截断。
// 拟合里的白点缩放按参考常数，改变它会让整体色温偏移，不能随手调。
// 线性入口给合成阶段使用，显示入口在末尾再做伽马编码。
// 输入颜色按线性空间处理，调用前不要先做伽马编码。
// 输出颜色的范围由拟合曲线决定，显示阶段仍要做伽马编码。
// 白点缩放改变整体色温，默认值来自参考程序。
// 输入矩阵与输出矩阵互逆，修改其中一个要同步另一个。
// 拟合分段在低亮度接近线性，高亮度压缩到一。
// 负颜色在进入矩阵前先夹到零，避免非数。
// 线性入口不做显示编码，给合成阶段使用。
// 显示入口在末尾做伽马编码，给最终画面使用。
// 曝光参数只缩放输入，不改变曲线形状。
// 所有常数按参考实现保留，不要用近似值替换。
// 输入矩阵与输出矩阵的常数来自参考实现，不要用近似值替换。
// 拟合分段在零附近保持连续，暗部不会出现断层。
// 曝光前置增益只改输入亮度，不改变曲线形状。
// 显示入口在末尾做伽马编码，线性入口不做。
// 负颜色在进入矩阵前夹到零，避免非数。


// ACES 压缩曲线里的有理式：中间亮度拉直，两端压住。
vec3 ogxRrtOdtFit(vec3 value)
{
    // 分子与分母都是二次多项式，拟合 RRT+ODT 的 S 形曲线；常数照参考保留。
    vec3 a = value * (value + 0.0245786) - 0.000090537;
    // 分母在零附近不为零，避免暗部除法放大噪声。
    vec3 b = value * (value + 0.4329510) + 0.238081;
    return a / b;
}

// 阿布尼校正矩阵的三列，抵消加亮造成的色相偏移。
// Abney 校正矩阵：抵消高亮时的色相偏移；数值几乎是对角矩阵，只有蓝色列带一点红。
const vec3 OGX_ABNEY_0 = vec3(0.99999976, -1.26657e-7, -1.29064e-9);
const vec3 OGX_ABNEY_1 = vec3(1.67316e-8, 0.99999976, -5.32026e-9);
const vec3 OGX_ABNEY_2 = vec3(-0.00725587, 6.47740e-9, 1.00725580);

// 转 AP1 工作色域的三列。
// AP1 是 ACES 的宽色域原色空间；先转进去压缩，再转回 sRGB，高光颜色不会被过早裁掉。
const vec3 OGX_AP1_0 = vec3(0.59719, 0.35458, 0.04823);
const vec3 OGX_AP1_1 = vec3(0.07600, 0.90834, 0.01566);
const vec3 OGX_AP1_2 = vec3(0.02840, 0.13383, 0.83777);

// 从 AP1 转回显示色域的三列。
// 回到 sRGB 的逆矩阵；负系数是宽色域转窄色域的正常结果，最后交给伽马编码。
const vec3 OGX_AP1_BACK_0 = vec3(1.60475, -0.53108, -0.07367);
const vec3 OGX_AP1_BACK_1 = vec3(-0.10208, 1.10813, -0.00605);
const vec3 OGX_AP1_BACK_2 = vec3(-0.00327, -0.07276, 1.07602);

// 影院标准 ACES 近似：提亮、转工作色域、压缩、再转回显示色域。
// `abney` 为真时附加一次很小的色域修正，抵消加亮造成的色相偏移。
// ACES 为什么先换到 AP1：sRGB 原色在极亮处会先被裁成纯色，宽色域能保留更多高光色相。
// 压缩曲线是 RRT+ODT 的二次有理拟合，不是逐段样条；它的肩部足够长，太阳与云不会切白。
// Abney 校正是可选项：关闭时高光更艳，打开时更接近人眼对亮色的去饱和。
// 最后的伽马二是参考实现的显示编码，调用方不要再做第二次。
vec3 ogxAces(vec3 color, bool abney)
{
    // 1.4 是参考实现的曝光前置增益，让中灰落到曲线较直的一段。
    color *= 1.4;
    if (abney)
    {
        color = ogxApplyRows(OGX_ABNEY_0, OGX_ABNEY_1, OGX_ABNEY_2, color);
    }
    color = ogxApplyRows(OGX_AP1_0, OGX_AP1_1, OGX_AP1_2, color);
    // S 形拟合把高光滚降压平，暗部抬一点，避免纯黑和纯白同时出现。
    color = ogxRrtOdtFit(color);
    color = ogxApplyRows(OGX_AP1_BACK_0, OGX_AP1_BACK_1, OGX_AP1_BACK_2, color);
    return ogxLinearToGamma(color);
}

// 参考包的 `ACES` 默认开启 Abney 效应校正；单参数重载让旧调用点保持原签名。
// ACES 单参入口：保留旧调用方式，内部按默认白点走完整映射。
// 单参数重载默认开启 Abney 校正；需要比较原色时调用两参数版本并传假。
vec3 ogxAces(vec3 color) { return ogxAces(color, true); }

// 经济版电影曲线：一条有理式，成本低于 ACES 拟合，观感更硬、更亮。
// 电影版 ACES 近似：没有宽色域矩阵，只保留 Narkowicz 的拟合，适合低开销路径。
vec3 ogxTonemapAcesFilm(vec3 color)
{
    vec3 x = color * 0.9; // 先压一点曝光。
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.95) + 0.12); // 分子分母都是二次式。
}

// AgX 曲线与可配置色域矩阵，具体实现在子文件。
// 子文件：common/color/agx.slang。
// 颜色模块 AgX：对比曲线、宽色域压缩、可配置色域矩阵与三套参考变体。
// 调用位置：由 `common/color.slang` 内联引入，默认强光压缩与可配置选项都走这里。
// 可复制示例：`vec3 c = ogxAgx(linearColor, 13.0, true);`
// 设计原因与取舍：普通版与可配置版共用矩阵工具，避免三套色域转换各写一份。

// --- 算法说明与边界 ---
// AgX 先把曝光后的颜色转到对数域，再按对比度曲线压缩；压缩矩阵把主色拉回可见范围。
// 完整版保留 look 与色域滑动，精简版省掉矩阵，只给低开销阶段使用。
// 色域矩阵按主色坐标构造，输入与输出都夹在零到一，避免负色进入后续曲线。
// 所有变体共用同一套常数，新增入口时只换矩阵与采样顺序，不改压缩本身。
// AgX 色调映射：先把线性颜色换到 AgX 空间，按曝光与对比度压缩，再换回显示空间。
// 模块保留完整版、精简版与可配置版：完整版带 look 与色域矩阵，精简版省掉矩阵运算。
// 色域转换、压缩矩阵与主色滑动都拆成纯函数，方便严格对照逐个核对常数。
// AgX 的压缩曲线在中间调近似线性，两端分别压缩黑与白；对比度参数只改中间段的斜率。
// 对数域先把曝光范围拉开，再压缩到零到一，暗部细节不会因为高光被一起压掉。
// 色域矩阵按主色坐标构造，主色滑动把过饱和的颜色拉回可见范围，避免霓虹色断层。
// 完整版保留 look 与矩阵，精简版省掉矩阵运算；两者使用同一套压缩常数。
// 可配置版把曝光、对比度与色域矩阵拆成参数，给测试世界逐个比较。
// 所有入口都先处理负值，负色进入幂函数会得到非数。
// 输入颜色是线性空间，曝光在进入对数域前乘上。
// 对数域把暗部与高光拉开，压缩曲线再把它折回零到一。
// 对比度只改中间段斜率，端点保持固定。
// 色域矩阵按主色坐标构造，输入与输出都夹在零到一。
// 主色滑动把过饱和颜色拉回可见范围，强度为零时不改色。
// 完整版保留 look 与矩阵，精简版省掉矩阵运算。
// 可配置版把曝光、对比度与色域拆成参数，给测试世界比较。
// 负颜色在进入幂函数前夹到零，避免非数。
// 压缩矩阵与色域矩阵分开，修改色域不会影响压缩曲线。
// 矩阵乘法按列存放，调用方不要按行解释。
// 输出仍是线性颜色，显示编码由调用方负责。
// look 参数只影响中间调，不改变黑白端点。
// 曝光为零时曲线仍保留一点黑位，不会全黑。
// 高光压缩到一附近，太阳不会直接截断成纯白。
// 色域转换后的颜色可能超出零到一，压缩前先夹紧。
// 精简版省掉色域矩阵，颜色会比完整版略饱和。
// 可配置版的参数顺序与参考一致，严格对照按原签名调用。
// 所有变体共用同一套压缩常数，新增入口只换矩阵。
// 输入矩阵与输出矩阵都按列存放，转置会改变色相。
// 对比度为零时曲线退化成线性压缩，仍保留端点。
// 主色坐标来自参考程序，修改前先核对色域。
// 色域矩阵的行列式接近一，颜色不会被整体放大。
// AgX 只做色调映射，不做白平衡与饱和度调整。


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
// AgX 宽色域压缩：参考的默认曝光是 13、半动态范围 6.5；显式传入两个常数，避免派生值丢失。
// AgX 的核心是先把曝光压到对数域，再用一条 S 曲线压缩，最后回宽色域。
// 中间灰定在零点一八：这是摄影里的标准中灰，场景亮度除以它以后，
// 亮部与暗部在曲线上对称展开，不会因为场景整体偏亮而丢掉高光。
// 对比曲线用五次多项式而不是分段样条，是为了在 GPU 上少分支、结果连续。
vec3 ogxAgx(vec3 color, float ev, float hev, bool abney)
{
    color *= 2.3; // 按参考写法推进这一步。
    if (abney) // 按参考条件选择这一支。
    {
        color = ogxApplyRows(OGX_ABNEY_0, OGX_ABNEY_1, OGX_ABNEY_2, color);
    }
    color = ogxApplyRows(OGX_AGX_0, OGX_AGX_1, OGX_AGX_2, color);
    const float MIDDLE_GREY = 0.18;
    color = clamp(log2(color / MIDDLE_GREY), vec3(-hev), vec3(hev));
    color = (color + hev) / ev;
    color = ogxAgxContrast(color);
    color = ogxApplyRows(OGX_AGX_BACK_0, OGX_AGX_BACK_1, OGX_AGX_BACK_2, color);
    return color;
}

// 旧三参数入口：半动态范围由曝光派生，保持现有调用点不变。
vec3 ogxAgx(vec3 color, float ev, bool abney) { return ogxAgx(color, ev, ev * 0.5, abney); }

// Eclipse 的 AgX look：保留参考的偏移、斜率与幂变量，默认零偏移、单位斜率与幂，只把饱和度推到 1.25。
// AgX 的 look 曲线：在色调映射后做一次对比与饱和调整。
vec3 ogxAgxLook(vec3 value)
{
    const vec3 lw = vec3(0.2126, 0.7152, 0.0722); // 参考实现固定 Rec.709 亮度。
    float luma = dot(value, lw); // 先取亮度，饱和度围绕它展开。
    vec3 offset = vec3(0.0); // 参考默认零偏移。
    vec3 slope = vec3(1.0); // 参考默认单位斜率。
    vec3 power = vec3(1.0); // 参考默认单位幂。
    float sat = 1.25; // 对比度/饱和度。
    value = pow(value * slope + offset, power); // 逐通道应用偏移、斜率与幂。
    return luma + sat * (value - luma); // 围绕亮度拉开饱和度。
}

// Eclipse 的 AgX 完整版：插入矩阵、动态范围 -12.47393 到 4.026069，再用 AGX look。
// AgX 主映射：把线性场景色压进显示范围并保留高光层次。
vec3 ogxToneMapAgx(vec3 color)
{
    vec3 in0 = vec3(0.856627153315983, 0.137318972929847, 0.11189821299995); // 插入矩阵第一列。
    vec3 in1 = vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 in2 = vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859); // 这是第三列的数值，按参考实现的顺序填写。
    vec3 out0 = vec3(1.1271005818144368, - 0.1413297634984383, - 0.14132976349843826); // 输出矩阵第一列。
    vec3 out1 = vec3(- 0.11060664309660323, 1.157823702216272, - 0.11060664309660294); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 out2 = vec3(- 0.016493938717834573, - 0.016493938717834257, 1.2519364065950405); // 这是第三列的数值，按参考实现的顺序填写。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入 AgX 工作空间。
    color = clamp(log2(color), vec3(- 12.47393), vec3(4.026069)); // 夹进承认的动态范围。
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
    vec3 in1 = vec3(0.0784335999999992, 0.878468636469772, 0.0784336); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 in2 = vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 这是第三列的数值，按参考实现的顺序填写。
    vec3 out0 = vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    vec3 out1 = vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 out2 = vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 这是第三列的数值，按参考实现的顺序填写。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), vec3(- 12.47393), vec3(4.026069)); // 与完整版相同的端点。
    color = (color + 12.47393) / (4.026069 + 12.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, vec3(2.2)); // 线性化。
    return clamp(color, vec3(0.0), vec3(1.0)); // 夹紧。
}

// Eclipse 的 AgX Merlin 版：矩阵同上，端点整体上移一档，动态范围更窄。
// AgX 的另一种拟合：用简化多项式逼近同一曲线，减少常数运算。
vec3 ogxToneMapAgxCompact(vec3 color)
{
    vec3 in0 = vec3(0.842479062253094, 0.0423282422610123, 0.0423756549057051); // 精简插入矩阵第一列。
    vec3 in1 = vec3(0.0784335999999992, 0.878468636469772, 0.0784336); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 in2 = vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104); // 这是第三列的数值，按参考实现的顺序填写。
    vec3 out0 = vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438); // 输出矩阵第一列。
    vec3 out1 = vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241); // 这是第二列的数值，按参考实现的顺序填写。
    vec3 out2 = vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116); // 这是第三列的数值，按参考实现的顺序填写。
    color = ogxApplyColumns(in0, in1, in2, color); // 进入工作空间。
    color = clamp(log2(color), vec3(- 11.47393), vec3(3.226069)); // Merlin 的端点比精简版高 1。
    color = (color + 11.47393) / (3.226069 + 11.47393); // 归一化。
    color = ogxAgxContrast(color); // 对比曲线。
    color = ogxAgxLook(color); // 参考 look。
    color = ogxApplyColumns(out0, out1, out2, color); // 回显示原色。
    color = pow(color, vec3(2.2)); // 线性化。
    return clamp(color, vec3(0.0), vec3(1.0)); // 夹紧。
}

// 三列矩阵：用三个列向量表示，避开 Slang 与 GLSL 的行列顺序差异。
struct OgxAgxMat3
{
    vec3 c0; // 这是第一列的数值，按参考实现的顺序填写。
    vec3 c1; // 这是第二列的数值，按参考实现的顺序填写。
    vec3 c2; // 这是第三列的数值，按参考实现的顺序填写。
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
    vec3 a = m.c0; // 这是第一列的数值，按参考实现的顺序填写。
    vec3 b = m.c1; // 这是第二列的数值，按参考实现的顺序填写。
    vec3 c = m.c2; // 这是第三列的数值，按参考实现的顺序填写。
    vec3 r0 = vec3(b.y * c.z - b.z * c.y, a.z * c.y - a.y * c.z, a.y * b.z - a.z * b.y); // 伴随矩阵第一行。
    vec3 r1 = vec3(b.z * c.x - b.x * c.z, a.x * c.z - a.z * c.x, a.z * b.x - a.x * b.z); // 这是第二行的数值，按参考实现的顺序填写。
    vec3 r2 = vec3(b.x * c.y - b.y * c.x, a.y * c.x - a.x * c.y, a.x * b.y - a.y * b.x); // 这是第三行的数值，按参考实现的顺序填写。
    float determinant = dot(a, r0); // 行列式。
    OgxAgxMat3 result;
    result.c0 = vec3(r0.x, r1.x, r2.x) / determinant; // 伴随矩阵转置后按列写入。
    result.c1 = vec3(r0.y, r1.y, r2.y) / determinant;
    result.c2 = vec3(r0.z, r1.z, r2.z) / determinant;
    return result;
}

// 色度坐标到 XYZ：Y 归一为一，X 与 Z 由 xy 反推。
// AgX 反变换：从显示色回推线性值，供历史帧比较与调试。
vec3 ogxAgxUnproject(vec2 xy)
{
    if (xy.y == 0.0) return vec3(0.0); // 参考实现对零分母直接返回零。
    float x = xy.x / xy.y; // X 分量。
    float z = (1.0 - xy.x - xy.y) / xy.y; // Z 分量。
    return vec3(x, 1.0, z); // Y 固定为一。
}

// 由三原色与白点色度构造 RGB 到 XYZ 的矩阵；列顺序与参考实现一致。
// 原色坐标转矩阵：先把色度坐标还原成 XYZ，再用白点求三原色的缩放。
// 为什么不用现成常数：可配置 AgX 允许换原色，矩阵必须跟着白点与三原色重算。
// 行列式为零时逆矩阵没有意义，调用方要保证三原色不共线。
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
    result.c1 = vec3(scale.x * xyzRed.y, scale.y * xyzGreen.y, scale.z * xyzBlue.y); // 这是第二行的数值，按参考实现的顺序填写。
    result.c2 = vec3(scale.x * xyzRed.z, scale.y * xyzGreen.z, scale.z * xyzBlue.z); // 这是第三行的数值，按参考实现的顺序填写。
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
    return mix(primary, mix(neighborB, neighborA, float(amount >= 0.0)), ogxSaturate(abs(amount))); // 保留参考实现的顺序。
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

// 组合矩阵在前面定义，主入口先声明，避免依赖文件里的书写顺序。
mat3 ogxAgxCustomGamutMatrix3();

// iterationT 的可配置 AgX：把 RGB 转到调整后的工作空间，再走完整曲线。
// 组合矩阵由 `ogxAgxCustomGamutMatrix3` 提供，和单独调用矩阵版本共用同一套原色常数。
// 可配置 AgX：把趾部、肩部、白点与原色都做成参数，供不同参考风格共用。
// 默认参数取 iterationT 的配置；曲线在两端各留一段线性，避免纯黑与纯白结块。
// 压缩矩阵先算一次再复用，不逐像素重建，配置换原色时才需要重算。
vec3 ogxAgxConfigurable(vec3 rgb)
{
    mat3 adjustedFromSrgb = ogxAgxCustomGamutMatrix3(); // sRGB 到调整后空间的组合矩阵。
    vec3 adjustedRgb = adjustedFromSrgb[0] * rgb.x + adjustedFromSrgb[1] * rgb.y + adjustedFromSrgb[2] * rgb.z; // 三列加权，避免行列约定差异。
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
OgxAgxMat3 ogxAgxCustomGamutMatrix()
{
    vec2 xyRed = vec2(0.64, 0.33); // 红原色色度。
    vec2 xyGreen = vec2(0.3, 0.6); // 绿原色色度。
    vec2 xyBlue = vec2(0.15, 0.06); // 蓝原色色度。
    vec2 xyWhite = vec2(0.3127, 0.3290); // D65 白点。
    OgxAgxMat3 srgbToXyz = ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite); // sRGB 到 XYZ。
    OgxAgxMat3 adjustedToXyz = ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite); // 调整后色域到 XYZ。
    return ogxAgxMulMat(srgbToXyz, ogxAgxInverse(adjustedToXyz)); // 组合成 sRGB 到调整后空间。
}

// 把三列矩阵换成 GLSL 的 mat3：参考包的三原色函数返回 mat3，调用方按矩阵乘向量。
mat3 ogxAgxMat3ToMat3(OgxAgxMat3 m)
{
    return mat3(m.c0, m.c1, m.c2);
}

// 参考签名的三原色矩阵：内部仍用三列结构体，只在边界转成 mat3。
mat3 ogxAgxPrimariesToMat3(vec2 xyRed, vec2 xyGreen, vec2 xyBlue, vec2 xyWhite)
{
    return ogxAgxMat3ToMat3(ogxAgxPrimariesToMatrix(xyRed, xyGreen, xyBlue, xyWhite));
}

// 参考签名的压缩矩阵，与上一函数配对。
mat3 ogxAgxCompressionToMat3(vec2 xyRed, vec2 xyGreen, vec2 xyBlue, vec2 xyWhite)
{
    return ogxAgxMat3ToMat3(ogxAgxComputeCompressionMatrix(xyRed, xyGreen, xyBlue, xyWhite));
}

// 参考签名的 AgX 组合矩阵：无参数，返回 sRGB 到调整后空间的矩阵。
mat3 ogxAgxCustomGamutMatrix3()
{
    return ogxAgxMat3ToMat3(ogxAgxCustomGamutMatrix());
}

// Reinhard 系列曲线，具体实现在子文件。
// 子文件：common/color/reinhard.slang。
// 颜色模块 Reinhard：基础、全范围、可编辑与 Reinhard-Jodie 四条曲线。
// 调用位置：由 `common/color.slang` 内联引入，供对照与可选曲线使用。
// 可复制示例：`vec3 c = ogxTonemapReinhard(linearColor);`
// 设计原因与取舍：四条曲线常数不同，不能用一个参数互相替代。

// --- 算法说明与边界 ---
// 完整版按每个通道除以一加亮度，编辑版把亮度提到指数再压，Jodie 版先算亮度再按比例缩放颜色。
// 三个入口都保留零曝光时的原色，负值不会进入幂函数。
// Reinhard 色调映射的三种变体：完整版按亮度压缩，编辑版保留更多中间调，Jodie 版对颜色做亮度归一。
// 三个入口都只接收线性颜色与曝光，返回显示空间颜色。
// 完整版对每个通道做 `x / (1 + x)`，高光压缩但颜色会偏灰。
// 编辑版先把亮度提到指数再压，中间调更亮，适合曝光偏低的画面。
// Jodie 版先算亮度，再按亮度比例缩放颜色，色相保持得更好。
// 三个入口都保留零曝光原色，负值不会进入幂函数。
// 三个入口都只接收线性颜色与曝光，输出仍是线性颜色。
// 完整版逐通道压缩，颜色会偏灰，适合快速预览。
// 编辑版把亮度提到指数再压，中间调更亮。
// Jodie 版先算亮度再缩放颜色，色相保持得更好。
// 曝光为零时返回原色，负值不会进入幂函数。
// 完整版与编辑版的差别只在亮度指数，曲线形状相同。
// Jodie 版先算亮度再缩放颜色，色相保持得更好。
// 曝光为零时返回原色，负值不会进入幂函数。
// 输出仍是线性颜色，显示编码由调用方负责。
// 三个入口都只接收线性颜色与曝光，输出仍是线性颜色。
// 完整版逐通道压缩，颜色会偏灰，适合快速预览。
// 编辑版把亮度提到指数再压，中间调更亮。


// Eclipse 全范围 Reinhard：白点 10、提亮 0.5，保留完整有理式。
// Reinhard 完整版：按最大通道压缩，保留色相。
vec3 ogxTonemapReinhardFull(vec3 color)
{
    float whitepoint = 10.0; // 参考实现固定白点。
    float lighten = 0.5; // 参考实现固定提亮量。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Eclipse 可编辑 Reinhard：先把颜色抬 1.2 次方，再用更低的提亮 0.333。
// Reinhard 编辑版：用固定曝光近似，适合快速预览。
vec3 ogxTonemapReinhardEdit(vec3 color)
{
    color = pow(color, vec3(1.2)); // 抬暗部，保持高光不动。
    float whitepoint = 10.0; // 与全范围版相同的白点。
    float lighten = 0.333; // 更低的提亮量，画面更亮。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Reinhard-Jodie：同时算亮度压缩与逐通道压缩，再按逐通道结果混回去。
// Reinhard-Jodie：按亮度与通道分别压缩，减少高光偏色。
vec3 ogxTonemapReinhardJodie(vec3 color)
{
    color *= 1.5; // 参考实现的曝光抬升。
    vec3 tonemapLuminance = color / (1.0 + dot(color, vec3(0.21, 0.72, 0.07))); // 保色相的亮度压缩。
    vec3 tonemapRgb = color / (1.0 + color); // 逐通道压缩，高光更容易去饱和。
    return mix(tonemapLuminance, tonemapRgb, tonemapRgb * 0.8 + 0.2); // 亮部更多采用逐通道结果。
}

// `Reinhard` 简单曲线：先放大一点六六倍再除以一加自身，暗部提得最明显。
vec3 ogxTonemapReinhard(vec3 color)
{
    vec3 x = color * 1.66; // 放大让中间灰更亮。
    return x / (1.0 + x); // 双曲线压缩，结果永远不会超过一。
}

// Uchimura 系列曲线，具体实现在子文件。
// 子文件：common/color/uchimura.slang。
// 颜色模块 Uchimura：基础三段曲线、指数肩部版与平滑肩部版。
// 调用位置：由 `common/color.slang` 内联引入，供对照与可选曲线使用。
// 可复制示例：`vec3 c = ogxTonemapUchimura(linearColor);`
// 设计原因与取舍：参考实现的肩部与平滑顺序保留，避免改变高光过渡。

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

// Eclipse 的 Uchimura 指数肩部版：肩部用 exp，参考实现保留反向 smoothstep 参数顺序。
// Uchimura 指数版：按分段指数压缩高光，适合夜景。
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
// Uchimura 改进版：用可调切线参数控制肩部过渡。
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
    vec3 y = cp * (x - s0); // 参考 `curve` 的输入。
    vec3 shoulder = P - (P - s1) * (1.0 - y / (1.0 + y)); // 参考 `curve` 是 1 - y/(1+y)，不是 smoothstep。
    vec3 linear = m + a * (x - m); // 线性段。
    return clamp(toe * w0 + linear * w1 + shoulder * w2, vec3(0.0), vec3(1.0)); // 三段拼接。
}

// 胶片与肩部曲线，具体实现在子文件。
// 子文件：common/color/curve.slang。
// 颜色模块胶片曲线：Hejl、Hable、Lottes 与 Xonk 四条独立拟合。
// 调用位置：由 `common/color.slang` 内联引入，按选项选择。
// 可复制示例：`vec3 c = ogxTonemapHable(linearColor);`
// 设计原因与取舍：每条曲线常数独立，合并会让对照失去可复核的边界。

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

// `Xonk` 曲线：先抬高三成伽马，再用一条有理式压肩部，暗部比 `Reinhard` 更亮。
// 它是一条独立拟合，和 `ACES`、`AgX`、`Reinhard` 都不是同一条曲线，不能互相替代。
vec3 ogxTonemapPowerCurve(vec3 color)
{
    color = pow(color, vec3(1.3)); // 先抬伽马，暗部细节更容易看见。
    return color / (0.333 + color); // 有理式软肩，最亮处趋近于一。
}

#endif
