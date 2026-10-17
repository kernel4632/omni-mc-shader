/*
末地不透明表面光照：用固定色温太阳光、全局光与可变半影阴影照亮末地表面，天空像素画吸积盘与行星，
是 iterationT `world1/composite.fsh` 该段算法的一比一移植。
职责：读回表面数据，叠行星相位控制的太阳光、全局光、遮蔽、阴影、高光与自发光，天空交给吸积盘与行星，最后写回一号画面。
调用位置：`effects/lighting/composite_surface.glsl` 在 `OMNI_END` 分支引入本文件，绘制主体再调用 `CompositeSurfaceLighting();`。
可复制示例：`CompositeSurfaceLighting();`（要求调用方已提供 `texelCoord`、`texCoord`、光色 varying、
    `shadowtex0`、`shadowtex1`、`dhDepthTex1` 等全局量，见 `rendering/composite_shared.glsl`）。
设计原因与取舍：末地没有太阳贴图，光色用 `Blackbody(6000.0)`，天空由 `BlackHole_AccretionDisc_Stars` 与 `PlanetEnd2` 直接画出；
    与主世界同用一个函数名，靠上级文件的分支二选一，拆出本文件只为让每个维度一份逻辑更短、更好找。
*/
#ifndef OMNI_COMPOSITE_SURFACE_END_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_SURFACE_END_INCLUDED // 置上标记，后续再次引用直接跳过。

// 末地不透明表面光照：固定色温太阳光、行星相位、全局光与可变半影阴影，天空留给吸积盘与行星（来自 `world1/composite.fsh`）。
void CompositeSurfaceLighting(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度。

	if (materialMask.water > 0.5){ // 末地水面按光滑非金属处理。
		gbuffer.material.roughness = 1.0; // 粗糙度拉满。
		gbuffer.material.metalness = 0.0; // 去掉金属度。
	}

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		bool isDH = gbuffer.depthL == 1.0; // 标记远景像素。
		if (isDH){ // 天空像素改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldDir = normalize(worldPos); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
	#endif
	float opaqueDist = gbuffer.depthL < 1.0 ? length(viewPos) : farDist; // 表面到相机的距离，天空按远裁剪面。

	vec3 colorSunLight = Blackbody(6000.0); // 末地用固定色温的太阳光色。
	vec3 finalComposite = vec3(0.0); // 累积的末地表面颜色。

	if (materialMaskSoild.sky < 0.5){ // 只处理有几何的像素。
		vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

		#ifdef DISTANT_HORIZONS
			#ifdef OMNI_DH_SHADOW
				materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.65 + 0.35; // 有远景阴影时叶片透光按距离收敛。
			#else
				materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0 - float(isDH) * 1e10) * 0.65 + 0.35; // 没有远景阴影时远景叶子不透光。
			#endif
			#ifndef OMNI_DH_SSS // 关闭远景透光时，远景叶片与雪的透光比重归零，只影响远景像素。
				materialMaskSoild.leaves *= saturate(1.0 - float(isDH));
			#endif
		#else
			materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.6 + 0.4; // 叶片透光随距离收敛。
		#endif

		worldNormal = normalize(mix(worldNormal, vec3(0.0, 1.0, 0.0), materialMaskSoild.grass * 0.49)); // 草的法线朝上拉。
		gbuffer.material.scattering *= saturate(1.0 - materialMaskSoild.leaves - materialMaskSoild.grass); // 叶片与草之外的表面不做透光。

		finalComposite += vec3(colorSunLight * 0.005) * ((worldNormal.y * 0.35 + 0.75) * (dot(worldSunVector, worldNormal) * 0.3 + 0.7) * (planetShadow * planetShadow * 0.93 + 0.07)); // 行星相位控制的太阳环境光。

		vec3 sunlightMult = colorSunLight * (0.3 * OMNI_SUNLIGHT_INTENSITY * planetShadow * planetShadow); // 太阳直射按行星相位缩放。

		vec4 gi = texelFetch(colortex1, texelCoord, 0); // 一号画面里存着延迟阶段算好的全局光与遮蔽。
		gi = mix(gi, vec4(0.0, 0.0, 0.0, 1.0), materialMask.particle); // 粒子不接收全局光。

		vec3 rsm = CurveToLinear(gi.rgb); // 全局光解码回线性。
		rsm *= sunlightMult * (7.0 * OMNI_GI_BRIGHTNESS); // 乘直射与全局光亮度。
		finalComposite += rsm; // 叠全局光。

		#ifdef OMNI_GTAO
			#ifdef OMNI_GTAO_MULTIBOUNCE
				vec3 ao = GTAOMultiBounce(gi.a, gbuffer.albedo); // 遮蔽做多弹射补偿。
			#else
				vec3 ao = vec3(gi.a); // 直接用遮蔽值。
			#endif
		#else
			vec3 ao = vec3(1.0); // 不开遮蔽时全亮。
		#endif
		finalComposite *= ao; // 遮蔽乘到颜色上。

		if(heldBlockLightValue + heldBlockLightValue2 > 0.0)
			finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5); // 叠手持光源。

		finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSoild); // 叠方块光。
		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSoild); // 叠资源包自发光。

		float sunlight = Fd_Burley(worldNormal, -worldDir, worldShadowVector, gbuffer.material.roughness); // 阳光漫反射项。

		float sunlightTrans = saturate(materialMaskSoild.leaves * 3.0) * 0.25 + materialMask.particle * 0.4 + materialMaskSoild.grass * 0.15; // 薄片透光占比。
		sunlight = mix(sunlight, 0.6, sunlightTrans); // 薄片把阳光漫反射往固定值拉。
		gbuffer.parallaxShadow = saturate(gbuffer.parallaxShadow + sunlightTrans * 1e10); // 薄片视差自阴影放宽。

		vec3 shadow = vec3(1.0); // 阳光阴影可见度，初值全亮。
		vec3 specularHighlight = vec3(0.0); // 太阳高光，初值零。
		vec3 sss = vec3(0.0); // 次表面散射，初值零。

		if (sunlight + gbuffer.material.scattering > 0.0) // 有阳光或透光才算阴影。
			shadow *= VariablePenumbraShadow(worldPos, worldNormal, sunlight, gbuffer.albedo, gbuffer.material.scattering, materialMaskSoild, sss); // 可变半影阴影并带回透光。

		#if OMNI_PARALLAX_MODE > 0
			shadow *= gbuffer.parallaxShadow; // 视差自阴影也压阳光。
		#endif

		if (any(greaterThan(sunlight * shadow, vec3(0.0)))){ // 还有阳光的像素才继续。
			#ifdef OMNI_SCREEN_SPACE_SHADOWS
				// 先把“这个像素是否参与屏幕空间阴影”算成一个布尔量，避免判断条件被预处理指令切成分开的几段。
				float screenSpaceOccluders = materialMaskSoild.leaves + materialMaskSoild.hand + materialMaskSoild.entitiesSnow; // 不参与屏幕空间阴影的薄片与手。
				#ifdef OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
					screenSpaceOccluders += materialMaskSoild.entityPlayer; // 玩家也排除时一起计入。
				#endif
				bool applyScreenSpaceShadow = screenSpaceOccluders < 1.0; // 这些薄片占比不满才算屏幕空间阴影。
				#if OMNI_PARALLAX_MODE == 0
					applyScreenSpaceShadow = applyScreenSpaceShadow && gbuffer.parallaxShadow > 0.0; // 没开视差时还要看视差自阴影。
				#endif
				if (applyScreenSpaceShadow)
					shadow *= mix(ScreenSpaceShadow(viewPos, viewDir, gbuffer.normalL, materialMaskSoild, shadowVector), 1.0, saturate(materialMaskSoild.leaves * 1.67 - 0.67)); // 屏幕空间阴影，叶片按比例削弱；方向传视空间的 shadowVector，与原程序一致。
			#endif

			#ifdef OMNI_CAUSTICS
				if (materialMask.water > 0.5 || isEyeInWater == 1)
					shadow *= CalculateWaterCaustics(worldPos, worldShadowVector); // 水面焦散。
			#endif

			shadow *= sunlightMult; // 阴影乘直射光。

			finalComposite += sunlight * shadow; // 叠漫反射阳光。

			if (materialMask.water + materialMask.ice < 0.5){ // 水与冰不做这层高光。
				float highlightGGX = SpecularGGX(gbuffer.normalL, -viewDir, shadowVector, clamp(gbuffer.material.roughness, 0.0015, 0.9), gbuffer.material.f0); // GGX 高光。
				highlightGGX *= saturate(4.0 - gbuffer.material.roughness * 3.5); // 光滑面高光更强。
				highlightGGX *= 0.07 - materialMaskSoild.grass * 0.035; // 整体很弱，草更弱。
				specularHighlight = mix(vec3(1.0), gbuffer.albedo, vec3(gbuffer.material.metalness)) * shadow * highlightGGX; // 金属面高光带底色。
			}
		}
		finalComposite += sss * sunlightMult; // 叠次表面散射。

		finalComposite *= gbuffer.albedo; // 乘底色。

		finalComposite *= 1.0 - gbuffer.material.metalness * 0.75; // 非金属整体压一点。

		finalComposite += specularHighlight; // 叠高光。

		#ifdef OMNI_END_ISLAND_LIGHT
			// 末地主岛光源：按到 (0,190,0) 的距离与夹角额外照亮附近表面并给高光；默认关闭时整段不编译，画面与原来一致。
			finalComposite += EndIslandLighting(worldPos, worldNormal, worldDir, gbuffer.albedo, gbuffer.material.roughness, gbuffer.material.f0, gbuffer.material.metalness); // 叠主岛光源。
		#endif
	}

	worldDir = (isEyeInWater == 1 && materialMask.water > 0.5) ? refract(worldDir, normalize((gbufferModelViewInverse * vec4(gbuffer.normalW, 0.0)).xyz), WATER_REFRACT_IOR) : worldDir; // 水下看水面时折射世界方向。

	if (materialMaskSoild.sky > 0.5){ // 天空像素画末地天空。
		finalComposite = vec3(0.0); // 清空。

		BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector); // 吸积盘与星空。

		PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector); // 行星与光环。
	}

	float totalInternalReflection = 0.0; // 全反射标记，写进一号画面透明通道。
	if (length(worldDir) < 0.5){ // 折射方向退化说明发生全反射。
		finalComposite = vec3(0.0); // 全反射看不到外面。
		totalInternalReflection = 1.0; // 记录发生全反射。
	}

	finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

	compositeOutput1 = vec4(finalComposite, totalInternalReflection); // 写回一号画面。
}
#endif // 文件守卫结束。
