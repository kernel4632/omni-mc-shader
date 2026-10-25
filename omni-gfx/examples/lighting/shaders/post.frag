#version 330 core
// 后期阶段：曝光、泛光、AgX 色调映射、轻微冷暖分离与抖动，输出最终显示画面。
// 调用位置：每帧最后一步；读取抗锯齿颜色、泛光图与一个像素的曝光统计。
// 设计原因与取舍：
//   默认使用 AgX，高光滚降比 ACES 更缓，低阳天空与云不会先被切成白块；
//   调色只在显示空间做很轻的冷暖分离，不靠提高饱和度掩盖光照问题。
#include "common.glsl"

uniform sampler2D uColor; // 抗锯齿后的线性颜色。
uniform sampler2D uBloom; // 泛光图，线性。
uniform sampler2D uExposure; // 一个像素的平均对数亮度。
uniform vec2 uResolution; // 画面尺寸。
uniform float uExposureKey; // 目标中间亮度。
uniform int uTonemap; // 零 AgX，一 ACES，二无压缩。
uniform float uAspect; // 宽高比。
uniform float uBloomStrength; // 泛光强度。

out vec4 fragColor; // 最终显示颜色。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    vec3 color = texture(uColor, uv).rgb; // 线性场景颜色。
    color += texture(uBloom, uv).rgb * uBloomStrength; // 泛光与场景同为线性，直接相加。
    float averageLog = texture(uExposure, vec2(0.5)).r; // 几何画面平均对数亮度。
    float exposure = clamp(uExposureKey / max(exp2(averageLog), 1e-4), 0.02, 64.0); // 自动曝光倍率；不再用四倍上限，逆光场景也能提亮暗部。
    color *= exposure; // 应用曝光。
    color *= ogxVignette(uv, 0.42, 0.72, uAspect); // 轻微暗角，边缘只压两成。
    color = ogxFilmGrain(color, gl_FragCoord.xy, uTime, 0.0025); // 极轻颗粒，打散渐变色带。
    vec3 mapped; // 压缩后的显示颜色。
    if (uTonemap == 0) // AgX，默认曲线。
    {
        mapped = ogxAgx(color, 16.5, true); // 宽动态范围压缩。
        mapped = ogxLinearToGamma2(mapped); // 转显示伽马。
    }
    else if (uTonemap == 1) // ACES，影院标准对照。
    {
        mapped = ogxAces(color, true); // 曲线自带伽马。
    }
    else // 无压缩，只做伽马；用于检查高光是否被曲线改变色相。
    {
        mapped = ogxTonemapNone(color); // 直接伽马。
    }
    // 很轻的调色：保持饱和度接近原始，只在暗部加一点冷、高光加一点暖。
    float luma = ogxLuminance(mapped); // 显示亮度。
    mapped = mix(vec3(luma), mapped, 0.99); // 几乎不改变饱和度。
    mapped = (mapped - 0.5) * 1.02 + 0.5; // 极小对比，保留黑场。
    mapped += vec3(0.010, 0.004, -0.008) * (1.0 - luma); // 暗部略偏冷青。
    mapped += vec3(0.008, 0.004, -0.006) * luma; // 高光略偏暖。
    mapped = clamp(mapped, 0.0, 1.0); // 显示范围。
    float dither = (ogxBayer64(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)) - 0.5) / 255.0; // 每帧变化的抖动。
    fragColor = vec4(clamp(mapped + dither, 0.0, 1.0), 1.0); // 写屏幕。
}
