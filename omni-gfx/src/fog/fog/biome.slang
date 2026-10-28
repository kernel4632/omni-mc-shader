// 群系子文件：Eclipse 的群系雾色与密度混合。
// 调用位置：由 `fog/fog.slang` 内联；通用群系雾与天气雾调用这里的三个入口。
// 设计原因与取舍：四个群系权重与两套密度分开传入，颜色与密度各自混合，
// 这样天气系统可以在不改变颜色的情况下只调密度。
// 可复制示例：`float3 c = ogxBiomeFogColor(float4(1.0, 0.0, 0.0, 0.0), swamp, jungle, dark, pale, coverage);`

// Eclipse 群系雾色：四个群系各给一组红绿蓝基色，按权重相加；返回本群系颜色与覆盖程度。
// 为什么颜色分量分开写：与参考文件一行对一行，之后核对某个群系的颜色不会看错列。
float3 ogxBiomeFogColor(float4 weights, float3 paleGarden, float3 swamp, float3 jungle, float3 darkForest, out float coverage)
{
    coverage = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 四个群系权重之和就是覆盖程度。
    float3 color = float3(0.0); // 默认不在任何群系内，颜色为零。
    color.r = weights.w * paleGarden.r + weights.x * swamp.r + weights.y * jungle.r + weights.z * darkForest.r; // 红色分量。
    color.g = weights.w * paleGarden.g + weights.x * swamp.g + weights.y * jungle.g + weights.z * darkForest.g; // 绿色分量。
    color.b = weights.w * paleGarden.b + weights.x * swamp.b + weights.y * jungle.b + weights.z * darkForest.b; // 蓝色分量。
    return color; // 交回群系雾色。
}

// Eclipse 群系雾密度：把高度衰减雾与团雾两套密度朝当前群系混合，远处按包络退回原值。
// `weights` 顺序是沼泽、丛林、黑森林、苍白花园；`maxDistance` 是随距离收敛的包络。
void ogxBiomeFogDensity(float4 weights, inout float uniformDensity, inout float cloudyDensity,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(weights.x + weights.y + weights.z + weights.w, 0.0, 1.0); // 落在任一已启用群系内的程度。
    float biomeUniform = weights.x * swampUniform + weights.y * jungleUniform + weights.z * darkForestUniform + weights.w * paleGardenUniform; // 高度衰减雾密度加权和。
    float biomeCloudy = weights.x * swampCloudy + weights.y * jungleCloudy + weights.z * darkForestCloudy + weights.w * paleGardenCloudy; // 团雾密度加权和。
    float blend = inBiome * maxDistance; // 群系内且靠近相机时才替换。
    uniformDensity = lerp(uniformDensity, biomeUniform, blend); // 高度衰减雾朝群系值混合。
    cloudyDensity = lerp(cloudyDensity, biomeCloudy, blend); // 团雾朝群系值混合。
}

// Eclipse 的群系雾密度：把沼泽、丛林、黑森林、苍白花园、沙暴、雪暴六类分开加权。
// 参考实现先算总权重，再分别写密度两个分量；沙暴高度密度为零，雪暴固定 0.01。
void ogxBiomeFogDensityReference(inout float4 uniformDensity, inout float4 cloudyDensity,
    float paleGarden, float jungles, float swamps, float darkForests, float sandStorm, float snowStorm,
    float swampUniform, float jungleUniform, float darkForestUniform, float paleGardenUniform,
    float swampCloudy, float jungleCloudy, float darkForestCloudy, float paleGardenCloudy, float maxDistance)
{
    float inBiome = clamp(paleGarden + jungles + swamps + darkForests + sandStorm + snowStorm, 0.0, 1.0); // 六类群系的总权重。
    float2 density = float2(0.0); // 高度密度与团雾密度。
    density.x = swamps * swampUniform + jungles * jungleUniform + darkForests * darkForestUniform
              + sandStorm * 0.0 + snowStorm * 0.01; // 高度密度里沙暴为零、雪暴固定 0.01。
    density.y = paleGarden * paleGardenCloudy + swamps * swampCloudy + jungles * jungleCloudy
              + darkForests * darkForestCloudy + sandStorm * 0.5 + snowStorm * 0.5; // 团雾密度六类都参与。
    uniformDensity = lerp(uniformDensity, float4(density.x), inBiome * maxDistance); // 高度密度混合。
    cloudyDensity = lerp(cloudyDensity, float4(density.y), inBiome * maxDistance); // 团雾密度混合。
}

