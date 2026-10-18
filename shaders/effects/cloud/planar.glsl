/*
平面云：在固定高度的一层平面上铺云，用扭曲与多层旋转噪声造出云块，比体积云便宜且连续。
来源 iterationT `PlanarClouds.glsl`。
调用位置：由 `effects/cloud/cloud.glsl` 引入；只在读得到三维云噪声的延迟三号、七号、八号参与编译，其它程序整段跳过。
可复制示例：
    `PlanarClouds(color, worldDir, camera, dither, cloudTransmittance);`
调用前提：平面云选项由 `effects/cloud/cloud.glsl` 定义；噪声贴图、球面求交、米氏相位与黄金角由加载器与 `common/math.glsl` 提供；
    空气透视 `GetSkyRadianceToPoint` 由 `effects/sky/sky.glsl` 提供。
设计原因与取舍：平面云是 iterationT 独有的层，不受每日天气表影响，只读平面云自己的选项；
    密度用三次模糊噪声、光照估计用更便宜的双线性噪声与更少层数，避免光照时重复跑高成本采样。
*/
#ifndef OMNI_CLOUD_PLANAR_INCLUDED
#define OMNI_CLOUD_PLANAR_INCLUDED
#ifdef OMNI_CLOUD_DENSITY_PASS // 由 effects/cloud/cloud.glsl 在三维云噪声可用的阶段打开；其它程序整段不编译。
// --- 三次模糊噪声：平面云专用，与共用数学里的版本返回类型和纹理都不同，按合同留在这里一份 ---
float BicubicBlurNoise(vec2 coord){
	coord = coord * (1.2e-4 * 64.0) - 0.5; // 噪声贴图按每方块一点二万分之一缩放。
	vec2 p = floor(coord); // 整数像素。
	vec2 f = coord - p; // 小数偏移。
	vec2 ff = f * f; // 偏移平方。
	vec4 w0; // 两个方向的前两个权重。
	vec4 w1; // 两个方向的后两个权重。
	w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重是反向偏移的立方。
	w1.yw = ff * f; // 第四个权重是偏移立方。
	w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
	w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重由总和为六推出。
	vec4 s = w0 + w1; // 每对权重和。
	vec4 c = p.xxyy + vec2(-0.5, 1.5).xyxy + w1 / s; // 每对合并成一次双线性采样的位置。
	c *= 1.0 / 64.0; // 换回零到一坐标。
	vec2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
	return mix(mix(textureLod(noisetex, c.yw, 0.0).w, textureLod(noisetex, c.xw, 0.0).w, m.x),
			   mix(textureLod(noisetex, c.yz, 0.0).w, textureLod(noisetex, c.xz, 0.0).w, m.x),
			   m.y); // 四次双线性采样得到十六像素的三次模糊，取第四通道。
}
// 双线性噪声：平面云细节用的普通采样。
float BilinearNoise(vec2 position) {
	return textureLod(noisetex, position * 1.2e-4, 0.0).w; // 与三次版同一缩放，取第四通道。
}
// 平面云的扭曲：几层噪声叠出缓慢起伏的偏移量，让云块边缘不平整。
float GetPlanarCloudsDistortion(vec2 position, vec2 windDirection){
	float density = BilinearNoise(position - windDirection); // 第一层。
	float scale = 4.0; // 起始频率。
	for (int i = 0; i < 3; i++, scale *= 3.0){ // 三层，频率逐级乘三。
		density += BilinearNoise(scale * (position - windDirection * fsqrt(scale))) * pow(scale, -1.3); // 每层按频率的负一点三次方衰减。
	}
	return density; // 返回扭曲量。
}
// 平面云密度：位置先被扭曲，再叠多层旋转噪声得到云块。
float GetPlanarCloudsDensity(vec2 position, vec2 windDirection){
	position *= OMNI_PLANAR_NOISE_SCALE; // 按选项缩放位置。
	float distortion = GetPlanarCloudsDistortion(position, windDirection); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle)); // 按黄金角旋转并缩放的矩阵。
	float density = BicubicBlurNoise(position - windDirection); // 第一层密度。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 6.0; i++, rot *= rotateGoldenAngle){ // 六层。
		float scale = fsqrt(i); // 每层频率取平方根。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同，云块更有方向感。
		float weight = pow(octScale, -0.85 * i); // 每层权重按频率衰减。
		density += BicubicBlurNoise(noisePosition) * weight; // 累加这一层。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均到零到一附近。
	density = saturate(density + OMNI_PLANAR_COVERAGE - 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方让边缘更收。
}
// 平面云的光照密度：与上面同理，但用双线性噪声且层数更少，专供光照估计。
float GetPlanarCloudsLightingDensity(vec2 position, vec2 windDirection){
	position *= OMNI_PLANAR_NOISE_SCALE; // 按选项缩放位置。
	float distortion = GetPlanarCloudsDistortion(position, windDirection); // 取扭曲量。
	position += distortion * 50.0; // 用扭曲量偏移位置。
	const float octScale = 2.8; // 每层频率倍数。
	const mat2 rotateGoldenAngle = octScale * mat2(cos(goldenAngle), -sin(goldenAngle), sin(goldenAngle), cos(goldenAngle)); // 按黄金角旋转并缩放的矩阵。
	float density = BicubicBlurNoise(position - windDirection); // 第一层。
	mat2 rot = rotateGoldenAngle; // 旋转矩阵逐步累乘。
	float weights = 1.0; // 权重和。
	for (float i = 1.0; i <= 3.0; i++, rot *= rotateGoldenAngle){ // 三层，比密度版少。
		float scale = fsqrt(i); // 每层频率取平方根。
		vec2 noisePosition = rot * (position - windDirection * scale); // 旋转并随风偏移。
		noisePosition *= vec2(1.0 - 0.35 * scale, 1.0 + 0.05 * scale); // 两个方向拉伸不同。
		float weight = pow(octScale, -0.85 * i); // 每层权重。
		density += BilinearNoise(noisePosition) * weight; // 用便宜的噪声累加。
		weights += weight; // 累加权重。
	}
	density /= weights; // 平均。
	density = saturate(density + OMNI_PLANAR_COVERAGE - 1.0); // 用云量抬阈值。
	density *= exp(-distortion); // 扭曲大的地方压薄。
	return density * density; // 平方收口。
}
// 平面云：视线与云平面求一次交点，再沿光方向叠几层光照密度估遮挡。
// 调用前提：`color` 已算好天空颜色（会被就地修改），`cloudTransmittance` 是体积云留下的透过率。
// 为什么不受每日天气影响：平面云是 iterationT 独有的层，Eclipse 的每日天气表没有它，所以这里只读 `OMNI_PLANAR_*`。
void PlanarClouds(inout vec3 color, vec3 worldDir, vec3 camera, float dither, float cloudTransmittance){
	float planetRadius = atmosphereModel_bottom_radius * 1e3; // 行星半径从大气常数换成米。
	vec3 rayStartPos = vec3(0.0, planetRadius + cameraPosition.y, 0.0); // 相机在行星球上的位置。
	float intersection = RaySphereIntersection(rayStartPos, worldDir, planetRadius + OMNI_PLANAR_ALTITUDE).y; // 视线与云平面的远交点。
	if (intersection > 0.0){ // 只有真的相交才画。
		float wind = 2.5 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 随风移动的时间量。
		vec2 windDirection = vec2(-wind, wind * 0.2); // 主风向与一点横向分量。
		float VdotL = dot(worldDir, worldShadowVector) * 0.5 + 0.5; // 视线与光方向夹角余弦映射到零到一。
		vec3 centerPosition = worldDir * intersection; // 交点相对相机的方向。
		vec2 samplePosition = centerPosition.xz + cameraPosition.xz; // 交点的地表水平坐标。
		cloudTransmittance = min(GetPlanarCloudsDensity(samplePosition, windDirection) * cloudTransmittance * 40.0, 0.9); // 平面云的不透明度。
		#ifdef OMNI_VOLUMETRIC_CLOUDS // 与体积云叠加时按雨天压薄平面云。
			cloudTransmittance *= 1.0 - wetness; // 雨天让平面云让位给体积云。
		#endif
		if (cloudTransmittance > 1e-5){ // 只有云确实可见才算光照。
			float stepLength = mix(150.0, 0.0, worldShadowVector.z); // 沿光方向的起始步长，随光方向变化。
			samplePosition += stepLength * dither * worldShadowVector.xy; // 起点加抖动，减少条带。
			float lightingDepth = 0.0; // 沿光方向累积的遮挡密度。
			for (int i = 0; i < 4; i++, samplePosition += worldShadowVector.xy * stepLength, stepLength *= 1.5){ // 四步，步长逐步放大。
				lightingDepth += GetPlanarCloudsLightingDensity(samplePosition, windDirection) * stepLength; // 累加遮挡。
			}
			float sunlightEnergy = 1.0 / (lightingDepth + 1.0); // 遮挡越少阳光越强。
			float powderFactor = exp2(-cloudTransmittance * (worldShadowVector.y * 5.0 + 0.5)); // 粉末效应：正对光时云边发亮。
			sunlightEnergy *= MiePhaseFunction(powderFactor * 0.8, VdotL * 0.5 + 0.5); // 乘米氏相位。
			sunlightEnergy *= MiePhaseFunction(0.9, VdotL) * 0.4 + 1.0; // 再加强前向散射。
			vec3 cloudColor = colorShadowlight * (sunlightEnergy * 6.0); // 乘直射光色。
			float skylightEnergy = exp2(-cloudTransmittance * 0.15); // 环境光透过。
			cloudColor += colorSkylight * (skylightEnergy * 0.2); // 加上天光色。
			cloudTransmittance *= exp2(-(length(centerPosition) + 2e3) * 4e-5); // 远处平面云也按距离压薄。
			vec3 atmoPoint = camera + centerPosition * 0.001; // 交点附近一点。
			vec3 transmittance; // 大气透过率输出。
			vec3 aerialPerspective = GetSkyRadianceToPoint(camera, atmoPoint, worldSunVector, -worldSunVector, transmittance); // 这段空气的散射。
			color *= (1.0 - cloudTransmittance); // 天空被云挡掉的部分。
			color += (cloudColor * transmittance + aerialPerspective) * cloudTransmittance; // 加上云颜色与空气散射。
		}
	}
}
#endif // 云密度阶段结束。
#endif // 文件守卫结束。
