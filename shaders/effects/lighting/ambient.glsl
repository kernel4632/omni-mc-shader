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
#ifndef OMNI_AMBIENT_INCLUDED
#define OMNI_AMBIENT_INCLUDED
// @effect {"label":{"zh_cn":"环境光与遮蔽","en_us":"GI & AO"}}
// @option {"label":{"zh_cn":"全局光反射阴影图","en_us":"GI RSM"},"description":{"zh_cn":"用阴影图里可见的表面做一次屏幕外反弹，给阴影补光。","en_us":"Bounces light from surfaces visible in the shadow map to fill in shadows."}}
#define OMNI_GI_RSM
// @option {"label":{"zh_cn":"全局光质量","en_us":"GI Quality"},"description":{"zh_cn":"每个像素的反弹采样次数，越高越干净也越慢。","en_us":"Bounce samples per pixel; higher is cleaner and slower."},"slider":true}
#define OMNI_GI_QUALITY 16 // [4 8 12 16 24 32 48 64 96 128]
// @option {"label":{"zh_cn":"全局光半径","en_us":"GI Radius"},"description":{"zh_cn":"反弹搜索的半径，越大补光越广。","en_us":"Search radius of the bounce; larger spreads more light."},"slider":true}
#define OMNI_GI_RADIUS 7.0 // [1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光亮度","en_us":"GI Brightness"},"description":{"zh_cn":"反弹补光的整体亮度。","en_us":"Overall brightness of the bounce light."},"slider":true}
#define OMNI_GI_BRIGHTNESS 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"全局光渲染分辨率","en_us":"GI Render Resolution"},"description":{"zh_cn":"全局光在多少分辨率上算，半分辨率更省。","en_us":"Resolution the GI is computed at; half is cheaper."},"values":{"0.25":{"zh_cn":"四分之一","en_us":"Quarter"},"0.5":{"zh_cn":"一半","en_us":"Half"}}}
#define OMNI_GI_RENDER_RESOLUTION 0.5 // [0.25 0.5]
// @option {"label":{"zh_cn":"全局光衰减","en_us":"GI Falloff"},"description":{"zh_cn":"反弹随距离衰减的指数，越大越只影响近处。","en_us":"Distance falloff exponent of the bounce; higher keeps it near."},"slider":true}
#define OMNI_GI_FALLOFF 1.1 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"全局光天光衰减","en_us":"GI Skylight Falloff"},"description":{"zh_cn":"反弹随天空光等级衰减，避免洞穴里也被补到光。","en_us":"Fades the bounce with skylight so caves are not lit."}}
#define OMNI_GI_SKYLIGHT_FALLOFF
// @option {"label":{"zh_cn":"关闭手部全局光","en_us":"Disable Hand GI"},"description":{"zh_cn":"手不接收屏幕外的反弹补光。","en_us":"Keeps the hand from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_HAND_GI
// @option {"label":{"zh_cn":"关闭手部全局光速度","en_us":"Disable Hand GI Velocity"},"description":{"zh_cn":"手不参与全局光的历史重投影，减少手的拖影。","en_us":"Excludes the hand from GI history reprojection to reduce smearing."}}
//#define OMNI_DISABLE_HAND_GI_VELOCITY
// @option {"label":{"zh_cn":"关闭玩家全局光","en_us":"Disable Player GI"},"description":{"zh_cn":"玩家角色不接收屏幕外的反弹补光。","en_us":"Keeps the player from receiving off-screen bounce light."}}
//#define OMNI_DISABLE_PLAYER_GI
// @option {"label":{"zh_cn":"关闭玩家全局光速度","en_us":"Disable Player GI Velocity"},"description":{"zh_cn":"玩家不参与全局光的历史重投影。","en_us":"Excludes the player from GI history reprojection."}}
//#define OMNI_DISABLE_PLAYER_GI_VELOCITY
// @option {"label":{"zh_cn":"地平线遮蔽","en_us":"GTAO"},"description":{"zh_cn":"地面真相环境遮蔽，墙角缝隙变暗。","en_us":"Ground-truth ambient occlusion; darkens corners and creases."}}
#define OMNI_GTAO
// @option {"label":{"zh_cn":"遮蔽质量","en_us":"GTAO Quality"},"description":{"zh_cn":"环绕视线的切片数，越高越稳也越慢。","en_us":"Slices around the view; higher is steadier and slower."},"slider":true}
#define OMNI_GTAO_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"遮蔽切片质量","en_us":"GTAO Slice Quality"},"description":{"zh_cn":"每个切片的搜索步数。","en_us":"Search steps per slice."},"slider":true}
#define OMNI_GTAO_SLICE_QUALITY 3 // [1 2 3 4 5 6 8 10 15 20]
// @option {"label":{"zh_cn":"遮蔽半径模式","en_us":"GTAO Radius Mode"},"description":{"zh_cn":"零为世界半径，一为屏幕半径。","en_us":"Zero uses world radius, one uses screen radius."},"values":{"0":{"zh_cn":"世界","en_us":"World"},"1":{"zh_cn":"屏幕","en_us":"Screen"}}}
#define OMNI_GTAO_RADIUS_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"遮蔽世界半径","en_us":"GTAO World Radius"},"description":{"zh_cn":"世界半径模式下的取样半径，单位方块。","en_us":"Sample radius in world-radius mode, in blocks."},"slider":true}
#define OMNI_GTAO_WORLD_RADIUS 2.0 // [0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0]
// @option {"label":{"zh_cn":"遮蔽屏幕半径","en_us":"GTAO Screen Radius"},"description":{"zh_cn":"屏幕半径模式下的取样半径，单位屏幕比例。","en_us":"Sample radius in screen-radius mode, in screen fraction."},"slider":true}
#define OMNI_GTAO_SCREEN_RADIUS 0.05 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"遮蔽最大半径","en_us":"GTAO Max Radius"},"description":{"zh_cn":"屏幕半径上限，避免近处取样范围过大。","en_us":"Cap on the screen radius so near geometry does not over-sample."},"slider":true}
#define OMNI_GTAO_MAX_RADIUS 0.1 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"遮蔽衰减起点","en_us":"GTAO Falloff Start"},"description":{"zh_cn":"远处样本开始衰减的位置比例。","en_us":"Fraction at which far samples start to fade."},"slider":true}
#define OMNI_GTAO_FALLOFF_START 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"遮蔽强度","en_us":"GTAO Strength"},"description":{"zh_cn":"遮蔽压暗的强度，取零等于关闭。","en_us":"Darkening strength of the AO; zero disables it."},"slider":true}
#define OMNI_GTAO_STRENGTH 0.95 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"遮蔽多弹射","en_us":"GTAO Multibounce"},"description":{"zh_cn":"按表面底色给遮蔽做一次多弹射补偿，暗部不会压死。","en_us":"Multi-bounce correction using albedo so dark areas do not crush."}}
#define OMNI_GTAO_MULTIBOUNCE
// @option {"label":{"zh_cn":"远景遮蔽","en_us":"Distant AO"},"description":{"zh_cn":"让远景地形参与地平线遮蔽与全局光；关闭后远景不接收遮蔽，近景也不会被远景挡住。默认开启，与原来一致。来源 Eclipse 的 DH_AMBIENT_OCCLUSION。","en_us":"Lets distant terrain take part in ground-truth AO and GI; when off, distant chunks get no occlusion and nearby pixels are not occluded by distant geometry. On by default. Ports Eclipse's DH_AMBIENT_OCCLUSION."}}
#define OMNI_DH_AO
// 相对坐标、数学、噪声与共享效果按下述顺序引入；本文件末尾的算法只在这里定义一次。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
#include "/effects/shadow/shadow.glsl"
// 反射阴影图全局光：反弹、时间滤波与空间滤波。
#include "/effects/lighting/gi.glsl"
// 地平线遮蔽与多弹射补偿。
#include "/effects/lighting/gtao.glsl"
// --- 延迟二号（主世界）与延迟四号（末地）的片元主体：空间滤波与地平线遮蔽 ---
// 放在遮蔽与空间滤波函数之后，才能调用它们；按程序宏隔开，只有这两个程序需要它。
// `startDepth` 由调用方传：主世界延迟二号用不含半透明的深度图，末地延迟四号用含半透明的深度图。
#if (defined OMNI_DEFERRED2_PASS && !defined OMNI_END) || (defined OMNI_END && defined OMNI_DEFERRED4_PASS)
// 输入起始深度，返回一号画面的内容：有几何的像素算遮蔽与全局光，天空像素保持无全局光、遮蔽为一。
vec4 RenderGISpatialFilter(float startDepth){
	float depth = startDepth; // 本像素起始深度，由调用方按程序选择不含或含半透明的深度图。
	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置，自动撤销抖动。

	#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
		#ifdef OMNI_DH_AO // 只有开启远景遮蔽才把远景当作有几何，关闭时远景像素按天空处理。
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

		#ifdef OMNI_GI_RSM // 打开全局光反弹才算。
			gi.rgb = GI_SpatialFilter(-viewPos.z, normal, viewDir); // 半分辨率全局光做空间滤波。
		#endif
	}

	return gi; // 返回一号画面的内容。
}
#endif // 延迟阶段主体结束。
#endif // 文件守卫结束。
