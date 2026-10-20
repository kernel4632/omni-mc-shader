/*
末地星空与行星：星空复用主世界那份 Eclipse 星场，行星部分再用射线求交画地表、光环与大气。
来源：行星、吸积盘与雾照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 移植；星空按用户要求换成
  Eclipse `lib/stars.glsl`，与主世界共用 `effects/sky/sky.glsl` 的 `CalculateStars`，不再是 iterationT 的末地星空，
  差异记入 `docs/parity.md` 偏离记录与 `docs/eclipse-parity.md`「星空」行。
职责：`EndCalculateStars` 转发主世界星场并画出末地星空，`H`、`ppss`、`Disc` 是行星表面的
  双向反射近似，`PlanetEnd2` 画整颗行星本体、光环与大气。
调用位置：由 `effects/world/end.glsl` 引入；`rendering/composite.glsl` 的合成零号在末地天空像素调用
  `PlanetEnd2`，合成二号经 `ComputeFakeSkyReflectionEnd` 调用。
可复制示例：`PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector);`
调用前提：由 `effects/world/end.glsl` 在声明 `timeFactor`、`planetShadow` 之后、且已引入
  `effects/sky/sky.glsl` 之后引入；`worldSunVector`、`worldShadowVector`、`noisetex`、`MiePhaseFunction`、
  `RaySphereIntersection`、`RayPlaneIntersection`、`curve` 由绘制主体与 `common/math.glsl` 提供，本文件不重复引入；
  `CalculateStars` 由 `effects/sky/sky.glsl` 提供。
关键设计原因与取舍：行星是屏幕空间的解析积分，不改写几何；末地天空整幅由这里画出，不走预计算大气。
  星空不再单独维护一份，与主世界共用同一份 Eclipse 星场，星点形态在两个维度保持一致，也避免复制代码。
*/
#ifndef OMNI_END_SKY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_SKY_INCLUDED // 置上标记，后续再次引用直接跳过。
// 行星表面与环带的纯公式放在通用库。
#include "/gfx/atmosphere.glsl"

// --- 星空：与主世界共用同一份 Eclipse 星场，来源 Eclipse `lib/stars.glsl`（经 `effects/sky/sky.glsl`） ---
// 为什么共用：用户要求末地星空也换成 Eclipse 的实现，而主世界已把星场核换成 Eclipse；
//   共用同一份函数可保证两个维度的星点形状、疏密与星色一致，也不必把星场代码复制两份。
// 与旧 iterationT 末地星空的差异：星点由「三维格子哈希」换成 Eclipse 的稳定星场；
//   星场朝向沿用主世界 `CalculateStars` 的「绕日轴对齐天球」，不再单独按时间绕竖直轴旋转。
// 调用位置：`effects/world/end_disc.glsl` 的 `BlackHole_AccretionDisc_Stars` 在 `OMNI_STAR_TYPE > 0` 时调用。
// 签名与原 `EndCalculateStars` 一致（只吃世界方向），调用方不用改；太阳方向由全局量 `worldSunVector` 取。
vec3 EndCalculateStars(vec3 worldDir){
	return CalculateStars(worldDir, worldSunVector); // 直接复用主世界星场。
}

// --- 行星表面的双向反射：把入射与出射两侧的积分近似各算一次 ---
vec3 H(vec3 albedo, float a){
	return gfx_chandrasekhar_h(albedo, a); // 钱德拉塞卡近似在通用库。
}

vec3 ppss(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir, float s){
	return gfx_planet_brdf(albedo, normal, eyeDir, lightDir); // 双向反射在通用库；`s` 为保持原调用签名。
}

float Disc(float a, float s, float h){
	return gfx_disc_profile(a, s, h); // 圆盘剖面在通用库。
}

// --- 行星本体：射线与行星球求交，算出地表、光环与大气 ---
void PlanetEnd2(inout vec3 color, in vec3 eye, in vec3 rayDir, in vec3 lightDir){
	const float Rground = 20e6; // 行星半径。
	const float Ratmo = 20.1e6; // 大气层顶半径。
	eye.y += Rground; // 相机抬到行星表面之上。
	eye.y += 15e6; // 再抬高，模拟远离行星的视角。

	float VdotL = dot(worldShadowVector, rayDir); // 视线与阳光夹角余弦，供相位使用。

	float mie = MiePhaseFunction(0.8, VdotL); // 米氏相位。

	float angleX = -1.57079633 + (0.2 * sin(timeFactor + 3.0) - 0.1); // 俯仰角随时间摆动。
	float angleY = timeFactor; // 偏航角随时间转动。

	mat3 eyeRoataionMatrixX = mat3(1, 0, 0, 0, cos(angleX), -sin(angleX), 0, sin(angleX), cos(angleX)); // 俯仰旋转矩阵。
	mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0, sin(angleY), 0, 1, 0, -sin(angleY), 0, cos(angleY)); // 偏航旋转矩阵。
	mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。

	float ringAngle = 0.008 * sin(timeFactor + 4.6); // 光环的倾角随时间轻微摆动。

	mat3 ringRoataionMatrix = mat3(1.0, 0.0, 0.0,
								   0.0, cos(ringAngle), sin(ringAngle),
								   0.0, -sin(ringAngle), cos(ringAngle)); // 光环旋转矩阵。
	mat3 ringRoataionMatrixInverse = transpose(ringRoataionMatrix); // 光环旋转的逆。

	rayDir = eyeRoataionMatrix * rayDir; // 视线转到行星坐标系。
	lightDir = eyeRoataionMatrix * lightDir; // 光方向同样转过去。

	vec3 rayDirRing = ringRoataionMatrix * rayDir; // 视线转到光环坐标系。
	vec3 lightDirRing = ringRoataionMatrix * lightDir; // 光方向转到光环坐标系。

	vec3 ringOrigin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 光环所在平面的原点。
	vec2 ringRadius = vec2(1.6, 2.6); // 光环内外半径。

	vec3 surface = vec3(0.0); // 行星表面与光环累积的颜色。
	float LdotR = dot(rayDir, -lightDir); // 光线与视线夹角余弦。

	vec2 groundIntersection = RaySphereIntersection(eye, rayDir, Rground); // 与行星地表求交。
	vec2 topAtmoIntersection = RaySphereIntersection(eye, rayDir, Ratmo); // 与大气层顶求交。

	vec3 surfacePos = rayDir * groundIntersection.x; // 地表交点位置。
	vec3 surfaceNormal = normalize(surfacePos + vec3(0.0, eye.y, 0.0)); // 地表法线，由球心指向交点。

	if (groundIntersection.y > 0.0){ // 射线打到行星本体。
		color *= 0.0; // 本体完全遮住后面的天光。

		vec3 surfaceAlbedo = vec3(0.98, 0.87, 0.55); // 行星表面底色，偏暖白。

		surface = ppss(surfaceAlbedo, surfaceNormal, -rayDir, lightDir, 1.0); // 算地表着色。

		vec3 origin = ringOrigin + surfacePos / Rground; // 光环采样的起点。
		vec3 rayPos = RayPlaneIntersection(origin, lightDirRing, vec3(0.0, 0.0, 1.0)); // 沿光方向与光环平面求交。
		float rayRadius = length(rayPos); // 交点到光环中心的半径。

		if (rayRadius > ringRadius.x && rayRadius < ringRadius.y && dot(rayPos - origin, lightDirRing) > 0.0){ // 落在环带内且朝光一侧。
			float ringNoise = gfx_planet_ring_noise(rayRadius * 0.5 + 0.69, noisetex); // 五层噪声叠出环带细缝。
			surface *= exp(-pow(saturate(ringNoise) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius)); // 噪声把环带压出缝隙。
		}

		float UdotN = saturate(dot(ringRoataionMatrixInverse[2], surfaceNormal)); // 光环上表面法线与地表法线夹角。
		float DdotN = saturate(dot(-ringRoataionMatrixInverse[2], surfaceNormal)); // 光环下表面同理。
		float OLdotN = saturate(dot(ringRoataionMatrixInverse * normalize(vec3(-lightDir.xy, 0.0)), surfaceNormal)); // 光线在环面上的投影与法线夹角。

		float ringLighting = Disc(UdotN, 1.2, 1.5) * (1.0 - Disc(UdotN, 3.4, 0.3)); // 上表面环带光照。
		ringLighting += Disc(DdotN, 1.2, 1.5) * (1.0 - Disc(DdotN, 3.4, 0.3)); // 下表面环带光照。
		ringLighting *= 1.0 - Disc(OLdotN, 0.7, 1.3); // 被行星自身挡住的部分去掉。

		surface += surfaceAlbedo * (1.5e-4 + ringLighting * 0.01); // 环带光叠到地表上。
	}

	if (topAtmoIntersection.y > 0.0){ // 射线经过大气层。
		float isGround = step(0.0, groundIntersection.y); // 是否打到地面。
		float thickness = (topAtmoIntersection.y - topAtmoIntersection.x - (groundIntersection.y - groundIntersection.x) * isGround) * 1e-7; // 大气层内的光学厚度。
		float topAtmoMie = mie * thickness * thickness; // 米氏散射。
		topAtmoMie *= mix(1.0, smoothstep(0.9, 0.4, dot(surfaceNormal, normalize(eye))), isGround); // 打到地面时按视线角度衰减。
		surface += topAtmoMie * vec3(0.65, 0.7, 1.0); // 大气偏冷蓝。
	}

	color += surface * 0.6; // 地表与大气叠加到画面。

	float inRing = saturate(abs(ringAngle) * 3000.0 - 0.8); // 当前是否正对环面。

	float ring = 0.0; // 环带的亮度。
	float transmittance = 1.0; // 环带留下的透过率。

	if (rayDirRing.z * ringAngle < 0.0){ // 视线穿过环面。

		vec3 origin = vec3(0.0, cos(ringAngle), sin(ringAngle)) * (eye.y / Rground); // 环面原点。

		vec3 ringPos = RayPlaneIntersection(origin, rayDirRing, vec3(0.0, 0.0, 1.0)); // 视线与环面求交。
		float rayRadius = length(ringPos); // 交点到环心半径。
		vec2 ringRadius = vec2(1.6, 2.6); // 环带内外半径。

		if(rayRadius > ringRadius.x && rayRadius < ringRadius.y) // 落在环带内。
		{
			float ringNoise = gfx_planet_ring_noise(rayRadius * 0.5 + 0.69, noisetex); // 五层噪声叠出环带细缝。
			ring += pow(saturate(ringNoise) * 1.5, 3.0); // 噪声得到环带形状。
			ring *= smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius); // 内边缘渐入。

			if(ringPos.y < 0.0 && groundIntersection.y > 0.0){ // 交点在环面下方且视线打到地面。
				ring *= 0.0; // 被行星本体挡住，环带不显示。
			}else{
				transmittance *= exp2(-ring * 3.0); // 否则环带按厚度吃掉一部分透过。
			}

			float d = length(cross(lightDirRing, ringPos)); // 交点到光方向的垂距。
			ring *= 0.98 * max(smoothstep(0.8, 1.2, d), step(0.0, dot(lightDirRing, ringPos))) + 0.02; // 朝光一侧更亮，加一点底亮。
		}
	}

	ring = mix(planetShadow * 0.49 + 0.01, ring, inRing); // 正对环面时用环带亮度，否则用行星阴影的固定暗带。
	transmittance = mix(0.7, transmittance, inRing); // 透过率同样按是否正对环面切换。

	color *= transmittance; // 环带吃掉一部分天光。

	ring *= 1.0 + mie * 10.0 * planetShadow; // 正对时叠一份米氏散射。

	color += ring * 0.012 * vec3(1.0, 0.85, 0.60); // 环带偏暖黄叠到画面。
}
#endif // OMNI_END_SKY_INCLUDED 结束。
