# Omni

一个以共享配置、自定义画面和按需性能开销为目标的 Minecraft Java 光影项目。

**当前为开发代码审查阶段，版本以 `VERSION` 为准。** 已接入基础世界绘制与完整效果流程、四套预设、配置分享及开发自动化。
本轮只执行离线编译与 Python 测试，没有启动 Minecraft 或运行显卡视觉测试。
代码接入不等于画面正确，世界显示、性能和兼容性均未验证。先前“只有天空”的游戏异常不能因离线通过就认定已修复。

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

## 去哪里修改

| 要做什么 | 打开哪里 |
| --- | --- |
| 改阴影、水面、云等效果 | `shaders/effects/` 中同名文件 |
| 改绘制顺序或程序入口 | `shaders/rendering/` 中对应流程与 `programs.json` |
| 改中间画面约定 | `shaders/rendering/buffers.glsl` |
| 改加载器设置 | `shaders/rendering/pipeline.properties` |
| 增加一套可分享配置 | `presets/` 中新增 `.properties` |
| 改选项菜单生成 | `options.py` |
| 改检查、打包、同步 | `build.py` |
| 改开发工具安装 | `dev.py` 和 `dev-tools.lock.json` |
| 改独立游戏启动 | `game.py` |
| 改版本号 | `VERSION` |
| 查实际能力与限制 | `docs/capabilities.md` |
| 检查中文注释与未实现标记 | `audit.py` |
| 导入、导出、对比、重置配置 | `options.py` 命令入口 |

## 文档

- [开发、调试与发布](docs/development.md)
- [绘制流程](docs/rendering.md)
- [兼容性与验证状态](docs/compatibility.md)
- [性能测量方法](docs/performance.md)
- [代码能力与验证边界](docs/capabilities.md)
- [项目开发约定](AGENTS.md)

## 参考资料

- [Iris 开发文档](https://shaders.properties/)
- [Iris 调试说明](https://github.com/IrisShaders/docs/blob/main/src/content/docs/current/Reference/Miscellaneous/debugging_shaders.mdx)
- [第三方来源与许可](THIRD_PARTY.md)：云密度直接采用固定版本的 Ashima 噪声，保留 MIT 原文；参考包原件未复制。
- [RenderDoc](https://renderdoc.org/) 与 [GFX-Debuggers](https://modrinth.com/mod/gfx-debuggers)

Minecraft 本体由玩家通过自己的启动器合法安装。调试整合包只记录模组下载信息。
