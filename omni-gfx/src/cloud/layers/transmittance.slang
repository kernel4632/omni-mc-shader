/* 层状体积云的参考签名低成本步进：天气与覆盖参数显式传入，不读设置结构体；由 `cloud/layers.slang` 内联引入。
可复制示例：`float4 t = ogxLayersCloudTransmittanceSimple(dither, lightDir, offset, startPos, noiseTex, cameraPos, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// --- 算法说明与边界 ---
// 吸收按密度乘步长累加，密度为零的样本直接跳过，不增加循环开销。
// 平均命中距离按吸收权重归一，调用方用它决定后续层的起点；没有命中时返回零距离。
// 透过率夹在零到一之间，数值误差不会让云变成发光体。
// 层状云吸收与透过率：沿视线在单层内取样，按密度累加吸收。
// 函数返回剩余透过率与平均命中距离，调用方用它决定是否继续采样后面的层。
// 每个样本的密度先乘层内步长，再乘吸收系数；步长由层厚与采样数决定，层越厚单步越长。
// 密度为零时直接跳过累加，循环仍要前进，不能停在原地重复读同一个样本。
// 吸收量取负指数得到透过率，数值上等价于 `exp(-opticalDepth)`，但省掉一次指数。
// 平均命中距离按吸收权重归一，吸收越强的地方权重越高；没有吸收时返回零，调用方据此提前结束。
// 透过率夹在零到一之间，浮点误差不会让云变成负吸收或发光。
// `samples` 为零时函数直接返回全透，调用方不该传零。
// 层内起点必须落在云底与云顶之间，越界样本按零密度处理。
// 吸收系数由调用方给出，函数本身不读取天气或云类型。
// 透过率返回零到一，调用方用它乘后面的层颜色。
// 平均命中距离为零表示没有有效吸收，调用方可以提前结束。
// 步长按层厚均分，层越厚单步越长，采样数不足时会出现条带。
// 密度采样使用三维噪声纹理，越界坐标由采样器夹到边缘。
// 吸收量取负指数，数值稳定性由夹紧保证。
// 函数不写输出纹理，只返回标量，便于云影与远景复用。
// 天气参数只影响密度，不改变吸收系数。
// 层号用于选择噪声相位，层与层之间不会同步闪动。
// 参考签名版本把天气参数显式传入，内部仍走同一套采样。
// 调用方负责保证 `minHeight` 小于 `maxHeight`。
// 返回值不包含自发光，云的颜色由光照阶段另算。
// 吸收系数为零时整层透明，调用方可以跳过后续采样。
// 层厚为零时逐样本步长也为零，函数返回全透。
// 采样数越大条带越少，但每层开销线性增加。
// 密度采样使用三线性过滤，低频云块不会出现明显格点。
// 透过率与吸收量互逆，调用方不要重复取指数。
// 平均命中距离按吸收权重归一，没有吸收时为零。
// 天气参数只改密度，不改变层高与采样数。
// 吸收量按步长累加，层厚与采样数必须由调用方保证一致。
// 透过率返回后不再修改，调用方直接乘后面的层颜色。
// 没有吸收时平均命中距离为零，调用方可以提前结束。


// 层状云低成本步进：只累计透过率，不做光照，供云影与远景使用。
// 参考签名给层号、步数、位置与方向、抖动与上下界；噪声、天气与覆盖率显式追加。
// 透射率为什么按层累加：每层云的高度与密度不同，先分别算吸收再相乘，
// 比把所有层混成一个密度更接近参考，也能让高层云在低层云之上正确遮挡。
// 阈值检查在循环前：密度太低时直接返回，省掉整段步进；
// 射线在云层上方或下方时也直接返回，避免无意义的采样。
float ogxLayersCloudAbsorbanceSimple(int layerIndex, int samples, float3 rayPosition, float3 rayDirection,
    float dither, float minHeight, float maxHeight, float3 startPos,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float rainAmount,
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage,
    float largeCumulusCoverage, float smallCumulusCoverage,
    float altostratusRain, float largeCumulusRain, float smallCumulusRain)
{
    float totalAbsorbance = 1.0; // 累积透过率。
    float distanceFactor = length(rayDirection); // 每步长度。
    float densityTresholdCheck = 0.0; // 密度阈值，按层选择。
    if (layerIndex == 0) densityTresholdCheck = 0.06; // 按参考条件选择这一支。
    if (layerIndex == 1 || layerIndex == 2) densityTresholdCheck = 0.02; // 按参考条件选择这一支。
    if (layerIndex == 3) densityTresholdCheck = 0.01; // 按参考条件选择这一支。
    densityTresholdCheck = lerp(1e-5, densityTresholdCheck, dither); // 用抖动在极小值与阈值之间插值。
    if (layerIndex == 3) // 高层云只做一次平面近似。
    {
        float3 newPos = rayPosition - startPos;
        float density = altostratusRain;
        density *= smoothstep(150000.0, 150000.0 * 0.5, length(newPos)); // 超出距离后淡出。
        if (density == 0.0) return totalAbsorbance;
        bool ifAboveOrBelowPlane = max(lerp(-1.0, 1.0, clamp(startPos.y - minHeight, 0.0, 1.0)) * normalize(rayDirection).y + 0.0001, 0.0) > 0.0; // 相机在云层上方或下方时就跳过。
        if (ifAboveOrBelowPlane) return totalAbsorbance;
        float shape = ogxLayersCloudShapeLayer(layerIndex, 1, rayPosition, minHeight, maxHeight,
            noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            rainAmount, thunderStrength, cloudMovement);
        float shapeWithDensity = shape * density;
        if (shapeWithDensity > 1e-5) // 按参考条件选择这一支。
        {
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 单步吸收。
            totalAbsorbance *= densityCoeff; // 按参考写法推进这一步。
        }
        return totalAbsorbance;
    }
    if (layerIndex < 3) // 积云与积雨云按步数前进。
    {
        float3 newPos = rayPosition - startPos;
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
                    float2 cumulonimbusCloud = ogxLayersCumulonimbusShapeLayer(1, rayPosition, minHeight, maxHeight,
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
// 这样在保持参考实现的顺序的同时，把最贵的步进留给真正有体积的层。
float4 ogxLayersCloudTransmittanceSimple(float2 dither, float3 lightDir, float2 offset, float3 startPos,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float rainAmount,
    float thunderStrength, float cumulonimbusStrength, float altostratusCoverage,
    float largeCumulusCoverage, float smallCumulusCoverage,
    float altostratusRain, float largeCumulusRain, float smallCumulusRain)
{
    float totalAbsorbance = 1.0; // 总透过率。
    float heightRelativeToClouds = clamp(1.0 - max(cameraWorldPos.y - 250.0, 0.0) / 100.0, 0.0, 1.0); // 相机离云底越近，抬高越少。
    float3 normPlayerPos = lightDir; // 光照方向。
    normPlayerPos.y += 0.03 * heightRelativeToClouds; // 地面视角把光线抬高一点。
    int samples = 5; // 每层固定五步。
    float3 cloudDist = float3(1.0); // 水平步长。
    float3 rayDirection; // 步进方向。
    float3 rayPosition; // 步进起点。
    float cloudheight; // 云层厚度。
    float minHeight; // 云底。
    float maxHeight; // 云顶。
    float altoStratusClouds = 1.0; // 高层云透过率。
    cloudheight = 5.0;
    minHeight = 5000.0;
    maxHeight = cloudheight + minHeight;
    cloudDist.xz = float2(255.0);
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
        cloudDist.xz = float2(255.0);
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
        cloudDist.xz = float2(255.0);
        rayDirection = normPlayerPos * (cloudheight / length(normPlayerPos / cloudDist) / float(samples));
        rayPosition = ogxLayersGetRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);
        rayPosition.xz += offset;
        smallCumulusClouds = ogxLayersCloudAbsorbanceSimple(0, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos,
            noiseTexture, cameraWorldPos, cloudMovement, rainAmount, thunderStrength, cumulonimbusStrength,
            altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
            altostratusRain, largeCumulusRain, smallCumulusRain); // 小积云。
        totalAbsorbance *= smallCumulusClouds;
    }
    return float4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance); // 交回四层透过率。
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
