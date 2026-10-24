#ifndef WORLD_SHARED_INCLUDED // 只引入一次，避免三个阶段重复定义同一批函数。
#define WORLD_SHARED_INCLUDED // 置上标记，后续再次引用直接跳过。
// 测试世界共用：把生成的通用库一次引入，并给出场景统一的太阳、云与雾参数。
// 调用位置：天空、地形与水面三个着色器都在文件开头引入本文件。
// 设计原因与取舍：参数只写一份，三个阶段的太阳颜色与云层位置不会互相错开。
// 数学：黑体、亮度与抖动。
#include "/omni-gfx/math.glsl"
// 噪声：地形颗粒与水波细节。
#include "/omni-gfx/noise.glsl"
// 大气：天空与空气透视。
#include "/omni-gfx/atmosphere.glsl"
// 云：体积云与云影。
#include "/omni-gfx/cloud.glsl"
// 水面：波法线与水面着色。
#include "/omni-gfx/water.glsl"
// 雾：低空体积雾。
#include "/omni-gfx/fog.glsl"

// 太阳颜色：五千八百开黑体，归一化亮度后由各阶段自己决定强度。
vec3 worldSunColor() // 返回只含色度的太阳颜色。
{
    vec3 color = ogxBlackbody(5800.0); // 黑体拟合给出偏暖的白。
    return color / max(ogxLuminance(color), 1e-4); // 只保留色度，亮度交给调用方。
}

// 场景云层：云量来自命令行参数，风随时间缓慢推动云团。
OgxCloudLayer worldCloudLayer(float time, float cover) // 返回本帧的云层参数。
{
    OgxCloudLayer layer = ogxCloudLayerDefault(); // 先取默认高度与密度。
    layer.coverage = cover; // 命令行可以调整云量。
    layer.wind = vec3(time * 0.0035, 0.0, time * 0.0012); // 每秒约三点五米的水平风。
    return layer; // 返回本帧使用的云层。
}

// 场景低空雾：风比云慢，雾团贴着地面流动。
OgxFog worldFog(float time) // 返回本帧的雾参数。
{
    OgxFog fog = ogxFogDefault(); // 先取默认密度与高度。
    fog.wind = vec3(time * 0.0040, 0.0, time * 0.0015); // 每秒约四米的水平风。
    return fog; // 返回本帧使用的雾。
}

#endif // 共用参数结束。
