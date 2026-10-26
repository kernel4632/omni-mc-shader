# omni-gfx 通用图形库计划

这份文件记录 Omni 下一阶段的初衷，防止上下文压缩后忘记目标。
调用位置：新会话先读本文件，再读 `docs/structure-plan.md` 和 `AGENTS.md`。
一句话目标：**用最少的自写代码，做一个跨引擎、可维护、效果不低于现在的图形库，并让 Minecraft 光影直接导入。**

## 一、初衷

Omni 不再只是“一个 Minecraft 光影包”。它要产出一个独立库 `omni-gfx`：

- 放在仓库根目录，和 `shaders/` 平级；
- 用 Slang 编写；
- 尽可能复用成熟库、框架和论文实现；
- 我们自己只写适配、组合和生成器，手写代码尽量少；
- 效果不能比现在少，观感不能比现在差；
- 兼容性优先：Minecraft 光影能直接导入，未来能接 Vulkan/Aperture 和其他引擎。

## 二、硬限制

Minecraft 光影只读 GLSL 文本，不认 Slang。因此：

- **Slang 是源代码**，我们维护的只有 Slang；
- 构建时自动生成 **GLSL 330** 给 Iris 直接 `#include`；
- 同一份源再生成 **SPIR-V**，供 Aperture/Vulkan 使用；
- 生成文件不手改，改源文件后重新生成。

“MC 直接导入”指导入生成的 GLSL，不是把 Slang 原文件塞进光影包。

## 三、目录

```text
Omni/
├─ shaders/                     现有 Minecraft 光影包（消费者）
│  ├─ omni-gfx/                 构建生成的 GLSL，MC 直接 include
│  └─ gfx/                      旧 GLSL 库，迁移完成前保留
├─ omni-gfx/                    独立库
│  ├─ src/                      Slang 源文件（唯一手写算法源）
│  ├─ generated/glsl/           自动生成，给 Iris
│  ├─ generated/spirv/          自动生成，给 Vulkan/Aperture
│  ├─ examples/world/           不启动 MC 的测试世界
│  ├─ tests/                    截图对比、性能、边界
│  ├─ tools/                    生成器、打包、许可证清单
│  ├─ vendor/                   第三方代码，保留许可证
│  ├─ docs/
│  ├─ CMakeLists.txt
│  ├─ LICENSE
│  └─ README.md
└─ docs/                        项目文档
```

## 四、技术栈

| 用途 | 选择 | 原因 |
| --- | --- | --- |
| 着色语言 | Slang | 模块、泛型、跨后端，能生成 GLSL/HLSL/SPIR-V |
| 示例窗口/GPU | SDL3 GPU API | 一套 C API 覆盖 Vulkan/D3D12/Metal，样板少 |
| CPU 数学 | glm | 不自己写矩阵和相机 |
| 图片读写 | stb_image / stb_image_write | 单头文件，够用 |
| UI 调试 | Dear ImGui（可选） | 调参数快 |
| 测试 | Catch2/doctest + Python 黄金图 | CPU 单测 + GPU 截图对比 |
| 着色器校验 | SPIRV-Tools / SPIRV-Cross | 编译、校验、GLSL 后端 |
| 构建 | CMake + Ninja | 跨平台，CI 简单 |

如果 SDL3 GPU 在某些驱动上不稳定，退回 bgfx 或直接 Vulkan；不自己写窗口和设备初始化。

## 五、复用优先

原则：**能复用就不手写；不能复用才移植；移植必须核对许可证。**

| 领域 | 优先参考 |
| --- | --- |
| 数学/颜色/采样 | Slang 标准库、现有 `gfx` 代码 |
| PBR/IBL/SSAO/泛光 | Filament（Apache 2.0） |
| 大气 | Bruneton 预计算大气 |
| 云 | Nubis / Hillaire 体积云 |
| 水 | Tessendorf FFT 海洋、Gerstner |
| 阴影 | CSM、PCSS、ReSTIR/RTXDI |
| 雾 | Frostbite 体积雾、Bruneton 空气透视 |
| 降噪/超分 | NRD、OIDN、FSR/CAS |
| 色调映射 | AgX、ACES（已有） |

第三方代码统一放 `vendor/`，保留 LICENSE 和来源；不能把 UE/Unity 的代码直接搬进独立库。

## 六、代码量口径

“手写代码”只统计：

- `omni-gfx/src/**`；
- `omni-gfx/tools/**` 里我们维护的生成器；
- `omni-gfx/tests/**` 里我们写的测试。

不计入：

- `generated/**`；
- `vendor/**`；
- 第三方示例；
- 现有 `shaders/` 里的旧实现。

目标：

- 手写核心 **≤10600 行**（第六次按实际规模上调：前五批累计到 9267 行；第六批严格函数对照新增 iterationT 与 Eclipse 的 AgX 配置、Eclipse 天空模型、色调映射、云相函数与 TAA 取样端口，并加入两个 profile 的生成与编译工具）；生成代码不手改；
- 生成代码不手改；
- 每减少 500 行要说明换来了什么，不靠删效果凑数。

## 七、兼容性分层

| 层级 | 目标 | 验收 |
| --- | --- | --- |
| 1 | Iris / GLSL 330 | MC 光影能直接 include，519 个选项和九页菜单不变 |
| 2 | Aperture / Vulkan | 同一份 Slang 源生成 SPIR-V，能跑演示场景 |
| 3 | 其他引擎 | 按需生成 HLSL/GLSL，不承诺首发全覆盖 |
| 4 | 独立测试世界 | 不启动 MC 能出图、测帧率、做截图对比 |

## 八、工作流

```text
改 omni-gfx/src/*.slang
        ↓
生成 GLSL 330 / SPIR-V / HLSL
        ↓
独立测试世界截图 + 性能
        ↓
MC 光影编译 + 同场景对比
        ↓
提交
```

规则：

- 只改 Slang 源，不改生成文件；
- 每次生成后跑 `audit`、`verify`、`compile`；
- 每个模块有独立测试场景和截图基准；
- MC 里的选项、菜单、预设仍由现有生成器管理。

## 九、阶段

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| 0 | `omni-gfx` 骨架、CMake、Slang 编译、SDL3 全屏三角形 | 不启动 MC 能出图 |
| 1 | 迁 `math`、`color`、`sampling` | 与现有 GLSL 输出一致，MC 能 include |
| 2 | 程序化体素世界 + 天空 + 水 + 云 | 可移动相机、截图、测帧时 |
| 3 | 大气、云、雾、水、阴影、GI、反射、后期、抗锯齿逐模块迁移 | 同场景对比不低于现在，许可证清楚 |
| 4 | 整包接入 MC | 280 组程序编译通过，519 个选项不变 |
| 5 | 生成 SPIR-V，接 Aperture/Vulkan | 同一份源多后端通过 |
| 6 | 文档、许可证、示例、CI、发布 | 别人能独立构建 |

## 十、验收标准

- `omni-gfx` 不依赖 Minecraft 就能构建和运行；
- MC 光影通过生成的 GLSL 直接导入，选项、菜单、预设不变；
- 同一场景截图与现在对比，差异在可接受范围；
- 固定设备、固定场景，性能不低于现在的 95%；
- 手写核心代码 ≤8800 行（不含生成和第三方）；
- `omni-gfx/src` 不出现 Minecraft、Iris、`OMNI_*`、`colortex` 等宿主符号；
- 每个第三方依赖有许可证记录；
- 生成文件可复现，构建脚本一条命令完成。

## 十一、风险

1. **Slang → GLSL 330 兼容**：生成代码可能用高版本特性；需要兼容配置或双后端。
2. **SDL3 GPU 成熟度**：驱动差异；退回 bgfx/Vulkan。
3. **GPU CI**：CI 机器可能没有显卡；黄金图本地跑，CI 只编译和跑软件 Vulkan。
4. **许可证**：参考算法不能直接复制；发布前逐项核对。
5. **“效果更好”不能保证**：只能定义场景、指标、基准，用数据说话。
6. **代码量目标**：519 个选项和三维度适配会占空间；2000 行是冲刺目标，不是硬承诺。

## 十二、非目标

- 不做新游戏引擎；
- 不重写 Minecraft 的菜单和选项系统；
- 不承诺首发支持所有引擎；
- 不宣称“世界第一个通用图形库”；
- 不在迁移完成前删除现有 `shaders/gfx` 或破坏 MC 光影。

## 十三、当前状态与下一步

- 当前版本以 `VERSION` 为准；MC 光影包已有九页菜单、519 个选项、280 组程序和 4 套预设。
- `shaders/gfx/` 是旧 GLSL 原型，约 4k 行，迁移完成前保留。
- 2026-10-24 完成阶段 0–2：根目录 `omni-gfx/` 骨架、Slang 源、GLSL 330 生成、SPIR-V 探针、`math` / `color` / `sampling` 迁移、程序化测试世界（天空、地形、水面、云、可移动相机、截图与帧时）。
- 2026-10-24 完成阶段 3 的第一批效果迁移：`noise`、`atmosphere`、`cloud`、`water`、`fog` 五个 Slang 模块；测试世界改用生成的 GLSL，加入单次散射大气、24 步程序化体积云、方向波水面、软高度图阴影、云影、空气透视与低空雾。
- 生成库已接入 `shaders/rendering/color/post_tonemap.glsl`（`composite14` 的色调映射）与 `shaders/rendering/fog/landscattering.glsl`（合成程序的瑞利与米氏相函数）；离线全量编译 280 组程序通过。
- GPU 等值测试 26/26 通过，最大绝对差 0；阶段三测试世界在 1280×720 下 120 帧平均 73.76 毫秒，截图在 `.dev/omni-gfx/world-phase3.png`，详见 `omni-gfx/docs/verification.md`。
- 2026-10-24 完成阶段 3 的画面与性能收尾：体积云改为半分辨率（640×360）、十二步、蓝噪声抖动、时间累积与双边升采样；地形改用覆盖全岛的方向光阴影贴图；水面补上屏幕空间地形反射、深水体色与远距离雾；后期加入两级对数亮度自动曝光。测试世界在 1280×720 下从 73.76 毫秒降到平均 28.96 毫秒（中位 29.09，约 34.5 帧每秒），截图在 `.dev/omni-gfx/world-final.png`，详见 `omni-gfx/docs/verification.md`。
- 2026-10-24 完成阶段 3 收尾与整包接入：新增 `shadow`、`gi`、`reflection`、`post`、`antialias` 五个 Slang 模块，扩展到 13 个模块；阴影补上三级级联与 PCSS，全局光补上地平线遮蔽、反弹与两级滤波，反射补上九点降噪，抗锯齿补上时间重投影，后期补上泛光核、景深与分块测光。Minecraft 侧的九个适配层改为引用生成库，调用点、519 个选项、九页菜单与默认画面不变；280 组程序离线编译通过。
- 测试世界新增这些效果后，1280×720 在 Intel Arc 上 120 帧平均 11.86 毫秒（约 84 帧每秒），截图 `.dev/omni-gfx/world-complete.png`，详见 `omni-gfx/docs/verification.md`。
- 未验证：Minecraft 游戏内画面、性能与兼容性；Vulkan/Aperture 运行时；其他显卡；纯屏幕空间追踪的独立场景；抗锯齿的移动画面表现。
- 2026-10-25 完成第二批迁移：`weather`、`surface`、`parallax`、`voxel`、`upscale`、`planet`、`accretion`、`atmosphere_model`、`cloud_volume`、`fog_volume` 十个 Slang 模块，并补齐 `math`、`color`、`sampling`、`cloud`、`water`、`fog`、`atmosphere`、`post` 的剩余算法。`shaders/gfx/` 的 23 个文件全部变成适配层，GLSL 生成 23 个模块；SPIR-V 22 个探针通过，`voxel` 暂缺。
- `shaders/rendering/` 的十二个循环逐个分类：只有大气光学厚度迁进库（`ogxAtmoSimpleScattering`），其余十一处是几何装配、材质采样或依赖宿主选项的阶段胶水，分类表见 `docs/rendering.md`。
- 生成器新增三维纹理句柄（`Sampler3D` / `Usampler3D`）与整数取格写法；库源码审计覆盖 `.slang`，生成文件的中文说明按比例检查。
- 手写核心从 4870 行增加到 7626 行，上限按决策记录上调到 8000 行；中文说明仍按 HOP 覆盖一半以上非空行。
- 2026-10-25 完成第三批：新增 `lpv` 模块，把 Eclipse 的光传播体积取样、编码、边缘淡出与合成搬进库，`rendering/lighting/lpv.glsl` 只剩纹理与越界接线；`sampling` 补上平滑过滤、阴影平滑过滤、最近点取样、旋转网格超采样与抗锯齿抖动序列；`math` 补上不夹紧映射、三分量极值、圆盘点列、螺旋采样与粗糙高光方向；`color` 补上 `Hejl`、`Hable`、`Reinhard`、`Lottes`、`Uchimura`、经济版电影曲线与标准 sRGB 编码；`post` 补上浮点与定点抖动、多边形光圈；`noise` 补上白噪声与三角噪声；`cloud` 补上降雨密度。生成 24 个模块，SPIR-V 24/24 通过。
- `docs/gfx-parity.md` 重写为 76 行逐项对照：未覆盖从 4 条降到 0 条，`PrintFloat` 与 `text_rendering` 按调试界面证据标为 MC 专用，剩余 15 条部分覆盖逐条写明宿主数据源。
- 手写核心从 7626 行增加到 8153 行，上限按决策记录上调到 8400 行。
- 2026-10-25 完成第四批：`docs/gfx-parity.md` 按源码重建，24 个模块逐项列出参考来源；原 15 条部分覆盖全部处理，11 条变为已覆盖（其中 4 条保留 MC 专用子项、2 条保留库内子项），4 条变为库内，部分与未覆盖都归零。海洋波形与泡沫、下界五群系配色、Eclipse 三段下界雾、labPBR 材质解码已进库并接到宿主；四季与时段雾、程序化雨点、阴影修补、水面高度/焦散、梯度旋度、体素索引纯算式进库，暂未接线。
- 只服务 Minecraft 的部分逐条给出参考行号与宿主声明位置，写在 `docs/gfx-parity.md` 第六节：手持光源与高光、材质编号掩码、手部屏幕阴影与手电筒、屏幕追踪与双边升采样、体素写入、调试叠加与编号表。
- 手写核心从 8153 行增加到 8717 行，上限按决策记录上调到 8800 行。
- 2026-10-26 测试世界重建为连续山谷湖盆场景：`assets/` 增加 CC0 草甸/泥土/岩石/湿沙/腐殖土/树皮贴图与 1K 全景天空，`terrain.py` 改为连续高度场，`vegetation.py` 生成树线、灌木、草丛、野花与岩石，`render.py` 使用三级 CSM、平面反射、TAA、自动曝光、景深、泛光与调色。1280×720 本机 Intel Arc 120 帧平均 23.2 毫秒（约 43.1 帧每秒），截图 `.dev/omni-gfx/world-photoreal.png`，与 NPS 公共领域照片的并排图 `.dev/omni-gfx/world-comparison.png`。**画面仍未达到照片级**：树冠是程序化团块、岸线与远山偏规整、水体反射低分辨率；体积云模块保留在库中，但测试世界改用 HDR 天空，理由与差距写入 `omni-gfx/docs/verification.md`。
- 2026-10-26 新增光影验证场景 `omni-gfx/examples/lighting`：简单湖盆、两种金属与三种电介质球、方块、石台、立石、水面、体积雾与体积云；太阳颜色取大气透过率，三级 CSM/PCSS 与接触阴影、半分辨率遮蔽与颜色反弹、平面反射与吸收/泡沫、六步阴影雾、TAA、泛光与 ACES/AgX。1280×720 本机 Intel Arc 120 帧平均 28.02 毫秒（约 35.7 帧每秒），截图 `.dev/omni-gfx/world-lighting.png`，与 Bierstadt Lake（CC0）和 Moraine Lake（Public Domain）的并排图 `.dev/omni-gfx/world-lighting-comparison.png`。云仍偏扁平的层积云，光柱很弱，详见 `omni-gfx/docs/verification.md`。
- 2026-10-26 验证边界：`omni-gfx/build.py check` 只审计测试世界实际编译的 GLSL；Python 示例与资源准备脚本不进入光影 ZIP，也不参与库注释比例。手写核心 9267 行，低于 9400 上限。
- 下一步：把库内的 Eclipse 程序化雨点、阴影修补、水面高度/焦散与四季函数接到光影选项（需要先定默认画面与选项命名）；为 `voxel` 补整数三维纹理探针；阶段 5（完整 SPIR-V 演示管线）与阶段 6（文档、许可证、示例与发布）。

## 十四、决策记录

| 日期 | 决定 |
| --- | --- |
| 2026-10-24 | 库名工作名 `omni-gfx`，放在 `shaders/` 旁边 |
| 2026-10-24 | 源代码用 Slang；MC 用生成的 GLSL，Vulkan 用 SPIR-V |
| 2026-10-24 | 复用优先，手写只做适配、组合、生成器 |
| 2026-10-24 | Iris 第一优先，Aperture/Vulkan 第二，其他引擎按需 |
| 2026-10-24 | 手写核心目标 ≤3000 行，冲刺 2000 行；生成/第三方不计 |
| 2026-10-24 | 本机没有 C++ 工具链，测试世界改用 Python + GLFW + PyOpenGL；不创建无法验证的 CMake 工程 |
| 2026-10-24 | GLSL 由固定降级表生成，不用 Slang 的 GLSL 后端；原因是后端输出 `#version 450`、函数改名并附带 `main()`，不能作为库引入 |
| 2026-10-24 | SPIR-V 由每模块探针生成，二进制不入仓库；`generated/spirv/manifest.json` 只在本机保留 |
| 2026-10-24 | 阶段三效果模块用程序化噪声替代参考实现的噪声贴图；大气长度单位用公里，保证 `float` 精度，调用方负责米到公里的换算 |
| 2026-10-24 | 手写核心上限从 3000 行上调到 5200 行：阶段三把九个效果模块的实现整体迁入 `omni-gfx/src`，原上限按旧范围制定 |
| 2026-10-24 | 效果迁移采用适配层：`shaders/gfx/` 保留原函数名与宿主开关，算式只留 `omni-gfx/src` 一份，避免同时改几百个调用点导致默认画面漂移 |
| 2026-10-25 | 手写核心上限从 5200 行上调到 8000 行：第二批把天气、表面、视差、行星、吸积盘、大气查表、体积云、体积雾、体素、放大与后期眩光整体迁入，中文说明按 HOP 覆盖一半以上非空行，行数随效果算法实际增长 |
| 2026-10-25 | 手写核心上限从 8000 行上调到 8400 行：第三批补上 `lpv` 模块、采样过滤与八处纯计算缺口，未覆盖项清零；上调只对应用户要求的“补缺或给出证据”，不靠删效果凑数 |
| 2026-10-25 | 手写核心上限从 8400 行上调到 8800 行：第四批把海洋、下界雾、材质解码与参考文件剩余纯算式迁入库，部分覆盖清零；上调对应实际迁入的算法行数，不删效果、不重复实现 |
| 2026-10-25 | 手写核心上限从 8800 行上调到 9400 行：新增函数级对照工具 `tools/parity.py` 与人工对照数据，并补入 `ogxHalton2/3`、`ogxRayBox*`、`ogxSquare`、`ogxLengthSquared`、`ogxSafeInvLength`、`ogxTriangleWave`、`ogxFma2`、`ogxSinCos`、`ogxRotate2` 十一个纯计算；上调对应工具与迁入函数，不删效果 |
| 2026-10-25 | 函数级缺口清零，手写核心 9261 行仍低于 9400 上限：采样器改为显式参数，云图、月亮与天空盒取像素都进库；21 条调试叠加改判 MC 专用并写明机制；`ogxFogFade` 只淡出散射色，修掉测试世界海天交界的断续黑线 |
| 2026-10-26 | 手写核心上限从 9400 行上调到 10600 行：新增严格函数对照 JSON、两个 profile 的生成与编译，以及 Eclipse 与 iterationT 的色调映射、AgX 配置、天空密度/相函数、云相函数与 TAA 取样端口；上调只对应实际迁入的参考算法与验证工具，不删效果 |
