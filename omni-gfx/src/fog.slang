/*
Omni 通用图形库雾模块：高度衰减、噪声雾团、粉末效应、混合相位与沿视线积分。
调用位置：地形、水面与低空空气的雾；Minecraft 光影由 `/omni-gfx/fog.glsl` 引入。
可复制示例：
    OgxFog f = ogxFogDefault(); // 取默认雾。
    float4 r = ogxFogMarch(f, camKm, worldKm, sunDir, sunColor, j, 10); // 沿视线积分雾。
    c = ogxFogApply(c, r); // 把雾合成到颜色。
设计原因与取舍：
    密度剖面与相位来自旧 `shaders/gfx/fog.glsl` 的 `gfx_fog_density_height`、`gfx_fog_density_noise`
    与 `gfx_fog_phase`，把纹理噪声换成程序化值噪声，保持雾团边缘与高度衰减的手感。
    步数与抖动由调用方给出，库不读取天气、选项或宿主时间；返回预乘散射色与剩余透过率，
    调用方按自己的混合顺序合成，避免和大气散射重复叠加。
*/
#ifndef OGX_FOG_INCLUDED
#define OGX_FOG_INCLUDED

// 数学提供相函数，噪声提供雾团形状。
#include "math.slang"
#include "noise.slang"

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

// 默认低空雾：贴地薄雾，密度适中，云影下会自然变暗。
OgxFog ogxFogDefault()
{
    OgxFog fog; // 先声明再填写字段。
    fog.color = float3(0.55, 0.68, 0.82); // 偏冷的天空色。
    fog.density = 0.18; // 每公里密度，远景能看到空气感。
    fog.heightFalloff = 0.06; // 六十米高度衰减，雾贴在低空。
    fog.baseHeight = 0.0; // 海平面最浓。
    fog.noiseScale = 9.0; // 百米级雾团。
    fog.noiseStrength = 0.75; // 噪声明显但不把雾打碎。
    fog.wind = float3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    fog.sunStrength = 1.0; // 阳光散射默认全强。
    return fog; // 返回可直接修改的默认值。
}

// 雾密度：高度指数衰减乘三维噪声，得到会流动的雾团。
float ogxFogDensity(OgxFog fog, float3 position)
{
    float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
    float3 noisePosition = (position + fog.wind) * fog.noiseScale; // 换到雾坐标并叠加风。
    float noise = ogxFbm3(noisePosition, 3); // 三层次雾团。
    return fog.density * height * lerp(1.0, noise * 1.6, ogxSaturate(fog.noiseStrength)); // 噪声只调制密度，不改变高度剖面。
}

// 混合相位：三成后向、七成前向，逆光和顺光都不会过曝。
float ogxFogPhase(float nu)
{
    return ogxMiePhase(-0.4, nu) * 0.3 + ogxMiePhase(0.5, nu) * 0.7; // 与旧雾模块相同的权重。
}

// 粉末效应：薄雾在背光方向略微增亮，模拟多次散射。
float ogxFogPowder(float density, float nu)
{
    float powder = 1.0 - exp(-max(density, 0.0) * 4.0); // 密度越低越明显。
    return lerp(1.0, powder, ogxSaturate(0.5 - 0.5 * nu)); // 只影响背光方向。
}

// 沿视线积分雾：返回预乘散射色与剩余透过率。
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

// 把雾应用到已经着色的颜色：先乘剩余透过率，再加散射色。
float3 ogxFogApply(float3 color, float4 fog)
{
    return color * fog.a + fog.rgb; // 预乘散射色直接相加。
}

// 粉末效应：背光时气溶胶把光往前推，边缘因此更亮，正对时补偿回去。
float ogxLegacyPowder(float absorption, float lightingAbsorption, float VdotL)
{
    return lerp((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越强效果越强。
}

// 混合相位：后向与前向两个米氏相位加权，雾的轮廓在逆光时仍有层次。
float ogxLegacyFogPhase(float VdotL)
{
    return ogxMiePhase(-0.4, VdotL) * 0.3 + ogxMiePhase(0.5, VdotL) * 0.7; // 前向占七成。
}

// 多次散射相位：四个衰减档各给一个相位，用来叠出体积雾的多层散射。
// 返回四分量的原因是 GLSL 的数组参数在 Slang 里没有等价写法，四档直接装进一个向量。
float4 ogxMultiScatteringPhases(float VdotL)
{
    return float4(ogxLegacyFogPhase(VdotL), ogxLegacyFogPhase(VdotL * 0.5),
                  ogxLegacyFogPhase(VdotL * 0.25), ogxLegacyFogPhase(VdotL * 0.125)); // 四档角度逐次减半，与旧实现的循环一致。
}

// 雾密度的高度剖面：两层高度之间的空气最浓，离开这段距离按指数下降，夜间更浓。
float ogxFogDensityHeight(float3 fogPos, float heightA, float heightB, float falloff, float timeMidnight)
{
    float maxHeight = max(heightA, heightB); // 两层里较高的。
    float minHeight = min(heightA, heightB); // 两层里较低的。
    float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到浓度层的距离。
    dh *= 2.0 / falloff; // 按衰减距离归一化。
    float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢。
    return density * 0.1; // 乘基础密度。
}

// 噪声雾密度：高度包络乘四层噪声，平方两次让雾团边界清楚。
float ogxFogDensityNoise(float3 fogPos, float3 wind, float heightA, float heightB, float falloff,
    float timeMidnight, Sampler2D noiseTexture)
{
    float dh = abs(fogPos.y - max(heightA, heightB)); // 到浓度层的距离。
    dh *= 1.0 / falloff; // 按衰减距离归一化。
    float envelope = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
    float density = 0.0; // 累积的雾密度。
    fogPos = fogPos * 0.02 + wind; // 缩放坐标并叠加风向。
    for (float alpha = 0.5; alpha >= 0.125; alpha *= 0.5) // 四层不同频率的噪声。
    {
        density += alpha * ogxFogNoise(fogPos, noiseTexture); // 按权重累加。
        fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
    }
    density *= envelope; // 乘高度衰减。
    density = density * density; // 平方让雾团更实。
    return density * density * 3.0; // 再平方并放大，得到清楚的边界。
}

#endif
