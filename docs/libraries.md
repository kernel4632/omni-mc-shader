# 可复用库与框架（寻找阶段）

本文件记录外部可复用代码的调研结果：能直接采用的库、许可、覆盖的功能，以及没有库、必须自己按公开论文实现的部分。
目标：尽量少写自己的算法代码，把数学、噪声、颜色、抗锯齿、超分、环境光遮蔽、大气这些交给成熟库。

## 结论先说

- **没有现成的 Minecraft 光影「框架」**：Iris 就是加载器，社区用 `shaders/lib/` 放共享函数，没有官方的可复用库集合。
- **可以合法采用的库不少**，但都集中在「通用图形函数」层面；光影与 MC 绘制流程的对接（程序、缓冲、选项、光照合成）仍然要我们自己写。
- **「自己只写几百行」可以实现的是数学/工具层**，不是整套真实感效果。真实感主体（PBR、水、体积云/雾、SSR、GI、SSS）没有可直接引用的宽松许可库，只能按公开论文独立实现。

## 能直接接入的独立 GLSL 库

这些是单文件、能用 `#include` 引入、许可宽松的库，优先直接采用。

| 库 | 提供什么 | 许可 | 接入方式 |
| --- | --- | --- | --- |
| Ashima 三维单纯形噪声 | 噪声 | MIT | 未采用；云改用 iterationT 预计算噪声贴图 |
| SMAA（iryoku/smaa） | 形态学抗锯齿 | MIT | 引入 GLSL，另带 AreaTex/SearchTex 查找表纹理 |
| XeGTAO（GameTechDev） | 环境光遮蔽 | MIT（Intel） | 以着色器方式接入，需适配 Iris |
| glsl-atmosphere（wwwtyro） | 瑞利/米氏天空散射 | 公有领域（Unlicense） | 单函数，直接 `#include` |
| AgX / ACES / Uchimura 高光压缩 | 高光还原 | 公开算法 | 代码很短，按 HOP 重写进项目 |

## 引擎/框架源码（只作参考，按原理重写）

这些不是能接入的库，而是宽松许可的**引擎实现**。读它们的 GLSL/HLSL 算法，按 HOP 重写进项目，不能整包搬。

| 来源 | 语言 | 许可 | 可参考的效果 |
| --- | --- | --- | --- |
| Google Filament | GLSL/C++ | Apache-2.0 | PBR、IBL、SSAO、SSR、TAA、DOF、泛光、体积雾、色调映射、色彩分级 |
| Godot Engine | GLSL 风格 | MIT | SSAO、SSR、SDFGI 全局光、体积雾、辉光、景深散景、运动模糊、TAA/FSR、天空、雾 |
| three.js | GLSL | MIT | BSDF、色调映射、雾、灯光模式；后处理含 SMAA、泛光、散景、SSR、GTAO、TAA、FXAA |
| AMD FidelityFX（FSR/CACAO/SSSR/LPM/SPD） | HLSL/GLSL | MIT（CACAO 已核实） | 超分、环境光遮蔽、随机屏幕反射、色调映射 |
| Sebastian Lague Clouds | C# 着色器 | MIT（已核实） | 体积云 |
| Bruneton 预计算大气散射 | C++ | BSD-3-Clause | 物理大气（需预计算 LUT） |

## 采用前需再核实许可

| 库 / 来源 | 提供什么 | 现状 |
| --- | --- | --- |
| yiwenl/glsl-utils、hughsk、jamieowen/glsl-blend、hiepgaf/GLSL_libs | 噪声、混合、颜色、曝光 | 多为 MIT，需逐个核对并记录来源 |

## 明确不能用（许可限制）

| 来源 | 原因 |
| --- | --- |
| Photon Shaders（sixthsurge） | 个人版权，禁止在 Modrinth/CurseForge 等平台再分发 |
| 大多数主流光影包（Complementary、BSL、Chocapic13 等） | 版权保留，不允许复制进自己的包 |
| lygia（patriciogonzalezvivo） | Prosperity 许可：免费仅限非商业，商业只有 30 天试用。光影免费分发时可用，但必须随包附许可与声明；若将来商业化则不可用 |

## 没有库、必须自己实现的部分

这些是「真实感」的主体，找不到宽松许可的现成实现，只能按公开论文独立写：

- 与 Iris 的对接：绘制程序、缓冲协议、选项、延迟与前向光照的合成。
- PBR / labPBR 材质解码与直接光照。
- 水面：解析波、海浪、吸收/散射、折射、反射、水面高光。
- 体积云、体积雾、光柱。
- 屏幕空间反射（SSR）与降噪。
- 时间抗锯齿（AA 的形态学部分可用 SMAA，时间部分要自己写）。
- 彩色/透射阴影、接触硬化、焦散。
- 次表面散射、全局光、体素/光子。
- 季节、生物群系颜色、行星曲率、资源包天空。

## 建议的库分层与目录

按项目现有约定，第三方库放 `shaders/libraries/`，每个库一个目录，保留上游版权与许可原文：

```
shaders/libraries/
  smaa/            抗锯齿（+ 查找表纹理）
  xegtao/          环境光遮蔽
  atmosphere/      解析大气（wwwtyro）
  (待定) fsr/      超分（许可核实后再放）
```

我们的对接代码保持在 `shaders/common/` 与 `shaders/effects/`，只负责调用库函数并接入 Iris 流程。

## 许可与打包规则（沿用项目约定）

1. 每个采用的库在 `dependencies.json` 登记来源、版本、许可、文件哈希。
2. `THIRD_PARTY.md` 汇总，原许可随包。
3. 只收许可明确、允许再分发的库；许可不明或禁止再分发的一律不用。
4. 库的文件不改字节，只在旁边写我们的调用与说明。

## 对「自己只写几百行」的现实评估

- 数学/噪声/颜色/抗锯齿/超分/AO/大气：可由库覆盖，我们的代码确实能压到很少。
- 光影主体与 MC 对接：无法由库覆盖，必须是我们的代码，行数会明显超过几百行。
- 因此现实目标是：**把能外包的都外包，把自己的代码集中在「效果组合与 MC 对接」这一薄层**，而不是承诺总行数。

## 下一步

1. 你确认此清单后，我逐个核实「待核实」库的许可。
2. 按确认结果把库放进 `shaders/libraries/`，登记 `dependencies.json` 与 `THIRD_PARTY.md`。
3. 用库替换现有自写实现：先换噪声与抗锯齿，再换 AO 与大气。
4. 按 `docs/eclipse-parity.md` 的合并建议与 `docs/parity.md` 的偏离记录，用库与公开论文逐个补效果。
