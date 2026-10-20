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

#include "/gfx/math.glsl"

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

// 屏幕深度换米制距离；时间抗锯齿的深度比较与参考深度都用这一套。
float gfx_taa_linear_depth(float depth, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 零到一转负一到一。
	return 1.0 / (depth * projection_inverse[2][3] + projection_inverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度，写历史参考深度时用。
float gfx_taa_screen_depth(float depth, mat4 projection_inverse){
	depth = (1.0 / depth - projection_inverse[3][3]) / projection_inverse[2][3]; // 解出负一到一深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// 读当前帧颜色；`packedDepth` 为真时透明度是屏幕深度，读完换成米制，供下界历史使用。
// `bicubic` 为真时用三次采样，否则用双线性；两种采样的边缘锐度不同，由调用方按选项选择。
vec4 gfx_taa_sample_current(sampler2D color_texture, vec2 coord, vec2 viewport, mat4 projection_inverse, bool packedDepth, bool bicubic){
	if (packedDepth){ // 下界把颜色与深度放在同一张图。
		vec4 data = bicubic ? gfx_bicubic_texture4(color_texture, coord, viewport) : textureLod(color_texture, coord, 0.0); // 取颜色与深度。
		data.rgb = gfx_rgb_to_ycocg(data.rgb); // 颜色转亮度色差空间。
		data.a = gfx_taa_linear_depth(data.a, projection_inverse); // 深度换米制。
		return data; // 交回四分量。
	}
	vec3 color = bicubic ? gfx_BicubicTexture(color_texture, coord, viewport) : textureLod(color_texture, coord, 0.0).rgb; // 取当前帧颜色。
	return vec4(gfx_rgb_to_ycocg(color), 0.0); // 深度占位为零。
}

// 精确读当前帧纹素；邻域方差统计用，整数坐标不会混入邻居颜色。
vec4 gfx_taa_fetch_current(sampler2D color_texture, ivec2 coord, mat4 projection_inverse, bool packedDepth){
	vec4 data = texelFetch(color_texture, coord, 0); // 精确读取。
	if (packedDepth){ // 下界连深度一起读。
		data.rgb = gfx_rgb_to_ycocg(data.rgb); // 颜色转亮度色差空间。
		data.a = gfx_taa_linear_depth(data.a, projection_inverse); // 深度换米制。
		return data; // 四分量带深度。
	}
	return vec4(gfx_rgb_to_ycocg(data.rgb), 0.0); // 主世界与末地只要颜色。
}

// 双线性读历史里打包的两个参考深度，返回两个分量的双线性插值。
vec2 gfx_taa_prev_depth_bilinear(sampler2D history_texture, vec2 coord, vec2 viewport){
	coord = coord * viewport - 0.5; // 换到纹素坐标并移到纹素中心。
	vec2 f = fract(coord); // 纹素内小数偏移。
	ivec2 texel = ivec2(coord); // 左上角纹素。
	vec2 s0 = gfx_Unpack2x16(texelFetch(history_texture, texel, 0).a); // 左上角两个参考深度。
	vec2 s1 = gfx_Unpack2x16(texelFetch(history_texture, texel + ivec2(1, 0), 0).a); // 右上角。
	vec2 s2 = gfx_Unpack2x16(texelFetch(history_texture, texel + ivec2(0, 1), 0).a); // 左下角。
	vec2 s3 = gfx_Unpack2x16(texelFetch(history_texture, texel + ivec2(1, 1), 0).a); // 右下角。
	return mix(mix(s0, s1, f.x), mix(s2, s3, f.x), f.y); // 双向插值。
}

// 读上一帧历史颜色与参考深度；`packedDepth` 为真时从透明度解包参考深度。
vec4 gfx_taa_sample_previous(sampler2D history_texture, vec2 coord, vec2 viewport, mat4 projection_inverse, bool packedDepth, bool bicubic){
	if (packedDepth){ // 下界历史带参考深度。
		vec3 color = bicubic ? gfx_bicubic_texture4(history_texture, coord, viewport).rgb : textureLod(history_texture, coord, 0.0).rgb; // 取历史颜色。
		float prev_depth = gfx_taa_prev_depth_bilinear(history_texture, coord, viewport).x; // 解包上一帧参考深度。
		return vec4(gfx_rgb_to_ycocg(color), gfx_taa_linear_depth(prev_depth, projection_inverse)); // 颜色与米制参考深度。
	}
	vec3 color = bicubic ? gfx_BicubicTexture(history_texture, coord, viewport) : textureLod(history_texture, coord, 0.0).rgb; // 取历史颜色。
	return vec4(gfx_rgb_to_ycocg(color), 0.0); // 参考深度占位。
}

// 读上一帧某个纹素的参考深度；普通维度存在透明度，下界从打包值里取第二个分量。
float gfx_taa_prev_depth_fetch(sampler2D history_texture, ivec2 coord, bool packedDepth){
	return packedDepth ? gfx_Unpack2x16(texelFetch(history_texture, coord, 0).a).y : texelFetch(history_texture, coord, 0).w; // 按存储方式取深度。
}

// 取上一帧三乘三邻域的参考深度最小与最大值，供深度一致性判断。
vec2 gfx_taa_prev_depth_minmax(sampler2D history_texture, vec2 prev_coord, vec2 viewport, bool packedDepth){
	ivec2 nearest = ivec2(prev_coord * viewport); // 上一帧坐标换成最近纹素。
	float d0 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2(-1, -1), packedDepth); // 左上。
	float d1 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 0, -1), packedDepth); // 上方。
	float d2 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 1, -1), packedDepth); // 右上。
	float d3 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2(-1,  0), packedDepth); // 左侧。
	float d4 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 0,  0), packedDepth); // 中心。
	float d5 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 1,  0), packedDepth); // 右侧。
	float d6 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2(-1,  1), packedDepth); // 左下。
	float d7 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 0,  1), packedDepth); // 下方。
	float d8 = gfx_taa_prev_depth_fetch(history_texture, nearest + ivec2( 1,  1), packedDepth); // 右下。
	float min_depth = min(d0, min(d1, min(d2, min(d3, min(d4, min(d5, min(d6, min(d7, d8)))))))); // 九点最小值。
	float max_depth = max(d0, max(d1, max(d2, max(d3, max(d4, max(d5, max(d6, max(d7, d8)))))))); // 九点最大值。
	return vec2(min_depth, max_depth); // 返回范围。
}

// 当前帧三乘三邻域：求颜色均值、十字均值、方差范围；`packedDepth` 为真时同时给出参考深度范围。
vec3 gfx_taa_variance_3x3(ivec2 coord, vec3 curr_color, sampler2D color_texture, mat4 projection_inverse, bool packedDepth,
		float aggression, out vec3 avg_color, out vec3 cross_avg, out vec2 reference_minmax){
	vec4 data0 = gfx_taa_fetch_current(color_texture, coord + ivec2(-1, -1), projection_inverse, packedDepth); // 左上。
	vec4 data1 = gfx_taa_fetch_current(color_texture, coord + ivec2( 0, -1), projection_inverse, packedDepth); // 上方。
	vec4 data2 = gfx_taa_fetch_current(color_texture, coord + ivec2( 1, -1), projection_inverse, packedDepth); // 右上。
	vec4 data3 = gfx_taa_fetch_current(color_texture, coord + ivec2(-1,  0), projection_inverse, packedDepth); // 左侧。
	vec4 data4 = gfx_taa_fetch_current(color_texture, coord + ivec2( 0,  0), projection_inverse, packedDepth); // 中心。
	vec4 data5 = gfx_taa_fetch_current(color_texture, coord + ivec2( 1,  0), projection_inverse, packedDepth); // 右侧。
	vec4 data6 = gfx_taa_fetch_current(color_texture, coord + ivec2(-1,  1), projection_inverse, packedDepth); // 左下。
	vec4 data7 = gfx_taa_fetch_current(color_texture, coord + ivec2( 0,  1), projection_inverse, packedDepth); // 下方。
	vec4 data8 = gfx_taa_fetch_current(color_texture, coord + ivec2( 1,  1), projection_inverse, packedDepth); // 右下。
	cross_avg = data1.rgb + data3.rgb + data4.rgb + data5.rgb + data7.rgb; // 十字五点之和。
	avg_color = (cross_avg + data0.rgb + data2.rgb + data6.rgb + data8.rgb) / 9.0; // 九点均值。
	cross_avg *= 0.2; // 十字均值。
	vec3 m2 = (data0.rgb * data0.rgb + data1.rgb * data1.rgb + data2.rgb * data2.rgb + data3.rgb * data3.rgb + data4.rgb * data4.rgb
		+ data5.rgb * data5.rgb + data6.rgb * data6.rgb + data7.rgb * data7.rgb + data8.rgb * data8.rgb) / 9.0; // 二阶矩。
	vec3 variance = sqrt(m2 - avg_color * avg_color) * aggression; // 标准差乘裁剪强度得到范围半径。
	vec3 min_color = min(avg_color - variance, curr_color) * 0.5; // 范围下界，至少包住当前颜色。
	vec3 max_color = max(avg_color + variance, curr_color) * 0.5; // 范围上界。
	if (packedDepth){ // 下界还要邻域参考深度范围。
		reference_minmax = vec2(min(data0.a, min(data1.a, min(data2.a, min(data3.a, min(data4.a, min(data5.a, min(data6.a, min(data7.a, data8.a)))))))),
			max(data0.a, max(data1.a, max(data2.a, max(data3.a, max(data4.a, max(data5.a, max(data6.a, max(data7.a, data8.a))))))))); // 九点深度范围。
	}else{ // 普通维度没有参考深度。
		reference_minmax = vec2(0.0); // 占位。
	}
	avg_color = min_color + max_color; // 输出范围中心。
	return max_color - min_color; // 输出范围半径。
}

// 时间重投影：当前帧与历史帧按邻域范围、运动量、深度一致性混合；返回颜色与代表深度。
// `packedDepth` 为真时按上下界打包参考深度，`reference_depth` 回传换回屏幕深度的参考值。
vec4 gfx_taa_reproject(vec2 coord, vec3 velocity, float curr_depth_min, sampler2D current_texture, sampler2D history_texture,
		vec2 viewport, ivec2 texel_coord, mat4 projection_inverse, float far_plane, vec2 jitter,
		float blend_weight, float aggression, float depth_threshold, bool bicubic_current, bool bicubic_previous,
		bool clip_to_center, bool depth_compare, bool micro_blur, bool packedDepth, out float reference_depth){
	vec2 unjitter = coord + jitter * 0.5; // 撤销本帧抖动，取样才落在真实位置。
	vec4 curr_data = gfx_taa_sample_current(current_texture, unjitter, viewport, projection_inverse, packedDepth, bicubic_current); // 当前帧样本。
	vec3 curr_color = curr_data.rgb; // 当前帧颜色。
	vec3 avg_color = curr_color; // 邻域均值初值。
	vec3 cross_avg = curr_color; // 十字均值初值。
	vec2 reference_minmax = vec2(0.0); // 参考深度范围初值。
	vec3 variance = gfx_taa_variance_3x3(texel_coord, curr_color, current_texture, projection_inverse, packedDepth, aggression, avg_color, cross_avg, reference_minmax); // 求邻域范围。
	vec2 prev_coord = coord - velocity.xy; // 退回上一帧位置。
	vec4 prev_data = gfx_taa_sample_previous(history_texture, prev_coord, viewport, projection_inverse, packedDepth, bicubic_previous); // 读上一帧历史。
	vec3 prev_color = gfx_clip_aabb(avg_color, variance, prev_data.rgb, clip_to_center); // 把历史夹进当前范围。
	if (packedDepth){ // 下界把参考深度夹到邻域范围。
		const float depth_tolerance = 2e-5; // 参考深度容差，极小，避免抖出条纹。
		prev_data.a = clamp(prev_data.a + velocity.z, reference_minmax.x - depth_tolerance, reference_minmax.y + depth_tolerance); // 夹到邻域深度范围。
	}
	float blend = blend_weight; // 历史基础权重。
	vec2 pixel_velocity = abs(fract(velocity.xy * viewport) - 0.5) * 2.0; // 像素为单位的运动量。
	blend *= sqrt(pixel_velocity.x * pixel_velocity.y) * 0.25 + 0.75; // 运动越大历史权重越低。
	blend *= float(gfx_saturate(coord) == coord); // 上一帧坐标出屏时不用历史。
	if (depth_compare){ // 深度比较通过才保留历史权重。
		vec2 prev_depth = gfx_taa_prev_depth_minmax(history_texture, prev_coord, viewport, packedDepth); // 上一帧深度范围。
		float curr_dist = gfx_taa_linear_depth(curr_depth_min, projection_inverse); // 当前帧换成米制。
		float threshold = max(depth_threshold - curr_dist / far_plane * 0.2 * depth_threshold, 1e-5); // 越远阈值越小。
		blend *= step(prev_depth.x - curr_depth_min + velocity.z, threshold); // 历史更深一侧的一致性判断。
		blend *= step(curr_depth_min - velocity.z - prev_depth.y, threshold); // 历史更浅一侧的一致性判断。
	}
	if (micro_blur) curr_color = mix(cross_avg, curr_color, gfx_saturate(blend * 5.0 - 0.5)); // 权重低时更倾向十字均值。
	curr_color = mix(curr_color, prev_color, blend); // 按权重把历史混进当前帧。
	if (packedDepth){ // 下界参考深度也按权重混合。
		reference_depth = mix(curr_data.a, prev_data.a, blend); // 混合参考深度。
		reference_depth = gfx_taa_screen_depth(reference_depth, projection_inverse); // 换回屏幕深度再打包。
	}else{ // 普通维度不需要参考深度。
		reference_depth = 0.0; // 占位。
	}
	return vec4(gfx_ycocg_to_rgb(curr_color), curr_depth_min); // 返回颜色与代表深度。
}

#endif
