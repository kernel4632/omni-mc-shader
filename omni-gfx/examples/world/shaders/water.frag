#version 330 core
// 水面片元阶段：菲涅尔混合、太阳高光、屏幕折射、水体吸收、岸线泡沫与远景雾。
// 调用位置：测试世界在地形之后绘制水面；反射由独立阶段算好并降噪，这里只负责合成。
// 设计原因与取舍：反射从本阶段拆出去以后，水面不再自己步进，主画面只做十几次采样；
// 半分辨率反射放大时会被水面法线打散，看不出分辨率差异，却省下四分之三的追踪开销。
// 天空与海面接缝靠两边共用同一份空气透视参数来消除。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 水面世界坐标。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform float uTime; // 场景时间，驱动波浪。
uniform float uFrame; // 帧号，给雾抖动换相位。
uniform samplerCube uSky; // 天空立方体贴图，包含云。
uniform sampler2D uReflection; // 半分辨率降噪后的反射，透明通道是可信度。
uniform sampler2D uSceneColor; // 水面之前的场景颜色。
uniform sampler2D uSceneDepth; // 水面之前的场景深度。
uniform vec2 uResolution; // 画面尺寸。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。
uniform float uSunStrength; // 太阳辐照度倍率。

out vec4 fragColor; // 合成后的水面颜色。

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
    water.deepColor = vec3(0.032, 0.100, 0.170); // 深水加深一点蓝色，但保留可见的层次。
    water.absorption = vec3(0.220, 0.080, 0.045); // 吸收只留浅滩可见，深处收敛到深水色，海底空洞不会透出黑色。
    vec3 normalDetail = ogxWaterNormal(vWorldPosition.xz, uTime, distanceToCamera, 0.9, 0.9); // 近处细节波法线。
    vec3 normalBroad = ogxWaterNormal(vWorldPosition.xz * 0.22, uTime, distanceToCamera, 0.9, 0.9); // 低频波法线，远处用它压低闪烁。
    vec3 normal = normalize(mix(normalDetail, normalBroad, smoothstep(60.0, 600.0, distanceToCamera))); // 按距离混合两种尺度。
    vec3 reflectionDirection = reflect(-viewDirection, normal); // 反射方向。
    vec2 screenUv = gl_FragCoord.xy / uResolution; // 当前像素的屏幕坐标。
    vec4 traced = texture(uReflection, screenUv); // 降噪后的地形反射与可信度。
    // 反射立方体贴图只有一百六十像素见方，必须从较模糊的层级开始取，
    // 否则云的边缘会被放大成一块块方块，看上去像水面上堆了白色积木。
    float reflectionLod = mix(1.6, 4.5, smoothstep(40.0, 1500.0, distanceToCamera)); // 近处保留云的轮廓，远处才模糊。
    vec3 skyReflection = textureLod(uSky, reflectionDirection, reflectionLod).rgb; // 天空与云的反射。
    vec3 reflection = mix(skyReflection, traced.rgb, traced.a); // 命中地形就用地形，否则用天空。
    float surfaceDepth = linearDepth(gl_FragCoord.z); // 水面到相机的距离。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float waterDepth = max(sceneDepth - surfaceDepth, 0.0); // 水层厚度近似。
    vec2 offset = ogxWaterRefractionOffset(normal, waterDepth, distanceToCamera, water.refraction); // 折射偏移。
    vec2 distortedUv = clamp(screenUv + offset, vec2(0.001), vec2(0.999)); // 偏移后的采样坐标。
    float distortedDepth = linearDepth(texture(uSceneDepth, distortedUv).r); // 偏移后采样到的表面深度。
    if (distortedDepth < surfaceDepth) // 偏移跨过了岸线，会采到水面之前的东西。
    {
        distortedUv = screenUv; // 退回原坐标，岸边不会出现拉伸的岸上颜色。
    }
    vec3 behind = max(texture(uSceneColor, distortedUv).rgb, water.deepColor * 0.45); // 水下的场景颜色，黑色空洞用深水色兜底。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.35 + vec2(uTime * 0.05, uTime * 0.03), 2); // 泡沫噪声。
    float foam = ogxWaterFoam(waterDepth, foamNoise); // 岸线泡沫。
    float alpha; // 水面覆盖率。
    vec3 waterColor = ogxWaterShade(water, normal, viewDirection, sunDirection, sunColor * uSunStrength,
                                    reflection, behind, waterDepth, foam, alpha); // 菲涅尔、吸收、高光与泡沫合成。
    vec3 sceneColor = texture(uSceneColor, screenUv).rgb; // 本像素原本的场景颜色。
    vec3 color = waterColor; // 水体着色里已经含菲涅尔、吸收与泡沫，再混一次场景色会重复计算。
    // 远处水面在屏幕上只剩几像素，水雾与吸收会把它压成黑带；按距离收敛到同方向的天空色，
    // 与地平线接上，这也是真实海面远处看起来就是天空色的原因。
    float horizonBlend = smoothstep(150.0, 3000.0, distanceToCamera) * 0.92;
    color = mix(color, skyReflection, horizonBlend);
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, -viewDirection, distanceToCamera * 0.001, sunDirection, 3, transmittance); // 水面到相机的空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 3); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写成不透明的最终水色。
}
