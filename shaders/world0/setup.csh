#version 430
// 生成的setup入口：修改绘制主体与显式流程表。
// 选择本程序的绘制阶段或物体类别。
#define OMNI_COMPUTE
// 显式引入完整绘制主体。
#include "/rendering/lpv.glsl"
// 输出由主体按统一缓冲协议写入。
