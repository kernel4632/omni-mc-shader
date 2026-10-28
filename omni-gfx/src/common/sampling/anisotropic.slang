/*
Omni 通用图形库各向异性过滤模块：按屏幕导数构造椭圆核，沿长轴取多个样本。
调用位置：斜视地面、水面与任何需要保持贴图细节的地形取样；由 `/omni-gfx/common/sampling/anisotropic.glsl` 引入。
可复制示例：
    vec4 albedo = ogxSampleAnisotropic(tex, normals, specular, coord, duv1, duv2, atlasSize, 256.0, 4, true, true, true, true, normalTex, specularTex, materialAo); // 做各向异性过滤。
设计原因与取舍：
    导数只在片元阶段可用，因此本文件不并入基础采样模块；基础模块会被顶点与阴影程序引用。
    椭圆核、长轴步进与法线/材质加权保持参考实现，纹理和 atlas 尺寸全部显式传入。
    `useMaterialAo` 为真时按 labPBR 约定从法线贴图蓝通道取材质遮蔽，与 `surface` 模块的公式相同；
    这里不引用 `surface`，避免通用采样层反向依赖材质业务模块。
*/
#ifndef OGX_SAMPLING_ANISOTROPIC_INCLUDED
#define OGX_SAMPLING_ANISOTROPIC_INCLUDED

// 数学提供夹紧、矩阵列展开、相函数与光线求交。
#include "../math.slang"

// 各向异性采样：按屏幕导数构造椭圆核，沿长轴取多个样本做过滤，避免斜视时贴图糊成一片。
// `quality` 是每像素样本数，`normalSpecular` 为真时同时过滤法线与材质图。
float4 ogxSampleAnisotropic(Sampler2D tex, Sampler2D normals, Sampler2D specular, float2 coord, float2 duv1,
    float2 duv2, float2 atlasSize, float textureResolution, int quality, bool normalSpecular, bool useNormalMap,
    bool useSpecularMap, bool useMaterialAo, inout float3 normalTex, inout float4 specularTex, out float materialAo)
{
    materialAo = 1.0; // 默认不压暗底色；调用方没有法线图时保持一。
    float2 atlasTiles = atlasSize / textureResolution; // 一张贴图在 atlas 里占几格。
    float2 tilesCoord = coord * atlasTiles; // 换到格坐标。
    float2x2 qd = inverse(float2x2(ddx(tilesCoord), ddy(tilesCoord))); // 屏幕导数矩阵的逆。
    qd = transpose(qd) * qd; // 逆矩阵的转置乘自身，得到椭圆核。
    float d = determinant(qd); // 行列式。
    float t = (qd[0][0] + qd[1][1]) * 0.5; // 迹的一半。
    float D = sqrt(abs(t * t - d)); // 判别式。
    float V = t - D; // 短轴。
    float v = t + D; // 长轴。
    float2 A = float2(-qd[0][1], qd[0][0] - V); // 长轴方向。
    A *= rsqrt(V * dot(A, A) + 1e-20); // 归一化，避免除零。
    float lod = log2(rsqrt(v) * textureResolution); // 采样层级由长轴决定。
    float steps = float(quality); // 样本数。
    float rSteps = 1.0 / float(quality); // 样本数倒数。
    A *= rSteps; // 每步的偏移。
    float4 albedoSample = float4(0.0); // 颜色累加。
    float3 normalSample = float3(0.0); // 法线累加。
    float4 specularSample = float4(0.0); // 材质累加。
    float2 tilesBaseCoord = floor(tilesCoord); // 当前格。
    for (float i = 0.5 - steps * 0.5; i < steps * 0.5; i++) // 沿长轴逐样本。
    {
        float2 sampleCoord = i * A; // 当前偏移。
        sampleCoord = (tilesBaseCoord + fract(tilesCoord + sampleCoord)) / atlasTiles; // 回到贴图坐标并保持在格内。
        float4 sampleAlbedo = tex.SampleLevel(sampleCoord, lod); // 取颜色。
        albedoSample += float4(sampleAlbedo.rgb * sampleAlbedo.a, sampleAlbedo.a); // 预乘透明度累加。
        if (normalSpecular) // 同时过滤法线与材质。
        {
            if (useNormalMap) normalSample += normals.SampleLevel(sampleCoord, lod).rgb * sampleAlbedo.a; // 法线按透明度加权。
            if (useSpecularMap) specularSample += specular.SampleLevel(sampleCoord, lod) * sampleAlbedo.a; // 材质按透明度加权。
        }
    }
    float weights = 1.0 / albedoSample.a; // 透明度总和倒数。
    float3 rawNormal = normalSample * weights; // 归一化后的贴图法线，蓝通道等会儿还要取遮蔽。
    if (normalSpecular) // 写回法线与材质。
    {
        if (useNormalMap) normalTex = ogxDecodeNormalTex(rawNormal); // 解出切线法线。
        if (useSpecularMap) specularTex = specularSample * weights; // 材质取加权平均。
    }
    else // 不过滤附加图时用梯度采样保持层级正确。
    {
        // 两个分支都加大括号：严格对照会在选项关闭时静态裁掉整段，
        // 没有大括号的 `if` 无法被裁掉，会把本该关闭的两次采样算进来。
        if (useNormalMap)
        {
            rawNormal = normals.SampleGrad(coord, duv1, duv2).rgb;
            normalTex = ogxDecodeNormalTex(rawNormal); // 法线用梯度采样。
        }
        if (useSpecularMap)
        {
            specularTex = specular.SampleGrad(coord, duv1, duv2); // 材质用梯度采样。
        }
    }
    if (useNormalMap && useMaterialAo) materialAo = rawNormal.b * 0.5 + 0.5; // labPBR 遮蔽存蓝通道，映射到零点五到一。
    return float4(albedoSample.rgb * weights, tex.SampleLevel(coord, 0.0).a); // 颜色取平均，透明度保留原值。
}

#endif
