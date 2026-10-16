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
  `effects/water.glsl` 的水面与 `effects/material.glsl` 的地表湿润读 `OMNI_SURFACE_WETNESS` 与 `OMNI_DISABLE_LOCAL_PRECIPITATION`。
可复制示例：
  `Rain(color, rainMask);`  合成阶段给整幅画面叠雨色；
  `vec2 offset = RainWindOffset(worldPos); worldPos.xz += offset;`  顶点阶段倾斜雨雪几何；
  `float mask = WeatherRainMask(texel);`  片元阶段取雨遮罩，空白纹素会被丢弃。
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `Rain` 需要合成主程序的 `in vec3 colorShadowlight`、`in vec3 colorSkylight`；
  `RainWindOffset` 需要程序声明 `uniform float eyeBrightnessOneSmooth;`（该值在 `rendering/pipeline.properties` 里由加载器计算）；
  `OMNI_RAIN_SHADOW` 属于 `effects/cloud.glsl`，调用方需先引入该文件；
  `OMNI_DISABLE_LOCAL_PRECIPITATION` 与 `wetness`、`eyeSnowySmooth`、`eyeNoPrecipitationSmooth` 由天气选项与加载器输入提供。
关键设计原因与取舍：
  雨雪几何只在顶点阶段水平推移，不引入顶点着色器的复杂运算；晴天不出雨是因为加载器已经不给雨遮罩值，这里不再额外判断；
  雨遮罩写进零号画面的透明通道，读取端靠它判断雨落在画面哪一层，而不是靠世界位置猜。
*/
#ifndef OMNI_WEATHER_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_WEATHER_INCLUDED // 置上标记，后续再次引用直接跳过。

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

// 通用小工具提供零到一夹紧等计算。
#include "/common/math.glsl"
// 云影选项 `OMNI_RAIN_SHADOW` 在云效果文件里定义，这里按需要引入它，避免调用方漏引。
#include "/effects/cloud.glsl"

// --- 雨中画面：按雨遮罩把画面往雨天色混合 ---
// 输入是已经合成好的颜色与雨遮罩；输出混合后的颜色。
// 为什么雨色由天光与阴影光组成：雨天光线更均匀，直接用天光加一点被雨云削弱的阳光最接近真实。
// 为什么区分是否关闭局部降水：默认只在真的下雨的群系叠雨色，强制局部降水时不论群系都按整体降雨处理。
void Rain(inout vec3 color, float rainMask, vec3 shadowlightColorInput, vec3 skylightColorInput){
	vec3 rainSunlight = shadowlightColorInput * (5.0 - OMNI_RAIN_SHADOW * 4.0); // 雨天阳光被雨云削弱，阴影越弱雨色越暗。
	vec3 rainColor = skylightColorInput + rainSunlight * 0.1; // 雨天色以天光为主，掺一点阳光。

	#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认只在所在群系真的下雨时叠雨色。
		color = mix(color, rainColor * (eyeSnowySmooth * 0.07 + 0.01), rainMask * (0.2 * eyeSnowySmooth + 0.15) * wetness * OMNI_RAIN_VISIBILITY); // 雪天雨色更亮，混合量随雨遮罩、湿润度与可见度增大。
	#else // 关闭局部降水时按整体降雨处理，不再看群系。
		color = mix(color, rainColor * 0.01, saturate(rainMask * wetness * (OMNI_RAIN_VISIBILITY * 0.15))); // 一律用很淡的雨色。
	#endif
}

// --- 雨雪几何倾斜：在顶点阶段把雨雪下落方向推移成斜的 ---
// 输入是相机相对世界位置；返回要加到世界坐标横纵轴上的偏移。
// 为什么沿高度推移：越高的顶点推得越远，整片雨雪几何变成斜的平行四边形，看起来像被风吹斜。
// 为什么乘 `eyeBrightnessOneSmooth`：只有玩家真正露天时雨雪才该倾斜，洞穴里看到的雨雪不跟着动。
// 说明：iterationT 把这段写在 `Weather_VS` 的主函数里，没有独立名字；这里按职责抽成函数，命名是 Omni 的补充。
vec2 RainWindOffset(vec3 worldPos){
	float angle = dot(worldPos.xyz + cameraPosition.xyz, vec3(3.0, 0.5, 3.0)) + frameTimeCounter * 0.2; // 用位置与时间算一个缓慢摆动的相位。
	vec2 rot = vec2(sin(angle), cos(angle)); // 由相位得到摆动方向。
	vec2 offset = (vec2(OMNI_RAIN_WIND_X, OMNI_RAIN_WIND_Z) + rot * OMNI_RAIN_DISTURBANCE) * worldPos.y; // 固定风向加摆动，再按高度放大。

	return eyeBrightnessOneSmooth * offset; // 只有露天时倾斜，返回最终偏移。
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
#endif // 文件守卫结束。
