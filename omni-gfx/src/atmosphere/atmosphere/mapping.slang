/*
大气子文件：天球对齐、日月圆盘、天空盒坐标、云图集取样、极光与彩虹。
调用位置：由 `atmosphere/atmosphere.slang` 按顺序内联，供大气、天空与云模块共用。
可复制示例：`float3 d = ogxAlignToSunAxis(worldDir, sunVector);`
设计原因与取舍：只做方向与坐标换算，颜色、强度与天气由调用方传入；常数照参考保留。
*/
// 把视线方向绕太阳轴旋转对齐天球：罗德里格旋转公式，太阳方向由调用方传入。
// 这样星场会跟着太阳的年周期转，而不是固定在天球上。
float3 ogxAlignToSunAxis(float3 worldDir, float3 sunVector)
{
    float cosine = dot(sunVector, float3(0.0, 0.0, 1.0)); // 太阳轴与参考轴夹角余弦。
    float3 axis = cross(sunVector, float3(0.0, 0.0, 1.0)); // 旋转轴。
    float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
    return cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式对齐星场。
}

// 真实月亮圆盘：角半径由尺寸档位换算，档位越大圆盘越大。
float ogxMoonDiscReal(float3 worldDir, float3 moonDir, float sizeSetting)
{
    float moonSize = 0.999 + (10.0 - sizeSetting) * 0.0001; // 档位越大圆盘越大。
    return ogxDiscProfile(dot(worldDir, moonDir), 1.0 - moonSize, 1.0 / (1.0 - moonSize)); // 用圆盘剖面收边。
}

// 默认月亮圆盘：比太阳更硬、更小的圆盘。
float ogxMoonDiscDefault(float3 worldDir, float3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 5e-5, 1e5); // 默认月亮更硬更小。
}

// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float ogxMoonDiscReflection(float3 worldDir, float3 moonDir)
{
    return ogxSunDisc(worldDir, moonDir, 0.0025, 300.0); // 反射用更大的角半径与更软的边缘。
}

// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ogxSkyProject` 互为逆。
// `tileSize` 是单张面的边长；结果不带屏幕偏移，由调用方按自己的贴图布局追加。
float3 ogxSkyUnproject(float2 texel, float tileSize)
{
    float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
    float3 direction = float3(0.0); // 待求的世界方向。
    if (texel.x < tileSize) // 第一张面，朝横轴正负。
    {
        direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else if (texel.x < 2.0 * tileSize) // 第二张面，朝纵轴正负。
    {
        direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
        direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
    }
    else // 第三张面，朝深度轴正负。
    {
        direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
        direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
        direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
    }
    return normalize(direction); // 单位世界方向。
}

// 把一个世界方向投到天空盒三维贴图上，与 `ogxSkyUnproject` 互为逆。
float2 ogxSkyProject(float3 dir, float tileSize)
{
    float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
    float3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
    float2 texel; // 待求的纹素坐标。
    if (adir.x > adir.y && adir.x > adir.z) // 横分量最大时用第一张面。
    {
        dir /= adir.x; // 归一化主轴分量。
        texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
    }
    else if (adir.y > adir.x && adir.y > adir.z) // 纵分量最大时用第二张面。
    {
        dir /= adir.y; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
        texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
    }
    else // 否则用第三张面。
    {
        dir /= adir.z; // 归一化主轴分量。
        texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
        texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
    }
    return texel; // 返回纹素坐标，屏幕偏移由调用方追加。
}

// 等距圆柱投影：把世界方向换成经纬度贴图坐标。
// 与 `ogxSkyProject` 的差别是贴图布局不同：这里是左右铺经度、上下铺纬度的整张天球图，
// 六面天空盒用的是 3×2 的瓦片图集；两套布局不能混用。`y` 零在正下方、一在正上方。
float2 ogxSkyEquirect(float3 direction)
{
    float longitude = clamp(ogxAtan2(float2(-direction.z, -direction.x)), -OGX_PI, OGX_PI); // 绕竖直轴的角度，正面为零。
    float latitude = asin(clamp(direction.y, -1.0, 1.0)); // 高度角，正上为正。
    return float2(longitude * (0.5 / OGX_PI) + 0.5, latitude * (1.0 / OGX_PI) + 0.5); // 归一到零到一。
}

// 天空云图坐标：经纬坐标先夹进贴图，再按调用方给的子图布局换成纹素坐标。
// 为什么布局要显式传入：参考光影把云图塞在整屏缓冲的一个小角落里，位置与边长随分辨率变化；
// 库里只保留“方向到子图坐标”的换算，具体放在哪由宿主决定，换布局不必改算法。
// `texelSize` 是整张贴图的纹素大小，`origin` 是子图左上角的纹素坐标，`tile` 是子图边长。
float2 ogxSkyCloudAtlasCoord(float3 direction, float2 texelSize, float2 origin, float tile)
{
    float2 p = clamp(ogxSkyEquirect(direction), float2(0.0), float2(1.0)); // 经纬坐标夹进子图范围。
    return p * tile * texelSize + origin * texelSize; // 子图内部按纹素换算到整图坐标。
}

// 读天空云图：按方向取对应经纬度的云颜色与覆盖率，四个通道原样返回。
// `skyTex` 是显式传入的采样器，库不绑定任何宿主纹理；过滤方式由调用方设置。
float4 ogxSkyCloudsFromTex(Sampler2D skyTex, float3 direction, float2 texelSize, float2 origin, float tile)
{
    float2 uv = ogxSkyCloudAtlasCoord(direction, texelSize, origin, tile); // 方向换成子图内的纹理坐标。
    return skyTex.SampleLevel(uv, 0.0); // 零号层级，不做各向异性过滤。
}

// 按粗糙度收拢的天空云图采样：粗糙度越大，靠近天顶的云越向观测方向压缩。
// 为什么按高度分界：地平线附近的云本来就叠在一起，粗糙度只该影响头顶那片，
// 否则远处的云会被整片抹平。`roughness` 零到一，由材质粗糙度或模糊强度给出。
float4 ogxSkyCloudsFromTexLod(Sampler2D skyTex, float3 direction, float2 texelSize, float2 origin, float tile,
    float roughness)
{
    float2 p = ogxSkyEquirect(direction); // 经纬坐标。
    roughness = 1.0 - pow(1.0 - roughness, 3.0); // 三次曲线让低粗糙度变化更细。
    float high = min(max(p.y - 0.5, 0.0) * 50.0, 1.0); // 只有天顶那半边的云参与收拢。
    p = lerp(p, (p - 0.5) * (1.0 - roughness) + 0.5, high); // 按粗糙度把坐标朝中心压缩。
    p = clamp(p * 2.0 - 1.0, float2(-1.0), float2(1.0)) * 0.5 + 0.5; // 压缩后再夹一次，边缘不越界。
    return skyTex.SampleLevel(p * tile * texelSize + origin * texelSize, 0.0); // 取子图内的颜色。
}

// 极光：夜晚高空的缓慢帘幕，雨天被云遮挡；`tint` 为正偏绿、为负偏蓝紫。
float3 ogxAurora(float3 color, float3 direction, float3 sunDirection, float time, float wetness, float tint, float strength)
{
    float night = 1.0 - smoothstep(-0.2, 0.1, sunDirection.y); // 太阳越低夜色越浓，极光越亮。
    float ripple = 0.5 + 0.5 * sin(direction.x * 6.0 + time * 0.02) * sin(direction.z * 5.0 - time * 0.015); // 两个方向的正弦交叉出缓慢起伏。
    float curtain = pow(max(0.0, sin(direction.x * 18.0 + ripple * 3.0)), 8.0); // 帘幕随位置起伏、随时间缓慢移动。
    float3 auroraColor = lerp(float3(0.12, 0.16, 0.50), float3(0.08, 0.35, 0.20), 0.5 + 0.5 * tint); // 极光颜色：正值偏绿、负值偏蓝紫。
    return color + auroraColor * curtain * smoothstep(0.1, 0.5, direction.y) * (1.0 - wetness) * night * strength; // 帘幕只露在高空，雨云之下熄灭。
}

// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
float3 ogxRainbow(float3 color, float3 direction, float3 sunDirection, float wetness, float strength)
{
    float angle = acos(clamp(dot(direction, -sunDirection), -1.0, 1.0)); // 与背太阳方向的夹角。
    float offset = (angle - 0.733) / 0.018; // 相对约四十二度彩虹角的偏移。
    float band = exp(-offset * offset); // 窄带：只用乘法构成，避开对负数取幂的未定义结果。
    float3 spectrum = 0.5 + 0.5 * cos((angle - 0.72) * 120.0 + float3(0.0, 2.1, 4.2)); // 角度到红橙黄绿的彩色谱。
    return color + spectrum * band * wetness * (1.0 - wetness) * smoothstep(0.0, 0.1, direction.y) * strength; // 只在雨停后仍湿润时出现。
}
