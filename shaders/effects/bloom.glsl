// 泛光：最终显示从线性强光取样；示例 omniBloom(uv)。
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
    vec3 result = vec3(0); // 关闭时返回零贡献。
#ifdef OMNI_BLOOM_ENABLED
    for (int i=0;i<16;i++) {
        float angle = float(i)*2.399963; // 环形分散样本。
        float radius = 2.0+float(i)*1.5; // 覆盖近处到远处强光。
        vec2 offset = vec2(cos(angle),sin(angle))*radius/vec2(viewWidth,viewHeight); // 分辨率无关像素半径。
        vec3 c = texture(colortex0,clamp(uv+offset,0.0,1.0)).rgb; // 时间合成后的稳定线性颜色。
        result += c*max(omniLuminance(c)-1.0,0.0)/max(omniLuminance(c),0.001); // 只有超过白色的光扩散。
    }
    result *= OMNI_BLOOM_STRENGTH/16.0; // 按采样数归一化。
#endif
    return result; // 独立开关移除纹理读取。
}
#endif
