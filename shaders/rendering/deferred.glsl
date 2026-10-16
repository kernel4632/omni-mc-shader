/*
延迟绘制主体：照 iterationT 的 `deferred`、`deferred1` 到 `deferred6` 七个全屏程序一比一移植。
职责与写出缓冲：
    `deferred` 写七号：左下角最多五百像素见方的水面波法线，供焦散采样；
    `deferred1` 写二号：反射阴影图全局光的时间滤波历史；
    `deferred2` 写一号：全局光的空间滤波与地平线遮蔽；
    `deferred3` 写一号和二号：天空、体积云、平面云、星星、日月，以及上半屏天空盒与右上角云影贴图；
    `deferred4`、`deferred5` 写二号：云影贴图横向、纵向高斯模糊；
    `deferred6` 写四号和六号：把不透明法线光照图与材质编号复制给半透明层当默认值。
调用位置：各维度同名入口定义阶段宏、维度宏与对应 `OMNI_DEFERRED*_PASS` 后引入本文件。
    本文件不写 `#version`，语言版本由入口声明；顶点阶段用加载器给的整屏三角形，不需要投影矩阵。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_DEFERRED2_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_DEFERRED3_PASS 1` 再引入本文件即得延迟三号顶点阶段。
关键设计原因与取舍：
    延迟三号、四号、五号把四号六号画面当三维云噪声读，所以文件顶部按这三个程序打开 `COLORTEX_CLOUDNOISE`，
    采样器类型才由 `common/uniforms.glsl` 选对；其余程序保持二维画面。
    原程序一个程序一个文件，本文件把它们合成一个主体，按程序宏分派；每个程序的片元 `main()` 与 iterationT 逐行一致。
    延迟顶点里只有三号要算光色（走 `rendering/lights.glsl`），四号五号要算云影贴图坐标，其余只需铺满屏幕。
    效果文件算法与本文件里的合并方式见 `docs/parity.md`；本文件只安排阶段流程与输入输出，不复制算法。
*/
#ifndef OMNI_DEFERRED_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_DEFERRED_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 延迟三号、四号、五号在延迟阶段把四号六号画面换成三维云噪声，宏名照 iterationT 原名由程序自己打开。
// 末地的延迟四号是全局光空间滤波，不读云噪声，所以要把它排除在外。
#if defined OMNI_DEFERRED3_PASS || ((defined OMNI_DEFERRED4_PASS || defined OMNI_DEFERRED5_PASS) && !defined OMNI_END)
	#define COLORTEX_CLOUDNOISE 1 // 打开后四号六号声明成三维采样器。
#endif

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX

	#if defined OMNI_DEFERRED3_PASS // 只有主世界有延迟三号（画天空），顶点与合成共用一段光色计算。
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
	void main(){
		#if !defined OMNI_CAUSTICS && (!defined OMNI_VFOG || !defined OMNI_UNDERWATER_VFOG)
			discard; // 既不开焦散又不开水下体积雾时没人读这张法线图，整片丢弃。
		#endif
		const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。

		vec3 screenCaustics = vec3(0.0, 0.0, 1.0); // 默认朝上的波法线。
		vec2 causticsCoord = gl_FragCoord.xy * (50.0 / min(screenSize.y, maxCausticsNormalHeight)); // 把屏幕坐标换算到波浪空间。
		screenCaustics = GetWavesNormal(vec3(causticsCoord.x, 1.0, causticsCoord.y), 25.0).xyz; // 求该处的波法线。

		deferredOutput7 = vec4(EncodeNormal(screenCaustics), 0.0, 0.0); // 八面体编码后写进七号。
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
		void main(){
			const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。
			vec3 screenCaustics = vec3(0.0, 0.0, 1.0); // 默认朝上的波法线。
			vec2 causticsCoord = gl_FragCoord.xy * (50.0 / min(screenSize.y, maxCausticsNormalHeight)); // 把屏幕坐标换算到波浪空间。
			screenCaustics = GetWavesNormal(vec3(causticsCoord.x, 1.0, causticsCoord.y), 25.0).xyz; // 求该处的波法线。
			deferredOutput7 = vec4(EncodeNormal(screenCaustics), 0.0, 0.0); // 八面体编码后写进七号。
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
	void main(){
		float depth = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的不透明深度。
		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置，自动撤销抖动。

		#ifdef DISTANT_HORIZONS
			if (depth == 1.0){ // 天空像素改读远景深度。
				depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
				viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
			}
		#endif

		vec4 gi = vec4(0.0, 0.0, 0.0, 1.0); // 默认没有全局光，遮蔽为一。

		if (depth < 1.0){ // 有几何才算全局光与遮蔽。
			vec3 viewDir = normalize(viewPos); // 视线方向。
			vec3 normal = DecodeNormal(texelFetch(colortex3, texelCoord, 0).xy); // 从三号画面解出法线。
			float opaqueDist = length(viewPos); // 不透明表面到相机的距离。

			#ifdef OMNI_GTAO
				if (-viewPos.z > 0.15) gi.a = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal); // 太近的像素不算遮蔽。
			#endif

			#ifdef OMNI_GI_RSM
				gi.rgb = GI_SpatialFilter(-viewPos.z, normal, viewDir); // 半分辨率全局光做空间滤波。
			#endif
		}

		deferredOutput1 = gi; // 写回一号画面。
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
	void main(){
		float depth = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的不透明深度。
		vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置。

		#ifdef DISTANT_HORIZONS
			if (depth == 1.0){ // 天空像素改读远景深度。
				depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
				viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
			}
		#endif

		vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。

		vec3 viewDir = normalize(viewPos); // 视线方向。
		vec3 worldDir = normalize(worldPos); // 世界方向。

		#ifdef DISTANT_HORIZONS
			float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
		#else
			float farDist = max(far * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
		#endif
		float cloudShadow = 1.0; // 全局云影初值，本程序不使用。

		#ifdef OMNI_ATMO_HORIZON
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 打开地平线时相机高度有下限。
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 否则至少按海平面高度算。
		#endif

		vec3 cameraSkyBox = vec3(0.0, max(cameraPosition.y, ATMO_SKYBOX_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 天空盒投影用的相机高度。

		vec2 noise_0 = vec2(bayer64(gl_FragCoord.xy), 0.5); // 天空盒像素用的固定拜尔抖动。
		vec2 noise_1 = BlueNoiseTemporal().xy; // 主画面用的逐帧蓝噪声。

		vec2 cloudAltitude = vec2(mix(OMNI_CLOUD_CLEAR_ALTITUDE, OMNI_CLOUD_RAIN_ALTITUDE, wetness)); // 晴雨两档云底高度。
		cloudAltitude.y += mix(OMNI_CLOUD_CLEAR_THICKNESS, OMNI_CLOUD_RAIN_THICKNESS, wetness); // 加上层厚得到云顶高度。

		float wind = 0.0005 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_FTC_OFFSET); // 云漂动的时间量。
		vec3 windDirection = vec3(1.0, wetness * 0.1 - 0.05, -0.4) * wind; // 云漂动的方向与位移。

		deferredOutput1 = texelFetch(colortex1, texelCoord, 0); // 默认原样保留场景颜色。

		// ------------------------------ 天空 ------------------------------
		if (depth == 1.0){ // 只有天空像素才重画。
			vec3 finalComposite = vec3(0.0); // 累积的天空颜色。

			vec3 transmittance = vec3(1.0); // 大气透过率。

			#ifdef OMNI_ATMO_HORIZON
				bool horizon = true; // 打开地平线时地平线方向也算地面大气。
			#else
				bool horizon = false; // 否则地平线以下不算地面大气。
			#endif
			bool ray_r_mu_intersects_ground; // 视线是否打到地面，由大气函数回填。
			vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground); // 查预计算大气的天空辐射。
			float eclipseDarkening = CalculateEclipseDarkening(worldDir, worldSunVector, worldMoonVector); // 月食：日月对齐时把天空压暗，默认轨道下日月相对所以不触发。
			atmosphere *= eclipseDarkening; // 把压暗因子乘到天空辐射上。

			finalComposite += atmosphere; // 先叠大气。

			float cloudTransmittance = 1.0; // 云留下的透过率。
			#ifdef OMNI_VOLUMETRIC_CLOUDS
				if ((cameraPosition.y > cloudAltitude.x || !ray_r_mu_intersects_ground) && (cameraPosition.y < cloudAltitude.y || worldDir.y < 0.0)) // 相机在云层附近或朝上看才需要步进。
					NubisCumulus(finalComposite, worldDir, cloudAltitude, windDirection, camera, noise_1, cloudTransmittance); // 体积云。
			#endif

			#ifdef OMNI_PLANAR_CLOUDS
				if (cameraPosition.y < OMNI_PC_ALTITUDE && !ray_r_mu_intersects_ground) // 相机在云平面以下才看得到。
					PlanarClouds(finalComposite, worldDir, camera, noise_1.y, cloudTransmittance); // 平面云。
			#endif

			vec3 celestial = GammaToLinear(texelFetch(colortex0, texelCoord, 0).rgb) * (OMNI_SKY_TEXTURE_BRIGHTNESS * 0.2); // 零号画面的天体颜色转线性并按选项缩放。

			#if OMNI_STAR_TYPE == 1
				celestial += CalculateStars(worldDir, worldSunVector); // 点状星空，太阳方向由本程序传入。
			#endif

			celestial *= OMNI_NIGHT_BRIGHTNESS; // 天体整体按夜间亮度缩放。

			vec3 sunDisc = RenderSunDisc(worldDir, worldSunVector) * (0.2 + timeNoon * 3.0) * eclipseDarkening; // 太阳圆盘，白天更亮，月食时一起压暗。
			vec3 moonDisc = CalculateMoonDiscColor() * (RenderMoonDisc(worldDir, worldMoonVector) * OMNI_NIGHT_BRIGHTNESS * CalculateMoonPhaseBrightness(worldSunVector, worldMoonVector)); // 月亮圆盘：颜色由真实月亮选项决定，亮度再乘月相比例。

			#ifdef OMNI_MOON_TEXTURE
				celestial = mix(celestial * cloudTransmittance + sunDisc + moonDisc, // 用贴图月亮时水下不画月亮。
								(celestial + sunDisc + moonDisc * float(isEyeInWater != 0)) * cloudTransmittance,
								mix(1.0, OMNI_RAIN_SHADOW, wetness));
			#else
				celestial = mix(celestial * cloudTransmittance + sunDisc + moonDisc, // 不用贴图月亮时水里也画月亮。
								(celestial + sunDisc + moonDisc) * cloudTransmittance,
								mix(1.0, OMNI_RAIN_SHADOW, wetness));
			#endif

			finalComposite += celestial * transmittance * 200.0; // 天体带大气透过率叠到天空上。
			finalComposite = omniAtmosphere(finalComposite, worldDir); // Omni 额外功能：叠加极光与彩虹，默认关闭。
			#ifdef OMNI_CAVE_MODE
				finalComposite = mix(finalComposite, vec3(max(OMNI_NOLIGHT_BRIGHTNESS, 0.00007) * 0.05), saturate(eyeBrightnessZeroSmooth)); // 完全看不到天空时换成极暗配色。
			#endif

			finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
			finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

			deferredOutput1 = vec4(finalComposite, 1.0); // 写回一号画面。
		}

		// ------------------------------ 天空盒图 ------------------------------
		deferredOutput2 = texelFetch(colortex2, texelCoord, 0); // 默认原样保留二号画面。

		float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图边长。
		vec2 skyImageTexel = gl_FragCoord.xy; // 当前像素坐标。
		skyImageTexel.y -= ceil(screenSize.y * 0.5 + 1.0); // 抬到上半屏。
		vec2 boundary = tileSize * vec2(3.0, 2.0); // 三乘二张面的总范围。

		if (clamp(skyImageTexel, vec2(0.0), boundary) == skyImageTexel){ // 只有落在天空盒图范围内才重画。
			vec3 skyImage = vec3(0.0); // 累积的天空盒颜色。

			vec3 viewVector = UnprojectSky(skyImageTexel, tileSize); // 纹素坐标反解成世界方向。

			#ifdef OMNI_ATMO_REFLECTION_HORIZON
				bool horizon = true; // 反射天空盒是否处理地平线。
			#else
				bool horizon = false;
			#endif
			vec3 transmittance = vec3(1.0); // 大气透过率。
			bool ray_r_mu_intersects_ground; // 是否打到地面。
			vec3 atmosphere = GetSkyRadiance(cameraSkyBox, viewVector, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground); // 查该方向的天空辐射。
			atmosphere *= CalculateEclipseDarkening(viewVector, worldSunVector, worldMoonVector); // 反射天空盒同样按月食压暗。

			skyImage += atmosphere; // 叠大气。

			float cloudTransmittance = 1.0; // 云留下的透过率。
			#ifdef OMNI_VOLUMETRIC_CLOUDS
				if ((cameraPosition.y > cloudAltitude.x || !ray_r_mu_intersects_ground) && (cameraPosition.y < cloudAltitude.y || worldDir.y < 0.0)) // 与主天空同一判据。
					NubisCumulus(skyImage, viewVector, cloudAltitude, windDirection, camera, noise_0, cloudTransmittance); // 体积云。
			#endif

			#ifdef OMNI_PLANAR_CLOUDS
				if (cameraPosition.y < OMNI_PC_ALTITUDE && !ray_r_mu_intersects_ground) // 相机在云平面以下。
					PlanarClouds(skyImage, viewVector, cameraSkyBox, noise_0.x, cloudTransmittance); // 平面云。
			#endif

			#ifdef OMNI_CAVE_MODE
				skyImage = mix(skyImage, vec3(max(OMNI_NOLIGHT_BRIGHTNESS, 0.00005) * 0.07), eyeBrightnessZeroSmooth); // 洞穴模式下的极暗天空盒。
			#endif

			skyImage /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
			skyImage = LinearToCurve(skyImage); // 四次方根编码。
			deferredOutput2 = vec4(skyImage, cloudTransmittance); // 透过率存进透明通道供顶点阶段读云量。
		}

		#ifdef OMNI_CLOUD_SHADOW
			vec2 shadowTexel = screenSize - gl_FragCoord.xy; // 云影贴在画面右上角，坐标要翻转。
			float shadowTexSize = floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 方贴图边长。
			shadowTexel /= shadowTexSize; // 换成零到一的贴图坐标。

			if (saturate(shadowTexel) == shadowTexel){ // 只有落在方贴图范围内才算云影。
				deferredOutput2.r = CloudShadowTex(shadowTexel, cloudAltitude, windDirection); // 从云密度算出该处云影。
			}
		#endif
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
		void main(){
			float depth = texelFetch(depthtex0, texelCoord, 0).x; // 末地用含半透明的深度。
			vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置。

			#ifdef DISTANT_HORIZONS
				if (depth == 1.0){ // 天空像素改读远景深度。
					depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
					viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
				}
			#endif

			vec4 gi = vec4(0.0, 0.0, 0.0, 1.0); // 默认没有全局光，遮蔽为一。

			if (depth < 1.0){ // 有几何才算全局光与遮蔽。
				vec3 viewDir = normalize(viewPos); // 视线方向。
				vec3 normal = DecodeNormal(texelFetch(colortex3, texelCoord, 0).xy); // 从三号画面解出法线。

				#ifdef OMNI_GTAO
					if (-viewPos.z > 0.15) gi.a = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal); // 太近的像素不算遮蔽。
				#endif

				#ifdef OMNI_GI_RSM
					gi.rgb = GI_SpatialFilter(-viewPos.z, normal, viewDir); // 半分辨率全局光做空间滤波。
				#endif
			}

			deferredOutput1 = gi; // 写回一号画面。
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
#endif // 片元阶段结束。
#endif // 文件守卫结束。
