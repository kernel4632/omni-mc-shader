/*
反射小波滤波：对三号画面的反射做一遍小波滤波，按半径大小去掉半分辨率追踪留下的噪点。
来源 iterationT `composite3.fsh`、`composite4.fsh`。
调用位置：由 `effects/reflection/reflection.glsl` 引入；程序主体 `CompositeReflectionFilter()` 在
    `effects/reflection/composite_filter.glsl`，只为 composite3 / composite4 编译。
可复制示例：`AtrousWaveletFilter(reflectionData, viewPos, viewDir, normal, roughness, 40.0, vec2(0.0));`
设计原因与取舍：滤波只在合成三号、四号两遍里用，半径与是否抖动由调用方决定；放在反射文件旁边，便于和追踪算法一起读。
*/
#ifndef OMNI_REFLECTION_DENOISE_INCLUDED
#define OMNI_REFLECTION_DENOISE_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- composite3 / composite4：反射小波滤波 ---
#if defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS
// 反射滤波：用九点小波核按法线与深度相似度加权，抹掉屏幕反射的噪点同时保住反射边界。
// 输入是反射数据、表面位置、视线方向、法线、粗糙度、滤波半径与抖动噪声；就地改写反射数据。
// 为什么按法线与深度加权：命中点落在不同法线或不同深度的邻居属于别的物体，混进来会把反射糊成一片。
// 为什么先按亮度幂次重整再还原：高动态范围的反射点会盖住整片邻域，先压一下亮度再合并，边界更干净。
void AtrousWaveletFilter(inout vec4 reflectionData, vec3 viewPos, vec3 viewDir, vec3 normal, float roughness, float radius, vec2 noise){
	float linearDepth = -viewPos.z; // 表面的米制深度。
	float NdotV = saturate(dot(-viewDir, normal)); // 视线与法线夹角余弦。

	roughness = max(roughness, 1e-4); // 粗糙度给一个下限，避免除以零。

	radius *= min(roughness * 20.0, 1.0); // 越粗糙反射越糊，滤波半径越大。
	radius *= reflectionData.a * 0.9 + 0.1; // 命中距离越远半径越大。

	const mat2 rot90 = mat2(cos(1.5708), -sin(1.5708), sin(1.5708), cos(1.5708)); // 旋转九十度，用来由切向得到副切向。

	vec2 T = normalize(cross(normal, viewDir).xy) * radius; // 沿表面切向的采样步长。
	vec2 B = T * rot90; // 副切向的采样步长。
	T *= mix(0.1075, 0.5, NdotV) * pixelSize; // 切向按视角缩放并换成屏幕坐标。
	B *= mix(0.7, 0.5, NdotV) * pixelSize; // 副切向同理。

	vec3 reflectedDir = reflect(-viewDir, normal); // 当前像素的反射方向。

	float normalThreshold = 75.0 / roughness; // 法线相似度的幂次，越粗糙越严。
	float luminanceThreshold = reflectionData.a * 0.95 + 0.05; // 亮度重整的幂次，按命中距离变化。
	
	vec4 accum = vec4(0.0); // 加权累加的反射数据。
	float weights = 0.0; // 累加权重。

	const vec2 offset[9] = vec2[9]( // 三乘三邻域偏移。
		vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), 
		vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), 
		vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0));

	for (int i = 0; i < 9; i++){ // 遍历九个邻点。
		vec2 sampleCoord = texCoord + T * (offset[i] + noise.x) + B * (offset[i] + noise.y); // 邻点坐标，按抖动微调。

		vec4 sampleData = textureLod(colortex3, sampleCoord, 0.0); // 读邻点反射数据。

		if (sampleData.a < 0.0001) continue; // 邻点没有反射，跳过。

		float sampleLinerDepth = LinearDepth_From_ScreenDepth(textureLod(depthtex0, sampleCoord, 0.0).x); // 邻点米制深度。
		vec3 sampleReflectedDir = reflect(-viewDir, DecodeNormal(textureLod(colortex4, sampleCoord, 0.0).xy)); // 邻点反射方向。

		float normalWeight = pow(saturate(dot(sampleReflectedDir, reflectedDir)), normalThreshold); // 反射方向越接近权重越大。
		float depthWeight = exp2(-(abs(sampleLinerDepth - linearDepth) * 1.58)); // 深度越接近权重越大。
		float sampleWeight = normalWeight * depthWeight; // 两个权重相乘。
		
		sampleData.rgb += 1e-13; // 避免零亮度在下面除法里出问题。
		float luminance = length(sampleData.rgb); // 邻点亮度。
		sampleData.rgb *= pow(luminance, luminanceThreshold) / luminance; // 按幂次重整亮度。

		accum += sampleData * sampleWeight; // 按权重累加。
		weights += sampleWeight; // 累加权重。
	
	}
	
	if (weights > 1e-13){ // 有有效邻点才写回。
		accum /= weights; // 取加权平均。

		accum.rgb += 1e-13; // 同样避免零亮度。
		float luminance = length(accum.rgb); // 平均后的亮度。
		accum.rgb *= pow(luminance, 1.0 / luminanceThreshold) / luminance; // 还原亮度重整。

		reflectionData = accum; // 写回滤波结果。
	}
}
#endif // composite3 与 composite4 段结束。
#endif // 文件守卫结束。
