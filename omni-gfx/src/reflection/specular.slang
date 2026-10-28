/*
Omni 通用图形库高光模块：GGX、可见法线采样、粗糙菲涅耳、反射可见度与高光合成。
调用位置：Eclipse 风格高光与反射合成；由 `/omni-gfx/reflection/specular.glsl` 引入。
可复制示例：
    vec3 color = ogxSpecularReflections(viewPos, playerPos, nPos, lightVec, noise, flatN, n, 0.4, 0.02, albedo, diffuse, light, 1.0, false, false, background, sun, 1.0, 50.0, true, true, flash, 1.0, sceneTex, depthTex, proj, invProj, view, invView, prevProj, prevView, 0.05, 1000.0, delta, 1.0, texel); // 合成高光。
设计原因与取舍：
    金属、介电与水面共用同一套菲涅耳与 GGX；背景天空、环境反射和太阳高光按参考顺序合成。
当前状态：由 `shaders/effects/reflection/screenspace.glsl` 引入并编译；Eclipse 高光后端后续接到顶层入口。
*/
#ifndef OGX_REFLECTION_SPECULAR_INCLUDED
#define OGX_REFLECTION_SPECULAR_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../common/math.slang"
// 手持光提供光斑、手电与手光阴影。
#include "../heldlight.slang"
// 天空提供云环境色、星空与日月圆盘。
#include "../atmosphere/sky.slang"
// 反射提供体素与雾的合成入口。
#include "wsr.slang"

// 法线夹紧：把背向视线的法线朝视线方向拉回，避免掠射高光发黑。
float3 ogxClampReflectionNormal(float3 n, float3 v) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float nDotV = ogxSaturate(dot(n, -v)); // 法线与视线夹角余弦。
    return normalize(nDotV * v + n); // 参考实现的混合。
} // 按参考顺序推进。

// Frisvad 切线基：由法线直接构造两个正交切向，避免叉乘退化。
float3x3 ogxFrisvadBasis(float3 n) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float3 f; // 第一切向。
    float3 r; // 第二切向。
    if (n.z < -0.9) // 法线接近负 z 时用固定基，避免除以接近零的数。
    { // 按参考顺序推进。
        f = float3(0.0, -1.0, 0.0); // 当前步骤的中间量。
        r = float3(-1.0, 0.0, 0.0); // 当前步骤的中间量。
    } // 按参考顺序推进。
    else // 另一支保持参考行为。
    { // 按参考顺序推进。
        float a = 1.0 / (1.0 + n.z); // 参考实现的比例。
        float b = -n.x * n.y * a; // 交叉项。
        f = float3(1.0 - n.x * n.x * a, b, -n.x); // 当前步骤的中间量。
        r = float3(b, 1.0 - n.y * n.y * a, -n.y); // 当前步骤的中间量。
    } // 按参考顺序推进。
    return float3x3(f, r, n); // 三列依次是切向、副切向、法线。
} // 按参考顺序推进。

// 可见法线 GGX 采样：把视线压到半球椭球，再采一个半程方向。
float3 ogxGgxVndfDirection(float3 viewerDirection, float alpha, float2 xy) // 当前步骤的中间量。
{ // 按参考顺序推进。
    viewerDirection = normalize(float3(alpha * 0.5 * viewerDirection.xy, viewerDirection.z)); // 压到半球配置。
    const float tau = OGX_TAU; // 参考实现的两倍圆周。
    float phi = tau * xy.x; // 采样角。
    float cosTheta = (1.0 - xy.y) * (1.0 + viewerDirection.z) - viewerDirection.z; // 余弦。
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0)); // 正弦。
    sinTheta = clamp(sinTheta, 0.0, 1.0); // 参考实现的钳制。
    cosTheta = clamp(cosTheta, sinTheta * 0.5, 1.0); // 参考实现的钳制。
    float3 reflected = float3(float2(cos(phi), sin(phi)) * sinTheta, cosTheta); // 反射方向。
    float3 halfway = reflected + viewerDirection; // 半程方向。
    return normalize(float3(alpha * halfway.xy, halfway.z)); // 回到椭球配置。
} // 按参考顺序推进。

// Eclipse 的 GGX：粗糙度先取 2.5 次方，再算 D、F 与可见性。
// Eclipse 的 GGX 与通用 GGX 不同：粗糙度先取二点五次方，高光边缘更硬；
// 菲涅尔用指数近似而不是五次方，金属的高光颜色更饱和。
// 这些差异来自参考包，不能直接换成通用实现，否则金属球会变灰。
float3 ogxGgxBrdf(float3 n, float3 v, float3 l, float r, float3 f0, float3 metalAlbedoTint) // 当前步骤的中间量。
{ // 按参考顺序推进。
    r = max(pow(r, 2.5), 0.0001); // 粗糙度重整与下限。
    float3 h = normalize(l + v); // 半程方向。
    float hn = rsqrt(dot(h, h)); // 半程长度倒数。
    float dotLH = clamp(dot(h, l) * hn, 0.0, 1.0); // 半程与光。
    float dotNH = clamp(dot(h, n) * hn, 0.0, 1.0); // 半程与法线。
    float dotNL = clamp(dot(n, l), 0.0, 1.0); // 法线与光。
    float dotNHsq = dotNH * dotNH; // 平方。
    float denom = dotNHsq * r - dotNHsq + 1.0; // 分母。
    // 参考实现使用十七位圆周率；这里保留长常数，避免换成十一位的 OGX_PI 后高光末位漂移。
    float d = r / (3.141592653589793 * denom * denom); // 法线分布。
    float3 f = (f0 + (1.0 - f0) * exp2((-5.55473 * dotLH - 6.98316) * dotLH)) * metalAlbedoTint; // 菲涅耳。
    float k2 = 0.25 * r; // 可见性系数。
    return dotNL * d * f / (dotLH * dotLH * (1.0 - k2) + k2); // 合成高光。
} // 按参考顺序推进。

// Eclipse 的粗糙度菲涅耳：按粗糙度调整曲线与亮度。
float ogxFresnelSchlickRoughness(float xDotN, float roughness) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float shlickFresnel = clamp(1.0 + xDotN, 0.0, 1.0); // 基础菲涅耳。
    float curves = exp(-4.0 * pow(1.0 - roughness, 2.5)); // 曲线权重。
    float brightness = exp(-3.0 * pow(1.0 - sqrt(roughness), 3.50)); // 亮度权重。
    shlickFresnel = pow(1.0 - pow(1.0 - shlickFresnel, lerp(1.0, 1.9, curves)), lerp(5.0, 2.6, curves)); // 曲线重整。
    shlickFresnel = lerp(0.0, lerp(1.0, 0.065, brightness), clamp(shlickFresnel, 0.0, 1.0)); // 亮度重整。
    return shlickFresnel; // 交回菲涅耳。
} // 按参考顺序推进。

// 反射可见度：按 f0 与粗糙度判断高光是否值得显示，避免粗糙金属被反射糊满。
// 反射可见度决定这块表面值不值得做屏幕追踪：粗糙金属与湿面才显示反射。
// 三段阈值分别处理非金属、粗糙度与超光滑材料，最后平方两次让过渡更陡。
// 提前返回可以把最贵的追踪省掉，画面差异只在很弱的反射上。
float ogxReflectionVisibility(float f0, float roughness, float roughnessThreshold) // 当前步骤的中间量。
{ // 按参考顺序推进。
    float thresholdValue = roughnessThreshold / 100.0; // 参考实现的百分比。
    float dialectrics = max(f0 * 255.0 - 26.0, 0.0) / 229.0; // 非金属比例。
    float value = 0.35; // 第一段阈值。
    float thresholdA = min(max((1.0 - dialectrics) - value, 0.0) / value, 1.0); // 第一段。
    float smoothness = 1.0 - sqrt(roughness); // 感知光滑度。
    value = thresholdValue; // 第二段阈值。
    float thresholdB = min(max(smoothness - value, 0.0) / value, 1.0); // 第二段。
    value = 0.1; // 超光滑材料保护。
    float thresholdC = 1.0 - min(max(value - (1.0 - smoothness), 0.0) / value, 1.0); // 第三段。
    float visibilityGradient = max(thresholdA * thresholdC - thresholdB, 0.0); // 合成梯度。
    visibilityGradient = 1.0 - visibilityGradient; // 按参考写法推进这一步。
    visibilityGradient *= visibilityGradient; // 按参考写法推进这一步。
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    return visibilityGradient; // 交回可见度。
}

// 高光反射主函数：背景反射、环境反射、太阳 GGX 与手持光 GGX 的合成。
// 高光合成顺序：背景天空、环境反射、太阳高光、手电高光。
// 环境反射占用过的部分要从太阳高光里扣掉，否则金属表面会亮两次。
// 金属用硬编码反射率表，电介质用 f0；这是参考实现的材质约定。
float3 ogxSpecularReflections(float3 viewPos, float3 playerPos, float3 NplayerPos, float3 lightVec,
    float2 noise, float3 flatNormal, float3 normal, float roughness, float f0, float3 albedo,
    float3 diffuseLighting, float3 lightColor, float lightmap, bool isHand, bool isMetalPass,
    float3 backgroundReflection, float3 sunlightColor, float sunSpecularMultiplier,
    float roughnessThreshold, bool ssrEnabled, bool backgroundEnabled, float3 flashlightColor,
    float flashlightIntensity, Sampler2D sceneTexture, Sampler2D depthTexture,
    float4x4 projection, float4x4 projectionInverse, float4x4 modelView, float4x4 modelViewInverse,
    float4x4 previousProjection, float4x4 previousModelView, float nearPlane, float farPlane,
    float3 cameraDelta, float renderScale, float2 texelSize)
{
    lightmap = min(max(lightmap - 0.9, 0.0) / 0.1, 1.0); // 光照图重整。
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    roughness = 1.0 - roughness; // 粗糙度反转。
    roughness *= roughness;
    f0 = f0 == 0.0 ? 0.02 : f0; // 默认介电常数。
    bool isMetal = f0 > 229.5 / 255.0; // 金属判定。
    float3x3 basis = ogxFrisvadBasis(normal); // 切线基。
    float3 viewDir = ogxMatrix3MulPoint(basis, -NplayerPos); // 转到切线空间。
    float3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), float3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxFresnelSchlickRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    float3 metalAlbedoTint = isMetal ? albedo : float3(1.0); // 金属染色。
    float3 hardCodedMetalsF0[8]; // 参考的八种金属反射率，逐项赋值避免 GLSL 330 的数组构造限制。
    hardCodedMetalsF0[0] = float3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = float3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = float3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = float3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = float3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = float3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = float3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = float3(0.961999998804, 0.94946811207, 0.922115710997); // 参考实现的八种金属。
    float3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    float3 reflectance = isMetal ? hardCodedMetals : float3(f0); // 反射率。
    float3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    float3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    float backgroundReflectMask = lightmap; // 背景遮罩。
    float4 environmentReflection = float4(0.0); // 环境反射。
    float3 backgroundTint = float3(1.0); // 背景染色。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        float3 darkened = isMetal ? diffuseLighting * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        if (backgroundEnabled) specular = lerp(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        if (ssrEnabled) // 屏幕空间反射。
        {
            environmentReflection = ogxEnvironmentReflections(reflectedVector, flatNormal, normal,
                playerPos, viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint,
                false, 1.0, sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
                previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale,
                texelSize, 0.0); // 不用 Photonics；主世界默认不在水里。
            specular = lerp(specular, environmentReflection.rgb, environmentReflection.a); // 合并环境反射。
        }
        specular = lerp(darkened, specular, F0); // 按菲涅耳混合。
        specular = lerp(specular, darkened, visibility); // 按可见度回到漫反射。
    }
    if (sunSpecularMultiplier > 0.0) // 太阳高光。
    {
        float3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * sunlightColor
            * ogxGgxBrdf(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // GGX。
        specular += lightSourceReflection * (1.0 - environmentReflection.a); // 环境反射占用后剩下的部分。
    }
    if (flashlightIntensity > 0.0) // 手电高光。
    {
        float3 flashLightReflection = flashlightColor * flashlightIntensity
            * ogxGgxBrdf(normal, -normal, -normal, roughness, reflectance, metalAlbedoTint); // 参考实现的手电方向近似。
        specular += flashLightReflection;
    }
    return specular; // 交回高光。
}

// 严格参考签名的高光反射入口：背景天空、环境反射、太阳 GGX 与手电 GGX 的顺序照原程序。
// 参考把天空图、屏幕图、深度图与相机矩阵当全局量；库把它们放在参数表尾部，算式不变。
float3 ogxSpecularReflectionsExact(float3 viewPos, float3 playerPos, float3 NplayerPos, float3 lightVec,
    float2 noise, float3 flatNormal, float3 normal, float roughness, float f0, float3 albedo,
    float3 diffuseLighting, float3 lightColor, float lightmap, bool isHand, bool isWater,
    inout float reflectanceForAlpha, float4 flashLightStuff, Sampler2D skyTexture, float2 pixelSize,
    float3 waterAbsorb, float eyeInWater, float sunSpecularMultiplier, float roughnessThreshold,
    Sampler2D sceneTexture, Sampler2D depthTexture, float4x4 projection, float4x4 projectionInverse,
    float4x4 modelView, float4x4 modelViewInverse, float4x4 previousProjection, float4x4 previousModelView,
    float nearPlane, float farPlane, float3 cameraDelta, float renderScale, float2 texelSize,
    float environmentQuality, float3 flashLightColor, bool handHeldLights, bool firstPersonCamera,
    Usampler1D blockDataTexture, int heldItemId, int heldItemId2)
{
    lightmap = min(max(lightmap - 0.9, 0.0) / 0.1, 1.0); // 光照图重整。
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    lightmap *= lightmap;
    lightmap = 1.0 - lightmap;
    roughness = 1.0 - roughness; // 粗糙度反转。
    roughness *= roughness;
    f0 = f0 == 0.0 ? 0.02 : f0; // 默认介电常数。
    bool isMetal = f0 > 229.5 / 255.0; // 金属判定。
    float3x3 basis = ogxFrisvadBasis(normal); // 切线基。
    float3 viewDir = float3(dot(basis[0], -NplayerPos), dot(basis[1], -NplayerPos), dot(basis[2], -NplayerPos)); // 转到切线空间。
    float3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), float3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxFresnelSchlickRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    float3 metalAlbedoTint = isMetal ? albedo : float3(1.0); // 金属染色。
    float3 hardCodedMetalsF0[8]; // 参考实现的八种金属。
    hardCodedMetalsF0[0] = float3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = float3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = float3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = float3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = float3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = float3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = float3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = float3(0.961999998804, 0.94946811207, 0.922115710997);
    float3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    float3 reflectance = isMetal ? hardCodedMetals : float3(f0); // 反射率。
    float3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    reflectanceForAlpha = clamp(dot(F0, float3(0.3333333)), 0.0, 1.0); // 参考实现给水面用的反射率。
    if (eyeInWater == 1 && isWater) // 水下看水面的斯涅尔窗。
    {
        float snellsWindow = min(max(0.54 - clamp(1.0 + VdotN, 0.0, 1.0), 0.0) / 0.1, 1.0);
        snellsWindow = 1.0 - snellsWindow * snellsWindow;
        snellsWindow *= snellsWindow * snellsWindow;
        reflectanceForAlpha = f0 + (1.0 - f0) * snellsWindow;
    }
    float3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    float4 environmentReflection = float4(0.0); // 环境反射。
    float backgroundReflectMask = lightmap; // 背景遮罩从光照图开始。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        float3 backgroundReflection = ogxSkyCloudLookup(reflectedVector, skyTexture, pixelSize).rgb / 1200.0; // 天空图。
        if (eyeInWater == 1) backgroundReflection *= exp(-waterAbsorb * 15.0) * 2.0; // 水下吸收。
        float3 backgroundTint = float3(1.0); // 背景染色。
        environmentReflection = ogxEnvironmentReflections(reflectedVector, flatNormal, normal, playerPos,
            viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint, isWater, environmentQuality,
            sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
            previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale, texelSize, 0.0); // 屏幕空间反射。
        backgroundReflection *= backgroundTint;
        float3 darkened = isMetal ? diffuseLighting * (1.0 - environmentReflection.a) * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        specular = lerp(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        specular = lerp(specular, environmentReflection.rgb, environmentReflection.a); // 环境反射。
        specular = lerp(darkened, specular, F0); // 菲涅耳混合。
        specular = lerp(specular, darkened, visibility); // 可见度回退。
    }
    float3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * lightColor
        * ogxGgxBrdf(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // 太阳 GGX。
    specular += lightSourceReflection * (1.0 - environmentReflection.a);
    float3 flashLightReflection = flashLightColor * flashLightStuff.a
        * ogxGgxBrdf(normal, -flashLightStuff.xyz, -flashLightStuff.xyz, roughness, reflectance, metalAlbedoTint); // 手电 GGX。
    specular += flashLightReflection;
    if (handHeldLights && !isHand && firstPersonCamera) // 手持光在反射里的高光。
    {
        if (heldItemId > 0) // 主手。
        {
            float3 shiftedViewPos = viewPos + float3(-0.25, 0.2, 0.0);
            float3 shiftedPlayerPos = ogxMatrix3MulPoint(float3x3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            float3 handLightCol = ogxHandLightFromBlockData(heldItemId, shiftedPlayerPos, lightRange,
                blockDataTexture, float3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxGgxBrdf(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
        if (heldItemId2 > 0) // 副手。
        {
            float3 shiftedViewPos = viewPos + float3(0.25, 0.2, 0.0);
            float3 shiftedPlayerPos = ogxMatrix3MulPoint(float3x3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            float3 handLightCol = ogxHandLightFromBlockData(heldItemId2, shiftedPlayerPos, lightRange,
                blockDataTexture, float3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxGgxBrdf(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
    }
    return specular;
}

#endif
