/*
表面模块适配层：方块光曲线、材质法线、遮蔽换算与自发光已迁到生成库。
调用位置：`rendering/lighting/emissive.glsl` 与地形材质代码引用本文件；
    这些效果层只保留选项与材质判断，算式只在 `omni-gfx/src/surface.slang` 一份。
可复制示例：`vec3 c = gfx_block_light(lightmap, ao, sourceMask, torchColor, 1.0, true);` 火把光，实现在生成库。
设计原因与取舍：函数名与参数顺序保持原样，调用点不需要改动，默认画面不会漂移；
    所有选项值由调用方传入，库不读取任何 `OMNI_*` 宏。
*/
#ifndef GFX_SURFACE_INCLUDED
#define GFX_SURFACE_INCLUDED

// 迁移后的表面实现：方块光、材质法线与自发光。
// 每行只做一次转发，方便对照旧签名与生成库里的实现。
#include "/omni-gfx/surface.glsl"

// 天光曲线：先抬高低等级，再压暗高等级，等级越高越接近饱和。
float gfx_curve_block_light_sky(float blockLight){
	return ogxCurveBlockLightSky(blockLight); // 实现在生成库。
}

// 方块光曲线：按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float gfx_curve_block_light_torch(float blockLight){
	return ogxCurveBlockLightTorch(blockLight); // 实现在生成库。
}

// 材质遮蔽：资源包把遮蔽存在法线贴图蓝通道，启用时映射到零点五到一。
float gfx_material_ao(vec3 normalTexRGB, bool enabled){
	return ogxMaterialAo(normalTexRGB, enabled); // 实现在生成库。
}

// 法线倍率：围绕朝外方向缩放起伏，倍率为一时保持原样。
vec3 gfx_material_normal_scale(vec3 tangentNormal, float multiplier){
	return ogxMaterialNormalScale(tangentNormal, multiplier); // 实现在生成库。
}

// 一次解出切线空间法线与遮蔽，返回前三个分量为法线、第四个分量为遮蔽。
vec4 gfx_material_normal(vec3 normalTexRGB, bool aoEnabled, float multiplier){
	return ogxMaterialNormal(normalTexRGB, aoEnabled, multiplier); // 实现在生成库。
}

// 方块光：按光等级、遮蔽与光源标记算出火把照亮周围的颜色。
vec3 gfx_block_light(float lightmap, vec3 ao, float source_mask, vec3 torch_color, float brightness, bool overworld){
	return ogxBlockLight(lightmap, ao, source_mask, torch_color, brightness, overworld); // 实现在生成库。
}

// 纹理自发光：按模式把硬编码发光与资源包发光相加或二选一。
vec3 gfx_texture_emissive(vec3 albedo, float emissive, float hardcoded_mask, bool torch_tinted, vec3 torch_color, float torch_brightness,
		float texture_brightness, int mode, bool overworld){
	return ogxTextureEmissive(albedo, emissive, hardcoded_mask, torch_tinted, torch_color, torch_brightness,
		texture_brightness, mode, overworld); // 实现在生成库。
}

// 矿石发光：鲜艳又明亮的矿物颗粒才发光，灰色石底几乎不亮。
float gfx_ore_emission(vec3 albedo){
	return ogxOreEmission(albedo); // 实现在生成库。
}

// 纹饰发光：只看明度，越亮的纹路越亮。
float gfx_trim_emission(vec3 albedo){
	return ogxTrimEmission(albedo); // 实现在生成库。
}

#endif
