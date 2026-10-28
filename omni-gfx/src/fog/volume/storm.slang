/* 体积雾的暴风密度：噪声雾团与低空层相加，雪暴才随高度变淡；由 `fog/volume.slang` 内联引入。
可复制示例：`float density = ogxFogStormDensity(worldPos, media, noiseTexture);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 暴风浓雾：噪声雾团与低空层相加，雪暴才随高度变淡。
float ogxFogStormDensity(float3 worldPos, OgxFogMedia media, Sampler2D noiseTexture)
{
    float3 scroll = float3(media.storm_time, 0.0, media.storm_time) * 15.0; // 随时间在横纵方向滚动。
    float3 samplePos = (worldPos * float3(1.0, 1.0 / 48.0, 1.0) - scroll) * 100.0; // 纵向压扁、乘一百再减滚动量。
    float noise = 1.0 - ogxStormNoise(samplePos, noiseTexture, 512.0); // 取反，让噪声高的地方雾更浓。
    float heightFade = exp2(-0.06 * max(worldPos.y - (media.storm_height + 3.0), 0.0)); // 起始高度以上缓慢变淡。
    float denseCloud = noise * noise * lerp(1.0, heightFade, media.snow_storm); // 噪声雾团。
    return 1.0 + denseCloud + media.daily_fog; // 低空层与噪声雾团相加。
}

// 闪电光柱照明，具体实现在子文件。
// --- light ---
