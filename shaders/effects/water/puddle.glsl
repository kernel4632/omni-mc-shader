/*
水洼的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/water/puddle.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/water/puddle.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WATER_PUDDLE_INCLUDED
#define OMNI_EFFECT_WATER_PUDDLE_INCLUDED
// @effect {"label":{"zh_cn":"水洼","en_us":"Puddles"}}
// 菜单页留在「水与地面」：水洼属于地表效果，与水面、地面和植物放在同一页。
// @option {"label":{"zh_cn":"尺寸","en_us":"Puddle size"},"description":{"zh_cn":"低洼处积水范围的大小，调大后水洼更大更连片，调小更零散；来源 Eclipse 的 `Puddle_Size`，默认 1.0 与参考一致。","en_us":"Size of the puddles that form in low spots; larger makes them bigger and better connected. From Eclipse `Puddle_Size`; default 1.0 matches the reference."}}
#define OMNI_PUDDLE_SIZE 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"湿面反射锐度","en_us":"Wet reflection sharpness"},"description":{"zh_cn":"湿表面反射的清晰程度，调大后积水表面更接近镜面；默认 0.0 表示不改动当前粗糙度，Eclipse 默认 0.9。","en_us":"How sharp reflections get on wet ground; larger is more mirror-like. Default 0.0 leaves roughness unchanged; Eclipse default is 0.9."}}
#define OMNI_PUDDLE_REFLECTION_SHARPNESS 0.0 // [0.0 0.9 0.925 0.95 0.975 1.0]
#endif // 选项层结束
