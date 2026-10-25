/*
生成文件：体积云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库体积云模块：形状取样、光照步进、沿视线步进与云影。
调用位置：任何需要体积云的程序；Minecraft 光影由 `/omni-gfx/cloud_volume.glsl` 引入，
    `rendering/cloud/volumetric.glsl` 只把选项、天气与纹理换成参数。
可复制示例：
    vec3 hitOffset; // 平均命中位置，相机相对方向。
    vec4 layer = ogxCumulusMarch(worldDir, media, noise, hitOffset, baseTex, detailTex, curlTex, samples, quality, light);
设计原因与取舍：
    纹理、云层高度、风、天气与太阳方向全部由调用方传入，库不读取选项或宿主状态。
    基础云与附加层共用同一套步进核心；空气透视属于大气效果，留在调用方合成，库只交回加色项与透过率。
    结构体字段沿用旧名字：宿主有几十处逐字段赋值，改名会把风险推到调用点。
*/
#ifndef OGX_CLOUD_VOLUME_INCLUDED
#define OGX_CLOUD_VOLUME_INCLUDED

// 云模块提供顶部曲线与相位函数，数学提供球面求交与夹紧。
#include "/omni-gfx/cloud.glsl"
#include "/omni-gfx/math.glsl"
// 体积云的一层参数；基础云与卷云、高层云、积雨云共用同一套字段，避免每个附加层再写一份循环。
struct OgxCumulusMedia
{
    vec3 wind; // 风的位移方向与速度。
    vec3 camera_position; // 相机绝对世界位置，供云影与闪电使用。
    vec3 light_color; // 直射光颜色。
    vec3 sky_color; // 天空环境光颜色。
    vec3 lightning_position; // 闪电光柱中心，相机相对坐标。
    vec2 altitude; // 云层底与顶的高度。
    vec2 lighting_strength; // 直射与环境强度。
    float planet_radius; // 行星半径，米。
    float cloud_scale; // 云块水平尺度。
    float density_option; // 密度倍率。
    float coverage; // 这一层的云量下限。
    float wetness; // 零到一的湿润度。
    float bottom_brightness; // 云底亮度。
    float outscatter_factor; // 外散射指数。
    float lightning_intensity; // 闪电事件强度，零表示没有闪电。
    float lightning_strength; // 闪电亮度选项。
};

// 三次平滑曲线：把零到一压成两端缓、中间快的过渡。
float ogxCumulusCurve(float x)
{
    return x * x * (3.0 - 2.0 * x); // 两端导数为零，云的口沿不会出现折线。
}

// 把步进位置换成云坐标：竖直方向按行星曲率弯曲，水平方向加随高度增大的偏移。
// 曲率修正让远处的云跟着地球弧度下沉，否则云层会像一块硬板挂在天边。
vec4 ogxCumulusSetPos(vec3 marchingPos, OgxCumulusMedia media)
{
    vec4 cloudPos = vec4(marchingPos, 0.0); // 前三通道是位置，第四通道是层内高度。
    cloudPos.y = length(cloudPos.xyz + vec3(0.0, media.planet_radius, 0.0)) - media.planet_radius; // 用球面距离算真实高度。
    cloudPos.w = ogxRemapSaturate(cloudPos.y, media.altitude.x, media.altitude.y); // 在云层里的归一化高度。
    cloudPos.xyz = cloudPos.xyz * media.cloud_scale + vec3(30.0 * cloudPos.w, 0.0, -12.0 * cloudPos.w); // 水平缩放并随高度剪切，云因此有斜向层次。
    return cloudPos; // 返回云坐标。
}

// 采样云密度：基础形状乘云量得到不透明密度，再叠细节噪声得到碎边。
// 返回 `x` 是基础密度、`y` 是用于消光的最终密度；`sampleDetail` 为假时跳过细节以省性能。
vec2 ogxCumulusSampleDensity(vec4 cloudPos, OgxCumulusMedia media, bool sampleDetail, float coverage,
    sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise, float baseScale, float coverageOffset,
    float detailScale, float detailStrength)
{
    vec4 baseSample = textureLod(baseNoise, cloudPos.xyz * baseScale + media.wind * 10.0, 0.0); // 按云坐标与风偏移读基础噪声。
    float baseDensity = baseSample.y * 0.4 + baseSample.z * 0.4 + baseSample.w * 0.2; // 三个通道加权得到形状。
    baseDensity = ogxRemapSaturate(baseSample.x, baseDensity - 1.0, 1.0); // 用第一通道做概率重映射，得到云块。
    float shapeCurve = ogxCloudTopCurve(ogxSaturate(1.0 - cloudPos.w)) * 0.5; // 上半段的收口曲线。
    shapeCurve += ogxCumulusCurve(ogxSaturate(1.15 - cloudPos.w * 1.43)) * 0.5; // 下半段的收口曲线。
    baseDensity *= shapeCurve; // 竖直方向收口，云像是浮在中间。
    baseDensity *= ogxFastSqrt(ogxSaturate(cloudPos.w * 2.5)) * 0.2 + 0.8; // 下半段略压扁。
    baseDensity *= mix(1.0, ogxCloudTopCurve(ogxSaturate(cloudPos.w * 3.0)), media.wetness); // 雨天让云更集中在顶部。
    float coverageNoise = textureLod(baseNoise, cloudPos.xyz * vec3(8.5e-5, -1e-5, 8.5e-5) + media.wind + coverageOffset, 0.0).x; // 极低频云量噪声。
    coverage = ogxRemapSaturate(1.0 - coverageNoise, coverage * 0.2, coverage); // 把云量映射成密度下限。
    baseDensity = ogxRemapSaturate(baseDensity, coverage, 1.0); // 低于下限的部分去掉。
    baseDensity *= ogxCumulusCurve(ogxSaturate(cloudPos.w * 1.8 - 0.8)) * 2.0 + 1.0; // 中段加厚。
    baseDensity *= ogxCloudTopCurve(ogxSaturate(cloudPos.w * 1.8)); // 顶部收口。
    baseDensity = ogxSaturate(baseDensity); // 收敛到零到一。
    float detailedDensity = 0.0; // 详细密度，下面按是否需要细节赋值。
    if (baseDensity > 1e-6 && sampleDetail) // 只有基础密度确实存在才叠细节。
    {
        float curl = textureLod(curlNoise, cloudPos.xy * 0.0001, 0.0).w; // 读噪声第四通道。
        cloudPos.xy += curl * (100.0 - cloudPos.w * 100.0); // 越靠云底扭曲越大。
        vec3 detailedNoise = textureLod(detailNoise, cloudPos.xyz * detailScale + media.wind * 140.0, 0.0).xyz; // 读三十二立方细节噪声。
        detailedDensity = 1.0 - detailedNoise.x * 0.625 - detailedNoise.y * 0.25 - detailedNoise.z * 0.125; // 三通道按权重合成侵蚀量。
        detailedDensity *= (0.21 - media.wetness * 0.11) * detailStrength; // 强度与天气权重可调。
        detailedDensity = ogxRemapSaturate(baseDensity, detailedDensity, 1.0); // 用基础密度限制侵蚀范围。
    }
    else // 不需要细节时直接用基础密度。
    {
        detailedDensity = baseDensity; // 保持连续。
    }
    return vec2(baseDensity, detailedDensity); // 返回两份密度。
}

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱，云采样点离柱越近越亮。
vec3 ogxCumulusLightning(vec3 relativePos, OgxCumulusMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return vec3(0.0); // 没有闪电事件时不加。
    vec3 boltPos = vec3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
    float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return vec3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}

// 云的光照：沿光方向在云里步进估遮挡，再算直射与环境的合成颜色。
// 五步、步长乘一点五：近处密、远处疏，既能看到体积感又不至于每像素几十次采样。
vec3 ogxCumulusLighting(vec3 marchingPos, OgxCumulusMedia media, vec2 cloudDensity, vec4 cloudPos, float noise,
    float vdotl, float coverage, vec3 worldLight, sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise,
    float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    float stepLength = 28.0; // 光照步进起始步长。
    float lightingDensity = 0.0; // 沿光方向累积的云密度。
    for (int i = 0; i < 5; i++, stepLength *= 1.5) // 五步，步长逐步放大。
    {
        vec4 checkPos = ogxCumulusSetPos(marchingPos + worldLight * stepLength * noise, media); // 取样点。
        lightingDensity += ogxCumulusSampleDensity(checkPos, media, i < 3, coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength).y * stepLength; // 前三步带细节，后两步省掉。
        marchingPos += worldLight * stepLength; // 沿光方向推进。
    }
    float hg = ogxHenyeyGreenstein(vdotl, 0.7); // 前向相位，决定银边。
    float direct = exp2(-lightingDensity * (cloudPos.w * 0.15 + 0.05)) * (hg + 0.02) * (1.0 - media.wetness * 0.8); // 透过率乘前向相位。
    direct += (1.0 / (lightingDensity * 0.2 + 1.0)) * (ogxHenyeyGreenstein(vdotl, 0.2) + 0.1); // 叠一个更宽的环境项。
    direct *= hg * 2.0 + 1.0; // 银边再加强一次。
    direct *= mix(media.bottom_brightness, 0.005 + pow(cloudDensity.y, media.outscatter_factor), ogxCumulusCurve(ogxSaturate(cloudPos.w * 3.333 - 0.333))); // 云底亮度与外散射按高度混合。
    direct *= pow(max(cloudPos.w, 0.05), 0.75); // 云顶更亮。
    vec3 cloudColor = media.light_color * (direct * media.lighting_strength.x * 36.0); // 乘直射光色与强度。
    float ambient = 1.0 - cloudDensity.x; // 云越薄环境光透得越多。
    ambient *= ogxFastSqrt(cloudPos.w); // 高处环境光更多。
    cloudColor += media.sky_color * (ambient * media.lighting_strength.y * 0.35); // 乘天光色与强度。
    cloudColor += ogxCumulusLightning(marchingPos - media.camera_position, media, 400.0, -10.0); // 叠上闪电照亮的部分。
    return cloudColor; // 返回云的颜色。
}

// 体积云步进核心：沿视线在云层里步进，返回云的加色项与透过率；平均命中位置通过 `hitOffset` 交回。
// 为什么把空气透视留给调用方：天空散射函数属于大气效果，通用库只负责云本身的密度与光照。
vec4 ogxCumulusMarch(vec3 worldDir, OgxCumulusMedia media, vec2 noise, out vec3 hitOffset,
    sampler3D baseNoise, sampler3D detailNoise, sampler2D curlNoise, float cloudSamples, float cloudQuality,
    vec3 worldLight, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    vec3 rayStart = vec3(0.0, media.planet_radius + media.camera_position.y, 0.0); // 相机在行星球上的位置。
    vec2 bottom = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.x); // 与云层底的交点。
    vec2 top = ogxRaySphereIntersection(rayStart, worldDir, media.planet_radius + media.altitude.y); // 与云层顶的交点。
    vec2 marching = media.camera_position.y > media.altitude.y ? vec2(top.x, bottom.x) : vec2(bottom.y, top.y); // 相机在云上还是云下决定进出顺序。
    vec3 marchingStart = marching.x * worldDir; // 步进起点相对相机。
    vec3 marchingEnd = marching.y * worldDir; // 步进终点相对相机。
    float inCloud = (1.0 - ogxSaturate((media.camera_position.y - media.altitude.y) * 0.005)) *
        (1.0 - ogxSaturate((media.altitude.x - media.camera_position.y) * 0.005)); // 相机低于云顶、高于云底的权重。
    float inner = bottom.y >= 0.0 && media.camera_position.y > media.altitude.x ? bottom.x : top.y; // 云内起点距离。
    inner = min(inner, 5000.0); // 限长避免步进过远。
    marchingStart = marchingStart * (1.0 - inCloud) + media.camera_position; // 相机在云内时起点改到相机。
    marchingEnd = mix(marchingEnd, inner * worldDir, inCloud) + media.camera_position; // 相机在云内时终点改到云内一点。
    float steps = cloudSamples - ogxSaturate(ogxFastSqrt(abs(worldDir.y)) * 1.4 - 0.4) * 8.0; // 采样数上限，越朝上步数越少。
    steps = max(floor(steps * cloudQuality), 1.0); // 乘精细度倍率，并保证至少一步。
    float stepSize = 1.0 / steps; // 归一化步长。
    vec3 increment = (marchingEnd - marchingStart) * stepSize; // 每步位移。
    vec3 marchingPos = marchingStart + increment * noise.x; // 起点加抖动量，减少条带。
    float densityMul = media.density_option * (media.altitude.y - media.altitude.x) * stepSize; // 乘层厚与归一化步长得消光系数。
    float vdotl = dot(worldDir, worldLight); // 视线与光方向的夹角余弦。
    vec3 accum = vec3(0.0); // 累积的云颜色。
    float transmittance = 1.0; // 初始完全透明。
    vec3 rayHit = vec3(0.0); // 用于估平均命中位置的加权和。
    float sumTransmit = 0.0; // 透过率权重和。
    for (int i = 0; i < int(steps); i++, marchingPos += increment) // 逐步推进。
    {
        vec4 cloudPos = ogxCumulusSetPos(marchingPos, media); // 当前云坐标。
        vec2 cloudDensity = ogxCumulusSampleDensity(cloudPos, media, true, media.coverage, baseNoise, detailNoise, curlNoise,
            baseScale, coverageOffset, detailScale, detailStrength); // 采样密度，用本层云量。
        if (cloudDensity.y < 1e-6) continue; // 这一步没有云就跳过。
        vec3 cloudColor = ogxCumulusLighting(marchingPos, media, cloudDensity, cloudPos, noise.y, vdotl, media.coverage, worldLight,
            baseNoise, detailNoise, curlNoise, baseScale, coverageOffset, detailScale, detailStrength); // 这一段云的光照。
        float absorption = exp2(-cloudDensity.y * densityMul); // 这一段的透过率。
        accum += cloudColor * (transmittance - absorption * transmittance); // 把这一段发出并被后面吸收的部分加进来。
        rayHit += marchingPos * transmittance; // 记录命中位置。
        sumTransmit += transmittance; // 记录权重。
        transmittance *= absorption; // 更新透过率。
        if (transmittance < 0.0001) break; // 几乎不透明就不再采样。
    }
    hitOffset = rayHit / sumTransmit - media.camera_position; // 平均命中位置换成相机相对方向。
    return vec4(accum, transmittance); // 返回加色与透过率。
}

// 云影贴图：从地表坐标沿光方向投到云层，取两处云密度合成阴影值。
float ogxCumulusShadowTex(vec2 coord, OgxCumulusMedia media, vec3 worldLight, float range, sampler3D baseNoise,
    sampler2D curlNoise, float baseScale, float coverageOffset, float detailScale, float detailStrength)
{
    coord = coord * range - (range * 0.5); // 贴图坐标换回相对相机的地表坐标。
    vec4 checkPos = vec4(coord.x + media.camera_position.x, 0.0, coord.y + media.camera_position.z, 0.0); // 取样点世界坐标。
    float thickness = media.altitude.y - media.altitude.x; // 云层厚度。
    checkPos += vec4(worldLight * ((media.altitude.x + thickness * 0.25) / worldLight.y), 0.25); // 投到云层下四分之一处。
    float cloudDensity = ogxCumulusSampleDensity(checkPos, media, false, media.coverage, baseNoise, baseNoise, curlNoise,
        baseScale, coverageOffset, detailScale, detailStrength).y; // 取那一处云密度。
    checkPos += vec4(worldLight * ((thickness * 0.25) / worldLight.y), 0.25); // 再往上一段。
    cloudDensity = max(cloudDensity, ogxCumulusSampleDensity(checkPos, media, false, media.coverage, baseNoise, baseNoise, curlNoise,
        baseScale, coverageOffset, detailScale, detailStrength).y); // 两块取较厚的那块。
    return exp2(-cloudDensity * 20.0); // 密度换成透过率。
}

#endif
