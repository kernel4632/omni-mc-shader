/*
Omni 通用图形库后期模块：泛光降采样与模糊、三次升采样、亮度曲线、暗角、颗粒、景深与测光统计。
调用位置：任何需要多级泛光、景深或最终画面处理的程序；Minecraft 光影由 `/omni-gfx/post/post.glsl` 引入。
可复制示例：
    `vec3 c = ogxBloomDownsample(source, uv, texel);` 十三样本降采样。
    `vec3 c = ogxBloomChainCopy(chain, uv, size);` 链上某级原样拷贝。
    `vec3 b = ogxAxialGaussianBlur(source, uv, scale, origin, size, axis, 0.12, 6.0, texel);` 一维高斯。
    `float r = ogxCocRadius(focus, depth, aperture);` 薄透镜弥散圆半径。
    `float avg = ogxExposureTileAverage(sceneTexture, params);` 加权平均亮度。
设计原因与取舍：
    纹理、像素大小、子图范围与模糊参数全部由调用方传入，库不读取引擎画面或屏幕尺寸。
    伽马编码沿用管线的四次方根近似，保证与原程序相同的亮度；五级泛光的子图排布属于宿主布局，
    仍留在效果层的组合函数里，这里只提供每一级的核与统计公式。
*/
#ifndef OGX_POST_INCLUDED
#define OGX_POST_INCLUDED

// 亮度权重、四次方根编码与区间重映射来自数学模块。
#include "../common/math.slang"
// 抖动要用噪声模块里的三角分布噪声。
#include "../common/noise.slang"
// 采样提供白噪声、蓝噪声与低差异序列。
#include "../common/sampling.slang"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "../shadow/shadow.slang"

// 泛光、调色与屏幕图案，具体实现在子文件。
#include "post/bloom.slang"
// 景深、散景与光圈，具体实现在子文件。
#include "post/dof.slang"
// 动态模糊、曝光分块与眩光，具体实现在子文件。
#include "post/effects.slang"

// 泛光降采样：先做四点盒式取样，再转换到线性颜色。
float3 ogxBloomDownsample(Sampler2D source, float2 coord, float2 texel)
{
    float3 blur = ogxCurveToLinear3(source.SampleLevel(coord, 0.0).rgb) * 0.125; // 中心样本。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + float2(texel.x, texel.y), 0.0).rgb) * 0.5; // 右下对角。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + float2(texel.x, -texel.y), 0.0).rgb) * 0.5; // 右上对角。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + float2(-texel.x, texel.y), 0.0).rgb) * 0.5; // 左下对角。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + float2(-texel.x, -texel.y), 0.0).rgb) * 0.5; // 左上对角。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(texel.x, 0.0), 0.0).rgb) * 0.25; // 右两像素。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(0.0, texel.y), 0.0).rgb) * 0.25; // 上两像素。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(-texel.x, 0.0), 0.0).rgb) * 0.25; // 左两像素。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(0.0, -texel.y), 0.0).rgb) * 0.25; // 下两像素。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(texel.x, texel.y), 0.0).rgb) * 0.125; // 远处右下。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处右上。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(-texel.x, texel.y), 0.0).rgb) * 0.125; // 远处左下。
    blur += ogxCurveToLinear3(source.SampleLevel(coord + 2.0 * float2(-texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处左上。
    return ogxLinearToCurve3(blur * 0.25); // 权重和为四，乘四分之一保持亮度。
}

// 自动曝光、泛光合并与夜视曲线属于后期效果，编译进同一份产物。
#include "../post/exposure.slang"
// 受伤、入水与着火等画面状态属于后期效果，编译进同一份产物。
#include "../post/scene.slang"

#endif
