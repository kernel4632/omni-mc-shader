/*
通用图形库反射模块：可见法线采样、屏幕空间追踪、反射主流程、菲涅耳合并与小波滤波。
调用位置：任何需要反射的程序；本仓库由 `effects/reflection/screenspace.glsl` 与 `effects/reflection/denoise.glsl` 转发调用。
可复制示例：
    vec3 d = gfx_sample_ggx_vndf(viewVector, roughness, noise); // 生成一条模糊反射方向。
    vec4 r = gfx_specular_reflections(surface, trace, media, noise, depth1, depth2, dhDepth, scene); // 追踪并着色。
    gfx_reflection_atrous_filter(data, viewPos, viewDir, normal, roughness, 40.0, noise, texCoord, reflectTex, depthTex, normalTex, pixelSize, projectionInverse); // 九点滤波。
设计原因与取舍：
    主流程不读取 Minecraft uniform：深度图、投影、光色与天空都由参数传入；
    天空兜底、体素回退、命中深度与反射雾这些宿主细节用 `GFX_REFLECTION_*` 钩子注入，默认是中性操作。
    公式照原程序保留，只把圆周常数换成库内常数；三个维度共用一条流程，差异写成 `gfx_reflection_media` 的开关。
*/

#ifndef GFX_REFLECTION_INCLUDED
#define GFX_REFLECTION_INCLUDED

#include "/gfx/math.glsl"

#define GFX_TAU 6.28318530718 // 一个完整圆周。

// 可见法线分布采样：按粗糙度把反射方向散开，得到模糊反射。
vec3 gfx_sample_ggx_vndf(vec3 viewVector, float roughness, vec2 noise){
	vec3 orthoNormal = normalize(vec3(roughness * viewVector.xy, viewVector.z)); // 把视线按粗糙度压成一个辅助轴。
	float length2 = dot(orthoNormal.xy, orthoNormal.xy); // 水平分量的长度平方。
	vec3 orthoTangent = length2 > 0.0 ? vec3(-orthoNormal.y, orthoNormal.x, 0.0) * inversesqrt(length2) : vec3(1.0, 0.0, 0.0); // 水平切线。
	vec3 orthoBitangent = cross(orthoNormal, orthoTangent); // 副切线。
	float radius = sqrt(noise.y * 0.7); // 采样半径，取平方根让样本落在圆内。
	float angle = GFX_TAU * noise.x; // 采样角度。
	vec2 samplePos = vec2(cos(angle), sin(angle)) * radius; // 圆上的采样位置。
	float scaling = orthoNormal.z * 0.5 + 0.5; // 沿竖直方向把圆压成椭圆。
	samplePos.y = (1.0 - scaling) * sqrt(1.0 - samplePos.x * samplePos.x) + scaling * samplePos.y; // 投影到椭圆上。
	vec3 sampleVector = samplePos.x * orthoTangent + samplePos.y * orthoBitangent + sqrt(max(0.0, 1.0 - dot(samplePos, samplePos))) * orthoNormal; // 合成三维方向。
	return normalize(vec3(roughness * sampleVector.xy, max(sampleVector.z, 0.0))); // 按粗糙度压扁并归一化。
}

// 屏幕坐标与深度还原视空间位置；屏幕空间追踪算射线起点与命中点时用。
vec3 gfx_reflection_view_pos(vec2 coord, float depth, mat4 projection_inverse){
	vec3 ndc = vec3(coord, depth) * 2.0 - 1.0; // 零到一转负一到一。
	vec3 pos = vec3(vec2(projection_inverse[0][0], projection_inverse[1][1]) * ndc.xy, 0.0) + projection_inverse[3].xyz; // 只用逆投影的非零项。
	return pos / (projection_inverse[2][3] * ndc.z + projection_inverse[3][3]); // 透视除法。
}

// 视空间位置投到屏幕，不补抖动；追踪射线用原始投影。
vec3 gfx_reflection_screen_pos(vec3 view_pos, mat4 projection){
	vec3 pos = vec3(projection[0][0], projection[1][1], projection[2][2]) * view_pos + projection[3].xyz; // 投影矩阵的非零项。
	return pos * (0.5 / -view_pos.z) + 0.5; // 透视除法并转到零到一。
}

// 屏幕深度换米制距离。
float gfx_reflection_linear_depth(float depth, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 零到一转负一到一。
	return 1.0 / (depth * projection_inverse[2][3] + projection_inverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回屏幕深度。
float gfx_reflection_screen_depth(float depth, mat4 projection_inverse){
	depth = (1.0 / depth - projection_inverse[3][3]) / projection_inverse[2][3]; // 解出负一到一深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// 远景深度换成同一距离在近景投影下的深度。
float gfx_reflection_dh_to_screen_depth(float depth, mat4 dh_projection_inverse, mat4 projection_inverse){
	depth = depth * 2.0 - 1.0; // 远景深度转到负一到一。
	depth = 1.0 / (depth * dh_projection_inverse[2][3] + dh_projection_inverse[3][3]); // 先换成米。
	depth = (1.0 / depth - projection_inverse[3][3]) / projection_inverse[2][3]; // 再用近景投影换回深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// 读追踪采样点的深度：手部优先手部图，近景是天空时按开关改读远景。
float gfx_reflection_sample_depth(vec2 coord, bool is_hand, bool hand_supported, sampler2D depth_texture, sampler2D hand_depth_texture,
		sampler2D dh_depth_texture, bool has_dh, bool dh_ssr, mat4 dh_projection_inverse, mat4 projection_inverse){
	if (hand_supported && is_hand) return textureLod(hand_depth_texture, coord, 0.0).x; // 手部读不含玩家的深度。
	float depth = textureLod(depth_texture, coord, 0.0).x; // 其他像素读普通不透明深度。
	if (has_dh && dh_ssr && depth == 1.0) depth = gfx_reflection_dh_to_screen_depth(textureLod(dh_depth_texture, coord, 0.0).x, dh_projection_inverse, projection_inverse); // 远景深度换到近景尺度。
	return depth; // 返回该坐标的深度。
}

// 屏幕空间追踪：从起点沿反射方向在屏幕里步进，撞到比射线更近的几何就命中。
// 命中后二分细化，避免粗步长跨过薄几何；屏幕外的方向没有可靠深度，直接停止。
bool gfx_screen_space_trace(vec3 view_ray_ori, vec3 view_ray_dir, float ndotv, float noise, float min_length, bool is_hand, inout vec3 screen_pos,
		sampler2D depth_texture, sampler2D hand_depth_texture, sampler2D dh_depth_texture, mat4 projection, mat4 projection_inverse,
		mat4 dh_projection_inverse, float near_plane, bool hand_supported, bool has_dh, bool dh_ssr, int quality, int refinement_steps, float z_diff_threshold){
	float r_steps = 1.0 / float(quality); // 步数的倒数，用作归一化步长。
	float view_ray_length = (-near_plane - view_ray_ori.z) / view_ray_dir.z + step(view_ray_dir.z, 0.0) * 1e20; // 射线到近裁剪面的长度，背向时给极远值。
	vec3 ray_dir = normalize(gfx_reflection_screen_pos(view_ray_ori + view_ray_dir * view_ray_length, projection) - screen_pos); // 屏幕坐标下的射线方向。
	float min_step_length = min_length * r_steps; // 最小步长按质量缩放。
	float step_length = mix(min_step_length, r_steps, ndotv); // 正对视线时步长更大，掠射时更小。
	float z_scaling = abs(1.0 / ray_dir.z); // 深度方向的缩放。
	bool hit = false; // 命中标记。
	float max_depth = has_dh ? gfx_reflection_screen_depth(gfx_reflection_linear_depth(1.0, dh_projection_inverse), projection_inverse) : 1.0; // 有远景时步进上限是远景最远距离。
	screen_pos += ray_dir * step_length * noise; // 起点按噪声抖动，减少规则条纹。
	float depth = gfx_reflection_sample_depth(screen_pos.xy, false, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 读起始点深度。
	for (int i = 0; i < quality + 3; i++){ // 最多走质量加三次，多出的几次用于边界收尾。
		if (gfx_saturate(screen_pos.xy) != screen_pos.xy) break; // 出了屏幕就停止。
		if (screen_pos.z >= max_depth){ // 射线到达最远处。
			hit = depth >= max_depth; // 该处也是尽头才算命中。
			break;
		}else if (screen_pos.z < 0.7 && !is_hand){ // 射线跑到相机很近的地方，后面没有可靠深度。
			break;
		}
		if (depth < screen_pos.z){ // 几何深度比射线更近，说明可能撞上几何。
			vec3 refine_dir = ray_dir * step_length * 0.5; // 细化步长，从半步开始逐次减半。
			for (int j = 0; j < refinement_steps; j++, refine_dir *= 0.5){ // 二分细化交点。
				screen_pos += refine_dir * (step(screen_pos.z, depth) * 2.0 - 1.0); // 越过就回退半步，没越过就前进半步。
				depth = gfx_reflection_sample_depth(screen_pos.xy, is_hand, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 重读该点深度。
			}
			if (depth > screen_pos.z) continue; // 细化后几何又跑到后面，这一步不算命中。
			float step_dist = gfx_reflection_linear_depth(screen_pos.z, projection_inverse); // 射线点的米制距离。
			float sample_dist = gfx_reflection_linear_depth(depth, projection_inverse); // 几何点的米制距离。
			float dist_diff = abs(sample_dist - step_dist) / step_dist; // 两点的相对深度差。
			if (dist_diff < z_diff_threshold && screen_pos.z > 0.0 && screen_pos.z < max_depth){ // 差足够小且深度有效才算命中。
				hit = true;
				break;
			}
		}
		step_length = clamp(abs(depth - screen_pos.z) * z_scaling, min_step_length, r_steps); // 按深度差自适应下一步长度。
		screen_pos += ray_dir * step_length; // 前进一步。
		depth = gfx_reflection_sample_depth(screen_pos.xy, false, hand_supported, depth_texture, hand_depth_texture, dh_depth_texture, has_dh, dh_ssr, dh_projection_inverse, projection_inverse); // 读新位置的深度。
	}
	return hit; // 返回是否命中。
}

// --- 反射主流程：追踪、天空与体素回退、反射雾 ---
// 一次反射的输入几何：位置、方向与屏幕起点打包，主函数不必收一长串参数。
struct gfx_reflection_surface {
	vec3 view_pos;    // 视空间表面位置。
	vec3 world_pos;   // 相机相对世界位置，供体素回退与反射雾使用。
	vec3 view_dir;    // 由相机指向表面的单位视线。
	vec3 normal;      // 视空间表面法线。
	vec3 screen_pos;  // 起点屏幕坐标与深度。
	float roughness;  // 材质粗糙度，粗糙面据此散开反射方向。
	float normal_up;  // 法线朝上的分量，天空回退按它判断能接多少天光。
	bool is_hand;     // 手部像素，深度图选择不同。
	bool is_smooth;   // 光滑面走镜面反射。
};

// 屏幕追踪的固定输入：深度图、投影与质量档位只在这里出现一次。
struct gfx_reflection_trace {
	mat4 projection;               // 近景投影。
	mat4 projection_inverse;       // 近景逆投影。
	mat4 dh_projection_inverse;    // 远景逆投影，没有远景时传近景逆投影占位。
	mat4 model_view;               // 视空间转相机相对世界空间。
	mat4 model_view_inverse;       // 相机相对世界空间转视空间。
	float near_plane;              // 近裁剪面距离。
	bool hand_supported;           // 当前版本是否有手部深度。
	bool has_dh;                   // 是否加载了远景模组。
	bool dh_ssr;                   // 是否允许反射命中远景。
	int quality;                   // 步进质量。
	int refinement_steps;          // 命中后的细化步数。
	float z_diff_threshold;        // 深度差阈值。
};

// 反射合成参数：把维度差异写成普通开关，主流程只有一条路径。
// 为什么用开关而不是在通用库里分维度：通用库不认识下界、末地这些游戏概念，调用方把差异说明成数值。
struct gfx_reflection_media {
	vec3 current_color;           // 全反射像素直接使用的当前场景色。
	vec3 highlight_color;         // 太阳或月光的高光颜色。
	float skylight;               // 天光等级，零到一。
	float highlight_strength;     // 高光提示强度，零表示不画。
	float output_factor;          // 管线线性单位与曲线单位之间的换算。
	float open_length;            // 没命中时射线到相机的总距离，雾按它估净空。
	float far_distance;           // 反射雾的最远距离。
	float cap_distance;           // 反射雾额外的绝对上限。
	bool total_reflection;        // 这是全反射像素。
	bool underwater;              // 相机在水里。
	bool sky_enabled;             // 没命中时用天空兜底。
	bool sky_uses_skylight;       // 天空兜底按天光衰减。
	bool sky_uses_facing;         // 天空兜底按朝上程度衰减。
	bool voxel_enabled;           // 屏幕没命中时再试体素回退。
	bool hit_dist_uses_total;     // 命中距离把表面到相机的距离也算进去（下界）。
	bool fog_color_enabled;       // 叠加解析雾色（下界、末地）。
	bool fog_color_needs_length;  // 解析雾色只在空气段大于零时叠加。
	bool fog_volume_enabled;      // 补地表散射与体积雾（主世界）。
};

// 反射合成参数的中性默认值：先关掉所有可选路径，再由各维度打开自己需要的项。
// 为什么把默认值放通用库：三个维度只是开关不同，默认结构只维护一份，避免抄错某个字段。
gfx_reflection_media gfx_reflection_media_default(vec3 current_color, vec3 highlight_color, float skylight,
		float highlight_strength, bool total_reflection, bool underwater, float output_factor){
	gfx_reflection_media media; // 待填的合成参数。
	media.current_color = current_color; // 全反射时直接用当前场景色。
	media.highlight_color = highlight_color; // 直射高光颜色。
	media.skylight = skylight; // 天光等级。
	media.highlight_strength = highlight_strength; // 高光提示强度。
	media.output_factor = output_factor; // 管线单位换算由调用方给出。
	media.open_length = 1e10; // 没命中时射线默认极远。
	media.far_distance = 1e10; // 雾最远距离默认不裁。
	media.cap_distance = 1e10; // 雾绝对上限默认不裁。
	media.total_reflection = total_reflection; // 全反射标记。
	media.underwater = underwater; // 相机是否在水里。
	media.sky_enabled = false; // 默认没有天空兜底。
	media.sky_uses_skylight = false; // 默认不按天光衰减。
	media.sky_uses_facing = false; // 默认不按朝向衰减。
	media.voxel_enabled = false; // 默认不追体素。
	media.hit_dist_uses_total = false; // 命中距离默认从表面量起。
	media.fog_color_enabled = false; // 默认没有解析雾。
	media.fog_color_needs_length = false; // 解析雾默认总是叠加。
	media.fog_volume_enabled = false; // 默认没有体积雾与地表散射。
	return media; // 交回中性参数。
}

// 以下六个宏是调用方注入的钩子，默认全部是中性操作；作用与 `gfx/fog_volume.glsl` 的雾照明钩子相同。
// 为什么用宏：通用库不能引用效果函数与宿主 uniform，调用方在引入本文件前把宿主细节写进钩子。
// 天空兜底：把反射方向换成天空颜色；默认没有天空。
#ifndef GFX_REFLECTION_SKY
#define GFX_REFLECTION_SKY(world_dir, is_smooth) vec3(0.0)
#endif
// 太阳高光：默认不亮，主世界用宿主光方向替换。
#ifndef GFX_REFLECTION_SKY_HIGHLIGHT
#define GFX_REFLECTION_SKY_HIGHLIGHT(normal, view_dir) 0.0
#endif
// 天空判定：默认把命中点当实心几何。
#ifndef GFX_REFLECTION_IS_SKY
#define GFX_REFLECTION_IS_SKY(screen_pos) false
#endif
// 体素回退：默认没命中，返回的 a 为负。
#ifndef GFX_REFLECTION_VOXEL
#define GFX_REFLECTION_VOXEL(world_pos, world_dir, normal, hit_world) vec4(0.0, 0.0, 0.0, -1.0)
#endif
// 命中点深度：默认用射线自己的深度，调用方可以改成读深度图。
#ifndef GFX_REFLECTION_HIT_DEPTH
#define GFX_REFLECTION_HIT_DEPTH(screen_pos) (screen_pos.z)
#endif
// 解析雾色：下界与末地按空气段长度返回散射色，默认没有雾。
#ifndef GFX_REFLECTION_FOG_COLOR
#define GFX_REFLECTION_FOG_COLOR(surface_dist, air_length, world_dir, is_sky) vec3(0.0)
#endif
// 体积雾与地表散射：主世界调用，默认原样返回。
#ifndef GFX_REFLECTION_FOG_VOLUME
#define GFX_REFLECTION_FOG_VOLUME(color, start_world, end_world, world_dir, air_length, is_sky) color
#endif
// 命中点视空间位置：默认用通用逆投影，调用方可改成会撤销时间抗锯齿抖动的版本。
#ifndef GFX_REFLECTION_VIEW_POS
#define GFX_REFLECTION_VIEW_POS(coord, depth, projection_inverse) gfx_reflection_view_pos(coord, depth, projection_inverse)
#endif
// 体素命中点投回屏幕：默认用不补抖动的原始投影，调用方可以补上时间抗锯齿抖动。
#ifndef GFX_REFLECTION_SCREEN_POS
#define GFX_REFLECTION_SCREEN_POS(view_pos, projection) gfx_reflection_screen_pos(view_pos, projection)
#endif

// 生成反射方向：光滑面直接反射，粗糙面先按可见法线抽样再反射。
vec3 gfx_reflection_dir(vec3 view_dir, vec3 normal, float roughness, vec2 noise, bool is_smooth){
	if (is_smooth) return reflect(view_dir, normal); // 镜面方向。
	vec3 normal_up = normalize(vec3(0.0, normal.z, -normal.y)); // 用竖直参考轴构造一个切向。
	mat3 to_tangent = mat3(cross(normal_up, normal), normal_up, normal); // 切线基，第三列是法线。
	vec3 tangent_view = view_dir * to_tangent; // 视线转到切线空间。
	vec3 visible_normal = to_tangent * gfx_sample_ggx_vndf(-tangent_view, roughness, noise); // 抽样一个可见法线。
	return reflect(view_dir, visible_normal); // 沿可见法线反射。
}

// 读场景颜色并换回线性；反射颜色统一用这个入口，编码格式只有一处。
vec3 gfx_reflection_scene_color(sampler2D scene_texture, vec2 coord){
	return gfx_CurveToLinear(textureLod(scene_texture, coord, 0.0).rgb); // 曲线编码转线性。
}

// 天空回退的朝向权重：面越朝上，接收的天空越多；朝下时保留四分之一，避免全黑。
float gfx_reflection_sky_facing(float normal_up){
	return gfx_saturate((normal_up + 0.7) * 2.0) * 0.75 + 0.25; // 与天空光在地面的分布一致。
}

// 命中点到表面的距离：命中点深度从深度图或射线深度取，单位是米。
float gfx_reflection_hit_length(vec3 view_pos, vec3 screen_pos, float hit_depth, mat4 projection_inverse){
	vec3 hit_pos = GFX_REFLECTION_VIEW_POS(screen_pos.xy, hit_depth, projection_inverse); // 还原命中点视空间位置。
	return distance(hit_pos, view_pos); // 命中点与表面之间隔着多少空气。
}

// 反射主流程：追踪一次反射，按开关补天空、体素与雾，最后返回曲线编码的颜色与命中距离。
// `noise` 由调用方给，主世界用蓝噪声、其他维度用固定噪声；`output_factor` 是管线单位换算。
// 深度图与场景颜色图单独作为采样器传入，避免把不透明类型塞进结构体。
vec4 gfx_specular_reflections(gfx_reflection_surface surface, gfx_reflection_trace trace, gfx_reflection_media media, vec2 noise,
		sampler2D depth_texture, sampler2D hand_depth_texture, sampler2D dh_depth_texture, sampler2D scene_texture){
	float ndotv = gfx_saturate(dot(-surface.view_dir, surface.normal)); // 视线与法线的夹角余弦。
	vec3 ray_dir = gfx_reflection_dir(surface.view_dir, surface.normal, surface.roughness, noise, surface.is_smooth); // 反射方向。
	vec3 screen_pos = surface.screen_pos; // 起点屏幕坐标，追踪会就地更新。
	float min_length = 0.015; // 粗糙面的最小步长。
	if (surface.is_smooth) min_length = (3e-4 - surface.view_pos.z * 7e-6 * gfx_saturate(ndotv * 500.0 - 1.0)) * trace.projection[1][1]; // 光滑面最小步长随深度与视线倾斜收紧。
	bool hit = gfx_screen_space_trace(surface.view_pos, ray_dir, ndotv, noise.x, min_length, surface.is_hand, screen_pos,
		depth_texture, hand_depth_texture, dh_depth_texture, trace.projection, trace.projection_inverse,
		trace.dh_projection_inverse, trace.near_plane, trace.hand_supported, trace.has_dh, trace.dh_ssr, trace.quality,
		trace.refinement_steps, trace.z_diff_threshold); // 屏幕空间追踪。
	vec3 ray_world_dir = mat3(trace.model_view_inverse) * ray_dir; // 反射方向转到世界空间，供天空、体素与雾使用。

	vec3 reflection = vec3(0.0); // 反射颜色；没命中且没有天空时保持黑色，避免读到未定义值。
	if (hit) reflection = gfx_reflection_scene_color(scene_texture, screen_pos.xy); // 命中几何时取该处场景色。

	bool is_sky = true; // 命中点是不是天空；没命中时按天空处理，与高光判定一致。
	float highlight = 0.0; // 太阳高光，只在光滑天空像素上出现。
	if (hit) is_sky = GFX_REFLECTION_IS_SKY(screen_pos); // 主世界按材质编号区分天空，其他维度都算实心。
	if (is_sky && surface.is_smooth && media.highlight_strength > 0.0) highlight = GFX_REFLECTION_SKY_HIGHLIGHT(surface.normal, surface.view_dir) * media.highlight_strength; // 光滑天空像素加一个太阳镜面高光。

	if (!hit){ // 没命中时用天空回退。
		if (media.total_reflection){ // 全反射时表面看不到外面的东西，直接取当前场景色。
			reflection = media.current_color;
		}else if (media.sky_enabled && !media.underwater && media.skylight > 0.0){ // 空中且有一定天光时才用天空。
			reflection = GFX_REFLECTION_SKY(ray_world_dir, surface.is_smooth); // 取天空颜色。
			float falloff = media.sky_uses_facing ? gfx_reflection_sky_facing(surface.normal_up) : 1.0; // 朝上的面接更多天空。
			if (media.sky_uses_skylight) falloff *= media.skylight; // 按天光衰减。
			reflection *= falloff; // 衰减天空反射。
			highlight *= falloff; // 高光同样衰减。
		}
	}

	reflection += media.highlight_color * highlight; // 叠加直射高光；没有高光时这一项为零。

	float hit_dist = surface.is_smooth ? 0.0 : 1.0; // 光滑面视作镜面，命中距离记零；粗糙面命中后按空气段改写。

	if (media.voxel_enabled && !hit && !media.total_reflection && !media.underwater){ // 屏幕空间没命中时再用体素补一次。
		vec3 voxel_hit_world; // 体素命中的相机相对世界位置，用来把反射雾的雾段算到真实命中点。
		vec4 voxel_hit = GFX_REFLECTION_VOXEL(surface.world_pos, ray_world_dir, surface.normal, voxel_hit_world); // 世界空间追踪体素图。
		if (voxel_hit.a >= 0.0){ // `a` 不为负就是命中。
			reflection = voxel_hit.rgb; // 用体素里存下的方块颜色作为反射。
			hit = true; // 当作命中几何，后面的雾按命中处理。
			is_sky = false; // 命中的不是天空。
			hit_dist = voxel_hit.a; // 归一化命中距离；光滑面原样保留，粗糙面稍后按雾段改写。
			screen_pos = GFX_REFLECTION_SCREEN_POS(mat3(trace.model_view) * voxel_hit_world, trace.projection); // 把命中点投回屏幕，反射雾按这段距离罩住体素反射。
		}
	}

	float surface_dist = length(surface.view_pos); // 表面到相机的距离。
	float air_length = media.open_length - surface_dist; // 没命中时按净空总距离减去表面距离估空气段。
	if (hit && !is_sky) air_length = gfx_reflection_hit_length(surface.view_pos, screen_pos, GFX_REFLECTION_HIT_DEPTH(screen_pos), trace.projection_inverse); // 命中实心几何时按命中点算空气段。
	if (hit && !surface.is_smooth){ // 粗糙面把空气段换成滤波用的命中距离。
		float dist_for_hit = media.hit_dist_uses_total ? air_length + surface_dist : air_length; // 下界的命中距离把表面距离也算进去。
		hit_dist = gfx_saturate(max(dist_for_hit * 2.0, 3.0 * surface.roughness)); // 距离越远、表面越粗糙，滤波半径越大。
	}
	float fog_air = max(min(min(air_length + surface_dist, media.far_distance), media.cap_distance) - surface_dist, 0.0); // 雾段裁到可视范围。

	if (media.fog_color_enabled && (!media.fog_color_needs_length || fog_air > 0.0)) reflection += GFX_REFLECTION_FOG_COLOR(surface_dist, fog_air, ray_world_dir, is_sky) / media.output_factor; // 下界末地补解析雾。
	if (media.fog_volume_enabled){ // 主世界补地表散射与体积雾。
		float fog_skylight = media.underwater ? 1.0 : media.skylight; // 水下天光按满值，水下雾才能正常出现。
		if (fog_skylight > 0.0 && fog_air > 0.0){ // 有天光且有空气段才补雾。
			vec3 lit = reflection * media.output_factor; // 换到管线线性单位。
			vec3 fogged = GFX_REFLECTION_FOG_VOLUME(lit, surface.world_pos, surface.world_pos + ray_world_dir * fog_air, ray_world_dir, fog_air, is_sky); // 在副本上补散射。
			reflection = mix(reflection, fogged / media.output_factor, fog_skylight); // 按天光在原色与补雾色之间混合。
		}
	}

	return vec4(gfx_LinearToCurve(reflection), hit_dist); // 曲线编码后与命中距离一起返回。
}

// 把反射颜色按菲涅耳、金属度与水吸收混进场景色；`not_total` 为假时是全反射像素，直接取反射色。
void gfx_specular_reflection_mix(inout vec3 color, vec3 view_dir, vec3 normal, vec3 albedo, float water_absorption, vec3 reflection,
		bool not_total, float metalness, float roughness, float f0, float reflection_strength, bool overworld){
	if (!not_total){ // 全反射像素直接取反射色。
		color = reflection; // 表面看不到外面的东西。
		return;
	}
	reflection *= mix(vec3(1.0), albedo, vec3(metalness)); // 金属面用底色给反射染色。
	vec3 l = normalize(reflect(view_dir, normal) + normal * roughness); // 反射方向按粗糙度偏一点。
	vec3 h = normalize(l - view_dir); // 反射方向与视线的半程。
	float l_dot_h = gfx_saturate(dot(l, h)); // 反射与半程夹角。
	float n_dot_l = gfx_saturate(dot(normal, l)); // 反射方向的入射余弦。
	float n_dot_v = gfx_saturate(dot(normal, -view_dir)); // 视线方向的入射余弦。
	float specular = gfx_F_Schlick(l_dot_h, f0, 1.0); // 菲涅耳。
	specular *= gfx_V_Schlick(n_dot_l, n_dot_v + 0.8, roughness); // 乘可见性，视线余弦补零点八避免掠射过亮。
	specular *= reflection_strength; // 乘材质允许的反射强度。
	specular = mix(specular, 1.0, metalness); // 金属面反射权重拉满。
	vec3 temp = color; // 记下原底色，金属面要再加一份。
	float diff = (length(color) - length(reflection)) / (length(color) + length(reflection)); // 底色与反射的亮度相对差。
	diff = sign(diff) * sqrt(abs(diff)); // 开方让差的分布更平缓。
	specular += 0.75 * diff * (1.0 - specular) * specular; // 亮度差大时补一点反射。
	if (overworld){ // 主世界按水吸收缩反射权重。
		color = mix(color, reflection, gfx_saturate(specular * water_absorption)); // 混合反射。
		color += temp * (metalness * water_absorption); // 金属面再加一份底色。
	}else{ // 下界末地按反射权重混合。
		color = mix(color, reflection, gfx_saturate(specular)); // 混合反射。
		color += temp * metalness; // 金属面再加一份底色。
	}
}

// 反射小波滤波：九点邻域按反射方向与深度相似度加权，抹掉追踪噪点同时保住反射边界。
// 为什么按法线与深度加权：命中点落在不同法线或不同深度的邻居属于别的物体，混进来会把反射糊成一片。
// 为什么先按亮度幂次重整再还原：高动态范围的反射点会盖住整片邻域，先压一下亮度再合并，边界更干净。
void gfx_reflection_atrous_filter(inout vec4 reflection_data, vec3 view_pos, vec3 view_dir, vec3 normal,
		float roughness, float radius, vec2 noise, vec2 tex_coord, sampler2D reflection_texture,
		sampler2D depth_texture, sampler2D normal_texture, vec2 pixel_size, mat4 projection_inverse){
	float linear_depth = -view_pos.z; // 表面的米制深度。
	float ndotv = gfx_saturate(dot(-view_dir, normal)); // 视线与法线夹角余弦。

	roughness = max(roughness, 1e-4); // 粗糙度给一个下限，避免除以零。
	radius *= min(roughness * 20.0, 1.0); // 越粗糙反射越糊，滤波半径越大。
	radius *= reflection_data.a * 0.9 + 0.1; // 命中距离越远半径越大。

	const mat2 rot90 = mat2(cos(1.5708), -sin(1.5708), sin(1.5708), cos(1.5708)); // 旋转九十度，用来由切向得到副切向。
	vec2 tangent = normalize(cross(normal, view_dir).xy) * radius; // 沿表面切向的采样步长。
	vec2 bitangent = tangent * rot90; // 副切向的采样步长。
	tangent *= mix(0.1075, 0.5, ndotv) * pixel_size; // 切向按视角缩放并换成屏幕坐标。
	bitangent *= mix(0.7, 0.5, ndotv) * pixel_size; // 副切向同理。

	vec3 reflected_dir = reflect(-view_dir, normal); // 当前像素的反射方向。
	float normal_threshold = 75.0 / roughness; // 法线相似度的幂次，越粗糙越严。
	float luminance_threshold = reflection_data.a * 0.95 + 0.05; // 亮度重整的幂次，按命中距离变化。

	vec4 accum = vec4(0.0); // 加权累加的反射数据。
	float weights = 0.0; // 累加权重。
	const vec2 offset[9] = vec2[9]( // 三乘三邻域偏移。
		vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0),
		vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0),
		vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0));

	for (int i = 0; i < 9; i++){ // 遍历九个邻点。
		vec2 sample_coord = tex_coord + tangent * (offset[i] + noise.x) + bitangent * (offset[i] + noise.y); // 邻点坐标，按抖动微调。
		vec4 sample_data = textureLod(reflection_texture, sample_coord, 0.0); // 读邻点反射数据。
		if (sample_data.a < 0.0001) continue; // 邻点没有反射，跳过。

		float sample_depth = gfx_reflection_linear_depth(textureLod(depth_texture, sample_coord, 0.0).x, projection_inverse); // 邻点米制深度。
		vec3 sample_reflected = reflect(-view_dir, gfx_DecodeNormal(textureLod(normal_texture, sample_coord, 0.0).xy)); // 邻点反射方向。

		float normal_weight = pow(gfx_saturate(dot(sample_reflected, reflected_dir)), normal_threshold); // 反射方向越接近权重越大。
		float depth_weight = exp2(-(abs(sample_depth - linear_depth) * 1.58)); // 深度越接近权重越大。
		float sample_weight = normal_weight * depth_weight; // 两个权重相乘。

		sample_data.rgb += 1e-13; // 避免零亮度在下面除法里出问题。
		float luminance = length(sample_data.rgb); // 邻点亮度。
		sample_data.rgb *= pow(luminance, luminance_threshold) / luminance; // 按幂次重整亮度。

		accum += sample_data * sample_weight; // 按权重累加。
		weights += sample_weight; // 累加权重。
	}

	if (weights > 1e-13){ // 有有效邻点才写回。
		accum /= weights; // 取加权平均。
		accum.rgb += 1e-13; // 同样避免零亮度。
		float luminance = length(accum.rgb); // 平均后的亮度。
		accum.rgb *= pow(luminance, 1.0 / luminance_threshold) / luminance; // 还原亮度重整。
		reflection_data = accum; // 写回滤波结果。
	}
}

#endif
