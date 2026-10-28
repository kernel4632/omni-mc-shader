/*
生成文件：WSR 反射模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 WSR 反射模块：体素追踪、屏幕空间反射与历史重投影。
调用位置：Eclipse WSR 风格反射；由 `/omni-gfx/reflection/wsr.glsl` 引入，高光模块再组合它。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。
可复制示例：
    OgxRayJob job = ogxRayJob(origin, direction); // 构造射线任务。
    ogxWsrTrace(job, voxelIds, voxelColors, hits, hitCount, blockId, skylight, side, worldOffset); // 体素追踪。
设计原因与取舍：
    体素命中与屏幕空间追踪只读显式纹理和矩阵，步进顺序与参考实现一致。
    `WSR` 是世界空间反射的行业缩写，也是选项与严格台账沿用的名字，不是作者名；
    改动它会同时破坏玩家配置与参考对照，因此保留。
    雾、水下体积与 LPV 已移到各自模块，本文件只负责反射。
*/
#ifndef OGX_REFLECTION_WSR_INCLUDED
#define OGX_REFLECTION_WSR_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 体素求交提供光线步进与遮挡判断。
#include "/omni-gfx/voxel/trace.glsl"
// 间接光模块带入相机投影工具，屏幕空间追踪与历史重投影都要用。
#include "/omni-gfx/gi/indirect.glsl"
// 屏幕空间高光追踪的提前声明：环境反射函数会先调用它，定义放在文件后半段。
vec3 ogxReflectionRayTrace(vec3 dir, vec3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    sampler2D depthTexture, vec2 texelSize, bool packedDepth, mat4 projection);

// WSR 体素追踪：在三维方块编号图里逐格前进，记录半透明命中与最终不透明命中。
// WSR 体素追踪：沿视线在体素编号图里找命中，供反射与雾共用。
void ogxWsrTrace(inout OgxRayJob job, usampler3D voxelIds, sampler3D voxelColors,
    inout OgxTranslucentHit translucentHits[10], inout uint translucentHitsCount,
    out int blockId, out float skylightmap, int side, float worldOffset)
{
    job.direction = normalize(job.direction); // 方向单位化。
    blockId = -1; // 默认没有方块。
    skylightmap = 0.0; // 默认没有天光。
    vec3 position = job.origin; // 当前格坐标。
    vec3 raySign = sign(job.direction); // 每轴方向。
    vec3 invDir = 1.0 / job.direction; // 方向倒数。
    vec3 tMax = vec3(1e30); // 到下一格边界的参数。
    ivec3 cell = ivec3(floor(position)); // 当前格。
    ivec3 stepDir = ivec3(raySign); // 每轴步进。
    if (job.direction.x != 0.0) tMax.x = (float(cell.x) + max(raySign.x, 0.0) - position.x) * invDir.x; // 横轴边界。
    if (job.direction.y != 0.0) tMax.y = (float(cell.y) + max(raySign.y, 0.0) - position.y) * invDir.y; // 纵轴边界。
    if (job.direction.z != 0.0) tMax.z = (float(cell.z) + max(raySign.z, 0.0) - position.z) * invDir.z; // 深度轴边界。
    int previousBlock = -1; // 上一格方块，避免同一方块反复记半透明。
    for (int i = 0; i < 512; i++) // 固定步数。
    {
        if (!ogxVoxelInside(cell, side)) break; // 走出体积。
        float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近边界。
        vec3 stepAxis = step(tMax, vec3(tMin)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x);
        stepAxis.z *= (1.0 - stepAxis.y);
        cell += ivec3(stepAxis * raySign); // 走一格。
        position += job.direction * tMin; // 更新位置。
        tMax += stepAxis * abs(invDir) - tMin; // 更新边界。
        if (!ogxVoxelInside(cell, side)) break; // 越界停止。
        uint id = texelFetch(voxelIds, cell, 0).r; // 方块编号。
        if (id == 0u) continue; // 空气。
        blockId = int(id); // 记录编号。
        vec4 stored = texelFetch(voxelColors, cell, 0); // 颜色与光照。
        if ((stored.a > 0.01) && (previousBlock != blockId) && (translucentHitsCount < 10u)) // 半透明方块。
        {
            vec3 hitNormal = -stepAxis * raySign; // 进入面法线。
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
vec4 ogxEnvironmentReflections(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    vec3 viewPos, vec2 noise, bool isHand, float roughness, inout float backgroundReflectMask,
    inout vec3 backgroundTint, bool isEyeInWater, float quality, sampler2D sceneTexture, sampler2D depthTexture,
    mat4 projection, mat4 projectionInverse, mat4 modelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 previousModelView, float nearPlane, float farPlane,
    vec3 cameraDelta, float renderScale, vec2 texelSize, float usePhotonics)
{
    vec4 reflection = vec4(0.0); // 反射结果。
    float reflectionLength = 0.0; // 反射长度。
    quality = quality > 0.0 ? quality : 30.0; // 参考实现的默认前向 SSR 质量。
    if (usePhotonics > 0.5) // Photonics 路径。
    {
        if (dot(reflectedVector, flatNormal) < 0.0) return reflection; // 射线朝表面内侧。
        return reflection; // 体素追踪由单独的 Photonics 函数负责。
    }
    bool depthCheck = false; // 深度检查。
    vec3 raytracePos = ogxReflectionRayTrace(ogxMatrix3MulPoint(mat3(modelView), reflectedVector), viewPos,
        noise.y, quality, isHand, reflectionLength, depthCheck, nearPlane, farPlane, renderScale,
        depthTexture, texelSize, true, projection); // 屏幕空间追踪，读四分之一分辨率打包深度。
    if (raytracePos.z > 1.00001) return reflection; // 没命中。
    reflectionLength = min(max(reflectionLength - 0.1, 0.0) / 0.9, 1.0); // 参考实现的长度重整。
    float lod = mix(0.0, 6.0 * (1.0 - exp(-15.0 * sqrt(roughness))), 1.0 - pow(1.0 - reflectionLength, 5.0)); // 粗糙度决定层级。
    vec3 previousPosition = ogxToWorldSpace(ogxToScreenSpace(raytracePos, projectionInverse), modelViewInverse) + cameraDelta; // 历史位置。
    previousPosition = ogxMatrix3MulPoint(mat3(previousModelView), previousPosition) + ogxMatrixTranslation(previousModelView);
    previousPosition.xy = ogxProject(previousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5; // 历史屏幕位置。
    if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0)
    {
        if (raytracePos.z > 0.9999999) backgroundReflectMask = 1.0; // 天空命中。
        reflection.a = raytracePos.z > 0.9999999 ? (isHand || isEyeInWater ? 1.0 : 0.0) : 1.0; // 天空命中只有手或水下才当作反射。
        reflection.rgb = textureLod(sceneTexture, previousPosition.xy, lod).rgb; // 读历史颜色。
    }
    return reflection; // 交回反射。
}

// 屏幕空间高光追踪：参考实现的 `rayTraceSpeculars`，支持远景矩阵与手部跳过。
vec3 ogxReflectionRayTrace(vec3 dir, vec3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    sampler2D depthTexture, vec2 texelSize, bool packedDepth, mat4 projection)
{
    const float biasAmount = 0.0001; // 深度偏差。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点。
    float rayLength = ((position.z + dir.z * farPlane * sqrt(3.0)) > -nearPlane)
        ? (-nearPlane - position.z) / dir.z : farPlane * sqrt(3.0); // 射线长度。
    vec3 direction = ogxToClipSpace3(position + dir * rayLength, projection) - clipPosition; // 裁剪空间方向。
    vec3 reflectedTC = vec3((direction.xy + clipPosition.xy) * renderScale, 0.999999); // 参考实现的回退。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z); // 最短长度。
    vec3 stepv = direction * mult / quality; // 每步。
    clipPosition.xy *= renderScale;
    stepv.xy *= renderScale;
    vec3 spos = clipPosition + stepv * (dither * 0.5 + 0.5); // 起点加抖动。
    spos += vec3(0.5 * texelSize, 0.0); // 半像素偏移。
    float minZ = spos.z - 0.00025 / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    vec3 hitPos = vec3(1.1); // 默认没有命中。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        if (!hand && (spos.x < 0.0 || spos.x > 1.0 || spos.y < 0.0 || spos.y > 1.0)) return vec3(1.1); // 手部允许出屏。
        float sp; // 屏幕深度；打包格式从 alpha 通道解码。
        if (packedDepth) { sp = ogxLinearToScreenDepth(sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelSize / 4.0), 0).a / 65000.0), nearPlane, farPlane); }
        else { sp = texelFetch(depthTexture, ivec2(spos.xy / texelSize), 0).r; }
        if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) // 命中。
        {
            hitPos = vec3(spos.xy / renderScale, sp);
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
vec4 ogxVoxelReflectionColor(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    float noise, inout float backgroundReflectMask, vec3 directLightColor, vec3 ambientLightColor)
{
    backgroundReflectMask = 1.0; // 参考实现固定回到背景反射。
    return vec4(0.0); // 参考实现的当前颜色输出。
}

// 严格参考签名的体素反射入口：参考正文的追踪整段被注释，实际只算光源颜色并返回零。
// `lightSourceColor` 与 `averageSkyColor` 是参考全局 SSBO 的显式输入，缩放常数照原样保留。
vec4 ogxVoxelReflectionColorExact(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    float noise, inout float backgroundReflectMask, vec3 lightSourceColor, vec3 averageSkyColor,
    float ambientBrightness)
{
    vec3 directLightColor = lightSourceColor / 1400.0; // 参考实现的直射光缩放。
    vec3 ambientLightColor = averageSkyColor / 900.0; // 参考实现的环境光缩放。
    ambientLightColor *= ambientBrightness; // 环境光再乘环境亮度。
    vec4 color = vec4(0.0); // 追踪主体被注释后只剩清空颜色。
    backgroundReflectMask = 1.0; // 没有命中时回到背景反射。
    return color; // 交回参考实现的当前输出。
}

// WSR 的 LPV 体积雾：沿视线指数步进，用三维密度图与 LPV 图累积照明。
// 参考实现直接调 `cloudVol` 与 `SampleLpvLinear`；库用同样布局的三维纹理代替。

// 严格参考签名的 LPV 雾入口：密度场、LPV 图与手持光表都作为显式资源。
// 参考在循环里调用 cloudVol、GetLpvPosition、SampleLpvLinear 与 GetHandLight；
// 这里把密度场换成三维纹理，LPV 采样用库里的精确实现，手持光走同一套字节拆包。

// WSR 的空气雾：按 Eclipse 参考逐行移植指数步进、阴影、云密度与大气透视。
// 参考参数在前，相机、阴影、密度场与选项资源追加在后；默认分支不读宿主全局量。

// WSR 水下体积：按 Eclipse 参考逐行移植水吸收、焦散、方向光与闪电照明。
// 参考参数在前，相机、阴影、噪声与选项资源追加在后；默认分支不读宿主全局量。

#endif
