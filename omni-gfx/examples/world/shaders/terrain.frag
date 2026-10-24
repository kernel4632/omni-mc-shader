#version 330 core
// 地形片元阶段：方向光阴影贴图、云影、天空环境光、空气透视与低空雾。
// 调用位置：测试世界的地形绘制，顶点数据由 Python 侧按高度图生成。
// 设计原因与取舍：阴影改成一张覆盖全岛的方向光阴影贴图。原来沿高度图步进二十四次，
// 每像素要做二十四次纹理取样，而且只能得到整体遮挡，方块之间没有互相投影；
// 现在每像素只比较三乘三邻域，快得多，也能看到墙根的暗部和山脊投到地面上的影子。
// 环境光直接取天空立方体贴图的高层多级纹理，省掉每像素重新积分大气。
#include "world_shared.glsl"

in vec3 vWorldPosition; // 世界坐标。
in vec3 vNormal; // 世界空间法线。
in vec3 vColor; // 方块面颜色。
in float vOcclusion; // 预计算的环境光遮蔽。

uniform vec3 uCameraPos; // 相机位置。
uniform vec3 uSunDirection; // 太阳方向。
uniform mat4 uShadowMatrix; // 方向光视图投影矩阵，把世界坐标换到阴影贴图坐标。
uniform sampler2D uShadowMap; // 方向光深度图。
uniform float uShadowTexel; // 阴影贴图一个纹素的跨度，用于邻域采样。
uniform samplerCube uSkyCube; // 天空立方体贴图，用来取环境光。
uniform float uTime; // 场景时间，推动云与雾。
uniform float uFrame; // 帧号，给雾抖动换相位。
uniform float uCloudCover; // 云量。
uniform float uSunStrength; // 太阳直射倍率。
uniform float uSkyStrength; // 天空环境光倍率。

out vec4 fragColor; // 线性高动态范围颜色。

// 方向光阴影：把世界点换到阴影贴图坐标，用三乘三邻域比较得到柔和边缘。
float shadowMapVisibility(vec3 worldPosition, vec3 normal)
{
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    // 沿法线抬起一点再投影，平面上的掠射光不会和自己比较出条纹。
    vec4 lightPosition = uShadowMatrix * vec4(worldPosition + normal * 0.35, 1.0);
    vec3 coordinate = lightPosition.xyz / lightPosition.w * 0.5 + 0.5; // 换到零到一的贴图坐标。
    if (coordinate.z < 0.0 || coordinate.z > 1.0) // 超出深度范围说明点在阴影范围外。
    {
        return 1.0; // 范围外一律算受光。
    }
    if (coordinate.x < 0.0 || coordinate.x > 1.0 || coordinate.y < 0.0 || coordinate.y > 1.0) // 超出横向范围。
    {
        return 1.0; // 岛外没有投影物。
    }
    // 掠射时深度变化最快，偏置要更大，否则同一块顶面会把自己投成条纹。
    float bias = 0.0016 + 0.0030 * (1.0 - max(dot(normal, sunDirection), 0.0));
    float visibility = 0.0; // 九次比较里有多少次是受光的。
    for (int y = -1; y <= 1; y++) // 三乘三邻域，等效于小半径百分比过滤。
    {
        for (int x = -1; x <= 1; x++)
        {
            vec2 offset = vec2(float(x), float(y)) * uShadowTexel; // 邻域偏移。
            float depth = texture(uShadowMap, coordinate.xy + offset).r; // 该纹素记录的最近深度。
            visibility += (coordinate.z - bias <= depth) ? 1.0 : 0.0; // 比较得到受光或遮挡。
        }
    }
    return visibility / 9.0; // 平均成零到一的可见度。
}

void main()
{
    vec3 normal = normalize(vNormal); // 方块面法线。
    vec3 sunDirection = normalize(uSunDirection); // 太阳方向。
    vec3 sunColor = worldSunColor(); // 太阳色度。
    float shadow = shadowMapVisibility(vWorldPosition, normal); // 方向光阴影。
    OgxCloudLayer layer = worldCloudLayer(uTime, uCloudCover); // 本帧云层。
    float cloudShadow = ogxCloudShadow(layer, vWorldPosition * 0.001, sunDirection); // 云影，保留整体的明暗块。
    float diffuse = max(dot(normal, sunDirection), 0.0); // 直射余弦。
    vec3 sun = sunColor * (uSunStrength * diffuse * shadow * cloudShadow); // 太阳直射。
    // 天空环境光：天顶偏蓝、地平线偏白，墙面的法线接近水平，颜色因此接近地平线。
    vec3 zenith = textureLod(uSkyCube, vec3(0.0, 1.0, 0.0), 4.0).rgb; // 天顶颜色。
    vec3 horizon = textureLod(uSkyCube, normalize(vec3(sunDirection.x, 0.12, sunDirection.z)), 4.0).rgb; // 向阳侧的地平线颜色。
    vec3 ambient = mix(horizon, zenith, normal.y * 0.5 + 0.5) * uSkyStrength; // 按朝向混合的环境光。
    vec3 ground = vec3(0.20, 0.17, 0.13) * max(-normal.y, 0.0) * 0.6; // 地面反弹光，只影响朝下的面。
    float fill = max(dot(normal, normalize(vec3(-sunDirection.x, 0.35, -sunDirection.z))), 0.0); // 背光面的补光方向。
    vec3 fillLight = sunColor * (fill * uSunStrength * 0.28); // 天空与海面的反弹，避免侧墙死黑。
    float grain = 0.90 + 0.20 * ogxValueNoise2(vWorldPosition.xz * 1.1 + vec2(vWorldPosition.y * 0.3)); // 细颗粒打散整片纯色。
    vec3 color = vColor * grain * (sun + ambient + ground + fillLight) * vOcclusion; // 合成光照。
    float distanceToCamera = length(vWorldPosition - uCameraPos); // 到相机的距离，米。
    vec3 viewDirection = normalize(vWorldPosition - uCameraPos); // 从相机指向地形。
    OgxAtmosphere air = worldAtmosphere(); // 本场景的大气常数。
    float altitude = max(uCameraPos.y, 0.0) * 0.001; // 相机高度，公里。
    vec3 transmittance; // 空气透视的剩余透过率。
    vec3 haze = ogxAerialPerspective(air, altitude, viewDirection, distanceToCamera * 0.001, sunDirection, 3, transmittance); // 远景空气散射。
    color = color * transmittance + haze; // 先做空气透视。
    float jitter = ogxBayer8(gl_FragCoord.xy + vec2(uFrame * 0.37, uFrame * 0.71)); // 稳定的雾抖动，避免静态噪点。
    vec4 fog = ogxFogMarch(worldFog(uTime), uCameraPos * 0.001, vWorldPosition * 0.001, sunDirection, sunColor * 2.0, jitter, 3); // 低空体积雾。
    color = ogxFogApply(color, fog); // 再叠贴地雾。
    fragColor = vec4(color, 1.0); // 写入场景颜色。
}
