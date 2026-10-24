#version 330 core
// 泛光阶段：一次亮度筛选与两次降采样、一次升采样，构成两级光晕。
// 调用位置：时间抗锯齿之后、后期曝光之前；三种模式由调用方用 `uMode` 选择。
// 设计原因与取舍：测试世界只做两级、四分之一分辨率，足以让太阳与云边出现柔和光晕，
// 又不至于在集成显卡上多花几毫秒；核函数来自生成的后期模块，与光影包里的泛光同源。
#include "world_shared.glsl"

uniform sampler2D uSource; // 本帧来源：模式零读抗锯齿结果，其他模式读上一级泛光。
uniform sampler2D uSmall; // 更小一级的泛光，升采样时用。
uniform vec2 uResolution; // 本阶段目标尺寸。
uniform vec2 uSourceResolution; // 来源图尺寸。
uniform int uMode; // 零为亮度筛选加降采样，一为降采样，二为升采样合并。
uniform float uThreshold; // 亮度阈值，低于它的像素不产生光晕。

out vec4 fragColor; // 泛光结果。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 本阶段坐标。
    vec2 texel = 1.0 / uSourceResolution; // 来源图一个纹素的大小。
    if (uMode == 0) // 亮度筛选后降采样。
    {
        vec3 source = texture(uSource, uv).rgb; // 中心像素。
        float luminance = ogxLuminance(source); // 亮度。
        float weight = smoothstep(uThreshold, uThreshold * 2.0 + 0.2, luminance); // 只有亮部才可见。
        fragColor = vec4(ogxBloomDownsample(uSource, uv, texel) * weight, 1.0); // 十三样本降采样。
    }
    else if (uMode == 1) // 继续降采样。
    {
        fragColor = vec4(ogxBloomDownsample(uSource, uv, texel), 1.0);
    }
    else // 升采样并与本级的较粗结果相加。
    {
        vec4 coarse = ogxBloomBicubic(uSmall, uv, 1.0 / uResolution); // 从更小一级三次升采样。
        vec3 local = texture(uSource, uv).rgb; // 本级已有的光晕，和上面同一套曲线编码。
        fragColor = vec4(coarse.rgb + local, 1.0); // 相加得到更宽的光晕。
    }
}
