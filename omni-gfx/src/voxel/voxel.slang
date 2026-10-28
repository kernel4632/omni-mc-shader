/*
Omni 通用图形库体素追踪模块：在规则三维网格里沿射线逐格前进，撞到实心方格时用存下的颜色与光照着色。
调用位置：任何有三维方块编号图与颜色图的程序；Minecraft 光影由 `/omni-gfx/voxel/voxel.glsl` 引入，
    `rendering/reflection/voxel.glsl` 只保留选项换算与坐标平移。
可复制示例：ogxVoxelReflection 返回反射颜色与归一化命中距离，并带回命中点。
设计原因与取舍：
    网格偏移、边长、两张三维纹理、光色、太阳方向、追踪距离与强度全部由调用方传入，库不读取任何引擎状态。
    水、冰、玻璃按半透明处理，只给后面的画面染色后继续走；铁块按镜面弹射，最多弹四次，
    防止两面镜子互相拖满循环。追踪用标准的三维逐格步进：每步选最近的一根格子边界，撞到实心方块就停。
    方块编号是方块的业务数据，用 `uint` 直接传入，库不假设它来自哪张方块表。
    三维纹理取格写成 `Load(int4(cell, level))`：Slang 把细节层级放在坐标的第四个分量，
    生成器再把它还原成 GLSL 的 `texelFetch(tex, cell, level)`，两边算式不变。
*/
#ifndef OGX_VOXEL_INCLUDED
#define OGX_VOXEL_INCLUDED

// 数学提供夹紧与向量单位化，颜色提供 sRGB 到线性的转换。
#include "../common/math.slang"
// 颜色提供伽马、线性转换与色调映射。
#include "../common/color.slang"

// 半透明方块：水、冰、玻璃，光线穿过后只给后面的画面染色，不停下。
bool ogxVoxelIsTranslucent(uint id) { return id == 8u || id == 79u || id == 95u; }

// 植物：草、花、树叶等，不挡光也不算实体，直接穿过。
bool ogxVoxelIsPlant(uint id)
{
    return id == 12u || id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7030u || id == 7040u; // 编号与方块映射表一致。
}

// 铁块：反射撞到它时当镜子处理；编号 504 与方块映射表一致。
bool ogxVoxelIsIron(uint id) { return id == 504u; }

// 半透明方块的染色强度：水最清、冰居中、玻璃最浓。
// 为什么按编号分档：颜色图没有存透明度，只能按方块种类近似；玻璃本身有色，染色就重一些。
float ogxVoxelTintStrength(uint id)
{
    if (id == 8u) return 0.4; // 水：多数是清水，只带一点生物群系颜色。
    if (id == 79u) return 0.6; // 冰：本身偏蓝。
    return 0.8; // 玻璃与染色玻璃：颜色最重。
}

// 算一层半透明染色：把方块底色归一化成方向色（保留色相、去掉亮度），再按强度与无色混合。
// 为什么归一化：只用色相给后面的画面染色，避免水太亮把反射整个提白。
float3 ogxVoxelTranslucentTint(uint id, float3 albedo)
{
    return lerp(float3(1.0), ogxNormalize(albedo), ogxVoxelTintStrength(id)); // 按方块种类决定染色深度。
}

// 给命中的体素面上色：底色乘（方块光加天光的间接光，再加直射太阳光）。
// `packedLight` 是写入端打包的方块光与天光，`voxelNormal` 是进入面朝外的法线。
float3 ogxVoxelShade(float3 albedo, float3 voxelNormal, float packedLight, float3 torchColor, float3 skyColor,
    float3 sunColor, float3 sunDirection, float strength)
{
    float packed = floor(packedLight * 255.0 + 0.5); // 还原成整数位的打包光照。
    float blockLevel = floor(packed / 16.0) / 15.0; // 高四位是方块光等级。
    float skyLevel = ogxMod(packed, 16.0) / 15.0; // 低四位是天光等级。
    float3 indirect = torchColor * blockLevel + skyColor * skyLevel; // 方块光与天光一起给环境亮度。
    float3 direct = sunColor * ogxSaturate(dot(voxelNormal, sunDirection)); // 直射按体素面朝太阳的余弦。
    return albedo * (indirect + direct) * strength; // 底色乘光照与玩家强度。
}

// 判断体素下标是否落在边长 `side` 的立方体里，越界就没有编号。
// 逐分量比较而不是向量比较：GLSL 330 的整数向量不支持大于等于运算符。
bool ogxVoxelInside(int3 cell, int side)
{
    return cell.x >= 0 && cell.y >= 0 && cell.z >= 0 && cell.x < side && cell.y < side && cell.z < side; // 三个轴都要在零到边长之间。
}

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// `originWorld` 是表面相机相对世界位置，`rayDirWorld` 是世界空间反射方向，`surfaceNormal` 是表面法线；
// `voxelOffset` 是相机相对位置到体积坐标的平移，`side` 是每边单元数。
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。
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

// 体素编号：从三维掩码直接取格，并按参考实现取两千以内的编号。
// 体素块读取的提前声明：入口放在定义之前。
uint ogxGetVoxelBlock(Usampler3D voxelMask, int3 voxelPos);

// Eclipse 体素块读取入口：参考签名只给坐标，三维体素图作为显式资源传入。
uint ogxGetVoxelBlockReference(int3 voxelPos, Usampler3D voxelMask)
{
    return ogxGetVoxelBlock(voxelMask, voxelPos); // 转调同一个三维取像素。
}

uint ogxGetVoxelBlock(Usampler3D voxelMask, int3 voxelPos)
{
    return voxelMask.Load(int4(voxelPos, 0)).r % 2000u; // 参考实现的编号掩码。
}

// 体素写入格：把方块位置加上相机小数偏移，再落到以体积中心为原点的整数格。
// `center` 是体积半边长，调用方按自己的网格尺寸给出，库不假设固定边长。
int3 ogxVoxelWriteIndex(float3 playerPos, float3 cameraOffset, int3 center)
{
    return int3(floor(playerPos + cameraOffset)) + center; // 与 Eclipse `GetVoxelIndex` 的取整顺序一致。
}

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

// 体素下标：三轴按行优先展开成一维下标，供六面数据数组使用。
int ogxVoxelIndex(int3 voxelPos, int size)
{
    return voxelPos.x + voxelPos.y * size + voxelPos.z * size * size; // 与参考实现的展开顺序一致。
}

// 体素面编号：按法线主轴与正负方向映射到零到五，零到五分别对应六个面。
int ogxVoxelNormalIndex(float3 voxelNormal)
{
    return clamp(int(abs(voxelNormal.x) * (voxelNormal.x * 0.5 + 0.5)
        + abs(voxelNormal.y) * (voxelNormal.y * 0.5 + 2.5)
        + abs(voxelNormal.z) * (voxelNormal.z * 0.5 + 4.5) + 0.5), 0, 5); // 参考实现的连续映射。
}

// 解包两个十六位小数：把一个浮点数的低位与高位拆回两个零到一的值。
float2 ogxDecodeVec2_16(float a)
{
    const float2 constant1 = 4294967294.0 / float2(65536.0, 4294967295.0); // 两个通道的缩放。
    const float constant2 = 65536.0 / 65535.0; // 端点修正。
    return fract(a * constant1) * constant2; // 拆包并修正。
}

// 解包两个八位颜色：参考实现把颜色压进一个浮点数，读回时按两位十六进制拆开。
float2 ogxDecodeVec2(float a)
{
    return float2(fract(a * 256.0), fract(a * 65536.0)); // 低字节与高字节。
}

// 解码一个体素面的贴图坐标、光照与染色：六面数据里每个面存同样布局。
void ogxDecodeVoxelFace(float4 blockTexture, out float2 texcoord, out float2 lightmap, out float3 tintColor)
{
    texcoord = ogxDecodeVec2_16(blockTexture.x); // 第一个分量是贴图坐标。
    lightmap = ogxDecodeVec2(blockTexture.y); // 第二个分量是光照图。
    lightmap = min(max(lightmap - 0.05, 0.0) * 1.06, 1.0); // 参考实现先压暗再放大，去掉底部一段。
    float2 rgTint = ogxDecodeVec2(blockTexture.b); // 第三个分量是红绿染色。
    tintColor = float3(rgTint.r, blockTexture.a, rgTint.g); // 蓝染色在第四分量。
}

// 只取体素面的贴图坐标，供不需要光照的反射采样。
void ogxGetVoxelTexCoord(float4 blockTexture, out float2 texcoord)
{
    texcoord = ogxDecodeVec2_16(blockTexture.x); // 与完整解码使用同一拆包。
}

// 体素自发光：鲜艳又明亮的像素才发光，返回零到零点五。
float ogxGetVoxelEmission(float3 albedo)
{
    float3 hsv = ogxRgbToHsv(albedo); // 拆出饱和度与明度。
    float emissive = smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5); // 饱和度当门槛，明度拉对比。
    return emissive * 0.5; // 参考实现的半值。
}

// 把体素自发光混进光照：发光强度接近满值时表示没有自发光，否则按曲线混向底色。
void ogxVoxelEmission(inout float3 lighting, float3 albedo, float emission, float emissiveBrightness, float emissiveCurve)
{
    if (emission < 254.5 / 255.0) // 接近满值表示不发光。
    {
        lighting = lerp(lighting, albedo * 5.0 * emissiveBrightness, pow(emission, emissiveCurve)); // 按强度与曲线混入。
    }
}

// 阴影体素写入：判断这一笔是否该写入并算出格号；方块编号与实体枚举由调用方在边界决定。
// `shouldWrite` 为假时不写；`voxelId` 为零时按空气处理；返回值是最终写入的编号。
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

// Eclipse 自发光强度：把颜色转成 HSV，按饱和度与亮度估计发光，再压到一半。
// 参考用全局 Albedo，库版本显式接收颜色；常数与参考一致。
float ogxPhotonicsEmission(float3 albedo)
{
    return ogxGetVoxelEmission(albedo); // 自发光曲线只在体素模块维护一份。
}

// 解码一个体素面的完整数据：脸表纹理的第 y 行是六个面，x 轴是一维体素下标。
// 为什么把参考的 SSBO 换成二维纹理：参考的 `voxelData` 声明被注释掉，原文不能编译；
// 这里把同一份 `[voxelIndex][normalIndex]` 数据装进只读纹理，取格语义保持不变。
void ogxGetVoxelData(int3 voxelPos, inout float2 texcoord, inout float3 tintColor,
    float3 voxelNormal, inout float2 lightmap, Sampler2D voxelDataTexture, int voxelSize)
{
    int index = ogxVoxelIndex(voxelPos, voxelSize); // 三轴展开成一维格号。
    int faceIndex = ogxVoxelNormalIndex(voxelNormal); // 法线映射到六个面之一。
    float4 blockTexture = voxelDataTexture.Load(int3(int2(index, faceIndex), 0)); // 读该面的打包数据。
    texcoord = ogxDecodeVec2_16(blockTexture.x); // 贴图坐标占第一个分量。
    lightmap = ogxDecodeVec2(blockTexture.y); // 光照图占第二个分量。
    lightmap = min(max(lightmap - 0.05, 0.0) * 1.06, 1.0); // 去掉底部一段并放大。
    float2 rgTint = ogxDecodeVec2(blockTexture.b); // 红绿染色占第三个分量。
    tintColor = float3(rgTint.x, blockTexture.a, rgTint.y); // 蓝色染色在第四分量。
}

// 只读体素贴图坐标：反射裁剪只需要第一个分量的十六位解包。
void ogxGetVoxelFaceTexCoord(int3 voxelPos, inout float2 texcoord, float3 voxelNormal,
    Sampler2D voxelDataTexture, int voxelSize)
{
    int index = ogxVoxelIndex(voxelPos, voxelSize); // 与完整解码共用同一套格号。
    int faceIndex = ogxVoxelNormalIndex(voxelNormal); // 与完整解码共用同一套面号。
    texcoord = ogxDecodeVec2_16(voxelDataTexture.Load(int3(int2(index, faceIndex), 0)).x); // 只解第一个分量。
}

// 写入体素掩码：参考直接 imageStore，库把目标格与编号交给调用方显式接收。
// 为什么用 out 参数：GLSL 330 没有三维可写图像，宿主的图像存储属于渲染器资源；
// 这里保留参考的边界判断与写入值，调用方把结果刷进自己的图像或缓冲。
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

// 阴影体素写入：把参考的渲染阶段、实体编号与方块编号换成显式输入。
// `terrainStage`、`entityStage`、`blockEntityStage` 由宿主按当前绘制阶段给出；
// `writePos` 与 `writeId` 接收最终写入位置和编号，方便宿主刷新体素图。
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

#endif
