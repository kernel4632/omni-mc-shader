/*
延迟五号：纵向模糊云影贴图；末地在这里做全局光空间滤波。
来源：从 `rendering/deferred.glsl` 拆分，主体与延迟四号共用 `rendering/deferred_cloud_shadow_blur.glsl`。
调用位置：各维度 `deferred5` 入口定义 `OMNI_DEFERRED5_PASS`、维度宏与阶段宏后引入本文件。
可复制示例：`#define CLOUD_SHADOW_BLUR_AXIS ivec2(0, 1)` 后引入共用阶段，得到纵向模糊。
设计原因与取舍：延迟四号与五号原来逐行相同，只差采样轴；本文件只声明轴，
    顶点缩放、末地分支与主世界模糊只在共用模板里维护一份。
*/
#ifndef OMNI_DEFERRED_BODY_INCLUDED // 只引入一次，避免 `main()` 与输出变量重复定义。
#define OMNI_DEFERRED_BODY_INCLUDED // 置上标记，后续再次引用直接跳过。

// 云影纵向高斯模糊。
#define CLOUD_SHADOW_BLUR_AXIS ivec2(0, 1)
// 共用阶段：顶点、末地全局光分支与主世界云影模糊。
#include "/rendering/deferred_cloud_shadow_blur.glsl"

#endif // 文件守卫结束。
