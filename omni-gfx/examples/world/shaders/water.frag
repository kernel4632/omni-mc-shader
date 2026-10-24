#version 330 core
// 水面片元阶段：解析波形法线、菲涅尔反射、屏幕空间折射、深浅水色与太阳高光。
// 调用位置：测试世界在水面绘制阶段调用；反射纹理是每帧生成的小型天空立方体贴图。
// 设计原因与取舍：不做真实光线追踪，用天空立方体贴图和屏幕空间折射近似，
// 在固定场景里能同时看清反射、透射和岸线，代价是薄薄一层水面颜色近似。
#include "atmosphere.glsl"

in vec3 vWorldPosition;  // 水面世界坐标。

uniform vec3 uCameraPos;  // 相机位置。
uniform float uTime;  // 场景时间，驱动波浪。
uniform samplerCube uSky;  // 天空立方体贴图，包含云。
uniform sampler2D uSceneColor;  // 水面之前的场景颜色。
uniform sampler2D uSceneDepth;  // 水面之前的场景深度。
uniform vec2 uResolution;  // 画面尺寸。
uniform float uNear;  // 投影近平面。
uniform float uFar;  // 投影远平面。

out vec4 fragColor;  // 预乘前的水面颜色与透明度。

// 四组方向波叠加，返回带水平位移的近似法线。
vec3 waveNormal(vec2 position, float time)
{
    vec2 gradient = vec2(0.0);  // 高度场的水平梯度。
    gradient += vec2(0.62, 0.28) * cos(dot(position, vec2(0.62, 0.28)) * 0.42 + time * 0.9) * 0.085;  // 长波。
    gradient += vec2(-0.31, 0.74) * cos(dot(position, vec2(-0.31, 0.74)) * 0.95 + time * 1.3) * 0.050;  // 斜向波。
    float distance = length(position - uCameraPos.xz);  // 到相机的水平距离。
    float detailFade = 1.0 - smoothstep(60.0, 260.0, distance);  // 远处不再采样高频细节，避免闪烁。
    gradient += vec2(0.88, -0.41) * cos(dot(position, vec2(0.88, -0.41)) * 1.90 + time * 1.7) * 0.020 * detailFade;  // 短波。
    gradient += vec2(-0.67, -0.55) * cos(dot(position, vec2(-0.67, -0.55)) * 4.10 + time * 2.1) * 0.006 * detailFade;  // 细碎波纹。
    return normalize(vec3(-gradient.x, 1.0, -gradient.y));  // 高度场梯度转成法线。
}

// 把深度缓冲的零到一值换成沿视线方向的距离。
float linearDepth(float depth)
{
    float z = depth * 2.0 - 1.0;  // 换回裁剪空间的负一到一。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear));  // 透视投影反解。
}

void main()
{
    vec3 normal = waveNormal(vWorldPosition.xz, uTime);  // 水面法线。
    vec3 viewDirection = normalize(uCameraPos - vWorldPosition);  // 从水面指向相机。
    float facing = max(dot(normal, viewDirection), 0.0);  // 正对程度。
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);  // 菲涅尔：越掠射越像镜子。
    vec3 reflection = texture(uSky, reflect(-viewDirection, normal)).rgb;  // 天空反射。
    vec2 screenUv = gl_FragCoord.xy / uResolution;  // 当前像素的屏幕坐标。
    vec2 distortedUv = clamp(screenUv + normal.xz * 0.035, vec2(0.001), vec2(0.999));  // 折射偏移。
    vec3 behind = texture(uSceneColor, distortedUv).rgb;  // 水下的场景颜色。
    float sceneDepth = linearDepth(texture(uSceneDepth, distortedUv).r);  // 水下场景的距离。
    float waterDepth = max(sceneDepth - linearDepth(gl_FragCoord.z), 0.0);  // 水层厚度近似。
    vec3 shallow = vec3(0.16, 0.52, 0.48);  // 浅水偏绿。
    vec3 deep = vec3(0.010, 0.075, 0.170);  // 深水偏蓝。
    vec3 tint = mix(shallow, deep, clamp(waterDepth / 55.0, 0.0, 1.0));  // 按厚度混合水色。
    vec3 refracted = behind * tint;  // 水下颜色被水吸收。
    vec3 color = mix(refracted, reflection * vec3(0.82, 0.90, 1.0), fresnel);  // 反射与折射按菲涅尔混合，反射略偏蓝。
    vec3 sunDirection = normalize(uSunDirection);  // 太阳方向。
    float specular = pow(max(dot(reflect(-viewDirection, normal), sunDirection), 0.0), 420.0);  // 太阳高光。
    color += sunColor() * specular * 6.0;  // 高光叠加。
    float horizonDistance = length(vWorldPosition - uCameraPos);  // 到相机的距离。
    float horizonFade = 1.0 - smoothstep(700.0, 2200.0, horizonDistance);  // 远处水面淡出到天空。
    color = mix(color, skyBase(normalize(vWorldPosition - uCameraPos)), smoothstep(600.0, 2000.0, horizonDistance));  // 远处水色并入天空，消除硬地平线。
    float alpha = clamp(fresnel * 0.9 + 0.28, 0.0, 0.96) * horizonFade;  // 水面整体不透明度。
    fragColor = vec4(color, alpha);  // 交给混合阶段。
}
