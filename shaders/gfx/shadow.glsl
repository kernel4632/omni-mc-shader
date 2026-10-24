/*
阴影模块适配层：实现已整体迁到生成库，这里只保留光影包使用的原函数名。
调用位置：`effects/shadow/shadow.glsl`、`effects/lighting/held_light.glsl` 与全局光模块引用本文件。
可复制示例：`vec3 q = gfx_shadow_screen_pos_distorted(worldPos, shadowView, shadowProjection, 0.9);` 参数与旧版一致。
设计原因与取舍：光影包里的调用点很多，直接改名字会牵动大量与阴影无关的文件；适配层让旧名字指向生成库，
    实际算式只有 `omni-gfx/src/shadow.slang` 一份，画面与迁移前逐项相同。
*/
#ifndef GFX_SHADOW_INCLUDED
#define GFX_SHADOW_INCLUDED

// 迁移后的阴影实现：投影、边缘压缩、屏幕空间阴影、PCSS 与软阴影。
#include "/omni-gfx/shadow.glsl"

// 世界位置转到阴影相机视空间，并按投影缩放、把深度折半。
vec3 gfx_shadow_view_pos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection) { // 旧名字的兼容入口。
	return ogxShadowViewPos(worldPos, shadowView, shadowProjection); // 实现在生成库。
}

// 投到阴影图，不做边缘压缩。
vec3 gfx_shadow_screen_pos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection) { // 旧名字的兼容入口。
	return ogxShadowScreenPos(worldPos, shadowView, shadowProjection); // 实现在生成库。
}

// 投到阴影图并做边缘压缩，离中心越远压得越紧。
vec3 gfx_shadow_screen_pos_distorted(vec3 worldPos, mat4 shadowView, mat4 shadowProjection, float bias) { // 旧名字的兼容入口。
	return ogxShadowScreenPosDistorted(worldPos, shadowView, shadowProjection, bias); // 实现在生成库。
}

// 对已经算好的阴影图坐标补一次边缘压缩，读取端使用。
vec2 gfx_distort_shadow_pos(vec2 shadowPos, float bias) { // 旧名字的兼容入口。
	return ogxDistortShadowPos(shadowPos, bias); // 实现在生成库。
}

// 屏幕深度换米制距离。
float gfx_shadow_linear_depth(float depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	return ogxShadowLinearDepth(depth, projection_inverse); // 实现在生成库。
}

// 屏幕空间阴影：从表面沿光源方向在屏幕里步进找遮挡。
float gfx_screen_space_shadow(vec3 view_pos, vec3 view_dir, vec3 normal, vec3 shadow_dir, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse, mat4 dh_projection_inverse, float pixel_scale, vec2 offset_coord, float noise, bool has_dh, int steps, float strength) { // 旧名字的兼容入口。
	return ogxScreenSpaceShadow(view_pos, view_dir, normal, shadow_dir, depth_texture, dh_depth_texture, projection, projection_inverse, dh_projection_inverse, pixel_scale, offset_coord, noise, has_dh, steps, strength); // 实现在生成库。
}

// 阳光的屏幕空间阴影：在屏幕里沿阳光方向步进，按吸收量削弱。
float gfx_sun_screen_shadow(vec3 view_pos, vec3 view_dir, vec3 normal, vec3 shadow_vector, float fov, float absorption, float softness, float grass, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse, mat4 dh_projection_inverse, float pixel_scale, float min_step, vec2 offset_coord, float noise, bool has_dh, int steps) { // 旧名字的兼容入口。
	return ogxSunScreenShadow(view_pos, view_dir, normal, shadow_vector, fov, absorption, softness, grass, depth_texture, dh_depth_texture, projection, projection_inverse, dh_projection_inverse, pixel_scale, min_step, offset_coord, noise, has_dh, steps); // 实现在生成库。
}

// 阴影图里一段视线的遮挡距离，按样本比例折算成米。
float gfx_shadow_segment_occlusion(vec3 shadow_start, vec3 shadow_end, sampler2D shadow_texture, int steps, float noise, float bias, float segment_length) { // 旧名字的兼容入口。
	return ogxShadowSegmentOcclusion(shadow_start, shadow_end, shadow_texture, steps, noise, bias, segment_length); // 实现在生成库。
}

// 不透明表面阴影：可变半影、彩色半透明阴影与次表面散射。
vec3 gfx_variable_penumbra_shadow(vec3 world_pos, vec3 world_normal, float sunlight, vec3 albedo, float scattering_strength, float hand, float leaves, float grass, vec3 camera_position, vec3 view_axis_z, mat4 shadow_view, mat4 shadow_projection, sampler2D shadow_depth0, sampler2DShadow shadow_depth1, sampler2D shadow_color0, float shadow_map_resolution, float shadow_distance, float far_plane, float bias, vec2 noise, bool variable_penumbra, bool colored_shadows, bool sss_directional, float sss_brightness, float sss_phase, float sss_quality, float vps_quality, float vps_spread, float basic_blur, out vec3 sss) { // 旧名字的兼容入口。
	return ogxVariablePenumbraShadow(world_pos, world_normal, sunlight, albedo, scattering_strength, hand, leaves, grass, camera_position, view_axis_z, shadow_view, shadow_projection, shadow_depth0, shadow_depth1, shadow_color0, shadow_map_resolution, shadow_distance, far_plane, bias, noise, variable_penumbra, colored_shadows, sss_directional, sss_brightness, sss_phase, sss_quality, vps_quality, vps_spread, basic_blur, sss); // 实现在生成库。
}

#endif
