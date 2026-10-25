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
    wave = normalize(wave + vec3((chop - 0.5) * 0.10, 0.0, (chop - 0.5) * 0.085) * (1.0 - smoothstep(12.0, 80.0, surfaceDepth))); // 远处收掉高频。
    // 高频风纹：远处湖面只剩几像素时，单靠大波法线看不出水；加一层快速噪声坡度，倒影会被撕成细碎波纹。
    float rippleA = ogxValueNoise2(vWorldPosition.xz * 1.7 + vec2(uTime * 0.12, -uTime * 0.09)); // 一米级风纹。
    float rippleB = ogxValueNoise2(vWorldPosition.xz * 3.4 - vec2(uTime * 0.19, uTime * 0.13)); // 半米级碎纹。
    float rippleFade = 1.0 - smoothstep(180.0, 900.0, surfaceDepth); // 远处淡出，避免闪烁。
    wave = normalize(wave + vec3((rippleA - 0.5) * 0.16, 0.0, (rippleB - 0.5) * 0.16) * rippleFade); // 小坡度扰动。
    if (uWaterDebug == 1) // 开发用：直接看法线，检查波纹是否过强。
    {
        fragColor = vec4(wave * 0.5 + 0.5, 1.0);
        return;
    }
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    // 平面反射按法线在屏幕上偏移，再用九点旋转核模糊；粗糙水面不会是一面完美镜子。
    vec2 reflectionUv = screenUv + wave.xz * (0.14 / (1.0 + surfaceDepth * 0.030)); // 波纹偏移；远处收小，倒影不会被拉成横条。
    float blur = mix(1.0, 5.0, smoothstep(25.0, 900.0, surfaceDepth)); // 远处倒影更模糊。
    vec2 texel = uReflectionTexel * blur; // 模糊步长。
    vec2 diagonal = vec2(0.78, 0.62); // 斜向采样，避免十字核把高光拉成横竖亮线。
    vec3 reflection = texture(uReflection, clamp(reflectionUv, vec2(0.001), vec2(0.999))).rgb * 0.28; // 中心样本。
    reflection += texture(uReflection, clamp(reflectionUv + vec2(texel.x, 0.0), vec2(0.001), vec2(0.999))).rgb * 0.10; // 右。
    reflection += texture(uReflection, clamp(reflectionUv - vec2(texel.x, 0.0), vec2(0.001), vec2(0.999))).rgb * 0.10; // 左。
    reflection += texture(uReflection, clamp(reflectionUv + vec2(0.0, texel.y), vec2(0.001), vec2(0.999))).rgb * 0.10; // 上。
    reflection += texture(uReflection, clamp(reflectionUv - vec2(0.0, texel.y), vec2(0.001), vec2(0.999))).rgb * 0.10; // 下。
    reflection += texture(uReflection, clamp(reflectionUv + texel * diagonal, vec2(0.001), vec2(0.999))).rgb * 0.08; // 右上。
    reflection += texture(uReflection, clamp(reflectionUv - texel * diagonal, vec2(0.001), vec2(0.999))).rgb * 0.08; // 左下。
    reflection += texture(uReflection, clamp(reflectionUv + texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999))).rgb * 0.08; // 左上。
    reflection += texture(uReflection, clamp(reflectionUv - texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999))).rgb * 0.08; // 右下。
    // 天空只补倒影出屏的边缘；平面倒影本身已经包含山体、天空与云，不能再被一块蓝天覆盖。
    vec3 reflectedDir = reflect(-view, wave); // 反射方向。
    reflectedDir.y = max(reflectedDir.y, 0.015); // 水面不反射地平线以下。
    vec3 skyReflection = lightingSampleSky(reflectedDir, mix(1.0, 4.0, blur * 0.15)); // 天空与云。
    vec2 edgeUv = smoothstep(vec2(0.0), vec2(0.035), reflectionUv) * (1.0 - smoothstep(vec2(0.965), vec2(1.0), reflectionUv)); // 边缘权重。
    reflection = mix(skyReflection, reflection, edgeUv.x * edgeUv.y); // 只在靠近屏幕边缘时用天空补边。
    // 反射高光压缩：太阳附近的云和天空可以很亮，但湖面不应该整片过曝成白纸。
    reflection = min(reflection, vec3(24.0)); // 先夹住极端值，避免后续除法被一个超大样本主导。
    reflection /= 1.0 + max(reflection.r, max(reflection.g, reflection.b)) * 0.12; // 柔和压缩，保留太阳路径的亮核。
    // 折射：按水深与视线偏移采样水下颜色，跨过岸线就退回原坐标，避免拉伸。
    float sceneDepth = linearDepth(texture(uSceneDepth, screenUv).r); // 水下不透明面的距离。
    float waterDepth = max(sceneDepth - surfaceDepth, 0.0) * max(abs(view.y), 0.14); // 近似竖直水深；掠射时仍保留浅滩梯度。
    vec2 refractionUv = clamp(screenUv + ogxWaterRefractionOffset(wave, waterDepth, surfaceDepth, 0.045), vec2(0.001), vec2(0.999)); // 折射坐标。
    if (linearDepth(texture(uSceneDepth, refractionUv).r) < surfaceDepth) // 偏移跨过岸线。
    {
        refractionUv = screenUv; // 退回原坐标。
    }
    vec3 behind = texture(uSceneColor, refractionUv).rgb; // 水下场景颜色。
    OgxWater water = ogxWaterDefault(); // 水体参数。
    water.deepColor = vec3(0.0025, 0.018, 0.036); // 深水偏青蓝，保留可见层次。
    water.absorption = vec3(0.62, 0.180, 0.075); // 红光吸收最快，浅滩偏青、深处偏蓝。
    water.shallowColor = vec3(0.018, 0.080, 0.072); // 浅滩的青绿色，不要过饱和。
    water.roughness = 0.075; // 湖面有一点风，太阳高光摊成一条细带。
    vec3 transmitted = behind * ogxWaterAbsorption(water, waterDepth); // 逐通道吸收。
    transmitted = mix(water.deepColor, transmitted, exp(-waterDepth * 0.38)); // 深水收敛到体色。
    transmitted = mix(water.shallowColor, transmitted, clamp(waterDepth * 0.50, 0.0, 1.0)); // 浅滩保留水色。
    // 菲涅尔：正对时几乎全透，掠射时接近镜面；这是水面最重要的物理线索。
    float NdotV = max(dot(wave, view), 0.0); // 视线与水面法线。
    float fresnel = ogxWaterFresnel(NdotV, 0.02); // 水的菲涅尔。
    vec3 color = mix(transmitted, reflection, fresnel); // 折射与反射按菲涅尔混合。
    // 太阳闪光：很锐的 GGX 高光，让水面在低阳下有一条碎金带；单独夹住，避免掠射角把整片湖烧白。
    float glint = min(ogxSpecularGGX(wave, view, sunDirection, water.roughness, 0.02), 4.0); // 太阳高光。
    color += sunChroma * (glint * uSunIrradiance * 0.85); // 高光直接叠在最终颜色上。
    // 岸线泡沫：只在浅水与噪声都满足时出现，远处淡出，避免整圈白边。
    float foamNoise = ogxFbm2(vWorldPosition.xz * 0.85 + vec2(uTime * 0.02, -uTime * 0.015), 3); // 泡沫形状。
    float foam = ogxWaterFoam(waterDepth * 0.55, foamNoise); // 库的岸线泡沫；乘零点五五让泡沫带约一米半宽。
    foam = smoothstep(0.16, 0.62, foam); // 让泡沫成块，不是一层均匀白边。
    foam *= 1.0 - smoothstep(35.0, 170.0, surfaceDepth); // 远处泡沫只有几像素，淡出避免锯齿。
    vec3 foamColor = vec3(0.58, 0.62, 0.60) * (0.52 + 0.48 * max(dot(wave, sunDirection), 0.0)); // 泡沫受太阳照亮。
    color = mix(color, foamColor, foam * 0.62); // 泡沫是覆盖，不是叠加白光。
    // 远处水面在屏幕上只剩几像素，逐渐收敛到同方向的天空色，与地平线接上。
    vec3 horizonDir = normalize(vec3(-view.x, 0.02, -view.z)); // 水平方向。
    vec3 horizon = lightingSampleSky(horizonDir, 2.5) * vec3(0.90, 0.94, 1.0); // 地平线天空，略压一点。
    color = mix(color, horizon, smoothstep(260.0, 2400.0, surfaceDepth) * 0.72); // 远距离空气透视，近处湖水不被洗白。
    fragColor = vec4(color, 1.0); // 水面不透明写入，深度随后覆盖。
}
