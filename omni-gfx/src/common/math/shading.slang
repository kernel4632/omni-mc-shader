// 数学模块材质与求交：GGX、菲涅尔、黑体色温、射线与包围盒求交、相函数。
// 调用位置：由 `common/math.slang` 内联引入，表面、大气与反射模块共用。
// 可复制示例：`float3 c = ogxBlackbody(6500.0);`
// 设计原因与取舍：这些函数只做几何与光学近似，不读取任何宿主状态。

// --- 材质、黑体与光线求交 ---

// 沃尔特 GGX 分布：粗糙度越大，高光越散。
float ogxDistributionGGX(float NdotH, float roughness)
{
    float roughness2 = roughness * roughness;
    float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0;
    return roughness2 / (OGX_PI * k * k);
}

// 菲涅尔近似：掠射角反射强，正对时只剩基础反射率。
float ogxFresnelSchlick(float VdotH, float f0, float f90)
{
    VdotH = 1.0 - VdotH;
    float VdotH2 = VdotH * VdotH;
    return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH;
}

// 可见性项：把入射与出射方向的遮挡相乘，采用粗糙度一半的常用近似。
float ogxVisibilitySchlick(float NdotL, float NdotV, float roughness)
{
    float k = roughness * 0.5;
    return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
}

// 布利漫反射：能量在掠射时更集中，避免边缘死黑。
float ogxDiffuseBurley(float3 n, float3 v, float3 l, float roughness)
{
    float3 h = normalize(v + l);
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
    float lightScatter = ogxFresnelSchlick(NdotL, 1.0, f90);
    float viewScatter = ogxFresnelSchlick(NdotV, 1.0, f90);
    return NdotL * lightScatter * viewScatter * OGX_INV_PI;
}

// 完整 GGX 高光：菲涅尔、可见性、分布三项相乘。
float ogxSpecularGGX(float3 n, float3 v, float3 l, float roughness, float f0)
{
    float3 h = normalize(v + l);
    float NdotH = ogxSaturate(dot(n, h));
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float ggx = ogxFresnelSchlick(LdotH, f0, 1.0);
    ggx *= ogxVisibilitySchlick(NdotL, NdotV, roughness);
    ggx *= ogxDistributionGGX(NdotH, roughness);
    return ggx;
}

// 黑体色温拟合：先求色度横坐标与纵坐标，再转线性显示原色。
// 分界点四千开与两千二百二十二开来自原拟合的分段条件，不能省略。
float3 ogxBlackbody(float temperature)
{
    static const float4 SPLINE_X_LOW = float4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910);
    static const float4 SPLINE_X_HIGH = float4(-3.0258469e9, 2.1070479e6, 0.2226347e3, 0.240390);
    static const float4 SPLINE_Y_LOW = float4(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    static const float4 SPLINE_Y_MID = float4(-0.9549476, -1.37418593, 2.09137015, -0.16748867);
    static const float4 SPLINE_Y_HIGH = float4(3.0817580, -5.87338670, 3.75112997, -0.37001483);
    float rt = 1.0 / temperature;
    float rt2 = rt * rt;
    float4 coeffX = float4(rt2 * rt, rt2, rt, 1.0);
    float x = dot(coeffX, temperature < 4000.0 ? SPLINE_X_LOW : SPLINE_X_HIGH);
    float x2 = x * x;
    float4 coeffY = float4(x2 * x, x2, x, 1.0);
    float4 splineY = temperature < 2222.0 ? SPLINE_Y_LOW : (temperature < 4000.0 ? SPLINE_Y_MID : SPLINE_Y_HIGH);
    float z = 1.0 / dot(coeffY, splineY);
    float3 xyz = float3(x * z, 1.0, z);
    xyz.z -= xyz.x + 1.0;
    // 三列分别乘三个色度分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
    static const float3 XYZ_TO_SRGB_0 = float3(3.24097, -0.96924, 0.05563);
    static const float3 XYZ_TO_SRGB_1 = float3(-1.53738, 1.87597, -0.20398);
    static const float3 XYZ_TO_SRGB_2 = float3(-0.49861, 0.04156, 1.05697);
    float3 rgb = XYZ_TO_SRGB_0 * xyz.x + XYZ_TO_SRGB_1 * xyz.y + XYZ_TO_SRGB_2 * xyz.z;
    return max(rgb, float3(0.0));
}

// 射线与平面求交：射线与平面法线接近平行时返回极远处的默认交点，避免除零。
float3 ogxRayPlaneIntersection(float3 origin, float3 direction, float3 normal)
{
    float rayPlaneAngle = dot(direction, normal);
    float planeRayDistance = 1e8;
    float3 intersection = direction * planeRayDistance;
    if (rayPlaneAngle > 0.0001 || rayPlaneAngle < -0.0001)
    {
        planeRayDistance = dot(-origin, normal) / rayPlaneAngle;
        intersection = origin + direction * planeRayDistance;
    }
    return intersection;
}

// 射线与球求交：返回进入和离开两个距离，无交点时返回一正一负的极值。
float2 ogxRaySphereIntersection(float3 origin, float3 direction, float radius){
    float b = dot(origin, direction);
    float c = -radius * radius + dot(origin, origin);
    float d = b * b - c;
    float2 intersection = float2(1e10, -1e10);
    if (d >= 0.0)
    {
        d = sqrt(d);
        intersection = float2(-b - d, -b + d);
    }
    return intersection;
}

// 射线与球求交的另一种约定：没打中时返回两个负一，命中时返回进入与离开的距离。
// 为什么保留两个版本：`ogxRaySphereIntersection` 用极大值表示未命中，适合直接取近交点；
// 这个版本照参考实现用负一当哨兵，调用方可以只判断一个分量就知道要不要继续算。
// 球心固定在原点，`position` 是射线的起点，`direction` 必须已经归一化。
float2 ogxRaySphereHit(float3 position, float3 direction, float radius)
{
    float PoD = dot(position, direction); // 起点在射线方向上的投影。
    float radiusSquared = radius * radius; // 半径平方。
    float delta = PoD * PoD + radiusSquared - dot(position, position); // 球面方程的判别式。
    if (delta < 0.0) // 判别式为负说明射线擦不到球。
    {
        return float2(-1.0); // 两个负一表示未命中。
    }
    delta = sqrt(delta); // 判别式开方，得到两个交点相对最近点的偏移。
    return -PoD + float2(-delta, delta); // 先减投影再加减偏移，得到两个距离。
}

// 射线与轴对齐包围盒求交：返回进入与离开的距离。
// 三个轴分别解一次区间，再把区间求交集；无交点时返回一正一负的极值。
// `boxSize` 是盒子的半边长，盒子以 `origin` 所在坐标系的原点为中心。
float2 ogxRayBoxRange(float3 origin, float3 direction, float3 boxSize)
{
    float3 safeDirection = float3(abs(direction.x) < 1e-6 ? 1e-6 : direction.x,
                                  abs(direction.y) < 1e-6 ? 1e-6 : direction.y,
                                  abs(direction.z) < 1e-6 ? 1e-6 : direction.z);
    float3 inverseDirection = 1.0 / safeDirection;
    float3 t0 = (-boxSize - origin) * inverseDirection;
    float3 t1 = (boxSize - origin) * inverseDirection;
    float3 near = min(t0, t1);
    float3 far = max(t0, t1);
    float enter = max(max(near.x, near.y), near.z);
    float leave = min(min(far.x, far.y), far.z);
    return leave >= enter ? float2(enter, leave) : float2(1e10, -1e10);
}

// 射线与包围盒求交的便捷版：命中时返回进入距离，未命中返回负一。
float ogxRayBoxIntersection(float3 origin, float3 direction, float3 boxSize)
{
    float2 range = ogxRayBoxRange(origin, direction, boxSize);
    return range.x <= range.y && range.y > 0.0 ? range.x : -1.0;
}

// 瑞利相函数：天空散射近似各向同性，常数是十六分之三除以圆周率。
float ogxRayleighPhase(float nu) { return 0.059683104 * (nu * nu + 1.0); }

// 米氏相函数：康奈特-沙克形式，`g` 越大前向散射越集中。
float ogxMiePhase(float g, float nu)
{
    float gg = g * g;
    float k = 0.1193662 * (1.0 - gg) / (2.0 + gg);
    return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5);
}

// 亨耶-格林斯坦相函数：把除以圆周率的部分作为显式参数，方便参考包保留自己的 3.14 常数。
// 为什么参数化：云、雾与层状云参考实现的圆周率精度不同，统一常数会改变严格对照的数值。
float ogxHenyeyGreensteinPhase(float cosAngle, float g, float inversePi)
{
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * cosAngle) + (gg + 1.0), -1.5) * 0.25 * inversePi;
}

// 闪电光柱照明：把闪电当成一根竖直光柱，按距离做指数衰减。
// 云与雾的媒体结构字段不同，纯计算放在这里，两边只负责从自己的结构取出参数。
float3 ogxLightningGlow(float3 relativePos, float3 lightningPosition, float intensity, float strength,
    float lightDistance, float falloff)
{
    if (intensity <= 0.0) return float3(0.0); // 没有闪电事件时不加。
    float3 boltPos = float3(lightningPosition.x, clamp(relativePos.y, lightningPosition.y, lightningPosition.y + 116.0), lightningPosition.z); // 光柱同一水平位置。
    float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return float3(0.55, 0.65, 0.9) * (lightningLight * intensity * strength); // 冷色闪光。
}
