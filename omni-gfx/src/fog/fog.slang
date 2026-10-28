/*
Omni 通用图形库雾模块：高度衰减、噪声雾团、粉末效应、混合相位与沿视线积分。
调用位置：地形、水面与低空空气的雾；Minecraft 光影由 `/omni-gfx/fog/fog.glsl` 引入。
可复制示例：
    OgxFog f = ogxFogDefault(); // 取默认雾。
    float4 r = ogxFogMarch(f, camKm, worldKm, sunDir, sunColor, j, 10); // 沿视线积分雾。
    c = ogxFogApply(c, r); // 把雾合成到颜色。
设计原因与取舍：
    密度剖面与相位来自迁移前 GLSL 原型的 `gfx_fog_density_height`、`gfx_fog_density_noise`
    与 `gfx_fog_phase`，把纹理噪声换成程序化值噪声，保持雾团边缘与高度衰减的手感。
    步数与抖动由调用方给出，库不读取天气、选项或宿主时间；返回预乘散射色与剩余透过率，
    调用方按自己的混合顺序合成，避免和大气散射重复叠加。
*/
#ifndef OGX_FOG_INCLUDED
#define OGX_FOG_INCLUDED

// 数学提供相函数，噪声提供雾团形状。
#include "../common/math.slang"
// 噪声提供哈希、分形与云团细节。
#include "../common/noise.slang"

// 一层低空雾的参数；不同群系或天气换字段即可。
struct OgxFog
{
    float3 color; // 雾的环境色，线性空间。
    float density; // 基础高度处的密度，每公里。
    float heightFalloff; // 离开基础高度后的衰减距离，公里。
    float baseHeight; // 最浓的高度，公里。
    float noiseScale; // 雾团的水平尺度，每公里。
    float noiseStrength; // 噪声对密度的调制强度，零到一。
    float3 wind; // 水平风向，公里。
    float sunStrength; // 阳光在雾里的散射强度。
};

// 高度雾、噪声雾与沿视线积分，具体实现在子文件。
#include "fog/density.slang"
// 末地涡旋与末地相位，具体实现在子文件。
#include "fog/end.slang"
// 下界群系的自发光与雾色，具体实现在子文件。
#include "fog/nether.slang"
// 通用群系雾色与密度，具体实现在子文件。
#include "fog/biome.slang"

float4 ogxFogMarch(OgxFog fog, float3 camera, float3 worldPosition, float3 sunDirection,
                   float3 sunColor, float jitter, int steps)
{
    float3 delta = worldPosition - camera; // 相机到目标点的向量。
    float distance = length(delta); // 视线长度，公里。
    if (distance <= 1e-5) // 零长度不产生雾。
    {
        return float4(0.0, 0.0, 0.0, 1.0); // 完全透明。
    }
    float3 viewDirection = delta / distance; // 单位视线方向。
    const int maxSteps = 24; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = distance / float(count); // 每步长度。
    float distanceAlongRay = stepLength * ogxSaturate(jitter); // 抖动起点，减少层状条纹。
    float transmittance = 1.0; // 初始完全透明。
    float3 scattered = float3(0.0); // 累积散射光。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    float phase = ogxFogPhase(nu); // 混合相位。
    for (int i = 0; i < maxSteps; i++) // 逐步穿过雾层。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        float3 position = camera + viewDirection * distanceAlongRay; // 当前采样点。
        float density = ogxFogDensity(fog, position); // 当前密度。
        if (density > 0.001) // 空区域跳过。
        {
            float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
            float powder = ogxFogPowder(density, nu); // 薄雾的多次散射。
            float3 sun = sunColor * fog.sunStrength * (phase * 2.0 + 0.15) * height * powder; // 阳光散射。
            float3 ambient = fog.color * (0.30 + 0.70 * height); // 环境光。
            float extinction = exp(-density * stepLength * 1.2); // 这一段的透过率。
            scattered += (sun + ambient) * transmittance * (1.0 - extinction); // 按剩余透过率累加。
            transmittance *= extinction; // 更新透过率。
        }
        distanceAlongRay += stepLength; // 前进一段。
        if (transmittance < 0.02) // 几乎不透明就不再采样。
        {
            break; // 提前结束。
        }
    }
    return float4(scattered, transmittance); // 返回预乘散射色与剩余透过率。
}

float3 ogxFogApply(float3 color, float4 fog)
{
    return color * fog.a + fog.rgb; // 预乘散射色直接相加。
}

#endif
