/*
生成文件：手持光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库手持光模块：把玩家手持光源与手电筒照到表面，并给出高光。
调用位置：需要动态手持光照的程序；Minecraft 光影由 `/omni-gfx/heldlight.glsl` 引入。
可复制示例：
    vec3 held = ogxHeldLighting(viewPos, viewDir, normal, 0.4, ao, false, ...);
    ogxTorchSpecularHighlight(color, viewPos, viewDir, dist, albedo, normal, material, ...);
设计原因与取舍：
    参考实现用编译期开关选择手电筒或火把两种模型。库把开关变成显式参数，两条公式都保留，
    调用方按自己的设置走其中一条，不会因缺少宏而得到另一种画面。
    屏幕空间阴影、投影矩阵、光色与强度全部显式传入；模块本身不读取任何相机或世界状态。
*/
#ifndef OGX_HELDLIGHT_INCLUDED
#define OGX_HELDLIGHT_INCLUDED

// 表面模块提供手电筒光斑与指向，阴影模块提供屏幕空间阴影，数学与颜色模块提供漫反射、高光与色彩转换。
#include "/omni-gfx/surface.glsl"
#include "/omni-gfx/shadow/shadow.glsl"
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/color.glsl"
// 手电筒模型的手持光：两个光源分别位于左右手，按光斑、距离衰减与漫反射累加。
// `aimDir` 是光束指向，`heldLightShadow` 为真时每个光斑再乘屏幕空间阴影。
vec3 ogxHeldLightingSpot(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    float heldBlockLightValue, float heldBlockLightValue2, vec3 aimDir, vec3 lightColor, float brightness,
    float posRX, float posRY, float posLX, float posLY, float fov, float falloff, bool overworld, bool heldLightShadow,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise, bool hasDh, int shadowSteps)
{
    float heldLightFalloff = 0.0; // 两个光源累加后的强度。
    if (isHand) // 手部不参与光束，只给一个很弱的底光。
    {
        heldLightFalloff = 0.01 * max(heldBlockLightValue, heldBlockLightValue2); // 参考实现的固定系数。
    }
    else
    {
        if (heldBlockLightValue > 0.0) // 右手光源。
        {
            vec3 spotPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源在视空间的位置。
            float spotDistR = length(spotPosR); // 到光源的距离。
            vec3 shadowDirR = spotPosR / spotDistR; // 从光源指向表面的方向。
            float spotR = pow(max(spotDistR, 0.6), -falloff); // 距离衰减，近处限幅避免爆亮。
            spotR *= ogxSpotShape(dot(shadowDirR, aimDir), fov); // 乘光斑形状。
            if (heldLightShadow) // 开关打开才采样屏幕空间阴影。
            {
                spotR *= ogxScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirR, depthTexture, dhDepthTexture,
                    projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                    shadowSteps, 0.85); // 强度零点八五与参考的乘零点八五加零点一五一致。
            }
            spotR *= ogxDiffuseBurley(normal, -viewDir, -shadowDirR, roughness) * 1.7 + 0.05; // 漫反射权重。
            heldLightFalloff += heldBlockLightValue * spotR; // 按光源等级累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手光源。
        {
            vec3 spotPosL = viewPos - vec3(posLX, posLY, 0.0); // 左手位置。
            float spotDistL = length(spotPosL); // 到光源距离。
            vec3 shadowDirL = spotPosL / spotDistL; // 光源到表面方向。
            float spotL = pow(max(spotDistL, 0.6), -falloff); // 距离衰减。
            spotL *= ogxSpotShape(dot(shadowDirL, aimDir), fov); // 光斑形状。
            if (heldLightShadow) // 同样可开阴影。
            {
                spotL *= ogxScreenSpaceShadow(viewPos, viewDir, normal, -shadowDirL, depthTexture, dhDepthTexture,
                    projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                    shadowSteps, 0.85); // 与右手相同。
            }
            spotL *= ogxDiffuseBurley(normal, -viewDir, -shadowDirL, roughness) * 1.7 + 0.05; // 漫反射权重。
            heldLightFalloff += heldBlockLightValue2 * spotL; // 累加左手贡献。
        }
    }
    float scale = overworld ? 0.02 : 0.2; // 下界末地放大十倍。
    return lightColor * (ao * 0.5 + 0.5) * (heldLightFalloff * (brightness * scale)); // 乘遮蔽与整体亮度。
}

// 火把模型的手持光：光源贴近相机，用距离曲线给一个柔和球状光。
// 开启阴影时按左右手分别做屏幕空间阴影与漫反射，否则只按相机距离衰减。
vec3 ogxHeldLightingTorch(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    float heldBlockLightValue, float heldBlockLightValue2, vec3 lightColor, float brightness,
    float posRX, float posRY, float posLX, float posLY, float falloff, bool overworld, bool heldLightShadow,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projectionInverse,
    mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise, bool hasDh, int shadowSteps)
{
    float heldLightFalloff = 0.0; // 累加强度。
    if (isHand) // 手部只给弱底光。
    {
        heldLightFalloff = 0.2 * max(heldBlockLightValue, heldBlockLightValue2); // 参考实现的固定系数。
    }
    else if (heldLightShadow) // 开阴影时左右手分别计算。
    {
        if (heldBlockLightValue > 0.0) // 右手。
        {
            vec3 torchPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源位置。
            float torchDistR = length(torchPosR); // 距离。
            torchDistR += 4.0 / (torchDistR + 2.0); // 近处的软核，避免距离趋于零时过亮。
            float torchR = pow(torchDistR, -falloff); // 距离衰减。
            vec3 shadowDirR = -normalize(viewPos - vec3(posRX, posRY, 0.0)); // 光源到表面方向。
            torchR *= ogxScreenSpaceShadow(viewPos, viewDir, normal, shadowDirR, depthTexture, dhDepthTexture,
                projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                shadowSteps, 0.85); // 屏幕空间阴影。
            torchR *= ogxDiffuseBurley(normal, -viewDir, shadowDirR, roughness) * 1.7 + 0.05; // 漫反射。
            heldLightFalloff += heldBlockLightValue * torchR; // 累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手。
        {
            vec3 torchPosL = viewPos - vec3(posLX, posLY, 0.0); // 光源位置。
            float torchDistL = length(torchPosL); // 距离。
            torchDistL += 4.0 / (torchDistL + 2.0); // 近处软核。
            float torchL = pow(torchDistL, -falloff); // 距离衰减。
            vec3 shadowDirL = -normalize(viewPos - vec3(posLX, posLY, 0.0)); // 光源到表面方向。
            torchL *= ogxScreenSpaceShadow(viewPos, viewDir, normal, shadowDirL, depthTexture, dhDepthTexture,
                projection, projectionInverse, dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh,
                shadowSteps, 0.85); // 屏幕空间阴影。
            torchL *= ogxDiffuseBurley(normal, -viewDir, shadowDirL, roughness) * 1.7 + 0.05; // 漫反射。
            heldLightFalloff += heldBlockLightValue2 * torchL; // 累加。
        }
    }
    else // 没开阴影时用相机距离的解析衰减。
    {
        float torchDist = length(viewPos); // 到相机距离。
        torchDist += 4.0 / (torchDist + 2.0); // 近处软核。
        heldLightFalloff = pow(torchDist, -falloff); // 距离衰减。
        heldLightFalloff *= ogxDiffuseBurley(normal, -viewDir, -viewDir, roughness) + 0.3; // 漫反射加固定底光。
        heldLightFalloff *= heldBlockLightValue + heldBlockLightValue2; // 两个光源等级相加。
    }
    float scale = overworld ? 0.0015 : 0.015; // 下界末地放大十倍。
    return lightColor * (ao * 0.5 + 0.5) * (heldLightFalloff * (brightness * scale)); // 乘遮蔽与亮度。
}

// 手持光总入口：按 `heldLightMode` 在两种参考模型之间选择，两条路径都不丢参数。
vec3 ogxHeldLighting(vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, vec3 ao, bool isHand,
    int heldLightMode, float heldBlockLightValue, float heldBlockLightValue2, vec3 aimDir, vec3 lightColor,
    float brightness, float posRX, float posRY, float posLX, float posLY, float fov, float falloff, bool overworld,
    bool heldLightShadow, sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection,
    mat4 projectionInverse, mat4 dhProjectionInverse, float pixelScale, vec2 offsetCoord, float noise,
    bool hasDh, int shadowSteps)
{
    if (heldLightMode > 0) // 手电筒模型。
    {
        return ogxHeldLightingSpot(viewPos, viewDir, normal, roughness, ao, isHand, heldBlockLightValue,
            heldBlockLightValue2, aimDir, lightColor, brightness, posRX, posRY, posLX, posLY, fov, falloff,
            overworld, heldLightShadow, depthTexture, dhDepthTexture, projection, projectionInverse,
            dhProjectionInverse, pixelScale, offsetCoord, noise, hasDh, shadowSteps); // 走光斑路径。
    }
    return ogxHeldLightingTorch(viewPos, viewDir, normal, roughness, ao, isHand, heldBlockLightValue,
        heldBlockLightValue2, lightColor, brightness, posRX, posRY, posLX, posLY, falloff, overworld,
        heldLightShadow, depthTexture, dhDepthTexture, projection, projectionInverse, dhProjectionInverse,
        pixelScale, offsetCoord, noise, hasDh, shadowSteps); // 走火把路径。
}

// 手持光高光：手电筒模型按光斑给镜面高光，火把模型按相机距离给一个柔和镜面。
// `materialRoughness` 会先夹到零点零零二，避免完全光滑时的高光除零。
void ogxTorchSpecularHighlight(inout vec3 color, vec3 viewPos, vec3 viewDir, float dist, vec3 albedo,
    vec3 normal, float materialRoughness, float materialF0, int heldLightMode, float heldBlockLightValue,
    float heldBlockLightValue2, vec3 aimDir, vec3 lightColor, float brightness, float posRX, float posRY,
    float posLX, float posLY, float fov, float falloff, bool overworld)
{
    materialRoughness = max(materialRoughness, 0.002); // 参考实现的粗糙度下限。
    if (heldLightMode > 0) // 手电筒模型。
    {
        float heldHighlight = 0.0; // 高光累加。
        if (heldBlockLightValue > 0.0) // 右手。
        {
            vec3 spotPosR = viewPos - vec3(posRX, posRY, 0.0); // 光源位置。
            float spotDistR = length(spotPosR); // 距离。
            vec3 shadowDirR = spotPosR / spotDistR; // 光源到表面方向。
            float spotR = pow(max(spotDistR, 0.6), -falloff); // 距离衰减。
            spotR *= ogxSpotShape(dot(shadowDirR, aimDir), fov); // 光斑形状。
            spotR *= ogxSpecularGGX(normal, -viewDir, -shadowDirR, materialRoughness, materialF0); // 镜面高光。
            heldHighlight += heldBlockLightValue * spotR; // 累加。
        }
        if (heldBlockLightValue2 > 0.0) // 左手。
        {
            vec3 spotPosL = viewPos - vec3(posLX, posLY, 0.0); // 光源位置。
            float spotDistL = length(spotPosL); // 距离。
            vec3 shadowDirL = spotPosL / spotDistL; // 光源到表面方向。
            float spotL = pow(max(spotDistL, 0.6), -falloff); // 距离衰减。
            spotL *= ogxSpotShape(dot(shadowDirL, aimDir), fov); // 光斑形状。
            spotL *= ogxSpecularGGX(normal, -viewDir, -shadowDirL, materialRoughness, materialF0); // 镜面高光。
            heldHighlight += heldBlockLightValue2 * spotL; // 累加。
        }
        if (heldHighlight > 0.001) // 只有明显高光才写回颜色。
        {
            float scale = overworld ? 0.0025 : 0.025; // 下界末地放大十倍。
            color += lightColor * albedo * (heldHighlight * (brightness * scale)); // 叠到颜色上。
        }
    }
    else // 火把模型。
    {
        float heldHighlight = ogxSpecularGGX(normal, -viewDir, -viewDir, materialRoughness, materialF0); // 视线方向的镜面。
        if (heldHighlight > 0.001) // 明显高光才继续。
        {
            dist += 4.0 / (dist + 2.0); // 近处软核。
            heldHighlight *= pow(dist, -falloff); // 距离衰减。
            heldHighlight *= (heldBlockLightValue + heldBlockLightValue2); // 两个光源等级相加。
            float scale = overworld ? 0.0002 : 0.002; // 下界末地放大十倍。
            color += lightColor * albedo * (heldHighlight * (brightness * scale)); // 叠到颜色上。
        }
    }
}

// Eclipse 手持光：从方块光表的一维图里读颜色与范围，再按距离三次方衰减。
// 参考用 `imgBlockData` 的 imageLoad 与内置的 unpackUnorm4x8；库把方块光表作为
// 一维只读纹理传入，并按同样的字节顺序手工拆包，避免依赖 GLSL 4.0 的打包函数。
vec3 ogxHandLightFromBlockData(int itemId, vec3 playerPos, inout float lightRange,
    usampler1D blockDataTexture, vec3 relativeEyePosition)
{
    vec3 lightFinal = vec3(0.0); // 默认没有手持光。
    uint blockData = texelFetch(blockDataTexture, itemId, 0).r; // 读该物品的打包颜色与范围。
    vec4 lightColorRange = vec4(float(blockData & 255u), float((blockData >> 8u) & 255u),
        float((blockData >> 16u) & 255u), float((blockData >> 24u) & 255u)) / 255.0; // 四个字节还原成零到一。
    lightRange = lightColorRange.a * 255.0; // 范围回到零到二百五十五。
    if (lightRange > 0.0) // 只有带范围的物品才发光。
    {
        vec3 lightColor = ogxSrgbToLinear(lightColorRange.rgb); // 颜色从 sRGB 换到线性。
        float lightDist = length(playerPos + relativeEyePosition); // 手持光到表面的距离。
        const float NoL = 1.0; // 参考实现固定为正面受光。
        float falloff = pow(1.0 - lightDist / lightRange, 3.0); // 三次方衰减。
        lightFinal = lightColor * NoL * max(falloff, 0.0); // 范围外为零。
    }
    return lightFinal; // 交回手持光颜色。
}

#endif
