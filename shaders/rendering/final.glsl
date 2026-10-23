/*
最终绘制主体：把 iterationT `Lib/Programs/Final.glsl` 的 `PROGRAM_FINAL_2` 段搬进一个文件，直接写屏幕。
来源：`Lib/Programs/Final.glsl` 的 `PROGRAM_FINAL_2` 与 `final.fsh`、`final.vsh` 一比一移植；算法函数来自效果文件。
调用位置：各维度 `final` 入口定义阶段宏、维度宏与 `OMNI_FINAL_PASS` 后引入本文件；
    本文件不写 `#version`，语言版本由入口声明；顶点用 `Lib/Programs/PostVS.glsl` 的整屏三角形。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_FINAL_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件。
输出约定：直接写屏幕 `gl_FragData[0]`，不声明绘制缓冲；原程序在这里做锐化、手与玩家的抗锯齿、抖动与黑边。
关键设计原因与取舍：
    渲染比例等于一时，先按已开启的排除选项决定哪些像素用手或玩家的边缘抗锯齿 `Fxaa`，其余像素做 `CAS` 锐化；
    渲染比例小于一时改用八号画面里的放大结果再锐化（`FidelityFX_FSR1`），所以本程序读过放大输出。
    强光压缩的序号只在十四号分派，这里不做色调整，只做锐化、抖动与黑边，与原程序一致。
    原 `final.fsh` 还引入 `PrintFloat.glsl` 但 `main` 从未调用它；这里照合同引入 `effects/dev/debug.glsl` 并真正调用
    `debugColor` 与 `omniProfiler`，默认关闭，关闭时画面与原程序一致。
    镜头形变（色差、鱼眼、像素化）照 Eclipse `dimensions/final.fsh` 也放在本程序：它们要按畸变坐标重采样已经完整的
    最终画面，只有在这里才有一张写完的显示域画面可读，默认全关时 `LensDistortion` 原样返回，画面与原程序一致。
*/
#ifndef OMNI_FINAL_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_FINAL_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 八号画面在这里要按二维画面采样，和原程序一样在引入加载器输入前打开这个宏，采样器类型才正确。
#define COLORTEX8_2D 1 // 打开后 `colortex8` 由 `common/uniforms.glsl` 声明成二维采样器。

// 加载器输入最先引入，提供画面尺寸、深度与各号画面。
#include "/common/uniforms.glsl"

// ================================ 顶点阶段 ================================
// 原 `final.vsh` 只引入 `Lib/Programs/PostVS.glsl`，顶点铺满屏幕。
#ifdef OMNI_VERTEX
	void main(){
		gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
	}
#endif // 顶点阶段结束。

// ================================ 片元阶段 ================================
#if defined OMNI_FRAGMENT && defined OMNI_FINAL_PASS

	// 本程序按放大后的分辨率工作，坐标与像素尺寸都要用放大后的尺寸算。
	vec2 finalScreenSize = ceil(screenSize / MC_RENDER_QUALITY); // 放大后的目标尺寸。
	vec2 finalPixelSize = 1.0 / finalScreenSize; // 放大后一个像素的坐标大小。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，供效果文件引用。
	vec2 texCoord = gl_FragCoord.xy * finalPixelSize; // 零到一屏幕坐标，黑边与边缘抗锯齿用。

	// 共用数学：亮度、颜色曲线与交错梯度噪声。
	#include "/common/math.glsl"
	// 提供材质编号 `MATID_*`，手与玩家的排除判断用它。
	#include "/bind/ground/material.glsl"
	// 边缘抗锯齿 `Fxaa`；内部再引入坐标换算。
	#include "/rendering/clarity/antialiasing.glsl"
	// 黑边 `BlackBar`。
	#include "/rendering/color/color.glsl"
	// 对比度自适应锐化与放大。
	#include "/rendering/clarity/upscale.glsl"
	// 调试画面与耗时条；原程序一并引入，这里把 `debugColor`、`omniProfiler` 真正接到最终屏幕颜色上。
	#include "/rendering/dev/debug.glsl"
	// 屏幕空间镜头形变：色差、鱼眼与像素化，默认全关时原样返回画面。
	#include "/rendering/lens/distortion.glsl"
	// 受伤与低血量画面表现：受击闪红、低血量红边心跳与死亡暗红，默认关闭时原样返回画面。
	#include "/rendering/lens/hurt.glsl"

	void main(){
		vec3 color = vec3(0.0); // 最终要写的屏幕颜色。

		// 是否需要给手或玩家这类没有时间积累的像素补一次边缘抗锯齿；由排除选项决定，先算成一个布尔量。
		bool useEdgeAA = false;
		#if OMNI_DISABLE_HAND_TAA || defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只有相关排除选项开启时才读材质编号。
			float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读材质编号，判断像素是不是手或玩家。
		#endif
		#if OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都关了时间抗锯齿。
			useEdgeAA = materialIDs == MATID_HAND || materialIDs == MATID_ENTITIES_PLAYER; // 这两类像素没有时间积累。
		#elif OMNI_DISABLE_HAND_TAA // 只关了手的时间抗锯齿。
			useEdgeAA = materialIDs == MATID_HAND; // 手没有时间积累。
		#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只关了玩家的时间抗锯齿与动态模糊。
			useEdgeAA = materialIDs == MATID_ENTITIES_PLAYER; // 玩家没有时间积累。
		#endif

		// 内部渲染比例低于一且开着放大程序时，画面来自放大输出；同样先算成布尔量，让后面的判断是一整条 if。
		bool fsrUpscaled = false;
		#if MC_VERSION >= 11801 // 放大功能只在一点一八点一以后可用。
			#if OMNI_FSR // 开着放大程序。
				fsrUpscaled = MC_RENDER_QUALITY < 1.0; // 内部比例低于一才走放大输出。
			#endif
		#endif

		if (MC_RENDER_QUALITY == 1.0){ // 内部渲染比例为一：画面就是一比一，直接读一号画面并就地锐化。
			color = texelFetch(colortex1, texelCoord, 0).rgb; // 读一号画面的当前像素。
			if (useEdgeAA){ // 手或玩家没有时间积累。
				color = Fxaa(color, texCoord); // 改用边缘抗锯齿补一次。
			}else{ // 其余像素就地锐化。
				#if OMNI_CAS_SHARPNESS > 0 && defined OMNI_TAA && (!OMNI_FSR || MC_VERSION < 11801) // 开了锐化、开着时间抗锯齿，且没有独立的放大程序时。
					color = FidelityFX_CAS(color, texelCoord); // 按十字邻域对比度自适应锐化。
				#endif
			}
		}else if (fsrUpscaled){ // 内部渲染比例低于一：画面已经过放大。
			color = FidelityFX_FSR1(texelCoord); // 从八号画面读放大结果并锐化。
		}else{ // 其它情况：按连续坐标读一号画面。
			color = textureLod(colortex1, texCoord, 0.0).rgb; // 双线性读一号画面。
		}

		// 镜头形变：按选项对最终画面做色差、鱼眼或像素化重采样；三项默认全关时原样返回，画面不变。
		// 源画面跟随前面选出的路径：走放大时是八号放大画面，否则是一号画面，避免形变把放大结果丢掉。
		#if MC_VERSION >= 11801 && OMNI_FSR
			if (fsrUpscaled){ // 最终颜色来自放大画面，形变也要重采样同一张。
				color = LensDistortion(colortex8, color, texCoord);
			}else{ // 未走放大时重采样一号画面。
				color = LensDistortion(colortex1, color, texCoord);
			}
		#else
			color = LensDistortion(colortex1, color, texCoord);
		#endif

		// 受伤、低血量与死亡的画面表现；效果关闭时原样返回，画面不变。
		color = omniHurtEffect(color, texCoord);

		color += InterleavedGradientNoise(gl_FragCoord.xy) * (1.0 / 255.0); // 叠加一点抖动，减小色带。

		color *= BlackBar(OMNI_SCREEN_RATIO); // 按电影比例裁黑边，零表示不加。

		// 调试视图：按选项把最终颜色换成法线、深度或光照图；默认零不改变画面。
		color = debugColor(color, textureLod(depthtex0, texCoord, 0.0).x, texCoord);
		// 帧耗时条：把整帧耗时画在左下角；默认关闭时原样返回。
		color = omniProfiler(color, texCoord);

		gl_FragData[0] = vec4(color, 0.0); // 直接写屏幕。
	}

#endif // 片元阶段结束。
#endif // 文件守卫结束。
