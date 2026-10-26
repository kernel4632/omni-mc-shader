/*
颜色与曝光的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/color/color.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_COLOR_COLOR_INCLUDED
#define OMNI_RENDER_COLOR_COLOR_INCLUDED
#include "/effects/color/color.glsl"
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

// --- 内部常数：原 `Settings.glsl` 里不进菜单的曝光常数 ---
#define AE_CLAMP // 给分块亮度设一个极小下限，避免全黑画面把曝光推到无穷。

// 颜色曲线与亮度来自共用数学；曝光统计还要读一号与二号画面。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 强光压缩算法放在通用库里，本文件只保留选项、曝光统计与调用。
#include "/gfx/color.glsl"
// 自动曝光的分块统计也在通用后期库，本文件只填参数。
#include "/gfx/post.glsl"

// --- 曝光统计：按分块对一号画面求平均亮度，得到目标曝光 ---
// 把画面切成固定大小的小块，每个块只读一个亮度，按到中心的距离和亮度给块计权，再加权平均。
// 为什么分块而不是逐像素：逐像素太贵；分块加计权既便宜又能得到接近整屏的平均亮度。
// 为什么用对数平均：亮度跨度很大，直接平均会被几个高光块带偏。
float GetExposureTiles(){
	float avg = Luminance(CurveToLinear(textureLod(colortex1, vec2(0.65, 0.65), floor(log2(min(viewWidth, viewHeight)))).rgb)) * (MAIN_OUTPUT_FACTOR / 128.0); // 用一个粗糙降采样估计整体亮度，供计权用。
	gfx_exposure_params params; // 分块统计需要的全部输入。
	params.screen_size = screenSize; // 画面尺寸。
	params.pixel_size = pixelSize; // 单像素大小。
	params.lod = 6; // 用第六级多级纹理做分块采样。
	params.luma_scale = MAIN_OUTPUT_FACTOR / 128.0; // 管线亮度换算。
	params.average = avg; // 粗估整体亮度。
	params.mode = OMNI_AE_MODE; // 测光方式。
	params.luminance_mode = OMNI_LUMINANCE_WEIGHT_MODE; // 亮度计权方式。
	params.luminance_strength = OMNI_LUMINANCE_WEIGHT_STRENGTH; // 计权强度。
	#ifdef OMNI_END // 末地标记。
		params.end_dimension = true; // 末地不看中心。
	#else
		params.end_dimension = false; // 其他维度按中心计权。
	#endif
	#ifdef OMNI_NETHER // 下界标记。
		params.nether = true; // 下界用固定计权指数。
	#else
		params.nether = false; // 其他维度按整体亮度调整。
	#endif
	#ifdef OMNI_CAVE_MODE // 洞穴模式标记。
		params.cave_mode = true; // 洞穴按偏离整体亮度计权。
	#else
		params.cave_mode = false; // 普通模式不启用洞穴计权。
	#endif
	#ifdef OMNI_OVERWORLD // 主世界标记。
		params.overworld = true; // 主世界指数范围与末地不同。
	#else
		params.overworld = false; // 非主世界不套主世界曲线。
	#endif
	float exposure = gfx_exposure_tile_average(colortex1, params); // 分块循环在通用库里。
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

// 参考签名兼容层：HSV 转 RGB 与 Eclipse 黑体色。
vec3 HsvToRgb(vec3 color){ return ogxHsvToRgb(color); }
vec3 blackbody(float temperature){ return ogxBlackbodyEclipse(temperature); }

// 参考签名兼容层：浮点与定点尾数抖动直接读帧时间，位宽照参考。
vec3 fp10Dither(vec3 color, vec2 tc01){ return ogxDitherFloat(color, tc01, frameTimeCounter, vec3(6.0, 6.0, 5.0)); }
vec3 fp16Dither(vec3 color, vec2 tc01){ return ogxDitherFloat(color, tc01, frameTimeCounter, vec3(10.0)); }
vec3 int8Dither(vec3 color, vec2 tc01){ return ogxDitherFixed(color, tc01, frameTimeCounter, -8.0); }
vec3 int10Dither(vec3 color, vec2 tc01){ return ogxDitherFixed(color, tc01, frameTimeCounter, -10.0); }
vec3 int16Dither(vec3 color, vec2 tc01){ return ogxDitherFixed(color, tc01, frameTimeCounter, -16.0); }

// 参考签名兼容层：iterationT 的默认 AgX 曝光 13、半动态范围 6.5。
vec3 AgX(vec3 color){ return ogxAgx(color, 13.0, 13.0 * 0.5, true); }

// 参考签名兼容层：iterationT 的 `None` 仍做二点二伽马；Eclipse 的 `no_tonemapper` 才原样返回。
vec3 None(vec3 color){ return pow(color, vec3(1.0 / 2.2)); }
vec3 TonemapNone(vec3 color){ return pow(color, vec3(1.0 / 2.2)); }

// 参考签名兼容层：iterationT `SlidePrimary` 直接转发到通用库，参数顺序与参考一致。
vec2 SlidePrimary(vec2 primary, vec2 neighborA, vec2 neighborB, float amount){
	return ogxAgxSlidePrimary(primary, neighborA, neighborB, amount);
}

// 说明：原程序里那套可配置宽色域压缩（`AgXConfigurable` 一族，八个函数与五个常量）在 iterationT 里
// 也没有接入渲染流程，属于实验残留；这里按项目规范「不留死代码」删除，默认画面不受影响，
// 记录见 `docs/parity.md` 的偏离清单。
#endif // OMNI_RENDER_COLOR_COLOR_INCLUDED
