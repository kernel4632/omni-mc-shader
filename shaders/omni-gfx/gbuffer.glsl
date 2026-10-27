/*
生成文件：延迟缓冲模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 G-buffer 解码模块：把多张中间画面还原成表面数据、材质与光源标记。
调用位置：需要读取延迟着色中间画面的程序；Minecraft 光影由 `/omni-gfx/gbuffer.glsl` 引入。
可复制示例：
    OgxGbufferData d = ogxGetGbufferData(g0, g3, g4, g5, g6, depth1, depth0, texel, true, ...);
    OgxMaterialMask m = ogxCalculateMasks(d.materialIDL, ids);
设计原因与取舍：
    参考实现直接读取 colortex 与固定材质编号。库改成显式传入纹理、像素坐标、编号表与选项，
    这样算法本身不依赖 Minecraft，调用方仍可按自己的缓冲布局填写。
    `GetGbufferData` 的每一行读取顺序与参考实现一致；材质编号只通过 `OgxMaterialIdTable`
    传入，避免把资源包的编号约定写死进通用库。
*/
#ifndef OGX_GBUFFER_INCLUDED
#define OGX_GBUFFER_INCLUDED

// 表面模块提供 labPBR 材质解码，数学模块提供解包与法线解码。
#include "/omni-gfx/surface.glsl"
#include "/omni-gfx/math.glsl"
// 材质编号表：参考实现的 MATID 常量由宿主资源包决定，这里集中成一个显式结构。
struct OgxMaterialIdTable
{
    float sky; // 天空。
    float land; // 普通陆地。
    float beaconBeam; // 信标光束，多个分支会额外匹配它。
    float grass; // 草。
    float leaves; // 树叶。
    float hand; // 手部。
    float water; // 水。
    float stainedGlass; // 染色玻璃。
    float ice; // 冰。
    float entitiesPlayer; // 玩家实体。
    float entitiesLitHigh; // 高亮实体。
    float entitiesLitMedium; // 中亮实体。
    float entitiesLitLow; // 低亮实体。
    float lightning; // 闪电。
    float entitiesSnow; // 积雪实体。
    float torch; // 火把。
    float lava; // 岩浆。
    float glowstone; // 荧石。
    float fire; // 火焰。
    float redstoneTorch; // 红石火把。
    float redstone; // 红石元件。
    float soulFire; // 灵魂火。
    float amethyst; // 紫水晶。
    float oxidizedBulb; // 氧化铜灯。
    float particle; // 普通粒子。
    float particleLit; // 受光粒子。
    float endPortal; // 末地传送门。
    float selection; // 选择框。
};

// 光源标记：每一项都是零或一，表示该像素属于哪类发光体或特殊表面。
struct OgxMaterialMask
{
    float sky; // 天空。
    float land; // 普通陆地。
    float grass; // 草。
    float leaves; // 树叶。
    float hand; // 手部。
    float entityPlayer; // 玩家实体。
    float water; // 水。
    float stainedGlass; // 染色玻璃。
    float ice; // 冰。
    float entitiesLitHigh; // 高亮实体。
    float entitiesLitMedium; // 中亮实体。
    float entitiesLitLow; // 低亮实体。
    float lightning; // 闪电。
    float entitiesSnow; // 积雪实体。
    float torch; // 火把。
    float lava; // 岩浆。
    float glowstone; // 荧石。
    float fire; // 火焰。
    float redstoneTorch; // 红石火把。
    float redstone; // 红石元件。
    float soulFire; // 灵魂火。
    float amethyst; // 紫水晶。
    float oxidizedBulb; // 氧化铜灯。
    float particle; // 普通粒子。
    float particleLit; // 受光粒子。
    float endPortal; // 末地传送门。
    float selection; // 选择框。
};

// G-buffer 解码结果：字段与参考实现一一对应，调用方按需读取。
struct OgxGbufferData
{
    vec3 albedo; // 近景线性底色。
    vec4 albedoW; // 远景线性底色，第四个分量保留解包值。
    vec3 normalL; // 近景视空间法线。
    vec3 normalW; // 远景视空间法线。
    float depthL; // 近景屏幕深度。
    float depthW; // 远景屏幕深度。
    vec2 lightmapL; // 近景方块光与天光。
    vec2 lightmapW; // 远景方块光与天光。
    float materialIDL; // 近景材质编号，已归一化。
    float materialIDW; // 远景材质编号，已归一化。
    float waterMask; // 水面覆盖。
    float rainAlpha; // 雨幕透明度。
    float parallaxShadow; // 视差阴影。
    OgxPbrMaterial material; // labPBR 材质参数。
};

// 把材质编号还原成光源标记：与参考实现逐项比较，顺序一致。
// 为什么用显式编号表：不同资源包对同一方块的编号可能不同，表由调用方在边界填写。
OgxMaterialMask ogxCalculateMasks(float materialIDs, OgxMaterialIdTable ids)
{
    OgxMaterialMask mask; // 待填的标记。
    materialIDs = floor(materialIDs * 255.0); // 参考实现把零到一编码还原成整数编号。
    mask.sky = float(materialIDs == ids.sky); // 天空。
    mask.land = float(materialIDs == ids.land); // 普通陆地。
    mask.grass = float(materialIDs == ids.grass || materialIDs == ids.beaconBeam); // 草与信标光束共用同一分支。
    mask.leaves = float(materialIDs == ids.leaves); // 树叶。
    mask.hand = float(materialIDs == ids.hand); // 手部。
    mask.water = float(materialIDs == ids.water); // 水。
    mask.stainedGlass = float(materialIDs == ids.stainedGlass); // 染色玻璃。
    mask.ice = float(materialIDs == ids.ice); // 冰。
    mask.entityPlayer = float(materialIDs == ids.entitiesPlayer); // 玩家实体。
    mask.entitiesLitHigh = float(materialIDs == ids.entitiesLitHigh || materialIDs == ids.beaconBeam); // 高亮实体与信标共用分支。
    mask.entitiesLitMedium = float(materialIDs == ids.entitiesLitMedium); // 中亮实体。
    mask.entitiesLitLow = float(materialIDs == ids.entitiesLitLow); // 低亮实体。
    mask.entitiesSnow = float(materialIDs == ids.entitiesSnow || materialIDs == ids.beaconBeam); // 积雪实体与信标共用分支。
    mask.lightning = float(materialIDs == ids.lightning); // 闪电。
    mask.torch = float(materialIDs == ids.torch); // 火把。
    mask.lava = float(materialIDs == ids.lava); // 岩浆。
    mask.glowstone = float(materialIDs == ids.glowstone); // 荧石。
    mask.fire = float(materialIDs == ids.fire); // 火焰。
    mask.redstoneTorch = float(materialIDs == ids.redstoneTorch); // 红石火把。
    mask.redstone = float(materialIDs == ids.redstone); // 红石元件。
    mask.soulFire = float(materialIDs == ids.soulFire); // 灵魂火。
    mask.amethyst = float(materialIDs == ids.amethyst); // 紫水晶。
    mask.oxidizedBulb = float(materialIDs == ids.oxidizedBulb); // 氧化铜灯。
    mask.particle = float(materialIDs == ids.particle); // 普通粒子。
    mask.particleLit = float(materialIDs == ids.particleLit); // 受光粒子。
    mask.endPortal = float(materialIDs == ids.endPortal); // 末地传送门。
    mask.selection = float(materialIDs == ids.selection); // 选择框。
    return mask; // 交回全部标记。
}

// 修正粒子覆盖：粒子层本身不写入水面与玻璃标记，要把固体层的标记压掉并让深度统一。
// `modernVersion` 对应参考实现的 MC_VERSION >= 11500 条件；旧版本保留原标记。
void ogxFixParticleMask(inout OgxMaterialMask solidMask, inout OgxMaterialMask mask, inout float depthL, float depthW, bool modernVersion)
{
    if (modernVersion && (solidMask.particle > 0.5 || solidMask.particleLit > 0.5)) // 固体层确实有粒子才修正。
    {
        mask.particle = 1.0; // 标记为粒子。
        mask.water = 0.0; // 粒子不继承水。
        mask.stainedGlass = 0.0; // 也不继承染色玻璃。
        mask.ice = 0.0; // 也不继承冰。
        mask.sky = 0.0; // 有粒子就不是天空。
        depthL = depthW; // 深度改用远景，避免粒子被近景深度裁掉。
    }
}

// 只修标记、不改深度的重载，供不需要深度修正的绘制阶段使用。
void ogxFixParticleMaskNoDepth(inout OgxMaterialMask solidMask, inout OgxMaterialMask mask, bool modernVersion)
{
    if (modernVersion && (solidMask.particle > 0.5 || solidMask.particleLit > 0.5)) // 与上一函数同一判据。
    {
        mask.particle = 1.0; // 标记为粒子。
        mask.water = 0.0; // 清掉水标记。
        mask.stainedGlass = 0.0; // 清掉玻璃标记。
        mask.ice = 0.0; // 清掉冰标记。
        mask.sky = 0.0; // 清掉天空标记。
    }
}

// 解码整套 G-buffer：读取顺序、通道分配与参考实现一致，所有纹理由调用方传入。
// `pbr` 关闭时使用空气材质；`mcBefore11605` 对应旧版本把远景反射强度乘上深度阈值。
OgxGbufferData ogxGetGbufferData(sampler2D gbuffer0, sampler2D gbuffer3, sampler2D gbuffer4, sampler2D gbuffer5,
    sampler2D gbuffer6, sampler2D depthTex1, sampler2D depthTex0, ivec2 texelCoord, bool pbr, bool usePorosity,
    int pbrFormat, float defaultPorosity, float porosityAbsorption, bool roughnessClamp, float emissivenessGamma,
    float sssStrength, float sssOffset, float wet, bool mcBefore11605)
{
    OgxGbufferData data; // 待填的结果。
    vec4 g0 = texelFetch(gbuffer0, texelCoord, 0); // 第一张：近景底色与雨幕。
    vec4 g3 = texelFetch(gbuffer3, texelCoord, 0); // 第三张：近景法线与光照图。
    vec4 g4 = texelFetch(gbuffer4, texelCoord, 0); // 第四张：远景法线与光照图。
    vec4 g5 = texelFetch(gbuffer5, texelCoord, 0); // 第五张：近景材质与视差。
    vec4 g6 = texelFetch(gbuffer6, texelCoord, 0); // 第六张：远景材质与水面。
    data.albedo = ogxGammaToLinear(g0.rgb); // 近景底色从伽马空间换到线性。
    data.albedoW = vec4(ogxUnpack2x8(g6.r), ogxUnpack2x8(g6.g)); // 远景底色由两个八位打包值解开。
    data.albedoW.rgb = ogxGammaToLinear(data.albedoW.rgb); // 远景底色同样转线性。
    data.normalL = ogxDecodeNormal(g3.rg); // 近景法线由两个八位编码还原。
    data.normalW = ogxDecodeNormal(g4.rg); // 远景法线同样还原。
    data.depthL = texelFetch(depthTex1, texelCoord, 0).x; // 近景屏幕深度。
    data.depthW = texelFetch(depthTex0, texelCoord, 0).x; // 远景屏幕深度。
    data.lightmapL = g3.ba; // 近景方块光与天光。
    data.lightmapW = g4.ba; // 远景方块光与天光。
    data.lightmapL = vec2(data.lightmapL.r, ogxCurveBlockLightSky(data.lightmapL.g)); // 天光走同一条曲线。
    data.lightmapW = vec2(data.lightmapW.r, ogxCurveBlockLightSky(data.lightmapW.g)); // 远景同样处理。
    data.materialIDL = g5.b; // 近景材质编号。
    data.materialIDW = g6.b; // 远景材质编号。
    data.waterMask = g6.a; // 远景第四通道是水面覆盖。
    data.rainAlpha = 1.0 - g0.a; // 近景第四通道是雨幕。
    vec2 g5a = ogxUnpack2x8(g5.a); // 第五张透明通道打包了湿润度与视差阴影。
    data.parallaxShadow = g5a.y; // 第二个分量是视差阴影。
    if (pbr) // 开启 labPBR 才解码材质。
    {
        vec4 specTex = vec4(ogxUnpack2x8(g5.r), ogxUnpack2x8(g5.g)); // 红绿通道拆成四字节材质图。
        data.material = ogxItxMaterialFromTex(data.albedo, specTex, g5a.x, usePorosity, pbrFormat,
            defaultPorosity, porosityAbsorption, roughnessClamp, emissivenessGamma, sssStrength, sssOffset); // 复用同一套材质解码。
        if (mcBefore11605) data.material.reflectionStrength *= float(data.depthW >= 0.7); // 旧版本远景才允许反射。
    }
    else // 没有 PBR 时退到空气材质。
    {
        data.material.roughness = 1.0; // 空气没有高光。
        data.material.metalness = 0.0; // 不是金属。
        data.material.f0 = 0.0; // 没有反射率。
        data.material.emissiveness = 0.0; // 不发光。
        data.material.scattering = 0.0; // 不散射。
        data.material.reflectionStrength = 0.0; // 不反射。
    }
    return data; // 交回解码结果。
}

#endif
