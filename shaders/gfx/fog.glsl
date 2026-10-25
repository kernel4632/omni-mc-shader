/*
雾模块适配层：粉末效应、相位、高度雾、团雾、下界雾、末地涡旋雾与云状分形噪声已迁到生成库。
调用位置：`rendering/fog/*`、`rendering/world/{nether,end}.glsl` 与 `accretion` 适配层引用本文件；
    算式只在 `omni-gfx/src/fog.slang` 一份。
可复制示例：`float d = gfx_fog_density_height(fogPos, 60.0, 70.0, 10.0, 0.0);` 高度雾密度。
设计原因与取舍：函数名、参数顺序与输入输出参数保持原样，调用点无需改动，默认画面不会漂移；
    噪声贴图、时间、地图尺度与颜色全部由调用方传入，库不读取任何宿主状态。
*/
#ifndef GFX_FOG_INCLUDED
#define GFX_FOG_INCLUDED

// 数学与迁移后的雾实现。
#include "/gfx/math.glsl"
#include "/omni-gfx/fog.glsl"

// 粉末效应：光穿过薄雾时，背光方向略微增亮，模拟多次散射。
float gfx_powder_effect(float absorption, float lighting_absorption, float vdot_l){ return ogxLegacyPowder(absorption, lighting_absorption, vdot_l); } // 实现在生成库。

// 混合前后向的雾相位，让雾在逆光和顺光下都不过分刺眼。
float gfx_fog_phase(float vdot_l){ return ogxLegacyFogPhase(vdot_l); } // 实现在生成库。

// 多次散射相位：把观察角按一半递减，重复四次，写入长度四的数组。
void gfx_multi_scattering_phases(float vdot_l, inout float phases[4]){
	vec4 values = ogxMultiScatteringPhases(vdot_l); // 四档相位一次算完。
	phases[0] = values.x; // 第一档。
	phases[1] = values.y; // 第二档。
	phases[2] = values.z; // 第三档。
	phases[3] = values.w; // 第四档。
}

// 三维噪声：用噪声贴图两通道做一次三线性插值，得到零到一的密度。
float gfx_fog_noise(vec3 position, sampler2D noise_texture){ return ogxFogNoise(position, noise_texture); } // 实现在生成库。

// 仅高度衰减的雾密度：两档高度之间最浓，超出后指数下降。
float gfx_fog_density_height(vec3 fog_pos, float height_a, float height_b, float falloff, float time_midnight){ return ogxFogDensityHeight(fog_pos, height_a, height_b, falloff, time_midnight); } // 实现在生成库。

// 团雾密度：高度包络乘三层噪声叠出的雾团。
float gfx_fog_density_noise(vec3 fog_pos, vec3 wind, float height_a, float height_b, float falloff, float time_midnight, sampler2D noise_texture){ return ogxFogDensityNoise(fog_pos, wind, height_a, height_b, falloff, time_midnight, noise_texture); } // 实现在生成库。

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float gfx_nether_fog_density_at(vec3 pos, sampler2D noiseTexture){ return ogxNetherFogDensityAt(pos, noiseTexture); } // 实现在生成库。

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
float gfx_nether_fog_cloud_volume(vec3 pos, float time, sampler2D noiseTexture){ return ogxNetherFogCloudVolume(pos, time, noiseTexture); } // 实现在生成库。

// 读一张贴着世界坐标的三维噪声：水平切格后，用噪声贴图的上下两层按高度插值。
float gfx_end_vortex_noise(vec3 pos, sampler2D noiseTexture, float noiseResolution){ return ogxEndVortexNoise(pos, noiseTexture, noiseResolution); } // 实现在生成库。

// 把雾团的采样坐标绕竖直轴旋转：越靠近中心转得越强，形成漩涡。
void gfx_end_vortex_swirl(inout vec3 alteredOrigin, vec3 origin, float time){ ogxEndVortexSwirl(alteredOrigin, origin, time); } // 实现在生成库。

// 用中心球与主岛圆环限制雾的体积：中心球内和主岛圆环之外都让雾变薄。
void gfx_end_vortex_bounds(inout float volume, vec3 origin){ ogxEndVortexBounds(volume, origin); } // 实现在生成库。

// 雾团的形状：噪声加漩涡得到一团会转的云，并在主岛下方留一段虚空区。
float gfx_end_vortex_shape(vec3 pos, float time, sampler2D noiseTexture, float noiseResolution){ return ogxEndVortexShape(pos, time, noiseTexture, noiseResolution); } // 实现在生成库。

// 光柱的相位：离光柱中心越近越亮，中心处接近一百。
float gfx_end_vortex_light_phase(vec3 lightPos){ return ogxEndVortexLightPhase(lightPos); } // 实现在生成库。

// 雾中光柱的着色：三步取雾的遮挡，再按遮挡与自身密度叠出直射与散射。
vec3 gfx_end_vortex_lighting(vec3 startPos, vec3 lightPos, float density, vec3 lightColor, float time, sampler2D noiseTexture, float noiseResolution){ return ogxEndVortexLighting(startPos, lightPos, density, lightColor, time, noiseTexture, noiseResolution); } // 实现在生成库。

// 沿一条视线步进体积涡旋雾，返回散射色与剩余透射率。
vec4 gfx_end_vortex_fog(vec3 cameraPos, vec3 worldDir, float viewDist, float dither, int sampleCount, float expFactor, float maxDist, vec3 vortexColor, vec3 ambientColor, float stormScale, float hazeDensity, float time, sampler2D noiseTexture, float noiseResolution, float outputScale){
	return ogxEndVortexFog(cameraPos, worldDir, viewDist, dither, sampleCount, expFactor, maxDist, vortexColor, ambientColor,
		stormScale, hazeDensity, time, noiseTexture, noiseResolution, outputScale); // 实现在生成库。
}

// 末地解析雾的密度：视线先转到行星相位坐标系，再按等效高度做积分。
float gfx_end_fog_density(vec3 worldDir, float dist, float VdotL, float angleX, float angleY, float planetShadow, float stormScale, float hazeScale){
	return ogxEndFogDensity(worldDir, dist, VdotL, angleX, angleY, planetShadow, stormScale, hazeScale); // 实现在生成库。
}

// 末地三维噪声：把世界坐标折成三维格子，再查二维噪声图。
float gfx_end_3d_noise(vec3 position, sampler2D noiseTexture, float noiseResolution){ return ogxEnd3dNoise(position, noiseTexture, noiseResolution); } // 实现在生成库。

// 云状分形噪声：四层不同频率的三维噪声叠加，供吸积盘等体积细节使用。
float gfx_cloud_fbm(vec3 position, vec3 shift, sampler2D noiseTexture, float noiseResolution){ return ogxCloudFbm(position, shift, noiseTexture, noiseResolution); } // 实现在生成库。

#endif
