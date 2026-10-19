/*
通用图形库大气模块：球面几何、密度剖面与预计算贴图坐标。
调用位置：任何需要球面大气几何或查表坐标的程序；本仓库由 `effects/sky/atmosphere_model.glsl` 转发调用。
可复制示例：
    float d = gfx_distance_to_top(radius, mu, topRadius); // 到层顶的距离。
    float e = gfx_density_rayleigh_mie(expScale, altitude); // 指数密度。
    float u = gfx_texture_coord(unit, textureSize); // 内缩半像素的贴图坐标。
设计原因与取舍：
    大气半径、贴图尺寸和密度系数全部由调用方传入，库不读取引擎常量。
    公式与 iterationT 原程序一致；只把全局常数换成参数，保持查表结果不变。
*/
#ifndef GFX_ATMOSPHERE_INCLUDED
#define GFX_ATMOSPHERE_INCLUDED

#include "/gfx/math.glsl"

// 把半径夹进大气层范围内。
float gfx_clamp_radius(float r, float bottomRadius, float topRadius){
	return clamp(r, bottomRadius, topRadius); // 下不低于地面、上不超过层顶。
}

// 安全开方：负零以下一律当零，避免浮点误差出非数。
float gfx_safe_sqrt(float a){
	return sqrt(max(a, 0.0)); // 负数开到零。
}

// 视线到大气层顶的距离，解球面方程取远根。
float gfx_distance_to_top(float r, float mu, float topRadius){
	float discriminant = r * r * (mu * mu - 1.0) + topRadius * topRadius; // 交点判别式。
	return max(-r * mu + gfx_safe_sqrt(discriminant), 0.0); // 取朝向层顶一侧的根。
}

// 视线到大气层底的距离，解球面方程取近根。
float gfx_distance_to_bottom(float r, float mu, float bottomRadius){
	float discriminant = r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius; // 球面交点判别式。
	return max(-r * mu - gfx_safe_sqrt(discriminant), 0.0); // 取靠近相机一侧的根。
}

// 判断一条朝下的视线是否真的打到地面球。
bool gfx_ray_intersects_ground(float r, float mu, float bottomRadius){
	return mu < 0.0 && r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius >= 0.0; // 朝下且判别式非负才相交。
}

// 瑞利与米氏密度剖面：以二为底的指数衰减。
float gfx_density_rayleigh_mie(float expScale, float altitude){
	return exp2(expScale * altitude); // 高度越高密度越低。
}

// 臭氧密度剖面：转折高度以下一段斜线，以上另一段斜线。
float gfx_density_absorption(float width, vec4 profile, float altitude){
	return altitude < width ? profile.x * altitude + profile.y : profile.z * altitude + profile.w; // 两段线性剖面。
}

// 把零到一的比例映射到贴图像素中心，避免采到子图交界。
float gfx_texture_coord(float x, float textureSize){
	return 0.5 / textureSize + x * (1.0 - 1.0 / textureSize); // 内缩半像素。
}

// 把子图内部比例映射到拼合大图坐标，子图在大图里也内缩半像素。
float gfx_combined_texture_coord(float x, float originalSize, float combinedSize){
	return 0.5 / combinedSize + x * (originalSize / combinedSize - 1.0 / combinedSize); // 按子图尺寸缩放。
}

#endif
