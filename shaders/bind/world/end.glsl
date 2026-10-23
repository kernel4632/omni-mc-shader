/*
末地的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/world/end.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_WORLD_END_INCLUDED
#define OMNI_BIND_WORLD_END_INCLUDED
#include "/effects/world/end.glsl"
/*
末地天空与雾：画出末地特有的星空、行星、吸积盘光环、大气雾与主岛光源，全部按时间因子旋转。
来源：行星、吸积盘与雾照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 一比一移植，同名冲突函数按移植合同九点五节
  加 `End` 前缀（`Calculate3DNoise`）；星空按用户要求换成 Eclipse `lib/stars.glsl`，复用主世界
  `effects/sky/sky.glsl` 的 `CalculateStars`，`EndCalculateStars` 只做转发，差异记入 `docs/parity.md` 偏离记录；
  末地雾的两个密度选项来自 Eclipse（`lib/settings.glsl:911-912`），按 `docs/eclipse-parity.md` 第 39 行合并，默认取中性值；
  主岛光源的来源、选项与阴影相机见 `effects/world/end_island_light.glsl`；体积涡旋雾来自 Eclipse `lib/end_fog.glsl`，默认关闭。
职责：本文件是末地效果入口，集中定义末地天空、吸积盘与雾的选项与内部常数，声明 `timeFactor`、`planetShadow` 两个全局量，
  并按依赖顺序引入各算法分文件：
  星空与行星 `effects/world/end_sky.glsl`；吸积盘 `effects/world/end_disc.glsl`；末地雾与体积涡旋雾 `effects/world/end_fog.glsl`；
  主岛光源 `effects/world/end_island_light.glsl`；反射、折射与彩色玻璃吸收 `effects/world/end_reflection.glsl`。
调用位置：
  `rendering/composite.glsl` 的合成零号在末地天空像素上调用 `BlackHole_AccretionDisc_Stars` 与 `PlanetEnd2`；
  合成零号在有几何的像素上、开启 `OMNI_END_ISLAND_LIGHT` 时调用 `EndIslandLighting` 叠主岛光源；
  合成二号在末地反射回退里调用 `BlackHole_AccretionDisc_Reflection`、`PlanetEnd2` 与只叠散射的 `EndFog`；
  合成五号在末地水雾里调用返回散射色加剩余透射率的 `EndFogWithTransmittance`。
可复制示例：
  `BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector);`
  `PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector);`
  `vec4 endFog = EndFogWithTransmittance(waterDist, worldDir); color = color * endFog.a + endFog.rgb;`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明或先引入）：
  `worldSunVector`、`worldShadowVector` 是绘制主体声明的光方向全局量（合成程序里是顶点阶段传入的 `in`）；
  `frameTimeCounter`、`noisetex`、`cameraPosition` 由 `common/uniforms.glsl` 提供，`MiePhaseFunction`、`Blackbody`、
  `RaySphereIntersection`、`RayPlaneIntersection`、`remapSaturate`、`curve`、`saturate`、`InterleavedGradientNoise`、
  `Fd_Burley`、`SpecularGGX` 由 `common/math.glsl` 提供，`BlueNoiseTemporal` 由 `common/noise.glsl` 提供；
  `OMNI_SUNLIGHT_INTENSITY` 由 `effects/lighting/sunlight.glsl` 提供，`OMNI_STAR_TYPE` 与星场 `CalculateStars` 由 `effects/sky/sky.glsl` 提供，
  `OMNI_TAA` 由 `effects/clarity/antialiasing.glsl` 提供；这些都必须在引入本文件之前引入。
关键设计原因与取舍：
  原程序在文件顶部用 `frameTimeCounter` 与旋转周期算出 `timeFactor` 与 `planetShadow` 两个全局量，本文件照搬，
  所以这些全局量与 `frameTimeCounter` 挂钩，同一帧内多次调用不会重复计算；
  吸积盘与行星都是屏幕空间的解析积分，不改写几何，末地天空整幅由这里画出，不走预计算大气；
  主岛光源照 Eclipse 另建一盏竖直向下的阴影相机，矩阵只用 `cameraPosition` 就地构造、不需要计算着色器，见 `effects/world/end_island_light.glsl`；
  体积涡旋雾的取舍见 `effects/world/end_fog.glsl` 的文件头。
*/

// --- 时间因子：整颗末地天空按它旋转 ---
// 手动相位时取固定角度，否则按累计时间除以公转周期循环。零点二八二是原程序的起始相位。
// 累计秒数由绑定层提供，下面只做周期换算。
#include "/bind/time.glsl"
#ifdef OMNI_END_MANUAL_PLANET_CYCLE
	const float timeFactor = fract(OMNI_END_MANUAL_PLANET_ANGLE / 360.0 + 0.282) * TAU; // 手动相位换算成弧度。
#else
	float timeFactor = fract(bind_time().seconds * ((1.0 / 60.0) / OMNI_END_PLANET_CYCLE) + 0.282) * TAU; // 由时间推进的相位。
#endif

// 行星阴影：相位落在两段里时行星本体挡住光环，光环那一侧变暗。
float planetShadow = smoothstep(0.62, 0.35, timeFactor) + smoothstep(1.6, 1.87, timeFactor);

// 末地的几个算法体按内容拆到同目录的子文件夹，这里按依赖顺序引入。
#include "/bind/world/end_sky.glsl"
#include "/bind/world/end_disc.glsl"
#include "/bind/world/end_fog.glsl"
#include "/bind/world/end_island_light.glsl"
#include "/bind/world/end_reflection.glsl"
#endif // OMNI_BIND_WORLD_END_INCLUDED
