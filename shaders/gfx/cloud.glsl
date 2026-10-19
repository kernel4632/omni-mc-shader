/*
通用图形库云模块：云的光照相位与顶部曲线。
调用位置：任何需要体积云光照形状的程序；本仓库由 `effects/cloud/volumetric.glsl` 转发调用。
可复制示例：
    float p = gfx_henyey_greenstein(cosAngle, 0.8); // 前向散射相位。
    float t = gfx_cloud_top_curve(x); // 云的顶部圆润曲线。
设计原因与取舍：
    只做纯数学，不读取噪声纹理、云层高度或选项；采样与密度仍由调用方负责。
    公式照 iterationT 原程序保留，迁移只改名字。
*/
#ifndef GFX_CLOUD_INCLUDED
#define GFX_CLOUD_INCLUDED

#include "/gfx/math.glsl"

#define GFX_GOLDEN_ANGLE 2.39996322973 // 黄金角，用来旋转噪声层。

// 亨耶-格林斯坦相位：描述云滴把光往哪个方向散，参数越大越集中在前方。
float gfx_henyey_greenstein(float cosAngle, float g){
	float num = 1.0 - g * g; // 分子，控制整体强度。
	float denom = 1.0 + g * g - 2.0 * g * cosAngle; // 分母，越靠前越小。
	float inverse = inversesqrt(denom); // 分母的平方根倒数。
	return num * inverse * inverse * inverse * (0.25 / GFX_PI); // 归一化后返回。
}

// 云的顶部曲线：把一到零的坐标变成圆润的凸起。
float gfx_cloud_top_curve(float x){
	x = x - 1.0; // 平移到顶点。
	return 1.0 - x * x; // 开口向下的抛物线。
}

// 三次模糊噪声：平面云专用，四次双线性采样合成十六像素模糊，取第四通道。
float gfx_bicubic_blur_noise(vec2 coord, sampler2D noiseTexture){
	coord = coord * (1.2e-4 * 64.0) - 0.5; // 噪声贴图按每方块一点二万分之一缩放。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个权重。
	vec4 w1; // 两个方向的后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= 1.0 / 64.0; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(noiseTexture, c.yw, 0.0).w, textureLod(noiseTexture, c.xw, 0.0).w, m.x),
	           mix(textureLod(noiseTexture, c.yz, 0.0).w, textureLod(noiseTexture, c.xz, 0.0).w, m.x),
	           m.y); // 四次采样合成一次模糊。
}

// 双线性噪声：平面云细节用的普通采样。
float gfx_bilinear_noise(vec2 position, sampler2D noiseTexture){
	return textureLod(noiseTexture, position * 1.2e-4, 0.0).w; // 与三次版同一缩放。
}

// 平面云的扭曲：几层噪声叠出缓慢起伏的偏移量，让云块边缘不平整。
float gfx_planar_distortion(vec2 position, vec2 windDirection, sampler2D noiseTexture){
	float density = gfx_bilinear_noise(position - windDirection, noiseTexture); // 第一层。
	float scale = 4.0; // 起始频率。
	for (int i = 0; i < 3; i++, scale *= 3.0){ // 三层，频率逐级乘三。
		density += gfx_bilinear_noise(scale * (position - windDirection * gfx_fsqrt(scale)), noiseTexture) * pow(scale, -1.3); // 按频率衰减。
	}
	return density; // 返回扭曲量。
}

// 平面云密度：位置先扭曲，再叠多层旋转噪声得到云块。
float gfx_planar_density(vec2 position, vec2 windDirection, sampler2D noiseTexture, float noiseScale, float coverage){
	position *= noiseScale; // 按调用方给的空间尺度缩放。
	float distortion = gfx_planar_distortion(position, windDirection, noiseTexture); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(GFX_GOLDEN_ANGLE), -sin(GFX_GOLDEN_ANGLE), sin(GFX_GOLDEN_ANGLE), cos(GFX_GOLDEN_ANGLE)); // 按黄金角旋转并缩放。
	float density = gfx_bicubic_blur_noise(position - windDirection, noiseTexture); // 第一层密度。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 6.0; i++, rot *= rotateGoldenAngle){ // 六层。
		float scale = gfx_fsqrt(i); // 每层频率取平方根。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同。
		float weight = pow(octScale, -0.85 * i); // 每层权重按频率衰减。
		density += gfx_bicubic_blur_noise(noisePosition, noiseTexture) * weight; // 累加这一层。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均到零到一附近。
	density = clamp(density + coverage - 1.0, 0.0, 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方让边缘更收。
}

// 平面云的光照密度：用便宜的噪声和更少层数，专供光照估计。
float gfx_planar_lighting_density(vec2 position, vec2 windDirection, sampler2D noiseTexture, float noiseScale, float coverage){
	position *= noiseScale; // 按空间尺度缩放。
	float distortion = gfx_planar_distortion(position, windDirection, noiseTexture); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(GFX_GOLDEN_ANGLE), -sin(GFX_GOLDEN_ANGLE), sin(GFX_GOLDEN_ANGLE), cos(GFX_GOLDEN_ANGLE)); // 按黄金角旋转并缩放。
	float density = gfx_bicubic_blur_noise(position - windDirection, noiseTexture); // 第一层。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 3.0; i++, rot *= rotateGoldenAngle){ // 三层。
		float scale = gfx_fsqrt(i); // 每层频率。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同。
		float weight = pow(octScale, -0.85 * i); // 每层权重。
		density += gfx_bilinear_noise(noisePosition, noiseTexture) * weight; // 用便宜的噪声累加。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均。
	density = clamp(density + coverage - 1.0, 0.0, 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方收口。
}

#endif
