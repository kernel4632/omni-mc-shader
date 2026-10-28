/*
生成文件：末地模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库末地模块：末地星空、行星 BRDF、黑洞吸积盘包装与云影查表。
调用位置：`shaders/effects/world/end_sky.glsl` 的 `CalculateStars` 调用 `ogxEndStars`；
    主文件提供 ogxPlanetShading 入口，其余函数由子文件与严格 profile 使用。
可复制示例：
    vec3 stars = ogxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);
    vec3 disc = ogxBlackHoleStars(color, rayDir, lightDir, 0.5, frameTime, true, true, sunVector, 1, noiseTex, 512.0);
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
#include "/omni-gfx/common/math.glsl"
// 雾提供分形云噪声，吸积盘纹理细节要用。
#include "/omni-gfx/fog/fog.glsl"
// 云提供球面求交、密度与顶部曲线，云影查表要用。
#include "/omni-gfx/cloud/cloud.glsl"
// 行星提供末地天空与行星环，行星着色要用钱德拉塞卡近似。
#include "/omni-gfx/planet.glsl"
// 吸积盘积分只保留一份，末地的天空版与反射版只差参数。
#include "/omni-gfx/accretion.glsl"
// 末地星空：天球格子哈希与黑体星色。
// 子文件：world/end/stars.slang。
// 末地星空子文件：按天球格子取哈希星点，星色用黑体温度。
// 调用位置：由 `world/end.slang` 内联；末地天空与吸积盘叠加都调用 `ogxEndStars`。
// 设计原因与取舍：星场只依赖方向、时间与太阳方向，旋转与色温都来自通用数学，可单独测试。
// 可复制示例：`vec3 stars = ogxEndStars(worldDir, sunVector, frameTime, 1, 1.0, 1.0);`

// iterationT 末地星空：先绕纵轴缓慢自转，再把天球对齐太阳轴，最后在格子里取星点。
// `starType`、`brightness`、`amount` 是参考签名的三个开关；当前星场只用到前两个，保留参数以便严格对照。
vec3 ogxEndStars(vec3 worldDir, vec3 worldSunVector, float time, int starType, float brightness, float amount)
{
    float angleY = time * 0.001; // 星空缓慢自转。
    mat3 eyeRotationY = ogxRotationY(angleY); // 绕纵轴旋转。
    worldDir = ogxMatrix3MulPoint(eyeRotationY, worldDir); // 转到星空坐标。
    const float scale = 384.0; // 星点密度。
    const float coverage = 0.007; // 星点覆盖率。
    const float maxLuminance = 0.04; // 单颗星最大亮度。
    const float minTemperature = 4000.0; // 最低色温。
    const float maxTemperature = 8000.0; // 最高色温。
    float cosine = dot(worldSunVector, vec3(0.0, 0.0, 1.0)); // 绕日轴对齐。
    vec3 axis = cross(worldSunVector, vec3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 轴长度倒数平方。
    worldDir = cosine * worldDir + cross(axis, worldDir)
        + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 参考实现的球面旋转。
    vec3 p = worldDir * scale; // 放大到格子。
    vec3 i = floor(p); // 格子下标。
    vec3 f = p - i; // 格内偏移。
    float r = dot(f - 0.5, f - 0.5); // 到格中心距离平方。
    vec3 i3 = fract(i * vec3(443.897, 441.423, 437.195)); // 三维哈希。
    i3 += dot(i3, i3.yzx + 19.19); // 二次混合。
    vec2 hash = fract((i3.xx + i3.yz) * i3.zy); // 两个哈希值。
    hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 亮度曲线。
    float c = ogxRemapSaturate(hash.x, 1.0 - coverage, 1.0); // 覆盖率阈值。
    return maxLuminance * ogxRemapSaturate(r, 0.25, 0.0) * c * c * ogxBlackbody(mix(minTemperature, maxTemperature, hash.y)); // 星点亮度乘色温。
}

// 吸积盘包装：天空版与反射版只填参数。
// 子文件：world/end/accretion.slang。
// 末地吸积盘子文件：只保留天空版与反射版的参数，积分本身调用 `accretion` 模块。
// 调用位置：由 `world/end.slang` 内联；需要“吸积盘加星空”或“反射版吸积盘”的程序调用下面两个入口。
// 设计原因与取舍：两个版本原来各抄一份五十行积分，盘面算式改一次要改两处；现在只剩步数、起点与噪声幂次不同。
// 可复制示例：`vec3 c = ogxBlackHoleStars(color, rayDir, lightDir, 0.5, time, true, true, sunVector, 1, noiseTex, 512.0);`

// --- 算法说明与边界 ---
// 吸积盘积分沿视线在盘面内取样，半径越大越暗，多普勒项让朝向相机的一侧更亮。
// 天空版把颜色加到星空，反射版只返回颜色；两者共用同一套积分与噪声。
// 末地吸积盘：沿视线在盘面上积分，按半径与角度取噪声细节，再叠多普勒增亮。
// 天空版把盘面颜色加到星空上，反射版只返回颜色给反射合成；两者共用同一套积分。
// 吸积盘积分沿视线在盘面内取样，半径越大越暗，多普勒项让朝向相机的一侧更亮。
// 天空版把颜色加到星空，反射版只返回颜色；两者共用同一套积分与噪声。


// 黑洞吸积盘主函数：调用通用积分，再按参考实现的顺序叠星空并让盘面遮挡背景。
// `detailAlongLongitude`、`doppler` 与 `starType` 对应参考实现的三个菜单开关。
vec3 ogxBlackHoleStars(vec3 color, vec3 rayDir, vec3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, vec3 worldSunVector, int starType,
    sampler2D noiseTexture, float noiseResolution)
{
    vec4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, time, 50, 3.0, 4,
        detailAlongLongitude, doppler, noiseResolution); // 天空版：五十步、起点三、噪声四次方。
    if (starType > 0) color += ogxEndStars(rayDir, worldSunVector, time, starType, 1.0, 1.0); // 参考实现的星空叠加。
    color *= disc.a; // 盘面遮挡背景。
    return color + disc.rgb; // 最终颜色。
}

// 黑洞吸积盘反射版：步数更少、起点更远、噪声五次方，细节权重与主函数不同。
vec3 ogxBlackHoleReflection(vec3 color, vec3 rayDir, vec3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, sampler2D noiseTexture, float noiseResolution)
{
    vec4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, time, 30, 4.0, 5,
        detailAlongLongitude, doppler, noiseResolution); // 反射版：三十步、起点四、噪声五次方。
    color *= disc.a; // 盘面遮挡背景。
    return color + disc.rgb; // 最终颜色。
}

// 末地云影：按太阳方向取两次云密度。
// 子文件：world/end/cloud_shadow.slang。
// 末地云影子文件：按太阳方向在云层高度取两次密度，再换成地面阴影。
// 调用位置：由 `world/end.slang` 内联；需要复现 iterationT 云影查表的程序调用 `ogxCloudShadowTex`。
// 设计原因与取舍：只算基础形状、不算细节层，和参考实现的 `sampleDetail=false` 一致；噪声贴图与画质由调用方给出。
// 可复制示例：`float s = ogxCloudShadowTex(coord, altitude, wind, cameraXZ, sunVector, baseTex, 0.5, offset, 0.4, 0.7, 0.0, 512.0);`

// 云影密度函数的提前声明：云影查表会先调用它，定义放在文件末尾。
vec3 ogxCloudShadowDensity(vec4 cloudPos, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, vec3 windDirection);

// iterationT 云影查表：按太阳方向在云层高度取样两次，取较大密度后做指数衰减。
// `baseNoise` 是云形状噪声；`coverage` 与 `wetness` 由调用方按菜单填写。
float ogxCloudShadowTex(vec2 coord, vec2 cloudAltitude, vec3 windDirection, vec2 cameraXZ,
    vec3 worldShadowVector, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, float shadowRange)
{
    coord = coord * shadowRange - shadowRange * 0.5; // 屏幕坐标转云影范围。
    vec4 checkPos = vec4(coord.x + cameraXZ.x, 0.0, coord.y + cameraXZ.y, 0.0); // 云影起点。
    float thickness = cloudAltitude.y - cloudAltitude.x; // 云层厚度。
    checkPos += vec4(worldShadowVector * ((cloudAltitude.x + thickness * 0.25) / worldShadowVector.y), 0.25); // 沿太阳方向抬到云层。
    vec3 density = ogxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection); // 第一次取样。
    checkPos += vec4(worldShadowVector * ((thickness * 0.25) / worldShadowVector.y), 0.25); // 再抬四分之一层。
    density = max(density, ogxCloudShadowDensity(checkPos, baseNoise, baseScale, coverageOffset, clearCoverage, rainCoverage, wetness, windDirection)); // 第二次取样。
    return exp2(-density.y * 20.0); // 参考实现的云影衰减。
}

// 云影密度：只算基础形状，不算细节层，和参考实现的 `sampleDetail=false` 一致。
vec3 ogxCloudShadowDensity(vec4 cloudPos, sampler3D baseNoise, float baseScale, vec3 coverageOffset,
    float clearCoverage, float rainCoverage, float wetness, vec3 windDirection)
{
    vec4 baseSample = textureLod(baseNoise, cloudPos.xyz * baseScale + windDirection * 10.0, 0.0); // 基础噪声。
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2; // 三层混合。
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0); // 按形状重置。
    float shapeCurve = ogxCloudTopCurve(ogxSaturate(1.0 - cloudPos.w)) * 0.5; // 顶部曲线。
    shapeCurve += ogxCurve01(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 底部曲线。
    baseDensity *= shapeCurve; // 乘形状。
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 底部权重。
    baseDensity *= mix(1.0, ogxCloudTopCurve(ogxSaturate(cloudPos.w * 3.0)), wetness); // 雨天改顶部曲线。
    float coverageNoise = textureLod(baseNoise, cloudPos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + windDirection + coverageOffset, 0.0).x; // 覆盖噪声。
    float coverage = mix(clearCoverage, rainCoverage, wetness); // 晴雨覆盖。
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 覆盖阈值。
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0); // 覆盖裁剪。
    baseDensity *= ogxCurve01(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 密度控制。
    baseDensity *= ogxCloudTopCurve(ogxSaturate(cloudPos.w * 1.8)); // 顶部衰减。
    baseDensity = ogxSaturate(baseDensity); // 夹紧。
    return vec3(baseDensity); // 没有细节层。
}

// 末地行星着色：保留参考签名，实际算式与 `planet` 模块的行星 BRDF 相同。
// 参考的第五参数不参与着色，保留它只为让严格对照能按原签名调用。
vec3 ogxPlanetShading(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir, float s)
{
    return ogxPlanetBrdf(albedo, normal, eyeDir, lightDir); // 同一公式只维护一份；第五参数只为签名兼容。
}

#endif
