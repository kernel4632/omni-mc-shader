/*
通用图形库体积云模块：形状取样、光照步进、沿视线步进与云影。
调用位置：任何需要体积云的程序；本仓库由 effects/cloud/volumetric.glsl 调用。
可复制示例：
    `vec4 layer = gfx_cloud_layer(worldDir, media, noise, hitOffset, baseNoise, detailNoise, curlNoise, samples, quality, light, scales...);` 步进一层云。
    `float shadow = gfx_cloud_shadow_tex(coord, media, light, range, baseNoise, curlNoise, scales...);` 取一处云影。
设计原因与取舍：
    纹理、云层高度、风、天气与太阳方向全部由调用方传入，库不读取选项或宿主状态。
    基础云与附加层共用同一套步进核心；空气透视属于大气效果，留在调用方合成。
*/
#ifndef GFX_CLOUD_VOLUME_INCLUDED
#define GFX_CLOUD_VOLUME_INCLUDED

#include "/gfx/cloud.glsl"

// --- 体积云：形状取样、光照步进与沿视线步进 ---
// 这一组函数只做纯计算与纹理采样，纹理、云层高度、风、天气和太阳方向都由调用方传入。
// `wetness` 是零到一的湿润度，控制云量、云底亮度与细节侵蚀；默认值由效果层按选项换算。

// 体积云的一层参数；基础云与卷云、高层云、积雨云共用同一套字段，避免每个附加层再写一份循环。
struct gfx_cloud_media {
	vec3 wind; // 风的位移方向与速度。
	vec3 camera_position; // 相机绝对世界位置，供云影与闪电使用。
	vec3 light_color; // 直射光颜色。
	vec3 sky_color; // 天空环境光颜色。
	vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
	vec2 altitude; // 云层底与顶的高度。
	vec2 lighting_strength; // 直射与环境强度。
	float planet_radius; // 行星半径，米。
	float cloud_scale; // 云块水平尺度。
	float density_option; // 密度倍率。
	float coverage; // 这一层的云量下限。
	float wetness; // 零到一的湿润度。
	float bottom_brightness; // 云底亮度。
	float outscatter_factor; // 外散射指数。
	float lightning_intensity; // 闪电事件强度，零表示没有闪电。
	float lightning_strength; // 闪电亮度选项。
};

// 三次平滑曲线：把零到一压成两端缓、中间快的过渡。
float gfx_cloud_curve(float x){ return x * x * (3.0 - 2.0 * x); }

// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向加随高度增大的偏移。
vec4 gfx_cloud_set_pos(vec3 marching_pos, gfx_cloud_media media){
	vec4 cloud_pos = vec4(marching_pos, 0.0); // 前三通道是位置，第四通道是层内高度。
	cloud_pos.y = length(cloud_pos.xyz + vec3(0.0, media.planet_radius, 0.0)) - media.planet_radius; // 用球面距离算真实高度。
	cloud_pos.w = gfx_remapSaturate(cloud_pos.y, media.altitude.x, media.altitude.y); // 在云层里的归一化高度。
	cloud_pos.xyz = cloud_pos.xyz * media.cloud_scale + vec3(30.0 * cloud_pos.w, 0.0, -12.0 * cloud_pos.w); // 水平缩放并随高度剪切，云因此有斜向层次。
	return cloud_pos; // 返回云坐标。
}

// 采样云密度：基础形状乘云量得到不透明密度，再叠细节噪声得到碎边。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sample_detail` 为假时跳过细节以省性能。
vec2 gfx_cloud_sample_density(vec4 cloud_pos, gfx_cloud_media media, bool sample_detail, float coverage,
		sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise, float base_scale, float coverage_offset,
		float detail_scale, float detail_strength){
	vec4 base_sample = textureLod(base_noise, cloud_pos.xyz * base_scale + media.wind * 10.0, 0.0); // 按云坐标与风偏移读基础噪声。
	float base_density = base_sample.y * 0.4 + base_sample.z * 0.4 + base_sample.w * 0.2; // 三个通道加权得到形状。
	base_density = gfx_remapSaturate(base_sample.x, base_density - 1.0, 1.0); // 用第一通道做概率重映射，得到云块。
	float shape_curve = gfx_cloud_top_curve(gfx_saturate(1.0 - cloud_pos.w)) * 0.5; // 上半段的收口曲线。
	shape_curve += gfx_cloud_curve(gfx_saturate(1.15 - cloud_pos.w * 1.43)) * 0.5; // 下半段的收口曲线。
	base_density *= shape_curve; // 竖直方向收口，云像是浮在中间。
	base_density *= gfx_fsqrt(gfx_saturate(cloud_pos.w * 2.5)) * 0.2 + 0.8; // 下半段略压扁。
	base_density *= mix(1.0, gfx_cloud_top_curve(gfx_saturate(cloud_pos.w * 3.0)), media.wetness); // 雨天让云更集中在顶部。
	float coverage_noise = textureLod(base_noise, cloud_pos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + media.wind + coverage_offset, 0.0).x; // 极低频云量噪声。
	coverage = gfx_remapSaturate(1.0 - coverage_noise, coverage * 0.2, coverage); // 把云量映射成密度下限。
	base_density = gfx_remapSaturate(base_density, coverage, 1.0); // 低于下限的部分去掉。
	base_density *= gfx_cloud_curve(gfx_saturate(cloud_pos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 中段加厚。
	base_density *= gfx_cloud_top_curve(gfx_saturate(cloud_pos.w * 1.8)); // 顶部收口。
	base_density = gfx_saturate(base_density); // 收敛到零到一。
	float detailed_density = 0.0; // 详细密度，下面按是否需要细节赋值。
	if (base_density > 1e-6 && sample_detail){ // 只有基础密度确实存在才叠细节。
		float curl_noise = textureLod(curl_noise, cloud_pos.xy * 0.0001, 0.0).w; // 读噪声第四通道。
		cloud_pos.xy += curl_noise * (100.0 - cloud_pos.w * 100.0); // 越靠云底扭曲越大。
		vec3 detailed_noise = textureLod(detail_noise, cloud_pos.xyz * detail_scale + media.wind * 140.0, 0.0).xyz; // 读三十二立方细节噪声。
		detailed_density = 1.0 - detailed_noise.x * 0.625 - detailed_noise.y * 0.25 - detailed_noise.z * 0.125; // 三通道按权重合成侵蚀量。
		detailed_density *= (0.21 - media.wetness * 0.11) * detail_strength; // 强度与天气权重可调。
		detailed_density = gfx_remapSaturate(base_density, detailed_density, 1.0); // 用基础密度限制侵蚀范围。
	}else{ // 不需要细节时直接用基础密度。
		detailed_density = base_density; // 保持连续。
	}
	return vec2(base_density, detailed_density); // 返回两份密度。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱，云采样点离柱越近越亮。
vec3 gfx_cloud_lightning(vec3 relative_pos, gfx_cloud_media media, float light_distance, float falloff){
	if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
	vec3 bolt_pos = vec3(media.lightning_position.x, clamp(relative_pos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
	float bolt_distance = length(relative_pos - bolt_pos); // 介质采样点到光柱的距离。
	float lightning_light = max(1.0 - bolt_distance / light_distance, 0.0); // 照明范围内线性衰减。
	lightning_light = exp((1.0 - lightning_light) * falloff); // 换成更集中的指数衰减。
	return vec3(0.55, 0.65, 0.9) * (lightning_light * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}

// 云的光照：沿光方向在云里步进估遮挡，再算直射与环境的合成颜色。
vec3 gfx_cloud_lighting(vec3 marching_pos, gfx_cloud_media media, vec2 cloud_density, vec4 cloud_pos, float noise,
		float vdotl, float coverage, vec3 world_light, sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise,
		float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	float step_length = 28.0; // 光照步进起始步长。
	float lighting_density = 0.0; // 沿光方向累积的云密度。
	for (int i = 0; i < 5; i++, step_length *= 1.5){ // 五步，步长逐步放大。
		vec4 check_pos = gfx_cloud_set_pos(marching_pos + world_light * step_length * noise, media); // 取样点。
		lighting_density += gfx_cloud_sample_density(check_pos, media, i < 3, coverage, base_noise, detail_noise, curl_noise,
			base_scale, coverage_offset, detail_scale, detail_strength).y * step_length; // 前三步带细节，后两步省掉。
		marching_pos += world_light * step_length; // 沿光方向推进。
	}
	float hg = gfx_henyey_greenstein(vdotl, 0.7); // 前向相位，决定银边。
	float direct = exp2(-lighting_density * (cloud_pos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - media.wetness * 0.8); // 透过率乘前向相位。
	direct += (1.0 / (lighting_density * 0.2 + 1.0)) * (gfx_henyey_greenstein(vdotl, 0.2) + 0.1); // 叠一个更宽的环境项。
	direct *= hg * 2.0 + 1.0; // 银边再加强一次。
	direct *= mix(media.bottom_brightness, 0.005 + pow(cloud_density.y, media.outscatter_factor), gfx_cloud_curve(gfx_saturate(cloud_pos.w * 3.333 - 0.333))); // 云底亮度与外散射按高度混合。
	direct *= pow(max(cloud_pos.w, 0.05), 0.75); // 云顶更亮。
	vec3 cloud_color = media.light_color * (direct * media.lighting_strength.x * 36.0); // 乘直射光色与强度。
	float ambient = 1.0 - cloud_density.x; // 云越薄环境光透得越多。
	ambient *= gfx_fsqrt(cloud_pos.w); // 高处环境光更多。
	cloud_color += media.sky_color * (ambient * media.lighting_strength.y * 0.35); // 乘天光色与强度。
	cloud_color += gfx_cloud_lightning(marching_pos - media.camera_position, media, 400.0, -10.0); // 叠上闪电照亮的部分。
	return cloud_color; // 返回云的颜色。
}

// 体积云步进核心：沿视线在云层里步进，返回云的加色项与透过率；平均命中位置通过 `hit_offset` 交回。
// 为什么把空气透视留给调用方：天空散射函数属于大气效果，通用库只负责云本身的密度与光照。
vec4 gfx_cloud_layer(vec3 world_dir, gfx_cloud_media media, vec2 noise, out vec3 hit_offset,
		sampler3D base_noise, sampler3D detail_noise, sampler2D curl_noise, float cloud_samples, float cloud_quality,
		vec3 world_light, float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	vec3 ray_start = vec3(0.0, media.planet_radius + media.camera_position.y, 0.0); // 相机在行星球上的位置。
	vec2 bottom = gfx_RaySphereIntersection(ray_start, world_dir, media.planet_radius + media.altitude.x); // 与云层底的交点。
	vec2 top = gfx_RaySphereIntersection(ray_start, world_dir, media.planet_radius + media.altitude.y); // 与云层顶的交点。
	vec2 marching = media.camera_position.y > media.altitude.y ? vec2(top.x, bottom.x) : vec2(bottom.y, top.y); // 相机在云上还是云下决定进出顺序。
	vec3 marching_start = marching.x * world_dir; // 步进起点相对相机。
	vec3 marching_end = marching.y * world_dir; // 步进终点相对相机。
	float in_cloud = (1.0 - gfx_saturate((media.camera_position.y - media.altitude.y) * 0.005)) *
		(1.0 - gfx_saturate((media.altitude.x - media.camera_position.y) * 0.005)); // 相机低于云顶、高于云底的权重。
	float inner = bottom.y >= 0.0 && media.camera_position.y > media.altitude.x ? bottom.x : top.y; // 云内起点距离。
	inner = min(inner, 5000.0); // 限长避免步进过远。
	marching_start = marching_start * (1.0 - in_cloud) + media.camera_position; // 相机在云内时起点改到相机。
	marching_end = mix(marching_end, inner * world_dir, in_cloud) + media.camera_position; // 相机在云内时终点改到云内一点。
	float steps = cloud_samples - gfx_saturate(gfx_fsqrt(abs(world_dir.y)) * 1.4 - 0.4) * 8.0; // 采样数上限，越朝上步数越少。
	steps = max(floor(steps * cloud_quality), 1.0); // 乘精细度倍率，并保证至少一步。
	float step_size = 1.0 / steps; // 归一化步长。
	vec3 increment = (marching_end - marching_start) * step_size; // 每步位移。
	vec3 marching_pos = marching_start + increment * noise.x; // 起点加抖动量，减少条带。
	float marching_length = length(increment); // 每步的米制长度。
	float density_mul = media.density_option * (media.altitude.y - media.altitude.x) * step_size; // 乘层厚与归一化步长得消光系数。
	float vdotl = dot(world_dir, world_light); // 视线与光方向的夹角余弦。
	vec3 accum = vec3(0.0); // 累积的云颜色。
	float transmittance = 1.0; // 初始完全透明。
	vec3 ray_hit = vec3(0.0); // 用于估平均命中位置的加权和。
	float sum_transmit = 0.0; // 透过率权重和。
	for (int i = 0; i < int(steps); i++, marching_pos += increment){ // 逐步推进。
		vec4 cloud_pos = gfx_cloud_set_pos(marching_pos, media); // 当前云坐标。
		vec2 cloud_density = gfx_cloud_sample_density(cloud_pos, media, true, media.coverage, base_noise, detail_noise, curl_noise,
			base_scale, coverage_offset, detail_scale, detail_strength); // 采样密度，用本层云量。
		if (cloud_density.y < 1e-6) continue; // 这一步没有云就跳过。
		vec3 cloud_color = gfx_cloud_lighting(marching_pos, media, cloud_density, cloud_pos, noise.y, vdotl, media.coverage, world_light,
			base_noise, detail_noise, curl_noise, base_scale, coverage_offset, detail_scale, detail_strength); // 这一段云的光照。
		float absorption = exp2(-cloud_density.y * density_mul); // 这一段的透过率。
		accum += cloud_color * (transmittance - absorption * transmittance); // 把这一段发出并被后面吸收的部分加进来。
		ray_hit += marching_pos * transmittance; // 记录命中位置。
		sum_transmit += transmittance; // 记录权重。
		transmittance *= absorption; // 更新透过率。
		if (transmittance < 0.0001) break; // 几乎不透明就不再采样。
	}
	hit_offset = ray_hit / sum_transmit - media.camera_position; // 平均命中位置换成相机相对方向。
	return vec4(accum, transmittance); // 返回加色与透过率。
}

// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
float gfx_cloud_shadow_tex(vec2 coord, gfx_cloud_media media, vec3 world_light, float range, sampler3D base_noise,
		sampler2D curl_noise, float base_scale, float coverage_offset, float detail_scale, float detail_strength){
	coord = coord * range - (range * 0.5); // 贴图坐标换回相对相机的地表坐标。
	vec4 check_pos = vec4(coord.x + media.camera_position.x, 0.0, coord.y + media.camera_position.z, 0.0); // 取样点世界坐标。
	float thickness = media.altitude.y - media.altitude.x; // 云层厚度。
	check_pos += vec4(world_light * ((media.altitude.x + thickness * 0.25) / world_light.y), 0.25); // 投到云层下四分之一处。
	float cloud_density = gfx_cloud_sample_density(check_pos, media, false, media.coverage, base_noise, base_noise, curl_noise,
		base_scale, coverage_offset, detail_scale, detail_strength).y; // 取那一处云密度。
	check_pos += vec4(world_light * ((thickness * 0.25) / world_light.y), 0.25); // 再往上一段。
	cloud_density = max(cloud_density, gfx_cloud_sample_density(check_pos, media, false, media.coverage, base_noise, base_noise, curl_noise,
		base_scale, coverage_offset, detail_scale, detail_strength).y); // 两块取较厚的那块。
	return exp2(-cloud_density * 20.0); // 密度换成透过率。
}

#endif
