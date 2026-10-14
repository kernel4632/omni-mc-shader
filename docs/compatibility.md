# 兼容性与验证

本文件区分准备目标与真实验证，不能根据下载文件名推断已经兼容。

## 当前开发目标

- Minecraft Java；初始入口使用 GLSL 330 compatibility。
- 日常开发优先使用 Iris；OptiFine 的实际加载尚未验证。
- 专用调试整合包的精确版本见 `dev-tools.lock.json`。
- 检查脚本支持 Windows / Linux x64 与 Python 3.12+。

## 验证状态

| 项目 | 状态与边界 |
| --- | --- |
| 本地选项、引用和打包检查 | 由 `python build.py check` 验证 |
| 本地构建工具回归测试 | 由 `python -m unittest discover -s tests` 验证 |
| 真实显卡 final 绘制 | Intel Arc 核显：正常画面、深度与坐标三个视图通过 |
| NVIDIA RTX 5060 | 设备存在；尚未指定该设备完成绘制测试，未验证 |
| Minecraft / Iris 场景绘制 | 未验证，不能用离线或独立 OpenGL 测试代替 |
| RenderDoc 游戏捕获 | 便携程序已安装并验证官方签名；游戏捕获未验证 |
| OptiFine | 未验证 |
| AMD、macOS、其他游戏版本 | 未验证 |
| 第三方模组与资源包 | 未验证 |

本机 GPU 报告放 `.dev/reports/gpu.json`，包含实际设备与驱动的 OpenGL 信息。
GitHub 自动检查的结果以 Actions 运行记录为准。

## 后续适配记录

每次验证记录：游戏和加载器版本、显卡及驱动、预设、维度、天气、资源包、相关模组、结果。
至少覆盖主世界、下界和末地，再扩大到其他维度与常见模组组合。
出现错误时保留具体场景和日志，修复后用相同条件复测。
