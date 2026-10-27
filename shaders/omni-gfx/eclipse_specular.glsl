/*
生成文件：Eclipse 高光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 高光与反射模块：体素求交、WSR/Photonics 阴影、反射着色与屏幕空间高光。
调用位置：需要复现 Eclipse `specular.glsl`、`diffuse_lighting.glsl` 与 `indirect_lighting_effects.glsl`
    的程序；Minecraft 光影由 `/omni-gfx/eclipse_specular.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    OgxEclipseRayJob job = ogxEclipseRayJob(origin, direction);
    OgxEclipseTranslucentHit hits[10];
    int blockId; float sky;
    ogxEclipseTraceWsr(job, voxelIds, hits, blockId, sky);
    vec4 color = ogxEclipsePhotonicsReflection(job, hits, ...);
设计原因与取舍：
    参考实现直接读 `cb_array`、`imgVoxelMask`、`shadowtex0` 与大量菜单宏。库把体素图、阴影图、矩阵、
    光色、天空光与开关全部改成显式参数；遍历顺序、常数、采样次数和分支条件保持不变。
    体素世界用三维纹理代替原来的分层 SSBO：两者都按整数格取方块编号，语义相同，库因此不绑定 Minecraft。
    反射雾与 LPV 雾的密度由调用方传入三维纹理，库只负责步进、吸收和合成。
*/
#ifndef OGX_ECLIPSE_SPECULAR_INCLUDED
#define OGX_ECLIPSE_SPECULAR_INCLUDED

// 相机与数学提供投影、求交与夹紧；体素提供格号与法线编号；Eclipse 补充提供 GGX 与螺旋采样。
#include "/omni-gfx/camera.glsl"
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/voxel.glsl"
#include "/omni-gfx/eclipse_extra.glsl"
#include "/omni-gfx/eclipse_indirect.glsl"
#include "/omni-gfx/eclipse_sky.glsl"
#include "/omni-gfx/lpv.glsl"
#include "/omni-gfx/water.glsl"
#include "/omni-gfx/shadow.glsl"
// 体素包围盒求交结果：命中、参数、位置与进入面轴。
struct OgxEclipseRayHit
{
    bool hit; // 是否命中。
    float t; // 射线参数。
    vec3 currPos; // 命中位置。
    vec3 stepAxis; // 进入面轴。
};

// 体素射线任务：起点、方向、结果。
struct OgxEclipseRayJob
{
    vec3 origin; // 起点，体积坐标。
    vec3 direction; // 方向。
    vec3 resultPosition; // 命中位置。
    vec3 resultColor; // 命中颜色。
    vec3 resultNormal; // 命中法线。
    bool resultHit; // 是否命中。
};

// 半透明命中：给反射链逐层染色。
struct OgxEclipseTranslucentHit
{
    vec3 hitNormal; // 命中面法线。
    vec3 hitPos; // 命中点。
    vec4 hitColor; // 颜色与透明度。
    int hitId; // 方块编号。
    float skylight; // 天光。
};

// 屏幕空间高光追踪的提前声明：环境反射函数会先调用它，定义放在文件后半段。
vec3 ogxEclipseRayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, bool hand,
    inout float reflectionLength, inout bool depthCheck, float nearPlane, float farPlane, float renderScale,
    sampler2D depthTexture, vec2 texelSize, bool packedDepth, mat4 projection);

// 构造一个体素射线任务。
OgxEclipseRayJob ogxEclipseRayJob(vec3 origin, vec3 direction){
    OgxEclipseRayJob job; // 逐字段赋值，避免结构体构造顺序出错。
    job.origin = origin;
    job.direction = direction;
    job.resultPosition = vec3(0.0);
    job.resultColor = vec3(0.0);
    job.resultNormal = vec3(0.0);
    job.resultHit = false;
    return job;
}

// 体素包围盒求交：返回结构体版本，和参考实现的 `AABBintersection2` 相同。
OgxEclipseRayHit ogxEclipseAabbIntersection2(vec3 currPos, vec3 reflectedVector, vec3 stepSizes,
    vec3 boxMin, vec3 boxMax, vec3 stepAxis)
{
    vec3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    vec3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    vec3 tmin = min(t1, t2); // 每轴入口。
    vec3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    OgxEclipseRayHit result; // 结果。
    result.hit = hit;
    result.t = tmin0;
    vec3 entryDist = abs(tmin - vec3(tmin0)); // 哪一轴最先进入。
    vec3 normal = step(entryDist, vec3(0.0)); // 入口轴标记。
    result.stepAxis = mix(stepAxis, normal, fHit); // 命中时更新轴。
    result.currPos = mix(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return result; // 交回结构体。
}

// 排序两个裁切体素交点：先取较近的，再用贴图 alpha 判断是否穿过去。
// 裁剪命中排序的提前声明：参考参数在前，体素面表、贴图、相机位置作为显式资源追加。
void ogxEclipseSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, vec3 stepDir,
    vec2 gtexSize, vec2 texCoordOffset, vec3 voxelPos, inout bool hit,
    inout vec3 shiftedCurrPos, inout vec3 stepAxis, sampler2D gtexture,
    sampler2D voxelDataTexture, int voxelSize, vec3 cameraWorldPos);

// Eclipse 裁剪命中排序入口：保留旧的参数顺序，方便现有调用方逐项迁移。
void ogxItxSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, vec3 stepDir,
    vec2 gtexSize, vec2 texCoordOffset, vec3 voxelPos, inout bool hit,
    inout vec3 shiftedCurrPos, inout vec3 stepAxis, sampler2D gtexture,
    sampler2D voxelDataTexture, int voxelSize, vec3 cameraWorldPos)
{
    ogxEclipseSortIntersectionCutout(hit1, hit2, stepDir, gtexSize, texCoordOffset, voxelPos,
        hit, shiftedCurrPos, stepAxis, gtexture, voxelDataTexture, voxelSize, cameraWorldPos);
}

void ogxEclipseSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, vec3 stepDir,
    vec2 gtexSize, vec2 texCoordOffset, vec3 voxelPos, inout bool hit,
    inout vec3 shiftedCurrPos, inout vec3 stepAxis, sampler2D gtexture,
    sampler2D voxelDataTexture, int voxelSize, vec3 cameraWorldPos)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    OgxEclipseRayHit secondHit = useFirst ? hit2 : hit1; // 第二命中。
    vec2 texCoord; // 贴图坐标。
    vec3 voxelNormal = -firstHit.stepAxis * stepDir; // 进入面法线。
    ogxEclipseGetTexCoord(ivec3(voxelPos), texCoord, voxelNormal, voxelDataTexture, voxelSize); // 从体素面表读贴图坐标。
    vec3 wPos = firstHit.currPos + cameraWorldPos; // 转成绝对世界位置。
    vec2 sampleDir = firstHit.stepAxis.x * fract(wPos.zy) + firstHit.stepAxis.y * fract(wPos.xz)
        + firstHit.stepAxis.z * fract(wPos.xy); // 进入面内的采样方向。
    texCoord = mix(texCoord + vec2(0.0, texCoordOffset.y), texCoord - vec2(0.0, texCoordOffset.y), sampleDir); // 纵向偏移。
    texCoord = mix(texCoord + vec2(texCoordOffset.x, 0.0), texCoord - vec2(texCoordOffset.x, 0.0), sampleDir); // 横向偏移。
    float sampleAlpha = textureLod(gtexture, texCoord, 0.0).a; // 参考实现的纹理采样。
    firstHit = sampleAlpha > 0.1 ? firstHit : secondHit; // 透明就穿到第二命中。
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

// 排序两个不透明体素交点：只保留较近的一个。
void ogxEclipseSortIntersectionOpaque(inout OgxEclipseRayHit hit1, OgxEclipseRayHit hit2,
    inout bool hit, inout vec3 shiftedCurrPos, inout vec3 stepAxis)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    hit1 = firstHit;
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = mix(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = mix(stepAxis, firstHit.stepAxis, fHit);
}

// 栅栏包围盒：横杆加两根立柱，逐个求交后取最近。
void ogxEclipseFenceIntersection(inout vec3 shiftedCurrPos, vec3 reflectedVector, vec3 invReflectedVector,
    inout bool hit, vec3 floorOffsetWorldPos, vec3 floorOffsetWorldPos1, vec3 floorOffsetWorldPos2,
    inout vec3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + vec3(0.375, 0.001, 0.375), floorOffsetWorldPos + vec3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
}

// 双段栅栏：横杆加四根立柱。
void ogxEclipseFenceIntersection2(inout vec3 shiftedCurrPos, vec3 reflectedVector, vec3 invReflectedVector,
    inout bool hit, vec3 floorOffsetWorldPos, vec3 floorOffsetWorldPos1, vec3 floorOffsetWorldPos2,
    vec3 floorOffsetWorldPos3, vec3 floorOffsetWorldPos4, inout vec3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + vec3(0.375, 0.001, 0.375), floorOffsetWorldPos + vec3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - vec3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    OgxEclipseRayHit hit4 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3, floorOffsetWorldPos4, stepAxis); // 第三立柱。
    OgxEclipseRayHit hit5 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3 - vec3(0.0, 0.375, 0.0), floorOffsetWorldPos4 - vec3(0.0, 0.375, 0.0), stepAxis); // 第四立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
}

// 四分之一体素追踪：在低分辨率掩码里走到第一个非空格，返回是否命中。
bool ogxEclipseTraceQuarterVoxel(vec3 reflectedVector, vec3 invReflectedVector, vec3 stepSizes,
    vec3 voxelPos, vec3 stepDir, vec3 nextDist, vec3 currPos, usampler3D quarterVoxelMask, int side)
{
    vec3 quarterVoxelPos = voxelPos / 4.0; // 转四分之一格。
    vec3 originalQuarterVoxelPos = quarterVoxelPos; // 起点备份。
    vec3 quarterNextDist = 4.0 * ((stepDir * 0.5 + 0.5) - fract(quarterVoxelPos)) * invReflectedVector; // 下一边界。
    vec3 quarterCurrPos = currPos; // 当前位置。
    for (int i = 0; i < side / 4; i++) // 固定步数。
    {
        float closestDist = min(min(quarterNextDist.x, quarterNextDist.y), quarterNextDist.z); // 最近边界。
        quarterCurrPos += reflectedVector * closestDist; // 前进。
        vec3 stepAxis = step(quarterNextDist, vec3(closestDist)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x); // 参考实现的轴选择。
        stepAxis.z *= (1.0 - stepAxis.y);
        quarterVoxelPos += stepAxis * stepDir; // 走一格。
        if (clamp(quarterVoxelPos, vec3(0.0), vec3(side / 4)) != quarterVoxelPos) break; // 越界停止。
        uint blockID = texelFetch(quarterVoxelMask, ivec3(quarterVoxelPos), 0).r; // 读掩码。
        if (blockID > 0u && quarterVoxelPos != originalQuarterVoxelPos) return true; // 命中非空。
        quarterNextDist += 4.0 * stepSizes * stepAxis - closestDist; // 推进边界。
    }
    return false; // 没有命中。
}

// 体素阴影投影偏差：参考实现的 `applyShadowBias`。
vec3 ogxEclipseApplyShadowBias(vec3 projectedShadowPosition, vec3 shadowNormal, float shadowDistance,
    float shadowMapResolution)
{
    float biasSize = (shadowDistance / shadowMapResolution * 2.0) * 2.0; // 一个阴影纹素对应的方块比例。
    float biasDistanceFactor = length(projectedShadowPosition.xy); // 离阴影图中心越远偏差越大。
    biasDistanceFactor = 1.0 + biasDistanceFactor * ((16.0 * 8.0) / shadowDistance) * 0.1; // 距离放大。
    return projectedShadowPosition + shadowNormal * biasSize * 0.15 * biasDistanceFactor; // 沿法线推离表面。
}

// 体素阴影主函数：参考实现的 `ComputeVoxelShadowMap`，用显式阴影图与矩阵。
float ogxEclipseComputeVoxelShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade,
    float noise, vec3 geoNormals, sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader, mat4 endShadowMatrix, mat4 endShadowPerspective)
{
    float distortFactor = 1.0; // 边缘压缩系数。
    vec3 projectedShadowPosition; // 阴影图坐标。
    if (!endShader) // 主世界与下界。
    {
        projectedShadowPosition = ogxMatrix3MulPoint(mat3(shadowView), playerPos) + ogxMatrixTranslation(shadowView); // 转到阴影相机。
        vec3 shadowNormal = ogxMatrix3MulPoint(mat3(shadowView), geoNormals); // 法线也转过去。
        projectedShadowPosition = ogxEclipseApplyShadowBias(projectedShadowPosition, shadowNormal, shadowDistance, shadowMapResolution); // 推离表面。
        projectedShadowPosition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * projectedShadowPosition
            + ogxMatrixTranslation(shadowProjection); // 乘投影。
        distortFactor = 1.0 / (log(length(projectedShadowPosition.xy) * distortB + distortA) * distortK); // 边缘压缩。
        projectedShadowPosition.xy *= distortFactor; // 压缩横纵。
        projectedShadowPosition.z += shadowProjection[3][2] * 0.0012; // 深度偏移。
    }
    else // 末地主岛光使用独立矩阵。
    {
        vec4 shadowPos = ogxMatrixMulPoint4(endShadowMatrix, vec4(playerPos, 1.0)); // 末地阴影矩阵。
        vec3 shadowNormal = ogxMatrix3MulPoint(mat3(endShadowMatrix), geoNormals); // 法线。
        shadowPos.xyz = vec4(ogxEclipseApplyShadowBias(shadowPos.xyz, shadowNormal, shadowDistance, shadowMapResolution), 1.0).xyz; // 推离。
        shadowPos = ogxMatrixMulPoint4(endShadowPerspective, shadowPos); // 透视投影。
        projectedShadowPosition = shadowPos.xyz / shadowPos.w; // 齐次除法。
        distortFactor = 1.0; // 末地不做压缩。
    }
    projectedShadowPosition = projectedShadowPosition * vec3(0.5, 0.5, 0.5 / 6.0) + vec3(0.5); // 参考实现的深度缩放。
    float shadowmap = 0.0; // 阴影累加。
    vec3 translucentTint = vec3(0.0); // 彩色半透明阴影。
    int samples = basicFilter ? shadowSampleCount / 2 : 1; // 滤波样本数。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (basicFilter) // 只有开启滤波时才加螺旋偏移。
        {
            float rdMul = (endShader ? 52.0 : 2.4 * distortFactor) * d0k; // 参考实现的半径。
            vec2 offsetS = ogxEclipseCleanVoxelSample(i, float(samples - 1), noise) * rdMul; // 螺旋偏移。
            projectedShadowPosition.xy += offsetS; // 累加偏移。
        }
        if (coloredShadows) // 彩色半透明阴影。
        {
            float shadowDepthDiff = pow(clamp((textureLod(translucentShadowMap, projectedShadowPosition.xy, 0.0).x - projectedShadowPosition.z) * 2.0, 0.0, 1.0), 2.0); // 不透明遮挡差。
            float opaqueShadow = textureLod(opaqueShadowMap, projectedShadowPosition.xy, 0.0).x; // 不透明阴影。
            shadowmap += max(opaqueShadow, shadowDepthDiff); // 取较大。
            vec4 translucentShadow = textureLod(shadowcolor0, projectedShadowPosition.xy, 0.0); // 半透明阴影。
            float shadowAlpha = pow(1.0 - pow(translucentShadow.a, 5.0), 0.2); // 参考实现的透明度曲线。
            translucentShadow.rgb = max(normalize(translucentShadow.rgb + 0.0001), max(opaqueShadow, 1.0 - shadowAlpha)) * shadowAlpha; // 保色相。
            translucentTint += mix(translucentShadow.rgb, vec3(1.0), opaqueShadow * shadowDepthDiff); // 累积染色。
        }
        else
        {
            shadowmap += textureLod(opaqueShadowMap, projectedShadowPosition.xy, 0.0).x; // 普通阴影。
        }
    }
    if (coloredShadows) directLightColor *= mix(vec3(1.0), translucentTint / float(samples), maxDistFade); // 光源染色。
    float shadowResult = shadowmap / float(samples); // 平均阴影。
    if (endShader) // 末地主岛光的圆形范围。
    {
        float r = length(projectedShadowPosition.xy - vec2(0.5)); // 到中心距离。
        if (r < 0.5 && abs(projectedShadowPosition.z) < 1.0) shadowResult *= smoothstep(0.5, 0.25, r); // 软边。
        else shadowResult = 0.0; // 圆外没有光。
    }
    return shadowResult; // 交回阴影。
}

// Photonics 阴影：和体素阴影相同的几何路径，但用 Photonics 采样曲线与固定样本数。
float ogxEclipseComputePhotonicsShadowMap(inout vec3 directLightColor, vec3 playerPos, float maxDistFade,
    float noise, vec3 geoNormals, sampler2D opaqueShadowMap, sampler2D translucentShadowMap, sampler2D shadowcolor0,
    mat4 shadowView, mat4 shadowProjection, float shadowDistance, float shadowMapResolution,
    float distortA, float distortB, float distortK, float d0k, int shadowSampleCount, bool basicFilter,
    bool coloredShadows, bool endShader)
{
    return ogxEclipseComputeVoxelShadowMap(directLightColor, playerPos, maxDistFade, noise, geoNormals,
        opaqueShadowMap, translucentShadowMap, shadowcolor0, shadowView, shadowProjection, shadowDistance, shadowMapResolution,
        distortA, distortB, distortK, d0k, shadowSampleCount, basicFilter, coloredShadows, endShader,
        mat4(1.0), mat4(1.0)); // 末地矩阵在这里不用，传入单位矩阵。
}

// WSR 体素追踪：在三维方块编号图里逐格前进，记录半透明命中与最终不透明命中。
void ogxEclipseTraceWsr(inout OgxEclipseRayJob job, usampler3D voxelIds, sampler3D voxelColors,
    inout OgxEclipseTranslucentHit translucentHits[10], inout uint translucentHitsCount,
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

// 方块光体素版：LPV 采样与手持光由调用方传入，曲线和边缘淡出与参考实现相同。
vec3 ogxEclipseDoBlockLightLightingVoxel(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, vec3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightmapLight *= lightmapLight;
    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot); // 混合曲线。
    vec3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版光照图遮罩。
    vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
    float voxelRangeFalloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
    voxelRangeFalloff = 1.0 - pow(1.0 - pow(voxelRangeFalloff, 1.5), 3.0); // 参考实现的曲线。
    blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), voxelRangeFalloff); // 体积外回退。
    blockLight += handLight; // 手持光直接相加。
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 参考签名版的方块光体素曲线：只保留 `specular.glsl` 默认分支里的光照图曲线。
// 为什么单独一份：增强版还会混入 LPV 与手持光，默认路径的常数集合会多出参考没有的值；
// 严格对照需要一个只做参考算式的入口，调用方按需选择增强版或这一份。
vec3 ogxEclipseDoBlockLightLightingVoxelExact(vec3 lightColor, float lightmap, vec3 lpvSample,
    vec3 handLight, float torchAmount)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 参考实现先把光照图夹到合法范围。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区线性起点。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方让高亮区收窄。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 平方根曲线。
    lightmapLight *= lightmapLight; // 再平方，暗部抬升更明显。
    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot); // 高亮区混向固定亮度。
    vec3 blockLight = lightmapCurve * lightColor; // 光照图乘方块光颜色。
    return blockLight * torchAmount; // 参考实现最后乘火把亮度。
}

// 间接光：Eclipse 的 `doIndirectLighting`，把光照图曲线乘到环境光上。
vec3 ogxEclipseDoIndirectLighting(vec3 lightColor, vec3 minimumLightColor, float lightmap,
    float ambientBrightness, float minLightAmount, float minLightAmountInside, float nightVision)
{
    float lightmapCurve = (pow(lightmap, 15.0) * 2.0 + lightmap * lightmap) / 3.0; // 参考实现的曲线。
    vec3 indirectLight = lightColor * lightmapCurve * ambientBrightness; // 环境光。
    indirectLight += mix(minimumLightColor * (minLightAmount * 0.004 + nightVision * 0.02),
        minimumLightColor * (minLightAmountInside * 0.004 + nightVision * 0.02), 1.0 - lightmap); // 最低亮度。
    return indirectLight; // 交回间接光。
}

// Photonics 反射着色：间接光、方块光、阴影、云影与自发光一起决定命中面颜色。
void ogxEclipsePhotonicsReflectionShading(inout vec4 color, vec3 normal, vec3 worldPos, float noise,
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
    vec3 indirectLighting = ogxEclipseDoIndirectLighting(ambientLightColor * skylight, vec3(1.0),
        lightmap.y, ambientBrightness, minLightAmount, minLightAmountInside, nightVision); // 间接光。
    vec3 playerPosition = worldPos; // 相机相对位置。
    indirectLighting += ogxEclipseDoBlockLightLightingVoxel(torchColor, lightmap.x, lpvSample, handLight,
        lpvPos, lpvSize, fadeLength, torchAmount, vanillaMask); // 方块光。
    float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance + 16.0), 0.0) * 5.0, 1.0)); // 阴影距离淡出。
    float sh = 1.0; // 阳光阴影。
    if (!endShader) sh = ogxEclipseComputePhotonicsShadowMap(directLightColor, playerPosition, shadowMapFalloff,
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
void ogxEclipsePhotonicsReflectionShadingExact(inout vec4 color, vec3 normal, vec3 worldPos, float noise,
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
    vec3 indirectLighting = ogxEclipseDoIndirectLighting(ambientLightColor * skylight, vec3(1.0),
        lightmap.y, ambientBrightness, minLightAmount, minLightAmountInside, nightVision); // 间接光。
    vec3 playerPosition = worldPos; // 相机相对位置。
    indirectLighting += ogxEclipseDoBlockLightLightingVoxelExact(torchColor, lightmap.x, lpvSample, handLight, torchAmount); // 方块光。
    float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(playerPosition) / (shadowDistance + 16.0), 0.0) * 5.0, 1.0)); // 阴影距离淡出。
    float sh = ogxEclipseComputePhotonicsShadowMap(directLightColor, playerPosition, shadowMapFalloff, noise, normal,
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
vec4 ogxEclipsePhotonicsReflection(OgxEclipseRayJob job, OgxEclipseTranslucentHit translucentHits[10],
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
            ogxEclipsePhotonicsReflectionShading(sampleColor, translucentHits[i].hitNormal,
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
        ogxEclipsePhotonicsReflectionShading(sampleColor, job.resultNormal, job.resultPosition, noise.y,
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

// 反射可见度：按 f0 与粗糙度判断高光是否值得显示，避免粗糙金属被反射糊满。
float ogxEclipseGetReflectionVisibility(float f0, float roughness, float roughnessThreshold)
{
    float thresholdValue = roughnessThreshold / 100.0; // 参考实现的百分比。
    float dialectrics = max(f0 * 255.0 - 26.0, 0.0) / 229.0; // 非金属比例。
    float value = 0.35; // 第一段阈值。
    float thresholdA = min(max((1.0 - dialectrics) - value, 0.0) / value, 1.0); // 第一段。
    float smoothness = 1.0 - sqrt(roughness); // 感知光滑度。
    value = thresholdValue; // 第二段阈值。
    float thresholdB = min(max(smoothness - value, 0.0) / value, 1.0); // 第二段。
    value = 0.1; // 超光滑材料保护。
    float thresholdC = 1.0 - min(max(value - (1.0 - smoothness), 0.0) / value, 1.0); // 第三段。
    float visibilityGradient = max(thresholdA * thresholdC - thresholdB, 0.0); // 合成梯度。
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    return visibilityGradient; // 交回可见度。
}

// 环境反射：屏幕空间追踪加历史重投影，天空回退由调用方在 `backgroundReflection` 里处理。
vec4 ogxEclipseGetEnvironmentReflections(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
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
    vec3 raytracePos = ogxEclipseRayTraceSpeculars(ogxMatrix3MulPoint(mat3(modelView), reflectedVector), viewPos,
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
vec3 ogxEclipseRayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, bool hand,
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
    float minZ = spos.z - 0.00025 / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    vec3 hitPos = vec3(1.1); // 默认没有命中。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        if (!hand && (spos.x < 0.0 || spos.x > 1.0 || spos.y < 0.0 || spos.y > 1.0)) return vec3(1.1); // 手部允许出屏。
        float sp; // 屏幕深度；打包格式从 alpha 通道解码。
        if (packedDepth) { sp = ogxEclipseInvLinZ(sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelSize / 4.0), 0).a / 65000.0), nearPlane, farPlane); }
        else { sp = texelFetch(depthTexture, ivec2(spos.xy / texelSize), 0).r; }
        if (sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) // 命中。
        {
            hitPos = vec3(spos.xy / renderScale, sp);
            break;
        }
        minZ = maxZ - biasAmount / ogxEclipseLinZ(spos.z, nearPlane, farPlane); // 推进下界。
        maxZ += stepv.z;
        spos += stepv;
        reflectionLength += 1.0 / quality; // 累积长度。
    }
    if (hand) return reflectedTC; // 手部回退到裁剪坐标。
    return hitPos; // 交回命中。
}

// 高光反射主函数：背景反射、环境反射、太阳 GGX 与手持光 GGX 的合成。
vec3 ogxEclipseSpecularReflections(vec3 viewPos, vec3 playerPos, vec3 NplayerPos, vec3 lightVec,
    vec2 noise, vec3 flatNormal, vec3 normal, float roughness, float f0, vec3 albedo,
    vec3 diffuseLighting, vec3 lightColor, float lightmap, bool isHand, bool isMetalPass,
    vec3 backgroundReflection, vec3 sunlightColor, float sunSpecularMultiplier,
    float roughnessThreshold, bool ssrEnabled, bool backgroundEnabled, vec3 flashlightColor,
    float flashlightIntensity, sampler2D sceneTexture, sampler2D depthTexture,
    mat4 projection, mat4 projectionInverse, mat4 modelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 previousModelView, float nearPlane, float farPlane,
    vec3 cameraDelta, float renderScale, vec2 texelSize)
{
    lightmap = min(max(lightmap - 0.9, 0.0) / 0.1, 1.0); // 光照图重整。
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    roughness = 1.0 - roughness; // 粗糙度反转。
    roughness *= roughness;
    f0 = f0 == 0.0 ? 0.02 : f0; // 默认介电常数。
    bool isMetal = f0 > 229.5 / 255.0; // 金属判定。
    mat3 basis = ogxEclipseFrisvad(normal); // 切线基。
    vec3 viewDir = ogxMatrix3MulPoint(basis, -NplayerPos); // 转到切线空间。
    vec3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), vec3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxEclipseShlickFresnelRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0); // 金属染色。
    vec3 hardCodedMetalsF0[8]; // 参考的八种金属反射率，逐项赋值避免 GLSL 330 的数组构造限制。
    hardCodedMetalsF0[0] = vec3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = vec3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = vec3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = vec3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = vec3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = vec3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = vec3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = vec3(0.961999998804, 0.94946811207, 0.922115710997); // 参考实现的八种金属。
    vec3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    vec3 reflectance = isMetal ? hardCodedMetals : vec3(f0); // 反射率。
    vec3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    vec3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxEclipseGetReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    float backgroundReflectMask = lightmap; // 背景遮罩。
    vec4 environmentReflection = vec4(0.0); // 环境反射。
    vec3 backgroundTint = vec3(1.0); // 背景染色。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        vec3 darkened = isMetal ? diffuseLighting * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        if (backgroundEnabled) specular = mix(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        if (ssrEnabled) // 屏幕空间反射。
        {
            environmentReflection = ogxEclipseGetEnvironmentReflections(reflectedVector, flatNormal, normal,
                playerPos, viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint,
                false, 1.0, sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
                previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale,
                texelSize, 0.0); // 不用 Photonics；主世界默认不在水里。
            specular = mix(specular, environmentReflection.rgb, environmentReflection.a); // 合并环境反射。
        }
        specular = mix(darkened, specular, F0); // 按菲涅耳混合。
        specular = mix(specular, darkened, visibility); // 按可见度回到漫反射。
    }
    if (sunSpecularMultiplier > 0.0) // 太阳高光。
    {
        vec3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * sunlightColor
            * ogxEclipseGgx(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // GGX。
        specular += lightSourceReflection * (1.0 - environmentReflection.a); // 环境反射占用后剩下的部分。
    }
    if (flashlightIntensity > 0.0) // 手电高光。
    {
        vec3 flashLightReflection = flashlightColor * flashlightIntensity
            * ogxEclipseGgx(normal, -normal, -normal, roughness, reflectance, metalAlbedoTint); // 参考实现的手电方向近似。
        specular += flashLightReflection;
    }
    return specular; // 交回高光。
}

// 严格参考签名的高光反射入口：背景天空、环境反射、太阳 GGX 与手电 GGX 的顺序照原程序。
// 参考把天空图、屏幕图、深度图与相机矩阵当全局量；库把它们放在参数表尾部，算式不变。
vec3 ogxEclipseSpecularReflectionsExact(vec3 viewPos, vec3 playerPos, vec3 NplayerPos, vec3 lightVec,
    vec2 noise, vec3 flatNormal, vec3 normal, float roughness, float f0, vec3 albedo,
    vec3 diffuseLighting, vec3 lightColor, float lightmap, bool isHand, bool isWater,
    inout float reflectanceForAlpha, vec4 flashLightStuff, sampler2D skyTexture, vec2 pixelSize,
    vec3 waterAbsorb, float eyeInWater, float sunSpecularMultiplier, float roughnessThreshold,
    sampler2D sceneTexture, sampler2D depthTexture, mat4 projection, mat4 projectionInverse,
    mat4 modelView, mat4 modelViewInverse, mat4 previousProjection, mat4 previousModelView,
    float nearPlane, float farPlane, vec3 cameraDelta, float renderScale, vec2 texelSize,
    float environmentQuality, vec3 flashLightColor, bool handHeldLights, bool firstPersonCamera,
    usampler1D blockDataTexture, int heldItemId, int heldItemId2)
{
    lightmap = min(max(lightmap - 0.9, 0.0) / 0.1, 1.0); // 光照图重整。
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    roughness = 1.0 - roughness; // 粗糙度反转。
    roughness *= roughness;
    f0 = f0 == 0.0 ? 0.02 : f0; // 默认介电常数。
    bool isMetal = f0 > 229.5 / 255.0; // 金属判定。
    mat3 basis = ogxEclipseFrisvad(normal); // 切线基。
    vec3 viewDir = -NplayerPos * basis; // 转到切线空间。
    vec3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), vec3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxEclipseShlickFresnelRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0); // 金属染色。
    vec3 hardCodedMetalsF0[8]; // 参考实现的八种金属。
    hardCodedMetalsF0[0] = vec3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = vec3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = vec3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = vec3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = vec3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = vec3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = vec3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = vec3(0.961999998804, 0.94946811207, 0.922115710997);
    vec3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    vec3 reflectance = isMetal ? hardCodedMetals : vec3(f0); // 反射率。
    vec3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    reflectanceForAlpha = clamp(dot(F0, vec3(0.3333333)), 0.0, 1.0); // 参考实现给水面用的反射率。
    if (eyeInWater == 1 && isWater) // 水下看水面的斯涅尔窗。
    {
        float snellsWindow = min(max(0.54 - clamp(1.0 + VdotN, 0.0, 1.0), 0.0) / 0.1, 1.0);
        snellsWindow = 1.0 - snellsWindow * snellsWindow;
        snellsWindow *= snellsWindow * snellsWindow;
        reflectanceForAlpha = f0 + (1.0 - f0) * snellsWindow;
    }
    vec3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxEclipseGetReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    vec4 environmentReflection = vec4(0.0); // 环境反射。
    float backgroundReflectMask = lightmap; // 背景遮罩从光照图开始。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        vec3 backgroundReflection = ogxEclipseSkyCloudsFromTex(reflectedVector, skyTexture, pixelSize).rgb / 1200.0; // 天空图。
        if (eyeInWater == 1) backgroundReflection *= exp(-waterAbsorb * 15.0) * 2.0; // 水下吸收。
        vec3 backgroundTint = vec3(1.0); // 背景染色。
        environmentReflection = ogxEclipseGetEnvironmentReflections(reflectedVector, flatNormal, normal, playerPos,
            viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint, isWater, environmentQuality,
            sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
            previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale, texelSize, 0.0); // 屏幕空间反射。
        backgroundReflection *= backgroundTint;
        vec3 darkened = isMetal ? diffuseLighting * (1.0 - environmentReflection.a) * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        specular = mix(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        specular = mix(specular, environmentReflection.rgb, environmentReflection.a); // 环境反射。
        specular = mix(darkened, specular, F0); // 菲涅耳混合。
        specular = mix(specular, darkened, visibility); // 可见度回退。
    }
    vec3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * lightColor
        * ogxEclipseGgx(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // 太阳 GGX。
    specular += lightSourceReflection * (1.0 - environmentReflection.a);
    vec3 flashLightReflection = flashLightColor * flashLightStuff.a
        * ogxEclipseGgx(normal, -flashLightStuff.xyz, -flashLightStuff.xyz, roughness, reflectance, metalAlbedoTint); // 手电 GGX。
    specular += flashLightReflection;
    if (handHeldLights && !isHand && firstPersonCamera) // 手持光在反射里的高光。
    {
        if (heldItemId > 0) // 主手。
        {
            vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = ogxMatrix3MulPoint(mat3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            vec3 handLightCol = ogxEclipseGetHandLight(heldItemId, shiftedPlayerPos, lightRange,
                blockDataTexture, vec3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxEclipseGgx(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
        if (heldItemId2 > 0) // 副手。
        {
            vec3 shiftedViewPos = viewPos + vec3(0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = ogxMatrix3MulPoint(mat3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            vec3 handLightCol = ogxEclipseGetHandLight(heldItemId2, shiftedPlayerPos, lightRange,
                blockDataTexture, vec3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxEclipseGgx(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
    }
    return specular;
}

// 体素反射的当前参考实现：追踪主体在原程序里被整段注释，只剩背景遮罩与清空颜色。
// 保留参数与输出，后续恢复追踪时调用方不用改接口。
vec4 ogxEclipseVoxelReflection(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
    float noise, inout float backgroundReflectMask, vec3 directLightColor, vec3 ambientLightColor)
{
    backgroundReflectMask = 1.0; // 参考实现固定回到背景反射。
    return vec4(0.0); // 参考实现的当前颜色输出。
}

// 严格参考签名的体素反射入口：参考正文的追踪整段被注释，实际只算光源颜色并返回零。
// `lightSourceColor` 与 `averageSkyColor` 是参考全局 SSBO 的显式输入，缩放常数照原样保留。
vec4 ogxEclipseVoxelReflectionExact(vec3 reflectedVector, vec3 flatNormal, vec3 normal, vec3 origin,
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
vec4 ogxEclipseRaymarchWsrLpv(vec3 origin, vec3 endPos, float dither, sampler3D densityTexture,
    sampler3D lpvTexture, vec3 cameraOffset, float lpvSize, float fadeLength, float minDensity,
    float mult, int sampleCount, float lpvBrightness, vec3 handLight, float torchAmount, bool vanillaMask)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    vec3 rayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float rayLength = length(rayStart); // 射线长度。
    rayStart *= min(rayLength, min(256.0, 1e6)) / max(rayLength, 1e-6); // 参考实现的距离上限。
    rayLength = length(rayStart);
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = cameraOffset + d * rayStart + origin; // 当前世界位置。
        float density = max(textureLod(densityTexture, progress, 0.0).r / 1000.0, minDensity) * mult; // 密度。
        float volumeCoeff = exp(-dd * density * rayLength); // 本段透过率。
        vec3 lpvPos = (progress - origin) / max(lpvSize, 1.0); // 体积坐标。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘。
        float fade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴淡出。
        if (fade < 0.01) break; // 体积外停止。
        vec3 sampleColor = textureLod(lpvTexture, lpvPos, 0.0).rgb; // LPV 光色。
        if (vanillaMask) sampleColor *= 1.0; // 原版遮罩由调用方预先乘进纹理。
        vec3 lighting = sampleColor * lpvBrightness * 25.0 * exp(-5.0 * (1.0 - ogxLuminance(sampleColor))); // 参考实现的亮度曲线。
        lighting += handLight * torchAmount * lpvBrightness * 0.04; // 手持光。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// 严格参考签名的 LPV 雾入口：密度场、LPV 图与手持光表都作为显式资源。
// 参考在循环里调用 cloudVol、GetLpvPosition、SampleLpvLinear 与 GetHandLight；
// 这里把密度场换成三维纹理，LPV 采样用库里的精确实现，手持光走同一套字节拆包。
vec4 ogxEclipseRaymarchWsrLpvExact(vec3 origin, vec3 endPos, float dither,
    sampler3D densityTexture, sampler3D lpvTexture, vec3 cameraOffset, float lpvSize, float fadeLength,
    float minDensity, int vlSamples, int sampleCount, float lpvBrightness, float torchAmount,
    float caveDetection, float farPlane, vec3 relativeEyePosition, usampler1D blockDataTexture,
    int heldItemId, int heldItemId2, int frameCounter, vec2 blockSkyRange)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 空段直接返回。
    float mult = float(vlSamples) / float(sampleCount) * 1.15; // 参考实现的样本数换算。
    float minimumDensity = minDensity; // 参考实现的最低密度，由调用方按选项给出。
    vec3 lpvRayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float lpvRayLength = length(lpvRayStart); // 射线长度。
    lpvRayStart *= min(lpvRayLength, min(256.0, farPlane)) / lpvRayLength; // 参考实现的距离上限。
    lpvRayLength = length(lpvRayStart); // 截断后的长度。
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定样本数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进位置。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 rayProgress = cameraOffset + d * lpvRayStart + origin; // 当前世界位置。
        float density = 0.0; // 这一步的雾密度。
        float minimumDensityNow = minimumDensity; // 洞穴里抬高最低密度。
        if (caveDetection < 0.9999) density = textureLod(densityTexture, rayProgress, 0.0).r * (1.0 - caveDetection); // 密度场换成显式纹理。
        minimumDensityNow += caveDetection * minimumDensity; // 洞穴补偿。
        density = max(density / 1000.0, minimumDensityNow) * mult; // 参考实现的密度换算。
        float volumeCoeff = exp(-dd * density * lpvRayLength); // 本段透过率。
        vec3 lpvPos = ogxGetLpvPositionExplicit(rayProgress, vec3(0.0), lpvSize); // 体积坐标。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘淡出。
        float lpvFade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        if (lpvFade < 0.01) break; // 走出体积就停。
        vec3 sampleColor = ogxItxSampleLpvLinear(lpvPos, lpvTexture, lpvTexture, frameCounter, lpvSize, blockSkyRange).rgb; // LPV 光色。
        vec3 lighting = sampleColor * lpvBrightness * 25.0
            * exp(-5.0 * (1.0 - dot(sampleColor, vec3(0.21, 0.72, 0.07)))); // 参考亮度曲线与亮度权重。
        float lightRange = 0.0; // 手持光范围。
        vec3 handLight1 = ogxEclipseGetHandLight(heldItemId, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 主手。
        vec3 handLight2 = ogxEclipseGetHandLight(heldItemId2, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 副手。
        lighting += (handLight1 + handLight2) * torchAmount * lpvBrightness * 0.04; // 手持光叠加。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// WSR 的空气雾：固定指数步进，阴影图与密度图共同决定每段散射。
vec4 ogxEclipseRaymarchWsrFog(vec3 origin, vec3 endPos, vec2 dither, vec3 lightColor,
    vec3 ambientColor, vec3 averagedAmbient, int sampleCount, sampler3D densityTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float sunPhase,
    float skyPhase, vec3 sunVector, vec3 atmosphereAbsorption)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    vec3 dVWorld = endPos - origin; // 射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    dVWorld *= min(rayLength, 1e6) / max(rayLength, 1e-6); // 距离上限。
    float dL = length(dVWorld) / 8.0; // 每段长度。
    const float expFactor = 11.0; // 指数步长。
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 总透过率。
    vec3 atmosphere = vec3(1.0); // 大气透过率。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float rayL = ogxRayleighPhase(dot(sunVector, rayDir)); // 瑞利相位。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither.y) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.x) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = d * dVWorld + origin; // 当前世界位置。
        float shadow = 1.0; // 阳光阴影。
        vec3 shadowPos = ogxShadowScreenPos(progress, shadowView, shadowProjection); // 投到阴影图。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) shadow = textureLod(shadowTexture, shadowPos.xy, 0.0).x; // 读阴影。
        float density = textureLod(densityTexture, progress, 0.0).r; // 雾密度。
        float coeff = exp(-density * dd * dL); // 本段透过率。
        vec3 indirect = ambientColor * skyPhase; // 天空散射。
        vec3 direct = lightColor * sunPhase * shadow; // 太阳散射。
        vec3 lighting = direct + indirect; // 本段照明。
        color += (lighting - lighting * coeff) * totalAbsorbance; // 累积散射。
        totalAbsorbance *= coeff; // 累积透过率。
        if (totalAbsorbance < 0.01) break; // 足够浓就停。
        vec3 atmosphereCoeff = exp(-atmosphereAbsorption * dd * dL); // 大气吸收。
        vec3 haze = (lightColor * shadow * rayL + averagedAmbient) * (1.0 - atmosphereCoeff); // 空气透视。
        color += haze * atmosphere; // 叠加空气透视。
        atmosphere *= atmosphereCoeff; // 累积大气透过率。
    }
    return vec4(color, totalAbsorbance); // 交回雾。
}

// WSR 水下体积：水吸收、焦散与方向光一起决定水下光柱。
vec4 ogxEclipseWsrWaterVolumetrics(vec3 origin, vec3 endPos, vec2 dither, vec3 ambient,
    vec3 lightSource, vec3 lpv, vec3 waterAbsorption, vec3 dirtScatter, float waterAltitude,
    float sunElevation, float bubbleScale, float phaseScale)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有水体。
    const int sampleCount = 3; // 参考实现的固定三步。
    vec3 dVWorld = endPos - origin; // 射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    dVWorld *= min(rayLength, 1e6) / max(rayLength, 1e-6); // 距离上限。
    vec3 absorbance = vec3(1.0); // 累积吸收。
    vec3 result = vec3(0.0); // 累积颜色。
    vec3 rayDir = normalize(endPos - origin); // 射线方向。
    float vdotl = dot(vec3(0.0, 1.0, 0.0), rayDir); // 参考实现的太阳方向近似。
    float phase = ogxEclipseFogPhase(vdotl) * phaseScale; // 雾相位。
    float thing = -normalize(dVWorld).y; // 垂直方向。
    thing = clamp(thing + 0.333, 0.0, 1.0);
    thing = pow(1.0 - pow(1.0 - thing, 2.0), 2.0) * 15.0; // 参考实现的形状。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定三步。
    {
        float d = (pow(expFactor, float(i) + dither.x) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.y) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = d * dVWorld; // 相机相对位置。
        float distanceFromSurface = max(-(progress.y - waterAltitude), 0.0); // 到水面的距离。
        float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / bubbleScale, 0.0, 1.0)); // 气泡。
        float caustics = max(phase * 0.5 * mix(0.5, 1.5, bubble), phase); // 焦散。
        vec3 sunAbsorbance = exp(-waterAbsorption * (distanceFromSurface / max(abs(vec3(0.0, 1.0, 0.0).y), 1e-6))); // 太阳吸收。
        vec3 waterAbsorbance = exp(-waterAbsorption * (distanceFromSurface + thing)); // 水体吸收。
        vec3 direct = lightSource * phase * caustics * sunAbsorbance; // 直射。
        vec3 indirect = ambient * waterAbsorbance; // 间接。
        vec3 light = (indirect + direct + lpv) * dirtScatter; // 总光。
        vec3 volumeCoeff = exp(-waterAbsorption * length(dd * dVWorld)); // 本段吸收。
        result += (light - light * volumeCoeff) / max(waterAbsorption, vec3(1e-6)) * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积吸收。
    }
    return vec4(result, dot(absorbance, vec3(0.333333))); // 交回水体颜色与透过率。
}

#endif
