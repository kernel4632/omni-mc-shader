#version 330 core
// 泛光阶段：亮度筛选、两级降采样与升采样合并，让太阳与云边有真实的镜头扩散。
// 调用位置：时间抗锯齿之后、曝光统计之前。
// 设计原因与取舍：泛光只取超过阈值的部分，草地与石台不会被整体提亮；
// 两级不同尺度的核让高光既有短而亮的芯，也有长而淡的晕，接近相机镜头而不是一团白雾。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/color.glsl"

uniform sampler2D uSource; // 当前来源。
uniform sampler2D uSmall; // 更粗一级的泛光。
uniform vec2 uResolution; // 当前目标尺寸。
uniform vec2 uSourceResolution; // 来源尺寸。
uniform int uMode; // 零筛选降采样，一继续降采样，二升采样合并。
uniform float uThreshold; // 高光阈值。

out vec4 fragColor; // 泛光颜色。

// 四点盒式取样，同时做一次亮度筛选；阈值以下的像素不进入泛光。
vec3 sampleBright(vec2 uv) // 返回筛选后的颜色。
{
    vec2 texel = 1.0 / uSourceResolution; // 来源纹素。
    vec3 color = texture(uSource, uv + texel * vec2(-0.5, -0.5)).rgb; // 左上。
    color += texture(uSource, uv + texel * vec2(0.5, -0.5)).rgb; // 右上。
    color += texture(uSource, uv + texel * vec2(-0.5, 0.5)).rgb; // 左下。
    color += texture(uSource, uv + texel * vec2(0.5, 0.5)).rgb; // 右下。
    color *= 0.25; // 平均。
    float luma = ogxLuminance(color); // 亮度。
    float weight = max(luma - uThreshold, 0.0) / max(luma, 1e-4); // 只保留超过阈值的部分。
    return color * weight; // 筛选后的高光。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前目标坐标。
    if (uMode == 0) // 第一级：从完整画面筛出高光。
    {
        fragColor = vec4(sampleBright(uv), 1.0); // 筛选后的高光。
    }
    else if (uMode == 1) // 第二级：从第一级继续降采样。
    {
        vec2 texel = 1.0 / uSourceResolution; // 来源纹素。
        vec3 color = texture(uSource, uv + texel * vec2(-1.0, -1.0)).rgb; // 四角平均。
        color += texture(uSource, uv + texel * vec2(1.0, -1.0)).rgb;
        color += texture(uSource, uv + texel * vec2(-1.0, 1.0)).rgb;
        color += texture(uSource, uv + texel * vec2(1.0, 1.0)).rgb;
        fragColor = vec4(color * 0.25, 1.0); // 更粗的一级。
    }
    else // 第三级：把粗一级升采样回来，与细一级相加。
    {
        vec2 texel = 1.0 / uSourceResolution; // 粗图纹素。
        vec3 small = texture(uSmall, uv + texel * vec2(-0.5, -0.5)).rgb;
        small += texture(uSmall, uv + texel * vec2(0.5, -0.5)).rgb;
        small += texture(uSmall, uv + texel * vec2(-0.5, 0.5)).rgb;
        small += texture(uSmall, uv + texel * vec2(0.5, 0.5)).rgb;
        small *= 0.25; // 双线性四采样平滑。
        vec3 fine = texture(uSource, uv).rgb; // 细一级。
        fragColor = vec4(fine + small * 0.65, 1.0); // 合并两级。
    }
}
