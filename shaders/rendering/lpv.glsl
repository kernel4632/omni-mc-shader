// LPV 光传播体积：计算阶段初始化与传播，间接光阶段采样；示例 setup.csh 引入。
#ifndef OMNI_LPV_LIB
#define OMNI_LPV_LIB
const uint lpvSide = 16u; // 光照体积的边长，单位为体素格。
const uint lpvCount = lpvSide * lpvSide * lpvSide; // 单帧需要处理的单元总数。
#ifdef OMNI_COMPUTE
layout(local_size_x=8, local_size_y=8, local_size_z=8) in; // 计算阶段的三维工作组，一次覆盖一个切片。
layout(std430) buffer LpvCells { vec4 cells[]; } lpv; // 光照体积单元，索引按三维线性编号。
// 清空本帧光照体积：计算入口的第一步，片元阶段不调用。
void omniLpvClear() {
    uint index = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * lpvSide + gl_GlobalInvocationID.z * lpvSide * lpvSide; // 三维线性编号。
    if (index >= lpvCount) return; // 越界线程直接返回，避免越界写入。
    lpv.cells[index] = vec4(0.0); // 本帧从零开始累积。
}
void main() { omniLpvClear(); } // 计算入口本阶段只做帧初始化。
#endif
#endif
