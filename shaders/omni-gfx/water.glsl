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
    `OgxOceanWaveSum sum = ogxOceanWaveSum(vec2(0.0), t, ogxOceanWavesDefault());` 迭代正弦海洋。
    `float h = ogxOceanWaveHeight(sum, 13.0, 1.0);` 归一化后的波高。
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

// 平滑噪声取样：先把坐标吸到最近的纹素中心，再用三次曲线改写小数部分，得到不会闪的平滑噪声。
// 与旧 `shaders/gfx/water.glsl` 的算式一致，波纹形状因此不变。
vec4 ogxTextureSmooth(sampler2D noiseTexture, vec2 coord)
{
    coord *= 64.0; // 放大到六十四格，再按格取平滑。
    coord += 0.5; // 移到格子中心。
    vec2 whole = floor(coord); // 整数格。
    vec2 part = coord - whole; // 小数部分。
    coord = whole + part * part * (3.0 - 2.0 * part); // 三次曲线改写小数部分。
    coord -= 0.5; // 移回格子角。
    coord *= 0.015625; // 缩回六十四分之一，换算到零到一坐标。
    return textureLod(noiseTexture, coord, 0.0); // 读取平滑后的噪声通道。
}

// 几乎恒等函数：只在靠近中间的一段把值重写成更平的曲线，用来压掉最亮和最暗的水波。
float ogxAlmostIdentity(float x, float m, float n)
{
    x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值。
    if (x <= m) // 只在该区间中间改写。
    {
        float a = 2.0 * n - m; // 三次项系数。
        float b = 2.0 * m - 3.0 * n; // 二次项系数。
        float t = x / m; // 归一化到零到一。
        x = (a * t + b) * t * t + n; // 三次多项式保持端点连续。
    }
    return 1.0 - x; // 再翻转回来。
}

// 水面高度：六层不同尺度与速度的噪声叠加，按权重和归一化。
float ogxWaves(vec3 position, sampler2D noiseTexture, float time, float waveScale)
{
    float wavesTime = time * 0.0035; // 波浪时间比真实时间慢很多。
    position *= waveScale; // 按波浪尺度缩放空间坐标。
    vec2 p = position.xz - position.y; // 取水平坐标，减去高度让波浪跟着高度错动。
    p += -3.875 * wavesTime; // 整片波浪一起平移。
    p.x = -p.x; // 翻转一个轴，打散方向。
    float waves = 0.0; // 累积高度。
    float weight = 0.0; // 累积权重。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(2.0, 1.2) + vec2(0.0, p.x * 2.1)).w; weight += 1.0; // 第一层大浪。
    p = p * 0.475; // 缩小坐标，频率升高。
    p += vec2(-5.16, -7.75) * wavesTime; // 这一层被风推着走。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(2.0, 1.4) + vec2(0.0, -p.x * 2.1)).w * 4.0; weight += 4.0; // 第二层。
    p *= 0.67; // 再抬高频率。
    p.x += 7.75 * wavesTime; // 反向移动。
    waves += ogxTextureSmooth(noiseTexture, p + vec2(0.0, p.x * 1.1)).z * 8.0; weight += 8.0; // 第三层。
    p *= 0.7; // 继续抬高频率。
    p.x += -2.82 * wavesTime; // 顺风移动。
    waves += ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.75) + vec2(0.0, -p.x * 1.7)).w * 16.0; weight += 16.0; // 第四层。
    p *= 0.45; // 高频细节。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, -p.x * 1.7)).z, 0.2, 0.1) * 30.0; weight += 30.0; // 第五层。
    p *= 0.5; // 最高频一层。
    p.x += wavesTime; // 顺风移动。
    waves += ogxAlmostIdentity(ogxTextureSmooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, p.x * 1.7)).w, 0.2, 0.1) * 20.0; weight += 20.0; // 第六层。
    return waves / weight; // 高度除以权重和，归一化到零到一。
}

// 波法线：用中心与两个邻点的高度差构成法线，再按波高与陡度缩放。
vec3 ogxWavesNormal(vec3 position, sampler2D noiseTexture, float time, float waveScale, float waveHeight, float heightScale)
{
    float sampleDistance = 12.0; // 切线差分采样的距离。
    position.xz -= 0.005 * sampleDistance; // 把采样点整体挪一点，让差分落在波浪内部。
    float center = ogxWaves(position, noiseTexture, time, waveScale); // 中心高度。
    float left = ogxWaves(position + vec3(0.01 * sampleDistance, 0.0, 0.0), noiseTexture, time, waveScale); // 横向偏移。
    float up = ogxWaves(position + vec3(0.0, 0.0, 0.01 * sampleDistance), noiseTexture, time, waveScale); // 纵向偏移。
    vec3 normal = vec3(center - left, center - up, 1.0); // 用两个方向的高度差构成法线。
    normal.xy *= waveHeight * (heightScale / sampleDistance); // 乘波高与陡度，控制倾斜。
    return normal; // 返回未归一化的法线。
}

// 水面视差：沿视线在波浪高度场里步进，找到视线与浪面的交点。
vec3 ogxWaterParallax(vec3 position, vec3 viewVector, sampler2D noiseTexture, float time, float waveScale, float heightScale)
{
    vec3 stepSize = vec3(heightScale * 0.8, heightScale * 0.8, 0.6); // 每步大小，按波高缩放。
    float waveHeight = ogxWaves(position, noiseTexture, time, waveScale); // 起点波高。
    vec3 pCoord = vec3(0.0, 0.0, 1.0); // 以当前点为参考向前推进的距离。
    vec3 steps = viewVector * stepSize; // 每步步进。
    float sampleHeight = waveHeight; // 当前步的波高。
    for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i) // 最多十二步。
    {
        pCoord.xy += steps.xy * clamp((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2), 0.0, 1.0); // 按剩余深度推进水平偏移。
        pCoord.z += steps.z; // 步进向前。
        sampleHeight = ogxWaves(position + vec3(pCoord.x, 0.0, pCoord.y), noiseTexture, time, waveScale); // 读取新位置的波高。
    }
    return position + vec3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

// 折射坐标：水面按两种法线的差做偏移，玻璃与冰按折射方向投影到屏幕。
vec2 ogxWaterRefractionCoord(bool isWater, vec3 normal, vec3 viewPos, vec3 waveNormal,
    mat3 modelView, mat4 projection, float waterDeep, float waterDist, vec2 screenInput)
{
    vec2 coord = screenInput; // 默认不变，返回原屏幕坐标。
    if (isWater) // 水面：用波法线与平水面法线的差做偏移。
    {
        vec3 waveView = normalize(ogxMatrix3MulPoint(modelView, waveNormal)); // 波法线转到视空间。
        vec3 flatView = normalize(ogxMatrix3MulPoint(modelView, vec3(0.0, 1.0, 0.0))); // 平水面法线转到视空间。
        coord = flatView.xy - waveView.xy; // 两种法线的差就是偏移方向。
        coord *= ogxSaturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深偏得越远，远处收敛到零。
        coord += screenInput; // 叠到原坐标上。
    }
    else // 玻璃与冰：按折射方向投影到屏幕。
    {
        vec3 direction = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
        direction /= ogxSaturate(dot(direction, -normal)); // 归一化到视线方向，避免分母让角度爆炸。
        direction *= ogxSaturate(waterDeep * 2.0) * 0.125; // 按深度缩放。
        vec4 position = ogxMatrixMul(projection, vec4(viewPos + direction, 0.0)); // 投影到裁剪空间。
        coord = position.xy / position.w * 0.5 + 0.5; // 转到屏幕坐标。
    }
    return coord; // 返回采样用的屏幕坐标。
}

// 水洼覆盖：只有湿度超过噪声阈值的地方才积水，五次方让边缘收得很快。
float ogxPuddleCoverage(float halfWet, float noise, float size)
{
    float puddles = max(halfWet - noise, 0.0); // 只算湿度超过噪声阈值的部分。
    puddles = clamp(halfWet - exp(-25.0 * puddles * puddles * puddles * puddles * puddles * size), 0.0, 1.0); // 指数衰减得到积水比例。
    return puddles; // 返回零到一的积水覆盖。
}

// 降水高光：三层噪声叠出雨点打在物体表面的细碎高光。
float ogxRainSpecular(vec3 pos, sampler2D noiseTexture)
{
    pos.y *= 0.2; // 压扁竖直方向，让高光沿竖直变化更慢。
    float n = 0.0; // 累积噪声。
    n += ogxFogNoise(pos, noiseTexture); // 第一层。
    n += ogxFogNoise(pos * 0.5, noiseTexture) * 2.0; // 第二层，缩小坐标并放大权重。
    n += ogxFogNoise(pos * 0.25, noiseTexture) * 4.0; // 第三层，更细的权重更高。
    n /= 7.0; // 平均到零到一。
    return clamp(n, 0.0, 1.0) * 0.7 + 0.3; // 留一个下限，避免完全没有高光。
}

// 水体雾：把水下的吸收、散射与全反射合成一段颜色，再按可见度混回场景。
vec3 ogxWaterFog(vec3 color, vec3 viewDir, float opaqueDist, float waterDist, vec3 normal,
    float ice, float stainedGlass, float hand, float occludedWater, float waterSkylight, float totalInternal,
    vec3 lightDir, vec3 lightColor, vec3 skyColor, vec3 upView, float eyeWaterDepth, float wetness,
    float refractIor, float fogDensityOption, bool underwater)
{
    float distDiff = opaqueDist - waterDist; // 水面到水底的真实距离。
    waterDist = underwater ? mix(waterDist, opaqueDist, stainedGlass) : mix(distDiff, min(distDiff * 0.3, 6.0), occludedWater); // 按遮挡与玻璃修正厚度。
    waterDist = max(waterDist, totalInternal * eyeWaterDepth * 50.0); // 全反射时按眼睛水深拉长光程。
    vec3 shadowRefracted = refract(-lightDir, upView, 1.0 / refractIor); // 太阳经过水面的折射方向。
    vec3 fogColor = mix(vec3(0.05, 0.6, 1.0), vec3(0.3, 0.9, 1.5), ice); // 冰偏青，普通水偏蓝。
    fogColor = mix(fogColor, vec3(0.5), wetness * 0.6); // 越湿颜色越灰。
    fogColor *= dot(vec3(0.33333), skyColor); // 水雾颜色随环境色变化。
    if (!underwater) // 水面之上看水下。
    {
        fogColor *= 0.04 - wetness * 0.032; // 水面之上的散射只占很小一部分。
        fogColor *= waterSkylight; // 再乘该处水面的天光。
        vec3 l = normalize(reflect(viewDir, normal)); // 视线在水面的反射方向。
        vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
        float fresnel = ogxSaturate(dot(normal, l)) * ogxSaturate(dot(l, h) * 1.5 - 0.5); // 简化的反射权重。
        float scatter = 3.0 * fresnel * pow(dot(shadowRefracted, viewDir) * 5.0 + 5.2, -1.4); // 逆光时的散射强度。
        fogColor = mix(fogColor, lightColor * fogColor * 3.0, scatter * ogxSaturate(1.0 - wetness - occludedWater)); // 按散射叠进光色。
    }
    else // 眼睛在水里。
    {
        fogColor *= 0.02 - wetness * 0.012; // 水下的散射更暗。
        float scatter = 1.0 / (dot(shadowRefracted, viewDir) * 5.0 + 5.1); // 水下的前向散射。
        vec3 sunScatter = lightColor * scatter * fogColor * 2.0; // 太阳在水下的散射色。
        fogColor *= dot(viewDir, upView) * 0.4 + 0.6; // 向上看更亮。
        fogColor += sunScatter * (eyeWaterDepth * (1.0 - wetness * 0.6)); // 加上太阳散射。
    }
    float density = underwater ? ice * 0.96 + 0.04 : 0.29; // 水下密度更高。
    float visibility = exp2(-waterDist * density * fogDensityOption); // 按光程指数衰减得到可见度。
    visibility = clamp(visibility, 0.35 * ice, 1.0); // 冰给出一个可见度下限。
    visibility = mix(visibility, 0.7, hand); // 手里的东西只受轻微影响。
    vec3 attenuation = underwater ? vec3(0.1, 0.6, 1.0) : vec3(0.2, 0.5, 0.7); // 分通道衰减色，水底偏蓝。
    color *= pow(attenuation * 0.99, vec3(waterDist * (0.21 * float(!underwater) + 0.04) * fogDensityOption)); // 按光程衰减，长波先掉。
    return mix(fogColor, color, visibility); // 用可见度在水雾色与场景色之间混合。
}

// 雨点动画法线：读一张雨点动画贴图并转成带符号的法线，指数控制边缘锐度。
// 只取红绿两通道：这张贴图存的是法线的横纵分量，蓝色在写入端舍弃。
vec2 ogxRainAnimationNormal(sampler2D rainTexture, vec2 coord, float exponent)
{
    vec2 n = textureLod(rainTexture, coord, 0.0).rg; // 读红绿两通道。
    n = n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 零到一转成负一到一，并翻转纵轴。
    n = pow(abs(n), vec2(exponent)) * sign(n); // 按指数压形状，符号保留。
    return n; // 返回法线横纵分量。
}

// 波法线方块读取：把世界位置按折射方向投到七号画面左下角的波法线方块，解出世界空间法线。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
vec3 ogxWavesNormalFromTex(vec3 position, vec3 lightDir, sampler2D normalTexture, vec2 pixelSize,
    vec2 screenExtent, float maxResolution, float refractIor)
{
    vec3 refracted = refract(lightDir, vec3(0.0, 1.0, 0.0), 1.0 / refractIor); // 阳光按水面折射率弯折。
    vec2 coord = position.xz; // 先取水平坐标。
    coord.x += position.y * refracted.x / refracted.y; // 按高度沿光线横移横坐标。
    coord.y += position.y * refracted.z / refracted.y; // 按高度沿光线横移纵坐标。
    coord *= 0.02; // 缩到波法线图的空间尺度。
    coord = fract(coord); // 平铺到零到一。
    coord *= pixelSize * min(screenExtent.y, maxResolution); // 折算成方块里的像素坐标。
    return ogxDecodeNormal(textureLod(normalTexture, coord, 0.0).xy); // 从方块里读八面体编码法线。
}

// 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
// `cameraOffset` 用来还原绝对世界坐标，`underwater` 决定是否往全亮靠。
float ogxWaterCaustics(vec3 worldPos, vec3 lightDir, vec3 cameraOffset, sampler2D normalTexture,
    vec2 pixelSize, vec2 screenExtent, float maxResolution, float refractIor, vec2 dither,
    bool underwater, float brightness, float power)
{
    vec3 position = worldPos + cameraOffset; // 换成绝对世界坐标。
    vec3 lookupCenter = position + vec3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。
    float caustics = 0.0; // 累计焦散强度。
    for (float i = -1.0; i <= 1.0; i++) // 三乘三抖动采样。
    {
        for (float j = -1.0; j <= 1.0; j++)
        {
            vec2 offset = dither + vec2(i, j); // 当前采样偏移。
            vec3 lookupPoint = lookupCenter; // 这一处的波面查询点。
            lookupPoint.xz += offset * 0.1; // 按偏移横移。
            vec3 wavesNormal = ogxWavesNormalFromTex(lookupPoint, lightDir, normalTexture, pixelSize,
                screenExtent, maxResolution, refractIor).xzy; // 读取波法线并换到竖直轴朝上的坐标。
            vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
            vec3 collision = lookupPoint - refractVector / refractVector.y; // 光线与水平面的交点。
            collision -= position; // 相对当前位置。
            float dist = dot(collision, collision) * 7.1; // 交点距离的平方，放大差距。
            caustics += 1.0 - ogxSaturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
        }
    }
    float finalCaustics = mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(underwater)); // 拼成焦散亮度，水下再往全亮靠一点。
    return pow(finalCaustics * brightness, power); // 按亮度倍率与对比指数重整。
}

// 迭代正弦海洋的参数：换水体只改字段，不必再抄一遍循环。
// 这些数就是 iterationT 海洋扩展的取值，举个例子：每层频率乘一点一八、权重乘零点八，
// 于是低频波大而慢、高频波小而快，叠出来才是海面而不是规则条纹。
struct OgxOceanWaves
{
    int iterations; // 叠几层波形，层数越多越细也越贵。
    float drag; // 每层把采样点往波前进方向拖多少，形成剪切与卷曲。
    float timeScale; // 时间缩放，让相位推进速度跟上原程序。
    float detail; // 细节权重指数，只影响累加出来的方向。
    float frequency; // 起始频率。
    float speed; // 起始相位速度。
    float weightFalloff; // 每层权重衰减，越高越偏向低频波。
    float frequencyGain; // 每层频率放大。
    float speedGain; // 每层相位速度放大。
    float angleStep; // 每层方向角增量，让各层方向错开。
};

// 默认参数：iterationT 海洋扩展的常数，调用方只改真正要变的那几个字段。
OgxOceanWaves ogxOceanWavesDefault()
{
    OgxOceanWaves waves;
    waves.iterations = 13; // 层数的基础值，原程序的迭代偏移量。
    waves.drag = 0.048; // 拖拽量小一点，避免波形自己卷起来。
    waves.timeScale = 0.45; // 时间放慢，海面起伏看起来更沉。
    waves.detail = 0.75; // 细节指数，原程序取值。
    waves.frequency = 6.0; // 起始频率。
    waves.speed = 2.0; // 起始相位速度。
    waves.weightFalloff = 0.8; // 每层权重乘零点八，低频占主导。
    waves.frequencyGain = 1.18; // 每层频率乘一点一八。
    waves.speedGain = 1.07; // 每层速度乘一点零七。
    waves.angleStep = 12.0; // 每层方向转十二弧度，等效于错开一圈多，视觉上方向不重复。
    return waves;
}

// 逐层叠加的结果：都是未归一化的和，调用方按自己的用法再除权重和。
struct OgxOceanWaveSum
{
    float height; // 波高和，未除权重。
    float weightSum; // 权重和，用来归一化。
    vec2 detail; // 按细节指数累加的方向，泡沫与法线要用。
    vec2 position; // 被波形拖拽后的采样点。
};

// 迭代正弦：每层的频率、速度都放大，权重衰减，采样点被波形拖着走。
// 为什么方向累加也放在同一个循环里：一处调用只取波高、另一处还要方向，
// 多算一次加法不影响波高，却省掉第二份一模一样的循环，两边不会再各自漂移。
OgxOceanWaveSum ogxOceanWaveSum(vec2 position, float time, OgxOceanWaves waves)
{
    float iter = 0.0; // 每层方向角。
    float frequency = waves.frequency; // 当前层频率。
    float speed = waves.speed; // 当前层速度。
    float weight = 1.0; // 当前层权重，从一整份开始衰减。
    float height = 0.0; // 累加波高。
    float weightSum = 0.0; // 累加权重。
    vec2 detail = vec2(0.0); // 累加方向。
    float modifiedTime = time * waves.timeScale; // 缩放后的时间。
    for (int i = 0; i < waves.iterations; i++) // 逐层叠加。
    {
        vec2 direction = vec2(sin(iter), cos(iter)); // 当前层方向。
        float x = dot(direction, position) * frequency + modifiedTime * speed; // 当前层的相位。
        float wave = exp(sin(x) - 1.0); // 波峰更尖的包络，海面才有尖顶。
        float result = wave * cos(x); // 波形值。
        vec2 force = result * weight * direction; // 对采样点的拖拽力。
        detail += force / pow(weight, waves.detail); // 权重越小的层贡献越大，细节层因此不会被低频淹没。
        position -= force * waves.drag; // 采样点被拖拽，形成剪切。
        height += wave * weight; // 累加波高。
        iter += waves.angleStep; // 方向角前进。
        weightSum += weight; // 累加权重。
        weight *= waves.weightFalloff; // 权重衰减。
        frequency *= waves.frequencyGain; // 频率放大。
        speed *= waves.speedGain; // 速度放大。
    }
    OgxOceanWaveSum sum;
    sum.height = height; // 交回未归一化的波高。
    sum.weightSum = weightSum; // 交回权重和。
    sum.detail = detail; // 交回方向累加。
    sum.position = position; // 交回拖拽后的位置。
    return sum;
}

// 归一化波高并按海面高度缩放、居中：两处调用共用这一条换算式。
float ogxOceanWaveHeight(OgxOceanWaveSum sum, float oceanHeight, float factor)
{
    return sum.height / sum.weightSum * oceanHeight * factor - oceanHeight * factor * 0.5; // 居中让海面在基准高度上下对称。
}

// 波形空间：把世界水平坐标按原点偏移与横向缩放换成迭代正弦使用的坐标。
// 为什么单独成一个函数：波高、方向与像素数据必须用同一个空间，三处各写一遍迟早会漂移。
vec2 ogxOceanWaveSpace(vec2 position, vec2 offset, float xzScale, float horizontalScale)
{
    return (position - offset) * xzScale * horizontalScale; // 先减原点再乘两级缩放。
}

// 海洋波方向：把逐层累加的方向除以权重和，取负后指向波前进方向。
vec2 ogxOceanWaveDirection(OgxOceanWaveSum sum, float detailWeight)
{
    return -sum.detail / pow(sum.weightSum, 1.0 - detailWeight); // 与参考实现的归一化逐项相同。
}

// 海洋波形法线：横纵方向乘上海面高度与波高倍率，再补一个固定的竖直强度。
vec3 ogxOceanWaveNormal(vec2 direction, float oceanHeight, float factor, float normalStrength)
{
    float oceanHeightFactor = oceanHeight / 13.0; // 海面高度相对基础值十三的倍率。
    float totalFactor = oceanHeightFactor * factor; // 总倍率。
    return normalize(vec3(direction.x * totalFactor, normalStrength, direction.y * totalFactor)); // 由方向构造法线。
}

// 波形法线与涟漪法线的混合：涟漪越强，法线越偏向贴图给出的细节。
// `totalEffect` 是四邻高度和，开方后作为混合权重，照参考实现。
vec3 ogxOceanNormalWithRipple(vec2 position, vec2 direction, float factor, float oceanHeight, float normalStrength,
    vec2 modelOffset, sampler2D rippleTexture, float rippleRange, vec2 texel)
{
    vec3 waveNormal = ogxOceanWaveNormal(direction, oceanHeight, factor, normalStrength); // 先算波形法线。
    vec2 eyePosition = position + modelOffset; // 加上模型偏移，定位涟漪。
    vec2 fetch = (eyePosition + vec2(rippleRange, rippleRange)) / (rippleRange * 2.0); // 涟漪贴图坐标。
    float left = textureLod(rippleTexture, fetch - vec2(texel.x, 0.0), 0.0).r; // 左侧高度。
    float right = textureLod(rippleTexture, fetch + vec2(texel.x, 0.0), 0.0).r; // 右侧高度。
    float top = textureLod(rippleTexture, fetch - vec2(0.0, texel.x), 0.0).r; // 上侧高度。
    float bottom = textureLod(rippleTexture, fetch + vec2(0.0, texel.x), 0.0).r; // 下侧高度。
    float totalEffect = left + right + top + bottom; // 四邻合计。
    vec3 rippleNormal = normalize(vec3(left - right, 1.0, top - bottom)); // 涟漪法线。
    return normalize(mix(waveNormal, rippleNormal, pow(totalEffect, 0.5))); // 按涟漪强度混合。
}

// 海洋泡沫：三层三维噪声相乘得到泡沫形状，再按波峰高度与细胞噪声调制。
// `waveAmplitude` 是已经乘过法线竖直分量的波峰振幅，函数只负责把它夹到零到一。
float ogxOceanFoam(sampler3D foamTexture, vec2 waterUV, float time, float foamAmount, float foamOpacity,
    float waveAmplitude)
{
    vec2 s1 = textureLod(foamTexture, vec3(waterUV * 0.26, time / 360.0), 0.0).rg; // 第一层泡沫噪声。
    vec2 s2 = textureLod(foamTexture, vec3(waterUV * 0.02, time / 360.0 + 0.5), 0.0).rg; // 第二层。
    vec2 s3 = textureLod(foamTexture, vec3(waterUV * 0.1, time / 360.0 + 1.0), 0.0).rg; // 第三层。
    float surfaceNoise = s1.r * s2.r * s3.r * 2.8 * foamAmount; // 三层相乘得到泡沫形状。
    waveAmplitude = clamp(waveAmplitude * 1.2, 0.0, 1.0); // 波峰处的振幅。
    surfaceNoise = (1.0 - waveAmplitude) * surfaceNoise + waveAmplitude * foamAmount; // 波峰处泡沫更强。
    float worleyNoise = 0.2 + 0.8 * s1.g * (1.0 - s2.g); // 细胞状调制。
    surfaceNoise = smoothstep(0.45, 1.0, surfaceNoise) * worleyNoise; // 阈值平滑并乘调制。
    return clamp(2.0 * surfaceNoise * foamOpacity, 0.0, 1.0); // 乘不透明度得到最终泡沫。
}

// 海面像素：一次算出方向、还原位置、法线、泡沫与波高，片元阶段只取一次。
struct OgxOceanPixel
{
    vec2 direction; // 波形方向。
    vec2 worldPos; // 还原后的世界位置。
    vec3 normal; // 混合涟漪后的法线。
    float foam; // 泡沫强度。
    float height; // 波高。
};

// 完整海面像素：把波形迭代、空间换算、涟漪贴图与泡沫噪声放在同一处，宿主只传数据。
// `texel` 是涟漪贴图的横向纹素大小；`iterations` 是浮点层数，内部向上取整，与参考实现一致。
OgxOceanPixel ogxOceanPixel(vec2 position, float factor, float iterations, float time,
    vec2 waveOffset, float xzScale, float horizontalScale, float oceanHeight, vec2 modelOffset,
    sampler2D rippleTexture, float rippleRange, vec2 texel,
    sampler3D foamTexture, float globalTime, float foamAmount, float foamOpacity, float normalStrength)
{
    vec2 wavePos = ogxOceanWaveSpace(position, waveOffset, xzScale, horizontalScale); // 换到波形空间。
    OgxOceanWaves waves = ogxOceanWavesDefault(); // 参考实现的默认常数。
    waves.iterations = int(ceil(iterations)); // 层数向上取整，与原来的整数比较等价。
    OgxOceanWaveSum sum = ogxOceanWaveSum(wavePos, time, waves); // 逐层累加。
    OgxOceanPixel pixel; // 待填充。
    pixel.direction = ogxOceanWaveDirection(sum, waves.detail); // 波形方向。
    pixel.worldPos = sum.position / horizontalScale / xzScale; // 还原世界位置。
    pixel.height = ogxOceanWaveHeight(sum, oceanHeight, factor); // 归一化波高。
    pixel.normal = ogxOceanNormalWithRipple(position, pixel.direction, factor, oceanHeight, normalStrength,
        modelOffset, rippleTexture, rippleRange, texel); // 波形法线混入涟漪。
    float waveAmplitude = pixel.height * pow(max(pixel.normal.y, 0.0), 4.0); // 波峰振幅。
    vec2 waterUV = mix(position - waveOffset, pixel.worldPos, clamp(factor * 2.0, 0.2, 1.0)); // 泡沫坐标在原始与波后位置间混合。
    pixel.foam = ogxOceanFoam(foamTexture, waterUV, globalTime, foamAmount, foamOpacity, waveAmplitude); // 泡沫强度。
    return pixel; // 交回完整数据。
}

// 涟漪专用标量哈希：与 Eclipse `ripples.glsl` 的 `hash12` 保持同一组常数。
// 为什么不用噪声模块的 `ogxHash12`：那个哈希混入了另一组偏移，值噪声依赖它；涟漪要照原图逐项复现，不能换。
float ogxRippleHash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031); // 两个坐标扩成三个分量。
    p3 += dot(p3, p3.yzx + 19.19); // 三个分量互相混合。
    return fract((p3.x + p3.y) * p3.z); // 取小数部分。
}

// Eclipse 雨点涟漪：九个格子的雨滴各自扩散出圆环，取梯度得到法线。
// `intensity` 控制每格大小，`time` 是累积秒数；九个方向相加后归一，结果与参考实现相同。
vec3 ogxRainRipples(vec2 fragCoord, float time, float intensity)
{
    float cellDensity = 5.0 * intensity; // 每米几个雨点。
    float sizeCompensation = cellDensity / 5.0; // 密度改变时补偿圆环半径。
    vec2 uv = fragCoord * cellDensity; // 换到格子坐标。
    vec2 p0 = floor(uv); // 当前格子。
    vec2 circles = vec2(0.0); // 累加梯度。
    for (int j = -1; j <= 1; j++) // 三乘三邻格。
    {
        for (int i = -1; i <= 1; i++)
        {
            vec2 pi = p0 + vec2(float(i), float(j)); // 邻格坐标。
            vec2 p = pi + ogxHash22(pi); // 雨点落在格内随机位置。
            float t = fract(0.9 * time + ogxRippleHash12(pi)); // 这一滴的扩散相位。
            vec2 v = p - uv; // 从雨点到当前像素。
            float d = length(v) - 2.0 * t * sizeCompensation; // 圆环半径随时间扩大。
            float d1 = d - 0.01; // 前后两个采样点。
            float d2 = d + 0.01;
            float p1 = sin(21.0 * d1) * smoothstep(-0.6, -0.3, d1) * (1.0 - smoothstep(-0.3, 0.0, d1)); // 前一点的高度。
            float p2 = sin(21.0 * d2) * smoothstep(-0.6, -0.3, d2) * (1.0 - smoothstep(-0.3, 0.0, d2)); // 后一点的高度。
            circles += 0.5 * normalize(v) * ((p2 - p1) / 0.02 * (1.0 - t) * (1.0 - t)); // 中心差分得到坡度。
        }
    }
    circles /= 9.0; // 九个方向取平均。
    return vec3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0))); // 参考实现不做归一化，保持原幅度。
}

// Eclipse 水面焦散：沿太阳方向把水面位置投到水底，用噪声图三层旋转采样得到汇聚花纹。
// `time` 是累积秒数，`waveSpeed` 与 `patchyBlend` 是水面选项，噪声图由调用方给出。
float ogxWaterBumpCaustics(vec3 worldPos, vec3 sunVec, float surfacePos, float time, float waveSpeed,
    float patchyBlend, sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    vec2 projected = worldPos.xz + (sunVec.xz / abs(sunVec.y)) * surfacePos; // 沿阳光投到水底。
    vec2 pos = projected; // 当前采样坐标。
    float largeWaves = textureLod(noiseTexture, pos / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = mix(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float heightSum = 0.0; // 三层高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    vec2 rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    float sample0 = textureLod(noiseTexture, pos / vec2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层，横向拉长。
    heightSum += pow(abs(abs(sample0 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 折线整形后累加。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    float sample1 = textureLod(noiseTexture, pos / vec2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层，纵向拉长。
    heightSum += pow(abs(abs(sample1 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第二层。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    float sample2 = textureLod(noiseTexture, pos / vec2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层，正方形。
    heightSum += pow(abs(abs(sample2 * 2.0 - 1.0) * 2.0 - 1.0), 1.0 + largeWavesCurved); // 累加第三层。
    return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5)); // 汇聚成焦散亮度。
}

// Eclipse 水面高度：三层噪声按旋转叠加，再乘大波曲线。
float ogxWaterBumpHeightmap(vec2 position, float largeWavesCurved, float time, float waveSpeed, sampler2D noiseTexture)
{
    float movement = time * 0.035 * waveSpeed; // 波纹随时间平移。
    vec2 pos = position; // 当前采样坐标。
    float heightSum = 0.0; // 高度累加。
    float cosine = cos(2.39996); // 旋转角余弦。
    float sine = sin(2.39996); // 旋转角正弦。
    vec2 rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第一次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(48.0, 12.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第一层高度。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第二次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(12.0, 48.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第二层高度。
    rotated = vec2(pos.x * cosine + pos.y * sine, -pos.x * sine + pos.y * cosine); // 第三次旋转。
    pos = rotated;
    heightSum += textureLod(noiseTexture, pos / vec2(32.0, 32.0) + largeWavesCurved * 0.5 + movement, 0.0).b; // 第三层高度。
    return (heightSum / 4.5) * max(largeWavesCurved, 0.3); // 归一化并留一个下限。
}

// Eclipse 水面法线：中心与横纵两个邻点的高度差构成法线，采样距离随距离与画质变化。
vec3 ogxWaterBumpNormal(vec3 waterPos, vec3 playerPos, float time, float waveSpeed, float patchyBlend,
    float wavesARadius, float wavesBRadius, bool hyperDetailed, sampler2D noiseTexture)
{
    float largeWaves = textureLod(noiseTexture, waterPos.xy / 600.0, 0.0).b; // 大尺度波。
    float largeWavesCurved = pow(1.0 - pow(1.0 - largeWaves, 2.5), 4.5); // 曲线重整。
    largeWavesCurved = mix(1.0 - largeWavesCurved, largeWavesCurved, patchyBlend); // 按斑块选项混合。
    float deltaPos = 0.025; // 超高质量用固定小步长。
    if (!hyperDetailed) // 普通质量按大波曲线与距离选步长。
    {
        deltaPos = mix(wavesARadius, wavesBRadius, largeWavesCurved); // 两个半径之间插值。
        deltaPos += min(length(playerPos) / (16.0 * 24.0), 3.0); // 远处加大步长，减少闪烁。
    }
    float h0 = ogxWaterBumpHeightmap(waterPos.xy, largeWavesCurved, time, waveSpeed, noiseTexture); // 中心高度。
    float h1 = ogxWaterBumpHeightmap(waterPos.xy + vec2(deltaPos, 0.0), largeWavesCurved, time, waveSpeed, noiseTexture); // 横向邻点。
    float h3 = ogxWaterBumpHeightmap(waterPos.xy + vec2(0.0, deltaPos), largeWavesCurved, time, waveSpeed, noiseTexture); // 纵向邻点。
    float xDelta = (h1 - h0) / deltaPos; // 横向坡度。
    float yDelta = (h3 - h0) / deltaPos; // 纵向坡度。
    return normalize(vec3(xDelta, yDelta, 1.0 - pow(abs(xDelta + yDelta), 2.0))); // 高度场法线。
}

#endif
