#version 330 core
// 反射阶段（半分辨率）：沿反射方向在世界空间步进，输出反射颜色、命中距离与几何信息。
// 调用位置：地形画完之后、水面合成之前；水面阶段读取降噪后的结果，不再自己追踪。
// 设计原因与取舍：把追踪挪到独立阶段有两个好处：半分辨率让步进成本降到四分之一，
// 并且可以在合成之前做一次邻域降噪，反射不会把逐像素的噪点直接带进水面颜色。
// 这里用世界空间步进而非纯屏幕空间步进：相机俯视水面时反射光线朝上，
// 世界空间步进可以直接和场景深度比距离，薄几何也不会被粗步长跨过去。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 水面世界坐标。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform vec3 uForward; // 相机前方向，用来算视深度。
uniform float uTime; // 场景时间，驱动波浪。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。
uniform mat4 uViewProjection; // 视图投影矩阵，世界点投到屏幕。
uniform mat4 uProjectionInverse; // 逆投影矩阵，屏幕深度换米制。
uniform samplerCube uSky; // 天空立方体贴图，作为兜底。
uniform sampler2D uSceneColor; // 场景颜色。
uniform sampler2D uSceneDepth; // 场景深度。

layout(location = 0) out vec4 fragReflection; // 反射颜色与可信度。
layout(location = 1) out vec4 fragDepth; // 屏幕深度，供降噪判断邻域。
layout(location = 2) out vec4 fragNormal; // 编码法线，供降噪判断朝向。

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
    viewDepth = dot(position - uCameraPos, uForward); // 沿视线方向的深度，与反解同一口径。
    return screenUv.x >= 0.0 && screenUv.x <= 1.0 && screenUv.y >= 0.0 && screenUv.y <= 1.0; // 画面外的点不算命中。
}

// 世界空间反射步进：命中的场景颜色与可信度一起返回。
vec3 traceReflection(vec3 origin, vec3 direction, out float confidence)
{
    confidence = 0.0; // 默认不可信，调用方会退回天空反射。
    float stepLength = 0.8; // 起始步长，米。
    float travelled = stepLength; // 已经走过的距离。
    for (int i = 0; i < 24; i++) // 固定步数，最远约四百米，覆盖岛到相机之间的水面。
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
            for (int j = 0; j < 4; j++) // 四次二分足够把错位压到肉眼看不出的量级。
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
        stepLength *= 1.18; // 步长逐渐放大，近处精细、远处覆盖更远。
    }
    return vec3(0.0); // 没有命中。
}

void main()
{
    vec3 viewDirection = normalize(uCameraPos - vWorldPosition); // 从水面指向相机。
    float distanceToCamera = length(uCameraPos - vWorldPosition); // 到相机的距离。
    vec3 normalDetail = ogxWaterNormal(vWorldPosition.xz, uTime, distanceToCamera, 0.9, 0.9); // 近处细节波法线。
    vec3 normalBroad = ogxWaterNormal(vWorldPosition.xz * 0.22, uTime, distanceToCamera, 0.9, 0.9); // 低频波法线。
    vec3 normal = normalize(mix(normalDetail, normalBroad, smoothstep(60.0, 600.0, distanceToCamera))); // 按距离混合两种尺度。
    vec3 reflectionDirection = reflect(-viewDirection, normal); // 反射方向。
    float confidence = 0.0; // 屏幕空间反射的可信度。
    vec3 reflection = traceReflection(vWorldPosition + normal * 0.05, reflectionDirection, confidence); // 世界空间追踪。
    if (confidence <= 0.001) // 没命中时退回天空，远处与掠射角不会出现空洞。
    {
        reflection = textureLod(uSky, reflectionDirection, 2.0).rgb; // 天空立方体贴图。
    }
    vec3 viewPos = ogxReflectionViewPos(gl_FragCoord.xy / uResolution, gl_FragCoord.z, uProjectionInverse); // 视空间位置。
    float screenDepth = ogxReflectionScreenDepth(-viewPos.z, uProjectionInverse); // 水面的屏幕深度。
    fragReflection = vec4(reflection, confidence); // 写反射与可信度。
    fragDepth = vec4(screenDepth, 0.0, 0.0, 1.0); // 写深度，降噪按它剔除非水面像素。
    fragNormal = vec4(ogxEncodeNormal(normal), 1.0, 1.0); // 写编码法线。
}
