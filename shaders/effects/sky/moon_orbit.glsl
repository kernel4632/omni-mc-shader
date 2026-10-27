/*
效果文件 `effects/sky/moon_orbit.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/moon_orbit.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_SKY_MOON_ORBIT_INCLUDED
#define OMNI_SKY_MOON_ORBIT_INCLUDED
/*
月亮轨道、月食与月相：来源 Eclipse，把月亮从永远在太阳对面解耦成独立轨道，才可能出现月相、月食与真实月亮。
调用位置：由 `effects/sky/sky.glsl` 引入；`CalculateWorldMoonVector` 在顶点阶段（`rendering/lights.glsl`）算出月亮方向，
    `CalculateMoonPhaseBrightness`、`CalculateEclipseDarkening`、`CalculateMoonDiscColor` 在延迟三号与光照里使用。
可复制示例：
    `vec3 moonDir = CalculateWorldMoonVector(worldSunVector);`
    `float phase = CalculateMoonPhaseBrightness(worldSunVector, worldMoonVector);`
设计原因与取舍：默认不改变画面——自定义轨道、月相亮度、真实月亮都默认关闭，月食默认开启但默认轨道下日月相对、永不接近。
    轨道数学照 Eclipse `dimensions/begin.csh:73-95` 的 `moonDirection` 逐行移植，纯公式在 `shaders/gfx/atmosphere.glsl`；
    平滑时间由加载器按 `pipeline.properties` 每帧算好。
*/
// --- 月亮轨道、月食与月相 ---
// 月亮轨道的内部常数照 Eclipse `lib/settings.glsl:411-413`，本项目不把它们开放成玩家选项。
#define MONTH_LENGTH 8 // 一个月多少游戏日，月亮绕一圈比一天略长，所以每天相对太阳移动一点。
#define EARTH_ROTATION_TILT 14.0 // 月亮轨道随季节摆动的最大赤纬偏移，单位度。
uniform float omniMoonTimeSmooth; // 平滑后的累计世界时间，由加载器按 `pipeline.properties` 每帧算好。世界天数 `worldDay` 由 `common/uniforms.glsl` 统一声明。
// 月亮轨道公式放在通用库，这里只传时间、纬度与倾角。
#include "/omni-gfx/atmosphere.glsl"
// 把时间换算成月亮的世界方向：纬度决定升起高度，倾角决定赤纬，时间决定时角。
vec3 MoonDirection(float time, float latitude, float pathRotation){
	return ogxMoonDirection(time, latitude, pathRotation, float(MONTH_LENGTH)); // 转发到通用库，月份长度按本文件常数。
}
// 由世界时间闭式算出月亮方向：开启自定义轨道时月亮独立运行，关闭时月亮仍与太阳相对。
// 这是顶点阶段的一项纯计算，不读取任何中间画面，因此各程序算出的方向完全一致。
vec3 CalculateWorldMoonVector(vec3 worldSunVector){
	#ifdef OMNI_CUSTOM_MOON_ROTATION
		#ifdef OMNI_SMOOTH_MOON_ROTATION
			float totalTime = omniMoonTimeSmooth; // 平滑后的累计世界时间，月亮移动不跳格。
		#else
			float totalTime = float(worldDay) * 24000.0 + float(worldTime); // 未平滑时按整数刻累计。
		#endif
		float absWorldTime = totalTime - 48000.0; // 偏移两天，与 Eclipse 的相位对齐。
		float yearLengthTicks = float(MONTH_LENGTH) * 12.0 * 24000.0; // 一年对应的刻数。
		float timeInYear = mod(absWorldTime, yearLengthTicks) / yearLengthTicks; // 落在一年内的相位。
		float moonOffset = 2.0 * EARTH_ROTATION_TILT * smoothstep(0.0, 0.5, timeInYear) * (1.0 - smoothstep(0.5, 1.0, timeInYear)) - EARTH_ROTATION_TILT; // 随季节摆动的赤纬；Eclipse 用反向 `smoothstep`，这里改成等价的单向写法，避免未定义行为。
		return normalize(MoonDirection(absWorldTime - OMNI_MOON_TIME_OFFSET, OMNI_MOON_LATITUDE, moonOffset)); // 换算成单位方向。
	#else
		return -worldSunVector; // 关闭时月亮与太阳相对，与移植前完全一致。
	#endif
}
// 月相亮度：由太阳与月亮方向的夹角算被照亮比例，满月为一、新月为零；关闭时返回一，不改变画面。
// 为什么用夹角而不是游戏自带的月相编号：自定义轨道下月亮位置与世界时间解耦，只有几何夹角才是真实的相位。
float CalculateMoonPhaseBrightness(vec3 worldSunVector, vec3 worldMoonVector){
	#ifdef OMNI_MOONPHASE_BASED_MOONLIGHT
		return saturate((1.0 - dot(worldSunVector, worldMoonVector)) * 0.5); // 方向相反是满月，方向相同是新月。
	#else
		return 1.0; // 不改变月光与月盘亮度。
	#endif
}
// 月食变暗：日月方向接近时把天空压暗，来源 Eclipse `lib/ROBOBO_sky.glsl:130-133`。
// 为什么按视线高度过渡：地平线以下看不到天体，不必压暗，只压地平线以上的那一侧。
float CalculateEclipseDarkening(vec3 worldDir, vec3 worldSunVector, vec3 worldMoonVector){
	#ifdef OMNI_ECLIPSE
		float eclipseDarkness = smoothstep(0.005, 0.08, length(worldSunVector - worldMoonVector)); // 日月越近越小，对齐时接近零。
		eclipseDarkness = mix(1.0, eclipseDarkness, smoothstep(-1.0, 0.175, worldDir.y)); // 只压地平线以上的天空。
		return mix(1.0, eclipseDarkness, OMNI_ECLIPSE_DARKENING); // 按选项强度在不变暗与全暗之间插值。
	#else
		return 1.0; // 关闭月食变暗时不改变天空。
	#endif
}
// 月亮圆盘颜色：真实月亮模式按色温与亮度基准，否则用现有的偏暖白。
// 最后再乘 Eclipse `moonColorR/G/B` 的三通道倍率，默认全一、不改变基础色。
vec3 CalculateMoonDiscColor(){
	vec3 moonColor; // 月亮圆盘的基础颜色。
	#ifdef OMNI_REALMOON
		moonColor = Blackbody(OMNI_MOON_TEMP) * (OMNI_MOON_ILLUMINANCE / 600.0); // 黑体颜色亮度已归一，再按亮度基准相对默认值缩放。
	#else
		moonColor = vec3(0.8886, 1.0019, 1.3095); // 现有的偏暖白月亮圆盘。
	#endif
	return moonColor * vec3(OMNI_MOON_COLOR_R, OMNI_MOON_COLOR_G, OMNI_MOON_COLOR_B); // 补上 Eclipse 的三通道倍率，默认全一。
}
#endif // OMNI_SKY_MOON_ORBIT_INCLUDED
