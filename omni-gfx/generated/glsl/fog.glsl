/*
生成文件：雾模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库雾模块：高度衰减、噪声雾团、粉末效应、混合相位与沿视线积分。
调用位置：地形、水面与低空空气的雾；Minecraft 光影由 `/omni-gfx/fog.glsl` 引入。
可复制示例：
    OgxFog f = ogxFogDefault(); // 取默认雾。
    vec4 r = ogxFogMarch(f, camKm, worldKm, sunDir, sunColor, j, 10); // 沿视线积分雾。
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
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/noise.glsl"
// 一层低空雾的参数；不同群系或天气换字段即可。
struct OgxFog
{
    vec3 color; // 雾的环境色，线性空间。
    float density; // 基础高度处的密度，每公里。
    float heightFalloff; // 离开基础高度后的衰减距离，公里。
    float baseHeight; // 最浓的高度，公里。
    float noiseScale; // 雾团的水平尺度，每公里。
    float noiseStrength; // 噪声对密度的调制强度，零到一。
    vec3 wind; // 水平风向，公里。
    float sunStrength; // 阳光在雾里的散射强度。
};

// 默认低空雾：贴地薄雾，密度适中，云影下会自然变暗。
OgxFog ogxFogDefault()
{
    OgxFog fog; // 先声明再填写字段。
    fog.color = vec3(0.55, 0.68, 0.82); // 偏冷的天空色。
    fog.density = 0.18; // 每公里密度，远景能看到空气感。
    fog.heightFalloff = 0.06; // 六十米高度衰减，雾贴在低空。
    fog.baseHeight = 0.0; // 海平面最浓。
    fog.noiseScale = 9.0; // 百米级雾团。
    fog.noiseStrength = 0.75; // 噪声明显但不把雾打碎。
    fog.wind = vec3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    fog.sunStrength = 1.0; // 阳光散射默认全强。
    return fog; // 返回可直接修改的默认值。
}

// 雾密度：高度指数衰减乘三维噪声，得到会流动的雾团。
float ogxFogDensity(OgxFog fog, vec3 position)
{
    float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
    vec3 noisePosition = (position + fog.wind) * fog.noiseScale; // 换到雾坐标并叠加风。
    float noise = ogxFbm3(noisePosition, 3); // 三层次雾团。
    return fog.density * height * mix(1.0, noise * 1.6, ogxSaturate(fog.noiseStrength)); // 噪声只调制密度，不改变高度剖面。
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
    return mix(1.0, powder, ogxSaturate(0.5 - 0.5 * nu)); // 只影响背光方向。
}

// 沿视线积分雾：返回预乘散射色与剩余透过率。
vec4 ogxFogMarch(OgxFog fog, vec3 camera, vec3 worldPosition, vec3 sunDirection,
                   vec3 sunColor, float jitter, int steps)
{
    vec3 delta = worldPosition - camera; // 相机到目标点的向量。
    float distance = length(delta); // 视线长度，公里。
    if (distance <= 1e-5) // 零长度不产生雾。
    {
        return vec4(0.0, 0.0, 0.0, 1.0); // 完全透明。
    }
    vec3 viewDirection = delta / distance; // 单位视线方向。
    const int maxSteps = 24; // 固定循环上限。
    int count = min(max(steps, 1), maxSteps); // 调用方可以降低质量。
    float stepLength = distance / float(count); // 每步长度。
    float distanceAlongRay = stepLength * ogxSaturate(jitter); // 抖动起点，减少层状条纹。
    float transmittance = 1.0; // 初始完全透明。
    vec3 scattered = vec3(0.0); // 累积散射光。
    float nu = dot(viewDirection, sunDirection); // 视线与阳光夹角。
    float phase = ogxFogPhase(nu); // 混合相位。
    for (int i = 0; i < maxSteps; i++) // 逐步穿过雾层。
    {
        if (i >= count) // 超过质量设置就停止。
        {
            break; // 提前结束。
        }
        vec3 position = camera + viewDirection * distanceAlongRay; // 当前采样点。
        float density = ogxFogDensity(fog, position); // 当前密度。
        if (density > 0.001) // 空区域跳过。
        {
            float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
            float powder = ogxFogPowder(density, nu); // 薄雾的多次散射。
            vec3 sun = sunColor * fog.sunStrength * (phase * 2.0 + 0.15) * height * powder; // 阳光散射。
            vec3 ambient = fog.color * (0.30 + 0.70 * height); // 环境光。
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
    return vec4(scattered, transmittance); // 返回预乘散射色与剩余透过率。
}

// 把雾应用到已经着色的颜色：先乘剩余透过率，再加散射色。
vec3 ogxFogApply(vec3 color, vec4 fog)
{
    return color * fog.a + fog.rgb; // 预乘散射色直接相加。
}

// 粉末效应：背光时气溶胶把光往前推，边缘因此更亮，正对时补偿回去。
float ogxLegacyPowder(float absorption, float lightingAbsorption, float VdotL)
{
    return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越强效果越强。
}

// 混合相位：后向与前向两个米氏相位加权，雾的轮廓在逆光时仍有层次。
float ogxLegacyFogPhase(float VdotL)
{
    return ogxMiePhase(-0.4, VdotL) * 0.3 + ogxMiePhase(0.5, VdotL) * 0.7; // 前向占七成。
}

// 多次散射相位：四个衰减档各给一个相位，用来叠出体积雾的多层散射。
// 返回四分量的原因是 GLSL 的数组参数在 Slang 里没有等价写法，四档直接装进一个向量。
vec4 ogxMultiScatteringPhases(float VdotL)
{
    return vec4(ogxLegacyFogPhase(VdotL), ogxLegacyFogPhase(VdotL * 0.5),
                  ogxLegacyFogPhase(VdotL * 0.25), ogxLegacyFogPhase(VdotL * 0.125)); // 四档角度逐次减半，与旧实现的循环一致。
}

// 雾密度的高度剖面：两层高度之间的空气最浓，离开这段距离按指数下降，夜间更浓。
float ogxFogDensityHeight(vec3 fogPos, float heightA, float heightB, float falloff, float timeMidnight)
{
    float maxHeight = max(heightA, heightB); // 两层里较高的。
    float minHeight = min(heightA, heightB); // 两层里较低的。
    float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到浓度层的距离。
    dh *= 2.0 / falloff; // 按衰减距离归一化。
    float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢。
    return density * 0.1; // 乘基础密度。
}

// 噪声雾密度：高度包络乘四层噪声，平方两次让雾团边界清楚。
float ogxFogDensityNoise(vec3 fogPos, vec3 wind, float heightA, float heightB, float falloff,
    float timeMidnight, sampler2D noiseTexture)
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
float ogxEnd3dNoise(vec3 position, sampler2D noiseTexture, float noiseResolution)
{
    vec3 p = floor(position); // 整数格决定用贴图哪一块。
    vec3 b = fract(position); // 格内偏移用于插值。
    b = b * b * (3.0 - 2.0 * b); // 三次平滑，格与格之间不出现硬边。
    vec2 uv = 17.0 * p.z + p.xy + b.xy; // 把三层格子压到二维坐标，十七是原程序打散层数的常数。
    vec2 rg = textureLod(noiseTexture, (uv + 0.5) / noiseResolution, 0.0).zx; // 取两张通道，零号层级与原来的即时采样一致。
    return mix(rg.x, rg.y, b.z); // 按格内高度在两层之间插值。
}

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
// `shift` 是每层之间的时间位移，让细节缓慢流动而不是整块平移。
float ogxCloudFbm(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution)
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

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float ogxNetherFogDensityAt(vec3 pos, sampler2D noiseTexture)
{
    pos /= 18.0; // 整体缩小，让格子更大。
    pos.xz *= 0.5; // 水平再压一半，雾团更扁。
    vec3 p = floor(pos); // 整数格坐标。
    vec3 f = fract(pos); // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 平滑小数。
    vec2 uv = p.xz + f.xz + p.y * vec2(0.0, 193.0); // 三维格子映射到二维图，纵轴加大偏移错开层。
    vec2 xy = textureLod(noiseTexture, uv / 512.0, 0.0).yx; // 读两通道并交换，零号层级与旧实现一致。
    return mix(xy.r, xy.g, f.y); // 按高度插值。
}

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
// 羽流给竖直烟柱，贴地烟给低处一层，两者取较大者，避免叠加过曝。
float ogxNetherFogCloudVolume(vec3 pos, float time, sampler2D noiseTexture)
{
    vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直拉伸，烟柱显得更高。
    float wind = pow(max(pos.y - 30.0, 0.0) / 15.0, 2.1); // 越高风偏移越大。
    float plumes = textureLod(noiseTexture, (samplePos.xz + wind) / 256.0, 0.0).b; // 噪声蓝通道当羽流形状。
    float floorPlumes = clamp(0.3 - exp(plumes * -6.0), 0.0, 1.0); // 贴地烟的量。
    plumes *= plumes; // 平方拉开烟与空的差别。
    float erosion = ogxNetherFogDensityAt(samplePos * 400.0 - time * 10.0 - wind * 10.0, noiseTexture) * 0.7 + 0.3; // 随时间的侵蚀。
    float roofToFloor = exp(max(100.0 - pos.y, 0.0) / -15.0); // 从天花板到地面变淡。
    float floorFalloff = pow(exp(max(pos.y - 31.0, 0.0) / -3.0), 2.0); // 离地越高越淡。
    return max((roofToFloor - plumes * (1.0 - erosion)) * 2.0, clamp((floorFalloff - floorPlumes * 0.5) * erosion, 0.0, 1.0)); // 两种形状取大者。
}

// 末地涡旋噪声：与下界单格密度同样的降维思路，但贴图边长由调用方给出。
float ogxEndVortexNoise(vec3 pos, sampler2D noiseTexture, float noiseResolution)
{
    pos /= 18.0; // 世界坐标缩到十八分之一，决定颗粒稀密。
    pos.xz *= 0.5; // 水平再压一半，雾团沿竖直拉长。
    vec3 cell = floor(pos); // 所在整数格。
    vec3 f = fract(pos); // 格内偏移。
    f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，格与格之间不出现硬边。
    vec2 uv = cell.xz + f.xz + cell.y * vec2(0.0, 193.0); // 三维到二维的分配，一百九十三打散高度。
    vec2 xy = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 读上下两层并交换通道。
    return mix(xy.r, xy.g, f.y); // 按格内高度插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// 先算旋转后与原始坐标的混合比例，再插值，避免远处雾团被整片拧动。
void ogxEndVortexSwirl(inout vec3 alteredOrigin, vec3 origin, float time)
{
    float radiance = 2.39996 + alteredOrigin.y / 1.5 + time / 50.0; // 旋转角随时间与高度推进。
    float cosine = cos(radiance); // 旋转角的余弦，下面用显式公式代替矩阵。
    float sine = sin(radiance); // 旋转角的正弦。
    vec2 rotated = vec2(cosine * alteredOrigin.x + sine * alteredOrigin.z, cosine * alteredOrigin.z - sine * alteredOrigin.x); // 与旧实现的「行向量乘矩阵」逐项相同。
    float swirlBounds = clamp(sqrt(max(length(vec3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转。
    alteredOrigin.xz = mix(rotated, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void ogxEndVortexBounds(inout float volume, vec3 origin)
{
    vec3 origin2 = origin - vec3(0.0, 100.0, 0.0); // 相对高度一百的中心。
    origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
    float center = length(origin2); // 到中心的距离。
    float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
    float radius = 150.0; // 主岛圆环的半径。
    float thickness = 25.0 * radius; // 圆环判定的厚度尺度，取大得到平缓边缘。
    float torus = (thickness - clamp(pow(length(vec2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
    volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 末地雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float ogxEndVortexShape(vec3 pos, float time, sampler2D noiseTexture, float noiseResolution)
{
    float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距原点三百格内为涡旋核心。
    vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直压扁，得到分层云感。
    float voidZone = max(exp2(-sqrt(max(pos.y + 60.0, 0.0))), 0.0); // 主岛下方六十格起逐渐发白。
    ogxEndVortexSwirl(samplePos, pos, time); // 把采样坐标按漩涡旋转。
    float noise = ogxEndVortexNoise(samplePos * 12.0, noiseTexture, noiseResolution); // 基础噪声决定浓淡。
    float erosion = 1.0 - ogxEndVortexNoise((samplePos - time / 18.0) * (124.0 + (1.0 - noise) * 7.0), noiseTexture, noiseResolution); // 随时间上升的侵蚀噪声。
    float clumpyFog = max(exp(noise * -mix(10.0, 4.0, vortexBounds)) * mix(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
    ogxEndVortexBounds(clumpyFog, pos); // 按体积限制减薄。
    return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float ogxEndVortexLightPhase(vec3 lightPos)
{
    float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一。
    return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
vec3 ogxEndVortexLighting(vec3 startPos, vec3 lightPos, float density, vec3 lightColor, float time, sampler2D noiseTexture, float noiseResolution)
{
    float phase = ogxEndVortexLightPhase(lightPos); // 到光柱中心的相位。
    float shadow = 0.0; // 沿光方向累积的遮挡。
    for (int j = 0; j < 3; j++) // 三步采样雾的遮挡。
    {
        vec3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * 0.25); // 从当前点向光柱中心退回采样。
        shadow += ogxEndVortexShape(shadowSamplePos, time, noiseTexture, noiseResolution); // 累加遮挡。
    }
    vec3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
    lighting += lightColor * phase * phase * (1.0 - exp(-shadow * vec3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
    return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// 步数、步长分布、密度颜色与输出缩放全由参数给出，因为远景开关与画质选项属于宿主。
vec4 ogxEndVortexFog(vec3 cameraPos, vec3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist,
    vec3 vortexColor, vec3 ambientColor, float stormScale, float hazeDensity, float time,
    sampler2D noiseTexture, float noiseResolution, float outputScale)
{
    vec3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
    float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
    float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
    rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
    float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
    vec3 color = vec3(0.0); // 累积的雾发光。
    float absorbance = 1.0; // 累积的透过率，用来给后面的光正确留出通道。
    float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
    float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
    for (int i = 0; i < sampleCount; i++) // 逐步前进。
    {
        float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
        float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
        vec3 progressW = cameraPos + d * rayWorld; // 这一步的世界位置。
        vec3 lightPos = progressW - vec3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处。
        float volumeDensity = ogxEndVortexShape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
        float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPos) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
        float stormDensity = min(volumeDensity, clearArea * clearArea * stormScale); // 风暴部分按贴脸留空与密度封顶。
        float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
        vec3 lightsources = ogxEndVortexLighting(progressW, lightPos, volumeDensity, vortexColor, time, noiseTexture, noiseResolution); // 这一步的雾内光柱发光。
        vec3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
        vec3 stormLighting = indirect + lightsources; // 这一步的总发光。
        color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
        absorbance *= volumeCoeff; // 透过率继续衰减。
        vec3 hazeLighting = vec3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
        color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
    }
    return vec4(color * outputScale, absorbance); // 散射色换算到管线单位，剩余透射率一并交回。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分，最后乘风暴与雾霭两层密度。
// `VdotL` 是视线与光方向余弦，`angleX`、`angleY` 是行星相位角，`planetShadow` 是行星遮挡权重。
float ogxEndFogDensity(vec3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale)
{
    mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
    mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
    mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。
    vec3 dir = ogxMatrix3MulPoint(eyeRoataionMatrix, worldDir); // 视线转到相位坐标系。
    dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
    float h = abs(dir.z) * dist * 0.03; // 沿视线方向的等效高度。
    float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。
    float storm = ogxMiePhase(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分。
    float haze = 0.25; // 不带方向的雾霭基准部分。
    float density = fogDepth * (storm * stormScale + haze * hazeScale); // 两层分别缩放后相加。
    density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。
    return density; // 交回未换算单位的密度。
}

#endif
