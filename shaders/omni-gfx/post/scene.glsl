/*
生成文件：画面效果模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
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
#include "/omni-gfx/common/math.glsl"
// 画面效果：受伤、入水、着火与血量上色。
// 子文件：post/scene/gameplay.slang。
// 画面效果子文件：受伤、入水与着火三种屏幕扭曲，以及血量上色。
// 调用位置：由 `post/scene.slang` 内联；需要复现 Eclipse `gameplay_effects.glsl` 的程序调用 `ogxGameplayEffects`。
// 设计原因与取舍：三种扭曲各自成一个函数，入口只按优先级取最大值；这样新增一种效果不必改另外两种的算式。
// 可复制示例：`ogxGameplayEffects(color, uv, noise, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0.0, 0.0, 0.0, 0.0, sceneTex, noiseTex, 1.777, frameTime, 1.0, 1.0);`

// 受伤扭曲：低血量按心跳做轻微缩放，暴击时放大；死亡状态直接给最强的暗角扭曲。
float ogxDamageDistortion(vec2 texcoord, float noise, float currentHealth, float maxHealth, // 当前步骤的中间量。
    float threeHeart, float criticalDamage, float motionAmount, float frameTime, // 当前步骤的中间量。
    bool lowHealthEffect, bool damageTakenEffect) // 按参考顺序推进。
{ // 按参考顺序推进。
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    float heartBeat = pow(sin(frameTime * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1; // 心跳频率。
    float damageDistortion = vignette * noise * heartBeat * threeHeart; // 低血量扭曲。
    damageDistortion = mix(damageDistortion, vignette * (0.5 + noise), criticalDamage) * motionAmount; // 暴击扭曲。
    return isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion; // 死亡优先。
} // 按参考顺序推进。

// 入水扭曲：镜头带水时读水珠噪声，入水时从中心向外推一圈波纹，两者取较大值。
float ogxWaterDistortion(vec2 texcoord, sampler2D noiseTexture, float aspectRatio,
    float exitWater, float enterWater, float isEyeInWater)
{
    float mask = 0.0; // 默认没有扭曲。
    if (exitWater > 0.0) // 镜头带水。
    {
        vec3 scale = vec3(1.0, 1.0, 0.0); // 水珠在屏幕上的缩放。
        bool eyeInWater = isEyeInWater == 1.0; // 眼睛是否在水里。
        scale.xy = (eyeInWater ? vec2(0.3) : vec2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * vec2(aspectRatio, 1.0);
        scale.z = eyeInWater ? 0.0 : exitWater; // 纵向偏移随出水进度增加。
        float waterDrops = textureLod(noiseTexture, (texcoord - vec2(0.0, scale.z)) * scale.xy, 0.0).r; // 水珠噪声。
        if (eyeInWater) waterDrops = 0.0; // 水下不显示水珠。
        if (isEyeInWater == 0.0 && exitWater > 0.0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3; // 出水水珠。
        mask = max(mask, waterDrops);
    }
    if (enterWater > 0.0) // 入水波纹。
    {
        vec2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0 - sqrt(1.0 - enterWater))); // 从中心向外推。
        float waterSplash = textureLod(noiseTexture, zoomTC * vec2(aspectRatio, 1.0), 0.0).r * (1.0 - enterWater); // 入水噪声。
        mask = max(mask, waterSplash);
    }
    return mask;
}

// 着火扭曲：底部火焰噪声随时间向上滚动，扭曲量随火焰强度与岩浆进度增加。
float ogxFireDistortion(vec2 texcoord, sampler2D noiseTexture, float aspectRatio,
    float frameTime, float fireStrength, float exitLava)
{
    vec2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - exitLava, 2.0)); // 底部放大。
    float flameDistort = textureLod(noiseTexture, zoomin * vec2(aspectRatio, 1.0) - vec2(0.0, frameTime * 0.3), 0.0).b
        * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * fireStrength * exitLava; // 火焰噪声。
    return flameDistort;
}

// 血量上色：低血量把边缘染红，受伤按暗角混红，死亡压成暗红亮度。
void ogxGameplayColor(inout vec3 color, vec3 distortedColor, float vignette,
    float oneHeart, float threeHeart, float criticalDamage, float minorDamage, bool isDead,
    bool lowHealthEffect, bool damageTakenEffect)
{
    vec3 distortedLuma = vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07)); // 红色亮度。
    if (lowHealthEffect) // 低血量。
    {
        float colorLuma = dot(color, vec3(0.21, 0.72, 0.07)); // 当前亮度。
        vec3 lumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 红色边缘。
        color = mix(color, lumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart)); // 按暗角与单心混合。
    }
    if (damageTakenEffect) // 受伤。
    {
        color = mix(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 小伤害。
        color = mix(color, distortedLuma, sqrt(criticalDamage)); // 暴击伤害。
    }
    if (isDead) color = distortedLuma * 0.35; // 死亡画面。
}

// 画面效果入口：三种扭曲按优先级取最大，再统一做一次场景缩放与血量上色。
void ogxGameplayEffects(inout vec3 color, vec2 texcoord, float noise,
    float currentHealth, float maxHealth, float oneHeart, float threeHeart,
    float criticalDamage, float minorDamage, bool lowHealthEffect, bool damageTakenEffect,
    bool waterOnCamera, bool fireDistort, float exitWater, float enterWater, float exitLava,
    float isEyeInWater, sampler2D sceneTexture, sampler2D noiseTexture, float aspectRatio,
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
    vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask); // 以中心缩放。
    vec3 distortedColor = textureLod(sceneTexture, zoomUV, 0.0).rgb; // 读扭曲后的场景。
    if ((waterOnCamera && exitWater > 0.01) || (fireDistort && exitLava > 0.01)) color = distortedColor; // 水或火覆盖时替换场景。
    ogxGameplayColor(color, distortedColor, vignette, oneHeart, threeHeart, criticalDamage, minorDamage, isDead,
        lowHealthEffect, damageTakenEffect); // 血量上色。
}

// 场景控制：把云层、密度与雾系数原样输出。
// 子文件：post/scene/controller.slang。
// 场景控制子文件：把菜单的云层覆盖、密度与雾系数原样抄到输出。
// 调用位置：由 `post/scene.slang` 内联；需要复现 Eclipse `scene_controller.glsl` 默认值的程序调用下面两个入口。
// 设计原因与取舍：这里没有算法，只有接口映射；单独成文件是为了让画面效果文件只留受伤、入水与着火。
// 可复制示例：`ogxSceneControllerDefaults(outSmallCoverage, outSmallDensity, outLargeCoverage, outLargeDensity, outAltostratusCoverage, outAltostratusDensity, outCirrusCoverage, outCirrusDensity, outFogA, outFogB);`

// 场景控制参数：没有自定义触发器时，把所有天气与云层参数原样输出。
void ogxSceneControllerParameters(float smallCumulusCoverage, float smallCumulusDensity,
    float largeCumulusCoverage, float largeCumulusDensity, float altostratusCoverage,
    float altostratusDensity, float cirrusCoverage, float cirrusDensity,
    out float outSmallCoverage, out float outSmallDensity, out float outLargeCoverage,
    out float outLargeDensity, out float outAltostratusCoverage, out float outAltostratusDensity,
    out float outCirrusCoverage, out float outCirrusDensity, out float fogA, out float fogB)
{
    outSmallCoverage = smallCumulusCoverage; // 小积云覆盖。
    outSmallDensity = smallCumulusDensity; // 小积云密度。
    outLargeCoverage = largeCumulusCoverage; // 大积云覆盖。
    outLargeDensity = largeCumulusDensity; // 大积云密度。
    outAltostratusCoverage = altostratusCoverage; // 高层云覆盖。
    outAltostratusDensity = altostratusDensity; // 高层云密度。
    outCirrusCoverage = cirrusCoverage; // 卷云覆盖。
    outCirrusDensity = cirrusDensity; // 卷云密度。
    fogA = 1.0; // 均匀雾倍率。
    fogB = 1.0; // 云雨雾倍率。
}

// 场景控制器的默认参数：把云层覆盖与密度写进输出，雾系数固定为一。
// 参考签名只有十个输出；库版本不再接收额外输入，直接给出参考默认值。
void ogxSceneControllerDefaults(out float smallCumulusCoverage, out float smallCumulusDensity,
    out float largeCumulusCoverage, out float largeCumulusDensity, out float altostratusCoverage,
    out float altostratusDensity, out float cirrusCoverage, out float cirrusDensity,
    out float fogA, out float fogB)
{
    smallCumulusCoverage = 1.0; // 默认满覆盖。
    smallCumulusDensity = 0.5; // 小积云中等密度。
    largeCumulusCoverage = 1.0; // 大积云满覆盖。
    largeCumulusDensity = 0.6; // 大积云略浓。
    altostratusCoverage = 0.6; // 高层云六成覆盖。
    altostratusDensity = 0.1; // 高层云很薄。
    cirrusCoverage = 0.07; // 卷云稀疏。
    cirrusDensity = 0.005; // 卷云几乎透明。
    fogA = 1.0; // 均匀雾倍率中性。
    fogB = 1.0; // 云雨雾倍率中性。
}

#endif
