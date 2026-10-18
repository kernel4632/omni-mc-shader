/*
时间抗锯齿：用上一帧画面按相机运动重投影到当前帧，再按邻域颜色范围裁剪后混合，抹平边缘与噪点。
来源：时间重投影、邻域裁剪、颜色空间转换与深度取样照 iterationT `Lib/BasicFounctions/TAA.glsl` 一比一移植；
  最终的边缘抗锯齿 `Fxaa` 照 iterationT `Lib/Programs/Final.glsl` 一比一移植。
调用位置：
  合成七号片元调用 `WriteTaaHistory`（本文件末尾，按 `OMNI_COMPOSITE7_PASS` 隔开），把重投影后的颜色写回七号画面作为下一帧历史；
  final 片元在关闭手或玩家抗锯齿时对被排除的像素调用 `Fxaa` 补一次边缘抗锯齿。
本文件的相机速度函数叫 `TaaCameraVelocity`：它同时回填重投影要用的深度，并区分玻璃与冰。
  同名用途在 `effects/lighting/ambient.glsl` 是 `GiCameraVelocity`、在 `effects/lens/lens.glsl` 是
  `MotionBlurCameraVelocity`，三份实现不同，按 iterationT 原程序各留一份，名字体现用途以区分。
可复制示例：
  `vec4 taa = TemporalReprojection(taaTexCoord, TaaCameraVelocity(depth, materialIDs), depth);`
  `color = Fxaa(color, taaTexCoord);`
  `compositeOutput7 = WriteTaaHistory();`  合成七号把历史写成七号画面的内容。
调用前提（iterationT 原样保留）：
  坐标换算函数按 `OMNI_TAA` 决定是否撤销本帧抖动，所以任何用到坐标换算的主体都必须先引入本文件；
  时间重投影依赖调用方先声明 `taaTexelCoord`、`taaTexCoord`，并让材质编号 `MATID_*` 可见；
  `Fxaa` 读取一号画面与 `pixelSize`。
设计原因与取舍：
  只有相机重投影，没有实体速度缓冲，动态物体会靠邻域裁剪与深度比较把过时历史挡掉；
  历史可信度由混合权重、运动量和深度差共同决定，任一项对不上就少用或不用历史，避免拖影。
  下界的时间抗锯齿与主世界不同（参考深度打包进七号画面透明度通道），按 `OMNI_NETHER` 分支在本文件内提供另一套取样、邻域统计与重投影；
  合成七号的主体 `WriteTaaHistory` 与算法合在本文件：它只做选项分派与写出，拆成另一个文件没有额外好处；
  按 `OMNI_COMPOSITE7_PASS` 隔开，因为本文件还被地形、阴影、延迟等程序引入，它们没有合成七号的输入。
    本文件按算法拆到同目录：TAA 核心在 `taa.glsl`，FXAA 在 `fxaa.glsl`；程序主体 `WriteTaaHistory` 留在本文件；引入顺序与拆分前逐字一致。
*/
#ifndef OMNI_ANTIALIASING_INCLUDED // 只引入一次，避免宏与函数重复定义。
#define OMNI_ANTIALIASING_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"时域抗锯齿","en_us":"Temporal AA"}}
// @option {"label":{"zh_cn":"时间边缘平滑","en_us":"TAA"},"description":{"zh_cn":"用上一帧历史把边缘和噪点叠平滑；开启前请先在着色器设置里打开抗锯齿。","en_us":"Uses previous-frame history to smooth edges and noise; enable antialiasing in shader settings first."}}
#define OMNI_TAA
// @option {"label": {"zh_cn": "远景也参与抖动", "en_us": "Jitter distant terrain"}, "description": {"zh_cn": "远景地块随近景一起做逐帧抖动，交界处才和近景对齐；关掉后远景不抖、更稳，但交界可能与近景错半像素。默认开启。来源 Eclipse 的 DH_TAA_JITTER。", "en_us": "Lets distant chunks share the per-frame jitter with nearby terrain so the boundary stays aligned; off keeps distant terrain steadier but may misalign it by half a pixel. On by default. Ports Eclipse's DH_TAA_JITTER."}}
#define OMNI_DH_TAA_JITTER 1 // [0 1]
// @option {"label": {"zh_cn": "历史混合权重", "en_us": "History Blend Weight"}, "slider": true, "description": {"zh_cn": "越高画面越稳、越容易留轻微拖影。", "en_us": "Higher is steadier but more prone to slight smearing."}}
#define OMNI_TAA_BLENDWEIGHT 0.97 // [0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label": {"zh_cn": "历史裁剪强度", "en_us": "History Clip Aggression"}, "slider": true, "description": {"zh_cn": "邻域裁剪的松紧，越大越容易拒绝历史、减少拖影。", "en_us": "Tightness of neighbourhood clipping; higher rejects more history and reduces smearing."}}
#define OMNI_TAA_AGGRESSION 2.0 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"关闭手部边缘平滑","en_us":"Disable Hand TAA"},"description":{"zh_cn":"手不参与时间抗锯齿，减少手的拖影；这类像素改用边缘抗锯齿。","en_us":"Excludes the hand from TAA to reduce smearing; those pixels fall back to edge AA."}}
#define OMNI_DISABLE_HAND_TAA 0 // [0 1]
// @option {"label":{"zh_cn":"关闭玩家边缘平滑与动态模糊","en_us":"Disable Player TAA & Motion Blur"},"description":{"zh_cn":"玩家角色不参与时间抗锯齿和动态模糊，减少第三人称下的拖影。","en_us":"Excludes the player from TAA and motion blur."}}
//#define OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
// @option {"label": {"zh_cn": "深度比较阈值", "en_us": "Depth Compare Threshold"}, "slider": true, "description": {"zh_cn": "判断历史点是否被遮挡的深度差上限；越小越容易判定为被遮挡、越少拖影。", "en_us": "Depth difference above which history is treated as occluded; smaller rejects more history and reduces smearing."}}
#define OMNI_TAA_DEPTH_COMPARE_THRESHOLD 0.0007 // [0.00002 0.00003 0.00005 0.00007 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1]

// --- 内部常数：原 `Settings.glsl` 里不进菜单的时间抗锯齿开关 ---
#define TAA_CLOSEST_DEPTH // 向前重投影时取三乘三邻域里最近的深度，减少物体边缘把背景深度带偏。
#define TAA_BICUBIC_PREVIOUS // 读取历史画面时用三次采样，比双线性更锐利。
#define TAA_DEPTH_COMPARE // 用上一帧深度和当前深度比较，判断对应点是否被遮挡。
#define TAA_MICRO_BLUR // 历史权重很低时对当前帧做一次极轻的邻域平均，压掉抖动。
//#define TAA_BICUBIC_CURRENT // 原程序默认关闭：当前帧用双线性采样即可。
//#define TAA_CLIP_TO_CENTER // 原程序默认关闭：邻域裁剪默认用另一种做法。

// 加载器输入、共享数学先引入；坐标换算依赖本文件定义的 `OMNI_TAA`，所以放在选项之后。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
// 材质编号 `MATID_*` 由材质效果文件定义，本文件的速度函数要用，自己引入避免调用方漏引。
#include "/effects/ground/material.glsl"
// 本文件自己的像素坐标：不依赖调用程序声明的全局量，任何程序在任意阶段引入都能编译。
// 为什么自己取：邻域取样需要一个全局像素坐标，各程序各自声明的同名全局量不一定排在本文件之前。
// 为什么放在片元守卫里面：`gl_FragCoord` 只有片元阶段存在，顶点阶段不编译下面这些函数。
#ifdef OMNI_FRAGMENT
ivec2 taaTexelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
vec2 taaTexCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。

// 时间抗锯齿核心：颜色空间、取样、方差统计、重投影与相机速度。
#include "/effects/clarity/taa.glsl"
// 边缘抗锯齿 FXAA。
#include "/effects/clarity/fxaa.glsl"
// --- 合成七号主体：时间抗锯齿历史，逐行照 iterationT `composite7.fsh` ---
// 按选项排除手与玩家、算相机速度、做邻域裁剪重投影；下界额外把参考深度与当前深度打包进透明度通道。
// 为什么按程序宏隔开：只有合成七号需要它，本文件还被地形、阴影、延迟等程序引入，它们没有材质编号与七号输出。
// 为什么返回而不是直接写 `compositeOutput7`：本文件在被引入的程序声明输出之前就展开，返回让程序自己赋值。
#if defined OMNI_COMPOSITE7_PASS
vec4 WriteTaaHistory(){
	#ifdef OMNI_TAA // 开启时间抗锯齿才做重投影。
		float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
		float depth = 1.0; // 供相机速度函数回填的代表深度。
		vec3 velocity = TaaCameraVelocity(depth, materialIDs); // 算当前像素相对上一帧的屏幕位移，并回填深度。
		vec4 taa = vec4(0.0); // 重投影结果。
		#ifdef OMNI_NETHER // 下界重投影额外回填参考深度，写回历史时要一起打包。
			float referenceDepth = 0.0; // 重投影后的参考深度。
		#endif

		// 先算出这个像素要不要用历史：三条宏分支各把要排除的材质标记为假，其余像素保持为真。
		bool reproject = true; // 默认走重投影。
		#if OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都排除。
			if (materialIDs == MATID_HAND || materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 这两类像素不用历史。
		#elif OMNI_DISABLE_HAND_TAA // 只排除手。
			if (materialIDs == MATID_HAND) reproject = false; // 手不用历史。
		#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只排除玩家。
			if (materialIDs == MATID_ENTITIES_PLAYER) reproject = false; // 玩家不用历史。
		#endif
		if (!reproject){ // 被排除的像素直接用当前帧颜色。
			taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色。
		}else{ // 其余像素走时间重投影。
			#ifdef OMNI_NETHER // 下界用带参考深度的重投影。
				taa = TemporalReprojection(texCoord, velocity, depth, referenceDepth); // 邻域裁剪后把历史混进当前帧，并回填参考深度。
			#else // 其余维度用主世界版重投影。
				taa = TemporalReprojection(texCoord, velocity, depth); // 邻域裁剪后把历史混进当前帧。
			#endif
		}
	#else // 关闭时间抗锯齿时原样复制当前帧。
		vec4 taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色与深度。
		#ifdef OMNI_NETHER // 下界直接沿用当前帧的深度当作参考深度。
			float referenceDepth = taa.a; // 当前帧深度就是参考深度。
		#endif
	#endif

	#ifdef OMNI_NETHER // 下界把参考深度与当前深度打包进七号画面透明度通道。
		return vec4(saturate(taa.rgb), Pack2x16(saturate(vec2(referenceDepth, taa.a)))); // 颜色加两个深度的打包值。
	#else // 其余维度直接交回。
		return taa; // 交回七号，作为下一帧的历史。
	#endif
}
#endif // 合成七号主体结束。
#endif // 片元阶段结束。
#endif // 文件守卫结束。
