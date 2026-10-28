/*
体素反射子文件：从表面沿反射方向在三维编号图里逐格前进，撞到实心方块就着色返回。
调用位置：由 `voxel/voxel.slang` 内联引入，宿主只引用主模块即可拿到追踪入口。
可复制示例：`float4 hit = ogxVoxelReflection(origin, dir, normal, offset, side, ids, colors, torch, sky, sun, sunDir, 64.0, 1.0, hitPos);`
设计原因与取舍：
    追踪要同时读编号图与颜色图，和写入端只做格号换算的职责不同，因此单独成文件；
    半透明染色、铁块镜面弹射与距离封顶都留在这一份，避免主文件继续变长。
*/

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置；返回值 `a` 为负表示没有命中。
float4 ogxVoxelReflection(float3 originWorld, float3 rayDirWorld, float3 surfaceNormal, float3 voxelOffset, int side,
    Usampler3D voxelIdTexture, Sampler3D voxelColorTexture, float3 torchColor, float3 skyColor,
    float3 sunColor, float3 sunDirection, float maxDistance, float strength, out float3 hitWorldPos)
{
    hitWorldPos = originWorld; // 先给一个占位，命中时才被真正赋值。
    if (dot(rayDirWorld, surfaceNormal) <= 0.0) return float4(0.0, 0.0, 0.0, -1.0); // 射线朝表面内侧，追踪没有意义。
    const int maxSteps = 320; // 每根射线最多走的格数，覆盖整条体积对角线还有余量。
    const int ironBounces = 4; // 铁块镜面最多弹射几次，防止两面镜子互相反射把循环拖满。
    float maxDist = min(maxDistance, float(side)); // 追踪距离不超过体积边长。
    float3 accumTint = float3(1.0); // 半透明方块累积的染色，最后乘到后面的画面上。
    float traveled = 0.0; // 已经走过的米数，跨镜面弹射累加，用来对总距离封顶。
    float3 posWorld = originWorld + surfaceNormal * 0.05; // 起点沿法线抬起一点，避开表面自身那一格。
    float3 dir = rayDirWorld; // 当前这段射线的方向，铁块弹射后会被改掉。
    for (int bounce = 0; bounce <= ironBounces; bounce++) // 每多弹一次镜面就多跑一段直线步进。
    {
        float3 gridPos = posWorld + voxelOffset; // 转成体素网格坐标，整数边界就是体素边界。
        int3 cell = int3(floor(gridPos)); // 起点所在体素下标。
        if (!ogxVoxelInside(cell, side)) return float4(0.0, 0.0, 0.0, -1.0); // 起点不在体积内，无法追踪。
        int3 stepDir = int3(sign(dir)); // 每轴前进方向，正负一或零。
        float3 invDir = 1.0 / dir; // 方向倒数，用来算跨边界的参数距离。
        float3 tDelta = abs(invDir); // 跨过一整格所需的参数距离。
        float3 tMax = float3(1e30); // 到下一个边界的参数距离；方向为零的轴保持极大值，不会被先选中。
        if (dir.x != 0.0) tMax.x = (float(cell.x) + max(sign(dir.x), 0.0) - gridPos.x) * invDir.x; // 横轴到边界的距离。
        if (dir.y != 0.0) tMax.y = (float(cell.y) + max(sign(dir.y), 0.0) - gridPos.y) * invDir.y; // 纵轴到边界的距离。
        if (dir.z != 0.0) tMax.z = (float(cell.z) + max(sign(dir.z), 0.0) - gridPos.z) * invDir.z; // 深度轴到边界的距离。
        bool mirrored = false; // 这一段是否以击中铁块镜面结束。
        for (int i = 0; i < maxSteps; i++)
        {
            float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近的一次跨格距离。
            if (traveled + tMin > maxDist) return float4(0.0, 0.0, 0.0, -1.0); // 总距离超出上限，没有命中。
            float3 faceNormal = float3(0.0); // 本次进入体素的朝向；沿哪个轴走就从它的对面进入。
            if (tMax.x <= tMin) { cell.x += stepDir.x; tMax.x += tDelta.x; faceNormal.x = -float(stepDir.x); } // 走横轴这一格。
            else if (tMax.y <= tMin) { cell.y += stepDir.y; tMax.y += tDelta.y; faceNormal.y = -float(stepDir.y); } // 走纵轴这一格。
            else { cell.z += stepDir.z; tMax.z += tDelta.z; faceNormal.z = -float(stepDir.z); } // 走深度轴这一格。
            if (!ogxVoxelInside(cell, side)) return float4(0.0, 0.0, 0.0, -1.0); // 走出体积，后面的格子没有编号。
            uint voxelId = voxelIdTexture.Load(int4(cell, 0)).r; // 读这一格的方块编号。
            if (voxelId == 0u) continue; // 空气，继续走。
            if (ogxVoxelIsPlant(voxelId)) continue; // 植物不挡光，继续走。
            float4 stored = voxelColorTexture.Load(int4(cell, 0)); // 读这一格的颜色与光照。
            float3 albedo = ogxSrgbToLinear(stored.rgb); // 贴图色从 sRGB 换回线性，与场景单位一致。
            if (ogxVoxelIsTranslucent(voxelId)) { accumTint *= ogxVoxelTranslucentTint(voxelId, albedo); continue; } // 水冰玻璃按彩色水染色后继续。
            float3 hitPoint = posWorld + dir * tMin; // 本次刚跨进来的边界点，就是命中面所在位置。
            if (ogxVoxelIsIron(voxelId) && bounce < ironBounces) // 铁块镜面：弹开再追，铁块自己不上色。
            {
                traveled += tMin; // 把这一段长度计入总距离。
                hitWorldPos = hitPoint; // 先记住镜面位置，后续万一没命中仍有合理取值。
                posWorld = hitPoint + faceNormal * 0.01; // 起点抬离镜面，避免下一次步进又落回同一格。
                dir = reflect(dir, faceNormal); // 按进入面法线弹射。
                mirrored = true; // 标记本段以镜面结束，去跑下一段。
                break; // 退出内层，外层用新的起点与方向重设步进状态。
            }
            hitWorldPos = hitPoint; // 命中点的相机相对世界位置，调用方用它算雾段。
            float3 shaded = ogxVoxelShade(albedo, faceNormal, stored.a, torchColor, skyColor, sunColor, sunDirection, strength) * accumTint; // 按体素面法线着色并乘上半透明染色。
            return float4(shaded, ogxSaturate((traveled + tMin) / maxDist)); // 归一化总命中距离放进 a，供反射滤波使用。
        }
        if (!mirrored) return float4(0.0, 0.0, 0.0, -1.0); // 走到步数上限还没命中，交给调用方走天空回退。
    }
    return float4(0.0, 0.0, 0.0, -1.0); // 镜面弹射次数用尽仍未命中，交给调用方走天空回退。
}

