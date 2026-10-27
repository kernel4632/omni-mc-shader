/*
阶段胶水 `rendering/caustics_vertex.glsl`：延迟零号与延迟一号共用的整屏顶点，负责把焦散贴图缩放到目标分辨率。
调用位置：`rendering/deferred_pass0.glsl`、`deferred_pass1.glsl` 的 `OMNI_VERTEX` 段。
可复制示例：`#include "/rendering/caustics_vertex.glsl"`，顶点阶段直接复用这两个函数。
设计原因与取舍：顶点缩放是阶段约定，不是水面效果的算法；放回 `rendering/` 后效果文件只保留焦散采样与选项。
*/
#ifndef OMNI_CAUSTICS_VERTEX_INCLUDED
#define OMNI_CAUSTICS_VERTEX_INCLUDED
/*
焦散法线方块的共用顶点：把延迟零号与延迟一号的整屏顶点缩放到焦散贴图分辨率。
调用位置：`rendering/deferred_pass0.glsl`、`deferred_pass1.glsl` 的 `OMNI_VERTEX` 段。
可复制示例：`#include "/rendering/caustics_vertex.glsl"`。
设计原因与取舍：两个程序都要把整屏四边形缩到左下角固定像素见方，原程序各写一份；
    集中后只保留一套屏幕比例换算，避免改分辨率时两边不一致。
*/
#ifdef OMNI_VERTEX // 只在顶点阶段提供 `main()`。

// 屏幕尺寸与焦散常量来自加载器声明。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// 整屏顶点：把零到一的四边形缩到焦散贴图需要的像素范围。
void main(){
	const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 贴图最大边长，限制高分辨率屏幕上的方块高度。
	vec2 causticsTexCoord = gl_Vertex.xy; // 加载器给的零到一顶点。
	causticsTexCoord *= screenSize * (1.0 / min(screenSize.y, maxCausticsNormalHeight)); // 按屏幕长宽比缩到目标方形。
	gl_Position = vec4(causticsTexCoord * 2.0 - 1.0, 0.0, 1.0); // 转回裁剪空间。
}

#endif // 顶点阶段结束。
#endif // OMNI_CAUSTICS_VERTEX_INCLUDED
