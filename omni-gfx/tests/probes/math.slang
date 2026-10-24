/*
数学模块编译探针：把每个公开函数至少调用一次，供 Slang 生成 SPIR-V 时做完整类型检查。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：
    探针不追求正确画面，只追求覆盖全部函数签名，因此输入用屏幕坐标构造。
    生成的 SPIR-V 是模块可编译的证据，不是可以直接运行的完整渲染管线。
*/
#include "../../src/math.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25;  // 随像素变化的输入，避免常量折叠掩盖类型问题。
    float2 uv = float2(t, position.y * 0.001);  // 二维输入用于编码和噪声函数。
    float3 n = normalize(float3(t, 0.3, 0.8));  // 一个合法单位法线。
    float3 v = normalize(float3(-0.2, 0.5, 0.9));  // 视线方向。
    float3 l = normalize(float3(0.4, 0.7, 0.1));  // 光线方向。
    float3 acc = float3(0.0);  // 累加所有结果，保证调用不会被当成无用代码提前删掉。

    acc += ogxSaturate(t) + ogxLuminance(n) + ogxSign(t) + ogxFastSqrt(t);  // 标量与亮度基础函数。
    acc += ogxRemapSaturate(t, 0.0, 1.0) + ogxAtan2(uv) + ogxFastAcos(t);  // 区间映射与三角函数近似。
    acc += ogxLinearToGamma(n) + ogxGammaToLinear(n) + ogxLinearToCurve(t) + ogxCurveToLinear(t);  // 伽马与曲线。
    acc += ogxLinearToCurve3(n) + ogxCurveToLinear3(n);  // 向量曲线。
    float packed8 = ogxPack2x8(uv);  // 八位打包。
    float packed16 = ogxPack2x16(uv);  // 十六位打包。
    acc += float3(ogxUnpack2x8(packed8), ogxUnpack2x16(packed16).x);  // 拆包结果。
    float2 enc = ogxEncodeNormal(n);  // 法线编码。
    acc += ogxDecodeNormal(enc) + ogxDecodeNormalTex(float3(t, 0.5, 1.0 - t));  // 两种法线解码。
    acc += ogxDistributionGGX(t, 0.4) * n;  // 高光分布。
    acc += ogxFresnelSchlick(t, 0.04, 1.0) * n + ogxVisibilitySchlick(t, 0.8, 0.4) * n;  // 菲涅尔与可见性。
    acc += ogxDiffuseBurley(n, v, l, 0.5) * n + ogxSpecularGGX(n, v, l, 0.4, 0.04) * n;  // 漫反射与高光。
    acc += ogxBlackbody(6500.0);  // 黑体色温。
    acc += ogxRayPlaneIntersection(float3(0.0, 1.0, 0.0), l, float3(0.0, 1.0, 0.0));  // 平面求交。
    acc += float3(ogxRaySphereIntersection(float3(0.0), l, 1.0), 0.0);  // 球求交。
    acc += ogxRayleighPhase(t) * n + ogxMiePhase(0.6, t) * n;  // 两种相函数。
    acc += ogxInterleavedGradientNoise(uv) + ogxBayer2(uv) + ogxBayer4(uv) + ogxBayer8(uv) + ogxBayer64(uv);  // 抖动。
    OgxTangentBasis basis = ogxTangentBasis(float3(1.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0));  // 切线基。
    acc += basis.tangent + basis.bitangent + basis.normal;  // 读取三个字段。
    float3 hsv = ogxRgbToHsv(n);  // 颜色转色相。
    acc += ogxRadialCurve(t) * n + ogxPlanetCurvatureDrop(uv, 1.0) * n;  // 径向轮廓与曲率。
    float3 warpedDirection = l;  // 空间扭曲就地修改方向与位置。
    float3 warpedPosition = float3(1.0, 2.0, 3.0);  // 远离原点，避免除零。
    ogxWarpSpace(warpedDirection, warpedPosition);  // 调用扭曲。
    acc += warpedDirection + hsv;  // 汇总剩余结果。

    return float4(acc, 1.0);  // 有输出即可，数值本身不参与测试。
}
