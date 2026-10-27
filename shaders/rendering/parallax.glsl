/*
视差：在地表材质的高度图上沿视线找可见交点，给出偏移后的采样像素，并可算视差自阴影与法线。
来源：照 iterationT `Lib/IndividualFounctions/Parallax.glsl` 一比一移植（原 `effects/ground/material.glsl` 的视差段）。
调用位置：`effects/ground/material.glsl` 在文件末尾显式引入本文件；任何引入材质文件的图形阶段都会带上它，
  但整段只在地形、实体、方块实体、手、蜘蛛眼这些几何片元阶段编译，其它阶段（合成、后处理等）不参与。
可复制示例：
  `ivec2 texel = ParallaxOcclusionMapping(texCoord, tbn, shadowVector, duv1, duv2, normalTex, parallaxShadow);`
设计原因与取舍：
  视差只服务地表材质，所以从材质文件里拆出来，让搜 `parallax` 能直接找到调用与参数换算。
  高度采样、平滑与锐利两套步进、视差阴影都放在 `gfx/parallax.glsl`；本文件只选图集分辨率、回绕方式、噪声与选项。
  选项（`OMNI_PARALLAX_MODE`、`OMNI_PARALLAX_DEPTH` 等）仍留在 `effects/ground/material.glsl`：
  合成阶段（`composite.glsl`）通过引入材质文件读 `OMNI_PARALLAX_MODE` 决定是否应用视差自阴影，选项必须在那个文件可见。
调用前提（iterationT 原样保留）：调用方必须已声明图集采样器 `tex`、`normals`、`gaux4`（方块图集）与视空间位置 `viewPos`，
  地形还要 `flat in` 的 `textureResolution` 与 `atlasSize`。
*/
#ifndef OMNI_PARALLAX_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_PARALLAX_INCLUDED // 置上标记。
// 视差用到共用数学（解码法线）与通用视差算法，显式引入而不依赖调用顺序。
#include "/common/math.glsl"
#include "/gfx/parallax.glsl"
// 视差阴影在开时间抗锯齿时用蓝噪声抖动起点。
#if OMNI_PARALLAX_MODE > 0 && OMNI_PARALLAX_SHADOW && defined OMNI_TAA
#include "/common/noise.glsl"
#endif
// --- 视差：沿视线在高度图里找可见交点，并与视差自阴影配合 ---
// 视差只在几何片元编译：它需要 `dFdx`、图集采样器 `tex`/`normals`/`gaux4` 与视空间位置 `viewPos`，
// 合成阶段没有这些全局量；原程序靠“只有几何片元引入 `Parallax.glsl`”达到同样限制，这里显式写出阶段条件。
#if defined OMNI_FRAGMENT && (defined OMNI_TERRAIN_PASS || defined OMNI_ENTITIES_PASS || defined OMNI_BLOCK_PASS || defined OMNI_HAND_PASS || defined OMNI_SPIDEREYES_PASS)
#if OMNI_PARALLAX_MODE > 1 // 平滑模式：双线性高度采样加二分细化。
// 平滑视差：从当前坐标沿视线步进求交，再做若干次二分细化，最后可选算阴影与法线。
// 图集大小、纹理分辨率与回绕方式在这里按阶段选好，通用库只负责步进。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 normalTex, inout float parallaxShadow){
	float parallaxResolution; // 图块边长，单位像素。
	vec2 parallaxAtlasSize; // 图集像素尺寸。
	bool parallaxIsBlock; // 是否按方块图集回绕。
	#ifdef OMNI_TERRAIN_PASS // 地形用顶点阶段传下的分辨率与图集尺寸。
		parallaxResolution = textureResolution; // 方块纹理分辨率。
		parallaxAtlasSize = vec2(atlasSize); // 方块图集尺寸。
		parallaxIsBlock = true; // 地形恒按方块图集回绕。
	#else // 实体等阶段自己从采样器读图集尺寸。
		parallaxResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		parallaxAtlasSize = vec2(textureSize(tex, 0)); // 实体图集大小由采样器读出。
		parallaxIsBlock = textureSize(gaux4, 0) == ivec2(parallaxAtlasSize); // 图集大小与方块图集一致才回绕。
	#endif
	#ifdef OMNI_PARALLAX_FADE // 需要淡出时交给通用库。
		bool fadeEnabled = true; // 远处淡出视差与阴影。
	#else
		bool fadeEnabled = false; // 不做远处淡出。
	#endif
	#ifdef OMNI_TAA // 开时间抗锯齿时把抖动所需数据交给库，由库在算法内部取蓝噪声。
		bool taa = true; // 逐像素抖动。
	#else
		bool taa = false; // 不开时只多走一步。
	#endif
	return gfx_parallax_smooth(coord, tbnMat, shadowVector, duv1, duv2, viewPos, normals, noisetex,
		parallaxAtlasSize, parallaxResolution, parallaxIsBlock, OMNI_PARALLAX_DEPTH, OMNI_PARALLAX_QUALITY,
		OMNI_PARALLAX_MAX_REFINEMENTS, OMNI_PARALLAX_SHADOW_QUALITY, bool(OMNI_PARALLAX_SHADOW), taa,
		fadeEnabled, ivec2(gl_FragCoord.xy), frameCounter, OMNI_PARALLAX_BASED_NORMAL, normalTex, parallaxShadow); // 步进循环在通用库。
}
#elif OMNI_PARALLAX_MODE == 1 // 锐利模式：逐像素穿越图块，保持像素外观。
// 锐利视差：沿视线逐像素穿过高度图，命中后可选算自阴影与法线。
ivec2 ParallaxOcclusionMapping(vec2 coord, mat3 tbnMat, vec3 shadowVector, vec2 duv1, vec2 duv2, inout vec3 hitNormal, inout float parallaxShadow){
	float parallaxResolution; // 图块边长，单位像素。
	vec2 parallaxAtlasSize; // 图集像素尺寸。
	bool parallaxIsBlock; // 是否按方块图集回绕。
	#ifdef OMNI_TERRAIN_PASS // 地形用顶点阶段传下的分辨率与图集尺寸。
		parallaxResolution = textureResolution; // 方块纹理分辨率。
		parallaxAtlasSize = vec2(atlasSize); // 方块图集尺寸。
		parallaxIsBlock = true; // 地形恒按方块图集回绕。
	#else // 实体等阶段自己从采样器读图集尺寸。
		parallaxResolution = OMNI_ENTITIES_TEXTURE_RESOLUTION; // 实体用整数分辨率。
		parallaxAtlasSize = vec2(textureSize(tex, 0)); // 实体图集大小由采样器读出。
		parallaxIsBlock = textureSize(gaux4, 0) == ivec2(parallaxAtlasSize); // 图集大小与方块图集一致才回绕。
	#endif
	#ifdef OMNI_PARALLAX_FADE // 需要淡出时交给通用库。
		bool fadeEnabled = true; // 远处淡出视差与阴影。
	#else
		bool fadeEnabled = false; // 不做远处淡出。
	#endif
	return gfx_parallax_sharp(coord, tbnMat, shadowVector, duv1, duv2, viewPos, normals,
		parallaxAtlasSize, parallaxResolution, parallaxIsBlock, OMNI_PARALLAX_DEPTH, OMNI_PARALLAX_QUALITY,
		OMNI_PARALLAX_SHADOW_QUALITY, bool(OMNI_PARALLAX_SHADOW), fadeEnabled,
		OMNI_PARALLAX_BASED_NORMAL, hitNormal, parallaxShadow); // 逐像素步进在通用库。
}
#endif // 平滑与锐利两种视差结束。
#endif // 几何片元视差段结束。
#endif // 文件守卫结束。
