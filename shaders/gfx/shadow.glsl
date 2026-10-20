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

#endif
