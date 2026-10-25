#version 330 core
// 云影贴图：从地面沿太阳方向投到云层，把云密度换成柔和的受光比例。
// 调用位置：每帧一次，写到 256 像素的贴图；地表与立石用它接收大块云影。
// 设计原因与取舍：
//   云影让地面明暗与天上的云对应起来；直接对每个地表像素步进云层太贵，
//   先烘成一张以相机为中心的低分辨率贴图，地表只多一次纹理采样。
#include "common.glsl"

uniform vec2 uResolution; // 云影贴图尺寸。
uniform float uRange; // 覆盖范围，米。

out vec4 fragColor; // 红通道是太阳可见度。

void main()
{
    vec2 coord = gl_FragCoord.xy / uResolution; // 贴图坐标。
    OgxCumulusMedia media = lightingCloudMedia(); // 与主画面同一套云参数。
    float shadow = ogxCumulusShadowTex(coord, media, normalize(uSunDirection), uRange, uCloudBase, uCloudCurl,
                                       1.0, 0.0, 3.0, 1.0); // 库的云影投影。
    fragColor = vec4(shadow, shadow, shadow, 1.0); // 一受光，零全影。
}
