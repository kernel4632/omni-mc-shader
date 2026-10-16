/*
水面：把 iterationT 的波浪、海洋物理波、雨点涟漪、水下雾、折射与彩色玻璃吸收集中到一个文件。
职责分成四块：
  一、选项：`OMNI_WAVE_SCALE`、`OMNI_WAVE_HEIGHT`、`OMNI_WATER_PARALLAX`、`OMNI_UNDERWATER_FOG`、`OMNI_WATERFOG_DENSITY`、`OMNI_CAUSTICS`，全项目只在这里定义一次；
  二、波浪：`GetWaves`、`GetWavesNormal`、`GetWaterParallaxCoord` 用噪声贴图叠多层正弦，算出波高、波法线与视差坐标；
  三、物理海浪：`physics_*` 一组函数按迭代正弦合成海面，供海洋物理扩展使用；
  四、屏幕合成：`WaterFog` 水下与水面雾、`WaterRefractionLite` 折射、`TransparentAbsorption` 彩色玻璃吸收，以及雨点涟漪 `GetRainNormal`。
调用位置：
  `rendering/translucent.glsl` 顶点阶段用 `GetWaterParallaxCoord`、`GetWavesNormal` 抬升水面并造波；
  `rendering/composite.glsl` 屏幕合成阶段用 `WaterFog`、`WaterRefractionLite`、`TransparentAbsorption`；
  `effects/shadow.glsl` 的焦散读取七号画面里的波法线，与本文件共用 `GetWavesNormal` 写出的数据。
可复制示例：
  `vec3 normal = GetWavesNormal(worldPos, OMNI_WAVE_HEIGHT);`  由世界位置得到波法线；
  `WaterFog(color, viewDir, opaqueDist, waterDist, normal, mask, occludedWater, waterSkylight, totalInternalReflection);`  水下与水后雾。
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明这些全局量）：
  `MaterialMask` 结构由 `effects/material.glsl` 提供（本文件已显式引入）；
  `ivec2 texelCoord`、`vec2 screenCoordInput` 由延迟与合成主程序声明；
  `in vec3 colorShadowlight`、`in vec3 colorSkylight` 等光色输入由合成主程序声明；
  物理海浪的 `physics_*` 输入由外部海洋物理扩展提供，缺失时对应函数不被调用，不影响基础水面；
  雨点涟漪的 `rainStrength` 与 `gaux1`、`gaux2`、`gaux3` 三张动画贴图由几何阶段主程序声明。
关键设计原因与取舍：
  波浪高度与法线都从 `GetWaves` 一处取，顶点抬升和片元法线不会各写一套而对不上；
  折射采样附带防泄漏：偏移后的位置若落在水面前方就退回原位，避免前景颜色漏进水里；
  水下雾与彩色玻璃吸收只用分波段衰减，红衰减最快、蓝最慢，水越深越偏青绿。
*/
#ifndef OMNI_WATER_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_WATER_INCLUDED // 置上标记，后续再次引用直接跳过。

// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"波浪密度","en_us":"Wave scale"},"description":{"zh_cn":"水面波纹的空间频率；调大波纹更密更细。","en_us":"Spatial frequency of the water ripples; larger makes them finer."},"slider":true}
#define OMNI_WAVE_SCALE 0.05 // [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"波浪高度","en_us":"Wave height"},"description":{"zh_cn":"水面起伏的强度；调大波浪更明显。","en_us":"Strength of the water surface undulation; larger makes waves more visible."},"slider":true}
#define OMNI_WAVE_HEIGHT 1.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"水面视差","en_us":"Water parallax"},"description":{"zh_cn":"按波浪高度偏移水面采样，让波峰看起来真的凸起；关闭后只用法线造形。","en_us":"Offsets water sampling by wave height so crests look raised; off keeps shape from normals only."}}
#define OMNI_WATER_PARALLAX
// @option {"label":{"zh_cn":"水下雾","en_us":"Underwater fog"},"description":{"zh_cn":"在水下或隔着水看远处时叠加雾；关闭后水更通透。","en_us":"Adds fog when underwater or looking through water; off makes the water clearer."}}
#define OMNI_UNDERWATER_FOG
// @option {"label":{"zh_cn":"水雾密度","en_us":"Water fog density"},"description":{"zh_cn":"水下与水后雾的浓度；调大看得更近。","en_us":"Density of underwater and through-water fog; larger reduces visibility."},"slider":true}
#define OMNI_WATERFOG_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"水面焦散","en_us":"Water caustics"},"description":{"zh_cn":"阳光透过波动水面在水底汇聚出的亮纹。","en_us":"Bright patterns where sunlight focuses through the rippling water onto the bottom."}}
#define OMNI_CAUSTICS

// 波法线解码与颜色曲线来自共用计算，屏幕还原与投影来自坐标换算，`MaterialMask` 由材质文件提供。
#include "/common/math.glsl"
#include "/common/coordinates.glsl"
#include "/effects/ground/material.glsl"
// 局部降水开关决定雨点涟漪是否跟随降雨，归属天气文件。
#include "/effects/weather/weather.glsl"

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

// 按迭代正弦求波形方向，与波高同源，只是累加拖拽力。
vec2 physics_waveDirection(vec2 position, int iterations, float time) {
	position = (position - physics_waveOffset) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale; // 换到波形空间。
	float iter = 0.0; // 每层方向角。
	float frequency = PHYSICS_FREQUENCY; // 当前层频率。
	float speed = PHYSICS_SPEED; // 当前层速度。
	float weight = 1.0; // 当前层权重。
	float waveSum = 0.0; // 累加权重。
	float modifiedTime = time * PHYSICS_TIME_MULTIPLICATOR; // 缩放后的时间。
	vec2 dx = vec2(0.0); // 累加方向。

	for (int i = 0; i < iterations; i++) { // 逐层叠加。
		vec2 direction = vec2(sin(iter), cos(iter)); // 当前层方向。
		float x = dot(direction, position) * frequency + modifiedTime * speed; // 当前层的相位。
		float wave = exp(sin(x) - 1.0); // 波峰更尖的包络。
		float result = wave * cos(x); // 波形值。
		vec2 force = result * weight * direction; // 对采样点的拖拽力。

		dx += force / pow(weight, PHYSICS_W_DETAIL); // 按细节指数累加方向。
		position -= force * PHYSICS_DRAG_MULT; // 采样点被拖拽。
		iter += PHYSICS_ITER_INC; // 方向角前进。
		waveSum += weight; // 累加权重。
		weight *= PHYSICS_WEIGHT; // 权重衰减。
		frequency *= PHYSICS_FREQUENCY_MULT; // 频率放大。
		speed *= PHYSICS_SPEED_MULT; // 速度放大。
	}

	return vec2(dx / pow(waveSum, 1.0 - PHYSICS_W_DETAIL)); // 归一化方向。
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

// --- 雨点涟漪：用三张动画贴图叠出雨滴落点，供水面与地表使用 ---
// 三层动画贴图越大越散开，用降雨强度与降雪、无降水标记调制，雪天与干燥群系不出现雨点。
// 为什么用三重噪声：单层噪声太规则，三层不同缩放叠加后落点更自然。
float Get3DNoise(vec3 pos){
	vec3 p = floor(pos); // 整数格。
	vec3 f = pos - p; // 格内小数。
	f = curve(f); // 平滑小数，插值更自然。

	vec2 uv = 17.0 * p.z + p.xy + f.xy; // 任意分配一个三维到二维的坐标。
	vec2 rg = textureLod(noisetex, (uv + 0.5) / 64.0, 0.0).zw; // 读噪声贴图后两个通道。

	return mix(rg.x, rg.y, f.z); // 按高度插值。
}

// 雨雾高光调制：三层噪声叠加后归一，让雨中的高光随时间轻微变化。
float GetModulatedRainSpecular(vec3 pos){
	pos.y *= 0.2; // 压缩竖直方向，雨高光在竖直上变化更慢。

	float n = Get3DNoise(pos); // 第一层。
		  n += Get3DNoise(pos * 0.5) * 2.0; // 第二层，缩小坐标并放大权重。
		  n += Get3DNoise(pos * 0.25) * 4.0; // 第三层，更细更高权重。

	n /= 7.0; // 归一化到大致零到一。

	return saturate(n) * 0.7 + 0.3; // 夹紧后留一个下限，避免完全无高光。
}

// 读一张雨点动画贴图并转成带符号的法线，指数控制边缘锐度。
vec2 GetRainAnimationTex(sampler2D texSampler, vec2 coord, float rp){
	vec2 n = textureLod(texSampler, coord, 0.0).rg; // 读红绿两通道。
	n =  n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 零到一转成负一到一，并翻转纵轴。
	n = pow(abs(n), vec2(rp)) * sign(n); // 按指数压形状，符号保留。
	return n; // 返回法线横纵分量。
}

// 雨点法线：按动画相位在贴图上采样，三层按降雨强弱叠加。
// 为什么用整数帧取模：让动画按固定帧率推进，避免不同刷新设备上速度不一致。
vec2 GetRainNormal(vec3 pos, float strength, inout float wet){
	pos.xyz *= 0.5; // 缩放坐标，让落点更大。
	#ifdef OMNI_DISABLE_LOCAL_PRECIPITATION // 强制局部无降水时只看整体降雨。
		strength *= rainStrength; // 只乘降雨强度。
	#else // 默认按所在群系的下雪与无降水标记调制。
		strength *= rainStrength * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth); // 雪天或干燥群系雨点减弱。
	#endif

	float frame = fract(floor(frameTimeCounter * 60.0) / 60.0); // 当前动画帧，按每秒六十帧取整。
	vec2 coord = vec2(pos.x, fract(pos.z / 60.0) - frame); // 动画沿一个轴滑动。

	float wet2 = wet * wet; // 湿润度平方。
	float rp = 2.0 - (wet2 * wet2) * 1.2; // 越湿边缘越锐。

	vec2 n1 = GetRainAnimationTex(gaux1, coord, rp); // 第一张动画贴图。
	vec2 n2 = GetRainAnimationTex(gaux2, coord, rp); // 第二张动画贴图。
	vec2 n3 = GetRainAnimationTex(gaux3, coord, rp); // 第三张动画贴图。

	pos.x -= frameTimeCounter * 0.5; // 沿一个轴漂移，落点缓慢移动。
	float downfall = textureLod(noisetex, pos.xz * 0.0025, 0.0).w; // 读噪声得到落点密度。
	downfall = saturate(downfall - 0.25); // 留一个阈值，稀疏区域没有雨点。

	vec2 n = n1; // 第一层总是有。
	n += n2 * saturate(downfall * 2.0); // 密度中等时叠第二层。
	n += n3 * saturate(downfall * 2.0 - 1.0); // 密度高时才叠第三层。

	float lod = dot(fwidth(pos.xz), vec2(1.0)); // 屏幕上的坐标变化量，用来按距离衰减。

	n /= lod * 5.0 + 1.0; // 越远越平，避免远处闪烁。
	n *= strength; // 乘降雨强度。

	wet = saturate(mix(downfall, wet, 1.0 - 0.4 * saturate(strength))); // 湿润度向落点密度靠拢，降雨越强越明显。

	return n; // 返回雨点法线。
}

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
	float visibility = exp2(-waterDist * fogDensity * OMNI_WATERFOG_DENSITY); // 按密度指数衰减得到可见度。

	visibility = clamp(visibility, 0.35 * mask.ice, 1.0); // 冰下留一个最低可见度。
	visibility = mix(visibility, 0.7, mask.hand); // 手持物只受七成雾影响，避免手被糊掉。

	vec3 attenuationColor = isEyeInWater == 0 ? vec3(0.2, 0.5, 0.7) : vec3(0.1, 0.6, 1.0); // 分波段衰减色，水下偏蓝。
	color *= pow(attenuationColor * 0.99, vec3(waterDist * (0.21 * float(isEyeInWater == 0) + 0.04) * OMNI_WATERFOG_DENSITY)); // 红衰减最快，蓝最慢。

	color = mix(waterFogColor, color, visibility); // 用可见度在雾色与场景色之间混合。
}

// --- 水面折射Lite：只移动一次采样坐标的轻量折射 ---
// 调用位置：`rendering/composite.glsl`；先把采样点按水面法线偏移，再读一号画面的颜色。
// 防泄漏：偏移后的采样点若比当前水面更近，说明采到了前景物体，直接退回原位。
// 为什么分成水面与水外两条路：水面用波法线偏移更贴合，水外的玻璃等用整段折射方向偏移更准确。
// 为什么像素坐标由调用方传 `texelCoord`：渲染缩放或放大链下 `screenCoordInput` 与 `screenSize` 的口径可能不同，
//   用传入的整数像素坐标直接读深度，才与原程序一致，不会差出一个像素。
void WaterRefractionLite(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist, float fogTimeFactor, float cloudShadow, vec2 screenCoordInput, ivec2 texelCoord){
	vec2 refractCoord = screenCoordInput; // 默认不折射，用原屏幕坐标。

	float waterDeep = opaqueDist - waterDist; // 水面到水底的厚度，越厚折射越强。

	if (mask.water > 0.5){ // 水面本身：用波法线偏移。
		float NdotU = dot(normal, gbufferModelView[1].xyz) + float(isEyeInWater == 1) * 2.0; // 法线朝向与水下判断。
		vec3 wavesNormal = GetWavesNormal(worldPos + cameraPosition, step(0.05, NdotU) * 18.0).xzy; // 求波法线并换到竖直轴朝上的坐标。
		vec4 wnv = gbufferModelView * vec4(wavesNormal.xyz, 0.0); // 波法线转到视空间。
		vec3 wavesNormalView = normalize(wnv.xyz); // 归一化。

		vec4 nv = gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0); // 平水面法线转到视空间。
		nv.xyz = normalize(nv.xyz); // 归一化。

		refractCoord = nv.xy - wavesNormalView.xy; // 两种法线的差就是折射偏移方向。
		refractCoord *= saturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深折射越强，除以距离避免远处偏移过大。
		refractCoord += screenCoordInput; // 加到原坐标上。
	}else{ // 玻璃等透明面：用整段折射方向。
		vec3 refractDir = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
		refractDir = refractDir / saturate(dot(refractDir, -normal)); // 归一化到视线方向。
		refractDir *= saturate(waterDeep * 2.0) * 0.125; // 按厚度缩放。

		vec4 refractPos = vec4(viewPos + refractDir, 0.0); // 折射后的视空间位置。
		refractPos = gbufferProjection * refractPos; // 投影到裁剪空间。

		refractCoord = refractPos.xy / refractPos.w * 0.5 + 0.5; // 转成屏幕坐标。
	}

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素的深度，直接用调用方传入的整数像素坐标，不靠屏幕坐标反推。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点的深度。
	if(refractDepth < currentDepth) refractCoord = screenCoordInput; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(screenCoordInput, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord, 0.0).rgb); // 读回折射后的场景颜色。

	#if (defined OMNI_LANDSCATTERING && defined OMNI_LANDSCATTERING_REFRACTION) || (defined OMNI_VFOG && defined OMNI_VFOG_REFRACTION) // 只在同时开启地表散射或体积雾的折射时，给玻璃后面补雾。
		if (mask.stainedGlass > 0.5){ // 只处理彩色玻璃。
			float rDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射点的深度。
			vec3 rViewPos = ViewPos_From_ScreenPos(refractCoord, rDepth); // 还原视空间位置。
			#ifdef DISTANT_HORIZONS // 有远景时，近景是天空就改用远景深度。
				if (rDepth == 1.0){ // 近景是天空。
					rDepth = textureLod(dhDepthTex1, refractCoord, 0.0).x; // 读远景深度。
					rViewPos = ViewPos_From_ScreenPos_DH(refractCoord, rDepth); // 远景还原位置。
				}
				float farDist = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
				#ifdef OMNI_DH_LIMIT_VFOG_DIST
					farDist = min(2048.0, farDist); // 限制雾距离上限。
				#endif
			#else
				float farDist = far * 1.4; // 没有远景时用近景远裁剪面估计。
			#endif

			float rDist = min(length(rViewPos) + float(rDepth == 1.0) * 1e10, farDist); // 折射点距离，天空给很远。
			rDist = max(rDist - waterDist, 0.0); // 减去水面距离，只剩水体厚度。

			vec3 rWorldPos = mat3(gbufferModelViewInverse) * rViewPos; // 折射点转回相机相对世界。
			vec3 rWorldDir = normalize(rWorldPos); // 世界方向。

			vec3 endPos = rWorldDir * rDist; // 雾的终点。

			color *= MAIN_OUTPUT_FACTOR; // 换成管线线性单位，雾函数按此单位工作。

			#ifdef OMNI_LANDSCATTERING
				#ifdef OMNI_LANDSCATTERING_REFRACTION
					LandAtmosphericScattering(color, rDist, worldPos, endPos, rWorldDir, rDepth == 1.0); // 给折射后的场景补地表散射。
				#endif
			#endif

			#ifdef OMNI_VFOG
				#ifdef OMNI_VFOG_REFRACTION
					float fogTransmittance = 1.0; // 透射率占位，本处不返回。
					if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, worldPos, endPos, rWorldDir, cloudShadow, fogTimeFactor, fogTransmittance); // 给折射后的场景补体积雾。
				#endif
			#endif

			color /= MAIN_OUTPUT_FACTOR; // 换回管线存储单位。
		}
	#endif
}

// --- 彩色玻璃吸收：按玻璃自身的颜色与不透明度吸收透过的光 ---
// 调用位置：`rendering/composite.glsl`；只影响彩色玻璃像素。
// 为什么把颜色归一化再乘回长度：贴图颜色可能很亮，先取方向与大致亮度，避免吸收过强或失效。
void TransparentAbsorption(inout vec3 color, vec4 stainedGlassAlbedo, float waterAbsorption){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	stainedGlassAlbedo.a = pow(stainedGlassAlbedo.a, 0.2); // 抬升不透明度曲线，让吸收更明显。

	#ifdef OMNI_UNDERWATER_FOG // 水下时玻璃吸收按水的吸收程度缩放。
		if (isEyeInWater == 1) stainedGlassAlbedo.a = mix(0.0, stainedGlassAlbedo.a, waterAbsorption); // 水越浅吸收越弱。
	#endif

	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, stainedGlassAlbedo.a)); // 按不透明度在无吸收与玻璃色之间混合后吸收。
}
#endif // 文件守卫结束。
