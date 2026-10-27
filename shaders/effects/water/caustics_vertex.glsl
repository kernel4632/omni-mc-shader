/*
效果文件 `effects/water/caustics_vertex.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/caustics_vertex.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_CAUSTICS_VERTEX_INCLUDED
#define OMNI_CAUSTICS_VERTEX_INCLUDED
/*
焦散法线方块的共用顶点：把延迟零号与延迟一号的整屏顶点缩放到焦散贴图分辨率。
调用位置：`rendering/deferred_pass0.glsl`、`deferred_pass1.glsl` 的 `OMNI_VERTEX` 段。
可复制示例：`#include "/effects/water/caustics_vertex.glsl"`。
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
