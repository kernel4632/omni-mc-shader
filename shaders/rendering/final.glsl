/*
最终绘制主体（占位）：由戊片按 iterationT `Lib/Programs/Final.glsl` 的 `PROGRAM_FINAL_2` 段填充，现在只保证编译链接。
调用位置：各维度 `final` 入口定义阶段宏与 `OMNI_FINAL_PASS` 后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_FINAL_PASS 1`，再引入本文件。
输出约定：直接写屏幕，不声明绘制缓冲；原程序在这里做锐化、手与玩家的抗锯齿、抖动和黑边。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_FINAL_BODY_INCLUDED // 只引入一次。
#define OMNI_FINAL_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段：整屏三角形。
void main(){
	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0); // 加载器把顶点放在零到一的方块上，乘二减一铺满屏幕。
}
#endif // 顶点阶段结束。

#ifdef OMNI_FRAGMENT // 片元阶段。
void main(){
	gl_FragData[0] = vec4(0.0); // 占位输出黑色到屏幕。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
