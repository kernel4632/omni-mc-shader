// 末地吸积盘子文件：只保留天空版与反射版的参数，积分本身调用 `accretion` 模块。
// 调用位置：由 `world/end.slang` 内联；需要“吸积盘加星空”或“反射版吸积盘”的程序调用下面两个入口。
// 设计原因与取舍：两个版本原来各抄一份五十行积分，盘面算式改一次要改两处；现在只剩步数、起点与噪声幂次不同。
// 可复制示例：`float3 c = ogxBlackHoleStars(color, rayDir, lightDir, 0.5, time, true, true, sunVector, 1, noiseTex, 512.0);`

// --- 算法说明与边界 ---
// 吸积盘积分沿视线在盘面内取样，半径越大越暗，多普勒项让朝向相机的一侧更亮。
// 天空版把颜色加到星空，反射版只返回颜色；两者共用同一套积分与噪声。
// 末地吸积盘：沿视线在盘面上积分，按半径与角度取噪声细节，再叠多普勒增亮。
// 天空版把盘面颜色加到星空上，反射版只返回颜色给反射合成；两者共用同一套积分。
// 吸积盘积分沿视线在盘面内取样，半径越大越暗，多普勒项让朝向相机的一侧更亮。
// 天空版把颜色加到星空，反射版只返回颜色；两者共用同一套积分与噪声。


// 黑洞吸积盘主函数：调用通用积分，再按参考实现的顺序叠星空并让盘面遮挡背景。
// `detailAlongLongitude`、`doppler` 与 `starType` 对应参考实现的三个菜单开关。
float3 ogxBlackHoleStars(float3 color, float3 rayDir, float3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, float3 worldSunVector, int starType,
    Sampler2D noiseTexture, float noiseResolution)
{
    float4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, time, 50, 3.0, 4,
        detailAlongLongitude, doppler, noiseResolution); // 天空版：五十步、起点三、噪声四次方。
    if (starType > 0) color += ogxEndStars(rayDir, worldSunVector, time, starType, 1.0, 1.0); // 参考实现的星空叠加。
    color *= disc.a; // 盘面遮挡背景。
    return color + disc.rgb; // 最终颜色。
}

// 黑洞吸积盘反射版：步数更少、起点更远、噪声五次方，细节权重与主函数不同。
float3 ogxBlackHoleReflection(float3 color, float3 rayDir, float3 lightDir, float noise, float time,
    bool detailAlongLongitude, bool doppler, Sampler2D noiseTexture, float noiseResolution)
{
    float4 disc = ogxAccretionDisc(rayDir, lightDir, noise, noiseTexture, time, 30, 4.0, 5,
        detailAlongLongitude, doppler, noiseResolution); // 反射版：三十步、起点四、噪声五次方。
    color *= disc.a; // 盘面遮挡背景。
    return color + disc.rgb; // 最终颜色。
}
