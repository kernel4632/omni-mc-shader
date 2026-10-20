/*
通用图形库反射模块：可见法线分布的采样。
调用位置：任何需要按粗糙度生成反射方向的程序；本仓库由 `effects/reflection/screenspace.glsl` 转发调用。
可复制示例：
    vec3 d = gfx_sample_ggx_vndf(viewVector, roughness, noise); // 生成一条模糊反射方向。
设计原因与取舍：
    只做纯数学，不读取深度、屏幕尺寸或反射画面；追踪与合成由调用方负责。
    公式照原程序保留，只把圆周常数换成库内常数。
*/
#ifndef GFX_REFLECTION_INCLUDED
#define GFX_REFLECTION_INCLUDED

#include "/gfx/math.glsl"

#define GFX_TAU 6.28318530718 // 一个完整圆周。

// 可见法线分布采样：按粗糙度把反射方向散开，得到模糊反射。
vec3 gfx_sample_ggx_vndf(vec3 viewVector, float roughness, vec2 noise){
	vec3 orthoNormal = normalize(vec3(roughness * viewVector.xy, viewVector.z)); // 把视线按粗糙度压成一个辅助轴。
	float length2 = dot(orthoNormal.xy, orthoNormal.xy); // 水平分量的长度平方。
	vec3 orthoTangent = length2 > 0.0 ? vec3(-orthoNormal.y, orthoNormal.x, 0.0) * inversesqrt(length2) : vec3(1.0, 0.0, 0.0); // 水平切线。
	vec3 orthoBitangent = cross(orthoNormal, orthoTangent); // 副切线。
	float radius = sqrt(noise.y * 0.7); // 采样半径，取平方根让样本落在圆内。
	float angle = GFX_TAU * noise.x; // 采样角度。
	vec2 samplePos = vec2(cos(angle), sin(angle)) * radius; // 圆上的采样位置。
	float scaling = orthoNormal.z * 0.5 + 0.5; // 沿竖直方向把圆压成椭圆。
	samplePos.y = (1.0 - scaling) * sqrt(1.0 - samplePos.x * samplePos.x) + scaling * samplePos.y; // 投影到椭圆上。
	vec3 sampleVector = samplePos.x * orthoTangent + samplePos.y * orthoBitangent + sqrt(max(0.0, 1.0 - dot(samplePos, samplePos))) * orthoNormal; // 合成三维方向。
	return normalize(vec3(roughness * sampleVector.xy, max(sampleVector.z, 0.0))); // 按粗糙度压扁并归一化。
}

// 屏幕坐标与深度还原视空间位置；屏幕空间追踪算射线起点与命中点时用。
vec3 gfx_reflection_view_pos(vec2 coord, float depth, mat4 projection_inverse){
	vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
	vec3 pos = vec3(vec2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + projection_inverse[3].xyz; // 只用逆投影的非零项。
	return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 视空间位置投到屏幕，不补抖动；追踪射线用原始投影。
vec3 gfx_reflection_screen_pos(vec3 view_pos, mat4 projection){
	vec3 pos = vec3(projection[0][0], projection[1][1], projection[2][2]) * view_pos + projection[3].xyz; // 投影矩阵的非零项。
	return pos * (0.5 / -view_pos.z) + 0.5; // 透视除法并转到零到一。
}

// 屏幕深度换米制距离。
float gfx_reflection_linear_depth(float depth, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 零到一转负一到一。
	return 1.0 / (depth * projection_inverse[2][3] + projection_inverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度。
float gfx_reflection_screen_depth(float depth, mat4 projection_inverse){
	depth = (1.0 / depth - projection_inverse[3][3]) / projection_inverse[2][3]; // 解出负一到一深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景深度换成同一距离在近景投影下的深度。
float gfx_reflection_dh_to_screen_depth(float depth, mat4 dh_projection_inverse, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 远景深度转到负一到一。
	depth = 1.0 / (depth * dh_projection_inverse[2][3] + dh_projection_inverse[3][3]); // 先换成米。
	depth = (1.0 / depth - projection_inverse[3][3]) / projection_inverse[2][3]; // 再用近景投影换回深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// 读追踪采样点的深度：手部优先手部图，近景是天空时按开关改读远景。
float gfx_reflection_sample_depth(vec2 coord, bool is_hand, bool hand_supported, sampler2D depth_texture, sampler2D hand_depth_texture,
		sampler2D dh_depth_texture, bool has_dh, bool dh_ssr, mat4 dh_projection_inverse, mat4 projection_inverse){
	if (hand_supported && is_hand) return textureLod(hand_depth_texture, coord, 0.0).x; // 手部读不含玩家的深度。
	float depth = textureLod(depth_texture, coord, 0.0).x; // 其他像素读普通不透明深度。
	if (has_dh && dh_ssr && depth == 1.0) depth = gfx_reflection_dh_to_screen_depth(textureLod(dh_depth_texture, coord, 0.0).x, dh_projection_inverse, projection_inverse); // 远景深度换到近景尺度。
	return depth; // 返回该坐标的深度。
}

// 屏幕空间追踪：从起点沿反射方向在屏幕里步进，撞到比射线更近的几何就命中。
// 命中后二分细化，避免粗步长跨过薄几何；屏幕外的方向没有可靠深度，直接停止。
bool gfx_screen_space_trace(vec3 view_ray_ori, vec3 view_ray_dir, float ndotv, float noise, float min_length, bool is_hand, inout vec3 screen_pos,
		sampler2D depth_texture, sampler2D hand_depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse,
		mat4 dh_projection_inverse, float near_plane, bool hand_supported, bool has_dh, bool dh_ssr, int quality, int refinement_steps, float z_diff_threshold){
	float r_steps = 1.0 / float(quality); // 步数的倒数，用作归一化步长。
	float view_ray_length = (-near_plane - view_ray_ori.z) / view_ray_dir.z + step(view_ray_dir.z, 0.0) * 1e20; // 射线到近裁剪面的长度，背向时给极远值。
	vec3 ray_dir = normalize(gfx_reflection_screen_pos(view_ray_ori + view_ray_dir * view_ray_length, projection) - screen_pos); // 屏幕坐标下的射线方向。
	float min_step_length = min_length * r_steps; // 最小步长按质量缩放。
	float step_length = mix(min_step_length, r_steps, ndotv); // 正对视线时步长更大，掠射时更小。
	float z_scaling = abs(1.0 / ray_dir.z); // 深度方向的缩放。
	bool hit = false; // 命中标记。
	float max_depth = has_dh ? gfx_reflection_screen_depth(gfx_reflection_linear_depth(1.0, dh_projection_inverse), projection_inverse) : 1.0; // 有远景时步进上限是远景最远距离。
	screen_pos += ray_dir * step_length * noise; // 起点按噪声抖动，减少规则条纹。
	float depth = gfx_reflection_sample_depth(screen_pos.xy, false, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 读起始点深度。
	for (int i = 0; i < quality + 3; i++){ // 最多走质量加三次，多出的几次用于边界收尾。
		if (gfx_saturate(screen_pos.xy) != screen_pos.xy) break; // 出了屏幕就停止。
		if (screen_pos.z >= max_depth){ // 射线到达最远处。
			hit = depth >= max_depth; // 该处也是尽头才算命中。
			break;
		}else if (screen_pos.z < 0.7 && !is_hand){ // 射线跑到相机很近的地方，后面没有可靠深度。
			break;
		}
		if (depth < screen_pos.z){ // 几何深度比射线更近，说明可能撞上几何。
			vec3 refine_dir = ray_dir * step_length * 0.5; // 细化步长，从半步开始逐次减半。
			for (int j = 0; j < refinement_steps; j++, refine_dir *= 0.5){ // 二分细化交点。
				screen_pos += refine_dir * (step(screen_pos.z, depth) * 2.0 - 1.0); // 越过就回退半步，没越过就前进半步。
				depth = gfx_reflection_sample_depth(screen_pos.xy, is_hand, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 重读该点深度。
			}
			if (depth > screen_pos.z) continue; // 细化后几何又跑到后面，这一步不算命中。
			float step_dist = gfx_reflection_linear_depth(screen_pos.z, projection_inverse); // 射线点的米制距离。
			float sample_dist = gfx_reflection_linear_depth(depth, projection_inverse); // 几何点的米制距离。
			float dist_diff = abs(sample_dist - step_dist) / step_dist; // 两点的相对深度差。
			if (dist_diff < z_diff_threshold && screen_pos.z > 0.0 && screen_pos.z < max_depth){ // 差足够小且深度有效才算命中。
				hit = true;
				break;
			}
		}
		step_length = clamp(abs(depth - screen_pos.z) * z_scaling, min_step_length, r_steps); // 按深度差自适应下一步长度。
		screen_pos += ray_dir * step_length; // 前进一步。
		depth = gfx_reflection_sample_depth(screen_pos.xy, false, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 读新位置的深度。
	}
	return hit; // 返回是否命中。
}

// 把反射颜色按菲涅耳、金属度与水吸收混进场景色；`not_total` 为假时是全反射像素，直接取反射色。
void gfx_specular_reflection_mix(inout vec3 color, vec3 view_dir, vec3 normal, vec3 albedo, float water_absorption, vec3 reflection,
		bool not_total, float metalness, float roughness, float f0, float reflection_strength, bool overworld){
	if (!not_total){ // 全反射像素直接取反射色。
		color = reflection; // 表面看不到外面的东西。
		return;
	}
	reflection *= mix(vec3(1.0), albedo, vec3(metalness)); // 金属面用底色给反射染色。
	vec3 l = normalize(reflect(view_dir, normal) + normal * roughness); // 反射方向按粗糙度偏一点。
	vec3 h = normalize(l - view_dir); // 反射方向与视线的半程。
	float l_dot_h = gfx_saturate(dot(l, h)); // 反射与半程夹角。
	float n_dot_l = gfx_saturate(dot(normal, l)); // 反射方向的入射余弦。
	float n_dot_v = gfx_saturate(dot(normal, -view_dir)); // 视线方向的入射余弦。
	float specular = gfx_F_Schlick(l_dot_h, f0, 1.0); // 菲涅耳。
	specular *= gfx_V_Schlick(n_dot_l, n_dot_v + 0.8, roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
	specular *= reflection_strength; // 乘材质允许的反射强度。
	specular = mix(specular, 1.0, metalness); // 金属面反射权重拉满。
	vec3 temp = color; // 记下原底色，金属面要再加一份。
	float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
	diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
	specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。
	if (overworld){ // 主世界按水吸收缩反射权重。
		color = mix(color, reflection, gfx_saturate(specular * water_absorption)); // 混合反射。
		color += temp * (metalness * water_absorption); // 金属面再加一份底色。
	}else{ // 下界末地按反射权重混合。
		color = mix(color, reflection, gfx_saturate(specular)); // 混合反射。
		color += temp * metalness; // 金属面再加一份底色。
	}
}

#endif
