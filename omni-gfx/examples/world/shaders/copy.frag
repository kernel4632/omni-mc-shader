#version 330 core
// 场景拷贝阶段：把场景颜色原样写进水面目标，供水面着色器读折射与反射。
// 调用位置：测试世界的水面绘制之前，替代原来的一次帧缓冲拷贝。
// 设计原因与取舍：整屏拷贝用一次全屏绘制完成，不依赖帧缓冲拷贝的附件格式匹配，
// 每个像素都一定被写到；水面只需要颜色，深度继续用场景自己的深度附件。
#include "/omni-gfx/common/math.glsl"

uniform sampler2D uSource; // 场景颜色。
uniform vec2 uResolution; // 目标尺寸。

out vec4 fragColor; // 原样输出。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素坐标。
    fragColor = vec4(texture(uSource, uv).rgb, 1.0); // 只拷颜色，透明度写成不透明。
}
