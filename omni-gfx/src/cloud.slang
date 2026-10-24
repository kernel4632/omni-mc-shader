/*
Omni 通用图形库云模块：球壳求交、程序化密度、朝阳光照与沿视线步进。
调用位置：天空与水面反射里的云；Minecraft 光影由 `/omni-gfx/cloud.glsl` 引入。
可复制示例：
    OgxCloudLayer l = ogxCloudLayerDefault(); // 取默认云层。
    float4 c = ogxCloudMarch(l, camKm, viewDir, sunDir, sunColor, skyColor, j, 24); // 步进一层云。
    float k = ogxCloudShadow(l, groundKm, sunDir); // 取地面云影。
设计原因与取舍：
    形状来自旧 `shaders/gfx/cloud_volume.glsl` 的球面云坐标、云量重映射与光照步进，
    把纹理采样换成程序化值噪声，因此不需要额外贴图也能独立出图。
    只用一层云，但加入低频云量图、域扭曲和随高度剪切，专门消除平面云层的重复条纹。
    密度与光照步数全部由调用方传入，库不读取天气、选项或宿主状态。
*/
#ifndef OGX_CLOUD_INCLUDED
#define OGX_CLOUD_INCLUDED

// 噪声提供云团与细节，数学提供球面求交与相函数。
#include "math.slang"
#include "noise.slang"

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
    layer.bottom = 0.16; // 云底一百六十米，能从岛上看清云层。
    layer.top = 0.62; // 云顶六百二十米，厚度四百六十米，云有足够的竖向结构。
    layer.planetRadius = 6360.0; // 与大气模块使用同一颗行星。
    layer.coverage = 0.38; // 中等云量，保留清晰的蓝天缝隙。
    layer.density = 3.2; // 密度倍率，让云在逆光时仍有厚度。
    layer.detail = 1.0; // 默认开启边缘侵蚀。
    layer.wind = float3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    return layer; // 返回可直接修改的默认值。
}

// 云密度：低频云量图决定哪里长云，域扭曲与高度剪切打断重复。
float ogxCloudDensity(OgxCloudLayer layer, float3 position, bool withDetail)
{
    float curvature = dot(position.xz, position.xz) / (2.0 * layer.planetRadius); // 球面相对切面的高度亏损。
    float altitude = position.y - curvature; // 修正后的真实高度。
    float height = (altitude - layer.bottom) / max(layer.top - layer.bottom, 1e-4); // 层内归一化高度。
    if (height <= 0.0 || height >= 1.0) // 云层外没有密度。
    {
        return 0.0; // 直接跳过，省掉后面的噪声。
    }
    float2 wind = layer.wind.xz; // 只取水平风。
    float2 warp = float2(ogxFbm2(position.xz * 1.3 + wind * 1.7 + float2(3.0, 7.0), 2), // 横向扭曲。
                         ogxFbm2(position.xz * 1.3 + wind * 1.7 + float2(11.0, 5.0), 2)) - 0.5; // 纵向扭曲。
    float2 cloudUv = position.xz + warp * 1.2; // 扭曲后的平面坐标。
    cloudUv += float2(height * 0.35, -height * 0.22); // 随高度剪切，云看起来有斜向层次。
    // 把采样坐标旋转三十度再取形状：值噪声的格子与坐标轴对齐，直接沿风向铺开会
    // 看到一排排同向的云块，转一个角度后网格方向与视线、风向都不重合，重复感明显降低。
    float2 rotatedUv = float2(cloudUv.x * 0.8660 + cloudUv.y * 0.5000, -cloudUv.x * 0.5000 + cloudUv.y * 0.8660);
    float shape2D = ogxFbm2(rotatedUv * 4.2 + wind * 3.0, 4); // 四层二维形状，最细一层约五十米，云团边缘因此不再是一团棉花。
    float shape3D = ogxFbm3(float3(rotatedUv.x * 3.2, position.y * 14.0, rotatedUv.y * 3.2) + float3(wind.x * 2.0, 0.0, wind.y * 2.0), 2); // 三维团块，给云竖向结构。
    float shape = shape2D * 0.40 + shape3D * 0.60; // 平面大形状与三维团块合在一起。
    float billow = abs(shape - 0.5) * 2.0; // 离平均越远越鼓，用来做积云那种圆顶。
    shape += billow * 0.10; // 只加一点点，太多会变成硬边气泡。
    float coverageNoise = ogxFbm2(position.xz * 0.16 + wind * 2.0, 2); // 几公里尺度的云量变化。
    float threshold = lerp(0.58, 0.30, ogxSaturate(layer.coverage)); // 云量越大，阈值越低。
    float density = smoothstep(threshold, threshold + 0.09, shape * (0.80 + coverageNoise * 0.45)); // 云块边缘，阈值宽度决定过渡。
    float vertical = smoothstep(0.0, 0.05, height) * smoothstep(1.0, 0.72, height); // 底部收口更硬，云底因此是平的。
    density *= vertical * (0.72 + 0.28 * smoothstep(0.10, 0.55, height)); // 中上层更密，云顶看起来更厚实。
    if (withDetail && layer.detail > 0.0 && density > 0.001) // 只有确实有云时才叠细节。
    {
        // 细节噪声保持各方向格距接近：垂直方向与水平方向用同一个尺度，
        // 否则竖向格距过密，逆光时会出现一丝丝的细线，看起来像划痕。
        float detailNoise = ogxFbm3(float3(cloudUv.x * 15.0, position.y * 16.0, cloudUv.y * 15.0) + float3(wind.x * 8.0, 0.0, wind.y * 8.0), 2); // 七十米级细节。
        density *= lerp(1.0, smoothstep(0.12, 0.62, detailNoise), ogxSaturate(layer.detail) * 0.58); // 侵蚀云边，避免硬块。
    }
    return ogxSaturate(density) * layer.density; // 乘以密度倍率后返回。
}

// 朝太阳方向在云里短步进，估计还有多少阳光能到当前点。
float ogxCloudLight(OgxCloudLayer layer, float3 position, float3 sunDirection, int steps)
{
    const int maxSteps = 5; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float opticalDepth = 0.0; // 沿阳光累积的云密度。
    float stepLength = 0.015; // 起始步长，公里。
    float3 samplePosition = position; // 从当前点出发。
    for (int i = 0; i < maxSteps; i++) // 逐步朝太阳前进。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        samplePosition += sunDirection * stepLength; // 前进一段。
        opticalDepth += ogxCloudDensity(layer, samplePosition, false) * stepLength; // 累加路径上的云。
        stepLength *= 1.7; // 越远步长越大，覆盖更厚的云。
    }
    return exp(-opticalDepth * 12.0); // 比尔-朗伯透射率。
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
    endDistance = min(endDistance, 4.0); // 远处云淡出，避免无限步进。
    const int maxSteps = 32; // 固定循环上限。
    int count = min(max(steps, 4), maxSteps); // 至少四步，最多三十二步。
    float stepLength = (endDistance - startDistance) / float(count); // 每步长度。
    float distanceAlongRay = startDistance + stepLength * ogxSaturate(jitter); // 抖动起点，减轻层状条纹。
    float3 scattered = float3(0.0); // 累积散射光。
    float transmittance = 1.0; // 还剩多少背景光能穿过。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    float phase = ogxMiePhase(0.65, nu); // 前向散射相位，逆光时云边更亮。
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
            float light = ogxCloudLight(layer, position, sunDirection, 3); // 朝太阳的透射率。
            light = lerp(light, 0.55, 0.35); // 多次散射近似：真正的云背光面不会全黑。
            float height = ogxSaturate((position.y - layer.bottom) / max(layer.top - layer.bottom, 1e-4)); // 层内高度。
            float powder = 1.0 - exp(-density * 6.0); // 薄处更亮的粉末效应。
            float3 sun = sunColor * light * (phase * 1.1 + 0.55) * (0.35 + 0.65 * powder); // 太阳直射。
            // 环境光按高度与密度变化：云底比云顶暗，薄处比厚处亮。
            // 强度要足够，否则背光面会发灰发脏，看起来像一层烟。
            float3 ambient = skyColor * (0.30 + 0.30 * (1.0 - ogxSaturate(density))) * (0.45 + 0.55 * height); // 天空环境光。
            float extinction = exp(-density * stepLength * 24.0); // 这一段的透过率。
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

#endif
