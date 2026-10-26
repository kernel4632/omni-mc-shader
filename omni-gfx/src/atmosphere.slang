/*
Omni 通用图形库大气模块：球面几何、密度剖面、单次散射与空气透视。
调用位置：天空、地形远景、水面与云的环境光；Minecraft 光影由 `/omni-gfx/atmosphere.glsl` 引入。
可复制示例：
    OgxAtmosphere a = ogxAtmosphereEarth(); // 取一组地球常数。
    float3 s = ogxAtmosphereSky(a, 0.03, viewDir, sunDir, 10); // 算天空颜色。
    float3 h = ogxAerialPerspective(a, 0.03, viewDir, 1.5, sunDir, 5, t2); // 算远景空气散射。
设计原因与取舍：
    公式来自旧 `shaders/gfx/atmosphere.glsl` 的球面几何与密度剖面，并补上可独立运行的单次散射积分。
    不读取预计算贴图，换机器与不启动 Minecraft 都能得到同一片天空；代价是每像素多几次指数运算。
    长度单位统一为公里，避免行星半径用米时 float 精度不足；调用方把米乘零点零零一。
    太阳与月亮方向、散射系数、行星半径全部由调用方传入，库不读取任何引擎状态。
*/
#ifndef OGX_ATMOSPHERE_INCLUDED
#define OGX_ATMOSPHERE_INCLUDED

// 数学模块提供相函数、射线求交与夹紧。
#include "math.slang"

// 一次大气计算需要的全部常数；不同星球换一组字段即可，不必改算法。
struct OgxAtmosphere
{
    float planetRadius; // 行星底半径，公里。
    float atmosphereRadius; // 大气层顶半径，公里。
    float rayleighHeight; // 瑞利密度衰减高度，公里。
    float mieHeight; // 米氏密度衰减高度，公里。
    float3 rayleighScattering; // 瑞利散射系数，每公里。
    float3 mieScattering; // 米氏散射系数，每公里。
    float3 ozoneAbsorption; // 臭氧吸收系数，每公里。
    float mieG; // 米氏相位的前向集中程度。
    float sunIntensity; // 太阳辐照度的整体倍率。
};

// 地球参数：海平面半径六千三百六十公里，层顶八十公里，数值与旧库一致。
OgxAtmosphere ogxAtmosphereEarth()
{
    OgxAtmosphere air; // 先声明再逐项填写，Slang 与 GLSL 都支持这种写法。
    air.planetRadius = 6360.0; // 地球半径，公里。
    air.atmosphereRadius = 6440.0; // 大气层顶，海平面以上八十公里。
    air.rayleighHeight = 8.0; // 瑞利散射主要由低空空气造成。
    air.mieHeight = 1.2; // 米氏散射集中在更低的雾霾层。
    air.rayleighScattering = float3(5.8e-3, 13.5e-3, 33.1e-3); // 蓝光散射最强，天空因此偏蓝。
    air.mieScattering = float3(1.0e-3, 1.0e-3, 1.0e-3); // 气溶胶散射近似中性灰，压低地平线白雾。
    air.ozoneAbsorption = float3(0.65e-3, 1.881e-3, 0.085e-3); // 臭氧吸收少量红光与蓝光。
    air.mieG = 0.62; // 前向散射明显，太阳附近出现白晕。
    air.sunIntensity = 13.0; // 与测试世界的曝光配合，保持高动态范围。
    return air; // 返回一组可直接使用的常数。
}

// 臭氧剖面：十公里以下没有，二十五公里最浓，四十公里以上消失。
float ogxAtmosphereOzoneProfile(float altitude)
{
    float x = (altitude - 10.0) / 30.0; // 把十到四十公里映射到零到一。
    return max(1.0 - abs(x * 2.0 - 1.0), 0.0); // 三角形剖面，峰值在二十五公里。
}

// 瑞利密度：高度越高越稀薄，指数衰减。
float ogxAtmosphereDensityRayleigh(OgxAtmosphere air, float altitude)
{
    return exp(-max(altitude, 0.0) / air.rayleighHeight); // 负高度按海平面处理。
}

// 米氏密度：同样指数衰减，但衰减高度更短。
float ogxAtmosphereDensityMie(OgxAtmosphere air, float altitude)
{
    return exp(-max(altitude, 0.0) / air.mieHeight); // 气溶胶集中在低空。
}

// 视线到球面远交点的距离；相机在球内时取正根。
float ogxAtmosphereDistanceToTop(float3 origin, float3 direction, float radius)
{
    float b = dot(origin, direction); // 球面方程的中间项。
    float c = dot(origin, origin) - radius * radius; // 常数项。
    float discriminant = b * b - c; // 判别式。
    if (discriminant < 0.0) // 没有交点说明视线完全在球外。
    {
        return 0.0; // 返回零，调用方据此跳过。
    }
    return max(-b + sqrt(discriminant), 0.0); // 远交点，负值夹到零。
}

// 视线到行星地面的距离；没有打到地面时通过 `hit` 交回假。
float ogxAtmosphereDistanceToGround(float3 origin, float3 direction, float radius, out bool hit)
{
    float b = dot(origin, direction); // 球面方程中间项。
    float c = dot(origin, origin) - radius * radius; // 常数项。
    float discriminant = b * b - c; // 判别式。
    if (discriminant < 0.0) // 没有交点。
    {
        hit = false; // 告诉调用方没有地面。
        return 0.0; // 距离无意义。
    }
    float near = -b - sqrt(discriminant); // 近交点。
    if (near < 0.0) // 相机在地面以下或交点在身后。
    {
        hit = false; // 不把背后的地面算进来。
        return 0.0;
    }
    hit = true; // 真正打到前方地面。
    return near; // 返回近交点距离。
}

// 一段视线上的光学厚度：分别累加瑞利、米氏与臭氧三组密度。
float3 ogxAtmosphereOpticalDepth(OgxAtmosphere air, float3 origin, float3 direction, float distance)
{
    float3 depth = float3(0.0); // 三组光学厚度。
    if (distance <= 0.0) // 零长度不产生遮挡。
    {
        return depth; // 直接返回零。
    }
    const int steps = 8; // 固定八段，保证不同显卡的耗时接近。
    float stepLength = distance / float(steps); // 每段长度。
    float3 position = origin + direction * (stepLength * 0.5); // 从第一段中点开始。
    for (int i = 0; i < steps; i++) // 逐段累加。
    {
        float altitude = length(position) - air.planetRadius; // 这一段所在高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float ozone = ogxAtmosphereOzoneProfile(altitude); // 臭氧密度。
        depth += float3(rayleigh, mie, ozone) * stepLength; // 密度乘段长。
        position += direction * stepLength; // 前进到下一段。
    }
    return depth; // 返回三组光学厚度。
}

// 由光学厚度算透过率：散射系数与臭氧吸收共同消光。
float3 ogxAtmosphereTransmittance(OgxAtmosphere air, float3 opticalDepth)
{
    float3 extinction = air.rayleighScattering * opticalDepth.x // 瑞利消光。
                      + air.mieScattering * opticalDepth.y // 米氏消光。
                      + air.ozoneAbsorption * opticalDepth.z; // 臭氧吸收。
    return exp(-extinction); // 比尔-朗伯定律。
}

// 某点朝太阳方向到层顶的透过率；太阳贴地时自然变暗。
float3 ogxAtmosphereSunTransmittance(OgxAtmosphere air, float3 position, float3 sunDirection, int steps)
{
    float distanceToTop = ogxAtmosphereDistanceToTop(position, sunDirection, air.atmosphereRadius); // 到层顶的距离。
    if (distanceToTop <= 0.0) // 太阳在地平线以下或视线没有交点。
    {
        return float3(0.0); // 没有直射阳光。
    }
    const int maxSteps = 4; // 固定上限，调用方只能在这个范围内减少。
    int count = min(max(steps, 1), maxSteps); // 至少一段，最多四段。
    float3 depth = float3(0.0); // 太阳方向的光学厚度。
    float stepLength = distanceToTop / float(count); // 每段长度。
    float3 samplePosition = position + sunDirection * (stepLength * 0.5); // 第一段中点。
    for (int i = 0; i < maxSteps; i++) // 固定循环上限。
    {
        if (i >= count) // 超过调用方要求的段数就停止。
        {
            break; // 提前结束，避免多做指数运算。
        }
        float altitude = length(samplePosition) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float ozone = ogxAtmosphereOzoneProfile(altitude); // 臭氧密度。
        depth += float3(rayleigh, mie, ozone) * stepLength; // 累加密度乘段长。
        samplePosition += sunDirection * stepLength; // 前进。
    }
    return ogxAtmosphereTransmittance(air, depth); // 换成透过率。
}

// 天空辐射：沿视线做单次散射积分，包含地面遮挡与地面反弹。
float3 ogxAtmosphereSky(OgxAtmosphere air, float cameraAltitude, float3 viewDirection, float3 sunDirection, int steps)
{
    float3 origin = float3(0.0, air.planetRadius + max(cameraAltitude, 0.0), 0.0); // 相机放在行星正上方。
    float distanceToTop = ogxAtmosphereDistanceToTop(origin, viewDirection, air.atmosphereRadius); // 到层顶的距离。
    bool groundHit; // 视线是否打到地面。
    float distanceToGround = ogxAtmosphereDistanceToGround(origin, viewDirection, air.planetRadius, groundHit); // 到地面的距离。
    float maxDistance = distanceToTop; // 默认积到层顶。
    if (groundHit && distanceToGround < maxDistance) // 地面比层顶更近时积到地面。
    {
        maxDistance = distanceToGround; // 地面挡住后面的空气。
    }
    if (maxDistance <= 0.0) // 视线没有穿过大气。
    {
        return float3(0.0); // 返回黑色。
    }
    const int maxSteps = 12; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = maxDistance / float(count); // 每段长度。
    float3 scattered = float3(0.0); // 累积的散射光。
    float3 transmittance = float3(1.0); // 到当前段为止的透过率。
    float3 position = origin + viewDirection * (stepLength * 0.5); // 第一段中点。
    float nu = dot(viewDirection, sunDirection); // 视线与太阳夹角余弦。
    float rayleighPhase = ogxRayleighPhase(nu); // 瑞利相函数。
    float miePhase = ogxMiePhase(air.mieG, nu); // 米氏相函数。
    for (int i = 0; i < maxSteps; i++) // 逐段积分。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float altitude = length(position) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float3 sunTransmittance = ogxAtmosphereSunTransmittance(air, position, sunDirection, 3); // 阳光到这里还剩多少。
        float3 extinction = air.rayleighScattering * rayleigh + air.mieScattering * mie; // 这一段的消光系数。
        float3 inScatter = (air.rayleighScattering * (rayleigh * rayleighPhase) // 瑞利散射。
                          + air.mieScattering * (mie * miePhase)) // 米氏散射。
                          * sunTransmittance * air.sunIntensity; // 乘阳光透过率与强度。
        scattered += inScatter * transmittance * stepLength; // 按剩余透过率累加。
        transmittance *= exp(-extinction * stepLength); // 更新剩余透过率。
        position += viewDirection * stepLength; // 前进到下一段。
    }
    if (groundHit) // 视线落到地面时补一层地面反射。
    {
        float3 groundPosition = origin + viewDirection * maxDistance; // 地面交点。
        float3 groundNormal = normalize(groundPosition); // 球面法线。
        float3 sunTransmittance = ogxAtmosphereSunTransmittance(air, groundPosition, sunDirection, 3); // 地面处的阳光。
        float groundLight = max(dot(groundNormal, sunDirection), 0.0); // 地面受光余弦。
        scattered += air.sunIntensity * sunTransmittance * groundLight * 0.02; // 低反照率地面，避免抢走地形。
    }
    return max(scattered, float3(0.0)); // 数值误差不产生负颜色。
}

// 空气透视：相机到某个世界点的散射与透过率；地形、水面与云的远景都调用它。
float3 ogxAerialPerspective(OgxAtmosphere air, float cameraAltitude, float3 viewDirection, float distance,
                            float3 sunDirection, int steps, out float3 transmittance)
{
    transmittance = float3(1.0); // 默认没有遮挡。
    if (distance <= 0.0) // 零距离不产生空气透视。
    {
        return float3(0.0); // 没有散射。
    }
    float3 origin = float3(0.0, air.planetRadius + max(cameraAltitude, 0.0), 0.0); // 相机在行星正上方。
    const int maxSteps = 6; // 固定循环上限，远景不需要天空那么细。
    int count = min(max(steps, 1), maxSteps); // 按调用方要求减少段数。
    float stepLength = distance / float(count); // 每段长度。
    float3 scattered = float3(0.0); // 累积散射。
    float3 position = origin + viewDirection * (stepLength * 0.5); // 第一段中点。
    float nu = dot(viewDirection, sunDirection); // 视线与太阳夹角。
    float rayleighPhase = ogxRayleighPhase(nu); // 瑞利相函数。
    float miePhase = ogxMiePhase(air.mieG, nu); // 米氏相函数。
    for (int i = 0; i < maxSteps; i++) // 逐段积分。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float altitude = length(position) - air.planetRadius; // 采样点高度。
        float rayleigh = ogxAtmosphereDensityRayleigh(air, altitude); // 瑞利密度。
        float mie = ogxAtmosphereDensityMie(air, altitude); // 米氏密度。
        float3 sunTransmittance = ogxAtmosphereSunTransmittance(air, position, sunDirection, 2); // 阳光到这里的透过率。
        float3 extinction = air.rayleighScattering * rayleigh + air.mieScattering * mie; // 消光系数。
        float3 inScatter = (air.rayleighScattering * (rayleigh * rayleighPhase) // 瑞利散射。
                          + air.mieScattering * (mie * miePhase)) // 米氏散射。
                          * sunTransmittance * air.sunIntensity; // 阳光强度。
        scattered += inScatter * transmittance * stepLength; // 按剩余透过率累加。
        transmittance *= exp(-extinction * stepLength); // 更新透过率。
        position += viewDirection * stepLength; // 前进。
    }
    return max(scattered, float3(0.0)); // 返回这段空气的散射色。
}

// 太阳圆盘：视线越接近太阳方向越亮，边缘用平滑曲线收口。
float ogxSunDisc(float3 viewDirection, float3 sunDirection, float size, float hardness)
{
    float d = dot(viewDirection, sunDirection); // 与太阳方向的夹角余弦。
    float x = ogxSaturate((d - (1.0 - size)) * hardness); // 从中心到边缘的遮罩。
    float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
    return disc * disc; // 平方让边缘更收。
}

// iterationT 太阳圆盘：在圆盘遮罩上乘参考实现的暖白色，供原样对照。
float3 ogxItxSunDisc(float3 worldDir, float3 sunDir)
{
    float d = dot(worldDir, sunDir); // 与太阳方向的夹角余弦。
    float size = 5e-5; // 太阳角半径。
    float hardness = 4e4; // 边缘斜率。
    float disc = ogxCurve01(ogxSaturate((d - (1.0 - size)) * hardness)); // 参考实现的平滑曲线。
    disc *= disc; // 平方收边。
    return float3(1.1114, 0.9756, 0.9133) * disc; // 太阳的暖白色。
}

// 球面几何的另一种写法：只给半径与高度角余弦，省掉每次重建起点向量。
// 与旧 `shaders/gfx/atmosphere.glsl` 的算式逐项一致，供预计算查表的坐标映射使用。
float ogxSphereDistanceToTop(float r, float mu, float topRadius)
{
    float discriminant = r * r * (mu * mu - 1.0) + topRadius * topRadius; // 交点判别式。
    return max(-r * mu + sqrt(max(discriminant, 0.0)), 0.0); // 取朝向层顶一侧的根。
}

// 视线到大气层底的距离，解球面方程取近根。
float ogxSphereDistanceToBottom(float r, float mu, float bottomRadius)
{
    float discriminant = r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius; // 球面交点判别式。
    return max(-r * mu - sqrt(max(discriminant, 0.0)), 0.0); // 取靠近相机一侧的根。
}

// 判断一条朝下的视线是否真的打到地面球。
bool ogxSphereRayIntersectsGround(float r, float mu, float bottomRadius)
{
    return mu < 0.0 && r * r * (mu * mu - 1.0) + bottomRadius * bottomRadius >= 0.0; // 朝下且判别式非负才相交。
}

// 瑞利与米氏密度剖面：以二为底的指数衰减。
float ogxExponentialDensity(float expScale, float altitude)
{
    return exp2(expScale * altitude); // 高度越高密度越低。
}

// 臭氧密度剖面：转折高度以下一段斜线，以上另一段斜线。
float ogxAbsorptionDensity(float width, float4 profile, float altitude)
{
    return altitude < width ? profile.x * altitude + profile.y : profile.z * altitude + profile.w; // 两段线性剖面。
}

// 把零到一的比例映射到贴图像素中心，避免采到子图交界。
float ogxTexelCenterCoord(float x, float textureSize)
{
    return 0.5 / textureSize + x * (1.0 - 1.0 / textureSize); // 内缩半像素。
}

// 把子图内部比例映射到拼合大图坐标，子图在大图里也内缩半像素。
float ogxSubTextureCoord(float x, float originalSize, float combinedSize)
{
    return 0.5 / combinedSize + x * (originalSize / combinedSize - 1.0 / combinedSize); // 按子图尺寸缩放。
}

// 月亮轨道：由游戏时间、纬度与轨道倾角闭式算出月亮的世界方向，y 轴朝天。
float3 ogxMoonDirection(float time, float latitude, float pathRotation, float monthLength)
{
    float phi = radians(-latitude); // 观测点纬度，换算成弧度。
    float del = radians(pathRotation); // 月亮轨道相对天赤道的倾角。
    float t = time / 24000.0; // 时间换算成天。
    t *= 1.0 + 1.0 / monthLength; // 月亮每天比太阳多走一点，长期累积才产生月相与对齐。
    float h = t * 2.0 * OGX_PI - OGX_PI; // 时角，一整天转一圈。
    float sinH = sin(phi) * sin(del) + cos(phi) * cos(del) * cos(h); // 高度角正弦。
    float elevation = asin(clamp(sinH, -1.0, 1.0)); // 高度角；钳一下避免浮点误差让反正弦出非数。
    float cosH = cos(elevation); // 高度角余弦。
    float cosA = (sin(del) - sin(phi) * sinH) / max(cos(phi) * cosH, 1e-4); // 方位角余弦；分母加下限，避免两极附近除零。
    cosA = clamp(cosA, -1.0, 1.0); // 同样钳一下，防止浮点误差越界。
    float A = acos(cosA); // 方位角。
    if (sin(h) > 0.0) // 时角过午时镜像到另一半球。
    {
        A = 2.0 * OGX_PI - A;
    }
    return float3(cosH * sin(A), sinH, cosH * cos(A)); // 单位方向，y 轴朝天。
}

// 圆盘剖面：由阈值与斜率构成边缘平滑的圆盘，平方后边界更清楚。
float ogxDiscProfile(float a, float s, float h)
{
    float x = ogxSaturate((a - (1.0 - s)) * h); // 由阈值与斜率构成的圆盘剖面。
    float disc = x * x * (3.0 - 2.0 * x); // 平滑收口。
    return disc * disc; // 平方拉开明暗边界。
}

// 把半径夹进大气层范围内，越界时按最近的边界算。
float ogxClampRadius(float r, float bottomRadius, float topRadius)
{
    return clamp(r, bottomRadius, topRadius); // 下不低于地面、上不超过层顶。
}

// 安全开方：负零以下一律当零，避免浮点误差算出非数。
float ogxSafeSqrt(float a)
{
    return sqrt(max(a, 0.0)); // 负数开到零。
}

// 星场散列：把一个方向格打散成零到一的随机数。
// 与噪声模块的通用哈希只差搅动常数（三十一点三二），为保持旧星场分布而单独保留。
float ogxStarHash13(float3 p3)
{
    p3 = fract(p3 * 0.1031); // 先乘一个小数再取小数部分，打散整数格的规律。
    p3 += dot(p3, p3.zyx + 31.32); // 三个分量互相掺入，避免相邻格出现相近的值。
    return fract((p3.x + p3.y) * p3.z); // 合并三个分量，得到零到一。
}

// 噪声星场：把散列值低于阈值的格子压成零，剩下的当作星点原始亮度。
float ogxStarNoisyField(float3 samplePos, float threshold)
{
    float starVal = ogxStarHash13(samplePos); // 先取这个格的随机值。
    starVal = clamp(starVal / (1.0 - threshold) - threshold / (1.0 - threshold), 0.0, 1.0); // 阈值以下压到零，剩下归一化到零到一。
    return starVal; // 返回星点亮度。
}

// 稳定星场：只在整数格上取值，再用双线性插值平滑，避免相机移动时星点闪烁。
// 已知代价（Eclipse 原注释承认）：双线性插值会把单个星点拉成十字，这里按合同保留原写法。
float ogxStarStableField(float3 samplePos, float threshold)
{
    float fractX = fract(samplePos.x); // 当前点在横方向的格内偏移。
    float fractY = fract(samplePos.y); // 当前点在纵方向的格内偏移。
    float3 floorSample = floor(samplePos.xyz); // 所在整数格。
    float v1 = ogxStarNoisyField(floorSample, threshold); // 左下格的星点亮度。
    float v2 = ogxStarNoisyField(floorSample + float3(0.0, 1.0, 0.0), threshold); // 左上格。
    float v3 = ogxStarNoisyField(floorSample + float3(1.0, 0.0, 0.0), threshold); // 右下格。
    float v4 = ogxStarNoisyField(floorSample + float3(1.0, 1.0, 0.0), threshold); // 右上格。
    float starVal = v1 * (1.0 - fractX) * (1.0 - fractY) // 四角按格内偏移加权求和。
                  + v2 * (1.0 - fractX) * fractY // 左上权重。
                  + v3 * fractX * (1.0 - fractY) // 右下权重。
                  + v4 * fractX * fractY; // 右上权重。
    return starVal; // 平滑后的星点亮度。
}

// 彩色星场散列：只用二维坐标，正弦放大再取小数。
float ogxStarHash12(float2 co)
{
    return fract(sin(2.0 * OGX_PI * fract(dot(co.xy, float2(12.9898, 78.233)))) * 43758.5453); // 最常见的二维散列写法。
}

// 星温：把零到一的散列映射成色温，三次方让多数星星偏冷白、少数偏暖。
float ogxStarTemperature(float hash)
{
    return hash * hash * hash * (19000.0 - 5500.0) + 5500.0; // 色温范围五千五到一万九开尔文。
}

// 星面：把方向投到立方体的一面按格撒星，输出该方向的亮度与颜色。
float ogxStarPlane(float3 dir, out float3 starColor)
{
    float scale = 1.0 / 600.0; // 格子大小，越小星点越密。
    float2 basePos = dir.xy * (0.4 / scale) / max(1e-3, abs(dir.z)); // 投到这个面上并按深度缩放。
    starColor = float3(0.0); // 这个面的星色初值。
    float2 pos = floor(basePos); // 所在整数格。
    float2 center = pos + float2(0.5); // 格中心，用来算到星心的距离。
    float d = distance(basePos, center); // 当前采样点到星心的距离。
    basePos = floor(basePos); // 锁定到格，保证相机移动时星点不飘。
    float color = 0.0; // 这个面的星点亮度。
    if (ogxStarHash12(basePos.xy * scale) > 0.997) // 只有极少数格子有星。
    {
        float radius = 0.4; // 星点半径，越大越胖。
        float brightness = exp(-(d * d) / (2.0 * radius * radius)); // 高斯衰减，星心最亮。
        float r = ogxStarHash12(basePos.xy * 0.5); // 这颗星的随机亮度因子。
        color = r * (0.3 * sin(1.0 * (r * 5.0) + r) + 0.7) * brightness; // 亮度带一点随机起伏。
        starColor = 2.0 * ogxBlackbody(ogxStarTemperature(ogxStarHash12(center))); // 按格中心的散列取色温上色。
    }
    return color * pow(abs(dir.z), 2); // 按该面朝向加权，面边界处平滑过渡。
}

// 星盒：把方向分别当立方体三轴投影，叠出完整六面星场。
float ogxStarBox(float3 dir, out float3 starColor)
{
    float3 starColor1 = float3(0.0); // 第一组投影的星色。
    float3 starColor2 = float3(0.0); // 第二组投影的星色。
    float3 starColor3 = float3(0.0); // 第三组投影的星色。
    float color = ogxStarPlane(dir.xyz, starColor1) + ogxStarPlane(dir.yzx, starColor2) + ogxStarPlane(dir.zxy, starColor3); // 三组投影叠亮度。
    starColor = starColor1 + starColor2 + starColor3; // 三组投影叠星色。
    return sqrt(color); // 开方压一下亮度分布，与 Eclipse 一致。
}

// 白色稳定星场：返回星场亮度；星色固定为白，由调用方直接使用。
float ogxStarsStable(float3 viewPos, float brightness, float amount)
{
    float s = max(1.0 - ogxStarStableField(viewPos * 300.0, 0.99), 0.0); // 采样密度三百、阈值零点九九与 Eclipse 相同。
    return brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 彩色星盒星场：返回亮度并由 `starColor` 回填星色，调用方按需要相乘。
float ogxStarsColored(float3 viewPos, float brightness, float amount, out float3 starColor)
{
    starColor = float3(1.0); // 星色由星盒回填，这里先给初值。
    float s = max(1.0 - ogxStarBox(viewPos, starColor), 0.0); // 彩色星盒星场。
    return 75.0 * brightness * exp(s * -20.0 * (1.0 / amount)); // 系数与 Eclipse 相同。
}

// 把视线方向绕太阳轴旋转对齐天球：罗德里格旋转公式，太阳方向由调用方传入。
// 这样星场会跟着太阳的年周期转，而不是固定在天球上。
float3 ogxAlignToSunAxis(float3 worldDir, float3 sunVector)
{
    float cosine = dot(sunVector, float3(0.0, 0.0, 1.0)); // 太阳轴与参考轴夹角余弦。
    float3 axis = cross(sunVector, float3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
    return cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式对齐星场。
}

// 真实月亮圆盘：角半径由尺寸档位换算，档位越大圆盘越大。
float ogxMoonDiscReal(float3 worldDir, float3 moonDir, float sizeSetting)
{
    float moonSize = 0.999 + (10.0 - sizeSetting) * 0.0001; // 档位越大圆盘越大。
    return ogxDiscProfile(dot(worldDir, moonDir), 1.0 - moonSize, 1.0 / (1.0 - moonSize)); // 用圆盘剖面收边。
}

// 默认月亮圆盘：比太阳更硬、更小的圆盘。
float ogxMoonDiscDefault(float3 worldDir, float3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 5e-5, 1e5); // 默认月亮更硬更小。
}

// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float ogxMoonDiscReflection(float3 worldDir, float3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 0.0025, 300.0); // 反射用更大的角半径与更软的边缘。
}

// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ogxSkyProject` 互为逆。
// `tileSize` 是单张面的边长；结果不带屏幕偏移，由调用方按自己的贴图布局追加。
float3 ogxSkyUnproject(float2 texel, float tileSize)
{
    float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
    float3 direction = float3(0.0); // 待求的世界方向。
    if (texel.x < tileSize) // 第一张面，朝横轴正负。
    {
        direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else if (texel.x < 2.0 * tileSize) // 第二张面，朝纵轴正负。
    {
        direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else // 第三张面，朝深度轴正负。
    {
        direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
        direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
    }
    return normalize(direction); // 单位世界方向。
}

// 把一个世界方向投到天空盒三维贴图上，与 `ogxSkyUnproject` 互为逆。
float2 ogxSkyProject(float3 dir, float tileSize)
{
    float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
    float3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
    float2 texel; // 待求的纹素坐标。
    if (adir.x > adir.y && adir.x > adir.z) // 横分量最大时用第一张面。
    {
        dir /= adir.x; // 归一化主轴分量。
        texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
    }
    else if (adir.y > adir.x && adir.y > adir.z) // 纵分量最大时用第二张面。
    {
        dir /= adir.y; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
    }
    else // 否则用第三张面。
    {
        dir /= adir.z; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
        texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
    }
    return texel; // 返回纹素坐标，屏幕偏移由调用方追加。
}

// 等距圆柱投影：把世界方向换成经纬度贴图坐标。
// 与 `ogxSkyProject` 的差别是贴图布局不同：这里是左右铺经度、上下铺纬度的整张天球图，
// 六面天空盒用的是 3×2 的瓦片图集；两套布局不能混用。`y` 零在正下方、一在正上方。
float2 ogxSkyEquirect(float3 direction)
{
    float longitude = clamp(ogxAtan2(float2(-direction.z, -direction.x)), -OGX_PI, OGX_PI); // 绕竖直轴的角度，正面为零。
    float latitude = asin(clamp(direction.y, -1.0, 1.0)); // 高度角，正上为正。
    return float2(longitude * (0.5 / OGX_PI) + 0.5, latitude * (1.0 / OGX_PI) + 0.5); // 归一到零到一。
}

// 天空云图坐标：经纬坐标先夹进贴图，再按调用方给的子图布局换成纹素坐标。
// 为什么布局要显式传入：参考光影把云图塞在整屏缓冲的一个小角落里，位置与边长随分辨率变化；
// 库里只保留“方向到子图坐标”的换算，具体放在哪由宿主决定，换布局不必改算法。
// `texelSize` 是整张贴图的纹素大小，`origin` 是子图左上角的纹素坐标，`tile` 是子图边长。
float2 ogxSkyCloudAtlasCoord(float3 direction, float2 texelSize, float2 origin, float tile)
{
    float2 p = clamp(ogxSkyEquirect(direction), float2(0.0), float2(1.0)); // 经纬坐标夹进子图范围。
    return p * tile * texelSize + origin * texelSize; // 子图内部按纹素换算到整图坐标。
}

// 读天空云图：按方向取对应经纬度的云颜色与覆盖率，四个通道原样返回。
// `skyTex` 是显式传入的采样器，库不绑定任何宿主纹理；过滤方式由调用方设置。
float4 ogxSkyCloudsFromTex(Sampler2D skyTex, float3 direction, float2 texelSize, float2 origin, float tile)
{
    float2 uv = ogxSkyCloudAtlasCoord(direction, texelSize, origin, tile); // 方向换成子图内的纹理坐标。
    return skyTex.SampleLevel(uv, 0.0); // 零号层级，不做各向异性过滤。
}

// 按粗糙度收拢的天空云图采样：粗糙度越大，靠近天顶的云越向观测方向压缩。
// 为什么按高度分界：地平线附近的云本来就叠在一起，粗糙度只该影响头顶那片，
// 否则远处的云会被整片抹平。`roughness` 零到一，由材质粗糙度或模糊强度给出。
float4 ogxSkyCloudsFromTexLod(Sampler2D skyTex, float3 direction, float2 texelSize, float2 origin, float tile,
    float roughness)
{
    float2 p = ogxSkyEquirect(direction); // 经纬坐标。
    roughness = 1.0 - pow(1.0 - roughness, 3.0); // 三次曲线让低粗糙度变化更细。
    float high = min(max(p.y - 0.5, 0.0) * 50.0, 1.0); // 只有天顶那半边的云参与收拢。
    p = lerp(p, (p - 0.5) * (1.0 - roughness) + 0.5, high); // 按粗糙度把坐标朝中心压缩。
    p = clamp(p * 2.0 - 1.0, float2(-1.0), float2(1.0)) * 0.5 + 0.5; // 压缩后再夹一次，边缘不越界。
    return skyTex.SampleLevel(p * tile * texelSize + origin * texelSize, 0.0); // 取子图内的颜色。
}

// 极光：夜晚高空的缓慢帘幕，雨天被云遮挡；`tint` 为正偏绿、为负偏蓝紫。
float3 ogxAurora(float3 color, float3 direction, float3 sunDirection, float time, float wetness, float tint, float strength)
{
    float night = 1.0 - smoothstep(-0.2, 0.1, sunDirection.y); // 太阳越低夜色越浓，极光越亮。
    float ripple = 0.5 + 0.5 * sin(direction.x * 6.0 + time * 0.02) * sin(direction.z * 5.0 - time * 0.015); // 两个方向的正弦交叉出缓慢起伏。
    float curtain = pow(max(0.0, sin(direction.x * 18.0 + ripple * 3.0)), 8.0); // 帘幕随位置起伏、随时间缓慢移动。
    float3 auroraColor = lerp(float3(0.12, 0.16, 0.50), float3(0.08, 0.35, 0.20), 0.5 + 0.5 * tint); // 极光颜色：正值偏绿、负值偏蓝紫。
    return color + auroraColor * curtain * smoothstep(0.1, 0.5, direction.y) * (1.0 - wetness) * night * strength; // 帘幕只露在高空，雨云之下熄灭。
}

// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
float3 ogxRainbow(float3 color, float3 direction, float3 sunDirection, float wetness, float strength)
{
    float angle = acos(clamp(dot(direction, -sunDirection), -1.0, 1.0)); // 与背太阳方向的夹角。
    float offset = (angle - 0.733) / 0.018; // 相对约四十二度彩虹角的偏移。
    float band = exp(-offset * offset); // 窄带：只用乘法构成，避开对负数取幂的未定义结果。
    float3 spectrum = 0.5 + 0.5 * cos((angle - 0.72) * 120.0 + float3(0.0, 2.1, 4.2)); // 角度到红橙黄绿的彩色谱。
    return color + spectrum * band * wetness * (1.0 - wetness) * smoothstep(0.0, 0.1, direction.y) * strength; // 只在雨停后仍湿润时出现。
}

// 钱德拉塞卡近似：各项同性散射的倍增因子，反照率越高、余弦越大越亮。
float3 ogxChandrasekharH(float3 albedo, float a)
{
    float3 R = sqrt(float3(1.0) - albedo); // 单次散射反照率的平方根。
    float3 r = (1.0 - R) / (1.0 + R); // 反射率比值。
    float3 h = r + (0.5 - r * a) * log((1.0 + a) / a); // 钱德拉塞卡近似。
    h *= albedo * a; // 乘反照率与余弦项。
    return 1.0 / (1.0 - h); // 取倒数得到倍增。
}

// 行星表面双向反射：入射与出射两侧各算一次钱德拉塞卡近似，再除以相函数分母。
float3 ogxPlanetBrdf(float3 albedo, float3 normal, float3 eyeDir, float3 lightDir)
{
    float NdotL = dot(normal, lightDir); // 法线与光方向夹角余弦。
    float NdotV = dot(normal, eyeDir); // 法线与视线夹角余弦。
    albedo *= clamp(NdotL, 0.0, 1.0) * clamp(NdotL, 0.0, 1.0) * (3.0 - 2.0 * clamp(NdotL, 0.0, 1.0)); // 反照率按入射角衰减。
    float3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 两侧近似与相函数分母。
    return clamp(color, 0.0, 1.0); // 夹到合理范围。
}

// 行星环带噪声：五层噪声叠出环带细缝，返回已经去掉偏移的累加值。
float ogxPlanetRingNoise(float position, Sampler2D noiseTexture)
{
    const float octAlpha = 0.5; // 每层噪声的权重衰减。
    const float octScale = 4.0; // 每层频率放大。
    const float octShift = (octAlpha / octScale) / 5.0; // 层间偏移。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 当前层权重。
    for (int i = 0; i < 5; i++) // 五层噪声叠出环带细缝。
    {
        accum += alpha * noiseTexture.SampleLevel(float2(position, 0.0), 0.0).z; // 读噪声的第三通道。
        position = position * octScale; // 抬高频率。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift - 0.1; // 加上层间偏移并减去阈值。
}

// Eclipse 的瑞利相函数：Elek 2009 的线性近似，已经除以四派做能量守恒。
float ogxEclipseSkyRayleighPhase(float cosTheta)
{
    return cosTheta * (0.1 * OGX_INV_PI) + 0.28 * OGX_INV_PI; // 参考实现把两个常数都乘 1/pi。
}

// Eclipse 的米氏相函数：用 g 的平方与 1.5 次幂，和 Henyey-Greenstein 不是同一公式。
float ogxEclipseSkyMiePhase(float cosTheta, float g)
{
    float gg = g * g; // 先算 g 的平方。
    return (gg * -0.25 + 0.25) * OGX_INV_PI * pow(-(2.0 * g) * cosTheta + (gg + 1.0), -1.5); // 参考实现的负指数。
}

// Eclipse 的相函数对：第一分量瑞利，第二分量米氏。
float2 ogxEclipseSkyPhase(float cosTheta, float g)
{
    return float2(ogxEclipseSkyRayleighPhase(cosTheta), ogxEclipseSkyMiePhase(cosTheta, g));
}

// Eclipse 的大气密度：瑞利与米氏共用一条指数，臭氧用两段指数围出峰值。
// `planetRadius` 与 `scaleHeights` 由调用方给出，默认是 6731 公里与 8/1.2 公里。
float3 ogxEclipseSkyDensity(float centerDistance, float planetRadius, float2 scaleHeights)
{
    float2 inverseScaleHeights = 1.0 / scaleHeights; // 标高倒数。
    float2 rayleighMie = exp(centerDistance * -inverseScaleHeights + planetRadius * inverseScaleHeights); // 瑞利与米氏。
    float ozone = exp(-max(0.0, (35000.0 - centerDistance) - planetRadius) * (1.0 / 5000.0)) // 臭氧上边界。
                * exp(-max(0.0, (centerDistance - 35000.0) - planetRadius) * (1.0 / 15000.0)); // 臭氧下边界。
    return float3(rayleighMie, ozone); // 三个分量对应三种介质。
}

// Eclipse 的大气质量：沿视线固定步数积分密度，步长由射线长度决定。
float3 ogxEclipseSkyAirmass(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights)
{
    float stepSize = rayLength * (1.0 / steps); // 每步长度。
    float3 increment = direction * stepSize; // 每步位移。
    position += increment * 0.5; // 从半步处开始，避开端点。
    float3 airmass = float3(0.0); // 累积密度。
    for (int i = 0; i < steps; ++i, position += increment) // 固定步数。
    {
        airmass += ogxEclipseSkyDensity(length(position), planetRadius, scaleHeights); // 逐点累积密度。
    }
    return airmass * stepSize; // 乘步长得到光学路径。
}

// Eclipse 的大气质量射线版：先求与大气顶层的交点，再调用固定步数版。
float3 ogxEclipseSkyAirmassRay(float3 position, float3 direction, float steps,
    float planetRadius, float2 scaleHeights, float atmosphereRadius)
{
    float rayLength = dot(position, direction); // 投影长度。
    rayLength = rayLength * rayLength + atmosphereRadius * atmosphereRadius - dot(position, position); // 判别式。
    if (rayLength < 0.0) return float3(0.0); // 射线不碰大气。
    rayLength = sqrt(rayLength) - dot(position, direction); // 到交点的距离。
    return ogxEclipseSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 交给固定步数版。
}

// Eclipse 的光学厚度：三种介质的消光系数乘各自的大气质量。
float3 ogxEclipseSkyOpticalDepth(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights,
    float3 coefficientRayleigh, float3 coefficientMie, float3 coefficientOzone)
{
    float3 airmass = ogxEclipseSkyAirmass(position, direction, rayLength, steps, planetRadius, scaleHeights); // 三种介质的路径。
    return coefficientRayleigh * airmass.x + coefficientMie * airmass.y + coefficientOzone * airmass.z; // 按介质加权。
}

// Eclipse 的透过率：把光学厚度换成以二为底的指数，和参考实现的 `exp(-od/ln2)` 等价。
float3 ogxEclipseSkyTransmittance(float3 position, float3 direction, float rayLength, float steps,
    float planetRadius, float2 scaleHeights,
    float3 coefficientRayleigh, float3 coefficientMie, float3 coefficientOzone)
{
    float3 depth = ogxEclipseSkyOpticalDepth(position, direction, rayLength, steps, planetRadius, scaleHeights,
        coefficientRayleigh, coefficientMie, coefficientOzone); // 先算光学厚度。
    return exp2(-depth); // exp(-depth/ln2) 与 exp2(-depth) 等价。
}

#endif
