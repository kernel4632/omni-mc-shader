/*
合成五号场景最终合成：折射、彩色玻璃吸收、合并反射、雾、雨、选择框与镜头光斑，是 iterationT `composite5.fsh` 及两个维度版本的算法体一比一移植。
职责：在一号画面颜色上依次做水玻璃冰折射与彩色玻璃吸收、合并三号画面的反射、体积雾与地面散射、雨、原版雾、
    选择框与浦肯野效应，最后编码写回一号画面，并按需把镜头光斑与体积雾泛光写进三号画面。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE5_PASS` 分支引入维度相关效果与反射、颜色、镜头、选择框文件后引入本文件，
    最后 `void main(){ CompositeSceneColor(); }` 调用。
可复制示例：`CompositeSceneColor();`（要求调用方已提供 `texelCoord`、`texCoord`、`sunCoord`、`sunVisibility`、
    `colortex1`、`colortex3`、`compositeOutput1` 与 `compositeOutput3` 等）。
设计原因与取舍：本程序横跨水、反射、雾、雨、选择框、镜头多个效果，按维度分成三段；三段都依赖维度文件，
    所以放在 `effects/world/`。
*/
#ifndef OMNI_COMPOSITE_SCENE_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_SCENE_INCLUDED // 置上标记，后续再次引用直接跳过。

#if defined OMNI_NETHER // 下界：折射与彩色玻璃用下界版，雾用 `NetherFog`。
// 下界场景最终合成（来自 `world-1/composite5.fsh`）。
void CompositeSceneColor(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSoild = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		bool isDH = gbuffer.depthW == 1.0; // 标记远景像素。
		if (isDH){ // 半透明表面是天空像素时改读远景深度。
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}

		if (gbuffer.depthL == 1.0){ // 不透明表面是天空像素时改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSoild = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSoild) + materialMaskSoild.sky * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + materialMask.sky * 1e10, farDist); // 半透明表面距离，天空给很远。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.ice + materialMask.stainedGlass > 0.5) // 冰面与彩色玻璃做折射。
		RefractSampleOnceNether(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist); // 下界折射。

	if (materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
		TransparentAbsorptionNether(color, gbuffer.albedoW); // 下界彩色玻璃吸收。

	if (materialMask.water + materialMask.ice > 0.5 || isEyeInWater == 1) // 水与冰整体染一点冷色。
		color *= vec3(0.5, 0.55, 0.7); // 下界水色。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, 1.0, gbuffer.material); // 合并三号画面的反射，下界不用水吸收。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if(heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	vec4 netherFog = NetherFog(waterDist); // 下界整条视线的雾散射与剩余透射率。
	color = color * netherFog.a + netherFog.rgb; // 先按透射率把被雾挡住的背景压暗，再叠雾散射；体积雾关闭时透射率为一，画面不变。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSoild.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		#ifdef DISTANT_HORIZONS
			if (isDH) gbuffer.depthW = ScreenDepth_From_DHScreenDepth(gbuffer.depthW); // 深度换回近景尺度。
		#endif
		compositeOutput1 = vec4(color.rgb, gbuffer.depthW); // 否则透明通道存深度。
	#endif
}
#elif defined OMNI_END // 末地：折射与彩色玻璃用末地版，雾用 `EndFog`。
// 末地场景最终合成（来自 `world1/composite5.fsh`）。
void CompositeSceneColor(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSoild = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){ // 半透明表面是天空像素时改读远景深度。
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}

		if (gbuffer.depthL == 1.0){ // 不透明表面是天空像素时改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSoild = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSoild) + materialMaskSoild.sky * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + materialMask.sky * 1e10, farDist); // 半透明表面距离，天空给很远。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.water + materialMask.ice + materialMask.stainedGlass > 0.5) // 水、冰与彩色玻璃做折射。
		RefractSampleOnceEnd(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist); // 末地折射。

	if (materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
		TransparentAbsorptionEnd(color, gbuffer.albedoW); // 末地彩色玻璃吸收。

	if (materialMask.water + materialMask.ice > 0.5 || isEyeInWater == 1) // 水与冰整体染一点冷色。
		color *= vec3(0.5, 0.55, 0.7); // 末地水色。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, 1.0, gbuffer.material); // 合并三号画面的反射，末地不用水吸收。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if(heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	color += EndFog(waterDist, worldDir); // 末地整条视线的雾。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSoild.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		compositeOutput1 = vec4(color.rgb, 0.0); // 否则透明通道留零。
	#endif
}
#else // 主世界：体积雾、地面散射、雨与镜头光斑都在这里。
// 主世界场景最终合成（来自 `world0/composite5.fsh`）。
void CompositeSceneColor(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSolid, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSolid = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}
		if (gbuffer.depthL == 1.0){
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSolid = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.4, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSolid) + float(gbuffer.depthL == 1.0) * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + float(gbuffer.depthW == 1.0) * 1e10, farDist); // 半透明表面距离，天空给很远。

	float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
	#ifndef OMNI_VFOG_IGNORE_WORLDTIME
		#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
			fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7)); // 按昼夜与所在群系降水调整。
		#else
			fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 只按昼夜与整体湿润度调整。
		#endif
	#endif

	float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾与光柱使用。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.water + materialMask.ice + materialMask.stainedGlass > 0.5)
		RefractSampleOnce(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist, fogTimeFactor, globalCloudShadow, texCoord, texelCoord); // 水玻璃冰做折射。

	float waterAbsorption = 1.0; // 水的吸收系数。
	if (isEyeInWater == 1) waterAbsorption = saturate(exp2(-waterDist * 0.06 * OMNI_WATER_FOG_DENSITY)); // 水下按距离算吸收。

	if (materialMask.stainedGlass > 0.5)
		TransparentAbsorption(color, gbuffer.albedoW, waterAbsorption); // 彩色玻璃吸收。

	if (gbuffer.material.reflectionStrength > 0.0)
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, waterAbsorption, gbuffer.material); // 合并三号画面的反射。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾与散射按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if (heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	#ifdef DISTANT_HORIZONS
		#ifdef OMNI_DH_LIMIT_VFOG_DIST
			vec3 rayWorldPos = worldDir * min(waterDist, max(float(dhRenderDistance), far) * 1.4); // 雾气射线终点，限制在一百区块内。
		#else
			vec3 rayWorldPos = worldDir * min(length(worldPos) + float(gbuffer.depthW == 1.0) * 1e10, max(float(dhRenderDistance), far) * 1.4); // 不限制时的射线终点。
		#endif
	#else
		vec3 rayWorldPos = worldDir * min(waterDist, far * 1.4); // 没有远景时用近景可视距离。
	#endif

	#ifdef OMNI_LANDSCATTERING
		LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5); // 地面大气散射。
	#endif

	#ifdef OMNI_VFOG
		#ifdef OMNI_UNDERWATER_VFOG
			if (isEyeInWater == 1) color += UnderwaterVolumetricFog(vec3(0.0), worldPos, worldDir, globalCloudShadow); // 水下体积雾光柱。
		#endif

		float fogTransmittance = 1.0; // 体积雾透射率。
		if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 体积雾。
	#endif

	if(isEyeInWater == 0.0 && wetness > 0.0) Rain(color, gbuffer.rainAlpha, colorShadowlight, colorSkylight); // 雨中画面。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSolid.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	#ifdef OMNI_PURKINJE_EFFECT
		PurkinjeEffect(color); // 暗处色偏。
	#endif

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		compositeOutput1 = vec4(color.rgb, 0.0); // 否则透明通道留零。
	#endif

	#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE || (defined OMNI_VFOG && defined OMNI_VFOG_BLOOM && !defined OMNI_DOF)
		compositeOutput3 = vec4(0.0); // 默认没有镜头光斑。

		#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE
			if (sunVisibility > 0.0 && isEyeInWater == 0) compositeOutput3.rgb = LensFlare(); // 看得到太阳时画眩光与光斑。
		#endif

		#if defined OMNI_VFOG && defined OMNI_VFOG_BLOOM && !defined OMNI_DOF
			compositeOutput3.a = 1.0 - fogTransmittance; // 体积雾泛光引导存进透明通道。
		#endif
	#endif
}
#endif // 维度分支结束。
#endif // 文件守卫结束。
