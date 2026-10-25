#version 330 core
// 云纹理模糊：对半分辨率体积云做一次可分离高斯，去掉步进颗粒与锯齿边。
// 调用位置：体积云步进之后、天空合成之前；先横向再纵向各画一次。
// 设计原因与取舍：云本身是软介质，模糊不会损失结构，却能把半分辨率采样与细节噪声藏起来；
// 五行高斯核只用九次采样，成本远低于把云步进改到全分辨率。
#include "/omni-gfx/math.glsl"

uniform sampler2D uSource; // 来源云纹理，rgb 预乘颜色，a 覆盖率。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec2 uDirection; // 一个纹素的方向：横向或纵向。

out vec4 fragColor; // 模糊后的云。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素坐标。
    vec2 stepUv = uDirection / uResolution; // 一个纹素的步长。
    // 五点高斯权重，和为一点零；两次分离模糊得到二维高斯。
    vec4 color = texture(uSource, uv) * 0.2270270270; // 中心。
    color += texture(uSource, uv + stepUv) * 0.1945945946; // 正一。
    color += texture(uSource, uv - stepUv) * 0.1945945946; // 负一。
    color += texture(uSource, uv + stepUv * 2.0) * 0.1216216216; // 正二。
    color += texture(uSource, uv - stepUv * 2.0) * 0.1216216216; // 负二。
    color += texture(uSource, uv + stepUv * 3.0) * 0.0540540541; // 正三。
    color += texture(uSource, uv - stepUv * 3.0) * 0.0540540541; // 负三。
    color += texture(uSource, uv + stepUv * 4.0) * 0.0162162162; // 正四。
    color += texture(uSource, uv - stepUv * 4.0) * 0.0162162162; // 负四。
    fragColor = color; // 模糊后的预乘云。
}
