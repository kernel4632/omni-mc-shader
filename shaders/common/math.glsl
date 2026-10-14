// 共用纯计算：颜色转换、亮度、安全归一化与可重复空间噪声，不包含任何业务效果。
// 调用位置：需要这些计算的效果文件显式 #include "/common/math.glsl"。
// 可复制示例：`vec3 lin = omniLinear(color); float lum = omniLuminance(lin); float n = omniNoise(world);`
#ifndef OMNI_MATH
#define OMNI_MATH
float omniLuminance(vec3 color) { return dot(color, vec3(0.2126, 0.7152, 0.0722)); } // 按人眼敏感度计算亮度。
vec3 omniLinear(vec3 color) { return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color)); } // 贴图转线性。
vec3 omniSrgb(vec3 color) { return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color)); } // 显示编码。
vec3 omniNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); } // 零向量不会污染整幅画面。
float omniHash(vec2 point) { return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453); } // 可重复的空间随机数。
float omniNoise(vec3 point) {
    vec3 cell = floor(point); // 点所在的整数噪声格。
    vec3 local = fract(point); // 点在该格内的局部位置。
    local = local * local * (3.0 - 2.0 * local); // 平滑格内变化，避免硬边。
    vec2 seed = cell.xy + cell.z * vec2(37.0, 17.0); // 三维格映射到二维随机种子。
    float lower = mix(mix(omniHash(seed), omniHash(seed + vec2(1,0)), local.x), mix(omniHash(seed + vec2(0,1)), omniHash(seed + vec2(1,1)), local.x), local.y); // 下层四角混合。
    seed += vec2(37.0, 17.0); // 下一高度层使用不同随机种子。
    float upper = mix(mix(omniHash(seed), omniHash(seed + vec2(1,0)), local.x), mix(omniHash(seed + vec2(0,1)), omniHash(seed + vec2(1,1)), local.x), local.y); // 上层四角混合。
    return mix(lower, upper, local.z); // 连续混合相邻高度层。
}
#endif
