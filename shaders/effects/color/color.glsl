/*
调色与曝光：把线性场景颜色映射成屏幕颜色，并算出自动曝光值；同时给出强光压缩、高级调色与浦肯野效应。
来源：三条强光压缩曲线与曝光值、黑边照 iterationT `Lib/Programs/Final.glsl` 一比一移植；
  自动曝光统计照 iterationT `Lib/IndividualFounctions/MotionBlur.glsl` 的 `GetExposureTiles` 一比一移植；
  可配置的宽色域压缩照 iterationT `Lib/IndividualFounctions/AgX.glsl` 一比一移植；
  浦肯野效应照 iterationT `composite5.fsh` 的 `PurkinjeEffect` 一比一移植；
  白平衡色温照 Eclipse `lib/settings.glsl:748` 的 `WHITE_BALANCE` 与 `composite11.fsh:318-320` 的乘法移植（默认中性）。
调用位置：
  合成八号片元在顶行统计像素处调用 `GetExposureTiles` 并把结果写进二号画面，供后续帧与最终阶段读取；
  合成十四号片元调用 `GetExposureValue` 取曝光、`WhiteBalance` 做白平衡，再按 `TONEMAP_OPERATOR` 做色调映射与高级调色；
  final 片元调用 `BlackBar` 画黑边；合成五号片元调用 `PurkinjeEffect` 做暗处色偏。
可复制示例：
  `float exposure = GetExposureValue();`
  `color = OMNI_TONEMAP_OPERATOR(color);`
  `color *= BlackBar(OMNI_SCREEN_RATIO);`
调用前提（iterationT 原样保留）：
  `GetExposureTiles` 依赖 `colortex1` 与 `screenSize`、`pixelSize`，并读取 `OMNI_CAVE_MODE`；
  `BlackBar` 依赖调用方先声明 `texCoord`；`GetExposureValue` 读取二号画面顶行的自动曝光统计像素。
  强光压缩的选择项在项目里用序号表示：调用方按 `#if OMNI_TONEMAP_OPERATOR == 1` 取 `ACES`、
  `== 2` 取 `None`、其余取 `AgX`，选项扫描器只接受数字取值，所以不能直接把函数名当选项值。
设计原因与取舍：
  曝光分两级：八号片元按分块平均亮度算出目标曝光并写进顶行像素，最终阶段再把它换算成实际乘数；
  强光压缩先转宽色域再压，暗部和亮部都保留色彩；简单曲线把所有亮部压向纯白，代价是丢掉高光颜色。
  自动曝光的目标是画面中间灰，适应速度按帧时间计算，帧率高低走同一条曲线，避免亮暗突变时跳动。
*/
#ifndef OMNI_COLOR_INCLUDED // 只引入一次，避免选项、内部常数与函数重复定义。
#define OMNI_COLOR_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"颜色与曝光","en_us":"Color & exposure"}}
// @option {"label": {"zh_cn": "强光压缩方式", "en_us": "Tonemap"}, "description": {"zh_cn": "把高动态范围压到屏幕范围所用的曲线。这一项在项目里用序号表示，零为 AgX，一为 ACES，二为无压缩。", "en_us": "Curve that maps high dynamic range into display range. Stored as an index: zero AgX, one ACES, two none."}, "values": {"0": {"zh_cn": "AgX", "en_us": "AgX"}, "1": {"zh_cn": "ACES", "en_us": "ACES"}, "2": {"zh_cn": "无", "en_us": "None"}}}
#define OMNI_TONEMAP_OPERATOR 0 // [0 1 2]
// @option {"label": {"zh_cn": "AgX 动态范围", "en_us": "AgX Dynamic Range"}, "slider": true, "description": {"zh_cn": "AgX 曲线承认的曝光范围，越大高光与暗部保留越多。", "en_us": "Exposure range the AgX curve accepts; larger keeps more highlight and shadow."}}
#define OMNI_AGX_EV 13.0 // [8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 24.0 32.0]
// @option {"label": {"zh_cn": "阿布尼效应校正", "en_us": "Abney Effect Correction"}, "description": {"zh_cn": "抵消加亮时色相偏移，亮部颜色更接近真实。", "en_us": "Counteracts the hue shift when lightening, keeping highlights more natural."}}
#define OMNI_ABNEY_EFFECT_CORRECTION
// @option {"label": {"zh_cn": "高级调色", "en_us": "Advanced Color Adjustment"}, "description": {"zh_cn": "启用白光裁剪、亮度伽马与饱和度这组更细致的调整。", "en_us": "Enables the finer white-clip, luminance-gamma and saturation adjustments."}}
//#define OMNI_ADVANCED_COLOR
// @option {"label": {"zh_cn": "伽马", "en_us": "Gamma"}, "slider": true, "description": {"zh_cn": "高级调色里的显示伽马，越大越暗。", "en_us": "Display gamma inside advanced color; higher is darker."}}
#define OMNI_GAMMA 1.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5]
// @option {"label": {"zh_cn": "亮度伽马", "en_us": "Luminance Gamma"}, "slider": true, "description": {"zh_cn": "只作用在亮度上的伽马，调整明暗对比而不改色相。", "en_us": "Gamma applied to luminance only, changing contrast without hue."}}
#define OMNI_LUMA_GAMMA 1.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5]
// @option {"label": {"zh_cn": "饱和度", "en_us": "Saturation"}, "slider": true, "description": {"zh_cn": "高级调色里的颜色鲜艳程度。", "en_us": "Colour vividness inside advanced color."}}
#define OMNI_SATURATION 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label": {"zh_cn": "白光裁剪", "en_us": "White Clip"}, "slider": true, "description": {"zh_cn": "高级调色里多大的亮度算纯白，越大越容易保留高光细节。", "en_us": "Brightness treated as pure white in advanced color; higher keeps more highlight detail."}}
#define OMNI_WHITE_CLIP 0.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]
// @option {"label": {"zh_cn": "白平衡", "en_us": "White Balance"}, "slider": true, "description": {"zh_cn": "按色温给画面染色，值低偏暖、值高偏冷；默认六千五百为中性，完全不改画面。来源 Eclipse `lib/settings.glsl:748` 的 `WHITE_BALANCE`。", "en_us": "Tints the image by colour temperature; lower leans warm, higher leans cool. The default 6500 is neutral and changes nothing. From Eclipse `lib/settings.glsl:748` `WHITE_BALANCE`."}}
#define OMNI_WHITE_BALANCE 6500 // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000 15000 20000 25000 50000]
// @option {"label": {"zh_cn": "手动曝光", "en_us": "Manual Exposure"}, "description": {"zh_cn": "关掉自动曝光，改用下面的固定曝光值。", "en_us": "Turns off auto exposure and uses the fixed EV value below."}}
//#define OMNI_MANUAL_EXPOSURE
// @option {"label": {"zh_cn": "固定曝光值", "en_us": "Exact EV value"}, "slider": true, "description": {"zh_cn": "手动曝光所用的曝光值。", "en_us": "Exposure value used by manual exposure."}}
#define OMNI_EV_VALUE 14.0 // [0.0 0.33 0.67 1.0 1.33 1.67 2.0 2.33 2.67 3.0 3.33 3.67 4.0 4.33 4.67 5.0 5.33 5.67 6.0 6.33 6.67 7.0 7.33 7.67 8.0 8.33 8.67 9.0 9.33 9.67 10.0 10.33 10.67 11.0 11.33 11.67 12.0 12.33 12.67 13.0 13.33 13.67 14.0 14.33 14.67 15.0 15.33 15.67 16.0 16.33 16.67 17.0 17.33 17.67 18.0 18.33 18.67 19.0 19.33 19.67 20.0]
// @option {"label": {"zh_cn": "曝光偏移", "en_us": "AE Offset"}, "slider": true, "description": {"zh_cn": "在自动曝光结果上整体加减的曝光，负值更暗。", "en_us": "Exposure added on top of the auto result; negative is darker."}}
#define OMNI_AE_OFFSET 0.0 // [-5.0 -4.67 -4.33 -4.0 -3.67 -3.33 -3.0 -2.67 -2.33 -2.0 -1.67 -1.33 -1.0 -0.67 -0.33 0.0 0.33 0.67 1.0 1.33 1.67 2.0 2.33 2.67 3.0 3.33 3.67 4.0 4.33 4.67 5.0]
// @option {"label": {"zh_cn": "测光方式", "en_us": "AE Mode"}, "description": {"zh_cn": "自动曝光如何给画面的不同位置计权。", "en_us": "How auto exposure weights different screen areas."}, "values": {"0": {"zh_cn": "默认", "en_us": "Default"}, "1": {"zh_cn": "中心权重", "en_us": "Center Weighted"}, "2": {"zh_cn": "只看中心", "en_us": "Center Only"}, "3": {"zh_cn": "全屏平均", "en_us": "Screen Average"}}}
#define OMNI_AE_MODE 0 // [0 1 2 3]
// @option {"label": {"zh_cn": "曝光曲线", "en_us": "AE Curve"}, "slider": true, "description": {"zh_cn": "平均亮度到曝光的曲线指数，越大越克制。", "en_us": "Exponent mapping average luminance to exposure."}}
#define OMNI_AE_CURVE 0.7 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.85 0.9 0.95 1.0]
// @option {"label": {"zh_cn": "亮度计权方式", "en_us": "Luminance Weighted Mode"}, "description": {"zh_cn": "按分块亮度给曝光统计计权，让暗部或亮部更有话语权。", "en_us": "Weights the exposure statistic by tile luminance."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "预设一", "en_us": "Preset 1"}, "2": {"zh_cn": "预设二", "en_us": "Preset 2"}, "3": {"zh_cn": "偏向暗部", "en_us": "Shadow Priority"}, "4": {"zh_cn": "偏向高光", "en_us": "Highlight Priority"}}}
#define OMNI_LUMINANCE_WEIGHT_MODE 1 // [0 1 2 3 4]
// @option {"label": {"zh_cn": "计权强度", "en_us": "Weighted Strength"}, "slider": true, "description": {"zh_cn": "亮度计权的强度，越大越偏向所选的暗部或高光。", "en_us": "Strength of luminance weighting."}}
#define OMNI_LUMINANCE_WEIGHT_STRENGTH 0.7 // [0.5 0.7 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "平滑曝光", "en_us": "Smooth AE"}, "description": {"zh_cn": "让自动曝光随时间缓慢变化，减少亮暗突变时的跳动。", "en_us": "Makes auto exposure change gradually over time."}}
#define OMNI_SMOOTH_EXPOSURE
// @option {"label": {"zh_cn": "曝光过渡时间", "en_us": "AE Transition Time"}, "slider": true, "description": {"zh_cn": "自动曝光适应亮度变化所需的秒数。", "en_us": "Seconds auto exposure takes to adapt to a brightness change."}}
#define OMNI_EXPOSURE_TIME 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label": {"zh_cn": "黑边比例", "en_us": "AspectRatio"}, "description": {"zh_cn": "按电影比例在画面上下加黑边；零为不加。", "en_us": "Adds cinematic black bars; zero means none."}, "values": {"0.0": {"zh_cn": "不加", "en_us": "None"}, "1.333333": {"zh_cn": "四比三", "en_us": "4:3"}, "1.777778": {"zh_cn": "十六比九", "en_us": "16:9"}, "2.0": {"zh_cn": "二比一", "en_us": "2:1"}, "2.39": {"zh_cn": "宽银幕", "en_us": "2.39:1"}}}
#define OMNI_SCREEN_RATIO 0.0 // [0.0 1.333333 1.435052 1.5 1.6 1.777778 2.0 2.333333 2.39]
// @option {"label": {"zh_cn": "浦肯野效应", "en_us": "Purkinje Effect"}, "description": {"zh_cn": "暗处颜色向偏蓝的暗视觉偏移，模拟人眼在黑暗中偏色。", "en_us": "Shifts dark colours toward scotopic blue, mimicking human night vision."}}
//#define OMNI_PURKINJE_EFFECT
// @option {"label": {"zh_cn": "浦肯野阈值", "en_us": "Threshold"}, "slider": true, "description": {"zh_cn": "低于此亮度才发生色偏。", "en_us": "Luminance below which the shift happens."}}
#define OMNI_PURKINJE_EFFECT_THRESHOLD 0.00003 // [0.00001 0.000015 0.00002 0.00003 0.00005 0.00007 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001]
// @option {"label": {"zh_cn": "浦肯野强度", "en_us": "Strength"}, "slider": true, "description": {"zh_cn": "色偏的强度。", "en_us": "Strength of the colour shift."}}
#define OMNI_PURKINJE_EFFECT_STRENGTH 0.7 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "关闭夜视校正", "en_us": "Disable Night Vision"}, "page": "dev", "description": {"zh_cn": "调试开关：忽略夜视对曝光曲线的抬升，用来比较真实亮度。","en_us": "Debug switch: ignores the night-vision lift of the exposure curve to compare real brightness."}}
//#define OMNI_DISABLE_NIGHTVISION
// @option {"label": {"zh_cn": "关闭失明与黑暗校正", "en_us": "Disable Blindness & Darkness"}, "page": "dev", "description": {"zh_cn": "调试开关：忽略失明与黑暗对曝光、泛光和原版雾的影响。","en_us": "Debug switch: ignores blindness and darkness on exposure, bloom and vanilla fog."}}
//#define OMNI_DISABLE_BLINDNESS_DARKNESS

// --- 内部常数：原 `Settings.glsl` 里不进菜单的曝光常数 ---
#define AE_CLAMP // 给分块亮度设一个极小下限，避免全黑画面把曝光推到无穷。

// 颜色曲线与亮度来自共用数学；曝光统计还要读一号与二号画面。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// --- 三条强光压缩曲线 ---
// 改编型的伦勃朗曲线的一部分，把中间亮度拉直、两端压缩。
vec3 RRTAndODTFit(vec3 v){
	vec3 a = v * (v + 0.0245786) - 0.000090537; // 分子多项式。
	vec3 b = v * (v + 0.4329510) + 0.238081; // 分母多项式。
	return a / b; // 有理式压缩。
}

// 影院标准的 ACES 近似：先转色域，再压缩，最后转回显示原色。
vec3 ACES(vec3 color){
	color *= 1.4; // 整体提亮一点，贴近影院观感。
	#ifdef OMNI_ABNEY_EFFECT_CORRECTION // 可选地抵消阿布尼效应。
		color *= mat3(0.99999976, -1.26657e-7, -1.29064e-9, 1.67316e-8, 0.99999976, -5.32026e-9, -0.00725587, 6.47740e-9, 1.00725580); // 一次微小色域修正。
	#endif
	color *= mat3(0.59719, 0.35458, 0.04823, 0.07600, 0.90834, 0.01566, 0.02840, 0.13383, 0.83777); // 转 AP1 工作色域。
	color = RRTAndODTFit(color); // 压缩动态范围。
	color *= mat3(1.60475, -0.53108, -0.07367, -0.10208, 1.10813, -0.00605, -0.00327, -0.07276, 1.07602); // 转回显示色域。
	return LinearToGamma(color); // 转伽马空间。
}

// AgX 对比度的多项式近似，按归一化曝光给出 S 曲线。
vec3 AgxDefaultContrastApprox(vec3 x){
	return (((((15.5 * x - 40.14) * x + 31.96) * x - 6.868) * x + 0.4298) * x + 0.1191) * x - 0.00232; // 六次多项式。
}

// AgX 强光压缩：先转宽色域工作空间，把曝光压到承认范围，再用 S 曲线成形，保住色相。
vec3 AgX(vec3 color) {
	color *= 2.3; // 整体提亮一点。
	#ifdef OMNI_ABNEY_EFFECT_CORRECTION // 可选地抵消阿布尼效应。
		color *= mat3(0.99999976, -1.26657e-7, -1.29064e-9, 1.67316e-8, 0.99999976, -5.32026e-9, -0.00725587, 6.47740e-9, 1.00725580); // 一次微小色域修正。
	#endif
	color *= mat3(0.842479062253094, 0.0784335999999992, 0.0792237451477643, 0.0423282422610123, 0.878468636469772, 0.0791661274605434, 0.0423756549057051, 0.0784336, 0.879142973793104); // 转宽色域工作空间。
	const float hev = OMNI_AGX_EV * 0.5; // 承认范围的一半。
	const float middle_grey = 0.18; // 中间灰。
	color = clamp(log2(color / middle_grey), -hev, hev); // 以中间灰为基准取对数并夹在范围内。
	color = (color + hev) / OMNI_AGX_EV; // 归一到零到一。
	color = AgxDefaultContrastApprox(color); // S 曲线成形。
	color *= mat3(1.19687900512017, -0.0980208811401368, -0.0990297440797205, -0.0528968517574562, 1.15190312990417, -0.0989611768448433, -0.0529716355144438, -0.0980434501171241, 1.15107367264116); // 转回显示原色。
	return color; // 返回线性显示颜色。
}

// 无压缩：只做伽马编码，保留所有高光但容易硬剪切。
vec3 None(vec3 color){
	return pow(color, vec3(1.0 / 2.2)); // 二点二伽马。
}

// --- 曝光统计：按分块对一号画面求平均亮度，得到目标曝光 ---
// 把画面切成固定大小的小块，每个块只读一个亮度，按到中心的距离和亮度给块计权，再加权平均。
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
// 为什么用对数平均：亮度跨度很大，直接平均会被几个高光块带偏。
float GetExposureTiles(){
	float avg = Luminance(CurveToLinear(textureLod(colortex1, vec2(0.65, 0.65), floor(log2(min(viewWidth, viewHeight)))).rgb)) * (MAIN_OUTPUT_FACTOR / 128.0); // 用一个粗糙降采样估计整体亮度，供计权用。
	int lod = 6; // 用第六级多级纹理做分块采样。
	float tileScale = exp2(float(lod)); // 一个块覆盖多少像素。
	vec2 tileCount = floor(screenSize / tileScale); // 每行每列有多少块。
	vec2 tileCenter = tileCount * 0.5; // 块网格的中心。
	float exposure = 0.0; // 加权亮度累加。
	float weights = 0.0; // 权重累加。
	for (int x = 0; x < tileCount.x; x++){ // 逐列遍历块。
	for (int y = 0; y < tileCount.y; y++){ // 逐行遍历块。
		float tileExposure = Luminance(CurveToLinear(texelFetch(colortex1, ivec2(x, y), lod).rgb)) * (MAIN_OUTPUT_FACTOR / 128.0); // 这个块的亮度。
		vec2 tileDistance = (tileCenter - vec2(x, y) + 0.5) * pixelSize * tileScale * 2.0; // 块中心到画面中心的屏幕距离。
		float centerDistance = length(tileDistance); // 到画面中心的距离。
		#if OMNI_AE_MODE == 0 // 默认：中心权重。
			#ifdef OMNI_END // 末地不看中心，全部等权。
				float tileWeight = 1.0; // 末地每块权重相同。
			#else // 其他维度按到中心的距离衰减。
				float tileWeight = remapSaturate(centerDistance, 0.6, 0.4); // 越靠中心权重越高。
			#endif
		#elif OMNI_AE_MODE == 1 // 中心权重较强。
			float tileWeight = remapSaturate(centerDistance, 0.7, 0.0); // 中心权重曲线。
			tileWeight *= tileWeight; // 再平方，中心更突出。
		#elif OMNI_AE_MODE == 2 // 只看中心。
			float tileWeight = remapSaturate(centerDistance, 0.6, 0.4); // 与默认相同的曲线。
		#elif OMNI_AE_MODE == 3 // 全屏平均。
			float tileWeight = 1.0; // 每块等权。
		#endif
		#ifdef AE_CLAMP // 给块亮度设极小下限。
			tileExposure = max(6.4e-9, tileExposure); // 避免全黑块把权重推到无穷。
		#endif
		#if defined OMNI_CAVE_MODE && defined OMNI_OVERWORLD // 洞穴模式且在主世界时按偏离程度计权。
			float lumaWeight = avg / tileExposure; // 相对整体亮度的比例。
			tileWeight *= pow(lumaWeight, 0.7); // 越偏离整体亮度权重越大，适应洞穴。
		#else // 其他情况按亮度计权方式。
			#if OMNI_LUMINANCE_WEIGHT_MODE > 0 // 关闭计权时不动权重。
				#if OMNI_LUMINANCE_WEIGHT_MODE == 1 // 预设一。
					#ifdef OMNI_NETHER // 下界用固定指数。
						float lumaWeight = avg / tileExposure; // 相对亮度。
						lumaWeight = pow(lumaWeight, 0.7); // 固定指数。
					#else // 主世界与末地按整体亮度改变指数。
						float lumaWeight = avg / tileExposure; // 相对亮度。
						#ifdef OMNI_OVERWORLD // 主世界按整体亮度调指数。
							lumaWeight = pow(lumaWeight, remapSaturate(avg, 1.55e-6, 6.25e-8) * 0.7); // 暗环境更偏向亮块。
						#else // 末地指数范围不同。
							lumaWeight = pow(lumaWeight, remapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地曲线。
						#endif
					#endif
				#elif OMNI_LUMINANCE_WEIGHT_MODE == 2 // 预设二。
					#ifdef OMNI_NETHER // 下界用固定指数。
						float lumaWeight = avg / tileExposure; // 相对亮度。
						lumaWeight = pow(lumaWeight, 0.7); // 固定指数。
					#else // 其他维度用较平的曲线。
						float lumaWeight = avg / tileExposure; // 相对亮度。
						lumaWeight = pow(lumaWeight, remapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 曲线指数。
					#endif
				#elif OMNI_LUMINANCE_WEIGHT_MODE == 3 // 偏向暗部。
					float lumaWeight = avg / tileExposure; // 相对亮度。
					lumaWeight = pow(lumaWeight, OMNI_LUMINANCE_WEIGHT_STRENGTH); // 用选项给的强度。
				#elif OMNI_LUMINANCE_WEIGHT_MODE == 4 // 偏向高光。
					float lumaWeight = tileExposure / avg; // 比例取反。
					lumaWeight = pow(lumaWeight, OMNI_LUMINANCE_WEIGHT_STRENGTH); // 用选项给的强度。
				#endif
				tileWeight *= lumaWeight; // 把亮度权重乘进块权重。
			#endif
		#endif
		exposure += tileExposure * tileWeight; // 累加加权亮度。
		weights += tileWeight; // 累加权重。
	}
	}
	exposure /= weights; // 加权平均。
	exposure *= EXPOSURE_OUTPUT_FACTOR; // 换到曝光单位。
	return LinearToCurve(exposure); // 按管线编码后写进顶行像素。
}

// --- 曝光值：把顶行像素里的统计换算成这一帧要乘的曝光 ---
// 手动模式直接由曝光值换算；自动模式再按曲线和偏移调整，并乘回管线单位。
float GetExposureValue(){
	#ifdef OMNI_MANUAL_EXPOSURE // 手动曝光。
		return 1.5e5 * MAIN_OUTPUT_FACTOR * exp2(-OMNI_EV_VALUE); // 由曝光值直接换算。
	#else // 自动曝光。
		float ae = CurveToLinear(texelFetch(colortex2, ivec2(0, screenSize.y - 1.0), 0).a) * (5120.0 / EXPOSURE_OUTPUT_FACTOR); // 读顶行自动曝光统计。
		float aeCurve = OMNI_AE_CURVE; // 曲线指数初值。
		#ifndef OMNI_DISABLE_NIGHTVISION // 夜视时把曲线指数抬到接近一。
			aeCurve = mix(aeCurve, 0.95, nightVision); // 按夜视强度混合。
		#endif
		#ifdef AE_CLAMP // 开启曝光钳位时按亮度压曲线。
			aeCurve *= remapSaturate(ae, 2.0, 1.0) * 0.6 + 0.4; // 越暗越接近固定值，避免过曝。
		#endif
		#ifdef OMNI_NETHER // 下界整体压一点曲线。
			aeCurve *= 0.83; // 下界修正系数。
		#endif
		ae = pow(ae, -aeCurve); // 按曲线把亮度换成曝光。
		ae *= exp2(OMNI_AE_OFFSET); // 叠加曝光偏移。
		#ifndef OMNI_DISABLE_BLINDNESS_DARKNESS // 黑暗效果时压低曝光。
			ae *= 1.0 - min(darknessLightFactor * 2.0, 0.9); // 按黑暗脉动亮度压低。
		#endif
		return 8.5 * MAIN_OUTPUT_FACTOR * ae; // 乘回管线单位并给出最终曝光。
	#endif
}

// --- 黑边：按电影比例在画面上下画黑边 ---
// `newRatio` 是目标宽高比，零表示不加黑边。返回零或一表示该像素是否落在画面内。
float BlackBar(float newRatio){
	if (newRatio == 0.0) return 1.0; // 不加黑边时全部保留。
	vec2 aCoord = abs(texCoord - 0.5) * 2.0; // 到画面中心归一化后的偏移。
	float width = min(newRatio / aspectRatio, 1.0); // 目标比例下的宽度。
	float height = min(aspectRatio / newRatio, 1.0); // 目标比例下的高度。
	return step(aCoord.x, width) * step(aCoord.y, height); // 落在目标画面内为一，外面为零。
}

// --- 浦肯野效应：暗处向偏蓝的暗视觉偏移 ---
// 亮度低于阈值时，颜色向偏蓝的亮度混合，阈值和强度由选项控制。
void PurkinjeEffect(inout vec3 color){
	float luminance = Luminance(color); // 当前颜色亮度。
	color = mix(color, luminance * vec3(0.7777, 1.0004, 1.6190), saturate((OMNI_PURKINJE_EFFECT_THRESHOLD - luminance) * OMNI_PURKINJE_EFFECT_STRENGTH / OMNI_PURKINJE_EFFECT_THRESHOLD)); // 越暗混入越多。
}

// --- 白平衡：按色温给线性颜色染色 ---
// 来源 Eclipse `composite11.fsh:318-320`，那里在色调映射之前对线性颜色乘 `blackbody(WHITE_BALANCE)`。
// 为什么默认六千五百开尔文视为中性：日光下的白点约六千五百开尔文，此时判定为中性、不改动颜色，
//   与原程序的 `#if WHITE_BALANCE != 6500` 等价，保证默认画面不变。
// 为什么放在色调映射之前：白平衡是相机白点校正，要在曝光后的线性颜色上做；
//   压缩曲线之后再改会破坏已经压好的高光，也与真实相机的处理顺序不符。
vec3 WhiteBalance(vec3 color){
	if (OMNI_WHITE_BALANCE != 6500.0) color *= Blackbody(OMNI_WHITE_BALANCE); // 非中性时才按黑体色温染色，低值偏暖、高值偏冷。
	return color; // 返回染色后的线性颜色。
}

// --- 高级调色：白光裁剪、亮度伽马与饱和度，从十四号主体里单独拆出 ---
// 先回线性空间，再压白点、按亮度伽马调整明暗对比、按饱和度调整鲜艳度，最后回显示空间。
vec3 AdvancedColor(vec3 color){
	color = GammaToLinear(color); // 从伽马空间回到线性。
	color = pow(length(color), 1.0 / OMNI_LUMA_GAMMA) * normalize(color + 1e-20); // 只改颜色的长度，保色相。
	color = saturate(color * (1.0 + OMNI_WHITE_CLIP)); // 按白点裁剪并夹紧。
	color = mix(color, vec3(Luminance(color)), vec3(1.0 - OMNI_SATURATION)); // 朝灰阶混合以调整饱和度。
	color = saturate(pow(color, vec3(((1.0 / 2.2) / OMNI_GAMMA)))); // 按伽马回显示空间。
	return color; // 返回调好的颜色。
}

// --- 可配置的宽色域压缩：原程序一处独立的实验实现，本文件照原样保留 ---
// 下面这组函数与上面的 AgX 并列，是另一套可调压缩参数；原程序未接入渲染流程，按合同一并移植，名字保持原名。
const float min_ev = -6.0; // 承认的最暗曝光。
const float max_ev = 6.0; // 承认的最亮曝光。
const float slope = 2.3; // S 曲线中点斜率。
const float toe_power = 1.9; // 暗部弯曲指数。
const float shoulder_power = 2.5; // 亮部弯曲指数。
const vec3 compression = vec3(0.0, 0.0, 0.0); // 三个原色的压缩量。
const vec3 rotation = vec3(0.0, 0.0, -2.0); // 三个原色的旋转量。
const float saturation = 1.0; // 该实现的饱和度。

// 由色度坐标的横纵比还原向量的第三个分量，纵坐标为零时返回零。
vec3 unproject(vec2 xy){
	if(xy.y == 0.0) // 纵坐标为零无法还原。
		return vec3(0.0); // 返回零。
	float Y = 1.0; // 亮度分量固定为一。
	float X = xy.x / xy.y; // 横坐标比例。
	float Z = (1.0 - xy.x - xy.y) / xy.y; // 第三分量比例。
	return vec3(X, Y, Z); // 返回三刺激值。
}

// 由四个原色的色度坐标构造色域转换矩阵。
mat3 primaries_to_matrix(vec2 xy_red, vec2 xy_green, vec2 xy_blue, vec2 xy_white)
{
	vec3 XYZ_red = unproject(xy_red); // 红色原色。
	vec3 XYZ_green = unproject(xy_green); // 绿色原色。
	vec3 XYZ_blue = unproject(xy_blue); // 蓝色原色。
	vec3 XYZ_white = unproject(xy_white); // 白点。
	mat3 temp = mat3(
				XYZ_red.x,	XYZ_green.x,	XYZ_blue.x,
				1.0,        1.0,            1.0,
				XYZ_red.z,	XYZ_green.z,	XYZ_blue.z); // 三原色拼成的矩阵。
	mat3 inverse = inverse(temp); // 求逆。
	vec3 scale = XYZ_white * inverse; // 解出每个原色的缩放。
	return mat3(
		scale.x * XYZ_red.x, scale.y * XYZ_green.x,	scale.z * XYZ_blue.x,
		scale.x * XYZ_red.y, scale.y * XYZ_green.y,	scale.z * XYZ_blue.y,
		scale.x * XYZ_red.z, scale.y * XYZ_green.z,	scale.z * XYZ_blue.z); // 返回带缩放的矩阵。
}

// 把一个原色沿与邻居的距离按角度滑动，返回滑动比例，用来调整色域形状。
float RotationToSlide(vec2 primary, vec2 neighborA, vec2 neighborB, float angle){
	vec2 neighbor = mix(neighborB, neighborA, float(angle >= 0.0)); // 按角度符号挑邻居。
	float distance_to_neighbor = distance(primary, neighbor); // 到邻居的距离。
	float distance_to_center = length(primary); // 到原点的距离。
	float side = sin(angle / 180.0 * PI) * distance_to_center; // 侧向位移。
	return side / distance_to_neighbor; // 归一化的滑动量。
}

// 按滑动量在邻居之间插值，得到移动后的原色。
vec2 SlidePrimary(vec2 primary, vec2 neighborA, vec2 neighborB, float amount){
	return mix(primary, mix(neighborB, neighborA, float(amount >= 0.0)), saturate(abs(amount))); // 按滑动量的绝对值插值。
}

// 按给定的原色与白点算出压缩后的色域矩阵。
mat3 ComputeCompressionMatrix(vec2 xyR, vec2 xyG, vec2 xyB, vec2 xyW){
	vec2 offsetR = xyR - xyW; // 红原色相对白点。
	vec2 offsetG = xyG - xyW; // 绿原色相对白点。
	vec2 offsetB = xyB - xyW; // 蓝原色相对白点。
	vec3 slide = vec3(0.0); // 三个原色的滑动量。
	slide.r = RotationToSlide(offsetR, offsetB, offsetG, rotation.r); // 红原色的滑动量。
	slide.g = RotationToSlide(offsetG, offsetR, offsetB, rotation.g); // 绿原色的滑动量。
	slide.b = RotationToSlide(offsetB, offsetG, offsetR, rotation.b); // 蓝原色的滑动量。
	vec3 scale_factor = 1.0 / (1.0 - compression); // 按压缩量算出缩放。
	vec2 R = (SlidePrimary(offsetR, offsetB, offsetG, slide.r) * scale_factor.r) + xyW; // 移动后的红原色。
	vec2 G = (SlidePrimary(offsetG, offsetR, offsetB, slide.g) * scale_factor.g) + xyW; // 移动后的绿原色。
	vec2 B = (SlidePrimary(offsetB, offsetG, offsetR, slide.b) * scale_factor.b) + xyW; // 移动后的蓝原色。
	vec2 W = xyW; // 白点不变。
	return primaries_to_matrix(R, G, B, W); // 返回新色域矩阵。
}

// 把线性颜色按承认的曝光范围归一到零到一，供后面的曲线使用。
vec3 open_domain_to_normalized_log2(vec3 in_od, float minimum_ev, float maximum_ev)
{
	const float middle_grey = 0.18; // 中间灰。
	float total_exposure = maximum_ev - minimum_ev; // 承认的曝光跨度。
	vec3 output_log = clamp(log2(in_od / middle_grey), minimum_ev, maximum_ev); // 对数并夹在范围内。
	return (output_log - minimum_ev) / total_exposure; // 归一到零到一。
}

// 求一段幂函数曲线的缩放系数，让曲线在中点处斜率为给定值。
float equation_scale(float x_pivot, float y_pivot, float slope_pivot, float power){
	return pow(pow((slope_pivot * x_pivot), -power) * (pow((slope_pivot * (x_pivot / y_pivot)), power) - 1.0), -1.0 / power); // 由中点条件解出缩放。
}

// 完整的 S 曲线：在中点两侧分别用暗部与亮部指数，得到连续的压缩曲线。
float equation_full_curve(float x, float x_pivot, float y_pivot, float slope_pivot, float toe_power, float shoulder_power){
	float bpivot = float(x >= x_pivot); // 判断在中点的哪一侧。
	float scale_x_pivot = mix(x_pivot, 1.0 - x_pivot, bpivot); // 该侧的横轴中点。
	float scale_y_pivot = mix(y_pivot, 1.0 - y_pivot, bpivot); // 该侧的纵轴中点。
	float toe_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, toe_power); // 暗部缩放。
	float shoulder_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, shoulder_power); // 亮部缩放。
	float scale = mix(-toe_scale, shoulder_scale, bpivot); // 按侧别选缩放。
	float term = (slope_pivot * (x - x_pivot)) / scale; // 曲线中间量。
	float power = mix(toe_power, shoulder_power, float(scale >= 0)); // 按缩放符号选指数。
	float hyperbolic = term / pow(1.0 + pow(term, power), 1.0 / power); // 双曲压缩。
	return scale * hyperbolic + y_pivot; // 返回偏移后的结果。
}

// 把线性显示颜色经过可配置色域转换、对数归一和 S 曲线，得到压缩后的颜色。
vec3 AgXConfigurable(vec3 rgb){
	mat3 sRGB_to_XYZ = primaries_to_matrix(vec2(0.64,0.33),
													vec2(0.3,0.6),
													vec2(0.15,0.06),
													vec2(0.3127, 0.3290)); // 显示原色到三刺激值。
	mat3 adjusted_to_XYZ = ComputeCompressionMatrix(vec2(0.64,0.33),
														vec2(0.3,0.6),
														vec2(0.15,0.06),
														vec2(0.3127, 0.3290)); // 压缩后的色域到三刺激值。
	mat3 XYZ_to_adjusted = inverse(adjusted_to_XYZ); // 三刺激值到压缩色域。
	mat3 XYZ_to_sRGB = inverse(sRGB_to_XYZ); // 三刺激值到显示原色。
	vec3 xyz = rgb * sRGB_to_XYZ; // 转到三刺激值。
	vec3 ajustedRGB = xyz * XYZ_to_adjusted; // 转到压缩色域。
	float x_pivot = abs(min_ev) / (max_ev - min_ev); // 曲线中点的横坐标。
	float y_pivot = 0.5; // 曲线中点的纵坐标。
	vec3 log = open_domain_to_normalized_log2(ajustedRGB, min_ev, max_ev); // 对数归一。
	float outputR = equation_full_curve(log.r, x_pivot, y_pivot, slope, toe_power, shoulder_power); // 红色通道曲线。
	float outputG = equation_full_curve(log.g, x_pivot, y_pivot, slope, toe_power, shoulder_power); // 绿色通道曲线。
	float outputB = equation_full_curve(log.b, x_pivot, y_pivot, slope, toe_power, shoulder_power); // 蓝色通道曲线。
	return vec3(outputR, outputG, outputB); // 返回压缩结果。
}

// 只返回色域转换矩阵的版本，供别处复用。
mat3 AgXConfigurable1(){
	mat3 sRGB_to_XYZ = primaries_to_matrix(vec2(0.64,0.33),
													vec2(0.3,0.6),
													vec2(0.15,0.06),
													vec2(0.3127, 0.3290)); // 显示原色到三刺激值。
	mat3 adjusted_to_XYZ = ComputeCompressionMatrix(vec2(0.64,0.33),
														vec2(0.3,0.6),
														vec2(0.15,0.06),
														vec2(0.3127, 0.3290)); // 压缩后的色域到三刺激值。
	mat3 XYZ_to_adjusted = inverse(adjusted_to_XYZ); // 三刺激值到压缩色域。
	mat3 XYZ_to_sRGB = inverse(sRGB_to_XYZ); // 三刺激值到显示原色。
	return sRGB_to_XYZ * XYZ_to_adjusted; // 返回显示原色到压缩色域的矩阵。
}
#endif // 文件守卫结束。
