/*
LPV 计算入口：清空、注入并双缓冲传播光传播体积，是 Omni 自己的额外功能。
调用位置：各维度的 `setup.csh` 定义 `OMNI_COMPUTE` 后引入本文件；选项与坐标映射来自 `effects/lighting/lpv.glsl`。
可复制示例：无（计算程序由 `rendering/programs.json` 的 `compute` 段登记，入口由构建生成）。
设计原因与取舍：
    一个工作组覆盖整格，所以可以用工作组屏障同步双缓冲的两张图像；
    关闭体积光或缺少自定义图像能力时，整段保持空实现，由 `effects/lighting/ambient.glsl` 的屏幕空间路径接管。
*/
// LPV 光传播体积的计算入口：清空、注入和双缓冲传播。
// 调用位置：各维度的 setup.csh 定义 OMNI_COMPUTE 后引入本文件。
// 设计原因：每轮传播先写入一张图像，再用图像内存屏障和工作组屏障让下一轮读到完整结果。
// 设计取舍：这里只负责计算阶段，不改变 LPV 的选项、体积坐标或缓冲协议；没有计算阶段时由 ambient.glsl 保留屏幕空间路径。
#ifndef OMNI_LPV_LIB // 防止重复引用造成重复声明。
#define OMNI_LPV_LIB // 标记本文件已经引入。
// 效果选项与采样映射来自效果主体。
#include "/effects/lighting/lpv.glsl"
#ifdef OMNI_COMPUTE // 只有计算阶段编译下面的入口。
layout(local_size_x=8, local_size_y=8, local_size_z=8) in; // 单一工作组覆盖整格，可用工作组屏障。
// 读取源图像的一个单元并夹紧到网格内，避免越界。
vec3 omniLpvReadA(ivec3 cell) {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时不做任何图像读取。
    return imageLoad(omniLpvA,clamp(cell,ivec3(0),ivec3(lpvSide-1))).rgb; // 边界重复自身。
#else // 关闭体积光时的安全回退。
    return vec3(0.0); // 不读取图像，返回零能量。
#endif // 结束读取分支。
}
// 读取目标图像的一个单元并夹紧到网格内。
vec3 omniLpvReadB(ivec3 cell) {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时不做任何图像读取。
    return imageLoad(omniLpvB,clamp(cell,ivec3(0),ivec3(lpvSide-1))).rgb; // 边界重复自身。
#else // 关闭体积光时的安全回退。
    return vec3(0.0); // 不读取图像，返回零能量。
#endif // 结束读取分支。
}
// 清空并注入：给每格写入方向光近似，作为传播起点。
void omniLpvSeed() {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时不写图像。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 light = vec3(0.0); // 没有几何数据时按方向光给基础能量。
#if !defined OMNI_NETHER && !defined OMNI_END // 其他维度没有主世界方向光。
    float height = 0.5 + 0.5 * omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition).y; // 天体高度。
    light = vec3(0.8,0.8,0.9) * height; // 直射光近似颜色。
#endif // 结束维度判断。
    imageStore(omniLpvA,cell,vec4(light*0.05,1.0)); // 把方向光近似写入传播源，作为后续每轮扩散的起点。
    memoryBarrierImage(); // 先提交图像写入，避免同一工作组后续读取到旧的源数据。
    barrier(); // 再同步整个工作组，保证所有单元都完成初次注入后才开始读取。
#endif // 结束注入分支。
}
// 正向传播一步：从源读取六邻居，写回目标。
void omniLpvSpreadAB() {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时不做传播。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 sum = omniLpvReadA(cell); // 自身先参与平均。
    sum += omniLpvReadA(cell+ivec3(1,0,0)) + omniLpvReadA(cell-ivec3(1,0,0)); // 左右邻居。
    sum += omniLpvReadA(cell+ivec3(0,1,0)) + omniLpvReadA(cell-ivec3(0,1,0)); // 上下邻居。
    sum += omniLpvReadA(cell+ivec3(0,0,1)) + omniLpvReadA(cell-ivec3(0,0,1)); // 前后邻居。
    imageStore(omniLpvB,cell,vec4(sum/7.0,1.0)); // 把源图像的七个位置平均后写入目标图像。
    memoryBarrierImage(); // 先让目标图像写入对工作组可见，再允许主流程同步所有工作项。
    barrier(); // 再同步整个工作组，保证下一轮不会读到尚未写完的目标图像。
#endif // 结束正向传播分支。
}
// 反向传播一步：从目标读取六邻居，写回源图像。
void omniLpvSpreadBA() {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时不做传播。
    ivec3 cell = ivec3(gl_GlobalInvocationID); // 当前单元。
    vec3 sum = omniLpvReadB(cell); // 自身先参与平均。
    sum += omniLpvReadB(cell+ivec3(1,0,0)) + omniLpvReadB(cell-ivec3(1,0,0)); // 左右邻居。
    sum += omniLpvReadB(cell+ivec3(0,1,0)) + omniLpvReadB(cell-ivec3(0,1,0)); // 上下邻居。
    sum += omniLpvReadB(cell+ivec3(0,0,1)) + omniLpvReadB(cell-ivec3(0,0,1)); // 前后邻居。
    imageStore(omniLpvA,cell,vec4(sum/7.0,1.0)); // 把目标图像的七个位置平均后写回源图像。
    memoryBarrierImage(); // 先提交回写结果，避免下一轮再次读取到上一轮的旧源数据。
    barrier(); // 再同步整个工作组，保证双缓冲轮换时源图像已经完整更新。
#endif // 结束反向传播分支。
}
void main() {
#if defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES // 关闭时计算入口保持空实现。
    omniLpvSeed(); // 初次注入函数内部已经按图像屏障、工作组屏障的顺序完成同步。
    for (int k=0;k<OMNI_LPV_STEPS;k++) { if (k%2==0) omniLpvSpreadAB(); else omniLpvSpreadBA(); } // 每轮函数内部完成双缓冲传播和同步，奇偶轮次交替使用两张图像。
#endif // 结束计算入口分支。
}
#endif // 结束计算阶段。
#endif // 结束文件守卫。
