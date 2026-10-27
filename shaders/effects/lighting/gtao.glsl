/*
效果文件 `effects/lighting/gtao.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lighting/gtao.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_GTAO_INCLUDED
#define OMNI_GTAO_INCLUDED
/*
地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重，并做多弹射补偿。
来源 iterationT 地面真相环境遮蔽段。
调用位置：由 `effects/lighting/ambient.glsl` 引入；延迟主体 `RenderGISpatialFilter` 调用 `GroundTruthBasedAmbientOcclusion`，
    合成阶段调用 `GTAOMultiBounce` 给遮蔽补间接光。
可复制示例：
    `float ao = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal);`
    `vec3 aoColor = GTAOMultiBounce(gi.a, gbuffer.albedo);`
设计原因与取舍：遮蔽与全局光互相独立、开关也各自独立，拆成两个文件后可分别阅读和关闭。
*/
// 多弹射补偿放在通用库，这里只传入遮蔽与底色。
#include "/omni-gfx/gi.glsl"
// 地平线遮蔽：沿视线做多切片搜索最大地平线角，积分出半球被挡住的比重。
// 调用前提：`texCoord`、`gbufferProjection`、`depthtex1` 已声明；采样循环在通用库。
float GroundTruthBasedAmbientOcclusion(vec3 viewPos, vec3 viewDir, vec3 normal){
	#ifdef OMNI_TAA // 开时间抗锯齿时用逐帧噪声。
		vec2 noise = BlueNoiseTemporal(); // 每帧变化的蓝噪声。
	#else // 否则用空间噪声。
		vec2 noise = BlueNoise(); // 固定空间噪声。
	#endif
	OgxGtaoParams params; // 画质、半径与远景能力。
	params.steps = OMNI_GTAO_QUALITY; // 环绕视线的切片数。
	params.slice_steps = OMNI_GTAO_SLICE_QUALITY; // 每个切片的搜索步数。
	params.falloff_start = OMNI_GTAO_FALLOFF_START; // 衰减起点。
	params.max_sample_radius = OMNI_GTAO_MAX_RADIUS; // 屏幕半径上限。
	params.world_radius = OMNI_GTAO_WORLD_RADIUS; // 世界半径。
	params.screen_radius = OMNI_GTAO_SCREEN_RADIUS; // 屏幕半径。
	params.strength = OMNI_GTAO_STRENGTH; // 遮蔽强度。
	params.radius_mode = OMNI_GTAO_RADIUS_MODE; // 半径模式。
	#ifdef GTAO_FALLOFF_Z_OFFSET // 可选的深度加权开关。
		params.falloff_z_offset = true; // 用深度加权距离。
	#else
		params.falloff_z_offset = false; // 按普通距离加权。
	#endif
	#ifdef DISTANT_HORIZONS // 有远景时多两张输入。
		params.has_dh = true; // 标记有远景深度。
		#if OMNI_DH_AO // 只有开启远景遮蔽才把远景样本当作遮挡物。
			params.dh_ao = true; // 天空样本改读远景。
		#else
			params.dh_ao = false; // 天空样本不产生遮挡。
		#endif
		return ogxGroundTruthAo(viewPos, viewDir, normal, texCoord, aspectRatio, depthtex1, dhDepthTex0,
			gbufferProjection, gbufferProjectionInverse, dhProjectionInverse, params, noise); // 一次调用完成全部切片。
	#else // 没有远景时用近景深度占位。
		params.has_dh = false; // 没有远景深度。
		params.dh_ao = false; // 不启用远景遮蔽。
		return ogxGroundTruthAo(viewPos, viewDir, normal, texCoord, aspectRatio, depthtex1, depthtex1,
			gbufferProjection, gbufferProjectionInverse, gbufferProjectionInverse, params, noise); // 一次调用完成全部切片。
	#endif
}
// 遮蔽多弹射：按表面底色给遮蔽补一层间接光，深色表面补得少，避免暗部压死。
vec3 GTAOMultiBounce(float ao, vec3 albedo){
	return ogxAoMultiBounce(ao, albedo); // 转发到通用库。
}

#endif // OMNI_GTAO_INCLUDED
