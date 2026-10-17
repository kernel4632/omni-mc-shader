/*
材质：把资源包的底色、法线、表面三张贴图解码成光照要用的表面数据，并给出材质编号掩码与视差偏移。
来源：照 iterationT `Lib/GbufferData.glsl` 与 `Lib/IndividualFounctions/Parallax.glsl` 一比一移植。
  `MaterialFromTex` 解码 labPBR 表面；`GetGbufferData` 从各号画面读回世界表面；`CalculateMasks` 把材质编号
  转成一堆零一掩码；`FixParticleMask`、`ApplyMaterial` 修补粒子与水玻璃冰；视差函数在高度图上找可见交点。
调用位置：
  合成阶段片元：`GbufferData gbuffer = GetGbufferData();` 后接 `CalculateMasks`、`FixParticleMask`、`ApplyMaterial`；
  几何阶段片元：地形、实体、方块、手、蜘蛛眼用 `ParallaxOcclusionMapping` 做视差；
  几何阶段顶点：地形与实体的顶点着色器读材质编号判定、法线平滑与草地修正选项。
可复制示例：
  `GbufferData gbuffer = GetGbufferData();`
  `MaterialMask mask = CalculateMasks(gbuffer.materialIDW);`
  `ivec2 texel = ParallaxOcclusionMapping(texCoord, tbn, shadowVector, duv1, duv2, normalTex, parallaxShadow);`
调用前提（iterationT 原样保留）：
  `GetGbufferData` 依赖调用方先声明整数像素坐标 `texelCoord`，并已引入画面与深度声明；
  视差函数依赖调用方声明图集采样器 `tex`、`normals`、`gaux4`（方块图集）与视空间位置 `viewPos`，
  地形还要 `flat in` 的 `textureResolution` 与 `atlasSize`。
设计原因与取舍：
  材质编号 `MATID_*` 与粒子修正开关 `CORRECT_PARTICLE_NORMAL` 是内部常数，进菜单的选项只列在下方 `@option`。
  视差段与读回段用阶段宏包住：`GetGbufferData` 需要调用方声明的 `texelCoord`，视差需要 `dFdx` 与图集采样器，
  这两类全局量只出现在特定阶段；原程序靠“只有对应阶段引入对应文件”达到同样限制，这里显式写清阶段条件，
  这样同一个效果文件被任何阶段引入都能安全编译。
*/
#ifndef OMNI_MATERIAL_INCLUDED // 只引入一次，避免结构与选项重复定义。
#define OMNI_MATERIAL_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"材质与视差","en_us":"Textures & parallax"}}
// @option {"label":{"zh_cn":"方块纹理分辨率","en_us":"Block Texture Resolution"},"description":{"zh_cn":"必须等于资源包方块贴图的分辨率，零表示自动。错误的值会让方块视差错位。","en_us":"Must match the resource pack block texture resolution; zero means auto. A wrong value breaks parallax."}}
#define OMNI_TEXTURE_RESOLUTION 0 // [0 1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"实体纹理分辨率","en_us":"Entity Texture Resolution"},"description":{"zh_cn":"实体视差用的纹理分辨率，必须与资源包一致，否则实体会错位。","en_us":"Texture resolution for entity parallax; must match the pack or entities break."}}
#define OMNI_ENTITIES_TEXTURE_RESOLUTION 16 // [1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"各向异性过滤","en_us":"Anisotropic Filtering"},"description":{"zh_cn":"让倾斜的表面更清晰；开启视差时会被禁用。","en_us":"Sharper textures on tilted surfaces; disabled while parallax is on."},"values":{"0":{"zh_cn":"关","en_us":"off"},"2":{"zh_cn":"2x","en_us":"2x"},"4":{"zh_cn":"4x","en_us":"4x"},"8":{"zh_cn":"8x","en_us":"8x"},"16":{"zh_cn":"16x","en_us":"16x"}}}
#define OMNI_ANISOTROPIC_FILTERING_QUALITY 4 // [0 2 4 8 16]
// @option {"label":{"zh_cn":"法线高光也过滤","en_us":"Filter Normal & Specular"},"description":{"zh_cn":"把各向异性过滤也用在法线与高光贴图上，代价略高但更清晰。","en_us":"Applies anisotropic filtering to the normal and specular maps too."}}
//#define OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR
// @option {"label":{"zh_cn":"实体视差","en_us":"Entity Parallax"},"description":{"zh_cn":"给实体也做视差；需要先正确设置实体纹理分辨率。","en_us":"Enables parallax on entities; set the entity texture resolution first."}}
#define OMNI_ENTITIES_PARALLAX
// @option {"label":{"zh_cn":"视差模式","en_us":"Parallax Mode"},"description":{"zh_cn":"关、锐利或平滑；锐利保持像素外观，平滑更少锯齿。","en_us":"Off, Sharp or Smooth; Sharp keeps the pixel look, Smooth has fewer artifacts."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"锐利","en_us":"Sharp"},"2":{"zh_cn":"平滑","en_us":"Smooth"}}}
#define OMNI_PARALLAX_MODE 0 // [0 1 2]
// @option {"label":{"zh_cn":"视差采样质量","en_us":"Parallax Quality"},"description":{"zh_cn":"锐利模式决定视差范围，平滑模式决定伪影多少，越大越细也越慢。","en_us":"Sharp sets the parallax range, Smooth sets artifact level; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_QUALITY 40 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"视差细化步数","en_us":"Parallax Refinements"},"description":{"zh_cn":"平滑视差找到交点后再二分细化的次数，越大边缘越准也越慢。","en_us":"Bisection steps after the parallax hit in Smooth mode; higher is more accurate and slower."},"slider":true}
#define OMNI_PARALLAX_MAX_REFINEMENTS 12 // [0 2 4 6 8 12 16]
// @option {"label":{"zh_cn":"视差阴影","en_us":"Parallax Self Shadow"},"description":{"zh_cn":"让视差像素自己也投出阳光阴影，代价很低。","en_us":"Lets parallax pixels cast their own sunlight shadow; cheap."}}
#define OMNI_PARALLAX_SHADOW
// @option {"label":{"zh_cn":"视差阴影质量","en_us":"Self Shadow Quality"},"description":{"zh_cn":"视差阴影的采样数，越大越细也越慢。","en_us":"Sample count for the parallax shadow; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_SHADOW_QUALITY 20 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"由视差生成法线","en_us":"Parallax Based Normal"},"description":{"zh_cn":"让法线效果与视差一致；平滑模式只对侧面生效。","en_us":"Keeps normals consistent with parallax; Smooth only affects sides."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"仅侧面","en_us":"Side Only"},"2":{"zh_cn":"全部","en_us":"All"}}}
#define OMNI_PARALLAX_BASED_NORMAL 1 // [0 1 2]
// @option {"label":{"zh_cn":"视差深度","en_us":"Parallax Depth"},"description":{"zh_cn":"凹凸看起来多深，单位是方块高度。","en_us":"How deep surfaces appear, in block heights."},"slider":true}
#define OMNI_PARALLAX_DEPTH 1.0 // [0.1 0.15 0.2 0.3 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 5.0 7.5 10.0]
// @option {"label":{"zh_cn":"视差淡出","en_us":"Parallax Fade"},"description":{"zh_cn":"纹理像素很小时淡出视差，避免远处闪烁；不建议关闭。","en_us":"Fades parallax when texels get tiny, avoiding shimmer; better kept on."}}
#define OMNI_PARALLAX_FADE
// @option {"label":{"zh_cn":"启用 PBR","en_us":"Enable PBR"},"description":{"zh_cn":"使用 labPBR 资源包的表面贴图；关闭后下面这些材质效果全部停用。","en_us":"Uses labPBR surface maps; turning it off disables all the material effects below."}}
#define OMNI_ENABLE_PBR
// @option {"label":{"zh_cn":"PBR 标准类型","en_us":"PBR Format"},"description":{"zh_cn":"资源包用的是 labPBR 还是另一种表面贴图编码。","en_us":"Whether the pack stores labPBR or PTGI surface data."},"values":{"0":{"zh_cn":"labPBR","en_us":"labPBR"},"2":{"zh_cn":"PTGI","en_us":"PTGI"}}}
#define OMNI_TEXTURE_PBR_FORMAT 0 // [0 2]
// @option {"label":{"zh_cn":"限制最大粗糙度","en_us":"Clamp High Roughness"},"description":{"zh_cn":"把高粗糙表面的反射直接屏蔽，省性能。","en_us":"Skips reflections on very rough surfaces to save performance."}}
#define OMNI_ROUGHNESS_CLAMP
// @option {"label":{"zh_cn":"限制方块法线强度","en_us":"Terrain Normal Clamp"},"description":{"zh_cn":"压住方块的极端法线，减少噪点。","en_us":"Limits extreme terrain normals to reduce noise."}}
//#define OMNI_TERRAIN_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制手部法线强度","en_us":"Hand Normal Clamp"},"description":{"zh_cn":"压住手持物的极端法线，减少噪点。","en_us":"Limits extreme hand normals to reduce noise."}}
#define OMNI_HAND_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制实体法线强度","en_us":"Entity Normal Clamp"},"description":{"zh_cn":"压住实体的极端法线，减少噪点。","en_us":"Limits extreme entity normals to reduce noise."}}
#define OMNI_ENTITIES_NORMAL_CLAMP
// @option {"label":{"zh_cn":"次表面散射强度","en_us":"SSS Strength"},"description":{"zh_cn":"光照穿透表面的深度倍率，与偏移一起为零时关闭次表面散射。","en_us":"Depth multiplier of light through the surface; with the offset at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"次表面散射偏移","en_us":"SSS Strength Offset"},"description":{"zh_cn":"给穿透深度一个最小值；与倍率一起为零时关闭次表面散射。","en_us":"Minimum value for the light depth; with the multiplier at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH_OFFSET 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"自发光曲线","en_us":"Emissive Gamma"},"description":{"zh_cn":"PBR 自发光的亮暗对比强度，越大反差越明显。","en_us":"Contrast curve of PBR emissiveness; higher is more contrast."},"slider":true}
#define OMNI_EMISSIVENESS_GAMMA 2.2 // [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"labPBR 孔隙率","en_us":"labPBR Porosity"},"description":{"zh_cn":"使用资源包里的孔隙率通道，决定表面多容易积水。","en_us":"Uses the porosity channel so the surface can puddle more or less."}}
//#define OMNI_TEXTURE_PBR_POROSITY
// @option {"label":{"zh_cn":"默认孔隙率","en_us":"Default Porosity"},"description":{"zh_cn":"资源包不给孔隙率时用的值，越小越不吸水、水洼越明显。","en_us":"Porosity when the pack has none; lower means less absorbent and more puddles."},"slider":true}
#define OMNI_TEXTURE_DEFAULT_POROSITY 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"潮湿反照吸收","en_us":"Wetness Albedo Absorption"},"description":{"zh_cn":"潮湿表面压暗的强度，孔隙率越大越明显。","en_us":"How much wet surfaces darken; stronger with higher porosity."},"slider":true}
#define OMNI_POROSITY_ABSORPTION 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"禁用手部高光","en_us":"Disable Hand Specular"},"description":{"zh_cn":"去掉手持物的高光，解决某些模组下的反射噪点。","en_us":"Removes held item specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_HAND_SPECULAR
// @option {"label":{"zh_cn":"禁用玩家高光","en_us":"Disable Player Specular"},"description":{"zh_cn":"去掉玩家自身的高光，解决某些模组下的反射噪点。","en_us":"Removes the player's own specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_PLAYER_SPECULAR
// @option {"label":{"zh_cn":"实体顶点法线平滑","en_us":"Entity Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供实体顶点切线与法线，代价很低。","en_us":"Provides entity vertex tangents and normals for some mods; cheap."}}
#define OMNI_ENTITIES_VS_TBN
// @option {"label":{"zh_cn":"方块顶点法线平滑","en_us":"Block Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供方块顶点切线与法线，代价很低。","en_us":"Provides block vertex tangents and normals for some mods; cheap."}}
//#define OMNI_TERRAIN_VS_TBN
// @option {"label":{"zh_cn":"未指定方块按植物处理","en_us":"General Grass Fix"},"description":{"zh_cn":"把倾斜的面都当成植物渲染，可能误伤其他方块。","en_us":"Treats tilted faces as plants; may misfire on other blocks."}}
//#define OMNI_GENERAL_GRASS_FIX
// @option {"label":{"zh_cn":"白色调试世界","en_us":"White Debug World"},"page":"dev","description":{"zh_cn":"把所有几何的底色改写成纯白，用来检查光照与几何；仅供调试。","en_us":"Rewrites every geometry albedo to plain white for checking lighting and geometry; debug only."}}
//#define OMNI_WHITE_DEBUG_WORLD
// 内部常数：方块与实体材质编号，按 iterationT `Settings.glsl` 原值，几何与合成阶段共用一份。
#define MATID_SKY 0.0 // 天空里没有几何的像素。
#define MATID_LAND 1.0 // 普通不透明方块，默认材质编号。
#define MATID_GRASS 2.0 // 草与植物类。
#define MATID_LEAVES 3.0 // 树叶。
#define MATID_HAND 4.0 // 手持物。
#define MATID_WATER 6.0 // 水。
#define MATID_STAINEDGLASS 7.0 // 染色玻璃。
#define MATID_ICE 8.0 // 冰。
#define MATID_ENTITIES_PLAYER 10.0 // 玩家自身。
#define MATID_ENTITIES_LIT_HIGH 11.0 // 实体里高亮度自发光的一类。
#define MATID_ENTITIES_LIT_MEDIUM 12.0 // 实体里中等亮度自发光的一类。
#define MATID_ENTITIES_LIT_LOW 13.0 // 实体里低亮度自发光的一类。
#define MATID_ENTITIES_SNOW 14.0 // 实体身上的雪层。
#define MATID_LIGHTNING 15.0 // 闪电。
#define MATID_BEACON_BEAM 16.0 // 信标光柱。
#define MATID_GLOWSTONE 20.0 // 荧石。
#define MATID_TORCH 21.0 // 火把。
#define MATID_LAVA 22.0 // 岩浆。
#define MATID_FIRE 23.0 // 火。
#define MATID_REDSTONE_TORCH 24.0 // 红石火把。
#define MATID_REDSTONE 25.0 // 红石线。
#define MATID_SOULFIRE 26.0 // 灵魂火。
#define MATID_AMETHYST 27.0 // 紫水晶。
#define MATID_OXIDIZED_BULB 28.0 // 氧化的铜灯。
#define MATID_PARTICLE 40.0 // 普通粒子。
#define MATID_PARTICLE_LIT 41.0 // 受光粒子。
#define MATID_END_PORTAL 50.0 // 末地传送门。
#define MATID_SELECTION 200.0 // 选择框与线条。
// 内部常数：粒子法线修正开关。iterationT 原文声明了它但源码里没有引用，按合同原样保留在这里。
#define CORRECT_PARTICLE_NORMAL
// 解码、掩码与视差都用到共用数学，先引入加载器输入与共用计算。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// --- 方块光曲线：把原版方块光等级压成光照要用的亮度 ---
// 天光曲线的形状：先抬高低等级，再整体压暗，等级越高越接近饱和。
float CurveBlockLightSky(float blockLight){
	blockLight = 1.0 - pow(1.0 - blockLight * 0.9, 0.7); // 抬高低等级并保留低端细节。
	blockLight = saturate(blockLight * blockLight * blockLight * 1.95); // 三次方拉开对比后夹紧。
	return blockLight; // 返回处理后的天光等级。
}
// 方块光曲线的形状：先按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float CurveBlockLightTorch(float blockLight){
	float dist = (1.0 - blockLight) * 15.0 + 1.0; // 把等级转成米制距离，等级为零时距离最远。
	dist = dist * dist; // 距离平方，衰减更快。
	float boost = saturate(blockLight * 2.0 - 1.0); // 只有高等级才有的提升量。
	blockLight = blockLight + boost * boost; // 先加提升，突出光源附近的亮度。
	blockLight /= dist; // 再按距离平方衰减。
	return blockLight; // 返回处理后的方块光。
}
// --- 表面数据结构：读回画面后一次装完光照要用的量 ---
// 每次采样的表面材质参数：粗糙、金属、菲涅尔零点、自发光、散射与反射强度。
struct Material{
	float roughness; // 粗糙度，越大高光越散。
	float metalness; // 金属度，越大底色越偏反射。
	float f0; // 表面正射反射率，金属接近底色、非金属约零点零四。
	float emissiveness; // 自发光强度。
	float scattering; // 次表面散射强度。
	float reflectionStrength; // 这份表面允许反射的强度。
};
// 一个像素读回的完整表面数据：底色、法线、深度、光照图、材质编号与材质参数。
struct GbufferData{
	vec3 albedo; // 不透明表面底色，已转线性。
	vec4 albedoW; // 半透明表面底色与其透明度。
	vec3 normalL; // 半透明表面的切线空间法线。
	vec3 normalW; // 不透明表面的世界切线空间法线。
	float depthL; // 半透明层深度。
	float depthW; // 不透明层深度。
	vec2 lightmapL; // 半透明层光照图，方块光与天光。
	vec2 lightmapW; // 不透明层光照图。
	float materialIDL; // 半透明层材质编号。
	float materialIDW; // 不透明层材质编号。
	float waterMask; // 水遮罩。
	float rainAlpha; // 雨雪遮罩。
	float parallaxShadow; // 视差自阴影透过率。
	Material material; // 解码后的材质参数。
};
// 一条射线，供屏幕空间反射等使用。
struct Ray{
	vec3 dir; // 方向。
	vec3 origin; // 起点。
};
// 一张平面，供屏幕空间反射等使用。
struct Plane{
	vec3 normal; // 法线。
	vec3 origin; // 平面上一点。
};
// 一次求交结果，供屏幕空间反射等使用。
struct Intersection{
	vec3 pos; // 交点位置。
	float distance; // 沿射线的距离。
	float angle; // 命中面的夹角。
};
// 空气材质：不做反射、粗糙度为一。
const Material airMaterial = Material(1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
// 水材质：光滑强反射。
const Material material_water = Material(0.0, 0.0, 0.02, 0.0, 0.0, 1.0);
// 玻璃材质：比水略高的固定反射率。
const Material material_glass = Material(0.0, 0.0, 0.042, 0.0, 0.0, 1.0);
// 冰材质：反射率介于水与玻璃之间。
const Material material_ice = Material(0.0, 0.0, 0.018, 0.0, 0.0, 1.0);
// 从表面贴图解出材质：孔隙率决定吸水压暗，其余通道解出粗糙、金属、自发光与散射。
// 参数 `wet` 是这一处的湿润度，`baseTex` 会被吸水压暗，所以是 `inout`。
Material MaterialFromTex(inout vec3 baseTex, vec4 specTex, float wet){
	#ifdef OMNI_TEXTURE_PBR_POROSITY // 资源包自带孔隙率时按标准位宽解码。
		#if OMNI_TEXTURE_PBR_FORMAT < 2
			float porosity = saturate(specTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specTex.b)); // 蓝色通道的高六位表示孔隙率。
		#else
			float porosity = OMNI_TEXTURE_DEFAULT_POROSITY; // `PTGI` 格式没有孔隙率，退回默认值。
		#endif
	#else
		float porosity = OMNI_TEXTURE_DEFAULT_POROSITY; // 没开孔隙率时统一用默认值。
	#endif
	baseTex *= 1.0 - wet * fsqrt(porosity) * OMNI_POROSITY_ABSORPTION; // 吸水越多的表面越暗，孔隙率开方让差异更平缓。
	Material material; // 下面逐项填入。
	float rawSmoothness = mix(specTex.r, 1.0, saturate(wet * (1.7 - porosity * 0.7))); // 湿润把表面拉向光滑，孔隙率大则拉得少。
	material.roughness = 1.0 - rawSmoothness; // 平滑度取反得到粗糙度。
	material.roughness *= material.roughness; // 再平方，让光滑面更集中。
	float rawMetalness = specTex.g; // 绿色通道是金属度。
	#if OMNI_TEXTURE_PBR_FORMAT == 0
		rawMetalness = saturate(rawMetalness + step(0.9, rawMetalness)); // labPBR 允许预设金属，把高位拉满。
	#endif
	#ifdef OMNI_ROUGHNESS_CLAMP // 开启限制时把金属度往零点一以内收，配合反射屏蔽。
		material.metalness = saturate(rawMetalness * 1.1 - 0.1); // 先放大再平移，最后夹紧。
	#else
		material.metalness = rawMetalness; // 否则原样使用。
	#endif
	material.f0 = rawMetalness * 0.96 + 0.04; // 金属度高则反射率接近底色，非金属约零点零四。
	#ifdef OMNI_ROUGHNESS_CLAMP // 限制模式用更陡的曲线快速去掉粗糙面的反射。
		material.reflectionStrength = saturate(2.0 - material.roughness * 5.0); // 粗糙度超过零点四就基本不反射。
	#else
		material.reflectionStrength = saturate(2.0 - material.roughness * 2.0); // 普通模式反射保留更多。
	#endif
	material.reflectionStrength = saturate(material.reflectionStrength + material.metalness * 1e10 + wet * 3.0); // 金属和湿润表面一律全反射。
	material.emissiveness = specTex.a; // 透明通道是自发光。
	#if OMNI_TEXTURE_PBR_FORMAT < 2
		material.emissiveness -= step(1.0, material.emissiveness); // 标准规定满值表示没有自发光，减掉它。
	#endif
	material.emissiveness = pow(material.emissiveness, OMNI_EMISSIVENESS_GAMMA); // 按选项重整亮暗对比。
	#if OMNI_TEXTURE_PBR_FORMAT < 2
		material.scattering = saturate((specTex.b * 255.0 - 64.0) / 191.0) * OMNI_SSS_STRENGTH + OMNI_SSS_STRENGTH_OFFSET; // 蓝色通道的其余位表示散射强度。
	#else
		material.scattering = 0.0; // `PTGI` 格式没有散射，记零。
	#endif
	return material; // 交回解码好的材质。
}
// 从各号画面读回一个像素的完整表面数据，供合成阶段使用。
// 调用前提：调用方必须先声明整数像素坐标 `texelCoord`。
#if defined OMNI_COMPOSITE0_PASS || defined OMNI_COMPOSITE1_PASS || defined OMNI_COMPOSITE2_PASS || defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS || defined OMNI_COMPOSITE5_PASS
GbufferData GetGbufferData(){
	GbufferData data; // 逐项填入。
	vec4 gbuffer0 = texelFetch(colortex0, texelCoord, 0); // 零号画面：不透明底色。
	vec4 gbuffer3 = texelFetch(colortex3, texelCoord, 0); // 三号画面：不透明法线与光照图。
	vec4 gbuffer4 = texelFetch(colortex4, texelCoord, 0); // 四号画面：半透明法线与光照图。
	vec4 gbuffer5 = texelFetch(colortex5, texelCoord, 0); // 五号画面：不透明高光材质与湿润。
	vec4 gbuffer6 = texelFetch(colortex6, texelCoord, 0); // 六号画面：半透明颜色材质与水遮罩。
	data.albedo = GammaToLinear(gbuffer0.rgb); // 底色从伽马空间转回线性。
	data.albedoW = vec4(Unpack2x8(gbuffer6.r), Unpack2x8(gbuffer6.g)); // 半透明底色打包在两个通道里，先拆开。
	data.albedoW.rgb = GammaToLinear(data.albedoW.rgb); // 拆开后的底色同样转线性。
	data.normalL = DecodeNormal(gbuffer3.rg); // 三号画面的两个通道是半透明法线。
	data.normalW = DecodeNormal(gbuffer4.rg); // 四号画面的两个通道是不透明法线。
	data.depthL = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的深度。
	data.depthW = texelFetch(depthtex0, texelCoord, 0).x; // 含半透明的深度。
	data.lightmapL = gbuffer3.ba; // 三号画面的后两个通道是半透明光照图。
	data.lightmapW = gbuffer4.ba; // 四号画面的后两个通道是不透明光照图。
	data.lightmapL = vec2(data.lightmapL.r, CurveBlockLightSky(data.lightmapL.g)); // 天光分量按曲线重整。
	data.lightmapW = vec2(data.lightmapW.r, CurveBlockLightSky(data.lightmapW.g)); // 不透明层同样处理。
	data.materialIDL = gbuffer5.b; // 五号画面的蓝色通道是不透明材质编号。
	data.materialIDW = gbuffer6.b; // 六号画面的蓝色通道是半透明材质编号。
	data.waterMask = gbuffer6.a; // 六号画面的透明通道是水遮罩。
	data.rainAlpha = 1.0 - gbuffer0.a; // 零号画面的透明度被雨雪乘过，取反得到雨量。
	vec2 gbuffer5a = Unpack2x8(gbuffer5.a); // 五号画面的透明通道打包了湿润与视差阴影。
	data.parallaxShadow = gbuffer5a.y; // 第二个是视差自阴影。
	#ifdef OMNI_ENABLE_PBR // 开启物理光照时才解材质，否则当作空气。
		vec4 specTex = vec4(Unpack2x8(gbuffer5.r), Unpack2x8(gbuffer5.g)); // 五号画面的红绿通道里是表面贴图。
		data.material = MaterialFromTex(data.albedo, specTex, gbuffer5a.x); // 解出材质，同时压暗吸水底色。
		#if MC_VERSION < 11605
			data.material.reflectionStrength *= float(data.depthW >= 0.7); // 旧版没有单独的半透明深度，天空像素不该反射。
		#endif
	#else
		data.material = airMaterial; // 关闭物理光照时统一按空气处理。
	#endif
	return data; // 交回读回的数据。
}
#endif // 合成阶段读回段结束。
// --- 材质掩码：把材质编号拆成一组零一标记，后续按标记分效果 ---
// 一份掩码里每个字段都是零或一，表示这个像素属于某类材质。
struct MaterialMask{
	float sky; // 天空像素。
	float land; // 普通不透明方块。
	float grass; // 草与植物。
	float leaves; // 树叶。
	float hand; // 手持物。
	float entityPlayer; // 玩家。
	float water; // 水。
	float stainedGlass; // 染色玻璃。
	float ice; // 冰。
	float entitiesLitHigh; // 高亮自发光实体。
	float entitiesLitMedium; // 中亮自发光实体。
	float entitiesLitLow; // 低亮自发光实体。
	float lightning; // 闪电。
	float entitiesSnow; // 实体雪层。
	float torch; // 火把。
	float lava; // 岩浆。
	float glowstone; // 荧石。
	float fire; // 火。
	float redstoneTorch; // 红石火把。
	float redstone; // 红石线。
	float soulFire; // 灵魂火。
	float amethyst; // 紫水晶。
	float oxidizedBulb; // 氧化铜灯。
	float particle; // 普通粒子。
	float particlelit; // 受光粒子。
	float endPortal; // 末地传送门。
	float selection; // 选择框。
};
// 把八位材质编号还原成类别，再逐项比对给出掩码。
MaterialMask CalculateMasks(float materialIDs){
	MaterialMask mask; // 逐项填入。
	materialIDs = floor(materialIDs * 255.0); // 画面里存的是编号除以二百五十五，先还原成编号。
	mask.sky = float(materialIDs == MATID_SKY); // 天空。
	mask.land = float(materialIDs == MATID_LAND); // 普通方块。
	mask.grass = float(materialIDs == MATID_GRASS || materialIDs == MATID_BEACON_BEAM); // 草，信标光柱也当作草处理。
	mask.leaves = float(materialIDs == MATID_LEAVES); // 树叶。
	mask.hand = float(materialIDs == MATID_HAND); // 手持物。
	mask.water = float(materialIDs == MATID_WATER); // 水。
	mask.stainedGlass = float(materialIDs == MATID_STAINEDGLASS); // 染色玻璃。
	mask.ice = float(materialIDs == MATID_ICE); // 冰。
	mask.entityPlayer = float(materialIDs == MATID_ENTITIES_PLAYER); // 玩家。
	mask.entitiesLitHigh = float(materialIDs == MATID_ENTITIES_LIT_HIGH || materialIDs == MATID_BEACON_BEAM); // 高亮实体。
	mask.entitiesLitMedium = float(materialIDs == MATID_ENTITIES_LIT_MEDIUM); // 中亮实体。
	mask.entitiesLitLow = float(materialIDs == MATID_ENTITIES_LIT_LOW); // 低亮实体。
	mask.entitiesSnow = float(materialIDs == MATID_ENTITIES_SNOW || materialIDs == MATID_BEACON_BEAM); // 实体雪层。
	mask.lightning = float(materialIDs == MATID_LIGHTNING); // 闪电。
	mask.torch = float(materialIDs == MATID_TORCH); // 火把。
	mask.lava = float(materialIDs == MATID_LAVA); // 岩浆。
	mask.glowstone = float(materialIDs == MATID_GLOWSTONE); // 荧石。
	mask.fire = float(materialIDs == MATID_FIRE); // 火。
	mask.redstoneTorch = float(materialIDs == MATID_REDSTONE_TORCH); // 红石火把。
	mask.redstone = float(materialIDs == MATID_REDSTONE); // 红石线。
	mask.soulFire = float(materialIDs == MATID_SOULFIRE); // 灵魂火。
	mask.amethyst = float(materialIDs == MATID_AMETHYST); // 紫水晶。
	mask.oxidizedBulb = float(materialIDs == MATID_OXIDIZED_BULB); // 氧化铜灯。
	mask.particle = float(materialIDs == MATID_PARTICLE); // 普通粒子。
	mask.particlelit = float(materialIDs == MATID_PARTICLE_LIT); // 受光粒子。
	mask.endPortal = float(materialIDs == MATID_END_PORTAL); // 末地传送门。
	mask.selection = float(materialIDs == MATID_SELECTION); // 选择框。
	return mask; // 交回掩码。
}
// 粒子修正并带深度：粒子很薄，读回时会落到后面的几何上，所以把半透明层也标记成粒子并借用不透明深度。
void FixParticleMask(inout MaterialMask materialMaskSoild, inout MaterialMask materialMask, inout float depthL, in float depthW){
	#if MC_VERSION >= 11500 // 一点一五以后粒子单独一层，才需要这份修正。
	if (materialMaskSoild.particle > 0.5 || materialMaskSoild.particlelit > 0.5){ // 不透明层出现粒子才修正。
		materialMask.particle = 1.0; // 半透明层也当作粒子。
		materialMask.water = 0.0; // 粒子不是水。
		materialMask.stainedGlass = 0.0; // 也不是玻璃。
		materialMask.ice = 0.0; // 也不是冰。
		materialMask.sky = 0.0; // 也不是天空。
		depthL = depthW; // 深度改用不透明层，避免粒子读到自己后面的方块。
	}
	#endif
}
// 粒子修正：同上，但不改深度，供不需要深度的阶段使用。
void FixParticleMask(inout MaterialMask materialMaskSoild, inout MaterialMask materialMask){
	#if MC_VERSION >= 11500 // 同样只在一点一五以后生效。
	if (materialMaskSoild.particle > 0.5 || materialMaskSoild.particlelit > 0.5){ // 不透明层出现粒子才修正。
		materialMask.particle = 1.0; // 半透明层也当作粒子。
		materialMask.water = 0.0; // 粒子不是水。
		materialMask.stainedGlass = 0.0; // 也不是玻璃。
		materialMask.ice = 0.0; // 也不是冰。
		materialMask.sky = 0.0; // 也不是天空。
	}
	#endif
}
// 用固定材质覆盖解码材质：水、染色玻璃与冰用写死的参数，并标记为光滑面。
void ApplyMaterial(inout Material material, in MaterialMask materialMask, inout bool isSmooth){
	if (materialMask.water > 0.5){ // 水。
		material = material_water; // 换成水材质。
		isSmooth = true; // 标记为光滑。
	}
	if (materialMask.stainedGlass > 0.5){ // 染色玻璃。
		material = material_glass; // 换成玻璃材质。
		isSmooth = true; // 标记为光滑。
	}
	if (materialMask.ice > 0.5){ // 冰。
		material = material_ice; // 换成冰材质。
		isSmooth = true; // 标记为光滑。
	}
}
// --- 视差：沿视线在高度图里找可见交点，并与视差自阴影配合 ---
// 视差只在几何片元编译：它需要 `dFdx`、图集采样器 `tex`/`normals`/`gaux4` 与视空间位置 `viewPos`，
// 合成阶段没有这些全局量；原程序靠“只有几何片元引入 `Parallax.glsl`”达到同样限制，这里显式写出阶段条件。
#if defined OMNI_FRAGMENT && (defined OMNI_TERRAIN_PASS || defined OMNI_ENTITIES_PASS || defined OMNI_BLOCK_PASS || defined OMNI_HAND_PASS || defined OMNI_SPIDEREYES_PASS)
#if OMNI_PARALLAX_MODE > 1 // 平滑模式：双线性高度采样加二分细化。
// 视差阴影用到时间蓝噪声。
#include "/common/noise.glsl"
// 双线性采样式高度：在图块内跨格子读四角高度并插值，越界处用一层薄壳把空隙补平。
// 参数 `tilesBaseTexel` 是图块左上角在图集里的像素坐标，`iTextureResolution` 是图块边长的按位掩码。
float BilinearHeightSample(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution
#ifndef OMNI_TERRAIN_PASS
, bool isBlock // 实体阶段要判断这张图是不是方块图集。
#endif
){
	ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
	ivec2 texelW = texelX + 1; // 右上角像素。
	vec2 f = coord - vec2(texelX); // 到左下角的小数偏移。
	#ifndef OMNI_TERRAIN_PASS
		if (isBlock){ // 实体用到方块图集时也要按图块回绕。
			texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕到本图块内。
			texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
		}
	#else
		texelX = tilesBaseTexel + (texelX & iTextureResolution); // 地形一律按图块回绕。
		texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
	#endif
	vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 左下角高度。
				   texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a, // 右下角高度。
				   texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a, // 左上角高度。
				   texelFetch(normals, texelW, 0).a); // 右上角高度。
	sh += saturate(1.0 - sh * 1e20); // 高度为零表示没有视差数据，补成完整高度，避免出现空洞。
	return mix(mix(sh.x, sh.y, f.x), // 先沿横轴插值两对。
			   mix(sh.z, sh.w, f.x), // 再沿横轴插值另外两对。
			   f.y); // 最后沿纵轴插值得到高度。
}
// 用高度差直接生成法线：平滑模式可以只用高度场求梯度，得到与视差一致的法线。
vec3 HeightBasedNormal(vec2 coord, ivec2 tilesBaseTexel, float textureResolution, int iTextureResolution
#ifndef OMNI_TERRAIN_PASS
, bool isBlock // 实体阶段要判断是不是方块图集。
#endif
){
	coord -= 0.5; // 把坐标移到像素中心。
	ivec2 texelX = ivec2(floor(coord)); // 左下角像素。
	ivec2 texelW = texelX + 1; // 右上角像素。
	vec2 f = coord - vec2(texelX); // 小数偏移。
	#ifndef OMNI_TERRAIN_PASS
		if (isBlock){ // 实体用到方块图集时回绕。
			texelX = tilesBaseTexel + (texelX & iTextureResolution); // 左下角回绕。
			texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角回绕。
		}
	#else
		texelX = tilesBaseTexel + (texelX & iTextureResolution); // 地形一律回绕。
		texelW = tilesBaseTexel + (texelW & iTextureResolution); // 右上角同理。
	#endif
	vec4 sh = vec4(texelFetch(normals, texelX, 0).a, // 四角高度，含义同上一函数。
				   texelFetch(normals, ivec2(texelW.x, texelX.y), 0).a,
				   texelFetch(normals, ivec2(texelX.x, texelW.y), 0).a,
				   texelFetch(normals, texelW, 0).a);
	#if OMNI_PARALLAX_MODE == 2 // 平滑模式：直接由四角高度差得到梯度。
		sh.w = sh.y + sh.z - sh.x - sh.w; // 把四角合成一个中心差分量。
		return vec3(sh.w * f.yx + (sh.x - sh.yz), (8.0 / OMNI_PARALLAX_DEPTH) / textureResolution); // 梯度乘深度再归一化，深度越大法线越陡。
	#else
		const float eps = 0.01; // 靠近像素边缘时梯度会突变，用一个小阈值把它压平。
		f -= 0.5; // 偏移改到像素中心附近。
		float dX = mix(sh.x - sh.y, sh.z - sh.w, saturate(f.y * 1e20)) * saturate((eps - abs(f.x)) * 1e20); // 横向梯度，越靠边越弱。
		float dY = mix(sh.x - sh.z, sh.y - sh.w, saturate(f.x * 1e20)) * saturate((eps - abs(f.y)) * 1e20); // 纵向梯度同理。
		return vec3(dX, dY, step(abs(dX) + abs(dY), 0.0)); // 没有梯度的地方朝外。
	#endif
}
// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
// 参数 `tbnMat` 是切线基，`shadowVector` 是视空间阳光方向，`duv1`、`duv2` 是纹理坐标的屏幕导数。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 normalTex, inout float parallaxShadow){
	#ifndef OMNI_TERRAIN_PASS
		const float textureResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		ivec2 atlasSize = textureSize(tex, 0); // 实体图集大小由采样器读出。
		bool isBlock = textureSize(gaux4, 0) == atlasSize; // 图集大小与方块图集一致就按方块处理。
	#endif
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少个图块。
	#ifdef OMNI_PARALLAX_FADE // 需要淡出时先算这一处的淡出因子。
		vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
		float fade = saturate(pow(max(duvMax.x, duvMax.y), -0.1) * (1.0 / 1.4)); // 像素越小越淡出，避免远处闪烁。
	#endif
	vec2 tilesBaseCoord = floor(coord * atlasTiles); // 当前坐标落在哪个图块。
	ivec2 tilesBaseTexel = ivec2(tilesBaseCoord * textureResolution); // 该图块左上角的像素坐标。
	int iTextureResolution = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
	vec3 parallaxTexelCoord = vec3(coord * atlasSize, 1.0); // 换成图集像素坐标并把深度放到一。
	float sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy - 0.5, tilesBaseTexel, textureResolution, iTextureResolution // 先读起始高度。
	#ifndef OMNI_TERRAIN_PASS
	, isBlock // 实体阶段传入是否方块。
	#endif
	);
	if (sampleHeight > 0.0 && sampleHeight < 1.0){ // 只有处在表面内部的像素才需要偏移。
		parallaxTexelCoord.xy -= 0.5; // 坐标移到像素中心。
		vec3 viewVector = normalize(viewPos) * tbnMat; // 视线方向转到切线空间。
		viewVector /= -viewVector.z; // 归一化到单位深度步长。
		vec3 stepDir = viewVector / OMNI_PARALLAX_QUALITY; // 每一步的方向。
		stepDir.xy *= textureResolution * OMNI_PARALLAX_DEPTH * 0.25; // 横向步长按图块尺寸与深度缩放。
		float stepLength = 2.0 / OMNI_PARALLAX_QUALITY; // 逐步加深的初始步长。
		for (int i = 0; i < OMNI_PARALLAX_QUALITY; i++, stepLength += 2.0 / OMNI_PARALLAX_QUALITY){ // 线性步进找交点。
			parallaxTexelCoord += stepDir * stepLength; // 前进一小步。
			sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution // 读这一步的高度。
			#ifndef OMNI_TERRAIN_PASS
			, isBlock // 实体阶段传入是否方块。
			#endif
			);
			if (sampleHeight > parallaxTexelCoord.z) break; // 表面高度超过步进深度就找到了交点。
		}
		for (int i = 0; i < OMNI_PARALLAX_MAX_REFINEMENTS; i++){ // 二分细化交点。
			if (sampleHeight > parallaxTexelCoord.z){ // 越过交点就回退半步。
				parallaxTexelCoord -= stepDir * stepLength; // 回退。
				stepLength *= 0.5; // 步长减半。
			}
			parallaxTexelCoord += stepDir * stepLength; // 再前进一个更小的步。
			sampleHeight = BilinearHeightSample(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution // 读高度。
			#ifndef OMNI_TERRAIN_PASS
			, isBlock // 实体阶段传入是否方块。
			#endif
			);
		}
		if (sampleHeight <= parallaxTexelCoord.z) parallaxTexelCoord += stepDir * stepLength * 2.0; // 最后仍未越界就多走两步，避免停在表面下。
		#ifdef OMNI_PARALLAX_SHADOW // 需要视差自阴影时。
			if (parallaxShadow > 0.0){ // 只有原先允许受光的像素才算阴影。
				shadowVector = shadowVector * tbnMat; // 阳光方向转到切线空间。
				shadowVector /= shadowVector.z * 0.9 + 0.1; // 归一化到单位深度步长，避免水平方向过大。
				vec3 shadowTexelCoord = parallaxTexelCoord; // 从交点出发。
				vec3 stepSize = shadowVector / (OMNI_PARALLAX_SHADOW_QUALITY); // 阴影步进方向。
				stepSize.xy *= textureResolution * OMNI_PARALLAX_DEPTH * 0.25; // 横向步长按图块与深度缩放。
				#ifdef OMNI_TAA // 开时间抗锯齿时用蓝噪声抖动起点。
					shadowTexelCoord += stepSize * BlueNoiseTemporal().x; // 逐像素抖动，让噪点被时间平均。
				#else
					shadowTexelCoord += stepSize; // 不开时只多走一步。
				#endif
				for (int i = 0; i < OMNI_PARALLAX_SHADOW_QUALITY; i++, shadowTexelCoord += stepSize){ // 沿光方向步进找遮挡。
					if (shadowTexelCoord.z > 1.0) break; // 超出表面顶部就不再遮挡。
					sampleHeight = BilinearHeightSample(shadowTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution // 读遮挡候选的高度。
					#ifndef OMNI_TERRAIN_PASS
					, isBlock // 实体阶段传入是否方块。
					#endif
					);
					float diff = shadowTexelCoord.z - sampleHeight; // 光线高度减去表面高度，负得越多遮挡越强。
					parallaxShadow *= saturate(diff * 40.0 + 1.0); // 逐步累积遮蔽。
					if (parallaxShadow < 0.003) break; // 已经足够黑就提前结束。
				}
			}
			#ifdef OMNI_PARALLAX_FADE
				parallaxShadow = mix(1.0, parallaxShadow, fade); // 远处淡出阴影，避免闪烁。
			#endif
		#endif
		parallaxTexelCoord.xy += 0.5; // 坐标移回像素角。
		#if OMNI_PARALLAX_BASED_NORMAL == 2 // 全部用视差生成法线时。
			normalTex = HeightBasedNormal(parallaxTexelCoord.xy, tilesBaseTexel, textureResolution, iTextureResolution // 由高度场求法线。
			#ifndef OMNI_TERRAIN_PASS
			, isBlock // 实体阶段传入是否方块。
			#endif
			);
		#endif
		parallaxTexelCoord.xy = (fract(parallaxTexelCoord.xy / textureResolution) + tilesBaseCoord) * textureResolution; // 把偏移后的坐标折回原本的图块。
	}
	ivec2 parallaxTexel = ivec2(parallaxTexelCoord.xy); // 最终要采样到的像素。
	#if OMNI_PARALLAX_BASED_NORMAL < 2 // 不是全部用视差法线时，照常从法线贴图取。
		normalTex = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 解出切线空间法线。
	#else
		#ifdef OMNI_PARALLAX_FADE
			normalTex = mix(vec3(0.0, 0.0, 1.0), normalTex, fade); // 远处淡出到朝外法线。
		#endif
	#endif
	return parallaxTexel; // 交回被遮挡后的采样像素。
}
#elif OMNI_PARALLAX_MODE == 1 // 锐利模式：逐像素穿越图块，保持像素外观。
// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 hitNormal, inout float parallaxShadow){
	#ifndef OMNI_TERRAIN_PASS
		const float textureResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		ivec2 atlasSize = textureSize(tex, 0); // 实体图集大小。
		bool isBlock = textureSize(gaux4, 0) == atlasSize; // 是否方块图集。
	#endif
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少图块。
	vec2 pixelCoord = coord * vec2(atlasSize); // 当前坐标换算成图集像素。
	ivec2 parallaxTexel = ivec2(floor(pixelCoord)); // 起始像素。
	int iTextureResolution = int(textureResolution) - 1; // 图块边长减一，用作回绕掩码。
	float sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 起始高度。
	sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
	bool exit = false; // 是否命中了表面。
	if (sampleHeight > 0.0 && sampleHeight < 1.0){ // 只有处在表面内部才穿越。
		#ifdef OMNI_PARALLAX_FADE
			vec2 duvMax = max(abs(duv1), abs(duv2)) * atlasTiles; // 纹理坐标的屏幕变化量换成图块单位。
			float fade = saturate(pow(max(duvMax.x, duvMax.y), -0.4) * 0.2); // 像素越小越淡出。
		#endif
		ivec2 tilesPixelBase = ivec2(floor(coord * atlasTiles) * textureResolution); // 当前图块左上角的像素。
		vec3 viewVector = normalize(viewPos) * tbnMat; // 视线方向转到切线空间。
		vec3 stepDir = normalize(vec3(viewVector.xy * OMNI_PARALLAX_DEPTH * textureResolution * 0.25, -viewVector.z)); // 每像素前进方向，横向按深度缩放。
		vec2 ardir = abs(1.0 / stepDir.xy); // 每走一个像素在横纵方向各需要多远。
		ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 横纵方向的符号，用位运算取正负一。
		vec2 totalStep = (vec2(sdir) * (0.5 - (pixelCoord - vec2(parallaxTexel))) + 0.5) * ardir; // 到下一个像素边界的距离。
		float stepLength = 0.0; // 这一步走过的深度。
		float stepHeight = 1.0; // 这一步光线所在的高度。
		float prevStepHeight = 1.0; // 上一步高度，用于判断交点落在哪一列。
		ivec2 stepNext = ivec2(0); // 这一步往哪个方向跨像素。
		for (int i = 0; i < OMNI_PARALLAX_QUALITY; i++){ // 逐像素前进。
			stepLength = min(totalStep.x, totalStep.y); // 先碰到哪一侧边界就按哪一侧走。
			stepHeight = 1.0 - stepLength * stepDir.z; // 这一步光线到达的高度。
			if (sampleHeight > stepHeight){ // 表面高过光线，说明这一段遮挡了像素。
				if (sampleHeight > prevStepHeight){ // 交点落在上一步与这一步之间时用上一步的法线。
					hitNormal = vec3(-stepNext * sdir, 0.0); // 由跨步方向估计侧面法线。
					sampleHeight = prevStepHeight; // 高度取上一步，便于后续阴影。
				}
				exit = true; // 标记命中。
				break; // 结束步进。
			}
			stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 判断这一步跨的是哪一侧。
			parallaxTexel += stepNext * sdir; // 前进到下一个像素。
			totalStep += vec2(stepNext) * ardir; // 累加边界距离。
			prevStepHeight = stepHeight; // 记下这一步高度。
			#ifndef OMNI_TERRAIN_PASS
				bool wrapTile = isBlock; // 实体只在用到方块图集时回绕到本图块。
			#else
				bool wrapTile = true; // 地形阶段总是回绕到本图块。
			#endif
			if (wrapTile){ // 先用宏决定是否回绕，再走一条完整的 `if`，避免判断括号被预处理指令切开。
				parallaxTexel = tilesPixelBase + (parallaxTexel & iTextureResolution); // 把像素折回本图块。
			}
			sampleHeight = texelFetch(normals, parallaxTexel, 0).a; // 读新像素的高度。
			sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
		}
		#ifdef OMNI_PARALLAX_SHADOW // 需要自阴影时。
			shadowVector = shadowVector * tbnMat; // 阳光方向转到切线空间。
			float shadow = 1.0; // 阴影透过率从全透开始。
			if (dot(shadowVector, hitNormal) * parallaxShadow > 0.0 && exit){ // 命中的侧面朝向阳光才需要阴影。
				float currHeight = sampleHeight; // 当前高度。
				stepLength = (1.0 - currHeight) / stepDir.z; // 先走到表面顶部。
				vec2 shadowTexelCoord = pixelCoord + stepLength * stepDir.xy; // 到达顶部时的像素坐标。
				ivec2 shadowTexel = ivec2(floor(shadowTexelCoord)); // 取整。
				stepDir = normalize(vec3(shadowVector.xy * OMNI_PARALLAX_DEPTH * textureResolution * 0.25, shadowVector.z)); // 换成沿光方向的前进方向。
				vec2 ardir = abs(1.0 / stepDir.xy); // 每像素的边界距离。
				ivec2 sdir = (floatBitsToInt(stepDir.xy) >> 31) * 2 + 1; // 方向符号。
				totalStep = (vec2(sdir) * (0.5 - (shadowTexelCoord - shadowTexel)) + 0.5) * ardir; // 到下一像素边界的距离。
				stepNext = ivec2(0); // 复位跨步方向。
				for (int i = 0; i < OMNI_PARALLAX_SHADOW_QUALITY; i++){ // 沿光方向逐像素找遮挡。
					stepLength = min(totalStep.x, totalStep.y); // 先碰到的边界。
					stepHeight = currHeight + stepLength * stepDir.z; // 这一步的高度。
					stepNext = (floatBitsToInt(vec2(stepLength) - totalStep) >> 31) + 1; // 跨哪一侧。
					shadowTexel += stepNext * sdir; // 前进到下一个像素。
					totalStep += vec2(stepNext) * ardir; // 累加边界距离。
					#ifndef OMNI_TERRAIN_PASS
						bool wrapTile = isBlock; // 实体只在用到方块图集时回绕。
					#else
						bool wrapTile = true; // 地形阶段总是回绕。
					#endif
					if (wrapTile){ // 先用宏决定是否回绕，再走一条完整的 `if`。
						shadowTexel = tilesPixelBase + (shadowTexel & iTextureResolution); // 折回本图块。
					}
					sampleHeight = texelFetch(normals, shadowTexel, 0).a; // 读高度。
					sampleHeight += saturate(1.0 - sampleHeight * 1e20); // 高度为零时补成完整高度。
					if (sampleHeight > stepHeight){ // 表面高过光线，说明被遮挡。
						parallaxShadow = 0.0; // 直接判为阴影。
						break; // 结束。
					}
				}
				#ifdef OMNI_PARALLAX_FADE
					parallaxShadow *= mix(1.0, shadow, fade); // 远处淡出阴影。
				#else
					parallaxShadow *= shadow; // 否则原样。
				#endif
			}
		#endif
	#if OMNI_PARALLAX_BASED_NORMAL == 1 // 仅侧面：只有命中侧面时才用视差法线。
		#ifdef OMNI_PARALLAX_FADE
			hitNormal = mix(DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb), hitNormal, fade * (1.0 - hitNormal.z)); // 远处淡出到贴图法线。
		#else
			if (hitNormal.z == 1.0) hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中侧面时用贴图法线。
		#endif
		}else{
			hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 没命中时直接用贴图法线。
	#elif OMNI_PARALLAX_BASED_NORMAL == 2 && defined OMNI_PARALLAX_FADE
		hitNormal = mix(vec3(0.0, 0.0, 1.0), hitNormal, fade); // 全部用视差法线时，远处淡出到朝外法线。
	#endif
	}
	#if OMNI_PARALLAX_BASED_NORMAL == 0 // 不用视差法线时一律取贴图法线。
		hitNormal = DecodeNormalTex(texelFetch(normals, parallaxTexel, 0).rgb); // 解出切线空间法线。
	#endif
	return parallaxTexel; // 交回最终采样像素。
}
#endif // 平滑与锐利两种视差结束。
#endif // 几何片元视差段结束。
#endif // 文件守卫结束。
