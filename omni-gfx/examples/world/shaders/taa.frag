#version 330 core
// 时间抗锯齿阶段：次像素抖动 + 历史重投影 + 邻域裁剪，并叠加半分辨率环境光遮蔽。
// 调用位置：水面合成之后、曝光统计之前。
// 设计原因与取舍：
//   投影矩阵每帧抖动半个像素以内，历史帧的采样点因此落在像素内的不同位置，
//   静止画面叠十几帧就能把树线、草叶和云边的锯齿抹平；相机移动时用世界位置重投影，
//   三乘三邻域方差把历史裁进当前颜色范围，快速转向也不会拖影。
//   环境光遮蔽在半分辨率算，这里按深度做四邻域加权升采样，避免出现半分辨率的方块。
//   水面像素在颜色附件的透明通道写了零，遮蔽不作用在水面上，否则水会被地形遮蔽染黑。
#include "world_shared.glsl"

uniform sampler2D uCurrent; // 本帧合成颜色。
uniform sampler2D uHistory; // 上一帧结果。
uniform sampler2D uDepth; // 本帧深度。
uniform sampler2D uAO; // 半分辨率遮蔽。
uniform vec2 uResolution; // 完整画面尺寸。
uniform vec2 uAOTexel; // 遮蔽图一个纹素的大小。
uniform mat4 uProjectionInverse; // 逆投影矩阵。
uniform mat4 uPreviousViewProjection; // 上一帧的视图投影矩阵，用来重投影。
uniform vec3 uCameraPos; // 本帧相机位置。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform vec3 uForward; // 相机前方向。
uniform float uBlend; // 本帧权重，越小越平滑。
uniform float uFar; // 远平面，用于深度阈值缩放。
uniform vec2 uJitter; // 本帧次像素抖动，纹理坐标单位。

out vec4 fragColor; // 抗锯齿后的颜色。

// 四邻域加权升采样遮蔽：按深度差剔除跨越物体边界的邻居，边缘不会糊。
float upsampleAo(vec2 uv, float depth)
{
    vec2 offset = uAOTexel * 0.5; // 半分辨率半个纹素。
    float sum = 0.0; // 权重和。
    float total = 0.0; // 加权遮蔽和。
    for (int i = 0; i < 4; i++) // 四个对角邻居。
    {
        vec2 direction = vec2(i == 0 || i == 2 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0); // 四个方向。
        vec2 sampleUv = uv + direction * offset; // 邻居坐标。
        float sampleDepth = texture(uDepth, sampleUv).r; // 邻居的屏幕深度。
        float weight = 1.0 / (1.0 + abs(sampleDepth - depth) * 4000.0); // 深度差越小，权重越大。
        sum += weight; // 累加权重。
        total += texture(uAO, sampleUv).r * weight; // 累加遮蔽。
    }
    return total / max(sum, 1e-4); // 归一化。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 本帧深度。
    vec3 viewPos = ogxGiViewPos(uv - uJitter, depth, uProjectionInverse); // 还原视空间位置，减掉本帧抖动。
    vec3 worldPos = uCameraPos + uRight * viewPos.x + uUp * viewPos.y - uForward * viewPos.z; // 换回世界位置。
    vec4 previousClip = uPreviousViewProjection * vec4(worldPos, 1.0); // 上一帧裁剪空间坐标。
    vec2 previousUv = previousClip.xy / max(previousClip.w, 1e-5) * 0.5 + 0.5; // 上一帧屏幕坐标。
    vec2 velocity = uv - previousUv; // 本帧相对上一帧的位移。
    velocity = clamp(velocity, vec2(-0.2), vec2(0.2)); // 限制单帧位移，遮挡边缘不会拉出长条。
    float reference; // 参考深度，本测试世界不使用打包深度。
    vec4 reprojected = ogxTaaReproject(uv, vec3(velocity, 0.0), depth, uCurrent, uHistory, uResolution,
                                       ivec2(gl_FragCoord.xy), uProjectionInverse, uFar, vec2(0.0), uBlend,
                                       0.6, 6e-4, false, false, true, false, false, false, reference); // 时间重投影。
    vec3 color = reprojected.rgb; // 重投影后的颜色。
    if (depth >= 0.999) // 天空已经在前面的半分辨率累积里做过时间混合，这里直接用本帧结果。
    {
        color = texture(uCurrent, uv).rgb; // 避免邻域方差把云的高频抖动放大成颗粒。
    }
    else // 有几何的像素才乘遮蔽。
    {
        float ao = clamp(upsampleAo(uv, depth), 0.42, 1.0); // 对应位置的遮蔽，留一个下限。
        float isSurface = step(0.5, texture(uCurrent, uv).a); // 水面在透明通道写了零，不乘地形遮蔽。
        color *= mix(1.0, ao, isSurface); // 压暗暗部缝隙。
    }
    // 次像素抖动会让画面整体平移不到一像素，历史与当前因此不能直接平均到同一位置；
    // 重投影已经把世界点对齐，这里只需把采样坐标写回，不需要额外补偿。
    fragColor = vec4(color, 1.0); // 写到历史缓冲。
}
