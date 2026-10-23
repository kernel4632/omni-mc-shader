/*
环境光与遮蔽的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lighting/ambient.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_LIGHTING_AMBIENT_INCLUDED
#define OMNI_BIND_LIGHTING_AMBIENT_INCLUDED
#include "/effects/lighting/ambient.glsl"
/*
环境光与遮蔽：反射阴影图全局光的时间与空间滤波，以及地平线环境遮蔽，按 iterationT 原算法移植。
调用位置：延迟一号主体算全局光时间滤波时调用 `GI_TemporalFilter`；
    延迟二号与延迟四号主体 `RenderGISpatialFilter` 取深度后调用 `GI_SpatialFilter`、`GroundTruthBasedAmbientOcclusion`；
    合成主体把遮蔽乘到最终颜色上并做多弹射补偿时调用 `GTAOMultiBounce`。
本文件的相机速度函数叫 `GiCameraVelocity`：它按选项把手与玩家排除出全局光历史重投影。
  同名用途在 `effects/clarity/antialiasing.glsl` 是 `TaaCameraVelocity`、在 `effects/lens/lens.glsl` 是
  `MotionBlurCameraVelocity`，三份实现不同，按 iterationT 原程序各留一份，名字体现用途以区分。
可复制示例：
    `vec3 gi = GI_SpatialFilter(dist, normal, viewDir);`
    `float ao = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal);`
    `vec3 ao = GTAOMultiBounce(gi.a, gbuffer.albedo);`
设计原因与取舍：
    全局光只在需要时才编译：时间滤波与空间滤波各自放在对应程序宏里，避免在别的程序里凭空多出一堆采样。
    反射阴影图全局光与地平线遮蔽互相独立，各自带开关，关闭时整支计算不编译。
    延迟二号（主世界）与延迟四号（末地）的主体 `RenderGISpatialFilter` 也合在本文件：两个程序逐行相同，
    只有起始深度取自哪张深度图不同；把它作为参数传入，两处共用同一段，不必另开一个只有几行的程序体文件。
    调用前提（iterationT 原样保留）：冻结 `OMNI_DEFERRED1_PASS` 的程序要先声明 `shadowtex0`、`shadowtex1`、
    `shadowcolor0`、`shadowcolor1` 与 `texelCoord`、`texCoord`，并让材质编号 `MATID_ENTITIES_PLAYER` 可见；
    `OMNI_DEFERRED2_PASS` 的程序要先声明 `gbufferProjection`、`depthtex1`、`texCoord`；
    坐标换算按合同要先引入定义 `OMNI_TAA` 的效果文件。为什么这里不直接引入 `effects/ground/material.glsl`：
    那份文件带只在几何阶段存在的贴图取样器，延迟程序引不动，材质编号由绘制主体保证可见。
    末地把延迟程序重新排序（时间滤波在二号、空间滤波在四号），所以本文件的编译条件同时认末地对应的程序宏。
    本文件按算法拆到同目录：全局光的反弹、时间滤波与空间滤波在 `gi.glsl`，地平线遮蔽与多弹射在 `gtao.glsl`；延迟主体 `RenderGISpatialFilter` 留在本文件；引入顺序与拆分前逐字一致。
*/
// 相对坐标、数学、噪声与共享效果按下述顺序引入；本文件末尾的算法只在这里定义一次。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/bind/clarity/antialiasing.glsl"
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
#include "/bind/shadow/shadow.glsl"
// 反射阴影图全局光：反弹、时间滤波与空间滤波。
#include "/bind/lighting/gi.glsl"
// 地平线遮蔽与多弹射补偿。
#include "/bind/lighting/gtao.glsl"
// --- 延迟二号（主世界）与延迟四号（末地）的片元主体：空间滤波与地平线遮蔽 ---
// 放在遮蔽与空间滤波函数之后，才能调用它们；按程序宏隔开，只有这两个程序需要它。
// `startDepth` 由调用方传：主世界延迟二号用不含半透明的深度图，末地延迟四号用含半透明的深度图。
#if (defined OMNI_DEFERRED2_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED4_PASS)
// 输入起始深度，返回一号画面的内容：有几何的像素算遮蔽与全局光，天空像素保持无全局光、遮蔽为一。
vec4 RenderGISpatialFilter(float startDepth){
	float depth = startDepth; // 本像素起始深度，由调用方按程序选择不含或含半透明的深度图。
	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置，自动撤销抖动。

	#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
		#if OMNI_DH_AO // 只有开启远景遮蔽才把远景当作有几何，关闭时远景像素按天空处理。
			if (depth == 1.0){ // 天空像素改读远景深度。
				depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
				viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
			}
		#endif
	#endif

	vec4 gi = vec4(0.0, 0.0, 0.0, 1.0); // 默认没有全局光，遮蔽为一。

	if (depth < 1.0){ // 有几何才算全局光与遮蔽。
		vec3 viewDir = normalize(viewPos); // 视线方向。
		vec3 normal = DecodeNormal(texelFetch(colortex3, texelCoord, 0).xy); // 从三号画面解出法线。

		#ifdef OMNI_GTAO // 打开地平线遮蔽才算。
			if (-viewPos.z > 0.15) gi.a = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal); // 太近的像素不算遮蔽。
		#endif

		#if OMNI_GI_RSM // 打开全局光反弹才算。
			gi.rgb = GI_SpatialFilter(-viewPos.z, normal, viewDir); // 半分辨率全局光做空间滤波。
		#endif
	}

	return gi; // 返回一号画面的内容。
}
#endif // 延迟阶段主体结束。
#endif // OMNI_BIND_LIGHTING_AMBIENT_INCLUDED
