// 泛光：从时间合成后的线性场景里找出亮过白色的强光源，向四周扩散光晕，再叠回画面。
// 调用位置：rendering/final.glsl 在镜头效果之后调用 omniBloom(texcoord)，返回值直接并入线性颜色。
// 可复制示例：`vec3 glow = omniBloom(texcoord);`
// 设计原因：真实相机的强光会在镜片上散开成光晕，只单纯加亮会显得生硬；
// 所以这里只让超过白色的部分扩散，普通亮度保持不变，避免整幅画面被抬亮发灰。
// 取舍：固定 16 次环形采样，实现简单、性能可控；光晕近似圆形，不读取降采样链。
#ifndef OMNI_BLOOM
#define OMNI_BLOOM
// @effect {"label":{"zh_cn":"泛光","en_us":"Bloom"}}
// @option {"label":{"zh_cn":"开启泛光","en_us":"Bloom"}}
//#define OMNI_BLOOM_ENABLED
// @option {"label":{"zh_cn":"泛光强度","en_us":"Bloom strength"},"slider":true}
#define OMNI_BLOOM_STRENGTH 0.25 // [0.1 0.25 0.5 1.0]
// @option {"label":{"zh_cn":"泛光阈值","en_us":"Bloom threshold"},"description":{"zh_cn":"亮度超过此值才产生光晕；低于一时高光也会泛光，高于一时只有强光源泛光。","en_us":"Only luminance above this value blooms; below one highlights also glow, above one only strong sources do."},"slider":true}
#define OMNI_BLOOM_THRESHOLD 1.0 // [0.5 0.8 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"泛光半径","en_us":"Bloom radius"},"slider":true}
#define OMNI_BLOOM_RADIUS 1.0 // [0.5 1.0 1.5 2.0]
// 需要的共用输入：omniLuminance 亮度计算，以及 colortex0 颜色、viewWidth 与 viewHeight 尺寸。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"

// --- 单个样本的泛光贡献 ---
// 只有亮过白色的部分参与扩散，并按亮度归一化。
// 为什么归一化：亮度越高的样本本身越亮，除以自身亮度后各样本贡献接近，光晕不会糊成一团白。
// 为什么除数保持正数：纯黑样本亮度为零，直接相除会得到无效值，所以下限取一个极小正数。
vec3 omniBloomSample(vec3 sampleColor) {
    float lum = omniLuminance(sampleColor); // 亮度同时用于筛选和归一化，只算一次。
    return sampleColor * max(lum - OMNI_BLOOM_THRESHOLD, 0.0) / max(lum, 0.001); // 亮度不超过阈值时贡献为零。
}

// --- 泛光主入口 ---
// 对每个像素做一圈环形采样，把强光扩散结果加回线性颜色。
vec3 omniBloom(vec2 uv) {
    vec3 result = vec3(0.0); // 默认零贡献，关闭泛光或强度为零时直接返回它。
#ifdef OMNI_BLOOM_ENABLED
    if (OMNI_BLOOM_STRENGTH <= 0.0) return result; // 强度非正时提前退出，等价于关闭。
    vec2 bufferSize = max(vec2(viewWidth, viewHeight), vec2(1.0)); // 尺寸为零按一像素处理，避免除零。
    for (int i = 0; i < 16; i++) {
        float angle = float(i) * 2.399963; // 取黄金角让 16 个样本均匀铺开成一圈。
        float radius = (2.0 + float(i) * 1.5) * OMNI_BLOOM_RADIUS; // 半径由近到远递增，近处强光扩散更明显；半径选项整体放大或缩小。
        vec2 offset = vec2(cos(angle), sin(angle)) * radius / bufferSize; // 转成与分辨率无关的屏幕偏移。
        vec3 sampleColor = texture(colortex0, clamp(uv + offset, 0.0, 1.0)).rgb; // 时间合成后的稳定线性颜色。
        result += omniBloomSample(sampleColor); // 累加这一环的光晕贡献。
    }
    result *= OMNI_BLOOM_STRENGTH / 16.0; // 除以采样数再乘强度，得到平均光晕。
    // 出现非有限值时直接清零，避免一个坏点污染整幅画面。
    // 为什么不能写成 `result *= float(all(equal(result, result)))`：非数乘零仍是非数，而无穷大自身比较又为真，
    // 那种写法既清不掉非数也拦不住无穷大。`isnan` 与 `isinf` 在 GLSL 330 就可用，直接赋值才能可靠归零。
    if (any(isnan(result)) || any(isinf(result))) result = vec3(0.0);
#endif
    return result; // 关闭泛光时没有纹理读取，直接返回零贡献。
}
#endif
