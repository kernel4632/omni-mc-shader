/*
覆盖层绘制主体（占位）：由乙片按 iterationT `Basic`、`Line`、`Textured`、`Damagedblock`、`Armor_Glint`、
`Beaconbeam`、`Weather` 七组顶点片元程序填充，现在只保证编译链接。
调用位置：各维度对应的七个 `gbuffers_*` 入口定义阶段宏与各自程序宏后引入。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_WEATHER_PASS 1`，再引入本文件。
输出约定：基础、线条、贴图、信标光束写 `DRAWBUFFERS:035`；方块破坏、附魔光、天气只写 `DRAWBUFFERS:0`。
天气靠混合方式把雨雪遮罩乘进零号 `a`，占位写零透明度不会改动底下的画面。
填充时按 `docs/parity.md` 第七节“地基接口”的引入顺序先引入 `common/` 与效果文件，不在这里写算法函数。
*/
#ifndef OMNI_OVERLAY_BODY_INCLUDED // 只引入一次。
#define OMNI_OVERLAY_BODY_INCLUDED // 置上标记。

#ifdef OMNI_VERTEX // 顶点阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。
}
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && (defined OMNI_DAMAGEDBLOCK_PASS || defined OMNI_ARMOR_GLINT_PASS || defined OMNI_WEATHER_PASS) // 只写颜色的三种程序。
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号颜色。
void main(){
	gbufferOutput0 = vec4(0.0); // 占位输出零。
}
#elif defined OMNI_FRAGMENT // 写完整表面数据的四种程序。
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
