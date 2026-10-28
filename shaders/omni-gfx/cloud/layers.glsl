/*
生成文件：层状体积云模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库层状体积云模块：五层云形状、云影、朝光散射与主步进循环。
调用位置：需要层状体积云的程序；Minecraft 光影由 `/omni-gfx/cloud/layers.glsl` 引入。
可复制示例：`float phase = ogxLayersPhaseCloud(0.5, 0.8, 0);` 取一档云相函数。
设计原因与取舍：
    参考实现用大量宏选择云层与天气分支。库把每一层的高度、厚度、比例、距离和覆盖收进结构体，
    把太阳、月亮、闪电与噪声图显式传入，函数体仍按原来的层号分支和采样顺序执行。
    条件功能（积雨云、闪电、极光）用布尔开关保留；关闭时与参考实现的默认路径一致。
    `texture` 的隐式层级在这里统一写成显式零级，避免不同显卡对导数层级的实现差异。
当前状态：由 `shaders/effects/shared/cloud.glsl` 引入并编译；顶层云入口仍走体积云与平面云。
*/
#ifndef OGX_CLOUD_LAYERS_INCLUDED
#define OGX_CLOUD_LAYERS_INCLUDED

// 数学提供球面求交，云模块提供密度取样与相函数，天空提供云的环境色查表。
#include "/omni-gfx/common/math.glsl"
// 云提供球面求交、密度与单层步进。
#include "/omni-gfx/cloud/cloud.glsl"
// 天空提供云环境色、星空与日月圆盘。
#include "/omni-gfx/atmosphere/sky.glsl"
// 一层云的几何与覆盖：参考实现的宏逐项搬进字段，调用方按层号填写。
struct OgxLayersCloudLayer
{
    float height; // 云底高度，米。
    float tallness; // 云层厚度，米。
    float scale; // 世界坐标到云坐标的比例。
    float distance; // 这一层的可见距离，米。
    float coverage; // 云量，零到一。
    float rainDensity; // 雨天密度。
    float detail; // 高频侵蚀尺度。
};

// 体积云的全部环境输入：层数据、天气、太阳与闪电。
struct OgxLayersCloudSettings
{
    OgxLayersCloudLayer layers[5]; // 零小积云、一大积云、二积雨云、三高层云、四卷云。
    float cloudMovement; // 云的水平位移，米。
    float rainAmount; // 降雨强度。
    float thunderStrength; // 雷暴强度。
    float sunElevation; // 太阳高度角正弦。
    float moonElevation; // 月亮高度角正弦。
    float cumulonimbusStrength; // 积雨云强度。
    float distanceFogScale; // 距离雾的指数系数，通常为负。
    float skyBrightness; // 天空亮度。
    float lightningFlash; // 当前闪电亮度。
    float lightningFade; // 闪电衰减。
    float cumulonimbusLightningBrightness; // 积雨云闪电亮度。
    float auroraAmount; // 极光强度，零表示没有极光。
    vec3 auroraLighting; // 极光颜色，调用方按自己的极光模型算好。
    vec4 lightningBoltPosition; // 普通闪电位置，第四个分量是强度。
    vec3 cumulonimbusLightningColor; // 积雨云闪电颜色。
    int cumulonimbus; // 是否启用积雨云，零关闭。
    int lightningEnabled; // 是否启用积雨云闪电。
};

// 五层云总入口的提前声明：严格入口在子文件里先调用它，定义放在主文件末尾。
vec4 ogxLayersGetVolumetricClouds(OgxLayersCloudSettings s, vec3 viewPos, vec2 dither, vec3 sunVector,
    vec3 moonVector, vec3 directLightCol, vec3 directLightCol2, vec3 indirectLightCol,
    inout float cloudPlaneDistance, inout vec2 cloudDistance, vec3 cameraPos, sampler2D skyTexture, vec2 texelSize,
    float farPlane, float dhFarPlane, mat4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort);

// 哈希、噪声、逐层形状、积雨云与降雨加成，具体实现在子文件。
// 子文件：cloud/layers/shape.slang。
/* 层状体积云的形状：哈希、旋度噪声、逐层密度、积雨云与降雨加成；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetCloudShape(settings, 1, 1, position, minHeight, maxHeight, noise);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 二维哈希：把格坐标打散成两个零到一的随机数，供云形状使用。
vec2 ogxLayersHash2(vec2 p) // 当前步骤的中间量。
{ // 按参考顺序推进。
    // 参考实现用 33.33，通用噪声的 `ogxHash22` 用 19.19；两者只差一个常数，
    // 但严格对照要求常数逐项一致，所以云模块保留自己的变体，不退化成转调。
    vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973)); // 三个不同频率的搅动。
    p3 += dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33); // 互相混合。
    return fract((vec2(p3.x, p3.x) + vec2(p3.y, p3.z)) * vec2(p3.z, p3.y)); // 取两个独立分量。
} // 按参考顺序推进。

// 归一化哈希向量：把格坐标变成一个单位方向，供 Perlin 梯度使用。
// 把二维哈希值归一到零到一，避免负值让噪声出现暗带。
vec2 ogxLayersNormalizeHash(vec2 p) // 当前步骤的中间量。
{ // 按参考顺序推进。
    return normalize(ogxLayersHash2(p) - 0.5); // 中心化后单位化。
} // 按参考顺序推进。

// Perlin 梯度：返回解析梯度，供旋度噪声直接使用。
// 由哈希选二维梯度方向，供 Perlin 噪声生成云形状。
vec2 ogxLayersPerlinGradient(vec2 coord) // 当前步骤的中间量。
{ // 按参考顺序推进。
    vec2 i = floor(coord); // 整数格。
    vec2 f = fract(coord); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); // 参考实现的导数，虽然不是严格数学导数但画面更自然。
    vec2 g0 = ogxLayersNormalizeHash(i); // 左下梯度。
    vec2 g1 = ogxLayersNormalizeHash(i + vec2(1.0, 0.0)); // 右下梯度。
    vec2 g2 = ogxLayersNormalizeHash(i + vec2(0.0, 1.0)); // 左上梯度。
    vec2 g3 = ogxLayersNormalizeHash(i + vec2(1.0, 1.0)); // 右上梯度。
    float v0 = dot(g0, f); // 左下贡献。
    float v1 = dot(g1, f - vec2(1.0, 0.0)); // 右下贡献。
    float v2 = dot(g2, f - vec2(0.0, 1.0)); // 左上贡献。
    float v3 = dot(g3, f - vec2(1.0, 1.0)); // 右上贡献。
    vec2 omu = 1.0 - u; // 反向平滑权重。
    return vec2(((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x, // 交回这一段的计算结果。
                  ((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y); // 两个方向的梯度。
} // 按参考顺序推进。

// 二维旋度：把梯度旋转九十度，得到无散度的流动场。
vec2 ogxLayersCurl2D(vec2 coord) // 当前步骤的中间量。
{ // 按参考顺序推进。
    vec2 gradient = ogxLayersPerlinGradient(coord); // 取梯度。
    return vec2(gradient.y, -gradient.x); // 旋转九十度。
} // 按参考顺序推进。

// 极光的三维噪声：四个平移后的哈希值按距离加权，得到柔和的团块。
float ogxLayersTriNoise2d(vec2 coord, float time) // 当前步骤的中间量。
{ // 按参考顺序推进。
    vec2 p = coord * 0.5; // 整体缩放。
    vec2 i = floor(p); // 整数格。
    vec2 f = fract(p); // 格内偏移。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑。
    float a = ogxLayersHash2(i).x; // 左下。
    float b = ogxLayersHash2(i + vec2(1.0, 0.0)).x; // 右下。
    float c = ogxLayersHash2(i + vec2(0.0, 1.0)).x; // 左上。
    float d = ogxLayersHash2(i + vec2(1.0, 1.0)).x; // 右上。
    float value = mix(mix(a, b, u.x), mix(c, d, u.x), u.y); // 双线性插值。
    float wave = sin(time + value * OGX_TAU) * 0.5 + 0.5; // 时间相位。
    return value * wave; // 噪声乘相位。
} // 按参考顺序推进。

// 三维噪声采样：把云坐标折到 512 见方噪声图的一列，再按纵向小数插值两行。
// 参考把这一步写成独立函数；库版本把噪声图显式传入，算式与常数逐项保留。
float ogxLayersDensityAtPos(vec3 pos, sampler2D noiseTexture) // 当前步骤的中间量。
{ // 按参考顺序推进。
    pos /= 18.0; // 换成噪声格坐标。
    pos.xz *= 0.5; // 横向压缩，让云细节更宽。
    vec3 p = floor(pos); // 所在格子的整数坐标。
    vec3 f = fract(pos); // 格内小数位置。
    vec2 uv = p.xz + f.xz + p.y * vec2(0.0, 193.0); // 纵向每层错开一行，避免层间条纹。
    vec2 coord = uv / 512.0; // 换成零到一纹理坐标。
    vec2 xy = textureLod(noiseTexture, coord, 0.0).yx; // 图里存的是两层密度。
    return mix(xy.r, xy.g, f.y); // 按纵向小数在两层之间插值。
} // 按参考顺序推进。

// 单层云形状：按层号走参考实现的分支，返回零到一的密度。
// 云层形状与云影的提前声明：入口放在定义之前。
// 五层云共用一套形状函数：层号决定高度、厚度、覆盖率与噪声尺度，
// 这样新增一层只需要填参数，不必再抄一遍采样流程。
// 大尺度噪声决定云团分布，小尺度噪声决定边缘侵蚀；两者分开采样，
// 远处只用大尺度，近处才叠细节，避免远景闪烁。
float ogxLayersGetCloudShape(OgxLayersCloudSettings s, int layerIndex, int lod, vec3 position, // 当前步骤的中间量。
    float minHeight, float maxHeight, sampler2D noiseTexture); // 当前步骤的中间量。
float ogxLayersGetCloudShadow(OgxLayersCloudSettings s, vec3 playerPos, vec3 sunVector, // 当前步骤的中间量。
    int cloudShadowAmount, float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture); // 当前步骤的中间量。

// 层状云层形状入口：参考签名只带层号、细节层级、位置与高度范围，云设置与噪声由宿主提供。
float ogxLayersGetCloudShapeReference(int layerIndex, int lod, vec3 position, float minHeight, float maxHeight, // 当前步骤的中间量。
    OgxLayersCloudSettings s, sampler2D noiseTexture) // 按参考顺序推进。
{ // 按参考顺序推进。
    return ogxLayersGetCloudShape(s, layerIndex, lod, position, minHeight, maxHeight, noiseTexture); // 交回这一段的计算结果。
}

// 层状云影入口：参考签名只给世界位置与太阳方向，云设置、相机与噪声由宿主提供。
float ogxLayersGetCloudShadowReference(vec3 playerPos, vec3 sunVector, OgxLayersCloudSettings s,
    int cloudShadowAmount, float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    return ogxLayersGetCloudShadow(s, playerPos, sunVector, cloudShadowAmount, cumulonimbusScale,
        cameraPos, noiseTexture);
}

// 积云侵蚀的提前声明：形状入口先算竖直包络，再调用它削细节。
float ogxLayersCloudErosion(OgxLayersCloudSettings s, int layerIndex, int lod, vec3 position,
    float minHeight, float maxHeight, sampler2D noiseTexture, float shape, vec3 samplePos, float posToMax, float tallness);

// 云形状的实际定义：把层号、覆盖率与上下界交给噪声采样，返回该层的密度。
float ogxLayersGetCloudShape(OgxLayersCloudSettings s, int layerIndex, int lod, vec3 position,
    float minHeight, float maxHeight, sampler2D noiseTexture)
{
    float coverage = 0.0; // 云量。
    float shape = 0.0; // 形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    vec3 samplePos = position * vec3(0.25, 0.005, 0.25); // 形状取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    if (layerIndex == 4) // 卷云。
    {
        coverage = s.layers[4].coverage; // 卷云量。
        vec2 coord = position.zx + 6.0 * s.cloudMovement; // 卷云坐标。
        vec2 curl = ogxLayersCurl2D(0.00002 * coord) * 0.5
                    + ogxLayersCurl2D(0.00005 * coord) * 0.25
                    + ogxLayersCurl2D(0.00018 * coord) * 0.125; // 三层旋度。
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 2.0) / 80000.0 * s.layers[4].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (0.000005 / s.layers[4].scale) * coord, 0.0).r; // 小尺度。
        float detailAmplitude = 0.3; // 初始细节振幅。
        float detailFrequency = 0.00002; // 初始细节频率。
        float curlStrength = 1.3; // 初始旋度强度。
        for (int i = 0; i < 3; ++i) // 三层细节。
        {
            float detail = textureLod(noiseTexture, coord * detailFrequency + curl * curlStrength, 0.0).r; // 取细节。
            smallCloud -= detail * detailAmplitude; // 从形状里削掉。
            detailAmplitude *= 0.5; // 振幅减半。
            detailFrequency *= 4.0; // 频率翻四倍。
            curlStrength *= 2.7; // 旋度增强。
        }
        smallCloud = abs(largeCloud * -0.4) + smallCloud; // 大尺度偏移。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖减去噪声。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 卷云不使用后面的通用包络。
    }
    if (layerIndex == 3) // 高层云。
    {
        coverage = s.layers[3].coverage + 0.0 * s.rainAmount + 0.0 * s.thunderStrength; // 高层云量。
        largeCloud = textureLod(noiseTexture, (position.xz + s.cloudMovement * 20.0) / 100000.0 * s.layers[3].scale, 0.0).b; // 大尺度。
        vec2 altoCoord = (position.xz + vec2(-s.cloudMovement, s.cloudMovement) * 20.0) / 7500.0
            - vec2(1.0 - largeCloud, -largeCloud) / 5.0; // 高层云小尺度坐标。
        smallCloud = 1.0 - textureLod(noiseTexture, altoCoord * s.layers[3].scale, 0.0).b; // 小尺度。
        smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9 - largeCloud, 0.0, 1.0); // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
        shape *= shape; // 平方收边。
        if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部裁掉。
        return shape; // 高层云直接返回。
    }
    if (layerIndex == 1) // 大积云。
    {
        coverage = s.layers[1].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 雨天与雷暴增加云量。
        largeCloud = textureLod(noiseTexture, (samplePos.zx + s.cloudMovement * 3.0) / 10000.0 * s.layers[1].scale, 0.0).b; // 大尺度。
        smallCloud = textureLod(noiseTexture, (samplePos.zx - s.cloudMovement * 3.0) / 2500.0 * s.layers[1].scale, 0.0).b; // 小尺度。
        smallCloud = abs(largeCloud * -0.7) + smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    else if (layerIndex == 0) // 小积云。
    {
        coverage = s.layers[0].coverage + s.rainAmount * 0.1 + s.thunderStrength * 0.1; // 天气加成。
        largeCloud = textureLod(noiseTexture, (samplePos.xz + s.cloudMovement) / 5000.0 * s.layers[0].scale, 0.0).b; // 大尺度。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement) / 500.0 * s.layers[0].scale, 0.0).r; // 小尺度。
        smallCloud = abs(largeCloud - 0.6) + smallCloud * smallCloud; // 合并。
        float val = coverage; // 覆盖值。
        shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0); // 覆盖曲线。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在层内。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 25.0, 1.0), 5.0); // 底部圆角。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-0.5 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 顶部圆角。
    shape = max((shape - 1.0) + topShape * bottomShape, 0.0); // 合成竖直包络。
    return ogxLayersCloudErosion(s, layerIndex, lod, position, minHeight, maxHeight, noiseTexture, shape, samplePos, posToMax, tallness); // 竖直包络之后再做细节侵蚀。
}

// 积云侵蚀：按层号取两组噪声，从形状边缘往里削，最后按四次方收边。
// 为什么单独成函数：侵蚀只服务积云，放在形状入口里会让主函数同时管覆盖与细节。
float ogxLayersCloudErosion(OgxLayersCloudSettings s, int layerIndex, int lod, vec3 position,
    float minHeight, float maxHeight, sampler2D noiseTexture, float shape, vec3 samplePos, float posToMax, float tallness)
{
    if (shape <= 0.001) return 0.0; // 没有形状就没有侵蚀。
    float erodeAmount = 0.5; // 侵蚀强度。
    if (lod < 1) return max(shape - 0.27 * erodeAmount, 0.0); // 低细节直接减薄。
    samplePos.xz -= s.cloudMovement / 4.0; // 侵蚀坐标随风偏移。
    samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 越高偏移越大。
    float erosion = 0.0; // 侵蚀量。
    float omShape = 1.0 - shape; // 反向形状。
    if (layerIndex == 0) // 小积云侵蚀。
    {
        erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale / 3.0, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / (s.layers[0].tallness / s.layers[0].scale), 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[0].detail * s.layers[0].scale, noiseTexture, 512.0) - falloff)
            * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion; // 四次方收边。
    }
    if (layerIndex == 1) // 大积云侵蚀。
    {
        erosion += (1.0 - ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale / 3.571428, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / (s.layers[1].tallness / s.layers[1].scale), 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * s.layers[1].detail * s.layers[1].scale, noiseTexture, 512.0) - falloff)
            * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion; // 四次方收边。
    }
    return max(shape - erosion * erodeAmount, 0.0); // 减掉侵蚀。
}

// 积雨云形状：返回 `x` 为密度、`y` 为大云标记。
// 积雨云单独一份：它的高度跨越大半个云层，底部要平、顶部要圆，
// 用普通层的覆盖率函数会把整团云压成薄片。
// 这里先算大尺度轮廓，再用小尺度噪声补底部与顶部，最后按高度做侵蚀；
// 侵蚀强度随高度上升，云顶更碎，云底保持完整。
vec2 ogxLayersGetCumulonimbusShape(OgxLayersCloudSettings s, int lod, vec3 position, float minHeight, float maxHeight,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float largeCloud = 0.0; // 大尺度。
    float smallCloud = 0.0; // 小尺度。
    vec3 samplePos = position * vec3(1.0, 1.0 / 48.0, 1.0) / 4.0; // 取样坐标。
    float tallness = maxHeight - minHeight; // 层厚。
    float posToMax = maxHeight - position.y; // 到云顶距离。
    largeCloud = max(sin((samplePos.x - s.cloudMovement * 10.0) / 2700.0) * cos((samplePos.z - s.cloudMovement * 10.0) / 2700.0), 0.0); // 大尺度波形。
    largeCloud = mix(max(min(largeCloud - 0.25, 0.5) * 2.0, 0.0), max(min(largeCloud, 0.25) * 4.0, 0.0), s.thunderStrength); // 雷暴时收窄。
    float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraPos)); // 远处才显示积雨云。
    float isLarge = smoothstep(0.0, 1.0, shape); // 大云标记。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 5.0, 1.0), 5.0); // 底部圆角。
    float smallMaxHeight = tallness * 0.45 + minHeight; // 小云顶。
    float shape2 = 0.0; // 第二层形状。
    if (position.y < smallMaxHeight) // 小云只在下半层。
    {
        float smallTallness = smallMaxHeight - minHeight; // 小云厚度。
        float posToMaxSmall = smallMaxHeight - position.y; // 小云到顶距离。
        smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - s.cloudMovement * 4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r
            * smoothstep(smallMaxHeight, tallness * 0.2 + minHeight, position.y); // 小云噪声。
        shape2 = min(max(1.1 - smallCloud, 0.0) / sqrt(1.1), 1.0) * smoothstep(5000.0, 7000.0, length(position - cameraPos)); // 小云形状。
        shape2 = min(min(shape2, clamp(smallMaxHeight - position.y, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在小云内。
        float smallTopShape = min(max(posToMaxSmall, 0.0) / max(smallTallness, 1.0), 1.0); // 小云顶。
        smallTopShape = min(exp(23.0 * (1.0 - smallTopShape)), 1.0 - pow(1.0 - smallTopShape, 9.0)); // 圆角。
        shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0); // 合成。
    }
    shape = min(min(shape, clamp(posToMax, 0.0, 1.0)), 1.0 - clamp(minHeight - position.y, 0.0, 1.0)); // 限制在主层内。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部归一化。
    topShape = min(exp(-1.0 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0)); // 圆角。
    float topShape2 = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 第二顶部归一化。
    topShape2 = min(exp(-0.1 * (1.0 - topShape2)), 1.0 - pow(1.0 - topShape2, 7.0)); // 第二圆角。
    shape = max((shape - 1.0) + topShape * bottomShape + (1.0 - topShape2) * bottomShape, 0.0); // 合成主形状。
    shape = pow(shape, 1.0 + smoothstep(tallness * 0.4 + minHeight, tallness * 0.8 + minHeight, position.y)); // 越高越收。
    shape += shape2; // 加上小云。
    if (s.cumulonimbus == 1) shape *= pow(s.cumulonimbusStrength, mix(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y))); // 积雨云强度。
    if (shape > 0.001) // 有形状才侵蚀。
    {
        if (lod < 1) return vec2(max(shape - 0.27 * 0.5, 0.0), isLarge); // 低细节直接减薄。
        samplePos.xz -= s.cloudMovement / 4.0; // 随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 高度偏移。
        float omShape = 1.0 - shape; // 反向形状。
        float erosion = (1.0 - ogxCloudDensityAtPos(samplePos * 190.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0)) * sqrt(omShape); // 第一层侵蚀。
        float falloff = 1.0 - clamp(posToMax / 4600.0, 0.0, 1.0); // 高度衰减。
        erosion += abs(ogxCloudDensityAtPos(samplePos * 580.0 * cumulonimbusScale * 0.05, noiseTexture, 512.0) - falloff)
            * 0.65 * omShape * (1.0 - falloff * 0.5); // 第二层侵蚀。
        erosion = erosion * erosion * erosion * erosion * smoothstep(maxHeight + 40.0, tallness * 0.5 + minHeight, position.y); // 四次方并淡出。
        return vec2(max(shape - erosion * 0.5, 0.0), isLarge); // 返回密度与大云标记。
    }
    return vec2(0.0, isLarge); // 没有形状。
}

// 层状云形状：按云层选择覆盖率与噪声尺度，先算平面形状，再按高度裁剪与侵蚀。
// 参考签名是层号、细节层级、位置与上下界；噪声图、覆盖率与天气参数显式追加在末尾。
// 为什么用 switch：参考按层号分支，每层采样次数与顺序不同，合并会改变采样序列。
float ogxLayersCloudShapeLayer(int layerIndex, int lod, vec3 position, float minHeight, float maxHeight,
    sampler2D noiseTexture, float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage,
    float rainAmount, float thunderStrength, float cloudMovement)
{
    float coverage = 0.0; // 本层覆盖率。
    float shape = 0.0; // 平面形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    vec3 samplePos = position * vec3(0.25, 0.005, 0.25); // 细节采样用的压缩坐标。
    float tallness = maxHeight - minHeight; // 云层厚度。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    switch (layerIndex)
    {
        default: { break; } // 未知层不产生云。
        case 3: { // 高层云：大尺度覆盖加一层细节。
            coverage = altostratusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = textureLod(noiseTexture, (position.xz + cloudMovement * 20.0) / 100000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - textureLod(noiseTexture, ((position.xz + vec2(-cloudMovement, cloudMovement) * 20.0) / 7500.0 - vec2(1.0 - largeCloud, -largeCloud) / 5.0) * 1.0, 0.0).b;
            smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9 - largeCloud, 0.0, 1.0);
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            shape *= shape;
            if (position.y < (-0.0001 * minHeight + 0.8) * minHeight) shape = 0.0; // 底部薄层压掉。
            return shape;
        }
        case 1: { // 大积云：两张大尺度噪声相加。
            coverage = largeCumulusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = textureLod(noiseTexture, (samplePos.zx + cloudMovement * 3.0) / 10000.0 * 1.0, 0.0).b;
            smallCloud = textureLod(noiseTexture, (samplePos.zx - cloudMovement * 3.0) / 2500.0 * 1.0, 0.0).b;
            smallCloud = abs(largeCloud * -0.7) + smallCloud;
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            break;
        }
        case 0: { // 小积云：大尺度边缘直接参与形状。
            coverage = smallCumulusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = textureLod(noiseTexture, (samplePos.xz + cloudMovement) / 5000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - textureLod(noiseTexture, (samplePos.xz - cloudMovement) / 500.0 * 1.0, 0.0).r;
            smallCloud = abs(largeCloud - 0.6) + smallCloud * smallCloud;
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            break;
        }
    }
    shape = min(min(shape, clamp(posToMax, 0, 1)), 1.0 - clamp(minHeight - position.y, 0, 1)); // 上下边界夹紧。
    float bottomShape = 1.0 - pow(1.0 - min(max(position.y - minHeight, 0.0) / 25.0, 1.0), 5.0); // 底部圆角。
    float topShape = min(max(posToMax, 0.0) / max(tallness, 1.0), 1.0); // 顶部收口。
    topShape = min(exp(-0.5 * (1.0 - topShape)), 1.0 - pow(1.0 - topShape, 5.0));
    shape = max((shape - 1.0) + topShape * bottomShape, 0.0); // 竖直包络。
    if (shape > 0.001) // 只在有云的位置做细节侵蚀。
    {
        float erodeAmount = 0.5; // 侵蚀强度。
        if (lod < 1) return max(shape - 0.27 * erodeAmount, 0.0); // 低细节层直接给均匀侵蚀。
        samplePos.xz -= cloudMovement / 4.0; // 细节层随风偏移。
        samplePos.xz += pow(max(position.y - (minHeight + 20.0), 0.0) / (max(tallness, 1.0) * 0.20), 1.5); // 越靠上越斜，云顶被吹偏。
        float erosion = 0.0; // 侵蚀量。
        float omShape = 1.0 - shape; // 形状的补值。
        switch (layerIndex)
        {
            default: { break; }
            case 0: { // 小积云细节。
                erosion += (1.0 - ogxLayersDensityAtPos(samplePos * 600.0 * 1.0 / 3.0, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (130.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxLayersDensityAtPos(samplePos * 600.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
            case 1: { // 大积云细节。
                erosion += (1.0 - ogxLayersDensityAtPos(samplePos * 250.0 * 1.0 / 3.571428, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (280.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxLayersDensityAtPos(samplePos * 250.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
        }
        return max(shape - erosion * erodeAmount, 0.0);
    }
    else return 0.0;
}

// 层状积雨云形状：大尺度正弦云团叠加很小的塔状云，输出形状与大云标记。
// 参考签名是细节层级、位置与上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加。
// 参考签名版积雨云：参数顺序与参考一致，内部仍走同一套形状与侵蚀。
// 为什么保留两份：严格对照需要原签名，画面入口需要结构体参数；
// 两份都只做一次转调，不复制算式，改公式时只改共享实现。
vec2 ogxLayersCumulonimbusShapeLayer(int lod, vec3 position, float minHeight, float maxHeight,
    sampler2D noiseTexture, vec3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength)
{
	float largeCloud = 0.0;
	float smallCloud = 0.0;

	vec3 samplePos = position*vec3(1.0, 1.0/48.0, 1.0)/4.0;
	float tallness = maxHeight - minHeight;
	float posToMax = maxHeight - position.y;

	float cumulonimbusScale = 1.0;
	                                                                                                            
	
	                                     

	                                                 
	                                                                                                                              

	largeCloud = (max(sin((samplePos.x - cloudMovement*10.0)/2700) * cos((samplePos.z - cloudMovement*10.0)/2700), 0.0));
	largeCloud = mix(max(min(largeCloud - 0.25, 0.5)*2.0, 0.0), max(min(largeCloud, 0.25)*4.0, 0.0), thunderStrength);
	float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraWorldPos));
	                           
	
	float isLarge = smoothstep(0.0, 1.0, shape);
	                 

	float bottomShape = 1.0-pow(1.0-min(max(position.y-minHeight,0.0) / 5.0, 1.0), 5.0);

	float smallMaxHeight = (tallness*0.45 + minHeight);

	float shape2 = 0.0;
	if (position.y < smallMaxHeight) {
	float smallTallness = smallMaxHeight - minHeight;
	float posToMaxSmall = smallMaxHeight - position.y;

	smallCloud = 1.0-textureLod(noiseTexture, (samplePos.xz - cloudMovement*4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r * smoothstep(smallMaxHeight, tallness*0.2+minHeight, position.y);
	
	shape2 = min(max(1.1 - smallCloud,0.0)/sqrt(1.1),1.0)  * smoothstep(5000.0, 7000.0, length(position - cameraWorldPos));

	shape2 = min(min(shape2, clamp(smallMaxHeight - position.y,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float smallTopShape = min(max(posToMaxSmall,0.0) / max(smallTallness,1.0),1.0);
	smallTopShape = min(exp(23 * (1.0-smallTopShape)), 	1.0-pow(1.0-smallTopShape,9.0));

	shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0);
	}

	shape = min(min(shape, clamp(posToMax,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float topShape = min(max(posToMax,0.0) / max(tallness,1.0),1.0);
	topShape = min(exp(-1.0 * (1.0-topShape)), 	1.0-pow(1.0-topShape,5.0));

	float topShape2 = min(max(posToMax,0.0) / max(tallness,1.0),1.0); 

	topShape2 = min(exp(-0.1 * (1.0-topShape2)), 	1.0-pow(1.0-topShape2,7.0));
	
	shape = max((shape - 1.0) + topShape * bottomShape + (1- topShape2) * bottomShape, 0.0);

	shape = pow(shape, 1 + smoothstep(tallness*0.4+minHeight, tallness*0.8+minHeight, position.y));

	shape += shape2;

		shape *= pow(cumulonimbusStrength, mix(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y)));

	if(shape > 0.001){
		if (lod < 1) return vec2(max(shape - 0.27*0.5,0.0), isLarge);

		samplePos.xz -= cloudMovement/4.0;
		samplePos.xz += pow( max(position.y - (minHeight+20.0), 0.0) / (max(tallness,1.0)*0.20), 1.5);

		float omShape = 1.0 - shape;

		float erosion = (1.0 - ogxLayersDensityAtPos(samplePos * 190 * cumulonimbusScale*0.05, noiseTexture)) * sqrt(omShape);

		float falloff = 1.0 - clamp((posToMax)/4600.0,0.0,1.0);

		erosion += abs(ogxLayersDensityAtPos(samplePos * 580 * cumulonimbusScale*0.05, noiseTexture) - falloff) * 0.65 * (omShape) * (1.0-falloff*0.5);

		erosion = erosion*erosion*erosion*erosion*smoothstep(maxHeight+40.0, tallness*0.5+minHeight, position.y);
		

		return vec2(max(shape - erosion*0.5,0.0), isLarge);
	} else return vec2(0.0, isLarge);
}

// 层状云降雨加成：当前云量加上雨与雷带来的额外覆盖，限制在一以内。
// 参考把雨强与雷强当全局量；库版本显式接收，算式与常数不变。
float ogxLayersGetRainDensity(float currentDensity, float rainAmount, float thunderStrength)
{
    float extraDensity = min(currentDensity + rainAmount * 0.1 + thunderStrength * 0.1, 1.0); // 雨天云量更满。
    return extraDensity; // 交回夹紧后的覆盖率。
}

/*
云层混合顺序按小积云、大积云、积雨云、高层云、卷云。
每一层的高度与厚度独立。
修改层数组下标时要同步主入口。
云影与形状共用噪声。
离线编译不验证云边。
*/

// 行星阴影、云影、闪电落点与步进起点，具体实现在子文件。
// 子文件：cloud/layers/shadow.slang。
/* 层状体积云的阴影：行星阴影、三层云影、闪电落点与步进起点；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`ogxLayersGetCloudShadow(settings, playerPos, sunVector, 100, 1.0, cameraPos, noise);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 闪电位置：在云层半径内取一个随机方向，并确认那里确实有积雨云。
vec3 ogxLayersGetLightningPosition(OgxLayersCloudSettings s, float minHeight, float maxHeight, float cumulonimbusScale,
    vec3 cameraPos, sampler2D noiseTexture)
{
    float angle = fract(sin(dot(vec2(s.lightningBoltPosition.w), vec2(12.9898, 78.233))) * 43758.5453) * OGX_TAU; // 随机角。
    float rMin = 7000.0; // 内半径。
    float rMax = 13000.0; // 外半径。
    float radius = sqrt(mix(rMin * rMin, rMax * rMax, fract(sin(dot(vec2(s.lightningBoltPosition.w + 1.0), vec2(12.9898, 78.233))) * 43758.5453))); // 面积均匀的半径。
    vec3 lightningPos = vec3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 初始位置。
    float shapeAtLightning = ogxLayersGetCumulonimbusShape(s, 0, lightningPos, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x; // 该处云密度。
    lightningPos.y = minHeight + (maxHeight - minHeight) * 0.48; // 参考实现把高度固定到 0.48。
    if (shapeAtLightning < 0.1) lightningPos = vec3(0.0); // 没有云就不闪。
    return lightningPos; // 交回相机相对位置。
}

// 行星阴影：太阳越低，主岛下方越暗。
float ogxLayersGetPlanetShadow(vec3 playerPos, vec3 sunVector)
{
    float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / max(sunVector.y * 0.1, 0.0)), 0.0) / 100.0, 1.0); // 高度阈值。
    planetShadow = mix(pow(1.0 - pow(1.0 - planetShadow, 2.0), 2.0), 1.0, pow(max(sunVector.y, 0.0), 2.0)); // 太阳越高阴影越少。
    return planetShadow; // 交回阴影权重。
}

// 云影：把地面点沿太阳方向投到各层云，按层密度累加。
float ogxLayersGetCloudShadow(OgxLayersCloudSettings s, vec3 playerPos, vec3 sunVector, int cloudShadowAmount,
    float cumulonimbusScale, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalShadow = ogxLayersGetPlanetShadow(playerPos, sunVector); // 行星阴影。
    vec3 startPosition = playerPos; // 投影起点。
    vec3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向到单位高度的位移。
    if (cloudShadowAmount > 0) // 有云影才计算。
    {
        float cloudShadows = 0.0; // 云影累加。
        startPosition = playerPos + startOffset * max((s.layers[0].height + 20.0) - playerPos.y, 0.0); // 投到小积云下段。
        cloudShadows = ogxLayersGetCloudShape(s, 0, 0, startPosition, s.layers[0].height,
            s.layers[0].height + s.layers[0].tallness / s.layers[0].scale, noiseTexture) * s.layers[0].rainDensity; // 小积云。
        startPosition = playerPos + startOffset * max((s.layers[1].height + 30.0) - playerPos.y, 0.0); // 投到大积云下段。
        cloudShadows += ogxLayersGetCloudShape(s, 1, 0, startPosition, s.layers[1].height,
            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * s.layers[1].rainDensity; // 大积云。
        startPosition = playerPos + startOffset * max(s.layers[3].height - playerPos.y, 0.0); // 投到高层云。
        cloudShadows += ogxLayersGetCloudShape(s, 3, 0, startPosition, s.layers[3].height, s.layers[3].height + 5.0,
            noiseTexture) * s.layers[3].rainDensity * (1.0 - abs(sunVector.y)); // 高层云。
        float distanceFactor = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), sunVector))), 45.0, 90.0) - 45.0; // 太阳角度。
        startPosition = playerPos + sunVector * mix(7000.0, 18000.0, distanceFactor / 45.0); // 投到积雨云。
        cloudShadows += ogxLayersGetCumulonimbusShape(s, 0, startPosition, 600.0, 4600.0 + startPosition.y,
            cumulonimbusScale, cameraPos, noiseTexture).x; // 积雨云。
        cloudShadows *= float(cloudShadowAmount) / 100.0; // 按强度缩放。
        totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云越厚阴影越黑。
    }
    return totalShadow; // 交回总阴影。
}

// 步进起点：按相机在云层中的位置把射线压到平面，避免从错误的一侧开始。
vec3 ogxLayersGetRayOrigin(vec3 rayStartPos, vec3 cameraPos, float dither, float minHeight, float maxHeight)
{
    vec3 cloudDist = vec3(1.0); // 水平与竖直的缩放。
    cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
        clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 越靠近云层水平步长越小。
    float flip = mix(max(cameraPos.y - maxHeight, 0.0), max(minHeight - cameraPos.y, 0.0), clamp(rayStartPos.y, 0.0, 1.0)); // 上下翻转。
    return rayStartPos * dither + cameraPos + (rayStartPos / length(rayStartPos / cloudDist)) * flip; // 压到平面并加抖动。
}

// 层状云闪电落点：用时间哈希选极坐标角度与半径，再把位置贴到积雨云层里。
// 参考签名只有云层上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加，
// 时间哈希与自定义落点常数直接写成参考数值，保持同一组常数。
vec3 ogxLayersLightningPositionBolt(float minHeight, float maxHeight,
    sampler2D noiseTexture, vec3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength, float lightningTimer)
{
    float angle = fract(sin(dot(vec2(lightningTimer, lightningTimer * 2.0), vec2(12.9898, 78.233))) * 43758.5453) * OGX_TAU; // 时间哈希转角度。
    float rMin = 7000.0; // 最近落点半径。
    float rMax = 13000.0; // 最远落点半径。
    float radius = sqrt(mix(rMin * rMin, rMax * rMax, fract(sin(dot(vec2(lightningTimer + 1, (lightningTimer + 1) * 2.0), vec2(12.9898, 78.233))) * 43758.5453))); // 在环形区域里取半径。
    vec3 lightningPos = vec3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 极坐标转云层坐标。
    float shapeAtLightningPos = ogxLayersCumulonimbusShapeLayer(0, lightningPos, minHeight, maxHeight,
        noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x; // 落点处的积雨云形状。
    float moveUp = 0.48; // 闪电起点抬到云层中上部。
    lightningPos.y = minHeight + (maxHeight - minHeight) * moveUp; // 重算高度。
    lightningPos.y -= cameraWorldPos.y; // 换成相机相对高度。
    if (shapeAtLightningPos < 0.1) lightningPos = vec3(0.0); // 落点没有云就不闪。
    lightningPos = vec3(100.0, 0.0, 0.0) - cameraWorldPos; // 参考默认的自定义落点。
    return lightningPos; // 交回闪电位置。
}

// 层状云影：从玩家位置沿太阳方向升到三层云底，各取一次云形状并按降雨加成叠加。
// 参考签名只有玩家位置与太阳方向；云噪声、风、雨雷、三层覆盖与闪电状态显式追加。
float ogxLayersCloudShadowLayer(vec3 playerPos, vec3 sunVector,
    sampler2D noiseTexture, vec4 lightningBoltPosition, float sunElevation,
    float cloudMovement, float rainAmount, float thunderStrength,
    float smallCumulusCoverage, float largeCumulusCoverage, float altostratusCoverage,
    float smallCumulusRain, float largeCumulusRain, float altostratusRain)
{
    if (lightningBoltPosition.w > 0.0 && sunElevation < 0.0) // 夜里打闪电时不投云影，避免整片变黑。
    {
        return 1.0;
    }
    float totalShadow = ogxLayersGetPlanetShadow(playerPos, sunVector); // 先算星球本身遮住多少阳光。
    vec3 startPosition = playerPos; // 云影采样起点。
    vec3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向升到云底所需的水平偏移。
    float cloudShadows = 0.0; // 三层云影累加。
    startPosition = playerPos + startOffset * max((250.0 + 20.0) - playerPos.y, 0.0); // 小积云底。
    cloudShadows = ogxLayersCloudShapeLayer(0, 0, startPosition, 250.0, 250.0 + 130.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxLayersGetRainDensity(smallCumulusRain, rainAmount, thunderStrength); // 小积云影。
    startPosition = playerPos + startOffset * max((400.0 + 30.0) - playerPos.y, 0.0); // 大积云底。
    cloudShadows += ogxLayersCloudShapeLayer(1, 0, startPosition, 400.0, 400.0 + 280.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength); // 大积云影。
    startPosition = playerPos + startOffset * max(5000.0 - playerPos.y, 0.0); // 高层云底。
    cloudShadows += ogxLayersCloudShapeLayer(3, 0, startPosition, 5000.0, 5000.0 + 5.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * altostratusRain * (1.0 - abs(sunVector.y)); // 高层云影随太阳高度变淡。
    cloudShadows *= float(100.0) / 100.0; // 参考的云影总量比例。
    totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云影越厚，透过率下降越快。
    return totalShadow; // 交回阳光透过率。
}

// 云相函数、散射与光照，具体实现在子文件。
// 子文件：cloud/layers/lighting.slang。
/* 层状体积云的光照：相函数、朝光散射与单次散射合成；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`float phase = ogxLayersPhaseCloud(0.5, 0.8, 0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 云的相函数：按 `mode` 选择 Henyey-Greenstein、Cornette-Shanks 或 HG-Draine。
// 按云相位模式组合前向与背向散射，决定云边缘的透光方向。
float ogxLayersPhaseCloud(float x, float g, int mode) // 当前步骤的中间量。
{ // 按参考顺序推进。
    // 模式一用 Cornette-Shanks：比默认多一个前向峰，适合太阳附近的银边；模式二用 Draine 近似。
    if (mode == 1) // Cornette-Shanks。
    { // 按参考顺序推进。
        return (3.0 * (1.0 - g * g) * (1.0 + x * x)) / (25.133 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * x, 1.5)); // 参考实现系数 25.133。
    }
    if (mode == 2) // HG-Draine。
    {
        const float a = 0.9; // 前向权重。
        float gg = g * g; // g 的平方。
        return ((1.0 - gg) * (1.0 + a * x * x)) / (4.0 * (1.0 + (a * (1.0 + 2.0 * gg)) / 3.0) * 3.1415926 * pow(1.0 + gg - 2.0 * g * x, 1.5)); // 参考实现公式。
    }
    float gg = g * g; // 默认 Henyey-Greenstein。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考实现除以 3.14。
}

// 朝光散射：沿光方向取几步云密度，层数与步长按层号决定。
// 云层散射为什么只取少量步长：云体内部没有细节几何，遮挡是连续的密度函数，
// 四到六步已经能把整层走完；步长随光源方向与层厚变化，近处细、远处粗。
// 相位按层选择：积云用前向集中的 HG，高层云用更平的 Cornette-Shanks，
// 积雨云再叠一份宽相位，避免闪电照亮时整块云一起发白。
float ogxLayersGetCloudScattering(OgxLayersCloudSettings s, int layerIndex, vec3 rayPosition, vec3 sunVector,
    vec3 moonVector, float dither, float minHeight, float maxHeight, float density, float cumulonimbusScale,
    float sunVisibility, float moonVisibility, vec3 cameraPos, sampler2D noiseTexture)
{
    int samples = 3; // 默认三步。
    if (layerIndex == 2) samples = 7; // 积雨云七步。
    if (layerIndex == 3 || layerIndex == 4) samples = 2; // 高层云与卷云两步。
    int lod = 0; // 光照取样用低细节。
    float shadow = 0.0; // 遮挡累加。
    vec3 shadowRayPosition = vec3(0.0); // 采样位置。
    float isLarge = 80.0; // 积雨云步长。
    vec3 lightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
    for (int i = 0; i < samples; i++) // 逐样本。
    {
        if (layerIndex == 3 || layerIndex == 4) // 平面云沿日月方向。
        {
            // 向太阳采样时用两百米级步长，云层很厚，细步长只会增加采样数而不改遮挡形状。
            shadowRayPosition = rayPosition + sunVector * sunVisibility * (0.25 + float(i) * dither) * 200.0
                + moonVector * moonVisibility * (0.25 + float(i) * dither) * 200.0; // 沿日月方向取样。
        }
        else if (layerIndex == 0 || layerIndex == 1) // 积云沿混合方向。
        {
            // 月亮方向用小步长，月光弱、云影边缘更容易看出层叠，细采样能保住柔边。
            shadowRayPosition = rayPosition + lightVec * (0.25 + float(i) + dither) * 20.0; // 小步长。
        }
        else if (layerIndex == 2) // 积雨云大步长。
        {
            // 积雨云用大步长，云体尺度大，二十米级步长足够穿过整层而不产生条带。
            shadowRayPosition = rayPosition + lightVec * (0.5 + float(i) + dither) * isLarge; // 大步长。
            isLarge *= 1.374; // 每步放大。
        }
        if (layerIndex != 2) shadow += ogxLayersGetCloudShape(s, layerIndex, lod, shadowRayPosition, minHeight, maxHeight, noiseTexture) * density; // 普通云。
        else shadow += ogxLayersGetCumulonimbusShape(s, lod, shadowRayPosition, minHeight, maxHeight, cumulonimbusScale, cameraPos, noiseTexture).x * density; // 积雨云。
    }
    return shadow; // 交回遮挡量。
}

// 云的光照：直射按 Beer 定律衰减，前后散射按粉末效应插值，间接光按形状抬升。
// 云的单次散射颜色：直射、天光、阴影与相位共同决定云的明暗。
vec3 ogxLayersGetCloudLighting(int layerIndex, float shape, float shapeFaded, float sunShadowMask, vec3 directLightCol,
    vec3 directLightCol2, float indirectShadowMask, vec3 indirectLightCol, vec3 rayPosition, float backScatterPhase,
    vec4 phaseLevels, float backScatterPhase2, vec4 phaseLevels2)
{
    vec3 heightScal = vec3(mix(1.0, 0.5, clamp(rayPosition.y, 0.0, 7000.0) / 7000.0)); // 高度对光色的压缩。
    directLightCol = pow(directLightCol, heightScal); // 直射颜色按高度压暗。
    directLightCol2 = pow(directLightCol2, heightScal); // 第二直射同样。
    // Beer 系数负四：参考实现的消光强度，绝对值越大云越不透光。
    float beerCoef = -4.0; // Beer 系数。
    float powder = min(exp(beerCoef * exp(beerCoef * shapeFaded)) * 3.5, 1.0); // 粉末效应。
    float backscatter = powder * backScatterPhase; // 后向散射。
    float forwardscatter = mix(mix(phaseLevels.x, phaseLevels.y, powder), mix(phaseLevels.z, phaseLevels.w, powder), powder); // 四档相函数插值。
    float backscatter2 = powder * backScatterPhase2; // 第二后向。
    float forwardscatter2 = mix(mix(phaseLevels2.x, phaseLevels2.y, powder), mix(phaseLevels2.z, phaseLevels2.w, powder), powder); // 第二前向。
    float expBeer = 6.28 * exp((beerCoef - 1.0) * sunShadowMask); // 直射透过率。
    vec3 directScattering = expBeer * directLightCol * (forwardscatter + backscatter); // 太阳直射。
    directScattering += expBeer * directLightCol2 * (forwardscatter2 + backscatter2); // 月亮直射。
    // 间接光按形状指数衰减，再按遮蔽掩码平方混合；平方让薄云保留更多环境光。
    vec3 indirectScattering = indirectLightCol * mix(1.0, exp2(-5.0 * shape), indirectShadowMask * indirectShadowMask); // 间接光。
    return indirectScattering + directScattering; // 合成。
}

// 层状云相函数：Henyey-Greenstein 单峰前向散射，`g` 是各向异性，`x` 是夹角余弦。
// 为什么单列一条：参考默认只启用这一种相位，带类型开关的旧实现会多出其它模型的常数。
float ogxLayersPhaseCloudHenyey(float g, float x)
{
    return ogxHenyeyGreensteinPhase(x, g, 1.0 / 3.14); // 参考原式直接写 3.14。
}

// 层状云内散射：沿太阳或月亮方向取几个云形状样本，累加成透过率。
// 参考签名是层号、位置、日月方向、日月高度、抖动与密度；云层上下界与噪声等显式追加。
// 为什么保留循环：采样次数由层号决定，参考也保留运行期循环，合并会改变采样顺序。
float ogxLayersCloudScatteringSamples(int layerIndex, vec3 rayPosition, vec3 sunVector, vec3 moonVector,
    float sunElevation, float moonElevation, float dither, float density,
    float minHeight, float maxHeight, sampler2D noiseTexture, vec3 cameraWorldPos,
    float cloudMovement, float rainAmount, float thunderStrength, float cumulonimbusStrength,
    float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage)
{
    int samples = 3; // 普通层三步。
    int lod = 0; // 阴影只取低细节。
    if (layerIndex == 2) samples = 7; // 积雨云更厚，多取几步。
    if ((layerIndex == 3) || (layerIndex == 4)) samples = 2; // 高层云很薄，两步够用。
    float shadow = 0.0; // 累积的云密度。
    vec3 shadowRayPosition = vec3(0.0); // 采样位置。
    float sunVis = smoothstep(-0.06, 0.01, sunElevation); // 太阳在地平线附近时逐渐变弱。
    sunVis = sunVis * sunVis;
    float moonVis = smoothstep(0.0, 0.075, -moonElevation); // 月亮同样处理。
    moonVis = moonVis * moonVis;
    moonVis *= smoothstep(0.06, -0.06, sunElevation); // 太阳升起后月亮光退场。
    float isLarge = 80; // 积雨云步长。
    vec3 lightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, sunElevation))); // 日月方向按太阳高度混合。
    for (int i = 0; i < samples; i++)
    {
        if ((layerIndex == 3) || (layerIndex == 4))
        {
            shadowRayPosition = rayPosition + sunVector * sunVis * (0.25 + i * dither) * 200.0 + moonVector * moonVis * (0.25 + i * dither) * 200.0; // 高层云沿日月方向短步进。
        }
        else if ((layerIndex == 1) || (layerIndex == 0))
        {
            shadowRayPosition = rayPosition + lightVec * (0.25 + i + dither) * 20.0; // 积云二十米一步。
        }
        else
        {
            shadowRayPosition = rayPosition + lightVec * (0.5 + i + dither) * isLarge; // 积雨云按大范围步长。
        }
        if (layerIndex != 2)
        {
            shadow += ogxLayersCloudShapeLayer(layerIndex, lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                rainAmount, thunderStrength, cloudMovement) * density; // 普通云层取形状。
        }
        else
        {
            shadow += ogxLayersCumulonimbusShapeLayer(lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x * density; // 积雨云取形状。
            isLarge *= 1.374; // 每步再拉远，减少远处重复采样。
        }
    }
    return shadow; // 交回云内遮挡量。
}

// 主体积云步进、低成本透过率与严格入口，具体实现在子文件。
// 子文件：cloud/layers/ray.slang。
/* 层状体积云的单层主步进：五层共用同一套循环与光照，按层号分支；由 `cloud/layers.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`vec4 clouds = ogxCloudLayerMarch(settings, 1, 32, rayPosition, rayDirection, dither, 500.0, 2500.0, sunVector, moonVector, sunScattering, moonScattering, skyScattering, 10000.0, skyColor, cloudDistance, 0.0, phases, 0.0, phases, cameraPos, true, false, noiseTexture, shadowTexture, shadowView, shadowProjection, 2048.0, 1.0);` 参数逐项与签名对应。
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 单层云的步进：参考实现的主循环，逐层处理平面云与积云两条路径。
// `cloudPlaneDistance` 的 `x` 是最近可见云的距离，`y` 是混合权重；由调用方按层合并。
// 平面云分支的提前声明：主入口先分派，具体步进放在文件后半段。
vec4 ogxCloudPlaneMarch(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,     float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,     vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,     inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,     vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,     sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck);
// 积云分支的提前声明：与平面云共用同一组输入，额外带上可见阈值。
vec4 ogxCloudCumulusMarch(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,     float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,     vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,     inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,     vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,     sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck);

// 单层云入口：按层号分派到平面云或积云路径。
vec4 ogxCloudLayerMarch(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,     float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,     vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,     inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,     vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,     sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    float distanceFactor = length(rayDirection); // 一步的世界长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex >= 3) return ogxCloudPlaneMarch(s, layerIndex, samples, rayPosition, rayDirection, dither, minHeight, maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance, sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort, distanceFactor, densityThresholdCheck); // 平面云只取一个样本。
    return ogxCloudCumulusMarch(s, layerIndex, samples, rayPosition, rayDirection, dither, minHeight, maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance, sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort, distanceFactor, densityThresholdCheck); // 积云沿视线步进。
}

// 平面云路径：高层云与卷云只在视线穿过平面时取一个样本，不进入体积步进。
vec4 ogxCloudPlaneMarch(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,     float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,     vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,     inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,     vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,     sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck)
{
    vec3 color = vec3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
    if (layerIndex == 3 || layerIndex == 4) densityThresholdCheck = 0.01; // 平面云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动在极小与阈值之间插值。
    if (layerIndex == 3 || layerIndex == 4) // 平面云路径。
    {
        float density = 0.0; // 这一层的密度。
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        if (layerIndex == 3) density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 高层云。
        else density = s.layers[4].rainDensity * smoothstep(s.layers[4].distance, s.layers[4].distance * 0.5, length(newPos)); // 卷云。
        if (density == 0.0) return vec4(color, totalAbsorbance); // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(cameraPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面的哪一侧。
        if (!deferred && length(newPos) > referenceDistance) return vec4(color, totalAbsorbance); // 世界几何挡住云。
        if (ifAboveOrBelowPlane) return vec4(color, totalAbsorbance); // 背向云层的一侧不步进。
        float shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 取样形状。
        float shapeWithDensity = shape * density; // 乘密度。
        if (shapeWithDensity > mix(1e-5, 0.06, dither)) // 记录最近可见云。
        {
            cloudPlaneDistance.x = length(newPos);
            cloudPlaneDistance.y = 0.0;
        }
        if (shapeWithDensity > 1e-5) // 有云才做光照。
        {
            float sunShadowMask = ogxLayersGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture) * (1.0 - abs(sunVector.y)); // 朝光遮挡。
            float indirectShadowMask = 0.5; // 平面云间接光固定半量。
            vec3 lighting = ogxLayersGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensity, sunShadowMask,
                sunScattering, moonScattering, indirectShadowMask, skyScattering, rayPosition, backScatterPhase, phaseLevels,
                backScatterPhase2, phaseLevels2); // 光照。
            newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视的距离压缩。
            float distancefog = exp2(0.4 * s.distanceFogScale * length(newPos.xz)); // 距离雾。
            vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
            lighting = lighting * distancefog + atmosphereHaze; // 混进雾。
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 这一段的透过率。
            color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 按剩余透过率累加。
            totalAbsorbance *= densityCoeff; // 更新透过率。
        }
        return vec4(color, totalAbsorbance); // 平面云只取一个样本。
    }
}

// 地形阴影：把当前云样本投到阴影图，返回三通道受光系数。
// 为什么单独成函数：积云与平面云都需要同一套投影、边缘压缩和范围判断，复制会漂移。
vec3 ogxCloudTerrainShadow(vec3 relativePos, bool enabled, sampler2D shadowTexture,
    mat4 shadowView, mat4 shadowProjection, float shadowDistort)
{
    vec3 shadow = vec3(1.0); // 默认全亮。
    if (!enabled) return shadow; // 关闭时不采样。
    vec3 fragPosition = ogxMatrixMulPoint(shadowView, relativePos) + ogxMatrixTranslation(shadowView); // 阴影相机空间。
    fragPosition = vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]) * fragPosition
        + ogxMatrixTranslation(shadowProjection); // 阴影投影。
    float distortFactor = shadowDistort > 0.0 ? 1.0 / (log(length(fragPosition.xy) * 0.61 + 1.0) * 1.8) : 1.0; // 参考实现的边缘压缩。
    vec3 shadowPos = vec3(fragPosition.xy * distortFactor, fragPosition.z); // 压缩后的阴影坐标。
    if (abs(shadowPos.x) >= 1.0 - 0.5 / 2048.0 || abs(shadowPos.y) >= 1.0 - 0.5 / 2048.0) return shadow; // 不在阴影图内。
    shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5; // 转零到一。
    return vec3(textureLod(shadowTexture, shadowPos.xy, 0.0).x); // 读阴影。
}

// 闪电照明：普通闪电按水平距离照亮云，积雨云闪电再按距离、密度、高度与时间淡出。
// 单独成函数是为了让主步进只保留光照合成顺序，闪电的两套参数不挤在循环里。
void ogxCloudLightningLighting(inout vec3 lighting, OgxLayersCloudSettings s, int layerIndex,
    vec3 newPos, float density, float shapeWithDensity, float minHeight, float maxHeight,
    vec3 rayPosition, vec3 lightningPos, float horizontalDist)
{
    if (horizontalDist < 7500.0 && s.lightningBoltPosition.w > 0.0) // 普通闪电照亮云。
    {
        float lightningIntensity = exp(-horizontalDist * 0.006) * density * s.lightningFlash; // 闪电强度。
        lighting = mix(lighting, vec3(1.3, 1.5, 3.0), lightningIntensity); // 混向冷白。
    }
    if (s.lightningEnabled <= 0 || (layerIndex != 2 && s.thunderStrength <= 0.0)) return; // 没有积雨云闪电。
    float lightningDist = length(newPos - lightningPos); // 到闪电位距离。
    if (lightningDist >= 6000.0 || length(lightningPos) <= 0.0) return; // 不在照明范围内。
    float lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity) * s.lightningFlash; // 距离与密度权重。
    lightningIntensity *= 1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y); // 高度淡出。
    lightningIntensity *= smoothstep(17000.0, 14000.0, horizontalDist); // 水平淡出。
    lightningIntensity *= s.lightningFade; // 时间淡出。
    vec3 lightningStrength = s.cumulonimbusLightningColor * s.cumulonimbusLightningBrightness * 0.125; // 闪电颜色。
    lighting = mix(lighting, lightningStrength, lightningIntensity); // 混向闪电。
}

// 积云路径：小积云、大积云与积雨云沿视线逐样本累积散射与透过率。
vec4 ogxCloudCumulusMarch(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,     float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,     vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,     inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,     vec4 phaseLevels2, vec3 cameraPos, bool terrainShadowOnClouds, bool deferred, sampler2D noiseTexture,     sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort, float distanceFactor, float densityThresholdCheck)
{
    vec3 color = vec3(0.0); // 累积散射色。
    float totalAbsorbance = 1.0; // 累积透过率。
    if (layerIndex < 3) // 积云路径。
    {
        vec3 newPos = rayPosition - cameraPos; // 相机相对位置。
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(newPos)); // 小积云距离淡出。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(newPos)); // 大积云距离淡出。
        if (layerIndex == 2) density = 0.8; // 积雨云固定密度。
        if (density < 0.01) return vec4(color, totalAbsorbance); // 密度太低跳过。
        vec3 lightningPos = vec3(0.0); // 积雨云闪电位置。
        if (s.lightningEnabled > 0 && layerIndex == 2) lightningPos = ogxLayersGetLightningPosition(s, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 只有积雨云取闪电位。
        vec3 mainLightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, s.sunElevation))); // 日月混合方向。
        float tallness = maxHeight - minHeight; // 层厚。
        bool maxFogDistReached = false; // 是否已经记录最近云。
        for (int i = 0; i < samples; i++) // 主步进循环。
        {
            newPos = rayPosition - cameraPos; // 更新相对位置。
            if (!deferred && length(newPos) > referenceDistance) break; // 世界几何挡住后面。
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 在云层包围盒内。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxLayersGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云标记放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 按高度淡出。
                if (shapeWithDensityFaded > densityThresholdCheck && !maxFogDistReached) // 记录最近可见云。
                {
                    cloudPlaneDistance.x = length(newPos);
                    cloudPlaneDistance.y = 0.0;
                    maxFogDistReached = true;
                }
                if (shapeWithDensityFaded > 1e-5) // 有云才继续。
                {
                    vec3 shadow = ogxCloudTerrainShadow(newPos, terrainShadowOnClouds, shadowTexture, shadowView, shadowProjection, shadowDistort); // 地形阴影。
                    float skylightOcclusion = 1.0; // 参考在极光开启时每个样本重算上层遮挡。
                    // 极光关闭（AURORA_LOCATION=0）的参考变体只算一次；这里按默认开启分支实现，
                    // 保证严格对照的 7621 次采样与默认配置一致。
                    if (layerIndex == 0) // 小积云会被大积云遮住天光。
                    {
                        float upperLayerOcclusion = ogxLayersGetCloudShape(s, 1, 0, rayPosition + vec3(0.0, 1.0, 0.0)
                            * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0), s.layers[1].height,
                            s.layers[1].height + s.layers[1].height / s.layers[1].scale, noiseTexture); // 参考的层顶。
                        skylightOcclusion = mix(mix(0.0, 0.2, densityLarge), 1.0,
                            pow(1.0 - upperLayerOcclusion * densityLarge, 5.0)); // 参考极光分支用五次方。
                    }
                    float indirectShadowMask = 1.0 - min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0); // 间接光遮挡。
                    float sunShadowMask = ogxLayersGetCloudScattering(s, layerIndex, rayPosition, sunVector, moonVector, dither,
                        minHeight, maxHeight, density, 1.0, smoothstep(-0.06, 0.01, s.sunElevation), smoothstep(0.0, 0.075, -s.moonElevation), cameraPos, noiseTexture); // 朝光遮挡。
                    vec3 shadowStartPos = vec3(0.0); // 层间阴影起点。
                    if (layerIndex == 0) // 大积云投到小积云。
                    {
                        shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max((s.layers[1].height + 20.0) - rayPosition.y, 0.0); // 投到上层。
                        sunShadowMask += 3.0 * ogxLayersGetCloudShape(s, 1, 0, shadowStartPos, s.layers[1].height,
                            s.layers[1].height + s.layers[1].tallness / s.layers[1].scale, noiseTexture) * densityLarge; // 上层遮挡。
                    }
                    if (layerIndex != 2 && s.cumulonimbus > 0) // 积雨云投到其他积云。
                    {
                        float angle = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), mainLightVec))), 45.0, 90.0) - 45.0; // 参考保留的角度项，当前不参与距离。
                        shadowStartPos = rayPosition + mainLightVec * 9000.0; // 大步投到积雨云。
                        sunShadowMask += ogxLayersGetCumulonimbusShape(s, 0, shadowStartPos, 600.0, 4600.0 + shadowStartPos.y, 1.0, cameraPos, noiseTexture).x * 3.0; // 积雨云遮挡。
                    }
                    shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max(s.layers[3].height - rayPosition.y, 0.0); // 投到高层云。
                    sunShadowMask += ogxLayersGetCloudShape(s, 3, 0, shadowStartPos, s.layers[3].height, s.layers[3].height, noiseTexture)
                        * s.layers[3].rainDensity * (1.0 - abs(mainLightVec.y)); // 高层云遮挡。
                    vec3 lighting = ogxLayersGetCloudLighting(layerIndex, shapeWithDensity, shapeWithDensityFaded, sunShadowMask,
                        sunScattering * shadow, moonScattering * shadow, indirectShadowMask, skyScattering * skylightOcclusion, rayPosition,
                        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2); // 光照。
                    float horizontalDist = length(newPos.xz - s.lightningBoltPosition.xz); // 普通闪电水平距离。
                    ogxCloudLightningLighting(lighting, s, layerIndex, newPos, density, shapeWithDensity,
                        minHeight, maxHeight, rayPosition, lightningPos, horizontalDist); // 普通与积雨云闪电。
                    lighting += s.auroraLighting * min(max(rayHeightInCloud, 0.0) / max(tallness, 1.0), 1.0) * skylightOcclusion * skylightOcclusion; // 参考的极光按云内高度与天光遮挡叠加。
                    newPos.xz /= max(newPos.y, 0.0) * 0.0025 + 1.0; // 空气透视距离压缩。
                    float distancefog = exp2(s.distanceFogScale * length(newPos.xz)); // 距离雾。
                    vec3 atmosphereHaze = sampledSkyCol - sampledSkyCol * distancefog; // 雾色。
                    lighting = lighting * distancefog + atmosphereHaze; // 混雾。
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded); // 这一段透过率。
                    color += (lighting - lighting * densityCoeff) * totalAbsorbance; // 累加。
                    totalAbsorbance *= densityCoeff; // 更新透过率。
                    if (totalAbsorbance < 1e-5) break; // 已经完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
        return vec4(color, totalAbsorbance); // 交回这一层的颜色与透过率。
    }
}

// 层状云低成本步进提供云影与远景透过率。
// 子文件：cloud/layers/simple.slang。
/* 层状体积云的设置版低成本步进：只累计透过率，供云影与远景使用；由 `cloud/layers.slang` 内联引入。
可复制示例：`vec4 t = ogxLayersGetVolumetricCloudsSimple(settings, dither, lightDir, offset, startPos, cameraPos, noiseTex);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 云影步进：只算透过率，不算光照，供阴影程序低成本使用。
float ogxCloudLayerMarchSimple(OgxLayersCloudSettings s, int layerIndex, int samples, vec3 rayPosition, // 当前步骤的中间量。
    vec3 rayDirection, float dither, float minHeight, float maxHeight, vec3 startPos, vec3 cameraPos, // 当前步骤的中间量。
    sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 初始完全透明。
    float distanceFactor = length(rayDirection); // 一步长度。
    float densityThresholdCheck = 0.0; // 可见阈值。
    if (layerIndex == 0) densityThresholdCheck = 0.06; // 小积云。
    if (layerIndex == 1 || layerIndex == 2) densityThresholdCheck = 0.02; // 大积云与积雨云。
    if (layerIndex == 3) densityThresholdCheck = 0.01; // 高层云。
    densityThresholdCheck = mix(1e-5, densityThresholdCheck, dither); // 按抖动插值。
    if (layerIndex == 3) // 高层云单样本。
    {
        vec3 newPos = rayPosition - startPos; // 相对起点。
        float density = s.layers[3].rainDensity * smoothstep(s.layers[3].distance, s.layers[3].distance * 0.5, length(newPos)); // 距离密度。
        if (density == 0.0) return totalAbsorbance; // 距离外没有云。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0))
            * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在平面哪一侧。
        if (ifAboveOrBelowPlane) return totalAbsorbance; // 背向不步进。
        float shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 形状。
        float shapeWithDensity = shape * density; // 密度。
        if (shapeWithDensity > 1e-5) totalAbsorbance *= exp(-distanceFactor * shapeWithDensity); // 乘透过率。
        return totalAbsorbance; // 交回透过率。
    }
    if (layerIndex < 3) // 积云。
    {
        float densityLarge = s.layers[1].rainDensity; // 大积云密度。
        float density = 0.0; // 这一层密度。
        if (layerIndex == 0) density = s.layers[0].rainDensity * smoothstep(s.layers[0].distance, s.layers[0].distance * 0.5, length(rayPosition - startPos)); // 小积云。
        if (layerIndex == 1) density = s.layers[1].rainDensity * smoothstep(s.layers[1].distance, s.layers[1].distance * 0.5, length(rayPosition - startPos)); // 大积云。
        if (layerIndex == 2) density = 0.8; // 积雨云。
        if (density < 0.01) return totalAbsorbance; // 密度太低。
        float tallness = maxHeight - minHeight; // 层厚。
        for (int i = 0; i < samples; i++) // 主循环。
        {
            float rayHeightInCloud = rayPosition.y - minHeight; // 层内高度。
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 包围盒。
            {
                float shape = 0.0; // 形状。
                float isLarge = 1.0; // 大云权重。
                if (layerIndex != 2) shape = ogxLayersGetCloudShape(s, layerIndex, 1, rayPosition, minHeight, maxHeight, noiseTexture); // 普通云。
                else
                {
                    vec2 cumulonimbusCloud = ogxLayersGetCumulonimbusShape(s, 1, rayPosition, minHeight, maxHeight, 1.0, cameraPos, noiseTexture); // 积雨云。
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y; // 大云放大。
                }
                float shapeWithDensity = shape * density * isLarge; // 总密度。
                float shapeWithDensityFaded = shape * density * pow(clamp(rayHeightInCloud / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 高度淡出。
                if (shapeWithDensityFaded > 1e-5) // 有云。
                {
                    totalAbsorbance *= exp(-distanceFactor * shapeWithDensityFaded); // 乘透过率。
                    if (totalAbsorbance < 1e-5) break; // 完全不透明。
                }
            }
            rayPosition += rayDirection; // 前进。
        }
    }
    return totalAbsorbance; // 交回透过率。
}

// 云影总入口：返回四个透过率，供阴影程序按层重建云影。
vec4 ogxLayersGetVolumetricCloudsSimple(OgxLayersCloudSettings s, vec2 dither, vec3 lightDir, vec2 offset,
    vec3 startPos, vec3 cameraPos, sampler2D noiseTexture)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - s.layers[0].height, 0.0) / 100.0, 0.0, 1.0); // 相机高度。
    vec3 normPlayerPos = lightDir; // 光线方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点。
    int samples = 5; // 固定五步。
    vec3 cloudDist = vec3(1.0); // 水平步长。
    float cloudheight = 5.0; // 高层云厚度。
    float minHeight = s.layers[3].height; // 高层云底。
    float maxHeight = cloudheight + minHeight; // 高层云顶。
    cloudDist.xz = vec2(255.0); // 平面云水平步长。
    vec3 rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步。
    vec3 rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
    rayPosition.xz += offset; // 阴影偏移。
    float altoStratusClouds = ogxCloudLayerMarchSimple(s, 3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        startPos, cameraPos, noiseTexture); // 高层云。
    totalAbsorbance *= altoStratusClouds; // 更新透过率。
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        largeCumulusClouds = ogxCloudLayerMarchSimple(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 大积云。
        totalAbsorbance *= largeCumulusClouds; // 更新透过率。
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5) // 还有光才继续。
    {
        cloudheight = s.layers[0].tallness / s.layers[0].scale; // 小积云厚度。
        minHeight = s.layers[0].height; // 小积云底。
        maxHeight = cloudheight + minHeight; // 小积云顶。
        cloudDist.xz = vec2(255.0); // 水平步长。
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 分层步长。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 起点。
        rayPosition.xz += offset; // 偏移。
        smallCumulusClouds = ogxCloudLayerMarchSimple(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, startPos, cameraPos, noiseTexture); // 小积云。
        totalAbsorbance *= smallCumulusClouds; // 更新透过率。
    }
    return vec4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四个透过率。
}

// 层状云参考签名步进提供天气参数入口。
// 子文件：cloud/layers/transmittance.slang。
/* 层状体积云的参考签名低成本步进：天气与覆盖参数显式传入，不读设置结构体；由 `cloud/layers.slang` 内联引入。
可复制示例：`vec4 t = ogxLayersCloudTransmittanceSimple(dither, lightDir, offset, startPos, noiseTex, cameraPos, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 层状云低成本步进：只累计透过率，不做光照，供云影与远景使用。
// 参考签名给层号、步数、位置与方向、抖动与上下界；噪声、天气与覆盖率显式追加。
// 透射率为什么按层累加：每层云的高度与密度不同，先分别算吸收再相乘，
// 比把所有层混成一个密度更接近参考，也能让高层云在低层云之上正确遮挡。
// 阈值检查在循环前：密度太低时直接返回，省掉整段步进；
// 射线在云层上方或下方时也直接返回，避免无意义的采样。
float ogxLayersCloudAbsorbanceSimple(int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection, // 当前步骤的中间量。
    float dither, float minHeight, float maxHeight, vec3 startPos, // 当前步骤的中间量。
    sampler2D noiseTexture, vec3 cameraWorldPos, float cloudMovement, float rainAmount, // 当前步骤的中间量。
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage, // 当前步骤的中间量。
    float largeCumulusCoverage, float smallCumulusCoverage, // 当前步骤的中间量。
    float altostratusRain, float largeCumulusRain, float smallCumulusRain) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 每步长度。
    float densityTresholdCheck = 0.0; // 密度阈值，按层选择。
    if (layerIndex == 0) densityTresholdCheck = 0.06; // 按参考条件选择这一支。
    if (layerIndex == 1 || layerIndex == 2) densityTresholdCheck = 0.02; // 按参考条件选择这一支。
    if (layerIndex == 3) densityTresholdCheck = 0.01; // 按参考条件选择这一支。
    densityTresholdCheck = mix(1e-5, densityTresholdCheck, dither); // 用抖动在极小值与阈值之间插值。
    if (layerIndex == 3) // 高层云只做一次平面近似。
    { // 按参考顺序推进。
        vec3 newPos = rayPosition - startPos; // 当前步骤的中间量。
        float density = altostratusRain; // 当前步骤的中间量。
        density *= smoothstep(150000.0, 150000.0 * 0.5, length(newPos)); // 超出距离后淡出。
        if (density == 0.0) return totalAbsorbance; // 交回这一段的计算结果。
        bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在云层上方或下方时就跳过。
        if (ifAboveOrBelowPlane) return totalAbsorbance; // 交回这一段的计算结果。
        float shape = ogxLayersCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight, // 当前步骤的中间量。
            noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage, // 按参考顺序推进。
            rainAmount, thunderStrength, cloudMovement); // 按参考顺序推进。
        float shapeWithDensity = shape * density; // 当前步骤的中间量。
        if (shapeWithDensity > 1e-5) // 按参考条件选择这一支。
        { // 按参考顺序推进。
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 单步吸收。
            totalAbsorbance *= densityCoeff; // 按参考写法推进这一步。
        } // 按参考顺序推进。
        return totalAbsorbance; // 交回这一段的计算结果。
    }
    if (layerIndex < 3) // 积云与积雨云按步数前进。
    {
        vec3 newPos = rayPosition - startPos;
        float densityLarge = ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength);
        float density = 0.0;
        if (layerIndex == 0) density = ogxLayersGetRainDensity(smallCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
        if (layerIndex == 1) density = ogxLayersGetRainDensity(largeCumulusRain, rainAmount, thunderStrength) * smoothstep(100000.0, 100000.0 * 0.5, length(newPos));
        if (layerIndex == 2) density = 0.8;
        if (density < 0.01) return totalAbsorbance;
        float tallness = maxHeight - minHeight;
        for (int i = 0; i < samples; i++)
        {
            newPos = rayPosition - startPos;
            float rayHeightInCloud = rayPosition.y - minHeight;
            if (clamp(rayPosition.y - maxHeight, 0.0, 1.0) < 1.0 && clamp(rayHeightInCloud, 0.0, 1.0) > 0.0) // 只处理云层内部的采样。
            {
                float shape = 0.0;
                float isLarge = 1.0;
                if (layerIndex != 2)
                {
                    shape = ogxLayersCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
                        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                        rainAmount, thunderStrength, cloudMovement);
                }
                else
                {
                    vec2 cumulonimbusCloud = ogxLayersCumulonimbusShapeLayer(1, rayPosition, minHeight, maxHeight,
                        noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength);
                    shape = cumulonimbusCloud.x;
                    isLarge = 1.0 + 4.0 * cumulonimbusCloud.y;
                }
                float shapeWithDensity = shape * density * isLarge;
                float shapeWithDensityFaded = shape * density * pow(clamp((rayHeightInCloud) / (max(tallness, 1.0) * 0.25), 0.0, 1.0), 2.0); // 底部淡出。
                if (shapeWithDensityFaded > 1e-5)
                {
                    float densityCoeff = exp(-distanceFactor * shapeWithDensityFaded);
                    totalAbsorbance *= densityCoeff;
                    if (totalAbsorbance < 1e-5) break; // 已经全黑就提前结束。
                }
            }
            rayPosition += rayDirection; // 前进一步。
        }
    }
    return totalAbsorbance; // 交回透过率。
}

// 层状云影总入口的简单版：三层云各走一次低成本步进，乘成总透过率。
// 参考签名是抖动、光照方向、偏移与起点；云噪声、天气、覆盖率与相机位置显式追加。
// 三层透射率从高到低叠加：高层云先算，积云其次，小积云最后；
// 每层都把剩余透射率乘进去，前一层挡住的光不会在后一层重复计算。
// 采样数只给积云与小积云，高层云很薄，单样本就够；
// 这样在保持参考顺序的同时，把最贵的步进留给真正有体积的层。
vec4 ogxLayersCloudTransmittanceSimple(vec2 dither, vec3 lightDir, vec2 offset, vec3 startPos,
    sampler2D noiseTexture, vec3 cameraWorldPos, float cloudMovement, float rainAmount,
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage,
    float largeCumulusCoverage, float smallCumulusCoverage,
    float altostratusRain, float largeCumulusRain, float smallCumulusRain)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraWorldPos.y - 250.0, 0.0) / 100.0, 0.0, 1.0); // 相机离云底越近，抬高越少。
    vec3 normPlayerPos = lightDir; // 光照方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角把光线抬高一点。
    int samples = 5; // 每层固定五步。
    vec3 cloudDist = vec3(1.0); // 水平步长。
    vec3 rayDirection; // 步进方向。
    vec3 rayPosition; // 步进起点。
    float cloudheight; // 云层厚度。
    float minHeight; // 云底。
    float maxHeight; // 云顶。
    float altoStratusClouds = 1.0; // 高层云透过率。
    cloudheight = 5.0;
    minHeight = 5000.0;
    maxHeight = cloudheight + minHeight;
    cloudDist.xz = vec2(255.0);
    rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist)); // 单步长度。
    rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight); // 找到进入云层的起点。
    rayPosition.xz += offset; // 阴影偏移。
    altoStratusClouds = ogxLayersCloudAbsorbanceSimple(3, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
        noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
        altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        altostratusRain, largeCumulusRain, smallCumulusRain); // 高层云。
    totalAbsorbance *= altoStratusClouds;
    float largeCumulusClouds = 1.0; // 大积云透过率。
    if (totalAbsorbance > 1e-5)
    {
        cloudheight = 280.0;
        minHeight = 400.0;
        maxHeight = cloudheight + minHeight;
        cloudDist.xz = vec2(255.0);
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples)); // 按步数均分厚度。
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        largeCumulusClouds = ogxLayersCloudAbsorbanceSimple(1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 大积云。
        totalAbsorbance *= largeCumulusClouds;
    }
    float smallCumulusClouds = 1.0; // 小积云透过率。
    if (totalAbsorbance > 1e-5)
    {
        cloudheight = 130.0 / 1.0;
        minHeight = 250.0;
        maxHeight = cloudheight + minHeight;
        minHeight = 250.0 - 350.0; // 参考把小积云底向下扩了三百五十米。
        maxHeight = cloudheight + minHeight;
        cloudDist.xz = vec2(255.0);
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples));
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        smallCumulusClouds = ogxLayersCloudAbsorbanceSimple(0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 小积云。
        totalAbsorbance *= smallCumulusClouds;
    }
    return vec4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四层透过率。
}

/*
维护说明：低成本透过率为什么这样分层。

层号与用途：
    零号是小积云，云底二百五十米，向下扩三百五十米，厚度一百三十米。
    一号是大积云，云底四百米，厚度二百八十米。
    二号是积雨云，密度固定零点八，形状走积雨云的塔状分支。
    三号是高层云，只做一次平面近似，不进入步进循环。

采样顺序：
    总入口固定从高层云开始，再算大积云，最后算小积云。
    顺序不能换：后面的层会把当前总透过率当作提前结束条件，
    先算哪一层会改变一共执行多少次噪声采样，严格对照会直接报差异。

提前结束：
    每一层结束都把透过率乘进总透过率；低于十万分之一就跳过后面的层。
    这是参考实现的短路，不是优化开关；关掉它会多做采样，画面也会略暗。

抖动：
    密度阈值用抖动系数在极小值与层阈值之间插值。
    这样做是为了让相邻像素的可见边缘错开，避免云影出现规则的同心圆。

距离淡出：
    积云用 smoothstep 在一百公里到五十公里之间淡出。
    淡出的是密度而不是透过率；先乘密度再做指数吸收，远处的云影才会逐渐变浅。

相机高度：
    小积云的云底曾被向下扩了三百五十米，这是参考的固定写法。
    它让低空相机也能看到小积云投下的影子，不能按“云底应该更高”去改。

单位：
    minHeight、maxHeight、rayDirection 与 startPos 全部用方块。
    cloudDist 只是构造步长时的水平尺度，不是真实距离，不能拿去和世界坐标比较。

修改入口时先确认三件事：
    一是层号与云底、云顶的对应关系没有变；
    二是高层云仍然只走一次平面采样；
    三是四层返回值顺序仍然是“小积云、大积云、高层云、总透过率”。
*/

/*
云影边缘要用测试世界截图核对。
步长与阈值成组调整。
层号越界返回全通。
*/

// 层状云严格入口提供参考默认常数。
// 子文件：cloud/layers/exact.slang。
/* 层状体积云的严格入口：按参考签名重排参数并填写参考默认常数；由 `cloud/layers.slang` 内联引入。
可复制示例：`vec4 c = ogxLayersGetVolumetricCloudsExact(viewPos, dither, sunVector, moonVector, sunColor, moonColor, indirectColor, cloudPlane, cloudDist, settings, cameraPos, farPlane, dhFarPlane, modelViewInverse, 32, false, false, 1.0, true, layer0, layer1, layer2, layer3, layer4, auroraRgb, 1.0, 1.0, lightningRgb, noiseTex, shadowTex, shadowView, shadowProj, 2048.0, 1.0, skyTex, texel);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 严格参考签名的单层云步进入口：参考参数在前，云设置、相机与阴影资源追加在后。
// 主体仍由 `ogxCloudLayerMarch` 执行，入口只负责把显式参数重新排好。
// 五层云的高度、厚度与距离按参考默认配置传入，避免把宿主菜单常数藏进结构体。
vec4 ogxCloudLayerMarchExact(int layerIndex, int samples, vec3 rayPosition, vec3 rayDirection,
    float dither, float minHeight, float maxHeight, vec3 sunVector, vec3 moonVector, vec3 sunScattering,
    vec3 moonScattering, vec3 skyScattering, float referenceDistance, vec3 sampledSkyCol,
    inout vec2 cloudPlaneDistance, float backScatterPhase, vec4 phaseLevels, float backScatterPhase2,
    vec4 phaseLevels2, OgxLayersCloudSettings settings, vec3 cameraPos, bool terrainShadowOnClouds,
    bool deferred, sampler2D noiseTexture, sampler2D shadowTexture, mat4 shadowView,
    mat4 shadowProjection, float shadowResolution, float shadowDistort, vec4 layer0Size,
    vec4 layer1Size, vec4 layer2Size, vec3 layer3Size, vec3 layer4Size, vec3 auroraRgb,
    float auroraBrightness, float auroraAmount, vec3 customLightningRgb)
{
    settings.layers[0].height = layer0Size.x; // 小积云高度。
    settings.layers[0].tallness = layer0Size.y; // 小积云厚度。
    settings.layers[0].scale = layer0Size.z; // 小积云水平尺度。
    settings.layers[0].distance = layer0Size.w; // 小积云可见距离。
    settings.layers[1].height = layer1Size.x; // 大积云高度。
    settings.layers[1].tallness = layer1Size.y; // 大积云厚度。
    settings.layers[1].scale = layer1Size.z; // 大积云水平尺度。
    settings.layers[1].distance = layer1Size.w; // 大积云可见距离。
    settings.layers[2].height = layer2Size.x; // 高层云高度。
    settings.layers[2].distance = layer2Size.y; // 高层云可见距离。
    settings.layers[2].scale = layer2Size.z; // 高层云水平尺度。
    settings.layers[3].height = layer3Size.x; // 卷云高度。
    settings.layers[3].distance = layer3Size.y; // 卷云可见距离。
    settings.layers[3].scale = layer3Size.z; // 卷云水平尺度。
    settings.layers[4].height = layer4Size.x; // 额外云层高度。
    settings.layers[4].distance = layer4Size.y; // 额外云层可见距离。
    settings.layers[4].scale = layer4Size.z; // 额外云层水平尺度。
    settings.auroraLighting = 0.015 * auroraBrightness * (sin(auroraRgb + 0.63) * 0.5 + 0.5) * auroraAmount
        * smoothstep(0.0, -0.1, sunVector.y) * smoothstep(0.1, 0.0, moonVector.y); // 参考的极光光照。
    settings.cumulonimbus = 1; // 参考默认 CUMULONIMBUS=1。
    settings.cumulonimbusLightningBrightness = 100.0; // 参考默认 CUMULONIMBUS_LIGHTNING_BRIGHTNESS。
    settings.cumulonimbusLightningColor = vec3(customLightningRgb.x, 1.05 * customLightningRgb.y,
        1.22 * customLightningRgb.z); // 参考的积雨云闪电颜色。
    return ogxCloudLayerMarch(settings, layerIndex, samples, rayPosition, rayDirection, dither, minHeight,
        maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, referenceDistance,
        sampledSkyCol, cloudPlaneDistance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2,
        cameraPos, terrainShadowOnClouds, deferred, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调同一份层步进。
}

// 严格参考签名的体积云总入口：参考参数在前，云层尺寸、极光与天空盒资源追加在后。
// 云层尺寸和极光参数在这里写成常数，参考的首页天空盒查表也在这里完成，采样顺序与参考一致。
vec4 ogxLayersGetVolumetricCloudsExact(vec3 viewPos, vec2 dither, vec3 sunVector, vec3 moonVector,
    vec3 directLightCol, vec3 directLightCol2, vec3 indirectLightCol, inout float cloudPlaneDistance,
    inout vec2 cloudDistance, OgxLayersCloudSettings settings, vec3 cameraPos, float farPlane,
    float dhFarPlane, mat4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, vec4 layer0Size, vec4 layer1Size, vec4 layer2Size,
    vec3 layer3Size, vec3 layer4Size, vec3 auroraRgb, float auroraBrightness, float auroraAmount,
    vec3 customLightningRgb, sampler2D noiseTexture, sampler2D shadowTexture, mat4 shadowView,
    mat4 shadowProjection, float shadowResolution, float shadowDistort, sampler2D skyTexture, vec2 texelSize)
{
    settings.layers[0].height = layer0Size.x; // 小积云高度。
    settings.layers[0].tallness = layer0Size.y; // 小积云厚度。
    settings.layers[0].scale = layer0Size.z; // 小积云水平尺度。
    settings.layers[0].distance = layer0Size.w; // 小积云可见距离。
    settings.layers[1].height = layer1Size.x; // 大积云高度。
    settings.layers[1].tallness = layer1Size.y; // 大积云厚度。
    settings.layers[1].scale = layer1Size.z; // 大积云水平尺度。
    settings.layers[1].distance = layer1Size.w; // 大积云可见距离。
    settings.layers[2].height = layer2Size.x; // 高层云高度。
    settings.layers[2].distance = layer2Size.y; // 高层云可见距离。
    settings.layers[2].scale = layer2Size.z; // 高层云水平尺度。
    settings.layers[3].height = layer3Size.x; // 卷云高度。
    settings.layers[3].distance = layer3Size.y; // 卷云可见距离。
    settings.layers[3].scale = layer3Size.z; // 卷云水平尺度。
    settings.layers[4].height = layer4Size.x; // 额外云层高度。
    settings.layers[4].distance = layer4Size.y; // 额外云层可见距离。
    settings.layers[4].scale = layer4Size.z; // 额外云层水平尺度。
    settings.auroraLighting = 0.015 * auroraBrightness * (sin(auroraRgb + 0.63) * 0.5 + 0.5) * auroraAmount
        * smoothstep(0.0, -0.1, sunVector.y) * smoothstep(0.1, 0.0, moonVector.y); // 参考的极光光照。
    settings.cumulonimbus = 1; // 参考默认 CUMULONIMBUS=1。
    settings.cumulonimbusLightningBrightness = 100.0; // 参考默认 CUMULONIMBUS_LIGHTNING_BRIGHTNESS。
    settings.cumulonimbusLightningColor = vec3(customLightningRgb.x, 1.05 * customLightningRgb.y,
        1.22 * customLightningRgb.z); // 参考的积雨云闪电颜色。
    return ogxLayersGetVolumetricClouds(settings, viewPos, dither, sunVector, moonVector, directLightCol,
        directLightCol2, indirectLightCol, cloudPlaneDistance, cloudDistance, cameraPos, skyTexture, texelSize,
        farPlane, dhFarPlane, modelViewInverse, samples, deferred, skyGround, skyBrightness,
        terrainShadowOnClouds, noiseTexture, shadowTexture, shadowView, shadowProjection,
        shadowResolution, shadowDistort); // 转调五层总入口。
}

// 单层步进准备：层厚、水平步长与采样数决定一步的长度，起点压到该层云底与云顶之间。
// 五层原来各写两行同样的式子，抽成 ???? 后改步长公式只改一处，层与层之间不会漂移。
void ogxLayersLayerRay(vec3 viewDir, float thickness, vec3 cloudDist, int samples, vec2 dither,
    vec3 cameraPos, float minHeight, out vec3 rayDirection, out vec3 rayPosition)
{
    rayDirection = viewDir * (thickness / length(viewDir / cloudDist) / float(samples)); // 一层走完的步长。
    rayPosition = ogxLayersGetRayOrigin(rayDirection, cameraPos, dither.y, minHeight, minHeight + thickness); // 起点压到云层平面。
}

// 五层体积云总入口：按参考实现的顺序步进小积云、大积云、积雨云、高层云与卷云，再按相机高度混合。
// 为什么保留为单一入口：五层顺序、相机高度混合与距离合成共享同一份状态，拆开会让二十多个参数
// 在子函数之间来回传递，反而更难核对参考顺序；其余超过一百行的函数已按算法拆分。
// 天空色由本函数在步进起点处查天空盒，与参考 GetVolumetricClouds 的采样位置一致。
vec4 ogxLayersGetVolumetricClouds(OgxLayersCloudSettings s, vec3 viewPos, vec2 dither, vec3 sunVector,
    vec3 moonVector, vec3 directLightCol, vec3 directLightCol2, vec3 indirectLightCol,
    inout float cloudPlaneDistance, inout vec2 cloudDistance, vec3 cameraPos, sampler2D skyTexture, vec2 texelSize,
    float farPlane, float dhFarPlane, mat4 modelViewInverse, int samples, bool deferred, bool skyGround,
    float skyBrightness, bool terrainShadowOnClouds, sampler2D noiseTexture,
    sampler2D shadowTexture, mat4 shadowView, mat4 shadowProjection, float shadowResolution, float shadowDistort)
{
    vec3 color = vec3(0.0); // 累积颜色。
    float totalAbsorbance = 1.0; // 累积透过率。
    vec4 cloudColor = vec4(color, totalAbsorbance); // 当前层结果。
    vec4 cloudColorOriginal = cloudColor; // 每层重置用。
    float cloudheight = s.layers[0].tallness / s.layers[0].scale; // 第一层厚度。
    float minHeight = s.layers[0].height; // 第一层云底。
    float maxHeight = cloudheight + minHeight; // 第一层云顶。
    float heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - minHeight, 0.0) / 100.0, 0.0, 1.0); // 相机相对云层的高度。
    float maxdist = dhFarPlane > 0.0 ? dhFarPlane - 16.0 : farPlane + 16.0 * 5.0; // 最大可见距离。
    float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 1.0e8; // 参考实现的距离哨兵。
    vec4 normPlayerPos = vec4(ogxMatrixMulPoint(modelViewInverse, viewPos) + ogxMatrixTranslation(modelViewInverse), 1.0); // 视空间转世界。
    normPlayerPos = normalize(normPlayerPos); // 单位视线方向。
    float sdotv = dot(sunVector, normPlayerPos.xyz); // 太阳与视线夹角。
    float sdotv2 = dot(moonVector, normPlayerPos.xyz); // 月亮与视线夹角。
    if (skyGround) normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角抬高一点，避免云压到地平线。
    float cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
        clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 相机在层内时水平步长更小。
    vec3 cloudDist = vec3(1.0); // 水平与竖直步长。
    cloudDist.xz = mix(vec2(255.0), vec2(5.5), cloudMix); // 层内 5.5，层外 255。
    vec3 rayDirection; // 当前层的步长方向。
    vec3 rayPosition; // 当前层的步进起点。
    ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, min(cloudDist, vec3(0.05 * lViewPosM)), samples, dither,
        cameraPos, minHeight, rayDirection, rayPosition); // 小积云：层内步长更小。
    vec3 sampledSkyCol = ogxSkyGradientLookup(normalize(rayPosition - cameraPos), skyTexture, texelSize) / 1200.0; // 参考在第一步后查天空盒。
    if (skyGround) // 参考 SKY_GROUND 分支：地面视角把天空色混向间接光。
    {
        if (s.cumulonimbus > 1.0) heightRelativeToClouds = clamp(1.0 - max(cameraPos.y - 6000.0, 0.0) / 100.0, 0.0, 1.0); // 积雨云开启时改用六千米基准。
        sampledSkyCol = mix(sampledSkyCol, indirectLightCol, heightRelativeToClouds); // 与参考相同的混合。
    }
    sampledSkyCol *= skyBrightness; // 天空亮度。
    vec3 playerPos = ogxMatrixMulPoint4(modelViewInverse, vec4(viewPos, 1.0)).xyz; // 相机相对世界位置。
    float maxLength = min(length(playerPos), farPlane) / max(length(playerPos), 1e-4); // 限制到远平面。
    playerPos *= maxLength; // 截断。
    float startDistance = length(playerPos); // 到像素的距离。
    float sunVis = smoothstep(-0.06, 0.1, s.sunElevation); // 太阳可见度。
    float moonVis = smoothstep(0.0, 0.075, -s.moonElevation); // 月亮可见度。
    float backScatterPhase = 0.0; // 太阳后向散射。
    vec4 phaseLevels = vec4(0.0); // 太阳四档相函数。
    if (sunVis > 0.0) // 太阳在地平线上才算。
    {
        backScatterPhase = ogxLayersPhaseCloud(-sdotv, 0.25, 0) * 2.0; // 后向。
        phaseLevels = vec4(ogxLayersPhaseCloud(sdotv, 0.80, 0), ogxLayersPhaseCloud(sdotv, 0.55, 0),
            ogxLayersPhaseCloud(sdotv, 0.35, 0), ogxLayersPhaseCloud(sdotv, 0.10, 0)); // 四档前向。
    }
    float backScatterPhase2 = 0.0; // 月亮后向。
    vec4 phaseLevels2 = vec4(0.0); // 月亮四档。
    if (moonVis > 0.0) // 月亮在地平线上才算。
    {
        backScatterPhase2 = ogxLayersPhaseCloud(-sdotv2, 0.25, 0) * 2.0; // 后向。
        phaseLevels2 = vec4(ogxLayersPhaseCloud(sdotv2, 0.80, 0), ogxLayersPhaseCloud(sdotv2, 0.55, 0),
            ogxLayersPhaseCloud(sdotv2, 0.35, 0), ogxLayersPhaseCloud(sdotv2, 0.10, 0)); // 四档前向。
    }
    vec3 sunScattering = directLightCol * sunVis * sunVis; // 太阳散射。
    vec3 moonScattering = directLightCol2 * moonVis * moonVis * (1.0 - sunVis * sunVis); // 月亮散射。
    vec3 skyScattering = indirectLightCol * (1.0 + sunVis); // 天空散射。
    bool mixBelowLayer0 = cameraPos.y < s.layers[0].height + s.layers[0].tallness; // 相机是否在小积云下方。
    bool mixBelowLayer1 = cameraPos.y < s.layers[1].height; // 相机是否在大积云下方。
    vec4 smallCumulusClouds = cloudColorOriginal; // 小积云结果。
    vec2 cloudLayer0Distance = vec2(startDistance, 1.0); // 小积云距离。
    smallCumulusClouds = ogxCloudLayerMarch(s, 0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
        sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer0Distance,
        backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
        shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 小积云。
    cloudColor.a *= smallCumulusClouds.a; // 更新透过率。
    float smallCumulusDistance = length(rayPosition - cameraPos); // 小积云命中距离。
    vec4 largeCumulusClouds = cloudColorOriginal; // 大积云结果。
    vec2 cloudLayer1Distance = vec2(startDistance, 1.0); // 大积云距离。
    if (cloudColor.a > 1e-5 || !mixBelowLayer1) // 有剩余光且相机位置合适。
    {
        cloudheight = s.layers[1].tallness; // 大积云厚度。
        minHeight = s.layers[1].height; // 大积云底。
        maxHeight = cloudheight + minHeight; // 大积云顶。
        cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPos.y), 0.0,
            clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPos.y), 0.0, 1.0)); // 重算混合。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), cloudMix); // 大积云水平步长。
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, samples, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 大积云：按当前层厚重算。
        largeCumulusClouds = ogxCloudLayerMarch(s, 1, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer1Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 大积云。
        cloudColor.a *= largeCumulusClouds.a; // 更新透过率。
    }
    float largeCumulusDistance = length(rayPosition - cameraPos); // 大积云命中距离。
    vec4 cumulonimbusClouds = cloudColorOriginal; // 积雨云结果。
    vec2 cloudLayer4Distance = vec2(startDistance, 1.0); // 积雨云距离。
    if (s.cumulonimbus > 0 && (cloudColor.a > 1e-5 || !mixBelowLayer0)) // 开启积雨云。
    {
        cloudheight = 4000.0; // 积雨云厚度。
        minHeight = 600.0; // 积雨云底。
        maxHeight = cloudheight + minHeight; // 积雨云顶。
        int cumulonimbusSamples = 2 * samples; // 两倍样本。
        cloudDist.xz = vec2(8.0); // 固定水平步长。
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, cumulonimbusSamples, dither, cameraPos,
            minHeight, rayDirection, rayPosition); // 积雨云：样本翻倍，步长相应缩短。
        cumulonimbusClouds = ogxCloudLayerMarch(s, 2, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight,
            maxHeight, sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol,
            cloudLayer4Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds,
            deferred, noiseTexture, shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 积雨云。
        cloudColor.a *= cumulonimbusClouds.a; // 更新透过率。
    }
    float cumulonimbusDistance = length(rayPosition - cameraPos); // 积雨云命中距离。
    vec4 altoStratusClouds = cloudColorOriginal; // 高层云结果。
    vec2 cloudLayer2Distance = vec2(startDistance, 1.0); // 高层云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画高层云。
    {
        cloudheight = 5.0; // 高层云很薄。
        minHeight = s.layers[3].height; // 高层云底。
        maxHeight = cloudheight + minHeight; // 高层云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, 1, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 高层云：单步走到层顶。
        altoStratusClouds = ogxCloudLayerMarch(s, 3, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer2Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 高层云。
        cloudColor.a *= altoStratusClouds.a; // 更新透过率。
    }
    vec4 cirrusClouds = cloudColorOriginal; // 卷云结果。
    vec2 cloudLayer3Distance = vec2(startDistance, 1.0); // 卷云距离。
    if (cloudColor.a > 1e-5) // 有剩余光才画卷云。
    {
        cloudheight = 5.0; // 卷云很薄。
        minHeight = s.layers[4].height; // 卷云底。
        maxHeight = cloudheight + minHeight; // 卷云顶。
        cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight, 0.0,
            clamp((maxHeight - 15.0) - cameraPos.y, 0.0, 1.0))); // 层内水平步长。
        ogxLayersLayerRay(normPlayerPos.xyz, cloudheight, cloudDist, 1, dither, cameraPos, minHeight,
            rayDirection, rayPosition); // 卷云：单步走到层顶。
        cirrusClouds = ogxCloudLayerMarch(s, 4, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight,
            sunVector, moonVector, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer3Distance,
            backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2, cameraPos, terrainShadowOnClouds, deferred, noiseTexture,
            shadowTexture, shadowView, shadowProjection, shadowResolution, shadowDistort); // 卷云。
        cloudColor.a *= cirrusClouds.a; // 更新透过率。
    }
    if (cameraPos.y > s.layers[1].height) // 相机在大积云上方时交换远近层。
    {
        vec2 temp = cloudLayer1Distance;
        cloudLayer1Distance = cloudLayer0Distance;
        cloudLayer0Distance = temp;
    }
    float tempDistance = mix(cloudLayer2Distance.x, cloudLayer3Distance.x, cloudLayer2Distance.y); // 高层与卷云按权重混合。
    tempDistance = mix(cloudLayer1Distance.x, tempDistance, cloudLayer1Distance.y); // 大积云再混合。
    cloudPlaneDistance = mix(cloudLayer0Distance.x, tempDistance, cloudLayer0Distance.y); // 小积云再混合。
    if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance; // 闪电检测用的小积云距离。
    if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance; // 大积云覆盖。
    if (cameraPos.y < s.layers[1].height) // 相机在下层时的顺序。
    {
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
    }
    else
    {
        if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
        if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
    }
    if (cumulonimbusClouds.a < 1.0) cloudDistance.g = cumulonimbusDistance; // 积雨云距离。
    if (cloudDistance.r > 15000.0) cloudDistance.r = 0.0; // 太远就不算闪电高度。
    if (cloudDistance.g > 15000.0) cloudDistance.g = 0.0;
    cloudColor.rgb = cirrusClouds.rgb; // 先放卷云。
    cloudColor.rgb *= altoStratusClouds.a; // 再乘高层云透过率。
    cloudColor.rgb += altoStratusClouds.rgb; // 加高层云。
    if (mixBelowLayer0) // 相机在小积云下方：从下往上合成。
    {
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
    }
    else if (mixBelowLayer1) // 相机在大积云下方。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
    }
    else // 相机在更高处。
    {
        cloudColor.rgb *= smallCumulusClouds.a;
        cloudColor.rgb += smallCumulusClouds.rgb;
        cloudColor.rgb *= largeCumulusClouds.a;
        cloudColor.rgb += largeCumulusClouds.rgb;
        cloudColor.rgb *= cumulonimbusClouds.a;
        cloudColor.rgb += cumulonimbusClouds.rgb;
    }
    color = cloudColor.rgb; // 最终颜色。
    totalAbsorbance = cloudColor.a; // 最终透过率。
    return vec4(color, totalAbsorbance); // 交回云颜色与透过率。
}

#endif
