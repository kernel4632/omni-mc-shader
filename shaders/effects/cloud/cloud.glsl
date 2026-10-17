/*
云：把体积云、平面云和云影贴图按 iterationT 的算法画进天空并遮暗地表，外加云影的高斯模糊。
调用位置：延迟三号主体画天空像素与天空盒时调用 `NubisCumulus`、`PlanarClouds`、`CalculateStars` 一起使用；
    三号主体右上角写云影贴图时调用 `CloudShadowTex`；
    延迟四号与五号主体对云影贴图做横向、纵向模糊时调用 `CloudShadowAxialBlur`；
    合成主体算地表直射光与天光被云遮挡多少时调用 `CloudShadowFromTex`、`GetSmoothCloudShadow`。
可复制示例：
    `NubisCumulus(compositeColor, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance);`
    `PlanarClouds(compositeColor, worldDir, camera, dither, cloudTransmittance);`
    `float shadow = CloudShadowFromTex(worldPos);`
设计原因与取舍：
    体积云与平面云都能出图，各自带开关，默认都开；两者共用同一份云量、云高、云厚、云色等选项，
    切换或叠加时色调不突变。
    云影不是另外建模，而是沿光线穿过同一份三维云密度采样，所以天上的云和地上的影对得上。
    调用前提（iterationT 原样保留）：调用方必须先声明 `colortex2`、`worldShadowVector`、`worldSunVector`、
    `worldMoonVector`、`colorShadowlight`、`colorSkylight` 等全局量；延迟阶段四号、六号画面由程序自己
    打开 `COLORTEX_CLOUDNOISE` 换成三维云噪声，本文件按那个宏读三维采样器。
*/
#ifndef OMNI_CLOUD_INCLUDED
#define OMNI_CLOUD_INCLUDED
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"平面云","en_us":"Planar Clouds"},"description":{"zh_cn":"把云画在一层固定高度的平面上，便宜且连续。","en_us":"Draws the clouds on one fixed-altitude sheet; cheap and continuous."}}
#define OMNI_PLANAR_CLOUDS
// @option {"label":{"zh_cn":"平面云量","en_us":"Planar Cloud Coverage"},"description":{"zh_cn":"平面云铺满天空的程度。","en_us":"How much the planar clouds cover the sky."},"slider":true}
#define OMNI_PLANAR_COVERAGE 0.5 // [0.3 0.32 0.34 0.36 0.38 0.4 0.42 0.44 0.46 0.48 0.5 0.52 0.54 0.56 0.58 0.6 0.62 0.64 0.66 0.68 0.7 0.72 0.74 0.76 0.78 0.8 0.82 0.84 0.86 0.88 0.9]
// @option {"label":{"zh_cn":"平面云噪声尺度","en_us":"Planar Cloud Noise Scale"},"description":{"zh_cn":"平面云块的大小，越大云块越小越碎。","en_us":"Planar cloud block size; larger is smaller and more broken."},"slider":true}
#define OMNI_PLANAR_NOISE_SCALE 0.025 // [0.01 0.015 0.02 0.025 0.03 0.035 0.04 0.045 0.5]
// @option {"label":{"zh_cn":"平面云高度","en_us":"Planar Cloud Altitude"},"description":{"zh_cn":"平面云挂的高度，单位方块。","en_us":"Altitude of the planar clouds in blocks."}}
#define OMNI_PLANAR_ALTITUDE 6000.0 // [2000.0 2500.0 3000.0 3500.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0]
// @option {"label":{"zh_cn":"体积云","en_us":"Volumetric Clouds"},"description":{"zh_cn":"沿视线在云层里步进得到厚实的云，代价较高。","en_us":"Marches through the cloud layer for thick clouds; costlier."}}
#define OMNI_VOLUMETRIC_CLOUDS
// @option {"label":{"zh_cn":"云精细度","en_us":"Cloud Quality"},"description":{"zh_cn":"体积云沿视线的步数倍率，越大越细也越慢。","en_us":"Multiplier on the volumetric cloud steps; higher is finer and slower."},"slider":true}
#define OMNI_CLOUD_QUALITY 1.0 // [0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"体积云采样数","en_us":"Cloud Samples"},"description":{"zh_cn":"体积云沿视线采样的次数上限（朝天看时略少），越大越细也越慢；与上面的精细度倍率相乘。","en_us":"Upper bound on volumetric cloud view samples (slightly fewer looking up); higher is finer and slower; multiplied by the quality factor above."},"slider":true}
#define OMNI_CLOUD_SAMPLES 20 // [8 10 12 16 20 24 28 32 40 48 56 64 80 96 128]
// @option {"label":{"zh_cn":"晴天云高度","en_us":"Clear Cloud Altitude"},"description":{"zh_cn":"晴天云层底部高度，单位方块。","en_us":"Base altitude of the clear-weather cloud layer in blocks."}}
#define OMNI_CLOUD_CLEAR_ALTITUDE 500.0 // [300.0 350.0 400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2250.0 2500.0 2750.0 3000.0 4000.0 5000.0]
// @option {"label":{"zh_cn":"晴天云厚度","en_us":"Clear Cloud Thickness"},"description":{"zh_cn":"晴天云层有多厚，单位方块。","en_us":"Thickness of the clear-weather cloud layer in blocks."}}
#define OMNI_CLOUD_CLEAR_THICKNESS 500.0 // [100.0 150.0 200.0 250.0 300.0 350.0 400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2250.0 2500.0 2750.0 3000.0 4000.0 5000.0]
// @option {"label":{"zh_cn":"晴天云量","en_us":"Clear Cloud Coverage"},"description":{"zh_cn":"晴天云层覆盖多少天空。","en_us":"How much the clear-weather clouds cover the sky."},"slider":true}
#define OMNI_CLOUD_CLEAR_COVERAGE 0.28 // [0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3 0.32 0.34 0.36 0.38 0.4 0.42 0.44 0.46 0.48 0.5 0.52 0.54 0.56 0.58 0.6 0.62 0.64 0.66 0.68 0.7 0.72 0.74 0.76 0.78 0.8 0.82 0.84 0.86 0.88 0.9 0.92 0.94 0.96 0.98 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"晴天云密度","en_us":"Clear Cloud Density"},"description":{"zh_cn":"晴天云的消光强度，越大云越不透光。","en_us":"Extinction of the clear-weather clouds; higher is more opaque."},"slider":true}
#define OMNI_CLOUD_CLEAR_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"晴天云受光","en_us":"Clear Cloud Sunlighting"},"description":{"zh_cn":"晴天云受的直射光强度。","en_us":"Direct sunlight strength on the clear-weather clouds."},"slider":true}
#define OMNI_CLOUD_CLEAR_SUNLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"晴天云天光","en_us":"Clear Cloud Skylighting"},"description":{"zh_cn":"晴天云受的环境光强度。","en_us":"Ambient light strength on the clear-weather clouds."},"slider":true}
#define OMNI_CLOUD_CLEAR_SKYLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"晴天云块大小","en_us":"Clear Cloud Scale"},"description":{"zh_cn":"晴天云块大小，越大云块越小。","en_us":"Clear-weather cloud block size; larger is smaller."},"slider":true}
#define OMNI_CLOUD_CLEAR_SCALE 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"雨天云高度","en_us":"Rain Cloud Altitude"},"description":{"zh_cn":"雨天云层底部高度，单位方块。","en_us":"Base altitude of the rain cloud layer in blocks."}}
#define OMNI_CLOUD_RAIN_ALTITUDE 500.0 // [300.0 350.0 400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2250.0 2500.0 2750.0 3000.0 4000.0 5000.0]
// @option {"label":{"zh_cn":"雨天云厚度","en_us":"Rain Cloud Thickness"},"description":{"zh_cn":"雨天云层有多厚，单位方块。","en_us":"Thickness of the rain cloud layer in blocks."}}
#define OMNI_CLOUD_RAIN_THICKNESS 800.0 // [100.0 150.0 200.0 250.0 300.0 350.0 400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2250.0 2500.0 2750.0 3000.0 4000.0 5000.0]
// @option {"label":{"zh_cn":"雨天云量","en_us":"Rain Cloud Coverage"},"description":{"zh_cn":"雨天云层覆盖多少天空。","en_us":"How much the rain clouds cover the sky."},"slider":true}
#define OMNI_CLOUD_RAIN_COVERAGE 0.96 // [0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3 0.32 0.34 0.36 0.38 0.4 0.42 0.44 0.46 0.48 0.5 0.52 0.54 0.56 0.58 0.6 0.62 0.64 0.66 0.68 0.7 0.72 0.74 0.76 0.78 0.8 0.82 0.84 0.86 0.88 0.9 0.92 0.94 0.96 0.98 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"雨天云密度","en_us":"Rain Cloud Density"},"description":{"zh_cn":"雨天云的消光强度，越大云越不透光。","en_us":"Extinction of the rain clouds; higher is more opaque."},"slider":true}
#define OMNI_CLOUD_RAIN_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"雨天云受光","en_us":"Rain Cloud Sunlighting"},"description":{"zh_cn":"雨天云受的直射光强度，通常压得更低。","en_us":"Direct sunlight strength on the rain clouds; usually lower."},"slider":true}
#define OMNI_CLOUD_RAIN_SUNLIGHTING 0.4 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"雨天云天光","en_us":"Rain Cloud Skylighting"},"description":{"zh_cn":"雨天云受的环境光强度。","en_us":"Ambient light strength on the rain clouds."},"slider":true}
#define OMNI_CLOUD_RAIN_SKYLIGHTING 0.8 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"雨天云块大小","en_us":"Rain Cloud Scale"},"description":{"zh_cn":"雨天云块大小，越大云块越小。","en_us":"Rain cloud block size; larger is smaller."},"slider":true}
#define OMNI_CLOUD_RAIN_SCALE 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 5.0]
// @option {"label":{"zh_cn":"云细节噪声强度","en_us":"Cloud Detailed Noise Strength"},"description":{"zh_cn":"云边缘细节噪声的强度，越大碎边越明显。","en_us":"Strength of the fine noise on cloud edges; higher is more broken."},"slider":true}
#define OMNI_CLOUD_DETAILED_NOISE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0]
// @option {"label":{"zh_cn":"云基础噪声尺度","en_us":"Cloud Base Noise Scale"},"description":{"zh_cn":"云形状基础噪声的空间频率，越大云块越小。","en_us":"Spatial frequency of the base cloud shape; higher is smaller blocks."},"slider":true}
#define OMNI_CLOUD_BASE_NOISE_SCALE 0.0007 // [0.0001 0.00015 0.0002 0.00025 0.0003 0.00035 0.0004 0.00045 0.0005 0.00055 0.0006 0.00065 0.0007 0.00075 0.0008 0.00085 0.0009 0.00095 0.001 0.0011 0.0012 0.0014 0.0015 0.0016 0.0017 0.0018 0.0019 0.002]
// @option {"label":{"zh_cn":"云细节噪声尺度","en_us":"Cloud Detailed Noise Scale"},"description":{"zh_cn":"云边缘细节噪声的空间频率。","en_us":"Spatial frequency of the fine cloud-edge noise."},"slider":true}
#define OMNI_CLOUD_DETAILED_NOISE_SCALE 0.007 // [0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.011 0.012 0.013 0.014 0.015 0.016 0.017 0.018 0.019 0.02]
// @option {"label":{"zh_cn":"云底亮度","en_us":"Cloud Bottom Brightness"},"description":{"zh_cn":"云背光面保留的底光，越大背光云越不黑。","en_us":"Base light kept on shaded cloud sides; higher is less black."},"slider":true}
#define OMNI_CLOUD_BOTTOM_BRIGHTNESS 0.15 // [0.01 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"云外散射指数","en_us":"Cloud Outscatter Factor"},"description":{"zh_cn":"阳光透过云的集中程度，越大越集中在太阳方向。","en_us":"How tightly light spreads through the clouds; higher concentrates it near the sun."},"slider":true}
#define OMNI_CLOUD_OUTSCATTER_FACTOR 1.3 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"云量噪声偏移","en_us":"Cloud Coverage Noise Offset"},"description":{"zh_cn":"云量在噪声里的偏移，改变云块的整体分布。","en_us":"Offsets the coverage noise, changing the overall cloud layout."},"slider":true}
#define OMNI_CLOUD_COVERAGE_NOISE_OFFSET 0.68 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label":{"zh_cn":"云远距淡出","en_us":"Cloud Fade"},"description":{"zh_cn":"远处云逐渐融进天空，避免出现硬边。","en_us":"Fades distant clouds into the sky to avoid hard edges."}}
#define OMNI_CLOUD_FADE
// @option {"label":{"zh_cn":"云速","en_us":"Cloud Speed"},"description":{"zh_cn":"云飘动的快慢。","en_us":"How fast the clouds drift."},"slider":true}
#define OMNI_CLOUD_SPEED 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 5.0 7.5 10.0 15.0 20.0 30.0 40.0 50.0 75.0 100.0]
// @option {"label":{"zh_cn":"云时间偏移","en_us":"Cloud Time Offset"},"description":{"zh_cn":"给云和平面云的飘动时间加一个固定偏移，用来错开云的位置；不改变飘动速度。","en_us":"Offsets the cloud drift time by a fixed amount to shift their position; does not change speed."},"slider":true}
#define OMNI_CLOUD_TIME_OFFSET 0 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200 205 210 215 220 225 230 235 240 245 250 255 260 265 270 275 280 285 290 295 300 305 310 315 320 325 330 335 340 345 350 355]
// @option {"label":{"zh_cn":"云影","en_us":"Cloud Shadow"},"description":{"zh_cn":"云在地上投下阴影。","en_us":"Clouds cast shadows on the ground."}}
#define OMNI_CLOUD_SHADOW
// @option {"label":{"zh_cn":"云影淡出","en_us":"Cloud Shadow Fade"},"description":{"zh_cn":"太阳贴近地平线时让云影变淡，避免阴影拉得过长。","en_us":"Fades cloud shadows as the sun nears the horizon."}}
#define OMNI_CLOUD_SHADOW_FADE
// @option {"label":{"zh_cn":"云影范围","en_us":"Cloud Shadow Range"},"description":{"zh_cn":"云影贴图覆盖的地表范围，单位方块。","en_us":"Ground area covered by the cloud shadow texture, in blocks."}}
#define OMNI_CLOUD_SHADOW_RANGE 4096.0 // [2048.0 3072.0 4096.0 6144.0 8192.0 12288.0 16384.0]
// @option {"label":{"zh_cn":"云影贴图尺寸","en_us":"Cloud Shadow Texture Size"},"description":{"zh_cn":"云影贴图的边长上限，越大云影越细。","en_us":"Side length cap of the cloud shadow texture; higher is finer."},"slider":true}
#define OMNI_CLOUD_SHADOWTEX_SIZE 256.0 // [128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
// @option {"label":{"zh_cn":"雨天阴影","en_us":"Rain Shadow"},"description":{"zh_cn":"阴雨天直射光被云挡掉多少，越大雨天越暗。","en_us":"How much rain clouds block direct light; higher is darker."},"slider":true}
#define OMNI_RAIN_SHADOW 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// 下面是合并 Eclipse 多层云新增的附加层选项：卷云、高层云与积雨云。附加层默认全部关闭，
// 关闭时下面的采样与光照整段不参与编译，默认画面与只有基础云时完全一致。
// @option {"label":{"zh_cn":"卷云层","en_us":"Cirrus Layer"},"description":{"zh_cn":"在最高处加一层薄卷云；附加层默认关闭，关闭时不产生任何采样。","en_us":"Adds a thin cirrus sheet at the top; off by default and adds no sampling when off."}}
//#define OMNI_CLOUD_CIRRUS
// @option {"label":{"zh_cn":"卷云高度","en_us":"Cirrus Altitude"},"description":{"zh_cn":"卷云层底部高度，单位方块，取值照 Eclipse 的卷云高度。","en_us":"Base altitude of the cirrus in blocks; value from Eclipse."}}
#define OMNI_CLOUD_CIRRUS_ALTITUDE 7000.0 // [3000.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0]
// @option {"label":{"zh_cn":"卷云厚度","en_us":"Cirrus Thickness"},"description":{"zh_cn":"卷云层厚度，单位方块；Eclipse 把卷云当成薄面，这里体积步进需要一点厚度。","en_us":"Thickness of the cirrus in blocks; Eclipse treats it as a thin sheet, our volumetric march needs some thickness."}}
#define OMNI_CLOUD_CIRRUS_THICKNESS 400.0 // [100.0 200.0 300.0 400.0 500.0 600.0 800.0 1000.0 1500.0 2000.0]
// @option {"label":{"zh_cn":"卷云量","en_us":"Cirrus Coverage"},"description":{"zh_cn":"卷云铺满天空的程度，取值照 Eclipse 的卷云云量。","en_us":"How much the cirrus covers the sky; value from Eclipse."},"slider":true}
#define OMNI_CLOUD_CIRRUS_COVERAGE 0.07 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.12 0.14 0.16 0.18 0.2 0.22 0.24 0.26 0.28 0.3]
// @option {"label":{"zh_cn":"卷云密度","en_us":"Cirrus Density"},"description":{"zh_cn":"卷云的消光强度，取值照 Eclipse 的卷云密度，默认很薄。","en_us":"Extinction of the cirrus; value from Eclipse, very thin by default."},"slider":true}
#define OMNI_CLOUD_CIRRUS_DENSITY 0.005 // [0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.15 0.2 0.3 0.5]
// @option {"label":{"zh_cn":"卷云块大小","en_us":"Cirrus Scale"},"description":{"zh_cn":"卷云块的大小，取值照 Eclipse 的卷云尺度。","en_us":"Block size of the cirrus; value from Eclipse."},"slider":true}
#define OMNI_CLOUD_CIRRUS_SCALE 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"卷云受光","en_us":"Cirrus Sunlighting"},"description":{"zh_cn":"卷云受的直射光强度；Eclipse 没有单列这一项，这里照基础云的受光补一个可调值。","en_us":"Direct sunlight strength on the cirrus; Eclipse has no such option, added to match the base cloud lighting."},"slider":true}
#define OMNI_CLOUD_CIRRUS_SUNLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"卷云天光","en_us":"Cirrus Skylighting"},"description":{"zh_cn":"卷云受的环境光强度；同受光一样是补的可调值。","en_us":"Ambient light strength on the cirrus; an added knob like the sunlighting."},"slider":true}
#define OMNI_CLOUD_CIRRUS_SKYLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"高层云层","en_us":"Altostratus Layer"},"description":{"zh_cn":"在中等高度加一层较平的高层云；默认关闭，关闭时不产生采样。","en_us":"Adds a flatter altostratus sheet at mid altitude; off by default."}}
//#define OMNI_CLOUD_ALTOSTRATUS
// @option {"label":{"zh_cn":"高层云高度","en_us":"Altostratus Altitude"},"description":{"zh_cn":"高层云层底部高度，单位方块，取值照 Eclipse 的高层云高度。","en_us":"Base altitude of the altostratus in blocks; value from Eclipse."}}
#define OMNI_CLOUD_ALTOSTRATUS_ALTITUDE 5000.0 // [2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0]
// @option {"label":{"zh_cn":"高层云厚度","en_us":"Altostratus Thickness"},"description":{"zh_cn":"高层云层厚度，单位方块；Eclipse 把它当成薄面，这里步进需要一点厚度。","en_us":"Thickness of the altostratus in blocks; Eclipse treats it as a thin sheet."}}
#define OMNI_CLOUD_ALTOSTRATUS_THICKNESS 600.0 // [100.0 200.0 300.0 400.0 600.0 800.0 1000.0 1500.0 2000.0]
// @option {"label":{"zh_cn":"高层云量","en_us":"Altostratus Coverage"},"description":{"zh_cn":"高层云铺满天空的程度，取值照 Eclipse 的高层云云量。","en_us":"How much the altostratus covers the sky; value from Eclipse."},"slider":true}
#define OMNI_CLOUD_ALTOSTRATUS_COVERAGE 0.6 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"高层云密度","en_us":"Altostratus Density"},"description":{"zh_cn":"高层云的消光强度，取值照 Eclipse 的高层云密度。","en_us":"Extinction of the altostratus; value from Eclipse."},"slider":true}
#define OMNI_CLOUD_ALTOSTRATUS_DENSITY 0.1 // [0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.1 0.12 0.15 0.2 0.3 0.4 0.5 0.6 0.8 1.0]
// @option {"label":{"zh_cn":"高层云块大小","en_us":"Altostratus Scale"},"description":{"zh_cn":"高层云块的大小，取值照 Eclipse 的高层云尺度。","en_us":"Block size of the altostratus; value from Eclipse."},"slider":true}
#define OMNI_CLOUD_ALTOSTRATUS_SCALE 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"高层云受光","en_us":"Altostratus Sunlighting"},"description":{"zh_cn":"高层云受的直射光强度；同卷云一样是补的可调值。","en_us":"Direct sunlight strength on the altostratus; an added knob."},"slider":true}
#define OMNI_CLOUD_ALTOSTRATUS_SUNLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"高层云天光","en_us":"Altostratus Skylighting"},"description":{"zh_cn":"高层云受的环境光强度；同受光一样是补的可调值。","en_us":"Ambient light strength on the altostratus; an added knob."},"slider":true}
#define OMNI_CLOUD_ALTOSTRATUS_SKYLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"积雨云层","en_us":"Cumulonimbus Layer"},"description":{"zh_cn":"加一层高耸的雷暴积雨云；默认关闭，关闭时不产生采样。Eclipse 的三档模式因缺少场景强度输入并入开关。","en_us":"Adds a towering cumulonimbus; off by default. Eclipse's three modes collapse to a toggle because the scene strength input is absent."}}
//#define OMNI_CLOUD_CUMULONIMBUS
// @option {"label":{"zh_cn":"积雨云高度","en_us":"Cumulonimbus Altitude"},"description":{"zh_cn":"积雨云底部高度，单位方块，取值照 Eclipse 积雨云底部高度。","en_us":"Base altitude of the cumulonimbus in blocks; value from Eclipse."}}
#define OMNI_CLOUD_CUMULONIMBUS_ALTITUDE 600.0 // [300.0 400.0 500.0 600.0 800.0 1000.0 1500.0 2000.0]
// @option {"label":{"zh_cn":"积雨云厚度","en_us":"Cumulonimbus Thickness"},"description":{"zh_cn":"积雨云层厚度，单位方块，取值照 Eclipse 积雨云高度范围。","en_us":"Thickness of the cumulonimbus in blocks; value from Eclipse."}}
#define OMNI_CLOUD_CUMULONIMBUS_THICKNESS 4000.0 // [1000.0 2000.0 3000.0 4000.0 5000.0 6000.0 8000.0]
// @option {"label":{"zh_cn":"积雨云量","en_us":"Cumulonimbus Coverage"},"description":{"zh_cn":"积雨云铺满天空的程度；Eclipse 没有这一项，这里用与基础云一致的云量下限。","en_us":"How much the cumulonimbus covers the sky; Eclipse has no such option."},"slider":true}
#define OMNI_CLOUD_CUMULONIMBUS_COVERAGE 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
// @option {"label":{"zh_cn":"积雨云密度","en_us":"Cumulonimbus Density"},"description":{"zh_cn":"积雨云的消光强度，取值照 Eclipse 积雨云固定密度零点八。","en_us":"Extinction of the cumulonimbus; Eclipse uses a fixed 0.8."},"slider":true}
#define OMNI_CLOUD_CUMULONIMBUS_DENSITY 0.8 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0]
// @option {"label":{"zh_cn":"积雨云块大小","en_us":"Cumulonimbus Scale"},"description":{"zh_cn":"积雨云块的大小；Eclipse 没有这一项，默认与基础云相同。","en_us":"Block size of the cumulonimbus; default matches the base cloud."},"slider":true}
#define OMNI_CLOUD_CUMULONIMBUS_SCALE 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"积雨云受光","en_us":"Cumulonimbus Sunlighting"},"description":{"zh_cn":"积雨云受的直射光强度；同其它附加层一样是补的可调值。","en_us":"Direct sunlight strength on the cumulonimbus; an added knob."},"slider":true}
#define OMNI_CLOUD_CUMULONIMBUS_SUNLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"积雨云天光","en_us":"Cumulonimbus Skylighting"},"description":{"zh_cn":"积雨云受的环境光强度；同受光一样是补的可调值。","en_us":"Ambient light strength on the cumulonimbus; an added knob."},"slider":true}
#define OMNI_CLOUD_CUMULONIMBUS_SKYLIGHTING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"积雨云内闪电","en_us":"Cumulonimbus Lightning"},"description":{"zh_cn":"积雨云内部被真实闪电照亮；需要同时打开积雨云层与闪电照明，关闭时无任何计算。","en_us":"Lights the cumulonimbus from real lightning; requires both the cumulonimbus layer and lightning illumination."}}
//#define OMNI_CUMULONIMBUS_LIGHTNING
// @option {"label":{"zh_cn":"积雨云闪电亮度","en_us":"Cumulonimbus Lightning Brightness"},"description":{"zh_cn":"积雨云内闪电多亮，取值照 Eclipse 的闪电亮度。","en_us":"How bright the cumulonimbus lightning is; value from Eclipse."},"slider":true}
#define OMNI_CUMULONIMBUS_LIGHTNING_BRIGHTNESS 100.0 // [25.0 50.0 75.0 100.0 125.0 150.0 200.0]
// 云的算法依赖大气透视与共用数学，显式引入而不依赖调用顺序。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/sky/sky.glsl"
// 积雨云内闪电复用氛围文件里的闪电开关与加载器输入（`lightningBoltPosition`），显式引入而不依赖调用顺序。
#include "/effects/sky/atmosphere.glsl"
// 每日天气：按游戏日给出当天四层云的覆盖度与密度，供基础云与各附加层替换默认云量；
// 总开关关闭时它整段不参与编译，默认画面与原来一致。文件自带守卫，重复引入无副作用。
#include "/effects/weather/dailyweather.glsl"
// 体积云与平面云只延迟三号用，且要读三维云噪声；别的程序（合成、云影模糊）不该把它们编译进来，
// 否则会把三维噪声贴图当成二维采样。原程序靠“只有延迟三号引入这两个文件”区分，这里用一个显式守卫。
#if defined COLORTEX_CLOUDNOISE && defined OMNI_DEFERRED3_PASS
// --- 亨耶-格林斯坦相位函数：云这种大粒子的前向散射，输入夹角余弦与不透明度参数 ---
float HenyeyGreenstein(float inCosAngle, float inG){
	float num = 1.0 - inG * inG; // 分子，归一化用。
	float denom = 1.0 + inG * inG - 2.0 * inG * inCosAngle; // 分母，越前向越小。
	float rsqrt_denom = inversesqrt(denom); // 分母的近似负二分之一次方。
	return num * rsqrt_denom * rsqrt_denom * rsqrt_denom * (0.25 / PI); // 归一化后返回相位值。
}
// 云顶上凸的收口曲线：把零到一映射成一道平滑的弧，云顶因此不是平切。
float curveTop(float x){
	x = x - 1.0; // 先平移到负一到零。
	return 1.0 - x * x; // 开口向下的抛物线。
}
// 采样云密度：先叠基础形状与云量得到不透明密度，再叠细节噪声得到碎边。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sampleDetail` 为假时跳过细节以省性能。
// `coverage` 是这一层的云量下限：基础云传晴雨混合值，附加层传各自的云量选项。
vec2 SampleCloudDensity(vec4 cloudPos, vec3 windDirection, bool sampleDetail, float coverage){
	// 基础形状：低频三维噪声决定云块大轮廓。
		vec4 baseNoise = textureLod(colortex4, cloudPos.xyz * OMNI_CLOUD_BASE_NOISE_SCALE + windDirection * 10.0, 0.0); // 按云坐标与风偏移读基础噪声。
		float baseDensity = baseNoise.y * 0.4 + baseNoise.z * 0.4 + baseNoise.w * 0.2; // 三个通道加权得到形状。
		baseDensity = remapSaturate(baseNoise.x, baseDensity - 1.0, 1.0); // 用第一通道做概率重映射，得到云块。
		float shapeCurve = curveTop(saturate(1.0 - cloudPos.w)) * 0.5; // 上半段的收口曲线。
		shapeCurve += curve(saturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 下半段的收口曲线。
		baseDensity *= shapeCurve; // 竖直方向收口，云像是浮在中间。
		baseDensity *= fsqrt(saturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 下半段略压扁。
		baseDensity *= mix(1.0, curveTop(saturate(cloudPos.w * 3.0)), wetness); // 雨天让云更集中在顶部。
	// 云量：单独的更低频噪声决定这一块区域有没有云。
		float coverageNoise = textureLod(colortex4, cloudPos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + windDirection + OMNI_CLOUD_COVERAGE_NOISE_OFFSET, 0.0).x; // 极低频云量噪声。
		coverage = remapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 把云量映射成密度下限。
		baseDensity = remapSaturate(baseDensity, coverage, 1.0); // 低于下限的部分去掉。
	// 密度控制：竖直方向再塑形，让云底更密云顶更薄。
		baseDensity *= curve(saturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 中段加厚。
		baseDensity *= curveTop(saturate(cloudPos.w * 1.8)); // 顶部收口。
		baseDensity = saturate(baseDensity); // 收敛到零到一。
	float detailedDensity = 0.0; // 详细密度，下面按是否需要细节赋值。
	if(baseDensity > 1e-6 && sampleDetail){ // 只有基础密度确实存在才叠细节。
		// 卷曲噪声：让云的边缘随高度发生横向扭曲。
			float curlNoise = textureLod(noisetex, cloudPos.xy * 0.0001, 0.0).w; // 读噪声第四通道。
			cloudPos.xy += curlNoise * (100.0 - cloudPos.w * 100.0); // 越靠云底扭曲越大。
		// 细节噪声：高频三维噪声给云块加碎边。
			vec3 detailedNoise = textureLod(colortex6, cloudPos.xyz * OMNI_CLOUD_DETAILED_NOISE_SCALE + windDirection * 140.0, 0.0).xyz; // 读三十二立方细节噪声。
			detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125; // 三通道按权重合成侵蚀量。
			detailedDensity *= (0.21 - wetness * 0.11) * OMNI_CLOUD_DETAILED_NOISE_STRENGTH; // 强度与天气权重可调。
			detailedDensity = remapSaturate(baseDensity, detailedDensity, 1.0); // 用基础密度限制侵蚀范围。
	}else{ // 不需要细节时直接用基础密度。
		detailedDensity = baseDensity; // 保持连续。
	}
	return vec2(baseDensity, detailedDensity); // 返回两份密度。
}
// 基础云的密度采样：云量取晴雨混合值，行为与 iterationT 的 `SampleDensity` 完全一致。
vec2 SampleDensity(vec4 cloudPos, vec3 windDirection, bool sampleDetail){
	return SampleCloudDensity(cloudPos, windDirection, sampleDetail, mix(OMNI_CLOUD_CLEAR_COVERAGE, OMNI_CLOUD_RAIN_COVERAGE, wetness)); // 传入晴雨混合云量。
}
// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向加随高度增大的偏移。
vec4 SetCloudPos(vec3 marchingPos, vec2 cloudAltitude, float planetRadius, float cloudScale, vec3 windDirection){
	vec4 cloudPos = vec4(marchingPos, 0.0); // 前三通道是位置，第四通道是层内高度。
	cloudPos.y = length(cloudPos.xyz + vec3(0.0, planetRadius, 0.0)) - planetRadius; // 用球面距离算真实高度。
	cloudPos.w = remapSaturate(cloudPos.y, cloudAltitude.x, cloudAltitude.y); // 在云层里的归一化高度。
	cloudPos.xyz = cloudPos.xyz * cloudScale + vec3(30.0 * cloudPos.w, 0.0, -12.0 * cloudPos.w); // 水平缩放并随高度剪切，云因此有斜向层次。
	return cloudPos; // 返回云坐标。
}
// 云的光照：沿光方向在云里步进估遮挡，再算直射与环境的合成颜色。
// `coverage` 是这一层的云量下限，供光照步进复用同一份形状，基础云与附加层各自传入。
vec3 CloudLighting(vec3 marchingPos, vec2 cloudAltitude, float planetRadius, float cloudScale, vec2 lightingStrength, vec2 cloudDensity, vec4 cloudPos, vec3 windDirection, float noise, float VdotL, float coverage){
	float stepLength = 28.0; // 光照步进起始步长。
	float lightingDensity = 0.0; // 沿光方向累积的云密度。
	for (int i = 0; i < 5; i++, stepLength *= 1.5){ // 五步，步长逐步放大。
		vec4 checkPos = SetCloudPos(marchingPos + worldShadowVector * stepLength * noise, cloudAltitude, planetRadius, cloudScale, windDirection); // 取样点。
		lightingDensity += SampleCloudDensity(checkPos, windDirection, i < 3, coverage).y * stepLength; // 前三步带细节，后两步省掉。
		marchingPos += worldShadowVector * stepLength; // 沿光方向推进。
	}
	// 直射散射：透过云层的阳光，含一个很宽的环境项。
		float hg = HenyeyGreenstein(VdotL, 0.7); // 前向相位，决定银边。
		float directScattering = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - wetness * 0.8); // 透过率乘前向相位。
		directScattering += (1.0 / (lightingDensity * 0.2 + 1.0)) * (HenyeyGreenstein(VdotL, 0.2) + 0.1); // 叠一个更宽的环境项。
		directScattering *= hg * 2.0 + 1.0; // 银边再加强一次。
		directScattering *= mix(OMNI_CLOUD_BOTTOM_BRIGHTNESS, 0.005 + pow(cloudDensity.y, OMNI_CLOUD_OUTSCATTER_FACTOR), curve(saturate(cloudPos.w * 3.333 - 0.333))); // 云底亮度与外散射按高度混合。
		directScattering *= pow(max(cloudPos.w, 0.05), 0.75); // 云顶更亮。
		vec3 cloudColor = colorShadowlight * (directScattering * lightingStrength.x * 36.0); // 乘直射光色与强度。
	// 环境散射：云背光面接到的天光。
		float ambientScattering = 1.0 - cloudDensity.x; // 云越薄环境光透得越多。
		ambientScattering *= fsqrt(cloudPos.w); // 高处环境光更多。
		cloudColor += colorSkylight * (ambientScattering * lightingStrength.y * 0.35); // 乘天光色与强度。
	return cloudColor; // 返回云的颜色。
}
// 体积云步进核心：沿视线在云层里步进，累加颜色与透过率，最后按空气透视与天空混合。
// 受光强度、云块尺度、密度与云量都由调用方给出，基础云与附加层因此共用同一套步进与光照。
// 调用前提：`color` 是已经算好的天空颜色（会被就地修改）、`worldDir` 是单位方向、`camera` 是米制相机位置。
void NubisCloudLayer(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance, vec2 lightingStrength, float cloudScale, float cloudDensityOption, float cloudCoverage){
	const float planetRadius = atmosphereModel_bottom_radius * 1e3; // 行星半径从大气常数换成米。
	// 步进区间：先求视线与云层上下界的交点。
		vec3 rayStartPos = vec3(0.0, planetRadius + cameraPosition.y, 0.0); // 相机在行星球上的位置。
		vec2 iBottom = RaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude.x); // 与云层底的交点。
		vec2 iTop = RaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude.y); // 与云层顶的交点。
		vec2 iMarching = cameraPosition.y > cloudAltitude.y ? vec2(iTop.x, iBottom.x) : vec2(iBottom.y, iTop.y); // 相机在云上还是云下决定进出顺序。
		vec3 marchingStart = iMarching.x * worldDir; // 步进起点相对相机。
		vec3 marchingEnd = iMarching.y * worldDir; // 步进终点相对相机。
		float inCloud = (1.0 - saturate((cameraPosition.y - cloudAltitude.y) * 0.005)) * // 相机低于云顶的权重。
						(1.0 - saturate((cloudAltitude.x - cameraPosition.y) * 0.005)); // 相机高于云底的权重。
		float iInner = iBottom.y >= 0.0 && cameraPosition.y > cloudAltitude.x ? iBottom.x : iTop.y; // 云内起点距离。
		iInner = min(iInner, 5000.0); // 限长避免步进过远。
		marchingStart = marchingStart * (1.0 - inCloud) + cameraPosition; // 相机在云内时起点改到相机。
		marchingEnd = mix(marchingEnd, iInner * worldDir, inCloud) + cameraPosition; // 相机在云内时终点改到云内一点。
		float marchingSteps = OMNI_CLOUD_SAMPLES - saturate(fsqrt(abs(worldDir.y)) * 1.4 - 0.4) * 8.0; // 采样数上限，越朝上步数越少。
		marchingSteps = max(floor(marchingSteps * OMNI_CLOUD_QUALITY), 1.0); // 乘精细度倍率，并保证至少一步。
		float marchingStepSize = 1.0 / marchingSteps; // 归一化步长。
		vec3 marchingIncrement = (marchingEnd - marchingStart) * marchingStepSize; // 每步位移。
		vec3 marchingPos = marchingStart + marchingIncrement * noise.x; // 起点加抖动量，减少条带。
		float marchingLength = length(marchingIncrement); // 每步的米制长度。
	// 云参数：受光、尺度与云量已由调用方算好，这里只把密度换算成消光系数。
		float cloudDensityMul = cloudDensityOption; // 调用方给的密度倍率。
		cloudDensityMul *= (cloudAltitude.y - cloudAltitude.x) * marchingStepSize; // 乘层厚与归一化步长得消光系数。
		float VdotL = dot(worldDir, worldShadowVector); // 视线与光方向的夹角余弦。
	// 步进：前向累积颜色，透过率降到很低就提前结束。
		vec3 cloudAccum = vec3(0.0, 0.0, 0.0); // 累积的云颜色。
		cloudTransmittance = 1.0; // 初始完全透明。
		vec3 rayHitPos = vec3(0.0); // 用于估平均命中位置的加权和。
		float sumTransmit = 0.0; // 透过率权重和。
		for (int i = 0; i < int(marchingSteps); i++, marchingPos += marchingIncrement){	// 逐步推进。
			vec4 cloudPos = SetCloudPos(marchingPos, cloudAltitude, planetRadius, cloudScale, windDirection); // 当前云坐标。
			vec2 cloudDensity = SampleCloudDensity(cloudPos, windDirection, true, cloudCoverage); // 采样密度，用本层云量。
			if (cloudDensity.y < 1e-6) continue; // 这一步没有云就跳过。
			vec3 cloudColor = CloudLighting(marchingPos, cloudAltitude, planetRadius, cloudScale, lightingStrength, cloudDensity, cloudPos, windDirection, noise.y, VdotL, cloudCoverage); // 这一段云的光照。
			float absorption = exp2(-cloudDensity.y * cloudDensityMul); // 这一段的透过率。
			cloudAccum += cloudColor * (cloudTransmittance - absorption * cloudTransmittance); // 把这一段发出并被后面吸收的部分加进来。
			rayHitPos += marchingPos * cloudTransmittance; // 记录命中位置。
			sumTransmit += cloudTransmittance; // 记录权重。
			cloudTransmittance *= absorption; // 更新透过率。
			if (cloudTransmittance < 0.0001) break; // 几乎不透明就不再采样。
		}
	// 空气透视：远处云融进大气，近处云保持实体。
		#ifdef OMNI_CLOUD_FADE // 打开淡出时按距离混合。
			rayHitPos /= sumTransmit; // 平均命中位置。
			rayHitPos -= cameraPosition; // 换成相对相机的方向。
			float fade = saturate(exp2(-length(rayHitPos) * 8e-5)); // 越远越淡。
			float cloudTransmittanceFaded = mix(1.0, cloudTransmittance, fade); // 淡出后的透过率。
			cloudAccum *= fade; // 远处的云颜色也压暗。
			if(cloudTransmittance < 0.9999){ // 只有真的有云才需要算透视。
				vec3 atmoPoint = camera + rayHitPos * 0.001; // 取云命中处附近一点。
				vec3 transmittance; // 大气透过率输出。
				vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
				color *= cloudTransmittanceFaded; // 天空被云挡住的部分。
				color += aerialPerspective * (1.0 - cloudTransmittanceFaded); // 加上空气散射。
				color += cloudAccum * transmittance; // 加上云本身被大气衰减后的颜色。
			}
		#else // 关闭淡出时直接用透过率混合。
			if(cloudTransmittance < 0.9999){ // 只有真的有云才处理。
				rayHitPos /= sumTransmit; // 平均命中位置。
				rayHitPos -= cameraPosition; // 换成相对相机的方向。
				vec3 atmoPoint = camera + rayHitPos * 0.001; // 取云命中处附近一点。
				vec3 transmittance; // 大气透过率输出。
				vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, worldMoonVector, transmittance); // 这段空气的散射。
				color *= cloudTransmittance; // 天空被云挡住的部分。
				color += aerialPerspective * (1.0 - cloudTransmittance); // 加上空气散射。
				color += cloudAccum * transmittance; // 加上云本身颜色。
			}
		#endif
}
// 基础体积云：把晴雨两档的受光、尺度、密度与云量按湿润度插值后交给步进核心，行为与 iterationT 一致。
// 调用前提：同一套步进核心，参数取晴雨混合值。
void NubisCumulus(inout vec3 color, vec3 worldDir, vec2 cloudAltitude, vec3 windDirection, vec3 camera, vec2 noise, out float cloudTransmittance){
	vec2 lightingStrength = vec2(mix(OMNI_CLOUD_CLEAR_SUNLIGHTING, OMNI_CLOUD_RAIN_SUNLIGHTING, wetness), // 直射强度按天气插值。
								 mix(OMNI_CLOUD_CLEAR_SKYLIGHTING, OMNI_CLOUD_RAIN_SKYLIGHTING, wetness)); // 环境强度按天气插值。
	float cloudScale = mix(OMNI_CLOUD_CLEAR_SCALE, OMNI_CLOUD_RAIN_SCALE, wetness); // 云块大小按天气插值。
	#ifdef OMNI_DAILY_WEATHER // 每日天气开启时，当天云量顶替“晴天云量”这一侧，雨天侧仍按湿润度插值。
		vec4 dailyCoverage = omniWeatherCoverage(); // 当天四层覆盖度：`x` 小积云、`y` 大积云、`z` 高层云、`w` 卷云。
		vec4 dailyDensity = omniWeatherDensity(); // 当天四层消光密度，顺序同上。
		float clearCoverage = max(dailyCoverage.x, dailyCoverage.y); // Omni 只有一层积云，把小积云与大积云取较大者合并成这一天的低空云量。
		float clearDensity = max(dailyDensity.x, dailyDensity.y); // 密度同样取较大者，保证低空较厚的那一天不被算薄。
	#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
		float clearCoverage = OMNI_CLOUD_CLEAR_COVERAGE; // 晴天云量选项原值。
		float clearDensity = OMNI_CLOUD_CLEAR_DENSITY; // 晴天云密度选项原值。
	#endif
	float cloudDensityMul = mix(clearDensity, OMNI_CLOUD_RAIN_DENSITY, wetness); // 密度倍率：晴天侧取当天值，雨天侧仍靠向雨云。
	float cloudCoverage = mix(clearCoverage, OMNI_CLOUD_RAIN_COVERAGE, wetness); // 云量同理，雨天仍会加厚。
	NubisCloudLayer(color, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance, lightingStrength, cloudScale, cloudDensityMul, cloudCoverage); // 交给步进核心。
}
// 附加层：卷云、高层云与积雨云，默认全部关闭；关闭时整段不参与编译，不产生任何额外采样。
// 打开后各自把海拔、厚度、云量、密度、尺度与受光交给同一套步进核心，按 Eclipse 的分层顺序叠加。
// 调用前提：`color` 是已叠好天空与基础云的天空颜色，`intersectsGround` 是视线是否打到地面。
#if defined OMNI_CLOUD_CUMULONIMBUS || defined OMNI_CLOUD_ALTOSTRATUS || defined OMNI_CLOUD_CIRRUS
void NubisExtraLayers(inout vec3 color, vec3 worldDir, vec3 windDirection, vec3 camera, vec2 noise, bool intersectsGround, inout float cloudTransmittance){
	#ifdef OMNI_CLOUD_CUMULONIMBUS // 积雨云：高耸的雷暴云，最先叠在基础云之上。
		// 为什么不受每日天气影响：Eclipse 的积雨云由雷暴强度与固定密度驱动，每日天气表没有它，所以这里只取积雨云自己的选项。
		vec2 cumulonimbusAltitude = vec2(OMNI_CLOUD_CUMULONIMBUS_ALTITUDE); // 底部高度。
		cumulonimbusAltitude.y += OMNI_CLOUD_CUMULONIMBUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > cumulonimbusAltitude.x || !intersectsGround) && (cameraPosition.y < cumulonimbusAltitude.y || worldDir.y < 0.0)){ // 与基础体积云同一可见判据。
			float cumulonimbusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cumulonimbusAltitude, windDirection, camera, noise, cumulonimbusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_CUMULONIMBUS_SUNLIGHTING, OMNI_CLOUD_CUMULONIMBUS_SKYLIGHTING), OMNI_CLOUD_CUMULONIMBUS_SCALE, OMNI_CLOUD_CUMULONIMBUS_DENSITY, OMNI_CLOUD_CUMULONIMBUS_COVERAGE); // 受光、尺度、密度与云量。
			#if defined OMNI_CUMULONIMBUS_LIGHTNING && defined OMNI_LIGHTNING && defined IS_IRIS // 只有真实闪电输入可用时才加云内闪电。
				if (lightningBoltPosition.w > 0.0){ // 没有闪电事件时不加。
					float boltDistance = length(lightningBoltPosition.xyz); // 闪电到相机的距离，闪电位置是相机相对坐标。
					float distanceWeight = saturate(1.0 - boltDistance / 7500.0); // 超过七千五百格的闪电照不到云。
					float flash = lightningBoltPosition.w * distanceWeight * (1.0 - cumulonimbusTransmittance); // 云越厚被照亮越明显。
					color += vec3(0.63, 0.756, 1.22) * (flash * OMNI_CUMULONIMBUS_LIGHTNING_BRIGHTNESS * 0.01); // 冷色闪光，亮度照 Eclipse 选项。
				}
			#endif
			cloudTransmittance *= cumulonimbusTransmittance; // 积雨云也挡住后面的天体。
		}
	#endif
	#ifdef OMNI_CLOUD_ALTOSTRATUS // 高层云：中等高度的一片云层。
		vec2 altostratusAltitude = vec2(OMNI_CLOUD_ALTOSTRATUS_ALTITUDE); // 底部高度。
		altostratusAltitude.y += OMNI_CLOUD_ALTOSTRATUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > altostratusAltitude.x || !intersectsGround) && (cameraPosition.y < altostratusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#ifdef OMNI_DAILY_WEATHER // 每日天气开启时，高层云的云量与密度取当天第三项 `l2`。
				float altostratusDensity = omniWeatherDensity().b; // 当天高层云密度。
				float altostratusCoverage = omniWeatherCoverage().b; // 当天高层云量。
			#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
				float altostratusDensity = OMNI_CLOUD_ALTOSTRATUS_DENSITY; // 高层云密度选项原值。
				float altostratusCoverage = OMNI_CLOUD_ALTOSTRATUS_COVERAGE; // 高层云量选项原值。
			#endif
			float altostratusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, altostratusAltitude, windDirection, camera, noise, altostratusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_ALTOSTRATUS_SUNLIGHTING, OMNI_CLOUD_ALTOSTRATUS_SKYLIGHTING), OMNI_CLOUD_ALTOSTRATUS_SCALE, altostratusDensity, altostratusCoverage); // 受光与尺度取选项，密度与云量取上面算好的值。
			cloudTransmittance *= altostratusTransmittance; // 高层云也挡住后面的天体。
		}
	#endif
	#ifdef OMNI_CLOUD_CIRRUS // 卷云：最高处的一层薄云。
		vec2 cirrusAltitude = vec2(OMNI_CLOUD_CIRRUS_ALTITUDE); // 底部高度。
		cirrusAltitude.y += OMNI_CLOUD_CIRRUS_THICKNESS; // 顶部高度。
		if ((cameraPosition.y > cirrusAltitude.x || !intersectsGround) && (cameraPosition.y < cirrusAltitude.y || worldDir.y < 0.0)){ // 同一可见判据。
			#ifdef OMNI_DAILY_WEATHER // 每日天气开启时，卷云的云量与密度取当天第四项 `l3`。
				float cirrusDensity = omniWeatherDensity().a; // 当天卷云密度。
				float cirrusCoverage = omniWeatherCoverage().a; // 当天卷云量。
			#else // 关闭时用选项原值，行为与引入每日天气之前完全一致。
				float cirrusDensity = OMNI_CLOUD_CIRRUS_DENSITY; // 卷云密度选项原值。
				float cirrusCoverage = OMNI_CLOUD_CIRRUS_COVERAGE; // 卷云量选项原值。
			#endif
			float cirrusTransmittance; // 这一层留下的透过率。
			NubisCloudLayer(color, worldDir, cirrusAltitude, windDirection, camera, noise, cirrusTransmittance, // 复用基础云的步进核心。
				vec2(OMNI_CLOUD_CIRRUS_SUNLIGHTING, OMNI_CLOUD_CIRRUS_SKYLIGHTING), OMNI_CLOUD_CIRRUS_SCALE, cirrusDensity, cirrusCoverage); // 受光与尺度取选项，密度与云量取上面算好的值。
			cloudTransmittance *= cirrusTransmittance; // 卷云也挡住后面的天体。
		}
	#endif
}
#endif // 附加层结束。
// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
// 调用前提：`coord` 是零到一的云影贴图坐标，采样方向用全局量 `worldShadowVector`。
float CloudShadowTex(vec2 coord, vec2 cloudAltitude, vec3 windDirection){
	coord = coord * OMNI_CLOUD_SHADOW_RANGE - (OMNI_CLOUD_SHADOW_RANGE * 0.5); // 贴图坐标换回相对相机的地表坐标。
	vec4 checkPos = vec4(coord.x + cameraPosition.x, 0.0, coord.y + cameraPosition.z, 0.0); // 取样点世界坐标。
	float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
	checkPos += vec4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y) , 0.25); // 投到云层下四分之一处。
	float cloudDensity = SampleDensity(checkPos, windDirection, false).y; // 取那一处云密度。
	checkPos += vec4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y) , 0.25); // 再往上一段。
	cloudDensity = max(cloudDensity, SampleDensity(checkPos, windDirection, false).y); // 两块取较厚的那块。
	return exp2(-cloudDensity * 20.0); // 密度换成透过率。
}
// --- 三次模糊噪声：平面云专用，与共用数学里的版本返回类型和纹理都不同，按合同留在这里一份 ---
float BicubicBlurNoise(vec2 coord){
	coord = coord * (1.2e-4 * 64.0) - 0.5; // 噪声贴图按每方块一点二万分之一缩放。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个权重。
	vec4 w1; // 两个方向的后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= 1.0 / 64.0; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(noisetex, c.yw, 0.0).w, textureLod(noisetex, c.xw, 0.0).w, m.x),
			   mix(textureLod(noisetex, c.yz, 0.0).w, textureLod(noisetex, c.xz, 0.0).w, m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊，取第四通道。
}
// 双线性噪声：平面云细节用的普通采样。
float BilinearNoise(vec2 position) {
	return textureLod(noisetex, position * 1.2e-4, 0.0).w; // 与三次版同一缩放，取第四通道。
}
// 平面云的扭曲：几层噪声叠出缓慢起伏的偏移量，让云块边缘不平整。
float GetPlanarCloudsDistortion(vec2 position, vec2 windDirection){
	float density = BilinearNoise(position - windDirection); // 第一层。
	float scale = 4.0; // 起始频率。
	for (int i = 0; i < 3; i++, scale *= 3.0){ // 三层，频率逐级乘三。
		density += BilinearNoise(scale * (position - windDirection * fsqrt(scale))) * pow(scale, -1.3); // 每层按频率的负一点三次方衰减。
	}
	return density; // 返回扭曲量。
}
// 平面云密度：位置先被扭曲，再叠多层旋转噪声得到云块。
float GetPlanarCloudsDensity(vec2 position, vec2 windDirection){
	position *= OMNI_PLANAR_NOISE_SCALE; // 按选项缩放位置。
	float distortion = GetPlanarCloudsDistortion(position, windDirection); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle)); // 按黄金角旋转并缩放的矩阵。
	float density = BicubicBlurNoise(position - windDirection); // 第一层密度。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 6.0; i++, rot *= rotateGoldenAngle){ // 六层。
		float scale = fsqrt(i); // 每层频率取平方根。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同，云块更有方向感。
		float weight = pow(octScale, -0.85 * i); // 每层权重按频率衰减。
		density += BicubicBlurNoise(noisePosition) * weight; // 累加这一层。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均到零到一附近。
	density = saturate(density + OMNI_PLANAR_COVERAGE - 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方让边缘更收。
}
// 平面云的光照密度：与上面同理，但用双线性噪声且层数更少，专供光照估计。
float GetPlanarCloudsLightingDensity(vec2 position, vec2 windDirection){
	position *= OMNI_PLANAR_NOISE_SCALE; // 按选项缩放位置。
	float distortion = GetPlanarCloudsDistortion(position, windDirection); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle)); // 按黄金角旋转并缩放的矩阵。
	float density = BicubicBlurNoise(position - windDirection); // 第一层。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 3.0; i++, rot *= rotateGoldenAngle){ // 三层，比密度版少。
		float scale = fsqrt(i); // 每层频率取平方根。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同。
		float weight = pow(octScale, -0.85 * i); // 每层权重。
		density += BilinearNoise(noisePosition) * weight; // 用便宜的噪声累加。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均。
	density = saturate(density + OMNI_PLANAR_COVERAGE - 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方收口。
}
// 平面云：视线与云平面求一次交点，再沿光方向叠几层光照密度估遮挡。
// 调用前提：`color` 已算好天空颜色（会被就地修改），`cloudTransmittance` 是体积云留下的透过率。
// 为什么不受每日天气影响：平面云是 iterationT 独有的层，Eclipse 的每日天气表没有它，所以这里只读 `OMNI_PLANAR_*`。
void PlanarClouds(inout vec3 color, vec3 worldDir, vec3 camera, float dither, float cloudTransmittance){
	float planetRadius = atmosphereModel_bottom_radius * 1e3; // 行星半径从大气常数换成米。
	vec3 rayStartPos = vec3(0.0, planetRadius + cameraPosition.y, 0.0); // 相机在行星球上的位置。
	float intersection = RaySphereIntersection(rayStartPos, worldDir, planetRadius + OMNI_PLANAR_ALTITUDE).y; // 视线与云平面的远交点。
	if (intersection > 0.0){ // 只有真的相交才画。
		float wind = 2.5 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 随风移动的时间量。
		vec2 windDirection = vec2(-wind, wind * 0.2); // 主风向与一点横向分量。
		float VdotL = dot(worldDir, worldShadowVector) * 0.5 + 0.5; // 视线与光方向夹角余弦映射到零到一。
		vec3 centerPosition = worldDir * intersection; // 交点相对相机的方向。
		vec2 samplePosition = centerPosition.xz + cameraPosition.xz; // 交点的地表水平坐标。
		cloudTransmittance = min(GetPlanarCloudsDensity(samplePosition, windDirection) * cloudTransmittance * 40.0, 0.9); // 平面云的不透明度。
		#ifdef OMNI_VOLUMETRIC_CLOUDS // 与体积云叠加时按雨天压薄平面云。
			cloudTransmittance *= 1.0 - wetness; // 雨天让平面云让位给体积云。
		#endif
		if (cloudTransmittance > 1e-5){ // 只有云确实可见才算光照。
			float stepLength = mix(150.0, 0.0, worldShadowVector.z); // 沿光方向的起始步长，随光方向变化。
			samplePosition += stepLength * dither * worldShadowVector.xy; // 起点加抖动，减少条带。
			float lightingDepth = 0.0; // 沿光方向累积的遮挡密度。
			for (int i = 0; i < 4; i++, samplePosition += worldShadowVector.xy * stepLength, stepLength *= 1.5){ // 四步，步长逐步放大。
				lightingDepth += GetPlanarCloudsLightingDensity(samplePosition, windDirection) * stepLength; // 累加遮挡。
			}
			float sunlightEnergy = 1.0 / (lightingDepth + 1.0); // 遮挡越少阳光越强。
			float powderFactor = exp2(-cloudTransmittance * (worldShadowVector.y * 5.0 + 0.5)); // 粉末效应：正对光时云边发亮。
			sunlightEnergy *= MiePhaseFunction(powderFactor * 0.8, VdotL * 0.5 + 0.5); // 乘米氏相位。
			sunlightEnergy *= MiePhaseFunction(0.9, VdotL) * 0.4 + 1.0; // 再加强前向散射。
			vec3 cloudColor = colorShadowlight * (sunlightEnergy * 6.0); // 乘直射光色。
			float skylightEnergy = exp2(-cloudTransmittance * 0.15); // 环境光透过。
			cloudColor += colorSkylight * (skylightEnergy * 0.2); // 加上天光色。
			cloudTransmittance *= exp2(-(length(centerPosition) + 2e3) * 4e-5); // 远处平面云也按距离压薄。
			vec3 atmoPoint = camera + centerPosition * 0.001; // 交点附近一点。
			vec3 transmittance; // 大气透过率输出。
			vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, -worldSunVector, transmittance); // 这段空气的散射。
			color *= (1.0 - cloudTransmittance); // 天空被云挡掉的部分。
			color += (cloudColor * transmittance + aerialPerspective) * cloudTransmittance; // 加上云颜色与空气散射。
		}
	}
}
#endif // 体积云与平面云结束。
// --- 云影三次采样：与共用数学里的同名函数返回类型和参数都不同，按合同留在云影这里一份 ---
// 读一张二维纹理的十六像素三次模糊，返回第一个通道，`texSize` 是纹理尺寸。
float CloudBicubicBlurTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	vec2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
	coord = coord * texSize - 0.5; // 换成以像素为单位的坐标。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个权重。
	vec4 w1; // 两个方向的后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= texPixelSize.xxyy; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(texSampler, c.yw, 0.0).x, textureLod(texSampler, c.xw, 0.0).x, m.x),
			   mix(textureLod(texSampler, c.yz, 0.0).x, textureLod(texSampler, c.xz, 0.0).x, m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊，取红通道。
}
// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
// 调用前提：全局量 `worldShadowVector` 已声明，云影贴在二号画面右上角。
float CloudShadowFromTex(vec3 worldPos, vec3 shadowLightVector){
	#ifdef NO_COMPOSITE_VS // 没有合成顶点阶段时退回按阴影相机方向投影。
		vec3 worldShadowVector = shadowModelViewInverse[2].xyz; // 用阴影相机视线方向作为光方向。
	#endif
	vec2 coord = worldPos.xz - shadowLightVector.xz * ((worldPos.y + cameraPosition.y) / shadowLightVector.y); // 沿光方向投到云影贴图平面。
	coord = coord * (1.0 / OMNI_CLOUD_SHADOW_RANGE) + 0.5; // 换成零到一的贴图坐标。
	float cloudShadow = 1.0 - wetness; // 雨天默认的云影底值。
	if (saturate(coord) == coord){ // 只有落在贴图范围内才采样。
		float shadowTexSize = floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 云影贴图实际边长。
		vec2 shadowTexel = screenSize - coord * shadowTexSize; // 贴图贴在画面右上角，坐标要翻转。
		vec2 fade = saturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
		cloudShadow = mix(cloudShadow, CloudBicubicBlurTexture(colortex2, shadowTexel * pixelSize, screenSize), fade.x * fade.y); // 三次采样并淡出。
	}
	#ifdef OMNI_CLOUD_SHADOW_FADE // 打开淡出时，太阳越贴地云影越淡。
		float fadeAngle = smoothstep(0.06, 0.18, abs(shadowLightVector.y)); // 光方向越平越淡。
		cloudShadow = mix(1.0 - wetness, cloudShadow, fadeAngle * fadeAngle); // 按淡出权重混合。
	#endif
	return ((OMNI_RAIN_SHADOW - 1.0) * wetness + 1.0) * cloudShadow + (wetness - OMNI_RAIN_SHADOW * wetness); // 晴天与雨天两档之间插值。
}
// 全局云影：给整个场景用的一个粗粒度云影值，来自二号画面顶行的统计像素。
float GetSmoothCloudShadow(){
	#if defined OMNI_VOLUMETRIC_CLOUDS && defined OMNI_CLOUD_SHADOW // 有体积云和云影时读统计像素。
		float globalCloudShadow = mix(texelFetch(colortex2, ivec2(40, screenSize.y - 1.0), 0).a, 1.0, 0.03 - wetness * 0.015); // 顶行四十号像素存全局云影。
	#else // 否则用纯天气估一个值。
		float globalCloudShadow = 1.0 - wetness * (OMNI_RAIN_SHADOW * 0.985); // 雨天按雨天阴影压暗。
	#endif
	return globalCloudShadow; // 返回全局云影。
}
// 云影三次采样：原程序横纵两个程序各写一份只差采样轴，按合同合并成一个函数，名字加云影前缀。
// 调用前提：`colortex2` 与 `screenSize` 已声明；`axis` 取值横向 `(1,0)` 或纵向 `(0,1)`。
vec4 CloudShadowAxialBlur(ivec2 texelCoord, ivec2 axis){
	ivec4 shadowTexBorder = ivec4(screenSize - floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)), screenSize - 1.0); // 云影贴图的边界，采样要夹在里面。
	vec4 blur = vec4(0.0); // 模糊结果。
	ivec2 sampleCoord = clamp(texelCoord - 3 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第三个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.054543; // 按高斯权重累加。
	sampleCoord = clamp(texelCoord - 2 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第二个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.099384; // 累加。
	sampleCoord = clamp(texelCoord - 1 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第一个负向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.181090; // 累加。
	vec4 data2 = texelFetch(colortex2, texelCoord, 0); // 中心样本。
	blur.r += data2.r * 0.329966; // 中心权重最大。
	blur.gba += data2.gba; // 其余通道原样带过。
	sampleCoord = clamp(texelCoord + 1 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第一个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.181090; // 累加。
	sampleCoord = clamp(texelCoord + 2 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第二个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.099384; // 累加。
	sampleCoord = clamp(texelCoord + 3 * axis, shadowTexBorder.xy, shadowTexBorder.zw); // 第三个正向样本。
	blur.r += texelFetch(colortex2, sampleCoord, 0).r * 0.054543; // 累加。
	return blur; // 返回模糊后的云影贴图。
}
#endif // 文件守卫结束。
