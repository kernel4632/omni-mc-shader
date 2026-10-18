/*
单个程序的绘制主体：只包含 OMNI_DEFERRED4_PASS 对应的阶段与算法。
来源：从 `rendering/deferred.glsl` 拆分，内容逐行保留，只是去掉了其他程序的分支。
为什么拆开：每个程序只展开自己用到的效果，重载时编译更快。
*/
/*
延迟绘制主体：照 iterationT 的 `deferred`、`deferred1` 到 `deferred6` 七个全屏程序一比一移植。
职责与写出缓冲：
    `deferred` 写七号：左下角最多五百像素见方的水面波法线，供焦散采样；
    `deferred1` 写二号：反射阴影图全局光的时间滤波历史；
    `deferred2` 写一号：全局光的空间滤波与地平线遮蔽；
    `deferred3` 写一号和二号：天空、体积云、平面云、星星、日月，以及上半屏天空盒与右上角云影贴图；
    `deferred4`、`deferred5` 写二号：云影贴图横向、纵向高斯模糊；
    `deferred6` 写四号和六号：把不透明法线光照图与材质编号复制给半透明层当默认值。
    `deferred7`（低分辨率体积云，主世界、`OMNI_CLOUD_RENDER_SCALE > 1` 时）写十号：低分辨率上只算基础体积云；
    `deferred8`（把云贴回天空，同前）写一号：放大十号云贴回天空，并补平面云与附加层。关闭或原分辨率时不生成这两步。
调用位置：各维度同名入口定义阶段宏、维度宏与对应 `OMNI_DEFERRED*_PASS` 后引入本文件。
    本文件不写 `#version`，语言版本由入口声明；顶点阶段用加载器给的整屏三角形，不需要投影矩阵。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_DEFERRED2_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_DEFERRED3_PASS 1` 再引入本文件即得延迟三号顶点阶段。
关键设计原因与取舍：
    延迟三号、四号、五号与低分辨率云七号把四号六号画面当三维云噪声读，所以文件顶部按这些程序打开 `COLORTEX_CLOUDNOISE`，采样器类型才由 `common/uniforms.glsl` 选对；其余程序保持二维画面。
    原程序一个程序一个文件，本文件把它们合成一个主体，按程序宏分派；算法体已经搬进对应效果文件：
        焦散法线 `effects/water/caustics.glsl` 的 `RenderCaustics`（延迟零号主世界、延迟一号末地）；全局光空间滤波 `effects/lighting/ambient.glsl` 的 `RenderGISpatialFilter`（延迟二号主世界、延迟四号末地）。
        天空、云、日月星与天空盒 `effects/sky/skyrender.glsl` 的 `RenderDeferredSky`（延迟三号，主天空与天空盒共用一段累积）。
    本文件只按绘制顺序安排每个程序的输入输出与调用，不复制算法；全屏复制、时间滤波与云影模糊就是一两次现成函数调用，留在原处；延迟顶点里只有三号要算光色（走 `rendering/lights.glsl`），四号五号要算云影贴图坐标，其余只需铺满屏幕。
*/
#ifndef OMNI_DEFERRED_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_DEFERRED_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 延迟三号、四号、五号在延迟阶段把四号六号画面换成三维云噪声，宏名照 iterationT 原名由程序自己打开。
// 末地的延迟四号是全局光空间滤波，不读云噪声，所以要把它排除在外。低分辨率体积云的延迟七号（算云）与
// 延迟八号（把云贴回天空，复用平面云与附加层函数）也要三维云噪声。
	#define COLORTEX_CLOUDNOISE 1 // 打开后四号六号声明成三维采样器。

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX

		// 云影模糊只作用在画面右上角的方贴图上，顶点把整屏四边形缩到那块方贴图的范围。
		vec3 worldShadowVector; // 云影效果文件里合成专用函数引用它；顶点阶段不调用那些函数。
		vec3 worldSunVector; // 云带入的天空效果文件里星空函数引用它；本阶段不调用，仅让文件可编译。
		#include "/effects/cloud/cloud.glsl"
		void main(){
			vec2 shadowTexSize = pixelSize * floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 方贴图占屏幕的比例。
			vec2 shadowTexCoord = gl_Vertex.xy; // 加载器顶点在零到一的方块上。
			shadowTexCoord = shadowTexCoord * shadowTexSize + (1.0 - shadowTexSize); // 缩到右上角方贴图的位置。
			gl_Position = vec4(shadowTexCoord * 2.0 - 1.0, 0.0, 1.0); // 铺满屏幕。
		}

#endif

// ================================ 片元阶段 ================================

#if defined OMNI_FRAGMENT
	#if defined OMNI_END
		// 末地把全局光空间滤波放到延迟四号（来自 `world1/deferred4.fsh`）：用含半透明的深度算遮蔽与空间滤波。
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 deferredOutput1; // 一号全局光与遮蔽。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
		#include "/effects/ground/material.glsl"
		// 先定义 `OMNI_TAA`，坐标换算与遮蔽抖动要用。
		#include "/effects/clarity/antialiasing.glsl"
		ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
		vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
		vec3 worldShadowVector; // 阴影与天空文件引用它。
		vec3 shadowVector; // 屏幕空间阴影引用它。
		vec3 worldSunVector; // 天空与光照文件引用它。
		vec3 worldMoonVector; // 天空与光照文件引用它。
		vec3 colorShadowlight; // 日月直射光色之和。
		vec3 colorSunlight; // 太阳直射光色。
		vec3 colorMoonlight; // 月亮直射光色。
		vec3 colorSkylight; // 日月环境光色之和。
		vec3 colorSunSkylight; // 太阳一侧的环境光色。
		vec3 colorMoonSkylight; // 月亮一侧的环境光色。
		vec3 colorTorchlight; // 火把光色。
		float timeNoon; // 太阳高度因子。
		float timeMidnight; // 月亮高度因子。
		uniform sampler2D shadowtex0; // 阴影遮挡图。
		uniform sampler2D shadowtex1; // 阴影实心图。
		uniform sampler2D shadowcolor0; // 阴影颜色图。
		uniform sampler2D shadowcolor1; // 阴影法线天光图。
		#include "/common/coordinates.glsl"
		#include "/common/noise.glsl"
		// 提供阳光泄漏修正选项，并带入环境光与阴影文件（末地版阴影相机由 `OMNI_END` 选择）。
		#include "/effects/lighting/sunlight.glsl"
	// 全局光空间滤波的算法在 `effects/lighting/ambient.glsl`（上面经 `effects/lighting/sunlight.glsl` 引入），这里只取深度并写一号。
		void main(){
			deferredOutput1 = RenderGISpatialFilter(texelFetch(depthtex0, texelCoord, 0).x); // 末地用含半透明的深度做遮蔽与空间滤波。
		}
	#else // 主世界：云影横向与纵向模糊。
	/* DRAWBUFFERS:2 */
	layout(location = 0) out vec4 deferredOutput2; // 二号云影贴图。
	#include "/common/uniforms.glsl"
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec3 worldShadowVector; // 云影效果文件里合成专用函数引用它；本程序不调用那些函数。
	vec3 worldSunVector; // 云带入的天空效果文件里星空函数引用它；本程序不调用，仅让文件可编译。
	// 提供 `CloudShadowAxialBlur`。
	#include "/effects/cloud/cloud.glsl"
	void main(){
			deferredOutput2 = CloudShadowAxialBlur(texelCoord, ivec2(1, 0)); // 横向高斯模糊。
	}
#endif
#endif
#endif
