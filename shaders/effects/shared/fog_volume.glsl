/*
效果文件 `effects/shared/fog_volume.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/fog.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_FOG_FOG_INCLUDED
#define OMNI_EFFECT_FOG_FOG_INCLUDED
// @effect {"label":{"zh_cn":"雾与空气","en_us":"Fog & air"}}
// @option {"label":{"zh_cn":"空气雾","en_us":"Volumetric fog"},"description":{"zh_cn":"沿视线在空气里步进得到的体积雾与光柱。","en_us":"Volumetric fog and light shafts marched along the view."}}
#define OMNI_VFOG
// @option {"label":{"zh_cn":"空气雾噪声类型","en_us":"Volumetric fog noise"},"description":{"zh_cn":"仅高度衰减只有一层随高度变浓的雾，团雾用三维噪声造出雾团。","en_us":"Height-only gives one layer that thickens with altitude; Wispy uses 3D noise for fog banks."},"values":{"0":{"zh_cn":"仅高度衰减","en_us":"Height only"},"1":{"zh_cn":"团雾","en_us":"Wispy"}}}
#define OMNI_VFOG_NOISE_TYPE 0 // [0 1]
// @option {"label":{"zh_cn":"空气雾采样质量","en_us":"Volumetric fog quality"},"description":{"zh_cn":"体积雾与水下体积雾沿视线的采样次数，越高越干净也越慢。","en_us":"View samples for volumetric fog and underwater fog; higher is cleaner and slower."},"slider":true}
#define OMNI_VFOG_QUALITY 6 // [4 6 8 10 12 14 16 18 20 22 24 28 32 48 64 128]
// @option {"label":{"zh_cn":"空气雾密度","en_us":"Volumetric fog density"},"description":{"zh_cn":"噪声控制的雾团密度，越大雾越浓。","en_us":"Density of the noise-driven fog; larger is thicker."},"slider":true}
#define OMNI_VFOG_DENSITY 0.01 // [0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"空气雾基础密度","en_us":"Volumetric fog base density"},"description":{"zh_cn":"不靠噪声的一张基础雾层密度，取零时只有噪声雾。","en_us":"Flat fog layer density independent of noise; zero leaves only the noise fog."},"slider":true}
#define OMNI_VFOG_DENSITY_BASE 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"空气雾衰减高度","en_us":"Volumetric fog height"},"description":{"zh_cn":"仅高度衰减模式下两档高度之间最浓，超出后衰减；团雾模式下最高点落在较高的这一档。","en_us":"Height-only keeps peak density between the two heights; Wispy puts the peak at the higher one."},"slider":true}
#define OMNI_VFOG_HEIGHT 65.0 // [-100.0 -90.0 -80.0 -70.0 -60.0 -50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0 210.0 220.0 230.0 240.0 250.0 260.0 270.0 280.0 290.0 300.0 310.0 320.0 350.0 400.0 450.0 500.0 600.0 700.0 800.0 900.0 1000.0]
// @option {"label":{"zh_cn":"空气雾衰减高度二","en_us":"Volumetric fog height 2"},"description":{"zh_cn":"与上一档一起决定体积雾最浓的高度区间。","en_us":"With the other height, sets the band where volumetric fog is densest."},"slider":true}
#define OMNI_VFOG_HEIGHT_2 50.0 // [-100.0 -90.0 -80.0 -70.0 -60.0 -50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 45.0 50.0 55.0 60.0 65.0 70.0 75.0 80.0 85.0 90.0 95.0 100.0 105.0 110.0 115.0 120.0 125.0 130.0 135.0 140.0 145.0 150.0 155.0 160.0 165.0 170.0 175.0 180.0 185.0 190.0 195.0 200.0 210.0 220.0 230.0 240.0 250.0 260.0 270.0 280.0 290.0 300.0 310.0 320.0 350.0 400.0 450.0 500.0 600.0 700.0 800.0 900.0 1000.0]
// @option {"label":{"zh_cn":"空气雾衰减距离","en_us":"Volumetric fog falloff"},"description":{"zh_cn":"体积雾离开最浓高度后衰减的快慢，越大衰减越慢。","en_us":"How fast fog fades away from its densest height; larger fades slower."},"slider":true}
#define OMNI_VFOG_FALLOFF 40.0 // [1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0]
// @option {"label":{"zh_cn":"空气雾全时段启用","en_us":"Volumetric fog all day"},"description":{"zh_cn":"关闭时白天降低体积雾密度，打开后全天保持。","en_us":"Off thins the fog during the day; on keeps it constant around the clock."}}
//#define OMNI_VFOG_IGNORE_WORLDTIME
// @option {"label":{"zh_cn":"空气雾半透明染色","en_us":"Volumetric fog stained light"},"description":{"zh_cn":"透过彩色玻璃的阳光会被染色；仅支持部分显卡，可能出现额外开销。","en_us":"Tints sunlight passing through stained glass; supported on some GPUs only."}}
//#define OMNI_VFOG_STAINED
// @option {"label":{"zh_cn":"空气雾云影暗部","en_us":"Volumetric fog cloud shadow"},"description":{"zh_cn":"云影也压暗体积雾的受光，让光柱与云影一致。","en_us":"Cloud shadows also darken the lit fog so shafts match the cloud shadow."}}
//#define OMNI_VFOG_CLOUD_SHADOW
// @option {"label":{"zh_cn":"空气雾阳光强度","en_us":"Volumetric fog sunlight"},"description":{"zh_cn":"体积雾里阳光散射的强度，决定光柱多亮。","en_us":"Strength of sun scattering in the fog; how bright the shafts are."},"slider":true}
#define OMNI_VFOG_SUNLIGHT_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"空气雾环境光强度","en_us":"Volumetric fog ambient"},"description":{"zh_cn":"体积雾整体环境色的强度，决定雾本身多亮。","en_us":"Strength of the fog's ambient colour; how bright the fog itself is."},"slider":true}
#define OMNI_VFOG_FOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"体积光照","en_us":"Volumetric lighting"},"description":{"zh_cn":"体积雾自身对光照的吸收，光柱内部更暗、边缘更亮。","en_us":"Self-absorption of light inside the fog; darkens shaft interiors."}}
#define OMNI_VFOG_VOLUMETRIC_LIGHTING
// @option {"label":{"zh_cn":"体积光照吸收率","en_us":"Volumetric absorption"},"description":{"zh_cn":"体积光照的吸光强度，越大吸收越明显。","en_us":"Absorption strength of volumetric lighting; larger is darker."},"slider":true}
#define OMNI_VFOG_SUNLIGHT_ABSORPTION 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"水下空气雾","en_us":"Underwater fog"},"description":{"zh_cn":"水下的蓝色光柱，由阳光穿过水面缝隙汇聚而成。","en_us":"Blue light shafts underwater, focused through gaps in the water surface."}}
#define OMNI_UNDERWATER_VFOG
// @option {"label":{"zh_cn":"水下空气雾密度","en_us":"Underwater fog density"},"description":{"zh_cn":"水下光柱的强度。","en_us":"Strength of the underwater light shafts."},"slider":true}
#define OMNI_UNDERWATER_VFOG_DENSITY 1.0 // [0.1 0.15 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.4 1.6 1.8 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"地面大气散射","en_us":"Land atmospheric scattering"},"description":{"zh_cn":"地表方向空气对阳光的散射，给远处地形加一层空气感。","en_us":"Scattering of sunlight by the air toward the surface, adding aerial haze to distant land."}}
#define OMNI_LANDSCATTERING
// @option {"label":{"zh_cn":"地面大气散射强度","en_us":"Land scattering strength"},"description":{"zh_cn":"地面大气散射的整体强度。","en_us":"Overall strength of land atmospheric scattering."},"slider":true}
#define OMNI_LANDSCATTERING_STRENGTH 2.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.5 1.7 2.0 2.5 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 100.0]
// @option {"label":{"zh_cn":"地面大气散射距离","en_us":"Land scattering distance"},"description":{"zh_cn":"地面大气散射沿视线的累积倍率，越大越浓。","en_us":"Multiplier on the optical length for land scattering; larger is hazier."},"slider":true}
#define OMNI_LANDSCATTERING_DISTANCE 0.003 // [0.001 0.002 0.003 0.005 0.007 0.01 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"地面大气散射阴影暗部","en_us":"Land scattering shadow"},"description":{"zh_cn":"在阴影区降低地面大气散射，避免阴影里也泛白。","en_us":"Reduces land scattering in shadowed areas so they do not wash out."}}
#define OMNI_LANDSCATTERING_SHADOW 0 // [0 1]
// @option {"label":{"zh_cn":"阴影暗部采样质量","en_us":"Land scattering shadow quality"},"description":{"zh_cn":"地面大气散射阴影的采样次数，越高噪点越少也越慢。","en_us":"Samples for the land scattering shadow; higher is cleaner and slower."},"slider":true}
#define OMNI_LANDSCATTERING_SHADOW_QUALITY 6 // [4 6 8 10 12 14 16 18 20 22 24 28 32 48 64 128]
// @option {"label":{"zh_cn":"禁用光照衰减","en_us":"Disable fog falloff"},"description":{"zh_cn":"关闭体积雾与地表散射随天空光等级的衰减；关掉后暗处雾气可能过强。","en_us":"Disables the skylight falloff of fog and land scattering; off may be too foggy in the dark."}}
#define OMNI_INDOOR_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"反射中渲染空气雾","en_us":"Volumetric fog in reflections"},"description":{"zh_cn":"在屏幕反射里也补体积雾，反射不再是干净的镜面。","en_us":"Adds volumetric fog inside reflections so they are not mirror-clean."}}
#define OMNI_VFOG_REFLECTION
// @option {"label":{"zh_cn":"折射后渲染空气雾","en_us":"Volumetric fog after refraction"},"description":{"zh_cn":"在彩色玻璃后方的折射画面里补体积雾。","en_us":"Adds volumetric fog to the refracted image behind stained glass."}}
//#define OMNI_VFOG_REFRACTION
// @option {"label":{"zh_cn":"反射中渲染地表散射","en_us":"Land scattering in reflections"},"description":{"zh_cn":"在屏幕反射里也补地表大气散射。","en_us":"Adds land atmospheric scattering inside reflections."}}
//#define OMNI_LANDSCATTERING_REFLECTION
// @option {"label":{"zh_cn":"折射后渲染地表散射","en_us":"Land scattering after refraction"},"description":{"zh_cn":"在彩色玻璃后方的折射画面里补地表大气散射。","en_us":"Adds land scattering to the refracted image behind stained glass."}}
//#define OMNI_LANDSCATTERING_REFRACTION
// @option {"label":{"zh_cn":"下界雾强度","en_us":"Nether fog density"},"description":{"zh_cn":"下界与末地空气的浑浊程度。","en_us":"How murky the Nether and End air is."},"slider":true}
#define OMNI_NETHER_FOG_DENSITY 1.0 // [0.0 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"限制空气雾渲染距离","en_us":"Limit volumetric fog distance"},"description":{"zh_cn":"把体积雾渲染范围限制在一百区块以内，防止远处质量严重下降；可能导致远处体积雾缺失。","en_us":"Limits fog rendering to about 100 chunks to avoid quality collapse; may cut fog in the far distance."}}
#define OMNI_DH_LIMIT_VFOG_DIST

// --- 洞穴雾与边界雾：来源 Eclipse `lib/settings.glsl:219-233` 与 `dimensions/composite4.fsh:449-533` ---
// 两项在原程序里都默认开启且会改变画面，本项目按“默认中性”约定默认关闭，开启后才生效。
// @option {"label":{"zh_cn":"洞穴雾","en_us":"Cave fog"},"description":{"zh_cn":"洞穴深处单独的一层雾，用可调颜色与衰减把黑暗空间填出空气感；默认关闭，开启后洞穴内画面会变化。","en_us":"A separate fog layer deep in caves with adjustable colour and falloff; off by default, turning it on changes the look inside caves."}}
#define OMNI_CAVE_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"洞穴雾衰减","en_us":"Cave fog falloff"},"description":{"zh_cn":"洞穴雾由近向远变浓的快慢，越大越早变浓；只在洞穴雾开启时生效。","en_us":"How quickly cave fog thickens from near to far; larger thickens sooner; only used when Cave fog is on."},"slider":true}
#define OMNI_CAVE_FOG_FALLOFF 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"洞穴雾红","en_us":"Cave fog red"},"description":{"zh_cn":"洞穴雾的红色分量，三个颜色分量一起决定雾色；只在洞穴雾开启时生效。","en_us":"Red component of the cave fog colour; only used when Cave fog is on."},"slider":true}
#define OMNI_CAVE_FOG_COLOR_R 0.1 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"洞穴雾绿","en_us":"Cave fog green"},"description":{"zh_cn":"洞穴雾的绿色分量，三个颜色分量一起决定雾色；只在洞穴雾开启时生效。","en_us":"Green component of the cave fog colour; only used when Cave fog is on."},"slider":true}
#define OMNI_CAVE_FOG_COLOR_G 0.2 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"洞穴雾蓝","en_us":"Cave fog blue"},"description":{"zh_cn":"洞穴雾的蓝色分量，三个颜色分量一起决定雾色；只在洞穴雾开启时生效。","en_us":"Blue component of the cave fog colour; only used when Cave fog is on."},"slider":true}
#define OMNI_CAVE_FOG_COLOR_B 0.5 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"区块边界雾","en_us":"Chunk border fog"},"description":{"zh_cn":"在渲染距离附近拉起一层天空色的雾墙，遮住区块加载；默认关闭，开启后远处会出现雾墙。","en_us":"Fades distant terrain into a sky-coloured fog wall near the render distance to hide chunk loading; off by default."}}
#define OMNI_BORDER_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"边界雾浓度","en_us":"Border fog intensity"},"description":{"zh_cn":"边界雾雾墙出现的位置，数值越大雾墙离得越近、越明显；只在区块边界雾开启时生效。","en_us":"Where the fog wall appears; larger brings it closer and thicker; only used when Chunk border fog is on."},"slider":true}
#define OMNI_BORDER_FOG_INTENSITY 0.6 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// --- 时段雾：来源 Eclipse `lib/settings.glsl:191-203` 与 `lib/climate_settings.glsl:172-201` 的 `FogDensities` ---
// 把一天按 `worldTime` 切成晨、午、晚、夜四段，每段给一段权重；密度系数分成“均匀雾”与“多云雾”两套，
// 分别对应“仅高度衰减”雾与“团雾”，与 Eclipse 的均匀、多云两个分量一致。
// Eclipse 默认开启且会改变画面，本项目按“默认中性”约定把总开关默认关闭；下面的系数与总倍率虽然
// 默认启用，但只在总开关打开后才参与计算，所以默认画面与原来一致。
// @option {"label":{"zh_cn":"时段雾","en_us":"Time-of-day fog"},"description":{"zh_cn":"让体积雾密度随主世界一天时间与雾类型变化，来自 Eclipse；默认关闭，打开后夜间更浓、清晨与傍晚居中。","en_us":"Varies volumetric fog density by time of day and fog type, from Eclipse; off by default."}}
#define OMNI_TOD_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"时段雾总倍率","en_us":"Time-of-day fog multiplier"},"description":{"zh_cn":"统一放大或缩小四段时段密度，对应 Eclipse 的总倍率。","en_us":"Overall multiplier on the four time-of-day densities; matches Eclipse."},"slider":true}
#define OMNI_TOD_FOG_MULT 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"清晨均匀雾密度","en_us":"Morning uniform fog density"},"description":{"zh_cn":"清晨“均匀雾”（仅高度衰减的雾）的密度；只在时段雾开启且体积雾噪声类型为仅高度衰减时生效。","en_us":"Morning density of the uniform (height-only) fog; used only when Time-of-day fog is on and the fog noise type is height only."},"slider":true}
#define OMNI_TOD_FOG_MORNING_UNIFORM 0.01 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"正午均匀雾密度","en_us":"Noon uniform fog density"},"description":{"zh_cn":"正午“均匀雾”（仅高度衰减的雾）的密度；只在时段雾开启且体积雾噪声类型为仅高度衰减时生效。","en_us":"Noon density of the uniform (height-only) fog; used only when Time-of-day fog is on and the fog noise type is height only."},"slider":true}
#define OMNI_TOD_FOG_NOON_UNIFORM 0.01 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"傍晚均匀雾密度","en_us":"Evening uniform fog density"},"description":{"zh_cn":"傍晚“均匀雾”（仅高度衰减的雾）的密度；只在时段雾开启且体积雾噪声类型为仅高度衰减时生效。","en_us":"Evening density of the uniform (height-only) fog; used only when Time-of-day fog is on and the fog noise type is height only."},"slider":true}
#define OMNI_TOD_FOG_EVENING_UNIFORM 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"夜间均匀雾密度","en_us":"Night uniform fog density"},"description":{"zh_cn":"夜间“均匀雾”（仅高度衰减的雾）的密度；只在时段雾开启且体积雾噪声类型为仅高度衰减时生效。","en_us":"Night density of the uniform (height-only) fog; used only when Time-of-day fog is on and the fog noise type is height only."},"slider":true}
#define OMNI_TOD_FOG_NIGHT_UNIFORM 0.2 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"清晨多云雾密度","en_us":"Morning cloudy fog density"},"description":{"zh_cn":"清晨“多云雾”（团雾）的密度；只在时段雾开启且体积雾噪声类型为团雾时生效。","en_us":"Morning density of the cloudy (wispy) fog; used only when Time-of-day fog is on and the fog noise type is wispy."},"slider":true}
#define OMNI_TOD_FOG_MORNING_CLOUDY 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"正午多云雾密度","en_us":"Noon cloudy fog density"},"description":{"zh_cn":"正午“多云雾”（团雾）的密度；只在时段雾开启且体积雾噪声类型为团雾时生效。","en_us":"Noon density of the cloudy (wispy) fog; used only when Time-of-day fog is on and the fog noise type is wispy."},"slider":true}
#define OMNI_TOD_FOG_NOON_CLOUDY 0.01 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"傍晚多云雾密度","en_us":"Evening cloudy fog density"},"description":{"zh_cn":"傍晚“多云雾”（团雾）的密度；只在时段雾开启且体积雾噪声类型为团雾时生效。","en_us":"Evening density of the cloudy (wispy) fog; used only when Time-of-day fog is on and the fog noise type is wispy."},"slider":true}
#define OMNI_TOD_FOG_EVENING_CLOUDY 0.01 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"夜间多云雾密度","en_us":"Night cloudy fog density"},"description":{"zh_cn":"夜间“多云雾”（团雾）的密度；只在时段雾开启且体积雾噪声类型为团雾时生效。","en_us":"Night density of the cloudy (wispy) fog; used only when Time-of-day fog is on and the fog noise type is wispy."},"slider":true}
#define OMNI_TOD_FOG_NIGHT_CLOUDY 0.05 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.15 0.2 0.25 0.3 0.4 0.5 0.7 1.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
雾与空气：照 iterationT `Lib/IndividualFounctions/VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`
与 `Lib/BasicFounctions/VanillaComposite.glsl` 的 `VanillaFog` 一比一移植。
职责：本文件是雾效果入口，集中定义全部雾相关选项与内部常数，并引入本效果依赖的共享文件；
  算法体按来源拆到同目录文件，`#include` 顺序与拆分前的原文件逐段一致：
  时段雾与每日天气雾 `effects/fog/tod_fog.glsl`；体积雾 `effects/fog/volumetric.glsl`；
  地面大气散射 `effects/fog/landscattering.glsl`；洞穴雾与边界雾 `effects/fog/cave_border_fog.glsl`；
  原版雾 `effects/fog/vanilla_fog.glsl`；水下体积雾 `effects/fog/underwater_fog.glsl`；
  雪暴与沙暴另见 `effects/weather/storm.glsl`。
调用位置：
  `rendering/composite.glsl` 的 `composite2` 程序在反射里补体积雾与地表散射；
  `rendering/composite.glsl` 的 `composite5` 程序对整幅画面补体积雾、水下体积雾、地表散射与原版雾。
可复制示例：
  `VolumetricFog(color, vec3(0.0), rayWorldPos, worldDir, globalCloudShadow, fogTimeFactor, fogTransmittance);`
  `LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5);`
  `VanillaFog(color, waterDist);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `worldShadowVector`、`worldSunVector`、`colorSkylight`、`colorShadowlight`、`cameraPosition`、
  `gbufferModelViewInverse`、`wetness`、`isEyeInWater`、`eyeBrightnessSmoothCurved`、`timeNoon`、`timeMidnight`、
  `screenSize`、`pixelSize`、`colortex7`、`shadowtex0`、`shadowtex1` 由合成主程序声明；
  `OMNI_SKYLIGHT_INTENSITY`、`OMNI_SUNLIGHT_INTENSITY`、`OMNI_CAVE_MODE` 由 `effects/lighting/sunlight.glsl` 提供，
  绘制主体需在本文件之前引入它；
  `OMNI_UNDERWATER_FOG`、`OMNI_WATER_FOG_DENSITY` 由 `effects/water/water.glsl` 提供，本文件在函数定义之后引入它。
关键设计原因与取舍：
  选项与内部常数只在这里定义一次，算法体按来源分文件，便于按效果查找与修改；
  各分文件由本文件按原程序顺序引入，`#include` 语义与拆分前逐段一致；
  `effects/water/water.glsl` 的折射会调用体积雾与地表散射，所以它必须排在那两个分文件之后；
  水下体积雾读水面选项，所以它排在 `water.glsl` 之后。
*/


// --- 内部常数：原 `Settings.glsl` 里不进菜单的取值，名字保持原名 ---
#define VFOG_SUNLIGHT_STEPS 4 // 体积光照沿阳光方向的步数。
#define VFOG_SUNLIGHT_STEPLENGTH 5.0 // 体积光照沿阳光方向的起始步长，单位米，每步放大一点五倍。

// 数学提供相位函数与曲线，蓝噪声提供步进抖动，阴影提供阴影图坐标、焦散与波法线，天空云提供大气数据与云影，光照提供强度选项。
// 光照强度属于共享选项，本效果按同一档位读取。
#include "/effects/shared/light.glsl"
#include "/common/math.glsl"
// 抖动开关与坐标换算同属时间抗锯齿输入，先引入共享选项再还原屏幕坐标。
#include "/effects/shared/antialias.glsl"
// 洞穴雾与边界雾要从像素坐标还原视线方向，用这里的 `ViewPos_From_ScreenPos_Raw`；文件自带守卫，重复引入无副作用。
#include "/common/coordinates.glsl"
#include "/common/noise.glsl"
// 群系特色环境：按玩家所在群系给体积雾换雾色与密度，由主助手在 `rendering/pipeline.properties` 登记群系权重；
// 总开关关闭时它不产生任何代码，默认画面与原来一致。
#include "/bind/world/biome.glsl"
#include "/effects/shared/shadow.glsl"
#include "/effects/shared/atmosphere.glsl"
#include "/effects/shared/cloud.glsl"
// 闪电照明与云、雾共用同一份事件输入，单独成共享文件。
#include "/effects/shared/lightning.glsl"
// 原版雾用失明与黑暗的调试开关，属于共享画面状态，直接引用开关定义。
#include "/effects/shared/screen.glsl"
// 雪暴与沙暴提供暴风强度、额外浓雾与雾色，供体积雾主体调用；默认关闭时整段不增加代码。
#include "/effects/shared/storm.glsl"

// 雾照明要用体积光的取样函数与选项；只在雾照明开启时引入，默认关闭时整段不出现，不影响原来引用。
#if OMNI_LPV_VL_FOG_ILLUMINATION
	#include "/effects/shared/lpv.glsl"
#endif

// 水下手持光钩子：体积雾通用库在包含前读取它，不定义时默认不加光。
#if defined OMNI_LPV_FOG_LIGHT && defined OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
	#define OGX_UNDERWATER_HAND_LIGHT(world_pos) (omniLpvHandLight(heldItemId, world_pos) + omniLpvHandLight(heldItemId2, world_pos)) // 两手光源的光色乘距离衰减。
#endif

// --- 参考签名兼容层：末地三维噪声与云 FBM 分形噪声，分辨率取参考的 64 ---
float Calculate3DNoise(vec3 position){ return ogxTexture3dNoise(position, noisetex, 64.0); }
float CalculateCloudFBM(vec3 position, vec3 shift){ return ogxCloudFbm(position, shift, noisetex, 64.0); }
float CalculateCloudFBM_LQ(vec3 position, vec3 shift){
	const int octaves = 3;
	const float octAlpha = 0.9;
	const float octScale = 2.0;
	const float octShift = (octAlpha / octScale) / float(octaves);
	float accum = 0.0;
	float alpha = 0.5;
	for (int i = 0; i < octaves; i++){
		accum += alpha * Calculate3DNoise(position);
		position = (position + shift) * octScale;
		alpha *= octAlpha;
	}
	return accum + octShift;
}

// 雾的几个算法体按来源拆到同目录文件，这里按原程序的引用顺序引入。
#include "/effects/shared/fog/tod_fog.glsl"
#include "/effects/shared/fog/volumetric.glsl"
#include "/effects/shared/fog/landscattering.glsl"
#include "/effects/shared/fog/cave_border_fog.glsl"
#include "/effects/shared/fog/vanilla_fog.glsl"
#endif // OMNI_EFFECT_FOG_FOG_INCLUDED

// 严格对照补充说明：
// 末地三维噪声、云分形噪声与低质量分形噪声都保留参考的调用方式。
// 三维噪声的贴图分辨率在参考里固定为六十四，这里显式写六十四，避免宿主选项改变核对结果。
// 指数循环的层数与衰减照参考，兼容重载只补上缺失的贴图参数。
// 雾密度、涡旋雾与水下雾仍由各自的宿主文件提供相机、时间和阴影输入。
// 这些输入不进入分形噪声的算式，因此不会改变噪声的常数集合。

// 补充说明：三维噪声与分形噪声的兼容重载只补贴图和分辨率。
// 分辨率固定为六十四，是为了与参考贴图的采样网格一致。
// 两次噪声调用的顺序照参考，先基础层再细节层。
// 雾密度兼容重载使用上下界与衰减选项，不读取相机位置。
// 水下雾与体积雾仍由各自宿主文件提供深度与阴影输入。
// 这些输入不改变密度算式，也不会改变常数集合。
// 兼容重载保留原函数名，旧的显式参数版本继续可用。
