/*
通用图形库视差模块：在地表材质的高度图上沿视线找可见交点，并算视差自阴影与法线。
调用位置：任何使用方块图集高度图做视差的几何片元程序；本仓库由 `effects/ground/parallax.glsl` 调用。
可复制示例：
    `ivec2 texel = gfx_parallax_smooth(coord, tbn, light, duv1, duv2, viewPos, normals, atlas, 16.0, true, 40, 12, 20, true, true, false, 0.0, 1, normal, shadow);`
    `ivec2 texel = gfx_parallax_sharp(coord, tbn, light, duv1, duv2, viewPos, normals, atlas, 16.0, true, 40, 20, true, true, false, 0.0, 1, normal, shadow);`
设计原因与取舍：
    方块图集、高度图、切线基、视线位置、分辨率与全部画质参数由调用方传入，库不读取任何引擎状态。
    平滑模式用双线性高度采样加二分细化，锐利模式逐像素穿越图块；两种外观差别明显，所以保留两套函数。
    高度为零表示没有视差数据，统一补成完整高度，避免出现空洞。
*/
#ifndef GFX_PARALLAX_INCLUDED
#define GFX_PARALLAX_INCLUDED

#include "/gfx/math.glsl"

// 双线性高度采样：在图块内跨格子读四角高度并插值，越界处用一层薄壳把空隙补平。
// `tiles_base_texel` 是图块左上角在图集里的像素坐标，`resolution_mask` 是图块边长的按位掩码。
// `is_block` 表示是否按方块图集回绕：地形恒为真，实体由调用方判断。
float gfx_parallax_height_bilinear(sampler2D normals, vec2 coord, ivec2 tiles_base_texel,
		float texture_resolution, int resolution_mask, bool is_block){
	ivec2 texel_x = ivec2(floor(coord)); // 左下角像素。
	ivec2 texel_w = texel_x + 1; // 右上角像素。
	vec2 fraction = coord - vec2(texel_x); // 到左下角的小数偏移。
	if (is_block){ // 方块图集按图块回绕。
		texel_x = tiles_base_texel + (texel_x & resolution_mask); // 左下角回绕到本图块内。
		texel_w = tiles_base_texel + (texel_w & resolution_mask); // 右上角同理。
	}
	vec4 heights = vec4(texelFetch(normals, texel_x, 0).a, // 左下角高度。
		texelFetch(normals, ivec2(texel_w.x, texel_x.y), 0).a, // 右下角高度。
		texelFetch(normals, ivec2(texel_x.x, texel_w.y), 0).a, // 左上角高度。
		texelFetch(normals, texel_w, 0).a); // 右上角高度。
	heights += gfx_saturate(1.0 - heights * 1e20); // 高度为零表示没有视差数据，补成完整高度，避免出现空洞。
	return mix(mix(heights.x, heights.y, fraction.x), // 先沿横轴插值两对。
		mix(heights.z, heights.w, fraction.x), // 再沿横轴插值另外两对。
		fraction.y); // 最后沿纵轴插值得到高度。
}

// 用高度差直接生成法线：平滑模式可以只用高度场求梯度，得到与视差一致的法线。
// `mode` 为二时用中心差分，否则用带边缘压平的梯度；两种曲线照原程序保留。
vec3 gfx_parallax_height_normal(sampler2D normals, vec2 coord, ivec2 tiles_base_texel,
		float texture_resolution, int resolution_mask, bool is_block, float depth, int mode){
	coord -= 0.5; // 把坐标移到像素中心。
	ivec2 texel_x = ivec2(floor(coord)); // 左下角像素。
	ivec2 texel_w = texel_x + 1; // 右上角像素。
	vec2 fraction = coord - vec2(texel_x); // 小数偏移。
	if (is_block){ // 方块图集按图块回绕。
		texel_x = tiles_base_texel + (texel_x & resolution_mask); // 左下角回绕。
		texel_w = tiles_base_texel + (texel_w & resolution_mask); // 右上角同理。
	}
	vec4 heights = vec4(texelFetch(normals, texel_x, 0).a, // 四角高度。
		texelFetch(normals, ivec2(texel_w.x, texel_x.y), 0).a,
		texelFetch(normals, ivec2(texel_x.x, texel_w.y), 0).a,
		texelFetch(normals, texel_w, 0).a);
	if (mode == 2){ // 平滑模式：直接由四角高度差得到梯度。
		heights.w = heights.y + heights.z - heights.x - heights.w; // 把四角合成一个中心差分量。
		return vec3(heights.w * fraction.yx + (heights.x - heights.yz), (8.0 / depth) / texture_resolution); // 梯度乘深度再归一化，深度越大法线越陡。
	}
	const float eps = 0.01; // 靠近像素边缘时梯度会突变，用一个小阈值把它压平。
	fraction -= 0.5; // 偏移改到像素中心附近。
	float dx = mix(heights.x - heights.y, heights.z - heights.w, gfx_saturate(fraction.y * 1e20)) * gfx_saturate((eps - abs(fraction.x)) * 1e20); // 横向梯度，越靠边越弱。
	float dy = mix(heights.x - heights.z, heights.y - heights.w, gfx_saturate(fraction.x * 1e20)) * gfx_saturate((eps - abs(fraction.y)) * 1e20); // 纵向梯度同理。
	return vec3(dx, dy, step(abs(dx) + abs(dy), 0.0)); // 没有梯度的地方朝外。
}

// 锐利模式的命中法线处理：按「由凹凸生成法线」的取值决定是否换回贴图法线或远处淡出。
vec3 gfx_parallax_hit_normal(sampler2D normals, ivec2 parallax_texel, vec3 hit_normal, float fade,
		bool fade_enabled, int based_normal){
	if (based_normal == 1){ // 仅侧面：只有步进里命中侧面时才用视差法线。
		if (fade_enabled){ // 远处淡出到贴图法线。
			hit_normal = mix(gfx_DecodeNormalTex(texelFetch(normals, parallax_texel, 0).rgb), hit_normal, fade * (1.0 - hit_normal.z));
		}else if (hit_normal.z == 1.0){ // 没命中侧面时用贴图法线。
			hit_normal = gfx_DecodeNormalTex(texelFetch(normals, parallax_texel, 0).rgb);
		}
	}else if (based_normal == 2 && fade_enabled){ // 全部用视差法线且需淡出时。
		hit_normal = mix(vec3(0.0, 0.0, 1.0), hit_normal, fade); // 远处淡出到朝外法线。
	}
	return hit_normal; // 交回处理后的法线。
}

// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
// `tbn` 是切线基，`shadow_vector` 是视空间阳光方向，`duv1`、`duv2` 是纹理坐标的屏幕导数。
ivec2 gfx_parallax_smooth(vec2 coord, mat3 tbn, vec3 shadow_vector, vec2 duv1, vec2 duv2, vec3 view_pos,
		sampler2D normals, vec2 atlas_size, float texture_resolution, bool is_block,
		float depth, int quality, int refinements, int shadow_quality, bool shadow_enabled, bool taa,
		bool fade_enabled, float dither, int based_normal, inout vec3 normal_tex, inout float parallax_shadow){
	vec2 atlas_tiles = atlas_size / texture_resolution; // 图集里横纵各有多少个图块。
	float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
	if (fade_enabled){ // 需要淡出时先算这一处的淡出因子。
		vec2 duv_max = max(abs(duv1), abs(duv2)) * atlas_tiles; // 纹理坐标的屏幕变化量换成图块单位。
		fade = gfx_saturate(pow(max(duv_max.x, duv_max.y), -0.1) * (1.0 / 1.4)); // 像素越小越淡出，避免远处闪烁。
	}
	vec2 tiles_base_coord = floor(coord * atlas_tiles); // 当前坐标落在哪个图块。
	ivec2 tiles_base_texel = ivec2(tiles_base_coord * texture_resolution); // 该图块左上角的像素坐标。
	int resolution_mask = int(texture_resolution) - 1; // 图块边长减一，用作回绕掩码。
	vec3 parallax_coord = vec3(coord * atlas_size, 1.0); // 换成图集像素坐标并把深度放到一。
	float sample_height = gfx_parallax_height_bilinear(normals, parallax_coord.xy - 0.5, tiles_base_texel,
		texture_resolution, resolution_mask, is_block); // 先读起始高度。
	if (sample_height > 0.0 && sample_height < 1.0){ // 只有处在表面内部的像素才需要偏移。
		parallax_coord.xy -= 0.5; // 坐标移到像素中心。
		vec3 view_vector = normalize(view_pos) * tbn; // 视线方向转到切线空间。
		view_vector /= -view_vector.z; // 归一化到单位深度步长。
		vec3 step_dir = view_vector / float(quality); // 每一步的方向。
		step_dir.xy *= texture_resolution * depth * 0.25; // 横向步长按图块尺寸与深度缩放。
		float step_length = 2.0 / float(quality); // 逐步加深的初始步长。
		for (int i = 0; i < quality; i++, step_length += 2.0 / float(quality)){ // 线性步进找交点。
			parallax_coord += step_dir * step_length; // 前进一小步。
			sample_height = gfx_parallax_height_bilinear(normals, parallax_coord.xy, tiles_base_texel,
				texture_resolution, resolution_mask, is_block); // 读这一步的高度。
			if (sample_height > parallax_coord.z) break; // 表面高度超过步进深度就找到了交点。
		}
		for (int i = 0; i < refinements; i++){ // 二分细化交点。
			if (sample_height > parallax_coord.z){ // 越过交点就回退半步。
				parallax_coord -= step_dir * step_length; // 回退。
				step_length *= 0.5; // 步长减半。
			}
			parallax_coord += step_dir * step_length; // 再前进一个更小的步。
			sample_height = gfx_parallax_height_bilinear(normals, parallax_coord.xy, tiles_base_texel,
				texture_resolution, resolution_mask, is_block); // 读高度。
		}
		if (sample_height <= parallax_coord.z) parallax_coord += step_dir * step_length * 2.0; // 最后仍未越界就多走两步，避免停在表面下。
		if (shadow_enabled && parallax_shadow > 0.0){ // 只有原先允许受光的像素才算阴影。
			vec3 shadow_dir = shadow_vector * tbn; // 阳光方向转到切线空间。
			shadow_dir /= shadow_dir.z * 0.9 + 0.1; // 归一化到单位深度步长，避免水平方向过大。
			vec3 shadow_coord = parallax_coord; // 从交点出发。
			vec3 step_size = shadow_dir / float(shadow_quality); // 阴影步进方向。
			step_size.xy *= texture_resolution * depth * 0.25; // 横向步长按图块与深度缩放。
			if (taa) shadow_coord += step_size * dither; // 开时间抗锯齿时用蓝噪声抖动起点。
			else shadow_coord += step_size; // 不开时只多走一步。
			for (int i = 0; i < shadow_quality; i++, shadow_coord += step_size){ // 沿光方向步进找遮挡。
				if (shadow_coord.z > 1.0) break; // 超出表面顶部就不再遮挡。
				sample_height = gfx_parallax_height_bilinear(normals, shadow_coord.xy, tiles_base_texel,
					texture_resolution, resolution_mask, is_block); // 读遮挡候选的高度。
				float diff = shadow_coord.z - sample_height; // 光线高度减去表面高度，负得越多遮挡越强。
				parallax_shadow *= gfx_saturate(diff * 40.0 + 1.0); // 逐步累积遮蔽。
				if (parallax_shadow < 0.003) break; // 已经足够黑就提前结束。
			}
			if (fade_enabled) parallax_shadow = mix(1.0, parallax_shadow, fade); // 远处淡出阴影，避免闪烁。
		}
		parallax_coord.xy += 0.5; // 坐标移回像素角。
		if (based_normal == 2) normal_tex = gfx_parallax_height_normal(normals, parallax_coord.xy,
			tiles_base_texel, texture_resolution, resolution_mask, is_block, depth, 2); // 由高度场求法线。
		parallax_coord.xy = (fract(parallax_coord.xy / texture_resolution) + tiles_base_coord) * texture_resolution; // 把偏移后的坐标折回原本的图块。
	}
	ivec2 parallax_texel = ivec2(parallax_coord.xy); // 最终要采样到的像素。
	if (based_normal < 2){ // 不是全部用视差法线时，照常从法线贴图取。
		normal_tex = gfx_DecodeNormalTex(texelFetch(normals, parallax_texel, 0).rgb); // 解出切线空间法线。
	}else if (fade_enabled){ // 全部用视差法线时按淡出因子回落到朝外法线。
		normal_tex = mix(vec3(0.0, 0.0, 1.0), normal_tex, fade); // 远处淡出到朝外法线。
	}
	return parallax_texel; // 交回被遮挡后的采样像素。
}

// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
ivec2 gfx_parallax_sharp(vec2 coord, mat3 tbn, vec3 shadow_vector, vec2 duv1, vec2 duv2, vec3 view_pos,
		sampler2D normals, vec2 atlas_size, float texture_resolution, bool is_block,
		float depth, int quality, int shadow_quality, bool shadow_enabled, bool fade_enabled,
		int based_normal, inout vec3 hit_normal, inout float parallax_shadow){
	vec2 atlas_tiles = atlas_size / texture_resolution; // 图集里横纵各有多少个图块。
	vec2 pixel_coord = coord * atlas_size; // 当前坐标换算成图集像素。
	ivec2 parallax_texel = ivec2(floor(pixel_coord)); // 起始像素。
	int resolution_mask = int(texture_resolution) - 1; // 图块边长减一，用作回绕掩码。
	float fade = 1.0; // 远处淡出因子，未开淡出时不参与。
	if (fade_enabled){ // 需要淡出时先算这一处的淡出因子。
		vec2 duv_max = max(abs(duv1), abs(duv2)) * atlas_tiles; // 纹理坐标的屏幕变化量换成图块单位。
		fade = gfx_saturate(pow(max(duv_max.x, duv_max.y), -0.4) * 0.2); // 像素越小越淡出。
	}
	float sample_height = texelFetch(normals, parallax_texel, 0).a; // 起始高度。
	sample_height += gfx_saturate(1.0 - sample_height * 1e20); // 高度为零时补成完整高度。
	bool exit = false; // 是否命中了表面。
	if (sample_height > 0.0 && sample_height < 1.0){ // 只有处在表面内部才穿越。
		ivec2 tiles_pixel_base = ivec2(floor(coord * atlas_tiles) * texture_resolution); // 当前图块左上角的像素。
		vec3 view_vector = normalize(view_pos) * tbn; // 视线方向转到切线空间。
		vec3 step_dir = normalize(vec3(view_vector.xy * depth * texture_resolution * 0.25, -view_vector.z)); // 每像素前进方向，横向按深度缩放。
		vec2 ardir = abs(1.0 / step_dir.xy); // 每走一个像素在横纵方向各需要多远。
		ivec2 sdir = (floatBitsToInt(step_dir.xy) >> 31) * 2 + 1; // 横纵方向的符号，用位运算取正负一。
		vec2 total_step = (vec2(sdir) * (0.5 - (pixel_coord - vec2(parallax_texel))) + 0.5) * ardir; // 到下一个像素边界的距离。
		float step_length = 0.0; // 这一步走过的深度。
		float step_height = 1.0; // 这一步光线所在的高度。
		float prev_step_height = 1.0; // 上一步高度，用于判断交点落在哪一列。
		ivec2 step_next = ivec2(0); // 这一步往哪个方向跨像素。
		for (int i = 0; i < quality; i++){ // 逐像素前进。
			step_length = min(total_step.x, total_step.y); // 先碰到哪一侧边界就按哪一侧走。
			step_height = 1.0 - step_length * step_dir.z; // 这一步光线到达的高度。
			if (sample_height > step_height){ // 表面高过光线，说明这一段遮挡了像素。
				if (sample_height > prev_step_height){ // 交点落在上一步与这一步之间时用上一步的法线。
					hit_normal = vec3(-step_next * sdir, 0.0); // 由跨步方向估计侧面法线。
					sample_height = prev_step_height; // 高度取上一步，便于后续阴影。
				}
				exit = true; // 标记命中。
				break; // 结束步进。
			}
			step_next = (floatBitsToInt(vec2(step_length) - total_step) >> 31) + 1; // 判断这一步跨的是哪一侧。
			parallax_texel += step_next * sdir; // 前进到下一个像素。
			total_step += vec2(step_next) * ardir; // 累加边界距离。
			prev_step_height = step_height; // 记下这一步高度。
			if (is_block) parallax_texel = tiles_pixel_base + (parallax_texel & resolution_mask); // 方块图集折回本图块。
			sample_height = texelFetch(normals, parallax_texel, 0).a; // 读新像素的高度。
			sample_height += gfx_saturate(1.0 - sample_height * 1e20); // 高度为零时补成完整高度。
		}
		if (shadow_enabled){ // 需要自阴影时。
			vec3 shadow_dir = shadow_vector * tbn; // 阳光方向转到切线空间。
			float shadow = 1.0; // 阴影透过率从全透开始。
			if (dot(shadow_dir, hit_normal) * parallax_shadow > 0.0 && exit){ // 命中的侧面朝向阳光才需要阴影。
				float curr_height = sample_height; // 当前高度。
				step_length = (1.0 - curr_height) / step_dir.z; // 先走到表面顶部。
				vec2 shadow_coord_2d = pixel_coord + step_length * step_dir.xy; // 到达顶部时的像素坐标。
				ivec2 shadow_texel = ivec2(floor(shadow_coord_2d)); // 取整。
				step_dir = normalize(vec3(shadow_dir.xy * depth * texture_resolution * 0.25, shadow_dir.z)); // 换成沿光方向的前进方向。
				vec2 ardir_shadow = abs(1.0 / step_dir.xy); // 每像素的边界距离。
				ivec2 sdir_shadow = (floatBitsToInt(step_dir.xy) >> 31) * 2 + 1; // 方向符号。
				total_step = (vec2(sdir_shadow) * (0.5 - (shadow_coord_2d - shadow_texel)) + 0.5) * ardir_shadow; // 到下一像素边界的距离。
				step_next = ivec2(0); // 复位跨步方向。
				for (int i = 0; i < shadow_quality; i++){ // 沿光方向逐像素找遮挡。
					step_length = min(total_step.x, total_step.y); // 先碰到的边界。
					step_height = curr_height + step_length * step_dir.z; // 这一步的高度。
					step_next = (floatBitsToInt(vec2(step_length) - total_step) >> 31) + 1; // 跨哪一侧。
					shadow_texel += step_next * sdir_shadow; // 前进到下一个像素。
					total_step += vec2(step_next) * ardir_shadow; // 累加边界距离。
					if (is_block) shadow_texel = tiles_pixel_base + (shadow_texel & resolution_mask); // 方块图集折回本图块。
					sample_height = texelFetch(normals, shadow_texel, 0).a; // 读高度。
					sample_height += gfx_saturate(1.0 - sample_height * 1e20); // 高度为零时补成完整高度。
					if (sample_height > step_height){ // 表面高过光线，说明被遮挡。
						parallax_shadow = 0.0; // 直接判为阴影。
						break; // 结束。
					}
				}
				parallax_shadow *= fade_enabled ? mix(1.0, shadow, fade) : shadow; // 远处淡出阴影，未开淡出时原样。
			}
		}
		hit_normal = gfx_parallax_hit_normal(normals, parallax_texel, hit_normal, fade, fade_enabled, based_normal); // 命中后按当前模式处理法线。
	}else if (based_normal == 1){ // 没命中侧面就退回贴图法线。
		hit_normal = gfx_DecodeNormalTex(texelFetch(normals, parallax_texel, 0).rgb); // 没命中时直接用贴图法线。
	}
	if (based_normal == 0) hit_normal = gfx_DecodeNormalTex(texelFetch(normals, parallax_texel, 0).rgb); // 不用视差法线时一律取贴图法线。
	return parallax_texel; // 交回最终采样像素。
}

#endif
