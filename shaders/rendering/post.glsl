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
    片元算法体全部搬到效果页：时间抗锯齿历史在 `effects/clarity/post_taa.glsl`，运动模糊在 `effects/lens/post_motionblur.glsl`，
    标题标志在 `effects/lens/title.glsl`，统计像素在 `effects/color/post_stats.glsl`，泛光链在 `effects/color/post_bloom.glsl`，色调映射在 `effects/color/post_tonemap.glsl`。
    景深与锐化、放大各自只需一句效果函数调用，作为程序的输入输出留在本文件，不再另开文件。
    十一个程序共用的 `texelCoord`、`texCoord`、光色全局量与采样器只声明一次，见 `effects/clarity/post_shared.glsl`。
    泛光五级与放大程序各自缩放整屏四边形，所以顶点阶段也按程序宏分出不同 `main()`，缩放公式照原程序。
    被引入的效果文件会整段编译，它们引用的镜头光斑量 `sunCoord`、`sunVisibility` 在后期顶点阶段不输出，
    所以共享头按调用前提把它们声明成空全局，让整份文件可编译而本程序不调用它们。
*/
#ifndef OMNI_POST_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_POST_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 放大程序要把八号画面当二维纹理采样，和原程序一样在引入加载器输入前打开这个宏。
#if defined OMNI_COMPOSITE15_PASS || defined OMNI_COMPOSITE16_PASS // 十五号与十六号都引入 `effects/clarity/upscale.glsl`。
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
// 只需时间抗锯齿与材质编号；坐标换算依赖 `effects/clarity/antialiasing.glsl` 定义的 `OMNI_TAA`，所以先引入材质再引入它。
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE7_PASS

	// 后期共享声明，全项目只声明一次。
	#include "/effects/clarity/post_shared.glsl"
	// 提供材质编号 `MATID_*`，抗锯齿的速度重投影引用它。
	#include "/effects/ground/material.glsl"
	// 时间重投影与相机速度；内部再引入坐标换算。
	#include "/effects/clarity/antialiasing.glsl"

	/* DRAWBUFFERS:7 */
	layout(location = 0) out vec4 compositeOutput7; // 七号时间抗锯齿历史画面。
	// 时间抗锯齿历史的算法体；写在输出声明之后，算法体才能写 `compositeOutput7`。
	#include "/effects/clarity/post_taa.glsl"

	void main(){ WriteTaaHistory(); } // 重投影历史并写回七号。

#endif // 合成七号结束。

// --- 合成六号、八号、九号到十四号：共用同一批效果文件 ---
// 为什么共用：景深、动态模糊、泛光与合并泛光都编译整份效果文件；`effects/lens/lens.glsl` 的镜头光斑读体积雾选项，
// `effects/color/bloom.glsl` 的合并泛光读雨、水雾与体积雾选项，`effects/color/color.glsl` 的曝光统计读洞穴模式选项，
// 所以这些程序都要先把选项归属文件按顺序引入，才不会在编译时看到未定义的宏。选项归属见 `docs/parity.md` 第九节。
#if defined OMNI_FRAGMENT && (defined OMNI_COMPOSITE6_PASS || defined OMNI_COMPOSITE8_PASS || defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS || defined OMNI_COMPOSITE14_PASS)

	// 后期共享声明，全项目只声明一次。
	#include "/effects/clarity/post_shared.glsl"
	// 材质编号（并提供视差与材质选项）。
	#include "/effects/ground/material.glsl"
	// 提供 `OMNI_TAA` 与时间抗锯齿选项，并带入坐标换算。
	#include "/effects/clarity/antialiasing.glsl"
	// 提供雨可见度等选项，泛光的合并读它。
	#include "/effects/weather/weather.glsl"
	// 提供水下雾开关与浓度选项，泛光的合并读它。
	#include "/effects/water/water.glsl"
	// 提供体积雾选项，并带入水面、阴影、天空、云与光照依赖。
	#include "/effects/fog/fog.glsl"
	// 坐标与深度换算。
	#include "/common/coordinates.glsl"
	// 时间噪声，景深与动态模糊的抖动读它。
	#include "/common/noise.glsl"
	// 曝光统计、曝光值与强光压缩曲线。
	#include "/effects/color/color.glsl"
	// 景深、动态模糊、暗角与镜头光斑。
	#include "/effects/lens/lens.glsl"
	// 泛光降采样、轴向模糊与合并泛光。
	#include "/effects/color/bloom.glsl"

	// --- 合成六号：景深 ---
	#if defined OMNI_COMPOSITE6_PASS
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 compositeOutput1; // 一号景深后的场景颜色。
		void main(){
			#ifdef OMNI_DOF // 只有开启景深才写一号画面。
				compositeOutput1 = DepthOfField(); // 按弥散半径散焦合成。
			#endif
		}

	// --- 合成八号：运动模糊、标题标志与顶行统计像素 ---
	#elif defined OMNI_COMPOSITE8_PASS
		/* DRAWBUFFERS:12 */
		layout(location = 0) out vec4 compositeOutput1; // 一号模糊后的场景颜色。
		layout(location = 1) out vec4 compositeOutput2; // 二号顶行统计像素与保留内容。
		// 动态模糊与镜头光斑叠加的算法体。
		#include "/effects/lens/post_motionblur.glsl"
		// 标题标志叠加与标题计数累加。
		#include "/effects/lens/title.glsl"
		// 顶行统计像素的算法体。
		#include "/effects/color/post_stats.glsl"
		void main(){
			vec3 color = MotionBlurSceneColor(); // 模糊后的线性场景颜色。
			float bloomGuide = 0.0; // 泛光引导，默认零。
			#ifdef OMNI_TITLE // 开着标题标志时叠加图标，并取它的不透明度当引导。
				bloomGuide = TitleLogo(color); // 图标叠回线性场景颜色并返回不透明度。
			#endif
			compositeOutput1 = vec4(LinearToCurve(color), bloomGuide); // 写一号画面，透明度是泛光引导。
			vec4 data2 = UpdateStatPixels(texelFetch(colortex2, texelCoord, 0)); // 逐像素改写二号顶行统计像素。
			#ifdef OMNI_TITLE // 开着标题标志时同时累加标题计数像素。
				data2 = UpdateTitleCounter(data2); // 累加顶行横坐标二十那个像素。
			#endif
			compositeOutput2 = data2; // 写二号画面。
		}

	// --- 合成九号到十三号：泛光降采样与升采样链 ---
	#elif defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS
		/* DRAWBUFFERS:5 */
		layout(location = 0) out vec4 compositeOutput5; // 五号泛光链。
		// 泛光五级链的算法体。
		#include "/effects/color/post_bloom.glsl"

		#if defined OMNI_COMPOSITE9_PASS // 第一级：从一号画面降采样。
			void main(){ BloomDownSampleScene(); } // 半分辨率降采样并写五号。
		#elif defined OMNI_COMPOSITE10_PASS // 第二级：从五号画面继续降采样。
			void main(){ BloomDownSampleChain(); } // 继续降采样并写五号。
		#elif defined OMNI_COMPOSITE11_PASS // 第三级：横向轴向高斯，链上各级排成一行。
			void main(){ BloomBlurHorizontal(); } // 横向模糊并写五号。
		#elif defined OMNI_COMPOSITE12_PASS // 第四级：纵向轴向高斯，坐标回拧。
			void main(){ BloomBlurVertical(); } // 纵向模糊并写五号。
		#elif defined OMNI_COMPOSITE13_PASS // 第五级：把各级三次模糊后叠成一张光晕。
			void main(){ BloomCombine(); } // 叠加各级并写五号。
		#endif

	// --- 合成十四号：合并泛光、暗角、曝光、色调映射与高级调色 ---
	#elif defined OMNI_COMPOSITE14_PASS
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 compositeOutput1; // 一号色调映射后的场景颜色。
		// 合并泛光、曝光与调色的算法体。
		#include "/effects/color/post_tonemap.glsl"
		// 胶片颗粒算法体；默认关闭时调用原样返回，画面不变。
		#include "/effects/clarity/grain.glsl"
		// 色调映射之后的色彩分级与亮度曲线，两个开关默认关闭时不改画面。
		#include "/effects/color/colorgrade.glsl"
		void main(){
			TonemapColor(); // 合并泛光、曝光与调色并写回一号。
			compositeOutput1 = vec4(OmniColorGrade(compositeOutput1.rgb), compositeOutput1.a); // 在色调映射后的显示域颜色上做色彩分级，透明度沿用原值。
			compositeOutput1.rgb = OmniFilmGrain(compositeOutput1.rgb, texCoord); // 在显示空间叠加胶片颗粒；默认关闭时原样返回。
		} // 合成十四号结束。
	#endif

#endif // 合成六号、八号、九号到十四号结束。

// --- 合成十五号：`CAS` 锐化 ---
// 只引入锐化与时间抗锯齿（`CAS` 的开启条件是同时开着时间抗锯齿）；材质文件提供被抗锯齿引用的材质编号。
#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE15_PASS

	// 后期共享声明，全项目只声明一次。
	#include "/effects/clarity/post_shared.glsl"
	// 提供材质编号，被抗锯齿文件引用。
	#include "/effects/ground/material.glsl"
	// 提供 `OMNI_TAA`，锐化的开启条件读它。
	#include "/effects/clarity/antialiasing.glsl"
	// 对比度自适应锐化与放大。
	#include "/effects/clarity/upscale.glsl"

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

	// 后期共享声明，全量声明一次；本程序只用 `screenSize` 与共用数学。
	#include "/effects/clarity/post_shared.glsl"
	// 边缘方向重采样放大。
	#include "/effects/clarity/upscale.glsl"

	/* DRAWBUFFERS:8 */
	layout(location = 0) out vec4 compositeOutput8; // 八号放大输出。

	void main(){
		compositeOutput8 = vec4(FsrEasu(gl_FragCoord.xy, screenSize, ceil(screenSize / MC_RENDER_QUALITY)), 0.0); // 输入是一号画面，输出尺寸是放大后的目标尺寸。
	}

#endif // 合成十六号结束。

#endif // 文件守卫结束。
