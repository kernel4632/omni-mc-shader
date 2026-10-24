// 测试世界的云层：在固定高度区间内步进，用分形噪声生成密度，再做一次朝太阳的短步进。
// 调用位置：天空着色器的主光线与立方体贴图的六个面都调用 `skyRadiance`。
// 设计原因与取舍：单层云、单次散射、固定步数，牺牲物理精度换取可测的帧时；
// 云层只在地平线以上绘制，避免向地下步进浪费采样。
#include "noise.glsl"
#include "atmosphere.glsl"

uniform float uTime;  // 场景时间，用来推动云的风速。
uniform float uCloudCover;  // 云量，零到一，越大云越厚。
uniform vec3 uCameraPos;  // 相机位置，决定云层视差。

// 云的密度：平面低频形状加高频细节，再按高度做上下淡出。
float cloudDensity(vec3 position)
{
    vec3 wind = vec3(uTime * 1.6, 0.0, uTime * 0.55);  // 云随风缓慢移动。
    vec2 p = position.xz + wind.xz;  // 只采样平面坐标，省掉一半哈希。
    float shape = fbm2(p * 0.006, 3);  // 大尺度云团。
    float detail = fbm2(p * 0.025 + vec2(11.0, 7.0), 2);  // 小尺度边缘。
    float vertical = smoothstep(120.0, 145.0, position.y) * smoothstep(185.0, 160.0, position.y);  // 云层上下淡出。
    float density = shape * 0.80 + detail * 0.20 - (0.60 - uCloudCover * 0.14);  // 覆盖阈值控制云量。
    return max(density, 0.0) * 4.5 * vertical;  // 放大到便于吸收计算的量级。
}

// 朝太阳方向做三次短步进，估计云内部的透光程度。
float cloudLight(vec3 position)
{
    float density = 0.0;  // 累计挡光的密度。
    vec3 stepDirection = normalize(uSunDirection) * 3.5;  // 每次向太阳靠近三点五米。
    for (int i = 1; i <= 2; i++)  // 固定两次，步数少但足以拉开亮暗。
    {
        density += cloudDensity(position + stepDirection * float(i));  // 累加路径上的云。
    }
    return exp(-density * 0.45);  // 比尔-朗伯透射率。
}

// 在云层高度区间内步进，返回带云的前景颜色与覆盖率。
vec4 marchClouds(vec3 origin, vec3 direction, float jitter)
{
    float bottom = 120.0;  // 云底高度。
    float top = 185.0;  // 云顶高度。
    if (abs(direction.y) < 0.015)  // 近乎水平的光线不进入云层，直接跳过。
    {
        return vec4(0.0);
    }
    float t0 = (bottom - origin.y) / direction.y;  // 与云底的交点距离。
    float t1 = (top - origin.y) / direction.y;  // 与云顶的交点距离。
    float nearDistance = max(min(t0, t1), 0.0);  // 取进入云层的距离。
    float farDistance = max(t0, t1);  // 取离开云层的距离。
    if (farDistance <= nearDistance || nearDistance > 6000.0)  // 相机在云层上方或云层不可见。
    {
        return vec4(0.0);
    }
    farDistance = min(farDistance, 6000.0);  // 远处云淡出，避免无限步进。
    const int STEPS = 14;  // 主光线步数，固定值便于比较性能。
    float stepLength = (farDistance - nearDistance) / float(STEPS);  // 每步长度。
    float distanceAlongRay = nearDistance + stepLength * jitter;  // 抖动起点，减轻层状条纹。
    float transmittance = 1.0;  // 还剩多少背景光能穿过。
    vec3 scattered = vec3(0.0);  // 云散射出的颜色。
    for (int i = 0; i < STEPS; i++)  // 固定步数的主循环。
    {
        vec3 position = origin + direction * distanceAlongRay;  // 当前采样点。
        float density = cloudDensity(position);  // 当前密度。
        if (density > 0.001)  // 空区域跳过光照步进。
        {
            float light = cloudLight(position);  // 朝太阳的透射率。
            float powder = 1.0 - exp(-density * 2.0);  // 边缘更亮的粉末效应。
            vec3 ambient = vec3(0.16, 0.20, 0.30) * 0.42;  // 天顶环境光。
            vec3 lit = sunColor() * light * (0.40 + 0.60 * powder) * 2.0 + ambient;  // 太阳光加环境光。
            float extinction = exp(-density * stepLength * 0.045);  // 本段云的吸收。
            scattered += lit * transmittance * (1.0 - extinction);  // 按剩余透射率累加。
            transmittance *= extinction;  // 更新剩余透射率。
        }
        distanceAlongRay += stepLength;  // 前进一段。
        if (transmittance < 0.02)  // 已经完全不透明，提前结束。
        {
            break;
        }
    }
    float alpha = (1.0 - transmittance) * smoothstep(0.04, 0.30, direction.y);  // 云的覆盖率，地平线附近淡出。
    vec3 color = scattered / max(alpha, 1e-4);  // 预乘颜色还原成普通颜色。
    return vec4(color, alpha);  // 供天空合成。
}

// 完整天空：先取大气底色，再叠上云层。
vec3 skyRadiance(vec3 direction, float jitter)
{
    vec3 background = skyBase(direction);  // 无云天空。
    vec4 clouds = marchClouds(uCameraPos, direction, jitter);  // 相机高度近似固定为七十米。
    return mix(background, clouds.rgb, clouds.a);  // 按覆盖率合成。
}
