/*
生物与玩家：给实体受光统一调亮度与色温，并给手持物做一个整体缩放。

调用位置：
  rendering/terrain.glsl 的 omniShadeSurface：对实体颜色调用 omniEntityLight；
  rendering/terrain.glsl 的顶点阶段：对手持物裁剪坐标调用 omniHandZoom。
可复制示例：`lit = omniEntityLight(lit);` 与 `gl_Position = omniHandZoom(gl_Position);`

设计原因与取舍：只改整块生物与手持物的亮度、色温和大小，不做逐生物局部光；
这样接入简单、任何资源包和模组都不受影响，代价是做不到单个生物单独调。
*/
#ifndef OMNI_ENTITY
#define OMNI_ENTITY
// @effect {"label":{"zh_cn":"生物与玩家","en_us":"Mobs & player"}}
// @option {"label":{"zh_cn":"生物受光强度","en_us":"Mob light strength"},"slider":true}
#define OMNI_ENTITY_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"生物色温","en_us":"Mob light tint"},"description":{"zh_cn":"正值生物受光偏暖、负值偏冷，零保持中性。","en_us":"Positive warms the light on mobs, negative cools it, zero stays neutral."},"slider":true}
#define OMNI_ENTITY_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"手持物大小","en_us":"Held item size"},"description":{"zh_cn":"让手里拿的东西整体变大；取零等于不缩放。","en_us":"Scales held items up or down; zero disables scaling."},"slider":true}
#define OMNI_HAND_SIZE 0.0 // [0.0 0.1 0.2 0.3 0.5]
// 归一化等共用计算来自数学模块。
#include "/common/math.glsl"
// 生物受光：整体乘一个强度，再按色温偏移红蓝通道，绿色不动。
vec3 omniEntityLight(vec3 lit) {
    lit *= OMNI_ENTITY_STRENGTH; // 生物整体更亮或更暗。
    return lit * vec3(1.0 + 0.2 * OMNI_ENTITY_TINT, 1.0, 1.0 - 0.2 * OMNI_ENTITY_TINT); // 色温偏移，取零保持中性。
}
// 手持物缩放：把裁剪坐标的横纵按大小选项放大，零等于原样。
vec4 omniHandZoom(vec4 clip) {
    clip.xy *= 1.0 + OMNI_HAND_SIZE; // 大于零放大，取零保持不变。
    return clip;
}
#endif
