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
        焦散法线 `effects/water/caustics.glsl` 的 `RenderCaustics`（延迟零号主世界、延迟一号末地）；全局光空间滤波 `effects/lighting/globalillumination.glsl` 的 `RenderGISpatialFilter`（延迟二号主世界、延迟四号末地）。
        天空、云、日月星与天空盒 `effects/sky/skyrender.glsl` 的 `RenderDeferredSky`（延迟三号，主天空与天空盒共用一段累积）。
    本文件只按绘制顺序安排每个程序的输入输出与调用，不复制算法；全屏复制、时间滤波与云影模糊就是一两次现成函数调用，留在原处；延迟顶点里只有三号要算光色（走 `rendering/lights.glsl`），四号五号要算云影贴图坐标，其余只需铺满屏幕。
*/
#ifndef OMNI_DEFERRED_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_DEFERRED_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 延迟三号、四号、五号在延迟阶段把四号六号画面换成三维云噪声，宏名照 iterationT 原名由程序自己打开。
// 末地的延迟四号是全局光空间滤波，不读云噪声，所以要把它排除在外。低分辨率体积云的延迟七号（算云）与
// 延迟八号（把云贴回天空，复用平面云与附加层函数）也要三维云噪声。
#if defined OMNI_DEFERRED3_PASS || defined OMNI_DEFERRED7_PASS || defined OMNI_DEFERRED8_PASS || ((defined OMNI_DEFERRED4_PASS || defined OMNI_DEFERRED5_PASS) && !defined OMNI_END)
	#define COLORTEX_CLOUDNOISE 1 // 打开后四号六号声明成三维采样器。
#endif

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX

	#if defined OMNI_DEFERRED3_PASS || defined OMNI_DEFERRED7_PASS || defined OMNI_DEFERRED8_PASS // 三号画天空、七号算低分辨率云、八号把云贴回天空，都要光色。
		// 延迟三号顶点与合成顶点共用一段光色计算，并按原程序打开云光照分支得到固定的高空相机。
		#define VS_CLOUD_LIGHTING 1
		#include "/rendering/lights.glsl"
	#elif (defined OMNI_DEFERRED0_PASS && !defined OMNI_NETHER && !defined OMNI_END) || (defined OMNI_DEFERRED1_PASS && defined OMNI_END)
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
	#elif (defined OMNI_DEFERRED4_PASS || defined OMNI_DEFERRED5_PASS) && !defined OMNI_END
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
	#else
		// 下界与末地的延迟零号是复制程序，延迟一、二、六号只做全屏处理，顶点铺满屏幕即可。
		void main(){
			gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 整屏三角形。
		}
	#endif

#endif // 顶点阶段结束。

// ================================ 片元阶段 ================================

#if defined OMNI_FRAGMENT && defined OMNI_DEFERRED0_PASS // 延迟零号。
	#if defined OMNI_NETHER || defined OMNI_END
		// 下界与末地的延迟零号是复制程序（来自 `world-1/deferred.fsh`、`world1/deferred.fsh`）：
		// 它们没有主世界的焦散需求，只把不透明法线与材质编号复制给半透明层当默认值。
		/* DRAWBUFFERS:46 */
		layout(location = 0) out vec4 deferredOutput4; // 四号半透明法线光照图。
		layout(location = 1) out vec4 deferredOutput6; // 六号半透明材质编号。
		#include "/common/uniforms.glsl"
		ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
		void main(){
			vec4 data3 = texelFetch(colortex3, texelCoord, 0); // 读不透明法线光照图。
			vec4 data5 = texelFetch(colortex5, texelCoord, 0); // 读不透明高光材质。
			deferredOutput4 = data3; // 法线光照图原样复制给半透明层。
			deferredOutput6 = vec4(0.0, 0.0, data5.z, 0.0); // 只把材质编号复制进六号蓝色通道。
		}
	#else // 主世界：水面波法线方块。
	/* DRAWBUFFERS:7 */
	layout(location = 0) out vec4 deferredOutput7; // 七号焦散法线方块。
	// 加载器画面与共用数学先引入；再按依赖顺序引入效果文件。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 先定义 `OMNI_TAA`，坐标换算按它决定是否撤销抖动。
	#include "/effects/clarity/antialiasing.glsl"
	// 以下方向与光色量只在效果文件里合成阶段才会调用的函数中用到；本程序一起编译整个文件，所以先声明。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
	vec3 worldShadowVector; // 阴影相机对应的世界光方向。
	vec3 shadowVector; // 上面那个方向在视空间的值。
	vec3 worldSunVector; // 太阳的世界方向。
	vec3 worldMoonVector; // 月亮的世界方向。
	vec3 colorShadowlight; // 日月直射光色之和。
	vec3 colorSunlight; // 太阳直射光色。
	vec3 colorMoonlight; // 月亮直射光色。
	vec3 colorSkylight; // 日月环境光色之和。
	vec3 colorSunSkylight; // 太阳一侧的环境光色。
	vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	vec3 colorTorchlight; // 火把光色。
	float timeNoon; // 太阳高度因子。
	float timeMidnight; // 月亮高度因子。
	uniform sampler2D shadowtex0; // 阴影遮挡图，供阴影查询函数引用。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	uniform sampler2D shadowcolor1; // 阴影法线天光图，原程序一并声明。
	uniform sampler2D gaux1; // 第一张涟漪动画贴图，雨点涟漪函数引用它。
	uniform sampler2D gaux2; // 第二张涟漪动画贴图。
	uniform sampler2D gaux3; // 第三张涟漪动画贴图。
	uniform float rainStrength; // 降雨强度，雨点涟漪函数引用它。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	// 体积雾选项供丢弃判断，并带入水面、阴影、天空、云与光照依赖。
	#include "/effects/fog/fog.glsl"
	// 焦散法线的算法在效果文件里，这里只调用并写七号。
	#include "/effects/water/caustics.glsl"
	void main(){
		RenderCaustics(); // 算波法线并写七号；不开焦散与水下体积雾时由效果文件整片丢弃。
	}
	#endif // 延迟零号维度分支结束。
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED1_PASS // 延迟一号。
	#if defined OMNI_END
		// 末地把焦散法线放到延迟一号（来自 `world1/deferred1.fsh`）：比主世界少一个丢弃判断，总是写七号画面。
		/* DRAWBUFFERS:7 */
		layout(location = 0) out vec4 deferredOutput7; // 七号焦散法线方块。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		// 提供材质编号，水面文件与坐标换算引用它。
		#include "/effects/ground/material.glsl"
		// 先定义 `OMNI_TAA`，坐标换算要用。
		#include "/effects/clarity/antialiasing.glsl"
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
		uniform float rainStrength; // 降雨强度，雨点函数引用。
		uniform sampler2D shadowtex0; // 阴影遮挡图，雾文件引用。
		uniform sampler2D shadowtex1; // 阴影实心图，雾文件引用。
		uniform sampler2D shadowcolor0; // 阴影颜色图，雾文件引用。
		#include "/common/coordinates.glsl"
		#include "/common/noise.glsl"
		// 雾文件带入水面、阴影、天空、云与光照依赖，也提供 `GetWavesNormal`。
		#include "/effects/fog/fog.glsl"
		// 焦散法线的算法在效果文件里，这里只调用并写七号。
		#include "/effects/water/caustics.glsl"
		void main(){
			RenderCaustics(); // 算波法线并写七号；末地没有丢弃判断，总是写七号。
		}
	#else // 主世界与下界：全局光时间滤波。
	/* DRAWBUFFERS:2 */
	layout(location = 0) out vec4 deferredOutput2; // 二号全局光历史。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 先定义 `OMNI_TAA`，坐标换算要用。
	#include "/effects/clarity/antialiasing.glsl"
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
	#include "/effects/lighting/sunlight.glsl"
	void main(){
		deferredOutput2 = GI_TemporalFilter(); // 与历史帧按法线和深度双向插值。
	}
	#endif // 全局光时间滤波分支结束。
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED2_PASS // 延迟二号。
	#if defined OMNI_END
		// 末地把全局光时间滤波放到延迟二号（来自 `world1/deferred2.fsh`），主体与主世界的延迟一号一致，只是程序位置不同。
		/* DRAWBUFFERS:2 */
		layout(location = 0) out vec4 deferredOutput2; // 二号全局光历史。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
		#include "/effects/ground/material.glsl"
		// 先定义 `OMNI_TAA`，坐标换算要用。
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
		uniform sampler2D shadowtex0; // 阴影遮挡图，全局光反弹与阴影函数引用它。
		uniform sampler2D shadowtex1; // 阴影实心图。
		uniform sampler2D shadowcolor0; // 阴影颜色图。
		uniform sampler2D shadowcolor1; // 阴影法线天光图。
		#include "/common/coordinates.glsl"
		#include "/common/noise.glsl"
		// 提供阳光泄漏修正选项，并带入环境光与阴影文件（末地版阴影相机由 `OMNI_END` 选择）。
		#include "/effects/lighting/sunlight.glsl"
		void main(){
			deferredOutput2 = GI_TemporalFilter(); // 与历史帧按法线和深度双向插值。
		}
	#else // 主世界：空间滤波与地平线遮蔽。
	/* DRAWBUFFERS:1 */
	layout(location = 0) out vec4 deferredOutput1; // 一号全局光与遮蔽。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 先定义 `OMNI_TAA`，坐标换算与遮蔽抖动要用。
	#include "/effects/clarity/antialiasing.glsl"
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
	uniform sampler2D shadowtex0; // 阴影遮挡图，供被引入的阴影函数引用。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	uniform sampler2D shadowcolor1; // 阴影法线天光图。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	// 提供阳光泄漏修正选项，并带入环境光与阴影文件。
	#include "/effects/lighting/sunlight.glsl"
	// 全局光空间滤波的算法在效果文件里，这里只取深度并写一号。
	#include "/effects/lighting/globalillumination.glsl"
	void main(){
		deferredOutput1 = RenderGISpatialFilter(texelFetch(depthtex1, texelCoord, 0).x); // 用不含半透明的深度做遮蔽与空间滤波。
	}
	#endif // 全局光空间滤波分支结束。
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED3_PASS // 延迟三号：天空、云与统计像素。
	/* DRAWBUFFERS:12 */
	layout(location = 0) out vec4 deferredOutput1; // 一号天空像素颜色。
	layout(location = 1) out vec4 deferredOutput2; // 二号天空盒与云影。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 提供材质编号，被引入的环境光速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 先定义 `OMNI_TAA`，坐标换算要用。
	#include "/effects/clarity/antialiasing.glsl"
	// 光色与方向由顶点阶段（`rendering/lights.glsl`）算出，这里用同名 `in` 接收。
	in vec3 worldShadowVector; // 阴影相机对应的世界光方向。
	in vec3 shadowVector; // 上面那个方向在视空间的值。
	in vec3 worldSunVector; // 太阳的世界方向。
	in vec3 worldMoonVector; // 月亮的世界方向。
	in vec3 colorShadowlight; // 日月直射光色之和。
	in vec3 colorSunlight; // 太阳直射光色。
	in vec3 colorMoonlight; // 月亮直射光色。
	in vec3 colorSkylight; // 日月环境光色之和。
	in vec3 colorSunSkylight; // 太阳一侧的环境光色。
	in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	in vec3 colorTorchlight; // 火把光色。
	in float timeNoon; // 太阳高度因子。
	in float timeMidnight; // 月亮高度因子。
	// 被引入的阴影与环境光效果文件整体会一起编译，它们的查询函数引用下列输入。
	uniform sampler2D shadowtex0; // 阴影遮挡图。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	// 预计算大气、日月圆盘、星空与天空盒投影。
	#include "/effects/sky/sky.glsl"
	// 体积云、平面云与云影贴图。
	#include "/effects/cloud/cloud.glsl"
	// 提供洞穴模式与无光亮度选项，并带入光色计算依赖。
	#include "/effects/lighting/sunlight.glsl"
	// Omni 额外功能：极光与彩虹，默认关闭。
	#include "/effects/sky/atmosphere.glsl"
	// 天空、云、日月星与天空盒的算法在效果文件里，这里只调用并写一号与二号。
	#include "/effects/sky/skyrender.glsl"
	void main(){
		RenderDeferredSky(); // 画天空像素、天空盒图与右上角云影贴图。
	}
#elif defined OMNI_FRAGMENT && (defined OMNI_DEFERRED4_PASS || defined OMNI_DEFERRED5_PASS) // 延迟四号五号。
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
		// 全局光空间滤波的算法在效果文件里，这里只取深度并写一号。
		#include "/effects/lighting/globalillumination.glsl"
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
		#if defined OMNI_DEFERRED4_PASS
			deferredOutput2 = CloudShadowAxialBlur(texelCoord, ivec2(1, 0)); // 横向高斯模糊。
		#else
			deferredOutput2 = CloudShadowAxialBlur(texelCoord, ivec2(0, 1)); // 纵向高斯模糊。
		#endif
	}
	#endif // 云影模糊分支结束。
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED6_PASS // 延迟六号：半透明层的默认表面数据。
	/* DRAWBUFFERS:46 */
	layout(location = 0) out vec4 deferredOutput4; // 四号半透明法线光照图。
	layout(location = 1) out vec4 deferredOutput6; // 六号半透明材质编号。
	#include "/common/uniforms.glsl"
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	void main(){
		vec4 data3 = texelFetch(colortex3, texelCoord, 0); // 读不透明法线光照图。
		vec4 data5 = texelFetch(colortex5, texelCoord, 0); // 读不透明高光材质。

		deferredOutput4 = data3; // 法线光照图原样复制给半透明层。
		deferredOutput6 = vec4(0.0, 0.0, data5.z, 0.0); // 只把材质编号复制进六号蓝色通道。
	}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED7_PASS // 延迟七号：低分辨率体积云。
	// 只在主世界、且体积云渲染分辨率大于一时执行；写十号画面，尺寸由绘制设置按分辨率缩小。
	/* RENDERTARGETS: 10 */
	layout(location = 0) out vec4 deferredOutput10; // 十号：低分辨率云的加色与透过率。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	// 光色与方向由顶点阶段（`rendering/lights.glsl`）算出，这里用同名 `in` 接收；被引入的天空、云、光照与氛围文件整体会一起编译，它们引用到的量都要声明。
	in vec3 worldShadowVector; // 阴影相机对应的世界光方向，云光照与平面云引用它。
	in vec3 shadowVector; // 上面那个方向在视空间的值。
	in vec3 worldSunVector; // 太阳的世界方向，大气查表引用它。
	in vec3 worldMoonVector; // 月亮的世界方向，大气查表引用它。
	in vec3 colorShadowlight; // 日月直射光色之和，云引用它。
	in vec3 colorSunlight; // 太阳直射光色。
	in vec3 colorMoonlight; // 月亮直射光色。
	in vec3 colorSkylight; // 日月环境光色之和，云引用它。
	in vec3 colorSunSkylight; // 太阳一侧的环境光色。
	in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	in vec3 colorTorchlight; // 火把光色。
	in float timeNoon; // 太阳高度因子，天空文件引用它。
	in float timeMidnight; // 月亮高度因子，天空文件引用它。
	// 被引入的阴影与光照文件整体会一起编译，它们的查询函数引用下列输入。
	uniform sampler2D shadowtex0; // 阴影遮挡图。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	// 预计算大气：取云可见判据里的「视线是否打到地面」。
	#include "/effects/sky/sky.glsl"
	// 体积云密度、光照与总图；分辨率选项也在这一步定义。
	#include "/effects/cloud/cloud.glsl"
	// 这一阶段在更低的分辨率上运行，坐标按分辨率除数换回全分辨率口径；被引入文件整体会一起编译，需要这两个量。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy * float(OMNI_CLOUD_RENDER_SCALE)); // 对应的全分辨率像素坐标。
	vec2 texCoord = gl_FragCoord.xy * pixelSize * float(OMNI_CLOUD_RENDER_SCALE); // 对应的全分辨率零到一屏幕坐标。
	// 提供洞穴模式等选项，并带入光色计算依赖。
	#include "/effects/lighting/sunlight.glsl"
	// Omni 额外功能：极光与彩虹，默认关闭；公告牌与云内闪电一并带入。
	#include "/effects/sky/atmosphere.glsl"
	void main(){
		float depth = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的深度，坐标已换回全分辨率。
		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置。
		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
		vec3 worldDir = normalize(worldPos); // 世界方向。

		#ifdef OMNI_ATMO_HORIZON // 与延迟三号主天空同一套相机高度与地平线开关。
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0);
			bool horizon = true;
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0);
			bool horizon = false;
		#endif
		vec2 noise = BlueNoiseTemporal().xy; // 主画面用的逐帧蓝噪声。
		vec2 cloudAltitude = vec2(mix(OMNI_CLOUD_CLEAR_ALTITUDE, OMNI_CLOUD_RAIN_ALTITUDE, wetness)); // 晴雨两档云底高度。
		cloudAltitude.y += mix(OMNI_CLOUD_CLEAR_THICKNESS, OMNI_CLOUD_RAIN_THICKNESS, wetness); // 加上层厚得到云顶高度。
		float wind = 0.0005 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 云漂动的时间量。
		vec3 windDirection = vec3(1.0, wetness * 0.1 - 0.05, -0.4) * wind; // 云漂动的方向与位移。

		vec3 atmoTransmittance; // 大气透过率，本阶段不用，仅取云可见判据。
		bool intersectsGround; // 视线是否打到地面。
		GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, atmoTransmittance, intersectsGround); // 查表取可见判据。

		deferredOutput10 = omniCloudImage(worldDir, camera, noise, cloudAltitude, windDirection, intersectsGround, worldDir.y < 0.0); // 算基础体积云并写十号。
	}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED8_PASS // 延迟八号：把低分辨率云放大贴回天空，并补平面云与附加层。
	// 只在主世界、且体积云渲染分辨率大于一时执行；写一号画面。
	/* DRAWBUFFERS:1 */
	layout(location = 0) out vec4 deferredOutput1; // 一号：贴好云的天空颜色。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	in vec3 worldShadowVector; // 阴影相机对应的世界光方向，平面云与附加层光照引用它。
	in vec3 shadowVector; // 上面那个方向在视空间的值。
	in vec3 worldSunVector; // 太阳的世界方向，大气查表与云引用它。
	in vec3 worldMoonVector; // 月亮的世界方向，大气查表与云引用它。
	in vec3 colorShadowlight; // 日月直射光色之和，云引用它。
	in vec3 colorSunlight; // 太阳直射光色。
	in vec3 colorMoonlight; // 月亮直射光色。
	in vec3 colorSkylight; // 日月环境光色之和，云引用它。
	in vec3 colorSunSkylight; // 太阳一侧的环境光色。
	in vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	in vec3 colorTorchlight; // 火把光色。
	in float timeNoon; // 太阳高度因子，天空文件引用它。
	in float timeMidnight; // 月亮高度因子，天空文件引用它。
	uniform sampler2D shadowtex0; // 阴影遮挡图。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
	#include "/common/coordinates.glsl"
	#include "/common/noise.glsl"
	#include "/effects/sky/sky.glsl"
	#include "/effects/cloud/cloud.glsl"
	#include "/effects/lighting/sunlight.glsl"
	#include "/effects/sky/atmosphere.glsl"
	void main(){
		vec4 base = texelFetch(colortex1, texelCoord, 0); // 延迟三号画好的天空。
		deferredOutput1 = base; // 默认原样保留，几何像素不动。
		float depth = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的深度。
		if (depth != 1.0) return; // 只有天空像素才贴云。

		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置。
		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
		vec3 worldDir = normalize(worldPos); // 世界方向。

		#ifdef OMNI_ATMO_HORIZON // 与延迟三号主天空同一套相机高度与地平线开关。
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0);
			bool horizon = true;
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0);
			bool horizon = false;
		#endif
		vec2 noise = BlueNoiseTemporal().xy; // 主画面用的逐帧蓝噪声。
		vec2 cloudAltitude = vec2(mix(OMNI_CLOUD_CLEAR_ALTITUDE, OMNI_CLOUD_RAIN_ALTITUDE, wetness)); // 晴雨两档云底高度。
		cloudAltitude.y += mix(OMNI_CLOUD_CLEAR_THICKNESS, OMNI_CLOUD_RAIN_THICKNESS, wetness); // 加上层厚得到云顶高度。
		float wind = 0.0005 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 云漂动的时间量。
		vec3 windDirection = vec3(1.0, wetness * 0.1 - 0.05, -0.4) * wind; // 云漂动的方向与位移。

		vec3 atmoTransmittance; // 大气透过率，本阶段不用，仅取云可见判据。
		bool intersectsGround; // 视线是否打到地面。
		GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, atmoTransmittance, intersectsGround); // 查表取可见判据。

		vec4 cloudImage = textureLod(colortex10, texCoord, 0.0); // 双线性放大低分辨率体积云。
		vec3 color = CurveToLinear(base.rgb) * MAIN_OUTPUT_FACTOR; // 一号画面解回管线亮度单位。
		color = color * cloudImage.a + cloudImage.rgb; // 体积云：天空乘透过率加云色。
		#ifdef OMNI_PLANAR_CLOUDS // 平面云仍在全分辨率上算，接在体积云之后，顺序与从前一致。
			if (cameraPosition.y < OMNI_PLANAR_ALTITUDE && !intersectsGround)
				PlanarClouds(color, worldDir, camera, noise.y, cloudImage.a); // 平面云，传入体积云留下的透过率。
		#endif
		#if OMNI_CLOUD_CUMULONIMBUS > 0 || defined OMNI_CLOUD_ALTOSTRATUS || defined OMNI_CLOUD_CIRRUS // 附加层同样在全分辨率上叠加。
			float cloudTransmittance = cloudImage.a; // 从体积云留下的透过率接着算。
			NubisExtraLayers(color, worldDir, windDirection, camera, noise, intersectsGround, cloudTransmittance); // 卷云、高层云与积雨云。
		#endif

		deferredOutput1 = vec4(LinearToCurve(color / MAIN_OUTPUT_FACTOR), base.a); // 换回管线亮度单位并编码写回一号。
	}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
