/*
体素写入子文件：把阴影阶段与地形阶段的位置换成体素格号，越界丢弃，再交回最终编号。
调用位置：由 `voxel/voxel.slang` 内联引入，写入端与生成探针共用同一份格号换算。
可复制示例：`int3 cell = ogxGetVoxelIndex(playerPos, cameraOffset, side);`
设计原因与取舍：
    宿主的图像写入需要 Iris 自定义图像，库只计算格号与编号，不直接写显存；
    这样同一套边界判断能服务 GLSL 330、SPIR-V 探针和未来的其它后端。
    写入函数不依赖追踪类型，单独放在子文件后，主文件只保留材质与读取。
*/

// --- 算法说明与边界 ---
// 写入前先检查坐标，越界直接返回，不写坏相邻格。
// 一维下标按三维尺寸展开，读写使用同一套顺序；阴影阶段遍历可见方块，把编号与光照填进体素图。
// 体素写入：先检查坐标是否在体积内，再按三维尺寸算一维下标。
// 写入函数把方块编号与颜色存进纹理；阴影阶段遍历可见方块，把编号与光照填进体素图。
// 写入前先检查坐标，越界直接返回，不写坏相邻格。
// 一维下标按三维尺寸展开，读写使用同一套顺序；阴影阶段遍历可见方块，把编号与光照填进体素图。


// 体素写入是否在体积内：三个轴都必须在零到边长减一之间，越界写会被丢弃。
bool ogxVoxelWriteInBounds(int3 voxelPos, int size)
{
    return voxelPos.x >= 0 && voxelPos.y >= 0 && voxelPos.z >= 0
        && voxelPos.x < size && voxelPos.y < size && voxelPos.z < size; // 逐轴判断，避免夹紧后写错格。
}

// 写入格：把玩家相对位置加上相机小数偏移，再平移到体积中心；`side` 是每边格数。
int3 ogxGetVoxelIndex(float3 playerPos, float3 cameraOffset, int side)
{
    return int3(floor(playerPos + cameraOffset)) + int3(side / 2); // 参考实现按体积半边长平移。
}

// 为什么先判断越界：体素图只覆盖玩家周围一段，阴影阶段仍会碰到边界外的方块；
// 越界写会让相邻区域的数据串位，反射里出现不属于那里的颜色。
// 编号与光照用整数通道，颜色用八位；反射只需要近似颜色，八位足够且省显存。
void ogxSetVoxelBlock(int3 voxelPos, uint blockId, int voxelSize,
    inout int3 writePos, inout uint writeId)
{
    // 为什么要逐分量比较：Slang 的向量 `!=` 返回布尔向量，不能直接当条件；
    // 逐分量写清楚上下界，GLSL 与 Slang 的结果一致。
    int maxVoxel = voxelSize - 1;
    if (voxelPos.x < 0 || voxelPos.y < 0 || voxelPos.z < 0 ||
        voxelPos.x > maxVoxel || voxelPos.y > maxVoxel || voxelPos.z > maxVoxel) return; // 越界写入丢弃。
    writePos = voxelPos; // 记录真正写入的格号。
    writeId = blockId; // 记录写入的方块编号。
}

uint ogxPopulateShadowVoxelIndex(float3 playerPos, float3 cameraOffset, int3 midBlockOffset, int side,
    bool shouldWrite, uint voxelId, float renderedItemId, float entityId, uint itemOffset, out int3 voxelPos)
{
    voxelPos = ogxGetVoxelIndex(playerPos + float3(midBlockOffset) / 64.0, cameraOffset, side); // 中点偏移后算格号。
    if (!shouldWrite) return 0u; // 不写入的绘制阶段直接返回。
    if (voxelId == 0u) voxelId = 1u; // 参考实现把无编号地形当成实心方块。
    if (renderedItemId > 100.0 && renderedItemId < 276.0) voxelId = uint(renderedItemId) + itemOffset; // 手持物品按偏移写入，避免与草互动。
    else if (entityId > 0.0) voxelId = uint(entityId) + itemOffset; // 实体编号同样加偏移。
    return voxelId; // 交回最终编号。
}

// 阴影体素填充：只写相机附近一段，远处交给屏幕空间与天空回退。
// 每格只存一份颜色与光照，不存六个面；反射是低频效果，单份足够。
void ogxPopulateShadowVoxel(float3 playerPos, float3 eyeOffset, float3 cameraFraction, float3 midBlock,
    bool terrainStage, bool entityStage, bool blockEntityStage, float blockEntityId,
    float entityId, float currentRenderedItemId, float mcEntityX, int voxelSize,
    bool lpvEntityLights, bool waterInteraction, inout int3 writePos, inout uint writeId)
{
    uint voxelId = 0u; // 默认没有方块。
    float3 originPos = playerPos; // 从玩家相对位置开始。
    if (terrainStage) // 地形绘制阶段。
    {
        float blockID = mcEntityX; // 方块编号来自实体属性。
        voxelId = uint(blockID + 0.5); // 参考先四舍五入再转整数。
        if (voxelId == 0u) voxelId = 1u; // 无编号地形当作实心方块。
        originPos += midBlock / 64.0; // 方块中点偏移六十四分之一格。
    }
    int3 voxelPos = ogxGetVoxelIndex(originPos + eyeOffset, cameraFraction, voxelSize); // 加上相机小数偏移。
    if (lpvEntityLights && ((entityStage && (currentRenderedItemId > 0.0 || entityId > 0.0)) || blockEntityStage))
    {
        if (blockEntityStage) // 方块实体阶段。
        {
            if (blockEntityId > 0.0 && blockEntityId < 500.0 && blockEntityId != 267.0)
                voxelId = uint(blockEntityId); // 附魔台不写入，避免遮挡书架光。
        }
        else if (currentRenderedItemId > 100.0 && currentRenderedItemId < 276.0) // 手持物品。
        {
            if (entityId != 1607.0 && entityId != 1601.0) // 物品展示框与玩家不写入。
            {
                voxelId = uint(currentRenderedItemId);
                voxelId += 2000u; // 加偏移，避免与草的编号互相影响。
            }
        }
        else // 只有会发光的实体写入。
        {
            if (entityId == 1603.0 || entityId == 1605.0 || entityId == 1606.0 || entityId == 1608.0
                || entityId == 1611.0 || entityId == 1609.0)
                voxelId = uint(entityId) + 2000u;
        }
    }
    if (waterInteraction && ((entityStage && (currentRenderedItemId > 0.0 || entityId > 0.0)) || blockEntityStage))
    {
        if (entityId == 1612.0 || entityId == 1613.0) voxelId = uint(entityId) + 2000u; // 船与小船加入体素。
    }
    if (voxelId > 0u) ogxSetVoxelBlock(voxelPos, voxelId, voxelSize, writePos, writeId); // 最终写入。
}
