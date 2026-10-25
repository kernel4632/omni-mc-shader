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
    if (uIsTerrain == 1) // 地形：低频干湿斑块与近水湿岸。
    {
        metallic = 0.0; // 地面不是金属。
        float macro = ogxFbm2(vWorldPosition.xz * 0.055 + vec2(5.1, 2.7), 3); // 十几米尺度的干湿斑块。
        float mid = ogxFbm2(vWorldPosition.xz * 0.20 + vec2(11.3, -4.2), 2); // 几米尺度的草色变化。
        float fine = ogxValueNoise2(vWorldPosition.xz * 0.9); // 一米以内的草色颗粒。
        albedo *= (0.62 + macro * 0.76) * (0.86 + mid * 0.28) * (0.94 + fine * 0.12); // 三个尺度叠出草地的不均匀。
        albedo *= vec3(1.02, 0.98 + fine * 0.06, 0.92 + fine * 0.09); // 草叶的暖黄与冷绿差异。
        float dry = smoothstep(0.48, 0.78, ogxValueNoise2(vWorldPosition.xz * 0.045 + vec2(17.0, 3.0))); // 干草斑块。
        albedo *= mix(vec3(1.0), vec3(1.18, 1.00, 0.62), dry * 0.28); // 少量枯黄斑块，草地不再是一条荧光绿也不整片发灰。
        albedo *= vec3(0.55, 1.35, 0.42); // 暖阳下保住草地的绿色，避免整片地面被压成米黄色。
        // 大尺度草色斑块：一百到数百米的变化，远景不会只剩一条条被高度场压出来的色带。
        float broad = ogxFbm2(vWorldPosition.xz * 0.006 + vec2(7.3, 1.9), 3); // 一百七十米尺度。
        float huge = ogxValueNoise2(vWorldPosition.xz * 0.0015 + vec2(2.1, 5.7)); // 六百米尺度。
        albedo *= mix(0.82, 1.14, broad) * mix(0.90, 1.10, huge);
        albedo *= mix(vec3(0.96, 1.08, 0.86), vec3(1.04, 1.00, 0.94), broad); // 冷绿与暖黄草斑。
        float farColor = ogxValueNoise2(vWorldPosition.xz * 0.018 + vec2(6.2, 3.8)); // 五十五米尺度。
        albedo *= mix(0.86, 1.10, farColor); // 远景颜色也有起伏，山脊不会是一条同色的长带。
        // 远景微法线：以五十米为周期的缓坡，打散高度场在远山上留下的水平条纹。
        float farStep = 6.0;
        float farNoise = ogxValueNoise2(vWorldPosition.xz * 0.020 + vec2(3.1, 8.4));
        float farX = ogxValueNoise2((vWorldPosition.xz + vec2(farStep, 0.0)) * 0.020 + vec2(3.1, 8.4));
        float farZ = ogxValueNoise2((vWorldPosition.xz + vec2(0.0, farStep)) * 0.020 + vec2(3.1, 8.4));
        vec3 farBump = vec3((farNoise - farX) / farStep, 0.0, (farNoise - farZ) / farStep) * 1.30;
        normal = normalize(normal + farBump * (1.0 - smoothstep(80.0, 520.0, distance)));
        // 微法线：按程序化草色噪声的梯度扰动法线，地面有细碎的明暗，不像一整块绿塑料。
        float eps = 0.12; // 差分步长，米。
        float height0 = ogxValueNoise2(vWorldPosition.xz * 0.75); // 当前高度。
        float heightX = ogxValueNoise2((vWorldPosition.xz + vec2(eps, 0.0)) * 0.75); // 东侧高度。
        float heightZ = ogxValueNoise2((vWorldPosition.xz + vec2(0.0, eps)) * 0.75); // 南侧高度。
        vec3 bump = vec3((height0 - heightX) / eps, 0.0, (height0 - heightZ) / eps) * 0.10; // 梯度换成微法线。
        normal = normalize(normal + bump * (1.0 - smoothstep(20.0, 120.0, distance))); // 远处淡出，避免闪烁。
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
    vec3 sunChroma = lightingSunChroma(); // 由大气透过率决定的太阳颜色。
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
    float cloudShadow = lightingCloudShadow(vWorldPosition); // 大块云影。
    float cloudWeight = smoothstep(22.0, 70.0, distance) * 0.70; // 近景保持阳光，云影落在中远景，避免整块前景被压黑。
    float visibility = shadow * mix(1.0, cloudShadow, cloudWeight); // 云影压暗地面，但保留太阳方向感。
    float NdotL = max(dot(normal, sunDirection), 0.0); // 太阳入射角。
    float NdotV = max(dot(normal, view), 0.0); // 视线与法线夹角。
    float fresnel = ogxFresnelSchlick(NdotV, 0.04, 1.0); // 电介质菲涅尔，用于漫反射能量守恒。
    vec3 diffuseAlbedo = albedo * (1.0 - metallic); // 金属没有漫反射。
    vec3 specularTint = mix(vec3(1.0), albedo, metallic); // 金属高光带自身颜色。
    float f0 = mix(0.04, max(albedo.r, max(albedo.g, albedo.b)), metallic); // 金属的 F0 接近反照率。
    // 直射漫反射：能量守恒的兰伯特项，再乘太阳辐照度与可见度。
    vec3 diffuse = diffuseAlbedo * (OGX_INV_PI * uSunIrradiance * NdotL * visibility);
    // 直射高光：GGX 微表面，粗糙度决定高光是一条细线还是一片柔亮。
    // 最小粗糙度抬到零点一，避免太阳这种极小光源在低模球面上退化成方块状的单像素亮点。
    float specular = ogxSpecularGGX(normal, view, sunDirection, max(roughness, 0.10), f0); // 标量高光。
    vec3 direct = sunChroma * (diffuse + specularTint * (specular * uSunIrradiance * visibility)); // 直射光颜色。
    // 天空环境光：法线方向取天空贴图，漫反射项乘一减菲涅尔，粗糙表面平均更大一片天空。
    vec3 skyDiffuse = lightingSkyAmbient(normal, roughness) * diffuseAlbedo * (1.0 - fresnel); // 漫反射天光。
    vec3 reflection = reflect(-view, normal); // 反射方向。
    float lod = mix(1.0, 5.5, roughness); // 粗糙表面取更模糊的层级。
    float envFresnel = ogxFresnelSchlick(NdotV, f0, 1.0); // 环境反射的菲涅尔。
    vec3 skySpecular = lightingSampleSky(reflection, lod) * (envFresnel * mix(0.18, 1.0, metallic) * specularTint); // 环境高光；绝缘体很弱，金属明显。
    // 地面反弹：朝下的面接收草地反射的阳光，颜色偏绿；这是屏幕空间反弹之前的基础一层。
    vec3 ground = vec3(0.050, 0.075, 0.030) * sunChroma * (uSunIrradiance * 0.020 * max(-normal.y, 0.0)) * (1.0 - metallic); // 草地反弹。
    vec3 indirect = skyDiffuse + skySpecular + ground; // 间接光。
    // 空气透视：远景融进天空色，地平线不出现硬边；反射通道强度减半，倒影不要被雾洗白。
    float aerialFade = smoothstep(20.0, 500.0, distance) * uAerialStrength; // 近景不受影响。
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
