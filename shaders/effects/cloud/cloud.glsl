/*
云：云效果入口，集中定义平面云、体积云、附加云层与云影的全部选项，并按依赖顺序引入同目录算法文件。
调用位置：延迟三号画天空像素与天空盒时调用 `NubisCumulus`、`PlanarClouds`、`CalculateStars`；
    三号右上角写云影贴图时调用 `CloudShadowTex`；延迟四号与五号对云影贴图做横向、纵向模糊时调用 `CloudShadowAxialBlur`；
    合成阶段算地表直射光与天光被云遮挡多少时调用 `CloudShadowFromTex`、`GetSmoothCloudShadow`；
    体积云渲染分辨率大于一时（低分辨率模式）额外用到延迟七号：它在更低的分辨率上只算基础体积云，结果存进十号画面；
    延迟八号再把十号画面放大贴回一号天空，并补上平面云与附加层。
可复制示例：
    `NubisCumulus(compositeColor, worldDir, cloudAltitude, windDirection, camera, noise, cloudTransmittance);`
    `PlanarClouds(compositeColor, worldDir, camera, dither, cloudTransmittance);`
    `float shadow = CloudShadowFromTex(worldPos, worldShadowVector);`
    `vec4 cloudImage = omniCloudImage(worldDir, camera, noise, cloudAltitude, windDirection, intersectsGround, worldDir.y < 0.0);`
设计原因与取舍：
    本文件是云效果入口，选项只在这里定义一次，算法体按内容拆到同目录文件，引入顺序与拆分前一致：
    体积云密度、光照与步进核心 `effects/cloud/volumetric.glsl`；平面云 `effects/cloud/planar.glsl`；云影贴图与模糊 `effects/cloud/shadow.glsl`。
    体积云与平面云都能出图，各自带开关，默认都开；两者共用同一份云量、云高、云厚、云色等选项，切换或叠加时色调不突变。
    云影不是另外建模，而是沿光线穿过同一份三维云密度采样，所以天上的云和地上的影对得上。
    调用前提（iterationT 原样保留）：调用方必须先声明 `colortex2`、`worldShadowVector`、`worldSunVector`、
    `worldMoonVector`、`colorShadowlight`、`colorSkylight` 等全局量；延迟阶段四号、六号画面由程序自己
    打开三维云噪声，本文件把同一判据收成一个宏交给体积云与平面云。
*/
#ifndef OMNI_CLOUD_INCLUDED
#define OMNI_CLOUD_INCLUDED
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"平面云","en_us":"Planar Clouds"},"description":{"zh_cn":"把云画在一层固定高度的平面上，便宜且连续。","en_us":"Draws the clouds on one fixed-altitude sheet; cheap and continuous."}}
#define OMNI_PLANAR_CLOUDS 1 // [0 1]
// @option {"label":{"zh_cn":"平面云量","en_us":"Planar Cloud Coverage"},"description":{"zh_cn":"平面云铺满天空的程度。","en_us":"How much the planar clouds cover the sky."},"slider":true}
#define OMNI_PLANAR_COVERAGE 0.5 // [0.3 0.32 0.34 0.36 0.38 0.4 0.42 0.44 0.46 0.48 0.5 0.52 0.54 0.56 0.58 0.6 0.62 0.64 0.66 0.68 0.7 0.72 0.74 0.76 0.78 0.8 0.82 0.84 0.86 0.88 0.9]
// @option {"label":{"zh_cn":"平面云噪声尺度","en_us":"Planar Cloud Noise Scale"},"description":{"zh_cn":"平面云块的大小，越大云块越小越碎。","en_us":"Planar cloud block size; larger is smaller and more broken."},"slider":true}
#define OMNI_PLANAR_NOISE_SCALE 0.025 // [0.01 0.015 0.02 0.025 0.03 0.035 0.04 0.045 0.5]
// @option {"label":{"zh_cn":"平面云高度","en_us":"Planar Cloud Altitude"},"description":{"zh_cn":"平面云挂的高度，单位方块。","en_us":"Altitude of the planar clouds in blocks."}}
#define OMNI_PLANAR_ALTITUDE 6000.0 // [2000.0 2500.0 3000.0 3500.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0]
// @option {"label":{"zh_cn":"云层","en_us":"Volumetric Clouds"},"description":{"zh_cn":"沿视线在云层里步进得到厚实的云，代价较高。","en_us":"Marches through the cloud layer for thick clouds; costlier."}}
#define OMNI_VOLUMETRIC_CLOUDS
// @option {"label":{"zh_cn":"精细度","en_us":"Cloud Quality"},"description":{"zh_cn":"体积云沿视线的步数倍率，越大越细也越慢。","en_us":"Multiplier on the volumetric cloud steps; higher is finer and slower."},"slider":true}
#define OMNI_CLOUD_QUALITY 1.2 // [0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0 2.5 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"云层采样数","en_us":"Cloud Samples"},"description":{"zh_cn":"体积云沿视线采样的次数上限（朝天看时略少），越大越细也越慢；与上面的精细度倍率相乘。","en_us":"Upper bound on volumetric cloud view samples (slightly fewer looking up); higher is finer and slower; multiplied by the quality factor above."},"slider":true}
#define OMNI_CLOUD_SAMPLES 20 // [8 10 12 16 20 24 28 32 40 48 56 64 80 96 128]
// @option {"label":{"zh_cn":"云层渲染分辨率","en_us":"Volumetric Cloud Render Resolution"},"description":{"zh_cn":"体积云单独在更低的分辨率上步进，再放大贴回天空；一为原分辨率（默认，画面与从前一致），二或四更省性能但云边缘更软。","en_us":"Steps the volumetric clouds at a lower resolution, then upsamples onto the sky; one is the original resolution (default, unchanged picture), two or four is cheaper but softer."},"values":{"1":{"zh_cn":"原分辨率","en_us":"Full"},"2":{"zh_cn":"一半","en_us":"Half"},"4":{"zh_cn":"四分之一","en_us":"Quarter"}}}
#define OMNI_CLOUD_RENDER_SCALE 1 // [1 2 4]
// 体积云低分辨率模式：渲染分辨率大于一时打开。低分辨率模式把体积云搬到独立阶段，
// 主天空不再内联计算体积云；原分辨率下整段不生效，默认画面与行为完全不变。
#if OMNI_CLOUD_RENDER_SCALE > 1
#define OMNI_CLOUD_LOWRES 1
#endif
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
// @option {"label":{"zh_cn":"细节噪声强度","en_us":"Cloud Detailed Noise Strength"},"description":{"zh_cn":"云边缘细节噪声的强度，越大碎边越明显。","en_us":"Strength of the fine noise on cloud edges; higher is more broken."},"slider":true}
#define OMNI_CLOUD_DETAILED_NOISE_STRENGTH 1.0 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.5 3.0 3.5 4.0]
// @option {"label":{"zh_cn":"基础噪声尺度","en_us":"Cloud Base Noise Scale"},"description":{"zh_cn":"云形状基础噪声的空间频率，越大云块越小。","en_us":"Spatial frequency of the base cloud shape; higher is smaller blocks."},"slider":true}
#define OMNI_CLOUD_BASE_NOISE_SCALE 0.0007 // [0.0001 0.00015 0.0002 0.00025 0.0003 0.00035 0.0004 0.00045 0.0005 0.00055 0.0006 0.00065 0.0007 0.00075 0.0008 0.00085 0.0009 0.00095 0.001 0.0011 0.0012 0.0014 0.0015 0.0016 0.0017 0.0018 0.0019 0.002]
// @option {"label":{"zh_cn":"细节噪声尺度","en_us":"Cloud Detailed Noise Scale"},"description":{"zh_cn":"云边缘细节噪声的空间频率。","en_us":"Spatial frequency of the fine cloud-edge noise."},"slider":true}
#define OMNI_CLOUD_DETAILED_NOISE_SCALE 0.007 // [0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01 0.011 0.012 0.013 0.014 0.015 0.016 0.017 0.018 0.019 0.02]
// @option {"label":{"zh_cn":"底亮度","en_us":"Cloud Bottom Brightness"},"description":{"zh_cn":"云背光面保留的底光，越大背光云越不黑。","en_us":"Base light kept on shaded cloud sides; higher is less black."},"slider":true}
#define OMNI_CLOUD_BOTTOM_BRIGHTNESS 0.15 // [0.01 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"外散射指数","en_us":"Cloud Outscatter Factor"},"description":{"zh_cn":"阳光透过云的集中程度，越大越集中在太阳方向。","en_us":"How tightly light spreads through the clouds; higher concentrates it near the sun."},"slider":true}
#define OMNI_CLOUD_OUTSCATTER_FACTOR 1.3 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"量噪声偏移","en_us":"Cloud Coverage Noise Offset"},"description":{"zh_cn":"云量在噪声里的偏移，改变云块的整体分布。","en_us":"Offsets the coverage noise, changing the overall cloud layout."},"slider":true}
#define OMNI_CLOUD_COVERAGE_NOISE_OFFSET 0.68 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label":{"zh_cn":"远距淡出","en_us":"Cloud Fade"},"description":{"zh_cn":"远处云逐渐融进天空，避免出现硬边。","en_us":"Fades distant clouds into the sky to avoid hard edges."}}
#define OMNI_CLOUD_FADE 1 // [0 1]
// @option {"label":{"zh_cn":"速","en_us":"Cloud Speed"},"description":{"zh_cn":"云飘动的快慢。","en_us":"How fast the clouds drift."},"slider":true}
#define OMNI_CLOUD_SPEED 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 5.0 7.5 10.0 15.0 20.0 30.0 40.0 50.0 75.0 100.0]
// @option {"label":{"zh_cn":"时间偏移","en_us":"Cloud Time Offset"},"description":{"zh_cn":"给云和平面云的飘动时间加一个固定偏移，用来错开云的位置；不改变飘动速度。","en_us":"Offsets the cloud drift time by a fixed amount to shift their position; does not change speed."},"slider":true}
#define OMNI_CLOUD_TIME_OFFSET 0 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200 205 210 215 220 225 230 235 240 245 250 255 260 265 270 275 280 285 290 295 300 305 310 315 320 325 330 335 340 345 350 355]
// @option {"label":{"zh_cn":"影","en_us":"Cloud Shadow"},"description":{"zh_cn":"云在地上投下阴影。","en_us":"Clouds cast shadows on the ground."}}
#define OMNI_CLOUD_SHADOW
// @option {"label":{"zh_cn":"影淡出","en_us":"Cloud Shadow Fade"},"description":{"zh_cn":"太阳贴近地平线时让云影变淡，避免阴影拉得过长。","en_us":"Fades cloud shadows as the sun nears the horizon."}}
#define OMNI_CLOUD_SHADOW_FADE 1 // [0 1]
// @option {"label":{"zh_cn":"影范围","en_us":"Cloud Shadow Range"},"description":{"zh_cn":"云影贴图覆盖的地表范围，单位方块。","en_us":"Ground area covered by the cloud shadow texture, in blocks."}}
#define OMNI_CLOUD_SHADOW_RANGE 4096.0 // [2048.0 3072.0 4096.0 6144.0 8192.0 12288.0 16384.0]
// @option {"label":{"zh_cn":"影贴图尺寸","en_us":"Cloud Shadow Texture Size"},"description":{"zh_cn":"云影贴图的边长上限，越大云影越细。","en_us":"Side length cap of the cloud shadow texture; higher is finer."},"slider":true}
#define OMNI_CLOUD_SHADOWTEX_SIZE 256.0 // [128.0 192.0 256.0 384.0 512.0 768.0 1024.0]
// @option {"label":{"zh_cn":"雨天阴影","en_us":"Rain Shadow"},"description":{"zh_cn":"阴雨天直射光被云挡掉多少，越大雨天越暗。","en_us":"How much rain clouds block direct light; higher is darker."},"slider":true}
#define OMNI_RAIN_SHADOW 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// 下面是合并 Eclipse 多层云新增的附加层选项：卷云、高层云与积雨云。附加层默认全部关闭，
// 关闭时下面的采样与光照整段不参与编译，默认画面与只有基础云时完全一致。
// @option {"label":{"zh_cn":"卷云层","en_us":"Cirrus Layer"},"description":{"zh_cn":"在最高处加一层薄卷云；附加层默认关闭，关闭时不产生任何采样。","en_us":"Adds a thin cirrus sheet at the top; off by default and adds no sampling when off."}}
#define OMNI_CLOUD_CIRRUS 0 // [0 1]
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
#define OMNI_CLOUD_ALTOSTRATUS 0 // [0 1]
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
// @option {"label":{"zh_cn":"积雨云层","en_us":"Cumulonimbus Layer"},"description":{"zh_cn":"加一层高耸的雷暴积雨云，照 Eclipse 分三档：关为不出现；雷暴时或之后为只在有雷暴时出现、雷暴过去后逐渐消退；始终为全天存在。中档读加载器的雷暴强度，Eclipse 的“雷暴后延迟消退”用同一强度近似，没有跨帧保持量。","en_us":"Adds a towering cumulonimbus, in Eclipse's three modes: Off; During/After a thunderstorm (appears with a storm, fades once it passes); or Always on. The middle mode reads the loader's thunder strength; Eclipse's lingering fade-out is approximated with the same input since there is no cross-frame state."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"雷暴时或之后","en_us":"During/After Thunderstorm"},"2":{"zh_cn":"始终","en_us":"Always"}}}
#define OMNI_CLOUD_CUMULONIMBUS 0 // [0 1 2]
// @option {"label":{"zh_cn":"积雨云高度","en_us":"Cumulonimbus Altitude"},"description":{"zh_cn":"积雨云底部高度，单位方块；取值照 Eclipse `lib/volumetricClouds.glsl:1158` 的积雨云底部六百格。","en_us":"Base altitude of the cumulonimbus in blocks; Eclipse's base of 600 (`lib/volumetricClouds.glsl:1158`)."}}
#define OMNI_CLOUD_CUMULONIMBUS_ALTITUDE 600.0 // [300.0 400.0 500.0 600.0 800.0 1000.0 1500.0 2000.0]
// @option {"label":{"zh_cn":"积雨云厚度","en_us":"Cumulonimbus Thickness"},"description":{"zh_cn":"积雨云层厚度，单位方块；取值照 Eclipse `lib/volumetricClouds.glsl:1157` 的积雨云高度四千格。","en_us":"Thickness of the cumulonimbus in blocks; Eclipse's cumulonimbus height of 4000 (`lib/volumetricClouds.glsl:1157`)."}}
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
#define OMNI_CUMULONIMBUS_LIGHTNING 0 // [0 1]
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
// 云密度只在能读三维云噪声的阶段参与编译：延迟三号画天空、七号算低分辨率云、八号把云贴回天空。
// 同一个判据收成一个宏，交给体积云与平面云，其它程序整段跳过，不会把三维噪声贴图当成二维采样。
#if defined COLORTEX_CLOUDNOISE && (defined OMNI_DEFERRED3_PASS || defined OMNI_DEFERRED7_PASS || defined OMNI_DEFERRED8_PASS)
#define OMNI_CLOUD_DENSITY_PASS 1 // 三维云噪声可用，开启体积云与平面云的编译。
#endif
// 体积云密度、光照、步进核心、附加云层与低分辨率云总图。
#include "/effects/cloud/volumetric.glsl"
// 平面云：固定高度一层平面上的云。
#include "/effects/cloud/planar.glsl"
// 云影贴图与模糊：不依赖云密度，任何引入云的程序都能编译。
#include "/effects/cloud/shadow.glsl"
#endif // 文件守卫结束。
