/*
体素追踪模块适配层：三维逐格步进、半透明染色、铁块镜面弹射与体素着色已迁到生成库。
调用位置：`rendering/reflection/voxel.glsl` 引用本文件；效果层只保留选项与坐标平移，
    算法只在 `omni-gfx/src/voxel.slang` 一份。
可复制示例：`vec4 hit = gfx_voxel_reflection(origin, rayDir, normal, offset, 128, idTex, colorTex, torch, sky, sun, sunDir, 64.0, 1.0, hitWorld);`
设计原因与取舍：函数名、参数顺序与输出参数保持原样，调用点无需改动，默认画面不会漂移；
    两张三维纹理与方块编号含义由调用方提供，库不绑定任何宿主纹理或方块表。
*/
#ifndef GFX_VOXEL_INCLUDED
#define GFX_VOXEL_INCLUDED

// 迁移后的体素实现：逐格步进、半透明染色与镜面弹射。
#include "/omni-gfx/voxel.glsl"

// 半透明方块：水、冰、玻璃，光线穿过后只给后面的画面染色，不停下。
bool gfx_voxel_is_translucent(uint id){ return ogxVoxelIsTranslucent(id); } // 实现在生成库。

// 植物：草、花、树叶等，不挡光也不算实体，直接穿过。
bool gfx_voxel_is_plant(uint id){ return ogxVoxelIsPlant(id); } // 实现在生成库。

// 铁块：反射撞到它时当镜子处理；编号 504 与方块映射表一致。
bool gfx_voxel_is_iron(uint id){ return ogxVoxelIsIron(id); } // 实现在生成库。

// 半透明方块的染色强度：水最清、冰居中、玻璃最浓。
float gfx_voxel_tint_strength(uint id){ return ogxVoxelTintStrength(id); } // 实现在生成库。

// 算一层半透明染色：把方块底色归一化成方向色，再按强度与无色混合。
vec3 gfx_voxel_translucent_tint(uint id, vec3 albedo){ return ogxVoxelTranslucentTint(id, albedo); } // 实现在生成库。

// 给命中的体素面上色：底色乘（方块光加天光的间接光，再加直射太阳光）。
vec3 gfx_voxel_shade(vec3 albedo, vec3 voxel_normal, float packed_light, vec3 torch_color, vec3 sky_color,
		vec3 sun_color, vec3 sun_direction, float strength){
	return ogxVoxelShade(albedo, voxel_normal, packed_light, torch_color, sky_color, sun_color, sun_direction, strength); // 实现在生成库。
}

// 判断体素下标是否落在边长 `side` 的立方体里，越界就没有编号。
bool gfx_voxel_inside(ivec3 cell, int side){ return ogxVoxelInside(cell, side); } // 实现在生成库。

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
vec4 gfx_voxel_reflection(vec3 origin_world, vec3 ray_dir_world, vec3 surface_normal, vec3 voxel_offset, int side,
		usampler3D voxel_id_texture, sampler3D voxel_color_texture, vec3 torch_color, vec3 sky_color,
		vec3 sun_color, vec3 sun_direction, float max_distance, float strength, out vec3 hit_world_pos){
	return ogxVoxelReflection(origin_world, ray_dir_world, surface_normal, voxel_offset, side, voxel_id_texture,
		voxel_color_texture, torch_color, sky_color, sun_color, sun_direction, max_distance, strength, hit_world_pos); // 实现在生成库。
}

#endif
