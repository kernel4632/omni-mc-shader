/*
效果文件 `effects/lighting/blocklight.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lighting/blocklight.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_LIGHTING_BLOCKLIGHT_INCLUDED
#define OMNI_EFFECT_LIGHTING_BLOCKLIGHT_INCLUDED
// @effect {"label":{"zh_cn":"方块光与手持光","en_us":"Block & held light"}}
// @option {"label":{"zh_cn":"方块光强度","en_us":"Block light brightness"},"description":{"zh_cn":"光源方块自身发光与照亮周围的强度，同时影响资源包自发光的强度。","en_us":"Brightness of light sources and the area they light; also scales resource-pack emissiveness."},"slider":true}
#define OMNI_TORCHLIGHT_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"方块光色温","en_us":"Block light temperature"},"description":{"zh_cn":"光源方块发光与照亮周围的色温，单位开尔文；只改颜色不改强度。","en_us":"Colour temperature of block light in kelvin; changes colour only, not brightness."},"slider":true}
#define OMNI_TORCHLIGHT_COLOR_TEMPERATURE 3000 // [2000 2500 3000 3500 4000 4500 5000 5500 6000 6500 7000 7500 8000 8500 9000 9500 10000 12000 15000]
// @option {"label":{"zh_cn":"指向性方块光","en_us":"Directional block light"},"description":{"zh_cn":"在法线贴图上显示光照方向；需要支持法线贴图的资源包，可能出现光照衔接错误。","en_us":"Shows the light direction on normal maps; needs a normal-map pack and may show seams."}}
#define OMNI_DIRECTIONAL_BLOCKLIGHT 0 // [0 1]
// @option {"label":{"zh_cn":"指向性权重","en_us":"Directional strength"},"description":{"zh_cn":"指向性方块光的强度；调大方向感更强，光照衔接错误也更明显。","en_us":"Strength of directional block light; larger is more directional and shows more seams."},"slider":true}
#define OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"发光贴图模式","en_us":"Emissive mode"},"description":{"zh_cn":"硬编码发光、资源包 PBR 发光，或两者相加。","en_us":"Hardcoded emissive, resource-pack PBR emissive, or both added."},"values":{"0":{"zh_cn":"仅硬编码","en_us":"Hardcoded only"},"1":{"zh_cn":"仅PBR贴图","en_us":"PBR only"},"2":{"zh_cn":"PBR贴图 + 硬编码","en_us":"PBR + hardcoded"}}}
#define OMNI_TEXTURE_EMISSIVENESS_MODE 2 // [0 1 2]
// @option {"label":{"zh_cn":"硬编码亮度","en_us":"Hardcoded brightness"},"description":{"zh_cn":"按方块类型写死的自发光强度。","en_us":"Emissive strength baked in by block type."},"slider":true}
#define OMNI_TEXTURE_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"PBR贴图亮度","en_us":"PBR emissive brightness"},"description":{"zh_cn":"资源包自发光贴图的整体亮度。","en_us":"Overall brightness of the resource-pack emissive map."},"slider":true}
#define OMNI_EMISSIVENESS_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"手持光源模式","en_us":"Held light mode"},"description":{"zh_cn":"火把是随视角的球形光，手电筒是朝前的一束光。","en_us":"Torch is a view-centred glow, flashlight is a forward beam."},"values":{"0":{"zh_cn":"火把","en_us":"Torch"},"1":{"zh_cn":"手电筒","en_us":"Flashlight"}}}
#define OMNI_HELDLIGHT_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"手持光源强度","en_us":"Held light brightness"},"description":{"zh_cn":"手持光源的整体强度。","en_us":"Overall brightness of the held light."},"slider":true}
#define OMNI_HELDLIGHT_BRIGHTNESS 1.0 // [0.0 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"火把衰减系数","en_us":"Torch falloff"},"description":{"zh_cn":"火把模式下亮度随距离衰减的快慢；调大衰减更快。","en_us":"How fast torch-mode brightness falls with distance; larger fades faster."},"slider":true}
#define OMNI_HELDLIGHT_FALLOFF 1.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"手持光投阴影","en_us":"Held light shadow"},"description":{"zh_cn":"让手持光源投射屏幕空间阴影，可能出现轻微的错误遮挡。","en_us":"Lets the held light cast screen-space shadows; may show slight wrong occlusion."}}
#define OMNI_HELDLIGHT_SHADOW
// @option {"label":{"zh_cn":"手持光阴影强度","en_us":"Held light shadow strength"},"description":{"zh_cn":"手持光源投下阴影的最大变暗程度，一为全黑、零不压暗；零点八五与原来一致，对应 Eclipse 的 LPV_HANDHELD_SHADOWS_STRENGTH。","en_us":"Maximum darkening of the held light's shadow; 1 is fully dark, 0 does not darken; 0.85 matches the old look; matches Eclipse's LPV_HANDHELD_SHADOWS_STRENGTH."},"slider":true}
#define OMNI_HELDLIGHT_SHADOW_STRENGTH 0.85 // [0.0 0.25 0.5 0.6 0.7 0.75 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
// @option {"label":{"zh_cn":"手持光阴影质量","en_us":"Held light shadow quality"},"description":{"zh_cn":"手持光屏幕阴影的步数，高更精细也更慢；对应 Eclipse 的 LPV_HANDHELD_SHADOWS_QUALITY。","en_us":"Steps of the held light's screen shadow; high is finer and slower; matches Eclipse's LPV_HANDHELD_SHADOWS_QUALITY."},"values":{"0":{"zh_cn":"低","en_us":"Low"},"1":{"zh_cn":"高","en_us":"High"}}}
#define OMNI_HELDLIGHT_SHADOW_QUALITY 0 // [0 1]
// @option {"label":{"zh_cn":"手持光影响高光","en_us":"Held light specular"},"description":{"zh_cn":"把手持光源映到表面高光上；需要支持高光贴图的资源包并开启 PBR。","en_us":"Maps the held light into surface specular; needs a specular-map pack with PBR on."}}
#define OMNI_SPECULAR_HELDLIGHT
// @option {"label":{"zh_cn":"手电筒光束角度","en_us":"Flashlight FOV"},"description":{"zh_cn":"手电筒照亮范围的大小。","en_us":"Size of the flashlight's lit cone."},"slider":true}
#define OMNI_FLASHLIGHT_FOV 0.25 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]
// @option {"label":{"zh_cn":"手电筒衰减系数","en_us":"Flashlight falloff"},"description":{"zh_cn":"手电筒模式下亮度随距离衰减的快慢；调大衰减更快。","en_us":"How fast flashlight brightness falls with distance; larger fades faster."},"slider":true}
#define OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"手电筒指向平滑","en_us":"Flashlight aim smoothing"},"description":{"zh_cn":"让手电筒指向滞后于视角变化，转头时光束不会瞬间跟到底。","en_us":"Makes the flashlight aim lag behind camera turns so the beam does not snap."}}
#define OMNI_FLASHLIGHT_CAMERA_SMOOTH 1 // [0 1]
// @option {"label":{"zh_cn":"手电筒过渡时长","en_us":"Flashlight aim time"},"description":{"zh_cn":"手电筒指向平滑的过渡时间，单位秒。","en_us":"Transition time of the aim smoothing in seconds."},"slider":true}
#define OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME 10.0 // [5.0 7.0 10.0 15.0 20.0 30.0 50.0]
// @option {"label":{"zh_cn":"手电筒颜色-红","en_us":"Flashlight colour - R"},"description":{"zh_cn":"手电筒光束的红色分量。","en_us":"Red channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_R 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"手电筒颜色-绿","en_us":"Flashlight colour - G"},"description":{"zh_cn":"手电筒光束的绿色分量。","en_us":"Green channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_G 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"手电筒颜色-蓝","en_us":"Flashlight colour - B"},"description":{"zh_cn":"手电筒光束的蓝色分量。","en_us":"Blue channel of the flashlight beam."},"slider":true}
#define OMNI_FLASHLIGHT_COLOR_B 1.0 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"水平位置-左持","en_us":"Horizontal offset - left"},"description":{"zh_cn":"左手手电筒灯源的水平位置，正值方向为右。","en_us":"Horizontal position of the left-hand light, positive is right."},"slider":true}
#define OMNI_FLASHLIGHT_POS_L_X -0.25 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"垂直位置-左持","en_us":"Vertical offset - left"},"description":{"zh_cn":"左手手电筒灯源的垂直位置，正值方向为上。","en_us":"Vertical position of the left-hand light, positive is up."},"slider":true}
#define OMNI_FLASHLIGHT_POS_L_Y -0.15 // [-1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"水平位置-右持","en_us":"Horizontal offset - right"},"description":{"zh_cn":"右手手电筒灯源的水平位置，正值方向为右。","en_us":"Horizontal position of the right-hand light, positive is right."},"slider":true}
#define OMNI_FLASHLIGHT_POS_R_X 0.25 // [-1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"垂直位置-右持","en_us":"Vertical offset - right"},"description":{"zh_cn":"右手手电筒灯源的垂直位置，正值方向为上。","en_us":"Vertical position of the right-hand light, positive is up."},"slider":true}
#define OMNI_FLASHLIGHT_POS_R_Y -0.15 // [-1.5 -1.4 -1.3 -1.2 -1.1 -1.0 -0.9 -0.8 -0.7 -0.6 -0.5 -0.45 -0.4 -0.35 -0.3 -0.25 -0.2 -0.15 -0.1 -0.05 0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
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
#include "/effects/ground/material.glsl"

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
	return ogxBlockLight(lightmap, ao, lightSourceMask, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS, overworld); // 一次调用完成方块光。
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
		return ogxTextureEmissive(albedo, emissive, 0.0, false, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS,
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
		return ogxTextureEmissive(albedo, emissive, blockLightingMask, torchTinted, colorTorchlight, OMNI_TORCHLIGHT_BRIGHTNESS,
			OMNI_TEXTURE_BRIGHTNESS, OMNI_TEXTURE_EMISSIVENESS_MODE, overworld); // 一次调用完成硬编码与相加模式。
	#endif
}

// 手持光源：光斑形状、屏幕空间阴影、手持光与手持高光。
#include "/effects/lighting/held_light.glsl"
#endif // OMNI_EFFECT_LIGHTING_BLOCKLIGHT_INCLUDED
