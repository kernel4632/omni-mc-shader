#version 330 core
// 云纹理模糊：对半分辨率体积云做一次可分离高斯，去掉步进颗粒与锯齿边。
// 调用位置：体积云步进之后、天空合成之前；先横向再纵向各画一次。
// 设计原因与取舍：云本身是软介质，模糊不会损失结构，却能把半分辨率采样与细节噪声藏起来；
// 核只覆盖两个纹素，边缘保持花椰菜的鼓包，不会把整朵云糊成棉花糖。
#include "/omni-gfx/common/math.glsl"

uniform sampler2D uSource; // 来源云纹理，rgb 预乘颜色，a 覆盖率。
uniform vec2 uResolution; // 半分辨率尺寸。
uniform vec2 uDirection; // 一个纹素的方向：横向或纵向。

out vec4 fragColor; // 模糊后的云。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素坐标。
    vec2 stepUv = uDirection / uResolution; // 一个纹素的步长。
    // 五点高斯权重，和为一点零；两次分离模糊得到二维高斯。
    vec4 color = texture(uSource, uv) * 0.402619; // 中心。
    color += texture(uSource, uv + stepUv) * 0.244201; // 正一。
    color += texture(uSource, uv - stepUv) * 0.244201; // 负一。
    color += texture(uSource, uv + stepUv * 2.0) * 0.054488; // 正二。
    color += texture(uSource, uv - stepUv * 2.0) * 0.054488; // 负二。
    fragColor = color; // 模糊后的预乘云。
}
