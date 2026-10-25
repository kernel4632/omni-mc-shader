#version 330 core
// 水面片元阶段：Gerstner 波法线、菲涅尔、粗糙平面反射、屏幕折射、吸收、太阳闪光与岸线泡沫。
// 调用位置：主场景在水面以上的不透明几何之后；水面写入自己的深度，雾阶段据此计算距离。
// 设计原因与取舍：
//   反射来自镜像相机，不是屏幕空间猜出来的；波纹只扰动采样坐标，山脊倒影不会出现阶梯。
//   折射读取水下的场景颜色，再按水下光程做逐通道吸收；掠射时光程最长，
//   水色自然收敛到深蓝，而不是整片反射亮天空，这是水面在低视角下不发白的关键。
//   菲涅尔用真实水的零点零二基础反射率，再对粗糙水面封顶；近看透底、远看映天，但不会变成一面镜子。
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
    // Gerstner 波法线：五组不同波长与方向的解析波，叠加一层细碎风纹。
    // 远处自动压平高频，避免一个像素跨过多个波长时闪成噪点。
    vec3 wave = ogxGerstnerNormal(vWorldPosition.xz, uTime, surfaceDepth, 1.0, 0.82);
    if (uWaterDebug == 1) // 开发用：直接看法线，检查波纹是否过强。
    {
        fragColor = vec4(wave * 0.5 + 0.5, 1.0);
        return;
    }    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    // 平面反射按法线在屏幕上偏移，再用九点旋转核模糊；粗糙水面不会是一面完美镜子。
    // 偏移随距离收小，倒影不会被拉成横条；模糊半径随距离与粗糙度一起增大。
    vec2 reflectionUv = screenUv + wave.xz * (0.020 / (1.0 + surfaceDepth * 0.018));
    float lod = mix(0.4, 3.4, smoothstep(12.0, 650.0, surfaceDepth)); // 远处取更高的 mip，滤掉地平线附近的高频明暗。
    vec2 texel = uReflectionTexel * 1.6;
    vec3 reflection = textureLod(uReflection, clamp(reflectionUv, vec2(0.001), vec2(0.999)), lod).rgb * 0.44;
    vec2 diagonal = vec2(0.72, 0.69); // 斜向采样，避免十字核把高光拉成横竖亮线。
    reflection += textureLod(uReflection, clamp(reflectionUv + texel * diagonal, vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv - texel * diagonal, vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv + texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    reflection += textureLod(uReflection, clamp(reflectionUv - texel * vec2(-diagonal.x, diagonal.y), vec2(0.001), vec2(0.999)), lod).rgb * 0.14;
    // 天空只补倒影出屏的边缘；平面倒影本身已经包含山体、天空与云，不能再被一块蓝天覆盖。
    vec3 reflectedDir = reflect(-view, wave);
    reflectedDir.y = max(reflectedDir.y, 0.015);
    vec3 skyReflection = lightingSampleSky(reflectedDir, mix(1.0, 3.5, lod * 0.25)) * vec3(0.86, 0.92, 1.0);
    vec2 edgeUv = smoothstep(vec2(0.0), vec2(0.035), reflectionUv) * (1.0 - smoothstep(vec2(0.965), vec2(1.0), reflectionUv));
    reflection = mix(skyReflection, reflection, edgeUv.x * edgeUv.y);
    // 反射高光压缩：太阳附近的云和天空可以很亮，但湖面不应该整片过曝成白纸。
    reflection = min(reflection, vec3(12.0)); // 先夹住极端值。
    reflection /= 1.0 + max(reflection.r, max(reflection.g, reflection.b)) * 0.14; // 柔和压缩，保留太阳路径的亮核。
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
    OgxWater water = ogxWaterDefault(); // 水体参数。
    water.deepColor = vec3(0.0020, 0.014, 0.030); // 深水偏青蓝，保留可见层次。
    water.absorption = vec3(0.52, 0.145, 0.058); // 红光吸收最快，浅滩偏青、深处偏蓝。
    water.shallowColor = vec3(0.012, 0.060, 0.052); // 浅滩青绿色，不要过饱和。
    water.roughness = 0.16; // 湖面有风，太阳高光摊成一条细带。
    // 吸收按水下光程算，不按竖直深度。掠射时视线在水里走得很远，红光先被吃掉，
    // 颜色收敛到深蓝；这是水面在低视角下变暗的主要来源，比单纯压反射更接近真实水色。
    vec3 transmitted = behind * ogxWaterAbsorption(water, pathLength);
    transmitted = mix(water.deepColor, transmitted, exp(-pathLength * 0.22));
    transmitted = mix(water.shallowColor, transmitted, clamp(verticalDepth * 0.60, 0.0, 1.0));
    if (uWaterDebug == 2) { fragColor = vec4(reflection, 1.0); return; } // 开发用：只看反射色。
    if (uWaterDebug == 3) { fragColor = vec4(transmitted, 1.0); return; } // 开发用：只看折射与吸收。
    // 菲涅尔：正对时几乎全透，掠射时接近镜面；这是水面最重要的物理线索。
    float NdotV = max(dot(wave, view), 0.0); // 视线与水面法线。
    float fresnel = min(ogxWaterFresnel(NdotV, 0.02), 0.82); // 粗糙水面在极限掠射时也不会完全镜面。
    // 掠射角压反射：真实湖面在这个角度主要映出对岸的暗色山体，而不是整片亮天空；
    // 再叠一层冷色水体倾向，避免反射被太阳附近的白色雾霾推成一条白带。
    reflection *= vec3(0.78, 0.88, 1.0) * mix(0.62, 1.0, smoothstep(0.02, 0.42, NdotV));
    vec3 color = mix(transmitted, reflection, fresnel); // 折射与反射按菲涅尔混合。
    // 太阳闪光：用只保留大尺度坡度的法线算一个宽高光，再乘一块低频亮斑。
    // 直接用五组解析波的法线算锐高光，波峰会在湖面排成规则的白格；粗糙水面上的太阳路径
    // 应该是一条断续的碎金带，而不是整片棋盘。
    vec3 glintNormal = normalize(mix(vec3(0.0, 1.0, 0.0), wave, 0.45));
    float glint = min(ogxSpecularGGX(glintNormal, view, sunDirection, 0.42, 0.02), 1.0);
    float glitterMask = texture(uCloudCurl, vWorldPosition.xz * 0.012 + vec2(uTime * 0.0020, -uTime * 0.0011)).r;
    glint *= smoothstep(0.42, 0.70, glitterMask) * smoothstep(0.04, 0.20, NdotV);
    if (uWaterDebug == 4) { fragColor = vec4(vec3(glint * 0.3), 1.0); return; } // 开发用：只看太阳高光。
    color += sunChroma * (glint * uSunIrradiance * 0.18);
    // 岸线泡沫：只用很浅的水与岸坡梯度两个条件，泡沫贴着岸线出现，不会铺满整片浅湖。
    // 噪声取自三维 Worley 细节图，气泡是圆的；旧的方形值噪声会在水面上印出规则的白色网格。
    float foamNoise = texture(uCloudDetail, vec3(vWorldPosition.xz * 0.060, uTime * 0.006)).x;
    vec2 depthStep = 1.0 / uResolution;
    float depthLeft = linearDepth(texture(uSceneDepth, screenUv - vec2(depthStep.x, 0.0)).r);
    float depthRight = linearDepth(texture(uSceneDepth, screenUv + vec2(depthStep.x, 0.0)).r);
    float depthDown = linearDepth(texture(uSceneDepth, screenUv - vec2(0.0, depthStep.y)).r);
    float depthUp = linearDepth(texture(uSceneDepth, screenUv + vec2(0.0, depthStep.y)).r);
    // 岸坡梯度：水下地形在岸边变化快，湖心变化慢；用四邻深度差把泡沫限制在岸线附近。
    float shoreGradient = abs(depthRight - depthLeft) + abs(depthUp - depthDown);
    float foam = ogxWaterFoam(verticalDepth, foamNoise); // 库的岸线泡沫；按竖直水深判断。
    foam = smoothstep(0.34, 0.72, foam) * smoothstep(0.20, 1.20, shoreGradient);
    foam *= 1.0 - smoothstep(25.0, 110.0, surfaceDepth); // 远处泡沫只有几像素，淡出避免锯齿。
    vec3 foamColor = vec3(0.52, 0.56, 0.55) * (0.48 + 0.52 * max(dot(wave, sunDirection), 0.0)); // 泡沫受太阳照亮。
    color = mix(color, foamColor, foam * 0.62); // 泡沫是覆盖，不是叠加白光。
    // 远处水面在屏幕上只剩几像素，逐渐收敛到同方向的天空色，与地平线接上。
    // 收敛权重比上一版低得多，远景湖面保留自己的深蓝色，不再被白色地平线洗掉。
    vec3 horizonDir = normalize(vec3(-view.x, 0.02, -view.z));
    vec3 horizon = lightingSampleSky(horizonDir, 2.5) * vec3(0.72, 0.82, 0.95);
    color = mix(color, horizon, smoothstep(700.0, 2600.0, surfaceDepth) * 0.35);
    // 云影也落在湖面上：水面的反射与高光都来自同一颗太阳，云挡住太阳时湖水应该一起变暗。
    // 只压暗，不加灰；阴影里的湖水仍保留深蓝色与波纹层次。
    float waterCloudShadow = lightingCloudShadow(vWorldPosition);
    color *= mix(0.58, 1.0, waterCloudShadow);
    fragColor = vec4(color, 1.0); // 水面不透明写入，深度随后覆盖。
}
