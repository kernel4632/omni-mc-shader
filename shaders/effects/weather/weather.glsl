/*
天气的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/weather/weather.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/weather/weather.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WEATHER_WEATHER_INCLUDED
#define OMNI_EFFECT_WEATHER_WEATHER_INCLUDED
// @effect {"label":{"zh_cn":"天气","en_us":"Weather"}}
// @option {"label":{"zh_cn":"雨可见度","en_us":"Rain visibility"},"description":{"zh_cn":"雨丝与雨中画面的强度；取零等于几乎看不到雨。","en_us":"Strength of rain streaks and the rainy look; zero makes rain almost invisible."},"slider":true}
#define OMNI_RAIN_VISIBILITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 5.0]
// @option {"label":{"zh_cn":"雨的扰动强度","en_us":"Rain disturbance"},"description":{"zh_cn":"雨雪下落时左右摆动的幅度；调大雨丝摆动更明显。","en_us":"How much rain and snow sway while falling; larger makes the streak wobble more."},"slider":true}
#define OMNI_RAIN_DISTURBANCE 0.05 // [0.0 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2]
// @option {"label":{"zh_cn":"雨的横向风","en_us":"Rain wind (X)"},"description":{"zh_cn":"雨雪沿东西方向的倾斜，正东负西；取零竖直下落。","en_us":"Lean of rain and snow along the east-west axis, positive east; zero falls straight."},"slider":true}
#define OMNI_RAIN_WIND_X 0.1 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.175 -0.15 -0.125 -0.1 -0.075 -0.05 -0.025 0.0 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"雨的纵向风","en_us":"Rain wind (Z)"},"description":{"zh_cn":"雨雪沿南北方向的倾斜，正南负北；取零竖直下落。","en_us":"Lean of rain and snow along the north-south axis, positive south; zero falls straight."},"slider":true}
#define OMNI_RAIN_WIND_Z 0.05 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.175 -0.15 -0.125 -0.1 -0.075 -0.05 -0.025 0.0 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"雨点溅射","en_us":"Rain splash"},"description":{"zh_cn":"雨点砸在地面与水面的溅射效果，以及雨天的湿润推进。","en_us":"Splashes where raindrops hit the ground and water, plus how wetness builds up in rain."}}
#define OMNI_RAIN_SPLASH_EFFECT
// @option {"label":{"zh_cn":"关闭局部降水","en_us":"Disable local precipitation"},"description":{"zh_cn":"强制把雨雪当成全局降雨，不受所在群系影响。","en_us":"Forces rain and snow to be treated as global rainfall regardless of the biome."}}
//#define OMNI_DISABLE_LOCAL_PRECIPITATION
// @option {"label":{"zh_cn":"地表基础湿润","en_us":"Surface wetness"},"description":{"zh_cn":"不靠下雨也给地面加一层湿润；取零时地面只在下雨时变湿。","en_us":"Adds a base layer of wetness to surfaces without rain; zero keeps surfaces wet only in the rain."},"slider":true}
#define OMNI_SURFACE_WETNESS 0.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// Iris 原生湿润半衰期常量：下雨后地面变湿所用时间，取字面量供菜单读取。
// @option {"label":{"zh_cn":"变湿半衰期","en_us":"Wetness halflife"},"description":{"zh_cn":"开始下雨后地面变湿所需时间的半衰期，单位秒；Iris 直接读取该原生常量。","en_us":"Halflife in seconds for surfaces to become wet once it starts raining; Iris reads this native constant."},"slider":true}
const float wetnessHalflife = 200.0; // [10.0 20.0 30.0 50.0 75.0 100.0 150.0 200.0 300.0 500.0]
// Iris 原生干燥半衰期常量：停雨后地面变干所用时间，取字面量供菜单读取。
// @option {"label":{"zh_cn":"变干半衰期","en_us":"Dryness halflife"},"description":{"zh_cn":"停雨后地面变干所需时间的半衰期，单位秒；Iris 直接读取该原生常量。","en_us":"Halflife in seconds for surfaces to dry once the rain stops; Iris reads this native constant."},"slider":true}
const float drynessHalflife = 50.0; // [10.0 20.0 30.0 50.0 75.0 100.0 150.0 200.0 300.0 500.0]
#endif // 选项层结束
