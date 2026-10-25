#version 330 core
// 天空与云采样阶段（半分辨率）：用生成的大气与云模块算一帧的天空与体积云。
// 调用位置：测试世界每帧第二遍绘制，结果先写进半分辨率缓冲，再由时间累积与合成阶段使用。
// 设计原因与取舍：体积云是整个场景最贵的一步，放到半分辨率后像素少四分之三；
// 抖动换成蓝噪声并按帧平移，单帧看起来是细密颗粒，累积几帧后就变成连续过渡，
// 这样步数降到十几步也不会留下层状条纹。大气本身很平滑，跟着降采样看不出差别。
// 立方体贴图模式复用同一份代码，水面反射与背景天空的色温因此完全一致。
#include "world_shared.glsl"

uniform vec3 uForward; // 相机前方向，主画面模式使用。
uniform vec3 uRight; // 相机右方向，主画面模式使用。
uniform vec3 uUp; // 相机上方向，主画面模式使用。
uniform float uTanHalfFov; // 竖直视场角一半的正切。
uniform float uAspect; // 画面宽高比。
uniform int uFace; // 小于零表示主画面，否则是立方体贴图的面编号。
uniform vec2 uResolution; // 当前渲染目标的尺寸。
uniform float uFrame; // 帧号，用来推进蓝噪声与云的相位。
uniform vec3 uSunDirection; // 太阳方向，世界空间单位向量。
uniform vec3 uCameraPos; // 相机位置，米。
uniform float uTime; // 场景时间，推动云层。
uniform float uCloudCover; // 云量，零到一。
uniform sampler2D uBlueNoise; // 六十四像素见方的蓝噪声贴图。
uniform int uCloudSteps; // 沿视线的云步数。
uniform int uSkySteps; // 大气积分段数。
uniform float uCloudSun; // 云的太阳强度倍率，比地面低，避免逆光云整片死白。

out vec4 fragColor; // 线性天空颜色与云的覆盖率，覆盖率留给升采样做边缘保护。

void main()
{
    vec2 pixel = gl_FragCoord.xy; // 当前像素坐标，两种模式都用它取抖动。
    vec3 direction; // 当前像素对应的世界空间方向。
    if (uFace < 0) // 主画面：由像素坐标和相机基向量构造光线。
    {
        direction = worldRayDirection(pixel, uResolution, uForward, uRight, uUp, uTanHalfFov, uAspect); // 与累积阶段完全相同的公式。
    }
    else // 立方体贴图：像素坐标映射到当前面的局部坐标。
    {
        vec2 uv = pixel / uResolution * 2.0 - 1.0; // 每个面都是同样大小的方形。
        direction = normalize(worldCubeDirection(uFace, uv)); // 面方向。
    }
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度，亮度另乘倍率。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 米换成公里。
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    // 天空积分只在水平面以上有意义：把方向抬到地平线以上三度再算。
    // 太贴近水平时视线会与地面相交，单次散射退化成零，海天交界会出现一条黑带。
    vec3 skyDirection = normalize(vec3(direction.x, max(direction.y, 0.055), direction.z)); // 抬到地平线以上。
    vec3 sky = ogxAtmosphereSky(air, altitude, skyDirection, sunDirection, uSkySteps); // 单次散射天空。
    // 蓝噪声抖动：同一个像素每帧拿到不同的起点，时间累积后把十几步的台阶抹平。
    float jitter = ogxBlueNoiseTemporal(uBlueNoise, ivec2(pixel), int(uFrame)).x;
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    vec4 clouds = ogxCloudMarch(layer, uCameraPos * 0.001, direction, sunDirection, sunColor * uCloudSun,
                                sky * 0.45, jitter, uCloudSteps); // 体积云，返回普通颜色与覆盖率。
    // 云也在大气里：沿视线走到云层的路程越长，云越被空气散射洗淡。
    // 不做这一步，地平线附近的云会比天空更饱和，看起来像贴上去的一块板。
    float pathKm = min(max((layer.bottom + layer.top) * 0.5 - altitude, 0.0) / max(direction.y, 0.02), 24.0); // 到云层的近似路程。
    vec3 cloudTransmittance; // 云层的剩余透过率。
    vec3 cloudHaze = ogxAerialPerspective(air, altitude, direction, pathKm, sunDirection, 2, cloudTransmittance); // 云到相机之间的空气散射。
    clouds.rgb = clouds.rgb * cloudTransmittance + cloudHaze; // 云被空气透视洗淡。
    float horizonFade = smoothstep(0.08, 0.30, direction.y); // 低空云在地平线附近淡出，掠射方向步长太长会碎成白点。
    float coverage = clouds.a * horizonFade; // 实际覆盖率。
    vec3 color = mix(sky, clouds.rgb, coverage); // 按覆盖率合成。
    fragColor = vec4(color, coverage); // 覆盖率单独留在透明度通道，升采样时用它保护云边。
}
