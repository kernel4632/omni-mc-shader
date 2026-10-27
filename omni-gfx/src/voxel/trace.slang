/*
Omni 通用图形库体素求交模块：射线任务、包围盒、栅栏、裁剪排序、四分之一体素与螺旋采样。
调用位置：体素反射、阴影与可见性判断；由 `/omni-gfx/voxel/trace.glsl` 引入。
可复制示例：
    OgxEclipseRayJob job = ogxEclipseRayJob(origin, direction); // 构造射线任务。
    float2 hit = ogxEclipseCleanVoxelSample(3, 8.0, 0.5); // 取螺旋采样点。
设计原因与取舍：
    所有求交只依赖整数格与几何参数；裁剪命中会读体素面表，其余路径不读取宿主纹理。
*/
#ifndef OGX_VOXEL_TRACE_INCLUDED
#define OGX_VOXEL_TRACE_INCLUDED

#include "../math.slang"
#include "voxel.slang"

// 体素包围盒求交结果：命中、参数、位置与进入面轴。
struct OgxEclipseRayHit
{
    bool hit; // 是否命中。
    float t; // 射线参数。
    float3 currPos; // 命中位置。
    float3 stepAxis; // 进入面轴。
};

// 体素射线任务：起点、方向、结果。
struct OgxEclipseRayJob
{
    float3 origin; // 起点，体积坐标。
    float3 direction; // 方向。
    float3 resultPosition; // 命中位置。
    float3 resultColor; // 命中颜色。
    float3 resultNormal; // 命中法线。
    bool resultHit; // 是否命中。
};

// 半透明命中：给反射链逐层染色。
struct OgxEclipseTranslucentHit
{
    float3 hitNormal; // 命中面法线。
    float3 hitPos; // 命中点。
    float4 hitColor; // 颜色与透明度。
    int hitId; // 方块编号。
    float skylight; // 天光。
};

// 构造一个体素射线任务。
OgxEclipseRayJob ogxEclipseRayJob(float3 origin, float3 direction){
    OgxEclipseRayJob job; // 逐字段赋值，避免结构体构造顺序出错。
    job.origin = origin;
    job.direction = direction;
    job.resultPosition = float3(0.0);
    job.resultColor = float3(0.0);
    job.resultNormal = float3(0.0);
    job.resultHit = false;
    return job;
}

// 体素包围盒求交：返回结构体版本，和参考实现的 `AABBintersection2` 相同。
OgxEclipseRayHit ogxEclipseAabbIntersection2(float3 currPos, float3 reflectedVector, float3 stepSizes,
    float3 boxMin, float3 boxMax, float3 stepAxis)
{
    float3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    float3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    float3 tmin = min(t1, t2); // 每轴入口。
    float3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    OgxEclipseRayHit result; // 结果。
    result.hit = hit;
    result.t = tmin0;
    float3 entryDist = abs(tmin - float3(tmin0)); // 哪一轴最先进入。
    float3 normal = step(entryDist, float3(0.0)); // 入口轴标记。
    result.stepAxis = lerp(stepAxis, normal, fHit); // 命中时更新轴。
    result.currPos = lerp(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return result; // 交回结构体。
}

// 排序两个裁切体素交点：先取较近的，再用贴图 alpha 判断是否穿过去。
// 裁剪命中排序的提前声明：参考参数在前，体素面表、贴图、相机位置作为显式资源追加。
void ogxEclipseSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos);

// Eclipse 裁剪命中排序入口：保留旧的参数顺序，方便现有调用方逐项迁移。
void ogxItxSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos)
{
    ogxEclipseSortIntersectionCutout(hit1, hit2, stepDir, gtexSize, texCoordOffset, voxelPos,
        hit, shiftedCurrPos, stepAxis, gtexture, voxelDataTexture, voxelSize, cameraWorldPos);
}

// 镂空求交排序的实际定义：按距离与面朝向保留最近命中，供反射与阴影使用。
void ogxEclipseSortIntersectionCutout(OgxEclipseRayHit hit1, OgxEclipseRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    OgxEclipseRayHit secondHit = useFirst ? hit2 : hit1; // 第二命中。
    float2 texCoord; // 贴图坐标。
    float3 voxelNormal = -firstHit.stepAxis * stepDir; // 进入面法线。
    ogxEclipseGetTexCoord(int3(voxelPos), texCoord, voxelNormal, voxelDataTexture, voxelSize); // 从体素面表读贴图坐标。
    float3 wPos = firstHit.currPos + cameraWorldPos; // 转成绝对世界位置。
    float2 sampleDir = firstHit.stepAxis.x * fract(wPos.zy) + firstHit.stepAxis.y * fract(wPos.xz)
        + firstHit.stepAxis.z * fract(wPos.xy); // 进入面内的采样方向。
    texCoord = lerp(texCoord + float2(0.0, texCoordOffset.y), texCoord - float2(0.0, texCoordOffset.y), sampleDir); // 纵向偏移。
    texCoord = lerp(texCoord + float2(texCoordOffset.x, 0.0), texCoord - float2(texCoordOffset.x, 0.0), sampleDir); // 横向偏移。
    float sampleAlpha = gtexture.SampleLevel(texCoord, 0.0).a; // 参考实现的纹理采样。
    firstHit = sampleAlpha > 0.1 ? firstHit : secondHit; // 透明就穿到第二命中。
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = lerp(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = lerp(stepAxis, firstHit.stepAxis, fHit);
}

// 排序两个不透明体素交点：只保留较近的一个。
void ogxEclipseSortIntersectionOpaque(inout OgxEclipseRayHit hit1, OgxEclipseRayHit hit2,
    inout bool hit, inout float3 shiftedCurrPos, inout float3 stepAxis)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxEclipseRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    hit1 = firstHit;
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = lerp(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = lerp(stepAxis, firstHit.stepAxis, fHit);
}

// 栅栏包围盒：横杆加两根立柱，逐个求交后取最近。
void ogxEclipseFenceIntersection(inout float3 shiftedCurrPos, float3 reflectedVector, float3 invReflectedVector,
    inout bool hit, float3 floorOffsetWorldPos, float3 floorOffsetWorldPos1, float3 floorOffsetWorldPos2,
    inout float3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + float3(0.375, 0.001, 0.375), floorOffsetWorldPos + float3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - float3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
}

// 双段栅栏：横杆加四根立柱。
void ogxEclipseFenceIntersection2(inout float3 shiftedCurrPos, float3 reflectedVector, float3 invReflectedVector,
    inout bool hit, float3 floorOffsetWorldPos, float3 floorOffsetWorldPos1, float3 floorOffsetWorldPos2,
    float3 floorOffsetWorldPos3, float3 floorOffsetWorldPos4, inout float3 stepAxis)
{
    OgxEclipseRayHit hit1 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + float3(0.375, 0.001, 0.375), floorOffsetWorldPos + float3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxEclipseRayHit hit2 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxEclipseRayHit hit3 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - float3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    OgxEclipseRayHit hit4 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3, floorOffsetWorldPos4, stepAxis); // 第三立柱。
    OgxEclipseRayHit hit5 = ogxEclipseAabbIntersection2(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos4 - float3(0.0, 0.375, 0.0), stepAxis); // 第四立柱。
    ogxEclipseSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
    ogxEclipseSortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
}

// 四分之一体素追踪：在低分辨率掩码里走到第一个非空格，返回是否命中。
bool ogxEclipseTraceQuarterVoxel(float3 reflectedVector, float3 invReflectedVector, float3 stepSizes,
    float3 voxelPos, float3 stepDir, float3 nextDist, float3 currPos, Usampler3D quarterVoxelMask, int side)
{
    float3 quarterVoxelPos = voxelPos / 4.0; // 转四分之一格。
    float3 originalQuarterVoxelPos = quarterVoxelPos; // 起点备份。
    float3 quarterNextDist = 4.0 * ((stepDir * 0.5 + 0.5) - fract(quarterVoxelPos)) * invReflectedVector; // 下一边界。
    float3 quarterCurrPos = currPos; // 当前位置。
    for (int i = 0; i < side / 4; i++) // 固定步数。
    {
        float closestDist = min(min(quarterNextDist.x, quarterNextDist.y), quarterNextDist.z); // 最近边界。
        quarterCurrPos += reflectedVector * closestDist; // 前进。
        float3 stepAxis = step(quarterNextDist, float3(closestDist)); // 哪一轴先到。
        stepAxis.yz *= (1.0 - stepAxis.x); // 参考实现的轴选择。
        stepAxis.z *= (1.0 - stepAxis.y);
        quarterVoxelPos += stepAxis * stepDir; // 走一格。
        if (clamp(quarterVoxelPos, float3(0.0), float3(side / 4)) != quarterVoxelPos) break; // 越界停止。
        uint blockID = quarterVoxelMask.Load(int4(int3(quarterVoxelPos), 0)).r; // 读掩码。
        if (blockID > 0u && quarterVoxelPos != originalQuarterVoxelPos) return true; // 命中非空。
        quarterNextDist += 4.0 * stepSizes * stepAxis - closestDist; // 推进边界。
    }
    return false; // 没有命中。
}

// 体素平面求交：只接受落在两格以内且仍在同一格内的交点。
bool ogxEclipsePlaneIntersect(inout float3 currPos, float worldOffset, inout float3 voxelPos, float3 reflectedVector,
    inout float3 stepAxis, float3 normal)
{
    float denom = dot(reflectedVector, normal); // 平面法线与射线。
    if (abs(denom) < 1e-6) return false; // 平行。
    float t = -(dot(currPos, normal) - worldOffset) / denom; // 交点参数。
    if (t > 0.0 && t < 2.0) // 只接受近处交点。
    {
        float3 hitPos = currPos + t * reflectedVector; // 交点。
        if (all(equal(int3(voxelPos), int3(hitPos)))) // 仍在同一格。
        {
            currPos = hitPos;
            stepAxis = normal;
            return true;
        }
    }
    return false; // 没有有效交点。
}

// 体素包围盒求交：返回是否命中，并把位置推进到入口。
bool ogxEclipseAabbIntersection(inout float3 currPos, float3 reflectedVector, float3 stepSizes, float3 boxMin,
    float3 boxMax, inout float3 stepAxis)
{
    float3 t1 = (boxMin - currPos) * stepSizes; // 近平面参数。
    float3 t2 = (boxMax - currPos) * stepSizes; // 远平面参数。
    float3 tmin = min(t1, t2); // 每轴入口。
    float3 tmax = max(t1, t2); // 每轴出口。
    float tmin0 = max(max(tmin.x, tmin.y), tmin.z); // 最晚入口。
    float tmax0 = min(min(tmax.x, tmax.y), tmax.z); // 最早出口。
    bool hit = tmin0 < tmax0 && tmin0 > 0.0; // 有效区间。
    float fHit = float(hit); // 转浮点。
    float3 entryDist = abs(tmin - float3(tmin0)); // 哪一轴最先进入。
    float3 normal = step(entryDist, float3(0.0)); // 入口轴标记。
    stepAxis = lerp(stepAxis, normal, fHit); // 命中时更新轴。
    currPos = lerp(currPos, currPos + tmin0 * reflectedVector, fHit); // 命中时推进到入口。
    return hit; // 交回命中。
}

// 体素采样螺旋：把样本序号变成单位圆上的螺旋点，2.26 是参考实现的关键常数。
float2 ogxEclipseCleanVoxelSample(int samples, float totalSamples, float noise)
{
    float variance = noise * 0.897; // 每像素抖动。
    float variedSamples = float(samples) + variance; // 抖动后的样本号。
    float spiralShape = sqrt(variedSamples / (totalSamples + variance)); // 半径。
    float shape = 2.26; // 参考实现的关键旋转系数。
    float theta = variedSamples * (OGX_PI * shape); // 角度。
    return float2(cos(theta) * spiralShape, sin(theta) * spiralShape); // 螺旋点。
}

#endif
