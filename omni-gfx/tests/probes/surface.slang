/*
表面模块编译探针：调用天光与方块光曲线、材质法线与遮蔽、火把光与自发光。
调用位置：`omni-gfx/build.py spirv` 逐模块编译；探针只验证，不进入光影包。
设计原因与取舍：全部输入由屏幕坐标构造，覆盖两类自发光模式与下界分支。
*/
Sampler2D probeTex2D; // 全局纹理声明：探针只需要类型，不需要真实绑定。
#include "../../src/surface.slang"

[shader("fragment")]
float4 probeMain(float4 position : SV_Position) : SV_Target
{
    float t = position.x * 0.001 + 0.25; // 随像素变化的输入。
    float3 normalTex = float3(t, 1.0 - t, 0.8); // 法线贴图颜色。
    float3 albedo = float3(0.8, 0.2, 0.1); // 贴图底色。
    float3 c = float3(ogxCurveBlockLightSky(t) + ogxCurveBlockLightTorch(t)); // 两条光曲线。
    c += ogxMaterialNormal(normalTex, true, 1.0).xyz; // 法线与遮蔽。
    c += ogxMaterialNormalScale(float3(0.0, 0.0, 1.0), t); // 法线倍率。
    c += ogxBlockLight(t, float3(1.0), 0.5, float3(1.0, 0.7, 0.4), 1.0, true); // 火把光。
    c += ogxTextureEmissive(albedo, t, 0.5, true, float3(1.0, 0.7, 0.4), 1.0, 1.0, 2, false); // 自发光相加模式。
    c += ogxOreEmission(albedo) + ogxTrimEmission(albedo); // 矿石与纹饰发光。
    return float4(c, 1.0); // 有输出即可。
}
