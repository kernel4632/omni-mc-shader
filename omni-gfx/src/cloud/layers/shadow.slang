/* 层状体积云的阴影：行星阴影、三层云影、闪电落点与步进起点；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetCloudShadow(settings, playerPos, sunVector, 100, 1.0, cameraPos, noise);`
设计取舍：云影沿太阳方向投到各层云底，按层密度累加，天上的云和地面的影共用同一份形状。 */

// 闪电位置：在云层半径内取一个随机方向，并确认那里确实有积雨云。
float3 ogxLayersGetLightningPosition(OgxLayersCloudSettings s, float minHeight, float maxHeight, float cumulonimbusScale,
    float3 cameraPos, Sampler2D noiseTexture)
{
    float angle = fract(sin(dot(float2(s.lightningBoltPosition.w), float2(12.9898, 78.233))) * 43758.5453) * 6.28318530718; // 随机角。
    float rMin = 7000.0; // 内半径。
    float rMax = 13000.0; // 外半径。
    float radius = sqrt(lerp(rMin * rMin, rMax * rMax, fract(sin(dot(float2(s.lightningBoltPosition.w + 1.0), float2(12.9898, 78.233))) * 43758.5453))); // 面积均匀的半径。
    float3 lightningPos = float3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 初始位置。
    float shapeAtLightning = ogxLayersGetCumulonimbusShape(s, 0, lightningPos, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x; // 该处云密度。
    lightningPos.y = minHeight + (maxHeight - minHeight) * 0.48; // 参考实现把高度固定到 0.48。
    if (shapeAtLightning < 0.1) lightningPos = float3(0.0); // 没有云就不闪。
    return lightningPos; // 交回相机相对位置。
}

// 行星阴影：太阳越低，主岛下方越暗。
float ogxLayersGetPlanetShadow(float3 playerPos, float3 sunVector)
{
    float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / max(sunVector.y * 0.1, 0.0)), 0.0) / 100.0, 1.0); // 高度阈值。
    planetShadow = lerp(pow(1.0 - pow(1.0 - planetShadow, 2.0), 2.0), 1.0, pow(max(sunVector.y, 0.0), 2.0)); // 太阳越高阴影越少。
    return planetShadow; // 交回阴影权重。
}

// 云影：把地面点沿太阳方向投到各层云，按层密度累加。
float ogxLayersGetCloudShadow(OgxLayersCloudSettings s, float3 playerPos, float3 sunVector, int cloudShadowAmount,
    float cumulonimbusScale, float3 cameraPos, Sampler2D noiseTexture)
{
    float totalShadow = ogxLayersGetPlanetShadow(playerPos, sunVector); // 行星阴影。
    float3 startPosition = playerPos; // 投影起点。
    float3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向到单位高度的位移。
    if (cloudShadowAmount > 0) // 有云影才计算。
    {
        float cloudShadows = 0.0; // 云影累加。
        startPosition = playerPos + startOffset * max((s.layers[0].height + 20.0) - playerPos.y, 0.0); // 投到小积云下段。
        cloudShadows = ogxLayersGetCloudShape(s, 0, 0, startPosition, s.layers[0].height,
            s.layers[0].height + s.layers[0].tallness / s.layers[0].scale, noiseTexture) * s.layers[0].rainDensity; // 小积云。
        startPosition = playerPos + startOffset * max((s.layers[1].height + 30.0) - playerPos.y, 0.0); // 投到大积云下段。
        cloudShadows += ogxLayersGetCloudShape(s, 1, 0, startPosition, s.layers[1].height,
            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * s.layers[1].rainDensity; // 大积云。
        startPosition = playerPos + startOffset * max(s.layers[3].height - playerPos.y, 0.0); // 投到高层云。
        cloudShadows += ogxLayersGetCloudShape(s, 3, 0, startPosition, s.layers[3].height, s.layers[3].height + 5.0,
            noiseTexture) * s.layers[3].rainDensity * (1.0 - abs(sunVector.y)); // 高层云。
        float distanceFactor = clamp(degrees(acos(dot(float3(0.0, 1.0, 0.0), sunVector))), 45.0, 90.0) - 45.0; // 太阳角度。
        startPosition = playerPos + sunVector * lerp(7000.0, 18000.0, distanceFactor / 45.0); // 投到积雨云。
        cloudShadows += ogxLayersGetCumulonimbusShape(s, 0, startPosition, 600.0, 4600.0 + startPosition.y,
            cumulonimbusScale, cameraPos, noiseTexture).x; // 积雨云。
        cloudShadows *= float(cloudShadowAmount) / 100.0; // 按强度缩放。
        totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云越厚阴影越黑。
    }
    return totalShadow; // 交回总阴影。
}

// 步进起点：按相机在云层中的位置把射线压到平面，避免从错误的一侧开始。
float3 ogxLayersGetRayOrigin(float3 rayStartPos, float3 cameraPos, float dither, float minHeight, float maxHeight)
{
    float3 cloudDist = float3(1.0); // 水平与竖直的缩放。
    cloudDist.xz = lerp(float2(255.0), float2(5.0), clamp(cameraPos.y - minHeight, 0.0,
        clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 越靠近云层水平步长越小。
    float flip = lerp(max(cameraPos.y - maxHeight, 0.0), max(minHeight - cameraPos.y, 0.0), clamp(rayStartPos.y, 0.0, 1.0)); // 上下翻转。
    return rayStartPos * dither + cameraPos + (rayStartPos / length(rayStartPos / cloudDist)) * flip; // 压到平面并加抖动。
}

// 层状云闪电落点：用时间哈希选极坐标角度与半径，再把位置贴到积雨云层里。
// 参考签名只有云层上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加，
// 时间哈希与自定义落点常数直接写成参考数值，保持同一组常数。
float3 ogxLayersLightningPositionBolt(float minHeight, float maxHeight,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength, float lightningTimer)
{
    float angle = fract(sin(dot(float2(lightningTimer, lightningTimer * 2.0), float2(12.9898, 78.233))) * 43758.5453) * 6.28318530718; // 时间哈希转角度。
    float rMin = 7000.0; // 最近落点半径。
    float rMax = 13000.0; // 最远落点半径。
    float radius = sqrt(lerp(rMin * rMin, rMax * rMax, fract(sin(dot(float2(lightningTimer + 1, (lightningTimer + 1) * 2.0), float2(12.9898, 78.233))) * 43758.5453))); // 在环形区域里取半径。
    float3 lightningPos = float3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 极坐标转云层坐标。
    float shapeAtLightningPos = ogxLayersCumulonimbusShapeLayer(0, lightningPos, minHeight, maxHeight,
        noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x; // 落点处的积雨云形状。
    float moveUp = 0.48; // 闪电起点抬到云层中上部。
    lightningPos.y = minHeight + (maxHeight - minHeight) * moveUp; // 重算高度。
    lightningPos.y -= cameraWorldPos.y; // 换成相机相对高度。
    if (shapeAtLightningPos < 0.1) lightningPos = float3(0.0); // 落点没有云就不闪。
    lightningPos = float3(100.0, 0.0, 0.0) - cameraWorldPos; // 参考默认的自定义落点。
    return lightningPos; // 交回闪电位置。
}

// 层状云影：从玩家位置沿太阳方向升到三层云底，各取一次云形状并按降雨加成叠加。
// 参考签名只有玩家位置与太阳方向；云噪声、风、雨雷、三层覆盖与闪电状态显式追加。
float ogxLayersCloudShadowLayer(float3 playerPos, float3 sunVector,
    Sampler2D noiseTexture, float4 lightningBoltPosition, float sunElevation,
    float cloudMovement, float rainAmount, float thunderStrength,
    float smallCumulusCoverage, float largeCumulusCoverage, float altostratusCoverage,
    float smallCumulusRain, float largeCumulusRain, float altostratusRain)
{
    if (lightningBoltPosition.w > 0.0 && sunElevation < 0.0) // 夜里打闪电时不投云影，避免整片变黑。
    {
        return 1.0;
    }
    float totalShadow = ogxLayersGetPlanetShadow(playerPos, sunVector); // 先算星球本身遮住多少阳光。
    float3 startPosition = playerPos; // 云影采样起点。
    float3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向升到云底所需的水平偏移。
    float cloudShadows = 0.0; // 三层云影累加。
    startPosition = playerPos + startOffset * max((250.0 + 20.0) - playerPos.y, 0.0); // 小积云底。
    cloudShadows = ogxLayersCloudShapeLayer(0, 0, startPosition, 250.0, 250.0 + 130.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxLayersGetRainDensity(smallCumulusRain, rainAmount, thunderStrength); // 小积云影。
    startPosition = playerPos + startOffset * max((400.0 + 30.0) - playerPos.y, 0.0); // 大积云底。
    cloudShadows += ogxLayersCloudShapeLayer(1, 0, startPosition, 400.0, 400.0 + 280.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength); // 大积云影。
    startPosition = playerPos + startOffset * max(5000.0 - playerPos.y, 0.0); // 高层云底。
    cloudShadows += ogxLayersCloudShapeLayer(3, 0, startPosition, 5000.0, 5000.0 + 5.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * altostratusRain * (1.0 - abs(sunVector.y)); // 高层云影随太阳高度变淡。
    cloudShadows *= float(100.0) / 100.0; // 参考的云影总量比例。
    totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云影越厚，透过率下降越快。
    return totalShadow; // 交回阳光透过率。
}
