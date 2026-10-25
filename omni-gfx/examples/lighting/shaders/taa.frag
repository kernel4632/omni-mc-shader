#version 330 core
// 时间抗锯齿：次像素抖动、世界位置重投影、邻域方差裁剪，把云、雾和阴影的颗粒抹平。
// 调用位置：体积雾之后、泛光与色调映射之前。
// 设计原因与取舍：
//   场景相机在截图模式下静止，历史帧的采样点落在像素内不同位置，多帧叠加就能消除锯齿；
//   移动时按世界位置重投影，三乘三邻域方差把历史夹回当前范围，转身不会拖影。
//   云与雾已经各自累积过一轮，这里只处理几何边缘与残余噪点，混合权重可以低一些。
#include "common.glsl"

uniform sampler2D uCurrent; // 本帧雾合成后的颜色。
uniform sampler2D uHistory; // 上一帧结果。
uniform sampler2D uDepth; // 本帧深度。
uniform vec2 uResolution; // 完整画面尺寸。
uniform mat4 uProjectionInverse; // 逆投影。
uniform mat4 uPreviousViewProjection; // 上一帧视图投影。
uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uRight; // 相机右方向。
uniform vec3 uUp; // 相机上方向。
uniform vec3 uForward; // 相机前方向。
uniform float uBlend; // 本帧权重。
uniform float uFar; // 远平面。
uniform vec2 uJitter; // 本帧次像素抖动。

out vec4 fragColor; // 抗锯齿后的颜色。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 本帧深度。
    vec3 viewPos = ogxGiViewPos(uv - uJitter, depth, uProjectionInverse); // 还原视空间位置。
    vec3 worldPos = uCameraPos + uRight * viewPos.x + uUp * viewPos.y - uForward * viewPos.z; // 换回世界位置。
    vec4 previousClip = uPreviousViewProjection * vec4(worldPos, 1.0); // 上一帧裁剪空间。
    vec2 previousUv = previousClip.xy / max(previousClip.w, 1e-5) * 0.5 + 0.5; // 上一帧屏幕坐标。
    vec2 velocity = uv - previousUv; // 本帧相对上一帧的位移。
    velocity = clamp(velocity, vec2(-0.2), vec2(0.2)); // 限制单帧位移。
    float reference; // 参考深度；本场景不使用打包深度。
    vec4 reprojected = ogxTaaReproject(uv, vec3(velocity, 0.0), depth, uCurrent, uHistory, uResolution,
                                       ivec2(gl_FragCoord.xy), uProjectionInverse, uFar, vec2(0.0), uBlend,
                                       0.6, 6e-4, false, false, true, false, false, false, reference); // 库的重投影与裁剪。
    vec3 color = reprojected.rgb; // 重投影后的颜色。
    if (depth >= 0.999) // 天空已经由云累积平滑过，避免邻域方差放大云的高频。
    {
        color = texture(uCurrent, uv).rgb; // 直接用本帧天空。
    }
    fragColor = vec4(color, 1.0); // 写入历史缓冲。
}
