/*
通用图形库水面模块：噪声波高、波法线与水面视差。
调用位置：任何需要程序化水面起伏的程序；本仓库由 `effects/water/waves.glsl` 转发调用。
可复制示例：
    float h = gfx_waves(worldPos, noiseTexture, seconds, 0.05); // 采样波高。
    vec3 n = gfx_waves_normal(worldPos, noiseTexture, seconds, 0.05, 1.0, 1.2); // 未归一化法线。
    vec3 p = gfx_water_parallax(worldPos, viewDir, noiseTexture, seconds, 0.05, 1.2); // 视差坐标。
设计原因与取舍：
    噪声纹理、时间、空间缩放和波高全部由调用方传入，库不读取引擎时间或选项。
    波法线故意不做归一化，让调用方能在归一化前叠加玩家涟漪，保持与原程序相同的顺序。
    六层噪声的权重与方向照 iterationT 原程序保留，只把常数换成参数。
*/
#ifndef GFX_WATER_INCLUDED
#define GFX_WATER_INCLUDED

// 用三次曲线平滑噪声采样，减少像素块感。
vec4 gfx_texture_smooth(sampler2D noiseTexture, vec2 coord){
	coord *= 64.0; // 噪声纹理边长六十四，先换成像素坐标。
	coord += 0.5; // 移到像素中心。
	vec2 whole = floor(coord); // 整数像素。
	vec2 part = coord - whole; // 小数部分。
	coord = whole + part * part * (3.0 - 2.0 * part); // 三次曲线改写小数部分。
	coord -= 0.5; // 移回像素角。
	coord *= 0.015625; // 除以六十四，换回零到一坐标。
	return textureLod(noiseTexture, coord, 0.0); // 读取平滑后的噪声四通道。
}

// 把零到一的值压成两端平、中间过渡的形状，让波峰更饱满。
float gfx_almost_identity(float x, float m, float n){
	x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值。
	if (x <= m){ // 只在靠近中间的一段改写。
		float a = 2.0 * n - m; // 三次项系数。
		float b = 2.0 * m - 3.0 * n; // 二次项系数。
		float t = x / m; // 归一化到零到一。
		x = (a * t + b) * t * t + n; // 三次多项式重排形状。
	}
	return 1.0 - x; // 翻转方向。
}

// 六层噪声叠加的波高，返回归一化高度。
float gfx_waves(vec3 position, sampler2D noiseTexture, float time, float waveScale){
	float wavesTime = time * 0.0035; // 波浪时间，比真实秒慢很多。
	position *= waveScale; // 按波浪密度缩放空间坐标。
	vec2 p = position.xz - position.y; // 用水平坐标，减去高度让波浪随高度起伏。
	p += -3.875 * wavesTime; // 整片波沿一个方向平移。
	p.x = -p.x; // 翻转一个轴，打散规则方向。
	vec2 waves = vec2(0.0); // 前两个分量存累加高度和累加权重。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(2.0, 1.2) + vec2(0.0, p.x * 2.1)).w, 1.0); // 第一层低频大波。
	p = p * 0.475; // 收缩坐标，频率升高。
	p += vec2(-5.16, -7.75) * wavesTime; // 每层自己的行进方向与速度。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(2.0, 1.4) + vec2(0.0, -p.x * 2.1)).w * 4.0, 4.0); // 第二层。
	p *= 0.67; // 继续抬高频率。
	p.x += 7.75 * wavesTime; // 换一个方向。
	waves += vec2(gfx_texture_smooth(noiseTexture, p + vec2(0.0, p.x * 1.1)).z * 8.0, 8.0); // 第三层。
	p *= 0.7; // 再抬高频率。
	p.x += -2.82 * wavesTime; // 换方向。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.75) + vec2(0.0, -p.x * 1.7)).w * 16.0, 16.0); // 第四层。
	p *= 0.45; // 高频细节。
	p.x += wavesTime; // 换方向。
	waves += vec2(gfx_almost_identity(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, -p.x * 1.7)).z, 0.2, 0.1) * 30.0, 30.0); // 第五层。
	p *= 0.5; // 最高频一层。
	p.x += wavesTime; // 换方向。
	waves += vec2(gfx_almost_identity(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, p.x * 1.7)).w, 0.2, 0.1) * 20.0, 20.0); // 第六层。
	return waves.x / waves.y; // 高度除以权重和，归一化。
}

// 用中央差分求波法线，返回未归一化的向量，方便调用方先叠涟漪再归一化。
vec3 gfx_waves_normal(vec3 position, sampler2D noiseTexture, float time, float waveScale, float waveHeight, float heightScale){
	const float sampleDistance = 12.0; // 法线差分采样距离。
	position.xz -= 0.005 * sampleDistance; // 采样点整体后移一点，让差分落在波面中心。
	float center = gfx_waves(position, noiseTexture, time, waveScale); // 中心高度。
	float left = gfx_waves(position + vec3(0.01 * sampleDistance, 0.0, 0.0), noiseTexture, time, waveScale); // 横向偏移。
	float up = gfx_waves(position + vec3(0.0, 0.0, 0.01 * sampleDistance), noiseTexture, time, waveScale); // 纵向偏移。
	vec3 normal = vec3(center - left, center - up, 1.0); // 两个方向的高度差构成法线。
	normal.xy *= waveHeight * (heightScale / sampleDistance); // 按波高与采样距离缩放坡度。
	return normal;
}

// 沿视线在波高场里前进，找到真正可见的波面位置。
vec3 gfx_water_parallax(vec3 position, vec3 viewVector, sampler2D noiseTexture, float time, float waveScale, float heightScale){
	vec3 stepSize = vec3(heightScale * 0.8, heightScale * 0.8, 0.6); // 每步大小，横向按波高缩放。
	float waveHeight = gfx_waves(position, noiseTexture, time, waveScale); // 起点波高。
	vec3 pCoord = vec3(0.0, 0.0, 1.0); // 以表面为参考，向前推进的深度。
	vec3 steps = viewVector * stepSize; // 每步的位移。
	float sampleHeight = waveHeight; // 当前位置的波高。
	for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i){ // 最多十二步。
		pCoord.xy += steps.xy * clamp((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2), 0.0, 1.0); // 按深度差决定步长。
		pCoord.z += steps.z; // 视线深度前进。
		sampleHeight = gfx_waves(position + vec3(pCoord.x, 0.0, pCoord.y), noiseTexture, time, waveScale); // 读取新位置波高。
	}
	return position + vec3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

#endif
