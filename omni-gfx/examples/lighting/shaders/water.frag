#version 330 core
// 水面片元阶段：Gerstner 波法线、平面反射、折射、iterationT 的水体吸收与菲涅尔。
// 调用位置：主场景在水面以上的不透明几何之后；水面写入自己的深度，雾阶段据此计算距离。
// 设计原因与取舍：
//   反射来自镜像相机，倒影包含山体、树线与云；水面没有单独的太阳高光，
//   iterationT 的太阳亮带来自倒影里被米氏散射照亮的那片天空，所以这里也不再叠白色光斑。
//   水体吸收与雾色逐项照 iterationT 的 WaterFog：红绿蓝分别衰减，深水收敛到暗青，
//   然后用菲涅尔把反射混进来；正对时能看清水下，掠射时接近镜面。
#include "common.glsl"

in vec3 vWorldPosition; // 水面世界坐标。

uniform sampler2D uReflection; // 半分辨率平面反射。
uniform vec2 uReflectionTexel; // 反射图一个纹素的大小。
uniform sampler2D uSceneColor; // 水面之前的不透明场景颜色。
uniform sampler2D uSceneDepth; // 不透明场景深度。
uniform vec2 uResolution; // 完整画面尺寸。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。
uniform int uWaterDebug; // 一表示输出法线调试色，仅用于开发。

out vec4 fragColor; // 水面颜色。

// 把深度缓冲的零到一值换成沿视线的距离。
float linearDepth(float depth) // 返回米。
{
    float z = depth * 2.0 - 1.0; // 换回裁剪空间的负一到一。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear)); // 透视投影反解。
}

void main()
{
    vec3 view = normalize(uCameraPosition - vWorldPosition); // 从水面指向相机。
    float surfaceDepth = length(uCameraPosition - vWorldPosition); // 水面到相机的距离。
    vec2 screenUv = gl_FragCoord.xy / uResolution; // 当前像素坐标。
    // Gerstner 波法线：五组不同波长与方向的解析波，叠加一层细碎风纹。
    // 远处自动压平高频，避免一个像素跨过多个波长时闪成噪点。
    vec3 wave = ogxGerstnerNormal(vWorldPosition.xz, uTime, surfaceDepth, 0.45, 0.025);
    if (uWaterDebug == 1) // 开发用：直接看法线，检查波纹是否过强。
    {
        fragColor = vec4(wave * 0.5 + 0.5, 1.0);
        return;
    }
    vec3 skyLight = lightingSunSkyLight(); // 天空辐照度，用于水色。
    // 平面反射按法线在屏幕上偏移，再用九点旋转核模糊；粗糙水面不会是一面完美镜子。
    vec2 reflectionUv = screenUv + wave.xz * (0.0015 / (1.0 + surfaceDepth * 0.018));
    float lod = mix(2.0, 5.0, smoothstep(12.0, 1600.0, surfaceDepth)); // 远处取更高的 mip，滤掉地平线附近的高频明暗。
    vec2 texel = uReflectionTexel * 3.6;
    vec3 reflection = textureLod(uReflection, clamp(reflectionUv, vec2(0.001), vec2(0.999)), lod).rgb * 0.44;
    vec2 diagonal = vec2(0.72, 0.69); // 斜向采样，避免十字核把高光拉成横竖亮线。
    reflection += textureLod(uReflection, clamp(reflectionUv + texel * diagonal, vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv - texel * diagonal, vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv + texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv - texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    // 天空只补倒影出屏的边缘；平面倒影本身已经包含山体、天空与云，不能再被一块蓝天覆盖。
    vec3 reflectedDir = reflect(-view, wave);
    reflectedDir.y = max(reflectedDir.y, 0.008);
    vec3 skyReflection = lightingSampleSky(reflectedDir, mix(1.0, 4.2, lod * 0.25));
    vec2 edgeUv = smoothstep(vec2(0.0), vec2(0.035), reflectionUv) * (1.0 - smoothstep(vec2(0.965), vec2(1.0), reflectionUv));
    reflection = mix(skyReflection, reflection, edgeUv.x * edgeUv.y);
    // 折射：按水下光程偏移采样水下颜色，跨过岸线就退回原坐标，避免拉伸。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float pathLength = max(sceneDepth - surfaceDepth, 0.0); // 光线在水里走过的实际长度，米。
    float verticalDepth = pathLength * max(abs(view.y), 0.10); // 近似竖直水深，供岸线泡沫使用。
    vec2 refractionUv = clamp(screenUv + ogxWaterRefractionOffset(wave, verticalDepth, surfaceDepth, 0.038), vec2(0.001), vec2(0.999));
    if (linearDepth(texture(uSceneDepth, refractionUv).r) < surfaceDepth) // 偏移跨过岸线。
    {
        refractionUv = screenUv; // 退回原坐标。
    }
    vec3 behind = texture(uSceneColor, refractionUv).rgb; // 水下场景颜色。
    // 水体吸收与雾：逐项照 iterationT 的 WaterFog，上水面时使用 0.29 的消光与 0.21 的吸收指数。
    vec3 attenuationColor = vec3(0.2, 0.5, 0.7); // 红绿蓝的衰减基色。
    vec3 absorbed = behind * pow(attenuationColor * 0.99, vec3(pathLength * 0.21)); // 逐通道吸收。
    float visibility = exp2(-pathLength * 0.29); // 水下能见度。
    vec3 waterFogColor = vec3(0.05, 0.6, 1.0); // 水体本身的散射色。
    waterFogColor *= dot(vec3(0.33333), skyLight) * 0.04; // 天光越亮水色越亮，与 iterationT 相同。
    vec3 transmitted = mix(waterFogColor, absorbed, visibility); // 先吸收，再按可见度混入雾色。
    if (uWaterDebug == 5) { fragColor = vec4(behind, 1.0); return; } // 开发用：只看水下场景原色。
    if (uWaterDebug == 2) { fragColor = vec4(reflection, 1.0); return; } // 开发用：只看反射色。
    if (uWaterDebug == 3) { fragColor = vec4(transmitted, 1.0); return; } // 开发用：只看折射与吸收。
    // 菲涅尔：与 iterationT 相同的 Schlick 与可见性项；正对几乎全透，掠射接近镜面。
    float NdotV = max(dot(wave, view), 0.0); // 视线与水面法线。
    float NdotL = max(dot(wave, reflect(-view, wave)), 0.0); // 反射方向与法线，镜面时等于 NdotV。
    float specular = ogxFresnelSchlick(NdotL, 0.02, 1.0); // 水的 F0 是零点零二。
    specular *= ogxVisibilitySchlick(NdotL, NdotV + 0.8, 0.0); // 与 iterationT 的 V_Schlick 相同。
    // 反射与折射的亮度差会加强轮廓：亮天空在水面边缘更明显，暗树影则压回去。
    float difference = (length(transmitted) - length(reflection)) / (length(transmitted) + length(reflection) + 1e-4);
    difference = sign(difference) * sqrt(abs(difference));
    specular += 0.75 * difference * (1.0 - specular) * specular;
    vec3 color = mix(transmitted, reflection, clamp(specular, 0.0, 1.0)); // 折射与反射按菲涅尔混合。
    // 晴天静水没有白沫；只有下雨或拍岸时才应该出现，本场景保持水面干净。
    // 远处水面在屏幕上只剩几像素，逐渐收敛到同方向的天空色，与地平线接上。
    vec3 horizonDir = normalize(vec3(-view.x, 0.02, -view.z));
    vec3 horizon = lightingSampleSky(horizonDir, 3.0);
    color = mix(color, horizon, smoothstep(1500.0, 9000.0, surfaceDepth) * 0.45);
    fragColor = vec4(color, 1.0); // 水面不透明写入，深度随后覆盖。
}
