/*
Slang 探针兼容函数：补 Slang 没有、但模块仍按 GLSL 写法使用的内建函数。
调用位置：`sampling/anisotropic` 与 `gi/indirect` 的探针，在引入模块前包含本文件。
设计原因与取舍：
    这些函数只服务于 SPIR-V 编译验证，不进入生成的 GLSL；生成的 GLSL 继续用
    GLSL 自己的 `inverse` 与 `textureSize`。兼容层不改模块算式与常数。
*/
float2x2 inverse(float2x2 m) // 二阶矩阵求逆：伴随矩阵除以行列式。
{
    float d = m[0][0] * m[1][1] - m[0][1] * m[1][0]; // 行列式。
    return float2x2(m[1][1], -m[0][1], -m[1][0], m[0][0]) / d; // 伴随矩阵除以行列式。
}

float2 textureSize(Sampler2D tex, int level) // 取二维纹理的宽高，替代 GLSL 的 textureSize。
{
    uint width = 0u; // 宽度由纹理接口写回。
    uint height = 0u; // 高度由纹理接口写回。
    tex.GetDimensions(width, height); // Slang 用 GetDimensions 取尺寸。
    return float2(width, height); // 返回与 GLSL 相同的浮点宽高。
}
