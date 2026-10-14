/*
 * 最终绘制：读取场景与调试数据，输出屏幕颜色。
 * 调用位置：final.vsh 和 final.fsh，通过 OMNI_VERTEX / OMNI_FRAGMENT 区分。
 * 引入示例：#define OMNI_FRAGMENT 后 #include "/rendering/final.glsl"
 */

#ifdef OMNI_VERTEX
out vec2 texcoord; // 将画面坐标传给像素绘制。

// --- 覆盖整个屏幕 ---
void main() {
    gl_Position = ftransform(); // 使用加载器提供的屏幕四边形。
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy; // 保留加载器的纹理变换。
}
#endif

#ifdef OMNI_FRAGMENT
uniform sampler2D colortex0; // 已绘制好的场景颜色。
uniform sampler2D depthtex0; // 加载器提供的场景深度。
in vec2 texcoord; // 对应屏幕上的采样位置。
layout(location = 0) out vec4 color; // 最终屏幕颜色。

// 引入开发用显示选择及其选项。
#include "/effects/debug.glsl"

// --- 读取场景并选择最终显示 ---
void main() {
    vec4 scene = texture(colortex0, texcoord); // 保留场景颜色和透明度。
#if OMNI_DEBUG_VIEW == 1
    float depth = texture(depthtex0, texcoord).r; // 只在观察深度时增加深度读取。
#else
    float depth = 0.0; // 其他视图编译时省去深度纹理采样。
#endif
    color = vec4(debugColor(scene.rgb, depth, texcoord), scene.a); // 显示所选数据。
}
#endif
