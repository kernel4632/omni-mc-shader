/*
泛光的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/color/bloom.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/color/bloom.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_COLOR_BLOOM_INCLUDED
#define OMNI_EFFECT_COLOR_BLOOM_INCLUDED
// @effect {"label":{"zh_cn":"泛光","en_us":"Bloom"}}
// @option {"label":{"zh_cn":"开关","en_us":"Bloom"},"description":{"zh_cn":"让亮部产生柔和光晕。","en_us":"Adds a soft glow around bright areas."}}
#define OMNI_BLOOM 1 // [0 1]
// @option {"label":{"zh_cn":"强度","en_us":"Bloom Amount"},"slider":true,"description":{"zh_cn":"光晕混入场景的强度，越大越亮。","en_us":"How strongly the glow is mixed into the scene."}}
#define OMNI_BLOOM_AMOUNT 0.2 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "下界末地泛光增强", "en_us": "Nether End Bloom Boost"}, "slider": true, "description": {"zh_cn": "下界与末地雾中的泛光额外增强量。", "en_us": "Extra bloom boost through Nether and End fog."}}
#define OMNI_NETHER_END_BLOOM_BOOST 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"空气雾散射泛光","en_us":"Volumetric Fog Scattering Bloom"},"description":{"zh_cn":"用体积雾的散射引导泛光，让光柱周围一起发亮。","en_us":"Uses volumetric fog scattering to guide the glow around light shafts."}}
#define OMNI_VFOG_BLOOM 1 // [0 1]
// @option {"label": {"zh_cn": "雾内泛光", "en_us": "Bloomy Fog"}, "slider": true, "description": {"zh_cn": "把光晕往体积雾里按雾的浓淡混进去，让雾看起来柔和、顺带盖住一点噪点；零为关闭、画面不变。来源 Eclipse `lib/settings.glsl:215` 的 `BLOOMY_FOG`（原程序默认零点五）。", "en_us": "Blends the glow into volumetric fog by how thick the fog is, making it look soft and hiding a little noise; zero is off and changes nothing. From Eclipse `BLOOMY_FOG` (upstream default 0.5)."}}
#define OMNI_FOG_BLOOM 0.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 6.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "水下雾内泛光", "en_us": "Underwater Bloomy Fog"}, "slider": true, "description": {"zh_cn": "在水下把光晕按水的浓淡混进去，让浑水里也有柔光；零为关闭、画面不变。来源 Eclipse `lib/settings.glsl:216` 的 `UNDERWATER_BLOOMY_FOG`（原程序默认一）。", "en_us": "Underwater, blends the glow by how murky the water is; zero is off and changes nothing. From Eclipse `UNDERWATER_BLOOMY_FOG` (upstream default 1.0)."}}
#define OMNI_UNDERWATER_FOG_BLOOM 0.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 6.0 10.0 15.0 20.0]
#endif // 选项层结束
