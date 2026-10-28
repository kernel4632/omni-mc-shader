/*
Omni 通用图形库云模块：单层球面云的求交、程序化密度、朝阳光照、沿视线步进与云影取样。
调用位置：天空与水面反射里的球面云；Minecraft 光影由 `/omni-gfx/cloud/cloud.glsl` 引入。
平面云自己的密度、扭曲与光照在 `cloud/planar.slang`，本文件不再混放两套云算法。
可复制示例：
    OgxCloudLayer l = ogxCloudLayerDefault(); // 取默认云层。
    float4 c = ogxCloudMarch(l, camKm, viewDir, sunDir, sunColor, skyColor, j, 24); // 步进一层云。
    float k = ogxCloudShadow(l, groundKm, sunDir); // 取地面云影。
设计原因与取舍：
    形状来自迁移前 GLSL 原型的球面云坐标、云量重映射与光照步进，
    把纹理采样换成程序化值噪声，因此不需要额外贴图也能独立出图。
    只用一层云，但加入低频云量图、域扭曲和随高度剪切，专门消除平面云层的重复条纹。
    密度与光照步数全部由调用方传入，库不读取天气、选项或宿主状态。
*/
#ifndef OGX_CLOUD_INCLUDED
#define OGX_CLOUD_INCLUDED

// 噪声提供云团与细节，数学提供球面求交与相函数。
#include "../common/math.slang"
// 噪声提供哈希、分形与云团细节。
#include "../common/noise.slang"

// 一层体积云的参数；不同云层换字段即可复用同一套步进。
struct OgxCloudLayer
{
    float bottom; // 云底高度，公里。
    float top; // 云顶高度，公里。
    float planetRadius; // 行星半径，公里，用来把平面云层弯成球壳。
    float coverage; // 云量，零到一。
    float density; // 密度倍率。
    float detail; // 边缘侵蚀强度，零到一。
    float3 wind; // 水平风向与速度，公里。
};

// 默认云层：一百二十米到二百四十米，地球半径，云量零点四五。
OgxCloudLayer ogxCloudLayerDefault()
{
    OgxCloudLayer layer; // 先声明再填写字段。
    layer.bottom = 0.75; // 云底七百五十米，从岛上仰望时云在头顶，不压住地平线。
    layer.top = 2.20; // 云顶两千二百米，厚一千四百多米，积云有足够的竖向结构。
    layer.planetRadius = 6360.0; // 与大气模块使用同一颗行星。
    layer.coverage = 0.30; // 中等云量，保留清晰的蓝天缝隙。
    layer.density = 1.5; // 密度倍率：太厚会让整层云变成灰色的天花板。
    layer.detail = 1.0; // 默认开启边缘侵蚀。
    layer.wind = float3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    return layer; // 返回可直接修改的默认值。
}

// 降雨对云量的加成：雨与雷暴各叠一成，超过一的部分截掉。
// 为什么单独一个函数：降雨强度与雷暴强度来自天气，云层本身不知道下雨，加成必须在边界一次算完。
float ogxCloudRainDensity(float density, float rain, float thunder)
{
    return min(density + rain * 0.1 + thunder * 0.1, 1.0);
}

// 云密度：低频云量图决定哪里长云，域扭曲与高度剪切打断重复。
float ogxCloudDensity(OgxCloudLayer layer, float3 position, bool withDetail)
{
    float curvature = dot(position.xz, position.xz) / (2.0 * layer.planetRadius); // 球面相对切面的高度亏损。
    float altitude = position.y - curvature; // 修正后的真实高度。
    // 云底高度用低频噪声起伏几十米：云底因此不是一条笔直的水平线，远看更像真实的积云底。
    float baseWobble = (ogxFbm2(position.xz * 0.42 + layer.wind.xz, 2) - 0.5) * 0.16;
    float bottom = layer.bottom + baseWobble; // 本列的云底高度。
    float height = (altitude - bottom) / max(layer.top - bottom, 1e-4); // 层内归一化高度。
    if (height <= 0.0 || height >= 1.0) // 云层外没有密度。
    {
        return 0.0; // 直接跳过，省掉后面的噪声。
    }
    float2 wind = layer.wind.xz; // 只取水平风。
    float2 base = position.xz + wind; // 随风平移的平面坐标。
    // 域扭曲：一层次级噪声把值噪声的方格打散，云团边缘不再沿着坐标轴。
    // 只用两层目的是一次密度取样控制在十次噪声以内：云的代价主要在密度函数里。
    float2 warp = float2(ogxFbm2(base * 1.05 + float2(3.7, 1.9), 2),
                         ogxFbm2(base * 1.05 + float2(9.2, 5.4), 2)) - 0.5;
    float2 plane = base + warp * 2.4; // 扭曲后的平面坐标。
    plane += float2(height * 0.62, -height * 0.38); // 随高度剪切，云有斜向层次而不是竖直柱子。
    // 两个尺度定形状：六百米级的大团决定云块位置，一百八十米级的中团给圆顶。
    float large = ogxFbm2(plane * 1.55, 3); // 大团块。
    float medium = ogxFbm3(float3(plane * 5.0, altitude * 5.0), 2); // 中团块；纵向用同一频率，否则会出现横向薄片。
    float shape = large * 0.55 + medium * 0.45; // 合在一起。
    shape = pow(ogxSaturate(shape), 0.85); // 略微推高亮的部位，圆顶更鼓。
    float coverageNoise = ogxValueNoise2(base * 0.085); // 几公里尺度的云量变化，一层就够。
    float threshold = lerp(0.62, 0.40, ogxSaturate(layer.coverage)); // 云量越大，阈值越低。
    threshold -= (coverageNoise - 0.5) * 0.14; // 成片与空窗交替。
    float density = smoothstep(threshold, threshold + 0.05, shape); // 边缘过渡收窄，云块轮廓更清楚。
    // 竖向轮廓：底部收得快、顶部慢慢收，形成平底圆顶的积云形状。
    float vertical = smoothstep(0.0, 0.12, height) * (1.0 - smoothstep(0.55, 1.0, height) * 0.85);
    density *= vertical; // 竖向包络。
    if (withDetail && layer.detail > 0.0 && density > 0.002) // 只有确实有云时才叠细节。
    {
        // 高频侵蚀：三个方向同尺度，否则竖向格距过密，逆光时会出现一丝丝划痕。
        float erosion = ogxFbm3(float3(plane * 14.0, altitude * 14.0) + float3(wind * 6.0, 0.0), 1);
        density *= lerp(1.0, smoothstep(0.18, 0.68, erosion), ogxSaturate(layer.detail) * 0.72); // 只在边缘削薄。
    }
    return ogxSaturate(density) * layer.density; // 乘以密度倍率后返回。
}

// 朝太阳方向在云里短步进，估计还有多少阳光能到当前点。
float ogxCloudLight(OgxCloudLayer layer, float3 position, float3 sunDirection, int steps)
{
    const int maxSteps = 6; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float opticalDepth = 0.0; // 沿阳光累积的云密度。
    float stepLength = 0.012; // 起始步长，公里。
    float3 samplePosition = position; // 从当前点出发。
    for (int i = 0; i < maxSteps; i++) // 逐步朝太阳前进。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        samplePosition += sunDirection * stepLength; // 前进一段。
        opticalDepth += ogxCloudDensity(layer, samplePosition, false) * stepLength; // 累加路径上的云。
        stepLength *= 1.75; // 越远步长越大，覆盖更厚的云。
    }
    float direct = exp(-opticalDepth * 11.0); // 直接的比尔-朗伯透射率。
    // 多次散射：光子会在云滴之间反复弹射，真实的厚云背光面是灰色而不是黑色。
    // 用一个更慢衰减的指数近似这部分能量，系数偏小，只负责把暗部托起来。
    float multiple = exp(-opticalDepth * 2.2) * 0.34;
    return direct + multiple; // 两者相加，上限交给调用方压。
}

// 沿视线步进云层：返回云的普通颜色与覆盖率，供天空合成。
float4 ogxCloudMarch(OgxCloudLayer layer, float3 camera, float3 viewDirection, float3 sunDirection,
                     float3 sunColor, float3 skyColor, float jitter, int steps)
{
    float3 origin = float3(0.0, layer.planetRadius + max(camera.y, 0.0), 0.0); // 相机在行星正上方。
    float2 bottomHit = ogxRaySphereIntersection(origin, viewDirection, layer.planetRadius + layer.bottom); // 与云底的交点。
    float2 topHit = ogxRaySphereIntersection(origin, viewDirection, layer.planetRadius + layer.top); // 与云顶的交点。
    float startDistance = 0.0; // 步进起点。
    float endDistance = 0.0; // 步进终点。
    if (camera.y < layer.bottom) // 相机在云下：先碰到云底。
    {
        startDistance = bottomHit.y; // 云底远交点。
        endDistance = topHit.y; // 云顶远交点。
    }
    else if (camera.y > layer.top) // 相机在云上：先碰到云顶。
    {
        startDistance = topHit.x; // 云顶近交点。
        endDistance = bottomHit.x; // 云底近交点。
    }
    else // 相机在云层内部。
    {
        startDistance = 0.0; // 从相机开始。
        endDistance = topHit.y; // 到云顶为止。
    }
    if (endDistance <= startDistance || endDistance <= 0.0) // 没有穿过云层。
    {
        return float4(0.0, 0.0, 0.0, 0.0); // 完全透明。
    }
    endDistance = min(endDistance, 2.8); // 远处云淡出：步长在掠射方向拉得很长，再远也只会被空气透视洗掉。
    const int maxSteps = 32; // 固定循环上限。
    int count = min(max(steps, 4), maxSteps); // 至少四步，最多三十二步。
    float stepLength = (endDistance - startDistance) / float(count); // 每步长度。
    float distanceAlongRay = startDistance + stepLength * ogxSaturate(jitter); // 抖动起点，减轻层状条纹。
    float3 scattered = float3(0.0); // 累积散射光。
    float transmittance = 1.0; // 还剩多少背景光能穿过。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    // 双瓣相函数：前向散射给银边，瑞利项托住侧光。前向峰值必须夹住，
    // 否则正对低阳的云会被推到几十倍亮度，泛光一开就成一片白斑。
    float phase = ogxMiePhase(0.62, nu) * 0.85 + ogxRayleighPhase(nu) * 0.30;
    phase = min(phase, 3.2);
    for (int i = 0; i < maxSteps; i++) // 逐步穿过云层。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float3 position = camera + viewDirection * distanceAlongRay; // 当前采样点。
        float density = ogxCloudDensity(layer, position, true); // 当前密度。
        if (density > 0.002) // 空区域跳过光照步进。
        {
            float light = min(ogxCloudLight(layer, position, sunDirection, 4), 1.20); // 朝太阳的透射率，厚云也保留多次散射。
            float height = ogxSaturate((position.y - layer.bottom) / max(layer.top - layer.bottom, 1e-4)); // 层内高度。
            // 粉末效应：正对阳光看薄云边缘时，能看到云滴把光散回来，边缘因此发亮。
            float powder = 1.0 - exp(-density * 7.0);
            float3 sun = sunColor * light * (phase * 0.95 + 0.50) * (0.40 + 0.60 * powder); // 太阳直射。
            // 环境光按高度与密度变化：云底比云顶暗，薄处比厚处亮。
            // 强度要足够，否则背光面会发灰发脏，看起来像一层烟。
            float3 ambient = skyColor * (0.26 + 0.34 * (1.0 - ogxSaturate(density * 0.5))) * (0.42 + 0.58 * height); // 天空环境光。
            float extinction = exp(-density * stepLength * 26.0); // 这一段的透过率。
            scattered += (sun + ambient) * transmittance * (1.0 - extinction); // 按剩余透过率累加。
            transmittance *= extinction; // 更新剩余透过率。
        }
        distanceAlongRay += stepLength; // 前进一段。
        if (transmittance < 0.02) // 几乎不透明就不再采样。
        {
            break; // 提前结束。
        }
    }
    float alpha = 1.0 - transmittance; // 云的覆盖率。
    float3 color = scattered / max(alpha, 1e-4); // 预乘颜色还原成普通颜色。
    return float4(color, alpha); // 供天空按覆盖率合成。
}

// 云影：把地面点沿阳光投到云层中部，取那里的密度换成透过率。
float ogxCloudShadow(OgxCloudLayer layer, float3 groundPosition, float3 sunDirection)
{
    if (sunDirection.y <= 0.0) // 太阳在地平线以下没有云影。
    {
        return 1.0; // 不压暗。
    }
    float targetHeight = layer.bottom + (layer.top - layer.bottom) * 0.5; // 云层中部高度。
    float distance = (targetHeight - groundPosition.y) / max(sunDirection.y, 0.15); // 沿阳光到云层的距离。
    float3 position = groundPosition + sunDirection * distance; // 投影点。
    float density = ogxCloudDensity(layer, position, false); // 投影点的云密度。
    return lerp(1.0, exp(-density * 1.5), 0.35); // 密度换成柔和云影，避免地面全黑。
}

// 亨耶-格林斯坦相函数：`g` 越大越向前集中，云的向阳边缘因此更亮。
// 与通用数学的 `ogxHenyeyGreensteinPhase` 形状相同，但参考实现把归一化常数写成 0.25/π，
// 层状云与末地雾又各用 3.14；三处常数必须保持参考精度，所以这里保留直接算式并在注释里说明差异。
float ogxHenyeyGreenstein(float cosAngle, float g)
{
    float num = 1.0 - g * g; // 分子，决定整体强度。
    float denom = 1.0 + g * g - 2.0 * g * cosAngle; // 分母，越靠前越小。
    float inverse = rsqrt(denom); // 分母的平方根倒数。
    return num * inverse * inverse * inverse * (0.25 / OGX_PI); // 合成一次散射的相函数。
}
// 云顶曲线：把归一化高度换成边缘压低的圆顶，用来让云的顶部看起来是弧面。
float ogxCloudTopCurve(float x)
{
    x = x - 1.0; // 平移到零点。
    return 1.0 - x * x; // 开口向下的抛物线。
}

// 为什么先加相机高度：云影贴图跟着相机平移，投影必须用相机相对的高度，否则走动时影子会漂。
float2 ogxCloudShadowCoord(float3 worldPos, float3 lightDir, float cameraY, float range)
{
    float2 coord = worldPos.xz - lightDir.xz * ((worldPos.y + cameraY) / lightDir.y); // 沿光方向落到云影平面。
    return coord * (1.0 / range) + 0.5; // 换成贴图坐标。
}

// 十六像素三次模糊：四次双线性采样合成，返回红通道；云影贴图只有红通道有意义。
// 两次双线性之间按权重比例混合，效果等价于四次三次采样，但纹理读取次数减半。
float ogxCloudShadowBicubic(Sampler2D shadowTex, float2 coord, float2 texSize)
{
    float2 texPixel = 1.0 / texSize; // 一个像素的坐标大小。
    coord = coord * texSize - 0.5; // 换成以像素为单位的坐标。
    float2 p = floor(coord); // 整数像素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 两个方向的前两个权重。
    float4 w1; // 两个方向的后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
    w1.yw = ff * f; // 第四个权重是偏移立方。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
    float4 s = w0 + w1; // 每对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
    c *= texPixel.xxyy; // 换回零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return lerp(lerp(shadowTex.SampleLevel(c.yw, 0.0).x, shadowTex.SampleLevel(c.xw, 0.0).x, m.x),
                lerp(shadowTex.SampleLevel(c.yz, 0.0).x, shadowTex.SampleLevel(c.xz, 0.0).x, m.x),
                m.y); // 四次双线性采样得到十六像素的三次模糊，取红通道。
}

// 云影取样：按天气在晴天与雨天两档之间混合，`wetness` 是降雨湿润度。
float ogxCloudShadowSample(Sampler2D shadowTex, float3 worldPos, float3 lightDir, float cameraY, float range,
    float2 screenExtent, float2 pixelSize, float texSize, float wetness, float rainShadow, bool fadeAngle)
{
    float2 coord = ogxCloudShadowCoord(worldPos, lightDir, cameraY, range); // 投到云影贴图坐标。
    float cloudShadow = 1.0 - wetness; // 雨天默认的云影底值。
    if (ogxEqual(ogxSaturate(coord), coord)) // 只有落在贴图范围内才采样。
    {
        float2 shadowTexel = screenExtent - coord * texSize; // 贴图贴在画面右上角，坐标要翻转。
        float2 fade = ogxSaturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
        cloudShadow = lerp(cloudShadow, ogxCloudShadowBicubic(shadowTex, shadowTexel * pixelSize, screenExtent), fade.x * fade.y); // 三次采样并淡出。
    }
    if (fadeAngle) // 太阳越贴地云影越淡。
    {
        float fade = smoothstep(0.06, 0.18, abs(lightDir.y)); // 光方向越平越淡。
        cloudShadow = lerp(1.0 - wetness, cloudShadow, fade * fade); // 按淡出权重混合。
    }
    return ((rainShadow - 1.0) * wetness + 1.0) * cloudShadow + (wetness - rainShadow * wetness); // 晴天与雨天两档之间插值。
}

// 全局云影：从云影贴图顶行的统计像素取一个粗粒度值；没有贴图时按天气估。
float ogxGlobalCloudShadow(Sampler2D shadowTex, int2 statTexel, float wetness, float rainShadow, bool fromTexture)
{
    if (fromTexture) return lerp(shadowTex.Load(int3(statTexel, 0)).a, 1.0, 0.03 - wetness * 0.015); // 统计像素存全局云影。
    return 1.0 - wetness * (rainShadow * 0.985); // 纯天气估计。
}

// 云影横向或纵向高斯模糊：权重固定，轴由参数给；其余通道原样带过。
// 只模糊红通道，因为绿蓝通道存的是别的统计量，混进来会污染后续读取。
float4 ogxCloudShadowBlur(Sampler2D shadowTex, int2 texel, int2 axis, int2 borderMin, int2 borderMax)
{
    float4 blur = float4(0.0); // 模糊结果。
    int2 sampleCoord = clamp(texel - 3 * axis, borderMin, borderMax); // 第三个负向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.054543; // 按高斯权重累加。
    sampleCoord = clamp(texel - 2 * axis, borderMin, borderMax); // 第二个负向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.099384; // 累加。
    sampleCoord = clamp(texel - 1 * axis, borderMin, borderMax); // 第一个负向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.181090; // 累加。
    float4 center = shadowTex.Load(int3(texel, 0)); // 中心样本。
    blur.r += center.r * 0.329966; // 中心权重最大。
    blur.gba += center.gba; // 其余通道原样带过。
    sampleCoord = clamp(texel + 1 * axis, borderMin, borderMax); // 第一个正向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.181090; // 累加。
    sampleCoord = clamp(texel + 2 * axis, borderMin, borderMax); // 第二个正向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.099384; // 累加。
    sampleCoord = clamp(texel + 3 * axis, borderMin, borderMax); // 第三个正向样本。
    blur.r += shadowTex.Load(int3(sampleCoord, 0)).r * 0.054543; // 累加。
    return blur; // 返回模糊后的云影贴图。
}

// 层状云的云相函数：和 Henyey-Greenstein 不是同一公式，分母固定除以 3.14。
// 层状云相位兼容层：把参考的双瓣散射写成同一个入口，供云光照复用。
float ogxCloudPhaseLayered(float x, float g)
{
    return ogxHenyeyGreensteinPhase(x, g, 1.0 / 3.14); // 参考实现直接写 3.14，保留同一精度。
}

// 层状云的云密度三线性取样：不做平滑，直接用小数部分在两层噪声之间插值。
// 与 `ogxStormNoise` 的区别是后者先把小数部分做了 smoothstep，两者不能互换。
float ogxCloudDensityAtPos(float3 position, Sampler2D noiseTexture, float noiseResolution)
{
    position /= 18.0; // 参考实现的世界尺度。
    position.xz *= 0.5; // 横向再压一半。
    float3 cell = floor(position); // 整数格。
    float3 fraction = fract(position); // 小数部分。
    float2 uv = cell.xz + fraction.xz + cell.y * float2(0.0, 193.0); // 三维转二维噪声坐标。
    float2 sample2 = noiseTexture.SampleLevel(uv / noiseResolution, 0.0).yx; // 取两个通道。
    return lerp(sample2.r, sample2.g, fraction.y); // 按纵向小数插值。
}

#endif
