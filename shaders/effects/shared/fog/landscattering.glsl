/*
效果文件 `effects/shared/fog/landscattering.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/shared/fog/landscattering.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_LANDSCATTERING_INCLUDED
#define OMNI_LANDSCATTERING_INCLUDED
/*
地面大气散射：给地表方向的视线补一层空气散射，阴影区按选项削弱。
来源：iterationT `Lib/BasicFounctions/VanillaComposite.glsl` 的散射段一比一移植。
职责：`simpleScattering` 沿阳光取几段估光学厚度，`LandAtmosphericScattering` 把它加到画面。
调用位置：由 `effects/fog/fog.glsl` 引入；`rendering/composite.glsl` 的合成五号、`effects/water/water.glsl`
  的折射与 `effects/reflection/reflection.glsl` 的反射都调用 `LandAtmosphericScattering`。
可复制示例：`LandAtmosphericScattering(color, waterDist, vec3(0.0), rayWorldPos, worldDir, materialMask.sky > 0.5);`
调用前提：由 `effects/fog/fog.glsl` 引入，且已先引入 `common/math.glsl`、`effects/shadow/shadow.glsl`、
  `effects/sky/sky.glsl` 并声明相机与阴影相关全局量；本文件不重复引入。
关键设计原因与取舍：`LandAtmosphericScattering` 的调用点是加色，所以它就地改画面；阴影遮蔽与室内衰减都按开关折叠。
    瑞利与米氏相函数来自 `/omni-gfx/atmosphere.glsl`（由 Slang 源生成），公式和常数与旧 `gfx_` 实现一致；
    引入生成库不改变数值，只把公共算法收回唯一来源。
*/

// 生成库大气：相函数与密度剖面由 Slang 源生成，下面的散射计算改用同一份实现。
#include "/omni-gfx/atmosphere.glsl"

// 简化的单次散射：沿阳光方向取几段估光学厚度，算出这段空气加到视线上的散射色。
// 输入是相机、视线方向、散射距离、受光距离与光源方向；返回叠加的散射颜色。
// 四段累加与密度剖面在生成库，本文件只把当前大气常数填进结构体。
vec3 simpleScattering(vec3 camera, vec3 worldDir, float dist, float shadowDist, vec3 lightVector){
	return ogxAtmoSimpleScattering(omniAtmosphereModel(), camera, worldDir, dist, shadowDist, lightVector); // 实现在生成库。
}

// 地面大气散射：给地表方向的视线补一层空气散射，阴影区按选项削弱。
// 输入是待修改颜色、距离、起点、终点、世界方向与是否天空；就地把散射加到颜色里。
// 为什么把起点抬高到最低高度：贴地时大气几何退化，抬高保证散射计算稳定。
void LandAtmosphericScattering(inout vec3 color, in float dist, vec3 startPos, vec3 endPos, vec3 worldDir, bool isSky){
	float strength = max(OMNI_LANDSCATTERING_STRENGTH - float(isSky), 0.0); // 天空像素不重复加散射，强度减一。
	#ifdef OMNI_VFOG // 有体积雾时按白天缩放，避免和体积雾双重叠加。
		strength *= timeNoon;
	#endif
	#if !OMNI_INDOOR_FOG // 默认随天空光等级衰减。
		strength *= eyeBrightnessSmoothCurved;
	#endif

	if(strength > 0.001 && isEyeInWater == 0){ // 强度太低或不在空气中就不算。

		#ifdef OMNI_ATMO_HORIZON // 打开地平线时按选项高度算相机。
			vec3 camera = vec3(0.0, max(cameraPosition.y, ATMO_MIN_ALTITUDE) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 高度换成公里并加星球半径。
		#else
			vec3 camera = vec3(0.0, max(cameraPosition.y, 63.0) * 0.001 + atmosphereModel_bottom_radius, 0.0); // 默认按海平面高度。
		#endif

		float shadowDist = dist; // 受光的距离，默认等于总距离。

		#if OMNI_LANDSCATTERING_SHADOW // 打开阴影遮蔽时沿视线段查阴影图，按被挡的比例缩短受光距离。
			vec3 shadowStart = ShadowScreenPos_From_WorldPos(startPos + gbufferModelViewInverse[3].xyz); // 起点投到阴影图。
			vec3 shadowEnd = ShadowScreenPos_From_WorldPos(endPos + gbufferModelViewInverse[3].xyz); // 终点投到阴影图。

			#ifdef OMNI_TAA // 打开时间抗锯齿时用逐帧抖动。
				float noise = BayerTemporal();
			#else
				float noise = bayer64(gl_FragCoord.xy);
			#endif

			float occluded = ogxShadowSegmentOcclusion(shadowStart, shadowEnd, shadowtex0, int(OMNI_LANDSCATTERING_SHADOW_QUALITY),
				noise, OMNI_SHADOW_MAP_BIAS, length(endPos - startPos)); // 一次调用统计被挡住的米数。

			shadowDist = max(shadowDist - occluded, 0.0); // 按被挡比例缩短受光距离。
		#endif

		dist *= OMNI_LANDSCATTERING_DISTANCE; // 总距离乘距离倍率。
		shadowDist *= OMNI_LANDSCATTERING_DISTANCE; // 受光距离同样乘倍率。

		color += simpleScattering(camera, worldDir, dist, shadowDist, worldSunVector) // 算出这段空气的散射。
			   * (1.0 - wetness) // 雨天空气更均匀，去掉方向性散射。
			   * strength; // 乘最终强度。
	}
}
#endif // OMNI_LANDSCATTERING_INCLUDED
