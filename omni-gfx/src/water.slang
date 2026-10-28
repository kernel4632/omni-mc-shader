/*
Omni 通用图形库水面模块：方向波法线、菲涅尔、吸收、折射偏移、太阳高光与岸线泡沫。
调用位置：水面着色与任何需要程序化水面的程序；Minecraft 光影由 `/omni-gfx/water.glsl` 引入。
可复制示例：
    OgxWater w = ogxWaterDefault(); // 取默认水体。
    float3 n = ogxWaterNormal(p.xz, t, d, 1.0, 1.0); // 算波法线。
    float3 c = ogxWaterShade(w, n, viewDir, sunDir, sunColor, r1, r2, depthM, foamAmt, alphaOut); // 算水面颜色。
    `OgxOceanWaveSum sum = ogxOceanWaveSum(float2(0.0), t, ogxOceanWavesDefault());` 迭代正弦海洋。
    `float h = ogxOceanWaveHeight(sum, 13.0, 1.0);` 归一化后的波高。
设计原因与取舍：
    波形来自迁移前 GLSL 原型的六层噪声叠加思路，换成解析方向波，省掉噪声贴图。
    只做单层水面，但保留长波、斜波、短波与细波纹四级，远处自动淡出高频，避免闪烁。
    反射与折射颜色由调用方传入，库不读取立方体贴图或屏幕纹理，因此能同时服务 Iris 与独立测试世界。
*/
#ifndef OGX_WATER_INCLUDED
#define OGX_WATER_INCLUDED

// 数学模块提供菲涅尔、GGX 高光与夹紧，噪声模块打散规则波列。
#include "common/math.slang"
// 噪声提供哈希、分形与云团细节。
#include "common/noise.slang"

// 一组水面光学参数；不同水体换字段即可，不必改波形与着色顺序。
struct OgxWater
{
    float3 shallowColor; // 浅水颜色，线性空间。
    float3 deepColor; // 深水颜色，线性空间。
    float3 absorption; // 逐通道吸收系数，每米。
    float waveScale; // 波形空间缩放。
    float waveHeight; // 波形坡度倍率。
    float roughness; // 太阳高光粗糙度。
    float refraction; // 屏幕折射偏移强度。
};

// 波法线、菲涅尔、吸收与岸边，具体实现在子文件。
#include "water/waves.slang"
// 水洼、雨纹与焦散，具体实现在子文件。
#include "water/rain.slang"
// 海浪、泡沫与凹凸法线，具体实现在子文件。
#include "water/ocean.slang"

#endif
