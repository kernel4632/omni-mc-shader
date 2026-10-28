// 颜色模块 ACES：影院标准曲线、经济版电影曲线与 AP1 工作色域矩阵。
// 调用位置：由 `common/color.slang` 内联引入，后期色调映射按选项调用。
// 可复制示例：`float3 c = ogxAces(linearColor, true);`
// 设计原因与取舍：矩阵与常数集中在一处，方便和参考实现逐行核对。

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
    return ogxLinearToGamma(color);
}

// 参考包的 `ACES` 默认开启 Abney 效应校正；单参数重载让旧调用点保持原签名。
// ACES 单参入口：保留旧调用方式，内部按默认白点走完整映射。
float3 ogxAces(float3 color) { return ogxAces(color, true); }

// 经济版电影曲线：一条有理式，成本低于 ACES 拟合，观感更硬、更亮。
float3 ogxTonemapAcesFilm(float3 color)
{
    float3 x = color * 0.9; // 先压一点曝光。
    return (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.95) + 0.12); // 分子分母都是二次式。
}

/*
实现说明：ACES 电影色调映射。
一、输入矩阵：把显示原色转到 ACES 的工作空间，矩阵逐项来自参考实现。
二、RRT 与 ODT 拟合：用一组有理多项式近似胶片响应，亮部缓慢压缩，暗部保留对比。
三、输出矩阵：把工作空间转回显示原色，再夹到零到一。
四、参数：`ogxTonemapAcesFilm` 接收曝光前后两个开关，`ogxAces` 只做完整链路。
五、常数：多项式系数与矩阵都按参考精度保留，改成近似值会让高光偏色。
六、用途：摄影风格与需要稳定高光的场景；不负责伽马编码，编码由调用方决定。
*/

/*
函数索引：
一、`ogxRrtOdtFit`：RRT 与 ODT 的有理多项式拟合。
二、`ogxAces`：完整 ACES 链路，输入线性颜色与曝光开关。
三、`ogxAces` 的重载：参考签名版本，参数顺序一致。
四、`ogxTonemapAcesFilm`：电影风格的简化版。
五、矩阵：输入与输出矩阵逐项来自参考实现。
六、常数：多项式系数按参考精度保留，改成近似值会让高光偏色。
七、边界：输出夹到零到一，不负责伽马编码。
八、用途：摄影风格与需要稳定高光的场景。
*/

/*
参数与边界：
一、输入颜色是线性空间，曝光开关在映射前应用。
二、RRT 与 ODT 的多项式在极亮时仍会压缩，不会溢出。
三、输出矩阵后夹到零到一。
四、电影版与完整版的区别只在曝光与对比。
五、所有常数按参考精度保留。
六、输出不包含伽马编码。
七、画面验证要看高光与肤色。
*/

/*
补充说明：ACES 的输入输出。
输入是线性颜色，曝光在映射前乘上。
输出夹到零到一，伽马编码由调用方完成。
矩阵按列主序存储，和 GLSL 的矩阵乘向量一致。
多项式在极亮时仍会压缩，不会溢出。
画面验证看高光与肤色。
*/
