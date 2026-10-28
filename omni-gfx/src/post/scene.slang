/*
Omni 通用图形库 Eclipse 场景补充模块：受伤与入水画面效果、场景控制参数、末地雾阴影。
调用位置：需要复现 Eclipse `gameplay_effects.glsl`、`scene_controller.glsl` 与 `end_fog.glsl` 的程序；
    Minecraft 光影由 `/omni-gfx/post/scene.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    `ogxGameplayEffects(color, uv, noise, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0.0, 0.0, 0.0, 0.0, sceneTex, noiseTex, 1.777, frameTime, 1.0, 1.0);` 把受伤与入水效果叠到颜色。
    `ogxSceneControllerDefaults(outSmallCoverage, outSmallDensity, outLargeCoverage, outLargeDensity, outAltostratusCoverage, outAltostratusDensity, outCirrusCoverage, outCirrusDensity, outFogA, outFogB);` 取参考默认云层参数。
设计原因与取舍：
    参考实现直接读血量、眼在水中、`colortex7` 与末地雾密度纹理。库把数值、纹理与尺寸改成显式参数，
    分支、常数与采样顺序保持不变；场景控制只是把输入默认值抄到输出，参数表来自菜单来源。
    末地雾阴影属于雾模块，本文件不复制它的采样，示例因此只列本文件定义的入口。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。画面效果入口目前只有探针覆盖，顶层画面仍由各效果文件分别处理。
*/
#ifndef OGX_POST_SCENE_INCLUDED
#define OGX_POST_SCENE_INCLUDED

// 数学提供夹紧与取模；颜色提供亮度权重。
#include "../common/math.slang"

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

// 受伤、入水与着火画面效果：先算屏幕扭曲，再按血量与伤害上色。
// 开关用布尔参数表示，避免库读取菜单宏；未开启的分支保持零贡献。
void ogxGameplayEffects(inout float3 color, float2 texcoord, float noise,
    float currentHealth, float maxHealth, float oneHeart, float threeHeart,
    float criticalDamage, float minorDamage, bool lowHealthEffect, bool damageTakenEffect,
    bool waterOnCamera, bool fireDistort, float exitWater, float enterWater, float exitLava,
    float isEyeInWater, Sampler2D sceneTexture, Sampler2D noiseTexture, float aspectRatio,
    float frameTime, float motionAmount, float fireStrength)
{
    bool isDead = currentHealth * maxHealth <= 0.0 && currentHealth > -1.0; // 血量归零。
    float distortMask = 0.0; // 屏幕扭曲量。
    float vignette = sqrt(clamp(dot(texcoord * 2.0 - 1.0, texcoord * 2.0 - 1.0) * 0.5, 0.0, 1.0)); // 暗角。
    if (lowHealthEffect || damageTakenEffect) // 低血量与受伤。
    {
        float heartBeat = pow(sin(frameTime * 15.0) * 0.5 + 0.5, 2.0) * 0.2 + 0.1; // 心跳。
        float damageDistortion = vignette * noise * heartBeat * threeHeart; // 低血量扭曲。
        damageDistortion = lerp(damageDistortion, vignette * (0.5 + noise), criticalDamage) * motionAmount; // 暴击扭曲。
        distortMask = isDead ? vignette * (0.7 + noise * 0.3) : damageDistortion; // 死亡扭曲。
    }
    if (waterOnCamera) // 出水与入水。
    {
        if (exitWater > 0.0) // 镜头带水。
        {
            float3 scale = float3(1.0, 1.0, 0.0);
            bool eyeInWater = isEyeInWater == 1.0;
            scale.xy = (eyeInWater ? float2(0.3) : float2(0.5, 0.25 + (exitWater * exitWater) * 0.25)) * float2(aspectRatio, 1.0);
            scale.z = eyeInWater ? 0.0 : exitWater;
            float waterDrops = noiseTexture.SampleLevel((texcoord - float2(0.0, scale.z)) * scale.xy, 0.0).r; // 水珠噪声。
            if (eyeInWater) waterDrops = 0.0;
            if (isEyeInWater == 0.0 && exitWater > 0.0) waterDrops = sqrt(min(max(waterDrops - (1.0 - sqrt(exitWater)) * 0.7, 0.0) * (1.0 + exitWater), 1.0)) * 0.3; // 出水水珠。
            distortMask = max(distortMask, waterDrops);
        }
        if (enterWater > 0.0) // 入水波纹。
        {
            float2 zoomTC = 0.5 + (texcoord - 0.5) * (1.0 - (1.0 - sqrt(1.0 - enterWater)));
            float waterSplash = noiseTexture.SampleLevel(zoomTC * float2(aspectRatio, 1.0), 0.0).r * (1.0 - enterWater);
            distortMask = max(distortMask, waterSplash);
        }
    }
    if (fireDistort && exitLava > 0.0) // 着火扭曲。
    {
        float2 zoomin = 0.5 + (texcoord - 0.5) * (1.0 - pow(1.0 - clamp(-texcoord.y * 0.5 + 0.75, 0.0, 1.0), 1.0)) * (1.0 - pow(1.0 - exitLava, 2.0));
        float flameDistort = noiseTexture.SampleLevel(zoomin * float2(aspectRatio, 1.0) - float2(0.0, frameTime * 0.3), 0.0).b
            * clamp(-texcoord.y * 0.3 + 0.3, 0.0, 1.0) * fireStrength * exitLava;
        distortMask = max(distortMask, flameDistort);
    }
    float2 zoomUV = 0.5 + (texcoord - 0.5) * (1.0 - distortMask); // 以中心缩放。
    float3 distortedColor = sceneTexture.SampleLevel(zoomUV, 0.0).rgb; // 读扭曲后的场景。
    if ((waterOnCamera && exitWater > 0.01) || (fireDistort && exitLava > 0.01)) color = distortedColor; // 水或火覆盖时替换场景。
    if (lowHealthEffect || damageTakenEffect) // 颜色效果。
    {
        float3 distortedLuma = float3(1.0, 0.0, 0.0) * dot(distortedColor, float3(0.21, 0.72, 0.07)); // 红色亮度。
        if (lowHealthEffect)
        {
            float colorLuma = dot(color, float3(0.21, 0.72, 0.07));
            float3 lumaRedEdges = lerp(float3(colorLuma), float3(1.0, 0.3, 0.3) * distortedLuma.r, vignette); // 红色边缘。
            color = lerp(color, lumaRedEdges, lerp(vignette * threeHeart, oneHeart, oneHeart)); // 低血量上色。
        }
        if (damageTakenEffect)
        {
            color = lerp(color, distortedLuma, vignette * sqrt(min(minorDamage, 1.0))); // 小伤害。
            color = lerp(color, distortedLuma, sqrt(criticalDamage)); // 暴击伤害。
        }
        if (isDead) color = distortedLuma * 0.35; // 死亡画面。
    }
}

// 场景控制器的默认参数：把云层覆盖与密度写进输出，雾系数固定为一。
// 参考签名只有十个输出；库版本不再接收额外输入，直接给出参考默认值。
void ogxSceneControllerDefaults(out float smallCumulusCoverage, out float smallCumulusDensity,
    out float largeCumulusCoverage, out float largeCumulusDensity, out float altostratusCoverage,
    out float altostratusDensity, out float cirrusCoverage, out float cirrusDensity,
    out float fogA, out float fogB)
{
    smallCumulusCoverage = 1.0;
    smallCumulusDensity = 0.5;
    largeCumulusCoverage = 1.0;
    largeCumulusDensity = 0.6;
    altostratusCoverage = 0.6;
    altostratusDensity = 0.1;
    cirrusCoverage = 0.07;
    cirrusDensity = 0.005;
    fogA = 1.0;
    fogB = 1.0;
}

/*
实现说明：画面效果与场景参数。
一、受伤效果：低血量与受伤时按心跳频率做屏幕扭曲，边缘红色随暗角增强。
二、入水与出水：水珠噪声按镜头带水程度缩放，入水波纹从中心向外推。
三、着火：底部火焰噪声按时间向上滚动，扭曲量随火焰强度增加。
四、死亡：血量归零时把画面压成红色亮度。
五、场景控制：没有自定义触发器时，把云层覆盖、密度与雾系数原样输出。
六、边界：血量、介质、纹理与画面比例全部显式传入，库不读取宿主状态。
七、顺序：先算扭曲再上色，最后按状态覆盖场景色。
*/
/*
函数索引：
一、`ogxSceneControllerParameters`：把云层覆盖、密度与雾系数原样输出。
二、`ogxGameplayEffects`：受伤、入水、着火与死亡的屏幕效果。
三、`ogxSceneControllerDefaults`：给出参考默认云层参数。
四、受伤：按心跳频率做扭曲，边缘红色随暗角增强。
五、入水与出水：水珠噪声按镜头带水程度缩放。
六、着火：底部火焰噪声按时间向上滚动。
七、死亡：血量归零时把画面压成红色亮度。
八、边界：血量、介质、纹理与画面比例全部显式传入。
九、顺序：先算扭曲再上色，最后按状态覆盖场景色。
*/
/*
参数与边界：
一、血量归一化到零到一，最大血量由调用方给出。
二、受伤强度与低血量开关分开，二者可以同时开启。
三、入水与出水的进度在零到一之间。
四、着火扭曲只在介质为岩浆时生效。
五、场景纹理与噪声纹理由调用方传入。
六、画面比例用于修正水珠与火焰的横向拉伸。
七、死亡状态优先于其它颜色效果。
八、所有效果只改颜色与坐标，不改深度。
九、顺序：先算扭曲再上色，最后覆盖场景色。
十、画面验证要看受伤、入水与着火三种状态。
*/
/*
补充说明：画面状态的优先级。
死亡颜色优先于低血量与受伤。
入水与着火可以同时存在，扭曲取较大值。
场景控制器只输出参数，不改颜色。
所有纹理与数值显式传入。
*/
#endif
