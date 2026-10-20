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

// 粉末效应：光穿过薄雾时，背光方向略微增亮，模拟多次散射。
float gfx_powder_effect(float absorption, float lightingAbsorption, float VdotL){
	return mix((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越少效果越强。
}

// 混合前后向的雾相位，让雾在逆光和顺光下都不过分刺眼。
float gfx_fog_phase(float VdotL){
	return gfx_MiePhaseFunction(-0.4, VdotL) * 0.3 + gfx_MiePhaseFunction(0.5, VdotL) * 0.7; // 三成后向、七成前向。
}

// 多次散射相位：把观察角按一半递减，重复四次，写入长度四的数组。
void gfx_multi_scattering_phases(float VdotL, inout float phases[4]){
	float factor = 1.0; // 每一级的夹角倍率。
	for (int i = 0; i < 4; i++, factor *= 0.5){
		phases[i] = gfx_fog_phase(VdotL * factor); // 记录这一级的相位。
	}
}

// 三维噪声：用噪声贴图两通道做一次三线性插值，得到零到一的密度。
float gfx_fog_noise(vec3 position, sampler2D noiseTexture){
	vec3 p = floor(position); // 整数格。
	vec3 f = position - p; // 格内小数偏移。
	f = f * f * (3.0 - 2.0 * f); // 三次曲线平滑小数。
	vec2 uv = 17.0 * p.z + p.xy + f.xy; // 把三维格子映射到二维噪声坐标。
	vec2 n = textureLod(noiseTexture, uv * 0.015625 + 0.0078125, 0.0).zw; // 读噪声贴图后两通道。
	return mix(n.x, n.y, f.z); // 按高度插值。
}

// 仅高度衰减的雾密度：两档高度之间最浓，超出后指数下降。
float gfx_fog_density_height(vec3 fogPos, float heightA, float heightB, float falloff, float timeMidnight){
	float maxHeight = max(heightA, heightB); // 两档里较高的。
	float minHeight = min(heightA, heightB); // 两档里较低的。
	float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到最浓区间外的距离。
	dh *= 2.0 / falloff; // 按衰减距离归一化。
	float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里更浓。
	return density * 0.1; // 缩到合理量级。
}

// 团雾密度：高度包络乘三层噪声叠出的雾团。
float gfx_fog_density_noise(vec3 fogPos, vec3 wind, float heightA, float heightB, float falloff, float timeMidnight, sampler2D noiseTexture){
	float dh = abs(fogPos.y - max(heightA, heightB)); // 到最高密度高度的距离。
	dh *= 1.0 / falloff; // 按衰减距离归一化。
	float envelope = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
	float density = 0.0; // 累加的雾密度。
	fogPos = fogPos * 0.02 + wind; // 换到雾坐标并叠加风速。
	for (float alpha = 0.5; alpha >= 0.125; alpha *= 0.5){ // 三层不同频率的噪声。
		density += alpha * gfx_fog_noise(fogPos, noiseTexture); // 按权重累加。
		fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
	}
	density *= envelope; // 乘高度衰减。
	density = density * density; // 平方拉开明暗。
	return density * density * 3.0; // 再平方并放大，得到清晰边界。
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

// 末地三维噪声：把世界坐标折成三维格子，再查二维噪声图。
float gfx_end_3d_noise(vec3 position, sampler2D noiseTexture){
	vec3 p = floor(position); // 整数格。
	vec3 b = fract(position); // 格内偏移。
	b = b * b * (3.0 - 2.0 * b); // 平滑偏移。
	vec2 uv = 17.0 * p.z + p.xy + b.xy; // 三维到二维的坐标分配。
	vec2 rg = textureLod(noiseTexture, (uv + 0.5) / 64.0, 0.0).zx; // 读噪声两个通道。
	return mix(rg.x, rg.y, b.z); // 按高度插值。
}

#endif
