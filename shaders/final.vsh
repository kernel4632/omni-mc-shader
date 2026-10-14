#version 330 compatibility

/*
 * 最终画面：提供覆盖整个屏幕的位置和纹理坐标。
 * 调用方式：光影加载器在最终绘制阶段自动调用，与 final.fsh 配对。
 * 使用示例：将 Omni 放入 shaderpacks，在游戏中选择 Omni。
 */

#define OMNI_VERTEX // 标明这是最终绘制的顶点阶段。
// 固定入口交给明示的绘制流程；引用行不附加注释以兼容加载器。
#include "/rendering/final.glsl"
