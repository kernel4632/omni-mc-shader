/*
水下体积雾：在水下沿视线步进阴影可见性并叠焦散，画出汇聚的蓝色光柱。
来源：iterationT `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl` 一比一移植。
职责：本文件只把相机、阴影图、波法线图、光色与选项接给通用库，步进与焦散都在 `gfx/fog_volume.glsl`。
调用位置：由 `effects/fog/fog.glsl` 引入；`effects/world/composite_scene.glsl` 与
  `effects/reflection/reflection.glsl` 在水下调用 `UnderwaterVolumetricFog`。
可复制示例：`vec3 shafts = UnderwaterVolumetricFog(vec3(0.0), worldPos, worldDir, globalCloudShadow);`
调用前提：由 `effects/fog/fog.glsl` 在引入 `effects/water/water.glsl` 之后引入，所以水下雾选项
  `OMNI_UNDERWATER_FOG` 与水雾密度选项可用；波法线来自 `effects/shadow/shadow.glsl`。
关键设计原因与取舍：原 `UnderwaterVolumetricFog.glsl` 里的 `CalculateWaterCaustics` 与
  `effects/shadow/shadow.glsl` 的同名函数内容不同，两份都保留在通用库；水下手持光按 Eclipse
  `composite3.fsh` 的 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER` 用钩子注入，默认不增加光。
*/
#ifndef OMNI_UNDERWATER_FOG_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_UNDERWATER_FOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// 水下体积雾：在水下沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向与全局云影；返回光柱颜色。
// 阴影图、波法线图、相机位置、光色与全部选项都显式交给通用库，宿主细节不再进入循环。
vec3 UnderwaterVolumetricFog(vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow){
	#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用实心深度图。
		bool useSolidShadow = true; // 英伟达走实心深度图。
	#else
		bool useSolidShadow = false; // 其他显卡用普通遮挡图。
	#endif
	#ifdef OMNI_UNDERWATER_FOG // 水下雾开启时按水色吸收。
		bool waterAbsorption = true; // 启用分波段吸收。
	#else
		bool waterAbsorption = false; // 关闭时不做水色吸收。
	#endif
	float handLightScale = 0.0; // 手持光默认不参与。
	#if defined OMNI_LPV_FOG_LIGHT && defined OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER // 雾照明-水下手持光开启时。
		handLightScale = OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.0004; // 亮度按 Eclipse 的系数换算。
	#endif
	return gfx_underwater_fog(startPos, endPos, worldDir, globalCloudShadow,
		cameraPosition, worldShadowVector, shadowtex0, shadowtex1, useSolidShadow,
		shadowModelView, shadowProjection, OMNI_SHADOW_MAP_BIAS,
		colortex7, pixelSize, screenSize, CAUSTICS_TEX_RESOLUTION, WATER_REFRACT_IOR,
		colorShadowlight, OMNI_SUNLIGHT_INTENSITY, OMNI_UNDERWATER_VFOG_DENSITY,
		int(OMNI_VFOG_QUALITY), BlueNoiseTemporal().y, waterAbsorption, OMNI_WATER_FOG_DENSITY, handLightScale); // 一次调用完成整段光柱。
}
#endif // OMNI_UNDERWATER_FOG_INCLUDED 结束。
