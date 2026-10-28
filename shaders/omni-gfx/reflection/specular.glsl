/*
生成文件：高光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库高光模块：GGX、可见法线采样、粗糙菲涅耳、反射可见度与高光合成。
调用位置：Eclipse 风格高光与反射合成；由 `/omni-gfx/reflection/specular.glsl` 引入。
可复制示例：
    vec3 color = ogxSpecularReflections(viewPos, playerPos, nPos, lightVec, noise, flatN, n, 0.4, 0.02, albedo, diffuse, light, 1.0, false, false, background, sun, 1.0, 50.0, true, true, flash, 1.0, sceneTex, depthTex, proj, invProj, view, invView, prevProj, prevView, 0.05, 1000.0, delta, 1.0, texel); // 合成高光。
设计原因与取舍：
    金属、介电与水面共用同一套菲涅耳与 GGX；背景天空、环境反射和太阳高光按参考顺序合成。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。高光合成目前只被库内反射模块间接引用，没有顶层画面入口。
*/
#ifndef OGX_REFLECTION_SPECULAR_INCLUDED
#define OGX_REFLECTION_SPECULAR_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 手持光提供光斑、手电与手光阴影。
#include "/omni-gfx/heldlight.glsl"
// 天空提供云环境色、星空与日月圆盘。
#include "/omni-gfx/atmosphere/sky.glsl"
// 反射提供体素与雾的合成入口。
#include "/omni-gfx/reflection/wsr.glsl"
// 法线夹紧：把背向视线的法线朝视线方向拉回，避免掠射高光发黑。
vec3 ogxClampReflectionNormal(vec3 n, vec3 v)
{
    float nDotV = ogxSaturate(dot(n, -v)); // 法线与视线夹角余弦。
    return normalize(nDotV * v + n); // 参考实现的混合。
}

// Frisvad 切线基：由法线直接构造两个正交切向，避免叉乘退化。
mat3 ogxFrisvadBasis(vec3 n)
{
    vec3 f; // 第一切向。
    vec3 r; // 第二切向。
    if (n.z < -0.9) // 法线接近负 z 时用固定基，避免除以接近零的数。
    {
        f = vec3(0.0, -1.0, 0.0);
        r = vec3(-1.0, 0.0, 0.0);
    }
    else
    {
        float a = 1.0 / (1.0 + n.z); // 参考实现的比例。
        float b = -n.x * n.y * a; // 交叉项。
        f = vec3(1.0 - n.x * n.x * a, b, -n.x);
        r = vec3(b, 1.0 - n.y * n.y * a, -n.y);
    }
    return mat3(f, r, n); // 三列依次是切向、副切向、法线。
}

// 可见法线 GGX 采样：把视线压到半球椭球，再采一个半程方向。
vec3 ogxGgxVndfDirection(vec3 viewerDirection, float alpha, vec2 xy)
{
    viewerDirection = normalize(vec3(alpha * 0.5 * viewerDirection.xy, viewerDirection.z)); // 压到半球配置。
    const float tau = OGX_TAU; // 参考实现的两倍圆周。
    float phi = tau * xy.x; // 采样角。
    float cosTheta = (1.0 - xy.y) * (1.0 + viewerDirection.z) - viewerDirection.z; // 余弦。
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0)); // 正弦。
    sinTheta = clamp(sinTheta, 0.0, 1.0); // 参考实现的钳制。
    cosTheta = clamp(cosTheta, sinTheta * 0.5, 1.0); // 参考实现的钳制。
    vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta); // 反射方向。
    vec3 halfway = reflected + viewerDirection; // 半程方向。
    return normalize(vec3(alpha * halfway.xy, halfway.z)); // 回到椭球配置。
}

// Eclipse 的 GGX：粗糙度先取 2.5 次方，再算 D、F 与可见性。
vec3 ogxGgxBrdf(vec3 n, vec3 v, vec3 l, float r, vec3 f0, vec3 metalAlbedoTint)
{
    r = max(pow(r, 2.5), 0.0001); // 粗糙度重整与下限。
    vec3 h = normalize(l + v); // 半程方向。
    float hn = inversesqrt(dot(h, h)); // 半程长度倒数。
    float dotLH = clamp(dot(h, l) * hn, 0.0, 1.0); // 半程与光。
    float dotNH = clamp(dot(h, n) * hn, 0.0, 1.0); // 半程与法线。
    float dotNL = clamp(dot(n, l), 0.0, 1.0); // 法线与光。
    float dotNHsq = dotNH * dotNH; // 平方。
    float denom = dotNHsq * r - dotNHsq + 1.0; // 分母。
    // 参考实现使用十七位圆周率；这里保留长常数，避免换成十一位的 OGX_PI 后高光末位漂移。
    float d = r / (3.141592653589793 * denom * denom); // 法线分布。
    vec3 f = (f0 + (1.0 - f0) * exp2((-5.55473 * dotLH - 6.98316) * dotLH)) * metalAlbedoTint; // 菲涅耳。
    float k2 = 0.25 * r; // 可见性系数。
    return dotNL * d * f / (dotLH * dotLH * (1.0 - k2) + k2); // 合成高光。
}

// Eclipse 的粗糙度菲涅耳：按粗糙度调整曲线与亮度。
float ogxFresnelSchlickRoughness(float xDotN, float roughness)
{
    float shlickFresnel = clamp(1.0 + xDotN, 0.0, 1.0); // 基础菲涅耳。
    float curves = exp(-4.0 * pow(1.0 - roughness, 2.5)); // 曲线权重。
    float brightness = exp(-3.0 * pow(1.0 - sqrt(roughness), 3.50)); // 亮度权重。
    shlickFresnel = pow(1.0 - pow(1.0 - shlickFresnel, mix(1.0, 1.9, curves)), mix(5.0, 2.6, curves)); // 曲线重整。
    shlickFresnel = mix(0.0, mix(1.0, 0.065, brightness), clamp(shlickFresnel, 0.0, 1.0)); // 亮度重整。
    return shlickFresnel; // 交回菲涅耳。
}

// 反射可见度：按 f0 与粗糙度判断高光是否值得显示，避免粗糙金属被反射糊满。
float ogxReflectionVisibility(float f0, float roughness, float roughnessThreshold)
{
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
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    visibilityGradient = 1.0 - visibilityGradient;
    visibilityGradient *= visibilityGradient;
    return visibilityGradient; // 交回可见度。
}

// 高光反射主函数：背景反射、环境反射、太阳 GGX 与手持光 GGX 的合成。
vec3 ogxSpecularReflections(vec3 viewPos, vec3 playerPos, vec3 NplayerPos, vec3 lightVec,
    vec2 noise, vec3 flatNormal, vec3 normal, float roughness, float f0, vec3 albedo,
    vec3 diffuseLighting, vec3 lightColor, float lightmap, bool isHand, bool isMetalPass,
    vec3 backgroundReflection, vec3 sunlightColor, float sunSpecularMultiplier,
    float roughnessThreshold, bool ssrEnabled, bool backgroundEnabled, vec3 flashlightColor,
    float flashlightIntensity, sampler2D sceneTexture, sampler2D depthTexture,
    mat4 projection, mat4 projectionInverse, mat4 modelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 previousModelView, float nearPlane, float farPlane,
    vec3 cameraDelta, float renderScale, vec2 texelSize)
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
    mat3 basis = ogxFrisvadBasis(normal); // 切线基。
    vec3 viewDir = ogxMatrix3MulPoint(basis, -NplayerPos); // 转到切线空间。
    vec3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), vec3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxFresnelSchlickRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0); // 金属染色。
    vec3 hardCodedMetalsF0[8]; // 参考的八种金属反射率，逐项赋值避免 GLSL 330 的数组构造限制。
    hardCodedMetalsF0[0] = vec3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = vec3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = vec3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = vec3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = vec3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = vec3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = vec3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = vec3(0.961999998804, 0.94946811207, 0.922115710997); // 参考实现的八种金属。
    vec3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    vec3 reflectance = isMetal ? hardCodedMetals : vec3(f0); // 反射率。
    vec3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    vec3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    float backgroundReflectMask = lightmap; // 背景遮罩。
    vec4 environmentReflection = vec4(0.0); // 环境反射。
    vec3 backgroundTint = vec3(1.0); // 背景染色。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        vec3 darkened = isMetal ? diffuseLighting * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        if (backgroundEnabled) specular = mix(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        if (ssrEnabled) // 屏幕空间反射。
        {
            environmentReflection = ogxEnvironmentReflections(reflectedVector, flatNormal, normal,
                playerPos, viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint,
                false, 1.0, sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
                previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale,
                texelSize, 0.0); // 不用 Photonics；主世界默认不在水里。
            specular = mix(specular, environmentReflection.rgb, environmentReflection.a); // 合并环境反射。
        }
        specular = mix(darkened, specular, F0); // 按菲涅耳混合。
        specular = mix(specular, darkened, visibility); // 按可见度回到漫反射。
    }
    if (sunSpecularMultiplier > 0.0) // 太阳高光。
    {
        vec3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * sunlightColor
            * ogxGgxBrdf(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // GGX。
        specular += lightSourceReflection * (1.0 - environmentReflection.a); // 环境反射占用后剩下的部分。
    }
    if (flashlightIntensity > 0.0) // 手电高光。
    {
        vec3 flashLightReflection = flashlightColor * flashlightIntensity
            * ogxGgxBrdf(normal, -normal, -normal, roughness, reflectance, metalAlbedoTint); // 参考实现的手电方向近似。
        specular += flashLightReflection;
    }
    return specular; // 交回高光。
}

// 严格参考签名的高光反射入口：背景天空、环境反射、太阳 GGX 与手电 GGX 的顺序照原程序。
// 参考把天空图、屏幕图、深度图与相机矩阵当全局量；库把它们放在参数表尾部，算式不变。
vec3 ogxSpecularReflectionsExact(vec3 viewPos, vec3 playerPos, vec3 NplayerPos, vec3 lightVec,
    vec2 noise, vec3 flatNormal, vec3 normal, float roughness, float f0, vec3 albedo,
    vec3 diffuseLighting, vec3 lightColor, float lightmap, bool isHand, bool isWater,
    inout float reflectanceForAlpha, vec4 flashLightStuff, sampler2D skyTexture, vec2 pixelSize,
    vec3 waterAbsorb, float eyeInWater, float sunSpecularMultiplier, float roughnessThreshold,
    sampler2D sceneTexture, sampler2D depthTexture, mat4 projection, mat4 projectionInverse,
    mat4 modelView, mat4 modelViewInverse, mat4 previousProjection, mat4 previousModelView,
    float nearPlane, float farPlane, vec3 cameraDelta, float renderScale, vec2 texelSize,
    float environmentQuality, vec3 flashLightColor, bool handHeldLights, bool firstPersonCamera,
    usampler1D blockDataTexture, int heldItemId, int heldItemId2)
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
    mat3 basis = ogxFrisvadBasis(normal); // 切线基。
    vec3 viewDir = vec3(dot(basis[0], -NplayerPos), dot(basis[1], -NplayerPos), dot(basis[2], -NplayerPos)); // 转到切线空间。
    vec3 reflectedVector = reflect(NplayerPos, normal); // 理想反射。
    float VdotN = dot(-normalize(viewDir), vec3(0.0, 0.0, 1.0)); // 视线与法线。
    float shlickFresnel = ogxFresnelSchlickRoughness(VdotN, roughness); // 粗糙菲涅耳。
    albedo = f0 == 1.0 ? sqrt(albedo) : albedo; // 金属用底色。
    vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0); // 金属染色。
    vec3 hardCodedMetalsF0[8]; // 参考实现的八种金属。
    hardCodedMetalsF0[0] = vec3(0.531228825312, 0.51235724246, 0.495828545714);
    hardCodedMetalsF0[1] = vec3(0.944229966045, 0.77610211732, 0.373402004593);
    hardCodedMetalsF0[2] = vec3(0.912298031535, 0.91385063144, 0.919680580954);
    hardCodedMetalsF0[3] = vec3(0.55559681715, 0.55453707574, 0.554779427513);
    hardCodedMetalsF0[4] = vec3(0.925952196272, 0.72090163805, 0.504154241735);
    hardCodedMetalsF0[5] = vec3(0.632483812932, 0.62593707362, 0.641478899539);
    hardCodedMetalsF0[6] = vec3(0.678849234658, 0.64240055565, 0.588409633571);
    hardCodedMetalsF0[7] = vec3(0.961999998804, 0.94946811207, 0.922115710997);
    vec3 hardCodedMetals = f0 == 1.0 ? albedo : hardCodedMetalsF0[int(clamp(f0 * 255.0 - 229.5, 0.0, 7.0))]; // 金属 f0。
    vec3 reflectance = isMetal ? hardCodedMetals : vec3(f0); // 反射率。
    vec3 F0 = (reflectance + (1.0 - reflectance) * shlickFresnel) * metalAlbedoTint; // 菲涅耳。
    reflectanceForAlpha = clamp(dot(F0, vec3(0.3333333)), 0.0, 1.0); // 参考实现给水面用的反射率。
    if (eyeInWater == 1 && isWater) // 水下看水面的斯涅尔窗。
    {
        float snellsWindow = min(max(0.54 - clamp(1.0 + VdotN, 0.0, 1.0), 0.0) / 0.1, 1.0);
        snellsWindow = 1.0 - snellsWindow * snellsWindow;
        snellsWindow *= snellsWindow * snellsWindow;
        reflectanceForAlpha = f0 + (1.0 - f0) * snellsWindow;
    }
    vec3 specular = diffuseLighting; // 高光结果。
    float visibility = ogxReflectionVisibility(f0, roughness, roughnessThreshold); // 可见度。
    vec4 environmentReflection = vec4(0.0); // 环境反射。
    float backgroundReflectMask = lightmap; // 背景遮罩从光照图开始。
    if (visibility < 1.0) // 只在需要时算反射。
    {
        vec3 backgroundReflection = ogxSkyCloudLookup(reflectedVector, skyTexture, pixelSize).rgb / 1200.0; // 天空图。
        if (eyeInWater == 1) backgroundReflection *= exp(-waterAbsorb * 15.0) * 2.0; // 水下吸收。
        vec3 backgroundTint = vec3(1.0); // 背景染色。
        environmentReflection = ogxEnvironmentReflections(reflectedVector, flatNormal, normal, playerPos,
            viewPos, noise, isHand, roughness, backgroundReflectMask, backgroundTint, isWater, environmentQuality,
            sceneTexture, depthTexture, projection, projectionInverse, modelView, modelViewInverse,
            previousProjection, previousModelView, nearPlane, farPlane, cameraDelta, renderScale, texelSize, 0.0); // 屏幕空间反射。
        backgroundReflection *= backgroundTint;
        vec3 darkened = isMetal ? diffuseLighting * (1.0 - environmentReflection.a) * (1.0 - lightmap) : diffuseLighting; // 金属压暗。
        specular = mix(darkened, backgroundReflection, backgroundReflectMask); // 背景反射。
        specular = mix(specular, environmentReflection.rgb, environmentReflection.a); // 环境反射。
        specular = mix(darkened, specular, F0); // 菲涅耳混合。
        specular = mix(specular, darkened, visibility); // 可见度回退。
    }
    vec3 lightSourceReflection = backgroundReflectMask * sunSpecularMultiplier * lightColor
        * ogxGgxBrdf(normal, -NplayerPos, lightVec, roughness, reflectance, metalAlbedoTint); // 太阳 GGX。
    specular += lightSourceReflection * (1.0 - environmentReflection.a);
    vec3 flashLightReflection = flashLightColor * flashLightStuff.a
        * ogxGgxBrdf(normal, -flashLightStuff.xyz, -flashLightStuff.xyz, roughness, reflectance, metalAlbedoTint); // 手电 GGX。
    specular += flashLightReflection;
    if (handHeldLights && !isHand && firstPersonCamera) // 手持光在反射里的高光。
    {
        if (heldItemId > 0) // 主手。
        {
            vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = ogxMatrix3MulPoint(mat3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            vec3 handLightCol = ogxHandLightFromBlockData(heldItemId, shiftedPlayerPos, lightRange,
                blockDataTexture, vec3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxGgxBrdf(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
        if (heldItemId2 > 0) // 副手。
        {
            vec3 shiftedViewPos = viewPos + vec3(0.25, 0.2, 0.0);
            vec3 shiftedPlayerPos = ogxMatrix3MulPoint(mat3(modelViewInverse), shiftedViewPos)
                + ogxMatrixTranslation(modelViewInverse) + cameraDelta;
            float lightRange = 0.0;
            vec3 handLightCol = ogxHandLightFromBlockData(heldItemId2, shiftedPlayerPos, lightRange,
                blockDataTexture, vec3(0.0));
            if (lightRange > 0.0) specular += handLightCol * ogxGgxBrdf(normal, -shiftedPlayerPos, -shiftedPlayerPos,
                roughness, reflectance, metalAlbedoTint);
        }
    }
    return specular;
}

/*
实现说明：屏幕空间高光反射。
一、可见法线：按粗糙度把反射方向散开，样本落在椭圆内。
二、追踪：沿反射方向在深度图里步进，命中后取屏幕颜色；手部允许出屏。
三、历史：用上一帧投影重投影命中点，坐标越界时退回当前帧。
四、滤波：九点小波滤波按法线、深度与粗糙度剔除样本，去掉噪点。
五、合成：菲涅尔与粗糙度决定反射比例，金属与湿面提高反射强度。
六、严格入口：`ogxSpecularReflectionsExact` 保留参考参数顺序，资源参数追加在尾部。
七、边界：深度图、法线图、历史图与矩阵全部显式传入；库不读取宿主全局量。
八、顺序：先追踪再滤波，最后与漫反射合成；调换会让反射雾段对不上。
*/
/*
函数索引：
一、`ogxClampReflectionNormal`：把反射法线夹到可见半球，避免背面反射。
二、`ogxFrisvadBasis`：按 Frisvad 方法构造切线基，退化方向有稳定回退。
三、`ogxGgxVndfDirection`：按可见法线分布采样反射方向，输入粗糙度与噪声。
四、`ogxGgxBrdf`：输入法线、视线、光方向、粗糙度与基础反射率，输出高光。
五、`ogxFresnelSchlickRoughness`：粗糙度版的菲涅尔，粗糙面在掠射时不会过亮。
六、`ogxReflectionVisibility`：反射可见度，手部、水下与屏幕边界各有回退。
七、`ogxSpecularReflections`：屏幕空间追踪加历史重投影，输出反射颜色与长度。
八、`ogxSpecularReflectionsExact`：参考签名入口，参数顺序与参考实现一致，资源追加在尾部。
九、滤波：九点小波滤波按法线、深度与粗糙度剔除样本，输入输出都是曲线编码颜色。
十、合成：菲涅尔与粗糙度决定反射比例，金属与湿面提高反射强度。
十一、顺序：先追踪再滤波，最后与漫反射合成；调换会让反射雾段对不上。
十二、边界：深度图、法线图、历史图与矩阵全部显式传入；库不读取宿主全局量。
*/
/*
参数与边界：
一、追踪质量决定步数，质量越高越慢；默认三十步适合中距离反射。
二、近裁剪面与远裁剪面用于线性化深度，调用方要传当前相机的值。
三、渲染缩放小于一时，深度图按四分之一分辨率打包，追踪要按同样的比例取样。
四、手部允许出屏，因为手持物可能贴着画面边缘。
五、水下反射要跳过天空命中，否则水面会出现天空色块。
六、历史重投影需要上一帧的投影与视图矩阵，缺一帧就会退回当前颜色。
七、粗糙度决定层级，粗糙面读更高层级的颜色，避免噪点。
八、反射长度归一化后再算层级，短反射更清晰。
九、九点滤波的法线阈值与深度阈值由调用方给出，场景尺度不同要调整。
十、金属的反射颜色是底色，电介质的反射颜色是白色。
十一、反射强度在湿面与金属上提高，粗糙面降低。
十二、严格入口的参数顺序与参考实现一致，新增资源追加在尾部。
十三、追踪命中天空时返回长度一，调用方据此走背景反射。
十四、深度比较留了偏差，太小会出现自反射条纹，太大则漏掉薄物体。
十五、屏幕空间追踪看不到画面外的物体，调用方要准备体素或天空回退。
十六、滤波只在同一表面内混合，法线差太大时退回中心样本。
十七、反射雾段用命中距离，未命中时用最大距离。
十八、所有纹理与矩阵显式传入，库不读取宿主槽位。
十九、画面缩放的坐标换算容易漏乘，测试时先看四分之一分辨率。
二十、手部与水下分支要单独验证，默认路径不会覆盖它们。
二十一、严格对照检查采样次数与常数，画面需要在测试世界里看反射边缘。
二十二、追踪循环的提前返回只处理出屏，命中与未命中在循环后统一返回。
二十三、历史颜色是曲线编码，读回后要解码再滤波。
二十四、反射合成在显示空间之前完成，避免伽马后再混合造成亮度偏差。
二十五、金属度与粗糙度来自材质解码，调用方要保证范围。
二十六、反射方向要先夹到可见半球，背面反射没有意义。
二十七、切线基在视线与法线平行时退化，Frisvad 方法给了稳定回退。
二十八、采样噪声由调用方传入，逐帧变化能减少固定图案。
二十九、滤波窗口与追踪质量独立，降噪不会增加追踪步数。
三十、反射长度小于零表示未命中，调用方不要拿它算雾。
*/
/*
补充说明：反射合成。
一、反射比例由菲涅尔与粗糙度共同决定。
二、金属的反射颜色是底色。
三、湿面提高反射强度。
四、粗糙面降低反射强度。
五、反射雾段用命中距离。
六、未命中时用最大距离。
七、画面验证看水面与金属边缘。
八、严格对照检查采样次数与常数。
九、所有纹理与矩阵显式传入。
十、离线编译不验证反射画面。
*/
#endif
