/*
效果文件 `effects/sky/sky.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/sky/sky.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_SKY_SKY_INCLUDED
#define OMNI_EFFECT_SKY_SKY_INCLUDED
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label":{"zh_cn":"地平线","en_us":"Sky Horizon"},"description":{"zh_cn":"打开后地平线方向也算被行星表面挡住的大气，日出时地平线一带更真实。","en_us":"Also shades the horizon band below the eye as ground-lit atmosphere."}}
//#define OMNI_ATMO_HORIZON
// @option {"label":{"zh_cn":"反射天空盒地平线","en_us":"Skybox Horizon"},"description":{"zh_cn":"反射用的天空盒是否同样处理地平线方向。","en_us":"Whether the reflection skybox shades the horizon the same way."}}
#define OMNI_ATMO_REFLECTION_HORIZON
// @option {"label":{"zh_cn":"月亮纹理平滑","en_us":"Moon Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读月亮贴图，低分辨率资源包会显得更糊。","en_us":"Reads the moon texture with bilinear filtering; low-resolution packs look softer."}}
#define OMNI_BILINEAR_MOON_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"盒纹理平滑","en_us":"Skybox Texture Smoothing"},"description":{"zh_cn":"用双线性过滤读天空盒贴图，低分辨率资源包会显得更糊。","en_us":"Reads the skybox texture with bilinear filtering; low-resolution packs look softer."}}
#define OMNI_BILINEAR_SKYBOX_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"月亮纹理","en_us":"Moon Texture"},"description":{"zh_cn":"用资源包的月亮贴图代替内置圆盘。","en_us":"Uses the resource pack moon texture instead of the built-in disc."}}
#define OMNI_MOON_TEXTURE
// @option {"label":{"zh_cn":"夜间亮度比值","en_us":"Night Brightness"},"description":{"zh_cn":"夜间环境光相对白天环境光的比值，越大夜里越亮。","en_us":"Night ambient light relative to day; larger makes nights brighter."},"slider":true}
#define OMNI_NIGHT_BRIGHTNESS 0.0003 // [0.0 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 1.0]
// @option {"label":{"zh_cn":"盒纹理","en_us":"Skybox Texture"},"description":{"zh_cn":"用资源包的天空盒贴图叠在天空上。","en_us":"Overlays the resource pack skybox texture on the sky."}}
#define OMNI_SKYBOX_TEXTURE 0 // [0 1]
// @option {"label":{"zh_cn":"资源包天空","en_us":"Resource Pack Sky"},"description":{"zh_cn":"用资源包画好的整片天空（自定义天空层、日月与星空）当天空底色，替换光影的程序化大气；只作用在主视图的天空，水面反射的天空盒仍用程序化大气。默认关闭，关闭时画面与从前一致。","en_us":"Uses the resource pack's painted sky (custom sky layers, sun, moon and stars) as the sky base instead of the procedural atmosphere; only the main view is affected, reflections keep the procedural skybox. Off by default."}}
#define OMNI_RESOURCEPACK_SKY 0 // [0 1]
// @option {"label":{"zh_cn":"资源包天空亮度","en_us":"Resource Pack Sky Brightness"},"description":{"zh_cn":"资源包天空底色的亮度倍率，用来和光影本身的大气亮度对齐；只在开启资源包天空时生效，具体数值要在游戏里对照调整。","en_us":"Brightness multiplier for the resource pack sky base, to match the shader's own atmosphere; only used with Resource Pack Sky. The exact value needs in-game tuning."},"slider":true}
#define OMNI_RESOURCEPACK_SKY_BRIGHTNESS 1.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"反射天空盒分辨率","en_us":"Skybox Resolution"},"description":{"zh_cn":"反射里天空贴图的边长，越高越清晰也越费性能。","en_us":"Side length of the reflected sky image; higher is sharper and costlier."},"values":{"32.0":{"zh_cn":"极低","en_us":"Lowest"},"64.0":{"zh_cn":"低","en_us":"Low"},"128.0":{"zh_cn":"中","en_us":"Medium"},"256.0":{"zh_cn":"高","en_us":"High"},"512.0":{"zh_cn":"极高","en_us":"Very high"}}}
#define OMNI_SKY_IMAGE_RESOLUTION 64.0 // [32.0 48.0 64.0 96.0 128.0 192.0 256.0 384.0 512.0]
// @option {"label":{"zh_cn":"纹理亮度","en_us":"Texture Brightness"},"description":{"zh_cn":"原版星星、月亮贴图和天空盒的亮度倍率。","en_us":"Brightness multiplier for vanilla stars, the moon texture and the skybox."},"slider":true}
#define OMNI_SKY_TEXTURE_BRIGHTNESS 1.0 // [0.0 0.05 0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"星星类型","en_us":"Star Type"},"description":{"zh_cn":"关为没有星星，点状为按方向生成的星点，原版为资源包星空贴图。","en_us":"Off has no stars, Dots draws procedural points, Vanilla uses the pack sky texture."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"点状","en_us":"Dots"},"2":{"zh_cn":"原版","en_us":"Vanilla"}}}
#define OMNI_STAR_TYPE 1 // [0 1 2]
// @option {"label":{"zh_cn":"星星数量","en_us":"Stars Amount"},"description":{"zh_cn":"点状星空的星点疏密倍率，默认一倍与现在一致；只在星星类型为点状时生效。","en_us":"Density multiplier for the Dots star field; default 1 matches the current look; only used with the Dots star type."},"slider":true}
#define OMNI_STARS_AMOUNT 1.0 // [0.5 0.75 1.0 1.25 1.5 1.75 2.0]
// @option {"label":{"zh_cn":"星星亮度","en_us":"Stars Brightness"},"description":{"zh_cn":"点状星空的星点整体亮度倍率，默认一倍与现在一致；只在星星类型为点状时生效。","en_us":"Overall brightness multiplier for the Dots star field; default 1 matches the current look; only used with the Dots star type."},"slider":true}
#define OMNI_STARS_BRIGHTNESS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 3.0 4.0 5.0]
// @option {"label":{"zh_cn":"彩色星点","en_us":"Colored Stars"},"description":{"zh_cn":"改用带星温的彩色星场（Eclipse 的 `starbox`）；关闭时是 Eclipse 默认的白色星点，只在星星类型为点状时生效。","en_us":"Uses the star-temperature colored field (Eclipse `starbox`); off keeps Eclipse's default white stars; only used with the Dots star type."}}
#define OMNI_STARS_COLORED 0 // [0 1]
// @option {"label":{"zh_cn":"日月倾角","en_us":"Sun Path Rotation"},"description":{"zh_cn":"日月运动轨迹相对原版轨迹的倾角，Iris 直接读取该原生常量。","en_us":"Tilt of the sun and moon path versus vanilla; Iris reads this native constant."}}
const float sunPathRotation = -30.0; // [-90.0 -89.0 -88.0 -87.0 -86.0 -85.0 -84.0 -83.0 -82.0 -81.0 -80.0 -79.0 -78.0 -77.0 -76.0 -75.0 -74.0 -73.0 -72.0 -71.0 -70.0 -69.0 -68.0 -67.0 -66.0 -65.0 -64.0 -63.0 -62.0 -61.0 -60.0 -59.0 -58.0 -57.0 -56.0 -55.0 -54.0 -53.0 -52.0 -51.0 -50.0 -49.0 -48.0 -47.0 -46.0 -45.0 -44.0 -43.0 -42.0 -41.0 -40.0 -39.0 -38.0 -37.0 -36.0 -35.0 -34.0 -33.0 -32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0]
// --- 月亮轨道与月食：来源 Eclipse `lib/settings.glsl:400-456`、`dimensions/begin.csh:73-95`、`lib/ROBOBO_sky.glsl:130-133` ---
// 这一组选项默认不改变画面：自定义轨道、真实月亮、月相亮度都默认关闭，月食默认开启但默认轨道下日月永不接近。
// @option {"label":{"zh_cn":"自定义月亮轨道","en_us":"Custom Moon Rotation"},"description":{"zh_cn":"让月亮按自己的轨道运行，不再永远待在太阳对面，才可能出现月相与月食；关闭时与现在完全一样。","en_us":"Gives the moon its own orbit instead of always opposing the sun, allowing phases and eclipses; off keeps the current look."}}
//#define OMNI_CUSTOM_MOON_ROTATION
// @option {"label":{"zh_cn":"月亮轨道纬度","en_us":"Moon Orbit Latitude"},"description":{"zh_cn":"观测点纬度，决定月亮升起的高度；只在自定义月亮轨道开启时生效。","en_us":"Observer latitude, setting how high the moon rises; only used with custom moon rotation."},"slider":true}
#define OMNI_MOON_LATITUDE 40.0 // [-89.0 -88.0 -87.0 -86.0 -85.0 -84.0 -83.0 -82.0 -81.0 -80.0 -79.0 -78.0 -77.0 -76.0 -75.0 -74.0 -73.0 -72.0 -71.0 -70.0 -69.0 -68.0 -67.0 -66.0 -65.0 -64.0 -63.0 -62.0 -61.0 -60.0 -59.0 -58.0 -57.0 -56.0 -55.0 -54.0 -53.0 -52.0 -51.0 -50.0 -49.0 -48.0 -47.0 -46.0 -45.0 -44.0 -43.0 -42.0 -41.0 -40.0 -39.0 -38.0 -37.0 -36.0 -35.0 -34.0 -33.0 -32.0 -31.0 -30.0 -29.0 -28.0 -27.0 -26.0 -25.0 -24.0 -23.0 -22.0 -21.0 -20.0 -19.0 -18.0 -17.0 -16.0 -15.0 -14.0 -13.0 -12.0 -11.0 -10.0 -9.0 -8.0 -7.0 -6.0 -5.0 -4.0 -3.0 -2.0 -1.0 0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0]
// @option {"label":{"zh_cn":"月亮时间偏移","en_us":"Moon Time Offset"},"description":{"zh_cn":"月亮轨道相对世界时间的偏移，用来挑一个起始相位；只在自定义月亮轨道开启时生效。","en_us":"Offset of the moon orbit in world time to pick a starting phase; only used with custom moon rotation."},"slider":true}
#define OMNI_MOON_TIME_OFFSET 1000.0 // [0.0 500.0 1000.0 1500.0 2000.0 2500.0 3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 6000.0 6500.0 7000.0 7500.0 8000.0 8500.0 9000.0 9500.0 10000.0 10500.0 11000.0 11500.0 12000.0 12500.0 13000.0 13500.0 14000.0 14500.0 15000.0 15500.0 16000.0 16500.0 17000.0 17500.0 18000.0 18500.0 19000.0 19500.0 20000.0 20500.0 21000.0 21500.0 22000.0 22500.0 23000.0 23500.0]
// @option {"label":{"zh_cn":"月亮轨道平滑","en_us":"Smooth Moon Rotation"},"description":{"zh_cn":"用平滑后的世界时间驱动月亮，移动不跳格；只在自定义月亮轨道开启时生效。","en_us":"Drives the moon with smoothed world time so it moves without stepping; only used with custom moon rotation."}}
#define OMNI_SMOOTH_MOON_ROTATION
// @option {"label":{"zh_cn":"月相亮度","en_us":"Moonphase Moonlight"},"description":{"zh_cn":"按月亮与太阳的夹角算月相，把月光与月盘按被照亮比例压暗；默认关闭。","en_us":"Scales moonlight and the moon disc by the illuminated fraction from the sun-moon angle; off by default."}}
//#define OMNI_MOONPHASE_BASED_MOONLIGHT
// @option {"label":{"zh_cn":"月亮亮度基准","en_us":"Moon Illuminance"},"description":{"zh_cn":"真实月亮模式下月盘的亮度基准；只在真实月亮开启时生效。","en_us":"Brightness reference of the moon disc in realistic moon mode; only used with Realistic Moon."},"slider":true}
#define OMNI_MOON_ILLUMINANCE 600.0 // [0.0 10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0 100.0 150.0 200.0 300.0 400.0 500.0 600.0 700.0 800.0 900.0 1000.0 2000.0 3000.0 4000.0 5000.0 6000.0 7000.0 8000.0 9000.0 10000.0 11000.0 12000.0 13000.0 14000.0 15000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 150000.0 200000.0 250000.0 300000.0 400000.0 500000.0]
// @option {"label":{"zh_cn":"月亮色温","en_us":"Moon Temperature"},"description":{"zh_cn":"真实月亮模式下月盘的色温，越低越暖；只在真实月亮开启时生效。","en_us":"Color temperature of the moon disc in realistic moon mode; lower is warmer."},"slider":true}
#define OMNI_MOON_TEMP 8000.0 // [1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2100.0 2200.0 2300.0 2400.0 2500.0 2600.0 2700.0 2800.0 2900.0 3000.0 3100.0 3200.0 3300.0 3400.0 3500.0 3600.0 3700.0 3800.0 3900.0 4000.0 4100.0 4200.0 4300.0 4400.0 4500.0 4600.0 4700.0 4800.0 4900.0 5000.0 5100.0 5200.0 5300.0 5400.0 5600.0 5700.0 5800.0 5900.0 6000.0 6100.0 6200.0 6300.0 6400.0 6500.0 6600.0 6700.0 6800.0 6900.0 7000.0 7100.0 7200.0 7300.0 7400.0 7500.0 7600.0 7700.0 7800.0 7900.0 8000.0 8100.0 8200.0 8300.0 8400.0 8500.0 8600.0 8700.0 8800.0 8900.0 9000.0 9100.0 9200.0 9300.0 9400.0 9500.0 9600.0 9700.0 9800.0 9900.0 10000.0 15000.0 20000.0 25000.0 50000.0]
// @option {"label":{"zh_cn":"真实月亮","en_us":"Realistic Moon"},"description":{"zh_cn":"用真实月亮的色温与尺寸画月盘；Eclipse 自带的月亮贴图不在本项目内，没有贴图时退回现有的程序圆盘。","en_us":"Draws the moon with realistic temperature and size; the Eclipse moon texture is not bundled, so it falls back to the built-in disc."}}
//#define OMNI_REALMOON
// @option {"label":{"zh_cn":"月面法线","en_us":"Moon Normals"},"description":{"zh_cn":"用月面法线贴图做起伏明暗；本项目没有该贴图，缺少时退回现有的程序圆盘。","en_us":"Adds relief shading from a moon normal map; the texture is not bundled, so it falls back."}}
//#define OMNI_MOON_NORMALS
// @option {"label":{"zh_cn":"月亮尺寸","en_us":"Moon Size"},"description":{"zh_cn":"真实月亮模式下月盘的角直径档位，越大月亮越大；只在真实月亮开启时生效。","en_us":"Angular size of the moon disc in realistic moon mode; larger means a bigger moon."},"slider":true}
#define OMNI_MOON_SIZE_SETTING 4.5 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0]
// @option {"label":{"zh_cn":"月食变暗","en_us":"Eclipse Darkening"},"description":{"zh_cn":"日月方向对齐时把天空压暗；默认开启，但默认轨道下日月永不接近，所以不影响默认画面。","en_us":"Darkens the sky when the sun and moon align; on by default but never triggers with the default orbit."}}
#define OMNI_ECLIPSE
// @option {"label":{"zh_cn":"月食变暗强度","en_us":"Eclipse Strength"},"description":{"zh_cn":"日月对齐时压暗的程度，零为不压暗；只在月食变暗开启时生效。","en_us":"How much the sky darkens on alignment; zero disables it; only used when Eclipse Darkening is on."},"slider":true}
#define OMNI_ECLIPSE_DARKENING 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"月亮颜色-红","en_us":"Moon colour - R"},"description":{"zh_cn":"月亮圆盘颜色的红色倍率，一为不变；补上 Eclipse 的 moonColorR/G/B，默认全一不改画面。","en_us":"Red multiplier of the moon disc colour; one is unchanged. Ports Eclipse moonColorR/G/B; defaults keep the current look."},"slider":true}
#define OMNI_MOON_COLOR_R 1.0 // [0.0 0.2 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"月亮颜色-绿","en_us":"Moon colour - G"},"description":{"zh_cn":"月亮圆盘颜色的绿色倍率，一为不变；补上 Eclipse 的 moonColorR/G/B，默认全一不改画面。","en_us":"Green multiplier of the moon disc colour; one is unchanged. Ports Eclipse moonColorR/G/B; defaults keep the current look."},"slider":true}
#define OMNI_MOON_COLOR_G 1.0 // [0.0 0.2 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.8 2.0]
// @option {"label":{"zh_cn":"月亮颜色-蓝","en_us":"Moon colour - B"},"description":{"zh_cn":"月亮圆盘颜色的蓝色倍率，一为不变；补上 Eclipse 的 moonColorR/G/B，默认全一不改画面。","en_us":"Blue multiplier of the moon disc colour; one is unchanged. Ports Eclipse moonColorR/G/B; defaults keep the current look."},"slider":true}
#define OMNI_MOON_COLOR_B 1.0 // [0.0 0.2 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.8 2.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
天空：天空效果入口，集中定义全部天空、日月、星空相关选项与大气内部常数，并按依赖顺序引入同目录算法文件。
调用位置：延迟三号画天空像素时调用 `GetSkyRadiance`、`CalculateStars`、`RenderSunDisc`、`RenderMoonDisc`；
    三号把上半屏天空盒写成三维贴图时调用 `UnprojectSky` 与 `GetSkyRadiance`；
    合成阶段把世界方向投回天空盒坐标时调用 `ProjectSky`；
    合成顶点阶段算日月与环境光色时调用 `GetSunAndSkyIrradiance`；
    体积云与平面云算远处的空气透视时调用 `GetSkyRadianceToPoint`。
可复制示例（`camera` 是米制世界位置，`worldDir` 是单位世界方向）：
    `vec3 atmosphere = GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, transmittance, ray_r_mu_intersects_ground);`
    `vec3 sunIrradiance = GetSunAndSkyIrradiance(camera, worldSunVector, -worldSunVector, moonIrradiance, sunSkyIrradiance, moonSkyIrradiance);`
    `vec2 skyUv = ProjectSky(worldDir, tileSize);`
设计原因与取舍：
    本文件是天空效果入口，选项与内部常数只在这里定义一次，算法体按内容拆到同目录文件，引入顺序与拆分前一致：
    预计算大气 `effects/sky/atmosphere_model.glsl`；日月圆盘 `effects/sky/sun_moon.glsl`；
    月亮轨道、月食与月相 `effects/sky/moon_orbit.glsl`；星空 `effects/sky/stars.glsl`；天空盒投影 `effects/sky/skybox.glsl`。
    天空不是实时积分，而是读预计算大气三维贴图；加载器在延迟与合成阶段把八号画面换成那张数据，
    所以这里只做查表与相位函数组合，代价与分辨率无关。
    调用前提（iterationT 原样保留）：调用方必须先声明 `texelCoord`、`worldSunVector`、`worldMoonVector` 等全局量；
    这些量由绘制主体在引入本文件前给出，本文件不重复声明。
    天空散射系数（Eclipse 的 `Sky_Brightness` 与瑞利、米氏系数）放在 `effects/sky/skyscatter.glsl`：
    这里只把瑞利、米氏倍率与天空亮度乘进查表结果，默认全一、画面不变。
    月亮轨道、月食与月相来自 Eclipse：自定义轨道在顶点阶段由世界时间闭式算出，日月解耦后才可能月食；
    真实月亮模式需要的月亮贴图与法线贴图是 Eclipse 自带文件，本项目没有，缺少时退回程序圆盘。
    月亮颜色的三通道倍率来自 Eclipse `lib/settings.glsl:402-404`：Eclipse 把它直接当月亮色，
    本项目已有色温路径，这里改成乘在基础月亮色上的倍率，默认全一、画面不变。
    资源包天空与其它天文量不同：它不靠查表，而是让原版与资源包把天空几何画进零号画面再读回来，
    所以本文件只放选项；天空几何的分流在 `rendering/celestial.glsl`，底色读取与合成在 `effects/sky/skyrender.glsl`。
*/
// --- 内部常数：原 `Settings.glsl` 里不进菜单的取值，名字保持原名 ---
#define ATMO_MIN_ALTITUDE 500.0 // 相机大气高度下限，低于它按这个高度算，避免贴地时大气几何退化。
#define ATMO_SKYBOX_MIN_ALTITUDE 500.0 - wetness * 300.0 // 反射天空盒的相机高度下限，雨天云更厚所以再压低一点。
// 预计算大气三维贴图的排布尺寸，读表时要按这些尺寸算坐标。
#define TRANSMITTANCE_TEXTURE_WIDTH 256.0 // 透过率子图宽度，单位像素。
#define TRANSMITTANCE_TEXTURE_HEIGHT 64.0 // 透过率子图高度。
#define SCATTERING_TEXTURE_R_SIZE 32.0 // 散射子图的半径方向尺寸，拼进深度方向。
#define SCATTERING_TEXTURE_MU_SIZE 128.0 // 散射子图的高度角方向尺寸。
#define SCATTERING_TEXTURE_MU_S_SIZE 32.0 // 散射子图的太阳高度角方向尺寸。
#define SCATTERING_TEXTURE_NU_SIZE 16.0 // 散射子图的视线与太阳夹角方向尺寸。
#define COMBINED_TEXTURE_WIDTH 512.0 // 拼合后大图宽度。
#define COMBINED_TEXTURE_HEIGHT 128.0 // 拼合后大图高度。
#define COMBINED_TEXTURE_DEPTH 33.0 // 拼合后大图深度。
#define IRRADIANCE_TEXTURE_WIDTH 64.0 // 辐照度子图宽度。
#define IRRADIANCE_TEXTURE_HEIGHT 16.0 // 辐照度子图高度。
// 大气物理常数，长度单位公里，亮度单位辐射亮度；与 iterationT 完全一致。
#define atmosphereModel_solar_irradiance 		vec3(1.68194, 1.85149, 1.91198) // 太阳辐照度，决定大气散射的基准亮度。
#define atmosphereModel_sun_angular_radius 		0.005 // 太阳视半径，日落时用它对太阳方向做渐隐。
#define atmosphereModel_bottom_radius 			6360.0 // 行星底半径，越过它就算被地面挡住。
#define atmosphereModel_top_radius 				6420.0 // 大气层顶半径，视线到这里离开大气。
#define atmosphereModel_rayleigh_scattering 	vec3(0.008396, 0.014590, 0.033100) // 瑞利散射系数，蓝光最强，天空因此偏蓝。
#define atmosphereModel_mie_scattering 			vec3(0.003996) // 米氏散射系数，气溶胶造成太阳附近的白晕。
#define atmosphereModel_mie_extinction 			vec3(0.004440) // 米氏消光系数，比散射略大，差额被吸收。
#define atmosphereModel_mie_phase_function_g 	0.8 // 米氏相位的前向集中程度。
#define atmosphereModel_absorption_extinction 	vec3(0.0020031, 0.0016555, 0.0000847) // 臭氧吸收系数。
#define atmosphereModel_ground_albedo 			vec3(0.1) // 地面反照率，地平线方向算一次地面反弹。
#define atmosphereModel_mu_s_min 				-0.5 // 太阳高度角的查表下限。
#define atmosphereModel_densityProfile_rayleigh 			-0.1803369 // 瑞利密度剖面的指数系数。
#define atmosphereModel_densityProfile_mie 					-1.2022459 // 米氏密度剖面的指数系数。
#define atmosphereModel_densityProfile_absorption_width 	25.0 // 臭氧三角剖面的转折高度。
#define atmosphereModel_densityProfile_absorption 			vec4(0.09617967, -0.9617967, -0.09617967, 3.847187) // 臭氧剖面分段线性系数。
// 共用数学与加载器输入，显式引入而不依赖调用顺序。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
// 太阳色与辐照：提供 `omniSunTint()`，给太阳直射与太阳圆盘做相对染色；默认取值下返回全一、不改画面。
#include "/effects/sky/suncolor.glsl"
// 天空散射系数：提供 `omniSkyRayleighTint()` 与 `omniSkyMieTint()`，给瑞利与米氏散射做逐通道倍率；默认全一、不改画面。
#include "/effects/sky/skyscatter.glsl"
// 预计算大气：球面几何、密度剖面、贴图查表、透过率、辐照度与天空辐射。
#include "/effects/sky/atmosphere_model.glsl"
// 日月圆盘：把日月光点画成天空上的圆盘。
#include "/effects/sky/sun_moon.glsl"
// 月亮轨道、月食与月相：自定义轨道、月相与真实月亮。
#include "/effects/sky/moon_orbit.glsl"
// 星空：Eclipse 星场，供主世界与末地共用。
#include "/effects/sky/stars.glsl"
// 天空盒投影：世界方向与天空盒图坐标的互逆换算。
#include "/effects/sky/skybox.glsl"
// Eclipse 天空图集与三次采样的同名兼容层。
#include "/effects/sky/eclipse_sky_adapters.glsl"
#endif // OMNI_EFFECT_SKY_SKY_INCLUDED
