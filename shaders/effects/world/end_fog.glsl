/*
末地雾：按视线方向与行星相位算出一层很淡的定向雾，并可叠一层体积涡旋雾。
来源：解析雾照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 的 `EndFog`；体积涡旋雾照 Eclipse
  `lib/end_fog.glsl`（`docs/eclipse-parity.md` 第 39 行列出的未合并项「体积末地雾（涡旋）」）。
职责：`EndVortex*` 生成一团绕主岛旋转的浓雾、光柱与雾霭；
  `EndFogWithTransmittance` 把散射色与剩余透射率一起交回合成阶段，`EndFog` 只交回散射色给反射与折射。
调用位置：由 `effects/world/end.glsl` 引入；合成五号经 `EndFogWithTransmittance` 调用，
  末地反射与末地折射经 `EndFog` 调用。
可复制示例：
  `vec4 endFog = EndFogWithTransmittance(waterDist, worldDir); color = color * endFog.a + endFog.rgb;`
  `color += EndFog(waterDist, worldDir);`
调用前提：由 `effects/world/end.glsl` 在声明 `timeFactor`、`planetShadow` 之后引入；体积涡旋雾默认关闭，
  关闭时整段不编译，连采样都不生成。
关键设计原因与取舍：原程序把雾烘进一张按方向采样的低分辨率雾图，本项目只在整条视线上调雾函数，
  所以这里沿视线步进并把雾交回调用方；体积涡旋雾会挡住背景，需要把剩余透射率带回合成阶段，
  而反射与折射的调用点只能加色，所以同一段雾用两个函数名区分，见末尾两个函数的说明。
*/
#ifndef OMNI_END_FOG_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_FOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 末地体积涡旋雾：一团绕主岛旋转的浓雾，以及雾中的光柱与雾霭 ---
// 出处：Eclipse `lib/end_fog.glsl` 的 `densityAtPosFog`、`SwirlAroundOrigin`、`VolumeBounds`、`fogShape`、
//   `endFogPhase`、`LightSourceLighting`、`GetVolumetricFog`；算法、常数与步进分布逐行照原程序。
// 为什么放在这里：原程序把雾烘进一张按方向采样的低分辨率雾图；本项目只在整条视线上调雾函数，
//   所以这里从相机沿世界视线方向步进，把累加到的散射色与剩余透射率交回调用方。
// 与 Eclipse 的两处取舍：
//   一、原程序从一张不清除的随机缓冲 `colortex4` 读雾中闪电的随机位置，并另有一处闪电强度；
//   本项目没有这块缓冲，且原程序在不开 `END_LIGHTNING` 时整段退化为「纯涡旋」锚点，所以这里直接取纯涡旋锚点。
//   二、原程序把雾的吸收率交回上层乘在场景上；本项目把吸收率随返回值带回，
//   只叠散射的调用点只用散射色，合成阶段按 `color = color * 透射率 + 散射色` 让被雾挡住的背景真正变暗。
#ifdef OMNI_END_VORTEX_FOG // 开关关闭时整段不编译，默认画面与采样都省掉。

// 读一张贴着世界坐标的三维噪声：水平切格后，用噪声贴图的上下两层按高度插值，得到雾团的颗粒。
float EndVortexNoise(vec3 pos){
	pos /= 18.0; // 把世界坐标缩到十八分之一，决定颗粒在世界里的稀密。
	pos.xz *= 0.5; // 水平方向再压一半，让雾团沿竖直方向拉长。
	vec3 cell = floor(pos); // 所在整数格。
	vec3 f = fract(pos); // 格内偏移。
	f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，让格与格之间不出现硬边。
	vec2 uv = cell.xz + f.xz + cell.y * vec2(0.0, 193.0); // 三维到二维的坐标分配，一百九十三是原程序用来打散高度的常数。
	vec2 xy = textureLod(noisetex, uv / float(noiseTextureResolution), 0.0).yx; // 读两个通道并交换，得到上下两层的值。
	return mix(xy.r, xy.g, f.y); // 按格内高度在两层之间插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// `alteredOrigin` 是要被旋转的采样坐标，`origin` 是这一步的真实世界位置，用来算旋转强度。
void EndVortexSwirl(inout vec3 alteredOrigin, vec3 origin){
	float radiance = 2.39996 + alteredOrigin.y / 1.5 + frameTimeCounter / 50.0; // 旋转角随时间与高度推进，二点三九九九六是原程序的起始角。
	mat2 rotation = mat2(vec2(cos(radiance), -sin(radiance)), vec2(sin(radiance), cos(radiance))); // 二维旋转矩阵。
	float swirlBounds = clamp(sqrt(max(length(vec3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转，越远越接近不转；原程序省略了零下限，这里补上以免近中心处对负数开方得到无效值。
	alteredOrigin.xz = mix(alteredOrigin.xz * rotation, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void EndVortexBounds(inout float volume, vec3 origin){
	vec3 origin2 = origin - vec3(0.0, 100.0, 0.0); // 相对高度一百的中心。
	origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
	float center = length(origin2); // 到中心的距离。
	float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
	float radius = 150.0; // 主岛圆环的半径。
	float thickness = 25.0 * radius; // 圆环判定的厚度尺度，数值取大以得到平缓的边缘。
	float torus = (thickness - clamp(pow(length(vec2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
	volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float EndVortexShape(vec3 pos){
	float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距世界原点三百格内为涡旋核心，对应原程序的 `vortexBoundRange`。
	vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直方向压得很扁，得到分层的云感。
	float voidZone = max(exp2(-sqrt(max(pos.y + 60.0, 0.0))), 0.0); // 主岛下方六十格起向下逐渐发白的虚空区，原程序写作 `pos.y - -60`。
	EndVortexSwirl(samplePos, pos); // 把采样坐标按漩涡旋转。
	float noise = EndVortexNoise(samplePos * 12.0); // 基础噪声，决定雾团的浓淡。
	float erosion = 1.0 - EndVortexNoise((samplePos - frameTimeCounter / 18.0) * (124.0 + (1.0 - noise) * 7.0)); // 随时间上升并放大的侵蚀噪声，把雾掏空。
	float clumpyFog = max(exp(noise * -mix(10.0, 4.0, vortexBounds)) * mix(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
	EndVortexBounds(clumpyFog, pos); // 按体积限制减薄。
	return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float EndVortexLightPhase(vec3 lightPos){
	float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一七。
	return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
vec3 EndVortexLighting(vec3 startPos, vec3 lightPos, float density, vec3 lightColor){
	float phase = EndVortexLightPhase(lightPos); // 到光柱中心的相位。
	float shadow = 0.0; // 沿光方向累积的遮挡。
	for (int j = 0; j < 3; j++){ // 三步采样雾的遮挡。
		vec3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * 0.25); // 从当前点向光柱中心退回采样。
		shadow += EndVortexShape(shadowSamplePos); // 累加遮挡。
	}
	vec3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
	lighting += lightColor * phase * phase * (1.0 - exp(-shadow * vec3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
	return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// `rgb` 是叠加到画面上的散射色，`a` 是透过雾后剩余的透射率，供合成阶段压暗背景。
// `worldDir` 是世界空间视线方向，`viewDist` 是这条视线到几何或远裁剪面的距离。
vec4 EndVortexFog(vec3 worldDir, float viewDist){
	vec3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
	float verticalFactor = pow(abs(worldDir.y), 2.0); // 视线的竖直程度，越水平就用越远的步进距离；`worldDir` 已归一化，与原程序对射线单位向量取纵轴分量等价。
	float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
	#ifdef DISTANT_HORIZONS // 开远景时步进更多、切得更远，覆盖远景区块。
		const int SAMPLECOUNT = 19; // 步数。
		const float expFactor = 33.0; // 指数分布底数，越大近处越密。
		float maxDist = mix(800.0, 300.0, verticalFactor); // 步进上限：水平看远、竖直看近。
	#else // 没有远景时步数少一些。
		const int SAMPLECOUNT = 15; // 步数。
		const float expFactor = 11.0; // 指数分布底数。
		float maxDist = mix(380.0, 300.0, verticalFactor); // 步进上限。
	#endif
	float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
	rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
	float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
	vec3 color = vec3(0.0); // 累积的雾发光。
	float absorbance = 1.0; // 累积的透过率，用来给后面的光正确地留出通道。
	float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声抖动步进，抖动会被时间平均掉。
		float dither = BlueNoiseTemporal().x; // 每帧变化的抖动值。
	#else // 否则用屏幕空间固定噪声。
		float dither = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
	#endif
	float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
	vec3 vortexColor = vec3(OMNI_END_VORTEX_LIGHT_R, OMNI_END_VORTEX_LIGHT_G, OMNI_END_VORTEX_LIGHT_B) * 0.25; // 光柱颜色，零点二五是原程序的缩放。
	vec3 ambientColor = vec3(OMNI_END_VORTEX_AMBIENT_R, OMNI_END_VORTEX_AMBIENT_G, OMNI_END_VORTEX_AMBIENT_B); // 雾内环境光颜色。
	for (int i = 0; i < SAMPLECOUNT; i++){ // 逐步前进。
		float d = (pow(expFactor, (float(i) + dither) / float(SAMPLECOUNT)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
		float dd = pow(expFactor, (float(i) + dither2) / float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT) / (expFactor - 1.0); // 这一步的宽度。
		vec3 progressW = cameraPosition + d * rayWorld; // 这一步的世界位置。
		vec3 lightPos = progressW - vec3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处，对应原程序纯涡旋分支的锚点。
		float volumeDensity = EndVortexShape(progressW); // 这一步的雾密度。
		float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPosition) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
		float stormDensity = min(volumeDensity, clearArea * clearArea * OMNI_END_VORTEX_STORM_DENSITY); // 风暴部分，按贴脸留空与密度封顶。
		float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
		vec3 lightsources = EndVortexLighting(progressW, lightPos, volumeDensity, vortexColor); // 这一步的雾内光柱发光。
		vec3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
		vec3 stormLighting = indirect + lightsources; // 这一步的总发光。
		color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
		absorbance *= volumeCoeff; // 透过率继续衰减。
		float hazeDensity = 0.001 * OMNI_END_VORTEX_HAZE_DENSITY; // 雾霭部分的基础密度。
		vec3 hazeLighting = vec3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
		color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
	}
	return vec4(color * 1e-3 * OMNI_SUNLIGHT_INTENSITY, absorbance); // 散射色换算到管线单位并乘阳光强度、剩余透射率一并交回；系数为量级对齐，游戏内未校准。
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

	mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
	mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
	mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。

	worldDir = eyeRoataionMatrix * worldDir; // 视线转到相位坐标系。

	dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
	float h = abs(worldDir.z) * dist * 0.03; // 沿视线方向的等效高度。
	float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。

	float storm = MiePhaseFunction(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分：米氏相位乘行星相位。
	float haze = 0.25; // 不带方向的雾霭基准部分。
	// 两个密度选项来自 Eclipse `lib/settings.glsl:911-912`（`END_STORM_DENSTIY`、`END_HAZE_DENSTIY`）；
	// 默认都为一，缩放后相加与原来的单一密度逐位等价，画面不变。
	float density = fogDepth * (storm * OMNI_END_FOG_STORM_DENSITY + haze * OMNI_END_FOG_HAZE_DENSITY); // 两层分别缩放后相加。

	density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。

	vec3 fog = vec3(density * 1e-5 * OMNI_SUNLIGHT_INTENSITY); // 解析雾的贡献，换算到管线单位并乘阳光强度。

	float transmittance = 1.0; // 解析雾只加色不遮挡，默认全透；只有体积涡旋雾会把它压下来。
	#ifdef OMNI_END_VORTEX_FOG // 打开涡旋体积雾时再沿视线叠一层，关闭时这一行不生成，透射率保持为一。
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
#endif // OMNI_END_FOG_INCLUDED 结束。
