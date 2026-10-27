/*
抗锯齿模块编译探针：调用颜色空间转换、历史裁剪、三次采样与时间重投影。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入随像素变化，避免常量折叠掩盖类型问题；采样器只做类型检查。
*/
#include "../../../src/antialias/antialias.slang"

Sampler2D gProbeTexture; // 探针用的占位纹理，只为让采样器参数通过类型检查。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 coord = float2(t, position.y * 0.002); // 画面坐标。
    float2 viewport = float2(1280.0, 720.0); // 画面尺寸。
    float4x4 identity = float4x4(1.0); // 单位矩阵。
    float3 color = ogxRgbToYCoCg(float3(t, 0.4, 0.8)); // 转亮度色差空间。
    color = ogxYCoCgToRgb(color); // 再换回来。
    color = ogxClipAabb(color, float3(0.1), color * 0.9, true); // 历史裁剪。
    float4 bicubic = ogxBicubicTexture4(gProbeTexture, coord, viewport); // 三次采样。
    float linear = ogxTaaLinearDepth(t, identity); // 深度换米制。
    float screen = ogxTaaScreenDepth(linear + 1.0, identity); // 换回屏幕深度。
    float reference; // 参考深度。
    float4 reprojected = ogxTaaReproject(coord, float3(0.01, 0.0, 0.0), t, gProbeTexture, gProbeTexture,
        viewport, int2(position.xy), identity, 1000.0, float2(0.0), 0.9, 1.0, 1e-4, false, false, true, false, false, false, reference); // 时间重投影。
    float3 result = color + bicubic.rgb + reprojected.rgb + float3(linear + screen, reference, 0.0); // 汇总输出。
    return float4(result, 1.0); // 有输出即可。
}
