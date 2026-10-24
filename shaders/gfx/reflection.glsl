/*
反射模块适配层：采样、追踪、菲涅耳合并与降噪已迁到生成库，这里保留宿主合成流程。
调用位置：`effects/reflection/screenspace.glsl` 与 `effects/reflection/denoise.glsl` 引用本文件。
可复制示例：`vec4 r = gfx_specular_reflections(surface, trace, media, noise, depth1, depth2, dhDepth, scene);`
设计原因与取舍：天空兜底、体素回退、反射雾这些宿主差异用 `GFX_REFLECTION_*` 钩子注入，
    钩子只在合成流程里展开；采样循环与滤波都在 `omni-gfx/src/reflection.slang`，两处不再各写一套公式。
*/
#ifndef GFX_REFLECTION_INCLUDED
#define GFX_REFLECTION_INCLUDED

// 迁移后的反射实现：可见法线采样、屏幕空间追踪、方向生成与降噪。
#include "/omni-gfx/reflection.glsl"
// 数学模块提供饱和、法线解码与曲线编码。
#include "/gfx/math.glsl"

// 可见法线分布采样：按粗糙度把反射方向散开，得到模糊反射。
vec3 gfx_sample_ggx_vndf(vec3 viewVector, float roughness, vec2 noise) { // 旧名字的兼容入口。
	return ogxSampleGgxVndf(viewVector, roughness, noise); // 实现在生成库。
}

// 视空间位置投到屏幕，不补抖动。
vec3 gfx_reflection_screen_pos(vec3 view_pos, mat4 projection) { // 旧名字的兼容入口。
	return ogxReflectionScreenPos(view_pos, projection); // 实现在生成库。
}

// 屏幕坐标与深度还原视空间位置。
vec3 gfx_reflection_view_pos(vec2 coord, float depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	return ogxReflectionViewPos(coord, depth, projection_inverse); // 实现在生成库。
}

// 屏幕深度换米制距离。
float gfx_reflection_linear_depth(float depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	return ogxReflectionLinearDepth(depth, projection_inverse); // 实现在生成库。
}

// 读场景颜色并换回线性。
vec3 gfx_reflection_scene_color(sampler2D scene_texture, vec2 coord) { // 旧名字的兼容入口。
	return ogxReflectionSceneColor(scene_texture, coord); // 实现在生成库。
}

// 天空回退的朝向权重：面越朝上，接收的天空越多。
float gfx_reflection_sky_facing(float normal_up) { // 旧名字的兼容入口。
	return ogxReflectionSkyFacing(normal_up); // 实现在生成库。
}

// 把反射颜色按菲涅耳、金属度与水吸收混进场景色。
void gfx_specular_reflection_mix(inout vec3 color, vec3 view_dir, vec3 normal, vec3 albedo, float water_absorption, vec3 reflection, bool not_total, float metalness, float roughness, float f0, float reflection_strength, bool overworld) { // 旧名字的兼容入口。
	ogxSpecularReflectionMix(color, view_dir, normal, albedo, water_absorption, reflection, not_total, metalness, roughness, f0, reflection_strength, overworld); // 实现在生成库。
}

// 反射小波滤波：九点邻域按反射方向与深度相似度加权，抹掉追踪噪点同时保住边界。
void gfx_reflection_atrous_filter(inout vec4 reflection_data, vec3 view_pos, vec3 view_dir, vec3 normal, float roughness, float radius, vec2 noise, vec2 tex_coord, sampler2D reflection_texture, sampler2D depth_texture, sampler2D normal_texture, vec2 pixel_size, mat4 projection_inverse) { // 旧名字的兼容入口。
	ogxReflectionAtrousFilter(reflection_data, view_pos, view_dir, normal, roughness, radius, noise, tex_coord, reflection_texture, depth_texture, normal_texture, pixel_size, projection_inverse); // 实现在生成库。
}

// 一次反射的输入几何：位置、方向与屏幕起点打包，主函数不必收一长串参数。
struct gfx_reflection_surface { // 宿主合成用的输入结构。
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
struct gfx_reflection_trace { // 宿主合成用的追踪参数。
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
struct gfx_reflection_media { // 宿主合成用的开关集合。
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
gfx_reflection_media gfx_reflection_media_default(vec3 current_color, vec3 highlight_color, float skylight, float highlight_strength, bool total_reflection, bool underwater, float output_factor) { // 默认值只维护一份。
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

// 以下七个宏是调用方注入的钩子，默认全部是中性操作。
#ifndef GFX_REFLECTION_SKY
#define GFX_REFLECTION_SKY(world_dir, is_smooth) vec3(0.0) // 默认没有天空兜底。
#endif
#ifndef GFX_REFLECTION_SKY_HIGHLIGHT
#define GFX_REFLECTION_SKY_HIGHLIGHT(normal, view_dir) 0.0 // 默认没有太阳高光。
#endif
#ifndef GFX_REFLECTION_IS_SKY
#define GFX_REFLECTION_IS_SKY(screen_pos) false // 默认把命中点当实心几何。
#endif
#ifndef GFX_REFLECTION_VOXEL
#define GFX_REFLECTION_VOXEL(world_pos, world_dir, normal, hit_world) vec4(0.0, 0.0, 0.0, -1.0) // 默认没命中体素。
#endif
#ifndef GFX_REFLECTION_HIT_DEPTH
#define GFX_REFLECTION_HIT_DEPTH(screen_pos) (screen_pos.z) // 默认用射线自己的深度。
#endif
#ifndef GFX_REFLECTION_FOG_COLOR
#define GFX_REFLECTION_FOG_COLOR(surface_dist, air_length, world_dir, is_sky) vec3(0.0) // 默认没有解析雾。
#endif
#ifndef GFX_REFLECTION_FOG_VOLUME
#define GFX_REFLECTION_FOG_VOLUME(color, start_world, end_world, world_dir, air_length, is_sky) color // 默认原样返回。
#endif
#ifndef GFX_REFLECTION_VIEW_POS
#define GFX_REFLECTION_VIEW_POS(coord, depth, projection_inverse) gfx_reflection_view_pos(coord, depth, projection_inverse) // 默认用通用逆投影。
#endif
#ifndef GFX_REFLECTION_SCREEN_POS
#define GFX_REFLECTION_SCREEN_POS(view_pos, projection) gfx_reflection_screen_pos(view_pos, projection) // 默认不补抖动。
#endif

// 命中点到表面的距离：命中点视空间位置由钩子还原，单位是米。
float gfx_reflection_hit_length(vec3 view_pos, vec3 screen_pos, float hit_depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	vec3 hit_pos = GFX_REFLECTION_VIEW_POS(screen_pos.xy, hit_depth, projection_inverse); // 还原命中点视空间位置。
	return ogxReflectionHitLength(view_pos, hit_pos); // 距离计算在生成库。
}

// 反射主流程：追踪一次反射，按开关补天空、体素与雾，最后返回曲线编码的颜色与命中距离。
vec4 gfx_specular_reflections(gfx_reflection_surface surface, gfx_reflection_trace trace, gfx_reflection_media media, vec2 noise, sampler2D depth_texture, sampler2D hand_depth_texture, sampler2D dh_depth_texture, sampler2D scene_texture) { // 宿主合成流程。
	float ndotv = gfx_saturate(dot(-surface.view_dir, surface.normal)); // 视线与法线的夹角余弦。
	vec3 ray_dir = ogxReflectionDir(surface.view_dir, surface.normal, surface.roughness, noise, surface.is_smooth); // 反射方向。
	vec3 screen_pos = surface.screen_pos; // 起点屏幕坐标，追踪会就地更新。
	float min_length = 0.015; // 粗糙面的最小步长。
	if (surface.is_smooth) min_length = (3e-4 - surface.view_pos.z * 7e-6 * gfx_saturate(ndotv * 500.0 - 1.0)) * trace.projection[1][1]; // 光滑面最小步长随深度收紧。
	bool hit = ogxScreenSpaceTrace(surface.view_pos, ray_dir, ndotv, noise.x, min_length, surface.is_hand, screen_pos, depth_texture, hand_depth_texture, dh_depth_texture, trace.projection, trace.projection_inverse, trace.dh_projection_inverse, trace.near_plane, trace.hand_supported, trace.has_dh, trace.dh_ssr, trace.quality, trace.refinement_steps, trace.z_diff_threshold); // 屏幕空间追踪。
	vec3 ray_world_dir = mat3(trace.model_view_inverse) * ray_dir; // 反射方向转到世界空间，供天空、体素与雾使用。
	vec3 reflection = vec3(0.0); // 反射颜色；没命中且没有天空时保持黑色。
	if (hit) reflection = gfx_reflection_scene_color(scene_texture, screen_pos.xy); // 命中几何时取该处场景色。
	bool is_sky = true; // 命中点是不是天空；没命中时按天空处理。
	float highlight = 0.0; // 太阳高光，只在光滑天空像素上出现。
	if (hit) is_sky = GFX_REFLECTION_IS_SKY(screen_pos); // 主世界按材质编号区分天空。
	if (is_sky && surface.is_smooth && media.highlight_strength > 0.0) highlight = GFX_REFLECTION_SKY_HIGHLIGHT(surface.normal, surface.view_dir) * media.highlight_strength; // 光滑天空像素加太阳高光。
	if (!hit) { // 没命中时用天空回退。
		if (media.total_reflection) { // 全反射时直接取当前场景色。
			reflection = media.current_color;
		} else if (media.sky_enabled && !media.underwater && media.skylight > 0.0) { // 空中且有一定天光时才用天空。
			reflection = GFX_REFLECTION_SKY(ray_world_dir, surface.is_smooth); // 取天空颜色。
			float falloff = media.sky_uses_facing ? gfx_reflection_sky_facing(surface.normal_up) : 1.0; // 朝上的面接更多天空。
			if (media.sky_uses_skylight) falloff *= media.skylight; // 按天光衰减。
			reflection *= falloff; // 衰减天空反射。
			highlight *= falloff; // 高光同样衰减。
		}
	}
	reflection += media.highlight_color * highlight; // 叠加直射高光。
	float hit_dist = surface.is_smooth ? 0.0 : 1.0; // 光滑面视作镜面，粗糙面命中后按空气段改写。
	if (media.voxel_enabled && !hit && !media.total_reflection && !media.underwater) { // 屏幕空间没命中时再用体素补一次。
		vec3 voxel_hit_world; // 体素命中的相机相对世界位置。
		vec4 voxel_hit = GFX_REFLECTION_VOXEL(surface.world_pos, ray_world_dir, surface.normal, voxel_hit_world); // 世界空间追踪体素图。
		if (voxel_hit.a >= 0.0) { // `a` 不为负就是命中。
			reflection = voxel_hit.rgb; // 用体素里存下的方块颜色作为反射。
			hit = true; // 当作命中几何。
			is_sky = false; // 命中的不是天空。
			hit_dist = voxel_hit.a; // 归一化命中距离。
			screen_pos = GFX_REFLECTION_SCREEN_POS(mat3(trace.model_view) * voxel_hit_world, trace.projection); // 把命中点投回屏幕。
		}
	}
	float surface_dist = length(surface.view_pos); // 表面到相机的距离。
	float air_length = media.open_length - surface_dist; // 没命中时按净空总距离估空气段。
	if (hit && !is_sky) air_length = gfx_reflection_hit_length(surface.view_pos, screen_pos, GFX_REFLECTION_HIT_DEPTH(screen_pos), trace.projection_inverse); // 命中实心几何时按命中点算空气段。
	if (hit && !surface.is_smooth) { // 粗糙面把空气段换成滤波用的命中距离。
		float dist_for_hit = media.hit_dist_uses_total ? air_length + surface_dist : air_length; // 下界把表面距离也算进去。
		hit_dist = gfx_saturate(max(dist_for_hit * 2.0, 3.0 * surface.roughness)); // 距离越远、表面越粗糙，滤波半径越大。
	}
	float fog_air = max(min(min(air_length + surface_dist, media.far_distance), media.cap_distance) - surface_dist, 0.0); // 雾段裁到可视范围。
	if (media.fog_color_enabled && (!media.fog_color_needs_length || fog_air > 0.0)) reflection += GFX_REFLECTION_FOG_COLOR(surface_dist, fog_air, ray_world_dir, is_sky) / media.output_factor; // 下界末地补解析雾。
	if (media.fog_volume_enabled) { // 主世界补地表散射与体积雾。
		float fog_skylight = media.underwater ? 1.0 : media.skylight; // 水下天光按满值。
		if (fog_skylight > 0.0 && fog_air > 0.0) { // 有天光且有空气段才补雾。
			vec3 lit = reflection * media.output_factor; // 换到管线线性单位。
			vec3 fogged = GFX_REFLECTION_FOG_VOLUME(lit, surface.world_pos, surface.world_pos + ray_world_dir * fog_air, ray_world_dir, fog_air, is_sky); // 在副本上补散射。
			reflection = mix(reflection, fogged / media.output_factor, fog_skylight); // 按天光在原色与补雾色之间混合。
		}
	}
	return vec4(gfx_LinearToCurve(reflection), hit_dist); // 曲线编码后与命中距离一起返回。
}

#endif
