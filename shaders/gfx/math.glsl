/*
通用图形库数学模块：曲线、编码、材质、光线求交、噪声与双三次采样。
调用位置：任何需要纯数学函数的图形程序；本仓库由 `common/math.glsl` 转发调用。
可复制示例：
    vec3 n = gfx_DecodeNormal(gfx_EncodeNormal(worldNormal)); // 法线编码后再解回。
    vec3 c = gfx_Blackbody(6500.0); // 用色温生成颜色。
    float ao = gfx_remapSaturate(distance, 0.0, 1.0); // 把距离映射到零到一。
设计原因与取舍：
    只接收显式参数，不读取任何引擎状态；函数名统一 `gfx_` 前缀，避免和宿主重名。
    保留原程序的常数和写法，迁移只改名字与调用位置，保证画面不变。
*/
#ifndef GFX_MATH_INCLUDED
#define GFX_MATH_INCLUDED

#define GFX_PI 3.14159265359
#define GFX_HALF_PI 1.57079632679
#define GFX_INV_PI 0.31830988618

// 把值夹到零到一，支持标量和向量。
#define gfx_saturate(x) clamp(x, 0.0, 1.0)

// 人眼亮度权重，和显示管线一致。
float gfx_math_luminance(vec3 c){ return dot(c, vec3(0.2125, 0.7154, 0.0721)); }

// 位运算取符号，支持标量和向量。
#define gfx_fsign(x) uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3f800000u)

// 位运算近似平方根，支持标量和向量。
#define gfx_fsqrt(x) intBitsToFloat(0x1fbd1df5 + (floatBitsToInt(x) >> 1))

float gfx_remapSaturate(float x, float e0, float e1){
	return gfx_saturate((x - e0) / (e1 - e0)); // 先线性映射再夹紧。
}
float gfx_atan2(vec2 v){
	return v.x == 0.0 ?
		(1.0 - step(abs(v.y), 0.0)) * sign(v.y) * GFX_HALF_PI : // 竖直方向直接给正负半圆周率。
		atan(v.y / v.x) + step(v.x, 0.0) * sign(v.y) * GFX_PI; // 左半平面补一个圆周率。
}
float gfx_facos(float x){
	float ax = abs(x); // 先按绝对值算，最后按符号翻转。
	float res = -0.156583 * ax + GFX_HALF_PI; // 一次多项式近似。
	res *= gfx_fsqrt(1.0 - ax); // 乘近似平方根修正曲线形状。
	return x >= 0 ? res : GFX_PI - res; // 负数用对称关系得到结果。
}
vec3 gfx_LinearToGamma(vec3 c){
	return pow(c, vec3(1.0 / 2.2)); // 简化伽马，不是分段标准曲线。
}
vec3 gfx_GammaToLinear(vec3 c){
	return pow(c, vec3(2.2)); // 与上面互逆。
}
float gfx_LinearToCurve(float c){
	return pow(c, 0.25); // 四次方根。
}
float gfx_CurveToLinear(float c){
	c = c * c; // 先平方。
	return c * c; // 再平方得到四次方。
}
vec3 gfx_LinearToCurve(vec3 c){
	return pow(c, vec3(0.25)); // 每个通道取四次方根。
}
vec3 gfx_CurveToLinear(vec3 c){
	c = c * c; // 先平方。
	return c * c; // 再平方。
}
void gfx_DoNightEye(inout vec3 c){
	float luminance = gfx_math_luminance(c); // 原色亮度。
	c = mix(c, luminance * vec3(0.7771, 1.0038, 1.6190), vec3(0.5)); // 偏蓝亮度与原色各占一半。
}
float gfx_Pack2x8(vec2 x){
	uvec2 u = uvec2(x * 255.0); // 量化到八位整数。
	return float((u.x << 8u) | u.y) / 65535.0; // 高八位放第一个，低八位放第二个。
}
vec2 gfx_Unpack2x8(float x){
	uint u = uint(x * 65535.0); // 还原成十六位整数。
	return vec2(u >> 8u, u & 255u) / 255.0; // 拆出高低八位并归一化。
}
float gfx_Pack2x16(vec2 x){
	uvec2 u = uvec2(x * 65535.0); // 量化到十六位整数。
	return uintBitsToFloat((u.x << 16u) | u.y); // 直接把位当浮点存，读取方必须按位还原。
}
vec2 gfx_Unpack2x16(float x){
	uint u = floatBitsToUint(x); // 取回原始位。
	return vec2(u >> 16u, u & 65535u) / 65535.0; // 拆出高低十六位并归一化。
}
vec3 gfx_DecodeNormalTex(vec3 texNormal){
	vec3 normal = vec3(0.0, 0.0, 1.0); // 无效贴图时用的默认朝外法线。

	if (abs(texNormal.x + texNormal.y + texNormal.z - 1.5) < 1.488){ // 全黑或全白的贴图不是法线数据。
		normal.xy = texNormal.xy * 2.0 - 1.0; // 零到一转回负一到一。
		normal.xy = max(abs(normal.xy) - 1.0 / 255.0, 0.0) * sign(normal.xy); // 去掉八位量化留下的一格偏差，平面不会微微倾斜。
		normal.z = sqrt(1.0 - dot(normal.xy, normal.xy)); // 由单位长度推出第三个分量。
	}
	return normal; // 切线空间法线。
}
vec2 gfx_OctWrap(vec2 v) {
	return (1.0 - abs(v.yx)) * gfx_fsign(v.xy); // 交换分量并按符号放到对应象限。
}
vec2 gfx_EncodeNormal(vec3 n){
	n.xy /= (abs(n.x) + abs(n.y) + abs(n.z)); // 投影到八面体表面。
	n.xy = n.z >= 0.0 ? n.xy : gfx_OctWrap(n.xy); // 下半球折到外圈。

	return n.xy * 0.5 + 0.5; // 负一到一转成零到一。
}
vec3 gfx_DecodeNormal(vec2 en){
	vec2 n = en * 2.0 - 1.0; // 零到一转回负一到一。

	float nz = 1.0 - abs(n.x) - abs(n.y); // 八面体上的第三个分量。
	return normalize(vec3(nz >= 0 ? n : gfx_OctWrap(n), nz)); // 外圈翻回下半球后归一化。
}
float gfx_D_Walter(float NdotH, float roughness){
	float roughness2 = roughness * roughness; // 粗糙度平方。
	float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0; // 分母中间量。
	return roughness2 / (GFX_PI * k * k); // 分布值。
}
float gfx_F_Schlick(float VdotH, float f0, float f90){
	VdotH = 1.0 - VdotH; // 越接近掠射越大。
	float VdotH2 = VdotH * VdotH; // 平方。
	return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH; // 五次方插值。
}
float gfx_V_Schlick(float NdotL, float NdotV, float roughness){
	float k = roughness * 0.5; // 原程序取粗糙度一半。
	return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k)); // 入射与出射遮挡相乘。
}
float gfx_Fd_Burley(vec3 n, vec3 v, vec3 l, float roughness){
	vec3 h = normalize(v + l); // 半程向量。
	float LdotH = gfx_saturate(dot(l, h)); // 光与半程夹角。
	float NdotL = gfx_saturate(dot(n, l)); // 光照余弦。
	float NdotV = gfx_saturate(dot(n, v)); // 视线余弦。

	float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH; // 掠射端反射率。

	float lightScatter = gfx_F_Schlick(NdotL, 1.0, f90); // 入射方向散射。
	float viewScatter = gfx_F_Schlick(NdotV, 1.0, f90); // 出射方向散射。

	return NdotL * lightScatter * viewScatter * GFX_INV_PI; // 乘余弦并归一化能量。
}
float gfx_SpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0){
	vec3 h = normalize(v + l); // 半程向量。
	float NdotH = gfx_saturate(dot(n, h)); // 法线与半程夹角。
	float LdotH = gfx_saturate(dot(l, h)); // 光与半程夹角。
	float NdotL = gfx_saturate(dot(n, l)); // 光照余弦。
	float NdotV = gfx_saturate(dot(n, v)); // 视线余弦。

	float GGX = gfx_F_Schlick(LdotH, f0, 1.0); // 菲涅尔。
	GGX *= gfx_V_Schlick(NdotL, NdotV, roughness); // 乘可见性。
	GGX *= gfx_D_Walter(NdotH, roughness); // 乘分布。

	return GGX; // 高光强度。
}
vec3 gfx_Blackbody(float temperature){
	// 拟合来源：普朗克轨迹词条的分段三次多项式。
	const mat2x4 splineX = mat2x4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910,
								  -3.0258469e9,  2.1070479e6, 0.2226347e3, 0.240390); // 横坐标两段系数，以四千开分界。

	const mat3x4 splineY = mat3x4(-1.1063814, -1.34811020, 2.18555832, -0.20219683,
								  -0.9549476, -1.37418593, 2.09137015, -0.16748867,
								   3.0817580, -5.87338670, 3.75112997, -0.37001483); // 纵坐标三段系数。

	float rt = 1.0 / temperature; // 色温倒数。
	float rt2 = rt * rt; // 倒数平方。
	vec4 coeffX = vec4(rt2 * rt, rt2, rt, 1.0); // 三次多项式的各次项。

	float x = dot(coeffX, temperature < 4000.0 ? splineX[0] : splineX[1]); // 色度横坐标。
	float x2 = x * x; // 平方。
	vec4 coeffY = vec4(x2 * x, x2, x, 1.0); // 纵坐标多项式的各次项。

	float z = 1.0 / dot(coeffY, temperature < 2222.0 ? splineY[0] : temperature < 4000.0 ? splineY[1] : splineY[2]); // 纵坐标倒数。

	vec3 xyz = vec3(x * z, 1.0, z); // 亮度归一的颜色坐标。
	xyz.z -= xyz.x + 1.0; // 由色度推出第三个分量。

	const mat3 xyzToSrgb = mat3( 3.24097, -0.96924,  0.05563,
								-1.53738,  1.87597, -0.20398,
								-0.49861,  0.04156,  1.05697); // 转线性显示原色的矩阵。

	return max(xyzToSrgb * xyz, vec3(0.0)); // 去掉色域外的负值。
}
vec3 gfx_RayPlaneIntersection(vec3 ori, vec3 dir, vec3 normal){
	float rayPlaneAngle = dot(dir, normal); // 射线与平面法线的夹角余弦。

	float planeRayDist = 1e8; // 平行时的默认距离。
	vec3 intersectionPos = dir * planeRayDist; // 默认交点放到极远处。

	if (rayPlaneAngle > 0.0001 || rayPlaneAngle < -0.0001){ // 不平行才真正求交，避免除零。
		planeRayDist = dot(-ori, normal) / rayPlaneAngle; // 沿射线到平面的距离。
		intersectionPos = ori + dir * planeRayDist; // 交点位置。
	}

	return intersectionPos; // 交点。
}
vec2 gfx_RaySphereIntersection(vec3 ori, vec3 dir, float radius){
	float b = dot(ori, dir); // 二次方程一次项的一半。
	float c = -radius * radius + dot(ori, ori); // 常数项。
	float d = b * b - c; // 判别式。

	vec2 intersection = vec2(1e10, -1e10); // 无交点标记。

	if (d >= 0.0){ // 判别式非负才相交。
		d = sqrt(d); // 开方。
		intersection = vec2(-b - d, -b + d); // 进入与离开距离。
	}

	return intersection; // 两个距离。
}
float gfx_RayleighPhaseFunction(float nu) {
	return 0.059683104 * (nu * nu + 1.0); // 常数是十六分之三除以圆周率。
}
float gfx_MiePhaseFunction(float g, float nu) {
	float gg = g * g; // 不对称因子平方。
	float k = 0.1193662 * (1.0 - gg) / (2.0 + gg); // 归一化系数，常数是八分之三除以圆周率。
	return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5); // 康奈特-沙克形式。
}
float gfx_InterleavedGradientNoise(vec2 c){
	return fract(52.9829189 * fract(0.06711056 * c.x + 0.00583715 * c.y)); // 常数来自原始论文。
}
float gfx_bayer2(vec2 a) {
	a = floor(a); // 只看整数像素。

	return fract(dot(a, vec2(0.5, a.y * 0.75))); // 四个格子得到零、四分之一、二分之一、四分之三。
}
float gfx_bayer4  (vec2 a) { return gfx_bayer2 (0.5   * a) * 0.25     + gfx_bayer2(a); } // 四乘四拜尔矩阵。
float gfx_bayer8  (vec2 a) { return gfx_bayer4 (0.5   * a) * 0.25     + gfx_bayer2(a); } // 八乘八拜尔矩阵。
float gfx_bayer64 (vec2 a) { return gfx_bayer8 (0.125 * a) * 0.015625 + gfx_bayer8(a); } // 六十四乘六十四拜尔矩阵。
vec3 gfx_BicubicTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	vec2 texPixelSize = 1.0 / texSize; // 一个像素的坐标大小。
	coord = coord * texSize; // 换成像素坐标。

	vec2 p = floor(coord - 0.5) + 0.5; // 左下最近像素中心。
	vec2 f = coord - p; // 到该中心的小数偏移。
	vec2 f2 = f * f; // 偏移平方。
	vec2 f3 = f * f2; // 偏移立方。

	const float c = 0.5; // 卡特穆尔-罗姆张力。
	vec2 w0 =        -c  * f3 +  2.0 * c         * f2 - c * f; // 第一个像素权重。
	vec2 w1 =  (2.0 - c) * f3 - (3.0 - c)        * f2         + 1.0; // 第二个像素权重。
	vec2 w2 = -(2.0 - c) * f3 + (3.0 -  2.0 * c) * f2 + c * f; // 第三个像素权重。
	vec2 w3 =         c  * f3 -                c * f2; // 第四个像素权重。

	vec2 w12 = w1 + w2; // 中间两个像素合并成一次双线性采样。
	vec2 tc12 = texPixelSize * (p + w2 / w12); // 合并采样的位置。
	vec2 tc0 = texPixelSize * (p - 1.0); // 最左或最下像素位置。
	vec2 tc3 = texPixelSize * (p + 2.0); // 最右或最上像素位置。

	vec4 color = vec4(textureLod(texSampler, vec2(tc12.x, tc0.y ), 0.0).rgb, 1.0) * (w12.x * w0.y ) +
				 vec4(textureLod(texSampler, vec2(tc0.x,  tc12.y), 0.0).rgb, 1.0) * (w0.x  * w12.y) +
				 vec4(textureLod(texSampler, vec2(tc12.x, tc12.y), 0.0).rgb, 1.0) * (w12.x * w12.y) +
				 vec4(textureLod(texSampler, vec2(tc3.x,  tc12.y), 0.0).rgb, 1.0) * (w3.x  * w12.y) +
				 vec4(textureLod(texSampler, vec2(tc12.x, tc3.y ), 0.0).rgb, 1.0) * (w12.x * w3.y ); // 十字形五次采样，`a` 通道累计权重。
	return color.rgb / color.a; // 除以权重和，补偿省掉的四角。
}
vec4 gfx_BicubicBlurTexture(sampler2D texSampler, vec2 coord){
	const float texPixelSize = 1.0 / 64.0; // 噪声贴图一个像素的大小。
	coord = coord * 64.0 - 0.5; // 换成以像素中心为原点的坐标。

	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。

	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个三次样条权重。
	vec4 w1; // 两个方向的后两个三次样条权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。

	vec4 s = w0 + w1; // 左右两对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= texPixelSize; // 换回零到一坐标。

	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(noisetex, c.yw, 0.0), textureLod(noisetex, c.xw, 0.0), m.x),
			   mix(textureLod(noisetex, c.yz, 0.0), textureLod(noisetex, c.xz, 0.0), m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊。
}
vec3 gfx_omniNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }
vec3 gfx_omniRgbToHsv(vec3 c){
	const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0; // 极值组合的基向量，照 Eclipse。
	const float e = 1.0e-10; // 防止除零的极小量。
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g)); // 按蓝绿大小选中间通道。
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r)); // 再按红与最大值选主通道。
	float d = q.x - min(q.w, q.y); // 最大值与最小值之差就是饱和度分子。
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x); // 交回色相、饱和度、明度。
}

// 环带径向轮廓：四次方乘线性衰减，中心亮、边缘暗。
float gfx_pcurve(float x){
	float x2 = x * x; // 平方。
	return 12.207 * x2 * x2 * (1.0 - x); // 四次方乘线性衰减。
}

// 依次绕三个轴旋转后合成矩阵。
mat3 gfx_rotate_matrix(float x, float y, float z){
	mat3 matx = mat3(1.0, 0.0, 0.0, 0.0, cos(x), sin(x), 0.0, -sin(x), cos(x)); // 绕横轴。
	mat3 maty = mat3(cos(y), 0.0, -sin(y), 0.0, 1.0, 0.0, sin(y), 0.0, cos(y)); // 绕纵轴。
	mat3 matz = mat3(cos(z), sin(z), 0.0, -sin(z), cos(z), 0.0, 0.0, 0.0, 1.0); // 绕前后轴。
	return maty * matx * matz; // 三个旋转合成。
}

// 行星曲率下沉：水平距离平方乘强度，模拟球面相对切面的高度亏损。
float gfx_planet_curvature_drop(vec2 horizontal, float amount){
	float curvature = length(horizontal) / 128.0; // 水平距离除以一百二十八。
	return curvature * curvature * amount; // 平方后乘强度。
}

#endif
