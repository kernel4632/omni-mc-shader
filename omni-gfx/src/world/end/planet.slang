// 末地行星子文件：用钱德拉塞卡近似与 Lambert 曲线给行星表面着色。
// 调用位置：由 `world/end.slang` 内联；需要复现 iterationT 行星 BRDF 的程序调用 `ogxPlanetShading`。
// 设计原因与取舍：只接收反照率、法线与方向；行星本体的求交与光环在 `planet` 模块，这里只保留着色。
// 可复制示例：`float3 c = ogxPlanetShading(albedo, normal, eyeDir, lightDir, 0.0);`

// iterationT 行星 BRDF：用 Chandrasekhar H 函数与 Lambert 曲线近似行星表面。
float3 ogxPlanetShading(float3 albedo, float3 normal, float3 eyeDir, float3 lightDir, float s)
{
    float NdotL = dot(normal, lightDir); // 光线与法线。
    float NdotV = dot(normal, eyeDir); // 视线与法线。
    albedo *= ogxCurve01(ogxSaturate(NdotL)); // 参考实现的曲线。
    float3 color = albedo * ogxChandrasekharH(albedo, NdotL) * ogxChandrasekharH(albedo, NdotV) / (4.0 * OGX_PI * (NdotL + NdotV)); // 双向反射。
    return ogxSaturate(color); // 夹到合法范围。
}
