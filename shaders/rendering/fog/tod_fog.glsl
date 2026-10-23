/*
时段雾与每日天气雾：把体积雾的密度按主世界一天时间与当天天气缩放。
来源：Eclipse `lib/climate_settings.glsl:172-201` 的 `FogDensities`。
职责：只提供 `FogDensityScale`，按当前雾类型（仅高度衰减或团雾）给出一个密度标度。
调用位置：`effects/fog/volumetric.glsl` 的 `VolumetricFog` 在步进前调用一次，得到这一帧的密度标度；
  暴风时本函数退回固定密度，把雾让给 `effects/weather/storm.glsl` 的暴风通道，避免同一项叠加两次。
可复制示例：`float scale = FogDensityScale(stormStrength);`
调用前提：由 `effects/fog/fog.glsl` 引入；选项 `OMNI_VFOG_DENSITY`、`OMNI_TOD_FOG*` 与内部量
  `OMNI_DAILY_WEATHER`、`OMNI_OVERWORLD`、`omniWeatherFog`、`worldTime` 由引入方先行提供，本文件不重复定义。
关键设计原因与取舍：时段雾与每日天气的总开关都默认关闭，关闭时函数只返回固定密度选项，默认画面与原来一致。
*/
#ifndef OMNI_TOD_FOG_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_TOD_FOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 雾密度标度：时段雾与每日天气 ---
// 雾密度标度：来源 Eclipse `lib/climate_settings.glsl:172-201` 的 `FogDensities`。
// 它同时服务两件来源：时段雾按 `worldTime` 把一天切成晨、午、晚、夜四段；
// 每日天气按游戏日取当天的匀雾与云雾密度。两者都用同一个标度乘到体积雾的噪声密度上：
// 匀雾（`x`）乘给“仅高度衰减”雾，云雾（`y`）乘给团雾，对应 Eclipse 的均匀、多云两套密度系数。
// 传入 `stormStrength` 是为了与暴风通道分工：暴风时雾由 `OmniStormFog` 负责，这里退回固定密度，
// 避免同一个每日雾值既被当作标度、又被暴风通道当作加性密度叠两次。
float FogDensityScale(float stormStrength){
	#if OMNI_DAILY_WEATHER // 每日天气开启时用当天雾密度；默认关闭时不产生这段代码。
		#ifdef OMNI_OVERWORLD // 每日天气只属于主世界；下界与末地没有正常昼夜与季节轮换。
			#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减模式取匀雾那一项。
				float dailyScale = omniWeatherFog().x; // 当天匀雾密度。
			#else // 团雾模式取云雾那一项。
				float dailyScale = omniWeatherFog().y; // 当天云雾密度。
			#endif
		#else
			float dailyScale = OMNI_VFOG_DENSITY; // 非主世界退回固定密度选项。
		#endif
		if (stormStrength > 0.0){ // 正在刮暴风时，这层雾交给 `OmniStormFog`，这里不再叠每日雾。
			dailyScale = OMNI_VFOG_DENSITY; // 退回固定密度，避免两项同时生效。
		}
	#else // 每日天气关闭时退回固定密度选项，行为与原来一致。
		float dailyScale = OMNI_VFOG_DENSITY; // 固定密度选项原值。
	#endif

	#if OMNI_TOD_FOG // 时段雾总开关默认关闭，打开后密度才随一天变化。
		#ifdef OMNI_OVERWORLD // 时段雾只属于主世界；下界与末地没有正常昼夜循环。
			float todTime = mod(float(worldTime), 24000.0); // 当天时刻，取一天内的循环。

			float todMorning = clamp((todTime - 22000.0) / 2000.0, 0.0, 1.0) + clamp((2000.0 - todTime) / 2000.0, 0.0, 1.0); // 晨：跨午夜的两段相加。
			float todNoon    = clamp(todTime / 2000.0, 0.0, 1.0) * clamp((12000.0 - todTime) / 2000.0, 0.0, 1.0); // 午：日出后到正午前。
			float todEvening = clamp((todTime - 10000.0) / 2000.0, 0.0, 1.0) * clamp((14000.0 - todTime) / 2000.0, 0.0, 1.0); // 晚：黄昏前后一段。
			float todNight   = clamp((todTime - 13000.0) / 2000.0, 0.0, 1.0) * clamp((23000.0 - todTime) / 2000.0, 0.0, 1.0); // 夜：入夜到深夜一段。

			#if OMNI_VFOG_NOISE_TYPE == 0 // 仅高度衰减的雾取“均匀”一套系数。
				float todDensity = todMorning * OMNI_TOD_FOG_MORNING_UNIFORM + todNoon * OMNI_TOD_FOG_NOON_UNIFORM
				                 + todEvening * OMNI_TOD_FOG_EVENING_UNIFORM + todNight * OMNI_TOD_FOG_NIGHT_UNIFORM; // 四段权重乘各自密度求和。
			#else // 团雾取“多云”一套系数。
				float todDensity = todMorning * OMNI_TOD_FOG_MORNING_CLOUDY + todNoon * OMNI_TOD_FOG_NOON_CLOUDY
				                 + todEvening * OMNI_TOD_FOG_EVENING_CLOUDY + todNight * OMNI_TOD_FOG_NIGHT_CLOUDY; // 同上，换成多云一套。
			#endif

			float todScale = todDensity * OMNI_TOD_FOG_MULT; // 乘总倍率，对应 Eclipse 的 `TOD_Fog_mult`。
			#if OMNI_DAILY_WEATHER // 时段雾与每日天气同时开启：照 Eclipse 的 `max` 取较大者，不叠加。
				return max(dailyScale, todScale); // 两个来源取大值。
			#else
				return todScale; // 只有时段雾时直接返回时段值。
			#endif
		#endif
	#endif
	return dailyScale; // 时段雾关闭或非主世界，返回固定密度或当天雾密度，画面与原来一致。
}
#endif // OMNI_TOD_FOG_INCLUDED 结束。
