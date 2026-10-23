/*
每日天气的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/weather/dailyweather.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/weather/dailyweather.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WEATHER_DAILYWEATHER_INCLUDED
#define OMNI_EFFECT_WEATHER_DAILYWEATHER_INCLUDED
// @effect {"label":{"zh_cn":"每日天气","en_us":"Daily weather"}}
// @option {"label":{"zh_cn":"表","en_us":"Daily weather table"},"description":{"zh_cn":"按游戏日轮换取当天的云量与雾密度；默认关闭，关闭时画面与原来一致。","en_us":"Rotates cloud coverage and fog density by in-game day; off by default, so the default look is unchanged."}}
#define OMNI_DAILY_WEATHER 0 // [0 1]
// @option {"label":{"zh_cn":"随机天气","en_us":"Random weather"},"description":{"zh_cn":"每天从十天里随机取一行，而不是按天数顺序取；只在每日天气表开启时生效。","en_us":"Picks a random row of ten each day instead of cycling in order; used only when the table is on."}}
#define OMNI_DAILY_WEATHER_RANDOM 0 // [0 1]
// @option {"label":{"zh_cn":"轮换天数","en_us":"Cycle length"},"description":{"zh_cn":"多少天走完一遍天气表；取十天时和 Eclipse 默认一致，取小则只用前几行。","en_us":"Days to go through the whole table; ten matches Eclipse, smaller uses only the first rows."},"slider":true}
#define OMNI_DAILY_WEATHER_CYCLE 10 // [1 2 3 4 5 6 7 8 9 10]
#endif // 选项层结束
