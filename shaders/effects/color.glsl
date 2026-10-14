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
// 曝光有效性与时间历史共用一个接口。
#include "/effects/antialiasing.glsl"
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
    color = color/(1.0+color); // 映射高动态范围，保持单调不剪切。
    color = mix(vec3(omniLuminance(color)),color,OMNI_SATURATION); // 以亮度轴调整色彩。
    color = (color-0.5)*OMNI_CONTRAST+0.5; // 围绕中间亮度调整对比。
    return clamp(omniSrgb(clamp(color,0.0,1.0)),0.0,1.0); // 最终一步才编码到屏幕颜色。
}
#endif
