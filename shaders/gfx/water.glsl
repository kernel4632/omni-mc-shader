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

// 用三次曲线平滑噪声采样，减少像素块感。
vec4 gfx_texture_smooth(sampler2D noiseTexture, vec2 coord){
	coord *= 64.0; // 噪声纹理边长六十四，先换成像素坐标。
	coord += 0.5; // 移到像素中心。
	vec2 whole = floor(coord); // 整数像素。
	vec2 part = coord - whole; // 小数部分。
	coord = whole + part * part * (3.0 - 2.0 * part); // 三次曲线改写小数部分。
	coord -= 0.5; // 移回像素角。
	coord *= 0.015625; // 除以六十四，换回零到一坐标。
	return textureLod(noiseTexture, coord, 0.0); // 读取平滑后的噪声四通道。
}

// 把零到一的值压成两端平、中间过渡的形状，让波峰更饱满。
float gfx_almost_identity(float x, float m, float n){
	x = abs(x * 2.0 - 1.0); // 折回零到一并取绝对值。
	if (x <= m){ // 只在靠近中间的一段改写。
		float a = 2.0 * n - m; // 三次项系数。
		float b = 2.0 * m - 3.0 * n; // 二次项系数。
		float t = x / m; // 归一化到零到一。
		x = (a * t + b) * t * t + n; // 三次多项式重排形状。
	}
	return 1.0 - x; // 翻转方向。
}

// 六层噪声叠加的波高，返回归一化高度。
float gfx_waves(vec3 position, sampler2D noiseTexture, float time, float waveScale){
	float wavesTime = time * 0.0035; // 波浪时间，比真实秒慢很多。
	position *= waveScale; // 按波浪密度缩放空间坐标。
	vec2 p = position.xz - position.y; // 用水平坐标，减去高度让波浪随高度起伏。
	p += -3.875 * wavesTime; // 整片波沿一个方向平移。
	p.x = -p.x; // 翻转一个轴，打散规则方向。
	vec2 waves = vec2(0.0); // 前两个分量存累加高度和累加权重。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(2.0, 1.2) + vec2(0.0, p.x * 2.1)).w, 1.0); // 第一层低频大波。
	p = p * 0.475; // 收缩坐标，频率升高。
	p += vec2(-5.16, -7.75) * wavesTime; // 每层自己的行进方向与速度。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(2.0, 1.4) + vec2(0.0, -p.x * 2.1)).w * 4.0, 4.0); // 第二层。
	p *= 0.67; // 继续抬高频率。
	p.x += 7.75 * wavesTime; // 换一个方向。
	waves += vec2(gfx_texture_smooth(noiseTexture, p + vec2(0.0, p.x * 1.1)).z * 8.0, 8.0); // 第三层。
	p *= 0.7; // 再抬高频率。
	p.x += -2.82 * wavesTime; // 换方向。
	waves += vec2(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.75) + vec2(0.0, -p.x * 1.7)).w * 16.0, 16.0); // 第四层。
	p *= 0.45; // 高频细节。
	p.x += wavesTime; // 换方向。
	waves += vec2(gfx_almost_identity(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, -p.x * 1.7)).z, 0.2, 0.1) * 30.0, 30.0); // 第五层。
	p *= 0.5; // 最高频一层。
	p.x += wavesTime; // 换方向。
	waves += vec2(gfx_almost_identity(gfx_texture_smooth(noiseTexture, p * vec2(1.0, 0.8) + vec2(0.0, p.x * 1.7)).w, 0.2, 0.1) * 20.0, 20.0); // 第六层。
	return waves.x / waves.y; // 高度除以权重和，归一化。
}

// 用中央差分求波法线，返回未归一化的向量，方便调用方先叠涟漪再归一化。
vec3 gfx_waves_normal(vec3 position, sampler2D noiseTexture, float time, float waveScale, float waveHeight, float heightScale){
	const float sampleDistance = 12.0; // 法线差分采样距离。
	position.xz -= 0.005 * sampleDistance; // 采样点整体后移一点，让差分落在波面中心。
	float center = gfx_waves(position, noiseTexture, time, waveScale); // 中心高度。
	float left = gfx_waves(position + vec3(0.01 * sampleDistance, 0.0, 0.0), noiseTexture, time, waveScale); // 横向偏移。
	float up = gfx_waves(position + vec3(0.0, 0.0, 0.01 * sampleDistance), noiseTexture, time, waveScale); // 纵向偏移。
	vec3 normal = vec3(center - left, center - up, 1.0); // 两个方向的高度差构成法线。
	normal.xy *= waveHeight * (heightScale / sampleDistance); // 按波高与采样距离缩放坡度。
	return normal;
}

// 沿视线在波高场里前进，找到真正可见的波面位置。
vec3 gfx_water_parallax(vec3 position, vec3 viewVector, sampler2D noiseTexture, float time, float waveScale, float heightScale){
	vec3 stepSize = vec3(heightScale * 0.8, heightScale * 0.8, 0.6); // 每步大小，横向按波高缩放。
	float waveHeight = gfx_waves(position, noiseTexture, time, waveScale); // 起点波高。
	vec3 pCoord = vec3(0.0, 0.0, 1.0); // 以表面为参考，向前推进的深度。
	vec3 steps = viewVector * stepSize; // 每步的位移。
	float sampleHeight = waveHeight; // 当前位置的波高。
	for (int i = 0; sampleHeight < pCoord.z && i < 12; ++i){ // 最多十二步。
		pCoord.xy += steps.xy * clamp((pCoord.z - sampleHeight) * (-viewVector.z + 0.05) / (stepSize.z * 0.2), 0.0, 1.0); // 按深度差决定步长。
		pCoord.z += steps.z; // 视线深度前进。
		sampleHeight = gfx_waves(position + vec3(pCoord.x, 0.0, pCoord.y), noiseTexture, time, waveScale); // 读取新位置波高。
	}
	return position + vec3(pCoord.x, 0.0, pCoord.y); // 返回偏移后的采样坐标。
}

// 水洼覆盖：湿润度高于低洼噪声处的面积才积水，尺寸参数放大水洼范围。
float gfx_puddle_coverage(float halfWet, float noise, float size){
	float puddles = max(halfWet - noise, 0.0); // 只有湿润高于噪声阈值的低洼处才开始积水。
	puddles = clamp(halfWet - exp(-25.0 * puddles * puddles * puddles * puddles * puddles * size), 0.0, 1.0); // 指数衰减给出覆盖率，尺寸越大衰减越慢。
	return puddles; // 返回零到一的积水覆盖。
}

// 湿面反射锐度：把干表面粗糙度往湿表面粗糙度混合，锐度为零时原样返回。
float gfx_puddle_roughness(float roughness, float wetRoughness, float wetnessStages, float sharpness){
	return mix(roughness, wetRoughness, wetnessStages * sharpness); // 湿润阶段乘锐度作为混合比例。
}

// 雨雾高光调制：三层三维噪声叠加后归一，让雨中的高光随时间轻微变化。
float gfx_rain_specular(vec3 pos, sampler2D noiseTexture){
	pos.y *= 0.2; // 压缩竖直方向，雨高光在竖直上变化更慢。
	float n = gfx_fog_noise(pos, noiseTexture); // 第一层。
	n += gfx_fog_noise(pos * 0.5, noiseTexture) * 2.0; // 第二层，缩小坐标并放大权重。
	n += gfx_fog_noise(pos * 0.25, noiseTexture) * 4.0; // 第三层，更细更高权重。
	n /= 7.0; // 归一化到大致零到一。
	return clamp(n, 0.0, 1.0) * 0.7 + 0.3; // 夹紧后留一个下限，避免完全无高光。
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
	float dist_diff = opaque_dist - water_dist; // 水面到水底的真实厚度。
	water_dist = underwater ? // 在水下且隔着玻璃时改用不透明距离。
			mix(water_dist, opaque_dist, stained_glass) :
			mix(dist_diff, min(dist_diff * 0.3, 6.0), occluded_water); // 隔着玻璃时厚度打折并封顶，避免过浓。
	water_dist = max(water_dist, total_internal * eye_water_depth * 50.0); // 全反射时把雾距离拉长，形成亮环。

	vec3 shadow_refracted = refract(-light_dir, up_view, 1.0 / refract_ior); // 阳光在水面折射后的方向。

	vec3 fog_color = mix(vec3(0.05, 0.6, 1.0), vec3(0.3, 0.9, 1.5), ice); // 冰面偏亮青，普通水偏青。
	fog_color = mix(fog_color, vec3(0.5), wetness * 0.6); // 越湿雾色越中性。
	fog_color *= dot(vec3(0.33333), sky_color); // 乘天光色，雾色随环境变化。

	if (!underwater){ // 水面之上看水下。
		fog_color *= 0.04 - wetness * 0.032; // 水面之上的雾很淡，雨天更淡。
		fog_color *= water_skylight; // 再乘该处水面接收的天光。

		vec3 l = normalize(reflect(view_dir, normal)); // 视线在水面的反射方向。
		vec3 h = normalize(l - view_dir); // 反射方向与视线的半程。
		float fresnel = gfx_saturate(dot(normal, l)) * gfx_saturate(dot(l, h) * 1.5 - 0.5); // 一个简化的菲涅耳权重。
		float scatter = 3.0 * fresnel * pow(dot(shadow_refracted, view_dir) * 5.0 + 5.2, -1.4); // 逆光时的散射更强。
		fog_color = mix(fog_color, light_color * fog_color * 3.0, scatter * gfx_saturate(1.0 - wetness - occluded_water)); // 逆光散射叠上去，湿地或隔玻璃时减弱。
	}else{ // 整只眼睛在水里。
		fog_color *= 0.02 - wetness * 0.012; // 水下雾更淡。
		float scatter = 1.0 / (dot(shadow_refracted, view_dir) * 5.0 + 5.1); // 朝向阳光的散射。
		vec3 sun_scatter = light_color * scatter * fog_color * 2.0; // 阳光在水里的散射色。

		fog_color *= dot(view_dir, up_view) * 0.4 + 0.6; // 朝上看更亮。
		fog_color += sun_scatter * (eye_water_depth * (1.0 - wetness * 0.6)); // 叠加阳光散射。
	}

	float density = underwater ? ice * 0.96 + 0.04 : 0.29; // 基础雾密度，冰下更浓。
	float visibility = exp2(-water_dist * density * fog_density_option); // 按密度指数衰减得到可见度。
	visibility = clamp(visibility, 0.35 * ice, 1.0); // 冰下留一个最低可见度。
	visibility = mix(visibility, 0.7, hand); // 手持物只受七成雾影响，避免手被糊掉。

	vec3 attenuation = underwater ? vec3(0.1, 0.6, 1.0) : vec3(0.2, 0.5, 0.7); // 分波段衰减色，水下偏蓝。
	color *= pow(attenuation * 0.99, vec3(water_dist * (0.21 * float(!underwater) + 0.04) * fog_density_option)); // 红衰减最快，蓝最慢。
	return mix(fog_color, color, visibility); // 用可见度在雾色与场景色之间混合。
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
