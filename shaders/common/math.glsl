/*
共用纯计算：照 iterationT `Lib/Utilities.glsl` 一比一移植，外加全管线共用的内部常数。
调用位置：每个绘制主体在 `common/uniforms.glsl` 之后引入；效果文件也可以直接引入。
可复制示例：
    `vec3 c = CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb) * MAIN_OUTPUT_FACTOR;`  读回场景线性亮度
    `compositeOutput1 = vec4(LinearToCurve(color / MAIN_OUTPUT_FACTOR), 1.0);`              按管线单位写回
    `vec3 n = DecodeNormal(data.rg);`                                                      解八面体法线
设计原因与取舍：
    函数名、宏名、常数、写法全部保持原名原样，各效果文件按原名互相调用，便于逐行对照原程序。
    `PI`、`saturate` 这类宏和函数名不带前缀，所以别的文件不能再定义同名宏。
    原文件开头的版本号宏只是菜单装饰，按移植合同不移植。
    `MAIN_OUTPUT_FACTOR` 是整条管线的亮度单位：中间画面存 `LinearToCurve(x / 2048)`，最终阶段再乘回。
    单位链路任何一处不一致都会整片过曝，所以这些常数只在这里定义一次。
*/
#ifndef OMNI_MATH_INCLUDED // 只引入一次，避免宏和函数重复定义。
#define OMNI_MATH_INCLUDED // 置上标记。

// 本文件的 `BicubicBlurTexture` 直接读 `noisetex`，所以自己先引入加载器输入声明。
// 为什么放在文件内部而不是要求调用方先引入：引用顺序写错时只会报“未声明的标识符”，
// 很难一眼看出是顺序问题；这里自己保证一次，效果文件怎么排都能编译。
#include "/common/uniforms.glsl"

// --- 内部常数：原 `Settings.glsl` 里不进菜单的共用常数 ---
#define MAIN_OUTPUT_FACTOR 2048.0 // 场景亮度单位：中间画面颜色先除以它再做四次方根编码。
#define EXPOSURE_OUTPUT_FACTOR 128.0 // 曝光统计用的亮度单位。
#define ANIMATION_SPEED 1.0 // 植物摆动等动画速度倍率。
#define WATER_REFRACT_IOR 1.2 // 水面折射率，比真实水的一点三三小，避免折射拉伸过大。
#define CAUSTICS_TEX_RESOLUTION 500.0 // 焦散法线方块边长，单位像素，七号画面左下角。

// --- 数学常数：圆周率相关与两个低差异序列用的无理数 ---
#define PI           3.14159265359 // 圆周率。
#define hPI          1.57079632679 // 半个圆周率。
#define TAU          6.28318530718 // 两倍圆周率。
#define rPI          0.31830988618 // 圆周率的倒数。
#define goldenRatio  1.61803398875 // 黄金比，时间噪声逐帧偏移用。
#define plasticRatio 1.32471795724 // 塑料数，二维低差异序列用。
#define goldenAngle  2.39996322973 // 黄金角，螺旋采样用。

// --- 常用小工具宏 ---
// 原程序还有 `min3`，本项目没有一处调用，按“不留无人使用的代码”删掉，其余保持原名原样。
#define max3(a, b, c)                   max(a, max(b, c)) // 三个数取最大。
#define min4(a, b, c, d)                min(min(a, b), min(c, d)) // 四个数取最小。
#define max4(a, b, c, d)                max(max(a, b), max(c, d)) // 四个数取最大。
#define min5(a, b, c, d, e)             min(a, min(b, min(c, min(d, e)))) // 五个数取最小。
#define max5(a, b, c, d, e)             max(a, max(b, max(c, max(d, e)))) // 五个数取最大。
#define min9(a, b, c, d, e, f, g, h, i) min(a, min(b, min(c, min(d, min(e, min(f, min(g, min(h, i)))))))) // 九个数取最小，三乘三邻域用。
#define max9(a, b, c, d, e, f, g, h, i) max(a, max(b, max(c, max(d, max(e, max(f, max(g, max(h, i)))))))) // 九个数取最大。
#define saturate(x)                     clamp(x, 0.0, 1.0) // 夹到零到一。
#define curve(x)                        x * x * (3.0 - 2.0 * x) // 平滑曲线；原样不加括号，调用方须自己给参数加括号。
#define Luminance(c)                    dot(c, vec3(0.2125, 0.7154, 0.0721)) // 感知亮度，权重照原程序。
#define fsign(x)                        uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) | 0x3f800000u) // 位运算取正负一，零也按正号。
#define fsqrt(x)                        intBitsToFloat(0x1fbd1df5 + (floatBitsToInt(x) >> 1)) // 位运算近似平方根，速度快、精度低。

// --- 区间重映射 ---
// 把落在 `e0` 到 `e1` 的值映射到零到一并夹紧。
float remapSaturate(float x, float e0, float e1){
	return saturate((x - e0) / (e1 - e0)); // 先线性映射再夹紧。
}

// --- 角度近似 ---
// 两参数反正切：返回从横轴到向量的角度，横分量为零时单独处理避免除零。
float atan2(vec2 v){
	return v.x == 0.0 ?
		(1.0 - step(abs(v.y), 0.0)) * sign(v.y) * hPI : // 竖直方向直接给正负半圆周率。
		atan(v.y / v.x) + step(v.x, 0.0) * sign(v.y) * PI; // 左半平面补一个圆周率。
}

// 快速反余弦近似：一次多项式乘近似平方根，精度够光照用。
float facos(float x){
	float ax = abs(x); // 先按绝对值算，最后按符号翻转。
	float res = -0.156583 * ax + hPI; // 一次多项式近似。
	res *= fsqrt(1.0 - ax); // 乘近似平方根修正曲线形状。
	return x >= 0 ? res : PI - res; // 负数用对称关系得到结果。
}

// --- 颜色曲线：伽马与管线四次方根编码 ---
// 线性转伽马空间，指数二点二。
vec3 LinearToGamma(vec3 c){
	return pow(c, vec3(1.0 / 2.2)); // 简化伽马，不是分段标准曲线。
}

// 伽马空间转线性，贴图颜色进入光照前用。
vec3 GammaToLinear(vec3 c){
	return pow(c, vec3(2.2)); // 与上面互逆。
}

// 管线编码：取四次方根，让十六位定点画面在暗部有足够精度。
float LinearToCurve(float c){
	return pow(c, 0.25); // 四次方根。
}

// 管线解码：四次方，用两次平方代替幂函数更快。
float CurveToLinear(float c){
	c = c * c; // 先平方。
	return c * c; // 再平方得到四次方。
}

// 三维版本的管线编码。
vec3 LinearToCurve(vec3 c){
	return pow(c, vec3(0.25)); // 每个通道取四次方根。
}

// 三维版本的管线解码。
vec3 CurveToLinear(vec3 c){
	c = c * c; // 先平方。
	return c * c; // 再平方。
}

// 夜视色偏：暗处颜色向偏蓝的亮度混一半，模拟人眼暗视觉。
void DoNightEye(inout vec3 c){
	float luminance = Luminance(c); // 原色亮度。
	c = mix(c, luminance * vec3(0.7771, 1.0038, 1.6190), vec3(0.5)); // 偏蓝亮度与原色各占一半。
}

// --- 打包：把两个数塞进一个通道 ---
// 两个零到一的数各取八位，拼进一个十六位通道。
float Pack2x8(vec2 x){
	uvec2 u = uvec2(x * 255.0); // 量化到八位整数。
	return float((u.x << 8u) | u.y) / 65535.0; // 高八位放第一个，低八位放第二个。
}

// 从十六位通道拆回两个八位数。
vec2 Unpack2x8(float x){
	uint u = uint(x * 65535.0); // 还原成十六位整数。
	return vec2(u >> 8u, u & 255u) / 255.0; // 拆出高低八位并归一化。
}

// 两个零到一的数各取十六位，按位拼进一个三十二位浮点通道。
float Pack2x16(vec2 x){
	uvec2 u = uvec2(x * 65535.0); // 量化到十六位整数。
	return uintBitsToFloat((u.x << 16u) | u.y); // 直接把位当浮点存，读取方必须按位还原。
}

// 从三十二位浮点通道按位拆回两个数。
vec2 Unpack2x16(float x){
	uint u = floatBitsToUint(x); // 取回原始位。
	return vec2(u >> 16u, u & 65535u) / 65535.0; // 拆出高低十六位并归一化。
}

// --- 法线编码 ---
// 解码法线贴图：三通道和接近一点五才认为是有效法线，否则按朝外法线处理。
vec3 DecodeNormalTex(vec3 texNormal){
	vec3 normal = vec3(0.0, 0.0, 1.0); // 无效贴图时用的默认朝外法线。

	if (abs(texNormal.x + texNormal.y + texNormal.z - 1.5) < 1.488){ // 全黑或全白的贴图不是法线数据。
		normal.xy = texNormal.xy * 2.0 - 1.0; // 零到一转回负一到一。
		normal.xy = max(abs(normal.xy) - 1.0 / 255.0, 0.0) * sign(normal.xy); // 去掉八位量化留下的一格偏差，平面不会微微倾斜。
		normal.z = sqrt(1.0 - dot(normal.xy, normal.xy)); // 由单位长度推出第三个分量。
	}
	return normal; // 切线空间法线。
}

// 八面体编码的折叠：把下半球翻到外圈。
vec2 OctWrap(vec2 v) {
	return (1.0 - abs(v.yx)) * fsign(v.xy); // 交换分量并按符号放到对应象限。
}

// 单位法线压成两个零到一的数，存进画面的两个通道。
vec2 EncodeNormal(vec3 n){
	n.xy /= (abs(n.x) + abs(n.y) + abs(n.z)); // 投影到八面体表面。
	n.xy = n.z >= 0.0 ? n.xy : OctWrap(n.xy); // 下半球折到外圈。

	return n.xy * 0.5 + 0.5; // 负一到一转成零到一。
}

// 从两个通道解回单位法线，与上面互逆。
vec3 DecodeNormal(vec2 en){
	vec2 n = en * 2.0 - 1.0; // 零到一转回负一到一。

	float nz = 1.0 - abs(n.x) - abs(n.y); // 八面体上的第三个分量。
	return normalize(vec3(nz >= 0 ? n : OctWrap(n), nz)); // 外圈翻回下半球后归一化。
}

// --- 光照模型 ---
// 法线分布：微表面朝向半程向量的比例，粗糙度越大高光越散。
float D_Walter(float NdotH, float roughness){
	float roughness2 = roughness * roughness; // 粗糙度平方。
	float k = NdotH * NdotH * (roughness2 - 1.0) + 1.0; // 分母中间量。
	return roughness2 / (PI * k * k); // 分布值。
}

// 菲涅尔近似：掠射角反射更强，五次方曲线。
float F_Schlick(float VdotH, float f0, float f90){
	VdotH = 1.0 - VdotH; // 越接近掠射越大。
	float VdotH2 = VdotH * VdotH; // 平方。
	return f0 + (f90 - f0) * VdotH2 * VdotH2 * VdotH; // 五次方插值。
}

// 可见性项：微表面互相遮挡的比例，已经乘了入射余弦。
float V_Schlick(float NdotL, float NdotV, float roughness){
	float k = roughness * 0.5; // 原程序取粗糙度一半。
	return NdotL / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k)); // 入射与出射遮挡相乘。
}

// 漫反射：迪士尼模型，粗糙表面在掠射角更亮。
float Fd_Burley(vec3 n, vec3 v, vec3 l, float roughness){
	vec3 h = normalize(v + l); // 半程向量。
	float LdotH = saturate(dot(l, h)); // 光与半程夹角。
	float NdotL = saturate(dot(n, l)); // 光照余弦。
	float NdotV = saturate(dot(n, v)); // 视线余弦。

	float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH; // 掠射端反射率。

	float lightScatter = F_Schlick(NdotL, 1.0, f90); // 入射方向散射。
	float viewScatter = F_Schlick(NdotV, 1.0, f90); // 出射方向散射。

	return NdotL * lightScatter * viewScatter * rPI; // 乘余弦并归一化能量。
}

// 高光：菲涅尔、可见性、分布三项相乘。
float SpecularGGX(vec3 n, vec3 v, vec3 l, float roughness, float f0){
	vec3 h = normalize(v + l); // 半程向量。
	float NdotH = saturate(dot(n, h)); // 法线与半程夹角。
	float LdotH = saturate(dot(l, h)); // 光与半程夹角。
	float NdotL = saturate(dot(n, l)); // 光照余弦。
	float NdotV = saturate(dot(n, v)); // 视线余弦。

	float GGX = F_Schlick(LdotH, f0, 1.0); // 菲涅尔。
	GGX *= V_Schlick(NdotL, NdotV, roughness); // 乘可见性。
	GGX *= D_Walter(NdotH, roughness); // 乘分布。

	return GGX; // 高光强度。
}

// --- 黑体颜色：按色温给出光源颜色，火把色温选项用 ---
// 普朗克轨迹的分段多项式拟合，先求色度坐标再转线性显示颜色。
vec3 Blackbody(float temperature){
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

// --- 射线求交 ---
// 射线与过原点的平面求交；几乎平行时返回极远处的点。
vec3 RayPlaneIntersection(vec3 ori, vec3 dir, vec3 normal){
	float rayPlaneAngle = dot(dir, normal); // 射线与平面法线的夹角余弦。

	float planeRayDist = 1e8; // 平行时的默认距离。
	vec3 intersectionPos = dir * planeRayDist; // 默认交点放到极远处。

	if (rayPlaneAngle > 0.0001 || rayPlaneAngle < -0.0001){ // 不平行才真正求交，避免除零。
		planeRayDist = dot(-ori, normal) / rayPlaneAngle; // 沿射线到平面的距离。
		intersectionPos = ori + dir * planeRayDist; // 交点位置。
	}

	return intersectionPos; // 交点。
}

// 射线与球心在原点的球求交，返回进出两个距离；不相交时返回近大远小的无效值。
vec2 RaySphereIntersection(vec3 ori, vec3 dir, float radius){
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

// --- 散射相位函数 ---
// 瑞利相位：小粒子散射，前后对称。
float RayleighPhaseFunction(float nu) {
	return 0.059683104 * (nu * nu + 1.0); // 常数是十六分之三除以圆周率。
}

// 米氏相位：大粒子散射，`g` 越大越偏向前方。
float MiePhaseFunction(float g, float nu) {
	float gg = g * g; // 不对称因子平方。
	float k = 0.1193662 * (1.0 - gg) / (2.0 + gg); // 归一化系数，常数是八分之三除以圆周率。
	return k * (1.0 + nu * nu) * pow(1.0 + gg - 2.0 * g * nu, -1.5); // 康奈特-沙克形式。
}

// --- 抖动噪声 ---
// 交错梯度噪声：按像素位置给出均匀分布的伪随机数。
float InterleavedGradientNoise(vec2 c){
	return fract(52.9829189 * fract(0.06711056 * c.x + 0.00583715 * c.y)); // 常数来自原始论文。
}

// 二乘二拜尔矩阵：下面更大的矩阵由它递归组合。
float bayer2(vec2 a) {
	a = floor(a); // 只看整数像素。

	return fract(dot(a, vec2(0.5, a.y * 0.75))); // 四个格子得到零、四分之一、二分之一、四分之三。
}

float bayer4  (vec2 a) { return bayer2 (0.5   * a) * 0.25     + bayer2(a); } // 四乘四拜尔矩阵。
float bayer8  (vec2 a) { return bayer4 (0.5   * a) * 0.25     + bayer2(a); } // 八乘八拜尔矩阵。
float bayer64 (vec2 a) { return bayer8 (0.125 * a) * 0.015625 + bayer8(a); } // 六十四乘六十四拜尔矩阵。

// --- 三次采样：原程序在两种时间抗锯齿里各写一份且逐字相同，按移植合同合并到这里一份 ---
// 五次采样近似卡特穆尔-罗姆三次插值，放大历史画面时比双线性更锐利。
// 为什么只采五次：四角的权重很小，省掉后画面差别看不出，采样数从九次降到五次。
vec3 BicubicTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
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

// --- 噪声贴图三次模糊：原程序地形顶点与阴影顶点各写一份且逐字相同，合并到这里一份 ---
// 调用前提：`common/uniforms.glsl` 已引入，函数固定读取六十四像素的 `noisetex`，`texSampler` 参数只为保持原签名。
// 泛光版与云影版参数和返回类型不同，分别留在 `effects/color/bloom.glsl` 与 `effects/cloud/cloud.glsl`，见移植合同偏离记录。
vec4 BicubicBlurTexture(sampler2D texSampler, vec2 coord){
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

// --- Omni 额外函数：原程序没有，保留文件仍在使用 ---
// 安全归一化：长度为零时普通归一化会得到无穷，光传播体积计算阶段用它算天体方向。
vec3 omniNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }
// 颜色转色相、饱和度、明度：体积光染色与矿石/纹饰自发光都要拆出这三个量，来源 Eclipse `lib/hsv.glsl`。
// 为什么放共用文件：两处以上效果（体积光、自发光矿石/纹饰）都要用，复制一份会与别处不一致。
vec3 omniRgbToHsv(vec3 c){
	const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0; // 极值组合的基向量，照 Eclipse。
	const float e = 1.0e-10; // 防止除零的极小量。
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g)); // 按蓝绿大小选中间通道。
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r)); // 再按红与最大值选主通道。
	float d = q.x - min(q.w, q.y); // 最大值与最小值之差就是饱和度分子。
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x); // 交回色相、饱和度、明度。
}
#endif // 文件守卫结束。
