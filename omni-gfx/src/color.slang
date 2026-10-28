/*
Omni 通用图形库颜色模块：线性颜色、亮度、伽马、强光压缩、黑边与调色。
调用位置：任何需要把线性高动态范围颜色映射到显示空间或做最终调色的程序；
    Minecraft 光影由 `/omni-gfx/color.glsl` 引入，引入后数学模块同时可用。
可复制示例：
    float3 a = ogxAces(linearColor, true); // 影院标准压缩。
    float3 b = ogxAgx(linearColor, 13.0, true); // 宽色域压缩。
    float3 c = ogxTonemapNone(linearColor); // 只做伽马编码。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀。
    伽马使用二点二近似，与旧 `shaders/gfx/color.glsl` 一致，不在这里做分段标准曲线。
    矩阵乘法展开成三列乘分量再相加，保持与 GLSL 矩阵乘向量的求和顺序一致。
*/
#ifndef OGX_COLOR_INCLUDED
#define OGX_COLOR_INCLUDED

// 数学模块提供亮度权重、夹紧与编码函数。
#include "math.slang"

// 三列矩阵乘向量：GLSL 的矩阵乘向量就是三列分别乘分量再相加，这里照同一顺序展开。

// 伽马、基础色调映射与白平衡，具体实现在子文件。
#include "color/tonemap.slang"
// Eclipse，具体实现在子文件。
#include "color/agx.slang"

#endif
