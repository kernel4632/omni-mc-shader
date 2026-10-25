#version 330 core
// 地形片元阶段：把草甸、泥土、岩石、湿沙与腐殖土五种扫描材质按坡度与湿度混合，
// 再叠三层尺度法线、级联 PCSS 软阴影、天空环境光、空气透视与低空雾。
// 调用位置：测试世界的场景绘制，顶点来自 `terrain.py` 的连续高度场。
// 设计原因与取舍：
//   纯色地形在近景会像塑料板。这里每种材质都有颜色、法线与粗糙度三张图，
//   按坡度、离水距离、林下噪声和脚下小径动态混合，避免一条明显的材质边界。
//   法线只做 XZ 投影：测试世界的地形以草甸和缓坡为主，陡崖交给岩石纹理的宏观起伏；
//   远处按距离淡出微表面，避免亚像素法线在时间抗锯齿里变成闪点。
//   阴影用三级级联 + PCSS：近景草根有接触阴影，远山有整体明暗，树冠投下软边。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 高度场法线。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uFrame; // 帧号，阴影与雾抖动换相位。
uniform float uCloudCover; // 云量。
uniform float uWaterLevel; // 水面高度，米。
uniform sampler2DArray uAlbedo; // 六层颜色，sRGB。
uniform sampler2DArray uNormal; // 六层法线，OpenGL 约定。
uniform sampler2DArray uRough; // 六层粗糙度。
uniform samplerCube uSkyCube; // 天空立方体贴图，提供环境光。
uniform int uReflectionPass; // 一表示正在渲染平面反射，水下片段要丢掉。
#include "shadow_sample.glsl"

layout(location = 0) out vec4 fragColor; // 线性高动态范围颜色。
layout(location = 1) out vec4 fragNormal; // 编码法线与线性深度。

// 小径遮罩：一条从机位前方弯向湖岸的土路，给近景一个自然的引导线。
// 用两条正弦叠加做弯道，宽度加一点低频噪声，边缘不会像尺子画出来的。
float trailMask(vec2 position)
{
    float lengthMask = smoothstep(104.0, 122.0, position.y) * (1.0 - smoothstep(214.0, 236.0, position.y));
    float curve = 5.2 * sin((position.y - 104.0) * 0.045) + 2.4 * sin((position.y - 104.0) * 0.013 + 1.3);
    float halfWidth = 1.5 + 0.8 * ogxValueNoise2(position * 0.12);
    float distance = abs(position.x - curve);
    return lengthMask * (1.0 - smoothstep(halfWidth, halfWidth + 2.2, distance));
}

// 材质权重：坡度越高岩石越多，贴近水面是湿沙，林下噪声给腐殖土，小径盖在草地上。
// 返回五层权重；纹理数组层号固定为草、土、石、沙、林、树皮，最后一层地形不用。
vec4 materialWeights(vec3 position, vec3 normal, float distanceToCamera)
{
    float slope = 1.0 - clamp(normal.y, 0.0, 1.0); // 零是平地，一是直壁。
    float height = position.y;
    float lake = length(vec2((position.x - 0.0) / 112.0, (position.z + 30.0) / 148.0)); // 湖盆归一距离。
    float shore = 1.0 - smoothstep(0.94, 1.16, lake); // 一在水边，零在内陆。
    float rock = smoothstep(0.16, 0.46, slope); // 陡坡露出岩石。
    rock += smoothstep(105.0, 220.0, height) * 0.55; // 高山裸岩，低处仍是草甸。
    rock = clamp(rock, 0.0, 1.0);
    float sand = smoothstep(0.98, 1.10, lake) * (1.0 - smoothstep(1.18, 1.34, lake)); // 水线附近的沙。
    sand *= (1.0 - smoothstep(2.5, 5.5, height)) * (1.0 - smoothstep(0.20, 0.42, slope));
    float forest = smoothstep(0.62, 0.76, ogxFbm2(position.xz * 0.016 + 4.7, 3)); // 林下腐殖土斑块。
    forest *= (1.0 - rock) * (1.0 - sand) * 0.75;
    float barePatch = smoothstep(0.58, 0.78, ogxFbm2(position.xz * 0.055 + 7.3, 3)) * (1.0 - rock) * (1.0 - sand);
    float trail = trailMask(position.xz) * (1.0 - rock);
    float grass = 1.0;
    grass *= 1.0 - rock;
    grass *= 1.0 - sand;
    grass *= 1.0 - forest * 0.72;
    grass *= 1.0 - trail * 0.88;
    grass *= 1.0 - barePatch * 0.18;
    float dirt = clamp(forest * 0.30 + trail * 0.95 + barePatch * 0.20, 0.0, 1.0);
    dirt *= (1.0 - rock) * (1.0 - sand);
    // 远处用同样的权重会因贴图缩小产生色斑；按距离轻微向草色收拢，保持整体色块。
    float distant = smoothstep(180.0, 900.0, distanceToCamera);
    grass += distant * (1.0 - grass) * 0.35;
    return vec4(grass, dirt, rock, sand); // 第五层从草与土的混合里再分，见下。
}

// 采样一层颜色、法线与粗糙度：UV 与尺度由调用方给，层号直接进纹理数组。
vec3 sampleAlbedo(vec2 uv, int layer)
{
    return texture(uAlbedo, vec3(uv, float(layer))).rgb;
}

float sampleRoughness(vec2 uv, int layer)
{
    return texture(uRough, vec3(uv, float(layer))).r;
}

vec3 sampleNormal(vec2 uv, int layer)
{
    return texture(uNormal, vec3(uv, float(layer))).xyz * 2.0 - 1.0;
}

// 天空环境光：沿法线取天空立方体贴图，朝上的面偏天顶，朝下的面偏地面反弹。
vec3 skyAmbient(vec3 normal, float occlusion)
{
    vec3 direct = textureLod(uSkyCube, normal, 3.0).rgb;
    vec3 zenith = textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 3.0).rgb;
    vec3 color = mix(direct, zenith, 0.28);
    return color * mix(0.52, 1.0, occlusion) * uSkyStrength;
}

void main()
{
    if (uReflectionPass == 1 && vWorldPosition.y < uWaterLevel + 0.02) // 平面反射只保留水面以上的景物。
    {
        discard;
    }
    vec3 geometric = normalize(vNormal);
    vec3 toCamera = uCameraPos - vWorldPosition;
    float distanceToCamera = length(toCamera);
    vec3 viewDirection = normalize(toCamera);
    vec3 sunDirection = normalize(uSunDirection);
    if (geometric.y < 0.0) // 高度场法线偶尔因三角形绕序变负，翻回朝上。
    {
        geometric = -geometric;
    }

    // 五种材质按世界坐标采样。每种用不同尺度，避免所有纹理在同一频率上重复。
    vec4 weights = materialWeights(vWorldPosition, geometric, distanceToCamera);
    float forestWeight = clamp(1.0 - weights.x - weights.y - weights.z - weights.w, 0.0, 1.0);
    vec3 albedo = vec3(0.0);
    vec3 normalDetail = vec3(0.0);
    float roughness = 0.0;
    float total = 1e-4;
    if (distanceToCamera > 55.0)
    {
        // 远景简化：只取草与岩两张颜色，泥土/沙/林下用色调近似。
        // 这里覆盖画面大部分像素，省掉十几张法线与粗糙度采样，是帧时的主要来源。
        vec2 uv = vWorldPosition.xz / 5.0;
        vec3 grass = sampleAlbedo(uv, 0);
        grass = mix(vec3(ogxLuminance(grass)), grass, 1.12) * vec3(0.52, 0.64, 0.45);
        vec3 rock = sampleAlbedo(uv * 1.3, 2);
        rock = mix(vec3(ogxLuminance(rock)), rock, 0.35) * vec3(0.44, 0.47, 0.50);
        float moss = smoothstep(70.0, 150.0, vWorldPosition.y) * 0.55;
        rock = mix(rock, vec3(0.10, 0.14, 0.07), moss * 0.45);
        albedo = mix(grass, rock, clamp(weights.z, 0.0, 1.0));
        albedo = mix(albedo, albedo * vec3(0.58, 0.48, 0.36), weights.y * 0.75);
        albedo = mix(albedo, vec3(0.52, 0.46, 0.32), weights.w * 0.75);
        albedo = mix(albedo, albedo * vec3(0.52, 0.47, 0.36), forestWeight * 0.55);
        roughness = 0.82;
        total = 1.0;
    }
    else
    {
    if (weights.x > 0.004) // 草甸：三米一循环，近看有草叶与枯叶。
    {
        vec2 uv = vWorldPosition.xz / 3.1;
        vec2 microUv = vWorldPosition.xz / 0.78; // 高频细节层，近处草叶有颗粒。
        vec3 grass = sampleAlbedo(uv, 0) * 0.62 + sampleAlbedo(microUv, 0) * 0.38;
        float grassLuma = ogxLuminance(grass);
        grass = mix(vec3(grassLuma), grass, 1.12) * vec3(0.52, 0.64, 0.45); // 压低荧光绿，保留草地的暖黄绿。
        albedo += grass * weights.x;
        normalDetail += (sampleNormal(uv, 0) * 0.55 + sampleNormal(microUv, 0) * 0.45) * weights.x;
        roughness += sampleRoughness(uv, 0) * weights.x;
        total += weights.x;
    }
    if (weights.y > 0.004) // 泥土与小径：四米一循环，湿润处更深。
    {
        vec2 uv = vWorldPosition.xz / 4.2;
        albedo += sampleAlbedo(uv, 1) * vec3(0.78, 0.66, 0.54) * weights.y;
        normalDetail += sampleNormal(uv, 1) * weights.y;
        roughness += sampleRoughness(uv, 1) * weights.y;
        total += weights.y;
    }
    if (weights.z > 0.004) // 岩石：六米一循环，陡坡的层理更粗。
    {
        vec2 uv = vWorldPosition.xz / 6.5;
        vec3 rock = sampleAlbedo(uv, 2);
        rock = mix(vec3(ogxLuminance(rock)), rock, 0.35) * vec3(0.44, 0.47, 0.50); // 偏冷灰，不像沙丘。
        float moss = smoothstep(70.0, 150.0, vWorldPosition.y) * (0.35 + 0.35 * ogxValueNoise2(vWorldPosition.xz * 0.09));
        rock = mix(rock, vec3(0.10, 0.14, 0.07), moss * 0.45); // 中高坡混一点苔藓与高山草。
        albedo += rock * weights.z;
        normalDetail += sampleNormal(uv, 2) * weights.z;
        roughness += sampleRoughness(uv, 2) * weights.z;
        total += weights.z;
    }
    if (weights.w > 0.004) // 湿沙：两米一循环。
    {
        vec2 uv = vWorldPosition.xz / 2.0;
        albedo += sampleAlbedo(uv, 3) * vec3(0.55, 0.48, 0.36) * weights.w;
        normalDetail += sampleNormal(uv, 3) * weights.w;
        roughness += sampleRoughness(uv, 3) * weights.w;
        total += weights.w;
    }
    if (forestWeight > 0.004) // 林下腐殖土：三点五米一循环。
    {
        vec2 uv = vWorldPosition.xz / 3.4;
        albedo += sampleAlbedo(uv, 4) * vec3(0.58, 0.56, 0.42) * forestWeight;
        normalDetail += sampleNormal(uv, 4) * forestWeight;
        roughness += sampleRoughness(uv, 4) * forestWeight;
        total += forestWeight;
    }
    }
    albedo /= total;
    roughness /= total;
    normalDetail /= total;

    // 大尺度颜色变化：同一种草在阴阳坡与干湿处不会是一块纯色。
    float macro = ogxFbm2(vWorldPosition.xz * 0.028 + 13.1, 4);
    float dryness = smoothstep(0.42, 0.74, ogxFbm2(vWorldPosition.xz * 0.018 + 31.0, 3));
    albedo *= 0.70 + macro * 0.52;
    albedo *= mix(vec3(1.0), vec3(1.16, 1.00, 0.72), dryness * 0.40); // 干草斑块，草坡不再一整片绿。
    albedo *= vec3(1.0, 0.98 + macro * 0.05, 0.92 + macro * 0.10); // 略微暖调，抵消阴天蓝。
    // 湿沙与泥土靠近水面时更深、更亮，湿表面才有反光。
    float wet = 0.0;
    if (vWorldPosition.y < uWaterLevel + 2.2)
    {
        wet = 1.0 - smoothstep(uWaterLevel, uWaterLevel + 2.2, vWorldPosition.y);
        albedo *= mix(1.0, 0.58, wet * 0.85);
        roughness = mix(roughness, 0.30, wet * 0.75);
    }
    if (vWorldPosition.y < uWaterLevel - 0.02) // 水下地面被水吸收，颜色提前压掉。
    {
        albedo *= vec3(0.42, 0.62, 0.60);
    }
    // 高山雪线：只在高处与朝上的面保留白雪，山脊因此有明确的冷色高光。
    float snow = smoothstep(300.0, 340.0, vWorldPosition.y) * smoothstep(0.35, 0.70, geometric.y);
    snow *= 0.40 + 0.60 * ogxValueNoise2(vWorldPosition.xz * 0.07);
    albedo = mix(albedo, vec3(0.78, 0.82, 0.88), snow * 0.30);
    roughness = mix(roughness, 0.66, snow);

    // 法线：XZ 投影的切线法线映射到高度场切平面；远处淡出，防止闪烁。
    float detailFade = 1.0 - smoothstep(45.0, 240.0, distanceToCamera);
    vec3 tangent = normalize(vec3(1.0, 0.0, 0.0) - geometric * geometric.x);
    vec3 bitangent = cross(geometric, tangent);
    float normalStrength = mix(0.55, 1.15, weights.z) * detailFade;
    vec3 bump = tangent * normalDetail.x + bitangent * normalDetail.y;
    vec3 normal = normalize(geometric + bump * normalStrength);

    vec3 sunColor = worldSunColor(); // 与天空、云、水面共用同一色温。
    float shadow = 1.0;
    if (distanceToCamera < 90.0) // 九十米外不再做九点 PCF，远山阴影在画面上只有几像素。
    {
        shadow = shadowVisibility(vWorldPosition, geometric, distanceToCamera, 0.06, 13.0);
    }
    float cloudShadow = 1.0; // HDR 天空的云不参与动态云影，避免与照片云错位。
    float sunAmount = max(dot(normal, sunDirection), 0.0);
    float specular = ogxSpecularGGX(normal, viewDirection, sunDirection, clamp(roughness, 0.06, 0.98), 0.035);
    specular *= smoothstep(0.0, 0.08, sunAmount); // 背光面没有高光。
    vec3 sun = sunColor * (uSunStrength * sunAmount * shadow * cloudShadow);
    sun += sunColor * (uSunStrength * specular * shadow * cloudShadow);
    float skyOcclusion = clamp(0.55 + 0.45 * geometric.y, 0.25, 1.0); // 朝下的缝隙接收更少天光。
    vec3 ambient = albedo * vec3(0.28, 0.33, 0.38) * uSkyStrength;
    if (distanceToCamera < 90.0)
    {
        ambient = skyAmbient(normal, skyOcclusion) * albedo;
    }
    vec3 bounce = albedo * vec3(0.34, 0.30, 0.20) * max(0.0, -normal.y) * 0.55; // 地面反弹。
    vec3 color = albedo * sun + ambient + bounce;
    // 湖岸湿沙的镜面反射：天空与对岸的亮部会在湿沙上拉出一条柔和高光。
    if (wet > 0.001)
    {
        vec3 wetReflection = textureLod(uSkyCube, reflect(-viewDirection, normal), 2.5).rgb;
        color += wetReflection * wet * 0.12 * albedo.r;
    }

    vec3 viewToSurface = normalize(vWorldPosition - uCameraPos);
    vec3 horizonColor = textureLod(uSkyCube, normalize(vec3(viewToSurface.x, 0.04, viewToSurface.z)), 2.0).rgb;
    if (distanceToCamera < 90.0) // 近景做完整大气与贴地雾，远景只叠一层空气色。
    {
        OgxAtmosphere air = worldAtmosphere();
        float altitude = max(uCameraPos.y, 0.0) * 0.001;
        vec3 transmittance;
        vec3 haze = ogxAerialPerspective(air, altitude, viewToSurface, distanceToCamera * 0.001, sunDirection, 3, transmittance);
        color = color * transmittance + haze;
        float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71));
        vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection,
                               sunColor * 2.0, jitter, 3);
        color = ogxFogApply(color, fog);
    }
    float extraHaze = smoothstep(120.0, 1400.0, distanceToCamera) * 0.06;
    color = mix(color, horizonColor, extraHaze);

    fragColor = vec4(color, 1.0);
    fragNormal = vec4(ogxEncodeNormal(geometric), clamp(distanceToCamera / 1000.0, 0.0, 1.0), 1.0);
}
