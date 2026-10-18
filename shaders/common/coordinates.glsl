/*
坐标换算：照 iterationT `Lib/Uniform/GbufferTransforms.glsl` 一比一移植，屏幕、视空间与深度互相换算。
调用位置：绘制主体在 `common/uniforms.glsl`、`common/math.glsl` 和定义 `OMNI_TAA` 的
`effects/clarity/antialiasing.glsl` 之后引入本文件。
可复制示例：
    `vec3 viewPos = ViewPos_From_ScreenPos(texCoord, depth);`        还原视空间位置，自动撤销抖动
    `vec3 screenPos = ScreenPos_From_ViewPos(viewPos);`              投回屏幕，自动补上抖动
    `float d = LinearDepth_From_ScreenDepth(depth);`                 非线性深度换成米
设计原因与取舍：
    带 `_Raw` 的版本不处理抖动，用于已经撤销过抖动的坐标或不需要对齐历史的地方。
    原程序用 `TAA` 宏判断是否抖动，这里换成 Omni 选项名 `OMNI_TAA`；调用方必须先引入定义它的效果文件，
    否则这里看不到选项，会悄悄按“不抖动”计算，画面和历史对不上。
    远景版本的撤销抖动额外要求 `OMNI_DH_TAA_JITTER`（近景版本只看 `OMNI_TAA`）：远景顶点在
    `rendering/distant.glsl` 里按同一个开关决定是否抖动，两端口径必须一致，否则远景会整体偏半像素。
    远景版本只在加载远景模组时存在，函数名加 `_DH` 后缀，与原程序一致。
    相机速度在原程序四处各写一份且内容不同，按移植合同留在各自效果文件并改成用途名：
    `TaaCameraVelocity`、`GiCameraVelocity`、`MotionBlurCameraVelocity`，见偏离记录。
*/
#ifndef OMNI_COORDINATES_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_COORDINATES_INCLUDED // 置上标记。

// 投影矩阵与 `taaJitter` 都来自加载器输入声明，这里自己先引入，调用方不必记顺序。
#include "/common/uniforms.glsl"

// --- 近景：普通投影矩阵 ---
// 屏幕坐标与深度还原视空间位置；开启时间抗锯齿时先撤销本帧抖动。
vec3 ViewPos_From_ScreenPos(vec2 coord, float depth){
	#ifdef OMNI_TAA
		coord -= taaJitter * 0.5; // 抖动以负一到一为单位，换到零到一坐标要乘一半。
	#endif
	vec3 ndcPos = vec3(coord, depth) * 2.0 - 1.0; // 零到一转到负一到一。
	vec3 viewPos = vec3(vec2(gbufferProjectionInverse[0][0], gbufferProjectionInverse[1][1]) * ndcPos.xy, 0.0) + gbufferProjectionInverse[3].xyz; // 只用逆投影的非零项，比整矩阵乘法省。
	return viewPos / (gbufferProjectionInverse[2][3] * ndcPos.z + gbufferProjectionInverse[3][3]); // 透视除法。
}

// 同上但不撤销抖动。
vec3 ViewPos_From_ScreenPos_Raw(vec2 coord, float depth){
	vec3 ndcPos = vec3(coord, depth) * 2.0 - 1.0; // 零到一转到负一到一。
	vec3 viewPos = vec3(vec2(gbufferProjectionInverse[0][0], gbufferProjectionInverse[1][1]) * ndcPos.xy, 0.0) + gbufferProjectionInverse[3].xyz; // 逆投影的非零项。
	return viewPos / (gbufferProjectionInverse[2][3] * ndcPos.z + gbufferProjectionInverse[3][3]); // 透视除法。
}

// 视空间位置投到屏幕，返回零到一的坐标和深度；开启时间抗锯齿时补上抖动。
vec3 ScreenPos_From_ViewPos(vec3 viewPos){
	vec3 screenPos = vec3(gbufferProjection[0][0], gbufferProjection[1][1], gbufferProjection[2][2]) * viewPos + gbufferProjection[3].xyz; // 投影矩阵的非零项。
	screenPos = screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
	#ifdef OMNI_TAA
		screenPos.xy += taaJitter * 0.5; // 与几何阶段的抖动对齐。
	#endif
	return screenPos; // 屏幕坐标与深度。
}

// 同上但不补抖动。
vec3 ScreenPos_From_ViewPos_Raw(vec3 viewPos){
	vec3 screenPos = vec3(gbufferProjection[0][0], gbufferProjection[1][1], gbufferProjection[2][2]) * viewPos + gbufferProjection[3].xyz; // 投影矩阵的非零项。
	return screenPos * (0.5 / -viewPos.z) + 0.5; // 透视除法并转到零到一。
}

// 非线性屏幕深度换成到相机的米制距离。
float LinearDepth_From_ScreenDepth(float depth){
	depth = depth * 2.0 - 1.0; // 零到一转到负一到一。
	return 1.0 / (depth * gbufferProjectionInverse[2][3] + gbufferProjectionInverse[3][3]); // 逆投影的深度部分。
}

// 米制距离换回非线性屏幕深度，与上面互逆。
float ScreenDepth_From_LinearDepth(float depth){
	depth = (1.0 / depth - gbufferProjectionInverse[3][3]) / gbufferProjectionInverse[2][3]; // 解出负一到一深度。
	return depth * 0.5 + 0.5; // 转回零到一。
}

// --- 远景：远景模组自己的投影矩阵 ---
#ifdef DISTANT_HORIZONS

	// 远景版的屏幕到视空间，远景裁剪面不同，必须用远景逆投影。
	vec3 ViewPos_From_ScreenPos_DH(vec2 coord, float depth){
		#if defined(OMNI_TAA) && OMNI_DH_TAA_JITTER // 远景顶点抖过才撤销；关掉远景抖动时远景像素本就落在真实位置。
			coord -= taaJitter * 0.5; // 撤销本帧抖动。
		#endif
		vec3 ndcPos = vec3(coord, depth) * 2.0 - 1.0; // 零到一转到负一到一。
		vec4 viewPos = dhProjectionInverse * vec4(ndcPos, 1.0); // 远景逆投影整矩阵乘法。
		return viewPos.xyz / viewPos.w; // 透视除法。
	}

	// 远景版，不撤销抖动。
	vec3 ViewPos_From_ScreenPos_Raw_DH(vec2 coord, float depth){
		vec3 ndcPos = vec3(coord, depth) * 2.0 - 1.0; // 零到一转到负一到一。
		vec4 viewPos = dhProjectionInverse * vec4(ndcPos, 1.0); // 远景逆投影。
		return viewPos.xyz / viewPos.w; // 透视除法。
	}

	// 远景深度换成米制距离。
	float LinearDepth_From_ScreenDepth_DH(float depth){
		depth = depth * 2.0 - 1.0; // 零到一转到负一到一。
		return 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 远景逆投影的深度部分。
	}

	// 远景深度换算成同一距离在近景投影下的深度，远近两种深度才能直接比较。
	float ScreenDepth_From_DHScreenDepth(float depth){
		depth = depth * 2.0 - 1.0; // 远景深度转到负一到一。
		depth = 1.0 / (depth * dhProjectionInverse[2][3] + dhProjectionInverse[3][3]); // 先换成米。
		depth = (1.0 / depth - gbufferProjectionInverse[3][3]) / gbufferProjectionInverse[2][3]; // 再用近景投影换回深度。
		return depth * 0.5 + 0.5; // 转回零到一。
	}

#endif // 远景函数结束。
#endif // 文件守卫结束。
