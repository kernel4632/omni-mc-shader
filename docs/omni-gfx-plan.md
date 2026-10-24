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

- 手写核心 **≤3000 行**，冲刺 2000 行；
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
- 手写核心代码 ≤3000 行（不含生成和第三方）；
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
- 生成库已接入 `shaders/rendering/color/post_tonemap.glsl`，`composite14` 的 ACES / AgX / 无压缩三条曲线改为调用 `ogx` 函数；离线全量编译 280 组程序通过。
- GPU 等值测试 26/26 通过，最大绝对差 0；测试世界截图与帧时记录在 `.dev/omni-gfx/`，详见 `omni-gfx/docs/verification.md`。
- 未验证：Minecraft 游戏内画面、Vulkan/Aperture 运行时、其他显卡、交互窗口逐项手动操作。
- 下一步：阶段 3，按效果模块迁移大气、云、雾、水、阴影、GI、反射、后期与抗锯齿，逐项用同一测试世界固定机位与旧实现比较。
- 阶段 1 的贴图过滤函数（双三次采样）仍留在旧 `shaders/gfx/`，需要先设计显式纹理接口再迁移。

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
