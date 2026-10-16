/*
实体绘制主体（占位）：由乙片按 iterationT `Entities_VS.glsl`、`Entities_FS.glsl` 填充，现在只保证编译链接。
调用位置：各维度 `gbuffers_entities`、`gbuffers_block`、`gbuffers_hand`、`gbuffers_spidereyes` 入口
定义阶段宏与 `OMNI_ENTITIES_PASS`、`OMNI_BLOCK_PASS`、`OMNI_HAND_PASS`、`OMNI_SPIDEREYES_PASS` 之一后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_HAND_PASS 1`，再引入本文件。
输出约定：四种程序都写零号、三号、五号，对应 `DRAWBUFFERS:035`。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_ENTITIES_BODY_INCLUDED // 只引入一次。
#define OMNI_ENTITIES_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。
}
#endif // 顶点阶段结束。

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
