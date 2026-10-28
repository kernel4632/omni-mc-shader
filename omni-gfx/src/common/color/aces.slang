// 颜色模块 ACES：影院标准曲线、经济版电影曲线与 AP1 工作色域矩阵。
// 调用位置：由 `common/color.slang` 内联引入，后期色调映射按选项调用。
// 可复制示例：`float3 c = ogxAces(linearColor, true);`
// 设计原因与取舍：矩阵与常数集中在一处，方便和参考实现逐行核对。

// ACES 压缩曲线里的有理式：中间亮度拉直，两端压住。
float3 ogxRrtOdtFit(float3 value) // 当前步骤的中间量。
{ // 按参考顺序推进。
    // 分子与分母都是二次多项式，拟合 RRT+ODT 的 S 形曲线；常数照参考保留。
    float3 a = value * (value + 0.0245786) - 0.000090537; // 当前步骤的中间量。
    // 分母在零附近不为零，避免暗部除法放大噪声。
    float3 b = value * (value + 0.4329510) + 0.238081;
    return a / b;
}

// 阿布尼校正矩阵的三列，抵消加亮造成的色相偏移。
// Abney 校正矩阵：抵消高亮时的色相偏移；数值几乎是对角矩阵，只有蓝色列带一点红。
static const float3 OGX_ABNEY_0 = float3(0.99999976, -1.26657e-7, -1.29064e-9);
static const float3 OGX_ABNEY_1 = float3(1.67316e-8, 0.99999976, -5.32026e-9);
static const float3 OGX_ABNEY_2 = float3(-0.00725587, 6.47740e-9, 1.00725580);

// 转 AP1 工作色域的三列。
// AP1 是 ACES 的宽色域原色空间；先转进去压缩，再转回 sRGB，高光颜色不会被过早裁掉。
static const float3 OGX_AP1_0 = float3(0.59719, 0.35458, 0.04823);
static const float3 OGX_AP1_1 = float3(0.07600, 0.90834, 0.01566);
static const float3 OGX_AP1_2 = float3(0.02840, 0.13383, 0.83777);

// 从 AP1 转回显示色域的三列。
// 回到 sRGB 的逆矩阵；负系数是宽色域转窄色域的正常结果，最后交给伽马编码。
static const float3 OGX_AP1_BACK_0 = float3(1.60475, -0.53108, -0.07367);
static const float3 OGX_AP1_BACK_1 = float3(-0.10208, 1.10813, -0.00605);
static const float3 OGX_AP1_BACK_2 = float3(-0.00327, -0.07276, 1.07602);

// 影院标准 ACES 近似：提亮、转工作色域、压缩、再转回显示色域。
// `abney` 为真时附加一次很小的色域修正，抵消加亮造成的色相偏移。
// ACES 为什么先换到 AP1：sRGB 原色在极亮处会先被裁成纯色，宽色域能保留更多高光色相。
// 压缩曲线是 RRT+ODT 的二次有理拟合，不是逐段样条；它的肩部足够长，太阳与云不会切白。
// Abney 校正是可选项：关闭时高光更艳，打开时更接近人眼对亮色的去饱和。
// 最后的伽马二是参考实现的显示编码，调用方不要再做第二次。
float3 ogxAces(float3 color, bool abney)
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
float3 ogxAces(float3 color) { return ogxAces(color, true); }

// 经济版电影曲线：一条有理式，成本低于 ACES 拟合，观感更硬、更亮。
// 电影版 ACES 近似：没有宽色域矩阵，只保留 Narkowicz 的拟合，适合低开销路径。
float3 ogxTonemapAcesFilm(float3 color)
{
    float3 x = color * 0.9; // 先压一点曝光。
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.95) + 0.12); // 分子分母都是二次式。
}
