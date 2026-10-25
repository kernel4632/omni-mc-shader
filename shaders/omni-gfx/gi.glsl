/*
生成文件：全局光模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库全局光模块：地平线遮蔽、反射阴影图反弹、历史重投影、时间与空间滤波。
调用位置：任何需要屏幕空间全局光或环境遮蔽的程序；Minecraft 光影由 `/omni-gfx/gi.glsl` 引入。
可复制示例：
    `float ao = ogxGroundTruthAo(viewPos, viewDir, normal, coord, aspect, depthTex, dhTex, projection, projectionInverse, dhInverse, params, noise);` 一帧的地平线遮蔽。
    `vec3 bounce = ogxAoMultiBounce(ao, albedo);` 给遮蔽补一次多弹射。
    `vec3 filtered = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);` 七乘七空间滤波。
设计原因与取舍：
    纹理、矩阵、相机位置与选项全部由调用方传入，库不读取引擎状态；`OgxGiView` 把同一帧的
    相机与屏幕参数打包，避免每个函数重复十几项。算法与旧 `shaders/gfx/gi.glsl` 逐项一致，
    迁移只改名字和语法，默认画面因此不变；地平线遮蔽的采样仍由调用方负责，这里只做纯数学。
*/
#ifndef OGX_GI_INCLUDED
#define OGX_GI_INCLUDED

// 饱和、快速反余弦、曲线编码与噪声来自数学模块；阴影投影来自阴影模块。
#include "/omni-gfx/math.glsl"
#include "/omni-gfx/shadow.glsl"
// 螺旋采样的黄金角正余弦：每步旋转这个角度，样本沿螺旋均匀铺开。
const float OGX_GI_GOLDEN_COS = -0.737368878;
const float OGX_GI_GOLDEN_SIN = 0.675490294;

// 一帧全局光需要的相机、投影与屏幕参数；字段名保持普通图形术语，不绑定任何宿主。
struct OgxGiView
{
    mat4 projection_inverse; // 近景逆投影。
    mat4 previous_projection; // 上一帧投影。
    mat4 model_view_inverse; // 视空间转世界。
    mat4 previous_model_view; // 上一帧世界转视空间。
    mat4 model_view; // 本帧世界转视空间。
    mat4 shadow_view; // 阴影相机视图。
    mat4 shadow_projection; // 阴影相机投影。
    mat4 dh_projection_inverse; // 远景逆投影；没有远景时填近景值占位。
    mat3 shadow_normal; // 法线从世界转到阴影相机。
    vec3 camera_position; // 本帧相机世界位置。
    vec3 previous_camera_position; // 上一帧相机世界位置。
    vec2 screen_size; // 画面像素尺寸。
    vec2 texel_size; // 一个像素的屏幕坐标大小。
};

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。
vec3 ogxAoMultiBounce(float ao, vec3 albedo)
{
    vec3 a = 2.0404 * albedo - 0.3324; // 一次项系数。
    vec3 b = -4.7951 * albedo + 0.6417; // 二次项系数。
    vec3 c = 2.7552 * albedo + 0.6903; // 三次项系数。
    return max(vec3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}

// 双边升采样：把半分辨率的遮蔽（或任何四通道画面）放大到全分辨率。
// 四个相邻纹素先按深度筛一次：只有与参考深度相差不超过阈值的样本参与，物体边界不会被糊开。
// 为什么不用普通双线性：半分辨率的一格盖住全分辨率两格，边界处会把前景与背景混成一条灰边。
// `pixel` 是全分辨率像素坐标，`upscale` 是遮蔽图相对全分辨率的倍数（通常为二）；
// `referenceDepth` 与 `sourceDepth` 必须用同一套深度单位，阈值也按这套单位给出。
vec4 ogxBilateralUpscale(sampler2D source, sampler2D sourceDepth, ivec2 pixel, int upscale,
    float referenceDepth, float depthThreshold)
{
    ivec2 base = pixel / upscale; // 当前像素落在遮蔽图的哪一格。
    vec4 result = vec4(0.0); // 加权颜色。
    float sum = 0.0; // 权重和。
    for (int i = 0; i < 4; i++) // 四个相邻格，正好围住这一格。
    {
        ivec2 offset = ivec2(i < 2 ? -1 : 0, (i == 0 || i == 3) ? -1 : 0); // 四个格子的相对位置。
        ivec2 cell = base + offset; // 邻格坐标。
        float sampleDepth = texelFetch(sourceDepth, cell, 0).r; // 邻格的深度。
        float weight = abs(sampleDepth - referenceDepth) < depthThreshold ? 1.0 : 1e-5; // 深度相近才参与。
        result += texelFetch(source, cell, 0) * weight; // 累加颜色。
        sum += weight; // 累加权重。
    }
    return result / sum; // 归一化；四个样本全被拒绝时权重和仍然大于零。
}

// 屏幕坐标与深度还原视空间位置，不撤销抖动；重投影需要原始位置。
vec3 ogxGiViewPos(vec2 coord, float depth, mat4 projection_inverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec3 pos = vec3(vec2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + ogxMatrixTranslation(projection_inverse); // 只用逆投影的非零项与平移列。
    return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 远景屏幕坐标与深度还原视空间位置；没有远景时调用方不会走到这里。
vec3 ogxGiViewPosDh(vec2 coord, float depth, mat4 dh_projection_inverse)
{
    vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
    vec4 pos = ogxMatrixMul(dh_projection_inverse, vec4(ndc, 1.0)); // 远景逆投影整矩阵乘法。
    return pos.xyz / pos.w; // 透视除法。
}

// 地平线遮蔽的参数：画质、半径模式、远景能力与强度都由调用方给出。
struct OgxGtaoParams
{
    float steps; // 环绕视线的切片数。
    float slice_steps; // 每个切片的搜索步数。
    float falloff_start; // 衰减起点，占半径的比例。
    float max_sample_radius; // 屏幕半径上限。
    float world_radius; // 世界半径模式下的起始半径。
    float screen_radius; // 屏幕半径模式下的固定半径。
    float strength; // 遮蔽强度，零为无遮蔽、一为全遮蔽。
    int radius_mode; // 零为世界半径，其他为屏幕半径。
    bool has_dh; // 是否有远景深度，决定世界半径随距离衰减的快慢。
    bool dh_ao; // 是否把远景样本当作遮挡物。
    bool falloff_z_offset; // 是否用深度加权的衰减距离。
};

// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 深度图、投影矩阵、画面坐标、比例与噪声全部由调用方传入，库不读取任何引擎画面。
float ogxGroundTruthAo(vec3 viewPos, vec3 viewDir, vec3 normal, vec2 coord, float aspect,
    sampler2D depthTexture, sampler2D dhDepthTexture, mat4 projection, mat4 projection_inverse,
    mat4 dh_projection_inverse, OgxGtaoParams params, vec2 noise)
{
    float rSteps = 1.0 / params.steps; // 切片数倒数。
    float rSliceSteps = 1.0 / params.slice_steps; // 步数倒数。
    float projFactor = 0.125 * projection[1][1]; // 投影缩放系数。
    float radius; // 世界半径或屏幕半径。
    float sampleRadiusRaw; // 换算后的屏幕半径。
    float sampleRadius; // 夹紧后的屏幕半径。
    float falloff; // 衰减距离。
    if (params.radius_mode == 0) // 世界半径模式。
    {
        radius = params.world_radius - viewPos.z * (params.has_dh ? 0.02 : 0.01); // 有远景时衰减更慢。
        sampleRadiusRaw = radius * projFactor / -viewPos.z; // 换成屏幕半径。
        sampleRadius = min(sampleRadiusRaw, params.max_sample_radius); // 上限。
        falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
    }
    else // 屏幕半径模式。
    {
        sampleRadius = params.screen_radius; // 固定屏幕半径。
        falloff = sampleRadius / projFactor * -viewPos.z; // 换算成世界衰减距离。
    }
    float ao = 0.0; // 累积的遮蔽。
    float slice_steps = params.slice_steps; // 每个切片的搜索步数。
    for (float i = 0.0; i < params.steps; i++) // 逐切片。
    {
        float sliceAngle = (i + noise.x) * rSteps * OGX_PI; // 切片角度，只扫半圈因为两侧对称。
        vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
        vec3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 切片方向正交到视线的分量。
        vec3 axis = cross(sliceDir, viewDir); // 切片平面法向。
        vec3 projNormal = normal - dot(normal, axis) * axis; // 法线投影到切片平面。
        float rProjNormalLength = inversesqrt(dot(projNormal, projNormal)); // 投影长度倒数。
        float cosNormalAngle = ogxSaturate(dot(projNormal, viewDir) * rProjNormalLength); // 投影法线与视线夹角余弦。
        float normalAngle = sign(dot(orthoSliceDir, projNormal)) * ogxFastAcos(cosNormalAngle); // 带符号的法线角。
        vec2 minCosHorizonAngle = cos(vec2(normalAngle + OGX_HALF_PI, normalAngle - OGX_HALF_PI)); // 两侧地平线角的下限。
        vec2 maxCosHorizonAngle = minCosHorizonAngle; // 两侧可见地平线角的初值。
        for (float j = 0.0; j < slice_steps; j++) // 逐搜索步。
        {
            float stepNoise = (i + j * slice_steps) * 0.61803399; // 用黄金比错开各步。
            stepNoise = fract(stepNoise + noise.y); // 加噪声后取小数。
            float offset = (j + stepNoise) * rSliceSteps; // 归一化搜索距离。
            offset *= offset; // 平方让近处更密。
            vec2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
            sampleOffset.y *= aspect; // 修正宽高比。
            {
                vec2 sampleCoord = coord + sampleOffset; // 正向采样坐标。
                float sampleDepth = textureLod(depthTexture, sampleCoord, 0.0).x; // 采样深度。
                vec3 sampleVector; // 采样点相对当前点。
                if (params.has_dh && params.dh_ao && sampleDepth == 1.0) // 天空样本改读远景深度。
                {
                    sampleDepth = textureLod(dhDepthTexture, sampleCoord, 0.0).x; // 远景深度。
                    sampleVector = ogxGiViewPosDh(sampleCoord, sampleDepth, dh_projection_inverse) - viewPos; // 远景还原。
                }
                else // 近景样本正常还原。
                {
                    sampleVector = ogxGiViewPos(sampleCoord, sampleDepth, projection_inverse) - viewPos; // 近景还原。
                }
                float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
                float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
                float falloffWeight; // 衰减权重。
                if (params.falloff_z_offset) // 可选的深度加权。
                {
                    float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * 1.7)); // 加权距离。
                    falloffWeight = ogxRemapSaturate(offsetDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                else // 默认按距离加权。
                {
                    falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.x, falloffWeight); // 远处回落到下限。
                maxCosHorizonAngle.x = max(cosHorizonAngle, maxCosHorizonAngle.x); // 取可见地平线角。
            }
            {
                vec2 sampleCoord = coord - sampleOffset; // 反向采样坐标。
                float sampleDepth = textureLod(depthTexture, sampleCoord, 0.0).x; // 采样深度。
                vec3 sampleVector; // 采样点相对当前点。
                if (params.has_dh && params.dh_ao && sampleDepth == 1.0) // 天空样本改读远景深度。
                {
                    sampleDepth = textureLod(dhDepthTexture, sampleCoord, 0.0).x; // 远景深度。
                    sampleVector = ogxGiViewPosDh(sampleCoord, sampleDepth, dh_projection_inverse) - viewPos; // 远景还原。
                }
                else // 近景样本正常还原。
                {
                    sampleVector = ogxGiViewPos(sampleCoord, sampleDepth, projection_inverse) - viewPos; // 近景还原。
                }
                float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
                float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
                float falloffWeight; // 衰减权重。
                if (params.falloff_z_offset) // 可选的深度加权。
                {
                    float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * 1.7)); // 加权距离。
                    falloffWeight = ogxRemapSaturate(offsetDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                else // 默认按距离加权。
                {
                    falloffWeight = ogxRemapSaturate(1.0 / rSampleDist, falloff * params.falloff_start, falloff); // 衰减权重。
                }
                cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.y, falloffWeight); // 远处回落到下限。
                maxCosHorizonAngle.y = max(cosHorizonAngle, maxCosHorizonAngle.y); // 取可见地平线角。
            }
        }
        maxCosHorizonAngle = vec2(-ogxFastAcos(maxCosHorizonAngle.y), ogxFastAcos(maxCosHorizonAngle.x)) * 2.0; // 两侧换成开口角。
        float horizonAngleIntegra = 2.0 * cosNormalAngle + (maxCosHorizonAngle.x + maxCosHorizonAngle.y) * sin(normalAngle) - cos(maxCosHorizonAngle.x - normalAngle) - cos(maxCosHorizonAngle.y - normalAngle); // 这一片的半球可见缺口。
        ao += horizonAngleIntegra / rProjNormalLength; // 累加。
    }
    ao *= 0.25 * rSteps; // 平均。
    return ogxSaturate(mix(1.0, ao, params.strength)); // 按强度在无遮蔽与遮蔽之间插值。
}

// 历史法线与深度采样：四个角按法线、距离和双线性权重混合，返回未归一化的历史反弹。
vec3 ogxGiHistorySample(vec3 currNormal, float currDist, vec3 cameraVelocity, vec2 prevCoord, float renderScale,
    sampler2D historyTexture, sampler2D normalTexture, vec2 screen_size, out float weightSum)
{
    vec2 prevTexel = floor(prevCoord); // 历史纹素整数部分。
    vec3 prevGi = vec3(0.0); // 累积历史反弹。
    weightSum = 0.0; // 权重和。
    for (int k = 0; k < 4; k++) // 左下、右下、左上、右上四个历史纹素。
    {
        vec2 sampleTexel = prevTexel + vec2(float(k >> 1), float(k & 1)); // 按下标拼出四个角。
        vec4 prevData = texelFetch(normalTexture, ivec2(sampleTexel.x + renderScale * screen_size.x, sampleTexel.y), 0); // 读历史法线深度。
        vec3 prevNormal = prevData.xyz * 2.0 - 1.0; // 还原历史法线。
        float normalWeight = float(dot(currNormal, prevNormal) > 0.5); // 法线相近才参与。
        float prevDist = prevData.a * 1000.0; // 历史距离。
        float depthWeight = max(abs(currDist - prevDist - cameraVelocity.z), 0.0); // 距离差。
        depthWeight = exp(-depthWeight / (currDist * 0.1 + 0.1)); // 差距越大权重越低。
        depthWeight = ogxSaturate(depthWeight * 2.0); // 放大后再收敛。
        float bilinearWeight = (1.0 - abs(prevCoord.x - sampleTexel.x)) * (1.0 - abs(prevCoord.y - sampleTexel.y)); // 双线性权重。
        bilinearWeight *= normalWeight * depthWeight; // 总权重。
        prevGi += ogxCurveToLinear3(texelFetch(historyTexture, ivec2(sampleTexel), 0).rgb) * bilinearWeight; // 累加解码后的历史反弹。
        weightSum += bilinearWeight; // 累加权重。
    }
    return prevGi; // 交回加权历史反弹。
}

// 反射阴影图反弹：从阴影图里可见的表面取底色，按法线朝向与距离给当前点补一份光。
// `useSolidShadow` 对应支持遮挡贴图的显卡，`leakFix` 对应主世界的阳光泄漏修正，`underwater` 是眼睛在水下。
vec3 ogxGiRsm(vec3 viewPos, vec3 normal, OgxGiView view,
    sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0, sampler2D shadowColor1,
    float radius, int steps, float falloff, float shadowMapResolution, float shadowBias, vec2 noise,
    bool useSolidShadow, bool leakFix, bool underwater)
{
    vec3 worldPos = ogxMatrixMulPoint(view.model_view_inverse, viewPos) + ogxMatrixTranslation(view.model_view_inverse); // 视空间位置换世界空间。
    vec3 shadowPosition = ogxShadowScreenPos(worldPos, view.shadow_view, view.shadow_projection); // 投到阴影图。
    vec3 shadow_normal = ogxMatrix3MulPoint(view.shadow_normal, normal); // 法线转到阴影相机空间；三乘三矩阵在调用方已经组合好。
    float pixelOffset = radius * view.shadow_projection[0][0]; // 搜索半径换成阴影图像素。
    float zScale = 1.0 / view.shadow_projection[0][0]; // 阴影深度的缩放系数。
    float angle = noise.x * 6.28318530718; // 起始旋转角。
    vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
    float rSteps = 1.0 / float(steps); // 采样次数倒数。
    vec3 rsm = vec3(0.0); // 累积的反弹颜色。
    for (int i = 0; i < steps; i++) // 螺旋逐点采样。
    {
        rot = vec2(OGX_GI_GOLDEN_COS * rot.x + OGX_GI_GOLDEN_SIN * rot.y,
                     -OGX_GI_GOLDEN_SIN * rot.x + OGX_GI_GOLDEN_COS * rot.y); // 每步旋转黄金角。
        float r = (float(i) + noise.y) * rSteps; // 归一化半径。
        vec2 offset = rot * r * pixelOffset; // 屏幕偏移。
        vec2 offsetPosition = shadowPosition.xy + offset; // 采样点的阴影图坐标。
        vec2 sampleCoord = ogxDistortShadowPos(offsetPosition, shadowBias); // 还原压缩后的坐标。
        ivec2 sampleTexel = ivec2(shadowMapResolution * sampleCoord); // 换成纹素。
        float sampleDepth = useSolidShadow ? texelFetch(shadowDepth1, sampleTexel, 0).x : texelFetch(shadowDepth0, sampleTexel, 0).x; // 按显卡能力选深度图。
        if (sampleDepth == 0.0 || sampleDepth >= 1.0) // 没有几何或超出范围就跳过。
        {
            continue;
        }
        vec3 sampleVector = vec3(offsetPosition, sampleDepth) - shadowPosition; // 采样点相对当前点。
        sampleVector *= vec3(zScale, zScale, -zScale * 2.0); // 修正到统一的深度尺度。
        vec3 sampleDir = normalize(sampleVector); // 采样方向。
        float nDotV = dot(sampleDir, shadow_normal); // 当前点法线与采样方向的夹角余弦。
        if (nDotV <= 0.0) // 背对采样点不接收。
        {
            continue;
        }
        vec4 sampleData = texelFetch(shadowColor1, sampleTexel, 0); // 读阴影图里的法线与天光。
        vec3 sampleNormal = sampleData.rgb * 2.0 - 1.0; // 还原采样点法线。
        float snDotV = dot(-sampleDir, sampleNormal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
        if (snDotV < 0.0) // 背对方向不发光。
        {
            continue;
        }
        vec3 sampleAlbedo = ogxGammaToLinear(texelFetch(shadowColor0, sampleTexel, 0).rgb); // 采样点底色转线性。
        sampleVector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
        float sampleDist = length(sampleVector); // 采样距离。
        float distFalloff = pow(sampleDist + 0.035, -falloff) * ogxFastSqrt(1.0 - r); // 距离衰减与中心加权。
        float lightMask = leakFix ? ogxSaturate(sampleData.a * 15.0 + float(underwater)) : 1.0; // 主世界只给接到天光或水里的点补光。
        rsm += sampleAlbedo * (nDotV * snDotV * distFalloff * lightMask); // 累加一份反弹。
    }
    rsm *= rSteps * radius * 0.1; // 平均并按半径缩放。
    return rsm; // 返回反弹颜色。
}

// 相机速度：区分远景与近景、手与世界，算出当前像素相对上一帧的屏幕位移。
vec2 ogxGiCameraVelocity(vec2 coord, float depth, bool isDh, float materialIds, OgxGiView view,
    bool disableHand, bool disablePlayer, float handDepth, float playerMaterial)
{
    vec3 screenPos = vec3(coord, depth); // 屏幕坐标加深度。
    vec3 projection = vec3(0.0); // 上一帧投影结果。
    if (isDh) // 远景像素用远景矩阵。
    {
        projection = vec3(vec2(view.dh_projection_inverse[0].x, view.dh_projection_inverse[1].y) * (screenPos * 2.0 - 1.0).xy, 0.0) + ogxMatrixTranslation(view.dh_projection_inverse); // 逆投影到视空间。
        projection /= view.dh_projection_inverse[2].w * (screenPos.z * 2.0 - 1.0) + view.dh_projection_inverse[3].w; // 透视除法。
        projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
        projection += view.camera_position - view.previous_camera_position; // 加相机世界位移。
        projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 世界转上一帧视空间。
    }
    else // 近景像素。
    {
        vec3 ndc = screenPos * 2.0 - 1.0; // 转负一到一。
        projection = vec3(vec2(view.projection_inverse[0].x, view.projection_inverse[1].y) * ndc.xy, 0.0) + ogxMatrixTranslation(view.projection_inverse); // 逆投影到视空间。
        projection /= view.projection_inverse[2].w * ndc.z + view.projection_inverse[3].w; // 透视除法。
        bool isPlayer = materialIds == playerMaterial; // 玩家像素标记。
        if (disableHand && disablePlayer) // 手和玩家都不参与重投影。
        {
            if (depth >= 0.7 && !isPlayer) // 非玩家且较远。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disableHand) // 只有手不参与。
        {
            if (depth >= 0.7) // 较远像素才重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
        else if (disablePlayer) // 只有玩家不参与。
        {
            if (!isPlayer) // 非玩家像素。
            {
                if (depth < 0.7) // 手部固定深度偏移。
                {
                    projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
                }
                else // 其他近景像素正常重投影。
                {
                    projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                    projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                    projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
                }
            }
        }
        else // 都参与重投影。
        {
            if (depth < 0.7) // 手部固定位移。
            {
                projection += (ogxMatrixTranslation(view.previous_model_view) - ogxMatrixTranslation(view.model_view)) * handDepth;
            }
            else // 其他近景像素正常重投影。
            {
                projection = ogxMatrixMulPoint(view.model_view_inverse, projection) + ogxMatrixTranslation(view.model_view_inverse); // 视空间转世界。
                projection += view.camera_position - view.previous_camera_position; // 加相机位移。
                projection = ogxMatrixMulPoint(view.previous_model_view, projection) + ogxMatrixTranslation(view.previous_model_view); // 转上一帧视空间。
            }
        }
    }
    vec3 previousScreen = vec3(view.previous_projection[0].x, view.previous_projection[1].y, view.previous_projection[2].z) * projection + ogxMatrixTranslation(view.previous_projection); // 上一帧投影的缩放与平移项。
    previousScreen = previousScreen / -projection.z * 0.5 + 0.5; // 透视除法与零到一换算，除数用投影前的深度。
    return coord - previousScreen.xy; // 返回屏幕位移。
}

// 全局光时间滤波：本帧反弹与历史帧按法线、深度和运动量混合，同时把法线与距离写回历史图。
vec4 ogxGiTemporalFilter(vec2 coord, ivec2 texelCoord, OgxGiView view,
    sampler2D historyTexture, sampler2D normalTexture, sampler2D materialTexture, sampler2D depthTexture, sampler2D dhDepthTexture,
    sampler2D shadowDepth0, sampler2D shadowDepth1, sampler2D shadowColor0, sampler2D shadowColor1,
    float renderScale, bool has_dh, bool useDhAo, bool newVersion, bool leakFix, bool underwater,
    bool useSolidShadow, bool disableHand, bool disablePlayer, float handDepth, float playerMaterial,
    float radius, float falloff, int steps, float shadowMapResolution, float shadowBias, vec2 noise)
{
    vec4 prev = texelFetch(historyTexture, texelCoord, 0); // 先取历史像素。
    vec2 local = coord / renderScale; // 全局光渲染分辨率下的坐标。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        ivec2 texel = ivec2(local * view.screen_size); // 对应的屏幕纹素。
        float currDepth = texelFetch(depthTexture, texel, 0).x; // 本帧不透明深度。
        bool isDh = false; // 是否远景像素。
        if (has_dh && useDhAo && currDepth == 1.0) // 天空像素改读远景深度。
        {
            currDepth = texelFetch(dhDepthTexture, texel, 0).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (currDepth < 1.0) // 有几何才算反弹。
        {
            vec4 data3 = texelFetch(normalTexture, texel, 0); // 读法线光照图。
            vec3 currNormal = ogxDecodeNormal(data3.xy); // 解出本帧法线。
            vec3 currViewPos = ogxGiViewPos(local, currDepth, view.projection_inverse); // 还原视空间位置。
            if (isDh) // 远景用远景逆投影。
            {
                currViewPos = ogxGiViewPosDh(local, currDepth, view.dh_projection_inverse);
            }
            vec3 gi = vec3(0.0); // 本帧反弹。
            bool applyRsm = true; // 默认所有像素都反弹。
            if (newVersion) // 新版本按天光标记决定。
            {
                if (leakFix) // 只有接到天光或在水里才反弹。
                {
                    applyRsm = data3.w > 0.0 || underwater;
                }
            }
            else // 旧版本还要求像素足够远。
            {
                if (leakFix) // 较远且接到天光。
                {
                    applyRsm = currDepth > 0.7 && (data3.w > 0.0 || underwater);
                }
                else // 只要求较远。
                {
                    applyRsm = currDepth > 0.7;
                }
            }
            if (applyRsm) // 只有需要反弹的像素才采样阴影图。
            {
                gi = ogxGiRsm(currViewPos, currNormal, view, shadowDepth0, shadowDepth1, shadowColor0, shadowColor1,
                    radius, steps, falloff, shadowMapResolution, shadowBias, noise, useSolidShadow, leakFix, underwater); // 算一次反弹。
            }
            float materialIds = floor(texelFetch(materialTexture, texel, 0).b * 255.0); // 读材质编号。
            vec2 velocity = ogxGiCameraVelocity(local, currDepth, isDh, materialIds, view, disableHand, disablePlayer, handDepth, playerMaterial); // 屏幕位移。
            vec2 prevCoord = local - velocity; // 映射到上一帧坐标。
            vec2 clamped = clamp(prevCoord, vec2(0.0), vec2(1.0) - view.texel_size * 2.0); // 夹到画面内。
            if (ogxEqual(clamped, prevCoord)) // 历史坐标有效才做滤波。
            {
                vec2 prevTexelCoord = prevCoord * renderScale * view.screen_size - 0.5; // 换成历史纹素坐标。
                float currDist = min(-currViewPos.z, 1000.0); // 本帧到相机的距离，限长避免远处权重异常。
                vec3 cameraVelocity = ogxMatrixMulPoint(view.model_view, view.camera_position - view.previous_camera_position); // 相机速度转到视空间。
                float weightSum = 0.0; // 权重和。
                vec3 prevGi = ogxGiHistorySample(currNormal, currDist, cameraVelocity, prevTexelCoord, renderScale,
                    historyTexture, normalTexture, view.screen_size, weightSum); // 取上一帧加权历史反弹。
                gi = mix(gi, prevGi, 0.95 * weightSum); // 与历史混合。
            }
            prev = vec4(ogxLinearToCurve3(gi), 0.0); // 编码回历史格式。
        }
    }
    local.x -= 1.0; // 顶行左侧一格存法线与距离。
    if (ogxEqual(ogxSaturate(local), local)) // 只在有效范围内处理。
    {
        ivec2 texel = ivec2(floor(local * view.screen_size)); // 对应的屏幕纹素。
        float depth = texelFetch(depthTexture, texel, 0).x; // 不透明深度。
        bool isDh = false; // 远景标记。
        if (has_dh && useDhAo && depth == 1.0) // 天空像素改读远景深度。
        {
            depth = texelFetch(dhDepthTexture, texel, 0).x; // 远景深度。
            isDh = true; // 标记远景。
        }
        if (depth < 1.0) // 有几何才写历史数据。
        {
            vec3 normal = ogxDecodeNormal(texelFetch(normalTexture, texel, 0).xy); // 解法线。
            float dist = 1.0 / ((depth * 2.0 - 1.0) * view.projection_inverse[2][3] + view.projection_inverse[3][3]); // 深度换米制距离。
            if (isDh) // 远景换算。
            {
                dist = 1.0 / ((depth * 2.0 - 1.0) * view.dh_projection_inverse[2][3] + view.dh_projection_inverse[3][3]);
            }
            prev = vec4(normal * 0.5 + 0.5, dist * 0.001); // 法线压到零到一，距离缩小存进透明通道。
        }
        else // 天空像素没有有效历史。
        {
            prev = vec4(vec3(0.5), 0.0); // 写入中性值。
        }
    }
    return prev; // 返回本帧要写回历史图的数据。
}

// 七乘七邻域偏移按行列下标现算：x 从负三到三，y 同样，按行优先排列。
// 全局光空间滤波：在七乘七邻域里按法线与深度加权平均，抑制半分辨率带来的噪点。
vec3 ogxGiSpatialFilter(vec2 coord, float dist, vec3 normal, vec3 viewDir, OgxGiView view, sampler2D historyTexture, float renderScale)
{
    vec2 local = coord * renderScale; // 全局光分辨率下的坐标。
    float weights = 0.0; // 权重和。
    vec3 gi = vec3(0.0); // 累积的反弹颜色。
    float clampedDist = min(dist, 1000.0); // 距离限长。
    float b = clampedDist * 0.001 + 0.025; // 深度阈值里的中间量。
    float depthThreshold = min(0.1 + clampedDist * 0.05, 1.1) + ogxSaturate(1.0 - abs(dot(normal, viewDir)) / b) * 10.0; // 掠射角放宽深度阈值。
    vec2 border = vec2(renderScale) - view.texel_size * 2.0; // 边界。
    vec2 offsetScale = view.texel_size * 4.0 * renderScale; // 邻域步长。
    for (int i = 0; i < 49; i++) // 遍历四十九个邻点。
    {
        vec2 sampleCoord = clamp(local + vec2(float((i % 7) - 3), float((i / 7) - 3)) * offsetScale, vec2(0.0), border); // 采样坐标。
        float weight = length(vec2(float((i % 7) - 3), float((i / 7) - 3))); // 按到中心的距离算权重。
        weight = exp2(-weight * weight * 0.1); // 高斯权重。
        vec4 sampleData = textureLod(historyTexture, sampleCoord + vec2(renderScale, 0.0), 0.0); // 读历史法线深度。
        vec3 sampleNormal = sampleData.xyz * 2.0 - 1.0; // 还原法线。
        float normalWeight = abs(dot(normal, sampleNormal)); // 法线相近度。
        normalWeight = pow(normalWeight, 64.0); // 高次方只保留很接近的。
        float depthWeight = ogxSaturate(-abs(sampleData.w * 1000.0 - clampedDist) + depthThreshold); // 深度相近度。
        weight = weight * normalWeight * depthWeight + 1e-20; // 总权重，加极小值避免全零。
        gi += ogxCurveToLinear3(textureLod(historyTexture, sampleCoord, 0.0).rgb) * weight; // 累加解码后的反弹。
        weights += weight; // 累加权重。
    }
    return ogxLinearToCurve3(gi / weights); // 平均后编码返回。
}

#endif
