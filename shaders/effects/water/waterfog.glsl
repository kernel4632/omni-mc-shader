/*
水雾：水下的雾色与随距离衰减，把不透水面与水面之间的距离差算进雾里。
来源 iterationT 水下雾段。
调用位置：由 `effects/water/water.glsl` 引入；合成阶段处理半透明水面时调用 `WaterFog`。
可复制示例：`WaterFog(color, viewDir, opaqueDist, waterDist, normal, materialMask);`
设计原因与取舍：水雾按“水”这一主体归到 `effects/water/` 文件夹，和折射、吸收分开，各自可读；
    雾密度由入口选项 `OMNI_WATER_FOG_DENSITY` 控制。
*/
#ifndef OMNI_WATERFOG_INCLUDED
#define OMNI_WATERFOG_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 水下与水后雾：按距离做分波段衰减并向雾色靠拢 ---
// 调用位置：`rendering/composite.glsl`；示例见文件头。
// 参数里的 `occludedWater` 表示视线被半透明玻璃挡住的水，`totalInternalReflection` 表示发生全反射。
// 为什么区分是否在水下：水面之上看水下与整只眼睛浸在水里，雾色与散射方向都不同。
void WaterFog(inout vec3 color, vec3 viewDir, float opaqueDist, float waterDist, vec3 normal, MaterialMask mask, float occludedWater, float waterSkylight, float totalInternalReflection, vec3 shadowLightVector, vec3 shadowlightColorInput, vec3 skylightColorInput){
	float distDiff = opaqueDist - waterDist; // 水面到水底的真实厚度。
	waterDist = isEyeInWater == 0 ? // 不在水下时，实际雾距离是水体厚度。
				mix(distDiff, min(distDiff * 0.3, 6.0), occludedWater) : // 隔着玻璃时厚度打折并封顶，避免过浓。
				mix(waterDist, opaqueDist, mask.stainedGlass); // 在水下且隔着玻璃时改用不透明距离。

	float eyeWaterDepth = saturate(float(eyeBrightnessSmooth.y) / 120.0 - 0.8); // 眼睛离水面的深度感，由天空光反推。
	waterDist = max(waterDist, totalInternalReflection * eyeWaterDepth * 50.0); // 全反射时把雾距离拉长，形成亮环。

	vec3 shadowVectorRefracted = refract(-shadowLightVector, gbufferModelView[1].xyz, 1.0 / WATER_REFRACT_IOR); // 阳光在水面折射后的方向。

	vec3 waterFogColor = mix(vec3(0.05, 0.6, 1.0), vec3(0.3, 0.9, 1.5), mask.ice); // 冰面偏亮青，普通水偏青。
	waterFogColor = mix(waterFogColor, vec3(0.5), wetness * 0.6); // 越湿雾色越中性。

	waterFogColor *= dot(vec3(0.33333), skylightColorInput); // 乘天光色，雾色随环境变化。

	if (isEyeInWater == 0){ // 水面之上看水下。
		waterFogColor *= 0.04 - wetness * 0.032; // 水面之上的雾很淡，雨天更淡。
		waterFogColor *= waterSkylight; // 再乘该处水面接收的天光。

		vec3 l = normalize(reflect(viewDir, normal)); // 视线在水面的反射方向。
		vec3 h = normalize(l - viewDir); // 反射方向与视线的半程。
		float F = saturate(dot(normal, l)) * saturate(dot(l, h) * 1.5 - 0.5); // 一个简化的菲涅耳权重。
		float scatter = 3.0 * F * pow(dot(shadowVectorRefracted, viewDir) * 5.0 + 5.2, -1.4); // 逆光时的散射更强。

		waterFogColor = mix(waterFogColor, shadowlightColorInput * waterFogColor * 3.0, scatter * saturate(1.0 - wetness - occludedWater)); // 逆光散射叠上去，湿地或隔玻璃时减弱。
	}else{ // 整只眼睛在水里。
		waterFogColor *= 0.02 - wetness * 0.012; // 水下雾更淡。
		float scatter = 1.0 / (dot(shadowVectorRefracted, viewDir) * 5.0 + 5.1); // 朝向阳光的散射。
		vec3 waterSunlightScatter = shadowlightColorInput * scatter * waterFogColor * 2.0; // 阳光在水里的散射色。

		waterFogColor *= dot(viewDir, gbufferModelView[1].xyz) * 0.4 + 0.6; // 朝上看更亮。
		waterFogColor += waterSunlightScatter * (eyeWaterDepth * (1.0 - wetness * 0.6)); // 叠加阳光散射。
	}

	float fogDensity = isEyeInWater == 0 ? 0.29 : mask.ice * 0.96 + 0.04; // 基础雾密度，冰下更浓。
	float visibility = exp2(-waterDist * fogDensity * OMNI_WATER_FOG_DENSITY); // 按密度指数衰减得到可见度。

	visibility = clamp(visibility, 0.35 * mask.ice, 1.0); // 冰下留一个最低可见度。
	visibility = mix(visibility, 0.7, mask.hand); // 手持物只受七成雾影响，避免手被糊掉。

	vec3 attenuationColor = isEyeInWater == 0 ? vec3(0.2, 0.5, 0.7) : vec3(0.1, 0.6, 1.0); // 分波段衰减色，水下偏蓝。
	color *= pow(attenuationColor * 0.99, vec3(waterDist * (0.21 * float(isEyeInWater == 0) + 0.04) * OMNI_WATER_FOG_DENSITY)); // 红衰减最快，蓝最慢。

	color = mix(waterFogColor, color, visibility); // 用可见度在雾色与场景色之间混合。
}

#endif // 文件守卫结束。
