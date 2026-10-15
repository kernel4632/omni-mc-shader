// 调色与曝光：把线性场景映射为显示颜色，并计算时间合成保存的曝光。
// 调用位置：最终显示与时间合成分别通过 "/effects/color.glsl" 引入，读取 colortex0、colortex5、colortex6。
// 可复制示例：`vec3 shown = omniColor(color, exposure);` 与 `float exposure = omniExposure(texcoord);`
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
// @option {"label":{"zh_cn":"有序抖动","en_us":"Ordered dither"},"description":{"zh_cn":"用四乘四阈值矩阵打散八位量化色带。","en_us":"A 4x4 ordered matrix breaks 8-bit color banding."}}
#define OMNI_DITHER 1 // [0 1]
// 曝光有效性与时间历史共用一个接口。
#include "/effects/antialiasing.glsl"
// 判断数值能否继续参与计算：NaN 与无穷都视为无效。
bool omniFinite(float value) { return !isnan(value) && !isinf(value); }
// 判断颜色能否继续参与计算：任一分量为无效值即整体无效。
bool omniFinite(vec3 color) { return !any(isnan(color)) && !any(isinf(color)); }
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
// 四乘四有序阈值矩阵：像素坐标取模后得到零到一的阈值。
float omniBayer(vec2 pixel) {
    const float thresholds[16] = float[16]( // 每个格子使用不同的量化阈值。
        0.0/16.0, 8.0/16.0, 2.0/16.0, 10.0/16.0,
        12.0/16.0, 4.0/16.0, 14.0/16.0, 6.0/16.0,
        3.0/16.0, 11.0/16.0, 1.0/16.0, 9.0/16.0,
        15.0/16.0, 7.0/16.0, 13.0/16.0, 5.0/16.0);
    int x = int(mod(pixel.x,4.0)); int y = int(mod(pixel.y,4.0)); // 像素落在四乘四格内。
    return thresholds[x+y*4]; // 返回当前格的有序阈值。
}
float omniExposure(vec2 uv) {
#ifdef OMNI_AUTO_EXPOSURE
    float sum = 0.0; // 九个测光点的对数亮度之和。
    for (int y=0;y<3;y++) for (int x=0;x<3;x++) sum += log(max(omniLuminance(texture(colortex6,(vec2(x,y)+0.5)/3.0).rgb),0.001)); // 固定测光点不受当前像素变化。
    if (!omniFinite(sum)) return OMNI_EXPOSURE; // 测光样本无效时回退到固定曝光，避免 NaN 扩散。
    float target = clamp(0.18/exp(sum/9.0),0.25,8.0); // 目标曝光限制在合理范围，防止无限增大。
    float old = texture(colortex5,vec2(0.5)).g; // 上一帧曝光保存在普通历史像素。
    if (!omniHistoryValid() || !omniFinite(old)) return target*OMNI_EXPOSURE; // 新场景或历史无效时直接初始化。
    return mix(old,target*OMNI_EXPOSURE,1.0-exp(-clamp(frameTime,0.0,0.5)*1.5)); // 帧率无关的缓慢适应。
#else
    return OMNI_EXPOSURE; // 固定曝光无需测光采样。
#endif
}
vec3 omniColor(vec3 color, float exposure) {
    if (!omniFinite(color) || !omniFinite(exposure)) return vec3(0.0); // 无效输入保守回退到黑色，避免异常扩散到整屏。
    color *= exposure*OMNI_BRIGHTNESS; // 亮度与曝光独立配置。
    color *= exp(vec3(0.12,0.0,-0.12)*OMNI_WHITE_BALANCE); // 中性零值不偏色。
    color = max(color,vec3(0)); // 强光映射之前拒绝负值。
    color = omniToneMap(color); // 按选项映射高动态范围，保持单调不剪切。
    color = mix(vec3(omniLuminance(color)),color,OMNI_SATURATION); // 以亮度轴调整色彩。
    color = (color-0.5)*OMNI_CONTRAST+0.5; // 围绕中间亮度调整对比。
    color = omniSrgb(clamp(color,0.0,1.0)); // 最终一步才编码到屏幕颜色。
#if OMNI_DITHER == 1
    color += (omniBayer(gl_FragCoord.xy)-0.5)/255.0; // 有序抖动打散八位量化色带。
#endif
    if (!omniFinite(color)) return vec3(0.0); // 溢出等浮点异常保守回退到黑色。
    return clamp(color,0.0,1.0); // 抖动之后仍限制在屏幕颜色范围。
}
#endif
