/*
后期绘制主体（占位）：由戊片按 iterationT `composite6` 到 `composite16` 的片元程序填充，现在只保证编译链接。
调用位置：各维度 `composite6` … `composite16` 入口定义阶段宏与对应 `OMNI_COMPOSITE*_PASS` 后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE14_PASS 1`，再引入本文件。
输出约定（对应各程序的文件头注释）：
    `composite6` 写一号（景深）；`composite7` 写七号（时间抗锯齿历史）；`composite8` 写一号和二号（运动模糊与统计像素）；
    `composite9` … `composite13` 写五号（泛光降采样与升采样）；`composite14` 写一号（合并泛光、暗角、曝光、色调映射）；
    `composite15` 写一号（锐化）；`composite16` 写八号（放大输出）。
全屏阶段用加载器提供的整屏三角形顶点。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_POST_BODY_INCLUDED // 只引入一次。
#define OMNI_POST_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段：整屏三角形。
void main(){
	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE16_PASS // 放大输出。
/* DRAWBUFFERS:8 */
layout(location = 0) out vec4 compositeOutput8; // 八号放大结果。
void main(){
	compositeOutput8 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_COMPOSITE8_PASS // 运动模糊与统计像素。
/* DRAWBUFFERS:12 */
layout(location = 0) out vec4 compositeOutput1; // 一号模糊后的颜色。
layout(location = 1) out vec4 compositeOutput2; // 二号顶行统计像素。
void main(){
	compositeOutput1 = vec4(0.0); // 占位输出零。
	compositeOutput2 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && defined OMNI_COMPOSITE7_PASS // 时间抗锯齿历史。
/* DRAWBUFFERS:7 */
layout(location = 0) out vec4 compositeOutput7; // 七号历史画面。
void main(){
	compositeOutput7 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && (defined OMNI_COMPOSITE9_PASS || defined OMNI_COMPOSITE10_PASS || defined OMNI_COMPOSITE11_PASS || defined OMNI_COMPOSITE12_PASS || defined OMNI_COMPOSITE13_PASS) // 泛光链。
/* DRAWBUFFERS:5 */
layout(location = 0) out vec4 compositeOutput5; // 五号泛光。
void main(){
	compositeOutput5 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT // 景深、合并泛光与锐化。
/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 compositeOutput1; // 一号场景颜色。
void main(){
	compositeOutput1 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
