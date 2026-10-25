#version 330 core
// 体积雾阶段：按高度密度与阴影贴图步进，产生贴着水面的薄雾和被立石切开的光柱。
// 调用位置：水面合成之后、时间抗锯齿之前；读取水面目标颜色与深度。
// 设计原因与取舍：
//   雾的每一步都查一次简化级联阴影；太阳方向上的几何会挡出暗带，光柱不是后期画上去的。
//   相位用双瓣 HG，前向散射让逆光雾更亮；步进起点用蓝噪声抖动，时间抗锯齿把条带抹平。
//   只对几何像素生效，天空的雾已经在大气散射里算过，重复叠会压暗地平线。
#include "common.glsl"
#include "shadow_lighting.glsl"

uniform sampler2D uSceneColor; // 水面合成后的颜色。
uniform sampler2D uDepth; // 水面或地形的深度。
uniform vec2 uResolution; // 完整画面尺寸。
uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform float uTanHalfFov; // 视场角一半的正切。
uniform float uAspect; // 宽高比。
uniform float uNear; // 投影近平面。
uniform float uFar; // 投影远平面。
uniform float uFogDensity; // 近地面雾密度倍率。
uniform float uFogHeight; // 高雾衰减高度，米。
uniform float uFogScatter; // 阳光散射强度。
uniform float uFogAmbient; // 天光雾亮度。

out vec4 fragColor; // 雾合成后的颜色。

// 深度换距离。
float linearDepth(float depth) // 返回沿视线距离，米。
{
    float z = depth * 2.0 - 1.0; // 裁剪空间。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear)); // 透视反解。
}

// 雾密度：低空贴水薄雾加一层更高的稀雾，再用噪声打散成团块。
float fogDensity(vec3 position) // 返回每米消光系数。
{
    float height = max(position.y - uWaterLevel, 0.0); // 离水面高度。
    float mist = exp(-height / 3.2); // 贴水薄雾，几米内明显。
    float haze = exp(-height / 34.0); // 高一点的稀雾，负责远景空气感。
    vec2 wind = vec2(uTime * 0.004, uTime * 0.002); // 雾随风缓慢移动。
    float noise = texture(uCloudCurl, (position.xz * 0.012) + wind).r; // 低频团块。
    float breakup = mix(0.45, 1.55, noise); // 团块明暗。
    return uFogDensity * (mist * 0.65 + haze * 0.35) * breakup; // 两层相加。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 当前像素深度。
    vec3 color = texture(uSceneColor, uv).rgb; // 水面合成后的颜色。
    if (depth >= 0.9999) // 天空已经包含大气散射。
    {
        fragColor = vec4(color, 1.0); // 不再叠地面雾。
        return;
    }
    vec3 direction = lightingRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 当前视线。
    float distance = linearDepth(depth); // 到场景的距离。
    float maxDistance = min(distance, 320.0); // 雾只积到三百二十米，更远交给空气透视。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    float cosSun = dot(direction, sunDirection); // 视线与太阳夹角。
    float phase = ogxHenyeyGreenstein(cosSun, 0.72) + ogxHenyeyGreenstein(cosSun, 0.25) * 0.35; // 双瓣相位。
    float jitter = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x; // 起点抖动。
    float stepLength = maxDistance / 6.0; // 六步，够看雾团与光柱，也给显卡留余量。
    vec3 scattered = vec3(0.0); // 累积散射。
    vec3 skyAmbient = lightingSkyAmbient(vec3(0.0, 1.0, 0.0), 0.8) * uFogAmbient; // 天光在整段雾里近似不变，循环外取一次。
    float transmittance = 1.0; // 剩余透过率。
    float travelled = stepLength * jitter; // 抖动起点。
    for (int i = 0; i < 6; i++) // 逐步穿过雾。
    {
        vec3 position = uCameraPosition + direction * travelled; // 当前雾点。
        float density = fogDensity(position); // 当地密度。
        if (density > 1e-5) // 空区域跳过阴影查询。
        {
            float dither = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(i * 17, i * 31)).x; // 每步一个抖动。
            float shadow = lightingShadowCheap(position, vec3(0.0, 1.0, 0.0), travelled, dither); // 阳光是否被挡。
            float extinction = exp(-density * stepLength); // 这一步的透过率。
            // 太阳散射：阴影决定光柱，相位决定逆光亮度；强度按步长与剩余透过率积分。
            vec3 sunLight = sunChroma * (uSunIrradiance * uFogScatter * phase * shadow * 0.35); // 直射雾光。
            vec3 ambient = skyAmbient; // 天光。
            scattered += (sunLight + ambient) * (transmittance * (1.0 - extinction)); // 体积散射积分。
            transmittance *= extinction; // 更新透过率。
        }
        travelled += stepLength; // 前进。
        if (transmittance < 0.01) // 几乎不透明。
        {
            break; // 提前结束。
        }
    }
    fragColor = vec4(color * transmittance + scattered, 1.0); // 雾合成。
}
