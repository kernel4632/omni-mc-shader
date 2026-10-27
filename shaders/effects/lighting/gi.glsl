/*
效果文件 `effects/lighting/gi.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lighting/gi.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_GI_INCLUDED
#define OMNI_GI_INCLUDED
/*
反射阴影图全局光：把相机、纹理与选项换成通用库参数，反弹、时间滤波和空间滤波各调用一次。
来源 iterationT 全局光系列。
调用位置：由 `effects/lighting/ambient.glsl` 引入；延迟一号（主世界）/ 延迟二号（末地）做时间滤波，
    延迟二号（主世界）/ 延迟四号（末地）做空间滤波，整段只在这些程序里编译。
可复制示例：
    `vec4 gi = GI_TemporalFilter();`
    `vec3 filtered = GI_SpatialFilter(dist, normal, viewDir);`
设计原因与取舍：主循环在 `gfx/gi.glsl`，这里只填 `gfx_gi_view` 结构、解释选项并各调用一次；
    程序宏仍留在这里，保证不需要全局光的程序不产生采样代码。
*/
// 通用库提供反弹、历史重投影、时间滤波与空间滤波。
#include "/gfx/gi.glsl"
// 远景深度贴图选择：没有远景模组时用近景深度占位，通用库按开关决定是否读取。
#ifdef DISTANT_HORIZONS
	#define OMNI_GI_DH_DEPTH dhDepthTex0 // 远景深度贴图。
#else
	#define OMNI_GI_DH_DEPTH depthtex1 // 占位，不会被读取。
#endif
#if OMNI_GI_RSM // 只有打开全局光才需要下面的函数。
// 把本帧相机、投影、阴影相机与屏幕尺寸打包成通用库结构；没有远景时用近景矩阵占位。
gfx_gi_view GiView(){
	gfx_gi_view view; // 本帧参数。
	view.projection_inverse = gbufferProjectionInverse; // 近景逆投影。
	view.previous_projection = gbufferPreviousProjection; // 上一帧投影。
	view.model_view_inverse = gbufferModelViewInverse; // 视空间转世界。
	view.previous_model_view = gbufferPreviousModelView; // 上一帧世界转视空间。
	view.model_view = gbufferModelView; // 本帧世界转视空间。
	#ifdef OMNI_END // 末地使用随相机旋转的阴影相机。
		view.shadow_view = shadowModelViewEnd; // 末地阴影视图。
		view.shadow_normal = mat3(shadowModelViewEnd) * mat3(gbufferModelViewInverse); // 法线转到末地阴影相机。
	#else // 主世界与下界使用主阴影相机。
		view.shadow_view = shadowModelView; // 主阴影视图。
		view.shadow_normal = mat3(shadowModelView) * mat3(gbufferModelViewInverse); // 法线转到主阴影相机。
	#endif
	view.shadow_projection = shadowProjection; // 阴影投影。
	#ifdef DISTANT_HORIZONS // 有远景时填远景逆投影。
		view.dh_projection_inverse = dhProjectionInverse; // 远景逆投影。
	#else // 没有远景时用近景值占位，通用库不会读取。
		view.dh_projection_inverse = gbufferProjectionInverse; // 占位。
	#endif
	view.camera_position = cameraPosition; // 本帧相机世界位置。
	view.previous_camera_position = previousCameraPosition; // 上一帧相机世界位置。
	view.screen_size = screenSize; // 画面像素尺寸。
	view.texel_size = pixelSize; // 一个像素的屏幕坐标大小。
	return view; // 交回打包结果。
}

// 反射阴影图与时间滤波只在延迟一号（主世界）或延迟二号（末地）编译，避免别的程序引用不存在的阴影采样器。
#if (defined OMNI_DEFERRED1_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED2_PASS)
// 反射阴影图反弹的兼容入口：保留原名供旧代码与测试查找，实际公式在通用库。
vec3 RSM(vec3 viewPos, vec3 normal){
	#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用一号阴影深度。
		const bool useSolidShadow = true; // 读一号深度。
	#else // 其他显卡读零号深度。
		const bool useSolidShadow = false; // 读零号深度。
	#endif
	#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做阳光泄漏修正。
		const bool leakFix = true; // 只给接到天光的表面补光。
	#else // 末地或关闭修正时不做遮罩。
		const bool leakFix = false; // 所有可见表面都补光。
	#endif
	return gfx_gi_rsm(viewPos, normal, GiView(), shadowtex0, shadowtex1, shadowcolor0, shadowcolor1,
		OMNI_GI_RADIUS, int(OMNI_GI_QUALITY), OMNI_GI_FALLOFF, float(shadowMapResolution), OMNI_SHADOW_MAP_BIAS,
		BlueNoiseTemporal(), useSolidShadow, leakFix, isEyeInWater == 1); // 一次调用完成反弹。
}

// 时间滤波：把本帧反弹、历史画面与阴影图交给通用库，返回要写回二号画面的数据。
vec4 GI_TemporalFilter(){
	#ifdef DISTANT_HORIZONS // 有远景时允许改读远景深度。
		const bool hasDh = true; // 远景分支存在。
	#else // 没有远景时用近景深度占位。
		const bool hasDh = false; // 远景分支不存在。
	#endif
	#ifdef MC_GL_VENDOR_NVIDIA // 支持遮挡贴图的显卡用一号阴影深度。
		const bool useSolidShadow = true; // 读一号深度。
	#else // 其他显卡读零号深度。
		const bool useSolidShadow = false; // 读零号深度。
	#endif
	#if defined OMNI_SUNLIGHT_LEAK_FIX && !defined OMNI_END // 主世界做阳光泄漏修正。
		const bool leakFix = true; // 只给接到天光的表面补光。
	#else // 末地或关闭修正时不做遮罩。
		const bool leakFix = false; // 所有可见表面都补光。
	#endif
	#if MC_VERSION >= 11605 // 新版本按天光标记决定是否反弹。
		const bool newVersion = true; // 使用天光标记。
	#else // 旧版本还要求像素足够远。
		const bool newVersion = false; // 使用深度阈值。
	#endif
	#ifdef OMNI_DISABLE_HAND_GI_VELOCITY // 手不参与重投影。
		const bool disableHand = true; // 排除手部。
	#else // 手正常参与。
		const bool disableHand = false; // 不排除手部。
	#endif
	#ifdef OMNI_DISABLE_PLAYER_GI_VELOCITY // 玩家不参与重投影。
		const bool disablePlayer = true; // 排除玩家。
	#else // 玩家正常参与。
		const bool disablePlayer = false; // 不排除玩家。
	#endif
	return gfx_gi_temporal_filter(texCoord, texelCoord, GiView(), colortex2, colortex2, colortex5, depthtex1, OMNI_GI_DH_DEPTH,
		shadowtex0, shadowtex1, shadowcolor0, shadowcolor1, OMNI_GI_RENDER_RESOLUTION, hasDh, OMNI_DH_AO != 0, newVersion,
		leakFix, isEyeInWater == 1, useSolidShadow, disableHand, disablePlayer, MC_HAND_DEPTH, float(MATID_ENTITIES_PLAYER),
		OMNI_GI_RADIUS, OMNI_GI_FALLOFF, int(OMNI_GI_QUALITY), float(shadowMapResolution), OMNI_SHADOW_MAP_BIAS, BlueNoiseTemporal()); // 一次调用完成时间滤波。
}
#endif // 反射阴影图与时间滤波结束。
// 空间滤波：主世界在延迟二号、末地在延迟四号，读半分辨率历史并做七乘七邻域平均。
#if (defined OMNI_DEFERRED2_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED4_PASS)
vec3 GI_SpatialFilter(float dist, vec3 normal, vec3 viewDir){
	return gfx_gi_spatial_filter(texCoord, dist, normal, viewDir, GiView(), colortex2, OMNI_GI_RENDER_RESOLUTION); // 一次调用完成空间滤波。
}
#endif // 空间滤波结束。
#endif // 全局光开关结束。
#endif // OMNI_GI_INCLUDED
