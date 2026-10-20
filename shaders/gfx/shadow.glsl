/*
通用图形库阴影模块：把世界位置投到阴影相机、压缩边缘，并用屏幕深度步进找遮挡。
调用位置：任何使用方向光阴影贴图或屏幕空间阴影的程序；本仓库由 `effects/shadow/shadow.glsl`
    与 `effects/lighting/held_light.glsl` 转发调用。
可复制示例：
    vec3 p = gfx_shadow_screen_pos(worldPos, shadowView, shadowProjection); // 不做压缩。
    vec3 q = gfx_shadow_screen_pos_distorted(worldPos, shadowView, shadowProjection, 0.9); // 边缘压缩。
    vec2 uv = gfx_distort_shadow_pos(q.xy, 0.9); // 读取端补压缩。
    float s = gfx_screen_space_shadow(viewPos, viewDir, normal, shadowDir, depthTex, dhDepthTex, projection, projectionInverse, dhInverse, pixelScale, offset, noise, true, 8, 0.85); // 手持光屏幕阴影。
设计原因与取舍：
    阴影相机矩阵、投影、深度图与压缩强度全部由调用方传入，库不读取引擎 uniform。
    深度只取一半再转零到一，与原程序一致；边缘压缩让阴影图边缘拿到更高有效分辨率。
    屏幕空间步进与远处深度图分开传入，没有远景时用近景深度占位，默认路径不依赖扩展。
*/
#ifndef GFX_SHADOW_INCLUDED
#define GFX_SHADOW_INCLUDED

// 米制距离、饱和与圆周常数来自数学模块。
#include "/gfx/math.glsl"

// 世界位置转到阴影相机视空间，并按投影缩放、把深度折半。
vec3 gfx_shadow_view_pos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection){
	vec3 shadowPos = mat3(shadowView) * worldPos + shadowView[3].xyz; // 世界位置转到阴影相机视空间。
	float scale = shadowProjection[0][0]; // 正交投影的水平缩放。
	shadowPos *= vec3(scale, scale, -scale * 0.5); // 按投影缩放，深度取半。
	return shadowPos;
}

// 投到阴影图，不做边缘压缩。
vec3 gfx_shadow_screen_pos(vec3 worldPos, mat4 shadowView, mat4 shadowProjection){
	return gfx_shadow_view_pos(worldPos, shadowView, shadowProjection) * 0.5 + 0.5; // 负一到一转成零到一。
}

// 投到阴影图并做边缘压缩，离中心越远压得越紧。
vec3 gfx_shadow_screen_pos_distorted(vec3 worldPos, mat4 shadowView, mat4 shadowProjection, float bias){
	vec3 shadowPos = gfx_shadow_view_pos(worldPos, shadowView, shadowProjection); // 先转到阴影视空间。
	float dist = length(shadowPos.xy); // 到阴影图中心的距离。
	float distortFactor = (1.0 - bias) + dist * bias; // 边缘压缩系数，中心为一。
	shadowPos.xy *= 0.95 / distortFactor; // 向内压缩，零点九五留出边界余量。
	return shadowPos * 0.5 + 0.5; // 负一到一转成零到一。
}

// 对已经算好的阴影图坐标补一次边缘压缩，读取端使用。
vec2 gfx_distort_shadow_pos(vec2 shadowPos, float bias){
	shadowPos = shadowPos * 2.0 - 1.0; // 零到一先转回负一到一。
	float dist = length(shadowPos.xy); // 到中心距离。
	float distortFactor = (1.0 - bias) + dist * bias; // 与写入端同一压缩系数。
	shadowPos *= 0.95 / distortFactor; // 同一压缩量。
	return shadowPos * 0.5 + 0.5; // 再转回零到一。
}

// 屏幕深度换米制距离：手持光的屏幕空间阴影用它判断遮挡，与场景几何同一套逆投影。
float gfx_shadow_linear_depth(float depth, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 零到一转负一到一。
	return 1.0 / (depth * projection_inverse[2][3] + projection_inverse[3][3]); // 逆投影的深度部分。
}

// 屏幕空间阴影：从表面沿光源方向在屏幕里步进，走到比射线更近的几何就判为遮挡。
// 为什么起点要沿法线抬一点：手持光源离表面很近，不抬会刚出发就打到自己，整片出现自阴影。
// 为什么用抖动：固定采样会在光斑边缘留下规则条纹，抖动后配合时间抗锯齿消除。
// 步数由调用方按画质选项给，八步与十六步对应原来的低、高质量。
float gfx_screen_space_shadow(vec3 view_pos, vec3 view_dir, vec3 normal, vec3 shadow_dir,
		sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse,
		mat4 dh_projection_inverse, float pixel_scale, vec2 offset_coord, float noise, bool has_dh, int steps, float strength){
	shadow_dir.z = max(shadow_dir.z, 1e-5); // 深度分量保证不太小，避免下列除法把射线推到无穷远。
	float ray_length = -0.04 * view_pos.z / shadow_dir.z; // 一步射线的长度，按当前深度与光源方向缩放。
	vec3 view_ray_dir = shadow_dir * ray_length; // 视空间里的射线方向。
	vec3 start = view_pos; // 射线起点就是当前表面。
	float ndotl = gfx_saturate(dot(shadow_dir, normal)); // 光源方向与法线的夹角余弦。
	float fov = atan(1.0 / projection[1][1]) * 360.0 * GFX_INV_PI; // 由投影反推视角，供偏移按视野缩放。
	start += view_ray_dir * (pixel_scale * max(0.04 / max(dot(normal, -view_dir), 0.1), 1e3)); // 沿射线先跳过一段，掠射时跳得更多。
	start += normal * (8e-3 * fov * -view_pos.z * pixel_scale / max(ndotl, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
	vec3 end = start + view_ray_dir; // 一步的终点。
	start = vec3(vec2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
	end = vec3(vec2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
	vec3 screen_ray_dir = end - start; // 这一步在裁剪空间的位移。
	screen_ray_dir.xy *= 0.5; // 横纵方向换算到零到一坐标。
	start.xy += projection[3].xy; // 补上投影的平移项。
	start.xy *= 0.5; // 裁剪空间转到零到一。
	float min_dist = gfx_shadow_linear_depth(0.7, projection_inverse); // 深度小于这个值的像素在前面，不再作为遮挡。
	float shadow = 1.0; // 可见度，初值全亮。
	float step_length = 1.0; // 步长，逐步增大。
	for (int i = 0; i < steps; i++, start += screen_ray_dir * step_length, step_length += 0.3){ // 步长递增覆盖更远。
		vec3 sample_pos = start + screen_ray_dir * noise * step_length; // 加抖动的采样位置。
		if (sample_pos.z < min_dist) break; // 已经走到相机很近的地方，后面没有可靠深度。
		sample_pos.xy = sample_pos.xy / sample_pos.z + offset_coord; // 透视除法得到屏幕坐标。
		if (gfx_saturate(sample_pos.xy) != sample_pos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。
		float sample_depth = textureLod(depth_texture, sample_pos.xy, 0.0).x; // 读该点的不透明深度。
		if (sample_depth < 0.7) break; // 近处已有几何挡住，后面不必再看。
		float sample_dist; // 采样点到相机的米制距离。
		if (has_dh && sample_depth == 1.0){ // 近景是天空时改读远景深度。
			sample_depth = textureLod(dh_depth_texture, sample_pos.xy, 0.0).x; // 改读远景深度。
			sample_dist = gfx_shadow_linear_depth(sample_depth, dh_projection_inverse); // 远景深度换成距离。
		}else{
			sample_dist = gfx_shadow_linear_depth(sample_depth, projection_inverse); // 近景深度换成距离。
		}
		if (sample_pos.z - sample_dist > 0.0){ // 射线深度超过几何深度，说明几何在前面。
			shadow = 0.0; // 记为完全遮挡。
			break; // 结束步进。
		}
	}
	return max(shadow, 1.0 - strength); // 按强度给阴影压到下限，强度零点八五时与原来的零点一五底光完全一致。
}

// 阳光的屏幕空间阴影：在屏幕里沿阳光方向步进，撞到比当前更近的几何就累加遮挡。
// 为什么叶片先用饱和放大：叶片的材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
// `fov` 由调用方按材质选择（草和叶片用较大视野估计），`absorption` 是每次遮挡的吸收量。
float gfx_sun_screen_shadow(vec3 view_pos, vec3 view_dir, vec3 normal, vec3 shadow_vector, float fov,
		float absorption, float softness, float grass, sampler2D depth_texture, sampler2D dh_depth_texture,
		mat4 projection, mat4 projection_inverse, mat4 dh_projection_inverse, float pixel_scale, float min_step,
		vec2 offset_coord, float noise, bool has_dh, int steps){
	vec3 view_ray_dir = shadow_vector * max(-view_pos.z * 3e-5 * fov, min_step); // 每一步在屏幕上的推进量。
	vec3 start = view_pos; // 步进起点。

	if (softness < 0.1){ // 普通表面才做偏移，草和叶片的画面已经足够软。
		float ndotl = gfx_saturate(dot(shadow_vector, normal)); // 阳光与法线的夹角。
		start += view_ray_dir * (pixel_scale * max(0.04 / max(dot(normal, -view_dir), 0.1), 1e3)); // 沿光线先跳过一段，避免刚出发就打到自己。
		start += normal * (8e-3 * fov * -view_pos.z * pixel_scale / max(ndotl, 0.01)); // 再沿法线抬一点，掠射角抬得更多。
	}

	vec3 end = start + view_ray_dir; // 一步的终点。
	start = vec3(vec2(projection[0][0], projection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
	end = vec3(vec2(projection[0][0], projection[1][1]) * end.xy, -end.z); // 终点同样投影。
	vec3 screen_ray_dir = end - start; // 这一步在裁剪空间的位移。
	screen_ray_dir.xy *= 0.5; // 横纵方向换算到零到一坐标。
	start.xy += projection[3].xy; // 补上投影的平移项。
	start.xy *= 0.5; // 裁剪空间转到零到一。
	start += screen_ray_dir * grass; // 草的原点再前进一小段，减少草自身投出的错误阴影。

	float shadow = 1.0; // 阴影可见度，初值全亮。
	float step_length = 1.0; // 步长，逐步增大。
	float z_thickness = 0.025 + 0.0125 * -view_pos.z; // 遮挡厚度阈值，距离越远越厚，避免远处噪点。

	for (int i = 0; i < steps; i++, start += screen_ray_dir * step_length, step_length += 0.3){ // 步长递增覆盖更远。
		vec3 sample_pos = start + screen_ray_dir * noise * step_length; // 加抖动的采样位置。
		sample_pos.xy = sample_pos.xy / sample_pos.z + offset_coord; // 透视除法得到屏幕坐标。
		if (gfx_saturate(sample_pos.xy) != sample_pos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。

		float sample_depth = textureLod(depth_texture, sample_pos.xy, 0.0).x; // 近景深度。
		float sample_dist; // 采样点到相机的米制距离。
		if (has_dh && sample_depth == 1.0){ // 近景是天空时才查远景。
			sample_depth = textureLod(dh_depth_texture, sample_pos.xy, 0.0).x; // 改读远景深度。
			sample_dist = gfx_shadow_linear_depth(sample_depth, dh_projection_inverse); // 远景深度换成距离。
		}else{
			sample_dist = gfx_shadow_linear_depth(sample_depth, projection_inverse); // 近景深度换成距离。
		}

		float depth_diff = sample_pos.z - sample_dist; // 当前射线深度与几何深度之差，为正说明几何在前面。
		if (depth_diff > 0.0 && depth_diff < z_thickness) shadow *= absorption; // 落在厚度阈值内才算遮挡。
		if (shadow < 0.01) break; // 已经足够暗，提前结束。
	}

	return shadow; // 返回可见度。
}

// 阴影图里一段视线的遮挡距离：沿线段在阴影图采样，统计被实心几何挡住的样本比例。
// `shadow_start` 与 `shadow_end` 是线段两端已经投到阴影图的坐标，`bias` 是边缘压缩强度。
// 为什么把线段长度也传进来：遮挡距离要按样本比例折算成米，调用方已经知道这段有多长。
float gfx_shadow_segment_occlusion(vec3 shadow_start, vec3 shadow_end, sampler2D shadow_texture, int steps,
		float noise, float bias, float segment_length){
	float r_steps = 1.0 / float(steps); // 采样数倒数。
	vec3 increment = (shadow_end - shadow_start) * r_steps; // 阴影图里的步进。
	vec3 position = increment * noise + shadow_start; // 起点加抖动。
	float occluded = 0.0; // 被挡住的样本数。

	for (int i = 0; i < steps; i++, position += increment){ // 沿视线段采样。
		vec3 shadow_pos = position; // 当前采样坐标。
		shadow_pos.xy = gfx_distort_shadow_pos(shadow_pos.xy, bias); // 补边缘压缩。
		if (gfx_saturate(shadow_pos.xy) == shadow_pos.xy && shadow_pos.z < 1.0){ // 落在阴影图内。
			float solid_depth = textureLod(shadow_texture, shadow_pos.xy, 0.0).x; // 读遮挡深度。
			occluded += step(solid_depth, shadow_pos.z); // 遮挡物在射线前面才算被挡。
		}
	}

	return occluded * (segment_length * r_steps); // 按样本比例折算成被遮挡的米数。
}

// 不透明表面阴影：把相机相对世界位置投到阴影相机，做可变半影与彩色半透明阴影，并算出次表面散射。
// 阴影图、矩阵、分辨率、噪声与全部选项由调用方传入；通用库不读取引擎状态。
// 为什么先做透光散射：叶片、草这类薄片本身就透光，先算透光再把阳光按透光比例削弱，阴影才不会在薄片上过硬。
// 为什么阴影图外坐标直接放弃采样：半影采样会跑出阴影图边界，硬读边界会把边界压成一条黑线。
vec3 gfx_variable_penumbra_shadow(vec3 world_pos, vec3 world_normal, float sunlight, vec3 albedo,
		float scattering_strength, float hand, float leaves, float grass, vec3 camera_position, vec3 view_axis_z,
		mat4 shadow_view, mat4 shadow_projection, sampler2D shadow_depth0, sampler2DShadow shadow_depth1,
		sampler2D shadow_color0, float shadow_map_resolution, float shadow_distance, float far_plane, float bias,
		vec2 noise, bool variable_penumbra, bool colored_shadows, bool sss_directional, float sss_brightness,
		float sss_phase, float sss_quality, float vps_quality, float vps_spread, float basic_blur, out vec3 sss){
	world_pos += camera_position; // 相机相对世界位置补上相机位置，换成阴影相机能用的世界坐标。
	world_pos -= view_axis_z * 0.5 * hand; // 手持物抬高半格，避免手贴脸时投出错误的自阴影。
	vec3 shadow_normal = mat3(shadow_view) * world_normal; // 世界法线转到阴影相机空间。
	shadow_normal.z = -shadow_normal.z; // 深度轴与视空间相反，翻转过来比较方向才正确。
	vec3 shadow_screen_pos = gfx_shadow_view_pos(world_pos, shadow_view, shadow_projection); // 世界位置按投影缩放、深度取半。
	float z_scale = 1.0 / shadow_projection[0][0]; // 深度缩放倒数，把深度差还原成实际距离。
	float dist = length(shadow_screen_pos.xy); // 到阴影图中心的距离。
	float distort_factor = (1.0 - bias) + dist * bias; // 边缘压缩系数，与坐标变换一致。
	const mat2 rot_mat = mat2(cos(2.39996322973), sin(2.39996322973), -sin(2.39996322973), cos(2.39996322973)); // 每步旋转黄金角，样本沿螺旋散开避免规则条纹。
	vec3 result = vec3(1.0); // 阴影可见度，初值全亮。
	sss = vec3(0.0); // 次表面散射初值为零。
	if (scattering_strength > 0.0){ // 只有透光材质才走散射，普通表面直接跳过整段。
		vec3 shadow_screen_pos_raw = shadow_screen_pos; // 未压缩坐标，散射采样要用。
		shadow_screen_pos_raw.xy *= 0.95 / distort_factor; // 补上与写入端一致的边缘压缩。
		shadow_screen_pos_raw = shadow_screen_pos_raw * 0.5 + 0.5; // 转成零到一纹理坐标。
		float spread = (scattering_strength * 0.12 + 0.05) / (distort_factor * shadow_distance) + basic_blur / shadow_map_resolution; // 散射采样半径：透光越强、距离越远越大，再加基础模糊。
		vec3 scattering_density = 15.0 / (scattering_strength * albedo + 0.1); // 散射密度：底色的透光通道越大越容易透过。
		float r_steps = 1.0 / sss_quality; // 次数的倒数，用来归一化半径与结果。
		float angle = noise.x * 6.28318530718; // 初始角度也取随机，避免所有像素从同一方向起步。
		vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。
		float scattering_depth = 0.0; // 累计散射深度。
		for (float i = 0.0; i < sss_quality; i++){ // 逐次采样阴影图，累计遮挡厚度。
			rot *= rot_mat; // 每步旋转黄金角。
			float radius = (i + noise.y) * r_steps; // 半径从随机相位起步，样本不重叠。
			vec2 offset = rot * spread * radius; // 当前采样偏移。
			float sample_depth = textureLod(shadow_depth0, shadow_screen_pos_raw.xy + offset, 0.0).x; // 读取该点遮挡深度。
			scattering_depth += max(shadow_screen_pos_raw.z - sample_depth, 1e-5); // 累加接收点到遮挡物的距离，最小留一点避免零。
		}
		scattering_depth *= r_steps * z_scale; // 取平均并还原成实际距离。
		vec3 scattering = exp2(-scattering_depth * scattering_density); // 厚度越大透光越弱，指数衰减。
		float dist_falloff = gfx_saturate(((min(shadow_distance, far_plane) - length(world_pos)) * 0.05 - 1.0)); // 超出阴影范围就淡出透光。
		if (sss_directional){ // 开启朝向透光时按观察角计算。
			sss = scattering * (sss_brightness * dist_falloff * (sss_phase * 0.5 + 0.15)); // 逆光方向更亮的米氏相位。
		}else{ // 关闭朝向透光时用固定亮度。
			sss = scattering * (sss_brightness * dist_falloff * 0.2); // 固定占比，不随角度变化。
		}
		scattering_strength *= dist_falloff; // 阳光也按同一淡出缩放，远处不再额外透光。
	}
	if (sunlight > 0.0){ // 没有阳光时不必采样阴影。
		shadow_screen_pos += shadow_normal * (0.002 * (1.0 - leaves) * distort_factor); // 沿法线抬一点减少自身条纹，叶片不抬以免漏光。
		shadow_screen_pos.xy *= 0.95 / distort_factor; // 补上与写入端一致的边缘压缩。
		shadow_screen_pos = shadow_screen_pos * 0.5 + 0.5; // 转成零到一纹理坐标。
		if (gfx_saturate(shadow_screen_pos.xy) == shadow_screen_pos.xy){ // 只在阴影图内采样，图外保持全亮。
			result = vec3(0.0); // 从全暗开始累加可见样本。
			float spread = vps_spread * 200.0 / (distort_factor * shadow_distance); // 半影搜索半径：随扩散选项与距离缩放。
			float avg_diff = 0.0; // 遮挡物与接收点的平均深度差，用来放大半影。
			if (variable_penumbra){ // 可变半影：先估遮挡物距离再决定边缘宽度。
				float spread_lod = log2(shadow_map_resolution / 512.0); // 按分辨率选取合适的纹理细节层级，高分辨率用更粗层级抑制噪点。
				for (int i = -1; i <= 1; i++){ // 三乘三邻域估计遮挡物距离。
					for (int j = -1; j <= 1; j++){
						vec2 lookup_coord = shadow_screen_pos.xy + vec2(i, j) * spread * 0.0039; // 邻域采样坐标。
						float depth_diff = shadow_screen_pos.z - textureLod(shadow_depth0, lookup_coord, spread_lod).x; // 接收点深度减去遮挡物深度。
						depth_diff = clamp(depth_diff * z_scale * 0.0035, 0.0, 0.025); // 归一化并限制范围。
						avg_diff += depth_diff * depth_diff; // 平方累加，后面开根得到均方根。
					}
				}
				avg_diff /= 9.0; // 求九个样本的平均。
				avg_diff = sqrt(avg_diff); // 开根得到平均深度差。
			}
			avg_diff = max(avg_diff, 0.015 * leaves + 0.01 * grass); // 叶片与草至少给一点半影，避免薄片边缘过硬。
			float sample_spread = avg_diff * 0.2 * spread + basic_blur / shadow_map_resolution; // 最终采样半径：深度差越大半影越宽，再加基础模糊。
			shadow_screen_pos.z -= (2e-6 + noise.y * 2e-6) * (dist + 0.03) * (1.0 - 0.9 * leaves) * shadow_distance; // 深度偏移随距离增大，抵消阴影图分辨率不足带来的条纹。
			float r_steps = 1.0 / vps_quality; // 次数倒数。
			float angle = noise.y * 6.28318530718; // 初始角度取随机。
			vec2 rot = vec2(cos(angle), sin(angle)); // 当前旋转方向。
			for (float i = 0.0; i < vps_quality; i++){ // 逐次采样阴影图求未遮挡比例。
				rot *= rot_mat; // 每步旋转黄金角。
				float radius = sqrt((i + noise.x) * r_steps); // 平方根半径让样本在圆面上均匀分布。
				vec2 offset = rot * radius * sample_spread; // 当前采样偏移。
				vec3 sample_coord = vec3(shadow_screen_pos.xy + offset, shadow_screen_pos.z); // 采样坐标。
				if (colored_shadows){ // 彩色阴影：半透明层用自身颜色，实心层只按遮挡。
					float translucent_shadow = step(sample_coord.z, textureLod(shadow_depth0, sample_coord.xy, 0.0).x); // 半透明阴影：深度更远即未遮挡。
					result += vec3(translucent_shadow); // 半透明部分累加可见度。
					float solid_shadow = textureLod(shadow_depth1, sample_coord, 0.0); // 实心阴影贴图：含彩色阴影的合成结果。
					vec3 shadow_color_sample = gfx_GammaToLinear(textureLod(shadow_color0, sample_coord.xy, 0.0).rgb); // 该点半透明颜色转线性。
					result += shadow_color_sample * (solid_shadow - translucent_shadow); // 实心与半透明之差乘颜色，得到彩色阴影贡献。
				}else{ // 关闭彩色阴影时只按实心遮挡。
					result += vec3(textureLod(shadow_depth1, sample_coord, 0.0)); // 直接累加可见度。
				}
			}
			result *= r_steps; // 取平均得到最终可见度。
		}
	}
	if (sss_directional){ // 开启朝向透光时，用透光比例把阴影往亮处提一点。
		return result * (gfx_saturate(0.4 - scattering_strength * 0.4) + 0.6); // 透光越强整体越亮。
	}
	return result * (gfx_saturate(0.5 - scattering_strength * 0.5) + 0.5); // 关闭时提亮幅度更小。
}

#endif
