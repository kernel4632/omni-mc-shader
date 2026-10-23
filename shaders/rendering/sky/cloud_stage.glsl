/*
低分辨率体积云阶段的共用参数：延迟七号算云、延迟八号把云贴回天空，两边都需要同一套云高度、风与可见判据。
调用位置：`rendering/deferred_pass7.glsl` 与 `deferred_pass8.glsl` 的主函数，在 `cloud/cloud.glsl` 之后引入。
可复制示例：
    `vec2 cloudAltitude; vec3 windDirection; vec2 noise; vec3 camera; bool intersectsGround;`
    `CloudStageParameters(worldDir, cloudAltitude, windDirection, noise, camera, intersectsGround);`
设计原因与取舍：这些量只由天气、时间与相机高度决定，不是云算法本身；集中一份后两个程序口径一致，
    改云高度或风的换算时不会只改到一支。云的形状、光照与步进仍在 `gfx/cloud.glsl`。
*/
#ifndef OMNI_CLOUD_STAGE_INCLUDED // 只展开一次。
#define OMNI_CLOUD_STAGE_INCLUDED // 置上标记。

// 组装云阶段参数：晴雨两档高度按湿润度插值，风按时间推进，相机按地平线开关取高度。
// `intersectsGround` 由预计算大气查表给出，决定相机在云层下方时是否还能看到云。
void CloudStageParameters(vec3 worldDir, out vec2 cloudAltitude, out vec3 windDirection, out vec2 noise,
		out vec3 camera, out bool intersectsGround){
	#ifdef OMNI_ATMO_HORIZON // 与延迟三号主天空同一套相机高度与地平线开关。
		camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 有下限的相机高度。
		bool horizon = true; // 地平线方向也当作被行星挡住。
	#else
		camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 至少按海平面高度算。
		bool horizon = false; // 地平线方向按天空处理。
	#endif
	noise = BlueNoiseTemporal().xy; // 主画面用的逐帧蓝噪声。
	cloudAltitude = vec2(mix(OMNI_CLOUD_CLEAR_ALTITUDE, OMNI_CLOUD_RAIN_ALTITUDE, wetness)); // 晴雨两档云底高度。
	cloudAltitude.y += mix(OMNI_CLOUD_CLEAR_THICKNESS, OMNI_CLOUD_RAIN_THICKNESS, wetness); // 加上层厚得到云顶高度。
	float wind = 0.0005 * (frameTimeCounter * OMNI_CLOUD_SPEED + 10.0 * OMNI_CLOUD_TIME_OFFSET); // 云漂动的时间量。
	windDirection = vec3(1.0, wetness * 0.1 - 0.05, -0.4) * wind; // 云漂动的方向与位移。
	vec3 atmoTransmittance; // 大气透过率，本阶段不用，仅取云可见判据。
	GetSkyRadiance(camera, worldDir, worldSunVector, worldMoonVector, horizon, atmoTransmittance, intersectsGround); // 查表取可见判据。
}

#endif // 文件守卫结束。
