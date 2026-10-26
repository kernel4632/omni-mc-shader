/*
大气模块适配层：球面几何、密度剖面、星场、日月圆盘、天空盒投影、极光彩虹与行星表面已迁到生成库。
调用位置：`rendering/sky/*`、`rendering/world/*` 与大气查表适配层引用本文件；
    效果层只保留时间、天气与选项换算，算式只在 `omni-gfx/src/atmosphere.slang` 一份。
可复制示例：`float d = gfx_distance_to_top(radius, mu, topRadius);` 到层顶的距离，实现在生成库。
设计原因与取舍：函数名、参数顺序与输出参数保持原样，几十个调用点无需改动，默认画面不会漂移；
    半径、贴图尺寸、星点密度与颜色开关全部由调用方传入，库不读取任何宿主常量。
*/
#ifndef GFX_ATMOSPHERE_INCLUDED
#define GFX_ATMOSPHERE_INCLUDED

// 通用数学与迁移后的大气实现。
#include "/gfx/math.glsl"
#include "/omni-gfx/atmosphere.glsl"

// 把半径夹进大气层范围内。
float gfx_clamp_radius(float r, float bottomRadius, float topRadius){ return ogxClampRadius(r, bottomRadius, topRadius); } // 实现在生成库。

// 安全开方：负零以下一律当零，避免浮点误差出非数。
float gfx_safe_sqrt(float a){ return ogxSafeSqrt(a); } // 实现在生成库。

// 视线到大气层顶的距离，解球面方程取远根。
float gfx_distance_to_top(float r, float mu, float top_radius){ return ogxSphereDistanceToTop(r, mu, top_radius); } // 实现在生成库。

// 视线到大气层底的距离，解球面方程取近根。
float gfx_distance_to_bottom(float r, float mu, float bottom_radius){ return ogxSphereDistanceToBottom(r, mu, bottom_radius); } // 实现在生成库。

// 判断一条朝下的视线是否真的打到地面球。
bool gfx_ray_intersects_ground(float r, float mu, float bottom_radius){ return ogxSphereRayIntersectsGround(r, mu, bottom_radius); } // 实现在生成库。

// 瑞利与米氏密度剖面：以二为底的指数衰减。
float gfx_density_rayleigh_mie(float exp_scale, float altitude){ return ogxExponentialDensity(exp_scale, altitude); } // 实现在生成库。

// 臭氧密度剖面：转折高度以下一段斜线，以上另一段斜线。
float gfx_density_absorption(float width, vec4 profile, float altitude){ return ogxAbsorptionDensity(width, profile, altitude); } // 实现在生成库。

// 把零到一的比例映射到贴图像素中心，避免采到子图交界。
float gfx_texture_coord(float x, float texture_size){ return ogxTexelCenterCoord(x, texture_size); } // 实现在生成库。

// 把子图内部比例映射到拼合大图坐标，子图在大图里也内缩半像素。
float gfx_combined_texture_coord(float x, float original_size, float combined_size){ return ogxSubTextureCoord(x, original_size, combined_size); } // 实现在生成库。

// 星场散列：把一个方向格打散成零到一的随机数。
float gfx_star_hash13(vec3 p3){ return ogxStarHash13(p3); } // 实现在生成库。

// 噪声星场：把散列值低于阈值的格子压成零，剩下的当作星点原始亮度。
float gfx_star_noisy_field(vec3 samplePos, float threshold){ return ogxStarNoisyField(samplePos, threshold); } // 实现在生成库。

// 稳定星场：只在整数格上取值，再用双线性插值平滑，避免相机移动时星点闪烁。
float gfx_star_stable_field(vec3 samplePos, float threshold){ return ogxStarStableField(samplePos, threshold); } // 实现在生成库。

// 彩色星场散列：只用二维坐标，正弦放大再取小数。
float gfx_star_hash12(vec2 co){ return ogxStarHash12(co); } // 实现在生成库。

// 星温：把零到一的散列映射成色温。
float gfx_star_temperature(float hash){ return ogxStarTemperature(hash); } // 实现在生成库。

// 星面：把方向投到立方体的一面按格撒星，输出该方向的亮度与颜色。
float gfx_star_plane(vec3 dir, out vec3 starColor){ return ogxStarPlane(dir, starColor); } // 实现在生成库。

// 星盒：把方向分别当立方体三轴投影，叠出完整六面星场。
float gfx_star_box(vec3 dir, out vec3 starColor){ return ogxStarBox(dir, starColor); } // 实现在生成库。

// 白色稳定星场：返回星场亮度；星色固定为白，由调用方直接使用。
float gfx_stars_stable(vec3 viewPos, float brightness, float amount){ return ogxStarsStable(viewPos, brightness, amount); } // 实现在生成库。

// 彩色星盒星场：返回亮度并由 `starColor` 回填星色。
float gfx_stars_colored(vec3 viewPos, float brightness, float amount, out vec3 starColor){ return ogxStarsColored(viewPos, brightness, amount, starColor); } // 实现在生成库。

// 把视线方向绕太阳轴旋转对齐天球。
vec3 gfx_align_to_sun_axis(vec3 worldDir, vec3 sunVector){ return ogxAlignToSunAxis(worldDir, sunVector); } // 实现在生成库。

// 太阳圆盘遮罩：返回零到一的亮度，太阳颜色与辐照倍率由调用方乘上。
float gfx_sun_disc(vec3 world_dir, vec3 sun_dir){ return ogxSunDisc(world_dir, sun_dir, 5e-5, 4e4); } // 角半径与硬度是太阳的固定值，实现在生成库。

// 真实月亮圆盘：角半径由尺寸档位换算，档位越大圆盘越大。
float gfx_moon_disc_real(vec3 world_dir, vec3 moon_dir, float size_setting){ return ogxMoonDiscReal(world_dir, moon_dir, size_setting); } // 实现在生成库。

// 默认月亮圆盘：比太阳更硬、更小的圆盘。
float gfx_moon_disc_default(vec3 world_dir, vec3 moon_dir){ return ogxMoonDiscDefault(world_dir, moon_dir); } // 实现在生成库。

// 反射里的月亮圆盘：反射天空盒分辨率低，用更大的角半径换取可见。
float gfx_moon_disc_reflection(vec3 world_dir, vec3 moon_dir){ return ogxMoonDiscReflection(world_dir, moon_dir); } // 实现在生成库。

// 月亮轨道：由游戏时间、纬度与轨道倾角闭式算出月亮的世界方向。
vec3 gfx_moon_direction(float time, float latitude, float path_rotation, float month_length){ return ogxMoonDirection(time, latitude, path_rotation, month_length); } // 实现在生成库。

// 把天空盒三维贴图上的一个纹素坐标反解成世界方向。
vec3 gfx_sky_unproject(vec2 texel, float tileSize){ return ogxSkyUnproject(texel, tileSize); } // 实现在生成库。

// 把一个世界方向投到天空盒三维贴图上。
vec2 gfx_sky_project(vec3 dir, float tileSize){ return ogxSkyProject(dir, tileSize); } // 实现在生成库。

// 极光：夜晚高空的缓慢帘幕，雨天被云遮挡。
vec3 gfx_aurora(vec3 color, vec3 direction, vec3 sunDirection, float time, float wetness, float tint, float strength){ return ogxAurora(color, direction, sunDirection, time, wetness, tint, strength); } // 实现在生成库。

// 彩虹：雨后晴天的背太阳方向，出现一条窄彩色弧。
vec3 gfx_rainbow(vec3 color, vec3 direction, vec3 sunDirection, float wetness, float strength){ return ogxRainbow(color, direction, sunDirection, wetness, strength); } // 实现在生成库。

// 钱德拉塞卡近似：各项同性散射的倍增因子。
vec3 gfx_chandrasekhar_h(vec3 albedo, float a){ return ogxChandrasekharH(albedo, a); } // 实现在生成库。

// 行星表面双向反射：入射与出射两侧各算一次钱德拉塞卡近似。
vec3 gfx_planet_brdf(vec3 albedo, vec3 normal, vec3 eyeDir, vec3 lightDir){ return ogxPlanetBrdf(albedo, normal, eyeDir, lightDir); } // 实现在生成库。

// 圆盘剖面：由阈值与斜率构成边缘平滑的圆盘，平方后边界更清楚。
float gfx_disc_profile(float a, float s, float h){ return ogxDiscProfile(a, s, h); } // 实现在生成库。

// 行星环带噪声：五层噪声叠出环带细缝。
float gfx_planet_ring_noise(float position, sampler2D noiseTexture){ return ogxPlanetRingNoise(position, noiseTexture); } // 实现在生成库。

// Eclipse 球面与经纬贴图坐标：参考直接使用 TAU/PI 与 rTAU。
vec3 cartToSphere(vec2 coord){
	coord.y = 1.0 - coord.y;
	coord *= vec2(TAU, PI); // 经度乘 TAU、纬度乘 PI，把零到一映射到整圈。
	vec2 lon = vec2(sin(coord.x), cos(coord.x)) * sin(coord.y);
	return vec3(lon.x, cos(coord.y), lon.y);
}
vec2 sphereToCart(vec3 dir){
	float lonlat = atan(-dir.x, -dir.z);
	return vec2(lonlat * 0.159155 + 0.5, 0.5 * dir.y + 0.5); // 参考的 rTAU 取 0.159155。
}

#endif
