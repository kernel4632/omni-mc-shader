/*
通用图形库表面模块：方块光曲线与材质法线、遮蔽换算。
调用位置：任何需要把方块光等级、法线贴图和材质遮蔽变成光照输入的程序；本仓库由 `effects/ground/material.glsl` 转发调用。
可复制示例：
    float c = gfx_curve_block_light_sky(blockLight); // 天光等级曲线。
    vec3 n = gfx_material_normal_scale(tangentNormal, 1.0); // 法线起伏倍率。
    vec4 m = gfx_material_normal(normalTexRGB, true, 1.0); // 法线加遮蔽。
设计原因与取舍：
    选项值由调用方作为参数传入，库不读取任何 `OMNI_*` 宏。
    曲线常数照 iterationT 与 Eclipse 原程序保留，迁移只改名字与参数位置。
*/
#ifndef GFX_SURFACE_INCLUDED
#define GFX_SURFACE_INCLUDED

#include "/gfx/math.glsl"

// 天光曲线：先抬高低等级，再压暗高等级，等级越高越接近饱和。
float gfx_curve_block_light_sky(float blockLight){
	blockLight = 1.0 - pow(1.0 - blockLight * 0.9, 0.7); // 抬高低等级并保留低端细节。
	blockLight = clamp(blockLight * blockLight * blockLight * 1.95, 0.0, 1.0); // 三次方拉开对比后夹紧。
	return blockLight;
}

// 方块光曲线：按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float gfx_curve_block_light_torch(float blockLight){
	float dist = (1.0 - blockLight) * 15.0 + 1.0; // 把等级转成米制距离。
	dist = dist * dist; // 距离平方，衰减更快。
	float boost = clamp(blockLight * 2.0 - 1.0, 0.0, 1.0); // 只有高等级才有的提升量。
	blockLight = blockLight + boost * boost; // 先加提升，突出光源附近的亮度。
	blockLight /= dist; // 再按距离平方衰减。
	return blockLight;
}

// 材质遮蔽：资源包把遮蔽存在法线贴图蓝通道，启用时映射到零点五到一。
float gfx_material_ao(vec3 normalTexRGB, bool enabled){
	return enabled ? normalTexRGB.b * 0.5 + 0.5 : 1.0; // 未启用时不做任何遮蔽。
}

// 法线倍率：围绕朝外方向缩放起伏，倍率为一时保持原样。
vec3 gfx_material_normal_scale(vec3 tangentNormal, float multiplier){
	return normalize(tangentNormal * multiplier + vec3(0.0, 0.0, 1.0 - multiplier)); // z 补齐后重新单位化。
}

// 一次解出切线空间法线与遮蔽，返回前三个分量为法线、第四个分量为遮蔽。
vec4 gfx_material_normal(vec3 normalTexRGB, bool aoEnabled, float multiplier){
	vec3 normal = gfx_material_normal_scale(gfx_DecodeNormalTex(normalTexRGB), multiplier); // 先解码再缩放。
	return vec4(normal, gfx_material_ao(normalTexRGB, aoEnabled)); // 把遮蔽一起交回。
}

#endif
