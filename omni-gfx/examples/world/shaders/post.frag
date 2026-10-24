#version 330 core
// 后期阶段：泛光叠加、自动曝光、暗角、颗粒与色调映射，把线性场景变成可保存的显示画面。
// 调用位置：测试世界每帧最后一步，读取抗锯齿后的颜色、泛光图与一个像素的曝光统计。
// 设计原因与取舍：曝光不再写死，避免太阳一侧的云和海面反光把整片画面推成死白；
// 泛光、暗角、颗粒与三条曲线都来自生成的通用库，测试世界不再自己复制这些公式。
#include "world_shared.glsl"

uniform sampler2D uColor; // 抗锯齿后的线性颜色。
uniform sampler2D uBloom; // 泛光图，曲线编码。
uniform sampler2D uExposure; // 一个像素的平均对数亮度。
uniform vec2 uResolution; // 画面尺寸。
uniform float uExposureKey; // 目标中间亮度，越大画面越亮。
uniform int uTonemap; // 零为 ACES，一为 AgX，二为无压缩。
uniform float uFrame; // 帧号，用于抖动。
uniform float uTime; // 场景时间，用于颗粒。
uniform float uAspect; // 画面宽高比。
uniform float uBloomStrength; // 泛光强度。

out vec4 fragColor; // 最终显示颜色。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 零到一的画面坐标。
    vec3 color = texture(uColor, uv).rgb; // 线性场景颜色。
    color += texture(uBloom, uv).rgb * uBloomStrength; // 泛光图与场景同为线性，直接相加。
    float averageLog = texture(uExposure, vec2(0.5)).r; // 整幅画面的平均对数亮度。
    // 曝光倍率把平均亮度拉到目标值，再夹进区间，避免极端画面忽明忽暗。
    float exposure = clamp(uExposureKey / max(exp2(averageLog), 1e-4), 0.18, 1.6);
    color *= exposure; // 应用曝光。
    color *= ogxVignette(uv, 0.42, 0.7, uAspect); // 轻微暗角，边缘只压三成。
    color = ogxFilmGrain(color, gl_FragCoord.xy, uTime, 0.004); // 极轻的颗粒，打散渐变色带。
    vec3 mapped; // 压缩后的显示颜色。
    if (uTonemap == 0) // 影院标准曲线，自带显示伽马。
    {
        mapped = ogxAces(color, true);
    }
    else if (uTonemap == 1) // 宽色域曲线，输出线性显示色，需要再编码。
    {
        mapped = ogxLinearToGamma2(ogxAgx(color, 13.0, true));
    }
    else // 无压缩，只做伽马。
    {
        mapped = ogxTonemapNone(color);
    }
    float dither = (ogxBayer64(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)) - 0.5) / 255.0; // 每帧变化的抖动。
    fragColor = vec4(clamp(mapped + dither, 0.0, 1.0), 1.0); // 写屏幕。
}
