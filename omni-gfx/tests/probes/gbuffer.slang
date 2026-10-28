/*
延迟缓冲模块编译探针：填一套材质编号，再调用材质遮罩解码。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与分支，不进入光影包。
设计原因与取舍：编号表按主世界常用材质填写，遮罩函数的所有分支因此都能被解析。
*/
#include "../../src/gbuffer.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    OgxMaterialIdTable ids; // 材质编号表。
    ids.sky = 1.0; ids.land = 2.0; ids.grass = 3.0; ids.leaves = 4.0; ids.hand = 5.0; ids.water = 6.0; // 常用地表。
    ids.stainedGlass = 7.0; ids.ice = 8.0; ids.entitiesPlayer = 9.0; ids.entitiesLitHigh = 10.0; // 半透明与实体。
    ids.entitiesLitMedium = 11.0; ids.entitiesLitLow = 12.0; ids.lightning = 13.0; ids.entitiesSnow = 14.0; // 实体光照档位。
    ids.torch = 15.0; ids.lava = 16.0; ids.glowstone = 17.0; ids.fire = 18.0; ids.redstoneTorch = 19.0; // 发光方块。
    ids.redstone = 20.0; ids.soulFire = 21.0; ids.amethyst = 22.0; ids.oxidizedBulb = 23.0; // 特殊发光。
    ids.particle = 24.0; ids.particleLit = 25.0; ids.endPortal = 26.0; ids.selection = 27.0; ids.beaconBeam = 28.0; // 粒子与传送门。
    OgxMaterialMask mask = ogxCalculateMasks(t, ids); // 按编号解码遮罩。
    return float4(mask.sky, mask.water, mask.torch, 1.0); // 取三个遮罩作为可编译输出。
}
