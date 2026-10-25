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
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    // 地面点沿太阳方向投到云层中部，用同一份大尺度遮罩决定这里是否真的有云。
    // 不做这一步时，云影会使用平均覆盖率，出现“天上没云、地上仍有阴影”的悬空感。
    vec2 ground = (coord - 0.5) * uRange + uCameraPosition.xz; // 贴图覆盖的地面范围。
    float midAltitude = (media.altitude.x + media.altitude.y) * 0.5; // 云层中部高度。
    vec2 plane = ground + sunDirection.xz * ((midAltitude - uCameraPosition.y) / max(sunDirection.y, 0.05)); // 云层平面落点。
    if (length(plane - lightingSunCloudPlane()) < 300.0) // 与主画面同一个太阳云洞。
    {
        fragColor = vec4(1.0, 1.0, 1.0, 1.0); // 洞里完全受光，雾与地面出现亮柱。
        return;
    }
    float shadeMask = texture(uCloudCurl, plane * 8.0e-5 + vec2(uTime * 0.000003, -uTime * 0.000002)).g; // 十公里尺度厚薄。
    media.coverage = mix(1.00, 1.20, smoothstep(0.35, 0.65, shadeMask)); // 厚处过门槛成影，薄处仍透光。
    float shadow = ogxCumulusShadowTex(coord, media, sunDirection, uRange, uCloudBase, uCloudCurl,
                                       1.0, 0.0, 3.0, 1.0); // 库的云影投影。
    fragColor = vec4(vec3(mix(1.0, shadow, 0.70)), 1.0); // 保留三成底光，云影清晰但不把地面压成黑块。
}
