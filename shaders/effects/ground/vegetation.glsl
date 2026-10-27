/*
效果文件 `effects/ground/vegetation.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/ground/vegetation.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_GROUND_VEGETATION_INCLUDED
#define OMNI_EFFECT_GROUND_VEGETATION_INCLUDED
// @effect {"label":{"zh_cn":"植物","en_us":"Plants"}}
// @option {"label":{"zh_cn":"晃动","en_us":"Waving Plants"},"description":{"zh_cn":"草和树叶会不会随风摆，代价很低。","en_us":"Whether grass and leaves sway in the wind; cheap."}}
#define OMNI_WAVING_PLANTS 1 // [0 1]
// @option {"label":{"zh_cn":"阴影贴图植物晃动","en_us":"Waving Plants in ShadowMap"},"description":{"zh_cn":"让影子里的植物也摆；开启后阴影图中植物会闪。","en_us":"Waves plants inside the shadow map; may flicker in the shadow map."}}
//#define OMNI_SHADOW_WAVING_PLANTS

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
植物摆动：让草、小麦和树叶随风摆动，几何阶段的地形顶点与阴影顶点共用同一份算法与常数。
来源：照 iterationT `Lib/Programs/Gbuffers/Terrain_VS.glsl` 与 `Shadow_VS.glsl` 里的植物摆动段一比一移植。
调用位置：
  地形顶点着色器：算好相机相对世界位置后调用 `WavingPlants(worldPos, mc_Entity.x, v_blockLight.y, gl_MultiTexCoord0.y, mc_midTexCoord.y);`
  阴影顶点着色器：在 `OMNI_SHADOW_WAVING_PLANTS` 打开时调用同一函数，参数来自 `blockLight.y` 与同一组纹理坐标。
可复制示例：
  `vec4 worldPos = gbufferModelViewInverse * viewPos; worldPos.xyz += cameraPosition.xyz;`
  `WavingPlants(worldPos.xyz, mc_Entity.x, v_blockLight.y, gl_MultiTexCoord0.y, mc_midTexCoord.y);`
调用前提（iterationT 原样保留）：`wetness`、`frameTimeCounter` 已由加载器输入声明，`noisetex` 也已声明；
  传入的 `worldPos` 是含相机位置的相机相对世界坐标，风才固定在世界里，不随镜头移动。
设计原因与取舍：
  风常数 `heavy*`、`light*`、`speed*` 只在这里定义一次，地形与阴影顶点共用，两边摆动的幅度与相位完全一致，
  否则同一个植物在地上和它的影子里会摆得不一样。
  草用两套风（轻风与重风）按湿度和随机风强混合；小麦与树叶各自一套三角函数，湿天摆幅更大。
*/
// 内部常数：草的重风参数，风和随机相位一起决定大幅摆动。
#define heavyAxialFrequency 8.0 // 重风纵向的频率。
#define heavyAxialWaveLocalization 0.9 // 重风纵向沿位置变化的快慢。
#define heavyAxialRandomization 13.0 // 重风纵向的随机相位幅度。
#define heavyAxialAmplitude 15.0 // 重风纵向的摆幅。
#define heavyAxialOffset 15.0 // 重风纵向的偏置，让摆动不对称。
#define heavyLateralFrequency 6.732 // 重风横向的频率。
#define heavyLateralWaveLocalization 1.274 // 重风横向沿位置变化的快慢。
#define heavyLateralRandomization 1.0 // 重风横向的随机相位幅度。
#define heavyLateralAmplitude 6.0 // 重风横向的摆幅。
#define heavyLateralOffset 0.0 // 重风横向的偏置。
// 内部常数：草的轻风参数，微风时以它为主。
#define lightAxialFrequency 5.5 // 轻风纵向的频率。
#define lightAxialWaveLocalization 1.1 // 轻风纵向沿位置变化的快慢。
#define lightAxialRandomization 21.0 // 轻风纵向的随机相位幅度。
#define lightAxialAmplitude 5.0 // 轻风纵向的摆幅。
#define lightAxialOffset 5.0 // 轻风纵向的偏置。
#define lightLateralFrequency 5.9732 // 轻风横向的频率。
#define lightLateralWaveLocalization 1.174 // 轻风横向沿位置变化的快慢。
#define lightLateralRandomization 0.0 // 轻风横向没有随机相位，保持规整。
#define lightLateralAmplitude 1.0 // 轻风横向的摆幅。
#define lightLateralOffset 0.0 // 轻风横向的偏置。
// 内部常数：小麦与树叶各自的速度，越大摆得越快。
#define speedWheat 0.1 // 小麦整株的摆动速度。
#define speedWheatLeaf 0.04 // 小麦叶片小幅度抖动的速度。
#define speedLeaves 0.05 // 树叶的摆动速度。
// 摆动用到噪声与共用数学，先引入加载器输入与共用计算。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 植物摆动：按方块编号选择一套风，在原地修改传入的相机相对世界坐标。
// 为什么单独拆出来：地形顶点与阴影顶点要摆得完全一致，共用一份才能保证地上的植物和它的影子对齐。
void WavingPlants(inout vec3 worldPos, float entityId, float blockLightY, float texCoordY, float midTexCoordY){
#if !defined(OMNI_END) && OMNI_WAVING_PLANTS // 末地不摆，未开摆动时整个函数不做事。
	float tick = frameTimeCounter * ANIMATION_SPEED; // 动画时间按速度常数缩放。
	float lightWeight = saturate(blockLightY * 1.5 - 0.5); // 天光太暗的植物不动，避免洞穴里乱摆。
	lightWeight = lightWeight * lightWeight; // 平方。
	lightWeight = lightWeight * lightWeight; // 再平方，让权重更集中。
	float grassWeight = step(texCoordY, midTexCoordY); // 只有方块的上一半会摆，根部分不动。
	if (entityId == 7020.0){ // 一种双层草的形态。
		grassWeight = grassWeight * 0.7; // 摆幅压到七成。
	}else
	if (entityId == 7021.0){ // 另一种双层草的形态。
		grassWeight = grassWeight * 0.7 + 0.7; // 再补七成，整株都摆。
	}
// --- 草：轻风与重风按随机风强混合 ---
	if (entityId == 12.0 || entityId == 7010.0 || entityId == 7020.0 || entityId == 7021.0){ // 这几类编号是草（十二是单独的矮草）。
		float windStrength = mix(0.85, 1.0, wetness); // 雨天风略大。
		vec2 pn = worldPos.xz; // 取水平位置查随机风强。
		pn.x *= 2.0; // 横向频率加倍。
		pn.x -= tick * 15.0; // 让风场沿横向流动。
		pn.y *= 8.0; // 纵向频率提高。
		float windStrengthRandom = BicubicBlurTexture(noisetex, pn / 640.0).x; // 大尺度随机风强。
		windStrengthRandom = mix(windStrengthRandom * windStrengthRandom, windStrengthRandom, wetness); // 雨天让风强更极端。
		windStrength *= mix(windStrengthRandom, 0.5, wetness * 0.25); // 风强随位置起伏，雨天略偏中间值。
		vec2 pn0 = worldPos.xz; // 再取一组位置查相位噪声。
		pn0.x -= tick / 3.0; // 相位也随时间流动。
		float stoch = BicubicBlurTexture(noisetex, pn0 / 64.0).x; // 逐块随机相位，避免整片草同相位。
		vec2 stochLarge = BicubicBlurTexture(noisetex, worldPos.xz / 384.0).xz; // 大尺度随机偏移，让草丛整体游走。
		vec3 p = worldPos.xyz; // 取三维位置参与相位。
		p.x += sin(p.z / 2.0) * 1.0; // 沿纵深给相位一点起伏。
		p.xz += stochLarge.rg * 5.0; // 再加一组大尺度偏移。
		vec2 angleLight = vec2(sin(tick * lightAxialFrequency - p.x * lightAxialWaveLocalization + stoch * lightAxialRandomization) * lightAxialAmplitude + lightAxialOffset, // 轻风纵向角度。
							   sin(tick * lightLateralFrequency - p.x * lightLateralWaveLocalization + stoch * lightLateralRandomization) * lightLateralAmplitude + lightLateralOffset); // 轻风横向角度。
		vec2 angleHeavy = vec2(sin(tick * heavyAxialFrequency - p.x * heavyAxialWaveLocalization + stoch * heavyAxialRandomization) * heavyAxialAmplitude + heavyAxialOffset, // 重风纵向角度。
							   sin(tick * heavyLateralFrequency - p.x * heavyLateralWaveLocalization + stoch * heavyLateralRandomization) * heavyLateralAmplitude + heavyLateralOffset); // 重风横向角度。
		float windStrengthCrossfade = saturate(windStrength * 2.0 - 1.0); // 风强超过一半开始转向重风。
		float lightWindFade = clamp(windStrength * 2.0, 0.2, 1.0); // 轻风至少保留两成。
		vec2 angle = mix(angleLight * lightWindFade, angleHeavy, vec2(windStrengthCrossfade)) * 2.0; // 按风强在两套风之间混合再放大。
		worldPos.x += sin(angle.x * (PI / 180.0)) * grassWeight * lightWeight * 0.5; // 横向摆动。
		worldPos.z += sin(angle.y * (PI / 180.0)) * grassWeight * lightWeight * 0.5; // 纵向摆动。
		worldPos.y += (cos((angle.x + angle.y) * (PI / 180.0)) - 1.0) * grassWeight * lightWeight * 0.5; // 竖直方向被带动，摆起来更自然。
	}
// --- 小麦：整株摆动加叶片抖动 ---
	if (entityId == 7011.0){ // 小麦编号。
		{
			float magnitude = sin(tick * (PI / 28.0) + (worldPos.x + worldPos.z)) * 0.024 + 0.004; // 整株摆幅随位置起伏并保留底线。
			magnitude *= grassWeight; // 乘上只摆上半边的权重。
			magnitude *= lightWeight; // 乘上天光权重。
			float d0 = sin(tick * (PI / speedWheat / 122.0)) * 3.0 - 1.5 + worldPos.z; // 各方向的相位扰动。
			float d1 = sin(tick * (PI / speedWheat / 152.0)) * 3.0 - 1.5 + worldPos.x; // 同上。
			float d2 = sin(tick * (PI / speedWheat / 122.0)) * 3.0 - 1.5 + worldPos.x; // 同上。
			float d3 = sin(tick * (PI / speedWheat / 152.0)) * 3.0 - 1.5 + worldPos.z; // 同上。
			worldPos.x += sin((tick * PI / (28.0 * speedWheat)) + (worldPos.x + d0) * 0.1 + (worldPos.z + d1) * 0.1) * magnitude; // 横向整株摆动。
			worldPos.z += sin((tick * PI / (28.0 * speedWheat)) + (worldPos.z + d2) * 0.1 + (worldPos.x + d3) * 0.1) * magnitude; // 纵向整株摆动。
		}
		{
			float magnitude = sin(tick * (PI / 28.0) + (worldPos.x + worldPos.y) * 0.5) * 0.005 + 0.015; // 叶片抖动幅度更小。
			magnitude *= grassWeight; // 乘上摆动权重。
			magnitude *= lightWeight; // 乘上天光权重。
			float d0 = sin(tick * (PI / speedWheatLeaf / 112.0)) * 3.0 - 1.5; // 叶片相位扰动。
			float d1 = sin(tick * (PI / speedWheatLeaf / 142.0)) * 3.0 - 1.5; // 同上。
			float d2 = sin(tick * (PI / speedWheatLeaf / 112.0)) * 3.0 - 1.5; // 同上。
			float d3 = sin(tick * (PI / speedWheatLeaf / 142.0)) * 3.0 - 1.5; // 同上。
			worldPos.x += sin(tick * (PI / speedWheatLeaf / 18.0) + (-worldPos.x + d0) * 1.6 + (worldPos.z + d1) * 1.6) * magnitude * (1.0 + wetness * 2.0); // 横向叶片抖动，雨天更大。
			worldPos.z += sin(tick * (PI / speedWheatLeaf / 18.0) + (worldPos.z + d2) * 1.6 + (-worldPos.x + d3) * 1.6) * magnitude * (1.0 + wetness * 2.0); // 纵向叶片抖动。
			worldPos.y += sin(tick * (PI / speedWheatLeaf / 11.0) + (worldPos.z + d2) + (worldPos.x + d3)) * (magnitude / 3.0) * (1.0 + wetness * 2.0); // 竖直叶片抖动，幅度为三分之一。
		}
	}
// --- 树叶：低频大幅摆动 ---
	if (entityId == 7030.0){ // 树叶编号。
		float magnitude = sin(tick * (PI / speedLeaves / 28.0) + (worldPos.x + worldPos.z)) * 0.009 + 0.009; // 树叶摆幅随位置起伏并保留底线。
		magnitude *= lightWeight; // 树叶不区分上下，只乘天光权重。
		float d0 = sin(tick * (PI / speedLeaves / 112.0)) * 3.0 - 1.5; // 相位扰动。
		float d1 = sin(tick * (PI / speedLeaves / 142.0)) * 3.0 - 1.5; // 同上。
		float d2 = sin(tick * (PI / speedLeaves / 132.0)) * 3.0 - 1.5; // 同上。
		float d3 = sin(tick * (PI / speedLeaves / 122.0)) * 3.0 - 1.5; // 同上。
		worldPos.x += sin(tick * (PI / speedLeaves / 18.0) + (-worldPos.x + d0) * 1.6 + (worldPos.z + d1) * 1.6) * magnitude * (1.0 + wetness * 1.0); // 横向摆动，雨天略大。
		worldPos.z += sin(tick * (PI / speedLeaves / 17.0) + (worldPos.z + d2) * 1.6 + (-worldPos.x + d3) * 1.6) * magnitude * (1.0 + wetness * 1.0); // 纵向摆动。
		worldPos.y += sin(tick * (PI / speedLeaves / 11.0) + (worldPos.z + d2) + (worldPos.x + d3)) * (magnitude / 2.0) * (1.0 + wetness * 1.0); // 竖直摆动，幅度为一半。
	}
#endif // 摆动条件结束。
}
#endif // OMNI_EFFECT_GROUND_VEGETATION_INCLUDED
