/*
方块光与手持光的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lighting/blocklight.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_LIGHTING_BLOCKLIGHT_INCLUDED
#define OMNI_BIND_LIGHTING_BLOCKLIGHT_INCLUDED
#include "/effects/lighting/blocklight.glsl"
/*
方块光与手持光：照 iterationT `Lib/BasicFounctions/Blocklight.glsl` 一比一移植。
职责分成三块：
  一、选项：方块光强度与色温、自发光模式与亮度、手持光与手电筒的全部设置，全项目只在这里定义一次；
  二、光照计算：`BlockLighting` 算原版方块光，`TextureLighting` 算资源包自发光，`HeldLighting` 算手持光源；
  三、手持高光：`TorchSpecularHighlight` 把手持光源映到表面高光上，`TorchScreenSpaceShadow` 给手持光源投屏幕空间阴影。
调用位置：
  `rendering/composite.glsl` 的 `composite` 程序逐像素调用 `HeldLighting`、`BlockLighting`、`TextureLighting`；
  `rendering/composite.glsl` 的 `composite5` 程序在合并反射之后调用 `TorchSpecularHighlight`。
可复制示例：
  `finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSoild);`
  `finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5);`
  `TorchSpecularHighlight(color, viewPos, viewDir, waterDist, gbuffer.albedo, gbuffer.normalW, gbuffer.material);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `colorTorchlight` 由合成主程序声明，是火把光色，本文件只读取；
  `heldBlockLightValue`、`heldBlockLightValue2`、`eyeRxSmooth`、`eyeRySmooth` 由 `common/uniforms.glsl` 声明；
  `texelCoord`、`texCoord`、`depthtex1`、`dhDepthTex1`、`gbufferProjection`、`pixelSize`、`taaJitter` 由主程序或加载器提供；
  `OMNI_TAA` 由 `effects/clarity/antialiasing.glsl` 提供，`Material` 与 `MaterialMask` 由 `effects/ground/material.glsl` 提供（本文件已引入）。
关键设计原因与取舍：
  主世界与下界末地用不同的亮度常数：原程序把两套数值写在同一分支里，这里照搬，保证两个维度各自的手持光强度与原程序一致；
  自发光分「仅硬编码」「仅资源包」「两者相加」三种模式，默认相加，关闭资源包自发光时不改方块自身发光；
  `DIRECTIONAL_BLOCKLIGHT` 在 iterationT 3.2.0 只声明未使用，按移植合同保留选项但不接任何计算，画面不受影响。
    本文件按算法拆到同目录：手持光源（光斑形状、屏幕空间阴影、手持光与手持高光）在 `held_light.glsl`；方块光与纹理自发光留在本文件；引入顺序与拆分前逐字一致。
*/


// 共用数学提供曲线与光照模型，坐标换算提供深度还原，蓝噪声提供屏幕阴影抖动，材质文件提供掩码结构。
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
#include "/bind/ground/material.glsl"

// --- 原版方块光：按方块光等级与遮蔽算出火把照亮周围的光 ---
// 输入是方块光等级、遮蔽项与不透明材质掩码；输出该像素收到的方块光颜色。
// 为什么先按光等级压低遮蔽：光源方块附近的像素本身就亮，遮蔽不该把它压黑，所以靠近满级时把遮蔽推向全亮。
// 为什么先给光源方块限一个上限等级：发光方块自己贴图上不该出现高亮方块光，限一档避免自发光方块过曝。
vec3 BlockLighting(float lightmap, vec3 ao, MaterialMask mask){
	float lightSourceMask = saturate(mask.glowstone // 各类发光方块与受光实体合成一个「这里是不是光源」的标记。
								   + mask.torch
								   + mask.fire
								   + mask.lava
								   + mask.entitiesLitHigh
								   + mask.entitiesLitMedium
								   + mask.entitiesLitLow
								   + mask.particlelit
								   + mask.soulFire
								   + mask.amethyst);
	#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
		const bool overworld = true; // 主世界常数较小，靠自动曝光拉回。
	#else
		const bool overworld = false; // 下界末地没有阳光，常数放大十倍。
	#endif
	return gfx_block_light(lightmap, ao, lightSourceMask, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS, overworld); // 一次调用完成方块光。
}

// --- 纹理自发光：按材质掩码给发光方块与受光实体补自发光 ---
// 输入是底色、方块光等级、自发光强度与不透明材质掩码；输出该像素收到的自发光颜色。
// 为什么分三种模式：仅硬编码、仅资源包、两者相加，玩家可按资源包情况选择，默认相加。
// 为什么用底色长度缩放硬编码发光：贴图越亮的部位自发光越强，避免在暗贴图上凭空发光。
vec3 TextureLighting(vec3 albedo, float lightmap, float emissiveness, MaterialMask mask){
	float emissive = emissiveness * OMNI_EMISSIVENESS_BRIGHTNESS; // 资源包自发光先乘整体亮度。
	#ifdef OMNI_OVERWORLD
		const bool overworld = true; // 主世界倍率。
	#else
		const bool overworld = false; // 下界末地放大十倍。
	#endif
	#if OMNI_TEXTURE_EMISSIVENESS_MODE == 1 // 仅资源包模式：只用自发光强度，不看方块类型。
		return gfx_texture_emissive(albedo, emissive, 0.0, false, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS,
			OMNI_TEXTURE_BRIGHTNESS, 1, overworld); // 一次调用完成资源包自发光。
	#else // 硬编码与相加模式：先把各类方块的硬编码发光累加成一个强度。
		float blockLightingMask  = 	mask.glowstone 			* 0.016; // 荧石。
			  blockLightingMask += 	mask.torch 				* 0.03; // 火把。
			  blockLightingMask += 	mask.fire 				* 0.004; // 火。
			  blockLightingMask += 	mask.lava 				* 0.012; // 岩浆。
			  blockLightingMask += 	mask.redstoneTorch 		* 0.001; // 红石火把。
			  blockLightingMask += 	mask.oxidizedBulb 		* 0.0002; // 氧化铜灯。
		bool torchTinted = blockLightingMask > 0.0; // 只有出现火把类光源才染成火把光色，判断点与原程序一致。
			  blockLightingMask += 	mask.soulFire 			* 0.001; // 灵魂火。
			  blockLightingMask += 	mask.amethyst 			* 0.0003; // 紫水晶。
			  blockLightingMask += 	mask.endPortal 			* 4.0; // 末地传送门的发光很强。
			  blockLightingMask += 	mask.entitiesLitHigh 	* 0.02; // 高亮自发光实体。
			  blockLightingMask += 	mask.entitiesLitMedium 	* 0.005; // 中亮实体。
			  blockLightingMask += 	mask.entitiesLitLow 	* 0.002; // 低亮实体。
			  blockLightingMask += 	mask.particlelit 		* 0.01; // 受光粒子。
			  blockLightingMask += 	mask.redstone 			* 0.2 * emissive; // 红石线随资源包自发光变亮。
		return gfx_texture_emissive(albedo, emissive, blockLightingMask, torchTinted, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS,
			OMNI_TEXTURE_BRIGHTNESS, OMNI_TEXTURE_EMISSIVENESS_MODE, overworld); // 一次调用完成硬编码与相加模式。
	#endif
}

// 手持光源：光斑形状、屏幕空间阴影、手持光与手持高光。
#include "/bind/lighting/held_light.glsl"
#endif // OMNI_BIND_LIGHTING_BLOCKLIGHT_INCLUDED
