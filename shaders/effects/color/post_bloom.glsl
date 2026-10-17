/*
后期泛光链：`composite9` 到 `composite13` 五个程序的算法体，做泛光的降采样、横向与纵向轴向模糊，最后叠成光晕。
职责：第一级从一号画面降采样，第二级从五号画面继续降采样；第三、四级各自在一条横排的小图上做轴向高斯；
    第五级把各级三次模糊后的结果按权重叠成一张光晕，雨里把权重抬高并整体提亮。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE9_PASS` 到 `OMNI_COMPOSITE13_PASS` 分支先引入共享声明与
    `effects/color/bloom.glsl`，再引入本文件，每个程序在 `main()` 里调用对应的一个函数；输出 `compositeOutput5` 由主文件声明。
可复制示例：`void main(){ BloomCombine(); }`（要求调用方已提供 `texCoord`、`pixelSize`、`screenSize` 与泛光底层函数）。
设计原因与取舍：降采样与轴向模糊的底层 `BloomDownSample`、`AxialGaussianBlur`、`BloomBicubicBlurTexture` 在
    `effects/color/bloom.glsl`，本文件只做五级链的排布与写出，逐行照 `composite9.fsh` 到 `composite13.fsh`。
    各级把图排成一行、靠坐标偏移和边界判断落到对应级，这种排布是原程序为了省程序数量，照抄不改。
*/
#ifndef OMNI_POST_BLOOM_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_POST_BLOOM_INCLUDED // 置上标记，后续再次引用直接跳过。

// 泛光第一级：把一号画面降采样到半分辨率。
void BloomDownSampleScene(){
	vec2 sampleCoord = texCoord * 2.0; // 采样坐标放大两倍，对应半分辨率画面。
	vec2 border = pixelSize * 4.0 + 1.0; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) // 只在画面范围内采样。
		blur = BloomDownSample(colortex1, sampleCoord); // 从一号画面降采样。
	compositeOutput5 = vec4(blur, 0.0); // 写五号。
}

// 泛光第二级：从五号画面继续降采样。
void BloomDownSampleChain(){
	vec2 sampleCoord = texCoord * 2.0; // 采样坐标放大两倍。
	vec2 border = pixelSize * 2.0 + 0.5; // 允许超出的边界。
	vec3 blur = vec3(0.0); // 默认黑色。
	if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) // 只在画面范围内采样。
		blur = BloomDownSample(colortex5, sampleCoord); // 从五号画面降采样。
	compositeOutput5 = vec4(blur, 0.0); // 写五号。
}

// 泛光第三级：横向轴向高斯，链上各级排成一行。
void BloomBlurHorizontal(){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 borderWidth = pixelSize; // 边界用一像素宽。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 border = originSize + borderWidth; // 当前级的边界。
	vec2 axis = vec2(1.0, 0.0); // 横向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 coord = texCoord; // 在本级内推进的坐标。

	if (coord.x <= border.x && coord.y <= border.y){ // 第二级：直接抄。
		blur = CurveToLinear(textureLod(colortex5, clamp(coord, vec2(0.0), originSize), 0.0).rgb); // 读上一级结果。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 下一级宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第三级：横向模糊。
		blur = AxialGaussianBlur(colortex5, coord, vec2(2.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3); // 半径与步长来自泛光文件。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第四级。
		blur = AxialGaussianBlur(colortex5, coord, vec2(4.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD4, BLOOM_STEP_LOD4); // 更长的横向核。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第五级。
		blur = AxialGaussianBlur(colortex5, coord, vec2(8.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD5, BLOOM_STEP_LOD5); // 横向核继续变长。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第六级。
		blur = AxialGaussianBlur(colortex5, coord, vec2(16.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD6, BLOOM_STEP_LOD6); // 横向核继续变长。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第七级。
		blur = AxialGaussianBlur(colortex5, coord, vec2(32.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD7, BLOOM_STEP_LOD7); // 横向核继续变长。
	}
	coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
	originSize.x *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第八级。
		blur = AxialGaussianBlur(colortex5, coord, vec2(64.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD8, BLOOM_STEP_LOD8); // 最长的一级。
	}
	compositeOutput5 = vec4(LinearToCurve(blur), 0.0); // 写回五号。
}

// 泛光第四级：纵向轴向高斯，采样坐标回拧到各级自己的起点。
void BloomBlurVertical(){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	vec2 borderWidth = pixelSize; // 边界用一像素宽。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 border = originSize + borderWidth; // 当前级的边界。
	vec2 axis = vec2(0.0, 1.0); // 纵向模糊。
	vec3 blur = vec3(0.0); // 累积颜色。
	vec2 coord = texCoord; // 用于判断落在哪一级的坐标。
	float currInterval = 0.0; // 到下一级的间隔。
	float sampleOrigin = 0.0; // 当前级在图里的起始横坐标。

	if (coord.x <= border.x && coord.y <= border.y){ // 第二级：直接抄。
		blur = CurveToLinear(textureLod(colortex5, clamp(coord, vec2(0.0), originSize), 0.0).rgb); // 读上一级结果。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 当前级的宽度加间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标同步前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第三级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 2.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3); // 纵向核。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第四级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 4.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD4, BLOOM_STEP_LOD4); // 纵向核变长。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第五级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 8.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD5, BLOOM_STEP_LOD5); // 纵向核变长。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第六级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 16.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD6, BLOOM_STEP_LOD6); // 纵向核变长。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第七级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 32.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD7, BLOOM_STEP_LOD7); // 纵向核变长。
	}
	currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
	coord.x -= currInterval; // 移到下一级。
	sampleOrigin += currInterval; // 起始横坐标前移。
	originSize *= 0.5; // 宽度减半。
	border = originSize + borderWidth; // 更新边界。
	if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第八级。
		blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 64.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD8, BLOOM_STEP_LOD8); // 最长的一级。
	}
	compositeOutput5 = vec4(LinearToCurve(blur), 0.0); // 写回五号。
}

// 泛光第五级：把各级三次模糊后的结果按权重叠成一张光晕，雨里权重更高。
void BloomCombine(){
	vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
	const float intervalWidth = 3.0; // 级与级之间隔三像素。
	vec2 tCoord = texCoord * 2.0; // 采样坐标放大两倍。
	vec2 border = pixelSize * 8.0 + 1.0; // 允许超出的边界。

	float rainAlpha = 0.0; // 雨遮罩；主世界才有。
	#ifdef OMNI_OVERWORLD // 主世界从零号画面读雨量。
		rainAlpha = 1.0 - textureLod(colortex0, tCoord, 0.0).a; // 零号透明度越低说明雨越密。
		rainAlpha = saturate(rainAlpha * OMNI_RAIN_VISIBILITY); // 乘雨可见度选项。
	#endif

	vec2 coord = texCoord; // 当前级坐标。
	vec2 sampleOrigin = vec2(0.0); // 当前级在图里的起始横坐标。
	vec3 bloom = vec3(0.0); // 累积光晕。

	if (tCoord.x <= border.x && tCoord.y <= border.y){ // 只在画面范围内叠加。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.5, screenSize).rgb) * 1.0; // 第二级直接取。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.25 - sampleOrigin, screenSize).rgb) * mix(0.83333333, 1.0, rainAlpha); // 第三级，雨里权重更高。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.125 - sampleOrigin, screenSize).rgb) * mix(0.69444444, 1.0, rainAlpha); // 第四级。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.0625 - sampleOrigin, screenSize).rgb) * mix(0.57870370, 1.0, rainAlpha); // 第五级。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.03125 - sampleOrigin, screenSize).rgb) * mix(0.48225309, 1.0, rainAlpha); // 第六级。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.015625 - sampleOrigin, screenSize).rgb) * mix(0.40187757, 1.0, rainAlpha); // 第七级。

		sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
		originSize *= 0.5; // 宽度减半。
		bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.0078125 - sampleOrigin, screenSize).rgb) * mix(0.33489798, 1.0, rainAlpha); // 第八级。
	}

	bloom *= mix(0.2774, 1.2 / 7.0, rainAlpha); // 雨里整体提亮，原程序保留的常数。

	compositeOutput5 = vec4(LinearToCurve(bloom), 0.0); // 写回五号。
}
#endif // 文件守卫结束。
