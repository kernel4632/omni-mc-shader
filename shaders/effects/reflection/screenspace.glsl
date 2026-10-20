/*
屏幕空间反射：从当前像素沿反射方向在屏幕里步进找命中，未命中回退假天空盒，并算高光提示强度与反射颜色。
来源 iterationT `composite2.fsh`（追踪与着色）与 `composite5.fsh`（把反射并进场景颜色）。
调用位置：由 `effects/reflection/reflection.glsl` 引入；只在 composite2 / composite5 程序里编译，别的程序整段跳过。
可复制示例：
    `vec4 r = CalculateSpecularReflections(viewPos, worldPos, viewDir, normal, depth, albedo, material, skyLight, isHand, isSmooth, highlightStrength);`
    `CalculateSpecularReflections(color, viewDir, normal, albedo, waterSurface, gbuffer);`
设计原因与取舍：追踪、GGX 采样、假天空回退与反射着色是一个整体，和小波滤波分开成两个文件便于按算法阅读；
    反射在屏幕空间进行，只能反射画面里看得见的表面，屏幕外回退天空盒，这是屏幕空间反射的固有边界。
*/
#ifndef OMNI_REFLECTION_SCREENSPACE_INCLUDED
#define OMNI_REFLECTION_SCREENSPACE_INCLUDED // 置上标记，后续再次引用直接跳过。
#include "/gfx/reflection.glsl"
// --- composite2：屏幕空间反射与天空盒回退 ---
#ifdef OMNI_COMPOSITE2_PASS
// 蓝噪声给追踪与体积反射抖动，材质提供解码材质，天空云提供假天空反射与云影开关，雾提供反射里的体积雾与地表散射。
#include "/common/noise.glsl"
#include "/effects/ground/material.glsl"
#include "/effects/sky/sky.glsl"
#include "/effects/cloud/cloud.glsl"
#include "/effects/fog/fog.glsl"

#if !defined OMNI_NETHER && !defined OMNI_END // 主世界才用天空盒回退；下界用 `NetherFog`，末地用末地天空。
// 体素反射：屏幕空间没命中时改在体素图上追踪，提供选项、体素颜色图取样与 `omniVoxelReflection`。
#include "/effects/reflection/voxel.glsl"
// 如果屏幕追踪没命中，就用上半屏的天空盒图当反射：把反射方向投到天空盒坐标再取色。
// 为什么单列一个函数：屏幕内没有内容时天空是唯一的反射源，缺了它反射处会变成黑洞。
// 调用前提：`colortex2`、`worldMoonVector`、`colorMoonlight`、`isEyeInWater` 已由合成主程序声明。
vec3 ComputeFakeSkyReflection(vec3 reflectWorldDir){
	float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图的边长，受屏幕尺寸限制。
	vec2 skyImageCoord = ProjectSky(reflectWorldDir, tileSize); // 反射方向投到天空盒坐标，与天空写入端同一套映射。
	vec4 skyImage = textureLod(colortex2, skyImageCoord, 0.0); // 读天空盒图。
	skyImage.rgb = CurveToLinear(skyImage.rgb); // 从曲线编码换回线性。

	#ifdef OMNI_MOON_TEXTURE // 使用资源包月亮贴图时，反射里也画一个月亮圆盘。
		if (isEyeInWater == 0){ // 水下不画月亮，避免和水面下的画面冲突。
			float moonDisc = RenderMoonDiscReflection(reflectWorldDir, worldMoonVector); // 反射用的月亮圆盘，角半径更大才看得见。
			moonDisc *= mix(1.0, skyImage.a, OMNI_RAIN_SHADOW); // 按雨天遮蔽把月亮压暗。
			moonDisc *= (15.0 * OMNI_SKY_TEXTURE_BRIGHTNESS / MAIN_OUTPUT_FACTOR); // 换算到管线单位并乘纹理亮度。
			skyImage.rgb += colorMoonlight * moonDisc; // 月亮直射叠加到天空反射上。
		}
	#endif

	return skyImage.rgb; // 返回天空反射颜色。
}
#endif // 天空盒回退分支结束。

// 可见法线抽样：按粗糙度把反射方向散射开，粗糙面因此得到模糊反射。
// 来源：原程序改自一篇公开论文的可见法线抽样，作者名字与链接见参考包，本函数保持原程序写法。
vec3 sampleGGXVNDF(vec3 viewVector, float roughness, vec2 noise) { return gfx_sample_ggx_vndf(viewVector, roughness, noise); }

// 远景深度贴图选择：没有远景模组时用近景深度占位，通用库按开关决定是否读取。
#ifdef DISTANT_HORIZONS
	#define OMNI_REFLECTION_DH_DEPTH dhDepthTex1 // 远景不含半透明深度。
#else
	#define OMNI_REFLECTION_DH_DEPTH depthtex1 // 占位，不会被读取。
#endif

// 取追踪采样点的深度：把深度图选择与手部/远景开关交给通用库。
float TraceSampleDepth(vec2 coord, bool isHand){
	#if defined DISTANT_HORIZONS && OMNI_DH_SSR // 近景是天空且开启远景反射时改读远景深度。
		const bool dhSsr = true; // 启用远景反射。
	#else
		const bool dhSsr = false; // 远景按天空处理。
	#endif
	#if MC_VERSION >= 11605 // 一点一六点五以后手部有单独深度。
		const bool handSupported = true; // 支持手部深度。
	#else
		const bool handSupported = false; // 没有手部深度。
	#endif
	#ifdef DISTANT_HORIZONS
		const bool hasDh = true; // 有远景深度。
		mat4 dhInverse = dhProjectionInverse; // 远景逆投影。
	#else
		const bool hasDh = false; // 没有远景深度。
		mat4 dhInverse = gbufferProjectionInverse; // 占位。
	#endif
	return gfx_reflection_sample_depth(coord, isHand, handSupported, depthtex1, depthtex2, OMNI_REFLECTION_DH_DEPTH,
		hasDh, dhSsr, dhInverse, gbufferProjectionInverse); // 一次调用完成深度选择。
}

// 屏幕空间追踪：步进与二分细化在通用库，这里只传深度图、投影与质量选项。
bool ScreenSpaceTracer(vec3 viewRayOri, vec3 viewRayDir, float NdotV, float noise, float minLength, bool isHand, inout vec3 screenPos){
	#ifdef DISTANT_HORIZONS
		const bool hasDh = true; // 有远景深度。
		mat4 dhInverse = dhProjectionInverse; // 远景逆投影。
		#if OMNI_DH_SSR
			const bool dhSsr = true; // 启用远景反射。
		#else
			const bool dhSsr = false; // 远景按天空处理。
		#endif
	#else
		const bool hasDh = false; // 没有远景深度。
		const bool dhSsr = false; // 没有远景反射。
		mat4 dhInverse = gbufferProjectionInverse; // 占位。
	#endif
	#if MC_VERSION >= 11605
		const bool handSupported = true; // 支持手部深度。
	#else
		const bool handSupported = false; // 没有手部深度。
	#endif
	return gfx_screen_space_trace(viewRayOri, viewRayDir, NdotV, noise, minLength, isHand, screenPos,
		depthtex1, depthtex2, OMNI_REFLECTION_DH_DEPTH, gbufferProjection, gbufferProjectionInverse, dhInverse, near,
		handSupported, hasDh, dhSsr, int(OMNI_RAYTRACE_QUALITY), int(OMNI_RAYTRACE_REFINEMENT_STEPS), OMNI_RAYTRACE_ZDIFF_THRESHOLD); // 一次调用完成追踪。
}

#if defined OMNI_NETHER
// 下界反射：没有天空盒回退，命中取屏幕颜色、没命中留黑，再叠一段 `NetherFog`（来自 `world-1/composite2.fsh`）。
// 调用前提：`NetherFog` 由 `effects/world/nether.glsl` 提供，绘制主体需在本文件之前引入它。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记，下界不使用。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif
	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif

	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离，写进返回的 a 通道供后续滤波使用。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面，命中距离记零。
	}else{ // 粗糙面：按可见法线抽样。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样一个可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪。
	}

	reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 命中点或默认点取屏幕颜色。

	reflection = mix(vec3(0.0), reflection, float(hit)); // 没命中就留黑。

	float dist = length(viewPos); // 表面到相机的距离。
	float rDist = 80.0; // 反射射线的默认长度。

	if(hit){ // 命中几何时按命中点算这段空气长度。
		float hitDepth = textureLod(depthtex0, screenPos.xy, 0.0).x; // 命中点深度。
		vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, hitDepth); // 还原命中点视空间位置。
		rDist = dist + distance(hitPos, viewPos); // 表面到相机的距离加命中点距离。

		if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面把命中距离写进 a 通道。
	}

	reflection += NetherFog(vec2(rDist, dist)) / MAIN_OUTPUT_FACTOR; // 补一段下界雾。

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#elif defined OMNI_END
// 末地反射：天空盒回退换成末地天空，命中距离那段补 `EndFog`（来自 `world1/composite2.fsh`）。
// 调用前提：`ComputeFakeSkyReflectionEnd` 与 `EndFog` 由 `effects/world/end.glsl` 提供，绘制主体需在本文件之前引入它。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif

	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif

	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面。
	}else{ // 粗糙面：按可见法线抽样。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 切向参考轴。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪。
	}

	reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 命中点或默认点取屏幕颜色。

	vec3 rayDirectionWorld = mat3(gbufferModelViewInverse) * rayDir; // 反射方向转到世界空间。
	vec3 skyReflection = vec3(0.0); // 天空回退颜色。
	if(!totalInternalReflection && isEyeInWater == 0){ // 空中且非全反射才用末地天空。
		skyReflection = ComputeFakeSkyReflectionEnd(rayDirectionWorld, isSmooth); // 末地天空回退。
		skyReflection *= saturate((dot(normal, gbufferModelView[1].xyz) + 0.7) * 2.0) * 0.75 + 0.25; // 朝上的面接更多天空。
	}
	if(totalInternalReflection) skyReflection = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 全反射直接取当前场景色。

	reflection = mix(skyReflection, reflection, float(hit)); // 命中则用屏幕颜色，否则用天空。

	float dist = length(viewPos); // 表面到相机的距离。
	float rDist = 1e10; // 反射射线在空气里的长度。

	if(hit){ // 命中几何时按命中点算这段空气长度。
		vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, textureLod(depthtex0, screenPos.xy, 0.0).x); // 还原命中点。
		rDist = distance(hitPos, viewPos); // 命中点到表面的距离。

		if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面写命中距离。
	}

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	rDist = max(min(min(rDist + dist, farDist), 512.0) - dist, 0.0); // 空气段长度裁到可视范围内。

	if (rDist > 0.0) reflection += EndFog(rDist, rayDirectionWorld) / MAIN_OUTPUT_FACTOR; // 有空气段才补末地雾。

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#else // 主世界
// 反射主函数（写三号画面）：追踪反射方向，命中取屏幕颜色，没命中取天空回退，再叠反射里的体积雾与地表散射。
// 输入是表面位置、世界位置、视线方向、法线、深度、底色、材质、天光等级、是否手部、是否光滑面与高光强度；输出三号画面的反射数据。
// 为什么全反射像素直接取当前场景色：发生全反射时表面看不到外面的东西，取自身颜色才不会出现黑洞。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记写在二号画面之外的一号画面 a 通道。
	skylight = smoothstep(0.3, 0.8, skylight); // 天光等级重整到零到一。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif

	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标，保证与深度同源。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif


	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离，写进返回的 a 通道供后续滤波使用。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射，方向就是反射方向。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长，随深度与视线倾斜收紧。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面，命中距离记零。
	}else{ // 粗糙面：按可见法线抽样，反射方向带散射。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基，第三列是法线。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样一个可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪，最小步长更小。
	}

	vec3 rayWorldDir = mat3(gbufferModelViewInverse) * rayDir; // 反射方向转到世界空间，供天空与雾使用。


	bool isSky = true; // 命中点是不是天空，默认按天空处理。

	float highlightGGX = 0.0; // 太阳高光，只在光滑天空像素上出现。

	if(hit){ // 命中几何时取该处的场景色。
		isSky = floor(textureLod(colortex5, screenPos.xy, 0.0).b * 255.0) < 0.5; // 材质编号小于零点五的当作天空。
		reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 读回该处曲线编码的颜色。
	}

	if(isSky && isSmooth && highlightStrength > 0.0) highlightGGX = SpecularGGX(normal, -viewDir, shadowVector, 0.002, 0.06) * highlightStrength; // 光滑天空像素加一个太阳镜面高光。

	if(!hit){ // 没命中时用天空回退。
		if(totalInternalReflection){ // 全反射。
			reflection = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 直接取当前场景色。
		}else if (isEyeInWater == 0 && skylight > 0.0){ // 不在水下且有一定天光时才用天空。
			reflection = ComputeFakeSkyReflection(rayWorldDir); // 取天空盒反射。
			float skylightFalloff = skylight * (saturate((dot(normal, gbufferModelView[1].xyz) + 0.7) * 2.0) * 0.75 + 0.25); // 朝上的面接更多天光。
			reflection *= skylightFalloff; // 按天光衰减反射。
			highlightGGX *= skylightFalloff; // 高光同样衰减。
		}
	}

	#if defined OMNI_MOON_TEXTURE // 用月亮贴图时高光偏月光，否则偏当前直射光。
		reflection += colorSunlight * highlightGGX; // 叠加太阳高光。
	#else
		reflection += colorShadowlight * highlightGGX; // 叠加直射高光。
	#endif

	#if OMNI_VOXEL_REFLECTION && defined IRIS_FEATURE_CUSTOM_IMAGES // 屏幕空间没命中时再用体素反射补一次。
		if(!hit && !totalInternalReflection && isEyeInWater == 0){ // 空中且屏幕空间没命中才追踪体素。
			vec3 voxelHitWorld; // 体素命中的相机相对世界位置，用来把反射雾的雾段算到真实命中点。
			vec4 voxelHit = omniVoxelReflection(worldPos, rayWorldDir, normal, voxelHitWorld); // 世界空间追踪体素图。
			if(voxelHit.a >= 0.0){ // `a` 不为负就是命中。
				reflection = voxelHit.rgb; // 用体素里存下的方块颜色作为反射。
				hit = true; // 当作命中几何，后面的雾按命中处理。
				isSky = false; // 命中的不是天空。
				hitDist = voxelHit.a; // 归一化命中距离，供反射滤波使用。
				screenPos = ScreenPos_From_ViewPos(mat3(gbufferModelView) * voxelHitWorld); // 把命中点投回屏幕，反射雾、地表散射与雾照明就按这段距离罩住体素反射，而不是当成零长度。
			}
		}
	#endif


	#if (defined OMNI_LANDSCATTERING && (defined OMNI_LANDSCATTERING_REFLECTION || defined DISTANT_HORIZONS)) || (defined OMNI_VFOG && defined OMNI_VFOG_REFLECTION) // 反射里要不要补体积雾与地表散射。
		float dist = length(viewPos); // 表面到相机的距离。
		float rDist = 1e10; // 反射射线在空气里的长度，默认极远。

		if(hit){ // 命中几何时按命中点算这段空气的长度。
			if(!isSky){ // 命中实心几何。
				vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, screenPos.z); // 还原命中点视空间位置。
				rDist = distance(hitPos, viewPos); // 命中点到表面的距离。
			}

			if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面把命中距离写进 a 通道供滤波。
		}

		if (isEyeInWater == 1) skylight = 1.0; // 水下天光按满值，水下雾才能正常出现。

		if (skylight > 0.0){ // 有天光才补空气里的散射。
			#ifdef DISTANT_HORIZONS
				float farDist = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
				#ifdef OMNI_DH_LIMIT_VFOG_DIST
					farDist = min(2048.0, farDist); // 限制雾距离上限。
				#endif
			#else
				float farDist = far * 1.4; // 没有远景时用近景远裁剪面估计。
			#endif
			rDist = max(min(rDist + dist, farDist) - dist, 0.0); // 空气段长度裁到可视范围内。


			if (rDist > 0.0){ // 有空气段才补雾。
				reflection *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾函数按此单位工作。
				vec3 volumetricReflection = reflection; // 在副本上补散射，最后按天光混合。

				vec3 endPos = worldPos + rayWorldDir * rDist; // 反射射线的终点世界位置。

			
				#ifdef OMNI_LANDSCATTERING // 地表大气散射。
					#ifdef DISTANT_HORIZONS
						LandAtmosphericScattering(volumetricReflection, rDist, worldPos, endPos, rayWorldDir, isSky); // 有远景时一律补散射。
					#else
						#ifdef OMNI_LANDSCATTERING_REFLECTION
							LandAtmosphericScattering(volumetricReflection, rDist, worldPos, endPos, rayWorldDir, isSky); // 只在开启反射时补散射。
						#endif
					#endif
				#endif
			

				#ifdef OMNI_VFOG // 体积雾。
					#ifdef OMNI_VFOG_REFLECTION
						float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾的光照遮蔽使用。

						#ifdef OMNI_UNDERWATER_VFOG
							if (isEyeInWater == 1) volumetricReflection += UnderwaterVolumetricFog(worldPos, endPos, rayWorldDir, globalCloudShadow); // 水下补水下体积雾。
						#endif

						float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
						#ifndef OMNI_VFOG_IGNORE_WORLDTIME // 不忽略时间时按白天夜晚调整。
							#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系降水情况。
								fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7));
							#else
								fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 关闭局部降水时只看整体湿润度。
							#endif
						#endif
						
						float fogTransmittance = 1.0; // 透射率占位，本处不返回。
						if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(volumetricReflection, worldPos, endPos, rayWorldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 补体积雾。
					#endif
				#endif


				reflection = mix(reflection, volumetricReflection, skylight); // 按天光在原始反射与补雾反射之间混合。
				reflection /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
			}
		}
	#else // 不需要补雾时只算命中距离供滤波。
		if(hit && !isSmooth){ // 粗糙面命中几何。
			vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, textureLod(depthtex0, screenPos.xy, 0.0).x); // 用含半透明深度还原命中点。
			float rDist = distance(hitPos, viewPos); // 命中点到表面的距离。

			hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 写进 a 通道供滤波。
		}
	#endif

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#endif // 反射主函数分支结束。
#endif // composite2 段结束。

// --- composite5：把三号画面的反射合并进场景色 ---
#ifdef OMNI_COMPOSITE5_PASS
// 材质提供 `Material` 结构，反射合并要读它的金属度与反射强度。
#include "/effects/ground/material.glsl"

// 反射合并：把三号画面的反射按菲涅耳与金属度混合进底色。
// 输入是场景色、视线方向、法线、底色、水的吸收与材质；就地把反射混进场景色。
// 为什么主世界与下界末地共用一份签名：主世界给水吸收留权重，下界末地没有水吸收这一项，数值差异留在函数体内用 `OMNI_OVERWORLD` 分支处理，调用点保持同一个。
// 为什么用 `length(color)` 与 `length(reflection)` 再补一项：亮度差大时补一点反射，金属与高亮边缘不会突黑。
void CalculateSpecularReflections(inout vec3 color, vec3 viewDir, vec3 normal, vec3 albedo, float waterAbsorption, Material material){

	vec3 reflection = CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb); // 读三号画面的反射颜色并换回线性。

	#ifndef OMNI_NETHER // 下界没有全反射标记这一套。
		bool notTotalReflection = texelFetch(colortex1, texelCoord, 0).a < 0.5; // 一号画面 a 通道小于零点五表示不是全反射像素。
	#else
		bool notTotalReflection = true; // 下界没有全反射标记，一律按普通像素处理。
	#endif

	if (notTotalReflection){ // 先算好布尔量再走一条完整的 `if`，避免判断括号被预处理指令切开。

		reflection *= mix(vec3(1.0), albedo, vec3(material.metalness)); // 金属面用底色给反射染色。

		vec3 l = normalize(reflect(viewDir, normal) + normal * material.roughness); // 反射方向按粗糙度偏一点，得到更亮的反射。
		vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
		float LdotH = saturate(dot(l, h)); // 反射与半程夹角。
		float NdotL = saturate(dot(normal, l)); // 反射方向的入射余弦。
		float NdotV = saturate(dot(normal, -viewDir)); // 视线方向的入射余弦。

		float specular = F_Schlick(LdotH, material.f0, 1.0); // 菲涅耳。
		specular *= V_Schlick(NdotL, NdotV + 0.8, material.roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
		specular *= material.reflectionStrength; // 乘材质允许的反射强度。

		specular = mix(specular, 1.0, material.metalness); // 金属面反射权重拉满。

		vec3 temp = color; // 记下原底色，金属面要再加一份。

		float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
		diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
		specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。

		#ifdef OMNI_OVERWORLD
			color = mix(color, reflection, saturate(specular * waterAbsorption)); // 主世界按水吸收缩反射权重。
			color += temp * (material.metalness * waterAbsorption); // 金属面再加一份底色。
		#else
			color = mix(color, reflection, saturate(specular)); // 下界末地按反射权重混合。
			color += temp * material.metalness; // 金属面再加一份底色。
		#endif
	}else{ // 全反射像素。
		color = reflection; // 直接取反射颜色。
	}
}
#endif // composite5 段结束。

#endif // 文件守卫结束。
