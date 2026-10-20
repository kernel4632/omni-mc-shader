/*
通用图形库吸积盘模块：沿视线在黑洞附近步进，累加盘的颜色与透过率。
调用位置：任何需要画黑洞吸积盘的程序；本仓库由 `effects/world/end_disc.glsl` 的天空版与反射版调用。
可复制示例：
    vec4 d = gfx_accretion_disc(rayDir, lightDir, noise, noiseTexture, seconds, 50, 3.0, 4, false, true); // rgb 盘颜色、a 透过率。
设计原因与取舍：
    天空版与反射版只差步数、起点、噪声指数与是否叠星空；积分、空间扭曲与盘着色完全共用，所以放进通用库。
    星空仍由效果层叠加，因为那是末地天空的业务；本模块只依赖方向、噪声纹理与时间，不读取任何引擎全局量。
    写法与常数照 iterationT 原程序保留，包括圆环辉光、黑体色温与多普勒调制。
*/
#ifndef GFX_ACCRETION_INCLUDED
#define GFX_ACCRETION_INCLUDED

#include "/gfx/math.glsl"
#include "/gfx/fog.glsl"

// 吸积盘积分：`steps` 是步数，`start_offset` 是起始位置离黑洞的距离，
// `density_power` 是噪声幂次（天空版四、反射版五），`detail_along_longitude` 决定细节是否沿方位角分布，
// `doppler` 打开后按方位角调制亮度。返回 rgb 盘颜色与 a 透过率。
vec4 gfx_accretion_disc(vec3 ray_dir, vec3 light_dir, float noise, sampler2D noise_texture, float seconds,
		int steps, float start_offset, int density_power, bool detail_along_longitude, bool doppler){
	const float step_length = 0.2; // 每步长度。
	const float disc_radius = 2.25; // 吸积盘半径。
	const float disc_width = 3.5; // 吸积盘宽度。
	const float disc_inner = disc_radius - disc_width * 0.5; // 内半径。
	float r_steps = 1.0 / float(steps); // 步数倒数，最后做平均。

	vec3 eye = -light_dir * 8.0; // 视线起点。
	vec3 ray_pos = eye + ray_dir * start_offset; // 起始步进位置。
	mat3 rotation = gfx_rotate_matrix(0.1, 0.0, -0.35); // 吸积盘的固定倾角。

	vec3 result = vec3(0.0); // 累积的盘颜色。
	float transmittance = 1.0; // 透过率。
	ray_pos += ray_dir * step_length * noise; // 起点按噪声抖动，减少步进条纹。

	for (int i = 0; i < steps; i++){ // 逐步前进。
		if (transmittance < 0.0001) break; // 已被遮满就停止。
		gfx_warp_space(ray_dir, ray_pos); // 靠近黑洞时光线被拉弯。
		ray_pos += ray_dir * step_length; // 前进一步。

		vec3 disc_pos = rotation * ray_pos; // 转到吸积盘坐标系。
		float r = length(disc_pos); // 到盘中心的半径。
		float p = atan2(-disc_pos.zx); // 盘面上的方位角。
		float h = disc_pos.y; // 离盘面的高度。

		float radial_gradient = 1.0 - gfx_saturate((r - disc_inner) / disc_width * 0.5); // 径向衰减。
		float dist = abs(h); // 到盘面的距离。
		float disc_thickness = 0.1 * radial_gradient; // 盘的厚度随半径变化。

		float fr = abs(r - disc_inner) + 0.4; // 到内边缘的距离。
		fr = fr * fr; // 平方。
		float fade = fr * fr * 0.04; // 亮度衰减。
		float bloom_factor = 1.0 / (h * h * 40.0 + fade + 0.00002); // 靠近盘面的辉光。
		bloom_factor *= gfx_saturate(2.0 - abs(dist) / disc_thickness); // 只在盘厚范围内。
		bloom_factor = bloom_factor * bloom_factor; // 平方增强。

		float dr = gfx_pcurve(radial_gradient); // 径向轮廓。
		float density = dr; // 当前密度。
		density *= gfx_saturate(1.0 - abs(dist) / disc_thickness); // 按离盘面距离衰减。
		density = gfx_saturate(density * 0.7); // 整体缩放。
		density = gfx_saturate(density + bloom_factor * 0.1); // 叠上辉光。

		if (density > 0.0001){ // 有密度才算这一步的颜色。
			vec3 disc_coord; // 噪声采样坐标。
			vec3 shift; // 噪声随时间流动的方向。
			if (detail_along_longitude){ // 细节沿纬度分布时用方位角。
				disc_coord = vec3(r, p * (1.0 - radial_gradient * 0.5), h * 0.1) * 3.5;
				shift = seconds * vec3(0.1, 0.07, 0.0);
			}else{ // 默认细节只沿半径与高度分布。
				disc_coord = vec3(r, 0.0, h * 0.1) * 3.5;
				shift = seconds * vec3(0.03, 0.05, 0.0);
			}
			float fbm = gfx_cloud_fbm(disc_coord, shift, noise_texture, 64.0); // 高质量云噪声。
			if (density_power == 4){ // 天空版：噪声四次方。
				fbm = fbm * fbm;
				fbm = fbm * fbm;
				density *= fbm * dr;
			}else{ // 反射版：噪声五次方，写法与原程序一致。
				float fbm2 = fbm * fbm;
				density *= fbm2 * fbm2 * fbm;
				density *= dr;
			}

			float gr = 1.0 - radial_gradient; // 反径向。
			gr = gr * gr; // 平方。
			float glow_strength = 1.0 / (gr * gr * 400.0 + 0.002); // 越靠内越亮的辉光。
			vec3 glow = gfx_Blackbody(2700.0 + glow_strength * 50.0) * glow_strength; // 按辉光强度取黑体色。
			if (doppler) glow *= sin(p - 1.07) * 0.75 + 1.0; // 多普勒效应：一侧更亮。

			float step_transmittance = exp2(-density * 7.0); // 这一步的透过率。
			float integral = 1.0 - step_transmittance; // 这一步吸收掉的量。
			transmittance *= step_transmittance; // 累积透过率。
			result += integral * transmittance * glow; // 按透过率累加颜色。
		}

		vec2 t = vec2(1.0, 0.01); // 圆环截面参数。
		float torus_dist = length(length(disc_pos + vec3(0.0, -0.05, 0.0)) - t); // 到圆环的距离。
		float bloom_disc = 1.0 / (pow(torus_dist, 3.5) + 0.001); // 圆环辉光。
		vec3 ring_color = gfx_Blackbody(12000.0); // 高色温的冷白。
		bloom_disc *= step(0.5, r); // 只在盘外缘以外。
		result += ring_color * bloom_disc * 0.1 * transmittance; // 叠上圆环辉光。
	}
	result *= r_steps; // 步数平均。
	return vec4(result, transmittance); // 交回盘颜色与剩余透过率。
}

#endif
