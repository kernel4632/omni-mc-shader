/*
合成一号水下与水后雾：在合成零号之后把水下与水面之后的雾叠进场景色，是 iterationT `composite1.fsh` 的算法体一比一移植。
职责：读回一号画面颜色，处理水下看水面的折射天空盒回退与全反射标记，再调用 `WaterFog` 叠水下与水后雾。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE1_PASS` 分支引入水面与云效果后引入本文件，
    最后 `void main(){ CompositeWaterFog(); }` 调用。
可复制示例：`CompositeWaterFog();`（要求调用方已提供 `texelCoord`、`texCoord`、光色 varying、
    `colortex1`、`colortex2` 与 `WATER_REFRACT_IOR` 等，见 `rendering/composite_shared.glsl`）。
设计原因与取舍：本程序只服务水面与雾效果，所以放进 `effects/water/`；`WaterFog` 本身在 `effects/water/water.glsl`。
*/
#ifndef OMNI_COMPOSITE_WATERFOG_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_WATERFOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// 水下与水后雾：折射天空盒回退、全反射标记，再交给 `WaterFog` 叠雾（来自 `composite1.fsh`）。
void CompositeWaterFog(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	FixParticleMask(materialMaskSolid, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。
	vec3 viewPosTranslucent = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthL == 1.0){
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
		if (gbuffer.depthW == 1.0){
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPosTranslucent = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldDir = normalize(worldPos); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = gbuffer.depthL < 1.0 ? length(viewPos) : farDist; // 不透明表面距离。
	float waterDist = gbuffer.depthW < 1.0 ? length(viewPosTranslucent) : farDist; // 半透明表面距离。

	vec3 finalComposite = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb) * MAIN_OUTPUT_FACTOR; // 一号画面换回线性用于合成。

	if (isEyeInWater == 1 && materialMask.water > 0.5){ // 水下看水面：折射方向改读天空盒。
		worldDir = refract(worldDir, mat3(gbufferModelViewInverse) * gbuffer.normalW, WATER_REFRACT_IOR); // 水面折射方向。
		if (gbuffer.depthL == 1.0){ // 水面背后是天空时改读天空盒图。
			float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图边长。
			vec2 skyImageCoord = ProjectSky(worldDir, tileSize); // 折射方向投到天空盒坐标。
			finalComposite = CurveToLinear(textureLod(colortex2, skyImageCoord, 0.0).rgb) * MAIN_OUTPUT_FACTOR; // 读天空盒颜色。
		}
	}

	float totalInternalReflection = 0.0; // 全反射标记，写进一号画面透明通道。
	if (length(worldDir) < 0.5){ // 折射方向退化说明发生全反射。
		finalComposite = vec3(0.0); // 全反射看不到外面，直接压黑。
		totalInternalReflection = 1.0; // 记录发生全反射。
	}

	#ifdef OMNI_UNDERWATER_FOG
		if(gbuffer.waterMask > 0.5 || isEyeInWater == 1 || materialMask.ice > 0.5){ // 水、水下、冰面才做水雾。
			float occludedWater = gbuffer.waterMask * materialMask.stainedGlass; // 被玻璃挡住的水。
			WaterFog(finalComposite, viewDir, opaqueDist, waterDist, gbuffer.normalW, materialMask, occludedWater, gbuffer.lightmapW.g, totalInternalReflection, shadowVector, colorShadowlight, colorSkylight); // 水下与水后雾。
		}
	#endif

	finalComposite /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

	compositeOutput1 = vec4(finalComposite.rgb, totalInternalReflection); // 写回一号画面。
}
#endif // 文件守卫结束。
