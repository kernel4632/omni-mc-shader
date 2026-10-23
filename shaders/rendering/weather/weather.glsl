/*
天气的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/weather/weather.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_WEATHER_WEATHER_INCLUDED
#define OMNI_RENDER_WEATHER_WEATHER_INCLUDED
#include "/effects/weather/weather.glsl"
/*
天气：把 iterationT 的雨天合成、雨雪几何倾斜与雨遮罩集中到一个文件。
职责分成三块：
  一、选项：`OMNI_RAIN_VISIBILITY`、`OMNI_RAIN_DISTURBANCE`、`OMNI_RAIN_WIND_X`、`OMNI_RAIN_WIND_Z`、
    `OMNI_RAIN_SPLASH_EFFECT`、`OMNI_DISABLE_LOCAL_PRECIPITATION`、`OMNI_SURFACE_WETNESS`，以及 Iris 原生常量
    `wetnessHalflife`、`drynessHalflife`，全项目只在这里定义一次；
  二、`Rain` 在合成阶段按雨遮罩把画面往雨天色混合；
  三、`RainWindOffset` 与 `WeatherRainMask` 把雨雪几何程序的顶点倾斜与片元遮罩计算抽出来，供绘制主体调用。
调用位置：
  `rendering/composite.glsl` 合成阶段在雾之后调用 `Rain`；
  `rendering/overlay.glsl` 的雨雪程序顶点阶段调用 `RainWindOffset`，片元阶段调用 `WeatherRainMask`；
  `effects/water/water.glsl` 的水面与 `effects/ground/material.glsl` 的地表湿润读 `OMNI_SURFACE_WETNESS` 与 `OMNI_DISABLE_LOCAL_PRECIPITATION`。
可复制示例：
  `Rain(color, rainMask);`  合成阶段给整幅画面叠雨色；
  `vec2 offset = RainWindOffset(worldPos); worldPos.xz += offset;`  顶点阶段倾斜雨雪几何；
  `float mask = WeatherRainMask(texel);`  片元阶段取雨遮罩，空白纹素会被丢弃。
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `Rain` 需要合成主程序的 `in vec3 colorShadowlight`、`in vec3 colorSkylight`；
  `RainWindOffset` 需要程序声明 `uniform float eyeBrightnessOneSmooth;`（该值在 `rendering/pipeline.properties` 里由加载器计算）；
  `OMNI_RAIN_SHADOW` 属于 `effects/cloud/cloud.glsl`，调用方需先引入该文件；
  `RainWindOffset` 的相机位置、动画时间与露天标记由 `bind/` 绑定层从加载器输入转换。
关键设计原因与取舍：
  雨雪几何只在顶点阶段水平推移，不引入顶点着色器的复杂运算；晴天不出雨是因为加载器已经不给雨遮罩值，这里不再额外判断；
  雨遮罩写进零号画面的透明通道，读取端靠它判断雨落在画面哪一层，而不是靠世界位置猜。
*/
// 雨雪随风偏移放在通用库，这里只传入相机、时间与选项。
#include "/gfx/weather.glsl"
// 宿主输入统一由绑定层整理：时间、相机位置与露天标记不再散落在效果里。
#include "/bind/time.glsl"
#include "/bind/camera.glsl"
#include "/bind/weather.glsl"


// 通用小工具提供零到一夹紧等计算。
#include "/common/math.glsl"
// 云影选项 `OMNI_RAIN_SHADOW` 在云效果文件里定义，这里按需要引入它，避免调用方漏引。
#include "/rendering/cloud/cloud.glsl"

// --- 雨中画面：按雨遮罩把画面往雨天色混合 ---
// 输入是已经合成好的颜色与雨遮罩；输出混合后的颜色。
// 为什么雨色由天光与阴影光组成：雨天光线更均匀，直接用天光加一点被雨云削弱的阳光最接近真实。
// 为什么区分是否关闭局部降水：默认只在真的下雨的群系叠雨色，强制局部降水时不论群系都按整体降雨处理。
void Rain(inout vec3 color, float rainMask, vec3 shadowlightColorInput, vec3 skylightColorInput){
	OmniWeather weather = bind_weather(); // 本帧的降雨与环境数据只在入口读一次。
	vec3 rainSunlight = shadowlightColorInput * (5.0 - OMNI_RAIN_SHADOW * 4.0); // 雨天阳光被雨云削弱，阴影越弱雨色越暗。
	vec3 rainColor = skylightColorInput + rainSunlight * 0.1; // 雨天色以天光为主，掺一点阳光。

	#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认只在所在群系真的下雨时叠雨色。
		color = mix(color, rainColor * (weather.snowy * 0.07 + 0.01), rainMask * (0.2 * weather.snowy + 0.15) * weather.wetness * OMNI_RAIN_VISIBILITY); // 雪天雨色更亮，混合量随雨遮罩、湿润度与可见度增大。
	#else // 关闭局部降水时按整体降雨处理，不再看群系。
		color = mix(color, rainColor * 0.01, saturate(rainMask * weather.wetness * (OMNI_RAIN_VISIBILITY * 0.15))); // 一律用很淡的雨色。
	#endif
}

// --- 雨雪几何倾斜：在顶点阶段把雨雪下落方向推移成斜的 ---
// 输入是相机相对世界位置；返回要加到世界坐标横纵轴上的偏移。
// 为什么沿高度推移：越高的顶点推得越远，整片雨雪几何变成斜的平行四边形，看起来像被风吹斜。
// 为什么乘 `eyeBrightnessOneSmooth`：只有玩家真正露天时雨雪才该倾斜，洞穴里看到的雨雪不跟着动。
// 说明：iterationT 把这段写在 `Weather_VS` 的主函数里，没有独立名字；这里按职责抽成函数，命名是 Omni 的补充。
vec2 RainWindOffset(vec3 worldPos){
	OmniCamera camera = bind_camera(); // 相机位置从绑定结构取一次。
	OmniTime time = bind_time(); // 动画时间从绑定结构取一次。
	return gfx_rain_wind_offset(worldPos, camera.position, time.seconds, vec2(OMNI_RAIN_WIND_X, OMNI_RAIN_WIND_Z), OMNI_RAIN_DISTURBANCE, bind_weather().eyeBrightnessOne); // 全局量与选项交给库。
}

// --- 雨遮罩：读天气贴图的透明通道，空白纹素直接丢弃 ---
// 输入是天气贴图纹素；返回雨遮罩值，供写进零号画面的透明通道。
// 为什么小于零点一就丢弃：天气贴图大部分是透明的，不丢弃会画出整片空白四边形，挡住后面的场景。
// 说明：iterationT 把这段写在 `Weather_FS` 的主函数里，没有独立名字；这里按职责抽成函数。
#ifdef OMNI_FRAGMENT
// 说明：`discard` 只在片元阶段合法，顶点阶段引入本文件时会跳过这个函数。
float WeatherRainMask(vec4 texel){
	if (texel.a < 0.1) discard; // 透明纹素直接丢弃，不写缓冲。

	return texel.a; // 其余返回自身的覆盖度，作为雨遮罩。
}
#endif // 片元专用函数结束。
#endif // OMNI_RENDER_WEATHER_WEATHER_INCLUDED
