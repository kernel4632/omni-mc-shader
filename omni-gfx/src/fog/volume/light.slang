/* 体积雾的闪电照明：把闪电当成一根竖直光柱，按距离做指数衰减；由 `fog/volume.slang` 内联引入。
可复制示例：`float3 light = ogxFogLightning(relativePos, media, 200.0, 4.0);`
设计取舍：没有闪电事件时返回零，冷色闪光再乘事件强度与亮度选项。 */

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
float3 ogxFogLightning(float3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    if (media.lightning_intensity <= 0.0) return float3(0.0); // 没有闪电事件时不加。
    float3 boltPos = float3(media.lightning_position.x, clamp(relativePos.y, media.lightning_position.y, media.lightning_position.y + 116.0), media.lightning_position.z); // 光柱同一水平位置。
    float boltDistance = length(relativePos - boltPos); // 介质采样点到光柱的距离。
    float lightningLight = max(1.0 - boltDistance / lightDistance, 0.0); // 照明范围内线性衰减。
    lightningLight = exp((1.0 - lightningLight) * falloff); // 换成更集中的指数衰减。
    return float3(0.55, 0.65, 0.9) * (lightningLight * media.lightning_intensity * media.lightning_strength); // 冷色闪光。
}
