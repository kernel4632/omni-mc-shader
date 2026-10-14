// 共用计算：颜色、噪声和安全归一化，由效果显式引入；示例 omniLinear(color)。
#ifndef OMNI_MATH
#define OMNI_MATH
float omniLuminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); } // 按人眼敏感度计算亮度。
vec3 omniLinear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); } // 贴图转线性。
vec3 omniSrgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); } // 显示编码。
vec3 omniNormalize(vec3 v) { return v * inversesqrt(max(dot(v, v), 1e-10)); } // 零向量不会污染整幅画面。
float omniHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); } // 可重复的空间随机数。
float omniNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p); // 找到噪声格与格内位置。
    f = f * f * (3.0 - 2.0 * f); // 平滑跨格变化。
    vec2 q = i.xy + i.z * vec2(37.0, 17.0); // 三维格映射到随机种子。
    float a = mix(mix(omniHash(q), omniHash(q + vec2(1,0)), f.x), mix(omniHash(q + vec2(0,1)), omniHash(q + vec2(1,1)), f.x), f.y);
    q += vec2(37.0, 17.0); // 下一高度层使用不同随机种子。
    float b = mix(mix(omniHash(q), omniHash(q + vec2(1,0)), f.x), mix(omniHash(q + vec2(0,1)), omniHash(q + vec2(1,1)), f.x), f.y);
    return mix(a, b, f.z); // 连续混合相邻高度层。
}
#endif
