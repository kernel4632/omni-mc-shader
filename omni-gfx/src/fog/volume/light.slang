/* 体积雾的闪电照明：把闪电当成一根竖直光柱，按距离做指数衰减；由 `fog/volume.slang` 内联引入。
可复制示例：`float3 light = ogxFogLightning(relativePos, media, 200.0, 4.0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 闪电照亮参与散射的介质：把闪电当成一根竖直光柱。
float3 ogxFogLightning(float3 relativePos, OgxFogMedia media, float lightDistance, float falloff)
{
    return ogxLightningGlow(relativePos, media.lightning_position, media.lightning_intensity,
        media.lightning_strength, lightDistance, falloff); // 光柱计算只在数学模块一份。
}

// 密度模型选择与沿光方向吸收，具体实现在子文件。
// --- step ---
