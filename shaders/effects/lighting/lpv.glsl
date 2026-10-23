/*
光传播体积的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lighting/lpv.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lighting/lpv.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LIGHTING_LPV_INCLUDED
#define OMNI_EFFECT_LIGHTING_LPV_INCLUDED
// @effect {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"}}
// @option {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"},"description":{"zh_cn":"在相机周围的三维格子里让彩色方块光扩散，再混回表面；缺计算能力或自定义图像时退回屏幕空间间接光。","en_us":"Diffuses colored block light in a grid around the camera and blends it into surfaces; falls back to screen space without compute or custom images."}}
#define OMNI_LPV_ENABLED 0 // [0 1]
// @option {"label":{"zh_cn":"体积大小","en_us":"Volume size"},"description":{"zh_cn":"体积格每边的方块数，越大覆盖越广、占用显存越多。","en_us":"Blocks per side of the volume; larger covers more and uses more VRAM."},"values":{"6":{"zh_cn":"小","en_us":"Small"},"7":{"zh_cn":"中","en_us":"Medium"},"8":{"zh_cn":"大","en_us":"Large"}}}
#define OMNI_LPV_SIZE 7 // [6 7 8]
// @option {"label":{"zh_cn":"光饱和度","en_us":"Light saturation"},"slider":true,"description":{"zh_cn":"传播中的颜色有多鲜艳，一百为原色。","en_us":"How vivid the propagated colors are; 100 keeps the source color."}}
#define OMNI_LPV_SATURATION 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// @option {"label":{"zh_cn":"透光染色","en_us":"Tint saturation"},"slider":true,"description":{"zh_cn":"玻璃等半透明方块给穿过的光染色的强度，一百为原色。","en_us":"How strongly translucent blocks tint light passing through; 100 keeps the source color."}}
#define OMNI_LPV_TINT_SATURATION 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// @option {"label":{"zh_cn":"法线偏移","en_us":"Normal offset"},"slider":true,"description":{"zh_cn":"表面法线让取样点沿法线偏移的程度，减少贴面漏光，零为关闭。","en_us":"How far the sample point moves along the surface normal; zero disables it."}}
#define OMNI_LPV_NORMAL_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// @option {"label":{"zh_cn":"红石光源","en_us":"Redstone lights"},"description":{"zh_cn":"让红石线、红石火把贡献彩色光。","en_us":"Lets redstone wire and torches contribute colored light."}}
#define OMNI_LPV_REDSTONE_LIGHTS
// @option {"label":{"zh_cn":"体积光强度","en_us":"LPV strength"},"slider":true,"description":{"zh_cn":"体积光混回表面的比例，一为原样。","en_us":"How much of the volume light is blended into surfaces; one is neutral."}}
#define OMNI_LPV_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"彩色蜡烛","en_us":"Colored candles"},"description":{"zh_cn":"让点亮的彩色蜡烛按自身颜色在体积光里发光；默认关闭，打开后蜡烛周围会带上对应颜色。","en_us":"Lets lit colored candles emit light in their own colour into the volume; off by default."}}
//#define OMNI_LPV_COLORED_CANDLES
// @option {"label":{"zh_cn":"实体光源","en_us":"Entity lights"},"description":{"zh_cn":"让烈焰人、发光鱿鱼、岩浆怪、点燃的炸药、末地水晶与光灵箭，以及信标、潮涌核心、附魔台、酿造台这些发光方块实体，还有掉在地上的火把、荧石等发光物品，在体积光里发光；只在体积光开启时生效，默认开、等于 Eclipse。","en_us":"Lets blazes, glow squid, magma cubes, primed TNT, end crystals and spectral arrows, glowing block entities (beacon, conduit, enchanting table, brewing stand) and dropped glowing items (torches, glowstone) add light to the volume; only used when the volume is on; on by default to match Eclipse."}}
#define OMNI_LPV_ENTITY_LIGHTS
// @option {"label":{"zh_cn":"雾照明","en_us":"Fog illumination"},"description":{"zh_cn":"让体积里的彩色光照亮周围的空气，洞穴里能看到带颜色的光晕；默认关闭，开启后雾会带上颜色。","en_us":"Lets the volume's colored light illuminate the surrounding air so caves show colored glow; off by default."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION 0 // [0 1]
// @option {"label":{"zh_cn":"雾照明亮度","en_us":"Fog illumination brightness"},"description":{"zh_cn":"被照亮的雾的亮度，一百为基准；只在雾照明开启时生效。","en_us":"Brightness of the lit fog, 100 is the baseline; only used when Fog illumination is on."},"slider":true}
#define OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 130 140 150 160 180 200 250 300]
// @option {"label":{"zh_cn":"雾照明-手持光","en_us":"Fog illumination - handheld"},"description":{"zh_cn":"让手里的火把、荧石等手持光源也照亮空气，光色取自手持物品；只在雾照明开启时生效，默认关闭、等于 Eclipse。","en_us":"Lets held light sources such as a torch or glowstone also light up the air, using the held item's own colour; only used when Fog illumination is on; off by default to match Eclipse."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD 0 // [0 1]
// @option {"label":{"zh_cn":"雾照明-水下手持光","en_us":"Fog illumination - water handheld"},"description":{"zh_cn":"在水下让手持光源照亮水体，靠近火把的水先亮暖色、远处只剩青蓝；只在雾照明开启时生效，默认开、等于 Eclipse。","en_us":"Underwater, lets held light sources light up the water, warm near the torch and blue-green farther out; only used when Fog illumination is on; on by default to match Eclipse."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
#endif // 选项层结束
