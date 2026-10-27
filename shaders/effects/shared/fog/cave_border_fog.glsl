/*
效果文件 `effects/shared/fog/cave_border_fog.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/fog/cave_border_fog.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_CAVE_BORDER_FOG_INCLUDED
#define OMNI_CAVE_BORDER_FOG_INCLUDED
/*
洞穴雾与区块边界雾：来源 Eclipse `dimensions/composite4.fsh` 的 `blendAllFogTypes` 与 `getBorderFogDensity`。
职责：`OmniCaveDetection` 用天空光反推洞内程度，`CaveFog` 填洞内空气，`BorderFogSkyColor` 查该方向天空色，
  `BorderFog` 把渲染距离附近的画面混向天空色，遮住区块加载。
调用位置：由 `effects/fog/fog.glsl` 的 `VanillaFog` 在主世界按 `OMNI_CAVE_FOG`、`OMNI_BORDER_FOG` 开关调用。
可复制示例：`CaveFog(color, dist);`  `BorderFog(color, dist);`
调用前提：由 `effects/fog/fog.glsl` 引入，且已先引入 `common/coordinates.glsl`、`effects/sky/sky.glsl`
  并声明相机量；本文件不重复引入。两项默认关闭，关闭时 `VanillaFog` 不含调用。
关键设计原因与取舍：原程序用加载器驱动的洞内计时，本项目用等价天空光曲线反推；边界雾改用预计算大气天空辐射。
*/

// --- 洞穴雾与边界雾：来源 Eclipse `dimensions/composite4.fsh` 的 `blendAllFogTypes` 与 `getBorderFogDensity` ---
// 洞内程度：Eclipse 用加载器按“黑暗里停留的计时”平滑出一个量；本项目没有这个计时，
// 用等价的天空光曲线反推，天空光越暗越接近洞内，返回零到一，洞穴雾与边界雾共用。
float OmniCaveDetection(){
	return 1.0 - eyeBrightnessSmoothCurved; // 天空光曲线为一说明露天，为零说明洞内。
}

// 某方向的天空色：替代 Eclipse 边界雾查询用的天空贴图 `skyFromTex`，改用本项目等价的预计算大气天空辐射。
// 为什么相机高度抬到最低高度：贴地时大气几何退化，抬高后地平线一带不会裂开，与地表散射同法。
vec3 BorderFogSkyColor(vec3 worldDir){
	#ifdef OMNI_ATMO_HORIZON // 打开地平线时相机高度有下限，与天空渲染一致。
		vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 高度换成公里并加星球半径。
	#else
		vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 默认按海平面高度。
	#endif
	vec3 transmittance; // 大气透过率，这里不用，只作查表输出。
	bool rayIntersectsGround; // 视线是否打到地面，这里不用，只作查表输出。
	return GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, true, transmittance, rayIntersectsGround); // 查该方向的天空辐射。
}

// 洞穴雾：照 Eclipse `dimensions/composite4.fsh:452-472` 一比一搬运，把洞内空气填成一层可调的雾。
// 输入是待修改颜色与这条视线的距离；就地把洞穴雾加到颜色上。
// 依赖替代：Eclipse 的归一化玩家位置取本像素的世界视线方向，`caveDetection` 用 `OmniCaveDetection` 的等价量。
void CaveFog(inout vec3 color, float linearDistance){
	vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * ViewPos_From_ScreenPos_Raw(gl_FragCoord.xy * pixelSize, 1.0)); // 本像素的世界视线方向，等于 Eclipse 归一化后的玩家位置。
	float caveDetection = OmniCaveDetection(); // 洞内程度，替代 Eclipse 的加载器驱动量。

	vec3 cavefogCol = vec3(OMNI_CAVE_FOG_COLOR_R, OMNI_CAVE_FOG_COLOR_G, OMNI_CAVE_FOG_COLOR_B) * 0.3; // 基础雾色按原程序缩到零点三。
	cavefogCol *= 1.0 - pow(1.0 - pow(1.0 - max(1.0 - linearDistance / far, 0.0), 2.0), OMNI_CAVE_FOG_FALLOFF); // 随距离由近向远变浓。
	cavefogCol *= exp(-7.0 * clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0)) * 0.999 + 0.001; // 朝下看最浓、朝上看最淡的竖直梯度。

	float skyhole = pow(clamp(1.0 - pow(max(worldDir.y - 0.6, 0.0) * 5.0, 2.0), 0.0, 1.0), 2.0); // 抬头天空方向的洞顶权重。
	float caveFactor = 1.0 - smoothstep(60.0, 63.0, cameraPosition.y); // 高度窗：六十到六十三米之间淡出，对应 Eclipse `CAVE_DETECTION` 的默认档。
	bool isSky = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x >= 1.0; // 天空像素单独按洞顶权重混合。

	color = mix(color + cavefogCol * caveDetection, cavefogCol, isSky ? skyhole * caveDetection * caveFactor : 0.0); // 与 Eclipse 同一行公式。
}

// 区块边界雾：照 Eclipse `dimensions/composite4.fsh:519-533` 与 `:827-863` 搬运，把渲染距离附近的画面淡到天空色。
// 输入是待修改颜色与这条视线的距离；就地把远处地形混向该方向的天空颜色，遮住区块加载。
// 依赖替代：雾色改用预计算大气天空辐射；原程序对不透明与半透明各算一次边界雾，这里只有一条距离，合并成一次。
void BorderFog(inout vec3 color, float linearDistance){
	vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * ViewPos_From_ScreenPos_Raw(gl_FragCoord.xy * pixelSize, 1.0)); // 本像素的世界视线方向。
	float caveDetection = OmniCaveDetection(); // 洞内程度，洞穴里不出现边界雾。

	float distanceFactor = min(max(1.0 - linearDistance / far, 0.0) * 3.0 / OMNI_BORDER_FOG_INTENSITY, 1.0); // 越接近远裁剪面越接近一。
	float borderFogDensity = smoothstep(0.0, 1.0, 1.0 - distanceFactor); // 只在远处拉起一层雾墙；写成正序阈值，与原程序的反序写法数学等价。
	borderFogDensity *= exp(-10.0 * pow(clamp(worldDir.y, 0.0, 1.0) * 4.0, 2.0)); // 只在朝下的方向出现。
	borderFogDensity *= 1.0 - caveDetection; // 洞穴里不出边界雾。

	bool isSky = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x >= 1.0; // 天空像素本身不用再补边界雾。
	borderFogDensity *= isSky ? 0.0 : 1.0; // 与 Eclipse `getBorderFogDensity` 天空返回零一致。

	color = mix(color, BorderFogSkyColor(worldDir), borderFogDensity); // 把远处画面混向天空色。
}
#endif // OMNI_CAVE_BORDER_FOG_INCLUDED
