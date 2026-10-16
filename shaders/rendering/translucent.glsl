/*
半透明绘制主体（占位）：由乙片按 iterationT `Water_VS.glsl`、`Water_FS.glsl`、`Hand_Water_*.glsl` 填充，现在只保证编译链接。
调用位置：各维度 `gbuffers_water`、`gbuffers_hand_water` 入口定义阶段宏与 `OMNI_WATER_PASS` 或 `OMNI_HAND_WATER_PASS` 后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_WATER_PASS 1`，再引入本文件。
输出约定：水面写四号、六号、零号，对应 `DRAWBUFFERS:460`；手持半透明写四号、六号，对应 `DRAWBUFFERS:46`。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_TRANSLUCENT_BODY_INCLUDED // 只引入一次。
#define OMNI_TRANSLUCENT_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_WATER_PASS // 水面片元。
/* DRAWBUFFERS:460 */
layout(location = 0) out vec4 gbufferOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 gbufferOutput6; // 六号半透明颜色材质。
layout(location = 2) out vec4 gbufferOutput0; // 零号水遮罩。
void main(){
	gbufferOutput4 = vec4(0.0); // 占位输出零。
	gbufferOutput6 = vec4(0.0); // 占位输出零。
	gbufferOutput0 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT // 手持半透明片元。
/* DRAWBUFFERS:46 */
layout(location = 0) out vec4 gbufferOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 gbufferOutput6; // 六号半透明颜色材质。
void main(){
	gbufferOutput4 = vec4(0.0); // 占位输出零。
	gbufferOutput6 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
