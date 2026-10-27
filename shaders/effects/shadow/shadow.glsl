/*
效果文件 `effects/shadow/shadow.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shadow/shadow.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_SHADOW_SHADOW_INCLUDED
#define OMNI_EFFECT_SHADOW_SHADOW_INCLUDED
// @effect {"label":{"zh_cn":"阴影","en_us":"Shadows"}}
// @option {"label":{"zh_cn":"图投影偏差","en_us":"Shadow map bias"},"description":{"zh_cn":"阴影相机把边缘坐标向内收的程度；调大能减轻阴影边抖动，但远处阴影会略微缩小。","en_us":"How far shadow coordinates are pulled inward near the edge; larger hides edge wobble but slightly shrinks far shadows."},"slider":true}
#define OMNI_SHADOW_MAP_BIAS 0.9 // [0.0 0.1 0.7 0.75 0.8 0.85 0.9 0.92 0.94 0.96]
// @option {"label":{"zh_cn":"可变半影","en_us":"Variable penumbra"},"description":{"zh_cn":"按遮挡物远近自动调软阴影边缘：遮挡物离得远影子边更软，贴近时更锐。","en_us":"Widens shadow edges with the distance to the occluder, so far shadows are softer and near ones stay sharp."}}
#define OMNI_VARIABLE_PENUMBRA_SHADOWS 1 // [0 1]
// @option {"label":{"zh_cn":"基础模糊","en_us":"Shadow basic blur"},"description":{"zh_cn":"影子边缘的基础模糊量；调大整体更软，调小更锐。","en_us":"Base blur of the shadow edge; higher is softer overall."},"slider":true}
#define OMNI_SHADOW_BASIC_BLUR 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]
// @option {"label":{"zh_cn":"半影采样数","en_us":"Penumbra samples"},"description":{"zh_cn":"可变半影每像素的采样次数；越大边缘越干净也越耗性能。","en_us":"Samples per pixel for the penumbra; higher is cleaner but costlier."}}
#define OMNI_VPS_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"半影扩散","en_us":"Penumbra spread"},"description":{"zh_cn":"阴影边缘往外散开的宽度；调大半影更宽、影子更柔和。","en_us":"How wide the shadow edge spreads; larger gives a wider, softer penumbra."},"slider":true}
#define OMNI_VPS_SPREAD 0.1 // [0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"彩色半透明阴影","en_us":"Colored translucent shadows"},"description":{"zh_cn":"半透明方块用自身颜色给影子染色，例如有色玻璃投出同色的影子。","en_us":"Translucent blocks tint the shadow by their own color, such as stained glass casting a matching shadow."}}
#define OMNI_COLORED_SHADOWS 1 // [0 1]
// @option {"label":{"zh_cn":"屏幕阴影","en_us":"Screen space shadows"},"description":{"zh_cn":"补充阴影图覆盖不到的近处细节；关掉后植物等薄片可能出现漏光。","en_us":"Adds nearby detail the shadow map cannot cover; turning it off may cause light leaking through thin geometry."}}
#define OMNI_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"玩家关闭屏幕阴影","en_us":"Player screen shadows"},"description":{"zh_cn":"避免玩家自己身上出现屏幕空间阴影，减少第三人称下的错误暗块。","en_us":"Skips screen space shadows on the player to avoid wrong dark patches in third person."}}
//#define OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"透光采样数","en_us":"Subsurface samples"},"description":{"zh_cn":"叶片、草等透光材质每像素的散射采样次数；越大越干净也越耗性能。","en_us":"Scattering samples per pixel for translucent surfaces like leaves and grass; higher is cleaner but costlier."}}
#define OMNI_SSS_QUALITY 6 // [2 3 4 6 8 12 16 24 32]
// @option {"label":{"zh_cn":"透光亮度","en_us":"Translucency brightness"},"description":{"zh_cn":"阳光透过叶片、草时漏出的亮度；调大透光更明显。","en_us":"How bright sunlight glows through leaves and grass; larger makes the translucency stronger."},"slider":true}
#define OMNI_SSS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"焦散亮度","en_us":"Caustics brightness"},"description":{"zh_cn":"水面焦散花纹的整体亮度倍率，一为不变；来源 Eclipse `settings.glsl:999` 的 `WATER_CAUSTICS_BRIGHTNESS`。","en_us":"Overall brightness multiplier of the water caustics pattern; one is unchanged. From Eclipse `settings.glsl:999` `WATER_CAUSTICS_BRIGHTNESS`."},"slider":true}
#define OMNI_WATER_CAUSTICS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"焦散对比","en_us":"Caustics power"},"description":{"zh_cn":"水面焦散花纹的对比指数，越大亮纹越集中、暗处越暗；一为不变。来源 Eclipse `settings.glsl:1000` 的 `WATER_CAUSTICS_POWER`。","en_us":"Contrast exponent of the water caustics pattern; larger concentrates the bright veins and darkens the rest; one is unchanged. From Eclipse `settings.glsl:1000` `WATER_CAUSTICS_POWER`."},"slider":true}
#define OMNI_WATER_CAUSTICS_POWER 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.2 3.4 3.6 3.8 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"透光朝向","en_us":"Directional translucency"},"description":{"zh_cn":"让透过的光随观察角度变化，逆光看叶片时更亮。","en_us":"Makes the light through leaves vary with view angle, brighter when backlit."}}
#define OMNI_SSS_NORMAL 0 // [0 1]
// @option {"label":{"zh_cn":"远景透光（透光）","en_us":"Distant SSS"},"description":{"zh_cn":"让远景地形的叶片与雪像近景一样透光；关闭后远景叶片与雪不透光，影子更硬。默认开启，与原来一致。来源 Eclipse 的 DH_SUBSURFACE_SCATTERING。","en_us":"Lets distant leaves and snow pass light like nearby ones; when off they stop being translucent and shadows get harder. On by default. Ports Eclipse's DH_SUBSURFACE_SCATTERING."}}
#define OMNI_DH_SSS 1 // [0 1]
// @option {"label":{"zh_cn":"远景进阴影","en_us":"Distant terrain in shadows"},"description":{"zh_cn":"让远景地形也投进阴影图，远处山体才能挡住阳光。","en_us":"Casts distant terrain into the shadow map so far hills can block sunlight."}}
//#define OMNI_DH_SHADOW
// @option {"label":{"zh_cn":"远景阴影剔除","en_us":"Distant shadow culling"},"description":{"zh_cn":"剔除阴影图里被近处地形挡住、看不到的远景块，省性能；极端情况下可能出现阴影缺口。","en_us":"Culls distant chunks hidden behind near terrain in the shadow map to save cost; may rarely cut a shadow."}}
#define OMNI_DH_SHADOW_CULLING 1 // [0 1]
// @option {"label":{"zh_cn":"远景阴影伪影修复","en_us":"Distant shadow fix"},"description":{"zh_cn":"修正远景地形投出的颗粒状阴影伪影。","en_us":"Fixes grainy shadow artifacts cast by distant terrain."}}
#define OMNI_DH_SHADOW_FIX
// Iris 原生阴影分辨率常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"分辨率","en_us":"Shadow resolution"},"description":{"zh_cn":"Iris 直接读取该原生常量并分配阴影纹理；越高影子越清晰也越占显存。","en_us":"Iris reads this native constant to allocate the shadow texture; higher is sharper and uses more VRAM."},"values":{"1024":{"zh_cn":"低","en_us":"Low"},"2048":{"zh_cn":"中","en_us":"Medium"},"4096":{"zh_cn":"高","en_us":"High"}}}
const int shadowMapResolution = 2048; // [1024 2048 4096 8192 16384 32768]
// Iris 原生阴影距离常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"距离","en_us":"Shadow distance"},"description":{"zh_cn":"Iris 直接读取该原生常量并设置阴影覆盖范围，单位米。","en_us":"Iris reads this native constant to set the shadow range in meters."},"values":{"64.0":{"zh_cn":"近","en_us":"Near"},"128.0":{"zh_cn":"中","en_us":"Medium"},"192.0":{"zh_cn":"远","en_us":"Far"},"256.0":{"zh_cn":"极远","en_us":"Very far"}}}
const float shadowDistance = 192.0; // [64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0 1536.0 2048.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
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
#include "/effects/shadow/screen_shadow.glsl"
// 水下焦散。
#include "/effects/shadow/water_caustics.glsl"
#endif // OMNI_EFFECT_SHADOW_SHADOW_INCLUDED
