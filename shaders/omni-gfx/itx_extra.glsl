/*
生成文件：补充后期模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 iterationT 补充模块：对焦、曝光、泛光合并、FXAA、镜头光斑与各向异性采样。
调用位置：需要复现 iterationT 后期与地形取样细节的程序；Minecraft 光影由 `/omni-gfx/itx_extra.glsl` 引入。
可复制示例：
    float focus = ogxGetFocus(colortex2, screenExtent, 0, 8.0, projectionInverse);
    vec3 tone = ogxMergeBloom(color, 1.0 - data.a, ...);
    vec3 sharp = ogxFxaa(color, texCoord, pixelSize, colortex1);
设计原因与取舍：
    参考实现把这些步骤写成程序入口的一部分，直接依赖缓冲编号与宏。库把缓冲、选项与常量
    全部改为参数，函数体仍逐行保留原来的条件分支与常数，调用方按自己的管线填写即可。
    所有纹理由参数传入，模块不读取游戏状态，因此同一份算法可以用于测试世界或别的引擎。
*/
#ifndef OGX_ITX_EXTRA_INCLUDED
#define OGX_ITX_EXTRA_INCLUDED

// 数学与颜色模块提供曲线转换、曝光与相位，大气模块提供平面云的空气透视。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/color.glsl"
#include "/omni-gfx/atmosphere_model.glsl"
#include "/omni-gfx/cloud.glsl"
#include "/omni-gfx/fog.glsl"
#include "/omni-gfx/shadow.glsl"
// 对焦距离：参考实现从第二张缓冲左下角取一个对比度统计值，或直接使用手动焦距。
float ogxGetFocus(sampler2D focusTexture, ivec2 screenExtent, int focusMode, float focalPoint, mat4 projectionInverse)
{
    float focus; // 对焦距离，米。
    if (focusMode == 0) // 自动对焦：读取统计像素。
    {
        vec4 stat = texelFetch(focusTexture, ivec2(60, screenExtent.y - 1), 0); // 固定取横向第六十个像素。
        focus = ogxShadowLinearDepth(stat.a * 0.125 + 0.875, projectionInverse); // 编码值还原成米。
    }
    else // 手动对焦。
    {
        focus = focalPoint; // 直接使用调用方给的焦距。
    }
    return focus; // 交回对焦距离。
}

// 镜头光斑的桶形偏移：把二维偏移按到画面中心的距离旋转，得到弯曲的光斑轨迹。
vec2 ogxLensDistOffset(vec2 uv, vec2 pxOffset, float barrel)
{
    vec2 toCenter = uv; // 画面中心到当前点的方向。
    vec3 prep = normalize(vec3(toCenter.y, -toCenter.x, 0.0)); // 旋转轴。
    float angle = length(toCenter) * 2.221 * barrel; // 偏移角随距离增长。
    vec3 oldOffset = vec3(pxOffset, 0.0); // 原始二维偏移抬成三维。
    vec3 rotated = oldOffset * cos(angle) + cross(prep, oldOffset) * sin(angle) + prep * dot(prep, oldOffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 只取二维结果。
}

// 单个彩色光斑：三个颜色通道用略微不同的距离，形成色散边缘。
vec3 ogxLensFlareSpot(vec2 uv, vec2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxLensDistOffset(uv, pos, barrel); // 先做桶形弯曲。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝通道。
    return vec3(r, g, b); // 合成彩色光斑。
}

// 一串小光斑：六层逐渐变小的光斑沿同一条轨迹排开，再补一个大光斑。
vec3 ogxLensOrb(vec2 uv, vec2 pos, float dist, float size, float barrel)
{
    vec3 color = vec3(0.0); // 累加结果。
    const float orbCount = 6.0; // 参考实现的固定层数。
    for (float i = 0.0; i < orbCount; i++) // 逐层累加。
    {
        float j = i + 1.0; // 从第一层开始。
        float offset = j / (j + 0.1); // 沿轨迹的偏移。
        float colorOffset = j / orbCount * 0.5; // 颜色偏移。
        float spotSize = size / (j + 1.0); // 越往后越小。
        color += ogxLensFlareSpot(uv, pos, dist + offset, spotSize * 2.0, spotSize, barrel) * vec3(1.0 - colorOffset, 1.0, 0.5 + colorOffset) * j; // 按层号加权。
    }
    color += ogxLensFlareSpot(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 最外层大光斑。
    return color; // 交回整串光斑。
}

// 环形光斑：用反比曲线给出一圈柔和的色散环。
vec3 ogxLensRing(vec2 uv, vec2 pos, float dist, float chromaOffset, float blur, float barrel)
{
    vec2 uvd = uv * length(uv); // 径向拉长，环才不是正圆。
    pos = ogxLensDistOffset(uv, pos, barrel); // 同样做桶形弯曲。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝通道。
    return vec3(r, g, b); // 合成彩色环。
}

// 镜头光斑与眩光：先按到太阳的屏幕距离算一圈眩光，再叠两层环与多个彩色光斑。
// `lensGlare` 与 `lensFlare` 对应参考实现的两个独立开关，两者可以同时打开。
vec3 ogxLensFlare(vec2 texCoord, vec2 sunCoord, float aspectRatio, float projectionYY, bool lensGlare,
    bool lensFlare, float glareBrightness, float flareBrightness, vec3 colorSunlight, float sunVisibility,
    float vfogDensity, float mainOutputFactor)
{
    vec3 result = vec3(0.0); // 累加结果。
    vec2 coord = texCoord - 0.5; // 以画面中心为原点。
    vec2 sunPos = sunCoord - 0.5; // 太阳的屏幕位置。
    coord.x *= aspectRatio; // 横纵比修正，光斑不会被拉扁。
    sunPos.x *= aspectRatio; // 太阳位置同样修正。
    float fovFactor = max(projectionYY, 2.0); // 视野越大，光斑尺度越大。
    const float barrel = 1.0; // 参考实现的桶形畸变强度。
    if (lensGlare) // 眩光：沿太阳方向的放射状亮纹。
    {
        vec2 v = coord - sunPos; // 到太阳的屏幕向量。
        float dist = length(v); // 距离。
        float glareDist = dist * 13.0 / fovFactor; // 按视野归一化。
        float phase = atan(v.y, v.x) + 0.131; // 方向角加固定相位。
        float glare = 2.0 - clamp(glareDist, 0.0, 1.0) + sin(phase * 12.0) * clamp(glareDist * 2.5 - 0.2, 0.0, 1.0); // 放射条纹。
        glare = glare * glare; // 平方让亮纹更集中。
        glareDist = glareDist * glareDist; // 距离平方。
        glare *= 8e-5 / (glareDist * glareDist); // 反比衰减。
        glare = min(glare, 200.0); // 上限防止爆亮。
        result += vec3(glare * glareBrightness); // 叠到结果。
    }
    if (lensFlare) // 光斑：多层圆斑、环与彩色鬼影。
    {
        float size = 0.5 * fovFactor; // 光斑基准尺寸。
        vec3 flareColor = vec3(0.0); // 光斑累加。
        flareColor += ogxLensOrb(coord, sunPos, 0.0, size * 0.01, barrel) * 0.1; // 主光斑串。
        flareColor += ogxLensRing(coord, sunPos, 1.0, 0.02, 1.4, barrel) * 0.01; // 正向环。
        flareColor += ogxLensRing(coord, sunPos, -1.0, 0.02, 1.4, barrel) * 0.01; // 反向环。
        flareColor += ogxLensFlareSpot(coord, sunPos, -2.00, 0.05, size * 0.05, barrel) * 0.5; // 远端鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.90, 0.02, size * 0.03, barrel) * 0.3; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.70, 0.01, size * 0.06, barrel) * 0.5; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.55, 0.02, size * 0.02, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.35, 0.02, size * 0.04, barrel) * 0.7; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.01, size * 0.15, barrel) * vec3(0.3, 0.4, 0.38); // 彩色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.02, size * 0.08, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.05, 0.01, size * 0.03, barrel) * 0.1; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.30, 0.02, size * 0.20, barrel) * vec3(0.2, 0.18, 0.14); // 暖色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 1.20, 0.03, size * 0.10, barrel) * 0.2; // 远端鬼影。
        result += flareColor * (flareBrightness * 0.3); // 按强度叠到结果。
    }
    result *= colorSunlight * (sunVisibility * clamp(exp2(1.0 - vfogDensity * 20.0), 0.0, 1.0) / mainOutputFactor); // 按阳光与雾衰减。
    return ogxLinearToCurve3(result); // 转回曲线编码。
}

// 自动曝光的 tile 统计：把画面缩到六十四像素一格，逐格算亮度并按距离与夜视加权。
// `aeMode` 与 `luminanceWeightMode` 对应参考实现的对应宏，`caveMode` 与 `dimension` 决定分支。
float ogxGetExposureTiles(sampler2D exposureTexture, int viewWidth, int viewHeight, vec2 screenExtent,
    vec2 pixelSize, float mainOutputFactor, float exposureOutputFactor, int aeMode, int dimension,
    bool aeClamp, bool caveMode, int luminanceWeightMode, float luminanceWeightStrength)
{
    float averageLod = floor(log2(min(viewWidth, viewHeight))); // 按较短边选层级。
    float avg = ogxLuminance(ogxCurveToLinear3(textureLod(exposureTexture, vec2(0.65, 0.65), averageLod).rgb)) * (mainOutputFactor / 128.0); // 整幅画面的平均亮度。
    int lod = 6; // 六十四像素一格的层级。
    float tileScale = exp2(float(lod)); // 一格对应的像素数。
    vec2 tileCount = floor(screenExtent / tileScale); // 横纵格数。
    vec2 tileCenter = tileCount * 0.5; // 画面中心在格坐标里的位置。
    float exposure = 0.0; // 加权曝光累加。
    float weights = 0.0; // 权重累加。
    for (int x = 0; x < int(tileCount.x); x++) // 逐列。
    {
        for (int y = 0; y < int(tileCount.y); y++) // 逐行。
        {
            float tileExposure = ogxLuminance(ogxCurveToLinear3(texelFetch(exposureTexture, ivec2(x, y), lod).rgb)) * (mainOutputFactor / 128.0); // 这一格的亮度。
            vec2 tileDistance = (tileCenter - vec2(x, y) + 0.5) * pixelSize * tileScale * 2.0; // 到中心的归一化距离。
            float centerDistance = length(tileDistance); // 距离。
            float tileWeight = 1.0; // 默认权重。
            if (aeMode == 0 && dimension != 2) tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 主世界与下界按中心加权。
            else if (aeMode == 1) { tileWeight = ogxRemapSaturate(centerDistance, 0.7, 0.0); tileWeight *= tileWeight; } // 中心权重更强。
            else if (aeMode == 2) tileWeight = ogxRemapSaturate(centerDistance, 0.6, 0.4); // 与零模式相同。
            if (aeMode == 3) tileWeight = 1.0; // 全画面平均。
            if (aeClamp) tileExposure = max(6.4e-9, tileExposure); // 防止零亮度。
            if (caveMode && dimension == 0) // 洞穴模式按与平均亮度的比值加权。
            {
                float lumaWeight = avg / tileExposure; // 亮度比。
                tileWeight *= pow(lumaWeight, 0.7); // 暗处权重更高。
            }
            else if (luminanceWeightMode > 0) // 普通亮度加权。
            {
                float lumaWeight = avg / tileExposure; // 亮度比。
                if (luminanceWeightMode == 1) // 模式一。
                {
                    if (dimension == 1) lumaWeight = pow(lumaWeight, 0.7); // 下界固定指数。
                    else if (dimension == 0) lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.7); // 主世界按平均亮度改指数。
                    else lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 末地略缓和。
                }
                else if (luminanceWeightMode == 2) // 模式二。
                {
                    if (dimension == 1) lumaWeight = pow(lumaWeight, 0.7); // 下界固定指数。
                    else lumaWeight = pow(lumaWeight, ogxRemapSaturate(avg, 1.55e-6, 6.25e-8) * 0.5 + 0.2); // 其他维度。
                }
                else if (luminanceWeightMode == 3) lumaWeight = pow(lumaWeight, luminanceWeightStrength); // 固定指数。
                else if (luminanceWeightMode == 4) lumaWeight = pow(tileExposure / avg, luminanceWeightStrength); // 反向权重。
                tileWeight *= lumaWeight; // 乘到格权重。
            }
            exposure += tileExposure * tileWeight; // 累加曝光。
            weights += tileWeight; // 累加权重。
        }
    }
    exposure /= weights; // 加权平均。
    exposure *= exposureOutputFactor; // 输出缩放。
    return ogxLinearToCurve(exposure); // 转回曲线编码。
}

// 曝光值：手动模式直接由 EV 算出，自动模式从曝光统计像素读取并按曲线、夜视与黑暗调整。
float ogxGetExposureValue(sampler2D exposureTexture, ivec2 screenExtent, bool manualExposure, float evValue,
    float mainOutputFactor, float exposureOutputFactor, float aeCurve, float nightVision, bool aeClamp,
    bool dimensionNether, float aeOffset, float darknessFactor, bool disableBlindness)
{
    if (manualExposure) // 手动曝光。
    {
        return 1.5e5 * mainOutputFactor * exp2(-evValue); // 参考实现的固定比例。
    }
    float ae = ogxCurveToLinear(texelFetch(exposureTexture, ivec2(0, screenExtent.y - 1), 0).a) * (5120.0 / exposureOutputFactor); // 统计像素还原。
    if (!disableBlindness) aeCurve = mix(aeCurve, 0.95, nightVision); // 夜视把曲线推平。
    if (aeClamp) aeCurve *= ogxRemapSaturate(ae, 2.0, 1.0) * 0.6 + 0.4; // 极暗时限制曲线。
    if (dimensionNether) aeCurve *= 0.83; // 下界整体压低。
    ae = pow(ae, -aeCurve); // 曲线调整。
    ae *= exp2(aeOffset); // 曝光偏移。
    if (!disableBlindness) ae *= 1.0 - min(darknessFactor * 2.0, 0.9); // 黑暗效果压暗。
    return 8.5 * mainOutputFactor * ae; // 最终曝光。
}

// 合并泛光：按维度、雨幕、视距与雾的可见度算出泛光量，再把模糊后的泛光混进颜色。
// 参考实现用多个宏选分支，这里用显式布尔参数保留同样的分支与常数。
vec3 ogxMergeBloom(vec3 color, float bloomGuide, vec2 texCoord, sampler2D bloomTexture,
    sampler2D gbuffer0, sampler2D gbuffer7, sampler2D depthTex0, sampler2D dhDepthTex0,
    ivec2 texelCoord, int dimension, float bloomAmount, float rainVisibility, float wetness,
    float eyeBrightnessCurved, bool indoorFog, bool underwaterFog, bool vfog, bool vfogBloom,
    float waterFogDensity, float netherFogDensity, float netherEndBloomBoost, vec4 netherBiomes,
    bool hasDh, float farPlane, mat4 projectionInverse, mat4 dhProjectionInverse, bool disableBlindness,
    float blindness, float darknessFactor, sampler2D fogTexture, vec2 taaJitter)
{
    float linearDepth = 0.0; // 线性深度，米。
    float rainAlpha = 0.0; // 雨幕透明度。
    if (dimension == 0) // 主世界。
    {
        rainAlpha = 1.0 - texelFetch(gbuffer0, texelCoord, 0).a; // 第一张缓冲记录雨幕。
        rainAlpha *= rainVisibility; // 按可见度缩放。
        float depth = texelFetch(depthTex0, texelCoord, 0).x; // 屏幕深度。
        linearDepth = ogxShadowLinearDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxShadowLinearDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
    }
    else if (dimension == 1) // 下界。
    {
        linearDepth = ogxShadowLinearDepth(ogxUnpack2x16(texelFetch(gbuffer7, texelCoord, 0).a).x, projectionInverse); // 第七张缓冲打包线性深度。
        if (!hasDh) linearDepth = min(linearDepth, farPlane); // 没有远景时限制到远平面。
    }
    else // 末地。
    {
        float depth = texelFetch(depthTex0, texelCoord, 0).x; // 屏幕深度。
        linearDepth = ogxShadowLinearDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxShadowLinearDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
    }
    vec3 bloom = ogxCurveToLinear3(textureLod(bloomTexture, texCoord * 0.5, 0.0).rgb); // 半分辨率泛光图。
    float amount = bloomAmount; // 泛光量。
    if (dimension == 2) amount *= 0.5 * netherEndBloomBoost + 1.0; // 末地增强。
    if (dimension == 1) // 下界按群系提高雾与泛光。
    {
        float biomeOffset = netherBiomes.x * 1.0;
        biomeOffset += netherBiomes.y * 0.75; // 绯红森林。
        biomeOffset += netherBiomes.z * 0.25; // 诡异森林。
        biomeOffset += netherBiomes.w * 0.5; // 玄武岩三角洲。
        biomeOffset = biomeOffset * netherEndBloomBoost + 1.0; // 按增强倍率缩放。
        float fogDensity = 0.008 * biomeOffset * netherEndBloomBoost * netherFogDensity; // 群系雾密度。
        if (underwaterFog) fogDensity = 0.7; // 水下固定浓雾。
        float visibility = 1.0 / exp2(linearDepth * fogDensity); // 可见度。
        float fogFactor = 1.1 - visibility; // 雾造成的泛光。
        fogFactor *= bloomGuide; // 按泛光引导缩放。
        amount = max(amount * biomeOffset, min(fogFactor, 0.92)); // 取较大者并封顶。
    }
    else // 主世界与末地。
    {
        float fogDensity = float(underwaterFog) * 0.7; // 水下雾。
        if (underwaterFog) fogDensity = float(waterFogDensity > 0.0) * 0.07 * waterFogDensity; // 参考实现的水下密度。
        float visibility = 1.0 / exp2(linearDepth * fogDensity); // 可见度。
        float fogFactor = 1.1 - visibility; // 雾泛光。
        fogFactor *= bloomGuide; // 按引导缩放。
        amount = max(amount, fogFactor); // 取较大者。
    }
    if (dimension == 0) // 主世界的雨幕与雾泛光。
    {
        float rainBloomAmount = wetness * (indoorFog ? 0.35 : (0.2 * eyeBrightnessCurved + 0.15)); // 雨天泛光。
        rainBloomAmount = clamp(rainBloomAmount + rainAlpha * 0.2, 0.0, 1.0); // 加上雨幕。
        amount = max(amount, rainBloomAmount); // 取较大者。
        if (vfog && !vfogBloom) amount = max(amount, 0.0); // 保留分支位置。
        if (vfog && vfogBloom) // 体积雾的泛光。
        {
            float fogTransmittance = textureLod(fogTexture, texCoord + taaJitter * 0.5, 0.0).a * bloomGuide; // 雾的透过率。
            amount = max(amount, fogTransmittance); // 取较大者。
        }
    }
    if (!disableBlindness) amount *= 1.0 - blindness - darknessFactor; // 黑暗与失明压暗泛光。
    return mix(color, bloom, clamp(amount, 0.0, 1.0)); // 混合泛光。
}

// FXAA：按四邻域亮度梯度找边缘方向，再沿边缘取四个样本做抗锯齿。
vec3 ogxFxaa(vec3 rgbM, vec2 coord, vec2 pixelSize, sampler2D colorTexture)
{
    const float reduceMin = 1.0 / 64.0; // 最小梯度。
    const float reduceMul = 1.0 / 8.0; // 梯度缩放。
    const float spanMax = 16.0; // 最大搜索跨度。
    vec3 rgbNW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, -0.5), 0.0).xyz; // 左上。
    vec3 rgbNE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, -0.5), 0.0).xyz; // 右上。
    vec3 rgbSW = textureLod(colorTexture, coord + pixelSize * vec2(-0.5, 0.5), 0.0).xyz; // 左下。
    vec3 rgbSE = textureLod(colorTexture, coord + pixelSize * vec2(0.5, 0.5), 0.0).xyz; // 右下。
    vec3 luma = vec3(0.299, 0.587, 0.114); // 亮度权重。
    float lumaNW = dot(rgbNW, luma); // 左上亮度。
    float lumaNE = dot(rgbNE, luma); // 右上亮度。
    float lumaSW = dot(rgbSW, luma); // 左下亮度。
    float lumaSE = dot(rgbSE, luma); // 右下亮度。
    float lumaM = dot(rgbM, luma); // 中心亮度。
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE))); // 最小亮度。
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE))); // 最大亮度。
    vec2 dir; // 边缘方向。
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * reduceMul), reduceMin); // 方向衰减。
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce); // 方向归一化。
    dir = min(vec2(spanMax, spanMax), max(vec2(-spanMax, -spanMax), dir * rcpDirMin)) * pixelSize; // 限制跨度并换成像素。
    vec3 rgbA = (1.0 / 2.0) * (textureLod(colorTexture, coord + dir * vec2(1.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(2.0 / 3.0 - 0.5), 0.0).xyz); // 内侧两点。
    vec3 rgbB = rgbA * (1.0 / 2.0) + (1.0 / 4.0) * (textureLod(colorTexture, coord + dir * vec2(0.0 / 3.0 - 0.5), 0.0).xyz
        + textureLod(colorTexture, coord + dir * vec2(3.0 / 3.0 - 0.5), 0.0).xyz); // 外侧两点。
    float lumaB = dot(rgbB, luma); // 外侧亮度。
    if ((lumaB < lumaMin) || (lumaB > lumaMax)) return rgbA; // 外侧落在亮度范围外就用内侧。
    return rgbB; // 否则用更宽的平均。
}

// 远景地形噪点：按楼层量化坐标，再按亮度与材质给一个可正可负的亮度扰动。
vec3 ogxDhNoise(vec3 color, vec3 pos, float materialIDs, int leafId, float steps, float strength)
{
    pos = floor(pos * steps) / steps; // 坐标量化到固定楼层，远景纹素不会闪烁。
    float weight = ogxLuminance(color) * 2.0 - 1.0; // 亮度映射到负一到一。
    weight = 1.0 - weight * weight; // 中间亮度权重最大。
    weight *= float(materialIDs == float(leafId)) + 1.0; // 树叶噪点更强。
    weight *= strength; // 整体强度。
    float noise = fract(sin(dot(pos.xy + fract(sin(pos.z * 91.3458) * 47453.5453), vec2(12.9898, 78.233))) * 43758.5453); // 一维哈希。
    noise = (noise * 2.0 - 1.0) * weight; // 转成负一到一。
    return clamp(color - color * noise, 0.0, 1.0); // 按噪点压暗或提亮。
}

// 末地传送门层：每层一个旋转、缩放与平移，叠出会流动的传送门纹理。
mat4 ogxEndPortalLayer(float layer, float timeSeconds)
{
    mat4 translate = mat4(1.0, 0.0, 0.0, 17.0 / layer,
                                  0.0, 1.0, 0.0, (2.0 + layer / 1.5) * (timeSeconds * 0.0005),
                                  0.0, 0.0, 1.0, 0.0,
                                  0.0, 0.0, 0.0, 1.0); // 每层不同的平移。
    float angle = radians((layer * layer * 4321.0 + layer * 9.0) * 2.0); // 每层不同的旋转角。
    float s = (4.5 - layer / 4.0) * 2.0; // 与参考实现相同的均匀缩放。
    mat4 scaleRotate = mat4(s * cos(angle), -s * sin(angle), 0.0, 0.0,
                                    s * sin(angle), s * cos(angle), 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 0.0, 0.0, 1.0); // 按列填写的缩放旋转矩阵。
    mat4 uvScaleTranslate = mat4(0.5, 0.0, 0.0, 0.25,
                                         0.0, 0.5, 0.0, 0.25,
                                         0.0, 0.0, 1.0, 0.0,
                                         0.0, 0.0, 0.0, 1.0); // 贴图坐标从零到一压到四分之一到四分之三。
    mat4 scaledTranslate; // 缩放旋转乘平移。
    mat4 result; // 再乘贴图缩放。
    for (int column = 0; column < 4; column++) // 逐列展开矩阵乘法。
    {
        for (int row = 0; row < 4; row++) // 逐行点积。
        {
            scaledTranslate[column][row] = scaleRotate[0][row] * translate[column][0] + scaleRotate[1][row] * translate[column][1]
                + scaleRotate[2][row] * translate[column][2] + scaleRotate[3][row] * translate[column][3]; // 第一段乘积。
            result[column][row] = scaledTranslate[0][row] * uvScaleTranslate[column][0] + scaledTranslate[1][row] * uvScaleTranslate[column][1]
                + scaledTranslate[2][row] * uvScaleTranslate[column][2] + scaledTranslate[3][row] * uvScaleTranslate[column][3]; // 第二段乘积。
        }
    }
    return result; // 参考实现的乘法顺序。
}

// 各向异性采样：按屏幕导数构造椭圆核，沿长轴取多个样本做过滤，避免斜视时贴图糊成一片。
// `quality` 是每像素样本数，`normalSpecular` 为真时同时过滤法线与材质图。
vec4 ogxSampleAnisotropic(sampler2D tex, sampler2D normals, sampler2D specular, vec2 coord, vec2 duv1,
    vec2 duv2, vec2 atlasSize, float textureResolution, int quality, bool normalSpecular, bool useNormalMap,
    bool useSpecularMap, inout vec3 normalTex, inout vec4 specularTex)
{
    vec2 atlasTiles = atlasSize / textureResolution; // 一张贴图在 atlas 里占几格。
    vec2 tilesCoord = coord * atlasTiles; // 换到格坐标。
    mat2 qd = inverse(mat2(dFdx(tilesCoord), dFdy(tilesCoord))); // 屏幕导数矩阵的逆。
    qd = transpose(qd) * qd; // 逆矩阵的转置乘自身，得到椭圆核。
    float d = determinant(qd); // 行列式。
    float t = (qd[0][0] + qd[1][1]) * 0.5; // 迹的一半。
    float D = sqrt(abs(t * t - d)); // 判别式。
    float V = t - D; // 短轴。
    float v = t + D; // 长轴。
    vec2 A = vec2(-qd[0][1], qd[0][0] - V); // 长轴方向。
    A *= inversesqrt(V * dot(A, A) + 1e-20); // 归一化，避免除零。
    float lod = log2(inversesqrt(v) * textureResolution); // 采样层级由长轴决定。
    float steps = float(quality); // 样本数。
    float rSteps = 1.0 / float(quality); // 样本数倒数。
    A *= rSteps; // 每步的偏移。
    vec4 albedoSample = vec4(0.0); // 颜色累加。
    vec3 normalSample = vec3(0.0); // 法线累加。
    vec4 specularSample = vec4(0.0); // 材质累加。
    vec2 tilesBaseCoord = floor(tilesCoord); // 当前格。
    for (float i = 0.5 - steps * 0.5; i < steps * 0.5; i++) // 沿长轴逐样本。
    {
        vec2 sampleCoord = i * A; // 当前偏移。
        sampleCoord = (tilesBaseCoord + fract(tilesCoord + sampleCoord)) / atlasTiles; // 回到贴图坐标并保持在格内。
        vec4 sampleAlbedo = textureLod(tex, sampleCoord, lod); // 取颜色。
        albedoSample += vec4(sampleAlbedo.rgb * sampleAlbedo.a, sampleAlbedo.a); // 预乘透明度累加。
        if (normalSpecular) // 同时过滤法线与材质。
        {
            if (useNormalMap) normalSample += textureLod(normals, sampleCoord, lod).rgb * sampleAlbedo.a; // 法线按透明度加权。
            if (useSpecularMap) specularSample += textureLod(specular, sampleCoord, lod) * sampleAlbedo.a; // 材质按透明度加权。
        }
    }
    float weights = 1.0 / albedoSample.a; // 透明度总和倒数。
    if (normalSpecular) // 写回法线与材质。
    {
        if (useNormalMap) normalTex = ogxDecodeNormalTex(normalSample * weights); // 解出切线法线。
        if (useSpecularMap) specularTex = specularSample * weights; // 材质取加权平均。
    }
    else // 不过滤附加图时用梯度采样保持层级正确。
    {
        if (useNormalMap) normalTex = ogxDecodeNormalTex(textureGrad(normals, coord, duv1, duv2).rgb); // 法线用梯度采样。
        if (useSpecularMap) specularTex = textureGrad(specular, coord, duv1, duv2); // 材质用梯度采样。
    }
    return vec4(albedoSample.rgb * weights, textureLod(tex, coord, 0.0).a); // 颜色取平均，透明度保留原值。
}

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

// 陆地大气散射：沿视线取一段空气，按高度密度与阴影长度算出附加的天空散射。
// `landStrength`、`distanceScale` 与阴影质量由调用方传入，其余大气常数来自模型。
vec3 ogxLandAtmosphericScattering(OgxAtmosphereModel model, vec3 color, float dist, vec3 startPos,
    vec3 endPos, vec3 worldDir, bool isSky, float landStrength, bool vfog, float timeNoon,
    float eyeBrightness, bool indoorFog, vec3 cameraWorldPos, float minAltitude, bool atmoHorizon,
    bool landscapeShadow, int shadowQuality, vec3 worldSunVector, float bayerNoise,
    mat4 shadowView, mat4 shadowProjection, sampler2D shadowTexture, float distanceScale,
    float wetness, bool overworld)
{
    float strength = max(landStrength - float(isSky), 0.0); // 天空像素不额外加陆地散射。
    if (vfog) strength *= timeNoon; // 体积雾开启时只在白天加。
    if (!indoorFog) strength *= eyeBrightness; // 室内按眼睛亮度淡出。
    if (strength > 0.001 && overworld) // 只有主世界且强度足够时才计算。
    {
        float altitude = atmoHorizon ? max(cameraWorldPos.y, minAltitude) * 0.001 + model.bottom_radius
                                     : max(cameraWorldPos.y, 63.0) * 0.001 + model.bottom_radius; // 相机在大气里的半径。
        vec3 camera = vec3(0.0, altitude, 0.0); // 参考实现把相机放在竖直轴上。
        float shadowDist = dist; // 阴影长度初值。
        if (landscapeShadow) // 开启阴影时沿阴影图采样。
        {
            float rSteps = 1.0 / float(shadowQuality); // 采样数倒数。
            vec3 shadowStart = ogxShadowScreenPos(startPos, shadowView, shadowProjection); // 起点投到阴影图。
            vec3 shadowEnd = ogxShadowScreenPos(endPos, shadowView, shadowProjection); // 终点投到阴影图。
            float noise = bayerNoise; // 抖动。
            vec3 shadowIncrement = (shadowEnd - shadowStart) * rSteps; // 每步增量。
            vec3 shadowRayPosition = shadowIncrement * noise + shadowStart; // 起点加抖动。
            float shadowLength = 0.0; // 被遮挡的样本数。
            for (int i = 0; i < shadowQuality; i++) // 沿阴影图采样。
            {
                vec3 shadowPos = shadowRayPosition; // 当前采样。
                shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, 0.9); // 补边缘压缩。
                if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 落在图内。
                {
                    float solidDepth = textureLod(shadowTexture, shadowPos.xy, 0.0).x; // 读遮挡深度。
                    shadowLength += step(solidDepth, shadowPos.z); // 遮挡计数。
                }
                shadowRayPosition += shadowIncrement; // 前进。
            }
            shadowDist = max(shadowDist - shadowLength * length((endPos - startPos) * rSteps), 0.0); // 按遮挡比例缩短。
        }
        dist *= distanceScale; // 距离缩放。
        shadowDist *= distanceScale; // 阴影距离同样缩放。
        vec3 scattering = ogxAtmoSimpleScattering(model, camera, worldDir, dist, shadowDist, worldSunVector); // 大气单次散射。
        color += scattering * (1.0 - wetness) * strength; // 雨天压低陆地散射。
    }
    return color; // 交回叠加后的颜色。
}

#endif
