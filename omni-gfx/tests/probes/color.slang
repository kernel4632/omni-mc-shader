/*
颜色模块编译探针：调用全部公开函数，供 Slang 生成 SPIR-V 时检查类型与常量。
调用位置：`omni-gfx/build.py spirv`；探针只验证，不进入光影包。
设计原因与取舍：
    颜色函数的分支靠布尔参数覆盖，两条路径都写一次，避免只编到默认分支。
*/
#include "../../src/color.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float3 linearColor = float3(position.x * 0.001, 0.2, 0.4);  // 一个在显示范围附近的线性颜色。
    float3 displayColor = ogxLinearToGamma2(linearColor);  // 先得到显示空间颜色。
    float3 acc = ogxGammaToLinear2(displayColor);  // 再转回线性，两个方向都覆盖。
    acc += ogxAces(linearColor, true) + ogxAces(linearColor, false);  // 两条 ACES 分支。
    acc += ogxAgx(linearColor, 13.0, true) + ogxAgx(linearColor, 13.0, false);  // 两条 AgX 分支。
    acc += ogxTonemapNone(linearColor);  // 无压缩路径。
    acc += ogxTonemapHejl(linearColor) + ogxTonemapHable(linearColor);  // 两条胶片曲线。
    acc += ogxTonemapReinhard(linearColor) + ogxTonemapLottes(linearColor);  // 简单曲线与肩部曲线。
    acc += ogxTonemapUchimura(linearColor) + ogxTonemapAcesFilm(linearColor);  // 三段拼接曲线与经济版电影曲线。
    acc += ogxLinearToSrgb(linearColor);  // 标准 sRGB 分段编码。
    acc += ogxBlackBar(float2(0.5, 0.5), 1.7, 2.35) * linearColor;  // 黑边判断返回标量。
    acc += ogxPurkinje(linearColor, 0.5, 1.0);  // 暗视觉偏移。
    acc += ogxWhiteBalance(linearColor, float3(1.0, 0.98, 0.95));  // 白平衡。
    acc += ogxAdvancedColor(displayColor, 1.0, 0.0, 1.0, 1.0);  // 高级调色。
    float3 hsv = ogxRgbToHsv(linearColor);  // 借数学模块转色相。
    acc += ogxHsvToRgb(hsv);  // 再转回颜色。
    acc += ogxSrgbToLinear(displayColor);  // sRGB 近似解码。
    acc += ogxApplyColumns(float3(1.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), float3(0.0, 0.0, 1.0), linearColor);  // 三列乘向量。
    return float4(acc, 1.0);  // 有输出即可，数值本身不参与测试。
}
