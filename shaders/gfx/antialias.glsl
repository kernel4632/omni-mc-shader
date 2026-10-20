/*
通用图形库抗锯齿模块：颜色空间转换与历史颜色裁剪。
调用位置：任何需要时间抗锯齿的程序；本仓库由 `effects/clarity/taa.glsl` 转发调用。
可复制示例：
    vec3 y = gfx_rgb_to_ycocg(color); // 转到亮度与色差空间。
    vec3 c = gfx_clip_aabb(avg, variance, history); // 把历史裁进当前邻域。
设计原因与取舍：
    只做纯数学，不读取历史画面或深度；采样与重投影由调用方负责。
    YCoCg 让亮度与色差分开裁剪，避免高对比边缘出现彩边。
*/
#ifndef GFX_ANTIALIAS_INCLUDED
#define GFX_ANTIALIAS_INCLUDED

// 把线性颜色转到亮度与色差空间，亮度单独处理。
vec3 gfx_rgb_to_ycocg(vec3 color){
	return vec3(color.r * 0.25 + color.g * 0.5 + color.b * 0.25,
	            color.r * 0.5 - color.b * 0.5,
	            -color.r * 0.25 + color.g * 0.5 - color.b * 0.25); // 亮度与两个色差。
}

// 从亮度与色差空间换回线性颜色。
vec3 gfx_ycocg_to_rgb(vec3 color){
	float y = color.x; // 亮度。
	float co = color.y; // 橙到青的色差。
	float cg = color.z; // 绿到品红的色差。
	return vec3(y + co - cg, y + cg, y - co - cg); // 逆变换。
}

// 把历史颜色裁进当前三乘三邻域；`toCenter` 为真时朝中心拉，否则按分量分别裁剪。
vec3 gfx_clip_aabb(vec3 average, vec3 variance, vec3 history, bool toCenter){
	if (toCenter){
		float eps = 1e-20; // 极小量，避免除零。
		vec3 extent = variance - eps; // 范围半径。
		vec3 offset = history - average; // 历史相对中心的偏移。
		vec3 unit = abs(offset / extent); // 各通道越界比例。
		float maxUnit = max(unit.x, max(unit.y, unit.z)); // 最大越界比例。
		return maxUnit > 1.0 ? average + offset / maxUnit : history; // 沿原方向拉回边界。
	}
	vec3 diff = history - average; // 历史相对中心的偏移。
	vec3 clipMax = mix(vec3(1.0), variance / diff, greaterThan(diff, variance)); // 超出上界的比例。
	vec3 clipMin = mix(vec3(1.0), -variance / diff, lessThan(diff, -variance)); // 超出下界的比例。
	diff *= clipMax.x * clipMax.y * clipMax.z * clipMin.x * clipMin.y * clipMin.z; // 一次缩到范围内。
	return average + diff; // 返回裁剪后的历史。
}

// 五次采样读四分量纹理，保留透明度；与泛光的三次升采样核不同。
vec4 gfx_bicubic_texture4(sampler2D source, vec2 coord, vec2 texSize){
	vec2 texel = 1.0 / texSize; // 一个纹素的大小。
	coord = coord * texSize; // 换到像素坐标。
	vec2 p = floor(coord - 0.5) + 0.5; // 采样核中心。
	vec2 f = coord - p; // 中心偏移。
	vec2 f2 = f * f; // 平方。
	vec2 f3 = f * f2; // 立方。
	const float c = 0.5; // 三次核系数。
	vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f; // 最左权重。
	vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0; // 左权重。
	vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f; // 右权重。
	vec2 w3 = c * f3 - c * f2; // 最右权重。
	vec2 w12 = w1 + w2; // 左右权重和。
	vec2 tc12 = texel * (p + w2 / w12); // 中间采样坐标。
	vec2 tc0 = texel * (p - 1.0); // 最左采样点。
	vec2 tc3 = texel * (p + 2.0); // 最右采样点。
	vec4 color = textureLod(source, vec2(tc12.x, tc0.y), 0.0) * (w12.x * w0.y)
	           + textureLod(source, vec2(tc0.x, tc12.y), 0.0) * (w0.x * w12.y)
	           + textureLod(source, vec2(tc12.x, tc12.y), 0.0) * (w12.x * w12.y)
	           + textureLod(source, vec2(tc3.x, tc12.y), 0.0) * (w3.x * w12.y)
	           + textureLod(source, vec2(tc12.x, tc3.y), 0.0) * (w12.x * w3.y); // 五个采样点加权。
	return color / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y); // 归一化。
}

#endif
