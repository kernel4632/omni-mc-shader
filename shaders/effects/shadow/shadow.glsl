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
  `ivec2 texelCoord`、`vec2 texCoord` 由延迟与合成主程序声明；`MaterialMask` 结构由 `effects/material.glsl` 提供；
  `OMNI_TAA`、`OMNI_DISABLE_HAND_TAA`、`OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR` 由 `effects/antialiasing.glsl` 提供。
关键设计原因与取舍：
  坐标变换与遮挡查询分成两层，写入端只复用变换、不引入深度采样，读取端只关心比较，职责不混；
  主世界与末地用不同的阴影相机矩阵，编译期二选一，运行时不再多一次分支；
  全局量按原程序依赖调用方已声明，本文件不重复声明，避免与主程序重复定义一个输入而导致编译失败。
*/
#ifndef OMNI_SHADOW_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_SHADOW_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"阴影","en_us":"Shadows"}}
// @option {"label":{"zh_cn":"阴影图投影偏差","en_us":"Shadow map bias"},"description":{"zh_cn":"阴影相机把边缘坐标向内收的程度；调大能减轻阴影边抖动，但远处阴影会略微缩小。","en_us":"How far shadow coordinates are pulled inward near the edge; larger hides edge wobble but slightly shrinks far shadows."},"slider":true}
#define OMNI_SHADOW_MAP_BIAS 0.9 // [0.0 0.1 0.7 0.75 0.8 0.85 0.9 0.92 0.94 0.96]
// @option {"label":{"zh_cn":"可变半影","en_us":"Variable penumbra"},"description":{"zh_cn":"按遮挡物远近自动调软阴影边缘：遮挡物离得远影子边更软，贴近时更锐。","en_us":"Widens shadow edges with the distance to the occluder, so far shadows are softer and near ones stay sharp."}}
#define OMNI_VARIABLE_PENUMBRA_SHADOWS
// @option {"label":{"zh_cn":"阴影基础模糊","en_us":"Shadow basic blur"},"description":{"zh_cn":"影子边缘的基础模糊量；调大整体更软，调小更锐。","en_us":"Base blur of the shadow edge; higher is softer overall."},"slider":true}
#define OMNI_SHADOW_BASIC_BLUR 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0]
// @option {"label":{"zh_cn":"半影采样数","en_us":"Penumbra samples"},"description":{"zh_cn":"可变半影每像素的采样次数；越大边缘越干净也越耗性能。","en_us":"Samples per pixel for the penumbra; higher is cleaner but costlier."}}
#define OMNI_VPS_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"半影扩散","en_us":"Penumbra spread"},"description":{"zh_cn":"阴影边缘往外散开的宽度；调大半影更宽、影子更柔和。","en_us":"How wide the shadow edge spreads; larger gives a wider, softer penumbra."},"slider":true}
#define OMNI_VPS_SPREAD 0.1 // [0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"彩色半透明阴影","en_us":"Colored translucent shadows"},"description":{"zh_cn":"半透明方块用自身颜色给影子染色，例如有色玻璃投出同色的影子。","en_us":"Translucent blocks tint the shadow by their own color, such as stained glass casting a matching shadow."}}
#define OMNI_COLORED_SHADOWS
// @option {"label":{"zh_cn":"屏幕空间阴影","en_us":"Screen space shadows"},"description":{"zh_cn":"补充阴影图覆盖不到的近处细节；关掉后植物等薄片可能出现漏光。","en_us":"Adds nearby detail the shadow map cannot cover; turning it off may cause light leaking through thin geometry."}}
#define OMNI_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"玩家关闭屏幕阴影","en_us":"Player screen shadows"},"description":{"zh_cn":"避免玩家自己身上出现屏幕空间阴影，减少第三人称下的错误暗块。","en_us":"Skips screen space shadows on the player to avoid wrong dark patches in third person."}}
//#define OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
// @option {"label":{"zh_cn":"次表面散射采样数","en_us":"Subsurface samples"},"description":{"zh_cn":"叶片、草等透光材质每像素的散射采样次数；越大越干净也越耗性能。","en_us":"Scattering samples per pixel for translucent surfaces like leaves and grass; higher is cleaner but costlier."}}
#define OMNI_SSS_QUALITY 6 // [2 3 4 6 8 12 16 24 32]
// @option {"label":{"zh_cn":"透光亮度","en_us":"Translucency brightness"},"description":{"zh_cn":"阳光透过叶片、草时漏出的亮度；调大透光更明显。","en_us":"How bright sunlight glows through leaves and grass; larger makes the translucency stronger."},"slider":true}
#define OMNI_SSS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"透光朝向","en_us":"Directional translucency"},"description":{"zh_cn":"让透过的光随观察角度变化，逆光看叶片时更亮。","en_us":"Makes the light through leaves vary with view angle, brighter when backlit."}}
//#define OMNI_SSS_NORMAL
// @option {"label":{"zh_cn":"远景进阴影","en_us":"Distant terrain in shadows"},"description":{"zh_cn":"让远景地形也投进阴影图，远处山体才能挡住阳光。","en_us":"Casts distant terrain into the shadow map so far hills can block sunlight."}}
//#define OMNI_DH_SHADOW
// @option {"label":{"zh_cn":"远景阴影剔除","en_us":"Distant shadow culling"},"description":{"zh_cn":"剔除阴影图里被近处地形挡住、看不到的远景块，省性能；极端情况下可能出现阴影缺口。","en_us":"Culls distant chunks hidden behind near terrain in the shadow map to save cost; may rarely cut a shadow."}}
#define OMNI_DH_SHADOW_CULLING
// @option {"label":{"zh_cn":"远景阴影伪影修复","en_us":"Distant shadow fix"},"description":{"zh_cn":"修正远景地形投出的颗粒状阴影伪影。","en_us":"Fixes grainy shadow artifacts cast by distant terrain."}}
#define OMNI_DH_SHADOW_FIX
// Iris 原生阴影分辨率常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"阴影分辨率","en_us":"Shadow resolution"},"description":{"zh_cn":"Iris 直接读取该原生常量并分配阴影纹理；越高影子越清晰也越占显存。","en_us":"Iris reads this native constant to allocate the shadow texture; higher is sharper and uses more VRAM."},"values":{"1024":{"zh_cn":"低","en_us":"Low"},"2048":{"zh_cn":"中","en_us":"Medium"},"4096":{"zh_cn":"高","en_us":"High"}}}
const int shadowMapResolution = 2048; // [1024 2048 4096 8192 16384 32768]
// Iris 原生阴影距离常量必须直接使用字面量，菜单范围仍从这一行唯一读取。
// @option {"label":{"zh_cn":"阴影距离","en_us":"Shadow distance"},"description":{"zh_cn":"Iris 直接读取该原生常量并设置阴影覆盖范围，单位米。","en_us":"Iris reads this native constant to set the shadow range in meters."},"values":{"64.0":{"zh_cn":"近","en_us":"Near"},"128.0":{"zh_cn":"中","en_us":"Medium"},"192.0":{"zh_cn":"远","en_us":"Far"},"256.0":{"zh_cn":"极远","en_us":"Very far"}}}
const float shadowDistance = 192.0; // [64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0 1536.0 2048.0]

// 深度与屏幕坐标换算给屏幕空间阴影用，共用计算提供颜色曲线与相位函数，蓝噪声提供采样抖动。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
#include "/common/noise.glsl"

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
	vec3 ShadowScreenPos_From_WorldPos_Distorted(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelViewEnd) * worldPos + shadowModelViewEnd[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    float dist = length(shadowPos.xy); // 到阴影图中心的距离，用来决定压缩强度。
	    float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 边缘压缩系数，中心为一。
	    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩，零点九五留出边界余量。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 投到阴影相机，不做边缘压缩。
	vec3 ShadowScreenPos_From_WorldPos(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelViewEnd) * worldPos + shadowModelViewEnd[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 投到阴影相机，不做边缘压缩；与上一个函数相同，名字保留原程序写法的差异。
	vec3 ShadowScreenPos_From_WorldPos_WithoutZScaling(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelViewEnd) * worldPos + shadowModelViewEnd[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 对已经算好的阴影图坐标再补一次边缘压缩，读取端补压缩用。
	vec2 DistortShadowScreenPos(vec2 shadowPos){
	    shadowPos = shadowPos * 2.0 - 1.0; // 零到一先转回负一到一。
	    float dist = length(shadowPos.xy); // 到中心距离。
	    float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 与写入端同一压缩系数。
	    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
	    return shadowPos * 0.5 + 0.5; // 再转回零到一。
	}
#else // 主世界与下界：使用加载器给的普通阴影相机矩阵。
	// 投到阴影相机并做边缘压缩，压缩让阴影图边缘分辨率更高。
	vec3 ShadowScreenPos_From_WorldPos_Distorted(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelView) * worldPos + shadowModelView[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    float dist = length(shadowPos.xy); // 到阴影图中心的距离，用来决定压缩强度。
	    float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 边缘压缩系数，中心为一。
	    shadowPos.xy *= 0.95 / distortFactor; // 向内压缩，零点九五留出边界余量。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 投到阴影相机，不做边缘压缩。
	vec3 ShadowScreenPos_From_WorldPos(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelView) * worldPos + shadowModelView[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 投到阴影相机，不做边缘压缩；与上一个函数相同，名字保留原程序写法的差异。
	vec3 ShadowScreenPos_From_WorldPos_WithoutZScaling(vec3 worldPos){
	    vec3 shadowPos = mat3(shadowModelView) * worldPos + shadowModelView[3].xyz; // 世界位置转到阴影相机视空间。
	    shadowPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。
	    return shadowPos * 0.5 + 0.5; // 负一到一转成零到一的纹理坐标。
	}
	// 对已经算好的阴影图坐标再补一次边缘压缩，读取端补压缩用。
	vec2 DistortShadowScreenPos(vec2 shadowPos){
	    shadowPos = shadowPos * 2.0 - 1.0; // 零到一先转回负一到一。
	    float dist = length(shadowPos.xy); // 到中心距离。
	    float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 与写入端同一压缩系数。
	    shadowPos *= 0.95 / distortFactor; // 同一压缩量。
	    return shadowPos * 0.5 + 0.5; // 再转回零到一。
	}
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
	worldPos += gbufferModelViewInverse[3].xyz; // 相机相对世界位置补上相机位置，换成阴影相机能用的世界坐标。
	worldPos -= gbufferModelViewInverse[2].xyz * 0.5 * mask.hand; // 手持物抬高半格，避免手贴脸时投出错误的自阴影。

	#ifdef OMNI_END // 末地阴影相机单独一套矩阵。
		vec3 shadowNormal = mat3(shadowModelViewEnd) * worldNormal; // 世界法线转到末地阴影相机空间。
		shadowNormal.z = -shadowNormal.z; // 深度轴与视空间相反，翻转过来比较方向才正确。
		vec3 shadowScreenPos = mat3(shadowModelViewEnd) * worldPos + shadowModelViewEnd[3].xyz; // 世界位置转到末地阴影相机空间。
	#else // 主世界与下界用加载器矩阵。
		vec3 shadowNormal = mat3(shadowModelView) * worldNormal; // 世界法线转到阴影相机空间。
		shadowNormal.z = -shadowNormal.z; // 深度轴翻转。
		vec3 shadowScreenPos = mat3(shadowModelView) * worldPos + shadowModelView[3].xyz; // 世界位置转到阴影相机空间。
	#endif
	shadowScreenPos *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按投影缩放，深度取半。

	float zScale = 1.0 / shadowProjection[0][0]; // 深度缩放倒数，把深度差还原成实际距离。
	float dist = length(shadowScreenPos.xy); // 到阴影图中心的距离。
	float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 边缘压缩系数，与坐标变换一致。

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动，抗锯齿会把噪点平均掉。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
		#if defined OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都关了时间抗锯齿时改用固定噪声。
			if (mask.hand > 0.5 || mask.entityPlayer > 0.5) noise = BlueNoise(); // 这两类像素不靠时间累积，固定噪声避免闪烁。
		#else
			#ifdef OMNI_DISABLE_HAND_TAA // 只关手的抗锯齿。
				if (mask.hand > 0.5) noise = BlueNoise(); // 手部像素用固定噪声。
			#endif
			#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只关玩家的抗锯齿。
				if (mask.entityPlayer > 0.5) noise = BlueNoise(); // 玩家像素用固定噪声。
			#endif
		#endif
	#else // 不开时间抗锯齿时只能固定噪声。
		vec2 noise = BlueNoise(); // 按像素平铺的固定蓝噪声。
	#endif

	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 每步旋转黄金角，样本沿螺旋散开避免规则条纹。

	vec3 result = vec3(1.0); // 阴影可见度，初值全亮。

	sss = vec3(0.0); // 次表面散射初值为零。

	if (scatteringStrength > 0.0){ // 只有透光材质才走散射，普通表面直接跳过整段。
		vec3 shadowScreenPosRaw = shadowScreenPos; // 未压缩坐标，散射采样要用。
		shadowScreenPosRaw.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
		shadowScreenPosRaw = shadowScreenPosRaw * 0.5 + 0.5; // 转成零到一纹理坐标。

		float spread = (scatteringStrength * 0.12 + 0.05) / (distortFactor * shadowDistance) + OMNI_SHADOW_BASIC_BLUR / shadowMapResolution; // 散射采样半径：透光越强、距离越远越大，再加基础模糊。
		vec3 scatteringDensity = 15.0 / (scatteringStrength * albedo + 0.1); // 散射密度：底色的透光通道越大越容易透过。

		const float steps = OMNI_SSS_QUALITY; // 散射采样次数来自选项。
		const float rSteps = 1.0 / steps; // 次数的倒数，用来归一化半径与结果。

		float angle = noise.x * TAU; // 初始角度也取随机，避免所有像素从同一方向起步。
		vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。

		float scatteringDepth = 0.0; // 累计散射深度。

		for (float i = 0.0; i < steps; i++){ // 逐次采样阴影图，累计遮挡厚度。
			rot *= rotMat; // 每步旋转黄金角。
			float radius = (i + noise.y) * rSteps; // 半径从随机相位起步，样本不重叠。
			vec2 offset = rot * spread * radius; // 当前采样偏移。

			float sampleDepth = textureLod(shadowtex0, shadowScreenPosRaw.xy + offset, 0.0).x; // 读取该点遮挡深度。

			scatteringDepth += max(shadowScreenPosRaw.z - sampleDepth, 1e-5); // 累加接收点到遮挡物的距离，最小留一点避免零。
		}
		scatteringDepth *= rSteps * zScale; // 取平均并还原成实际距离。

		vec3 scattering = exp2(-scatteringDepth * scatteringDensity); // 厚度越大透光越弱，指数衰减。

		float distFalloff = saturate(((min(shadowDistance, far) - length(worldPos)) * 0.05 - 1.0)); // 超出阴影范围就淡出透光。

		#ifdef OMNI_SSS_NORMAL // 开启朝向透光时按观察角计算。
			sss = scattering * (OMNI_SSS_BRIGHTNESS * distFalloff * (MiePhaseFunction(0.5, dot(worldNormal, -worldShadowVector)) * 0.5 + 0.15)); // 逆光方向更亮的米氏相位。
		#else // 关闭朝向透光时用固定亮度。
			sss = scattering * (OMNI_SSS_BRIGHTNESS * distFalloff * 0.2); // 固定占比，不随角度变化。
		#endif

		scatteringStrength *= distFalloff; // 阳光也按同一淡出缩放，远处不再额外透光。
	}

	if (sunlight > 0.0){ // 没有阳光时不必采样阴影。
		shadowScreenPos += shadowNormal * (0.002 * (1.0 - mask.leaves) * distortFactor); // 沿法线抬一点减少自身条纹，叶片不抬以免漏光。
		shadowScreenPos.xy *= 0.95 / distortFactor; // 补上与写入端一致的边缘压缩。
		shadowScreenPos = shadowScreenPos * 0.5 + 0.5; // 转成零到一纹理坐标。

		if (saturate(shadowScreenPos.xy) == shadowScreenPos.xy){ // 只在阴影图内采样，图外保持全亮。
			result = vec3(0.0); // 从全暗开始累加可见样本。

			float spread = OMNI_VPS_SPREAD * 200.0 / (distortFactor * shadowDistance); // 半影搜索半径：随扩散选项与距离缩放。

			float avgDiff = 0.0; // 遮挡物与接收点的平均深度差，用来放大半影。

			#ifdef OMNI_VARIABLE_PENUMBRA_SHADOWS // 可变半影：先估遮挡物距离再决定边缘宽度。
				float spreadLod = log2(shadowMapResolution / 512.0); // 按分辨率选取合适的纹理细节层级，高分辨率用更粗层级抑制噪点。
				for (int i = -1; i <= 1; i++){ // 三乘三邻域估计遮挡物距离。
					for (int j = -1; j <= 1; j++){
						vec2 lookupCoord = shadowScreenPos.xy + vec2(i, j) * spread * 0.0039; // 邻域采样坐标。
						float depthDiff = shadowScreenPos.z - textureLod(shadowtex0, lookupCoord, spreadLod).x; // 接收点深度减去遮挡物深度。
						depthDiff = clamp(depthDiff * zScale * 0.0035, 0.0, 0.025); // 归一化并限制范围。
						avgDiff += depthDiff * depthDiff; // 平方累加，后面开根得到均方根。
					}
				}

				avgDiff /= 9.0; // 求九个样本的平均。
				avgDiff = sqrt(avgDiff); // 开根得到平均深度差。
			#endif

			avgDiff = max(avgDiff, 0.015 * mask.leaves + 0.01 * mask.grass); // 叶片与草至少给一点半影，避免薄片边缘过硬。

			float sampleSpread = avgDiff * 0.2 * spread + OMNI_SHADOW_BASIC_BLUR / shadowMapResolution; // 最终采样半径：深度差越大半影越宽，再加基础模糊。

			shadowScreenPos.z -= (2e-6 + noise.y * 2e-6) * (dist + 0.03) * (1.0 - 0.9 * mask.leaves) * shadowDistance; // 深度偏移随距离增大，抵消阴影图分辨率不足带来的条纹。

			const float steps = OMNI_VPS_QUALITY; // 半影采样次数来自选项。
			const float rSteps = 1.0 / steps; // 次数倒数。

			float angle = noise.y * TAU; // 初始角度取随机。
			vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。

			for (float i = 0.0; i < steps; i++){ // 逐次采样阴影图求未遮挡比例。
				rot *= rotMat; // 每步旋转黄金角。
				float radius = sqrt((i + noise.x) * rSteps); // 平方根半径让样本在圆面上均匀分布。
				vec2 offset = rot * radius * sampleSpread; // 当前采样偏移。

				vec3 sampleCoord = vec3(shadowScreenPos.xy + offset, shadowScreenPos.z); // 采样坐标。

				#ifdef OMNI_COLORED_SHADOWS // 彩色阴影：半透明层用自身颜色，实心层只按遮挡。
					float translucentShadow = step(sampleCoord.z, textureLod(shadowtex0, sampleCoord.xy, 0.0).x); // 半透明阴影：深度更远即未遮挡。
					result += vec3(translucentShadow); // 半透明部分累加可见度。

					float soildShadow = textureLod(shadowtex1, sampleCoord, 0.0); // 实心阴影贴图：含彩色阴影的合成结果。
					vec3 shadowColorSample = GammaToLinear(textureLod(shadowcolor0, sampleCoord.xy, 0.0).rgb); // 该点半透明颜色转线性。
					result += shadowColorSample * (soildShadow - translucentShadow); // 实心与半透明之差乘颜色，得到彩色阴影贡献。
				#else // 关闭彩色阴影时只按实心遮挡。
					float soildShadow = textureLod(shadowtex1, sampleCoord, 0.0); // 实心阴影贴图。
					result += vec3(soildShadow); // 直接累加可见度。
				#endif
			}
			result *= rSteps; // 取平均得到最终可见度。
		}
	}

	#ifdef OMNI_SSS_NORMAL // 开启朝向透光时，用透光比例把阴影往亮处提一点。
		return result * (saturate(0.4 - scatteringStrength * 0.4) + 0.6); // 透光越强整体越亮。
	#else
		return result * (saturate(0.5 - scatteringStrength * 0.5) + 0.5); // 关闭时提亮幅度更小。
	#endif
}

#endif // 可变半影阴影结束，只由声明比较采样器的程序编译。

// --- 屏幕空间阴影：在屏幕里沿阳光方向找遮挡，补阴影图覆盖不到的近处细节 ---
// 输入是视空间位置、视线方向与视空间法线；沿阳光在屏幕上的投影方向步进，撞到比当前更近的几何就累加遮挡。
// 为什么叶片先用饱和放大：叶片的材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
float ScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, MaterialMask mask, vec3 shadowVector){
	mask.leaves = saturate(mask.leaves * 1e10); // 把叶片标记归一到零或一。

	float fov = mask.grass + mask.leaves > 0.5 ? 95.0 : atan(1.0 / gbufferProjection[1][1]) * 360.0 * rPI; // 草和叶片按较大视野估计，其余由投影反推真实视野。

	vec3 viewRayDir = shadowVector * max(-viewPos.z * 3e-5 * fov, 0.06 * shadowDistance / shadowMapResolution); // 每一步在屏幕上的推进量，随深度与视野缩放并留最小步长。

	vec3 start = viewPos; // 步进起点。

	if (mask.grass + mask.leaves < 0.1){ // 普通表面才做偏移，草和叶片的画面已经足够软。
		float pixelScale = max(pixelSize.x, pixelSize.y); // 一个像素的最大边长，用来把偏移量折算到屏幕。
		float NdotL = saturate(dot(shadowVector, normal)); // 阳光与法线的夹角。

		start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿光线先跳过一段，避免刚出发就打到自己。
		start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(NdotL, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
	}

	vec3 end = start + viewRayDir; // 一步的终点。

	start = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
	end   = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * end.xy,   -end.z); // 终点同样投影。

	vec3 screenRayDir = (end - start); // 这一步在裁剪空间的位移。
	screenRayDir.xy *= 0.5; // 横纵方向换算到零到一坐标。

	start.xy += gbufferProjection[3].xy; // 补上投影的平移项。
	start.xy *= 0.5; // 裁剪空间转到零到一。

	start += screenRayDir * mask.grass; // 草的原点再前进一小段，减少草自身投出的错误阴影。

	float absorption = 0.0; // 一次遮挡的吸收量。
	absorption += 0.7 * mask.grass; // 草的吸收系数。
	absorption += 0.85 * mask.leaves; // 叶片的吸收更强。
	absorption = pow(absorption, sqrt(-viewPos.z) * 0.5); // 距离越远吸收越弱，远处几何不再压黑。

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float noise = BlueNoiseTemporal().x; // 每帧变化的抖动。
		#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
			if (mask.entityPlayer > 0.5) noise = BlueNoise().x; // 玩家像素改用固定噪声。
		#endif
		vec2 offsetCoord = 0.5 + taaJitter * 0.5; // 采样坐标补上本帧抖动。
	#else // 不开时间抗锯齿时固定噪声。
		float noise = BlueNoise().x; // 固定噪声。
		vec2 offsetCoord = vec2(0.5); // 不补抖动。
	#endif

	float shadow = 1.0; // 阴影可见度，初值全亮。
	float stepLength = 1.0; // 步长，逐步增大。
	float zThickness = 0.025 + 0.0125 * -viewPos.z; // 遮挡厚度阈值，距离越远越厚，避免远处噪点。

	for (int i = 0; i < 12; i++, start += screenRayDir * stepLength, stepLength += 0.3){ // 最多十二步，步长递增覆盖更远。
		vec3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。
		samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。

		if (saturate(samplePos.xy) != samplePos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。

		#ifdef DISTANT_HORIZONS // 有远景时先看近景深度，近景是天空才查远景。
			float sampleDepth = textureLod(depthtex1, samplePos.xy, 0.0).x; // 近景深度。
			float sampleDist = 0.0; // 采样点距离。

			if (sampleDepth == 1.0){ // 近景是天空。
				sampleDepth = textureLod(dhDepthTex1, samplePos.xy, 0.0).x; // 改读远景深度。
				sampleDist = LinearDepth_From_ScreenDepth_DH(sampleDepth); // 远景深度换成距离。
			}else{
				sampleDist = LinearDepth_From_ScreenDepth(sampleDepth); // 近景深度换成距离。
			}
		#else
			float sampleDist = LinearDepth_From_ScreenDepth(textureLod(depthtex1, samplePos.xy, 0.0).x); // 直接把深度换成距离。
		#endif

		float depthDiff = samplePos.z - sampleDist; // 当前射线深度与几何深度之差，为正说明几何在前面。

		if (depthDiff > 0.0 && depthDiff < zThickness) shadow *= absorption; // 落在厚度阈值内才算遮挡。

		if (shadow < 0.01) break; // 已经足够暗，提前结束。
	}

	return shadow; // 返回可见度。
}

// --- 焦散法线：从七号画面的方块里读出波法线 ---
// 七号画面左下角最多五百像素见方，存的是水面波法线；读取时用折射方向把世界位置投到这个方块里。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
vec3 GetWavesNormalFromTex(vec3 position, vec3 shadowLightVector){
	const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。

	vec2 coord = position.xz; // 先取水平坐标。
	vec3 lightVector = refract(shadowLightVector, vec3(0.0, 1.0, 0.0), 1.0 / WATER_REFRACT_IOR); // 阳光按水面折射率弯折得到光线方向。
	coord.x += position.y * lightVector.x / lightVector.y; // 按高度沿光线横移横坐标。
	coord.y += position.y * lightVector.z / lightVector.y; // 按高度沿光线横移纵坐标。

	coord *= 0.02; // 缩到波法线图的空间尺度。
	coord = fract(coord); // 平铺到零到一。

	coord *= pixelSize * min(screenSize.y, maxCausticsNormalHeight); // 折算成方块里的像素坐标。

	vec3 normal; // 解出的波法线。
	normal.xyz = DecodeNormal(textureLod(colortex7, coord, 0.0).xy); // 从方块里读八面体编码法线。

	return normal; // 返回世界空间波法线。
}

// --- 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹 ---
// 输入是相机相对世界位置；把阳光按水面折射后向水下投，用波面法线判断光线是否汇聚，汇聚处更亮。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
float CalculateWaterCaustics(vec3 worldPos, vec3 shadowLightVector){
	worldPos.xyz += cameraPosition; // 相机相对世界位置补上相机位置，换成绝对坐标。

	vec2 dither = BlueNoiseTemporal(); // 每帧变化的抖动，打散采样花纹。

	vec3 lookupCenter = worldPos + vec3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。

	vec3 lightVector = refract(shadowLightVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
	vec3 depthBias = vec3(worldPos.y * lightVector.x, 0.0, worldPos.y * lightVector.z) / lightVector.y; // 按水深沿光线偏移，找到水底对应位置。

	float caustics = 0.0; // 累计焦散强度。

	for (float i = -1.0; i <= 1.0; i++){ // 三乘三抖动采样。
		for (float j = -1.0; j <= 1.0; j++){
			vec2 offset = dither + vec2(i, j); // 当前采样偏移。

			vec3 lookupPoint = lookupCenter; // 这一处的波面查询点。
			lookupPoint.xz += offset * 0.1; // 按偏移横移。

			vec3 wavesNormal = GetWavesNormalFromTex(lookupPoint, shadowLightVector).xzy; // 读取波法线并换到竖直轴朝上的坐标。

			vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
			vec3 collisionPoint = lookupPoint - refractVector / refractVector.y; // 光线与水平面的交点。
			collisionPoint -= worldPos; // 相对当前位置。

			float dist = dot(collisionPoint, collisionPoint) * 7.1; // 交点距离的平方，放大差距。

			caustics += 1.0 - saturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
		}
	}

	return mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(isEyeInWater)); // 拼成焦散亮度，水下再往全亮靠一点。
}
#endif // 文件守卫结束。
