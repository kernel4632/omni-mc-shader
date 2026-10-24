#version 330 core
// 地形片元阶段：太阳直射、天空环境光、软高度图阴影、云影、空气透视与低空雾。
// 调用位置：测试世界的地形绘制；不依赖 Minecraft 的任何输入。
// 设计原因与取舍：阴影直接在高度图上步进，用遮挡深度估计半影，省掉阴影贴图也能看到柔和边缘。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界空间法线。
in vec3 vColor; // 方块面颜色。
in float vOcclusion; // 预计算的环境光遮蔽。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform sampler2D uHeight; // 高度图，横向与纵向都按地形尺寸归一化。
uniform float uTerrainSize; // 地形边长，用来把世界坐标换成高度图坐标。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uFrame; // 帧号，给抖动换相位。
uniform float uCloudCover; // 云量。

out vec4 fragColor; // 线性高动态范围颜色。

// 高度图软阴影：朝太阳步进，遇到更高的地形就按高出量估计半影。
float terrainShadow(vec3 position, float jitter)
{
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    float result = 1.0; // 剩余可见度。
    float distanceAlong = 0.8 + jitter * 0.6; // 起点略抬高，避免自遮挡；抖动打散台阶。
    for (int i = 0; i < 24; i++) // 固定步数，保证不同显卡的耗时接近。
    {
        vec3 samplePosition = position + sunDirection * distanceAlong; // 沿太阳方向前进。
        vec2 uv = samplePosition.xz / uTerrainSize; // 换成高度图坐标。
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) // 出了地形范围就没有遮挡。
        {
            break; // 提前结束。
        }
        float height = texture(uHeight, uv).r; // 该位置的地形高度。
        float above = height - samplePosition.y; // 地形高于光线的量。
        if (above > 0.0) // 光线穿进地形。
        {
            float softness = max(0.25, distanceAlong * 0.08); // 越远的遮挡物半影越宽。
            result = min(result, 1.0 - smoothstep(0.0, softness, above)); // 刚接触时半透明，深入后全黑。
        }
        distanceAlong += 1.5 + distanceAlong * 0.08; // 逐步拉大步长，覆盖更远。
    }
    return result; // 零为全遮挡，一为全亮。
}

// 天空环境光：取天顶方向的单次散射，给背光面一个偏蓝的底色。
vec3 skyAmbient(OgxAtmosphere air, float altitude, vec3 sunDirection)
{
    vec3 zenith = normalize(vec3(0.0, 1.0, 0.0) + sunDirection * 0.25); // 稍微朝太阳偏，环境光更暖。
    return ogxAtmosphereSky(air, altitude, zenith, sunDirection, 4); // 四段足够做环境底色。
}

void main()
{
    vec3 normal = normalize(vNormal); // 方块面法线。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    OgxAtmosphere air = ogxAtmosphereEarth(); // 大气常数。
    float jitter = ogxBayer8(gl_FragCoord.xy); // 稳定的八乘八抖动，避免静态噪点。
    float shadow = terrainShadow(vWorldPosition, 0.5); // 高度图软阴影，固定起点避免逐像素噪点。
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    float cloudShadow = ogxCloudShadow(layer, vWorldPosition * 0.001, sunDirection); // 云影。
    float diffuse = max(dot(normal, sunDirection), 0.0); // 直射余弦。
    vec3 sun = sunColor * (6.0 * diffuse * shadow * cloudShadow); // 太阳直射。
    vec3 sky = skyAmbient(air, altitude, sunDirection) * (0.55 + 0.45 * normal.y) * 2.2; // 天空环境光。
    sky += vec3(0.080, 0.095, 0.120); // 多次散射的底光，避免背光墙全黑。
    vec3 ground = vec3(0.16, 0.14, 0.12) * max(-normal.y, 0.0) * 0.9; // 地面反弹光。
    float fill = max(dot(normal, normalize(vec3(-sunDirection.x, 0.35, -sunDirection.z))), 0.0); // 背光面的补光方向。
    vec3 fillLight = sunColor * fill * 0.90; // 模拟天空与海面的反弹，避免侧墙死黑。
    float grain = 0.86 + 0.28 * ogxValueNoise2(vWorldPosition.xz * 1.1 + vec2(vWorldPosition.y * 0.3)); // 细颗粒打散整片纯色。
    vec3 color = vColor * grain * (sun + sky + ground + fillLight) * vOcclusion; // 合成光照。
    float distanceToCamera = length(vWorldPosition - uCameraPos); // 到相机的距离，米。
    vec3 viewDirection = normalize(vWorldPosition - uCameraPos); // 从相机指向地形。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewDirection, distanceToCamera * 0.001, sunDirection, 5, transmittance); // 远景空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 6); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写入场景颜色。
}
