/*
效果文件 `effects/reflection/composite_specular.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/reflection/composite_specular.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_COMPOSITE_SPECULAR_INCLUDED
#define OMNI_COMPOSITE_SPECULAR_INCLUDED
/*
合成二号屏幕空间反射：按不透明表面材质追踪反射，未命中时回退天空盒，是 iterationT `composite2.fsh` 的算法体一比一移植。
职责：读回半透明表面数据与材质，算高光提示强度，调用 `CalculateSpecularReflections` 并把反射写进三号画面。
调用位置：`rendering/composite.glsl` 的 `OMNI_COMPOSITE2_PASS` 分支引入维度相关效果与反射文件后引入本文件，
    最后 `void main(){ CompositeScreenSpaceReflection(); }` 调用。
可复制示例：`CompositeScreenSpaceReflection();`（要求调用方已提供 `texelCoord`、`texCoord`、`shadowHighlightStrength`
    与 `colortex3` 等，见 `rendering/composite_shared.glsl`）。
设计原因与取舍：追踪算法在 `effects/reflection/reflection.glsl`，本文件只做本程序的输入输出与调用。
*/

// 屏幕空间反射：允许反射的表面才追踪，结果写进三号画面（来自 `composite2.fsh`）。
void CompositeScreenSpaceReflection(){
	GbufferData gbuffer = GetGbufferData(); // 读回本像素的完整表面数据。
	MaterialMask materialMaskSolid = CalculateMasks(gbuffer.materialIDL); // 不透明层材质掩码。
	MaterialMask materialMask = CalculateMasks(gbuffer.materialIDW); // 半透明层材质掩码。

	FixParticleMask(materialMaskSolid, materialMask); // 薄粒子修正。
	bool isSmooth = false; // 光滑面标记，由材质覆盖函数回填。
	ApplyMaterial(gbuffer.material, materialMask, isSmooth); // 水玻璃冰用写死材质。

	vec3 viewPos = ViewPos_From_ScreenPos(texCoord, gbuffer.depthW); // 半透明表面视空间位置。

	#ifdef DISTANT_HORIZONS
		if (gbuffer.depthW == 1.0){
			gbuffer.depthW = texelFetch(dhDepthTex0, texelCoord, 0).x; // 远景完整深度。
			viewPos = ViewPos_From_ScreenPos_DH(texCoord, gbuffer.depthW); // 远景逆投影。
		}
	#endif

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos; // 视空间转相机相对世界空间。
	vec3 viewDir = normalize(viewPos); // 视线方向。

	float highlightStrength = float((isEyeInWater != 1 || materialMask.water < 0.5) && gbuffer.lightmapW.g > 0.0) * shadowHighlightStrength; // 高光提示强度，水下水面归零。

	compositeOutput3 = vec4(0.0); // 默认没有反射。

	if (gbuffer.material.reflectionStrength > 0.0) // 只有允许反射的表面才追踪。
		compositeOutput3 = CalculateSpecularReflections(viewPos, worldPos, viewDir, gbuffer.normalW, gbuffer.depthW, gbuffer.albedo, gbuffer.material, gbuffer.lightmapW.g, materialMask.hand > 0.5, isSmooth, highlightStrength); // 追踪反射并回退天空盒。
}
// 参考签名兼容层：参考的反射合并直接读三号反射图与一号不透明度。
void CalculateSpecularReflections(inout vec3 color, vec3 viewDir, vec3 normal, vec3 albedo, Material material){
	vec3 reflection = CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb); // 三号画面存的是编码后的反射色。
	bool notTotal = texelFetch(colortex1, texelCoord, 0).a >= 0.5; // 一号透明度低于一半时走正常混合。
	ogxSpecularReflectionMix(color, viewDir, normal, albedo, 1.0, reflection, notTotal,
		material.metalness, material.roughness, material.f0, material.reflectionStrength, true);
}

#endif // OMNI_COMPOSITE_SPECULAR_INCLUDED
