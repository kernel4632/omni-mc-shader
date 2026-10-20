/*
通用图形库体素追踪模块：在规则三维网格里沿射线逐格前进，撞到实心方格时用存下的颜色与光照着色。
调用位置：任何有三维方块编号图与颜色图的程序；本仓库由 `effects/reflection/voxel.glsl` 调用。
可复制示例：
    `vec3 hitWorld; vec4 hit = gfx_voxel_reflection(origin, rayDir, normal, voxelOffset, 128, idTex, colorTex, torchColor, skyColor, sunColor, sunDir, 64.0, 1.0, hitWorld);`
设计原因与取舍：
    网格偏移、边长、两张三维纹理、光色、太阳方向、追踪距离与强度全部由调用方传入，库不读取任何引擎状态。
    水、冰、玻璃按半透明处理，只给后面的画面染色后继续走；铁块按镜面弹射，最多弹四次，防止两面镜子互相拖满循环。
    追踪用标准的三维逐格步进：每步选最近的一根格子边界，撞到实心方块就停。
*/
#ifndef GFX_VOXEL_INCLUDED
#define GFX_VOXEL_INCLUDED

#include "/gfx/math.glsl"
#include "/gfx/color.glsl"

// 半透明方块：水、冰、玻璃，光线穿过后只给后面的画面染色，不停下。
bool gfx_voxel_is_translucent(uint id){ return id == 8u || id == 79u || id == 95u; }
// 植物：草、花、树叶等，不挡光也不算实体，直接穿过。
bool gfx_voxel_is_plant(uint id){ return id == 12u || id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7030u || id == 7040u; }
// 铁块：反射撞到它时当镜子处理；编号 504 与方块映射表一致。
bool gfx_voxel_is_iron(uint id){ return id == 504u; }

// 半透明方块的染色强度：水最清、冰居中、玻璃最浓。
// 为什么按编号分档：颜色图没有存透明度，只能按方块种类近似；玻璃本身有色，染色就重一些。
float gfx_voxel_tint_strength(uint id){
	if (id == 8u) return 0.4; // 水：多数是清水，只带一点生物群系颜色。
	if (id == 79u) return 0.6; // 冰：本身偏蓝。
	return 0.8; // 玻璃与染色玻璃：颜色最重。
}

// 算一层半透明染色：把方块底色归一化成方向色（保留色相、去掉亮度），再按强度与无色混合。
// 为什么归一化：只用色相给后面的画面染色，避免水太亮把反射整个提白。
vec3 gfx_voxel_translucent_tint(uint id, vec3 albedo){
	return mix(vec3(1.0), gfx_omniNormalize(albedo), gfx_voxel_tint_strength(id));
}

// 给命中的体素面上色：底色乘（方块光加天光的间接光，再加直射太阳光）。
// `packed_light` 是写入端打包的方块光与天光，`voxel_normal` 是进入面朝外的法线。
vec3 gfx_voxel_shade(vec3 albedo, vec3 voxel_normal, float packed_light, vec3 torch_color, vec3 sky_color,
		vec3 sun_color, vec3 sun_direction, float strength){
	float packed = floor(packed_light * 255.0 + 0.5); // 还原成整数位的打包光照。
	float block_level = floor(packed / 16.0) / 15.0; // 高四位是方块光等级。
	float sky_level = mod(packed, 16.0) / 15.0; // 低四位是天光等级。
	vec3 indirect = torch_color * block_level + sky_color * sky_level; // 方块光与天光一起给环境亮度。
	vec3 direct = sun_color * gfx_saturate(dot(voxel_normal, sun_direction)); // 直射按体素面朝太阳的余弦。
	return albedo * (indirect + direct) * strength; // 底色乘光照与玩家强度。
}

// 判断体素下标是否落在边长 `side` 的立方体里，越界就没有编号。
bool gfx_voxel_inside(ivec3 cell, int side){
	return all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, ivec3(side)));
}

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// `origin_world` 是表面相机相对世界位置，`ray_dir_world` 是世界空间反射方向，`surface_normal` 是表面法线；
// `voxel_offset` 是相机相对位置到体积坐标的平移，`side` 是每边单元数。
// 输出参数 `hit_world_pos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。
vec4 gfx_voxel_reflection(vec3 origin_world, vec3 ray_dir_world, vec3 surface_normal, vec3 voxel_offset, int side,
		usampler3D voxel_id_texture, sampler3D voxel_color_texture, vec3 torch_color, vec3 sky_color,
		vec3 sun_color, vec3 sun_direction, float max_distance, float strength, out vec3 hit_world_pos){
	hit_world_pos = origin_world; // 先给一个占位，命中时才被真正赋值。
	if (dot(ray_dir_world, surface_normal) <= 0.0) return vec4(0.0, 0.0, 0.0, -1.0); // 射线朝表面内侧，追踪没有意义。
	const int max_steps = 320; // 每根射线最多走的格数，覆盖整条体积对角线还有余量。
	const int iron_bounces = 4; // 铁块镜面最多弹射几次，防止两面镜子互相反射把循环拖满。
	float max_dist = min(max_distance, float(side)); // 追踪距离不超过体积边长。
	vec3 accum_tint = vec3(1.0); // 半透明方块累积的染色，最后乘到后面的画面上。
	float traveled = 0.0; // 已经走过的米数，跨镜面弹射累加，用来对总距离封顶。
	vec3 pos_world = origin_world + surface_normal * 0.05; // 起点沿法线抬起一点，避开表面自身那一格。
	vec3 dir = ray_dir_world; // 当前这段射线的方向，铁块弹射后会被改掉。
	for (int bounce = 0; bounce <= iron_bounces; bounce++){ // 每多弹一次镜面就多跑一段直线步进。
		vec3 grid_pos = pos_world + voxel_offset; // 转成体素网格坐标，整数边界就是体素边界。
		ivec3 cell = ivec3(floor(grid_pos)); // 起点所在体素下标。
		if (!gfx_voxel_inside(cell, side)) return vec4(0.0, 0.0, 0.0, -1.0); // 起点不在体积内，无法追踪。
		ivec3 step_dir = ivec3(sign(dir)); // 每轴前进方向，正负一或零。
		vec3 inv_dir = 1.0 / dir; // 方向倒数，用来算跨边界的参数距离。
		vec3 t_delta = abs(inv_dir); // 跨过一整格所需的参数距离。
		vec3 t_max = vec3(1e30); // 到下一个边界的参数距离；方向为零的轴保持极大值，不会被先选中。
		if (dir.x != 0.0) t_max.x = (float(cell.x) + max(sign(dir.x), 0.0) - grid_pos.x) * inv_dir.x;
		if (dir.y != 0.0) t_max.y = (float(cell.y) + max(sign(dir.y), 0.0) - grid_pos.y) * inv_dir.y;
		if (dir.z != 0.0) t_max.z = (float(cell.z) + max(sign(dir.z), 0.0) - grid_pos.z) * inv_dir.z;
		bool mirrored = false; // 这一段是否以击中铁块镜面结束。
		for (int i = 0; i < max_steps; i++){
			float t_min = min(min(t_max.x, t_max.y), t_max.z); // 最近的一次跨格距离。
			if (traveled + t_min > max_dist) return vec4(0.0, 0.0, 0.0, -1.0); // 总距离超出上限，没有命中。
			vec3 face_normal = vec3(0.0); // 本次进入体素的朝向；沿哪个轴走就从它的对面进入。
			if (t_max.x <= t_min){ cell.x += step_dir.x; t_max.x += t_delta.x; face_normal.x = -float(step_dir.x); } // 走横轴这一格。
			else if (t_max.y <= t_min){ cell.y += step_dir.y; t_max.y += t_delta.y; face_normal.y = -float(step_dir.y); } // 走纵轴这一格。
			else { cell.z += step_dir.z; t_max.z += t_delta.z; face_normal.z = -float(step_dir.z); } // 走深度轴这一格。
			if (!gfx_voxel_inside(cell, side)) return vec4(0.0, 0.0, 0.0, -1.0); // 走出体积，后面的格子没有编号。
			uint voxel_id = texelFetch(voxel_id_texture, cell, 0).r; // 读这一格的方块编号。
			if (voxel_id == 0u) continue; // 空气，继续走。
			if (gfx_voxel_is_plant(voxel_id)) continue; // 植物不挡光，继续走。
			vec4 stored = texelFetch(voxel_color_texture, cell, 0); // 读这一格的颜色与光照。
			vec3 albedo = gfx_srgb_to_linear(stored.rgb); // 贴图色从 sRGB 换回线性，与场景单位一致。
			if (gfx_voxel_is_translucent(voxel_id)){ accum_tint *= gfx_voxel_translucent_tint(voxel_id, albedo); continue; } // 水冰玻璃按彩色水染色后继续。
			vec3 hit_point = pos_world + dir * t_min; // 本次刚跨进来的边界点，就是命中面所在位置。
			if (gfx_voxel_is_iron(voxel_id) && bounce < iron_bounces){ // 铁块镜面：弹开再追，铁块自己不上色。
				traveled += t_min; // 把这一段长度计入总距离。
				hit_world_pos = hit_point; // 先记住镜面位置，后续万一没命中仍有合理取值。
				pos_world = hit_point + face_normal * 0.01; // 起点抬离镜面，避免下一次步进又落回同一格。
				dir = reflect(dir, face_normal); // 按进入面法线弹射。
				mirrored = true; // 标记本段以镜面结束，去跑下一段。
				break; // 退出内层，外层用新的起点与方向重设步进状态。
			}
			hit_world_pos = hit_point; // 命中点的相机相对世界位置，调用方用它算雾段。
			vec3 shaded = gfx_voxel_shade(albedo, face_normal, stored.a, torch_color, sky_color, sun_color, sun_direction, strength) * accum_tint; // 按体素面法线着色并乘上半透明染色。
			return vec4(shaded, gfx_saturate((traveled + t_min) / max_dist)); // 归一化总命中距离放进 a，供反射滤波使用。
		}
		if (!mirrored) return vec4(0.0, 0.0, 0.0, -1.0); // 走到步数上限还没命中，交给调用方走天空回退。
	}
	return vec4(0.0, 0.0, 0.0, -1.0); // 镜面弹射次数用尽仍未命中，交给调用方走天空回退。
}

#endif
