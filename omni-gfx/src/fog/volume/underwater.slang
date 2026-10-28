/* 水下体积雾：焦散取样与光柱步进，输出汇聚的蓝色光柱；由 `fog/volume.slang` 内联引入。
可复制示例：`float caustics = ogxUnderwaterCaustics(worldPos, shadowLightVector, normalTexture, pixelSize, screenExtent, maxResolution, 1.2);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

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
        float3 handLight = OGX_UNDERWATER_HAND_LIGHT(rayPos); // 手持光源在该点留下的光，由效果层注入。
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

// 严格参考签名入口，具体实现在子文件。

// WSR 水下体积：按 Eclipse 参考逐行移植水吸收、焦散、方向光与闪电照明。
// 参考参数在前，相机、阴影、噪声与选项资源追加在后；默认分支不读宿主全局量。

float4 ogxUnderwaterVolumeReference(float3 origin, float3 endPos, float2 dither, float3 ambient,
    float3 lightSource, float3 lpv, float3 waterAbsorption, float dirtAmount, float3 dirtColor,
    float waterAltitude, float sunElevation, float bubbleScale, float time, float waveSpeed,
    float patchyBlend, Sampler2D noiseTexture, float3 sunVector, float3 cameraOffset, float3 cameraWorldPos,
    float farPlane, float cloudShadow, Sampler2D shadowTexture, float4x4 shadowView, float4x4 shadowProjection,
    float distortA, float distortB, float distortK, float shadowResolution, float4 lightningPosition,
    float lightningFlash)
{
    if (length(origin - endPos) < 0.001) return float4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有水体。
    const int sampleCount = 3; // 参考实现的固定三步。
    float lightSourceCheck = float(sunElevation > 1e-5) * 2.0 - 1.0; // 太阳在地平线上时翻转云影方向。
    float3 scatterCoef = dirtAmount * dirtColor / 3.14; // 参考的脏水散射系数。
    float3 dVWorld = endPos - origin - cameraOffset; // 相机相对的射线位移。
    float rayLength = length(dVWorld); // 射线长度。
    float maxLength = min(rayLength, farPlane) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到远裁剪面。
    float3 absorbance = float3(1.0); // 累积吸收。
    float3 vL = float3(0.0); // 累积颜色。
    float3 rayDir = normalize(endPos - origin); // 射线方向。
    float VdotL = dot(sunVector, rayDir); // 视线与阳光方向的夹角。
    float phase = ogxEndLightFalloff(VdotL) * 5.0; // 参考的雾相位。
    float thing = -normalize(dVWorld).y; // 垂直方向。
    thing = clamp(thing + 0.333, 0.0, 1.0); // 参考的形状偏移。
    thing = pow(1.0 - pow(1.0 - thing, 2.0), 2.0) * 15.0; // 参考的形状重整。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定三步。
    {
        float d = (pow(expFactor, float(i) + dither.x) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither.y) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        float3 progressP = cameraOffset + d * dVWorld; // 相机相对位置。
        float3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        float distanceFromWaterSurface = max(-(progressW.y - waterAltitude), 0.0); // 到水面的距离。
        float3 fragposition = ogxMatrixMulPoint(shadowView, progressP) + ogxMatrixTranslation(shadowView); // 阴影相机空间坐标。
        fragposition = float3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragposition + shadowProjection[3].xyz; // 按投影对角线缩放。
        float distortFactor = ogxShadowDistortFactor(fragposition.xy, distortA, distortB, distortK); // 阴影边缘压缩。
        float3 spPos = float3(fragposition.xy * distortFactor, fragposition.z); // 压缩后的阴影坐标。
        float3 pos = float3(spPos.xy * distortFactor, spPos.z); // 参考在这里再压一次。
        float3 sh = float3(1.0); // 受光系数。
        if (abs(pos.x) < 1.0 - 0.5 / shadowResolution && abs(pos.y) < 1.0 - 0.5 / shadowResolution) // 落在阴影图内才采样。
        {
            pos = pos * float3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 换成零到一坐标。
            sh = float3(shadowTexture.SampleLevel(pos.xy, 0.0).x); // 只读不透明深度。
        }
        sh *= cloudShadow; // 参考的云影由宿主预计算成标量。
        float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / bubbleScale, 0.0, 1.0)); // 气泡形状。
        float caustics = max(max(ogxWaterBumpCaustics(progressW, sunVector, -(progressW.y - waterAltitude), time, waveSpeed, patchyBlend, noiseTexture), phase * 0.5) * lerp(0.5, 1.5, bubble), phase); // 参考的焦散与相位混合。
        float3 sunAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface / abs(sunVector.y))); // 阳光穿过水面的吸收。
        float3 waterAbsorbance = exp(-waterAbsorption * (distanceFromWaterSurface + thing)); // 水体吸收。
        float3 direct = lightSource * sh * phase * caustics * sunAbsorbance; // 直射。
        float3 indirect = ambient; // 间接光。
        float horizontalDist = length(progressP.xz - lightningPosition.xz); // 到闪电的水平距离。
        if (horizontalDist < 250.0 && lightningPosition.w > 0.0) // 闪电在附近时照亮水体。
        {
            float lightningIntensity = exp(-horizontalDist * 0.02) * lightningFlash; // 距离衰减。
            indirect = lerp(indirect, float3(1.3, 1.5, 3.0) * sh, lightningIntensity); // 冷色闪光。
        }
        indirect *= waterAbsorbance; // 间接光也被水体吸收。
        float3 light = (indirect + direct + lpv) * scatterCoef; // 总光。
        float3 volumeCoeff = exp(-waterAbsorption * length(dd * dVWorld)); // 本段吸收。
        vL += (light - light * volumeCoeff) / waterAbsorption * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积吸收。
    }
    return float4(vL, dot(absorbance, float3(0.333333))); // 交回水体颜色与透过率。
}
