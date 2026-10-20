/*
后期程序的共用片元依赖：按固定顺序引入景深、动态模糊、泛光与合并泛光需要的效果文件。
调用位置：由 `rendering/post_pass6.glsl`、`post_pass8.glsl` 到 `post_pass14.glsl` 的片元阶段引入。
可复制示例：在 `#if defined OMNI_FRAGMENT` 里写一行 `#include "/rendering/post_fragment_deps.glsl"`。
设计原因与取舍：这九个程序原来各抄一份十一行引入表，顺序错一处就会看到未定义的选项宏；
    集中到本文件后顺序只有一份，程序文件只保留自己的输出声明与一次效果调用。
    只属于时间抗锯齿、锐化与放大的依赖更少，仍由各自文件单独引入，避免把用不到的整份效果编译进来。
*/
#ifndef OMNI_POST_FRAGMENT_DEPS_INCLUDED
#define OMNI_POST_FRAGMENT_DEPS_INCLUDED

// 后期共享声明，全项目只声明一次。
#include "/effects/clarity/post_shared.glsl"
// 材质编号（并提供视差与材质选项）。
#include "/effects/ground/material.glsl"
// 提供 `OMNI_TAA` 与时间抗锯齿选项，并带入坐标换算。
#include "/effects/clarity/antialiasing.glsl"
// 提供雨可见度等选项，泛光的合并读它。
#include "/effects/weather/weather.glsl"
// 提供水下雾开关与浓度选项，泛光的合并读它。
#include "/effects/water/water.glsl"
// 提供体积雾选项，并带入水面、阴影、天空、云与光照依赖。
#include "/effects/fog/fog.glsl"
// 坐标与深度换算。
#include "/common/coordinates.glsl"
// 时间噪声，景深与动态模糊的抖动读它。
#include "/common/noise.glsl"
// 曝光统计、曝光值与强光压缩曲线。
#include "/effects/color/color.glsl"
// 景深、动态模糊、暗角与镜头光斑。
#include "/effects/lens/lens.glsl"
// 泛光降采样、轴向模糊与合并泛光。
#include "/effects/color/bloom.glsl"

#endif // 文件守卫结束。
