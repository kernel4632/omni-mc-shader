/*
?????????????????????????????
?????`omni-gfx/build.py spirv`??????????????
*/
#include "../../src/gbuffer.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // ??????
    OgxMaterialIdTable ids; // ????
    ids.sky = 1.0; ids.land = 2.0; ids.grass = 3.0; ids.leaves = 4.0; ids.hand = 5.0; ids.water = 6.0;
    ids.stainedGlass = 7.0; ids.ice = 8.0; ids.entitiesPlayer = 9.0; ids.entitiesLitHigh = 10.0;
    ids.entitiesLitMedium = 11.0; ids.entitiesLitLow = 12.0; ids.lightning = 13.0; ids.entitiesSnow = 14.0;
    ids.torch = 15.0; ids.lava = 16.0; ids.glowstone = 17.0; ids.fire = 18.0; ids.redstoneTorch = 19.0;
    ids.redstone = 20.0; ids.soulFire = 21.0; ids.amethyst = 22.0; ids.oxidizedBulb = 23.0;
    ids.particle = 24.0; ids.particleLit = 25.0; ids.endPortal = 26.0; ids.selection = 27.0; ids.beaconBeam = 28.0;
    OgxMaterialMask mask = ogxCalculateMasks(t, ids); // ?????
    return float4(mask.sky, mask.water, mask.torch, 1.0); // ??????
}
