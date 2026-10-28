/*
Omni 通用图形库体素追踪模块：在规则三维网格里沿射线逐格前进，撞到实心方格时用存下的颜色与光照着色。
调用位置：任何有三维方块编号图与颜色图的程序；Minecraft 光影由 `/omni-gfx/voxel/voxel.glsl` 引入，
    `shaders/effects/reflection/voxel.glsl` 只保留选项换算与坐标平移。
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

// 世界空间追踪，具体实现在子文件。
#include "voxel/reflection.slang"
// 写入格、越界判断与阴影阶段编号，具体实现在子文件。
#include "voxel/write.slang"

#endif
