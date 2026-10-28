/*
效果文件 `effects/reflection/screenspace.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/reflection/screenspace.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_REFLECTION_SCREENSPACE_INCLUDED
#define OMNI_REFLECTION_SCREENSPACE_INCLUDED
/*
屏幕空间反射：从当前像素沿反射方向在屏幕里步进找命中，未命中回退天空盒或体素，并算高光提示强度与反射颜色。
来源 iterationT `composite2.fsh`（追踪与着色）与 `composite5.fsh`（把反射并进场景颜色）。
调用位置：由 `effects/reflection/reflection.glsl` 引入；只在 composite2 / composite5 程序里编译，别的程序整段跳过。
可复制示例：
    `vec4 r = CalculateSpecularReflections(viewPos, worldPos, viewDir, normal, depth, albedo, material, skyLight, isHand, isSmooth, highlightStrength);`
    `CalculateSpecularReflections(color, viewDir, normal, albedo, waterSurface, gbuffer);`
设计原因与取舍：追踪、天空兜底、体素回退、反射雾与高光是一个整体，通用流程在 `gfx/reflection.glsl`；
    本文件只把宿主 uniform、维度差异与选项写进通用库的结构和钩子，画面参数与原来逐字一致。
    天空兜底补的是屏幕里看不到的方向，这是屏幕空间反射的固有边界；下界与末地各用本维度的天空与雾。
*/

// --- composite2：屏幕空间反射与天空盒回退 ---
#ifdef OMNI_COMPOSITE2_PASS
// 蓝噪声给追踪与体积反射抖动，材质提供解码材质，天空云提供假天空反射与云影开关，雾提供反射里的体积雾与地表散射。
#include "/common/noise.glsl"
#include "/effects/shared/surface.glsl"
#include "/effects/shared/skyview.glsl"
#include "/effects/shared/cloud.glsl"
#include "/effects/shared/fog.glsl"

// 远景深度图选择：没有远景模组时用近景深度占位，通用库按开关决定是否读取。
#ifdef DISTANT_HORIZONS
	#define OMNI_REFLECTION_DH_DEPTH dhDepthTex1 // 远景不含半透明深度。
#else
	#define OMNI_REFLECTION_DH_DEPTH depthtex1 // 占位，不会被读取。
#endif

#if !defined OMNI_NETHER && !defined OMNI_END // 主世界才用天空盒回退；下界用 `NetherFog`，末地用末地天空。
// 体素反射：屏幕空间没命中时改在体素图上追踪，提供选项、体素颜色图取样与 `omniVoxelReflection`。
#include "/effects/reflection/voxel.glsl"
// 如果屏幕追踪没命中，就用上半屏的天空盒图当反射：把反射方向投到天空盒坐标再取色。
// 为什么单列一个函数：屏幕内没有内容时天空是唯一的反射源，缺了它反射处会变成黑洞。
// 调用前提：`colortex2`、`worldMoonVector`、`colorMoonlight`、`isEyeInWater` 已由合成主程序声明。
vec3 ComputeFakeSkyReflection(vec3 reflectWorldDir){
	float tileSize = min(OMNI_SKY_IMAGE_RESOLUTION, floor(min(screenSize.x / 3.3, screenSize.y * 0.45))); // 天空盒图的边长，受屏幕尺寸限制。
	vec2 skyImageCoord = ProjectSky(reflectWorldDir, tileSize); // 反射方向投到天空盒坐标，与天空写入端同一套映射。
	vec4 skyImage = textureLod(colortex2, skyImageCoord, 0.0); // 读天空盒图。
	skyImage.rgb = CurveToLinear(skyImage.rgb); // 从曲线编码换回线性。

	#ifdef OMNI_MOON_TEXTURE // 使用资源包月亮贴图时，反射里也画一个月亮圆盘。
		if (isEyeInWater == 0){ // 水下不画月亮，避免和水面下的画面冲突。
			float moonDisc = RenderMoonDiscReflection(reflectWorldDir, worldMoonVector); // 反射用的月亮圆盘，角半径更大才看得见。
			moonDisc *= mix(1.0, skyImage.a, OMNI_RAIN_SHADOW); // 按雨天遮蔽把月亮压暗。
			moonDisc *= (15.0 * OMNI_SKY_TEXTURE_BRIGHTNESS / MAIN_OUTPUT_FACTOR); // 换算到管线单位并乘纹理亮度。
			skyImage.rgb += colorMoonlight * moonDisc; // 月亮直射叠加到天空反射上。
		}
	#endif

	return skyImage.rgb; // 返回天空反射颜色。
}
#endif // 天空盒回退分支结束。

// 反射里的空气散射：地表大气散射与体积雾都按反射射线那一段补，最后返回补好的颜色。
// 为什么返回颜色而不是就地修改：通用库把这个钩子当表达式用，返回值直接接进混合步骤。
vec3 OmniReflectionVolumeFog(vec3 color, vec3 startWorld, vec3 endWorld, vec3 rayWorldDir, float airLength, bool isSky){
	#ifdef OMNI_LANDSCATTERING // 地表大气散射。
		#if defined DISTANT_HORIZONS || defined OMNI_LANDSCATTERING_REFLECTION
			LandAtmosphericScattering(color, airLength, startWorld, endWorld, rayWorldDir, isSky); // 有远景或开启反射散射时补散射。
		#endif
	#endif

	#ifdef OMNI_VFOG // 体积雾。
		#ifdef OMNI_VFOG_REFLECTION
			float globalCloudShadow = GetSmoothCloudShadow(); // 全局云影，供雾的光照遮蔽使用；只有体积雾才读。
			#ifdef OMNI_UNDERWATER_VFOG
				if (isEyeInWater == 1) color += UnderwaterVolumetricFog(startWorld, endWorld, rayWorldDir, globalCloudShadow); // 水下补水下体积雾。
			#endif

			float fogTimeFactor = 1.0; // 体积雾的时间因子，白天更浓。
			#ifndef OMNI_VFOG_IGNORE_WORLDTIME // 不忽略时间时按白天夜晚调整。
				#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系降水情况。
					fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness * (1.0 - eyeNoPrecipitationSmooth * 0.7));
				#else
					fogTimeFactor *= mix(1.0 - timeNoon, 1.0, wetness); // 关闭局部降水时只看整体湿润度。
				#endif
			#endif

			float fogTransmittance = 1.0; // 透射率占位，本处不返回。
			if (fogTimeFactor > 0.01 && isEyeInWater == 0) VolumetricFog(color, startWorld, endWorld, rayWorldDir, globalCloudShadow, fogTimeFactor, fogTransmittance); // 补体积雾。
		#endif
	#endif
	return color; // 交回补好散射的颜色。
}

// 命中点视空间位置：撤销时间抗锯齿抖动，与场景几何对齐；三个维度共用。
#define OMNI_REFLECTION_VIEW_POS(coord, depth, projection_inverse) ViewPos_From_ScreenPos(coord, depth)

// --- 维度钩子：通用库的默认钩子是中性操作，这里按维度接上天空、体素、深度与雾 ---
#if defined OMNI_NETHER
// 下界没有天空兜底与体素，只有一段解析雾；雾函数自己按两个距离求差。
#define OMNI_REFLECTION_FOG_COLOR(surface_dist, air_length, world_dir, is_sky) NetherFog(vec2(air_length + surface_dist, surface_dist))
#elif defined OMNI_END
// 末地天空兜底带光滑面标记，命中点深度取含半透明的深度图，雾只叠散射。
#define OMNI_REFLECTION_SKY(world_dir, is_smooth) ComputeFakeSkyReflectionEnd(world_dir, is_smooth)
#define OMNI_REFLECTION_HIT_DEPTH(screen_pos) textureLod(depthtex0, screen_pos.xy, 0.0).x
#define OMNI_REFLECTION_FOG_COLOR(surface_dist, air_length, world_dir, is_sky) EndFog(air_length, world_dir)
#else
// 主世界天空兜底用上半屏天空盒，天空判定与太阳高光接回宿主光方向，体素回退与体积雾走对应效果函数。
#define OMNI_REFLECTION_SKY(world_dir, is_smooth) ComputeFakeSkyReflection(world_dir)
#define OMNI_REFLECTION_SKY_HIGHLIGHT(normal, view_dir) SpecularGGX(normal, -view_dir, shadowVector, 0.002, 0.06)
#define OMNI_REFLECTION_IS_SKY(screen_pos) (floor(textureLod(colortex5, screen_pos.xy, 0.0).b * 255.0) < 0.5)
// 体素函数只在开启功能且显卡支持自定义图像时存在，钩子也只在这时接上。
#if OMNI_VOXEL_REFLECTION && defined IRIS_FEATURE_CUSTOM_IMAGES
#define OMNI_REFLECTION_VOXEL(world_pos, world_dir, normal, hit_world) omniVoxelReflection(world_pos, world_dir, normal, hit_world)
#endif
#define OMNI_REFLECTION_SCREEN_POS(view_pos, projection) ScreenPos_From_ViewPos(view_pos)
#define OMNI_REFLECTION_FOG_VOLUME(color, start_world, end_world, world_dir, air_length, is_sky) OmniReflectionVolumeFog(color, start_world, end_world, world_dir, air_length, is_sky)
// 命中点深度：补雾的配置用射线自己的深度，不补雾的配置改读深度图，与原程序的两个分支一致。
#if (defined OMNI_LANDSCATTERING && (defined OMNI_LANDSCATTERING_REFLECTION || defined DISTANT_HORIZONS)) || (defined OMNI_VFOG && defined OMNI_VFOG_REFLECTION)
#define OMNI_REFLECTION_HIT_DEPTH(screen_pos) (screen_pos.z)
#else
#define OMNI_REFLECTION_HIT_DEPTH(screen_pos) textureLod(depthtex0, screen_pos.xy, 0.0).x
#endif
#endif

// 追踪、天空与体素回退、反射雾的主流程在通用库。

// 屏幕空间追踪、方向生成与降噪都在生成库；本文件只保留宿主合成流程。
#include "/omni-gfx/reflection/reflection.glsl"
// 数学模块提供饱和、法线解码与曲线编码。
#include "/omni-gfx/common/math.glsl"

// 一次反射的输入几何：位置、方向与屏幕起点打包，主函数不必收一长串参数。
struct ReflectionSurface { // 宿主合成用的输入结构。
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
struct ReflectionTrace { // 宿主合成用的追踪参数。
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
struct ReflectionMedia { // 宿主合成用的开关集合。
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
ReflectionMedia ReflectionMediaDefault(vec3 current_color, vec3 highlight_color, float skylight, float highlight_strength, bool total_reflection, bool underwater, float output_factor) { // 默认值只维护一份。
	ReflectionMedia media; // 待填的合成参数。
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
#ifndef OMNI_REFLECTION_SKY
#define OMNI_REFLECTION_SKY(world_dir, is_smooth) vec3(0.0) // 默认没有天空兜底。
#endif
#ifndef OMNI_REFLECTION_SKY_HIGHLIGHT
#define OMNI_REFLECTION_SKY_HIGHLIGHT(normal, view_dir) 0.0 // 默认没有太阳高光。
#endif
#ifndef OMNI_REFLECTION_IS_SKY
#define OMNI_REFLECTION_IS_SKY(screen_pos) false // 默认把命中点当实心几何。
#endif
#ifndef OMNI_REFLECTION_VOXEL
#define OMNI_REFLECTION_VOXEL(world_pos, world_dir, normal, hit_world) vec4(0.0, 0.0, 0.0, -1.0) // 默认没命中体素。
#endif
#ifndef OMNI_REFLECTION_HIT_DEPTH
#define OMNI_REFLECTION_HIT_DEPTH(screen_pos) (screen_pos.z) // 默认用射线自己的深度。
#endif
#ifndef OMNI_REFLECTION_FOG_COLOR
#define OMNI_REFLECTION_FOG_COLOR(surface_dist, air_length, world_dir, is_sky) vec3(0.0) // 默认没有解析雾。
#endif
#ifndef OMNI_REFLECTION_FOG_VOLUME
#define OMNI_REFLECTION_FOG_VOLUME(color, start_world, end_world, world_dir, air_length, is_sky) color // 默认原样返回。
#endif
#ifndef OMNI_REFLECTION_VIEW_POS
#define OMNI_REFLECTION_VIEW_POS(coord, depth, projection_inverse) ogxReflectionViewPos(coord, depth, projection_inverse) // 默认用通用逆投影。
#endif
#ifndef OMNI_REFLECTION_SCREEN_POS
#define OMNI_REFLECTION_SCREEN_POS(view_pos, projection) ogxReflectionScreenPos(view_pos, projection) // 默认不补抖动。
#endif

// 命中点到表面的距离：命中点视空间位置由钩子还原，单位是米。
float ReflectionHitLength(vec3 view_pos, vec3 screen_pos, float hit_depth, mat4 projection_inverse) { // 旧名字的兼容入口。
	vec3 hit_pos = OMNI_REFLECTION_VIEW_POS(screen_pos.xy, hit_depth, projection_inverse); // 还原命中点视空间位置。
	return ogxReflectionHitLength(view_pos, hit_pos); // 距离计算在生成库。
}

// 反射主流程：追踪一次反射，按开关补天空、体素与雾，最后返回曲线编码的颜色与命中距离。
vec4 SpecularReflections(ReflectionSurface surface, ReflectionTrace trace, ReflectionMedia media, vec2 noise, sampler2D depth_texture, sampler2D hand_depth_texture, sampler2D dh_depth_texture, sampler2D scene_texture) { // 宿主合成流程。
	float ndotv = ogxSaturate(dot(-surface.view_dir, surface.normal)); // 视线与法线的夹角余弦。
	vec3 ray_dir = ogxReflectionDir(surface.view_dir, surface.normal, surface.roughness, noise, surface.is_smooth); // 反射方向。
	vec3 screen_pos = surface.screen_pos; // 起点屏幕坐标，追踪会就地更新。
	float min_length = 0.015; // 粗糙面的最小步长。
	if (surface.is_smooth) min_length = (3e-4 - surface.view_pos.z * 7e-6 * ogxSaturate(ndotv * 500.0 - 1.0)) * trace.projection[1][1]; // 光滑面最小步长随深度收紧。
	bool hit = ogxScreenSpaceTrace(surface.view_pos, ray_dir, ndotv, noise.x, min_length, surface.is_hand, screen_pos, depth_texture, hand_depth_texture, dh_depth_texture, trace.projection, trace.projection_inverse, trace.dh_projection_inverse, trace.near_plane, trace.hand_supported, trace.has_dh, trace.dh_ssr, trace.quality, trace.refinement_steps, trace.z_diff_threshold); // 屏幕空间追踪。
	vec3 ray_world_dir = mat3(trace.model_view_inverse) * ray_dir; // 反射方向转到世界空间，供天空、体素与雾使用。
	vec3 reflection = vec3(0.0); // 反射颜色；没命中且没有天空时保持黑色。
	if (hit) reflection = ogxReflectionSceneColor(scene_texture, screen_pos.xy); // 命中几何时取该处场景色。
	bool is_sky = true; // 命中点是不是天空；没命中时按天空处理。
	float highlight = 0.0; // 太阳高光，只在光滑天空像素上出现。
	if (hit) is_sky = OMNI_REFLECTION_IS_SKY(screen_pos); // 主世界按材质编号区分天空。
	if (is_sky && surface.is_smooth && media.highlight_strength > 0.0) highlight = OMNI_REFLECTION_SKY_HIGHLIGHT(surface.normal, surface.view_dir) * media.highlight_strength; // 光滑天空像素加太阳高光。
	if (!hit) { // 没命中时用天空回退。
		if (media.total_reflection) { // 全反射时直接取当前场景色。
			reflection = media.current_color;
		} else if (media.sky_enabled && !media.underwater && media.skylight > 0.0) { // 空中且有一定天光时才用天空。
			reflection = OMNI_REFLECTION_SKY(ray_world_dir, surface.is_smooth); // 取天空颜色。
			float falloff = media.sky_uses_facing ? ogxReflectionSkyFacing(surface.normal_up) : 1.0; // 朝上的面接更多天空。
			if (media.sky_uses_skylight) falloff *= media.skylight; // 按天光衰减。
			reflection *= falloff; // 衰减天空反射。
			highlight *= falloff; // 高光同样衰减。
		}
	}
	reflection += media.highlight_color * highlight; // 叠加直射高光。
	float hit_dist = surface.is_smooth ? 0.0 : 1.0; // 光滑面视作镜面，粗糙面命中后按空气段改写。
	if (media.voxel_enabled && !hit && !media.total_reflection && !media.underwater) { // 屏幕空间没命中时再用体素补一次。
		vec3 voxel_hit_world; // 体素命中的相机相对世界位置。
		vec4 voxel_hit = OMNI_REFLECTION_VOXEL(surface.world_pos, ray_world_dir, surface.normal, voxel_hit_world); // 世界空间追踪体素图。
		if (voxel_hit.a >= 0.0) { // `a` 不为负就是命中。
			reflection = voxel_hit.rgb; // 用体素里存下的方块颜色作为反射。
			hit = true; // 当作命中几何。
			is_sky = false; // 命中的不是天空。
			hit_dist = voxel_hit.a; // 归一化命中距离。
			screen_pos = OMNI_REFLECTION_SCREEN_POS(mat3(trace.model_view) * voxel_hit_world, trace.projection); // 把命中点投回屏幕。
		}
	}
	float surface_dist = length(surface.view_pos); // 表面到相机的距离。
	float air_length = media.open_length - surface_dist; // 没命中时按净空总距离估空气段。
	if (hit && !is_sky) air_length = ReflectionHitLength(surface.view_pos, screen_pos, OMNI_REFLECTION_HIT_DEPTH(screen_pos), trace.projection_inverse); // 命中实心几何时按命中点算空气段。
	if (hit && !surface.is_smooth) { // 粗糙面把空气段换成滤波用的命中距离。
		float dist_for_hit = media.hit_dist_uses_total ? air_length + surface_dist : air_length; // 下界把表面距离也算进去。
		hit_dist = ogxSaturate(max(dist_for_hit * 2.0, 3.0 * surface.roughness)); // 距离越远、表面越粗糙，滤波半径越大。
	}
	float fog_air = max(min(min(air_length + surface_dist, media.far_distance), media.cap_distance) - surface_dist, 0.0); // 雾段裁到可视范围。
	if (media.fog_color_enabled && (!media.fog_color_needs_length || fog_air > 0.0)) reflection += OMNI_REFLECTION_FOG_COLOR(surface_dist, fog_air, ray_world_dir, is_sky) / media.output_factor; // 下界末地补解析雾。
	if (media.fog_volume_enabled) { // 主世界补地表散射与体积雾。
		float fog_skylight = media.underwater ? 1.0 : media.skylight; // 水下天光按满值。
		if (fog_skylight > 0.0 && fog_air > 0.0) { // 有天光且有空气段才补雾。
			vec3 lit = reflection * media.output_factor; // 换到管线线性单位。
			vec3 fogged = OMNI_REFLECTION_FOG_VOLUME(lit, surface.world_pos, surface.world_pos + ray_world_dir * fog_air, ray_world_dir, fog_air, is_sky); // 在副本上补散射。
			reflection = mix(reflection, fogged / media.output_factor, fog_skylight); // 按天光在原色与补雾色之间混合。
		}
	}
	return vec4(LinearToCurve(reflection), hit_dist); // 曲线编码后与命中距离一起返回。
}

// 追踪输入：深度图、投影与质量选项只在这里选一次，三个维度共用。
ReflectionTrace OmniReflectionTrace(){
	ReflectionTrace trace; // 待填的追踪参数。
	#ifdef DISTANT_HORIZONS // 有远景时才接远景深度与逆投影。
		trace.dh_projection_inverse = dhProjectionInverse; // 远景逆投影。
		trace.has_dh = true; // 有远景模组。
		#if OMNI_DH_SSR
			trace.dh_ssr = true; // 允许反射命中远景。
		#else
			trace.dh_ssr = false; // 远景按天空处理。
		#endif
	#else
		trace.dh_projection_inverse = gbufferProjectionInverse; // 占位逆投影。
		trace.has_dh = false; // 没有远景模组。
		trace.dh_ssr = false; // 没有远景反射。
	#endif
	#if MC_VERSION >= 11605 // 一点一六点五以后手部有单独深度。
		trace.hand_supported = true; // 支持手部深度。
	#else
		trace.hand_supported = false; // 没有手部深度。
	#endif
	trace.projection = gbufferProjection; // 近景投影。
	trace.projection_inverse = gbufferProjectionInverse; // 近景逆投影。
	trace.model_view = gbufferModelView; // 视空间转相机相对世界空间。
	trace.model_view_inverse = gbufferModelViewInverse; // 相机相对世界空间转视空间。
	trace.near_plane = near; // 近裁剪面距离。
	trace.quality = int(OMNI_RAYTRACE_QUALITY); // 步进质量。
	trace.refinement_steps = int(OMNI_RAYTRACE_REFINEMENT_STEPS); // 细化步数。
	trace.z_diff_threshold = OMNI_RAYTRACE_ZDIFF_THRESHOLD; // 深度差阈值。
	return trace;
}

// 反射表面：把调用方已有的几何量装进通用库结构，三个维度共用。
ReflectionSurface OmniReflectionSurface(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float depth, float roughness, bool isHand, bool isSmooth){
	ReflectionSurface surface; // 待填的表面。
	surface.view_pos = viewPos; // 视空间表面位置。
	surface.world_pos = worldPos; // 相机相对世界位置。
	surface.view_dir = viewDir; // 视线方向。
	surface.normal = normal; // 表面法线。
	#ifdef DISTANT_HORIZONS
		surface.screen_pos = ScreenPos_From_ViewPos(viewPos); // 有远景时按投影还原屏幕坐标，保证与深度同源。
	#else
		surface.screen_pos = vec3(texCoord, depth); // 没有远景时直接用当前像素坐标与深度。
	#endif
	surface.roughness = roughness; // 材质粗糙度。
	surface.normal_up = dot(normal, gbufferModelView[1].xyz); // 法线朝上的分量，天空回退按它衰减。
	surface.is_hand = isHand; // 手部像素。
	surface.is_smooth = isSmooth; // 光滑面标记。
	return surface;
}

// 反射合成参数：通用库给出中性默认值，本函数只把管线换算接过去。
ReflectionMedia OmniReflectionMedia(vec3 currentColor, vec3 highlightColor, float skylight, float highlightStrength, bool totalReflection, bool underwater){
	return ReflectionMediaDefault(currentColor, highlightColor, skylight, highlightStrength, totalReflection, underwater, MAIN_OUTPUT_FACTOR); // 默认结构在通用库。
}

// --- 三个维度的反射入口：只填结构并调用一次通用流程，算法都在 `gfx/reflection.glsl` ---
#if defined OMNI_NETHER
// 下界反射：没有天空盒回退，命中取屏幕颜色、没命中留黑，再叠一段 `NetherFog`（来自 `world-1/composite2.fsh`）。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记，下界不使用。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif
	ReflectionSurface surface = OmniReflectionSurface(viewPos, worldPos, viewDir, normal, gbufferdepth, material.roughness, isHand, isSmooth); // 表面输入。
	ReflectionMedia media = OmniReflectionMedia(vec3(0.0), vec3(0.0), skylight, 0.0, totalInternalReflection, isEyeInWater != 0); // 合成参数。
	media.open_length = 80.0; // 没命中时按八十米净空估雾段。
	media.hit_dist_uses_total = true; // 下界命中距离把表面距离也算进去。
	media.fog_color_enabled = true; // 补一段下界雾。
	return SpecularReflections(surface, OmniReflectionTrace(), media, noise, depthtex1, depthtex2, OMNI_REFLECTION_DH_DEPTH, colortex1); // 一次调用完成追踪与着色。
}
#elif defined OMNI_END
// 末地反射：天空盒回退换成末地天空，命中距离那段补 `EndFog`（来自 `world1/composite2.fsh`）。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif
	ReflectionSurface surface = OmniReflectionSurface(viewPos, worldPos, viewDir, normal, gbufferdepth, material.roughness, isHand, isSmooth); // 表面输入。
	ReflectionMedia media = OmniReflectionMedia(CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb), vec3(0.0), 1.0, 0.0, totalInternalReflection, isEyeInWater != 0); // 合成参数。
	#ifdef DISTANT_HORIZONS
		media.far_distance = clamp(dhFarPlane, 1024.0, 2048.0); // 有远景时把远裁剪面夹在合理范围。
	#else
		media.far_distance = max(far * 1.2, 1024.0); // 否则用近景远裁剪面。
	#endif
	media.cap_distance = 512.0; // 末地雾最多补到五百一十二米。
	media.sky_enabled = true; // 没命中时用末地天空兜底。
	media.sky_uses_facing = true; // 朝上的面接更多天空。
	media.fog_color_enabled = true; // 补一段末地雾。
	media.fog_color_needs_length = true; // 有空气段才补雾。
	return SpecularReflections(surface, OmniReflectionTrace(), media, noise, depthtex1, depthtex2, OMNI_REFLECTION_DH_DEPTH, colortex1); // 一次调用完成追踪与着色。
}
#else
// 主世界反射：追踪反射方向，命中取屏幕颜色，没命中取天空回退，再叠反射里的体积雾与地表散射。
// 为什么全反射像素直接取当前场景色：发生全反射时表面看不到外面的东西，取自身颜色才不会出现黑洞。
vec4 CalculateSpecularReflections(vec3 viewPos, vec3 worldPos, vec3 viewDir, vec3 normal, float gbufferdepth, vec3 albedo, Material material, float skylight, bool isHand, bool isSmooth, float highlightStrength){
	bool totalInternalReflection = texelFetch(colortex1, texelCoord, 0).a > 0.5; // 全反射标记写在二号画面之外的一号画面 a 通道。
	#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的二维噪声。
	#else
		vec2 noise = BlueNoise(); // 固定二维噪声。
	#endif
	ReflectionSurface surface = OmniReflectionSurface(viewPos, worldPos, viewDir, normal, gbufferdepth, material.roughness, isHand, isSmooth); // 表面输入。
	#if defined OMNI_MOON_TEXTURE // 用月亮贴图时高光偏月光，否则偏当前直射光。
		vec3 highlightColor = colorSunlight; // 太阳高光。
	#else
		vec3 highlightColor = colorShadowlight; // 直射高光。
	#endif
	ReflectionMedia media = OmniReflectionMedia(CurveToLinear(texelFetch(colortex1, texelCoord, 0).rgb), highlightColor, smoothstep(0.3, 0.8, skylight), highlightStrength, totalInternalReflection, isEyeInWater != 0); // 合成参数。
	media.sky_enabled = true; // 没命中时用天空盒兜底。
	media.sky_uses_skylight = true; // 天空兜底按天光衰减。
	media.sky_uses_facing = true; // 朝上的面接更多天空。
	#if OMNI_VOXEL_REFLECTION && defined IRIS_FEATURE_CUSTOM_IMAGES // 屏幕空间没命中时再用体素反射补一次。
		media.voxel_enabled = true; // 开启体素回退。
	#endif
	#if (defined OMNI_LANDSCATTERING && (defined OMNI_LANDSCATTERING_REFLECTION || defined DISTANT_HORIZONS)) || (defined OMNI_VFOG && defined OMNI_VFOG_REFLECTION) // 反射里要不要补体积雾与地表散射。
		media.fog_volume_enabled = true; // 补散射与体积雾。
		#ifdef DISTANT_HORIZONS
			media.far_distance = max(float(dhRenderDistance), far) * 1.4; // 远景可视距离。
			#ifdef OMNI_DH_LIMIT_VFOG_DIST
				media.far_distance = min(2048.0, media.far_distance); // 限制雾距离上限。
			#endif
		#else
			media.far_distance = far * 1.4; // 没有远景时用近景远裁剪面估计。
		#endif
	#endif
	return SpecularReflections(surface, OmniReflectionTrace(), media, noise, depthtex1, depthtex2, OMNI_REFLECTION_DH_DEPTH, colortex1); // 一次调用完成追踪与着色。
}
#endif // 反射主函数分支结束。
#endif // composite2 段结束。

// --- composite5：把三号画面的反射合并进场景色 ---
#ifdef OMNI_COMPOSITE5_PASS
// 材质提供 `Material` 结构，反射合并要读它的金属度与反射强度。
#include "/effects/shared/surface.glsl"
// 反射合并使用通用库的菲涅耳与水吸收。
#include "/omni-gfx/reflection/reflection.glsl"

// 反射合并：把三号画面的反射按菲涅耳与金属度混合进底色。
// 输入是场景色、视线方向、法线、底色、水的吸收与材质；就地把反射混进场景色。
// 为什么主世界与下界末地共用一份签名：主世界给水吸收留权重，下界末地没有水吸收这一项，数值差异留在函数体内用 `OMNI_OVERWORLD` 分支处理，调用点保持同一个。
// 为什么用 `length(color)` 与 `length(reflection)` 再补一项：亮度差大时补一点反射，金属与高亮边缘不会突黑。
void CalculateSpecularReflections(inout vec3 color, vec3 viewDir, vec3 normal, vec3 albedo, float waterAbsorption, Material material){
	vec3 reflection = CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb); // 读三号画面的反射颜色并换回线性。
	#ifndef OMNI_NETHER // 下界没有全反射标记这一套。
		bool notTotalReflection = texelFetch(colortex1, texelCoord, 0).a < 0.5; // 一号画面 a 通道小于零点五表示不是全反射像素。
	#else
		bool notTotalReflection = true; // 下界没有全反射标记，一律按普通像素处理。
	#endif
	#ifdef OMNI_OVERWORLD
		const bool overworld = true; // 主世界按水吸收缩反射权重。
	#else
		const bool overworld = false; // 下界末地按反射权重混合。
	#endif
	ogxSpecularReflectionMix(color, viewDir, normal, albedo, waterAbsorption, reflection, notTotalReflection,
		material.metalness, material.roughness, material.f0, material.reflectionStrength, overworld); // 一次调用完成反射合并。
}
#endif // composite5 段结束。

#endif // OMNI_REFLECTION_SCREENSPACE_INCLUDED
