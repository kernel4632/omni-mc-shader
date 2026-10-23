/*
行星曲率的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/planet.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/planet.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_PLANET_INCLUDED
#define OMNI_EFFECT_WORLD_PLANET_INCLUDED
// @effect {"label":{"zh_cn":"行星曲率","en_us":"Planet curvature"}}
// @option {"label":{"zh_cn":"行星曲率","en_us":"Planet curvature"},"description":{"zh_cn":"让远处地形、实体与水面随距相机的距离逐渐下沉，模拟星球表面的弯曲地平线。默认关闭，关闭时画面与现在完全一致。","en_us":"Sinks terrain, entities and water with distance from the camera to simulate a curved planet surface. Off by default."}}
#define OMNI_PLANET_CURVATURE 0 // [0 1]
// @option {"label":{"zh_cn":"曲率强度","en_us":"Curvature amount"},"description":{"zh_cn":"下沉的强度，越大弯曲越明显；默认一，照 Eclipse。零等于不弯曲。","en_us":"Strength of the drop; larger bends more. Default matches Eclipse; zero means no bending."},"slider":true}
#define OMNI_CURVATURE_AMOUNT 1.0 // [-10.0 -5.0 -2.0 -1.5 -1.0 -0.5 0.0 0.5 1.0 1.5 2.0 5.0 10.0]
#endif // 选项层结束
