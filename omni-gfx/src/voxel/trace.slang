/*
Omni 通用图形库体素求交模块：射线任务、包围盒、栅栏、裁剪排序、四分之一体素与螺旋采样。
调用位置：体素反射、阴影与可见性判断；由 `/omni-gfx/voxel/trace.glsl` 引入。
可复制示例：
    OgxRayJob job = ogxRayJob(origin, direction); // 构造射线任务。
    float2 hit = ogxVoxelSampleOffset(3, 8.0, 0.5); // 取螺旋采样点。
设计原因与取舍：
    所有求交只依赖整数格与几何参数；裁剪命中会读体素面表，其余路径不读取宿主纹理。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。体素求交目前只被库内反射与阴影模块间接引用，没有独立画面入口。
*/
#ifndef OGX_VOXEL_TRACE_INCLUDED
#define OGX_VOXEL_TRACE_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"
// 体素提供坐标、材质与发光读取。
#include "voxel.slang"

// 体素包围盒求交结果：命中、参数、位置与进入面轴。
struct OgxRayHit
{
    bool hit; // 是否命中。
    float t; // 射线参数。
    float3 currPos; // 命中位置。
    float3 stepAxis; // 进入面轴。
};

// 体素射线任务：起点、方向、结果。
struct OgxRayJob
{
    float3 origin; // 起点，体积坐标。
    float3 direction; // 方向。
    float3 resultPosition; // 命中位置。
    float3 resultColor; // 命中颜色。
    float3 resultNormal; // 命中法线。
    bool resultHit; // 是否命中。
};

// 半透明命中：给反射链逐层染色。
struct OgxTranslucentHit
{
    float3 hitNormal; // 命中面法线。
    float3 hitPos; // 命中点。
    float4 hitColor; // 颜色与透明度。
    int hitId; // 方块编号。
    float skylight; // 天光。
};

// 构造一个体素射线任务。
OgxRayJob ogxRayJob(float3 origin, float3 direction){
    OgxRayJob job; // 逐字段赋值，避免结构体构造顺序出错。
    job.origin = origin;
    job.direction = direction;
    job.resultPosition = float3(0.0);
    job.resultColor = float3(0.0);
    job.resultNormal = float3(0.0);
    job.resultHit = false;
    return job;
}

// 体素包围盒求交：返回结构体版本，和参考实现的 `AABBintersection2` 相同。
OgxRayHit ogxVoxelAabbHit(float3 currPos, float3 reflectedVector, float3 stepSizes,
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
    OgxRayHit result; // 结果。
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
void ogxSortIntersectionCutout(OgxRayHit hit1, OgxRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos);

// Eclipse 裁剪命中排序入口：保留旧的参数顺序，方便现有调用方逐项迁移。
void ogxSortIntersectionCutoutReference(OgxRayHit hit1, OgxRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos)
{
    ogxSortIntersectionCutout(hit1, hit2, stepDir, gtexSize, texCoordOffset, voxelPos,
        hit, shiftedCurrPos, stepAxis, gtexture, voxelDataTexture, voxelSize, cameraWorldPos);
}

// 镂空求交排序的实际定义：按距离与面朝向保留最近命中，供反射与阴影使用。
void ogxSortIntersectionCutout(OgxRayHit hit1, OgxRayHit hit2, float3 stepDir,
    float2 gtexSize, float2 texCoordOffset, float3 voxelPos, inout bool hit,
    inout float3 shiftedCurrPos, inout float3 stepAxis, Sampler2D gtexture,
    Sampler2D voxelDataTexture, int voxelSize, float3 cameraWorldPos)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    OgxRayHit secondHit = useFirst ? hit2 : hit1; // 第二命中。
    float2 texCoord; // 贴图坐标。
    float3 voxelNormal = -firstHit.stepAxis * stepDir; // 进入面法线。
    ogxGetVoxelFaceTexCoord(int3(voxelPos), texCoord, voxelNormal, voxelDataTexture, voxelSize); // 从体素面表读贴图坐标。
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
void ogxSortIntersectionOpaque(inout OgxRayHit hit1, OgxRayHit hit2,
    inout bool hit, inout float3 shiftedCurrPos, inout float3 stepAxis)
{
    bool useFirst = hit1.hit && (!hit2.hit || hit1.t < hit2.t); // 较近的优先。
    OgxRayHit firstHit = useFirst ? hit1 : hit2; // 第一命中。
    hit1 = firstHit;
    hit = firstHit.hit;
    float fHit = float(hit);
    shiftedCurrPos = lerp(shiftedCurrPos, firstHit.currPos, fHit);
    stepAxis = lerp(stepAxis, firstHit.stepAxis, fHit);
}

// 栅栏包围盒：横杆加两根立柱，逐个求交后取最近。
void ogxFenceAabbIntersect(inout float3 shiftedCurrPos, float3 reflectedVector, float3 invReflectedVector,
    inout bool hit, float3 floorOffsetWorldPos, float3 floorOffsetWorldPos1, float3 floorOffsetWorldPos2,
    inout float3 stepAxis)
{
    OgxRayHit hit1 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + float3(0.375, 0.001, 0.375), floorOffsetWorldPos + float3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxRayHit hit2 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxRayHit hit3 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - float3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    ogxSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
}

// 双段栅栏：横杆加四根立柱。
void ogxFenceAabbIntersect2(inout float3 shiftedCurrPos, float3 reflectedVector, float3 invReflectedVector,
    inout bool hit, float3 floorOffsetWorldPos, float3 floorOffsetWorldPos1, float3 floorOffsetWorldPos2,
    float3 floorOffsetWorldPos3, float3 floorOffsetWorldPos4, inout float3 stepAxis)
{
    OgxRayHit hit1 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos + float3(0.375, 0.001, 0.375), floorOffsetWorldPos + float3(0.625, 0.999, 0.625), stepAxis); // 横杆。
    OgxRayHit hit2 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1, floorOffsetWorldPos2, stepAxis); // 第一立柱。
    OgxRayHit hit3 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos1 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos2 - float3(0.0, 0.375, 0.0), stepAxis); // 第二立柱。
    OgxRayHit hit4 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3, floorOffsetWorldPos4, stepAxis); // 第三立柱。
    OgxRayHit hit5 = ogxVoxelAabbHit(shiftedCurrPos, reflectedVector, invReflectedVector,
        floorOffsetWorldPos3 - float3(0.0, 0.375, 0.0), floorOffsetWorldPos4 - float3(0.0, 0.375, 0.0), stepAxis); // 第四立柱。
    ogxSortIntersectionOpaque(hit1, hit2, hit, shiftedCurrPos, stepAxis);
    ogxSortIntersectionOpaque(hit1, hit3, hit, shiftedCurrPos, stepAxis);
    ogxSortIntersectionOpaque(hit1, hit4, hit, shiftedCurrPos, stepAxis);
    ogxSortIntersectionOpaque(hit1, hit5, hit, shiftedCurrPos, stepAxis);
}

// 四分之一体素追踪：在低分辨率掩码里走到第一个非空格，返回是否命中。
bool ogxQuarterVoxelTrace(float3 reflectedVector, float3 invReflectedVector, float3 stepSizes,
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
        // 逐分量判断四分之一体素的边界：Slang 的向量比较返回布尔向量，不能直接当条件。
        float maxQuarter = float(side / 4);
        if (quarterVoxelPos.x < 0.0 || quarterVoxelPos.y < 0.0 || quarterVoxelPos.z < 0.0 ||
            quarterVoxelPos.x > maxQuarter || quarterVoxelPos.y > maxQuarter || quarterVoxelPos.z > maxQuarter) break; // 越界停止。
        uint blockID = quarterVoxelMask.Load(int4(int3(quarterVoxelPos), 0)).r; // 读掩码。
        // 逐分量比较：GLSL 的向量 != 返回单个布尔值，Slang 返回布尔向量，不能共用 any()。
        if (blockID > 0u && (quarterVoxelPos.x != originalQuarterVoxelPos.x ||
            quarterVoxelPos.y != originalQuarterVoxelPos.y ||
            quarterVoxelPos.z != originalQuarterVoxelPos.z)) return true; // 命中非空。
        quarterNextDist += 4.0 * stepSizes * stepAxis - closestDist; // 推进边界。
    }
    return false; // 没有命中。
}

// 体素平面求交：只接受落在两格以内且仍在同一格内的交点。
bool ogxVoxelPlaneIntersect(inout float3 currPos, float worldOffset, inout float3 voxelPos, float3 reflectedVector,
    inout float3 stepAxis, float3 normal)
{
    float denom = dot(reflectedVector, normal); // 平面法线与射线。
    if (abs(denom) < 1e-6) return false; // 平行。
    float t = -(dot(currPos, normal) - worldOffset) / denom; // 交点参数。
    if (t > 0.0 && t < 2.0) // 只接受近处交点。
    {
        float3 hitPos = currPos + t * reflectedVector; // 交点。
        // 逐分量比较：避免 GLSL 与 Slang 对向量 == 的返回值不同。
        if (int3(voxelPos).x == int3(hitPos).x && int3(voxelPos).y == int3(hitPos).y &&
            int3(voxelPos).z == int3(hitPos).z) // 仍在同一格。
        {
            currPos = hitPos;
            stepAxis = normal;
            return true;
        }
    }
    return false; // 没有有效交点。
}

// 体素包围盒求交：返回是否命中，并把位置推进到入口。
bool ogxVoxelAabbIntersect(inout float3 currPos, float3 reflectedVector, float3 stepSizes, float3 boxMin,
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
float2 ogxVoxelSampleOffset(int samples, float totalSamples, float noise)
{
    float variance = noise * 0.897; // 每像素抖动。
    float variedSamples = float(samples) + variance; // 抖动后的样本号。
    float spiralShape = sqrt(variedSamples / (totalSamples + variance)); // 半径。
    float shape = 2.26; // 参考实现的关键旋转系数。
    float theta = variedSamples * (OGX_PI * shape); // 角度。
    return float2(cos(theta) * spiralShape, sin(theta) * spiralShape); // 螺旋点。
}

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// `originWorld` 是表面相机相对世界位置，`rayDirWorld` 是世界空间反射方向，`surfaceNormal` 是表面法线；
// `voxelOffset` 是相机相对位置到体积坐标的平移，`side` 是每边单元数。
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。

/*
实现说明：体素求交工具。
一、射线任务：`OgxRayJob` 保存起点、方向与命中结果，构造时全部清零。
二、包围盒：逐轴求入口与出口，取最晚入口与最早出口，命中时把位置推进到入口。
三、栅栏：横杆加立柱，多次求交后取最近；双段栅栏是四根立柱的扩展。
四、裁剪排序：先取较近交点，再用贴图 alpha 判断是否穿过去。
五、四分之一体素：低分辨率掩码逐格前进，命中非空格就停。
六、平面求交：只接受两格以内且仍在同一格的交点。
七、螺旋采样：样本序号变成圆上的螺旋点，抖动让相邻像素错开。
八、边界：求交只依赖整数格与几何参数，贴图由调用方传入。
*/
/*
函数索引：
一、`ogxRayJob`：构造射线任务，结果字段清零。
二、`ogxVoxelAabbHit`：包围盒求交，返回结构体。
三、`ogxSortIntersectionCutout`：裁剪命中排序，按贴图 alpha 决定是否穿过。
四、`ogxSortIntersectionCutoutReference`：参考签名版本。
五、`ogxSortIntersectionOpaque`：只保留较近的不透明交点。
六、`ogxFenceAabbIntersect` 与 `ogxFenceAabbIntersect2`：栅栏横杆与立柱求交。
七、`ogxQuarterVoxelTrace`：四分之一体素掩码步进。
八、`ogxVoxelPlaneIntersect`：平面求交，只接受两格以内。
九、`ogxVoxelAabbIntersect`：返回是否命中并推进位置。
十、`ogxVoxelSampleOffset`：螺旋采样点。
十一、边界：求交只依赖整数格与几何参数。
十二、顺序：先取最近交点，再用贴图判断是否穿过。
*/
/*
参数与边界：
一、射线方向要归一化，参数距离才有统一含义。
二、包围盒的上下界按分量排序。
三、栅栏的横杆与立柱位置来自方块局部坐标。
四、裁剪排序读取贴图 alpha，纹理坐标由调用方给出。
五、四分之一体素的边长是体积边长的四分之一。
六、平面求交只接受两格以内的交点。
七、螺旋采样的总数必须大于零。
八、所有纹理句柄显式传入，库不读取宿主槽位。
九、求交只依赖整数格与几何参数。
十、画面验证要看体素反射边缘与栅栏轮廓。
*/
#endif
