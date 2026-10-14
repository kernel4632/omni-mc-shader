#version 330 compatibility

/*
 * 最终画面：将已经绘制好的场景原样显示到屏幕。
 * 调用方式：光影加载器在最终绘制阶段自动调用，与 final.vsh 配对。
 * 使用示例：选择 Omni 后，这一步直接输出场景颜色。
 */

#define OMNI_FRAGMENT // 标明这是最终绘制的像素阶段。
// 固定入口交给明示的绘制流程；引用行不附加注释以兼容加载器。
#include "/rendering/final.glsl"
