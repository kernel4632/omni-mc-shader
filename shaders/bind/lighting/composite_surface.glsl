/*
合成零号表面光照：给不透明表面算完整光照，是 iterationT `composite.fsh` 主世界程序的算法体一比一移植，
下界与末地的同名版本放在同效果的独立文件里。
职责：主世界读回表面数据与延迟阶段存下的全局光，叠天光、直射阳光、可变半影阴影、屏幕空间阴影、高光与自发光，
    最后编码写回一号画面；本文件只做维度分派，并保留主世界专用的两个辅助函数与主世界光照本体。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE0_PASS` 分支先声明维度相关采样器并引入所需效果文件，
    再引入本文件，最后 `void main(){ CompositeSurfaceLighting(); }` 调用。
可复制示例：`CompositeSurfaceLighting();`（要求调用方已提供 `texelCoord`、`texCoord`、光色 varying、
    `shadowtex0`、`shadowtex1`、`dhDepthTex1` 等全局量，见 `rendering/composite_shared.glsl`）。
设计原因与取舍：三个维度共用一个函数名，靠 `OMNI_NETHER`、`OMNI_END` 选择分支，与原程序按维度目录分文件等价；
    下界、末地两份随维度变化的算法体分别移到 `effects/lighting/composite_surface_nether.glsl`
    与 `effects/lighting/composite_surface_end.glsl`，本文件只留主世界实现与维度分派。
*/
#ifndef OMNI_COMPOSITE_SURFACE_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_SURFACE_INCLUDED // 置上标记，后续再次引用直接跳过。

#if defined OMNI_NETHER // 下界：没有太阳，光照来自 `NetherLighting` 与雾色，不接收全局光与阴影。
// 下界不透明表面光照在独立文件里。
#include "/bind/lighting/composite_surface_nether.glsl"
#elif defined OMNI_END // 末地：没有太阳贴图，光色用固定黑体色，天空像素画吸积盘与行星。
// 末地不透明表面光照在独立文件里。
#include "/bind/lighting/composite_surface_end.glsl"
#else // 主世界：完整光照，含全局光、可变半影阴影与屏幕空间阴影。
// 无光底光与环境光：先给一点随法线朝向的无光底光，再叠天光照明与水体染色。
vec3 CompositeAmbientLight(vec3 worldNormal, float skylight, float cloudShadow, vec3 waterTint){
	#ifdef OMNI_CAVE_MODE // 洞穴模式：极暗底光，避免洞穴里被补到不该有的亮。
		vec3 ambient = vec3(0.83, 0.87, 1.0) * ((worldNormal.y * 0.25 + 0.75) * max(OMNI_NOLIGHT_BRIGHTNESS, 0.00003)); // 洞穴极暗底光。
	#else
		vec3 ambient = vec3(0.86, 0.94, 1.19) * ((worldNormal.y * 0.3 + 0.8) * OMNI_NOLIGHT_BRIGHTNESS); // 常规无光亮度。
	#endif
	return ambient + SkyLighting(worldNormal, skylight, cloudShadow) * waterTint; // 叠天光照明并按水色染色。
}
// 输出写入：把底色、金属掩码、高光与额外自发光叠好后编码写进一号画面。
void WriteOverworldSurface(vec3 albedo, float metalnessMask, vec3 specularHighlight, float lightning, vec3 worldPos, float skylight, inout vec3 finalComposite){
	finalComposite *= albedo; // 乘底色。
	finalComposite *= metalnessMask; // 乘非金属掩码。
	finalComposite += specularHighlight; // 叠高光。
	finalComposite += vec3(1.0) * lightning; // 闪电自发光。
	finalComposite = omniLightning(finalComposite, worldPos, skylight); // Omni 额外功能：真实闪电事件照亮附近表面。
	finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。
	compositeOutput1 = vec4(finalComposite, 0.0); // 写回一号画面。
}
// 主世界不透明表面光照：无光底光、全局光、遮蔽、阴影、高光与自发光（来自 `composite.fsh`）。
void CompositeSurfaceLighting(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	compositeOutput1 = texelFetch(colortex1, texelCoord, 0); // 默认原样保留场景颜色。

	if (materialMaskSolid.sky < 0.5){ // 只处理有几何的像素，天空留给延迟阶段。
		FixParticleMask(materialMaskSolid, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度，避免读到自己后面的方块。

		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

		#ifdef DISTANT_HORIZONS
			bool isDH = gbuffer.depthL == 1.0; // 标记远景像素。
			if (isDH){ // 天空像素改读远景深度。
				gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
				viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影还原位置。
			}
		#endif

		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
		vec3 viewDir = normalize(viewPos); // 视线方向。
		vec3 worldDir = normalize(worldPos); // 世界方向。
		vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

		#if defined OMNI_ENABLE_PBR && OMNI_PUDDLE_MODE == 2 // 仅水洼模式：把 Eclipse `applyPuddles` 的水洼表面接到已解出的材质上。
			// 手、玩家与各种实体不做水洼，照 Eclipse 的 `!hand && !entities`；水与冰在半透明层，不在这个分支里。
			bool isPuddleBlocked = materialMaskSolid.hand + materialMaskSolid.entityPlayer + materialMaskSolid.entitiesLitHigh + materialMaskSolid.entitiesLitMedium + materialMaskSolid.entitiesLitLow + materialMaskSolid.entitiesSnow > 0.5; // 是否是要排除的实体面。
			if (!isPuddleBlocked)
				OmniPuddleSurface(worldNormal, gbuffer.albedo, gbuffer.material.roughness, gbuffer.material.f0, gbuffer.lightmapL.g, worldPos); // 用 `OMNI_PUDDLE_SIZE` 决定的水洼覆盖改写水洼表面的法线、粗糙度与底色。
		#endif // 默认模式一不执行，画面与原来一致。

		#ifdef DISTANT_HORIZONS
			float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
		#else
			float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
		#endif
		float opaqueDist = gbuffer.depthL < 1.0 ? length(viewPos) : farDist; // 表面到相机的距离，天空按远裁剪面。

		#ifdef OMNI_VOLUMETRIC_CLOUDS
			#ifdef OMNI_CLOUD_SHADOW
				float cloudShadow = CloudShadowFromTex(worldPos, worldShadowVector); // 从云影贴图取这一点的云影。
			#else
				float cloudShadow = 1.0 - wetness * OMNI_RAIN_SHADOW; // 没有云影贴图时按雨天估一个底值。
			#endif
		#else
			float cloudShadow = 1.0; // 没有体积云时云影不生效。
		#endif

		vec3 sunlightMult = colorShadowlight * (OMNI_SUNLIGHT_INTENSITY * mix(cloudShadow, 1.0, 0.03 - wetness * 0.015)); // 直射光乘云影与强度。

		#ifdef OMNI_CAVE_MODE
			sunlightMult *= mix(1.0, 0.1, eyeBrightnessZeroSmooth); // 洞穴模式按看不到天空的程度压直射。
		#endif

		vec3 waterTint = vec3(1.0); // 水体染色，默认不染。

		#ifdef OMNI_UNDERWATER_FOG
			if (isEyeInWater == 1) waterTint = vec3(0.55, 0.75, 1.0) / max(3.0, opaqueDist * 0.1 * OMNI_WATER_FOG_DENSITY); // 水下按距离与水雾密度染偏蓝。
			sunlightMult *= waterTint; // 直射光同步染色。
		#endif

		#ifndef OMNI_CAUSTICS
			if (materialMask.water > 0.5 || isEyeInWater == 1) sunlightMult *= 0.75; // 不开焦散时水下水面的直射压一点。
		#endif

		gbuffer.material.scattering *= saturate(1.0 - materialMaskSolid.leaves - materialMaskSolid.grass); // 叶片与草之外的表面不做透光。

		#ifdef DISTANT_HORIZONS
			#ifdef OMNI_DH_SHADOW
				materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.65 + 0.35; // 有远景阴影时叶片透光按距离收敛。
			#else
				materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0 - float(isDH) * 1e10) * 0.65 + 0.35; // 没有远景阴影时远景叶子不透光。
			#endif
			#if !OMNI_DH_SSS // 关闭远景透光时，远景叶片与雪的透光比重归零，只影响远景像素。
				materialMaskSolid.leaves *= saturate(1.0 - float(isDH));
			#endif
		#else
			materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.6 + 0.4; // 叶片透光随距离收敛。
		#endif

		worldNormal = normalize(mix(worldNormal, vec3(0.0, 1.0, 0.0), materialMaskSolid.grass * 0.49)); // 草的法线朝上拉，减少杂乱。

		vec3 finalComposite = CompositeAmbientLight(worldNormal, gbuffer.lightmapL.g, cloudShadow, waterTint); // 无光底光加天光照明。

		vec4 gi = compositeOutput1; // 一号画面里存着延迟阶段算好的全局光与遮蔽。
		gi = mix(gi, vec4(0.0, 0.0, 0.0, 1.0), materialMask.particle); // 粒子不接收全局光。

		vec3 rsm = CurveToLinear(gi.rgb); // 全局光解码回线性。
		rsm *= sunlightMult * (8.0 * OMNI_GI_BRIGHTNESS); // 乘直射与全局光亮度。
		#ifdef OMNI_SUNLIGHT_LEAK_FIX
			#ifdef OMNI_GI_SKYLIGHT_FALLOFF
				rsm *= saturate(gbuffer.lightmapL.g * 4.0 + float(isEyeInWater == 1)); // 只在天光充足或水下保留全局光。
			#else
				rsm *= saturate(gbuffer.lightmapL.g * 1e3 + float(isEyeInWater == 1)); // 更严格地只留天光像素。
			#endif
		#endif

		// 先把“这个像素要不要接收全局光”算成一个布尔量，避免判断条件被预处理指令切成分开的几段。
		bool applyGi = true; // 默认接收全局光。
		#ifdef OMNI_DISABLE_HAND_GI
			applyGi = applyGi && materialMaskSolid.hand < 0.5; // 开启排除手时，手不接收全局光。
		#endif
		#ifdef OMNI_DISABLE_PLAYER_GI
			applyGi = applyGi && materialMaskSolid.entityPlayer < 0.5; // 开启排除玩家时，玩家不接收全局光。
		#endif
		if (applyGi)
			finalComposite += rsm; // 通过手与玩家的排除条件后叠全局光。

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

		vec3 blockLighting = BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSolid); // 原版方块光。
		#if OMNI_LPV_ENABLED // Omni 额外功能：用体积彩色光替换方块光；缺少自定义图像能力时整段不编译。
			#ifdef IRIS_FEATURE_CUSTOM_IMAGES
			blockLighting = omniLpvApply(blockLighting, worldPos, worldNormal); // 按体积边缘淡出把体积光混进来。
			#endif
		#endif
		finalComposite += blockLighting; // 叠方块光（可能已被体积光替换）。
		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSolid); // 叠资源包自发光。

		float sunlight = Fd_Burley(worldNormal, -worldDir, worldShadowVector, gbuffer.material.roughness); // 阳光漫反射项。

		float sunlightTrans = saturate(materialMaskSolid.leaves * 3.0) * 0.25 + materialMask.particle * 0.4 + materialMaskSolid.grass * 0.15; // 薄片透光占比。
		sunlight = mix(sunlight, 0.6, sunlightTrans); // 薄片把阳光漫反射往固定值拉。
		gbuffer.parallaxShadow = saturate(gbuffer.parallaxShadow + sunlightTrans * 1e10); // 薄片视差自阴影放宽。

		vec3 shadow = vec3(1.0); // 阳光阴影可见度，初值全亮。

		#ifdef OMNI_SUNLIGHT_LEAK_FIX
			float occludedWater = gbuffer.waterMask * materialMask.stainedGlass; // 被玻璃挡住的水。
			float lightMask = saturate(gbuffer.lightmapL.g * mix(1e4, 1.0, occludedWater) + float(isEyeInWater == 1)); // 泄漏修正遮罩。
			shadow *= lightMask; // 阴影先按遮罩压。
		#endif

		vec3 specularHighlight = vec3(0.0); // 太阳高光，初值零。
		vec3 sss = vec3(0.0); // 次表面散射，初值零。

		if ((sunlight + gbuffer.material.scattering) * shadow.x > 0.0){ // 有阳光或透光才算阴影。
			shadow *= VariablePenumbraShadow(worldPos, worldNormal, sunlight, gbuffer.albedo, gbuffer.material.scattering, materialMaskSolid, sss); // 可变半影阴影并带回透光。
			#ifdef OMNI_SUNLIGHT_LEAK_FIX
				sss *= lightMask; // 透光同样受泄漏修正遮罩。
			#endif
			finalComposite += sss * sunlightMult; // 叠次表面散射。
		}

		#if OMNI_PARALLAX_MODE > 0
			shadow *= gbuffer.parallaxShadow; // 视差自阴影也压阳光。
		#endif

		float metalnessMask = gbuffer.material.metalness; // 金属度掩码。
		float skylightmap = min(smoothstep(0.3, 0.8, gbuffer.lightmapL.g), float(isEyeInWater == 0)); // 天光等级重整，水下归零。
		metalnessMask *= 0.1 * skylightmap + 0.9; // 天光越低金属效果越弱。
		metalnessMask = 1.0 - metalnessMask * 0.985; // 翻转成非金属掩码。

		if (any(greaterThan(sunlight * shadow, vec3(0.0)))){ // 还有阳光的像素才继续。
			#ifdef OMNI_SCREEN_SPACE_SHADOWS
				// 先把“这个像素是否参与屏幕空间阴影”算成一个布尔量，避免判断条件被预处理指令切成分开的几段。
				float screenSpaceOccluders = materialMaskSolid.leaves + materialMaskSolid.hand + materialMaskSolid.entitiesSnow; // 不参与屏幕空间阴影的薄片与手。
				#ifdef OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
					screenSpaceOccluders += materialMaskSolid.entityPlayer; // 玩家也排除时一起计入。
				#endif
				bool applyScreenSpaceShadow = screenSpaceOccluders < 1.0; // 这些薄片占比不满才算屏幕空间阴影。
				#if OMNI_PARALLAX_MODE == 0
					applyScreenSpaceShadow = applyScreenSpaceShadow && gbuffer.parallaxShadow > 0.0; // 没开视差时还要看视差自阴影。
				#endif
				if (applyScreenSpaceShadow)
					shadow *= mix(ScreenSpaceShadow(viewPos, viewDir, gbuffer.normalL, materialMaskSolid, shadowVector), 1.0, saturate(materialMaskSolid.leaves * 1.67 - 0.67)); // 屏幕空间阴影，叶片按比例削弱。
			#endif

			#ifdef OMNI_CAUSTICS
				if (materialMask.water > 0.5 || isEyeInWater == 1)
					shadow *= CalculateWaterCaustics(worldPos, worldShadowVector); // 水面焦散。
			#endif

			shadow *= sunlightMult; // 阴影乘直射光。

			finalComposite += shadow * (sunlight * metalnessMask); // 叠漫反射阳光。

			if (materialMask.water + materialMask.ice < 0.5){ // 水与冰不做这层高光。
				float highlightGGX = SpecularGGX(gbuffer.normalL, -viewDir, shadowVector, clamp(gbuffer.material.roughness, 0.0015, 0.9), gbuffer.material.f0); // GGX 高光。
				highlightGGX *= saturate(4.0 - gbuffer.material.roughness * 3.5); // 光滑面高光更强。
				highlightGGX *= 0.07 - materialMaskSolid.grass * 0.035; // 整体很弱，草更弱。
				specularHighlight = mix(vec3(1.0), gbuffer.albedo, vec3(gbuffer.material.metalness)) * shadow * highlightGGX; // 金属面高光带底色。
			}
		}

		WriteOverworldSurface(gbuffer.albedo, metalnessMask, specularHighlight, materialMaskSolid.lightning, worldPos, gbuffer.lightmapL.g, finalComposite); // 统一写出零号画面。
	}
}
#endif // 维度分支结束。
#endif // 文件守卫结束。
