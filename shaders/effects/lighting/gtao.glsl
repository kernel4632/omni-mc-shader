/*
地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重，并做多弹射补偿。
来源 iterationT 地面真相环境遮蔽段。
调用位置：由 `effects/lighting/ambient.glsl` 引入；延迟主体 `RenderGISpatialFilter` 调用 `GroundTruthBasedAmbientOcclusion`，
    合成阶段调用 `GTAOMultiBounce` 给遮蔽补间接光。
可复制示例：
    `float ao = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal);`
    `vec3 aoColor = GTAOMultiBounce(gi.a, gbuffer.albedo);`
设计原因与取舍：遮蔽与全局光互相独立、开关也各自独立，拆成两个文件后可分别阅读和关闭。
*/
#ifndef OMNI_GTAO_INCLUDED
#define OMNI_GTAO_INCLUDED // 置上标记，后续再次引用直接跳过。
// 多弹射补偿放在通用库，这里只传入遮蔽与底色。
#include "/gfx/gi.glsl"
// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 调用前提：`texCoord`、`gbufferProjection`、`depthtex1` 已声明。
float GroundTruthBasedAmbientOcclusion(vec3 viewPos, vec3 viewDir, vec3 normal){
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else // 否则用空间噪声。
		vec2 noise = BlueNoise(); // 固定空间噪声。
	#endif
	const float steps = OMNI_GTAO_QUALITY; // 环绕视线的切片数。
	const float rSteps = 1.0 / steps; // 切片数倒数。
	const float sliceSteps = OMNI_GTAO_SLICE_QUALITY; // 每个切片的搜索步数。
	const float rSliceSteps = 1.0 / sliceSteps; // 步数倒数。
	const float falloffStart = OMNI_GTAO_FALLOFF_START; // 衰减起点。
	const float maxSampleRadius = OMNI_GTAO_MAX_RADIUS; // 屏幕半径上限。
	#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权开关。
		const float falloffZoffset = 1.7; // 深度方向放大系数。
	#endif
	float projFactor = 0.125 * gbufferProjection[1][1]; // 投影缩放系数。
	#if OMNI_GTAO_RADIUS_MODE == 0 // 世界半径模式。
		#ifdef DISTANT_HORIZONS // 有远景时衰减更慢。
			float radius = OMNI_GTAO_WORLD_RADIUS - viewPos.z * 0.02; // 世界半径随距离缩小。
		#else // 没有远景时衰减更快。
			float radius = OMNI_GTAO_WORLD_RADIUS - viewPos.z * 0.01; // 世界半径随距离缩小。
		#endif
		float sampleRadiusRaw = radius * projFactor / -viewPos.z; // 换成屏幕半径。
		float sampleRadius = min(sampleRadiusRaw, maxSampleRadius); // 上限。
		float falloff = sampleRadius * radius / sampleRadiusRaw; // 衰减距离。
	#else // 屏幕半径模式。
		const float sampleRadius = OMNI_GTAO_SCREEN_RADIUS; // 固定屏幕半径。
		float falloff = sampleRadius / projFactor * -viewPos.z; // 换算成世界衰减距离。
	#endif
	float ao = 0.0; // 累积的遮蔽。
	for (float i = 0.0; i < steps; i++){ // 逐切片。
		float sliceAngle = (i + noise.x) * rSteps * PI; // 切片角度，只扫半圈因为两侧对称。
		vec3 sliceDir = vec3(cos(sliceAngle), sin(sliceAngle), 0.0); // 切片方向。
		vec3 orthoSliceDir = sliceDir - dot(sliceDir, viewDir) * viewDir; // 切片方向正交到视线的分量。
		vec3 axis = cross(sliceDir, viewDir); // 切片平面法向。
		vec3 projNormal = normal - dot(normal, axis) * axis; // 法线投影到切片平面。
		float rProjNormalLength = inversesqrt(dot(projNormal, projNormal)); // 投影长度倒数。
		float cosNormalAngle = saturate(dot(projNormal, viewDir) * rProjNormalLength); // 投影法线与视线夹角余弦。
		float normalAngle = sign(dot(orthoSliceDir, projNormal)) * facos(cosNormalAngle); // 带符号的法线角。
		vec2 minCosHorizonAngle = cos(vec2(normalAngle + hPI, normalAngle - hPI)); // 两侧地平线角的下限。
		vec2 maxCosHorizonAngle = minCosHorizonAngle; // 两侧可见地平线角的初值。
		for (float j = 0.0; j < sliceSteps; j++){ // 逐搜索步。
			float stepNoise = (i + j * sliceSteps) * 0.61803399; // 用黄金比错开各步。
			stepNoise = fract(stepNoise + noise.y); // 加噪声后取小数。
			float offset = (j + stepNoise) * rSliceSteps; // 归一化搜索距离。
			offset *= offset; // 平方让近处更密。
			vec2 sampleOffset = offset * sliceDir.xy * sampleRadius; // 屏幕偏移。
			sampleOffset.y *= aspectRatio; // 修正宽高比。
			{ // 正向搜索。
				vec2 sampleCoord = texCoord + sampleOffset; // 正向采样坐标。
				float sampleDepth = textureLod(depthtex1, sampleCoord, 0.0).x; // 采样深度。
				#ifdef DISTANT_HORIZONS // 远景处理。
					vec3 sampleVector = vec3(0.0); // 采样向量。
					#if OMNI_DH_AO // 只有开启远景遮蔽才把远景样本当作遮挡物。
						if (sampleDepth == 1.0){ // 天空像素改读远景深度。
							sampleDepth = textureLod(dhDepthTex0, sampleCoord, 0.0).x; // 远景深度。
							sampleVector = ViewPos_From_ScreenPos_DH(sampleCoord, sampleDepth); // 远景还原。
						}else{ // 近景像素正常还原。
							sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 近景还原。
						}
					#else // 关闭远景遮蔽时天空样本按无穷远，不产生遮挡。
						sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 只用近景深度还原。
					#endif
					sampleVector = sampleVector - viewPos; // 换成相对当前点。
				#else // 没有远景时直接还原。
					vec3 sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth) - viewPos; // 采样点相对当前点。
				#endif
				float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
				float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
				#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权。
					float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * falloffZoffset)); // 加权距离。
					float falloffWeight = remapSaturate(offsetDist, falloff * falloffStart, falloff); // 衰减权重。
				#else // 默认按距离加权。
					float falloffWeight = remapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 衰减权重。
				#endif
				cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.x, falloffWeight); // 远处回落到下限。
				maxCosHorizonAngle.x = max(cosHorizonAngle, maxCosHorizonAngle.x); // 取可见地平线角。
			}{ // 反向搜索。
				vec2 sampleCoord = texCoord - sampleOffset; // 反向采样坐标。
				float sampleDepth = textureLod(depthtex1, sampleCoord, 0.0).x; // 采样深度。
				#ifdef DISTANT_HORIZONS // 远景处理。
					vec3 sampleVector = vec3(0.0); // 采样向量。
					#if OMNI_DH_AO // 只有开启远景遮蔽才把远景样本当作遮挡物。
						if (sampleDepth == 1.0){ // 天空像素改读远景深度。
							sampleDepth = textureLod(dhDepthTex0, sampleCoord, 0.0).x; // 远景深度。
							sampleVector = ViewPos_From_ScreenPos_DH(sampleCoord, sampleDepth); // 远景还原。
						}else{ // 近景像素正常还原。
							sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 近景还原。
						}
					#else // 关闭远景遮蔽时天空样本按无穷远，不产生遮挡。
						sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth); // 只用近景深度还原。
					#endif
					sampleVector = sampleVector - viewPos; // 换成相对当前点。
				#else // 没有远景时直接还原。
					vec3 sampleVector = ViewPos_From_ScreenPos(sampleCoord, sampleDepth) - viewPos; // 采样点相对当前点。
				#endif
				float rSampleDist = inversesqrt(dot(sampleVector, sampleVector)); // 距离倒数。
				float cosHorizonAngle = dot(sampleVector, viewDir) * rSampleDist; // 采样点给出的地平线余弦。
				#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权。
					float offsetDist = length(vec3(sampleVector.xy, sampleVector.z * falloffZoffset)); // 加权距离。
					float falloffWeight = remapSaturate(offsetDist, falloff * falloffStart, falloff); // 衰减权重。
				#else // 默认按距离加权。
					float falloffWeight = remapSaturate(1.0 / rSampleDist, falloff * falloffStart, falloff); // 衰减权重。
				#endif
				cosHorizonAngle = mix(cosHorizonAngle, minCosHorizonAngle.y, falloffWeight); // 远处回落到下限。
				maxCosHorizonAngle.y = max(cosHorizonAngle, maxCosHorizonAngle.y); // 取可见地平线角。
			}
		}
		maxCosHorizonAngle = vec2(-facos(maxCosHorizonAngle.y), facos(maxCosHorizonAngle.x)) * 2.0; // 两侧换成开口角。
		float horizonAngleIntegra = 2.0 * cosNormalAngle + (maxCosHorizonAngle.x + maxCosHorizonAngle.y) * sin(normalAngle) - cos(maxCosHorizonAngle.x - normalAngle) - cos(maxCosHorizonAngle.y - normalAngle); // 这一片的半球可见缺口。
		ao += horizonAngleIntegra / rProjNormalLength; // 累加。
	}
	ao *= 0.25 * rSteps; // 平均。
	return saturate(mix(1.0, ao, OMNI_GTAO_STRENGTH)); // 按强度在无遮蔽与遮蔽之间插值。
}
// 遮蔽多弹射：按表面底色给遮蔽补一层间接光，深色表面补得少，避免暗部压死。
vec3 GTAOMultiBounce(float ao, vec3 albedo){
	return gfx_ao_multi_bounce(ao, albedo); // 转发到通用库。
}

#endif // 文件守卫结束。
