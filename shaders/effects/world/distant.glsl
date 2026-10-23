/*
远景附加的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/distant.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/distant.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_DISTANT_INCLUDED
#define OMNI_EFFECT_WORLD_DISTANT_INCLUDED
// @effect {"label":{"zh_cn":"远景附加","en_us":"Distant extras"}}
// @option {"label":{"zh_cn":"远景过绘防护","en_us":"Distant overdraw prevention"},"description":{"zh_cn":"丢弃已被近景区块画好的近距离远景块，减少重复绘制；默认关闭，开启后近处远景不再绘制。","en_us":"Discards distant chunks already covered by near chunks to cut overdraw; off by default."}}
#define OMNI_DH_OVERDRAW_PREVENTION 0 // [0 1]
// @option {"label":{"zh_cn":"过绘防护距离","en_us":"Overdraw distance"},"description":{"zh_cn":"过绘防护的作用半径，单位方块；零表示跟随远景距离。只在开启过绘防护时生效。","en_us":"Radius of overdraw prevention in blocks; 0 follows the view distance. Only used when overdraw prevention is on."},"slider":true}
#define OMNI_DH_OVERDRAW_MAX_DISTANCE 128 // [0 32 48 64 80 96 112 128 144 160 176 192 208 224 240 256]
// @option {"label":{"zh_cn":"噪声远距衰减","en_us":"Noise dropoff"},"description":{"zh_cn":"远景噪声超过该距离后逐渐消失，单位方块；零表示不衰减，噪声整片保留。","en_us":"Distant noise fades out beyond this distance in blocks; 0 keeps the noise everywhere."},"slider":true}
#define OMNI_DH_NOISE_DROPOFF 0 // [0 128 256 512 768 1024 1536 2048 3072 4096 8192]
#endif // 选项层结束
