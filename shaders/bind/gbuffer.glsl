/*
G 缓冲绑定：把 Minecraft 的材质编号、G 缓冲画面与深度读成普通结构体，并提供材质掩码与手部判断。
调用位置：`effects/ground/material.glsl` 在本文件之上保留材质选项与 PBR 解码；需要读回表面的效果都经该文件拿到这些结构。
可复制示例：
    `GbufferData gbuffer = bind_gbuffer(texelCoord);`
    `MaterialMask mask = bind_material_mask(gbuffer.materialIDW);`
    `if (bind_is_hand_depth(depth)) ...`
设计原因与取舍：画面编号、打包方式与材质编号是 Minecraft 侧的约定，集中放在绑定层；
  通用库和效果层都不再自己解释 `colortex` 的通道含义。材质编号仍按 iterationT 原值，保持与几何阶段一致。
  手部与玩家判断也在这里给出，避免每个效果各写一份深度阈值与编号比较。
*/
#ifndef OMNI_BIND_GBUFFER_INCLUDED
#define OMNI_BIND_GBUFFER_INCLUDED

// 读画面与解码法线都要用共用数学，绑定层自己保证引入顺序。
#include "/common/math.glsl"
#include "/omni-gfx/surface.glsl"
// 延迟缓冲的材质编号表与掩码解码在通用库，绑定层只保留 Minecraft 侧的编号。
#include "/omni-gfx/gbuffer.glsl"
// 湿面粗糙度与吸水暗化用通用库的水面公式。
#include "/omni-gfx/water.glsl"

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

// 每次采样的表面材质参数：粗糙、金属、菲涅尔零点、自发光、散射与反射强度。
struct Material{
	float roughness; // 粗糙度，越大高光越散。
	float metalness; // 金属度，越大底色越偏反射。
	float f0; // 表面正射反射率，金属接近底色、非金属约零点零四。
	float emissiveness; // 自发光强度。
	float scattering; // 次表面散射强度。
	float reflectionStrength; // 这份表面允许反射的强度。
};
// 一个像素读回的完整表面数据：底色、法线、深度、光照图、材质编号、表面贴图与材质参数。
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
	vec4 specTex; // 五号画面解包后的表面贴图，供效果层按 PBR 格式解码。
	float wet; // 湿润度，供效果层压暗吸水底色。
	Material material; // 解码后的材质参数，由效果层填入。
};
// 空气材质：不做反射、粗糙度为一。
const Material airMaterial = Material(1.0, 0.0, 0.0, 0.0, 0.0, 0.0);
// 水材质：光滑强反射。
const Material material_water = Material(0.0, 0.0, 0.02, 0.0, 0.0, 1.0);
// 玻璃材质：比水略高的固定反射率。
const Material material_glass = Material(0.0, 0.0, 0.042, 0.0, 0.0, 1.0);
// 冰材质：反射率介于水与玻璃之间。
const Material material_ice = Material(0.0, 0.0, 0.018, 0.0, 0.0, 1.0);

// 读回一个像素的完整表面数据；画面与深度采样器由调用方传入，纹理通道的含义只在这里解释一次。
GbufferData bind_gbuffer(ivec2 texel, sampler2D albedo_tex, sampler2D normal_light_translucent_tex,
		sampler2D normal_light_tex, sampler2D specular_tex, sampler2D translucent_tex,
		sampler2D depth_translucent_tex, sampler2D depth_opaque_tex){
	GbufferData data; // 逐项填入。
	// 通道解码与天光曲线在通用库；这里只把绑定层自己的纹理名传进去。
	OgxGbufferData raw = ogxGetGbufferData(albedo_tex, normal_light_translucent_tex, normal_light_tex, specular_tex,
		translucent_tex, depth_translucent_tex, depth_opaque_tex, texel, false, false, 0, 0.0, 1.0, false,
		1.0, 0.0, 0.0, 0.0, false);
	data.albedo = raw.albedo; // 不透明底色，已转线性。
	data.albedoW = raw.albedoW; // 半透明底色与透明度。
	data.normalL = raw.normalL; // 半透明层法线。
	data.normalW = raw.normalW; // 不透明层法线。
	data.depthL = raw.depthL; // 半透明层深度。
	data.depthW = raw.depthW; // 不透明层深度。
	data.lightmapL = raw.lightmapL; // 半透明层光照图。
	data.lightmapW = raw.lightmapW; // 不透明层光照图。
	data.materialIDL = raw.materialIDL; // 半透明层材质编号。
	data.materialIDW = raw.materialIDW; // 不透明层材质编号。
	data.waterMask = raw.waterMask; // 水遮罩。
	data.rainAlpha = raw.rainAlpha; // 雨雪遮罩。
	data.parallaxShadow = raw.parallaxShadow; // 视差自阴影。
	data.specTex = raw.specTex; // 表面贴图与通用库共用同一次读取，不再重复采样。
	data.wet = raw.wet; // 湿润度同样来自那次读取。
	return data; // 交回读回的数据。
}

// 材质掩码：一份掩码里每个字段都是零或一，表示这个像素属于某类材质。
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

// 材质编号转类别：画面里存的是编号除以二百五十五，先还原再逐项比对。
MaterialMask bind_material_mask(float material_ids){
	material_ids = floor(material_ids * 255.0); // 先还原成整数编号。
	MaterialMask mask; // 逐项填入。
	mask.sky = float(material_ids == MATID_SKY); // 天空。
	mask.land = float(material_ids == MATID_LAND); // 普通方块。
	mask.grass = float(material_ids == MATID_GRASS || material_ids == MATID_BEACON_BEAM); // 草，信标光柱也当作草处理。
	mask.leaves = float(material_ids == MATID_LEAVES); // 树叶。
	mask.hand = float(material_ids == MATID_HAND); // 手持物。
	mask.water = float(material_ids == MATID_WATER); // 水。
	mask.stainedGlass = float(material_ids == MATID_STAINEDGLASS); // 染色玻璃。
	mask.ice = float(material_ids == MATID_ICE); // 冰。
	mask.entityPlayer = float(material_ids == MATID_ENTITIES_PLAYER); // 玩家。
	mask.entitiesLitHigh = float(material_ids == MATID_ENTITIES_LIT_HIGH || material_ids == MATID_BEACON_BEAM); // 高亮实体。
	mask.entitiesLitMedium = float(material_ids == MATID_ENTITIES_LIT_MEDIUM); // 中亮实体。
	mask.entitiesLitLow = float(material_ids == MATID_ENTITIES_LIT_LOW); // 低亮实体。
	mask.entitiesSnow = float(material_ids == MATID_ENTITIES_SNOW || material_ids == MATID_BEACON_BEAM); // 实体雪层。
	mask.lightning = float(material_ids == MATID_LIGHTNING); // 闪电。
	mask.torch = float(material_ids == MATID_TORCH); // 火把。
	mask.lava = float(material_ids == MATID_LAVA); // 岩浆。
	mask.glowstone = float(material_ids == MATID_GLOWSTONE); // 荧石。
	mask.fire = float(material_ids == MATID_FIRE); // 火。
	mask.redstoneTorch = float(material_ids == MATID_REDSTONE_TORCH); // 红石火把。
	mask.redstone = float(material_ids == MATID_REDSTONE); // 红石线。
	mask.soulFire = float(material_ids == MATID_SOULFIRE); // 灵魂火。
	mask.amethyst = float(material_ids == MATID_AMETHYST); // 紫水晶。
	mask.oxidizedBulb = float(material_ids == MATID_OXIDIZED_BULB); // 氧化铜灯。
	mask.particle = float(material_ids == MATID_PARTICLE); // 普通粒子。
	mask.particlelit = float(material_ids == MATID_PARTICLE_LIT); // 受光粒子。
	mask.endPortal = float(material_ids == MATID_END_PORTAL); // 末地传送门。
	mask.selection = float(material_ids == MATID_SELECTION); // 选择框。
	return mask; // 交回掩码。
}

// 手部材质编号：输入是已经还原成整数编号的材质值。
bool bind_is_hand_id(float material_id){ return material_id == MATID_HAND; }
// 玩家材质编号：输入是已经还原成整数编号的材质值。
bool bind_is_player_id(float material_id){ return material_id == MATID_ENTITIES_PLAYER; }
// 手部固定深度：小于零点七的像素是手，运动模糊与重投影共用这一条。
bool bind_is_hand_depth(float depth){ return depth < 0.7; }
// 世界表面深度：大于等于零点七的像素才按世界几何处理。
bool bind_is_world_depth(float depth){ return depth >= 0.7; }

// 粒子修正并带深度：粒子很薄，读回时会落到后面的几何上，所以把半透明层也标记成粒子并借用不透明深度。
void bind_fix_particle_mask(inout MaterialMask solid_mask, inout MaterialMask mask, inout float depthL, float depthW){
	#if MC_VERSION >= 11500 // 一点一五以后粒子单独一层，才需要这份修正。
	if (solid_mask.particle > 0.5 || solid_mask.particlelit > 0.5){ // 不透明层出现粒子才修正。
		mask.particle = 1.0; // 半透明层也当作粒子。
		mask.water = 0.0; // 粒子不是水。
		mask.stainedGlass = 0.0; // 也不是玻璃。
		mask.ice = 0.0; // 也不是冰。
		mask.sky = 0.0; // 也不是天空。
		depthL = depthW; // 深度改用不透明层，避免粒子读到自己后面的方块。
	}
	#endif
}
// 粒子修正：同上，但不改深度，供不需要深度的阶段使用。
void bind_fix_particle_mask(inout MaterialMask solid_mask, inout MaterialMask mask){
	#if MC_VERSION >= 11500 // 同样只在一点一五以后生效。
	if (solid_mask.particle > 0.5 || solid_mask.particlelit > 0.5){ // 不透明层出现粒子才修正。
		mask.particle = 1.0; // 半透明层也当作粒子。
		mask.water = 0.0; // 粒子不是水。
		mask.stainedGlass = 0.0; // 也不是玻璃。
		mask.ice = 0.0; // 也不是冰。
		mask.sky = 0.0; // 也不是天空。
	}
	#endif
}
// 用固定材质覆盖解码材质：水、染色玻璃与冰用写死的参数，并标记为光滑面。
void bind_apply_material(inout Material material, in MaterialMask mask, inout bool is_smooth){
	if (mask.water > 0.5){ // 水。
		material = material_water; // 换成水材质。
		is_smooth = true; // 标记为光滑。
	}
	if (mask.stainedGlass > 0.5){ // 染色玻璃。
		material = material_glass; // 换成玻璃材质。
		is_smooth = true; // 标记为光滑。
	}
	if (mask.ice > 0.5){ // 冰。
		material = material_ice; // 换成冰材质。
		is_smooth = true; // 标记为光滑。
	}
}

// 从 G 缓冲的表面贴图解出材质：孔隙率决定吸水压暗，其余通道解出粗糙、金属、自发光与散射。
// 所有格式与画质选项都由效果层传入，绑定层只按给定参数解释通道。
Material bind_material_from_tex(inout vec3 base_tex, vec4 spec_tex, float wet,
		bool use_porosity, int pbr_format, float default_porosity, float porosity_absorption,
		bool roughness_clamp, float emissiveness_gamma, float sss_strength, float sss_offset,
		float puddle_sharpness){
	OgxPbrMaterial decoded = ogxPbrMaterialFromTex(base_tex, spec_tex, wet, use_porosity, pbr_format,
		default_porosity, porosity_absorption, roughness_clamp, emissiveness_gamma, sss_strength, sss_offset,
		puddle_sharpness); // 解码在通用库，底色吸水压暗由输入输出参数带回。
	Material material; // 转成光影包沿用的结构体。
	material.roughness = decoded.roughness;
	material.metalness = decoded.metalness;
	material.f0 = decoded.f0;
	material.emissiveness = decoded.emissiveness;
	material.scattering = decoded.scattering;
	material.reflectionStrength = decoded.reflectionStrength;
	return material; // 交回解码好的材质。
}
#endif
