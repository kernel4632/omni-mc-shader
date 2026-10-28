/*
效果文件 `effects/world/end_fog.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/end_fog.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_END_FOG_INCLUDED
#define OMNI_END_FOG_INCLUDED
/*
末地雾：把宿主选项、时间与相机数据转成通用库参数，并区分两种返回形状。
来源：解析雾照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 的 `EndFog`；体积涡旋雾照 Eclipse
  `lib/end_fog.glsl`（`docs/eclipse-parity.md` 第 39 行列出的未合并项「体积末地雾（涡旋）」）。
职责：本文件只保留选项接线、按远景与时间抗锯齿选择步进参数，然后调用 `/omni-gfx/fog/fog.glsl`；
  `EndVortexFog` 处理涡旋体积雾的宿主分支，`EndFogLayers` 叠加解析雾与体积雾，
  `EndFogWithTransmittance` 把散射色与剩余透射率一起交回合成阶段，`EndFog` 只交回散射色给反射与折射。
调用位置：由 `effects/world/end.glsl` 引入；合成五号经 `EndFogWithTransmittance` 调用，
  末地反射与末地折射经 `EndFog` 调用。
可复制示例：
  `vec4 endFog = EndFogWithTransmittance(waterDist, worldDir); color = color * endFog.a + endFog.rgb;`
  `color += EndFog(waterDist, worldDir);`
调用前提：由 `effects/world/end.glsl` 在声明 `timeFactor`、`planetShadow` 之后引入；体积涡旋雾默认关闭，
  关闭时整段不编译，连采样都不生成。
关键设计原因与取舍：雾的形状、光照与步进公式全部在通用库，宿主只决定步数与开关；
  体积涡旋雾会挡住背景，需要把剩余透射率带回合成阶段，而反射与折射的调用点只能加色，
  所以同一段雾用两个函数名区分，见末尾两个函数的说明。
*/
// 末地涡旋雾的纯计算放在通用库，这里只传时间、采样器与画质参数。
// 阳光、天光、底光与火把亮度由共享光照文件统一定义。
#include "/effects/shared/light.glsl"
#include "/omni-gfx/fog/fog.glsl"
// 相机位置与动画时间由绑定层整理，效果文件不再直接读宿主输入。
#include "/bind/camera.glsl"
#include "/bind/time.glsl"

#if OMNI_END_VORTEX_FOG // 开关关闭时整段不编译，默认画面与采样都省掉。

// 沿视线步进体积涡旋雾，返回散射色与剩余透射率；这里只做宿主分支，算法在通用库。
// `rgb` 是叠加到画面上的散射色，`a` 是透过雾后剩余的透射率，供合成阶段压暗背景。
vec4 EndVortexFog(vec3 worldDir, float viewDist){
	float verticalFactor = pow(abs(worldDir.y), 2.0); // 视线的竖直程度，越水平就用越远的步进距离。
	#ifdef DISTANT_HORIZONS // 开远景时步进更多、切得更远，覆盖远景区块。
		const int SAMPLECOUNT = 19; // 步数。
		const float expFactor = 33.0; // 指数分布底数，越大近处越密。
		float maxDist = mix(800.0, 300.0, verticalFactor); // 步进上限：水平看远、竖直看近。
	#else // 没有远景时步数少一些。
		const int SAMPLECOUNT = 15; // 步数。
		const float expFactor = 11.0; // 指数分布底数。
		float maxDist = mix(380.0, 300.0, verticalFactor); // 步进上限。
	#endif
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声抖动步进，抖动会被时间平均掉。
		float dither = BlueNoiseTemporal().x; // 每帧变化的抖动值。
	#else // 否则用屏幕空间固定噪声。
		float dither = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
	#endif
	vec3 vortexColor = vec3(OMNI_END_VORTEX_LIGHT_R, OMNI_END_VORTEX_LIGHT_G, OMNI_END_VORTEX_LIGHT_B) * 0.25; // 光柱颜色，零点二五是原程序的缩放。
	vec3 ambientColor = vec3(OMNI_END_VORTEX_AMBIENT_R, OMNI_END_VORTEX_AMBIENT_G, OMNI_END_VORTEX_AMBIENT_B); // 雾内环境光颜色。
	return ogxEndVortexFog(bind_camera().position, worldDir, viewDist, dither, SAMPLECOUNT, expFactor, maxDist,
		vortexColor, ambientColor, OMNI_END_VORTEX_STORM_DENSITY, 0.001 * OMNI_END_VORTEX_HAZE_DENSITY,
		bind_time().seconds, noisetex, float(noiseTextureResolution), 1e-3 * OMNI_SUNLIGHT_INTENSITY); // 全部纯计算转交通用库。
}
#endif // 体积涡旋雾结束。

// --- 末地雾：按视线方向与行星相位算出一层很淡的定向雾 ---
// 为什么用行星相位而不是距离：末地的雾来自背景行星的散射，方向与相位决定它的浓淡。
// 为什么返回 `vec4`：解析雾只加色不遮挡，但体积涡旋雾会挡住背景，需要把剩余透射率一起带回；
//   所以前三分量是散射色、第四分量是剩余透射率，两种调用点各取所需。
vec4 EndFogLayers(float dist, vec3 worldDir){
	float VdotL = dot(worldShadowVector, worldDir); // 视线与光方向夹角余弦。

	float angleX = -1.57079633 + (0.2 * sin(timeFactor + 3.0) - 0.1) - 0.008 * sin(timeFactor + 4.7); // 俯仰角，比行星多一项。
	float angleY = timeFactor; // 偏航角。

	float density = ogxEndFogDensity(worldDir, dist, VdotL, angleX, angleY, planetShadow,
		OMNI_END_FOG_STORM_DENSITY, OMNI_END_FOG_HAZE_DENSITY); // 解析雾的密度在通用库计算，两个选项在这里传入。
	vec3 fog = vec3(density * 1e-5 * OMNI_SUNLIGHT_INTENSITY); // 解析雾的贡献，换算到管线单位并乘阳光强度。

	float transmittance = 1.0; // 解析雾只加色不遮挡，默认全透；只有体积涡旋雾会把它压下来。
	#if OMNI_END_VORTEX_FOG // 打开涡旋体积雾时再沿视线叠一层，关闭时这一行不生成，透射率保持为一。
		vec4 vortex = EndVortexFog(worldDir, dist); // 体积涡旋雾的散射色与剩余透射率。
		fog += vortex.rgb; // 散射色照旧叠加。
		transmittance = vortex.a; // 交回体积雾的透射率，供合成阶段压暗背景。
	#endif

	return vec4(fog, transmittance); // rgb 是散射色、a 是剩余透射率。
}

// 只叠散射的入口：末地反射与末地折射调用它，调用点是 `color += EndFog(...)`，只需要散射色。
// 为什么保留这个形状：反射文件与末地折射文件的调用点本次不改，它们只能加色、不能乘透射率。
vec3 EndFog(float dist, vec3 worldDir){
	return EndFogLayers(dist, worldDir).rgb; // 丢掉透射率，只交回散射色；涡旋雾关闭时与旧行为逐位一致。
}

// 散射加透射率的入口：合成五号调用它，按 `color = color * a + rgb` 先把背景压暗再叠散射。
// 为什么单独用一个名字：末地三个调用点同是 `(float, vec3)`，无法靠重载区分，只能各用不同函数名。
vec4 EndFogWithTransmittance(float dist, vec3 worldDir){
	return EndFogLayers(dist, worldDir); // 转交公共计算，散射色与透射率一并带回。
}
// --- Eclipse 末地雾兼容层：参考函数自己取时间与噪声贴图 ---
void SwirlAroundOrigin(inout vec3 alteredOrigin, vec3 origin){
	ogxEndVortexSwirl(alteredOrigin, origin, frameTimeCounter);
}
float fogShape(vec3 pos){
	return ogxEndVortexShape(pos, frameTimeCounter, noisetex, 512.0);
}
float cloudVol(vec3 pos){
	return ogxNetherFogCloudVolume(pos, frameTimeCounter, noisetex);
}
float densityAtPosFog(vec3 pos){
	return ogxStormNoise(pos, noisetex, 512.0);
}
#endif // OMNI_END_FOG_INCLUDED
