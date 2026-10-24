#version 330 core
// 水面片元阶段：屏幕空间地形反射、菲涅尔混合、太阳高光、屏幕折射、水体吸收、岸线泡沫与远景雾。
// 调用位置：测试世界在地形之后绘制水面；反射与折射都读取同一帧的场景颜色与深度。
// 设计原因与取舍：地形反射用屏幕空间步进。岛在水面之上，反射光线朝上，正好能在
// 已经画好的场景深度里找到交点，不必再渲染一遍镜像场景；步进失败时退回天空立方体，
// 所以远处水面与掠射角不会出现空洞。命中后再用三次二分把交点拉近真实表面，
// 减少反射错位。天空与海面接缝靠两边共用同一份空气透视参数来消除。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 水面世界坐标。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform vec3 uForward; // 相机前方向，用来算视深度。
uniform float uTime; // 场景时间，驱动波浪。
uniform float uFrame; // 帧号，给雾抖动换相位。
uniform samplerCube uSky; // 天空立方体贴图，包含云。
uniform sampler2D uSceneColor; // 水面之前的场景颜色。
uniform sampler2D uSceneDepth; // 水面之前的场景深度。
uniform vec2 uResolution; // 画面尺寸。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。
uniform mat4 uViewProjection; // 相机视图投影矩阵，屏幕空间步进使用。
uniform float uSunStrength; // 太阳辐照度倍率。

out vec4 fragColor; // 合成后的水面颜色。

// 把深度缓冲的零到一值换成沿视线方向的距离。
float linearDepth(float depth)
{
    float z = depth * 2.0 - 1.0; // 换回裁剪空间的负一到一。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear)); // 透视投影反解。
}

// 把一个世界点投影到屏幕，同时给出它沿视线方向的深度。
bool projectPoint(vec3 position, out vec2 screenUv, out float viewDepth)
{
    vec4 clip = uViewProjection * vec4(position, 1.0); // 裁剪空间坐标。
    screenUv = vec2(-1.0); // 失败时给出画面外的坐标。
    viewDepth = 0.0; // 失败时深度无意义。
    if (clip.w <= 1e-3) // 点在相机后面。
    {
        return false;
    }
    screenUv = clip.xy / clip.w * 0.5 + 0.5; // 归一化到零到一。
    viewDepth = dot(position - uCameraPos, uForward); // 沿视线方向的深度，与下面的反解同一口径。
    return screenUv.x >= 0.0 && screenUv.x <= 1.0 && screenUv.y >= 0.0 && screenUv.y <= 1.0; // 画面外的点不算命中。
}

// 屏幕空间反射：沿反射方向步进，命中的地形颜色与可信度一起返回。
vec3 traceReflection(vec3 origin, vec3 direction, out float confidence)
{
    confidence = 0.0; // 默认不可信，调用方会退回天空反射。
    float stepLength = 0.8; // 起始步长，米。
    float travelled = stepLength; // 已经走过的距离。
    for (int i = 0; i < 18; i++) // 固定步数，最远约两百米，覆盖岛到相机之间的水面。
    {
        vec3 position = origin + direction * travelled; // 当前采样点。
        vec2 sampleUv; // 采样点的屏幕坐标。
        float sampleDepth; // 采样点的视深度。
        if (!projectPoint(position, sampleUv, sampleDepth)) // 出了画面或跑到相机后面就停止。
        {
            break;
        }
        float sceneDepth = linearDepth(texture(uSceneDepth, sampleUv).r); // 这个像素上真正看到的表面深度。
        float thickness = max(0.6, sampleDepth * 0.05); // 允许的厚度，远处放宽，避免漏掉薄墙。
        if (sceneDepth < sampleDepth && sceneDepth > sampleDepth - thickness) // 光线钻到了表面后面。
        {
            float low = max(travelled - stepLength, 0.0); // 二分区间下端。
            float high = travelled; // 二分区间上端。
            for (int j = 0; j < 3; j++) // 三次等分足够把错位压到肉眼看不出的量级。
            {
                float middle = (low + high) * 0.5; // 区间中点。
                vec3 probe = origin + direction * middle; // 试探点。
                vec2 probeUv; // 试探点的屏幕坐标。
                float probeDepth; // 试探点的视深度。
                if (!projectPoint(probe, probeUv, probeDepth)) // 试探点跑出画面就保持当前区间。
                {
                    break;
                }
                float probeScene = linearDepth(texture(uSceneDepth, probeUv).r); // 试探点处的场景深度。
                if (probeScene < probeDepth) // 试探点已经在表面后面，收窄上半段。
                {
                    high = middle;
                }
                else // 还在表面前面，收窄下半段。
                {
                    low = middle;
                }
            }
            vec3 hitPosition = origin + direction * high; // 取靠后的端点，保证落在几何内部。
            vec2 hitUv; // 命中点的屏幕坐标。
            float hitDepth; // 命中点的视深度。
            if (!projectPoint(hitPosition, hitUv, hitDepth)) // 理论上不会失败，仍然按失败处理。
            {
                return vec3(0.0);
            }
            vec2 edgeFade = smoothstep(vec2(0.0), vec2(0.07), hitUv) * smoothstep(vec2(0.0), vec2(0.07), 1.0 - hitUv); // 画面边缘淡出。
            confidence = edgeFade.x * edgeFade.y; // 越靠边越不可信，避免拉出长条。
            return texture(uSceneColor, hitUv).rgb; // 命中处的场景颜色就是要反射的地形。
        }
        travelled += stepLength; // 前进一段。
        stepLength *= 1.20; // 步长逐渐放大，近处精细、远处覆盖更远。
    }
    return vec3(0.0); // 没有命中。
}

void main()
{
    vec3 viewDirection = normalize(uCameraPos - vWorldPosition); // 从水面指向相机。
    float distanceToCamera = length(uCameraPos - vWorldPosition); // 到相机的距离，米。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    OgxWater water = ogxWaterDefault(); // 水体光学参数。
    water.deepColor = vec3(0.032, 0.100, 0.170); // 深水加深一点蓝色，但保留可见的层次。
    water.absorption = vec3(0.105, 0.046, 0.021); // 吸收比库默认值弱，浅滩能看见沙底。
    vec3 normalDetail = ogxWaterNormal(vWorldPosition.xz, uTime, distanceToCamera, 0.9, 0.9); // 近处细节波法线。
    vec3 normalBroad = ogxWaterNormal(vWorldPosition.xz * 0.22, uTime, distanceToCamera, 0.9, 0.9); // 低频波法线，远处用它压低闪烁。
    vec3 normal = normalize(mix(normalDetail, normalBroad, smoothstep(60.0, 600.0, distanceToCamera))); // 按距离混合两种尺度。
    vec3 reflectionDirection = reflect(-viewDirection, normal); // 反射方向。
    float confidence; // 屏幕空间反射的可信度。
    vec3 traced = traceReflection(vWorldPosition + normal * 0.05, reflectionDirection, confidence); // 地形反射。
    // 反射立方体贴图只有一百二十八像素见方，必须从较模糊的层级开始取，
    // 否则云的边缘会被放大成一块块方块，看上去像水面上堆了白色积木。
    float reflectionLod = mix(1.6, 4.5, smoothstep(40.0, 1500.0, distanceToCamera)); // 近处保留云的轮廓，远处才模糊。
    vec3 skyReflection = textureLod(uSky, reflectionDirection, reflectionLod).rgb; // 天空与云的反射。
    vec3 reflection = mix(skyReflection, traced, confidence); // 命中地形就用地形，否则用天空。
    vec2 screenUv = gl_FragCoord.xy / uResolution; // 当前像素的屏幕坐标。
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
    vec3 behind = texture(uSceneColor, distortedUv).rgb; // 水下的场景颜色。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.35 + vec2(uTime * 0.05, uTime * 0.03), 2); // 泡沫噪声。
    float foam = ogxWaterFoam(waterDepth, foamNoise); // 岸线泡沫。
    float alpha; // 水面覆盖率。
    vec3 waterColor = ogxWaterShade(water, normal, viewDirection, sunDirection, sunColor * uSunStrength,
                                    reflection, behind, waterDepth, foam, alpha); // 菲涅尔、吸收、高光与泡沫合成。
    vec3 sceneColor = texture(uSceneColor, screenUv).rgb; // 本像素原本的场景颜色。
    vec3 color = mix(sceneColor, waterColor, alpha); // 手动合成，保证之后只做一次空气透视。
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
