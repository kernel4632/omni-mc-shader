/*
水面的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/water/water.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_WATER_WATER_INCLUDED
#define OMNI_RENDER_WATER_WATER_INCLUDED
#include "/effects/water/water.glsl"
/*
水面：把 iterationT 的波浪、海洋物理波、雨点涟漪、水下雾、折射与彩色玻璃吸收集中到一个文件。
职责分成四块：
  一、选项：`OMNI_WAVE_SCALE`、`OMNI_WAVE_HEIGHT`、`OMNI_WATER_PARALLAX`、`OMNI_UNDERWATER_FOG`、`OMNI_WATER_FOG_DENSITY`、`OMNI_CAUSTICS`、
    雨点涟漪范围 `OMNI_PUDDLE_MODE`（照 Eclipse `lib/settings.glsl:359` 的 `PUDDLE_MODE`，默认与原来一致）与其强度 `OMNI_RAIN_RIPPLE_STRENGTH`、对比 `OMNI_RAIN_RIPPLE_CONTRAST`（默认都为一，与原来一致），
    以及玩家交互水面 `OMNI_PLAYER_WATER` 与其强度 `OMNI_PLAYER_WATER_STRENGTH`，全项目只在这里定义一次；
  二、波浪：`GetWaves`、`GetWavesNormal`、`GetWaterParallaxCoord` 用噪声贴图叠多层正弦，算出波高、波法线与视差坐标；
  三、物理海浪：`physics_*` 一组函数按迭代正弦合成海面，供海洋物理扩展使用；
  四、屏幕合成：`WaterFog` 水下与水面雾、`RefractSampleOnce` 折射、`TransparentAbsorption` 彩色玻璃吸收，以及雨点涟漪 `GetRainNormal`；
  五、玩家交互水面：玩家在水里移动时的一圈圈涟漪，算法在同目录 `playerwater.glsl`，`GetWavesNormal` 把它叠到波法线上。
调用位置：
  `rendering/translucent.glsl` 顶点阶段用 `GetWaterParallaxCoord`、`GetWavesNormal` 抬升水面并造波；
  `rendering/composite.glsl` 屏幕合成阶段用 `WaterFog`、`RefractSampleOnce`、`TransparentAbsorption`；
  `effects/shadow/shadow.glsl` 的焦散读取七号画面里的波法线，与本文件共用 `GetWavesNormal` 写出的数据。
可复制示例：
  `vec3 normal = GetWavesNormal(worldPos, OMNI_WAVE_HEIGHT);`  由世界位置得到波法线；
  `WaterFog(color, viewDir, opaqueDist, waterDist, normal, mask, occludedWater, waterSkylight, totalInternalReflection);`  水下与水后雾。
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `MaterialMask` 结构由 `effects/ground/material.glsl` 提供（本文件已显式引入）；
  `ivec2 texelCoord`、`vec2 screenCoordInput` 由延迟与合成主程序声明；
  `in vec3 colorShadowlight`、`in vec3 colorSkylight` 等光色输入由合成主程序声明；
  物理海浪的 `physics_*` 输入由外部海洋物理扩展提供，缺失时对应函数不被调用，不影响基础水面；
  雨点涟漪的降雨强度由 `bind/weather.glsl` 从 `rainStrength` 转换，`gaux1`、`gaux2`、`gaux3` 三张动画贴图由几何阶段主程序声明。
关键设计原因与取舍：
  波浪高度与法线都从 `GetWaves` 一处取，顶点抬升和片元法线不会各写一套而对不上；
  折射采样附带防泄漏：偏移后的位置若落在水面前方就退回原位，避免前景颜色漏进水里；
  水下雾与彩色玻璃吸收只用分波段衰减，红衰减最快、蓝最慢，水越深越偏青绿；
  折射函数 `RefractSampleOnce` 就是 iterationT `composite5.fsh` 的 `WaterRefractionLite`，下界、末地各有一份加 `Nether`、`End` 后缀；
    移植后改名，是为了说明它只把采样坐标偏移一次再读回场景色，原来的 `Lite` 说不清和谁比、差在哪。
    本文件按算法拆到同目录：基础与物理解析波浪在 `waves.glsl`，雨点涟漪在 `rain.glsl`，水雾在 `waterfog.glsl`，折射与透光吸收在 `refraction.glsl`；引入顺序与拆分前逐字一致。
*/


// 波法线解码与颜色曲线来自共用计算，屏幕还原与投影来自坐标换算，`MaterialMask` 由材质文件提供。
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
#include "/bind/ground/material.glsl"
// 局部降水开关决定雨点涟漪是否跟随降雨，归属天气文件。
#include "/rendering/weather/weather.glsl"
// 玩家交互水面：玩家在水里移动时带起的一圈圈涟漪，独立成文件让水面文件保持聚焦。
#include "/rendering/water/playerwater.glsl"
// 水洼：提供 `OmniPuddleCoverage`（雨点涟漪与合成阶段的水洼覆盖）、`OmniPuddleRoughness` 与 `OmniPuddleSurface`；默认取值不额外改画面。
#include "/rendering/water/puddle.glsl"

// 基础波浪与物理解析波浪。
#include "/rendering/water/waves.glsl"
// 雨点涟漪。
#include "/rendering/water/rain.glsl"
// 水雾。
#include "/rendering/water/waterfog.glsl"
// 水面折射与彩色透光吸收。
#include "/rendering/water/refraction.glsl"
// Eclipse 水面波函数兼容层。
#include "/rendering/water/eclipse_bump_adapters.glsl"
#endif // OMNI_RENDER_WATER_WATER_INCLUDED
