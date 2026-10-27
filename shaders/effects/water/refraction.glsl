/*
效果文件 `effects/water/refraction.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/refraction.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_WATER_REFRACTION_INCLUDED
#define OMNI_WATER_REFRACTION_INCLUDED
/*
水面折射与彩色透光吸收：把水下的采样按波法线偏移一次，再按水与玻璃的颜色吸收透过的光。
来源 iterationT 水面折射段与彩色玻璃吸收段。
调用位置：由 `effects/water/water.glsl` 引入；合成阶段处理半透明水面时调用 `RefractSampleOnce`、`TransparentAbsorption`。
可复制示例：
    `RefractSampleOnce(color, materialMask, normal, worldPos, viewPos);`
    `TransparentAbsorption(color, stainedGlassAlbedo, waterAbsorption);`
设计原因与取舍：折射与吸收都属“透过水看东西”，共用水的距离与颜色，放一起方便对照；
    折射会按体积雾与远景选项决定是否采样，保留 iterationT 的条件。
*/
// 折射屏幕坐标：水面先取波法线，再交给通用库算偏移；玻璃直接按折射方向投影。
// 为什么把波法线采样留在本文件：它要读噪声贴图与选项，通用库只接收算好的方向。
vec2 RefractionScreenCoord(MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist, vec2 screenInput){
	float waterDeep = opaqueDist - waterDist; // 水面到水底的厚度，越厚折射越强。
	vec3 waveNormal = vec3(0.0); // 玻璃不需要波法线。
	if (mask.water > 0.5){ // 只有水面才采样波浪。
		float NdotU = dot(normal, gbufferModelView[1].xyz) + float(isEyeInWater == 1) * 2.0; // 法线朝向与水下判断。
		waveNormal = GetWavesNormal(worldPos + cameraPosition, step(0.05, NdotU) * 18.0).xzy; // 波法线换到竖直轴朝上。
	}
	// 相机矩阵、投影与厚度显式传入，公式在通用库。
	return ogxWaterRefractionCoord(mask.water > 0.5, normal, viewPos, waveNormal, mat3(gbufferModelView), gbufferProjection, waterDeep, waterDist, screenInput);
}

// --- 水面折射：把采样坐标偏移一次再读回场景色 ---
// 调用位置：`rendering/composite.glsl`；先把采样点按水面法线偏移，再读一号画面的颜色。
// 对应 iterationT `composite5.fsh` 的 `WaterRefractionLite`，移植后改名以说明它只采样一次，避免含糊的 `Lite`。
// 防泄漏：偏移后的采样点若比当前水面更近，说明采到了前景物体，直接退回原位。
// 为什么分成水面与水外两条路：水面用波法线偏移更贴合，水外的玻璃等用整段折射方向偏移更准确。
// 为什么像素坐标由调用方传 `texelCoord`：渲染缩放或放大链下 `screenCoordInput` 与 `screenSize` 的口径可能不同，
//   用传入的整数像素坐标直接读深度，才与原程序一致，不会差出一个像素。
void RefractSampleOnce(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist, float fogTimeFactor, float cloudShadow, vec2 screenCoordInput, ivec2 texelCoord){
	vec2 refractCoord = RefractionScreenCoord(mask, normal, worldPos, viewPos, waterDist, opaqueDist, screenCoordInput); // 一次算出折射后的屏幕坐标。

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素的深度，直接用调用方传入的整数像素坐标，不靠屏幕坐标反推。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点的深度。
	if(refractDepth < currentDepth) refractCoord = screenCoordInput; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(screenCoordInput, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord, 0.0).rgb); // 读回折射后的场景颜色。

	#if (defined OMNI_LANDSCATTERING && defined OMNI_LANDSCATTERING_REFRACTION) || (defined OMNI_VFOG && defined OMNI_VFOG_REFRACTION) // 只在同时开启地表散射或体积雾的折射时，给玻璃后面补雾。
		if (mask.stainedGlass > 0.5){ // 只处理彩色玻璃。
			float rDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射点的深度。
			vec3 rViewPos = ViewPos_From_ScreenPos(refractCoord, rDepth); // 还原视空间位置。
			#ifdef DISTANT_HORIZONS // 有远景时，近景是天空就改用远景深度。
				if (rDepth == 1.0){ // 近景是天空。
					rDepth = textureLod(dhDepthTex1, refractCoord, 0.0).x; // 读远景深度。
					rViewPos = ViewPos_From_ScreenPos_DH(refractCoord, rDepth); // 远景还原位置。
				}
				float farDist = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
				#ifdef OMNI_DH_LIMIT_VFOG_DIST
					farDist = min(2048.0, farDist); // 限制雾距离上限。
				#endif
			#else
				float farDist = far * 1.4; // 没有远景时用近景远裁剪面估计。
			#endif

			float rDist = min(length(rViewPos) + float(rDepth == 1.0) * 1e10, farDist); // 折射点距离，天空给很远。
			rDist = max(rDist - waterDist, 0.0); // 减去水面距离，只剩水体厚度。

			vec3 rWorldPos = mat3(gbufferModelViewInverse) * rViewPos; // 折射点转回相机相对世界。
			vec3 rWorldDir = normalize(rWorldPos); // 世界方向。

			vec3 endPos = rWorldDir * rDist; // 雾的终点。

			color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾函数按此单位工作。

			#ifdef OMNI_LANDSCATTERING
				#ifdef OMNI_LANDSCATTERING_REFRACTION
					LandAtmosphericScattering(color, rDist, worldPos, endPos, rWorldDir, rDepth == 1.0); // 给折射后的场景补地表散射。
				#endif
			#endif

			#ifdef OMNI_VFOG
				#ifdef OMNI_VFOG_REFRACTION
					float fogTransmittance = 1.0; // 透射率占位，本处不返回。
					if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, worldPos, endPos, rWorldDir, cloudShadow, fogTimeFactor, fogTransmittance); // 给折射后的场景补体积雾。
				#endif
			#endif

			color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
		}
	#endif
}

// --- 彩色玻璃吸收：按玻璃自身的颜色与不透明度吸收透过的光 ---
// 调用位置：`rendering/composite.glsl`；只影响彩色玻璃像素。
// 为什么把颜色归一化再乘回长度：贴图颜色可能很亮，先取方向与大致亮度，避免吸收过强或失效。
void TransparentAbsorption(inout vec3 color, vec4 stainedGlassAlbedo, float waterAbsorption){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	stainedGlassAlbedo.a = pow(stainedGlassAlbedo.a, 0.2); // 抬升不透明度曲线，让吸收更明显。

	#ifdef OMNI_UNDERWATER_FOG // 水下时玻璃吸收按水的吸收程度缩放。
		if (isEyeInWater == 1) stainedGlassAlbedo.a = mix(0.0, stainedGlassAlbedo.a, waterAbsorption); // 水越浅吸收越弱。
	#endif

	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, stainedGlassAlbedo.a)); // 按不透明度在无吸收与玻璃色之间混合后吸收。
}
#endif // OMNI_WATER_REFRACTION_INCLUDED
