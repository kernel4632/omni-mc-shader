/*
主世界（维度宏 `OMNI_OVERWORLD`）的中间画面与加载器常量声明：只写三个维度取值不同的那几项。
调用位置：各维度生成的入口文件在引入绘制主体之前，主世界那份引入本文件；
  加载器按每个程序展开后的片元源码读取这些 `const` 指令，所以声明必须真的被编译进程序才会生效。
可复制示例：入口里的 `#include "/rendering/buffers_main.glsl"` 会先带入本文件，再带入共用声明。
只写差异的原因：三个维度相同的格式、清除、消除色与阴影常量集中在 `rendering/buffers.glsl`，
  由本文件先引入；本文件只补主世界独有的取值，值照 iterationT 根目录 `composite.fsh` 文件头。
设计原因与取舍：
  七号画面在主世界当时间抗锯齿历史，十六位够用；八号画面直接显示，八位就够。
  主世界按完整阴影距离绘制几何，一号阴影深度做硬件比较采样，零号阴影深度生成多级纹理供可变半影搜索。
  原版遮蔽强度保持满值，`GTAO` 另算，两者相乘得到最终遮蔽。
*/
#ifndef OMNI_BUFFERS_MAIN_INCLUDED // 只引入一次，避免与其它入口重复声明。
#define OMNI_BUFFERS_MAIN_INCLUDED // 置上标记。

// 共用声明：格式零到六、清除、清除色与三维度相同的阴影、噪声常量。
#include "/rendering/buffers.glsl"

/*
主世界七号画面格式：时间抗锯齿历史，十六位。
const int colortex7Format = RGBA16;
主世界八号画面格式：放大输出直接显示，八位就够。
const int colortex8Format = RGBA8;
*/

// 阴影绘制距离等于阴影距离，主世界绘制完整阴影。
const float shadowDistanceRenderMul = 1.0;
// 一号阴影深度用硬件比较采样，得到柔和边缘。
const bool shadowHardwareFiltering1 = true;
// 零号阴影深度生成多级纹理，可变半影搜索用。
const bool shadowtex0Mipmap = true;
// 主世界保持满值原版遮蔽，`GTAO` 另算。
const float ambientOcclusionLevel = 1.0;
#endif // 文件守卫结束。
