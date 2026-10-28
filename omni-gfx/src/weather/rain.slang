/*
Omni 通用图形库天气雨纹模块：三层动画雨纹、降水分布与湿润度更新。
调用位置：雨天水面与地形的法线扰动；由 `/omni-gfx/weather/rain.glsl` 引入。
可复制示例：
    vec2 n = ogxGetRainNormal(pos, strength, wet, rainTex1, rainTex2, rainTex3, noiseTex, time, 2.0); // 取雨滴法线。
设计原因与取舍：
    雨纹按每秒六十帧离散滚动，三层强度由大尺度降水分布决定；湿润度在函数内更新，采样顺序与参考实现一致。
当前状态：由 `shaders/effects/shared/water/rain.glsl` 引入并编译；宿主 `GetRainAnimationTex` 调用 `ogxRainAnimationTex`。
*/
#ifndef OGX_WEATHER_RAIN_INCLUDED
#define OGX_WEATHER_RAIN_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"

// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
float2 ogxRainAnimationTex(Sampler2D texSampler, float2 coord, float rp);

// 雨滴法线：三张动画噪声图按降水强度叠加，再按屏幕导数做层级衰减。
// `wet` 会被更新成新的湿润度，`strength` 已由调用方乘过雨强与群系系数。
float2 ogxGetRainNormal(float3 pos, float strength, inout float wet, Sampler2D rainTex1, Sampler2D rainTex2,
    Sampler2D rainTex3, Sampler2D noiseTexture, float timeSeconds, float rpBase)
{
    pos.xyz *= 0.5; // 世界坐标缩小，雨纹更大。
    float frame = fract(floor(timeSeconds * 60.0) / 60.0); // 每秒六十帧的离散时间，避免连续滚动。
    float2 coord = float2(pos.x, fract(pos.z / 60.0) - frame); // 沿深度方向滚动的坐标。
    float wet2 = wet * wet; // 湿润度平方。
    float rp = 2.0 - (wet2 * wet2) * 1.2; // 对比度随湿润度降低。
    float2 n1 = ogxRainAnimationTex(rainTex1, coord, rp); // 第一层雨纹。
    float2 n2 = ogxRainAnimationTex(rainTex2, coord, rp); // 第二层。
    float2 n3 = ogxRainAnimationTex(rainTex3, coord, rp); // 第三层。
    pos.x -= timeSeconds * 0.5; // 噪声图随时间横向漂移。
    float downfall = noiseTexture.SampleLevel(pos.xz * 0.0025, 0.0).w; // 大尺度降水分布。
    downfall = clamp(downfall - 0.25, 0.0, 1.0); // 去掉低值。
    float2 n = n1; // 第一层总是参与。
    n += n2 * clamp(downfall * 2.0, 0.0, 1.0); // 降水中等时叠第二层。
    n += n3 * clamp(downfall * 2.0 - 1.0, 0.0, 1.0); // 降水很强时叠第三层。
    float lod = dot(fwidth(pos.xz), float2(1.0)); // 屏幕导数决定过滤强度。
    n /= lod * 5.0 + 1.0; // 远处减弱，避免闪烁。
    n *= strength; // 乘降水强度。
    wet = clamp(lerp(downfall, wet, 1.0 - 0.4 * clamp(strength, 0.0, 1.0)), 0.0, 1.0); // 更新湿润度。
    return n; // 交回法线扰动。
}

// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
float2 ogxRainAnimationTex(Sampler2D texSampler, float2 coord, float rp)
{
    float2 n = texSampler.SampleLevel(coord, 0.0).rg; // 取红绿通道。
    n = n * float2(2.0, -2.0) + float2(-1.0, 1.0); // 转成负一到一。
    n = pow(abs(n), float2(rp)) * sign(n); // 按湿润度拉对比。
    return n; // 交回重整后的雨纹。
}

#endif
