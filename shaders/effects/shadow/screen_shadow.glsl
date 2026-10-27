/*
效果文件 `effects/shadow/screen_shadow.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shadow/screen_shadow.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_SCREEN_SHADOW_INCLUDED
#define OMNI_SCREEN_SHADOW_INCLUDED
/*
屏幕空间阴影：在屏幕里沿阳光方向找遮挡，补阴影图覆盖不到的近处细节。
来源 iterationT 阴影图之外的屏幕空间补充段。
调用位置：由 `effects/shadow/shadow.glsl` 引入；需要细碎阴影的程序调用 `ScreenSpaceShadow`。
可复制示例：`float shadow = ScreenSpaceShadow(viewPos, viewDir, normal, mask, shadowVector);`
设计原因与取舍：屏幕空间阴影是阴影图之外的补充手段，和阴影图坐标、可变半影分开成文件，便于按算法定位；阈值与抖动照 iterationT 原样。
*/
// --- 屏幕空间阴影：在屏幕里沿阳光方向找遮挡，补阴影图覆盖不到的近处细节 ---
// 输入是视空间位置、视线方向与视空间法线；沿阳光在屏幕上的投影方向步进，撞到比当前更近的几何就累加遮挡。
// 为什么叶片先用饱和放大：叶片的材质编号可能带小数，先归一到零或一，后面的取舍才稳定。
// 步进主循环在 `gfx/shadow.glsl`，本函数只选视野、吸收量与噪音。
float ScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, MaterialMask mask, vec3 shadowVector){
	mask.leaves = saturate(mask.leaves * 1e10); // 把叶片标记归一到零或一。

	float fov = mask.grass + mask.leaves > 0.5 ? 95.0 : atan(1.0 / gbufferProjection[1][1]) * 360.0 * rPI; // 草和叶片按较大视野估计，其余由投影反推真实视野。

	float absorption = 0.0; // 一次遮挡的吸收量。
	absorption += 0.7 * mask.grass; // 草的吸收系数。
	absorption += 0.85 * mask.leaves; // 叶片的吸收更强。
	absorption = pow(absorption, sqrt(-viewPos.z) * 0.5); // 距离越远吸收越弱，远处几何不再压黑。

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		float noise = BlueNoiseTemporal().x; // 每帧变化的抖动。
		#ifdef OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
			if (mask.entityPlayer > 0.5) noise = BlueNoise().x; // 玩家像素改用固定噪声。
		#endif
		vec2 offsetCoord = 0.5 + taaJitter * 0.5; // 采样坐标补上本帧抖动。
	#else // 不开时间抗锯齿时固定噪声。
		float noise = BlueNoise().x; // 固定噪声。
		vec2 offsetCoord = vec2(0.5); // 不补抖动。
	#endif

	#ifdef DISTANT_HORIZONS // 有远景时先看近景深度，近景是天空才查远景。
		return ogxSunScreenShadow(viewPos, viewDir, normal, shadowVector, fov, absorption, mask.grass + mask.leaves, mask.grass,
			depthtex1, dhDepthTex1, gbufferProjection, gbufferProjectionInverse, dhProjectionInverse, max(pixelSize.x, pixelSize.y),
			0.06 * shadowDistance / shadowMapResolution, offsetCoord, noise, true, 12); // 十二步，步长递增。
	#else
		return ogxSunScreenShadow(viewPos, viewDir, normal, shadowVector, fov, absorption, mask.grass + mask.leaves, mask.grass,
			depthtex1, depthtex1, gbufferProjection, gbufferProjectionInverse, gbufferProjectionInverse, max(pixelSize.x, pixelSize.y),
			0.06 * shadowDistance / shadowMapResolution, offsetCoord, noise, false, 12); // 没有远景时用近景深度占位。
	#endif
}

#endif // OMNI_SCREEN_SHADOW_INCLUDED
