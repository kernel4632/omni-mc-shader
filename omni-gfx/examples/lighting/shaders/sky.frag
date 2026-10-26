#version 330 core
// 天空阶段：物理单次散射天空、太阳圆盘与体积云合成；同一个程序也生成等距柱状天空贴图。
// 调用位置：主画面背景、反射背景与每八帧更新一次的天空贴图；贴图再供环境光和水面反射。
// 设计原因与取舍：
//   不使用全景照片：太阳方向、天空色温和云的位置必须能被独立改变，才能检验光照是否自洽。
//   环境光与反射只读一张二维等距柱状贴图，不再依赖立方体贴图；同一份方向映射在着色器里写一次。
//   天空不写深度，几何随后覆盖；主画面把结果写到第二张颜色附件，第一张留零给直射光。
#include "common.glsl"

uniform vec2 uResolution; // 当前渲染目标尺寸。
uniform vec3 uForward; // 主画面相机前方向。
uniform vec3 uRight; // 主画面相机右方向。
uniform vec3 uUp; // 主画面相机上方向。
uniform float uTanHalfFov; // 竖直视场角一半的正切。
uniform float uAspect; // 画面宽高比。
uniform int uSkyMode; // 零主画面，一等距柱状贴图，二反射背景。
uniform int uSceneTarget; // 一表示写入主场景的四张附件，零表示写入普通颜色目标。
uniform int uUseCloudTexture; // 一表示直接采样累积好的云，零表示按方向步进。
uniform sampler2D uCloudTexture; // 半分辨率累积云，rgb 是预乘加色，a 是覆盖率。
uniform vec2 uCloudTexel; // 云图一个纹素的大小。

layout(location = 0) out vec4 outDirect; // 主场景的直射光附件；天空为零。
layout(location = 1) out vec4 outIndirect; // 主场景的间接光附件；天空颜色写在这里。
layout(location = 2) out vec4 outNormalDepth; // 法线与线性深度；天空深度为零。
layout(location = 3) out vec4 outAlbedoRough; // 反照率与粗糙度；天空为零。

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 当前像素在目标里的坐标。
    vec3 direction; // 这个像素对应的世界方向。
    if (uSkyMode == 1) // 等距柱状贴图：横坐标是水平角，纵坐标是仰角。
    {
        float phi = (uv.x - 0.5) * 6.28318530718; // 水平角，零朝正 X。
        float theta = uv.y * 3.14159265359; // 从头顶到脚下。
        direction = normalize(vec3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))); // 球面方向。
    }
    else // 主画面与反射背景都用针孔相机光线。
    {
        direction = lightingRayDirection(gl_FragCoord.xy, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 相机光线。
    }
    // 反射背景只需要已有天空贴图，不再步进一遍云；水面不会为倒影付第二次体积云成本。
    if (uSkyMode == 2)
    {
        vec3 reflected = lightingSampleSky(direction, 2.2); // 带云与太阳的反射天空；取较高 mip，水面不会继承天空贴图的步进噪点。
        outDirect = vec4(reflected, 1.0); // 普通颜色目标的第一个附件。
        outIndirect = vec4(reflected, 1.0); // 主场景模式不会用到这一路。
        outNormalDepth = vec4(0.5, 0.5, 1.0, 0.0); // 天空没有几何。
        outAlbedoRough = vec4(0.0); // 天空没有材质。
        return; // 不再步进云。
    }
    float altitudeKm = max(uCameraPosition.y, 0.0) * 0.001; // 相机高度，公里。
    float sunDisk = (uSkyMode == 0) ? 1.0 : 0.0; // 只有主画面画太阳；环境光与水面的天空贴图不含圆盘，高光另算。
    vec3 sky = lightingSky(direction, altitudeKm, uSkyMode == 1 ? 6 : 9, sunDisk); // 主画面与贴图都用同一张散射表。
    // 把云叠到天空上：主画面用累积纹理，贴图按方向重新步进。
    vec3 cloudColor; // 预乘云颜色。
    float cloudTransmittance = 1.0; // 云的透射率。
    if (uUseCloudTexture == 1)
    {
        vec4 cloud = texture(uCloudTexture, uv); // 云纹理已经在自己的通道里做过可分离模糊，这里直接采样。
        cloudColor = cloud.rgb; // 预乘颜色。
        cloudTransmittance = cloud.a; // 透射率。
    }
    else
    {
        vec2 noise = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)); // 蓝噪声抖动起点。
        vec4 cloud = lightingCloudMarch(direction, noise); // 按方向步进，步数与 iterationT 相同。
        cloudColor = cloud.rgb; // 预乘颜色。
        cloudTransmittance = cloud.a; // 透射率。
    }
    // 云的距离用于 iterationT 的 CLOUD_FADE：远处云逐渐交给空气透视，不再是一条贴在天空上的纸片。
    float hitDistance = 200000.0; // 没有命中时给一个足够远的距离。
    if (direction.y > 0.001) // 只有朝上的视线会穿过云层。
    {
        float midAltitude = 750.0; // 云层中部高度，米。
        float slant = (midAltitude - uCameraPosition.y) / direction.y; // 到云层中部的斜距。
        if (slant > 0.0) hitDistance = slant; // 有效命中。
    }
    float cloudFade = clamp(exp2(-hitDistance * 8.0e-5), 0.0, 1.0); // 与 iterationT 相同的淡出曲线。
    float fadedTransmittance = mix(1.0, cloudTransmittance, cloudFade); // 云在远处逐渐消失。
    if (cloudTransmittance < 0.9999) // 只有真正有云时才付空气透视成本。
    {
        vec3 cloudPoint = uCameraPosition + direction * min(hitDistance, 60000.0); // 云团代表的点。
        vec3 aerialTransmittance; // 大气到云点的透过率。
        vec3 aerial = lightingAerial(cloudPoint, direction, min(hitDistance, 60000.0), aerialTransmittance); // 这段空气的散射色。
        sky = sky * fadedTransmittance + aerial * (1.0 - fadedTransmittance) + cloudColor * (cloudFade * aerialTransmittance); // iterationT 的云合成顺序。
    }
    else
    {
        sky = sky * fadedTransmittance + cloudColor * cloudFade; // 没有云时只是保留天空。
    }
    if (uSceneTarget == 1) // 主场景：天空写进间接光附件，直射光为零。
    {
        outDirect = vec4(0.0, 0.0, 0.0, 1.0); // 天空没有直射光。
        outIndirect = vec4(sky, 1.0); // 背景颜色。
        outNormalDepth = vec4(0.5, 0.5, 1.0, 0.0); // 深度一表示天空。
        outAlbedoRough = vec4(0.0); // 没有材质。
    }
    else // 等距柱状贴图或反射目标：只用第一张颜色。
    {
        outDirect = vec4(sky, 1.0); // 普通颜色。
        outIndirect = vec4(sky, 1.0); // 未使用的附件也写有效值。
        outNormalDepth = vec4(0.5, 0.5, 1.0, 0.0); // 天空没有几何。
        outAlbedoRough = vec4(0.0); // 没有材质。
    }
}
