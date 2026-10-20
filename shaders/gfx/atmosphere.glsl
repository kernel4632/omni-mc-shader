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

// --- 星场：把视线方向化成星点亮度与星色，算法照 Eclipse `lib/stars.glsl` ---
// 这些函数只做纯计算，星点密度、亮度与彩色开关由调用方决定。

// 星场散列：把一个方向格打散成零到一的随机数。
float gfx_star_hash13(vec3 p3){
	p3 = fract(p3 * 0.1031); // 先乘一个小数再取小数部分，打散整数格的规律。
	p3 += dot(p3, p3.zyx + 31.32); // 三个分量互相掺入，避免相邻格出现相近的值。
	return fract((p3.x + p3.y) * p3.z); // 合并三个分量，得到零到一。
}

// 噪声星场：把散列值低于阈值的格子压成零，剩下的当作星点原始亮度。
float gfx_star_noisy_field(vec3 samplePos, float threshold){
	float starVal = gfx_star_hash13(samplePos); // 先取这个格的随机值。
	starVal = clamp(starVal / (1.0 - threshold) - threshold / (1.0 - threshold), 0.0, 1.0); // 阈值以下压到零，剩下归一化到零到一。
	return starVal; // 返回星点亮度。
}

// 稳定星场：只在整数格上取值，再用双线性插值平滑，避免相机移动时星点闪烁。
// 已知代价（Eclipse 原注释承认）：双线性插值会把单个星点拉成十字，这里按合同保留原写法。
float gfx_star_stable_field(vec3 samplePos, float threshold){
	float fractX = fract(samplePos.x); // 当前点在 x 方向的格内偏移。
	float fractY = fract(samplePos.y); // 当前点在 y 方向的格内偏移。
	vec3 floorSample = floor(samplePos.xyz); // 所在整数格。
	float v1 = gfx_star_noisy_field(floorSample, threshold); // 左下格的星点亮度。
	float v2 = gfx_star_noisy_field(floorSample + vec3(0.0, 1.0, 0.0), threshold); // 左上格。
	float v3 = gfx_star_noisy_field(floorSample + vec3(1.0, 0.0, 0.0), threshold); // 右下格。
	float v4 = gfx_star_noisy_field(floorSample + vec3(1.0, 1.0, 0.0), threshold); // 右上格。
	float starVal = v1 * (1.0 - fractX) * (1.0 - fractY) // 四角按格内偏移加权求和。
				  + v2 * (1.0 - fractX) * fractY // 左上权重。
				  + v3 * fractX * (1.0 - fractY) // 右下权重。
				  + v4 * fractX * fractY; // 右上权重。
	return starVal; // 平滑后的星点亮度。
}

// 彩色星场散列：只用二维坐标，正弦放大再取小数。
float gfx_star_hash12(vec2 co){
	return fract(sin(2.0 * GFX_PI * fract(dot(co.xy, vec2(12.9898, 78.233)))) * 43758.5453); // 最常见的二维散列写法。
}

// 星温：把零到一的散列映射成色温，三次方让多数星星偏冷白、少数偏暖。
float gfx_star_temperature(float hash){
	return hash * hash * hash * (19000.0 - 5500.0) + 5500.0; // 色温范围五千五到一万九开尔文。
}

// 星面：把方向投到立方体的一面按格撒星，输出该方向的亮度与颜色。
float gfx_star_plane(vec3 dir, out vec3 starColor){
	float scale = 1.0 / 600.0; // 格子大小，越小星点越密。
	vec2 basePos = dir.xy * (0.4 / scale) / max(1e-3, abs(dir.z)); // 投到这个面上并按深度缩放。
	starColor = vec3(0.0); // 这个面的星色初值。
	vec2 pos = floor(basePos); // 所在整数格。
	vec2 center = pos + vec2(0.5); // 格中心，用来算到星心的距离。
	float d = distance(basePos, center); // 当前采样点到星心的距离。
	basePos = floor(basePos); // 锁定到格，保证相机移动时星点不飘。
	float color = 0.0; // 这个面的星点亮度。
	if (gfx_star_hash12(basePos.xy * scale) > 0.997){ // 只有极少数格子有星。
		float radius = 0.4; // 星点半径，越大越胖。
		float brightness = exp(-(d * d) / (2.0 * radius * radius)); // 高斯衰减，星心最亮。
		float r = gfx_star_hash12(basePos.xy * 0.5); // 这颗星的随机亮度因子。
		color = r * (0.3 * sin(1.0 * (r * 5.0) + r) + 0.7) * brightness; // 亮度带一点随机起伏。
		starColor = 2.0 * gfx_Blackbody(gfx_star_temperature(gfx_star_hash12(center))); // 按格中心的散列取色温上色。
	}
	return color * pow(abs(dir.z), 2); // 按该面朝向加权，面边界处平滑过渡。
}

// 星盒：把方向分别当立方体三轴投影，叠出完整六面星场。
float gfx_star_box(vec3 dir, out vec3 starColor){
	vec3 starColor1 = vec3(0.0); // 第一组投影的星色。
	vec3 starColor2 = vec3(0.0); // 第二组投影的星色。
	vec3 starColor3 = vec3(0.0); // 第三组投影的星色。
	float color = gfx_star_plane(dir.xyz, starColor1) + gfx_star_plane(dir.yzx, starColor2) + gfx_star_plane(dir.zxy, starColor3); // 三组投影叠亮度。
	starColor = starColor1 + starColor2 + starColor3; // 三组投影叠星色。
	return sqrt(color); // 开方压一下亮度分布，与 Eclipse 一致。
}

// 白色稳定星场：返回星场亮度；星色固定为白，由调用方直接使用。
float gfx_stars_stable(vec3 viewPos, float brightness, float amount){
	float s = max(1.0 - gfx_star_stable_field(viewPos * 300.0, 0.99), 0.0); // 采样密度三百、阈值零点九九与 Eclipse 相同。
	return brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 彩色星盒星场：返回亮度并由 `starColor` 回填星色，调用方按需要相乘。
float gfx_stars_colored(vec3 viewPos, float brightness, float amount, out vec3 starColor){
	starColor = vec3(1.0); // 星色由星盒回填，这里先给初值。
	float s = max(1.0 - gfx_star_box(viewPos, starColor), 0.0); // 彩色星盒星场。
	return 75.0 * brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 把视线方向绕太阳轴旋转对齐天球：罗德里格旋转公式，太阳方向由调用方传入。
vec3 gfx_align_to_sun_axis(vec3 worldDir, vec3 sunVector){
	float cosine = dot(sunVector, vec3(0, 0, 1)); // 太阳轴与参考轴夹角余弦。
	vec3 axis = cross(sunVector, vec3(0, 0, 1)); // 旋转轴。
	float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
	return cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式对齐星场。
}

// --- 日月圆盘：视线越接近天体方向越亮，边缘用平滑曲线收口 ---
// 圆盘不是几何，而是方向夹角的遮罩；角半径与硬度属于形体参数，由调用方给出。

// 太阳圆盘遮罩：返回零到一的亮度，太阳颜色与辐照倍率由调用方乘上。
float gfx_sun_disc(vec3 worldDir, vec3 sunDir){
	float d = dot(worldDir, sunDir); // 视线与太阳方向的夹角余弦。
	float size = 5e-5; // 圆盘角半径，越小圆盘越细。
	float hardness = 4e4; // 边缘硬度，越大边缘越陡。
	float x = clamp((d - (1.0 - size)) * hardness, 0.0, 1.0); // 从中心到边缘的平滑遮罩。
	float disc = x * x * (3.0 - 2.0 * x); // 三次平滑曲线收口。
	return disc * disc; // 平方让边缘更收。
}

// 真实月亮圆盘：角半径由尺寸档位换算，档位越大圆盘越大。
float gfx_moon_disc_real(vec3 worldDir, vec3 moonDir, float sizeSetting){
	float d = dot(worldDir, moonDir); // 视线与月亮方向的夹角余弦。
	float moonSize = 0.999 + (10.0 - sizeSetting) * 0.0001; // 档位越大圆盘越大。
	float x = clamp((d - moonSize) / (1.0 - moonSize), 0.0, 1.0); // 从圆盘中心到边缘的遮罩。
	float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
	return disc * disc; // 平方收口后返回零到一的亮度。
}

// 默认月亮圆盘：比太阳更硬、更小的圆盘。
float gfx_moon_disc_default(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 视线与月亮方向的夹角余弦。
	float size = 5e-5; // 圆盘角半径。
	float hardness = 1e5; // 边缘硬度，比太阳更硬。
	float x = clamp((d - (1.0 - size)) * hardness, 0.0, 1.0); // 月亮遮罩。
	float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
	return disc * disc; // 平方收口后返回零到一的亮度。
}

// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float gfx_moon_disc_reflection(vec3 worldDir, vec3 moonDir){
	float d = dot(worldDir, moonDir); // 夹角余弦。
	float size = 0.0025; // 反射用更大的角半径。
	float hardness = 300.0; // 边缘更软。
	float x = clamp((d - (1.0 - size)) * hardness, 0.0, 1.0); // 反射月亮遮罩。
	float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
	return disc * disc; // 返回零到一亮度。
}

// --- 月亮轨道：由游戏时间、纬度与轨道倾角闭式算出月亮的世界方向 ---
// `time` 是累计世界刻，`latitude` 与 `pathRotation` 是角度，`monthLength` 是月亮绕一圈的游戏日数。
// 返回单位方向，y 轴朝天；数学步骤照 Eclipse `dimensions/begin.csh:73-95`。
vec3 gfx_moon_direction(float time, float latitude, float pathRotation, float monthLength){
	float phi = radians(-latitude); // 观测点纬度，换算成弧度。
	float del = radians(pathRotation); // 月亮轨道相对天赤道的倾角。
	float t = time / 24000.0; // 时间换算成天。
	t *= 1.0 + 1.0 / monthLength; // 月亮每天比太阳多走一点，长期累积才产生月相与对齐。
	float H = t * 2.0 * GFX_PI - GFX_PI; // 时角，一整天转一圈。
	float sin_h = sin(phi) * sin(del) + cos(phi) * cos(del) * cos(H); // 高度角正弦。
	float h = asin(clamp(sin_h, -1.0, 1.0)); // 高度角；钳一下避免浮点误差让反正弦出非数。
	float cos_h = cos(h); // 高度角余弦。
	float cosA = (sin(del) - sin(phi) * sin_h) / max(cos(phi) * cos_h, 1e-4); // 方位角余弦；分母加下限，避免两极附近除零。
	cosA = clamp(cosA, -1.0, 1.0); // 同样钳一下，防止浮点误差越界。
	float A = acos(cosA); // 方位角。
	if (sin(H) > 0.0) A = 2.0 * GFX_PI - A; // 时角过午时镜像到另一半球。
	return vec3(cos_h * sin(A), sin_h, cos_h * cos(A)); // 单位方向，y 轴朝天。
}

// --- 天空盒投影：世界方向与三乘二天空盒贴图的纹素坐标互相换算 ---
// `tileSize` 是单张面的边长；投影结果不带屏幕偏移，由调用方按自己的贴图布局追加。

// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `gfx_sky_project` 互为逆。
vec3 gfx_sky_unproject(vec2 texel, float tileSize){
	float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
	vec3 direction = vec3(0.0); // 待求的世界方向。
	if (texel.x < tileSize) { // 第一张面，朝 x 正负。
		direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else if (texel.x < 2.0 * tileSize) { // 第二张面，朝 y 正负。
		direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else { // 第三张面，朝 z 正负。
		direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
		direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
	}
	return normalize(direction); // 单位世界方向。
}

// 把一个世界方向投到天空盒三维贴图上，与 `gfx_sky_unproject` 互为逆。
vec2 gfx_sky_project(vec3 dir, float tileSize){
	float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
	vec3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
	vec2 texel; // 待求的纹素坐标。
	if (adir.x > adir.y && adir.x > adir.z){ // x 份量最大时用第一张面。
		dir /= adir.x; // 归一化主轴分量。
		texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
	}else if (adir.y > adir.x && adir.y > adir.z){ // y 分量最大时用第二张面。
		dir /= adir.y; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
	}else{ // 否则用第三张面。
		dir /= adir.z; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
		texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
	}
	return texel; // 返回纹素坐标，屏幕偏移由调用方追加。
}

#endif
