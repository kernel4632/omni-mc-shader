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
    vec2 ground = (coord - 0.5) * uRange + uCameraPosition.xz; // 贴图覆盖的地面范围。
    float midAltitude = (media.altitude.x + media.altitude.y) * 0.5; // 云层中部高度。
    // 太阳侧的积云与左侧远云：与主画面同一块二维遮罩、同一套三维噪声，
    // 云影才会落在湖面上，而不是凭空出现一条没有云的光柱。
    vec2 cloudPlane = ground + sunDirection.xz * ((midAltitude - uCameraPosition.y) / max(sunDirection.y, 0.05));
    float sunCloud = 1.0 - smoothstep(1800.0, 4200.0, length(cloudPlane - vec2(1800.0, -8200.0)));
    float leftCloud = 1.0 - smoothstep(3000.0, 6500.0, length(cloudPlane - vec2(-2800.0, -15600.0)));
    media.coverage = mix(0.35, 0.65, max(sunCloud, leftCloud));
    float shadow = ogxCumulusShadowTex(coord, media, sunDirection, uRange, uCloudBase, uCloudCurl,
                                       0.0005, 0.0, 0.005, 1.20); // 库的云影投影。
    fragColor = vec4(vec3(mix(1.0, shadow, 0.85)), 1.0); // 保留一点底光，云影清晰但不把地面压成黑块。
}
