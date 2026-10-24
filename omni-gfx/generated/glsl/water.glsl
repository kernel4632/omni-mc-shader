/*
生成文件：水面模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库水面模块：方向波法线、菲涅尔、吸收、折射偏移、太阳高光与岸线泡沫。
调用位置：水面着色与任何需要程序化水面的程序；Minecraft 光影由 `/omni-gfx/water.glsl` 引入。
可复制示例：
    OgxWater w = ogxWaterDefault(); // 取默认水体。
    vec3 n = ogxWaterNormal(p.xz, t, d, 1.0, 1.0); // 算波法线。
    vec3 c = ogxWaterShade(w, n, viewDir, sunDir, sunColor, r1, r2, depthM, foamAmt, alphaOut); // 算水面颜色。
设计原因与取舍：
    波形来自旧 `shaders/gfx/water.glsl` 的六层噪声叠加思路，换成解析方向波，省掉噪声贴图。
    只做单层水面，但保留长波、斜波、短波与细波纹四级，远处自动淡出高频，避免闪烁。
    反射与折射颜色由调用方传入，库不读取立方体贴图或屏幕纹理，因此能同时服务 Iris 与独立测试世界。
*/
#ifndef OGX_WATER_INCLUDED
#define OGX_WATER_INCLUDED

// 数学模块提供菲涅尔、GGX 高光与夹紧，噪声模块打散规则波列。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/noise.glsl"
// 一组水面光学参数；不同水体换字段即可，不必改波形与着色顺序。
struct OgxWater
{
    vec3 shallowColor; // 浅水颜色，线性空间。
    vec3 deepColor; // 深水颜色，线性空间。
    vec3 absorption; // 逐通道吸收系数，每米。
    float waveScale; // 波形空间缩放。
    float waveHeight; // 波形坡度倍率。
    float roughness; // 太阳高光粗糙度。
    float refraction; // 屏幕折射偏移强度。
};

// 默认水体：偏青的浅水、深蓝的深水，红光吸收最快。
OgxWater ogxWaterDefault()
{
    OgxWater water; // 先声明再填写字段。
    water.shallowColor = vec3(0.10, 0.34, 0.36); // 浅水偏青绿。
    water.deepColor = vec3(0.008, 0.045, 0.120); // 深水偏蓝。
    water.absorption = vec3(0.18, 0.075, 0.035); // 红光最先被吸收，深水因此偏蓝。
    water.waveScale = 1.0; // 默认波形密度。
    water.waveHeight = 1.0; // 默认坡度。
    water.roughness = 0.08; // 水面比较光滑，高光集中。
    water.refraction = 0.035; // 折射偏移不要太大，避免岸边拉扯。
    return water; // 返回可直接修改的默认值。
}

// 水面法线：四组方向波的解析梯度相加，再转成朝上的法线。
vec3 ogxWaterNormal(vec2 position, float time, float distance, float waveScale, float waveHeight)
{
    vec2 p = position * waveScale; // 按波形密度缩放空间坐标。
    vec2 gradient = vec2(0.0); // 高度场的水平梯度。
    vec2 direction0 = vec2(0.62, 0.28); // 长波方向。
    vec2 direction1 = vec2(-0.31, 0.74); // 斜向波方向。
    float nearFade = 1.0 - smoothstep(20.0, 120.0, distance); // 近处保留高频细节。
    gradient = direction0 * (0.320 * 0.035 * cos(dot(p, direction0) * 0.035 + time * 0.55)); // 一百八十米级长波，远处也不会闪。
    gradient += direction1 * (0.220 * 0.060 * cos(dot(p, direction1) * 0.060 + time * 0.85)); // 一百米级斜向波。
    vec2 direction2 = vec2(0.88, -0.41); // 短波方向。
    gradient += direction2 * (0.080 * 0.180 * cos(dot(p, direction2) * 0.180 + time * 1.2)) * nearFade; // 三十米级短波只在近处。
    vec2 direction3 = vec2(-0.67, -0.55); // 细波纹方向。
    gradient += direction3 * (0.040 * 0.450 * cos(dot(p, direction3) * 0.450 + time * 1.7)) * nearFade * nearFade; // 十米级细波纹只在近处。
    gradient *= waveHeight; // 按坡度倍率缩放。
    float breakup = 0.75 + 0.5 * ogxValueNoise2(position * 0.015 + vec2(time * 0.02, time * 0.013)); // 低频噪声打散规则波列。
    gradient *= breakup; // 避免整片水面出现同一条亮带。
    float distanceFade = 1.0 - smoothstep(200.0, 900.0, distance) * 0.85; // 远处压平法线，减少像素级闪烁。
    return normalize(vec3(-gradient.x * distanceFade, 1.0, -gradient.y * distanceFade)); // 高度场梯度转成朝上的法线。
}

// 菲涅尔：正对时只剩基础反射率，掠射时接近全反射。
float ogxWaterFresnel(float NdotV, float f0)
{
    float x = 1.0 - ogxSaturate(NdotV); // 掠射程度。
    float x2 = x * x; // 平方。
    return f0 + (1.0 - f0) * x2 * x2 * x; // 五次方近似。
}

// 水的吸收：按水深逐通道衰减，红光最快，所以深水偏蓝。
vec3 ogxWaterAbsorption(OgxWater water, float depth)
{
    return exp(-water.absorption * max(depth, 0.0)); // 比尔-朗伯定律。
}

// 屏幕折射偏移：水越深、越靠近相机，偏移越明显；远处收小避免整片扭曲。
vec2 ogxWaterRefractionOffset(vec3 normal, float depth, float distance, float strength)
{
    vec2 offset = normal.xz * strength * ogxSaturate(depth * 0.12) / (1.0 + distance * 0.015); // 按深度与距离缩放。
    return offset; // 返回屏幕坐标偏移。
}

// 岸线泡沫：水很浅时出现，噪声让泡沫边缘不整齐。
float ogxWaterFoam(float depth, float noise)
{
    float edge = 1.0 - smoothstep(0.0, 0.9, max(depth, 0.0)); // 只在浅水出现。
    return edge * ogxSaturate(noise * 1.6 - 0.3); // 噪声把泡沫打散。
}

// 水面着色：折射色乘吸收，再按菲涅尔混入反射，最后叠太阳高光与泡沫。
vec3 ogxWaterShade(OgxWater water, vec3 normal, vec3 viewDirection, vec3 sunDirection, vec3 sunColor,
                     vec3 reflectionColor, vec3 refractionColor, float depth, float foam, out float alpha)
{
    float facing = ogxSaturate(dot(normal, viewDirection)); // 正对程度。
    float fresnel = ogxWaterFresnel(facing, 0.02); // 水的菲涅尔基础反射率约零点零二。
    vec3 transmitted = refractionColor * ogxWaterAbsorption(water, depth); // 水下颜色被水吸收。
    // 深水会彻底吸收掉水底的颜色，只剩水本身的体色；不补这一步，深海会变成一块黑。
    transmitted = mix(water.deepColor, transmitted, exp(-depth * 0.32)); // 越深越接近深水体色。
    transmitted = mix(water.shallowColor, transmitted, ogxSaturate(depth * 0.25)); // 浅水保留更多水色。
    vec3 color = mix(transmitted, reflectionColor, fresnel); // 折射与反射按菲涅尔混合。
    color += ogxSpecularGGX(normal, viewDirection, sunDirection, water.roughness, 0.02) * sunColor * 1.5; // 太阳高光。
    color += foam * water.shallowColor * 0.8; // 岸线泡沫。
    alpha = ogxSaturate(fresnel * 0.85 + 0.22 + ogxSaturate(depth * 0.08)); // 深水更不透明。
    return color; // 返回线性水面颜色。
}

#endif
