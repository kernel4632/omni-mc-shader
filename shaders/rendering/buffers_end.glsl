/*
末地（维度宏 `OMNI_END`）的中间画面与加载器常量声明：只写三个维度取值不同的那几项。
调用位置：各维度生成的入口文件在引入绘制主体之前，末地那份引入本文件；
  加载器按每个程序展开后的片元源码读取这些 `const` 指令，所以声明必须真的被编译进程序才会生效。
可复制示例：入口里的 `#include "/rendering/buffers_end.glsl"` 会先带入本文件，再带入共用声明。
只写差异的原因：三个维度相同的格式、清除、消除色与阴影常量集中在 `rendering/buffers.glsl`，
  由本文件先引入；本文件只补末地独有的取值，值照 iterationT `world1/composite.fsh` 文件头。
设计原因与取舍：
  末地七号画面当时间抗锯齿历史，十六位够用；八号画面放大输出用十六位。
  末地与主世界一样按完整阴影距离绘制几何、一号阴影做硬件比较、零号阴影生成多级纹理；末地光照暗，原版遮蔽关掉。
*/
#ifndef OMNI_BUFFERS_END_INCLUDED // 只引入一次，避免与其它入口重复声明。
#define OMNI_BUFFERS_END_INCLUDED // 置上标记。

// 共用声明：格式零到六、清除、清除色与三维度相同的阴影、噪声常量。
#include "/rendering/buffers.glsl"

/*
末地七号画面格式：时间抗锯齿历史，十六位。
const int colortex7Format = RGBA16;
末地八号画面格式：放大输出用十六位。
const int colortex8Format = RGB16;
*/

// 末地与主世界一样按完整阴影距离绘制几何。
const float shadowDistanceRenderMul = 1.0;
// 末地一号阴影深度用硬件比较采样。
const bool shadowHardwareFiltering1 = true;
// 末地零号阴影深度生成多级纹理。
const bool shadowtex0Mipmap = true;
// 末地关闭原版遮蔽。
const float ambientOcclusionLevel = 0.0;
#endif // 文件守卫结束。
