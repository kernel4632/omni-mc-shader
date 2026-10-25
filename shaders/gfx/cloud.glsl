/*
通用图形库云模块：云的光照相位、顶部曲线、平面云密度与云影取样。
调用位置：任何需要云形状或云影的程序；本仓库由 `effects/cloud/*` 与 `effects/reflection/screenspace.glsl` 调用。
可复制示例：
    float p = gfx_henyey_greenstein(cosAngle, 0.8); // 前向散射相位。
    float t = gfx_cloud_top_curve(x); // 云的顶部圆润曲线。
    float s = gfx_cloud_shadow(shadowTex, worldPos, lightDir, cameraY, 4096.0, screenSize, pixelSize, 256.0, wetness, 1.0, true); // 云影。
设计原因与取舍：
    只做纯数学与采样，不读取噪声纹理绑定、云层高度或选项；纹理与参数仍由调用方传入。
    公式照 iterationT 原程序保留，迁移只改名字；云影与云的形状放在一起，因为两者共用同一套天气与范围。
*/
#ifndef GFX_CLOUD_INCLUDED
#define GFX_CLOUD_INCLUDED

#include "/gfx/math.glsl"
// 迁移后的效果实现在生成库里。
#include "/omni-gfx/cloud.glsl"

#define GFX_GOLDEN_ANGLE 2.39996322973 // 黄金角，用来旋转噪声层。

// 亨耶-格林斯坦相位：描述云滴把光往哪个方向散，参数越大越集中在前方。
float gfx_henyey_greenstein(float cos_angle, float g){
	return ogxHenyeyGreenstein(cos_angle, g); // 实现在生成库。
}

// 云的顶部曲线：把一到零的坐标变成圆润的凸起。
float gfx_cloud_top_curve(float x){
	return ogxCloudTopCurve(x); // 实现在生成库。
}

// 三次模糊噪声：平面云专用，四次双线性采样合成十六像素模糊，取第四通道。
float gfx_bicubic_blur_noise(vec2 coord, sampler2D noise_texture){
	return ogxBicubicBlurNoise(coord, noise_texture); // 实现在生成库。
}

// 双线性噪声：平面云细节用的普通采样。
float gfx_bilinear_noise(vec2 position, sampler2D noise_texture){
	return ogxBilinearNoise(position, noise_texture); // 实现在生成库。
}

// 平面云的扭曲：几层噪声叠出缓慢起伏的偏移量，让云块边缘不平整。
float gfx_planar_distortion(vec2 position, vec2 wind_direction, sampler2D noise_texture){
	return ogxPlanarDistortion(position, wind_direction, noise_texture); // 实现在生成库。
}

// 平面云密度：位置先扭曲，再叠多层旋转噪声得到云块。
float gfx_planar_density(vec2 position, vec2 wind_direction, sampler2D noise_texture, float noise_scale, float coverage){
	return ogxPlanarDensity(position, wind_direction, noise_texture, noise_scale, coverage); // 实现在生成库。
}

// 平面云的光照密度：用便宜的噪声和更少层数，专供光照估计。
float gfx_planar_lighting_density(vec2 position, vec2 wind_direction, sampler2D noise_texture, float noise_scale, float coverage){
	return ogxPlanarLightingDensity(position, wind_direction, noise_texture, noise_scale, coverage); // 实现在生成库。
}

// --- 云影：把地表点投到云影贴图并取遮蔽 ---
// 为什么放在云模块：云影是云的可见结果，与云的形状共用同一套天气与范围参数。

// 云影投影坐标：把世界点沿光方向投到云影所在的水平面，再换成零到一贴图坐标。
vec2 gfx_cloud_shadow_coord(vec3 world_pos, vec3 light_dir, float camera_y, float range){
	return ogxCloudShadowCoord(world_pos, light_dir, camera_y, range); // 实现在生成库。
}

// 十六像素三次模糊：四次双线性采样合成，返回红通道。
float gfx_cloud_shadow_bicubic(sampler2D shadow_tex, vec2 coord, vec2 tex_size){
	return ogxCloudShadowBicubic(shadow_tex, coord, tex_size); // 实现在生成库。
}

// 云影取样：按天气在晴天与雨天两档之间混合。
float gfx_cloud_shadow(sampler2D shadow_tex, vec3 world_pos, vec3 light_dir, float camera_y, float range,
		vec2 screen_size, vec2 pixel_size, float tex_size, float wetness, float rain_shadow, bool fade_angle){
	return ogxCloudShadowSample(shadow_tex, world_pos, light_dir, camera_y, range, screen_size, pixel_size,
		tex_size, wetness, rain_shadow, fade_angle); // 实现在生成库。
}

// 全局云影：从云影贴图顶行的统计像素取一个粗粒度值。
float gfx_global_cloud_shadow(sampler2D shadow_tex, ivec2 stat_texel, float wetness, float rain_shadow, bool from_texture){
	return ogxGlobalCloudShadow(shadow_tex, stat_texel, wetness, rain_shadow, from_texture); // 实现在生成库。
}

// 云影横向或纵向高斯模糊：权重固定，轴由参数给。
vec4 gfx_cloud_shadow_blur(sampler2D shadow_tex, ivec2 texel, ivec2 axis, ivec2 border_min, ivec2 border_max){
	return ogxCloudShadowBlur(shadow_tex, texel, axis, border_min, border_max); // 实现在生成库。
}

#endif
