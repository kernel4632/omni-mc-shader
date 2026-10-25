#version 330 core
// 云影贴图：从地面沿太阳方向投到云层，把云密度换成柔和的受光比例。
// 调用位置：每帧一次，写到 512 像素的贴图；地表、立石与体积雾用它接收大块云影。
// 设计原因与取舍：
//   云影让地面明暗与天上的云对应起来；直接对每个地表像素步进云层太贵，
//   先烘成一张以相机为中心的低分辨率贴图，地表只多一次纹理采样。
//   覆盖率遮罩按投影后的云层平面取样，因此天空里没有云的方向不会在地面投出悬空阴影。
#include "common.glsl"

uniform vec2 uResolution; // 云影贴图尺寸。
uniform float uRange; // 覆盖范围，米。

out vec4 fragColor; // 红通道是太阳可见度。

void main()
{
    vec2 coord = gl_FragCoord.xy / uResolution; // 贴图坐标。
    OgxCumulusMedia media = lightingCloudMedia(); // 与主画面同一套云参数。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    float shadow = ogxCumulusShadowTex(coord, media, sunDirection, uRange, uCloudBase, uCloudCurl,
                                      0.00006, LIGHTING_CLOUD_COVERAGE_OFFSET, 0.0025, 1.10); // 库的云影投影。
    fragColor = vec4(vec3(mix(1.0, shadow, 0.85)), 1.0); // 保留一点底光，云影清晰但不把地面压成黑块。
}
