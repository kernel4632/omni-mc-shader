/*
效果文件 `effects/water/waterfog.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/waterfog.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_WATERFOG_INCLUDED
#define OMNI_WATERFOG_INCLUDED
/*
水雾：把水下与水后雾需要的宿主输入接进通用库，函数名与调用点保持不变。
来源 iterationT 水下雾段。
调用位置：由 `effects/water/water.glsl` 引入；合成阶段处理半透明水面时调用 `WaterFog`。
可复制示例：`WaterFog(color, viewDir, opaqueDist, waterDist, normal, materialMask);`
设计原因与取舍：雾色、分波段衰减、逆光散射与密度曲线都在 `gfx/water.glsl`；
    本文件只读眼睛水深、竖直轴、湿润度与选项，然后调用一次通用库，数值与原来逐字一致。
*/
// 水下与水后雾的公式在通用库。
#include "/omni-gfx/water.glsl"

// 水下与水后雾：按距离做分波段衰减并向雾色靠拢。
// 参数里的 `occludedWater` 表示视线被半透明玻璃挡住的水，`totalInternalReflection` 表示发生全反射。
// 为什么区分是否在水下：水面之上看水下与整只眼睛浸在水里，雾色与散射方向都不同。
void WaterFog(inout vec3 color, vec3 viewDir, float opaqueDist, float waterDist, vec3 normal, MaterialMask mask, float occludedWater, float waterSkylight, float totalInternalReflection, vec3 shadowLightVector, vec3 shadowlightColorInput, vec3 skylightColorInput){
	float eyeWaterDepth = saturate(float(eyeBrightnessSmooth.y) / 120.0 - 0.8); // 眼睛离水面的深度感，由天空光反推。
	color = ogxWaterFog(color, viewDir, opaqueDist, waterDist, normal, mask.ice, mask.stainedGlass, mask.hand,
		occludedWater, waterSkylight, totalInternalReflection, shadowLightVector, shadowlightColorInput, skylightColorInput,
		gbufferModelView[1].xyz, eyeWaterDepth, wetness, WATER_REFRACT_IOR, OMNI_WATER_FOG_DENSITY, isEyeInWater != 0); // 一次调用完成水雾合成。
}

#endif // OMNI_WATERFOG_INCLUDED
