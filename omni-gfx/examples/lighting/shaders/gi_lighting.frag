#version 330 core
// 屏幕空间全局光阶段：水平线环境光遮蔽、接触阴影与邻域颜色反弹，半分辨率计算。
// 调用位置：不透明场景与平面反射之后、合成与水面之前。
// 设计原因与取舍：
//   环境光只压暗暗部天光，接触阴影只压暗直射光，两者分开存，合成时不会把影子压成灰块。
//   颜色反弹取邻域表面反照率，给球体底部和石台侧面带上草地或暖方块的色偏；
//   这是屏幕空间近似，看不到镜头外的物体，但能把“暗部发灰”压回有颜色的阴影。
//   半分辨率加时间累积；边缘靠四邻域深度权重升采样，不会出现半分辨率的方块。
#include "common.glsl"

uniform sampler2D uDepth; // 不透明场景深度。
uniform sampler2D uNormalDepth; // 法线与距离。
uniform sampler2D uAlbedoRough; // 场景反照率与粗糙度。
uniform sampler2D uHistoryAo; // 上一帧的遮蔽与接触阴影。
uniform sampler2D uHistoryBounce; // 上一帧的颜色反弹。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec2 uFullResolution; // 完整画面尺寸。
uniform mat4 uProjection; // 本帧投影。
uniform mat4 uProjectionInverse; // 本帧逆投影。
uniform mat4 uPreviousViewProjection; // 上一帧视图投影，用于重投影。
uniform vec3 uForward; // 相机前方向。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform vec2 uJitter; // 本帧次像素抖动，纹理坐标单位。
uniform float uBlend; // 本帧权重。
uniform float uAoStrength; // 遮蔽强度。
uniform float uContactStrength; // 接触阴影强度。

layout(location = 0) out vec4 outAoContact; // 红是环境光遮蔽，绿是接触阴影。
layout(location = 1) out vec4 outBounce; // 邻域颜色反弹。

// 把屏幕深度换成视空间位置；`uv` 是不含抖动的采样坐标。
vec3 viewPosition(vec2 uv, float depth) // 返回视空间坐标，z 为负。
{
    return ogxGiViewPos(uv, depth, uProjectionInverse); // 库的逆投影还原。
}

// 把视空间位置投影到屏幕；返回 uv 与是否在画面内。
vec3 projectView(vec3 position, out bool valid) // 返回屏幕坐标与视深度。
{
    vec4 clip = uProjection * vec4(position, 1.0); // 裁剪空间。
    valid = clip.w > 0.0; // 相机后方的点不可用。
    return vec3(clip.xy / max(clip.w, 1e-5) * 0.5 + 0.5, position.z); // 屏幕坐标与视深度。
}

// 半球采样方向：用黄金角把样本铺开，再按法线建立切线基。
vec3 hemisphereDirection(vec3 normal, float index, float count, float rotation) // 返回单位方向。
{
    float angle = index * 2.399963229728653 + rotation; // 黄金角。
    float radius = sqrt((index + 0.5) / count); // 圆面均匀。
    vec3 tangent = normalize(cross(normal, abs(normal.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0))); // 切线。
    vec3 bitangent = cross(normal, tangent); // 副切线。
    vec3 direction = tangent * (cos(angle) * radius) + bitangent * (sin(angle) * radius)
                   + normal * sqrt(max(1.0 - radius * radius, 0.0)); // 余弦加权半球。
    return normalize(direction); // 单位方向。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 半分辨率坐标。
    float depth = texture(uDepth, uv).r; // 屏幕深度。
    if (depth >= 0.9999) // 天空没有遮蔽。
    {
        outAoContact = vec4(1.0, 1.0, 0.0, 1.0); // 完全受光。
        outBounce = vec4(0.0, 0.0, 0.0, 1.0); // 没有反弹。
        return;
    }
    vec4 normalDepth = texture(uNormalDepth, uv); // 法线与距离。
    vec3 normal = ogxDecodeNormal(normalDepth.xy); // 世界法线。
    vec3 viewPos = viewPosition(uv, depth); // 视空间位置。
    vec3 worldPos = uCameraPosition + uRight * viewPos.x + uUp * viewPos.y - uForward * viewPos.z; // 世界位置。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    float rotation = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)).x * 6.28318530718 + uFrame * 2.399963229728653; // 逐像素逐帧旋转。
    // 环境光遮蔽：十二个半球样本，半径一米二；只统计真正挡在天光方向上的近处几何。
    float occlusion = 0.0; // 遮挡计数。
    for (int i = 0; i < 8; i++) // 八个样本对半分辨率足够。
    {
        vec3 direction = hemisphereDirection(normal, float(i), 8.0, rotation); // 半球方向。
        vec3 samplePos = viewPos + direction * (0.85 + 0.65 * fract(float(i) * 0.618)); // 半径在一米二附近抖动。
        bool valid; // 投影是否有效。
        vec3 projected = projectView(samplePos, valid); // 投到屏幕。
        if (!valid || projected.x < 0.0 || projected.x > 1.0 || projected.y < 0.0 || projected.y > 1.0) // 出屏跳过。
        {
            continue; // 不产生遮挡。
        }
        float sampleDepth = texture(uDepth, projected.xy).r; // 样本位置的场景深度。
        vec3 scenePos = viewPosition(projected.xy, sampleDepth); // 场景在那里的视空间位置。
        float bias = 0.025; // 自遮挡偏置。
        if (scenePos.z > samplePos.z + bias) // 场景更靠近相机，说明样本点在几何后面。
        {
            float range = smoothstep(0.0, 1.0, 1.0 - length(samplePos - viewPos) / 1.8); // 远处样本权重递减。
            occlusion += range; // 累加遮挡。
        }
    }
    float ao = 1.0 - min(occlusion / 8.0 * 1.6, 0.92) * uAoStrength; // 换成零到一遮蔽。
    ao = clamp(ao, 0.05, 1.0); // 不压到纯黑，阴影里仍保留天光。
    // 接触阴影：沿太阳方向在屏幕上短距离步进，专门抓球与地面、方块与地面之间的窄缝。
    float contact = 1.0; // 默认没有接触遮挡。
    float NdotL = dot(normal, sunDirection); // 表面朝太阳程度。
    if (NdotL > 0.05) // 背光面不需要接触阴影。
    {
        vec3 sunView = vec3(dot(sunDirection, uRight), dot(sunDirection, uUp), -dot(sunDirection, uForward)); // 太阳的视空间方向。
        float blocked = 0.0; // 遮挡权重。
        for (int i = 1; i <= 6; i++) // 六步，覆盖约一米二。
        {
            float distance = 0.045 * float(i) * float(i) / 10.0 + 0.04 * float(i); // 近处密、远处疏。
            vec3 samplePos = viewPos + sunView * distance; // 沿阳光前进。
            bool valid; // 投影是否有效。
            vec3 projected = projectView(samplePos, valid); // 投到屏幕。
            if (!valid || projected.x < 0.0 || projected.x > 1.0 || projected.y < 0.0 || projected.y > 1.0) // 出屏。
            {
                break; // 后面的样本只会更远。
            }
            float sampleDepth = texture(uDepth, projected.xy).r; // 场景深度。
            vec3 scenePos = viewPosition(projected.xy, sampleDepth); // 场景视位置。
            if (scenePos.z > samplePos.z + 0.015) // 有几何挡住阳光。
            {
                blocked += (1.0 - float(i) / 12.0); // 近处遮挡权重更高。
            }
        }
        contact = 1.0 - min(blocked * 0.55, 0.85) * uContactStrength; // 换成可见度。
        contact = clamp(contact, 0.05, 1.0); // 保留一点天光。
    }
    // 颜色反弹：邻域反照率按深度相似度加权平均，给缝隙和物体底部带上周围颜色。
    vec3 bounce = vec3(0.0); // 反弹颜色。
    float bounceWeight = 0.0; // 权重和。
    for (int i = 0; i < 6; i++) // 六个屏幕样本。
    {
        float angle = float(i) * 2.399963229728653 + rotation * 0.7; // 螺旋角。
        vec2 offset = vec2(cos(angle), sin(angle)) * (8.0 + 14.0 * fract(float(i) * 0.618)) / uResolution; // 八到二十二像素。
        vec2 sampleUv = uv + offset; // 邻域坐标。
        if (sampleUv.x < 0.0 || sampleUv.x > 1.0 || sampleUv.y < 0.0 || sampleUv.y > 1.0) // 出屏。
        {
            continue; // 跳过。
        }
        float sampleDepth = texture(uDepth, sampleUv).r; // 邻域深度。
        if (sampleDepth >= 0.9999) // 天空不反弹颜色。
        {
            continue; // 跳过。
        }
        vec3 sampleNormal = ogxDecodeNormal(texture(uNormalDepth, sampleUv).xy); // 邻域法线。
        float depthWeight = 1.0 / (1.0 + abs(sampleDepth - depth) * 3000.0); // 深度越接近权重越大。
        float facing = 0.35 + 0.65 * max(dot(normal, sampleNormal), 0.0); // 朝向相近的表面更容易互相照亮。
        vec3 sampleAlbedo = texture(uAlbedoRough, sampleUv).rgb; // 邻域反照率。
        bounce += sampleAlbedo * (depthWeight * facing); // 加权累加。
        bounceWeight += depthWeight * facing; // 累加权重。
    }
    bounce /= max(bounceWeight, 1e-4); // 归一化。
    // 时间累积：按世界位置重投影上一帧，静态画面几帧就收敛，移动时也不会拖出长条。
    vec4 previousClip = uPreviousViewProjection * vec4(worldPos, 1.0); // 上一帧裁剪空间。
    vec2 previousUv = previousClip.xy / max(previousClip.w, 1e-4) * 0.5 + 0.5; // 上一帧屏幕坐标。
    bool historyValid = previousClip.w > 0.0 && previousUv.x > 0.0 && previousUv.x < 1.0 && previousUv.y > 0.0 && previousUv.y < 1.0; // 历史是否可用。
    if (historyValid) // 有有效历史。
    {
        vec4 previousAo = texture(uHistoryAo, previousUv); // 上一帧遮蔽。
        vec3 previousBounce = texture(uHistoryBounce, previousUv).rgb; // 上一帧反弹。
        ao = mix(previousAo.r, ao, uBlend); // 指数累积。
        contact = mix(previousAo.g, contact, uBlend); // 接触阴影累积。
        bounce = mix(previousBounce, bounce, uBlend); // 反弹累积。
    }
    outAoContact = vec4(ao, contact, 0.0, 1.0); // 两张遮蔽。
    outBounce = vec4(bounce, 1.0); // 反弹颜色。
}
