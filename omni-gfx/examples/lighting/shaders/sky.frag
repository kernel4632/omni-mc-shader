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
        vec3 reflected = lightingSampleSky(direction, 0.6); // 带云与太阳的反射天空。
        outDirect = vec4(reflected, 1.0); // 普通颜色目标的第一个附件。
        outIndirect = vec4(reflected, 1.0); // 主场景模式不会用到这一路。
        outNormalDepth = vec4(0.5, 0.5, 1.0, 0.0); // 天空没有几何。
        outAlbedoRough = vec4(0.0); // 天空没有材质。
        return; // 不再步进云。
    }
    float altitudeKm = max(uCameraPosition.y, 0.0) * 0.001; // 相机高度，公里。
    float sunDisk = (uSkyMode == 0) ? 1.0 : 0.0; // 只有主画面画太阳；环境光与水面的天空贴图不含圆盘，高光另算。
    vec3 sky = lightingSky(direction, altitudeKm, uSkyMode == 1 ? 6 : 9, sunDisk); // 主画面多两段，贴图省一点。
    // 把云叠到天空上：主画面用累积纹理，贴图按方向重新步进。
    if (uUseCloudTexture == 1)
    {
        // 四邻域取值让半分辨率云放大后边缘更软；透明通道是覆盖率，颜色已经预乘。
        vec4 cloud = texture(uCloudTexture, uv); // 中心样本。
        vec4 left = texture(uCloudTexture, uv - vec2(uCloudTexel.x, 0.0)); // 左。
        vec4 right = texture(uCloudTexture, uv + vec2(uCloudTexel.x, 0.0)); // 右。
        vec4 down = texture(uCloudTexture, uv - vec2(0.0, uCloudTexel.y)); // 下。
        vec4 up = texture(uCloudTexture, uv + vec2(0.0, uCloudTexel.y)); // 上。
        cloud = (cloud * 2.0 + left + right + down + up) / 6.0; // 轻微十字模糊，去掉半分辨率方块感。
        sky = sky * (1.0 - cloud.a) + cloud.rgb; // 预乘合成。
    }
    else
    {
        vec2 noise = ogxBlueNoise(uBlueNoise, ivec2(gl_FragCoord.xy)); // 蓝噪声抖动起点。
        vec4 cloud = lightingCloudMarch(direction, noise, uSkyMode == 1 ? 20 : 26); // 贴图二十步，主画面二十六步。
        sky = sky * (1.0 - cloud.a) + cloud.rgb; // 合成云。
    }
    // 地平线以下没有地形时避免纯黑：用略抬高的视线再取一次天空，远处水面会自然融进去。
    if (direction.y < 0.0)
    {
        vec3 lifted = normalize(vec3(direction.x, 0.002, direction.z)); // 抬到地平线上方。
        vec3 horizon = lightingSky(lifted, altitudeKm, 4, 0.0); // 更便宜的地平线色。
        sky = mix(horizon, sky, smoothstep(-0.25, 0.0, direction.y)); // 越低越接近地平线色。
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
