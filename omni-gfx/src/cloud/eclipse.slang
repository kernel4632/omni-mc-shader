/*
Omni 通用图形库 Eclipse 体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要 Eclipse 风格层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud/eclipse.glsl` 引入。
可复制示例：
    OgxEclipseCloudSettings s = ...; // 填云层高度、比例、覆盖与天气。
    float4 cloud = ogxEclipseGetVolumetricClouds(viewPos, dither, sunVector, moonVector, ...);
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
*/
#ifndef OGX_CLOUD_ECLIPSE_INCLUDED
#define OGX_CLOUD_ECLIPSE_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数，天空提供云的环境色查表。
#include "../math.slang"
#include "cloud.slang"
#include "../atmosphere/sky.slang"

// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxEclipseCloudLayer
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
struct OgxEclipseCloudSettings
{
    OgxEclipseCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
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

// 二维哈希：把格坐标打散成两个零到一的随机数。

// 哈希、噪声与五层云形状，具体实现在子文件。
#include "eclipse/shape.slang"
// 闪电、行星与云影，具体实现在子文件。
#include "eclipse/shadow.slang"
// 云相函数、散射与光照，具体实现在子文件。
#include "eclipse/lighting.slang"
// 主体积云步进与简化版本，具体实现在子文件。
#include "eclipse/march.slang"
// 云层密度、形状层与采样，具体实现在子文件。
#include "eclipse/layers.slang"
// 精确步进的吸收与透过率，具体实现在子文件。
#include "eclipse/exact.slang"

#endif
