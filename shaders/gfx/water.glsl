/*
通用图形库水面模块：噪声波高、波法线、水面视差、水洼覆盖、雨点动画与水雾。
调用位置：任何需要程序化水面起伏、积水形状、雨点涟漪或水雾的程序；本仓库由 `effects/water/*` 转发调用。
可复制示例：
    float h = gfx_waves(worldPos, noiseTexture, seconds, 0.05); // 采样波高。
    vec3 n = gfx_waves_normal(worldPos, noiseTexture, seconds, 0.05, 1.0, 1.2); // 未归一化法线。
    vec3 p = gfx_water_parallax(worldPos, viewDir, noiseTexture, seconds, 0.05, 1.2); // 视差坐标。
    float c = gfx_puddle_coverage(wetness, noise, 1.0); // 水洼覆盖。
    vec2 r = gfx_rain_animation_normal(rippleTexture, coord, 2.0); // 雨点法线。
    vec3 c = gfx_water_fog(color, viewDir, 20.0, 10.0, normal, ice, glass, hand, 0.0, 1.0, 0.0, lightDir, lightColor, skyColor, upView, 0.2, wetness, 1.2, 1.0, false); // 水雾。
设计原因与取舍：
    噪声纹理、时间、空间缩放、波高、折射率与雾密度全部由调用方传入，库不读取引擎时间或选项。
    波法线故意不做归一化，让调用方能在归一化前叠加玩家涟漪，保持与原程序相同的顺序。
    六层噪声的权重与方向照 iterationT 原程序保留，只把常数换成参数。
*/
#ifndef GFX_WATER_INCLUDED
#define GFX_WATER_INCLUDED

// 雨雾高光复用雾模块的三维噪声。
#include "/gfx/fog.glsl"
// 迁移后的水面实现在生成库里。
#include "/omni-gfx/water.glsl"

// 用三次曲线平滑噪声采样，减少像素块感。
vec4 gfx_texture_smooth(sampler2D noise_texture, vec2 coord){
	return ogxTextureSmooth(noise_texture, coord); // 实现在生成库。
}

// 把零到一的值压成两端平、中间过渡的形状，让波峰更饱满。
float gfx_almost_identity(float x, float m, float n){
	return ogxAlmostIdentity(x, m, n); // 实现在生成库。
}

// 六层噪声叠加的波高，返回归一化高度。
float gfx_waves(vec3 position, sampler2D noise_texture, float time, float wave_scale){
	return ogxWaves(position, noise_texture, time, wave_scale); // 实现在生成库。
}

// 用中央差分求波法线，返回未归一化的向量，方便调用方先叠涟漪再归一化。
vec3 gfx_waves_normal(vec3 position, sampler2D noise_texture, float time, float wave_scale, float wave_height, float height_scale){
	return ogxWavesNormal(position, noise_texture, time, wave_scale, wave_height, height_scale); // 实现在生成库。
}

// 沿视线在波高场里前进，找到真正可见的波面位置。
vec3 gfx_water_parallax(vec3 position, vec3 view_vector, sampler2D noise_texture, float time, float wave_scale, float height_scale){
	return ogxWaterParallax(position, view_vector, noise_texture, time, wave_scale, height_scale); // 实现在生成库。
}

// 水面折射坐标：把水面波法线或玻璃折射方向换成一次屏幕采样坐标。
// 为什么水面与玻璃分开：水面用平水面与波面的法线差近似偏移，玻璃用整段折射方向投影，公式不同。
// 参数里的 `model_view` 与 `projection` 由调用方传入，库不假设任何相机约定；`wave_normal` 只在水面时使用。
vec2 gfx_water_refraction_coord(bool is_water, vec3 normal, vec3 view_pos, vec3 wave_normal,
		mat3 model_view, mat4 projection, float water_deep, float water_dist, vec2 screen_input){
	return ogxWaterRefractionCoord(is_water, normal, view_pos, wave_normal, model_view, projection, water_deep, water_dist, screen_input); // 实现在生成库。
}

// 水洼覆盖：湿润度高于低洼噪声处的面积才积水，尺寸参数放大水洼范围。
float gfx_puddle_coverage(float half_wet, float noise, float size){
	return ogxPuddleCoverage(half_wet, noise, size); // 实现在生成库。
}

// 湿面反射锐度：把干表面粗糙度往湿表面粗糙度混合，锐度为零时原样返回。
float gfx_puddle_roughness(float roughness, float wet_roughness, float wetness_stages, float sharpness){
	return ogxPuddleRoughness(roughness, wet_roughness, wetness_stages, sharpness); // 实现在生成库。
}

// 雨雾高光调制：三层三维噪声叠加后归一，让雨中的高光随时间轻微变化。
float gfx_rain_specular(vec3 pos, sampler2D noise_texture){
	return ogxRainSpecular(pos, noise_texture); // 实现在生成库。
}

// 读一张雨点动画贴图并转成带符号的法线，指数控制边缘锐度。
vec2 gfx_rain_animation_normal(sampler2D rainTexture, vec2 coord, float exponent){
	vec2 n = textureLod(rainTexture, coord, 0.0).rg; // 读红绿两通道。
	n = n * vec2(2.0, -2.0) + vec2(-1.0, 1.0); // 零到一转成负一到一，并翻转纵轴。
	n = pow(abs(n), vec2(exponent)) * sign(n); // 按指数压形状，符号保留。
	return n; // 返回法线横纵分量。
}

// 水下与水后雾：按距离做分波段衰减并向雾色靠拢，返回混合后的颜色。
// 为什么水下与水面之上要分开：雾色、散射方向与基础密度都不同，原程序用 `isEyeInWater` 一次分派。
// 参数说明：`opaque_dist` 是不透明面到相机的距离，`water_dist` 是水面到相机的距离，
// `ice`、`stained_glass`、`hand` 是材质掩码，`water_skylight` 是该处水面接收的天光，
// `up_view` 是视空间的竖直轴，`eye_water_depth` 由天空光反推，`refract_ior` 是水面折射率。
vec3 gfx_water_fog(vec3 color, vec3 view_dir, float opaque_dist, float water_dist, vec3 normal,
		float ice, float stained_glass, float hand, float occluded_water, float water_skylight, float total_internal,
		vec3 light_dir, vec3 light_color, vec3 sky_color, vec3 up_view, float eye_water_depth, float wetness,
		float refract_ior, float fog_density_option, bool underwater){
	return ogxWaterFog(color, view_dir, opaque_dist, water_dist, normal, ice, stained_glass, hand, occluded_water,
		water_skylight, total_internal, light_dir, light_color, sky_color, up_view, eye_water_depth, wetness,
		refract_ior, fog_density_option, underwater); // 实现在生成库。
}

// 波法线方块读取：把世界位置按折射方向投到七号画面左下角的波法线方块，解出世界空间法线。
// 为什么先按折射方向移动坐标：光线进入水面会弯折，直接用世界横纵坐标会读到错误的波法线。
vec3 gfx_waves_normal_from_tex(vec3 position, vec3 light_dir, sampler2D normal_texture, vec2 pixel_size,
		vec2 screen_size, float max_resolution, float refract_ior){
	vec3 refracted = refract(light_dir, vec3(0.0, 1.0, 0.0), 1.0 / refract_ior); // 阳光按水面折射率弯折。
	vec2 coord = position.xz; // 先取水平坐标。
	coord.x += position.y * refracted.x / refracted.y; // 按高度沿光线横移横坐标。
	coord.y += position.y * refracted.z / refracted.y; // 按高度沿光线横移纵坐标。
	coord *= 0.02; // 缩到波法线图的空间尺度。
	coord = fract(coord); // 平铺到零到一。
	coord *= pixel_size * min(screen_size.y, max_resolution); // 折算成方块里的像素坐标。
	return gfx_DecodeNormal(textureLod(normal_texture, coord, 0.0).xy); // 从方块里读八面体编码法线。
}

// 水体焦散：按折射后的阳光在波面上找汇聚点，得到明暗花纹。
// 为什么用九次采样：三乘三抖动采样已经能把焦散花纹的噪点压到可接受，再多收益不明显。
// `camera_position` 用来还原绝对世界坐标，`underwater` 决定是否往全亮靠。
float gfx_water_caustics(vec3 world_pos, vec3 light_dir, vec3 camera_position, sampler2D normal_texture,
		vec2 pixel_size, vec2 screen_size, float max_resolution, float refract_ior, vec2 dither,
		bool underwater, float brightness, float power){
	vec3 position = world_pos + camera_position; // 换成绝对世界坐标。
	vec3 lookup_center = position + vec3(0.0, 1.0, 0.0); // 从水面上方一米处开始找波面。
	vec3 refracted = refract(light_dir, vec3(0.0, -1.0, 0.0), 1.0 / 1.2); // 阳光向下穿过水面时弯折；原程序固定用一点二。
	float caustics = 0.0; // 累计焦散强度。

	for (float i = -1.0; i <= 1.0; i++){ // 三乘三抖动采样。
		for (float j = -1.0; j <= 1.0; j++){
			vec2 offset = dither + vec2(i, j); // 当前采样偏移。
			vec3 lookup_point = lookup_center; // 这一处的波面查询点。
			lookup_point.xz += offset * 0.1; // 按偏移横移。
			vec3 waves_normal = gfx_waves_normal_from_tex(lookup_point, light_dir, normal_texture, pixel_size,
				screen_size, max_resolution, refract_ior).xzy; // 读取波法线并换到竖直轴朝上的坐标。
			vec3 refract_vector = refract(vec3(0.0, 1.0, 0.0), waves_normal.xyz, 1.0); // 竖直光线被波面折射后的方向。
			vec3 collision = lookup_point - refract_vector / refract_vector.y; // 光线与水平面的交点。
			collision -= position; // 相对当前位置。
			float dist = dot(collision, collision) * 7.1; // 交点距离的平方，放大差距。
			caustics += 1.0 - gfx_saturate(dist * 7.0); // 交点越近越亮，模拟光线汇聚。
		}
	}

	float final_caustics = mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(underwater)); // 拼成焦散亮度，水下再往全亮靠一点。
	return pow(final_caustics * brightness, power); // 按亮度倍率与对比指数重整。
}

#endif
