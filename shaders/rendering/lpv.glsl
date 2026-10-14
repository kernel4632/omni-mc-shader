// LPV 光传播体积计算：清空、注入与传播；示例 setup.csh 引入。
#ifndef OMNI_LPV_LIB // 防止重复引用造成重复声明。
#define OMNI_LPV_LIB // 标记本文件已经引入。
// 效果选项与采样映射来自效果主体。
#include "/effects/lpv.glsl"
#ifdef OMNI_COMPUTE // 只有计算阶段编译下面的入口。
layout(local_size_x=8, local_size_y=8, local_size_z=8) in; // 单一工作组覆盖整格，可用工作组屏障。
// 读取源图像的一个单元并夹紧到网格内，避免越界。
vec3 omniLpvReadA(ivec3 cell) {
#ifdef OMNI_LPV_ENABLED // 关闭时不做任何图像读取。
    return imageLoad(omniLpvA,clamp(cell,ivec3(0),ivec3(lpvSide-1))).rgb; // 边界重复自身。
#else // 关闭体积光时的安全回退。
    return vec3(0.0); // 不读取图像，返回零能量。
#endif // 结束读取分支。
}
// 读取目标图像的一个单元并夹紧到网格内。
vec3 omniLpvReadB(ivec3 cell) {
#ifdef OMNI_LPV_ENABLED // 关闭时不做任何图像读取。
    return imageLoad(omniLpvB,clamp(cell,ivec3(0),ivec3(lpvSide-1))).rgb; // 边界重复自身。
#else // 关闭体积光时的安全回退。
    return vec3(0.0); // 不读取图像，返回零能量。
#endif // 结束读取分支。
}
// 清空并注入：给每格写入方向光近似，作为传播起点。
void omniLpvSeed() {
#ifdef OMNI_LPV_ENABLED // 关闭时不写图像。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 light = vec3(0.0); // 没有几何数据时按方向光给基础能量。
#if !defined OMNI_NETHER && !defined OMNI_END // 其他维度没有主世界方向光。
    float height = 0.5 + 0.5 * omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition).y; // 天体高度。
    light = vec3(0.8,0.8,0.9) * height; // 直射光近似颜色。
#endif // 结束维度判断。
    imageStore(omniLpvA,cell,vec4(light*0.05,1.0)); // 初始能量写入源图像。
#endif // 结束注入分支。
}
// 正向传播一步：从源读取六邻居，写回目标。
void omniLpvSpreadAB() {
#ifdef OMNI_LPV_ENABLED // 关闭时不做传播。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 sum = omniLpvReadA(cell); // 自身先参与平均。
    sum += omniLpvReadA(cell+ivec3(1,0,0)) + omniLpvReadA(cell-ivec3(1,0,0)); // 左右邻居。
    sum += omniLpvReadA(cell+ivec3(0,1,0)) + omniLpvReadA(cell-ivec3(0,1,0)); // 上下邻居。
    sum += omniLpvReadA(cell+ivec3(0,0,1)) + omniLpvReadA(cell-ivec3(0,0,1)); // 前后邻居。
    imageStore(omniLpvB,cell,vec4(sum/7.0,1.0)); // 归一化后写入目标。
#endif // 结束正向传播分支。
}
// 反向传播一步：从目标读取六邻居，写回源图像。
void omniLpvSpreadBA() {
#ifdef OMNI_LPV_ENABLED // 关闭时不做传播。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 sum = omniLpvReadB(cell); // 自身先参与平均。
    sum += omniLpvReadB(cell+ivec3(1,0,0)) + omniLpvReadB(cell-ivec3(1,0,0)); // 左右邻居。
    sum += omniLpvReadB(cell+ivec3(0,1,0)) + omniLpvReadB(cell-ivec3(0,1,0)); // 上下邻居。
    sum += omniLpvReadB(cell+ivec3(0,0,1)) + omniLpvReadB(cell-ivec3(0,0,1)); // 前后邻居。
    imageStore(omniLpvA,cell,vec4(sum/7.0,1.0)); // 归一化后写回源图像。
#endif // 结束反向传播分支。
}
void main() {
#ifdef OMNI_LPV_ENABLED // 关闭时计算入口保持空实现。
    omniLpvSeed(); barrier(); // 先注入，再同步整格。
    for (int k=0;k<OMNI_LPV_STEPS;k++) { if (k%2==0) omniLpvSpreadAB(); else omniLpvSpreadBA(); barrier(); } // 偶数步后回到源图像，片元读取同一张。
#endif // 结束计算入口分支。
}
#endif // 结束计算阶段。
#endif // 结束文件守卫。
