/*
吸积盘模块适配层：黑洞附近的步进积分、空间扭曲与盘着色已迁到生成库。
调用位置：`rendering/world/end_disc.glsl` 的天空版与反射版引用本文件；
    效果层只保留步数、起始距离与星空叠加，算法只在 `omni-gfx/src/accretion.slang` 一份。
可复制示例：`vec4 d = gfx_accretion_disc(rayDir, lightDir, noise, noiseTexture, seconds, 50, 3.0, 4, false, true);`
设计原因与取舍：函数名、参数顺序与返回值含义保持原样，两个调用点无需改动，默认画面不会漂移；
    噪声贴图与时间由调用方传入，库不读取宿主时间。
*/
#ifndef GFX_ACCRETION_INCLUDED
#define GFX_ACCRETION_INCLUDED

// 通用数学、雾噪声与迁移后的吸积盘实现。
// 下面三行只引入依赖，不在这里写任何算式。
#include "/gfx/math.glsl"
#include "/gfx/fog.glsl"
#include "/omni-gfx/accretion.glsl"

// 吸积盘积分：返回 rgb 盘颜色与 a 透过率。
// 天空版与反射版共用这一份积分，只换参数。
// 参数含义依次为视线、光方向、抖动、噪声图、时间、步数、起点距离、噪声幂次与两个开关。
vec4 gfx_accretion_disc(vec3 ray_dir, vec3 light_dir, float noise, sampler2D noise_texture, float seconds,
		int steps, float start_offset, int density_power, bool detail_along_longitude, bool doppler){
	return ogxAccretionDisc(ray_dir, light_dir, noise, noise_texture, seconds, steps, start_offset, density_power,
		detail_along_longitude, doppler); // 实现在生成库。
}

#endif
