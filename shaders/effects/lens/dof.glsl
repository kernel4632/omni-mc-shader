/*
景深：把选项、深度与随机数换成通用库参数，弥散统计和散焦合成各调用一次。
来源 iterationT `DOF.glsl`；散景变形与色散照 Eclipse 的对应选项。
调用位置：由 `effects/lens/lens.glsl` 引入；合成五号调用 `CoCSpread`，合成六号调用 `DepthOfField`。
可复制示例：`vec4 dof = DepthOfField();`
设计原因与取舍：主循环在 `gfx/post.glsl`，这里只读宿主纹理、解释选项并把结果写回；
  这样通用库可以脱离 Minecraft 单独使用，而选项名与默认值保持不变。
*/
#ifndef OMNI_DOF_INCLUDED
#define OMNI_DOF_INCLUDED // 置上标记，后续再次引用直接跳过。
// 通用库提供弥散圆、镜头倍数、深度换算与完整散焦循环。
#include "/gfx/post.glsl"

// 基准镜头：五十毫米、f/2.8。取默认值时镜头倍数正好为一，画面与移植前一致。
const float DoF_RefFocal = 50.0; // 基准焦距，毫米。
const float DoF_RefAperture = 2.8; // 基准光圈，f 值。

// 远景深度贴图选择：没有远景模组时用近景深度占位，通用库按开关决定是否读取。
#ifdef DISTANT_HORIZONS
	#define OMNI_DOF_DH_DEPTH dhDepthTex0 // 远景深度贴图。
#else
	#define OMNI_DOF_DH_DEPTH depthtex0 // 占位，不会被读取。
#endif

// 取对焦距离：自动模式读屏幕中心的历史深度并平滑，手动模式直接用选项。
float GetFocus(){
	#if OMNI_CAMERA_FOCUS_MODE == 0 // 自动对焦。
		return LinearDepth_From_ScreenDepth(texelFetch(colortex2, ivec2(60, screenSize.y - 1.0), 0).a * 0.125 + 0.875); // 解码顶行统计像素里的对焦深度。
	#else // 手动对焦。
		return OMNI_CAMERA_FOCAL_POINT; // 直接用选项给的距离。
	#endif
}

// 当前帧的二维抖动：开时间抗锯齿时逐帧变化，否则保持固定蓝噪声。
vec2 DoFNoise(){
	#ifdef OMNI_TAA // 每帧变化的蓝噪声。
		return BlueNoiseTemporal(); // 避免固定图案。
	#else // 固定蓝噪声。
		return BlueNoise(); // 与未开时间抗锯齿时一致。
	#endif
}

// 前景弥散范围：把当前点深度、镜头换算与搜索次数交给通用库，返回归一化弥散。
float CoCSpread(){
	float lensFactor = gfx_dof_lens_factor(OMNI_DOF_FOCAL_LENGTH, OMNI_DOF_APERTURE, DoF_RefFocal, DoF_RefAperture); // 焦距光圈换算。
	#ifdef DISTANT_HORIZONS // 有远景时允许改读远景深度。
		const bool useDh = true; // 启用远景分支。
		mat4 dofDhProjectionInverse = dhProjectionInverse; // 远景逆投影。
	#else // 没有远景时用近景深度占位。
		const bool useDh = false; // 关闭远景分支。
		mat4 dofDhProjectionInverse = gbufferProjectionInverse; // 占位，不会被读取。
	#endif
	return gfx_dof_coc_spread(texCoord, depthtex0, OMNI_DOF_DH_DEPTH, gbufferProjectionInverse, dofDhProjectionInverse, useDh,
		GetFocus(), OMNI_DOF_BLUR, gbufferProjection[1][1], lensFactor, OMNI_DOF_MAX_COC, aspectRatio,
		int(OMNI_DOF_COCSPREAD_QUALITY), DoFNoise()); // 一次调用完成整段螺旋搜索。
}

// 散焦合成：通用库按弥散范围取样，返回曲线编码颜色；下界额外回写散焦后的深度。
vec4 DepthOfField(){
	float lensFactor = gfx_dof_lens_factor(OMNI_DOF_FOCAL_LENGTH, OMNI_DOF_APERTURE, DoF_RefFocal, DoF_RefAperture); // 焦距光圈换算。
	#ifdef DISTANT_HORIZONS // 有远景时允许改读远景深度。
		const bool useDh = true; // 启用远景分支。
		mat4 dofDhProjectionInverse = dhProjectionInverse; // 远景逆投影。
	#else // 没有远景时用近景深度占位。
		const bool useDh = false; // 关闭远景分支。
		mat4 dofDhProjectionInverse = gbufferProjectionInverse; // 占位，不会被读取。
	#endif
	#ifdef OMNI_NETHER // 下界要把散焦后的深度写进透明度。
		const bool storeDepth = true; // 回写深度。
	#else // 主世界与末地不需要深度。
		const bool storeDepth = false; // 透明度留零。
	#endif
	return gfx_depth_of_field(texCoord, colortex1, depthtex0, OMNI_DOF_DH_DEPTH, gbufferProjectionInverse, dofDhProjectionInverse, useDh,
		GetFocus(), OMNI_DOF_BLUR, gbufferProjection[1][1], lensFactor, OMNI_DOF_MAX_COC, pixelSize, aspectRatio,
		int(OMNI_DOF_QUALITY), OMNI_DOF_CATSEYE != 0, OMNI_DOF_CATSEYE_MIDPOINT, OMNI_DOF_CATSEYE_STRENGTH,
		OMNI_DOF_ANAMORPHIC_RATIO, OMNI_DOF_DISPERSION_MULT, storeDepth, DoFNoise()); // 一次调用完成整段散焦。
}

#endif // 文件守卫结束。
