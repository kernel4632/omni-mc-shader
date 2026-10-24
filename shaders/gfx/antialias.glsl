/*
抗锯齿模块适配层：颜色空间、历史裁剪与时间重投影已整体迁到生成库。
调用位置：`effects/clarity/taa.glsl` 引用本文件，`TAAReproject` 与两个颜色空间函数保持原名。
可复制示例：`vec3 y = RGB_To_YCoCg(color);` 光影侧的包装函数内部调用生成库。
设计原因与取舍：时间重投影的采样循环已经在 `omni-gfx/src/antialias.slang`，这里只转发，
    避免两套公式各自漂移；只被重投影内部使用的中间函数不再对外转发，减少无用接口。
*/
#ifndef GFX_ANTIALIAS_INCLUDED
#define GFX_ANTIALIAS_INCLUDED

// 迁移后的抗锯齿实现。
#include "/omni-gfx/antialias.glsl"

// 把线性颜色转到亮度与色差空间，亮度单独处理。
vec3 gfx_rgb_to_ycocg(vec3 color) { // 旧名字的兼容入口。
	return ogxRgbToYCoCg(color); // 实现在生成库。
}

// 从亮度与色差空间换回线性颜色。
vec3 gfx_ycocg_to_rgb(vec3 color) { // 旧名字的兼容入口。
	return ogxYCoCgToRgb(color); // 实现在生成库。
}

// 把历史颜色裁进当前三乘三邻域。
vec3 gfx_clip_aabb(vec3 average, vec3 variance, vec3 history, bool to_center) { // 旧名字的兼容入口。
	return ogxClipAabb(average, variance, history, to_center); // 实现在生成库。
}

// 时间重投影：当前帧与历史帧按邻域范围、运动量、深度一致性混合。
vec4 gfx_taa_reproject(vec2 coord, vec3 velocity, float curr_depth_min, sampler2D current_texture, sampler2D history_texture, vec2 viewport, ivec2 texel_coord, mat4 projection_inverse, float far_plane, vec2 jitter, float blend_weight, float aggression, float depth_threshold, bool bicubic_current, bool bicubic_previous, bool clip_to_center, bool depth_compare, bool micro_blur, bool packed_depth, out float reference_depth) { // 旧名字的兼容入口。
	return ogxTaaReproject(coord, velocity, curr_depth_min, current_texture, history_texture, viewport, texel_coord, projection_inverse, far_plane, jitter, blend_weight, aggression, depth_threshold, bicubic_current, bicubic_previous, clip_to_center, depth_compare, micro_blur, packed_depth, reference_depth); // 实现在生成库。
}

#endif
