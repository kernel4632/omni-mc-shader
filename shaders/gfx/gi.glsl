/*
通用图形库全局光模块：反射阴影图反弹、历史重投影、时间滤波与空间滤波，以及环境遮蔽多弹射。
调用位置：任何需要屏幕空间全局光或环境遮蔽的程序；本仓库由 `effects/lighting/gi.glsl` 与
    `effects/lighting/gtao.glsl` 转发调用。
可复制示例：
    `vec3 rsm = gfx_gi_rsm(viewPos, normal, view, ...);` 算一次反射阴影图反弹。
    `vec4 filtered = gfx_gi_temporal_filter(coord, texel, view, ...);` 把本帧反弹与历史混合。
    `vec3 gi = gfx_gi_spatial_filter(coord, dist, normal, viewDir, view, history, 0.5);` 做七乘七空间滤波。
    `vec3 ao = gfx_ao_multi_bounce(occlusion, albedo);` 给环境遮蔽补一次多弹射。
设计原因与取舍：
    纹理、矩阵、相机位置与选项全部由调用方传入，库不读取任何引擎状态；`gfx_gi_view` 把同一帧的
    相机与屏幕参数打包，避免每个函数重复十几项。反射阴影图与时间滤波的计算顺序照原程序保留，
    只把宿主宏换成布尔参数，默认路径的画面不变。环境遮蔽的采样仍由调用方负责，这里只做纯数学。
*/
#ifndef GFX_GI_INCLUDED
#define GFX_GI_INCLUDED

#include "/gfx/math.glsl"
#include "/gfx/shadow.glsl"

// 一帧全局光需要的相机、投影与屏幕参数；字段名保持普通图形术语，不绑定任何宿主。
struct gfx_gi_view {
	mat4 projection_inverse; // 近景逆投影。
	mat4 previous_projection; // 上一帧投影。
	mat4 model_view_inverse; // 视空间转世界。
	mat4 previous_model_view; // 上一帧世界转视空间。
	mat4 model_view; // 本帧世界转视空间。
	mat4 shadow_view; // 阴影相机视图。
	mat4 shadow_projection; // 阴影相机投影。
	mat4 dh_projection_inverse; // 远景逆投影；没有远景时填近景值占位。
	mat3 shadow_normal; // 法线从世界转到阴影相机。
	vec3 camera_position; // 本帧相机世界位置。
	vec3 previous_camera_position; // 上一帧相机世界位置。
	vec2 screen_size; // 画面像素尺寸。
	vec2 texel_size; // 一个像素的屏幕坐标大小。
};

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。
vec3 gfx_ao_multi_bounce(float ao, vec3 albedo){
	vec3 a = 2.0404 * albedo - 0.3324; // 一次项系数。
	vec3 b = -4.7951 * albedo + 0.6417; // 二次项系数。
	vec3 c = 2.7552 * albedo + 0.6903; // 三次项系数。
	return max(vec3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}

// 屏幕坐标与深度还原视空间位置，不撤销抖动；重投影需要原始位置。
vec3 gfx_gi_view_pos(vec2 coord, float depth, mat4 projection_inverse){
	vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
	vec3 pos = vec3(vec2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + projection_inverse[3].xyz; // 只用逆投影的非零项。
	return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 远景屏幕坐标与深度还原视空间位置；没有远景时调用方不会走到这里。
vec3 gfx_gi_view_pos_dh(vec2 coord, float depth, mat4 dh_projection_inverse){
	vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
	vec4 pos = dh_projection_inverse * vec4(ndc, 1.0); // 远景逆投影整矩阵乘法。
	return pos.xyz / pos.w; // 透视除法。
}

// 历史法线与深度采样：四个角按法线、距离和双线性权重混合，返回未归一化的历史反弹。
vec3 gfx_gi_history_sample(vec3 curr_normal, float curr_dist, vec3 camera_velocity, vec2 prev_coord, float render_scale,
		sampler2D history_texture, sampler2D normal_texture, vec2 screen_size, out float weight_sum){
	vec2 prev_texel = floor(prev_coord); // 历史纹素整数部分。
	vec3 prev_gi = vec3(0.0); // 累积历史反弹。
	weight_sum = 0.0; // 权重和。
	for (int k = 0; k < 4; k++){ // 左下、右下、左上、右上四个历史纹素。
		vec2 sample_texel = prev_texel + vec2(float(k >> 1), float(k & 1)); // 按下标拼出四个角。
		vec4 prev_data = texelFetch(normal_texture, ivec2(sample_texel.x + render_scale * screen_size.x, sample_texel.y), 0); // 读历史法线深度。
		vec3 prev_normal = prev_data.xyz * 2.0 - 1.0; // 还原历史法线。
		float normal_weight = float(dot(curr_normal, prev_normal) > 0.5); // 法线相近才参与。
		float prev_dist = prev_data.a * 1000.0; // 历史距离。
		float depth_weight = max(abs(curr_dist - prev_dist - camera_velocity.z), 0.0); // 距离差。
		depth_weight = exp(-depth_weight / (curr_dist * 0.1 + 0.1)); // 差距越大权重越低。
		depth_weight = gfx_saturate(depth_weight * 2.0); // 放大后再收敛。
		float bilinear_weight = (1.0 - abs(prev_coord.x - sample_texel.x)) * (1.0 - abs(prev_coord.y - sample_texel.y)); // 双线性权重。
		bilinear_weight *= normal_weight * depth_weight; // 总权重。
		prev_gi += gfx_CurveToLinear(texelFetch(history_texture, ivec2(sample_texel), 0).rgb) * bilinear_weight; // 累加解码后的历史反弹。
		weight_sum += bilinear_weight; // 累加权重。
	}
	return prev_gi; // 交回加权历史反弹。
}

// 反射阴影图反弹：从阴影图里可见的表面取底色，按法线朝向与距离给当前点补一份光。
// `use_solid_shadow` 对应支持遮挡贴图的显卡，`leak_fix` 对应主世界的阳光泄漏修正，`underwater` 是眼睛在水下。
vec3 gfx_gi_rsm(vec3 view_pos, vec3 normal, gfx_gi_view view,
		sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0, sampler2D shadow_color1,
		float radius, int steps, float falloff, float shadow_map_resolution, float shadow_bias, vec2 noise,
		bool use_solid_shadow, bool leak_fix, bool underwater){
	vec3 world_pos = mat3(view.model_view_inverse) * view_pos + view.model_view_inverse[3].xyz; // 视空间位置换世界空间。
	vec3 shadow_position = gfx_shadow_screen_pos(world_pos, view.shadow_view, view.shadow_projection); // 投到阴影图。
	vec3 shadow_normal = view.shadow_normal * normal; // 法线转到阴影相机空间。
	float pixel_offset = radius * view.shadow_projection[0][0]; // 搜索半径换成阴影图像素。
	float z_scale = 1.0 / view.shadow_projection[0][0]; // 阴影深度的缩放系数。
	float gap = 2.39996322973; // 黄金角，螺旋采样均匀铺开。
	mat2 rot_mat = mat2(cos(gap), sin(gap), -sin(gap), cos(gap)); // 每次旋转黄金角。
	float angle = noise.x * 6.28318530718; // 起始旋转角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	float r_steps = 1.0 / float(steps); // 采样次数倒数。
	vec3 rsm = vec3(0.0); // 累积的反弹颜色。
	for (int i = 0; i < steps; i++){ // 螺旋逐点采样。
		rot *= rot_mat; // 每步旋转一点。
		float r = (float(i) + noise.y) * r_steps; // 归一化半径。
		vec2 offset = rot * r * pixel_offset; // 屏幕偏移。
		vec2 offset_position = shadow_position.xy + offset; // 采样点的阴影图坐标。
		vec2 sample_coord = gfx_distort_shadow_pos(offset_position, shadow_bias); // 还原压缩后的坐标。
		ivec2 sample_texel = ivec2(shadow_map_resolution * sample_coord); // 换成纹素。
		float sample_depth = use_solid_shadow ? texelFetch(shadow_depth1, sample_texel, 0).x : texelFetch(shadow_depth0, sample_texel, 0).x; // 按显卡能力选深度图。
		if (sample_depth == 0.0 || sample_depth >= 1.0) continue; // 没有几何或超出范围就跳过。
		vec3 sample_vector = vec3(offset_position, sample_depth) - shadow_position; // 采样点相对当前点。
		sample_vector *= vec3(z_scale, z_scale, -z_scale * 2.0); // 修正到统一的深度尺度。
		vec3 sample_dir = normalize(sample_vector); // 采样方向。
		float n_dot_v = dot(sample_dir, shadow_normal); // 当前点法线与采样方向的夹角余弦。
		if (n_dot_v <= 0.0) continue; // 背对采样点不接收。
		vec4 sample_data = texelFetch(shadow_color1, sample_texel, 0); // 读阴影图里的法线与天光。
		vec3 sample_normal = sample_data.rgb * 2.0 - 1.0; // 还原采样点法线。
		float sn_dot_v = dot(-sample_dir, sample_normal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
		if (sn_dot_v < 0.0) continue; // 背对方向不发光。
		vec3 sample_albedo = gfx_GammaToLinear(texelFetch(shadow_color0, sample_texel, 0).rgb); // 采样点底色转线性。
		sample_vector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
		float sample_dist = length(sample_vector); // 采样距离。
		float dist_falloff = pow(sample_dist + 0.035, -falloff) * gfx_fsqrt(1.0 - r); // 距离衰减与中心加权。
		float light_mask = leak_fix ? gfx_saturate(sample_data.a * 15.0 + float(underwater)) : 1.0; // 主世界只给接到天光或水里的点补光。
		rsm += sample_albedo * (n_dot_v * sn_dot_v * dist_falloff * light_mask); // 累加一份反弹。
	}
	rsm *= r_steps * radius * 0.1; // 平均并按半径缩放。
	return rsm; // 返回反弹颜色。
}

// 相机速度：区分远景与近景、手与世界，算出当前像素相对上一帧的屏幕位移。
vec2 gfx_gi_camera_velocity(vec2 coord, float depth, bool is_dh, float material_ids, gfx_gi_view view,
		bool disable_hand, bool disable_player, float hand_depth, float player_material){
	vec3 screen_pos = vec3(coord, depth); // 屏幕坐标加深度。
	vec3 projection = vec3(0.0); // 上一帧投影结果。
	if (is_dh){ // 远景像素用远景矩阵。
		projection = vec3(vec2(view.dh_projection_inverse[0].x, view.dh_projection_inverse[1].y) * (screen_pos * 2.0 - 1.0).xy, 0.0) + view.dh_projection_inverse[3].xyz; // 逆投影到视空间。
		projection /= view.dh_projection_inverse[2].w * (screen_pos.z * 2.0 - 1.0) + view.dh_projection_inverse[3].w; // 透视除法。
		projection = mat3(view.model_view_inverse) * projection + view.model_view_inverse[3].xyz; // 视空间转世界。
		projection += view.camera_position - view.previous_camera_position; // 加相机世界位移。
		projection = mat3(view.previous_model_view) * projection + view.previous_model_view[3].xyz; // 世界转上一帧视空间。
	}else{ // 近景像素。
		vec3 ndc = screen_pos * 2.0 - 1.0; // 转负一到一。
		projection = vec3(vec2(view.projection_inverse[0].x, view.projection_inverse[1].y) * ndc.xy, 0.0) + view.projection_inverse[3].xyz; // 逆投影到视空间。
		projection /= view.projection_inverse[2].w * ndc.z + view.projection_inverse[3].w; // 透视除法。
		bool is_player = material_ids == player_material; // 玩家像素标记。
		if (disable_hand && disable_player){ // 手和玩家都不参与重投影。
			if (depth >= 0.7 && !is_player){ // 非玩家且较远。
				projection = mat3(view.model_view_inverse) * projection + view.model_view_inverse[3].xyz; // 视空间转世界。
				projection += view.camera_position - view.previous_camera_position; // 加相机位移。
				projection = mat3(view.previous_model_view) * projection + view.previous_model_view[3].xyz; // 转上一帧视空间。
			}
		}else if (disable_hand){ // 只有手不参与。
			if (depth >= 0.7){ // 较远像素才重投影。
				projection = mat3(view.model_view_inverse) * projection + view.model_view_inverse[3].xyz; // 视空间转世界。
				projection += view.camera_position - view.previous_camera_position; // 加相机位移。
				projection = mat3(view.previous_model_view) * projection + view.previous_model_view[3].xyz; // 转上一帧视空间。
			}
		}else if (disable_player){ // 只有玩家不参与。
			if (!is_player){ // 非玩家像素。
				if (depth < 0.7) projection += (view.previous_model_view[3].xyz - view.model_view[3].xyz) * hand_depth; // 手部固定深度偏移。
				else{ // 其他近景像素正常重投影。
					projection = mat3(view.model_view_inverse) * projection + view.model_view_inverse[3].xyz; // 视空间转世界。
					projection += view.camera_position - view.previous_camera_position; // 加相机位移。
					projection = mat3(view.previous_model_view) * projection + view.previous_model_view[3].xyz; // 转上一帧视空间。
				}
			}
		}else{ // 都参与重投影。
			if (depth < 0.7) projection += (view.previous_model_view[3].xyz - view.model_view[3].xyz) * hand_depth; // 手部固定位移。
			else{ // 其他近景像素正常重投影。
				projection = mat3(view.model_view_inverse) * projection + view.model_view_inverse[3].xyz; // 视空间转世界。
				projection += view.camera_position - view.previous_camera_position; // 加相机位移。
				projection = mat3(view.previous_model_view) * projection + view.previous_model_view[3].xyz; // 转上一帧视空间。
			}
		}
	}
	projection = (vec3(view.previous_projection[0].x, view.previous_projection[1].y, view.previous_projection[2].z) * projection + view.previous_projection[3].xyz) / -projection.z * 0.5 + 0.5; // 投回上一帧屏幕坐标。
	return coord - projection.xy; // 返回屏幕位移。
}

// 全局光时间滤波：本帧反弹与历史帧按法线、深度和运动量混合，同时把法线与距离写回历史图。
vec4 gfx_gi_temporal_filter(vec2 coord, ivec2 texel_coord, gfx_gi_view view,
		sampler2D history_texture, sampler2D normal_texture, sampler2D material_texture, sampler2D depth_texture, sampler2D dh_depth_texture,
		sampler2D shadow_depth0, sampler2D shadow_depth1, sampler2D shadow_color0, sampler2D shadow_color1,
		float render_scale, bool has_dh, bool use_dh_ao, bool new_version, bool leak_fix, bool underwater,
		bool use_solid_shadow, bool disable_hand, bool disable_player, float hand_depth, float player_material,
		float radius, float falloff, int steps, float shadow_map_resolution, float shadow_bias, vec2 noise){
	vec4 prev = texelFetch(history_texture, texel_coord, 0); // 先取历史像素。
	vec2 local = coord / render_scale; // 全局光渲染分辨率下的坐标。
	if (gfx_saturate(local) == local){ // 只在有效范围内处理。
		ivec2 texel = ivec2(local * view.screen_size); // 对应的屏幕纹素。
		float curr_depth = texelFetch(depth_texture, texel, 0).x; // 本帧不透明深度。
		bool is_dh = false; // 是否远景像素。
		if (has_dh && use_dh_ao && curr_depth == 1.0){ // 天空像素改读远景深度。
			curr_depth = texelFetch(dh_depth_texture, texel, 0).x; // 远景深度。
			is_dh = true; // 标记远景。
		}
		if (curr_depth < 1.0){ // 有几何才算反弹。
			vec4 data3 = texelFetch(normal_texture, texel, 0); // 读法线光照图。
			vec3 curr_normal = gfx_DecodeNormal(data3.xy); // 解出本帧法线。
			vec3 curr_view_pos = gfx_gi_view_pos(local, curr_depth, view.projection_inverse); // 还原视空间位置。
			if (is_dh) curr_view_pos = gfx_gi_view_pos_dh(local, curr_depth, view.dh_projection_inverse); // 远景还原。
			vec3 gi = vec3(0.0); // 本帧反弹。
			bool apply_rsm = true; // 默认所有像素都反弹。
			if (new_version){ // 新版本按天光标记决定。
				if (leak_fix) apply_rsm = data3.w > 0.0 || underwater; // 只有接到天光或在水里才反弹。
			}else{ // 旧版本还要求像素足够远。
				if (leak_fix) apply_rsm = curr_depth > 0.7 && (data3.w > 0.0 || underwater); // 较远且接到天光。
				else apply_rsm = curr_depth > 0.7; // 只要求较远。
			}
			if (apply_rsm) gi = gfx_gi_rsm(curr_view_pos, curr_normal, view, shadow_depth0, shadow_depth1, shadow_color0, shadow_color1,
				radius, steps, falloff, shadow_map_resolution, shadow_bias, noise, use_solid_shadow, leak_fix, underwater); // 算一次反弹。
			float material_ids = floor(texelFetch(material_texture, texel, 0).b * 255.0); // 读材质编号。
			vec2 velocity = gfx_gi_camera_velocity(local, curr_depth, is_dh, material_ids, view, disable_hand, disable_player, hand_depth, player_material); // 屏幕位移。
			vec2 prev_coord = local - velocity; // 映射到上一帧坐标。
			vec2 clamped = clamp(prev_coord, vec2(0.0), vec2(1.0) - view.texel_size * 2.0); // 夹到画面内。
			if (clamped == prev_coord){ // 历史坐标有效才做滤波。
				vec2 prev_texel_coord = prev_coord * render_scale * view.screen_size - 0.5; // 换成历史纹素坐标。
				float curr_dist = min(-curr_view_pos.z, 1000.0); // 本帧到相机的距离，限长避免远处权重异常。
				vec3 camera_velocity = mat3(view.model_view) * (view.camera_position - view.previous_camera_position); // 相机速度转到视空间。
				float weight_sum = 0.0; // 权重和。
				vec3 prev_gi = gfx_gi_history_sample(curr_normal, curr_dist, camera_velocity, prev_texel_coord, render_scale, history_texture, normal_texture, view.screen_size, weight_sum); // 取上一帧加权历史反弹。
				gi = mix(gi, prev_gi, 0.95 * weight_sum); // 与历史混合。
			}
			prev = vec4(gfx_LinearToCurve(gi), 0.0); // 编码回历史格式。
		}
	}
	local.x -= 1.0; // 顶行左侧一格存法线与距离。
	if (gfx_saturate(local) == local){ // 只在有效范围内处理。
		ivec2 texel = ivec2(floor(local * view.screen_size)); // 对应的屏幕纹素。
		float depth = texelFetch(depth_texture, texel, 0).x; // 不透明深度。
		bool is_dh = false; // 远景标记。
		if (has_dh && use_dh_ao && depth == 1.0){ // 天空像素改读远景深度。
			depth = texelFetch(dh_depth_texture, texel, 0).x; // 远景深度。
			is_dh = true; // 标记远景。
		}
		if (depth < 1.0){ // 有几何才写历史数据。
			vec3 normal = gfx_DecodeNormal(texelFetch(normal_texture, texel, 0).xy); // 解法线。
			float dist = 1.0 / ((depth * 2.0 - 1.0) * view.projection_inverse[2][3] + view.projection_inverse[3][3]); // 深度换米制距离。
			if (is_dh) dist = 1.0 / ((depth * 2.0 - 1.0) * view.dh_projection_inverse[2][3] + view.dh_projection_inverse[3][3]); // 远景换算。
			prev = vec4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
		}else{ // 天空像素没有有效历史。
			prev = vec4(vec3(0.5), 0.0); // 写入中性值。
		}
	}
	return prev; // 返回本帧要写回历史图的数据。
}

// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
vec3 gfx_gi_spatial_filter(vec2 coord, float dist, vec3 normal, vec3 view_dir, gfx_gi_view view, sampler2D history_texture, float render_scale){
	const vec2 offset[49] = vec2[49]( // 七乘七邻域偏移表。
	vec2(-3.0, -3.0), vec2(-2.0, -3.0), vec2(-1.0, -3.0), vec2(0.0, -3.0), vec2(1.0, -3.0), vec2(2.0, -3.0), vec2(3.0, -3.0),
	vec2(-3.0, -2.0), vec2(-2.0, -2.0), vec2(-1.0, -2.0), vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(2.0, -2.0), vec2(3.0, -2.0),
	vec2(-3.0, -1.0), vec2(-2.0, -1.0), vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(2.0, -1.0), vec2(3.0, -1.0),
	vec2(-3.0,  0.0), vec2(-2.0,  0.0), vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), vec2(2.0,  0.0), vec2(3.0,  0.0),
	vec2(-3.0,  1.0), vec2(-2.0,  1.0), vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0), vec2(2.0,  1.0), vec2(3.0,  1.0),
	vec2(-3.0,  2.0), vec2(-2.0,  2.0), vec2(-1.0,  2.0), vec2(0.0,  2.0), vec2(1.0,  2.0), vec2(2.0,  2.0), vec2(3.0,  2.0),
	vec2(-3.0,  3.0), vec2(-2.0,  3.0), vec2(-1.0,  3.0), vec2(0.0,  3.0), vec2(1.0,  3.0), vec2(2.0,  3.0), vec2(3.0,  3.0));
	vec2 local = coord * render_scale; // 全局光分辨率下的坐标。
	float weights = 0.0; // 权重和。
	vec3 gi = vec3(0.0); // 累积的反弹颜色。
	float clamped_dist = min(dist, 1000.0); // 距离限长。
	float b = clamped_dist * 0.001 + 0.025; // 深度阈值里的中间量。
	float depth_threshold = min(0.1 + clamped_dist * 0.05, 1.1) + gfx_saturate(1.0 - abs(dot(normal, view_dir)) / b) * 10.0; // 掠射角放宽深度阈值。
	vec2 border = vec2(render_scale) - view.texel_size * 2.0; // 边界。
	vec2 offset_scale = view.texel_size * 4.0 * render_scale; // 邻域步长。
	for (int i = 0; i < 49; i++){ // 遍历四十九个邻点。
		vec2 sample_coord = clamp(local + offset[i] * offset_scale, vec2(0.0), border); // 采样坐标。
		float weight = length(offset[i]); // 按到中心的距离算权重。
		weight = exp2(-weight * weight * 0.1); // 高斯权重。
		vec4 sample_data = textureLod(history_texture, sample_coord + vec2(render_scale, 0.0), 0.0); // 读历史法线深度。
		vec3 sample_normal = sample_data.xyz * 2.0 - 1.0; // 还原法线。
		float normal_weight = abs(dot(normal, sample_normal)); // 法线相近度。
		normal_weight = pow(normal_weight, 64.0); // 高次方只保留很接近的。
		float depth_weight = gfx_saturate(-abs(sample_data.w * 1000.0 - clamped_dist) + depth_threshold); // 深度相近度。
		weight = weight * normal_weight * depth_weight + 1e-20; // 总权重，加极小值避免全零。
		gi += gfx_CurveToLinear(textureLod(history_texture, sample_coord, 0.0).rgb) * weight; // 累加解码后的反弹。
		weights += weight; // 累加权重。
	}
	return gfx_LinearToCurve(gi / weights); // 平均后编码返回。
}

#endif
