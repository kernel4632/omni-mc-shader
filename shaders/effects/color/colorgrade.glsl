/*
效果文件 `effects/color/colorgrade.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/color/colorgrade.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_COLOR_COLORGRADE_INCLUDED
#define OMNI_EFFECT_COLOR_COLORGRADE_INCLUDED
// @effect {"label": {"zh_cn": "色彩分级", "en_us": "Color grading"}}
// @option {"label": {"zh_cn": "色彩分级", "en_us": "Color Grading"}, "description": {"zh_cn": "按暗部、中间调、高光三段分别染色。默认关闭，开启后下面三组参数才参与计算。", "en_us": "Tints shadows, mids and highlights separately. Off by default; the three groups below take effect only when enabled."}}
#define OMNI_COLOR_GRADING 0 // [0 1]
// @option {"label": {"zh_cn": "暗部红", "en_us": "Shadows Red"}, "slider": true, "description": {"zh_cn": "暗部偏向的目标色红色分量；三个分量都为一表示中性。", "en_us": "Red component of the shadow target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_SHADOWS_R 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "暗部绿", "en_us": "Shadows Green"}, "slider": true, "description": {"zh_cn": "暗部偏向的目标色绿色分量；三个分量都为一表示中性。", "en_us": "Green component of the shadow target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_SHADOWS_G 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "暗部蓝", "en_us": "Shadows Blue"}, "slider": true, "description": {"zh_cn": "暗部偏向的目标色蓝色分量；三个分量都为一表示中性。", "en_us": "Blue component of the shadow target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_SHADOWS_B 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "暗部倍率", "en_us": "Shadows Multiplier"}, "slider": true, "description": {"zh_cn": "暗部整体的明暗倍率，一为不变，越大越亮。", "en_us": "Overall brightness multiplier for shadows; one is unchanged, larger is brighter."}}
#define OMNI_COLOR_GRADING_SHADOWS_MUL 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "中间调红", "en_us": "Mids Red"}, "slider": true, "description": {"zh_cn": "中间调偏向的目标色红色分量；三个分量都为一表示中性。", "en_us": "Red component of the midtone target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_MIDS_R 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "中间调绿", "en_us": "Mids Green"}, "slider": true, "description": {"zh_cn": "中间调偏向的目标色绿色分量；三个分量都为一表示中性。", "en_us": "Green component of the midtone target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_MIDS_G 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "中间调蓝", "en_us": "Mids Blue"}, "slider": true, "description": {"zh_cn": "中间调偏向的目标色蓝色分量；三个分量都为一表示中性。", "en_us": "Blue component of the midtone target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_MIDS_B 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "中间调倍率", "en_us": "Mids Multiplier"}, "slider": true, "description": {"zh_cn": "中间调整体的明暗倍率，一为不变，越大越亮。", "en_us": "Overall brightness multiplier for mids; one is unchanged, larger is brighter."}}
#define OMNI_COLOR_GRADING_MIDS_MUL 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "高光红", "en_us": "Highlights Red"}, "slider": true, "description": {"zh_cn": "高光偏向的目标色红色分量；三个分量都为一表示中性。", "en_us": "Red component of the highlight target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_HIGHLIGHTS_R 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "高光绿", "en_us": "Highlights Green"}, "slider": true, "description": {"zh_cn": "高光偏向的目标色绿色分量；三个分量都为一表示中性。", "en_us": "Green component of the highlight target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_HIGHLIGHTS_G 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "高光蓝", "en_us": "Highlights Blue"}, "slider": true, "description": {"zh_cn": "高光偏向的目标色蓝色分量；三个分量都为一表示中性。", "en_us": "Blue component of the highlight target colour; all three at one is neutral."}}
#define OMNI_COLOR_GRADING_HIGHLIGHTS_B 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "高光倍率", "en_us": "Highlights Multiplier"}, "slider": true, "description": {"zh_cn": "高光整体的明暗倍率，一为不变，越大越亮。", "en_us": "Overall brightness multiplier for highlights; one is unchanged, larger is brighter."}}
#define OMNI_COLOR_GRADING_HIGHLIGHTS_MUL 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "亮度曲线", "en_us": "Luminance Curve"}, "description": {"zh_cn": "按下面两个参数把暗部与亮部的亮度拉开或收回。默认关闭，关闭时不改画面。", "en_us": "Pushes shadows and highlights apart or together using the two values below. Off by default."}}
#define OMNI_LUMINANCE_CURVE 0 // [0 1]
// @option {"label": {"zh_cn": "暗部曲线", "en_us": "Lower Curve"}, "slider": true, "description": {"zh_cn": "正值抬高暗部，负值压暗暗部，零为不变。", "en_us": "Positive lifts shadows, negative darkens them, zero is unchanged."}}
#define OMNI_LUMINANCE_CURVE_LOWER 0.0 // [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "亮部曲线", "en_us": "Upper Curve"}, "slider": true, "description": {"zh_cn": "正值抬高亮部，负值压暗亮部，零为不变。", "en_us": "Positive lifts highlights, negative darkens them, zero is unchanged."}}
#define OMNI_LUMINANCE_CURVE_UPPER 0.0 // [-2.0 -1.9 -1.8 -1.7 -1.6 -1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label": {"zh_cn": "串色", "en_us": "Crosstalk"}, "slider": true, "description": {"zh_cn": "让亮度影响饱和度：正值亮处更靠拢、暗处更分离，负值相反；零为不变。来源 Eclipse `settings.glsl:746` 的 `CROSSTALK`。", "en_us": "Lets luminance drive saturation: positive pulls bright colours together and parts dark ones, negative does the opposite; zero is unchanged. From Eclipse `settings.glsl:746` `CROSSTALK`."}}
#define OMNI_CROSSTALK 0.0 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.4 -0.3 -0.2 -0.1 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
色彩分级：对已经过色调映射的显示域颜色做暗部、中间调、高光三段染色，并提供一条可选的亮度曲线。
职责：把 Eclipse `dimensions/composite12.fsh:77-105` 的 `luminanceCurve` 与 `colorGrading` 一比一移植；
    两个开关 `OMNI_LUMINANCE_CURVE`、`OMNI_COLOR_GRADING` 都默认关闭，默认画面与移植前完全一致。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE14_PASS` 分支在 `TonemapColor()` 之后、写回一号画面之前调用 `OmniColorGrade`；
    也就是管线里色调映射已经完成、颜色变成零到一显示域的位置，与 Eclipse 把分级放在色调映射之后一致。
可复制示例：`color = OmniColorGrade(color);`（要求调用方已引入本文件，且传入的颜色是零到一显示域颜色）。
关键设计原因与取舍：
    Eclipse 原程序这两个开关默认就关闭，移植后也默认关闭，保证不改变当前默认画面。
    分段染色的数学：先按三通道平均亮度算出暗部、中间调、高光三段权重，三段权重在设计上相加等于一；
    再把颜色各乘每段的目标色与倍率，按权重叠加，最后夹到零到一，让不同亮度范围各自偏向一个颜色。
    `1.7320508076` 是根号三：目标色三通道都取一时，归一化后的目标再乘它正好还原为一，默认取值才不会偏色。
    原程序把三个目标色写成文件级 `const`，这里改成函数内局部量；因为 GLSL 的 `const` 初始化不允许调用 `normalize`。
    与 `OMNI_WHITE_BALANCE` 不重复：白平衡在色调映射之前做相机白点校正，本文件在色调映射之后做创作染色，阶段不同。
    串色 `OMNI_CROSSTALK` 来自 Eclipse `composite12.fsh:134` 的 `saturationAndCrosstalk`，默认零、不做处理；
    Eclipse 把饱和度与串色写在同一行，本项目饱和度在 `effects/color/color.glsl` 的高级调色里，这里只补串色这一项。
*/


// 共用数学：提供 `saturate` 等基础函数，本文件的分段染色与曲线都用到它。
#include "/common/math.glsl"
#include "/gfx/post.glsl"

// --- 亮度曲线：按通道把暗部与亮部拉开或收回 ---
// 暗部曲线：在零点附近抬起一段抛物线，`OMNI_LUMINANCE_CURVE_LOWER` 为正时暗部变亮，为零时整条曲线为零。
float OmniLowerCurve(float x) { return gfx_lower_curve(x); }

// 亮部曲线：在一附近抬起一段抛物线，`OMNI_LUMINANCE_CURVE_UPPER` 为正时亮部更亮，为零时整条曲线为零。
float OmniUpperCurve(float x) { return gfx_upper_curve(x); }

// 亮度曲线整体：三个通道各自叠加一条暗部曲线与一条亮部曲线，通道独立处理所以不会串色。
vec3 OmniLuminanceCurve(vec3 color) { return gfx_luminance_curve(color, OMNI_LUMINANCE_CURVE_LOWER, OMNI_LUMINANCE_CURVE_UPPER); }

// --- 分段染色：暗部、中间调、高光各乘一个目标色与倍率，再按亮度权重叠加 ---
// 目标色：把三个通道的取值归一化成方向；三者都接近零时没有方向，返回零，避免归一化除以零。
vec3 OmniGradeTarget(float red, float green, float blue) { return gfx_grade_target(red, green, blue); }

// 分段染色主体：按三通道平均亮度把每个像素分到暗部、中间调、高光三段，各段乘自己的目标与倍率。
// 为什么用平均亮度而不是感知亮度：此处沿用 Eclipse 原写法，三通道各占三分之一，改权重会改变分段边界。
vec3 OmniSegmentGrade(vec3 color){
	float gradeLuma = dot(color, vec3(1.0 / 3.0)); // 三通道平均亮度，决定这个像素落在哪一段。
	float shadowsAmount = saturate(-6.0 * gradeLuma + 2.75); // 暗部权重，亮度越低越大。
	float midsAmount = saturate(-abs(6.0 * gradeLuma - 3.0) + 1.25); // 中间调权重，亮度居中时最大。
	float highlightsAmount = saturate(6.0 * gradeLuma - 3.25); // 高光权重，亮度越高越大。
	vec3 shadowsTarget = OmniGradeTarget(OMNI_COLOR_GRADING_SHADOWS_R, OMNI_COLOR_GRADING_SHADOWS_G, OMNI_COLOR_GRADING_SHADOWS_B); // 暗部目标方向。
	vec3 midsTarget = OmniGradeTarget(OMNI_COLOR_GRADING_MIDS_R, OMNI_COLOR_GRADING_MIDS_G, OMNI_COLOR_GRADING_MIDS_B); // 中间调目标方向。
	vec3 highlightsTarget = OmniGradeTarget(OMNI_COLOR_GRADING_HIGHLIGHTS_R, OMNI_COLOR_GRADING_HIGHLIGHTS_G, OMNI_COLOR_GRADING_HIGHLIGHTS_B); // 高光目标方向。
	vec3 gradedShadows = color * shadowsTarget * OMNI_COLOR_GRADING_SHADOWS_MUL * 1.7320508076; // 暗部染色，乘根号三还原中性。
	vec3 gradedMids = color * midsTarget * OMNI_COLOR_GRADING_MIDS_MUL * 1.7320508076; // 中间调染色，同样乘根号三。
	vec3 gradedHighlights = color * highlightsTarget * OMNI_COLOR_GRADING_HIGHLIGHTS_MUL * 1.7320508076; // 高光染色，同样乘根号三。
	return saturate(gradedShadows * shadowsAmount + gradedMids * midsAmount + gradedHighlights * highlightsAmount); // 按三段权重叠加并夹到零到一。
}

// --- 对外入口：按两个开关决定是否做亮度曲线与分段染色 ---
// 顺序照 Eclipse：先做亮度曲线，再做分段染色。两个开关默认关闭，都关时原样返回颜色。
// 串色（`OMNI_CROSSTALK`）独立于两个开关，默认零时不做任何处理、画面不变。
vec3 OmniColorGrade(vec3 color){
	#if OMNI_LUMINANCE_CURVE // 开着亮度曲线时先调明暗两端。
		color = OmniLuminanceCurve(color); // 按通道做暗部与亮部修正。
	#endif
	#if OMNI_COLOR_GRADING // 开着色彩分级时再做三段染色。
		color = OmniSegmentGrade(color); // 按亮度分段染色并叠加。
	#endif
	if (OMNI_CROSSTALK != 0.0){ // 串色：让亮度拉近或推开颜色的饱和程度，默认零跳过。
		float crosstalkLuma = dot(color, vec3(1.0 / 3.0)); // 三通道平均亮度，与 Eclipse `composite12.fsh:130` 的 `luma` 一致。
		color += (color - crosstalkLuma) * (-crosstalkLuma * OMNI_CROSSTALK); // 与 Eclipse 串色项 `lumaColDiff*(-luminance*CROSSTALK)` 相同。
	}
	return color; // 返回最终显示域颜色。
}
#endif // OMNI_EFFECT_COLOR_COLORGRADE_INCLUDED
