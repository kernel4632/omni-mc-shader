/*
效果文件 `effects/lens/glare.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lens/glare.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_LENS_GLARE_INCLUDED
#define OMNI_LENS_GLARE_INCLUDED
/*
镜头眩光与光斑：沿光线方向拉出细长亮纹，再叠一组鬼影、光环与散点。
来源 iterationT `LensGlareFlare.glsl`。
调用位置：由 `effects/lens/lens.glsl` 引入；合成阶段调用 `LensFlare`。
可复制示例：`vec3 glare = LensFlare();`
设计原因与取舍：眩光与光斑共用同一批光点和色散取样，合在一个文件；两者各自带开关，关闭时整段不编译。
*/
// 眩光与光斑的形状计算放在通用库，这里只传屏幕位置、太阳位置与畸变强度。
#include "/omni-gfx/post/post.glsl"
// 镜头光斑、色散环与眩光主流程的唯一实现在通用镜头模块。
#include "/omni-gfx/lens/lens.glsl"
// --- 镜头眩光与光斑 ---
// 只在开启眩光或光斑时编译这一段。
#if OMNI_LENS_GLARE || OMNI_LENS_FLARE
	#define DISTORTION_BARREL 1.0 // 桶形畸变强度，让鬼影沿弧线排布。

	// 镜头光斑主入口：按太阳在屏幕上的位置铺开眩光与鬼影，并按太阳可见度与雾浓淡衰减。
	// 输出按管线编码，写进三号画面，稍后由八号与十四号阶段叠加。
	vec3 LensFlare(){
		return ogxLensFlare(texCoord, sunCoord, aspectRatio, gbufferProjection[1][1], bool(OMNI_LENS_GLARE),
			bool(OMNI_LENS_FLARE), OMNI_GLARE_BRIGHTNESS, OMNI_FLARE_BRIGHTNESS, colorSunlight, sunVisibility,
			OMNI_VFOG_DENSITY, MAIN_OUTPUT_FACTOR); // 整条光斑链在通用库，选项在这里传入。
	}
#endif // 眩光与光斑结束。

// --- 参考签名兼容层：参考的镜头函数直接读全局畸变强度 ---
// 参考只传偏移，不传桶形强度；这里固定为一，保持旧调用点的形状。
vec2 GetDistOffset(vec2 uv, vec2 pxoffset){ return ogxLensDistOffset(uv, pxoffset, 1.0); }
// 参考的单个光斑没有桶形参数，兼容层同样固定为一。
vec3 flare(vec2 uv, vec2 pos, float dist, float size, float chromaOffset){
	return ogxLensFlareSpot(uv, pos, dist, chromaOffset, size, 1.0); // 色散光斑在通用镜头模块。
}
// 参考的鬼影串只给位置与大小，桶形弯曲固定为一。
vec3 orb(vec2 uv, vec2 pos, float dist, float size){ return ogxLensOrb(uv, pos, dist, size, 1.0); }

#endif // OMNI_LENS_GLARE_INCLUDED
