#ifndef LIGHTING_COMMON_INCLUDED // 防止多个阶段重复定义同一批函数。
#define LIGHTING_COMMON_INCLUDED // 只展开一次。
// 光影验证场景共用：太阳与天空、云、雾、水面、阴影、颜色与抗锯齿全部来自生成的 omni-gfx 库。
// 调用位置：天空、体积云、地表、反射、水面、雾、环境光、合成、时间抗锯齿与后期阶段。
// 设计原因与取舍：
//   场景只保留简单几何，所有真实感来自光照：太阳色温由大气透过率决定，
//   天空用单次散射，云用三维噪声体积步进，阴影用三级级联 PCSS，雾按阴影贴图取光柱。
//   参数只在这里写一份，直射光、天空环境光、云、雾与水面反射不会各用一套太阳方向。
// 数学、颜色与采样：向量、曲线、蓝噪声与抖动。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/sampling.glsl"
// 噪声与云：三维形状、平面云与多次散射光照。
#include "/omni-gfx/noise.glsl"
#include "/omni-gfx/cloud.glsl"
#include "/omni-gfx/cloud_volume.glsl"
// 大气、雾、水与阴影：天空散射、空气透视、吸收、PCSS 与级联选择。
#include "/omni-gfx/atmosphere.glsl"
#include "/omni-gfx/fog.glsl"
#include "/omni-gfx/water.glsl"
#include "/omni-gfx/shadow.glsl"
// 全局光、反射、后期与时间抗锯齿。
#include "/omni-gfx/gi.glsl"
#include "/omni-gfx/reflection.glsl"
#include "/omni-gfx/post.glsl"
#include "/omni-gfx/antialias.glsl"
#include "/omni-gfx/color.glsl"

uniform vec3 uSunDirection; // 指向太阳的单位向量，所有阶段共用。
uniform vec3 uSunColor; // 太阳色度，已归一化亮度。
uniform float uSunIrradiance; // 太阳直射辐照度倍率，统一控制曝光。
uniform float uSkyIntensity; // 天空环境光倍率。
uniform float uTime; // 场景时间，推动云、雾与水面。
uniform float uFrame; // 帧号，给抖动换相位。
uniform float uWaterLevel; // 水面高度，米。
uniform vec3 uCameraPosition; // 相机世界位置，云、雾与水面共用。
uniform sampler2D uSkyMap; // 等距柱状天空贴图，包含云，供环境光与反射兜底。
uniform sampler3D uCloudBase; // 体积云基础形状噪声。
uniform sampler3D uCloudDetail; // 体积云细节侵蚀噪声。
uniform sampler2D uCloudCurl; // 云的水平扭曲与雾的团块噪声。
uniform sampler2D uCloudShadowMap; // 云影贴图，一表示受光。
uniform vec4 uCloudShadowRect; // 云影贴图的中心 x、中心 z、覆盖范围与强度。
uniform sampler2D uBlueNoise; // 蓝噪声，云、雾与 PCSS 的时间抖动。

// 云量天气图的水平偏移；主画面与云影贴图必须用同一个值，否则影子会与云错开。
// 数值的单位是天气图的一整圈，不是米；调它等于把整片云场沿世界坐标平移几公里。
#define LIGHTING_CLOUD_COVERAGE_OFFSET 0.24

// 太阳在云层中部的投影点：云洞、云影和光柱都从这里计算，改太阳方向时不会各自错位。
vec2 lightingSunCloudPlane() // 返回太阳方向与云层中部的交点水平坐标。
{
    vec3 sun = normalize(uSunDirection); // 单位太阳方向。
    float midAltitude = 5750.0; // 云层中部高度，与云层参数保持一致。
    return uCameraPosition.xz + sun.xz * ((midAltitude - uCameraPosition.y) / max(sun.y, 0.05)); // 沿太阳方向投到云层。
}

// 大气常数：与天空、云、雾、水面共用同一组；改一处所有阶段的色温和雾色一起变。
OgxAtmosphere lightingAtmosphere() // 返回本场景的大气参数。
{
    OgxAtmosphere air = ogxAtmosphereEarth(); // 先取库里的地球常数。
    air.sunIntensity = 20.0; // 太阳辐照度整体倍率，与曝光键值配合。
    air.mieScattering = vec3(0.12e-3, 0.12e-3, 0.13e-3); // 气溶胶再压低，晴天天空更深蓝，地平线不会先被白雾盖住。
    air.mieG = 0.60; // 前向散射较强，太阳附近有自然白晕，但不会把整条地平线烧白。
    return air; // 返回可直接使用的参数。
}

// 太阳色：由海平面处的大气透过率决定，低太阳自然偏暖，正午自然偏白。
vec3 lightingSunChroma() // 返回太阳直射光的颜色，不含强度。
{
    OgxAtmosphere air = lightingAtmosphere(); // 大气常数。
    vec3 origin = vec3(0.0, air.planetRadius + max(uCameraPosition.y, 0.0) * 0.001, 0.0); // 相机所在高度，公里。
    vec3 transmittance = ogxAtmosphereSunTransmittance(air, origin, normalize(uSunDirection), 4); // 阳光到地面的透过率。
    float luma = max(ogxLuminance(transmittance), 1e-4); // 只保留色度，亮度交给辐照度倍率。
    return uSunColor * mix(transmittance / luma, vec3(1.0), 0.95); // 叠上调用方的色温倾向，低阳保持接近白色。
}

// 天空颜色：单次散射加太阳圆盘；`altitudeKm` 是相机高度，`steps` 是积分段数，`sunDisk` 控制圆盘是否参与。
// 为什么把太阳圆盘单独开关：环境光与水面的天空贴图只要天空和云，太阳由直射光与水面高光单独计算，
// 否则巨大的圆盘会被模糊成一大片白斑，湖面看起来像一块发光的塑料。
vec3 lightingSky(vec3 direction, float altitudeKm, int steps, float sunDisk) // 返回天空辐射，线性高动态范围。
{
    OgxAtmosphere air = lightingAtmosphere(); // 大气常数。
    vec3 sky = ogxAtmosphereSky(air, altitudeKm, direction, normalize(uSunDirection), steps); // 单次散射天空。
    vec3 origin = vec3(0.0, air.planetRadius + max(altitudeKm, 0.0), 0.0); // 太阳透过率的起点。
    vec3 transmittance = ogxAtmosphereSunTransmittance(air, origin, normalize(uSunDirection), 4); // 阳光到相机的透过率。
    float disk = ogxSunDisc(direction, normalize(uSunDirection), 0.000016, 90000.0); // 约零点七度的太阳圆盘；之前三度多，泛光一开就成大白球。
    sky += uSunColor * transmittance * (disk * uSunIrradiance * 7.0 * sunDisk); // 圆盘亮度远高于天空，泛光会自然扩散。
    return max(sky, vec3(0.0)) * uSkyIntensity; // 天空整体倍率；直射光另算，不乘在这里。
}

// 云层参数：一次填完整，天空、方块与水面反射读同一份，云的位置不会错开。
OgxCumulusMedia lightingCloudMedia() // 返回体积云参数。
{
    OgxCumulusMedia media; // 先声明再逐字段填写。
    media.wind = vec3(uTime * 0.0006, 0.0, -uTime * 0.0011); // 缓慢水平风，按米计。
    media.camera_position = uCameraPosition; // 相机绝对位置，供曲率与云影使用。
    media.light_color = mix(lightingSunChroma(), vec3(1.0), 0.62); // 多次散射后接近白色，只保留少量太阳色温。
    media.sky_color = lightingSky(vec3(0.0, 1.0, 0.0), 2.0, 4, 0.0); // 云层高度的天顶光。
    media.lightning_position = vec3(0.0); // 本场景没有闪电。
    media.altitude = vec2(1200.0, 2400.0); // 云底与云顶高度，米；一千二百米厚的积云，影子能落在近处湖面。
    media.lighting_strength = vec2(max(uSunIrradiance * 0.026, 0.11), 0.58); // 直射倍率与环境光。
    media.planet_radius = 6360000.0; // 地球半径，米。
    media.cloud_scale = 1.0; // 云坐标直接用米，基础噪声与细节噪声各自乘自己的频率。
    media.density_option = 0.30; // 消光倍率；厚云不透光，薄边仍能透出银边。
    media.coverage = 0.50; // 多尺度天气图的云量下限；配合两层天气噪声形成大小不一的积云场。
    media.wetness = 0.06; // 晴天积云，只让云顶稍微收口。
    media.bottom_brightness = 0.32; // 云底保留少量直射，主要靠天光与多次散射。
    media.outscatter_factor = 1.40; // 外散射曲线，薄处与云顶更亮。
    media.lightning_intensity = 0.0; // 无闪电。
    media.lightning_strength = 0.0; // 无闪电。
    return media; // 返回本帧云层。
}

// 体积云：沿视线步进一层积云，返回预乘颜色与覆盖率；调用方再叠到天空。
vec4 lightingCloudMarch(vec3 direction, vec2 jitter, int steps) // 返回 rgb 加色与 a 覆盖率。
{
    OgxCumulusMedia media = lightingCloudMedia(); // 云层参数。
    // 云量完全由多尺度天气图与三维噪声决定。这里不再按视线角度手工加两团云：
    // 手工遮罩会和云影贴图对不上，也会把整片天空挤成一朵形状固定的蘑菇云。
    vec3 hitOffset; // 平均命中位置，空气透视淡出要用。
    vec4 cloud = ogxCumulusMarch(direction, media, jitter, hitOffset, uCloudBase, uCloudDetail, uCloudCurl,
                                 float(steps), 1.0, normalize(uSunDirection), 0.00006, LIGHTING_CLOUD_COVERAGE_OFFSET,
                                 0.0025, 1.10); // 高层积云。
    // 空气透视：云越远，颜色越向天空的蓝灰靠，同时降低覆盖率。
    // 没有这一步时，远处云层在地平线上排成一条高对比的碎块带，像一排贴在天空上的纸片。
    float hitDistance = length(hitOffset);
    float aerial = 1.0 - exp(-hitDistance * 5.0e-5);
    vec3 haze = media.sky_color * 0.45;
    cloud.rgb = mix(cloud.rgb, haze * (1.0 - cloud.a), aerial * 0.35);
    float distanceFade = 1.0 - smoothstep(20000.0, 52000.0, hitDistance); // 五十二公里外淡出，地平线不再是一条碎云带。
    cloud.rgb *= distanceFade;
    cloud.a = mix(1.0, cloud.a, distanceFade);
    return vec4(cloud.rgb, 1.0 - cloud.a); // 换成预乘颜色与覆盖率，方便时间累积。
}

// 云影：把地面点投到云影贴图；超出范围或靠近边缘时淡回受光。
// 高度修正让雾点也能查到头顶那片云：云影贴图烘在地面上，雾点越高，太阳光线穿过的云越靠前，
// 所以按高度沿太阳水平方向反推一段，光柱的明暗才会随高度倾斜，而不是一根竖直灰柱。
float lightingCloudShadow(vec3 position) // 返回零到一的太阳可见度。
{
    vec3 sun = normalize(uSunDirection);
    float heightShift = max(position.y, 0.0) / max(sun.y, 0.05);
    vec2 uv = (position.xz - sun.xz * heightShift - uCloudShadowRect.xy) / max(uCloudShadowRect.z, 1.0) + 0.5;
    vec2 edge = smoothstep(vec2(0.0), vec2(0.08), uv) * (1.0 - smoothstep(vec2(0.92), vec2(1.0), uv));
    float shadow = texture(uCloudShadowMap, clamp(uv, vec2(0.001), vec2(0.999))).r;
    return mix(1.0, shadow, edge.x * edge.y * uCloudShadowRect.w);
}

// 空气透视：地表到相机的散射；远景融进天空，地平线不会有一条硬边。
vec3 lightingAerial(vec3 position, vec3 viewDirection, float distance, out vec3 transmittance) // 返回散射色。
{
    OgxAtmosphere air = lightingAtmosphere(); // 大气常数。
    float altitude = max(uCameraPosition.y, 0.0) * 0.001; // 相机高度，公里。
    return ogxAerialPerspective(air, altitude, viewDirection, distance * 0.001, normalize(uSunDirection), 2, transmittance); // 两段足够远景。
}

// 像素坐标到世界方向；主画面、云与反射共用同一套针孔相机公式。
vec3 lightingRayDirection(vec2 pixel, vec2 resolution, vec3 forward, vec3 right, vec3 up, float tanHalfFov, float aspect) // 返回单位方向。
{
    vec2 ndc = pixel / resolution * 2.0 - 1.0; // 零到一换成负一到一。
    return normalize(forward + right * ndc.x * tanHalfFov * aspect + up * ndc.y * tanHalfFov); // 针孔相机光线。
}

// 立方体贴图六个面的方向：`uv` 是负一到一的局部坐标。
vec3 lightingCubeDirection(int face, vec2 uv) // 返回立方体面上的世界方向。
{
    if (face == 0) return vec3(1.0, -uv.y, -uv.x); // 正 X。
    if (face == 1) return vec3(-1.0, -uv.y, uv.x); // 负 X。
    if (face == 2) return vec3(uv.x, 1.0, uv.y); // 正 Y。
    if (face == 3) return vec3(uv.x, -1.0, -uv.y); // 负 Y。
    if (face == 4) return vec3(uv.x, -uv.y, 1.0); // 正 Z。
    return vec3(-uv.x, -uv.y, -1.0); // 负 Z。
}

// 采样等距柱状天空贴图：水平角决定 u，仰角决定 v；与天空预渲染的映射一致。
vec3 lightingSampleSky(vec3 direction, float lod) // 返回天空辐射。
{
    float u = atan(direction.z, direction.x) * 0.15915494309 + 0.5; // 水平角映射到零到一。
    float v = acos(clamp(direction.y, -1.0, 1.0)) * 0.31830988618; // 仰角映射到零到一，零是头顶。
    return textureLod(uSkyMap, vec2(u, v), lod).rgb; // 读天空贴图。
}

// 天空环境光：按法线取天空贴图，粗糙表面取更模糊的层级。
vec3 lightingSkyAmbient(vec3 normal, float roughness) // 返回漫反射天光。
{
    float lod = mix(2.0, 5.0, clamp(roughness, 0.0, 1.0)); // 粗糙表面平均更大一片天空。
    vec3 zenith = lightingSampleSky(vec3(0.0, 1.0, 0.0), lod + 1.0); // 天顶色也参与平均，避免地平线在球腰上形成亮环。
    vec3 sky = mix(lightingSampleSky(normal, lod), zenith, 0.35); // 法线样本与天顶混合，近似半球平均。
    vec3 ground = vec3(0.035, 0.042, 0.022); // 朝下的面接收草地反弹，不能采样天空下半球，否则球底会发蓝。
    float down = smoothstep(0.18, -0.12, normal.y); // 从赤道稍上方开始过渡到地面色。
    return mix(sky, ground, down * 0.82); // 朝下的面换成地面反弹。
}

#endif // 共用参数结束。
