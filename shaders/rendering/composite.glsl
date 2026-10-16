/*
合成绘制主体（占位）：由丁片按 iterationT `composite` 到 `composite5` 的片元程序填充，现在只保证编译链接。
调用位置：各维度 `composite`、`composite1` … `composite5` 入口定义阶段宏与对应 `OMNI_COMPOSITE*_PASS` 后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_COMPOSITE5_PASS 1`，再引入本文件。
输出约定（对应各程序的文件头注释）：
    `composite` 写一号（不透明表面完整光照）；`composite1` 写一号（水下与水后雾）；
    `composite2` 写三号（屏幕空间反射与天空盒回退）；`composite3`、`composite4` 写三号（反射小波滤波）；
    `composite5` 写一号和三号（折射、合并反射、体积雾、选择框，三号写镜头光斑）。
全屏阶段用加载器提供的整屏三角形顶点。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_COMPOSITE_BODY_INCLUDED // 只引入一次。
#define OMNI_COMPOSITE_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段：整屏三角形。
void main(){
	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_COMPOSITE5_PASS // 折射、合并反射与体积雾。
/* DRAWBUFFERS:13 */
layout(location = 0) out vec4 compositeOutput1; // 一号合成颜色。
layout(location = 1) out vec4 compositeOutput3; // 三号镜头光斑。
void main(){
	compositeOutput1 = vec4(0.0); // 占位输出零。
	compositeOutput3 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT && (defined OMNI_COMPOSITE2_PASS || defined OMNI_COMPOSITE3_PASS || defined OMNI_COMPOSITE4_PASS) // 反射与反射滤波。
/* DRAWBUFFERS:3 */
layout(location = 0) out vec4 compositeOutput3; // 三号反射数据。
void main(){
	compositeOutput3 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT // 不透明光照与水后雾。
/* DRAWBUFFERS:1 */
layout(location = 0) out vec4 compositeOutput1; // 一号场景颜色。
void main(){
	compositeOutput1 = vec4(0.0); // 占位输出零。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
