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
    air.mieScattering = vec3(0.55e-3, 0.55e-3, 0.58e-3); // 气溶胶略淡，地平线保持蓝灰而不是一条白带。
    air.mieG = 0.72; // 前向散射较强，太阳附近有自然白晕。
    return air; // 返回可直接使用的参数。
}

// 太阳色：由海平面处的大气透过率决定，低太阳自然偏暖，正午自然偏白。
vec3 lightingSunChroma() // 返回太阳直射光的颜色，不含强度。
{
    OgxAtmosphere air = lightingAtmosphere(); // 大气常数。
    vec3 origin = vec3(0.0, air.planetRadius + max(uCameraPosition.y, 0.0) * 0.001, 0.0); // 相机所在高度，公里。
    vec3 transmittance = ogxAtmosphereSunTransmittance(air, origin, normalize(uSunDirection), 4); // 阳光到地面的透过率。
    float luma = max(ogxLuminance(transmittance), 1e-4); // 只保留色度，亮度交给辐照度倍率。
    return uSunColor * (transmittance / luma); // 叠上调用方的色温倾向。
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
    float disk = ogxSunDisc(direction, normalize(uSunDirection), 0.00042, 32000.0); // 约零点五度的太阳圆盘。
    sky += uSunColor * transmittance * (disk * uSunIrradiance * 7.0 * sunDisk); // 圆盘亮度远高于天空，泛光会自然扩散。
    return max(sky, vec3(0.0)) * uSkyIntensity; // 天空整体倍率；直射光另算，不乘在这里。
}

// 大尺度云量遮罩：同一份二维噪声给主画面云块与地面云影共用。
// 为什么不让云影自己取一个固定覆盖率：主画面按视线投影到大云团，云影按太阳方向投影到同一片云，
// 如果两边用不同覆盖率，就会出现“天上没云、地上有影子”的悬空阴影。
float lightingCloudCoverage(vec2 plane) // 返回零到一的覆盖率下限。
{
    // 主云塔位置：相机前方约三十二公里、偏右三公里；半径四到九公里，形成一座孤立的高耸积雨云。
    // 为什么用世界坐标的圆形区域：只靠二维噪声很难稳定地把一座塔放到画面中央；这里先选位置，再让三维噪声长细节。
    vec2 hero = vec2(3000.0, -32000.0); // 主云塔中心，米。
    float heroRegion = 1.0 - smoothstep(4000.0, 9000.0, length(plane - hero)); // 中心为一，外缘平滑到零。
    plane += vec2(-6000.0, 28000.0); // 把背景云团也放到远处，避免它们盖住主云塔。
    float mask = texture(uCloudCurl, plane * 1.6e-5 + vec2(uTime * 0.000004, -uTime * 0.000002)).r; // 六十公里尺度。
    float mask2 = texture(uCloudCurl, plane * 5.2e-5 + vec2(-uTime * 0.000006, uTime * 0.000004)).g; // 十九公里尺度。
    float cluster = smoothstep(0.40, 0.58, mask) * smoothstep(0.33, 0.63, mask2); // 背景云团，彼此分开。
    cluster = mix(cluster * 0.35, 1.0, heroRegion); // 主云塔内部铺满，外部只留少量背景云。
    // 太阳方向的云洞：在太阳投影到云层的落点留一个缺口，四周用云环围住。
    // 缺口让阳光直射到湖面与薄雾，云环在地面投下影子；两者相接就形成清晰但不生硬的光柱。
    vec2 sunHole = lightingSunCloudPlane(); // 太阳投影到云层中部的落点。
    float sunDistance = length(plane - sunHole); // 到太阳投影点的距离。
    float gap = smoothstep(500.0, 1600.0, sunDistance); // 中心为零，外缘为一。
    float ring = smoothstep(500.0, 1400.0, sunDistance) * (1.0 - smoothstep(2600.0, 5000.0, sunDistance)); // 云环。
    cluster = max(cluster, ring * 0.95); // 云环负责影子。
    cluster *= gap; // 缺口保持透光，阳光才能穿过薄雾。
    return mix(0.12, 1.05, cluster); // 主云塔用略高于一的覆盖率，既填实塔身又保留噪声缺口。
}

// 云层参数：一次填完整，天空、方块与水面反射读同一份，云的位置不会错开。
OgxCumulusMedia lightingCloudMedia() // 返回体积云参数。
{
    OgxCumulusMedia media; // 先声明再逐字段填写。
    media.wind = vec3(uTime * 0.0009, 0.0, uTime * 0.0017); // 缓慢水平风，云块每秒移动几米。
    media.camera_position = uCameraPosition; // 相机绝对位置，供曲率与云影使用。
    media.light_color = mix(lightingSunChroma(), vec3(1.0), 0.45); // 云体多次散射后接近白色，只保留一半太阳色温。
    media.sky_color = lightingSky(vec3(0.0, 1.0, 0.0), 2.0, 4, 0.0); // 云层高度的天顶光；不要太阳圆盘，避免云底被一个白点压亮。
    media.lightning_position = vec3(0.0); // 本场景没有闪电。
    media.altitude = vec2(1500.0, 10000.0); // 云底与云顶高度，米；十公里高的积雨云在二十到四十公里外形成完整塔身。
    media.lighting_strength = vec2(uSunIrradiance * 0.012, 0.50); // 直射倍率；云顶亮白但不过曝，云底靠多次散射保留灰蓝。
    media.planet_radius = 6360000.0; // 地球半径，米。
    media.cloud_scale = 0.000065; // 约十五公里一个云块单元，主云塔宽三到五公里。
    media.density_option = 0.140; // 消光倍率；厚云不透光，薄边仍能透出银边。
    media.coverage = 0.72; // 默认云量；调用方按大尺度遮罩覆盖成云团与空隙。
    media.wetness = 0.10; // 晴天积云，只让云顶稍微收口。
    media.bottom_brightness = 0.028; // 云底更暗，避免整块云像白纸。
    media.outscatter_factor = 1.35; // 外散射曲线，薄边更亮。
    media.lightning_intensity = 0.0; // 无闪电。
    media.lightning_strength = 0.0; // 无闪电。
    return media; // 返回本帧云层。
}

// 体积云：沿视线步进一层积云，返回预乘颜色与覆盖率；调用方再叠到天空。
vec4 lightingCloudMarch(vec3 direction, vec2 jitter, int steps) // 返回 rgb 加色与 a 覆盖率。
{
    OgxCumulusMedia media = lightingCloudMedia(); // 云层参数。
    // 大尺度云量遮罩：把视线投到云层中部，在水平面上取低频噪声；
    // 直接把视线投影到云层平面上取样；按视线水平坐标取样在低仰角会被压成放射状长条，云会像被拉成雨帘。
    float layerDistance = max((5750.0 - uCameraPosition.y) / max(direction.y, 0.06), 0.0); // 到云层中部的距离。
    vec2 plane = uCameraPosition.xz + direction.xz * layerDistance; // 云层平面上的落点。
    // 主云塔用视线方位与仰角选出一根竖直云柱：二维平面遮罩只能选出天空里的一块圆斑，云会变成飞碟。
    // 方位角以正前方为零，仰角用方向向量的纵分量；这根柱子从云底一直长到云顶，才有塔的轮廓。
    float azimuth = atan(direction.x, -direction.z); // 当前视线的水平角。
    float elevation = asin(clamp(direction.y, -1.0, 1.0)); // 当前视线的仰角。
    float towerWidth = mix(0.085, 0.135, smoothstep(0.140, 0.205, elevation)); // 塔身宽度基本不变，只在顶部展开成砧状。
    float heroAzimuth = 1.0 - smoothstep(towerWidth * 0.55, towerWidth, abs(azimuth - 0.090)); // 塔身水平半宽约三到七度。
    float heroElevation = smoothstep(0.018, 0.045, elevation) * (1.0 - smoothstep(0.19, 0.245, elevation)); // 云底到云顶。
    float hero = heroAzimuth * heroElevation; // 一表示主云塔内部。
    // 太阳方向留出真正的无云洞：只降低覆盖率时，云量映射仍可能生成薄云，阳光穿不过来。
    if (length(plane - lightingSunCloudPlane()) < 300.0) // 云洞半径，米。
    {
        return vec4(0.0); // 完全透明，露出蓝天与太阳方向。
    }
    media.coverage = mix(lightingCloudCoverage(plane) * 0.35, 0.86, hero); // 背景云压低，主塔用略高覆盖率填实，噪声咬出边缘。
    vec3 hitOffset; // 平均命中位置，本场景不需要。
    vec4 cloud = ogxCumulusMarch(direction, media, jitter, hitOffset, uCloudBase, uCloudDetail, uCloudCurl,
                                 float(steps), 1.0, normalize(uSunDirection), 1.0, 0.0, 2.5, 1.2); // 库的步进核心；高频细节侵蚀把规则云柱咬成花椰菜边。
    return vec4(cloud.rgb, 1.0 - cloud.a); // 换成预乘颜色与覆盖率，方便时间累积。
}

// 云影：把地面点投到云影贴图；超出范围或靠近边缘时淡回受光。
float lightingCloudShadow(vec3 position) // 返回零到一的太阳可见度。
{
    vec2 uv = (position.xz - uCloudShadowRect.xy) / max(uCloudShadowRect.z, 1.0) + 0.5; // 世界坐标换成贴图坐标。
    vec2 edge = smoothstep(vec2(0.0), vec2(0.08), uv) * (1.0 - smoothstep(vec2(0.92), vec2(1.0), uv)); // 边缘淡出。
    float shadow = texture(uCloudShadowMap, clamp(uv, vec2(0.001), vec2(0.999))).r; // 贴图里一表示受光。
    return mix(1.0, shadow, edge.x * edge.y * uCloudShadowRect.w); // 范围外不压暗。
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
