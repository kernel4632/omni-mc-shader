/*
世界与远景：给很远的几何加一点地球弧度，并控制远景光影与远景雾的衔接。

调用位置：
  rendering/distant.glsl 的顶点阶段调用 omniPlanetCurve，片元阶段读取 OMNI_DH_ENABLED 决定远景是否走完整光照；
  effects/fog.glsl 的 omniFog 读取 OMNI_DH_FOG_BLEND 抹平近远景交界的雾差。
可复制示例：`viewPosition = omniPlanetCurve(viewPosition);`

设计原因与取舍：行星曲率只按水平距离把远处的竖直位置压低，是一个廉价近似；
它不改变近景，也不做真实球面投影，所以只影响远景的观感，不会动到玩家脚下的地面。
远景开关关闭时，远景改为只按原版光照亮度上色，省掉阴影与高光，代价是远景和近景的观感略有差别。
*/
#ifndef OMNI_WORLD
#define OMNI_WORLD
// @effect {"label":{"zh_cn":"世界与远景","en_us":"World & distance"}}
// @option {"label":{"zh_cn":"远景开关","en_us":"Distant lighting"},"description":{"zh_cn":"关闭后很远的区块不再计算光影，只按原版亮度上色。","en_us":"When off, far chunks skip custom lighting and use vanilla brightness only."}}
#define OMNI_DH_ENABLED
// @option {"label":{"zh_cn":"远景雾衔接","en_us":"Distant fog blend"},"description":{"zh_cn":"在很远处额外加雾，抹平远景和近景交界的雾差；取零保持原状。","en_us":"Adds extra fog far away to hide the seam between near and distant fog; zero keeps it unchanged."},"slider":true}
#define OMNI_DH_FOG_BLEND 0.0 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label":{"zh_cn":"行星曲率","en_us":"Planet curvature"},"description":{"zh_cn":"远处地平线向下弯的强度；取零等于平地。","en_us":"How strongly the far horizon curves down; zero is flat."},"slider":true}
#define OMNI_PLANET_CURVATURE 0.0 // [0.0 0.25 0.5 0.75 1.0]
// 共用数学计算。
#include "/common/math.glsl"
// 行星曲率：水平距离越远，竖直位置压得越低；系数很小，只在远景可见。
vec3 omniPlanetCurve(vec3 viewPosition) {
    float horizontal = length(viewPosition.xz); // 到相机的水平距离，单位米。
    viewPosition.y -= horizontal * horizontal * OMNI_PLANET_CURVATURE * 2e-7; // 二次下沉，曲率取零时不改变位置。
    return viewPosition;
}
#endif
