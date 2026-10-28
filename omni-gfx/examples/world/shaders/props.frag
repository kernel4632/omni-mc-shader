#version 330 core
// 树干、树枝与岩石的片元阶段：树皮沿 UV 采样，岩石按世界坐标三平面采样，
// 再叠级联 PCSS 软阴影、天空环境光、空气透视与低空雾。
// 调用位置：测试世界主场景绘制；阴影阶段只画深度，不进入这里。
// 设计原因与取舍：
//   树皮有明确的纵向纹理，必须用圆管的环向与纵向 UV；
//   岩石表面没有固定方向，用世界坐标里最接近法线的平面投影，避免接缝与拉伸。
//   两种材质都有颜色、法线与粗糙度贴图，高光由粗糙度决定，不会出现一层塑料亮膜。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界法线。
in vec2 vUv; // 树皮 UV。
in vec3 vColor; // 逐顶点色调。
in float vMaterial; // 材质编号。
in float vSway; // 风摆权重。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。
uniform float uTime; // 场景时间。
uniform float uFrame; // 帧号。
uniform float uCloudCover; // 云量。
uniform float uWaterLevel; // 水面高度，反射阶段用来丢弃水下片段。
uniform int uReflectionPass; // 一表示正在渲染平面反射。
uniform sampler2DArray uAlbedo; // 六层颜色。
uniform sampler2DArray uNormal; // 六层法线。
uniform sampler2DArray uRough; // 六层粗糙度。
uniform samplerCube uSkyCube; // 天空环境光。
#include "shadow_sample.glsl"

out vec4 fragColor; // 线性颜色。

// 岩石的三平面取样：选择法线绝对值最大的轴，UV 由另外两个世界轴组成。
vec2 rockUv(vec3 position, vec3 normal)
{
    vec3 amount = abs(normal); // 三个轴上法线的绝对分量。
    if (amount.y >= amount.x && amount.y >= amount.z) // 法线最接近竖直。
    {
        return position.xz / 2.1; // 朝上或朝下。
    }
    if (amount.x >= amount.z) // 法线更接近东西向。
    {
        return position.zy / 2.1; // 东西向。
    }
    return position.xy / 2.1; // 南北向。
}

void main()
{
    if (uReflectionPass == 1 && vWorldPosition.y < uWaterLevel + 0.02) // 水下树干与岩石不进反射。
    {
        discard;
    }
    vec3 geometric = normalize(vNormal); // 几何法线。
    int material = int(vMaterial + 0.5); // 四舍五入到材质编号。
    vec2 uv = vUv; // 默认使用圆管 UV。
    int layer = 5; // 默认树皮。
    float uvScale = 1.0; // 树皮不需要额外缩放。
    if (material == 2) // 岩石用世界投影，不读圆管 UV。
    {
        uv = rockUv(vWorldPosition, geometric); // 三平面取样。
        layer = 2; // 纹理数组里的岩石层。
    }
    vec3 albedo = texture(uAlbedo, vec3(uv * uvScale, float(layer))).rgb * vColor; // 贴图色乘顶点色调。
    vec3 normalSample = texture(uNormal, vec3(uv * uvScale, float(layer))).xyz * 2.0 - 1.0; // 切线法线还原。
    float roughness = texture(uRough, vec3(uv * uvScale, float(layer))).r; // 粗糙度只取红通道。
    // 用屏幕导数构造切线基：树皮圆管与岩石面都能用，不必额外存切线。
    vec3 tangent = normalize(dFdx(vWorldPosition) + vec3(1e-5, 0.0, 0.0)); // 屏幕横向导数。
    vec3 bitangent = normalize(dFdy(vWorldPosition) + vec3(0.0, 0.0, 1e-5)); // 屏幕纵向导数。
    vec3 normal = normalize(geometric + tangent * normalSample.x * 0.85 + bitangent * normalSample.y * 0.85); // 叠上法线细节。
    if (material == 2) // 岩石凹陷处再压暗一点，贴图的明暗才有体积。
    {
        albedo *= 0.82 + 0.28 * (normalSample.z * 0.5 + 0.5);
    }

    vec3 toCamera = uCameraPos - vWorldPosition; // 表面指向相机。
    float distanceToCamera = length(toCamera); // 距离用于阴影与雾。
    vec3 viewDirection = normalize(toCamera); // 单位视线方向。
    vec3 sunDirection = normalize(uSunDirection); // 单位太阳方向。
    float shadow = shadowVisibility(vWorldPosition, geometric, distanceToCamera, 0.08, 12.0); // 树干与岩石一律查阴影。
    float cloudShadow = 1.0; // HDR 天空的云不参与动态云影。
    float sunAmount = max(dot(normal, sunDirection), 0.0); // 兰伯特入射角。
    float specular = ogxSpecularGGX(normal, viewDirection, sunDirection, clamp(roughness, 0.08, 0.98), 0.04); // 树皮与岩石的弱高光。
    specular *= smoothstep(0.0, 0.10, sunAmount); // 背光面没有高光。
    vec3 sun = worldSunColor() * (uSunStrength * sunAmount * shadow * cloudShadow); // 直射光。
    sun += worldSunColor() * (uSunStrength * specular * shadow * cloudShadow); // 加高光。
    vec3 zenith = textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 3.0).rgb; // 天顶环境色。
    vec3 sky = mix(textureLod(uSkyCube, normal, 3.0).rgb, zenith, 0.25); // 沿法线取天空再混天顶。
    vec3 ambient = sky * uSkyStrength * (0.48 + 0.52 * geometric.y) * albedo; // 朝上的面接收更多天光。
    // 树下与岩石底部的环境光按风摆权重再压暗，接触处不会浮起来。
    ambient *= mix(0.78, 1.0, clamp(vSway + 0.5, 0.0, 1.0));
    vec3 color = albedo * sun + ambient;

    vec3 viewToSurface = normalize(vWorldPosition - uCameraPos); // 相机指向表面。
    OgxAtmosphere air = worldAtmosphere(); // 共用大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 高度换成公里。
    vec3 transmittance; // 相机到表面的透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewToSurface, distanceToCamera * 0.001, sunDirection, 3, transmittance); // 空气透视。
    color = color * transmittance + haze; // 先乘透过率再加雾色。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 每帧错开雾采样。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection,
                           worldSunColor() * 2.0, jitter, 3); // 低空雾走三步。
    color = ogxFogApply(color, fog); // 叠上雾。
    fragColor = vec4(color, 1.0);
}
