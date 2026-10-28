/*
Omni 通用图形库全局光模块：地平线遮蔽、反射阴影图反弹、历史重投影、时间与空间滤波。
调用位置：任何需要屏幕空间全局光或环境遮蔽的程序；Minecraft 光影由 `/omni-gfx/gi/gi.glsl` 引入。
可复制示例：
    `float ao = ogxGroundTruthAo(viewPos, viewDir, normal, coord, aspect, depthTex, dhTex, projection, projectionInverse, dhInverse, params, noise);` 一帧的地平线遮蔽。
    `vec3 bounce = ogxAoMultiBounce(ao, albedo);` 给遮蔽补一次多弹射。
    `vec3 filtered = ogxGiSpatialFilter(coord, dist, normal, viewDir, view, history, 0.5);` 七乘七空间滤波。
设计原因与取舍：
    纹理、矩阵、相机位置与选项全部由调用方传入，库不读取引擎状态；`OgxGiView` 把同一帧的
    相机与屏幕参数打包，避免每个函数重复十几项。算法与迁移前的 GLSL 原型逐项一致，
    迁移只改名字和语法，默认画面因此不变；地平线遮蔽的采样仍由调用方负责，这里只做纯数学。
*/
#ifndef OGX_GI_INCLUDED
#define OGX_GI_INCLUDED

// 饱和、快速反余弦、曲线编码与噪声来自数学模块；阴影投影来自阴影模块。
#include "../common/math.slang"
// 阴影提供屏幕空间阴影、PCSS 与级联选择。
#include "../shadow/shadow.slang"
// 采样提供白噪声、蓝噪声与低差异序列。
#include "../common/sampling.slang"

// 一帧全局光需要的相机、投影与屏幕参数；字段名保持普通图形术语，不绑定任何宿主。
struct OgxGiView
{
    float4x4 projection_inverse; // 近景逆投影。
    float4x4 previous_projection; // 上一帧投影。
    float4x4 model_view_inverse; // 视空间转世界。
    float4x4 previous_model_view; // 上一帧世界转视空间。
    float4x4 model_view; // 本帧世界转视空间。
    float4x4 shadow_view; // 阴影相机视图。
    float4x4 shadow_projection; // 阴影相机投影。
    float4x4 dh_projection_inverse; // 远景逆投影；没有远景时填近景值占位。
    float3x3 shadow_normal; // 法线从世界转到阴影相机。
    float3 camera_position; // 本帧相机世界位置。
    float3 previous_camera_position; // 上一帧相机世界位置。
    float2 screen_size; // 画面像素尺寸。
    float2 texel_size; // 一个像素的屏幕坐标大小。
};

// 反射阴影图入口的提前声明：时间滤波在子文件里先调用它，定义放在主文件末尾。
float3 ogxGiRsm(float3 viewPos, float3 normal, OgxGiView view,
    Sampler2D shadowDepth0, Sampler2D shadowDepth1, Sampler2D shadowColor0, Sampler2D shadowColor1,
    float radius, int steps, float falloff, float shadowMapResolution, float shadowBias, float2 noise,
    bool useSolidShadow, bool leakFix, bool underwater);

// 地平线遮蔽、反射阴影图与 GTAO，具体实现在子文件。
#include "gi/ao.slang"
// 相机速度与时间滤波，具体实现在子文件。
#include "gi/temporal.slang"
// 空间滤波与降噪，具体实现在子文件。
#include "gi/spatial.slang"

float3 ogxGiRsm(float3 viewPos, float3 normal, OgxGiView view,
    Sampler2D shadowDepth0, Sampler2D shadowDepth1, Sampler2D shadowColor0, Sampler2D shadowColor1,
    float radius, int steps, float falloff, float shadowMapResolution, float shadowBias, float2 noise,
    bool useSolidShadow, bool leakFix, bool underwater)
{
    float3 worldPos = ogxMatrixMulPoint(view.model_view_inverse, viewPos) + ogxMatrixTranslation(view.model_view_inverse); // 视空间位置换世界空间。
    float3 shadowPosition = ogxShadowScreenPos(worldPos, view.shadow_view, view.shadow_projection); // 投到阴影图。
    float3 shadow_normal = ogxMatrix3MulPoint(view.shadow_normal, normal); // 法线转到阴影相机空间；三乘三矩阵在调用方已经组合好。
    float pixelOffset = radius * view.shadow_projection[0][0]; // 搜索半径换成阴影图像素。
    float zScale = 1.0 / view.shadow_projection[0][0]; // 阴影深度的缩放系数。
    float angle = noise.x * OGX_TAU; // 起始旋转角。
    float2 rot = float2(cos(angle), sin(angle)); // 起始方向。
    float rSteps = 1.0 / float(steps); // 采样次数倒数。
    float3 rsm = float3(0.0); // 累积的反弹颜色。
    for (int i = 0; i < steps; i++) // 螺旋逐点采样。
    {
        rot = float2(cos(OGX_GOLDEN_ANGLE) * rot.x + sin(OGX_GOLDEN_ANGLE) * rot.y,
                     -sin(OGX_GOLDEN_ANGLE) * rot.x + cos(OGX_GOLDEN_ANGLE) * rot.y); // 每步旋转黄金角。
        float r = (float(i) + noise.y) * rSteps; // 归一化半径。
        float2 offset = rot * r * pixelOffset; // 屏幕偏移。
        float2 offsetPosition = shadowPosition.xy + offset; // 采样点的阴影图坐标。
        float2 sampleCoord = ogxDistortShadowPos(offsetPosition, shadowBias); // 还原压缩后的坐标。
        int2 sampleTexel = int2(shadowMapResolution * sampleCoord); // 换成纹素。
        float sampleDepth; // 按显卡能力选深度图；写成分支，严格对照才能按布尔参数裁掉另一张。
        if (useSolidShadow) { sampleDepth = shadowDepth1.Load(int3(sampleTexel, 0)).x; }
        else { sampleDepth = shadowDepth0.Load(int3(sampleTexel, 0)).x; }
        if (sampleDepth == 0.0 || sampleDepth >= 1.0) // 没有几何或超出范围就跳过。
        {
            continue;
        }
        float3 sampleVector = float3(offsetPosition, sampleDepth) - shadowPosition; // 采样点相对当前点。
        sampleVector *= float3(zScale, zScale, -zScale * 2.0); // 修正到统一的深度尺度。
        float3 sampleDir = normalize(sampleVector); // 采样方向。
        float nDotV = dot(sampleDir, shadow_normal); // 当前点法线与采样方向的夹角余弦。
        if (nDotV <= 0.0) // 背对采样点不接收。
        {
            continue;
        }
        float4 sampleData = shadowColor1.Load(int3(sampleTexel, 0)); // 读阴影图里的法线与天光。
        float3 sampleNormal = sampleData.rgb * 2.0 - 1.0; // 还原采样点法线。
        float snDotV = dot(-sampleDir, sampleNormal) * 1.004 - 0.004; // 采样点法线与入射方向的夹角余弦，留一点余量。
        if (snDotV < 0.0) // 背对方向不发光。
        {
            continue;
        }
        float3 sampleAlbedo = ogxGammaToLinear(shadowColor0.Load(int3(sampleTexel, 0)).rgb); // 采样点底色转线性。
        sampleVector.z *= 1.5; // 深度方向加权，避免细长表面贡献过大。
        float sampleDist = length(sampleVector); // 采样距离。
        float distFalloff = pow(sampleDist + 0.035, -falloff) * ogxFastSqrt(1.0 - r); // 距离衰减与中心加权。
        float lightMask = leakFix ? ogxSaturate(sampleData.a * 15.0 + float(underwater)) : 1.0; // 主世界只给接到天光或水里的点补光。
        rsm += sampleAlbedo * (nDotV * snDotV * distFalloff * lightMask); // 累加一份反弹。
    }
    rsm *= rSteps * radius * 0.1; // 平均并按半径缩放。
    return rsm; // 返回反弹颜色。
}

float3 ogxAoMultiBounce(float ao, float3 albedo)
{
    float3 a = 2.0404 * albedo - 0.3324; // 一次项系数。
    float3 b = -4.7951 * albedo + 0.6417; // 二次项系数。
    float3 c = 2.7552 * albedo + 0.6903; // 三次项系数。
    return max(float3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}

#endif
