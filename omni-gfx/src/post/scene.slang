/*
Omni 通用图形库 Eclipse 场景补充模块：受伤与入水画面效果、场景控制参数。
调用位置：需要复现 Eclipse `gameplay_effects.glsl` 与 `scene_controller.glsl` 的程序；
    Minecraft 光影由 `/omni-gfx/post/scene.glsl` 引入，后续由 `post/post` 引入并编译。
可复制示例：
    `ogxGameplayEffects(color, uv, noise, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0.0, 0.0, 0.0, 0.0, sceneTex, noiseTex, 1.777, frameTime, 1.0, 1.0);` 把受伤与入水效果叠到颜色。
    `ogxSceneControllerDefaults(outSmallCoverage, outSmallDensity, outLargeCoverage, outLargeDensity, outAltostratusCoverage, outAltostratusDensity, outCirrusCoverage, outCirrusDensity, outFogA, outFogB);` 取参考默认云层参数。
设计原因与取舍：
    参考实现直接读血量、眼在水中、`colortex7` 与末地雾密度纹理。库把数值、纹理与尺寸改成显式参数，
    分支、常数与采样顺序保持不变；场景控制只是把输入默认值抄到输出，参数表来自菜单来源。
    画面效果按受伤、入水、着火拆成三个小函数，入口只按优先级取最大值；场景控制另放子文件，
    这样打开任一文件都只看到一类职责。
*/
#ifndef OGX_POST_SCENE_INCLUDED
#define OGX_POST_SCENE_INCLUDED

// 数学提供夹紧与取模；颜色提供亮度权重。
#include "../common/math.slang"

// 画面效果：受伤、入水、着火与血量上色。
#include "scene/gameplay.slang"
// 场景控制：把云层、密度与雾系数原样输出。
#include "scene/controller.slang"

#endif
