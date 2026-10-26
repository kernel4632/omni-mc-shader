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
    float average = max(exp2(averageLog), 1e-5); // 平均亮度。
    // iterationT 的 AE_CURVE 是 0.7：曝光随场景亮度按负零点七次方变化，
    // 不是一比一抵消，所以亮场景仍然更亮、暗场景仍然更暗，画面不会总是被拉成同一块灰。
    float exposure = uExposureKey * pow(average / uExposureKey, -0.7);
    exposure = clamp(exposure, 0.02, 64.0); // 限制极端场景的曝光倍率。
    color *= exposure; // 应用曝光。
    color *= ogxVignette(uv, 0.40, 0.0, uAspect); // iterationT 的暗角：衰减 0.4，圆度零。
    vec3 mapped; // 压缩后的显示颜色。
    if (uTonemap == 0) // AgX，默认曲线。
    {
        mapped = ogxAgx(color, 13.0, true); // AGX_EV 13，与 iterationT 默认相同。
        mapped = ogxLinearToGamma2(mapped); // 转显示伽马二点二。
    }
    else if (uTonemap == 1) // ACES，影院标准对照。
    {
        mapped = ogxAces(color, true); // 曲线自带伽马。
    }
    else // 无压缩，只做伽马；用于检查高光是否被曲线改变色相。
    {
        mapped = ogxTonemapNone(color); // 直接伽马。
    }
    mapped = clamp(mapped, 0.0, 1.0); // 显示范围。
    float dither = (ogxBayer64(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)) - 0.5) / 255.0; // 每帧变化的抖动，打散色带。
    fragColor = vec4(clamp(mapped + dither, 0.0, 1.0), 1.0); // 写屏幕。
}
