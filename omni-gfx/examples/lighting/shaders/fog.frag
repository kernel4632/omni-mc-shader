#version 330 core
// 体积雾阶段：沿视线步进高度雾，并用阴影贴图生成真实光柱。
// 调用位置：水面合成之后、时间抗锯齿之前；读取水面目标颜色与深度。
// 设计原因与取舍：
//   密度、步数、相位、太阳取样步长与天光比例全部与 iterationT 的 体积雾 相同：
//   雾层中心放在海平面附近（Minecraft 的 50 到 65 格），而不是从头到脚铺一层白纱；
//   六个指数分布步把预算集中在水面与光柱上，远景交给大气表。
//   每个雾点只查一次阴影贴图，和 iterationT 一样靠抖动与时间抗锯齿抹平边缘。
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
uniform float uFogDensity; // 雾密度倍率；一对应 iterationT 的 体积雾_DENSITY 0.01。
uniform float uFogHeight; // 兼容旧参数；当前雾层高度由水面自动推算。
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

// 雾密度：iterationT 的 体积雾_NOISE_TYPE 0 高度剖面，只保留一层平滑雾气。
// 高度上下限从海平面换算：Minecraft 海平面是 63 格，雾层是 50 到 65 格，
// 所以在本场景（水面为零）就是水面以下十三米到以上两米。
float fogDensity(vec3 position) // 返回每米消光系数。
{
    float maxHeight = uWaterLevel + 2.0; // 雾层上限，对应 Minecraft 的 65 格。
    float minHeight = uWaterLevel - 13.0; // 雾层下限，对应 Minecraft 的 50 格。
    float dh = max(position.y - maxHeight, 0.0) + max(minHeight - position.y, 0.0); // 到雾层的距离。
    dh *= 2.0 / 40.0; // 体积雾_FALLOFF 40，换算成指数衰减。
    return exp2(-dh) * 0.1; // 雾层内密度为 0.1，再乘 体积雾_DENSITY。
}

// 单次散射相位：iterationT 的 FogPhase，前向瓣与宽瓣按三比七混合。
float fogPhase(float vdotl) // 返回相函数值。
{
    return ogxMiePhase(-0.4, vdotl) * 0.3 + ogxMiePhase(0.5, vdotl) * 0.7; // 两个方向瓣相加。
}

// 粉末效应：逆光看雾时，正面吸收更强，光柱边缘出现亮边。
float fogPowder(float absorption, float lightingAbsorption, float vdotl) // 返回零到一权重。
{
    return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, vdotl * 0.5 + 0.5); // 与 iterationT 相同。
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
    float maxDistance = min(distance, 900.0); // 只积到九百米，更远交给大气表。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunLight = lightingSunLight(); // 完整太阳辐照度。
    vec3 skyLight = lightingSunSkyLight(); // 天空辐照度。
    float jitter = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x; // 起点抖动。
    float vdotl = dot(direction, sunDirection); // 视线与太阳的夹角。
    vec3 scattered = vec3(0.0); // 累积散射。
    float visibilitySum = 0.0; // 开发检查用的可见度加权和。
    float visibilityWeight = 0.0; // 开发检查用的权重和。
    float transmittance = 1.0; // 剩余透过率。
    float fogAmount = 0.0; // 累积的雾量，最终乘天光。
    float rayAmount = 0.0; // 累积的太阳散射。
    const int steps = 6; // 与 iterationT 的 体积雾_QUALITY 相同。
    float rSteps = 1.0 / float(steps); // 步数倒数。
    // iterationT 的指数步长：pow(11, u) 把近处样本排得很密，远处只需几步。
    float rayLength = maxDistance * rSteps * 0.23979; // 每步对应的基础光学长度。
    float baseDensity = 0.05 / 12000.0; // 体积雾_DENSITY_BASE 1 除以远平面，给整条视线一点薄雾。
    for (int i = 0; i < steps; i++)
    {
        float u = (float(i) + jitter) * rSteps; // 当前步的归一化位置。
        float exponential = pow(11.0, u); // 指数分布。
        float stepLength = exponential * 0.1 - 0.1; // 这一段的起点比例。
        float stepDensity = exponential * rayLength * 1.442695; // 这一段的光学厚度尺度。
        float positionT = max(stepLength, 0.0); // 防止首步为负。
        vec3 position = uCameraPosition + direction * (maxDistance * positionT); // 当前雾点。
        float density = (fogDensity(position) * uFogDensity + baseDensity); // 当地密度。
        float absorption = exp2(-density * stepDensity); // 这一段的透过率。
        if (absorption < 0.99999) // 只有有雾的步才查阴影。
        {
            // 太阳方向的四次密度取样：与 iterationT 相同的五米起步、每步乘一点五。
            float lightingDensity = 0.0; // 太阳方向累积密度。
            float lightingStep = 5.0; // 起始步长，米。
            vec3 lightPosition = position; // 从当前雾点出发。
            for (int j = 0; j < 4; j++)
            {
                lightingDensity += fogDensity(lightPosition) * lightingStep; // 累加密度乘距离。
                lightPosition += sunDirection * lightingStep; // 朝太阳前进。
                lightingStep *= 1.5; // 远处步长更大。
            }
            lightingDensity = (lightingDensity * uFogDensity + baseDensity); // 乘密度倍率。
            float lightingAbsorption = exp2(-lightingDensity * stepDensity); // 太阳方向的透过率。
            // 四阶多次散射相位：相位角逐次减半，权重也减半，与 iterationT 相同。
            float phases = 0.0; // 相位和。
            float order = 1.0; // 当前阶权重。
            float phaseCos = vdotl; // 当前阶的夹角。
            for (int j = 0; j < 4; j++)
            {
                phases += exp(-lightingDensity * order) * fogPhase(phaseCos) * order; // 累加各阶相位。
                phaseCos *= 0.5; // 角度减半。
                order *= 0.5; // 权重减半。
            }
            phases *= fogPowder(absorption, lightingAbsorption, vdotl); // 逆光粉末效应。
            float dither = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy) + ivec2(i * 37 + 11, i * 17 + 5)).x; // 每步抖动。
            float shadow = lightingShadowCheap(position, vec3(0.0, 1.0, 0.0), distance, dither); // 太阳可见度。
            float integral = transmittance - absorption * transmittance; // 这一段的散射权重。
            rayAmount += phases * integral * shadow; // 太阳散射累积。
            fogAmount += integral; // 雾量累积。
            visibilitySum += shadow * integral; // 开发检查。
            visibilityWeight += integral; // 开发检查。
            transmittance *= absorption; // 更新透过率。
            if (transmittance < 0.01) break; // 几乎不透明。
        }
        else
        {
            transmittance *= absorption; // 没有雾也要更新透过率。
        }
    }
    if (uFogDebug == 1) // 开发检查：看阴影在雾里的分布。
    {
        float visibility = visibilityWeight > 1.0e-4 ? visibilitySum / visibilityWeight : 1.0;
        fragColor = vec4(vec3(visibility), 1.0);
        return;
    }
    // 雾的颜色：天光乘雾量，太阳色乘相位散射；比例与 iterationT 的 0.32 与 0.7 相同。
    vec3 fogColor = skyLight * (fogAmount * 0.32 * uFogAmbient);
    vec3 rayColor = sunLight * (rayAmount * 0.7 * uFogScatter);
    if (uFogDebug == 2) // 开发检查：只看雾散射。
    {
        fragColor = vec4(fogColor + rayColor, 1.0);
        return;
    }
    fragColor = vec4(color * transmittance + fogColor + rayColor, 1.0); // 雾合成。
}
