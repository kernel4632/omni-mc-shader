/*
星空：把视线方向对齐到天球后，用 Eclipse `lib/stars.glsl` 的星场撒出星点，供延迟三号叠加到夜空。
调用位置：由 `effects/sky/sky.glsl` 引入；`CalculateStars` 在 `effects/sky/skyrender.glsl`（星点类型为点状时）
    与 `effects/world/end_sky.glsl`（末地转发）里调用。
可复制示例：
    `celestial += CalculateStars(worldDir, worldSunVector);`
设计原因与取舍：白色路径走稳定星场、彩色路径走星盒，由 `OMNI_STARS_COLORED` 开关，默认是白色。
    Eclipse 用自定义旋转摆星场，本项目沿用原有的绕日轴旋转对齐天球；Eclipse 在合成阶段乘十，
    本项目改用 `starScale` 对齐既有夜间曝光。太阳方向作为参数传入：天空会被多个程序引入，直接在函数里读全局量会让不需要光色的程序编译失败。
*/
#ifndef OMNI_SKY_STARS_INCLUDED
#define OMNI_SKY_STARS_INCLUDED
// --- 星空：来源 Eclipse `lib/stars.glsl`（`hash13`、`NoisyStarField`、`StableStarField`、`stars`） ---
// 为什么换成 Eclipse：原星场是 iterationT 版本，星点形状、疏密与分布都和 Eclipse 不同源，本步按用户要求整体替换。
// 与 Eclipse 的差异一：Eclipse 在合成阶段把星场结果乘十再直接写屏，这里乘 `starScale` 接到本项目既有亮度口径上。
// 与 Eclipse 的差异二：Eclipse 用 `customRotation(sunPathRotation, worldTimeSmooth)` 摆星场，这里沿用原有「绕日轴旋转」对齐天球。
// 与 Eclipse 的差异三：Eclipse 的 `STARS_AMOUNT`、`STARS_BRIGHTNESS` 对应本项目的 `OMNI_STARS_AMOUNT`、`OMNI_STARS_BRIGHTNESS`。

// 星场散列：把一个方向格打散成零到一的随机数，来源 Eclipse `lib/stars.glsl` 的 `hash13`。
float hash13(vec3 p3){
	p3 = fract(p3 * 0.1031); // 先乘一个小数再取小数部分，打散整数格的规律。
	p3 += dot(p3, p3.zyx + 31.32); // 三个分量互相掺入，避免相邻格出现相近的值。
	return fract((p3.x + p3.y) * p3.z); // 合并三个分量，得到零到一。
}

// 噪声星场：把散列值低于阈值的格子压成零，剩下的当作星点原始亮度，来源 Eclipse 的 `NoisyStarField`。
float NoisyStarField(vec3 vSamplePos, float fThreshhold){
	float StarVal = hash13(vSamplePos); // 先取这个格的随机值。
	StarVal = clamp(StarVal / (1.0 - fThreshhold) - fThreshhold / (1.0 - fThreshhold), 0.0, 1.0); // 阈值以下压到零，剩下归一化到零到一。
	return StarVal; // 返回星点亮度。
}

// 稳定星场：只在整数格上取值，再用双线性插值平滑，避免相机移动时星点闪烁，来源 Eclipse 的 `StableStarField`。
// 已知代价（Eclipse 原注释承认）：双线性插值会把单个星点拉成十字，这里按合同保留原写法。
float StableStarField(vec3 vSamplePos, float fThreshhold){
	float fractX = fract(vSamplePos.x); // 当前点在 x 方向的格内偏移。
	float fractY = fract(vSamplePos.y); // 当前点在 y 方向的格内偏移。
	vec3 floorSample = floor(vSamplePos.xyz); // 所在整数格。
	float v1 = NoisyStarField(floorSample, fThreshhold); // 左下格的星点亮度。
	float v2 = NoisyStarField(floorSample + vec3(0.0, 1.0, 0.0), fThreshhold); // 左上格。
	float v3 = NoisyStarField(floorSample + vec3(1.0, 0.0, 0.0), fThreshhold); // 右下格。
	float v4 = NoisyStarField(floorSample + vec3(1.0, 1.0, 0.0), fThreshhold); // 右上格。
	float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY) // 四角按格内偏移加权求和。
				  + v2 * (1.0 - fractX) * fractY // 左上权重。
				  + v3 * fractX * (1.0 - fractY) // 右下权重。
				  + v4 * fractX * fractY; // 右上权重。
	return StarVal; // 平滑后的星点亮度。
}

#if OMNI_STARS_COLORED // 彩色星场（Eclipse 的 `starbox`）只在开启时才编进来，默认关闭、不产生无用代码。
// 彩色星场散列：来源 Eclipse `lib/stars.glsl` 的 `hash12_alt`，只用二维坐标。
float hash12(vec2 co){
	return fract(sin(2.0 * PI * fract(dot(co.xy, vec2(12.9898, 78.233)))) * 43758.5453); // 正弦放大再取小数，是最常见的二维散列写法。
}

// 星温：把零到一的散列映射成色温，来源 Eclipse 的 `starTemp`；三次方让多数星星偏冷白、少数偏暖。
float starTemp(float hash){
	return hash * hash * hash * (19000.0 - 5500.0) + 5500.0; // 色温范围五千五到一万九开尔文。
}

// 星面：把方向投到立方体的一面按格撒星，输出该方向的亮度与颜色，来源 Eclipse 的 `starplane`。
float starplane(vec3 dir, out vec3 starColor){
	float scale = 1.0 / 600.0; // 格子大小，越小星点越密。
	vec2 basePos = dir.xy * (0.4 / scale) / max(1e-3, abs(dir.z)); // 投到这个面上并按深度缩放。
	starColor = vec3(0.0); // 这个面的星色初值。
	vec2 pos = floor(basePos); // 所在整数格。
	vec2 center = pos + vec2(0.5); // 格中心，用来算到星心的距离。
	float d = distance(basePos, center); // 当前采样点到星心的距离。
	basePos = floor(basePos); // 锁定到格，保证相机移动时星点不飘。
	float color = 0.0; // 这个面的星点亮度。
	if (hash12(basePos.xy * scale) > 0.997){ // 只有极少数格子有星。
		float radius = 0.4; // 星点半径，越大越胖。
		float brightness = exp(-(d * d) / (2.0 * radius * radius)); // 高斯衰减，星心最亮。
		float r = hash12(basePos.xy * 0.5); // 这颗星的随机亮度因子。
		color = r * (0.3 * sin(1.0 * (r * 5.0) + r) + 0.7) * brightness; // 亮度带一点随机起伏。
		starColor = 2.0 * Blackbody(starTemp(hash12(center))); // 按格中心的散列取色温上色。
	}
	return color * pow(abs(dir.z), 2); // 按该面朝向加权，面边界处平滑过渡。
}

// 星盒：把方向分别当立方体三轴投影，叠出完整六面星场，来源 Eclipse 的 `starbox`。
float starbox(vec3 dir, out vec3 starColor){
	vec3 starColor1 = vec3(0.0); // 第一组投影的星色。
	vec3 starColor2 = vec3(0.0); // 第二组投影的星色。
	vec3 starColor3 = vec3(0.0); // 第三组投影的星色。
	float color = starplane(dir.xyz, starColor1) + starplane(dir.yzx, starColor2) + starplane(dir.zxy, starColor3); // 三组投影叠亮度。
	starColor = starColor1 + starColor2 + starColor3; // 三组投影叠星色。
	return sqrt(color); // 开方压一下亮度分布，与 Eclipse 一致。
}
#endif // OMNI_STARS_COLORED 结束。

// 星场总入口：来源 Eclipse 的 `stars`；按是否开启彩色星点选白色稳定星场或彩色星盒。
// 返回星场亮度，`starColor` 回填星色；白色路径没有星温，星色固定为一。
float stars(vec3 viewPos, out vec3 starColor){
	#if OMNI_STARS_COLORED
		starColor = vec3(1.0); // 星色由下面的星盒回填，这里先给初值。
		float s = max(1.0 - starbox(viewPos, starColor), 0.0); // 彩色星盒星场。
		return 75.0 * OMNI_STARS_BRIGHTNESS * exp(s * -20.0 * (1.0 / OMNI_STARS_AMOUNT)); // 系数与 Eclipse 相同。
	#else
		starColor = vec3(1.0); // 白星路径没有星温，固定白色。
		float s = max(1.0 - StableStarField(viewPos * 300.0, 0.99), 0.0); // 稳定星场，采样密度三百、阈值零点九九与 Eclipse 相同。
		return OMNI_STARS_BRIGHTNESS * exp(s * -20.0 * (1.0 / OMNI_STARS_AMOUNT)); // 系数与 Eclipse 相同。
	#endif
}

// 星场包装：把世界方向对齐到太阳天球后交给 Eclipse 星场，再缩放成本项目亮度口径；签名与原 `CalculateStars` 一致。
// 调用位置：`effects/sky/skyrender.glsl` 在 `OMNI_STAR_TYPE == 1` 时调用。
// 太阳方向作为参数传入：天空效果会被多个程序引入，直接在函数里读全局量会让不需要光色的程序编译失败。
vec3 CalculateStars(vec3 worldDir, vec3 sunVector){
	float cosine = dot(sunVector, vec3(0, 0, 1)); // 太阳轴与参考轴夹角余弦。
	vec3 axis = cross(sunVector, vec3(0, 0, 1)); // 旋转轴。
	float cosecantSquared = 1.0 / dot(axis, axis); // 旋转公式里的比例因子。
	worldDir = cosine * worldDir + cross(axis, worldDir) + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis; // 按罗德里格公式把星场对齐到太阳方向。

	#if OMNI_STARS_COLORED
		const float starScale = 0.05 / 75.0; // 彩色路径在 Eclipse 里带七十五倍系数，除回去，使两条路径最亮星一致。
	#else
		const float starScale = 0.05; // 与旧 `CalculateStars` 最亮星零点零五对齐，保持夜间曝光不变。
	#endif

	vec3 starColor; // 星场回填的星色。
	return starScale * stars(worldDir, starColor) * starColor; // 亮度乘星色，得到最终星点颜色。
}
#endif // 文件守卫结束。
