/*
末地天空：画出末地特有的星空、行星、吸积盘光环与大气雾，全部按时间因子旋转；另含末地主岛光源与雾密度选项。
来源：主体照 iterationT `Lib/IndividualFounctions/EndSky.glsl` 一比一移植，全部函数、内部常数与分支照原程序，
  只有同名冲突函数按移植合同九点五节加 `End` 前缀（`CalculateStars`、`Calculate3DNoise`），函数体不变。
  主岛光源与末地雾的两个密度选项来自 Eclipse（`lib/settings.glsl:419-421`、`:911-912`、`dimensions/composite.fsh:509`），
  按 `docs/eclipse-parity.md` 第 37、39 行合并，默认关闭或取中性值，不改变原有画面。
调用位置：
  `rendering/composite.glsl` 的合成零号在末地天空像素上调用 `BlackHole_AccretionDisc_Stars` 与 `PlanetEnd2`；
  合成零号在有几何的像素上、开启 `OMNI_END_ISLAND_LIGHT` 时调用 `EndIslandLighting` 叠主岛光源；
  `rendering/composite.glsl` 的合成二号在末地反射回退里调用 `BlackHole_AccretionDisc_Reflection`、`PlanetEnd2` 与 `EndFog`；
  `rendering/composite.glsl` 的合成五号在末地水雾里调用 `EndFog`。
可复制示例：
  `BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector);`
  `PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector);`
  `color += EndFog(waterDist, worldDir);`
  `finalComposite += EndIslandLighting(worldPos, worldNormal, worldDir, gbuffer.albedo, gbuffer.material.roughness, gbuffer.material.f0, gbuffer.material.metalness);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明或先引入）：
  `worldSunVector`、`worldShadowVector` 是绘制主体声明的光方向全局量（合成程序里是顶点阶段传入的 `in`）；
  `frameTimeCounter`、`noisetex`、`cameraPosition` 由 `common/uniforms.glsl` 提供，`MiePhaseFunction`、`Blackbody`、
  `RaySphereIntersection`、`RayPlaneIntersection`、`remapSaturate`、`curve`、`saturate`、`InterleavedGradientNoise`、
  `Fd_Burley`、`SpecularGGX` 由 `common/math.glsl` 提供，`BlueNoiseTemporal` 由 `common/noise.glsl` 提供；
  `OMNI_SUNLIGHT_INTENSITY` 由 `effects/lighting/sunlight.glsl` 提供，`OMNI_STAR_TYPE` 由 `effects/sky/sky.glsl` 提供，
  `OMNI_TAA` 由 `effects/clarity/antialiasing.glsl` 提供；这些都必须在引入本文件之前引入。
关键设计原因与取舍：
  原程序在文件顶部用 `frameTimeCounter` 与旋转周期算出 `timeFactor` 与 `planetShadow` 两个全局量，本文件照搬，
  所以这些全局量与 `frameTimeCounter` 挂钩，同一帧内多次调用不会重复计算；
  吸积盘与行星都是屏幕空间的解析积分，不改写几何，末地天空整幅由这里画出，不走预计算大气。
  主岛光源没有照搬 Eclipse 的阴影相机（需要计算着色器与附加缓冲），而是在合成零号按点光源解析照亮，
  距离与视野角取自 Eclipse，衰减形状是本项目的近似，见 `docs/eclipse-parity.md` 第 37 行的说明。
*/
#ifndef OMNI_END_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_INCLUDED // 置上标记，后续再次引用直接跳过。
// @effect {"label":{"zh_cn":"末地","en_us":"End"}}
// @option {"label":{"zh_cn":"末地公转周期","en_us":"End Revolution Period"},"description":{"zh_cn":"行星绕末地转一圈的时间。","en_us":"Time for the planet to orbit once."},"slider":true}
#define OMNI_END_PLANET_CYCLE 15.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 5.0 7.5 10.0 15.0 20.0 30.0 60.0]
// @option {"label":{"zh_cn":"手动相位控制","en_us":"Manual Phase Control"},"description":{"zh_cn":"手动指定末地行星的位置。","en_us":"Manually sets the planet's phase."}}
//#define OMNI_END_MANUAL_PLANET_CYCLE
// @option {"label":{"zh_cn":"相位角","en_us":"Phase Angle"},"description":{"zh_cn":"“手动相位控制”的相位值，单位度。","en_us":"Phase value in degrees used by Manual Phase Control."},"slider":true}
#define OMNI_END_MANUAL_PLANET_ANGLE 0.0 // [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0 121.0 122.0 123.0 124.0 125.0 126.0 127.0 128.0 129.0 130.0 131.0 132.0 133.0 134.0 135.0 136.0 137.0 138.0 139.0 140.0 141.0 142.0 143.0 144.0 145.0 146.0 147.0 148.0 149.0 150.0 151.0 152.0 153.0 154.0 155.0 156.0 157.0 158.0 159.0 160.0 161.0 162.0 163.0 164.0 165.0 166.0 167.0 168.0 169.0 170.0 171.0 172.0 173.0 174.0 175.0 176.0 177.0 178.0 179.0 180.0 181.0 182.0 183.0 184.0 185.0 186.0 187.0 188.0 189.0 190.0 191.0 192.0 193.0 194.0 195.0 196.0 197.0 198.0 199.0 200.0 201.0 202.0 203.0 204.0 205.0 206.0 207.0 208.0 209.0 210.0 211.0 212.0 213.0 214.0 215.0 216.0 217.0 218.0 219.0 220.0 221.0 222.0 223.0 224.0 225.0 226.0 227.0 228.0 229.0 230.0 231.0 232.0 233.0 234.0 235.0 236.0 237.0 238.0 239.0 240.0 241.0 242.0 243.0 244.0 245.0 246.0 247.0 248.0 249.0 250.0 251.0 252.0 253.0 254.0 255.0 256.0 257.0 258.0 259.0 260.0 261.0 262.0 263.0 264.0 265.0 266.0 267.0 268.0 269.0 270.0 271.0 272.0 273.0 274.0 275.0 276.0 277.0 278.0 279.0 280.0 281.0 282.0 283.0 284.0 285.0 286.0 287.0 288.0 289.0 290.0 291.0 292.0 293.0 294.0 295.0 296.0 297.0 298.0 299.0 300.0 301.0 302.0 303.0 304.0 305.0 306.0 307.0 308.0 309.0 310.0 311.0 312.0 313.0 314.0 315.0 316.0 317.0 318.0 319.0 320.0 321.0 322.0 323.0 324.0 325.0 326.0 327.0 328.0 329.0 330.0 331.0 332.0 333.0 334.0 335.0 336.0 337.0 338.0 339.0 340.0 341.0 342.0 343.0 344.0 345.0 346.0 347.0 348.0 349.0 350.0 351.0 352.0 353.0 354.0 355.0 356.0 357.0 358.0 359.0]
// @option {"label":{"zh_cn":"环带纬度细节","en_us":"Dusty Accretion Disc"},"description":{"zh_cn":"环带的细节沿纬度方向分布。","en_us":"Spreads the disc detail along its latitude."}}
//#define OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE
// @option {"label":{"zh_cn":"吸积盘多普勒效应","en_us":"Accretion Disc Doppler Effect"},"description":{"zh_cn":"模拟黑洞吸积盘旋转的多普勒效应，一边更亮、一边更暗。","en_us":"Simulates the doppler shift of the rotating accretion disc, brightening one side."}}
#define OMNI_ACCRETIONDISC_DOPPLER_EFFECT
// @option {"label":{"zh_cn":"末地主岛光源","en_us":"End Island Light"},"description":{"zh_cn":"在末地主岛上方（世界坐标零点、高度一百九十）放一盏灯，按到灯的距离和入射角照亮附近表面并产生高光。默认关闭，画面与不加这项时一致。","en_us":"Places a light above the End main island at world (0, 190, 0) that lights nearby surfaces by distance and angle and adds specular. Off by default."}}
//#define OMNI_END_ISLAND_LIGHT
// @option {"label":{"zh_cn":"主岛光源视野角","en_us":"Island Light FOV"},"description":{"zh_cn":"主岛光源的照射范围角度，单位度；超出这个角度的表面收不到这份光。取自 Eclipse 的七十七度。","en_us":"Cone angle of the island light in degrees; surfaces outside it get no light. Eclipse uses 77."},"slider":true}
#define OMNI_END_LIGHT_FOV 77.0 // [30.0 40.0 50.0 60.0 70.0 77.0 90.0 110.0 130.0 150.0]
// @option {"label":{"zh_cn":"主岛光源亮度","en_us":"Island Light Brightness"},"description":{"zh_cn":"主岛光源的整体亮度，一为基准值，零等于关灯。默认一不改变已有的光照尺度。","en_us":"Overall brightness of the island light; 1 is the reference and 0 is off. Default 1 keeps the existing light scale."},"slider":true}
#define OMNI_END_LIGHT_BRIGHTNESS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0]
// @option {"label":{"zh_cn":"末地风暴密度","en_us":"End Storm Density"},"description":{"zh_cn":"末地雾里带方向性的风暴部分浓度，一为现在的强度，零去掉这一层。取自 Eclipse 的同名密度。","en_us":"Density of the directional storm part of the End fog; 1 is the current strength, 0 removes it. Matches Eclipse's storm density."},"slider":true}
#define OMNI_END_FOG_STORM_DENSITY 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0]
// @option {"label":{"zh_cn":"末地雾霭密度","en_us":"End Haze Density"},"description":{"zh_cn":"末地雾里不带方向性的雾霭部分浓度，一为现在的强度，零去掉这一层。取自 Eclipse 的同名密度。","en_us":"Density of the direction-less haze part of the End fog; 1 is the current strength, 0 removes it. Matches Eclipse's haze density."},"slider":true}
#define OMNI_END_FOG_HAZE_DENSITY 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0]
// 主岛光源的位置：Eclipse `lib/settings.glsl:419` 的世界坐标，内部常数照原程序保留原名，不进菜单。
#define END_LIGHT_POS vec3(0.0, 190.0, 0.0)

// --- 时间因子：整颗末地天空按它旋转 ---
// 手动相位时取固定角度，否则按累计时间除以公转周期循环。零点二八二是原程序的起始相位。
#ifdef OMNI_END_MANUAL_PLANET_CYCLE
	const float timeFactor = fract(OMNI_END_MANUAL_PLANET_ANGLE / 360.0 + 0.282) * TAU; // 手动相位换算成弧度。
#else
	float timeFactor = fract(frameTimeCounter * ((1.0 / 60.0) / OMNI_END_PLANET_CYCLE) + 0.282) * TAU; // 由时间推进的相位。
#endif

// 行星阴影：相位落在两段里时行星本体挡住光环，光环那一侧变暗。
float planetShadow = smoothstep(0.62, 0.35, timeFactor) + smoothstep(1.6, 1.87, timeFactor);

// --- 星空：把方向量化到格子，每个格子按哈希决定有没有星、颜色与温度 ---
// 名称加 `End` 前缀：主世界 `effects/sky/sky.glsl` 另有一份 `CalculateStars`，两者签名不同但按合同区分开。
vec3 EndCalculateStars(vec3 worldDir){
	float angleY = frameTimeCounter * 0.001; // 整片星空绕竖直轴缓慢旋转的角度。
	mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0, sin(angleY), 0, 1, 0, -sin(angleY), 0, cos(angleY)); // 绕纵轴旋转矩阵。

	worldDir = eyeRoataionMatrixY * worldDir; // 先转到旋转后的方向。

	const float scale = 384.0; // 星空球被切成的格子密度。
	const float coverage = 0.007; // 有星的比例。
	const float maxLuminance = 0.04; // 单颗星的最大亮度。
	const float minTemperature = 4000.0; // 星光最低色温。
	const float maxTemperature = 8000.0; // 星光最高色温。

	float cosine = dot(worldSunVector,  vec3(0, 0, 1)); // 太阳方向与轴的夹角余弦。
	vec3 axis = cross(worldSunVector,  vec3(0, 0, 1)); // 旋转轴。
	float cosecantSquared = 1.0 / dot(axis, axis); // 轴长的倒数平方，用来归一转轴公式。
	worldDir = cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 把星空对齐到太阳方向。

	vec3 p = worldDir * scale; // 换成格子坐标。
	ivec3 i = ivec3(floor(p)); // 所在整数格。
	vec3 f = p - i; // 格内偏移。
	float r = dot(f - 0.5, f - 0.5); // 到格中心的距离平方，用来做圆形衰减。

	vec3 i3 = fract(i * vec3(443.897, 441.423, 437.195)); // 三个质数打散整数格。
	i3 += dot(i3, i3.yzx + 19.19); // 混合各分量。
	vec2 hash = fract((i3.xx + i3.yz) * i3.zy); // 得到两个零到一的哈希值。
	hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y; // 二次平滑哈希的第二个值。

	float c = remapSaturate(hash.x, 1.0 - coverage, 1.0); // 只有超过覆盖阈值才算是星。
	return (maxLuminance * remapSaturate(r, 0.25, 0.0) * c * c) * Blackbody(mix(minTemperature, maxTemperature, hash.y)); // 亮度衰减乘按温度取的星色。
}

// --- 行星表面的双向反射：把入射与出射两侧的积分近似各算一次 ---
vec3 H(vec3 albedo, float a){
	vec3 R = sqrt(vec3(1.0) - albedo); // 单次散射反照率的平方根。
	vec3 r = (1.0 - R) / (1.0 + R); // 反射率比值。
	vec3 H = r + (0.5 - r * a) * log((1.0 + a) / a); // 钱德拉塞卡近似。
	H *= albedo * a; // 乘反照率与余弦项。

	return 1.0 / (1.0 - H); // 取倒数得到倍增。
}

vec3 ppss(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir, float s){
	float NdotL = dot(normal, lightDir); // 法线与光方向夹角余弦。
	float NdotV = dot(normal, eyeDir); // 法线与视线夹角余弦。
	albedo *= curve(saturate(NdotL)); // 反照率按入射角衰减。

	vec3 color = albedo * H(albedo, NdotL) * H(albedo, NdotV) / (4.0 * PI * (NdotL + NdotV)); // 两侧近似与相函数分母。

	return saturate(color); // 夹到合理范围。
}

float Disc(float a, float s, float h){
	float disc = curve(saturate((a - (1.0 - s)) * h)); // 由阈值与斜率构成的圆盘剖面。
	return disc * disc; // 平方拉开明暗边界。
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
			const float octAlpha = 0.5; // 每层噪声的权重衰减。
			float octScale = 4.0; // 每层频率放大。
			float octShift = (octAlpha / octScale) / 5; // 层间偏移。
			float accum = 0.0; // 累积噪声。
			float alpha = 0.5; // 当前层权重。
			float shift = 0.0; // 层间位移。
			float position = rayRadius * 0.5 + 0.69; // 环带上的采样位置。

			position += shift; // 加上层间位移。

			for (int i = 0; i < 5; i++){ // 五层噪声叠出环带的细缝。
				accum += alpha * textureLod(noisetex, vec2(position, 0.0), 0.0).z; // 读噪声的第三通道。
				position = (position + shift) * octScale; // 抬高频率。
				alpha *= octAlpha; // 权重衰减。
			}

			surface *= exp(-pow(saturate(accum + octShift - 0.1) * 1.5, 3.0) * smoothstep(ringRadius.x, ringRadius.x * 1.1, rayRadius)); // 噪声把环带压出缝隙。
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
			const float octAlpha = 0.5; // 每层噪声权重衰减。
			float octScale = 4.0; // 每层频率放大。
			float octShift = (octAlpha / octScale) / 5; // 层间偏移。
			float accum = 0.0; // 累积噪声。
			float alpha = 0.5; // 当前层权重。
			float shift = 0.0; // 层间位移。
			float position = rayRadius * 0.5 + 0.69; // 环带采样位置。

			position += shift; // 加上层间位移。

			for (int i = 0; i < 5; i++) { // 五层噪声叠缝。
				accum += alpha * textureLod(noisetex, vec2(position, 0.0), 0.0).z; // 读噪声第三通道。
				position = (position + shift) * octScale; // 抬高频率。
				alpha *= octAlpha; // 权重衰减。
			}

			ring += pow(saturate(accum + octShift - 0.1) * 1.5, 3.0); // 噪声得到环带形状。
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

// 来源：原程序在此处标注了出处网址 `www.shadertoy.com/view/lstSRS`，按合同保留来源注释与写法。

// --- 旋转矩阵：依次绕三个轴旋转后合成 ---
mat3 RotateMatrix(float x, float y, float z){
	mat3 matx = mat3(1.0, 0.0, 0.0,
					 0.0, cos(x), sin(x),
					 0.0, -sin(x), cos(x)); // 绕横轴。

	mat3 maty = mat3(cos(y), 0.0, -sin(y),
					 0.0, 1.0, 0.0,
					 sin(y), 0.0, cos(y)); // 绕纵轴。

	mat3 matz = mat3(cos(z), sin(z), 0.0,
					 -sin(z), cos(z), 0.0,
					 0.0, 0.0, 1.0); // 绕前后轴。

	return maty * matx * matz; // 三个旋转合成。
}

// --- 空间扭曲：越靠近黑洞中心，光线被拉得越厉害 ---
void WarpSpace(inout vec3 eyevec, inout vec3 raypos){
	vec3 origin = vec3(0.0, 0.0, 0.0); // 黑洞中心。

	float singularityDist = distance(raypos, origin); // 到中心的距离。
	float warpFactor = 1.0 / (singularityDist * singularityDist + 0.000001); // 距离平方倒数，中心处极大。

	vec3 singularityVector = normalize(origin - raypos); // 指向中心的方向。

	float warpAmount = 0.06; // 扭曲强度。

	eyevec = normalize(eyevec + singularityVector * warpFactor * warpAmount); // 光线方向被拉向中心。
}

// --- 三维噪声：和主世界那份同源，按合同加 `End` 前缀以区分同名 ---
float EndCalculate3DNoise(vec3 position){
	vec3 p = floor(position); // 整数格。
	vec3 b = curve(fract(position)); // 格内偏移并平滑。

	vec2 uv = 17.0 * p.z + p.xy + b.xy; // 三维到二维的坐标分配。
	vec2 rg = textureLod(noisetex, (uv + 0.5) / 64.0, 0.0).zx; // 读噪声两个通道。

	return mix(rg.x, rg.y, b.z); // 按高度插值。
}

// --- 云状分形噪声：四层不同频率叠加，供吸积盘细节使用 ---
float CalculateCloudFBM(vec3 position, vec3 shift){
	const int octaves = 4; // 层数。
	const float octAlpha = 0.87; // 每层权重衰减。
	const float octScale = 2.5; // 每层频率放大。
	const float octShift = (octAlpha / octScale) / octaves; // 层间偏移。

	float accum = 0.0; // 累积噪声。
	float alpha = 0.5; // 当前层权重。

	for (int i = 0; i < octaves; i++) { // 逐层叠加。
		accum += alpha * EndCalculate3DNoise(position); // 加这一层。
		position = (position + shift) * octScale; // 抬高频率并加位移。
		alpha *= octAlpha; // 权重衰减。
	}

	return accum + octShift; // 返回归一化后的噪声。
}

float pcurve(float x){
	float x2 = x * x; // 平方。
	return 12.207 * x2 * x2 * (1.0 - x); // 四次方乘线性衰减，得到环带的径向轮廓。
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
				#ifdef OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE // 细节沿纬度分布时用方位角。
					vec3 discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5; // 盘坐标带方位角。
					float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.1, 0.07, 0.0)); // 高质量云噪声。
				#else // 默认细节只沿半径与高度分布。
					vec3 discCoord = vec3(r, 0.0, h * 0.1) * 3.5; // 盘坐标不带方位角。
					float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.03, 0.05, 0.0)); // 高质量云噪声。
				#endif
				fbm = fbm * fbm; // 平方。
				fbm = fbm * fbm; // 再平方，拉开明暗。

				density *= fbm * dr; // 噪声乘回径向轮廓。

				float gr = 1.0 - radialGradient; // 反径向。
				gr = gr * gr; // 平方。
				float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮的辉光。
				vec3 glow = Blackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。

				#ifdef OMNI_ACCRETIONDISC_DOPPLER_EFFECT // 多普勒效应：一侧更亮。
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
				#ifdef OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE // 细节沿纬度分布。
					vec3 discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5; // 带方位角的盘坐标。
					float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.1, 0.07, 0.0)); // 高质量云噪声。
				#else // 默认不带方位角。
					vec3 discCoord = vec3(r, 0.0, h * 0.1) * 3.5; // 盘坐标。
					float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.03, 0.05, 0.0)); // 高质量云噪声。
				#endif

				float fbm2 = fbm * fbm; // 平方。
				density *= fbm2 * fbm2 * fbm; // 噪声五次方乘回密度。
				density *= dr; // 再乘径向轮廓。

				float gr = 1.0 - radialGradient; // 反径向。
				gr = gr * gr; // 平方。
				float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮。
				vec3 glow = Blackbody(2700.0 + glowStrength * 50.0) * glowStrength; // 按辉光强度取黑体色。

				#ifdef OMNI_ACCRETIONDISC_DOPPLER_EFFECT // 多普勒效应。
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

// --- 末地雾：按视线方向与行星相位算出一层很淡的定向雾 ---
// 为什么用行星相位而不是距离：末地的雾来自背景行星的散射，方向与相位决定它的浓淡。
vec3 EndFog(float dist, vec3 worldDir){
	float VdotL = dot(worldShadowVector, worldDir); // 视线与光方向夹角余弦。

	float angleX = -1.57079633 + (0.2 * sin(timeFactor + 3.0) - 0.1) - 0.008 * sin(timeFactor + 4.7); // 俯仰角，比行星多一项。
	float angleY = timeFactor; // 偏航角。

	mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
	mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
	mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。

	worldDir = eyeRoataionMatrix * worldDir; // 视线转到相位坐标系。

	dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
	float h = abs(worldDir.z) * dist * 0.03; // 沿视线方向的等效高度。
	float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。

	float storm = MiePhaseFunction(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分：米氏相位乘行星相位。
	float haze = 0.25; // 不带方向的雾霭基准部分。
	// 两个密度选项来自 Eclipse `lib/settings.glsl:911-912`（`END_STORM_DENSTIY`、`END_HAZE_DENSTIY`）；
	// 默认都为一，缩放后相加与原来的单一密度逐位等价，画面不变。
	float density = fogDepth * (storm * OMNI_END_FOG_STORM_DENSITY + haze * OMNI_END_FOG_HAZE_DENSITY); // 两层分别缩放后相加。

	density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。

	return vec3(density * 1e-5 * OMNI_SUNLIGHT_INTENSITY); // 换算到管线单位并乘阳光强度。
}

// --- 末地主岛光源：把 END_LIGHT_POS 当成悬在主岛上方的点光源，按距离与夹角照亮表面并给高光 ---
// 出处：位置 `lib/settings.glsl:419`、视野角 `:420`、开关 `:421`；Eclipse 在 `dimensions/composite.fsh:509` 按
//   像素到光源重算光方向（`normalize(END_LIGHT_POS-(feetPlayerPos+cameraPosition))`），近处表面受光方向各不相同。
// 与 Eclipse 的取舍：Eclipse 另建一盏阴影相机（`dimensions/begin.csh:100-111`，近十五远二百五十六、视野角七十七），
//   需要计算着色器与附加缓冲；这里在合成零号按点光源解析照亮，距离窗与视野角照 Eclipse，衰减形状是本项目的近似。
// 调用前提：`cameraPosition`、`END_LIGHT_POS` 已可用，`Blackbody`、`Fd_Burley`、`SpecularGGX` 已由 `common/math.glsl` 提供。
vec3 EndIslandLighting(vec3 worldPos, vec3 normal, vec3 viewDir, vec3 albedo, float roughness, float f0, float metalness){
	vec3 lightVec = END_LIGHT_POS - (worldPos + cameraPosition); // 表面指向光源的向量，`worldPos` 是相机相对世界坐标。
	float lightDist = length(lightVec); // 到光源的距离。
	vec3 lightDir = lightVec / max(lightDist, 1e-4); // 单位光方向，防除零。

	// 距离窗：近十五远二百五十六照 Eclipse 的灯（`begin.csh:100-101`），两端各淡出一段，避免出现硬边。
	float distFade = smoothstep(15.0, 40.0, lightDist) * (1.0 - smoothstep(200.0, 256.0, lightDist)); // 距离窗。
	// 锥形窗：光轴竖直向下，方向与轴夹角超过 `OMNI_END_LIGHT_FOV` 一半就淡出；Eclipse 用这个角度构造透视灯。
	float cosAxis = dot(normalize((worldPos + cameraPosition) - END_LIGHT_POS), normalize(-END_LIGHT_POS)); // 表面相对光轴的余弦。
	float cosFov = cos(radians(OMNI_END_LIGHT_FOV * 0.5)); // 视野角一半的余弦，就是锥边的阈值。
	float cone = smoothstep(cosFov, min(cosFov * 1.05 + 0.01, 0.999), cosAxis); // 锥内为一，锥外为零。
	// 距离衰减：Eclipse 用阴影图而不是解析衰减，这里用平方反比近似，参考距离取灯的悬挂高度，让主岛附近接近一。
	float falloff = distFade * cone * OMNI_END_LIGHT_BRIGHTNESS / (1.0 + lightDist * lightDist / 36000.0); // 总衰减。

	vec3 lightColor = Blackbody(6000.0) * 0.3; // 与末地太阳同色温、同强度尺度（合成里用 `Blackbody(6000)` 与系数零点三）。
	vec3 result = albedo * lightColor * falloff * Fd_Burley(normal, -viewDir, lightDir, roughness); // 漫反射乘底色。

	float highlightGGX = SpecularGGX(normal, -viewDir, lightDir, clamp(roughness, 0.0015, 0.9), f0); // 与阳光同一套 GGX 高光。
	highlightGGX *= saturate(4.0 - roughness * 3.5); // 光滑面高光更强。
	highlightGGX *= 0.07; // 与阳光高光同一强度尺度。
	result += mix(vec3(1.0), albedo, vec3(metalness)) * lightColor * falloff * highlightGGX; // 金属面高光带底色。

	return result; // 交回可直接叠加到线性光照的颜色。
}

// --- 末地假天空反射：屏幕反射没命中时用末地天空兜底 ---
// 为什么加 `End` 后缀：主世界 `effects/reflection/reflection.glsl` 另有一份形状不同的 `ComputeFakeSkyReflection`，按合同区分开。
// 调用前提：`worldShadowVector` 已由绘制主体声明。
vec3 ComputeFakeSkyReflectionEnd(vec3 reflectWorldDir, bool isSmooth){
	vec3 sky = vec3(0.0); // 累积的反射天空颜色。

	BlackHole_AccretionDisc_Reflection(sky, reflectWorldDir, worldShadowVector); // 吸积盘反射版。

	PlanetEnd2(sky, vec3(0.0), reflectWorldDir, worldShadowVector); // 行星与光环。

	return sky / MAIN_OUTPUT_FACTOR; // 换算到管线存储单位。
}

// --- 末地水面折射：与主世界 `RefractSampleOnce` 形状不同，加 `End` 后缀区分 ---
// 与主世界版的差别：末地用 `EndFog` 补雾，不再走体积雾与地表散射，也不带时间因子与云影参数。
// 调用前提：`texCoord`、`texelCoord`、水面波法线与坐标换算已由绘制主体引入。
void RefractSampleOnceEnd(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist){
	vec2 refractCoord = texCoord; // 默认不折射，用原屏幕坐标。

	float waterDeep = opaqueDist - waterDist; // 水面到水底的厚度。

	if (mask.water > 0.5){ // 水面本身：用波法线偏移。
		float NdotU = dot(normal, gbufferModelView[1].xyz) + float(isEyeInWater == 1) * 2.0; // 法线朝向与水下判断。
		vec3 wavesNormal = GetWavesNormal(worldPos + cameraPosition, step(0.05, NdotU) * 18.0).xzy; // 求波法线并换到竖直轴朝上的坐标。
		vec4 wnv = gbufferModelView * vec4(wavesNormal.xyz, 0.0); // 波法线转到视空间。
		vec3 wavesNormalView = normalize(wnv.xyz); // 归一化。

		vec4 nv = gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0); // 平水面法线转到视空间。
		nv.xyz = normalize(nv.xyz); // 归一化。

		refractCoord = nv.xy - wavesNormalView.xy; // 两种法线的差就是折射偏移方向。
		refractCoord *= saturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深折射越强。
		refractCoord += texCoord; // 加到原坐标上。
	}else{ // 玻璃等透明面：用整段折射方向。
		vec3 refractDir = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
		refractDir = refractDir / saturate(dot(refractDir, -normal)); // 归一化到视线方向。
		refractDir *= saturate(waterDeep * 2.0) * 0.125; // 按厚度缩放。

		vec4 refractPos = vec4(viewPos + refractDir, 0.0); // 折射后的视空间位置。
		refractPos = gbufferProjection * refractPos; // 投影到裁剪空间。

		refractCoord = refractPos.xy / refractPos.w * 0.5 + 0.5; // 转成屏幕坐标。
	}

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素深度。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点深度。
	if(refractDepth < currentDepth) refractCoord = texCoord; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(texCoord, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord, 0.0).rgb); // 读回折射后的场景颜色。

	vec3 rViewPos = ViewPos_From_ScreenPos(refractCoord, textureLod(depthtex1, refractCoord, 0.0).x); // 折射点视空间位置。
	vec3 rWorldDir = normalize(mat3(gbufferModelViewInverse) * rViewPos); // 折射点世界方向。

	color += EndFog(max(length(rViewPos) - waterDist, 0.0), rWorldDir) / MAIN_OUTPUT_FACTOR; // 补一段末地雾。
}

// --- 末地彩色玻璃吸收：与主世界同名函数多一个参数不同，加 `End` 后缀区分 ---
void TransparentAbsorptionEnd(inout vec3 color, vec4 stainedGlassAlbedo){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, vec3(pow(stainedGlassAlbedo.a, 0.2)))); // 按不透明度吸收。
}
#endif // 文件守卫结束。
