/*
下界（维度宏 `OMNI_NETHER`）的中间画面与加载器常量声明：只写三个维度取值不同的那几项。
调用位置：各维度生成的入口文件在引入绘制主体之前，下界那份引入本文件；
  加载器按每个程序展开后的片元源码读取这些 `const` 指令，所以声明必须真的被编译进程序才会生效。
可复制示例：入口里的 `#include "/rendering/buffers_nether.glsl"` 会先带入本文件，再带入共用声明。
只写差异的原因：三个维度相同的格式、清除、消除色与阴影常量集中在 `rendering/buffers.glsl`，
  由本文件先引入；本文件只补下界独有的取值，值照 iterationT `world-1/composite.fsh` 文件头。
设计原因与取舍：
  下界时间抗锯齿把参考深度与当前深度一起打包进七号画面的透明度通道，必须三十二位浮点，否则打包值丢精度。
  下界光的照度低，原版遮蔽关掉；下界几乎不向阴影图绘制几何，阴影绘制距离缩到近乎零，故一号阴影不做硬件比较、零号阴影不生成多级纹理。
*/
#ifndef OMNI_BUFFERS_NETHER_INCLUDED // 只引入一次，避免与其它入口重复声明。
#define OMNI_BUFFERS_NETHER_INCLUDED // 置上标记。

// 共用声明：格式零到六、清除、清除色与三维度相同的阴影、噪声常量。
#include "/rendering/buffers.glsl"

/*
下界七号画面格式：下界时间抗锯齿把参考深度与当前深度打包进七号透明度通道，必须三十二位浮点，否则打包值丢精度。
const int colortex7Format = RGBA32F;
下界八号画面格式：放大输出用十六位。
const int colortex8Format = RGB16;
*/

// 下界照原程序把阴影绘制距离缩到近乎零。
const float shadowDistanceRenderMul = 0.007;
// 下界一号阴影深度不做硬件比较采样。
const bool shadowHardwareFiltering1 = false;
// 下界零号阴影深度不生成多级纹理。
const bool shadowtex0Mipmap = false;
// 下界关闭原版遮蔽。
const float ambientOcclusionLevel = 0.0;
#endif // 文件守卫结束。
