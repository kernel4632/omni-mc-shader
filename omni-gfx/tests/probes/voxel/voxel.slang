/*
体素模块编译探针：调用方块分类、半透明染色、面上着色与完整的三维逐格追踪。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：
    追踪需要两张三维纹理：整数方块编号图与颜色光照图。两张的句柄都必须真的声明出来，
    否则“整数三维纹理取格”这条路径根本不会被编译到，探针就成了空壳。
    Slang 没有 GLSL 的无符号纹理名，用等价的整数三维纹理类型补一个别名；
    这一步只补名字，不改模块里的算式与常数。
    输入用屏幕坐标构造，不追求画面正确，只要求类型、分支与取格写法全部走一遍。
*/
typealias Usampler3D = Texture3D<uint4>; // 与 GLSL 的 usampler3D 等价：四通道无符号三维纹理。

Usampler3D probeVoxelId; // 方块编号图，整数三维纹理，追踪的主数据。
Sampler3D probeVoxelColor; // 颜色与打包光照图。

#include "../../../src/voxel/voxel.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    uint id = uint(position.x) & 15u; // 随便取一个方块编号，把分类分支都走到。
    float3 albedo = float3(t, 0.5, 1.0 - t); // 方块底色。
    float3 normal = normalize(float3(t - 0.5, 0.4, 0.9)); // 体素面法线。
    float3 tint = ogxVoxelTranslucentTint(id, albedo); // 半透明染色。
    float3 shaded = ogxVoxelShade(albedo, normal, 0.75, albedo, albedo * 0.5, albedo * 2.0, normal, t); // 面上着色。
    float3 origin = float3(0.0, 0.0, 0.0); // 相机相对世界起点。
    float3 hitPosition; // 命中点由函数带回。
    float4 traced = ogxVoxelReflection(origin, normal, float3(0.0, 0.0, 1.0), float3(0.5), 96,
        probeVoxelId, probeVoxelColor, albedo, albedo * 0.5, albedo * 2.0, -normal, 64.0, t, hitPosition); // 完整追踪。
    float4 inside = ogxVoxelReflection(origin, -normal, normal, float3(0.5), 96,
        probeVoxelId, probeVoxelColor, albedo, albedo * 0.5, albedo * 2.0, -normal, 64.0, t, hitPosition); // 朝内侧的提前返回。
    float inRange = ogxVoxelInside(int3(int(position.x), 0, 0), 96) ? 1.0 : 0.0; // 下标范围判断。
    float kinds = (ogxVoxelIsTranslucent(id) ? 1.0 : 0.0) + (ogxVoxelIsPlant(id) ? 1.0 : 0.0) + (ogxVoxelIsIron(id) ? 0.5 : 0.0); // 三种分类。
    return float4(shaded + tint + traced.rgb + traced.a + inside.a + hitPosition + float3(inRange, kinds, 0.0), 1.0); // 有输出即可。
}
