/*
效果文件 `effects/world/end_disc.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/end_disc.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_END_DISC_INCLUDED
#define OMNI_END_DISC_INCLUDED
/*
末地吸积盘：把天空版与反射版需要的噪声与时间接进通用库，函数名与调用点保持不变。
来源：iterationT `Lib/IndividualFounctions/EndSky.glsl`；吸积盘积分在 `gfx/accretion.glsl`。
调用位置：由 `effects/world/end.glsl` 引入；合成零号调用天空版，`ComputeFakeSkyReflectionEnd` 调用反射版。
可复制示例：`BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector);`
调用前提：由 `effects/world/end.glsl` 引入，且已先引入 `effects/world/end_sky.glsl`（提供 `EndCalculateStars`）；
  `noisetex`、`frameTimeCounter`、`BlueNoiseTemporal`、`InterleavedGradientNoise`、`OMNI_TAA`、
  `OMNI_STAR_TYPE`、`OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE` 与 `OMNI_ACCRETIONDISC_DOPPLER_EFFECT` 由绘制主体与共享文件提供。
关键设计原因与取舍：积分、空间扭曲、圆环辉光与多普勒调制都在通用库；
  本文件只选天空版或反射版的步数、起点与噪声幂次，并决定是否叠星空；星空仍属末地天空业务，留在效果层。
*/
// 吸积盘积分在通用库。
#include "/omni-gfx/accretion.glsl"
// 吸积盘的云噪声随时间流动，时间从绑定层取。
#include "/bind/time.glsl"

// --- 吸积盘（天空版）：沿视线在黑洞附近步进，累加盘的颜色，再叠星空 ---
void BlackHole_AccretionDisc_Stars(inout vec3 color, in vec3 rayDir, in vec3 lightDir){
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声，抖动被时间平均掉。
		float noise = BlueNoiseTemporal().x; // 每帧变化的噪声。
	#else // 否则用屏幕空间的固定噪声。
		float noise = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
	#endif
	vec4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noisetex, bind_time().seconds, 50, 3.0, 4,
		OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE != 0, OMNI_ACCRETIONDISC_DOPPLER_EFFECT != 0); // 天空版五十步、起点三米、噪声四次方。

	#if OMNI_STAR_TYPE > 0 // 打开星空才画星星。
		color += CalculateStars(rayDir); // 参考的末地星空用 iterationT 星场，不是主世界稳定星场。
	#endif

	color *= disc.a; // 前面的天光被吸积盘吃掉。
	color += disc.rgb; // 叠上吸积盘颜色。
}

// --- 吸积盘（反射版）：步进更少，供屏幕反射的假天空回退使用 ---
void BlackHole_AccretionDisc_Reflection(inout vec3 color, in vec3 rayDir, in vec3 lightDir){
	float noise = BlueNoiseTemporal().x; // 每帧变化的噪声；反射版始终用时间噪声。
	vec4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noisetex, bind_time().seconds, 30, 4.0, 5,
		OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE != 0, OMNI_ACCRETIONDISC_DOPPLER_EFFECT != 0); // 反射版三十步、起点四米、噪声五次方。

	color *= disc.a; // 前面天光被吃掉。
	color += disc.rgb; // 叠吸积盘颜色。
}
#endif // OMNI_END_DISC_INCLUDED
