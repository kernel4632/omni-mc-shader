/*
镜头形变的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lens/distortion.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lens/distortion.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LENS_DISTORTION_INCLUDED
#define OMNI_EFFECT_LENS_DISTORTION_INCLUDED
// @effect {"label":{"zh_cn":"镜头形变","en_us":"Lens Distortion"}}
// @option {"label": {"zh_cn": "色差", "en_us": "Chromatic Aberration"}, "description": {"zh_cn": "全屏的镜头色差，让画面边缘的红蓝通道错开出彩边；与景深的散景色散不同。来源 Eclipse `lib/settings.glsl:811`。", "en_us": "Full-screen lens chromatic aberration; edges fringe red and blue. Different from the depth-of-field bokeh dispersion. From Eclipse `lib/settings.glsl:811`."}}
#define OMNI_CHROMATIC_ABERRATION 0 // [0 1]
// @option {"label": {"zh_cn": "色差强度", "en_us": "Chromatic Aberration Strength"}, "slider": true, "description": {"zh_cn": "色错的错开量，越大彩边越宽。来源 Eclipse `lib/settings.glsl:812`。", "en_us": "How far the colour channels are offset. From Eclipse `lib/settings.glsl:812`."}}
#define OMNI_CHROMATIC_ABERRATION_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 4.0 5.0]
// @option {"label": {"zh_cn": "鱼眼畸变", "en_us": "Fisheye"}, "description": {"zh_cn": "把画面从中心向外卷成桶形，模拟鱼眼镜头。来源 Eclipse `lib/settings.glsl:828`。", "en_us": "Warps the frame into a barrel shape, like a fisheye lens. From Eclipse `lib/settings.glsl:828`."}}
#define OMNI_FISHEYE 0 // [0 1]
// @option {"label": {"zh_cn": "鱼眼强度", "en_us": "Fisheye Strength"}, "slider": true, "description": {"zh_cn": "鱼眼卷曲的程度，越大边缘收得越紧。来源 Eclipse `lib/settings.glsl:827`。", "en_us": "How strongly the frame is warped. From Eclipse `lib/settings.glsl:827`."}}
#define OMNI_FISHEYE_STRENGTH 0.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "像素化", "en_us": "Pixelate"}, "description": {"zh_cn": "把画面按方块取色，模拟低分辨率画面。来源 Eclipse `lib/settings.glsl:820`。", "en_us": "Snaps the frame to blocks, like a low resolution. From Eclipse `lib/settings.glsl:820`."}}
#define OMNI_PIXELATE 0 // [0 1]
// @option {"label": {"zh_cn": "像素块大小", "en_us": "Pixel Size"}, "slider": true, "description": {"zh_cn": "每个方块占多少屏幕像素。来源 Eclipse `lib/settings.glsl:823` 的 `PIXELIZATION_STRENGTH`。", "en_us": "How many screen pixels each block covers. From Eclipse `lib/settings.glsl:823` `PIXELIZATION_STRENGTH`."}}
#define OMNI_PIXELATE_STRENGTH 4 // [2 3 4 5 6 7 8 9 10 16 32 64]
// @option {"label": {"zh_cn": "每通道色数", "en_us": "Colors per Channel"}, "slider": true, "description": {"zh_cn": "每个通道分几档颜色，零表示不分档，与像素化各自独立。来源 Eclipse `lib/settings.glsl:825` 的 `MAX_COLORS_PER_CHANNEL`。", "en_us": "Quantisation steps per channel; zero disables it, independent of pixelate. From Eclipse `lib/settings.glsl:825` `MAX_COLORS_PER_CHANNEL`."}}
#define OMNI_PIXELATE_COLORS 0 // [0 4 8 16 32 64 128 256 512]
#endif // 选项层结束
