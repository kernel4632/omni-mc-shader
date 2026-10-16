/*
世界与远景：给远景地形与水加逐块噪声打散纹理感，并按距离剔除挡住近景的远景几何。
来源：照 iterationT `Lib/Programs/Gbuffers/DH_Terrain_FS.glsl`、`DH_Water_FS.glsl` 的 `DH_noise` 与剔除段一比一移植。
调用位置：
  远景地形片元：先 `DHTerrainCulling(viewPos);` 剔除近处远景，再在开启噪声时 `DH_noise(albedo, worldPos);`
  远景水片元：在开启噪声时 `tex = DH_noise(color, worldPos);`
可复制示例：
  `DHTerrainCulling(viewPos);`
  `DH_noise(albedo, worldPos + cameraPosition + mat3(gbufferModelView) * viewNormal * 0.001);`
  `vec4 tex = DH_noise(color, worldPos + cameraPosition + mat3(gbufferModelView) * tbn[2] * 0.001);`
调用前提（iterationT 原样保留）：地形版 `DH_noise` 依赖调用方声明的 `materialIDs`（判断树叶），
  两个版本都依赖调用方把世界坐标与法线一起传进来，噪声才贴在世界表面上而不是屏幕上。
设计原因与取舍：噪声先把坐标量化到固定网格再取随机值，网格随 `DH_TEXTURE_NOISE_STEPS` 变密，
  贴图近看才不会糊成一片；权重再按亮度起伏，亮暗交界处噪声最明显，纯色区域几乎不加。
  水版比地形版多乘一层水的透明度，让浅水噪声更弱，深水更明显。
*/
#ifndef OMNI_WORLD_INCLUDED // 只引入一次。
#define OMNI_WORLD_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"远景","en_us":"Distance"}}
// @option {"label":{"zh_cn":"远景地形剔除","en_us":"Terrain Culling"},"description":{"zh_cn":"剔除靠近玩家的远景区块，减少和正常区块的混叠；可能让地形出现空缺。","en_us":"Culls distant chunks near the player to reduce overlap with normal chunks; may leave gaps."}}
#define OMNI_DH_TERRAIN_CULLING
// @option {"label":{"zh_cn":"远景纹理噪声","en_us":"Apply Texture Noise"},"description":{"zh_cn":"给远景表面加逐块噪声，打散纹理感。","en_us":"Adds per-block noise to distant surfaces to break up the texture."}}
#define OMNI_DH_TEXTURE_NOISE
// @option {"label":{"zh_cn":"噪声缩放","en_us":"Noise Scale"},"description":{"zh_cn":"噪声网格的密度，越大噪声越细。","en_us":"Density of the noise grid; higher is finer."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STEPS 4.0 // [2.0 4.0 8.0 16.0 32.0]
// @option {"label":{"zh_cn":"噪声强度","en_us":"Noise Strength"},"description":{"zh_cn":"噪声压暗表面的强度。","en_us":"How strongly the noise darkens the surface."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STRENGTH 0.07 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// 噪声用到共用数学与亮度，树叶判定取材质文件的编号，距离剔除读加载器的远景距离。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/material.glsl"
// 远景地形剔除：太近的远景区块与正常区块重叠，直接丢弃，避免两层地形互相闪烁。
// 调用前提：`far` 已由加载器输入声明。
void DHTerrainCulling(vec3 viewPos){
	#ifdef OMNI_DH_TERRAIN_CULLING // 关闭时不剔除。
		if (length(viewPos) < far * 0.7) discard; // 距离小于远景距离的七成就丢掉。
	#endif
}
// 远景地形噪声：把世界坐标量化到网格后取随机值，按亮度与树叶加权，压暗表面打散纹理感。
// 调用前提：调用方已声明 `materialIDs`。
void DH_noise(inout vec3 color, vec3 pos, float materialID){
	const float steps = OMNI_DH_TEXTURE_NOISE_STEPS; // 网格密度来自选项。
	pos = floor(pos * steps) / steps; // 把坐标量化到网格，避免噪声随距离糊掉。
	float weight = Luminance(color) * 2.0 - 1.0; // 亮度先映射到负一到一。
	weight = 1.0 - weight * weight; // 取反平方，让亮暗交界处权重最大。
	weight *= float(materialID == MATID_LEAVES) + 1.0; // 树叶权重加倍，树叶更碎。
	weight *= OMNI_DH_TEXTURE_NOISE_STRENGTH; // 整体强度来自选项。
	float noise = fract(sin(dot(pos.xy + fract(sin(pos.z * (91.3458)) * 47453.5453), vec2(12.9898, 78.233))) * 43758.5453); // 经典地形随机值，把高度也混进横纵坐标。
	noise = (noise * 2.0 - 1.0) * weight; // 转到正负区间再按权重缩放。
	color = saturate(color - color * noise); // 噪声为正处压暗，为负处略提亮。
}
// 远景水噪声：与地形版同源，但按水的透明度加权，并且输入输出带透明度。
vec4 DH_noise(vec4 color, vec3 pos){
	const float steps = OMNI_DH_TEXTURE_NOISE_STEPS; // 网格密度来自选项。
	pos = floor(pos * steps) / steps; // 同样量化到网格。
	float weight = Luminance(color.rgb) * 2.0 - 1.0; // 亮度先映射到负一到一。
	weight = 1.0 - weight * weight; // 取反平方，亮暗交界处权重最大。
	weight *= OMNI_DH_TEXTURE_NOISE_STRENGTH * color.a; // 再乘水的透明度，浅水噪声更弱。
	float noise = fract(sin(dot(pos.xy + fract(sin(pos.z * (91.3458)) * 47453.5453), vec2(12.9898, 78.233))) * 43758.5453); // 与地形版同一个随机函数。
	noise = (noise * 2.0 - 1.0) * weight; // 转到正负区间再按权重缩放。
	color.rgb = saturate(color.rgb - color.rgb * noise); // 只压暗颜色，透明度保持不变。
	return color; // 交回带透明度的结果。
}
#endif // 文件守卫结束。
