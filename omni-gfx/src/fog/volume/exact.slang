/* 体积雾的严格入口：按 iterationT 默认路径逐行移植的雾与水下光柱；由 `fog/volume.slang` 内联引入。
可复制示例：`ogxVolumetricFogExact(color, startPos, endPos, worldDir, cloudShadow, ...);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 严格参考签名的体积雾入口：按 iterationT 默认的 VFOG_NOISE_TYPE=0 路径逐行移植。
// 参考参数在前，相机、阴影矩阵与画质资源追加在后；不读取宿主全局量。
// 为什么单独一份而不是转调通用入口：通用入口还包含团雾、暴风、闪电、群系与体积光，
// 那些分支会引入参考默认路径没有的采样次数；严格对照要求采样顺序与常数逐项一致。
void ogxVolumetricFogExact(inout float3 color, float3 startPos, float3 endPos, float3 worldDir,
    float globalCloudShadow, float fogTimeFactor, out float transmittance, OgxFogMedia media,
    Sampler2D shadowDepth0, float farPlane, float densityOption, float baseDensityOption,
    float heightA, float heightB, float falloff, float sunAbsorption, int steps, int lightSteps,
    float lightStepLength, float shadowBias, Sampler2D noiseTexture, float2 pixelCoord, int frameCounter)
{
    fogTimeFactor *= media.time_midnight * 2.0 + 1.0; // 参考在高度雾模式下按午夜强度加浓。
    float2 blueNoise = fract(noiseTexture.Load(int3(int2(pixelCoord) % 64, 0)).xy + float2(1.61803398875, 1.32471795724) * float(frameCounter % 64)); // 参考的时序蓝噪声，两个黄金比例常数照原样保留。
    float noise = blueNoise.y; // 参考取蓝噪声的 y 分量作为步进抖动。
    float VdotL = dot(worldDir, media.light_vector); // 视线与阳光方向的夹角。
    float rSteps = 1.0 / float(steps); // 步数的倒数，避免循环内重复除法。
    float3 start = startPos - media.camera_position; // 参考用视图逆矩阵平移把世界位置转回相机相对坐标。
    float3 end = endPos - media.camera_position; // 终点同样转到相机相对坐标。
    float3 rayVector = end - start; // 相机相对的射线。
    float rayLength = length(rayVector) * rSteps * 0.23979; // 每步基础长度，零点二三九七九照参考保留。
    float3 shadowStart = ogxShadowScreenPos(start, media.shadow_view, media.shadow_projection); // 起点投到阴影图。
    float3 shadowEnd = ogxShadowScreenPos(end, media.shadow_view, media.shadow_projection); // 终点投到阴影图。
    float3 shadowRayVector = shadowEnd - shadowStart; // 阴影图里的步进矢量。
    start += media.camera_position; // 补回相机位置后才是绝对世界坐标。
    float baseDensity = baseDensityOption * (media.time_midnight * 0.1 + 0.05) / max(farPlane, 100.0); // 远裁剪面越小基础雾越浓。
    baseDensity *= media.eye_skylight; // 室内或洞穴里按天空光减弱。
    float4 phases = ogxMultiScatteringPhases(VdotL); // 四级散射相位，权重逐次减半。
    transmittance = 1.0; // 透射率从全透开始。
    float fogDensity = 0.0; // 环境雾累计量。
    float rayDensity = 0.0; // 阳光散射累计量。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float exponential = pow(11.0, (i + noise) * rSteps); // 指数步长因子。
        float stepLength = exponential * 0.1 - 0.1; // 这一步在视线上的归一化位置。
        float stepDensity = exponential * rayLength * 1.442695; // 这一步的光学厚度。
        float3 fogPos = start + stepLength * rayVector; // 这一步的世界位置。
        float3 shadowPos = shadowStart + stepLength * shadowRayVector; // 这一步的阴影图坐标。
        float density = ogxFogDensityHeight(fogPos, heightA, heightB, falloff, media.time_midnight); // 两次高度层之间的指数密度。
        density = (density * densityOption + baseDensity) * fogTimeFactor; // 乘密度选项与雾时间因子。
        float absorption = exp2(-density * stepDensity); // 这一步吸收掉的光。
        float lightingDensity = 0.0; // 沿阳光方向累计的密度。
        float lightingStepLength = lightStepLength; // 光方向步长从参考值开始。
        for (int j = 0; j < lightSteps; j++) // 沿阳光方向估遮挡。
        {
            lightingDensity += ogxFogDensityHeight(fogPos, heightA, heightB, falloff, media.time_midnight) * lightingStepLength; // 累加这一段密度。
            fogPos += media.light_vector * lightingStepLength; // 向太阳方向前进。
            lightingStepLength *= 1.5; // 步长逐步放大，远处权重更高。
        }
        lightingDensity = (lightingDensity * sunAbsorption * densityOption + baseDensity) * fogTimeFactor; // 乘吸收率与基础密度。
        float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 光方向上的吸收。
        float stepRayDensity = 0.0; // 这一步的阳光散射量。
        float order = 1.0; // 四级相位的权重。
        for (int j = 0; j < 4; j++) // 四级散射加权求和。
        {
            stepRayDensity += exp(-lightingDensity * order) * phases[j] * order; // 当前相位按权重累加。
            order *= 0.5; // 下一级权重减半。
        }
        stepRayDensity *= ogxLegacyPowder(absorption, lightingAbsorption, VdotL); // 乘粉末效应。
        shadowPos.xy = ogxDistortShadowPos(shadowPos.xy, shadowBias); // 补上阴影图边缘压缩。
        float shadow = 1.0; // 这一点受不受阳光。
        if (ogxEqual(ogxSaturate(shadowPos.xy), shadowPos.xy) && shadowPos.z < 1.0) // 坐标落在阴影图内才采样。
        {
            float solidDepth = shadowDepth0.SampleLevel(shadowPos.xy, 0.0).x; // 只读不透明深度。
            shadow *= step(shadowPos.z, solidDepth); // 射线在遮挡物前面才受光。
        }
        float integral = transmittance - absorption * transmittance; // 这一段吸收掉的光量。
        stepRayDensity *= integral; // 散射量按吸收缩放。
        fogDensity += integral; // 环境雾累加。
        rayDensity += stepRayDensity * shadow; // 散射只在受光处累加。
        transmittance *= absorption; // 透射率逐步衰减。
    }
    float3 skylight = media.sky_color; // 雾的环境色以天光为主。
    float3 skySunLight = media.light_color * 0.03; // 雾里的一点点直射光。
    skylight += skySunLight * (1.0 + (1.0 - globalCloudShadow) * (1.0 - media.wetness)); // 云影越浅这里补得越多。
    skylight = lerp(skylight, skySunLight, media.wetness * 0.7); // 雨天偏向直射色。
    float3 fogColor = skylight * fogDensity; // 环境雾色。
    float3 rayColor = media.light_color * rayDensity; // 阳光散射色。
    fogColor *= 0.32 * media.fog_density_option * media.sky_intensity; // 环境雾按强度选项缩放。
    rayColor *= 0.7 * media.sun_density_option * media.sun_intensity; // 散射按强度选项缩放。
    rayColor *= lerp(globalCloudShadow, 1.0, media.wetness * 0.1); // 没有逐点云影时用全局云影压散射。
    fogColor *= media.eye_skylight; // 环境雾按天空光衰减。
    transmittance = lerp(1.0, transmittance, media.eye_skylight); // 透射率也按天空光拉回。
    color = transmittance * color + fogColor + rayColor; // 场景色先被吸收，再叠上雾与散射。
}

// 严格参考签名的水下体积雾：范围、步数、阴影与焦散顺序照 iterationT 原程序。
// 参考的相机、阴影矩阵、波法线图与水色全部由调用方给出，循环内不读宿主全局量。
float3 ogxUnderwaterFogExact(float3 startPos, float3 endPos, float3 worldDir,
    float globalCloudShadow, float3 cameraOffset, float3 shadowLightVector, Sampler2D shadowDepth0,
    float4x4 shadowView, float4x4 shadowProjection,
    float shadowBias, Sampler2D waveNormalTexture, float2 pixelSize, float2 screenExtent,
    float causticsResolution, float causticsIor, float3 sunColor, float sunIntensity,
    float underwaterDensity, int steps, Sampler2D noiseTexture, float2 pixelCoord, float frameCounter,
    bool waterAbsorption, float waterDensity)
{
    const float range = 40.0; // 光柱的累积范围。
    float startDist = length(startPos); // 起点到相机的距离。
    if (startDist > range) return float3(0.0); // 起点已经在范围外。
    endPos = lerp(worldDir * range, endPos, step(length(endPos), range)); // 终点截断到范围内。
    float rayDist = distance(startPos, endPos); // 范围内射线长度。
    float3 rayDir = (endPos - startPos) / rayDist; // 射线方向。
    float stepLength = range / float(steps); // 每段长度。
    float noise = ogxBlueNoiseTemporal(noiseTexture, int2(pixelCoord), int(frameCounter)).y; // 参考的蓝噪声抖动。
    float3 result = float3(0.0); // 累加的光柱颜色。
    for (float i = 0.0; i < float(steps); i++) // 沿视线逐步前进。
    {
        float rayLength = (i + noise) * stepLength; // 当前位置，含抖动量。
        float3 rayPos = startPos + rayDir * rayLength; // 相机相对世界位置。
        if (startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停。
        float3 shadowPos = ogxShadowScreenPosDistorted(rayPos + cameraOffset, shadowView, shadowProjection, shadowBias); // 投到阴影图。
        float shadowDepth = shadowDepth0.SampleLevel(shadowPos.xy, 0.0).x; // 默认路径读半透明深度图。
        float3 shadow = float3(step(shadowPos.z + 1e-06, shadowDepth)); // 受光判定。
        rayLength += startDist; // 距离补上起点偏移。
        float caustics = ogxUnderwaterCaustics(rayPos + cameraOffset, shadowLightVector, waveNormalTexture,
            pixelSize, screenExtent, causticsResolution, causticsIor); // 该点焦散强度。
        shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
        shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
        if (waterAbsorption) shadow *= pow(float3(0.1, 0.6, 1.0) * 0.99, float3(rayLength * 0.04 * waterDensity)); // 分波段吸收。
        result += shadow; // 累加光柱。
    }
    result *= range / float(steps); // 取平均。
    float3 lightVector = refract(shadowLightVector, float3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光进入水面时弯折。
    float lightDotView = dot(lightVector, worldDir); // 光方向与视线夹角。
    float phase = ogxMiePhase(0.7, lightDotView); // 前向相位。
    result *= sunColor * (0.04 * phase * sunIntensity * underwaterDensity); // 乘直射光色与强度。
    if (waterAbsorption) result *= float3(0.2, 0.65, 1.0); // 有水下雾时染成水色。
    result *= globalCloudShadow; // 按全局云影压暗。
    return result; // 交回光柱颜色。
}

// 下界三段体积雾，具体实现在子文件。
// --- nether ---
