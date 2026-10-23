/*
光照与天体方向顶点主体：照 iterationT `Lib/Programs/CompositeVS.glsl` 一比一移植，算出片元要用的方向与光色。
职责：把阴影相机方向还原成世界方向的太阳与月亮，算出四种光源颜色（太阳、月亮、天空、火把）与日夜高度因子，
    按需要再算云可见度、太阳可见度与高光提示强度，全部通过 `out` 变量交给同一程序的片元阶段。
调用位置：合成 `composite`、`composite1`、`composite2`、`composite5` 与延迟 `deferred3` 的顶点阶段。
    这些绘制主体先在顶部按原程序定义对应的 `VS_*` 宏，再引入本文件（本文件提供 `void main()`）。
    合成阶段与延迟三号是否打开某个 `VS_*` 分支由各自绘制主体决定；本文件不写 `#version`，语言版本由入口声明。
可复制示例：
    `#define VS_CLOUD_LIGHTING 1` 再 `#include "/rendering/lights.glsl"`，得到延迟三号用的顶点阶段；
    `#define VS_SHADOW_HIGHLIGHT 1` 再引入，会多算一个 `shadowHighlightStrength` 交给合成二号。
关键设计原因与取舍：
    原程序把输出声明放在引入大气之后，但 Omni 的 `effects/sky/sky.glsl` 把 `CalculateStars` 也收了进来，
    那个函数在函数体里读 `worldSunVector`，所以这里把 `out` 声明提前到引入大气之前，保证整段可编译。
    原程序在本文件里自带一份 `ProjectSky`，Omni 已把它合并进 `effects/sky/sky.glsl` 只留一份，这里直接调用那份。
    `VS_SUN_VISIBILITY` 分支里的镜头光晕选项属于 `effects/lens/lens.glsl`，本文件不把它引入（那份文件含
    片元专用的 `gl_FragCoord`，不能在顶点阶段编译），因此调用本文件的合成五号主体必须先让这些选项可见。
    顶点阶段不调用 `effects/lighting/ambient.glsl`、`effects/shadow/shadow.glsl` 里的查询函数，但整个效果文件会被一起编译，
    所以这里给出它们引用的输入声明；这些声明在顶点阶段没有实际取值，仅用于让文件通过编译。
*/
#ifndef OMNI_LIGHTS_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_LIGHTS_INCLUDED // 置上标记，后续再次引用直接跳过。

// 加载器输入与共用数学先引入；本文件所有计算都基于它们。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// --- 交给片元的方向与光色：名字与 iterationT 相同，片元三号用同名 `in` 接收 ---
out vec3 worldShadowVector; // 阴影相机对应的世界光方向，当作太阳方向基准。
out vec3 shadowVector; // 上面那个方向转到视空间，屏幕空间阴影与镜头效果用。
out vec3 worldSunVector; // 太阳的世界方向，已按太阳角度翻转正负。
out vec3 worldMoonVector; // 月亮的世界方向；默认与太阳相对，开启自定义轨道后由世界时间独立算出。
out vec3 colorShadowlight; // 日月直射光色之和，阴影与云影用。
out vec3 colorSunlight; // 太阳直射光色。
out vec3 colorMoonlight; // 月亮直射光色。
out vec3 colorSkylight; // 日月环境光色之和，云与环境光用。
out vec3 colorSunSkylight; // 太阳一侧的环境光色。
out vec3 colorMoonSkylight; // 月亮一侧的环境光色。
out vec3 colorTorchlight; // 火把光色，由黑体色温算出。
out float timeNoon; // 太阳高度因子，零到一，太阳越高越大。
out float timeMidnight; // 月亮高度因子，零到一，月亮越高越大。

// --- 让被引入效果文件整体可编译的输入声明：顶点阶段不调用这些采样函数，取值不参与本阶段计算 ---
uniform sampler2D shadowtex0; // 阴影遮挡图，环境光与阴影的查询函数引用它。
// 注意：这里不声明 `shadowtex1` 与 `shadowcolor0`。顶点阶段与片元阶段对同名采样器要求类型一致，
// 而合成零号的片元把 `shadowtex1` 声明成 `sampler2DShadow`，顶点这里声明成普通采样器会链接失败；
// 顶点阶段的代码本来也不用它们，交给片元阶段各自声明。
ivec2 texelCoord; // 整数像素坐标，材质读回段引用它（合成程序会一起编译那段）。
vec2 texCoord; // 零到一屏幕坐标，环境遮蔽与时间抗锯齿引用它。

// 火把色温、冷色月光等选项分别属于块光与光照效果文件，引入它们即一并带入天空、云与环境光依赖。
#include "/bind/ground/material.glsl"
#include "/rendering/lighting/sunlight.glsl"

// 太阳可见度只在镜头光晕或眩光开启时才有意义，与 iterationT 一致按这两个选项分派。
#ifdef VS_SUN_VISIBILITY
	#if OMNI_LENS_GLARE || OMNI_LENS_FLARE
		out vec2 sunCoord; // 太阳在屏幕上的坐标，光晕与眩光按它找位置。
		out float sunVisibility; // 太阳可见度，零到一，被云或地形挡住时变低。
	#endif
#endif

// 合成二号需要一份高光提示强度，只有打开该分支时才输出。
#ifdef VS_SHADOW_HIGHLIGHT
	out float shadowHighlightStrength; // 屏幕空间高光提示强度，云越多越亮。
#endif

void main(){
	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 全屏三角形铺满屏幕，顶点来自加载器。

	worldShadowVector = shadowModelViewInverse[2].xyz; // 阴影相机的朝向就是光方向，从逆视图矩阵第三列取。
	shadowVector = mat3(gbufferModelView) * worldShadowVector; // 同一个方向转到视空间。
	worldSunVector = worldShadowVector * (step(sunAngle, 0.5) * 2.0 - 1.0); // 一天的后半段把方向翻到月亮侧。
	worldMoonVector = CalculateWorldMoonVector(worldSunVector); // 月亮方向：默认取太阳的反方向，自定义轨道时由世界时间闭式算出。

	float SdotU = dot(vec3(0.0, 1.0, 0.0), worldSunVector); // 太阳方向相对天顶的余弦。
	float MdotU = dot(vec3(0.0, 1.0, 0.0), worldMoonVector); // 月亮方向相对天顶的余弦。

	timeNoon = 1.0 - pow(1.0 - (clamp(SdotU, 0.2, 0.99) - 0.2) / 0.8, 6.0); // 太阳从低到高平滑升到一。
	timeMidnight = 1.0 - curve(saturate((1.0 - saturate(MdotU)) * 5.0 - 4.0)); // 月亮越高越接近一。

	// 云可见度与太阳可见度共用一段天空盒投影，只有需要它们的两个分支才编译这段。
	#if (defined VS_SUN_VISIBILITY && !defined OMNI_CAVE_MODE && (OMNI_LENS_GLARE || OMNI_LENS_FLARE)) || defined VS_SHADOW_HIGHLIGHT
		float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图边长，与原程序一致。
		vec2 skyImageCoord = ProjectSky(worldShadowVector, tileSize); // 光方向投到天空盒图上的坐标。

		float cloudVisibility = saturate(textureLod(colortex2, skyImageCoord, 0.0).a * 1.5 - 0.5); // 从天空盒透明通道读云量并抬高对比。
		cloudVisibility = mix(cloudVisibility, 1.0, curve(saturate((1.0 - saturate(SdotU)) * 12.0 - 11.0)) * saturate(1.0 - wetness * 1.5)); // 太阳很贴地且不湿时忽略云遮挡。
		cloudVisibility = mix(1.0, cloudVisibility, OMNI_RAIN_SHADOW); // 雨天云影越强，遮挡越按此值生效。
	#endif

	#ifdef VS_SHADOW_HIGHLIGHT
		shadowHighlightStrength = cloudVisibility / MAIN_OUTPUT_FACTOR; // 先换成管线亮度单位。
		shadowHighlightStrength *= timeNoon * 3.0 + 0.2; // 太阳越高高光提示越强。
	#endif

	#ifdef VS_SUN_VISIBILITY
		#if OMNI_LENS_GLARE || OMNI_LENS_FLARE
			#ifdef OMNI_CAVE_MODE
				sunVisibility = 0.0; // 洞穴模式下看不到太阳，直接给零。
			#else
				vec3 sunViewPos = shadowVector * 1e5; // 把太阳放到视空间里很远的一点。
				sunCoord = ScreenPos_From_ViewPos_Raw(sunViewPos).xy; // 投回屏幕坐标，不补抖动。

				float dirVisibility = remapSaturate(shadowVector.z, -0.2, -0.6); // 视线越正对太阳越可见。

				float effectVisibility = saturate(1.0 - blindness - darknessFactor); // 失明与黑暗效果会压暗太阳。

				#ifdef OMNI_GLARE_FLARE_SHADOWBASED
					vec3 cameraShadowPos = ShadowScreenPos_From_WorldPos_Distorted(worldShadowVector * 0.5 + gbufferModelViewInverse[3].xyz); // 沿光方向半格处投到阴影图。
					float shadowVisibility = step(cameraShadowPos.z, textureLod(shadowtex0, cameraShadowPos.xy, 0.0).x); // 那里未被挡住才算太阳可见。

					sunVisibility = dirVisibility * shadowVisibility * cloudVisibility * effectVisibility; // 四项相乘得到最终可见度。
				#else
					float screenVisibility = smoothstep(0.5, 0.45, abs(sunCoord.x - 0.5)) * // 太阳靠近屏幕边缘时淡出。
											 smoothstep(0.5, 0.45, abs(sunCoord.y - 0.5)); // 纵方向同样处理。
					float depthVisibility = step(1.0, textureLod(depthtex0, sunCoord, 0.0).x); // 太阳坐标处是天空才算没被地形挡住。

					#ifdef DISTANT_HORIZONS
						depthVisibility *= step(1.0, textureLod(dhDepthTex0, sunCoord, 0.0).x); // 有远景时远景深度也要是天空。
					#endif

					sunVisibility = dirVisibility * screenVisibility * depthVisibility * cloudVisibility * effectVisibility; // 五项相乘得到最终可见度。
				#endif

				sunVisibility *= timeNoon * 2.0 + 0.2; // 太阳越高可见度越强。
			#endif
		#endif
	#endif

	#ifdef VS_CLOUD_LIGHTING
		vec3 camera = vec3(0.0, 500.0 * 0.001 + atmosphereModel_bottom_radius, 0.0); // 云光照固定按五百米高空算相机高度。
	#else
		#ifdef OMNI_ATMO_HORIZON
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 打开地平线时相机高度有下限。
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 否则至少按海平面高度算。
		#endif
	#endif

	colorSunlight = GetSunAndSkyIrradiance(camera, worldSunVector, worldMoonVector, colorMoonlight, colorSunSkylight, colorMoonSkylight); // 查表得到太阳直射与环境、月亮直射与环境。

	colorSunlight *= 1.0 - curve(saturate((1.0 - saturate(SdotU)) * 30.0 - 29.0)); // 太阳很贴地时收掉直射，避免出现长条亮带。
	colorMoonlight *= 1.0 - curve(saturate((1.0 - saturate(MdotU)) * 5.0 - 4.0)); // 月亮很贴地时同样收掉。
	colorMoonlight *= CalculateMoonPhaseBrightness(worldSunVector, worldMoonVector); // 月相亮度：按日月夹角把月光按被照亮比例压暗，关闭时不改变亮度。
	#ifdef OMNI_COLD_MOONLIGHT
		DoNightEye(colorMoonlight); // 打开冷色月光时把月光混向偏蓝的亮度。
	#endif

	colorShadowlight = colorSunlight + colorMoonlight; // 直射总和，供阴影与云影使用。
	colorSkylight = colorSunSkylight + colorMoonSkylight; // 环境总和，供云与环境光使用。

	colorTorchlight = Blackbody(OMNI_TORCHLIGHT_COLOR_TEMPERATURE); // 火把光色由黑体色温算出。
}
#endif // 文件守卫结束。
