/*
自发光矿石与纹饰的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lighting/emissive.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lighting/emissive.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LIGHTING_EMISSIVE_INCLUDED
#define OMNI_EFFECT_LIGHTING_EMISSIVE_INCLUDED
// @effect {"label":{"zh_cn":"自发光矿石与纹饰","en_us":"Emissive ores & trims"}}
// @option {"label":{"zh_cn":"发光矿石","en_us":"Emissive ores"},"description":{"zh_cn":"让矿石里鲜亮的矿物颗粒按贴图颜色发光；需开启物理光照。","en_us":"Makes the bright mineral specks in ores glow from the texture colour; needs PBR."}}
#define OMNI_EMISSIVE_ORES 0 // [0 1]
// @option {"label":{"zh_cn":"矿石发光亮度","en_us":"Ore glow brightness"},"description":{"zh_cn":"自发光矿石的整体亮度。","en_us":"Overall brightness of emissive ores."},"slider":true}
#define OMNI_EMISSIVE_ORES_STRENGTH 0.9 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"发光纹饰","en_us":"Emissive trims"},"description":{"zh_cn":"让盔甲纹饰按明度发光；需开启物理光照。","en_us":"Makes armour trims glow by their brightness; needs PBR."}}
#define OMNI_EMISSIVE_TRIMS 0 // [0 1]
// @option {"label":{"zh_cn":"纹饰发光亮度","en_us":"Trim glow brightness"},"description":{"zh_cn":"自发光纹饰的整体亮度。","en_us":"Overall brightness of emissive trims."},"slider":true}
#define OMNI_EMISSIVE_TRIMS_STRENGTH 0.7 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif // 选项层结束
