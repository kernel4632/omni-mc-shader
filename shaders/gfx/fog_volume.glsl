/*
通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；本仓库由 `effects/fog/volumetric.glsl` 调用。
可复制示例：
    `gfx_fog_media media = ...;` 填相机、光色、天气与选项。
    `gfx_volumetric_fog(color, start, end, worldDir, media, ...);` 沿视线补雾。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明属于可选的宿主能力，用 `GFX_FOG_LPV_STEP` 宏留给效果层注入；不定义时是空操作。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
*/
#ifndef GFX_FOG_VOLUME_INCLUDED
#define GFX_FOG_VOLUME_INCLUDED

// 可选的雾照明钩子：效果层在包含本文件前定义，不定义时完全为空。
#ifndef GFX_FOG_LPV_STEP
#define GFX_FOG_LPV_STEP(fog_pos, integral, accum, done)
#endif
// 可选的水下手持光钩子：效果层把物品光采样接到这里，不定义时不加任何光。
#ifndef GFX_UNDERWATER_HAND_LIGHT
#define GFX_UNDERWATER_HAND_LIGHT(world_pos) vec3(0.0)
#endif

#include "/gfx/fog.glsl"
#include "/gfx/weather.glsl"
#include "/gfx/shadow.glsl"
#include "/gfx/water.glsl"

// 一帧体积雾需要的相机、光照与天气参数。
struct gfx_fog_media {
	vec3 camera_position; // 相机绝对世界位置。
	vec3 light_vector; // 指向光源的单位向量。
	vec3 light_color; // 直射光色。
	vec3 sky_color; // 天空环境光色。
	vec3 storm_color; // 暴风染色。
	vec3 biome_color; // 群系雾色。
	vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
	mat4 shadow_view; // 阴影相机视图。
	mat4 shadow_projection; // 阴影相机投影。
	vec2 cloud_shadow_screen; // 云影贴图所在画面的尺寸。
	vec2 cloud_shadow_texel; // 云影贴图画面的像素大小。
	float wetness; // 零到一的湿润度。
	float eye_skylight; // 天空光平滑值。
	float time_midnight; // 午夜强度。
	float time_factor; // 雾的时间因子。
	float density_scale; // 时段与每日天气给出的密度标度。
	float base_density; // 基础密度，已由效果层按远裁剪面或远景距离换算。
	float storm_strength; // 雪暴与沙暴的总强度。
	float snow_storm; // 雪暴强度，决定暴风雾是否随高度变淡。
	float daily_fog; // 每日天气的匀雾密度。
	float storm_density; // 暴风雾浓度选项。
	float storm_height; // 暴风雾起始高度。
	float storm_time; // 暴风噪声的滚动时间，单位秒。
	float wind_time; // 团雾随风移动的时间，已按云速换算。
	float global_cloud_shadow; // 整个场景共用的粗粒度云影。
	float shadow_map_resolution; // 阴影图像素边长。
	float shadow_bias; // 阴影坐标边缘压缩强度。
	float cloud_shadow_range; // 云影贴图覆盖范围，米。
	float cloud_shadow_tex_size; // 云影贴图最大边长。
	float rain_shadow; // 雨天的云影底值。
	float biome_coverage; // 落在已启用群系内的程度。
	float biome_height; // 群系高度衰减雾密度。
	float biome_cloudy; // 群系团雾密度。
	float lightning_intensity; // 闪电事件强度。
	float lightning_strength; // 闪电亮度选项。
	float sky_intensity; // 天光强度选项。
	float sun_intensity; // 阳光强度选项。
	float fog_density_option; // 环境雾强度选项。
	float sun_density_option; // 散射强度选项。
};

// 云影贴图的三次采样：取红通道，与云影写入端同一套模糊。
float gfx_fog_cloud_bicubic(sampler2D source, vec2 coord, vec2 tex_size){
	vec2 texel = 1.0 / tex_size; // 一个纹素的大小。
	coord = coord * tex_size - 0.5; // 换成以像素中心为原点。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 前两个权重。
	vec4 w1; // 后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
	w1.yw = ff * f; // 第四个权重。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
	c *= texel.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(source, c.yw, 0.0).x, textureLod(source, c.xw, 0.0).x, m.x),
		mix(textureLod(source, c.yz, 0.0).x, textureLod(source, c.xz, 0.0).x, m.x), m.y); // 四次采样合成模糊。
}

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float gfx_fog_cloud_shadow(vec3 world_pos, gfx_fog_media media, sampler2D cloud_shadow_tex, bool fade_by_angle){
	vec2 coord = world_pos.xz - media.light_vector.xz * ((world_pos.y + media.camera_position.y) / media.light_vector.y); // 沿光方向投到云影贴图平面。
	coord = coord * (1.0 / media.cloud_shadow_range) + 0.5; // 换成零到一的贴图坐标。
	float cloud_shadow = 1.0 - media.wetness; // 雨天默认的云影底值。
	if (gfx_saturate(coord) == coord){ // 只有落在贴图范围内才采样。
		float shadow_tex_size = floor(min(media.cloud_shadow_screen.y * 0.45, media.cloud_shadow_tex_size)); // 云影贴图实际边长。
		vec2 shadow_texel = media.cloud_shadow_screen - coord * shadow_tex_size; // 贴图贴在画面右上角，坐标要翻转。
		vec2 fade = gfx_saturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
		cloud_shadow = mix(cloud_shadow, gfx_fog_cloud_bicubic(cloud_shadow_tex, shadow_texel * media.cloud_shadow_texel, media.cloud_shadow_screen), fade.x * fade.y); // 三次采样并淡出。
	}
	if (fade_by_angle){ // 太阳越贴地云影越淡。
		float fade_angle = smoothstep(0.06, 0.18, abs(media.light_vector.y)); // 光方向越平越淡。
		cloud_shadow = mix(1.0 - media.wetness, cloud_shadow, fade_angle * fade_angle); // 按淡出权重混合。
	}
	return ((media.rain_shadow - 1.0) * media.wetness + 1.0) * cloud_shadow + (media.wetness - media.rain_shadow * media.wetness); // 晴天与雨天两档之间插值。
}

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
float gfx_fog_storm_density(vec3 world_pos, gfx_fog_media media, sampler2D noise_texture){
	vec3 scroll = vec3(media.storm_time, 0.0, media.storm_time) * 15.0; // 随时间在横纵方向滚动。
	vec3 sample_pos = (world_pos * vec3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量。
	float noise = 1.0 - gfx_storm_noise(sample_pos, noise_texture, 512.0); // 取反，让噪声高的地方雾更浓。
	float height_fade = exp2(-0.06 * max(world_pos.y - (media.storm_height + 3.0), 0.0)); // 起始高度以上缓慢变淡。
	float dense_cloud = noise * noise * mix(1.0, height_fade, media.snow_storm); // 噪声雾团。
	return 1.0 + dense_cloud + media.daily_fog; // 低空层与噪声雾团相加。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
vec3 gfx_fog_lightning(vec3 relative_pos, gfx_fog_media media, float light_distance, float falloff){
	if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
	vec3 bolt_pos = vec3(media.lightning_position.x, clamp(relative_pos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
	float bolt_distance = length(relative_pos - bolt_pos); // 介质采样点到光柱的距离。
	float lightning_light = max(1.0 - bolt_distance / light_distance, 0.0); // 照明范围内线性衰减。
	lightning_light = exp((1.0 - lightning_light) * falloff); // 换成更集中的指数衰减。
	return vec3(0.55, 0.65, 0.9) * (lightning_light * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
float gfx_fog_density(vec3 fog_pos, vec3 wind, bool noisy, float height_a, float height_b, float falloff, float time_midnight, sampler2D noise_texture){
	return noisy
		? gfx_fog_density_noise(fog_pos, wind, height_a, height_b, falloff, time_midnight, noise_texture)
		: gfx_fog_density_height(fog_pos, height_a, height_b, falloff, time_midnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
float gfx_fog_light_march(inout vec3 fog_pos, vec3 wind, gfx_fog_media media, bool noisy, float height_a, float height_b, float falloff, sampler2D noise_texture, int steps, float step_length){
	float lighting_density = 0.0; // 沿光方向累计的密度。
	for (int i = 0; i < steps; i++, fog_pos += media.light_vector * step_length, step_length *= 1.5){ // 沿光方向步进，步长逐步放大。
		lighting_density += gfx_fog_density(fog_pos, wind, noisy, height_a, height_b, falloff, media.time_midnight, noise_texture) * step_length; // 累加这一段密度。
	}
	return lighting_density; // 返回累计密度。
}

// 体积雾主体：沿视线步进，同时沿光方向估遮挡，累加雾色与阳光散射。
// `dither` 是这一步的抖动；`phases` 由效果层按体积光照开关选择单级或多级。
void gfx_volumetric_fog(inout vec3 color, vec3 start_pos, vec3 end_pos, vec3 world_dir, gfx_fog_media media,
		sampler2D noise_texture, sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0,
		sampler2D cloud_shadow_tex, bool noisy, bool volumetric_lighting, bool use_cloud_shadow, bool use_stained, bool use_solid_shadow, bool indoor, bool cave_mode,
		float height_a, float height_b, float falloff, float sun_absorption, int steps, int light_steps, float light_step_length, float dither,
		out float transmittance){
	float time_factor = media.time_factor * (noisy ? 1.0 : media.time_midnight * 2.0 + 1.0); // 仅高度衰减模式夜晚雾更浓。
	vec3 start = start_pos + media.camera_position; // 起点换成绝对世界坐标。
	vec3 end = end_pos + media.camera_position; // 终点同样换成绝对世界坐标。
	vec3 ray_vector = end - start; // 从起点到终点的矢量。
	float ray_length = length(ray_vector) / float(steps) * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。
	vec3 shadow_start = gfx_shadow_screen_pos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
	vec3 shadow_end = gfx_shadow_screen_pos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
	vec3 shadow_vector = shadow_end - shadow_start; // 阴影图里的步进矢量。
	vec3 storm_wind = noisy ? vec3(-1.0, -0.05, 0.6) * media.wind_time : vec3(0.0); // 团雾按风移动。
	transmittance = 1.0; // 透射率从全透开始。
	float fog_density = 0.0; // 环境雾累计量。
	float ray_density = 0.0; // 阳光散射累计量。
	vec3 lightning_fog = vec3(0.0); // 闪电点亮的空气。
	vec3 lpv_fog = vec3(0.0); // 雾照明累计量，由宏注入。
	vec3 translucent = vec3(0.0); // 透过半透明方块的染色光。
	for (int i = 0; i < steps; i++){ // 沿视线逐步前进。
		float exponential = pow(11.0, (float(i) + dither) / float(steps)); // 指数步长因子。
		float step_length = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
		float step_density = exponential * ray_length * 1.442695; // 这一步的光学厚度。
		vec3 fog_pos = start + step_length * ray_vector; // 这一步的雾采样位置。
		vec3 shadow_pos = shadow_start + step_length * shadow_vector; // 这一步的阴影图坐标。
		vec3 lightning_step = gfx_fog_lightning(fog_pos - media.camera_position, media, 150.0, -15.0); // 闪电照亮空气。
		float biome_distance = length((step_length * ray_vector).xz); // 这一步相对起点的水平距离。
		float biome_envelope = min(max(1.0 - biome_distance / 256.0, 0.0) * 2.0, 1.0); // 二百五十六米内替换最明显。
		float density_scale = mix(media.density_scale, media.biome_height, media.biome_coverage * biome_envelope); // 群系高度雾密度。
		if (noisy) density_scale = mix(media.density_scale, media.biome_cloudy, media.biome_coverage * biome_envelope); // 团雾取多云那套。
		float density = gfx_fog_density(fog_pos, storm_wind, noisy, height_a, height_b, falloff, media.time_midnight, noise_texture); // 这一点的雾密度。
		density = (density * density_scale + media.base_density) * time_factor; // 乘密度标度与时间因子。
		density += gfx_fog_storm_density(fog_pos, media, noise_texture) * media.storm_strength * media.storm_density; // 暴风额外浓雾。
		float absorption = exp2(-density * step_density); // 这一步吸收掉的光。
		float step_ray_density = 0.0; // 这一步的阳光散射量。
		if (volumetric_lighting){ // 沿阳光方向估吸收。
			float lighting_density = gfx_fog_light_march(fog_pos, storm_wind, media, noisy, height_a, height_b, falloff, noise_texture, light_steps, light_step_length); // 沿光方向累计密度。
			lighting_density = (lighting_density * sun_absorption * density_scale + media.base_density) * time_factor; // 乘吸收率与密度标度。
			float lighting_absorption = exp2(-lighting_density * step_density); // 光方向上的吸收。
			float phases[4]; // 四级散射相位。
			gfx_multi_scattering_phases(dot(world_dir, media.light_vector), phases); // 一次算好四级相位。
			float order = 1.0; // 多级相位的权重。
			for (int j = 0; j < 4; j++, order *= 0.5) step_ray_density += exp(-lighting_density * order) * phases[j] * order; // 四级散射加权求和。
			step_ray_density *= gfx_powder_effect(absorption, lighting_absorption, dot(world_dir, media.light_vector)); // 乘粉末效应。
		}else{ // 单级前向相位。
			step_ray_density = gfx_MiePhaseFunction(0.5, dot(world_dir, media.light_vector)) * 0.7 + 0.05;
		}
		shadow_pos.xy = gfx_distort_shadow_pos(shadow_pos.xy, media.shadow_bias); // 阴影图坐标补上边缘压缩。
		float shadow = 1.0; // 这一点受不受阳光。
		vec3 shadow_color_sample = vec3(1.0); // 该点半透明染色。
		if (gfx_saturate(shadow_pos.xy) == shadow_pos.xy && shadow_pos.z < 1.0){ // 坐标落在阴影图内才采样。
			ivec2 shadow_texel = ivec2(shadow_pos.xy * media.shadow_map_resolution); // 换成阴影图纹素。
			float solid_depth = use_solid_shadow ? texelFetch(shadow_depth1, shadow_texel, 0).x : texelFetch(shadow_depth0, shadow_texel, 0).x; // 按显卡能力选深度图。
			shadow *= step(shadow_pos.z, solid_depth); // 射线在遮挡物前面才受光。
			if (use_stained){ // 半透明染色。
				float transparent_depth = texelFetch(shadow_depth0, shadow_texel, 0).x; // 读半透明深度。
				shadow_color_sample = gfx_GammaToLinear(texelFetch(shadow_color0, shadow_texel, 0).rgb); // 读半透明颜色。
				float transparent_shadow = step(transparent_depth, shadow_pos.z) * shadow; // 半透明遮挡量。
				shadow_color_sample *= transparent_shadow; // 颜色按遮挡量缩放。
				shadow -= transparent_shadow; // 从受光里扣掉半透明遮挡。
			}
		}
		float cloud_shadow = 1.0; // 云影默认不压暗。
		if (use_cloud_shadow) cloud_shadow = gfx_fog_cloud_shadow(fog_pos - media.camera_position, media, cloud_shadow_tex, false); // 读该点云影。
		float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
		step_ray_density *= integral; // 散射量按吸收缩放。
		if (use_cloud_shadow){ // 有云影时雾色也按云影压暗。
			step_ray_density *= mix(cloud_shadow, 1.0, media.wetness * 0.1 + 0.03); // 散射按云影压暗。
			fog_density += integral * mix(cloud_shadow, 1.0, media.wetness * 0.3 + 0.7); // 环境雾按云影压暗。
		}else{ // 没有云影时直接累加。
			fog_density += integral; // 直接累加。
		}
		ray_density += step_ray_density * shadow; // 散射只在受光处累加。
		if (use_stained) translucent += step_ray_density * shadow_color_sample; // 累加染色散射。
		transmittance *= absorption; // 透射率逐步衰减。
		lightning_fog += lightning_step * integral; // 闪电按吸收量累加。
		bool lpv_done = false; // 雾照明走出体积时提前结束。
		GFX_FOG_LPV_STEP(fog_pos, integral, lpv_fog, lpv_done) // 由效果层决定是否采样体积光。
		if (lpv_done) break; // 走出体积就不再步进。
	}
	vec3 skylight = media.sky_color; // 雾的环境色以天光为主。
	vec3 sky_sun = media.light_color * 0.03; // 雾里的一点点直射光。
	skylight += sky_sun * (1.0 + (1.0 - media.global_cloud_shadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
	skylight = mix(skylight, sky_sun, media.wetness * 0.7); // 雨天偏向直射色。
	vec3 fog_color = skylight * fog_density; // 环境雾色。
	vec3 ray_color = media.light_color * ray_density; // 阳光散射色。
	fog_color *= media.storm_color; // 暴风染色。
	ray_color *= media.storm_color; // 阳光散射同样染色。
	vec3 biome_tint = mix(vec3(1.0), media.biome_color, media.biome_coverage); // 群系雾色。
	fog_color *= biome_tint; // 环境雾染成群系色。
	ray_color *= biome_tint; // 阳光散射同样染色。
	ray_color += media.light_color * translucent; // 叠上透过半透明方块的染色光。
	fog_color *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
	ray_color *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
	if (!use_cloud_shadow) ray_color *= mix(media.global_cloud_shadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
	if (!indoor){ // 体积雾随天空光等级衰减。
		fog_color *= media.eye_skylight; // 环境雾按天空光衰减。
		if (cave_mode) ray_color *= media.eye_skylight; // 洞穴模式下散射也衰减。
		lightning_fog *= media.eye_skylight; // 闪电来自天空。
		transmittance = mix(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
	}
	color = transmittance * color + fog_color + ray_color + lightning_fog + lpv_fog; // 场景色先被吸收，再叠上雾与散射。
}

// 水下焦散：从当前位置向上找水面，按波法线折射后取交点距离，距离越近光柱越强。
// 为什么单独一份：它与水面焦散的三乘三采样用途不同，这里只要一份范围很窄的值来收窄光柱。
float gfx_underwater_caustics(vec3 world_pos, vec3 shadow_light_vector, sampler2D normal_texture,
		vec2 pixel_size, vec2 screen_size, float max_resolution, float refract_ior){
	vec3 lookup_center = world_pos; // 从当前位置向上找波面。
	lookup_center.y += 1.0; // 抬高一米到水面上方。
	vec3 waves_normal = gfx_waves_normal_from_tex(lookup_center, shadow_light_vector, normal_texture,
		pixel_size, screen_size, max_resolution, refract_ior).xzy; // 读波法线并换到竖直轴朝上的坐标。
	vec3 refract_vector = refract(vec3(0.0, 1.0, 0.0), waves_normal, 1.0); // 竖直光线被波面折射后的方向。
	vec3 collision_point = lookup_center - refract_vector / refract_vector.y; // 光线与水平面的交点。
	float dist = distance(collision_point, world_pos); // 交点到当前点的距离。
	return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}

// 水下体积雾：沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向、云影、相机位置、阴影图与波法线图；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
vec3 gfx_underwater_fog(vec3 start_pos, vec3 end_pos, vec3 world_dir, float global_cloud_shadow,
		vec3 camera_position, vec3 shadow_light_vector, sampler2D shadow_depth0, sampler2D shadow_depth1,
		bool use_solid_shadow, mat4 shadow_view, mat4 shadow_projection, float shadow_bias,
		sampler2D wave_normal_texture, vec2 pixel_size, vec2 screen_size, float caustics_resolution, float caustics_ior,
		vec3 sun_color, float sun_intensity, float underwater_density, int steps, float dither,
		bool water_absorption, float water_density, float hand_light_scale){
	const float range = 40.0; // 光柱的累积范围。
	float start_dist = length(start_pos); // 起点到相机的距离。
	if (start_dist > range) return vec3(0.0); // 起点已经在范围外，不画光柱。
	end_pos = mix(world_dir * range, end_pos, step(length(end_pos), range)); // 终点超过范围就截断到范围内。
	float ray_dist = distance(start_pos, end_pos); // 这条射线在范围里的长度。
	vec3 ray_dir = (end_pos - start_pos) / ray_dist; // 射线方向。
	float step_length = range / float(steps); // 每段长度。
	vec3 result = vec3(0.0); // 累加的光柱颜色。
	vec3 hand_fog = vec3(0.0); // 累加的手持光颜色。
	for (float i = 0.0; i < float(steps); i++){ // 沿视线逐步前进。
		float ray_length = (i + dither) * step_length; // 当前位置，起点加抖动量。
		vec3 ray_pos = start_pos + ray_dir * ray_length; // 相机相对世界位置。
		if (start_dist + ray_length > range || ray_length > ray_dist) break; // 超出范围就停止。
		vec3 shadow_pos = gfx_shadow_screen_pos_distorted(ray_pos + camera_position, shadow_view, shadow_projection, shadow_bias); // 投到阴影图，含边缘压缩。
		float shadow_depth = use_solid_shadow ? textureLod(shadow_depth1, shadow_pos.xy, 0.0).x : textureLod(shadow_depth0, shadow_pos.xy, 0.0).x; // 按显卡能力选深度图。
		vec3 shadow = vec3(step(shadow_pos.z + 1e-06, shadow_depth)); // 受光则由深度图判定。
		ray_length += start_dist; // 距离补上起点偏移。
		float caustics = gfx_underwater_caustics(ray_pos + camera_position, shadow_light_vector, wave_normal_texture,
			pixel_size, screen_size, caustics_resolution, caustics_ior); // 该点焦散强度。
		shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
		shadow /= max(3.0, ray_length * 0.1); // 越远越弱。
		if (water_absorption) shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(ray_length * 0.04 * water_density)); // 红衰减最快，光柱因此偏蓝。
		result += shadow; // 累加。
		vec3 hand_light = GFX_UNDERWATER_HAND_LIGHT(ray_pos); // 手持光源在该点留下的光，由效果层注入。
		if (water_absorption) hand_light *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(ray_length * 0.04 * water_density)); // 与光柱同一套分波段吸收，近处暖、远处青蓝。
		hand_fog += hand_light; // 累加。
	}
	result *= range / float(steps); // 取平均。
	vec3 light_vector = refract(shadow_light_vector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
	float light_dot_view = dot(light_vector, world_dir); // 光方向与视线的夹角。
	float phase = gfx_MiePhaseFunction(0.7, light_dot_view); // 前向相位，正对阳光时更亮。
	result *= sun_color * (0.04 * phase * sun_intensity * underwater_density); // 乘直射光色、相位与强度。
	if (water_absorption) result *= vec3(0.2, 0.65, 1.0); // 有水下雾时把光柱染成水色。
	result *= global_cloud_shadow; // 按全局云影压暗。
	result += hand_fog * (range / float(steps)) * hand_light_scale; // 手持光不随阳光相位与云影变化，最后叠上。
	return result; // 返回光柱颜色。
}

#endif
