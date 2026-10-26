/*
Eclipse 场景模块编译探针：调用场景控制参数，覆盖不依赖纹理的纯计算入口。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证类型与函数调用，不进入光影包。
*/
#include "../../src/eclipse_scene.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float smallCoverage; // 小积云覆盖。
    float smallDensity; // 小积云密度。
    float largeCoverage; // 大积云覆盖。
    float largeDensity; // 大积云密度。
    float altoCoverage; // 高层云覆盖。
    float altoDensity; // 高层云密度。
    float cirrusCoverage; // 卷云覆盖。
    float cirrusDensity; // 卷云密度。
    float fogA; // 均匀雾倍率。
    float fogB; // 云雨雾倍率。
    ogxEclipseApplySceneControllerParameters(t, t, t, t, t, t, t, t, smallCoverage, smallDensity,
        largeCoverage, largeDensity, altoCoverage, altoDensity, cirrusCoverage, cirrusDensity, fogA, fogB); // 场景控制参数。
    return float4(smallCoverage + largeDensity + cirrusCoverage + fogA, altoDensity, 1.0, 1.0); // 有输出即可。
}
