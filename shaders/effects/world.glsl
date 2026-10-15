/*
世界与远景：给很远的几何加一点地球弧度，让远处地平线自然下沉。

调用位置：rendering/distant.glsl 的顶点阶段，在算出视空间位置、投影之前调用 omniPlanetCurve。
可复制示例：`viewPosition = omniPlanetCurve(viewPosition);`

设计原因与取舍：只按水平距离把远处的竖直位置压低，是一个廉价近似；
它不改变近景，也不做真实球面投影，所以只影响远景的观感，不会动到玩家脚下的地面。
*/
#ifndef OMNI_WORLD
#define OMNI_WORLD
// @effect {"label":{"zh_cn":"世界与远景","en_us":"World & distance"}}
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
