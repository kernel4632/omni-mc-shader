#version 330 core
// 时间抗锯齿阶段：把本帧画面与历史按邻域范围与深度一致性混合，并乘上全局光遮蔽。
// 调用位置：水面合成之后、曝光统计之前。
// 设计原因与取舍：本帧画面里有抖动过的体积云、遮蔽与反射噪点，直接压成八位会留下细砂；
// 时间累积用三乘三邻域方差把历史裁进当前范围，移动物体不会拖出长长的残影。
// 位移按世界位置重投影得到：反解出视空间位置、换回世界、再用上一帧视图投影投一遍，
// 相机移动与转动都会得到正确的屏幕位移，静止机位下位移自然为零。
#include "world_shared.glsl"

uniform sampler2D uCurrent; // 本帧合成颜色。
uniform sampler2D uHistory; // 上一帧结果。
uniform sampler2D uDepth; // 本帧深度。
uniform sampler2D uAO; // 半分辨率遮蔽。
uniform vec2 uResolution; // 完整画面尺寸。
uniform vec2 uAOTexel; // 遮蔽图一个纹素的大小，保留供后续做双边升采样。
uniform mat4 uProjectionInverse; // 逆投影矩阵。
uniform mat4 uPreviousViewProjection; // 上一帧的视图投影矩阵，用来重投影。
uniform vec3 uCameraPos; // 本帧相机位置。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform vec3 uForward; // 相机前方向。
uniform float uBlend; // 本帧权重，越小越平滑。
uniform float uFar; // 远平面，用于深度阈值缩放。

out vec4 fragColor; // 抗锯齿后的颜色。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 本帧深度。
    vec3 viewPos = ogxGiViewPos(uv, depth, uProjectionInverse); // 还原视空间位置。
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
    else // 有几何的像素才乘遮蔽，遮蔽只在实体表面有意义。
    {
        float ao = clamp(texture(uAO, uv).r, 0.45, 1.0); // 对应位置的遮蔽，留一个下限。
        color *= ao; // 压暗暗部缝隙；水面不写深度，宁可少压一点也不压出黑块。
    }
    fragColor = vec4(color, 1.0); // 写到历史缓冲。
}
