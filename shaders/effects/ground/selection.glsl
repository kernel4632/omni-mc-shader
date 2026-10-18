/*
选择框：选择框与线条的固定颜色、命中时的颜色替换，以及线条程序的可选图像输出。
来源：`SelectionBox` 照 iterationT `Lib/BasicFounctions/VanillaComposite.glsl` 一比一移植，
  线条图像输出照 `Lib/Programs/Gbuffers/Line_FS_IMAGE.glsl` 一比一移植。
调用位置：
  合成阶段片元（合成五号）：`SelectionBox(color, gbuffer.albedo, materialMaskSoild.selection > 0.5 && isEyeInWater < 3);`
  线条与基础几何片元：用 `SelectionBoxColor()` 取配置颜色替换透明度为零点四的线条颜色；
  线条程序开启 `OMNI_LINE_IMAGE_OUTPUT` 时：调用 `SelectionLineImage` 把命中像素直接写进零号与五号画面。
可复制示例：
  `SelectionBox(color, gbuffer.albedo, mask.selection > 0.5);`
  `if (albedo.a == 0.4) albedo.rgb = SelectionBoxColor();`
  `SelectionLineImage(albedo);`
调用前提（iterationT 原样保留）：`SelectionBox` 依赖加载器输入里的 `colortex2`、`screenSize` 与曝光常数；
  `SelectionLineImage` 依赖调用方在引入本文件之前打开 `GL_ARB_shader_image_load_store` 扩展，
  它自己声明两张 `image2D`，只在 `OMNI_LINE_PASS` 的线条片元里编译，别的阶段即使打开同一选项也不会引用图像类型。
设计原因与取舍：选择框颜色只在这里定义一次，线条、基础几何与图像输出共用 `SelectionBoxColor()`，
  改名有分支时不会出现两处颜色不一致；选择框的曝光取自二号画面顶行的自动曝光统计，与画面曝光同步。
*/
#ifndef OMNI_SELECTION_INCLUDED // 只引入一次。
#define OMNI_SELECTION_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"选择框","en_us":"Selection & lines"}}
// @option {"label":{"zh_cn":"颜色-红","en_us":"Selection Box Color Red"},"description":{"zh_cn":"方块选择框的红色分量。","en_us":"Red part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_R 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"颜色-绿","en_us":"Selection Box Color Green"},"description":{"zh_cn":"方块选择框的绿色分量。","en_us":"Green part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_G 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"颜色-蓝","en_us":"Selection Box Color Blue"},"description":{"zh_cn":"方块选择框的蓝色分量。","en_us":"Blue part of the block selection box colour."},"slider":true}
#define OMNI_SELECTION_BOX_COLOR_B 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"禁用选择框深度写入","en_us":"Disable Selection Box Depth Writing"},"description":{"zh_cn":"让选择框不写深度，减少它引起的错误阴影；不兼容一点一八以下版本。","en_us":"Stops the selection box writing depth, reducing wrong shadows; not for versions below 1.18."}}
#define OMNI_LINE_IMAGE_OUTPUT 0 // [0 1]
// 选择框曝光与颜色打包都用共用数学，材质编号取自材质文件。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/effects/ground/material.glsl"
// 选择框颜色：把三个颜色分量组成一条固定颜色，线条与基础几何共用一份。
vec3 SelectionBoxColor(){
	return vec3(OMNI_SELECTION_BOX_COLOR_R, OMNI_SELECTION_BOX_COLOR_G, OMNI_SELECTION_BOX_COLOR_B); // 三个分量来自选项。
}
// 选择框上色：命中选择框时改用固定颜色，并按当前曝光线性化，颜色不会被曝光链路额外压暗。
// 调用前提：`colortex2` 与 `screenSize` 已在加载器输入中声明。
void SelectionBox(inout vec3 color, vec3 albedo, bool isSelection){
	if (isSelection){ // 只有选择框像素才处理。
		float exposure = CurveToLinear(texelFetch(colortex2, ivec2(0, screenSize.y - 1.0), 0).a) * (1500.0 / EXPOSURE_OUTPUT_FACTOR); // 取顶行自动曝光统计再换算成线性曝光。
		color = albedo * exposure; // 用自身底色乘曝光，得到与画面一致的亮度。
	}
}
// 线条图像输出：命中时直接把选择框颜色写进零号画面、把材质编号写进五号画面，不写深度。
// 两张 `image2D` 在这里声明，函数不接收图像：GLSL 不允许把两张不同格式的图传给同一个函数，
// 图像类型的函数参数又不能带格式限定符，所以只能由本文件直接写自己声明的这两张画面。
// 只在开启 `OMNI_LINE_IMAGE_OUTPUT` 的线条片元里编译；图像读写扩展由调用方在引入前打开。
#if OMNI_LINE_IMAGE_OUTPUT && defined OMNI_LINE_PASS && defined OMNI_FRAGMENT
layout(rgba8) uniform image2D colorimg0; // 零号画面，贴图色。
layout(rgba16) uniform image2D colorimg5; // 五号画面，材质编号。
void SelectionLineImage(vec4 albedo){
	if (albedo.a > 0.1 && gl_FragCoord.z < texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x){ // 只在线条挡在已有几何前面时才写。
		if (albedo.a == 0.4) albedo.rgb = SelectionBoxColor(); // 选择框用配置的固定颜色。
		imageStore(colorimg0, ivec2(gl_FragCoord.xy), vec4(albedo.rgb, 1.0)); // 写零号画面为不透明底色。
		imageStore(colorimg5, ivec2(gl_FragCoord.xy), vec4(0.0, 0.0, (MATID_SELECTION + 0.1) / 255.0, Pack2x8(vec2(0.0, 1.0)))); // 写五号画面的选择框材质编号。
	}
}
#endif // 线条图像输出结束。
#endif // 文件守卫结束。
