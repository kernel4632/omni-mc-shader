/*
末地星空与行星：星空复用主世界那份 Eclipse 星场，行星部分再用射线求交画地表、光环与大气。
来源：行星、吸积盘与雾照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 移植；星空按用户要求换成
  Eclipse `lib/stars.glsl`，与主世界共用 `effects/sky/sky.glsl` 的 `CalculateStars`，不再是 iterationT 的末地星空，
  差异记入 `docs/parity.md` 偏离记录与 `docs/eclipse-parity.md`「星空」行。
职责：`EndCalculateStars` 转发主世界星场并画出末地星空，`H`、`ppss`、`Disc` 是行星表面的
  双向反射近似，`PlanetEnd2` 画整颗行星本体、光环与大气。
调用位置：由 `effects/world/end.glsl` 引入；`rendering/composite.glsl` 的合成零号在末地天空像素调用
  `PlanetEnd2`，合成二号经 `ComputeFakeSkyReflectionEnd` 调用。
可复制示例：`PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector);`
调用前提：由 `effects/world/end.glsl` 在声明 `timeFactor`、`planetShadow` 之后、且已引入
  `effects/sky/sky.glsl` 之后引入；`worldSunVector`、`worldShadowVector`、`noisetex`、`MiePhaseFunction`、
  `RaySphereIntersection`、`RayPlaneIntersection`、`curve` 由绘制主体与 `common/math.glsl` 提供，本文件不重复引入；
  `CalculateStars` 由 `effects/sky/sky.glsl` 提供。
关键设计原因与取舍：行星是屏幕空间的解析积分，不改写几何；末地天空整幅由这里画出，不走预计算大气。
  星空不再单独维护一份，与主世界共用同一份 Eclipse 星场，星点形态在两个维度保持一致，也避免复制代码。
*/
#ifndef OMNI_END_SKY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_SKY_INCLUDED // 置上标记，后续再次引用直接跳过。
// 行星表面与环带的纯公式放在通用库。
#include "/gfx/atmosphere.glsl"
#include "/gfx/planet.glsl"

// --- 星空：与主世界共用同一份 Eclipse 星场，来源 Eclipse `lib/stars.glsl`（经 `effects/sky/sky.glsl`） ---
// 为什么共用：用户要求末地星空也换成 Eclipse 的实现，而主世界已把星场核换成 Eclipse；
//   共用同一份函数可保证两个维度的星点形状、疏密与星色一致，也不必把星场代码复制两份。
// 与旧 iterationT 末地星空的差异：星点由「三维格子哈希」换成 Eclipse 的稳定星场；
//   星场朝向沿用主世界 `CalculateStars` 的「绕日轴对齐天球」，不再单独按时间绕竖直轴旋转。
// 调用位置：`effects/world/end_disc.glsl` 的 `BlackHole_AccretionDisc_Stars` 在 `OMNI_STAR_TYPE > 0` 时调用。
// 签名与原 `EndCalculateStars` 一致（只吃世界方向），调用方不用改；太阳方向由全局量 `worldSunVector` 取。
vec3 EndCalculateStars(vec3 worldDir){
	return CalculateStars(worldDir, worldSunVector); // 直接复用主世界星场。
}

// 行星本体：算法在通用库，本函数只把末地的全局量接过去。
// 为什么保留同名入口：合成零号与末地反射都按这个名字调用，绑定层换实现不影响绘制主体。
void PlanetEnd2(inout vec3 color, in vec3 eye, in vec3 rayDir, in vec3 lightDir){
	gfx_planet_end(color, eye, rayDir, lightDir, worldShadowVector, timeFactor, planetShadow, noisetex); // 行星与光环在通用库。
}

#endif // OMNI_END_SKY_INCLUDED 结束。
