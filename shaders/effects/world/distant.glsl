/*
效果文件 `effects/world/distant.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/distant.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_WORLD_DISTANT_INCLUDED
#define OMNI_EFFECT_WORLD_DISTANT_INCLUDED
// @effect {"label":{"zh_cn":"远景附加","en_us":"Distant extras"}}
// @option {"label":{"zh_cn":"远景过绘防护","en_us":"Distant overdraw prevention"},"description":{"zh_cn":"丢弃已被近景区块画好的近距离远景块，减少重复绘制；默认关闭，开启后近处远景不再绘制。","en_us":"Discards distant chunks already covered by near chunks to cut overdraw; off by default."}}
#define OMNI_DH_OVERDRAW_PREVENTION 0 // [0 1]
// @option {"label":{"zh_cn":"过绘防护距离","en_us":"Overdraw distance"},"description":{"zh_cn":"过绘防护的作用半径，单位方块；零表示跟随远景距离。只在开启过绘防护时生效。","en_us":"Radius of overdraw prevention in blocks; 0 follows the view distance. Only used when overdraw prevention is on."},"slider":true}
#define OMNI_DH_OVERDRAW_MAX_DISTANCE 128 // [0 32 48 64 80 96 112 128 144 160 176 192 208 224 240 256]
// @option {"label":{"zh_cn":"噪声远距衰减","en_us":"Noise dropoff"},"description":{"zh_cn":"远景噪声超过该距离后逐渐消失，单位方块；零表示不衰减，噪声整片保留。","en_us":"Distant noise fades out beyond this distance in blocks; 0 keeps the noise everywhere."},"slider":true}
#define OMNI_DH_NOISE_DROPOFF 0 // [0 128 256 512 768 1024 1536 2048 3072 4096 8192]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
远景附加能力：给远景地形与水加两个可选处理和两个可调参数，默认都不改变画面。
来源：过绘防护照 Eclipse `lib/settings.glsl:1090-1091`、`dimensions/DH_solid.fsh:171-182`、`dimensions/DH_translucent.fsh:311-319`；
  噪声远距衰减照 Eclipse `dimensions/DH_solid.fsh:150-153`（原 `NOISE_DROPOFF`）。
调用位置：由 `rendering/distant.glsl` 的远景地形与远景水片元各调用一次，位置见该文件。
可复制示例：
  `omniDHTerrainOverdrawPrevention(length(viewPos));` 远景地形过绘防护。
  `omniDHWaterOverdrawPrevention(length(viewPos));` 远景水过绘防护。
  `albedo = omniDHNoiseDropoff(albedo, albedoClean, length(viewPos));` 地形噪声远距衰减。
  `tex = omniDHNoiseDropoff(tex, texClean, length(viewPos));` 水噪声远距衰减。
调用前提：只能在片元阶段调用，因为过绘防护要用 `discard`；近景远裁剪面 `far` 由加载器输入声明。
设计原因与取舍：
  过绘防护丢掉已经由近景区块画好的近距离远景块，减少同一片像素被重复绘制，默认关闭以免改变现有画面。
  为什么用近景远裁剪面 `far` 而不是远景远裁剪面：与 `effects/world/world.glsl` 的区块淡入同口径，属按距离的近似。
  噪声远距衰减让远景噪声随距离变淡，避免远处出现密集噪点；参数为零表示关闭，此时噪声整片保留，与原来一致。
*/
// 过绘防护要用近景远裁剪面，共用数学提供 `saturate`。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 过绘防护的距离阈值：近景远裁剪面减去一段余量，再夹到下限与上限之间。
// 为什么减余量：远裁剪面附近有浮点和墙块，留一段避免把仍然可见的远景误丢。
// 为什么上限来自选项：选项为零表示跟随远景距离，此时上限就是远裁剪面本身。
float omniDHOverdrawLimit(float margin, float minLimit){
	#if OMNI_DH_OVERDRAW_MAX_DISTANCE == 0 // 零表示不设上限。
		float maxOverdrawDistance = far; // 上限取远裁剪面。
	#else // 其余按玩家距离。
		float maxOverdrawDistance = float(OMNI_DH_OVERDRAW_MAX_DISTANCE); // 上限取选项值。
	#endif
	return clamp(far - margin, minLimit, maxOverdrawDistance); // 得到丢弃近距离远景的距离。
}
// 远景地形过绘防护：距离小于阈值的远景地形直接丢弃，交给近景区块绘制。
void omniDHTerrainOverdrawPrevention(float viewDist){
	#if OMNI_DH_OVERDRAW_PREVENTION // 关闭时不编译下面的判断，画面不变。
		if (viewDist < omniDHOverdrawLimit(32.0, 32.0)) discard; // 地形用三十二方块余量与下限，照 Eclipse 原值。
	#endif
}
// 远景水过绘防护：水面没有近景剔除，单独按更靠外的阈值丢弃。
void omniDHWaterOverdrawPrevention(float viewDist){
	#if OMNI_DH_OVERDRAW_PREVENTION // 关闭时不编译。
		if (viewDist < omniDHOverdrawLimit(64.0, 16.0)) discard; // 水用六十四方块余量与十六下限，照 Eclipse 原值。
	#endif
}
// 远景地形噪声远距衰减：按距离把带噪声的颜色混回原色，越远噪声越淡。
vec3 omniDHNoiseDropoff(vec3 noisy, vec3 original, float viewDist){
	#if OMNI_DH_NOISE_DROPOFF > 0 // 零表示不衰减。
		float fade = saturate(viewDist / float(OMNI_DH_NOISE_DROPOFF)); // 距离占比，超过衰减距离后为一。
		noisy = mix(noisy, original, fade); // 按占比把噪声混回原色。
	#endif
	return noisy; // 返回处理后的颜色。
}
// 远景水噪声远距衰减：与地形同理，只改颜色，透明度保持不变。
vec4 omniDHNoiseDropoff(vec4 noisy, vec4 original, float viewDist){
	#if OMNI_DH_NOISE_DROPOFF > 0 // 零表示不衰减。
		float fade = saturate(viewDist / float(OMNI_DH_NOISE_DROPOFF)); // 距离占比。
		noisy.rgb = mix(noisy.rgb, original.rgb, fade); // 只混颜色通道，保留水的透明度。
	#endif
	return noisy; // 返回处理后的颜色。
}
#endif // OMNI_EFFECT_WORLD_DISTANT_INCLUDED
