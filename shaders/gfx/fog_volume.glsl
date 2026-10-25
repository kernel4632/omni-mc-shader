/*
体积雾模块适配层：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影已迁到生成库。
调用位置：`rendering/fog/volumetric.glsl` 引用本文件；效果层只把选项、天气、群系与阴影贴图换成参数，
    算法只在 `omni-gfx/src/fog_volume.slang` 一份。
可复制示例：先填好 `gfx_fog_media`，再调用一次 `gfx_volumetric_fog` 完成整段步进。
设计原因与取舍：结构体字段、函数名、参数顺序与输出参数保持原样，宿主几十处赋值与调用点都不用改；
    雾照明与水下手持光两个钩子宏仍由效果层在包含本文件前定义，生成库只在未定义时补空操作。
*/
#ifndef GFX_FOG_VOLUME_INCLUDED
#define GFX_FOG_VOLUME_INCLUDED

// 雾、天气、阴影、水面与颜色模块提供依赖，最后引入迁移后的体积雾实现。
// 引入顺序不能改：钩子宏必须在生成库之前由宿主定义。
#include "/gfx/fog.glsl"
#include "/gfx/weather.glsl"
#include "/gfx/shadow.glsl"
#include "/gfx/water.glsl"
#include "/omni-gfx/fog_volume.glsl"

// 旧结构体名接到生成库的类型上，字段名与顺序完全一致。
// 这样宿主逐字段赋值的语句可以原样保留。
#define gfx_fog_media OgxFogMedia

// 云影贴图的三次采样：取红通道，与云影写入端同一套模糊。
// 四次双线性采样合成十六像素模糊，读取次数只有逐像素方案的四分之一。
float gfx_fog_cloud_bicubic(sampler2D source, vec2 coord, vec2 tex_size){ return ogxFogCloudBicubic(source, coord, tex_size); } // 实现在生成库。

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float gfx_fog_cloud_shadow(vec3 world_pos, gfx_fog_media media, sampler2D cloud_shadow_tex, bool fade_by_angle){ return ogxFogCloudShadow(world_pos, media, cloud_shadow_tex, fade_by_angle); } // 实现在生成库。

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
// 沙暴不随高度变淡，雪暴要，因此用雪暴强度插值。
float gfx_fog_storm_density(vec3 world_pos, gfx_fog_media media, sampler2D noise_texture){ return ogxFogStormDensity(world_pos, media, noise_texture); } // 实现在生成库。

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
vec3 gfx_fog_lightning(vec3 relative_pos, gfx_fog_media media, float light_distance, float falloff){ return ogxFogLightning(relative_pos, media, light_distance, falloff); } // 实现在生成库。

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
// 两条分支共用同一组高度与衰减参数，切换时画面不会跳变。
float gfx_fog_density(vec3 fog_pos, vec3 wind, bool noisy, float height_a, float height_b, float falloff, float time_midnight, sampler2D noise_texture){ return ogxFogDensity(fog_pos, wind, noisy, height_a, height_b, falloff, time_midnight, noise_texture); } // 实现在生成库。

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
float gfx_fog_light_march(inout vec3 fog_pos, vec3 wind, gfx_fog_media media, bool noisy, float height_a, float height_b, float falloff, sampler2D noise_texture, int steps, float step_length){ return ogxFogLightMarch(fog_pos, wind, media, noisy, height_a, height_b, falloff, noise_texture, steps, step_length); } // 实现在生成库。

// 体积雾主体：沿视线步进，同时沿光方向估遮挡，累加雾色与阳光散射。
// 步长按十一的幂次分布，近处密、远处疏，四十步就能覆盖整段空气。
void gfx_volumetric_fog(inout vec3 color, vec3 start_pos, vec3 end_pos, vec3 world_dir, gfx_fog_media media,
		sampler2D noise_texture, sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0,
		sampler2D cloud_shadow_tex, bool noisy, bool volumetric_lighting, bool use_cloud_shadow, bool use_stained, bool use_solid_shadow, bool indoor, bool cave_mode,
		float height_a, float height_b, float falloff, float sun_absorption, int steps, int light_steps, float light_step_length, float dither,
		out float transmittance){
	ogxVolumetricFog(color, start_pos, end_pos, world_dir, media, noise_texture, shadow_depth0, shadow_depth1, shadow_color0,
		cloud_shadow_tex, noisy, volumetric_lighting, use_cloud_shadow, use_stained, use_solid_shadow, indoor, cave_mode,
		height_a, height_b, falloff, sun_absorption, steps, light_steps, light_step_length, dither, transmittance); // 实现在生成库。
}

// 水下焦散：从当前位置向上找水面，按波法线折射后取交点距离，距离越近光柱越强。
float gfx_underwater_caustics(vec3 world_pos, vec3 shadow_light_vector, sampler2D normal_texture,
		vec2 pixel_size, vec2 screen_size, float max_resolution, float refract_ior){
	return ogxUnderwaterCaustics(world_pos, shadow_light_vector, normal_texture, pixel_size, screen_size, max_resolution, refract_ior); // 实现在生成库。
}

// 水下体积雾：沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
vec3 gfx_underwater_fog(vec3 start_pos, vec3 end_pos, vec3 world_dir, float global_cloud_shadow,
		vec3 camera_position, vec3 shadow_light_vector, sampler2D shadow_depth0, sampler2D shadow_depth1,
		bool use_solid_shadow, mat4 shadow_view, mat4 shadow_projection, float shadow_bias,
		sampler2D wave_normal_texture, vec2 pixel_size, vec2 screen_size, float caustics_resolution, float caustics_ior,
		vec3 sun_color, float sun_intensity, float underwater_density, int steps, float dither,
		bool water_absorption, float water_density, float hand_light_scale){
	return ogxUnderwaterFog(start_pos, end_pos, world_dir, global_cloud_shadow, camera_position, shadow_light_vector,
		shadow_depth0, shadow_depth1, use_solid_shadow, shadow_view, shadow_projection, shadow_bias,
		wave_normal_texture, pixel_size, screen_size, caustics_resolution, caustics_ior, sun_color, sun_intensity,
		underwater_density, steps, dither, water_absorption, water_density, hand_light_scale); // 实现在生成库。
}

#endif
