/*
视差模块适配层：高度采样、视差步进、自阴影与法线生成已迁到生成库。
调用位置：`rendering/parallax.glsl` 与地形、实体材质代码引用本文件；
    效果层只保留图集分辨率、画质与开关换算，算式只在 `omni-gfx/src/parallax.slang` 一份。
可复制示例：
    `ivec2 texel = gfx_parallax_smooth(coord, tbn, light, duv1, duv2, viewPos, normals, atlas, 16.0, true, 40, 12, 20, true, true, false, 0.0, 1, normal, shadow);`
设计原因与取舍：函数名、参数顺序与输入输出参数保持原样，调用点无需改动，默认画面不会漂移；
    图集尺寸、图块分辨率与所有画质参数由调用方传入，库不读取任何选项宏。
    转发函数的签名压成一行，方便一眼对照旧调用点，也让中文说明保持在一半以上。
*/
#ifndef GFX_PARALLAX_INCLUDED
#define GFX_PARALLAX_INCLUDED

// 迁移后的视差实现：高度采样、两套步进与自阴影。
#include "/omni-gfx/parallax.glsl"

// 双线性高度采样：在图块内跨格子读四角高度并插值，越界处用一层薄壳把空隙补平。
float gfx_parallax_height_bilinear(sampler2D normals, vec2 coord, ivec2 tiles_base_texel, float texture_resolution, int resolution_mask, bool is_block){
	return ogxParallaxHeightBilinear(normals, coord, tiles_base_texel, texture_resolution, resolution_mask, is_block); // 实现在生成库。
}

// 用高度差直接生成法线：平滑模式可以只用高度场求梯度，得到与视差一致的法线。
vec3 gfx_parallax_height_normal(sampler2D normals, vec2 coord, ivec2 tiles_base_texel, float texture_resolution, int resolution_mask, bool is_block, float depth, int mode){
	return ogxParallaxHeightNormal(normals, coord, tiles_base_texel, texture_resolution, resolution_mask, is_block, depth, mode); // 实现在生成库。
}

// 锐利模式的命中法线处理：按「由凹凸生成法线」的取值决定是否换回贴图法线或远处淡出。
vec3 gfx_parallax_hit_normal(sampler2D normals, ivec2 parallax_texel, vec3 hit_normal, float fade, bool fade_enabled, int based_normal){
	return ogxParallaxHitNormal(normals, parallax_texel, hit_normal, fade, fade_enabled, based_normal); // 实现在生成库。
}

// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
ivec2 gfx_parallax_smooth(vec2 coord, mat3 tbn, vec3 shadow_vector, vec2 duv1, vec2 duv2, vec3 view_pos, sampler2D normals, vec2 atlas_size, float texture_resolution, bool is_block, float depth, int quality, int refinements, int shadow_quality, bool shadow_enabled, bool taa, bool fade_enabled, float dither, int based_normal, inout vec3 normal_tex, inout float parallax_shadow){
	return ogxParallaxSmooth(coord, tbn[0], tbn[1], tbn[2], shadow_vector, duv1, duv2, view_pos, normals, atlas_size, texture_resolution, is_block, depth, quality, refinements, shadow_quality, shadow_enabled, taa, fade_enabled, dither, based_normal, normal_tex, parallax_shadow); // 实现在生成库。
}

// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
ivec2 gfx_parallax_sharp(vec2 coord, mat3 tbn, vec3 shadow_vector, vec2 duv1, vec2 duv2, vec3 view_pos, sampler2D normals, vec2 atlas_size, float texture_resolution, bool is_block, float depth, int quality, int shadow_quality, bool shadow_enabled, bool fade_enabled, int based_normal, inout vec3 hit_normal, inout float parallax_shadow){
	return ogxParallaxSharp(coord, tbn[0], tbn[1], tbn[2], shadow_vector, duv1, duv2, view_pos, normals, atlas_size, texture_resolution, is_block, depth, quality, shadow_quality, shadow_enabled, fade_enabled, based_normal, hit_normal, parallax_shadow); // 实现在生成库。
}

#endif
