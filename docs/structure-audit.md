# rendering 阶段审计

这份文件回答三件事：`rendering/` 现在还留哪些文件、每个文件负责什么、下一批还能不能继续减少。
调用位置：继续结构重构前先读；每批完成后更新行数与状态。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：`rendering/` 只留程序主体、阶段顺序和真正的阶段胶水；每个效果的选项、宿主参数换算与阶段组合都在 `effects/`，纯算式在 `omni-gfx`。

## 一、当前口径

- 行数只数去注释后的非空代码行，命令与 `docs/structure-plan.md` 相同。
- 当前 `bind/` 385 行（6 个文件）、`rendering/` 2941 行（41 个文件）、`effects/` 6250 行（101 个文件）、生成的 `omni-gfx` 由库单独统计。
- 2026-10-27 把 98 个按效果命名的阶段片段与 `rendering/parallax.glsl` 移回 `effects/<页>/`，44 个选项文件与同名实现合并；`bind/ground/material.glsl` 的材质解码并入 `effects/ground/material.glsl`。只移动与合并，没有删除效果、选项、默认值或测试。

## 二、rendering 文件

| 文件 | 代码行 | 职责 |
| --- | ---: | --- |
| `rendering/buffers.glsl` | 26 | 共享中间画面与加载器常量声明 |
| `rendering/buffers_end.glsl` | 8 | 末地（维度宏 `OMNI_END`）的中间画面与加载器常量声明 |
| `rendering/buffers_main.glsl` | 8 | 主世界（维度宏 `OMNI_OVERWORLD`）的中间画面与加载器常量声明 |
| `rendering/buffers_nether.glsl` | 8 | 下界（维度宏 `OMNI_NETHER`）的中间画面与加载器常量声明 |
| `rendering/camera_adapters.glsl` | 23 | 相机坐标兼容层 |
| `rendering/celestial.glsl` | 127 | 天体绘制主体 |
| `rendering/composite_filter_pass.glsl` | 13 | 合成三号与四号的共用程序主体 |
| `rendering/composite_pass0.glsl` | 31 | 单个程序的绘制主体 |
| `rendering/composite_pass1.glsl` | 14 | 单个程序的绘制主体 |
| `rendering/composite_pass2.glsl` | 27 | 单个程序的绘制主体 |
| `rendering/composite_pass5.glsl` | 36 | 单个程序的绘制主体 |
| `rendering/composite_shared.glsl` | 32 | 合成共享声明 |
| `rendering/deferred_cloud_shadow_blur.glsl` | 62 | 延迟四号、五号的共用阶段 |
| `rendering/deferred_pass0.glsl` | 29 | 单个程序的绘制主体 |
| `rendering/deferred_pass1.glsl` | 28 | 单个程序的绘制主体 |
| `rendering/deferred_pass2.glsl` | 29 | 单个程序的绘制主体 |
| `rendering/deferred_pass3.glsl` | 25 | 单个程序的绘制主体 |
| `rendering/deferred_pass4.glsl` | 5 | 延迟四号 |
| `rendering/deferred_pass5.glsl` | 5 | 延迟五号 |
| `rendering/deferred_pass6.glsl` | 20 | 单个程序的绘制主体 |
| `rendering/deferred_pass7.glsl` | 51 | 单个程序的绘制主体 |
| `rendering/deferred_pass8.glsl` | 44 | 单个程序的绘制主体 |
| `rendering/deferred_shared.glsl` | 31 | 延迟程序共用的片元声明 |
| `rendering/distant.glsl` | 219 | 远景绘制主体 |
| `rendering/entities.glsl` | 433 | 实体绘制主体 |
| `rendering/final.glsl` | 73 | 最终绘制主体 |
| `rendering/lights.glsl` | 99 | 光照与天体方向顶点主体 |
| `rendering/lpv.glsl` | 102 | 光传播体积计算入口 |
| `rendering/overlay.glsl` | 300 | 覆盖层绘制主体 |
| `rendering/post_effect_pass.glsl` | 40 | 后期共用的程序主体 |
| `rendering/post_fragment_deps.glsl` | 14 | 后期程序的共用片元依赖 |
| `rendering/post_pass14.glsl` | 17 | 单个程序的绘制主体 |
| `rendering/post_pass15.glsl` | 20 | 单个程序的绘制主体 |
| `rendering/post_pass16.glsl` | 21 | 单个程序的绘制主体 |
| `rendering/post_pass7.glsl` | 12 | 单个程序的绘制主体 |
| `rendering/post_pass8.glsl` | 26 | 单个程序的绘制主体 |
| `rendering/post_vertex.glsl` | 12 | 后期程序的整屏顶点 |
| `rendering/shadow.glsl` | 229 | 阴影绘制主体 |
| `rendering/terrain.glsl` | 252 | 地形绘制主体 |
| `rendering/translucent.glsl` | 286 | 半透明绘制主体 |
| `rendering/watersim.glsl` | 104 | 波浪模拟计算入口 |

## 三、判断

- 保留下来的文件都能说明自己在哪个绘制阶段被调用，或它是多个阶段共用的声明胶水。
- 效果算法与选项已经按效果归位到 `effects/`，新增一个效果不再需要同时改 `effects/` 与 `rendering/<效果>/` 两处。
- 下一步可以继续减少的是程序主体之间重复的全局声明块；抽之前要先核对每个程序实际用到的采样器与阶段宏。

## 四、验证边界

- `audit`、`verify`、全量 `compile` 与 `strict-parity` 通过；按用户要求未启动 Minecraft。
- 游戏内画面、菜单逐页、性能与其他显卡仍未验证。
