/*
天空渲染：延迟三号片元阶段画天空像素、反射天空盒图与云影贴图，把大气散射、体积云、平面云、日月星与天空盒合成到一起。
调用位置：`rendering/deferred.glsl` 的延迟三号片元分支在引入天空、云、光照与氛围文件后引入本文件。
    该分支的片元 `main()` 只调用 `RenderDeferredSky()`；主天空与反射天空盒两段几乎相同的流程合并成 `AccumulateSkyClouds()`。
可复制示例：
    调用方先声明 `texelCoord`、`texCoord`、`in` 光色方向、阴影采样器与一号二号输出，再引入本文件；
    随后 `void main(){ RenderDeferredSky(); }` 即写出延迟三号的两个输出。
调用前提（iterationT 原样保留）：全局量 `texelCoord`、`texCoord`、`worldSunVector`、`worldMoonVector`、
    `timeNoon`、`timeMidnight` 与输出 `deferredOutput1`、`deferredOutput2` 由绘制主体在引入前给出，本文件不重复声明；
    相机、时间与天气由 `bind/` 的绑定结构提供。
设计原因与取舍：
    主天空与反射天空盒原本是两段近逐行复制的代码，`hop-audit-final.md` 记为越界复制；这里抽成 `AccumulateSkyClouds()`，
    仅把两者真正不同的量作为参数传入（相机、方向、噪声、地平线开关），公式与调用顺序逐行保持一致。
    两个相机参数的原因：反射天空盒查大气用被压低的高度 `cameraSkyBox`，体积云仍按真实相机 `camera` 步进，
    方向判据两处都用主视线 `worldDir.y`，这些是 iterationT 原样行为，不能顺手“修正”。
    云与星空的函数在 `effects/cloud/cloud.glsl`、`effects/sky/sky.glsl` 里，本文件只负责按顺序调用与合成。
    资源包天空（`OMNI_RESOURCEPACK_SKY`，只主世界生效）：把零号画面里原版与资源包画好的整片天空当底色，程序化大气退到
    只算透过率与地面相交判据（`addAtmosphere` 传假），日月与星空也交给资源包；云、极光与彩虹仍由本文件叠在底色上。
    反射天空盒不受影响，仍用程序化大气。这是项目额外功能，默认关闭；底色亮度用 `OMNI_RESOURCEPACK_SKY_BRIGHTNESS` 调节。
*/
#ifndef OMNI_SKY_RENDER_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_SKY_RENDER_INCLUDED
// 相机、时间与天气输入由绑定层整理成普通结构体，本文件只负责合成。
#include "/bind/camera.glsl"
#include "/bind/time.glsl"
#include "/bind/weather.glsl"

// --- 资源包天空底色 ---
// 读零号画面里原版与资源包画好的天空：天空程序按原版加色混合把各层叠进零号，这里从伽马空间转线性再乘亮度档。
// 为什么只能读零号画面：资源包的自定义天空层在天空绘制阶段被画成几何，没有暴露成采样器，只能读它画出来的结果。
// 为什么先转线性：零号存的是贴图色（伽马空间），而天空底色要与程序化大气在同一线性单位里比较与合成。
#if OMNI_RESOURCEPACK_SKY // 只在开启时生成，默认构建里连这个函数都不编出来。
vec3 omniResourcePackSky(){
	return GammaToLinear(texelFetch(colortex0, texelCoord, 0).rgb) * OMNI_RESOURCEPACK_SKY_BRIGHTNESS; // 天空底色。
}
#endif

// --- 天空与云的共用累积 ---
// 把大气辐射与全部云层累积到 `color`，并回填大气透过率、云透过率与月食压暗因子。
// 主天空与反射天空盒共用这一段：方向、相机、噪声不同，公式相同。
// `applyClouds` 为假时只叠大气，跳过全部云层；低分辨率模式用它让主天空先不画云，云改到延迟八号贴回。
// `addAtmosphere` 为假时不再叠程序化大气，改用调用方已铺好的底色（资源包天空）；大气仍照查一次，供云用它回填的透过率与地面相交判据。
void AccumulateSkyClouds(vec3 dir, vec3 atmosphereCamera, vec3 cloudCamera, vec2 noise, float planarNoise,
						 bool horizon, bool dirBelowHorizon, vec2 cloudAltitude, vec3 windDirection, bool applyClouds, bool addAtmosphere,
						 inout vec3 color, out vec3 transmittance, out float cloudTransmittance, out float eclipseDarkening){
	OmniCamera cameraData = bind_camera(); // 相机位置、画面尺寸与矩阵只读一次。
	transmittance = vec3(1.0); // 大气透过率初值，由下面的查表回填。
	bool ray_r_mu_intersects_ground; // 视线是否打到地面，由大气查表回填。
	vec3 atmosphere = GetSkyRadiance(atmosphereCamera, dir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground); // 查预计算大气的天空辐射。
	eclipseDarkening = CalculateEclipseDarkening(dir, worldSunVector, worldMoonVector); // 月食：日月对齐时把天空压暗，默认轨道下日月相对所以不触发。
	if (addAtmosphere) color += atmosphere * eclipseDarkening; // 默认把带月食压暗的大气叠上；资源包天空时底色已给，不再叠。

	cloudTransmittance = 1.0; // 云留下的透过率初值。
	#ifdef OMNI_VOLUMETRIC_CLOUDS // 打开体积云才步进。
		if (applyClouds && (cameraData.position.y > cloudAltitude.x || !ray_r_mu_intersects_ground) && (cameraData.position.y < cloudAltitude.y || dirBelowHorizon)) // 相机在云层附近或朝上看才需要步进。
			NubisCumulus(color, dir, cloudAltitude, windDirection, cloudCamera, noise, cloudTransmittance); // 体积云。
	#endif

	#if OMNI_PLANAR_CLOUDS // 打开平面云才算。
		if (applyClouds && cameraData.position.y < OMNI_PLANAR_ALTITUDE && !ray_r_mu_intersects_ground) // 相机在云平面以下才看得到。
			PlanarClouds(color, dir, atmosphereCamera, planarNoise, cloudTransmittance); // 平面云。
	#endif

	#if OMNI_CLOUD_CUMULONIMBUS > 0 || OMNI_CLOUD_ALTOSTRATUS || OMNI_CLOUD_CIRRUS // 附加层默认全关，关闭时连调用都不生成。
		if (applyClouds) NubisExtraLayers(color, dir, windDirection, cloudCamera, noise, ray_r_mu_intersects_ground, cloudTransmittance); // 卷云、高层云与积雨云。
	#endif
}

// --- 延迟三号片元主流程 ---
// 画天空像素（写一号）与反射天空盒图（写二号），并顺带在右上角写云影贴图；整段与 iterationT 的 `deferred3` 逐行一致。
void RenderDeferredSky(){
	OmniCamera cameraData = bind_camera(); // 相机位置、画面尺寸与矩阵只读一次。
	OmniTime time = bind_time(); // 云漂动时间只读一次。
	OmniWeather weather = bind_weather(); // 降雨与水下标记只读一次。
	float depth = texelFetch(depthtex1, texelCoord, 0).x; // 不含半透明的不透明深度。
	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置。

	#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
		if (depth == 1.0){ // 天空像素改读远景深度。
			depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
		}
	#endif

	vec3 worldPos = mat3(cameraData.viewInverse) * viewPos; // 视空间转相机相对世界空间。

	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldDir = normalize(worldPos); // 世界方向。

	#ifdef DISTANT_HORIZONS
		float farDist = max(dhFarPlane, 1024.0); // 有远景时用远景远裁剪面。
	#else
		float farDist = max(cameraData.farPlane * 1.2, 1024.0); // 否则用近景远裁剪面留一点余量。
	#endif
	float cloudShadow = 1.0; // 全局云影初值，本程序不使用。

	#ifdef OMNI_ATMO_HORIZON // 打开地平线时相机高度有下限。
		vec3 camera = vec3(0.0, max(cameraData.position.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 打开地平线时相机高度有下限。
	#else
		vec3 camera = vec3(0.0, max(cameraData.position.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 否则至少按海平面高度算。
	#endif

	vec3 cameraSkyBox = vec3(0.0, max(cameraData.position.y, ATMO_SKYBOX_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 天空盒投影用的相机高度。

	vec2 noise_0 = vec2(bayer64(gl_FragCoord.xy), 0.5); // 天空盒像素用的固定拜尔抖动。
	vec2 noise_1 = BlueNoiseTemporal().xy; // 主画面用的逐帧蓝噪声。

	vec2 cloudAltitude = vec2(mix(OMNI_CLOUD_CLEAR_ALTITUDE, OMNI_CLOUD_RAIN_ALTITUDE, weather.wetness)); // 晴雨两档云底高度。
	cloudAltitude.y += mix(OMNI_CLOUD_CLEAR_THICKNESS, OMNI_CLOUD_RAIN_THICKNESS, weather.wetness); // 加上层厚得到云顶高度。

	float wind = 0.0005 * (time.seconds * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 云漂动的时间量。
	vec3 windDirection = vec3(1.0, weather.wetness * 0.1 - 0.05, -0.4) * wind; // 云漂动的方向与位移。

	deferredOutput1 = texelFetch(colortex1, texelCoord, 0); // 默认原样保留场景颜色。

	// ------------------------------ 天空 ------------------------------
	if (depth == 1.0){ // 只有天空像素才重画。
		vec3 finalComposite = vec3(0.0); // 累积的天空颜色。

		#ifdef OMNI_ATMO_HORIZON
			bool horizon = true; // 打开地平线时地平线方向也算地面大气。
		#else
			bool horizon = false; // 否则地平线以下不算地面大气。
		#endif
		vec3 transmittance; // 大气透过率，由共用累积回填；主天空要拿它给天体做衰减。
		float cloudTransmittance; // 云留下的透过率。
		float eclipseDarkening; // 月食压暗因子，太阳圆盘也要用。
		#ifdef OMNI_CLOUD_LOWRES // 低分辨率模式：主天空先不画云，云留给延迟八号放大贴回。
			bool applyClouds = false; // 跳过云层，只叠大气与天体。
		#else // 原分辨率：与从前完全一致，天空这一步就把云画好。
			bool applyClouds = true; // 天空与云一起累积。
		#endif
		#if OMNI_RESOURCEPACK_SKY && defined OMNI_OVERWORLD // 资源包天空：先铺资源包画好的整片天空当底色。
			finalComposite = omniResourcePackSky(); // 资源包天空底色。
			bool addAtmosphere = false; // 程序化大气不再叠进画面，只用来给云提供透过率与地面相交判据。
		#else // 默认：底色由程序化大气提供。
			bool addAtmosphere = true; // 叠预计算大气。
		#endif
		AccumulateSkyClouds(worldDir, camera, camera, noise_1, noise_1.y, horizon, worldDir.y < 0.0, cloudAltitude, windDirection, applyClouds, addAtmosphere, finalComposite, transmittance, cloudTransmittance, eclipseDarkening); // 叠底色（大气或资源包天空）与全部云层。

		#if !(OMNI_RESOURCEPACK_SKY && defined OMNI_OVERWORLD) // 默认路径：叠零号画面的日月贴图与程序化星空。
		vec3 celestial = GammaToLinear(texelFetch(colortex0, texelCoord, 0).rgb) * (OMNI_SKY_TEXTURE_BRIGHTNESS * 0.2); // 零号画面的天体颜色转线性并按选项缩放。

		#if OMNI_STAR_TYPE == 1
			celestial += CalculateStars(worldDir, worldSunVector); // 点状星空，太阳方向由本程序传入。
		#endif

		celestial *= OMNI_NIGHT_BRIGHTNESS; // 天体整体按夜间亮度缩放。

		vec3 sunDisc = RenderSunDisc(worldDir, worldSunVector) * (0.2 + timeNoon * 3.0) * eclipseDarkening; // 太阳圆盘，白天更亮，月食时一起压暗。
		vec3 moonDisc = CalculateMoonDiscColor() * (RenderMoonDisc(worldDir, worldMoonVector) * OMNI_NIGHT_BRIGHTNESS * CalculateMoonPhaseBrightness(worldSunVector, worldMoonVector)); // 月亮圆盘：颜色由真实月亮选项决定，亮度再乘月相比例。

		#ifdef OMNI_MOON_TEXTURE
			celestial = mix(celestial * cloudTransmittance + sunDisc + moonDisc, // 用贴图月亮时水下不画月亮。
							(celestial + sunDisc + moonDisc * float(weather.eyeInWater != 0)) * cloudTransmittance,
							mix(1.0, OMNI_RAIN_SHADOW, weather.wetness));
		#else
			celestial = mix(celestial * cloudTransmittance + sunDisc + moonDisc, // 不用贴图月亮时水里也画月亮。
							(celestial + sunDisc + moonDisc) * cloudTransmittance,
							mix(1.0, OMNI_RAIN_SHADOW, weather.wetness));
		#endif

		finalComposite += celestial * transmittance * 200.0; // 天体带大气透过率叠到天空上。
		#endif // 默认路径结束；资源包天空时不叠程序化天体，日月星空已由资源包提供。

		finalComposite = omniAtmosphere(finalComposite, worldDir); // Omni 额外功能：叠加极光与彩虹，默认关闭。
		#ifdef OMNI_CAVE_MODE
			finalComposite = mix(finalComposite, vec3(max(OMNI_NOLIGHT_BRIGHTNESS, 0.00007) * 0.05), saturate(weather.eyeBrightnessZero)); // 完全看不到天空时换成极暗配色。
		#endif

		finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
		finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

		deferredOutput1 = vec4(finalComposite, 1.0); // 写回一号画面。
	}

	// ------------------------------ 天空盒图 ------------------------------
	deferredOutput2 = texelFetch(colortex2, texelCoord, 0); // 默认原样保留二号画面。

	float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(cameraData.screenSize.x / 3.3, cameraData.screenSize.y * 0.45))); // 天空盒图边长。
	vec2 skyImageTexel = gl_FragCoord.xy; // 当前像素坐标。
	skyImageTexel.y -= ceil(cameraData.screenSize.y * 0.5 + 1.0); // 抬到上半屏。
	vec2 boundary = tileSize * vec2(3.0, 2.0); // 三乘二张面的总范围。

	if (clamp(skyImageTexel, vec2(0.0), boundary) == skyImageTexel){ // 只有落在天空盒图范围内才重画。
		vec3 skyImage = vec3(0.0); // 累积的天空盒颜色。

		vec3 viewVector = UnprojectSky(skyImageTexel, tileSize); // 纹素坐标反解成世界方向。

		#ifdef OMNI_ATMO_REFLECTION_HORIZON
			bool horizon = true; // 反射天空盒是否处理地平线。
		#else
			bool horizon = false; // 关闭时地平线以下不算地面大气。
		#endif
		vec3 transmittance; // 大气透过率，本段不使用，仅满足共用累积的输出。
		float cloudTransmittance; // 云留下的透过率，写进二号透明通道供顶点阶段读云量。
		float eclipseDarkening; // 月食压暗因子，本段不使用。
		AccumulateSkyClouds(viewVector, cameraSkyBox, camera, noise_0, noise_0.x, horizon, worldDir.y < 0.0, cloudAltitude, windDirection, true, true, skyImage, transmittance, cloudTransmittance, eclipseDarkening); // 与主天空同一流程，只是相机与噪声不同；天空盒始终保持全分辨率，也始终叠程序化大气。

		#ifdef OMNI_CAVE_MODE
			skyImage = mix(skyImage, vec3(max(OMNI_NOLIGHT_BRIGHTNESS, 0.00005) * 0.07), weather.eyeBrightnessZero); // 洞穴模式下的极暗天空盒。
		#endif

		skyImage /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
		skyImage = LinearToCurve(skyImage); // 四次方根编码。
		deferredOutput2 = vec4(skyImage, cloudTransmittance); // 透过率存进透明通道供顶点阶段读云量。
	}

	#ifdef OMNI_CLOUD_SHADOW
		vec2 shadowTexel = cameraData.screenSize - gl_FragCoord.xy; // 云影贴在画面右上角，坐标要翻转。
		float shadowTexSize = floor(min(cameraData.screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 方贴图边长。
		shadowTexel /= shadowTexSize; // 换成零到一的贴图坐标。

		if (saturate(shadowTexel) == shadowTexel){ // 只有落在方贴图范围内才算云影。
			deferredOutput2.r = CloudShadowTex(shadowTexel, cloudAltitude, windDirection); // 从云密度算出该处云影。
		}
	#endif
}
#endif // 文件守卫结束。
