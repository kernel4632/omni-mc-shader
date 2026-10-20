/*
水下焦散：把波法线方块、折射与九次采样的主体接进通用库，函数名与调用点保持不变。
来源 iterationT 阳光在水体里的焦散段。
调用位置：由 `effects/shadow/shadow.glsl` 引入；合成阶段算水体焦散时调用 `CalculateWaterCaustics`，
    水下体积雾读取波法线时调用 `GetWavesNormalFromTex`。
可复制示例：`float caustics = CalculateWaterCaustics(worldPos, shadowLightVector);`
设计原因与取舍：波法线的折射投影与三乘三汇聚采样都在 `gfx/water.glsl`；
    本文件只把七号画面、屏幕尺寸、折射率与两个焦散选项接进去，画面参数与原来一致。
*/
#ifndef OMNI_WATER_CAUSTICS_INCLUDED
#define OMNI_WATER_CAUSTICS_INCLUDED // 置上标记，后续再次引用直接跳过。
// 焦散的折射投影与九次采样在通用库。
#include "/gfx/water.glsl"

// --- 焦散法线：从七号画面的方块里读出波法线 ---
// 七号画面左下角最多五百像素见方，存的是水面波法线；读取时用折射方向把世界位置投到这个方块里。
vec3 GetWavesNormalFromTex(vec3 position, vec3 shadowLightVector){
	return gfx_waves_normal_from_tex(position, shadowLightVector, colortex7, pixelSize, screenSize,
		CAUSTICS_TEX_RESOLUTION, WATER_REFRACT_IOR); // 一次调用完成折射投影与法线解码。
}

// --- 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹 ---
// 输入是相机相对世界位置；把阳光按水面折射后向水下投，用波面法线判断光线是否汇聚，汇聚处更亮。
float CalculateWaterCaustics(vec3 worldPos, vec3 shadowLightVector){
	vec2 dither = BlueNoiseTemporal(); // 每帧变化的抖动，打散采样花纹。
	return gfx_water_caustics(worldPos, shadowLightVector, cameraPosition, colortex7, pixelSize, screenSize,
		CAUSTICS_TEX_RESOLUTION, WATER_REFRACT_IOR, dither, isEyeInWater != 0,
		OMNI_WATER_CAUSTICS_BRIGHTNESS, OMNI_WATER_CAUSTICS_POWER); // 一次调用完成九次采样与亮度重整。
}
#endif // 文件守卫结束。
