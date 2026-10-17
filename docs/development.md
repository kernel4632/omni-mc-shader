# 开发、调试与发布

## 快速检查

日常完整自动检查只运行 `python build.py verify`：先生成，再用两个并行任务跑工具测试与关键光影检查，最后打包。整个命令有十秒预算，超时结束检查与子进程并报错，不继续后台扫描。

关键光影检查包含全树“选项是否接入计算”硬检查（发现未接线直接报错）、中文注释审计、全部入口的来源与引用边界检查，以及一小组编译探针：主世界 5 个轻量程序 `gbuffers_terrain`、`shadow`、`final`、`setup`、`shadowcomp` 编默认配置与基础环境，其中 `gbuffers_terrain`、`shadow`、`setup`、`shadowcomp` 另编全高配置与开远景环境，共 9 组唯一程序、约 7 秒，测试全跑（当前 120 个、0 跳过）。发现具体逻辑问题时针对受影响路径验证，不以扩大扫描数量代替代码审查或游戏证据。

`python build.py check` 做同样的只读检查（含编译探针），不跑测试、不打包；`python build.py compile`（放宽到 300 秒）做完整离线编译：全部程序 × 两种代表配置 × 基础与开远景两组环境，约两分钟，用于发布前和移植期的人工门禁。

Actions 在 Ubuntu 执行一次同样的命令并上传可下载包，新提交自动取消过时任务。GitHub 排队、工具下载和产物上传受平台与网络影响，不包含在十秒检查预算内。

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
游戏里仍需按光影重载键；默认连按两次 `K`，具体以按键设置为准。

专用实例默认启用 Iris 调试选项。在光影设置的“开发调试”中可选择：

| 值 | 内容 |
| --- | --- |
| 0 | 正常画面（关闭时与 iterationT 一致） |
| 1 | 几何法线 |
| 2 | 深度；大多数远处像素接近白色 |
| 3 | 光照图；红色为方块光、绿色为天光 |

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

`check` 是只读检查，不跑测试、不打包：检查版本、阶段配对（包括几何、计算、细分）、引用路径、循环引用、选项范围、预设取值、生成文件、全树“选项是否接入计算”硬检查、有效中文注释与运行依赖白名单，
并使用 glslang 编译一小组探针：主世界 5 个轻量程序 `gbuffers_terrain`、`shadow`、`final`、`setup`、`shadowcomp` 编默认配置与基础环境，其中 `gbuffers_terrain`、`shadow`、`setup`、`shadowcomp` 另编全高配置与开远景环境，共 9 组唯一程序。基础加载器与 Iris、DH 专有分支分别离线检查。
相同展开源码只链接一次；不穷举每项选项的每个取值或全部预设组合。`#line` 数字编号映射回原始源码路径与行号，循环引用保留完整链。
完整离线编译改用 `python build.py compile`（全部程序 × 两种代表配置 × 基础与开远景两组环境，约两分钟）。
actionlint 同时检查 GitHub 工作流语法。

`tests/gpu.py` 在本机 OpenGL 3.3 兼容环境中链接全部基础程序，并检查最终深度与坐标调试像素。没有覆盖完整几何画面或远景加载器集成，本轮未运行。
报告位于 `.dev/reports/gpu.json`，不作为 Minecraft/Iris 集成验证。
图形测试不能在没有桌面显卡环境的 GitHub 普通 runner 上保证运行，因此 CI 执行离线检查。

## 选项唯一来源

以下代码写在所属效果文件，不能复制到中央配置表。普通效果用原生 `#define`；Iris加载器白名单中的 `const`（例如阴影分辨率和阴影距离）使用字面量和紧邻范围，不能用宏替代：

```glsl
// @effect {"label":{"zh_cn":"水面","en_us":"Water"}}
// @option {"label":{"zh_cn":"水波强度","en_us":"Wave strength"},"slider":true}
#define WATER_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
```

`@option` 必须紧贴下一行的原生定义。默认值与范围只从定义读取。
布尔选项使用 `#define WATER_ENABLED`，默认关闭使用 `//#define WATER_ENABLED`。
每条说明提供 `zh_cn` 和 `en_us`；需要帮助文字时增加同样带两种翻译的 `description`。
每个有选项的效果定义一次 `@effect` 菜单名称。

`options.py` 同时扫描这两类原生声明，默认值和范围不在工具中另存。Iris当前源码的 `ConstDirectiveParser` 使用字面量解析，`OptionAnnotatedSource` 白名单包含 `shadowMapResolution` 与 `shadowDistance`；构建回归会检查声明类型和生成菜单名称。

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
每个版本使用 `## 版本号` 标题，下面用中文说明本次增加、修复或调整了什么。
发布时自动提取该版本内容作为 GitHub 发行说明；缺失、空白或重复记录会导致检查失败。
修改直接写在对应的 `## 版本号` 标题下（版本号取自 `VERSION`），发布说明按版本号精确提取；不存在单独的 `## 未发布` 章节。
当前为代码实现审查阶段，使用开发预发布版本；画面、性能、兼容验证分别记录。
正式版本使用 `x.y.z`；预发布版本使用 `x.y.z-dev.N` 等格式。

一命令发布入口已经实现，但本轮禁止执行：

```powershell
python build.py release --new-version 0.0.0-dev.5 --notes-file .dev/release-notes.md
```

示例版本只用于说明。命令要求干净 main、合法新版本、非空说明与真实交互输入“发布 版本号”。确认后更新版本、运行 Python 测试、构建、提交、创建新标签并原子推送；失败保留可审查状态，不强推、不改写已有标签。日常代码审查不会触发该命令。
标签推送自动执行发布工作流，校验失败时中止。
通过后创建 GitHub Release，上传光影 ZIP、预设 ZIP 与 SHA256 校验文件。
发行版详情直接显示中文修改清单，内容只在 `CHANGELOG.md` 维护。
本地可运行 `python build.py notes` 预览说明，或用 `--output dist/release-notes.md` 导出。
带后缀的版本自动标记为预发布。工作流使用 GitHub 自带令牌，无需保存个人令牌。

也可在 GitHub Actions 手动运行“发布光影版本”，填写已经推送的标签。
默认勾选创建草稿，用于检验发布流程。不要重复发布同一标签。

## 可重复打包

ZIP 的文件顺序、权限和时间戳固定，相同源码在相同工具环境下应得到相同校验值。
ZIP 平台标记固定为同一值，Windows 与 Linux 不因操作系统标记而产生差异。
只收集允许的光影资源后缀；不包含 `.dev/`、个人路径、游戏存档或登录数据。
预设单独打包，说明文件记录格式版本和目标光影版本。

## 第三方代码

当前没有随包运行的第三方库，云密度用 iterationT 的预计算噪声贴图；Base-330 评估后因输入输出重复未采用。来源与边界见 `THIRD_PARTY.md`，运行库受 `dependencies.json` 文件白名单与哈希控制，自有注释审计豁免第三方原文。
第一版参考代码由用户指定。采用前确认许可证，并保留要求的版权声明。
项目本身的许可证等待用户决定，不从工具的许可证推导。

## 配置分享与回归

```powershell
python config.py reset
python config.py import --input presets/realistic.properties --output .dev/config/realistic.json
python config.py export --input .dev/config/realistic.json --output .dev/config/load.properties
python config.py export --input .dev/config/realistic.json --output .dev/config/share.json --format json
python config.py diff --input .dev/config/share.json
python config.py diff --input .dev/config/share.json --other .dev/config/user.json
```

JSON格式二保存 `schemaVersion`、`shaderVersion` 和完整 `values`，格式版本只有 `config.SHARE_SCHEMA` 一个来源。无标记properties默认按当前VERSION导入；旧properties必须使用 `--legacy`，只接受旧调试选项。export默认生成可直接供加载器使用的properties，按后缀或 `--format json` 可以导出JSON分享。未知版本、非法取值与重复键报错，所有输出只写本项目 `.dev` 且拒绝符号链接或目录联接。

先在专用实例创建测试世界，再运行 `python game.py regression --world 世界目录名 --pack-format 实际格式编号`。工具只向 `.dev/minecraft/saves/该世界/datapacks/Omni-regression` 写命令，不启动游戏。进入测试世界执行 `/reload` 与 `/function omni:setup`；这会覆盖原点附近的专用测试区域，随后用 `omni:day`、`night`、`rain`、`underwater`、`cave`、`nether`、`end` 固定条件。当前版本的规则名为 `minecraft:advance_time` 和 `minecraft:advance_weather`，相机水下位置在实际深水池内，重复准备只清理带工具标记的实体。报告初始全部是“未运行”，需要实际观察与截图后记录证据。

性能工具使用开发目录内的官方 PresentMon。调用接口与上下文字段见 `docs/performance.md`，未提供有效采样不会生成性能结论。
