/*
单个程序的绘制主体：只包含 OMNI_DEFERRED1_PASS 对应的阶段与算法。
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

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX

		// 焦散法线只需要一个被拉长的整屏四边形，缩放让波法线方块与分辨率无关。
		// 主世界在延迟零号算焦散，末地把同一段放到延迟一号，所以两支共用这段顶点。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		void main(){
			const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。
			vec2 causticsTexCoord = gl_Vertex.xy; // 加载器顶点在零到一的方块上。
			causticsTexCoord *= screenSize * (1.0 / min(screenSize.y, maxCausticsNormalHeight)); // 按屏幕高度与方块上限缩放。
			gl_Position = vec4(causticsTexCoord * 2.0 - 1.0, 0.0, 1.0); // 铺满屏幕并超出边界，保证全屏被覆盖。
		}

#endif

// ================================ 片元阶段 ================================

#if defined OMNI_FRAGMENT
	#if defined OMNI_END
		// 末地把焦散法线放到延迟一号（来自 `world1/deferred1.fsh`）：比主世界少一个丢弃判断，总是写七号画面。
		/* DRAWBUFFERS:7 */
		layout(location = 0) out vec4 deferredOutput7; // 七号焦散法线方块。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		// 提供材质编号，水面文件与坐标换算引用它。
		#include "/bind/ground/material.glsl"
		// 先定义 `OMNI_TAA`，坐标换算要用。
		#include "/bind/clarity/antialiasing.glsl"
		ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
		vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
		vec3 worldShadowVector; // 水面与雾文件引用它。
		vec3 shadowVector; // 屏幕空间阴影引用它。
		vec3 worldSunVector; // 光照与天空文件引用它。
		vec3 worldMoonVector; // 天空与光照文件引用它。
		vec3 colorShadowlight; // 雾与光照文件引用它。
		vec3 colorSunlight; // 光照与天空文件引用它。
		vec3 colorMoonlight; // 天空与光照文件引用它。
		vec3 colorSkylight; // 雾文件引用它。
		vec3 colorSunSkylight; // 天空与光照文件引用它。
		vec3 colorMoonSkylight; // 天空与光照文件引用它。
		vec3 colorTorchlight; // 方块光文件引用它。
		float timeNoon; // 光照与雾文件引用它。
		float timeMidnight; // 光照与雾文件引用它。
		uniform sampler2D gaux1; // 第一张涟漪动画贴图，雨点函数引用。
		uniform sampler2D gaux2; // 第二张涟漪动画贴图。
		uniform sampler2D gaux3; // 第三张涟漪动画贴图。
		uniform sampler2D shadowtex0; // 阴影遮挡图，雾文件引用。
		uniform sampler2D shadowtex1; // 阴影实心图，雾文件引用。
		uniform sampler2D shadowcolor0; // 阴影颜色图，雾文件引用。
		#include "/common/coordinates.glsl"
		#include "/common/noise.glsl"
		// 雾文件带入水面、阴影、天空、云与光照依赖，也提供 `GetWavesNormal`。
		#include "/bind/fog/fog.glsl"
		// 焦散法线的算法在效果文件里，这里只调用并写七号。
		#include "/bind/water/caustics.glsl"
		void main(){
			RenderCaustics(); // 算波法线并写七号；末地没有丢弃判断，总是写七号。
		}
	#else // 主世界与下界：全局光时间滤波。
	/* DRAWBUFFERS:2 */
	layout(location = 0) out vec4 deferredOutput2; // 二号全局光历史。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
	#include "/bind/ground/material.glsl"
	// 先定义 `OMNI_TAA`，坐标换算要用。
	#include "/bind/clarity/antialiasing.glsl"
	// 环境光效果文件引用阳光泄漏修正等选项，并带入天空、云与光照文件，所以这里先声明它们需要的量。
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
	uniform sampler2D shadowtex0; // 阴影遮挡图，全局光反弹与阴影函数引用它。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	uniform sampler2D shadowcolor1; // 阴影法线天光图，全局光反弹引用它。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	// 提供阳光泄漏修正选项，并带入环境光与阴影文件。
	#include "/bind/lighting/sunlight.glsl"
	void main(){
		deferredOutput2 = GI_TemporalFilter(); // 与历史帧按法线和深度双向插值。
	}
#endif
#endif
#endif
