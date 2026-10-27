/*
效果文件 `effects/ground/material.glsl`：材质与视差的选项、资源包解码、G 缓冲读取和阶段入口集中在这里。
调用位置：地形、实体、方块、手、蜘蛛眼与合成阶段按需引用；菜单由 options.py 扫描本文件生成。
可复制示例：`Material material = MaterialFromTex(albedo, specTex, wet);` 与 `GbufferData data = GetGbufferData();`。
设计原因与取舍：材质解码与视差属于同一个地表效果，放在一处才能一起修改；G 缓冲通道解释仍由 `bind/gbuffer.glsl` 提供。
*/
#ifndef OMNI_EFFECT_GROUND_MATERIAL_INCLUDED
#define OMNI_EFFECT_GROUND_MATERIAL_INCLUDED
// @effect {"label":{"zh_cn":"材质与视差","en_us":"Textures & parallax"}}
// @option {"label":{"zh_cn":"方块纹理分辨率","en_us":"Block Texture Resolution"},"description":{"zh_cn":"必须等于资源包方块贴图的分辨率，零表示自动。错误的值会让方块视差错位。","en_us":"Must match the resource pack block texture resolution; zero means auto. A wrong value breaks parallax."}}
#define OMNI_TEXTURE_RESOLUTION 0 // [0 1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"实体纹理分辨率","en_us":"Entity Texture Resolution"},"description":{"zh_cn":"实体视差用的纹理分辨率，必须与资源包一致，否则实体会错位。","en_us":"Texture resolution for entity parallax; must match the pack or entities break."}}
#define OMNI_ENTITIES_TEXTURE_RESOLUTION 16 // [1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192]
// @option {"label":{"zh_cn":"各向异性过滤","en_us":"Anisotropic Filtering"},"description":{"zh_cn":"让倾斜的表面更清晰；开启视差时会被禁用。","en_us":"Sharper textures on tilted surfaces; disabled while parallax is on."},"values":{"0":{"zh_cn":"关","en_us":"off"},"2":{"zh_cn":"2x","en_us":"2x"},"4":{"zh_cn":"4x","en_us":"4x"},"8":{"zh_cn":"8x","en_us":"8x"},"16":{"zh_cn":"16x","en_us":"16x"}}}
#define OMNI_ANISOTROPIC_FILTERING_QUALITY 4 // [0 2 4 8 16]
// @option {"label":{"zh_cn":"法线高光也过滤","en_us":"Filter Normal & Specular"},"description":{"zh_cn":"把各向异性过滤也用在法线与高光贴图上，代价略高但更清晰。","en_us":"Applies anisotropic filtering to the normal and specular maps too."}}
//#define OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR
// @option {"label":{"zh_cn":"实体凹凸","en_us":"Entity Parallax"},"description":{"zh_cn":"给实体也做视差；需要先正确设置实体纹理分辨率。","en_us":"Enables parallax on entities; set the entity texture resolution first."}}
#define OMNI_ENTITIES_PARALLAX 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸模式","en_us":"Parallax Mode"},"description":{"zh_cn":"关、锐利或平滑；锐利保持像素外观，平滑更少锯齿。","en_us":"Off, Sharp or Smooth; Sharp keeps the pixel look, Smooth has fewer artifacts."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"锐利","en_us":"Sharp"},"2":{"zh_cn":"平滑","en_us":"Smooth"}}}
#define OMNI_PARALLAX_MODE 0 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸采样质量","en_us":"Parallax Quality"},"description":{"zh_cn":"锐利模式决定视差范围，平滑模式决定伪影多少，越大越细也越慢。","en_us":"Sharp sets the parallax range, Smooth sets artifact level; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_QUALITY 40 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"凹凸细化步数","en_us":"Parallax Refinements"},"description":{"zh_cn":"平滑视差找到交点后再二分细化的次数，越大边缘越准也越慢。","en_us":"Bisection steps after the parallax hit in Smooth mode; higher is more accurate and slower."},"slider":true}
#define OMNI_PARALLAX_MAX_REFINEMENTS 12 // [0 2 4 6 8 12 16]
// @option {"label":{"zh_cn":"凹凸阴影","en_us":"Parallax Self Shadow"},"description":{"zh_cn":"让视差像素自己也投出阳光阴影，代价很低。","en_us":"Lets parallax pixels cast their own sunlight shadow; cheap."}}
#define OMNI_PARALLAX_SHADOW 1 // [0 1]
// @option {"label":{"zh_cn":"凹凸阴影质量","en_us":"Self Shadow Quality"},"description":{"zh_cn":"视差阴影的采样数，越大越细也越慢。","en_us":"Sample count for the parallax shadow; higher is finer and slower."},"slider":true}
#define OMNI_PARALLAX_SHADOW_QUALITY 20 // [10 15 20 30 40 60 80 100 150 200 300 500]
// @option {"label":{"zh_cn":"由凹凸生成法线","en_us":"Parallax Based Normal"},"description":{"zh_cn":"让法线效果与视差一致；平滑模式只对侧面生效。","en_us":"Keeps normals consistent with parallax; Smooth only affects sides."},"values":{"0":{"zh_cn":"关","en_us":"off"},"1":{"zh_cn":"仅侧面","en_us":"Side Only"},"2":{"zh_cn":"全部","en_us":"All"}}}
#define OMNI_PARALLAX_BASED_NORMAL 1 // [0 1 2]
// @option {"label":{"zh_cn":"凹凸深度","en_us":"Parallax Depth"},"description":{"zh_cn":"凹凸看起来多深，单位是方块高度。","en_us":"How deep surfaces appear, in block heights."},"slider":true}
#define OMNI_PARALLAX_DEPTH 1.0 // [0.1 0.15 0.2 0.3 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 5.0 7.5 10.0]
// @option {"label":{"zh_cn":"凹凸淡出","en_us":"Parallax Fade"},"description":{"zh_cn":"纹理像素很小时淡出视差，避免远处闪烁；不建议关闭。","en_us":"Fades parallax when texels get tiny, avoiding shimmer; better kept on."}}
#define OMNI_PARALLAX_FADE
// @option {"label":{"zh_cn":"启用 PBR","en_us":"Enable PBR"},"description":{"zh_cn":"使用 labPBR 资源包的表面贴图；关闭后下面这些材质效果全部停用。","en_us":"Uses labPBR surface maps; turning it off disables all the material effects below."}}
#define OMNI_ENABLE_PBR
// @option {"label":{"zh_cn":"PBR 标准类型","en_us":"PBR Format"},"description":{"zh_cn":"资源包用的是 labPBR 还是另一种表面贴图编码。","en_us":"Whether the pack stores labPBR or PTGI surface data."},"values":{"0":{"zh_cn":"labPBR","en_us":"labPBR"},"2":{"zh_cn":"PTGI","en_us":"PTGI"}}}
#define OMNI_TEXTURE_PBR_FORMAT 0 // [0 2]
// @option {"label":{"zh_cn":"限制最大粗糙度","en_us":"Clamp High Roughness"},"description":{"zh_cn":"把高粗糙表面的反射直接屏蔽，省性能。","en_us":"Skips reflections on very rough surfaces to save performance."}}
#define OMNI_ROUGHNESS_CLAMP 1 // [0 1]
// @option {"label":{"zh_cn":"限制方块法线强度","en_us":"Terrain Normal Clamp"},"description":{"zh_cn":"压住方块的极端法线，减少噪点。","en_us":"Limits extreme terrain normals to reduce noise."}}
//#define OMNI_TERRAIN_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制手部法线强度","en_us":"Hand Normal Clamp"},"description":{"zh_cn":"压住手持物的极端法线，减少噪点。","en_us":"Limits extreme hand normals to reduce noise."}}
#define OMNI_HAND_NORMAL_CLAMP
// @option {"label":{"zh_cn":"限制实体法线强度","en_us":"Entity Normal Clamp"},"description":{"zh_cn":"压住实体的极端法线，减少噪点。","en_us":"Limits extreme entity normals to reduce noise."}}
#define OMNI_ENTITIES_NORMAL_CLAMP
// --- 资源包法线的整体强度与材质遮蔽：来源 Eclipse `lib/settings.glsl:371-376`、`dimensions/all_solid.fsh:743-752` ---
// 这一组默认不改变画面：材质遮蔽默认关闭，法线倍率默认一倍与资源包期望一致。
// @option {"label":{"zh_cn":"材质缝隙暗部","en_us":"Material Ambient Occlusion"},"description":{"zh_cn":"用资源包法线贴图的蓝通道当作遮蔽，压暗凹陷处的底色；默认关闭，关闭时画面不变。","en_us":"Uses the resource pack normal map's blue channel as occlusion to darken cavities; off by default so the current look is unchanged."}}
#define OMNI_MATERIAL_AO 0 // [0 1]
// @option {"label":{"zh_cn":"表面纹理强度","en_us":"Normal Map Strength"},"description":{"zh_cn":"资源包法线贴图的整体起伏倍率，一倍为资源包期望的原始强度；默认一倍，画面不变。","en_us":"Overall relief multiplier for resource pack normal maps; 1 is the value packs expect; default 1 leaves the current look unchanged."},"slider":true}
#define OMNI_NORMAL_MAP_MULT 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"透光强度","en_us":"SSS Strength"},"description":{"zh_cn":"光照穿透表面的深度倍率，与偏移一起为零时关闭次表面散射。","en_us":"Depth multiplier of light through the surface; with the offset at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"透光偏移","en_us":"SSS Strength Offset"},"description":{"zh_cn":"给穿透深度一个最小值；与倍率一起为零时关闭次表面散射。","en_us":"Minimum value for the light depth; with the multiplier at zero it disables SSS."},"slider":true}
#define OMNI_SSS_STRENGTH_OFFSET 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"发光曲线","en_us":"Emissive Gamma"},"description":{"zh_cn":"PBR 自发光的亮暗对比强度，越大反差越明显。","en_us":"Contrast curve of PBR emissiveness; higher is more contrast."},"slider":true}
#define OMNI_EMISSIVENESS_GAMMA 2.2 // [1.0 1.2 1.4 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"labPBR 孔隙率","en_us":"labPBR Porosity"},"description":{"zh_cn":"使用资源包里的孔隙率通道，决定表面多容易积水。","en_us":"Uses the porosity channel so the surface can puddle more or less."}}
#define OMNI_TEXTURE_PBR_POROSITY 0 // [0 1]
// @option {"label":{"zh_cn":"默认孔隙率","en_us":"Default Porosity"},"description":{"zh_cn":"资源包不给孔隙率时用的值，越小越不吸水、水洼越明显。","en_us":"Porosity when the pack has none; lower means less absorbent and more puddles."},"slider":true}
#define OMNI_TEXTURE_DEFAULT_POROSITY 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"潮湿反照吸收","en_us":"Wetness Albedo Absorption"},"description":{"zh_cn":"潮湿表面压暗的强度，孔隙率越大越明显。","en_us":"How much wet surfaces darken; stronger with higher porosity."},"slider":true}
#define OMNI_POROSITY_ABSORPTION 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"禁用手部高光","en_us":"Disable Hand Specular"},"description":{"zh_cn":"去掉手持物的高光，解决某些模组下的反射噪点。","en_us":"Removes held item specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_HAND_SPECULAR
// @option {"label":{"zh_cn":"禁用玩家高光","en_us":"Disable Player Specular"},"description":{"zh_cn":"去掉玩家自身的高光，解决某些模组下的反射噪点。","en_us":"Removes the player's own specular, fixing reflection noise with some mods."}}
//#define OMNI_DISABLE_PLAYER_SPECULAR
// @option {"label":{"zh_cn":"实体顶点法线平滑","en_us":"Entity Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供实体顶点切线与法线，代价很低。","en_us":"Provides entity vertex tangents and normals for some mods; cheap."}}
#define OMNI_ENTITIES_VS_TBN 1 // [0 1]
// @option {"label":{"zh_cn":"方块顶点法线平滑","en_us":"Block Vertex Normal Smoothing"},"description":{"zh_cn":"为某些模组提供方块顶点切线与法线，代价很低。","en_us":"Provides block vertex tangents and normals for some mods; cheap."}}
//#define OMNI_TERRAIN_VS_TBN
// @option {"label":{"zh_cn":"未指定方块按植物处理","en_us":"General Grass Fix"},"description":{"zh_cn":"把倾斜的面都当成植物渲染，可能误伤其他方块。","en_us":"Treats tilted faces as plants; may misfire on other blocks."}}
#define OMNI_GENERAL_GRASS_FIX 0 // [0 1]
// @option {"label":{"zh_cn":"白色调试世界","en_us":"White Debug World"},"page":"about","description":{"zh_cn":"把所有几何的底色改写成纯白，用来检查光照与几何；仅供调试。","en_us":"Rewrites every geometry albedo to plain white for checking lighting and geometry; debug only."}}
//#define OMNI_WHITE_DEBUG_WORLD

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
材质：把资源包的底色、法线、表面三张贴图解码成光照要用的表面数据，并保留原调用名转发绑定层。
来源：照 iterationT `Lib/GbufferData.glsl` 移植；视差取自 `Lib/IndividualFounctions/Parallax.glsl`，算法放在同目录的 `parallax.glsl`。
  `MaterialFromTex` 解码 labPBR 表面；`GetGbufferData` 从各号画面读回世界表面；`CalculateMasks` 把材质编号
  转成一堆零一掩码；`FixParticleMask`、`ApplyMaterial` 修补粒子与水玻璃冰。
  G 缓冲读取、材质编号、掩码与手部/实体判断的实现都在 `bind/gbuffer.glsl`，本文件只保留选项与 PBR 解码。
调用位置：
  合成阶段片元：`GbufferData gbuffer = GetGbufferData();` 后接 `CalculateMasks`、`FixParticleMask`、`ApplyMaterial`；
  几何阶段片元：地形、实体、方块、手、蜘蛛眼要视差时，用本文件末尾引入的 `ParallaxOcclusionMapping`；
  几何阶段顶点：地形与实体的顶点着色器读材质编号判定、法线平滑与草地修正选项。
可复制示例：
  `GbufferData gbuffer = GetGbufferData();`
  `MaterialMask mask = CalculateMasks(gbuffer.materialIDW);`
调用前提（iterationT 原样保留）：
  `GetGbufferData` 依赖调用方先声明整数像素坐标 `texelCoord`，并已引入画面与深度声明。
设计原因与取舍：
  材质编号 `MATID_*` 在 `bind/gbuffer.glsl`，粒子修正开关 `CORRECT_PARTICLE_NORMAL` 留在本文件；进菜单的选项只列在下方 `@option`。
  视差算法拆到 `effects/ground/parallax.glsl`：搜 `parallax` 就能直接找到算法主体，本文件末尾显式引入，
  原有调用点（地形、实体等）不用改。
  视差选项（`OMNI_PARALLAX_MODE` 等）与纹理分辨率、各向异性过滤一起留在本文件：合成阶段（`composite.glsl`）
  靠引入本文件读这些采样参数，它们本就是“地表纹理怎么采样”的设置，和材质采样参数放一起才不会散落。
  读回段用阶段宏包住：`GetGbufferData` 需要调用方声明的 `texelCoord`，这个全局量只出现在合成阶段；
  原程序靠“只有对应阶段引入对应文件”达到同样限制，这里显式写清阶段条件。
*/
// 材质编号 `MATID_*` 已移到 `bind/gbuffer.glsl`，几何与合成阶段仍从本文件拿到同一套名字。
// 内部常数：粒子法线修正开关。iterationT 原文声明了它但源码里没有引用，按合同原样保留在这里。
#define CORRECT_PARTICLE_NORMAL
// 解码、掩码与视差都用到共用数学，先引入加载器输入与共用计算。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 方块光曲线、材质法线与遮蔽算法放在通用库；这里只传入选项值。
#include "/gfx/surface.glsl"
// G 缓冲读取、材质编号、掩码与手部判断在绑定层，本文件只保留材质选项与 PBR 解码。
#include "/bind/gbuffer.glsl"
// --- 几何结构：射线、平面与求交结果，供屏幕空间反射等使用 ---
// 表面材质与 G 缓冲结构在 `bind/gbuffer.glsl`，本文件只负责按选项解码材质。
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
// 固定材质（空气、水、玻璃、冰）在 `bind/gbuffer.glsl`，与本文件共用同一套定义。
// 湿面反射锐度是材质解码的输入参数，选项定义在效果层，这里按输入读取一次。
#include "/effects/water/puddle.glsl"
// 从表面贴图解出材质：孔隙率、金属、自发光与散射的通道解释在绑定层，本文件只把选项接进去。
// 参数 `wet` 是这一处的湿润度，`baseTex` 会被吸水压暗，所以是 `inout`。
Material MaterialFromTex(inout vec3 baseTex, vec4 specTex, float wet){
	return bind_material_from_tex(baseTex, specTex, wet, bool(OMNI_TEXTURE_PBR_POROSITY), OMNI_TEXTURE_PBR_FORMAT,
		OMNI_TEXTURE_DEFAULT_POROSITY, OMNI_POROSITY_ABSORPTION, bool(OMNI_ROUGHNESS_CLAMP), OMNI_EMISSIVENESS_GAMMA,
		OMNI_SSS_STRENGTH, OMNI_SSS_STRENGTH_OFFSET, OMNI_PUDDLE_REFLECTION_SHARPNESS); // 解码公式在绑定层。
}
// 从各号画面读回一个像素的完整表面数据，供合成阶段使用。
// 调用前提：调用方必须先声明整数像素坐标 `texelCoord`。
#if defined OMNI_COMPOSITE0_PASS || defined OMNI_COMPOSITE1_PASS || defined OMNI_COMPOSITE2_PASS || defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS || defined OMNI_COMPOSITE5_PASS
GbufferData GetGbufferData(){
	GbufferData data = bind_gbuffer(texelCoord, colortex0, colortex3, colortex4, colortex5, colortex6, depthtex1, depthtex0); // 画面通道含义在绑定层解释。
	#ifdef OMNI_ENABLE_PBR // 开启物理光照时才解材质，否则当作空气。
		data.material = MaterialFromTex(data.albedo, data.specTex, data.wet); // 解出材质，同时压暗吸水底色。
		#if MC_VERSION < 11605
			data.material.reflectionStrength *= float(bind_is_world_depth(data.depthW)); // 旧版没有单独的半透明深度，天空像素不该反射。
		#endif
	#else
		data.material = airMaterial; // 关闭物理光照时统一按空气处理。
	#endif
	return data; // 交回读回的数据。
}
#endif // 合成阶段读回段结束。
// --- 材质掩码：实现与手部/实体判断都在绑定层，这里保留原调用名做一次转发 ---
MaterialMask CalculateMasks(float materialIDs){
	return bind_material_mask(materialIDs); // 材质编号到类别在绑定层解释。
}
// 粒子修正并带深度：粒子很薄，读回时会落到后面的几何上，所以把半透明层也标记成粒子并借用不透明深度。
void FixParticleMask(inout MaterialMask solidMask, inout MaterialMask mask, inout float depthL, in float depthW){
	bind_fix_particle_mask(solidMask, mask, depthL, depthW); // 修正规则在绑定层。
}
// 粒子修正：同上，但不改深度，供不需要深度的阶段使用。
void FixParticleMask(inout MaterialMask solidMask, inout MaterialMask mask){
	bind_fix_particle_mask(solidMask, mask); // 修正规则在绑定层。
}
// 用固定材质覆盖解码材质：水、染色玻璃与冰用写死的参数，并标记为光滑面。
void ApplyMaterial(inout Material material, in MaterialMask mask, inout bool isSmooth){
	bind_apply_material(material, mask, isSmooth); // 固定材质在绑定层。
}
// 资源包材质处理：把法线贴图的原始颜色解成切线空间法线，并按选项缩放起伏、导出材质遮蔽。
// 对应 Eclipse `dimensions/all_solid.fsh:204-210`（`applyBump` 里的 `NORMAL_MAP_MULT`）与 `:743-745`（`MATERIAL_AO`）。
// 为什么单独成一个函数：几何阶段（地形、实体、方块、手）都要在同一处对法线做这两步，
//   合并成一个纯函数，每个调用点只把现有 `DecodeNormalTex` 换成它，避免各写一份倍率与遮蔽。
// 为什么仍复用 `common/math.glsl` 的 `DecodeNormalTex`：那是全项目唯一的法线解码口径，另起一份会与别处不一致。
// 返回值：`xyz` 是单位切线空间法线；`w` 是可乘到底色上的遮蔽系数，未开材质遮蔽时恒为一。
// 材质遮蔽：资源包把遮蔽存在法线贴图的蓝通道，取出来乘到底色上；未开该选项时恒为一。
// 为什么单独拆出来：视差路径已经自己解出法线，只差遮蔽要另外取一次贴图，拆开才能单独复用。
float omniMaterialAO(vec3 normalTexRGB){
	return gfx_material_ao(normalTexRGB, bool(OMNI_MATERIAL_AO)); // 选项决定是否启用遮蔽。
}
// 法线倍率：围绕朝外方向缩放起伏，`OMNI_NORMAL_MAP_MULT` 越大起伏越强；为一等于原样。
// 传入的已经是切线空间单位法线，所以视差路径解出的法线也能直接套用，不必重采贴图。
vec3 omniMaterialNormalScale(vec3 tangentNormal){
	return gfx_material_normal_scale(tangentNormal, OMNI_NORMAL_MAP_MULT); // 倍率由选项传入。
}
vec4 omniMaterialNormal(vec3 normalTexRGB){
	return gfx_material_normal(normalTexRGB, bool(OMNI_MATERIAL_AO), OMNI_NORMAL_MAP_MULT); // 解码、缩放与遮蔽一次完成。
}
// 视差由使用它的几何阶段显式引入，本文件只提供材质解码与选项，不反向依赖渲染层。
#endif // OMNI_EFFECT_GROUND_MATERIAL_INCLUDED
