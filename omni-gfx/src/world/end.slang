/*
Omni 通用图形库末地模块：末地星空、行星 BRDF、黑洞吸积盘包装与云影查表。
调用位置：`shaders/effects/world/end_sky.glsl` 的 `CalculateStars` 调用 `ogxEndStars`；
    主文件提供 ogxPlanetShading 入口，其余函数由子文件与严格 profile 使用。
可复制示例：
    float3 stars = ogxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);
    float3 disc = ogxBlackHoleStars(color, rayDir, lightDir, 0.5, frameTime, true, true, sunVector, 1, noiseTex, 512.0);
    float shadow = ogxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);
设计原因与取舍：
    参考实现直接读 `frameTimeCounter`、`worldSunVector`、`STAR_TYPE` 与云噪声选项。库把时间、光方向、
    纹理和开关全部改成显式参数，公式、常数、循环次数和采样顺序保持不变。
    四个职责按内容拆在同名文件夹：星空、行星着色、吸积盘参数、云影查表；主文件只排引用顺序，
    所以一处算式只读一个文件，也不会因为拆分改变编译顺序。
*/

// --- 算法说明与边界 ---
// 行星着色只保留一个入口，内部调用通用 BRDF；第五参数不参与计算，只为参考签名兼容。
// 星空、吸积盘与云影各自在子文件里，主文件只按依赖顺序引入并提供行星入口。
// 末地模块组合星空、行星着色、吸积盘与云影：
// 行星着色保留参考签名，内部直接调用通用行星 BRDF，避免两份相同公式漂移。
// 星空按天球格子取哈希星点，吸积盘沿视线积分，云影按太阳方向取两次云密度。

#ifndef OGX_WORLD_END_INCLUDED
#define OGX_WORLD_END_INCLUDED

// 数学提供旋转、黑体色、曲线与夹紧，四个子文件共用。
#include "../common/math.slang"
// 雾提供分形云噪声，吸积盘纹理细节要用。
#include "../fog/fog.slang"
// 云提供球面求交、密度与顶部曲线，云影查表要用。
#include "../cloud/cloud.slang"
// 行星提供末地天空与行星环，行星着色要用钱德拉塞卡近似。
#include "../planet.slang"
// 吸积盘积分只保留一份，末地的天空版与反射版只差参数。
#include "../accretion.slang"

// 末地星空：天球格子哈希与黑体星色。
#include "end/stars.slang"
// 吸积盘包装：天空版与反射版只填参数。
#include "end/accretion.slang"
// 末地云影：按太阳方向取两次云密度。
#include "end/cloud_shadow.slang"

// 末地行星着色：保留参考签名，实际算式与 `planet` 模块的行星 BRDF 相同。
// 参考的第五参数不参与着色，保留它只为让严格对照能按原签名调用。
float3 ogxPlanetShading(float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float s)
{
    return ogxPlanetBrdf(albedo, normal, eyeDir, lightDir); // 同一公式只维护一份；第五参数只为签名兼容。
}

#endif
