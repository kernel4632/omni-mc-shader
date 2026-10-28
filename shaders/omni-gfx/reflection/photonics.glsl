/*
生成文件：Photonics 反射模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库Photonics 反射模块：命中面着色、方块光、云影与半透明反射合成。
调用位置：Eclipse Photonics 风格的体素反射；由 `/omni-gfx/reflection/photonics.glsl` 引入。
可复制示例：
    vec4 color = ogxPhotonicsReflection(job, hits, count, dir, normal, noise, mask, tint, ids, colors, direct, ambient, indirect, 1.0, 0.0, 0.0, 0.0, 0.0, torch, lpv, hand, lpvPos, 64.0, 1.0, 2.0, true, 128.0, 1.0, 1.0, sun, opaque, translucent, tintTex, view, proj, 2048.0, 0.9, 0.9, 1.0, 1.0, 8, true, false, 1.0, 1.0, true);
设计原因与取舍：
    半透明命中逐层染色，不透明命中再合成；阴影、方块光与自发光全部走显式参数，采样顺序与参考实现相同。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。Photonics 反射目前只被库内高光模块间接引用，没有顶层画面入口。
*/
#ifndef OGX_REFLECTION_PHOTONICS_INCLUDED
#define OGX_REFLECTION_PHOTONICS_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 体素提供坐标、材质与发光读取。
#include "/omni-gfx/voxel/voxel.glsl"
// 阴影贴图提供投影偏差、边缘压缩与体素阴影。
#include "/omni-gfx/shadow/map.glsl"
// 方块光提供光照图曲线与 LPV 混合。
#include "/omni-gfx/gi/diffuse.glsl"
// 间接光提供屏幕空间追踪与历史重投影。
#include "/omni-gfx/gi/indirect.glsl"
// Photonics 反射着色：间接光、方块光、阴影、云影与自发光一起决定命中面颜色。
// 光子学反射着色：把体素命中、手光与阴影合成为反射颜色。
void ogxPhotonicsReflectionShading(inout vec4 color, vec3 normal, vec3 worldPos, float noise,
    vec3 directLightColor, vec3 ambientLightColor, int blockID, float skylightmap, vec3 torchColor,
    vec3 lpvSample, vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount,
    bool vanillaMask, float shadowDistance, float ambientBrightness, float minLightAmount,
    float minLightAmountInside, float nightVision, float eyeBrightness, float cloudShadow, vec3 sunVector,
    sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount,
    bool basicFilter, bool coloredShadows, bool endShader, float emissiveBrightness, float emissiveCurve)
{
    float skyDir = normal.y * 0.5 + 0.5; // 法线朝上程度。
    vec2 lightmap = vec2(0.0, skylightmap); // 光照图。
    if (abs(blockID - 197) <= 1 || blockID == 242) lightmap.x = 1.0; // 岩浆块与海晶灯。
    float skylight = mix(0.08 + 0.92 * (1.0 - lightmap.y), 1.0, skyDir); // 天空光。
    vec3 indirectLighting = ogxIndirectLighting(ambientLightColor * skylight, vec3(1.0),
        lightmap.y, ambientBrightness, minLightAmount, minLightAmountInside, nightVision); // 间接光。
    vec3 playerPosition = worldPos; // 相机相对位置。
    indirectLighting += ogxBlockLightLightingVoxel(torchColor, lightmap.x, lpvSample, handLight,
        lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask); // 方块光。
    float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance + 16.0), 0.0) * 5.0, 1.0)); // 阴影距离淡出。
    float sh = 1.0; // 阳光阴影。
    if (!endShader) sh = ogxPhotonicsShadowMap(directLightColor, playerPosition, shadowMapFalloff,
        noise, normal, opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection,
        shadowDistance, shadowMapResolution, distortA, distortB, distortK, d0k, shadowSampleCount,
        basicFilter, coloredShadows, false); // 主世界阴影。
    float lightLeakFix = clamp(pow(eyeBrightness / 240.0 + lightmap.y, 2.0), 0.0, 1.0); // 漏光修正。
    sh *= lightLeakFix;
    sh *= cloudShadow; // 云影。
    float NdotL = endShader ? 1.0 : clamp((-15.0 + dot(normal, sunVector) * 255.0) / 240.0, 0.0, 1.0); // 参考实现的直射项。
    vec3 albedo = color.rgb; // 命中面底色。
    color.rgb *= indirectLighting + directLightColor * sh * NdotL; // 合成光照。
    float emissive = 0.0; // 自发光。
    if (blockID >= 100 && blockID < 282) // 普通光源方块。
    {
        emissive = 0.5;
        if (blockID == 266 || (blockID >= 276 && blockID <= 281)) emissive = 0.2; // 幽匿方块。
        else if (blockID == 195) emissive = 2.3; // 发光地衣。
        else if (blockID == 185) emissive = 1.5; // 哭泣的黑曜石。
        else if (blockID == 105) emissive = 2.0; // 酿造台。
        else if (blockID == 236) emissive = 1.0; // 重生锚。
        else if (blockID == 101) emissive = 0.7; // 紫水晶芽。
        else if (blockID == 103) emissive = 1.0; // 紫水晶簇。
        else if (blockID == 244) emissive = 1.5; // 灵魂火。
        emissive *= ogxGetVoxelEmission(albedo); // 自发光曲线。
        emissive = clamp(emissive, 0.0, 1.0); // 夹紧。
        ogxVoxelEmission(color.rgb, albedo, emissive, emissiveBrightness, emissiveCurve); // 混入自发光。
    }
}

// 严格参考签名的 Photonics 命中面着色：SSS 方块软化、矿石自发光与云影都照原分支保留。
// 云影由场景阶段预先算好作为显式值传入，避免在反射着色里重复展开整棵云影调用树。
void ogxPhotonicsReflectionShadingExact(inout vec4 color, vec3 normal, vec3 worldPos, float noise,
    vec3 directLightColor, vec3 ambientLightColor, int blockID, float skylightmap, vec3 torchColor,
    vec3 lpvSample, vec3 handLight, float torchAmount, float shadowDistance, float ambientBrightness,
    float minLightAmount, float minLightAmountInside, float nightVision, float eyeBrightness, float cloudShadow,
    vec3 sunVector, sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowMapResolution, float distortA, float distortB,
    float distortK, float d0k, int shadowSampleCount, bool basicFilter, bool coloredShadows,
    float emissiveBrightness, float emissiveCurve)
{
    float skyDir = normal.y * 0.5 + 0.5; // 法线朝上程度。
    vec2 lightmap = vec2(0.0, skylightmap); // 光照图。
    if (abs(blockID - 197) <= 1 || blockID == 242) lightmap.x = 1.0; // 岩浆块与海晶灯。
    float skylight = mix(0.08 + 0.92 * (1.0 - lightmap.y), 1.0, skyDir); // 天空光。
    vec3 indirectLighting = ogxIndirectLighting(ambientLightColor * skylight, vec3(1.0),
        lightmap.y, ambientBrightness, minLightAmount, minLightAmountInside, nightVision); // 间接光。
    vec3 playerPosition = worldPos; // 相机相对位置。
    indirectLighting += ogxBlockLightLightingVoxelExact(torchColor, lightmap.x, lpvSample, handLight, torchAmount); // 方块光。
    float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance + 16.0), 0.0) * 5.0, 1.0)); // 阴影距离淡出。
    float sh = ogxPhotonicsShadowMap(directLightColor, playerPosition, shadowMapFalloff, noise, normal,
        opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowDistance,
        shadowMapResolution, distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows, false); // 阴影。
    float lightLeakFix = clamp(pow(eyeBrightness / 240.0 + lightmap.y, 2.0), 0.0, 1.0); // 漏光修正。
    sh *= lightLeakFix;
    sh *= cloudShadow; // 预先算好的云影。
    float NdotL = clamp((-15.0 + dot(normal, sunVector) * 255.0) / 240.0, 0.0, 1.0); // 直射项。
    if (blockID == 80 || blockID == 87 || blockID == 56 || blockID == 79 || blockID == 54 || blockID == 55
        || blockID == 12 || blockID == 14 || blockID == 13 || blockID == 81 || blockID == 89 || blockID == 82
        || blockID == 195 || (blockID >= 269 && blockID <= 274) || blockID == 409 || blockID == 401
        || blockID == 102 || blockID == 101 || blockID == 103 || blockID == 11 || blockID == 15
        || blockID == 282 || blockID == 21) NdotL = mix(NdotL, 1.0, 0.25); // 植物与半透明方块的柔化。
    vec3 albedo = color.rgb; // 命中面底色。
    color.rgb *= indirectLighting + directLightColor * sh * NdotL; // 合成光照。
    float emissive = 0.0; // 自发光。
    if (blockID >= 100 && blockID < 282) // 普通光源方块。
    {
        emissive = 0.5;
        if (blockID == 266 || (blockID >= 276 && blockID <= 281)) emissive = 0.2; // 幽匿方块。
        else if (blockID == 195) emissive = 2.3; // 发光地衣。
        else if (blockID == 185) emissive = 1.5; // 哭泣的黑曜石。
        else if (blockID == 105) emissive = 2.0; // 酿造台。
        else if (blockID == 236) emissive = 1.0; // 重生锚。
        else if (blockID == 101) emissive = 0.7; // 紫水晶芽。
        else if (blockID == 103) emissive = 1.0; // 紫水晶簇。
        else if (blockID == 244) emissive = 1.5; // 灵魂火。
        emissive *= ogxGetVoxelEmission(albedo); // 自发光曲线。
        emissive = clamp(emissive, 0.0, 1.0); // 夹紧。
        ogxVoxelEmission(color.rgb, albedo, emissive, emissiveBrightness, emissiveCurve); // 混入自发光。
    }
}

// Photonics 反射：先追踪体素，再给半透明与不透明命中着色，最后按雾吸收。
vec4 ogxPhotonicsReflection(OgxRayJob job, OgxTranslucentHit translucentHits[10],
    uint translucentHitsCount, vec3 reflectedVector, vec3 flatNormal, vec2 noise,
    inout float backgroundReflectMask, inout vec3 backgroundTint,
    usampler3D voxelIds, sampler3D voxelColors, vec3 directLightColor, vec3 ambientLightColor,
    vec3 indirectLightColor, float ambientBrightness, float skyLightLevelSmooth, float nightVision,
    float minLightAmount, float minLightAmountInside, vec3 torchColor, vec3 lpvSample, vec3 handLight,
    vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask,
    float shadowDistance, float eyeBrightness, float cloudShadow, vec3 sunVector,
    sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0, mat4 shadowView, mat4 shadowProjection, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, float emissiveBrightness, float emissiveCurve, bool translucentInReflections)
{
    vec4 color = vec4(0.0); // 反射颜色。
    int blockID = 0; // 最终方块编号。
    float skylightmap = 0.0; // 最终天光。
    if (translucentInReflections) // 只有开启半透明反射时才逐层染色。
    {
        for (uint i = 0u; i < translucentHitsCount; i++) // 逐层半透明。
        {
            vec4 sampleColor = translucentHits[i].hitColor; // 半透明颜色。
            ogxPhotonicsReflectionShading(sampleColor, translucentHits[i].hitNormal,
                translucentHits[i].hitPos, noise.y, directLightColor, ambientLightColor,
                translucentHits[i].hitId, translucentHits[i].skylight, torchColor, lpvSample, handLight,
                lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask, shadowDistance, ambientBrightness,
                minLightAmount, minLightAmountInside, nightVision, eyeBrightness, cloudShadow, sunVector,
                opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowMapResolution,
                distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows,
                false, emissiveBrightness, emissiveCurve); // 给半透明命中着色。
            sampleColor.a *= (1.0 - color.a); // 预乘透明度。
            color.rgb += sampleColor.rgb * sampleColor.a; // 累积颜色。
            color.a += sampleColor.a; // 累积透明度。
            if (color.a > 0.995) return color; // 足够不透明就停止。
        }
        if (translucentHitsCount > 0u) backgroundTint = mix(normalize(translucentHits[0].hitColor.rgb + 1e-7),
            vec3(1.0), min(max(0.1 - translucentHits[0].hitColor.a, 0.0) * 10.0, 1.0)); // 背景染色。
    }
    if (job.resultHit) // 不透明命中。
    {
        vec4 sampleColor = vec4(job.resultColor, 1.0); // 命中颜色。
        ogxPhotonicsReflectionShading(sampleColor, job.resultNormal, job.resultPosition, noise.y,
            directLightColor, ambientLightColor, blockID, skylightmap, torchColor, lpvSample, handLight,
            lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask, shadowDistance, ambientBrightness,
            minLightAmount, minLightAmountInside, nightVision, eyeBrightness, cloudShadow, sunVector,
            opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowMapResolution,
            distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows,
            false, emissiveBrightness, emissiveCurve); // 给不透明命中着色。
        sampleColor.rgb *= backgroundTint; // 半透明背景染色。
        sampleColor.a *= (1.0 - color.a);
        color.rgb += sampleColor.rgb * sampleColor.a;
        color.a += sampleColor.a;
    }
    if (color.a < 0.999) backgroundReflectMask = 1.0; // 还有背景透出。
    return color; // 交回反射颜色。
}

#endif
