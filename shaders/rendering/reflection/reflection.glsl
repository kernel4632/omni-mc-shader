/*
反射的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/reflection/reflection.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_REFLECTION_REFLECTION_INCLUDED
#define OMNI_RENDER_REFLECTION_REFLECTION_INCLUDED
#include "/effects/reflection/reflection.glsl"
/*
屏幕空间反射：照 iterationT `Lib/IndividualFounctions/Reflections/SSR.glsl`、
`Reflections/ReflectionFilter.glsl` 与 `composite2.fsh`、`composite5.fsh` 的反射段一比一移植。
职责分成四块：
  一、玩家选项：光线步进质量、细化步数与深度差阈值，照 iterationT `Settings.glsl` 带取值范围的菜单项，全项目只在这里定义一次；
  二、屏幕空间追踪：`ScreenSpaceTracer` 沿反射方向在屏幕里找被反射到的几何，`sampleGGXVNDF` 给粗糙面抽样方向；
  三、反射合成：`CalculateSpecularReflections` 有重载两份，一份写三号画面（`composite2`），一份就地合并进场景色（`composite5`）；
  四、反射滤波：`AtrousWaveletFilter` 对三号画面做小波滤波，供 `composite3`、`composite4` 两次半径调用。
调用位置：
  `rendering/composite.glsl` 的 `composite2` 程序算反射并写三号画面；
  `rendering/composite.glsl` 的 `composite3`、`composite4` 程序对三号画面做小波滤波；
  `rendering/composite.glsl` 的 `composite5` 程序把三号画面的反射合并进场景色。
可复制示例：
  `compositeOutput3 = CalculateSpecularReflections(viewPos, worldPos, viewDir, normal, gbufferdepth, albedo, material, skylight, isHand, isSmooth, highlightStrength);`
  `CalculateSpecularReflections(color, viewDir, normal, albedo, waterAbsorption, material);`
  `AtrousWaveletFilter(reflectionData, viewPos, viewDir, normal, roughness, 40.0, vec2(0.0));`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `texelCoord`、`texCoord`、`gbufferModelViewInverse`、`gbufferProjection`、
  `worldSunVector`、`worldMoonVector`、`shadowVector`、`colorSunlight`、`colorMoonlight`、`colorShadowlight`、
  `timeNoon`、`wetness`、`eyeNoPrecipitationSmooth`、`isEyeInWater`、`far`、`colortex1`…`colortex5`、`depthtex0`、`depthtex1` 由合成主程序声明；
  本文件按阶段引入所需效果文件：`composite2` 引入雾与天空云反射，`composite5` 只引入材质，`composite3`/`composite4` 只引入坐标。
关键设计原因与取舍：
  原程序把 `ProjectSky` 写在 SSR 与天空两处，按合同只在 `effects/sky/sky.glsl` 保留一份，本文件直接调用；
  两份 `CalculateSpecularReflections` 参数不同、用途不同，原程序靠所在程序区分，这里按程序宏 `OMNI_COMPOSITE2_PASS`、`OMNI_COMPOSITE5_PASS` 分开，避免把只属于反射通道的采样编译进滤波通道；
  接近全反射的像素（`colortex1` 的 a 通道大于零点五）直接取当前场景色，避免反射处出现黑洞。
    本文件按算法拆到同目录：屏幕空间反射与着色在 `screenspace.glsl`，反射小波滤波在 `denoise.glsl`；引入顺序与拆分前逐字一致。
*/

// --- 玩家选项：光线步进质量、细化步数与深度差阈值，照 iterationT `Lib/Settings.glsl` 带取值范围的菜单项 ---
// 数学提供光照模型与颜色曲线，坐标换算提供屏幕与视空间互转，两份都供三个通道共用。
#include "/common/math.glsl"
#include "/common/coordinates.glsl"

// 屏幕空间反射追踪与着色：只在 composite2 / composite5 程序里编译。
#include "/rendering/reflection/screenspace.glsl"
// 反射小波滤波：只在 composite3 / composite4 程序里编译。
#include "/rendering/reflection/denoise.glsl"
#endif // OMNI_RENDER_REFLECTION_REFLECTION_INCLUDED
