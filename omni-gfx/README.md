# omni-gfx

Omni 的独立图形库。手写算法只维护 Slang 源，构建时生成 Minecraft 光影可直接 `#include` 的 GLSL 330，并用同一份源生成 SPIR-V 作为编译验证产物。

当前完成阶段 0–3 的核心部分：构建链、`math` / `color` / `sampling` 三个基础模块，以及 `noise` / `atmosphere` / `cloud` / `water` / `fog` 五个效果模块。测试世界已经改为直接使用生成的 GLSL，能在不启动 Minecraft 的情况下出图、截图和记录帧时；场景包含带材质与逐角遮蔽的体素地形、树木与草叶、三级方向光 PCSS 阴影、体积云与时间累积、屏幕空间反射与折射、空气透视与时间抗锯齿。函数级覆盖对照见 `docs/gfx-functions.md`。

最近一次 1280×720 固定机位：平均 24.1 毫秒（约 41 帧每秒），截图 `.dev/omni-gfx/world-realistic.png`，帧时 `.dev/omni-gfx/perf-realistic.json`。

## 目录

| 路径 | 用途 |
| --- | --- |
| `src/` | Slang 源文件，唯一手写算法来源 |
| `generated/glsl/` | 自动生成的 GLSL，与 `shaders/omni-gfx/` 内容相同 |
| `generated/spirv/` | 本机生成的 SPIR-V 与清单，二进制不提交 |
| `examples/world/` | 不启动 Minecraft 的程序化测试世界 |
| `tests/` | GPU 等值测试、Slang 编译探针、离线回归 |
| `tools/` | 生成器、编译器封装、统计与 OpenGL 工具 |
| `docs/` | 架构与验证记录 |

## 一条命令生成 GLSL

```powershell
python omni-gfx/build.py generate
python omni-gfx/build.py check
```

`generate` 写入两处：`omni-gfx/generated/glsl/` 和 `shaders/omni-gfx/`。Iris 只读取后者：

```glsl
// 通用库大气模块：天空散射与空气透视由 Slang 源生成。
#include "/omni-gfx/atmosphere.glsl"

vec3 sky = ogxAtmosphereSky(ogxAtmosphereEarth(), 0.03, viewDir, sunDir, 8);
```

## 生成 SPIR-V

需要 Slang 编译器。首次可以显式下载到 `.dev/tools`，二进制与缓存都不进仓库：

```powershell
python omni-gfx/build.py spirv --download
```

编译结果在 `omni-gfx/generated/spirv/`，`manifest.json` 记录编译器版本、大小与 SHA-256。探针只证明模块能编译成 SPIR-V，不是可直接运行的 Vulkan 管线。

## 运行测试世界

需要 Python 3.12、GLFW 与 PyOpenGL（项目虚拟环境已包含）。不需要 Minecraft。

```powershell
# 固定机位，渲染 120 帧，保存截图与帧时
.venv\Scripts\python.exe omni-gfx\examples\world\render.py --frames 120 --warmup 30 --screenshot .dev/omni-gfx/world-realistic.png --perf .dev/omni-gfx/perf-realistic.json

# 可移动相机：WASD 移动，空格与左 Ctrl 升降，鼠标转向，退出键结束，截图键保存
.venv\Scripts\python.exe omni-gfx\examples\world\render.py --window
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

手写核心只统计 `src/`、`tools/` 与 `tests/`，上限以 \omni-gfx/tools/count.py\ 为准；测试世界单列，生成 GLSL 与第三方代码分开统计。

## 函数级覆盖对照

```powershell
python omni-gfx/build.py parity
```

从 `references/iterationT/shaders/Lib` 与 `references/Eclipse/shaders/lib` 逐个函数扫描，写到 `docs/gfx-functions.md`：505 个函数里已迁入 378、MC 专用 127、缺失 0、调试输出 0。人工对照数据在 `tools/parity_map.json`，指向不存在的函数会让命令直接失败。

## 已知边界

- 测试世界是风格化近似，不是物理正确的大气、云或水体；大气是单次散射，云是单层程序化体积云，水面反射是屏幕空间近似。
- 本机 1280×720 的 120 帧记录为平均 23.0 毫秒、中位 23.2、95 分位 29.5，约 43.5 帧每秒；帧时随本机同时运行的其他程序波动，同一天从 21 到 34 毫秒都出现过。
- 时间抗锯齿已经接入次像素抖动与历史重投影；海天交界那条断续暗线已修掉，根因是淡出雾时把透过率一起乘小，现在只淡出散射与遮挡。
- 还没做：完整级联阴影跟随相机、屏幕空间全局光的颜色渗透、真实贴图与法线贴图。
- SPIR-V 只是模块探针，Vulkan/Aperture 的实际管线接入在阶段 5。
- 本机没有 C++ 工具链，演示程序使用 Python + GLFW + PyOpenGL；没有引入无法验证的 CMake 工程。
- Minecraft 内只验证了离线编译；新库接入后的游戏画面尚未验证。

## 许可证

本库许可证尚未由项目所有者确定，详见 `LICENSE`。开发期下载的 Slang、GLFW 与 PyOpenGL 不随库分发。

## 严格对照与两个 profile

\\powershell
python omni-gfx/build.py strict-parity
python omni-gfx/build.py profiles
\\n
\strict-parity\ 读取 \	ools/strict_review.json\，生成 \	ools/parity_report.json\ 与 \docs/gfx-functions-strict.md\；状态只允许 exact、approximate、mc_glue、missing。\profiles\ 分别生成 iterationT 与 Eclipse 的 \profile.frag\，并用本机 \glslang\ 独立编译。严格统计以报告为准，当前仍有 approximate 与 missing。
