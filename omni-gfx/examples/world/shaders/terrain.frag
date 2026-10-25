#version 330 core
// 地形片元阶段：按材质做微表面法线、粗糙度高光、叶片透光，再叠级联软阴影、云影、
// 天空环境光、空气透视与低空雾。
// 调用位置：测试世界的地形绘制，顶点数据由 Python 侧按高度图与植被生成。
// 设计原因与取舍：
//   测试世界没有贴图，纯色方块会显得像塑料。这里用世界坐标上的多尺度噪声扰动法线、
//   调制底色，并给不同材质不同粗糙度与高光，眼睛会把细碎的明暗当成表面纹理。
//   叶片和草叶额外加一层逆光透光，太阳在背后时树冠会亮起来，这是“植被”与“塑料片”的分界。
//   阴影用三级级联覆盖近景到整岛，PCSS 先找遮挡物平均深度再决定半影宽度。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界空间法线。
in vec3 vColor; // 方块面颜色。
in float vOcclusion; // 预计算的环境光遮蔽。
in float vMaterial; // 材质编号。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform mat4 uShadowMatrix0; // 第一级（最近）光源视图投影。
uniform mat4 uShadowMatrix1; // 第二级。
uniform mat4 uShadowMatrix2; // 第三级（最远）。
uniform sampler2D uShadowMap0; // 第一级深度图。
uniform sampler2D uShadowMap1; // 第二级深度图。
uniform sampler2D uShadowMap2; // 第三级深度图。
uniform vec3 uCascadeSplits; // 三级的分界距离，米。
uniform float uCascadeBlend; // 交界过渡宽度，米。
uniform samplerCube uSkyCube; // 天空立方体贴图，用来取环境光。
uniform float uWaterLevel; // 海平面高度，用来把近水沙地压暗并加湿。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uFrame; // 帧号，给阴影与雾抖动换相位。
uniform float uCloudCover; // 云量。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。
uniform float uWetness; // 近水湿润程度，零到一，越大反光越强。

layout(location = 0) out vec4 fragColor; // 线性高动态范围颜色。
layout(location = 1) out vec4 fragNormal; // 编码法线与线性深度。

// 一级阴影：把世界点换到该级的阴影图坐标，再做 PCSS 软阴影。
// 采样器不能放进三元表达式，所以每级单独一个分支，只把参数交给同一段计算。
float pcssFor(sampler2D map, mat4 matrix, vec3 worldPosition, vec3 normal)
{
    float texel = 1.0 / 1024.0; // 三级阴影图都是 1024 见方。
    vec4 lightPosition = matrix * vec4(worldPosition + normal * 0.3, 1.0); // 沿法线抬起一点，避免自遮挡。
    vec3 coordinate = lightPosition.xyz / lightPosition.w * 0.5 + 0.5; // 换到零到一的贴图坐标。
    if (coordinate.x < 0.0 || coordinate.x > 1.0 || coordinate.y < 0.0 || coordinate.y > 1.0) // 超出该级范围。
    {
        return 1.0; // 范围外算受光，下一级会接手。
    }
    if (coordinate.z < 0.0 || coordinate.z > 1.0) // 超出深度范围。
    {
        return 1.0;
    }
    float bias = 0.0012 + 0.0026 * (1.0 - max(dot(normal, normalize(uSunDirection)), 0.0)); // 掠射时偏置更大。
    float dither = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37)); // 每个像素的旋转角不同，噪点随后被时间抗锯齿抹平。
    return ogxPcssVisibility(map, coordinate, texel, 14.0, 22.0, bias, 8, 12, dither); // 遮挡物搜索加百分比过滤。
}

// 级联阴影：按视深度选级，靠近分界时两级混合，避免硬边。
float shadowMapVisibility(vec3 worldPosition, vec3 normal, float viewDepth)
{
    OgxCascadeSelect cascade = ogxSelectCascade(viewDepth, uCascadeSplits, uCascadeBlend); // 选级联。
    float primary; // 当前级的可见度。
    if (cascade.index == 0) // 最近一级。
    {
        primary = pcssFor(uShadowMap0, uShadowMatrix0, worldPosition, normal);
    }
    else if (cascade.index == 1) // 中间一级。
    {
        primary = pcssFor(uShadowMap1, uShadowMatrix1, worldPosition, normal);
    }
    else // 最远一级。
    {
        primary = pcssFor(uShadowMap2, uShadowMatrix2, worldPosition, normal);
    }
    if (cascade.weight <= 0.001) // 不需要过渡时直接返回，省掉第二级采样。
    {
        return primary;
    }
    float secondary; // 下一级的可见度。
    if (cascade.next == 1) // 从第一级过渡到第二级。
    {
        secondary = pcssFor(uShadowMap1, uShadowMatrix1, worldPosition, normal);
    }
    else // 从第二级过渡到第三级。
    {
        secondary = pcssFor(uShadowMap2, uShadowMatrix2, worldPosition, normal);
    }
    return mix(primary, secondary, cascade.weight); // 按过渡权重混合。
}

// 材质粗糙度：石头与湿沙反光集中，草地与泥土几乎只剩漫反射。
float materialRoughness(int material)
{
    if (material == 2) // 石头。
    {
        return 0.58;
    }
    if (material == 5) // 树干。
    {
        return 0.66;
    }
    if (material == 4) // 树叶。
    {
        return 0.74;
    }
    if (material == 3) // 沙子。
    {
        return 0.72;
    }
    if (material == 0) // 草地。
    {
        return 0.86;
    }
    return 0.80; // 泥土、草叶与花。
}

// 表面细节：在面所在的平面上取三层噪声，得到高度扰动与底色扰动。
// 为什么按面选平面：方块有六个朝向，同一套世界坐标噪声在不同面上会被拉伸，
// 换成“面内坐标”后，细节密度在顶面与侧墙上一致。
vec3 surfaceDetail(vec3 position, vec3 normal, int material, float distanceToCamera, out float albedoScale)
{
    vec2 plane; // 面内坐标。
    if (abs(normal.y) > 0.5) // 顶面与底面用横向坐标。
    {
        plane = position.xz;
    }
    else if (abs(normal.x) > 0.5) // 东西朝向的墙用纵向与横向。
    {
        plane = vec2(position.z, position.y);
    }
    else // 南北朝向的墙。
    {
        plane = vec2(position.x, position.y);
    }
    float coarse = ogxValueNoise2(plane * 0.37 + vec2(3.1, 7.7)); // 两三米尺度的色块。
    float medium = ogxValueNoise2(plane * 2.9); // 三十厘米尺度的起伏。
    float fine = ogxValueNoise2(plane * 11.0); // 十厘米尺度的颗粒。
    // 十厘米级颗粒在几十米外只有不到一个像素，直接采样会变成闪动的白点；
    // 按距离淡出细节，远处交给顶点颜色与阴影，这也是抗锯齿之外避免噪点的一条。
    float detailFade = 1.0 - smoothstep(12.0, 65.0, distanceToCamera); // 距离淡出。
    albedoScale = 1.0 + (coarse - 0.5) * 0.34 + ((medium - 0.5) * 0.16 + (fine - 0.5) * 0.10) * detailFade; // 三个尺度叠成底色扰动。
    float strength = 0.020; // 扰动强度，米。
    if (material == 2 || material == 5) // 石头与树皮更粗糙。
    {
        strength = 0.038;
    }
    else if (material == 3 || material == 0) // 沙地与草地更平。
    {
        strength = 0.014;
    }
    float e = 0.06; // 差分步长，米。
    float h0 = medium * 0.7 + fine * 0.3; // 当前点高度。
    float dx = (ogxValueNoise2((plane + vec2(e, 0.0)) * 2.9) * 0.7 + ogxValueNoise2((plane + vec2(e, 0.0)) * 11.0) * 0.3) - h0; // 横向差分。
    float dy = (ogxValueNoise2((plane + vec2(0.0, e)) * 2.9) * 0.7 + ogxValueNoise2((plane + vec2(0.0, e)) * 11.0) * 0.3) - h0; // 纵向差分。
    strength *= detailFade; // 远处不做微表面起伏，避免亚像素噪声。
    vec3 tangent; // 面内横轴。
    vec3 bitangent; // 面内纵轴。
    if (abs(normal.y) > 0.5) // 顶面。
    {
        tangent = vec3(1.0, 0.0, 0.0);
        bitangent = vec3(0.0, 0.0, 1.0);
    }
    else if (abs(normal.x) > 0.5) // 东西墙：横轴是 Z，纵轴是 Y。
    {
        tangent = vec3(0.0, 0.0, 1.0);
        bitangent = vec3(0.0, 1.0, 0.0);
    }
    else // 南北墙：横轴是 X，纵轴是 Y。
    {
        tangent = vec3(1.0, 0.0, 0.0);
        bitangent = vec3(0.0, 1.0, 0.0);
    }
    vec3 perturbed = normal + tangent * (-dx / e * strength * 12.0) + bitangent * (-dy / e * strength * 12.0); // 高度梯度转成法线倾斜。
    return normalize(perturbed); // 归一回单位长度。
}

// 天空环境光：按表面朝向从天空立方体贴图取色，朝上的面偏天顶蓝，竖直面偏地平线白。
vec3 skyAmbient(vec3 normal, float occlusion)
{
    vec3 direct = textureLod(uSkyCube, normal, 3.5).rgb; // 该朝向的天空颜色，取较模糊层级。
    vec3 zenith = textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 3.5).rgb; // 天顶颜色。
    vec3 color = mix(direct, zenith, 0.22); // 稍微偏向天顶，环境光不会太花。
    return color * mix(0.42, 1.0, occlusion) * uSkyStrength; // 遮蔽越强，天光进来得越少。
}

void main()
{
    int material = int(vMaterial + 0.5); // 顶点传来的材质编号。
    vec3 geometric = normalize(vNormal); // 方块面法线。
    vec3 toCameraEarly = uCameraPos - vWorldPosition; // 相机到地形，细节强度要按距离淡出。
    float distanceEarly = length(toCameraEarly); // 到相机的距离。
    float albedoScale; // 细节噪声给出的底色扰动。
    vec3 normal = surfaceDetail(vWorldPosition, geometric, material, distanceEarly, albedoScale); // 微表面法线。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    vec3 toCamera = uCameraPos - vWorldPosition; // 相机到地形。
    float distanceToCamera = length(toCamera); // 到相机的距离，米。
    vec3 viewDirection = normalize(toCamera); // 从表面指向相机。
    float shadow = shadowMapVisibility(vWorldPosition, geometric, distanceToCamera); // 级联软阴影用几何法线，细节法线不参与。
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    float cloudShadow = ogxCloudShadow(layer, vWorldPosition * 0.001, sunDirection); // 云影，保留整体的明暗块。
    float sunAmount = max(dot(normal, sunDirection), 0.0); // 细节法线参与直射，表面因此有起伏感。
    float geometricAmount = max(dot(geometric, sunDirection), 0.0); // 几何法线的直射，用来判断背光。
    vec3 albedo = vColor * albedoScale; // 底色乘细节扰动。
    float nearWater = smoothstep(2.5, 0.0, vWorldPosition.y - uWaterLevel); // 离水面越近越湿。
    bool underwater = vWorldPosition.y < uWaterLevel - 0.05; // 水面以下的方块会被水吸收，颜色必须提前压掉。
    if (underwater) // 水下地面：压暗并偏青，避免浅滩出现一块块发白的沙地。
    {
        albedo *= vec3(0.34, 0.52, 0.55);
    }
    if (material == 3) // 湿润的沙滩颜色更深、反光更集中。
    {
        albedo *= mix(1.0, 0.72, nearWater * uWetness);
    }
    float roughness = materialRoughness(material); // 材质粗糙度。
    if (material == 3) // 湿沙表面更光滑。
    {
        roughness = mix(roughness, 0.30, nearWater * uWetness);
    }
    float specular = ogxSpecularGGX(normal, viewDirection, sunDirection, roughness, 0.035); // 太阳的微表面高光。
    specular *= sunAmount > 0.0 ? 1.0 : 0.0; // 背光面没有高光。
    vec3 sun = sunColor * (uSunStrength * sunAmount * shadow * cloudShadow); // 太阳直射。
    sun += sunColor * (uSunStrength * specular * shadow * cloudShadow * 0.9); // 叠上高光。
    // 叶片与草叶的透光：太阳从背后照过来时，薄片会把光透过去，边缘发亮。
    if (material == 4 || material == 6 || material == 7)
    {
        float through = max(dot(-geometric, sunDirection), 0.0); // 逆光程度。
        vec3 leafTint = vec3(0.42, 0.62, 0.20); // 透出来的光偏黄绿。
        sun += sunColor * (uSunStrength * (through * 0.85 + 0.10) * shadow * cloudShadow) * leafTint * 0.55; // 透射项。
    }
    float occlusion = clamp(vOcclusion, 0.35, 1.0); // 逐角遮蔽，留一点下限避免死黑。
    vec3 ambient = skyAmbient(normal, occlusion) * vec3(0.85, 0.92, 1.05); // 天光，略微偏冷。
    if (material == 4) // 树冠内部几乎见不到天空，环境光按六成算，叶团才有体积。
    {
        ambient *= 0.62;
    }
    // 地面反弹光：朝下的面接收草地与沙地的暖色反射，阴影里不会发蓝发脏。
    float downward = max(-normal.y, 0.0);
    vec3 bounce = vec3(0.30, 0.26, 0.18) * downward * (0.35 + 0.65 * occlusion) * uSkyStrength * 0.55;
    // 背光补光：模拟天空与海面在大气里的多次散射，侧墙不会黑成一条。
    float fill = max(dot(normal, normalize(vec3(-sunDirection.x, 0.30, -sunDirection.z))), 0.0);
    vec3 fillLight = sunColor * (fill * uSunStrength * 0.16 * shadow); // 补光也受阴影约束，避免漏光。
    vec3 color = albedo * (sun + ambient * occlusion + bounce + fillLight); // 合成光照。
    // 草叶与树叶在背光时仍保留一点自身色，否则逆光会变成黑剪影。
    if (material == 4 || material == 6)
    {
        color += albedo * vec3(0.10, 0.14, 0.06) * (1.0 - geometricAmount) * uSkyStrength; // 自身透出的微光。
    }
    color *= 1.0 - 0.10 * smoothstep(0.75, 1.0, 1.0 - geometricAmount); // 掠射角轻微压暗，边缘不发亮。
    vec3 viewToSurface = normalize(vWorldPosition - uCameraPos); // 从相机指向地形。
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewToSurface, distanceToCamera * 0.001, sunDirection, 3, transmittance); // 远景空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动，避免静态噪点。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection,
                           sunColor * 2.0, jitter, 3); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写入场景颜色。
    float linearDepth = distanceToCamera; // 米制距离，供遮蔽与反射判断邻域。
    fragNormal = vec4(ogxEncodeNormal(geometric), clamp(linearDepth / 1000.0, 0.0, 1.0), 1.0); // 法线压到零到一，距离缩小存进蓝通道。
}
