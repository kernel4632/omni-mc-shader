/* 层状体积云的步进目录：单层主步进、五层合成、两套低成本透过率与严格入口；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetVolumetricClouds(settings, viewPos, dither, sunVector, ...);`
设计取舍：五个子文件各管一个算法，函数体与采样顺序照参考保留；本文件只按原顺序引用，不复制算法。 */

// 单层主步进：五层共用同一套循环与光照。
#include "march/ray.slang"
// 五层合成：按参考顺序步进再按相机高度混合。
#include "march/compose.slang"
// 设置版低成本透射率：只累计透过率，供云影与远景使用。
#include "march/simple.slang"
// 参考签名版低成本透射率：天气与覆盖参数显式传入。
#include "march/transmittance.slang"
// 严格参考签名入口：只重排参数并填写参考默认常数。
#include "march/exact.slang"
