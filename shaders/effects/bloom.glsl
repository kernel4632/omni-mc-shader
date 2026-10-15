// 泛光：从时间合成后的线性场景里提取超过白色的强光，做环形扩散后加到最终画面。
// 调用位置：rendering/final.glsl 在镜头效果之后调用 omniBloom(uv)，返回值直接并入线性颜色。
// 可复制示例：`vec3 glow = omniBloom(texcoord);`
#ifndef OMNI_BLOOM
#define OMNI_BLOOM
// @effect {"label":{"zh_cn":"泛光","en_us":"Bloom"}}
// @option {"label":{"zh_cn":"开启泛光","en_us":"Bloom"}}
//#define OMNI_BLOOM_ENABLED
// @option {"label":{"zh_cn":"泛光强度","en_us":"Bloom strength"},"slider":true}
#define OMNI_BLOOM_STRENGTH 0.25 // [0.1 0.25 0.5 1.0]
// 共用颜色与尺寸输入。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
vec3 omniBloom(vec2 uv) {
    vec3 result = vec3(0.0); // 关闭或强度为零时返回零贡献。
#ifdef OMNI_BLOOM_ENABLED
    if (OMNI_BLOOM_STRENGTH <= 0.0) return result; // 强度非正时提前退出，保守回退为零。
    vec2 bufferSize = max(vec2(viewWidth, viewHeight), vec2(1.0)); // 尺寸为零时按一像素处理，避免除零。
    for (int i = 0; i < 16; i++) {
        float angle = float(i) * 2.399963; // 环形分散样本角度。
        float radius = 2.0 + float(i) * 1.5; // 覆盖近处到远处强光。
        vec2 offset = vec2(cos(angle), sin(angle)) * radius / bufferSize; // 分辨率无关像素半径。
        vec3 sampleColor = texture(colortex0, clamp(uv + offset, 0.0, 1.0)).rgb; // 时间合成后的稳定线性颜色。
        float lum = omniLuminance(sampleColor); // 亮度只计算一次，供筛选与归一化共用。
        result += sampleColor * max(lum - 1.0, 0.0) / max(lum, 0.001); // 只有超过白色的光扩散，除数保持为正。
    }
    result *= OMNI_BLOOM_STRENGTH / 16.0; // 按采样数归一化。
    result *= float(all(equal(result, result))); // 出现 NaN 时回退零贡献，避免污染整幅画面。
#endif
    return result; // 独立开关移除纹理读取。
}
#endif
