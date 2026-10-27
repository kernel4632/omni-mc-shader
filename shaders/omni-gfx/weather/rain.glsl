/*
生成文件：雨纹模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库天气雨纹模块：三层动画雨纹、降水分布与湿润度更新。
调用位置：雨天水面与地形的法线扰动；由 `/omni-gfx/weather/rain.glsl` 引入。
可复制示例：
    vec2 n = ogxGetRainNormal(pos, strength, wet, rainTex1, rainTex2, rainTex3, noiseTex, time, 2.0); // 取雨滴法线。
设计原因与取舍：
    雨纹按每秒六十帧离散滚动，三层强度由大尺度降水分布决定；湿润度在函数内更新，采样顺序与参考实现一致。
*/
#ifndef OGX_WEATHER_RAIN_INCLUDED
#define OGX_WEATHER_RAIN_INCLUDED
#include "/omni-gfx/math.glsl"
// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
vec2 ogxRainAnimationTex(sampler2D texSampler, vec2 coord, float rp);

// 雨滴法线：三张动画噪声图按降水强度叠加，再按屏幕导数做层级衰减。
// `wet` 会被更新成新的湿润度，`strength` 已由调用方乘过雨强与群系系数。
vec2 ogxGetRainNormal(vec3 pos, float strength, inout float wet, sampler2D rainTex1, sampler2D rainTex2,
    sampler2D rainTex3, sampler2D noiseTexture, float timeSeconds, float rpBase)
{
    pos.xyz *= 0.5; // 世界坐标缩小，雨纹更大。
    float frame = fract(floor(timeSeconds * 60.0) / 60.0); // 每秒六十帧的离散时间，避免连续滚动。
    vec2 coord = vec2(pos.x, fract(pos.z / 60.0) - frame); // 沿深度方向滚动的坐标。
    float wet2 = wet * wet; // 湿润度平方。
    float rp = 2.0 - (wet2 * wet2) * 1.2; // 对比度随湿润度降低。
    vec2 n1 = ogxRainAnimationTex(rainTex1, coord, rp); // 第一层雨纹。
    vec2 n2 = ogxRainAnimationTex(rainTex2, coord, rp); // 第二层。
    vec2 n3 = ogxRainAnimationTex(rainTex3, coord, rp); // 第三层。
    pos.x -= timeSeconds * 0.5; // 噪声图随时间横向漂移。
    float downfall = textureLod(noiseTexture, pos.xz * 0.0025, 0.0).w; // 大尺度降水分布。
    downfall = clamp(downfall - 0.25, 0.0, 1.0); // 去掉低值。
    vec2 n = n1; // 第一层总是参与。
    n += n2 * clamp(downfall * 2.0, 0.0, 1.0); // 降水中等时叠第二层。
    n += n3 * clamp(downfall * 2.0 - 1.0, 0.0, 1.0); // 降水很强时叠第三层。
    float lod = dot(fwidth(pos.xz), vec2(1.0)); // 屏幕导数决定过滤强度。
    n /= lod * 5.0 + 1.0; // 远处减弱，避免闪烁。
    n *= strength; // 乘降水强度。
    wet = clamp(mix(downfall, wet, 1.0 - 0.4 * clamp(strength, 0.0, 1.0)), 0.0, 1.0); // 更新湿润度。
    return n; // 交回法线扰动。
}

// 单张雨纹的对比度重整：先转到负一到一，再按幂次拉对比，最后恢复符号。
vec2 ogxRainAnimationTex(sampler2D texSampler, vec2 coord, float rp)
{
    vec2 n = textureLod(texSampler, coord, 0.0).rg; // 取红绿通道。
    n = n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 转成负一到一。
    n = pow(abs(n), vec2(rp)) * sign(n); // 按湿润度拉对比。
    return n; // 交回重整后的雨纹。
}

#endif
