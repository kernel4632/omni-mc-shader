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
#include "/omni-gfx/cloud/cloud.glsl"
#include "/omni-gfx/cloud/volume.glsl"
// 大气、雾、水与阴影：天空散射、空气透视、吸收、PCSS 与级联选择。
#include "/omni-gfx/atmosphere/atmosphere.glsl"
#include "/omni-gfx/fog/fog.glsl"
#include "/omni-gfx/water.glsl"
#include "/omni-gfx/shadow/shadow.glsl"
// 全局光、反射、后期与时间抗锯齿。
#include "/omni-gfx/gi/gi.glsl"
#include "/omni-gfx/reflection/reflection.glsl"
#include "/omni-gfx/post/post.glsl"
#include "/omni-gfx/antialias/antialias.glsl"
#include "/omni-gfx/color.glsl"
// 预计算大气查表：太阳与天空颜色直接来自 iterationT 的同一份数据。
#include "/omni-gfx/atmosphere/model.glsl"

uniform vec3 uSunDirection; // 指向太阳的单位向量，所有阶段共用。
uniform vec3 uSunColor; // 太阳色度倾向；叠在大气透过率之上，默认接近白色。
uniform float uSunIrradiance; // 太阳辐照度倍率；一表示直接使用大气的物理太阳。
uniform float uSkyIntensity; // 天空整体倍率；一表示直接使用大气的物理天空。
uniform vec3 uSunLight; // CPU 预先算好的太阳直射辐照度，已含大气透过率与色适应。
uniform vec3 uSkyLight; // CPU 预先算好的天空辐照度。
uniform vec3 uSunTransmittance; // 太阳方向的透过率，给太阳圆盘染色。
uniform float uTime; // 场景时间，推动云、雾与水面。
uniform float uFrame; // 帧号，给抖动换相位。
uniform float uWaterLevel; // 水面高度，米。
uniform vec3 uCameraPosition; // 相机世界位置，云、雾与水面共用。
uniform sampler2D uSkyMap; // 等距柱状天空贴图，包含云，供环境光与反射兜底。
uniform sampler3D uAtmoLut; // iterationT 的预计算大气表：512×128×33 的 RGBA32F。
uniform sampler3D uCloudBase; // 体积云基础形状噪声。
uniform sampler3D uCloudDetail; // 体积云细节侵蚀噪声。
uniform sampler2D uCloudCurl; // 云的水平扭曲与雾的团块噪声。
uniform sampler2D uCloudShadowMap; // 云影贴图，一表示受光。
uniform vec4 uCloudShadowRect; // 云影贴图的中心 x、中心 z、覆盖范围与强度。
uniform sampler2D uBlueNoise; // 蓝噪声，云、雾与 PCSS 的时间抖动。

// 云量天气图的水平偏移；主画面与云影贴图必须用同一个值，否则影子会与云错开。
// 数值的单位是天气图的一整圈，不是米；调它等于把整片云场沿世界坐标平移几公里。
#define LIGHTING_CLOUD_COVERAGE_OFFSET 0.68

// 与 iterationT 的 `curve` 相同的平滑曲线：两端导数为零，用来收太阳圆盘与昼夜边界。
float lightingCurve(float x)
{
    return x * x * (3.0 - 2.0 * x); // 三次平滑，输入已经在零到一内。
}

// 太阳在云层中部的投影点：云洞、云影和光柱都从这里计算，改太阳方向时不会各自错位。
vec2 lightingSunCloudPlane() // 返回太阳方向与云层中部的交点水平坐标。
{
    vec3 sun = normalize(uSunDirection); // 单位太阳方向。
    float midAltitude = 750.0; // 云层中部高度，与云层参数保持一致。
    return uCameraPosition.xz + sun.xz * ((midAltitude - uCameraPosition.y) / max(sun.y, 0.05)); // 沿太阳方向投到云层。
}

// 与 iterationT 的 PrecomputedAtmosphere.glsl 完全相同的常数；天空、雾、云和水面共用一份。
OgxAtmosphereModel lightingAtmosphereModel() // 返回预计算大气查表的参数。
{
    OgxAtmosphereModel model; // 先声明再逐字段填写。
    model.bottom_radius = 6360.0; // 行星底半径，公里。
    model.top_radius = 6420.0; // 大气层顶，公里。
    model.sun_angular_radius = 0.005; // 太阳视半径，贴地时用它对透过率做渐隐。
    model.mie_phase_g = 0.8; // 米氏相位前向集中程度，与 iterationT 相同。
    model.mu_s_min = -0.5; // 太阳高度角查表下限。
    model.solar_irradiance = vec3(1.68194, 1.85149, 1.91198); // 太阳辐照度。
    model.rayleigh_scattering = vec3(0.008396, 0.014590, 0.033100); // 瑞利散射系数。
    model.mie_scattering = vec3(0.003996); // 米氏散射系数。
    model.absorption_extinction = vec3(0.0020031, 0.0016555, 0.0000847); // 臭氧吸收。
    model.density_rayleigh = -0.1803369; // 瑞利密度指数。
    model.density_mie = -1.2022459; // 米氏密度指数。
    model.absorption_width = 25.0; // 臭氧剖面转折高度。
    model.density_absorption = vec4(0.09617967, -0.9617967, -0.09617967, 3.847187); // 臭氧剖面系数。
    model.transmittance_width = 256.0; // 透过率子图尺寸。
    model.transmittance_height = 64.0;
    model.scattering_r = 32.0; // 散射子图尺寸。
    model.scattering_mu = 128.0;
    model.scattering_mu_s = 32.0;
    model.scattering_nu = 16.0;
    model.combined_width = 512.0; // 拼合大图尺寸；必须与加载的 AtmoData 一致。
    model.combined_height = 128.0;
    model.combined_depth = 33.0;
    model.irradiance_width = 64.0;
    model.irradiance_height = 16.0;
    return model; // 返回这组常数。
}

// 大气计算的相机位置：iterationT 把相机抬到至少六十三米，避免地表高度让地平线抖动。
vec3 lightingAtmosphereCamera() // 返回公里制的相机位置。
{
    return vec3(0.0, max(uCameraPosition.y, 63.0) * 0.001 + 6360.0, 0.0); // y 轴朝上，零经度。
}

// 太阳直射辐照度：CPU 每帧查一次大气表，片元阶段只读一个向量。
vec3 lightingSunLight() // 返回完整辐照度，不是归一化色度。
{
    return uSunLight * uSunColor * uSunIrradiance; // 叠调用方的色温倾向与整体倍率。
}

// 天空环境辐照度：同样由 CPU 预先查表，供地表、雾与水色使用。
vec3 lightingSunSkyLight() // 返回完整辐照度。
{
    return uSkyLight * uSkyIntensity; // 天空整体倍率。
}

// 太阳色度：把完整辐照度归一化，供雾、水面与云做染色；亮度由调用处单独乘。
vec3 lightingSunChroma() // 返回不含强度的太阳颜色。
{
    vec3 sun = lightingSunLight(); // 完整辐照度。
    return sun / max(ogxLuminance(sun), 1e-6); // 只保留色度。
}

// 天空辐射：查 iterationT 的散射表；`sunDisk` 控制是否叠加太阳圆盘。
// 为什么把太阳圆盘单独开关：环境光与水面的天空贴图只要天空和云，太阳由直射光与水面高光单独计算，
// 否则巨大的圆盘会被模糊成一大片白斑，湖面看起来像一块发光的塑料。
vec3 lightingSky(vec3 direction, float altitudeKm, int steps, float sunDisk) // 返回天空辐射，线性高动态范围。
{
    OgxAtmosphereModel model = lightingAtmosphereModel(); // 同一组常数。
    vec3 camera = vec3(0.0, max(uCameraPosition.y, 63.0) * 0.001 + 6360.0, 0.0); // 公里制相机。
    vec3 unusedTransmittance; // 天空表顺带返回的视线透过率，这里不用。
    bool groundHit; // 视线是否打到地面球；本场景取假，与 iterationT 默认一致。
    vec3 sky = ogxAtmoSkyRadiance(model, uAtmoLut, camera, direction, normalize(uSunDirection),
        -normalize(uSunDirection), false, vec3(1.0), vec3(1.0), 0.0, 0.0, 1.0, false, unusedTransmittance, groundHit); // 查散射表。
    if (sunDisk > 0.0) // 只有主画面画太阳。
    {
        float cosine = dot(direction, normalize(uSunDirection)); // 与太阳方向的夹角余弦。
        float disc = lightingCurve(ogxSaturate((cosine - (1.0 - 5.0e-5)) * 4.0e4)); // 约零点五度的圆盘。
        disc *= disc; // 平方收边。
        float timeNoon = 1.0 - pow(1.0 - (clamp(normalize(uSunDirection).y, 0.2, 0.99) - 0.2) / 0.8, 6.0); // 正午权重。
        vec3 sunDisc = vec3(1.1114, 0.9756, 0.9133) * (disc * (0.2 + timeNoon * 3.0) * 200.0); // 与 iterationT 相同的圆盘亮度。
        sky += sunDisc * uSunTransmittance * sunDisk; // 圆盘用 CPU 预计算的太阳透过率染暖。
    }
    return max(sky, vec3(0.0)) * uSkyIntensity; // 天空整体倍率。
}

// 云层参数：一次填完整，天空、方块与水面反射读同一份，云的位置不会错开。
OgxCumulusMedia lightingCloudMedia() // 返回体积云参数。
{
    OgxCumulusMedia media; // 先声明再逐字段填写。
    // 风与 iterationT 相同：风速按秒累积，再乘一个固定的水平方向；云坐标是米。
    float wind = 0.0005 * uTime; // 云场的水平位移。
    media.wind = vec3(1.0, -0.05, -0.4) * wind; // 一个方向的风，云不会被拉成十字。
    media.camera_position = uCameraPosition; // 相机绝对位置，供曲率与云影使用。
    media.light_color = lightingSunLight(); // 直射光用完整辐照度，模块内不再归一化。
    media.sky_color = lightingSunSkyLight(); // 天空环境辐照度。
    media.lightning_position = vec3(0.0); // 本场景没有闪电。
    media.altitude = vec2(500.0, 1000.0); // 晴天积云的云底与云顶高度，米。
    media.lighting_strength = vec2(1.0, 1.0); // 直射与环境强度，与 iterationT 默认相同。
    media.planet_radius = 6360000.0; // 地球半径，米。
    media.cloud_scale = 1.0; // 云坐标直接用米。
    media.density_option = 1.0; // 密度倍率；与 iterationT 的 CLOUD_CLEAR_DENSITY 相同。
    media.coverage = 0.28; // 晴天云量，与 CLOUD_CLEAR_COVERY 相同。
    media.wetness = 0.0; // 本场景是晴天。
    media.bottom_brightness = 0.15; // 云底保留的直射，与 CLOUD_BOTTOM_BRIGHTNESS 相同。
    media.outscatter_factor = 1.3; // 外散射指数，与 CLOUD_OUTSCATTER_FACTOR 相同。
    media.lightning_intensity = 0.0; // 无闪电。
    media.lightning_strength = 0.0; // 无闪电。
    return media; // 返回本帧云层。
}

// 体积云：沿视线步进一层积云，返回预乘颜色与透射率；调用方再叠到天空。
vec4 lightingCloudMarch(vec3 direction, vec2 jitter) // 返回 rgb 加色与 a 透射率。
{
    OgxCumulusMedia media = lightingCloudMedia(); // 云层参数。
    vec3 hitOffset; // 平均命中位置，空气透视淡出要用。
    // 步数与 iterationT 相同：二十步，视线越竖直越少；云坐标频率与云量偏移也保持一致。
    vec4 cloud = ogxCumulusMarch(direction, media, jitter, hitOffset, uCloudBase, uCloudDetail, uCloudCurl,
                                 20.0, 1.0, normalize(uSunDirection), 0.0007, LIGHTING_CLOUD_COVERAGE_OFFSET,
                                 0.007, 1.0); // 晴天积云。
    return cloud; // 返回预乘颜色与透射率。
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

// 空气透视：与 iterationT 的地表散射相同的四段解析散射，不采样大气表。
// 距离先乘 LANDSCATTERING_DISTANCE 0.003，再乘 LANDSCATTERING_STRENGTH 2.0；
// 这是参考光影对远景蓝灰薄雾的实际做法，比逐像素查表便宜，也避免远景被洗成同一块灰。
vec3 lightingAerial(vec3 position, vec3 viewDirection, float distance, out vec3 transmittance) // 返回散射色。
{
    OgxAtmosphereModel model = lightingAtmosphereModel(); // 同一组常数。
    vec3 camera = lightingAtmosphereCamera(); // 公里制相机。
    float scaled = distance * 0.001 * 0.003; // 米换成公里再乘参考距离倍率。
    transmittance = vec3(1.0); // 参考光影只叠加散射，不额外压暗表面。
    return ogxAtmoSimpleScattering(model, camera, viewDirection, scaled, scaled, normalize(uSunDirection)) * 2.0; // 与 iterationT 相同。
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

// 天空环境光：iterationT 的天光形状，由太阳方向的天空辐照度加一个朝上的权重构成。
vec3 lightingSkyAmbient(vec3 normal, float roughness) // 返回漫反射天光。
{
    vec3 sun = normalize(uSunDirection); // 太阳方向。
    float sdotn = dot(normal, normalize(sun + vec3(0.0, 1.0, 0.0))); // 法线与抬高的太阳方向。
    vec3 skylight = lightingSunSkyLight() * (sdotn * 0.35 + 0.65); // 天空辐照度带一点方向性。
    skylight += lightingSunLight() * ((normal.y * 0.4 + 0.6) * 0.025); // 太阳侧的补光，与 iterationT 的 SkyLighting 相同。
    return skylight * 0.2; // iterationT 在室外把天光压到两成，剩余亮度由全局光反弹补。
}

#endif // 共用参数结束。
