/*
通用图形库云模块：云的光照相位、顶部曲线、平面云密度与云影取样。
调用位置：任何需要云形状或云影的程序；本仓库由 `effects/cloud/*` 与 `effects/reflection/screenspace.glsl` 调用。
可复制示例：
    float p = gfx_henyey_greenstein(cosAngle, 0.8); // 前向散射相位。
    float t = gfx_cloud_top_curve(x); // 云的顶部圆润曲线。
    float s = gfx_cloud_shadow(shadowTex, worldPos, lightDir, cameraY, 4096.0, screenSize, pixelSize, 256.0, wetness, 1.0, true); // 云影。
设计原因与取舍：
    只做纯数学与采样，不读取噪声纹理绑定、云层高度或选项；纹理与参数仍由调用方传入。
    公式照 iterationT 原程序保留，迁移只改名字；云影与云的形状放在一起，因为两者共用同一套天气与范围。
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

// --- 云影：把地表点投到云影贴图并取遮蔽 ---
// 为什么放在云模块：云影是云的可见结果，与云的形状共用同一套天气与范围参数。

// 云影投影坐标：把世界点沿光方向投到云影所在的水平面，再换成零到一贴图坐标。
vec2 gfx_cloud_shadow_coord(vec3 world_pos, vec3 light_dir, float camera_y, float range){
	vec2 coord = world_pos.xz - light_dir.xz * ((world_pos.y + camera_y) / light_dir.y); // 沿光方向落到云影平面。
	return coord * (1.0 / range) + 0.5; // 换成贴图坐标。
}

// 十六像素三次模糊：四次双线性采样合成，返回红通道；云影贴图只有红通道有意义。
float gfx_cloud_shadow_bicubic(sampler2D shadow_tex, vec2 coord, vec2 tex_size){
	vec2 tex_pixel = 1.0 / tex_size; // 一个像素的坐标大小。
	coord = coord * tex_size - 0.5; // 换成以像素为单位的坐标。
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
	c *= tex_pixel.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(shadow_tex, c.yw, 0.0).x, textureLod(shadow_tex, c.xw, 0.0).x, m.x),
	           mix(textureLod(shadow_tex, c.yz, 0.0).x, textureLod(shadow_tex, c.xz, 0.0).x, m.x),
	           m.y); // 四次双线性采样得到十六像素的三次模糊，取红通道。
}

// 云影取样：按天气在晴天与雨天两档之间混合，`wetness` 是降雨湿润度。
float gfx_cloud_shadow(sampler2D shadow_tex, vec3 world_pos, vec3 light_dir, float camera_y, float range,
		vec2 screen_size, vec2 pixel_size, float tex_size, float wetness, float rain_shadow, bool fade_angle){
	vec2 coord = gfx_cloud_shadow_coord(world_pos, light_dir, camera_y, range); // 投到云影贴图坐标。
	float cloud_shadow = 1.0 - wetness; // 雨天默认的云影底值。
	if (gfx_saturate(coord) == coord){ // 只有落在贴图范围内才采样。
		vec2 shadow_texel = screen_size - coord * tex_size; // 贴图贴在画面右上角，坐标要翻转。
		vec2 fade = gfx_saturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
		cloud_shadow = mix(cloud_shadow, gfx_cloud_shadow_bicubic(shadow_tex, shadow_texel * pixel_size, screen_size), fade.x * fade.y); // 三次采样并淡出。
	}
	if (fade_angle){ // 太阳越贴地云影越淡。
		float fade = smoothstep(0.06, 0.18, abs(light_dir.y)); // 光方向越平越淡。
		cloud_shadow = mix(1.0 - wetness, cloud_shadow, fade * fade); // 按淡出权重混合。
	}
	return ((rain_shadow - 1.0) * wetness + 1.0) * cloud_shadow + (wetness - rain_shadow * wetness); // 晴天与雨天两档之间插值。
}

// 全局云影：从云影贴图顶行的统计像素取一个粗粒度值；没有贴图时按天气估。
float gfx_global_cloud_shadow(sampler2D shadow_tex, ivec2 stat_texel, float wetness, float rain_shadow, bool from_texture){
	if (from_texture) return mix(texelFetch(shadow_tex, stat_texel, 0).a, 1.0, 0.03 - wetness * 0.015); // 统计像素存全局云影。
	return 1.0 - wetness * (rain_shadow * 0.985); // 纯天气估计。
}

// 云影横向或纵向高斯模糊：权重固定，轴由参数给；其余通道原样带过。
vec4 gfx_cloud_shadow_blur(sampler2D shadow_tex, ivec2 texel, ivec2 axis, ivec2 border_min, ivec2 border_max){
	vec4 blur = vec4(0.0); // 模糊结果。
	ivec2 sample_coord = clamp(texel - 3 * axis, border_min, border_max); // 第三个负向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.054543; // 按高斯权重累加。
	sample_coord = clamp(texel - 2 * axis, border_min, border_max); // 第二个负向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.099384; // 累加。
	sample_coord = clamp(texel - 1 * axis, border_min, border_max); // 第一个负向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.181090; // 累加。
	vec4 center = texelFetch(shadow_tex, texel, 0); // 中心样本。
	blur.r += center.r * 0.329966; // 中心权重最大。
	blur.gba += center.gba; // 其余通道原样带过。
	sample_coord = clamp(texel + 1 * axis, border_min, border_max); // 第一个正向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.181090; // 累加。
	sample_coord = clamp(texel + 2 * axis, border_min, border_max); // 第二个正向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.099384; // 累加。
	sample_coord = clamp(texel + 3 * axis, border_min, border_max); // 第三个正向样本。
	blur.r += texelFetch(shadow_tex, sample_coord, 0).r * 0.054543; // 累加。
	return blur; // 返回模糊后的云影贴图。
}

#endif
