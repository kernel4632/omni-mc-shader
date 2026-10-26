#version 330 core
// 地表片元阶段：太阳直射与 PCSS 阴影、天空环境光、地面颜色反弹、空气透视。
// 调用位置：主场景与水面平面反射中的地形、球、方块与立石。
// 设计原因与取舍：
//   直射与间接光分开写两张附件：接触阴影和屏幕空间环境光只该压暗其中一路，
//   合成阶段才能做到“影子里的天光还在、接触处更暗”，而不是把整幅画面统一乘一个灰系数。
//   地表只加低频颜色变化，不加扫描贴图；真实感来自光，而不是把塑料感藏进纹理。
#include "common.glsl"
#include "shadow_lighting.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界法线。
in vec3 vAlbedo; // 线性反照率。
in float vRoughness; // 粗糙度。
in float vMetallic; // 金属度。

uniform int uIsTerrain; // 一表示地形，追加草色与湿岸变化。
uniform int uReflectionPass; // 一表示正在渲染平面反射，水下部分要丢掉。
uniform int uDebugMode; // 一表示输出太阳可见度，仅用于开发检查阴影。
uniform float uAerialStrength; // 空气透视强度，反射通道可以调低。

layout(location = 0) out vec4 outDirect; // 太阳直射光，含直射高光。
layout(location = 1) out vec4 outIndirect; // 天空环境光、环境高光与地面反弹。
layout(location = 2) out vec4 outNormalDepth; // 编码法线、到相机距离与不透明标记。
layout(location = 3) out vec4 outAlbedoRough; // 线性反照率与粗糙度，供屏幕空间反弹取样。

void main()
{
    if (uReflectionPass == 1 && vWorldPosition.y < uWaterLevel + 0.02) // 平面反射只保留水面以上的景物。
    {
        discard; // 水下地形不参与倒影。
    }
    vec3 normal = normalize(vNormal); // 几何法线。
    vec3 toCamera = uCameraPosition - vWorldPosition; // 指向相机。
    float distance = length(toCamera); // 到相机距离，米。
    vec3 view = toCamera / max(distance, 1e-4); // 单位视线。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 albedo = vAlbedo; // 基础反照率来自顶点。
    float roughness = clamp(vRoughness, 0.03, 1.0); // 粗糙度。
    float metallic = clamp(vMetallic, 0.0, 1.0); // 金属度。
    if (uIsTerrain == 1) // 地形：颜色变化已经烘进顶点色，这里只处理近水湿岸。
    {
        metallic = 0.0; // 地面不是金属。
        // 大块草色在几何阶段按顶点算好；这里只补一层低频斑块和细颗粒，避免整片草地像一块塑料。
        float spot = ogxFbm2(vWorldPosition.xz * 0.35 + vec2(3.7, 9.1), 2); // 两三米尺度的草色斑块。
        albedo *= 0.88 + spot * 0.24; // 明暗起伏。
        float grain = ogxValueNoise2(vWorldPosition.xz * 2.1); // 二十厘米以内的草叶颗粒。
        albedo *= 0.94 + grain * 0.12; // 很轻的颗粒，远景不会闪。
        // 片元阶段不再重复十几次噪声，
        // 这是本场景最大的一项填充成本，去掉后每一帧能省下几毫秒。
        float wet = 1.0 - smoothstep(uWaterLevel + 0.02, uWaterLevel + 0.9, vWorldPosition.y); // 近水一米内算湿岸。
        albedo *= mix(1.0, 0.62, wet); // 湿岸更深。
        roughness = mix(roughness, 0.28, wet * 0.8); // 湿岸更光滑，能反射天空。
    }
    else // 石块、金属与立方体：加很轻的程序化颗粒，避免整块表面像塑料。
    {
        float grain = ogxValueNoise2(vWorldPosition.xz * 2.3 + vWorldPosition.y * 1.7); // 几厘米到几十厘米的颗粒。
        albedo *= 0.82 + grain * 0.34; // 颜色轻微不均。
        roughness = clamp(roughness * (0.92 + grain * 0.16), 0.03, 1.0); // 粗糙度也有颗粒。
    }
    float dither = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x; // 每像素阴影旋转。
    float shadow = lightingShadow(vWorldPosition, normal, distance, dither); // 级联 PCSS。
    if (uDebugMode == 1) // 开发检查：把太阳可见度直接写成颜色。
    {
        outDirect = vec4(vec3(shadow), 1.0); // 白受光，黑阴影。
        outIndirect = vec4(0.0, 0.0, 0.0, 1.0);
        outNormalDepth = vec4(ogxEncodeNormal(normal), clamp(distance / 1000.0, 0.0, 1.0), 1.0);
        outAlbedoRough = vec4(albedo, roughness);
        return;
    }
    if (uDebugMode == 2) // 开发检查：把线性反照率直接写成颜色。
    {
        outDirect = vec4(albedo, 1.0);
        outIndirect = vec4(0.0, 0.0, 0.0, 1.0);
        outNormalDepth = vec4(ogxEncodeNormal(normal), clamp(distance / 1000.0, 0.0, 1.0), 1.0);
        outAlbedoRough = vec4(albedo, roughness);
        return;
    }
    if (uDebugMode == 4) // 开发检查：单点阴影比较。
    {
        vec3 c = lightingShadowCoord(uShadowMatrix0, vWorldPosition, normal, 0.02); // 第一级坐标。
        float d = texture(uShadowMap0, c.xy).r; // 贴图深度。
        float vis = step(c.z - 0.0002, d); // 单点比较。
        outDirect = vec4(vis, c.z, d, 1.0); // 红可见度，绿接收深度，蓝贴图深度。
        outIndirect = vec4(0.0, 0.0, 0.0, 1.0);
        outNormalDepth = vec4(ogxEncodeNormal(normal), clamp(distance / 1000.0, 0.0, 1.0), 1.0);
        outAlbedoRough = vec4(albedo, roughness);
        return;
    }
    float cloudShadow = lightingCloudShadow(vWorldPosition); // 大块云影，与天上的云来自同一张噪声。
    // 与 iterationT 相同：云影几乎完全生效，只留百分之三的直射让阴影里仍有方向感。
    float visibility = shadow * mix(cloudShadow, 1.0, 0.03); // 太阳可见度。
    float NdotL = max(dot(normal, sunDirection), 0.0); // 太阳入射角。
    float NdotV = max(dot(normal, view), 0.0); // 视线与法线夹角。
    vec3 sunLight = lightingSunLight(); // 完整太阳辐照度，已由大气表算出。
    vec3 sunChroma = sunLight / max(ogxLuminance(sunLight), 1e-6); // 只用于高光染色。
    vec3 diffuseAlbedo = albedo * (1.0 - metallic); // 金属没有漫反射。
    vec3 specularTint = mix(vec3(1.0), albedo, metallic); // 金属高光带自身颜色。
    float f0 = mix(0.04, max(albedo.r, max(albedo.g, albedo.b)), metallic); // 金属的 F0 接近反照率。
    // 直射漫反射：与 iterationT 相同的 Burley 漫反射，再乘太阳辐照度与可见度。
    float diffuse = ogxDiffuseBurley(normal, view, sunDirection, roughness);
    vec3 direct = sunLight * (diffuseAlbedo * (diffuse * visibility));
    // 直射高光：与 iterationT 相同的 GGX，草地压到二十分之一，避免低阳时整片草坡泛白。
    float specular = ogxSpecularGGX(normal, view, sunDirection, clamp(roughness, 0.0015, 0.9), f0);
    float highlight = specular * clamp(4.0 - roughness * 3.5, 0.0, 1.0) * (0.07 - (uIsTerrain == 1 ? 0.035 : 0.0));
    direct += specularTint * (highlight * sunLight * visibility);
    // 天空环境光：iterationT 的 SkyLighting，太阳侧天空辐照度带方向性，再乘反照率。
    vec3 skyDiffuse = lightingSkyAmbient(normal, roughness) * diffuseAlbedo;
    // 环境高光只留给金属与光滑物体；草地和树叶不再有白色轮廓。
    vec3 reflection = reflect(-view, normal); // 反射方向。
    float lod = mix(1.5, 5.0, roughness); // 粗糙表面取更模糊的天空层级。
    float envFresnel = ogxFresnelSchlick(NdotV, f0, 1.0); // 环境反射的菲涅尔。
    vec3 skySpecular = lightingSampleSky(reflection, lod) * (envFresnel * specularTint * mix(0.0, 0.45, step(0.5, metallic)));
    vec3 indirect = skyDiffuse + skySpecular; // 间接光。
    // 空气透视：用同一张大气表算相机到表面的散射与透过率；近景几乎不变化，远景融进天空。
    float aerialFade = smoothstep(20.0, 600.0, distance) * uAerialStrength; // 近景不受影响。
    if (aerialFade > 0.001) // 只有远处才付这段成本。
    {
        vec3 transmittance; // 剩余透过率。
        vec3 haze = lightingAerial(vWorldPosition, -view, distance, transmittance); // 空气散射色。
        direct *= mix(vec3(1.0), transmittance, aerialFade); // 直射光被空气吸收。
        indirect = indirect * mix(vec3(1.0), transmittance, aerialFade) + haze * aerialFade; // 间接光加散射。
    }
    outDirect = vec4(direct, 1.0); // 直射光附件。
    outIndirect = vec4(indirect, 1.0); // 间接光附件。
    if (uDebugMode == 3) // 开发检查：只输出直射光。
    {
        outDirect = vec4(direct, 1.0);
        outIndirect = vec4(0.0, 0.0, 0.0, 1.0);
    }
    if (uDebugMode == 4) // 开发检查：只输出间接光。
    {
        outDirect = vec4(0.0, 0.0, 0.0, 1.0);
        outIndirect = vec4(indirect, 1.0);
    }
    outNormalDepth = vec4(ogxEncodeNormal(normal), clamp(distance / 1000.0, 0.0, 1.0), 1.0); // 法线与距离。
    outAlbedoRough = vec4(albedo, roughness); // 反照率与粗糙度。
    if (uReflectionPass == 1) // 反射目标只有一张颜色附件。
    {
        outDirect = vec4(direct + indirect, 1.0); // 合并后写第一张颜色。
    }
}
