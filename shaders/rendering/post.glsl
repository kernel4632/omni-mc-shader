/*
后期绘制主体：把 iterationT 的 `composite6` 到 `composite16` 十一个全屏程序合并进一个文件，按程序宏分派。
来源：根目录 `composite6.fsh` 到 `composite16.fsh` 与对应 `.vsh` 一比一移植；算法函数全部来自效果文件。
调用位置：各维度 `composite6` … `composite16` 入口定义阶段宏、维度宏与对应 `OMNI_COMPOSITE*_PASS` 后引入本文件。
    本文件不写 `#version`，语言版本由入口声明；顶点用加载器给的整屏三角形。入口由 `rendering/programs.json` 生成。
可复制示例：
    入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE14_PASS 1`、`#define OMNI_OVERWORLD 1` 再引入本文件；
    入口写 `#define OMNI_VERTEX 1`、`#define OMNI_COMPOSITE9_PASS 1` 再引入本文件即得泛光第一级顶点阶段。
输出约定（对应各程序文件头，见 `rendering/buffers.glsl`）：
    `composite6` 写一号（景深）；`composite7` 写七号（时间抗锯齿历史）；`composite8` 写一号和二号（运动模糊与统计像素）；
    `composite9` … `composite13` 写五号（泛光降采样与升采样链）；`composite14` 写一号（合并泛光、暗角、曝光、色调映射）；
    `composite15` 写一号（`CAS` 锐化）；`composite16` 写八号（放大输出）。
关键设计原因与取舍：
    原程序一个程序一个文件，本文件按程序宏分派；每个程序的片元 `main()` 与 iterationT 逐行一致，只换程序宏与选项名。
    泛光五级与放大程序各自缩放整屏四边形，所以顶点阶段也按程序宏分出不同 `main()`，缩放公式照原程序。
    效果文件把选项分散在各文件里，所以本主体按第六片合同的顺序把它们引入，并为被引入文件的函数补齐它们引用的全局量与采样器。
    景深与动态模糊的算法合并在 `effects/lens.glsl`，泛光在 `effects/bloom.glsl`，曝光与调色在 `effects/color.glsl`，锐化在 `effects/upscale.glsl`。
    注意：`effects/lens.glsl` 里编译整个文件，镜头光斑函数引用 `sunCoord`、`colorSunlight`、`sunVisibility`，
    本程序的顶点不输出这些值，所以按调用前提声明成空全局，让整份文件可编译而本程序不调用它们。
*/
#ifndef OMNI_POST_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_POST_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 放大程序要把八号画面当二维纹理采样，和原程序一样在引入加载器输入前打开这个宏。
#if defined OMNI_COMPOSITE15_PASS || defined OMNI_COMPOSITE16_PASS // 十五号与十六号都引入 `effects/upscale.glsl`。
	#define COLORTEX8_2D 1 // 打开后 `colortex8` 由 `common/uniforms.glsl` 声明成二维采样器。
#endif

// 加载器输入最先引入；顶点阶段也要它提供的 `screenSize` 与 `MC_RENDER_QUALITY`。
#include "/common/uniforms.glsl"

// ================================ 顶点阶段 ================================
// 原程序里泛光五级与放大各写一份顶点做缩放，其余程序统一用 `Lib/Programs/PostVS.glsl` 的整屏三角形。
#ifdef OMNI_VERTEX

	#if defined OMNI_COMPOSITE9_PASS // 泛光第一级：缩小到半屏再四舍五入。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点在零到一的方块上。
			texCoord *= 0.51; // 缩到百分之五十一，覆盖半分辨率画面。
			gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
		}
	#elif defined OMNI_COMPOSITE10_PASS // 泛光第二级：再缩一半。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点。
			texCoord *= 0.255; // 缩到百分之二十五点五。
			gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
		}
	#elif defined OMNI_COMPOSITE11_PASS // 泛光第三级：横向留宽、纵向再缩。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点。
			texCoord *= vec2(0.6, 0.255); // 横纵不同比例，链上各级排成一行。
			gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
		}
	#elif defined OMNI_COMPOSITE12_PASS // 泛光第四级：与第三级同样的缩放。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点。
			texCoord *= vec2(0.6, 0.255); // 与升采样链对齐的横纵比例。
			gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
		}
	#elif defined OMNI_COMPOSITE13_PASS // 泛光第五级：回到半屏。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点。
			texCoord *= 0.51; // 缩到百分之五十一。
			gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
		}
	#elif defined OMNI_COMPOSITE16_PASS // 放大程序：顶点把整屏四边形缩到放大后的分辨率。
		void main(){
			vec2 texCoord = gl_Vertex.xy; // 加载器顶点。
			vec2 finalScreenSize = ceil(screenSize / MC_RENDER_QUALITY); // 放大后的目标尺寸。
			texCoord *= (finalScreenSize + 2.0) / screenSize * 0.5; // 目标尺寸相对屏幕的缩放，多留两像素边框。
			gl_Position = vec4(texCoord * 2.0 - 1.0, step(1.0, MC_RENDER_QUALITY) * 2.0, 1.0); // 有缩放时把深度推到远裁剪面外。
		}
	#else // 其余程序用整屏三角形。
		void main(){
			gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
		}
	#endif

#endif // 顶点阶段结束。

// ================================ 片元阶段 ================================

// --- 合成七号：时间抗锯齿历史 ---
// 只需时间抗锯齿与材质编号；坐标换算依赖 `effects/antialiasing.glsl` 定义的 `OMNI_TAA`，所以先引入材质再引入它。
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE7_PASS

	// 加载器输入；与前文重复但因守卫只会生效一次。
	#include "/common/uniforms.glsl"
	// 共用数学：邻域最值与颜色曲线。
	#include "/common/math.glsl"

	// 先声明被效果函数引用的全局量：函数在解析时就要看得到这些名字，必须放在引入效果文件之前。
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，抗锯齿的邻域取样用。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标，重投影的输入。

	// 提供材质编号 `MATID_*`，抗锯齿的速度重投影引用它。
	#include "/effects/material.glsl"
	// 时间重投影与相机速度；内部再引入坐标换算。
	#include "/effects/antialiasing.glsl"

	/* DRAWBUFFERS:7 */
	layout(location = 0) out vec4 compositeOutput7; // 七号时间抗锯齿历史画面。

	void main(){
		#ifdef OMNI_TAA // 开启时间抗锯齿才做重投影。
			float materialIDs = floor(texelFetch(colortex6, texelCoord, 0).b * 255.0); // 读当前像素的材质编号。
			float depth = 1.0; // 供相机速度函数回填的代表深度。
			vec3 velocity = CalculateCameraVelocity(depth, materialIDs); // 算当前像素相对上一帧的屏幕位移，并回填深度。
			vec4 taa = vec4(0.0); // 重投影结果。

			#if defined OMNI_DISABLE_HAND_TAA && defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 手与玩家都排除。
				if (materialIDs == MATID_HAND || materialIDs == MATID_ENTITIES_PLAYER){ // 这两类像素不用历史。
					taa = texelFetch(colortex1, texelCoord, 0); // 直接用当前帧颜色。
				}else // 其余像素走重投影。
			#elif defined OMNI_DISABLE_HAND_TAA // 只排除手。
				if (materialIDs == MATID_HAND){ // 手不用历史。
					taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色。
				}else // 其余像素走重投影。
			#elif defined OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR // 只排除玩家。
				if (materialIDs == MATID_ENTITIES_PLAYER){ // 玩家不用历史。
					taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色。
				}else // 其余像素走重投影。
			#endif
				{
					taa = TemporalReprojection(texCoord, velocity, depth); // 邻域裁剪后把历史混进当前帧。
				}
		#else // 关闭时间抗锯齿时原样复制当前帧。
			vec4 taa = texelFetch(colortex1, texelCoord, 0); // 当前帧颜色与深度。
		#endif

		compositeOutput7 = taa; // 写回七号，作为下一帧的历史。
	}

#endif // 合成七号结束。

// --- 合成六号、八号、九号到十四号：共用同一批效果文件 ---
// 为什么共用：景深、动态模糊、泛光与合并泛光都编译整份效果文件；`effects/lens.glsl` 的镜头光斑读体积雾选项，
// `effects/bloom.glsl` 的合并泛光读雨、水雾与体积雾选项，`effects/color.glsl` 的曝光统计读洞穴模式选项，
// 所以这些程序都要先把选项归属文件按顺序引入，才不会在编译时看到未定义的宏。选项归属见 `docs/parity.md` 第九节。
#if defined OMNI_FRAGMENT && (defined OMNI_COMPOSITE6_PASS || defined OMNI_COMPOSITE8_PASS || defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS || defined OMNI_COMPOSITE14_PASS)

	// 加载器输入。
	#include "/common/uniforms.glsl"
	// 共用数学：曲线、亮度、打包与三次采样。
	#include "/common/math.glsl"

	// --- 被引入效果文件的函数会引用这些全局量与采样器，必须先声明它们 ---
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
	vec2 sunCoord; // 太阳在屏幕上的位置，只被镜头光斑函数引用；本程序不调用，声明成空全局。
	vec3 worldShadowVector; // 阴影相机对应的世界光方向。
	vec3 shadowVector; // 上面那个方向在视空间的值。
	vec3 worldSunVector; // 太阳的世界方向。
	vec3 worldMoonVector; // 月亮的世界方向。
	vec3 colorShadowlight; // 日月直射光色之和。
	vec3 colorSunlight; // 太阳直射光色，镜头光斑按它染色。
	vec3 colorMoonlight; // 月亮直射光色。
	vec3 colorSkylight; // 日月环境光色之和。
	vec3 colorSunSkylight; // 太阳一侧的环境光色。
	vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	vec3 colorTorchlight; // 火把光色。
	float timeNoon; // 太阳高度因子。
	float timeMidnight; // 月亮高度因子。
	float sunVisibility; // 太阳可见度，只被镜头光斑函数引用；本程序不调用，声明成空全局。
	uniform sampler2D shadowtex0; // 阴影遮挡图，被引入的阴影查询函数引用。
	uniform sampler2D shadowtex1; // 阴影实心图。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	uniform sampler2D shadowcolor1; // 阴影法线天光图。
	uniform sampler2D gaux1; // 第一张涟漪动画贴图，雨点涟漪函数引用。
	uniform sampler2D gaux2; // 第二张涟漪动画贴图。
	uniform sampler2D gaux3; // 第三张涟漪动画贴图。
	uniform float rainStrength; // 降雨强度，雨点涟漪函数引用。
	#ifdef OMNI_NETHER // 下界泛光按群系调整，需要这几个群系平滑量。
		uniform float BiomeNetherWastesSmooth; // 下界荒地群系平滑量。
		uniform float BiomeSoulSandValleySmooth; // 灵魂沙峡谷群系平滑量。
		uniform float BiomeCrimsonForestSmooth; // 绯红森林群系平滑量。
		uniform float BiomeWarpedForestSmooth; // 诡异森林群系平滑量。
		uniform float BiomeBasaltDeltasSmooth; // 玄武岩三角洲群系平滑量。
	#endif

	// 材质编号（并提供视差与材质选项）、时间抗锯齿选项（先定义 `OMNI_TAA` 供坐标换算使用）。
	// 提供 `MATID_*` 与材质选项。
	#include "/effects/material.glsl"
	// 提供 `OMNI_TAA` 与时间抗锯齿选项，并带入坐标换算。
	#include "/effects/antialiasing.glsl"
	// 选项归属文件：雨在天气文件，水下雾在水面文件，体积雾与云影在雾文件；雾文件又带入阴影、天空、云与光照。
	// 提供雨可见度等选项，泛光的合并读它。
	#include "/effects/weather.glsl"
	// 提供水下雾开关与浓度选项，泛光的合并读它。
	#include "/effects/water.glsl"
	// 提供体积雾选项，并带入水面、阴影、天空、云与光照依赖。
	#include "/effects/fog.glsl"
	// 坐标与深度换算。
	#include "/common/coordinates.glsl"
	// 时间噪声，景深与动态模糊的抖动读它。
	#include "/common/noise.glsl"
	// 曝光统计、曝光值与强光压缩曲线。
	#include "/effects/color.glsl"
	// 景深、动态模糊、暗角与镜头光斑。
	#include "/effects/lens.glsl"
	// 泛光降采样、轴向模糊与合并泛光。
	#include "/effects/bloom.glsl"

	// --- 合成六号：景深 ---
	#if defined OMNI_COMPOSITE6_PASS
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 compositeOutput1; // 一号景深后的场景颜色。
		void main(){
			#ifdef OMNI_DOF // 只有开启景深才写一号画面。
				compositeOutput1 = DepthOfField(); // 按弥散半径散焦合成。
			#endif
		}

	// --- 合成八号：运动模糊与顶行统计像素 ---
	#elif defined OMNI_COMPOSITE8_PASS
		/* DRAWBUFFERS:12 */
		layout(location = 0) out vec4 compositeOutput1; // 一号模糊后的场景颜色。
		layout(location = 1) out vec4 compositeOutput2; // 二号顶行统计像素与保留内容。
		void main(){
			#ifdef OMNI_MOTION_BLUR // 开启动态模糊时按相机位移沿快门方向平均。
				vec3 color = MotionBlur(); // 返回模糊后的线性颜色。
			#else // 关闭时原样取历史画面。
				vec3 color = CurveToLinear(texelFetch(colortex7, texelCoord, 0).rgb); // 读七号画面线性颜色。
			#endif

			#ifdef OMNI_OVERWORLD // 主世界把镜头光斑叠回场景。
				#if defined OMNI_LENS_GLARE || defined OMNI_LENS_FLARE // 只在开了眩光或光斑时。
					color += CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb) * eyeBrightnessSmoothCurved; // 三号画面的光斑按天空光衰减叠加。
				#endif
			#endif

			float bloomGuide = 0.0; // 泛光引导强度；原程序在有标题计数时写入标题的混合权重，标题功能按合同不移植，所以恒为零。

			color = LinearToCurve(color); // 换回管线曲线编码。

			compositeOutput1 = vec4(color, bloomGuide); // 写一号画面，透明度留给泛光引导。

			vec4 data2 = texelFetch(colortex2, texelCoord, 0); // 读二号画面，逐像素改写顶行统计像素。

			vec2 texel = floor(gl_FragCoord.xy); // 当前像素的整数坐标。

			if (texel == vec2(0.0, screenSize.y - 1.0)){ // 顶行横坐标零：自动曝光统计。
				float avgExposure = GetExposureTiles(); // 按分块平均亮度算目标曝光。
				#ifdef OMNI_SMOOTH_EXPOSURE // 开启平滑时按帧时间向前一帧过渡。
					float prevAvgExposure = data2.a; // 上一帧的曝光统计。
					float frameTimeFixed = frameTime + step(frameTime, 0.0) * 5.0; // 帧时间为零时给一个兜底值。
					float exposureTime = saturate((step(avgExposure, prevAvgExposure) * 2.0 + 1.0) * frameTimeFixed / OMNI_EXPOSURE_TIME); // 变暗比变快慢一倍。
					avgExposure = mix(prevAvgExposure, avgExposure, exposureTime); // 混合过去。
				#endif
				data2.a = avgExposure; // 写进透明通道。
			}

			#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW // 顶行横坐标四十：全局云影。
				if (texel == vec2(40.0, screenSize.y - 1.0)){ // 只有这一个像素。
					data2.a = mix(data2.a, CloudShadowFromTex(vec3(0.0), worldShadowVector), 2.0 * frameTime); // 从云影贴图读原点的云影并按帧时间平滑。
				}
			#endif

			#if defined OMNI_DOF && OMNI_CAMERA_FOCUS_MODE == 0 // 顶行横坐标六十：自动对焦深度。
				if (texel == vec2(60.0, screenSize.y - 1.0)){ // 只有这一个像素。
					ivec2 centerTexelCoord = ivec2(screenSize * 0.5); // 屏幕中心像素。
					float prevCenterDepth = data2.a * 0.125 + 0.875; // 解码上一帧保存的中心深度。
					float centerDepth = texelFetch(depthtex0, centerTexelCoord, 0).x; // 读当前屏幕中心深度。
					#ifdef DISTANT_HORIZONS // 有远景模组时中心是远景像素就改用远景深度。
						if (centerDepth == 1.0){ // 深度为一说明近处没有几何。
							centerDepth = texelFetch(dhDepthTex0, centerTexelCoord, 0).x; // 读远景深度。
							centerDepth = ScreenDepth_From_DHScreenDepth(centerDepth); // 换到近景深度尺度。
						}
					#endif
					centerDepth = max(centerDepth, 0.875); // 近处下限，避免对焦距离趋近零。
					float f = exp2(-frameTime * 10.0 / OMNI_DOF_DEPTH_SMOOTH_HALFLIFE); // 对焦深度的平滑因子。
					float centerMaterialID = floor(texelFetch(colortex5, centerTexelCoord, 0).b * 255.0); // 中心的材质编号。
					#ifdef OMNI_DOF_FOCUS_IGNORE_HAND_PARTICLE // 中心是手或粒子时不动焦点。
						if (heldItemId != 358.0 && centerMaterialID == MATID_HAND || centerMaterialID == MATID_PARTICLE) f = 1.0; // 直接用上一帧深度。
					#endif
					data2.a = saturate(mix(centerDepth, prevCenterDepth, f) * 8.0 - 7.0); // 编码后写进透明通道。
				}
			#endif

			compositeOutput2 = data2; // 其余像素原样保留二号画面。
		}

	// --- 合成九号到十三号：泛光降采样与升采样链 ---
	#elif defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS
		/* DRAWBUFFERS:5 */
		layout(location = 0) out vec4 compositeOutput5; // 五号泛光链。

		#if defined OMNI_COMPOSITE9_PASS // 第一级：从一号画面降采样。
			void main(){
				vec2 sampleCoord = texCoord * 2.0; // 采样坐标放大两倍，对应半分辨率画面。
				vec2 border = pixelSize * 4.0 + 1.0; // 允许超出的边界。
				vec3 blur = vec3(0.0); // 默认黑色。
				if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) // 只在画面范围内采样。
					blur = BloomDownSample(colortex1, sampleCoord); // 从一号画面降采样。
				compositeOutput5 = vec4(blur, 0.0); // 写五号。
			}
		#elif defined OMNI_COMPOSITE10_PASS // 第二级：从五号画面继续降采样。
			void main(){
				vec2 sampleCoord = texCoord * 2.0; // 采样坐标放大两倍。
				vec2 border = pixelSize * 2.0 + 0.5; // 允许超出的边界。
				vec3 blur = vec3(0.0); // 默认黑色。
				if (sampleCoord.x <= border.x && sampleCoord.y <= border.y) // 只在画面范围内采样。
					blur = BloomDownSample(colortex5, sampleCoord); // 从五号画面降采样。
				compositeOutput5 = vec4(blur, 0.0); // 写五号。
			}
		#elif defined OMNI_COMPOSITE11_PASS // 第三级：横向轴向高斯，链上各级排成一行。
			void main(){
				vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
				vec2 borderWidth = pixelSize; // 边界用一像素宽。
				const float intervalWidth = 3.0; // 级与级之间隔三像素。
				vec2 border = originSize + borderWidth; // 当前级的边界。
				vec2 axis = vec2(1.0, 0.0); // 横向模糊。
				vec3 blur = vec3(0.0); // 累积颜色。
				vec2 coord = texCoord; // 在本级内推进的坐标。

				if (coord.x <= border.x && coord.y <= border.y){ // 第二级：直接抄。
					blur = CurveToLinear(textureLod(colortex5, clamp(coord, vec2(0.0), originSize), 0.0).rgb); // 读上一级结果。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 下一级宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第三级：横向模糊。
					blur = AxialGaussianBlur(colortex5, coord, vec2(2.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3); // 半径与步长来自泛光文件。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第四级。
					blur = AxialGaussianBlur(colortex5, coord, vec2(4.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD4, BLOOM_STEP_LOD4); // 更长的横向核。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第五级。
					blur = AxialGaussianBlur(colortex5, coord, vec2(8.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD5, BLOOM_STEP_LOD5); // 横向核继续变长。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第六级。
					blur = AxialGaussianBlur(colortex5, coord, vec2(16.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD6, BLOOM_STEP_LOD6); // 横向核继续变长。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第七级。
					blur = AxialGaussianBlur(colortex5, coord, vec2(32.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD7, BLOOM_STEP_LOD7); // 横向核继续变长。
				}
				coord.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
				originSize.x *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第八级。
					blur = AxialGaussianBlur(colortex5, coord, vec2(64.0, 1.0), 0.0, originSize, axis, BLOOM_SIZE_LOD8, BLOOM_STEP_LOD8); // 最长的一级。
				}
				compositeOutput5 = vec4(LinearToCurve(blur), 0.0); // 写回五号。
			}
		#elif defined OMNI_COMPOSITE12_PASS // 第四级：纵向轴向高斯，坐标回拧。
			void main(){
				vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
				vec2 borderWidth = pixelSize; // 边界用一像素宽。
				const float intervalWidth = 3.0; // 级与级之间隔三像素。
				vec2 border = originSize + borderWidth; // 当前级的边界。
				vec2 axis = vec2(0.0, 1.0); // 纵向模糊。
				vec3 blur = vec3(0.0); // 累积颜色。
				vec2 coord = texCoord; // 用于判断落在哪一级的坐标。
				float currInterval = 0.0; // 到下一级的间隔。
				float sampleOrigin = 0.0; // 当前级在图里的起始横坐标。

				if (coord.x <= border.x && coord.y <= border.y){ // 第二级：直接抄。
					blur = CurveToLinear(textureLod(colortex5, clamp(coord, vec2(0.0), originSize), 0.0).rgb); // 读上一级结果。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 当前级的宽度加间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标同步前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第三级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 2.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3); // 纵向核。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第四级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 4.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD4, BLOOM_STEP_LOD4); // 纵向核变长。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第五级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 8.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD5, BLOOM_STEP_LOD5); // 纵向核变长。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第六级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 16.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD6, BLOOM_STEP_LOD6); // 纵向核变长。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第七级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 32.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD7, BLOOM_STEP_LOD7); // 纵向核变长。
				}
				currInterval = originSize.x + pixelSize.x * intervalWidth; // 下一级的间隔。
				coord.x -= currInterval; // 移到下一级。
				sampleOrigin += currInterval; // 起始横坐标前移。
				originSize *= 0.5; // 宽度减半。
				border = originSize + borderWidth; // 更新边界。
				if (coord.x >= -borderWidth.x && coord.x <= border.x && coord.y <= border.y){ // 第八级。
					blur = AxialGaussianBlur(colortex5, texCoord, vec2(1.0, 64.0), sampleOrigin, originSize, axis, BLOOM_SIZE_LOD8, BLOOM_STEP_LOD8); // 最长的一级。
				}
				compositeOutput5 = vec4(LinearToCurve(blur), 0.0); // 写回五号。
			}
		#elif defined OMNI_COMPOSITE13_PASS // 第五级：把各级三次模糊后叠成一张光晕。
			void main(){
				vec2 originSize = vec2(0.25); // 每一级占画面宽度的初值。
				const float intervalWidth = 3.0; // 级与级之间隔三像素。
				vec2 tCoord = texCoord * 2.0; // 采样坐标放大两倍。
				vec2 border = pixelSize * 8.0 + 1.0; // 允许超出的边界。

				float rainAlpha = 0.0; // 雨遮罩；主世界才有。
				#ifdef OMNI_OVERWORLD // 主世界从零号画面读雨量。
					rainAlpha = 1.0 - textureLod(colortex0, tCoord, 0.0).a; // 零号透明度越低说明雨越密。
					rainAlpha = saturate(rainAlpha * OMNI_RAIN_VISIBILITY); // 乘雨可见度选项。
				#endif

				vec2 coord = texCoord; // 当前级坐标。
				vec2 sampleOrigin = vec2(0.0); // 当前级在图里的起始横坐标。
				vec3 bloom = vec3(0.0); // 累积光晕。

				if (tCoord.x <= border.x && tCoord.y <= border.y){ // 只在画面范围内叠加。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.5, screenSize).rgb) * 1.0; // 第二级直接取。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.25 - sampleOrigin, screenSize).rgb) * mix(0.83333333, 1.0, rainAlpha); // 第三级，雨里权重更高。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.125 - sampleOrigin, screenSize).rgb) * mix(0.69444444, 1.0, rainAlpha); // 第四级。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.0625 - sampleOrigin, screenSize).rgb) * mix(0.57870370, 1.0, rainAlpha); // 第五级。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.03125 - sampleOrigin, screenSize).rgb) * mix(0.48225309, 1.0, rainAlpha); // 第六级。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.015625 - sampleOrigin, screenSize).rgb) * mix(0.40187757, 1.0, rainAlpha); // 第七级。

					sampleOrigin.x -= originSize.x + pixelSize.x * intervalWidth; // 移到下一级。
					originSize *= 0.5; // 宽度减半。
					bloom += CurveToLinear(BloomBicubicBlurTexture(colortex5, coord * 0.0078125 - sampleOrigin, screenSize).rgb) * mix(0.33489798, 1.0, rainAlpha); // 第八级。
				}

				bloom *= mix(0.2774, 1.2 / 7.0, rainAlpha); // 雨里整体提亮，原程序保留的常数。

				compositeOutput5 = vec4(LinearToCurve(bloom), 0.0); // 写回五号。
			}
		#endif

	// --- 合成十四号：合并泛光、暗角、曝光、色调映射与高级调色 ---
	#elif defined OMNI_COMPOSITE14_PASS
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 compositeOutput1; // 一号色调映射后的场景颜色。
		void main(){
			ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 本程序局部坐标，与上面同名全局一致。
			vec4 data1 = texelFetch(colortex1, texelCoord, 0); // 读一号画面，透明度是泛光引导。
			vec3 color = CurveToLinear(data1.rgb); // 换成线性颜色。

			#ifdef OMNI_BLOOM // 开启泛光时先合并光晕。
				color = MergeBloom(color, 1.0 - data1.a); // 按引导强度把五号光晕混进来。
			#endif

			#ifdef OMNI_VIGNETTE // 开启暗角时压暗四角。
				color *= Vignette(texCoord, OMNI_VIGNETTE_FALLOFF, OMNI_VIGNETTE_ROUNDNESS); // 按到中心的距离压暗。
			#endif

			color *= GetExposureValue(); // 乘这一帧的曝光。

			#if OMNI_TONEMAP_OPERATOR == 1 // 序号一取 `ACES`。
				color = ACES(color); // 影院标准压缩曲线。
			#elif OMNI_TONEMAP_OPERATOR == 2 // 序号二取无压缩。
				color = None(color); // 只做伽马编码。
			#else // 其余（默认零）取 `AgX`。
				color = AgX(color); // 宽色域压缩，保住高光颜色。
			#endif

			#ifdef OMNI_ADVANCED_COLOR // 开启高级调色时做白光裁剪、亮度伽马与饱和度。
				color = AdvancedColor(color); // 一体化的调色函数。
			#endif

			#ifdef OMNI_SNEAKING_VIGNETTE // 潜行时画面下边缘再加一层暗角。
				color *= mix(1.0, Vignette(vec2(0.5, texCoord.y), 0.7, 0.0), isSneakingSmooth); // 按潜行强度混入。
			#endif

			compositeOutput1 = vec4(color, 0.0); // 写回一号画面。
		}
	#endif

#endif // 合成六号、八号、九号到十四号结束。

// --- 合成十五号：`CAS` 锐化 ---
// 只引入锐化与时间抗锯齿（`CAS` 的开启条件是同时开着时间抗锯齿）；材质文件提供被抗锯齿引用的材质编号。
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE15_PASS

	// 加载器输入；`colortex8` 已按上面的宏声明成二维采样器。
	#include "/common/uniforms.glsl"
	// 共用数学：亮度与邻域最值。
	#include "/common/math.glsl"
	// 提供材质编号，被抗锯齿文件引用。
	#include "/effects/material.glsl"
	// 提供 `OMNI_TAA`，锐化的开启条件读它。
	#include "/effects/antialiasing.glsl"
	// 对比度自适应锐化与放大。
	#include "/effects/upscale.glsl"

	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，邻域取样用。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标，本程序未使用但效果文件引用它。

	/* DRAWBUFFERS:1 */
	layout(location = 0) out vec4 compositeOutput1; // 一号锐化后的场景颜色。

	void main(){
		vec3 color = texelFetch(colortex1, texelCoord, 0).rgb; // 读一号画面颜色。

		#if OMNI_CAS_SHARPNESS > 0 && defined OMNI_TAA // 开了锐化且开着时间抗锯齿才锐化。
			color = FidelityFX_CAS(color, texelCoord); // 按十字邻域对比度自适应锐化。
		#endif

		compositeOutput1 = vec4(color, 0.0); // 写回一号画面。
	}

#endif // 合成十五号结束。

// --- 合成十六号：`FsrEasu` 放大到八号画面 ---
// 只引入放大与共用数学；顶点已把整屏四边形缩到放大后的分辨率。
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE16_PASS

	// 加载器输入；`colortex8` 已按上面的宏声明成二维采样器。
	#include "/common/uniforms.glsl"
	// 共用数学：亮度与邻域最值。
	#include "/common/math.glsl"
	// 边缘方向重采样放大。
	#include "/effects/upscale.glsl"

	/* DRAWBUFFERS:8 */
	layout(location = 0) out vec4 compositeOutput8; // 八号放大输出。

	void main(){
		compositeOutput8 = vec4(FsrEasu(gl_FragCoord.xy, screenSize, ceil(screenSize / MC_RENDER_QUALITY)), 0.0); // 输入是一号画面，输出尺寸是放大后的目标尺寸。
	}

#endif // 合成十六号结束。

#endif // 文件守卫结束。
