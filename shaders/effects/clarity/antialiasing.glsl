/*
效果文件 `effects/clarity/antialiasing.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/clarity/antialiasing.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_CLARITY_ANTIALIASING_INCLUDED
#define OMNI_EFFECT_CLARITY_ANTIALIASING_INCLUDED
// --- 效果实现：宿主输入、参数换算与阶段入口 ---
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
// 时间抗锯齿选项是多个页面共用的输入，放在共享层只定义一次。
#include "/effects/shared/antialias.glsl"
#include "/common/coordinates.glsl"
// 材质编号 `MATID_*` 属于 G 缓冲约定，直接引用绑定层，不再穿过整个地表材质效果。
#include "/bind/gbuffer.glsl"
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
			if (bind_is_hand_id(materialIDs) || bind_is_player_id(materialIDs)) reproject = false; // 这两类像素不用历史。
		#elif OMNI_DISABLE_HAND_TAA // 只排除手。
			if (bind_is_hand_id(materialIDs)) reproject = false; // 手不用历史。
		#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只排除玩家。
			if (bind_is_player_id(materialIDs)) reproject = false; // 玩家不用历史。
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
#endif // OMNI_EFFECT_CLARITY_ANTIALIASING_INCLUDED
