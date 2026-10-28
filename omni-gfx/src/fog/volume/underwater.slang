/* 水下体积雾：焦散取样与光柱步进，输出汇聚的蓝色光柱；由 `fog/volume.slang` 内联引入。
可复制示例：`float3 light = ogxUnderwaterFog(startPos, endPos, worldDir, cloudShadow, ...);`
设计取舍：光柱截断到四十米内；焦散三次方让亮纹更集中，远处按距离变弱。 */

// 水下焦散：从当前位置向上找水面，按波法线折射后取交点距离，距离越近光柱越强。
// 为什么单独一份：它与水面焦散的三乘三采样用途不同，这里只要一份范围很窄的值来收窄光柱。
float ogxUnderwaterCaustics(float3 worldPos, float3 shadowLightVector, Sampler2D normalTexture,
    float2 pixelSize, float2 screenExtent, float maxResolution, float refractIor)
{
    float3 lookupCenter = worldPos; // 从当前位置向上找波面。
    lookupCenter.y += 1.0; // 抬高一米到水面上方。
    float3 wavesNormal = ogxWavesNormalFromTex(lookupCenter, shadowLightVector, normalTexture,
        pixelSize, screenExtent, maxResolution, refractIor).xzy; // 读波法线并换到竖直轴朝上的坐标。
    float3 refractVector = refract(float3(0.0, 1.0, 0.0), wavesNormal, 1.0); // 竖直光线被波面折射后的方向。
    float3 collisionPoint = lookupCenter - refractVector / refractVector.y; // 光线与水平面的交点。
    float dist = distance(collisionPoint, worldPos); // 交点到当前点的距离。
    return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}

// 水下体积雾：沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向、云影、相机位置、阴影图与波法线图；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
float3 ogxUnderwaterFog(float3 startPos, float3 endPos, float3 worldDir, float globalCloudShadow,
    float3 cameraOffset, float3 shadowLightVector, Sampler2D shadowDepth0, Sampler2D shadowDepth1,
    bool useSolidShadow, float4x4 shadowView, float4x4 shadowProjection, float shadowBias,
    Sampler2D waveNormalTexture, float2 pixelSize, float2 screenExtent, float causticsResolution, float causticsIor,
    float3 sunColor, float sunIntensity, float underwaterDensity, int steps, float dither,
    bool waterAbsorption, float waterDensity, float handLightScale)
{
    const float range = 40.0; // 光柱的累积范围。
    float startDist = length(startPos); // 起点到相机的距离。
    if (startDist > range) return float3(0.0); // 起点已经在范围外，不画光柱。
    endPos = lerp(worldDir * range, endPos, step(length(endPos), range)); // 终点超过范围就截断到范围内。
    float rayDist = distance(startPos, endPos); // 这条射线在范围里的长度。
    float3 rayDir = (endPos - startPos) / rayDist; // 射线方向。
    float stepLength = range / float(steps); // 每段长度。
    float3 result = float3(0.0); // 累加的光柱颜色。
    float3 handFog = float3(0.0); // 累加的手持光颜色。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float rayLength = (i + dither) * stepLength; // 当前位置，起点加抖动量。
        float3 rayPos = startPos + rayDir * rayLength; // 相机相对世界位置。
        if (startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停止。
        float3 shadowPos = ogxShadowScreenPosDistorted(rayPos + cameraOffset, shadowView, shadowProjection, shadowBias); // 投到阴影图，含边缘压缩。
        float shadowDepth = useSolidShadow ? shadowDepth1.SampleLevel(shadowPos.xy, 0.0).x : shadowDepth0.SampleLevel(shadowPos.xy, 0.0).x; // 按显卡能力选深度图。
        float3 shadow = float3(step(shadowPos.z + 1e-06, shadowDepth)); // 受光则由深度图判定。
        rayLength += startDist; // 距离补上起点偏移。
        float caustics = ogxUnderwaterCaustics(rayPos + cameraOffset, shadowLightVector, waveNormalTexture,
            pixelSize, screenExtent, causticsResolution, causticsIor); // 该点焦散强度。
        shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
        shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
        if (waterAbsorption) shadow *= pow(float3(0.1, 0.6, 1.0) * 0.99, float3(rayLength * 0.04 * waterDensity)); // 红衰减最快，光柱因此偏蓝。
        result += shadow; // 累加。
        float3 handLight = GFX_UNDERWATER_HAND_LIGHT(rayPos); // 手持光源在该点留下的光，由效果层注入。
        if (waterAbsorption) handLight *= pow(float3(0.1, 0.6, 1.0) * 0.99, float3(rayLength * 0.04 * waterDensity)); // 与光柱同一套分波段吸收。
        handFog += handLight; // 累加。
    }
    result *= range / float(steps); // 取平均。
    float3 lightVector = refract(shadowLightVector, float3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
    float lightDotView = dot(lightVector, worldDir); // 光方向与视线的夹角。
    float phase = ogxMiePhase(0.7, lightDotView); // 前向相位，正对阳光时更亮。
    result *= sunColor * (0.04 * phase * sunIntensity * underwaterDensity); // 乘直射光色、相位与强度。
    if (waterAbsorption) result *= float3(0.2, 0.65, 1.0); // 有水下雾时把光柱染成水色。
    result *= globalCloudShadow; // 按全局云影压暗。
    result += handFog * (range / float(steps)) * handLightScale; // 手持光不随阳光相位与云影变化，最后叠上。
    return result; // 返回光柱颜色。
}
