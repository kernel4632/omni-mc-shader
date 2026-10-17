/*
水下体积雾：在水下沿视线步进阴影可见性并叠焦散，画出汇聚的蓝色光柱。
来源：iterationT `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl` 一比一移植。
职责：`CalculateUnderwaterCaustics` 取一份范围很窄的焦散值，`UnderwaterVolumetricFog` 沿视线累加光柱。
调用位置：由 `effects/fog/fog.glsl` 引入；`effects/world/composite_scene.glsl` 与
  `effects/reflection/reflection.glsl` 在水下调用 `UnderwaterVolumetricFog`。
可复制示例：`vec3 shafts = UnderwaterVolumetricFog(vec3(0.0), worldPos, worldDir, globalCloudShadow);`
调用前提：由 `effects/fog/fog.glsl` 在引入 `effects/water/water.glsl` 之后引入，所以水下雾选项
  `OMNI_UNDERWATER_FOG` 与水雾密度选项可用；波法线来自 `effects/shadow/shadow.glsl`。
关键设计原因与取舍：原 `UnderwaterVolumetricFog.glsl` 里的 `CalculateWaterCaustics` 与
  `effects/shadow/shadow.glsl` 的同名函数内容不同，按移植合同改名 `CalculateUnderwaterCaustics`，函数体不变；
  另外按 Eclipse `composite3.fsh` 补上 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER`：手持光源也照亮水体，
  颜色与范围取自手持物品（`effects/lighting/lpv.glsl` 的 `omniLpvHandLight`），按水的分波段吸收衰减。
*/
#ifndef OMNI_UNDERWATER_FOG_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_UNDERWATER_FOG_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 水下焦散：水下体积雾需要一份范围很窄的焦散值来收窄光柱 ---
// 说明：原 `UnderwaterVolumetricFog.glsl` 里的 `CalculateWaterCaustics` 与 `effects/shadow/shadow.glsl` 里的同名函数内容不同，
// 同名会冲突，按移植合同九点五节的处理方式改名，函数体保持不变；两份都记入偏离记录。
float CalculateUnderwaterCaustics(vec3 worldPos){
	worldPos.xyz += cameraPosition; // 相机相对世界位置补上相机位置，换成绝对坐标。

	vec3 lookupCenter = worldPos; // 从当前位置向上找波面。
	lookupCenter.y += 1.0; // 抬高一米到水面上方。

	vec3 wavesNormal = GetWavesNormalFromTex(lookupCenter, worldShadowVector).xzy; // 读波法线并换到竖直轴朝上的坐标。
	vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal.xyz, 1.0); // 竖直光线被波面折射后的方向。
	vec3 collisionPoint = lookupCenter - refractVector / refractVector.y; // 光线与水平面的交点。

	float dist = distance(collisionPoint, worldPos); // 交点到当前点的距离。

	return dist * 2.8 + 0.2; // 距离越近焦散越强，返回一个零到一附近的值。
}


// 水下体积雾：在水下沿视线步进阴影可见性，乘焦散与水吸收，得到汇聚的蓝色光柱。
// 输入是起点、终点、世界方向与全局云影；返回光柱颜色。
// 为什么限制四十米：光柱来自水面缝隙，远处既看不清又贵，截断到四十米内。
vec3 UnderwaterVolumetricFog(vec3 startPos, vec3 endPos, vec3 worldDir, float globalCloudShadow){
	const float range = 40.0; // 光柱的累积范围。

	float startDist = length(startPos); // 起点到相机的距离。
	if(startDist > range) return vec3(0.0); // 起点已经在范围外，不画光柱。

	endPos = mix(worldDir * range, endPos, step(length(endPos), range)); // 终点超过范围就截断到范围内。

	float rayDist = distance(startPos, endPos); // 这条射线在范围里的长度。
	vec3 rayDir = (endPos - startPos) / rayDist; // 射线方向。

	const float steps = OMNI_VFOG_QUALITY; // 采样次数来自体积雾质量。
	const float stepLength = range / steps; // 每段长度。

	float noise = BlueNoiseTemporal().y; // 每帧变化的抖动。

	vec3 result = vec3(0.0); // 累加的光柱颜色。
	#ifdef OMNI_LPV_FOG_LIGHT
		#ifdef OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER // 雾照明-水下手持光：手里的火把等也照亮水体。
			vec3 handFog = vec3(0.0); // 累加的手持光颜色。
		#endif
	#endif

	for (float i = 0.0; i < steps; i++){ // 沿视线逐步前进。
		float rayLength = (i + noise) * stepLength; // 当前位置，起点加抖动量。
		vec3 rayPos = startPos + rayDir * rayLength; // 世界位置。

		if(startDist + rayLength > range || rayLength > rayDist) break; // 超出范围就停止。

		vec3 shadowProjPos = ShadowScreenPos_From_WorldPos_Distorted(rayPos + gbufferModelViewInverse[3].xyz); // 投到阴影图，含边缘压缩。
		#ifdef MC_GL_VENDOR_NVIDIA
			vec3 shadow = vec3(step(shadowProjPos.z + 1e-06, textureLod(shadowtex1, shadowProjPos.xy, 0).x)); // 受光则由实心遮挡图判定。
		#else
			vec3 shadow = vec3(step(shadowProjPos.z + 1e-06, textureLod(shadowtex0, shadowProjPos.xy, 0).x)); // 受光则由遮挡图判定。
		#endif

		rayLength += startDist; // 距离补上起点偏移。

		float caustics = CalculateUnderwaterCaustics(rayPos); // 该点焦散强度。
		shadow *= caustics * caustics * caustics; // 三次方让焦散更集中。
		shadow /= max(3.0, rayLength * 0.1); // 越远越弱。
		#ifdef OMNI_UNDERWATER_FOG // 有水下雾时按水的分波段吸收衰减光柱。
			shadow *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * OMNI_WATER_FOG_DENSITY)); // 红衰减最快，光柱因此偏蓝。
		#endif

		result += shadow; // 累加。

		#ifdef OMNI_LPV_FOG_LIGHT
			#ifdef OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
				// 手持光源在该点留下的光，颜色与范围取自手持物品，离玩家越远越弱。
				vec3 handLight = omniLpvHandLight(heldItemId, rayPos) + omniLpvHandLight(heldItemId2, rayPos); // 两手光源的光色乘距离衰减。
				handLight *= pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(rayLength * 0.04 * OMNI_WATER_FOG_DENSITY)); // 与光柱同一套分波段吸收，近处暖、远处青蓝。
				handFog += handLight; // 累加。
			#endif
		#endif
	}
	result *= range / steps; // 取平均。

	vec3 lightVector = refract(worldShadowVector, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折。
	float LdotV = dot(lightVector,worldDir); // 光方向与视线的夹角。
	float phace = MiePhaseFunction(0.7, LdotV); // 前向相位，正对阳光时更亮。

	result *= colorShadowlight * (0.04 * phace * OMNI_SUNLIGHT_INTENSITY * OMNI_UNDERWATER_VFOG_DENSITY); // 乘直射光色、相位与强度。

	#ifdef OMNI_UNDERWATER_FOG // 有水下雾时把光柱染成水色。
		result *= vec3(0.2, 0.65, 1.0);
	#endif

	result *= globalCloudShadow; // 按全局云影压暗。

	#ifdef OMNI_LPV_FOG_LIGHT
		#ifdef OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER
			// 手持光不随阳光相位与云影变化，所以加在那些系数之后；亮度按 Eclipse `composite3.fsh:478` 的系数
			// （零点二乘百分之一定标缩到零点零零零四），再平均到整个范围，得到靠近火把的一圈暖光。
			result += handFog * (range / steps) * (OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 0.0004);
		#endif
	#endif

	return result; // 返回光柱颜色。
}
#endif // OMNI_UNDERWATER_FOG_INCLUDED 结束。
