/*
后期模块适配层：泛光核、景深、颗粒与测光统计已迁到生成库，五级泛光的子图排布留在光影侧。
调用位置：`effects/color/bloom.glsl`、`effects/lens/dof.glsl`、`effects/lens/glare.glsl`、
    `effects/clarity/grain.glsl`、`effects/lens/motion_blur.glsl` 与 `effects/color/color.glsl` 引用本文件。
可复制示例：`vec3 c = gfx_bloom_downsample(source, uv, texel);` 十三样本降采样，实现在生成库。
设计原因与取舍：子图排布依赖光影中间画面的布局，属于宿主约定，迁到通用库会把布局写死；
    核函数、景深与测光与宿主无关，全部在 `omni-gfx/src/post.slang`，两边通过同名转发连接。
*/
#ifndef GFX_POST_INCLUDED
#define GFX_POST_INCLUDED

// 迁移后的后期实现：泛光核、亮度曲线、暗角、颗粒、景深、动态模糊与测光。
#include "/omni-gfx/post.glsl"

// 光影侧的测光参数结构体：字段名与生成库一致，这里只把类型名接上。
#define gfx_exposure_params OgxExposureParams

// 把管线编码换回线性亮度：平方两次。
float gfx_curve_to_linear(float color) { // 标量版本。
	return ogxCurveToLinear(color); // 实现在生成库。
}

// 三分量版本，逐通道做同样的平方两次。
vec3 gfx_curve_to_linear(vec3 color) { // 向量版本。
	return ogxCurveToLinear3(color); // 实现在生成库。
}

// 把线性亮度换成管线编码：四次方根。
vec3 gfx_linear_to_curve(vec3 color) { // 向量版本。
	return ogxLinearToCurve3(color); // 实现在生成库。
}

// 十三样本降采样：中心小、四角大。
vec3 gfx_bloom_downsample(sampler2D source, vec2 coord, vec2 texel) { // 泛光第一级核。
	return ogxBloomDownsample(source, coord, texel); // 实现在生成库。
}

// 泛光链某一级的原样拷贝：坐标夹在本级子图范围内再读零号层级。
vec3 gfx_bloom_chain_copy(sampler2D chain_texture, vec2 local, vec2 origin_size) { // 链上单级拷贝。
	return ogxBloomChainCopy(chain_texture, local, origin_size); // 实现在生成库。
}

// 沿一个方向做长条高斯，横竖各一次等价于二维高斯。
vec3 gfx_axial_gaussian_blur(sampler2D source, vec2 coord, vec2 coord_scale, float sample_origin, vec2 sample_size, vec2 axis, float alpha, float steps, vec2 texel) { // 轴向高斯核。
	return ogxAxialGaussianBlur(source, coord, coord_scale, sample_origin, sample_size, axis, alpha, steps, texel); // 实现在生成库。
}

// 三次升采样：四次双线性采样合成十六像素的三次模糊。
vec4 gfx_bloom_bicubic(sampler2D source, vec2 coord, vec2 tex_size) { // 泛光升采样核。
	return ogxBloomBicubic(source, coord, tex_size); // 实现在生成库。
}

// 亮度曲线：暗部与亮部各一条抛物线。
float gfx_lower_curve(float x) { // 暗部曲线。
	return ogxLowerCurve(x); // 实现在生成库。
}

// 亮部曲线：在亮端抬起一段抛物线。
float gfx_upper_curve(float x) { // 亮部曲线。
	return ogxUpperCurve(x); // 实现在生成库。
}

// 把暗部与亮部修正同时加到三个通道。
vec3 gfx_luminance_curve(vec3 color, float lower, float upper) { // 亮度修正。
	return ogxLuminanceCurve(color, lower, upper); // 实现在生成库。
}

// 把三个通道归一化成染色方向。
vec3 gfx_grade_target(float red, float green, float blue) { // 调色目标。
	return ogxGradeTarget(red, green, blue); // 实现在生成库。
}

// 暗角：按到画面中心的距离压暗四角。
float gfx_vignette(vec2 coord, float falloff, float roundness, float aspect) { // 暗角权重。
	return ogxVignette(coord, falloff, roundness, aspect); // 实现在生成库。
}

// 胶片颗粒：把屏幕坐标与时间合成种子，折成细噪点。
vec3 gfx_film_grain(vec3 color, vec2 coord, float time, float strength) { // 胶片颗粒。
	return ogxFilmGrain(color, coord, time, strength); // 实现在生成库。
}

// 弥散圆半径：按薄透镜公式估算散焦大小。
float gfx_coc_radius(float focus, float depth, float aperture) { // 弥散圆半径。
	return ogxCocRadius(focus, depth, aperture); // 实现在生成库。
}

// 景深镜头倍数：焦距平方乘口径倍数。
float gfx_dof_lens_factor(float focal_length, float aperture, float reference_focal, float reference_aperture) { // 镜头倍数。
	return ogxDofLensFactor(focal_length, aperture, reference_focal, reference_aperture); // 实现在生成库。
}

// 米制距离换回非线性屏幕深度。
float gfx_screen_depth_from_linear_depth(float depth, mat4 projection_inverse) { // 深度反向换算。
	return ogxScreenDepthFromLinearDepth(depth, projection_inverse); // 实现在生成库。
}

// 读一个坐标的米制深度，远景按开关改读。
float gfx_dof_linear_depth(vec2 coord, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection_inverse, mat4 dh_projection_inverse, bool use_dh) { // 景深深度读取。
	return ogxDofLinearDepth(coord, depth_texture, dh_depth_texture, projection_inverse, dh_projection_inverse, use_dh); // 实现在生成库。
}

// 前景弥散范围：在螺旋上找更近且弥散更大的样本。
float gfx_dof_coc_spread(vec2 coord, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection_inverse, mat4 dh_projection_inverse, bool use_dh, float focus, float blur, float projection_scale, float lens_factor, float max_coc, float aspect, int steps, vec2 noise) { // 前景弥散统计。
	return ogxDofCocSpread(coord, depth_texture, dh_depth_texture, projection_inverse, dh_projection_inverse, use_dh, focus, blur, projection_scale, lens_factor, max_coc, aspect, steps, noise); // 实现在生成库。
}

// 景深散焦：按存下来的弥散范围在螺旋上取样。
vec4 gfx_depth_of_field(vec2 coord, sampler2D color_texture, sampler2D depth_texture, sampler2D dh_depth_texture, mat4 projection_inverse, mat4 dh_projection_inverse, bool use_dh, float focus, float blur, float projection_scale, float lens_factor, float max_coc, vec2 texel, float aspect, int quality, bool cat_eye, float cat_eye_midpoint, float cat_eye_strength, float anamorphic, float dispersion, bool store_depth, vec2 noise) { // 散焦主循环。
	return ogxDepthOfField(coord, color_texture, depth_texture, dh_depth_texture, projection_inverse, dh_projection_inverse, use_dh, focus, blur, projection_scale, lens_factor, max_coc, texel, aspect, quality, cat_eye, cat_eye_midpoint, cat_eye_strength, anamorphic, dispersion, store_depth, noise); // 实现在生成库。
}

// 相机动态模糊：沿两帧之间的屏幕位移取一串样本。
vec3 gfx_motion_blur(sampler2D color_texture, vec2 coord, ivec2 texel, vec2 pixel, vec2 velocity, float shutter_angle, int quality, bool dither) { // 动态模糊。
	return ogxMotionBlur(color_texture, coord, texel, pixel, velocity, shutter_angle, quality, dither); // 实现在生成库。
}

// 自动曝光分块统计：返回加权平均亮度。
float gfx_exposure_tile_average(sampler2D scene_texture, gfx_exposure_params params) { // 测光统计。
	return ogxExposureTileAverage(scene_texture, params); // 实现在生成库。
}

// 五级泛光链的核半径：每一级的形状由这些固定常数决定。
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
vec4 gfx_bloom_downsample_scene(sampler2D scene_texture, vec2 coord, vec2 texel) { // 泛光链入口。
	vec2 sample_coord = coord * 2.0; // 采样坐标放大两倍，对应半分辨率画面。
	vec2 border = texel * 4.0 + 1.0; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sample_coord.x <= border.x && sample_coord.y <= border.y) blur = gfx_bloom_downsample(scene_texture, sample_coord, texel); // 只在画面范围内采样。
	return vec4(blur, 0.0); // 交回五号画面要写的内容。
}

// 泛光第二级：从上一级泛光图继续降采样。
vec4 gfx_bloom_downsample_chain(sampler2D chain_texture, vec2 coord, vec2 texel) { // 泛光链降采样。
	vec2 sample_coord = coord * 2.0; // 采样坐标放大两倍。
	vec2 border = texel * 2.0 + 0.5; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sample_coord.x <= border.x && sample_coord.y <= border.y) blur = gfx_bloom_downsample(chain_texture, sample_coord, texel); // 只在画面范围内采样。
	return vec4(blur, 0.0); // 交回五号画面要写的内容。
}

// 泛光第三级：横向轴向高斯，链上各级排成一行。
vec4 gfx_bloom_blur_horizontal(sampler2D chain_texture, vec2 coord, vec2 texel) { // 横向模糊。
	vec2 origin_size = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 border_width = texel; // 边界用一像素宽。
	float interval_width = 3.0; // 级与级之间隔三像素。
	vec2 border = origin_size + border_width; // 当前级的边界。
	vec2 axis = vec2(1.0, 0.0); // 横向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 local = coord; // 在本级内推进的坐标。
	if (local.x <= border.x && local.y <= border.y) blur = gfx_bloom_chain_copy(chain_texture, local, origin_size); // 第二级直接抄。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 下一级宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(2.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD3, GFX_BLOOM_STEP_LOD3, texel); // 第三级横向模糊。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(4.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD4, GFX_BLOOM_STEP_LOD4, texel); // 第四级。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(8.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD5, GFX_BLOOM_STEP_LOD5, texel); // 第五级。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(16.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD6, GFX_BLOOM_STEP_LOD6, texel); // 第六级。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(32.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD7, GFX_BLOOM_STEP_LOD7, texel); // 第七级。
	local.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
	origin_size.x *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, local, vec2(64.0, 1.0), 0.0, origin_size, axis, GFX_BLOOM_SIZE_LOD8, GFX_BLOOM_STEP_LOD8, texel); // 第八级。
	return vec4(gfx_linear_to_curve(blur), 0.0); // 编码后交回五号画面要写的内容。
}

// 泛光第四级：纵向轴向高斯，采样坐标回拧到各级自己的起点。
vec4 gfx_bloom_blur_vertical(sampler2D chain_texture, vec2 coord, vec2 texel) { // 纵向模糊。
	vec2 origin_size = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 border_width = texel; // 边界用一像素宽。
	float interval_width = 3.0; // 级与级之间隔三像素。
	vec2 border = origin_size + border_width; // 当前级的边界。
	vec2 axis = vec2(0.0, 1.0); // 纵向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 local = coord; // 用于判断落在哪一级的坐标。
	if (local.x <= border.x && local.y <= border.y) blur = gfx_bloom_chain_copy(chain_texture, local, origin_size); // 第二级直接抄。
	float curr_interval = origin_size.x + texel.x * interval_width; // 当前级宽度加间隔。
	local.x -= curr_interval; // 移到下一级。
	float sample_origin = curr_interval; // 当前级在图里的起始横坐标。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 2.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD3, GFX_BLOOM_STEP_LOD3, texel); // 第三级纵向核。
	curr_interval = origin_size.x + texel.x * interval_width; // 下一级的间隔。
	local.x -= curr_interval; // 移到下一级。
	sample_origin += curr_interval; // 起始横坐标前移。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 4.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD4, GFX_BLOOM_STEP_LOD4, texel); // 第四级。
	curr_interval = origin_size.x + texel.x * interval_width; // 下一级的间隔。
	local.x -= curr_interval; // 移到下一级。
	sample_origin += curr_interval; // 起始横坐标前移。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 8.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD5, GFX_BLOOM_STEP_LOD5, texel); // 第五级。
	curr_interval = origin_size.x + texel.x * interval_width; // 下一级的间隔。
	local.x -= curr_interval; // 移到下一级。
	sample_origin += curr_interval; // 起始横坐标前移。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 16.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD6, GFX_BLOOM_STEP_LOD6, texel); // 第六级。
	curr_interval = origin_size.x + texel.x * interval_width; // 下一级的间隔。
	local.x -= curr_interval; // 移到下一级。
	sample_origin += curr_interval; // 起始横坐标前移。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 32.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD7, GFX_BLOOM_STEP_LOD7, texel); // 第七级。
	curr_interval = origin_size.x + texel.x * interval_width; // 下一级的间隔。
	local.x -= curr_interval; // 移到下一级。
	sample_origin += curr_interval; // 起始横坐标前移。
	origin_size *= 0.5; // 宽度减半。
	border = origin_size + border_width; // 更新边界。
	if (local.x >= -border_width.x && local.x <= border.x && local.y <= border.y) blur = gfx_axial_gaussian_blur(chain_texture, coord, vec2(1.0, 64.0), sample_origin, origin_size, axis, GFX_BLOOM_SIZE_LOD8, GFX_BLOOM_STEP_LOD8, texel); // 第八级。
	return vec4(gfx_linear_to_curve(blur), 0.0); // 编码后交回五号画面要写的内容。
}

// 泛光第五级：把各级三次模糊后的结果按权重叠成一张光晕，雨里权重更高。
vec4 gfx_bloom_combine(sampler2D chain_texture, vec2 coord, vec2 texel, vec2 screen_size, float rain_alpha) { // 泛光合并。
	vec2 origin_size = vec2(0.25); // 每一级占画面宽度的初值。
	float interval_width = 3.0; // 级与级之间隔三像素。
	vec2 t_coord = coord * 2.0; // 采样坐标放大两倍。
	vec2 border = texel * 8.0 + 1.0; // 允许超出的边界。
	vec2 local = coord; // 当前级坐标。
	vec2 sample_origin = vec2(0.0); // 当前级在图里的起始横坐标。
	vec3 bloom = vec3(0.0); // 累积光晕。
	if (t_coord.x <= border.x && t_coord.y <= border.y) { // 只在画面范围内叠加。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.5, screen_size).rgb) * 1.0; // 第二级直接取。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.25 - sample_origin, screen_size).rgb) * mix(0.83333333, 1.0, rain_alpha); // 第三级。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.125 - sample_origin, screen_size).rgb) * mix(0.69444444, 1.0, rain_alpha); // 第四级。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.0625 - sample_origin, screen_size).rgb) * mix(0.57870370, 1.0, rain_alpha); // 第五级。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.03125 - sample_origin, screen_size).rgb) * mix(0.48225309, 1.0, rain_alpha); // 第六级。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.015625 - sample_origin, screen_size).rgb) * mix(0.40187757, 1.0, rain_alpha); // 第七级。
		sample_origin.x -= origin_size.x + texel.x * interval_width; // 移到下一级。
		origin_size *= 0.5; // 宽度减半。
		bloom += gfx_curve_to_linear(gfx_bloom_bicubic(chain_texture, local * 0.0078125 - sample_origin, screen_size).rgb) * mix(0.33489798, 1.0, rain_alpha); // 第八级。
	}
	bloom *= mix(0.2774, 1.2 / 7.0, rain_alpha); // 雨里整体提亮，原程序保留的常数。
	return vec4(gfx_linear_to_curve(bloom), 0.0); // 编码后交回五号画面要写的内容。
}

// 镜头眩光：求一个偏移向量在桶形畸变后的方向，用于把鬼影沿弧线排列。
vec2 gfx_glare_dist_offset(vec2 uv, vec2 pxoffset, float barrel){
	return ogxGlareDistOffset(uv, pxoffset, barrel); // 实现在生成库。
}

// 画一个带色散的软光点：红绿蓝三个通道沿鬼影方向错开一点。
vec3 gfx_glare_flare(vec2 uv, vec2 pos, float dist, float chroma_offset, float size, float barrel){
	return ogxGlareFlare(uv, pos, dist, chroma_offset, size, barrel); // 实现在生成库。
}

// 画一串沿鬼影方向排列的圆形光斑，颜色从暖到冷渐变。
vec3 gfx_glare_orb(vec2 uv, vec2 pos, float dist, float size, float barrel){
	return ogxGlareOrb(uv, pos, dist, size, barrel); // 实现在生成库。
}

// 画一个环状光环，三个通道同样做色散。
vec3 gfx_glare_ring(vec2 uv, vec2 pos, float dist, float chroma_offset, float blur){
	return ogxGlareRing(uv, pos, dist, chroma_offset, blur); // 实现在生成库。
}

#endif
