#ifndef WORLD_SHARED_INCLUDED // 只引入一次，避免多个阶段重复定义同一批函数。
#define WORLD_SHARED_INCLUDED // 置上标记，后续再次引用直接跳过。
// 测试世界共用：把生成的通用库一次引入，并给出场景统一的太阳、云与雾参数。
// 调用位置：天空、累积、合成、地形与水面五个阶段都在文件开头引入本文件。
// 设计原因与取舍：太阳颜色、云层与雾只写一份，各阶段的色温与云位置不会互相错开；
// 像素到世界方向的换算也只写一份，升采样与时间累积才能逐像素对齐，不会出现接缝。
// 数学：黑体、亮度、抖动与矩阵。
#include "/omni-gfx/math.glsl"
// 采样：蓝噪声与按帧平移的抖动。
#include "/omni-gfx/sampling.glsl"
// 噪声：云、雾与水面细节。
#include "/omni-gfx/noise.glsl"
// 大气：天空与空气透视。
#include "/omni-gfx/atmosphere.glsl"
// 云：体积云与云影。
#include "/omni-gfx/cloud.glsl"
// 水面：波法线与水面着色。
#include "/omni-gfx/water.glsl"
// 雾：低空体积雾。
#include "/omni-gfx/fog.glsl"
// 阴影：PCSS 软阴影与级联选择。
#include "/omni-gfx/shadow.glsl"
// 全局光：地平线遮蔽与多弹射。
#include "/omni-gfx/gi.glsl"
// 反射：屏幕空间追踪与九点降噪。
#include "/omni-gfx/reflection.glsl"
// 后期：泛光核、亮度曲线与颗粒。
#include "/omni-gfx/post.glsl"
// 抗锯齿：时间重投影与历史裁剪。
#include "/omni-gfx/antialias.glsl"
// 颜色：色调映射曲线。
#include "/omni-gfx/color.glsl"

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

// 场景大气：地球常数，只把整体太阳强度降到与测试世界曝光相配的量级。
// 天空、空气透视与水面雾必须用同一组常数，否则远处海面会比天空亮一截，接缝立刻可见。
OgxAtmosphere worldAtmosphere() // 返回本场景使用的大气参数。
{
    OgxAtmosphere air = ogxAtmosphereEarth(); // 先取库里的地球常数。
    air.sunIntensity = 8.0; // 比库默认值低，留出高光余量，画面不容易整片过曝。
    air.mieScattering = vec3(0.25e-3, 0.25e-3, 0.25e-3); // 气溶胶淡一些，地平线保持淡蓝而不是一条白带。
    air.mieG = 0.45; // 前向散射略收，太阳附近的白晕不会糊成一片。
    return air; // 返回可直接使用的参数。
}

// 像素坐标到世界方向：主画面、时间累积与双边升采样共用，三者才能逐像素对齐。
// `pixel` 用片元坐标而不是归一化坐标，是因为半分辨率阶段也要用同一套公式。
vec3 worldRayDirection(vec2 pixel, vec2 resolution, vec3 forward, vec3 right, vec3 up, float tanHalfFov, float aspect)
{
    vec2 ndc = pixel / resolution * 2.0 - 1.0; // 零到一映射到负一到一。
    return normalize(forward + right * ndc.x * tanHalfFov * aspect + up * ndc.y * tanHalfFov); // 针孔相机光线。
}

// 立方体贴图六个面的方向：`uv` 是负一到一的局部坐标。
vec3 worldCubeDirection(int face, vec2 uv)
{
    if (face == 0) return vec3(1.0, -uv.y, -uv.x); // 正 X 面。
    if (face == 1) return vec3(-1.0, -uv.y, uv.x); // 负 X 面。
    if (face == 2) return vec3(uv.x, 1.0, uv.y); // 正 Y 面。
    if (face == 3) return vec3(uv.x, -1.0, -uv.y); // 负 Y 面。
    if (face == 4) return vec3(uv.x, -uv.y, 1.0); // 正 Z 面。
    return vec3(-uv.x, -uv.y, -1.0); // 负 Z 面。
}

#endif // 共用参数结束。
