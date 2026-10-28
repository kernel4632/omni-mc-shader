/*
水面子文件：水洼覆盖、雨点高光、水下雾、雨纹动画、波纹法线与焦散。
调用位置：由 `water.slang` 内联，水面、雨天与水下效果调用这里的入口。
可复制示例：`float p = ogxPuddleCoverage(halfWet, noise, size);`
设计原因与取舍：湿度、噪声与时间显式传入，纹理由调用方绑定；雨量与参考常数保持一致。
*/
// 水洼覆盖：只有湿度超过噪声阈值的地方才积水，五次方让边缘收得很快。
float ogxPuddleCoverage(float halfWet, float noise, float size)
{
    float puddles = max(halfWet - noise, 0.0); // 只算湿度超过噪声阈值的部分。
    puddles = clamp(halfWet - exp(-25.0 * puddles * puddles * puddles * puddles * puddles * size), 0.0, 1.0); // 指数衰减得到积水比例。
    return puddles; // 返回零到一的积水覆盖。
}

// 降水高光：三层噪声叠出雨点打在物体表面的细碎高光。
float ogxRainSpecular(float3 pos, Sampler2D noiseTexture)
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
float3 ogxWaterFog(float3 color, float3 viewDir, float opaqueDist, float waterDist, float3 normal,
    float ice, float stainedGlass, float hand, float occludedWater, float waterSkylight, float totalInternal,
    float3 lightDir, float3 lightColor, float3 skyColor, float3 upView, float eyeWaterDepth, float wetness,
    float refractIor, float fogDensityOption, bool underwater)
{
    float distDiff = opaqueDist - waterDist; // 水面到水底的真实距离。
    waterDist = underwater ? lerp(waterDist, opaqueDist, stainedGlass) : lerp(distDiff, min(distDiff * 0.3, 6.0), occludedWater); // 按遮挡与玻璃修正厚度。
    waterDist = max(waterDist, totalInternal * eyeWaterDepth * 50.0); // 全反射时按眼睛水深拉长光程。
    float3 shadowRefracted = refract(-lightDir, upView, 1.0 / refractIor); // 太阳经过水面的折射方向。
    float3 fogColor = lerp(float3(0.05, 0.6, 1.0), float3(0.3, 0.9, 1.5), ice); // 冰偏青，普通水偏蓝。
    fogColor = lerp(fogColor, float3(0.5), wetness * 0.6); // 越湿颜色越灰。
    fogColor *= dot(float3(0.33333), skyColor); // 水雾颜色随环境色变化。
    if (!underwater) // 水面之上看水下。
    {
        fogColor *= 0.04 - wetness * 0.032; // 水面之上的散射只占很小一部分。
        fogColor *= waterSkylight; // 再乘该处水面的天光。
        float3 l = normalize(reflect(viewDir, normal)); // 视线在水面的反射方向。
        float3 h = normalize(l - viewDir); // 反射方向与视线的半程。
        float fresnel = ogxSaturate(dot(normal, l)) * ogxSaturate(dot(l, h) * 1.5 - 0.5); // 简化的反射权重。
        float scatter = 3.0 * fresnel * pow(dot(shadowRefracted, viewDir) * 5.0 + 5.2, -1.4); // 逆光时的散射强度。
        fogColor = lerp(fogColor, lightColor * fogColor * 3.0, scatter * ogxSaturate(1.0 - wetness - occludedWater)); // 按散射叠进光色。
    }
    else // 眼睛在水里。
    {
        fogColor *= 0.02 - wetness * 0.012; // 水下的散射更暗。
        float scatter = 1.0 / (dot(shadowRefracted, viewDir) * 5.0 + 5.1); // 水下的前向散射。
        float3 sunScatter = lightColor * scatter * fogColor * 2.0; // 太阳在水下的散射色。
        fogColor *= dot(viewDir, upView) * 0.4 + 0.6; // 向上看更亮。
        fogColor += sunScatter * (eyeWaterDepth * (1.0 - wetness * 0.6)); // 加上太阳散射。
    }
    float density = underwater ? ice * 0.96 + 0.04 : 0.29; // 水下密度更高。
    float visibility = exp2(-waterDist * density * fogDensityOption); // 按光程指数衰减得到可见度。
    visibility = clamp(visibility, 0.35 * ice, 1.0); // 冰给出一个可见度下限。
    visibility = lerp(visibility, 0.7, hand); // 手里的东西只受轻微影响。
    float3 attenuation = underwater ? float3(0.1, 0.6, 1.0) : float3(0.2, 0.5, 0.7); // 分通道衰减色，水底偏蓝。
    color *= pow(attenuation * 0.99, float3(waterDist * (0.21 * float(!underwater) + 0.04) * fogDensityOption)); // 按光程衰减，长波先掉。
    return lerp(fogColor, color, visibility); // 用可见度在水雾色与场景色之间混合。
}

// 波法线方块读取：把世界位置按折射方向投到七号画面左下角的波法线方块，解出世界空间法线。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
float3 ogxWavesNormalFromTex(float3 position, float3 lightDir, Sampler2D normalTexture, float2 pixelSize,
    float2 screenExtent, float maxResolution, float refractIor)
{
    float3 refracted = refract(lightDir, float3(0.0, 1.0, 0.0), 1.0 / refractIor); // 阳光按水面折射率弯折。
    float2 coord = position.xz; // 先取水平坐标。
    coord.x += position.y * refracted.x / refracted.y; // 按高度沿光线横移横坐标。
    coord.y += position.y * refracted.z / refracted.y; // 按高度沿光线横移纵坐标。
    coord *= 0.02; // 缩到波法线图的空间尺度。
    coord = fract(coord); // 平铺到零到一。
    coord *= pixelSize * min(screenExtent.y, maxResolution); // 折算成方块里的像素坐标。
    return ogxDecodeNormal(normalTexture.SampleLevel(coord, 0.0).xy); // 从方块里读八面体编码法线。
}

// 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
// `cameraOffset` 用来还原绝对世界坐标，`underwater` 决定是否往全亮靠。
float ogxWaterCaustics(float3 worldPos, float3 lightDir, float3 cameraOffset, Sampler2D normalTexture,
    float2 pixelSize, float2 screenExtent, float maxResolution, float refractIor, float2 dither,
    bool underwater, float brightness, float power)
{
    float3 position = worldPos + cameraOffset; // 换成绝对世界坐标。
    float3 lookupCenter = position + float3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。
    float caustics = 0.0; // 累计焦散强度。
    const float causticsStart = -1.0; // 三乘三采样从负一开始，保留参考的循环下界常数。
    for (float i = causticsStart; i <= 1.0; i++) // 三乘三抖动采样。
    {
        for (float j = -1.0; j <= 1.0; j++)
        {
            float2 offset = dither + float2(i, j); // 当前采样偏移。
            float3 lookupPoint = lookupCenter; // 这一处的波面查询点。
            lookupPoint.xz += offset * 0.1; // 按偏移横移。
            float3 wavesNormal = ogxWavesNormalFromTex(lookupPoint, lightDir, normalTexture, pixelSize,
                screenExtent, maxResolution, refractIor).xzy; // 读取波法线并换到竖直轴朝上的坐标。
            float3 refractVector = refract(float3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
            float3 collision = lookupPoint - refractVector / refractVector.y; // 光线与水平面的交点。
            collision -= position; // 相对当前位置。
            float dist = dot(collision, collision) * 7.1; // 交点距离的平方，放大差距。
            caustics += 1.0 - ogxSaturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
        }
    }
    float finalCaustics = lerp(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(underwater)); // 拼成焦散亮度，水下再往全亮靠一点。
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
