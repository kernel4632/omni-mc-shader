/*
标题标志的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lens/title.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lens/title.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LENS_TITLE_INCLUDED
#define OMNI_EFFECT_LENS_TITLE_INCLUDED
// @effect {"label":{"zh_cn":"标题标志","en_us":"Title Logo"}}
// @option {"label": {"zh_cn": "标题标志", "en_us": "Title Logo"}, "page": "about", "description": {"zh_cn": "世界加载后短暂浮现 iterationT 品牌图标，来源 iterationT `Lib/Settings.glsl:481` 的 `TITLE`。", "en_us": "Briefly fades in the iterationT brand logo after a world loads. From iterationT `Lib/Settings.glsl:481` `TITLE`."}}
#define OMNI_TITLE 1 // [0 1]
#endif // 选项层结束
