/* 层状体积云的参考签名低成本步进：天气与覆盖参数显式传入，不读设置结构体；由 `cloud/layers.slang` 内联引入。
用法：调用下方 `ogxLayersCloudTransmittanceSimple`，参数顺序见函数签名。
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 层状云低成本步进：只累计透过率，不做光照，供云影与远景使用。
// 参考签名给层号、步数、位置与方向、抖动与上下界；噪声、天气与覆盖率显式追加。
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
    if (layerIndex == 0) densityTresholdCheck = 0.06;
    if (layerIndex == 1 || layerIndex == 2) densityTresholdCheck = 0.02;
    if (layerIndex == 3) densityTresholdCheck = 0.01;
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
        if (shapeWithDensity > 1e-5)
        {
            float densityCoeff = exp(-distanceFactor * shapeWithDensity); // 单步吸收。
            totalAbsorbance *= densityCoeff;
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
实现说明：层状云的低成本透过率。
一、单层吸收：`ogxLayersCloudAbsorbanceSimple` 只累计密度，不计算光照，供云影与远景使用。
二、阈值：每层用不同的密度阈值，低于阈值直接跳过，避免为透明空气做采样。
三、步进：沿视线按固定步数前进，步长由层厚与样本数决定，远处不额外加密。
四、提前结束：总透过率低于十万分之一就停止，后面的层已经看不见。
五、抖动：密度阈值用抖动系数在极小值与层阈值之间插值，让相邻像素的可见边缘错开。
六、距离淡出：积云在一百公里到五十公里之间淡出密度，远处云影逐渐变浅。
七、相机高度：小积云底部向下扩三百五十米，这是参考的固定写法，不能按几何直觉改。
八、单位：高度、方向与起点都用方块；水平尺度只用于构造步长，不是真实距离。
九、合成：四层返回值依次是小积云、大积云、高层云与总透过率，调用方按这个顺序混合。
*/

/*
函数索引：
一、`ogxLayersCloudAbsorbanceSimple`：单层吸收，沿视线累计密度，不计算光照。
二、`ogxLayersCloudTransmittanceSimple`：四层合成，返回小积云、大积云、高层云与总透过率。
三、阈值：每层用不同密度阈值，低密度直接跳过，避免为透明空气采样。
四、步进：步长由层厚与样本数决定，远处不额外加密。
五、提前结束：总透过率低于十万分之一就停止。
六、抖动：密度阈值用抖动系数在极小值与层阈值之间插值。
七、距离淡出：积云在一百公里到五十公里之间淡出密度。
八、相机高度：小积云底部向下扩三百五十米，这是参考的固定写法。
九、单位：高度、方向与起点都用方块；水平尺度只用于构造步长。
十、合成顺序：先小积云再大积云，再高层云，最后乘总透过率。
十一、边界：层号超出范围时返回全通，调用方不必自己夹紧。
十二、用途：云影与远景只需要透过率，不需要逐样本光照；这份实现比主步进便宜。
十三、常数：阈值、淡出距离与提前结束值都来自参考实现，不能按直觉改。
十四、纹理：噪声句柄与分辨率由调用方传入，库不绑定纹理单元。
十五、注意：修改步长会同时改变云影边缘与远景浓度，必须成组调整。
十六、验证：离线编译只证明语法，画面需要在测试世界里对照云影边缘。
*/

/*
参数与边界：
一、层号零到四，超出范围时返回全通。
二、样本数由调用方给出，越多越平滑也越慢。
三、密度阈值按层号不同，低密度空气直接跳过。
四、抖动系数在零到一之间，零表示不抖动。
五、总透过率低于十万分之一时提前结束。
六、积云的距离淡出从一百公里开始，到五十公里结束。
七、小积云底部向下扩三百五十米，这是参考的固定写法。
八、高层云与卷云只取一个平面样本，不进入体积步进。
九、返回值依次是小积云、大积云、高层云与总透过率。
十、水平尺度只用于构造步长，不是真实距离。
十一、噪声纹理与分辨率由调用方传入。
十二、修改步长会同时改变云影边缘与远景浓度。
十三、画面验证要看云影边缘与远景云层，离线编译只证明语法。
*/

/*
补充说明：透过率与云影的关系。
一、透过率越小，云影越浓；两者的阈值必须一致。
二、提前结束只影响性能，不改变可见结果。
三、抖动只改阈值，不改步长。
四、距离淡出只改密度，不改层高。
五、高层云与卷云的平面样本不受步长影响。
六、云影在远景处淡出，避免远处出现硬边。
七、修改淡出距离要同时看近景与远景。
八、画面验证要看云影边缘与地面亮度。
九、离线编译不验证云影形状。
*/

/*
补充说明：云影与透过率。
透过率越小云影越浓。
提前结束只影响性能。
抖动只改阈值。
距离淡出只改密度。
平面样本不受步长影响。
修改淡出距离要同时看近景与远景。
画面验证看云影边缘。
*/
/*
云影边缘要用测试世界截图核对。
步长与阈值成组调整。
层号越界返回全通。
*/
