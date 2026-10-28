// 三维噪声采样：把云坐标折到 512 见方噪声图的一列，再按纵向小数插值两行。
// 参考把这一步写成独立函数；库版本把噪声图显式传入，算式与常数逐项保留。
float ogxEclipseDensityAtPos(float3 pos, Sampler2D noiseTexture)
{
    pos /= 18.0; // 换成噪声格坐标。
    pos.xz *= 0.5; // 横向压缩，让云细节更宽。
    float3 p = floor(pos); // 所在格子的整数坐标。
    float3 f = fract(pos); // 格内小数位置。
    float2 uv = p.xz + f.xz + p.y * float2(0.0, 193.0); // 纵向每层错开一行，避免层间条纹。
    float2 coord = uv / 512.0; // 换成零到一纹理坐标。
    float2 xy = noiseTexture.SampleLevel(coord, 0.0).yx; // 图里存的是两层密度。
    return lerp(xy.r, xy.g, f.y); // 按纵向小数在两层之间插值。
}

// Eclipse 云形状：按云层选择覆盖率与噪声尺度，先算平面形状，再按高度裁剪与侵蚀。
// 参考签名是层号、细节层级、位置与上下界；噪声图、覆盖率与天气参数显式追加在末尾。
// 为什么用 switch：参考按层号分支，每层采样次数与顺序不同，合并会改变采样序列。
float ogxEclipseCloudShapeLayer(int layerIndex, int lod, float3 position, float minHeight, float maxHeight,
    Sampler2D noiseTexture, float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage,
    float rainAmount, float thunderStrength, float cloudMovement)
{
    float coverage = 0.0; // 本层覆盖率。
    float shape = 0.0; // 平面形状。
    float largeCloud = 0.0; // 大尺度噪声。
    float smallCloud = 0.0; // 小尺度噪声。
    float3 samplePos = position * float3(0.25, 0.005, 0.25); // 细节采样用的压缩坐标。
    float tallness = maxHeight - minHeight; // 云层厚度。
    float posToMax = maxHeight - position.y; // 到云顶的距离。
    switch (layerIndex)
    {
        default: { break; } // 未知层不产生云。
        case 3: { // 高层云：大尺度覆盖加一层细节。
            coverage = altostratusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = noiseTexture.SampleLevel((position.xz + cloudMovement * 20.0) / 100000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - noiseTexture.SampleLevel(((position.xz + float2(-cloudMovement, cloudMovement) * 20.0) / 7500.0 - float2(1.0 - largeCloud, -largeCloud) / 5.0) * 1.0, 0.0).b;
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
            largeCloud = noiseTexture.SampleLevel((samplePos.zx + cloudMovement * 3.0) / 10000.0 * 1.0, 0.0).b;
            smallCloud = noiseTexture.SampleLevel((samplePos.zx - cloudMovement * 3.0) / 2500.0 * 1.0, 0.0).b;
            smallCloud = abs(largeCloud * -0.7) + smallCloud;
            float val = coverage;
            shape = min(max(val - smallCloud, 0.0) / sqrt(val), 1.0);
            break;
        }
        case 0: { // 小积云：大尺度边缘直接参与形状。
            coverage = smallCumulusCoverage;
            coverage += 0.4 * rainAmount;
            coverage += 0.4 * thunderStrength;
            largeCloud = noiseTexture.SampleLevel((samplePos.xz + cloudMovement) / 5000.0 * 1.0, 0.0).b;
            smallCloud = 1.0 - noiseTexture.SampleLevel((samplePos.xz - cloudMovement) / 500.0 * 1.0, 0.0).r;
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
                erosion += (1.0 - ogxEclipseDensityAtPos(samplePos * 600.0 * 1.0 / 3.0, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (130.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxEclipseDensityAtPos(samplePos * 600.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.25);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
            case 1: { // 大积云细节。
                erosion += (1.0 - ogxEclipseDensityAtPos(samplePos * 250.0 * 1.0 / 3.571428, noiseTexture)) * sqrt(omShape);
                float falloff = 1.0 - clamp(posToMax / (280.0 / 1.0), 0.0, 1.0);
                erosion += abs(ogxEclipseDensityAtPos(samplePos * 250.0 * 1.0, noiseTexture) - falloff) * 0.75 * (omShape * omShape) * (1.0 - falloff * 0.5);
                erosion = erosion * erosion * erosion * erosion;
                break;
            }
        }
        return max(shape - erosion * erodeAmount, 0.0);
    }
    else return 0.0;
}

// Eclipse 积雨云形状：大尺度正弦云团叠加很小的塔状云，输出形状与大云标记。
// 参考签名是细节层级、位置与上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加。
float2 ogxEclipseCumulonimbusShapeLayer(int lod, float3 position, float minHeight, float maxHeight,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength)
{
	float largeCloud = 0.0;
	float smallCloud = 0.0;

	float3 samplePos = position*float3(1.0, 1.0/48.0, 1.0)/4.0;
	float tallness = maxHeight - minHeight;
	float posToMax = maxHeight - position.y;

	float cumulonimbusScale = 1.0;
	                                                                                                            
	
	                                     

	                                                 
	                                                                                                                              

	largeCloud = (max(sin((samplePos.x - cloudMovement*10.0)/2700) * cos((samplePos.z - cloudMovement*10.0)/2700), 0.0));
	largeCloud = lerp(max(min(largeCloud - 0.25, 0.5)*2.0, 0.0), max(min(largeCloud, 0.25)*4.0, 0.0), thunderStrength);
	float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraWorldPos));
	                           
	
	float isLarge = smoothstep(0.0, 1.0, shape);
	                 

	float bottomShape = 1.0-pow(1.0-min(max(position.y-minHeight,0.0) / 5.0, 1.0), 5.0);


	float smallMaxHeight = (tallness*0.45 + minHeight);

	float shape2 = 0.0;
	if (position.y < smallMaxHeight) {
	float smallTallness = smallMaxHeight - minHeight;
	float posToMaxSmall = smallMaxHeight - position.y;

	smallCloud = 1.0-noiseTexture.SampleLevel((samplePos.xz - cloudMovement*4.0) / 1800.0 * cumulonimbusScale * 0.2, 0.0).r * smoothstep(smallMaxHeight, tallness*0.2+minHeight, position.y);
	
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


		shape *= pow(cumulonimbusStrength, lerp(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y)));


	if(shape > 0.001){
		if (lod < 1) return float2(max(shape - 0.27*0.5,0.0), isLarge);

		samplePos.xz -= cloudMovement/4.0;
		samplePos.xz += pow( max(position.y - (minHeight+20.0), 0.0) / (max(tallness,1.0)*0.20), 1.5);

		float omShape = 1.0 - shape;

		float erosion = (1.0 - ogxEclipseDensityAtPos(samplePos * 190 * cumulonimbusScale*0.05, noiseTexture)) * sqrt(omShape);

		float falloff = 1.0 - clamp((posToMax)/4600.0,0.0,1.0);

		erosion += abs(ogxEclipseDensityAtPos(samplePos * 580 * cumulonimbusScale*0.05, noiseTexture) - falloff) * 0.65 * (omShape) * (1.0-falloff*0.5);

		erosion = erosion*erosion*erosion*erosion*smoothstep(maxHeight+40.0, tallness*0.5+minHeight, position.y);
		

		return float2(max(shape - erosion*0.5,0.0), isLarge);
	} else return float2(0.0, isLarge);
}

// Eclipse 闪电落点：用时间哈希选极坐标角度与半径，再把位置贴到积雨云层里。
// 参考签名只有云层上下界；噪声图、相机位置、风、雷雨与积雨云强度显式追加，
// 时间哈希与自定义落点常数直接写成参考数值，保持同一组常数。
float3 ogxEclipseLightningPositionBolt(float minHeight, float maxHeight,
    Sampler2D noiseTexture, float3 cameraWorldPos, float cloudMovement, float thunderStrength,
    float cumulonimbusStrength, float lightningTimer)
{
    float angle = fract(sin(dot(float2(lightningTimer, lightningTimer * 2.0), float2(12.9898, 78.233))) * 43758.5453) * 6.28318530718; // 时间哈希转角度。
    float rMin = 7000.0; // 最近落点半径。
    float rMax = 13000.0; // 最远落点半径。
    float radius = sqrt(lerp(rMin * rMin, rMax * rMax, fract(sin(dot(float2(lightningTimer + 1, (lightningTimer + 1) * 2.0), float2(12.9898, 78.233))) * 43758.5453))); // 在环形区域里取半径。
    float3 lightningPos = float3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle)); // 极坐标转云层坐标。
    float shapeAtLightningPos = ogxEclipseCumulonimbusShapeLayer(0, lightningPos, minHeight, maxHeight,
        noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x; // 落点处的积雨云形状。
    float moveUp = 0.48; // 闪电起点抬到云层中上部。
    lightningPos.y = minHeight + (maxHeight - minHeight) * moveUp; // 重算高度。
    lightningPos.y -= cameraWorldPos.y; // 换成相机相对高度。
    if (shapeAtLightningPos < 0.1) lightningPos = float3(0.0); // 落点没有云就不闪。
    lightningPos = float3(100.0, 0.0, 0.0) - cameraWorldPos; // 参考默认的自定义落点。
    return lightningPos; // 交回闪电位置。
}

// Eclipse 云相函数：Henyey-Greenstein 单峰前向散射，`g` 是各向异性，`x` 是夹角余弦。
// 为什么单列一条：参考默认只启用这一种相位，带类型开关的旧实现会多出其它模型的常数。
float ogxEclipsePhaseCloudHenyey(float g, float x)
{
    float gg = g * g; // 各向异性平方。
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14; // 参考原式。
}

// Eclipse 降雨加成：当前云量加上雨与雷带来的额外覆盖，限制在一以内。
// 参考把雨强与雷强当全局量；库版本显式接收，算式与常数不变。
float ogxEclipseGetRainDensity(float currentDensity, float rainAmount, float thunderStrength)
{
    float extraDensity = min(currentDensity + rainAmount * 0.1 + thunderStrength * 0.1, 1.0); // 雨天云量更满。
    return extraDensity; // 交回夹紧后的覆盖率。
}

// Eclipse 云影：从玩家位置沿太阳方向升到三层云底，各取一次云形状并按降雨加成叠加。
// 参考签名只有玩家位置与太阳方向；云噪声、风、雨雷、三层覆盖与闪电状态显式追加。
float ogxEclipseCloudShadowLayer(float3 playerPos, float3 sunVector,
    Sampler2D noiseTexture, float4 lightningBoltPosition, float sunElevation,
    float cloudMovement, float rainAmount, float thunderStrength,
    float smallCumulusCoverage, float largeCumulusCoverage, float altostratusCoverage,
    float smallCumulusRain, float largeCumulusRain, float altostratusRain)
{
    if (lightningBoltPosition.w > 0.0 && sunElevation < 0.0) // 夜里打闪电时不投云影，避免整片变黑。
    {
        return 1.0;
    }
    float totalShadow = ogxEclipseGetPlanetShadow(playerPos, sunVector); // 先算星球本身遮住多少阳光。
    float3 startPosition = playerPos; // 云影采样起点。
    float3 startOffset = sunVector / abs(sunVector.y); // 沿太阳方向升到云底所需的水平偏移。
    float cloudShadows = 0.0; // 三层云影累加。
    startPosition = playerPos + startOffset * max((250.0 + 20.0) - playerPos.y, 0.0); // 小积云底。
    cloudShadows = ogxEclipseCloudShapeLayer(0, 0, startPosition, 250.0, 250.0 + 130.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxEclipseGetRainDensity(smallCumulusRain, rainAmount, thunderStrength); // 小积云影。
    startPosition = playerPos + startOffset * max((400.0 + 30.0) - playerPos.y, 0.0); // 大积云底。
    cloudShadows += ogxEclipseCloudShapeLayer(1, 0, startPosition, 400.0, 400.0 + 280.0 / 1.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * ogxEclipseGetRainDensity(largeCumulusRain, rainAmount, thunderStrength); // 大积云影。
    startPosition = playerPos + startOffset * max(5000.0 - playerPos.y, 0.0); // 高层云底。
    cloudShadows += ogxEclipseCloudShapeLayer(3, 0, startPosition, 5000.0, 5000.0 + 5.0,
        noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
        rainAmount, thunderStrength, cloudMovement) * altostratusRain * (1.0 - abs(sunVector.y)); // 高层云影随太阳高度变淡。
    cloudShadows *= float(100.0) / 100.0; // 参考的云影总量比例。
    totalShadow *= exp((cloudShadows * cloudShadows) * -200.0); // 云影越厚，透过率下降越快。
    return totalShadow; // 交回阳光透过率。
}

// Eclipse 云内散射：沿太阳或月亮方向取几个云形状样本，累加成透过率。
// 参考签名是层号、位置、日月方向、日月高度、抖动与密度；云层上下界与噪声等显式追加。
// 为什么保留循环：采样次数由层号决定，参考也保留运行期循环，合并会改变采样顺序。
float ogxEclipseCloudScatteringSamples(int layerIndex, float3 rayPosition, float3 sunVector, float3 moonVector,
    float sunElevation, float moonElevation, float dither, float density,
    float minHeight, float maxHeight, Sampler2D noiseTexture, float3 cameraWorldPos,
    float cloudMovement, float rainAmount, float thunderStrength, float cumulonimbusStrength,
    float altostratusCoverage, float largeCumulusCoverage, float smallCumulusCoverage)
{
    int samples = 3; // 普通层三步。
    int lod = 0; // 阴影只取低细节。
    if (layerIndex == 2) samples = 7; // 积雨云更厚，多取几步。
    if ((layerIndex == 3) || (layerIndex == 4)) samples = 2; // 高层云很薄，两步够用。
    float shadow = 0.0; // 累积的云密度。
    float3 shadowRayPosition = float3(0.0); // 采样位置。
    float sunVis = smoothstep(-0.06, 0.01, sunElevation); // 太阳在地平线附近时逐渐变弱。
    sunVis = sunVis * sunVis;
    float moonVis = smoothstep(0.0, 0.075, -moonElevation); // 月亮同样处理。
    moonVis = moonVis * moonVis;
    moonVis *= smoothstep(0.06, -0.06, sunElevation); // 太阳升起后月亮光退场。
    float isLarge = 80; // 积雨云步长。
    float3 lightVec = normalize(lerp(moonVector, sunVector, smoothstep(-0.06, 0.06, sunElevation))); // 日月方向按太阳高度混合。
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
            shadow += ogxEclipseCloudShapeLayer(layerIndex, lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, altostratusCoverage, largeCumulusCoverage, smallCumulusCoverage,
                rainAmount, thunderStrength, cloudMovement) * density; // 普通云层取形状。
        }
        else
        {
            shadow += ogxEclipseCumulonimbusShapeLayer(lod, shadowRayPosition, minHeight, maxHeight,
                noiseTexture, cameraWorldPos, cloudMovement, thunderStrength, cumulonimbusStrength).x * density; // 积雨云取形状。
            isLarge *= 1.374; // 每步再拉远，减少远处重复采样。
        }
    }
    return shadow; // 交回云内遮挡量。
}
