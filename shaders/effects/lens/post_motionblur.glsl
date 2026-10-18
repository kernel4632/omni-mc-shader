/*
后期动态模糊颜色：`composite8` 程序主世界部分里算出模糊后的场景颜色，并把镜头光斑叠回场景。
职责：开启动态模糊时按相机位移沿快门方向平均，否则取七号历史；主世界再把三号画面的镜头光斑按天空光衰减叠加。
调用位置：`rendering/post.glsl` 的 `OMNI_COMPOSITE8_PASS` 分支先引入共享声明与 `effects/lens/lens.glsl`，再引入本文件，
    最后在 `main()` 里 `LinearToCurve(MotionBlurSceneColor())` 写进一号画面。
可复制示例：`vec3 color = MotionBlurSceneColor();`（要求调用方已提供 `texelCoord`、`colortex7`、`colortex3`）。
设计原因与取舍：模糊本身 `MotionBlur()` 在 `effects/lens/lens.glsl`，本文件只做程序级的选项分派与镜头光斑叠加，
    与原程序 `composite8.fsh` 的颜色段一比一对应；返回线性颜色，曲线编码与写出交给调用方，职责清楚。
*/
#ifndef OMNI_POST_MOTIONBLUR_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_POST_MOTIONBLUR_INCLUDED // 置上标记，后续再次引用直接跳过。

vec3 MotionBlurSceneColor(){
	#if OMNI_MOTION_BLUR // 开启动态模糊时按相机位移沿快门方向平均。
		vec3 color = MotionBlur(); // 返回模糊后的线性颜色。
	#else // 关闭时原样取历史画面。
		vec3 color = CurveToLinear(texelFetch(colortex7, texelCoord, 0).rgb); // 读七号画面线性颜色。
	#endif

	#ifdef OMNI_OVERWORLD // 主世界把镜头光斑叠回场景。
		#if OMNI_LENS_GLARE || OMNI_LENS_FLARE // 只在开了眩光或光斑时。
			color += CurveToLinear(texelFetch(colortex3, texelCoord, 0).rgb) * eyeBrightnessSmoothCurved; // 三号画面的光斑按天空光衰减叠加。
		#endif
	#endif

	return color; // 返回线性颜色，编码与写出由调用方负责。
}
#endif // 文件守卫结束。
