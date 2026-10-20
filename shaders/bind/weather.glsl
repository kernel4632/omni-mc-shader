/*
天气绑定：把降雨、眼睛亮度、夜视、失明、黑暗与脚下介质整理成一个普通结构体。
调用位置：天空、雾、水面和曝光效果在边界调用 `bind_weather()`，再把字段传给通用库或自己的计算。
可复制示例：`float rain = bind_weather().wetness;`
设计原因与取舍：眼睛亮度在加载器里有三个平滑版本，名称相似但用途不同，这里按含义改名后放一起，
  避免效果文件分别记 `eyeBrightnessSmoothCurved`、`eyeBrightnessZeroSmooth` 这些长名字；
  介质保留加载器的整数编号，水面与雾仍按同一套编号分支，防止 `isEyeInWater` 两处解释不一致。
*/
#ifndef OMNI_BIND_WEATHER_INCLUDED // 只引入一次，避免结构体与函数重复定义。
#define OMNI_BIND_WEATHER_INCLUDED // 置上标记，后续再次引用直接跳过。
// 天气输入只在加载器声明文件里出现一次。
#include "/common/uniforms.glsl"

struct OmniWeather {
	float wetness; // 平滑后的降雨湿润度，零到一。
	float nightVision; // 夜视强度，零到一。
	float blindness; // 失明强度，零到一。
	float darkness; // 黑暗效果强度，零到一。
	float darknessLight; // 黑暗效果的脉动亮度。
	float eyeBrightnessCurved; // 天空光亮度的曲线平滑值。
	float eyeBrightnessZero; // 完全没有天空光的平滑标记。
	float eyeBrightnessOne; // 天空光满值的平滑标记。
	float snowy; // 所在群系下雪的平滑标记。
	float noPrecipitation; // 所在群系不降水的平滑标记。
	vec2 eyeBrightness; // 平滑眼睛亮度，横轴方块光、纵轴天空光，零到两百四十。
	int eyeInWater; // 眼睛介质：零空气、一水、二岩浆、三细雪。
};

// 读取本帧的天气与环境输入；只做打包，不改变任何数值。
OmniWeather bind_weather(){
	OmniWeather weather; // 待填充的结构体。
	weather.wetness = wetness; // 平滑降雨湿润度。
	weather.nightVision = nightVision; // 夜视强度。
	weather.blindness = blindness; // 失明强度。
	weather.darkness = darknessFactor; // 黑暗效果强度。
	weather.darknessLight = darknessLightFactor; // 黑暗脉动亮度。
	weather.eyeBrightnessCurved = eyeBrightnessSmoothCurved; // 天空光曲线值。
	weather.eyeBrightnessZero = eyeBrightnessZeroSmooth; // 无天空光标记。
	weather.eyeBrightnessOne = eyeBrightnessOneSmooth; // 满天空光标记。
	weather.snowy = eyeSnowySmooth; // 下雪群系标记。
	weather.noPrecipitation = eyeNoPrecipitationSmooth; // 不降水标记。
	weather.eyeBrightness = vec2(eyeBrightnessSmooth); // 整数亮度换成通用二分量。
	weather.eyeInWater = isEyeInWater; // 介质编号。
	return weather; // 返回纯数据，调用方不需要知道来源。
}
#endif // 天气绑定结束。
