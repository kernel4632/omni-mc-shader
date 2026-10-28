/*
Omni 通用图形库表面模块：方块光曲线、材质法线、遮蔽换算与自发光。
调用位置：任何需要把方块光等级、法线贴图和材质遮蔽变成光照输入，或按贴图色算自发光的程序；
    Minecraft 光影由 `/omni-gfx/surface.glsl` 引入，`rendering/lighting/emissive.glsl`
    与地形材质代码只保留选项换算。
可复制示例：
    float c = ogxCurveBlockLightSky(blockLight); // 天光等级曲线。
    float3 n = ogxMaterialNormalScale(tangentNormal, 1.0); // 法线起伏倍率。
    float4 m = ogxMaterialNormal(normalTexRGB, true, 1.0); // 法线加遮蔽。
    float e = ogxOreEmission(albedo); // 矿石发光。
设计原因与取舍：
    选项值由调用方作为参数传入，库不读取任何 `OMNI_*` 宏，因此同一份算法能脱离光影使用。
    曲线常数照 iterationT 与 Eclipse 原程序保留，迁移只改名字与参数位置，默认画面不变。
    自发光按底色长度缩放：贴图越亮的部位越亮，暗贴图不会凭空发光。
*/
#ifndef OGX_SURFACE_INCLUDED
#define OGX_SURFACE_INCLUDED

// 数学模块提供法线解码、夹紧、湿面粗糙度与色相转换。
#include "common/math.slang"

// 天光曲线：先抬高低等级，再压暗高等级，等级越高越接近饱和。
float ogxCurveBlockLightSky(float blockLight)
{
    blockLight = 1.0 - pow(1.0 - blockLight * 0.9, 0.7); // 抬高低等级并保留低端细节。
    blockLight = clamp(blockLight * blockLight * blockLight * 1.95, 0.0, 1.0); // 三次方拉开对比后夹紧。
    return blockLight; // 返回零到一的天光强度。
}

// 方块光曲线：按距离平方衰减，再给高等级补一份提升，得到火把那样集中的光。
float ogxCurveBlockLightTorch(float blockLight)
{
    float dist = (1.0 - blockLight) * 15.0 + 1.0; // 把等级转成米制距离。
    dist = dist * dist; // 距离平方，衰减更快。
    float boost = clamp(blockLight * 2.0 - 1.0, 0.0, 1.0); // 只有高等级才有的提升量。
    blockLight = blockLight + boost * boost; // 先加提升，突出光源附近的亮度。
    blockLight /= dist; // 再按距离平方衰减。
    return blockLight; // 返回重整后的方块光。
}

// 材质遮蔽：资源包把遮蔽存在法线贴图蓝通道，启用时映射到零点五到一。
float ogxMaterialAo(float3 normalTexRGB, bool enabled)
{
    return enabled ? normalTexRGB.b * 0.5 + 0.5 : 1.0; // 未启用时不做任何遮蔽。
}

// 法线倍率：围绕朝外方向缩放起伏，倍率为一时保持原样。
// 先把倍率差补到 z 再单位化，这样倍率为零时正好是平坦的朝外法线。
float3 ogxMaterialNormalScale(float3 tangentNormal, float multiplier)
{
    return normalize(tangentNormal * multiplier + float3(0.0, 0.0, 1.0 - multiplier)); // z 补齐后重新单位化。
}

// 一次解出切线空间法线与遮蔽，返回前三个分量为法线、第四个分量为遮蔽。
float4 ogxMaterialNormal(float3 normalTexRGB, bool aoEnabled, float multiplier)
{
    float3 normal = ogxMaterialNormalScale(ogxDecodeNormalTex(normalTexRGB), multiplier); // 先解码再缩放。
    return float4(normal, ogxMaterialAo(normalTexRGB, aoEnabled)); // 把遮蔽一起交回。
}

// 方块光：按光等级、遮蔽与光源标记算出火把照亮周围的颜色。
// 为什么先按光等级压低遮蔽：光源附近本身亮，遮蔽不该把那里压黑，所以接近满级时把遮蔽推向全亮。
// 为什么先给光源方块限一个上限等级：发光方块自己贴图上不该出现高亮方块光，限一档避免过曝。
// 参数 `sourceMask` 由调用方把各类发光方块与受光实体合成为一个零到一的标记。
float3 ogxBlockLight(float lightmap, float3 ao, float sourceMask, float3 torchColor, float brightness, bool overworld)
{
    ao = lerp(ao, float3(1.0), ogxSaturate(lightmap * 5.0 - 4.2)); // 光等级接近满值时遮蔽趋向全亮。
    lightmap = min(lightmap, 1.0 - 0.13 * sourceMask); // 光源方块自身把方块光等级压一档。
    lightmap = ogxCurveBlockLightTorch(lightmap); // 按距离平方曲线重整等级，得到火把那样集中的光。
    float scale = overworld ? 0.015 : 0.15; // 下界末地没有阳光，常数放大十倍。
    return torchColor * ao * (lightmap * brightness * scale); // 火把光色乘遮蔽与强度。
}

// 纹理自发光：按模式把硬编码发光与资源包发光相加或二选一。
// 参数 `hardcodedMask` 是调用方按方块类型加权得到的强度，`emissive` 已乘过整体亮度。
// 为什么硬编码发光要乘底色长度：贴图越亮的部位自发光越强，避免暗贴图凭空发光。
float3 ogxTextureEmissive(float3 albedo, float emissive, float hardcodedMask, bool torchTinted, float3 torchColor, float torchBrightness,
    float textureBrightness, int mode, bool overworld)
{
    if (mode == 1) // 仅资源包：只用自发光强度，不看方块类型。
    {
        float scale = overworld ? 0.01 : 0.1; // 下界末地放大十倍。
        return float3(emissive * torchBrightness * scale); // 自发光强度乘亮度。
    }
    float3 lightingColor = torchTinted ? torchColor : float3(1.0); // 出现火把类光源才染成火把光色。
    hardcodedMask *= length(albedo); // 用底色亮度缩放，暗贴图不发光。
    float darkScale = overworld ? 1.0 : 10.0; // 下界末地的整体倍率。
    if (mode == 2) return lightingColor * (max(hardcodedMask * textureBrightness, emissive * 0.005) * torchBrightness * darkScale); // 相加模式取较大者。
    return lightingColor * (hardcodedMask * textureBrightness * torchBrightness * darkScale); // 仅硬编码模式。
}

// 矿石发光：鲜艳又明亮的矿物颗粒才发光，灰色石底几乎不亮。
float ogxOreEmission(float3 albedo)
{
    float3 hsv = ogxRgbToHsv(albedo); // 拆出饱和度与明度。
    return smoothstep(0.05, 0.15, hsv.y) * pow(hsv.z, 3.5) * 0.5; // 饱和度当门槛，明度拉对比，再乘 Eclipse 的半值。
}

// 纹饰发光：只看明度，越亮的纹路越亮；明度开方让暗纹也保留一部分发光。
float ogxTrimEmission(float3 albedo)
{
    float3 hsv = ogxRgbToHsv(albedo); // 拆出明度。
    return sqrt(hsv.z); // 明度开方，照 Eclipse。
}

// 从表面贴图解出的一整套物理材质参数；字段与光影包的材质结构一一对应，调用方逐个复制即可。
struct OgxPbrMaterial
{
    float roughness; // 粗糙度，越大高光越散。
    float metalness; // 金属度，越大底色越偏反射。
    float f0; // 正射反射率，非金属约零点零四。
    float emissiveness; // 资源包给出的自发光强度。
    float scattering; // 次表面散射强度。
    float reflectionStrength; // 这份表面允许反射的强度。
};

// 从 labPBR 表面贴图解出材质：蓝色通道兼作孔隙率与散射，红绿通道是平滑度与金属度。
// 参数全部显式传入，库不读取资源包格式选项；`baseTex` 会被吸水压暗，所以是输入输出参数。
// 为什么先算孔隙率：它同时决定吸水暗化与湿润后的平滑度，两处必须用同一个值。
OgxPbrMaterial ogxPbrMaterialFromTex(inout float3 baseTex, float4 specTex, float wet, bool usePorosity,
    int pbrFormat, float defaultPorosity, float porosityAbsorption, bool roughnessClamp,
    float emissivenessGamma, float sssStrength, float sssOffset, float puddleSharpness)
{
    float porosity = defaultPorosity; // 默认孔隙率。
    if (usePorosity && pbrFormat < 2) // 资源包自带孔隙率时才按高六位解码。
    {
        porosity = ogxSaturate(specTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specTex.b)); // 蓝通道高六位表示孔隙率。
    }
    baseTex *= 1.0 - wet * ogxFastSqrt(porosity) * porosityAbsorption; // 吸水越多的表面越暗，开方让差异平缓。
    OgxPbrMaterial material; // 下面逐项填写。
    float rawSmoothness = lerp(specTex.r, 1.0, ogxSaturate(wet * (1.7 - porosity * 0.7))); // 湿润把表面拉向光滑。
    material.roughness = 1.0 - rawSmoothness; // 平滑度取反得到粗糙度。
    material.roughness *= material.roughness; // 平方让光滑面更集中。
    material.roughness = ogxPuddleRoughness(material.roughness, 0.5, wet, puddleSharpness); // 湿面锐度按选项混合。
    float rawMetalness = specTex.g; // 绿通道是金属度。
    if (pbrFormat == 0) rawMetalness = ogxSaturate(rawMetalness + step(0.9, rawMetalness)); // labPBR 预设金属位拉满。
    material.metalness = roughnessClamp ? ogxSaturate(rawMetalness * 1.1 - 0.1) : rawMetalness; // 限制模式先放大再平移。
    material.f0 = rawMetalness * 0.96 + 0.04; // 金属度高时反射率接近底色。
    material.reflectionStrength = roughnessClamp ? ogxSaturate(2.0 - material.roughness * 5.0) : ogxSaturate(2.0 - material.roughness * 2.0); // 限制模式更快去掉粗糙面的反射。
    material.reflectionStrength = ogxSaturate(material.reflectionStrength + material.metalness * 1e10 + wet * 3.0); // 金属与湿面全反射。
    material.emissiveness = specTex.a; // 透明通道是自发光。
    if (pbrFormat < 2) material.emissiveness -= step(1.0, material.emissiveness); // 满值表示没有自发光。
    material.emissiveness = pow(material.emissiveness, emissivenessGamma); // 按选项重整亮暗对比。
    material.scattering = pbrFormat < 2 ? ogxSaturate((specTex.b * 255.0 - 64.0) / 191.0) * sssStrength + sssOffset : 0.0; // 蓝通道其余位是散射。
    return material; // 交回解码好的材质。
}

// Eclipse 方块光曲线：先把等级转成亮斑，再在平方曲线与固定高值之间混合。
// 为什么亮斑单独算：原版光照图在最高几档突然变亮，直接平方会让灯下反而没有层次。
float3 ogxBlockLightCurveSoft(float3 lightColor, float lightmap)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 输入先夹到合法范围。
    float brightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 只取最高三成作为亮斑。
    brightspot *= brightspot * brightspot; // 三次方让亮斑收得更紧。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 开方曲线，低等级抬得更快。
    lightmapLight *= lightmapLight; // 再平方，高等级更亮。
    float curve = lerp(lightmapLight, 2.5, brightspot); // 亮斑处直接推到固定高值。
    return curve * lightColor; // 乘光色得到方块光。
}

// 手电筒光斑：按光线与光束指向的夹角给出一束光的强度分布。
// 主瓣给中心亮区，副瓣给一点点外圈余晖，再乘一圈暗环，让边界更像手电筒。
float ogxSpotShape(float r, float fov)
{
    float shape = ogxCurve01(ogxSaturate(r * 2.0 - (2.0 - fov))); // 中心主瓣，夹角越小越亮。
    shape += ogxCurve01(ogxSaturate(r * 1.25 - (1.0 - fov))) * 0.01; // 很弱的外圈余晖。
    float ringSize = 8.0 / fov; // 暗环宽度随光束角度缩放。
    shape *= 1.0 - ogxCurve01(ogxSaturate(1.0 - abs(r * ringSize - ringSize + 1.0))) * 0.25; // 主瓣外压一圈暗环。
    return shape; // 零到一的光斑强度。
}



// Eclipse 间接光：天光按一条抬高次方的曲线缩放，再混入最低环境光。
// `minAmount` 与 `minAmountInside` 分别是室外、室内的最低光比例，`nightVision` 是夜视附加量。
float3 ogxDoIndirectLighting(float3 lightColor, float3 minimumLightColor, float lightmap,
    float ambientBrightness, float minAmount, float minAmountInside, float nightVision)
{
    float curve = (pow(lightmap, 15.0) * 2.0 + lightmap * lightmap) / 3.0; // 低等级压暗、高等级抬高。
    float3 indirect = lightColor * curve * ambientBrightness; // 天光按曲线缩放。
    indirect += lerp(minimumLightColor * (minAmount * 0.004 + nightVision * 0.02),
                     minimumLightColor * (minAmountInside * 0.004 + nightVision * 0.02), 1.0 - lightmap); // 室外室内两档最低光按天光混合。
    return indirect; // 交回间接光。
}

// iterationT 的纹理自发光：硬编码方块光权重逐项固定，资源包模式与硬编码模式分开。
// 参数 `mode`：0 只硬编码，1 只资源包，2 两者取较大；`overworld` 为假时整体乘十。
float3 ogxTextureLighting(float3 albedo, float lightmap, float emissive, float glowstone,
    float torch, float fire, float lava, float redstoneTorch, float oxidizedBulb, float soulFire,
    float amethyst, float endPortal, float litHigh, float litMedium, float litLow, float particleLit,
    float redstone, float emissiveBrightness, float textureBrightness, float torchBrightness,
    float3 torchColor, int mode, bool overworld)
{
    emissive *= emissiveBrightness; // 参考实现先把资源包自发光乘整体亮度。
    if (mode == 1) // 只用资源包自发光。
    {
        float scale = overworld ? 0.01 : 0.1; // 下界末地放大十倍。
        return float3(emissive * torchBrightness * scale);
    }
    float hardcoded = glowstone * 0.016; // 荧石权重。
    hardcoded += torch * 0.03; // 火把权重。
    hardcoded += fire * 0.004; // 火焰权重。
    hardcoded += lava * 0.012; // 岩浆权重。
    hardcoded += redstoneTorch * 0.001; // 红石火把权重。
    hardcoded += oxidizedBulb * 0.0002; // 氧化铜灯权重。
    float3 lightColor = hardcoded > 0.0 ? torchColor : float3(1.0); // 只有前六类光源染成火把色。
    hardcoded += soulFire * 0.001; // 灵魂火权重。
    hardcoded += amethyst * 0.0003; // 紫水晶权重。
    hardcoded += endPortal * 4.0; // 末地传送门权重。
    hardcoded += litHigh * 0.02; // 高亮实体。
    hardcoded += litMedium * 0.005; // 中亮实体。
    hardcoded += litLow * 0.002; // 低亮实体。
    hardcoded += particleLit * 0.01; // 受光粒子。
    hardcoded += redstone * 0.2 * emissive; // 红石按自发光缩放。
    hardcoded *= length(albedo); // 贴图越亮，硬编码发光越强。
    float darkScale = overworld ? 1.0 : 10.0; // 下界末地的整体倍率。
    if (mode == 2) return lightColor * (max(hardcoded * textureBrightness, emissive * 0.005) * torchBrightness * darkScale); // 两者取较大。
    return lightColor * (hardcoded * textureBrightness * torchBrightness * darkScale); // 只用硬编码。
}

// iterationT 的材质覆盖：水、彩色玻璃、冰按优先级替换整套材质参数，并标记为光滑。
// 为什么先水后玻璃再冰：参考实现按这个顺序覆盖，后写的一方获胜；不要改成 else-if。
void ogxApplyMaterialOverride(inout OgxPbrMaterial material, float water, float glass, float ice, inout bool isSmooth)
{
    if (water > 0.5) // 水材质：粗糙度与金属度为零，反射率 0.02，全反射。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.02;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
    if (glass > 0.5) // 彩色玻璃：反射率 0.042。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.042;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
    if (ice > 0.5) // 冰：反射率 0.018。
    {
        material.roughness = 0.0;
        material.metalness = 0.0;
        material.f0 = 0.018;
        material.emissiveness = 0.0;
        material.scattering = 0.0;
        material.reflectionStrength = 1.0;
        isSmooth = true;
    }
}

// iterationT 的 labPBR 材质解码：与 `ogxPbrMaterialFromTex` 相同，但不叠加 Omni 的水洼粗糙度。
// 为什么单独保留：参考实现的每一行常数都是画面合同的一部分，水洼混合属于额外功能，
// 不能悄悄改变参考路径的粗糙度。
OgxPbrMaterial ogxMaterialFromTexDefault(inout float3 baseTex, float4 specTex, float wet,
    bool usePorosity, int pbrFormat, float defaultPorosity, float porosityAbsorption,
    bool roughnessClamp, float emissivenessGamma, float sssStrength, float sssOffset)
{
    float porosity = defaultPorosity; // 默认孔隙率。
    if (usePorosity && pbrFormat < 2) // 资源包自带孔隙率时才解码高六位。
    {
        porosity = ogxSaturate(specTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specTex.b));
    }
    baseTex *= 1.0 - wet * ogxFastSqrt(porosity) * porosityAbsorption; // 吸水压暗。
    OgxPbrMaterial material; // 逐项填写。
    float rawSmoothness = lerp(specTex.r, 1.0, ogxSaturate(wet * (1.7 - porosity * 0.7))); // 湿面更光滑。
    material.roughness = 1.0 - rawSmoothness; // 平滑度取反。
    material.roughness *= material.roughness; // 平方集中高光。
    float rawMetalness = specTex.g; // 绿通道金属度。
    if (pbrFormat == 0) rawMetalness = ogxSaturate(rawMetalness + step(0.9, rawMetalness)); // labPBR 金属位拉满。
    material.metalness = roughnessClamp ? ogxSaturate(rawMetalness * 1.1 - 0.1) : rawMetalness; // 限制模式。
    material.f0 = rawMetalness * 0.96 + 0.04; // 反射率。
    material.reflectionStrength = roughnessClamp ? ogxSaturate(2.0 - material.roughness * 5.0) : ogxSaturate(2.0 - material.roughness * 2.0); // 粗糙面反射衰减。
    material.reflectionStrength = ogxSaturate(material.reflectionStrength + material.metalness * 1e10 + wet * 3.0); // 金属与湿面全反射。
    material.emissiveness = specTex.a; // 透明通道自发光。
    if (pbrFormat < 2) material.emissiveness -= step(1.0, material.emissiveness); // 满值表示无自发光。
    material.emissiveness = pow(material.emissiveness, emissivenessGamma); // 对比重整。
    material.scattering = pbrFormat < 2 ? ogxSaturate((specTex.b * 255.0 - 64.0) / 191.0) * sssStrength + sssOffset : 0.0; // 蓝通道剩余位是散射。
    return material; // 交回材质。
}

#endif
