# 性能测量

效果代码已接入，没有性能结论。本轮不运行游戏或采样；目录结构和编译通过不等于高帧率。

## 每次测量固定什么

- 显卡、驱动、游戏版本与加载器版本。
- 窗口分辨率、渲染距离、模拟距离和资源包。
- 世界、坐标、朝向、时间和天气。
- 光影选项和相关模组。
- 关闭垂直同步和帧率上限，在地形与着色器加载稳定后测量。

正式比较时保留一套固定测试世界，存档放 `.dev/minecraft/saves/`。
至少包含森林、水面、洞穴和大量透明物体场景。

## 记录什么

同时记录平均帧率、较慢帧表现与每帧耗时，避免只看一次瞬时 FPS。
例如 100 FPS 约为每帧 10 毫秒。比较同一场景下开关一个效果的差值。
测量方法和采样时长必须一致，区分 CPU 等待与 GPU 绘制耗时。

| 日期 | 版本 | 设备与场景 | 配置 | 每帧耗时 | 结论 |
| --- | --- | --- | --- | --- | --- |
| — | — | 尚未测量 | — | — | 暂无性能结论 |

## 优化约定

先测出耗时位置，再改变算法或数据安排，并在相同条件下复测。
关闭效果时尽量移除对应编译代码和独立绘制步骤。
额外缓冲能否释放取决于加载器和实际依赖，需要实际观察显存，不能仅凭开关推断。
RenderDoc 主要用于观察绘制步骤与资源；需要详细 NVIDIA 性能计数时再使用 Nsight。

## 真实采样工具

`game.py sample` 调用 [PresentMon 官方控制台](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)，按明确进程号保存原始 CSV，不自动提权、不停止其他采样。采样器由用户从官方发行包准备在 `.dev/tools/`，不随光影分发；本版没有下载或运行它。

```powershell
python game.py sample --presentmon .dev/tools/presentmon/PresentMon.exe --pid 12345 --seconds 30 --context .dev/performance-context.json
```

上下文 JSON 必须全部填写字符串字段：`device`（显卡）、`driver`（驱动）、`scene`（世界与固定坐标／天气）、`resolution`、`preset`、`minecraft`、`iris`。必须确认进程是专用测试实例。CSV 与汇总写 `.dev/reports/performance/`，已有 `frames.csv` 时拒绝覆盖，需要先归档。至少二十个有效帧且只有一个交换链，拒绝无穷、非数、零或负帧间隔。

汇总显示平均帧耗时、平均帧率和第九十九百分位慢帧。该指标是 `MsBetweenPresents`，包含处理器等待和呈现，不是单个效果 GPU 时间。显存、GPU 分项耗时和跨设备优化仍需另行真实捕获。
