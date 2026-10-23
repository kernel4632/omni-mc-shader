/*
材质与视差的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/ground/material.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_GROUND_MATERIAL_INCLUDED
#define OMNI_BIND_GROUND_MATERIAL_INCLUDED
#include "/effects/ground/material.glsl"
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
// 水洼的湿面反射锐度（`OmniPuddleRoughness`）在 water/puddle.glsl：粗糙度只在本文件的 `MaterialFromTex` 解出，
// 所以由本文件引入并在那里调用；水洼覆盖（`OmniPuddleCoverage`）仍由水效果自己引入，两边各取所需。
// 为什么放在函数之前：GLSL 要求先声明后使用，放在文件末尾会报找不到函数。
#include "/rendering/water/puddle.glsl"
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
// 视差算法（`ParallaxOcclusionMapping`）在 ground/parallax.glsl：它只服务地表材质，且只在地形、实体等几何片元阶段编译。
// 为什么放在这里引入：任何引入本文件的阶段都靠这一行拿到视差算法，原有调用点（地形、实体）一个都不用改。
#include "/rendering/parallax.glsl"
#endif // OMNI_BIND_GROUND_MATERIAL_INCLUDED
