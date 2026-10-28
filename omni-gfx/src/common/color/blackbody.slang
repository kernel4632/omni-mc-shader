// 颜色模块黑体近似：按色温拟合 RGB，再转线性显示色。
// 调用位置：由 `common/color.slang` 内联引入，光源色与调试色温共用。
// 可复制示例：`float3 c = ogxBlackbodyApprox(6500.0);`
// 设计原因与取舍：这是 Eclipse 的拟合曲线，与数学模块的普朗克轨迹版不同。

// Eclipse 黑体色：按温度拟合 RGB，再转线性；和普朗克轨迹版是两个不同近似。
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
