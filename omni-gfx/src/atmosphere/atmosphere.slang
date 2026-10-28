/*
Omni 通用图形库大气模块：球面几何、密度剖面、单次散射与空气透视。
调用位置：天空、地形远景、水面与云的环境光；Minecraft 光影由 `/omni-gfx/atmosphere/atmosphere.glsl` 引入。
可复制示例：
    OgxAtmosphere a = ogxAtmosphereEarth(); // 取一组地球常数。
    float3 s = ogxAtmosphereSky(a, 0.03, viewDir, sunDir, 10); // 算天空颜色。
    float3 h = ogxAerialPerspective(a, 0.03, viewDir, 1.5, sunDir, 5, t2); // 算远景空气散射。
设计原因与取舍：
    公式来自迁移前 GLSL 原型的球面几何与密度剖面，并补上可独立运行的单次散射积分。
    不读取预计算贴图，换机器与不启动 Minecraft 都能得到同一片天空；代价是每像素多几次指数运算。
    长度单位统一为公里，避免行星半径用米时 float 精度不足；调用方把米乘零点零零一。
    太阳与月亮方向、散射系数、行星半径全部由调用方传入，库不读取任何引擎状态。
*/
#ifndef OGX_ATMOSPHERE_INCLUDED
#define OGX_ATMOSPHERE_INCLUDED

// 数学模块提供相函数、射线求交与夹紧。
#include "../common/math.slang"
// 星点温度到颜色的黑体函数在颜色模块，星场需要它。
#include "../common/color.slang"

// 一次大气计算需要的全部常数；不同星球换一组字段即可，不必改算法。
struct OgxAtmosphere
{
    float planetRadius; // 行星底半径，公里。
    float atmosphereRadius; // 大气层顶半径，公里。
    float rayleighHeight; // 瑞利密度衰减高度，公里。
    float mieHeight; // 米氏密度衰减高度，公里。
    float3 rayleighScattering; // 瑞利散射系数，每公里。
    float3 mieScattering; // 米氏散射系数，每公里。
    float3 ozoneAbsorption; // 臭氧吸收系数，每公里。
    float mieG; // 米氏相位的前向集中程度。
    float sunIntensity; // 太阳辐照度的整体倍率。
};

// 行星大气、密度与单次散射，具体实现在子文件。
#include "atmosphere/scattering.slang"
// 太阳圆盘、球面求交与星场，具体实现在子文件。
#include "atmosphere/sun.slang"
// 天空映射、云图与月盘，具体实现在子文件。
#include "atmosphere/mapping.slang"
// 行星 BRDF 与 Eclipse 天空近似，具体实现在子文件。
#include "atmosphere/planet.slang"

#endif
