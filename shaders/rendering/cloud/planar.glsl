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
#include "/gfx/cloud.glsl"
// 由 effects/cloud/cloud.glsl 在三维云噪声可用的阶段打开；其它程序整段不编译。
#ifdef OMNI_CLOUD_DENSITY_PASS
// --- 三次模糊噪声：平面云专用，与共用数学里的版本返回类型和纹理都不同，按合同留在这里一份 ---
float BicubicBlurNoise(vec2 coord) { return gfx_bicubic_blur_noise(coord, noisetex); }
// 双线性噪声：平面云细节用的普通采样。
float BilinearNoise(vec2 position) { return gfx_bilinear_noise(position, noisetex); }
// 平面云的扭曲：几层噪声叠出缓慢起伏的偏移量，让云块边缘不平整。
float GetPlanarCloudsDistortion(vec2 position, vec2 windDirection) { return gfx_planar_distortion(position, windDirection, noisetex); }
// 平面云密度：位置先被扭曲，再叠多层旋转噪声得到云块。
float GetPlanarCloudsDensity(vec2 position, vec2 windDirection) { return gfx_planar_density(position, windDirection, noisetex, OMNI_PLANAR_NOISE_SCALE, OMNI_PLANAR_COVERAGE); }
// 平面云的光照密度：与上面同理，但用双线性噪声且层数更少，专供光照估计。
float GetPlanarCloudsLightingDensity(vec2 position, vec2 windDirection) { return gfx_planar_lighting_density(position, windDirection, noisetex, OMNI_PLANAR_NOISE_SCALE, OMNI_PLANAR_COVERAGE); }
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
