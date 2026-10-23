/*
单个程序的绘制主体：只包含 OMNI_COMPOSITE5_PASS 对应的阶段与算法。
来源：从 `rendering/composite.glsl` 拆分，内容逐行保留，只是去掉了其他程序的分支。
为什么拆开：每个程序只展开自己用到的效果，重载时编译更快。
*/
/*
合成绘制主体：照 iterationT 根目录 `composite`、`composite1` 到 `composite5` 六个全屏程序一比一移植。
职责：本文件只安排每个合成程序的输入输出（引入哪个效果文件、声明哪些采样器、写哪号画面），
    算法体全部在效果文件里，这里按程序顺序调用。共享的全局声明在 `rendering/composite_shared.glsl`。
调用位置：各维度同名入口先定义维度宏、`OMNI_FRAGMENT` 或 `OMNI_VERTEX`，以及对应 `OMNI_COMPOSITE*_PASS`，
    再引入本文件。顶点阶段统一复用 `rendering/lights.glsl`；片元阶段按合同顺序引入效果文件。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE0_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_COMPOSITE2_PASS 1` 再引入本文件即得合成二号顶点阶段。
写出缓冲与来源：
    `composite` 写一号，来自 `composite.fsh`；`composite1` 写一号，来自 `composite1.fsh`；
    `composite2` 写三号，来自 `composite2.fsh`；`composite3`、`composite4` 写三号，来自对应同名文件；
    `composite5` 写一号与三号，来自 `composite5.fsh`。
关键设计原因与取舍：
    原程序一个程序一个文件，本文件把它们合成一个主体，按程序宏分派；每个片元的算法体搬到对应效果页，
    本文件只保留阶段流程、各程序的采样器与输出声明，以及一次效果函数调用，便于按效果查找与修改。
    六个程序共用的 `texelCoord`、`texCoord`、光色 varying 与采样器只声明一次，见 `rendering/composite_shared.glsl`。
    被引入的效果文件会整段编译，所以它们引用的加载器输入（阴影采样器、涟漪贴图、降雨强度、天空光满值标记）
    由本文件或共享头声明；本程序自己不一定用到这些量，声明只为让整段可编译，名字照 iterationT。
    `composite5` 的 `sunCoord`、`sunVisibility` 由顶点阶段算出；镜头选项位于 `effects/lens/lens.glsl`，
    那份文件含片元专用的 `gl_FragCoord`，不能在顶点阶段引入，因此顶点阶段看不到 `OMNI_LENS_GLARE`，
    两个变量在顶点阶段不会被写出。阴影样本 `shadowtex1` 在末地与主世界零号按 `rendering/buffers.glsl` 的
    `shadowHardwareFiltering1` 声明成带比较的采样器，其余程序按普通深度贴图声明，两类写法与原程序一致。
*/
#ifndef OMNI_COMPOSITE_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_COMPOSITE_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX // 顶点阶段只做全屏三角形与光色计算，交给 `rendering/lights.glsl`。

		#define VS_SUN_VISIBILITY 1 // 打开太阳可见度分支，片元要用它画镜头光斑。
	// 提供 `void main()` 与全部光色输出。
	#include "/rendering/lights.glsl"

#endif

// ================================ 片元阶段 ================================
// 六个合成程序共用的片元全局量只声明一次。
#include "/rendering/composite_shared.glsl"

// ------------------------------- 合成零号：不透明表面完整光照 -------------------------------

// ------------------------------- 合成一号：水下与水后雾 -------------------------------

// ------------------------------- 合成二号：屏幕空间反射与天空盒回退 -------------------------------

// ------------------------------- 合成三号：反射小波滤波，半径四十 -------------------------------

// ------------------------------- 合成四号：反射小波滤波，半径二十 -------------------------------

// ------------------------------- 合成五号：折射、合并反射、雾、雨、选择框与镜头光斑 -------------------------------
#if defined OMNI_FRAGMENT
/* DRAWBUFFERS:13 */
layout(location = 0) out vec4 compositeOutput1; // 一号画面：最终合成颜色与景深弥散。
in vec2 sunCoord; // 太阳屏幕坐标，顶点阶段算出，镜头光斑按它定位。
in float sunVisibility; // 太阳可见度，顶点阶段算出，镜头光斑按它衰减。
uniform sampler2D shadowtex1; // 阴影实心图，本程序当普通深度贴图读取。
// 维度决定雾与折射由谁提供：主世界用体积雾与地表散射，下界用 `NetherFog`，末地用 `EndFog`。
#if defined OMNI_NETHER // 下界。
	// 雾文件带入水面、天空、云、光照，并提供 `VanillaFog` 与雾选项。
	#include "/bind/fog/fog.glsl"
	// 下界配色、雾与折射 `NetherFogColor`、`NetherFog`、`RefractSampleOnceNether`。
	#include "/bind/world/nether.glsl"
#elif defined OMNI_END // 末地。
	// 雾文件带入水面与 `VanillaFog`，并提供星空类型与阳光强度选项。
	#include "/bind/fog/fog.glsl"
	// 末地天空、雾与折射 `EndFog`、`RefractSampleOnceEnd`。
	#include "/bind/world/end.glsl"
#else // 主世界。
	// 带入天空、云、环境光与方块光依赖。
	#include "/bind/lighting/sunlight.glsl"
	// 体积雾、水下体积雾、地面大气散射、原版雾，并带入水面与阴影。
	#include "/bind/fog/fog.glsl"
#endif
// 反射合并 `CalculateSpecularReflections`。
#include "/bind/reflection/reflection.glsl"
// 浦肯野效应 `PurkinjeEffect`。
#include "/bind/color/color.glsl"
// 景深弥散 `CoCSpread` 与镜头光斑 `LensFlare`，并提供镜头选项。
#include "/bind/lens/lens.glsl"
// 选择框 `SelectionBox`。
#include "/bind/ground/selection.glsl"
#if defined OMNI_NETHER || defined OMNI_END // 下界与末地只写一号画面。
// 下界与末地的合成五号原程序只写一号画面，不画镜头光斑，所以这里不声明三号输出。
#else
#if OMNI_LENS_GLARE || OMNI_LENS_FLARE || (defined OMNI_VFOG && !defined OMNI_DOF) // 开启镜头相关效果或体积雾时才写三号。
	layout(location = 1) out vec4 compositeOutput3; // 三号画面：镜头光斑，仅在开启相关效果时写出。
#endif
#endif
// 折射、合并反射、雾、雨、选择框与镜头光斑算法在效果文件里。
#include "/bind/world/composite_scene.glsl"
void main(){ CompositeSceneColor(); } // 合成整幅场景色并写回一号与三号画面。
#endif

#endif
