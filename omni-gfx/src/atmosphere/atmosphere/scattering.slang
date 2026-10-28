/*
大气子文件：臭氧与密度剖面、光线与球壳求交、光学深度与单次散射。
调用位置：由 `atmosphere/atmosphere.slang` 内联，供天空查表与空气透视使用。
可复制示例：`vec3 sky = ogxAtmosphereSky(ogxAtmosphereEarth(), 0.0, viewDir, sunDir, 16);`
设计原因与取舍：常数集中在地球默认值，其他行星可换结构体字段；步数与方向全部显式传入。
    地球默认常数与单次散射入口放在主文件，这里只保留难读的剖面与求交算法。
*/
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
