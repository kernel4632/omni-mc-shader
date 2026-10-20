/*
通用图形库后期模块：泛光降采样、轴向高斯模糊与三次升采样。
调用位置：任何需要多级泛光的程序；本仓库由 `effects/color/bloom.glsl` 转发调用。
可复制示例：
    vec3 c = gfx_bloom_downsample(source, uv, texel); // 十三样本降采样。
    vec3 b = gfx_axial_gaussian_blur(source, uv, scale, origin, size, axis, 0.12, 6.0, texel); // 一维高斯。
    vec4 u = gfx_bloom_bicubic(small, uv, smallSize); // 三次升采样。
设计原因与取舍：
    纹理、像素大小、子图范围与模糊参数全部由调用方传入，库不读取引擎画面或屏幕尺寸。
    伽马编码沿用管线的四次方根近似，保证与原程序相同的亮度。
*/
#ifndef GFX_POST_INCLUDED
#define GFX_POST_INCLUDED

// 把管线编码换回线性亮度：平方两次。
vec3 gfx_curve_to_linear(vec3 color){
	color = color * color; // 第一次平方。
	return color * color; // 第二次平方，得到四次方。
}

// 把线性亮度换成管线编码：四次方根。
vec3 gfx_linear_to_curve(vec3 color){
	return pow(color, vec3(0.25)); // 四次方根编码。
}

// 十三样本降采样：中心小、四角大，权重和为四，输出乘四分之一保持亮度。
vec3 gfx_bloom_downsample(sampler2D source, vec2 coord, vec2 texel){
	vec3 blur = gfx_curve_to_linear(textureLod(source, coord, 0.0).rgb) * 0.125; // 中心样本。
	blur += gfx_curve_to_linear(textureLod(source, coord + vec2(texel.x, texel.y), 0.0).rgb) * 0.5; // 右下对角。
	blur += gfx_curve_to_linear(textureLod(source, coord + vec2(texel.x, -texel.y), 0.0).rgb) * 0.5; // 右上对角。
	blur += gfx_curve_to_linear(textureLod(source, coord + vec2(-texel.x, texel.y), 0.0).rgb) * 0.5; // 左下对角。
	blur += gfx_curve_to_linear(textureLod(source, coord + vec2(-texel.x, -texel.y), 0.0).rgb) * 0.5; // 左上对角。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(texel.x, 0.0), 0.0).rgb) * 0.25; // 右两像素。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(0.0, texel.y), 0.0).rgb) * 0.25; // 上两像素。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(-texel.x, 0.0), 0.0).rgb) * 0.25; // 左两像素。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(0.0, -texel.y), 0.0).rgb) * 0.25; // 下两像素。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(texel.x, texel.y), 0.0).rgb) * 0.125; // 远处右下。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处右上。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(-texel.x, texel.y), 0.0).rgb) * 0.125; // 远处左下。
	blur += gfx_curve_to_linear(textureLod(source, coord + 2.0 * vec2(-texel.x, -texel.y), 0.0).rgb) * 0.125; // 远处左上。
	return gfx_linear_to_curve(blur * 0.25); // 权重和为四，乘四分之一保持亮度。
}

// 沿一个方向做长条高斯，横竖各一次等价于二维高斯，样本数从平方降到线性。
vec3 gfx_axial_gaussian_blur(sampler2D source, vec2 coord, vec2 coordScale, float sampleOrigin, vec2 sampleSize, vec2 axis, float alpha, float steps, vec2 texel){
	vec3 blur = vec3(0.0); // 累积颜色。
	float weights = 0.0; // 累积权重。
	for (float i = -steps; i <= steps; i++){ // 从负步长到正步长。
		float sampleWeight = exp2(-i * i * alpha * 5.77); // 高斯权重。
		vec2 sampleCoord = coord + axis / coordScale * texel * i * 2.0; // 当前方向的取样坐标。
		vec2 original = sampleCoord; // 记录原始坐标，用来判断是否越界。
		sampleCoord = clamp(sampleCoord, vec2(sampleOrigin, 0.0), vec2(sampleOrigin + sampleSize.x, sampleSize.y)); // 夹在当前级范围。
		sampleWeight *= float(original == sampleCoord) + 1e-20; // 被夹过的样本不参与。
		sampleCoord *= coordScale; // 还原成读取该级的坐标。
		blur += gfx_curve_to_linear(textureLod(source, sampleCoord, 0.0).rgb) * sampleWeight; // 累加样本。
		weights += sampleWeight; // 累加权重。
	}
	return blur / weights; // 归一化，样本少时亮度不变。
}

// 三次升采样：四次双线性采样合成十六像素的三次模糊。
vec4 gfx_bloom_bicubic(sampler2D source, vec2 coord, vec2 texSize){
	vec2 texel = 1.0 / texSize; // 一个像素的坐标大小。
	coord = coord * texSize - 0.5; // 换成以像素中心为原点。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 前两个权重。
	vec4 w1; // 后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
	w1.yw = ff * f; // 第四个权重。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
	c *= texel.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样的混合比例。
	return mix(mix(textureLod(source, c.yw, 0.0), textureLod(source, c.xw, 0.0), m.x),
	           mix(textureLod(source, c.yz, 0.0), textureLod(source, c.xz, 0.0), m.x),
	           m.y); // 四次采样合成模糊。
}

// 亮度曲线：暗部与亮部各一条抛物线，通道独立处理避免串色。
float gfx_lower_curve(float x){
	return clamp(16.0 * x * (0.5 - x) * 0.1, 0.0, 1.0); // 峰在四分之一附近。
}

// 亮部曲线：在亮端抬起一段抛物线。
float gfx_upper_curve(float x){
	return clamp(16.0 * (0.5 - x) * (x - 1.0) * 0.1, 0.0, 1.0); // 峰在四分之三附近。
}

// 把暗部与亮部修正同时加到三个通道，系数由调用方传入。
vec3 gfx_luminance_curve(vec3 color, float lower, float upper){
	color.r += lower * gfx_lower_curve(color.r) + upper * gfx_upper_curve(color.r); // 红通道。
	color.g += lower * gfx_lower_curve(color.g) + upper * gfx_upper_curve(color.g); // 绿通道。
	color.b += lower * gfx_lower_curve(color.b) + upper * gfx_upper_curve(color.b); // 蓝通道。
	return color;
}

// 把三个通道归一化成染色方向；接近零时返回零，避免除零。
vec3 gfx_grade_target(float red, float green, float blue){
	vec3 target = vec3(red, green, blue); // 原始目标向量。
	return length(target) < 0.001 ? vec3(0.0) : normalize(target); // 太短就没有方向。
}
#endif
