// 调色与曝光：时间合成保存曝光，最终显示编码；示例 omniColor(color, exposure)。
#ifndef OMNI_COLOR
#define OMNI_COLOR
// @effect {"label":{"zh_cn":"调色","en_us":"Color"}}
// @option {"label":{"zh_cn":"曝光倍率","en_us":"Exposure"},"slider":true}
#define OMNI_EXPOSURE 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"自动曝光","en_us":"Auto exposure"}}
//#define OMNI_AUTO_EXPOSURE
// @option {"label":{"zh_cn":"对比度","en_us":"Contrast"},"slider":true}
#define OMNI_CONTRAST 1.0 // [0.75 1.0 1.1 1.25]
// @option {"label":{"zh_cn":"饱和度","en_us":"Saturation"},"slider":true}
#define OMNI_SATURATION 1.0 // [0.5 0.75 1.0 1.1 1.25]
// @option {"label":{"zh_cn":"白平衡","en_us":"White balance"},"slider":true}
#define OMNI_WHITE_BALANCE 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"亮度倍率","en_us":"Brightness"},"slider":true}
#define OMNI_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label":{"zh_cn":"色调映射","en_us":"Tone mapping"},"description":{"zh_cn":"零用简单有理曲线保持原亮度，一用 AgX 压缩高光并保留饱和。","en_us":"Zero keeps the simple rational curve; one uses AgX filmic highlight compression."}}
#define OMNI_TONE_MAP 1 // [0 1]
// 曝光有效性与时间历史共用一个接口。
#include "/effects/antialiasing.glsl"
// 简单有理映射：单调压高光，保持既有画面行为。
vec3 omniToneMapSimple(vec3 color) {
    return color/(1.0+color); // 亮部渐近于一，不出现硬剪切。
}
// AgX 色调映射：宽色域对数编码后用 S 曲线压缩高光。
vec3 omniToneMapAgx(vec3 color) {
    const mat3 toWorking = mat3( // 线性 sRGB 到 AgX 宽色域工作空间。
        vec3(0.856627153315983, 0.137318972929847, 0.11189821299995),
        vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903),
        vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859));
    const mat3 fromWorking = mat3( // 工作空间回到显示原色。
        vec3(1.1271005818144368, -0.1413297634984383, -0.14132976349843826),
        vec3(-0.11060664309660323, 1.157823702216272, -0.11060664309660294),
        vec3(-0.016493938717834573, -0.016493938717834257, 1.2519364065950405));
    const float lowestEv = -12.47393; // 承认的最暗曝光。
    const float highestEv = 4.026069; // 承认的最亮曝光。
    color = max(toWorking*color,vec3(1e-10)); // 取对数之前拒绝零与负值。
    color = clamp((log2(color)-lowestEv)/(highestEv-lowestEv),0.0,1.0); // 曝光归一到零至一。
    vec3 squared = color*color, fourth = squared*squared; // 曲线只使用偶次与奇次幂。
    color = 15.5*fourth*squared-40.14*fourth*color+31.96*fourth-6.868*squared*color+0.4298*squared+0.1191*color-0.00232; // 单调 S 曲线压缩高光。
    return clamp(fromWorking*color,0.0,1.0); // 回到显示原色并限制范围。
}
// 按选项选择压缩曲线：两种路径都在线性显示空间输出。
vec3 omniToneMap(vec3 color) {
#if OMNI_TONE_MAP == 1
    return omniToneMapAgx(color); // AgX 电影感高光。
#else
    return omniToneMapSimple(color); // 简单有理映射。
#endif
}
float omniExposure(vec2 uv) {
#ifdef OMNI_AUTO_EXPOSURE
    float mean = 0.0; // 使用真实场景亮度的对数均值。
    for (int y=0;y<3;y++) for (int x=0;x<3;x++) mean += log(max(omniLuminance(texture(colortex6,(vec2(x,y)+0.5)/3.0).rgb),0.001)); // 固定测光点不受当前像素变化。
    float target = clamp(0.18/exp(mean/9.0),0.25,8.0); // 防止曝光无限增大。
    float old = texture(colortex5,vec2(0.5)).g; // 上一帧曝光保存在普通历史像素。
    if (!omniHistoryValid()) return target*OMNI_EXPOSURE; // 新场景直接初始化。
    return mix(old,target*OMNI_EXPOSURE,1.0-exp(-clamp(frameTime,0.0,0.5)*1.5)); // 帧率无关的缓慢适应。
#else
    return OMNI_EXPOSURE; // 固定曝光无需测光采样。
#endif
}
vec3 omniColor(vec3 color, float exposure) {
    color *= exposure*OMNI_BRIGHTNESS; // 亮度与曝光独立配置。
    color *= exp(vec3(0.12,0.0,-0.12)*OMNI_WHITE_BALANCE); // 中性零值不偏色。
    color = max(color,vec3(0)); // 强光映射之前拒绝负值。
    color = omniToneMap(color); // 按选项映射高动态范围，保持单调不剪切。
    color = mix(vec3(omniLuminance(color)),color,OMNI_SATURATION); // 以亮度轴调整色彩。
    color = (color-0.5)*OMNI_CONTRAST+0.5; // 围绕中间亮度调整对比。
    return clamp(omniSrgb(clamp(color,0.0,1.0)),0.0,1.0); // 最终一步才编码到屏幕颜色。
}
#endif
