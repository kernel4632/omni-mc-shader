/*
后期共享声明：`composite6` 到 `composite16` 各程序与它们引入的效果文件共用的片元全局量，全项目只在这里声明一次。
调用位置：`rendering/post.glsl` 的每个片元程序块，在本程序的效果文件与算法体之前引入本文件。
可复制示例：效果文件直接使用 `texelCoord`、`texCoord`、光色全局量与 `shadowtex0` 等采样器，不需要自己再声明。
设计原因与取舍：
    原程序一个后期程序一个文件，各文件重复声明这同一批全局量，改一个类型要同时改多处；这里收成一份。
    这些量在后期程序里是普通全局量，不是顶点传下来的 `in`：后期顶点阶段只输出整屏三角形，不传光色，
    声明它们只为让引入的效果文件整段可编译；本程序真正用到的才参与计算，未用到的会被编译器优化掉。
    `shadowtex1` 在后期各程序都按普通深度贴图读，不随程序变类型，所以一并放在这里。
    八号画面的三维与二维选择由 `rendering/post.glsl` 在引入加载器输入前打开 `COLORTEX8_2D` 决定，不属于本文件。
*/
#ifndef OMNI_POST_SHARED_INCLUDED // 只引入一次，避免全局量与采样器重复声明。
#define OMNI_POST_SHARED_INCLUDED // 置上标记，后续再次引用直接跳过。

#ifdef OMNI_FRAGMENT // 只有片元阶段需要；顶点阶段只做整屏四边形缩放。
	// 加载器输入与共用数学：`gl_FragCoord`、画面尺寸、时间、采样器与颜色曲线。
	#include "/common/uniforms.glsl"
	#include "/common/math.glsl"
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标，读回各号画面用。
	vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标，重投影与模糊的输入。
	vec2 sunCoord; // 太阳在屏幕上的位置；只被镜头光斑函数引用，本程序不调用，声明成空全局。
	vec3 worldShadowVector; // 阴影相机对应的世界光方向；云影与阴影查询引用。
	vec3 shadowVector; // 上面那个方向在视空间的值。
	vec3 worldSunVector; // 太阳的世界方向。
	vec3 worldMoonVector; // 月亮的世界方向。
	vec3 colorShadowlight; // 日月直射光色之和。
	vec3 colorSunlight; // 太阳直射光色，镜头光斑按它染色。
	vec3 colorMoonlight; // 月亮直射光色。
	vec3 colorSkylight; // 日月环境光色之和。
	vec3 colorSunSkylight; // 太阳一侧的环境光色。
	vec3 colorMoonSkylight; // 月亮一侧的环境光色。
	vec3 colorTorchlight; // 火把光色。
	float timeNoon; // 太阳高度因子。
	float timeMidnight; // 月亮高度因子。
	float sunVisibility; // 太阳可见度；只被镜头光斑函数引用，本程序不调用，声明成空全局。
	uniform sampler2D shadowtex0; // 阴影遮挡图，被引入的阴影查询函数引用。
	uniform sampler2D shadowtex1; // 阴影实心图，被引入的阴影查询函数引用。
	uniform sampler2D shadowcolor0; // 阴影颜色图。
	uniform sampler2D shadowcolor1; // 阴影法线天光图。
	uniform sampler2D gaux1; // 第一张涟漪动画贴图，雨点涟漪函数引用。
	uniform sampler2D gaux2; // 第二张涟漪动画贴图。
	uniform sampler2D gaux3; // 第三张涟漪动画贴图。
	uniform float rainStrength; // 降雨强度，雨点涟漪函数引用。
	#ifdef OMNI_NETHER // 下界泛光按群系调整，需要这几个群系平滑量。
		uniform float BiomeNetherWastesSmooth; // 下界荒地群系平滑量。
		uniform float BiomeSoulSandValleySmooth; // 灵魂沙峡谷群系平滑量。
		uniform float BiomeCrimsonForestSmooth; // 绯红森林群系平滑量。
		uniform float BiomeWarpedForestSmooth; // 诡异森林群系平滑量。
		uniform float BiomeBasaltDeltasSmooth; // 玄武岩三角洲群系平滑量。
	#endif
#endif // 片元阶段声明结束。
#endif // 文件守卫结束。
