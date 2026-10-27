/*
效果文件 `effects/fog/vanilla_fog.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/fog/vanilla_fog.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_VANILLA_FOG_INCLUDED
#define OMNI_VANILLA_FOG_INCLUDED
/*
原版雾：处理原版药水的失明、黑暗与岩浆、细雪等特殊视效，并串起洞穴雾与边界雾。
来源：iterationT `Lib/BasicFounctions/VanillaComposite.glsl` 的 `VanillaFog` 一比一移植。
职责：只提供 `VanillaFog`，把画面往对应颜色混合。
调用位置：由 `effects/fog/fog.glsl` 引入；`effects/world/composite_scene.glsl` 的合成五号在整幅画面上调用。
可复制示例：`VanillaFog(color, waterDist);`
调用前提：由 `effects/fog/fog.glsl` 引入，且已先引入 `effects/color/color.glsl`（提供 `OMNI_DISABLE_BLINDNESS_DARKNESS`）
  与同目录 `cave_border_fog.glsl`（提供 `CaveFog`、`BorderFog`）；本文件不重复引入。
关键设计原因与取舍：这些效果来自原版药水与介质状态，按原版逻辑照搬；洞穴雾与边界雾只在主世界补。
*/

// --- 原版雾：处理失明、黑暗与岩浆、细雪等特殊视效 ---
// 输入是待修改颜色与距离；就地把画面往对应颜色混合。
// 为什么这些单独处理：它们来自原版药水与介质状态，不属于自定义雾，改动可能影响玩法判断，所以按原版逻辑照搬。
void VanillaFog(inout vec3 color, float dist){
	#ifdef OMNI_OVERWORLD // 洞穴雾与边界雾只属于主世界，下界与末地不画。
		#if OMNI_CAVE_FOG // 洞内空气里的洞穴雾：与 Eclipse 一样只在空气中且相机高度低于一千五百米。
			if (isEyeInWater == 0 && cameraPosition.y < 1500.0) CaveFog(color, dist); // 按距离与视线方向补洞内雾。
		#endif
		#if OMNI_BORDER_FOG // 渲染距离附近的区块边界雾。
			BorderFog(color, dist); // 把远处画面混向天空色，遮住区块加载。
		#endif
	#endif

	#if !OMNI_DISABLE_BLINDNESS_DARKNESS // 调试开关，关闭后不看失明与黑暗。
		if (darknessFactor > 0.0) color = mix(color, vec3(0.0), smoothstep(5.0, mix(far, 15.0, darknessFactor), dist) * darknessFactor); // 黑暗效果：越远越黑。
		if (blindness > 0.0) color = mix(color, vec3(0.0), smoothstep(1.5, mix(far, 4.5, blindness), dist) * blindness); // 失明效果：更近就开始变黑。
	#endif

	if (isEyeInWater == 3) color = mix(color, vec3(0.03), smoothstep(0.0, 2.0, dist)); // 细雪里画面压暗。
 
	if (isEyeInWater == 2) color = mix(color, vec3(0.3721, 0.0775, 0.0024) * OMNI_TORCHLIGHT_BRIGHTNESS, smoothstep(0.0, 1.0, dist)); // 岩浆里染成橙红。
}
#endif // OMNI_VANILLA_FOG_INCLUDED
