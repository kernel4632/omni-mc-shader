/*
阴影绘制主体（占位）：由乙片按 iterationT `Shadow_VS.glsl`、`Shadow_FS.glsl` 填充，现在只保证编译链接。
调用位置：各维度 `shadow`、`dh_shadow` 入口定义阶段宏与 `OMNI_SHADOW_PASS` 或 `OMNI_DH_SHADOW_PASS` 后引入。
可复制示例：入口写 `#define OMNI_VERTEX 1`、`#define OMNI_SHADOW_PASS 1`，再引入本文件。
输出约定：片元写 `shadowcolor0` 贴图色与 `shadowcolor1` 法线天空光，对应 `DRAWBUFFERS:01`。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_SHADOW_BODY_INCLUDED // 只引入一次。
#define OMNI_SHADOW_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的阴影矩阵直接变换顶点。
}
#endif // 顶点阶段结束。

#ifdef OMNI_FRAGMENT // 片元阶段。
/* DRAWBUFFERS:01 */
layout(location = 0) out vec4 shadowOutput0; // 阴影颜色。
layout(location = 1) out vec4 shadowOutput1; // 阴影法线与天空光。
void main(){
	shadowOutput0 = vec4(0.0); // 占位输出黑色。
	shadowOutput1 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
