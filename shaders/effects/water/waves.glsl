/*
水面波浪：用噪声与三角波叠出水面高度与法线，并提供物理解析波浪与水面视差坐标。
来源 iterationT `WaterWaves.glsl`、`PhysicsOceans.glsl`。
调用位置：由 `effects/water/water.glsl` 引入；水面、焦散、反射等引用波浪的地方都经它取得法线。
可复制示例：
    `vec3 n = GetWavesNormal(position, waveHeight);`
    `vec4 wave = physics_wavePixel(position, factor, iterations, time, ...);`
设计原因与取舍：基础波浪与物理解析波浪共用同一套噪声与缩放约定，放一起能看清两者关系；
    物理解析波浪的顶点与片元两段靠 `PHYSICS_VS` / `PHYSICS_FS` 宏分派，保留 iterationT 原样。
*/
#ifndef OMNI_WATER_WAVES_INCLUDED
#define OMNI_WATER_WAVES_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 波浪：多层噪声正弦叠成起伏 ---
// 先用三次曲线把噪声采样平滑化，再逐层缩小频率、加快速度，得到自然且可重复的波浪。
// 为什么用噪声贴图而不是解析正弦：贴图里已经烘好一层细节，叠几层就有足够丰富感，省下大量三角计算。
vec4 textureSmooth(sampler2D texSampler, vec2 coord){
	coord *= 64.0; // 噪声贴图边长六十四，先换成像素坐标。
	coord += 0.5; // 移到像素中心。

	vec2 whole = floor(coord); // 整数像素。
	vec2 part  = coord - whole; // 小数部分。

	coord = whole + curve(part); // 用三次曲线改写小数部分，采样更平滑。

	coord -= 0.5; // 移回像素角。
	coord *= 0.015625; // 除以六十四，换回零到一坐标。

	return textureLod(texSampler, coord, 0.0); // 读取平滑后的噪声四通道。
}

// 把零到一的值压成两端平、中间过渡的形状，用来让波浪峰值更饱满。
float AlmostIdentity(float x, float m, float n){
	x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值，得到对称形状。

	if (x <= m){ // 只在靠近中间的一段改写。
		float a = 2.0 * n - m; // 三次项系数。
		float b = 2.0 * m - 3.0 * n; // 二次项系数。
		float t = x / m; // 归一化到零到一。

		x = (a * t + b) * t * t + n; // 三次多项式重排形状。
	}

	return 1.0 - x; // 翻转方向。
}

// 主波函数：把世界位置缩放后逐层累加噪声采样，每层频率与速度都不同。
float GetWaves(vec3 position) {
	float wavesTime = frameTimeCounter * 0.0035; // 波浪时间，比真实秒慢很多，水面更平静。

	position *= OMNI_WAVE_SCALE; // 按波浪密度缩放空间坐标。
	vec2 p = position.xz - position.y; // 用水平坐标，减去高度让波浪随高度起伏。
	p += -3.875 * wavesTime; // 整片波沿一个方向平移。
	p.x = -p.x; // 翻转一个轴，打散规则方向。

	vec2 waves = vec2(0.0); // 前两个分量分别存累加高度和累加权重。

	waves += vec2(textureSmooth(noisetex, p * vec2(2.0, 1.2) + vec2(0.0, p.x * 2.1)).w,
				  1.0); // 第一层：低频大波，权重一。

		p = p * 0.475; // 收缩坐标，频率升高。
		p += vec2(-5.16, -7.75) * wavesTime; // 每层自己的行进方向与速度。

	waves += vec2(textureSmooth(noisetex, p * vec2(2.0, 1.4) + vec2(0.0, -p.x * 2.1)).w
				  * 4.0, 4.0); // 第二层：加四倍权重。

		p *= 0.67; // 继续抬高频率。
		p.x += 7.75 * wavesTime; // 换一个方向。

	waves += vec2(textureSmooth(noisetex, p + vec2(0.0, p.x * 1.1)).z
				  * 8.0, 8.0); // 第三层：换一个通道，权重八。

		p *= 0.7; // 再抬高频率。
		p.x += -2.82 * wavesTime; // 换方向。

	waves += vec2(textureSmooth(noisetex, p * vec2(1.0, 0.75) + vec2(0.0, -p.x * 1.7)).w
				  * 16.0, 16.0); // 第四层：权重十六。

		p *= 0.45; // 高频细节。
		p.x += wavesTime; // 换方向。

	waves += vec2(AlmostIdentity(textureSmooth(noisetex, p * vec2(1.0, 0.8) + vec2(0.0, -p.x * 1.7)).z, 0.2, 0.1)
				  * 30.0, 30.0); // 第五层：用形状函数让峰值饱满，权重三十。

		p *= 0.5; // 最高频一层。
		p.x += wavesTime; // 换方向。

	waves += vec2(AlmostIdentity(textureSmooth(noisetex, p * vec2(1.0, 0.8) + vec2(0.0,  p.x * 1.7)).w, 0.2, 0.1)
				  * 20.0, 20.0); // 第六层：最高频，权重二十。

	return waves.x / waves.y; // 高度除以权重和，归一化到合理范围。
}

#define sampleDistance 12.0 // 法线差分采样距离，原程序取值，写死让每个程序代价一致。

// 波法线：用高度差近似倾斜，中央差分取横纵两个方向。
// 为什么乘 `WAVE_HEIGHT / sampleDistance`：高度差除以采样距离才是坡度，再乘波浪高度选项统一缩放。
vec3 GetWavesNormal(vec3 position, const float waveHeight){
	position.xz -= 0.005 * sampleDistance; // 采样点整体后移一点，让差分落在波面中心。

	float wavesCenter = GetWaves(position); // 中心高度。
	float wavesLeft = GetWaves(position + vec3(0.01 * sampleDistance, 0.0, 0.0)); // 横向偏移一点的高度。
	float wavesUp   = GetWaves(position + vec3(0.0, 0.0, 0.01 * sampleDistance)); // 纵向偏移一点的高度。

	vec3 wavesNormal = vec3(wavesCenter - wavesLeft, wavesCenter - wavesUp, 1.0); // 用两个方向的高度差构成法线，竖直分量为一。

	wavesNormal.xy *= waveHeight * (OMNI_WAVE_HEIGHT / sampleDistance); // 按波高选项与采样距离缩放坡度。

	#if OMNI_PLAYER_WATER > 0 // 玩家交互水面：把玩家带起的涟漪叠到波法线的纵向分量上。
		wavesNormal.y = mix(wavesNormal.y, 1.0, PlayerWaterRipple(position)); // 涟漪越高越把法线朝上推，形成一圈凸起。
	#endif

	return normalize(wavesNormal); // 归一化成单位法线。
}

// 水面视差：沿视线在波高场里一步步前进，找到真正可见的波面位置。
// 为什么限制十二步：步数直接决定开销，写死让每个程序代价一致，也让画面表现稳定。
vec3 GetWaterParallaxCoord(vec3 position, vec3 viewVector){
	const vec3 stepSize = vec3(OMNI_WAVE_HEIGHT * 0.8, OMNI_WAVE_HEIGHT * 0.8, 0.6); // 每步的大小，横向按波高缩放，纵向固定。
	float waveHeight = GetWaves(position); // 起点波高。
	vec3 pCoord = vec3(0.0, 0.0, 1.0); // 以表面为参考，向前推进的深度。
	vec3 steps = viewVector * stepSize; // 每步的位移。

	float sampleHeight = waveHeight; // 当前位置的波高。

	for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i) // 波高还没追上视线深度就继续走，最多十二步。
	{
		pCoord.xy += steps.xy * saturate((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2)); // 按深度差决定这一步走多远。
		pCoord.z += steps.z; // 视线深度前进。
		sampleHeight = GetWaves(position + vec3(pCoord.x, 0.0, pCoord.y)); // 读取新位置的波高。
	}

	return position.xyz + vec3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

// --- 海洋物理波：按迭代正弦合成海面，供外部海洋物理扩展使用 ---
// 形状必须与原程序一致，因为实体偏移在中央处理器一侧也按同一套公式计算，两边不一致会让实体浮空或陷进水里。
// 下面这些输入由外部海洋物理扩展提供；扩展缺失时不会调用这些函数，基础水面不受影响。
const int PHYSICS_ITERATIONS_OFFSET = 13; // 迭代次数的基础偏移，原程序取值。
const float PHYSICS_DRAG_MULT = 0.048; // 每层波形对采样点的拖拽量。
const float PHYSICS_XZ_SCALE = 0.035; // 水平坐标缩放。
const float PHYSICS_TIME_MULTIPLICATOR = 0.45; // 时间缩放。
const float PHYSICS_W_DETAIL = 0.75; // 细节权重指数。
const float PHYSICS_FREQUENCY = 6.0; // 起始频率。
const float PHYSICS_SPEED = 2.0; // 起始速度。
const float PHYSICS_WEIGHT = 0.8; // 每层权重衰减。
const float PHYSICS_FREQUENCY_MULT = 1.18; // 每层频率放大。
const float PHYSICS_SPEED_MULT = 1.07; // 每层速度放大。
const float PHYSICS_ITER_INC = 12.0; // 每层方向角增量。
const float PHYSICS_NORMAL_STRENGTH = 0.6; // 法线竖直分量的强度。

uniform int physics_iterationsNormal; // 表面细节迭代次数，来自扩展。
uniform vec2 physics_waveOffset; // 波形原点偏移，保持网格改变时波形不变。
uniform ivec2 physics_textureOffset; // 波纹理采样偏移。
uniform float physics_gameTime; // 可随天气加速的游戏时间，单位秒。
uniform float physics_globalTime; // 全局时间，单位秒。
uniform float physics_oceanHeight; // 海面高度基准，基础值十三再乘波高。
uniform sampler2D physics_waviness; // 浅水深浅图。
uniform float physics_oceanWaveHorizontalScale; // 波浪水平尺寸。
uniform vec3 physics_modelOffset; // 模型偏移，用来定位涟漪。
uniform float physics_rippleRange; // 涟漪贴图覆盖范围。
uniform float physics_foamAmount; // 泡沫生成量。
uniform float physics_foamOpacity; // 泡沫不透明度。
uniform sampler2D physics_ripples; // 涟漪凹凸贴图。
uniform sampler3D physics_foam; // 泡沫噪声三维贴图。
uniform sampler2D physics_lightmap; // 原版光照图。

#ifdef PHYSICS_VS // 顶点阶段把局部位置与波高传给片元。
	out vec3 physics_localPosition; // 顶点局部位置。
	out float physics_localWaviness; // 顶点处的水深。
#endif
#ifdef PHYSICS_FS // 片元阶段接收顶点传来的数据。
	in vec3 physics_localPosition; // 顶点局部位置。
	in float physics_localWaviness; // 顶点处的水深。
#endif

// 按迭代正弦求某点波高：每层频率与速度都放大，权重衰减，最后归一化并居中。
float physics_waveHeight(vec2 position, int iterations, float factor, float time) {
	position = (position - physics_waveOffset) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale; // 换到波形空间。
	float iter = 0.0; // 每层方向角。
	float frequency = PHYSICS_FREQUENCY; // 当前层频率。
	float speed = PHYSICS_SPEED; // 当前层速度。
	float weight = 1.0; // 当前层权重。
	float height = 0.0; // 累加高度。
	float waveSum = 0.0; // 累加权重。
	float modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR; // 缩放后的时间。

	for (int i = 0; i < iterations; i++) { // 逐层叠加。
		vec2 direction = vec2(sin(iter), cos(iter)); // 当前层方向。
		float x = dot(direction, position) * frequency + modifiedTime * speed; // 当前层的相位。
		float wave = exp(sin(x) - 1.0); // 波峰更尖的包络。
		float result = wave * cos(x); // 波形值。
		vec2 force = result * weight * direction; // 对采样点的拖拽力。

		position -= force * PHYSICS_DRAG_MULT; // 采样点被拖拽，形成剪切。
		height += wave * weight; // 累加高度。
		iter += PHYSICS_ITER_INC; // 方向角前进。
		waveSum += weight; // 累加权重。
		weight *= PHYSICS_WEIGHT; // 权重衰减。
		frequency *= PHYSICS_FREQUENCY_MULT; // 频率放大。
		speed *= PHYSICS_SPEED_MULT; // 速度放大。
	}

	return height / waveSum * physics_oceanHeight * factor - physics_oceanHeight * factor * 0.5; // 归一化并按海面高度缩放、居中。
}

// 合成海面法线：波形法线再混入涟漪贴图的凹凸，涟漪越强权重越大。
vec3 physics_waveNormal(const in vec2 position, const in vec2 direction, const in float factor, const in float time) {
	float oceanHeightFactor = physics_oceanHeight / 13.0; // 海面高度相对基础值十三的倍率。
	float totalFactor = oceanHeightFactor * factor; // 总倍率。
	vec3 waveNormal = normalize(vec3(direction.x * totalFactor, PHYSICS_NORMAL_STRENGTH, direction.y * totalFactor)); // 由波形方向构造法线。

	vec2 eyePosition = position + physics_modelOffset.xz; // 加上模型偏移，定位涟漪位置。
	vec2 rippleFetch = (eyePosition + vec2(physics_rippleRange)) / (physics_rippleRange * 2.0); // 涟漪贴图采样坐标。
	vec2 rippleTexelSize = vec2(2.0 / textureSize(physics_ripples, 0).x, 0.0); // 一个纹素的横向大小。
	float left = texture(physics_ripples, rippleFetch - rippleTexelSize.xy).r; // 左侧涟漪高度。
	float right = texture(physics_ripples, rippleFetch + rippleTexelSize.xy).r; // 右侧涟漪高度。
	float top = texture(physics_ripples, rippleFetch - rippleTexelSize.yx).r; // 上侧涟漪高度。
	float bottom = texture(physics_ripples, rippleFetch + rippleTexelSize.yx).r; // 下侧涟漪高度。
	float totalEffect = left + right + top + bottom; // 四邻合计，表示涟漪强度。

	float normalx = left - right; // 横向坡度。
	float normalz = top - bottom; // 纵向坡度。
	vec3 rippleNormal = normalize(vec3(normalx, 1.0, normalz)); // 涟漪法线。
	return normalize(mix(waveNormal, rippleNormal, pow(totalEffect, 0.5))); // 按涟漪强度混合波形法线与涟漪法线。
}

// 海面像素的完整数据，一次算好方向、位置、法线、泡沫与高度，供片元阶段一次取用。
struct WavePixelData {
	vec2 direction; // 波形方向。
	vec2 worldPos; // 还原后的世界位置。
	vec3 normal; // 合成法线。
	float foam; // 泡沫强度。
	float height; // 波高。
};

// 一次算出海面像素的全部数据，内部把波高、方向与泡沫合成，避免片元阶段重复迭代。
WavePixelData physics_wavePixel(const in vec2 position, const in float factor, const in float iterations, const in float time) {
	vec2 wavePos = (position.xy - physics_waveOffset) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale; // 换到波形空间。
	float iter = 0.0; // 每层方向角。
	float frequency = PHYSICS_FREQUENCY; // 当前层频率。
	float speed = PHYSICS_SPEED; // 当前层速度。
	float weight = 1.0; // 当前层权重。
	float height = 0.0; // 累加高度。
	float waveSum = 0.0; // 累加权重。
	float modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR; // 缩放后的时间。
	vec2 dx = vec2(0.0); // 累加方向。

	for (int i = 0; i < iterations; i++) { // 逐层叠加。
		vec2 direction = vec2(sin(iter), cos(iter)); // 当前层方向。
		float x = dot(direction, wavePos) * frequency + modifiedTime * speed; // 当前层的相位。
		float wave = exp(sin(x) - 1.0); // 波峰更尖的包络。
		float result = wave * cos(x); // 波形值。
		vec2 force = result * weight * direction; // 对采样点的拖拽力。

		dx += force / pow(weight, PHYSICS_W_DETAIL); // 按细节指数累加方向。
		wavePos -= force * PHYSICS_DRAG_MULT; // 采样点被拖拽。
		height += wave * weight; // 累加高度。
		iter += PHYSICS_ITER_INC; // 方向角前进。
		waveSum += weight; // 累加权重。
		weight *= PHYSICS_WEIGHT; // 权重衰减。
		frequency *= PHYSICS_FREQUENCY_MULT; // 频率放大。
		speed *= PHYSICS_SPEED_MULT; // 速度放大。
	}

	WavePixelData data; // 待填充的数据。
	data.direction = -vec2(dx / pow(waveSum, 1.0 - PHYSICS_W_DETAIL)); // 方向取负，朝向波前进方向。
	data.worldPos = wavePos / physics_oceanWaveHorizontalScale / PHYSICS_XZ_SCALE; // 还原世界位置。
	data.height = height / waveSum * physics_oceanHeight * factor - physics_oceanHeight * factor * 0.5; // 归一化并按海面高度缩放、居中。

	data.normal = physics_waveNormal(position, data.direction, factor, time); // 复用上面的法线合成。

	float waveAmplitude = data.height * pow(max(data.normal.y, 0.0), 4.0); // 波峰处的振幅，用来抑制泡沫。
	vec2 waterUV = mix(position - physics_waveOffset, data.worldPos, clamp(factor * 2.0, 0.2, 1.0)); // 泡沫采样坐标在原始位置与波后位置间混合，避免泡沫拉花。

	vec2 s1 = textureLod(physics_foam, vec3(waterUV * 0.26, physics_globalTime / 360.0), 0).rg; // 泡沫噪声第一层。
	vec2 s2 = textureLod(physics_foam, vec3(waterUV * 0.02, physics_globalTime / 360.0 + 0.5), 0).rg; // 泡沫噪声第二层。
	vec2 s3 = textureLod(physics_foam, vec3(waterUV * 0.1, physics_globalTime / 360.0 + 1.0), 0).rg; // 泡沫噪声第三层。

	float waterSurfaceNoise = s1.r * s2.r * s3.r * 2.8 * physics_foamAmount; // 三层噪声相乘得到泡沫形状。
	waveAmplitude = clamp(waveAmplitude * 1.2, 0.0, 1.0); // 振幅夹到零到一。
	waterSurfaceNoise = (1.0 - waveAmplitude) * waterSurfaceNoise + waveAmplitude * physics_foamAmount; // 波峰处泡沫更强。

	float worleyNoise = 0.2 + 0.8 * s1.g * (1.0 - s2.g); // 用噪声的另一个通道做细胞状调制。
	float waterFoamMinSmooth = 0.45; // 泡沫起始阈值。
	float waterFoamMaxSmooth = 2.0; // 泡沫最大增益。
	waterSurfaceNoise = smoothstep(waterFoamMinSmooth, 1.0, waterSurfaceNoise) * worleyNoise; // 平滑阈值并乘细胞调制。

	data.foam = clamp(waterFoamMaxSmooth * waterSurfaceNoise * physics_foamOpacity, 0.0, 1.0); // 得到最终泡沫强度。

	return data; // 返回完整数据。
}

#endif // 文件守卫结束。
