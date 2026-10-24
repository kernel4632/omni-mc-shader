#version 330 core
// 地形片元阶段：三级级联 PCSS 软阴影、云影、天空环境光、空气透视与低空雾。
// 调用位置：测试世界的地形绘制，顶点数据由 Python 侧按高度图生成。
// 设计原因与取舍：阴影用三级级联覆盖近景到整岛，近处那级每米约四十个纹素，
// 墙根与树叶的投影不会糊成一团；级联交界按深度做线性过渡，不会出现一圈明显的密度跳变。
// PCSS 先找遮挡物平均深度再决定半影宽度，阴影边缘因此随距离变软，接近真实方向光。
// 环境光直接取天空立方体贴图的高层多级纹理，省掉每像素重新积分大气。
// 第二张颜色附件写编码法线与线性深度，供遮蔽与反射降噪判断邻域。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界空间法线。
in vec3 vColor; // 方块面颜色。
in float vOcclusion; // 预计算的环境光遮蔽。

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
uniform float uWaterLevel; // 海平面高度，水面以下的地形不画。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uFrame; // 帧号，给雾与阴影抖动换相位。
uniform float uCloudCover; // 云量。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。


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

void main()
{
    if (vWorldPosition.y < uWaterLevel) // 水下部分交给水面上色，避免透出一块没有光照的岛体。
    {
        discard;
    }
    vec3 normal = normalize(vNormal); // 方块面法线。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    vec3 toCamera = uCameraPos - vWorldPosition; // 相机到地形。
    float distanceToCamera = length(toCamera); // 到相机的距离，米。
    float viewDepth = distanceToCamera; // 沿视线方向的深度，级联按它选级。
    float shadow = shadowMapVisibility(vWorldPosition, normal, distanceToCamera); // 级联软阴影。
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    float cloudShadow = ogxCloudShadow(layer, vWorldPosition * 0.001, sunDirection); // 云影，保留整体的明暗块。
    float diffuse = max(dot(normal, sunDirection), 0.0); // 直射余弦。
    vec3 sun = sunColor * (uSunStrength * diffuse * shadow * cloudShadow); // 太阳直射。
    // 天空环境光：天顶偏蓝、地平线偏白，墙面的法线接近水平，颜色因此接近地平线。
    vec3 zenith = textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 4.0).rgb; // 天顶颜色。
    vec3 horizon = textureLod(uSkyCube, normalize(vec3(sunDirection.x, 0.12, sunDirection.z)), 4.0).rgb; // 向阳侧的地平线颜色。
    vec3 ambient = mix(horizon, zenith, normal.y * 0.5 + 0.5) * uSkyStrength; // 按朝向混合的环境光。
    vec3 ground = vec3(0.20, 0.17, 0.13) * max(-normal.y, 0.0) * 0.6; // 地面反弹光，只影响朝下的面。
    float fill = max(dot(normal, normalize(vec3(-sunDirection.x, 0.35, -sunDirection.z))), 0.0); // 背光面的补光方向。
    vec3 fillLight = sunColor * (fill * uSunStrength * 0.28); // 天空与海面的反弹，避免侧墙死黑。
    float grain = 0.90 + 0.20 * ogxValueNoise2(vWorldPosition.xz * 1.1 + vec2(vWorldPosition.y * 0.3)); // 细颗粒打散整片纯色。
    vec3 color = vColor * grain * (sun + ambient + ground + fillLight) * vOcclusion; // 合成光照。
    vec3 viewDirection = normalize(vWorldPosition - uCameraPos); // 从相机指向地形。
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewDirection, distanceToCamera * 0.001, sunDirection, 3, transmittance); // 远景空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动，避免静态噪点。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 3); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写入场景颜色。
    float linearDepth = distanceToCamera; // 米制距离，供遮蔽与反射判断邻域。
    fragNormal = vec4(ogxEncodeNormal(normal), clamp(linearDepth / 1000.0, 0.0, 1.0), 1.0); // 法线压到零到一，距离缩小存进蓝通道。
}
