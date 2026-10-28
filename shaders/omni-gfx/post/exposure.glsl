/*
生成文件：曝光与泛光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库后期曝光模块：自动曝光分块统计、曝光值与泛光合并。
调用位置：合成与最终画面程序；由 `/omni-gfx/post/exposure.glsl` 引入。
可复制示例：
    float ev = ogxGetExposureValue(exposureTex, screenExtent, false, 0.0, 1.0, 1.0, 1.0, 0.0, true, false, 0.0, 0.0, true); // 取自动曝光值。
设计原因与取舍：
    分块统计、测光权重与泛光量都按参考实现的分支保留；纹理、屏幕尺寸、维度与天气全部改成显式参数。
当前状态：由 `shaders/effects/color/color.glsl` 引入并编译；宿主曝光统计与曝光值调用 `ogxGetExposureTiles` 与 `ogxGetExposureValue`。
*/
#ifndef OGX_POST_EXPOSURE_INCLUDED
#define OGX_POST_EXPOSURE_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "/omni-gfx/shadow/shadow.glsl"
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
// 自动曝光取值：从统计纹理中读分块亮度，按测光模式合成曝光值。
// `disableNightVision` 与 `disableBlindness` 分开，因为宿主的两个调试开关互不影响。
float ogxGetExposureValue(sampler2D exposureTexture, ivec2 screenExtent, bool manualExposure, float evValue,
    float mainOutputFactor, float exposureOutputFactor, float aeCurve, float nightVision, bool aeClamp,
    bool dimensionNether, float aeOffset, float darknessFactor, bool disableNightVision, bool disableBlindness)
{
    if (manualExposure) // 手动曝光。
    {
        return 1.5e5 * mainOutputFactor * exp2(-evValue); // 参考实现的固定比例。
    }
    float ae = ogxCurveToLinear(texelFetch(exposureTexture, ivec2(0, screenExtent.y - 1), 0).a) * (5120.0 / exposureOutputFactor); // 统计像素还原。
    if (!disableNightVision) aeCurve = mix(aeCurve, 0.95, nightVision); // 夜视把曲线推平。
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
        linearDepth = ogxLinearDepthFromScreenDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxLinearDepthFromScreenDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
    }
    else if (dimension == 1) // 下界。
    {
        linearDepth = ogxLinearDepthFromScreenDepth(ogxUnpack2x16(texelFetch(gbuffer7, texelCoord, 0).a).x, projectionInverse); // 第七张缓冲打包线性深度。
        if (!hasDh) linearDepth = min(linearDepth, farPlane); // 没有远景时限制到远平面。
    }
    else // 末地。
    {
        float depth = texelFetch(depthTex0, texelCoord, 0).x; // 屏幕深度。
        linearDepth = ogxLinearDepthFromScreenDepth(depth, projectionInverse); // 换成米。
        if (hasDh && depth == 1.0) linearDepth = ogxLinearDepthFromScreenDepth(texelFetch(dhDepthTex0, texelCoord, 0).x, dhProjectionInverse); // 天空像素读远景。
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

#endif
