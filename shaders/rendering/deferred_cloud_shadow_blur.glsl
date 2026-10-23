/*
延迟四号、五号的共用阶段：把云影贴图做横向或纵向高斯模糊，并保留末地把全局光空间滤波放在同一程序里的分支。
调用位置：由 `rendering/deferred_pass4.glsl` 与 `deferred_pass5.glsl` 引入；调用方先用 `CLOUD_SHADOW_BLUR_AXIS` 给出采样轴。
可复制示例：`#define CLOUD_SHADOW_BLUR_AXIS ivec2(1, 0)` 再引入本文件得到横向模糊；改成 `ivec2(0, 1)` 得到纵向模糊。
设计原因与取舍：两个程序原来逐行相同，只有采样轴不同；合并后轴成为唯一差异，
    顶点缩放、末地全局光分支与输出声明只维护一份，避免横纵两次模糊出现不一致。
*/
#ifndef OMNI_DEFERRED_CLOUD_SHADOW_BLUR_INCLUDED
#define OMNI_DEFERRED_CLOUD_SHADOW_BLUR_INCLUDED

#ifndef CLOUD_SHADOW_BLUR_AXIS
	#define CLOUD_SHADOW_BLUR_AXIS ivec2(1, 0) // 默认横向；调用方总会覆盖。
#endif

// 延迟三号、四号、五号在延迟阶段把四号六号画面换成三维云噪声，宏名照 iterationT 原名由程序自己打开。
// 末地的延迟四号是全局光空间滤波，不读云噪声，所以要把它排除在外。低分辨率体积云的延迟七号（算云）与
// 延迟八号（把云贴回天空，复用平面云与附加层函数）也要三维云噪声。
	#define COLORTEX_CLOUDNOISE 1 // 打开后四号六号声明成三维采样器。

// ================================ 顶点阶段 ================================
#ifdef OMNI_VERTEX

		// 云影模糊只作用在画面右上角的方贴图上，顶点把整屏四边形缩到那块方贴图的范围。
		vec3 worldShadowVector; // 云影效果文件里合成专用函数引用它；顶点阶段不调用那些函数。
		vec3 worldSunVector; // 云带入的天空效果文件里星空函数引用它；本阶段不调用，仅让文件可编译。
		#include "/bind/cloud/cloud.glsl"
		void main(){
			vec2 shadowTexSize = pixelSize * floor(min(screenSize.y * 0.45, OMNI_CLOUD_SHADOWTEX_SIZE)); // 方贴图占屏幕的比例。
			vec2 shadowTexCoord = gl_Vertex.xy; // 加载器顶点在零到一的方块上。
			shadowTexCoord = shadowTexCoord * shadowTexSize + (1.0 - shadowTexSize); // 缩到右上角方贴图的位置。
			gl_Position = vec4(shadowTexCoord * 2.0 - 1.0, 0.0, 1.0); // 铺满屏幕。
		}

#endif

// ================================ 片元阶段 ================================

#if defined OMNI_FRAGMENT
	#if defined OMNI_END
		// 末地把全局光空间滤波放到延迟四号（来自 `world1/deferred4.fsh`）：用含半透明的深度算遮蔽与空间滤波。
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 deferredOutput1; // 一号全局光与遮蔽。
		#include "/common/uniforms.glsl"
		#include "/common/math.glsl"
		// 提供材质编号，环境光与时间抗锯齿的速度重投影引用它。
		#include "/bind/ground/material.glsl"
		// 先定义 `OMNI_TAA`，坐标换算与遮蔽抖动要用。
		#include "/bind/clarity/antialiasing.glsl"
		ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
		vec2 texCoord = gl_FragCoord.xy * pixelSize; // 零到一屏幕坐标。
		vec3 worldShadowVector; // 阴影与天空文件引用它。
		vec3 shadowVector; // 屏幕空间阴影引用它。
		vec3 worldSunVector; // 天空与光照文件引用它。
		vec3 worldMoonVector; // 天空与光照文件引用它。
		vec3 colorShadowlight; // 日月直射光色之和。
		vec3 colorSunlight; // 太阳直射光色。
		vec3 colorMoonlight; // 月亮直射光色。
		vec3 colorSkylight; // 日月环境光色之和。
		vec3 colorSunSkylight; // 太阳一侧的环境光色。
		vec3 colorMoonSkylight; // 月亮一侧的环境光色。
		vec3 colorTorchlight; // 火把光色。
		float timeNoon; // 太阳高度因子。
		float timeMidnight; // 月亮高度因子。
		uniform sampler2D shadowtex0; // 阴影遮挡图。
		uniform sampler2D shadowtex1; // 阴影实心图。
		uniform sampler2D shadowcolor0; // 阴影颜色图。
		uniform sampler2D shadowcolor1; // 阴影法线天光图。
		#include "/common/coordinates.glsl"
		#include "/common/noise.glsl"
		// 提供阳光泄漏修正选项，并带入环境光与阴影文件（末地版阴影相机由 `OMNI_END` 选择）。
		#include "/bind/lighting/sunlight.glsl"
	// 全局光空间滤波的算法在 `effects/lighting/ambient.glsl`（上面经 `effects/lighting/sunlight.glsl` 引入），这里只取深度并写一号。
		void main(){
			deferredOutput1 = RenderGISpatialFilter(texelFetch(depthtex0, texelCoord, 0).x); // 末地用含半透明的深度做遮蔽与空间滤波。
		}
	#else // 主世界：云影横向与纵向模糊。
	/* DRAWBUFFERS:2 */
	layout(location = 0) out vec4 deferredOutput2; // 二号云影贴图。
	#include "/common/uniforms.glsl"
	ivec2 texelCoord = ivec2(gl_FragCoord.xy); // 整数像素坐标。
	vec3 worldShadowVector; // 云影效果文件里合成专用函数引用它；本程序不调用那些函数。
	vec3 worldSunVector; // 云带入的天空效果文件里星空函数引用它；本程序不调用，仅让文件可编译。
	// 提供 `CloudShadowAxialBlur`。
	#include "/bind/cloud/cloud.glsl"
	void main(){
			deferredOutput2 = CloudShadowAxialBlur(texelCoord, CLOUD_SHADOW_BLUR_AXIS); // 按调用方给的方向做高斯模糊。
	}
#endif
#endif

#endif // 文件守卫结束。
