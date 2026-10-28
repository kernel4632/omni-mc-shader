/*
Omni 通用图形库 Eclipse 漫反射补充模块：手持光阴影、方块光合成与手电光。
调用位置：需要复现 Eclipse `diffuse_lighting.glsl` 的程序；Minecraft 光影由
    `/omni-gfx/gi/diffuse.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    float shadow = ogxSsrtHandlightShadow(viewPos, false, lightDir, noise, normal, false,
        modelViewInverse, nearPlane, farPlane, 1.0, depthTex, projection, 10.0, 0.0015, 0.3);
    vec3 flashlight = ogxFlashlight(texcoord, viewPos, normal, albedo,
        specularData, false, noiseTex, modelViewInverse, previousModelView, cameraWorldPos,
        previousCameraWorldPos, centerDepthSmooth, projectionInverse, 32.0, 1.0, 1.0, 2.0, 1.0, 0.9, 0.8);
设计原因与取舍：
    参考实现直接读 `depthtex2`、`gbufferModelViewInverse` 与手电菜单。库把深度图、矩阵、尺寸与
    手电颜色全部改成显式参数；分支、常数和采样顺序保持参考实现。
    手电的镜头脏污只接噪声纹理参数，不绑定 `noisetex`；这样独立测试与光影可以换纹理。
*/
#ifndef OGX_GI_DIFFUSE_INCLUDED
#define OGX_GI_DIFFUSE_INCLUDED

// 相机提供投影与裁剪空间换算；数学提供夹紧与线性深度。
#include "../camera.slang"
#include "../math.slang"

// 手持光屏幕空间阴影：沿光线方向在深度图里步进，撞到遮挡就压暗。
// 参考固定十步；远近景各取一张深度图，两条分支都写在函数体里，采样次数与参考一致。
float ogxSsrtHandlightShadow(float3 viewPos, bool depthCheck, float3 lightDir, float noise,
    float3 normals, bool hand, float4x4 modelViewInverse, float nearPlane, float farPlane,
    float renderScale, Sampler2D depthTexture, Sampler2D dhDepthTexture, float4x4 projection,
    float4x4 dhProjection, float dhVoxyNearPlane, float dhVoxyFarPlane, float texelSize, float strength)
{
    if (hand) return 1.0; // 手部不投手持光阴影。
    float3 worldLightDir = normalize(ogxMatrixMulPoint(modelViewInverse, lightDir)); // 光方向转世界，参考连平移一起乘。
    float NdotL = smoothstep(0.0, 0.2, abs(dot(normals, worldLightDir))); // 法线朝向的软边。
    float shadows = 1.0; // 阴影结果。
    float samples = 10.0; // 参考固定十步。
    float div = 0.0015; // 固定步长除数。
    float _near = nearPlane; // 近平面。
    float _far = farPlane * 4.0; // 远平面放大四倍。
    if (depthCheck) // 远景使用远景裁剪参数。
    {
        _near = dhVoxyNearPlane;
        _far = dhVoxyFarPlane;
    }
    float3 position = ogxToClipSpace3Dh(viewPos, depthCheck, projection, dhProjection); // 起点投到裁剪空间。
    float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.0)) > -_near)
        ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.0); // 射线长度。
    float3 direction = ogxToClipSpace3Dh(viewPos + lightDir * rayLength, depthCheck, projection, dhProjection) - position; // 裁剪空间方向。
    direction.xyz /= max(max(abs(direction.x) / div, abs(direction.y) / div), 400.0); // 固定步长。
    direction *= 6.0; // 参考实现的步数放大。
    position.xy *= renderScale;
    direction.xy *= renderScale;
    float3 newPos = position + direction * noise; // 加抖动。
    for (int i = 0; i < int(samples); i++) // 固定步数。
    {
        float samplePos;
        if (depthCheck) // 远景深度图。
        {
            samplePos = dhDepthTexture.Load(int3(int2(newPos.xy / texelSize), 0)).x;
        }
        else // 近景深度图。
        {
            samplePos = depthTexture.Load(int3(int2(newPos.xy / texelSize), 0)).x;
        }
        if (samplePos < newPos.z && samplePos > 0.0) // 被遮挡。
        {
            shadows = 0.0;
            break;
        }
        newPos += direction; // 前进一步。
    }
    return clamp(shadows * NdotL, 1.0 - strength, 1.0); // 参考实现的强度夹紧。
}

// 方块光合成：原版光照图曲线、LPV 体积、手持光与手电阴影一起决定最终方块光。
// `lpvSample` 与 `handLight` 由调用方先算好，库只负责曲线与混合。
float3 ogxBlockLightLighting(float3 lightColor, float lightmap, float3 lpvSample,
    float3 handLight, float3 lpvPos, float lpvSize, float fadeLength, float torchAmount,
    bool vanillaMask, bool useLpv)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float brightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    brightspot *= brightspot * brightspot; // 三次方。
    float lightCurve = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightCurve *= lightCurve;
    float lightmapCurve = lerp(lightCurve, 2.5, brightspot); // 混合曲线。
    float3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (useLpv) // 有 LPV 时才混合体积。
    {
        if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版遮罩。
        float3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
        float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        falloff = 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0); // 参考实现曲线。
        blockLight = lerp(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), falloff); // 体积外回退。
        blockLight += handLight; // 手持光相加。
    }
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 手电光：把屏幕位置换成手电筒锥，再按距离、圆斑与镜头脏污叠出光斑。
// `specularData` 返回方向与强度，供高光阶段复用。
// 参考签名是屏幕坐标、视空间位置、法线与底色；矩阵、相机位置、深度图与手电参数显式追加。
float3 ogxFlashlight(float2 texcoord, float3 viewPos, float3 normal, float3 albedo,
    out float4 specularData, bool hand, Sampler2D noiseTexture, float4x4 modelViewInverse,
    float4x4 previousModelView, float3 cameraWorldPos, float3 previousCameraWorldPos,
    float centerDepthSmooth, float4x4 projectionInverse, float range, float brightnessFalloff,
    float brightness, float size, float red, float green, float blue)
{
    float forwardOffset = 0.5; // 参考实现的前向偏移。
    float3 shiftedViewPos = viewPos + float3(-0.25, 0.2, 0.0); // 手电在视线左上方。
    float3 shiftedPlayerPos = ogxMatrix3MulPoint(float3x3(modelViewInverse), shiftedViewPos) + ogxMatrixTranslation(modelViewInverse)
        + (cameraWorldPos - previousCameraWorldPos) * 3.0; // 相机相对位置并补上相机移动。
    shiftedViewPos = ogxMatrix3MulPoint(float3x3(previousModelView), shiftedPlayerPos) + ogxMatrixTranslation(previousModelView); // 换到上一帧视空间，避免手电抖动。
    float2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - forwardOffset, 1e-7); // 投到屏幕。
    float linearDistance = length(shiftedPlayerPos); // 到手电的距离。
    float shiftedLinearDistance = length(scaledViewPos); // 屏幕距离。
    float lightFalloff = 1.0 - clamp(1.0 - linearDistance / range, -0.999, 1.0); // 距离衰减。
    lightFalloff = max(exp(-10.0 * brightnessFalloff * lightFalloff), 0.0); // 指数衰减。
    float specular = lightFalloff * exp2(-7.0 * shiftedLinearDistance * shiftedLinearDistance) * brightness; // 高光强度。
    specularData = float4(normalize(shiftedPlayerPos), specular); // 方向与强度。
    float projectedCircle = clamp(1.0 - shiftedLinearDistance * size, 0.0, 1.0); // 圆斑。
    float lensDirt = noiseTexture.SampleLevel(scaledViewPos * 0.2 + 0.1, 0.0).b; // 镜头脏污。
    float lensShape = (pow(abs(pow(abs(projectedCircle - 1.0), 2.0) * 2.0 - 0.5), 2.0) + lensDirt * 0.2) * 10.0; // 光斑形状。
    float offsetNdotL = clamp(dot(-normal, normalize(shiftedPlayerPos)), 0.0, 1.0); // 法线朝向。
    float3 diffuse = float3(1.0) * lightFalloff * offsetNdotL * pow(1.0 - pow(1.0 - projectedCircle, 2.0), 2.0) * lensShape * brightness; // 漫反射光斑。
    if (hand) // 手部不发光。
    {
        diffuse = float3(0.0);
        specularData = float4(0.0);
    }
    float lightWidth = 1.0 + linearDistance * 3.0; // 手电在屏幕上的覆盖宽度。
    float3 pointPos = ogxToScreenSpace(float3(texcoord, centerDepthSmooth), projectionInverse) + float3(-0.25, 0.2, 0.0); // 命中点换回视空间。
    pointPos = ogxMatrix3MulPoint(float3x3(modelViewInverse), pointPos); // 换到相机相对世界位置。
    float flashLightHitPoint = distance(pointPos, shiftedPlayerPos); // 命中点到手电的距离。
    float indirectFlashLight = exp(-10.0 * (1.0 - clamp(1.0 - length(shiftedViewPos.xy) / lightWidth, 0.0, 1.0))); // 屏幕范围的柔光。
    indirectFlashLight *= pow(clamp(1.0 - flashLightHitPoint / lightWidth, 0.0, 1.0), 2.0); // 越远越弱。
    diffuse += albedo / 150.0 * indirectFlashLight * lightFalloff; // 被照表面的间接反光。
    return diffuse * float3(red, green, blue); // 按手电颜色输出。
}

// 方块光体素版：LPV 采样与手持光由调用方传入，曲线和边缘淡出与参考实现相同。
float3 ogxBlockLightLightingVoxel(float3 lightColor, float lightmap, float3 lpvSample,
    float3 handLight, float3 lpvPos, float lpvSize, float fadeLength, float torchAmount, bool vanillaMask)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 夹紧光照。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 参考实现的曲线。
    lightmapLight *= lightmapLight;
    float lightmapCurve = lerp(lightmapLight, 2.5, lightmapBrightspot); // 混合曲线。
    float3 blockLight = lightmapCurve * lightColor; // 方块光。
    if (vanillaMask) lpvSample.rgb *= lightmapCurve; // 原版光照图遮罩。
    float3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘坐标。
    float voxelRangeFalloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
    voxelRangeFalloff = 1.0 - pow(1.0 - pow(voxelRangeFalloff, 1.5), 3.0); // 参考实现的曲线。
    blockLight = lerp(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap - 0.999, 0.0) / (1.0 - 0.999), 1.0), voxelRangeFalloff); // 体积外回退。
    blockLight += handLight; // 手持光直接相加。
    return blockLight * torchAmount; // 参考实现的亮度缩放。
}

// 参考签名版的方块光体素曲线：只保留 `specular.glsl` 默认分支里的光照图曲线。
// 为什么单独一份：增强版还会混入 LPV 与手持光，默认路径的常数集合会多出参考没有的值；
// 严格对照需要一个只做参考算式的入口，调用方按需选择增强版或这一份。
float3 ogxBlockLightLightingVoxelExact(float3 lightColor, float lightmap, float3 lpvSample,
    float3 handLight, float torchAmount)
{
    lightmap = clamp(lightmap, 0.0, 1.0); // 参考实现先把光照图夹到合法范围。
    float lightmapBrightspot = min(max(lightmap - 0.7, 0.0) * 3.3333, 1.0); // 高亮区线性起点。
    lightmapBrightspot *= lightmapBrightspot * lightmapBrightspot; // 三次方让高亮区收窄。
    float lightmapLight = 1.0 - sqrt(1.0 - lightmap); // 平方根曲线。
    lightmapLight *= lightmapLight; // 再平方，暗部抬升更明显。
    float lightmapCurve = lerp(lightmapLight, 2.5, lightmapBrightspot); // 高亮区混向固定亮度。
    float3 blockLight = lightmapCurve * lightColor; // 光照图乘方块光颜色。
    return blockLight * torchAmount; // 参考实现最后乘火把亮度。
}

#endif
