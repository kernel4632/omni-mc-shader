/*
地形绘制主体：把 iterationT 的地形顶点、几何、片元三个程序搬进一个主体文件。
来源：`Lib/Programs/Gbuffers/Terrain_VS.glsl`、`Terrain_GS.glsl`、`Terrain_FS.glsl` 一比一移植。
调用位置：各维度 `gbuffers_terrain` 的 `.vsh`、`.gsh`、`.fsh` 入口定义阶段宏与 `OMNI_TERRAIN_PASS` 后引入本文件；
  入口按 `rendering/programs.json` 生成，阶段宏是 `OMNI_VERTEX`、`OMNI_GEOMETRY`、`OMNI_FRAGMENT`，维度宏是
  `OMNI_OVERWORLD`、`OMNI_NETHER`、`OMNI_END`。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_TERRAIN_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/terrain.glsl"`。
输出约定：片元写零号贴图色、三号法线光照图、五号高光材质，对应 `DRAWBUFFERS:035`。
设计原因与取舍：
  地形是本项目最重的程序，本文件只保留顶点、几何、片元三个阶段的入口结构与输入输出，算法体拆到效果文件：
  草丛几何体 `effects/ground/grass_geometry.glsl`；片元主函数体与纹理采样、写出都在 `effects/ground/terrain_surface.glsl`。
  顶点入口的植物摆动与材质编号仍按 iterationT 原顺序留在入口里；片元入口只留一次 `omniTerrainFragment()` 调用。
  顶点阶段不引入 `effects/water/water.glsl`：它里面有只有片元能用的导数函数；湿润与雨点只在片元里需要。
  各向异性过滤与自发光模式用到的 `OMNI_TEXTURE_EMISSIVENESS_MODE` 归属 `effects/lighting/blocklight.glsl`，
  只在有高光贴图（`MC_SPECULAR_MAP`）时才引入，避免把整份方块光算法带进地形。
*/
#ifndef OMNI_TERRAIN_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_TERRAIN_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：曲线、法线编解码、打包等。
#include "/common/math.glsl"
// --- 本程序自带的加载器输入：效果文件会读这些名字，必须先于效果文件声明 ---
uniform sampler2D tex; // 方块贴图。
uniform sampler2D normals; // 法线贴图。
uniform sampler2D specular; // 高光贴图，存在高光贴图资源包时才有。
uniform sampler2D gaux1; // 雨点第一张动画贴图。
uniform sampler2D gaux2; // 雨点第二张动画贴图。
uniform sampler2D gaux3; // 雨点第三张动画贴图。
uniform ivec2 atlasSize; // 方块图集尺寸。
uniform int renderStage; // 当前原版绘制阶段，用来区分实体方块与透明方块。
uniform float rainStrength; // 降雨强度，雨点函数读取它。
// 视差函数照 iterationT 原样读取调用方声明的 `viewPos` 与地形 `textureResolution`，而且会被
// `antialiasing` 间接引入（它要用 `MATID_*`），所以片元必须在引入任何效果文件之前先声明这两个插值量。
#ifdef OMNI_FRAGMENT
	in vec3 viewPos; // 不透明表面的视空间位置，视差与切线基都要用它。
	flat in float textureResolution; // 方块纹理分辨率，由几何阶段平面插值传下，视差要用。
#endif
// 时间抗锯齿选项：坐标换算要用它决定是否撤销抖动，必须先于坐标换算引入。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MATID_*`、`ParallaxOcclusionMapping` 与材质相关选项。
#include "/effects/ground/material.glsl"
// 区块淡入：`omniChunkFade*` 一组纯计算，顶点取进度、几何转发、片元按进度抖动丢弃。
#include "/effects/clarity/chunkfade.glsl"
// 时间噪声：片元抖动丢弃要读蓝噪声，顶点与几何阶段只编译不调用。
#include "/common/noise.glsl"
// 植物摆动：提供 `WavingPlants`，顶点阶段的地形与阴影共用同一份摆法。
#include "/effects/ground/vegetation.glsl"
// 程序化草：提供草丛的摆动、方块编号查询与草叶外形；默认关闭，只在主世界编译。
#include "/effects/ground/grass.glsl"
// Omni 额外功能：植被季节色，默认关闭。
#include "/effects/weather/season.glsl"
// Omni 额外功能：积雪覆盖（来源 Eclipse），默认关闭；与季节同属天气相关的地表效果。
#include "/effects/weather/snow.glsl"
// 行星曲率：顶点阶段按相机相对水平距离把远处顶点下沉，选项与算法都在该文件。
#include "/effects/world/planet.glsl"
// 自发光模式选项归属方块光文件，只在有高光贴图时按需引入。
#if defined OMNI_FRAGMENT && defined MC_SPECULAR_MAP
	// 方块光文件读取火把光色，按它的调用前提给一个空全局。
	vec3 colorTorchlight;
	// 方块光与手持光：这里只借它的 `OMNI_TEXTURE_EMISSIVENESS_MODE` 选项。
	#include "/effects/lighting/blocklight.glsl"
#endif
// 水面与水雾：片元算湿润与雨点要用 `GetModulatedRainSpecular`、`GetRainNormal`，只在片元引入。
#ifdef OMNI_FRAGMENT
	// 天气文件里的雨色与风偏移读取阳光、天光与露天标记，按调用前提给空全局；本程序不调用它们。
	vec3 colorShadowlight; // 阳光颜色。
	vec3 colorSkylight; // 天光颜色。
	// 波浪、涟漪、湿润调制与水体光学。
	#include "/effects/water/water.glsl"
#endif
// 坐标换算：屏幕、视空间与深度互转，放在 `OMNI_TAA` 定义之后。
#include "/common/coordinates.glsl"
// 末地需要末地版阴影相机矩阵，只有片元用到，也只有末地用它。
#if defined OMNI_END && defined OMNI_FRAGMENT
	// 阴影：提供末地的 `shadowModelViewInverseEnd`。
	#include "/effects/shadow/shadow.glsl"
#endif

#ifdef OMNI_VERTEX // 顶点阶段：地形顶点着色器。
// 图集采样器与顶点属性由加载器或本程序提供，效果文件读的是这些名字。
// 方块实体编号：用来判定植物、树叶、发光方块等材质类别。
attribute vec4 mc_Entity;
// 方块纹理坐标的中点：用来判断哪一半顶点属于植物上端。
attribute vec4 mc_midTexCoord;
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
// 方块中心相对顶点的偏移：除以六十四得到方块中心，草丛以它为中心摆放。
attribute vec3 at_midBlock;
#endif

// 传给几何阶段的插值量；开关顶点切线时多传一组切线基。
out vec3 v_color; // 顶点色，雨天与调试会改它。
out vec2 v_texCoord; // 方块纹理坐标。
out vec3 v_viewPos; // 视空间位置，片元做切线基与视差要用。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
flat out float v_blockID; // 方块编号，几何阶段挑出草方块顶面用。
flat out float v_grassUp; // 该面是否朝上，只有朝上的面才长草。
flat out vec3 v_blockCenter; // 方块中心的相机相对世界坐标，草丛与隔壁查询都以它为基准。
#endif
#ifdef OMNI_TERRAIN_VS_TBN
	// 顶点切线属性，由模组或资源包提供。
	attribute vec4 at_tangent;
	out mat3 v_tbn; // 顶点切线基，开关时使用。
#endif
out vec2 v_blockLight; // 方块光与天光，零到一，已按原程序曲线重整。
flat out float v_materialIDs; // 材质编号，平面插值避免边界混值。
out float v_chunkFade; // 区块淡入进度，几何阶段转发给片元；关闭或加载器不支持时恒为一。

// 顶点主函数：把原程序的判定与摆动按顺序执行一遍。
void main(){
	#ifdef OMNI_WHITE_DEBUG_WORLD // 调试白光模式：按是否开启遮蔽调试改底色。
		#ifdef OMNI_GTAO // 开启地平线遮蔽时用纯白。
			v_color = vec3(1.0); // 直接给白。
		#else // 未开遮蔽时只保留红色与透明度作为区分。
			v_color = vec3(gl_Color.r, 0.0, gl_Color.a); // 取原色的一三通道。
		#endif
	#else // 正常模式。
		#ifdef OMNI_GTAO // 开启遮蔽调试时保留完整原色。
			v_color = gl_Color.rgb; // 原色直接用。
		#else // 一般情况把原色乘上自身透明度。
			v_color = gl_Color.rgb * gl_Color.a; // 预乘透明度，混合时更符合直觉。
		#endif
	#endif
	v_texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 方块纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	v_blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一，系数照原程序。

	if (mc_Entity.x == 213.0) v_blockLight.x = min(v_blockLight.x, 0.85); // 雨幕方块把方块光压一档，避免过亮。

	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	v_viewPos = viewPos.xyz; // 传给片元。
	float chunkFadeRaw = 1.0; // 加载器不提供淡入进度时保持一，等于区块一直完全显现。
	#ifdef IRIS_FEATURE_FADE_VARIABLE // 请求加载器特性后 `mc_chunkFade` 属性才存在。
		chunkFadeRaw = mc_chunkFade; // 读取原版区块淡入进度：未淡入时为负，淡入完成时为一。
	#endif
	v_chunkFade = omniChunkFadeValue(chunkFadeRaw); // 取正并夹到零到一，选项关闭时返回一。
	vec4 worldPos = gbufferModelViewInverse * viewPos; // 视空间回到相机相对世界坐标。
	worldPos.xyz += cameraPosition.xyz; // 加上相机绝对位置，得到世界坐标。

	#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
		v_blockID = mc_Entity.x; // 记录方块编号，几何阶段按它挑出草方块。
		v_grassUp = step(0.9, gl_Normal.y); // 只有朝上的面才可能是草方块顶面。
		v_blockCenter = worldPos.xyz - cameraPosition.xyz + at_midBlock / 64.0; // 方块中心，去掉相机绝对位置避免插值精度不足。
	#endif

	// 植物摆动：把世界坐标就地改一下，风固定在世界里。
	WavingPlants(worldPos.xyz, mc_Entity.x, v_blockLight.y, gl_MultiTexCoord0.y, mc_midTexCoord.y);

	worldPos.xyz -= cameraPosition.xyz; // 减回相机相对世界坐标。
	worldPos.xyz = omniChunkFadeSlide(worldPos.xyz, v_chunkFade, eyeBrightnessZeroSmooth, far); // 滑动档把远处未淡入的块从下方移入；关闭或不在滑动档时原样返回。
	worldPos.y -= omniPlanetCurvatureDrop(worldPos.xz); // 行星曲率：远处地形沿纵向下沉，模拟星球弯曲；关闭时为零。
	gl_Position = gl_ProjectionMatrix * gbufferModelView * worldPos; // 投影到裁剪空间。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 抖动按齐次坐标缩放后叠加。
	#endif

	#ifdef OMNI_TERRAIN_VS_TBN // 开关顶点切线时构造切线基。
		vec3 N = normalize(gl_NormalMatrix * gl_Normal); // 法线转到视空间。
		vec3 T = normalize(gl_NormalMatrix * at_tangent.xyz); // 切线转到视空间。
		vec3 B = cross(T, N) * sign(at_tangent.w); // 副切线由叉乘与手性得到。
		v_tbn = mat3(T, B, N); // 组装切线基。
	#endif

	v_materialIDs = MATID_LAND; // 默认按普通方块处理。

	#ifdef OMNI_GENERAL_GRASS_FIX // 未指定方块按植物处理：倾斜的面都当作植物。
		vec3 an = abs(gl_Normal); // 取法线绝对值。
		if (all(lessThan(an, vec3(0.99)))){ // 三个分量都不到零点九九，说明是斜面。
			v_materialIDs = MATID_GRASS; // 记为草。
		}
	#endif

	switch(int(mc_Entity.x)){ // 按方块实体编号挑材质类别。
	// 草与植物类编号。
		case 7000: case 7010: case 7011: case 7020: case 7021: case 7040:
			v_materialIDs = MATID_GRASS; // 记为草。
			break; // 结束该分支。

		case 7030: // 树叶编号。
			v_materialIDs = MATID_LEAVES; // 记为树叶。
			break; // 结束该分支。

		case 89: // 荧石方块编号。
			v_materialIDs = MATID_GLOWSTONE; // 记为荧石。
			break; // 结束该分支。

		case 50: // 火把方块编号。
			v_materialIDs = MATID_TORCH; // 记为火把。
			break; // 结束该分支。

		case 10: // 岩浆方块编号。
			v_materialIDs = MATID_LAVA; // 记为岩浆。
			break; // 结束该分支。

		case 51: // 火方块编号。
			v_materialIDs = MATID_FIRE; // 记为火。
			break; // 结束该分支。

		case 76: // 红石火把编号。
			v_materialIDs = MATID_REDSTONE_TORCH; // 记为红石火把。
			break; // 结束该分支。

		case 55: // 红石线编号。
			v_materialIDs = MATID_REDSTONE; // 记为红石线。
			break; // 结束该分支。

		case 7100: // 灵魂火编号。
			v_materialIDs = MATID_SOULFIRE; // 记为灵魂火。
			break; // 结束该分支。

		case 7101: // 紫水晶编号。
			v_materialIDs = MATID_AMETHYST; // 记为紫水晶，下面缺 `break` 与原程序一致，会继续走下一分支。

		case 7102: // 氧化铜灯编号。
			v_materialIDs = MATID_OXIDIZED_BULB; // 记为氧化铜灯。
	}
}
#endif // 顶点阶段结束。

#ifdef OMNI_GEOMETRY // 几何阶段：原程序在这里估方块纹理分辨率，再原样转发三角形。
// 几何阶段输入一个三角形，输出一个三角带。
layout(triangles) in; // 输入三角形。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
#if OMNI_GRASS_QUALITY == 2
layout(triangle_strip, max_vertices = 24) out; // 高密度：基准三角形加七段草叶。
#elif OMNI_GRASS_QUALITY == 1
layout(triangle_strip, max_vertices = 18) out; // 中密度：基准三角形加五段草叶。
#else
layout(triangle_strip, max_vertices = 12) out; // 低密度：基准三角形加三段草叶。
#endif
#else
layout(triangle_strip, max_vertices = 3) out; // 关闭草丛时只转发原来的三个顶点。
#endif

// 方块图集尺寸，由加载器提供。

// 接收顶点阶段的插值量。
in vec3 v_color[]; // 顶点色数组。
in vec2 v_texCoord[]; // 纹理坐标数组。
in vec3 v_viewPos[]; // 视空间位置数组。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
flat in float v_blockID[]; // 方块编号数组。
flat in float v_grassUp[]; // 朝上标记数组。
flat in vec3 v_blockCenter[]; // 方块中心数组。
// 九号画面：上一帧记下的方块编号与生物群系，草丛按它判断隔壁方块。
uniform sampler2D colortex9;
#endif
#ifdef OMNI_TERRAIN_VS_TBN
	in mat3 v_tbn[]; // 切线基数组。
#endif
in vec2 v_blockLight[]; // 方块光数组。
flat in float v_materialIDs[]; // 材质编号数组。
in float v_chunkFade[]; // 区块淡入进度数组。

// 转发给片元的插值量。
out vec3 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec3 viewPos; // 视空间位置。
#ifdef OMNI_TERRAIN_VS_TBN
	out mat3 tbn; // 切线基。
#endif
out vec2 blockLight; // 方块光。
flat out float materialIDs; // 材质编号。
flat out float textureResolution; // 该三角形所属方块的纹理分辨率，平面插值。
out float chunkFade; // 区块淡入进度，片元按它抖动丢弃。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
flat out float blockID; // 方块编号，片元写九号画面用。
#endif

// 草丛几何算法体在效果文件里，本文件只按开关调用。
#include "/effects/ground/grass_geometry.glsl"

// 几何主函数：先估分辨率，再逐顶点转发。
void main(){
	#if OMNI_TEXTURE_RESOLUTION == 0 // 自动模式：由三角形在屏幕上的纹理密度反推分辨率。
		vec2 coordSize = max(max(abs(v_texCoord[0] - v_texCoord[1]) / distance(v_viewPos[0], v_viewPos[1]), // 第一条边的纹理变化比距离。
								 abs(v_texCoord[1] - v_texCoord[2]) / distance(v_viewPos[1], v_viewPos[2])), // 第二条边。
								 abs(v_texCoord[2] - v_texCoord[0]) / distance(v_viewPos[2], v_viewPos[0])); // 第三条边，取最大者。

		textureResolution = floor(max(atlasSize.x * coordSize.x, atlasSize.y * coordSize.y) + 0.5); // 换成图集像素估算。
		textureResolution = exp2(round(log2(textureResolution))); // 取到最近的二的幂，资源包纹理通常是二的幂。
	#else // 手动模式：直接用玩家设置的方块纹理分辨率。
		textureResolution = OMNI_TEXTURE_RESOLUTION; // 取选项值。
	#endif

	for (int i = 0; i < 3; i++){ // 逐个顶点转发。
		gl_Position = gl_in[i].gl_Position; // 位置照抄。

		color = v_color[i]; // 转发顶点色。
		texCoord = v_texCoord[i]; // 转发纹理坐标。
		viewPos = v_viewPos[i]; // 转发视空间位置。
		#ifdef OMNI_TERRAIN_VS_TBN
			tbn = v_tbn[i]; // 转发切线基。
		#endif
		blockLight = v_blockLight[i]; // 转发方块光。
		materialIDs = v_materialIDs[i]; // 转发材质编号。
		#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
			blockID = v_blockID[i]; // 转发方块编号，片元写九号画面。
		#endif
		chunkFade = v_chunkFade[i]; // 转发区块淡入进度。

		EmitVertex(); // 发出顶点。
	}
	EndPrimitive(); // 结束三角形。

	// 草丛：只对草方块朝上的面、且在范围内生成；算法体在 `effects/ground/grass_geometry.glsl`。
	#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
		omniGrassGeometry(); // 生成草叶顶点，内部按距离分级并查隔壁方块。
	#endif
}
#endif // 几何阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_TERRAIN_PASS // 片元阶段：地形片元着色器。
/* DRAWBUFFERS:0359 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。
layout(location = 3) out vec4 gbufferOutput9; // 九号方块编号与生物群系，草阶段下一帧查询用。

// 从几何阶段接收的插值量。
in vec3 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
// `in vec3 viewPos;` 已在文件顶部、引入视差函数之前声明。
#ifdef OMNI_TERRAIN_VS_TBN
	in mat3 tbn; // 切线基。
#endif
in vec2 blockLight; // 方块光。
flat in float materialIDs; // 材质编号。
in float chunkFade; // 区块淡入进度，按它抖动丢弃新加载区块的像素。
// `flat in float textureResolution;` 已在文件顶部、引入视差函数之前声明。
#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
flat in float blockID; // 方块编号，写九号画面用。
uniform int biome; // 当前像素所在的生物群系编号，写九号画面用。
#endif

// 地形表面采样与写出在效果文件里，本文件只按阶段调用。
#include "/effects/ground/terrain_surface.glsl"


// 片元主函数：算法体在 `effects/ground/terrain_surface.glsl`，这里只调用。
void main(){ omniTerrainFragment(); }
#endif // 片元阶段结束。
#endif // 文件守卫结束。
