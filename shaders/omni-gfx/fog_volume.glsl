/*
生成文件：体积雾模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；Minecraft 光影由 `/omni-gfx/fog_volume.glsl` 引入，
    `rendering/fog/volumetric.glsl` 只把选项、天气、群系与阴影贴图换成参数。
可复制示例：先填好一层雾的参数，再调用一次 `ogxVolumetricFog` 完成整段步进。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明与水下手持光属于可选的宿主能力，用两个钩子宏留给效果层注入；不定义时是完全的空操作。
    钩子宏沿用旧名字：宿主在包含本文件之前就定义它们，改名需要同时改宿主，收益只有名字统一。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
*/
#ifndef OGX_FOG_VOLUME_INCLUDED
#define OGX_FOG_VOLUME_INCLUDED

// 可选的雾照明钩子：效果层在包含本文件前定义，不定义时完全为空。
// 它接受当前雾点、这一步的吸收量、累计颜色与提前结束标记，由宿主决定是否采样体积光。
#ifndef GFX_FOG_LPV_STEP
#define GFX_FOG_LPV_STEP(fog_pos, integral, accum, done)
#endif

// 可选的水下手持光钩子：效果层把物品光采样接到这里，不定义时不加任何光。
#ifndef GFX_UNDERWATER_HAND_LIGHT
#define GFX_UNDERWATER_HAND_LIGHT(world_pos) vec3(0.0)
#endif

// 雾密度、相位与粉末效应来自雾模块；暴风噪声来自天气，波法线与阴影坐标来自水面与阴影模块。
#include "/omni-gfx/fog.glsl"
#include "/omni-gfx/weather.glsl"
#include "/omni-gfx/shadow.glsl"
#include "/omni-gfx/water.glsl"
#include "/omni-gfx/color.glsl"
// 一帧体积雾需要的相机、光照与天气参数。
struct OgxFogMedia
{
    vec3 camera_position; // 相机绝对世界位置。
    vec3 light_vector; // 指向光源的单位向量。
    vec3 light_color; // 直射光色。
    vec3 sky_color; // 天空环境光色。
    vec3 storm_color; // 暴风染色。
    vec3 biome_color; // 群系雾色。
    vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
    mat4 shadow_view; // 阴影相机视图。
    mat4 shadow_projection; // 阴影相机投影。
    vec2 cloud_shadow_screen; // 云影贴图所在画面的尺寸。
    vec2 cloud_shadow_texel; // 云影贴图画面的像素大小。
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

// 云影贴图的三次采样：取红通道，与云影写入端同一套模糊。
// 四次双线性采样合成十六像素三次模糊，纹理读取次数只有逐像素方案的四分之一。
float ogxFogCloudBicubic(sampler2D source, vec2 coord, vec2 texSize)
{
    vec2 texel = 1.0 / texSize; // 一个纹素的大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    vec2 p = floor(coord); // 整数像素。
    vec2 f = coord - p; // 小数偏移。
    vec2 ff = f * f; // 偏移平方。
    vec4 w0; // 前两个权重。
    vec4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    vec4 s = w0 + w1; // 每对权重和。
    vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return mix(mix(textureLod(source, c.yw, 0.0).x, textureLod(source, c.xw, 0.0).x, m.x),
                mix(textureLod(source, c.yz, 0.0).x, textureLod(source, c.xz, 0.0).x, m.x), m.y); // 四次采样合成模糊。
}

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float ogxFogCloudShadow(vec3 worldPos, OgxFogMedia media, sampler2D cloudShadowTex, bool fadeByAngle)
{
    vec2 coord = worldPos.xz - media.light_vector.xz * ((worldPos.y + media.camera_position.y) / media.light_vector.y); // 沿光方向投到云影贴图平面。
    coord = coord * (1.0 / media.cloud_shadow_range) + 0.5; // 换成零到一的贴图坐标。
    float cloudShadow = 1.0 - media.wetness; // 雨天默认的云影底值。
    if (ogxEqual(ogxSaturate(coord), coord)) // 只有落在贴图范围内才采样。
    {
        float shadowTexSize = floor(min(media.cloud_shadow_screen.y * 0.45, media.cloud_shadow_tex_size)); // 云影贴图实际边长。
        vec2 shadowTexel = media.cloud_shadow_screen - coord * shadowTexSize; // 贴图贴在画面右上角，坐标要翻转。
        vec2 fade = ogxSaturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
        cloudShadow = mix(cloudShadow, ogxFogCloudBicubic(cloudShadowTex, shadowTexel * media.cloud_shadow_texel, media.cloud_shadow_screen), fade.x * fade.y); // 三次采样并淡出。
    }
    if (fadeByAngle) // 太阳越贴地云影越淡。
    {
        float fadeAngle = smoothstep(0.06, 0.18, abs(media.light_vector.y)); // 光方向越平越淡。
        cloudShadow = mix(1.0 - media.wetness, cloudShadow, fadeAngle * fadeAngle); // 按淡出权重混合。
    }
    return ((media.rain_shadow - 1.0) * media.wetness + 1.0) * cloudShadow + (media.wetness - media.rain_shadow * media.wetness); // 晴天与雨天两档之间插值。
}

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
float ogxFogStormDensity(vec3 worldPos, OgxFogMedia media, sampler2D noiseTexture)
{
    vec3 scroll = vec3(media.storm_time, 0.0, media.storm_time) * 15.0; // 随时间在横纵方向滚动。
    vec3 samplePos = (worldPos * vec3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量。
    float noise = 1.0 - ogxStormNoise(samplePos, noiseTexture, 512.0); // 取反，让噪声高的地方雾更浓。
    float heightFade = exp2(-0.06 * max(worldPos.y - (media.storm_height + 3.0), 0.0)); // 起始高度以上缓慢变淡。
    float denseCloud = noise * noise * mix(1.0, heightFade, media.snow_storm); // 噪声雾团。
    return 1.0 + denseCloud + media.daily_fog; // 低空层与噪声雾团相加。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
vec3 ogxFogLightning(vec3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
    vec3 boltPos = vec3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
    float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return vec3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
float ogxFogDensity(vec3 fogPos, vec3 wind, bool noisy, float heightA, float heightB, float falloff, float timeMidnight, sampler2D noiseTexture)
{
    return noisy
        ? ogxFogDensityNoise(fogPos, wind, heightA, heightB, falloff, timeMidnight, noiseTexture)
        : ogxFogDensityHeight(fogPos, heightA, heightB, falloff, timeMidnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
float ogxFogLightMarch(inout vec3 fogPos, vec3 wind, OgxFogMedia media, bool noisy, float heightA, float heightB, float falloff, sampler2D noiseTexture, int steps, float stepLength)
{
    float lightingDensity = 0.0; // 沿光方向累计的密度。
    for (int i = 0; i < steps; i++, fogPos += media.light_vector * stepLength, stepLength *= 1.5) // 沿光方向步进，步长逐步放大。
    {
        lightingDensity += ogxFogDensity(fogPos, wind, noisy, heightA, heightB, falloff, media.time_midnight, noiseTexture) * stepLength; // 累加这一段密度。
    }
    return lightingDensity; // 返回累计密度。
}

// 体积雾主体：沿视线步进，同时沿光方向估遮挡，累加雾色与阳光散射。
// `dither` 是这一步的抖动；`volumetricLighting` 由效果层按体积光照开关选择单级或多级散射。
void ogxVolumetricFog(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir, OgxFogMedia media,
    sampler2D noiseTexture, sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0,
    sampler2D cloudShadowTex, bool noisy, bool volumetricLighting, bool useCloudShadow, bool useStained, bool useSolidShadow, bool indoor, bool caveMode,
    float heightA, float heightB, float falloff, float sunAbsorption, int steps, int lightSteps, float lightStepLength, float dither,
    out float transmittance)
{
    float timeFactor = media.time_factor * (noisy ? 1.0 : media.time_midnight * 2.0 + 1.0); // 仅高度衰减模式夜晚雾更浓。
    vec3 start = startPos + media.camera_position; // 起点换成绝对世界坐标。
    vec3 end = endPos + media.camera_position; // 终点同样换成绝对世界坐标。
    vec3 rayVector = end - start; // 从起点到终点的矢量。
    float rayLength = length(rayVector) / float(steps) * 0.23979; // 每步的基础长度，零点二三九七九是原程序的归一化常数。
    vec3 shadowStart = ogxShadowScreenPos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
    vec3 shadowEnd = ogxShadowScreenPos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
    vec3 shadowVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。
    vec3 stormWind = noisy ? vec3(-1.0, -0.05, 0.6) * media.wind_time : vec3(0.0); // 团雾按风移动。
    transmittance = 1.0; // 透射率从全透开始。
    float fogDensity = 0.0; // 环境雾累计量。
    float rayDensity = 0.0; // 阳光散射累计量。
    vec3 lightningFog = vec3(0.0); // 闪电点亮的空气。
    vec3 lpvFog = vec3(0.0); // 雾照明累计量，由宏注入。
    vec3 translucent = vec3(0.0); // 透过半透明方块的染色光。
    for (int i = 0; i < steps; i++) // 沿视线逐步前进。
    {
        float exponential = pow(11.0, (float(i) + dither) / float(steps)); // 指数步长因子。
        float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
        float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度。
        vec3 fogPos = start + stepLength * rayVector; // 这一步的雾采样位置。
        vec3 shadowPos = shadowStart + stepLength * shadowVector; // 这一步的阴影图坐标。
        vec3 lightningStep = ogxFogLightning(fogPos - media.camera_position, media, 150.0, -15.0); // 闪电照亮空气。
        float biomeDistance = length((stepLength * rayVector).xz); // 这一步相对起点的水平距离。
        float biomeEnvelope = min(max(1.0 - biomeDistance / 256.0, 0.0) * 2.0, 1.0); // 二百五十六米内替换最明显。
        float densityScale = mix(media.density_scale, media.biome_height, media.biome_coverage * biomeEnvelope); // 群系高度雾密度。
        if (noisy) densityScale = mix(media.density_scale, media.biome_cloudy, media.biome_coverage * biomeEnvelope); // 团雾取多云那套。
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
            vec4 phases = ogxMultiScatteringPhases(dot(worldDir, media.light_vector)); // 一次算好四级相位。
            float order = 1.0; // 多级相位的权重。
            for (int j = 0; j < 4; j++, order *= 0.5) stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 四级散射加权求和。
            stepRayDensity *= ogxLegacyPowder(absorption, lightingAbsorption, dot(worldDir, media.light_vector)); // 乘粉末效应。
        }
        else // 单级前向相位。
        {
            stepRayDensity = ogxMiePhase(0.5, dot(worldDir, media.light_vector)) * 0.7 + 0.05;
        }
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, media.shadow_bias); // 阴影图坐标补上边缘压缩。
        float shadow = 1.0; // 这一点受不受阳光。
        vec3 shadowColorSample = vec3(1.0); // 该点半透明染色。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 坐标落在阴影图内才采样。
        {
            ivec2 shadowTexel = ivec2(shadowPos.xy * media.shadow_map_resolution); // 换成阴影图纹素。
            float solidDepth = useSolidShadow ? texelFetch(shadowDepth1, shadowTexel, 0).x : texelFetch(shadowDepth0, shadowTexel, 0).x; // 按显卡能力选深度图。
            shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
            if (useStained) // 半透明染色。
            {
                float transparentDepth = texelFetch(shadowDepth0, shadowTexel, 0).x; // 读半透明深度。
                shadowColorSample = ogxGammaToLinear(texelFetch(shadowColor0, shadowTexel, 0).rgb); // 读半透明颜色。
                float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。
                shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
                shadow -= transparentShadow; // 从受光里扣掉半透明遮挡。
            }
        }
        float cloudShadow = 1.0; // 云影默认不压暗。
        if (useCloudShadow) cloudShadow = ogxFogCloudShadow(fogPos - media.camera_position, media, cloudShadowTex, false); // 读该点云影。
        float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
        stepRayDensity *= integral; // 散射量按吸收缩放。
        if (useCloudShadow) // 有云影时雾色也按云影压暗。
        {
            stepRayDensity *= mix(cloudShadow, 1.0, media.wetness * 0.1 + 0.03); // 散射按云影压暗。
            fogDensity += integral * mix(cloudShadow, 1.0, media.wetness * 0.3 + 0.7); // 环境雾按云影压暗。
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
        GFX_FOG_LPV_STEP(fogPos, integral, lpvFog, lpvDone) // 由效果层决定是否采样体积光。
        if (lpvDone) break; // 走出体积就不再步进。
    }
    vec3 skylight = media.sky_color; // 雾的环境色以天光为主。
    vec3 skySun = media.light_color * 0.03; // 雾里的一点点直射光。
    skylight += skySun * (1.0 + (1.0 - media.global_cloud_shadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
    skylight = mix(skylight, skySun, media.wetness * 0.7); // 雨天偏向直射色。
    vec3 fogColor = skylight * fogDensity; // 环境雾色。
    vec3 rayColor = media.light_color * rayDensity; // 阳光散射色。
    fogColor *= media.storm_color; // 暴风染色。
    rayColor *= media.storm_color; // 阳光散射同样染色。
    vec3 biomeTint = mix(vec3(1.0), media.biome_color, media.biome_coverage); // 群系雾色。
    fogColor *= biomeTint; // 环境雾染成群系色。
    rayColor *= biomeTint; // 阳光散射同样染色。
    rayColor += media.light_color * translucent; // 叠上透过半透明方块的染色光。
    fogColor *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
    rayColor *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
    if (!useCloudShadow) rayColor *= mix(media.global_cloud_shadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
    if (!indoor) // 体积雾随天空光等级衰减。
    {
        fogColor *= media.eye_skylight; // 环境雾按天空光衰减。
        if (caveMode) rayColor *= media.eye_skylight; // 洞穴模式下散射也衰减。
        lightningFog *= media.eye_skylight; // 闪电来自天空。
        transmittance = mix(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
    }
    color = transmittance * color + fogColor + rayColor + lightningFog + lpvFog; // 场景色先被吸收，再叠上雾与散射。
}

// 水下焦散：从当前位置向上找水面，按波法线折射后取交点距离，距离越近光柱越强。
// 为什么单独一份：它与水面焦散的三乘三采样用途不同，这里只要一份范围很窄的值来收窄光柱。
float ogxUnderwaterCaustics(vec3 worldPos, vec3 shadowLightVector, sampler2D normalTexture,
    vec2 pixelSize, vec2 screenExtent, float maxResolution, float refractIor)
{
    vec3 lookupCenter = worldPos; // 从当前位置向上找波面。
    lookupCenter.y += 1.0; // 抬高一米到水面上方。
    vec3 wavesNormal = ogxWavesNormalFromTex(lookupCenter, shadowLightVector, normalTexture,
        pixelSize, screenExtent, maxResolution, refractIor).xzy; // 读波法线并换到竖直轴朝上的坐标。
    vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal, 1.0); // 竖直光线被波面折射后的方向。
    vec3 collisionPoint = lookupCenter - refractVector / refractVector.y; // 光线与水平面的交点。
    float dist = distance(collisionPoint, worldPos); // 交点到当前点的距离。
    return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}

// 水下体积雾：沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向、云影、相机位置、阴影图与波法线图；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
vec3 ogxUnderwaterFog(vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow,
    vec3 cameraOffset, vec3 shadowLightVector, sampler2D shadowDepth0, sampler2D shadowDepth1,
    bool useSolidShadow, mat4 shadowView, mat4 shadowProjection, float shadowBias,
    sampler2D waveNormalTexture, vec2 pixelSize, vec2 screenExtent, float causticsResolution, float causticsIor,
    vec3 sunColor, float sunIntensity, float underwaterDensity, int steps, float dither,
    bool waterAbsorption, float waterDensity, float handLightScale)
{
    const float range = 40.0; // 光柱的累积范围。
    float startDist = length(startPos); // 起点到相机的距离。
    if (startDist > range) return vec3(0.0); // 起点已经在范围外，不画光柱。
    endPos = mix(worldDir * range, endPos, step(length(endPos), range)); // 终点超过范围就截断到范围内。
    float rayDist = distance(startPos, endPos); // 这条射线在范围里的长度。
    vec3 rayDir = (endPos - startPos) / rayDist; // 射线方向。
    float stepLength = range / float(steps); // 每段长度。
    vec3 result = vec3(0.0); // 累加的光柱颜色。
    vec3 handFog = vec3(0.0); // 累加的手持光颜色。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float rayLength = (i + dither) * stepLength; // 当前位置，起点加抖动量。
        vec3 rayPos = startPos + rayDir * rayLength; // 相机相对世界位置。
        if (startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停止。
        vec3 shadowPos = ogxShadowScreenPosDistorted(rayPos + cameraOffset, shadowView, shadowProjection, shadowBias); // 投到阴影图，含边缘压缩。
        float shadowDepth = useSolidShadow ? textureLod(shadowDepth1, shadowPos.xy, 0.0).x : textureLod(shadowDepth0, shadowPos.xy, 0.0).x; // 按显卡能力选深度图。
        vec3 shadow = vec3(step(shadowPos.z + 1e-06, shadowDepth)); // 受光则由深度图判定。
        rayLength += startDist; // 距离补上起点偏移。
        float caustics = ogxUnderwaterCaustics(rayPos + cameraOffset, shadowLightVector, waveNormalTexture,
            pixelSize, screenExtent, causticsResolution, causticsIor); // 该点焦散强度。
        shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
        shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
        if (waterAbsorption) shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * waterDensity)); // 红衰减最快，光柱因此偏蓝。
        result += shadow; // 累加。
        vec3 handLight = GFX_UNDERWATER_HAND_LIGHT(rayPos); // 手持光源在该点留下的光，由效果层注入。
        if (waterAbsorption) handLight *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * waterDensity)); // 与光柱同一套分波段吸收。
        handFog += handLight; // 累加。
    }
    result *= range / float(steps); // 取平均。
    vec3 lightVector = refract(shadowLightVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
    float lightDotView = dot(lightVector, worldDir); // 光方向与视线的夹角。
    float phase = ogxMiePhase(0.7, lightDotView); // 前向相位，正对阳光时更亮。
    result *= sunColor * (0.04 * phase * sunIntensity * underwaterDensity); // 乘直射光色、相位与强度。
    if (waterAbsorption) result *= vec3(0.2, 0.65, 1.0); // 有水下雾时把光柱染成水色。
    result *= globalCloudShadow; // 按全局云影压暗。
    result += handFog * (range / float(steps)) * handLightScale; // 手持光不随阳光相位与云影变化，最后叠上。
    return result; // 返回光柱颜色。
}

#endif
