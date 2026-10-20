/*
通用图形库表面模块：方块光曲线、材质法线、遮蔽换算与自发光。
调用位置：任何需要把方块光等级、法线贴图和材质遮蔽变成光照输入，或按贴图色算自发光的程序；
    本仓库由 `effects/ground/material.glsl` 与 `effects/lighting/emissive.glsl` 转发调用。
可复制示例：
    float c = gfx_curve_block_light_sky(blockLight); // 天光等级曲线。
    vec3 n = gfx_material_normal_scale(tangentNormal, 1.0); // 法线起伏倍率。
    vec4 m = gfx_material_normal(normalTexRGB, true, 1.0); // 法线加遮蔽。
    float e = gfx_ore_emission(albedo); // 矿石发光。
设计原因与取舍：
    选项值由调用方作为参数传入，库不读取任何 `OMNI_*` 宏。
    曲线常数照 iterationT 与 Eclipse 原程序保留，迁移只改名字与参数位置。
*/
#ifndef GFX_SURFACE_INCLUDED
#define GFX_SURFACE_INCLUDED

#include "/gfx/math.glsl"

// 天光曲线：先抬高低等级，再压暗高等级，等级越高越接近饱和。
float gfx_curve_block_light_sky(float blockLight){
	blockLight = 1.0 - pow(1.0 - blockLight * 0.9, 0.7); // 抬高低等级并保留低端细节。
	blockLight = clamp(blockLight * blockLight * blockLight * 1.95, 0.0, 1.0); // 三次方拉开对比后夹紧。
	return blockLight;
}

// 方块光曲线：按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float gfx_curve_block_light_torch(float blockLight){
	float dist = (1.0 - blockLight) * 15.0 + 1.0; // 把等级转成米制距离。
	dist = dist * dist; // 距离平方，衰减更快。
	float boost = clamp(blockLight * 2.0 - 1.0, 0.0, 1.0); // 只有高等级才有的提升量。
	blockLight = blockLight + boost * boost; // 先加提升，突出光源附近的亮度。
	blockLight /= dist; // 再按距离平方衰减。
	return blockLight;
}

// 材质遮蔽：资源包把遮蔽存在法线贴图蓝通道，启用时映射到零点五到一。
float gfx_material_ao(vec3 normalTexRGB, bool enabled){
	return enabled ? normalTexRGB.b * 0.5 + 0.5 : 1.0; // 未启用时不做任何遮蔽。
}

// 法线倍率：围绕朝外方向缩放起伏，倍率为一时保持原样。
vec3 gfx_material_normal_scale(vec3 tangentNormal, float multiplier){
	return normalize(tangentNormal * multiplier + vec3(0.0, 0.0, 1.0 - multiplier)); // z 补齐后重新单位化。
}

// 一次解出切线空间法线与遮蔽，返回前三个分量为法线、第四个分量为遮蔽。
vec4 gfx_material_normal(vec3 normalTexRGB, bool aoEnabled, float multiplier){
	vec3 normal = gfx_material_normal_scale(gfx_DecodeNormalTex(normalTexRGB), multiplier); // 先解码再缩放。
	return vec4(normal, gfx_material_ao(normalTexRGB, aoEnabled)); // 把遮蔽一起交回。
}

// 方块光：按光等级、遮蔽与光源标记算出火把照亮周围的颜色。
// 为什么先按光等级压低遮蔽：光源附近本身亮，遮蔽不该把那里压黑，所以接近满级时把遮蔽推向全亮。
// 为什么先给光源方块限一个上限等级：发光方块自己贴图上不该出现高亮方块光，限一档避免过曝。
// 参数 `source_mask` 由调用方把各类发光方块与受光实体合成为一个零到一的标记。
vec3 gfx_block_light(float lightmap, vec3 ao, float source_mask, vec3 torch_color, float brightness, bool overworld){
	ao = mix(ao, vec3(1.0), gfx_saturate(lightmap * 5.0 - 4.2)); // 光等级接近满值时遮蔽趋向全亮。
	lightmap = min(lightmap, 1.0 - 0.13 * source_mask); // 光源方块自身把方块光等级压一档。
	lightmap = gfx_curve_block_light_torch(lightmap); // 按距离平方曲线重整等级，得到火把那样集中的光。
	float scale = overworld ? 0.015 : 0.15; // 下界末地没有阳光，常数放大十倍。
	return torch_color * ao * (lightmap * brightness * scale); // 火把光色乘遮蔽与强度。
}

// 纹理自发光：按模式把硬编码发光与资源包发光相加或二选一。
// 参数 `hardcoded_mask` 是调用方按方块类型加权得到的强度，`emissive` 已乘过整体亮度。
// 为什么硬编码发光要乘底色长度：贴图越亮的部位自发光越强，避免暗贴图凭空发光。
vec3 gfx_texture_emissive(vec3 albedo, float emissive, float hardcoded_mask, bool torch_tinted, vec3 torch_color, float torch_brightness,
		float texture_brightness, int mode, bool overworld){
	if (mode == 1){ // 仅资源包：只用自发光强度，不看方块类型。
		float scale = overworld ? 0.01 : 0.1; // 下界末地放大十倍。
		return vec3(emissive * torch_brightness * scale); // 自发光强度乘亮度。
	}
	vec3 lighting_color = torch_tinted ? torch_color : vec3(1.0); // 出现火把类光源才染成火把光色。
	hardcoded_mask *= length(albedo); // 用底色亮度缩放，暗贴图不发光。
	float dark_scale = overworld ? 1.0 : 10.0; // 下界末地的整体倍率。
	if (mode == 2) return lighting_color * (max(hardcoded_mask * texture_brightness, emissive * 0.005) * torch_brightness * dark_scale); // 相加模式取较大者。
	return lighting_color * (hardcoded_mask * texture_brightness * torch_brightness * dark_scale); // 仅硬编码模式。
}

// 矿石发光：鲜艳又明亮的矿物颗粒才发光，灰色石底几乎不亮。
float gfx_ore_emission(vec3 albedo){
	vec3 hsv = gfx_omniRgbToHsv(albedo); // 拆出饱和度与明度。
	return smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5) * 0.5; // 饱和度当门槛，明度拉对比，再乘 Eclipse 的半值。
}

// 纹饰发光：只看明度，越亮的纹路越亮；明度开方让暗纹也保留一部分发光。
float gfx_trim_emission(vec3 albedo){
	vec3 hsv = gfx_omniRgbToHsv(albedo); // 拆出明度。
	return sqrt(hsv.z); // 明度开方，照 Eclipse。
}

#endif
