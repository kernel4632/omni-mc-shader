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

// 按比例淡出一层预乘雾：只缩放散射色，并把透过率朝一插值。
// 为什么不能直接把四个分量一起乘小：透过率被乘小以后，颜色会被一起抹掉，
// 在“远处收敛到天空色、同时淡出雾”的接缝处就会压出一条黑线。
// `amount` 零表示完全不要这层雾，一表示保留原样。
float4 ogxFogFade(float4 fog, float amount)
{
    amount = ogxSaturate(amount); // 比例夹在零到一。
    return float4(fog.rgb * amount, lerp(1.0, fog.a, amount)); // 散射按比例缩放，透过率朝完全透明靠近。
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

// 三维噪声：把世界坐标折成三维格子，再用一张二维噪声图的上下两层按高度插值。
// 为什么能这样降维：噪声图本身是二维的，用格子的纵坐标错开贴图里的一行，
// 再把两个通道当成上下两层，就能在不增加纹理的情况下得到三维手感。
float ogxEnd3dNoise(float3 position, Sampler2D noiseTexture, float noiseResolution)
{
    float3 p = floor(position); // 整数格决定用贴图哪一块。
    float3 b = fract(position); // 格内偏移用于插值。
    b = b * b * (3.0 - 2.0 * b); // 三次平滑，格与格之间不出现硬边。
    float2 uv = 17.0 * p.z + p.xy + b.xy; // 把三层格子压到二维坐标，十七是原程序打散层数的常数。
    float2 rg = noiseTexture.SampleLevel((uv + 0.5) / noiseResolution, 0.0).zx; // 取两张通道，零号层级与原来的即时采样一致。
    return lerp(rg.x, rg.y, b.z); // 按格内高度在两层之间插值。
}

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
// `shift` 是每层之间的时间位移，让细节缓慢流动而不是整块平移。
float ogxCloudFbm(float3 position, float3 shift, Sampler2D noiseTexture, float noiseResolution)
{
    const int octaves = 4; // 四层就够，再多在远景里看不出来。
    const float octAlpha = 0.87; // 每层权重只衰减一成多，细节保留得多。
    const float octScale = 2.5; // 每层频率放大二点五倍，避免相邻层太像。
    const float octShift = (octAlpha / octScale) / float(octaves); // 层间偏移，把结果抬回零附近。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 第一层权重。
    for (int i = 0; i < octaves; i++) // 逐层叠加。
    {
        accum += alpha * ogxEnd3dNoise(position, noiseTexture, noiseResolution); // 加这一层。
        position = (position + shift) * octScale; // 抬高频率并错开时间。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift; // 返回归一化后的噪声。
}

// 云状分形噪声的低质量版本：三层、每层权重衰减零点九、频率乘二，供远景或低画质使用。
// 与 `ogxCloudFbm` 分开保留，因为层数和衰减常数不同，不能用一个参数偷偷替换参考路径。
float ogxCloudFbmLq(float3 position, float3 shift, Sampler2D noiseTexture, float noiseResolution)
{
    const int octaves = 3; // 三层。
    const float octAlpha = 0.9; // 每层权重衰减。
    const float octScale = 2.0; // 每层频率倍数。
    const float octShift = (octAlpha / octScale) / float(octaves); // 层间偏移。
    float accum = 0.0; // 累积噪声。
    float alpha = 0.5; // 第一层权重。
    for (int i = 0; i < octaves; i++) // 逐层叠加。
    {
        accum += alpha * ogxEnd3dNoise(position, noiseTexture, noiseResolution); // 加这一层。
        position = (position + shift) * octScale; // 抬高频率并错开时间。
        alpha *= octAlpha; // 权重衰减。
    }
    return accum + octShift; // 返回归一化后的噪声。
}

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float ogxNetherFogDensityAt(float3 pos, Sampler2D noiseTexture)
{
    pos /= 18.0; // 整体缩小，让格子更大。
    pos.xz *= 0.5; // 水平再压一半，雾团更扁。
    float3 p = floor(pos); // 整数格坐标。
    float3 f = fract(pos); // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 平滑小数。
    float2 uv = p.xz + f.xz + p.y * float2(0.0, 193.0); // 三维格子映射到二维图，纵轴加大偏移错开层。
    float2 xy = noiseTexture.SampleLevel(uv / 512.0, 0.0).yx; // 读两通道并交换，零号层级与旧实现一致。
    return lerp(xy.r, xy.g, f.y); // 按高度插值。
}

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
// 羽流给竖直烟柱，贴地烟给低处一层，两者取较大者，避免叠加过曝。
float ogxNetherFogCloudVolume(float3 pos, float time, Sampler2D noiseTexture)
{
    float3 samplePos = pos * float3(1.0, 1.0 / 48.0, 1.0); // 竖直拉伸，烟柱显得更高。
    float wind = pow(max(pos.y - 30.0, 0.0) / 15.0, 2.1); // 越高风偏移越大。
    float plumes = noiseTexture.SampleLevel((samplePos.xz + wind) / 256.0, 0.0).b; // 噪声蓝通道当羽流形状。
    float floorPlumes = clamp(0.3 - exp(plumes * -6.0), 0.0, 1.0); // 贴地烟的量。
    plumes *= plumes; // 平方拉开烟与空的差别。
    float erosion = ogxNetherFogDensityAt(samplePos * 400.0 - time * 10.0 - wind * 10.0, noiseTexture) * 0.7 + 0.3; // 随时间的侵蚀。
    float roofToFloor = exp(max(100.0 - pos.y, 0.0) / -15.0); // 从天花板到地面变淡。
    float floorFalloff = pow(exp(max(pos.y - 31.0, 0.0) / -3.0), 2.0); // 离地越高越淡。
    return max((roofToFloor - plumes * (1.0 - erosion)) * 2.0, clamp((floorFalloff - floorPlumes * 0.5) * erosion, 0.0, 1.0)); // 两种形状取大者。
}

// 末地涡旋噪声：与下界单格密度同样的降维思路，但贴图边长由调用方给出。
float ogxEndVortexNoise(float3 pos, Sampler2D noiseTexture, float noiseResolution)
{
    pos /= 18.0; // 世界坐标缩到十八分之一，决定颗粒稀密。
    pos.xz *= 0.5; // 水平再压一半，雾团沿竖直拉长。
    float3 cell = floor(pos); // 所在整数格。
    float3 f = fract(pos); // 格内偏移。
    f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，格与格之间不出现硬边。
    float2 uv = cell.xz + f.xz + cell.y * float2(0.0, 193.0); // 三维到二维的分配，一百九十三打散高度。
    float2 xy = noiseTexture.SampleLevel(uv / noiseResolution, 0.0).yx; // 读上下两层并交换通道。
    return lerp(xy.r, xy.g, f.y); // 按格内高度插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// 先算旋转后与原始坐标的混合比例，再插值，避免远处雾团被整片拧动。
void ogxEndVortexSwirl(inout float3 alteredOrigin, float3 origin, float time)
{
    float radiance = 2.39996 + alteredOrigin.y / 1.5 + time / 50.0; // 旋转角随时间与高度推进。
    float cosine = cos(radiance); // 旋转角的余弦，下面用显式公式代替矩阵。
    float sine = sin(radiance); // 旋转角的正弦。
    float2 rotated = float2(cosine * alteredOrigin.x + sine * alteredOrigin.z, cosine * alteredOrigin.z - sine * alteredOrigin.x); // 与旧实现的「行向量乘矩阵」逐项相同。
    float swirlBounds = clamp(sqrt(max(length(float3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转。
    alteredOrigin.xz = lerp(rotated, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void ogxEndVortexBounds(inout float volume, float3 origin)
{
    float3 origin2 = origin - float3(0.0, 100.0, 0.0); // 相对高度一百的中心。
    origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
    float center = length(origin2); // 到中心的距离。
    float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
    float radius = 150.0; // 主岛圆环的半径。
    float thickness = 25.0 * radius; // 圆环判定的厚度尺度，取大得到平缓边缘。
    float torus = (thickness - clamp(pow(length(float2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
    volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 末地雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float ogxEndVortexShape(float3 pos, float time, Sampler2D noiseTexture, float noiseResolution)
{
    float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距原点三百格内为涡旋核心。
    float3 samplePos = pos * float3(1.0, 1.0 / 48.0, 1.0); // 竖直压扁，得到分层云感。
    float voidZone = max(exp2(-sqrt(max(pos.y + 60.0, 0.0))), 0.0); // 主岛下方六十格起逐渐发白。
    ogxEndVortexSwirl(samplePos, pos, time); // 把采样坐标按漩涡旋转。
    float noise = ogxEndVortexNoise(samplePos * 12.0, noiseTexture, noiseResolution); // 基础噪声决定浓淡。
    float erosion = 1.0 - ogxEndVortexNoise((samplePos - time / 18.0) * (124.0 + (1.0 - noise) * 7.0), noiseTexture, noiseResolution); // 随时间上升的侵蚀噪声。
    float clumpyFog = max(exp(noise * -lerp(10.0, 4.0, vortexBounds)) * lerp(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
    ogxEndVortexBounds(clumpyFog, pos); // 按体积限制减薄。
    return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float ogxEndVortexLightPhase(float3 lightPos)
{
    float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一。
    return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
float3 ogxEndVortexLighting(float3 startPos, float3 lightPos, float density, float3 lightColor, float time, Sampler2D noiseTexture, float noiseResolution)
{
    float phase = ogxEndVortexLightPhase(lightPos); // 到光柱中心的相位。
    float shadow = 0.0; // 沿光方向累积的遮挡。
    for (int j = 0; j < 3; j++) // 三步采样雾的遮挡。
    {
        float3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * 0.25); // 从当前点向光柱中心退回采样。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution); // 累加遮挡。
    }
    float3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
    lighting += lightColor * phase * phase * (1.0 - exp(-shadow * float3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
    return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// 步数、步长分布、密度颜色与输出缩放全由参数给出，因为远景开关与画质选项属于宿主。
float4 ogxEndVortexFog(float3 cameraPos, float3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist,
    float3 vortexColor, float3 ambientColor, float stormScale, float hazeDensity, float time,
    Sampler2D noiseTexture, float noiseResolution, float outputScale)
{
    float3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
    float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
    float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
    rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
    float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
    float3 color = float3(0.0); // 累积的雾发光。
    float absorbance = 1.0; // 累积的透过率，用来给后面的光正确留出通道。
    float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
    float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
    for (int i = 0; i < sampleCount; i++) // 逐步前进。
    {
        float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
        float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
        float3 progressW = cameraPos + d * rayWorld; // 这一步的世界位置。
        float3 lightPos = progressW - float3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处。
        float volumeDensity = ogxEndVortexShape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
        float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPos) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
        float stormDensity = min(volumeDensity, clearArea * clearArea * stormScale); // 风暴部分按贴脸留空与密度封顶。
        float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
        float3 lightsources = ogxEndVortexLighting(progressW, lightPos, volumeDensity, vortexColor, time, noiseTexture, noiseResolution); // 这一步的雾内光柱发光。
        float3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
        float3 stormLighting = indirect + lightsources; // 这一步的总发光。
        color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
        absorbance *= volumeCoeff; // 透过率继续衰减。
        float3 hazeLighting = float3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
        color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
    }
    return float4(color * outputScale, absorbance); // 散射色换算到管线单位，剩余透射率一并交回。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分，最后乘风暴与雾霭两层密度。
// `VdotL` 是视线与光方向余弦，`angleX`、`angleY` 是行星相位角，`planetShadow` 是行星遮挡权重。
float ogxEndFogDensity(float3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale)
{
    float3x3 eyeRoataionMatrixX = float3x3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
    float3x3 eyeRoataionMatrixY = float3x3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
    float3x3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。
    float3 dir = ogxMatrix3MulPoint(eyeRoataionMatrix, worldDir); // 视线转到相位坐标系。
    dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
    float h = abs(dir.z) * dist * 0.03; // 沿视线方向的等效高度。
    float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。
    float storm = ogxMiePhase(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分。
    float haze = 0.25; // 不带方向的雾霭基准部分。
    float density = fogDepth * (storm * stormScale + haze * hazeScale); // 两层分别缩放后相加。
    density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。
    return density; // 交回未换算单位的密度。
}

// 下界群系自发光：五个群系各给一种基色与强度，按平滑权重相加后再乘整体亮度。
// 为什么每个群系单独一项：下界没有太阳，画面亮度全靠这组写死的基色撑着，群系之间差别很大。
float3 ogxNetherBiomeLighting(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness)
{
    float3 lighting = netherWastes * float3(0.99, 0.34, 0.10) * 4.5e-4; // 荒地偏橙红，最弱。
    lighting += soulSandValley * float3(0.60, 0.77, 1.00) * 2e-4; // 灵魂沙峡谷偏青蓝，更暗。
    lighting += crimsonForest * float3(1.00, 0.80, 0.57) * 4e-4; // 绯红森林偏暖白。
    lighting += warpedForest * float3(0.79, 0.82, 1.00) * 2.5e-4; // 诡异森林偏冷蓝。
    lighting += basaltDeltas * float3(1.00, 0.78, 0.62) * 1e-3; // 玄武岩三角洲最亮。
    return lighting * brightness; // 按整体亮度缩放。
}

// 下界群系雾色：前三个分量是颜色，第四个分量是密度，五个群系按同一套权重混合。
// 为什么密度也按群系混合：玄武岩三角洲的灰雾最浓、诡异森林最淡，颜色和浓度本来就该一起变。
float4 ogxNetherBiomeFogColor(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness, float density)
{
    float4 fog = float4(0.990, 0.170, 0.005, 0.010) * netherWastes; // 荒地橙红、中等密度。
    fog += float4(0.010, 0.035, 0.060, 0.007) * soulSandValley; // 灵魂沙峡谷近乎黑青。
    fog += float4(0.200, 0.020, 0.000, 0.010) * crimsonForest; // 绯红森林暗红。
    fog += float4(0.030, 0.100, 0.130, 0.007) * warpedForest; // 诡异森林暗青。
    fog += float4(0.400, 0.400, 0.400, 0.014) * basaltDeltas; // 玄武岩三角洲灰色、最浓。
    return fog * float4(brightness, brightness, brightness, density); // 颜色乘亮度、密度乘雾浓度。
}

// Eclipse 群系雾色：四个群系各给一组红绿蓝基色，按权重相加；返回本群系颜色与覆盖程度。
// 为什么颜色分量分开写：与参考文件一行对一行，之后核对某个群系的颜色不会看错列。
float3 ogxBiomeFogColor(float4 weights, float3 paleGarden, float3 swamp, float3 jungle, float3 darkForest, out float coverage)
{
    coverage = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 四个群系权重之和就是覆盖程度。
    float3 color = float3(0.0); // 默认不在任何群系内，颜色为零。
    color.r = weights.w * paleGarden.r + weights.x * swamp.r + weights.y * jungle.r + weights.z * darkForest.r; // 红色分量。
    color.g = weights.w * paleGarden.g + weights.x * swamp.g + weights.y * jungle.g + weights.z * darkForest.g; // 绿色分量。
    color.b = weights.w * paleGarden.b + weights.x * swamp.b + weights.y * jungle.b + weights.z * darkForest.b; // 蓝色分量。
    return color; // 交回群系雾色。
}

// Eclipse 群系雾密度：把高度衰减雾与团雾两套密度朝当前群系混合，远处按包络退回原值。
// `weights` 顺序是沼泽、丛林、黑森林、苍白花园；`maxDistance` 是随距离收敛的包络。
void ogxBiomeFogDensity(float4 weights, inout float uniformDensity, inout float cloudyDensity,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 落在任一已启用群系内的程度。
    float biomeUniform = weights.x * swampUniform + weights.y * jungleUniform + weights.z * darkForestUniform + weights.w * paleGardenUniform; // 高度衰减雾密度加权和。
    float biomeCloudy = weights.x * swampCloudy + weights.y * jungleCloudy + weights.z * darkForestCloudy + weights.w * paleGardenCloudy; // 团雾密度加权和。
    float blend = inBiome * maxDistance; // 群系内且靠近相机时才替换。
    uniformDensity = lerp(uniformDensity, biomeUniform, blend); // 高度衰减雾朝群系值混合。
    cloudyDensity = lerp(cloudyDensity, biomeCloudy, blend); // 团雾朝群系值混合。
}

// Eclipse 的群系雾密度：把沼泽、丛林、黑森林、苍白花园、沙暴、雪暴六类分开加权。
// 参考实现先算总权重，再分别写密度两个分量；沙暴高度密度为零，雪暴固定 0.01。
void ogxBiomeFogDensityEclipse(inout float4 uniformDensity, inout float4 cloudyDensity,
    float paleGarden, float jungles, float swamps, float darkForests, float sandStorm, float snowStorm,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(paleGarden + jungles + swamps + darkForests + sandStorm + snowStorm, 0.0, 1.0); // 六类群系的总权重。
    float2 density = float2(0.0); // 高度密度与团雾密度。
    density.x = swamps * swampUniform + jungles * jungleUniform + darkForests * darkForestUniform
              + sandStorm * 0.0 + snowStorm * 0.01; // 高度密度里沙暴为零、雪暴固定 0.01。
    density.y = paleGarden * paleGardenCloudy + swamps * swampCloudy + jungles * jungleCloudy
              + darkForests * darkForestCloudy + sandStorm * 0.5 + snowStorm * 0.5; // 团雾密度六类都参与。
    uniformDensity = lerp(uniformDensity, float4(density.x), inBiome * maxDistance); // 高度密度混合。
    cloudyDensity = lerp(cloudyDensity, float4(density.y), inBiome * maxDistance); // 团雾密度混合。
}

// Eclipse 末地雾的相函数：与云相函数同形，但常数用 3.14 而不是 pi，保留参考精度。
float ogxEndFogPhaseEclipse(float x, float g)
{
    float gg = g * g; // g 的平方。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现直接写 3.14。
}

// iterationT 的原版雾叠加：黑暗、失明、水下与岩浆四种状态分别压暗画面。
// 为什么按状态分开：每种状态的距离范围与目标颜色不同，合并会改变边界。
float3 ogxVanillaFog(float3 color, float dist, float farPlane, float darkness, float blindness,
    int eyeInWater, float torchBrightness)
{
    if (darkness > 0.0) // 黑暗效果：远处逐步变黑。
    {
        color = lerp(color, float3(0.0), smoothstep(5.0, lerp(farPlane, 15.0, darkness), dist) * darkness);
    }
    if (blindness > 0.0) // 失明效果：更近距离变黑。
    {
        color = lerp(color, float3(0.0), smoothstep(1.5, lerp(farPlane, 4.5, blindness), dist) * blindness);
    }
    if (eyeInWater == 3) // 细雪或粉雪：近处压成深灰。
    {
        color = lerp(color, float3(0.03), smoothstep(0.0, 2.0, dist));
    }
    if (eyeInWater == 2) // 岩浆：近处压成暖橙。
    {
        color = lerp(color, float3(0.3721, 0.0775, 0.0024) * torchBrightness, smoothstep(0.0, 1.0, dist));
    }
    return color; // 返回叠加后的颜色。
}

// iterationT 的选择框：选中方块时用贴图色乘曝光统计值，覆盖原画面。
float3 ogxSelectionBox(float3 color, float3 albedo, bool isSelection, float exposureEncoded, float exposureOutputFactor)
{
    if (!isSelection) return color; // 没有选中就不改。
    float exposure = exposureEncoded * exposureEncoded * exposureEncoded * exposureEncoded; // CurveToLinear 的标量版。
    exposure *= 1500.0 / exposureOutputFactor; // 参考实现的曝光缩放。
    return albedo * exposure; // 选中框用贴图色乘曝光。
}

#endif
