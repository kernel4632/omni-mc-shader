#version 330 core
// 场景拷贝：把合成后的颜色完整复制到水面目标，避免 blit 在半像素边界漏行。
// 调用位置：水面绘制之前，之后只把深度 blit 过去。
// 设计原因与取舍：全屏三角形采样一次纹理，颜色逐像素精确复制；
// 深度仍用 blit，因为深度格式与采样方式由驱动处理更可靠。
#include "/omni-gfx/common/math.glsl"

uniform sampler2D uSource; // 来源颜色。
uniform vec2 uResolution; // 画面尺寸。

out vec4 fragColor; // 复制结果。

void main() // 全屏三角形入口。
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 纹素中心坐标。
    fragColor = texture(uSource, uv); // 原样复制，不做色调或裁剪。
}
