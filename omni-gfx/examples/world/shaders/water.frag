#version 330 core
// 水面片元阶段：菲涅尔混合、太阳闪光、屏幕折射、水体吸收、岸线泡沫与远景空气透视。
// 调用位置：测试世界在地形之后绘制水面；反射由独立阶段算好并降噪，这里只负责合成。
// 设计原因与取舍：
//   反射从本阶段拆出去以后，水面不再自己步进，主画面只做十几次采样；
//   半分辨率反射放大时会被水面法线打散，看不出分辨率差异，却省下四分之三的追踪开销。
//   反射采样按法线偏移，水面因此不是一面完美镜子，近处能看出波纹把倒影揉碎。
//   颜色附件的透明通道写零，作为“这是水面”的标记，后面的遮蔽不会把地形遮蔽涂到水上。
//   天空与海面接缝靠两边共用同一份空气透视参数来消除。
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

out vec4 fragColor; // 合成后的水面颜色，透明通道固定为零。

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
    water.deepColor = vec3(0.020, 0.062, 0.115); // 深水偏蓝，保留可见层次。
    water.absorption = vec3(0.26, 0.088, 0.042); // 红光吸收最快，浅滩呈青绿、深处收敛到深蓝。
    water.shallowColor = vec3(0.038, 0.150, 0.160); // 浅滩的青绿色不要过饱和，否则岸边像一条发光带。
    water.roughness = 0.045; // 太阳闪光集中，海面才有那一条碎金带。
    // 三层波形：大尺度长波决定水面起伏，中尺度给出斜向交叉，近处再叠细波纹。
    vec3 normalDetail = ogxWaterNormal(vWorldPosition.xz, uTime, distanceToCamera, 0.62, 4.4); // 近处细节波法线。
    vec3 normalBroad = ogxWaterNormal(vWorldPosition.xz * 0.20, uTime * 0.85, distanceToCamera, 0.62, 4.4); // 低频波法线。
    vec3 normal = normalize(mix(normalDetail, normalBroad, smoothstep(50.0, 520.0, distanceToCamera))); // 按距离混合两种尺度。
    // 再叠一层方向不一致的细碎波纹：让水面在近处不会出现同一走向的规则条带。
    float chop = ogxValueNoise2(vWorldPosition.xz * 0.55 + vec2(uTime * 0.11, -uTime * 0.07)); // 半米到两米尺度的扰动。
    normal = normalize(normal + vec3((chop - 0.5) * 0.10, 0.0, (chop - 0.5) * 0.08) * (1.0 - smoothstep(10.0, 60.0, distanceToCamera))); // 远处收掉，避免闪烁。
    vec3 reflectionDirection = reflect(-viewDirection, normal); // 反射方向。
    vec2 screenUv = gl_FragCoord.xy / uResolution; // 当前像素的屏幕坐标。
    // 反射按法线在屏幕上偏移一点点：远处的倒影被波纹揉碎，不再是一条硬邦邦的镜像边界。
    vec2 reflectionOffset = normal.xz * 0.035 / (1.0 + distanceToCamera * 0.02); // 近处偏移明显，远处收敛。
    vec4 traced = texture(uReflection, clamp(screenUv + reflectionOffset, vec2(0.001), vec2(0.999))); // 降噪后的地形反射与可信度。
    // 反射立方体贴图只有一百九十二像素见方，必须从较模糊的层级开始取，
    // 否则云的边缘会被放大成一块块方块，看上去像水面上堆了白色积木。
    float reflectionLod = mix(1.4, 4.2, smoothstep(40.0, 1500.0, distanceToCamera)); // 近处保留云的轮廓，远处才模糊。
    reflectionDirection.y = max(reflectionDirection.y, 0.02); // 水面不可能反射地平线以下，压到水平面以上避免采到天空盒底部的黑面。
    vec3 skyReflection = textureLod(uSky, reflectionDirection, reflectionLod).rgb; // 天空与云的反射。
    vec3 reflection = mix(skyReflection, traced.rgb, traced.a); // 命中地形就用地形，否则用天空。
    float surfaceDepth = linearDepth(gl_FragCoord.z); // 水面到相机的距离。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float waterDepth = max(sceneDepth - surfaceDepth, 0.0); // 水层厚度近似。
    vec2 offset = ogxWaterRefractionOffset(normal, waterDepth, distanceToCamera, water.refraction * 1.6); // 折射偏移。
    vec2 distortedUv = clamp(screenUv + offset, vec2(0.001), vec2(0.999)); // 偏移后的采样坐标。
    float distortedDepth = linearDepth(texture(uSceneDepth, distortedUv).r); // 偏移后采样到的表面深度。
    if (distortedDepth < surfaceDepth) // 偏移跨过了岸线，会采到水面之前的东西。
    {
        distortedUv = screenUv; // 退回原坐标，岸边不会出现拉伸的岸上颜色。
    }
    vec3 behind = max(texture(uSceneColor, distortedUv).rgb, water.deepColor * 0.45); // 水下的场景颜色，黑色空洞用深水色兜底。
    // 两层泡沫噪声：一层沿水线成带状，一层打散成小块，岸边不会出现一条均匀的白边。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.42 + vec2(uTime * 0.06, uTime * 0.04), 3); // 泡沫噪声。
    float foamFade = 1.0 - smoothstep(45.0, 220.0, distanceToCamera); // 远处泡沫只有几像素，淡出避免锯齿。
    float foam = ogxWaterFoam(waterDepth * 0.8, foamNoise) * foamFade; // 岸线泡沫。
    float crest = smoothstep(0.66, 0.96, ogxValueNoise2(vWorldPosition.xz * 0.13 + vec2(uTime * 0.03, uTime * 0.02))); // 远处漂着的白浪花。
    foam = max(foam, crest * 0.18 * smoothstep(80.0, 320.0, distanceToCamera)); // 只在稍远处出现，近岸交给岸线泡沫。
    float alpha; // 水面覆盖率。
    vec3 waterColor = ogxWaterShade(water, normal, viewDirection, sunDirection, sunColor * uSunStrength,
                                    reflection, behind, waterDepth, foam, alpha); // 菲涅尔、吸收、高光与泡沫合成。
    // 太阳闪光再补一层更锐的 GGX：海面上那一条亮带是水面最容易被认出的特征。
    float glint = ogxSpecularGGX(normal, viewDirection, sunDirection, 0.028, 0.02); // 很光滑的微表面。
    glint *= smoothstep(-0.1, 0.25, dot(normalize(vWorldPosition - uCameraPos), sunDirection)); // 只在朝阳的那一侧。
    waterColor += sunColor * glint * uSunStrength * 2.4; // 叠上碎金带。
    // 远处水面在屏幕上只剩几像素，水雾与吸收会把它压成黑带；按距离收敛到同方向的天空色，
    // 与地平线接上，这也是真实海面远处看起来就是天空色的原因。
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    float horizonBlend = smoothstep(70.0, 1800.0, distanceToCamera); // 距离淡出，远处收敛到天空色。
    // 天空方向抬到地平线以上三度：贴近水平时视线会与地面相交，单次散射会退化成零。
    vec3 toSky = normalize(vec3(-viewDirection.x, max(-viewDirection.y, 0.055), -viewDirection.z));
    // 直接取天空立方体贴图：它每帧由同一份六步大气算法渲染，地平线附近也抬高三度，
    // 因此和画面上方的天空同源。采样一次纹理比逐像素再积一遍大气便宜，两边算式也不会各自漂移。
    vec3 horizonSky = textureLod(uSky, toSky, 1.0).rgb; // 一级层级足够平滑，又不会像二级把地平线压暗。
    vec3 color = mix(waterColor, horizonSky, horizonBlend);
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, -viewDirection, distanceToCamera * 0.001, sunDirection, 2, transmittance); // 水面到相机的空气散射；远景已由天空色接手，两段足够。
    // 远处水面已经收敛到天空色；再叠一次向下看的空气透视会得到接近零的散射，
    // 在海天交界压出一条黑线，所以只在还没收敛到天空的像素上应用。
    color = mix(color * transmittance + haze, color, horizonBlend); // 空气散射只作用于中近景。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 2); // 低空体积雾；抖动加时间抗锯齿把两段的台阶抹平。
    // 远处水面已经收敛到天空色，再叠地面雾会比天空亮，海天交界就会出现一条亮线。
    // 淡出时只缩小雾的散射与遮挡：若连透过率一起乘小，水面的天空色会被乘没，反而压出一条黑线。
    color = ogxFogApply(color, ogxFogFade(fog, 1.0 - horizonBlend)); // 再叠贴地雾。
    // 远处圆盘三角形被拉得极扁，个别像素会算出非有限值；这类像素直接丢弃，让天空补上。
    if (any(isnan(color)) || any(isinf(color))) { discard; }
    fragColor = vec4(color, 0.0); // 透明通道为零，标记这里是水面。
}
