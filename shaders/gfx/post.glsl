/*
通用图形库后期模块：泛光降采样、轴向高斯模糊、三次升采样、镜头眩光、景深公式与胶片颗粒。
调用位置：任何需要多级泛光、镜头光斑或最终画面噪点的程序；本仓库由 `effects/color/bloom.glsl`、
    `effects/lens/glare.glsl`、`effects/lens/dof.glsl` 与 `effects/clarity/grain.glsl` 转发调用。
可复制示例：
    vec3 c = gfx_bloom_downsample(source, uv, texel); // 十三样本降采样。
    vec3 b = gfx_axial_gaussian_blur(source, uv, scale, origin, size, axis, 0.12, 6.0, texel); // 一维高斯。
    vec4 u = gfx_bloom_bicubic(small, uv, smallSize); // 三次升采样。
    vec3 f = gfx_glare_flare(uv, pos, -0.9, 0.02, size, 1.0); // 色散光点。
设计原因与取舍：
    纹理、像素大小、子图范围与模糊参数全部由调用方传入，库不读取引擎画面或屏幕尺寸。
    伽马编码沿用管线的四次方根近似，保证与原程序相同的亮度。
*/
#ifndef GFX_POST_INCLUDED
#define GFX_POST_INCLUDED

// 亮度权重与区间重映射来自数学模块。
#include "/gfx/math.glsl"

// 把管线编码换回线性亮度：平方两次。
float gfx_curve_to_linear(float color){
	color = color * color; // 第一次平方。
	return color * color; // 第二次平方，得到四次方。
}

// 三分量版本，逐通道做同样的平方两次。
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

// 暗角：按到画面中心的距离压暗四角，圆度控制椭圆与圆形之间的形状。
float gfx_vignette(vec2 coord, float falloff, float roundness, float aspect){
	vec2 p = coord * 2.0 - 1.0; // 转负一到一。
	p.x *= mix(1.0, aspect, roundness); // 按圆度修正横坐标。
	float rf = dot(p, p) * falloff * falloff + 1.0; // 距离平方乘强度。
	return 1.0 / (rf * rf); // 二次衰减。
}

// --- 镜头眩光与光斑：纯形状计算，屏幕位置与太阳位置都由调用方传入 ---
// 这一组函数不读取太阳颜色、雾密度或选项；可见度与亮度由效果层乘在结果上。

// 求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
// `uv` 是相对画面中心的位置，`pxoffset` 是鬼影偏移，`barrel` 是畸变强度。
vec2 gfx_glare_dist_offset(vec2 uv, vec2 pxoffset, float barrel){
	vec2 tocenter = uv.xy; // 当前点到中心的方向。
	vec3 prep = normalize(vec3(tocenter.y, -tocenter.x, 0.0)); // 与中心方向垂直的轴。
	float angle = length(tocenter.xy) * 2.221 * barrel; // 旋转角随距离增大。
	vec3 oldoffset = vec3(pxoffset, 0.0); // 把偏移抬到三维。
	vec3 rotated = oldoffset * cos(angle) + cross(prep, oldoffset) * sin(angle) + prep * dot(prep, oldoffset) * (1.0 - cos(angle)); // 绕轴旋转。
	return rotated.xy; // 取回二维偏移。
}

// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点，得到彩色边缘。
vec3 gfx_glare_flare(vec2 uv, vec2 pos, float dist, float chromaOffset, float size, float barrel){
	pos = gfx_glare_dist_offset(uv, pos, barrel); // 先对鬼影位置做桶形畸变。
	float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) *( 1.0 / (size * 2.0)), 0.0) * 0.85; // 红色通道。
	float g = max(0.01 - pow(length(uv +  dist                 * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿色通道。
	float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝色通道。
	return vec3(r, g, b); // 返回带色散的光点颜色。
}

// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
vec3 gfx_glare_orb(vec2 uv, vec2 pos, float dist, float size, float barrel){
	const float orbCount = 6.0; // 一组鬼影包含几个圆形光斑。
	vec3 c = vec3(0.0); // 累加结果。
	for (float i = 0.0; i < orbCount; i++){ // 逐个光斑。
		float j = i + 1; // 从一起数的序号。
		float offset = j / (j + 0.1); // 这个光斑在鬼影方向上的位置。
		float colOffset = j / orbCount * 0.5; // 颜色偏移。
		float ss = size / (j + 1.0); // 越靠后的光斑越小。
		c += gfx_glare_flare(uv, pos, dist + offset, ss * 2.0, ss, barrel) * vec3(1.0 - colOffset, 1.0, 0.5 + colOffset) * j; // 累加并染色放大。
	}
	c += gfx_glare_flare(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 末尾再补一个大的柔和光斑。
	return c; // 返回光斑颜色。
}

// 画一个环状光环，三个通道同样做色散。
vec3 gfx_glare_ring(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur){
	vec2 uvd = uv * length(uv); // 把坐标按到中心距离放大，得到环而不是点。
	float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红色通道。
	float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd +  dist                 * pos), blur)), 0.0) * 1.0; // 绿色通道。
	float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝色通道。
	return vec3(r, g, b); // 返回光环颜色。
}

// 胶片颗粒：把屏幕坐标与时间合成种子，折成一个正负各半的细噪点加在颜色上。
// `time` 是累计秒数，`strength` 是颗粒幅度；关闭开关由调用方决定。
vec3 gfx_film_grain(vec3 color, vec2 coord, float time, float strength){
	float seed = (coord.x + 4.0) * (coord.y + 4.0) * (time * 10.0); // 屏幕坐标与时间合成种子，时间项让它逐帧变化。
	float flicker = mod((mod(seed, 13.0) + 1.0) * (mod(seed, 123.0) + 1.0), 0.01) - 0.005; // 两次取模相乘再折叠成一个很小的数。
	return color + vec3(flicker) * strength; // 三个通道同量叠加，颗粒不改变颜色比例。
}

// 弥散圆半径：按薄透镜公式估算一个点离对焦平面越远时散焦多大。
float gfx_coc_radius(float focus, float depth, float aperture){
	return abs(aperture * (depth - focus) / (depth * focus)); // 薄透镜近似。
}

// 景深镜头倍数：焦距平方乘口径倍数，焦距与光圈取基准值时正好为一。
float gfx_dof_lens_factor(float focalLength, float aperture, float referenceFocal, float referenceAperture){
	float focalRatio = focalLength / referenceFocal; // 焦距相对基准的倍数，越长越大。
	float apertureRatio = referenceAperture / aperture; // f 值越小口径越大，取倒数表示反比。
	return focalRatio * focalRatio * apertureRatio; // 焦距平方乘口径倍数，得到模糊倍数。
}

// 米制距离换回非线性屏幕深度；景深写回下界历史时需要这个反向换算。
float gfx_screen_depth_from_linear_depth(float depth, mat4 projectionInverse){
	depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一的深度。
	return depth * 0.5 + 0.5; // 再转回零到一。
}

// 读一个坐标的米制深度；`useDh` 为真且近景没有几何时改读远景深度，再统一到近景尺度。
// 为什么把下限夹在换米制之前：近处深度趋近于零时薄透镜公式会爆炸，先夹屏幕深度最稳。
float gfx_dof_linear_depth(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse, mat4 dhProjectionInverse, bool useDh){
	float depth = textureLod(depthTexture, coord, 0.0).x; // 读含半透明的近景深度。
	if (useDh && depth == 1.0){ // 只有启用远景且近景是天空时才改读远景。
		float dhDepth = textureLod(dhDepthTexture, coord, 0.0).x; // 读远景深度。
		float meters = 1.0 / ((dhDepth * 2.0 - 1.0) * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景深度换米制。
		depth = (1.0 / meters - projectionInverse[3][3]) / projectionInverse[2][3]; // 米制换到近景投影的负一到一深度。
		depth = clamp(depth * 0.5 + 0.5, 0.0, 1.0); // 转回零到一并夹紧。
	}
	depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
	return 1.0 / ((depth * 2.0 - 1.0) * projectionInverse[2][3] + projectionInverse[3][3]); // 换成米制距离。
}

// 前景弥散范围：在螺旋上找更近且弥散更大的样本，把它们的弥散并进当前点。
// 输入是当前点、焦距、模糊量、投影缩放、镜头倍数、最大弥散、画面比例与搜索次数；输出归一化弥散范围。
float gfx_dof_coc_spread(vec2 coord, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse, mat4 dhProjectionInverse, bool useDh,
		float focus, float blur, float projectionScale, float lensFactor, float maxCoc, float aspect, int steps, vec2 noise){
	float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数：模糊量乘投影缩放与镜头倍数。
	float rMaxCoc = 1.0 / maxCoc; // 最大弥散的倒数，用来归一化。
	float rAspect = 1.0 / aspect; // 宽高比倒数，让椭圆散景在像素上是圆的。
	float currDepth = gfx_dof_linear_depth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点米制深度。
	float currCoc = gfx_coc_radius(focus, currDepth, cocRadiusfactor); // 当前点弥散半径。
	float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
	startRadius *= startRadius; // 平方，让搜索从中心附近开始。
	float spreadCoc = currCoc; // 弥散范围初值为当前点。
	float rSteps = 1.0 / float(steps); // 步数倒数。
	const float gap = 2.39996322973; // 黄金角，螺旋均匀铺开。
	const mat2 rotMat = mat2(cos(gap), sin(gap), -sin(gap), cos(gap)); // 每次旋转黄金角。
	float angle = noise.x * 6.28318530718; // 起始角由噪声给出，避免固定图案。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (int i = 0; i < steps; i++){ // 螺旋逐点搜索。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt(startRadius + (float(i) + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
		vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
		sampleOffset.x *= rAspect; // 按宽高比修正成圆。
		float sampleDepth = gfx_dof_linear_depth(coord + sampleOffset, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
		float sampleCoc = gfx_coc_radius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		if (sampleCoc >= sampleRadius && sampleDepth <= currDepth) spreadCoc = max(spreadCoc, sampleCoc); // 更近且弥散够大才并进来。
	}
	return min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
}

// 景深散焦：按存下来的弥散范围在螺旋上取样，让更近且弥散够大的样本散到当前像素上。
// `storeDepth` 为真时把散焦后的深度一起写进透明度，供下界历史使用；屏幕深度由调用方投影矩阵换算。
vec4 gfx_depth_of_field(vec2 coord, sampler2D colorTexture, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projectionInverse, mat4 dhProjectionInverse, bool useDh,
		float focus, float blur, float projectionScale, float lensFactor, float maxCoc, vec2 texel, float aspect, int quality,
		bool catEye, float catEyeMidpoint, float catEyeStrength, float anamorphic, float dispersion, bool storeDepth, vec2 noise){
	float cocRadiusfactor = blur * projectionScale * lensFactor; // 口径系数，与弥散统计共用同一换算。
	float minCoc = 0.5641895835 * texel.y; // 一个像素大小的最小弥散，避免零半径时除零。
	float rAspect = 1.0 / aspect; // 宽高比倒数。
	float currDepth = gfx_dof_linear_depth(coord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 当前点深度。
	float currCoc = gfx_coc_radius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
	currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
	vec4 currData = textureLod(colorTexture, coord, 0.0); // 当前点的曲线编码颜色与弥散范围。
	float spreadCoc = currData.a * maxCoc; // 把存下来的范围还原成半径。
	float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
	centerWeight = mix(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点很清晰时把它自己压到极小。
	vec2 catEyeOffset = vec2(0.0); // 猫眼裁剪半径；关闭时保持零。
	if (catEye){ // 只有开启猫眼效应才算裁剪。
		catEyeOffset = coord * 2.0 - 1.0; // 从中心指向当前点。
		catEyeOffset.x *= aspect; // 按宽高比修正成圆。
		float catEyeDist = length(catEyeOffset); // 到中心的距离。
		catEyeDist = max(catEyeDist - catEyeMidpoint, 0.0); // 超过中点才开始裁剪。
		catEyeDist *= spreadCoc * catEyeStrength; // 按弥散与强度缩放。
		catEyeOffset = normalize(catEyeOffset) * catEyeDist; // 得到裁剪半径。
	}
	vec3 dof = vec3(0.0); // 散焦进来的颜色累加。
	float weights = 0.0; // 样本权重累加。
	vec3 selfColor = gfx_curve_to_linear(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
	float selfSamples = 1e-20; // 自计入样本数初值极小。
	float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
	float blendedDepth = 0.0; // 散焦后的深度累加。
	float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
	const float gap = 2.39996322973; // 黄金角。
	const mat2 rotMat = mat2(cos(gap), sin(gap), -sin(gap), cos(gap)); // 每次旋转黄金角。
	float rSteps = 1.0 / float(quality); // 步数倒数。
	float angle = noise.x * 6.28318530718; // 起始角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (int i = 0; i < quality; i++){ // 螺旋采样。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt((float(i) + noise.y) * rSteps) * spreadCoc; // 样本半径。
		vec2 sampleOffset = rot * sampleRadius; // 屏幕偏移。
		if (catEye && distance(catEyeOffset, sampleOffset) > spreadCoc) continue; // 超出猫眼裁剪半径就不采。
		sampleOffset.x *= rAspect * anamorphic; // 按宽高比修正后再按变形比横向拉伸。
		vec2 sampleCoord = coord + sampleOffset; // 样本坐标。
		float sampleDepth = gfx_dof_linear_depth(sampleCoord, depthTexture, dhDepthTexture, projectionInverse, dhProjectionInverse, useDh); // 样本深度。
		float sampleCoc = gfx_coc_radius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		sampleCoc = clamp(sampleCoc, minCoc, maxCoc); // 夹到范围。
		vec3 sampleColor; // 样本线性颜色。
		if (dispersion != 1.0){ // 色散开启时红蓝通道沿到中心的方向错开。
			vec2 dispersionOffset = (coord - 0.5) * sampleRadius * (dispersion - 1.0); // 错开量随半径与到中心距离增大。
			sampleColor.r = gfx_curve_to_linear(textureLod(colorTexture, sampleCoord + dispersionOffset, 0.0).r); // 红通道向外。
			sampleColor.g = gfx_curve_to_linear(textureLod(colorTexture, sampleCoord, 0.0).g); // 绿通道不动。
			sampleColor.b = gfx_curve_to_linear(textureLod(colorTexture, sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内。
		}else{ // 默认无色散只取一次样本。
			sampleColor = gfx_curve_to_linear(textureLod(colorTexture, sampleCoord, 0.0).rgb); // 样本线性颜色。
		}
		float sampleWeight = max(1.0, currCoc / sampleCoc); // 近处前方样本权重更高。
		sampleWeight *= sampleWeight; // 平方加强。
		bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
		bool isBlurredSample = sampleCoc >= sampleRadius && sampleDepth < currDepth; // 更近且弥散够大，散焦进来。
		if (isSelfSample){ // 属于当前点自己。
			selfColor += sampleColor; // 记为自贡献。
			selfSamples += 1.0; // 自贡献样本数。
		}else if (isBlurredSample){ // 散焦进来。
			dof += sampleColor * sampleWeight; // 累加散焦颜色。
			weights += sampleWeight; // 累加权重。
		}else{ // 不满足条件，记进中心权重。
			selfWeights += centerWeight; // 累加中心权重。
		}
		if (isSelfSample) selfDepth += sampleDepth; // 自己的样本累加深度。
		else if (isBlurredSample) blendedDepth += sampleDepth * sampleWeight; // 散焦样本按权重累加深度。
	}
	dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
	dof /= weights + selfSamples + selfWeights; // 归一化。
	if (!storeDepth) return vec4(gfx_linear_to_curve(dof), 0.0); // 主世界与末地不写深度。
	blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 下界把深度按同一套补偿。
	blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
	return vec4(gfx_linear_to_curve(dof), gfx_screen_depth_from_linear_depth(blendedDepth, projectionInverse)); // 返回颜色与换回的屏幕深度。
}

// --- 五级泛光链：降采样、两级轴向高斯与最终合并，各级参数照原程序保留 ---
// 每一级的核半径与样本数是固定内部常数，改一项都会改变光晕形状，所以集中写在这里。
#define GFX_BLOOM_SIZE_LOD3 0.16 // 第三级核半径。
#define GFX_BLOOM_SIZE_LOD4 0.035 // 第四级核半径。
#define GFX_BLOOM_SIZE_LOD5 0.0085 // 第五级核半径。
#define GFX_BLOOM_SIZE_LOD6 0.002 // 第六级核半径。
#define GFX_BLOOM_SIZE_LOD7 0.0005 // 第七级核半径。
#define GFX_BLOOM_SIZE_LOD8 0.00015 // 第八级核半径。
#define GFX_BLOOM_STEP_LOD3 2.0 // 第三级轴向样本数。
#define GFX_BLOOM_STEP_LOD4 5.0 // 第四级轴向样本数。
#define GFX_BLOOM_STEP_LOD5 12.0 // 第五级轴向样本数。
#define GFX_BLOOM_STEP_LOD6 28.0 // 第六级轴向样本数。
#define GFX_BLOOM_STEP_LOD7 50.0 // 第七级轴向样本数。
#define GFX_BLOOM_STEP_LOD8 90.0 // 第八级轴向样本数。

// 泛光第一级：把场景画面降采样到半分辨率；画面外的坐标返回黑色。
vec4 gfx_bloom_downsample_scene(sampler2D sceneTexture, vec2 coord, vec2 texel){
	vec2 sampleCoord = coord * 2.0; // 采样坐标放大两倍，对应半分辨率画面。
	vec2 border = texel * 4.0 + 1.0; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) blur = gfx_bloom_downsample(sceneTexture, sampleCoord, texel); // 只在画面范围内采样。
	return vec4(blur, 0.0); // 交回五号画面要写的内容。
}

// 泛光第二级：从上一级泛光图继续降采样。
vec4 gfx_bloom_downsample_chain(sampler2D chainTexture, vec2 coord, vec2 texel){
	vec2 sampleCoord = coord * 2.0; // 采样坐标放大两倍。
	vec2 border = texel * 2.0 + 0.5; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) blur = gfx_bloom_downsample(chainTexture, sampleCoord, texel); // 只在画面范围内采样。
	return vec4(blur, 0.0); // 交回五号画面要写的内容。
}

// 泛光第三级：横向轴向高斯，链上各级排成一行。
vec4 gfx_bloom_blur_horizontal(sampler2D chainTexture, vec2 coord, vec2 texel){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 borderWidth = texel; // 边界用一像素宽。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 border = originSize + borderWidth; // 当前级的边界。
	vec2 axis = vec2(1.0, 0.0); // 横向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 local = coord; // 在本级内推进的坐标。
	if (local.x <= border.x && local.y <= border.y) blur = gfx_curve_to_linear(textureLod(chainTexture, clamp(local, vec2(0.0), originSize), 0.0).rgb); // 第二级直接抄。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 下一级宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(2.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD3, GFX_BLOOM_STEP_LOD3, texel); // 第三级横向模糊。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(4.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD4, GFX_BLOOM_STEP_LOD4, texel); // 第四级。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(8.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD5, GFX_BLOOM_STEP_LOD5, texel); // 第五级。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(16.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD6, GFX_BLOOM_STEP_LOD6, texel); // 第六级。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(32.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD7, GFX_BLOOM_STEP_LOD7, texel); // 第七级。
	local.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, local, vec2(64.0, 1.0), 0.0, originSize, axis, GFX_BLOOM_SIZE_LOD8, GFX_BLOOM_STEP_LOD8, texel); // 第八级。
	return vec4(gfx_linear_to_curve(blur), 0.0); // 编码后交回五号画面要写的内容。
}

// 泛光第四级：纵向轴向高斯，采样坐标回拧到各级自己的起点。
vec4 gfx_bloom_blur_vertical(sampler2D chainTexture, vec2 coord, vec2 texel){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 borderWidth = texel; // 边界用一像素宽。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 border = originSize + borderWidth; // 当前级的边界。
	vec2 axis = vec2(0.0, 1.0); // 纵向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 local = coord; // 用于判断落在哪一级的坐标。
	if (local.x <= border.x && local.y <= border.y) blur = gfx_curve_to_linear(textureLod(chainTexture, clamp(local, vec2(0.0), originSize), 0.0).rgb); // 第二级直接抄。
	float currInterval = originSize.x + texel.x * intervalWidth; // 当前级宽度加间隔。
	local.x -= currInterval; // 移到下一级。
	float sampleOrigin = currInterval; // 当前级在图里的起始横坐标。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 2.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD3, GFX_BLOOM_STEP_LOD3, texel); // 第三级纵向核。
	currInterval = originSize.x + texel.x * intervalWidth; // 下一级的间隔。
	local.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 4.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD4, GFX_BLOOM_STEP_LOD4, texel); // 第四级。
	currInterval = originSize.x + texel.x * intervalWidth; // 下一级的间隔。
	local.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 8.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD5, GFX_BLOOM_STEP_LOD5, texel); // 第五级。
	currInterval = originSize.x + texel.x * intervalWidth; // 下一级的间隔。
	local.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 16.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD6, GFX_BLOOM_STEP_LOD6, texel); // 第六级。
	currInterval = originSize.x + texel.x * intervalWidth; // 下一级的间隔。
	local.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 32.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD7, GFX_BLOOM_STEP_LOD7, texel); // 第七级。
	currInterval = originSize.x + texel.x * intervalWidth; // 下一级的间隔。
	local.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (local.x >= -borderWidth.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chainTexture, coord, vec2(1.0, 64.0), sampleOrigin, originSize, axis, GFX_BLOOM_SIZE_LOD8, GFX_BLOOM_STEP_LOD8, texel); // 第八级。
	return vec4(gfx_linear_to_curve(blur), 0.0); // 编码后交回五号画面要写的内容。
}

// 泛光第五级：把各级三次模糊后的结果按权重叠成一张光晕，雨里权重更高。
vec4 gfx_bloom_combine(sampler2D chainTexture, vec2 coord, vec2 texel, vec2 screen_size, float rainAlpha){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 tCoord = coord * 2.0; // 采样坐标放大两倍。
	vec2 border = texel * 8.0 + 1.0; // 允许超出的边界。
	vec2 local = coord; // 当前级坐标。
	vec2 sampleOrigin = vec2(0.0); // 当前级在图里的起始横坐标。
	vec3 bloom = vec3(0.0); // 累积光晕。
	if (tCoord.x <= border.x && tCoord.y <= border.y){ // 只在画面范围内叠加。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.5, screen_size).rgb) * 1.0; // 第二级直接取。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.25 - sampleOrigin, screen_size).rgb) * mix(0.83333333, 1.0, rainAlpha); // 第三级，雨里权重更高。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.125 - sampleOrigin, screen_size).rgb) * mix(0.69444444, 1.0, rainAlpha); // 第四级。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.0625 - sampleOrigin, screen_size).rgb) * mix(0.57870370, 1.0, rainAlpha); // 第五级。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.03125 - sampleOrigin, screen_size).rgb) * mix(0.48225309, 1.0, rainAlpha); // 第六级。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.015625 - sampleOrigin, screen_size).rgb) * mix(0.40187757, 1.0, rainAlpha); // 第七级。
		sampleOrigin.x -= originSize.x + texel.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chainTexture, local * 0.0078125 - sampleOrigin, screen_size).rgb) * mix(0.33489798, 1.0, rainAlpha); // 第八级。
	}
	bloom *= mix(0.2774, 1.2 / 7.0, rainAlpha); // 雨里整体提亮，原程序保留的常数。
	return vec4(gfx_linear_to_curve(bloom), 0.0); // 编码后交回五号画面要写的内容。
}

// --- 自动曝光分块统计：把画面按多级纹理的块大小切开，逐块取亮度后加权平均 ---
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
// 为什么用加权而不是直接平均：人眼更在意画面中心与偏离整体亮度的区域，权重让测光更接近相机行为。
// 所有画面尺寸、像素大小与选项都由调用方传入，库不读取任何引擎状态。
struct gfx_exposure_params {
	vec2 screen_size; // 画面像素尺寸。
	vec2 pixel_size; // 一个像素在零到一坐标里的大小。
	int lod; // 多级纹理层级，决定一块覆盖多少像素。
	float luma_scale; // 管线亮度换算系数。
	float average; // 用一张粗样本估出的整体亮度，供亮度计权使用。
	int mode; // 测光方式：零默认、一中心权重、二只看中心、三全屏平均。
	int luminance_mode; // 亮度计权方式：零关闭，一到四对应四种曲线。
	float luminance_strength; // 亮度计权的强度。
	bool end_dimension; // 是否末地，末地默认测光不看中心。
	bool nether; // 是否下界，亮度计权在下界用固定指数。
	bool cave_mode; // 是否洞穴模式，洞穴按偏离整体亮度计权。
	bool overworld; // 是否主世界，亮度计权的指数范围与末地不同。
};

// 返回加权平均亮度，单位与输入画面一致；调用方再乘曝光输出系数并编码。
float gfx_exposure_tile_average(sampler2D scene_texture, gfx_exposure_params params){
	float tile_scale = exp2(float(params.lod)); // 一个块覆盖多少像素。
	vec2 tile_count = floor(params.screen_size / tile_scale); // 每行每列有多少块。
	vec2 tile_center = tile_count * 0.5; // 块网格的中心。
	float exposure = 0.0; // 加权亮度累加。
	float weights = 0.0; // 权重累加。
	for (int x = 0; x < tile_count.x; x++){ // 逐列遍历块。
		for (int y = 0; y < tile_count.y; y++){ // 逐行遍历块。
			float tile_exposure = gfx_math_luminance(gfx_curve_to_linear(texelFetch(scene_texture, ivec2(x, y), params.lod).rgb)) * params.luma_scale; // 这个块的亮度。
			vec2 tile_distance = (tile_center - vec2(x, y) + 0.5) * params.pixel_size * tile_scale * 2.0; // 块中心到画面中心的屏幕距离。
			float center_distance = length(tile_distance); // 到画面中心的距离。
			float tile_weight = 1.0; // 块权重，先给等权。
			if (params.mode == 0){ // 默认测光。
				tile_weight = params.end_dimension ? 1.0 : gfx_remapSaturate(center_distance, 0.6, 0.4); // 末地等权，其他维度越靠中心越高。
			}else if (params.mode == 1){ // 中心权重较强。
				tile_weight = gfx_remapSaturate(center_distance, 0.7, 0.0); // 中心权重曲线。
				tile_weight *= tile_weight; // 再平方，中心更突出。
			}else if (params.mode == 2){ // 只看中心。
				tile_weight = gfx_remapSaturate(center_distance, 0.6, 0.4); // 与默认相同的曲线。
			}
			tile_exposure = max(6.4e-9, tile_exposure); // 避免全黑块把权重推到无穷。
			if (params.cave_mode && params.overworld){ // 洞穴模式且在主世界时按偏离程度计权。
				float cave_weight = params.average / tile_exposure; // 相对整体亮度的比例。
				tile_weight *= pow(cave_weight, 0.7); // 越偏离整体亮度权重越大，适应洞穴。
			}else if (params.luminance_mode > 0){ // 其他情况按亮度计权方式。
				float luma_weight = 1.0; // 相对亮度权重。
				if (params.luminance_mode == 1){ // 预设一。
					luma_weight = params.average / tile_exposure; // 相对亮度。
					if (params.nether){ // 下界用固定指数。
						luma_weight = pow(luma_weight, 0.7);
					}else if (params.overworld){ // 主世界按整体亮度调指数。
						luma_weight = pow(luma_weight, gfx_remapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.7); // 暗环境更偏向亮块。
					}else{ // 末地指数范围不同。
						luma_weight = pow(luma_weight, gfx_remapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地曲线。
					}
				}else if (params.luminance_mode == 2){ // 预设二。
					luma_weight = params.average / tile_exposure; // 相对亮度。
					luma_weight = pow(luma_weight, params.nether ? 0.7 : gfx_remapSaturate(params.average, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 下界固定，其余用较平的曲线。
				}else if (params.luminance_mode == 3){ // 偏向暗部。
					luma_weight = pow(params.average / tile_exposure, params.luminance_strength); // 用选项给的强度。
				}else{ // 偏向高光。
					luma_weight = pow(tile_exposure / params.average, params.luminance_strength); // 比例取反。
				}
				tile_weight *= luma_weight; // 把亮度权重乘进块权重。
			}
			exposure += tile_exposure * tile_weight; // 累加加权亮度。
			weights += tile_weight; // 累加权重。
		}
	}
	return exposure / weights; // 加权平均。
}
#endif
