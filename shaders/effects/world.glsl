/*
世界与远景：给很远的几何加地平线弧度，并控制远景光影与远景雾的衔接。

调用位置：
  rendering/distant.glsl 的顶点阶段调用 omniPlanetCurve，片元阶段读取 OMNI_DH_ENABLED 决定远景是否走完整光照；
  effects/fog.glsl 的 omniFog 读取 OMNI_DH_FOG_BLEND 抹平近远景交界的雾差。
可复制示例：`viewPosition = omniPlanetCurve(viewPosition);`

设计原因与取舍：
  行星曲率在世界空间里算：先把相机空间位置换回相机相对的世界位置，按水平距离往下沉，再换回相机空间。
  下沉量用球面的近似公式“水平距离的平方除以两倍半径”。放在世界空间里，相机低头抬头时地平线仍然向下弯。
  强度一对应半径两万米的小行星，远景两千米处约下沉一百米，看得出弧度；真实地球半径下几乎看不见。
  远景开关关闭时，远景改为只按原版光照亮度上色，省掉阴影与高光，代价是远景和近景的观感略有差别。
  防重复引入标记用 `_INCLUDED` 结尾，避免和程序宏或选项同名。
*/
#ifndef OMNI_WORLD_INCLUDED
#define OMNI_WORLD_INCLUDED
// @effect {"label":{"zh_cn":"世界与远景","en_us":"World & distance"}}
// @option {"label":{"zh_cn":"远景开关","en_us":"Distant lighting"},"description":{"zh_cn":"关闭后很远的区块不再计算光影，只按原版亮度上色。","en_us":"When off, far chunks skip custom lighting and use vanilla brightness only."}}
#define OMNI_DH_ENABLED
// @option {"label":{"zh_cn":"远景雾衔接","en_us":"Distant fog blend"},"description":{"zh_cn":"在近景和远景交界处补一圈雾，遮住接缝；更远的远景不受影响，取零保持原状。","en_us":"Adds a band of fog where near terrain meets distant terrain to hide the seam; farther terrain is unaffected, zero keeps it unchanged."},"slider":true}
#define OMNI_DH_FOG_BLEND 0.0 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label":{"zh_cn":"行星曲率","en_us":"Planet curvature"},"description":{"zh_cn":"远处地平线向下弯的强度；取零等于平地。","en_us":"How strongly the far horizon curves down; zero is flat."},"slider":true}
#define OMNI_PLANET_CURVATURE 0.0 // [0.0 0.25 0.5 0.75 1.0]
// 相机空间与世界空间的互相换算。
#include "/common/coordinates.glsl"
// 行星曲率：世界空间里按水平距离下沉，再换回相机空间；曲率取零时位置不变。
vec3 omniPlanetCurve(vec3 viewPosition) {
    vec3 world = omniWorld(viewPosition); // 相机相对的世界位置，竖直方向始终是真正的上下。
    world.y -= dot(world.xz, world.xz) * OMNI_PLANET_CURVATURE / (2.0 * 20000.0); // 球面近似：距离平方除以两倍半径，强度一相当于两万米半径。
    return (gbufferModelView * vec4(world, 1.0)).xyz; // 换回相机空间，交给远景投影。
}
#endif
