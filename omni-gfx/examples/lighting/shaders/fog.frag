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
    float mist = exp(-height / 4.5); // 贴水薄雾，几米内明显。
    float haze = exp(-height / max(uFogHeight, 1.0)); // 高一点的稀雾，负责远景空气感。
    vec2 wind = vec2(uTime * 0.004, uTime * 0.002); // 雾随风缓慢移动。
    float low = texture(uCloudCurl, (position.xz * 0.009) + wind).r; // 低频团块。
    float high = texture(uCloudCurl, (position.xz * 0.027) + wind * 1.7).g; // 高频碎边。
    float breakup = mix(0.58, 1.32, low * 0.7 + high * 0.3); // 两层噪声合成柔和团块，避免单层噪声像脏斑。
    return uFogDensity * (mist * 0.78 + haze * 0.22) * breakup; // 两层相加。
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
    float maxDistance = min(distance, 420.0); // 雾只积到四百二十米，更远交给空气透视。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    float cosSun = dot(direction, sunDirection); // 视线与太阳夹角。
    float phase = ogxHenyeyGreenstein(cosSun, 0.64) + ogxHenyeyGreenstein(cosSun, 0.22) * 0.30; // 双瓣相位，逆光雾更亮。
    float jitter = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x; // 起点抖动。
    vec3 scattered = vec3(0.0); // 累积散射。
    vec3 skyAmbient = lightingSkyAmbient(vec3(0.0, 1.0, 0.0), 0.8) * uFogAmbient; // 天光在整段雾里近似不变，循环外取一次。
    float transmittance = 1.0; // 剩余透过率。
    // 十步二次分布：近处步长小，能看清贴着水面的雾带与光柱；远处步长大，成本不随距离增加。
    float previousT = 0.0; // 上一步在整段雾里的归一化位置。
    for (int i = 0; i < 10; i++) // 逐步穿过雾。
    {
        float u = (float(i) + jitter) / 10.0; // 当前步的归一化位置，带像素抖动。
        float t = u * u; // 二次曲线：近处密、远处疏。
        float stepLength = maxDistance * max(t - previousT, 0.0); // 本步步长，米。
        previousT = t; // 记录位置。
        if (stepLength <= 0.0) // 抖动可能让首步落到零。
        {
            continue; // 跳过。
        }
        vec3 position = uCameraPosition + direction * (maxDistance * t); // 当前雾点。
        float density = fogDensity(position); // 当地密度。
        if (density > 1e-5) // 空区域跳过阴影查询。
        {
            float dither = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(i * 17, i * 31)).x; // 每步一个抖动。
            float shadow = lightingShadowCheap(position, vec3(0.0, 1.0, 0.0), maxDistance * t, dither); // 地形是否挡光。
            float cloudShadow = lightingCloudShadow(position); // 云影把光柱切成明暗带。
            float visibility = shadow * mix(1.0, cloudShadow, 0.85); // 云影为主，地形阴影补近处细节。
            float extinction = exp(-density * stepLength); // 这一步的透过率。
            // 太阳散射：阴影决定光柱，相位决定逆光亮度；强度按步长与剩余透过率积分。
            vec3 sunLight = sunChroma * (uSunIrradiance * uFogScatter * phase * visibility * 0.55); // 直射雾光。
            vec3 ambient = skyAmbient; // 天光。
            scattered += (sunLight + ambient) * (transmittance * (1.0 - extinction)); // 体积散射积分。
            transmittance *= extinction; // 更新透过率。
        }
        if (transmittance < 0.01) // 几乎不透明。
        {
            break; // 提前结束。
        }
    }
    fragColor = vec4(color * transmittance + scattered, 1.0); // 雾合成。
}
