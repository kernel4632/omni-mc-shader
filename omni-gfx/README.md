# omni-gfx

Omni 的独立图形库。手写算法只维护 Slang 源，构建时生成 Minecraft 光影可直接 `#include` 的 GLSL 330，并用同一份源生成 SPIR-V 作为编译验证产物。

当前有 48 个模块，覆盖数学、颜色、采样、噪声、相机、表面、水面、大气、云、雾、阴影、体素、全局光、反射、后期、抗锯齿、天气与末地。测试世界直接使用生成的 GLSL，不启动 Minecraft 也能出图、截图和记录帧时。函数级覆盖对照见 `docs/gfx-functions.md`。

最近一次 1280×720 固定机位：户外测试世界平均 23.0 毫秒（约 43.5 帧每秒），截图 `.dev/omni-gfx/world-realistic.png`，帧时 `.dev/omni-gfx/world-realistic.json`；光影验证场景最新一轮平均 15.76 毫秒（约 63.4 帧每秒），截图 `.dev/omni-gfx/world-lighting-v4.png`，帧时 `.dev/omni-gfx/perf-lighting-v4.json`。帧时会随本机同时运行的程序波动，详细记录在 `docs/verification.md`。

## 目录

| 路径 | 用途 |
| --- | --- |
| `src/` | Slang 源文件，按效果分文件夹，唯一手写算法来源 |
| `src/<效果>/` | 复杂效果的主体与变体模块，例如 `cloud/layers.slang`、`reflection/wsr.slang` |
| `src/<模块>/` | 同一模块的算法子文件，例如 `cloud/layers/shape.slang`；生成时内联进主模块，不单独生成 GLSL |
| `shaders/omni-gfx/` | 自动生成的 GLSL，目录与模块一致，唯一产物位置 |
| `generated/spirv/` | 本机生成的 SPIR-V 与清单，二进制不提交 |
| `examples/world/` | 不启动 Minecraft 的程序化测试世界 |
| `examples/lighting/` | 光影链路验证场景 |
| `tests/` | GPU 等值测试、Slang 编译探针、离线回归 |
| `tools/` | 生成器、编译器封装、统计与 OpenGL 工具 |
| `docs/` | 架构与验证记录 |

## 一条命令生成 GLSL

```powershell
python omni-gfx/build.py generate
python omni-gfx/build.py check
```

`generate` 只写入 `shaders/omni-gfx/`，Iris 直接读取这一份。主模块里的子文件 `#include` 会在生成时按顺序内联，玩家看到的仍是每个模块一个 `.glsl`：

```glsl
// 通用库大气模块：天空散射与空气透视由 Slang 源生成。
#include "/omni-gfx/atmosphere/atmosphere.glsl"

vec3 sky = ogxAtmosphereSky(ogxAtmosphereEarth(), 0.03, viewDir, sunDir, 8);
```

## 生成 SPIR-V

需要 Slang 编译器。首次可以显式下载到 `.dev/tools`，二进制与缓存都不进仓库：

```powershell
python omni-gfx/build.py spirv --download
```

之后重新编译全部探针：

```powershell
python omni-gfx/build.py spirv
```

当前 48 个模块的探针全部通过，编译结果在 `omni-gfx/generated/spirv/`，`manifest.json` 记录编译器版本、大小与 SHA-256。探针只证明模块能编译成 SPIR-V，不是可直接运行的 Vulkan 管线。

## 运行测试世界

需要 Python 3.12、GLFW 与 PyOpenGL（项目虚拟环境已包含）。不需要 Minecraft。

```powershell
# 固定机位，渲染 120 帧，保存截图与帧时
.venv\Scripts\python.exe omni-gfx\examples\world\render.py --frames 120 --warmup 30 --screenshot .dev/omni-gfx/world-realistic.png --perf .dev/omni-gfx/world-realistic.json

# 可移动相机：WASD 移动，空格与左 Ctrl 升降，鼠标转向，退出键结束，截图键保存
.venv\Scripts\python.exe omni-gfx\examples\world\render.py --window

# 光影链路验证场景
.venv\Scripts\python.exe omni-gfx\examples\lighting\render.py --frames 120 --warmup 40 --screenshot .dev/omni-gfx/world-lighting-v4.png --perf .dev/omni-gfx/perf-lighting-v4.json
```

输出默认放在 `.dev/omni-gfx/`。帧时记录包含设备、分辨率、地形与水面三角形数、阴影贴图尺寸、云的步数与分辨率、时间累积权重与平均亮度。

## GPU 等值测试

```powershell
.venv\Scripts\python.exe omni-gfx\tests\equivalence.py
```

同一个片段着色器同时调用旧 `gfx_` 库与新 `ogx_` 库，逐像素比较浮点输出。当前 26 个用例全部逐位一致，结果写入 `.dev/omni-gfx/equivalence.json`。

## 代码量

```powershell
python omni-gfx/build.py count
```

手写核心只统计 `src/`、`tools/` 与 `tests/`，上限以 `omni-gfx/tools/count.py` 为准；测试世界单列，生成 GLSL 与第三方代码分开统计。

## 函数级覆盖对照

```powershell
python omni-gfx/build.py parity
```

从 `references/iterationT/shaders/Lib` 与 `references/Eclipse/shaders/lib` 逐个函数扫描，写到 `docs/gfx-functions.md`：505 个函数里已迁入 401、MC 专用 104、缺失 0、调试输出 0。人工对照数据在 `tools/parity_map.json`，指向不存在的函数会让命令直接失败。

严格结论以 `tools/parity_report.json` 为准：

```powershell
python omni-gfx/build.py strict-parity
python omni-gfx/build.py profiles
```

`strict-parity` 读取 `tools/strict_review.json`，生成 `tools/parity_report.json` 与 `docs/gfx-functions-strict.md`；状态只允许 exact、approximate、mc_glue、missing。`profiles` 分别生成 iterationT 与 Eclipse 的 `profile.frag`，并用本机 `glslang` 独立编译。当前 exact 474、approximate 0、reference_broken 5、missing 0、mc_glue 26，剩下的 mc_glue 只有程序入口、标题、文字渲染与群系属性表。

## 完整验证

```powershell
python build.py verify
python build.py compile
```

`verify` 在十秒预算内完成生成、工具测试、关键光影检查与打包；`compile` 用两种代表配置和基础/开远景环境编译全部程序。当前口径：519 个选项、269 个入口、280 组唯一程序、160 个测试。游戏内画面、菜单、性能与其他显卡仍未验证。

## 许可证

本库许可证尚未由项目所有者确定，详见 `LICENSE`。在明确选择并写入正式许可证之前，本目录保留所有权利，不构成开源或再分发授权。**发布前必须补齐许可证**，并逐项核对自有代码、参考算法与常数、开发期工具以及生成产物的授权范围；不能沿用参考包的许可证，也不能因为仓库私有就跳过这一步。开发期下载的 Slang、GLFW 与 PyOpenGL 不随库分发。

## 已知边界

- 测试世界是风格化近似，不是物理正确的大气、云或水体；大气是单次散射，云是单层程序化体积云，水面反射是屏幕空间近似。
- 时间抗锯齿已经接入次像素抖动与历史重投影；海天交界那条断续暗线已修掉，根因是淡出雾时把透过率一起乘小，现在只淡出散射与遮挡。
- 还没做：完整级联阴影跟随相机、屏幕空间全局光的颜色渗透、真实贴图与法线贴图。
- SPIR-V 只是模块探针，Vulkan/Aperture 的实际管线接入还没有开始。
- 本机没有 C++ 工具链，演示程序使用 Python + GLFW + PyOpenGL；没有引入无法验证的 CMake 工程。
- Minecraft 内只验证了离线编译；新库接入后的游戏画面尚未验证。
