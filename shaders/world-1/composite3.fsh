#version 330 compatibility
// 生成的composite3入口：修改绘制主体与显式流程表。
// 指定本入口在绘制的哪个阶段运行。
#define OMNI_FRAGMENT 1
// 指定本入口对应的绘制程序。
#define OMNI_COMPOSITE3_PASS 1
// 指定本入口所属维度，主体靠它选维度分支。
#define OMNI_NETHER 1
// 先引入本维度的中间画面与常量声明。
#include "/rendering/buffers_nether.glsl"
// 显式引入完整绘制主体。
#include "/rendering/composite_pass3.glsl"
// 输出由主体按统一缓冲协议写入。
