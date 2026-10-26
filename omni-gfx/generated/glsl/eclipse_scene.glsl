/*
生成文件：Eclipse 场景模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 场景补充模块：受伤与入水画面效果、场景控制参数、末地雾阴影。
调用位置：需要复现 Eclipse `gameplay_effects.glsl`、`scene_controller.glsl` 与 `end_fog.glsl` 的程序；
    Minecraft 光影由 `/omni-gfx/eclipse_scene.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    ogxEclipseApplyGameplayEffects(color, texCoord, 0.5, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, false, false,
        sceneTex, noiseTex, 1.777, 20.0, 1.0, 1.0, 0.0);
    ogxEclipseApplySceneControllerParameters(...);
    float shadow = ogxEclipseGetEndFogShadow(worldPos, lightPos, fogShapeTex, 1.0);
设计原因与取舍：
    参考实现直接读血量、眼在水中、`colortex7` 与末地雾密度纹理。库把数值、纹理与尺寸改成显式参数，
    分支、常数与采样顺序保持不变；场景控制只是把输入默认值抄到输出，参数表来自菜单来源。
*/
#ifndef OGX_ECLIPSE_SCENE_INCLUDED
#define OGX_ECLIPSE_SCENE_INCLUDED

// 数学提供夹紧与取模；颜色提供亮度权重。
#include "/omni-gfx/math.glsl"
// 场景控制参数：没有自定义触发器时，把所有天气与云层参数原样输出。
void ogxEclipseApplySceneControllerParameters(float smallCumulusCoverage, float smallCumulusDensity,
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

// 末地雾阴影：沿光源方向取三个密度样本，再按指数衰减成阴影。
float ogxEclipseGetEndFogShadow(vec3 worldPos, vec3 lightPos, sampler3D fogShape, float endStormDensity)
{
    float shadow = 0.0; // 密度累加。
    for (int i = 0; i < 3; i++) // 三个样本。
    {
        vec3 samplePos = worldPos - lightPos * (0.01 + pow(float(i), 0.75) * 0.25); // 参考实现的偏移。
        shadow += textureLod(fogShape, samplePos, 0.0).r * endStormDensity; // 取雾密度。
    }
    return clamp(exp2(shadow * -10.0), 0.0, 1.0); // 参考实现的衰减。
}

// 受伤、入水与着火画面效果：先算屏幕扭曲，再按血量与伤害上色。
// 开关用布尔参数表示，避免库读取菜单宏；未开启的分支保持零贡献。
void ogxEclipseApplyGameplayEffects(inout vec3 color, vec2 texcoord, float noise,
    float currentHealth, float maxHealth, float oneHeart, float threeHeart,
    float criticalDamage, float minorDamage, bool lowHealthEffect, bool damageTakenEffect,
    bool waterOnCamera, bool fireDistort, float exitWater, float enterWater, float exitLava,
    float isEyeInWater, sampler2D sceneTexture, sampler2D noiseTexture, float aspectRatio,
    float frameTime, float motionAmount, float fireStrength)
{
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float distortMask = 0.0; // 屏幕扭曲量。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    if (lowHealthEffect || damageTakenEffect) // 低血量与受伤。
    {
        float heartBeat = pow(sin(frameTime * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1; // 心跳。
        float damageDistortion = vignette * noise * heartBeat * threeHeart; // 低血量扭曲。
        damageDistortion = mix(damageDistortion, vignette * (0.5 + noise), criticalDamage) * motionAmount; // 暴击扭曲。
        distortMask = isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion; // 死亡扭曲。
    }
    if (waterOnCamera) // 出水与入水。
    {
        if (exitWater > 0.0) // 镜头带水。
        {
            vec3 scale = vec3(1.0, 1.0, 0.0);
            bool eyeInWater = isEyeInWater == 1.0;
            scale.xy = (eyeInWater ? vec2(0.3) : vec2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * vec2(aspectRatio, 1.0);
            scale.z = eyeInWater ? 0.0 : exitWater;
            float waterDrops = textureLod(noiseTexture, (texcoord - vec2(0.0, scale.z)) * scale.xy, 0.0).r; // 水珠噪声。
            if (eyeInWater) waterDrops = 0.0;
            if (isEyeInWater == 0.0 && exitWater > 0.0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3; // 出水水珠。
            distortMask = max(distortMask, waterDrops);
        }
        if (enterWater > 0.0) // 入水波纹。
        {
            vec2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0 - sqrt(1.0 - enterWater)));
            float waterSplash = textureLod(noiseTexture, zoomTC * vec2(aspectRatio, 1.0), 0.0).r * (1.0 - enterWater);
            distortMask = max(distortMask, waterSplash);
        }
    }
    if (fireDistort && exitLava > 0.0) // 着火扭曲。
    {
        vec2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - exitLava, 2.0));
        float flameDistort = textureLod(noiseTexture, zoomin * vec2(aspectRatio, 1.0) - vec2(0.0, frameTime * 0.3), 0.0).b
            * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * fireStrength * exitLava;
        distortMask = max(distortMask, flameDistort);
    }
    vec2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask); // 以中心缩放。
    vec3 distortedColor = textureLod(sceneTexture, zoomUV, 0.0).rgb; // 读扭曲后的场景。
    if ((waterOnCamera && exitWater > 0.01) || (fireDistort && exitLava > 0.01)) color = distortedColor; // 水或火覆盖时替换场景。
    if (lowHealthEffect || damageTakenEffect) // 颜色效果。
    {
        vec3 distortedLuma = vec3(1.0, 0.0, 0.0) * dot(distortedColor, vec3(0.21, 0.72, 0.07)); // 红色亮度。
        if (lowHealthEffect)
        {
            float colorLuma = dot(color, vec3(0.21, 0.72, 0.07));
            vec3 lumaRedEdges = mix(vec3(colorLuma), vec3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 红色边缘。
            color = mix(color, lumaRedEdges, mix(vignette * threeHeart, oneHeart, oneHeart)); // 低血量上色。
        }
        if (damageTakenEffect)
        {
            color = mix(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 小伤害。
            color = mix(color, distortedLuma, sqrt(criticalDamage)); // 暴击伤害。
        }
        if (isDead) color = distortedLuma * 0.35; // 死亡画面。
    }
}

#endif
