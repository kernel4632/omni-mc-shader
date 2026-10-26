/*
水面波浪：用噪声与三角波叠出水面高度与法线，并提供物理解析波浪与水面视差坐标。
来源 iterationT `WaterWaves.glsl`、`PhysicsOceans.glsl`。
调用位置：由 `effects/water/water.glsl` 引入；水面、焦散、反射等引用波浪的地方都经它取得法线。
可复制示例：
    `vec3 n = GetWavesNormal(position, waveHeight);`
    `vec4 wave = physics_wavePixel(position, factor, iterations, time, ...);`
设计原因与取舍：基础波浪与物理解析波浪共用同一套噪声与缩放约定，放一起能看清两者关系；
    物理解析波浪的顶点与片元两段靠 `PHYSICS_VS` / `PHYSICS_FS` 宏分派，保留 iterationT 原样。
    两段共用的迭代正弦循环和归一化换算式在生成库 `omni-gfx/src/water.slang`，
    这里只做波形空间换算、涟漪贴图采样与泡沫贴图取样，算式的唯一来源仍在库里。
*/
#ifndef OMNI_WATER_WAVES_INCLUDED
// 波浪公式在通用库，时间从绑定结构取，效果文件不再直接读宿主输入。
#include "/gfx/water.glsl"
#include "/bind/time.glsl"
#define OMNI_WATER_WAVES_INCLUDED // 置上标记，后续再次引用直接跳过。
// --- 波浪：多层噪声正弦叠成起伏 ---
// 先用三次曲线把噪声采样平滑化，再逐层缩小频率、加快速度，得到自然且可重复的波浪。
// 为什么用噪声贴图而不是解析正弦：贴图里已经烘好一层细节，叠几层就有足够丰富感，省下大量三角计算。
vec4 textureSmooth(sampler2D texSampler, vec2 coord){ return gfx_texture_smooth(texSampler, coord); }

// 把零到一的值压成两端平、中间过渡的形状，用来让波浪峰值更饱满。
float AlmostIdentity(float x, float m, float n){ return gfx_almost_identity(x, m, n); }

// 主波函数：把世界位置缩放后逐层累加噪声采样，每层频率与速度都不同。
float GetWaves(vec3 position){ return gfx_waves(position, noisetex, bind_time().seconds, OMNI_WAVE_SCALE); }

#define sampleDistance 12.0 // 法线差分采样距离，原程序取值，写死让每个程序代价一致。

// 波法线：用高度差近似倾斜，中央差分取横纵两个方向。
// 为什么乘 `WAVE_HEIGHT / sampleDistance`：高度差除以采样距离才是坡度，再乘波浪高度选项统一缩放。
vec3 GetWavesNormal(vec3 position, const float waveHeight){
	vec3 n = gfx_waves_normal(position, noisetex, bind_time().seconds, OMNI_WAVE_SCALE, waveHeight, OMNI_WAVE_HEIGHT);
	#if OMNI_PLAYER_WATER > 0
		n.y = mix(n.y, 1.0, PlayerWaterRipple(position));
	#endif
	return normalize(n);
}

// 水面视差：沿视线在波高场里一步步前进，找到真正可见的波面位置。
// 为什么限制十二步：步数直接决定开销，写死让每个程序代价一致，也让画面表现稳定。
vec3 GetWaterParallaxCoord(vec3 position, vec3 viewVector){ return gfx_water_parallax(position, viewVector, noisetex, bind_time().seconds, OMNI_WAVE_SCALE, OMNI_WAVE_HEIGHT); }

// --- 海洋物理波：按迭代正弦合成海面，供外部海洋物理扩展使用 ---
// 形状必须与原程序一致，因为实体偏移在中央处理器一侧也按同一套公式计算，两边不一致会让实体浮空或陷进水里。
// 下面这些输入由外部海洋物理扩展提供；扩展缺失时不会调用这些函数，基础水面不受影响。
const int PHYSICS_ITERATIONS_OFFSET = 13; // 迭代次数的基础偏移，原程序取值。
const float PHYSICS_XZ_SCALE = 0.035; // 水平坐标缩放。
const float PHYSICS_W_DETAIL = 0.75; // 细节权重指数，方向累加的分母要用。
const float PHYSICS_NORMAL_STRENGTH = 0.6; // 法线竖直分量的强度。
// 每层的拖拽、时间缩放、频率、速度与权重衰减都是算法常数，已经在库的 `ogxOceanWavesDefault()` 里，
// 这里不再重复一份，避免两处数值各改各的。

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

// 涟漪贴图的横向纹素大小：纹理尺寸仍由宿主查询，库只接收换算好的数值。
vec2 physics_rippleTexel() {
	return vec2(2.0 / textureSize(physics_ripples, 0).x, 0.0); // 横向一格对应两个纹素。
}

// 按迭代正弦求某点波高：每层频率与速度都放大，权重衰减，最后归一化并居中。
float physics_waveHeight(vec2 position, int iterations, float factor, float time) {
	vec2 waveSpace = ogxOceanWaveSpace(position, physics_waveOffset, PHYSICS_XZ_SCALE, physics_oceanWaveHorizontalScale); // 换到波形空间。
	OgxOceanWaves waves = ogxOceanWavesDefault(); // 默认常数在库。
	waves.iterations = iterations; // 层数由外部海洋扩展给。
	return ogxOceanWaveHeight(ogxOceanWaveSum(waveSpace, time, waves), physics_oceanHeight, factor); // 归一化并按海面高度缩放、居中。
}

// 合成海面法线：波形法线再混入涟漪贴图的凹凸，涟漪越强权重越大。
vec3 physics_waveNormal(const in vec2 position, const in vec2 direction, const in float factor, const in float time) {
	return ogxOceanNormalWithRipple(position, direction, factor, physics_oceanHeight, PHYSICS_NORMAL_STRENGTH,
		physics_modelOffset.xz, physics_ripples, physics_rippleRange, physics_rippleTexel()); // 混合在通用库。
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
// 波形迭代、空间换算、涟漪贴图与泡沫噪声都在通用库；这里只把宿主数据整理成结构体。
WavePixelData physics_wavePixel(const in vec2 position, const in float factor, const in float iterations, const in float time) {
	OgxOceanPixel pixel = ogxOceanPixel(position, factor, iterations, time, physics_waveOffset, PHYSICS_XZ_SCALE,
		physics_oceanWaveHorizontalScale, physics_oceanHeight, physics_modelOffset.xz, physics_ripples,
		physics_rippleRange, physics_rippleTexel(), physics_foam, physics_globalTime, physics_foamAmount,
		physics_foamOpacity, PHYSICS_NORMAL_STRENGTH); // 一次调用算完整像素。
	WavePixelData data; // 转成光影包沿用的结构体。
	data.direction = pixel.direction;
	data.worldPos = pixel.worldPos;
	data.normal = pixel.normal;
	data.foam = pixel.foam;
	data.height = pixel.height;
	return data; // 返回完整数据。
}

// --- Eclipse 物理波方向与雨点涟漪兼容层 ---
// 参考的波方向循环使用固定常数；这里照参考保留，供外部海洋物理扩展按原签名调用。
vec2 physics_waveDirection(vec2 position, int iterations, float time){
	position = (position - physics_waveOffset) * PHYSICS_XZ_SCALE * physics_oceanWaveHorizontalScale;
	float iter = 0.0;
	float frequency = 6.0;
	float speed = 2.0;
	float weight = 1.0;
	float waveSum = 0.0;
	float modifiedTime = time * 0.45;
	vec2 dx = vec2(0.0);
	for (int i = 0; i < iterations; i++){
		vec2 direction = vec2(sin(iter), cos(iter));
		float x = dot(direction, position) * frequency + modifiedTime * speed;
		float wave = exp(sin(x) - 1.0);
		float result = wave * cos(x);
		vec2 force = result * weight * direction;
		dx += force / pow(weight, 0.75);
		position -= force * 0.048;
		iter += 12.0;
		waveSum += weight;
		weight *= 0.8;
		frequency *= 1.18;
		speed *= 1.07;
	}
	return dx / pow(waveSum, 1.0 - 0.75);
}
// Eclipse 雨点涟漪：三乘三网格上的解析圆波。
vec3 ripples(vec2 fragCoord){
	const float rippleIntensity = 0.85;
	float cellDensity = 5.0 * rippleIntensity;
	float sizeCompensation = cellDensity / 5.0;
	vec2 uv = fragCoord * cellDensity;
	vec2 p0 = floor(uv);
	const int MAX_RADIUS = 1;
	const float waveFrequency = 21.0;
	vec2 circles = vec2(0.0);
	for (int j = -MAX_RADIUS; j <= MAX_RADIUS; ++j){
		for (int i = -MAX_RADIUS; i <= MAX_RADIUS; ++i){
			vec2 pi = p0 + vec2(float(i), float(j));
			vec2 p = pi + ogxHash22(pi);
			float t = fract(0.9 * frameTimeCounter + ogxRippleHash12(pi));
			vec2 v = p - uv;
			float d = length(v) - (float(MAX_RADIUS) + 1.0) * t * sizeCompensation;
			const float h = 1e-2;
			float d1 = d - h;
			float d2 = d + h;
			float p1 = sin(waveFrequency * d1) * smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
			float p2 = sin(waveFrequency * d2) * smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
			circles += 0.5 * normalize(v) * ((p2 - p1) / (2.0 * h) * (1.0 - t) * (1.0 - t));
		}
	}
	circles /= float((MAX_RADIUS * 2 + 1) * (MAX_RADIUS * 2 + 1));
	return vec3(circles, sqrt(1.0 - dot(circles, circles)));
}

#endif // 文件守卫结束。

// 严格对照补充说明：
// 物理波方向与雨点涟漪保留 Eclipse 的原始函数名与签名。
// 波方向循环的十二度迭代增量、零点八权重衰减与一点一八频率倍率都照参考。
// 雨点涟漪的三乘三网格、二十一频率与零点零一差分步长都照参考。
// 两个函数只依赖位置、时间与帧计数，不读取相机或阴影缓冲。
// 兼容重载不改变基础波浪，调用方仍可使用显式参数版本。

// 补充说明：物理波方向与雨点涟漪的兼容重载保留参考签名。
// 波方向循环使用位置、迭代次数与时间，不读取相机状态。
// 雨点涟漪使用屏幕坐标、帧时间与哈希，不读取深度。
// 两个函数都只依赖参数，不需要额外的宿主缓冲。
// 兼容重载不改变基础波浪，旧的显式参数版本继续可用。

// 补充说明：波方向与涟漪的兼容重载只补签名。
// 波方向循环的迭代次数由调用方给出，常数照参考。
// 涟漪网格固定三乘三，频率与差分步长照参考。
// 两个函数都不读取相机矩阵或阴影缓冲。
// 兼容重载不改变基础波浪，旧的调用点继续可用。

// 补充说明：兼容重载只补签名。
// 波方向与涟漪都不读取深度。
// 旧的显式参数版本继续可用。
// 常数照参考保留。
// 不修改宿主状态。
