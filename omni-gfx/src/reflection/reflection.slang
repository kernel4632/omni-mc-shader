/*
Omni 通用图形库反射模块：可见法线采样、屏幕空间追踪、反射方向、菲涅耳合并与小波滤波。
调用位置：任何需要屏幕空间反射的程序；Minecraft 光影由 `/omni-gfx/reflection/reflection.glsl` 引入。
可复制示例：
    `vec3 d = ogxSampleGgxVndf(viewVector, roughness, noise);` 生成一条模糊反射方向。
    `bool ok = ogxScreenSpaceTrace(origin, dir, ndotv, noise, minLength, false, screenPos, depthTex, handTex, dhTex, projection, projectionInverse, dhInverse, 0.05, true, false, false, 24, 4, 0.02);` 屏幕空间追踪。
    `ogxReflectionAtrousFilter(data, viewPos, viewDir, normal, roughness, 40.0, noise, uv, reflTex, depthTex, normalTex, pixelSize, projectionInverse);` 九点降噪。
设计原因与取舍：
    深度图、投影、光色与天空都由参数传入，库不读取引擎状态；主机特有的天空兜底、体素回退与
    反射雾仍留在 `shaders/gfx/reflection.glsl` 的合成流程里，那里只做开关组合，不再含采样循环。
    公式与旧实现逐项一致；矩阵乘法在 Slang 与 GLSL 的行列解释不同，统一走数学模块的显式展开。
*/
#ifndef OGX_REFLECTION_INCLUDED
#define OGX_REFLECTION_INCLUDED

// 饱和、曲线编码、菲涅耳与法线解码来自数学模块。
#include "../math.slang"

// 一个完整圆周，采样角度与旋转都用它。
static const float OGX_TAU = 6.28318530718;

// 可见法线分布采样：按粗糙度把反射方向散开，得到模糊反射。
float3 ogxSampleGgxVndf(float3 viewVector, float roughness, float2 noise)
{
    float3 orthoNormal = normalize(float3(roughness * viewVector.xy, viewVector.z)); // 把视线按粗糙度压成一个辅助轴。
    float length2 = dot(orthoNormal.xy, orthoNormal.xy); // 水平分量的长度平方。
    float3 orthoTangent = length2 > 0.0 ? float3(-orthoNormal.y, orthoNormal.x, 0.0) * rsqrt(length2) : float3(1.0, 0.0, 0.0); // 水平切线。
    float3 orthoBitangent = cross(orthoNormal, orthoTangent); // 副切线。
    float radius = sqrt(noise.y * 0.7); // 采样半径，取平方根让样本落在圆内。
    float angle = OGX_TAU * noise.x; // 采样角度。
    float2 samplePos = float2(cos(angle), sin(angle)) * radius; // 圆上的采样位置。
    float scaling = orthoNormal.z * 0.5 + 0.5; // 沿竖直方向把圆压成椭圆。
    samplePos.y = (1.0 - scaling) * sqrt(1.0 - samplePos.x * samplePos.x) + scaling * samplePos.y; // 投影到椭圆上。
    float3 sampleVector = samplePos.x * orthoTangent + samplePos.y * orthoBitangent + sqrt(max(0.0, 1.0 - dot(samplePos, samplePos))) * orthoNormal; // 合成三维方向。
    return normalize(float3(roughness * sampleVector.xy, max(sampleVector.z, 0.0))); // 按粗糙度压扁并归一化。
}

// 屏幕坐标与深度还原视空间位置；屏幕空间追踪算射线起点与命中点时用。
float3 ogxReflectionViewPos(float2 coord, float depth, float4x4 projectionInverse)
{
    float3 ndc = float3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    float3 pos = float3(float2(projectionInverse[0][0], projectionInverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projectionInverse); // 只用逆投影的非零项与平移列。
    return pos / (projectionInverse[2][3] * ndc.z + projectionInverse[3][3]); // 透视除法。
}

// 视空间位置投到屏幕，不补抖动；追踪射线用原始投影。
float3 ogxReflectionScreenPos(float3 viewPos, float4x4 projection)
{
    float3 pos = float3(projection[0][0], projection[1][1], projection[2][2]) * viewPos + ogxMatrixTranslation(projection); // 投影矩阵的非零项与平移列。
    return pos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
}

// 屏幕深度换米制距离。
float ogxReflectionLinearDepth(float depth, float4x4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 零到一转负一到一。
    return 1.0 / (depth * projectionInverse[2][3] + projectionInverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度。
float ogxReflectionScreenDepth(float depth, float4x4 projectionInverse)
{
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 解出负一到一深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景深度换成同一距离在近景投影下的深度。
float ogxReflectionDhToScreenDepth(float depth, float4x4 dhProjectionInverse, float4x4 projectionInverse)
{
    depth = depth * 2.0 - 1.0; // 远景深度转到负一到一。
    depth = 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 先换成米。
    depth = (1.0 / depth - projectionInverse[3][3]) / projectionInverse[2][3]; // 再用近景投影换回深度。
    return depth * 0.5 + 0.5; // 转回零到一。
}

// 读追踪采样点的深度：手部优先手部图，近景是天空时按开关改读远景。
float ogxReflectionSampleDepth(float2 coord, bool isHand, bool handSupported, Sampler2D depthTexture, Sampler2D handDepthTexture,
    Sampler2D dhDepthTexture, bool hasDh, bool dhSsr, float4x4 dhProjectionInverse, float4x4 projectionInverse)
{
    if (handSupported && isHand) // 手部读不含玩家的深度。
    {
        return handDepthTexture.SampleLevel(coord, 0.0).x;
    }
    float depth = depthTexture.SampleLevel(coord, 0.0).x; // 其他像素读普通不透明深度。
    if (hasDh && dhSsr && depth == 1.0) // 天空像素按开关改读远景。
    {
        depth = ogxReflectionDhToScreenDepth(dhDepthTexture.SampleLevel(coord, 0.0).x, dhProjectionInverse, projectionInverse); // 远景深度换到近景尺度。
    }
    return depth; // 返回该坐标的深度。
}

// 屏幕空间追踪：从起点沿反射方向在屏幕里步进，撞到比射线更近的几何就命中。
// 命中后二分细化，避免粗步长跨过薄几何；屏幕外的方向没有可靠深度，直接停止。
bool ogxScreenSpaceTrace(float3 viewRayOri, float3 viewRayDir, float ndotv, float noise, float minLength, bool isHand, inout float3 screenPos,
    Sampler2D depthTexture, Sampler2D handDepthTexture, Sampler2D dhDepthTexture, float4x4 projection, float4x4 projectionInverse,
    float4x4 dhProjectionInverse, float nearPlane, bool handSupported, bool hasDh, bool dhSsr, int quality, int refinementSteps, float zDiffThreshold)
{
    float rSteps = 1.0 / float(quality); // 步数的倒数，用作归一化步长。
    float viewRayLength = (-nearPlane - viewRayOri.z) / viewRayDir.z + step(viewRayDir.z, 0.0) * 1e20; // 射线到近裁剪面的长度，背向时给极远值。
    float3 rayDir = normalize(ogxReflectionScreenPos(viewRayOri + viewRayDir * viewRayLength, projection) - screenPos); // 屏幕坐标下的射线方向。
    float minStepLength = minLength * rSteps; // 最小步长按质量缩放。
    float stepLength = lerp(minStepLength, rSteps, ndotv); // 正对视线时步长更大，掠射时更小。
    float zScaling = abs(1.0 / rayDir.z); // 深度方向的缩放。
    bool hit = false; // 命中标记。
    float maxDepth = hasDh ? ogxReflectionScreenDepth(ogxReflectionLinearDepth(1.0, dhProjectionInverse), projectionInverse) : 1.0; // 有远景时步进上限是远景最远距离。
    screenPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少规则条纹。
    float depth = ogxReflectionSampleDepth(screenPos.xy, false, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
        hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 读起始点深度。
    for (int i = 0; i < quality + 3; i++) // 最多走质量加三次，多出的几次用于边界收尾。
    {
        if (!ogxEqual(ogxSaturate(screenPos.xy), screenPos.xy)) // 出了屏幕就停止。
        {
            break;
        }
        if (screenPos.z >= maxDepth) // 射线到达最远处。
        {
            hit = depth >= maxDepth; // 该处也是尽头才算命中。
            break;
        }
        else if (screenPos.z < 0.7 && !isHand) // 射线跑到相机很近的地方，后面没有可靠深度。
        {
            break;
        }
        if (depth < screenPos.z) // 几何深度比射线更近，说明可能撞上几何。
        {
            float3 refineDir = rayDir * stepLength * 0.5; // 细化步长，从半步开始逐次减半。
            for (int j = 0; j < refinementSteps; j++, refineDir *= 0.5) // 二分细化交点。
            {
                screenPos += refineDir * (step(screenPos.z, depth) * 2.0 - 1.0); // 越过就回退半步，没越过就前进半步。
                depth = ogxReflectionSampleDepth(screenPos.xy, isHand, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
                    hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 重读该点深度。
            }
            if (depth > screenPos.z) // 细化后几何又跑到后面，这一步不算命中。
            {
                continue;
            }
            float stepDist = ogxReflectionLinearDepth(screenPos.z, projectionInverse); // 射线点的米制距离。
            float sampleDist = ogxReflectionLinearDepth(depth, projectionInverse); // 几何点的米制距离。
            float distDiff = abs(sampleDist - stepDist) / stepDist; // 两点的相对深度差。
            if (distDiff < zDiffThreshold && screenPos.z > 0.0 && screenPos.z < maxDepth) // 差足够小且深度有效才算命中。
            {
                hit = true;
                break;
            }
        }
        stepLength = clamp(abs(depth - screenPos.z) * zScaling, minStepLength, rSteps); // 按深度差自适应下一步长度。
        screenPos += rayDir * stepLength; // 前进一步。
        depth = ogxReflectionSampleDepth(screenPos.xy, false, handSupported, depthTexture, handDepthTexture, dhDepthTexture,
            hasDh, dhSsr, dhProjectionInverse, projectionInverse); // 读新位置的深度。
    }
    return hit; // 返回是否命中。
}

// 生成反射方向：光滑面直接反射，粗糙面先按可见法线抽样再反射。
float3 ogxReflectionDir(float3 viewDir, float3 normal, float roughness, float2 noise, bool isSmooth)
{
    if (isSmooth) // 镜面方向。
    {
        return reflect(viewDir, normal);
    }
    float3 normalUp = normalize(float3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
    float3 tangentAxis = cross(normalUp, normal); // 切线基第一列。
    float3 bitangentAxis = normalUp; // 切线基第二列。
    float3 viewTangent = float3(dot(viewDir, tangentAxis), dot(viewDir, bitangentAxis), dot(viewDir, normal)); // 视线转到切线空间。
    float3 visibleNormal = ogxSampleGgxVndf(-viewTangent, roughness, noise); // 抽样一个可见法线。
    float3 worldNormal = tangentAxis * visibleNormal.x + bitangentAxis * visibleNormal.y + normal * visibleNormal.z; // 换回世界空间。
    return reflect(viewDir, worldNormal); // 沿可见法线反射。
}

// 读场景颜色并换回线性；反射颜色统一用这个入口，编码格式只有一处。
float3 ogxReflectionSceneColor(Sampler2D sceneTexture, float2 coord)
{
    return ogxCurveToLinear3(sceneTexture.SampleLevel(coord, 0.0).rgb); // 曲线编码转线性。
}

// 天空回退的朝向权重：面越朝上，接收的天空越多；朝下时保留四分之一，避免全黑。
float ogxReflectionSkyFacing(float normalUp)
{
    return ogxSaturate((normalUp + 0.7) * 2.0) * 0.75 + 0.25; // 与天空光在地面的分布一致。
}

// 命中点到表面的距离：命中点深度从深度图或射线深度取，单位是米。
float ogxReflectionHitLength(float3 viewPos, float3 hitViewPos)
{
    return distance(hitViewPos, viewPos); // 命中点与表面之间隔着多少空气。
}

// 把反射颜色按菲涅耳、金属度与水吸收混进场景色；`notTotal` 为假时是全反射像素，直接取反射色。
void ogxSpecularReflectionMix(inout float3 color, float3 viewDir, float3 normal, float3 albedo, float waterAbsorption, float3 reflection,
    bool notTotal, float metalness, float roughness, float f0, float reflectionStrength, bool overworld)
{
    if (!notTotal) // 全反射像素直接取反射色。
    {
        color = reflection; // 表面看不到外面的东西。
        return;
    }
    reflection *= lerp(float3(1.0), albedo, float3(metalness)); // 金属面用底色给反射染色。
    float3 l = normalize(reflect(viewDir, normal) + normal * roughness); // 反射方向按粗糙度偏一点。
    float3 h = normalize(l - viewDir); // 反射方向与视线的半程。
    float lDotH = ogxSaturate(dot(l, h)); // 反射与半程夹角。
    float nDotL = ogxSaturate(dot(normal, l)); // 反射方向的入射余弦。
    float nDotV = ogxSaturate(dot(normal, -viewDir)); // 视线方向的入射余弦。
    float specular = ogxFresnelSchlick(lDotH, f0, 1.0); // 菲涅耳。
    specular *= ogxVisibilitySchlick(nDotL, nDotV + 0.8, roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
    specular *= reflectionStrength; // 乘材质允许的反射强度。
    specular = lerp(specular, 1.0, metalness); // 金属面反射权重拉满。
    float3 temp = color; // 记下原底色，金属面要再加一份。
    float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
    diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
    specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。
    if (overworld) // 主世界按水吸收缩反射权重。
    {
        color = lerp(color, reflection, ogxSaturate(specular * waterAbsorption)); // 混合反射。
        color += temp * (metalness * waterAbsorption); // 金属面再加一份底色。
    }
    else // 下界末地按反射权重混合。
    {
        color = lerp(color, reflection, ogxSaturate(specular)); // 混合反射。
        color += temp * metalness; // 金属面再加一份底色。
    }
}

// 反射小波滤波：九点邻域按反射方向与深度相似度加权，抹掉追踪噪点同时保住反射边界。
// 为什么按法线与深度加权：命中点落在不同法线或不同深度的邻居属于别的物体，混进来会把反射糊成一片。
// 为什么先按亮度幂次重整再还原：高动态范围的反射点会盖住整片邻域，先压一下亮度再合并，边界更干净。
void ogxReflectionAtrousFilter(inout float4 reflectionData, float3 viewPos, float3 viewDir, float3 normal,
    float roughness, float radius, float2 noise, float2 texCoord, Sampler2D reflectionTexture,
    Sampler2D depthTexture, Sampler2D normalTexture, float2 pixelSize, float4x4 projectionInverse)
{
    float linearDepth = -viewPos.z; // 表面的米制深度。
    float ndotv = ogxSaturate(dot(-viewDir, normal)); // 视线与法线夹角余弦。
    roughness = max(roughness, 1e-4); // 粗糙度给一个下限，避免除以零。
    radius *= min(roughness * 20.0, 1.0); // 越粗糙反射越糊，滤波半径越大。
    radius *= reflectionData.a * 0.9 + 0.1; // 命中距离越远半径越大。
    float2 tangent = normalize(cross(normal, viewDir).xy) * radius; // 沿表面切向的采样步长。
    // 参考用固定九十度旋转矩阵；直接写矩阵元素，保留 1.5708 与 -1 这两个参考常数。
    const float2x2 rot90 = float2x2(cos(1.5708), -1.0, 1.0, cos(1.5708));
    float2 bitangent = rot90 * tangent; // 副切向：旋转九十度。
    tangent *= lerp(0.1075, 0.5, ndotv) * pixelSize; // 切向按视角缩放并换成屏幕坐标。
    bitangent *= lerp(0.7, 0.5, ndotv) * pixelSize; // 副切向同理。
    float3 reflectedDir = reflect(-viewDir, normal); // 当前像素的反射方向。
    float normalThreshold = 75.0 / roughness; // 法线相似度的幂次，越粗糙越严。
    float luminanceThreshold = reflectionData.a * 0.95 + 0.05; // 亮度重整的幂次，按命中距离变化。
    float4 accum = float4(0.0); // 加权累加的反射数据。
    float weights = 0.0; // 累加权重。
    for (int i = 0; i < 9; i++) // 遍历九个邻点。
    {
        float2 offset = float2(float((i % 3) - 1), float((i / 3) - 1)); // 三乘三邻域偏移，按行优先排列。
        float2 sampleCoord = texCoord + tangent * (offset + noise.x) + bitangent * (offset + noise.y); // 邻点坐标，按抖动微调。
        float4 sampleData = reflectionTexture.SampleLevel(sampleCoord, 0.0); // 读邻点反射数据。
        if (sampleData.a < 0.0001) // 邻点没有反射，跳过。
        {
            continue;
        }
        float sampleDepth = ogxReflectionLinearDepth(depthTexture.SampleLevel(sampleCoord, 0.0).x, projectionInverse); // 邻点米制深度。
        float3 sampleReflected = reflect(-viewDir, ogxDecodeNormal(normalTexture.SampleLevel(sampleCoord, 0.0).xy)); // 邻点反射方向。
        float normalWeight = pow(ogxSaturate(dot(sampleReflected, reflectedDir)), normalThreshold); // 反射方向越接近权重越大。
        float depthWeight = exp2(-(abs(sampleDepth - linearDepth) * 1.58)); // 深度越接近权重越大。
        float sampleWeight = normalWeight * depthWeight; // 两个权重相乘。
        sampleData.rgb += 1e-13; // 避免零亮度在下面除法里出问题。
        float luminance = length(sampleData.rgb); // 邻点亮度。
        sampleData.rgb *= pow(luminance, luminanceThreshold) / luminance; // 按幂次重整亮度。
        accum += sampleData * sampleWeight; // 按权重累加。
        weights += sampleWeight; // 累加权重。
    }
    if (weights > 1e-13) // 有有效邻点才写回。
    {
        accum /= weights; // 取加权平均。
        accum.rgb += 1e-13; // 同样避免零亮度。
        float luminance = length(accum.rgb); // 平均后的亮度。
        accum.rgb *= pow(luminance, 1.0 / luminanceThreshold) / luminance; // 还原亮度重整。
        reflectionData = accum; // 写回滤波结果。
    }
}

#endif
