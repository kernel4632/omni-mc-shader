/*
延迟绘制主体（占位）：由丙片按 iterationT `deferred` 到 `deferred6` 的片元程序填充，现在只保证编译链接。
调用位置：各维度 `deferred`、`deferred1` … `deferred6` 入口定义阶段宏与对应 `OMNI_DEFERRED*_PASS` 后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_DEFERRED3_PASS 1`，再引入本文件。
输出约定（对应各程序的文件头注释）：
    `deferred` 写七号（水面波浪法线）；`deferred1` 写二号（全局光时间滤波）；`deferred2` 写一号（空间滤波与遮蔽）；
    `deferred3` 写一号和二号（天空、云、统计像素）；`deferred4`、`deferred5` 写二号（云影模糊）；
    `deferred6` 写四号和六号（把不透明法线光照图与材质编号复制给半透明层）。
全屏阶段用加载器提供的整屏三角形顶点，坐标从 `gl_Vertex` 直接算出，不需要投影矩阵。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_DEFERRED_BODY_INCLUDED // 只引入一次。
#define OMNI_DEFERRED_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段：整屏三角形。
void main(){
	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_DEFERRED0_PASS // 水面波浪法线。
/* DRAWBUFFERS:7 */
layout(location = 0) out vec4 deferredOutput7; // 七号焦散法线方块。
void main(){
	deferredOutput7 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED1_PASS // 全局光时间滤波。
/* DRAWBUFFERS:2 */
layout(location = 0) out vec4 deferredOutput2; // 二号全局光历史。
void main(){
	deferredOutput2 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED2_PASS // 空间滤波与遮蔽。
/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 deferredOutput1; // 一号全局光与遮蔽。
void main(){
	deferredOutput1 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED3_PASS // 天空、云与统计像素。
/* DRAWBUFFERS:12 */
layout(location = 0) out vec4 deferredOutput1; // 一号天空像素颜色。
layout(location = 1) out vec4 deferredOutput2; // 二号天空盒与云影。
void main(){
	deferredOutput1 = vec4(0.0); // 占位输出零。
	deferredOutput2 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && (defined OMNI_DEFERRED4_PASS || defined OMNI_DEFERRED5_PASS) // 云影横向与纵向模糊。
/* DRAWBUFFERS:2 */
layout(location = 0) out vec4 deferredOutput2; // 二号云影贴图。
void main(){
	deferredOutput2 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_DEFERRED6_PASS // 半透明层的默认表面数据。
/* DRAWBUFFERS:46 */
layout(location = 0) out vec4 deferredOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 deferredOutput6; // 六号半透明材质编号。
void main(){
	deferredOutput4 = vec4(0.0); // 占位输出零。
	deferredOutput6 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
