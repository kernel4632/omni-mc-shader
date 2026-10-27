/*
效果文件 `effects/color/bloom.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/color/bloom.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_COLOR_BLOOM_INCLUDED
#define OMNI_EFFECT_COLOR_BLOOM_INCLUDED
// @effect {"label":{"zh_cn":"泛光","en_us":"Bloom"}}
// @option {"label":{"zh_cn":"开关","en_us":"Bloom"},"description":{"zh_cn":"让亮部产生柔和光晕。","en_us":"Adds a soft glow around bright areas."}}
#define OMNI_BLOOM 1 // [0 1]
// @option {"label":{"zh_cn":"强度","en_us":"Bloom Amount"},"slider":true,"description":{"zh_cn":"光晕混入场景的强度，越大越亮。","en_us":"How strongly the glow is mixed into the scene."}}
#define OMNI_BLOOM_AMOUNT 0.13 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label": {"zh_cn": "下界末地泛光增强", "en_us": "Nether End Bloom Boost"}, "slider": true, "description": {"zh_cn": "下界与末地雾中的泛光额外增强量。", "en_us": "Extra bloom boost through Nether and End fog."}}
#define OMNI_NETHER_END_BLOOM_BOOST 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"空气雾散射泛光","en_us":"Volumetric Fog Scattering Bloom"},"description":{"zh_cn":"用体积雾的散射引导泛光，让光柱周围一起发亮。","en_us":"Uses volumetric fog scattering to guide the glow around light shafts."}}
#define OMNI_VFOG_BLOOM 1 // [0 1]
// @option {"label": {"zh_cn": "雾内泛光", "en_us": "Bloomy Fog"}, "slider": true, "description": {"zh_cn": "把光晕往体积雾里按雾的浓淡混进去，让雾看起来柔和、顺带盖住一点噪点；零为关闭、画面不变。来源 Eclipse `lib/settings.glsl:215` 的 `BLOOMY_FOG`（原程序默认零点五）。", "en_us": "Blends the glow into volumetric fog by how thick the fog is, making it look soft and hiding a little noise; zero is off and changes nothing. From Eclipse `BLOOMY_FOG` (upstream default 0.5)."}}
#define OMNI_FOG_BLOOM 0.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 6.0 10.0 15.0 20.0]
// @option {"label": {"zh_cn": "水下雾内泛光", "en_us": "Underwater Bloomy Fog"}, "slider": true, "description": {"zh_cn": "在水下把光晕按水的浓淡混进去，让浑水里也有柔光；零为关闭、画面不变。来源 Eclipse `lib/settings.glsl:216` 的 `UNDERWATER_BLOOMY_FOG`（原程序默认一）。", "en_us": "Underwater, blends the glow by how murky the water is; zero is off and changes nothing. From Eclipse `UNDERWATER_BLOOMY_FOG` (upstream default 1.0)."}}
#define OMNI_UNDERWATER_FOG_BLOOM 0.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 6.0 10.0 15.0 20.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
泛光：把画面里亮过白色阈值的强光抽出来，逐级降采样再升采样成一张柔和光晕，最后与场景颜色合并。
来源：五个泛光程序段与各段的降采样、轴向高斯模糊、三次模糊照 iterationT `Lib/IndividualFounctions/Bloom.glsl` 一比一移植；
  合并泛光照 iterationT `Lib/Programs/Final.glsl` 的 `MergeBloom` 一比一移植。
调用位置：
  合成九号到十三号片元各自的 `main()` 调用本文件的五级链 `BloomDownSampleScene`、`BloomDownSampleChain`、
  `BloomBlurHorizontal`、`BloomBlurVertical`、`BloomCombine` 生成各级光晕，并把返回值写进五号画面；
  合成十四号片元调用 `MergeBloom`，把光晕按物体与雾的透明度混进场景颜色。
可复制示例：
  `vec3 glow = BloomDownSample(colortex1, texCoord * 2.0);`
  `vec3 blur = AxialGaussianBlur(colortex5, coord, vec2(2.0, 1.0), 0.0, originSize, vec2(1.0, 0.0), BLOOM_SIZE_LOD3, BLOOM_STEP_LOD3);`
  `color = MergeBloom(color, 1.0 - data1.a);`
  `compositeOutput5 = BloomDownSampleScene();`  合成九号把五级链的返回值写进五号画面。
调用前提（iterationT 原样保留）：各级函数按加载器给的 `texCoord`、`pixelSize`、`screenSize` 工作；
  `MergeBloom` 还要用到 `colortex0` 的雨遮罩、`colortex3` 的体积雾吸收（泛光引导）与雨、雾、天气等选项，
  这些选项由各自的归属效果文件定义，绘制主体负责按顺序引入。
设计原因与取舍：
  泛光不逐像素判断阈值，而是靠一条固定的降采样升采样链把亮部扩散开，链的半径与步长全是内部常数；
  光晕按物体透明度与雾的浓淡增强，让暴雨、水下和下界雾里的亮部更明显，这是原程序的表现手法。
  五级链的程序体与底层函数合在本文件：五级链只排布并调用下面三个底层函数，拆成另一个文件没有额外好处；
  但仍然按 `OMNI_COMPOSITE9_PASS` 到 `OMNI_COMPOSITE13_PASS` 隔开，因为它们只在合成九号到十三号编译。
  `OMNI_FOG_BLOOM` 按 Eclipse `dimensions/composite11.fsh:290-315` 的做法，用体积雾吸收作引导把光晕往雾里混，
  让雾变柔；Eclipse 另算一条平均光晕，这里复用同一条，属近似，默认零、画面不变。
  `OMNI_UNDERWATER_FOG_BLOOM` 对应同一处的水下分支（Eclipse `UNDERWATER_BLOOMY_FOG`）：Omni 水下不跑体积雾，
  改用水体的距离吸收当引导，倍率单独可调，默认零、画面不变。
*/
#include "/gfx/post.glsl"
// 颜色曲线、亮度与共享数学，以及做深度换算的坐标函数都要先引入。
#include "/common/uniforms.glsl"
// 降雨强度由绑定层提供，泛光强度按雨势提升。
#include "/bind/weather.glsl"
#include "/common/math.glsl"
#include "/effects/clarity/antialiasing.glsl"
#include "/common/coordinates.glsl"
// 合并泛光要读水雾密度 `OMNI_WATER_FOG_DENSITY`（定义在 `effects/water/water.glsl`），这里引入它的归属文件。
#include "/effects/water/water.glsl"
// 合并泛光用失明与黑暗的调试开关 `OMNI_DISABLE_BLINDNESS_DARKNESS`，它的归属文件是颜色效果，这里引入才拿到定义。
#include "/effects/color/color.glsl"

// 降采样、轴向高斯与三次升采样的公式和内部常数全部在 `gfx/post.glsl`；本文件只保留选项与合并逻辑。

// --- 合并泛光：把光晕按物体与雾的透明度混进场景颜色 ---
// `bloomGuide` 是引导强度，通常取一号画面的透明度，用来判断该处亮部有多亮。
// 为什么要看雾和雨：雾和雨会把光晕拉长变浓，原程序据此增强泛光，让天气与水下更有氛围。
vec3 MergeBloom(vec3 color, float bloomGuide){
#if defined OMNI_NETHER // 下界从打包的七号画面里拿线性深度。
	float linearDepth = LinearDepth_From_ScreenDepth(Unpack2x16(texelFetch(colortex7, texelCoord, 0).a).x); // 拆出并换算深度。
	#ifndef DISTANT_HORIZONS // 没有远景模组时限制在远裁剪面内。
		linearDepth = min(linearDepth, far); // 夹到远裁剪面。
	#endif
#else // 主世界与末地直接用近景深度。
	float depth = texelFetch(depthtex0, texelCoord, 0).x; // 读当前像素深度。
	float linearDepth = LinearDepth_From_ScreenDepth(depth); // 换成米制距离。
	#ifdef DISTANT_HORIZONS // 有远景模组时远景像素改用远景深度。
		if (depth == 1.0) linearDepth = LinearDepth_From_ScreenDepth_DH(texelFetch(dhDepthTex0, texelCoord, 0).x); // 远景深度换到同一尺度。
	#endif
#endif
	vec3 bloom = CurveToLinear(textureLod(colortex5, texCoord * 0.5, 0.0).rgb); // 读入降采样链合成的光晕。
	float bloomAmount = OMNI_BLOOM_AMOUNT; // 从强度选项起步。
#ifdef OMNI_END // 末地整体增强光晕。
	bloomAmount *= 0.5 * OMNI_NETHER_END_BLOOM_BOOST + 1.0; // 按增强选项放大。
#endif
#ifdef OMNI_NETHER // 下界按群系和雾浓淡调整。
	float biomeOffset =	 BiomeNetherWastesSmooth * 1.0; // 荒地群系系数。
	biomeOffset +=		 BiomeCrimsonForestSmooth * 0.75; // 绯红森林群系系数。
	biomeOffset +=		 BiomeWarpedForestSmooth * 0.25; // 诡异森林群系系数。
	biomeOffset +=		 BiomeBasaltDeltasSmooth * 0.5; // 玄武岩三角洲群系系数。
	biomeOffset = biomeOffset * OMNI_NETHER_END_BLOOM_BOOST + 1.0; // 乘增强选项。
	float fogDensity = 0.008 * biomeOffset * OMNI_NETHER_END_BLOOM_BOOST * OMNI_NETHER_FOG_DENSITY; // 雾越浓光晕越强。
	if (isEyeInWater > 1) fogDensity = 0.7; // 在岩浆或细雪里雾最浓。
	float visibility = 1.0 / exp2(linearDepth * fogDensity); // 距离越远可见度越低。
	float fogFactor = 1.1 - visibility; // 把可见度翻成雾的占比。
	fogFactor *= bloomGuide; // 只在亮的地方随雾增强。
	bloomAmount = max(bloomAmount * biomeOffset, min(fogFactor, 0.92)); // 取两者较大值，并留一点上限。
#else // 主世界与末地按水和雨的雾调整。
	float fogDensity = float(isEyeInWater > 1) * 0.7; // 岩浆或细雪里雾浓。
	#ifdef OMNI_UNDERWATER_FOG // 开水下雾时水里也加光晕。
		fogDensity = float(isEyeInWater == 1) * 0.07 * OMNI_WATER_FOG_DENSITY; // 水下雾的浓度由选项控制。
	#endif
	float visibility = 1.0 / exp2(linearDepth * fogDensity); // 距离越远可见度越低。
	float fogFactor = 1.1 - visibility; // 把可见度翻成雾的占比。
	fogFactor *= bloomGuide; // 只在亮的地方随雾增强。
	bloomAmount = max(bloomAmount, fogFactor); // 取两者较大值。
#endif
#ifdef OMNI_OVERWORLD // 屏幕边缘淡出掩码，水下雾内泛光使用。
	float fogBloomEdge = clamp(1.0 - pow(max(abs(texCoord.x - 0.5), abs(texCoord.y - 0.5)) * 2.0, 15.0), 0.0, 1.0); // 越靠近屏幕边缘越淡。
	// 只有明确开启雾内泛光时才读体积雾引导；默认关闭，参考签名不需要这次采样。
	// 雾内泛光默认关闭；开启时用泛光引导近似雾的浓淡，不再额外读体积雾缓冲。
	if (OMNI_FOG_BLOOM > 0.0 && OMNI_VFOG_BLOOM > 0) {
		float fogBloomAmount = saturate(bloomGuide * OMNI_FOG_BLOOM * 0.75) * fogBloomEdge; // 雾内泛光。
		bloomAmount = max(bloomAmount, fogBloomAmount); // 并入光晕混入占比。
	}
	// 水下雾内泛光：Omni 水下不跑体积雾，改用水体的距离吸收当引导。
	#ifdef OMNI_UNDERWATER_FOG
		if (isEyeInWater == 1){ // 眼睛在水里时才处理。
			float waterFogGuide = 1.0 - exp2(-linearDepth * 0.06 * OMNI_WATER_FOG_DENSITY); // 与合成五号的水体吸收同一式子，水越远越浑、引导越大。
			float waterFogBloom = saturate(waterFogGuide * OMNI_UNDERWATER_FOG_BLOOM * 0.75 * (1.0 + bind_weather().rain)) * fogBloomEdge; // 同一套公式，倍率换成水下专用的 Eclipse `UNDERWATER_BLOOMY_FOG`。
			bloomAmount = max(bloomAmount, waterFogBloom); // 并入光晕混入占比。
		}
	#endif
#endif
	#if !OMNI_DISABLE_BLINDNESS_DARKNESS // 失明或黑暗效果时不加光晕。
		bloomAmount *= 1.0 - blindness - darknessFactor; // 按遮挡强度压低。
	#endif
	return mix(color, bloom, saturate(bloomAmount)); // 按占比把光晕混进场景。
}

// --- 五级泛光链：合成九号到十三号各调用一个通用库函数，这里只选纹理与雨遮罩 ---
// 为什么按程序宏隔开：这五级只在合成九号到十三号生成，合并泛光（合成十四号）也引入本文件，但不需要它们。
// 为什么返回颜色而不是直接写 `compositeOutput5`：本文件在程序声明输出之前就被引入，写输出会要求声明顺序颠倒；
// 改成把结果交回调用方，程序自己 `compositeOutput5 = ...;`，任何程序都能安全引入这份效果文件。
#if defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS

// 泛光第一级：把一号画面降采样到半分辨率。
vec4 BloomDownSampleScene(){
	return gfx_bloom_downsample_scene(colortex1, texCoord, pixelSize); // 一次调用完成整级。
}

// 泛光第二级：从五号画面继续降采样。
vec4 BloomDownSampleChain(){
	return gfx_bloom_downsample_chain(colortex5, texCoord, pixelSize); // 一次调用完成整级。
}

// 泛光第三级：横向轴向高斯，链上各级排成一行。
vec4 BloomBlurHorizontal(){
	return gfx_bloom_blur_horizontal(colortex5, texCoord, pixelSize); // 一次调用完成整级。
}

// 泛光第四级：纵向轴向高斯，采样坐标回拧到各级自己的起点。
vec4 BloomBlurVertical(){
	return gfx_bloom_blur_vertical(colortex5, texCoord, pixelSize); // 一次调用完成整级。
}

// 泛光第五级：把各级三次模糊后的结果按权重叠成一张光晕，雨里权重更高。
vec4 BloomCombine(){
	float rainAlpha = 0.0; // 雨遮罩；主世界才有。
	#ifdef OMNI_OVERWORLD // 主世界从零号画面读雨量。
		rainAlpha = 1.0 - textureLod(colortex0, texCoord * 2.0, 0.0).a; // 零号透明度越低说明雨越密。
		rainAlpha = saturate(rainAlpha * OMNI_RAIN_VISIBILITY); // 乘雨可见度选项。
	#endif
	return gfx_bloom_combine(colortex5, texCoord, pixelSize, screenSize, rainAlpha); // 一次调用完成整级。
}
#endif // 五级泛光链结束。
#endif // OMNI_EFFECT_COLOR_BLOOM_INCLUDED
