/*
每日天气：按游戏日从一张天气表里取当天的云量与雾密度，让天气随天数轮换，而不是每天一个样。
来源：Eclipse `lib/settings.glsl:585-698` 的 `Daily_Weather` 表，选取逻辑照 `dimensions/begin.csh:242-300`；
  十天一循环的默认数值与随机取档的 `hash11` 都从原程序一比一搬运。
职责：
  一、选项：`OMNI_DAILY_WEATHER`、`OMNI_DAILY_WEATHER_RANDOM`、`OMNI_DAILY_WEATHER_CYCLE`，只在本文件定义一次；
  二、天气表：十天为一行，每天四层云的覆盖度与密度，加两项雾密度，数值照 Eclipse 默认；
  三、选取：按 `worldDay` 取当天那一行，或按哈希在十天里随机取一行。
调用位置：本文件对外只暴露一组取值函数，由绘制主体按需调用；
  云量：`effects/cloud/volumetric.glsl` 的基础体积云读 `l0`/`l1`、高层云读 `l2`、卷云读 `l3`，用当天值替换默认云量；
  平面云与积雨云不受本表影响：Eclipse 的每日天气表只有四层体积云，平面云是 iterationT 独有的层，
  积雨云在 Eclipse 里由雷暴强度 `thunderStrength` 与固定密度驱动，两处都没有接每日天气的来源；
  雾：`effects/fog/fog.glsl` 的 `FogDensityScale` 读 `omniWeatherFog`，把当天匀雾与云雾密度接进体积雾密度标度；
  `effects/weather/storm.glsl` 也引入它，只用当天匀雾补暴风雾；暴风时段体积雾密度标度会让位，避免同一项叠加两次。
可复制示例：
  `OmniWeatherDay day = omniWeatherDay();`     一次取齐当天的覆盖度、密度与雾；
  `vec4 cover = omniWeatherCoverage();`        只取四层覆盖度，顺序是 `l0` 到 `l3`；
  `vec2 fog = omniWeatherFog();`               只取两项雾密度，`x` 匀雾、`y` 云雾。
调用前提：世界天数 `worldDay` 由 `common/uniforms.glsl` 声明，本文件已引入，调用方无需重复声明。
关键设计原因与取舍：
  一、默认关闭。Eclipse 的 `Daily_Weather` 默认也关闭，关闭时本文件不产生任何代码，画面与原来一致。
  二、表用常量数组，不用上百个选项。Eclipse 把十天十项拆成一百个 `#define`，菜单会变成一堵选项墙；
     这里改成十天各一行的常量数组，只留三个开关型选项，数值仍照搬 Eclipse 默认，便于维护与逐行对照。
  三、不跨帧平滑。Eclipse 把选出的值存进场景控制器缓冲并逐帧插值；本项目没有这套缓冲，
     这里每个游戏日直接取当天一行，只在换日那一刻瞬间切换，其余时间稳定。
  四、覆盖范围与 Eclipse 一致。Eclipse 的每日天气表只驱动四层体积云（小积云、大积云、高层云、卷云），
     本项目据此只接进基础体积云、高层云与卷云；平面云是 iterationT 独有的层，积雨云在 Eclipse 里由雷暴驱动，
     两者都不接每日天气，避免在没有对照来源的情况下凭空编一层。
与同文件夹其它效果的衔接：
  季节 `effects/weather/season.glsl` 管一年尺度的植被换色，本文件管一天尺度的云与雾，两者都按 `worldDay` 走但不互相覆盖；
  雪暴与沙暴 `effects/weather/storm.glsl` 是单独的开关型天气，本文件为它提供当天的匀雾密度，也为云与体积雾提供当天数值；
  雨雪 `effects/weather/weather.glsl` 读加载器给出的降雨强度，本文件不改降雨强度，只给云量与雾密度。
*/
#ifndef OMNI_DAILY_WEATHER_INCLUDED // 只引入一次，避免选项与数组重复定义。
#define OMNI_DAILY_WEATHER_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"每日天气","en_us":"Daily weather"}}
// @option {"label":{"zh_cn":"表","en_us":"Daily weather table"},"description":{"zh_cn":"按游戏日轮换取当天的云量与雾密度；默认关闭，关闭时画面与原来一致。","en_us":"Rotates cloud coverage and fog density by in-game day; off by default, so the default look is unchanged."}}
#define OMNI_DAILY_WEATHER 0 // [0 1]
// @option {"label":{"zh_cn":"随机天气","en_us":"Random weather"},"description":{"zh_cn":"每天从十天里随机取一行，而不是按天数顺序取；只在每日天气表开启时生效。","en_us":"Picks a random row of ten each day instead of cycling in order; used only when the table is on."}}
#define OMNI_DAILY_WEATHER_RANDOM 0 // [0 1]
// @option {"label":{"zh_cn":"轮换天数","en_us":"Cycle length"},"description":{"zh_cn":"多少天走完一遍天气表；取十天时和 Eclipse 默认一致，取小则只用前几行。","en_us":"Days to go through the whole table; ten matches Eclipse, smaller uses only the first rows."},"slider":true}
#define OMNI_DAILY_WEATHER_CYCLE 10 // [1 2 3 4 5 6 7 8 9 10]

// 加载器输入：世界天数 `worldDay` 与其余公共输入都在这里声明。
#include "/common/uniforms.glsl"
// 共用数学：提供 `fract`、`mod`、`clamp` 等小工具，重复引入由守卫去重。
#include "/common/math.glsl"

#if OMNI_DAILY_WEATHER // 关闭时下面整段不参与编译，默认画面与原来一致。

// --- 哈希：把整数天数打散成零到一的小数 ---
// 照 Eclipse `dimensions/begin.csh:29-35` 的 `hash11` 一比一搬运，用于随机取档。
// 为什么不用正弦哈希：原程序用这套乘加打散，逐位浮点结果与它一致，便于逐行对照。
float omniWeatherHash(float p){
	p = fract(p * 0.1031); // 先乘一个无理近似再取小数，打散相邻整数。
	p *= p + 33.33; // 加偏移后再平方，让输入的小变化放大。
	p *= p + p; // 再乘自身的两倍，进一步拉开分布。
	return fract(p); // 取小数，得到零到一的哈希值。
}

// --- 天气表：十天，每天四层云与两项雾 ---
// 为什么一天一行：某一天的全部数值在同一行，改一天只看一行，不必在几个数组之间来回找。
// 覆盖度与密度的四列顺序是 `l0` 小积云、`l1` 大积云、`l2` 高层云、`l3` 卷云，数值照 Eclipse 的 `DAY0..DAY9_lX`。
const vec4 OMNI_WEATHER_COVERAGE[10] = vec4[](
	vec4(0.7, 0.7, 0.1, 0.1), // 第零天：小积云与大积云都多，天空偏阴。
	vec4(0.7, 1.2, 1.0, 0.06), // 第一天：大积云与高层云铺满，云层最厚。
	vec4(0.55, 0.0, 0.0, 0.175), // 第二天：只有小积云与一点卷云，天空偏晴。
	vec4(0.8, 1.0, 0.0, 0.07), // 第三天：小积云与大积云并存，无高层云。
	vec4(0.0, 0.0, 0.6, 0.08), // 第四天：只有高层云与薄卷云，低空干净。
	vec4(0.8, 0.0, 0.65, 0.1), // 第五天：小积云加高层云，中等云量。
	vec4(0.0, 1.3, 0.5, 0.1), // 第六天：大积云极多，天空大面积被遮。
	vec4(0.0, 0.0, 0.0, 0.34), // 第七天：只有卷云，天空最通透。
	vec4(0.6, 0.7, 0.3, 0.01), // 第八天：低中高都有，云量中等偏多。
	vec4(1.0, 0.0, 1.0, 0.1) // 第九天：小积云与高层云都满，阴天。
);

const vec4 OMNI_WEATHER_DENSITY[10] = vec4[](
	vec4(0.5, 0.5, 0.1, 0.1), // 第零天：低云中等消光，高层云很薄。
	vec4(0.5, 1.5, 0.0, 0.0), // 第一天：大积云消光最高，另两层近乎透明。
	vec4(0.4, 0.0, 0.0, 0.2), // 第二天：小积云偏薄，卷云略厚。
	vec4(0.7, 0.7, 0.0, 0.04), // 第三天：两层低云都较厚。
	vec4(0.0, 0.0, 1.0, 0.05), // 第四天：高层云最厚，低空无云。
	vec4(0.5, 0.0, 0.5, 0.0), // 第五天：小积云与高层云都中等。
	vec4(0.0, 1.0, 0.02, 0.0), // 第六天：大积云厚，高层云几乎不存在。
	vec4(0.0, 0.0, 0.0, 0.11), // 第七天：只有薄卷云。
	vec4(1.0, 0.5, 1.0, 0.03), // 第八天：小积云与高层云都最厚。
	vec4(1.0, 0.0, 0.1, 0.03) // 第九天：小积云满、高层云稀薄。
);

// 雾密度两列：`x` 是匀雾密度，`y` 是云雾密度，数值照 Eclipse 的 `DAY0..DAY9_ufog/cfog`。
const vec2 OMNI_WEATHER_FOG[10] = vec2[](
	vec2(0.0, 0.0), // 第零天：无雾。
	vec2(0.01, 0.1), // 第一天：一点匀雾加少量云雾。
	vec2(0.0, 0.0), // 第二天：无雾。
	vec2(0.0, 0.0), // 第三天：无雾。
	vec2(0.0, 0.0), // 第四天：无雾。
	vec2(0.0, 0.0), // 第五天：无雾。
	vec2(0.0, 0.0), // 第六天：无雾。
	vec2(0.0, 0.0), // 第七天：无雾。
	vec2(0.0, 0.0), // 第八天：无雾。
	vec2(0.0, 1.0) // 第九天：云雾最浓，天空同一片阴云。
);

// --- 取档：算出当天应该用天气表的哪一行 ---
// 返回零到九的行号，供表取值；`worldDay` 从加载器来，跨天自增。
int omniWeatherDayIndex(){
	#if OMNI_DAILY_WEATHER_RANDOM // 随机模式：用哈希在十天里跳着取。
		return int(clamp(omniWeatherHash(float(mod(worldDay, 1000))) * 10.0, 0.0, 9.0)); // 先压缩天数范围再哈希取整，结果落在十天之内。
	#else // 顺序模式：按天数对轮换周期取余。
		return int(mod(worldDay, OMNI_DAILY_WEATHER_CYCLE)); // 走完一遍从头开始。
	#endif
}

// 当天天气：把这一天的覆盖度、密度与雾一次取齐，交给调用方按需使用。
struct OmniWeatherDay {
	vec4 coverage; // 四层云覆盖度，顺序是 `l0` 到 `l3`。
	vec4 density; // 四层云消光密度，顺序同上。
	vec2 fog; // 两项雾密度：`x` 匀雾、`y` 云雾。
};

// 取当天天气：按 `omniWeatherDayIndex` 选出的行，从三张表里各取一份。
// 为什么返回结构而不是三个函数：一次取齐就不会在调用处重复算行号，也少一次哈希。
OmniWeatherDay omniWeatherDay(){
	int day = omniWeatherDayIndex(); // 当天行号。
	OmniWeatherDay result; // 待填的当日天气。
	result.coverage = OMNI_WEATHER_COVERAGE[day]; // 取当天覆盖度。
	result.density = OMNI_WEATHER_DENSITY[day]; // 取当天密度。
	result.fog = OMNI_WEATHER_FOG[day]; // 取当天雾密度。
	return result; // 交回调用方。
}

// 单取覆盖度：只要四层云覆盖度时省去结构定义。
vec4 omniWeatherCoverage(){
	return omniWeatherDay().coverage; // 由当日天气里取出覆盖度。
}

// 单取密度：只要四层云密度时省去结构定义。
vec4 omniWeatherDensity(){
	return omniWeatherDay().density; // 由当日天气里取出密度。
}

// 单取雾密度：只要雾时省去结构定义，`x` 匀雾、`y` 云雾。
vec2 omniWeatherFog(){
	return omniWeatherDay().fog; // 由当日天气里取出两项雾密度。
}

#endif // 每日天气开关结束。
#endif // 文件守卫结束。
