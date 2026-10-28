/* 层状体积云的光照：相函数、朝光散射与单次散射合成；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`float phase = ogxLayersPhaseCloud(0.5, 0.8, 0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 云的相函数：按 `mode` 选择 Henyey-Greenstein、Cornette-Shanks 或 HG-Draine。
// 按云相位模式组合前向与背向散射，决定云边缘的透光方向。
float ogxLayersPhaseCloud(float x, float g, int mode) // 当前步骤的中间量。
{ // 按参考顺序推进。
    // 模式一用 Cornette-Shanks：比默认多一个前向峰，适合太阳附近的银边；模式二用 Draine 近似。
    if (mode == 1) // Cornette-Shanks。
    { // 按参考顺序推进。
        return (3.0 * (1.0 - g * g) * (1.0 + x * x)) / (25.133 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * x, 1.5)); // 参考实现系数 25.133。
    }
    if (mode == 2) // HG-Draine。
    {
        const float a = 0.9; // 前向权重。
        float gg = g * g; // g 的平方。
        return ((1.0 - gg) * (1.0 + a * x * x)) / (4.0 * (1.0 + (a * (1.0 + 2.0 * gg)) / 3.0) * 3.1415926 * pow(1.0 + gg - 2.0 * g * x, 1.5)); // 参考实现公式。
    }
    float gg = g * g; // 默认 Henyey-Greenstein。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现除以 3.14。
}

// 朝光散射：沿光方向取几步云密度，层数与步长按层号决定。
// 云层散射为什么只取少量步长：云体内部没有细节几何，遮挡是连续的密度函数，
// 四到六步已经能把整层走完；步长随光源方向与层厚变化，近处细、远处粗。
// 相位按层选择：积云用前向集中的 HG，高层云用更平的 Cornette-Shanks，
// 积雨云再叠一份宽相位，避免闪电照亮时整块云一起发白。
float ogxLayersGetCloudScattering(OgxLayersCloudSettings s, int layerIndex, float3 rayPosition, float3 sunVector,
    float3 moonVector, float dither, float minHeight, float maxHeight, float density, float cumulonimbusScale,
    float sunVisibility, float moonVisibility, float3 cameraPos, Sampler2D noiseTexture)
{
    int samples = 3; // 默认三步。
    if (layerIndex == 2) samples = 7; // 积雨云七步。
    if (layerIndex == 3 || layerIndex == 4) samples = 2; // 高层云与卷云两步。
    int lod = 0; // 光照取样用低细节。
    float shadow = 0.0; // 遮挡累加。
    float3 shadowRayPosition = float3(0.0); // 采样位置。
    float isLarge = 80.0; // 积雨云步长。
    float3 lightVec = normalize(lerp(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (layerIndex == 3 || layerIndex == 4) // 平面云沿日月方向。
        {
            // 向太阳采样时用两百米级步长，云层很厚，细步长只会增加采样数而不改遮挡形状。
            shadowRayPosition = rayPosition + sunVector * sunVisibility * (0.25 + float(i) * dither) * 200.0
                + moonVector * moonVisibility * (0.25 + float(i) * dither) * 200.0; // 沿日月方向取样。
        }
        else if (layerIndex == 0 || layerIndex == 1) // 积云沿混合方向。
        {
            // 月亮方向用小步长，月光弱、云影边缘更容易看出层叠，细采样能保住柔边。
            shadowRayPosition = rayPosition + lightVec * (0.25 + float(i) + dither) * 20.0; // 小步长。
        }
        else if (layerIndex == 2) // 积雨云大步长。
        {
            // 积雨云用大步长，云体尺度大，二十米级步长足够穿过整层而不产生条带。
            shadowRayPosition = rayPosition + lightVec * (0.5 + float(i) + dither) * isLarge; // 大步长。
            isLarge *= 1.374; // 每步放大。
        }
        if (layerIndex != 2) shadow += ogxLayersGetCloudShape(s, layerIndex, lod, shadowRayPosition, minHeight, maxHeight, noiseTexture) * density; // 普通云。
        else shadow += ogxLayersGetCumulonimbusShape(s, lod, shadowRayPosition, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x * density; // 积雨云。
    }
    return shadow; // 交回遮挡量。
}

// 云的光照：直射按 Beer 定律衰减，前后散射按粉末效应插值，间接光按形状抬升。
// 云的单次散射颜色：直射、天光、阴影与相位共同决定云的明暗。
float3 ogxLayersGetCloudLighting(int layerIndex, float shape, float shapeFaded, float sunShadowMask, float3 directLightCol,
    float3 directLightCol2, float indirectShadowMask, float3 indirectLightCol, float3 rayPosition, float backScatterPhase,
    float4 phaseLevels, float backScatterPhase2, float4 phaseLevels2)
{
    float3 heightScal = float3(lerp(1.0, 0.5, clamp(rayPosition.y, 0.0, 7000.0) / 7000.0)); // 高度对光色的压缩。
    directLightCol = pow(directLightCol, heightScal); // 直射颜色按高度压暗。
    directLightCol2 = pow(directLightCol2, heightScal); // 第二直射同样。
    // Beer 系数负四：参考实现的消光强度，绝对值越大云越不透光。
    float beerCoef = -4.0; // Beer 系数。
    float powder = min(exp(beerCoef * exp(beerCoef * shapeFaded)) * 3.5, 1.0); // 粉末效应。
    float backscatter = powder * backScatterPhase; // 后向散射。
    float forwardscatter = lerp(lerp(phaseLevels.x, phaseLevels.y, powder), lerp(phaseLevels.z, phaseLevels.w, powder), powder); // 四档相函数插值。
    float backscatter2 = powder * backScatterPhase2; // 第二后向。
    float forwardscatter2 = lerp(lerp(phaseLevels2.x, phaseLevels2.y, powder), lerp(phaseLevels2.z, phaseLevels2.w, powder), powder); // 第二前向。
    float expBeer = 6.28 * exp((beerCoef - 1.0) * sunShadowMask); // 直射透过率。
    float3 directScattering = expBeer * directLightCol * (forwardscatter + backscatter); // 太阳直射。
    directScattering += expBeer * directLightCol2 * (forwardscatter2 + backscatter2); // 月亮直射。
    // 间接光按形状指数衰减，再按遮蔽掩码平方混合；平方让薄云保留更多环境光。
    float3 indirectScattering = indirectLightCol * lerp(1.0, exp2(-5.0 * shape), indirectShadowMask * indirectShadowMask); // 间接光。
    return indirectScattering + directScattering; // 合成。
}

// 层状云相函数：Henyey-Greenstein 单峰前向散射，`g` 是各向异性，`x` 是夹角余弦。
// 为什么单列一条：参考默认只启用这一种相位，带类型开关的旧实现会多出其它模型的常数。
float ogxLayersPhaseCloudHenyey(float g, float x)
{
    return ogxHenyeyGreensteinPhase(x, g, 1.0 / 3.14); // 参考原式直接写 3.14。
}

// 层状云内散射：沿太阳或月亮方向取几个云形状样本，累加成透过率。
// 参考签名是层号、位置、日月方向、日月高度、抖动与密度；云层上下界与噪声等显式追加。
// 为什么保留循环：采样次数由层号决定，参考也保留运行期循环，合并会改变采样顺序。
float ogxLayersCloudScatteringSamples(int layerIndex, float3 rayPosition, float3 sunVector, float3 moonVector,
    float sunElevation, float moonElevation, float dither, float density,
    float minHeight, float maxHeight, Sampler2D noiseTexture, float3 cameraWorldPos,
    float cloudMovement, float rainAmount, float thunderStrength, float cumulonimbusStrength,
    float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage)
{
    int samples = 3; // 普通层三步。
    int lod = 0; // 阴影只取低细节。
    if (layerIndex == 2) samples = 7; // 积雨云更厚，多取几步。
    if ((layerIndex == 3) || (layerIndex == 4)) samples = 2; // 高层云很薄，两步够用。
    float shadow = 0.0; // 累积的云密度。
    float3 shadowRayPosition = float3(0.0); // 采样位置。
    float sunVis = smoothstep(-0.06, 0.01, sunElevation); // 太阳在地平线附近时逐渐变弱。
    sunVis = sunVis * sunVis;
    float moonVis = smoothstep(0.0, 0.075, -moonElevation); // 月亮同样处理。
    moonVis = moonVis * moonVis;
    moonVis *= smoothstep(0.06, -0.06, sunElevation); // 太阳升起后月亮光退场。
    float isLarge = 80; // 积雨云步长。
    float3 lightVec = normalize(lerp(moonVector, sunVector, smoothstep(-0.06, 0.06, sunElevation))); // 日月方向按太阳高度混合。
    for (int i = 0; i < samples; i++)
    {
        if ((layerIndex == 3) || (layerIndex == 4))
        {
            shadowRayPosition = rayPosition + sunVector * sunVis * (0.25 + i * dither) * 200.0 + moonVector * moonVis * (0.25 + i * dither) * 200.0; // 高层云沿日月方向短步进。
        }
        else if ((layerIndex == 1) || (layerIndex == 0))
        {
            shadowRayPosition = rayPosition + lightVec * (0.25 + i + dither) * 20.0; // 积云二十米一步。
        }
        else
        {
            shadowRayPosition = rayPosition + lightVec * (0.5 + i + dither) * isLarge; // 积雨云按大范围步长。
        }
        if (layerIndex != 2)
        {
            shadow += ogxLayersCloudShapeLayer(layerIndex, lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                rainAmount, thunderStrength, cloudMovement) * density; // 普通云层取形状。
        }
        else
        {
            shadow += ogxLayersCumulonimbusShapeLayer(lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x * density; // 积雨云取形状。
            isLarge *= 1.374; // 每步再拉远，减少远处重复采样。
        }
    }
    return shadow; // 交回云内遮挡量。
}
