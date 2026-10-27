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
// --- 镜头眩光与光斑 ---
// 只在开启眩光或光斑时编译这一段。
#if OMNI_LENS_GLARE || OMNI_LENS_FLARE
	#define DISTORTION_BARREL 1.0 // 桶形畸变强度，让鬼影沿弧线排布。

	// 镜头光斑主入口：按太阳在屏幕上的位置铺开眩光与鬼影，并按太阳可见度与雾浓淡衰减。
	// 输出按管线编码，写进三号画面，稍后由八号与十四号阶段叠加。
	vec3 LensFlare(){
		vec3 lf = vec3(0.0); // 累加结果。
		vec2 coord = texCoord - 0.5; // 当前点相对中心。
		vec2 sunPos = sunCoord - 0.5; // 太阳相对中心。
		coord.x *= aspectRatio; // 按宽高比修正成圆。
		sunPos.x *= aspectRatio; // 太阳位置同样修正。
		float fovFactor = max(gbufferProjection[1][1], 2.0); // 由投影矩阵估计视场，给一个下限。
		#if OMNI_LENS_GLARE // 眩光：沿光线方向拉出细长亮纹。
			vec2 v = coord - sunPos; // 当前点到太阳的方向。
			float dist = length(v); // 距离。
			float gDist = dist * 13.0 / fovFactor; // 按视场归一化。
			float phase = atan2(v) + 0.131; // 方向角加一个固定偏移。
			float gl = 2.0 - saturate(gDist) + sin(phase * 12.0) * saturate(gDist * 2.5 - 0.2); // 细长亮纹。
			gl = gl * gl; // 平方加强。
			gDist = gDist * gDist; // 距离平方。
			gl *= 8e-5 / (gDist * gDist); // 按距离衰减。
			gl = min(gl, 200.0); // 设上限避免过亮。
			lf += vec3(gl * OMNI_GLARE_BRIGHTNESS); // 按眩光亮度累加。
		#endif
		#if OMNI_LENS_FLARE // 光斑：一组鬼影、两个光环和若干散点。
			float size = 0.5 * fovFactor; // 光斑整体大小。
			vec3 fl = vec3(0.0); // 光斑累加。
			fl += ogxGlareOrb(coord, sunPos, 0.0, size * 0.01, DISTORTION_BARREL) * 0.1; // 圆形鬼影。
			fl += ogxGlareRing(coord, sunPos,  1.0, 0.02, 1.4) * 0.01; // 远端光环。
			fl += ogxGlareRing(coord, sunPos, -1.0, 0.02, 1.4) * 0.01; // 近端光环。
			fl += ogxGlareFlare(coord, sunPos, -2.00, 0.05, size * 0.05, DISTORTION_BARREL) * 0.5; // 一抹大鬼影。
			fl += ogxGlareFlare(coord, sunPos, -0.90, 0.02, size * 0.03, DISTORTION_BARREL) * 0.3; // 散点。
			fl += ogxGlareFlare(coord, sunPos, -0.70, 0.01, size * 0.06, DISTORTION_BARREL) * 0.5; // 散点。
			fl += ogxGlareFlare(coord, sunPos, -0.55, 0.02, size * 0.02, DISTORTION_BARREL) * 0.2; // 散点。
			fl += ogxGlareFlare(coord, sunPos, -0.35, 0.02, size * 0.04, DISTORTION_BARREL) * 0.7; // 散点。
			fl += ogxGlareFlare(coord, sunPos, -0.25, 0.01, size * 0.15, DISTORTION_BARREL) * vec3(0.3, 0.4, 0.38); // 偏青的大鬼影。
			fl += ogxGlareFlare(coord, sunPos, -0.25, 0.02, size * 0.08, DISTORTION_BARREL) * 0.2; // 散点。
			fl += ogxGlareFlare(coord, sunPos,  0.05, 0.01, size * 0.03, DISTORTION_BARREL) * 0.1; // 散点。
			fl += ogxGlareFlare(coord, sunPos,  0.30, 0.02, size * 0.20, DISTORTION_BARREL) * vec3(0.2, 0.18, 0.14); // 偏暖的鬼影。
			fl += ogxGlareFlare(coord, sunPos,  1.20, 0.03, size * 0.10, DISTORTION_BARREL) * 0.2; // 散点。
			lf += fl * (OMNI_FLARE_BRIGHTNESS * 0.3); // 按光斑亮度累加。
		#endif
		lf *= colorSunlight * (sunVisibility * saturate(exp2(1.0 - OMNI_VFOG_DENSITY * 20.0)) / MAIN_OUTPUT_FACTOR); // 按阳光颜色、可见度与雾浓淡衰减。
		return LinearToCurve(lf); // 按管线编码返回。
	}
#endif // 眩光与光斑结束。

// --- 参考签名兼容层：参考的镜头函数直接读全局畸变强度 ---
vec2 GetDistOffset(vec2 uv, vec2 pxoffset){ return ogxGlareDistOffset(uv, pxoffset, 1.0); }
vec3 flare(vec2 uv, vec2 pos, float dist, float size, float chromaOffset){
	return ogxGlareFlare(uv, pos, dist, chromaOffset, size, 1.0);
}
vec3 orb(vec2 uv, vec2 pos, float dist, float size){ return ogxGlareOrb(uv, pos, dist, size, 1.0); }

#endif // OMNI_LENS_GLARE_INCLUDED
