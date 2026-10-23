/*
后期共用的程序主体：景深、两级泛光降采样、横纵模糊与合并泛光原本各占一个文件，流程完全相同。
调用位置：`rendering/programs.json` 把 `composite6`、`composite9` 到 `composite13` 都指向本文件；
    每个入口自己定义对应的 `OMNI_COMPOSITE*_PASS` 宏，本文件只展开那一支。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE11_PASS 1` 再引入本文件。
设计原因与取舍：六支程序的顶点缩放、输出画面与一次效果调用不同，其余整屏顶点、共用片元依赖与
    输出声明逐字相同；合并后这些公共行只写一次，效果算法仍在 `effects/`，调用顺序不变。
    缩放宏必须在引入 `post_vertex.glsl` 之前定义，所以按程序宏先选缩放值。
*/
#ifndef OMNI_POST_BODY_INCLUDED // 只展开一次，避免 `main()` 与输出变量重复定义。
#define OMNI_POST_BODY_INCLUDED // 置上标记。

// 加载器输入：顶点与片元都要用屏幕尺寸与内部渲染质量。
#include "/common/uniforms.glsl"

// 每个程序按自己的降采样比例缩放整屏顶点；景深用原分辨率。
#if defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE13_PASS
	#define POST_VERTEX_SCALE 0.51 // 一半边长，对应四分之一像素数。
#elif defined OMNI_COMPOSITE10_PASS
	#define POST_VERTEX_SCALE 0.255 // 四分之一步长，对应十六分之一像素数。
#elif defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS
	#define POST_VERTEX_SCALE vec2(0.6, 0.255) // 横向留出模糊半径，纵向四分之一。
#endif
// 整屏顶点只写一次，默认铺满屏幕。
#include "/rendering/post_vertex.glsl"

#if defined OMNI_FRAGMENT // 只有片元阶段写画面。

	// 后期共用依赖按固定顺序引入一次：颜色、镜头、泛光与景深。
	#include "/rendering/post_fragment_deps.glsl"

	// 景深写一号；泛光链写五号。
	#if defined OMNI_COMPOSITE6_PASS
		/* DRAWBUFFERS:1 */
		layout(location = 0) out vec4 compositeOutput1; // 一号景深后的场景颜色。
		void main(){
			#ifdef OMNI_DOF // 只有开启景深才写一号，关闭时保持上一阶段结果。
				compositeOutput1 = DepthOfField(); // 按弥散半径散焦合成。
			#endif
		}
	#else
		/* DRAWBUFFERS:5 */
		layout(location = 0) out vec4 compositeOutput5; // 五号泛光链画面。
		void main(){
			#if defined OMNI_COMPOSITE9_PASS
				compositeOutput5 = BloomDownSampleScene(); // 从场景亮度开始第一级降采样。
			#elif defined OMNI_COMPOSITE10_PASS
				compositeOutput5 = BloomDownSampleChain(); // 继续降采样。
			#elif defined OMNI_COMPOSITE11_PASS
				compositeOutput5 = BloomBlurHorizontal(); // 横向高斯模糊。
			#elif defined OMNI_COMPOSITE12_PASS
				compositeOutput5 = BloomBlurVertical(); // 纵向高斯模糊。
			#elif defined OMNI_COMPOSITE13_PASS
				compositeOutput5 = BloomCombine(); // 合并各级泛光。
			#else
				compositeOutput5 = vec4(0.0); // 未登记的程序保持空输出，正常流程不会走到。
			#endif
		}
	#endif

#endif // 片元阶段结束。
#endif // 文件守卫结束。
