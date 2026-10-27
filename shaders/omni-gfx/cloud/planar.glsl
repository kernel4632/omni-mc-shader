/*
生成文件：平面云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库平面云模块：在固定高度的一层云上取样、朝太阳求遮挡并合成空气透视。
调用位置：需要 iterationT 风格平面云的程序；Minecraft 光影由 `/omni-gfx/cloud/planar.glsl` 引入。
可复制示例：
    ogxPlanarClouds(color, worldDir, camera, dither, transmittance, ...);
设计原因与取舍：
    参考实现把噪声、风、云量与大气常数都写成全局宏。库把每一类输入显式传入，
    函数体仍保留原来的球面求交、四次光照步进与两次相函数，不改变画面手感。
    大气透视复用查表模型，避免在云模块里复制一套散射公式。
*/
#ifndef OGX_PLANAR_INCLUDED
#define OGX_PLANAR_INCLUDED

// 云模块提供平面密度，数学提供球面求交与相函数，大气模块提供空气透视。
#include "/omni-gfx/cloud/cloud.glsl"
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/atmosphere/model.glsl"
// 平面云合成：沿视线与云层求交，取密度与朝阳光照，再把云和空气透视叠到背景。
// `cloudTransmittance` 进来时是上一层的剩余透过率，返回时已乘上这一层。
void ogxPlanarClouds(inout vec3 color, vec3 worldDir, vec3 camera, float dither,
    inout float cloudTransmittance, OgxAtmosphereModel model, sampler3D lut, vec3 cameraWorldPos,
    float timeSeconds, float cloudSpeed, float ftcOffset, vec3 worldShadowVector,
    vec3 colorShadowlight, vec3 colorSkylight, float wetness, float cloudAltitude, float cloudNoiseScale,
    float cloudCoverage, sampler2D noiseTexture, vec3 worldSunVector, vec3 rayleighTint,
    vec3 mieTint, float nightBrightness, float skyBrightness, bool volumetricClouds)
{
    float planetRadius = model.bottom_radius * 1e3; // 模型半径从公里换成米。
    vec3 rayStartPos = vec3(0.0, planetRadius + cameraWorldPos.y, 0.0); // 相机在行星正上方。
    vec2 hit = ogxRaySphereIntersection(rayStartPos, worldDir, planetRadius + cloudAltitude); // 与云层求交。
    float intersection = hit.y; // 取远交点。
    if (intersection > 0.0) // 视线确实穿过云层才继续。
    {
        float wind = 2.5 * (timeSeconds * cloudSpeed + 10.0 * ftcOffset); // 风随时间推进。
        vec2 windDirection = vec2(-wind, wind * 0.2); // 风向略微斜向。
        float VdotL = dot(worldDir, worldShadowVector) * 0.5 + 0.5; // 视线与光的夹角映射到零到一。
        vec3 centerPosition = worldDir * intersection; // 云层交点。
        vec2 samplePosition = centerPosition.xz + cameraWorldPos.xz; // 交点换到世界水平坐标。
        cloudTransmittance = min(ogxPlanarDensity(samplePosition, windDirection, noiseTexture,
            cloudNoiseScale, cloudCoverage) * cloudTransmittance * 40.0, 0.9); // 这一层的遮挡。
        if (volumetricClouds) cloudTransmittance *= 1.0 - wetness; // 体积雾开启时雨天更薄。
        if (cloudTransmittance > 1e-5) // 有遮挡才做光照与合成。
        {
            float stepLength = mix(150.0, 0.0, worldShadowVector.z); // 朝太阳的步长，太阳越低步长越小。
            samplePosition += stepLength * dither * worldShadowVector.xy; // 起点按抖动错开。
            float lightingDepth = 0.0; // 朝太阳的遮挡量。
            for (int i = 0; i < 4; i++) // 四次光照步进。
            {
                lightingDepth += ogxPlanarLightingDensity(samplePosition, windDirection, noiseTexture,
                    cloudNoiseScale, cloudCoverage) * stepLength; // 累加这一步的密度。
                samplePosition += worldShadowVector.xy * stepLength; // 前进。
                stepLength *= 1.5; // 步长逐次放大。
            }
            float sunlightEnergy = 1.0 / (lightingDepth + 1.0); // 遮挡越少阳光越强。
            float powderFactor = exp2(-cloudTransmittance * (worldShadowVector.y * 5.0 + 0.5)); // 粉末效应。
            sunlightEnergy *= ogxMiePhase(powderFactor * 0.8, VdotL * 0.5 + 0.5); // 第一次相函数。
            sunlightEnergy *= ogxMiePhase(0.9, VdotL) * 0.4 + 1.0; // 第二次相函数补前向散射。
            vec3 cloudColor = colorShadowlight * (sunlightEnergy * 6.0); // 云被太阳照亮的颜色。
            float skylightEnergy = exp2(-cloudTransmittance * 0.15); // 天空光穿过的比例。
            cloudColor += colorSkylight * (skylightEnergy * 0.2); // 加天空环境光。
            cloudTransmittance *= exp2(-(length(centerPosition) + 2e3) * 4e-5); // 远处云逐渐融进空气。
            vec3 atmoPoint = camera + centerPosition * 0.001; // 交点从米换成公里。
            vec3 transmittance; // 相机到交点的透过率。
            vec3 aerialPerspective = ogxAtmoSkyRadianceToPoint(model, lut, camera, atmoPoint, worldSunVector,
                -worldSunVector, false, rayleighTint, mieTint, nightBrightness, 0.0, skyBrightness, transmittance); // 空气透视。
            color *= (1.0 - cloudTransmittance); // 背景先按云的遮挡压暗。
            color += (cloudColor * transmittance + aerialPerspective) * cloudTransmittance; // 再叠云与空气透视。
        }
    }
}

#endif
