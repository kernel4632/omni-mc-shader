// 画面效果子文件：受伤、入水与着火三种屏幕扭曲，以及血量上色。
// 调用位置：由 `post/scene.slang` 内联；需要复现 Eclipse `gameplay_effects.glsl` 的程序调用 `ogxGameplayEffects`。
// 设计原因与取舍：三种扭曲各自成一个函数，入口只按优先级取最大值；这样新增一种效果不必改另外两种的算式。
// 可复制示例：`ogxGameplayEffects(color, uv, noise, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0.0, 0.0, 0.0, 0.0, sceneTex, noiseTex, 1.777, frameTime, 1.0, 1.0);`

// 受伤扭曲：低血量按心跳做轻微缩放，暴击时放大；死亡状态直接给最强的暗角扭曲。
float ogxDamageDistortion(float2 texcoord, float noise, float currentHealth, float maxHealth, // 当前步骤的中间量。
    float threeHeart, float criticalDamage, float motionAmount, float frameTime, // 当前步骤的中间量。
    bool lowHealthEffect, bool damageTakenEffect) // 按参考顺序推进。
{ // 按参考顺序推进。
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    float heartBeat = pow(sin(frameTime * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1; // 心跳频率。
    float damageDistortion = vignette * noise * heartBeat * threeHeart; // 低血量扭曲。
    damageDistortion = lerp(damageDistortion, vignette * (0.5 + noise), criticalDamage) * motionAmount; // 暴击扭曲。
    return isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion; // 死亡优先。
} // 按参考顺序推进。

// 入水扭曲：镜头带水时读水珠噪声，入水时从中心向外推一圈波纹，两者取较大值。
float ogxWaterDistortion(float2 texcoord, Sampler2D noiseTexture, float aspectRatio,
    float exitWater, float enterWater, float isEyeInWater)
{
    float mask = 0.0; // 默认没有扭曲。
    if (exitWater > 0.0) // 镜头带水。
    {
        float3 scale = float3(1.0, 1.0, 0.0); // 水珠在屏幕上的缩放。
        bool eyeInWater = isEyeInWater == 1.0; // 眼睛是否在水里。
        scale.xy = (eyeInWater ? float2(0.3) : float2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * float2(aspectRatio, 1.0);
        scale.z = eyeInWater ? 0.0 : exitWater; // 纵向偏移随出水进度增加。
        float waterDrops = noiseTexture.SampleLevel((texcoord - float2(0.0, scale.z)) * scale.xy, 0.0).r; // 水珠噪声。
        if (eyeInWater) waterDrops = 0.0; // 水下不显示水珠。
        if (isEyeInWater == 0.0 && exitWater > 0.0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3; // 出水水珠。
        mask = max(mask, waterDrops);
    }
    if (enterWater > 0.0) // 入水波纹。
    {
        float2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0 - sqrt(1.0 - enterWater))); // 从中心向外推。
        float waterSplash = noiseTexture.SampleLevel(zoomTC * float2(aspectRatio, 1.0), 0.0).r * (1.0 - enterWater); // 入水噪声。
        mask = max(mask, waterSplash);
    }
    return mask;
}

// 着火扭曲：底部火焰噪声随时间向上滚动，扭曲量随火焰强度与岩浆进度增加。
float ogxFireDistortion(float2 texcoord, Sampler2D noiseTexture, float aspectRatio,
    float frameTime, float fireStrength, float exitLava)
{
    float2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - exitLava, 2.0)); // 底部放大。
    float flameDistort = noiseTexture.SampleLevel(zoomin * float2(aspectRatio, 1.0) - float2(0.0, frameTime * 0.3), 0.0).b
        * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * fireStrength * exitLava; // 火焰噪声。
    return flameDistort;
}

// 血量上色：低血量把边缘染红，受伤按暗角混红，死亡压成暗红亮度。
void ogxGameplayColor(inout float3 color, float3 distortedColor, float vignette,
    float oneHeart, float threeHeart, float criticalDamage, float minorDamage, bool isDead,
    bool lowHealthEffect, bool damageTakenEffect)
{
    float3 distortedLuma = float3(1.0, 0.0, 0.0) * dot(distortedColor, float3(0.21, 0.72, 0.07)); // 红色亮度。
    if (lowHealthEffect) // 低血量。
    {
        float colorLuma = dot(color, float3(0.21, 0.72, 0.07)); // 当前亮度。
        float3 lumaRedEdges = lerp(float3(colorLuma), float3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 红色边缘。
        color = lerp(color, lumaRedEdges, lerp(vignette * threeHeart, oneHeart, oneHeart)); // 按暗角与单心混合。
    }
    if (damageTakenEffect) // 受伤。
    {
        color = lerp(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 小伤害。
        color = lerp(color, distortedLuma, sqrt(criticalDamage)); // 暴击伤害。
    }
    if (isDead) color = distortedLuma * 0.35; // 死亡画面。
}

// 画面效果入口：三种扭曲按优先级取最大，再统一做一次场景缩放与血量上色。
void ogxGameplayEffects(inout float3 color, float2 texcoord, float noise,
    float currentHealth, float maxHealth, float oneHeart, float threeHeart,
    float criticalDamage, float minorDamage, bool lowHealthEffect, bool damageTakenEffect,
    bool waterOnCamera, bool fireDistort, float exitWater, float enterWater, float exitLava,
    float isEyeInWater, Sampler2D sceneTexture, Sampler2D noiseTexture, float aspectRatio,
    float frameTime, float motionAmount, float fireStrength)
{
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    float distortMask = 0.0; // 屏幕扭曲量。
    if (lowHealthEffect || damageTakenEffect) distortMask = ogxDamageDistortion(texcoord, noise, currentHealth, maxHealth,
        threeHeart, criticalDamage, motionAmount, frameTime, lowHealthEffect, damageTakenEffect); // 受伤优先。
    if (waterOnCamera) distortMask = max(distortMask, ogxWaterDistortion(texcoord, noiseTexture, aspectRatio,
        exitWater, enterWater, isEyeInWater)); // 入水其次。
    if (fireDistort && exitLava > 0.0) distortMask = max(distortMask, ogxFireDistortion(texcoord, noiseTexture,
        aspectRatio, frameTime, fireStrength, exitLava)); // 着火最后。
    float2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask); // 以中心缩放。
    float3 distortedColor = sceneTexture.SampleLevel(zoomUV, 0.0).rgb; // 读扭曲后的场景。
    if ((waterOnCamera && exitWater > 0.01) || (fireDistort && exitLava > 0.01)) color = distortedColor; // 水或火覆盖时替换场景。
    ogxGameplayColor(color, distortedColor, vignette, oneHeart, threeHeart, criticalDamage, minorDamage, isDead,
        lowHealthEffect, damageTakenEffect); // 血量上色。
}
