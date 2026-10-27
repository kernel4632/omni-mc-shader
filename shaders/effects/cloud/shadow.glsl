/*
效果文件 `effects/cloud/shadow.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/cloud/shadow.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_CLOUD_SHADOW_INCLUDED
#define OMNI_CLOUD_SHADOW_INCLUDED
/*
云影：把地表坐标沿光方向投到云影贴图取遮蔽，并对云影贴图做横纵两次高斯模糊。
来源 iterationT `CloudShadow.glsl`。
调用位置：由 `effects/cloud/cloud.glsl` 引入；延迟四号、五号调用 `CloudShadowAxialBlur` 做横向、纵向模糊，
    合成阶段调用 `CloudShadowFromTex`、`GetSmoothCloudShadow`。
可复制示例：
    `float shadow = CloudShadowFromTex(worldPos, worldShadowVector);`
    `vec4 blurred = CloudShadowAxialBlur(texelCoord, ivec2(1, 0));`
调用前提：中间画面 `colortex2` 由绘制主体提供，相机与湿度由 `bind/` 转换；云影范围、贴图尺寸与雨天阴影选项由 `effects/cloud/cloud.glsl` 定义。
设计原因与取舍：投影、十六像素三次模糊、两档天气混合与七点高斯权重都在 `gfx/cloud.glsl`；
    本文件只把宿主相机、湿度与选项接进通用库，函数名与调用点保持不变，画面参数与原来一致。
*/
// 相机与天气输入由绑定层整理，云影只接收普通数值。
#include "/bind/camera.glsl"
#include "/bind/weather.glsl"
// 云影的投影、三次模糊、全局统计与高斯模糊在通用库。
#include "/omni-gfx/cloud.glsl"

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float CloudShadowFromTex(vec3 worldPos, vec3 shadowLightVector){
	OmniCamera cameraData = bind_camera(); // 相机位置、画面尺寸与像素大小只读一次。
	OmniWeather weather = bind_weather(); // 降雨湿润度只读一次。
	#ifdef NO_COMPOSITE_VS // 没有合成顶点阶段时退回按阴影相机方向投影。
		vec3 worldShadowVector = cameraData.shadowViewInverse[2].xyz; // 用阴影相机视线方向作为光方向。
	#endif
	#if OMNI_CLOUD_SHADOW_FADE // 打开淡出时，太阳越贴地云影越淡。
		const bool fadeAngle = true; // 按光方向高度淡出。
	#else
		const bool fadeAngle = false; // 不淡出。
	#endif
	float shadowTexSize = floor(min(cameraData.screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 云影贴图实际边长。
	return ogxCloudShadowSample(colortex2, worldPos, shadowLightVector, cameraData.position.y, OMNI_CLOUD_SHADOW_RANGE,
		cameraData.screenSize, cameraData.pixelSize, shadowTexSize, weather.wetness, OMNI_RAIN_SHADOW, fadeAngle); // 一次调用完成投影、采样与天气混合。
}

// 参考签名兼容层：没有全局阴影光方向的程序使用朝向天空的保守方向。
float CloudShadowFromTex(vec3 worldPos){ return CloudShadowFromTex(worldPos, vec3(0.0, 1.0, 0.0)); }

// 全局云影：给整个场景用的一个粗粒度云影值，来自二号画面顶行的统计像素。
float GetSmoothCloudShadow(){
	OmniCamera cameraData = bind_camera(); // 画面高度只读一次。
	OmniWeather weather = bind_weather(); // 降雨湿润度只读一次。
	#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW // 有体积云和云影时读统计像素。
		const bool fromTexture = true; // 从贴图顶行读取。
	#else // 否则用纯天气估一个值。
		const bool fromTexture = false; // 不读贴图。
	#endif
	return ogxGlobalCloudShadow(colortex2, ivec2(40, cameraData.screenSize.y - 1.0), weather.wetness, OMNI_RAIN_SHADOW, fromTexture); // 一次调用取全局云影。
}

// 云影横向或纵向高斯模糊：原程序横纵两个程序各写一份只差采样轴，合并成一个函数，名字加云影前缀。
// 调用前提：`colortex2` 已声明，画面尺寸从绑定层读取；`axis` 取值横向 `(1,0)` 或纵向 `(0,1)`。
vec4 CloudShadowAxialBlur(ivec2 texelCoord, ivec2 axis){
	vec2 screenExtent = bind_camera().screenSize; // 画面尺寸只读一次。
	ivec4 shadowTexBorder = ivec4(screenExtent - floor(min(screenExtent.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)), screenExtent - 1.0); // 云影贴图的边界，采样要夹在里面。
	return ogxCloudShadowBlur(colortex2, texelCoord, axis, shadowTexBorder.xy, shadowTexBorder.zw); // 一次调用完成七点高斯模糊。
}
#endif // OMNI_CLOUD_SHADOW_INCLUDED
