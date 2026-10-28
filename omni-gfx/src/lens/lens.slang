/*
Omni 通用图形库镜头模块：对焦距离、桶形光斑、彩色鬼影、环形眩光与太阳眩光。
调用位置：需要复现 iterationT 镜头光斑与景深对焦的后期程序；由 `/omni-gfx/lens/lens.glsl` 引入。
可复制示例：
    float focus = ogxGetFocus(colortex2, screenExtent, 0, 8.0, projectionInverse); // 取对焦距离。
    vec3 color = ogxLensFlare(texCoord, sunCoord, aspect, projectionYY, true, true, 1.0, 1.0, sunColor, 1.0, 0.0, 1.0); // 叠镜头光斑。
设计原因与取舍：
    对焦与光斑都只依赖屏幕坐标、投影与太阳位置；纹理、开关和强度显式传入，常数与参考实现逐项相同。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。镜头光斑目前只有探针覆盖，还没有顶层画面入口。
*/
#ifndef OGX_LENS_LENS_INCLUDED
#define OGX_LENS_LENS_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "../shadow/shadow.slang"

// 对焦距离：参考实现从第二张缓冲左下角取一个对比度统计值，或直接使用手动焦距。
float ogxGetFocus(Sampler2D focusTexture, int2 screenExtent, int focusMode, float focalPoint, float4x4 projectionInverse)
{
    float focus; // 对焦距离，米。
    if (focusMode == 0) // 自动对焦：读取统计像素。
    {
        float4 stat = focusTexture.Load(int3(int2(60, screenExtent.y - 1), 0)); // 固定取横向第六十个像素。
        focus = ogxLinearDepthFromScreenDepth(stat.a * 0.125 + 0.875, projectionInverse); // 编码值还原成米。
    }
    else // 手动对焦。
    {
        focus = focalPoint; // 直接使用调用方给的焦距。
    }
    return focus; // 交回对焦距离。
}

// 镜头光斑的桶形偏移：把二维偏移按到画面中心的距离旋转，得到弯曲的光斑轨迹。
float2 ogxLensDistOffset(float2 uv, float2 pxOffset, float barrel)
{
    float2 toCenter = uv; // 画面中心到当前点的方向。
    float3 prep = normalize(float3(toCenter.y, -toCenter.x, 0.0)); // 旋转轴。
    float angle = length(toCenter) * 2.221 * barrel; // 偏移角随距离增长。
    float3 oldOffset = float3(pxOffset, 0.0); // 原始二维偏移抬成三维。
    float3 rotated = oldOffset * cos(angle) + cross(prep, oldOffset) * sin(angle) + prep * dot(prep, oldOffset) * (1.0 - cos(angle)); // 绕轴旋转。
    return rotated.xy; // 只取二维结果。
}

// 单个彩色光斑：三个颜色通道用略微不同的距离，形成色散边缘。
float3 ogxLensFlareSpot(float2 uv, float2 pos, float dist, float chromaOffset, float size, float barrel)
{
    pos = ogxLensDistOffset(uv, pos, barrel); // 先做桶形弯曲。
    float r = max(0.01 - pow(length(uv + (dist - chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 0.85; // 红通道。
    float g = max(0.01 - pow(length(uv + dist * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.0; // 绿通道。
    float b = max(0.01 - pow(length(uv + (dist + chromaOffset) * pos), 2.4) * (1.0 / (size * 2.0)), 0.0) * 1.5; // 蓝通道。
    return float3(r, g, b); // 合成彩色光斑。
}

// 一串小光斑：六层逐渐变小的光斑沿同一条轨迹排开，再补一个大光斑。
float3 ogxLensOrb(float2 uv, float2 pos, float dist, float size, float barrel)
{
    float3 color = float3(0.0); // 累加结果。
    const float orbCount = 6.0; // 参考实现的固定层数。
    for (float i = 0.0; i < orbCount; i++) // 逐层累加。
    {
        float j = i + 1.0; // 从第一层开始。
        float offset = j / (j + 0.1); // 沿轨迹的偏移。
        float colorOffset = j / orbCount * 0.5; // 颜色偏移。
        float spotSize = size / (j + 1.0); // 越往后越小。
        color += ogxLensFlareSpot(uv, pos, dist + offset, spotSize * 2.0, spotSize, barrel) * float3(1.0 - colorOffset, 1.0, 0.5 + colorOffset) * j; // 按层号加权。
    }
    color += ogxLensFlareSpot(uv, pos, dist + 0.8, 0.05, 3.0 * size, barrel) * 0.5; // 最外层大光斑。
    return color; // 交回整串光斑。
}

// 环形光斑：用反比曲线给出一圈柔和的色散环。
float3 ogxLensRing(float2 uv, float2 pos, float dist, float chromaOffset, float blur, float barrel)
{
    float2 uvd = uv * length(uv); // 径向拉长，环才不是正圆。
    pos = ogxLensDistOffset(uv, pos, barrel); // 同样做桶形弯曲。
    float r = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist - chromaOffset) * pos), blur)), 0.0) * 0.8; // 红通道。
    float g = max(1.0 / (1.0 + 250.0 * pow(length(uvd + dist * pos), blur)), 0.0) * 1.0; // 绿通道。
    float b = max(1.0 / (1.0 + 250.0 * pow(length(uvd + (dist + chromaOffset) * pos), blur)), 0.0) * 1.5; // 蓝通道。
    return float3(r, g, b); // 合成彩色环。
}

// 镜头光斑与眩光：先按到太阳的屏幕距离算一圈眩光，再叠两层环与多个彩色光斑。
// `lensGlare` 与 `lensFlare` 对应参考实现的两个独立开关，两者可以同时打开。
float3 ogxLensFlare(float2 texCoord, float2 sunCoord, float aspectRatio, float projectionYY, bool lensGlare,
    bool lensFlare, float glareBrightness, float flareBrightness, float3 colorSunlight, float sunVisibility,
    float vfogDensity, float mainOutputFactor)
{
    float3 result = float3(0.0); // 累加结果。
    float2 coord = texCoord - 0.5; // 以画面中心为原点。
    float2 sunPos = sunCoord - 0.5; // 太阳的屏幕位置。
    coord.x *= aspectRatio; // 横纵比修正，光斑不会被拉扁。
    sunPos.x *= aspectRatio; // 太阳位置同样修正。
    float fovFactor = max(projectionYY, 2.0); // 视野越大，光斑尺度越大。
    const float barrel = 1.0; // 参考实现的桶形畸变强度。
    if (lensGlare) // 眩光：沿太阳方向的放射状亮纹。
    {
        float2 v = coord - sunPos; // 到太阳的屏幕向量。
        float dist = length(v); // 距离。
        float glareDist = dist * 13.0 / fovFactor; // 按视野归一化。
        float phase = atan2(v.y, v.x) + 0.131; // 方向角加固定相位。
        float glare = 2.0 - clamp(glareDist, 0.0, 1.0) + sin(phase * 12.0) * clamp(glareDist * 2.5 - 0.2, 0.0, 1.0); // 放射条纹。
        glare = glare * glare; // 平方让亮纹更集中。
        glareDist = glareDist * glareDist; // 距离平方。
        glare *= 8e-5 / (glareDist * glareDist); // 反比衰减。
        glare = min(glare, 200.0); // 上限防止爆亮。
        result += float3(glare * glareBrightness); // 叠到结果。
    }
    if (lensFlare) // 光斑：多层圆斑、环与彩色鬼影。
    {
        float size = 0.5 * fovFactor; // 光斑基准尺寸。
        float3 flareColor = float3(0.0); // 光斑累加。
        flareColor += ogxLensOrb(coord, sunPos, 0.0, size * 0.01, barrel) * 0.1; // 主光斑串。
        flareColor += ogxLensRing(coord, sunPos, 1.0, 0.02, 1.4, barrel) * 0.01; // 正向环。
        flareColor += ogxLensRing(coord, sunPos, -1.0, 0.02, 1.4, barrel) * 0.01; // 反向环。
        flareColor += ogxLensFlareSpot(coord, sunPos, -2.00, 0.05, size * 0.05, barrel) * 0.5; // 远端鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.90, 0.02, size * 0.03, barrel) * 0.3; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.70, 0.01, size * 0.06, barrel) * 0.5; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.55, 0.02, size * 0.02, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.35, 0.02, size * 0.04, barrel) * 0.7; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.01, size * 0.15, barrel) * float3(0.3, 0.4, 0.38); // 彩色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, -0.25, 0.02, size * 0.08, barrel) * 0.2; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.05, 0.01, size * 0.03, barrel) * 0.1; // 鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 0.30, 0.02, size * 0.20, barrel) * float3(0.2, 0.18, 0.14); // 暖色鬼影。
        flareColor += ogxLensFlareSpot(coord, sunPos, 1.20, 0.03, size * 0.10, barrel) * 0.2; // 远端鬼影。
        result += flareColor * (flareBrightness * 0.3); // 按强度叠到结果。
    }
    result *= colorSunlight * (sunVisibility * clamp(exp2(1.0 - vfogDensity * 20.0), 0.0, 1.0) / mainOutputFactor); // 按阳光与雾衰减。
    return ogxLinearToCurve3(result); // 转回曲线编码。
}

#endif
