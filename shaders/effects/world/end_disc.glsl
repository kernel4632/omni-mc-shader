/*
末地吸积盘：沿视线在黑洞附近步进，累加盘的颜色，附空间扭曲、云状分形噪声与旋转矩阵。
来源：iterationT `Lib/IndividualFounctions/EndSky.glsl` 一比一移植，原程序在此处标注了出处网址
  `www.shadertoy.com/view/lstSRS`，按合同保留来源注释与写法。
职责：`RotateMatrix`、`WarpSpace`、`EndCalculate3DNoise`、`CalculateCloudFBM`、`pcurve` 是辅助计算，
  `BlackHole_AccretionDisc_Stars` 画天空版吸积盘并叠星空，`BlackHole_AccretionDisc_Reflection` 是步数更少的反射版。
调用位置：由 `effects/world/end.glsl` 引入；合成零号调用天空版，`ComputeFakeSkyReflectionEnd` 调用反射版。
可复制示例：`BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector);`
调用前提：由 `effects/world/end.glsl` 引入，且已先引入 `effects/world/end_sky.glsl`（提供 `EndCalculateStars`，
  它内部复用 `effects/sky/sky.glsl` 的 `CalculateStars`，所以两者都要先就位）；
  `noisetex`、`frameTimeCounter`、`Blackbody`、`BlueNoiseTemporal`、`InterleavedGradientNoise`、`OMNI_TAA`、
  `OMNI_STAR_TYPE` 由绘制主体与共享文件提供。
关键设计原因与取舍：`EndCalculate3DNoise` 加 `End` 前缀与主世界 `effects/fog/fog.glsl` 的同名函数区分；
  空间扭曲与云状分形噪声已经迁到 `shaders/gfx/math.glsl` 与 `shaders/gfx/fog.glsl`，本文件只做同名转发；
  吸积盘是屏幕空间积分，不改写几何。
*/
#ifndef OMNI_END_DISC_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_DISC_INCLUDED // 置上标记，后续再次引用直接跳过。
// 环带径向轮廓放在通用库，这里只传归一化半径。
#include "/gfx/math.glsl"
// 末地三维噪声放在通用库，这里只传噪声纹理。
#include "/gfx/fog.glsl"
// 吸积盘的云噪声随时间流动，时间从绑定层取。
#include "/bind/time.glsl"

// 来源：原程序在此处标注了出处网址 `www.shadertoy.com/view/lstSRS`，按合同保留来源注释与写法。

// --- 旋转矩阵：依次绕三个轴旋转后合成 ---
mat3 RotateMatrix(float x, float y, float z){
	return gfx_rotate_matrix(x, y, z); // 转发到通用库。
}

// --- 空间扭曲：越靠近黑洞中心，光线被拉得越厉害 ---
void WarpSpace(inout vec3 eyevec, inout vec3 raypos){
	gfx_warp_space(eyevec, raypos); // 转发到通用库。
}

// --- 三维噪声：和主世界那份同源，按合同加 `End` 前缀以区分同名 ---
float EndCalculate3DNoise(vec3 position){
	return gfx_end_3d_noise(position, noisetex, 64.0); // 转发到通用库，贴图边长与仓库噪声图一致。
}

// --- 云状分形噪声：四层不同频率叠加，供吸积盘细节使用 ---
float CalculateCloudFBM(vec3 position, vec3 shift){
	return gfx_cloud_fbm(position, shift, noisetex, 64.0); // 转发到通用库，贴图边长与仓库噪声图一致。
}

float pcurve(float x){
	return gfx_pcurve(x); // 转发到通用库。
}

// --- 吸积盘（天空版）：沿视线在黑洞附近步进，累加盘的颜色，再叠星空 ---
void BlackHole_AccretionDisc_Stars(inout vec3 color, in vec3 rayDir, in vec3 lightDir){
	const float steps = 50.0; // 步进次数。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const float stepLength = 0.2; // 每步长度。

	const float discRadius = 2.25; // 吸积盘半径。
	const float discWidth = 3.5; // 吸积盘宽度。
	const float discInner = discRadius - discWidth * 0.5; // 内半径。
	const float discOuter = discRadius + discWidth * 0.5; // 外半径。

	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声，抖动被时间平均掉。
		float noise = BlueNoiseTemporal().x; // 每帧变化的噪声。
	#else // 否则用屏幕空间的固定噪声。
		float noise = InterleavedGradientNoise(gl_FragCoord.xy); // 交错梯度噪声。
	#endif

	vec3 eye = -lightDir * 8.0; // 视线起点。
	vec3 rayPos = eye + rayDir * 3.0; // 起始步进位置。

	mat3 rotation = RotateMatrix(0.1, 0.0, -0.35); // 吸积盘的固定倾角。

	vec3 result = vec3(0.0); // 累积的盘颜色。
	float transmittance = 1.0; // 透过率。

	rayPos += rayDir * stepLength * noise; // 起点按噪声抖动，减少步进条纹。

	for(int i = 0; i < steps; i++){ // 逐步前进。
		if(transmittance < 0.0001) break; // 已被遮满就停止。

		WarpSpace(rayDir, rayPos); // 靠近黑洞时光线被拉弯。
		rayPos += rayDir * stepLength; // 前进一步。

		{
			vec3 discPos = rotation * rayPos; // 转到吸积盘坐标系。

			float r = length(discPos); // 到盘中心的半径。
			float p = atan2(-discPos.zx); // 盘面上的方位角。
			float h = discPos.y; // 离盘面的高度。

			float radialGradient = 1.0 - saturate((r - discInner) / discWidth * 0.5); // 径向衰减。
			float dist = abs(h); // 到盘面的距离。

			float discThickness = 0.1 * radialGradient; // 盘的厚度随半径变化。

			float fr = abs(r - discInner) + 0.4; // 到内边缘的距离。
			fr = fr * fr; // 平方。
			float fade = fr * fr * 0.04; // 亮度衰减。
			float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 靠近盘面的辉光。
			bloomFactor *= saturate(2.0 - abs(dist) / discThickness); // 只在盘厚范围内。
			bloomFactor = bloomFactor * bloomFactor; // 平方增强。

			float dr = pcurve(radialGradient); // 径向轮廓。
			float density = dr; // 当前密度。

			density *= saturate(1.0 - abs(dist) / discThickness); // 按离盘面距离衰减。
			density = saturate(density * 0.7); // 整体缩放。
			density = saturate(density + bloomFactor * 0.1); // 叠上辉光。

			if (density > 0.0001){ // 有密度才算这一步的颜色。
				#if OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE // 细节沿纬度分布时用方位角。
					vec3 discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5; // 盘坐标带方位角。
					float fbm = CalculateCloudFBM(discCoord, bind_time().seconds * vec3(0.1, 0.07, 0.0)); // 高质量云噪声。
				#else // 默认细节只沿半径与高度分布。
					vec3 discCoord = vec3(r, 0.0, h * 0.1) * 3.5; // 盘坐标不带方位角。
					float fbm = CalculateCloudFBM(discCoord, bind_time().seconds * vec3(0.03, 0.05, 0.0)); // 高质量云噪声。
				#endif
				fbm = fbm * fbm; // 平方。
				fbm = fbm * fbm; // 再平方，拉开明暗。

				density *= fbm * dr; // 噪声乘回径向轮廓。

				float gr = 1.0 - radialGradient; // 反径向。
				gr = gr * gr; // 平方。
				float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮的辉光。
				vec3 glow = Blackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。

				#if OMNI_ACCRETIONDISC_DOPPLER_EFFECT // 多普勒效应：一侧更亮。
					glow *= sin(p - 1.07) * 0.75 + 1.0; // 按方位角调制。
				#endif

				float stepTransmittance = exp2(-density * 7.0); // 这一步的透过率。
				float integral = 1.0 - stepTransmittance; // 这一步吸收掉的量。
				transmittance *= stepTransmittance; // 累积透过率。

				result += integral * transmittance * glow; // 按透过率累加颜色。
			}

			vec2 t = vec2(1.0, 0.01); // 圆环截面参数。
			float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
			float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
			vec3 col = Blackbody(12000.0); // 高色温的冷白。
			bloomDisc *= step(0.5, r); // 只在盘外缘以外。

			result += col * bloomDisc * 0.1 * transmittance; // 叠上圆环辉光。
		}
	}
	result *= rSteps; // 步数平均。

	#if OMNI_STAR_TYPE > 0 // 打开星空才画星星。
		color += EndCalculateStars(rayDir); // 叠星空。
	#endif

	color *= transmittance; // 前面的天光被吸积盘吃掉。
	color += result; // 叠上吸积盘颜色。
}

// --- 吸积盘（反射版）：步进更少，供屏幕反射的假天空回退使用 ---
void BlackHole_AccretionDisc_Reflection(inout vec3 color, in vec3 rayDir, in vec3 lightDir){
	const float steps = 30.0; // 步进次数，比天空版少。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const float stepLength = 0.2; // 每步长度。

	const float discRadius = 2.25; // 吸积盘半径。
	const float discWidth = 3.5; // 吸积盘宽度。
	const float discInner = discRadius - discWidth * 0.5; // 内半径。
	const float discOuter = discRadius + discWidth * 0.5; // 外半径。

	float noise = BlueNoiseTemporal().x; // 每帧变化的噪声。

	vec3 eye = -lightDir * 8.0; // 视线起点。
	vec3 rayPos = eye + rayDir * 4.0; // 起始步进位置，比天空版远一点。

	mat3 rotation = RotateMatrix(0.1, 0.0, -0.35); // 吸积盘固定倾角。

	vec3 result = vec3(0.0); // 累积的盘颜色。
	float transmittance = 1.0; // 透过率。

	rayPos += rayDir * stepLength * noise; // 起点抖动。

	for(int i = 0; i < steps; i++){ // 逐步前进。
		if(transmittance < 0.0001) break; // 遮满即停。

		WarpSpace(rayDir, rayPos); // 空间扭曲。
		rayPos += rayDir * stepLength; // 前进一步。

		{
			vec3 discPos = rotation * rayPos; // 转到吸积盘坐标系。

			float r = length(discPos); // 到盘心半径。
			float p = atan2(-discPos.zx); // 方位角。
			float h = discPos.y; // 离盘面高度。

			float radialGradient = 1.0 - saturate((r - discInner) / discWidth * 0.5); // 径向衰减。
			float dist = abs(h); // 到盘面距离。

			float discThickness = 0.1 * radialGradient; // 盘厚。

			float fr = abs(r - discInner) + 0.4; // 到内边缘距离。
			fr = fr * fr; // 平方。
			float fade = fr * fr * 0.04; // 亮度衰减。
			float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 靠近盘面的辉光。
			bloomFactor *= saturate(2.0 - abs(dist) / discThickness); // 只在盘厚内。
			bloomFactor = bloomFactor * bloomFactor; // 平方增强。

			float dr = pcurve(radialGradient); // 径向轮廓。
			float density = dr; // 当前密度。

			density *= saturate(1.0 - abs(dist) / discThickness); // 按离盘面距离衰减。
			density = saturate(density * 0.7); // 整体缩放。
			density = saturate(density + bloomFactor * 0.1); // 叠上辉光。

			if (density > 0.0001){ // 有密度才算颜色。
				#if OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE // 细节沿纬度分布。
					vec3 discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5; // 带方位角的盘坐标。
					float fbm = CalculateCloudFBM(discCoord, bind_time().seconds * vec3(0.1, 0.07, 0.0)); // 高质量云噪声。
				#else // 默认不带方位角。
					vec3 discCoord = vec3(r, 0.0, h * 0.1) * 3.5; // 盘坐标。
					float fbm = CalculateCloudFBM(discCoord, bind_time().seconds * vec3(0.03, 0.05, 0.0)); // 高质量云噪声。
				#endif

				float fbm2 = fbm * fbm; // 平方。
				density *= fbm2 * fbm2 * fbm; // 噪声五次方乘回密度。
				density *= dr; // 再乘径向轮廓。

				float gr = 1.0 - radialGradient; // 反径向。
				gr = gr * gr; // 平方。
				float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮。
				vec3 glow = Blackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。

				#if OMNI_ACCRETIONDISC_DOPPLER_EFFECT // 多普勒效应。
					glow *= sin(p - 1.07) * 0.75 + 1.0; // 按方位角调制。
				#endif

				float stepTransmittance = exp2(-density * 7.0); // 这一步透过率。
				float integral = 1.0 - stepTransmittance; // 吸收量。
				transmittance *= stepTransmittance; // 累积透过率。

				result += integral * transmittance * glow; // 累加颜色。
			}

			vec2 t = vec2(1.0, 0.01); // 圆环截面参数。
			float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环距离。
			float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001); // 圆环辉光。
			vec3 col = Blackbody(12000.0); // 冷白。
			bloomDisc *= step(0.5, r); // 只在盘外缘以外。

			result += col * bloomDisc * 0.1 * transmittance; // 叠圆环辉光。
		}
	}
	result *= rSteps; // 步数平均。

	color *= transmittance; // 前面天光被吃掉。
	color += result; // 叠吸积盘颜色。
}
#endif // OMNI_END_DISC_INCLUDED 结束。
