/*
数学模块适配层：曲线、编码、材质、光线求交、噪声、双三次采样与矩阵工具已迁到生成库。
调用位置：任何需要纯数学函数的图形程序，以及 `shaders/gfx/` 内的其它适配层与 `shaders/rendering/`；
    算式只在 `omni-gfx/src/math.slang` 一份，本文件只保留旧名字、旧宏与转发。
可复制示例：`vec3 n = gfx_DecodeNormal(gfx_EncodeNormal(worldNormal));` 法线编码后再解回。
设计原因与取舍：函数名与参数顺序保持原样，几百个调用点无需改动，默认画面不会漂移；
    六个常用宏也保留原名，让旧代码继续可读；宏体直接接到生成库的函数上，不重复算式。
    切线基在库里用结构体返回，本适配层在这里组装成旧的 3×3 矩阵，调用点不用改。
*/
#ifndef GFX_MATH_INCLUDED
#define GFX_MATH_INCLUDED

// 迁移后的数学实现：常数、编码、材质、求交、噪声与采样。
#include "/omni-gfx/math.glsl"

// 旧常数名接到生成库的常量上。
#define GFX_PI OGX_PI // 圆周率。
#define GFX_HALF_PI OGX_HALF_PI // 半圆周率。
#define GFX_INV_PI OGX_INV_PI // 圆周率倒数。

// 把值夹到零到一，支持标量和向量。
#define gfx_saturate(x) ogxSaturate(x) // 实现在生成库。

// 位运算取符号，支持标量和向量。
#define gfx_fsign(x) ogxSign(x) // 实现在生成库。

// 位运算近似平方根，支持标量。
#define gfx_fsqrt(x) ogxFastSqrt(x) // 实现在生成库。

// 人眼亮度权重，和显示管线一致。
float gfx_math_luminance(vec3 c){ return ogxLuminance(c); } // 实现在生成库。

float gfx_remapSaturate(float x, float e0, float e1){ return ogxRemapSaturate(x, e0, e1); } // 实现在生成库。
float gfx_atan2(vec2 v){ return ogxAtan2(v); } // 实现在生成库。
float gfx_facos(float x){ return ogxFastAcos(x); } // 实现在生成库。
vec3 gfx_LinearToGamma(vec3 c){ return ogxLinearToGamma(c); } // 实现在生成库。
vec3 gfx_GammaToLinear(vec3 c){ return ogxGammaToLinear(c); } // 实现在生成库。
float gfx_LinearToCurve(float c){ return ogxLinearToCurve(c); } // 实现在生成库。
float gfx_CurveToLinear(float c){ return ogxCurveToLinear(c); } // 实现在生成库。
vec3 gfx_LinearToCurve(vec3 c){ return ogxLinearToCurve3(c); } // 实现在生成库。
vec3 gfx_CurveToLinear(vec3 c){ return ogxCurveToLinear3(c); } // 实现在生成库。
void gfx_DoNightEye(inout vec3 c){ ogxDoNightEye(c); } // 实现在生成库。
float gfx_Pack2x8(vec2 x){ return ogxPack2x8(x); } // 实现在生成库。
vec2 gfx_Unpack2x8(float x){ return ogxUnpack2x8(x); } // 实现在生成库。
float gfx_Pack2x16(vec2 x){ return ogxPack2x16(x); } // 实现在生成库。
vec2 gfx_Unpack2x16(float x){ return ogxUnpack2x16(x); } // 实现在生成库。

// 法线贴图解码：全黑或全白的贴图不是法线数据，退回朝外法线。
vec3 gfx_DecodeNormalTex(vec3 texNormal){ return ogxDecodeNormalTex(texNormal); } // 实现在生成库。

vec2 gfx_OctWrap(vec2 v){ return ogxOctWrap(v); } // 实现在生成库。
vec2 gfx_EncodeNormal(vec3 n){ return ogxEncodeNormal(n); } // 实现在生成库。
vec3 gfx_DecodeNormal(vec2 en){ return ogxDecodeNormal(en); } // 实现在生成库。

// 高光分布与菲涅尔：名字保留迭代版叫法，算式在生成库。
float gfx_D_Walter(float NdotH, float roughness){ return ogxDistributionGGX(NdotH, roughness); } // 实现在生成库。
float gfx_F_Schlick(float VdotH, float f0, float f90){ return ogxFresnelSchlick(VdotH, f0, f90); } // 实现在生成库。
float gfx_V_Schlick(float NdotL, float NdotV, float roughness){ return ogxVisibilitySchlick(NdotL, NdotV, roughness); } // 实现在生成库。
float gfx_Fd_Burley(vec3 n, vec3 v, vec3 l, float roughness){ return ogxDiffuseBurley(n, v, l, roughness); } // 实现在生成库。
float gfx_SpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0){ return ogxSpecularGGX(n, v, l, roughness, f0); } // 实现在生成库。

vec3 gfx_Blackbody(float temperature){ return ogxBlackbody(temperature); } // 实现在生成库。
vec3 gfx_RayPlaneIntersection(vec3 ori, vec3 dir, vec3 normal){ return ogxRayPlaneIntersection(ori, dir, normal); } // 实现在生成库。
vec2 gfx_RaySphereIntersection(vec3 ori, vec3 dir, float radius){ return ogxRaySphereIntersection(ori, dir, radius); } // 实现在生成库。
float gfx_RayleighPhaseFunction(float nu){ return ogxRayleighPhase(nu); } // 实现在生成库。
float gfx_MiePhaseFunction(float g, float nu){ return ogxMiePhase(g, nu); } // 实现在生成库。
float gfx_InterleavedGradientNoise(vec2 c){ return ogxInterleavedGradientNoise(c); } // 实现在生成库。
float gfx_bayer2(vec2 a){ return ogxBayer2(a); } // 实现在生成库。
float gfx_bayer4(vec2 a){ return ogxBayer4(a); } // 实现在生成库。
float gfx_bayer8(vec2 a){ return ogxBayer8(a); } // 实现在生成库。
float gfx_bayer64(vec2 a){ return ogxBayer64(a); } // 实现在生成库。

// 双三次采样与十六像素模糊：纹理与尺寸由调用方传入。
vec3 gfx_BicubicTexture(sampler2D texSampler, vec2 coord, vec2 texSize){ return ogxBicubicTexture(texSampler, coord, texSize); } // 实现在生成库。
vec4 gfx_BicubicBlurTexture(sampler2D texSampler, vec2 coord){ return ogxBicubicBlurTexture(texSampler, coord); } // 实现在生成库。

vec3 gfx_omniNormalize(vec3 vector){ return ogxNormalize(vector); } // 实现在生成库。
vec3 gfx_omniRgbToHsv(vec3 c){ return ogxRgbToHsv(c); } // 实现在生成库。

// 环带径向轮廓：四次方乘线性衰减，中心亮、边缘暗。
float gfx_pcurve(float x){ return ogxRadialCurve(x); } // 实现在生成库。

// 依次绕三个轴旋转后合成矩阵。
mat3 gfx_rotate_matrix(float x, float y, float z){ return ogxRotateMatrix(x, y, z); } // 实现在生成库。

// 行星曲率下沉：水平距离平方乘强度，模拟球面相对切面的高度亏损。
float gfx_planet_curvature_drop(vec2 horizontal, float amount){ return ogxPlanetCurvatureDrop(horizontal, amount); } // 实现在生成库。

// 空间扭曲：越靠近原点，光线方向越被拉向原点，模拟黑洞附近的引力弯曲。
void gfx_warp_space(inout vec3 eyevec, inout vec3 raypos){ ogxWarpSpace(eyevec, raypos); } // 实现在生成库。

// 由屏幕导数构造切线基：返回列向量为切线、副切线、法线的矩阵。
// 生成库用结构体返回三个方向，这里按旧顺序装回矩阵，调用点的列访问语义不变。
mat3 gfx_tangent_basis(vec3 dp1, vec3 dp2, vec2 duv1, vec2 duv2){
	OgxTangentBasis basis = ogxTangentBasis(dp1, dp2, duv1, duv2); // 三个方向一次算好。
	return mat3(basis.tangent, basis.bitangent, basis.normal); // 按列组装成旧矩阵。
}

#endif
