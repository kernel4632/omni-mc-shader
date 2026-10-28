/*
Omni 通用图形库全局光模块：地平线遮蔽、反射阴影图反弹、历史重投影、时间与空间滤波。
调用位置：任何需要屏幕空间全局光或环境遮蔽的程序；Minecraft 光影由 `/omni-gfx/gi/gi.glsl` 引入。
可复制示例：
    `float ao = ogxGroundTruthAo(viewPos, viewDir, normal, coord, aspect, depthTex, dhTex, projection, projectionInverse, dhInverse, params, noise);` 一帧的地平线遮蔽。
    `vec3 bounce = ogxAoMultiBounce(ao, albedo);` 给遮蔽补一次多弹射。
    `vec3 filtered = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);` 七乘七空间滤波。
设计原因与取舍：
    纹理、矩阵、相机位置与选项全部由调用方传入，库不读取引擎状态；`OgxGiView` 把同一帧的
    相机与屏幕参数打包，避免每个函数重复十几项。算法与旧 `shaders/gfx/gi.glsl` 逐项一致，
    迁移只改名字和语法，默认画面因此不变；地平线遮蔽的采样仍由调用方负责，这里只做纯数学。
*/
#ifndef OGX_GI_INCLUDED
#define OGX_GI_INCLUDED

// 饱和、快速反余弦、曲线编码与噪声来自数学模块；阴影投影来自阴影模块。
#include "../math.slang"
#include "../shadow/shadow.slang"
#include "../sampling.slang"

// 螺旋采样的黄金角正余弦：每步旋转这个角度，样本沿螺旋均匀铺开。
// 黄金角旋转由数学模块的 OGX_GOLDEN_ANGLE 提供，和参考宏同值。

// 一帧全局光需要的相机、投影与屏幕参数；字段名保持普通图形术语，不绑定任何宿主。
struct OgxGiView
{
    float4x4 projection_inverse; // 近景逆投影。
    float4x4 previous_projection; // 上一帧投影。
    float4x4 model_view_inverse; // 视空间转世界。
    float4x4 previous_model_view; // 上一帧世界转视空间。
    float4x4 model_view; // 本帧世界转视空间。
    float4x4 shadow_view; // 阴影相机视图。
    float4x4 shadow_projection; // 阴影相机投影。
    float4x4 dh_projection_inverse; // 远景逆投影；没有远景时填近景值占位。
    float3x3 shadow_normal; // 法线从世界转到阴影相机。
    float3 camera_position; // 本帧相机世界位置。
    float3 previous_camera_position; // 上一帧相机世界位置。
    float2 screen_size; // 画面像素尺寸。
    float2 texel_size; // 一个像素的屏幕坐标大小。
};

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。

// 地平线遮蔽、反射阴影图与 GTAO，具体实现在子文件。
#include "gi/ao.slang"
// 相机速度与时间滤波，具体实现在子文件。
#include "gi/temporal.slang"
// 空间滤波与降噪，具体实现在子文件。
#include "gi/spatial.slang"

#endif
