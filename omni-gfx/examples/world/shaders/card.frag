#version 330 core
// 植物卡片片元阶段：叶片、草叶与野花共用，按 alpha 测试裁切后做双面光照。
// 调用位置：测试世界主场景的叶片、草丛与野花绘制。
// 设计原因与取舍：
//   叶片很薄，直接按几何法线做 Lambert 会让背面全黑；这里按正反面翻法线，
//   再加一层逆光透射，太阳在树后时叶缘会亮起来，这是植被与塑料片的分界。
//   草叶根部接收到的天空光更少，用纹理纵坐标压暗，草丛才有“从土里长出来”的接触感。
//   远处把 alpha 阈值降低一点，避免 mipmap 把细叶平均到零后整片消失。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 卡片法线。
in vec2 vUv; // 卡片纹理坐标。
in vec3 vColor; // 色调。
in float vSway; // 风摆权重。

uniform sampler2D uCard; // 当前植物卡片。
uniform vec3 uCardTint; // 卡片类型色调：树叶压暗、草略亮、花保持原色。
uniform int uCardShadow; // 一表示需要 PCSS 阴影；草叶与花用小核近似，省掉九次采样。
uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。
uniform float uTime; // 场景时间。
uniform float uFrame; // 帧号。
uniform float uCloudCover; // 云量。
uniform float uWaterLevel; // 水面高度，反射阶段用来丢弃水下片段。
uniform int uReflectionPass; // 一表示正在渲染平面反射。
uniform samplerCube uSkyCube; // 天空环境光。
#include "shadow_sample.glsl"

out vec4 fragColor; // 线性颜色。

void main()
{
    if (uReflectionPass == 1 && vWorldPosition.y < uWaterLevel + 0.02) // 水下草叶不进反射。
    {
        discard;
    }
    vec4 sampleColor = texture(uCard, vUv); // 卡片颜色与透明度。
    float distanceToCamera = length(uCameraPos - vWorldPosition); // 距离决定 alpha 阈值与雾。
    float alphaCut = mix(0.34, 0.20, smoothstep(35.0, 160.0, distanceToCamera)); // 远处降低阈值。
    if (sampleColor.a < alphaCut) // 小于阈值的像素完全丢弃。
    {
        discard; // 透明部分不写深度，后面的草叶能透出来。
    }
    vec3 albedo = sampleColor.rgb * vColor * uCardTint; // 贴图色乘顶点色调与类型色调。
    vec3 geometric = normalize(vNormal); // 卡片法线由顶点阶段给出。
    if (!gl_FrontFacing) // 双面卡片：背面把法线翻过来。
    {
        geometric = -geometric;
    }
    vec3 sunDirection = normalize(uSunDirection); // 单位太阳方向。
    vec3 viewDirection = normalize(uCameraPos - vWorldPosition); // 单位视线方向。
    float shadow = 1.0; // 默认全亮。
    if (uCardShadow > 0) // 只有需要阴影的卡片才进阴影图。
    {
        shadow = shadowVisibility(vWorldPosition, geometric, distanceToCamera, 0.035, 8.0); // 小核软阴影。
    }
    float cloudShadow = 1.0; // HDR 天空的云不参与动态云影。
    float sunAmount = max(dot(geometric, sunDirection), 0.0); // 叶面入射角。
    // 薄叶透光：太阳从背后照来，叶面本身背光，但仍有相当一部分光穿过。
    float through = max(dot(-geometric, sunDirection), 0.0);
    vec3 transmitted = worldSunColor() * uSunStrength * albedo * (through * 0.75 + 0.08) * shadow * cloudShadow; // 逆光透射，叶缘发亮。
    vec3 sun = worldSunColor() * (uSunStrength * sunAmount * shadow * cloudShadow) * albedo; // 正面直射光。
    float sheen = ogxSpecularGGX(geometric, viewDirection, sunDirection, 0.62, 0.03); // 叶片表面的弱高光。
    sun += worldSunColor() * uSunStrength * sheen * shadow * cloudShadow * 0.35; // 高光只占三成五。
    // 天空环境光：根部暗、顶端亮；叶片朝向天空时接收更多。
    float upward = 0.5 + 0.5 * geometric.y; // 朝上为一、朝下为零。
    vec3 ambient; // 环境光按是否采样天空分两条路径。
    if (uCardShadow > 0) // 近景叶片取真实天空色。
    {
        vec3 sky = mix(textureLod(uSkyCube, geometric, 3.0).rgb, textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 3.0).rgb, 0.22); // 混入天顶色。
        ambient = sky * uSkyStrength * albedo * mix(0.68, 1.0, vUv.y) * (0.68 + 0.32 * upward); // 根部与背面压暗。
    }
    else // 草叶与花用固定环境色，省一次立方体采样。
    {
        ambient = albedo * vec3(0.30, 0.35, 0.30) * uSkyStrength * mix(0.68, 1.0, vUv.y); // 固定冷绿环境光。
    }
    vec3 color = sun + transmitted + ambient; // 三种光相加。
    if (uCardShadow == 0) // 草叶与花只铺在近景，跳过空气透视与低空雾。
    {
        fragColor = vec4(color, 1.0);
        return;
    }

    vec3 viewToSurface = normalize(vWorldPosition - uCameraPos); // 相机指向表面。
    OgxAtmosphere air = worldAtmosphere(); // 与天空共用同一套大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 高度从米换成公里。
    vec3 transmittance; // 相机到表面的透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewToSurface, distanceToCamera * 0.001, sunDirection, 2, transmittance); // 空气透视。
    color = color * transmittance + haze; // 先乘透过率再加雾色。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 每帧错开雾采样。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection,
                           worldSunColor() * 2.0, jitter, 2); // 低空雾只走两步。
    color = ogxFogApply(color, fog); // 叠上雾。
    fragColor = vec4(color, 1.0); // 卡片已经按 alpha 裁切，不写半透明。
}
