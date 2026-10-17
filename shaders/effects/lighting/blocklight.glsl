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
*/
#ifndef OMNI_BLOCKLIGHT_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_BLOCKLIGHT_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"方块光与手持光","en_us":"Block & held light"}}
// @option {"label":{"zh_cn":"方块光强度","en_us":"Block light brightness"},"description":{"zh_cn":"光源方块自身发光与照亮周围的强度，同时影响资源包自发光的强度。","en_us":"Brightness of light sources and the area they light; also scales resource-pack emissiveness."},"slider":true}
#define OMNI_TORCHLIGHT_BRIGHTNESS 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"方块光色温","en_us":"Block light temperature"},"description":{"zh_cn":"光源方块发光与照亮周围的色温，单位开尔文；只改颜色不改强度。","en_us":"Colour temperature of block light in kelvin; changes colour only, not brightness."},"slider":true}
#define OMNI_TORCHLIGHT_COLOR_TEMPERATURE 3000 // [2000 2500 3000 3500 4000 4500 5000 5500 6000 6500 7000 7500 8000 8500 9000 9500 10000 12000 15000]
// @option {"label":{"zh_cn":"指向性方块光","en_us":"Directional block light"},"description":{"zh_cn":"在法线贴图上显示光照方向；需要支持法线贴图的资源包，可能出现光照衔接错误。","en_us":"Shows the light direction on normal maps; needs a normal-map pack and may show seams."}}
//#define OMNI_DIRECTIONAL_BLOCKLIGHT
// @option {"label":{"zh_cn":"指向性权重","en_us":"Directional strength"},"description":{"zh_cn":"指向性方块光的强度；调大方向感更强，光照衔接错误也更明显。","en_us":"Strength of directional block light; larger is more directional and shows more seams."},"slider":true}
#define OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"自发光贴图模式","en_us":"Emissive mode"},"description":{"zh_cn":"硬编码发光、资源包 PBR 发光，或两者相加。","en_us":"Hardcoded emissive, resource-pack PBR emissive, or both added."},"values":{"0":{"zh_cn":"仅硬编码","en_us":"Hardcoded only"},"1":{"zh_cn":"仅PBR贴图","en_us":"PBR only"},"2":{"zh_cn":"PBR贴图 + 硬编码","en_us":"PBR + hardcoded"}}}
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
#define OMNI_FLASHLIGHT_CAMERA_SMOOTH
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
	ao = mix(ao, vec3(1.0), saturate(lightmap * 5.0 - 4.2)); // 光等级接近满值时遮蔽趋向全亮，光源附近的暗角消失。

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

	lightmap = min(lightmap, 1.0 - 0.13 * lightSourceMask); // 发光方块自身把方块光等级压一档，避免贴图照出方块光。

	lightmap = CurveBlockLightTorch(lightmap); // 按距离平方曲线重整等级，得到火把那样集中的光。

	#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
		return colorTorchlight * ao * (lightmap * OMNI_TORCHLIGHT_BRIGHTNESS * 0.015); // 主世界常数较小，靠自动曝光拉回。
	#else
		return colorTorchlight * ao * (lightmap * OMNI_TORCHLIGHT_BRIGHTNESS * 0.15); // 下界末地没有阳光，常数放大十倍。
	#endif
}

// --- 纹理自发光：按材质掩码给发光方块与受光实体补自发光 ---
// 输入是底色、方块光等级、自发光强度与不透明材质掩码；输出该像素收到的自发光颜色。
// 为什么分三种模式：仅硬编码、仅资源包、两者相加，玩家可按资源包情况选择，默认相加。
// 为什么用底色长度缩放硬编码发光：贴图越亮的部位自发光越强，避免在暗贴图上凭空发光。
vec3 TextureLighting(vec3 albedo, float lightmap, float emissiveness, MaterialMask mask){
	emissiveness *= OMNI_EMISSIVENESS_BRIGHTNESS; // 资源包自发光先乘整体亮度。

	#if OMNI_TEXTURE_EMISSIVENESS_MODE == 1 // 仅资源包模式：只用自发光强度，不看方块类型。
		#ifdef OMNI_OVERWORLD
			return vec3(emissiveness * OMNI_TORCHLIGHT_BRIGHTNESS * 0.01); // 主世界常数。
		#else
			return vec3(emissiveness * OMNI_TORCHLIGHT_BRIGHTNESS * 0.1); // 下界末地放大十倍。
		#endif
	#else // 硬编码与相加模式：先把各类方块的硬编码发光累加成一个强度。
		float blockLightingMask  = 	mask.glowstone 			* 0.016; // 荧石。
			  blockLightingMask += 	mask.torch 				* 0.03; // 火把。
			  blockLightingMask += 	mask.fire 				* 0.004; // 火。
			  blockLightingMask += 	mask.lava 				* 0.012; // 岩浆。
			  blockLightingMask += 	mask.redstoneTorch 		* 0.001; // 红石火把。
			  blockLightingMask += 	mask.oxidizedBulb 		* 0.0002; // 氧化铜灯。

		vec3 blockLighting = vec3(1.0); // 默认白光，只有出现火把类光源才染成火把光色。
		if (blockLightingMask > 0.0) blockLighting = colorTorchlight;

			  blockLightingMask += 	mask.soulFire 			* 0.001; // 灵魂火。
			  blockLightingMask += 	mask.amethyst 			* 0.0003; // 紫水晶。
			  blockLightingMask += 	mask.endPortal 			* 4.0; // 末地传送门的发光很强。
			  blockLightingMask += 	mask.entitiesLitHigh 	* 0.02; // 高亮自发光实体。
			  blockLightingMask += 	mask.entitiesLitMedium 	* 0.005; // 中亮实体。
			  blockLightingMask += 	mask.entitiesLitLow 	* 0.002; // 低亮实体。
			  blockLightingMask += 	mask.particlelit 		* 0.01; // 受光粒子。
			  blockLightingMask += 	mask.redstone 			* 0.2 * emissiveness; // 红石线随资源包自发光变亮。

		blockLightingMask *= length(albedo); // 用底色亮度缩放，暗贴图不发光。

		#if OMNI_TEXTURE_EMISSIVENESS_MODE == 2 // 相加模式：硬编码与资源包取较大者。
			#ifdef OMNI_OVERWORLD
				return blockLighting * (max(blockLightingMask * OMNI_TEXTURE_BRIGHTNESS, emissiveness * 0.005) * OMNI_TORCHLIGHT_BRIGHTNESS);
			#else
				return blockLighting * (max(blockLightingMask * OMNI_TEXTURE_BRIGHTNESS, emissiveness * 0.005) * OMNI_TORCHLIGHT_BRIGHTNESS * 10.0);
			#endif
		#else // 仅硬编码模式：完全忽略资源包自发光。
			#ifdef OMNI_OVERWORLD
				return blockLighting * (blockLightingMask * OMNI_TEXTURE_BRIGHTNESS * OMNI_TORCHLIGHT_BRIGHTNESS);
			#else
				return blockLighting * (blockLightingMask * OMNI_TEXTURE_BRIGHTNESS * OMNI_TORCHLIGHT_BRIGHTNESS * 10.0);
			#endif
		#endif
	#endif
}

// --- 手电筒光斑形状：按光线与指向的夹角给出一束光的强度分布 ---
// 为什么用曲线两次叠加：主瓣给中心亮区，副瓣给一点点外圈余晖；再乘一圈环形暗环，让光斑边界更像手电筒。
float spotShape(float r){
	float shape = curve(saturate(r * 2.0 - (2.0 - OMNI_FLASHLIGHT_FOV))); // 中心主瓣，夹角越小越亮。
	shape += curve(saturate(r * 1.25 - (1.0 - OMNI_FLASHLIGHT_FOV))) * 0.01; // 很弱的外圈余晖。

	const float ringSize = 8.0 / OMNI_FLASHLIGHT_FOV; // 暗环的宽度随光束角度缩放。
	shape *= 1.0 - curve(saturate(1.0 - abs(r * ringSize - ringSize + 1.0))) * 0.25; // 在主瓣外面压一圈暗环。

	return shape; // 返回零到一的光斑强度。
}

// --- 手持光源的屏幕空间阴影：在屏幕里沿光源方向找遮挡 ---
// 输入是视空间表面位置、视线方向、法线与光源方向；输出可见度，零到一。
// 为什么起点要沿法线抬一点：手持光源离表面很近，不抬会刚出发就打到自己，整片出现自阴影。
// 为什么用蓝噪声抖动采样：固定采样会在光斑边缘留下规则条纹，抖动后配合时间抗锯齿消除。
float TorchScreenSpaceShadow(vec3 viewPos, vec3 viewDir, vec3 normal, vec3 shadowDir){
	#if OMNI_HELDLIGHT_SHADOW_QUALITY > 0 // 高质量用两倍步数，阴影更连续、远处也压得住。
		const int omniHeldShadowSteps = 16;
	#else
		const int omniHeldShadowSteps = 8; // 低质量步数与原来一致。
	#endif

	shadowDir.z = max(shadowDir.z, 1e-5); // 深度分量保证不太小，避免下列除法把射线推到无穷远。

	float rayLength = -0.04 * viewPos.z / shadowDir.z; // 一步射线的长度，按当前深度与光源方向缩放。
	vec3 viewRayDir = shadowDir * rayLength; // 视空间里的射线方向。

	vec3 start = viewPos; // 射线起点就是当前表面。

	float pixelScale = max(pixelSize.x, pixelSize.y); // 一个像素的最大边长，用来把偏移折算到屏幕。
	float NdotL = saturate(dot(shadowDir, normal)); // 光源方向与法线的夹角余弦。

	float fov = atan(1.0 / gbufferProjection[1][1]) * 360.0 * rPI; // 由投影反推视角，供偏移按视野缩放。
	start += viewRayDir * (pixelScale * max(0.04 / max(dot(normal, -viewDir), 0.1), 1e3)); // 沿射线先跳过一段，掠射时跳得更多。
	start += normal * (8e-3 * fov * -viewPos.z * pixelScale / max(NdotL, 0.01)); // 再沿法线抬一点，掠射角抬得更多。

	vec3 end = start + viewRayDir; // 一步的终点。

	start = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * start.xy, -start.z); // 起点投影到裁剪空间。
	end   = vec3(vec2(gbufferProjection[0][0], gbufferProjection[1][1]) * end.xy,   -end.z); // 终点同样投影。

	vec3 screenRayDir = (end - start); // 这一步在裁剪空间的位移。
	screenRayDir.xy *= 0.5; // 横纵方向换算到零到一坐标。

	start.xy += gbufferProjection[3].xy; // 补上投影的平移项。
	start.xy *= 0.5; // 裁剪空间转到零到一。

	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动，抗锯齿会把噪点平均掉。
		float noise = BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
		vec2 offsetCoord = 0.5 + taaJitter * 0.5; // 采样坐标补上本帧抖动。
	#else // 不开时间抗锯齿时只能固定噪声。
		float noise = BlueNoise().x; // 按像素平铺的固定噪声。
		vec2 offsetCoord = vec2(0.5); // 不补抖动。
	#endif

	float minDist = LinearDepth_From_ScreenDepth(0.7); // 深度小于这个值的像素在前面，不再作为遮挡。

	float shadow = 1.0; // 可见度，初值全亮。
	float stepLength = 1.0; // 步长，逐步增大。

	for (int i = 0; i < omniHeldShadowSteps; i++, start += screenRayDir * stepLength, stepLength += 0.3){ // 按质量取八或十六步，步长递增覆盖更远。
		vec3 samplePos = start + screenRayDir * noise * stepLength; // 加抖动的采样位置。

		if (samplePos.z < minDist) break; // 已经走到相机很近的地方，后面没有可靠深度。

		samplePos.xy = samplePos.xy / samplePos.z + offsetCoord; // 透视除法得到屏幕坐标。

		if (saturate(samplePos.xy) != samplePos.xy) break; // 出了屏幕就停止，屏幕外没有可靠深度。

		float sampleDepth = textureLod(depthtex1, samplePos.xy, 0.0).x; // 读该点的不透明深度。

		if (sampleDepth < 0.7) break; // 近处已有几何挡住，后面不必再看。

		#ifdef DISTANT_HORIZONS // 有远景时，近景是天空才改用远景深度。
			float sampleDist = 0.0; // 采样点距离。

			if (sampleDepth == 1.0){ // 近景是天空。
				sampleDepth = textureLod(dhDepthTex1, samplePos.xy, 0.0).x; // 改读远景深度。
				sampleDist = LinearDepth_From_ScreenDepth_DH(sampleDepth); // 远景深度换成距离。
			}else{
				sampleDist = LinearDepth_From_ScreenDepth(sampleDepth); // 近景深度换成距离。
			}
		#else
			float sampleDist = LinearDepth_From_ScreenDepth(textureLod(depthtex1, samplePos.xy, 0.0).x); // 直接把深度换成距离。
		#endif

		if (samplePos.z - sampleDist > 0.0){ // 射线深度超过几何深度，说明几何在前面。
			shadow = 0.0; // 记为完全遮挡。
			break; // 结束步进。
		}
	}

	return max(shadow, 1.0 - OMNI_HELDLIGHT_SHADOW_STRENGTH); // 按强度给阴影压到下限，强度零点八五时与原来的零点一五底光完全一致。
}

// --- 手持光源：火把球形光与手电筒一束光 ---
// 输入是视空间表面位置、视线方向、法线、粗糙度、遮蔽项与是否手部；输出该像素收到的手持光颜色。
// 为什么手部单独处理：手持物离光源最近，直接用发光等级当亮度，不再做方向与衰减，避免手被自己的光源照出条纹。
vec3 HeldLighting(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand){
	float heldLightFalloff = 0.0; // 手持光累计衰减量。

	#if OMNI_HELDLIGHT_MODE > 0 // 手电筒模式：两支灯源各是一束朝前的光。

		if (isHand){ // 手部直接按发光等级给亮度。
			heldLightFalloff = 0.01 * max(heldBlockLightValue, heldBlockLightValue2); // 取两只手里较大的发光等级。
		}else{
			#ifdef OMNI_FLASHLIGHT_CAMERA_SMOOTH // 打开指向平滑时，光束方向滞后于视角。
				float angleRx = eyeRxSmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 俯仰角按过渡时长滞后。
				mat3 Rx = mat3(1.0,  0.0,          0.0,
							   0.0,  cos(angleRx), sin(angleRx),
							   0.0, -sin(angleRx), cos(angleRx)); // 俯仰旋转矩阵。

				float angleRy = eyeRySmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 偏航角按过渡时长滞后。
				mat3 Ry = mat3(cos(angleRy), 0.0, -sin(angleRy),
							   0.0,          1.0,  0.0,
							   sin(angleRy), 0.0,  cos(angleRy)); // 偏航旋转矩阵。

				vec3 aimDir = Ry * Rx * vec3(0.0, 0.0, -1.0); // 平滑后的光束指向。
			#else
				vec3 aimDir = vec3(0.0, 0.0, -1.0); // 不平滑时始终朝相机正前方。
			#endif

			if (heldBlockLightValue > 0.0){ // 右手灯源。
				vec3 spotPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
				float spotDistR = length(spotPosR); // 灯源到表面的距离。
				vec3 shadowDirR = spotPosR / spotDistR; // 灯源指向表面的方向。

				float spotR = pow(max(spotDistR, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减，最近不少于零点六米。
				spotR *= spotShape(dot(shadowDirR, aimDir)); // 乘光斑形状，只有落在光束里才亮。

				#ifdef OMNI_HELDLIGHT_SHADOW // 打开手持光阴影时投屏幕空间阴影。
					spotR *= TorchScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirR); // 光源朝表面的反方向投射线。
				#endif
				spotR *= Fd_Burley(normal, -viewDir, -shadowDirR, roughness) * 1.7 + 0.05; // 乘漫反射，读图更自然。

				heldLightFalloff += heldBlockLightValue * spotR; // 按发光等级累加。
			}

			if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
				vec3 spotPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
				float spotDistL = length(spotPosL); // 灯源到表面的距离。
				vec3 shadowDirL = spotPosL / spotDistL; // 灯源指向表面的方向。

				float spotL = pow(max(spotDistL, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减，最近不少于零点六米。
				spotL *= spotShape(dot(shadowDirL, aimDir)); // 乘光斑形状，只有落在光束里才亮。

				#ifdef OMNI_HELDLIGHT_SHADOW
					spotL *= TorchScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirL); // 光源朝表面的反方向投射线。
				#endif
				spotL *= Fd_Burley(normal, -viewDir, -shadowDirL, roughness) * 1.7 + 0.05; // 乘漫反射，读图更自然。

				heldLightFalloff += heldBlockLightValue2 * spotL; // 按发光等级累加。
			}
		}

		#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
			return vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_HELDLIGHT_BRIGHTNESS * 0.02)); // 手电筒颜色乘遮蔽与强度。
		#else
			return vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_HELDLIGHT_BRIGHTNESS * 0.2)); // 下界末地常数放大十倍。
		#endif

	#else // 火把模式：一支从玩家位置向四周发散的球形光。

		if (isHand){ // 手部直接按发光等级给亮度。
			heldLightFalloff = 0.2 * max(heldBlockLightValue, heldBlockLightValue2); // 取两只手里较大的发光等级。
		}else{
			#ifdef OMNI_HELDLIGHT_SHADOW // 打开手持光阴影时分别给两只手投屏幕空间阴影。

				if (heldBlockLightValue > 0.0){ // 右手灯源。
					vec3 torchPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
					float torchDistR = length(torchPosR); // 灯源到表面的距离。
					torchDistR += 4.0 / (torchDistR + 2.0); // 近距离补一点距离，衰减曲线更圆润。

					float torchR = pow(torchDistR, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

					vec3 shadowDirR = -normalize(viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0)); // 光源方向指向灯源。
					torchR *= TorchScreenSpaceShadow(viewPos, viewDir, normal, shadowDirR); // 投屏幕空间阴影。
					torchR *= Fd_Burley(normal, -viewDir, shadowDirR, roughness) * 1.7 + 0.05; // 乘漫反射。

					heldLightFalloff += heldBlockLightValue * torchR; // 按发光等级累加。
				}

				if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
					vec3 torchPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
					float torchDistL = length(torchPosL); // 灯源到表面的距离。
					torchDistL += 4.0 / (torchDistL + 2.0); // 近距离补一点距离，衰减曲线更圆润。

					float torchL = pow(torchDistL, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

					vec3 shadowDirL = -normalize(viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0)); // 光源方向指向灯源。
					torchL *= TorchScreenSpaceShadow(viewPos, viewDir, normal, shadowDirL); // 投屏幕空间阴影。
					torchL *= Fd_Burley(normal, -viewDir, shadowDirL, roughness) * 1.7 + 0.05; // 乘漫反射。

					heldLightFalloff += heldBlockLightValue2 * torchL; // 按发光等级累加。
				}

			#else // 不投阴影时两支灯源合成一支居中光源，省两次屏幕步进。

				float torchDist = length(viewPos); // 表面到相机的距离，当作到光源的距离。
				torchDist += 4.0 / (torchDist + 2.0); // 近距离补一点距离。
				heldLightFalloff = pow(torchDist, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。
				heldLightFalloff *= Fd_Burley(normal, -viewDir, -viewDir, roughness) + 0.3; // 乘一个近似漫反射。

				heldLightFalloff *= heldBlockLightValue + heldBlockLightValue2; // 按两只手的发光等级之和累加。
			#endif
		}

		#ifdef OMNI_OVERWORLD // 主世界与下界末地用不同的亮度常数。
			return colorTorchlight * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.0015)); // 火把光色乘遮蔽与强度。
		#else
			return colorTorchlight * (ao * 0.5 + 0.5) * (heldLightFalloff * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.015)); // 下界末地常数放大十倍。
		#endif

	#endif
}

// --- 手持高光：把手持光源映到表面高光上 ---
// 输入是待修改的颜色、视空间位置、视线方向、距离、底色、法线与材质；就地把高光加到颜色里。
// 为什么手电筒与火把分开：手电筒用光斑形状限制高光范围，火把是接住相机方向的镜面反射，两者模型不同。
void TorchSpecularHighlight(inout vec3 color, vec3 viewPos, vec3 viewDir, float dist, vec3 albedo, vec3 normal, Material material){
	material.roughness = max(material.roughness, 0.002); // 粗糙度给一个下限，避免高光被压成无限细的线。
	#if OMNI_HELDLIGHT_MODE > 0 // 手电筒模式：高光只落在光束里。
		#ifdef OMNI_FLASHLIGHT_CAMERA_SMOOTH // 与手持光一致地处理光束指向平滑。
			float angleRx = eyeRxSmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 俯仰角按过渡时长滞后。
			mat3 Rx = mat3(1.0,  0.0,          0.0,
							0.0,  cos(angleRx), sin(angleRx),
							0.0, -sin(angleRx), cos(angleRx));

			float angleRy = eyeRySmooth * -OMNI_FLASHLIGHT_CAMERA_SMOOTH_TIME; // 偏航角按过渡时长滞后。
			mat3 Ry = mat3(cos(angleRy), 0.0, -sin(angleRy),
							0.0,          1.0,  0.0,
							sin(angleRy), 0.0,  cos(angleRy));

			vec3 aimDir = Ry * Rx * vec3(0.0, 0.0, -1.0); // 平滑后的光束指向。
		#else
			vec3 aimDir = vec3(0.0, 0.0, -1.0); // 不平滑时始终朝相机正前方。
		#endif

		float heldHighlight = 0.0; // 高光累计量。

		if (heldBlockLightValue > 0.0){ // 右手灯源。
			vec3 spotPosR = viewPos - vec3(OMNI_FLASHLIGHT_POS_R_X, OMNI_FLASHLIGHT_POS_R_Y, 0.0); // 灯源到表面的矢量。
			float spotDistR = length(spotPosR); // 灯源到表面的距离。
			vec3 shadowDirR = spotPosR / spotDistR; // 灯源指向表面的方向。

			float spotR = pow(max(spotDistR, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减。
			spotR *= spotShape(dot(shadowDirR, aimDir)); // 只有落在光束里才亮。

			spotR *= SpecularGGX(normal, -viewDir, -shadowDirR, material.roughness, material.f0); // 乘 GGX 高光。

			heldHighlight += heldBlockLightValue * spotR; // 按发光等级累加。
		}

		if (heldBlockLightValue2 > 0.0){ // 左手灯源，逻辑与右手同。
			vec3 spotPosL = viewPos - vec3(OMNI_FLASHLIGHT_POS_L_X, OMNI_FLASHLIGHT_POS_L_Y, 0.0); // 灯源到表面的矢量。
			float spotDistL = length(spotPosL); // 灯源到表面的距离。
			vec3 shadowDirL = spotPosL / spotDistL; // 灯源指向表面的方向。

			float spotL = pow(max(spotDistL, 0.6), -OMNI_FLASHLIGHT_HELDLIGHT_FALLOFF); // 按距离衰减。
			spotL *= spotShape(dot(shadowDirL, aimDir)); // 只有落在光束里才亮。

			spotL *= SpecularGGX(normal, -viewDir, -shadowDirL, material.roughness, material.f0); // 乘 GGX 高光。

			heldHighlight += heldBlockLightValue2 * spotL; // 按发光等级累加。
		}

		if (heldHighlight > 0.001){ // 高光太小就不改颜色，省一次加法。
			#ifdef OMNI_OVERWORLD
				color += vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * albedo * (heldHighlight * (OMNI_HELDLIGHT_BRIGHTNESS * 0.0025)); // 手电筒颜色乘底色与强度。
			#else
				color += vec3(OMNI_FLASHLIGHT_COLOR_R, OMNI_FLASHLIGHT_COLOR_G, OMNI_FLASHLIGHT_COLOR_B) * albedo * (heldHighlight * (OMNI_HELDLIGHT_BRIGHTNESS * 0.025)); // 下界末地常数放大十倍。
			#endif
		}
	#else // 火把模式：高光取相机方向上的镜面反射。
		float heldHighlight = SpecularGGX(normal, -viewDir, -viewDir, material.roughness, material.f0); // 光源方向近似取视线方向。

		if (heldHighlight > 0.001){ // 高光太小就不改颜色。
			dist += 4.0 / (dist + 2.0); // 近距离补一点距离。
			heldHighlight *= pow(dist, -OMNI_HELDLIGHT_FALLOFF); // 按距离衰减。

			heldHighlight *= (heldBlockLightValue + heldBlockLightValue2); // 按两只手的发光等级之和累加。

			#ifdef OMNI_OVERWORLD
				color += colorTorchlight * albedo * (heldHighlight * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.0002)); // 火把光色乘底色与强度。
			#else
				color += colorTorchlight * albedo * (heldHighlight * (OMNI_TORCHLIGHT_BRIGHTNESS * OMNI_HELDLIGHT_BRIGHTNESS * 0.002)); // 下界末地常数放大十倍。
			#endif
		}
	#endif
}
#endif // 文件守卫结束。
