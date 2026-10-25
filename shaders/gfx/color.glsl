/*
颜色模块适配层：伽马、亮度、ACES、AgX、高级调色、暗视觉、白平衡与饱和度矩阵已迁到生成库。
调用位置：`shaders/rendering/color/*`、`shaders/rendering/lens/*` 与其它适配层引用本文件；
    算式只在 `omni-gfx/src/color.slang` 一份。
可复制示例：`vec3 a = gfx_aces(linearColor, true);` 影院压缩，实现在生成库。
设计原因与取舍：函数名、参数顺序与就地修改的写法保持原样，调用点无需改动，默认画面不会漂移；
    亮度权重与伽马常数留在生成库，本文件不复制任何算式。
*/
#ifndef GFX_COLOR_INCLUDED
#define GFX_COLOR_INCLUDED

// 迁移后的颜色实现：伽马、压缩曲线、调色与暗视觉。
#include "/omni-gfx/color.glsl"

// 人眼亮度权重接到生成库的常量上，旧代码仍可读取这个数组。
#define GFX_LUMA_WEIGHTS OGX_LUMA_WEIGHTS

// 线性颜色转显示伽马空间。
vec3 gfx_linear_to_gamma(vec3 color){ return ogxLinearToGamma2(color); } // 实现在生成库。

// 显示伽马空间转回线性。
vec3 gfx_gamma_to_linear(vec3 color){ return ogxGammaToLinear2(color); } // 实现在生成库。

// 按人眼权重求亮度。
float gfx_luminance(vec3 color){ return ogxLuminance(color); } // 实现在生成库。

// ACES 压缩曲线里的有理式。
vec3 gfx_rrt_odt_fit(vec3 value){ return ogxRrtOdtFit(value); } // 实现在生成库。

// 影院标准 ACES 近似：转工作色域、压缩、再转回显示色域。
vec3 gfx_aces(vec3 color, bool abney){ return ogxAces(color, abney); } // 实现在生成库。

// AgX 对比度曲线，用六次多项式近似原查找表，省掉一张纹理。
vec3 gfx_agx_contrast(vec3 x){ return ogxAgxContrast(x); } // 实现在生成库。

// AgX 强光压缩：先把曝光夹进承认范围，再用 S 曲线成形。
vec3 gfx_agx(vec3 color, float ev, bool abney){ return ogxAgx(color, ev, abney); } // 实现在生成库。

// 无压缩：只做伽马编码，保留全部高光。
vec3 gfx_tonemap_none(vec3 color){ return ogxTonemapNone(color); } // 实现在生成库。

// 黑边：按目标宽高比在画面上下或左右画黑边。
float gfx_black_bar(vec2 coord, float aspect, float targetRatio){ return ogxBlackBar(coord, aspect, targetRatio); } // 实现在生成库。

// 浦肯野效应：亮度低于阈值时把颜色混向偏蓝的暗视觉。
// 生成库用返回值而不是就地修改，这里再写回调用方的变量，保持旧签名。
void gfx_purkinje(inout vec3 color, float threshold, float strength){ color = ogxPurkinje(color, threshold, strength); } // 实现在生成库。

// 白平衡：按调用方给的色温颜色乘在线性颜色上。
vec3 gfx_white_balance(vec3 color, vec3 tint){ return ogxWhiteBalance(color, tint); } // 实现在生成库。

// 高级调色：白光裁剪、亮度伽马与饱和度。
vec3 gfx_advanced_color(vec3 color, float lumaGamma, float whiteClip, float saturation, float gamma){ return ogxAdvancedColor(color, lumaGamma, whiteClip, saturation, gamma); } // 实现在生成库。

// 色相、饱和度、明度转回颜色。
vec3 gfx_hsv_to_rgb(vec3 c){ return ogxHsvToRgb(c); } // 实现在生成库。

// sRGB 到线性：照 Eclipse 的近似多项式。
vec3 gfx_srgb_to_linear(vec3 s){ return ogxSrgbToLinear(s); } // 实现在生成库。

// 饱和度矩阵：把颜色朝灰阶收或向外推，一为原色。
mat4 gfx_saturation_matrix(float saturation){ return ogxSaturationMatrix(saturation); } // 实现在生成库。

#endif
