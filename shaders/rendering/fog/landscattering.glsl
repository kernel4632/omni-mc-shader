/*
地面大气散射：给地表方向的视线补一层空气散射，阴影区按选项削弱。
来源：iterationT `Lib/BasicFounctions/VanillaComposite.glsl` 的散射段一比一移植。
职责：`simpleScattering` 沿阳光取几段估光学厚度，`LandAtmosphericScattering` 把它加到画面。
调用位置：由 `effects/fog/fog.glsl` 引入；`rendering/composite.glsl` 的合成五号、`effects/water/water.glsl`
  的折射与 `effects/reflection/reflection.glsl` 的反射都调用 `LandAtmosphericScattering`。
可复制示例：`LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5);`
调用前提：由 `effects/fog/fog.glsl` 引入，且已先引入 `common/math.glsl`、`effects/shadow/shadow.glsl`、
  `effects/sky/sky.glsl` 并声明相机与阴影相关全局量；本文件不重复引入。
关键设计原因与取舍：`LandAtmosphericScattering` 的调用点是加色，所以它就地改画面；阴影遮蔽与室内衰减都按开关折叠。
*/
#ifndef OMNI_LANDSCATTERING_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_LANDSCATTERING_INCLUDED // 置上标记，后续再次引用直接跳过。

// 简化的单次散射：沿阳光方向取几段估光学厚度，算出这段空气加到视线上的散射色。
// 输入是相机、视线方向、散射距离、受光距离与光源方向；返回叠加的散射颜色。
// 为什么用球面求交取段长：每段沿阳光走多远由大气层厚度决定，固定步长会在高处取样过密、低处过疏。
vec3 simpleScattering(vec3 camera, vec3 worldDir, float dist, float shadowDist, vec3 lightVector){
	float ds = RaySphereIntersection(camera, lightVector, atmosphereModel_top_radius).y * 0.25; // 沿阳光到大层顶的距离，取四分之一为每段长度。
	vec3 opticalLength = ds * lightVector; // 每段的光程矢量。
	camera += 0.5 * opticalLength; // 相机先前移到第一段中点。

	vec3 opticalDepth = vec3(0.0); // 累加的光学厚度，三通道分别是瑞利、米氏与吸收。
	for (int i = 0; i < 4; i++, camera += opticalLength){ // 四段累加。
		float altitude = length(camera) - atmosphereModel_bottom_radius; // 该段所在高度。
		opticalDepth += vec3(GetProfileDensityRayleighMie(atmosphereModel_densityProfile_rayleigh, altitude), // 瑞利密度。
							 GetProfileDensityRayleighMie(atmosphereModel_densityProfile_mie, altitude), // 米氏密度。
							 GetProfileDensityAbsorption (atmosphereModel_densityProfile_absorption_width, atmosphereModel_densityProfile_absorption, altitude)); // 臭氧密度。
	}
	opticalDepth = opticalDepth * ds + dist; // 乘段长并加上视线本身的距离。

	vec3 attenuation = exp2(-opticalDepth.x * atmosphereModel_rayleigh_scattering // 瑞利消光。
		 				    -opticalDepth.y * atmosphereModel_mie_scattering // 米氏消光。
		 			   	    -opticalDepth.z * atmosphereModel_absorption_extinction); // 臭氧吸收。

	float nu = dot(worldDir, lightVector); // 视线与阳光的夹角。
	vec3 scattering = RayleighPhaseFunction(nu) * atmosphereModel_rayleigh_scattering * (dist * 0.25 + shadowDist * 0.75) // 瑞利散射，四分之一取距离、四分之三取受光距离。
					+ MiePhaseFunction(0.6, nu) * atmosphereModel_mie_scattering * shadowDist; // 米氏散射只算受光的部分。

	return scattering * atmosphereModel_solar_irradiance * attenuation * GFX_ATMO_LMS; // 乘太阳辐照度、透过率与色适应矩阵。
}

// 地面大气散射：给地表方向的视线补一层空气散射，阴影区按选项削弱。
// 输入是待修改颜色、距离、起点、终点、世界方向与是否天空；就地把散射加到颜色里。
// 为什么把起点抬高到最低高度：贴地时大气几何退化，抬高保证散射计算稳定。
void LandAtmosphericScattering(inout vec3 color, in float dist, vec3 startPos, vec3 endPos, vec3 worldDir, bool isSky){
	float strength = max(OMNI_LANDSCATTERING_STRENGTH - float(isSky), 0.0); // 天空像素不重复加散射，强度减一。
	#ifdef OMNI_VFOG // 有体积雾时按白天缩放，避免和体积雾双重叠加。
		strength *= timeNoon;
	#endif
	#if !OMNI_INDOOR_FOG // 默认随天空光等级衰减。
		strength *= eyeBrightnessSmoothCurved;
	#endif

	if(strength > 0.001 && isEyeInWater == 0){ // 强度太低或不在空气中就不算。

		#ifdef OMNI_ATMO_HORIZON // 打开地平线时按选项高度算相机。
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 高度换成公里并加星球半径。
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 默认按海平面高度。
		#endif

		float shadowDist = dist; // 受光的距离，默认等于总距离。

		#if OMNI_LANDSCATTERING_SHADOW // 打开阴影遮蔽时沿视线段查阴影图，按被挡的比例缩短受光距离。
			vec3 shadowStart = ShadowScreenPos_From_WorldPos(startPos + gbufferModelViewInverse[3].xyz); // 起点投到阴影图。
			vec3 shadowEnd = ShadowScreenPos_From_WorldPos(endPos + gbufferModelViewInverse[3].xyz); // 终点投到阴影图。

			#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
				float noise = BayerTemporal();
			#else
				float noise = bayer64(gl_FragCoord.xy);
			#endif

			float occluded = gfx_shadow_segment_occlusion(shadowStart, shadowEnd, shadowtex0, int(OMNI_LANDSCATTERING_SHADOW_QUALITY),
				noise, OMNI_SHADOW_MAP_BIAS, length(endPos - startPos)); // 一次调用统计被挡住的米数。

			shadowDist = max(shadowDist - occluded, 0.0); // 按被挡比例缩短受光距离。
		#endif

		dist *= OMNI_LANDSCATTERING_DISTANCE; // 总距离乘距离倍率。
		shadowDist *= OMNI_LANDSCATTERING_DISTANCE; // 受光距离同样乘倍率。

		color += simpleScattering(camera, worldDir, dist, shadowDist, worldSunVector) // 算出这段空气的散射。
			   * (1.0 - wetness) // 雨天空气更均匀，去掉方向性散射。
			   * strength; // 乘最终强度。
	}
}
#endif // OMNI_LANDSCATTERING_INCLUDED 结束。
