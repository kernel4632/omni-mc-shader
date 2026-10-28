// 太阳圆盘：视线越接近太阳方向越亮，边缘用平滑曲线收口。
float ogxSunDisc(float3 viewDirection, float3 sunDirection, float size, float hardness)
{
    float d = dot(viewDirection, sunDirection); // 与太阳方向的夹角余弦。
    float x = ogxSaturate((d - (1.0 - size)) * hardness); // 从中心到边缘的遮罩。
    float disc = x * x * (3.0 - 2.0 * x); // 平滑曲线。
    return disc * disc; // 平方让边缘更收。
}

// iterationT 太阳圆盘：在圆盘遮罩上乘参考实现的暖白色，供原样对照。
float3 ogxSunDiscFixed(float3 worldDir, float3 sunDir)
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
        starColor = 2.0 * ogxBlackbodyApprox(ogxStarTemperature(ogxStarHash12(center))); // 按格中心的散列取色温上色。
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
