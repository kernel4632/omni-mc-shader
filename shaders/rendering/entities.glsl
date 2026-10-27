/*
实体绘制主体：把 iterationT 的实体、方块实体、手持物、蜘蛛眼四类程序合成一个主体文件。
来源：`Lib/Programs/Gbuffers/Entities_VS.glsl`、`Entities_FS.glsl` 一比一移植；原程序用
  `PROGRAM_ENTITIES`、`PROGRAM_BLOCK`、`PROGRAM_HAND`、`PROGRAM_SPIDEREYES` 区分四类，这里换成
  `OMNI_ENTITIES_PASS`、`OMNI_BLOCK_PASS`、`OMNI_HAND_PASS`、`OMNI_SPIDEREYES_PASS`。
调用位置：各维度 `gbuffers_entities`、`gbuffers_block`、`gbuffers_hand`、`gbuffers_spidereyes` 入口
  定义阶段宏与对应程序宏后引入本文件；入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_HAND_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/entities.glsl"`。
输出约定：四类程序都写零号、三号、五号，对应 `DRAWBUFFERS:035`。
设计原因与取舍：
  四类程序共用同一套顶点与片元流程，只用程序宏挑分支，与原程序一致；手持物的视场角改写投影，
  方块实体在末地传送门上叠十六层贴图，蜘蛛眼只发光不写深度。
  `DIMENSION_MAIN` 在 iterationT 里不只是“主世界”：蜘蛛眼程序在下界与末地也走主世界分支，
  所以这里用 `OMNI_OVERWORLD` 或蜘蛛眼程序还原同一条件，见下方 `OMNI_MAIN_DIMENSION`。
  顶点阶段不引入 `effects/water/water.glsl`，它含只有片元能用的导数函数。
*/
#ifndef OMNI_ENTITIES_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_ENTITIES_BODY_INCLUDED // 置上标记。

// 还原 iterationT 的 `DIMENSION_MAIN`：主世界程序与蜘蛛眼程序都为真。
#if defined OMNI_OVERWORLD || defined OMNI_SPIDEREYES_PASS
	#define OMNI_MAIN_DIMENSION // 主世界分支开关。
#endif

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：曲线、法线编解码、打包等。
#include "/common/math.glsl"
// --- 本程序自带的加载器输入：效果文件会读这些名字，必须先于效果文件声明 ---
uniform sampler2D tex; // 实体贴图。
uniform sampler2D specular; // 高光贴图。
uniform sampler2D normals; // 法线贴图。
uniform sampler2D gaux1; // 雨点第一张动画贴图。
uniform sampler2D gaux2; // 雨点第二张动画贴图。
uniform sampler2D gaux3; // 雨点第三张动画贴图。
uniform sampler2D gaux4; // 方块图集，实体用到方块贴图时做回绕判断。
// 天气文件里的雨色与风偏移读取阳光、天光与露天标记，按调用前提给空全局；本程序不调用它们。
vec3 colorShadowlight; // 阳光颜色。
vec3 colorSkylight; // 天光颜色。
// 视差函数照 iterationT 原样读取调用方声明的 `viewPos`，而且会被 `antialiasing` 间接引入（它要用 `MATID_*`），
// 所以片元必须在引入任何效果文件之前先声明这个插值量。
#ifdef OMNI_FRAGMENT
	in vec3 viewPos; // 实体表面的视空间位置，视差与切线基都要用它。
#endif
// 时间抗锯齿选项：坐标换算要用它决定是否撤销抖动，必须先于坐标换算引入。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MATID_*`、`ParallaxOcclusionMapping` 与实体材质选项。
#include "/effects/ground/material.glsl"
// 视差算法只服务几何片元阶段，由真正调用的阶段显式引入。
#include "/effects/ground/parallax.glsl"
// 自发光纹饰：提供纹饰自发光选项与 `omniTrimEmission`，实体片元按盔甲纹饰编号补一份自发光。
#include "/effects/lighting/emissive.glsl"
// 生物与玩家：提供 `EntityStatusColor` 与 `HandFovProjection`。
#include "/effects/entity/entity.glsl"
// Omni 额外功能：积雪覆盖（来源 Eclipse），默认关闭；与地形共用同一份雪覆盖算法。
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

#ifdef OMNI_VERTEX // 顶点阶段：四类实体程序的共用顶点着色器。
#ifdef OMNI_ENTITIES_PASS
	#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
		// 要区分玩家与其它实体，读取实体编号。
		uniform int entityId;
	#endif
#endif

// 传给片元的插值量。
out vec4 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec3 viewPos; // 视空间位置。
out vec2 blockLight; // 方块光与天光。

// 开关实体顶点切线时多传一组切线基。
#if (OMNI_ENTITIES_VS_TBN && (defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS) && (MC_VERSION < 11500 || MC_VERSION > 11604)) || (defined OMNI_HAND_PASS && MC_VERSION < 11300)
	// 顶点切线属性，由模组或资源包提供。
	attribute vec4 at_tangent;
	out mat3 tbn; // 顶点切线基。
#endif

#ifdef OMNI_BLOCK_PASS
	out vec4 portalCoord; // 传送门投影坐标，只方块实体用。
#endif


// 顶点主函数：按程序宏选手持物视场角，再算摆动与切线基。
void main(){
	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec3 planetViewPos = v_viewPos.xyz; // 复制视空间位置给行星曲率改写。
	omniPlanetCurvatureView(planetViewPos); // 行星曲率：远处实体顶点沿纵向下沉，模拟星球弯曲；关闭时为原样。
	v_viewPos.xyz = planetViewPos; // 写回改写后的视空间位置。
	viewPos = v_viewPos.xyz; // 传给片元。
	#ifdef OMNI_HAND_PASS // 手持物按模式改写视场角与深度，算法只保留在效果文件里一份。
		gl_Position = HandFovProjection(gbufferProjection, aspectRatio) * v_viewPos; // 调用效果文件统一实现的投影改写。
	#else // 非手持物直接用加载器投影。
		gl_Position = gl_ProjectionMatrix * v_viewPos; // 常规投影。
	#endif

	#ifdef OMNI_TAA // 时间抗锯齿：按程序决定是否给顶点加抖动。
		#if defined OMNI_HAND_PASS // 手持物单独看开关。
			#if !OMNI_DISABLE_HAND_TAA // 未关闭手部抗锯齿时加抖动。
				gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加本帧抖动。
			#endif
		#elif defined OMNI_ENTITIES_PASS // 普通实体单独看玩家开关。
			#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 关闭玩家抗锯齿时玩家不加抖动。
				bool jitterVertex = entityId != 7003; // 七千零三是玩家自身，跳过它。
			#else
				bool jitterVertex = true; // 未关闭时所有实体都加抖动。
			#endif
			if (jitterVertex){ // 先用宏决定是否加抖动，再走一条完整的 `if`，避免判断被预处理指令切开。
				gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加本帧抖动。
			}
		#else // 方块与蜘蛛眼总是加抖动。
			gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加本帧抖动。
		#endif
	#endif

	color = gl_Color; // 顶点色。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

	#if !defined OMNI_BLOCK_PASS // 方块实体以外的实体把方块光压一档。
		blockLight.x = min(blockLight.x, 0.85); // 避免实体自身过亮。
	#endif

	#if (OMNI_ENTITIES_VS_TBN && (defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS) && (MC_VERSION < 11500 || MC_VERSION > 11604)) || (defined OMNI_HAND_PASS && MC_VERSION < 11300)
		vec3 N = normalize(gl_NormalMatrix * gl_Normal); // 法线转到视空间。
		vec3 T = normalize(gl_NormalMatrix * at_tangent.xyz); // 切线转到视空间。
		vec3 B = cross(T, N) * sign(at_tangent.w); // 副切线由叉乘与手性得到。
		tbn = mat3(T, B, N); // 组装切线基。
	#endif
	

	#ifdef OMNI_BLOCK_PASS // 方块实体记下传送门投影坐标。
		portalCoord = gl_Position * 0.5; // 先缩放。
		portalCoord.xy = vec2(portalCoord.x + portalCoord.w, portalCoord.y + portalCoord.w); // 平移到零到一。
		portalCoord.zw = gl_Position.zw; // 保留深度与齐次分量。
	#endif
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && (defined OMNI_ENTITIES_PASS || defined OMNI_BLOCK_PASS || defined OMNI_HAND_PASS || defined OMNI_SPIDEREYES_PASS) // 片元阶段：四类实体的共用片元着色器。
#ifdef OMNI_ENTITIES_PASS
	uniform vec4 entityColor; // 实体受伤颜色与强度。
	uniform int entityId; // 实体编号。
	uniform int currentRenderedItemId; // 当前渲染物品编号，盔甲纹饰在这里给成 item.properties 的纹饰编号。
#endif

#ifdef OMNI_BLOCK_PASS
	uniform int blockEntityId; // 方块实体编号。
#endif

/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

// 从顶点阶段接收的插值量。
in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
// `in vec3 viewPos;` 已在文件顶部、引入视差函数之前声明。
in vec2 blockLight; // 方块光。

#if (OMNI_ENTITIES_VS_TBN && (defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS) && (MC_VERSION < 11500 || MC_VERSION > 11604)) || (defined OMNI_HAND_PASS && MC_VERSION < 11300)
	in mat3 tbn; // 顶点切线基。
#endif

#ifdef OMNI_BLOCK_PASS // 方块实体的传送门数据与颜色表。
	in vec4 portalCoord; // 传送门投影坐标。

	const vec3[] COLORS = vec3[]( // 十六层传送门贴图的颜色权重，照原程序。
	vec3(0.022087, 0.098399, 0.110818),
	vec3(0.011892, 0.095924, 0.089485),
	vec3(0.027636, 0.101689, 0.100326),
	vec3(0.046564, 0.109883, 0.114838),
	vec3(0.064901, 0.117696, 0.097189),
	vec3(0.063761, 0.086895, 0.123646),
	vec3(0.084817, 0.111994, 0.166380),
	vec3(0.097489, 0.154120, 0.091064),
	vec3(0.106152, 0.131144, 0.195191),
	vec3(0.097721, 0.110188, 0.187229),
	vec3(0.133516, 0.138278, 0.148582),
	vec3(0.070006, 0.243332, 0.235792),
	vec3(0.196766, 0.142899, 0.214696),
	vec3(0.047281, 0.315338, 0.321970),
	vec3(0.204675, 0.390010, 0.302066),
	vec3(0.080955, 0.314821, 0.661491));

	const mat4 SCALE_TRANSLATE = mat4(0.5, 0.0, 0.0, 0.25, // 传送门贴图的缩放平移矩阵。
									  0.0, 0.5, 0.0, 0.25,
									  0.0, 0.0, 1.0, 0.0,
									  0.0, 0.0, 0.0, 1.0);

	// 绕竖轴旋转的二维矩阵。
	mat2 mat2_rotate_z(float radian){
		return mat2(cos(radian), -sin(radian), sin(radian), cos(radian)); // 标准旋转矩阵。
	}

	// 生成第若干层传送门贴图的变换矩阵。
	mat4 end_portal_layer(float layer){
		mat4 translate = mat4(1.0, 0.0, 0.0, 17.0 / layer, // 逐层偏移。
							  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (frameTimeCounter * 0.0005), // 纵向随时间缓慢流动。
							  0.0, 0.0, 1.0, 0.0,
							  0.0, 0.0, 0.0, 1.0);

		mat2 rotate = mat2_rotate_z(radians((layer * layer * 4321.0 + layer * 9.0) * 2.0)); // 每层不同角度。

		mat2 scale = mat2((4.5 - layer / 4.0) * 2.0); // 每层不同缩放。

		return mat4(scale * rotate) * translate * SCALE_TRANSLATE; // 合成完整变换。
	}
#endif


// 材质编号解码：四类程序各有一套判定，集中成一个能一句话说清的动作。
vec2 DecodeEntityMaterial(){
	#if defined OMNI_ENTITIES_PASS
		float materialIDs = MATID_LAND; // 默认普通表面。
		float noDiscard = 0.0; // 允许不丢弃的标记，闪电与部分实体用。

		switch(entityId){ // 按实体编号分类。
			case 7003: // 玩家自身。
				materialIDs = MATID_ENTITIES_PLAYER; // 记为玩家。
				break; // 结束该分支。

			case 14: case 15: case 22: case 26: // 高亮度自发光实体。
				materialIDs = MATID_ENTITIES_LIT_HIGH; // 记为高亮。
				break; // 结束该分支。

			case 200: case 7001: // 中等亮度自发光实体。
				materialIDs = MATID_ENTITIES_LIT_MEDIUM; // 记为中亮。
				break; // 结束该分支。

			case 2: case 17: case 24: // 低亮度自发光实体。
				materialIDs = MATID_ENTITIES_LIT_LOW; // 记为低亮。
				break; // 结束该分支。

			case 7000: // 闪电。
				materialIDs = MATID_LIGHTNING; // 记为闪电。
				noDiscard = 1.0; // 闪电不丢弃透明像素。
				break; // 结束该分支。

			#ifdef IS_IRIS // Iris 下的发光实体单独编号。
				case 7002: // 发光实体。
					materialIDs = 256.0; // 用一个超出范围的编号，后面据此丢弃整个像素。
					break; // 结束该分支。
			#endif

			case 829925: // 实体身上的雪层。
				materialIDs = MATID_ENTITIES_SNOW; // 记为雪。
				break; // 结束该分支。

			case 41: // 另一类受光实体。
				noDiscard = 1.0; // 不丢弃透明像素。
		}
	#elif defined OMNI_SPIDEREYES_PASS
		float materialIDs = MATID_ENTITIES_LIT_LOW; // 蜘蛛眼按低亮自发光处理。
		float noDiscard = 0.0; // 不保留透明像素。
	#elif defined OMNI_BLOCK_PASS
		float materialIDs = blockEntityId == 119 ? MATID_END_PORTAL : MATID_LAND; // 传送门方块实体用传送门材质。
		float noDiscard = 0.0; // 不保留透明像素。
	#elif defined OMNI_HAND_PASS
		float materialIDs = MATID_HAND; // 手持物统一材质。
		float noDiscard = 0.0; // 不保留透明像素。
	#endif
	return vec2(materialIDs, noDiscard); // 材质编号与不丢弃标记一起交回。
}

// 切线基：顶点给了就用顶点的，否则用屏幕导数推出来。
mat3 BuildEntityTangentBasis(vec2 duv1, vec2 duv2){
	#if (!OMNI_ENTITIES_VS_TBN || (!defined OMNI_ENTITIES_PASS && !defined OMNI_SPIDEREYES_PASS) || (MC_VERSION >= 11500 && MC_VERSION <= 11604)) && (!defined OMNI_HAND_PASS || MC_VERSION >= 11300)
		return gfx_tangent_basis(dFdx(viewPos), dFdy(viewPos), duv1, duv2); // 由屏幕导数构造切线基。
	#else
		mat3 tbnMat = tbn; // 用顶点传来的切线基。
		if(!gl_FrontFacing) tbnMat[2] = -tbnMat[2]; // 背面翻转法线。
		return tbnMat;
	#endif
}

// 表面采样：按开关走视差或普通采样，得到底色、高光与法线，并可能丢弃透明像素。
// `materialAO` 是资源包法线蓝通道给出的材质遮蔽，未开该功能时恒为一，调用方把它乘到底色。
void SampleEntitySurface(vec2 texCoord, vec2 duv1, vec2 duv2, mat3 tbnMat, vec3 shadowVector, float materialIDs, float noDiscard, out vec4 albedoTex, out vec4 specularTex, out vec3 normalTex, inout float parallaxShadow, out float materialAO){
	materialAO = 1.0; // 默认不压暗：视差路径与没有法线的情形都保持一。
	#if OMNI_ENTITIES_PARALLAX && OMNI_PARALLAX_MODE > 0 && defined MC_NORMAL_MAP // 实体视差开启且有法线贴图。

		vec3 normalOut = vec3(0.0, 0.0, 1.0); // 视差函数会写回法线。
		ivec2 parallaxTexel = ParallaxOcclusionMapping(texCoord, tbnMat, shadowVector, duv1, duv2, normalOut, parallaxShadow); // 找到可见交点。

		albedoTex = texelFetch(tex, parallaxTexel, 0); // 精确取交点底色。

		#if defined OMNI_ENTITIES_PASS // 普通实体：按透明度丢弃。
			#ifdef IS_IRIS
				if (albedoTex.a + noDiscard <= 0.004 || materialIDs > 255.0) discard; // Iris 下发光实体整体丢弃。
			#else
				if (albedoTex.a + noDiscard <= 0.004) discard; // 其它情况按透明度丢弃。
			#endif
		#elif defined OMNI_SPIDEREYES_PASS // 蜘蛛眼用更高的阈值。
			if (albedoTex.a < 0.1) discard; // 低于零点一才丢弃，保留大部分蜘蛛眼。
		#else // 方块与手持物按更小阈值丢弃。
			if (albedoTex.a < 0.004) discard; // 几乎全透明才丢弃，保留细小边缘。
		#endif

		#ifdef MC_SPECULAR_MAP
			specularTex = texelFetch(specular, parallaxTexel, 0); // 精确取交点高光。
		#else
			specularTex = vec4(0.0); // 没有高光贴图时全零。
		#endif

		normalTex = normalOut; // 交回视差写回的法线。
		// 与地形视差路径一致：视差函数只解出交点法线，这里补上法线倍率与材质遮蔽，两个选项在实体视差下同样生效。
		normalTex = omniMaterialNormalScale(normalTex); // 按选项缩放起伏。
		materialAO = omniMaterialAO(texelFetch(normals, parallaxTexel, 0).rgb); // 取交点处的材质遮蔽，未开时为一。

	#else // 未开视差时按屏幕导数采贴图。

		albedoTex = textureGrad(tex, texCoord, duv1, duv2); // 按屏幕导数采底色。

		#if defined OMNI_ENTITIES_PASS // 普通实体：按透明度丢弃。
			#ifdef IS_IRIS
				if (albedoTex.a + noDiscard <= 0.004 || materialIDs > 255.0) discard; // Iris 下发光实体整体丢弃。
			#else
				if (albedoTex.a + noDiscard <= 0.004) discard; // 其它情况按透明度丢弃。
			#endif
		#elif defined OMNI_SPIDEREYES_PASS // 蜘蛛眼用更高的阈值。
			if(albedoTex.a < 0.1) discard; // 低于零点一才丢弃，保留大部分蜘蛛眼。
		#else // 方块与手持物按更小阈值丢弃。
			if (albedoTex.a < 0.004) discard; // 几乎全透明才丢弃，保留细小边缘。
		#endif

		#ifdef MC_NORMAL_MAP
			vec4 materialNormal = omniMaterialNormal(textureGrad(normals, texCoord, duv1, duv2).rgb); // 采法线，按选项缩放起伏并解出材质遮蔽。
			normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
			materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
		#else
			normalTex = vec3(0.0, 0.0, 1.0); // 没有法线贴图时朝外。
		#endif

		#ifdef MC_SPECULAR_MAP
			#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
				specularTex = textureGrad(specular, texCoord, duv1, duv2); // 仅硬编码模式按屏幕导数采高光。
			#else
				specularTex = textureLod(specular, texCoord, 0.0); // 其余模式只取一次。
			#endif
		#else
			specularTex = vec4(0.0); // 没有高光贴图时全零。
		#endif
			
	#endif
}

// 输出写入：按程序类别把底色、法线光照与高光材质写进零、三、五号画面。
void WriteEntityGbuffer(vec4 albedo, vec3 viewNormal, vec2 blockLight, vec4 specularTex, float materialIDs, float wet, float parallaxShadow){
	#if defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS
		gbufferOutput0 = albedo; // 实体保留透明度，混合到场景。
	#else
		gbufferOutput0 = vec4(albedo.rgb, 1.0); // 方块与手持物写不透明底色。
	#endif
	gbufferOutput3 = vec4(EncodeNormal(viewNormal), blockLight); // 三号写法线与方块光。
	gbufferOutput5 = vec4(Pack2x8(specularTex.rg), Pack2x8(specularTex.ba), (materialIDs + 0.1) / 255.0, Pack2x8(vec2(wet, parallaxShadow))); // 五号打包高光、材质编号、湿润与视差阴影。
}

// 片元主函数：先按程序定材质编号，再算切线基、视差、湿润、法线与高光。
void main(){
// 材质编号：四类程序各有一套判定。
	vec2 entityMaterial = DecodeEntityMaterial(); // 解码材质编号与不丢弃标记。
	float materialIDs = entityMaterial.x; // 材质编号，写进五号画面。
	float noDiscard = entityMaterial.y; // 不丢弃透明像素的标记。

// 切线基：顶点没给时用屏幕导数推出来。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。
	mat3 tbnMat = BuildEntityTangentBasis(duv1, duv2); // 用效果文件统一实现的切线基。


// 视差：算出阳光方向与自阴影初值，按开关走视差或普通采样。
	#ifdef OMNI_END // 末地用末地版阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverseEnd[2].xyz; // 阳光方向转到视空间。
	#else // 主世界与下界用加载器给的阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverse[2].xyz; // 阳光方向转到视空间。
	#endif

	float parallaxShadow = saturate(dot(tbnMat[2], shadowVector) * 200.0); // 面朝阳光程度，作为视差自阴影初值。

	vec4 albedoTex = vec4(0.0); // 采样得到的底色。
	vec4 specularTex = vec4(0.0); // 采样得到的高光。
	vec3 normalTex = vec3(0.0, 0.0, 1.0); // 采样得到的法线。
	float materialAO = 1.0; // 采样得到的材质遮蔽，未开该功能时为一。
	SampleEntitySurface(texCoord, duv1, duv2, tbnMat, shadowVector, materialIDs, noDiscard, albedoTex, specularTex, normalTex, parallaxShadow, materialAO); // 按开关统一采样表面贴图。


// 底色：贴图色乘顶点色，并叠受伤颜色。
	vec4 albedo = vec4(albedoTex.rgb * color.rgb, albedoTex.a); // 合成底色与透明度。
	albedo.rgb *= materialAO; // 资源包法线蓝通道的材质遮蔽压到底色，未开时为一、不改变画面。
	#ifdef OMNI_ENTITIES_PASS
		albedo.rgb = EntityStatusColor(albedo.rgb, entityColor); // 叠上实体状态色。
	#endif

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif


// 湿润：与地形同源，手持物直接按发光等级给湿润。
	#ifdef OMNI_ENABLE_PBR

		float NdotU = dot(tbnMat[2], gbufferModelView[1].xyz); // 表面法线与世上方向的夹角。

		#if OMNI_TEXTURE_PBR_POROSITY && OMNI_TEXTURE_PBR_FORMAT < 2
			float porosity = saturate(specularTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specularTex.b)); // 资源包孔隙率。
		#else
			float porosity = OMNI_TEXTURE_DEFAULT_POROSITY; // 默认孔隙率。
		#endif

		#ifdef OMNI_HAND_PASS // 手持物离相机近，湿润只按半强与朝向算。

			#ifdef OMNI_MAIN_DIMENSION // 主世界分支。
				#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
					float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加基础湿润。
				#else
					float wet = wetness + OMNI_SURFACE_WETNESS; // 只看整体降雨。
				#endif
				wet *= 0.5; // 手持物湿润压半。
				wet *= saturate(blockLight.y * 10.0 - 9.0); // 只有露天才有雨。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
			#else // 下界与末地分支。
				float wet = OMNI_SURFACE_WETNESS; // 只用基础湿润。
				wet *= 0.5; // 压半。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
			#endif
			
		#else // 非手持物。

			vec3 mcPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition; // 还原世界位置。

			#ifdef OMNI_MAIN_DIMENSION // 主世界分支。

				#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION
					float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加基础湿润。
				#else
					float wet = wetness + OMNI_SURFACE_WETNESS; // 只看整体降雨。
				#endif

				wet *= step(0.9, blockLight.y); // 只有露天才积雨。

				vec2 rainNormal = vec2(0.0); // 雨点法线横纵分量。
				if (wet > 1e-7){ // 确实湿了才加雨点。
					wet *= GetModulatedRainSpecular(mcPos); // 按位置调制湿润高光。

					float lightMask = saturate(blockLight.y * 10.0 - 9.0); // 只有露天才有雨点。

					#if defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS // 实体里只有雪层吃雨点，其它实体湿润压半。
						if (materialIDs == MATID_ENTITIES_SNOW){
							#ifdef OMNI_RAIN_SPLASH_EFFECT
								float splashStrength = saturate(NdotU * 2.0 - 1.0) * lightMask * (2.0 - porosity); // 溅射强度。
								if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet); // 得到雨点法线。
							#endif
						}else{
							wet *= 0.5; // 非雪实体湿润压半。
						}
					#else // 方块与手持水按常规算雨点。
						#ifdef OMNI_RAIN_SPLASH_EFFECT
							float splashStrength = saturate(NdotU * 2.0 - 1.0) * lightMask * (2.0 - porosity); // 溅射强度。
							if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet); // 得到雨点法线。
						#endif		
					#endif

					wet *= lightMask; // 非露天处压掉湿润。
					wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
				}
			#else // 下界与末地分支。
				float wet = OMNI_SURFACE_WETNESS; // 只用基础湿润。

				wet *= GetModulatedRainSpecular(mcPos); // 仍按位置调制。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
			#endif
			
		#endif

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif


// 法线：湿润把法线往朝外方向拉平，雨点再叠一点扰动。
	#if defined MC_NORMAL_MAP && defined OMNI_ENABLE_PBR
		normalTex = mix(normalize(normalTex), vec3(0.0, 0.0, 1.0), saturate(wet * (1.6 - porosity * 0.6))); // 越湿越接近平整水面。
	#endif

// 积雪覆盖：只给普通实体与方块实体叠雪，手持物与蜘蛛眼不叠；默认关闭时不执行。
// 为什么放在算视空间法线之前：雪会改切线空间法线，先叠雪再算视空间法线，光照才能用上雪面的起伏。
	#if (defined OMNI_ENTITIES_PASS || defined OMNI_BLOCK_PASS) && defined OMNI_SNOW_OVERLAY
		// 世界位置：视空间位置回到相机相对世界坐标，再加上相机绝对位置。
		vec3 snowWorldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition;
		// 叠雪前的世界法线：当前切线空间法线经切线基转视空间、再转世界，用来判断面的朝上程度。
		vec3 snowWorldNormal = mat3(gbufferModelViewInverse) * (tbnMat * normalize(normalTex));
		// 几何面世界法线：切线基第三列转到世界，用来判断面的朝向。
		vec3 snowWorldFlatNormal = mat3(gbufferModelViewInverse) * tbnMat[2];
		omniSnowOverlay(albedo.rgb, normalTex, specularTex.r, snowWorldPos, snowWorldNormal, snowWorldFlatNormal, blockLight.y); // 改底色、切线法线与平滑度。
	#endif


	vec3 viewNormal = tbnMat * normalize(normalTex); // 切线空间法线转到视空间。

	#if !defined OMNI_HAND_PASS && defined OMNI_ENABLE_PBR && defined OMNI_MAIN_DIMENSION && defined OMNI_RAIN_SPLASH_EFFECT
		viewNormal = normalize(viewNormal + mat3(gbufferModelView) * vec3(rainNormal.x, 0.0, rainNormal.y)); // 叠上雨点法线。
	#endif

	#if defined OMNI_ENTITIES_PASS || defined OMNI_SPIDEREYES_PASS
		#ifdef OMNI_ENTITIES_NORMAL_CLAMP
			vec3 viewDir = -normalize(viewPos.xyz); // 视线方向。
			viewNormal = normalize(viewNormal + tbnMat[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住掠射角处的极端法线。
		#endif
	#elif defined OMNI_BLOCK_PASS
		#ifdef OMNI_TERRAIN_NORMAL_CLAMP
			vec3 viewDir = -normalize(viewPos); // 视线方向。
			viewNormal = normalize(viewNormal + tbnMat[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住极端法线。
		#endif
	#elif defined OMNI_HAND_PASS
		#ifdef OMNI_HAND_NORMAL_CLAMP
			vec3 viewDir = -normalize(viewPos); // 视线方向。
			viewNormal = normalize(viewNormal + tbnMat[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住极端法线。
		#endif
	#endif


// 高光：按资源包编码取出，并按程序屏蔽不需要的高光。
	#if defined MC_SPECULAR_MAP && OMNI_TEXTURE_PBR_FORMAT == 2
		specularTex.a = specularTex.b; // `PTGI` 编码把自发光放在蓝通道，转到透明度通道。
	#endif

	#ifdef OMNI_HAND_PASS
		#ifdef OMNI_DISABLE_HAND_SPECULAR
			specularTex = vec4(0.0); // 关闭手持物高光时清零。
		#endif
	#endif

	#ifdef OMNI_ENTITIES_PASS
		#ifdef OMNI_DISABLE_PLAYER_SPECULAR
			if(materialIDs == MATID_ENTITIES_PLAYER) specularTex = vec4(0.0); // 关闭玩家高光时只清玩家。
		#endif
	#endif	


// 写死的贴图与颜色：雪层固定白，传送门叠十六层。
	#ifdef OMNI_ENTITIES_PASS
		if (materialIDs == MATID_ENTITIES_SNOW){ // 雪层实体。
			albedo.rgb = vec3(0.9690, 0.9965, 0.9965); // 固定雪白。
			viewNormal = tbnMat[2]; // 法线直接用面法线。
			specularTex = vec4(0.0, 0.0, 0.7, 0.0); // 固定一点高光。
		}
	#endif

	#ifdef OMNI_BLOCK_PASS
		if (materialIDs == MATID_END_PORTAL){ // 末地传送门方块实体。
			vec3 portalColor = textureProj(tex, portalCoord).rgb * COLORS[0]; // 第一层。
			for (int i = 0; i < 16; i++){
				portalColor += textureProj(tex, portalCoord * end_portal_layer(float(i + 1))).rgb * COLORS[i]; // 叠上其余各层。
			}
			albedo.rgb = portalColor; // 用叠加结果当底色。
			specularTex.rgb = vec3(1.0, 0.0, 254.0 / 255.0); // 固定高光与一个小自发光。
		}
	#endif

	// 自发光纹饰：亮纹饰与暗纹饰按明度发光，写进五号画面的自发光通道（来源 Eclipse `all_solid.fsh:866-870`）。
	// 为什么亮纹饰要减半：亮纹饰本身就很亮，不减半会过曝，照 Eclipse 的 0.4 系数。
	// 为什么要求开启物理光照：关闭 PBR 时合成阶段不读取这份自发光，写了也不生效。
	#if defined OMNI_ENTITIES_PASS && OMNI_EMISSIVE_TRIMS && defined OMNI_ENABLE_PBR
		if (currentRenderedItemId == 1026 || currentRenderedItemId == 1027){ // 两个编号见 item.properties。
			float trimGlow = OMNI_EMISSIVE_TRIMS_STRENGTH * omniTrimEmission(albedo.rgb); // 按明度算发光。
			if (currentRenderedItemId == 1026) trimGlow *= 0.4; // 亮纹饰发光减半。
			specularTex.a = max(specularTex.a, trimGlow); // 取较大者，不覆盖资源包自发光。
		}
	#endif

	WriteEntityGbuffer(albedo, viewNormal, blockLight, specularTex, materialIDs, wet, parallaxShadow); // 统一写出零、三、五号画面。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
