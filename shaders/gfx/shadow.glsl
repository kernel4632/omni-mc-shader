/*
通用图形库阴影模块：把世界位置投到阴影相机，并对阴影图坐标做边缘压缩。
调用位置：任何使用方向光阴影贴图的程序；本仓库由 `effects/shadow/shadow.glsl` 转发调用。
可复制示例：
    vec3 p = gfx_shadow_screen_pos(worldPos, shadowView, shadowProjection); // 不做压缩。
    vec3 q = gfx_shadow_screen_pos_distorted(worldPos, shadowView, shadowProjection, 0.9); // 边缘压缩。
    vec2 uv = gfx_distort_shadow_pos(q.xy, 0.9); // 读取端补压缩。
设计原因与取舍：
    阴影相机矩阵、投影和压缩强度全部由调用方传入，库不读取引擎 uniform。
    深度只取一半再转零到一，与原程序一致；边缘压缩让阴影图边缘拿到更高有效分辨率。
*/
#ifndef GFX_SHADOW_INCLUDED
#define GFX_SHADOW_INCLUDED

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

#endif
