/*
Omni 通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；Minecraft 光影由 `/omni-gfx/fog/volume.glsl` 引入，
    `shaders/effects/shared/fog/volumetric.glsl` 只把选项、天气、群系与阴影贴图换成参数。
可复制示例：先填好一层雾的参数，再调用一次 `ogxVolumetricFog` 完成整段步进。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明与水下手持光属于可选的宿主能力，用两个钩子宏留给效果层注入；不定义时是完全的空操作。
    钩子宏名是库的公开接口，效果层在包含本文件前定义；要改名必须同时改宿主，当前保留稳定名字。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
    算法按内容分成云影、暴风、闪电、单步、主体、水下、严格入口与下界烟八段，子文件放在同名文件夹内；
    主文件保留结构体、钩子和主体步进，打开文件就能看到完整步进顺序。
*/
#ifndef OGX_FOG_VOLUME_INCLUDED
#define OGX_FOG_VOLUME_INCLUDED

// 可选的雾照明钩子：效果层在包含本文件前定义，不定义时完全为空。
// 它接受当前雾点、这一步的吸收量、累计颜色与提前结束标记，由宿主决定是否采样体积光。
#ifndef OGX_FOG_LPV_STEP
#define OGX_FOG_LPV_STEP(fog_pos, integral, accum, done)
#endif

// 可选的水下手持光钩子：效果层把物品光采样接到这里，不定义时不加任何光。
#ifndef OGX_UNDERWATER_HAND_LIGHT
#define OGX_UNDERWATER_HAND_LIGHT(world_pos) float3(0.0)
#endif

// 雾密度、相位与粉末效应来自雾模块；暴风噪声来自天气，波法线与阴影坐标来自水面与阴影模块。
#include "fog.slang"
// 天气提供云量、风、降雨与雷暴强度。
#include "../weather/weather.slang"
// 闪电提供光柱照明，体积雾的闪电步进与云共用同一条曲线。
#include "../weather/lightning.slang"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "../shadow/shadow.slang"
// 阴影贴图提供边缘压缩，WSR 空气雾与水下体积按参考实现复用同一坐标变换。
#include "../shadow/map.slang"
// 水面提供吸收、波法线、泡沫与折射。
#include "../water.slang"
// 颜色提供伽马、线性转换与色调映射。
#include "../common/color.slang"
// 采样提供白噪声、蓝噪声与低差异序列。
#include "../common/sampling.slang"

// 一帧体积雾需要的相机、光照与天气参数。
struct OgxFogMedia
{
    float3 camera_position; // 相机绝对世界位置。
    float3 light_vector; // 指向光源的单位向量。
    float3 light_color; // 直射光色。
    float3 sky_color; // 天空环境光色。
    float3 storm_color; // 暴风染色。
    float3 biome_color; // 群系雾色。
    float3 lightning_position; // 闪电光柱中心，相机相对坐标。
    float4x4 shadow_view; // 阴影相机视图。
    float4x4 shadow_projection; // 阴影相机投影。
    float2 cloud_shadow_screen; // 云影贴图所在画面的尺寸。
    float2 cloud_shadow_texel; // 云影贴图画面的像素大小。
    float wetness; // 零到一的湿润度。
    float eye_skylight; // 天空光平滑值。
    float time_midnight; // 午夜强度。
    float time_factor; // 雾的时间因子。
    float density_scale; // 时段与每日天气给出的密度标度。
    float base_density; // 基础密度，已由效果层按远裁剪面或远景距离换算。
    float storm_strength; // 雪暴与沙暴的总强度。
    float snow_storm; // 雪暴强度，决定暴风雾是否随高度变淡。
    float daily_fog; // 每日天气的匀雾密度。
    float storm_density; // 暴风雾浓度选项。
    float storm_height; // 暴风雾起始高度。
    float storm_time; // 暴风噪声的滚动时间，单位秒。
    float wind_time; // 团雾随风移动的时间，已按云速换算。
    float global_cloud_shadow; // 整个场景共用的粗粒度云影。
    float shadow_map_resolution; // 阴影图像素边长。
    float shadow_bias; // 阴影坐标边缘压缩强度。
    float cloud_shadow_range; // 云影贴图覆盖范围，米。
    float cloud_shadow_tex_size; // 云影贴图最大边长。
    float rain_shadow; // 雨天的云影底值。
    float biome_coverage; // 落在已启用群系内的程度。
    float biome_height; // 群系高度衰减雾密度。
    float biome_cloudy; // 群系团雾密度。
    float lightning_intensity; // 闪电事件强度。
    float lightning_strength; // 闪电亮度选项。
    float sky_intensity; // 天光强度选项。
    float sun_intensity; // 阳光强度选项。
    float fog_density_option; // 环境雾强度选项。
    float sun_density_option; // 散射强度选项。
};

// 云影贴图的三次采样与世界坐标投影，具体实现在子文件。
#include "volume/shadow.slang"

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
// 为什么纵向压扁再乘一百：暴风的云团在水平方向拉得很长，压扁后噪声才会形成横向雪带。
float ogxFogStormDensity(float3 worldPos, OgxFogMedia media, Sampler2D noiseTexture)
{
    float3 scroll = float3(media.storm_time, 0.0, media.storm_time) * 15.0; // 随时间在横纵方向滚动。
    float3 samplePos = (worldPos * float3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量。
    float noise = 1.0 - ogxStormNoise(samplePos, noiseTexture, 512.0); // 取反，让噪声高的地方雾更浓。
    float heightFade = exp2(-0.06 * max(worldPos.y - (media.storm_height + 3.0), 0.0)); // 起始高度以上缓慢变淡。
    float denseCloud = noise * noise * lerp(1.0, heightFade, media.snow_storm); // 噪声雾团。
    return 1.0 + denseCloud + media.daily_fog; // 低空层与噪声雾团相加。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
// 光柱算法只在数学模块维护一份，这里把雾参数换成显式输入，避免再写一套衰减曲线。
float3 ogxFogLightning(float3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    return ogxLightningGlow(relativePos, media.lightning_position, media.lightning_intensity,
        media.lightning_strength, lightDistance, falloff); // 光柱计算只在数学模块一份。
}

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
// 为什么用一个布尔开关：两种密度模型共享后续步进，分开写会让主体循环复制两份。
float ogxFogDensity(float3 fogPos, float3 wind, bool noisy, float heightA, float heightB, float falloff, float timeMidnight, Sampler2D noiseTexture)
{
    return noisy
        ? ogxFogDensityNoise(fogPos, wind, heightA, heightB, falloff, timeMidnight, noiseTexture)
        : ogxFogDensityHeight(fogPos, heightA, heightB, falloff, timeMidnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
// 步长放大而不是等距：靠近采样点的遮挡更重要，远处用大步长节省循环。
float ogxFogLightMarch(inout float3 fogPos, float3 wind, OgxFogMedia media, bool noisy, float heightA, float heightB, float falloff, Sampler2D noiseTexture, int steps, float stepLength)
{
    float lightingDensity = 0.0; // 沿光方向累计的密度。
    for (int i = 0; i < steps; i++, fogPos += media.light_vector * stepLength, stepLength *= 1.5) // 沿光方向步进，步长逐步放大。
    {
        lightingDensity += ogxFogDensity(fogPos, wind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture) * stepLength; // 累加这一段密度。
    }
    return lightingDensity; // 返回累计密度。
}

// 阴影采样：按是否支持实心阴影选择深度图，再按是否开启半透明染色扣掉染色遮挡。
// 返回受光系数；`shadowColorSample` 交回该点的半透明颜色，供后续散射染色。
float ogxFogShadowAt(OgxFogMedia media, float3 shadowPos, Sampler2D shadowDepth0, Sampler2D shadowDepth1,
    Sampler2D shadowColor0, bool useStained, bool useSolidShadow, out float3 shadowColorSample)
{
    shadowColorSample = float3(1.0); // 默认不染色。
    if (!ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) || shadowPos.z >= 1.0) return 1.0; // 坐标在图外时保持全亮。
    int2 shadowTexel = int2(shadowPos.xy * media.shadow_map_resolution); // 换成阴影图纹素。
    float solidDepth = useSolidShadow ? shadowDepth1.Load(int3(shadowTexel, 0)).x : shadowDepth0.Load(int3(shadowTexel, 0)).x; // 按显卡能力选深度图。
    float shadow = step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
    if (!useStained) return shadow; // 不染色时只交回受光。
    float transparentDepth = shadowDepth0.Load(int3(shadowTexel, 0)).x; // 读半透明深度。
    shadowColorSample = ogxGammaToLinear(shadowColor0.Load(int3(shadowTexel, 0)).rgb); // 读半透明颜色。
    float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。
    shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
    return shadow - transparentShadow; // 从受光里扣掉半透明遮挡。
}

// 体积雾主体：沿视线步进，同时沿光方向估遮挡，累加雾色与阳光散射。
// `dither` 是这一步的抖动；`volumetricLighting` 由效果层按体积光照开关选择单级或多级散射。
void ogxVolumetricFog(inout float3 color, float3 startPos, float3 endPos, float3 worldDir, OgxFogMedia media,
    Sampler2D noiseTexture, Sampler2D shadowDepth0, Sampler2D shadowDepth1, Sampler2D shadowColor0,
    Sampler2D cloudShadowTex, bool noisy, bool volumetricLighting, bool useCloudShadow, bool useStained, bool useSolidShadow, bool indoor, bool caveMode,
    float heightA, float heightB, float falloff, float sunAbsorption, int steps, int lightSteps, float lightStepLength, float dither,
    out float transmittance)
{
    float timeFactor = media.time_factor * (noisy ? 1.0 : media.time_midnight * 2.0 + 1.0); // 仅高度衰减模式夜晚雾更浓。
    float3 start = startPos + media.camera_position; // 起点换成绝对世界坐标。
    float3 end = endPos + media.camera_position; // 终点同样换成绝对世界坐标。
    float3 rayVector = end - start; // 从起点到终点的矢量。
    float rayLength = length(rayVector) / float(steps) * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。
    float3 shadowStart = ogxShadowScreenPos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
    float3 shadowEnd = ogxShadowScreenPos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
    float3 shadowVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。
    float3 stormWind = noisy ? float3(-1.0, -0.05, 0.6) * media.wind_time : float3(0.0); // 团雾按风移动。
    transmittance = 1.0; // 透射率从全透开始。
    float fogDensity = 0.0; // 环境雾累计量。
    float rayDensity = 0.0; // 阳光散射累计量。
    float3 lightningFog = float3(0.0); // 闪电点亮的空气。
    float3 lpvFog = float3(0.0); // 雾照明累计量，由宏注入。
    float3 translucent = float3(0.0); // 透过半透明方块的染色光。
    for (int i = 0; i < steps; i++) // 沿视线逐步前进。
    {
        float exponential = pow(11.0, (float(i) + dither) / float(steps)); // 指数步长因子。
        float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
        float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度。
        float3 fogPos = start + stepLength * rayVector; // 这一步的雾采样位置。
        float3 shadowPos = shadowStart + stepLength * shadowVector; // 这一步的阴影图坐标。
        float3 lightningStep = ogxFogLightning(fogPos - media.camera_position, media, 150.0, -15.0); // 闪电照亮空气。
        float biomeDistance = length((stepLength * rayVector).xz); // 这一步相对起点的水平距离。
        float biomeEnvelope = min(max(1.0 - biomeDistance / 256.0, 0.0) * 2.0, 1.0); // 二百五十六米内替换最明显。
        float densityScale = lerp(media.density_scale, media.biome_height, media.biome_coverage * biomeEnvelope); // 群系高度雾密度。
        if (noisy) densityScale = lerp(media.density_scale, media.biome_cloudy, media.biome_coverage * biomeEnvelope); // 团雾取多云那套。
        float density = ogxFogDensity(fogPos, stormWind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture); // 这一点的雾密度。
        density = (density * densityScale + media.base_density) * timeFactor; // 乘密度标度与时间因子。
        density += ogxFogStormDensity(fogPos, media, noiseTexture) * media.storm_strength * media.storm_density; // 暴风额外浓雾。
        float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。
        float stepRayDensity = 0.0; // 这一步的阳光散射量。
        if (volumetricLighting) // 沿阳光方向估吸收。
        {
            float lightingDensity = ogxFogLightMarch(fogPos, stormWind, media, noisy, heightA, heightB, falloff, noiseTexture, lightSteps, lightStepLength); // 沿光方向累计密度。
            lightingDensity = (lightingDensity * sunAbsorption * densityScale + media.base_density) * timeFactor; // 乘吸收率与密度标度。
            float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。
            float4 phases = ogxMultiScatteringPhases(dot(worldDir, media.light_vector)); // 一次算好四级相位。
            float order = 1.0; // 多级相位的权重。
            for (int j = 0; j < 4; j++, order *= 0.5) stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 四级散射加权求和。
            stepRayDensity *= ogxLegacyPowder(absorption, lightingAbsorption, dot(worldDir, media.light_vector)); // 乘粉末效应。
        }
        else // 单级前向相位。
        {
            stepRayDensity = ogxMiePhase(0.5, dot(worldDir, media.light_vector)) * 0.7 + 0.05;
        }
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, media.shadow_bias); // 阴影图坐标补上边缘压缩。
        float3 shadowColorSample; // 该点半透明染色。
        float shadow = ogxFogShadowAt(media, shadowPos, shadowDepth0, shadowDepth1, shadowColor0, useStained, useSolidShadow, shadowColorSample); // 阴影与染色。
        float cloudShadow = 1.0; // 云影默认不压暗。
        if (useCloudShadow) cloudShadow = ogxFogCloudShadow(fogPos - media.camera_position, media, cloudShadowTex, false); // 读该点云影。
        float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
        stepRayDensity *= integral; // 散射量按吸收缩放。
        if (useCloudShadow) // 有云影时雾色也按云影压暗。
        {
            stepRayDensity *= lerp(cloudShadow, 1.0, media.wetness * 0.1 + 0.03); // 散射按云影压暗。
            fogDensity += integral * lerp(cloudShadow, 1.0, media.wetness * 0.3 + 0.7); // 环境雾按云影压暗。
        }
        else // 没有云影时直接累加。
        {
            fogDensity += integral; // 直接累加。
        }
        rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。
        if (useStained) translucent += stepRayDensity * shadowColorSample; // 累加染色散射。
        transmittance *= absorption; // 透射率逐步衰减。
        lightningFog += lightningStep * integral; // 闪电按吸收量累加。
        bool lpvDone = false; // 雾照明走出体积时提前结束。
        OGX_FOG_LPV_STEP(fogPos, integral, lpvFog, lpvDone) // 由效果层决定是否采样体积光。
        if (lpvDone) break; // 走出体积就不再步进。
    }
    float3 skylight = media.sky_color; // 雾的环境色以天光为主。
    float3 skySun = media.light_color * 0.03; // 雾里的一点点直射光。
    skylight += skySun * (1.0 + (1.0 - media.global_cloud_shadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
    skylight = lerp(skylight, skySun, media.wetness * 0.7); // 雨天偏向直射色。
    float3 fogColor = skylight * fogDensity; // 环境雾色。
    float3 rayColor = media.light_color * rayDensity; // 阳光散射色。
    fogColor *= media.storm_color; // 暴风染色。
    rayColor *= media.storm_color; // 阳光散射同样染色。
    float3 biomeTint = lerp(float3(1.0), media.biome_color, media.biome_coverage); // 群系雾色。
    fogColor *= biomeTint; // 环境雾染成群系色。
    rayColor *= biomeTint; // 阳光散射同样染色。
    rayColor += media.light_color * translucent; // 叠上透过半透明方块的染色光。
    fogColor *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
    rayColor *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
    if (!useCloudShadow) rayColor *= lerp(media.global_cloud_shadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
    if (!indoor) // 体积雾随天空光等级衰减。
    {
        fogColor *= media.eye_skylight; // 环境雾按天空光衰减。
        if (caveMode) rayColor *= media.eye_skylight; // 洞穴模式下散射也衰减。
        lightningFog *= media.eye_skylight; // 闪电来自天空。
        transmittance = lerp(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
    }
    color = transmittance * color + fogColor + rayColor + lightningFog + lpvFog; // 场景色先被吸收，再叠上雾与散射。
}

// 水下焦散与光柱，具体实现在子文件。
#include "volume/underwater.slang"
// 严格参考签名的雾与水下光柱入口，具体实现在子文件。
#include "volume/exact.slang"
// 下界羽流、雾霭与顶部烟，具体实现在子文件。
#include "volume/nether.slang"

// 参考签名的空气雾入口：按 Eclipse 的指数步进累积雾色与大气透视。
// 参考参数在前，相机、阴影、密度场与选项资源追加在后。
float4 ogxFogVolumeMarchReference(float3 origin, float3 endPos, float2 dither, float3 lightColor,
    float3 ambientColor, float3 averagedAmbient, int sampleCount, Sampler3D densityTexture,
    Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection, float3 cameraOffset,
    float3 cameraWorldPos, float3 sunVector, float farPlane, float vlSamples, float cloudShadow,
    float hazeAmount, float seaLevel, float caveDetection, float eyeBrightness, float3 rayleighCoefficients,
    float3 mieCoefficients, float distortA, float distortB, float distortK, float shadowResolution,
    float4 lightningBoltPosition, float3 lightningEffect)
{
    if (length(origin - endPos) < 0.001) return float4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    float mult = vlSamples / float(sampleCount) * 1.15; // 参考按体积光样本数缩放密度。
    float3 dVWorld = endPos - origin - cameraOffset; // 相机相对的射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    float3 rayDir = normalize(endPos - origin); // 射线方向。
    float maxLength = min(rayLength, farPlane) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到远裁剪面。
    float dL = length(dVWorld) / 8.0; // 每段长度。
    const float expFactor = 11.0; // 指数步长。
    float3 color = float3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 总透过率。
    float3 atmosphereAbsorbance = float3(1.0); // 大气透过率。
    float SdotV = dot(sunVector, rayDir); // 阳光与视线夹角。
    float sunPhase = ogxEndLightFalloff(SdotV) * 5.0; // 太阳相位。
    float skyPhase = 0.5 + pow(1.0 - pow(1.0 - clamp(rayDir.y * 0.5 + 0.5, 0.0, 1.0), 2.0), 5.0) * 2.0; // 天空相位。
    float rayL = ogxRayleighPhaseElek(SdotV); // 瑞利相位。
    float3 rC = float3(rayleighCoefficients.x * 1e-6, rayleighCoefficients.y * 1e-5, rayleighCoefficients.z * 1e-5); // 瑞利系数按参考量级缩放。
    float3 mC = mieCoefficients * 1e-6; // 米氏系数按参考量级缩放。
    float3 skyLightPhased = ambientColor * skyPhase; // 天空光乘相位。
    float3 lightSourcePhased = lightColor * sunPhase; // 直射光乘相位。
    float inACave = 1.0 - caveDetection; // 洞穴里减少雾。
    float lightLevelZero = pow(clamp(eyeBrightness / 240.0, 0.0, 1.0), 3.0); // 天空光等级的立方。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither.y) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.x) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        float3 progressP = cameraOffset + d * dVWorld + origin; // 相机相对位置。
        float3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        float3 fragposition = ogxMatrixMulPoint(shadowView, progressP) + ogxMatrixTranslation(shadowView); // 阴影相机空间坐标。
        fragposition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragposition + shadowProjection[3].xyz; // 按投影对角线缩放。
        float distortFactor = ogxShadowDistortFactor(fragposition.xy, distortA, distortB, distortK); // 阴影边缘压缩。
        float3 shadowPos = float3(fragposition.xy * distortFactor, fragposition.z); // 压缩后的阴影坐标。
        float3 sh = float3(1.0); // 受光系数。
        if (abs(shadowPos.x) < 1.0 - 0.5 / shadowResolution && abs(shadowPos.y) < 1.0 - 0.5 / shadowResolution) // 落在阴影图内才采样。
        {
            shadowPos = shadowPos * float3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 换成零到一坐标。
            sh = float3(shadowTexture.SampleLevel(shadowPos.xy, 0.0).x); // 只读不透明深度。
        }
        sh *= cloudShadow; // 参考的云影由宿主预计算成标量。
        float fogDensity = densityTexture.SampleLevel(progressW, 0.0).r * inACave * mult; // 三维密度场与体积光缩放。
        float fogVolumeCoeff = exp(-fogDensity * dd * dL); // 本段透过率。
        float3 indirectLight = skyLightPhased; // 天空散射。
        float3 directLight = lightSourcePhased * sh; // 太阳散射。
        float3 lightning = ogxLightningFog(progressP, lightningBoltPosition, lightningEffect); // 参考的闪电照明。
        float3 lighting = directLight + indirectLight + 0.0025 * lightning; // 本段照明。
        color += (lighting - lighting * fogVolumeCoeff) * totalAbsorbance; // 累积散射。
        totalAbsorbance *= lerp(1.0, fogVolumeCoeff, lightLevelZero); // 洞穴里减弱吸收。
        if (totalAbsorbance < 0.01) break; // 足够浓就停。
        float planetVolume = smoothstep(1.0 - exp(clamp(1.0 - length(progressP) / (16.0 * 150.0), 0.0, 1.0) * -10.0), 0.0, progressP.y - 500.0); // 行星遮挡的体积权重。
        float2 airCoef = exp2(-max(progressW.y - seaLevel, 0.0) / float2(8.0e3, 1.2e3) * float2(6.0, 7.0)) * 192.0 * hazeAmount * planetVolume; // 空气密度。
        float3 rL = rC * airCoef.x; // 瑞利部分。
        float3 m = mC * (airCoef.y + min(hazeAmount * 1.25, 1.0)); // 米氏部分。
        float3 airDensity = rL + m; // 总空气密度。
        float3 atmosphereVolumeCoeff = exp(-airDensity * dd * dL); // 大气透过率。
        float3 atmosphere = (lightSourcePhased * sh * (rayL * rL + sunPhase * m) + averagedAmbient * airDensity * (lightLevelZero * 0.99 + 0.01)) * inACave; // 大气散射色。
        color += (atmosphere - atmosphere * atmosphereVolumeCoeff) / (airDensity + 1e-6) * atmosphereAbsorbance; // 累积大气透视。
        atmosphereAbsorbance *= atmosphereVolumeCoeff; // 累积大气透过率。
    }
    return float4(color, totalAbsorbance); // 交回雾。
}

#endif
