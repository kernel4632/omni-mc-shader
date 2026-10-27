/*
单个程序的绘制主体：只包含 OMNI_COMPOSITE7_PASS 对应的阶段与算法。
来源：从 `rendering/post.glsl` 拆分，内容逐行保留，只是去掉了其他程序的分支。
为什么拆开：每个程序只展开自己用到的效果，重载时编译更快。
*/
/*
后期绘制主体：把 iterationT 的 `composite6` 到 `composite16` 十一个全屏程序合并进一个文件，按程序宏分派。
来源：根目录 `composite6.fsh` 到 `composite16.fsh` 与对应 `.vsh` 一比一移植；每个程序的算法体在对应效果文件里。
调用位置：各维度 `composite6` … `composite16` 入口定义阶段宏、维度宏与对应 `OMNI_COMPOSITE*_PASS` 后引入本文件。
    本文件不写 `#version`，语言版本由入口声明；顶点用加载器给的整屏三角形。入口由 `rendering/programs.json` 生成。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE14_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_COMPOSITE9_PASS 1` 再引入本文件即得泛光第一级顶点阶段。
输出约定（对应各程序文件头，见 `rendering/buffers.glsl`）：
    `composite6` 写一号（景深）；`composite7` 写七号（时间抗锯齿历史）；    `composite8` 写一号和二号（运动模糊、标题标志与统计像素）；
    `composite9` … `composite13` 写五号（泛光降采样与升采样链）；`composite14` 写一号（合并泛光、暗角、曝光、色调映射）；
    `composite15` 写一号（`CAS` 锐化）；`composite16` 写八号（放大输出）。
关键设计原因与取舍：
    原程序一个程序一个文件，本文件按程序宏分派；本文件只排绘制顺序、声明每个程序的输入输出与 `DRAWBUFFERS`，
    片元算法体全部搬到效果页：时间抗锯齿历史在 `effects/clarity/antialiasing.glsl`，运动模糊在 `effects/lens/post_motionblur.glsl`，
    标题标志在 `effects/lens/title.glsl`，统计像素在 `effects/color/post_stats.glsl`，泛光链在 `effects/color/bloom.glsl`，色调映射在 `effects/color/post_tonemap.glsl`。
    景深与锐化、放大各自只需一句效果函数调用，作为程序的输入输出留在本文件，不再另开文件。
    十一个程序共用的 `texelCoord`、`texCoord`、光色全局量与采样器只声明一次，见 `effects/clarity/post_shared.glsl`。
    泛光五级与放大程序各自缩放整屏四边形，所以顶点阶段也按程序宏分出不同 `main()`，缩放公式照原程序。
    被引入的效果文件会整段编译，它们引用的镜头光斑量 `sunCoord`、`sunVisibility` 在后期顶点阶段不输出，
    所以共享头按调用前提把它们声明成空全局，让整份文件可编译而本程序不调用它们。
*/
#ifndef OMNI_POST_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_POST_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 放大程序要把八号画面当二维纹理采样，和原程序一样在引入加载器输入前打开这个宏。

// 加载器输入最先引入；顶点阶段也要它提供的 `screenSize` 与 `MC_RENDER_QUALITY`。
#include "/common/uniforms.glsl"

// ================================ 顶点阶段 ================================
// 原程序里泛光五级与放大各写一份顶点做缩放，其余程序统一用 `Lib/Programs/PostVS.glsl` 的整屏三角形。
// 全屏顶点只写一次，默认铺满屏幕。
#include "/rendering/post_vertex.glsl"

// ================================ 片元阶段 ================================

// --- 合成七号：时间抗锯齿历史 ---
// 只需时间抗锯齿与材质编号；坐标换算依赖 `effects/clarity/antialiasing.glsl` 定义的 `OMNI_TAA`，所以先引入材质再引入它。
#if defined OMNI_FRAGMENT

	// 后期共享声明，全项目只声明一次。
	#include "/rendering/post_shared.glsl"
	// 提供材质编号 `MATID_*`，抗锯齿的速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 时间重投影与相机速度；内部再引入坐标换算。
	#include "/effects/clarity/antialiasing.glsl"

	/* DRAWBUFFERS:7 */
	layout(location = 0) out vec4 compositeOutput7; // 七号时间抗锯齿历史画面。

	void main(){ compositeOutput7 = WriteTaaHistory(); } // 重投影历史并把结果写回七号。

#endif

// --- 合成六号、八号、九号到十四号：共用同一批效果文件 ---
// 为什么共用：景深、动态模糊、泛光与合并泛光都编译整份效果文件；`effects/lens/lens.glsl` 的镜头光斑读体积雾选项，
// `effects/color/bloom.glsl` 的合并泛光读雨、水雾与体积雾选项，`effects/color/color.glsl` 的曝光统计读洞穴模式选项，
// 所以这些程序都要先把选项归属文件按顺序引入，才不会在编译时看到未定义的宏。选项归属见 `docs/parity.md` 第九节。

// --- 合成十五号：`CAS` 锐化 ---
// 只引入锐化与时间抗锯齿（`CAS` 的开启条件是同时开着时间抗锯齿）；材质文件提供被抗锯齿引用的材质编号。

// --- 合成十六号：`FsrEasu` 放大到八号画面 ---
// 只引入放大与共用数学；顶点已把整屏四边形缩到放大后的分辨率。

#endif
