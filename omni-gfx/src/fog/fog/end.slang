/*
雾子文件：末地漩涡雾、下界群系雾色、通用群系雾与末地阴影形状。
调用位置：由 `fog/fog.slang` 内联，末地天空与雾效果直接调用这里的入口。
可复制示例：`float phase = ogxEndVortexLightPhase(lightPos);`
设计原因与取舍：群系权重与光源位置显式传入，不读取宿主群系表；漩涡形状与参考采样顺序一致。
*/
// 末地雾形状与光源相位的提前声明：定义放在文件后半段。
float ogxEndVortexShape(float3 pos, float time, Sampler2D noiseTexture, float noiseResolution);
float ogxEndVortexLightPhase(float3 pos);

// iterationT 末地光源照明：沿光源方向取三层雾形状，按相位与吸收合成。
// 为什么单独一份：参考签名不带雾形状纹理，严格对照需要显式接收三维雾。
float3 ogxEndVortexLightingReference(float3 startPos, float3 lightPos, float dither, float density,
    float3 lightColor, float vortexBounds, Sampler2D noiseTexture, float time, float noiseResolution)
{
    float phase = ogxEndVortexLightPhase(lightPos); // 参考实现的光源相位。
    float shadow = 0.0; // 三层雾密度累加。
    for (int j = 0; j < 3; j++) // 三层采样。
    {
        float3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * (0.25 + 0.0 * 0.15)); // 采样位置。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution); // 读雾形状。
    }
    float3 finalLighting = lightColor * phase * exp(-7.0 * shadow); // 主照明。
    finalLighting += lightColor * phase * phase * (1.0 - exp(-shadow * float3(0.6, 2.0, 2.0)))
        * (1.0 - exp(-density * density)); // 多次散射补光。
    return finalLighting;
}

// iterationT 末地雾影：三层采样后按指数衰减，返回零到一的可见度。
float ogxEndFogShadowNoise(float3 worldPos, float3 lightPos, Sampler2D noiseTexture,
    float time, float noiseResolution, float endStormDensity)
{
    float shadow = 0.0; // 三层雾密度累加。
    for (int i = 0; i < 3; i++) // 三层采样。
    {
        float3 shadowSamplePos = worldPos - lightPos * (0.01 + pow(float(i), 0.75) * 0.25); // 采样位置。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution) * endStormDensity; // 读雾形状并乘风暴密度。
    }
    return clamp(exp2(shadow * -10.0), 0.0, 1.0); // 指数衰减到可见度。
}

// 末地涡旋噪声：与下界单格密度同样的降维思路，但贴图边长由调用方给出。
float ogxEndVortexNoise(float3 pos, Sampler2D noiseTexture, float noiseResolution)
{
    pos /= 18.0; // 世界坐标缩到十八分之一，决定颗粒稀密。
    pos.xz *= 0.5; // 水平再压一半，雾团沿竖直拉长。
    float3 cell = floor(pos); // 所在整数格。
    float3 f = fract(pos); // 格内偏移。
    f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，格与格之间不出现硬边。
    float2 uv = cell.xz + f.xz + cell.y * float2(0.0, 193.0); // 三维到二维的分配，一百九十三打散高度。
    float2 xy = noiseTexture.SampleLevel(uv / noiseResolution, 0.0).yx; // 读上下两层并交换通道。
    return lerp(xy.r, xy.g, f.y); // 按格内高度插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// 先算旋转后与原始坐标的混合比例，再插值，避免远处雾团被整片拧动。
void ogxEndVortexSwirl(inout float3 alteredOrigin, float3 origin, float time)
{
    float radiance = 2.39996 + alteredOrigin.y / 1.5 + time / 50.0; // 旋转角随时间与高度推进。
    float cosine = cos(radiance); // 旋转角的余弦，下面用显式公式代替矩阵。
    float sine = sin(radiance); // 旋转角的正弦。
    float2 rotated = float2(cosine * alteredOrigin.x + sine * alteredOrigin.z, cosine * alteredOrigin.z - sine * alteredOrigin.x); // 与旧实现的「行向量乘矩阵」逐项相同。
    float swirlBounds = clamp(sqrt(max(length(float3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转。
    alteredOrigin.xz = lerp(rotated, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void ogxEndVortexBounds(inout float volume, float3 origin)
{
    float3 origin2 = origin - float3(0.0, 100.0, 0.0); // 相对高度一百的中心。
    origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
    float center = length(origin2); // 到中心的距离。
    float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
    float radius = 150.0; // 主岛圆环的半径。
    float thickness = 25.0 * radius; // 圆环判定的厚度尺度，取大得到平缓边缘。
    float torus = (thickness - clamp(pow(length(float2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
    volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 末地雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float ogxEndVortexShape(float3 pos, float time, Sampler2D noiseTexture, float noiseResolution)
{
    float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距原点三百格内为涡旋核心。
    float3 samplePos = pos * float3(1.0, 1.0 / 48.0, 1.0); // 竖直压扁，得到分层云感。
    float voidZone = max(exp2(-1.0 * sqrt(max(pos.y - -60.0, 0.0))), 0.0); // 主岛下方六十格起逐渐发白。
    ogxEndVortexSwirl(samplePos, pos, time); // 把采样坐标按漩涡旋转。
    float noise = ogxEndVortexNoise(samplePos * 12.0, noiseTexture, noiseResolution); // 基础噪声决定浓淡。
    float erosion = 1.0 - ogxEndVortexNoise((samplePos - time / 18.0) * (124.0 + (1.0 - noise) * 7.0), noiseTexture, noiseResolution); // 随时间上升的侵蚀噪声。
    float clumpyFog = max(exp(noise * -lerp(10.0, 4.0, vortexBounds)) * lerp(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
    ogxEndVortexBounds(clumpyFog, pos); // 按体积限制减薄。
    return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float ogxEndVortexLightPhase(float3 lightPos)
{
    float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一。
    return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
float3 ogxEndVortexLighting(float3 startPos, float3 lightPos, float density, float3 lightColor, float time, Sampler2D noiseTexture, float noiseResolution)
{
    float phase = ogxEndVortexLightPhase(lightPos); // 到光柱中心的相位。
    float shadow = 0.0; // 沿光方向累积的遮挡。
    for (int j = 0; j < 3; j++) // 三步采样雾的遮挡。
    {
        float3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * (0.25 + 0.0 * 0.15)); // 从当前点向光柱中心退回采样，零点一五照参考保留但不参与。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution); // 累加遮挡。
    }
    float3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
    lighting += lightColor * phase * phase * (1.0 - exp(-shadow * float3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
    return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// 步数、步长分布、密度颜色与输出缩放全由参数给出，因为远景开关与画质选项属于宿主。
float4 ogxEndVortexFog(float3 cameraPos, float3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist,
    float3 vortexColor, float3 ambientColor, float stormScale, float hazeDensity, float time,
    Sampler2D noiseTexture, float noiseResolution, float outputScale)
{
    float3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
    float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
    float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
    rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
    float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
    float3 color = float3(0.0); // 累积的雾发光。
    float absorbance = 1.0; // 累积的透过率，用来给后面的光正确留出通道。
    float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
    float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
    for (int i = 0; i < sampleCount; i++) // 逐步前进。
    {
        float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
        float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
        float3 progressW = cameraPos + d * rayWorld; // 这一步的世界位置。
        float3 lightPos = progressW - float3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处。
        float volumeDensity = ogxEndVortexShape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
        float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPos) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
        float stormDensity = min(volumeDensity, clearArea * clearArea * stormScale); // 风暴部分按贴脸留空与密度封顶。
        float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
        float3 lightsources = ogxEndVortexLighting(progressW, lightPos, volumeDensity, vortexColor, time, noiseTexture, noiseResolution); // 这一步的雾内光柱发光。
        float3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
        float3 stormLighting = indirect + lightsources; // 这一步的总发光。
        color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
        absorbance *= volumeCoeff; // 透过率继续衰减。
        float3 hazeLighting = float3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
        color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
    }
    return float4(color * outputScale, absorbance); // 散射色换算到管线单位，剩余透射率一并交回。
}

// 末地体积涡旋雾：按 Eclipse `end_fog.glsl` 的 GetVolumetricFog 逐行移植。
// 参考参数在前，相机、随机缓冲、噪声与风暴资源追加在后；默认分支不读宿主全局量。
float4 ogxEndVolumetricFogExact(float3 viewPosition, float dither, float dither2,
    float4x4 modelViewInverse, float3 cameraWorldPos, float3 ambientColor, float3 vortexColor, float3 lightningColor,
    float3 orbColor, float orbMult, bool theOrb, float vortexBoundRange, float3 manualLightPos,
    Sampler2D randomTexture, Sampler2D noiseTexture, float noiseResolution, float endStormDensity,
    float endHazeDensity, int sampleCount, float expFactor, float maxDistNear, float maxDistFar,
    float time)
{
    float3 wpos = ogxMatrixMulPoint(modelViewInverse, viewPosition) + ogxMatrixTranslation(modelViewInverse); // 参考用视图逆矩阵把视线终点转到世界位置。
    float3 dVWorld = wpos - ogxMatrixTranslation(modelViewInverse); // 相机相对的射线位移。
    float verticalFactor = abs(normalize(dVWorld).y); // 视线越竖直，雾越短。
    verticalFactor = pow(verticalFactor, 2.0); // 参考对竖直分量平方。
    float rayLength = length(dVWorld); // 射线总长。
    float maxDist = lerp(maxDistNear, maxDistFar, verticalFactor); // 按视线角度在两组距离之间取值。
    float maxLength = min(rayLength, maxDist) / rayLength; // 距离上限的比例。
    dVWorld *= maxLength; // 截断到最大距离。
    float dL = length(dVWorld); // 实际步进长度。
    float3 color = float3(0.0); // 累积颜色。
    float absorbance = 1.0; // 累积透过率。
    float skyPhase = (0.5 + pow(clamp(normalize(wpos).y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
    float lightningflash = randomTexture.Load(int3(int2(1, 1), 0)).x / 150.0; // 参考从第四张缓冲固定像素取闪电强度。
    for (int i = 0; i < sampleCount; i++) // 逐步前进。
    {
        float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例。
        float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
        float3 progressP = ogxMatrixTranslation(modelViewInverse) + d * dVWorld; // 相机相对位置。
        float3 progressW = progressP + cameraWorldPos; // 绝对世界位置。
        float vortexBounds = clamp(vortexBoundRange - length(progressW), 0.0, 1.0); // 涡旋核心范围。
        float3 vortexPos = progressW - float3(0.0, 200.0, 0.0); // 中心光柱。
        float3 lightningPos = progressW - cameraWorldPos - manualLightPos; // 闪电光。
        lightningPos += fract(cameraWorldPos / 200.0) * 200.0 - 200.0 * 0.5; // 吸到两百格网格。
        float3 randomOffset = (randomTexture.Load(int3(int2(2, 1), 0)).xyz / 150.0) * 2.0 - 1.0; // 参考从第四张缓冲取随机偏移。
        lightningPos -= randomOffset * 2.5; // 随机偏移。
        float3 lightPosition = theOrb ? lightningPos : lerp(lightningPos, vortexPos, vortexBounds); // 参考的光源位置。
        float3 lightColors = (theOrb ? orbColor * orbMult : lerp(lightningColor * lightningflash, vortexColor, vortexBounds)) * 0.25; // 参考的光源颜色。
        float volumeDensity = ogxEndVortexShape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
        float clearArea = 1.0 - min(max(1.0 - length(progressP) / 100.0, 0.0), 1.0); // 相机一百格内留空。
        float stormDensity = min(volumeDensity, clearArea * clearArea * endStormDensity); // 风暴部分按贴脸留空与密度封顶。
        float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
        float3 lightsources = ogxEndVortexLighting(progressW, lightPosition, volumeDensity, lightColors,
            time, noiseTexture, noiseResolution); // 雾内光柱发光。
        float3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光。
        float3 stormLighting = indirect + lightsources; // 这一步的总发光。
        color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 累积散射。
        absorbance *= volumeCoeff; // 累积透过率。
        float hazeDensity = 0.001 * endHazeDensity; // 参考的雾霭密度。
        float3 hazeLighting = float3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 冷紫雾霭。
        color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率。
    }
    return float4(color, absorbance); // 交回雾色与透过率。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分，最后乘风暴与雾霭两层密度。
// `VdotL` 是视线与光方向余弦，`angleX`、`angleY` 是行星相位角，`planetShadow` 是行星遮挡权重。
float ogxEndFogDensity(float3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale)
{
    float3x3 eyeRotationMatrix = ogxRotationXThenY(angleX, angleY); // 与行星共用的俯仰加偏航。
    float3 dir = ogxMatrix3MulPoint(eyeRotationMatrix, worldDir); // 视线转到相位坐标系。
    dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
    float h = abs(dir.z) * dist * 0.03; // 沿视线方向的等效高度。
    float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。
    float storm = ogxMiePhase(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分。
    float haze = 0.25; // 不带方向的雾霭基准部分。
    float density = fogDepth * (storm * stormScale + haze * hazeScale); // 两层分别缩放后相加。
    density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。
    return density; // 交回未换算单位的密度。
}

// Eclipse 末地雾的相函数：与云相函数同形，但常数用 3.14 而不是 pi，保留参考精度。
float ogxEndFogPhaseAnisotropic(float x, float g)
{
    return ogxHenyeyGreensteinPhase(x, g, 1.0 / 3.14); // 参考实现直接写 3.14，保留同一精度。
}

// 雾相位：Eclipse 的指数相位，光线越正对越亮。
float ogxEndLightFalloff(float lightPoint)
{
    float linear = clamp(-lightPoint * 0.5 + 0.5, 0.001, 1.0); // 线性项。
    float linear2 = 1.0 - clamp(lightPoint, 0.0, 1.0); // 参考保留这一项，当前返回值没有用到它。
    float exponential = exp2(pow(linear, 0.3) * -15.0) * 1.5; // 指数项。
    exponential += sqrt(exp2(sqrt(linear) * -12.5)); // 开方项。
    return exponential; // 交回相位。
}

// 末地雾阴影：沿光源方向取三个密度样本，再按指数衰减成阴影。
float ogxEndFogShadowShape(float3 worldPos, float3 lightPos, Sampler3D fogShape, float endStormDensity)
{
    float shadow = 0.0; // 密度累加。
    for (int i = 0; i < 3; i++) // 三个样本。
    {
        float3 samplePos = worldPos - lightPos * (0.01 + pow(float(i), 0.75) * 0.25); // 参考实现的偏移。
        shadow += fogShape.SampleLevel(samplePos, 0.0).r * endStormDensity; // 取雾密度。
    }
    return clamp(exp2(shadow * -10.0), 0.0, 1.0); // 参考实现的衰减。
}
