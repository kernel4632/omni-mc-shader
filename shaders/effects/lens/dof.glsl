/*
景深：按薄透镜近似算弥散圆，统计前景弥散范围，再把失焦像素散射成散景，含景深色散。
来源 iterationT `DOF.glsl`。
调用位置：由 `effects/lens/lens.glsl` 引入；后处理程序调用 `DepthOfField`。
可复制示例：`vec4 dof = DepthOfField();`
设计原因与取舍：弥散圆、焦距、散焦范围、散焦合成是一条链，放在同一文件按顺序就能读完；
    色散与景深相关一起留在这里；暗角、眩光、动态模糊各自独立，拆到同目录其它文件。
*/
#ifndef OMNI_DOF_INCLUDED
#define OMNI_DOF_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 景深：弥散圆半径与深度 ---
// 按薄透镜公式估算一个点的弥散圆半径：离对焦平面越远，弥散越大。
// `f` 是对焦距离，`d` 是该点距离，`a` 是口径系数；三者单位一致时结果就是像素半径。
float CalculateCoCRadius(float f, float d, float a){
	return abs(a * (d - f) / (d * f)); // 薄透镜近似。
}

// --- 景深：焦距与光圈换算成模糊倍数 ---
// 真实镜头里，失焦的模糊程度正比于「焦距的平方除以光圈 f 值」：换长焦或开大光圈都会让画面更糊。
// 这里拿五十毫米、f/2.8 这套常见镜头做基准，两者相除得到相对倍数，好处是焦距与光圈取默认值时结果正好为一，
// 完全保留原来由 `OMNI_DOF_BLUR` 决定的模糊量，玩家不动这两项也能得到与移植前一致的画面。
const float DoF_RefFocal = 50.0; // 基准焦距，毫米。
const float DoF_RefAperture = 2.8; // 基准光圈，f 值。
float DoFLensFactor(){
	float focalRatio = OMNI_DOF_FOCAL_LENGTH / DoF_RefFocal; // 焦距相对基准的倍数，越长越大。
	float apertureRatio = DoF_RefAperture / OMNI_DOF_APERTURE; // f 值越小口径越大，取倒数表示反比。
	return focalRatio * focalRatio * apertureRatio; // 焦距平方乘口径倍数，得到模糊倍数。
}

// 读某个坐标的米制深度；远景像素改用远景深度，并给一个近处下限避免紧贴相机时数值失控。
float GetLinearDepth(vec2 coord){
	float depth = textureLod(depthtex0, coord, 0.0).x; // 读含半透明的深度。
	#ifdef DISTANT_HORIZONS // 有远景模组时判断是否远景像素。
		if (depth == 1.0){ // 深度为一说明近处没有几何。
			depth = textureLod(dhDepthTex0, coord, 0.0).x; // 改用远景深度。
			depth = saturate(ScreenDepth_From_DHScreenDepth(depth)); // 换到近景深度尺度。
		}
	#endif
	depth = max(depth, 0.875); // 近处下限，避免对焦距离趋近零时弥散爆炸。
	return LinearDepth_From_ScreenDepth(depth); // 换成米制距离。
}

// 取对焦距离：自动模式读屏幕中心的历史深度并平滑，手动模式直接用选项。
float GetFocus(){
	#if OMNI_CAMERA_FOCUS_MODE == 0 // 自动对焦。
		float focus = LinearDepth_From_ScreenDepth(texelFetch(colortex2, ivec2(60, screenSize.y - 1.0), 0).a * 0.125 + 0.875); // 读顶行统计像素里保存的对焦深度并解码。
	#else // 手动对焦。
		float focus = OMNI_CAMERA_FOCAL_POINT; // 直接用选项给的距离。
	#endif
	return focus; // 返回对焦距离。
}

// --- 景深：前景弥散范围统计 ---
// 在螺旋上撒一圈样本，找出附近比当前点更近、弥散更大的点，把它们的弥散并进来。
// 为什么需要它：一个像素要被足够大的前景散焦覆盖，否则近处物体边缘会显得又硬又细。
float CoCSpread(){
	float cocRadiusfactor = OMNI_DOF_BLUR * gbufferProjection[1][1] * DoFLensFactor(); // 口径系数：模糊量乘投影缩放，再乘焦距光圈换算的倍数。
	const float maxCoc = OMNI_DOF_MAX_COC; // 最大弥散半径。
	const float rMaxCoc = 1.0 / maxCoc; // 半径倒数，用于归一化。
	float rAspectRatio = 1.0 / aspectRatio; // 宽高比倒数，让椭圆散景在像素上是圆的。
	#ifdef OMNI_TAA // 开时间抗锯齿时用随时间变化的噪声，避免固定图案。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else // 关闭时用固定蓝噪声。
		vec2 noise = BlueNoise(); // 固定蓝噪声。
	#endif
	float currDepth = GetLinearDepth(texCoord); // 当前点的米制深度。
	float focus = GetFocus(); // 对焦距离。
	float currCoc = CalculateCoCRadius(focus, currDepth, cocRadiusfactor); // 当前点的弥散半径。
	float startRadius = currCoc * rMaxCoc; // 当前弥散占最大值的比例。
	startRadius *= startRadius; // 平方，让搜索从中心附近开始。
	float spreadCoc = currCoc; // 弥散范围初值为当前点的弥散。
	const float steps = OMNI_DOF_COCSPREAD_QUALITY; // 搜索步数。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 黄金角旋转矩阵。
	float angle = noise.x * TAU; // 起始角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (float i = 0.0; i < steps; i++){ // 螺旋逐点搜索。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt(startRadius + (i + noise.y) * (1.0 - startRadius) * rSteps) * maxCoc; // 这个样本的半径。
		vec2 sampleCoordOffset = rot * sampleRadius; // 屏幕偏移。
		sampleCoordOffset.x *= rAspectRatio; // 按宽高比修正成圆。
		vec2 sampleCoord = texCoord + sampleCoordOffset; // 样本坐标。
		float sampleDepth = GetLinearDepth(sampleCoord); // 样本深度。
		float sampleCoC = CalculateCoCRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		if (sampleCoC >= sampleRadius && sampleDepth <= currDepth){ // 只有样本弥散足够大且比当前点更近才并进来。
			spreadCoc = max(spreadCoc, sampleCoC); // 扩大弥散范围。
		}
	}
	spreadCoc = min(spreadCoc, maxCoc) * rMaxCoc; // 夹到最大值并归一化。
	return spreadCoc; // 返回归一化的弥散范围。
}

// --- 景深：散焦合成 ---
// 按弥散半径在螺旋上取样，只让"更近且弥散够大"的样本散到当前像素上，得到背景向近处的柔和过渡。
// 这样做能避免远处背景糊到近处清晰物体上，也能让近处前景盖住后面的背景。

// 下界散焦要把深度也一起带出画面：把这一样本的深度按它属于当前点自己、还是散焦进来，累加进对应累加器。
// 主世界与末地不需要这份深度，函数体只在为下界编译时生效，调用点也随宏去掉，不产生额外开销。
// 输入是“属于当前点自己”“散焦进来”两个判断、样本深度、散焦权重与两个累加器；就地更新两个累加器。
void AccumulateDOFDepth(bool isSelfSample, bool isBlurredSample, float sampleDepth, float sampleWeight, inout float selfDepth, inout float blendedDepth){
	#ifdef OMNI_NETHER
		if (isSelfSample) selfDepth += sampleDepth; // 属于当前点自己的样本累加自贡献深度。
		else if (isBlurredSample) blendedDepth += sampleDepth * sampleWeight; // 散焦进来的样本按权重累加深度。
	#endif
}

vec4 DepthOfField(){
	float cocRadiusfactor = OMNI_DOF_BLUR * gbufferProjection[1][1] * DoFLensFactor(); // 口径系数，与弥散统计用同一个换算。
	float minCoc = 0.5641895835 * pixelSize.y; // 一个像素大小的最小弥散，避免零半径时除零。
	const float maxCoc = OMNI_DOF_MAX_COC; // 最大弥散半径。
	float rAspectRatio = 1.0 / aspectRatio; // 宽高比倒数。
	#ifdef OMNI_TAA // 时间噪声选择同上面。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else
		vec2 noise = BlueNoise(); // 固定蓝噪声。
	#endif
	float currDepth = GetLinearDepth(texCoord); // 当前点深度。
	float focus = GetFocus(); // 对焦距离。
	float currCoc = CalculateCoCRadius(focus, currDepth, cocRadiusfactor); // 当前点弥散。
	currCoc = clamp(currCoc, minCoc, maxCoc); // 夹在最小与最大之间。
	vec4 currData = textureLod(colortex1, texCoord, 0.0); // 读当前点的曲线编码颜色与弥散范围。
	float spreadCoc = currData.a * maxCoc; // 把存下来的弥散范围还原成半径。
	float centerWeight = spreadCoc * spreadCoc - spreadCoc + 1.0; // 中心权重多项式。
	centerWeight = mix(centerWeight, 1e-20, pow(currCoc / spreadCoc, 4.0)); // 当前点自己很清晰时把它自己压到极小。
	#ifdef OMNI_DOF_CATSEYE // 猫眼效应：把散焦区域在画面边缘裁成椭圆。
		vec2 catsEyeOffset = (texCoord) * 2.0 - 1.0; // 从中心指向当前点。
		catsEyeOffset.x *= aspectRatio; // 按宽高比修正成圆。
		float catsEyeDist = length(catsEyeOffset); // 到中心的距离。
		catsEyeDist = max(catsEyeDist - OMNI_DOF_CATSEYE_MIDPOINT, 0.0); // 超过中点才开始裁剪。
		catsEyeDist *= spreadCoc * OMNI_DOF_CATSEYE_STRENGTH; // 按弥散与强度缩放。
		catsEyeOffset = normalize(catsEyeOffset) * catsEyeDist; // 得到裁剪半径。
	#endif
	vec3 dof = vec3(0.0); // 散焦进来的颜色累加。
	float weights = 0.0; // 样本权重累加。
	vec3 selfColor = CurveToLinear(currData.rgb) * 1e-20; // 当前点自贡献初值极小。
	float selfSamples = 1e-20; // 当前点自计入的样本数初值极小。
	float selfWeights = 0.0; // 被拒绝样本在中心上的权重累加。
	#ifdef OMNI_NETHER // 下界还要带出散焦后的深度。
		float blendedDepth = 0.0; // 散焦后的深度累加。
		float selfDepth = currDepth * 1e-20; // 当前点自计入深度初值极小。
	#endif
	const float steps = OMNI_DOF_QUALITY; // 采样步数。
	const float rSteps = 1.0 / steps; // 步数倒数。
	const float firstStepRadius = sqrt(rSteps); // 首个样本半径，原程序保留。
	const mat2 rotMat = mat2(cos(goldenAngle), sin(goldenAngle), -sin(goldenAngle), cos(goldenAngle)); // 黄金角旋转矩阵。
	float angle = noise.x * TAU; // 起始角。
	vec2 rot = vec2(cos(angle), sin(angle)); // 起始方向。
	for (float i = 0.0; i < steps; i++){ // 螺旋采样。
		rot *= rotMat; // 每步旋转一点。
		float sampleRadius = sqrt((i + noise.y) * rSteps) * spreadCoc; // 样本半径。
		vec2 sampleCoordOffset = rot * sampleRadius; // 屏幕偏移。
		#ifdef OMNI_DOF_CATSEYE // 猫眼裁剪：偏移超出裁剪半径就跳过。
			if (distance(catsEyeOffset, sampleCoordOffset) > spreadCoc) continue; // 超出就不采。
		#endif
		sampleCoordOffset.x *= rAspectRatio * OMNI_DOF_ANAMORPHIC_RATIO; // 按宽高比修正后再按变形比横向拉伸；变形比为一表示不变形。
		vec2 sampleCoord = texCoord + sampleCoordOffset; // 样本坐标。
		float sampleDepth =  GetLinearDepth(sampleCoord); // 样本深度。
		float sampleCoC = CalculateCoCRadius(focus, sampleDepth, cocRadiusfactor); // 样本弥散。
		sampleCoC = clamp(sampleCoC, minCoc, maxCoc); // 夹到范围。
		vec3 sampleColor; // 样本线性颜色，下面按是否做色散分两条路取。
		if (OMNI_DOF_DISPERSION_MULT != 1.0){ // 色散开启时：红蓝通道沿到画面中心的方向错开，绿通道不动。
			// 为什么减一：让默认值一表示「不错开」，与原程序默认一致，保证默认画面不变；
			// 偏移量随样本半径与到中心的距离增大，越靠边、越失焦的像素色边越明显。
			vec2 dispersionOffset = (texCoord - 0.5) * sampleRadius * (OMNI_DOF_DISPERSION_MULT - 1.0);
			sampleColor.r = CurveToLinear(textureLod(colortex1, sampleCoord + dispersionOffset, 0.0).r); // 红通道向外错开。
			sampleColor.g = CurveToLinear(textureLod(colortex1, sampleCoord, 0.0).g); // 绿通道不动。
			sampleColor.b = CurveToLinear(textureLod(colortex1, sampleCoord - dispersionOffset, 0.0).b); // 蓝通道向内错开。
		}else{ // 默认无色散：只取一次样本，与未加色散前完全一致。
			sampleColor = CurveToLinear(textureLod(colortex1, sampleCoord, 0.0).rgb); // 样本线性颜色。
		}
		float sampleWeight = max(1.0, currCoc / sampleCoC); // 近处前方样本权重更高，散焦累加时用。
		sampleWeight *= sampleWeight; // 平方加强。
		bool isSelfSample = currCoc >= sampleRadius && sampleDepth >= currDepth; // 样本属于当前点自己。
		bool isBlurredSample = sampleCoC >= sampleRadius && sampleDepth < currDepth; // 样本更近且弥散够大，散焦进来。

		if (isSelfSample){ // 样本属于当前点自己。
			selfColor += sampleColor; // 记为自贡献。
			selfSamples += 1.0; // 自贡献样本数。
		}else if (isBlurredSample){ // 样本散焦进来。
			dof += sampleColor * sampleWeight; // 累加散焦颜色。
			weights += sampleWeight; // 累加权重。
		}else{ // 样本不满足条件，记进中心权重。
			selfWeights += centerWeight; // 累加中心权重。
		}

		#ifdef OMNI_NETHER // 下界额外把深度也累加，供写出屏幕深度使用。
			AccumulateDOFDepth(isSelfSample, isBlurredSample, sampleDepth, sampleWeight, selfDepth, blendedDepth); // 按归属累加深度。
		#endif
	}

	dof += selfColor * (1.0 + selfWeights / selfSamples); // 把自贡献按被拒绝样本的补偿加回来。
	dof /= weights + selfSamples + selfWeights; // 归一化。

	#ifdef OMNI_NETHER // 下界把深度按同一套补偿与归一化后一起返回。
		blendedDepth += selfDepth * (1.0 + selfWeights / selfSamples); // 深度同样补偿。
		blendedDepth /= weights + selfSamples + selfWeights; // 归一化深度。
		return vec4(LinearToCurve(dof), ScreenDepth_From_LinearDepth(blendedDepth)); // 返回曲线编码颜色与换回的屏幕深度。
	#else
		return vec4(LinearToCurve(dof), 0.0); // 返回曲线编码颜色，透明度留零。
	#endif
}

#endif // 文件守卫结束。
