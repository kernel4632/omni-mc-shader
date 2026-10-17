/*
远景绘制主体：把 iterationT 的远景地形与远景水四组程序合成一个主体文件。
来源：`Lib/Programs/Gbuffers/DH_Terrain_VS.glsl`、`DH_Terrain_FS.glsl`、`DH_Water_VS.glsl`、`DH_Water_FS.glsl`
  一比一移植；原程序用入口文件选择，这里用 `OMNI_DH_TERRAIN_PASS` 与 `OMNI_DH_WATER_PASS` 在一个文件里分开。
调用位置：各维度 `dh_terrain`、`dh_water` 入口定义阶段宏与对应程序宏后引入本文件；入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_DH_WATER_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/distant.glsl"`。
输出约定：远景地形写零号、三号、五号，对应 `DRAWBUFFERS:035`；远景水写四号、六号，对应 `DRAWBUFFERS:46`。
设计原因与取舍：
  远景由加载器按远景模组的投影矩阵绘制，顶点用远景投影，片元只处理贴图噪声、剔除与简单的湿润；
  远景地形的逐块噪声与剔除在 `effects/world/world.glsl`，远景水的波法线在 `effects/water/water.glsl`，
  过绘防护与噪声远距衰减在 `effects/world/distant.glsl`，两者默认关闭，不改变现有画面。
  顶点阶段不引入含 `discard` 与导数函数的效果文件；`effects/world/world.glsl`、`effects/water/water.glsl` 都只用力的片元。
  注意：`effects/water/water.glsl` 合并了水波与雨点，雨点函数依赖 `gaux1` 到 `gaux3` 与 `rainStrength`，而 iterationT 的
  远景水只引入水波；`effects/weather/weather.glsl` 的雨函数依赖 `colorShadowlight` 与 `colorSkylight`，这里按需声明。
*/
#ifndef OMNI_DISTANT_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_DISTANT_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：曲线、法线编解码与打包。
#include "/common/math.glsl"
// 远景程序依赖加载器在开启远景模组时提供的投影与材质编号；基础环境缺这些名字，按原程序取值补回退。
// 为什么用 `#ifndef`：开启远景模组时由加载器与构建环境注入，重复定义会报错。
#ifndef DISTANT_HORIZONS
	uniform mat4 dhProjection; // 远景投影矩阵。
	const int dhMaterialId = 0; // 远景材质编号，基础环境当作普通方块。
#endif
#ifndef DH_BLOCK_UNKNOWN
	#define DH_BLOCK_UNKNOWN 0
	#define DH_BLOCK_LEAVES 1
	#define DH_BLOCK_STONE 2
	#define DH_BLOCK_WOOD 3
	#define DH_BLOCK_METAL 4
	#define DH_BLOCK_DIRT 5
	#define DH_BLOCK_LAVA 6
	#define DH_BLOCK_DEEPSLATE 7
	#define DH_BLOCK_SNOW 8
	#define DH_BLOCK_SAND 9
	#define DH_BLOCK_TERRACOTTA 10
	#define DH_BLOCK_NETHER_STONE 11
	#define DH_BLOCK_WATER 12
	#define DH_BLOCK_GRASS 13
	#define DH_BLOCK_AIR 14
	#define DH_BLOCK_ILLUMINATED 15
#endif
// 时间抗锯齿选项：远景顶点抖动要用。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MATID_*` 与物理光照选项。
#include "/effects/ground/material.glsl"
// 行星曲率：远景顶点要与近景地形做同一次下沉，否则交界处会错位，选项与算法都在该文件。
#include "/effects/world/planet.glsl"
// 远景噪声与剔除、水面波法线都只在片元引入。
#ifdef OMNI_FRAGMENT
	// 天气选项与雨函数：远景地形的湿润要读 `OMNI_SURFACE_WETNESS`。
	#include "/effects/weather/weather.glsl"
	// 天气的 `Rain` 读取阳光与天光颜色，按它的调用前提给两个空全局。
	vec3 colorShadowlight; // 阳光颜色，本程序不调用 `Rain`。
	vec3 colorSkylight; // 天光颜色，本程序不调用 `Rain`。
	// 天气的风偏移读取露天标记，按它的调用前提给一个空输入。
	// 水面与雨点：远景水要 `GetWavesNormal`；雨点函数要涟漪贴图与降雨强度，一并声明。
	uniform sampler2D gaux1; // 雨点第一张动画贴图，本程序不调用雨点函数。
	uniform sampler2D gaux2; // 雨点第二张动画贴图。
	uniform sampler2D gaux3; // 雨点第三张动画贴图。
	uniform float rainStrength; // 降雨强度。
	// 波浪、涟漪与水波法线。
	#include "/effects/water/water.glsl"
	// 远景噪声与剔除。
	#include "/effects/world/world.glsl"
	// 远景附加能力：过绘防护与噪声远距衰减。
	#include "/effects/world/distant.glsl"
#endif

#ifdef OMNI_VERTEX // 顶点阶段：远景地形与远景水分开写。
#if defined OMNI_DH_TERRAIN_PASS // 远景地形顶点着色器。
// 传给片元的插值量。
out vec3 color; // 顶点色。
out vec3 viewPos; // 视空间位置。
out vec3 viewNormal; // 视空间法线。
out vec2 blockLight; // 方块光与天光。
flat out float materialIDs; // 材质编号。


// 顶点主函数：远景投影，按远景材质编号挑类别。
void main(){
	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec3 planetViewPos = v_viewPos.xyz; // 复制视空间位置给行星曲率改写。
	omniPlanetCurvatureView(planetViewPos); // 行星曲率：远景地形与近景地形同一次下沉，交界处才接得上。
	v_viewPos.xyz = planetViewPos; // 写回下沉后的视空间位置。
	viewPos = v_viewPos.xyz; // 传给片元，用下沉后的位置重建世界坐标。
	gl_Position = dhProjection * v_viewPos; // 用远景投影。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color.rgb; // 顶点色取三通道。
	viewNormal = normalize(gl_NormalMatrix * gl_Normal); // 法线转到视空间。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

	materialIDs = 1.0; // 默认普通方块。

	switch(dhMaterialId){ // 按远景材质编号分类。
	// 树叶。
		case DH_BLOCK_LEAVES:
			materialIDs = MATID_LEAVES; // 记为树叶。
			break; // 结束该分支。
		case DH_BLOCK_SNOW:
			materialIDs = MATID_LEAVES + 0.1; // 雪用树叶编号加一点，后面按小数部分判断。
			break; // 结束该分支。
	// 岩浆。
		case DH_BLOCK_LAVA:
			materialIDs = MATID_LAVA; // 记为岩浆。
			break; // 结束该分支。
	// 荧石与灯。
		case DH_BLOCK_ILLUMINATED:
			materialIDs = MATID_GLOWSTONE; // 记为荧石。
			break; // 结束该分支。
	}

	if (materialIDs == 1.0 && blockLight.x > 0.93) materialIDs = MATID_GLOWSTONE; // 方块光很高的自身发光方块也算荧石。
}
#elif defined OMNI_DH_WATER_PASS // 远景水顶点着色器。
// 传给片元的插值量。
out vec4 color; // 顶点色。
out vec3 viewPos; // 视空间位置。
out mat3 tbn; // 切线基。
out vec2 blockLight; // 方块光与天光。
flat out float materialIDs; // 材质编号。


// 顶点主函数：按面法线构造切线基，按远景材质编号挑水或普通表面。
void main(){
	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec3 planetViewPos = v_viewPos.xyz; // 复制视空间位置给行星曲率改写。
	omniPlanetCurvatureView(planetViewPos); // 行星曲率：远景水与近景水面同一次下沉，交界处才接得上。
	v_viewPos.xyz = planetViewPos; // 写回下沉后的视空间位置。
	viewPos = v_viewPos.xyz; // 传给片元，用下沉后的位置重建世界坐标。
	gl_Position = dhProjection * v_viewPos; // 用远景投影。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color; // 顶点色。

	vec3 T = vec3(0.0); // 切线初值。
	vec3 B = vec3(0.0); // 副切线初值。
	vec3 N = normalize(gl_NormalMatrix * gl_Normal); // 法线转到视空间。

	if (gl_Normal.x > 0.5) { // 朝正横轴的面。
		T = normalize(gl_NormalMatrix * vec3( 0.0,  0.0, -1.0)); // 切线取纵轴负向。
		B = normalize(gl_NormalMatrix * vec3( 0.0, -1.0,  0.0)); // 副切线取竖轴负向。
	} else if (gl_Normal.x < -0.5){ // 朝负横轴的面。
		T = normalize(gl_NormalMatrix * vec3( 0.0,  0.0,  1.0)); // 切线取纵轴正向。
		B = normalize(gl_NormalMatrix * vec3( 0.0, -1.0,  0.0)); // 副切线取竖轴负向。
	} else if (gl_Normal.y > 0.5){ // 朝上。
		T = normalize(gl_NormalMatrix * vec3( 1.0,  0.0,  0.0)); // 切线取横轴正向。
		B = normalize(gl_NormalMatrix * vec3( 0.0,  0.0,  1.0)); // 副切线取纵轴正向。
	} else if (gl_Normal.y < -0.5){ // 朝下。
		T = normalize(gl_NormalMatrix * vec3( 1.0,  0.0,  0.0)); // 切线取横轴正向。
		B = normalize(gl_NormalMatrix * vec3( 0.0,  0.0,  1.0)); // 副切线取纵轴正向。
	} else if (gl_Normal.z > 0.5){ // 朝正纵轴。
		T = normalize(gl_NormalMatrix * vec3( 1.0,  0.0,  0.0)); // 切线取横轴正向。
		B = normalize(gl_NormalMatrix * vec3( 0.0, -1.0,  0.0)); // 副切线取竖轴负向。
	} else if (gl_Normal.z < -0.5){ // 朝负纵轴。
		T = normalize(gl_NormalMatrix * vec3(-1.0,  0.0,  0.0)); // 切线取横轴负向。
		B = normalize(gl_NormalMatrix * vec3( 0.0, -1.0,  0.0)); // 副切线取竖轴负向。
	}
	
	tbn = mat3(T, B, N); // 组装切线基。

	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。
	
	materialIDs = MATID_STAINEDGLASS; // 默认按染色玻璃处理。

	if (dhMaterialId == DH_BLOCK_WATER){ // 远景水材质。
		materialIDs = MATID_WATER; // 记为水。
	}
}
#endif // 顶点程序分支结束。
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_DH_TERRAIN_PASS // 远景地形片元着色器。
/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

// 从顶点阶段接收的插值量。
in vec3 color; // 顶点色。
in vec3 viewPos; // 视空间位置。
in vec3 viewNormal; // 视空间法线。
in vec2 blockLight; // 方块光与天光。
flat in float materialIDs; // 材质编号。


// 片元主函数：先剔除近处远景，再对贴图加噪声、算湿润，最后写三张画面。
void main(){
	DHTerrainCulling(viewPos); // 远景地形剔除：丢掉和正常区块重叠的近处远景块，关闭该选项时函数内不做剔除。

	DHChunkFading(length(viewPos)); // 远景区块淡入：靠近交界时按距离随机淡出，减少远景与近景的硬边。
	omniDHTerrainOverdrawPrevention(length(viewPos)); // 远景过绘防护：丢弃已被近景覆盖的近距离远景。

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; // 还原相机相对世界位置。

// 底色：顶点色，开启噪声时叠逐块噪声。
	vec3 albedo = color; // 底色取顶点色。
	#ifdef OMNI_DH_TEXTURE_NOISE
		vec3 albedoClean = albedo; // 记下未加噪声的底色，供远距衰减混回。
		if (fract(materialIDs) != 0.1) DH_noise(albedo, worldPos + cameraPosition + mat3(gbufferModelView) * viewNormal * 0.001, materialIDs); // 雪不叠噪声，其余按世界位置叠逐块噪声。界位置叠噪声。
		albedo = omniDHNoiseDropoff(albedo, albedoClean, length(viewPos)); // 远景噪声按距离变淡。
	#endif

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo = vec3(1.0); // 调试白光时全白。
	#endif

// 湿润：远景只按半强与朝向，主世界看降雨，其余维度只用地表基础湿润。
	#ifdef OMNI_ENABLE_PBR

		float NdotU = dot(viewNormal, gbufferModelView[1].xyz); // 表面法线与世上方向的夹角。

		#ifdef OMNI_OVERWORLD
			#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
				float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加基础湿润。
			#else
				float wet = wetness + OMNI_SURFACE_WETNESS; // 只看整体降雨。
			#endif
			wet *= 0.5; // 远景压半。
			wet *= saturate(blockLight.y * 10.0 - 9.0); // 只有露天才积雨。
			wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
		#else
			float wet = OMNI_SURFACE_WETNESS; // 只用基础湿润。
			wet *= 0.5; // 压半。
			wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
		#endif

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif

// 法线：远景直接用面法线。
	vec2 normalEnc = EncodeNormal(viewNormal); // 八面体编码法线。


	gbufferOutput0 = vec4(albedo, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(normalEnc, blockLight); // 三号写法线与光照图。
	gbufferOutput5 = vec4(0.0, 0.0, (materialIDs + 0.1) / 255.0, Pack2x8(vec2(wet, 1.0))); // 五号写材质编号与湿润，视差阴影记为一。
}
#elif defined OMNI_FRAGMENT && defined OMNI_DH_WATER_PASS // 远景水片元着色器。
/* DRAWBUFFERS:46 */
layout(location = 0) out vec4 gbufferOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 gbufferOutput6; // 六号半透明颜色材质。

// 从顶点阶段接收的插值量。
in vec4 color; // 顶点色。
in vec3 viewPos; // 视空间位置。
in mat3 tbn; // 切线基。
in vec2 blockLight; // 方块光与天光。
flat in float materialIDs; // 材质编号。


// 片元主函数：被近景挡住的远景水丢弃，再算波法线与打包颜色。
void main(){
	if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x < 1.0) discard; // 已有近景几何遮住时丢弃该远景水像素。

	DHChunkFading(length(viewPos)); // 远景区块淡入：远景水同样在交界处按距离随机淡出。
	omniDHWaterOverdrawPrevention(length(viewPos)); // 远景水过绘防护：丢弃已被近景覆盖的近距离远景水。

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz; // 还原相机相对世界位置。

	
// 底色：顶点色，开启噪声时叠逐块噪声。
	#ifdef OMNI_DH_TEXTURE_NOISE
		vec4 texClean = color; // 记下未加噪声的水色，供远距衰减混回。
		vec4 tex = DH_noise(color, worldPos + cameraPosition + mat3(gbufferModelView) * tbn[2] * 0.001); // 按水表位置叠噪声。
		tex = omniDHNoiseDropoff(tex, texClean, length(viewPos)); // 远景水噪声按距离变淡。
	#else
		vec4 tex = color; // 直接用顶点色。
	#endif


	#ifdef OMNI_WHITE_DEBUG_WORLD
		tex.rgb = vec3(1.0); // 调试白光时全白。
	#endif

// 波法线：水用波浪函数，冰与玻璃用面法线。
	vec3 waterNormal = vec3(0.0, 0.0, 1.0); // 默认朝外。

	vec3 mcPos = worldPos + cameraPosition; // 世界位置。

	bool iswater = materialIDs == MATID_WATER; // 是否为水。
	
	if (iswater){
		waterNormal = GetWavesNormal(mcPos, 18.0); // 远景波高固定，比近景更平。
	}

	waterNormal = tbn * waterNormal; // 转到视空间。

	if (iswater){ // 水面把法线偏向水平。
		vec3 viewDir = normalize(-viewPos); // 视线方向。
		#ifdef DISTANT_HORIZONS
			const float weight = 0.3; // 有远景时的权重。
		#else
			const float weight = 0.07; // 常规权重。
		#endif
		waterNormal = normalize(waterNormal + (tbn[2] / (max(0.0, dot(tbn[2], viewDir)) + 0.001)) * weight); // 按掠射程度把法线拉向面法线。
	}

	vec2 normalEnc = EncodeNormal(waterNormal); // 八面体编码法线。


	gbufferOutput4 = vec4(normalEnc, blockLight); // 四号写法线与方块光。
	gbufferOutput6 = vec4(Pack2x8(tex.rg), Pack2x8(tex.ba), (materialIDs + 0.1) / 255.0, float(iswater)); // 六号打包颜色、材质编号与水遮罩。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
