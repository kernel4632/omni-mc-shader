/*
下界的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/nether.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/nether.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_NETHER_INCLUDED
#define OMNI_EFFECT_WORLD_NETHER_INCLUDED
// @effect {"label":{"zh_cn":"下界","en_us":"Nether"}}
// @option {"label":{"zh_cn":"环境亮度","en_us":"Nether Ambient Brightness"},"description":{"zh_cn":"下界不等于无光，这里的整体亮度。","en_us":"Overall ambient brightness in the Nether, which is never fully dark."},"slider":true}
#define OMNI_NETHER_BRIGHTNESS 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"空气雾","en_us":"Nether volumetric fog"},"description":{"zh_cn":"在原有解析下界雾之上，叠加 Eclipse 的羽流烟柱、顶部烟与雾霭三段体积雾；关闭时画面与原来完全一致。","en_us":"Adds Eclipse's three volumetric layers (plumes, ceiling smoke, haze) on top of the existing analytic Nether fog; off leaves the original picture unchanged."}}
#define OMNI_NETHER_VOLUMETRIC_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"羽流密度","en_us":"Nether plume density"},"description":{"zh_cn":"下界低空发光烟柱的浓淡，越大烟柱越明显。","en_us":"Thickness of the glowing low plumes; larger makes them more visible."},"slider":true}
#define OMNI_NETHER_PLUME_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"顶部烟密度","en_us":"Nether ceiling smoke density"},"description":{"zh_cn":"贴近下界天花板出现的灰烟浓淡。","en_us":"Thickness of the grey smoke near the Nether ceiling."},"slider":true}
#define OMNI_NETHER_CEILING_SMOKE_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"雾霭密度","en_us":"Nether haze density"},"description":{"zh_cn":"整片下界空气的均匀雾霭浓淡。","en_us":"Thickness of the uniform haze filling the Nether air."},"slider":true}
#define OMNI_NETHER_HAZE_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"空气雾采样质量","en_us":"Nether volumetric fog quality"},"description":{"zh_cn":"下界体积雾沿视线的采样次数，越高越干净也越慢，默认十六与 Eclipse 相同。","en_us":"View samples for the Nether volumetric fog; higher is cleaner and slower, default 16 matches Eclipse."},"slider":true}
#define OMNI_NETHER_VFOG_QUALITY 16 // [4 6 8 10 12 16 20 24 32 48]
#endif // 选项层结束
