/*
调色与曝光：把线性场景颜色映射成屏幕颜色，并算出自动曝光值；同时给出强光压缩、高级调色与浦肯野效应。
来源：三条强光压缩曲线与曝光值、黑边照 iterationT `Lib/Programs/Final.glsl` 一比一移植；
  自动曝光统计照 iterationT `Lib/IndividualFounctions/MotionBlur.glsl` 的 `GetExposureTiles` 一比一移植；
  可配置的宽色域压缩照 iterationT `Lib/IndividualFounctions/AgX.glsl` 一比一移植；
  浦肯野效应照 iterationT `composite5.fsh` 的 `PurkinjeEffect` 一比一移植；
  白平衡色温照 Eclipse `lib/settings.glsl:748` 的 `WHITE_BALANCE` 与 `composite11.fsh:318-320` 的乘法移植（默认中性）；
  三项曝光增益照 Eclipse `lib/settings.glsl:773/778/779` 的 `EXPOSURE_MULTIPLIER`/`EXPOSURE_DARKENING`/`EXPOSURE_BRIGHTENING` 移植（默认一，画面不变）。
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
  Eclipse 的三项曝光控制是普通增益：原程序把它们放进对数曲线里，与本项目的亮度单位不同，直接照搬会让增亮项几乎不起作用；
  这里按同一意图做成整体增益，默认都为一、画面不变，逐条重建改为「曝光变暗」「曝光增亮」，见 `docs/eclipse-parity.md` 色调与曝光行。
*/
#ifndef OMNI_COLOR_INCLUDED // 只引入一次，避免选项、内部常数与函数重复定义。
#define OMNI_COLOR_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"颜色与曝光","en_us":"Color & exposure"}}
// @option {"label": {"zh_cn": "强光压缩方式", "en_us": "Tonemap"}, "description": {"zh_cn": "把高动态范围压到屏幕范围所用的曲线。这一项在项目里用序号表示，零为 AgX，一为 ACES，二为无压缩。", "en_us": "Curve that maps high dynamic range into display range. Stored as an index: zero AgX, one ACES, two none."}, "values": {"0": {"zh_cn": "AgX", "en_us": "AgX"}, "1": {"zh_cn": "ACES", "en_us": "ACES"}, "2": {"zh_cn": "无", "en_us": "None"}}}
#define OMNI_TONEMAP_OPERATOR 0 // [0 1 2]
// @option {"label": {"zh_cn": "AgX 动态范围", "en_us": "AgX Dynamic Range"}, "slider": true, "description": {"zh_cn": "AgX 曲线承认的曝光范围，越大高光与暗部保留越多。", "en_us": "Exposure range the AgX curve accepts; larger keeps more highlight and shadow."}}
#define OMNI_AGX_EV 13.0 // [8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0 12.5 13.0 13.5 14.0 14.5 15.0 15.5 16.0 16.5 17.0 17.5 18.0 24.0 32.0]
// @option {"label": {"zh_cn": "阿布尼效应校正", "en_us": "Abney Effect Correction"}, "description": {"zh_cn": "抵消加亮时色相偏移，亮部颜色更接近真实。", "en_us": "Counteracts the hue shift when lightening, keeping highlights more natural."}}
#define OMNI_ABNEY_EFFECT_CORRECTION 1 // [0 1]
// @option {"label": {"zh_cn": "高级调色", "en_us": "Advanced Color Adjustment"}, "description": {"zh_cn": "启用白光裁剪、亮度伽马与饱和度这组更细致的调整。", "en_us": "Enables the finer white-clip, luminance-gamma and saturation adjustments."}}
#define OMNI_ADVANCED_COLOR 0 // [0 1]
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
#define OMNI_MANUAL_EXPOSURE 0 // [0 1]
// @option {"label": {"zh_cn": "固定曝光值", "en_us": "Exact EV value"}, "slider": true, "description": {"zh_cn": "手动曝光所用的曝光值。", "en_us": "Exposure value used by manual exposure."}}
#define OMNI_EV_VALUE 14.0 // [0.0 0.33 0.67 1.0 1.33 1.67 2.0 2.33 2.67 3.0 3.33 3.67 4.0 4.33 4.67 5.0 5.33 5.67 6.0 6.33 6.67 7.0 7.33 7.67 8.0 8.33 8.67 9.0 9.33 9.67 10.0 10.33 10.67 11.0 11.33 11.67 12.0 12.33 12.67 13.0 13.33 13.67 14.0 14.33 14.67 15.0 15.33 15.67 16.0 16.33 16.67 17.0 17.33 17.67 18.0 18.33 18.67 19.0 19.33 19.67 20.0]
// @option {"label": {"zh_cn": "曝光偏移", "en_us": "AE Offset"}, "slider": true, "description": {"zh_cn": "在自动曝光结果上整体加减的曝光，负值更暗。", "en_us": "Exposure added on top of the auto result; negative is darker."}}
#define OMNI_AE_OFFSET 0.0 // [-5.0 -4.67 -4.33 -4.0 -3.67 -3.33 -3.0 -2.67 -2.33 -2.0 -1.67 -1.33 -1.0 -0.67 -0.33 0.0 0.33 0.67 1.0 1.33 1.67 2.0 2.33 2.67 3.0 3.33 3.67 4.0 4.33 4.67 5.0]
// @option {"label": {"zh_cn": "曝光乘数", "en_us": "Exposure Multiplier"}, "slider": true, "description": {"zh_cn": "在整个曝光上再乘一个系数，调大整体更亮。来源 Eclipse `lib/settings.glsl:773` 的 `EXPOSURE_MULTIPLIER`。", "en_us": "Extra gain applied to the whole exposure; larger is brighter. From Eclipse `lib/settings.glsl:773` `EXPOSURE_MULTIPLIER`."}}
#define OMNI_EXPOSURE_MULTIPLIER 1.0 // [0.25 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.1 1.2 1.3 1.4 1.5 2.0 3.0 4.0]
// @option {"label": {"zh_cn": "曝光变暗", "en_us": "Exposure Darkening"}, "slider": true, "description": {"zh_cn": "把整个曝光往下压，一为不变、零为全黑。来源 Eclipse `lib/settings.glsl:778` 的 `EXPOSURE_DARKENING`。", "en_us": "Pushes the whole exposure down; one is unchanged, zero is black. From Eclipse `lib/settings.glsl:778` `EXPOSURE_DARKENING`."}}
#define OMNI_EXPOSURE_DARKENING 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label": {"zh_cn": "曝光增亮", "en_us": "Exposure Brightening"}, "slider": true, "description": {"zh_cn": "把整个曝光往上抬，一为不变、越大越亮。来源 Eclipse `lib/settings.glsl:779` 的 `EXPOSURE_BRIGHTENING`，按名称取为增亮（原程序该项在分母里，方向相反）。", "en_us": "Lifts the whole exposure; one is unchanged, larger is brighter. From Eclipse `lib/settings.glsl:779` `EXPOSURE_BRIGHTENING`, oriented as a brightening (the original sits in the denominator, opposite direction)."}}
#define OMNI_EXPOSURE_BRIGHTENING 1.0 // [1.0 1.05 1.1 1.2 1.3 1.4 1.5 1.6 1.8 2.0 2.5 3.0 4.0]
// @option {"label": {"zh_cn": "测光方式", "en_us": "AE Mode"}, "description": {"zh_cn": "自动曝光如何给画面的不同位置计权。", "en_us": "How auto exposure weights different screen areas."}, "values": {"0": {"zh_cn": "默认", "en_us": "Default"}, "1": {"zh_cn": "中心权重", "en_us": "Center Weighted"}, "2": {"zh_cn": "只看中心", "en_us": "Center Only"}, "3": {"zh_cn": "全屏平均", "en_us": "Screen Average"}}}
#define OMNI_AE_MODE 0 // [0 1 2 3]
// @option {"label": {"zh_cn": "曝光曲线", "en_us": "AE Curve"}, "slider": true, "description": {"zh_cn": "平均亮度到曝光的曲线指数，越大越克制。", "en_us": "Exponent mapping average luminance to exposure."}}
#define OMNI_AE_CURVE 0.7 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.85 0.9 0.95 1.0]
// @option {"label": {"zh_cn": "亮度计权方式", "en_us": "Luminance Weighted Mode"}, "description": {"zh_cn": "按分块亮度给曝光统计计权，让暗部或亮部更有话语权。", "en_us": "Weights the exposure statistic by tile luminance."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "预设一", "en_us": "Preset 1"}, "2": {"zh_cn": "预设二", "en_us": "Preset 2"}, "3": {"zh_cn": "偏向暗部", "en_us": "Shadow Priority"}, "4": {"zh_cn": "偏向高光", "en_us": "Highlight Priority"}}}
#define OMNI_LUMINANCE_WEIGHT_MODE 1 // [0 1 2 3 4]
// @option {"label": {"zh_cn": "计权强度", "en_us": "Weighted Strength"}, "slider": true, "description": {"zh_cn": "亮度计权的强度，越大越偏向所选的暗部或高光。", "en_us": "Strength of luminance weighting."}}
#define OMNI_LUMINANCE_WEIGHT_STRENGTH 0.7 // [0.5 0.7 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "平滑曝光", "en_us": "Smooth AE"}, "description": {"zh_cn": "让自动曝光随时间缓慢变化，减少亮暗突变时的跳动。", "en_us": "Makes auto exposure change gradually over time."}}
#define OMNI_SMOOTH_EXPOSURE 1 // [0 1]
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
#define OMNI_DISABLE_NIGHTVISION 0 // [0 1]
// @option {"label": {"zh_cn": "关闭失明与黑暗校正", "en_us": "Disable Blindness & Darkness"}, "page": "dev", "description": {"zh_cn": "调试开关：忽略失明与黑暗对曝光、泛光和原版雾的影响。","en_us": "Debug switch: ignores blindness and darkness on exposure, bloom and vanilla fog."}}
#define OMNI_DISABLE_BLINDNESS_DARKNESS 0 // [0 1]

// --- 内部常数：原 `Settings.glsl` 里不进菜单的曝光常数 ---
#define AE_CLAMP // 给分块亮度设一个极小下限，避免全黑画面把曝光推到无穷。

// 颜色曲线与亮度来自共用数学；曝光统计还要读一号与二号画面。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 强光压缩算法放在通用库里，本文件只保留选项、曝光统计与调用。
#include "/gfx/color.glsl"

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
// 手动模式直接由曝光值换算；自动模式再按曲线和偏移调整，并乘回管线单位；
// 最后统一叠三项 Eclipse 曝光增益（乘数、变暗、增亮），默认均为一时结果与原来相同。
float GetExposureValue(){
	float exposure; // 先算出基础曝光，再统一叠增益。
	#if OMNI_MANUAL_EXPOSURE // 手动曝光。
		exposure = 1.5e5 * MAIN_OUTPUT_FACTOR * exp2(-OMNI_EV_VALUE); // 由曝光值直接换算。
	#else // 自动曝光。
		float ae = CurveToLinear(texelFetch(colortex2, ivec2(0, screenSize.y - 1.0), 0).a) * (5120.0 / EXPOSURE_OUTPUT_FACTOR); // 读顶行自动曝光统计。
		float aeCurve = OMNI_AE_CURVE; // 曲线指数初值。
		#if !OMNI_DISABLE_NIGHTVISION // 夜视时把曲线指数抬到接近一。
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
		#if !OMNI_DISABLE_BLINDNESS_DARKNESS // 黑暗效果时压低曝光。
			ae *= 1.0 - min(darknessLightFactor * 2.0, 0.9); // 按黑暗脉动亮度压低。
		#endif
		exposure = 8.5 * MAIN_OUTPUT_FACTOR * ae; // 乘回管线单位得到基础曝光。
	#endif
	return exposure * OMNI_EXPOSURE_MULTIPLIER * OMNI_EXPOSURE_DARKENING * OMNI_EXPOSURE_BRIGHTENING; // 叠三项增益，默认一为原样。
}

// --- 黑边：按电影比例在画面上下画黑边 ---
// `newRatio` 是目标宽高比，零表示不加黑边。返回零或一表示该像素是否落在画面内。
float BlackBar(float newRatio){
	return gfx_black_bar(texCoord, aspectRatio, newRatio); // 黑边形状在通用库。
}

// --- 浦肯野效应：暗处向偏蓝的暗视觉偏移 ---
// 亮度低于阈值时，颜色向偏蓝的亮度混合，阈值和强度由选项控制。
void PurkinjeEffect(inout vec3 color){
	gfx_purkinje(color, OMNI_PURKINJE_EFFECT_THRESHOLD, OMNI_PURKINJE_EFFECT_STRENGTH); // 混合公式在通用库。
}

// --- 白平衡：按色温给线性颜色染色 ---
// 来源 Eclipse `composite11.fsh:318-320`，那里在色调映射之前对线性颜色乘 `blackbody(WHITE_BALANCE)`。
// 为什么默认六千五百开尔文视为中性：日光下的白点约六千五百开尔文，此时判定为中性、不改动颜色，
//   与原程序的 `#if WHITE_BALANCE != 6500` 等价，保证默认画面不变。
// 为什么放在色调映射之前：白平衡是相机白点校正，要在曝光后的线性颜色上做；
//   压缩曲线之后再改会破坏已经压好的高光，也与真实相机的处理顺序不符。
vec3 WhiteBalance(vec3 color){
	if (OMNI_WHITE_BALANCE != 6500.0) color = gfx_white_balance(color, Blackbody(OMNI_WHITE_BALANCE)); // 非中性时才按黑体色温染色，低值偏暖、高值偏冷。
	return color; // 返回染色后的线性颜色。
}

// --- 高级调色：白光裁剪、亮度伽马与饱和度，从十四号主体里单独拆出 ---
// 先回线性空间，再压白点、按亮度伽马调整明暗对比、按饱和度调整鲜艳度，最后回显示空间。
vec3 AdvancedColor(vec3 color){
	return gfx_advanced_color(color, OMNI_LUMA_GAMMA, OMNI_WHITE_CLIP, OMNI_SATURATION, OMNI_GAMMA); // 调色步骤在通用库，选项在这里传入。
}

// 说明：原程序里那套可配置宽色域压缩（`AgXConfigurable` 一族，八个函数与五个常量）在 iterationT 里
// 也没有接入渲染流程，属于实验残留；这里按项目规范「不留死代码」删除，默认画面不受影响，
// 记录见 `docs/parity.md` 的偏离清单。
#endif // 文件守卫结束。
