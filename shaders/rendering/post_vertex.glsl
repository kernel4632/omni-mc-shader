/*
后期程序的整屏顶点：把加载器给的零到一四边形按程序需要的比例缩放。
调用位置：由 `rendering/post_pass6.glsl` 到 `post_pass15.glsl` 的顶点阶段引入；本文件不写 `#version`，语言版本由入口声明。
可复制示例：
    入口先写 `#define POST_VERTEX_SCALE 0.51` 再引入本文件，得到半分辨率整屏四边形；
    不写缩放宏时默认铺满屏幕。
设计原因与取舍：这些后期程序原来各写一份相同的 `main()`，只差缩放比例；
    比例由调用方的 `POST_VERTEX_SCALE` 给出，可以是单个浮点数，也可以是横纵不同的 `vec2`；
    投影公式只保留一处，避免十份顶点各自漂移。放大程序的深度补偿是独有逻辑，仍留在自己的文件里。
*/
#ifndef OMNI_POST_VERTEX_INCLUDED
#define OMNI_POST_VERTEX_INCLUDED

#ifdef OMNI_VERTEX
	#ifndef POST_VERTEX_SCALE
		#define POST_VERTEX_SCALE 1.0 // 默认铺满屏幕。
	#endif
	void main(){
		vec2 texCoord = gl_Vertex.xy * POST_VERTEX_SCALE; // 加载器顶点在零到一的方块上，按程序比例缩放。
		gl_Position = vec4(texCoord * 2.0 - 1.0, 0.0, 1.0); // 缩放后的整屏四边形。
	}
#endif

#endif // 文件守卫结束。
