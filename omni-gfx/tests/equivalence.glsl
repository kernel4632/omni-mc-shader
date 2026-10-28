#version 330 core
/*
适配层与生成库的 GPU 对照测试：同一像素、同一输入，分别走冻结的参考副本和直接调用 `ogx_` 函数。
调用位置：`omni-gfx/build.py test-gpu` 运行；不属于 Minecraft 光影入口。
设计原因与取舍：
    参考副本是 `tests/reference/` 里从旧库冻结的纯 GLSL，只用于数值对照，不进入光影包。
    第二次迁移后生产代码已经删除 `gfx_` 转发层，本测试验证生成库与迁移前算式仍然一致。
    两边在同一驱动、同一精度下计算，输出写两张浮点附件，Python 侧直接读回，差异不会被八位量化掩盖。
    贴图过滤函数需要显式纹理尺寸，参考副本与生成库都从同一张噪声纹理取像素。
*/
#include "reference/math.glsl"
#include "reference/color.glsl"
#include "reference/sampling.glsl"
#include "/omni-gfx/common/math.glsl"
#include "/omni-gfx/common/color.glsl"
#include "/omni-gfx/common/sampling.glsl"

uniform int uCase;  // 当前比较的用例编号，由 Python 逐个绘制。
uniform sampler2D uNoise;  // 两边共用的六十四像素噪声纹理。
layout(location = 0) out vec4 oldOut;  // 旧库结果，四个通道各自对应一个被比较的分量。
layout(location = 1) out vec4 newOut;  // 新库结果，通道顺序与旧库完全一致。

// 旧库的暗视觉函数就地修改颜色，包一层返回新值，方便放进比较表达式。
vec3 gfxPurkinjeResult(vec3 color)
{
    gfx_purkinje(color, 0.5, 1.0);  // 调用旧库的就地修改版本。
    return color;  // 返回修改后的颜色。
}

// 旧库的空间扭曲同样就地修改方向与位置，包一层返回可比较的结果。
vec3 gfxWarpResult(vec2 uv, vec3 color)
{
    vec3 direction = normalize(vec3(uv, 0.8));  // 初始方向。
    vec3 position = vec3(1.0, 0.5, 0.25);  // 初始位置。
    gfx_warp_space(direction, position);  // 调用旧库的扭曲。
    return direction * 0.5 + position * 0.1 + color * 0.0;  // 组合成可比较的向量。
}

// 新库的暗视觉函数，包装方式与旧库完全一致。
vec3 ogxPurkinjeResult(vec3 color)
{
    color = ogxPurkinje(color, 0.5, 1.0);  // 新库返回新值。
    return color;  // 返回修改后的颜色。
}

// 新库的空间扭曲包装。
vec3 ogxWarpResult(vec2 uv, vec3 color)
{
    vec3 direction = normalize(vec3(uv, 0.8));  // 与旧库相同的初始方向。
    vec3 position = vec3(1.0, 0.5, 0.25);  // 与旧库相同的初始位置。
    ogxWarpSpace(direction, position);  // 调用新库的扭曲。
    return direction * 0.5 + position * 0.1 + color * 0.0;  // 与旧库相同的组合方式。
}

// 旧库一侧：按编号选择函数，输入由像素坐标构造。
vec4 oldValue(int testCase, vec2 uv, vec3 c, vec3 n, vec3 v, vec3 l)
{
    if (testCase == 0) return vec4(gfx_math_luminance(c), gfx_atan2(uv), gfx_facos(uv.x), gfx_fsign(uv.x - 0.5));  // 亮度与三角近似。
    if (testCase == 1) return vec4(gfx_fsqrt(uv.x + 0.1), gfx_remapSaturate(uv.y, 0.0, 1.0), gfx_LinearToCurve(c.x), gfx_CurveToLinear(c.y));  // 平方根与曲线。
    if (testCase == 2) return vec4(gfx_Pack2x8(uv), gfx_Unpack2x8(gfx_Pack2x8(uv)), 0.0);  // 八位打包与拆包。
    if (testCase == 3) return vec4(gfx_Unpack2x16(gfx_Pack2x16(uv)), 0.0, 0.0);  // 十六位打包与拆包。
    if (testCase == 4) return vec4(gfx_EncodeNormal(n), gfx_DecodeNormal(gfx_EncodeNormal(n)).xy);  // 法线八面体编码。
    if (testCase == 5) return vec4(gfx_DecodeNormalTex(vec3(uv, 1.0 - uv.x)), gfx_D_Walter(uv.x, 0.4));  // 贴图法线与 GGX 分布。
    if (testCase == 6) return vec4(gfx_F_Schlick(uv.x, 0.04, 1.0), gfx_V_Schlick(uv.x, uv.y, 0.5), gfx_Fd_Burley(n, v, l, 0.5), gfx_SpecularGGX(n, v, l, 0.4, 0.04));  // 高光四项。
    if (testCase == 7) return vec4(gfx_Blackbody(3000.0), 1.0);  // 低色温黑体。
    if (testCase == 8) return vec4(gfx_Blackbody(6500.0), 1.0);  // 日光色温黑体。
    if (testCase == 9) return vec4(gfx_Blackbody(12000.0), 1.0);  // 高色温黑体。
    if (testCase == 10) return vec4(gfx_RayPlaneIntersection(vec3(0.0, 1.0, 0.0), l, vec3(0.0, 1.0, 0.0)), gfx_RaySphereIntersection(vec3(0.2, 0.4, 0.6), l, 1.0).x);  // 求交。
    if (testCase == 11) return vec4(gfx_RayleighPhaseFunction(uv.x), gfx_MiePhaseFunction(0.6, uv.y), gfx_InterleavedGradientNoise(uv * 64.0), gfx_bayer2(uv * 32.0));  // 相函数与噪声。
    if (testCase == 12) return vec4(gfx_bayer4(uv * 32.0), gfx_bayer8(uv * 16.0), gfx_bayer64(uv * 8.0), gfx_pcurve(uv.x));  // 拜尔与径向曲线。
    if (testCase == 13) return vec4(gfx_omniRgbToHsv(c), gfx_hsv_to_rgb(gfx_omniRgbToHsv(c)).x);  // 颜色转色相。
    if (testCase == 14) return vec4(gfx_hsv_to_rgb(gfx_omniRgbToHsv(c)).yz, gfx_pcurve(uv.x), gfx_black_bar(uv, 1.7, 2.35));  // 色相还原、径向曲线与黑边。
    if (testCase == 15) return vec4(gfx_tangent_basis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0))[0].x, gfx_tangent_basis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0))[1].y, gfx_tangent_basis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0))[2].z, 0.0);  // 切线基三个方向。
    if (testCase == 16) return vec4(gfxWarpResult(uv, c), 1.0);  // 空间扭曲的辅助结果。
    if (testCase == 17) return vec4(gfx_LinearToGamma(c).x, gfx_GammaToLinear(c));  // 数学模块伽马。
    if (testCase == 18) return vec4(gfx_linear_to_gamma(c).x, gfx_gamma_to_linear(c));  // 颜色模块伽马。
    if (testCase == 19) return vec4(gfx_aces(c, true), 1.0);  // ACES 带阿布尼校正。
    if (testCase == 20) return vec4(gfx_aces(c, false), 1.0);  // ACES 不带校正。
    if (testCase == 21) return vec4(gfx_agx(c, 13.0, true), 1.0);  // AgX 带校正。
    if (testCase == 22) return vec4(gfx_agx(c, 13.0, false), 1.0);  // AgX 不带校正。
    if (testCase == 23) return vec4(gfx_tonemap_none(c).x, gfx_advanced_color(c, 1.0, 0.0, 1.0, 1.0));  // 无压缩与高级调色。
    if (testCase == 24) return vec4(gfxPurkinjeResult(c).x, gfx_white_balance(c, vec3(1.0, 0.98, 0.95)));  // 暗视觉、白平衡与黑边。
    if (testCase == 25) return vec4(gfx_blue_noise(uNoise, ivec2(gl_FragCoord.xy)), gfx_blue_noise_temporal(uNoise, ivec2(gl_FragCoord.xy), 7).x, gfx_bayer_temporal(ivec2(gl_FragCoord.xy), 11));  // 采样模块。
    return vec4(0.0);  // 未定义编号返回零，Python 侧会检查编号范围。
}

// 新库一侧：与旧库逐项对应，名字只改前缀与必要的数字后缀。
vec4 newValue(int testCase, vec2 uv, vec3 c, vec3 n, vec3 v, vec3 l)
{
    if (testCase == 0) return vec4(ogxLuminance(c), ogxAtan2(uv), ogxFastAcos(uv.x), ogxSign(uv.x - 0.5));  // 亮度与三角近似。
    if (testCase == 1) return vec4(ogxFastSqrt(uv.x + 0.1), ogxRemapSaturate(uv.y, 0.0, 1.0), ogxLinearToCurve(c.x), ogxCurveToLinear(c.y));  // 平方根与曲线。
    if (testCase == 2) return vec4(ogxPack2x8(uv), ogxUnpack2x8(ogxPack2x8(uv)), 0.0);  // 八位打包与拆包。
    if (testCase == 3) return vec4(ogxUnpack2x16(ogxPack2x16(uv)), 0.0, 0.0);  // 十六位打包与拆包。
    if (testCase == 4) return vec4(ogxEncodeNormal(n), ogxDecodeNormal(ogxEncodeNormal(n)).xy);  // 法线八面体编码。
    if (testCase == 5) return vec4(ogxDecodeNormalTex(vec3(uv, 1.0 - uv.x)), ogxDistributionGGX(uv.x, 0.4));  // 贴图法线与 GGX 分布。
    if (testCase == 6) return vec4(ogxFresnelSchlick(uv.x, 0.04, 1.0), ogxVisibilitySchlick(uv.x, uv.y, 0.5), ogxDiffuseBurley(n, v, l, 0.5), ogxSpecularGGX(n, v, l, 0.4, 0.04));  // 高光四项。
    if (testCase == 7) return vec4(ogxBlackbody(3000.0), 1.0);  // 低色温黑体。
    if (testCase == 8) return vec4(ogxBlackbody(6500.0), 1.0);  // 日光色温黑体。
    if (testCase == 9) return vec4(ogxBlackbody(12000.0), 1.0);  // 高色温黑体。
    if (testCase == 10) return vec4(ogxRayPlaneIntersection(vec3(0.0, 1.0, 0.0), l, vec3(0.0, 1.0, 0.0)), ogxRaySphereIntersection(vec3(0.2, 0.4, 0.6), l, 1.0).x);  // 求交。
    if (testCase == 11) return vec4(ogxRayleighPhase(uv.x), ogxMiePhase(0.6, uv.y), ogxInterleavedGradientNoise(uv * 64.0), ogxBayer2(uv * 32.0));  // 相函数与噪声。
    if (testCase == 12) return vec4(ogxBayer4(uv * 32.0), ogxBayer8(uv * 16.0), ogxBayer64(uv * 8.0), ogxRadialCurve(uv.x));  // 拜尔与径向曲线。
    if (testCase == 13) return vec4(ogxRgbToHsv(c), ogxHsvToRgb(ogxRgbToHsv(c)).x);  // 颜色转色相。
    if (testCase == 14) return vec4(ogxHsvToRgb(ogxRgbToHsv(c)).yz, ogxRadialCurve(uv.x), ogxBlackBar(uv, 1.7, 2.35));  // 色相还原、径向曲线与黑边。
    if (testCase == 15) return vec4(ogxTangentBasis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0)).tangent.x, ogxTangentBasis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0)).bitangent.y, ogxTangentBasis(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0)).normal.z, 0.0);  // 切线基三个方向。
    if (testCase == 16) return vec4(ogxWarpResult(uv, c), 1.0);  // 空间扭曲的辅助结果。
    if (testCase == 17) return vec4(ogxLinearToGamma(c).x, ogxGammaToLinear(c));  // 数学模块伽马。
    if (testCase == 18) return vec4(ogxLinearToGamma(c).x, ogxGammaToLinear(c));  // 颜色模块伽马。
    if (testCase == 19) return vec4(ogxAces(c, true), 1.0);  // ACES 带阿布尼校正。
    if (testCase == 20) return vec4(ogxAces(c, false), 1.0);  // ACES 不带校正。
    if (testCase == 21) return vec4(ogxAgx(c, 13.0, true), 1.0);  // AgX 带校正。
    if (testCase == 22) return vec4(ogxAgx(c, 13.0, false), 1.0);  // AgX 不带校正。
    if (testCase == 23) return vec4(ogxLinearToGamma(c).x, ogxAdvancedColor(c, 1.0, 0.0, 1.0, 1.0));  // 旧无压缩的伽马编码与高级调色。
    if (testCase == 24) return vec4(ogxPurkinjeResult(c).x, ogxWhiteBalance(c, vec3(1.0, 0.98, 0.95)));  // 暗视觉、白平衡与黑边。
    if (testCase == 25) return vec4(ogxBlueNoise(uNoise, ivec2(gl_FragCoord.xy)), ogxBlueNoiseTemporal(uNoise, ivec2(gl_FragCoord.xy), 7).x, ogxBayerTemporal(ivec2(gl_FragCoord.xy), 11));  // 采样模块。
    return vec4(0.0);  // 未定义编号返回零。
}

void main()
{
    vec2 uv = fract(gl_FragCoord.xy / 256.0);  // 测试固定使用两百五十六像素见方，坐标限制在零到一。
    vec3 c = vec3(uv.x * 0.8 + 0.05, uv.y * 0.6 + 0.1, 0.25);  // 一个不越界的线性颜色。
    vec3 n = normalize(vec3(uv * 2.0 - 1.0, 0.75));  // 单位法线。
    vec3 v = normalize(vec3(-0.3, 0.4, 0.9));  // 观察方向。
    vec3 l = normalize(vec3(0.5, 0.7, -0.2));  // 光线方向。
    oldOut = oldValue(uCase, uv, c, n, v, l);  // 旧库结果。
    newOut = newValue(uCase, uv, c, n, v, l);  // 新库结果。
}
