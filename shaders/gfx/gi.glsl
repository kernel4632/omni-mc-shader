/*
全局光模块适配层：地平线遮蔽、反射阴影图反弹、时间滤波与空间滤波已整体迁到生成库。
调用位置：`effects/lighting/gi.glsl` 与 `effects/lighting/gtao.glsl` 引用本文件，调用点保持原样。
可复制示例：`float ao = gfx_ground_truth_ao(viewPos, viewDir, normal, ...);` 参数与迁移前一致。
设计原因与取舍：两个参数结构体在光影侧被逐字段填写，字段名沿用原来的下划线写法，
    同名类型用别名接上，适配层因此不产生结构体拷贝，也不会因为改名牵动与全局光无关的文件。
*/
#ifndef GFX_GI_INCLUDED
#define GFX_GI_INCLUDED

// 迁移后的全局光实现，包含遮蔽、反弹、历史重投影与两级滤波。
#include "/omni-gfx/gi.glsl"

// 光影侧的两个参数结构体：字段名与生成库一致，这里只把类型名接上。
#define gfx_gi_view OgxGiView
#define gfx_gtao_params OgxGtaoParams

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。
vec3 gfx_ao_multi_bounce(float ao, vec3 albedo) { // 旧名字的兼容入口。
	return ogxAoMultiBounce(ao, albedo); // 实现在生成库。
}

// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
float gfx_ground_truth_ao(vec3 view_pos, vec3 view_dir, vec3 normal, vec2 coord, float aspect, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse, mat4 dh_projection_inverse, gfx_gtao_params params, vec2 noise) { // 旧名字的兼容入口。
	return ogxGroundTruthAo(view_pos, view_dir, normal, coord, aspect, depth_texture, dh_depth_texture, projection, projection_inverse, dh_projection_inverse, params, noise); // 实现在生成库。
}

// 屏幕坐标与深度还原视空间位置，不撤销抖动。
vec3 gfx_gi_view_pos(vec2 coord, float depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	return ogxGiViewPos(coord, depth, projection_inverse); // 实现在生成库。
}

// 远景屏幕坐标与深度还原视空间位置。
vec3 gfx_gi_view_pos_dh(vec2 coord, float depth, mat4 dh_projection_inverse) { // 旧名字的兼容入口。
	return ogxGiViewPosDh(coord, depth, dh_projection_inverse); // 实现在生成库。
}

// 历史法线与深度采样：四个角按法线、距离和双线性权重混合。
vec3 gfx_gi_history_sample(vec3 curr_normal, float curr_dist, vec3 camera_velocity, vec2 prev_coord, float render_scale, sampler2D history_texture, sampler2D normal_texture, vec2 screen_size, out float weight_sum) { // 旧名字的兼容入口。
	return ogxGiHistorySample(curr_normal, curr_dist, camera_velocity, prev_coord, render_scale, history_texture, normal_texture, screen_size, weight_sum); // 实现在生成库。
}

// 反射阴影图反弹：从阴影图里可见的表面取底色，给当前点补一份光。
vec3 gfx_gi_rsm(vec3 view_pos, vec3 normal, gfx_gi_view view, sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0, sampler2D shadow_color1, float radius, int steps, float falloff, float shadow_map_resolution, float shadow_bias, vec2 noise, bool use_solid_shadow, bool leak_fix, bool underwater) { // 旧名字的兼容入口。
	return ogxGiRsm(view_pos, normal, view, shadow_depth0, shadow_depth1, shadow_color0, shadow_color1, radius, steps, falloff, shadow_map_resolution, shadow_bias, noise, use_solid_shadow, leak_fix, underwater); // 实现在生成库。
}

// 相机速度：算出当前像素相对上一帧的屏幕位移。
vec2 gfx_gi_camera_velocity(vec2 coord, float depth, bool is_dh, float material_ids, gfx_gi_view view, bool disable_hand, bool disable_player, float hand_depth, float player_material) { // 旧名字的兼容入口。
	return ogxGiCameraVelocity(coord, depth, is_dh, material_ids, view, disable_hand, disable_player, hand_depth, player_material); // 实现在生成库。
}

// 全局光时间滤波：本帧反弹与历史帧混合，同时把法线与距离写回历史图。
vec4 gfx_gi_temporal_filter(vec2 coord, ivec2 texel_coord, gfx_gi_view view, sampler2D history_texture, sampler2D normal_texture, sampler2D material_texture, sampler2D depth_texture, sampler2D dh_depth_texture, sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0, sampler2D shadow_color1, float render_scale, bool has_dh, bool use_dh_ao, bool new_version, bool leak_fix, bool underwater, bool use_solid_shadow, bool disable_hand, bool disable_player, float hand_depth, float player_material, float radius, float falloff, int steps, float shadow_map_resolution, float shadow_bias, vec2 noise) { // 旧名字的兼容入口。
	return ogxGiTemporalFilter(coord, texel_coord, view, history_texture, normal_texture, material_texture, depth_texture, dh_depth_texture, shadow_depth0, shadow_depth1, shadow_color0, shadow_color1, render_scale, has_dh, use_dh_ao, new_version, leak_fix, underwater, use_solid_shadow, disable_hand, disable_player, hand_depth, player_material, radius, falloff, steps, shadow_map_resolution, shadow_bias, noise); // 实现在生成库。
}

// 全局光空间滤波：七乘七邻域按法线与深度加权平均。
vec3 gfx_gi_spatial_filter(vec2 coord, float dist, vec3 normal, vec3 view_dir, gfx_gi_view view, sampler2D history_texture, float render_scale) { // 旧名字的兼容入口。
	return ogxGiSpatialFilter(coord, dist, normal, view_dir, view, history_texture, render_scale); // 实现在生成库。
}

#endif
