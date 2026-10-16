/*
地形绘制主体（占位）：由乙片按 iterationT `Terrain_VS.glsl`、`Terrain_GS.glsl`、`Terrain_FS.glsl` 填充，现在只保证编译链接。
调用位置：各维度 `gbuffers_terrain` 的顶点、几何、片元入口定义阶段宏与 `OMNI_TERRAIN_PASS` 后引入。
可复制示例：入口写 `#define OMNI_GEOMETRY 1`、`#define OMNI_TERRAIN_PASS 1`，再引入本文件。
输出约定：零号贴图色、三号法线光照图、五号高光材质，对应 `DRAWBUFFERS:035`。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_TERRAIN_BODY_INCLUDED // 只引入一次。
#define OMNI_TERRAIN_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。
}
#endif // 顶点阶段结束。

#ifdef OMNI_GEOMETRY // 几何阶段：原程序在这里算贴图分辨率，占位只转发三角形。
layout(triangles) in; // 输入一个三角形。
layout(triangle_strip, max_vertices = 3) out; // 原样输出三个顶点。
void main(){
	for (int i = 0; i < 3; i++){ // 逐个顶点转发。
		gl_Position = gl_in[i].gl_Position; // 位置不变。
		EmitVertex(); // 发出顶点。
	}
	EndPrimitive(); // 结束三角形。
}
#endif // 几何阶段结束。

#ifdef OMNI_FRAGMENT // 片元阶段。
/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。
void main(){
	gbufferOutput0 = vec4(0.0); // 占位输出黑色。
	gbufferOutput3 = vec4(0.0); // 占位输出零。
	gbufferOutput5 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
