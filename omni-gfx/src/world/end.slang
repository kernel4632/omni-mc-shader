/*
Omni 通用图形库末地模块：末地星空、行星 BRDF、黑洞吸积盘包装与云影查表。
调用位置：`shaders/effects/world/end_sky.glsl` 的 `CalculateStars` 调用 `ogxEndStars`；
    其余入口供严格 profile 与需要复现 iterationT 末地的程序使用。
可复制示例：
    float3 stars = ogxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0); // 当前步骤的中间量。
    float3 disc = ogxBlackHoleStars(color, rayDir, lightDir, 0.5, frameTime, true, true, sunVector, 1, noiseTex, 512.0);
    float shadow = ogxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);
设计原因与取舍：
    参考实现直接读 `frameTimeCounter`、`worldSunVector`、`STAR_TYPE` 与云噪声选项。库把时间、光方向、
    纹理和开关全部改成显式参数，公式、常数、循环次数和采样顺序保持不变。
    四个职责按内容拆在同名文件夹：星空、行星着色、吸积盘参数、云影查表；主文件只排引用顺序，
    所以一处算式只读一个文件，也不会因为拆分改变编译顺序。
*/
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
// 末地行星：钱德拉塞卡近似与 Lambert 曲线。
#include "end/planet.slang"
// 吸积盘包装：天空版与反射版只填参数。
#include "end/accretion.slang"
// 末地云影：按太阳方向取两次云密度。
#include "end/cloud_shadow.slang"

#endif
