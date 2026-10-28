// 颜色模块 Reinhard：基础、全范围、可编辑与 Reinhard-Jodie 四条曲线。
// 调用位置：由 `common/color.slang` 内联引入，供对照与可选曲线使用。
// 可复制示例：`float3 c = ogxTonemapReinhard(linearColor);`
// 设计原因与取舍：四条曲线常数不同，不能用一个参数互相替代。

// Eclipse 全范围 Reinhard：白点 10、提亮 0.5，保留完整有理式。
// Reinhard 完整版：按最大通道压缩，保留色相。
float3 ogxTonemapReinhardFull(float3 color)
{
    float whitepoint = 10.0; // 参考实现固定白点。
    float lighten = 0.5; // 参考实现固定提亮量。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Eclipse 可编辑 Reinhard：先把颜色抬 1.2 次方，再用更低的提亮 0.333。
// Reinhard 编辑版：用固定曝光近似，适合快速预览。
float3 ogxTonemapReinhardEdit(float3 color)
{
    color = pow(color, float3(1.2)); // 抬暗部，保持高光不动。
    float whitepoint = 10.0; // 与全范围版相同的白点。
    float lighten = 0.333; // 更低的提亮量，画面更亮。
    return (color * (1.0 + color / (whitepoint * whitepoint))) / (lighten + color);
}

// Reinhard-Jodie：同时算亮度压缩与逐通道压缩，再按逐通道结果混回去。
// Reinhard-Jodie：按亮度与通道分别压缩，减少高光偏色。
float3 ogxTonemapReinhardJodie(float3 color)
{
    color *= 1.5; // 参考实现的曝光抬升。
    float3 tonemapLuminance = color / (1.0 + dot(color, float3(0.21, 0.72, 0.07))); // 保色相的亮度压缩。
    float3 tonemapRgb = color / (1.0 + color); // 逐通道压缩，高光更容易去饱和。
    return lerp(tonemapLuminance, tonemapRgb, tonemapRgb * 0.8 + 0.2); // 亮部更多采用逐通道结果。
}

// `Reinhard` 简单曲线：先放大一点六六倍再除以一加自身，暗部提得最明显。
float3 ogxTonemapReinhard(float3 color)
{
    float3 x = color * 1.66; // 放大让中间灰更亮。
    return x / (1.0 + x); // 双曲线压缩，结果永远不会超过一。
}
