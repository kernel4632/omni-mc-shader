/*
生物与玩家：给实体受光统一调亮度与色温，调整手持物视野，并控制玩家发光效果在光影下的显示。

调用位置：
  rendering/terrain.glsl 的 omniShadeSurface：对实体颜色调用 omniEntityLight，发光实体再调用 omniGlow；
  rendering/terrain.glsl 的顶点阶段：对手持物裁剪坐标调用 omniHandZoom。
可复制示例：`lit = omniEntityLight(lit);`、`lit = omniGlow(lit, albedo);` 与 `gl_Position = omniHandZoom(gl_Position);`

设计原因与取舍：只改整块生物与手持物的亮度、色温、视野和发光强弱，不做逐生物局部光；
这样接入简单、任何资源包和模组都不受影响，代价是做不到单个生物单独调。
*/
#ifndef OMNI_ENTITY
#define OMNI_ENTITY
// @effect {"label":{"zh_cn":"生物与玩家","en_us":"Mobs & player"}}
// @option {"label":{"zh_cn":"生物受光强度","en_us":"Mob light strength"},"slider":true}
#define OMNI_ENTITY_LIGHT 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"生物色温","en_us":"Mob light tint"},"description":{"zh_cn":"正值生物受光偏暖、负值偏冷，零保持中性。","en_us":"Positive warms the light on mobs, negative cools it, zero stays neutral."},"slider":true}
#define OMNI_ENTITY_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"手持物视野","en_us":"Held item FOV"},"description":{"zh_cn":"手里物品看起来多大；七十是原版大小，数值越小物品越大。","en_us":"How large held items appear; 70 is the vanilla size, smaller values look bigger."},"slider":true}
#define OMNI_HAND_FOV 70.0 // [30.0 50.0 70.0 90.0 120.0]
// @option {"label":{"zh_cn":"玩家发光遮盖","en_us":"Glow effect"},"description":{"zh_cn":"发光效果在光影下有多明显；取零时发光实体按普通受光显示。","en_us":"How strongly the glowing effect shows; zero makes glowing entities render as normal lit."},"slider":true}
#define OMNI_PLAYER_GLOW 0.5 // [0.0 0.25 0.5 0.75 1.0]
// 归一化等共用计算来自数学模块。
#include "/common/math.glsl"
// 生物受光：整体乘一个强度，再按色温偏移红蓝通道，绿色不动。
vec3 omniEntityLight(vec3 lit) {
    lit *= OMNI_ENTITY_LIGHT; // 生物整体更亮或更暗。
    return lit * vec3(1.0 + 0.2 * OMNI_ENTITY_TINT, 1.0, 1.0 - 0.2 * OMNI_ENTITY_TINT); // 色温偏移，取零保持中性。
}
// 玩家发光遮盖：把普通受光颜色朝发光色靠拢，取零等于发光效果不生效。
vec3 omniGlow(vec3 lit, vec3 albedo) {
    return mix(lit, albedo * 2.5, OMNI_PLAYER_GLOW); // 取零时保持普通受光，取一时按自身颜色明显发光。
}
// 手持物缩放的参照视野是七十度；视野越小物品越大，等于原版时缩放是一。
vec4 omniHandZoom(vec4 clip) {
    clip.xy *= 70.0 / max(OMNI_HAND_FOV, 1.0); // 三十度约放大两倍多，一百二十度缩到约六成。
    return clip;
}
#endif
