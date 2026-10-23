/*
雪暴与沙暴的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/weather/storm.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/weather/storm.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WEATHER_STORM_INCLUDED
#define OMNI_EFFECT_WEATHER_STORM_INCLUDED
// @effect {"label":{"zh_cn":"雪暴与沙暴","en_us":"Snow & sand storms"}}
// @option {"label":{"zh_cn":"雪暴","en_us":"Snowstorm"},"description":{"zh_cn":"下雪群系下雪时刮起暴风雪，空气被雪雾填满、能见度骤降；默认关闭，开启后画面变化明显。","en_us":"A blizzard floods the air with snow haze in snowy biomes while it snows; off by default."}}
#define OMNI_SNOW_STORM 0 // [0 1]
// @option {"label":{"zh_cn":"沙暴","en_us":"Sandstorm"},"description":{"zh_cn":"干旱群系在雷暴时刮起沙尘暴，空气被沙尘填满；默认关闭，开启后画面变化明显。","en_us":"A sandstorm floods the air with dust in dry biomes during thunderstorms; off by default."}}
#define OMNI_SAND_STORM 0 // [0 1]
// @option {"label":{"zh_cn":"暴风浓度","en_us":"Storm density"},"description":{"zh_cn":"暴风额外浓雾的浓度，越大雾越厚、能见度越低；只在雪暴或沙暴开启时生效。","en_us":"Density of the extra storm fog; larger is thicker and less visible; used only when a storm is on."},"slider":true}
#define OMNI_STORM_DENSITY 0.1 // [0.0 0.02 0.05 0.08 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"暴风雾起始高度","en_us":"Storm fog start height"},"description":{"zh_cn":"雪暴雾开始随高度变淡的基准高度，照 Eclipse 的雾起始高度；沙暴不看高度。","en_us":"Base height where snowstorm fog starts thinning with altitude, matching Eclipse; sandstorms ignore height."},"slider":true}
#define OMNI_STORM_HEIGHT 60.0 // [0.0 10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0 100.0 120.0 150.0 200.0]
#endif // 选项层结束
