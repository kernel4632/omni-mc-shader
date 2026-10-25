/*
阴影的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/shadow/shadow.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_SHADOW_SHADOW_INCLUDED
#define OMNI_RENDER_SHADOW_SHADOW_INCLUDED
#include "/effects/shadow/shadow.glsl"
/*
阴影：把 iterationT 的阴影图坐标、可变半影阴影、屏幕空间阴影、次表面散射、焦散法线与水面波法线集中到一个文件。
职责分成四块：
  一、定义阴影相关选项，以及 Iris 原生常量 `shadowMapResolution`、`shadowDistance`，全项目只在这里定义一次；
  二、把相机相对世界位置投向阴影相机，得到零到一的阴影图坐标，主世界与末地各一套，末尾用 `OMNI_END` 编译期二选一；
  三、提供不透明表面的阴影查询 `VariablePenumbraShadow`，内部做可变半影与彩色半透明阴影，并带回次表面散射项；
  四、提供屏幕空间阴影 `ScreenSpaceShadow`、水体焦散 `CalculateWaterCaustics` 和七号画面的波法线 `GetWavesNormalFromTex`。
调用位置：
  `rendering/shadow.glsl`（阴影深度写入）、`rendering/dh_shadow.glsl`（远景阴影）与 `rendering/composite.glsl`（不透明光照）引入本文件；
  `rendering/dh_shadow.glsl` 的剔除只读 `shadowDistance` 与几个 `OMNI_DH_*` 选项，不调用下面的采样函数。
可复制示例：
  `vec3 shadowPos = ShadowScreenPos_From_WorldPos(worldPos);`  求一个世界位置的阴影图坐标；
  `vec3 shadow = VariablePenumbraShadow(worldPos, worldNormal, sunlight, albedo, scattering, mask, sss);`  不透明表面阴影可见度。
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `shadowtex0`、`shadowtex1`、`shadowcolor0` 三个阴影采样器，以及主程序的 `in vec3 worldShadowVector`、`in vec3 shadowVector`；
  `ivec2 texelCoord`、`vec2 texCoord` 由延迟与合成主程序声明；`MaterialMask` 结构由 `effects/ground/material.glsl` 提供；
  `OMNI_TAA`、`OMNI_DISABLE_HAND_TAA`、`OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR` 由 `effects/clarity/antialiasing.glsl` 提供。
关键设计原因与取舍：
  坐标变换与遮挡查询分成两层，写入端只复用变换、不引入深度采样，读取端只关心比较，职责不混；
  主世界与末地用不同的阴影相机矩阵，编译期二选一，运行时不再多一次分支；
  全局量按原程序依赖调用方已声明，本文件不重复声明，避免与主程序重复定义一个输入而导致编译失败。
    本文件按算法拆到同目录：屏幕空间阴影在 `screen_shadow.glsl`，水下焦散在 `water_caustics.glsl`；阴影图坐标与可变半影留在本文件；引入顺序与拆分前逐字一致。
*/


// 深度与屏幕坐标换算给屏幕空间阴影用，共用计算提供颜色曲线与相位函数，蓝噪声提供采样抖动。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
#include "/common/noise.glsl"
// 投影、比较与半影算法来自通用库，本文件只保留宿主矩阵与阴影图接线。
#include "/gfx/shadow.glsl"

// --- 阴影图坐标：世界位置投向阴影相机 ---
// 三个函数只差一处：是否做边缘压缩，以及是否把深度按投影缩放；分开写让调用方按用途挑选，不在函数里加开关。
// 写入端用未压缩坐标，读取端用压缩后坐标，两端坐标口径必须一致，否则阴影会整体偏移。
#ifdef OMNI_END // 末地：阴影相机随相机位置旋转平移，避免末地大坐标造成抖动。
	// --- 末地阴影相机矩阵：绕固定角度旋转，再按相机位置吸附到方块网格 ---
	const vec3 roataionAngle = vec3(0.28, -1.1, 1.0); // 三个轴上的固定旋转角，原程序取值。
	const mat3 rotX = mat3(1.0, 0.0, 0.0,
	                       0.0, cos(roataionAngle.x), sin(roataionAngle.x),
	                       0.0, -sin(roataionAngle.x), cos(roataionAngle.x)); // 绕横轴旋转。
	const mat3 rotY = mat3(cos(roataionAngle.y), 0.0, -sin(roataionAngle.y),
	                       0.0, 1.0, 0.0,
	                       sin(roataionAngle.y), 0.0, cos(roataionAngle.y)); // 绕纵轴旋转。
	const mat3 rotZ = mat3(cos(roataionAngle.z), sin(roataionAngle.z), 0.0,
	                       -sin(roataionAngle.z), cos(roataionAngle.z), 0.0,
	                       0.0, 0.0, 1.0); // 绕竖轴旋转。
	const mat3 rot = rotZ * rotX * rotY; // 三个旋转合成一个矩阵，顺序照原程序。
	vec3 shadowInterval = fract(rot * cameraPosition * 0.25) * 4.0; // 按相机位置把阴影原点吸附到四格网格，抵消亚格抖动。
	mat4 shadowModelViewEnd = mat4(vec4(rot[0], 0.0),
	                               vec4(rot[1], 0.0),
	                               vec4(rot[2], 0.0),
	                               vec4(shadowInterval.xy, shadowInterval.z - 100.0, 1.0)); // 末地阴影相机视图矩阵，向上抬一百格避开世界边界。
	mat3 rotInverse = transpose(rot); // 逆旋转是旋转矩阵的转置。`transpose` 不是常量表达式，不能写成 `const`。
	mat4 shadowModelViewInverseEnd = mat4(vec4(rotInverse[0], 0.0),
	                                      vec4(rotInverse[1], 0.0),
	                                      vec4(rotInverse[2], 0.0),
	                                      vec4(-shadowInterval.xy, 100 - shadowInterval.z, 1.0)); // 末地阴影相机的逆矩阵，供世界位置还原。
	// 投到阴影相机并做边缘压缩，压缩让阴影图边缘分辨率更高。
	vec3 ShadowScreenPos_From_WorldPos_Distorted(vec3 worldPos){ return gfx_shadow_screen_pos_distorted(worldPos, shadowModelViewEnd, shadowProjection, OMNI_SHADOW_MAP_BIAS); }
	// 投到阴影相机，不做边缘压缩。
	vec3 ShadowScreenPos_From_WorldPos(vec3 worldPos){ return gfx_shadow_screen_pos(worldPos, shadowModelViewEnd, shadowProjection); }
	// 投到阴影相机，不做边缘压缩；与上一个函数相同，名字保留原程序写法的差异。
	vec3 ShadowScreenPos_From_WorldPos_WithoutZScaling(vec3 worldPos){ return gfx_shadow_screen_pos(worldPos, shadowModelViewEnd, shadowProjection); }
	// 对已经算好的阴影图坐标再补一次边缘压缩，读取端补压缩用。
	vec2 DistortShadowScreenPos(vec2 shadowPos){ return gfx_distort_shadow_pos(shadowPos, OMNI_SHADOW_MAP_BIAS); }
#else // 主世界与下界：使用加载器给的普通阴影相机矩阵。
	// 投到阴影相机并做边缘压缩，压缩让阴影图边缘分辨率更高。
	vec3 ShadowScreenPos_From_WorldPos_Distorted(vec3 worldPos){ return gfx_shadow_screen_pos_distorted(worldPos, shadowModelView, shadowProjection, OMNI_SHADOW_MAP_BIAS); }
	// 投到阴影相机，不做边缘压缩。
	vec3 ShadowScreenPos_From_WorldPos(vec3 worldPos){ return gfx_shadow_screen_pos(worldPos, shadowModelView, shadowProjection); }
	// 投到阴影相机，不做边缘压缩；与上一个函数相同，名字保留原程序写法的差异。
	vec3 ShadowScreenPos_From_WorldPos_WithoutZScaling(vec3 worldPos){ return gfx_shadow_screen_pos(worldPos, shadowModelView, shadowProjection); }
	// 对已经算好的阴影图坐标再补一次边缘压缩，读取端补压缩用。
	vec2 DistortShadowScreenPos(vec2 shadowPos){ return gfx_distort_shadow_pos(shadowPos, OMNI_SHADOW_MAP_BIAS); }
#endif // 末地与主世界的坐标函数二选一结束。

// 可变半影阴影按深度比较采样 `shadowtex1`（`sampler2DShadow`），只有把它声明为比较采样器的程序才编译这一段：
// 合成零号声明 `sampler2DShadow`，其它程序（延迟、后期、合成一/二/五）把 `shadowtex1` 当普通深度贴图用。
// 不隔开会让这些程序按普通采样器读到该函数，编译失败。由引入它的程序定义 `OMNI_SHADOW_COMPARE`。
#ifdef OMNI_SHADOW_COMPARE
// --- 不透明表面阴影：可变半影 + 彩色半透明阴影 + 次表面散射 ---
// 输入是相机相对世界位置、世界法线、阳光漫反射项、底色、透光强度与材质类别；输出阴影可见度，并带回次表面散射颜色。
// 为什么先做透光散射：叶片、草这类薄片本身就透光，先算透光再把阳光按透光比例削弱，阴影才不会在薄片上过硬。
// 为什么阴影图外坐标直接放弃采样：半影采样会跑出阴影图边界，硬读边界会把边界压成一条黑线。
vec3 VariablePenumbraShadow(vec3 worldPos, vec3 worldNormal, float sunlight, vec3 albedo, float scatteringStrength, MaterialMask mask, out vec3 sss){
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动，抗锯齿会把噪点平均掉。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
		#if OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都关了时间抗锯齿时改用固定噪声。
			if (mask.hand > 0.5 || mask.entityPlayer > 0.5) noise = BlueNoise(); // 这两类像素不靠时间累积，固定噪声避免闪烁。
		#else
			#if OMNI_DISABLE_HAND_TAA // 只关手的抗锯齿。
				if (mask.hand > 0.5) noise = BlueNoise(); // 手部像素用固定噪声。
			#endif
			#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只关玩家的抗锯齿。
				if (mask.entityPlayer > 0.5) noise = BlueNoise(); // 玩家像素用固定噪声。
			#endif
		#endif
	#else // 不开时间抗锯齿时只能固定噪声。
		vec2 noise = BlueNoise(); // 按像素平铺的固定蓝噪声。
	#endif
	float sssPhase = 0.0; // 朝向透光用的米氏相位。
	#if OMNI_SSS_NORMAL // 开启朝向透光时才需要算相位。
		sssPhase = MiePhaseFunction(0.5, dot(worldNormal, -worldShadowVector)); // 逆光方向更亮。
	#endif
	#ifdef OMNI_END // 末地阴影相机单独一套矩阵。
		mat4 shadowView = shadowModelViewEnd; // 末地阴影相机视图。
	#else // 主世界与下界用加载器矩阵。
		mat4 shadowView = shadowModelView; // 普通阴影相机视图。
	#endif
	return gfx_variable_penumbra_shadow(worldPos, worldNormal, sunlight, albedo, scatteringStrength,
		mask.hand, mask.leaves, mask.grass, gbufferModelViewInverse[3].xyz, gbufferModelViewInverse[2].xyz,
		shadowView, shadowProjection, shadowtex0, shadowtex1, shadowcolor0, shadowMapResolution, shadowDistance,
		far, OMNI_SHADOW_MAP_BIAS, noise, bool(OMNI_VARIABLE_PENUMBRA_SHADOWS), bool(OMNI_COLORED_SHADOWS),
		bool(OMNI_SSS_NORMAL), OMNI_SSS_BRIGHTNESS, sssPhase, OMNI_SSS_QUALITY, OMNI_VPS_QUALITY,
		OMNI_VPS_SPREAD, OMNI_SHADOW_BASIC_BLUR, sss); // 采样循环全部在通用库。
}

#endif // 可变半影阴影结束，只由声明比较采样器的程序编译。

// 屏幕空间阴影。
#include "/rendering/shadow/screen_shadow.glsl"
// 水下焦散。
#include "/rendering/shadow/water_caustics.glsl"
#endif // OMNI_RENDER_SHADOW_SHADOW_INCLUDED
