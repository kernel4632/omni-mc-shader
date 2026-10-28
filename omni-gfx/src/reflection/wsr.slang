/*
Omni 通用图形库WSR 反射模块：体素追踪、屏幕空间反射、LPV 雾、空气雾与水下体积。
调用位置：Eclipse WSR 风格反射与体积雾；由 `/omni-gfx/reflection/wsr.glsl` 引入。
可复制示例：
    OgxRayJob job = ogxRayJob(origin, direction); // 构造射线任务。
    vec4 cloud = ogxWsrFogMarch(origin, end, dither, light, ambient, average, 16, density, shadowTex, view, proj, cameraOffset, cameraPos, sun, far, 32, 1.0, 1.0, 0.0, 0.0, 1.0, rayleigh, mie, 0.9, 0.9, 1.0, 2048.0, bolt, lightning); // 积分空气雾。
设计原因与取舍：
    体素命中、屏幕空间追踪、雾与水体都只读显式纹理和矩阵；指数步进、吸收与闪电照明的顺序与参考实现一致。
*/
#ifndef OGX_REFLECTION_WSR_INCLUDED
#define OGX_REFLECTION_WSR_INCLUDED

#include "../math.slang"
#include "../voxel/trace.slang"
#include "../shadow/map.slang"
#include "../fog/fog.slang"
#include "../water.slang"
#include "../weather/lightning.slang"
#include "../lpv.slang"
#include "../heldlight.slang"
#include "../gi/indirect.slang"

// 屏幕空间高光追踪的提前声明：环境反射函数会先调用它，定义放在文件后半段。
float3 ogxReflectionRayTrace(float3 dir, float3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    Sampler2D depthTexture, float2 texelSize, bool packedDepth, float4x4 projection);

// WSR 体素追踪：在三维方块编号图里逐格前进，记录半透明命中与最终不透明命中。
// WSR 体素追踪：沿视线在体素编号图里找命中，供反射与雾共用。
void ogxWsrTrace(inout OgxRayJob job, Usampler3D voxelIds, Sampler3D voxelColors,
    inout OgxTranslucentHit translucentHits[10], inout uint translucentHitsCount,
    out int blockId, out float skylightmap, int side, float worldOffset)
{
    job.direction = normalize(job.direction); // 方向单位化。
    blockId = -1; // 默认没有方块。
    skylightmap = 0.0; // 默认没有天光。
    float3 position = job.origin; // 当前格坐标。
    float3 raySign = sign(job.direction); // 每轴方向。
    float3 invDir = 1.0 / job.direction; // 方向倒数。
    float3 tMax = float3(1e30); // 到下一格边界的参数。
    int3 cell = int3(floor(position)); // 当前格。
    int3 stepDir = int3(raySign); // 每轴步进。
    if (job.direction.x != 0.0) tMax.x = (float(cell.x) + max(raySign.x, 0.0) - position.x) * invDir.x; // 横轴边界。
    if (job.direction.y != 0.0) tMax.y = (float(cell.y) + max(raySign.y, 0.0) - position.y) * invDir.y; // 纵轴边界。
    if (job.direction.z != 0.0) tMax.z = (float(cell.z) + max(raySign.z, 0.0) - position.z) * invDir.z; // 深度轴边界。
    int previousBlock = -1; // 上一格方块，避免同一方块反复记半透明。
    for (int i = 0; i < 512; i++) // 固定步数。
    {
        if (!ogxVoxelInside(cell, side)) break; // 走出体积。
        float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近边界。
        float3 stepAxis = step(tMax, float3(tMin)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x);
        stepAxis.z *= (1.0 - stepAxis.y);
        cell += int3(stepAxis * raySign); // 走一格。
        position += job.direction * tMin; // 更新位置。
        tMax += stepAxis * abs(invDir) - tMin; // 更新边界。
        if (!ogxVoxelInside(cell, side)) break; // 越界停止。
        uint id = voxelIds.Load(int4(cell, 0)).r; // 方块编号。
        if (id == 0u) continue; // 空气。
        blockId = int(id); // 记录编号。
        float4 stored = voxelColors.Load(int4(cell, 0)); // 颜色与光照。
        if ((stored.a > 0.01) && (previousBlock != blockId) && (translucentHitsCount < 10u)) // 半透明方块。
        {
            float3 hitNormal = -stepAxis * raySign; // 进入面法线。
            translucentHits[translucentHitsCount].hitNormal = hitNormal;
            translucentHits[translucentHitsCount].hitPos = position + worldOffset; // 转回世界。
            translucentHits[translucentHitsCount].hitColor = stored;
            translucentHits[translucentHitsCount].hitId = blockId;
            translucentHits[translucentHitsCount].skylight = stored.a; // 体素颜色 alpha 当作天光。
            translucentHitsCount += 1u;
        }
        previousBlock = blockId;
        job.resultHit = true; // 命中不透明面。
        job.resultPosition = position + worldOffset;
        job.resultColor = stored.rgb;
        job.resultNormal = -stepAxis * raySign;
        skylightmap = stored.a;
        break; // 参考实现遇到第一个非空方块就停。
    }
}

// 环境反射：屏幕空间追踪加历史重投影，天空回退由调用方在 `backgroundReflection` 里处理。
float4 ogxEnvironmentReflections(float3 reflectedVector, float3 flatNormal, float3 normal, float3 origin,
    float3 viewPos, float2 noise, bool isHand, float roughness, inout float backgroundReflectMask,
    inout float3 backgroundTint, bool isEyeInWater, float quality, Sampler2D sceneTexture, Sampler2D depthTexture,
    float4x4 projection, float4x4 projectionInverse, float4x4 modelView, float4x4 modelViewInverse,
    float4x4 previousProjection, float4x4 previousModelView, float nearPlane, float farPlane,
    float3 cameraDelta, float renderScale, float2 texelSize, float usePhotonics)
{
    float4 reflection = float4(0.0); // 反射结果。
    float reflectionLength = 0.0; // 反射长度。
    quality = quality > 0.0 ? quality : 30.0; // 参考实现的默认前向 SSR 质量。
    if (usePhotonics > 0.5) // Photonics 路径。
    {
        if (dot(reflectedVector, flatNormal) < 0.0) return reflection; // 射线朝表面内侧。
        return reflection; // 体素追踪由单独的 Photonics 函数负责。
    }
    bool depthCheck = false; // 深度检查。
    float3 raytracePos = ogxReflectionRayTrace(ogxMatrix3MulPoint(float3x3(modelView), reflectedVector), viewPos,
        noise.y, quality, isHand, reflectionLength, depthCheck, nearPlane, farPlane, renderScale,
        depthTexture, texelSize, true, projection); // 屏幕空间追踪，读四分之一分辨率打包深度。
    if (raytracePos.z > 1.00001) return reflection; // 没命中。
    reflectionLength = min(max(reflectionLength - 0.1, 0.0) / 0.9, 1.0); // 参考实现的长度重整。
    float lod = lerp(0.0, 6.0 * (1.0 - exp(-15.0 * sqrt(roughness))), 1.0 - pow(1.0 - reflectionLength, 5.0)); // 粗糙度决定层级。
    float3 previousPosition = ogxToWorldSpace(ogxToScreenSpace(raytracePos, projectionInverse), modelViewInverse) + cameraDelta; // 历史位置。
    previousPosition = ogxMatrix3MulPoint(float3x3(previousModelView), previousPosition) + ogxMatrixTranslation(previousModelView);
    previousPosition.xy = ogxProject(previousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5; // 历史屏幕位置。
    if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0)
    {
        if (raytracePos.z > 0.9999999) backgroundReflectMask = 1.0; // 天空命中。
        reflection.a = raytracePos.z > 0.9999999 ? (isHand || isEyeInWater ? 1.0 : 0.0) : 1.0; // 天空命中只有手或水下才当作反射。
        reflection.rgb = sceneTexture.SampleLevel(previousPosition.xy, lod).rgb; // 读历史颜色。
    }
    return reflection; // 交回反射。
}

// 屏幕空间高光追踪：参考实现的 `rayTraceSpeculars`，支持远景矩阵与手部跳过。
float3 ogxReflectionRayTrace(float3 dir, float3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    Sampler2D depthTexture, float2 texelSize, bool packedDepth, float4x4 projection)
{
    const float biasAmount = 0.0001; // 深度偏差。
    float3 clipPosition = ogxToClipSpace3(position, projection); // 起点。
    float rayLength = ((position.z + dir.z * farPlane * sqrt(3.0)) > -nearPlane)
        ? (-nearPlane - position.z) / dir.z : farPlane * sqrt(3.0); // 射线长度。
    float3 direction = ogxToClipSpace3(position + dir * rayLength, projection) - clipPosition; // 裁剪空间方向。
    float3 reflectedTC = float3((direction.xy + clipPosition.xy) * renderScale, 0.999999); // 参考实现的回退。
    float3 maxLengths = (step(float3(0.0), direction) - clipPosition) / direction; // 到边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z); // 最短长度。
    float3 stepv = direction * mult / quality; // 每步。
    clipPosition.xy *= renderScale;
    stepv.xy *= renderScale;
    float3 spos = clipPosition + stepv * (dither * 0.5 + 0.5); // 起点加抖动。
    spos += float3(0.5 * texelSize, 0.0); // 半像素偏移。
    float minZ = spos.z - 0.00025 / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    float3 hitPos = float3(1.1); // 默认没有命中。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        if (!hand && (spos.x < 0.0 || spos.x > 1.0 || spos.y < 0.0 || spos.y > 1.0)) return float3(1.1); // 手部允许出屏。
        float sp; // 屏幕深度；打包格式从 alpha 通道解码。
        if (packedDepth) { sp = ogxLinearToScreenDepth(sqrt(depthTexture.Load(int3(int2(spos.xy / texelSize / 4.0), 0)).a / 65000.0), nearPlane, farPlane); }
        else { sp = depthTexture.Load(int3(int2(spos.xy / texelSize), 0)).r; }
        if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) // 命中。
        {
            hitPos = float3(spos.xy / renderScale, sp);
            break;
        }
        minZ = maxZ - biasAmount / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 推进下界。
        maxZ += stepv.z;
        spos += stepv;
        reflectionLength += 1.0 / quality; // 累积长度。
    }
    if (hand) return reflectedTC; // 手部回退到裁剪坐标。
    return hitPos; // 交回命中。
}

// 体素反射的当前参考实现：追踪主体在原程序里被整段注释，只剩背景遮罩与清空颜色。
// 保留参数与输出，后续恢复追踪时调用方不用改接口。
float4 ogxVoxelReflectionColor(float3 reflectedVector, float3 flatNormal, float3 normal, float3 origin,
    float noise, inout float backgroundReflectMask, float3 directLightColor, float3 ambientLightColor)
{
    backgroundReflectMask = 1.0; // 参考实现固定回到背景反射。
    return float4(0.0); // 参考实现的当前颜色输出。
}

// 严格参考签名的体素反射入口：参考正文的追踪整段被注释，实际只算光源颜色并返回零。
// `lightSourceColor` 与 `averageSkyColor` 是参考全局 SSBO 的显式输入，缩放常数照原样保留。
float4 ogxVoxelReflectionColorExact(float3 reflectedVector, float3 flatNormal, float3 normal, float3 origin,
    float noise, inout float backgroundReflectMask, float3 lightSourceColor, float3 averageSkyColor,
    float ambientBrightness)
{
    float3 directLightColor = lightSourceColor / 1400.0; // 参考实现的直射光缩放。
    float3 ambientLightColor = averageSkyColor / 900.0; // 参考实现的环境光缩放。
    ambientLightColor *= ambientBrightness; // 环境光再乘环境亮度。
    float4 color = float4(0.0); // 追踪主体被注释后只剩清空颜色。
    backgroundReflectMask = 1.0; // 没有命中时回到背景反射。
    return color; // 交回参考实现的当前输出。
}

// WSR 的 LPV 体积雾：沿视线指数步进，用三维密度图与 LPV 图累积照明。
// 参考实现直接调 `cloudVol` 与 `SampleLpvLinear`；库用同样布局的三维纹理代替。
float4 ogxWsrLpvMarch(float3 origin, float3 endPos, float dither, Sampler3D densityTexture,
    Sampler3D lpvTexture, float3 cameraOffset, float lpvSize, float fadeLength, float minDensity,
    float mult, int sampleCount, float lpvBrightness, float3 handLight, float torchAmount, bool vanillaMask)
{
    if (length(origin - endPos) < 0.001) return float4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    float3 rayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float rayLength = length(rayStart); // 射线长度。
    rayStart *= min(rayLength, min(256.0, 1e6)) / max(rayLength, 1e-6); // 参考实现的距离上限。
    rayLength = length(rayStart);
    float4 color = float4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        float3 progress = cameraOffset + d * rayStart + origin; // 当前世界位置。
        float density = max(densityTexture.SampleLevel(progress, 0.0).r / 1000.0, minDensity) * mult; // 密度。
        float volumeCoeff = exp(-dd * density * rayLength); // 本段透过率。
        float3 lpvPos = (progress - origin) / max(lpvSize, 1.0); // 体积坐标。
        float3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘。
        float fade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴淡出。
        if (fade < 0.01) break; // 体积外停止。
        float3 sampleColor = lpvTexture.SampleLevel(lpvPos, 0.0).rgb; // LPV 光色。
        if (vanillaMask) sampleColor *= 1.0; // 原版遮罩由调用方预先乘进纹理。
        float3 lighting = sampleColor * lpvBrightness * 25.0 * exp(-5.0 * (1.0 - ogxLuminance(sampleColor))); // 参考实现的亮度曲线。
        lighting += handLight * torchAmount * lpvBrightness * 0.04; // 手持光。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// 严格参考签名的 LPV 雾入口：密度场、LPV 图与手持光表都作为显式资源。
// 参考在循环里调用 cloudVol、GetLpvPosition、SampleLpvLinear 与 GetHandLight；
// 这里把密度场换成三维纹理，LPV 采样用库里的精确实现，手持光走同一套字节拆包。
float4 ogxWsrLpvMarchExact(float3 origin, float3 endPos, float dither,
    Sampler3D densityTexture, Sampler3D lpvTexture, float3 cameraOffset, float lpvSize, float fadeLength,
    float minDensity, int vlSamples, int sampleCount, float lpvBrightness, float torchAmount,
    float caveDetection, float farPlane, float3 relativeEyePosition, Usampler1D blockDataTexture,
    int heldItemId, int heldItemId2, int frameCounter, float2 blockSkyRange)
{
    if (length(origin - endPos) < 0.001) return float4(0.0, 0.0, 0.0, 1.0); // 空段直接返回。
    float mult = float(vlSamples) / float(sampleCount) * 1.15; // 参考实现的样本数换算。
    float minimumDensity = minDensity; // 参考实现的最低密度，由调用方按选项给出。
    float3 lpvRayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float lpvRayLength = length(lpvRayStart); // 射线长度。
    lpvRayStart *= min(lpvRayLength, min(256.0, farPlane)) / lpvRayLength; // 参考实现的距离上限。
    lpvRayLength = length(lpvRayStart); // 截断后的长度。
    float4 color = float4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定样本数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进位置。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        float3 rayProgress = cameraOffset + d * lpvRayStart + origin; // 当前世界位置。
        float density = 0.0; // 这一步的雾密度。
        float minimumDensityNow = minimumDensity; // 洞穴里抬高最低密度。
        if (caveDetection < 0.9999) density = densityTexture.SampleLevel(rayProgress, 0.0).r * (1.0 - caveDetection); // 密度场换成显式纹理。
        minimumDensityNow += caveDetection * minimumDensity; // 洞穴补偿。
        density = max(density / 1000.0, minimumDensityNow) * mult; // 参考实现的密度换算。
        float volumeCoeff = exp(-dd * density * lpvRayLength); // 本段透过率。
        float3 lpvPos = ogxGetLpvPositionExplicit(rayProgress, float3(0.0), lpvSize); // 体积坐标。
        float3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘淡出。
        float lpvFade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        if (lpvFade < 0.01) break; // 走出体积就停。
        float3 sampleColor = ogxLpvSampleLinear(lpvPos, lpvTexture, lpvTexture, frameCounter, lpvSize, blockSkyRange).rgb; // LPV 光色。
        float3 lighting = sampleColor * lpvBrightness * 25.0
            * exp(-5.0 * (1.0 - dot(sampleColor, float3(0.21, 0.72, 0.07)))); // 参考亮度曲线与亮度权重。
        float lightRange = 0.0; // 手持光范围。
        float3 handLight1 = ogxHandLightFromBlockData(heldItemId, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 主手。
        float3 handLight2 = ogxHandLightFromBlockData(heldItemId2, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 副手。
        lighting += (handLight1 + handLight2) * torchAmount * lpvBrightness * 0.04; // 手持光叠加。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// WSR 的空气雾：按 Eclipse 参考逐行移植指数步进、阴影、云密度与大气透视。
// 参考参数在前，相机、阴影、密度场与选项资源追加在后；默认分支不读宿主全局量。
float4 ogxWsrFogMarch(float3 origin, float3 endPos, float2 dither, float3 lightColor,
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

// WSR 水下体积：按 Eclipse 参考逐行移植水吸收、焦散、方向光与闪电照明。
// 参考参数在前，相机、阴影、噪声与选项资源追加在后；默认分支不读宿主全局量。
float4 ogxWsrWaterVolume(float3 origin, float3 endPos, float2 dither, float3 ambient,
    float3 lightSource, float3 lpv, float3 waterAbsorption, float dirtAmount, float3 dirtColor,
    float waterAltitude, float sunElevation, float bubbleScale, float time, float waveSpeed,
    float patchyBlend, Sampler2D noiseTexture, float3 sunVector, float3 cameraOffset, float3 cameraWorldPos,
    float farPlane, float cloudShadow, Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection,
    float distortA, float distortB, float distortK, float shadowResolution, float4 lightningPosition,
    float lightningFlash)
{
    if (length(origin - endPos) < 0.001) return float4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有水体。
    const int sampleCount = 3; // 参考实现的固定三步。
    float lightSourceCheck = float(sunElevation > 1e-5) * 2.0 - 1.0; // 太阳在地平线上时翻转云影方向。
    float3 scatterCoef = dirtAmount * dirtColor / 3.14; // 参考的脏水散射系数。
    float3 dVWorld = endPos - origin - cameraOffset; // 相机相对的射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    float maxLength = min(rayLength, farPlane) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到远裁剪面。
    float3 absorbance = float3(1.0); // 累积吸收。
    float3 vL = float3(0.0); // 累积颜色。
    float3 rayDir = normalize(endPos - origin); // 射线方向。
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
        float3 progressP = cameraOffset + d * dVWorld; // 相机相对位置。
        float3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        float distanceFromWaterSurface = max(-(progressW.y - waterAltitude), 0.0); // 到水面的距离。
        float3 fragposition = ogxMatrixMulPoint(shadowView, progressP) + ogxMatrixTranslation(shadowView); // 阴影相机空间坐标。
        fragposition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragposition + shadowProjection[3].xyz; // 按投影对角线缩放。
        float distortFactor = ogxShadowDistortFactor(fragposition.xy, distortA, distortB, distortK); // 阴影边缘压缩。
        float3 spPos = float3(fragposition.xy * distortFactor, fragposition.z); // 压缩后的阴影坐标。
        float3 pos = float3(spPos.xy * distortFactor, spPos.z); // 参考在这里再压一次。
        float3 sh = float3(1.0); // 受光系数。
        if (abs(pos.x) < 1.0 - 0.5 / shadowResolution && abs(pos.y) < 1.0 - 0.5 / shadowResolution) // 落在阴影图内才采样。
        {
            pos = pos * float3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 换成零到一坐标。
            sh = float3(shadowTexture.SampleLevel(pos.xy, 0.0).x); // 只读不透明深度。
        }
        sh *= cloudShadow; // 参考的云影由宿主预计算成标量。
        float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / bubbleScale, 0.0, 1.0)); // 气泡形状。
        float caustics = max(max(ogxWaterBumpCaustics(progressW, sunVector, -(progressW.y - waterAltitude), time, waveSpeed, patchyBlend, noiseTexture), phase * 0.5) * lerp(0.5, 1.5, bubble), phase); // 参考的焦散与相位混合。
        float3 sunAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface / abs(sunVector.y))); // 阳光穿过水面的吸收。
        float3 waterAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface + thing)); // 水体吸收。
        float3 direct = lightSource * sh * phase * caustics * sunAbsorbance; // 直射。
        float3 indirect = ambient; // 间接光。
        float horizontalDist = length(progressP.xz - lightningPosition.xz); // 到闪电的水平距离。
        if (horizontalDist < 250.0 && lightningPosition.w > 0.0) // 闪电在附近时照亮水体。
        {
            float lightningIntensity = exp(-horizontalDist * 0.02) * lightningFlash; // 距离衰减。
            indirect = lerp(indirect, float3(1.3, 1.5, 3.0) * sh, lightningIntensity); // 冷色闪光。
        }
        indirect *= waterAbsorbance; // 间接光也被水体吸收。
        float3 light = (indirect + direct + lpv) * scatterCoef; // 总光。
        float3 volumeCoeff = exp(-waterAbsorption * length(dd * dVWorld)); // 本段吸收。
        vL += (light - light * volumeCoeff) / waterAbsorption * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积吸收。
    }
    return float4(vL, dot(absorbance, float3(0.333333))); // 交回水体颜色与透过率。
}

#endif
