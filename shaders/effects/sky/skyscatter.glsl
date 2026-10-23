/*
天空散射的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/sky/skyscatter.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/sky/skyscatter.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_SKY_SKYSCATTER_INCLUDED
#define OMNI_EFFECT_SKY_SKYSCATTER_INCLUDED
// @effect {"label":{"zh_cn":"天空散射","en_us":"Sky Scattering"}}
// @option {"label":{"zh_cn":"天空亮度","en_us":"Sky Brightness"},"description":{"zh_cn":"整个天空辐射的亮度倍率，默认一倍与现在一致；Eclipse 的天空亮度选项。","en_us":"Brightness multiplier for the whole sky radiance; default 1 matches the current look; Eclipse's Sky Brightness."},"slider":true}
#define OMNI_SKY_BRIGHTNESS 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.5 2.0 3.0 4.0 5.0 6.0 10.0]
// @option {"label":{"zh_cn":"天空蓝色红","en_us":"Rayleigh R"},"description":{"zh_cn":"瑞利散射红通道相对当前大气的倍率，越大天空越偏红；默认一倍与现在一致。","en_us":"Red-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_R 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"天空蓝色绿","en_us":"Rayleigh G"},"description":{"zh_cn":"瑞利散射绿通道相对当前大气的倍率，越大天空越偏绿；默认一倍与现在一致。","en_us":"Green-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_G 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"天空蓝色蓝","en_us":"Rayleigh B"},"description":{"zh_cn":"瑞利散射蓝通道相对当前大气的倍率，越大天空越蓝；默认一倍与现在一致。","en_us":"Blue-channel multiplier for Rayleigh scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_RAYLEIGH_B 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光红","en_us":"Mie R"},"description":{"zh_cn":"米氏散射红通道相对当前大气的倍率，越大太阳红晕越强；默认一倍与现在一致。","en_us":"Red-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_R 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光绿","en_us":"Mie G"},"description":{"zh_cn":"米氏散射绿通道相对当前大气的倍率，越大太阳绿晕越强；默认一倍与现在一致。","en_us":"Green-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_G 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"太阳白光蓝","en_us":"Mie B"},"description":{"zh_cn":"米氏散射蓝通道相对当前大气的倍率，越大太阳蓝晕越强；默认一倍与现在一致。","en_us":"Blue-channel multiplier for Mie scattering relative to the current atmosphere; default 1 matches the current look."},"slider":true}
#define OMNI_SKY_MIE_B 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0 5.0]
#endif // 选项层结束
