/*
植物的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/ground/vegetation.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/ground/vegetation.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_GROUND_VEGETATION_INCLUDED
#define OMNI_EFFECT_GROUND_VEGETATION_INCLUDED
// @effect {"label":{"zh_cn":"植物","en_us":"Plants"}}
// @option {"label":{"zh_cn":"晃动","en_us":"Waving Plants"},"description":{"zh_cn":"草和树叶会不会随风摆，代价很低。","en_us":"Whether grass and leaves sway in the wind; cheap."}}
#define OMNI_WAVING_PLANTS 1 // [0 1]
// @option {"label":{"zh_cn":"阴影贴图植物晃动","en_us":"Waving Plants in ShadowMap"},"description":{"zh_cn":"让影子里的植物也摆；开启后阴影图中植物会闪。","en_us":"Waves plants inside the shadow map; may flicker in the shadow map."}}
//#define OMNI_SHADOW_WAVING_PLANTS
#endif // 选项层结束
