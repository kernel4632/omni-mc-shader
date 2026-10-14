#version 330 compatibility
// 生成的gbuffers_spidereyes入口：修改绘制主体与显式流程表。
// 选择本程序的绘制阶段或物体类别。
#define OMNI_FRAGMENT
// 选择本程序的绘制阶段或物体类别。
#define OMNI_EMISSIVE
// 选择本程序的绘制阶段或物体类别。
#define OMNI_OVERLAY
// 选择本程序的绘制阶段或物体类别。
#define OMNI_END
// 显式引入完整绘制主体。
#include "/rendering/terrain.glsl"
// 输出由主体按统一缓冲协议写入。
