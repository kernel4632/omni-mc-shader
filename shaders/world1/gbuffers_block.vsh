#version 330 compatibility
// 生成的gbuffers_block入口：修改绘制主体与显式流程表。
// 选择本程序的绘制阶段或物体类别。
#define OMNI_VERTEX 1
// 选择本程序的绘制阶段或物体类别。
#define OMNI_BLOCK_PASS 1
// 选择本程序的绘制阶段或物体类别。
#define OMNI_END 1
// 先引入本维度的中间画面与常量声明。
#include "/rendering/buffers_end.glsl"
// 显式引入完整绘制主体。
#include "/rendering/entities.glsl"
// 输出由主体按统一缓冲协议写入。
