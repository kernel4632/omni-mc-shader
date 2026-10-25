#version 330 core
// 水面片元阶段：菲涅尔、粗糙平面反射、屏幕折射、吸收、太阳闪光与岸线泡沫。
// 调用位置：主场景在水面以上的不透明几何之后；水面写入自己的深度，雾阶段据此计算距离。
// 设计原因与取舍：
//   反射来自镜像相机，不是屏幕空间猜出来的；波纹只扰动采样坐标，山脊倒影不会出现阶梯。
//   折射读取水下的场景颜色，再按水深做逐通道吸收；浅滩透出泥沙，深处收敛到深蓝。
//   菲涅尔用真实水的零点零二基础反射率，近看透底、远看映天，这是水面不像塑料的关键。
#include "common.glsl"
#include "shadow_lighting.glsl"

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
    // 三层波形：近处细波、低频长波与一层不同方向的碎波；远处自动压平，避免闪烁。
    vec3 waveA = ogxWaterNormal(vWorldPosition.xz, uTime, surfaceDepth, 0.38, 1.10); // 近景细波。
    vec3 waveB = ogxWaterNormal(vWorldPosition.xz * 0.21 + vec2(3.7, -1.3), uTime * 0.83, surfaceDepth, 0.31, 0.85); // 低频长波。
    vec3 wave = normalize(mix(waveA, waveB, smoothstep(25.0, 420.0, surfaceDepth))); // 按距离混合。
    float chop = ogxValueNoise2(vWorldPosition.xz * 0.65 + vec2(uTime * 0.05, -uTime * 0.04)); // 半米级碎波。
    wave = normalize(wave + vec3((chop - 0.5) * 0.08, 0.0, (chop - 0.5) * 0.065) * (1.0 - smoothstep(12.0, 80.0, surfaceDepth))); // 远处收掉高频。
    if (uWaterDebug == 1) // 开发用：直接看法线，检查波纹是否过强。
    {
        fragColor = vec4(wave * 0.5 + 0.5, 1.0);
        return;
    }
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    // 平面反射按法线在屏幕上偏移，再用五点核模糊；粗糙水面不会是一面完美镜子。
    vec2 reflectionUv = screenUv + wave.xz * (0.09 / (1.0 + surfaceDepth * 0.03)); // 波纹偏移。
    float blur = mix(1.5, 7.5, smoothstep(20.0, 900.0, surfaceDepth)); // 远处倒影更模糊。
    vec2 texel = uReflectionTexel * blur; // 模糊步长。
    vec3 reflection = texture(uReflection, clamp(reflectionUv, vec2(0.001), vec2(0.999))).rgb * 0.4; // 中心样本。
    reflection += texture(uReflection, clamp(reflectionUv + vec2(texel.x, 0.0), vec2(0.001), vec2(0.999))).rgb * 0.15; // 右。
    reflection += texture(uReflection, clamp(reflectionUv - vec2(texel.x, 0.0), vec2(0.001), vec2(0.999))).rgb * 0.15; // 左。
    reflection += texture(uReflection, clamp(reflectionUv + vec2(0.0, texel.y), vec2(0.001), vec2(0.999))).rgb * 0.15; // 上。
    reflection += texture(uReflection, clamp(reflectionUv - vec2(0.0, texel.y), vec2(0.001), vec2(0.999))).rgb * 0.15; // 下。
    // 天空反射作为兜底与补充：倒影边缘出屏时仍然有天空，不会出现黑边。
    vec3 reflectedDir = reflect(-view, wave); // 反射方向。
    reflectedDir.y = max(reflectedDir.y, 0.015); // 水面不反射地平线以下。
    vec3 skyReflection = lightingSampleSky(reflectedDir, mix(1.0, 4.0, blur * 0.15)); // 天空与云。
    float reflectionWeight = clamp(0.55 + blur * 0.04, 0.55, 0.8); // 平面反射占主导，天空补边。
    reflection = mix(skyReflection, reflection, reflectionWeight) * vec3(0.78, 0.87, 0.96); // 合成反射，略压暗偏冷。
    // 折射：按水深与视线偏移采样水下颜色，跨过岸线就退回原坐标，避免拉伸。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float waterDepth = max(sceneDepth - surfaceDepth, 0.0) * max(abs(view.y), 0.10); // 近似竖直水深。
    vec2 refractionUv = clamp(screenUv + ogxWaterRefractionOffset(wave, waterDepth, surfaceDepth, 0.045), vec2(0.001), vec2(0.999)); // 折射坐标。
    if (linearDepth(texture(uSceneDepth, refractionUv).r) < surfaceDepth) // 偏移跨过岸线。
    {
        refractionUv = screenUv; // 退回原坐标。
    }
    vec3 behind = texture(uSceneColor, refractionUv).rgb; // 水下场景颜色。
    OgxWater water = ogxWaterDefault(); // 水体参数。
    water.deepColor = vec3(0.004, 0.026, 0.052); // 深水偏青蓝，保留可见层次。
    water.absorption = vec3(0.48, 0.130, 0.055); // 红光吸收最快，浅滩偏青、深处偏蓝。
    water.shallowColor = vec3(0.032, 0.115, 0.100); // 浅滩的青绿色，不要过饱和。
    water.roughness = 0.08; // 湖面有一点风，太阳高光摊成一条细带。
    vec3 transmitted = behind * ogxWaterAbsorption(water, waterDepth); // 逐通道吸收。
    transmitted = mix(water.deepColor, transmitted, exp(-waterDepth * 0.42)); // 深水收敛到体色。
    transmitted = mix(water.shallowColor, transmitted, clamp(waterDepth * 0.55, 0.0, 1.0)); // 浅滩保留水色。
    // 菲涅尔：正对时几乎全透，掠射时接近镜面；这是水面最重要的物理线索。
    float NdotV = max(dot(wave, view), 0.0); // 视线与水面法线。
    float fresnel = ogxWaterFresnel(NdotV, 0.02); // 水的菲涅尔。
    vec3 color = mix(transmitted, reflection, fresnel); // 折射与反射按菲涅尔混合。
    // 太阳闪光：很锐的 GGX 高光，让水面在低阳下有一条碎金带。
    float glint = ogxSpecularGGX(wave, view, sunDirection, water.roughness, 0.02); // 太阳高光。
    color += sunChroma * (glint * uSunIrradiance * 1.6); // 高光直接叠在最终颜色上。
    // 岸线泡沫：只在浅水与噪声都满足时出现，远处淡出，避免整圈白边。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.85 + vec2(uTime * 0.02, -uTime * 0.015), 3); // 泡沫形状。
    float foam = ogxWaterFoam(waterDepth * 0.9, foamNoise); // 库的岸线泡沫。
    foam = smoothstep(0.08, 0.55, foam); // 让泡沫成块，不是一层均匀白边。
    foam *= 1.0 - smoothstep(35.0, 180.0, surfaceDepth); // 远处泡沫只有几像素，淡出避免锯齿。
    color += vec3(0.72, 0.76, 0.74) * (foam * (0.45 + 0.55 * max(dot(wave, sunDirection), 0.0)) * 1.6); // 泡沫受太阳照亮。
    // 远处水面在屏幕上只剩几像素，逐渐收敛到同方向的天空色，与地平线接上。
    vec3 horizonDir = normalize(vec3(-view.x, 0.02, -view.z)); // 水平方向。
    vec3 horizon = lightingSampleSky(horizonDir, 2.0); // 地平线天空。
    color = mix(color, horizon, smoothstep(180.0, 900.0, surfaceDepth)); // 远处融进天空。
    fragColor = vec4(color, 1.0); // 水面不透明写入，深度随后覆盖。
}
