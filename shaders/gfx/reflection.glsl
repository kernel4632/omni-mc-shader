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

#endif
