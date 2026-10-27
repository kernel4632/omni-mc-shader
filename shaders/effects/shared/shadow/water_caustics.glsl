/*
效果文件 `effects/shared/shadow/water_caustics.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/shadow/water_caustics.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_WATER_CAUSTICS_INCLUDED
#define OMNI_WATER_CAUSTICS_INCLUDED
// 焦散要读蓝噪声抖动与水的折射率，坐标与噪声由共享数学和噪声提供。
#include "/common/math.glsl"
#include "/common/noise.glsl"
/*
水下焦散：把波法线方块、折射与九次采样的主体接进通用库，函数名与调用点保持不变。
来源 iterationT 阳光在水体里的焦散段。
调用位置：由 `effects/shared/shadow.glsl` 引入；合成阶段算水体焦散时调用 `CalculateWaterCaustics`，
    水下体积雾读取波法线时调用 `GetWavesNormalFromTex`。
可复制示例：`float caustics = CalculateWaterCaustics(worldPos, shadowLightVector);`
设计原因与取舍：波法线的折射投影与三乘三汇聚采样都在 `gfx/water.glsl`；
    本文件只把七号画面、屏幕尺寸、折射率与两个焦散选项接进去，画面参数与原来一致。
*/
// 焦散的折射投影与九次采样在通用库。
#include "/omni-gfx/water.glsl"

// --- 焦散法线：从七号画面的方块里读出波法线 ---
// 七号画面左下角最多五百像素见方，存的是水面波法线；读取时用折射方向把世界位置投到这个方块里。
vec3 GetWavesNormalFromTex(vec3 position, vec3 shadowLightVector){
	return ogxWavesNormalFromTex(position, shadowLightVector, colortex7, pixelSize, screenSize,
		CAUSTICS_TEX_RESOLUTION, WATER_REFRACT_IOR); // 一次调用完成折射投影与法线解码。
}

// --- 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹 ---
// 输入是相机相对世界位置；把阳光按水面折射后向水下投，用波面法线判断光线是否汇聚，汇聚处更亮。
float CalculateWaterCaustics(vec3 worldPos, vec3 shadowLightVector){
	vec2 dither = BlueNoiseTemporal(); // 每帧变化的抖动，打散采样花纹。
	return ogxWaterCaustics(worldPos, shadowLightVector, cameraPosition, colortex7, pixelSize, screenSize,
		CAUSTICS_TEX_RESOLUTION, WATER_REFRACT_IOR, dither, isEyeInWater != 0,
		OMNI_WATER_CAUSTICS_BRIGHTNESS, OMNI_WATER_CAUSTICS_POWER); // 一次调用完成九次采样与亮度重整。
}
// --- 参考签名兼容层：参考函数自己读全局光方向，宿主层用同名重载补齐 ---
// 为什么单独保留单参数版本：影子程序的 `worldShadowVector` 已由调用方声明，单参数入口
// 与 iterationT 的 `GetWavesNormalFromTex(position)`、`CalculateWaterCaustics(worldPos)` 对齐。
vec3 GetWavesNormalFromTex(vec3 position){
	return GetWavesNormalFromTex(position, vec3(0.0, 1.0, 0.0)); // 非阴影程序没有全局光方向，用朝上的保守方向。
}
float CalculateWaterCaustics(vec3 worldPos){
	return CalculateWaterCaustics(worldPos, vec3(0.0, 1.0, 0.0)); // 同上，兼容重载不依赖宿主全局量。
}
#endif // OMNI_WATER_CAUSTICS_INCLUDED
