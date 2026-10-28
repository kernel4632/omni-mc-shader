# Omni

<!-- stats:begin -->
当前统计：44 个生成模块（另有 4 个参考后端，共 48 个源模块）、94 个 Slang 源文件、14147 行生成 GLSL；函数对照 505 个，已迁入 404、MC 专用 101、缺失 0；严格对照 exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0。
<!-- stats:end -->

一个以共享配置、自定义画面和按需性能开销为目标的 Minecraft Java 光影项目。

**当前为开发代码审查阶段，版本以 `VERSION` 为准。** 已接入基础世界绘制与完整效果流程、四套预设、配置分享及开发自动化。
本轮没有启动 Minecraft；独立测试世界已用生成库出图并记录帧时，游戏内画面仍未验证。
代码接入不等于画面正确，世界显示、性能和兼容性均未验证。先前“只有天空”的游戏异常不能因离线通过就认定已修复。
独立图形库 `omni-gfx/` 已完成阶段 0–3 的第一批效果迁移：Slang 基础模块与噪声、大气、体积云、水面、雾五个效果模块，生成的 GLSL、SPIR-V 探针与不启动 Minecraft 的程序化测试世界；当前只在独立 OpenGL 环境验证，游戏内画面仍未验证。

## 开始开发

需要 Python 3.12+、Git；项目内图形调试环境另外需要 Windows x64。

```powershell
python dev.py setup --graphics
python build.py check
python -m unittest discover -s tests
python build.py build
```

`setup` 安装锁定版本的 GLSL 检查器和 GitHub 工作流检查器。
`--graphics` 另外下载便携 RenderDoc，并生成可导入启动器的 Fabric 调试整合包。
工具都放在 `.dev/`，开发依赖放在 `.venv/`。不需要安装整套效果模板。

本机已配置的专用实例可直接运行 `.venv\Scripts\python.exe game.py launch`。
它复用已有的游戏库，游戏目录独立放在 `.dev/minecraft`，禁用多人游戏。
换电脑时重新配置路径，方法见开发文档。

安装好 Python 图形测试依赖后运行：

```powershell
uv venv --python 3.12
uv pip sync requirements-dev.lock
.venv\Scripts\python.exe tests\gpu.py
```

产物在 `dist/`：光影 ZIP、预设 ZIP 和 `SHA256SUMS.txt`。
游戏中的光影包使用 `Omni-版本号.zip`，放入对应实例的 `shaderpacks/`。

切换光影预设会重建整条管线，第一次重建要编译全部程序，主线程会停顿几秒到十几秒；在服务器里请先暂停或退回主菜单再切换，避免因为长时间无响应被踢出。切换回已经编译过的配置会走缓存，明显更快。

## 去哪里修改

| 要做什么 | 打开哪里 |
| --- | --- |
| 改阴影、水面、云等效果 | 选项、参数换算与阶段入口都在 `shaders/effects/<页>/`，纯公式在 `omni-gfx/src/` |
| 改通用库算法 | `omni-gfx/src/` 的 Slang 源；生成物在 `shaders/omni-gfx/`，不手改 |
| 改不启动 Minecraft 的测试世界 | `omni-gfx/examples/world/` |
| 生成 GLSL、SPIR-V 或跑等值测试 | `python omni-gfx/build.py` |
| 接入新的加载器输入 | `shaders/bind/` 只做输入到普通数值的适配 |
| 改绘制顺序或程序入口 | `shaders/rendering/` 中对应流程与 `programs.json` |
| 改中间画面约定 | `shaders/rendering/buffers.glsl` |
| 改加载器设置 | `shaders/rendering/pipeline.properties` |
| 增加一套可分享配置 | `presets/` 中新增 `.properties` |
| 改选项菜单生成 | `options.py` |
| 改检查、打包、同步 | `build.py` |
| 改开发工具安装 | `dev.py` 和 `dev-tools.lock.json` |
| 改独立游戏启动 | `game.py` |
| 改版本号 | `VERSION` |
| 查实际能力与限制 | `docs/parity.md` 与 `docs/eclipse-parity.md` |
| 检查中文注释与未实现标记 | `audit.py` |
| 导入、导出、对比、重置配置 | `config.py` 命令入口 |

## 文档

- [开发、调试与发布](docs/development.md)
- [移植合同与分片状态](docs/parity.md)
- [Eclipse 效果对照](docs/eclipse-parity.md)
- [效果到 omni-gfx 函数的对照表](docs/gfx-parity.md)
- [绘制流程](docs/rendering.md)
- [兼容性与验证状态](docs/compatibility.md)
- [性能测量方法](docs/performance.md)
- [性能与重载优化执行计划](docs/performance-plan.md)
- [文件结构与共用层重构计划](docs/structure-plan.md)
- [omni-gfx 通用图形库计划](docs/omni-gfx-plan.md)
- [omni-gfx 使用与构建](omni-gfx/README.md)
- [omni-gfx 架构](omni-gfx/docs/architecture.md)
- [omni-gfx 验证记录](omni-gfx/docs/verification.md)
- [可复用库与框架](docs/libraries.md)
- [算法参考与可复用实现](docs/references.md)
- [项目开发约定](AGENTS.md)

## 参考资料

- [Iris 开发文档](https://shaders.properties/current/reference/overview/)
- [Iris 调试说明](https://github.com/IrisShaders/docs/blob/main/src/content/docs/current/Reference/Miscellaneous/debugging_shaders.mdx)
- [第三方来源与许可](THIRD_PARTY.md)：当前没有随包的第三方库，云密度用 iterationT 的预计算噪声贴图；参考包原件未复制。
- [RenderDoc](https://renderdoc.org/) 与 [GFX-Debuggers](https://modrinth.com/mod/gfx-debuggers)

Minecraft 本体由玩家通过自己的启动器合法安装。调试整合包只记录模组下载信息。
