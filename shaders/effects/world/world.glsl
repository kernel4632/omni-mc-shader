/*
效果文件 `effects/world/world.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/world.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_WORLD_WORLD_INCLUDED
#define OMNI_EFFECT_WORLD_WORLD_INCLUDED
// @effect {"label":{"zh_cn":"远景","en_us":"Distance"}}
// @option {"label":{"zh_cn":"地形剔除","en_us":"Terrain Culling"},"description":{"zh_cn":"剔除靠近玩家的远景区块，减少和正常区块的混叠；可能让地形出现空缺。","en_us":"Culls distant chunks near the player to reduce overlap with normal chunks; may leave gaps."}}
#define OMNI_DH_TERRAIN_CULLING 1 // [0 1]
// @option {"label":{"zh_cn":"纹理噪声","en_us":"Apply Texture Noise"},"description":{"zh_cn":"给远景表面加逐块噪声，打散纹理感。","en_us":"Adds per-block noise to distant surfaces to break up the texture."}}
#define OMNI_DH_TEXTURE_NOISE
// @option {"label":{"zh_cn":"噪声缩放","en_us":"Noise Scale"},"description":{"zh_cn":"噪声网格的密度，越大噪声越细。","en_us":"Density of the noise grid; higher is finer."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STEPS 4.0 // [2.0 4.0 8.0 16.0 32.0]
// @option {"label":{"zh_cn":"噪声强度","en_us":"Noise Strength"},"description":{"zh_cn":"噪声压暗表面的强度。","en_us":"How strongly the noise darkens the surface."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STRENGTH 0.07 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"区块淡入","en_us":"Distant Chunk Fading"},"description":{"zh_cn":"在远景与近景交界处按距离随机淡出远景区块，减少硬边。零为关闭，一淡出地形与水，二连远景阴影也淡出。默认关闭，画面与不加这项时一致。","en_us":"Randomly fades distant chunks near the boundary to soften hard edges. 0 off, 1 terrain and water, 2 also distant shadows. Off by default."},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"地形与水","en_us":"Terrain & Water"},"2":{"zh_cn":"含阴影","en_us":"With Shadows"}}}
#define OMNI_DH_CHUNK_FADING 0 // [0 1 2]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
世界与远景：给远景地形与水加逐块噪声打散纹理感，按距离剔除挡住近景的远景几何，并让远景区块在边界处淡入。
来源：噪声与剔除段照 iterationT `Lib/Programs/Gbuffers/DH_Terrain_FS.glsl`、`DH_Water_FS.glsl` 一比一移植；
  区块淡入额外照 Eclipse `dimensions/DH_solid.fsh:165-169`、`world0/shadow.fsh:37-43` 移植，见下面函数的出处说明。
调用位置：
  远景地形片元：先 `DHTerrainCulling(viewPos);` 剔除近处远景，再 `DHChunkFading(length(viewPos));` 淡入边界，
    最后在开启噪声时 `DH_noise(albedo, worldPos);`
  远景水片元：先 `DHChunkFading(length(viewPos));` 淡入边界，再在开启噪声时 `tex = DH_noise(color, worldPos);`
  远景阴影片元：`DHShadowChunkFading(length(相机相对世界位置), min(shadowDistance, far));` 淡出阴影边界。
可复制示例：
  `DHTerrainCulling(viewPos);`
  `DHChunkFading(length(viewPos));`
  `DH_noise(albedo, worldPos + cameraPosition + mat3(gbufferModelView) * viewNormal * 0.001);`
  `vec4 tex = DH_noise(color, worldPos + cameraPosition + mat3(gbufferModelView) * tbn[2] * 0.001);`
调用前提（iterationT 原样保留）：地形版 `DH_noise` 依赖调用方声明的 `materialIDs`（判断树叶），
  两个版本都依赖调用方把世界坐标与法线一起传进来，噪声才贴在世界表面上而不是屏幕上；
  `DHChunkFading`、`DHShadowChunkFading` 只有片元阶段能调用，因为它们要用 `discard` 和 `gl_FragCoord`。
设计原因与取舍：噪声先把坐标量化到固定网格再取随机值，网格随 `DH_TEXTURE_NOISE_STEPS` 变密，
  贴图近看才不会糊成一片；权重再按亮度起伏，亮暗交界处噪声最明显，纯色区域几乎不加。
  水版比地形版多乘一层水的透明度，让浅水噪声更弱，深水更明显。
  区块淡入用逐帧变化的随机阈值决定片元是丢是留，靠时间抗锯齿把随机点平均成平滑渐隐，避免突然出现或消失的硬边。
*/
// 噪声用到共用数学与亮度，树叶判定取材质文件的编号，距离剔除读加载器的远景距离。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/bind/gbuffer.glsl"
// 远景阴影淡入要用共用蓝噪声；本文件在两个绘制主体里都只于片元阶段引入，蓝噪声的像素坐标在这里可用。
#include "/common/noise.glsl"
// 远景地形剔除：太近的远景区块与正常区块重叠，直接丢弃，避免两层地形互相闪烁。
// 调用前提：`far` 已由加载器输入声明。
void DHTerrainCulling(vec3 viewPos){
	#if OMNI_DH_TERRAIN_CULLING // 关闭时不剔除。
		if (length(viewPos) < far * 0.7) discard; // 距离小于远景距离的七成就丢掉。
	#endif
}
// 远景淡入的随机阈值：R2 低差异序列，来自 Eclipse `dimensions/DH_solid.fsh:82-87`，逐帧加偏移。
// 为什么逐帧偏移：同一像素每帧取到不同阈值，随机点被时间抗锯齿平均成平滑渐隐，而不是固定噪点。
float DHChunkFadingDither(){
	vec2 coord = gl_FragCoord.xy + float(frameCounter % 40000) * 2.0; // 像素坐标加帧偏移，让阈值每帧变化。
	vec2 alpha = vec2(0.75487765, 0.56984026); // R2 序列的两个常数，照 Eclipse 原样。
	return fract(alpha.x * coord.x + alpha.y * coord.y); // 返回零到一的低差异随机值。
}
// 远景区块淡入：远景在靠近交界时按随机阈值丢弃片元，让区块淡出而不是突然出现或消失。
// 出处：Eclipse `lib/settings.glsl:1093`（`DH_CHUNK_FADING` 取值零一二）与 `dimensions/DH_solid.fsh:165-169`，公式照抄。
// 近似说明：Eclipse 的 `far` 是它远景程序的远裁剪面，这里套用近景远裁剪面 `far`（与 `DHTerrainCulling` 同口径），属按距离的近似。
// 调用前提：只有片元阶段能调用，因为要用 `discard` 与 `gl_FragCoord`；`far` 已由加载器输入声明。
void DHChunkFading(float viewDist){
	#if OMNI_DH_CHUNK_FADING > 0 // 关闭时整段不编译。
		float ditherFade = smoothstep(0.86 * far, 0.9 * far, viewDist); // 交界附近渐入的阈值。
		if (step(DHChunkFadingDither() / ditherFade, ditherFade) == 0.0) discard; // 随机舍弃交界附近的区块。
	#endif
}
// 远景阴影淡入：远景阴影靠近阴影距离边界时按随机阈值淡出，避免阴影图边缘出现硬边。
// 出处：Eclipse `world0/shadow.fsh:37-43`，公式照抄；随机阈值改用共用蓝噪声，属按距离的近似。
// 调用前提：只有片元阶段能调用；`shadowDistance` 由 `effects/shadow/shadow.glsl` 提供，`BlueNoise()` 由 `common/noise.glsl` 提供。
void DHShadowChunkFading(float worldDist, float fadeLimit){
	#if OMNI_DH_CHUNK_FADING > 1 // 只有开到二档才淡出远景阴影。
		float ditherFade = smoothstep(0.93 * fadeLimit, fadeLimit, worldDist); // 阴影边界附近渐出的阈值。
		if (step(ditherFade, BlueNoise().x) == 0.0) discard; // 随机舍弃边界附近的远景阴影。
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
#endif // OMNI_EFFECT_WORLD_WORLD_INCLUDED
