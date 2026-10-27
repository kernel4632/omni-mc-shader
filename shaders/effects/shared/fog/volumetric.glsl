/*
效果文件 `effects/shared/fog/volumetric.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/fog/volumetric.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_VOLUMETRIC_INCLUDED
#define OMNI_VOLUMETRIC_INCLUDED
/*
体积雾：把选项、天气、群系与阴影贴图换成通用库参数，整段步进调用一次。
来源：iterationT `Lib/IndividualFounctions/VolumetricFog.glsl` 一比一移植。
职责：选项换算、基础密度、时段与暴风、群系取值、雾照明钩子，以及 `VolumetricFog` 入口。
调用位置：由 `effects/fog/fog.glsl` 引入；合成五号、水面折射与反射都调用 `VolumetricFog`。
可复制示例：`VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance);`
设计原因与取舍：密度、光照步进、阴影、云影与最终合成在 `gfx/fog_volume.glsl`；
    雾照明需要宿主的三维图像与手持光表，用 `GFX_FOG_LPV_STEP` 宏作为可选钩子注入，默认关闭时是空操作。
    采样步数仍按 `const float steps = OMNI_VFOG_QUALITY` 的口径换算；闪电照明沿用 `omniLightningVolume`
    的竖直光柱公式，被点亮的空气在 `lightningFogLight` 里按每步吸收量累加，具体计算已随主循环放进通用库。
*/

// 雾照明钩子：只有同时开启雾照明、体积光与自定义图像能力时才定义。
#if defined OMNI_LPV_FOG_LIGHT
// 读一步空气里的彩色体积光：位置、体积边缘淡出与手持光都照原程序。
vec3 FogLpvStep(vec3 fog_pos, float integral, out bool done){
	done = false; // 默认还要继续步进。
	vec3 lpv_pos = omniLpvPosition(fog_pos - cameraPosition); // 雾采样点是绝对世界坐标，先减相机位置。
	float fade = omniLpvRangeFalloff(lpv_pos); // 体积边缘淡出。
	if (fade < 0.01){ // 走出体积就不再步进，与 Eclipse 一致。
		done = true; // 通知通用库结束循环。
		return vec3(0.0); // 没有光。
	}
	vec3 lpv_color = omniLpvSample(lpv_pos).rgb; // 读这一点被照亮的空气颜色。
	float luma = dot(lpv_color, vec3(0.2126, 0.7152, 0.0722)); // 亮度，用来抑制暗色光。
	vec3 lighting = lpv_color * (OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.25) * exp(-5.0 * (1.0 - luma)); // 亮度基准按一百换算。
	vec3 result = lighting * integral * fade; // 按这一步吸收量与边缘淡出累积。
	#if OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD // 雾照明-手持光。
		vec3 hand = omniLpvHandLight(heldItemId, fog_pos - cameraPosition) + omniLpvHandLight(heldItemId2, fog_pos - cameraPosition); // 两手光源。
		result += hand * (OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.0004) * integral * fade; // 暖色手持光晕。
	#endif
	return result; // 交回这一步的体积光。
}
#define GFX_FOG_LPV_STEP(fog_pos, integral, accum, done) { bool lpvDone = false; accum += FogLpvStep(fog_pos, integral, lpvDone); done = lpvDone; }
#endif

// 体积雾的密度、光照与阴影主循环在通用库。
// 阳光、天光、底光与火把亮度由共享光照文件统一定义。
#include "/effects/shared/light.glsl"
#include "/omni-gfx/fog/volume.glsl"

// 体积雾入口：先算基础密度与天气，再把所有参数交给通用库一次完成步进。
void VolumetricFog(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow, float fogTimeFactor, out float transmittance){
	OgxFogMedia media; // 本帧雾参数。
	media.camera_position = cameraPosition; // 相机绝对世界位置。
	media.light_vector = worldShadowVector; // 指向光源的单位向量。
	media.light_color = colorShadowlight; // 直射光色。
	media.sky_color = colorSkylight; // 天空环境光色。
	media.lightning_position = vec3(0.0); // 默认没有闪电。
	media.lightning_intensity = 0.0; // 默认没有闪电事件。
	#if OMNI_LIGHTNING && defined IS_IRIS // 只有真实闪电输入可用时才读取事件。
		media.lightning_position = lightningBoltPosition.xyz; // 闪电光柱中心。
		media.lightning_intensity = lightningBoltPosition.w; // 闪电强度。
	#endif
	media.lightning_strength = OMNI_LIGHTNING_STRENGTH; // 闪电亮度选项。
	#ifdef OMNI_END // 末地使用随相机旋转的阴影相机。
		media.shadow_view = shadowModelViewEnd; // 末地阴影视图。
	#else // 主世界与下界使用主阴影相机。
		media.shadow_view = shadowModelView; // 主阴影视图。
	#endif
	media.shadow_projection = shadowProjection; // 阴影投影。
	media.cloud_shadow_screen = screenSize; // 云影贴图所在画面尺寸。
	media.cloud_shadow_texel = pixelSize; // 画面像素大小。
	media.wetness = wetness; // 湿润度。
	media.eye_skylight = eyeBrightnessSmoothCurved; // 天空光平滑值。
	media.time_midnight = timeMidnight; // 午夜强度。
	media.time_factor = fogTimeFactor; // 雾的时间因子。
	media.global_cloud_shadow = globalCloudShadow; // 全局云影。
	media.shadow_map_resolution = float(shadowMapResolution); // 阴影图像素边长。
	media.shadow_bias = OMNI_SHADOW_MAP_BIAS; // 阴影坐标压缩强度。
	media.cloud_shadow_range = OMNI_CLOUD_SHADOW_RANGE; // 云影覆盖范围。
	media.cloud_shadow_tex_size = OMNI_CLOUD_SHADOWTEX_SIZE; // 云影贴图最大边长。
	media.rain_shadow = OMNI_RAIN_SHADOW; // 雨天云影底值。
	media.storm_time = frameTimeCounter; // 暴风噪声滚动时间。
	media.wind_time = (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET) * 0.0025; // 团雾随风移动时间。
	media.sky_intensity = OMNI_SKYLIGHT_INTENSITY; // 天光强度。
	media.sun_intensity = OMNI_SUNLIGHT_INTENSITY; // 阳光强度。
	media.fog_density_option = OMNI_VFOG_FOG_DENSITY; // 环境雾强度。
	media.sun_density_option = OMNI_VFOG_SUNLIGHT_DENSITY; // 散射强度。
	#if OMNI_INDOOR_FOG // 室内雾开关。
		const bool indoor = true; // 关闭随天空光衰减。
	#else
		const bool indoor = false; // 默认随天空光衰减。
	#endif
	#ifdef OMNI_CAVE_MODE // 洞穴模式。
		const bool caveMode = true; // 散射也按天空光衰减。
	#else
		const bool caveMode = false; // 散射保持。
	#endif

	#ifdef DISTANT_HORIZONS // 基础密度按远景渲染距离归一化。
		media.base_density = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.25 + 0.25) / clamp(float(dhRenderDistance), 512.0, 2048.0);
	#else // 没有远景时按近景远裁剪面归一化。
		media.base_density = OMNI_VFOG_DENSITY_BASE * (timeMidnight * 0.1 + 0.05) / max(far, 100.0);
	#endif
	#if !OMNI_INDOOR_FOG // 默认让体积雾随天空光等级衰减。
		media.base_density *= eyeBrightnessSmoothCurved; // 乘天空光曲线平滑值。
	#endif

	#if OMNI_SNOW_STORM || OMNI_SAND_STORM // 只有开启至少一种暴风时才计算强度。
		float stormSnow = OmniSnowStorm(); // 雪暴强度。
		float stormSand = OmniSandStorm(); // 沙暴强度。
		float stormStrength = clamp(stormSnow + stormSand, 0.0, 1.0); // 总强度。
		media.storm_color = mix(vec3(1.0), OmniStormColor(stormSnow, stormSand), stormStrength); // 暴风染色。
		media.daily_fog = OmniDailyWeatherFog(); // 当天匀雾密度。
	#else // 没开暴风时保持单位色与零密度。
		float stormSnow = 0.0; // 零雪暴。
		float stormSand = 0.0; // 零沙暴。
		float stormStrength = 0.0; // 零总强度。
		media.storm_color = vec3(1.0); // 不染色。
		media.daily_fog = 0.0; // 没有匀雾。
	#endif
	media.storm_strength = stormStrength; // 总强度。
	media.snow_storm = stormSnow; // 雪暴强度。
	media.storm_density = OMNI_STORM_DENSITY; // 暴风浓度。
	media.storm_height = OMNI_STORM_HEIGHT; // 暴风起始高度。
	media.density_scale = FogDensityScale(stormStrength); // 时段与每日天气密度标度。

	#if OMNI_PER_BIOME_ENV // 群系权重每像素算一次，供密度与雾色共用。
		vec4 biomeWeights = omniBiomeWeights(); // 四个群系的权重。
		float biomeCoverage; // 落在群系内的程度。
		vec3 biomeColor; // 群系雾色。
		omniBiomeFogColor(biomeWeights, biomeColor, biomeCoverage); // 取群系雾色与覆盖程度。
		float biomeUniform = biomeWeights.x * OMNI_SWAMP_FOG_DENSITY + biomeWeights.y * OMNI_JUNGLE_FOG_DENSITY + biomeWeights.z * OMNI_DARKFOREST_FOG_DENSITY + biomeWeights.w * OMNI_PALE_GARDEN_FOG_DENSITY; // 各群系高度衰减雾密度加权和。
		float biomeCloudy = biomeWeights.w * OMNI_PALE_GARDEN_FOG_CLOUDY_DENSITY + biomeWeights.x * OMNI_SWAMP_FOG_CLOUDY_DENSITY + biomeWeights.y * OMNI_JUNGLE_FOG_CLOUDY_DENSITY + biomeWeights.z * OMNI_DARKFOREST_FOG_CLOUDY_DENSITY; // 各群系团雾密度加权和。
		media.biome_coverage = biomeCoverage; // 覆盖程度。
		media.biome_height = biomeUniform; // 高度雾密度。
		media.biome_cloudy = biomeCloudy; // 团雾密度。
		media.biome_color = biomeColor; // 群系雾色。
	#else // 关闭群系环境时保持原密度与单位色。
		media.biome_coverage = 0.0; // 不在群系内。
		media.biome_height = media.density_scale; // 原密度标度。
		media.biome_cloudy = media.density_scale; // 原密度标度。
		media.biome_color = vec3(1.0); // 不染色。
	#endif

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float dither = BlueNoiseTemporal().y; // 用蓝噪声另一个通道避免与反射抖动相关。
	#else // 固定拜尔抖动。
		float dither = bayer64(gl_FragCoord.xy); // 固定图案。
	#endif
	#ifdef VFOG_LQ // `composite2` 打开低质量宏时体积雾只用三步。
		const int steps = 3; // 低质量步数。
	#else
		const int steps = int(OMNI_VFOG_QUALITY); // 选项里的采样质量。
	#endif
	#ifdef OMNI_VFOG_VOLUMETRIC_LIGHTING // 打开体积光照时用多级相位。
		const bool volumetricLighting = true; // 多级散射。
	#else
		const bool volumetricLighting = false; // 单级散射。
	#endif
	#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW && defined OMNI_VFOG_CLOUD_SHADOW // 有云影时逐点采样。
		const bool useCloudShadow = true; // 使用逐点云影。
	#else
		const bool useCloudShadow = false; // 使用全局云影。
	#endif
	#ifdef OMNI_VFOG_STAINED // 半透明染色只在支持遮挡贴图的显卡上开启。
		#ifdef MC_GL_VENDOR_NVIDIA
			const bool useStained = true; // 使用染色。
		#else
			const bool useStained = false; // 显卡不支持。
		#endif
	#else
		const bool useStained = false; // 选项关闭。
	#endif
	#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用一号阴影深度。
		const bool useSolidShadow = true; // 读一号深度。
	#else
		const bool useSolidShadow = false; // 读零号深度。
	#endif
	ogxVolumetricFog(color, startPos, endPos, worldDir, media, noisetex, shadowtex0, shadowtex1, shadowcolor0,
		colortex2, OMNI_VFOG_NOISE_TYPE != 0, volumetricLighting, useCloudShadow, useStained, useSolidShadow, indoor, caveMode,
		OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2, OMNI_VFOG_FALLOFF, OMNI_VFOG_SUNLIGHT_ABSORPTION, steps,
		VFOG_SUNLIGHT_STEPS, VFOG_SUNLIGHT_STEPLENGTH, dither, transmittance); // 一次调用完成整段步进。
}
// --- 参考签名兼容层：体积雾的两个参考函数 ---
// 参考的粉末效应用吸收系数与光照吸收系数直接插值，库里的版本参数化程度不同。
float PowderEffect(float absorption, float lightingAbsorption, float VdotL){
	return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5);
}
// 参考把四档散射系数写进调用方给的数组；库返回四分量，这里按参考循环填回。
void MultiScatteringPhases(float VdotL, inout float phases[4]){
	float cn = 1.0;
	for (int i = 0; i < 4; i++, cn *= 0.5){
		phases[i] = ogxFogPhase(VdotL * cn);
	}
}

// 参考签名兼容层：体积雾密度按参考的上下界与衰减，时间项由调用方给。
float FogDensity(vec3 fogPos, vec3 wind){
	float maxHeight = max(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2);
	float minHeight = min(OMNI_VFOG_HEIGHT, OMNI_VFOG_HEIGHT_2);
	float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0);
	dh *= 2.0 / OMNI_VFOG_FALLOFF;
	float density = exp2(-dh * (1.0 - 0.0 * 0.5));
	return density * 0.1;
}
#endif // OMNI_VOLUMETRIC_INCLUDED
