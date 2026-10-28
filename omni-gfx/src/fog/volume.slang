/*
Omni 通用图形库体积雾模块：密度、阳光方向吸收、沿视线步进、闪电、暴风、群系与云影。
调用位置：任何需要体积雾的程序；Minecraft 光影由 `/omni-gfx/fog/volume.glsl` 引入，
    `rendering/fog/volumetric.glsl` 只把选项、天气、群系与阴影贴图换成参数。
可复制示例：先填好一层雾的参数，再调用一次 `ogxVolumetricFog` 完成整段步进。
设计原因与取舍：
    纹理、阴影矩阵、相机、光色与选项全部由调用方传入，库不读取宿主状态。
    雾照明与水下手持光属于可选的宿主能力，用两个钩子宏留给效果层注入；不定义时是完全的空操作。
    钩子宏沿用旧名字：宿主在包含本文件之前就定义它们，改名需要同时改宿主，收益只有名字统一。
    步进顺序与常数照 iterationT 原程序保留，保证默认画面不变。
    算法按主体拆进 `fog/volume/` 的八个子文件：云影、暴风、闪电、单步、主体、水下、严格入口与下界烟。
*/
#ifndef OGX_FOG_VOLUME_INCLUDED
#define OGX_FOG_VOLUME_INCLUDED

// 可选的雾照明钩子：效果层在包含本文件前定义，不定义时完全为空。
// 它接受当前雾点、这一步的吸收量、累计颜色与提前结束标记，由宿主决定是否采样体积光。
#ifndef GFX_FOG_LPV_STEP
#define GFX_FOG_LPV_STEP(fog_pos, integral, accum, done)
#endif

// 可选的水下手持光钩子：效果层把物品光采样接到这里，不定义时不加任何光。
#ifndef GFX_UNDERWATER_HAND_LIGHT
#define GFX_UNDERWATER_HAND_LIGHT(world_pos) float3(0.0)
#endif

// 雾密度、相位与粉末效应来自雾模块；暴风噪声来自天气，波法线与阴影坐标来自水面与阴影模块。
#include "fog.slang"
#include "../weather/weather.slang"
#include "../shadow/shadow.slang"
#include "../water.slang"
#include "../color.slang"
#include "../sampling.slang"

// 一帧体积雾需要的相机、光照与天气参数。
struct OgxFogMedia
{
    float3 camera_position; // 相机绝对世界位置。
    float3 light_vector; // 指向光源的单位向量。
    float3 light_color; // 直射光色。
    float3 sky_color; // 天空环境光色。
    float3 storm_color; // 暴风染色。
    float3 biome_color; // 群系雾色。
    float3 lightning_position; // 闪电光柱中心，相机相对坐标。
    float4x4 shadow_view; // 阴影相机视图。
    float4x4 shadow_projection; // 阴影相机投影。
    float2 cloud_shadow_screen; // 云影贴图所在画面的尺寸。
    float2 cloud_shadow_texel; // 云影贴图画面的像素大小。
    float wetness; // 零到一的湿润度。
    float eye_skylight; // 天空光平滑值。
    float time_midnight; // 午夜强度。
    float time_factor; // 雾的时间因子。
    float density_scale; // 时段与每日天气给出的密度标度。
    float base_density; // 基础密度，已由效果层按远裁剪面或远景距离换算。
    float storm_strength; // 雪暴与沙暴的总强度。
    float snow_storm; // 雪暴强度，决定暴风雾是否随高度变淡。
    float daily_fog; // 每日天气的匀雾密度。
    float storm_density; // 暴风雾浓度选项。
    float storm_height; // 暴风雾起始高度。
    float storm_time; // 暴风噪声的滚动时间，单位秒。
    float wind_time; // 团雾随风移动的时间，已按云速换算。
    float global_cloud_shadow; // 整个场景共用的粗粒度云影。
    float shadow_map_resolution; // 阴影图像素边长。
    float shadow_bias; // 阴影坐标边缘压缩强度。
    float cloud_shadow_range; // 云影贴图覆盖范围，米。
    float cloud_shadow_tex_size; // 云影贴图最大边长。
    float rain_shadow; // 雨天的云影底值。
    float biome_coverage; // 落在已启用群系内的程度。
    float biome_height; // 群系高度衰减雾密度。
    float biome_cloudy; // 群系团雾密度。
    float lightning_intensity; // 闪电事件强度。
    float lightning_strength; // 闪电亮度选项。
    float sky_intensity; // 天光强度选项。
    float sun_intensity; // 阳光强度选项。
    float fog_density_option; // 环境雾强度选项。
    float sun_density_option; // 散射强度选项。
};

// 云影贴图的三次采样与世界坐标投影，具体实现在子文件。
#include "volume/shadow.slang"
// 暴风浓雾密度，具体实现在子文件。
#include "volume/storm.slang"
// 闪电光柱照明，具体实现在子文件。
#include "volume/light.slang"
// 密度模型选择与沿光方向吸收，具体实现在子文件。
#include "volume/step.slang"
// 体积雾主体步进，具体实现在子文件。
#include "volume/march.slang"
// 水下焦散与光柱，具体实现在子文件。
#include "volume/underwater.slang"
// 严格参考签名入口，具体实现在子文件。
#include "volume/exact.slang"
// 下界三段体积雾，具体实现在子文件。
#include "volume/nether.slang"

#endif
