/*
色彩分级的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/color/colorgrade.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/color/colorgrade.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
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
#endif // 选项层结束
