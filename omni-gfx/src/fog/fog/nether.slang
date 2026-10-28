// 下界子文件：五个群系的自发光与雾色，按平滑权重相加。
// 调用位置：由 `fog/fog.slang` 内联；下界雾与下界光照调用这里的两个入口。
// 设计原因与取舍：下界没有太阳，亮度全靠写死的群系基色；颜色与密度分开成两个函数，
// 调用方可以只取雾色或只取光照，不必背一整组参数。
// 可复制示例：`float3 light = ogxNetherBiomeLighting(0.0, 0.0, 0.0, 0.0, 1.0, 1.0);`

// 下界群系自发光：五个群系各给一种基色与强度，按平滑权重相加后再乘整体亮度。
// 为什么每个群系单独一项：下界没有太阳，画面亮度全靠这组写死的基色撑着，群系之间差别很大。
float3 ogxNetherBiomeLighting(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness)
{
    float3 lighting = netherWastes * float3(0.99, 0.34, 0.10) * 4.5e-4; // 荒地偏橙红，最弱。
    lighting += soulSandValley * float3(0.60, 0.77, 1.00) * 2e-4; // 灵魂沙峡谷偏青蓝，更暗。
    lighting += crimsonForest * float3(1.00, 0.80, 0.57) * 4e-4; // 绯红森林偏暖白。
    lighting += warpedForest * float3(0.79, 0.82, 1.00) * 2.5e-4; // 诡异森林偏冷蓝。
    lighting += basaltDeltas * float3(1.00, 0.78, 0.62) * 1e-3; // 玄武岩三角洲最亮。
    return lighting * brightness; // 按整体亮度缩放。
}

// 下界群系雾色：前三个分量是颜色，第四个分量是密度，五个群系按同一套权重混合。
// 为什么密度也按群系混合：玄武岩三角洲的灰雾最浓、诡异森林最淡，颜色和浓度本来就该一起变。
float4 ogxNetherBiomeFogColor(float netherWastes, float soulSandValley, float crimsonForest, float warpedForest,
    float basaltDeltas, float brightness, float density)
{
    float4 fog = float4(0.990, 0.170, 0.005, 0.010) * netherWastes; // 荒地橙红、中等密度。
    fog += float4(0.010, 0.035, 0.060, 0.007) * soulSandValley; // 灵魂沙峡谷近乎黑青。
    fog += float4(0.200, 0.020, 0.000, 0.010) * crimsonForest; // 绯红森林暗红。
    fog += float4(0.030, 0.100, 0.130, 0.007) * warpedForest; // 诡异森林暗青。
    fog += float4(0.400, 0.400, 0.400, 0.014) * basaltDeltas; // 玄武岩三角洲灰色、最浓。
    return fog * float4(brightness, brightness, brightness, density); // 颜色乘亮度、密度乘雾浓度。
}

