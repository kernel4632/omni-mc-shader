# 开发、调试与发布

## 准备环境

Python 3.12+ 用于构建；Windows / Linux x64 可自动安装检查工具。
完整便携图形环境目前面向 Windows x64。

```powershell
python dev.py setup --graphics
python dev.py doctor
```

下载来源、版本和校验值在 `dev-tools.lock.json`。
GLSL 编译器、工作流检查器和 RenderDoc 都安装到 `.dev/tools/`。
下载先校验再解压，RenderDoc 另外检查官方发布者签名。
重复执行会复用同版本安装，不修改系统 PATH。

图形测试依赖安装到 `.venv/`，使用 `requirements-dev.lock` 中的版本与哈希。
更新依赖时先改 `requirements-dev.in`，再运行：

```powershell
uv pip compile requirements-dev.in --generate-hashes --output-file requirements-dev.lock
```

## 游戏内调试

`setup --graphics` 生成 `.dev/Omni-debug.mrpack`，其中记录锁定的
Minecraft、Fabric、Iris、Sodium 和 GFX-Debuggers 版本。
将它导入支持 Modrinth 整合包的启动器，使用自己的账号启动。

推荐让专用实例使用项目的 `.dev/minecraft` 作为游戏目录。
如果启动器导入到其他目录，将专用实例的游戏目录指向这里，或手动使用构建产物。
本体、Java、登录和资源由启动器管理。当前模组版本不代表支持其他 MC 版本。

也可使用 `game.py` 复用本机已有的 Fabric 安装进行独立测试：

```powershell
.venv\Scripts\python.exe game.py configure --minecraft-dir "D:/Games/.minecraft" --version "已安装的Fabric版本目录名" --java "D:/Java/bin/java.exe" --isolated-java
.venv\Scripts\python.exe game.py launch
```

个人路径只保存在 `.dev/game.local.json`。`--isolated-java` 将完整 Java 复制到项目内，
使用 `omni-java` 进程名方便与玩家的游戏区别。开发实例采用库提供的测试身份，禁用多人游戏。
它不读取原实例的登录数据、设置或存档。该方式只用于本地开发验证。
如果游戏版本不是工具锁定的版本，应先匹配对应模组，再运行。

```powershell
python build.py sync
python dev.py watch
```

`sync` 将有效构建同步为 `.dev/minecraft/shaderpacks/Omni-dev.zip`。
`watch` 在源码变化后自动检查并同步，失败时保留上一份游戏包。
游戏里仍需按光影重载键；Iris 默认是 `R`，具体以按键设置为准。

专用实例默认启用 Iris 调试选项。在光影设置的“开发调试”中可选择：

| 值 | 内容 |
| --- | --- |
| 0 | 原始场景颜色 |
| 1 | 原始深度；大多数远处像素接近白色 |
| 2 | 屏幕坐标；红色向右增加，绿色向上增加 |

查看游戏实例的 `logs/latest.log` 定位加载错误。
Iris 报错行号可能对应实例内 `patched_shaders/` 的处理后代码。
不要直接把该行号当作源文件行号。

## 捕获一帧

```powershell
python dev.py renderdoc
```

在 GFX-Debuggers 启动弹窗中选择项目内的 RenderDoc。
然后在 RenderDoc 的 `File → Attach to Running Instance` 选择该专用游戏进程。
捕获一帧后查看纹理和绘制步骤。捕获文件 `.rdc` 放 `.dev/captures/`。
未实际完成捕获时，只能说明安装完成，不能声称游戏捕获验证通过。

本机已配置 `game.py` 时，可运行 `.venv\Scripts\python.exe game.py launch --capture`，
直接由项目内 RenderDoc 启动开发游戏，再连接该测试进程进行捕获。

Nsight Graphics 作为 NVIDIA 性能分析的后续工具，当前没有自动安装。
它需要厂商提供的安装流程；当前使用 RenderDoc 查看绘制资源，性能先按固定场景测量。

## 自动检查

```powershell
python build.py generate
python build.py check
python -m unittest discover -s tests
python build.py build
.venv\Scripts\python.exe tests\gpu.py
```

`check` 检查版本、入口配对、引用路径、循环引用、选项范围、预设取值、生成文件，
并使用 glslang 编译与链接默认配置、全部预设和每个选项单独改变的配置。
它不穷举全部选项组合。新增复杂效果时，应增加有代表性的组合预设。
actionlint 同时检查 GitHub 工作流语法。

`tests/gpu.py` 在本机 OpenGL 3.3 兼容环境中编译实际 final 入口，并检查三个调试视图的像素。
报告位于 `.dev/reports/gpu.json`，不作为 Minecraft/Iris 集成验证。
图形测试不能在没有桌面显卡环境的 GitHub 普通 runner 上保证运行，因此 CI 执行离线检查。

## 选项唯一来源

以下代码写在所属效果文件，不能复制到中央配置表：

```glsl
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"水波强度","en_us":"Wave strength"},"slider":true}
#define WATER_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
```

`@option` 必须紧贴下一行的原生定义。默认值与范围只从定义读取。
布尔选项使用 `#define WATER_ENABLED`，默认关闭使用 `//#define WATER_ENABLED`。
每条说明提供 `zh_cn` 和 `en_us`；需要帮助文字时增加同样带两种翻译的 `description`。
每个有选项的效果定义一次 `@effect` 菜单名称。

构建工具自动收集 `effects/**/*.glsl` 和 `presets/*.properties`，生成：

- `shaders/shaders.properties`：绘制设置、菜单、滑块和预设。
- `shaders/lang/zh_cn.lang` 与 `en_us.lang`：菜单翻译。

生成文件不提交。新克隆仓库运行 `setup` 或 `generate` 后再加载开发目录。
打包工具会先生成并检查，发布 ZIP 不依赖玩家运行 Python。

## Git 与版本

主分支是 `main`，提交格式是 `类型(范围): 中文描述`。
例如 `feat(water): 增加水波强度选项`。
每次提交前检查状态、差异和最近记录，只提交对应工作。

`VERSION` 是唯一当前版本来源。`CHANGELOG.md` 保存历史变化。
尚未进入第一版效果开发，当前使用开发准备版本。
正式版本使用 `x.y.z`；预发布版本使用 `x.y.z-dev.N` 等格式。

发布前修改 `VERSION` 和更新记录，通过检查并提交，再推送对应标签：

```powershell
git push origin main
git tag -a v0.0.0-dev.1 -m "开发准备版本"
git push origin v0.0.0-dev.1
```

示例标签只用于说明；实际标签必须等于 `v` 加上当前 `VERSION`，且没有被使用过。
标签推送自动执行发布工作流，校验失败时中止。
通过后创建 GitHub Release，上传光影 ZIP、预设 ZIP 与 SHA256 校验文件。
带后缀的版本自动标记为预发布。工作流使用 GitHub 自带令牌，无需保存个人令牌。

也可在 GitHub Actions 手动运行“发布光影版本”，填写已经推送的标签。
默认勾选创建草稿，用于检验发布流程。不要重复发布同一标签。

## 可重复打包

ZIP 的文件顺序、权限和时间戳固定，相同源码在相同工具环境下应得到相同校验值。
只收集允许的光影资源后缀；不包含 `.dev/`、个人路径、游戏存档或登录数据。
预设单独打包，说明文件记录格式版本和目标光影版本。

## 第三方代码

当前未导入 Base-330 或其他光影效果代码。
第一版参考代码由用户指定。采用前确认许可证，并保留要求的版权声明。
项目本身的许可证等待用户决定，不从工具的许可证推导。
