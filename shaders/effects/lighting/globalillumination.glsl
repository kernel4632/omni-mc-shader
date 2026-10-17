/*
全局光空间滤波：按像素法线与深度做半球采样，算出一号画面的全局光颜色与地平线遮蔽。
调用位置：`rendering/deferred.glsl` 的延迟二号（主世界）与延迟四号（末地）片元分支引入本文件；
    这两个程序的片元 `main()` 取各自深度图的起始深度，调用 `RenderGISpatialFilter()` 写一号画面。
可复制示例：
    `deferredOutput1 = RenderGISpatialFilter(texelFetch(depthtex1, texelCoord, 0).x);`  主世界延迟二号用不含半透明的深度起算。
    `deferredOutput1 = RenderGISpatialFilter(texelFetch(depthtex0, texelCoord, 0).x);`  末地延迟四号用含半透明的深度起算。
调用前提：调用方必须先声明 `texelCoord`、`texCoord`，并引入 `common/coordinates.glsl`（`ViewPos_From_ScreenPos`）、
    `common/math.glsl`（`DecodeNormal`）与 `effects/lighting/sunlight.glsl`（带入 `GroundTruthBasedAmbientOcclusion` 与 `GI_SpatialFilter`）。
设计原因与取舍：
    主世界延迟二号和末地延迟四号的主体逐行相同，只有起始深度取自哪张深度图不同；
    把起始深度作为参数传入，两个程序就共用同一段算法，也不必按程序宏在函数内隐藏分派，接手者能一眼看出差别只在传参。
    这里的常量与公式来自 iterationT 的 `deferred2`（主世界）与 `world1/deferred4`（末地），逐行保持一致。
*/
#ifndef OMNI_GLOBALILLUMINATION_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_GLOBALILLUMINATION_INCLUDED

// --- 延迟二号（主世界）、延迟四号（末地）片元主体 ---
// 输入起始深度，返回一号画面的内容：有几何的像素算遮蔽与全局光，天空像素保持无全局光、遮蔽为一。
vec4 RenderGISpatialFilter(float startDepth){
	float depth = startDepth; // 本像素起始深度，由调用方按程序选择不含或含半透明的深度图。
	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth); // 还原视空间位置，自动撤销抖动。

	#ifdef DISTANT_HORIZONS // 有远景时天空像素改读远景深度。
		if (depth == 1.0){ // 天空像素改读远景深度。
			depth = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, depth); // 用远景逆投影还原。
		}
	#endif

	vec4 gi = vec4(0.0, 0.0, 0.0, 1.0); // 默认没有全局光，遮蔽为一。

	if (depth < 1.0){ // 有几何才算全局光与遮蔽。
		vec3 viewDir = normalize(viewPos); // 视线方向。
		vec3 normal = DecodeNormal(texelFetch(colortex3, texelCoord, 0).xy); // 从三号画面解出法线。

		#ifdef OMNI_GTAO // 打开地平线遮蔽才算。
			if (-viewPos.z > 0.15) gi.a = GroundTruthBasedAmbientOcclusion(viewPos, -viewDir, normal); // 太近的像素不算遮蔽。
		#endif

		#ifdef OMNI_GI_RSM // 打开全局光反弹才算。
			gi.rgb = GI_SpatialFilter(-viewPos.z, normal, viewDir); // 半分辨率全局光做空间滤波。
		#endif
	}

	return gi; // 返回一号画面的内容。
}
#endif // 文件守卫结束。
