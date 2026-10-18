/*
体积雾：沿视线与光方向在空气里步进，算出体积雾颜色与透射率。
来源：iterationT `Lib/IndividualFounctions/VolumetricFog.glsl` 一比一移植。
职责：相位与噪声、按高度或三维噪声的雾密度、沿阳光方向的吸收估量，以及体积雾主体 `VolumetricFog`。
调用位置：由 `effects/fog/fog.glsl` 引入；`rendering/composite.glsl` 的合成五号与 `effects/water/water.glsl`
  的折射、`effects/reflection/reflection.glsl` 的反射都调用 `VolumetricFog`。
可复制示例：`VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance);`
调用前提：由 `effects/fog/fog.glsl` 引入，且已先引入 `common/math.glsl`、`common/noise.glsl`、
  `effects/shadow/shadow.glsl`、`effects/sky/sky.glsl`、`effects/cloud/cloud.glsl`、`effects/weather/storm.glsl`
  并声明相机与阴影相关全局量；本文件不重复引入。
关键设计原因与取舍：`FogDensityScale` 按合同拆到同目录 `tod.glsl` 并先于本文件引入；`VFOG_LQ` 由合成二号打开，
  反射通道只用三步；群系与暴风两层按开关折叠，默认关闭时整段不产生代码。
  雾照明按 Eclipse `composite3.fsh` 把体积彩色光逐段加进雾里：要同时开启体积光与雾照明（`OMNI_LPV_FOG_LIGHT`），
  并已由 `effects/fog/fog.glsl` 引入 `effects/lighting/lpv.glsl` 提供取样函数，默认关闭时整段不产生代码；
  同一处还按 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD` 叠上手持光源（火把等）在空气里的光晕，默认关闭。
*/
#ifndef OMNI_VOLUMETRIC_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_VOLUMETRIC_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 体积雾：相位、噪声与密度 ---
// 粉末效应：光穿过一层薄雾时，正对光源方向更亮，背光方向的雾壁反而更暗，模拟粒子间的多次散射。
float PowderEffect(float absorption, float lightingAbsorption, float VdotL){
	return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 采样点两侧的剩余光越少粉末效应越强。
}

// 雾的相位：前向与后向两个米氏相位加权，得到雾里比较均匀的散射方向性。
float FogPhase(float VdotL){
	return MiePhaseFunction(-0.4, VdotL) * 0.3 + MiePhaseFunction(0.5, VdotL) * 0.7; // 后向占三成、前向占七成。
}

// 多次散射相位：把相位按指数缩放的夹角重复四次，模拟光在雾里多次反弹后更均匀。
void MultiScatteringPhases(float VdotL, inout float phases[4]){
	float cn = 1.0; // 每一级的夹角缩放，从一倍开始逐级减半。

	for (int i = 0; i < 4; i++, cn *= 0.5){ // 四次，每次夹角缩放减半。
		phases[i] = FogPhase(VdotL * cn); // 记录这一级的相位。
	}
}

// 三维噪声：用噪声贴图的两通道做一次三线性插值，得到零到一的雾密度。
// 为什么用噪声贴图而不是实时噪声：贴图里已经烘好一层分布，采样代价低，也保证全屏可重复。
float Calculate3DNoise(vec3 position){
	vec3 p = floor(position); // 整数格。
	vec3 f = position - p; // 格内小数偏移。

	f = curve(f); // 用三次曲线平滑小数，插值更自然。

	vec2 uv = 17.0 * p.z + p.xy + f.xy; // 把三维格子映射到二维噪声坐标。
	vec2 n = textureLod(noisetex, uv * 0.015625 + 0.0078125, 0.0).zw; // 读噪声贴图后两通道。

	return mix(n.x, n.y, f.z); // 按高度在小数位置插值。
}

#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减：只用高度决定密度。

// 雾密度：以两档衰减高度之间最浓，超出后按衰减距离指数下降。
float FogDensity(vec3 fogPos, vec3 wind){
	float maxHeight = max(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2); // 两档高度里较高的。
	float minHeight = min(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2); // 两档高度里较低的。

	float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到最浓高度区间外的距离。
	dh *= 2.0 / OMNI_VFOG_FALLOFF; // 按衰减距离归一化。
	float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢雾更浓。

	return density * 0.1; // 缩到合理量级。
}

#else // 团雾：用三维噪声叠出雾团。

// 雾密度：先按高度算一个衰减包络，再乘多层噪声叠出的雾团。
float FogDensity(vec3 fogPos, vec3 wind){
	float dh = abs(fogPos.y - max(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2)); // 到最高密度高度的距离。
	dh *= 1.0 / OMNI_VFOG_FALLOFF; // 按衰减距离归一化。
	float falloff = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
 
	float density = 0.0; // 累加的雾密度。
	fogPos = fogPos * 0.02 + wind; // 换到雾坐标并叠加风速。

	for (float stepAlpha = 0.5; stepAlpha >= 0.125; stepAlpha *= 0.5) { // 三层不同频率的噪声叠加。
		density += stepAlpha * Calculate3DNoise(fogPos); // 按权重累加这一层噪声。
		fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
	}

	density *= falloff; // 乘高度衰减。

	density = density * density; // 平方拉开明暗。
	return density * density * 3.0; // 再平方并放大，得到清晰的雾团边界。
}

#endif

// 沿阳光方向估这一段雾对光的吸收：从雾采样点出发按逐步放大的步长前进，累加各处的原生密度。
// 输入是雾采样位置与风；就地推进 `fogPos`，返回沿光方向累计的密度（尚未乘选项、基础密度与时间因子）。
// 为什么步长逐步放大：靠近采样点的雾对光柱影响最大，远处用大步长近似即可，四步就能看出吸收差异。
float FogLightMarch(inout vec3 fogPos, vec3 wind){
	float lightingDensity = 0.0; // 沿光方向累计的密度。
	float lightingStepLength = VFOG_SUNLIGHT_STEPLENGTH; // 沿光方向起始步长。

	for (int i = 0; i < VFOG_SUNLIGHT_STEPS; i++, fogPos += worldShadowVector * lightingStepLength, lightingStepLength *= 1.5){ // 沿光方向步进，步长逐步放大。
		lightingDensity += FogDensity(fogPos, wind) * lightingStepLength; // 累加这一段的原生密度。
	}

	return lightingDensity; // 返回原始累计密度，供调用方乘吸收率与选项。
}

// 体积雾主体：沿视线一步步在雾里前进，同时沿光方向估遮挡，累加雾色与阳光散射。
// 输入是待修改颜色、起点、终点、世界方向、全局云影、时间因子；输出透射率，颜色就地叠加雾。
// 为什么步长用指数递增：近处雾细节重要、远处可以粗，指数步长把采样集中在前段。
void VolumetricFog(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow, float fogTimeFactor, out float transmittance){
	#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减模式夜晚雾更浓，时间因子再按夜晚放大。
		fogTimeFactor *= timeMidnight * 2.0 + 1.0;
	#endif

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float noise = BlueNoiseTemporal().y; // 用蓝噪声另一个通道避免与反射抖动相关。
	#else
		float noise = bayer64(gl_FragCoord.xy); // 固定拜尔抖动。
	#endif

	float VdotL = dot(worldDir, worldShadowVector); // 视线与阳光方向夹角，供相位与粉末效应使用。

	#ifdef VFOG_LQ // `composite2` 打开低质量宏时体积雾只用三步。
		const float steps = 3.0;
	#else
		const float steps = OMNI_VFOG_QUALITY; // 否则用选项里的采样质量。
	#endif
	const float rSteps = 1.0 / steps; // 步数倒数。

	vec3 start = startPos + gbufferModelViewInverse[3].xyz; // 起点补上相机位置换成世界坐标。
	vec3 end = endPos + gbufferModelViewInverse[3].xyz; // 终点同样换成世界坐标。

	vec3 rayVector = end - start; // 从起点到终点的矢量。
	float rayLength = length(rayVector) * rSteps * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。

	vec3 shadowStart = ShadowScreenPos_From_WorldPos(start); // 起点投到阴影图。
	vec3 shadowEnd = ShadowScreenPos_From_WorldPos(end); // 终点投到阴影图。

	vec3 shadowRayVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。

	start += cameraPosition; // 起点换成绝对世界坐标，供云影采样。

	#ifdef DISTANT_HORIZONS
		float baseDensity = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.25 + 0.25) / clamp(float(dhRenderDistance), 512.0, 2048.0); // 基础密度按远景渲染距离归一化。
	#else
		float baseDensity = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.1 + 0.05) / max(far, 100.0); // 没有远景时按近景远裁剪面归一化。
	#endif
	#if !OMNI_INDOOR_FOG // 默认让体积雾随天空光等级衰减，暗处雾更淡。
		baseDensity *= eyeBrightnessSmoothCurved; // 乘天空光曲线平滑值。
	#endif

	#if OMNI_SNOW_STORM || OMNI_SAND_STORM // 只有开启至少一种暴风时才计算强度，默认零开销。
		float stormSnow = OmniSnowStorm(); // 雪暴强度，零到一。
		float stormSand = OmniSandStorm(); // 沙暴强度，零到一。
		float stormStrength = clamp(stormSnow + stormSand, 0.0, 1.0); // 两种暴风的总强度，即使都没刮也保持零。
	#else
		float stormStrength = 0.0; // 没开暴风时总强度恒为零，供密度标度判断是否把雾交给暴风通道。
	#endif

	float fogDensityScale = FogDensityScale(stormStrength); // 密度标度：时段雾与每日天气按当前雾类型给出，暴风时退回固定密度避免与暴风通道叠加。

	#if OMNI_PER_BIOME_ENV // 群系权重每像素算一次，供下面的雾密度与雾色共用。
		vec4 biomeWeights = omniBiomeWeights(); // 四个群系的权重，来自加载器平滑量。
	#endif

	#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING // 打开体积光照时用多级相位，否则用单一相位。
		float phases[4]; // 四级散射相位。
		MultiScatteringPhases(VdotL, phases); // 一次算好四级相位。
	#else
		float phases = MiePhaseFunction(0.5, VdotL) * 0.7 + 0.05; // 单级前向相位。
	#endif

	#if OMNI_VFOG_NOISE_TYPE > 0 // 团雾模式要按风移动。
		float windTimer = (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET) * 0.0025; // 风速时间，与云速一致。
		vec3 wind = vec3(-1.0, -0.05, 0.6) * windTimer; // 固定的风方向。
	#else // 仅高度衰减模式不用风。
		vec3 wind = vec3(0.0); // 给一个零值，让密度与光照步进共用一个调用写法。
	#endif


	transmittance = 1.0; // 透射率从全透开始。
	float fogDensity = 0.0; // 环境雾累计量。
	float rayDensity = 0.0; // 阳光散射累计量。
	#if OMNI_LIGHTNING // 闪电点亮的空气累计量，按每一步的吸收量叠加。
		vec3 lightningFogLight = vec3(0.0); // 闪电在雾里点亮的空气颜色。
	#endif
	#ifdef OMNI_LPV_FOG_LIGHT // 雾照明要同时开启体积光与雾照明、并具备自定义图像能力才累计。
		vec3 lpvFogLight = vec3(0.0); // 体积彩色光照亮空气的累计量，与天空光衰减无关，洞穴暗处也要可见。
	#endif

	#ifdef MC_GL_VENDOR_NVIDIA // 只有部分显卡支持给半透明玻璃染色。
		#ifdef OMNI_VFOG_STAINED
			vec3 translucentColor = vec3(0.0); // 透过半透明方块的染色光。
		#endif
	#endif

	for (float i = 0.0; i < steps; i++){ // 沿视线逐步前进。
		float exponential = pow(11.0, (i + noise) * rSteps); // 指数步长因子。
		float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
		float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度，一点四四二六九五由以二为底换算而来。

		vec3 fogPos = start + stepLength * rayVector; // 这一步的雾采样位置。
		vec3 shadowPos = shadowStart + stepLength * shadowRayVector; // 这一步的阴影图坐标。

		#if OMNI_LIGHTNING // 闪电照亮空气：先按本步的雾采样点算冷色闪光，稍后按本步吸收量累加。
			vec3 lightningStep = omniLightningVolume(fogPos - cameraPosition, 150.0, -15.0); // 采样点是绝对世界坐标，先换相机相对；一百五十格与快速衰减照 Eclipse。
		#endif

		#if OMNI_PER_BIOME_ENV // 群系内按离相机的距离替换雾密度，远处退回原值。
			float biomeDistance = length((stepLength * rayVector).xz); // 这一步相对起点的水平距离，与 Eclipse 的口径一致。
			float biomeEnvelope = min(max(1.0 - biomeDistance / 256.0, 0.0) * 2.0, 1.0); // 二百五十六米内替换最明显，与 Eclipse 同一包络。
			float biomeUniformScale = fogDensityScale; // 高度衰减雾用的密度标度，先用原值再被混合。
			float biomeCloudyScale = fogDensityScale; // 团雾用的密度标度，先用原值再被混合。
			omniBiomeFogDensity(biomeWeights, biomeUniformScale, biomeCloudyScale, biomeEnvelope); // 把两套标度朝本群系密度混合。
			#if OMNI_VFOG_NOISE_TYPE == 0 // 当前是仅高度衰减雾，取高度衰减那一套。
				float densityScale = biomeUniformScale; // 群系混合后的密度标度。
			#else // 当前是团雾，取多云那一套。
				float densityScale = biomeCloudyScale; // 群系混合后的密度标度。
			#endif
		#else // 未启用群系环境时直接用原密度标度，画面与原来完全一致。
			float densityScale = fogDensityScale; // 原密度标度。
		#endif

		float density = FogDensity(fogPos, wind); // 算这一点的雾密度，仅高度衰减模式忽略风。
		density = (density * densityScale + baseDensity) * fogTimeFactor; // 噪声密度乘密度标度再加基础密度，再乘时间因子。
		#if OMNI_SNOW_STORM || OMNI_SAND_STORM // 暴风时在这条射线上再叠一层浓雾。
			density += OmniStormFog(fogPos, stormSnow) * stormStrength * OMNI_STORM_DENSITY; // 暴风噪声密度乘总强度与浓度选项。
		#endif
		float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。

		#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING // 体积光照：沿阳光方向估吸收。
			float lightingDensity = FogLightMarch(fogPos, wind); // 沿光方向累计密度，并就地推进 `fogPos`。

			lightingDensity = (lightingDensity * OMNI_VFOG_SUNLIGHT_ABSORPTION * densityScale + baseDensity) * fogTimeFactor; // 乘吸收率与群系混合后的密度标度再算总密度。
			float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。

			float stepRayDensity = 0.0; // 这一步的阳光散射量。
			float order = 1.0; // 多级相位的权重，从一倍开始逐级减半。
			for (int j = 0; j < 4; j++, order *= 0.5){ // 四级散射加权求和。
				stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 按级数与权重累加。
			}
			stepRayDensity *= PowderEffect(absorption, lightingAbsorption, VdotL); // 乘粉末效应。
		#endif


		shadowPos.xy = DistortShadowScreenPos(shadowPos.xy); // 阴影图坐标补上边缘压缩。

		float shadow = 1.0; // 这一点受不受阳光，默认受光。

		#ifdef OMNI_VFOG_STAINED
			vec3 shadowColorSample = vec3(1.0); // 该点半透明染色，默认白色。
		#endif

		if (saturate(shadowPos.xy) == shadowPos.xy && shadowPos.z < 1.0){ // 坐标落在阴影图内才采样。
			#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用实心与半透明两张图。
				float solidDepth = textureLod(shadowtex1, shadowPos.xy, 0).x; // 读实心深度。
				shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。

				#ifdef OMNI_VFOG_STAINED
					float transparentDepth = textureLod(shadowtex0, shadowPos.xy, 0).x; // 读半透明深度。
					shadowColorSample = GammaToLinear(textureLod(shadowcolor0, shadowPos.xy, 0).rgb); // 读半透明颜色。
					float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。

					shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
					shadow -= transparentShadow; // 从受光里扣掉半透明遮挡。
				#endif
			#else
				float solidDepth = textureLod(shadowtex0, shadowPos.xy, 0).x; // 只读一张遮挡图。
				shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
			#endif
		}


		#ifdef OMNI_VOLUMETRIC_CLOUDS // 有体积云时云影也能压体积雾。
			#ifdef OMNI_CLOUD_SHADOW
				#ifdef OMNI_VFOG_CLOUD_SHADOW
					float cloudShadow = CloudShadowFromTex(fogPos - cameraPosition, worldShadowVector); // 读该点云影，世界坐标要减去相机位置。
				#endif
			#endif
		#endif

		
		float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
		#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING
			stepRayDensity *= integral; // 散射量按这一段吸收缩放。
		#else
			float stepRayDensity = integral * phases; // 单向散射直接用相位乘吸收。
		#endif

		#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW && defined OMNI_VFOG_CLOUD_SHADOW // 有云影时雾色也按云影压暗。
			stepRayDensity *= mix(cloudShadow, 1.0, wetness * 0.1 + 0.03); // 散射按云影压暗。
			fogDensity += integral * mix(cloudShadow, 1.0, wetness * 0.3 + 0.7); // 环境雾按云影压暗。
		#else
			fogDensity += integral; // 没有云影时直接累加。
		#endif

		rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。

		#ifdef MC_GL_VENDOR_NVIDIA
			#ifdef OMNI_VFOG_STAINED
				translucentColor += stepRayDensity * shadowColorSample; // 累加染色散射。
			#endif
		#endif
		
		
		transmittance *= absorption; // 透射率逐步衰减。

		#if OMNI_LIGHTNING // 闪电点亮的空气，按本步吸收量累加进来。
			lightningFogLight += lightningStep * integral; // 雾越厚、这一步吸收越多，被点亮的部分越多。
		#endif

		#ifdef OMNI_LPV_FOG_LIGHT // 雾照明：把这一步所在空气的体积彩色光按本步吸收量累加进来。
			vec3 lpvPos = omniLpvPosition(fogPos - cameraPosition); // 体积坐标；雾采样点是绝对世界坐标，要先减相机位置。
			float lpvFade = omniLpvRangeFalloff(lpvPos); // 体积边缘淡出，避免体积边界出现硬边。
			if (lpvFade < 0.01) break; // 走出体积就不再步进，与 Eclipse `composite3.fsh:241` 一致。
			vec3 lpvColor = omniLpvSample(lpvPos).rgb; // 读这一点被照亮的空气颜色，零到一。
			float lpvLuma = dot(lpvColor, vec3(0.2126, 0.7152, 0.0722)); // 亮度，用来按 Eclipse 抑制暗色光。
			vec3 lpvLighting = lpvColor * (OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.25) * exp(-5.0 * (1.0 - lpvLuma)); // 照 Eclipse `composite3.fsh:247`，亮度基准按一百换算。
			lpvFogLight += lpvLighting * integral * lpvFade; // 按这一步吸收量与边缘淡出累积。
			#if OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD // 雾照明-手持光：手里的火把等也照亮这一步的空气。
				// 取两只手持光源在该点留下的光，按 Eclipse `composite3.fsh:258` 的系数（零点零四，再按本项目百分之一定标缩到零点零零零四）累加。
				vec3 handLight = omniLpvHandLight(heldItemId, fogPos - cameraPosition) + omniLpvHandLight(heldItemId2, fogPos - cameraPosition); // 两手光源的光色乘距离衰减。
				lpvFogLight += handLight * (OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.0004) * integral * lpvFade; // 与体积光同一处累积，得到暖色的手持光晕。
			#endif
		#endif
	}


	vec3 skylight = colorSkylight; // 雾的环境色以天光为主。
	vec3 skySunLight = colorShadowlight * 0.03; // 雾里的一点点直射光。
	skylight += skySunLight * (1.0 + (1.0 - globalCloudShadow) * (1.0 - wetness)); // 云影越浅这里补得越多。

	skylight = mix(skylight, skySunLight, wetness * 0.7); // 雨天偏向直射色，雾更灰。

	vec3 fogColor = skylight         * fogDensity; // 环境雾色。
	vec3 rayColor = colorShadowlight * rayDensity; // 阳光散射色。

	#if OMNI_SNOW_STORM || OMNI_SAND_STORM // 暴风时把雾色与散射色染成雪白或沙黄。
		vec3 stormTint = mix(vec3(1.0), OmniStormColor(stormSnow, stormSand), stormStrength); // 没刮风时为单位色，不改变画面。
		fogColor *= stormTint; // 环境雾按暴风颜色染色。
		rayColor *= stormTint; // 阳光散射同样染色，与 Eclipse 染色两组光色一致。
	#endif

	#if OMNI_PER_BIOME_ENV // 群系配色给雾的环境色与直射散射染色，与 Eclipse 的 `BiomeVLFogColors` 同一处作用。
		vec3 biomeFogColor; // 本群系合成的雾色。
		float biomeCoverage; // 落在任一已启用群系内的程度。
		omniBiomeFogColor(biomeWeights, biomeFogColor, biomeCoverage); // 取本群系雾色与覆盖程度。
		vec3 biomeTint = mix(vec3(1.0), biomeFogColor, biomeCoverage); // 不在群系内时保持原色，不改变画面。
		fogColor *= biomeTint; // 环境雾染成群系色。
		rayColor *= biomeTint; // 阳光散射同样染色。
	#endif

	#ifdef MC_GL_VENDOR_NVIDIA
		#ifdef OMNI_VFOG_STAINED
			rayColor += colorShadowlight * translucentColor; // 叠上透过半透明方块的染色光。
		#endif
	#endif

	fogColor *= 0.32 * OMNI_VFOG_FOG_DENSITY      * OMNI_SKYLIGHT_INTENSITY; // 环境雾按强度选项与天光强度缩放。
	rayColor *= 0.7  * OMNI_VFOG_SUNLIGHT_DENSITY * OMNI_SUNLIGHT_INTENSITY; // 散射按强度选项与阳光强度缩放。
	#if !defined OMNI_VOLUMETRIC_CLOUDS || !defined OMNI_CLOUD_SHADOW || !defined OMNI_VFOG_CLOUD_SHADOW // 没有云影时在这里压散射。
		rayColor *= mix(globalCloudShadow, 1.0, wetness * 0.1); // 全局云影压散射。
	#endif

	#if !OMNI_INDOOR_FOG // 默认体积雾随天空光等级衰减。
		fogColor *= eyeBrightnessSmoothCurved; // 环境雾按天空光衰减。
		#ifdef OMNI_CAVE_MODE // 洞穴模式下散射也衰减，避免洞口过亮。
			rayColor *= eyeBrightnessSmoothCurved;
		#endif
		#if OMNI_LIGHTNING // 闪电来自天空，洞穴里看不到，按天空光压掉。
			lightningFogLight *= eyeBrightnessSmoothCurved;
		#endif
		transmittance = mix(1.0, transmittance, eyeBrightnessSmoothCurved); // 透射率也按天空光拉回，暗处雾更淡。
	#endif

	color = transmittance * color; // 场景色先被雾吸收。
	color += fogColor + rayColor; // 再叠上雾色与散射。
	#if OMNI_LIGHTNING // 闪电照明：叠上被闪电点亮的空气。
		color += lightningFogLight; // 直接加到画面上。
	#endif
	#ifdef OMNI_LPV_FOG_LIGHT // 雾照明：叠上被体积彩色光照亮的空气，不随天空光衰减，暗处彩色光晕也能看见。
		color += lpvFogLight; // 直接把累计的被照亮空气加到画面上。
	#endif
}
#endif // OMNI_VOLUMETRIC_INCLUDED 结束。
