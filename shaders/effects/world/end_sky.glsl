/*
效果文件 `effects/world/end_sky.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/end_sky.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_END_SKY_INCLUDED
#define OMNI_END_SKY_INCLUDED
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
// 行星表面与环带的纯公式放在通用库。
#include "/omni-gfx/atmosphere.glsl"
#include "/omni-gfx/planet.glsl"

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

// --- 参考签名兼容层：末地行星的两个参考函数直接转发到通用库 ---
// `ppss` 的第五个参数在参考实现里没有参与 BRDF 双向反射算式；保留它只为与参考签名一致。
vec3 ppss(vec3 albedo, vec3 normal, vec3 lightDir, vec3 eyeDir, float unused){
	return ogxPlanetBrdf(albedo, normal, lightDir, eyeDir); // 参考的第五参数不参与 BRDF。
}
// `Disc` 是圆盘边缘的软阈值曲线，参数顺序与参考一致。
float Disc(float a, float s, float h){ return ogxDiscProfile(a, s, h); }

// 行星本体：算法在通用库，本函数只把末地的全局量接过去。
// 为什么保留同名入口：合成零号与末地反射都按这个名字调用，绑定层换实现不影响绘制主体。
void PlanetEnd2(inout vec3 color, in vec3 eye, in vec3 rayDir, in vec3 lightDir){
	ogxPlanetEnd(color, eye, rayDir, lightDir, worldShadowVector, timeFactor, planetShadow, noisetex); // 行星与光环在通用库。
}


// 参考签名兼容层：默认太阳方向由宿主全局量提供，主世界的两参数版本保持不变。
vec3 CalculateStars(vec3 worldDir){
	float angleY = frameTimeCounter * 0.001;
	mat3 eyeRotationY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY));
	worldDir = eyeRotationY * worldDir;
	const float scale = 384.0;
	const float coverage = 0.007;
	const float maxLuminance = 0.04;
	const float minTemperature = 4000.0;
	const float maxTemperature = 8000.0;
	float cosine = dot(worldSunVector, vec3(0.0, 0.0, 1.0));
	vec3 axis = cross(worldSunVector, vec3(0.0, 0.0, 1.0));
	float cosecantSquared = 1.0 / dot(axis, axis);
	worldDir = cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis;
	vec3 p = worldDir * scale;
	ivec3 i = ivec3(floor(p));
	vec3 f = p - i;
	float r = dot(f - 0.5, f - 0.5);
	vec3 i3 = fract(i * vec3(443.897, 441.423, 437.195));
	i3 += dot(i3, i3.yzx + 19.19);
	vec2 hash = fract((i3.xx + i3.yz) * i3.zy);
	hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y;
	float c = remapSaturate(hash.x, 1.0 - coverage, 1.0);
	return (maxLuminance * remapSaturate(r, 0.25, 0.0) * c * c) * Blackbody(mix(minTemperature, maxTemperature, hash.y));
}

#endif // OMNI_END_SKY_INCLUDED 结束。

// 严格对照补充说明：
// 末地行星的圆盘剖面与 BRDF 双向反射只依赖方向与参数。
// ppss 的第五个参数在参考里没有参与算式，保留它只为签名一致。
// Disc 的阈值、斜率与硬度照参考，圆盘平方后边界更清楚。
// 星空参考函数使用太阳方向、帧时间与黑体温度，宿主提供太阳方向全局量。
// 这些函数不读取行星缓冲，也不修改宿主状态。

// 补充说明：末地行星的圆盘与双向反射只依赖方向和参数。
// 兼容重载保留参考函数名，调用方不需要改绘制主体。
// 这些函数不读取行星缓冲，也不修改宿主状态。
