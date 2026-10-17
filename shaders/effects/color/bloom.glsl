/*
泛光：把画面里亮过白色阈值的强光抽出来，逐级降采样再升采样成一张柔和光晕，最后与场景颜色合并。
来源：五个泛光程序段与各段的降采样、轴向高斯模糊、三次模糊照 iterationT `Lib/IndividualFounctions/Bloom.glsl` 一比一移植；
  合并泛光照 iterationT `Lib/Programs/Final.glsl` 的 `MergeBloom` 一比一移植。
调用位置：
  合成九号到十三号片元分别调用 `BloomDownSample`、`AxialGaussianBlur`、`BloomBicubicBlurTexture` 生成各级光晕；
  合成十四号片元调用 `MergeBloom`，把光晕按物体与雾的透明度混进场景颜色。
可复制示例：
  `vec3 glow = BloomDownSample(colortex1, texCoord * 2.0);`
  `vec3 blur = AxialGaussianBlur(colortex5, coord, vec2(2.0, 1.0), 0.0, originSize, vec2(1.0, 0.0), BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3);`
  `color = MergeBloom(color, 1.0 - data1.a);`
调用前提（iterationT 原样保留）：各级函数按加载器给的 `texCoord`、`pixelSize`、`screenSize` 工作；
  `MergeBloom` 还要用到 `colortex0` 的雨遮罩、`colortex3` 的体积雾透过率与雨、雾、天气等选项，
  这些选项由各自的归属效果文件定义，绘制主体负责按顺序引入。
设计原因与取舍：
  泛光不逐像素判断阈值，而是靠一条固定的降采样升采样链把亮部扩散开，链的半径与步长全是内部常数；
  光晕按物体透明度与雾的浓淡增强，让暴雨、水下和下界雾里的亮部更明显，这是原程序的表现手法。
*/
#ifndef OMNI_BLOOM_INCLUDED // 只引入一次，避免函数与内部常数重复定义。
#define OMNI_BLOOM_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"泛光","en_us":"Bloom"}}
// @option {"label": {"zh_cn": "泛光开关", "en_us": "Bloom"}, "description": {"zh_cn": "让亮部产生柔和光晕。", "en_us": "Adds a soft glow around bright areas."}}
#define OMNI_BLOOM
// @option {"label": {"zh_cn": "泛光强度", "en_us": "Bloom Amount"}, "slider": true, "description": {"zh_cn": "光晕混入场景的强度，越大越亮。", "en_us": "How strongly the glow is mixed into the scene."}}
#define OMNI_BLOOM_AMOUNT 0.13 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "下界末地泛光增强", "en_us": "Nether End Bloom Boost"}, "slider": true, "description": {"zh_cn": "下界与末地雾中的泛光额外增强量。", "en_us": "Extra bloom boost through Nether and End fog."}}
#define OMNI_NETHER_END_BLOOM_BOOST 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "体积雾散射泛光", "en_us": "Volumetric Fog Scattering Bloom"}, "description": {"zh_cn": "用体积雾的散射引导泛光，让光柱周围一起发亮。", "en_us": "Uses volumetric fog scattering to guide the glow around light shafts."}}
#define OMNI_VFOG_BLOOM
// 颜色曲线、亮度与共享数学，以及做深度换算的坐标函数都要先引入。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/coordinates.glsl"
// 合并泛光要读水雾密度 `OMNI_WATERFOG_DENSITY`（定义在 `effects/water/water.glsl`），这里引入它的归属文件。
#include "/effects/water/water.glsl"
// 合并泛光用失明与黑暗的调试开关 `OMNI_DISABLE_BLINDNESS_DARKNESS`，它的归属文件是颜色效果，这里引入才拿到定义。
#include "/effects/color/color.glsl"

// --- 内部常数：各级降采样与升采样的半径和步长 ---
// 半径是每一级高斯核的相对大小，步长是每一级沿轴取多少个样本；数值照 iterationT 原样，改动会直接改变光晕形状。
#define BLOOM_SIZE_LOD3 0.16 // 第三级核半径。
#define BLOOM_SIZE_LOD4 0.035 // 第四级核半径。
#define BLOOM_SIZE_LOD5 0.0085 // 第五级核半径。
#define BLOOM_SIZE_LOD6 0.002 // 第六级核半径。
#define BLOOM_SIZE_LOD7 0.0005 // 第七级核半径。
#define BLOOM_SIZE_LOD8 0.00015 // 第八级核半径。

#define BLOOM_STEP_LOD3 2.0 // 第三级轴向样本数。
#define BLOOM_STEP_LOD4 5.0 // 第四级轴向样本数。
#define BLOOM_STEP_LOD5 12.0 // 第五级轴向样本数。
#define BLOOM_STEP_LOD6 28.0 // 第六级轴向样本数。
#define BLOOM_STEP_LOD7 50.0 // 第七级轴向样本数。
#define BLOOM_STEP_LOD8 90.0 // 第八级轴向样本数。

// --- 降采样：在缩小的分辨率上做一次便宜的模糊，为后面的轴向模糊准备输入 ---
// 十三个样本按中心大、四角小的权重合并，权重和为四，输出前乘回四分之一保持亮度不变。
vec3 BloomDownSample(sampler2D texSampler, vec2 sampleCoord){
	vec3 blur = CurveToLinear(textureLod(texSampler, sampleCoord, 0.0).rgb) * 0.125; // 中心样本先计入，权重八分之一。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + vec2( pixelSize.x,  pixelSize.y), 0.0).rgb) * 0.5; // 四个斜对角样本权重更高。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + vec2( pixelSize.x, -pixelSize.y), 0.0).rgb) * 0.5; // 右上对角样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + vec2(-pixelSize.x,  pixelSize.y), 0.0).rgb) * 0.5; // 左上对角样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + vec2(-pixelSize.x, -pixelSize.y), 0.0).rgb) * 0.5; // 左下对角样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2( pixelSize.x,  0.0), 0.0).rgb) * 0.25; // 水平方向两像素外的样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2( 0.0,  pixelSize.y), 0.0).rgb) * 0.25; // 竖直方向两像素外的样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2(-pixelSize.x,  0.0), 0.0).rgb) * 0.25; // 水平反向两像素外的样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2( 0.0, -pixelSize.y), 0.0).rgb) * 0.25; // 竖直反向两像素外的样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2( pixelSize.x,  pixelSize.y), 0.0).rgb) * 0.125; // 远处对角样本权重更低。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2( pixelSize.x, -pixelSize.y), 0.0).rgb) * 0.125; // 远处对角样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2(-pixelSize.x,  pixelSize.y), 0.0).rgb) * 0.125; // 远处对角样本。
	blur += CurveToLinear(textureLod(texSampler, sampleCoord + 2.0 * vec2(-pixelSize.x, -pixelSize.y), 0.0).rgb) * 0.125; // 远处对角样本。
	return LinearToCurve(blur * 0.25); // 权重和为四，乘四分之一后亮度不变。
}

// --- 轴向高斯模糊：沿一个方向做长条高斯，横竖各来一次就得到二维模糊 ---
// `coordScale` 把当前级的坐标还原到该级的分辨率；`sampleOrigin` 是该级在合图里的左下角；`sampleSize` 是该级大小；
// `axis` 是模糊方向；`alpha` 控制核的宽度；`steps` 是每侧样本数。
// 为什么沿轴而不是整块：横竖两次一维高斯等价于一次二维高斯，样本数从平方降到线性，性能好得多。
vec3 AxialGaussianBlur(sampler2D texSampler, vec2 coord, vec2 coordScale, float sampleOrigin, vec2 sampleSize, vec2 axis, const float alpha, const float steps){
	vec3 blur = vec3(0.0); // 累积的模糊颜色。
	float weights = 0.0; // 累积的权重。
	for (float i = -steps; i <= steps; i++){ // 从负步长到正步长对称取样。
		float sampleWeight = exp2(-i * i * alpha * 5.77); // 高斯权重，离中心越远权重越小。
		vec2 sampleCoord = coord + axis / coordScale * pixelSize * i * 2.0; // 当前方向的取样坐标。
		vec2 tCoord = sampleCoord; // 记下原始坐标，用来判断有没有被夹到边界外。
		sampleCoord = clamp(sampleCoord, vec2(sampleOrigin, 0.0), vec2(sampleOrigin + sampleSize.x, sampleSize.y)); // 夹在当前级的范围内。
		sampleWeight *= float(tCoord == sampleCoord) + 1e-20; // 被夹过的样本权重归零，边界外不参与模糊。
		sampleCoord *= coordScale; // 还原成读取该级所用的坐标。
		blur += CurveToLinear(textureLod(texSampler, sampleCoord, 0.0).rgb) * sampleWeight; // 累加这一样本。
		weights += sampleWeight; // 累加权重。
	}
	return blur / weights; // 按权重归一化，样本少时亮度也不会变。
}

// --- 三次模糊：在升采样合并时把一张小图放大成平滑的大图 ---
// 与共享数学里的同名函数不同，这里接收纹理尺寸参数并读取调用方指定的画面，按合同留在本文件。
vec4 BloomBicubicBlurTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	vec2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
	coord = coord * texSize - 0.5; // 换成以像素中心为原点的坐标。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个三次样条权重。
	vec4 w1; // 两个方向的后两个三次样条权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 左右两对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= texPixelSize.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(texSampler, c.yw, 0.0), textureLod(texSampler, c.xw, 0.0), m.x),
			   mix(textureLod(texSampler, c.yz, 0.0), textureLod(texSampler, c.xz, 0.0), m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊。
}

// --- 合并泛光：把光晕按物体与雾的透明度混进场景颜色 ---
// `bloomGuide` 是引导强度，通常取一号画面的透明度，用来判断该处亮部有多亮。
// 为什么要看雾和雨：雾和雨会把光晕拉长变浓，原程序据此增强泛光，让天气与水下更有氛围。
vec3 MergeBloom(vec3 color, float bloomGuide){
#ifdef OMNI_OVERWORLD // 主世界才有雨遮罩。
	float rainAlpha = 1.0 - texelFetch(colortex0, texelCoord, 0).a; // 零号画面透明度越低说明雨越密。
	rainAlpha *= OMNI_RAIN_VISIBILITY; // 乘雨可见度选项。
#endif
#ifdef OMNI_NETHER // 下界从打包的七号画面里拿线性深度。
	float linearDepth = LinearDepth_From_ScreenDepth(Unpack2x16(texelFetch(colortex7, texelCoord, 0).a).x); // 拆出并换算深度。
	#ifndef DISTANT_HORIZONS // 没有远景模组时限制在远裁剪面内。
		linearDepth = min(linearDepth, far); // 夹到远裁剪面。
	#endif
#else // 主世界与末地直接用近景深度。
	float depth = texelFetch(depthtex0, texelCoord, 0).x; // 读当前像素深度。
	float linearDepth = LinearDepth_From_ScreenDepth(depth); // 换成米制距离。
	#ifdef DISTANT_HORIZONS // 有远景模组时远景像素改用远景深度。
		if (depth == 1.0) linearDepth = LinearDepth_From_ScreenDepth_DH(texelFetch(dhDepthTex0, texelCoord, 0).x); // 远景深度换到同一尺度。
	#endif
#endif
	vec3 bloom = CurveToLinear(textureLod(colortex5, texCoord * 0.5, 0.0).rgb); // 读入降采样链合成的光晕。
	float bloomAmount = OMNI_BLOOM_AMOUNT; // 从强度选项起步。
#ifdef OMNI_END // 末地整体增强光晕。
	bloomAmount *= 0.5 * OMNI_NETHER_END_BLOOM_BOOST + 1.0; // 按增强选项放大。
#endif
#ifdef OMNI_NETHER // 下界按群系和雾浓淡调整。
	float biomeOffset =	 BiomeNetherWastesSmooth * 1.0; // 荒地群系系数。
	biomeOffset +=		 BiomeCrimsonForestSmooth * 0.75; // 绯红森林群系系数。
	biomeOffset +=		 BiomeWarpedForestSmooth * 0.25; // 诡异森林群系系数。
	biomeOffset +=		 BiomeBasaltDeltasSmooth * 0.5; // 玄武岩三角洲群系系数。
	biomeOffset = biomeOffset * OMNI_NETHER_END_BLOOM_BOOST + 1.0; // 乘增强选项。
	float fogDensity = 0.008 * biomeOffset * OMNI_NETHER_END_BLOOM_BOOST * OMNI_NETHERFOG_DENSITY; // 雾越浓光晕越强。
	if (isEyeInWater > 1) fogDensity = 0.7; // 在岩浆或细雪里雾最浓。
	float visibility = 1.0 / exp2(linearDepth * fogDensity); // 距离越远可见度越低。
	float fogFactor = 1.1 - visibility; // 把可见度翻成雾的占比。
	fogFactor *= bloomGuide; // 只在亮的地方随雾增强。
	bloomAmount = max(bloomAmount * biomeOffset, min(fogFactor, 0.92)); // 取两者较大值，并留一点上限。
#else // 主世界与末地按水和雨的雾调整。
	float fogDensity = float(isEyeInWater > 1) * 0.7; // 岩浆或细雪里雾浓。
	#ifdef OMNI_UNDERWATER_FOG // 开水下雾时水里也加光晕。
		fogDensity = float(isEyeInWater == 1) * 0.07 * OMNI_WATERFOG_DENSITY; // 水下雾的浓度由选项控制。
	#endif
	float visibility = 1.0 / exp2(linearDepth * fogDensity); // 距离越远可见度越低。
	float fogFactor = 1.1 - visibility; // 把可见度翻成雾的占比。
	fogFactor *= bloomGuide; // 只在亮的地方随雾增强。
	bloomAmount = max(bloomAmount, fogFactor); // 取两者较大值。
#endif
#ifdef OMNI_OVERWORLD // 主世界还要看下雨和体积雾。
	#ifndef OMNI_INDOOR_FOG // 室外按天空光给雨的泛光。
		float rainBloomAmount = wetness * (0.2 * eyeBrightnessSmoothCurved + 0.15); // 湿润度与天空光共同决定。
	#else // 室内按固定值。
		float rainBloomAmount = wetness * 0.35; // 室内雨的泛光。
	#endif
	rainBloomAmount = saturate(rainBloomAmount + rainAlpha * 0.2); // 叠加雨遮罩。
	bloomAmount = max(bloomAmount, rainBloomAmount); // 取两者较大值。
	#if defined OMNI_VFOG && !defined OMNI_DOF // 开体积雾且没开景深时，用雾的透过率引导。
		#ifdef OMNI_VFOG_BLOOM // 只有开启体积雾散射泛光才处理。
			float fogTransmittance = textureLod(colortex3, texCoord + taaJitter * 0.5, 0.0).a * bloomGuide; // 读体积雾透过率。
			float fogBloomAmount = fsqrt(fogTransmittance); // 用近似平方根做一次曲线调整。
			bloomAmount = max(bloomAmount, fogTransmittance); // 取两者较大值。
		#endif
	#endif
#endif
	#ifndef OMNI_DISABLE_BLINDNESS_DARKNESS // 失明或黑暗效果时不加光晕。
		bloomAmount *= 1.0 - blindness - darknessFactor; // 按遮挡强度压低。
	#endif
	return mix(color, bloom, saturate(bloomAmount)); // 按占比把光晕混进场景。
}
#endif // 文件守卫结束。
