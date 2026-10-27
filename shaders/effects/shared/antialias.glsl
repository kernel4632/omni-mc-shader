/*
效果文件 `effects/shared/antialias.glsl`：只保存时域抗锯齿的玩家选项。
调用位置：`effects/clarity/antialiasing.glsl` 引入它之后实现重投影与历史写入；镜头、光照、雾、阴影、世界等页面
    也要按 `OMNI_TAA` 决定是否抖动，因此它们直接引入本文件，不再为了一个开关去引用整个时域抗锯齿效果。
可复制示例：`#include "/effects/shared/antialias.glsl"`，随后即可使用 `OMNI_TAA`、`OMNI_DH_TAA_JITTER` 等选项。
设计原因与取舍：抖动开关同时影响坐标换算、阴影噪声、雾步进与镜头随机数，属于多个页面共用的输入；
    选项放在共享层只定义一次，各页面自己引入，避免依赖“谁的引用顺序恰好在我前面”这种隐含约定。
    重投影、历史裁剪与 FXAA 仍留在 `effects/clarity/`，因为它们是主世界与下界的画面算法，不是所有页面都需要的计算。
*/
#ifndef OMNI_SHARED_ANTIALIAS_INCLUDED
#define OMNI_SHARED_ANTIALIAS_INCLUDED
// @effect {"label":{"zh_cn":"时域抗锯齿","en_us":"Temporal AA"}}
// @option {"label":{"zh_cn":"时间边缘平滑","en_us":"TAA"},"description":{"zh_cn":"用上一帧历史把边缘和噪点叠平滑；开启前请先在着色器设置里打开抗锯齿。","en_us":"Uses previous-frame history to smooth edges and noise; enable antialiasing in shader settings first."}}
#define OMNI_TAA
// @option {"label": {"zh_cn": "远景也参与抖动", "en_us": "Jitter distant terrain"}, "description": {"zh_cn": "远景地块随近景一起做逐帧抖动，交界处才和近景对齐；关掉后远景不抖、更稳，但交界可能与近景错半像素。默认开启。来源 Eclipse 的 DH_TAA_JITTER。", "en_us": "Lets distant chunks share the per-frame jitter with nearby terrain so the boundary stays aligned; off keeps distant terrain steadier but may misalign it by half a pixel. On by default. Ports Eclipse's DH_TAA_JITTER."}}
#define OMNI_DH_TAA_JITTER 1 // [0 1]
// @option {"label": {"zh_cn": "历史混合权重", "en_us": "History Blend Weight"}, "slider": true, "description": {"zh_cn": "越高画面越稳、越容易留轻微拖影。", "en_us": "Higher is steadier but more prone to slight smearing."}}
#define OMNI_TAA_BLENDWEIGHT 0.97 // [0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99]
// @option {"label": {"zh_cn": "历史裁剪强度", "en_us": "History Clip Aggression"}, "slider": true, "description": {"zh_cn": "邻域裁剪的松紧，越大越容易拒绝历史、减少拖影。", "en_us": "Tightness of neighbourhood clipping; higher rejects more history and reduces smearing."}}
#define OMNI_TAA_AGGRESSION 2.0 // [1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0]
// @option {"label":{"zh_cn":"关闭手部边缘平滑","en_us":"Disable Hand TAA"},"description":{"zh_cn":"手不参与时间抗锯齿，减少手的拖影；这类像素改用边缘抗锯齿。","en_us":"Excludes the hand from TAA to reduce smearing; those pixels fall back to edge AA."}}
#define OMNI_DISABLE_HAND_TAA 0 // [0 1]
// @option {"label":{"zh_cn":"关闭玩家边缘平滑与动态模糊","en_us":"Disable Player TAA & Motion Blur"},"description":{"zh_cn":"玩家角色不参与时间抗锯齿和动态模糊，减少第三人称下的拖影。","en_us":"Excludes the player from TAA and motion blur."}}
//#define OMNI_DISABLE_PLAYER_TAA_MOTION_BLUR
// @option {"label": {"zh_cn": "深度比较阈值", "en_us": "Depth Compare Threshold"}, "slider": true, "description": {"zh_cn": "判断历史点是否被遮挡的深度差上限；越小越容易判定为被遮挡、越少拖影。", "en_us": "Depth difference above which history is treated as occluded; smaller rejects more history and reduces smearing."}}
#define OMNI_TAA_DEPTH_COMPARE_THRESHOLD 0.0007 // [0.00002 0.00003 0.00005 0.00007 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001 0.0015 0.002 0.003 0.005 0.007 0.01 0.015 0.02 0.03 0.05 0.07 0.1]
#endif // OMNI_SHARED_ANTIALIAS_INCLUDED
