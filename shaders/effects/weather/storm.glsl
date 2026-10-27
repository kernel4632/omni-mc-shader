/*
效果文件 `effects/weather/storm.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/weather/storm.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
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

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
雪暴与沙暴：暴风雪与沙尘暴天气下，把空气填成一层浓厚、随风滚动的雾，再给雾染上雪白或沙黄。
来源：从 `references/Eclipse/shaders/lib/overworld_fog.glsl` 的 `cloudVol`（第 16 到 52 行）与
  `lib/climate_settings.glsl` 的 `BiomeVLFogColors`（第 151 到 165 行）搬运；起风量对应
  `references/Eclipse/shaders/shaders.properties` 第 695 到 709 行的自定义输入 `snowStorm`、`sandStorm`；
  开关对应 `lib/settings.glsl:276-277` 的 `SNOW_STORMS`、`SAND_STORMS`。
调用位置：`effects/fog/fog.glsl` 的体积雾主体 `VolumetricFog` 在算每一步雾密度时调用 `OmniStormFog`
  叠一层额外浓雾，在最后给雾色与散射色染色时调用 `OmniStormColor`；绘制主体不直接调用本文件。
可复制示例：
  `float snow = OmniSnowStorm();`  `float sand = OmniSandStorm();`
  `density += OmniStormFog(worldPos, snow) * clamp(snow + sand, 0.0, 1.0) * OMNI_STORM_DENSITY;`
  `fogColor *= mix(vec3(1.0), OmniStormColor(snow, sand), clamp(snow + sand, 0.0, 1.0));`
调用前提（由 `effects/fog/fog.glsl` 所在的合成片元程序先声明这些全局量）：
  `rainStrength`、`eyeSnowySmooth`、`eyeNoPrecipitationSmooth` 由 `common/uniforms.glsl` 声明，本文件经 `bind/weather.glsl` 读取；
  `thunderStrength` 由本文件声明（Iris 内建量，Omni 别处没有用到）；
  `frameTimeCounter` 与噪声贴图 `noisetex` 由 `common/uniforms.glsl` 声明。
关键设计原因与取舍：
  一、起风量换用等价输入。Eclipse 用加载器的 `biome_category`（寒冷、沙漠、台地）判断是否起风，
    本项目没有这个分类输入，改用两份现成的平滑标记：`eyeSnowySmooth` 表示“冷群系正在下雪”，
    `eyeNoPrecipitationSmooth` 表示“干热群系（不下雨）”，再乘加载器已经平滑好的降雨强度、雷暴强度。
  二、Eclipse 在自定义输入里还给整场暴风套了一层十五秒进、三十秒出的迟滞。那需要一份跨帧保存的值，
    属于 `rendering/pipeline.properties` 的职责，不在本次改动范围；这里直接用已平滑的强度量，变化更直接。
  三、本项目体积雾来自 iterationT，与 Eclipse 的体积雾模型不同，无法整段照搬 `cloudVol`。这里只把
    Eclipse 那段暴风噪声 `IntenseFogs`（`overworld_fog.glsl:43`）连它的高度梯度原样搬成一层额外密度，
    叠加到本项目体积雾的步进里；雾色染色照 `BiomeVLFogColors` 的沙、雪两组系数。
  四、默认关闭。Eclipse 默认开启且会明显改变画面（能见度骤降），本项目按“默认中性”约定默认关闭，
    开启后才生效，默认画面与 iterationT 一致。
  五、浓雾量级按本项目的体积雾单位调整。Eclipse 的雾密度单位与 iterationT 不同，噪声形状照搬，
    绝对浓度由 `OMNI_STORM_DENSITY` 控制，默认值需在游戏内按实际观感微调。
与同一文件夹其它效果的衔接：
  `effects/weather/weather.glsl` 负责雨丝的倾斜与雨天压暗，`effects/weather/snow.glsl` 负责给露天方块叠雪，
  `effects/weather/season.glsl` 只改植被底色随时间的变化；三者都不产生“空气中的浓雾”，没有功能重叠。
  本文件补的正是这层随暴风出现的空气浓雾，只在体积雾步进里生效，是三者之外独立的一层。
*/


// 加载器输入：`noisetex`、`frameTimeCounter` 与天气标记都由声明和绑定层提供。
#include "/common/uniforms.glsl"
// 降雨与群系标记由绑定层整理，暴风强度只做乘法。
#include "/bind/weather.glsl"
// 共用数学：提供 `clamp`、`exp2`、`floor`、`fract`、`mix`、`texture` 等小工具，重复引入由守卫去重。
#include "/common/math.glsl"
// 暴风噪声与颜色、每日天气哈希的纯计算放在通用库。
#include "/omni-gfx/weather.glsl"
// 每日天气：提供当天的云量与雾密度，逐日轮换；本文件是天气文件夹里已经接进体积雾程序的入口，
// 所以在这里引入它，让每日匀雾能借暴风雾这条通道进入画面，同时让整个模块随雾程序一起编译。
#include "/effects/weather/dailyweather.glsl"

// 雷暴强度：Iris 内建量，Omni 别处没有声明，放在这里；只有沙暴会读它。
uniform float thunderStrength; // 雷暴强度，零到一，沙暴按它起风。

// --- 暴风强度：由群系标记与天气强度相乘得到 ---
// 雪暴强度：所在群系下雪且正在降水的强度（标记由绑定层提供），对应 Eclipse 的 `snowStorm` 自定义输入。
float OmniSnowStorm(){
	#if OMNI_SNOW_STORM // 开关关闭时恒为零，不参与任何计算。
		OmniWeather weather = bind_weather(); // 本帧的天气标记只读一次。
		return weather.snowy * weather.rain; // 下雪群系标记乘降雨强度，两者都已是零到一的平滑值。
	#else
		return 0.0; // 关闭时返回零，函数整体不影响画面。
	#endif
}

// 沙暴强度：干旱群系在雷暴时的强度，对应 Eclipse 在 Iris 下的 `sandStorm` 自定义输入。
float OmniSandStorm(){
	#if OMNI_SAND_STORM // 开关关闭时恒为零，不参与任何计算。
		return bind_weather().noPrecipitation * thunderStrength; // 干热群系标记乘雷暴强度，两者都已是零到一的平滑值。
	#else
		return 0.0; // 关闭时返回零，函数整体不影响画面。
	#endif
}

// --- 每日匀雾：把每日天气表里当天的匀雾密度取出来 ---
// 为什么放在这里：本函数与暴风雾同属体积雾的密度来源，放同一处便于对照 Eclipse 的雾密度合成顺序。
// 云量部分由 `effects/cloud/cloud.glsl` 另行接入，本文件只负责雾这一项。
// 说明：Eclipse 的匀雾密度多数日子取零，所以这项对画面的改变通常很小。
float OmniDailyWeatherFog(){
	#if OMNI_DAILY_WEATHER // 每日天气关闭时恒为零，不改变暴风雾。
		return omniWeatherFog().x; // 当天匀雾密度，`x` 是匀雾、`y` 是云雾。
	#else
		return 0.0; // 关闭时返回零。
	#endif
}

#if OMNI_SNOW_STORM || OMNI_SAND_STORM // 只有至少开启一种暴风时才编译噪声与浓度函数，默认完全不增加代码。
// --- 暴风噪声取值 ---
// 照 Eclipse `lib/overworld_fog.glsl:3-13` 的 `densityAtPosFog` 一比一搬运。
// 为什么先除以十八再把横向缩一半：这是 Eclipse 的噪声格子尺度，直接照搬保证雾团大小一致。
float OmniStormNoise(vec3 position){
	return ogxStormNoise(position, noisetex, 512.0); // 噪声公式在通用库，贴图边长照原程序。
}

// --- 暴风浓雾：照 Eclipse `lib/overworld_fog.glsl:42-47` 搬运 ---
// 返回额外密度，调用方再乘总强度与浓度选项叠加到体积雾步进里。
// 参数 `worldPos` 是世界坐标；`snowStorm` 是雪暴强度，沙暴恒为零、充满低空，雪暴才按起始高度向上变淡。
// 为什么分成两项：Eclipse 的暴风同时改两层，噪声层 `IntenseFogs` 制造滚动的雾团，
//   低空层 `low_gradientFog` 被抬满，让整片低空都铺上雾；这里把两项合在一起返回。
float OmniStormFog(vec3 worldPos, float snowStorm){
	vec3 scroll = vec3(frameTimeCounter, 0.0, frameTimeCounter) * 15.0; // 随时间在横纵方向滚动，让雾团像被风吹着走。
	vec3 samplePos = (worldPos * vec3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量，照 Eclipse 的 `samplePos2`。
	float noise = 1.0 - OmniStormNoise(samplePos); // 取反，让噪声高的地方雾更浓。
	float heightFade = exp2(-0.06 * max(worldPos.y - (OMNI_STORM_HEIGHT + 3.0), 0.0)); // 起始高度以上缓慢变淡，照原程序的梯度。
	float denseCloud = noise * noise * mix(1.0, heightFade, snowStorm); // 噪声雾团，照 `IntenseFogs`；雪暴才随高度衰减。
	return 1.0 + denseCloud + OmniDailyWeatherFog(); // 低空层与噪声雾团相加，再叠上当天匀雾密度，三项合起来才是这一天的浓度。
}

// --- 暴风颜色：照 Eclipse `lib/climate_settings.glsl:155-157` 的沙、雪两组系数 ---
// 返回归一化后的雾色乘子，调用方按总强度在单位色与它之间混合。
// 为什么按总强度归一：沙暴与雪暴互斥，任一单独出现时颜色不被另一个的零值拉暗。
vec3 OmniStormColor(float snowStorm, float sandStorm){
	return ogxStormColor(snowStorm, sandStorm); // 加权与归一化在通用库。
}
#endif // 暴风函数开关结束。
#endif // OMNI_EFFECT_WEATHER_STORM_INCLUDED
