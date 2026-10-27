/*
效果文件 `effects/water/water.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/water.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_WATER_WATER_INCLUDED
#define OMNI_EFFECT_WATER_WATER_INCLUDED
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"波浪密度","en_us":"Wave scale"},"description":{"zh_cn":"水面波纹的空间频率；调大波纹更密更细。","en_us":"Spatial frequency of the water ripples; larger makes them finer."},"slider":true}
#define OMNI_WAVE_SCALE 0.05 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"波浪高度","en_us":"Wave height"},"description":{"zh_cn":"水面起伏的强度；调大波浪更明显。","en_us":"Strength of the water surface undulation; larger makes waves more visible."},"slider":true}
#define OMNI_WAVE_HEIGHT 1.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"凹凸","en_us":"Water parallax"},"description":{"zh_cn":"按波浪高度偏移水面采样，让波峰看起来真的凸起；关闭后只用法线造形。","en_us":"Offsets water sampling by wave height so crests look raised; off keeps shape from normals only."}}
#define OMNI_WATER_PARALLAX 1 // [0 1]
// @option {"label":{"zh_cn":"水下雾","en_us":"Underwater fog"},"description":{"zh_cn":"在水下或隔着水看远处时叠加雾；关闭后水更通透。","en_us":"Adds fog when underwater or looking through water; off makes the water clearer."}}
#define OMNI_UNDERWATER_FOG
// @option {"label":{"zh_cn":"水雾密度","en_us":"Water fog density"},"description":{"zh_cn":"水下与水后雾的浓度；调大看得更近。","en_us":"Density of underwater and through-water fog; larger reduces visibility."},"slider":true}
#define OMNI_WATER_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"焦散","en_us":"Water caustics"},"description":{"zh_cn":"阳光透过波动水面在水底汇聚出的亮纹。","en_us":"Bright patterns where sunlight focuses through the rippling water onto the bottom."}}
#define OMNI_CAUSTICS
// @option {"label":{"zh_cn":"水洼与涟漪范围","en_us":"Puddles & ripples"},"description":{"zh_cn":"雨点涟漪出现的位置：整个湿表面均匀铺满，还是只在低洼积水处出现。「仅水洼」还会按「水洼尺寸」决定水洼范围，并让水洼表面更光滑更暗（照 Eclipse 的 `applyPuddles`）。默认与原来一致。来源 Eclipse `lib/settings.glsl:359` 的 `PUDDLE_MODE`。","en_us":"Where rain ripples appear: evenly over the whole wet surface, or only in low-lying puddles. \"Only puddles\" also uses \"Puddle size\" to shape the puddles and makes their surface smoother and darker (Eclipse's applyPuddles). Default matches the previous behaviour. From Eclipse `lib/settings.glsl:359` `PUDDLE_MODE`."},"values":{"0":{"zh_cn":"无雨点","en_us":"Off"},"1":{"zh_cn":"水洼与全湿润","en_us":"Puddles + fully wet"},"2":{"zh_cn":"仅水洼","en_us":"Only puddles"},"3":{"zh_cn":"仅全湿润","en_us":"Only fully wet"}}}
#define OMNI_PUDDLE_MODE 1 // [0 1 2 3]
// @option {"label":{"zh_cn":"雨点涟漪强度","en_us":"Rain ripple strength"},"description":{"zh_cn":"雨点砸在水面与地面时涟漪的起伏高低，一为不变；调大涟漪更明显，取零等于不画雨点。","en_us":"Height of the ripples where raindrops hit water and ground, one is unchanged; larger makes them stronger, zero draws none."},"slider":true}
#define OMNI_RAIN_RIPPLE_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"雨点涟漪对比","en_us":"Rain ripple contrast"},"description":{"zh_cn":"雨点涟漪的明暗分离程度，一为不变；调大亮圈更锐、圈外更平，调小则整片更柔和。","en_us":"How sharply the ripple rings separate from the flat surface, one is unchanged; larger makes the rings crisper and the rest flatter, smaller makes everything softer."},"slider":true}
#define OMNI_RAIN_RIPPLE_CONTRAST 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.75 2.0 2.5 3.0]
// @option {"label":{"zh_cn":"玩家交互水面","en_us":"Player water interaction"},"description":{"zh_cn":"玩家在水里移动时，水面从玩家处向外推出一圈圈涟漪。默认关闭；Eclipse 默认用波浪模拟，本项目未移植那套计算着色器方案。来源 Eclipse `dimensions/all_translucent.fsh` 的 `WATER_INTERACTION == 1`。","en_us":"Ripples spread out from the player across the water surface while moving in water. Off by default; Eclipse defaults to its wave-simulation mode, whose compute-shader pipeline is not ported here. From Eclipse `dimensions/all_translucent.fsh` `WATER_INTERACTION == 1`."},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"简单涟漪","en_us":"Simple ripples"}}}
#define OMNI_PLAYER_WATER 0 // [0 1]
// @option {"label":{"zh_cn":"玩家涟漪强度","en_us":"Player ripple strength"},"description":{"zh_cn":"玩家水波涟漪的高低；调大涟漪更明显。上一个选项关闭时不生效。","en_us":"Height of the player water ripples; larger makes them more visible. Has no effect while the option above is off."},"slider":true}
#define OMNI_PLAYER_WATER_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
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
#include "/effects/ground/material.glsl"
// 局部降水开关决定雨点涟漪是否跟随降雨，归属天气文件。
#include "/effects/weather/weather.glsl"
// 玩家交互水面：玩家在水里移动时带起的一圈圈涟漪，独立成文件让水面文件保持聚焦。
#include "/effects/water/playerwater.glsl"
// 水洼：提供 `OmniPuddleCoverage`（雨点涟漪与合成阶段的水洼覆盖）、`OmniPuddleRoughness` 与 `OmniPuddleSurface`；默认取值不额外改画面。
#include "/effects/water/puddle.glsl"

// 基础波浪与物理解析波浪。
#include "/effects/water/waves.glsl"
// 雨点涟漪。
#include "/effects/water/rain.glsl"
// 水雾。
#include "/effects/water/waterfog.glsl"
// 水面折射与彩色透光吸收。
#include "/effects/water/refraction.glsl"
// Eclipse 水面波函数兼容层。
#include "/effects/water/eclipse_bump_adapters.glsl"
#endif // OMNI_EFFECT_WATER_WATER_INCLUDED
