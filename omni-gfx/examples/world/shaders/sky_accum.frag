#version 330 core
// 天空时间累积阶段（半分辨率）：把每帧带噪声的云样本按历史混合，得到平滑的云层。
// 调用位置：紧接天空采样阶段，结果写进另一张半分辨率缓冲，供合成阶段升采样。
// 设计原因与取舍：十二步的体积云必然有台阶，靠蓝噪声抖动把台阶换成颗粒，
// 再把颗粒在时间上平均掉；直接用长历史会拖出残影，所以先把历史夹到当前帧
// 三乘三邻域的范围里，云移动时最多保留颜色相近的部分。
// 相机移动时用上一帧的相机基向量重投影：天空在无限远，方向不变就等于像素不变。
#include "world_shared.glsl"

uniform sampler2D uCurrent; // 本帧刚算出的天空与云。
uniform sampler2D uHistory; // 上一帧累积结果。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec3 uForward; // 本帧相机前方向。
uniform vec3 uRight; // 本帧相机右方向。
uniform vec3 uUp; // 本帧相机上方向。
uniform float uTanHalfFov; // 本帧竖直视场角一半的正切。
uniform float uAspect; // 本帧画面宽高比。
uniform vec3 uPrevForward; // 上一帧相机前方向。
uniform vec3 uPrevRight; // 上一帧相机右方向。
uniform vec3 uPrevUp; // 上一帧相机上方向。
uniform float uPrevTanHalfFov; // 上一帧竖直视场角一半的正切。
uniform float uPrevAspect; // 上一帧画面宽高比。
uniform float uBlend; // 本帧样本的权重，越小历史越长。

out vec4 fragColor; // 累积后的天空颜色与覆盖率。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素在半分辨率画面里的坐标。
    vec2 texel = 1.0 / uResolution; // 一个像素的跨度。
    vec4 current = texture(uCurrent, uv); // 本帧样本。
    // 三乘三邻域的最小值与最大值：历史落在范围外说明云移动了，夹回来才不会拖影。
    vec4 minimum = current; // 邻域下限。
    vec4 maximum = current; // 邻域上限。
    for (int y = -1; y <= 1; y++) // 逐行扫描邻域。
    {
        for (int x = -1; x <= 1; x++)
        {
            vec4 sampleColor = texture(uCurrent, uv + vec2(float(x), float(y)) * texel); // 邻域样本。
            minimum = min(minimum, sampleColor); // 更新下限。
            maximum = max(maximum, sampleColor); // 更新上限。
        }
    }
    vec3 direction = worldRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 当前像素的世界方向。
    vec2 previousUv = vec2(-1.0); // 负坐标表示重投影落在画面外。
    float facing = dot(direction, uPrevForward); // 与上一帧视线中心的夹角余弦。
    if (facing > 0.05) // 太靠边缘的方向不重投影，避免除零和极端拉伸。
    {
        float x = dot(direction, uPrevRight) / (facing * uPrevTanHalfFov * uPrevAspect); // 上一帧的横向屏幕坐标。
        float y = dot(direction, uPrevUp) / (facing * uPrevTanHalfFov); // 上一帧的纵向屏幕坐标。
        previousUv = vec2(0.5 + 0.5 * x, 0.5 + 0.5 * y); // 负一到一换成零到一。
    }
    vec4 history = current; // 默认没有历史时直接用本帧样本。
    bool inside = all(greaterThanEqual(previousUv, vec2(0.0))) && all(lessThanEqual(previousUv, vec2(1.0))); // 是否落在上一帧画面内。
    if (inside) // 只有确实有对应像素才读历史。
    {
        history = texture(uHistory, previousUv); // 取上一帧累积结果。
        history = clamp(history, minimum, maximum); // 夹进邻域范围，抑制残影。
    }
    fragColor = mix(history, current, uBlend); // 按权重混合，静态场景下会收敛到多帧平均。
}
