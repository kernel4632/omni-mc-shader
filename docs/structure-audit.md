# rendering 阶段审计

这份文件回答三件事：`rendering/` 现在还留哪些文件、每个文件负责什么、下一批还能不能继续减少。
调用位置：继续结构重构前先读；每批完成后更新行数与状态。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：`rendering/` 只留程序主体、阶段顺序和真正的阶段胶水；每个效果的选项、宿主参数换算与阶段组合都在 `effects/`，纯算式在 `omni-gfx`。

## 一、当前口径

- 行数只数去注释后的非空代码行，命令与 `docs/structure-plan.md` 相同。
- 当前 `bind/` 385 行（6 个文件）、`rendering/` 2992 行（43 个文件）、`effects/` 6490 行（99 个文件）、生成的 `omni-gfx` 由库单独统计。
- 2026-10-27 把 98 个按效果命名的阶段片段与 `rendering/parallax.glsl` 移回 `effects/<页>/`，44 个选项文件与同名实现合并；`bind/ground/material.glsl` 的材质解码并入 `effects/ground/material.glsl`。只移动与合并，没有删除效果、选项、默认值或测试。
- 2026-10-27 删除 `shaders/gfx/` 纯转发层；效果文件直接引用 `shaders/omni-gfx/`，生成 GLSL 只保留这一份。

## 二、rendering 文件

| 文件 | 代码行 | 职责 |
| --- | ---: | --- |
| `rendering/buffers.glsl` | 26 | 三个维度取值相同的画面格式、每帧清除、清除色、阴影与噪声常量 |
| `rendering/buffers_end.glsl` | 8 | 只写三个维度取值不同的那几项 |
| `rendering/buffers_main.glsl` | 8 | 只写三个维度取值不同的那几项 |
| `rendering/buffers_nether.glsl` | 8 | 只写三个维度取值不同的那几项 |
| `rendering/camera_adapters.glsl` | 23 | Eclipse 的投影函数直接读全局矩阵，宿主层用同名重载补齐 |
| `rendering/caustics_vertex.glsl` | 13 | 延迟零号与延迟一号共用的整屏顶点，负责把焦散贴图缩放到目标分辨率 |
| `rendering/celestial.glsl` | 127 | 把 iterationT 的天空基础与天空贴图三阶段程序合成一个主体文件 |
| `rendering/composite_filter_pass.glsl` | 13 | 两个程序都只做反射小波滤波，差别只在半径与抖动 |
| `rendering/composite_pass0.glsl` | 31 | 只包含 OMNI_COMPOSITE0_PASS 对应的阶段与算法 |
| `rendering/composite_pass1.glsl` | 14 | 只包含 OMNI_COMPOSITE1_PASS 对应的阶段与算法 |
| `rendering/composite_pass2.glsl` | 27 | 只包含 OMNI_COMPOSITE2_PASS 对应的阶段与算法 |
| `rendering/composite_pass5.glsl` | 36 | 只包含 OMNI_COMPOSITE5_PASS 对应的阶段与算法 |
| `rendering/composite_shared.glsl` | 32 | 六个合成程序（`composite` 到 `composite5`）共用的片元全局量，全项目只在这里声明一次 |
| `rendering/deferred_cloud_shadow_blur.glsl` | 62 | 把云影贴图做横向或纵向高斯模糊，并保留末地把全局光空间滤波放在同一程序里的分支 |
| `rendering/deferred_pass0.glsl` | 29 | 只包含 OMNI_DEFERRED0_PASS 对应的阶段与算法 |
| `rendering/deferred_pass1.glsl` | 28 | 只包含 OMNI_DEFERRED1_PASS 对应的阶段与算法 |
| `rendering/deferred_pass2.glsl` | 29 | 只包含 OMNI_DEFERRED2_PASS 对应的阶段与算法 |
| `rendering/deferred_pass3.glsl` | 25 | 只包含 OMNI_DEFERRED3_PASS 对应的阶段与算法 |
| `rendering/deferred_pass4.glsl` | 5 | 横向模糊云影贴图；末地在这里做全局光空间滤波 |
| `rendering/deferred_pass5.glsl` | 5 | 纵向模糊云影贴图；末地在这里做全局光空间滤波 |
| `rendering/deferred_pass6.glsl` | 20 | 只包含 OMNI_DEFERRED6_PASS 对应的阶段与算法 |
| `rendering/deferred_pass7.glsl` | 51 | 只包含 OMNI_DEFERRED7_PASS 对应的阶段与算法 |
| `rendering/deferred_pass8.glsl` | 44 | 只包含 OMNI_DEFERRED8_PASS 对应的阶段与算法 |
| `rendering/deferred_shared.glsl` | 31 | 把三个延迟阶段重复写过的像素坐标、顶点光色输入与阴影纹理集中到一处 |
| `rendering/distant.glsl` | 219 | 把 iterationT 的远景地形与远景水四组程序合成一个主体文件 |
| `rendering/entities.glsl` | 433 | 把 iterationT 的实体、方块实体、手持物、蜘蛛眼四类程序合成一个主体文件 |
| `rendering/final.glsl` | 73 | 把 iterationT `Lib/Programs/Final.glsl` 的 `PROGRAM_FINAL_2` 段搬进一个文件，直接写屏幕 |
| `rendering/lights.glsl` | 99 | 照 iterationT `Lib/Programs/CompositeVS.glsl` 一比一移植，算出片元要用的方向与光色 |
| `rendering/lpv.glsl` | 102 | `setup` 阶段填方块光表，`shadowcomp` 阶段每帧推进一拍彩色光传播 |
| `rendering/overlay.glsl` | 300 | 把 iterationT 的基础、线条、贴图、方块破坏、附魔光、信标光束、天气七组程序合成一个主体文件 |
| `rendering/post_effect_pass.glsl` | 40 | 景深、两级泛光降采样、横纵模糊与合并泛光原本各占一个文件，流程完全相同 |
| `rendering/post_fragment_deps.glsl` | 14 | 按固定顺序引入景深、动态模糊、泛光与合并泛光需要的效果文件 |
| `rendering/post_pass14.glsl` | 17 | 只包含 OMNI_COMPOSITE14_PASS 对应的阶段与算法 |
| `rendering/post_pass15.glsl` | 20 | 只包含 OMNI_COMPOSITE15_PASS 对应的阶段与算法 |
| `rendering/post_pass16.glsl` | 21 | 只包含 OMNI_COMPOSITE16_PASS 对应的阶段与算法 |
| `rendering/post_pass7.glsl` | 12 | 只包含 OMNI_COMPOSITE7_PASS 对应的阶段与算法 |
| `rendering/post_pass8.glsl` | 26 | 只包含 OMNI_COMPOSITE8_PASS 对应的阶段与算法 |
| `rendering/post_shared.glsl` | 38 | 后期各程序共用的片元全局量只在这里声明一次 |
| `rendering/post_vertex.glsl` | 12 | 把加载器给的零到一四边形按程序需要的比例缩放 |
| `rendering/shadow.glsl` | 229 | 把 iterationT 的阴影顶点与片元两个程序搬进一个主体文件，主世界与远景阴影共用一套代码 |
| `rendering/terrain.glsl` | 252 | 把 iterationT 的地形顶点、几何、片元三个程序搬进一个主体文件 |
| `rendering/translucent.glsl` | 286 | 把 iterationT 的水面与手持水四类程序合成一个主体文件 |
| `rendering/watersim.glsl` | 104 | 三个计算阶段在模拟场图像上注入、传播并求坡度，供水面片元读取 |

## 三、判断

- 保留下来的文件都能说明自己在哪个绘制阶段被调用，或它是多个阶段共用的声明胶水。
- 效果算法与选项已经按效果归位到 `effects/<页>/`，新增一个效果只改自己的效果文件；`rendering/` 不再保存效果实现。
- 下一步可以继续减少的是程序主体之间重复的全局声明块；抽之前要先核对每个程序实际用到的采样器与阶段宏。

## 四、验证边界

- `audit`、`verify`、全量 `compile` 与 `strict-parity` 通过；按用户要求未启动 Minecraft。
- 游戏内画面、菜单逐页、性能与其他显卡仍未验证。
