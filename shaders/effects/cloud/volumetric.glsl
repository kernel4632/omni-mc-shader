/*
体积云：三维噪声塑形、沿视线步进与云的光照，外加附加云层（卷云、高层云与积雨云）与低分辨率云总图。
来源 iterationT `NUBIS.glsl`。
调用位置：由 `effects/cloud/cloud.glsl` 引入；只在读得到三维云噪声的延迟三号、七号、八号参与编译，其它程序整段跳过。
可复制示例：
    `NubisCumulus(color, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance);`
    `NubisExtraLayers(color, worldDir, windDirection, camera, noise, intersectsGround, cloudTransmittance);`
    `vec4 cloudImage = omniCloudImage(worldDir, camera, noise, cloudAltitude, windDirection, intersectsGround, worldDir.y < 0.0);`
调用前提：云与云层选项由 `effects/cloud/cloud.glsl` 定义；三维云噪声采样器由延迟程序打开；
    闪电照明由 `effects/sky/atmosphere.glsl` 提供；球面求交与曲线由 `common/math.glsl` 提供。
设计原因与取舍：基础体积云与附加层共用同一套密度与光照函数，附加层只把海拔、厚度、云量、密度交给它，避免重复实现；
    云影贴图采样 `CloudShadowTex` 也依赖这里的密度采样，所以和密度函数放在一起；整段只在云密度可用的阶段编译，别的程序不产生无用代码。
*/
#ifndef OMNI_CLOUD_VOLUMETRIC_INCLUDED
#define OMNI_CLOUD_VOLUMETRIC_INCLUDED
#ifdef OMNI_CLOUD_DENSITY_PASS // 由 effects/cloud/cloud.glsl 在三维云噪声可用的阶段打开；其它程序整段不编译。
#if OMNI_CLOUD_CUMULONIMBUS == 1 // 中档积雨云要读雷暴强度；Iris 内建量，本程序里 `storm.glsl` 不参与编译，所以在此声明。
uniform float thunderStrength; // 雷暴强度，零到一，已由加载器平滑；零表示没有雷暴。
#endif
// --- 亨耶-格林斯坦相位函数：云这种大粒子的前向散射，输入夹角余弦与不透明度参数 ---
float HenyeyGreenstein(float inCosAngle, float inG){
	float num = 1.0 - inG * inG; // 分子，归一化用。
	float denom = 1.0 + inG * inG - 2.0 * inG * inCosAngle; // 分母，越前向越小。
	float rsqrt_denom = inversesqrt(denom); // 分母的近似负二分之一次方。
	return num * rsqrt_denom * rsqrt_denom * rsqrt_denom * (0.25 / PI); // 归一化后返回相位值。
}
// 云顶上凸的收口曲线：把零到一映射成一道平滑的弧，云顶因此不是平切。
float curveTop(float x){
	x = x - 1.0; // 先平移到负一到零。
	return 1.0 - x * x; // 开口向下的抛物线。
}
// 采样云密度：先叠基础形状与云量得到不透明密度，再叠细节噪声得到碎边。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sampleDetail` 为假时跳过细节以省性能。
// `coverage` 是这一层的云量下限：基础云传晴雨混合值，附加层传各自的云量选项。
vec2 SampleCloudDensity(vec4 cloudPos, vec3 windDirection, bool sampleDetail, float coverage){
	// 基础形状：低频三维噪声决定云块大轮廓。
		vec4 baseNoise = textureLod(colortex4, cloudPos.xyz * OMNI_CLOUD_BASE_NOISE_SCALE + windDirection * 10.0, 0.0); // 按云坐标与风偏移读基础噪声。
		float baseDensity = baseNoise.y * 0.4 + baseNoise.z * 0.4 + baseNoise.w * 0.2; // 三个通道加权得到形状。
		baseDensity = remapSaturate(baseNoise.x, baseDensity - 1.0, 1.0); // 用第一通道做概率重映射，得到云块。
		float shapeCurve = curveTop(saturate(1.0 - cloudPos.w)) * 0.5; // 上半段的收口曲线。
		shapeCurve += curve(saturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 下半段的收口曲线。
		baseDensity *= shapeCurve; // 竖直方向收口，云像是浮在中间。
		baseDensity *= fsqrt(saturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 下半段略压扁。
		baseDensity *= mix(1.0, curveTop(saturate(cloudPos.w * 3.0)), wetness); // 雨天让云更集中在顶部。
	// 云量：单独的更低频噪声决定这一块区域有没有云。
		float coverageNoise = textureLod(colortex4, cloudPos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + windDirection + OMNI_CLOUD_COVERAGE_NOISE_OFFSET, 0.0).x; // 极低频云量噪声。
		coverage = remapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 把云量映射成密度下限。
		baseDensity = remapSaturate(baseDensity, coverage, 1.0); // 低于下限的部分去掉。
	// 密度控制：竖直方向再塑形，让云底更密云顶更薄。
		baseDensity *= curve(saturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 中段加厚。
		baseDensity *= curveTop(saturate(cloudPos.w * 1.8)); // 顶部收口。
		baseDensity = saturate(baseDensity); // 收敛到零到一。
	float detailedDensity = 0.0; // 详细密度，下面按是否需要细节赋值。
	if(baseDensity > 1e-6 && sampleDetail){ // 只有基础密度确实存在才叠细节。
		// 卷曲噪声：让云的边缘随高度发生横向扭曲。
			float curlNoise = textureLod(noisetex, cloudPos.xy * 0.0001, 0.0).w; // 读噪声第四通道。
			cloudPos.xy += curlNoise * (100.0 - cloudPos.w * 100.0); // 越靠云底扭曲越大。
		// 细节噪声：高频三维噪声给云块加碎边。
			vec3 detailedNoise = textureLod(colortex6, cloudPos.xyz * OMNI_CLOUD_DETAILED_NOISE_SCALE + windDirection * 140.0, 0.0).xyz; // 读三十二立方细节噪声。
			detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125; // 三通道按权重合成侵蚀量。
			detailedDensity *= (0.21 - wetness * 0.11) * OMNI_CLOUD_DETAILED_NOISE_STRENGTH; // 强度与天气权重可调。
			detailedDensity = remapSaturate(baseDensity, detailedDensity, 1.0); // 用基础密度限制侵蚀范围。
	}else{ // 不需要细节时直接用基础密度。
		detailedDensity = baseDensity; // 保持连续。
	}
	return vec2(baseDensity, detailedDensity); // 返回两份密度。
}
// 基础云的密度采样：云量取晴雨混合值，行为与 iterationT 的 `SampleDensity` 完全一致。
vec2 SampleDensity(vec4 cloudPos, vec3 windDirection, bool sampleDetail){
	return SampleCloudDensity(cloudPos, windDirection, sampleDetail, mix(OMNI_CLOUD_CLEAR_COVERAGE, OMNI_CLOUD_RAIN_COVERAGE, wetness)); // 传入晴雨混合云量。
}
// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向加随高度增大的偏移。
vec4 SetCloudPos(vec3 marchingPos, vec2 cloudAltitude, float planetRadius, float cloudScale, vec3 windDirection){
	vec4 cloudPos = vec4(marchingPos, 0.0); // 前三通道是位置，第四通道是层内高度。
	cloudPos.y = length(cloudPos.xyz + vec3(0.0, planetRadius, 0.0)) - planetRadius; // 用球面距离算真实高度。
	cloudPos.w = remapSaturate(cloudPos.y, cloudAltitude.x, cloudAltitude.y); // 在云层里的归一化高度。
	cloudPos.xyz = cloudPos.xyz * cloudScale + vec3(30.0 * cloudPos.w, 0.0, -12.0 * cloudPos.w); // 水平缩放并随高度剪切，云因此有斜向层次。
	return cloudPos; // 返回云坐标。
}
// 云的光照：沿光方向在云里步进估遮挡，再算直射与环境的合成颜色。
// `coverage` 是这一层的云量下限，供光照步进复用同一份形状，基础云与附加层各自传入。
vec3 CloudLighting(vec3 marchingPos, vec2 cloudAltitude, float planetRadius, float cloudScale, vec2 lightingStrength, vec2 cloudDensity, vec4 cloudPos, vec3 windDirection, float noise, float VdotL, float coverage){
	float stepLength = 28.0; // 光照步进起始步长。
	float lightingDensity = 0.0; // 沿光方向累积的云密度。
	for (int i = 0; i < 5; i++, stepLength *= 1.5){ // 五步，步长逐步放大。
		vec4 checkPos = SetCloudPos(marchingPos + worldShadowVector * stepLength * noise, cloudAltitude, planetRadius, cloudScale, windDirection); // 取样点。
		lightingDensity += SampleCloudDensity(checkPos, windDirection, i < 3, coverage).y * stepLength; // 前三步带细节，后两步省掉。
		marchingPos += worldShadowVector * stepLength; // 沿光方向推进。
	}
	// 直射散射：透过云层的阳光，含一个很宽的环境项。
		float hg = HenyeyGreenstein(VdotL, 0.7); // 前向相位，决定银边。
		float directScattering = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - wetness * 0.8); // 透过率乘前向相位。
		directScattering += (1.0 / (lightingDensity * 0.2 + 1.0)) * (HenyeyGreenstein(VdotL, 0.2) + 0.1); // 叠一个更宽的环境项。
		directScattering *= hg * 2.0 + 1.0; // 银边再加强一次。
		directScattering *= mix(OMNI_CLOUD_BOTTOM_BRIGHTNESS, 0.005 + pow(cloudDensity.y, OMNI_CLOUD_OUTSCATTER_FACTOR), curve(saturate(cloudPos.w * 3.333 - 0.333))); // 云底亮度与外散射按高度混合。
		directScattering *= pow(max(cloudPos.w, 0.05), 0.75); // 云顶更亮。
		vec3 cloudColor = colorShadowlight * (directScattering * lightingStrength.x * 36.0); // 乘直射光色与强度。
	// 环境散射：云背光面接到的天光。
		float ambientScattering = 1.0 - cloudDensity.x; // 云越薄环境光透得越多。
		ambientScattering *= fsqrt(cloudPos.w); // 高处环境光更多。
		cloudColor += colorSkylight * (ambientScattering * lightingStrength.y * 0.35); // 乘天光色与强度。
	// Omni 额外功能：真实闪电事件照亮这一段云，按云采样点到闪电光柱的距离叠冷色闪光。
	// 四百格范围与较弱的指数衰减照 Eclipse `Iris_Lightningflash_VLcloud`；采样点是世界坐标，先换相机相对再比距离。
		cloudColor += omniLightningVolume(marchingPos - cameraPosition, 400.0, -10.0); // 没有闪电输入时返回零，不改变画面。
	return cloudColor; // 返回云的颜色。
}
// 体积云步进核心：沿视线在云层里步进，累加颜色与透过率，最后按空气透视与天空混合。
// 受光强度、云块尺度、密度与云量都由调用方给出，基础云与附加层因此共用同一套步进与光照。
// 调用前提：`color` 是已经算好的天空颜色（会被就地修改）、`worldDir` 是单位方向、`camera` 是米制相机位置。
void NubisCloudLayer(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance, vec2 lightingStrength, float cloudScale, float cloudDensityOption, float cloudCoverage){
	const float planetRadius = atmosphereModel_bottom_radius * 1e3; // 行星半径从大气常数换成米。
	// 步进区间：先求视线与云层上下界的交点。
		vec3 rayStartPos = vec3(0.0, planetRadius + cameraPosition.y, 0.0); // 相机在行星球上的位置。
		vec2 iBottom = RaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude.x); // 与云层底的交点。
		vec2 iTop = RaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude.y); // 与云层顶的交点。
		vec2 iMarching = cameraPosition.y > cloudAltitude.y ? vec2(iTop.x, iBottom.x) : vec2(iBottom.y, iTop.y); // 相机在云上还是云下决定进出顺序。
		vec3 marchingStart = iMarching.x * worldDir; // 步进起点相对相机。
		vec3 marchingEnd = iMarching.y * worldDir; // 步进终点相对相机。
		float inCloud = (1.0 - saturate((cameraPosition.y - cloudAltitude.y) * 0.005)) * // 相机低于云顶的权重。
						(1.0 - saturate((cloudAltitude.x - cameraPosition.y) * 0.005)); // 相机高于云底的权重。
		float iInner = iBottom.y >= 0.0 && cameraPosition.y > cloudAltitude.x ? iBottom.x : iTop.y; // 云内起点距离。
		iInner = min(iInner, 5000.0); // 限长避免步进过远。
		marchingStart = marchingStart * (1.0 - inCloud) + cameraPosition; // 相机在云内时起点改到相机。
		marchingEnd = mix(marchingEnd, iInner * worldDir, inCloud) + cameraPosition; // 相机在云内时终点改到云内一点。
		float marchingSteps = OMNI_CLOUD_SAMPLES - saturate(fsqrt(abs(worldDir.y)) * 1.4 - 0.4) * 8.0; // 采样数上限，越朝上步数越少。
		marchingSteps = max(floor(marchingSteps * OMNI_CLOUD_QUALITY), 1.0); // 乘精细度倍率，并保证至少一步。
		float marchingStepSize = 1.0 / marchingSteps; // 归一化步长。
		vec3 marchingIncrement = (marchingEnd - marchingStart) * marchingStepSize; // 每步位移。
		vec3 marchingPos = marchingStart + marchingIncrement * noise.x; // 起点加抖动量，减少条带。
		float marchingLength = length(marchingIncrement); // 每步的米制长度。
	// 云参数：受光、尺度与云量已由调用方算好，这里只把密度换算成消光系数。
		float cloudDensityMul = cloudDensityOption; // 调用方给的密度倍率。
		cloudDensityMul *= (cloudAltitude.y - cloudAltitude.x) * marchingStepSize; // 乘层厚与归一化步长得消光系数。
		float VdotL = dot(worldDir, worldShadowVector); // 视线与光方向的夹角余弦。
	// 步进：前向累积颜色，透过率降到很低就提前结束。
		vec3 cloudAccum = vec3(0.0, 0.0, 0.0); // 累积的云颜色。
		cloudTransmittance = 1.0; // 初始完全透明。
		vec3 rayHitPos = vec3(0.0); // 用于估平均命中位置的加权和。
		float sumTransmit = 0.0; // 透过率权重和。
		for (int i = 0; i < int(marchingSteps); i++, marchingPos += marchingIncrement){	// 逐步推进。
			vec4 cloudPos = SetCloudPos(marchingPos, cloudAltitude, planetRadius, cloudScale, windDirection); // 当前云坐标。
			vec2 cloudDensity = SampleCloudDensity(cloudPos, windDirection, true, cloudCoverage); // 采样密度，用本层云量。
			if (cloudDensity.y < 1e-6) continue; // 这一步没有云就跳过。
			vec3 cloudColor = CloudLighting(marchingPos, cloudAltitude, planetRadius, cloudScale, lightingStrength, cloudDensity, cloudPos, windDirection, noise.y, VdotL, cloudCoverage); // 这一段云的光照。
			float absorption = exp2(-cloudDensity.y * cloudDensityMul); // 这一段的透过率。
			cloudAccum += cloudColor * (cloudTransmittance - absorption * cloudTransmittance); // 把这一段发出并被后面吸收的部分加进来。
			rayHitPos += marchingPos * cloudTransmittance; // 记录命中位置。
			sumTransmit += cloudTransmittance; // 记录权重。
			cloudTransmittance *= absorption; // 更新透过率。
			if (cloudTransmittance < 0.0001) break; // 几乎不透明就不再采样。
		}
	// 空气透视：远处云融进大气，近处云保持实体。
		#if OMNI_CLOUD_FADE // 打开淡出时按距离混合。
			rayHitPos /= sumTransmit; // 平均命中位置。
			rayHitPos -= cameraPosition; // 换成相对相机的方向。
			float fade = saturate(exp2(-length(rayHitPos) * 8e-5)); // 越远越淡。
			float cloudTransmittanceFaded = mix(1.0, cloudTransmittance, fade); // 淡出后的透过率。
			cloudAccum *= fade; // 远处的云颜色也压暗。
			if(cloudTransmittance < 0.9999){ // 只有真的有云才需要算透视。
				vec3 atmoPoint = camera + rayHitPos * 0.001; // 取云命中处附近一点。
				vec3 transmittance; // 大气透过率输出。
				vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
				color *= cloudTransmittanceFaded; // 天空被云挡住的部分。
				color += aerialPerspective * (1.0 - cloudTransmittanceFaded); // 加上空气散射。
				color += cloudAccum * transmittance; // 加上云本身被大气衰减后的颜色。
			}
		#else // 关闭淡出时直接用透过率混合。
			if(cloudTransmittance < 0.9999){ // 只有真的有云才处理。
				rayHitPos /= sumTransmit; // 平均命中位置。
				rayHitPos -= cameraPosition; // 换成相对相机的方向。
				vec3 atmoPoint = camera + rayHitPos * 0.001; // 取云命中处附近一点。
				vec3 transmittance; // 大气透过率输出。
				vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
				color *= cloudTransmittance; // 天空被云挡住的部分。
				color += aerialPerspective * (1.0 - cloudTransmittance); // 加上空气散射。
				color += cloudAccum * transmittance; // 加上云本身颜色。
			}
		#endif
}
// 基础体积云：把晴雨两档的受光、尺度、密度与云量按湿润度插值后交给步进核心，行为与 iterationT 一致。
// 调用前提：同一套步进核心，参数取晴雨混合值。
void NubisCumulus(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance){
	vec2 lightingStrength = vec2(mix(OMNI_CLOUD_CLEAR_SUNLIGHTING, OMNI_CLOUD_RAIN_SUNLIGHTING, wetness), // 直射强度按天气插值。
								 mix(OMNI_CLOUD_CLEAR_SKYLIGHTING, OMNI_CLOUD_RAIN_SKYLIGHTING, wetness)); // 环境强度按天气插值。
	float cloudScale = mix(OMNI_CLOUD_CLEAR_SCALE, OMNI_CLOUD_RAIN_SCALE, wetness); // 云块大小按天气插值。
	#if OMNI_DAILY_WEATHER // 每日天气开启时，当天云量顶替“晴天云量”这一侧，雨天侧仍按湿润度插值。
		vec4 dailyCoverage = omniWeatherCoverage(); // 当天四层覆盖度：`x` 小积云、`y` 大积云、`z` 高层云、`w` 卷云。
		vec4 dailyDensity = omniWeatherDensity(); // 当天四层消光密度，顺序同上。
		float clearCoverage = max(dailyCoverage.x, dailyCoverage.y); // Omni 只有一层积云，把小积云与大积云取较大者合并成这一天的低空云量。
		float clearDensity = max(dailyDensity.x, dailyDensity.y); // 密度同样取较大者，保证低空较厚的那一天不被算薄。
	#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
		float clearCoverage = OMNI_CLOUD_CLEAR_COVERAGE; // 晴天云量选项原值。
		float clearDensity = OMNI_CLOUD_CLEAR_DENSITY; // 晴天云密度选项原值。
	#endif
	float cloudDensityMul = mix(clearDensity, OMNI_CLOUD_RAIN_DENSITY, wetness); // 密度倍率：晴天侧取当天值，雨天侧仍靠向雨云。
	float cloudCoverage = mix(clearCoverage, OMNI_CLOUD_RAIN_COVERAGE, wetness); // 云量同理，雨天仍会加厚。
	NubisCloudLayer(color, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance, lightingStrength, cloudScale, cloudDensityMul, cloudCoverage); // 交给步进核心。
}
// 附加层：卷云、高层云与积雨云，默认全部关闭；关闭时整段不参与编译，不产生任何额外采样。
// 打开后各自把海拔、厚度、云量、密度、尺度与受光交给同一套步进核心，按 Eclipse 的分层顺序叠加。
// 调用前提：`color` 是已叠好天空与基础云的天空颜色，`intersectsGround` 是视线是否打到地面。
#if OMNI_CLOUD_CUMULONIMBUS > 0 || OMNI_CLOUD_ALTOSTRATUS || OMNI_CLOUD_CIRRUS
void NubisExtraLayers(inout vec3 color, vec3 worldDir, vec3 windDirection, vec3 camera, vec2 noise, bool intersectsGround, inout float cloudTransmittance){
	#if OMNI_CLOUD_CUMULONIMBUS > 0 // 积雨云：高耸的雷暴云，最先叠在基础云之上。
		// 为什么不受每日天气影响：Eclipse 的积雨云由雷暴强度与固定密度驱动，每日天气表没有它，所以这里只取积雨云自己的选项。
		vec2 cumulonimbusAltitude = vec2(OMNI_CLOUD_CUMULONIMBUS_ALTITUDE); // 底部高度。
		cumulonimbusAltitude.y += OMNI_CLOUD_CUMULONIMBUS_THICKNESS; // 顶部高度。
		// 档位强度：强档常开，中档只在雷暴时出现。为何用加载器的雷暴强度：Eclipse 用自定义输入对
		// 「是否雷暴」做六十秒进、可调时长出的跨帧平滑，本项目没有跨帧保持量，这里用加载器已经平滑好的
		// 雷暴强度近似，雷暴期间变浓、雷暴过去后随之消退。
		float cumulonimbusStrength = 1.0; // 强档：始终满强度。
		#if OMNI_CLOUD_CUMULONIMBUS == 1
			cumulonimbusStrength = smoothstep(0.0, 0.1, thunderStrength); // 中档：雷暴强度驱动出现与消退。
		#endif
		if (cumulonimbusStrength > 1e-4 && (cameraPosition.y > cumulonimbusAltitude.x || !intersectsGround) && (cameraPosition.y < cumulonimbusAltitude.y || worldDir.y < 0.0)){ // 先看档位强度，再与基础体积云同一可见判据。
			float cumulonimbusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cumulonimbusAltitude, windDirection, camera, noise, cumulonimbusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_CUMULONIMBUS_SUNLIGHTING, OMNI_CLOUD_CUMULONIMBUS_SKYLIGHTING), OMNI_CLOUD_CUMULONIMBUS_SCALE, OMNI_CLOUD_CUMULONIMBUS_DENSITY * cumulonimbusStrength, OMNI_CLOUD_CUMULONIMBUS_COVERAGE); // 受光、尺度、云量与档位强度缩放后的密度。
			#if OMNI_CUMULONIMBUS_LIGHTNING && OMNI_LIGHTNING && defined IS_IRIS // 只有真实闪电输入可用时才加云内闪电。
				if (lightningBoltPosition.w > 0.0){ // 没有闪电事件时不加。
					float boltDistance = length(lightningBoltPosition.xyz); // 闪电到相机的距离，闪电位置是相机相对坐标。
					float distanceWeight = saturate(1.0 - boltDistance / 7500.0); // 超过七千五百格的闪电照不到云。
					float flash = lightningBoltPosition.w * distanceWeight * (1.0 - cumulonimbusTransmittance); // 云越厚被照亮越明显。
					color += vec3(0.63, 0.756, 1.22) * (flash * OMNI_CUMULONIMBUS_LIGHTNING_BRIGHTNESS * 0.01); // 冷色闪光，亮度照 Eclipse 选项。
				}
			#endif
			cloudTransmittance *= cumulonimbusTransmittance; // 积雨云也挡住后面的天体。
		}
	#endif
	#if OMNI_CLOUD_ALTOSTRATUS // 高层云：中等高度的一片云层。
		vec2 altostratusAltitude = vec2(OMNI_CLOUD_ALTOSTRATUS_ALTITUDE); // 底部高度。
		altostratusAltitude.y += OMNI_CLOUD_ALTOSTRATUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > altostratusAltitude.x || !intersectsGround) && (cameraPosition.y < altostratusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#if OMNI_DAILY_WEATHER // 每日天气开启时，高层云的云量与密度取当天第三项 `l2`。
				float altostratusDensity = omniWeatherDensity().b; // 当天高层云密度。
				float altostratusCoverage = omniWeatherCoverage().b; // 当天高层云量。
			#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
				float altostratusDensity = OMNI_CLOUD_ALTOSTRATUS_DENSITY; // 高层云密度选项原值。
				float altostratusCoverage = OMNI_CLOUD_ALTOSTRATUS_COVERAGE; // 高层云量选项原值。
			#endif
			float altostratusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, altostratusAltitude, windDirection, camera, noise, altostratusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_ALTOSTRATUS_SUNLIGHTING, OMNI_CLOUD_ALTOSTRATUS_SKYLIGHTING), OMNI_CLOUD_ALTOSTRATUS_SCALE, altostratusDensity, altostratusCoverage); // 受光与尺度取选项，密度与云量取上面算好的值。
			cloudTransmittance *= altostratusTransmittance; // 高层云也挡住后面的天体。
		}
	#endif
	#if OMNI_CLOUD_CIRRUS // 卷云：最高处的一层薄云。
		vec2 cirrusAltitude = vec2(OMNI_CLOUD_CIRRUS_ALTITUDE); // 底部高度。
		cirrusAltitude.y += OMNI_CLOUD_CIRRUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > cirrusAltitude.x || !intersectsGround) && (cameraPosition.y < cirrusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#if OMNI_DAILY_WEATHER // 每日天气开启时，卷云的云量与密度取当天第四项 `l3`。
				float cirrusDensity = omniWeatherDensity().a; // 当天卷云密度。
				float cirrusCoverage = omniWeatherCoverage().a; // 当天卷云量。
			#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
				float cirrusDensity = OMNI_CLOUD_CIRRUS_DENSITY; // 卷云密度选项原值。
				float cirrusCoverage = OMNI_CLOUD_CIRRUS_COVERAGE; // 卷云量选项原值。
			#endif
			float cirrusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cirrusAltitude, windDirection, camera, noise, cirrusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_CIRRUS_SUNLIGHTING, OMNI_CLOUD_CIRRUS_SKYLIGHTING), OMNI_CLOUD_CIRRUS_SCALE, cirrusDensity, cirrusCoverage); // 受光与尺度取选项，密度与云量取上面算好的值。
			cloudTransmittance *= cirrusTransmittance; // 卷云也挡住后面的天体。
		}
	#endif
}
#endif // 附加层结束。
// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
// 调用前提：`coord` 是零到一的云影贴图坐标，采样方向用全局量 `worldShadowVector`。
float CloudShadowTex(vec2 coord, vec2 cloudAltitude, vec3 windDirection){
	coord = coord * OMNI_CLOUD_SHADOW_RANGE - (OMNI_CLOUD_SHADOW_RANGE * 0.5); // 贴图坐标换回相对相机的地表坐标。
	vec4 checkPos = vec4(coord.x + cameraPosition.x, 0.0, coord.y + cameraPosition.z, 0.0); // 取样点世界坐标。
	float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
	checkPos += vec4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y) , 0.25); // 投到云层下四分之一处。
	float cloudDensity = SampleDensity(checkPos, windDirection, false).y; // 取那一处云密度。
	checkPos += vec4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y) , 0.25); // 再往上一段。
	cloudDensity = max(cloudDensity, SampleDensity(checkPos, windDirection, false).y); // 两块取较厚的那块。
	return exp2(-cloudDensity * 20.0); // 密度换成透过率。
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
