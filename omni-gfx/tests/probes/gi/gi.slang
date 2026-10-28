/*
全局光模块编译探针：调用多弹射遮蔽、视空间还原、地平线遮蔽、级联相机速度与空间滤波。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：输入用像素坐标构造，避免常量折叠掩盖类型问题；采样器版本的函数只做类型检查。
*/
#include "../../../src/gi/gi.slang"

Sampler2D gProbeTexture; // 探针用的占位纹理，只为让采样器参数通过类型检查。

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float2 coord = float2(t, position.y * 0.002); // 画面坐标。
    float4x4 identity = float4x4(1.0); // 单位矩阵。
    OgxGiView view; // 全局光参数。
    view.projection_inverse = identity; // 近景逆投影。
    view.previous_projection = identity; // 上一帧投影。
    view.model_view_inverse = identity; // 视空间转世界。
    view.previous_model_view = identity; // 上一帧世界转视空间。
    view.model_view = identity; // 本帧世界转视空间。
    view.shadow_view = identity; // 阴影相机视图。
    view.shadow_projection = identity; // 阴影相机投影。
    view.dh_projection_inverse = identity; // 远景逆投影。
    view.shadow_normal = float3x3(1.0); // 法线转换矩阵。
    view.camera_position = float3(0.0, 20.0, 0.0); // 相机位置。
    view.previous_camera_position = float3(0.0, 20.0, 1.0); // 上一帧相机位置。
    view.screen_size = float2(1280.0, 720.0); // 画面尺寸。
    view.texel_size = float2(1.0 / 1280.0, 1.0 / 720.0); // 纹素大小。
    OgxGtaoParams params; // 遮蔽参数。
    params.steps = 4.0; // 切片数。
    params.slice_steps = 6.0; // 每片步数。
    params.falloff_start = 0.5; // 衰减起点。
    params.max_sample_radius = 256.0; // 屏幕半径上限。
    params.world_radius = 3.0; // 世界半径。
    params.screen_radius = 24.0; // 屏幕半径。
    params.strength = 1.0; // 强度。
    params.radius_mode = 1; // 屏幕半径模式。
    params.has_dh = false; // 没有远景。
    params.dh_ao = false; // 远景不参与遮蔽。
    params.falloff_z_offset = false; // 默认衰减。
    float3 viewPos = ogxGiViewPos(coord, 0.5, identity); // 还原视空间位置。
    float3 viewPosDh = ogxGiViewPosDistant(coord, 0.5, identity); // 远景还原。
    float3 bounced = ogxAoMultiBounce(0.6, float3(0.4, 0.5, 0.3)); // 多弹射。
    float2 velocity = ogxGiCameraVelocity(coord, 0.5, false, 1.0, view, false, false, 0.1, 7.0); // 相机速度。
    float3 filtered = ogxGiSpatialFilter(coord, 10.0, float3(0.0, 1.0, 0.0), float3(0.0, 0.0, 1.0), view, gProbeTexture, 0.5); // 空间滤波。
    float3 result = viewPos + viewPosDh + bounced + float3(velocity, 0.0) + filtered; // 汇总输出。
    result += float3(params.strength, params.steps, params.falloff_start); // 参数也参与输出，避免整段被优化掉。
    return float4(result, 1.0); // 有输出即可。
}
