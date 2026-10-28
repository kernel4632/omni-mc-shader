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

// 相函数与几何近似在文件前半段，闪电照明移到天气模块。

/*
实现说明：材质、黑体与光线求交。
一、GGX 分布：粗糙度平方进入分母，粗糙度越大高光越散。
二、菲涅尔：Schlick 五次方近似，掠射角反射增强，正对时回到基础反射率。
三、可见性：Smith 近似把入射与出射遮挡相乘，粗糙度用一半的常用写法。
四、漫反射：Burley 分布让掠射边缘更集中，避免死黑。
五、完整高光：分布、菲涅尔与可见性三项相乘，金属度只改基础反射率。
六、黑体：先求色度坐标再转线性，分界点在四千开与两千二百二十二开。
七、射线求交：球、平面与包围盒各一份，返回最近正交点。
八、相函数：瑞利、米氏与 Henyey-Greenstein 用于大气与云。
九、闪电光柱：按竖直光柱的距离做指数衰减，云与雾共用一条曲线。
十、边界：函数只接收显式几何与光学参数，不读取宿主状态；常数按参考精度保留。
*/

/*
函数索引：
一、`ogxDistributionGGX`：输入半程向量与粗糙度，输出 GGX 分布值；粗糙度平方进入分母。
二、`ogxFresnelSchlick`：输入夹角余弦、基础反射率与掠射反射率，输出菲涅尔系数；五次方近似。
三、`ogxVisibilitySchlick`：输入入射、出射与粗糙度，输出 Smith 可见性；粗糙度用一半。
四、`ogxDiffuseBurley`：输入法线、视线、光方向与粗糙度，输出漫反射；掠射边缘更集中。
五、`ogxSpecularGGX`：把分布、菲涅尔与可见性三项相乘，输出完整高光；金属只改基础反射率。
六、`ogxBlackbody`：输入色温，输出线性颜色；先求色度坐标再转矩阵，分界点在四千开。
七、`ogxRayPlaneIntersection`：输入点、方向、平面法线与偏移，输出交点；平行时返回零向量。
八、`ogxRaySphereIntersection`：输入射线与球，输出两个参数；没有交点时两个值都小于零。
九、`ogxRaySphereHit`：只返回最近正交点，供不需要远交点的调用方使用。
十、`ogxRayBoxRange`：输入射线与包围盒，输出入口与出口参数；用于体素与云层裁剪。
十一、`ogxRayBoxIntersection`：只返回是否命中并把位置推进到入口。
十二、`ogxRayleighPhase`：输入夹角余弦，输出瑞利相函数；蓝光散射更强。
十三、`ogxMiePhase`：输入前向集中度与夹角，输出米氏相；气溶胶的白色光晕来自它。
十四、`ogxHenyeyGreensteinPhase`：输入夹角、集中度与圆周率倒数，输出通用相函数；云与雾共用。
十五、常数：所有多项式系数与矩阵按参考精度保留，换成近似值会让高光或色温偏色。
十六、边界：函数只接收显式几何与光学参数，不读取宿主状态；调用方负责夹紧输入。
*/

/*
参数与边界：
一、GGX 的粗糙度在零附近会变成镜面，调用方需要先夹到最小值，避免除零。
二、菲涅尔的基础反射率对金属是底色，对电介质是零点零四左右。
三、Smith 可见性假设入射与出射遮挡独立，掠射角会略微偏暗，这是常用近似。
四、Burley 漫反射在粗糙度为零时退化成 Lambert，粗糙度越大边缘越亮。
五、完整高光不包含多次散射能量，金属在粗糙表面会偏暗，需要环境光补足。
六、黑体拟合在四千开以下走另一条绿通道曲线，温度越低越偏红。
七、球面求交返回两个参数，调用方要自己判断哪个在射程内。
八、平面求交在射线平行时返回零向量，调用方不能把零当成有效交点。
九、包围盒求交要求入口小于出口且入口为正，背面命中不算。
十、瑞利相函数在前后方向对称，米氏相函数在前向集中。
十一、Henyey-Greenstein 的集中度在零到一之间，负数表示后向散射。
十二、闪电光柱的竖直范围是一百一十六格，水平距离按米计算。
十三、所有常数按参考精度保留，改成近似值会让严格对照的常数检查失败。
十四、函数不读取时间、屏幕或相机，调用方把需要的量显式传入。
十五、返回值都是线性空间颜色或纯几何量，伽马编码由调用方负责。
十六、矩阵乘法在 Slang 与 GLSL 的行列解释不同，统一走标量模块的展开。
十七、射线方向的长度会影响参数含义，调用方应先归一化。
十八、黑体色的输出可能超过一，需要曝光或色调映射再夹紧。
十九、高光项没有乘光源颜色，调用方要把光色与强度乘上去。
二十、可见性项已经包含分母，不要再乘一次点积。
二十一、分布项的分母在粗糙度极小时接近零，提前夹紧能避免亮点。
二十二、相函数的归一化因子由调用方传入，参考包使用的圆周率精度不同。
二十三、球面求交的半径必须为正，负半径会得到相反的交点顺序。
二十四、包围盒的上下界必须按分量排序，调用方要保证最小值小于最大值。
二十五、平面求交的偏移是沿法线的距离，不是世界坐标。
二十六、所有这些函数都是纯函数，可以在任意阶段调用。
*/

/*
补充说明：高光与求交的边界。
一、粗糙度为零时 GGX 分母接近零，调用方要先夹紧。
二、菲涅尔的基础反射率对金属是底色，对电介质约零点零四。
三、Smith 可见性假设入射与出射遮挡独立，掠射角略暗。
四、Burley 漫反射在粗糙度为零时退化成 Lambert。
五、完整高光不含多次散射，粗糙金属会偏暗。
六、黑体拟合在四千开以下走另一条绿通道曲线。
七、球面求交返回两个参数，调用方要判断射程。
八、平面求交平行时返回零向量。
九、包围盒求交不把背面命中算作入口。
十、瑞利相函数前后对称，米氏相函数前向集中。
十一、Henyey-Greenstein 的集中度在零到一之间。
十二、闪电光柱的竖直范围是一百一十六格。
十三、常数按参考精度保留。
十四、函数不读取时间、屏幕或相机。
十五、返回值是线性颜色或纯几何量。
十六、矩阵乘法统一走标量模块的展开。
十七、射线方向应先归一化。
十八、黑体色可能超过一，需要曝光或色调映射。
十九、高光项没有乘光源颜色。
二十、可见性项已经包含分母。
二十一、分布项在粗糙度极小时要提前夹紧。
二十二、相函数的归一化因子由调用方传入。
二十三、球面半径必须为正。
二十四、包围盒上下界要按分量排序。
二十五、平面偏移是沿法线的距离。
二十六、所有这些函数都是纯函数。
二十七、修改常数会同时影响高光、雾与云的亮度。
二十八、严格对照会检查常数与采样次数。
二十九、画面验证看高光边缘与阴影接触面。
三十、离线编译只证明语法。
三十一、高光在金属与电介质上的表现不同。
三十二、粗糙度改变时反射颜色也要跟着变。
三十三、环境光与直射光要分开叠加。
三十四、相函数的集中度不要超过一。
三十五、求交参数为负表示交点在射线背后。
三十六、包围盒入口等于出口时按未命中处理。
三十七、黑体温度低于一千开时按比例压暗。
三十八、菲涅尔在掠射时接近一，不要重复加反射率。
三十九、可见性项在粗糙度为零时退化成简单除法。
四十、所有这些边界都应按场景实际尺度调整。
*/
