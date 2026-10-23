/*
选择框的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/ground/selection.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/ground/selection.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_GROUND_SELECTION_INCLUDED
#define OMNI_EFFECT_GROUND_SELECTION_INCLUDED
// @effect {"label":{"zh_cn":"选择框","en_us":"Selection & lines"}}
// @option {"label":{"zh_cn":"颜色-红","en_us":"Selection Box Color Red"},"description":{"zh_cn":"方块选择框的红色分量。","en_us":"Red part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_R 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"颜色-绿","en_us":"Selection Box Color Green"},"description":{"zh_cn":"方块选择框的绿色分量。","en_us":"Green part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_G 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"颜色-蓝","en_us":"Selection Box Color Blue"},"description":{"zh_cn":"方块选择框的蓝色分量。","en_us":"Blue part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_B 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"禁用选择框深度写入","en_us":"Disable Selection Box Depth Writing"},"description":{"zh_cn":"让选择框不写深度，减少它引起的错误阴影；不兼容一点一八以下版本。","en_us":"Stops the selection box writing depth, reducing wrong shadows; not for versions below 1.18."}}
#define OMNI_LINE_IMAGE_OUTPUT 0 // [0 1]
#endif // 选项层结束
