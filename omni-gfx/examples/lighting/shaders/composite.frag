#version 330 core
// 合成阶段：把直射、间接、屏幕空间遮蔽与颜色反弹合成为一张线性颜色。
// 调用位置：不透明场景与全局光之后、水面与体积雾之前。
// 设计原因与取舍：
//   遮蔽按深度做四邻域升采样，物体边界不会被邻居的暗部染黑；
//   环境光遮蔽只压间接光，接触阴影只压直射光，影子内部仍保留有颜色的天光。
//   颜色反弹乘当地反照率，暗部因此带草地绿或暖方块的色偏，而不是一层灰。
#include "common.glsl"

uniform sampler2D uDirect; // 太阳直射光。
uniform sampler2D uIndirect; // 天空环境光与反射。
uniform sampler2D uNormalDepth; // 法线与距离。
uniform sampler2D uAlbedoRough; // 反照率与粗糙度。
uniform sampler2D uDepth; // 场景深度。
uniform sampler2D uAoContact; // 半分辨率遮蔽与接触阴影。
uniform sampler2D uBounce; // 半分辨率颜色反弹。
uniform vec2 uResolution; // 完整画面尺寸。
uniform vec2 uAOTexel; // 半分辨率一个纹素的大小。
uniform float uBounceStrength; // 颜色反弹强度。
uniform float uAoStrength; // 环境光遮蔽强度。
uniform float uContactStrength; // 接触阴影强度。

out vec4 fragColor; // 合成后的线性颜色。

// 四邻域升采样遮蔽：只取深度相近的邻居，物体轮廓不会被另一侧的暗部拉黑。
vec4 upsampleAo(vec2 uv, float depth) // 返回遮蔽与接触阴影。
{
    vec2 offset = uAOTexel * 0.5; // 半分辨率半格。
    vec4 sum = vec4(0.0); // 加权和。
    float weight = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 四个对角邻居。
    {
        vec2 direction = vec2(i == 0 || i == 2 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0); // 四个方向。
        vec2 sampleUv = uv + direction * offset; // 邻居坐标。
        float sampleDepth = texture(uDepth, sampleUv).r; // 邻居深度。
        float w = 1.0 / (1.0 + abs(sampleDepth - depth) * 5000.0); // 深度越近权重越大。
        sum += texture(uAoContact, sampleUv) * w; // 累加。
        weight += w; // 累加权重。
    }
    return sum / max(weight, 1e-4); // 归一化。
}

// 四邻域升采样颜色反弹：与遮蔽用同一套深度权重，边界不会串色。
vec3 upsampleBounce(vec2 uv, float depth) // 返回反弹颜色。
{
    vec2 offset = uAOTexel * 0.5; // 半分辨率半格。
    vec3 sum = vec3(0.0); // 加权和。
    float weight = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 四个对角邻居。
    {
        vec2 direction = vec2(i == 0 || i == 2 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0); // 四个方向。
        vec2 sampleUv = uv + direction * offset; // 邻居坐标。
        float sampleDepth = texture(uDepth, sampleUv).r; // 邻居深度。
        float w = 1.0 / (1.0 + abs(sampleDepth - depth) * 5000.0); // 深度权重。
        sum += texture(uBounce, sampleUv).rgb * w; // 累加。
        weight += w; // 权重。
    }
    return sum / max(weight, 1e-4); // 归一化。
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution; // 画面坐标。
    float depth = texture(uDepth, uv).r; // 场景深度。
    vec3 indirect = texture(uIndirect, uv).rgb; // 间接光。
    if (depth >= 0.9999) // 天空保持原样。
    {
        fragColor = vec4(indirect, 1.0); // 天空不受遮蔽。
        return;
    }
    vec3 direct = texture(uDirect, uv).rgb; // 直射光。
    vec3 albedo = texture(uAlbedoRough, uv).rgb; // 反照率。
    vec4 normalDepth = texture(uNormalDepth, uv); // 法线与距离。
    vec3 normal = ogxDecodeNormal(normalDepth.xy); // 世界法线。
    vec4 aoContact = upsampleAo(uv, depth); // 升采样遮蔽。
    vec3 bounce = upsampleBounce(uv, depth); // 升采样反弹。
    vec3 ao = ogxAoMultiBounce(aoContact.r, albedo); // iterationT 的多重反弹遮蔽，暗部按反照率提亮。
    float contact = mix(1.0, aoContact.g, uContactStrength); // 接触阴影。
    // 间接光乘多重反弹遮蔽：洞穴和物体底部变暗，但高反照率的墙面会把光反弹回来。
    indirect *= ao;
    // 直射光被接触阴影压暗；接触处的几何遮挡比 VPS 的半影更近。
    direct *= mix(0.04, 1.0, contact);
    // 颜色反弹：邻域反照率当成一盏很低强度的彩色环境光，朝上的面接收更多。
    float skyFacing = 0.35 + 0.65 * clamp(normal.y, 0.0, 1.0); // 朝上的面接收更多环境反弹。
    indirect += albedo * bounce * (uBounceStrength * skyFacing * mix(0.35, 1.0, aoContact.r));
    fragColor = vec4(direct + indirect, 1.0); // 合成。
}
