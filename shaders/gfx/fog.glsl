/*
通用图形库雾模块：粉末效应与多次散射相位。
调用位置：任何需要体积雾或体积云散射的程序；本仓库由 `effects/fog/volumetric.glsl` 转发调用。
可复制示例：
    float p = gfx_fog_phase(VdotL); // 混合前后向的散射相位。
    float w = gfx_powder_effect(absorption, lightingAbsorption, VdotL); // 粉末效应权重。
    gfx_multi_scattering_phases(VdotL, phases); // 四次衰减的相位。
设计原因与取舍：
    只做纯数学，不读取纹理或选项；雾密度、步进与光源方向由调用方负责。
    相位函数复用数学模块里的米氏相位，避免同一公式出现两份。
*/
#ifndef GFX_FOG_INCLUDED
#define GFX_FOG_INCLUDED

#include "/gfx/math.glsl"
// 迁移后的效果实现在生成库里。
#include "/omni-gfx/fog.glsl"

// 粉末效应：光穿过薄雾时，背光方向略微增亮，模拟多次散射。
float gfx_powder_effect(float absorption, float lighting_absorption, float vdot_l){
	return ogxLegacyPowder(absorption, lighting_absorption, vdot_l); // 实现在生成库。
}

// 混合前后向的雾相位，让雾在逆光和顺光下都不过分刺眼。
float gfx_fog_phase(float vdot_l){
	return ogxLegacyFogPhase(vdot_l); // 实现在生成库。
}

// 多次散射相位：把观察角按一半递减，重复四次，写入长度四的数组。
void gfx_multi_scattering_phases(float vdot_l, inout float phases[4]){
	vec4 values = ogxMultiScatteringPhases(vdot_l); // 四档相位一次算完。
	phases[0] = values.x; // 第一档。
	phases[1] = values.y; // 第二档。
	phases[2] = values.z; // 第三档。
	phases[3] = values.w; // 第四档。
}

// 三维噪声：用噪声贴图两通道做一次三线性插值，得到零到一的密度。
float gfx_fog_noise(vec3 position, sampler2D noise_texture){
	return ogxFogNoise(position, noise_texture); // 实现在生成库。
}

// 仅高度衰减的雾密度：两档高度之间最浓，超出后指数下降。
float gfx_fog_density_height(vec3 fog_pos, float height_a, float height_b, float falloff, float time_midnight){
	return ogxFogDensityHeight(fog_pos, height_a, height_b, falloff, time_midnight); // 实现在生成库。
}

// 团雾密度：高度包络乘三层噪声叠出的雾团。
float gfx_fog_density_noise(vec3 fog_pos, vec3 wind, float height_a, float height_b, float falloff, float time_midnight, sampler2D noise_texture){
	return ogxFogDensityNoise(fog_pos, wind, height_a, height_b, falloff, time_midnight, noise_texture); // 实现在生成库。
}

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float gfx_nether_fog_density_at(vec3 pos, sampler2D noiseTexture){
	pos /= 18.0; // 整体缩小，让格子更大。
	pos.xz *= 0.5; // 水平再压一半，雾团更扁。
	vec3 p = floor(pos); // 整数格坐标。
	vec3 f = fract(pos); // 格内小数偏移。
	f = f * f * (3.0 - 2.0 * f); // 平滑小数。
	vec2 uv = p.xz + f.xz + p.y * vec2(0.0, 193.0); // 三维格子映射到二维图。
	vec2 coord = uv / 512.0; // 换成零到一坐标。
	vec2 xy = texture(noiseTexture, coord).yx; // 读两通道并交换。
	return mix(xy.r, xy.g, f.y); // 按高度插值。
}

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
float gfx_nether_fog_cloud_volume(vec3 pos, float time, sampler2D noiseTexture){
	vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直拉伸，烟柱显得更高。
	float wind = pow(max(pos.y - 30.0, 0.0) / 15.0, 2.1); // 越高风偏移越大。
	float plumes = texture(noiseTexture, (samplePos.xz + wind) / 256.0).b; // 噪声蓝通道当羽流形状。
	float floorPlumes = clamp(0.3 - exp(plumes * -6.0), 0.0, 1.0); // 贴地烟的量。
	plumes *= plumes; // 平方拉开烟与空的差别。
	float erosion = gfx_nether_fog_density_at(samplePos * 400.0 - time * 10.0 - wind * 10.0, noiseTexture) * 0.7 + 0.3; // 随时间的侵蚀。
	float roofToFloor = exp(max(100.0 - pos.y, 0.0) / -15.0); // 从天花板到地面变淡。
	float floorFalloff = pow(exp(max(pos.y - 31.0, 0.0) / -3.0), 2.0); // 离地越高越淡。
	return max((roofToFloor - plumes * (1.0 - erosion)) * 2.0, clamp((floorFalloff - floorPlumes * 0.5) * erosion, 0.0, 1.0)); // 两种形状取大者。
}

// --- 末地体积涡旋雾：绕主岛旋转的浓雾、雾中光柱与雾霭 ---
// 以下函数全部接收显式参数：时间、相机位置、采样器与噪声图边长都由调用方传入，
// 这样同一套算法可以脱离 Minecraft 单独使用，也便于逐项对比原程序。

// 读一张贴着世界坐标的三维噪声：水平切格后，用噪声贴图的上下两层按高度插值。
// 输入是世界坐标、噪声贴图与贴图边长；输出零到一的密度，值越大雾团越浓。
float gfx_end_vortex_noise(vec3 pos, sampler2D noiseTexture, float noiseResolution){
	pos /= 18.0; // 把世界坐标缩到十八分之一，决定颗粒在世界里的稀密。
	pos.xz *= 0.5; // 水平方向再压一半，让雾团沿竖直方向拉长。
	vec3 cell = floor(pos); // 所在整数格。
	vec3 f = fract(pos); // 格内偏移。
	f = (f * f) * (3.0 - 2.0 * f); // 平滑权重，让格与格之间不出现硬边。
	vec2 uv = cell.xz + f.xz + cell.y * vec2(0.0, 193.0); // 三维到二维的坐标分配，一百九十三是原程序用来打散高度的常数。
	vec2 xy = textureLod(noiseTexture, uv / noiseResolution, 0.0).yx; // 读两个通道并交换，得到上下两层的值。
	return mix(xy.r, xy.g, f.y); // 按格内高度在两层之间插值。
}

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
// `alteredOrigin` 是要被旋转的采样坐标，`origin` 是这一步的真实位置，用来算旋转强度，`time` 是累计秒数。
void gfx_end_vortex_swirl(inout vec3 alteredOrigin, vec3 origin, float time){
	float radiance = 2.39996 + alteredOrigin.y / 1.5 + time / 50.0; // 旋转角随时间与高度推进，二点三九九九六是原程序的起始角。
	mat2 rotation = mat2(vec2(cos(radiance), -sin(radiance)), vec2(sin(radiance), cos(radiance))); // 二维旋转矩阵。
	float swirlBounds = clamp(sqrt(max(length(vec3(origin.x, origin.y - 100.0, origin.z)) / 200.0 - 1.0, 0.0)), 0.0, 1.0); // 只在离中心一定半径内转，越远越接近不转；原程序省略了零下限，这里补上以免近中心处对负数开方得到无效值。
	alteredOrigin.xz = mix(alteredOrigin.xz * rotation, alteredOrigin.xz, swirlBounds); // 按强度在旋转后与原始坐标之间插值。
}

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void gfx_end_vortex_bounds(inout float volume, vec3 origin){
	vec3 origin2 = origin - vec3(0.0, 100.0, 0.0); // 相对高度一百的中心。
	origin2.y *= 0.8; // 竖直压扁，让限制形状更扁。
	float center = length(origin2); // 到中心的距离。
	float bounds = max(1.0 - center / 95.0, 0.0) * 5.0; // 中心九十五格内的球状减薄。
	float radius = 150.0; // 主岛圆环的半径。
	float thickness = 25.0 * radius; // 圆环判定的厚度尺度，数值取大以得到平缓的边缘。
	float torus = (thickness - clamp(pow(length(vec2(length(origin.xz) - radius, origin2.y)), 2.0) - radius, 0.0, thickness)) / thickness; // 圆环外的减薄量。
	volume = max(volume - bounds - torus, 0.0); // 两种减薄叠加后夹到零以上。
}

// 雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
// 输入是世界坐标、累计秒数、噪声贴图与边长；输出这一点的雾密度。
float gfx_end_vortex_shape(vec3 pos, float time, sampler2D noiseTexture, float noiseResolution){
	float vortexBounds = clamp(300.0 - length(pos), 0.0, 1.0); // 距世界原点三百格内为涡旋核心，对应原程序的 `vortexBoundRange`。
	vec3 samplePos = pos * vec3(1.0, 1.0 / 48.0, 1.0); // 竖直方向压得很扁，得到分层的云感。
	float voidZone = max(exp2(-sqrt(max(pos.y + 60.0, 0.0))), 0.0); // 主岛下方六十格起向下逐渐发白的虚空区，原程序写作 `pos.y - -60`。
	gfx_end_vortex_swirl(samplePos, pos, time); // 把采样坐标按漩涡旋转。
	float noise = gfx_end_vortex_noise(samplePos * 12.0, noiseTexture, noiseResolution); // 基础噪声，决定雾团的浓淡。
	float erosion = 1.0 - gfx_end_vortex_noise((samplePos - time / 18.0) * (124.0 + (1.0 - noise) * 7.0), noiseTexture, noiseResolution); // 随时间上升并放大的侵蚀噪声，把雾掏空。
	float clumpyFog = max(exp(noise * -mix(10.0, 4.0, vortexBounds)) * mix(2.0, 1.0, vortexBounds) - erosion * 0.32, 0.0); // 噪声越浓雾越厚，再减去侵蚀。
	gfx_end_vortex_bounds(clumpyFog, pos); // 按体积限制减薄。
	return clumpyFog + voidZone; // 返回带虚空区的雾密度。
}

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float gfx_end_vortex_light_phase(vec3 lightPos){
	float falloff = exp(length(lightPos) / -50.0); // 每离中心五十格衰减到约三分之一七。
	return (falloff * 10.0) * (falloff * 10.0); // 平方放大，让光柱更集中。
}

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
vec3 gfx_end_vortex_lighting(vec3 startPos, vec3 lightPos, float density, vec3 lightColor, float time, sampler2D noiseTexture, float noiseResolution){
	float phase = gfx_end_vortex_light_phase(lightPos); // 到光柱中心的相位。
	float shadow = 0.0; // 沿光方向累积的遮挡。
	for (int j = 0; j < 3; j++){ // 三步采样雾的遮挡。
		vec3 shadowSamplePos = startPos - lightPos * (0.05 + float(j) * 0.25); // 从当前点向光柱中心退回采样。
		shadow += gfx_end_vortex_shape(shadowSamplePos, time, noiseTexture, noiseResolution); // 累加遮挡。
	}
	vec3 lighting = lightColor * phase * exp(-7.0 * shadow); // 直接来自光柱的亮光，被遮挡压暗。
	lighting += lightColor * phase * phase * (1.0 - exp(-shadow * vec3(0.6, 2.0, 2.0))) * (1.0 - exp(-density * density)); // 被雾散射开的二次亮光。
	return lighting; // 交回可直接叠加的雾内发光。
}

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
// `rgb` 是叠加到画面上的散射色，`a` 是透过雾后剩余的透射率；步数、步长分布、密度颜色与输出缩放全由参数给出，
// 因为远景开关、画质选项和阳光强度都属于宿主，通用库不读取它们。
vec4 gfx_end_vortex_fog(vec3 cameraPos, vec3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist,
		vec3 vortexColor, vec3 ambientColor, float stormScale, float hazeDensity, float time,
		sampler2D noiseTexture, float noiseResolution, float outputScale){
	vec3 rayWorld = worldDir * viewDist; // 相机到视线终点的世界向量。
	float rayLength = max(length(rayWorld), 1e-4); // 视线总长，下限防零长度相除。
	float marchLength = min(rayLength, maxDist); // 实际步进的总长度。
	rayWorld *= marchLength / rayLength; // 把世界向量缩到实际步进长度。
	float dL = length(rayWorld); // 缩放后的步进长度，供每步换算实际距离。
	vec3 color = vec3(0.0); // 累积的雾发光。
	float absorbance = 1.0; // 累积的透过率，用来给后面的光正确地留出通道。
	float skyPhase = (0.5 + pow(clamp(worldDir.y * 0.5 + 0.5, 0.0, 1.0), 4.0) * 5.0) * 0.1; // 抬头方向的雾霭权重。
	float dither2 = 1.0 - dither; // 第二组抖动，给步宽用。
	for (int i = 0; i < sampleCount; i++){ // 逐步前进。
		float d = (pow(expFactor, (float(i) + dither) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 这一步在视线上的比例，近密远疏。
		float dd = pow(expFactor, (float(i) + dither2) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 这一步的宽度。
		vec3 progressW = cameraPos + d * rayWorld; // 这一步的世界位置。
		vec3 lightPos = progressW - vec3(0.0, 200.0, 0.0); // 光柱锚在主岛上空二百格处，对应原程序纯涡旋分支的锚点。
		float volumeDensity = gfx_end_vortex_shape(progressW, time, noiseTexture, noiseResolution); // 这一步的雾密度。
		float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPos) / 100.0, 0.0), 1.0); // 相机一百格内留空，避免贴脸起雾。
		float stormDensity = min(volumeDensity, clearArea * clearArea * stormScale); // 风暴部分，按贴脸留空与密度封顶。
		float volumeCoeff = exp(-stormDensity * dd * dL); // 这一步之后的透过率。
		vec3 lightsources = gfx_end_vortex_lighting(progressW, lightPos, volumeDensity, vortexColor, time, noiseTexture, noiseResolution); // 这一步的雾内光柱发光。
		vec3 indirect = ambientColor * 0.2 * (exp((volumeDensity * volumeDensity) * -50.0) * 0.9 + 0.1) * 0.1; // 雾内环境光，越靠近浓雾越强。
		vec3 stormLighting = indirect + lightsources; // 这一步的总发光。
		color += (stormLighting - stormLighting * volumeCoeff) * absorbance; // 只把这一步真正发出的部分按透过率叠上。
		absorbance *= volumeCoeff; // 透过率继续衰减。
		vec3 hazeLighting = vec3(0.37, 0.32, 0.75) * skyPhase * 0.5; // 雾霭的冷紫散光。
		color += (hazeLighting - hazeLighting * exp(-hazeDensity * dd * dL)) * absorbance; // 雾霭不改变透过率，只按当前透过率叠上。
	}
	return vec4(color * outputScale, absorbance); // 散射色换算到管线单位，剩余透射率一并交回；缩放由调用方给出。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分，最后乘风暴与雾霭两层密度。
// `VdotL` 是视线与光方向余弦，`angleX`、`angleY` 是行星相位角，`planetShadow` 是行星遮挡权重；
// 两个缩放参数对应玩家选项，零表示去掉那一层。输出是未换算单位的密度。
float gfx_end_fog_density(vec3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale){
	mat3 eyeRoataionMatrixX = mat3(1.0, 0.0, 0.0, 0.0, cos(angleX), -sin(angleX), 0.0, sin(angleX), cos(angleX)); // 俯仰旋转。
	mat3 eyeRoataionMatrixY = mat3(cos(angleY), 0.0, sin(angleY), 0.0, 1.0, 0.0, -sin(angleY), 0.0, cos(angleY)); // 偏航旋转。
	mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY; // 合成旋转。

	vec3 dir = eyeRoataionMatrix * worldDir; // 视线转到相位坐标系。

	dist = min(dist, 512.0); // 距离封顶，远处不再变浓。
	float h = abs(dir.z) * dist * 0.03; // 沿视线方向的等效高度。
	float fogDepth = (1.0 - exp(-h)) / h * dist; // 密度沿距离的积分闭式解。

	float storm = gfx_MiePhaseFunction(0.3, VdotL) * 10.0 * planetShadow; // 带方向的风暴部分：米氏相位乘行星相位。
	float haze = 0.25; // 不带方向的雾霭基准部分。
	float density = fogDepth * (storm * stormScale + haze * hazeScale); // 两层分别缩放后相加。

	density *= planetShadow * 0.93 + 0.07; // 行星阴影压低密度。
	return density; // 交回未换算单位的密度。
}

// 末地三维噪声：把世界坐标折成三维格子，再查二维噪声图。
// `noiseResolution` 是噪声贴图边长，调用方可复用到不同尺寸的噪声图。
float gfx_end_3d_noise(vec3 position, sampler2D noiseTexture, float noiseResolution){
	vec3 p = floor(position); // 整数格。
	vec3 b = fract(position); // 格内偏移。
	b = b * b * (3.0 - 2.0 * b); // 平滑偏移。
	vec2 uv = 17.0 * p.z + p.xy + b.xy; // 三维到二维的坐标分配。
	vec2 rg = textureLod(noiseTexture, (uv + 0.5) / noiseResolution, 0.0).zx; // 读噪声两个通道。
	return mix(rg.x, rg.y, b.z); // 按高度插值。
}

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
// `shift` 是每层之间的时间位移，`noiseResolution` 是噪声贴图边长。
float gfx_cloud_fbm(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution){
	const int octaves = 4; // 层数。
	const float octAlpha = 0.87; // 每层权重衰减。
	const float octScale = 2.5; // 每层频率放大。
	const float octShift = (octAlpha / octScale) / octaves; // 层间偏移。

	float accum = 0.0; // 累积噪声。
	float alpha = 0.5; // 当前层权重。

	for (int i = 0; i < octaves; i++){ // 逐层叠加。
		accum += alpha * gfx_end_3d_noise(position, noiseTexture, noiseResolution); // 加这一层。
		position = (position + shift) * octScale; // 抬高频率并加位移。
		alpha *= octAlpha; // 权重衰减。
	}

	return accum + octShift; // 返回归一化后的噪声。
}

#endif
