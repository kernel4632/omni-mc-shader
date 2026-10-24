#version 330 core
// 地形片元阶段：太阳直射、天空环境光、高度图阴影与远景雾。
// 调用位置：测试世界的地形绘制；不依赖 Minecraft 的任何输入。
// 设计原因与取舍：阴影直接在高度图上步进，省掉阴影贴图，同时保留方块山坡的投影。
#include "atmosphere.glsl"

in vec3 vWorldPosition;  // 世界坐标。
in vec3 vNormal;  // 世界空间法线。
in vec3 vColor;  // 方块面颜色。
in float vOcclusion;  // 预计算的环境光遮蔽。

uniform vec3 uCameraPos;  // 相机位置。
uniform sampler2D uHeight;  // 高度图，横向与纵向都按地形尺寸归一化。
uniform float uTerrainSize;  // 地形边长，用来把世界坐标换成高度图坐标。

out vec4 fragColor;  // 线性高动态范围颜色。

// 高度图阴影：从当前点朝太阳步进，遇到更高的地形就判为遮挡。
float terrainShadow(vec3 position)
{
    vec3 sunDirection = normalize(uSunDirection);  // 太阳方向。
    float stepLength = 2.2;  // 每步水平前进约两米。
    vec3 samplePosition = position + vec3(0.0, 0.25, 0.0);  // 抬高一点，避免自遮挡。
    for (int i = 0; i < 22; i++)  // 固定步数，保证不同显卡的耗时接近。
    {
        samplePosition += sunDirection * stepLength;  // 沿太阳方向前进。
        vec2 uv = samplePosition.xz / uTerrainSize;  // 换成高度图坐标。
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)  // 出了地形范围就没有遮挡。
        {
            break;
        }
        float height = texture(uHeight, uv).r;  // 该位置的地形高度。
        if (height > samplePosition.y + 0.15)  // 地形高于光线，说明被挡住。
        {
            return 0.0;
        }
    }
    return 1.0;  // 一路没有遮挡。
}

void main()
{
    vec3 normal = normalize(vNormal);  // 方块面法线。
    vec3 sunDirection = normalize(uSunDirection);  // 太阳方向。
    float shadow = terrainShadow(vWorldPosition);  // 高度图阴影。
    float diffuse = max(dot(normal, sunDirection), 0.0);  // 直射余弦。
    vec3 sun = sunColor() * 2.0 * diffuse * shadow;  // 太阳直射。
    vec3 sky = skyBase(vec3(0.0, 1.0, 0.0)) * 0.55;  // 天顶环境光。
    vec3 ground = vec3(0.16, 0.14, 0.11) * max(-normal.y, 0.0) * 0.30 + vec3(0.095, 0.100, 0.110);  // 地面反弹光。
    vec3 color = vColor * (sun + sky * (0.55 + 0.45 * normal.y) + ground) * vOcclusion;  // 合成光照。
    float distanceToCamera = length(vWorldPosition - uCameraPos);  // 到相机的距离。
    float fog = 1.0 - exp(-pow(distanceToCamera * 0.0045, 1.6));  // 远景雾，越远越浓。
    vec3 fogColor = skyBase(normalize(vWorldPosition - uCameraPos));  // 雾色取同方向的天空底色。
    color = mix(color, fogColor, clamp(fog, 0.0, 0.92));  // 保留一点地形轮廓。
    fragColor = vec4(color, 1.0);  // 写入场景颜色。
}
