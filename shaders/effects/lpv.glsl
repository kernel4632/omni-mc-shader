// LPV 光传播体积：计算阶段注入与传播，间接光阶段三线性采样；示例 omniLpvSample(volume, world)。
#ifndef OMNI_LPV
#define OMNI_LPV
// @effect {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"}}
// @option {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"},"description":{"zh_cn":"计算阶段在八乘八乘八体积格注入并传播间接光；缺少计算能力时回退屏幕空间间接光。","en_us":"Injects and propagates indirect light in an 8x8x8 grid; falls back to screen space without compute."}}
//#define OMNI_LPV_ENABLED
// @option {"label": {"zh_cn": "传播步数", "en_us": "Propagation steps"}, "description": {"zh_cn": "空气补光的精细度。", "en_us": "Detail of the volumetric light propagation."}, "values": {"2": {"zh_cn": "低", "en_us": "Low"}, "4": {"zh_cn": "中", "en_us": "Medium"}, "6": {"zh_cn": "高", "en_us": "High"}}}
#define OMNI_LPV_STEPS 2 // [2 4 6]
// @option {"label": {"zh_cn": "体积光强度", "en_us": "LPV strength"}, "slider": true, "description": {"zh_cn": "空气补光多亮。", "en_us": "How bright the volumetric light is."}}
#define OMNI_LPV_STRENGTH 0.5 // [0.25 0.5 1.0]
// 相机位置由统一加载器输入提供。
#include "/common/uniforms.glsl"
// 方向归一化等共用计算由数学模块提供。
#include "/common/math.glsl"
const int lpvSide = 8; // 体积格每边单元数，与计算工作组一致。
const float lpvCellSize = 4.0; // 每个单元覆盖的世界格数。
// 体积格原点单元：以相机所在单元为中心，让体积跟随玩家。
vec3 omniLpvOrigin() { return floor(cameraPosition / lpvCellSize) - 0.5 * float(lpvSide); }
// 世界位置到体积归一化坐标：计算注入与片元采样共用同一映射。
vec3 omniLpvUvw(vec3 world) {
    vec3 cell = floor((world + cameraPosition) / lpvCellSize); // 当前世界单元编号。
    return (cell - omniLpvOrigin() + 0.5) / float(lpvSide); // 单元中心归一化到零至一。
}
// 三线性采样体积间接光：越界返回零，片元阶段使用。
vec3 omniLpvSample(sampler3D volume, vec3 world) {
    vec3 uvw = omniLpvUvw(world); // 归一化体积坐标。
    if (any(lessThan(uvw,vec3(0.0))) || any(greaterThan(uvw,vec3(1.0)))) return vec3(0.0); // 网格外没有体积光。
    return texture(volume,uvw).rgb; // 硬件三线性插值。
}
// 采样共享的块名与阶段可见性：计算写入，其余只读；缺少自定义图像能力时整段不声明，计算阶段写入也跳过。
#if defined OMNI_COMPUTE && defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES
layout(rgba8) uniform image3D omniLpvA; // 传播源与片元读取。
layout(rgba8) uniform image3D omniLpvB; // 传播目标。
#endif
#endif
