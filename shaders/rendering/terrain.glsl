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
  地形是本项目最重的程序，顶点做植物摆动与材质编号判定，几何做纹理分辨率估计，片元做视差、各向异性过滤、
  遮挡、湿润与打包。算法函数都留在效果文件里，这里只按 iterationT 的顺序串起流程与输入输出。
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

	// --- 草丛：只对草方块朝上的面、且在范围内生成；关闭选项或不在主世界时整段不编译 ---
	#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
		vec3 grassCenter = (v_viewPos[0] + v_viewPos[1] + v_viewPos[2]) / 3.0; // 面中心，视空间。
		float grassDist = length(grassCenter); // 到相机的距离，用来分级密度与高度。
		if (v_blockID[0] == OMNI_GRASS_BLOCK_ID && v_grassUp[0] > 0.5 && grassDist < OMNI_GRASS_RANGE){ // 草方块顶面且在范围内才长草。
			vec3 viewUp = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0); // 视空间里的世界竖直方向。
			vec3 viewEast = mat3(gbufferModelView) * vec3(1.0, 0.0, 0.0); // 视空间里的世界东方向，给隔壁查询用。
			vec3 viewSouth = mat3(gbufferModelView) * vec3(0.0, 0.0, 1.0); // 视空间里的世界南方向。

			// 按距离选段数：近处多几段，远处只留一片大叶，顶点数不超标。
			#if OMNI_GRASS_QUALITY == 2
				int triangle_count = 7; float heightMult = 1.1; // 高密度起始值。
				if (grassDist > 2.5) { triangle_count = 5; heightMult = 1.5; } // 稍远处减一段并加高。
				if (grassDist > 5.5) { triangle_count = 3; heightMult = 2.25; } // 更远再减并加高。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#elif OMNI_GRASS_QUALITY == 1
				int triangle_count = 5; float heightMult = 1.5; // 中密度起始值。
				if (grassDist > 7.5) { triangle_count = 3; heightMult = 2.25; } // 稍远处减段加高。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#else
				int triangle_count = 3; float heightMult = 2.25; // 低密度起始值。
				if (grassDist > 0.75 * OMNI_GRASS_RANGE) { triangle_count = 1; heightMult = 5.0; } // 最远处只留一片大叶。
			#endif

			// 隔壁方块：读九号画面上一帧记下的编号，判断四个水平邻居是不是草方块。
			// 为什么按邻居的屏幕像素读：世界坐标只有投影到屏幕才有对应的记录。
			float neighborE = omniGrassBlockAt(colortex9, grassCenter + viewEast, gbufferProjection, screenSize); // 东邻居。
			float neighborW = omniGrassBlockAt(colortex9, grassCenter - viewEast, gbufferProjection, screenSize); // 西邻居。
			float neighborS = omniGrassBlockAt(colortex9, grassCenter + viewSouth, gbufferProjection, screenSize); // 南邻居。
			float neighborN = omniGrassBlockAt(colortex9, grassCenter - viewSouth, gbufferProjection, screenSize); // 北邻居。
			// 编号为零表示这一像素没有记录（新加载、被遮挡或第一帧），当作草处理，避免整片草被压低。
			float openE = (neighborE < 0.5 || abs(neighborE - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 东边是否开口。
			float openW = (neighborW < 0.5 || abs(neighborW - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 西边是否开口。
			float openS = (neighborS < 0.5 || abs(neighborS - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 南边是否开口。
			float openN = (neighborN < 0.5 || abs(neighborN - OMNI_GRASS_BLOCK_ID) < 0.5) ? 1.0 : 0.0; // 北边是否开口。
			float openAvg = (openE + openW + openS + openN) * 0.25; // 四周平均开口程度。
			heightMult *= mix(0.65, 1.0, openAvg) * OMNI_GRASS_HEIGHT; // 旁边不是草就让草矮一点，避免越过台阶。

			// 草叶横向宽度方向：取竖直方向与视线方向的叉乘；正对竖直方向时退回东方向，避免除零。
			vec3 sideRaw = cross(viewUp, normalize(grassCenter)); // 横向宽度方向的原始方向。
			if (length(sideRaw) < 1e-4) sideRaw = viewEast; // 视线与竖直方向平行时换一个方向。
			vec3 bladeSide = normalize(sideRaw) * OMNI_GRASS_BASE_THICKNESS; // 收放到草叶宽度。

			vec2 seed = v_blockCenter[0].xz; // 方块中心的相机相对水平坐标当随机种子，同一方块每次结果一致。
			vec2 randomDir = 2.0 * (texture(noisetex, 0.75 * seed).xy + texture(noisetex, 0.35 * seed.yx).xy) - 1.0; // 两组噪声拼出稳定随机方向。
			vec2 windWorld = omniGrassWindOffset(v_blockCenter[0] + cameraPosition); // 风在方块中心处的世界位移。
			vec3 windView = mat3(gbufferModelView) * vec3(windWorld.x, 0.0, windWorld.y); // 风换成视空间。

			for (int j = 0; j < triangle_count; j++){ // 逐段拼出一片草叶。
				for (int i = 0; i < 3; i++){ // 每段三个顶点。
					vec3 offset = omniGrassBladeVertex(viewUp, bladeSide, heightMult, j, triangle_count, i); // 该角相对底部的偏移。
					float height = clamp(dot(offset, viewUp) / max(heightMult, 1e-4) * 0.5, 0.0, 1.0); // 沿竖直的高度比例。
					vec3 bladePos = grassCenter + offset; // 草叶顶点位置。
					bladePos += windView * height * height; // 越高越被风吹弯。
					bladePos += normalize(bladeSide) * OMNI_GRASS_RANDOMNESS * randomDir.x * height; // 每片草随机方向的小弯。

					gl_Position = gbufferProjection * vec4(bladePos, 1.0); // 投影到裁剪空间。
					#ifdef OMNI_TAA
						gl_Position.xy += taaJitter * gl_Position.w; // 与顶点阶段一致地加本帧抖动，避免草叶和时间抗锯齿错位。
					#endif

					color = v_color[i]; // 草叶底色沿用源顶点色。
					texCoord = v_texCoord[i]; // 贴图坐标沿用源顶点，草叶显示草方块的贴图。
					viewPos = bladePos; // 视空间位置，片元做切线基与视差要用。
					blockLight = v_blockLight[i]; // 方块光沿用源顶点。
					materialIDs = MATID_GRASS; // 草叶按草处理，湿润与光照走草的路径。
					chunkFade = v_chunkFade[i]; // 新加载区块的草叶同样淡入。
					blockID = v_blockID[i]; // 编号沿用源顶点，片元写九号画面时仍是草方块。
					EmitVertex(); // 发出草叶顶点。
				}
				EndPrimitive(); // 一段草叶结束。
			}
		}
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

// 各向异性过滤：沿屏幕上的纹理压缩方向多采几步，换回更清晰的远处方块。
vec4 SampleAnisotropic(vec2 coord, vec2 duv1, vec2 duv2, inout vec3 normalTex, inout vec4 specularTex, out float materialAO){
	materialAO = 1.0; // 材质遮蔽系数默认一：没有法线贴图或没开遮蔽时都不压暗底色。
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少图块。
	vec2 tilesCoord = coord * atlasTiles; // 坐标换到图块单位。

	// 采样方向由屏幕导数求出，参考原程序给出的着色器写法。
	mat2 qd = inverse(mat2(dFdx(tilesCoord), dFdy(tilesCoord))); // 屏幕导数矩阵求逆。
	qd = transpose(qd) * qd; // 转成对称矩阵。

	float d = determinant(qd); // 行列式。
	float t = (qd[0][0] + qd[1][1]) * 0.5; // 迹的一半。

	float D = sqrt(abs(t * t - d)); // 特征值差的半值。
	float V = t - D; // 较小的特征值。
	float v = t + D; // 较大的特征值。
	vec2 A = vec2(-qd[0][1], qd[0][0] - V); // 对应较小特征值的特征向量。
	A *= inversesqrt(V * dot(A, A) + 1e-20); // 归一化，避免除零。

	float lod = log2(inversesqrt(v) * textureResolution); // 由较大特征值推出采样层级。

	const float steps = OMNI_ANISOTROPIC_FILTERING_QUALITY; // 采样步数来自选项。
	const float rSteps = 1.0 / OMNI_ANISOTROPIC_FILTERING_QUALITY; // 每步的比例。

	A *= rSteps; // 特征向量缩放成每步位移。

	vec4 albedoSample = vec4(0.0); // 底色累加量。
	#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR // 开关时连法线与高光一起过滤。
		vec3 normalSample = vec3(0.0); // 法线累加量。
		vec4 specularSample = vec4(0.0); // 高光累加量。
	#endif

	vec2 tilesBaseCoord = floor(tilesCoord); // 当前图块位置。

	for (float i = 0.5 - steps * 0.5; i < steps * 0.5; i++){ // 沿特征向量均匀取几步。
		vec2 sampleCoord = i * A; // 这一步的偏移。
		sampleCoord = (tilesBaseCoord + fract(tilesCoord + sampleCoord)) / atlasTiles; // 回到零到一坐标，图块内回绕避免跨块。

		vec4 sampleAlbedo = textureLod(tex, sampleCoord, lod); // 读一步底色。

		albedoSample += vec4(sampleAlbedo.rgb * sampleAlbedo.a, sampleAlbedo.a); // 颜色按透明度加权累加。

		#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR

			#ifdef MC_NORMAL_MAP
				normalSample += textureLod(normals, sampleCoord, lod).rgb * sampleAlbedo.a; // 法线按透明度加权。
			#endif

			#ifdef MC_SPECULAR_MAP
				#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
					specularSample += textureLod(specular, sampleCoord, lod) * sampleAlbedo.a; // 仅硬编码模式也过滤高光。
				#endif
			#endif

		#endif
	}

	float weights = 1.0 / albedoSample.a; // 权重和的倒数。

	#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR

		#ifdef MC_NORMAL_MAP
			vec4 materialNormal = omniMaterialNormal(normalSample * weights); // 归一化后解码法线，并按选项缩放起伏、取出材质遮蔽。
			normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
			materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
		#endif

		#ifdef MC_SPECULAR_MAP
			#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
				specularTex = specularSample * weights; // 归一化高光。
			#else
				specularTex = textureLod(specular, coord, 0.0); // 其余模式不过滤高光，只取一次。
			#endif
		#endif

	#else

		#ifdef MC_NORMAL_MAP
			vec4 materialNormal = omniMaterialNormal(textureGrad(normals, coord, duv1, duv2).rgb); // 按屏幕导数采法线，并按选项缩放起伏、取出材质遮蔽。
			normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
			materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
		#endif

		#ifdef MC_SPECULAR_MAP
			#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
				specularTex = textureGrad(specular, coord, duv1, duv2); // 仅硬编码模式按屏幕导数采高光。
			#else
				specularTex = textureLod(specular, coord, 0.0); // 其余模式只取一次。
			#endif
		#endif

	#endif
	
	return vec4(albedoSample.rgb * weights, textureLod(tex, coord, 0.0).a); // 颜色归一化，透明度取原始值。
}

// 表面采样：按开关走视差、各向异性过滤或屏幕导数采样，得到底色、高光与法线，并可能丢弃透明像素。
// `materialAO` 是资源包法线蓝通道给出的材质遮蔽，未开该功能时恒为一，调用方把它乘到底色。
void SampleTerrainSurface(mat3 tbn, vec2 coord, vec2 duv1, vec2 duv2, vec3 shadowVector, inout float parallaxShadow, out vec4 albedoTex, out vec4 specularTex, out vec3 normalTex, out float materialAO){
	materialAO = 1.0; // 默认不压暗：视差路径与没有法线的情形都保持一。
	#if OMNI_PARALLAX_MODE > 0 && defined MC_NORMAL_MAP // 开启视差且有法线贴图时走视差路径。

		normalTex = vec3(0.0, 0.0, 1.0); // 视差函数会写回法线。
		ivec2 parallaxTexel = ParallaxOcclusionMapping(coord, tbn, shadowVector, duv1, duv2, normalTex, parallaxShadow); // 找到可见交点。
		albedoTex = texelFetch(tex, parallaxTexel, 0); // 精确取交点底色。

		#if MC_VERSION >= 11605 && !defined IS_IRIS // 新版区分实体方块与透明方块，丢弃阈值不同。
			float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 实体方块用更小阈值。
		#else
			float alphaRef = 0.1; // 旧版与 Iris 统一用零点一。
		#endif
		if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

		#ifdef MC_SPECULAR_MAP
			specularTex = texelFetch(specular, parallaxTexel, 0); // 精确取交点高光。
		#else
			specularTex = vec4(0.0); // 没有高光贴图时全零。
		#endif

	#else // 未开视差时按各向异性过滤或普通采样取贴图。

		#if OMNI_ANISOTROPIC_FILTERING_QUALITY > 0 // 开启各向异性过滤。

			normalTex = vec3(0.0, 0.0, 1.0); // 过滤函数会写回法线。
			specularTex = vec4(0.0); // 过滤函数会写回高光。
			albedoTex = SampleAnisotropic(coord, duv1, duv2, normalTex, specularTex, materialAO); // 各向异性取底色、表面与材质遮蔽。

			#if MC_VERSION >= 11605 && !defined IS_IRIS
				float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 丢弃阈值同视差路径。
			#else
				float alphaRef = 0.1; // 旧版与 Iris 统一。
			#endif
			if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

		#else // 不开过滤时按屏幕导数采一次。

			albedoTex = textureGrad(tex, coord, duv1, duv2); // 按屏幕导数采底色。

			#if MC_VERSION >= 11605 && !defined IS_IRIS
				float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 丢弃阈值同上。
			#else
				float alphaRef = 0.1; // 旧版与 Iris 统一。
			#endif
			if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

			#ifdef MC_NORMAL_MAP
				vec4 materialNormal = omniMaterialNormal(textureGrad(normals, coord, duv1, duv2).rgb); // 采法线并解出材质遮蔽。
				normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
				materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
			#else
				normalTex = vec3(0.0, 0.0, 1.0); // 没有法线贴图时朝外。
			#endif

			#ifdef MC_SPECULAR_MAP
				#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
					specularTex = textureGrad(specular, coord, duv1, duv2); // 仅硬编码模式按屏幕导数采高光。
				#else
					specularTex = textureLod(specular, coord, 0.0); // 其余模式只取一次。
				#endif
			#else
				specularTex = vec4(0.0); // 没有高光贴图时全零。
			#endif
			
		#endif

	#endif
}

// 输出写入：把底色、法线光照与高光材质写进零、三、五号画面。
void WriteTerrainGbuffer(vec3 albedo, vec2 normalEnc, float blockLightDirectional, vec2 blockLight, vec4 specularTex, float materialIDs, float wet, float parallaxShadow){
	gbufferOutput0 = vec4(albedo, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(normalEnc, blockLightDirectional, blockLight.y); // 三号写法线与方块光。
	gbufferOutput5 = vec4(Pack2x8(specularTex.rg), Pack2x8(specularTex.ba), (materialIDs + 0.1) / 255.0, Pack2x8(vec2(wet, parallaxShadow))); // 五号打包高光、材质编号、湿润与视差阴影。
}

// 片元主函数：按原程序顺序算切线基、视差、遮挡、湿润、法线与高光。
void main(){
// 切线基：顶点没给时用屏幕导数推出来。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。
	
	#ifndef OMNI_TERRAIN_VS_TBN // 顶点没提供切线基时现场构造。
		vec3 dp1 = dFdx(viewPos); // 视空间位置横向变化。
		vec3 dp2 = dFdy(viewPos); // 视空间位置纵向变化。

		vec3 N = normalize(cross(dp1, dp2)); // 法线由两条切向叉乘得到。
		vec3 dp2perp = cross(dp2, N); // 与法线正交的纵向切向。
		vec3 dp1perp = cross(N, dp1); // 与法线正交的横向切向。

		vec3 T = normalize(dp2perp * duv1.x + dp1perp * duv2.x); // 由纹理导数解出切线。
		vec3 B = normalize(dp2perp * duv1.y + dp1perp * duv2.y); // 解出副切线。
		float invmax = inversesqrt(max(dot(T, T), dot(B, B))); // 归一化因子。
		mat3 tbn = mat3(T * invmax, B * invmax, N); // 组装切线基。
	#endif

	#ifdef OMNI_DIRECTIONAL_BLOCKLIGHT // 指向性方块光要用方块光的屏幕梯度。
		vec2 blockLightDir = vec2(dFdx(blockLight.x), dFdy(blockLight.x)); // 方块光的屏幕变化方向。
	#endif


// 各向异性过滤与视差：先准备阳光方向，再按开关走视差或过滤。
	#ifdef OMNI_END // 末地用末地版阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverseEnd[2].xyz; // 阳光方向转到视空间。
	#else // 主世界与下界用加载器给的阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverse[2].xyz; // 阳光方向转到视空间。
	#endif

	float parallaxShadow = saturate(dot(tbn[2], shadowVector) * 200.0); // 面朝阳光程度，作为视差自阴影初值。


	vec4 albedoTex = vec4(0.0); // 采样得到的底色。
	vec4 specularTex = vec4(0.0); // 采样得到的高光。
	vec3 normalTex = vec3(0.0, 0.0, 1.0); // 采样得到的法线。
	float materialAO = 1.0; // 采样得到的材质遮蔽，未开该功能时为一。
	SampleTerrainSurface(tbn, texCoord, duv1, duv2, shadowVector, parallaxShadow, albedoTex, specularTex, normalTex, materialAO); // 按开关统一采样表面贴图。

// 区块淡入：按进度抖动丢弃像素，新加载的区块逐渐显现；选项关闭时从不丢弃。
	#if OMNI_CHUNK_FADE > 0 // 只有开启才准备抖动并判断。
		#ifdef OMNI_TAA // 开时间抗锯齿用蓝噪声，抖动模式会随时间被平均掉。
			float chunkFadeDither = BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
		#else // 否则用交错梯度噪声，不额外采样噪声贴图。
			float chunkFadeDither = InterleavedGradientNoise(gl_FragCoord.xy); // 每像素固定图案。
		#endif
		if (omniChunkFadeDiscard(chunkFade, chunkFadeDither)) discard; // 进度越小丢弃的像素越多。
	#endif


// 方块光：默认取原版方块光，指向性开启时再按表面朝向倾斜。
	float blockLightDirectional = blockLight.x; // 默认直接用原版方块光横轴。

	#ifdef OMNI_DIRECTIONAL_BLOCKLIGHT // 指向性方块光：按法线把方块光偏向一侧。
		float blockLightFwidth = abs(blockLightDir.x) + abs(blockLightDir.y); // 梯度大小，用来挡住跳变处。
		blockLightDir = normalize(vec2(tbn * vec3(blockLightDir, 1e-10))); // 梯度转到切线空间。

		float lightNormalWeight = dot(blockLightDir, normalTex.xy) * (1.0 - blockLight.x * 0.95) * OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH + 1.0; // 表面朝向让光偏向。

		if (blockLightFwidth > 1e-5 && blockLight.x < 1.0) blockLightDirectional = clamp(blockLightDirectional * lightNormalWeight, 0.0, 0.9999); // 只在方块光未满且梯度稳定时改写。
	#endif


// 底色：贴图色乘顶点色。
	vec3 albedo = albedoTex.rgb * color; // 合成底色。
	albedo *= materialAO; // 资源包法线蓝通道的材质遮蔽压到底色，未开时为一、不改变画面。

	albedo = omniSeason(albedo, color); // Omni 额外功能：按游戏天数给植被上季节色，默认关闭。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo = color.bbb; // 调试白光时只留顶点色的蓝通道。
	#endif


// 湿润：按降雨、孔隙率与朝向算湿的程度，并叠加雨点法线。
	#ifdef OMNI_ENABLE_PBR

		vec3 mcPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition; // 还原世界位置。
		float NdotU = dot(tbn[2], gbufferModelView[1].xyz); // 表面法线与世上方向的夹角，越朝上越易积水。

		#if defined OMNI_TEXTURE_PBR_POROSITY && OMNI_TEXTURE_PBR_FORMAT < 2 // 资源包自带孔隙率时按标准位宽解码。
			float porosity = saturate(specularTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specularTex.b)); // 高位为孔隙率。
		#else
			float porosity = OMNI_TEXTURE_DEFAULT_POROSITY; // 否则用默认孔隙率。
		#endif

		#ifdef OMNI_OVERWORLD // 主世界的地表湿润看降雨。
			#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系是否真的降水。
				float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加地表基础湿润。
			#else
				float wet = wetness + OMNI_SURFACE_WETNESS; // 强制局部降水时只看整体降雨。
			#endif

			wet *= saturate(abs(materialIDs - MATID_LAVA - 0.5) - 0.5); // 岩浆与火不沾水。
			wet *= step(0.9, blockLight.y); // 只有露天（天光接近满值）才积雨。

			vec2 rainNormal = vec2(0.0); // 雨点法线横纵分量。
			if (wet > 1e-7){ // 只有确实湿了才加雨点。
				wet *= GetModulatedRainSpecular(mcPos); // 按位置调制湿润高光。
				
				float lightMask = saturate(blockLight.y * 10.0 - 9.0); // 只有露天才有雨点。

				#ifdef OMNI_RAIN_SPLASH_EFFECT // 开启雨点溅射时产生雨点法线。
					float splashStrength = saturate(NdotU * 2.0 - 1.0) * lightMask * (2.0 - porosity); // 越朝上、露天、越不吸水，溅射越强。
					if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet); // 得到雨点法线。
				#endif

				wet *= lightMask; // 非露天处压掉湿润。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝下的面湿润更弱。
			}
		#else // 下界与末地没有降雨，只用地表基础湿润。
			float wet = OMNI_SURFACE_WETNESS; // 取基础湿润。

			wet *= saturate(abs(materialIDs - MATID_LAVA - 0.5) - 0.5); // 岩浆与火不沾水。
			wet *= GetModulatedRainSpecular(mcPos); // 仍按位置调制。
			wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
		#endif

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif


// 法线：湿润把法线往朝外方向拉平，雨点再叠一点扰动。
	#if defined MC_NORMAL_MAP && defined OMNI_ENABLE_PBR
		normalTex = mix(normalize(normalTex), vec3(0.0, 0.0, 1.0), saturate(wet * (1.6 - porosity * 0.6))); // 越湿越接近平整水面。
	#endif


	vec3 viewNormal = tbn * normalize(normalTex); // 切线空间法线转到视空间。

	#if defined OMNI_ENABLE_PBR && defined OMNI_OVERWORLD && defined OMNI_RAIN_SPLASH_EFFECT 
		viewNormal = normalize(viewNormal + mat3(gbufferModelView) * vec3(rainNormal.x, 0.0, rainNormal.y)); // 叠上雨点法线。
	#endif

	#ifdef OMNI_TERRAIN_NORMAL_CLAMP
		vec3 viewDir = -normalize(viewPos); // 视线方向。
		viewNormal = normalize(viewNormal + tbn[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住掠射角处的极端法线。
	#endif

	vec2 normalEnc = EncodeNormal(viewNormal); // 八面体编码法线。


// 积雪覆盖：把雪按露天程度与朝向叠到底色，默认关闭时不执行。
	#ifdef OMNI_SNOW_OVERLAY
		// 世界位置：视空间位置回到相机相对世界坐标，再加上相机绝对位置。
		vec3 snowWorldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition;
		// 带贴图扰动的世界法线：视空间法线转到世界。
		vec3 snowWorldNormal = mat3(gbufferModelViewInverse) * viewNormal;
		// 几何面世界法线：切线基第三列转到世界，用来判断面的朝向。
		vec3 snowWorldFlatNormal = mat3(gbufferModelViewInverse) * tbn[2];
		albedo = omniSnowOverlay(albedo, snowWorldPos, snowWorldNormal, snowWorldFlatNormal, blockLight.y);
	#endif


// 高光：按资源包编码取出，并给红石线一个最小发光。
	#if defined MC_SPECULAR_MAP && OMNI_TEXTURE_PBR_FORMAT == 2
		specularTex.a = specularTex.b; // `PTGI` 编码把自发光放在蓝通道，转到透明度通道。
	#endif

	#if defined OMNI_ENABLE_PBR && OMNI_TEXTURE_PBR_FORMAT != 1
		if (materialIDs == MATID_REDSTONE && color.b == 0.0){ // 红石线的基础色蓝通道为零，可用来识别。
			float power = color.r; // 用红通道当强度。
			power = saturate(power * 1.1 - 0.1) * step(0.3, power); // 压掉弱信号。
			specularTex.a = max(specularTex.a, power * power * 0.3); // 给它一个最小自发光。
		}
	#endif


	WriteTerrainGbuffer(albedo, normalEnc, blockLightDirectional, blockLight, specularTex, materialIDs, wet, parallaxShadow); // 统一写出零、三、五号画面。

	#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
		// 九号画面：红通道记方块编号，绿通道记生物群系，供下一帧几何阶段的草丛查询。
		// 为什么记成字节：编号和生物群系都是小整数，八位够用，跨帧查询不需要更高精度。
		gbufferOutput9 = vec4(blockID / 255.0, float(biome & 255) / 255.0, 0.0, 1.0); // 归一化到零到一存进八位画面。
	#endif
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
