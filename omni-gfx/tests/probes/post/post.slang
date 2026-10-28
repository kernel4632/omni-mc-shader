/*
后期模块编译探针：调用泛光核、亮度曲线、暗角、颗粒、景深与测光统计。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入随像素变化，避免常量折叠掩盖类型问题；采样器只做类型检查。
*/
#include "../../../src/post/post.slang"

Sampler2D gProbeTexture; // 探针用的占位纹理，只为让采样器参数通过类型检查。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 coord = float2(t, position.y * 0.002); // 画面坐标。
    float2 texel = float2(1.0 / 1280.0, 1.0 / 720.0); // 纹素大小。
    float2 texSize = float2(1280.0, 720.0); // 画面尺寸。
    float3 bloom = ogxBloomDownsample(gProbeTexture, coord, texel); // 降采样。
    float3 blur = ogxAxialGaussianBlur(gProbeTexture, coord, float2(2.0, 1.0), 0.0, float2(0.25), float2(1.0, 0.0), 0.12, 6.0, texel); // 一维高斯。
    float4 bicubic = ogxBloomBicubic(gProbeTexture, coord, texSize); // 三次升采样。
    float3 curve = ogxLuminanceCurve(bloom, 0.1, 0.2); // 亮度曲线。
    curve += ogxGradeTarget(0.2, 0.1, 0.3); // 染色方向。
    curve *= ogxVignette(coord, 0.5, 1.0, 1.777); // 暗角。
    curve = ogxFilmGrain(curve, coord, t, 0.01); // 颗粒。
    curve = ogxDitherFloat(curve, coord, t, float3(6.0, 6.0, 5.0)); // 浮点尾数抖动。
    curve = ogxDitherFixed(curve, coord, t, 10.0); // 定点位数抖动。
    float coc = ogxCocRadius(10.0, 12.0, 0.5); // 弥散圆。
    float lens = ogxDofLensFactor(50.0, 2.8, 50.0, 2.8); // 镜头倍数。
    float linear = ogxDofLinearDepth(coord, gProbeTexture, gProbeTexture, float4x4(1.0), float4x4(1.0), false); // 米制深度。
    float spread = ogxDofCocSpread(coord, gProbeTexture, gProbeTexture, float4x4(1.0), float4x4(1.0), false, 10.0, 1.0, 1.0, 1.0, 8.0, 1.777, 8, float2(0.5)); // 弥散范围。
    float4 dof = ogxDepthOfField(coord, gProbeTexture, gProbeTexture, gProbeTexture, float4x4(1.0), float4x4(1.0), false,
        10.0, 1.0, 1.0, 1.0, 8.0, texel, 1.777, 8, false, 0.5, 1.0, 1.0, 1.0, false, float2(0.5)); // 景深。
    float3 motion = ogxMotionBlur(gProbeTexture, coord, int2(position.xy), coord, float2(0.01, 0.0), 180.0, 4, true); // 动态模糊。
    OgxExposureParams params; // 测光参数。
    params.screen_size = texSize; // 画面尺寸。
    params.pixel_size = texel; // 像素大小。
    params.lod = 3; // 块层级。
    params.luma_scale = 1.0; // 亮度系数。
    params.average = 0.2; // 整体亮度。
    params.mode = 0; // 默认测光。
    params.luminance_mode = 0; // 关闭亮度计权。
    params.luminance_strength = 1.0; // 计权强度。
    params.end_dimension = false; // 不是末地。
    params.nether = false; // 不是下界。
    params.cave_mode = false; // 不是洞穴模式。
    params.overworld = true; // 主世界。
    float exposure = ogxExposureTileAverage(gProbeTexture, params); // 加权平均亮度。
    float3 result = curve + blur + bicubic.rgb + motion + dof.rgb + float3(coc + lens + linear + spread + exposure, 0.0, 0.0); // 汇总输出。
    return float4(result, 1.0); // 有输出即可。
}
