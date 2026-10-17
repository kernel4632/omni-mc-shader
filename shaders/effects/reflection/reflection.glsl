/*
屏幕空间反射：照 iterationT `Lib/IndividualFounctions/Reflections/SSR.glsl`、
`Reflections/ReflectionFilter.glsl` 与 `composite2.fsh`、`composite5.fsh` 的反射段一比一移植。
职责分成四块：
  一、玩家选项：光线步进质量、细化步数与深度差阈值，照 iterationT `Settings.glsl` 带取值范围的菜单项，全项目只在这里定义一次；
  二、屏幕空间追踪：`ScreenSpaceTracer` 沿反射方向在屏幕里找被反射到的几何，`sampleGGXVNDF` 给粗糙面抽样方向；
  三、反射合成：`CalculateSpecularReflections` 有重载两份，一份写三号画面（`composite2`），一份就地合并进场景色（`composite5`）；
  四、反射滤波：`AtrousWaveletFilter` 对三号画面做小波滤波，供 `composite3`、`composite4` 两次半径调用。
调用位置：
  `rendering/composite.glsl` 的 `composite2` 程序算反射并写三号画面；
  `rendering/composite.glsl` 的 `composite3`、`composite4` 程序对三号画面做小波滤波；
  `rendering/composite.glsl` 的 `composite5` 程序把三号画面的反射合并进场景色。
可复制示例：
  `compositeOutput3 = CalculateSpecularReflections(viewPos, worldPos, viewDir, normal, gbufferdepth, albedo, material, skylight, isHand, isSmooth, highlightStrength);`
  `CalculateSpecularReflections(color, viewDir, normal, albedo, waterAbsorption, material);`
  `AtrousWaveletFilter(reflectionData, viewPos, viewDir, normal, roughness, 40.0, vec2(0.0));`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `texelCoord`、`texCoord`、`gbufferModelViewInverse`、`gbufferProjection`、
  `worldSunVector`、`worldMoonVector`、`shadowVector`、`colorSunlight`、`colorMoonlight`、`colorShadowlight`、
  `timeNoon`、`wetness`、`eyeNoPrecipitationSmooth`、`isEyeInWater`、`far`、`colortex1`…`colortex5`、`depthtex0`、`depthtex1` 由合成主程序声明；
  本文件按阶段引入所需效果文件：`composite2` 引入雾与天空云反射，`composite5` 只引入材质，`composite3`/`composite4` 只引入坐标。
关键设计原因与取舍：
  原程序把 `ProjectSky` 写在 SSR 与天空两处，按合同只在 `effects/sky/sky.glsl` 保留一份，本文件直接调用；
  两份 `CalculateSpecularReflections` 参数不同、用途不同，原程序靠所在程序区分，这里按程序宏 `OMNI_COMPOSITE2_PASS`、`OMNI_COMPOSITE5_PASS` 分开，避免把只属于反射通道的采样编译进滤波通道；
  接近全反射的像素（`colortex1` 的 a 通道大于零点五）直接取当前场景色，避免反射处出现黑洞。
*/
#ifndef OMNI_REFLECTION_INCLUDED // 只引入一次，避免常数与函数重复定义。
#define OMNI_REFLECTION_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 玩家选项：光线步进质量、细化步数与深度差阈值，照 iterationT `Lib/Settings.glsl` 带取值范围的菜单项 ---
// @effect {"label":{"zh_cn":"反射","en_us":"Reflections"}}
// @option {"label":{"zh_cn":"光线步进质量","en_us":"Ray steps"},"description":{"zh_cn":"一次反射最多走多少步，越大越不容易漏掉远处几何，也更慢。","en_us":"Maximum steps per reflection ray; higher misses less distant geometry but is slower."},"slider":true}
#define OMNI_RAYTRACE_QUALITY 16 //[8 12 16 24 32 64 128 256 512]
// @option {"label":{"zh_cn":"细化步数","en_us":"Refinement steps"},"description":{"zh_cn":"命中后二分细化的次数，越大交点越准。原程序的范围注释缺右括号，这里补全。","en_us":"Bisection steps after a hit; higher is more accurate. The original range comment was missing its closing bracket, fixed here."},"slider":true}
#define OMNI_RAYTRACE_REFINEMENT_STEPS 5 //[2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]
// @option {"label":{"zh_cn":"深度差阈值","en_us":"Depth difference"},"description":{"zh_cn":"命中判定的相对深度差阈值，越小越严格。","en_us":"Relative depth-difference threshold for a hit; smaller is stricter."},"slider":true}
#define OMNI_RAYTRACE_ZDIFF_THRESHOLD 0.2 //[0.05 0.1 0.15 0.2 0.3 0.4 0.5]
// @option {"label":{"zh_cn":"远景反射","en_us":"Distant reflections"},"description":{"zh_cn":"让屏幕空间反射也能命中远景地形；关闭后反射只打到近景几何，远景处反射天空。默认开启，与原来一致。来源 Eclipse 的 DH_SCREENSPACE_REFLECTIONS。","en_us":"Lets screen-space reflections hit distant terrain; when off, rays only hit near geometry and reflect the sky over distant chunks. On by default. Ports Eclipse's DH_SCREENSPACE_REFLECTIONS."}}
#define OMNI_DH_SSR
// 数学提供光照模型与颜色曲线，坐标换算提供屏幕与视空间互转，两份都供三个通道共用。
#include "/common/math.glsl"
#include "/common/coordinates.glsl"

// --- composite2：屏幕空间反射与天空盒回退 ---
#ifdef OMNI_COMPOSITE2_PASS
// 蓝噪声给追踪与体积反射抖动，材质提供解码材质，天空云提供假天空反射与云影开关，雾提供反射里的体积雾与地表散射。
#include "/common/noise.glsl"
#include "/effects/ground/material.glsl"
#include "/effects/sky/sky.glsl"
#include "/effects/cloud/cloud.glsl"
#include "/effects/fog/fog.glsl"

#if !defined OMNI_NETHER && !defined OMNI_END // 主世界才用天空盒回退；下界用 `NetherFog`，末地用末地天空。
// 体素反射：屏幕空间没命中时改在体素图上追踪，提供选项、体素颜色图取样与 `omniVoxelReflection`。
#include "/effects/reflection/voxel.glsl"
// 如果屏幕追踪没命中，就用上半屏的天空盒图当反射：把反射方向投到天空盒坐标再取色。
// 为什么单列一个函数：屏幕内没有内容时天空是唯一的反射源，缺了它反射处会变成黑洞。
// 调用前提：`colortex2`、`worldMoonVector`、`colorMoonlight`、`isEyeInWater` 已由合成主程序声明。
vec3 ComputeFakeSkyReflection(vec3 reflectWorldDir){
	float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图的边长，受屏幕尺寸限制。
	vec2 skyImageCoord = ProjectSky(reflectWorldDir, tileSize); // 反射方向投到天空盒坐标，与天空写入端同一套映射。
	vec4 skyImage = textureLod(colortex2, skyImageCoord, 0.0); // 读天空盒图。
	skyImage.rgb = CurveToLinear(skyImage.rgb); // 从曲线编码换回线性。

	#ifdef OMNI_MOON_TEXTURE // 使用资源包月亮贴图时，反射里也画一个月亮圆盘。
		if (isEyeInWater == 0){ // 水下不画月亮，避免和水面下的画面冲突。
			float moonDisc = RenderMoonDiscReflection(reflectWorldDir, worldMoonVector); // 反射用的月亮圆盘，角半径更大才看得见。
			moonDisc *= mix(1.0, skyImage.a, OMNI_RAIN_SHADOW); // 按雨天遮蔽把月亮压暗。
			moonDisc *= (15.0 * OMNI_SKY_TEXTURE_BRIGHTNESS / MAIN_OUTPUT_FACTOR); // 换算到管线单位并乘纹理亮度。
			skyImage.rgb += colorMoonlight * moonDisc; // 月亮直射叠加到天空反射上。
		}
	#endif

	return skyImage.rgb; // 返回天空反射颜色。
}
#endif // 天空盒回退分支结束。

// 可见法线抽样：按粗糙度把反射方向散射开，粗糙面因此得到模糊反射。
// 来源：原程序改自一篇公开论文的可见法线抽样，作者名字与链接见参考包，本函数保持原程序写法。
vec3 sampleGGXVNDF(vec3 viewVector, float roughness, vec2 noise) {
	vec3 orthoNormal = normalize(vec3(roughness * viewVector.xy, viewVector.z)); // 把视线按粗糙度压扁后归一化，得到分布主轴。

	float length2 = dot(orthoNormal.xy, orthoNormal.xy); // 主轴水平分量的长度平方。
	vec3 orthoTangent = length2 > 0.0 ? vec3(-orthoNormal.y, orthoNormal.x, 0.0) * inversesqrt(length2) : vec3(1.0, 0.0, 0.0); // 水平切向，主轴水平分量为零时给一个占位方向。
	vec3 orthoBitangent = cross(orthoNormal, orthoTangent); // 副切向由叉积得到。

	float radius = sqrt(noise.y * 0.7); // 采样半径取噪声，乘零点七限制在圆盘内。
	float angle = TAU * noise.x; // 采样角度取噪声。
	vec2 samplePos = vec2(cos(angle), sin(angle)) * radius; // 圆盘上的采样位置。

	float scaling = orthoNormal.z * 0.5 + 0.5; // 主轴竖直分量决定的缩放，让圆盘在主轴附近压扁。
	samplePos.y = (1.0 - scaling) * sqrt(1.0 - samplePos.x * samplePos.x) + scaling * samplePos.y; // 把采样点投到椭圆上。

	vec3 sampleVector = samplePos.x * orthoTangent + samplePos.y * orthoBitangent + sqrt(max(0.0, 1.0 - dot(samplePos, samplePos))) * orthoNormal; // 组合成三维方向。
	return normalize(vec3(roughness * sampleVector.xy, max(sampleVector.z, 0.0))); // 按粗糙度压扁并归一化。
}

// 取追踪采样点的深度：手部读手部深度，其他读不透明深度，近景是天空时改读远景深度。
// 为什么单独成函数：追踪循环每前进一步、每细化一步都要重读深度，抽到一处后循环体只剩一条读深度，
// 既能保证三种读法一致，也让追踪循环少一层预处理嵌套，整段读起来是一段平铺的步进。
float TraceSampleDepth(vec2 coord, bool isHand){
	#if MC_VERSION >= 11605 // 一点一六点五以后手部有单独深度。
		if (isHand) return textureLod(depthtex2, coord, 0.0).x; // 手部读不含玩家的深度。
	#endif
	float depth = textureLod(depthtex1, coord, 0.0).x; // 其他像素读普通不透明深度。
	#if defined DISTANT_HORIZONS && defined OMNI_DH_SSR // 近景是天空且开启远景反射时改读远景深度；关闭时远景按天空处理，反射只打到近景几何。
		if (depth == 1.0) depth = ScreenDepth_From_DHScreenDepth(textureLod(dhDepthTex1, coord, 0.0).x); // 换成同一距离在近景投影下的深度。
	#endif
	return depth; // 返回该坐标的深度。
}

// 屏幕空间追踪：从起点沿反射方向在屏幕里逐步前进，撞到比射线更近的几何就命中。
// 输入是射线起点与方向、视线余弦、抖动噪声、最小步长与是否手部；就地推进 `screenPos`，返回是否命中。
// 为什么命中后要二分细化：粗步长会跨过薄几何，细化几次把交点收窄到表面附近，反射边界才不抖。
// 为什么经过 `screenPos.z` 与深度的相对差判定：只看深度大小会把掠射面判成命中，用相对差更稳。
bool ScreenSpaceTracer(vec3 viewRayOri, vec3 viewRayDir, float NdotV, float noise, float minLength, bool isHand, inout vec3 screenPos){
	const float rSteps = 1.0 / OMNI_RAYTRACE_QUALITY; // 步数的倒数，用作归一化步长。

	float viewRayLength = (-near - viewRayOri.z) / viewRayDir.z + step(viewRayDir.z, 0.0) * 1e20; // 射线到近裁剪面的长度，背向时给一个极远值。
	vec3 rayDir = normalize(ScreenPos_From_ViewPos_Raw(viewRayOri + viewRayDir * viewRayLength) - screenPos); // 屏幕坐标下的射线方向，用不去抖动的投影。

	float minStepLength = minLength * rSteps; // 最小步长按质量缩放。

	float stepLength = mix(minStepLength, rSteps, NdotV); // 正对视线时步长更大，掠射时步长更小更稳。
	float zScaling = abs(1.0 / rayDir.z); // 深度方向的缩放，把深度差换算成屏幕距离。

	bool hit = false; // 命中标记，初值未命中。

	#ifdef DISTANT_HORIZONS // 有远景时步进上限是远景最远距离，没有远景时是近景最远处。
		float maxDepth = ScreenDepth_From_LinearDepth(LinearDepth_From_ScreenDepth_DH(1.0)); // 远景最远距离对应的近景深度，作为有效深度与步进上限。
	#else
		float maxDepth = 1.0; // 没有远景时近景最远处为一。
	#endif

	screenPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少规则条纹。
	float depth = TraceSampleDepth(screenPos.xy, false); // 读该点深度，起始点不按手部处理。

	for(int i = 0; i < OMNI_RAYTRACE_QUALITY + 3; i++){ // 最多走质量加三次，多出的几次用于边界收尾。

		if (saturate(screenPos.xy) != screenPos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。

		if (screenPos.z >= maxDepth){ // 射线到达最远处。
			hit = depth >= maxDepth; // 该处也是尽头才算命中。
			break; // 结束步进。
		}else if (screenPos.z < 0.7 && !isHand){ // 射线跑到相机很近的地方，后面没有可靠深度。
			break; // 结束步进。
		}

		if (depth < screenPos.z){ // 几何深度比射线更近，说明可能撞上几何。

			vec3 refineDir = rayDir * stepLength * 0.5; // 细化步长，从半步开始逐次减半。

			for (int j = 0; j < OMNI_RAYTRACE_REFINEMENT_STEPS; j++, refineDir *= 0.5) { // 二分细化交点。

				screenPos += refineDir * (step(screenPos.z, depth) * 2.0 - 1.0); // 越过就回退半步，没越过就前进半步。
				depth = TraceSampleDepth(screenPos.xy, isHand); // 重读该点深度，手部读手部深度。
			}

			if (depth > screenPos.z) continue; // 细化后几何又跑到后面，这一步不算命中。

			float stepDist = LinearDepth_From_ScreenDepth(screenPos.z); // 射线点的米制距离。
			float sampleDist = LinearDepth_From_ScreenDepth(depth); // 几何点的米制距离。

			float distDiff = abs(sampleDist - stepDist) / stepDist; // 两点的相对深度差。

			if (distDiff < OMNI_RAYTRACE_ZDIFF_THRESHOLD && screenPos.z > 0.0 && screenPos.z < maxDepth){ // 差足够小且深度在有效范围内才算命中。
				hit = true;
				break;
			}
		}

		stepLength = clamp(abs(depth - screenPos.z) * zScaling, minStepLength, rSteps); // 按深度差自适应下一步长度，落在最小与最大之间。
		screenPos += rayDir * stepLength; // 前进一步。
		depth = TraceSampleDepth(screenPos.xy, false); // 读新位置的深度，步进点不按手部处理。
	}

	return hit; // 返回是否命中。
}

#if defined OMNI_NETHER
// 下界反射：没有天空盒回退，命中取屏幕颜色、没命中留黑，再叠一段 `NetherFog`（来自 `world-1/composite2.fsh`）。
// 调用前提：`NetherFog` 由 `effects/world/nether.glsl` 提供，绘制主体需在本文件之前引入它。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记，下界不使用。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif
	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif

	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离，写进返回的 a 通道供后续滤波使用。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面，命中距离记零。
	}else{ // 粗糙面：按可见法线抽样。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样一个可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪。
	}

	reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 命中点或默认点取屏幕颜色。

	reflection = mix(vec3(0.0), reflection, float(hit)); // 没命中就留黑。

	float dist = length(viewPos); // 表面到相机的距离。
	float rDist = 80.0; // 反射射线的默认长度。

	if(hit){ // 命中几何时按命中点算这段空气长度。
		float hitDepth = textureLod(depthtex0, screenPos.xy, 0.0).x; // 命中点深度。
		vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, hitDepth); // 还原命中点视空间位置。
		rDist = dist + distance(hitPos, viewPos); // 表面到相机的距离加命中点距离。

		if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面把命中距离写进 a 通道。
	}

	reflection += NetherFog(vec2(rDist, dist)) / MAIN_OUTPUT_FACTOR; // 补一段下界雾。

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#elif defined OMNI_END
// 末地反射：天空盒回退换成末地天空，命中距离那段补 `EndFog`（来自 `world1/composite2.fsh`）。
// 调用前提：`ComputeFakeSkyReflectionEnd` 与 `EndFog` 由 `effects/world/end.glsl` 提供，绘制主体需在本文件之前引入它。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif

	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif

	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面。
	}else{ // 粗糙面：按可见法线抽样。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 切向参考轴。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪。
	}

	reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 命中点或默认点取屏幕颜色。

	vec3 rayDirectionWorld = mat3(gbufferModelViewInverse) * rayDir; // 反射方向转到世界空间。
	vec3 skyReflection = vec3(0.0); // 天空回退颜色。
	if(!totalInternalReflection && isEyeInWater == 0){ // 空中且非全反射才用末地天空。
		skyReflection = ComputeFakeSkyReflectionEnd(rayDirectionWorld, isSmooth); // 末地天空回退。
		skyReflection *= saturate((dot(normal, gbufferModelView[1].xyz) + 0.7) * 2.0) * 0.75 + 0.25; // 朝上的面接更多天空。
	}
	if(totalInternalReflection) skyReflection = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 全反射直接取当前场景色。

	reflection = mix(skyReflection, reflection, float(hit)); // 命中则用屏幕颜色，否则用天空。

	float dist = length(viewPos); // 表面到相机的距离。
	float rDist = 1e10; // 反射射线在空气里的长度。

	if(hit){ // 命中几何时按命中点算这段空气长度。
		vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, textureLod(depthtex0, screenPos.xy, 0.0).x); // 还原命中点。
		rDist = distance(hitPos, viewPos); // 命中点到表面的距离。

		if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面写命中距离。
	}

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	rDist = max(min(min(rDist + dist, farDist), 512.0) - dist, 0.0); // 空气段长度裁到可视范围内。

	if (rDist > 0.0) reflection += EndFog(rDist, rayDirectionWorld) / MAIN_OUTPUT_FACTOR; // 有空气段才补末地雾。

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#else // 主世界
// 反射主函数（写三号画面）：追踪反射方向，命中取屏幕颜色，没命中取天空回退，再叠反射里的体积雾与地表散射。
// 输入是表面位置、世界位置、视线方向、法线、深度、底色、材质、天光等级、是否手部、是否光滑面与高光强度；输出三号画面的反射数据。
// 为什么全反射像素直接取当前场景色：发生全反射时表面看不到外面的东西，取自身颜色才不会出现黑洞。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记写在二号画面之外的一号画面 a 通道。
	skylight = smoothstep(0.3, 0.8, skylight); // 天光等级重整到零到一。

	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线的夹角余弦。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif

	#ifdef DISTANT_HORIZONS
		vec3 screenPos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标，保证与深度同源。
	#else
		vec3 screenPos = vec3(texCoord, gbufferdepth); // 没有远景时直接用当前像素坐标与深度。
	#endif


	vec3 reflection; // 反射颜色。
	float hitDist = 1.0; // 命中距离，写进返回的 a 通道供后续滤波使用。
	vec3 rayDir; // 反射射线方向。

	bool hit; // 是否命中几何。

	if(isSmooth){ // 光滑面：镜面反射，方向就是反射方向。
		rayDir = reflect(viewDir, normal); // 镜面反射方向。
		float minLength = (3e-4 - viewPos.z * 7e-6 * saturate(NdotV * 500.0 - 1.0)) * gbufferProjection[1][1]; // 最小步长，随深度与视线倾斜收紧。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, minLength, isHand, screenPos); // 屏幕空间追踪。

		hitDist = 0.0; // 光滑面视作镜面，命中距离记零。
	}else{ // 粗糙面：按可见法线抽样，反射方向带散射。
		vec3 normalUp = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
		mat3 toTangent = mat3(cross(normalUp, normal), normalUp, normal); // 切线基，第三列是法线。
		vec3 tangentView = viewDir * toTangent; // 视线转到切线空间。

		vec3 visibleNormal = toTangent * sampleGGXVNDF(-tangentView, material.roughness, noise); // 抽样一个可见法线。
		rayDir = reflect(viewDir, visibleNormal); // 沿可见法线反射。

		hit = ScreenSpaceTracer(viewPos, rayDir, NdotV, noise.x, 0.015, isHand, screenPos); // 屏幕空间追踪，最小步长更小。
	}

	vec3 rayWorldDir = mat3(gbufferModelViewInverse) * rayDir; // 反射方向转到世界空间，供天空与雾使用。


	bool isSky = true; // 命中点是不是天空，默认按天空处理。

	float highlightGGX = 0.0; // 太阳高光，只在光滑天空像素上出现。

	if(hit){ // 命中几何时取该处的场景色。
		isSky = floor(textureLod(colortex5, screenPos.xy, 0.0).b * 255.0) < 0.5; // 材质编号小于零点五的当作天空。
		reflection = CurveToLinear(textureLod(colortex1, screenPos.xy, 0.0).rgb); // 读回该处曲线编码的颜色。
	}

	if(isSky && isSmooth && highlightStrength > 0.0) highlightGGX = SpecularGGX(normal, -viewDir, shadowVector, 0.002, 0.06) * highlightStrength; // 光滑天空像素加一个太阳镜面高光。

	if(!hit){ // 没命中时用天空回退。
		if(totalInternalReflection){ // 全反射。
			reflection = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 直接取当前场景色。
		}else if (isEyeInWater == 0 && skylight > 0.0){ // 不在水下且有一定天光时才用天空。
			reflection = ComputeFakeSkyReflection(rayWorldDir); // 取天空盒反射。
			float skylightFalloff = skylight * (saturate((dot(normal, gbufferModelView[1].xyz) + 0.7) * 2.0) * 0.75 + 0.25); // 朝上的面接更多天光。
			reflection *= skylightFalloff; // 按天光衰减反射。
			highlightGGX *= skylightFalloff; // 高光同样衰减。
		}
	}

	#if defined OMNI_MOON_TEXTURE // 用月亮贴图时高光偏月光，否则偏当前直射光。
		reflection += colorSunlight * highlightGGX; // 叠加太阳高光。
	#else
		reflection += colorShadowlight * highlightGGX; // 叠加直射高光。
	#endif

	#if defined OMNI_VOXEL_REFLECTION && defined IRIS_FEATURE_CUSTOM_IMAGES // 屏幕空间没命中时再用体素反射补一次。
		if(!hit && !totalInternalReflection && isEyeInWater == 0){ // 空中且屏幕空间没命中才追踪体素。
			vec3 voxelHitWorld; // 体素命中的相机相对世界位置，用来把反射雾的雾段算到真实命中点。
			vec4 voxelHit = omniVoxelReflection(worldPos, rayWorldDir, normal, voxelHitWorld); // 世界空间追踪体素图。
			if(voxelHit.a >= 0.0){ // `a` 不为负就是命中。
				reflection = voxelHit.rgb; // 用体素里存下的方块颜色作为反射。
				hit = true; // 当作命中几何，后面的雾按命中处理。
				isSky = false; // 命中的不是天空。
				hitDist = voxelHit.a; // 归一化命中距离，供反射滤波使用。
				screenPos = ScreenPos_From_ViewPos(mat3(gbufferModelView) * voxelHitWorld); // 把命中点投回屏幕，反射雾、地表散射与雾照明就按这段距离罩住体素反射，而不是当成零长度。
			}
		}
	#endif


	#if (defined OMNI_LANDSCATTERING && (defined OMNI_LANDSCATTERING_REFLECTION || defined DISTANT_HORIZONS)) || (defined OMNI_VFOG && defined OMNI_VFOG_REFLECTION) // 反射里要不要补体积雾与地表散射。
		float dist = length(viewPos); // 表面到相机的距离。
		float rDist = 1e10; // 反射射线在空气里的长度，默认极远。

		if(hit){ // 命中几何时按命中点算这段空气的长度。
			if(!isSky){ // 命中实心几何。
				vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, screenPos.z); // 还原命中点视空间位置。
				rDist = distance(hitPos, viewPos); // 命中点到表面的距离。
			}

			if(!isSmooth) hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 粗糙面把命中距离写进 a 通道供滤波。
		}

		if (isEyeInWater == 1) skylight = 1.0; // 水下天光按满值，水下雾才能正常出现。

		if (skylight > 0.0){ // 有天光才补空气里的散射。
			#ifdef DISTANT_HORIZONS
				float farDist = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
				#ifdef OMNI_DH_LIMIT_VFOG_DIST
					farDist = min(2048.0, farDist); // 限制雾距离上限。
				#endif
			#else
				float farDist = far * 1.4; // 没有远景时用近景远裁剪面估计。
			#endif
			rDist = max(min(rDist + dist, farDist) - dist, 0.0); // 空气段长度裁到可视范围内。


			if (rDist > 0.0){ // 有空气段才补雾。
				reflection *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾函数按此单位工作。
				vec3 volumetricReflection = reflection; // 在副本上补散射，最后按天光混合。

				vec3 endPos = worldPos + rayWorldDir * rDist; // 反射射线的终点世界位置。

			
				#ifdef OMNI_LANDSCATTERING // 地表大气散射。
					#ifdef DISTANT_HORIZONS
						LandAtmosphericScattering(volumetricReflection, rDist, worldPos, endPos, rayWorldDir, isSky); // 有远景时一律补散射。
					#else
						#ifdef OMNI_LANDSCATTERING_REFLECTION
							LandAtmosphericScattering(volumetricReflection, rDist, worldPos, endPos, rayWorldDir, isSky); // 只在开启反射时补散射。
						#endif
					#endif
				#endif
			

				#ifdef OMNI_VFOG // 体积雾。
					#ifdef OMNI_VFOG_REFLECTION
						float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾的光照遮蔽使用。

						#ifdef OMNI_UNDERWATER_VFOG
							if (isEyeInWater == 1) volumetricReflection += UnderwaterVolumetricFog(worldPos, endPos, rayWorldDir, globalCloudShadow); // 水下补水下体积雾。
						#endif

						float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
						#ifndef OMNI_VFOG_IGNORE_WORLDTIME // 不忽略时间时按白天夜晚调整。
							#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系降水情况。
								fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7));
							#else
								fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 关闭局部降水时只看整体湿润度。
							#endif
						#endif
						
						float fogTransmittance = 1.0; // 透射率占位，本处不返回。
						if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(volumetricReflection, worldPos, endPos, rayWorldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 补体积雾。
					#endif
				#endif


				reflection = mix(reflection, volumetricReflection, skylight); // 按天光在原始反射与补雾反射之间混合。
				reflection /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
			}
		}
	#else // 不需要补雾时只算命中距离供滤波。
		if(hit && !isSmooth){ // 粗糙面命中几何。
			vec3 hitPos = ViewPos_From_ScreenPos(screenPos.xy, textureLod(depthtex0, screenPos.xy, 0.0).x); // 用含半透明深度还原命中点。
			float rDist = distance(hitPos, viewPos); // 命中点到表面的距离。

			hitDist = saturate(max(rDist * 2.0, 3.0 * material.roughness)); // 写进 a 通道供滤波。
		}
	#endif

	return vec4(LinearToCurve(reflection.rgb), hitDist); // 曲线编码后与命中距离一起返回。
}
#endif // 反射主函数分支结束。
#endif // composite2 段结束。

// --- composite5：把三号画面的反射合并进场景色 ---
#ifdef OMNI_COMPOSITE5_PASS
// 材质提供 `Material` 结构，反射合并要读它的金属度与反射强度。
#include "/effects/ground/material.glsl"

// 反射合并：把三号画面的反射按菲涅耳与金属度混合进底色。
// 输入是场景色、视线方向、法线、底色、水的吸收与材质；就地把反射混进场景色。
// 为什么主世界与下界末地共用一份签名：主世界给水吸收留权重，下界末地没有水吸收这一项，数值差异留在函数体内用 `OMNI_OVERWORLD` 分支处理，调用点保持同一个。
// 为什么用 `length(color)` 与 `length(reflection)` 再补一项：亮度差大时补一点反射，金属与高亮边缘不会突黑。
void CalculateSpecularReflections(inout vec3 color, vec3 viewDir, vec3 normal, vec3 albedo, float waterAbsorption, Material material){

	vec3 reflection = CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb); // 读三号画面的反射颜色并换回线性。

	#ifndef OMNI_NETHER // 下界没有全反射标记这一套。
		bool notTotalReflection = texelFetch(colortex1, texelCoord, 0).a < 0.5; // 一号画面 a 通道小于零点五表示不是全反射像素。
	#else
		bool notTotalReflection = true; // 下界没有全反射标记，一律按普通像素处理。
	#endif

	if (notTotalReflection){ // 先算好布尔量再走一条完整的 `if`，避免判断括号被预处理指令切开。

		reflection *= mix(vec3(1.0), albedo, vec3(material.metalness)); // 金属面用底色给反射染色。

		vec3 l = normalize(reflect(viewDir, normal) + normal * material.roughness); // 反射方向按粗糙度偏一点，得到更亮的反射。
		vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
		float LdotH = saturate(dot(l, h)); // 反射与半程夹角。
		float NdotL = saturate(dot(normal, l)); // 反射方向的入射余弦。
		float NdotV = saturate(dot(normal, -viewDir)); // 视线方向的入射余弦。

		float specular = F_Schlick(LdotH, material.f0, 1.0); // 菲涅耳。
		specular *= V_Schlick(NdotL, NdotV + 0.8, material.roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
		specular *= material.reflectionStrength; // 乘材质允许的反射强度。

		specular = mix(specular, 1.0, material.metalness); // 金属面反射权重拉满。

		vec3 temp = color; // 记下原底色，金属面要再加一份。

		float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
		diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
		specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。

		#ifdef OMNI_OVERWORLD
			color = mix(color, reflection, saturate(specular * waterAbsorption)); // 主世界按水吸收缩反射权重。
			color += temp * (material.metalness * waterAbsorption); // 金属面再加一份底色。
		#else
			color = mix(color, reflection, saturate(specular)); // 下界末地按反射权重混合。
			color += temp * material.metalness; // 金属面再加一份底色。
		#endif
	}else{ // 全反射像素。
		color = reflection; // 直接取反射颜色。
	}
}
#endif // composite5 段结束。

// --- composite3 / composite4：反射小波滤波 ---
#if defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS
// 反射滤波：用九点小波核按法线与深度相似度加权，抹掉屏幕反射的噪点同时保住反射边界。
// 输入是反射数据、表面位置、视线方向、法线、粗糙度、滤波半径与抖动噪声；就地改写反射数据。
// 为什么按法线与深度加权：命中点落在不同法线或不同深度的邻居属于别的物体，混进来会把反射糊成一片。
// 为什么先按亮度幂次重整再还原：高动态范围的反射点会盖住整片邻域，先压一下亮度再合并，边界更干净。
void AtrousWaveletFilter(inout vec4 reflectionData, vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, float radius, vec2 noise){
	float linearDepth = -viewPos.z; // 表面的米制深度。
	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线夹角余弦。

	roughness = max(roughness, 1e-4); // 粗糙度给一个下限，避免除以零。

	radius *= min(roughness * 20.0, 1.0); // 越粗糙反射越糊，滤波半径越大。
	radius *= reflectionData.a * 0.9 + 0.1; // 命中距离越远半径越大。

	const mat2 rot90 = mat2(cos(1.5708), -sin(1.5708), sin(1.5708), cos(1.5708)); // 旋转九十度，用来由切向得到副切向。

	vec2 T = normalize(cross(normal, viewDir).xy) * radius; // 沿表面切向的采样步长。
	vec2 B = T * rot90; // 副切向的采样步长。
	T *= mix(0.1075, 0.5, NdotV) * pixelSize; // 切向按视角缩放并换成屏幕坐标。
	B *= mix(0.7, 0.5, NdotV) * pixelSize; // 副切向同理。

	vec3 reflectedDir = reflect(-viewDir, normal); // 当前像素的反射方向。

	float normalThreshold = 75.0 / roughness; // 法线相似度的幂次，越粗糙越严。
	float luminanceThreshold = reflectionData.a * 0.95 + 0.05; // 亮度重整的幂次，按命中距离变化。
	
	vec4 accum = vec4(0.0); // 加权累加的反射数据。
	float weights = 0.0; // 累加权重。

	const vec2 offset[9] = vec2[9]( // 三乘三邻域偏移。
		vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), 
		vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), 
		vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0));

	for (int i = 0; i < 9; i++){ // 遍历九个邻点。
		vec2 sampleCoord = texCoord + T * (offset[i] + noise.x) + B * (offset[i] + noise.y); // 邻点坐标，按抖动微调。

		vec4 sampleData = textureLod(colortex3, sampleCoord, 0.0); // 读邻点反射数据。

		if (sampleData.a < 0.0001) continue; // 邻点没有反射，跳过。

		float sampleLinerDepth = LinearDepth_From_ScreenDepth(textureLod(depthtex0, sampleCoord, 0.0).x); // 邻点米制深度。
		vec3 sampleReflectedDir = reflect(-viewDir, DecodeNormal(textureLod(colortex4, sampleCoord, 0.0).xy)); // 邻点反射方向。

		float normalWeight = pow(saturate(dot(sampleReflectedDir, reflectedDir)), normalThreshold); // 反射方向越接近权重越大。
		float depthWeight = exp2(-(abs(sampleLinerDepth - linearDepth) * 1.58)); // 深度越接近权重越大。
		float sampleWeight = normalWeight * depthWeight; // 两个权重相乘。
		
		sampleData.rgb += 1e-13; // 避免零亮度在下面除法里出问题。
		float luminance = length(sampleData.rgb); // 邻点亮度。
		sampleData.rgb *= pow(luminance, luminanceThreshold) / luminance; // 按幂次重整亮度。

		accum += sampleData * sampleWeight; // 按权重累加。
		weights += sampleWeight; // 累加权重。
	
	}
	
	if (weights > 1e-13){ // 有有效邻点才写回。
		accum /= weights; // 取加权平均。

		accum.rgb += 1e-13; // 同样避免零亮度。
		float luminance = length(accum.rgb); // 平均后的亮度。
		accum.rgb *= pow(luminance, 1.0 / luminanceThreshold) / luminance; // 还原亮度重整。

		reflectionData = accum; // 写回滤波结果。
	}
}
#endif // composite3 与 composite4 段结束。
#endif // 文件守卫结束。
