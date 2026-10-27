/*
大气模块编译探针：调用球面几何、密度剖面、单次散射、空气透视与太阳圆盘。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用屏幕坐标构造，避免常量折叠掩盖类型问题；不追求画面正确。
*/
#include "../../../src/atmosphere/atmosphere.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 direction = normalize(float3(t, 0.4, 0.8)); // 视线方向。
    float3 sunDirection = normalize(float3(0.3, 0.2, -0.9)); // 太阳方向。
    OgxAtmosphere air = ogxAtmosphereEarth(); // 大气常数。
    float3 origin = float3(0.0, air.planetRadius + 0.03, 0.0); // 相机在行星正上方。
    float3 acc = float3(ogxAtmosphereOzoneProfile(25.0), ogxAtmosphereDensityRayleigh(air, 0.0), ogxAtmosphereDensityMie(air, 0.0)); // 密度剖面。
    acc += float3(ogxAtmosphereDistanceToTop(origin, direction, air.atmosphereRadius), 0.0, 0.0); // 到层顶的距离。
    bool hit; // 是否打到地面。
    acc += float3(ogxAtmosphereDistanceToGround(origin, direction, air.planetRadius, hit), 0.0, 0.0); // 到地面的距离。
    float3 opticalDepth = ogxAtmosphereOpticalDepth(air, origin, direction, 1.0); // 光学厚度。
    acc += ogxAtmosphereTransmittance(air, opticalDepth); // 透过率。
    acc += ogxAtmosphereSunTransmittance(air, origin, sunDirection, 3); // 阳光透过率。
    acc += ogxAtmosphereSky(air, 0.03, direction, sunDirection, 8); // 天空辐射。
    float3 transmittance; // 空气透视的剩余透过率。
    acc += ogxAerialPerspective(air, 0.03, direction, 1.5, sunDirection, 5, transmittance); // 空气透视。
    acc += ogxSunDisc(direction, sunDirection, 5e-5, 4e4) * direction; // 太阳圆盘。
    return float4(acc, 1.0); // 有输出即可。
}
