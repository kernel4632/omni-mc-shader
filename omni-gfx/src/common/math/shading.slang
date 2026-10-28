// 数学模块材质与求交：GGX、菲涅尔、黑体色温、射线与包围盒求交、相函数。
// 调用位置：由 `common/math.slang` 内联引入，表面、大气与反射模块共用。
// 可复制示例：`float3 c = ogxBlackbody(6500.0);`
// 设计原因与取舍：这些函数只做几何与光学近似，不读取任何宿主状态。

// --- 算法说明与边界 ---
// GGX 分布的分母在粗糙度接近零时夹紧，避免高光出现无穷大。
// Schlick 菲涅耳在掠射角趋向一，可见性项把微表面遮挡折进分母。
// Burley 漫反射在掠射角变亮，粗糙度越高越明显；高光合成把三项相乘。
// 黑体色按普朗克轨迹分段拟合，色温超出范围时夹到端点。
// 光照模型：GGX 分布、Schlick 菲涅耳、可见性、Burley 漫反射、高光合成、黑体色与射线求交。
// GGX 与可见性按参考常数实现；Burley 在掠射角变亮，黑体色用普朗克轨迹拟合。
// 射线求交包括平面、球与包围盒，相位函数包括瑞利、米氏与 Henyey-Greenstein。


// --- 材质、黑体与光线求交 ---

// 沃尔特 GGX 分布：粗糙度越大，高光越散。
// 分母里的圆周率让分布在整个半球上积分为一，粗糙度平方控制峰值高度。
// 为什么不用更简单的半程高光：GGX 的长尾更接近真实金属的高光边缘。
float ogxDistributionGGX(float NdotH, float roughness)
{
    float roughness2 = roughness * roughness; // 先平方，后面峰值宽度与分母都用这一份。
    float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0; // 分母的二次项，粗糙度为零时退化成一。
    return roughness2 / (OGX_PI * k * k); // 峰值高度由粗糙度平方决定。
}

// 菲涅尔近似：掠射角反射强，正对时只剩基础反射率。
// 先把夹角转成“一减余弦”再取五次方，是为了让曲线在正对时平滑落到 f0。
// `f90` 是掠射时的上限，金属与电介质可以分别给不同的值。
float ogxFresnelSchlick(float VdotH, float f0, float f90)
{
    VdotH = 1.0 - VdotH; // 换成掠射程度，零是正对、一是贴着表面。
    float VdotH2 = VdotH * VdotH; // 五次方的中间量。
    return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH; // 从正对反射率平滑过渡到掠射上限。
}

// 可见性项：把入射与出射方向的遮挡相乘，采用粗糙度一半的常用近似。
// 半粗糙度是实时渲染的常用折中：完全按 Smith 理论算更贵，画面差异很小。
// 分母在正对时接近一，掠射时变大，正好压住菲涅尔的亮边。
float ogxVisibilitySchlick(float NdotL, float NdotV, float roughness)
{
    float k = roughness * 0.5; // 半粗糙度是实时渲染的常用近似。
    return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k)); // 入射与出射遮挡相乘。
}

// 布利漫反射：能量在掠射时更集中，避免边缘死黑。
// 两个菲涅尔项分别描述光和视线方向的散射，乘起来比 Lambert 多一层柔边。
// 最后乘 1/π 是把反射率积分归一化，和 GGX 共用同一套能量口径。
float ogxDiffuseBurley(float3 n, float3 v, float3 l, float roughness)
{
    float3 h = normalize(v + l); // 半程方向，位置在视线与光线中间。
    float LdotH = ogxSaturate(dot(l, h)); // 光线与半程方向的余弦。
    float NdotL = ogxSaturate(dot(n, l)); // 表面朝光程度。
    float NdotV = ogxSaturate(dot(n, v)); // 表面朝视线程度。
    float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH; // 掠射上限随粗糙度抬高。
    float lightScatter = ogxFresnelSchlick(NdotL, 1.0, f90); // 光方向的散射。
    float viewScatter = ogxFresnelSchlick(NdotV, 1.0, f90); // 视线方向的散射。
    return NdotL * lightScatter * viewScatter * OGX_INV_PI; // 归一化后的漫反射。
}

// 完整 GGX 高光：菲涅尔、可见性、分布三项相乘。
// 三项相乘是标准高光分解，顺序不影响结果，这里按参考的写法排。
// 调用方只要给法线、视线、光方向、粗糙度与基础反射率，不需要自己拆项。
float ogxSpecularGGX(float3 n, float3 v, float3 l, float roughness, float f0)
{
    float3 h = normalize(v + l);
    float NdotH = ogxSaturate(dot(n, h)); // 法线与半程方向的余弦。
    float LdotH = ogxSaturate(dot(l, h));
    float NdotL = ogxSaturate(dot(n, l));
    float NdotV = ogxSaturate(dot(n, v));
    float ggx = ogxFresnelSchlick(LdotH, f0, 1.0); // 菲涅尔项。
    ggx *= ogxVisibilitySchlick(NdotL, NdotV, roughness); // 几何遮挡项。
    ggx *= ogxDistributionGGX(NdotH, roughness); // 法线分布项。
    return ggx;
}

// 黑体色温拟合：先求色度横坐标与纵坐标，再转线性显示原色。
// 分界点四千开与两千二百二十二开来自原拟合的分段条件，不能省略。
// 两组横坐标多项式分别覆盖低温和高温，纵坐标再多一段低温分支，
// 因为单一多项式在两端会偏色，分段后星空与日落的色温才连续。
// 最后从 XYZ 转回 sRGB 并夹掉负值，负值只出现在拟合边缘，直接保留会变成黑块。
float3 ogxBlackbody(float temperature)
{
    static const float4 SPLINE_X_LOW = float4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910);
    static const float4 SPLINE_X_HIGH = float4(-3.0258469e9, 2.1070479e6, 0.2226347e3, 0.240390);
    static const float4 SPLINE_Y_LOW = float4(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    static const float4 SPLINE_Y_MID = float4(-0.9549476, -1.37418593, 2.09137015, -0.16748867);
    static const float4 SPLINE_Y_HIGH = float4(3.0817580, -5.87338670, 3.75112997, -0.37001483);
    float rt = 1.0 / temperature; // 多项式以倒色温为自变量。
    float rt2 = rt * rt; // 倒色温平方，供三次多项式复用。
    float4 coeffX = float4(rt2 * rt, rt2, rt, 1.0); // 三次项、二次项、一次项与常数。
    float x = dot(coeffX, temperature < 4000.0 ? SPLINE_X_LOW : SPLINE_X_HIGH); // 四千开分段求横坐标。
    float x2 = x * x; // 纵坐标多项式以横坐标为自变量。
    float4 coeffY = float4(x2 * x, x2, x, 1.0); // 纵坐标的三次项。
    float4 splineY = temperature < 2222.0 ? SPLINE_Y_LOW : (temperature < 4000.0 ? SPLINE_Y_MID : SPLINE_Y_HIGH); // 低温、中温、高温三段。
    float z = 1.0 / dot(coeffY, splineY); // 先算缩放，再还原色度分量。
    float3 xyz = float3(x * z, 1.0, z); // 色度坐标转三分量。
    xyz.z -= xyz.x + 1.0; // 由 x+y+z=1 反推 Z 分量。
    // 三列分别乘三个色度分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
    static const float3 XYZ_TO_SRGB_0 = float3(3.24097, -0.96924, 0.05563);
    static const float3 XYZ_TO_SRGB_1 = float3(-1.53738, 1.87597, -0.20398);
    static const float3 XYZ_TO_SRGB_2 = float3(-0.49861, 0.04156, 1.05697);
    float3 rgb = XYZ_TO_SRGB_0 * xyz.x + XYZ_TO_SRGB_1 * xyz.y + XYZ_TO_SRGB_2 * xyz.z; // 三列按顺序相加。
    return max(rgb, float3(0.0)); // 拟合边缘的负值夹到零。
}

// 射线与平面求交：射线与平面法线接近平行时返回极远处的默认交点，避免除零。
// 阈值一万分之一弧度：再小的夹角在屏幕上已经看不出交点移动，继续除会放大浮点误差。
// 默认交点放在一亿米外，调用方仍能拿到一个有限坐标，不会传播无穷大。
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
// 用一亿与负一亿当哨兵：调用方只比较两个分量就能判断有没有交点，不必再加布尔返回值。
// 判别式只开一次方，进入与离开共用同一个偏移，少两次重复计算。
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
// 方向分量接近零时换成百万分之一：这样倒数仍是有限数，区间会自然落到盒外或全包。
// 先取每轴的近远再求最大最小，是标准的逐轴区间方法，不需要逐面判断。
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
// 蓝光波长短、散射强，所以天空偏蓝；这里只保留角度项，波长权重交给大气模块。
// 常数 0.059683104 等于 3/(16π)，与参考实现逐位一致。
float ogxRayleighPhase(float nu) { return 0.059683104 * (nu * nu + 1.0); }

// 米氏相函数：康奈特-沙克形式，`g` 越大前向散射越集中。
// 康奈特-沙克比 HG 多一个“一加余弦平方”因子，太阳附近的亮晕更集中。
// 分母的 -1.5 次方来自相函数的解析积分，改指数会让太阳周围过亮或过暗。
float ogxMiePhase(float g, float nu)
{
    float gg = g * g;
    float k = 0.1193662 * (1.0 - gg) / (2.0 + gg);
    return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5);
}

// 亨耶-格林斯坦相函数在云与雾里共用；把除派拆成参数，是为了让 3.14 与圆周率两种精度都能逐位对照。
// 分母的负一点五次方来自相函数的解析积分，改指数会改变太阳附近的亮度分布。
// 亨耶-格林斯坦相函数：把除以圆周率的部分作为显式参数，方便参考包保留自己的 3.14 常数。
// 为什么参数化：云、雾与层状云参考实现的圆周率精度不同，统一常数会改变严格对照的数值。
float ogxHenyeyGreensteinPhase(float cosAngle, float g, float inversePi)
{
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * cosAngle) + (gg + 1.0), -1.5) * 0.25 * inversePi;
}

// 相函数与几何近似在文件前半段，闪电照明移到天气模块。
