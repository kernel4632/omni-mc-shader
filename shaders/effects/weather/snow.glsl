/*
积雪覆盖的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/weather/snow.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/weather/snow.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WEATHER_SNOW_INCLUDED
#define OMNI_EFFECT_WEATHER_SNOW_INCLUDED
// @effect {"label":{"zh_cn":"积雪覆盖","en_us":"Snow cover"}}
// @option {"label":{"zh_cn":"积雪覆盖","en_us":"Snow cover"},"description":{"zh_cn":"下雪时给露天朝上的方块表面叠一层雪；默认关闭，关闭时画面与现在完全一致。","en_us":"Overlays snow on up-facing, sky-exposed block surfaces while it snows; off by default so the default look is unchanged."}}
//#define OMNI_SNOW_OVERLAY
// @option {"label":{"zh_cn":"积雪强度","en_us":"Snow strength"},"description":{"zh_cn":"雪的覆盖厚度与亮度，值越大雪越厚越白；默认照 Eclipse。","en_us":"Thickness and brightness of the snow; larger is thicker and whiter; default matches Eclipse."},"slider":true}
#define OMNI_SNOW_OVERLAY_STRENGTH 1.0 // [0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
#endif // 选项层结束
