// 颜色模块 Uchimura：基础三段曲线、指数肩部版与平滑肩部版。
// 调用位置：由 `common/color.slang` 内联引入，供对照与可选曲线使用。
// 可复制示例：`float3 c = ogxTonemapUchimura(linearColor);`
// 设计原因与取舍：参考实现的肩部与平滑顺序保留，避免改变高光过渡。

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

// Eclipse 的 Uchimura 指数肩部版：肩部用 exp，参考实现保留反向 smoothstep 参数顺序。
// Uchimura 指数版：按分段指数压缩高光，适合夜景。
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
// Uchimura 改进版：用可调切线参数控制肩部过渡。
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
