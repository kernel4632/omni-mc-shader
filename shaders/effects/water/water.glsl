/*
水面的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/water/water.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/water/water.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WATER_WATER_INCLUDED
#define OMNI_EFFECT_WATER_WATER_INCLUDED
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"波浪密度","en_us":"Wave scale"},"description":{"zh_cn":"水面波纹的空间频率；调大波纹更密更细。","en_us":"Spatial frequency of the water ripples; larger makes them finer."},"slider":true}
#define OMNI_WAVE_SCALE 0.05 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"波浪高度","en_us":"Wave height"},"description":{"zh_cn":"水面起伏的强度；调大波浪更明显。","en_us":"Strength of the water surface undulation; larger makes waves more visible."},"slider":true}
#define OMNI_WAVE_HEIGHT 1.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"凹凸","en_us":"Water parallax"},"description":{"zh_cn":"按波浪高度偏移水面采样，让波峰看起来真的凸起；关闭后只用法线造形。","en_us":"Offsets water sampling by wave height so crests look raised; off keeps shape from normals only."}}
#define OMNI_WATER_PARALLAX 1 // [0 1]
// @option {"label":{"zh_cn":"水下雾","en_us":"Underwater fog"},"description":{"zh_cn":"在水下或隔着水看远处时叠加雾；关闭后水更通透。","en_us":"Adds fog when underwater or looking through water; off makes the water clearer."}}
#define OMNI_UNDERWATER_FOG
// @option {"label":{"zh_cn":"水雾密度","en_us":"Water fog density"},"description":{"zh_cn":"水下与水后雾的浓度；调大看得更近。","en_us":"Density of underwater and through-water fog; larger reduces visibility."},"slider":true}
#define OMNI_WATER_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"焦散","en_us":"Water caustics"},"description":{"zh_cn":"阳光透过波动水面在水底汇聚出的亮纹。","en_us":"Bright patterns where sunlight focuses through the rippling water onto the bottom."}}
#define OMNI_CAUSTICS
// @option {"label":{"zh_cn":"水洼与涟漪范围","en_us":"Puddles & ripples"},"description":{"zh_cn":"雨点涟漪出现的位置：整个湿表面均匀铺满，还是只在低洼积水处出现。「仅水洼」还会按「水洼尺寸」决定水洼范围，并让水洼表面更光滑更暗（照 Eclipse 的 `applyPuddles`）。默认与原来一致。来源 Eclipse `lib/settings.glsl:359` 的 `PUDDLE_MODE`。","en_us":"Where rain ripples appear: evenly over the whole wet surface, or only in low-lying puddles. \"Only puddles\" also uses \"Puddle size\" to shape the puddles and makes their surface smoother and darker (Eclipse's applyPuddles). Default matches the previous behaviour. From Eclipse `lib/settings.glsl:359` `PUDDLE_MODE`."},"values":{"0":{"zh_cn":"无雨点","en_us":"Off"},"1":{"zh_cn":"水洼与全湿润","en_us":"Puddles + fully wet"},"2":{"zh_cn":"仅水洼","en_us":"Only puddles"},"3":{"zh_cn":"仅全湿润","en_us":"Only fully wet"}}}
#define OMNI_PUDDLE_MODE 1 // [0 1 2 3]
// @option {"label":{"zh_cn":"雨点涟漪强度","en_us":"Rain ripple strength"},"description":{"zh_cn":"雨点砸在水面与地面时涟漪的起伏高低，一为不变；调大涟漪更明显，取零等于不画雨点。","en_us":"Height of the ripples where raindrops hit water and ground, one is unchanged; larger makes them stronger, zero draws none."},"slider":true}
#define OMNI_RAIN_RIPPLE_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"雨点涟漪对比","en_us":"Rain ripple contrast"},"description":{"zh_cn":"雨点涟漪的明暗分离程度，一为不变；调大亮圈更锐、圈外更平，调小则整片更柔和。","en_us":"How sharply the ripple rings separate from the flat surface, one is unchanged; larger makes the rings crisper and the rest flatter, smaller makes everything softer."},"slider":true}
#define OMNI_RAIN_RIPPLE_CONTRAST 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.75 2.0 2.5 3.0]
// @option {"label":{"zh_cn":"玩家交互水面","en_us":"Player water interaction"},"description":{"zh_cn":"玩家在水里移动时，水面从玩家处向外推出一圈圈涟漪。默认关闭；Eclipse 默认用波浪模拟，本项目未移植那套计算着色器方案。来源 Eclipse `dimensions/all_translucent.fsh` 的 `WATER_INTERACTION == 1`。","en_us":"Ripples spread out from the player across the water surface while moving in water. Off by default; Eclipse defaults to its wave-simulation mode, whose compute-shader pipeline is not ported here. From Eclipse `dimensions/all_translucent.fsh` `WATER_INTERACTION == 1`."},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"简单涟漪","en_us":"Simple ripples"}}}
#define OMNI_PLAYER_WATER 0 // [0 1]
// @option {"label":{"zh_cn":"玩家涟漪强度","en_us":"Player ripple strength"},"description":{"zh_cn":"玩家水波涟漪的高低；调大涟漪更明显。上一个选项关闭时不生效。","en_us":"Height of the player water ripples; larger makes them more visible. Has no effect while the option above is off."},"slider":true}
#define OMNI_PLAYER_WATER_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#endif // 选项层结束
