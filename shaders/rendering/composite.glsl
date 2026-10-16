/*
合成绘制主体：照 iterationT 根目录 `composite`、`composite1` 到 `composite5` 六个全屏程序一比一移植。
职责：按顺序把不透明表面光照、水下与水后雾、屏幕空间反射、反射小波滤波、折射与彩色玻璃吸收、体积雾、
    雨、原版雾、选择框与镜头光斑合成到一号与三号画面。算法本身在效果文件里，本文件只安排阶段流程与输入输出。
调用位置：各维度同名入口先定义维度宏、`OMNI_FRAGMENT` 或 `OMNI_VERTEX`，以及对应 `OMNI_COMPOSITE*_PASS`，
    再引入本文件。顶点阶段统一复用 `rendering/lights.glsl`；片元阶段按合同顺序引入效果文件。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE0_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_COMPOSITE2_PASS 1` 再引入本文件即得合成二号顶点阶段。
写出缓冲与来源：
    `composite` 写一号，来自 `composite.fsh`；`composite1` 写一号，来自 `composite1.fsh`；
    `composite2` 写三号，来自 `composite2.fsh`；`composite3`、`composite4` 写三号，来自对应同名文件；
    `composite5` 写一号与三号，来自 `composite5.fsh`。
关键设计原因与取舍：
    原程序一个程序一个文件，本文件把它们合成一个主体，按程序宏分派，每个片元 `main()` 与 iterationT 逐行一致。
    顶点阶段按原程序给合成二号打开 `VS_SHADOW_HIGHLIGHT`、给合成五号打开 `VS_SUN_VISIBILITY`，再引入统一顶点文件。
    被引入的效果文件会整段编译，所以它们引用的加载器输入（阴影采样器、涟漪贴图、降雨强度、天空光满值标记）
    由本文件声明一次；本程序自己不一定用到这些量，声明只为让整段可编译，名字照 iterationT。
    `composite5` 的 `sunCoord`、`sunVisibility` 由顶点阶段算出；镜头选项位于 `effects/lens.glsl`，
    那份文件含片元专用的 `gl_FragCoord`，不能在顶点阶段引入，因此顶点阶段看不到 `OMNI_LENS_GLARE`，
    两个变量在顶点阶段不会被写出。本条属于跨片边界，处理方式见交付报告，不在本文件里改动别的效果文件。
    阴影样本 `shadowtex1` 按 `rendering/buffers.glsl` 的 `shadowHardwareFiltering1` 声明成带比较的采样器，
    与 `effects/shadow.glsl` 的读取方式一致；`effects/fog.glsl` 在英伟达分支按二维深度读同一张图，两者冲突见交付报告。
*/
#ifndef OMNI_COMPOSITE_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_COMPOSITE_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX // 顶点阶段只做全屏三角形与光色计算，交给 `rendering/lights.glsl`。

	#if defined OMNI_COMPOSITE2_PASS // 合成二号顶点。
		#define VS_SHADOW_HIGHLIGHT 1 // 打开高光提示强度分支，片元要用它算天空高光。
	#endif
	#if defined OMNI_COMPOSITE5_PASS // 合成五号顶点。
		#define VS_SUN_VISIBILITY 1 // 打开太阳可见度分支，片元要用它画镜头光斑。
	#endif
	// 提供 `void main()` 与全部光色输出。
	#include "/rendering/lights.glsl"

#endif // 顶点阶段结束。

// ================================ 片元阶段 ================================

// ------------------------------- 合成零号：不透明表面完整光照 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE0_PASS
/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 compositeOutput1; // 一号画面：场景曲线编码颜色。
#if defined OMNI_NETHER
// 下界：没有太阳，光照来自 `NetherLighting` 与雾色，不接收全局光与阴影（来自 `world-1/composite.fsh`）。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
// 下界不需要顶点光色来照明，但被引入的雾与光照文件整段编译，先声明它们引用的量。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色，方块光与手持光引用它。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
// 被引入的水面与雾文件整段编译，下列采样器由它们引用。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2D shadowtex1; // 阴影实心图，下界当普通深度贴图。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算与遮蔽抖动要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，遮蔽抖动用。
#include "/common/noise.glsl"
// 雾文件带入水面、阴影、天空、云与光照，并提供 `OMNI_NETHERFOG_DENSITY`。
#include "/effects/fog/fog.glsl"
// 下界配色与光照 `NetherLighting`、`NetherFogColor`。
#include "/effects/world/nether.glsl"
// Omni 额外功能：真实闪电事件照亮表面，默认开启但缺少事件输入时无影响。
#include "/effects/sky/atmosphere.glsl"
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthL == 1.0){ // 天空像素改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

	vec3 finalComposite = vec3(0.0); // 累积的下界表面颜色。

	if (materialMaskSoild.sky < 0.5){ // 只处理有几何的像素，天空留给下界雾色。
		finalComposite += NetherLighting() * (worldNormal.y * 0.25 + 1.0); // 按法线朝向叠下界自发光。

		float gi = 1.0; // 环境遮蔽，默认为一。
		#ifdef OMNI_GTAO
			if (materialMaskSoild.hand + materialMask.particle < 0.5) // 手与粒子不参与遮蔽。
				gi = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, gbuffer.normalL); // 算地平线遮蔽。
		#endif

		#ifdef OMNI_GTAO
			#ifdef OMNI_GTAO_MULTIBOUNCE
				vec3 ao = GTAOMultiBounce(gi, gbuffer.albedo); // 遮蔽做多弹射补偿。
			#else
				vec3 ao = vec3(gi); // 直接用遮蔽值。
			#endif
		#else
			vec3 ao = vec3(1.0); // 不开遮蔽时全亮。
		#endif

		finalComposite *= ao; // 遮蔽乘到颜色上。

		if(heldBlockLightValue + heldBlockLightValue2 > 0.0)
			finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5); // 叠手持光源。
		finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSoild); // 叠方块光。

		finalComposite *= mix(vec3(1.0), NetherFogColor().rgb, gbuffer.material.metalness * 0.7); // 金属面用雾色染色。
		finalComposite *= (1.0 - gbuffer.material.metalness * 0.75); // 非金属整体压一点。

		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSoild); // 叠资源包自发光。

		finalComposite *= gbuffer.albedo; // 乘底色。

	}else{ // 天空像素交给合成五号的雾与泛光。
		finalComposite = vec3(0.0); // 清成黑色。
	}

	finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

	compositeOutput1 = vec4(finalComposite, 0.0); // 写回一号画面。
}
#elif defined OMNI_END
// 末地：没有太阳贴图，光色用固定黑体色，天空像素画吸积盘与行星（来自 `world1/composite.fsh`）。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#define OMNI_SHADOW_COMPARE 1 // 末地同样用可变半影阴影，打开阴影效果里的对应段。
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2DShadow shadowtex1; // 阴影实心图，可变半影阴影按深度比较读取。
uniform sampler2D shadowcolor0; // 彩色半影阴影颜色图。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算与遮蔽抖动要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，遮蔽与阴影抖动用。
#include "/common/noise.glsl"
// 光照文件提供 `OMNI_SUNLIGHT_INTENSITY`、方块光、遮蔽与星空类型选项。
#include "/effects/lighting/sunlight.glsl"
// 水面文件提供波法线 `GetWavesNormal`，末地折射函数引用它。
#include "/effects/water/water.glsl"
// 末地天空 `BlackHole_AccretionDisc_Stars`、`PlanetEnd2` 与 `timeFactor`、`planetShadow`。
#include "/effects/world/end.glsl"
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度。

	if (materialMask.water > 0.5){ // 末地水面按光滑非金属处理。
		gbuffer.material.roughness = 1.0; // 粗糙度拉满。
		gbuffer.material.metalness = 0.0; // 去掉金属度。
	}

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		bool isDH = gbuffer.depthL == 1.0; // 标记远景像素。
		if (isDH){ // 天空像素改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldDir = normalize(worldPos); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
	#endif
	float opaqueDist = gbuffer.depthL < 1.0 ? length(viewPos) : farDist; // 表面到相机的距离，天空按远裁剪面。

	vec3 colorSunLight = Blackbody(6000.0); // 末地用固定色温的太阳光色。
	vec3 finalComposite = vec3(0.0); // 累积的末地表面颜色。

	if (materialMaskSoild.sky < 0.5){ // 只处理有几何的像素。
		vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

		#ifdef DISTANT_HORIZONS
			#ifdef OMNI_DH_SHADOW
				materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.65 + 0.35; // 有远景阴影时叶片透光按距离收敛。
			#else
				materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0 - float(isDH) * 1e10) * 0.65 + 0.35; // 没有远景阴影时远景叶子不透光。
			#endif
		#else
			materialMaskSoild.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.6 + 0.4; // 叶片透光随距离收敛。
		#endif

		worldNormal = normalize(mix(worldNormal, vec3(0.0, 1.0, 0.0), materialMaskSoild.grass * 0.49)); // 草的法线朝上拉。
		gbuffer.material.scattering *= saturate(1.0 - materialMaskSoild.leaves - materialMaskSoild.grass); // 叶片与草之外的表面不做透光。

		finalComposite += vec3(colorSunLight * 0.005) * ((worldNormal.y * 0.35 + 0.75) * (dot(worldSunVector, worldNormal) * 0.3 + 0.7) * (planetShadow * planetShadow * 0.93 + 0.07)); // 行星相位控制的太阳环境光。

		vec3 sunlightMult = colorSunLight * (0.3 * OMNI_SUNLIGHT_INTENSITY * planetShadow * planetShadow); // 太阳直射按行星相位缩放。

		vec4 gi = texelFetch(colortex1, texelCoord, 0); // 一号画面里存着延迟阶段算好的全局光与遮蔽。
		gi = mix(gi, vec4(0.0, 0.0, 0.0, 1.0), materialMask.particle); // 粒子不接收全局光。

		vec3 rsm = CurveToLinear(gi.rgb); // 全局光解码回线性。
		rsm *= sunlightMult * (7.0 * OMNI_GI_BRIGHTNESS); // 乘直射与全局光亮度。
		finalComposite += rsm; // 叠全局光。

		#ifdef OMNI_GTAO
			#ifdef OMNI_GTAO_MULTIBOUNCE
				vec3 ao = GTAOMultiBounce(gi.a, gbuffer.albedo); // 遮蔽做多弹射补偿。
			#else
				vec3 ao = vec3(gi.a); // 直接用遮蔽值。
			#endif
		#else
			vec3 ao = vec3(1.0); // 不开遮蔽时全亮。
		#endif
		finalComposite *= ao; // 遮蔽乘到颜色上。

		if(heldBlockLightValue + heldBlockLightValue2 > 0.0)
			finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5); // 叠手持光源。

		finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSoild); // 叠方块光。
		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSoild); // 叠资源包自发光。

		float sunlight = Fd_Burley(worldNormal, -worldDir, worldShadowVector, gbuffer.material.roughness); // 阳光漫反射项。

		float sunlightTrans = saturate(materialMaskSoild.leaves * 3.0) * 0.25 + materialMask.particle * 0.4 + materialMaskSoild.grass * 0.15; // 薄片透光占比。
		sunlight = mix(sunlight, 0.6, sunlightTrans); // 薄片把阳光漫反射往固定值拉。
		gbuffer.parallaxShadow = saturate(gbuffer.parallaxShadow + sunlightTrans * 1e10); // 薄片视差自阴影放宽。

		vec3 shadow = vec3(1.0); // 阳光阴影可见度，初值全亮。
		vec3 specularHighlight = vec3(0.0); // 太阳高光，初值零。
		vec3 sss = vec3(0.0); // 次表面散射，初值零。

		if (sunlight + gbuffer.material.scattering > 0.0) // 有阳光或透光才算阴影。
			shadow *= VariablePenumbraShadow(worldPos, worldNormal, sunlight, gbuffer.albedo, gbuffer.material.scattering, materialMaskSoild, sss); // 可变半影阴影并带回透光。

		#if OMNI_PARALLAX_MODE > 0
			shadow *= gbuffer.parallaxShadow; // 视差自阴影也压阳光。
		#endif

		if (any(greaterThan(sunlight * shadow, vec3(0.0)))){ // 还有阳光的像素才继续。
			#ifdef OMNI_SCREEN_SPACE_SHADOWS
				#ifdef OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
					#if OMNI_PARALLAX_MODE > 0
						if (materialMaskSoild.leaves + materialMaskSoild.hand + materialMaskSoild.entitiesSnow + materialMaskSoild.entityPlayer < 1.0)
					#else
						if (materialMaskSoild.leaves + materialMaskSoild.hand + materialMaskSoild.entitiesSnow + materialMaskSoild.entityPlayer < 1.0 && gbuffer.parallaxShadow > 0.0)
					#endif
				#else
					#if OMNI_PARALLAX_MODE > 0
						if (materialMaskSoild.leaves + materialMaskSoild.hand + materialMaskSoild.entitiesSnow < 1.0)
					#else
						if (materialMaskSoild.leaves + materialMaskSoild.hand + materialMaskSoild.entitiesSnow < 1.0 && gbuffer.parallaxShadow > 0.0)
					#endif
				#endif
					shadow *= mix(ScreenSpaceShadow(viewPos, viewDir, gbuffer.normalL, materialMaskSoild, shadowVector), 1.0, saturate(materialMaskSoild.leaves * 1.67 - 0.67)); // 屏幕空间阴影，叶片按比例削弱；方向传视空间的 shadowVector，与原程序一致。
			#endif

			#ifdef OMNI_CAUSTICS
				if (materialMask.water > 0.5 || isEyeInWater == 1)
					shadow *= CalculateWaterCaustics(worldPos, worldShadowVector); // 水面焦散。
			#endif

			shadow *= sunlightMult; // 阴影乘直射光。

			finalComposite += sunlight * shadow; // 叠漫反射阳光。

			if (materialMask.water + materialMask.ice < 0.5){ // 水与冰不做这层高光。
				float highlightGGX = SpecularGGX(gbuffer.normalL, -viewDir, shadowVector, clamp(gbuffer.material.roughness, 0.0015, 0.9), gbuffer.material.f0); // GGX 高光。
				highlightGGX *= saturate(4.0 - gbuffer.material.roughness * 3.5); // 光滑面高光更强。
				highlightGGX *= 0.07 - materialMaskSoild.grass * 0.035; // 整体很弱，草更弱。
				specularHighlight = mix(vec3(1.0), gbuffer.albedo, vec3(gbuffer.material.metalness)) * shadow * highlightGGX; // 金属面高光带底色。
			}
		}
		finalComposite += sss * sunlightMult; // 叠次表面散射。

		finalComposite *= gbuffer.albedo; // 乘底色。

		finalComposite *= 1.0 - gbuffer.material.metalness * 0.75; // 非金属整体压一点。

		finalComposite += specularHighlight; // 叠高光。
	}

	worldDir = (isEyeInWater == 1 && materialMask.water > 0.5) ? refract(worldDir, normalize((gbufferModelViewInverse * vec4(gbuffer.normalW, 0.0)).xyz), WATER_REFRACT_IOR) : worldDir; // 水下看水面时折射世界方向。

	if (materialMaskSoild.sky > 0.5){ // 天空像素画末地天空。
		finalComposite = vec3(0.0); // 清空。

		BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector); // 吸积盘与星空。

		PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector); // 行星与光环。
	}

	float totalInternalReflection = 0.0; // 全反射标记，写进一号画面透明通道。
	if (length(worldDir) < 0.5){ // 折射方向退化说明发生全反射。
		finalComposite = vec3(0.0); // 全反射看不到外面。
		totalInternalReflection = 1.0; // 记录发生全反射。
	}

	finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

	compositeOutput1 = vec4(finalComposite, totalInternalReflection); // 写回一号画面。
}
#else // 主世界
// 本程序是唯一使用可变半影阴影的合成阶段，声明比较采样器 `shadowtex1` 并按需要打开阴影效果里的对应段。
#define OMNI_SHADOW_COMPARE 1 // 让 `effects/shadow.glsl` 编译可变半影阴影函数。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，读回各号画面与阴影贴图用。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向，由顶点阶段传入。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
// 被引入的阴影效果整段编译，下列采样器由它们引用，本程序声明一次供整段使用。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2DShadow shadowtex1; // 阴影实心图，可变半影阴影按深度比较读取。
uniform sampler2D shadowcolor0; // 彩色半影阴影颜色图。
// 被引入的水面雨点函数整段编译，下列输入由它们引用。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，阴影与环境遮蔽抖动用。
#include "/common/noise.glsl"
// 天光照明 `SkyLighting`，并带入天空、云、环境光、方块光与阴影。
#include "/effects/lighting/sunlight.glsl"
// 水下雾与焦散选项，本程序据它们决定水色。
#include "/effects/water/water.glsl"
// Omni 额外功能：真实闪电事件照亮表面。
#include "/effects/sky/atmosphere.glsl"
// Omni 额外功能：光传播体积的采样映射与选项。
#include "/effects/lighting/lpv.glsl"
#ifdef OMNI_LPV_ENABLED
	#ifdef IRIS_FEATURE_CUSTOM_IMAGES
	uniform sampler3D omniLpvTex; // 计算阶段写入的体积间接光，片元这里三线性采样。
	#endif
#endif
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	compositeOutput1 = texelFetch(colortex1, texelCoord, 0); // 默认原样保留场景颜色。

	if (materialMaskSolid.sky < 0.5){ // 只处理有几何的像素，天空留给延迟阶段。
		FixParticleMask(materialMaskSolid, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度，避免读到自己后面的方块。

		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

		#ifdef DISTANT_HORIZONS
			bool isDH = gbuffer.depthL == 1.0; // 标记远景像素。
			if (isDH){ // 天空像素改读远景深度。
				gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
				viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影还原位置。
			}
		#endif

		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
		vec3 viewDir = normalize(viewPos); // 视线方向。
		vec3 worldDir = normalize(worldPos); // 世界方向。
		vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

		#ifdef DISTANT_HORIZONS
			float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
		#else
			float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
		#endif
		float opaqueDist = gbuffer.depthL < 1.0 ? length(viewPos) : farDist; // 表面到相机的距离，天空按远裁剪面。

		#ifdef OMNI_VOLUMETRIC_CLOUDS
			#ifdef OMNI_CLOUD_SHADOW
				float cloudShadow = CloudShadowFromTex(worldPos, worldShadowVector); // 从云影贴图取这一点的云影。
			#else
				float cloudShadow = 1.0 - wetness * OMNI_RAIN_SHADOW; // 没有云影贴图时按雨天估一个底值。
			#endif
		#else
			float cloudShadow = 1.0; // 没有体积云时云影不生效。
		#endif

		vec3 sunlightMult = colorShadowlight * (OMNI_SUNLIGHT_INTENSITY * mix(cloudShadow, 1.0, 0.03 - wetness * 0.015)); // 直射光乘云影与强度。

		#ifdef OMNI_CAVE_MODE
			sunlightMult *= mix(1.0, 0.1, eyeBrightnessZeroSmooth); // 洞穴模式按看不到天空的程度压直射。
		#endif

		vec3 waterTint = vec3(1.0); // 水体染色，默认不染。

		#ifdef OMNI_UNDERWATER_FOG
			if (isEyeInWater == 1) waterTint = vec3(0.55, 0.75, 1.0) / max(3.0, opaqueDist * 0.1 * OMNI_WATERFOG_DENSITY); // 水下按距离与水雾密度染偏蓝。
			sunlightMult *= waterTint; // 直射光同步染色。
		#endif

		#ifndef OMNI_CAUSTICS
			if (materialMask.water > 0.5 || isEyeInWater == 1) sunlightMult *= 0.75; // 不开焦散时水下水面的直射压一点。
		#endif

		gbuffer.material.scattering *= saturate(1.0 - materialMaskSolid.leaves - materialMaskSolid.grass); // 叶片与草之外的表面不做透光。

		#ifdef DISTANT_HORIZONS
			#ifdef OMNI_DH_SHADOW
				materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.65 + 0.35; // 有远景阴影时叶片透光按距离收敛。
			#else
				materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0 - float(isDH) * 1e10) * 0.65 + 0.35; // 没有远景阴影时远景叶子不透光。
			#endif
		#else
			materialMaskSolid.leaves *= saturate(3.2 - opaqueDist / min(shadowDistance, far) * 4.0) * 0.6 + 0.4; // 叶片透光随距离收敛。
		#endif

		worldNormal = normalize(mix(worldNormal, vec3(0.0, 1.0, 0.0), materialMaskSolid.grass * 0.49)); // 草的法线朝上拉，减少杂乱。

		#ifdef OMNI_CAVE_MODE
			vec3 finalComposite = vec3(0.83, 0.87, 1.0) * ((worldNormal.y * 0.25 + 0.75) * max(OMNI_NOLIGHT_BRIGHTNESS, 0.00003)); // 洞穴极暗底光。
		#else
			vec3 finalComposite = vec3(0.86, 0.94, 1.19) * ((worldNormal.y * 0.3 + 0.8) * OMNI_NOLIGHT_BRIGHTNESS); // 常规无光亮度。
		#endif
		finalComposite += SkyLighting(worldNormal, gbuffer.lightmapL.g, cloudShadow) * waterTint; // 叠天光照明。

		vec4 gi = compositeOutput1; // 一号画面里存着延迟阶段算好的全局光与遮蔽。
		gi = mix(gi, vec4(0.0, 0.0, 0.0, 1.0), materialMask.particle); // 粒子不接收全局光。

		vec3 rsm = CurveToLinear(gi.rgb); // 全局光解码回线性。
		rsm *= sunlightMult * (8.0 * OMNI_GI_BRIGHTNESS); // 乘直射与全局光亮度。
		#ifdef OMNI_SUNLIGHT_LEAK_FIX
			#ifdef OMNI_GI_SKYLIGHT_FALLOFF
				rsm *= saturate(gbuffer.lightmapL.g * 4.0 + float(isEyeInWater == 1)); // 只在天光充足或水下保留全局光。
			#else
				rsm *= saturate(gbuffer.lightmapL.g * 1e3 + float(isEyeInWater == 1)); // 更严格地只留天光像素。
			#endif
		#endif

		#if defined OMNI_DISABLE_HAND_GI && defined OMNI_DISABLE_PLAYER_GI
			if (materialMaskSolid.hand < 0.5 && materialMaskSolid.entityPlayer < 0.5)
		#elif defined OMNI_DISABLE_HAND_GI
			if (materialMaskSolid.hand < 0.5)
		#elif defined OMNI_DISABLE_PLAYER_GI
			if (materialMaskSolid.entityPlayer < 0.5)
		#endif
			finalComposite += rsm; // 手与玩家按选项排除后叠全局光。

		#ifdef OMNI_GTAO
			#ifdef OMNI_GTAO_MULTIBOUNCE
				vec3 ao = GTAOMultiBounce(gi.a, gbuffer.albedo); // 遮蔽做多弹射补偿。
			#else
				vec3 ao = vec3(gi.a); // 直接用遮蔽值。
			#endif
		#else
			vec3 ao = vec3(1.0); // 不开遮蔽时全亮。
		#endif
		finalComposite *= ao; // 遮蔽乘到颜色上。

		if(heldBlockLightValue + heldBlockLightValue2 > 0.0)
			finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5); // 叠手持光源。

		finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSolid); // 叠方块光。
		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSolid); // 叠资源包自发光。

		float sunlight = Fd_Burley(worldNormal, -worldDir, worldShadowVector, gbuffer.material.roughness); // 阳光漫反射项。

		float sunlightTrans = saturate(materialMaskSolid.leaves * 3.0) * 0.25 + materialMask.particle * 0.4 + materialMaskSolid.grass * 0.15; // 薄片透光占比。
		sunlight = mix(sunlight, 0.6, sunlightTrans); // 薄片把阳光漫反射往固定值拉。
		gbuffer.parallaxShadow = saturate(gbuffer.parallaxShadow + sunlightTrans * 1e10); // 薄片视差自阴影放宽。

		vec3 shadow = vec3(1.0); // 阳光阴影可见度，初值全亮。

		#ifdef OMNI_SUNLIGHT_LEAK_FIX
			float occludedWater = gbuffer.waterMask * materialMask.stainedGlass; // 被玻璃挡住的水。
			float lightMask = saturate(gbuffer.lightmapL.g * mix(1e4, 1.0, occludedWater) + float(isEyeInWater == 1)); // 泄漏修正遮罩。
			shadow *= lightMask; // 阴影先按遮罩压。
		#endif

		vec3 specularHighlight = vec3(0.0); // 太阳高光，初值零。
		vec3 sss = vec3(0.0); // 次表面散射，初值零。

		if ((sunlight + gbuffer.material.scattering) * shadow.x > 0.0){ // 有阳光或透光才算阴影。
			shadow *= VariablePenumbraShadow(worldPos, worldNormal, sunlight, gbuffer.albedo, gbuffer.material.scattering, materialMaskSolid, sss); // 可变半影阴影并带回透光。
			#ifdef OMNI_SUNLIGHT_LEAK_FIX
				sss *= lightMask; // 透光同样受泄漏修正遮罩。
			#endif
			finalComposite += sss * sunlightMult; // 叠次表面散射。
		}

		#if OMNI_PARALLAX_MODE > 0
			shadow *= gbuffer.parallaxShadow; // 视差自阴影也压阳光。
		#endif

		float metalnessMask = gbuffer.material.metalness; // 金属度掩码。
		float skylightmap = min(smoothstep(0.3, 0.8, gbuffer.lightmapL.g), float(isEyeInWater == 0)); // 天光等级重整，水下归零。
		metalnessMask *= 0.1 * skylightmap + 0.9; // 天光越低金属效果越弱。
		metalnessMask = 1.0 - metalnessMask * 0.985; // 翻转成非金属掩码。

		if (any(greaterThan(sunlight * shadow, vec3(0.0)))){ // 还有阳光的像素才继续。
			#ifdef OMNI_SCREEN_SPACE_SHADOWS
				#ifdef OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS
					#if OMNI_PARALLAX_MODE > 0
						if (materialMaskSolid.leaves + materialMaskSolid.hand + materialMaskSolid.entitiesSnow + materialMaskSolid.entityPlayer < 1.0)
					#else
						if (materialMaskSolid.leaves + materialMaskSolid.hand + materialMaskSolid.entitiesSnow + materialMaskSolid.entityPlayer < 1.0 && gbuffer.parallaxShadow > 0.0)
					#endif
				#else
					#if OMNI_PARALLAX_MODE > 0
						if (materialMaskSolid.leaves + materialMaskSolid.hand + materialMaskSolid.entitiesSnow < 1.0)
					#else
						if (materialMaskSolid.leaves + materialMaskSolid.hand + materialMaskSolid.entitiesSnow < 1.0 && gbuffer.parallaxShadow > 0.0)
					#endif
				#endif
					shadow *= mix(ScreenSpaceShadow(viewPos, viewDir, gbuffer.normalL, materialMaskSolid, shadowVector), 1.0, saturate(materialMaskSolid.leaves * 1.67 - 0.67)); // 屏幕空间阴影，叶片按比例削弱。
			#endif

			#ifdef OMNI_CAUSTICS
				if (materialMask.water > 0.5 || isEyeInWater == 1)
					shadow *= CalculateWaterCaustics(worldPos, worldShadowVector); // 水面焦散。
			#endif

			shadow *= sunlightMult; // 阴影乘直射光。

			finalComposite += shadow * (sunlight * metalnessMask); // 叠漫反射阳光。

			if (materialMask.water + materialMask.ice < 0.5){ // 水与冰不做这层高光。
				float highlightGGX = SpecularGGX(gbuffer.normalL, -viewDir, shadowVector, clamp(gbuffer.material.roughness, 0.0015, 0.9), gbuffer.material.f0); // GGX 高光。
				highlightGGX *= saturate(4.0 - gbuffer.material.roughness * 3.5); // 光滑面高光更强。
				highlightGGX *= 0.07 - materialMaskSolid.grass * 0.035; // 整体很弱，草更弱。
				specularHighlight = mix(vec3(1.0), gbuffer.albedo, vec3(gbuffer.material.metalness)) * shadow * highlightGGX; // 金属面高光带底色。
			}
		}

		finalComposite *= gbuffer.albedo; // 乘底色。

		finalComposite *= metalnessMask; // 乘非金属掩码。

		finalComposite += specularHighlight; // 叠高光。

		finalComposite += vec3(1.0) * materialMaskSolid.lightning; // 闪电自发光。

		finalComposite = omniLightning(finalComposite, worldPos, gbuffer.lightmapL.g); // Omni 额外功能：真实闪电事件照亮附近表面。

		#ifdef OMNI_LPV_ENABLED // Omni 额外功能：光传播体积给空气补间接光；缺少自定义图像能力时整段不编译。
			#ifdef IRIS_FEATURE_CUSTOM_IMAGES
			finalComposite += omniLpvSample(omniLpvTex, worldPos) * OMNI_LPV_STRENGTH; // 三线性采样体积间接光。
			#endif
		#endif

		finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
		finalComposite = LinearToCurve(finalComposite); // 四次方根编码。
		compositeOutput1 = vec4(finalComposite, 0.0); // 写回一号画面。
	}
}
#endif // 维度分支结束。
#endif // 合成零号结束。

// ------------------------------- 合成一号：水下与水后雾 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE1_PASS
/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 compositeOutput1; // 一号画面：颜色与全反射标记。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
// 被引入的水面雨点函数整段编译，下列输入由它们引用。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，被引入的效果文件引用。
#include "/common/noise.glsl"
// 先提供 `OMNI_RAIN_SHADOW` 与天空盒投影，供天气与水面引用。
#include "/effects/cloud/cloud.glsl"
// `WaterFog` 水下与水后雾。
#include "/effects/water/water.glsl"
void main(){
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

	float cloudShadow = 1.0; // 云影占位，本程序不使用。

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
#endif // 合成一号结束。

// ------------------------------- 合成二号：屏幕空间反射与天空盒回退 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE2_PASS
#define VFOG_LQ 1 // 反射里的体积雾只用三步，省反射通道开销，宏名照 iterationT。
/* DRAWBUFFERS:3 */
layout(location = 0) out vec4 compositeOutput3; // 三号画面：反射颜色与命中距离。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
in float shadowHighlightStrength; // 顶点阶段算出的高光提示强度。
// 被引入的阴影与雾效果整段编译，下列采样器由它们引用。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2D shadowtex1; // 阴影实心图，本程序当普通深度贴图读取。
uniform sampler2D shadowcolor0; // 彩色半影阴影颜色图。
// 被引入的水面雨点与天气函数整段编译，下列输入由它们引用。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算与噪声要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，反射抖动用。
#include "/common/noise.glsl"
// 维度决定反射里的天空回退与雾由谁提供，效果文件按分支引入后再引入反射文件。
#if defined OMNI_NETHER
	// 下界：雾文件提供 `OMNI_NETHERFOG_DENSITY`，下界文件提供 `NetherFog` 与 `NetherFogColor`。
	#include "/effects/fog/fog.glsl"
	#include "/effects/world/nether.glsl"
#elif defined OMNI_END
	// 末地：光照文件提供选项与星空类型，末地文件提供 `EndFog` 与 `ComputeFakeSkyReflectionEnd`。
	#include "/effects/lighting/sunlight.glsl"
	// 水面文件提供波法线 `GetWavesNormal`，末地折射函数引用它。
	#include "/effects/water/water.glsl"
	#include "/effects/world/end.glsl"
#else
	// 主世界：带入天空、云、环境光、方块光与雾依赖。
	#include "/effects/lighting/sunlight.glsl"
#endif
// 屏幕空间反射与天空盒回退 `CalculateSpecularReflections`，按维度选择不同的一份。
#include "/effects/reflection/reflection.glsl"
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSolid, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	float highlightStrength = float((isEyeInWater != 1 || materialMask.water < 0.5) && gbuffer.lightmapW.g > 0.0) * shadowHighlightStrength; // 高光提示强度，水下水面归零。

	compositeOutput3 = vec4(0.0); // 默认没有反射。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才追踪。
		compositeOutput3 = CalculateSpecularReflections(viewPos, worldPos, viewDir, gbuffer.normalW, gbuffer.depthW, gbuffer.albedo, gbuffer.material, gbuffer.lightmapW.g, materialMask.hand > 0.5, isSmooth, highlightStrength); // 追踪反射并回退天空盒。
}
#endif // 合成二号结束。

// ------------------------------- 合成三号：反射小波滤波，半径四十 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE3_PASS
/* DRAWBUFFERS:3 */
layout(location = 0) out vec4 compositeOutput3; // 三号画面：滤波后的反射数据。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，被反射滤波引用。
#include "/common/noise.glsl"
// 反射小波滤波 `AtrousWaveletFilter`。
#include "/effects/reflection/reflection.glsl"
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	vec4 reflectionData = texelFetch(colortex3, texelCoord, 0); // 读三号画面的反射数据。

	if (gbuffer.material.reflectionStrength > 0.0 && reflectionData.a > 0.0001){ // 有反射才滤波。
		AtrousWaveletFilter(reflectionData, viewPos, viewDir, gbuffer.normalW, gbuffer.material.roughness, 40.0, vec2(0.0)); // 大半径小波滤波，不加抖动。
	}

	compositeOutput3 = reflectionData; // 写回三号画面。
}
#endif // 合成三号结束。

// ------------------------------- 合成四号：反射小波滤波，半径二十 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE4_PASS
/* DRAWBUFFERS:3 */
layout(location = 0) out vec4 compositeOutput3; // 三号画面：滤波后的反射数据。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算与噪声要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，滤波抖动用。
#include "/common/noise.glsl"
// 反射小波滤波 `AtrousWaveletFilter`。
#include "/effects/reflection/reflection.glsl"
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	vec4 reflectionData = texelFetch(colortex3, texelCoord, 0); // 读三号画面的反射数据。

	if (gbuffer.material.reflectionStrength > 0.0 && reflectionData.a > 0.0001){ // 有反射才滤波。
		#ifdef OMNI_TAA
			vec2 noise = BlueNoiseTemporal() - 0.5; // 逐帧抖动，噪点被时间平均掉。
		#else
			vec2 noise = BlueNoise() - 0.5; // 固定抖动。
		#endif
		AtrousWaveletFilter(reflectionData, viewPos, viewDir, gbuffer.normalW, gbuffer.material.roughness, 20.0, noise); // 小半径小波滤波。
	}

	compositeOutput3 = reflectionData; // 写回三号画面。
}
#endif // 合成四号结束。

// ------------------------------- 合成五号：折射、合并反射、雾、雨、选择框与镜头光斑 -------------------------------
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE5_PASS
/* DRAWBUFFERS:13 */
layout(location = 0) out vec4 compositeOutput1; // 一号画面：最终合成颜色与景深弥散。
// 加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用数学与颜色曲线。
#include "/common/math.glsl"
ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
in vec3 shadowVector; // 上面那个方向在视空间的值。
in vec3 worldSunVector; // 太阳的世界方向。
in vec3 worldMoonVector; // 月亮的世界方向。
in vec3 colorShadowlight; // 日月直射光色之和。
in vec3 colorSunlight; // 太阳直射光色。
in vec3 colorMoonlight; // 月亮直射光色。
in vec3 colorSkylight; // 日月环境光色之和。
in vec3 colorSunSkylight; // 太阳一侧的环境光色。
in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
in vec3 colorTorchlight; // 火把光色。
in float timeNoon; // 太阳高度因子。
in float timeMidnight; // 月亮高度因子。
in vec2 sunCoord; // 太阳屏幕坐标，顶点阶段算出，镜头光斑按它定位。
in float sunVisibility; // 太阳可见度，顶点阶段算出，镜头光斑按它衰减。
// 被引入的阴影与雾效果整段编译，下列采样器由它们引用。
uniform sampler2D shadowtex0; // 阴影遮挡图。
uniform sampler2D shadowtex1; // 阴影实心图，本程序当普通深度贴图读取。
uniform sampler2D shadowcolor0; // 彩色半影阴影颜色图。
// 被引入的水面雨点与天气函数整段编译，下列输入由它们引用。
uniform sampler2D gaux1; // 第一张涟漪动画贴图。
uniform sampler2D gaux2; // 第二张涟漪动画贴图。
uniform sampler2D gaux3; // 第三张涟漪动画贴图。
uniform float rainStrength; // 降雨强度，雨点涟漪用。
// 读回表面数据与材质掩码。
#include "/effects/ground/material.glsl"
// 先定义 `OMNI_TAA`，坐标换算与噪声要用。
#include "/effects/clarity/antialiasing.glsl"
// 屏幕与视空间互转。
#include "/common/coordinates.glsl"
// 蓝噪声，被引入的效果文件引用。
#include "/common/noise.glsl"
// 维度决定雾与折射由谁提供：主世界用体积雾与地表散射，下界用 `NetherFog`，末地用 `EndFog`。
#if defined OMNI_NETHER
	// 雾文件带入水面、天空、云、光照，并提供 `VanillaFog` 与雾选项。
	#include "/effects/fog/fog.glsl"
	// 下界配色、雾与折射 `NetherFogColor`、`NetherFog`、`WaterRefractionLiteNether`。
	#include "/effects/world/nether.glsl"
#elif defined OMNI_END
	// 雾文件带入水面与 `VanillaFog`，并提供星空类型与阳光强度选项。
	#include "/effects/fog/fog.glsl"
	// 末地天空、雾与折射 `EndFog`、`WaterRefractionLiteEnd`。
	#include "/effects/world/end.glsl"
#else
	// 带入天空、云、环境光与方块光依赖。
	#include "/effects/lighting/sunlight.glsl"
	// 体积雾、水下体积雾、地面大气散射、原版雾，并带入水面与阴影。
	#include "/effects/fog/fog.glsl"
#endif
// 反射合并 `CalculateSpecularReflections`。
#include "/effects/reflection/reflection.glsl"
// 浦肯野效应 `PurkinjeEffect`。
#include "/effects/color/color.glsl"
// 景深弥散 `CoCSpread` 与镜头光斑 `LensFlare`，并提供镜头选项。
#include "/effects/lens/lens.glsl"
// 选择框 `SelectionBox`。
#include "/effects/ground/selection.glsl"
#if defined OMNI_NETHER || defined OMNI_END
// 下界与末地的合成五号原程序只写一号画面，不画镜头光斑，所以这里不声明三号输出。
#else
#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE || (defined OMNI_VFOG && defined OMNI_VFOG_BLOOM && !defined OMNI_DOF)
	layout(location = 1) out vec4 compositeOutput3; // 三号画面：镜头光斑，仅在开启相关效果时写出。
#endif
#endif
#if defined OMNI_NETHER
// 下界合成五号：折射与彩色玻璃用下界版，雾用 `NetherFog`（来自 `world-1/composite5.fsh`）。
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSoild = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		bool isDH = gbuffer.depthW == 1.0; // 标记远景像素。
		if (isDH){ // 半透明表面是天空像素时改读远景深度。
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}

		if (gbuffer.depthL == 1.0){ // 不透明表面是天空像素时改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSoild = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSoild) + materialMaskSoild.sky * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + materialMask.sky * 1e10, farDist); // 半透明表面距离，天空给很远。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.ice + materialMask.stainedGlass > 0.5) // 冰面与彩色玻璃做折射。
		WaterRefractionLiteNether(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist); // 下界折射。

	if (materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
		TransparentAbsorptionNether(color, gbuffer.albedoW); // 下界彩色玻璃吸收。

	if (materialMask.water + materialMask.ice > 0.5 || isEyeInWater == 1) // 水与冰整体染一点冷色。
		color *= vec3(0.5, 0.55, 0.7); // 下界水色。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, 1.0, gbuffer.material); // 合并三号画面的反射，下界不用水吸收。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if(heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	color += NetherFog(waterDist); // 下界整条视线的雾。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSoild.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		#ifdef DISTANT_HORIZONS
			if (isDH) gbuffer.depthW = ScreenDepth_From_DHScreenDepth(gbuffer.depthW); // 深度换回近景尺度。
		#endif
		compositeOutput1 = vec4(color.rgb, gbuffer.depthW); // 否则透明通道存深度。
	#endif
}
#elif defined OMNI_END
// 末地合成五号：折射与彩色玻璃用末地版，雾用 `EndFog`（来自 `world1/composite5.fsh`）。
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	float globalCloudShadow = 1.0; // 原程序保留的占位，末地不走体积雾，本值不被使用。

	FixParticleMask(materialMaskSoild, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSoild = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){ // 半透明表面是天空像素时改读远景深度。
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}

		if (gbuffer.depthL == 1.0){ // 不透明表面是天空像素时改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSoild = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSoild) + materialMaskSoild.sky * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + materialMask.sky * 1e10, farDist); // 半透明表面距离，天空给很远。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.water + materialMask.ice + materialMask.stainedGlass > 0.5) // 水、冰与彩色玻璃做折射。
		WaterRefractionLiteEnd(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist); // 末地折射。

	if (materialMask.stainedGlass > 0.5) // 彩色玻璃吸收。
		TransparentAbsorptionEnd(color, gbuffer.albedoW); // 末地彩色玻璃吸收。

	if (materialMask.water + materialMask.ice > 0.5 || isEyeInWater == 1) // 水与冰整体染一点冷色。
		color *= vec3(0.5, 0.55, 0.7); // 末地水色。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才合并反射。
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, 1.0, gbuffer.material); // 合并三号画面的反射，末地不用水吸收。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if(heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	color += EndFog(waterDist, worldDir); // 末地整条视线的雾。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSoild.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		compositeOutput1 = vec4(color.rgb, 0.0); // 否则透明通道留零。
	#endif
}
#else // 主世界
void main(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSolid, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。
	vec3 viewPosSolid = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}
		if (gbuffer.depthL == 1.0){
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPosSolid = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos.xyz); // 视线方向。
	vec3 worldDir = normalize(worldPos.xyz); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		float farDist = max(far * 1.4, 1024.0); // 否则用近景远裁剪面。
	#endif
	float opaqueDist = min(length(viewPosSolid) + float(gbuffer.depthL == 1.0) * 1e10, farDist); // 不透明表面距离，天空给很远。
	float waterDist = min(length(viewPos) + float(gbuffer.depthW == 1.0) * 1e10, farDist); // 半透明表面距离，天空给很远。

	float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
	#ifndef OMNI_VFOG_IGNORE_WORLDTIME
		#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
			fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7)); // 按昼夜与所在群系降水调整。
		#else
			fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 只按昼夜与整体湿润度调整。
		#endif
	#endif

	float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾与光柱使用。

	vec3 color = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb); // 读一号画面当前颜色。

	if (materialMask.water + materialMask.ice + materialMask.stainedGlass > 0.5)
		WaterRefractionLite(color, materialMask, gbuffer.normalW, worldPos, viewPos, waterDist, opaqueDist, fogTimeFactor, globalCloudShadow, texCoord, texelCoord); // 水玻璃冰做折射。

	float waterAbsorption = 1.0; // 水的吸收系数。
	if (isEyeInWater == 1) waterAbsorption = saturate(exp2(-waterDist * 0.06 * OMNI_WATERFOG_DENSITY)); // 水下按距离算吸收。

	if (materialMask.stainedGlass > 0.5)
		TransparentAbsorption(color, gbuffer.albedoW, waterAbsorption); // 彩色玻璃吸收。

	if (gbuffer.material.reflectionStrength > 0.0)
		CalculateSpecularReflections(color, viewDir, gbuffer.normalW, gbuffer.albedo, waterAbsorption, gbuffer.material); // 合并三号画面的反射。

	color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾与散射按此单位工作。

	#ifdef OMNI_SPECULAR_HELDLIGHT
		if (heldBlockLightValue + heldBlockLightValue2 > 0.0 && materialMask.sky < 0.5)
			TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material); // 手持光高光。
	#endif

	#ifdef DISTANT_HORIZONS
		#ifdef OMNI_DH_LIMIT_VFOG_DIST
			vec3 rayWorldPos = worldDir * min(waterDist, max(float(dhRenderDistance), far) * 1.4); // 雾气射线终点，限制在一百区块内。
		#else
			vec3 rayWorldPos = worldDir * min(length(worldPos) + float(gbuffer.depthW == 1.0) * 1e10, max(float(dhRenderDistance), far) * 1.4); // 不限制时的射线终点。
		#endif
	#else
		vec3 rayWorldPos = worldDir * min(waterDist, far * 1.4); // 没有远景时用近景可视距离。
	#endif

	#ifdef OMNI_LANDSCATTERING
		LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5); // 地面大气散射。
	#endif

	#ifdef OMNI_VFOG
		#ifdef OMNI_UNDERWATER_VFOG
			if (isEyeInWater == 1) color += UnderwaterVolumetricFog(vec3(0.0), worldPos, worldDir, globalCloudShadow); // 水下体积雾光柱。
		#endif

		float fogTransmittance = 1.0; // 体积雾透射率。
		if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 体积雾。
	#endif

	if(isEyeInWater == 0.0 && wetness > 0.0) Rain(color, gbuffer.rainAlpha, colorShadowlight, colorSkylight); // 雨中画面。

	VanillaFog(color, waterDist); // 原版雾、失明、黑暗、岩浆雪盲。

	SelectionBox(color, gbuffer.albedo, materialMaskSolid.selection > 0.5 && isEyeInWater < 3); // 选择框上色。

	#ifdef OMNI_PURKINJE_EFFECT
		PurkinjeEffect(color); // 暗处色偏。
	#endif

	color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
	color = LinearToCurve(color); // 四次方根编码。

	#ifdef OMNI_DOF
		compositeOutput1 = vec4(color.rgb, CoCSpread()); // 景深开启时透明通道存弥散范围。
	#else
		compositeOutput1 = vec4(color.rgb, 0.0); // 否则透明通道留零。
	#endif

	#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE || (defined OMNI_VFOG && defined OMNI_VFOG_BLOOM && !defined OMNI_DOF)
		compositeOutput3 = vec4(0.0); // 默认没有镜头光斑。

		#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE
			if (sunVisibility > 0.0 && isEyeInWater == 0) compositeOutput3.rgb = LensFlare(); // 看得到太阳时画眩光与光斑。
		#endif

		#if defined OMNI_VFOG && defined OMNI_VFOG_BLOOM && !defined OMNI_DOF
			compositeOutput3.a = 1.0 - fogTransmittance; // 体积雾泛光引导存进透明通道。
		#endif
	#endif
}
#endif // 维度分支结束。
#endif // 合成五号结束。

#endif // 文件守卫结束。
