/*
Omni 通用图形库 Eclipse 场景补充模块：受伤与入水画面效果、场景控制参数。
调用位置：需要复现 Eclipse `gameplay_effects.glsl` 与 `scene_controller.glsl` 的程序；
    Minecraft 光影由 `/omni-gfx/post/scene.glsl` 引入，后续由 `post/post` 引入并编译。
可复制示例：
    `ogxGameplayEffects(color, uv, noise, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0.0, 0.0, 0.0, 0.0, sceneTex, noiseTex, 1.777, frameTime, 1.0, 1.0);` 把受伤与入水效果叠到颜色。
    `ogxSceneControllerDefaults(outSmallCoverage, outSmallDensity, outLargeCoverage, outLargeDensity, outAltostratusCoverage, outAltostratusDensity, outCirrusCoverage, outCirrusDensity, outFogA, outFogB);` 取参考默认云层参数。
设计原因与取舍：
    参考实现直接读血量、眼在水中、`colortex7` 与末地雾密度纹理。库把数值、纹理与尺寸改成显式参数，
    分支、常数与采样顺序保持不变；场景控制只是把输入默认值抄到输出，参数表来自菜单来源。
    画面效果按受伤、入水、着火拆成三个小函数，入口只按优先级取最大值；场景控制另放子文件，
    这样打开任一文件都只看到一类职责。
*/
#ifndef OGX_POST_SCENE_INCLUDED
#define OGX_POST_SCENE_INCLUDED

// 数学提供夹紧与取模；颜色提供亮度权重。
#include "../common/math.slang"

// 画面效果：受伤、入水、着火与血量上色。
#include "scene/gameplay.slang"
// 场景控制：把云层、密度与雾系数原样输出。
#include "scene/controller.slang"

// 画面效果入口：三种扭曲按优先级取最大，再统一做一次场景缩放与血量上色。
// 为什么入口留在主文件：三种扭曲的公共顺序（受伤优先、入水其次、着火最后）是这一层的职责，
// 子文件只保留各自的算式；改动优先级时只需要看这一处。
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

#endif
