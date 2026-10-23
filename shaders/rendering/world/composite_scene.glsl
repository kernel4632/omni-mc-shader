/*
合成五号场景最终合成：折射、彩色玻璃吸收、合并反射、雾、雨、选择框与镜头光斑，是 iterationT `composite5.fsh` 及两个维度版本的算法体移植。
职责：在一号画面颜色上依次做水玻璃冰折射与彩色玻璃吸收、合并三号画面的反射、体积雾与地面散射、雨、原版雾、
    选择框与浦肯野效应，最后编码写回一号画面，并按需把镜头光斑与体积雾泛光写进三号画面。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE5_PASS` 分支引入维度相关效果与反射、颜色、镜头、选择框文件后引入本文件，
    最后 `void main(){ CompositeSceneColor(); }` 调用。
可复制示例：`CompositeSceneColor();`（要求调用方已提供 `texelCoord`、`texCoord`、`sunCoord`、`sunVisibility`、
    `colortex1`、`colortex3`、`compositeOutput1` 与 `compositeOutput3` 等）。
设计原因与取舍：本程序横跨水、反射、雾、雨、选择框、镜头多个效果，但三个维度的流程几乎相同，差别只在折射函数、
    雾函数、水吸收与输出通道这几处；所以只写一份流程，用 `#if` 在差处按维度分派，而不是把三段各抄一遍。
    原程序 `composite5.fsh`、`world-1/composite5.fsh`、`world1/composite5.fsh` 是三份近似复制，这里把复制去掉，
    差异逐处照原程序保留，画面与原来一致，属偏离记录登记的结构改动。
*/
#ifndef OMNI_COMPOSITE_SCENE_INCLUDED // 只引入一次，避免函数与结构体重复定义。
#define OMNI_COMPOSITE_SCENE_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 共用表面数据：一次读回本像素的几何与距离 ---

// 合成场景共用的表面数据。三个维度都要读同一批量，装进一个结构体随函数传递，省掉三段各读一遍。
struct SceneSurface {
	GbufferData gbuffer; // 本像素的表面数据：贴图色、法线、材质编号与两层深度。
	MaterialMask materialMaskSoild; // 不透明层材质掩码。
	MaterialMask materialMask; // 半透明层材质掩码。
	vec3 viewPos; // 半透明表面视空间位置。
	vec3 viewPosSoild; // 不透明表面视空间位置。
	vec3 worldPos; // 半透明表面相机相对世界位置。
	vec3 viewDir; // 视线方向。
	vec3 worldDir; // 世界方向。
	float opaqueDist; // 不透明表面距离，天空给很远。
	float waterDist; // 半透明表面距离，天空给很远。
	bool skyDepthW; // 远景深度替换前半透明层是否是天空，下界输出透明通道要用它。
};

// 读回本像素的表面、远景深度与视/世界位置，并算出两层距离：三个维度共用这份准备。
// 为什么抽出来：这段原来在下界、末地、主世界各抄一份，改一行要同步三处，容易抄漏；抽成一处后只剩后面的差处需要分派。
SceneSurface SceneReadSurface(){
	SceneSurface scene; // 待填的共用数据。
	scene.gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	scene.materialMaskSoild = CalculateMasks(scene.gbuffer.materialIDL); // 不透明层材质掩码。
	scene.materialMask = CalculateMasks(scene.gbuffer.materialIDW); // 半透明层材质掩码。

	scene.skyDepthW = scene.gbuffer.depthW == 1.0; // 远景替换前记下是否天空，下界输出透明通道要用它判远景。
	FixParticleMask(scene.materialMaskSoild, scene.materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(scene.gbuffer.material, scene.materialMask, isSmooth); // 水玻璃冰用写死材质。

	scene.viewPos = ViewPos_From_ScreenPos(texCoord, scene.gbuffer.depthW); // 半透明表面视空间位置。
	scene.viewPosSoild = ViewPos_From_ScreenPos(texCoord, scene.gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (scene.gbuffer.depthW == 1.0){ // 半透明表面是天空像素时改读远景深度。
			scene.gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			scene.viewPos = ViewPos_From_ScreenPos_DH(texCoord, scene.gbuffer.depthW); // 远景逆投影。
		}
		if (scene.gbuffer.depthL == 1.0){ // 不透明表面是天空像素时改读远景深度。
			scene.gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			scene.viewPosSoild = ViewPos_From_ScreenPos_DH(texCoord, scene.gbuffer.depthL); // 远景逆投影。
		}
	#endif

	scene.worldPos = mat3(gbufferModelViewInverse) * scene.viewPos; // 视空间转相机相对世界空间。
	scene.viewDir = normalize(scene.viewPos.xyz); // 视线方向。
	scene.worldDir = normalize(scene.worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		#if defined OMNI_NETHER || defined OMNI_END
			float farDist = max(far * 1.2, 1024.0); // 下界与末地取一点二倍近景远裁剪面，照各自原程序。
		#else
			float farDist = max(far * 1.4, 1024.0); // 主世界取一点四倍，照主世界原程序。
		#endif
	#endif
	#if defined OMNI_NETHER || defined OMNI_END
		// 下界与末地按材质掩码判天空（照各自原程序）：天空掩码给很远，雾才不会在天空处被距离截断。
		scene.opaqueDist = min(length(scene.viewPosSoild) + scene.materialMaskSoild.sky * 1e10, farDist); // 不透明表面距离。
		scene.waterDist = min(length(scene.viewPos) + scene.materialMask.sky * 1e10, farDist); // 半透明表面距离。
	#else
		// 主世界按深度是否等于一判天空（照主世界原程序）。写法与掩码版不同，画面已验证一致，保留以免改动行为。
		scene.opaqueDist = min(length(scene.viewPosSoild) + float(scene.gbuffer.depthL == 1.0) * 1e10, farDist); // 不透明表面距离。
		scene.waterDist = min(length(scene.viewPos) + float(scene.gbuffer.depthW == 1.0) * 1e10, farDist); // 半透明表面距离。
	#endif

	return scene; // 交给合成主体使用。
}

// 写回合成五号输出：换回存储单位、四次方根编码，再按需把景深弥散或传入值写进透明通道。
// 为什么传入值：下界的透明通道要存半透明深度，末地与主世界留零，只有这一点不同，所以用参数而非另写一份。
void SceneWriteOutput(vec3 color, float alpha){
	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。
	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围，忽略传入值。
	#else
		compositeOutput1 = vec4(color.rgb, alpha); // 否则透明通道存传入值。
	#endif
}

// --- 场景最终合成：三个维度共用一份流程，只在差处按维度分派 ---

void CompositeSceneColor(){
	SceneSurface scene = SceneReadSurface(); // 读回表面、位置与两层距离。

	#if !defined OMNI_NETHER && !defined OMNI_END // 主世界才要体积雾时间因子与全局云影，供折射与体积雾使用。
		float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
		#ifndef OMNI_VFOG_IGNORE_WORLDTIME
			#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
				fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7)); // 按昼夜与所在群系降水调整。
			#else
				fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 只按昼夜与整体湿润度调整。
			#endif
		#endif
		float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾与光柱使用。
	#endif

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	#if defined OMNI_NETHER
		// 下界：只有冰与彩色玻璃做折射，彩色玻璃再吸收；照 `world-1/composite5.fsh` 的条件不带水。
		if (scene.materialMask.ice + scene.materialMask.stainedGlass > 0.5) // 冰面与彩色玻璃做折射。
			RefractSampleOnceNether(color, scene.materialMask, scene.gbuffer.normalW, scene.worldPos, scene.viewPos, scene.waterDist, scene.opaqueDist); // 下界折射。
		if (scene.materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
			TransparentAbsorptionNether(color, scene.gbuffer.albedoW); // 下界彩色玻璃吸收。
	#elif defined OMNI_END
		// 末地：水、冰与彩色玻璃都做折射，彩色玻璃再吸收。
		if (scene.materialMask.water + scene.materialMask.ice + scene.materialMask.stainedGlass > 0.5) // 水、冰与彩色玻璃做折射。
			RefractSampleOnceEnd(color, scene.materialMask, scene.gbuffer.normalW, scene.worldPos, scene.viewPos, scene.waterDist, scene.opaqueDist); // 末地折射。
		if (scene.materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
			TransparentAbsorptionEnd(color, scene.gbuffer.albedoW); // 末地彩色玻璃吸收。
	#else
		// 主世界：水、冰与彩色玻璃都做折射，彩色玻璃吸收带按距离算出的水吸收。
		float waterAbsorption = 1.0; // 水的吸收系数，默认不吸收。
		if (isEyeInWater == 1) waterAbsorption = saturate(exp2(-scene.waterDist * 0.06 * OMNI_WATER_FOG_DENSITY)); // 水下按距离算吸收。
		if (scene.materialMask.water + scene.materialMask.ice + scene.materialMask.stainedGlass > 0.5) // 水、冰与彩色玻璃做折射。
			RefractSampleOnce(color, scene.materialMask, scene.gbuffer.normalW, scene.worldPos, scene.viewPos, scene.waterDist, scene.opaqueDist, fogTimeFactor, globalCloudShadow, texCoord, texelCoord); // 主世界折射，比另两个维度多吃雾与水波参数。
		if (scene.materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
			TransparentAbsorption(color, scene.gbuffer.albedoW, waterAbsorption); // 主世界彩色玻璃吸收。
	#endif

	if (scene.materialMask.water + scene.materialMask.ice > 0.5 || isEyeInWater == 1) // 水与冰整体染一点冷色。
		color *= vec3(0.5, 0.55, 0.7); // 三个维度同一组水色，照各自原程序。

	#if defined OMNI_NETHER || defined OMNI_END
		if (scene.gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
			CalculateSpecularReflections(color, scene.viewDir, scene.gbuffer.normalW, scene.gbuffer.albedo, 1.0, scene.gbuffer.material); // 下界与末地不用水吸收。
	#else
		if (scene.gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
			CalculateSpecularReflections(color, scene.viewDir, scene.gbuffer.normalW, scene.gbuffer.albedo, waterAbsorption, scene.gbuffer.material); // 主世界带上水吸收。
	#endif

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if(heldBlockLightValue + heldBlockLightValue2 > 0.0 && scene.materialMask.sky < 0.5)
			TorchSpecularHighlight(color, scene.viewPos, scene.viewDir, scene.waterDist, scene.gbuffer.albedo, scene.gbuffer.normalW, scene.gbuffer.material); // 手持光高光，三个维度共用。
	#endif

	#if defined OMNI_NETHER
		vec4 netherFog = NetherFog(scene.waterDist); // 下界整条视线的雾散射与剩余透射率。
		color = color * netherFog.a + netherFog.rgb; // 先按透射率把被雾挡住的背景压暗，再叠雾散射；体积雾关闭时透射率为一，画面不变。
	#elif defined OMNI_END
		vec4 endFog = EndFogWithTransmittance(scene.waterDist, scene.worldDir); // 末地整条视线的雾散射色与剩余透射率。
		color = color * endFog.a + endFog.rgb; // 先按透射率把被雾挡住的背景压暗，再叠雾散射；涡旋雾关闭时透射率为一，画面不变。
	#else
		// 主世界：地面大气散射、体积雾、水下体积雾与雨都在这里。
		#ifdef DISTANT_HORIZONS
			#ifdef OMNI_DH_LIMIT_VFOG_DIST
				vec3 rayWorldPos = scene.worldDir * min(scene.waterDist, max(float(dhRenderDistance), far) * 1.4); // 雾气射线终点，限制在一百区块内。
			#else
				vec3 rayWorldPos = scene.worldDir * min(length(scene.worldPos) + float(scene.gbuffer.depthW == 1.0) * 1e10, max(float(dhRenderDistance), far) * 1.4); // 不限制时的射线终点。
			#endif
		#else
			vec3 rayWorldPos = scene.worldDir * min(scene.waterDist, far * 1.4); // 没有远景时用近景可视距离。
		#endif

		#ifdef OMNI_LANDSCATTERING
			LandAtmosphericScattering(color, scene.waterDist, vec3(0.0), rayWorldPos, scene.worldDir, scene.materialMask.sky > 0.5); // 地面大气散射。
		#endif

		#ifdef OMNI_VFOG
			#ifdef OMNI_UNDERWATER_VFOG
				if (isEyeInWater == 1) color += UnderwaterVolumetricFog(vec3(0.0), scene.worldPos, scene.worldDir, globalCloudShadow); // 水下体积雾光柱。
			#endif
			float fogTransmittance = 1.0; // 体积雾透射率，供后面写入泛光引导。
			if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, vec3(0.0), rayWorldPos, scene.worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 体积雾。
		#endif

		if(isEyeInWater == 0.0 && wetness > 0.0) Rain(color, scene.gbuffer.rainAlpha, colorShadowlight, colorSkylight); // 雨中画面。
	#endif

	VanillaFog(color, scene.waterDist); // 原版雾、失明、黑暗、岩浆雪盲，三个维度共用。

	SelectionBox(color, scene.gbuffer.albedo, scene.materialMaskSoild.selection > 0.5 && isEyeInWater < 3); // 选择框上色，三个维度共用。

	#if !defined OMNI_NETHER && !defined OMNI_END
		#ifdef OMNI_PURKINJE_EFFECT
			PurkinjeEffect(color); // 暗处色偏，只有主世界原程序有。
		#endif
	#endif

	#if defined OMNI_NETHER
		float sceneAlpha = 0.0; // 下界透明通道默认零。
		#ifndef OMNI_DOF
			#ifdef DISTANT_HORIZONS
				if (scene.skyDepthW) scene.gbuffer.depthW = ScreenDepth_From_DHScreenDepth(scene.gbuffer.depthW); // 深度换回近景尺度。
			#endif
			sceneAlpha = scene.gbuffer.depthW; // 下界把半透明深度存进透明通道，照 `world-1/composite5.fsh`。
		#endif
		SceneWriteOutput(color, sceneAlpha); // 写法照下界合成五号。
	#else
		SceneWriteOutput(color, 0.0); // 末地与主世界的透明通道留零。
	#endif

	#if !defined OMNI_NETHER && !defined OMNI_END
		#if OMNI_LENS_GLARE || OMNI_LENS_FLARE || (defined OMNI_VFOG && !defined OMNI_DOF)
			compositeOutput3 = vec4(0.0); // 默认没有镜头光斑。

			#if OMNI_LENS_GLARE || OMNI_LENS_FLARE
				if (sunVisibility > 0.0 && isEyeInWater == 0) compositeOutput3.rgb = LensFlare(); // 看得到太阳时画眩光与光斑。
			#endif

			#if defined OMNI_VFOG && !defined OMNI_DOF
				compositeOutput3.a = 1.0 - fogTransmittance; // 体积雾吸收（泛光引导）存进透明通道，供泛光合并读取。
			#endif
		#endif
	#endif
}
#endif // 文件守卫结束。
