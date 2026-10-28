/*
Omni 通用图形库体积云模块：Nubis / Hillaire 风格的积云形状、光照、步进与云影。
调用位置：任何需要体积云的程序；Minecraft 光影由 `/omni-gfx/cloud/volume.glsl` 引入，
    `rendering/cloud/volumetric.glsl` 只把选项、天气与纹理换成参数。
可复制示例：
    OgxCumulusMedia media = ...; // 填好云底、云顶、风与光照强度。
    float3 hit; // 平均命中位置，供大气淡出使用。
    float4 cloud = ogxCumulusMarch(viewDir, media, jitter, hit, baseTex, detailTex, curlTex,
                                   40.0, 1.0, sunDir, 1.0, 0.0, 3.0, 1.2);
    // cloud.rgb 是预乘散射颜色，cloud.a 是透射率；调用方按 1 - cloud.a 合成覆盖率。
设计原因与取舍：
    形状来自三维 Perlin-Worley 基础噪声与高频 Worley 侵蚀。基础噪声先决定云块位置，
    高频噪声再从边缘往里削，云边因此是一簇簇花椰菜状的小鼓包，不是光滑的椭球。
    云底用快速收口的竖直包络压平，云顶用圆滑曲线收圆；没有固定的塔身或砧状遮罩，
    所以同一套参数不会生成窄柱状轮廓，云形完全由风、云量与噪声决定。
    光照沿太阳方向步进，单次散射与三档多次散射分开：厚云内部靠慢衰减的多次散射托起，
    薄边再加逆光透射，云底不会黑成纸片，云顶与向阳面保持亮白。
    纹理、云层高度、风、天气与太阳方向全部由调用方传入，库不读取选项或宿主状态。
    结构体字段沿用旧名字：宿主有几十处逐字段赋值，改名会把风险推到调用点。
*/
#ifndef OGX_CLOUD_VOLUME_INCLUDED
#define OGX_CLOUD_VOLUME_INCLUDED

// 云模块提供顶部曲线与相位函数，数学提供球面求交与夹紧。
#include "cloud.slang"
// 颜色模块提供参考的曲线函数。
#include "../color.slang"
#include "../math.slang"

// 体积云的一层参数；不同云层换字段即可复用同一套步进。
struct OgxCumulusMedia
{
    float3 wind; // 风的位移，单位与云坐标一致。
    float3 camera_position; // 相机绝对世界位置，供云影与闪电使用。
    float3 light_color; // 直射光颜色。
    float3 sky_color; // 天空环境光颜色。
    float3 lightning_position; // 闪电光柱中心，相机相对坐标。
    float2 altitude; // 云层底与顶的高度，米。
    float2 lighting_strength; // 直射与环境强度。
    float planet_radius; // 行星半径，米。
    float cloud_scale; // 世界坐标到云坐标的倍率；一表示直接用米。
    float density_option; // 密度倍率。
    float coverage; // 这一层的云量下限，越大云越多。
    float wetness; // 零到一的湿润度。
    float bottom_brightness; // 云底保留的直射亮度。
    float outscatter_factor; // 外散射指数，薄处与云顶更亮。
    float lightning_intensity; // 闪电事件强度，零表示没有闪电。
    float lightning_strength; // 闪电亮度选项。
};

// 三次平滑曲线：把零到一压成两端缓、中间快的过渡。
float ogxCumulusCurve(float x)
{
    return x * x * (3.0 - 2.0 * x); // 两端导数为零，云的口沿不会出现折线。
}

// NUBIS 的顶部曲线：以 1 为顶点、在 0 与 2 处落到零的抛物线，用来把云顶收圆。
// 积云顶部的垂直密度曲线：底部厚、顶部逐渐变薄。
float ogxCumulusCurveTop(float x)
{
    x = x - 1.0; // 把顶点移到一。
    return 1.0 - x * x; // 二次曲线在两端降到零。
}

// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向随高度剪切。
// 曲率修正让远处的云跟着地球弧度下沉，否则云层会像一块硬板挂在天边。
// 为什么保留 `cloud_scale`：Minecraft 侧用公里，测试世界用米；调用方乘一次就能统一，
// 库内不再猜单位，也不会把覆盖率的低频坐标压成常数。
float4 ogxCumulusSetPos(float3 marchingPos, OgxCumulusMedia media)
{
    float4 cloudPos = float4(marchingPos, 0.0); // 前三通道是位置，第四通道是层内高度。
    cloudPos.y = length(cloudPos.xyz + float3(0.0, media.planet_radius, 0.0)) - media.planet_radius; // 球面距离。
    cloudPos.w = ogxRemapSaturate(cloudPos.y, media.altitude.x, media.altitude.y); // 层内归一化高度。
    cloudPos.xyz = cloudPos.xyz * media.cloud_scale + float3(30.0 * cloudPos.w, 0.0, -12.0 * cloudPos.w); // 高度剪切。
    return cloudPos; // 返回米制世界坐标或调用方指定的云坐标。
}

// 采样云密度：三维 Perlin-Worley 决定云块，高频 Worley 削出花椰菜边缘。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sampleDetail` 为假时跳过高频侵蚀。
float2 ogxCumulusSampleDensity(float4 cloudPos, OgxCumulusMedia media, bool sampleDetail, float coverage,
    Sampler3D baseNoise, Sampler3D detailNoise, Sampler2D curlNoise, float baseScale, float coverageOffset,
    float detailScale, float detailStrength)
{
    // 与 iterationT 的 NUBIS 逐行一致：yzw 三种 Worley 作为阈值，x 通道作为 Perlin-Worley 形状，
    // 再乘竖直包络。128 立方纹理的通道分布与这套公式直接对应，云块边缘才有细碎的花椰菜鼓包。
    float4 baseSample = baseNoise.SampleLevel(cloudPos.xyz * baseScale + media.wind * 10.0, 0.0);
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2;
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0);
    // 竖直包络：底部快速到达满密度形成平底，顶部用两段曲线收圆，云不会长成蘑菇柄。
    float shapeCurve = ogxCumulusCurveTop(ogxSaturate(1.0 - cloudPos.w)) * 0.5;
    shapeCurve += ogxCumulusCurve(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5;
    baseDensity *= shapeCurve;
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8;
    baseDensity *= lerp(1.0, ogxCumulusCurveTop(ogxSaturate(cloudPos.w * 3.0)), media.wetness);
    // 云量：同一纵列从云底到云顶共享同一份覆盖，积云才会从平底往上长。
    // 噪声低的地方阈值接近一，整列都是蓝天；噪声高的地方阈值下降，只留下被三维噪声填满的云块。
    float coverageNoise = baseNoise.SampleLevel(cloudPos.xyz * float3(8.5e-5, -1.0e-5, 8.5e-5)
        + media.wind + float3(coverageOffset, coverageOffset, coverageOffset), 0.0).x;
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage);
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0);
    // 密度控制：中段最厚，顶部收薄，底部保留平底；这两条曲线也决定云顶的亮边宽度。
    baseDensity *= ogxCumulusCurve(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0;
    baseDensity *= ogxCumulusCurveTop(ogxSaturate(cloudPos.w * 1.8));
    baseDensity = ogxSaturate(baseDensity);
    float detailedDensity = 0.0; // 高频侵蚀后的密度。
    if (baseDensity > 1.0e-6 && sampleDetail) // 只有基础密度存在才付细节成本。
    {
        float curl = curlNoise.SampleLevel(cloudPos.xy * 0.0001, 0.0).w; // 水平扭曲。
        cloudPos.xy += curl * (100.0 - cloudPos.w * 100.0); // 越靠云底扭曲越大，底部有翻滚感。
        // 三张 Worley 从大到小削掉云边：通道权重 0.625、0.25、0.125 与 iterationT 相同。
        float3 detailedNoise = detailNoise.SampleLevel(cloudPos.xyz * detailScale + media.wind * 140.0, 0.0).xyz;
        detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125;
        detailedDensity *= (0.21 - media.wetness * 0.11) * detailStrength; // 晴天边缘更碎，雨天更实。
        detailedDensity = ogxRemapSaturate(baseDensity, detailedDensity, 1.0); // 侵蚀不能超过基础密度。
    }
    else // 不需要细节时直接用基础密度。
    {
        detailedDensity = baseDensity;
    }
    return float2(baseDensity, detailedDensity); // 返回两份密度。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱，云采样点离柱越近越亮。
float3 ogxCumulusLightning(float3 relativePos, OgxCumulusMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return float3(0.0); // 没有闪电事件时不加。
    float3 boltPos = float3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z);
    float boltDistance = length(relativePos - boltPos); // 介质到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return float3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength);
}

// 云的光照：沿太阳方向五次取样，单次散射、宽相位与底光按 NUBIS 的权重组合。
// 为什么分为直射与环境两部分：厚云内部直射衰减极快，如果没有缓慢衰减的宽相位，
// 云底会黑成纸片；环境项同时给出天空色，背光面才不会只剩灰。
float3 ogxCumulusLighting(float3 marchingPos, OgxCumulusMedia media, float2 cloudDensity, float4 cloudPos, float noise,
    float vdotl, float coverage, float3 worldLight, Sampler3D baseNoise, Sampler3D detailNoise, Sampler2D curlNoise,
    float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    // 与 iterationT 相同：起始 28 米，五步，每步乘 1.5；前三步带高频细节。
    float stepLength = 28.0; // 起始步长，米。
    float lightingDensity = 0.0; // 沿太阳方向累积的密度乘距离。
    for (int i = 0; i < 5; i++) // 五次取样覆盖约三百米。
    {
        float4 checkPos = ogxCumulusSetPos(marchingPos + worldLight * stepLength * noise, media); // 取样点。
        lightingDensity += ogxCumulusSampleDensity(checkPos, media, i < 3, coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength).y * stepLength; // 累加消光。
        marchingPos += worldLight * stepLength; // 沿光方向推进。
        stepLength *= 1.5; // 远处步长更大，因为云的细节在远处会合并。
    }
    // 单次散射：两档相位相加，再乘底部亮度与高度外散射。
    float hg = ogxHenyeyGreenstein(vdotl, 0.7); // 强前向相位，逆光时出现银边。
    float direct = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - media.wetness * 0.8); // 单次散射。
    direct += (1.0 / (lightingDensity * 0.2 + 1.0)) * (ogxHenyeyGreenstein(vdotl, 0.2) + 0.1); // 多次散射的宽相位。
    direct *= hg * 2.0 + 1.0; // 逆光侧整体提升。
    direct *= lerp(media.bottom_brightness, 0.005 + pow(cloudDensity.y, media.outscatter_factor),
        ogxCumulusCurve(ogxSaturate(cloudPos.w * 3.333 - 0.333))); // 云底到云顶的亮度分配。
    direct *= pow(max(cloudPos.w, 0.05), 0.75); // 云顶更受光。
    float3 lightColor = media.light_color * (direct * media.lighting_strength.x * 36.0); // 直射项，系数与 iterationT 相同。
    // 天光：薄处与云顶接收更多环境光，云底保留蓝灰底色。
    float ambient = 1.0 - cloudDensity.x;
    ambient *= ogxFastSqrt(cloudPos.w);
    lightColor += media.sky_color * (ambient * media.lighting_strength.y * 0.35);
    lightColor += ogxCumulusLightning(marchingPos - media.camera_position, media, 400.0, -10.0);
    return lightColor; // 返回这一段的云颜色。
}

// 体积云步进核心：沿视线在云层里步进，返回预乘散射颜色与透射率；平均命中位置通过 `hitOffset` 交回。
// 为什么把空气透视留给调用方：天空散射属于大气效果，通用库只负责云本身的密度与光照。
float4 ogxCumulusMarch(float3 worldDir, OgxCumulusMedia media, float2 noise, out float3 hitOffset,
    Sampler3D baseNoise, Sampler3D detailNoise, Sampler2D curlNoise, float cloudSamples, float cloudQuality,
    float3 worldLight, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    float3 rayStart = float3(0.0, media.planet_radius + media.camera_position.y, 0.0); // 相机在行星球上的位置。
    float2 bottom = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.x); // 云底交点。
    float2 top = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.y); // 云顶交点。
    float2 marching = media.camera_position.y > media.altitude.y ? float2(top.x, bottom.x) : float2(bottom.y, top.y); // 进出顺序。
    float3 marchingStart = marching.x * worldDir; // 相对相机的起点。
    float3 marchingEnd = marching.y * worldDir; // 相对相机的终点。
    float inCloud = (1.0 - ogxSaturate((media.camera_position.y - media.altitude.y) * 0.005)) *
        (1.0 - ogxSaturate((media.altitude.x - media.camera_position.y) * 0.005)); // 相机在云层内时的权重。
    float inner = bottom.y >= 0.0 && media.camera_position.y > media.altitude.x ? bottom.x : top.y; // 云内起点。
    inner = min(inner, 5000.0);
    marchingStart = marchingStart * (1.0 - inCloud) + media.camera_position; // 相机在云内时从相机开始。
    marchingEnd = lerp(marchingEnd, inner * worldDir, inCloud) + media.camera_position; // 云内只走五公里。
    // 视线越接近地平线，云层法向长度越长；超过六十公里后云的细节已经小于一个像素，
    // 再步进只会把远处压成一条硬带，所以在这里截断，交给空气透视淡出。
    float span = length(marchingEnd - marchingStart);
    if (span > 60000.0)
    {
        marchingEnd = marchingStart + normalize(marchingEnd - marchingStart) * 60000.0;
    }
    float steps = cloudSamples - ogxSaturate(ogxFastSqrt(abs(worldDir.y)) * 1.4 - 0.4) * 8.0; // 朝上时省几步。
    steps = max(floor(steps * cloudQuality), 1.0);
    float stepSize = 1.0 / steps;
    float3 increment = (marchingEnd - marchingStart) * stepSize;
    float3 marchingPos = marchingStart + increment * noise.x; // 抖动起点，消除层状条纹。
    float densityMul = media.density_option * (media.altitude.y - media.altitude.x) * stepSize; // 消光系数。
    float vdotl = dot(worldDir, worldLight);
    float3 accum = float3(0.0);
    float transmittance = 1.0;
    float3 rayHit = float3(0.0);
    float sumTransmit = 0.0;
    for (int i = 0; i < int(steps); i++, marchingPos += increment)
    {
        float4 cloudPos = ogxCumulusSetPos(marchingPos, media);
        float2 cloudDensity = ogxCumulusSampleDensity(cloudPos, media, true, media.coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength);
        if (cloudDensity.y < 1.0e-6) continue; // 空区域跳过光照。
        float3 cloudColor = ogxCumulusLighting(marchingPos, media, cloudDensity, cloudPos, noise.y, vdotl, media.coverage,
            worldLight, baseNoise, detailNoise, curlNoise, baseScale, coverageOffset, detailScale, detailStrength);
        float absorption = exp2(-cloudDensity.y * densityMul); // 这一段的透过率。
        accum += cloudColor * (transmittance - absorption * transmittance);
        rayHit += marchingPos * transmittance;
        sumTransmit += transmittance;
        transmittance *= absorption;
        if (transmittance < 1.0e-4) break;
    }
    hitOffset = rayHit / max(sumTransmit, 1.0e-4) - media.camera_position;
    return float4(accum, transmittance);
}

// 云影贴图：从地面坐标沿太阳方向投到云层，取两处云密度合成阴影值。
// 为什么先算世界坐标再调用 `ogxCumulusSetPos`：主视线步进用的是同一条云坐标变换，
// 直接拿米制坐标去采样噪声会把云影裁成另一种尺度，地面阴影和天上的云块对不上。
float ogxCumulusShadowTex(float2 coord, OgxCumulusMedia media, float3 worldLight, float range, Sampler3D baseNoise,
    Sampler2D curlNoise, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    coord = coord * range - (range * 0.5); // 贴图坐标换回相对相机的地表坐标。
    float3 groundPos = float3(coord.x + media.camera_position.x, 0.0, coord.y + media.camera_position.z); // 地面点。
    float thickness = media.altitude.y - media.altitude.x; // 云层厚度。
    float invLightY = 1.0 / max(worldLight.y, 0.05); // 低阳时限制投影距离。
    float3 samplePos = groundPos + worldLight * ((media.altitude.x + thickness * 0.25) * invLightY); // 投到云层下段。
    float4 cloudPos = ogxCumulusSetPos(samplePos, media);
    float cloudDensity = ogxCumulusSampleDensity(cloudPos, media, false, media.coverage, baseNoise, baseNoise, curlNoise,
        baseScale, coverageOffset, detailScale, detailStrength).y; // 下段密度。
    samplePos = groundPos + worldLight * ((media.altitude.x + thickness * 0.50) * invLightY); // 再往上一段。
    cloudPos = ogxCumulusSetPos(samplePos, media);
    cloudDensity = max(cloudDensity, ogxCumulusSampleDensity(cloudPos, media, false, media.coverage, baseNoise, baseNoise,
        curlNoise, baseScale, coverageOffset, detailScale, detailStrength).y); // 两块取较厚的那块。
    return exp2(-cloudDensity * 20.0); // 密度换成透过率；系数与 iterationT 的云影一致。
}

// iterationT 的标量曲线：与参考 curve 同一个式子，用于云层竖直分布。
// iterationT 的软曲线：把输入压到零到一之间，避免高光过曝。
float ogxItxCurve(float x) { return 1.0 - x / (1.0 + x); }

// iterationT 云密度：基础三维噪声合成大尺度形状，覆盖率裁剪后再叠细节噪声。
// 参考签名是云坐标、风向与是否取细节；三张噪声图、尺度与天气参数显式追加。
// 为什么用 OGX_CLAMP01：参考的 saturate 是宏，换成函数会把 0 与 1 加进常数表。
float2 ogxItxCloudSampleDensity(float4 cloudPos, float3 windDirection, bool sampleDetail,
    Sampler3D baseNoise, Sampler3D detailNoise, Sampler2D curlNoise,
    float baseScale, float coverageOffset, float clearCoverage, float rainCoverage,
    float detailScale, float detailStrength, float wetness)
{
    float4 baseSample = baseNoise.SampleLevel(cloudPos.xyz * baseScale + windDirection * 10.0, 0.0);
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2; // 三个尺度加权成基础密度。
    baseDensity = OGX_CLAMP01((baseSample.x - (baseDensity - 1.0)) / (1.0 - (baseDensity - 1.0))); // 按天气通道重映射。
    float shapeCurve = ogxCumulusCurveTop(OGX_CLAMP01(1.0 - cloudPos.w)) * 0.5; // 顶部圆角。
    shapeCurve += ogxItxCurve(OGX_CLAMP01(1.15 - cloudPos.w * 1.43)) * 0.5; // 底部收口。
    baseDensity *= shapeCurve;
    baseDensity *= sqrt(OGX_CLAMP01(cloudPos.w * 2.5)) * 0.2 + 0.8; // 低空加厚。
    baseDensity *= lerp(1.0, ogxCumulusCurveTop(OGX_CLAMP01(cloudPos.w * 3.0)), wetness); // 雨天云顶更平。
    float coverageNoise = baseNoise.SampleLevel(cloudPos.xyz * float3(8.5e-5, -1.0e-5, 8.5e-5) + windDirection + coverageOffset, 0.0).x;
    float coverage = lerp(clearCoverage, rainCoverage, wetness); // 晴雨两档覆盖率。
    coverage = OGX_CLAMP01(((1.0 - coverageNoise) - coverage * 0.2) / (coverage - coverage * 0.2)); // 噪声决定边界。
    baseDensity = OGX_CLAMP01((baseDensity - coverage) / (1.0 - coverage)); // 覆盖率裁剪。
    baseDensity *= ogxItxCurve(OGX_CLAMP01(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0;
    baseDensity *= ogxCumulusCurveTop(OGX_CLAMP01(cloudPos.w * 1.8));
    baseDensity = OGX_CLAMP01(baseDensity);
    float detailedDensity = 0.0;
    if (baseDensity > 1e-6 && sampleDetail)
    {
        float curlNoiseValue = curlNoise.SampleLevel(cloudPos.xy * 0.0001, 0.0).w; // 卷曲噪声扭曲细节层。
        cloudPos.xy += curlNoiseValue * (100.0 - cloudPos.w * 100.0);
        float3 detailedNoise = detailNoise.SampleLevel(cloudPos.xyz * detailScale + windDirection * 140.0, 0.0).xyz;
        detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125; // 三层细节加权。
        detailedDensity *= (0.21 - wetness * 0.11) * detailStrength;
        detailedDensity = OGX_CLAMP01((baseDensity - detailedDensity) / (1.0 - detailedDensity)); // 细节侵蚀。
    }
    else
    {
        detailedDensity = baseDensity;
    }
    return float2(baseDensity, detailedDensity);
}

// iterationT 云光照：沿太阳方向五次取样，累计密度后合成直接散射、底部亮度与环境光。
// 参考签名是位置、云层高度、行星参数、光照强度、密度、云坐标、风向、抖动与夹角；
// 噪声图与天气尺度显式追加。SetCloudPos 的算式直接写进函数体，常数与参考相同。
float3 ogxItxCloudLighting(float3 marchingPos, float2 cloudAltitude, float planetRadius, float cloudScale,
    float2 lightingStrength, float2 cloudDensity, float4 cloudPos, float3 windDirection, float noise, float VdotL,
    Sampler3D baseNoise, Sampler3D detailNoise, Sampler2D curlNoise, float3 worldShadowVector, float wetness,
    float baseScale, float coverageOffset, float clearCoverage, float rainCoverage,
    float detailScale, float detailStrength, float3 colorShadowlight, float3 colorSkylight)
{
    float stepLength = 28.0; // 第一步长度。
    float lightingDensity = 0.0; // 沿光方向累积的密度。
    for (int i = 0; i < 5; i++, stepLength *= 1.5) // 五步，每步拉长一半。
    {
        float3 shadowSamplePos = marchingPos + worldShadowVector * stepLength * noise; // 抖动后的取样位置。
        float4 checkPos = float4(shadowSamplePos, 0.0); // 与参考相同的齐次云坐标。
        checkPos.y = length(checkPos.xyz + float3(0.0, planetRadius, 0.0)) - planetRadius; // 距地高度。
        checkPos.w = OGX_CLAMP01((checkPos.y - cloudAltitude.x) / (cloudAltitude.y - cloudAltitude.x)); // 归一化高度。
        checkPos.xyz = checkPos.xyz * cloudScale + float3(30.0 * checkPos.w, 0.0, -12.0 * checkPos.w); // 随高度倾斜的云坐标。
        lightingDensity += ogxItxCloudSampleDensity(checkPos, windDirection, i < 3,
            baseNoise, detailNoise, curlNoise, baseScale, coverageOffset, clearCoverage, rainCoverage,
            detailScale, detailStrength, wetness).y * stepLength; // 细节层密度累加。
        marchingPos += worldShadowVector * stepLength; // 前进。
    }
    float hg = ogxHenyeyGreenstein(VdotL, 0.7); // 强前向散射。
    float directScattering = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - wetness * 0.8); // 直接散射。
    directScattering += (1.0 / (lightingDensity * 0.2 + 1.0)) * (ogxHenyeyGreenstein(VdotL, 0.2) + 0.1); // 弱前向的多次散射。
    directScattering *= hg * 2.0 + 1.0;
    directScattering *= lerp(0.15, 0.005 + pow(cloudDensity.y, 1.3), ogxItxCurve(OGX_CLAMP01(cloudPos.w * 3.333 - 0.333))); // 底部亮度与云顶外散射。
    directScattering *= pow(max(cloudPos.w, 0.05), 0.75); // 越高越亮。
    float3 cloudColor = colorShadowlight * (directScattering * lightingStrength.x * 36.0); // 太阳侧颜色。
    float ambientScattering = 1.0 - cloudDensity.x; // 环境散射。
    ambientScattering *= sqrt(cloudPos.w);
    cloudColor += colorSkylight * (ambientScattering * lightingStrength.y * 0.35); // 天空侧补光。
    return cloudColor;
}

#endif
