/*
生成文件：间接光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库 Eclipse 间接光模块：余弦半球采样、切线基、屏幕空间 GI、双边上采样与 SSGI 合成。
调用位置：需要复现 Eclipse `indirect_lighting_effects.glsl` 的程序；Minecraft 光影由
    `/omni-gfx/gi/indirect.glsl` 引入，当前由严格 profile 与独立测试消费。
可复制示例：
    `vec3 dir = ogxCosineHemisphereDirection(noise);` 生成一条余弦半球方向。
设计原因与取舍：
    参考实现直接读 `gl_FragCoord`、`frameCounter`、`gbufferModelView` 与缓冲编号。库把像素坐标、帧号、
    矩阵、纹理、射线数与开关全部改成显式参数；公式、循环顺序与分支条件保持参考实现。
    纹理只作为参数传入，库不绑定缓冲；调用方可以换分辨率、换历史缓冲，也可以独立测试。
当前状态：仅编译探针与 profile 覆盖，尚无顶层画面消费者。间接光目前只被库内反射模块间接引用，没有顶层画面入口。
*/
#ifndef OGX_GI_INDIRECT_INCLUDED
#define OGX_GI_INDIRECT_INCLUDED

// 相机提供投影与屏幕换算；数学提供夹紧与 R2 采样。
#include "/omni-gfx/common/camera.glsl"
// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "/omni-gfx/common/math.glsl"
// 反射提供屏幕空间追踪与历史重投影。
#include "/omni-gfx/reflection/reflection.glsl"
// 余弦半球采样：把二维均匀随机数变成半球上的余弦分布方向。
vec3 ogxCosineHemisphereDirection(vec2 xi)
{
    float theta = 2.0 * OGX_PI * xi.y; // 方位角。
    float r = sqrt(xi.x); // 半径。
    float x = r * cos(theta); // 横坐标。
    float y = r * sin(theta); // 纵坐标。
    return vec3(x, y, sqrt(clamp(1.0 - xi.x, 0.0, 1.0))); // 半球上的方向。
}

// 切线空间转世界：用任意上向量构造一组正交基，再把半球方向转过去。
vec3 ogxTangentToWorld(vec3 N, vec3 H)
{
    vec3 upVector = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0); // 避免叉乘退化。
    vec3 T = normalize(cross(upVector, N)); // 切向。
    vec3 B = cross(N, T); // 副切向。
    return (T * H.x) + (B * H.y) + (N * H.z); // 参考实现的线性组合。
}


// Eclipse 线性深度反解：米制距离换屏幕深度。
float ogxLinearToScreenDepth(float linearDepth, float nearPlane, float farPlane)
{
    return -((2.0 * nearPlane / linearDepth) - farPlane - nearPlane) / (farPlane - nearPlane); // 参考实现的反解。
}


// 取得纹理的像素尺寸：库需要显式尺寸，避免依赖宿主 `texelSize`。
vec2 texelFetchSize(sampler2D tex)
{
    return vec2(textureSize(tex, 0)); // GLSL 内建，返回整数尺寸。
}

// 取得纹理的像素尺寸：库需要显式尺寸，避免依赖宿主 `texelSize`。
// 屏幕空间 GI 追踪：从视空间位置沿方向步进，撞到深度图里的表面就返回命中点。
// `quarterRes` 为真时读取四分之一分辨率深度缓冲的 alpha 通道。
vec3 ogxGiRayTrace(vec3 dir, vec3 position, float dither, float quality,
    float nearPlane, float farPlane, float renderScale, sampler2D depthTexture, bool quarterRes,
    mat4 projection)
{
    const float biasAmount = 0.0001; // 深度偏差。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点投到裁剪空间。
    float rayLength = ((position.z + dir.z * farPlane * sqrt(3.0)) > -nearPlane)
        ? (-nearPlane - position.z) / dir.z : farPlane * sqrt(3.0); // 射线到近平面的长度。
    vec3 direction = ogxToClipSpace3(position + dir * rayLength, projection) - clipPosition; // 裁剪空间方向。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到屏幕边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z); // 最短的一条。
    vec3 stepv = direction * mult / quality; // 每步长度。
    clipPosition.xy *= renderScale; // 渲染缩放。
    stepv.xy *= renderScale; // 步长同样缩放。
    vec3 spos = clipPosition + stepv * dither; // 起点加抖动。
    float minZ = spos.z - biasAmount / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    for (int i = 0; i <= int(quality); i++) // 固定步数。
    {
        float sampleDepth; // 读深度；分支写成块，严格对照才能按四分之一分辨率开关裁掉另一条。
        if (quarterRes) { sampleDepth = sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture) / 4.0), 0).a / 65000.0); }
        else { sampleDepth = ogxLinearizeDepth(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture)), 0).r, nearPlane, farPlane); }
        float sp = ogxLinearToScreenDepth(sampleDepth, nearPlane, farPlane); // 反解屏幕深度。
        if ((sp < max(minZ, maxZ) && sp > min(minZ, maxZ))) return vec3(spos.xy / renderScale, sp); // 命中。
        minZ = maxZ - biasAmount / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 推进下界。
        maxZ += stepv.z; // 推进上界。
        spos += stepv; // 前进一步。
    }
    return vec3(1.1); // 没有命中。
}

// Eclipse 备用屏幕空间追踪：按屏幕距离决定步长，步数由参考实现的射线步数上限控制。
vec3 ogxGiRayMarch(vec3 dir, vec3 position, float noise, float stepSizes, bool hand,
    inout float curve, int raySteps, float nearPlane, float farPlane, float renderScale,
    vec2 viewSize, vec2 texelSize, vec2 taaOffset, sampler2D depthTexture, bool quarterRes,
    mat4 projection, mat4 modelViewInverse)
{
    vec3 worldPos = ogxToWorldSpace(position, modelViewInverse); // 转到相机相对世界。
    const float biasAmount = 0.00005; // 深度偏差。
    vec2 screenEdges = 2.0 / viewSize; // 屏幕边缘。
    float dist = 1.0 + length(worldPos) / farPlane; // 距离越远步长越大。
    float stepSize = stepSizes / dist; // 当前步长。
    int maxSteps = raySteps; // 最大步数。
    vec3 clipPosition = ogxToClipSpace3(position, projection); // 起点投到裁剪空间。
    float rayLength = ((position.z + dir.z * sqrt(3.0) * farPlane) > -sqrt(3.0) * nearPlane)
        ? (-sqrt(3.0) * nearPlane - position.z) / dir.z : sqrt(3.0) * farPlane; // 射线长度。
    vec3 end = ogxToClipSpace3(position + dir * rayLength, projection); // 终点。
    vec3 direction = end - clipPosition; // 裁剪空间方向。
    float len = max(abs(direction.x) / texelSize.x, abs(direction.y) / texelSize.y) / stepSize; // 屏幕步数。
    vec3 maxLengths = (step(vec3(0.0), direction) - clipPosition) / direction; // 到屏幕边缘的长度。
    float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z) * 2000.0; // 参考实现的放大。
    vec3 stepv = direction / len; // 每步。
    int iterations = min(int(min(len, mult * len) - 2.0), maxSteps); // 实际步数。
    clipPosition.xy *= renderScale; // 渲染缩放。
    stepv.xy *= renderScale; // 步长缩放。
    vec3 spos = clipPosition + stepv * noise; // 起点加抖动。
    spos.xy += taaOffset * texelSize * 0.5 * renderScale; // 时间抗锯齿偏移。
    float minZ = spos.z - biasAmount / ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 深度下界。
    float maxZ = spos.z; // 深度上界。
    curve = 0.0; // 命中前曲线为零。
    for (int i = 0; i < iterations; i++) // 逐级步进。
    {
        spos.xy = clamp(spos.xy, screenEdges, 1.0 - screenEdges); // 夹到屏幕内。
        if (spos.x < 0.0 || spos.y < 0.0 || spos.z < 0.0 || spos.x > 1.0 || spos.y > 1.0 || spos.z > 1.0) return vec3(1.1); // 离开屏幕。
        float sp; // 读深度；分支写成块，严格对照才能按四分之一分辨率开关裁掉另一条。
        if (quarterRes) { sp = ogxLinearToScreenDepth(sqrt(texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture) / 4.0), 0).a / 65000.0), nearPlane, farPlane); }
        else { sp = texelFetch(depthTexture, ivec2(spos.xy / texelFetchSize(depthTexture)), 0).r; }
        float currZ = ogxLinearizeDepth(spos.z, nearPlane, farPlane); // 当前米制深度。
        float nextZ = ogxLinearizeDepth(sp, nearPlane, farPlane); // 采样米制深度。
        if (nextZ < currZ && (sp <= max(minZ, maxZ) && sp >= min(minZ, maxZ))) return vec3(spos.xy / renderScale, sp); // 命中。
        minZ = maxZ - biasAmount / currZ; // 推进下界。
        maxZ += stepv.z; // 推进上界。
        spos += stepv; // 前进一步。
        curve += 1.0 / float(iterations); // 累积曲线。
    }
    return vec3(1.1); // 没有命中。
}

// 双边上采样 SSAO：四邻域按深度差加权，避免把远景遮蔽糊到近景。
vec4 ogxBilateralUpscaleSsao(sampler2D source, sampler2D sourceDepth, ivec2 pixel,
    int upscale, float referenceDepth, float depthThreshold, bool packedDepth, float nearPlane, float farPlane)
{
    ivec2 scaling = ivec2(1); // 参考实现的缩放。
    ivec2 posDepth = pixel * scaling; // 深度采样位置。
    ivec2 posColor = pixel; // 颜色采样位置。
    ivec2 pos = ivec2(vec2(pixel) * texelFetchSize(source) + vec2(1.0)); // 参考实现的偏移。
    ivec2 offsets[4] = ivec2[4](ivec2(-2, -2), ivec2(-2, 0), ivec2(0, 0), ivec2(0, -2)); // 四个邻域。
    vec4 result = vec4(0.0); // 颜色累加。
    float sum = 0.0; // 权重累加。
    for (int i = 0; i < 4; i++) // 四个邻域。
    {
        ivec2 radius = offsets[i]; // 当前偏移。
        float offsetDepth; // 读深度；分支写成块，严格对照才能按打包深度开关裁掉另一条。
        if (packedDepth) { offsetDepth = sqrt(texelFetch(sourceDepth, posDepth + radius * scaling + pos * scaling, 0).a / 65000.0); }
        else { offsetDepth = ogxLinearizeDepth(texelFetch(sourceDepth, posDepth + radius * scaling + pos * scaling, 0).r, nearPlane, farPlane); }
        float edges = abs(offsetDepth - referenceDepth) < depthThreshold ? 1.0 : 1e-5; // 深度边缘权重。
        result += texelFetch(source, posColor + radius + pos, 0) * edges; // 颜色加权。
        sum += edges; // 权重累加。
    }
    return result / sum; // 归一化。
}

// Eclipse 双边上采样入口：参考签名把像素坐标写成 vec2，内部仍按整数像素取四邻域。
// 只是为了保持参考参数顺序，算式走同一份四邻域深度加权。
vec4 ogxBilateralUpscaleSsaoReference(sampler2D source, sampler2D sourceDepth, vec2 coord,
    float referenceDepth, int upscale, float depthThreshold, float nearPlane, float farPlane)
{
    return ogxBilateralUpscaleSsao(source, sourceDepth, ivec2(coord), upscale, referenceDepth,
        depthThreshold, false, nearPlane, farPlane);
}

// SSGI 合成：多根余弦半球射线，命中时读历史场景色，未命中时保留天空贡献。
// 把屏幕空间追踪结果混进间接光，按最小光色与遮挡权重取舍。
vec3 ogxApplyScreenSpaceIndirect(vec3 unchangedIndirect, vec3 blockLightColor, vec3 minimumLightColor,
    vec3 viewPos, vec3 normal, vec3 noise, float lightmap, bool isGrass, bool isLod,
    ivec2 pixelCoord, int frameCounter, int rayCount, int raySteps, float giStrength,
    sampler2D sceneTexture, sampler2D depthTexture, vec2 texelSize,
    mat4 modelView, mat4 previousModelView, mat4 modelViewInverse,
    mat4 previousProjection, mat4 projection, mat4 projectionInverse,
    vec3 cameraDelta, float nearPlane, float farPlane, vec2 viewSize,
    bool quarterRes, bool highQuality, float giCurve)
{
    int nrays = rayCount; // 射线数。
    vec3 radiance = vec3(0.0); // 主辐射。
    vec3 occlusion = vec3(0.0); // 主遮蔽。
    vec3 skycontribution = unchangedIndirect; // 天空贡献。
    vec3 radiance2 = vec3(0.0); // 次辐射。
    vec3 occlusion2 = vec3(0.0); // 次遮蔽。
    vec3 skycontribution2 = unchangedIndirect; // 次天空。
    float curve = giCurve; // 命中曲线。
    vec3 bouncedLight = vec3(0.0); // 反弹光。
    for (int i = 0; i < nrays; i++) // 逐射线。
    {
        int seed = (frameCounter % 40000) * nrays + i; // 参考实现的帧序列。
        vec2 ij = fract(ogxR2Sample(seed) + noise.xy); // 采样点。
        vec3 rayDir = ogxTangentToWorld(normal, normalize(ogxCosineHemisphereDirection(ij))); // 世界方向。
        vec3 rayHit = highQuality
            ? ogxGiRayTrace(ogxMatrix3MulPoint(mat3(modelView), rayDir), viewPos, noise.z, 5.0 * float(raySteps), nearPlane, farPlane, 1.0, depthTexture, quarterRes, projection)
            : ogxGiRayMarch(ogxMatrix3MulPoint(mat3(modelView), rayDir), viewPos, noise.z, float(raySteps), isLod, curve, raySteps, nearPlane, farPlane, 1.0, viewSize, texelSize, vec2(0.0), depthTexture, quarterRes, projection, modelViewInverse); // 低质量版。
        curve = 1.0 - pow(1.0 - pow(1.0 - curve, 2.0), 5.0); // 参考实现的曲线重整。
        skycontribution = unchangedIndirect * (max(rayDir.y, pow(1.0 - lightmap, 2.0)) * 0.95 + 0.05) * 1.25; // 天空权重。
        radiance += skycontribution; // 累积天空。
        radiance2 += skycontribution2; // 累积次天空。
        if (rayHit.z < 0.9999 && distance(vec2(pixelCoord) * texelSize, rayHit.xy) > 0.001) // 命中且不是自身。
        {
            vec3 previousPosition = ogxToWorldSpace(ogxToScreenSpace(rayHit, projectionInverse), modelViewInverse) + cameraDelta; // 历史位置。
            previousPosition = ogxMatrix3MulPoint(mat3(previousModelView), previousPosition) + ogxMatrixTranslation(previousModelView); // 历史视空间。
            previousPosition.xy = ogxProject(previousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5; // 历史屏幕位置。
            if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0)
            {
                bouncedLight = texelFetch(sceneTexture, ivec2(previousPosition.xy / texelSize), 0).rgb * giStrength * curve; // 读历史颜色。
                radiance += bouncedLight; // 累积反弹。
                radiance2 += bouncedLight;
            }
            occlusion += skycontribution * curve; // 累积遮蔽。
            occlusion2 += skycontribution2 * curve;
        }
    }
    if (isLod) return max(radiance / float(nrays), vec3(0.0)); // 远景直接平均。
    return max((radiance - occlusion) / float(nrays), vec3(0.0)); // 参考实现的结果。
}

// Eclipse 的 SSGI 合成主循环：只走参考实现的低质量追踪分支，四根余弦半球射线。
// 为什么单独一份：增强版还带高质量追踪、历史场景色与手部排除；参考默认路径只调用
// `RT_alternate`，采样次数因此是四根射线各一次深度读取。
vec3 ogxApplyScreenSpaceIndirectReference(vec3 unchangedIndirect, vec3 blockLightColor, vec3 minimumLightColor,
    vec3 viewPos, vec3 normal, vec3 noise, float lightmap, bool isGrass, bool isLod,
    ivec2 pixelCoord, int frameCounter, int rayCount, int raySteps, vec2 viewSize, vec2 texelSize,
    sampler2D depthTexture, mat4 modelView, mat4 modelViewInverse, mat4 projection,
    float nearPlane, float farPlane)
{
    int nrays = rayCount; // 射线数。
    vec3 radiance = vec3(0.0); // 主辐射。
    vec3 occlusion = vec3(0.0); // 主遮蔽。
    vec3 skycontribution = unchangedIndirect; // 天空贡献。
    vec3 radiance2 = vec3(0.0); // 次辐射。
    vec3 occlusion2 = vec3(0.0); // 次遮蔽。
    vec3 skycontribution2 = unchangedIndirect; // 次天空。
    float curve = 1.0; // 命中曲线。
    for (int i = 0; i < nrays; i++) // 逐射线。
    {
        int seed = (frameCounter % 40000) * nrays + i; // 参考实现的帧序列。
        vec2 ij = fract(ogxR2Sample(seed) + noise.xy); // 采样点。
        vec3 rayDir = ogxTangentToWorld(normal, normalize(ogxCosineHemisphereDirection(ij))); // 世界方向。
        vec3 rayHit = ogxGiRayMarch(ogxMatrix3MulPoint(mat3(modelView), rayDir), viewPos,
            noise.z, float(raySteps), isLod, curve, raySteps, nearPlane, farPlane, 1.0, viewSize, texelSize,
            vec2(0.0), depthTexture, true, projection, modelViewInverse); // 参考的低质量追踪。
        curve = 1.0 - pow(1.0 - pow(1.0 - curve, 2.0), 5.0); // 曲线重整。
        skycontribution = unchangedIndirect * (max(rayDir.y, pow(1.0 - lightmap, 2.0)) * 0.95 + 0.05) * 1.25; // 天空权重。
        radiance += skycontribution; // 累积天空。
        radiance2 += skycontribution2; // 累积次天空。
        if (rayHit.z < 0.9999 && distance(vec2(pixelCoord) * texelSize, rayHit.xy) > 0.001) // 命中且不是自身。
        {
            occlusion += skycontribution * curve; // 累积遮蔽。
            occlusion2 += skycontribution2 * curve;
        }
    }
    if (isLod) return max(radiance / float(nrays), vec3(0.0)); // 远景直接平均。
    float threshold = isGrass ? 0.8 : (pow(1.0 - lightmap, 2.0) * 0.9 + 0.1); // 草地与普通表面的权重。
    return max((radiance - occlusion) / float(nrays), (radiance2 - occlusion2) / float(nrays) * threshold);
}

// 间接光：Eclipse 的 `doIndirectLighting`，把光照图曲线乘到环境光上。
vec3 ogxIndirectLighting(vec3 lightColor, vec3 minimumLightColor, float lightmap,
    float ambientBrightness, float minLightAmount, float minLightAmountInside, float nightVision)
{
    float lightmapCurve = (pow(lightmap, 15.0) * 2.0 + lightmap * lightmap) / 3.0; // 参考实现的曲线。
    vec3 indirectLight = lightColor * lightmapCurve * ambientBrightness; // 环境光。
    indirectLight += mix(minimumLightColor * (minLightAmount * 0.004 + nightVision * 0.02),
        minimumLightColor * (minLightAmountInside * 0.004 + nightVision * 0.02), 1.0 - lightmap); // 最低亮度。
    return indirectLight; // 交回间接光。
}

#endif
