/*
Omni 通用图形库层状体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud/layers.glsl` 引入。
可复制示例：
    OgxLayersCloudSettings s = ...; // 填云层高度、比例、覆盖与天气。
    float4 cloud = ogxLayersGetVolumetricClouds(viewPos, dither, sunVector, moonVector, ...);
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。层状体积云目前只有探针与 profile 覆盖，顶层云入口仍走体积云与平面云。
*/
#ifndef OGX_CLOUD_LAYERS_INCLUDED
#define OGX_CLOUD_LAYERS_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数，天空提供云的环境色查表。
#include "../common/math.slang"
// 云提供球面求交、密度与单层步进。
#include "cloud.slang"
// 天空提供云环境色、星空与日月圆盘。
#include "../atmosphere/sky.slang"

// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxLayersCloudLayer
{
    float height; // 云底高度，米。
    float tallness; // 云层厚度，米。
    float scale; // 世界坐标到云坐标的比例。
    float distance; // 这一层的可见距离，米。
    float coverage; // 云量，零到一。
    float rainDensity; // 雨天密度。
    float detail; // 高频侵蚀尺度。
};

// 体积云的全部环境输入：层数据、天气、太阳与闪电。
struct OgxLayersCloudSettings
{
    OgxLayersCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
    float cloudMovement; // 云的水平位移，米。
    float rainAmount; // 降雨强度。
    float thunderStrength; // 雷暴强度。
    float sunElevation; // 太阳高度角正弦。
    float moonElevation; // 月亮高度角正弦。
    float cumulonimbusStrength; // 积雨云强度。
    float distanceFogScale; // 距离雾的指数系数，通常为负。
    float skyBrightness; // 天空亮度。
    float lightningFlash; // 当前闪电亮度。
    float lightningFade; // 闪电衰减。
    float cumulonimbusLightningBrightness; // 积雨云闪电亮度。
    float auroraAmount; // 极光强度，零表示没有极光。
    float3 auroraLighting; // 极光颜色，调用方按自己的极光模型算好。
    float4 lightningBoltPosition; // 普通闪电位置，第四个分量是强度。
    float3 cumulonimbusLightningColor; // 积雨云闪电颜色。
    int cumulonimbus; // 是否启用积雨云，零关闭。
    int lightningEnabled; // 是否启用积雨云闪电。
};

// 哈希、噪声、逐层形状、积雨云与降雨加成，具体实现在子文件。
#include "layers/shape.slang"
// 行星阴影、云影、闪电落点与步进起点，具体实现在子文件。
#include "layers/shadow.slang"
// 云相函数、散射与光照，具体实现在子文件。
#include "layers/lighting.slang"
// 主体积云步进、低成本透过率与严格入口，具体实现在子文件。
#include "layers/ray.slang"
// 层状云合成提供五层顺序与相机高度混合。
#include "layers/compose.slang"
// 层状云低成本步进提供云影与远景透过率。
#include "layers/simple.slang"
// 层状云参考签名步进提供天气参数入口。
#include "layers/transmittance.slang"
// 层状云严格入口提供参考默认常数。
#include "layers/exact.slang"

#endif
