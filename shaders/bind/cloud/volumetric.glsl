/*
体积云：把云层选项与纹理换成通用库参数，形状、光照与沿视线步进各调用一次。
来源 iterationT `NUBIS.glsl`。
调用位置：由 `effects/cloud/cloud.glsl` 引入；只在读得到三维云噪声的延迟三号、七号、八号参与编译，其它程序整段跳过。
可复制示例：
    `NubisCumulus(color, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance);`
    `NubisExtraLayers(color, worldDir, windDirection, camera, noise, intersectsGround, cloudTransmittance);`
    `vec4 cloudImage = omniCloudImage(worldDir, camera, noise, cloudAltitude, windDirection, intersectsGround, worldDir.y < 0.0);`
调用前提：云与云层选项由 `effects/cloud/cloud.glsl` 定义；三维云噪声采样器由延迟程序打开；
    闪电照明由 `effects/sky/atmosphere.glsl` 提供；球面求交与曲线由 `common/math.glsl` 提供。
设计原因与取舍：步进与光照主循环在 `gfx/cloud.glsl`，这里只把晴雨、附加层与每日天气换算成
    `gfx_cloud_media`，并在步进结果上补空气透视；这样通用库不读取任何选项或宿主纹理。
    采样数上限仍按 `OMNI_CLOUD_SAMPLES - ...` 与 `marchingSteps * OMNI_CLOUD_QUALITY` 的口径换算；
    闪电照明沿用 `omniLightningVolume` 的竖直光柱公式，采样点按 `marchingPos - cameraPosition`
    换到相机相对坐标，具体计算已随主循环放进通用库。
*/
#ifndef OMNI_CLOUD_VOLUMETRIC_INCLUDED
#define OMNI_CLOUD_VOLUMETRIC_INCLUDED
#ifdef OMNI_CLOUD_DENSITY_PASS // 由 effects/cloud/cloud.glsl 在三维云噪声可用的阶段打开；其它程序整段不编译。
// 云的光照相位、顶部曲线与体积云主循环放在通用库；只在需要云密度的阶段引入。
#include "/gfx/cloud_volume.glsl"
#if OMNI_CLOUD_CUMULONIMBUS == 1 // 中档积雨云要读雷暴强度；Iris 内建量，本程序里 `storm.glsl` 不参与编译，所以在此声明。
uniform float thunderStrength; // 雷暴强度，零到一，已由加载器平滑；零表示没有雷暴。
#endif

// 把当前选项、光色与天气打包成一层云的参数；附加层只改海拔、受光、密度与云量。
gfx_cloud_media CloudMedia(vec2 cloudAltitude, vec2 lightingStrength, float cloudScale, float cloudDensityOption, float cloudCoverage){
	gfx_cloud_media media; // 一层云的参数。
	media.wind = vec3(0.0); // 风在调用处填，先给零。
	media.camera_position = cameraPosition; // 相机绝对世界位置。
	media.light_color = colorShadowlight; // 直射光色。
	media.sky_color = colorSkylight; // 天空环境光色。
	media.lightning_position = vec3(0.0); // 默认没有闪电。
	media.lightning_intensity = 0.0; // 默认没有闪电事件。
	#if OMNI_LIGHTNING && defined IS_IRIS // 只有真实闪电输入可用时才读取事件。
		media.lightning_position = lightningBoltPosition.xyz; // 闪电光柱中心，相机相对坐标。
		media.lightning_intensity = lightningBoltPosition.w; // 闪电事件强度。
	#endif
	media.lightning_strength = OMNI_LIGHTNING_STRENGTH; // 闪电亮度选项。
	media.altitude = cloudAltitude; // 云层底与顶。
	media.lighting_strength = lightingStrength; // 直射与环境强度。
	media.planet_radius = atmosphereModel_bottom_radius * 1e3; // 行星半径从大气常数换成米。
	media.cloud_scale = cloudScale; // 云块水平尺度。
	media.density_option = cloudDensityOption; // 密度倍率。
	media.coverage = cloudCoverage; // 这一层的云量下限。
	media.wetness = wetness; // 湿润度。
	media.bottom_brightness = OMNI_CLOUD_BOTTOM_BRIGHTNESS; // 云底亮度。
	media.outscatter_factor = OMNI_CLOUD_OUTSCATTER_FACTOR; // 外散射指数。
	return media; // 交回打包结果。
}

// 体积云步进核心：调用通用库，再把云色按空气透视融进天空。
// `color` 是已经算好的天空颜色（会被就地修改），`worldDir` 是单位方向，`camera` 是米制相机位置。
void NubisCloudLayer(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance, vec2 lightingStrength, float cloudScale, float cloudDensityOption, float cloudCoverage){
	gfx_cloud_media media = CloudMedia(cloudAltitude, lightingStrength, cloudScale, cloudDensityOption, cloudCoverage); // 本层参数。
	media.wind = windDirection; // 风的方向与速度。
	vec3 hitOffset; // 平均命中位置，相机相对方向。
	vec4 layer = gfx_cloud_layer(worldDir, media, noise, hitOffset, colortex4, colortex6, noisetex,
		OMNI_CLOUD_SAMPLES, OMNI_CLOUD_QUALITY, worldShadowVector, OMNI_CLOUD_BASE_NOISE_SCALE,
		OMNI_CLOUD_COVERAGE_NOISE_OFFSET, OMNI_CLOUD_DETAILED_NOISE_SCALE, OMNI_CLOUD_DETAILED_NOISE_STRENGTH); // 一次调用完成步进与光照。
	cloudTransmittance = layer.a; // 云留下的透过率。
	#if OMNI_CLOUD_FADE // 打开淡出时按距离混合。
		float fade = saturate(exp2(-length(hitOffset) * 8e-5)); // 越远越淡。
		float fadedTransmittance = mix(1.0, cloudTransmittance, fade); // 淡出后的透过率。
		layer.rgb *= fade; // 远处的云颜色也压暗。
		if (cloudTransmittance < 0.9999){ // 只有真的有云才需要算透视。
			vec3 atmoPoint = camera + hitOffset * 0.001; // 取云命中处附近一点。
			vec3 transmittance; // 大气透过率输出。
			vec3 aerial = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
			color *= fadedTransmittance; // 天空被云挡住的部分。
			color += aerial * (1.0 - fadedTransmittance); // 加上空气散射。
			color += layer.rgb * transmittance; // 加上云本身被大气衰减后的颜色。
		}
	#else // 关闭淡出时直接用透过率混合。
		if (cloudTransmittance < 0.9999){ // 只有真的有云才处理。
			vec3 atmoPoint = camera + hitOffset * 0.001; // 取云命中处附近一点。
			vec3 transmittance; // 大气透过率输出。
			vec3 aerial = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
			color *= cloudTransmittance; // 天空被云挡住的部分。
			color += aerial * (1.0 - cloudTransmittance); // 加上空气散射。
			color += layer.rgb * transmittance; // 加上云本身颜色。
		}
	#endif
}

// 基础体积云：把晴雨两档的受光、尺度、密度与云量按湿润度插值后交给步进核心。
void NubisCumulus(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance){
	vec2 lightingStrength = vec2(mix(OMNI_CLOUD_CLEAR_SUNLIGHTING, OMNI_CLOUD_RAIN_SUNLIGHTING, wetness), // 直射强度按天气插值。
		mix(OMNI_CLOUD_CLEAR_SKYLIGHTING, OMNI_CLOUD_RAIN_SKYLIGHTING, wetness)); // 环境强度按天气插值。
	float cloudScale = mix(OMNI_CLOUD_CLEAR_SCALE, OMNI_CLOUD_RAIN_SCALE, wetness); // 云块大小按天气插值。
	#if OMNI_DAILY_WEATHER // 每日天气开启时，当天云量顶替“晴天云量”这一侧。
		vec4 dailyCoverage = omniWeatherCoverage(); // 当天四层覆盖度：`x` 小积云、`y` 大积云、`z` 高层云、`w` 卷云。
		vec4 dailyDensity = omniWeatherDensity(); // 当天四层消光密度，顺序同上。
		float clearCoverage = max(dailyCoverage.x, dailyCoverage.y); // 把小积云与大积云取较大者合并成低空云量。
		float clearDensity = max(dailyDensity.x, dailyDensity.y); // 密度同样取较大者。
	#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
		float clearCoverage = OMNI_CLOUD_CLEAR_COVERAGE; // 晴天云量选项原值。
		float clearDensity = OMNI_CLOUD_CLEAR_DENSITY; // 晴天云密度选项原值。
	#endif
	float cloudDensityMul = mix(clearDensity, OMNI_CLOUD_RAIN_DENSITY, wetness); // 密度倍率。
	float cloudCoverage = mix(clearCoverage, OMNI_CLOUD_RAIN_COVERAGE, wetness); // 云量同理。
	NubisCloudLayer(color, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance, lightingStrength, cloudScale, cloudDensityMul, cloudCoverage); // 交给步进核心。
}

// 附加层：卷云、高层云与积雨云，默认全部关闭；关闭时整段不参与编译。
#if OMNI_CLOUD_CUMULONIMBUS > 0 || OMNI_CLOUD_ALTOSTRATUS || OMNI_CLOUD_CIRRUS
void NubisExtraLayers(inout vec3 color, vec3 worldDir, vec3 windDirection, vec3 camera, vec2 noise, bool intersectsGround, inout float cloudTransmittance){
	#if OMNI_CLOUD_CUMULONIMBUS > 0 // 积雨云：高耸的雷暴云。
		vec2 cumulonimbusAltitude = vec2(OMNI_CLOUD_CUMULONIMBUS_ALTITUDE); // 底部高度。
		cumulonimbusAltitude.y += OMNI_CLOUD_CUMULONIMBUS_THICKNESS; // 顶部高度。
		float cumulonimbusStrength = 1.0; // 强档：始终满强度。
		#if OMNI_CLOUD_CUMULONIMBUS == 1
			cumulonimbusStrength = smoothstep(0.0, 0.1, thunderStrength); // 中档：雷暴强度驱动出现与消退。
		#endif
		if (cumulonimbusStrength > 1e-4 && (cameraPosition.y > cumulonimbusAltitude.x || !intersectsGround) && (cameraPosition.y < cumulonimbusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			float cumulonimbusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cumulonimbusAltitude, windDirection, camera, noise, cumulonimbusTransmittance,
				vec2(OMNI_CLOUD_CUMULONIMBUS_SUNLIGHTING, OMNI_CLOUD_CUMULONIMBUS_SKYLIGHTING), OMNI_CLOUD_CUMULONIMBUS_SCALE,
				OMNI_CLOUD_CUMULONIMBUS_DENSITY * cumulonimbusStrength, OMNI_CLOUD_CUMULONIMBUS_COVERAGE); // 复用步进核心。
			#if OMNI_CUMULONIMBUS_LIGHTNING && OMNI_LIGHTNING && defined IS_IRIS // 只有真实闪电输入可用时才加云内闪电。
				if (lightningBoltPosition.w > 0.0){ // 没有闪电事件时不加。
					float boltDistance = length(lightningBoltPosition.xyz); // 闪电到相机的距离。
					float distanceWeight = saturate(1.0 - boltDistance / 7500.0); // 超过七千五百格的闪电照不到云。
					float flash = lightningBoltPosition.w * distanceWeight * (1.0 - cumulonimbusTransmittance); // 云越厚被照亮越明显。
					color += vec3(0.63, 0.756, 1.22) * (flash * OMNI_CUMULONIMBUS_LIGHTNING_BRIGHTNESS * 0.01); // 冷色闪光。
				}
			#endif
			cloudTransmittance *= cumulonimbusTransmittance; // 积雨云也挡住后面的天体。
		}
	#endif
	#if OMNI_CLOUD_ALTOSTRATUS // 高层云。
		vec2 altostratusAltitude = vec2(OMNI_CLOUD_ALTOSTRATUS_ALTITUDE); // 底部高度。
		altostratusAltitude.y += OMNI_CLOUD_ALTOSTRATUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > altostratusAltitude.x || !intersectsGround) && (cameraPosition.y < altostratusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#if OMNI_DAILY_WEATHER // 每日天气开启时取当天第三项。
				float altostratusDensity = omniWeatherDensity().b; // 当天高层云密度。
				float altostratusCoverage = omniWeatherCoverage().b; // 当天高层云量。
			#else // 关闭时用选项原值。
				float altostratusDensity = OMNI_CLOUD_ALTOSTRATUS_DENSITY; // 高层云密度选项原值。
				float altostratusCoverage = OMNI_CLOUD_ALTOSTRATUS_COVERAGE; // 高层云量选项原值。
			#endif
			float altostratusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, altostratusAltitude, windDirection, camera, noise, altostratusTransmittance,
				vec2(OMNI_CLOUD_ALTOSTRATUS_SUNLIGHTING, OMNI_CLOUD_ALTOSTRATUS_SKYLIGHTING), OMNI_CLOUD_ALTOSTRATUS_SCALE,
				altostratusDensity, altostratusCoverage); // 复用步进核心。
			cloudTransmittance *= altostratusTransmittance; // 高层云也挡住后面的天体。
		}
	#endif
	#if OMNI_CLOUD_CIRRUS // 卷云。
		vec2 cirrusAltitude = vec2(OMNI_CLOUD_CIRRUS_ALTITUDE); // 底部高度。
		cirrusAltitude.y += OMNI_CLOUD_CIRRUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > cirrusAltitude.x || !intersectsGround) && (cameraPosition.y < cirrusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#if OMNI_DAILY_WEATHER // 每日天气开启时取当天第四项。
				float cirrusDensity = omniWeatherDensity().a; // 当天卷云密度。
				float cirrusCoverage = omniWeatherCoverage().a; // 当天卷云量。
			#else // 关闭时用选项原值。
				float cirrusDensity = OMNI_CLOUD_CIRRUS_DENSITY; // 卷云密度选项原值。
				float cirrusCoverage = OMNI_CLOUD_CIRRUS_COVERAGE; // 卷云量选项原值。
			#endif
			float cirrusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cirrusAltitude, windDirection, camera, noise, cirrusTransmittance,
				vec2(OMNI_CLOUD_CIRRUS_SUNLIGHTING, OMNI_CLOUD_CIRRUS_SKYLIGHTING), OMNI_CLOUD_CIRRUS_SCALE,
				cirrusDensity, cirrusCoverage); // 复用步进核心。
			cloudTransmittance *= cirrusTransmittance; // 卷云也挡住后面的天体。
		}
	#endif
}
#endif // 附加层结束。

// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
float CloudShadowTex(vec2 coord, vec2 cloudAltitude, vec3 windDirection){
	gfx_cloud_media media = CloudMedia(cloudAltitude, vec2(0.0), 1.0, 0.0, mix(OMNI_CLOUD_CLEAR_COVERAGE, OMNI_CLOUD_RAIN_COVERAGE, wetness)); // 云影只需要云量与风。
	media.wind = windDirection; // 风的方向。
	return gfx_cloud_shadow_tex(coord, media, worldShadowVector, OMNI_CLOUD_SHADOW_RANGE, colortex4, noisetex,
		OMNI_CLOUD_BASE_NOISE_SCALE, OMNI_CLOUD_COVERAGE_NOISE_OFFSET, OMNI_CLOUD_DETAILED_NOISE_SCALE, OMNI_CLOUD_DETAILED_NOISE_STRENGTH); // 一次调用完成云影。
}

#ifdef OMNI_DEFERRED7_PASS // 低分辨率体积云总图：只算基础体积云，供放大后贴回天空。
// 为什么从透明底算起：体积云的加色与透过率与背景天空无关；先算出这两项，再在合成阶段用
// 「天空颜色乘透过率加云色」还原，就能在低分辨率上算云、在全分辨率上贴回，画面不裂开。
// 返回 `rgb` 是云的加色项，`a` 是云留下的透过率；平面云与附加层仍留在全分辨率的合成阶段。
vec4 omniCloudImage(vec3 worldDir, vec3 cloudCamera, vec2 noise, vec2 cloudAltitude, vec3 windDirection, bool intersectsGround, bool dirBelowHorizon){
	vec3 color = vec3(0.0); // 从透明底开始，得到的颜色就是云的加色项。
	float cloudTransmittance = 1.0; // 云留下的透过率初值。
	#ifdef OMNI_VOLUMETRIC_CLOUDS // 与延迟三号同一可见判据，只在相机能看到云层时步进。
		if ((cameraPosition.y > cloudAltitude.x || !intersectsGround) && (cameraPosition.y < cloudAltitude.y || dirBelowHorizon))
			NubisCumulus(color, worldDir, cloudAltitude, windDirection, cloudCamera, noise, cloudTransmittance); // 基础体积云。
	#endif
	return vec4(color, cloudTransmittance); // 返回加色与透过率。
}
#endif // 低分辨率体积云总图结束。
#endif // 云密度阶段结束。
#endif // 文件守卫结束。
