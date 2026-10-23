/*
单个程序的绘制主体：只包含 OMNI_DEFERRED8_PASS 对应的阶段与算法。
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

		// 延迟三号顶点与合成顶点共用一段光色计算，并按原程序打开云光照分支得到固定的高空相机。
		#define VS_CLOUD_LIGHTING 1
		#include "/rendering/lights.glsl"

#endif

// ================================ 片元阶段 ================================

#if defined OMNI_FRAGMENT
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
	#include "/bind/sky/sky.glsl"
	#include "/bind/cloud/cloud.glsl"
	#include "/bind/lighting/sunlight.glsl"
	#include "/bind/sky/atmosphere.glsl"
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
		#if OMNI_PLANAR_CLOUDS // 平面云仍在全分辨率上算，接在体积云之后，顺序与从前一致。
			if (cameraPosition.y < OMNI_PLANAR_ALTITUDE && !intersectsGround)
				PlanarClouds(color, worldDir, camera, noise.y, cloudImage.a); // 平面云，传入体积云留下的透过率。
#endif
		#if OMNI_CLOUD_CUMULONIMBUS > 0 || OMNI_CLOUD_ALTOSTRATUS || OMNI_CLOUD_CIRRUS // 附加层同样在全分辨率上叠加。
			float cloudTransmittance = cloudImage.a; // 从体积云留下的透过率接着算。
			NubisExtraLayers(color, worldDir, windDirection, camera, noise, intersectsGround, cloudTransmittance); // 卷云、高层云与积雨云。
#endif

		deferredOutput1 = vec4(LinearToCurve(color / MAIN_OUTPUT_FACTOR), base.a); // 换回管线亮度单位并编码写回一号。
	}
#endif
#endif
