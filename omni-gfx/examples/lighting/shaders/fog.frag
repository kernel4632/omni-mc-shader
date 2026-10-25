#version 330 core
// 体积雾阶段：沿视线步进高度雾，并用真实阴影步进生成可见光柱。
// 调用位置：水面合成之后、时间抗锯齿之前；读取水面目标颜色与深度。
// 设计原因与取舍：
//   每个雾点都沿太阳方向再走几次阴影查询：地形与云影把阳光切成亮暗两束，
//   光柱来自这份真实的可见度差，不是后期画上去的亮带。
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
uniform float uFogHeight; // 高层稀雾的衰减高度，米。
uniform float uFogScatter; // 阳光散射强度。
uniform float uFogAmbient; // 天光雾亮度。
uniform int uFogDebug; // 开发检查：零正常，一平均太阳可见度，二只输出雾散射。

out vec4 fragColor; // 雾合成后的颜色。

// 深度换距离。
float linearDepth(float depth) // 返回沿视线距离，米。
{
    float z = depth * 2.0 - 1.0; // 裁剪空间。
    return (2.0 * uNear * uFar) / (uFar + uNear - z * (uFar - uNear)); // 透视反解。
}

// 雾密度：贴水薄雾加一层更高的稀雾，再用两层噪声打散成团块。
float fogDensity(vec3 position) // 返回每米消光系数。
{
    float height = max(position.y - uWaterLevel, 0.0); // 离水面高度。
    // 贴水薄雾在二点六米内明显衰减：岸坡与近景地面高出水面几米，
    // 不应被一层均匀白纱盖住；光柱主要出现在水面上方这层薄雾里。
    float mist = exp(-height / 1.4);
    // 高层稀雾只保留很淡的一层，远处空气透视由地表着色器的解析散射负责，
    // 这里再叠一层浓雾会把草地与远山洗成同一种灰。
    float haze = exp(-height / max(uFogHeight, 1.0)) * 0.05;
    vec2 wind = vec2(uTime * 0.0032, uTime * 0.0017); // 雾随风缓慢移动。
    float low = texture(uCloudCurl, position.xz * 0.0075 + wind).r; // 一百多米尺度的团块。
    float high = texture(uCloudCurl, position.xz * 0.023 + wind * 1.7).g; // 四十米尺度的碎边。
    // 两层噪声只做轻微起伏：强度过大会让光柱断成脏斑点，时间抗锯齿也压不住。
    float breakup = mix(0.62, 1.25, low * 0.75 + high * 0.25);
    return uFogDensity * (mist * 0.95 + haze) * breakup; // 两层相加。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 当前像素深度。
    vec3 color = texture(uSceneColor, uv).rgb; // 水面合成后的颜色。
    if (depth >= 0.9999) // 天空已经包含大气散射与云。
    {
        fragColor = vec4(color, 1.0); // 不再叠地面雾。
        return;
    }
    vec3 direction = lightingRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 当前视线。
    float distance = linearDepth(depth); // 到场景的距离。
    float maxDistance = min(distance, 900.0); // 雾只积到九百米，更远交给空气透视。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunChroma = lightingSunChroma(); // 太阳色度。
    float cosSun = dot(direction, sunDirection); // 视线与太阳夹角。
    float phase = ogxHenyeyGreenstein(cosSun, 0.65) * 0.80 + ogxHenyeyGreenstein(cosSun, 0.12) * 0.20; // 双瓣相位，前向峰不尖。
    float jitter = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x; // 起点抖动。
    vec3 scattered = vec3(0.0); // 累积散射。
    float visibilitySum = 0.0; // 开发检查用的可见度加权和。
    float visibilityWeight = 0.0; // 开发检查用的权重和。
    vec3 skyAmbient = lightingSkyAmbient(vec3(0.0, 1.0, 0.0), 0.8) * uFogAmbient; // 天光在整段雾里近似不变。
    float transmittance = 1.0; // 剩余透过率。
    // 十六步二次分布：近处步长小，能看清贴着水面的雾带与光柱；远处步长大，成本不随距离增加。
    float previousT = 0.0;
    for (int i = 0; i < 16; i++)
    {
        float u = (float(i) + jitter) / 16.0; // 当前步的归一化位置。
        float t = u * u; // 二次曲线。
        float stepLength = maxDistance * max(t - previousT, 0.0); // 本步步长，米。
        previousT = t;
        if (stepLength <= 0.0) continue;
        vec3 position = uCameraPosition + direction * (maxDistance * t); // 当前雾点。
        float density = fogDensity(position); // 当地密度。
        if (density > 1.0e-5)
        {
            // 沿太阳方向走三次阴影查询：每次查一个更远的点，光柱边缘因此有柔和的半影。
            // 这一步是体积阴影，不是只看当前点；地形和云影都会在雾里留下真实的明暗。
            vec3 lightPosition = position; // 从当前雾点出发。
            float visibility = 0.0;
            float terrainVisibility = 0.0; // 开发检查：单独累计地形阴影，不混入云影。
            float lightStep = 3.5; // 第一段阴影距离，米；必须从近处开始，否则树冠与石门的影子会被跳过。
            for (int j = 0; j < 3; j++)
            {
                float dither = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(i * 17 + j * 41, i * 31 + j * 13)).x; // 每步抖动。
                float terrainShadow = lightingShadowCheap(lightPosition, vec3(0.0, 1.0, 0.0), maxDistance * t + lightStep, dither);
                float cloudShadow = lightingCloudShadow(lightPosition); // 云影在同一高度投下光柱。
                // 云影占比较低：云影是大块光带，真正的窄光柱来自石门、树冠与岸坡的地形阴影。
                // 如果让云影主导，雾里只会出现一整片灰，不会出现清晰的明暗边界。
                visibility += terrainShadow * mix(1.0, cloudShadow, 0.55);
                terrainVisibility += terrainShadow; // 开发检查：只累计地形阴影。
                lightPosition += sunDirection * lightStep; // 朝太阳走远一点。
                lightStep *= 2.8; // 三步覆盖近树、石门与远处树线。
            }
            visibility /= 3.0;
            terrainVisibility /= 3.0;
            float extinction = exp(-density * stepLength); // 这一步的透过率。
            visibilitySum += terrainVisibility * (1.0 - extinction); // 开发检查：按散射权重累计地形阴影。
            visibilityWeight += 1.0 - extinction; // 开发检查：累计权重。
            // 太阳散射：阴影决定光柱，相位决定逆光亮度；强度按步长与剩余透过率积分。
            vec3 sunLight = sunChroma * (uSunIrradiance * uFogScatter * phase * visibility * 0.055);
            vec3 ambient = skyAmbient * mix(0.25, 1.0, clamp(position.y / 80.0, 0.0, 1.0)); // 低处天光被地面挡掉一部分。
            scattered += (sunLight + ambient) * (transmittance * (1.0 - extinction)); // 体积散射积分。
            transmittance *= extinction;
        }
        if (transmittance < 0.01) break; // 几乎不透明。
    }
    if (uFogDebug == 1) // 开发检查：看阴影在雾里的分布。
    {
        float visibility = visibilityWeight > 1.0e-4 ? visibilitySum / visibilityWeight : 1.0;
        fragColor = vec4(vec3(visibility), 1.0);
        return;
    }
    if (uFogDebug == 2) // 开发检查：只看雾散射，检查光柱是否被地表颜色淹没。
    {
        fragColor = vec4(scattered, 1.0);
        return;
    }
    fragColor = vec4(color * transmittance + scattered, 1.0); // 雾合成。
}
