#version 330 core
// 全局光阶段：半分辨率地平线遮蔽、多弹射补偿与历史累积。
// 调用位置：水面合成之后、时间抗锯齿之前；结果在后期阶段乘到场景颜色上。
// 设计原因与取舍：遮蔽在半分辨率算，四片切片乘五步只要二十次深度采样，四分之一的像素
// 让这笔开销对集成显卡友好；本帧与历史按固定权重混合，配合后续时间抗锯齿把噪点抹平。
// 为什么用线性深度而不是屏幕深度：地平线遮蔽要比较真实距离，屏幕深度在远处分辨率极低。
#include "world_shared.glsl"

uniform sampler2D uDepth; // 不透明场景深度。
uniform sampler2D uNormalDepth; // 场景法线与线性深度（法线编码在 xy）。
uniform sampler2D uColor; // 场景颜色，用作底色估计。
uniform sampler2D uHistory; // 上一帧的遮蔽结果。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec2 uFullResolution; // 完整画面尺寸。
uniform mat4 uProjection; // 近景投影。
uniform mat4 uProjectionInverse; // 近景逆投影，用来还原视空间位置。
uniform vec3 uForward; // 相机前方向。
uniform float uAspect; // 画面宽高比。
uniform float uFrame; // 帧号，给噪声换相位。
uniform float uBlend; // 本帧权重，越大收敛越快、噪点越多。

out vec4 fragColor; // 红通道是最终遮蔽系数。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 半分辨率坐标。
    float depth = texture(uDepth, uv).r; // 屏幕深度。
    vec4 normalDepth = texture(uNormalDepth, uv); // 法线与线性深度。
    if (depth >= 1.0) // 天空没有遮蔽。
    {
        fragColor = vec4(1.0);
        return;
    }
    vec3 normal = ogxDecodeNormal(normalDepth.xy); // 还原世界法线。
    vec3 viewPos = ogxGiViewPos(uv, depth, uProjectionInverse); // 还原视空间位置。
    vec3 viewDir = normalize(viewPos); // 从相机指向表面。
    OgxGtaoParams params; // 遮蔽参数。
    params.steps = 4.0; // 环绕视线的切片数。
    params.slice_steps = 5.0; // 每个切片的搜索步数。
    params.falloff_start = 0.5; // 衰减起点。
    params.max_sample_radius = 192.0; // 屏幕半径上限。
    params.world_radius = 2.6; // 世界半径，米。
    params.screen_radius = 22.0; // 屏幕半径。
    params.strength = 1.0; // 遮蔽强度。
    params.radius_mode = 0; // 世界半径模式，近处更细。
    params.has_dh = false; // 测试世界没有远景深度。
    params.dh_ao = false; // 远景不参与遮蔽。
    params.falloff_z_offset = false; // 按距离衰减。
    vec2 noise = vec2(ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)), ogxBayer4(gl_FragCoord.xy + vec2(uFrame * 0.13))); // 逐帧变化的抖动。
    float ao = ogxGroundTruthAo(viewPos, viewDir, normal, uv, uAspect, uDepth, uDepth, uProjection, uProjectionInverse,
                                uProjectionInverse, params, noise); // 地平线遮蔽。
    vec3 albedo = clamp(texture(uColor, uv).rgb, vec3(0.02), vec3(1.0)); // 用场景颜色估计底色。
    vec3 bounce = ogxAoMultiBounce(ao, albedo); // 多弹射补偿，避免墙角全黑。
    float result = clamp(bounce.g * 0.6 + bounce.r * 0.4, 0.0, 1.0); // 取亮度作为遮蔽系数。
    float history = texture(uHistory, uv).r; // 上一帧结果。
    result = mix(history, result, uBlend); // 时间累积。
    fragColor = vec4(result, result, result, 1.0); // 写入遮蔽。
}
