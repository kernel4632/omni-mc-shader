/*
生成文件：体积雾模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；Minecraft 光影由 `/omni-gfx/fog/volume.glsl` 引入，
    `shaders/effects/shared/fog/volumetric.glsl` 只把选项、天气、群系与阴影贴图换成参数。
可复制示例：`vec4 fog = ogxVolumetricFog(media, worldPos, cameraOffset, cameraWorld, 1.0, 16, 8.0, 160.0, noiseTex, shadowTex);` 先填好一层雾的参数，再调用一次完成整段步进。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明与水下手持光属于可选的宿主能力，用两个钩子宏留给效果层注入；不定义时是完全的空操作。
    钩子宏名是库的公开接口，效果层在包含本文件前定义；要改名必须同时改宿主，当前保留稳定名字。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
    算法按内容分成云影、水下、严格入口与下界烟四段，子文件放在同名文件夹内；
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
#define OGX_UNDERWATER_HAND_LIGHT(world_pos) vec3(0.0)
#endif

// 雾密度、相位与粉末效应来自雾模块；暴风噪声来自天气，波法线与阴影坐标来自水面与阴影模块。
#include "/omni-gfx/fog/fog.glsl"
// 天气提供云量、风、降雨与雷暴强度。
#include "/omni-gfx/weather/weather.glsl"
// 闪电提供光柱照明，体积雾的闪电步进与云共用同一条曲线。
#include "/omni-gfx/weather/lightning.glsl"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "/omni-gfx/shadow/shadow.glsl"
// 阴影贴图提供边缘压缩，WSR 空气雾与水下体积按参考实现复用同一坐标变换。
#include "/omni-gfx/shadow/map.glsl"
// 水面提供吸收、波法线、泡沫与折射。
#include "/omni-gfx/water.glsl"
// 颜色提供伽马、线性转换与色调映射。
#include "/omni-gfx/common/color.glsl"
// 采样提供白噪声、蓝噪声与低差异序列。
#include "/omni-gfx/common/sampling.glsl"
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

// 云影贴图的三次采样与世界坐标投影，具体实现在子文件。
// 子文件：fog/volume/shadow.slang。
/* 体积雾的云影：把世界坐标投到云影贴图，并用四次双线性采样合成十六像素三次模糊；由 `fog/volume.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`float shadow = ogxFogCloudShadow(worldPos, media, cloudShadowTex, true);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

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

// 暴风浓雾密度，具体实现在子文件。

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
// 为什么纵向压扁再乘一百：暴风的云团在水平方向拉得很长，压扁后噪声才会形成横向雪带。
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
// 光柱算法只在数学模块维护一份，这里把雾参数换成显式输入，避免再写一套衰减曲线。
vec3 ogxFogLightning(vec3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    return ogxLightningGlow(relativePos, media.lightning_position, media.lightning_intensity,
        media.lightning_strength, lightDistance, falloff); // 光柱计算只在数学模块一份。
}

// 雾密度：仅高度衰减或团雾，参数由效果层按选项给出。
// 为什么用一个布尔开关：两种密度模型共享后续步进，分开写会让主体循环复制两份。
float ogxFogDensity(vec3 fogPos, vec3 wind, bool noisy, float heightA, float heightB, float falloff, float timeMidnight, sampler2D noiseTexture)
{
    return noisy
        ? ogxFogDensityNoise(fogPos, wind, heightA, heightB, falloff, timeMidnight, noiseTexture)
        : ogxFogDensityHeight(fogPos, heightA, heightB, falloff, timeMidnight); // 两种密度模型。
}

// 沿阳光方向估这一段雾对光的吸收：步长逐步放大，近处权重更高。
// 步长放大而不是等距：靠近采样点的遮挡更重要，远处用大步长节省循环。
float ogxFogLightMarch(inout vec3 fogPos, vec3 wind, OgxFogMedia media, bool noisy, float heightA, float heightB, float falloff, sampler2D noiseTexture, int steps, float stepLength)
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
float ogxFogShadowAt(OgxFogMedia media, vec3 shadowPos, sampler2D shadowDepth0, sampler2D shadowDepth1,
    sampler2D shadowColor0, bool useStained, bool useSolidShadow, out vec3 shadowColorSample)
{
    shadowColorSample = vec3(1.0); // 默认不染色。
    if (!ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) || shadowPos.z >= 1.0) return 1.0; // 坐标在图外时保持全亮。
    ivec2 shadowTexel = ivec2(shadowPos.xy * media.shadow_map_resolution); // 换成阴影图纹素。
    float solidDepth = useSolidShadow ? texelFetch(shadowDepth1, shadowTexel, 0).x : texelFetch(shadowDepth0, shadowTexel, 0).x; // 按显卡能力选深度图。
    float shadow = step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
    if (!useStained) return shadow; // 不染色时只交回受光。
    float transparentDepth = texelFetch(shadowDepth0, shadowTexel, 0).x; // 读半透明深度。
    shadowColorSample = ogxGammaToLinear(texelFetch(shadowColor0, shadowTexel, 0).rgb); // 读半透明颜色。
    float transparentShadow = step(transparentDepth, shadowPos.z) * shadow; // 半透明遮挡量。
    shadowColorSample *= transparentShadow; // 颜色按遮挡量缩放。
    return shadow - transparentShadow; // 从受光里扣掉半透明遮挡。
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
        vec3 shadowColorSample; // 该点半透明染色。
        float shadow = ogxFogShadowAt(media, shadowPos, shadowDepth0, shadowDepth1, shadowColor0, useStained, useSolidShadow, shadowColorSample); // 阴影与染色。
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
        OGX_FOG_LPV_STEP(fogPos, integral, lpvFog, lpvDone) // 由效果层决定是否采样体积光。
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

// 水下焦散与光柱，具体实现在子文件。
// 子文件：fog/volume/underwater.slang。
/* 水下体积雾：焦散取样与光柱步进，输出汇聚的蓝色光柱；由 `fog/volume.slang` 内联引入。
可复制示例：`float caustics = ogxUnderwaterCaustics(worldPos, shadowLightVector, normalTexture, pixelSize, screenExtent, maxResolution, 1.2);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

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
        vec3 handLight = OGX_UNDERWATER_HAND_LIGHT(rayPos); // 手持光源在该点留下的光，由效果层注入。
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

// 严格参考签名入口，具体实现在子文件。

// WSR 水下体积：按 Eclipse 参考逐行移植水吸收、焦散、方向光与闪电照明。
// 参考参数在前，相机、阴影、噪声与选项资源追加在后；默认分支不读宿主全局量。

vec4 ogxUnderwaterVolumeReference(vec3 origin, vec3 endPos, vec2 dither, vec3 ambient,
    vec3 lightSource, vec3 lpv, vec3 waterAbsorption, float dirtAmount, vec3 dirtColor,
    float waterAltitude, float sunElevation, float bubbleScale, float time, float waveSpeed,
    float patchyBlend, sampler2D noiseTexture, vec3 sunVector, vec3 cameraOffset, vec3 cameraWorldPos,
    float farPlane, float cloudShadow, sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection,
    float distortA, float distortB, float distortK, float shadowResolution, vec4 lightningPosition,
    float lightningFlash)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有水体。
    const int sampleCount = 3; // 参考实现的固定三步。
    float lightSourceCheck = float(sunElevation > 1e-5) * 2.0 - 1.0; // 太阳在地平线上时翻转云影方向。
    vec3 scatterCoef = dirtAmount * dirtColor / 3.14; // 参考的脏水散射系数。
    vec3 dVWorld = endPos - origin - cameraOffset; // 相机相对的射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    float maxLength = min(rayLength, farPlane) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到远裁剪面。
    vec3 absorbance = vec3(1.0); // 累积吸收。
    vec3 vL = vec3(0.0); // 累积颜色。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float VdotL = dot(sunVector, rayDir); // 视线与阳光方向的夹角。
    float phase = ogxEndLightFalloff(VdotL) * 5.0; // 参考的雾相位。
    float thing = -normalize(dVWorld).y; // 垂直方向。
    thing = clamp(thing + 0.333, 0.0, 1.0); // 参考的形状偏移。
    thing = pow(1.0 - pow(1.0 - thing, 2.0), 2.0) * 15.0; // 参考的形状重整。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定三步。
    {
        float d = (pow(expFactor, float(i) + dither.x) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.y) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progressP = cameraOffset + d * dVWorld; // 相机相对位置。
        vec3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        float distanceFromWaterSurface = max(-(progressW.y - waterAltitude), 0.0); // 到水面的距离。
        vec3 fragposition = ogxMatrixMulPoint(shadowView, progressP) + ogxMatrixTranslation(shadowView); // 阴影相机空间坐标。
        fragposition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragposition + shadowProjection[3].xyz; // 按投影对角线缩放。
        float distortFactor = ogxShadowDistortFactor(fragposition.xy, distortA, distortB, distortK); // 阴影边缘压缩。
        vec3 spPos = vec3(fragposition.xy * distortFactor, fragposition.z); // 压缩后的阴影坐标。
        vec3 pos = vec3(spPos.xy * distortFactor, spPos.z); // 参考在这里再压一次。
        vec3 sh = vec3(1.0); // 受光系数。
        if (abs(pos.x) < 1.0 - 0.5 / shadowResolution && abs(pos.y) < 1.0 - 0.5 / shadowResolution) // 落在阴影图内才采样。
        {
            pos = pos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 换成零到一坐标。
            sh = vec3(textureLod(shadowTexture, pos.xy, 0.0).x); // 只读不透明深度。
        }
        sh *= cloudShadow; // 参考的云影由宿主预计算成标量。
        float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / bubbleScale, 0.0, 1.0)); // 气泡形状。
        float caustics = max(max(ogxWaterBumpCaustics(progressW, sunVector, -(progressW.y - waterAltitude), time, waveSpeed, patchyBlend, noiseTexture), phase * 0.5) * mix(0.5, 1.5, bubble), phase); // 参考的焦散与相位混合。
        vec3 sunAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface / abs(sunVector.y))); // 阳光穿过水面的吸收。
        vec3 waterAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface + thing)); // 水体吸收。
        vec3 direct = lightSource * sh * phase * caustics * sunAbsorbance; // 直射。
        vec3 indirect = ambient; // 间接光。
        float horizontalDist = length(progressP.xz - lightningPosition.xz); // 到闪电的水平距离。
        if (horizontalDist < 250.0 && lightningPosition.w > 0.0) // 闪电在附近时照亮水体。
        {
            float lightningIntensity = exp(-horizontalDist * 0.02) * lightningFlash; // 距离衰减。
            indirect = mix(indirect, vec3(1.3, 1.5, 3.0) * sh, lightningIntensity); // 冷色闪光。
        }
        indirect *= waterAbsorbance; // 间接光也被水体吸收。
        vec3 light = (indirect + direct + lpv) * scatterCoef; // 总光。
        vec3 volumeCoeff = exp(-waterAbsorption * length(dd * dVWorld)); // 本段吸收。
        vL += (light - light * volumeCoeff) / waterAbsorption * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积吸收。
    }
    return vec4(vL, dot(absorbance, vec3(0.333333))); // 交回水体颜色与透过率。
}

// 严格参考签名的雾与水下光柱入口，具体实现在子文件。
// 子文件：fog/volume/exact.slang。
/* 体积雾的严格入口：按 iterationT 默认路径逐行移植的雾与水下光柱；由 `fog/volume.slang` 内联引入。
可复制示例：`vec4 fog = ogxVolumetricFogExact(media, worldPos, cameraOffset, cameraWorld, 1.0, 16, 8.0, 160.0, noiseTex, shadowTex, shadowView, shadowProj, 2048.0, 1.0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 严格参考签名的体积雾入口：按 iterationT 默认的 VFOG_NOISE_TYPE=0 路径逐行移植。
// 参考参数在前，相机、阴影矩阵与画质资源追加在后；不读取宿主全局量。
// 为什么单独一份而不是转调通用入口：通用入口还包含团雾、暴风、闪电、群系与体积光，
// 那些分支会引入参考默认路径没有的采样次数；严格对照要求采样顺序与常数逐项一致。
void ogxVolumetricFogExact(inout vec3 color, vec3 startPos, vec3 endPos, vec3 worldDir,
    float globalCloudShadow, float fogTimeFactor, out float transmittance, OgxFogMedia media,
    sampler2D shadowDepth0, float farPlane, float densityOption, float baseDensityOption,
    float heightA, float heightB, float falloff, float sunAbsorption, int steps, int lightSteps,
    float lightStepLength, float shadowBias, sampler2D noiseTexture, vec2 pixelCoord, int frameCounter)
{
    fogTimeFactor *= media.time_midnight * 2.0 + 1.0; // 参考在高度雾模式下按午夜强度加浓。
    vec2 blueNoise = fract(texelFetch(noiseTexture, ivec2(pixelCoord) % 64, 0).xy + vec2(1.61803398875, 1.32471795724) * float(frameCounter % 64)); // 参考的时序蓝噪声，两个黄金比例常数照原样保留。
    float noise = blueNoise.y; // 参考取蓝噪声的 y 分量作为步进抖动。
    float VdotL = dot(worldDir, media.light_vector); // 视线与阳光方向的夹角。
    float rSteps = 1.0 / float(steps); // 步数的倒数，避免循环内重复除法。
    vec3 start = startPos - media.camera_position; // 参考用视图逆矩阵平移把世界位置转回相机相对坐标。
    vec3 end = endPos - media.camera_position; // 终点同样转到相机相对坐标。
    vec3 rayVector = end - start; // 相机相对的射线。
    float rayLength = length(rayVector) * rSteps * 0.23979; // 每步基础长度，零点二三九七九照参考保留。
    vec3 shadowStart = ogxShadowScreenPos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
    vec3 shadowEnd = ogxShadowScreenPos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
    vec3 shadowRayVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。
    start += media.camera_position; // 补回相机位置后才是绝对世界坐标。
    float baseDensity = baseDensityOption * (media.time_midnight * 0.1 + 0.05) / max(farPlane, 100.0); // 远裁剪面越小基础雾越浓。
    baseDensity *= media.eye_skylight; // 室内或洞穴里按天空光减弱。
    vec4 phases = ogxMultiScatteringPhases(VdotL); // 四级散射相位，权重逐次减半。
    transmittance = 1.0; // 透射率从全透开始。
    float fogDensity = 0.0; // 环境雾累计量。
    float rayDensity = 0.0; // 阳光散射累计量。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float exponential = pow(11.0, (i + noise) * rSteps); // 指数步长因子。
        float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
        float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度。
        vec3 fogPos = start + stepLength * rayVector; // 这一步的世界位置。
        vec3 shadowPos = shadowStart + stepLength * shadowRayVector; // 这一步的阴影图坐标。
        float density = ogxFogDensityHeight(fogPos, heightA, heightB, falloff, media.time_midnight); // 两次高度层之间的指数密度。
        density = (density * densityOption + baseDensity) * fogTimeFactor; // 乘密度选项与雾时间因子。
        float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。
        float lightingDensity = 0.0; // 沿阳光方向累计的密度。
        float lightingStepLength = lightStepLength; // 光方向步长从参考值开始。
        for (int j = 0; j < lightSteps; j++) // 沿阳光方向估遮挡。
        {
            lightingDensity += ogxFogDensityHeight(fogPos, heightA, heightB, falloff, media.time_midnight) * lightingStepLength; // 累加这一段密度。
            fogPos += media.light_vector * lightingStepLength; // 向太阳方向前进。
            lightingStepLength *= 1.5; // 步长逐步放大，远处权重更高。
        }
        lightingDensity = (lightingDensity * sunAbsorption * densityOption + baseDensity) * fogTimeFactor; // 乘吸收率与基础密度。
        float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。
        float stepRayDensity = 0.0; // 这一步的阳光散射量。
        float order = 1.0; // 四级相位的权重。
        for (int j = 0; j < 4; j++) // 四级散射加权求和。
        {
            stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 当前相位按权重累加。
            order *= 0.5; // 下一级权重减半。
        }
        stepRayDensity *= ogxLegacyPowder(absorption, lightingAbsorption, VdotL); // 乘粉末效应。
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, shadowBias); // 补上阴影图边缘压缩。
        float shadow = 1.0; // 这一点受不受阳光。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 坐标落在阴影图内才采样。
        {
            float solidDepth = textureLod(shadowDepth0, shadowPos.xy, 0.0).x; // 只读不透明深度。
            shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
        }
        float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
        stepRayDensity *= integral; // 散射量按吸收缩放。
        fogDensity += integral; // 环境雾累加。
        rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。
        transmittance *= absorption; // 透射率逐步衰减。
    }
    vec3 skylight = media.sky_color; // 雾的环境色以天光为主。
    vec3 skySunLight = media.light_color * 0.03; // 雾里的一点点直射光。
    skylight += skySunLight * (1.0 + (1.0 - globalCloudShadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
    skylight = mix(skylight, skySunLight, media.wetness * 0.7); // 雨天偏向直射色。
    vec3 fogColor = skylight * fogDensity; // 环境雾色。
    vec3 rayColor = media.light_color * rayDensity; // 阳光散射色。
    fogColor *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
    rayColor *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
    rayColor *= mix(globalCloudShadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
    fogColor *= media.eye_skylight; // 环境雾按天空光衰减。
    transmittance = mix(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
    color = transmittance * color + fogColor + rayColor; // 场景色先被吸收，再叠上雾与散射。
}

// 严格参考签名的水下体积雾：范围、步数、阴影与焦散顺序照 iterationT 原程序。
// 参考的相机、阴影矩阵、波法线图与水色全部由调用方给出，循环内不读宿主全局量。
vec3 ogxUnderwaterFogExact(vec3 startPos, vec3 endPos, vec3 worldDir,
    float globalCloudShadow, vec3 cameraOffset, vec3 shadowLightVector, sampler2D shadowDepth0,
    mat4 shadowView, mat4 shadowProjection,
    float shadowBias, sampler2D waveNormalTexture, vec2 pixelSize, vec2 screenExtent,
    float causticsResolution, float causticsIor, vec3 sunColor, float sunIntensity,
    float underwaterDensity, int steps, sampler2D noiseTexture, vec2 pixelCoord, float frameCounter,
    bool waterAbsorption, float waterDensity)
{
    const float range = 40.0; // 光柱的累积范围。
    float startDist = length(startPos); // 起点到相机的距离。
    if (startDist > range) return vec3(0.0); // 起点已经在范围外。
    endPos = mix(worldDir * range, endPos, step(length(endPos), range)); // 终点截断到范围内。
    float rayDist = distance(startPos, endPos); // 范围内射线长度。
    vec3 rayDir = (endPos - startPos) / rayDist; // 射线方向。
    float stepLength = range / float(steps); // 每段长度。
    float noise = ogxBlueNoiseTemporal(noiseTexture, ivec2(pixelCoord), int(frameCounter)).y; // 参考的蓝噪声抖动。
    vec3 result = vec3(0.0); // 累加的光柱颜色。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float rayLength = (i + noise) * stepLength; // 当前位置，含抖动量。
        vec3 rayPos = startPos + rayDir * rayLength; // 相机相对世界位置。
        if (startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停。
        vec3 shadowPos = ogxShadowScreenPosDistorted(rayPos + cameraOffset, shadowView, shadowProjection, shadowBias); // 投到阴影图。
        float shadowDepth = textureLod(shadowDepth0, shadowPos.xy, 0.0).x; // 默认路径读半透明深度图。
        vec3 shadow = vec3(step(shadowPos.z + 1e-06, shadowDepth)); // 受光判定。
        rayLength += startDist; // 距离补上起点偏移。
        float caustics = ogxUnderwaterCaustics(rayPos + cameraOffset, shadowLightVector, waveNormalTexture,
            pixelSize, screenExtent, causticsResolution, causticsIor); // 该点焦散强度。
        shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
        shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
        if (waterAbsorption) shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * waterDensity)); // 分波段吸收。
        result += shadow; // 累加光柱。
    }
    result *= range / float(steps); // 取平均。
    vec3 lightVector = refract(shadowLightVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光进入水面时弯折。
    float lightDotView = dot(lightVector, worldDir); // 光方向与视线夹角。
    float phase = ogxMiePhase(0.7, lightDotView); // 前向相位。
    result *= sunColor * (0.04 * phase * sunIntensity * underwaterDensity); // 乘直射光色与强度。
    if (waterAbsorption) result *= vec3(0.2, 0.65, 1.0); // 有水下雾时染成水色。
    result *= globalCloudShadow; // 按全局云影压暗。
    return result; // 交回光柱颜色。
}

// 下界三段体积雾，具体实现在子文件。

// 下界羽流、雾霭与顶部烟，具体实现在子文件。
// 子文件：fog/volume/nether.slang。
/* 下界的体积雾：羽流、雾霭与顶部烟在同一条视线上分开累加；由 `fog/volume.slang` 内联引入。
可复制示例：`vec4 fog = ogxNetherVolumetricFog(rayDir, cameraOffset, cameraWorld, noiseTex, 1.0, 1.0, hazeColor, 1.0, 16, 8.0, 160.0, farPlane);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// Eclipse 下界三段体积雾：羽流、雾霭与顶部烟在同一条视线上分开累加。
// 为什么分三段：羽流发光、雾霭只加色不吸光、顶部烟贴天花板，三者的密度来源与混合方式都不同。
// `cameraOffset` 是相机相对世界的原点，`cameraWorldPos` 是绝对世界位置，雾噪声需要绝对坐标。
// `maxDist` 是步进距离上限，`farPlane` 是羽流随距离淡出用的远裁剪面，两者在参考实现里不是同一个值。
// `hazeColor` 由调用方按当前下界雾色给出，`outputScale` 把散射换算到目标管线单位。
vec4 ogxNetherVolumetricFog(vec3 rayDirection, vec3 cameraOffset, vec3 cameraWorldPos,
    float startDist, float endDist, float ditherA, float ditherB, int samples, float expFactor, float maxDist, float farPlane,
    float plumeDensityScale, float hazeDensityScale, float ceilingDensityScale, vec3 hazeColor,
    float outputScale, float time, sampler2D noiseTexture)
{
    endDist = min(endDist, maxDist); // 最远只步进到参考实现的距离上限。
    float rayLength = endDist - startDist; // 这一段视线的长度。
    if (rayLength <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0); // 空段或反向段直接返回。
    vec3 segment = rayDirection * rayLength; // 整段的相机相对世界向量。
    float dL = rayLength; // 光学厚度的段长。
    vec3 base = cameraOffset + rayDirection * startDist; // 相机相对世界里的起点。
    vec3 color = vec3(0.0); // 累加的散射色。
    float absorbance = 1.0; // 剩余透射率，从全透开始。
    for (int i = 0; i < samples; i++) // 沿这一段逐步前进。
    {
        float d = (pow(expFactor, (float(i) + ditherB) / float(samples)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 指数步长在段上的位置。
        float dd = pow(expFactor, (float(i) + ditherA) / float(samples)) * log(expFactor) / float(samples) / (expFactor - 1.0); // 这一步的厚度权重。
        vec3 relPos = base + d * segment; // 采样点的相机相对位置。
        float dist = length(relPos); // 到相机的距离。
        vec3 worldPos = relPos + cameraWorldPos; // 绝对世界位置，体积噪声要它。
        float densityVol = ogxNetherFogCloudVolume(worldPos, time, noiseTexture); // 这一点的原始体积密度。
        float clearArea = 1.0 - min(max(1.0 - dist / 24.0, 0.0), 1.0); // 相机二十四米内淡出。
        float plume = min(densityVol * pow(min(max(100.0 - worldPos.y, 0.0) / 30.0, 1.0), 4.0), pow(clamp(1.0 - dist / farPlane, 0.0, 1.0), 5.0)); // 越低越浓、越远越淡。
        plume *= plumeDensityScale; // 乘羽流密度选项。
        float plumeCoeff = exp(-plume * dd * dL); // 羽流吸收掉的光。
        vec3 plumeLight = vec3(1.0, 0.4, 0.2) * 0.25 * exp(-15.0 * densityVol) * (clearArea * clearArea * 0.9 + 0.1); // 暖橙色，密度高处压暗。
        color += (plumeLight - plumeLight * plumeCoeff) * absorbance; // 叠上羽流散射。
        absorbance *= plumeCoeff; // 透射率下降。
        float hazeDensity = 0.001 * hazeDensityScale; // 很低的均匀密度。
        float hazeCoeff = exp(-hazeDensity * dd * dL); // 雾霭吸收。
        color += (hazeColor - hazeColor * hazeCoeff) * absorbance; // 只加散射，不回乘透射率。
        float ceilingDensity = 0.001 * pow(min(max(worldPos.y - 40.0, 0.0) / 50.0, 1.0), 3.0) * ceilingDensityScale; // 越高越浓。
        float ceilingCoeff = exp(-ceilingDensity * dd * dL); // 顶部烟吸收。
        vec3 ceilingSmoke = vec3(0.1); // 固定灰烟颜色。
        color += (ceilingSmoke - ceilingSmoke * ceilingCoeff) * (absorbance * 0.5 + 0.5); // 半强度叠加。
        absorbance *= ceilingCoeff; // 透射率继续下降。
    }
    return vec4(color * outputScale, absorbance); // 返回换算后的散射色与剩余透射率。
}

// 参考签名的空气雾入口：按 Eclipse 的指数步进累积雾色与大气透视。
// 参考参数在前，相机、阴影、密度场与选项资源追加在后。
vec4 ogxFogVolumeMarchReference(vec3 origin, vec3 endPos, vec2 dither, vec3 lightColor,
    vec3 ambientColor, vec3 averagedAmbient, int sampleCount, sampler3D densityTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, vec3 cameraOffset,
    vec3 cameraWorldPos, vec3 sunVector, float farPlane, float vlSamples, float cloudShadow,
    float hazeAmount, float seaLevel, float caveDetection, float eyeBrightness, vec3 rayleighCoefficients,
    vec3 mieCoefficients, float distortA, float distortB, float distortK, float shadowResolution,
    vec4 lightningBoltPosition, vec3 lightningEffect)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    float mult = vlSamples / float(sampleCount) * 1.15; // 参考按体积光样本数缩放密度。
    vec3 dVWorld = endPos - origin - cameraOffset; // 相机相对的射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float maxLength = min(rayLength, farPlane) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到远裁剪面。
    float dL = length(dVWorld) / 8.0; // 每段长度。
    const float expFactor = 11.0; // 指数步长。
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 总透过率。
    vec3 atmosphereAbsorbance = vec3(1.0); // 大气透过率。
    float SdotV = dot(sunVector, rayDir); // 阳光与视线夹角。
    float sunPhase = ogxEndLightFalloff(SdotV) * 5.0; // 太阳相位。
    float skyPhase = 0.5 + pow(1.0 - pow(1.0 - clamp(rayDir.y * 0.5 + 0.5, 0.0, 1.0), 2.0), 5.0) * 2.0; // 天空相位。
    float rayL = ogxRayleighPhaseElek(SdotV); // 瑞利相位。
    vec3 rC = vec3(rayleighCoefficients.x * 1e-6, rayleighCoefficients.y * 1e-5, rayleighCoefficients.z * 1e-5); // 瑞利系数按参考量级缩放。
    vec3 mC = mieCoefficients * 1e-6; // 米氏系数按参考量级缩放。
    vec3 skyLightPhased = ambientColor * skyPhase; // 天空光乘相位。
    vec3 lightSourcePhased = lightColor * sunPhase; // 直射光乘相位。
    float inACave = 1.0 - caveDetection; // 洞穴里减少雾。
    float lightLevelZero = pow(clamp(eyeBrightness / 240.0, 0.0, 1.0), 3.0); // 天空光等级的立方。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither.y) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.x) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progressP = cameraOffset + d * dVWorld + origin; // 相机相对位置。
        vec3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        vec3 fragposition = ogxMatrixMulPoint(shadowView, progressP) + ogxMatrixTranslation(shadowView); // 阴影相机空间坐标。
        fragposition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragposition + shadowProjection[3].xyz; // 按投影对角线缩放。
        float distortFactor = ogxShadowDistortFactor(fragposition.xy, distortA, distortB, distortK); // 阴影边缘压缩。
        vec3 shadowPos = vec3(fragposition.xy * distortFactor, fragposition.z); // 压缩后的阴影坐标。
        vec3 sh = vec3(1.0); // 受光系数。
        if (abs(shadowPos.x) < 1.0 - 0.5 / shadowResolution && abs(shadowPos.y) < 1.0 - 0.5 / shadowResolution) // 落在阴影图内才采样。
        {
            shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 换成零到一坐标。
            sh = vec3(textureLod(shadowTexture, shadowPos.xy, 0.0).x); // 只读不透明深度。
        }
        sh *= cloudShadow; // 参考的云影由宿主预计算成标量。
        float fogDensity = textureLod(densityTexture, progressW, 0.0).r * inACave * mult; // 三维密度场与体积光缩放。
        float fogVolumeCoeff = exp(-fogDensity * dd * dL); // 本段透过率。
        vec3 indirectLight = skyLightPhased; // 天空散射。
        vec3 directLight = lightSourcePhased * sh; // 太阳散射。
        vec3 lightning = ogxLightningFog(progressP, lightningBoltPosition, lightningEffect); // 参考的闪电照明。
        vec3 lighting = directLight + indirectLight + 0.0025 * lightning; // 本段照明。
        color += (lighting - lighting * fogVolumeCoeff) * totalAbsorbance; // 累积散射。
        totalAbsorbance *= mix(1.0, fogVolumeCoeff, lightLevelZero); // 洞穴里减弱吸收。
        if (totalAbsorbance < 0.01) break; // 足够浓就停。
        float planetVolume = smoothstep(1.0 - exp(clamp(1.0 - length(progressP) / (16.0 * 150.0), 0.0, 1.0) * -10.0), 0.0, progressP.y - 500.0); // 行星遮挡的体积权重。
        vec2 airCoef = exp2(-max(progressW.y - seaLevel, 0.0) / vec2(8.0e3, 1.2e3) * vec2(6.0, 7.0)) * 192.0 * hazeAmount * planetVolume; // 空气密度。
        vec3 rL = rC * airCoef.x; // 瑞利部分。
        vec3 m = mC * (airCoef.y + min(hazeAmount * 1.25, 1.0)); // 米氏部分。
        vec3 airDensity = rL + m; // 总空气密度。
        vec3 atmosphereVolumeCoeff = exp(-airDensity * dd * dL); // 大气透过率。
        vec3 atmosphere = (lightSourcePhased * sh * (rayL * rL + sunPhase * m) + averagedAmbient * airDensity * (lightLevelZero * 0.99 + 0.01)) * inACave; // 大气散射色。
        color += (atmosphere - atmosphere * atmosphereVolumeCoeff) / (airDensity + 1e-6) * atmosphereAbsorbance; // 累积大气透视。
        atmosphereAbsorbance *= atmosphereVolumeCoeff; // 累积大气透过率。
    }
    return vec4(color, totalAbsorbance); // 交回雾。
}

#endif
