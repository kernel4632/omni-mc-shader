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

// 地球默认大气：海平面半径六千三百六十公里，层顶八十公里，数值与参考一致。
OgxAtmosphere ogxAtmosphereEarth()
{
    OgxAtmosphere air; // 先声明再逐项填写，Slang 与 GLSL 都支持这种写法。
    air.planetRadius = 6360.0; // 地球半径，公里。
    air.atmosphereRadius = 6440.0; // 大气层顶，海平面以上八十公里。
    air.rayleighHeight = 8.0; // 瑞利散射主要由低空空气造成。
    air.mieHeight = 1.2; // 米氏散射集中在更低的雾霾层。
    air.rayleighScattering = float3(5.8e-3, 13.5e-3, 33.1e-3); // 蓝光散射最强，天空因此偏蓝。
    air.mieScattering = float3(1.0e-3, 1.0e-3, 1.0e-3); // 气溶胶散射近似中性灰，压低地平线白雾。
    air.ozoneAbsorption = float3(0.65e-3, 1.881e-3, 0.085e-3); // 臭氧吸收少量红光与蓝光。
    air.mieG = 0.62; // 前向散射明显，太阳附近出现白晕。
    air.sunIntensity = 13.0; // 与测试世界的曝光配合，保持高动态范围。
    return air; // 返回一组可直接使用的常数。
}

// 单次散射积分：沿视线在球壳里取样，逐段累加太阳透过率与瑞利、米氏和臭氧。
// 步数由调用方给出；默认八步已经能画出地平线泛红，增加步数只改善太阳附近的细带。
float3 ogxAtmosphereSky(OgxAtmosphere air, float cameraAltitude, float3 viewDirection, float3 sunDirection, int steps)
{
    float3 origin = float3(0.0, air.planetRadius + max(cameraAltitude, 0.0), 0.0); // 相机放在行星正上方。
    float distanceToTop = ogxAtmosphereDistanceToTop(origin, viewDirection, air.atmosphereRadius); // 到层顶的距离。
    bool groundHit; // 视线是否打到地面。
    float distanceToGround = ogxAtmosphereDistanceToGround(origin, viewDirection, air.planetRadius, groundHit); // 到地面的距离。
    float maxDistance = distanceToTop; // 默认积到层顶。
    if (groundHit && distanceToGround < maxDistance) // 地面比层顶更近时积到地面。
    {
        maxDistance = distanceToGround; // 地面挡住后面的空气。
    }
    if (maxDistance <= 0.0) // 视线没有穿过大气。
    {
        return float3(0.0); // 返回黑色。
    }
    const int maxSteps = 12; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = maxDistance / float(count); // 每段长度。
    float3 scattered = float3(0.0); // 累积的散射光。
    float3 transmittance = float3(1.0); // 到当前段为止的透过率。
    float3 position = origin + viewDirection * (stepLength * 0.5); // 第一段中点。
    float nu = dot(viewDirection, sunDirection); // 视线与太阳夹角余弦。
    float rayleighPhase = ogxRayleighPhase(nu); // 瑞利相函数。
    float miePhase = ogxMiePhase(air.mieG, nu); // 米氏相函数。
    for (int i = 0; i < maxSteps; i++) // 逐段积分。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float altitude = length(position) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float3 sunTransmittance = ogxAtmosphereSunTransmittance(air, position, sunDirection, 3); // 阳光到这里还剩多少。
        float3 extinction = air.rayleighScattering * rayleigh + air.mieScattering * mie; // 这一段的消光系数。
        float3 inScatter = (air.rayleighScattering * (rayleigh * rayleighPhase) // 瑞利散射。
                          + air.mieScattering * (mie * miePhase)) // 米氏散射。
                          * sunTransmittance * air.sunIntensity; // 乘阳光透过率与强度。
        scattered += inScatter * transmittance * stepLength; // 按剩余透过率累加。
        transmittance *= exp(-extinction * stepLength); // 更新剩余透过率。
        position += viewDirection * stepLength; // 前进到下一段。
    }
    if (groundHit) // 视线落到地面时补一层地面反射。
    {
        float3 groundPosition = origin + viewDirection * maxDistance; // 地面交点。
        float3 groundNormal = normalize(groundPosition); // 球面法线。
        float3 sunTransmittance = ogxAtmosphereSunTransmittance(air, groundPosition, sunDirection, 3); // 地面处的阳光。
        float groundLight = max(dot(groundNormal, sunDirection), 0.0); // 地面受光余弦。
        scattered += air.sunIntensity * sunTransmittance * groundLight * 0.02; // 低反照率地面，避免抢走地形。
    }
    return max(scattered, float3(0.0)); // 数值误差不产生负颜色。
}

#endif
