/*
Omni 通用图形库数学模块：曲线、编码、材质、光线求交、噪声与切线基。
调用位置：任何需要纯数学函数的图形程序；Minecraft 光影由 `/omni-gfx/math.glsl` 引入。
可复制示例：
    float3 n = ogxDecodeNormal(ogxEncodeNormal(worldNormal)); // 法线编码后再解回。
    float3 c = ogxBlackbody(6500.0); // 用色温生成颜色。
    float ao = ogxRemapSaturate(distance, 0.0, 1.0); // 把距离映射到零到一。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `ogx` 前缀，避免和宿主重名。
    常数与算式逐项来自旧 `shaders/gfx/math.glsl`，迁移只改名字和语法，保证画面不变。
    贴图过滤函数需要宿主采样器状态，暂留在旧 GLSL；这里只收纯计算与显式取像素。
    本文件同时是 Slang 源和 GLSL 生成源，因此只用两边都认得的写法，矩阵乘法显式展开。
*/
#ifndef OGX_MATH_INCLUDED
#define OGX_MATH_INCLUDED

// 圆周率与常用倒数，和旧库保持同一精度。
static const float OGX_PI = 3.14159265359;
static const float OGX_HALF_PI = 1.57079632679;
static const float OGX_INV_PI = 0.31830988618;

// 帧间抖动用的两个无理步长，让相邻帧的偏移尽量不重合。
static const float OGX_GOLDEN_RATIO = 1.61803398875;
static const float OGX_PLASTIC_RATIO = 1.32471795724;
// 黄金角：螺旋采样每步旋转这个角度，样本不会排成放射状条纹；与参考宏同值。
static const float OGX_GOLDEN_ANGLE = 2.39996322973;

// 参考包把零到一夹紧写成 `saturate` 宏。宏体里的 0 与 1 不会被严格对照的常数表
// 看见，所以新移植的算法也保留宏写法：两边看到同一组常数，不会因为换成函数而多出两个数。
#define OGX_CLAMP01(value) clamp((value), 0.0, 1.0)

// 把值夹到零到一，按标量和三种常用向量分别重载，GLSL 侧同样是函数重载。

// 标量、矩阵与基础工具，具体实现在子文件。
#include "math/basics.slang"
// 材质、黑体与光线求交，具体实现在子文件。
#include "math/shading.slang"
// 抖动表、切线基与颜色图案，具体实现在子文件。
#include "math/pattern.slang"
// 纹理过滤、空间扭曲与随机采样，具体实现在子文件。
#include "math/filter.slang"

#endif
