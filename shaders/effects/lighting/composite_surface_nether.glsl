/*
下界不透明表面光照：给下界的不透明表面算自发光底子、方块光与手持光，再乘底色，是 iterationT
`world-1/composite.fsh` 该段算法的一比一移植。
职责：读回表面数据，叠 `NetherLighting` 的自发光配色、可选地平线遮蔽、方块光与资源包自发光，最后编码写回一号画面。
调用位置：`effects/lighting/composite_surface.glsl` 在 `OMNI_NETHER` 分支引入本文件，绘制主体再调用 `CompositeSurfaceLighting();`。
可复制示例：`CompositeSurfaceLighting();`（要求调用方已提供 `texelCoord`、`texCoord`、光色 varying、
    `shadowtex0`、`shadowtex1`、`dhDepthTex1` 等全局量，见 `rendering/composite_shared.glsl`）。
设计原因与取舍：下界没有太阳，整段删去直射阳光、天光、全局光与阴影，只留 `NetherLighting` 的自发光配色；
    与主世界同用一个函数名，靠上级文件的分支二选一，拆出本文件只为让每个维度一份逻辑更短、更好找。
*/
#ifndef OMNI_COMPOSITE_SURFACE_NETHER_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COMPOSITE_SURFACE_NETHER_INCLUDED // 置上标记，后续再次引用直接跳过。

// 下界不透明表面光照：自发光底子加方块光与手持光，再乘底色（来自 `world-1/composite.fsh`）。
void CompositeSurfaceLighting(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。
	MaterialMask materialMaskSoild = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。

	FixParticleMask(materialMaskSoild, materialMask, gbuffer.depthL, gbuffer.depthW); // 薄粒子借不透明深度。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthL); // 还原不透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthL == 1.0){ // 天空像素改读远景深度。
			gbuffer.depthL = texelFetch(dhDepthTex1, texelCoord, 0).x; // 远景不含半透明深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthL); // 远景逆投影。
		}
	#endif

	vec3 viewDir = normalize(viewPos); // 视线方向。
	vec3 worldNormal = mat3(gbufferModelViewInverse) * gbuffer.normalL; // 法线转到世界空间。

	vec3 finalComposite = vec3(0.0); // 累积的下界表面颜色。

	if (materialMaskSoild.sky < 0.5){ // 只处理有几何的像素，天空留给下界雾色。
		finalComposite += NetherLighting() * (worldNormal.y * 0.25 + 1.0); // 按法线朝向叠下界自发光。

		float gi = 1.0; // 环境遮蔽，默认为一。
		#ifdef OMNI_GTAO
			if (materialMaskSoild.hand + materialMask.particle < 0.5) // 手与粒子不参与遮蔽。
				gi = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, gbuffer.normalL); // 算地平线遮蔽。
		#endif

		#ifdef OMNI_GTAO
			#ifdef OMNI_GTAO_MULTIBOUNCE
				vec3 ao = GTAOMultiBounce(gi, gbuffer.albedo); // 遮蔽做多弹射补偿。
			#else
				vec3 ao = vec3(gi); // 直接用遮蔽值。
			#endif
		#else
			vec3 ao = vec3(1.0); // 不开遮蔽时全亮。
		#endif

		finalComposite *= ao; // 遮蔽乘到颜色上。

		if(heldBlockLightValue + heldBlockLightValue2 > 0.0)
			finalComposite += HeldLighting(viewPos, viewDir, gbuffer.normalL, gbuffer.material.roughness, ao, materialMask.hand > 0.5); // 叠手持光源。
		finalComposite += BlockLighting(gbuffer.lightmapL.r, ao, materialMaskSoild); // 叠方块光。

		finalComposite *= mix(vec3(1.0), NetherFogColor().rgb, gbuffer.material.metalness * 0.7); // 金属面用雾色染色。
		finalComposite *= (1.0 - gbuffer.material.metalness * 0.75); // 非金属整体压一点。

		finalComposite += TextureLighting(gbuffer.albedo, gbuffer.lightmapL.r, gbuffer.material.emissiveness, materialMaskSoild); // 叠资源包自发光。

		finalComposite *= gbuffer.albedo; // 乘底色。

	}else{ // 天空像素交给合成五号的雾与泛光。
		finalComposite = vec3(0.0); // 清成黑色。
	}

	finalComposite /= MAIN_OUTPUT_FACTOR; // 换成管线亮度单位。
	finalComposite = LinearToCurve(finalComposite); // 四次方根编码。

	compositeOutput1 = vec4(finalComposite, 0.0); // 写回一号画面。
}
#endif // 文件守卫结束。
