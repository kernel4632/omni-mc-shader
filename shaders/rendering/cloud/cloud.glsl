/*
云的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/cloud/cloud.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_CLOUD_CLOUD_INCLUDED
#define OMNI_RENDER_CLOUD_CLOUD_INCLUDED
#include "/effects/cloud/cloud.glsl"
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
// 云的算法依赖大气透视与共用数学，显式引入而不依赖调用顺序。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/rendering/sky/sky.glsl"
// 积雨云内闪电复用氛围文件里的闪电开关与加载器输入（`lightningBoltPosition`），显式引入而不依赖调用顺序。
#include "/rendering/sky/atmosphere.glsl"
// 每日天气：按游戏日给出当天四层云的覆盖度与密度，供基础云与各附加层替换默认云量；
// 总开关关闭时它整段不参与编译，默认画面与原来一致。文件自带守卫，重复引入无副作用。
#include "/rendering/weather/dailyweather.glsl"
// 云密度只在能读三维云噪声的阶段参与编译：延迟三号画天空、七号算低分辨率云、八号把云贴回天空。
// 同一个判据收成一个宏，交给体积云与平面云，其它程序整段跳过，不会把三维噪声贴图当成二维采样。
#if defined COLORTEX_CLOUDNOISE && (defined OMNI_DEFERRED3_PASS || defined OMNI_DEFERRED7_PASS || defined OMNI_DEFERRED8_PASS)
#define OMNI_CLOUD_DENSITY_PASS 1 // 三维云噪声可用，开启体积云与平面云的编译。
#endif
// 体积云密度、光照、步进核心、附加云层与低分辨率云总图。
#include "/rendering/cloud/volumetric.glsl"
// 平面云：固定高度一层平面上的云。
#include "/rendering/cloud/planar.glsl"
// 云影贴图与模糊：不依赖云密度，任何引入云的程序都能编译。
#include "/rendering/cloud/shadow.glsl"
#endif // OMNI_RENDER_CLOUD_CLOUD_INCLUDED
