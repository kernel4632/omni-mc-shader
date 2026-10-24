#version 330 core
// 水面片元阶段：解析波法线、菲涅尔反射、屏幕折射、水体吸收、太阳高光、岸线泡沫与远景雾。
// 调用位置：测试世界在水面绘制阶段调用；反射纹理是每帧生成的小型天空立方体贴图。
// 设计原因与取舍：水面在本着色器里和场景颜色手动合成，再统一做空气透视与雾，
// 避免半透明混合之后重复叠雾；代价是需要读一次本像素的场景颜色。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 水面世界坐标。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uTime; // 场景时间，驱动波浪。
uniform float uFrame; // 帧号，给雾抖动换相位。
uniform samplerCube uSky; // 天空立方体贴图，包含云。
uniform sampler2D uSceneColor; // 水面之前的场景颜色。
uniform sampler2D uSceneDepth; // 水面之前的场景深度。
uniform vec2 uResolution; // 画面尺寸。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。

out vec4 fragColor; // 合成后的不透明水面颜色。

// 把深度缓冲的零到一值换成沿视线方向的距离。
float linearDepth(float depth)
{
    float z = depth * 2.0 - 1.0; // 换回裁剪空间的负一到一。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear)); // 透视投影反解。
}

void main()
{
    vec3 viewDirection = normalize(uCameraPos - vWorldPosition); // 从水面指向相机。
    float distanceToCamera = length(uCameraPos - vWorldPosition); // 到相机的距离，米。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    OgxWater water = ogxWaterDefault(); // 水体光学参数。
    vec3 normalDetail = ogxWaterNormal(vWorldPosition.xz, uTime, distanceToCamera, 0.9, 0.9); // 近处细节波法线。
    vec3 normalBroad = ogxWaterNormal(vWorldPosition.xz * 0.22, uTime, distanceToCamera, 0.9, 0.9); // 低频波法线，远处用它压低闪烁。
    vec3 normal = normalize(mix(normalDetail, normalBroad, smoothstep(60.0, 600.0, distanceToCamera))); // 按距离混合两种尺度。
    float reflectionLod = mix(0.0, 4.5, smoothstep(80.0, 1800.0, distanceToCamera)); // 远处反射用更模糊的 mip。
    vec3 reflection = textureLod(uSky, reflect(-viewDirection, normal), reflectionLod).rgb; // 天空与云的模糊反射。
    vec2 screenUv = gl_FragCoord.xy / uResolution; // 当前像素的屏幕坐标。
    float surfaceDepth = linearDepth(gl_FragCoord.z); // 水面到相机的距离。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float waterDepth = max(sceneDepth - surfaceDepth, 0.0); // 水层厚度近似。
    vec2 offset = ogxWaterRefractionOffset(normal, waterDepth, distanceToCamera, water.refraction); // 折射偏移。
    vec2 distortedUv = clamp(screenUv + offset, vec2(0.001), vec2(0.999)); // 偏移后的采样坐标。
    vec3 behind = texture(uSceneColor, distortedUv).rgb; // 水下的场景颜色。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.35 + vec2(uTime * 0.05, uTime * 0.03), 2); // 泡沫噪声。
    float foam = ogxWaterFoam(waterDepth, foamNoise); // 岸线泡沫。
    float alpha; // 水面覆盖率。
    vec3 waterColor = ogxWaterShade(water, normal, viewDirection, sunDirection, sunColor * 4.0,
                                    reflection, behind, waterDepth, foam, alpha); // 水面着色。
    vec3 sceneColor = texture(uSceneColor, screenUv).rgb; // 本像素原本的场景颜色。
    vec3 color = mix(sceneColor, waterColor, alpha); // 手动合成，保证之后只做一次雾。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    OgxAtmosphere air = ogxAtmosphereEarth(); // 大气常数。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewDirection, distanceToCamera * 0.001, sunDirection, 4, transmittance); // 远景空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 5); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写成不透明，混合阶段读到的就是最终水色。
}
