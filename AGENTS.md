# Omni 开发约定

## 当前阶段

当前是开发准备阶段。`effects/` 中除 `debug.glsl` 外都是占位文件。
第一版效果必须等待用户指定参考代码后再开发。不能把目录存在当作功能实现。
阅读顺序：`README.md` → 要修改的主体文件 → `docs/rendering.md`。

## HOP：找得到、看得懂、改得安

1. 按实际效果组织。阴影在 `effects/shadow.glsl`，水面在 `effects/water.glsl`。
   算法、选项、说明和只服务此效果的计算放在同一个文件里。
2. 一项效果先用一个文件。实际复杂到难读时才按算法或内容拆进同名文件夹。
   不把同一个主体拆成定义层、处理层和工具层。
3. `rendering/` 明确安排绘制顺序和输入输出。效果算法不在这里复制。
   游戏要求的 `.vsh/.fsh` 是薄入口，显式 `#include` 对应绘制文件。
   `#include` 行只写引用，中文说明放上一行，以兼容 Iris 的引用解析。
4. 选项只在原生 `#define` 上定义一次。紧邻的 `// @option {...}` 提供菜单说明。
   `options.py` 自动扫描，生成 `shaders.properties` 和 `lang/*.lang`，不手工改产物。
   新增选项不修改中央登记表；新增绘制步骤必须显式修改相关流程。
5. `rendering/pipeline.properties` 是加载器绘制设置的唯一来源。
   `rendering/buffers.glsl` 是中间画面编号与用途的唯一约定。
   `VERSION` 是版本号唯一来源；标签必须是 `v` 加上它。
6. 文件头用中文写职责、调用位置和可用示例。跨文件 Python 函数用 docstring。
   业务代码配中文步骤注释，解释为什么做、处理什么数据。GLSL 的版本声明放第一行。
7. 名字使用普通词或图形行业标准词。函数一次完成一个能用一句话说明的动作。
   流程从上往下读，提前返回，避免深层嵌套、继承框架和隐藏分发。
8. 内部数据互相信任。用户配置、下载文件、命令参数、文件引用在边界检查一次。
   不添加吞掉错误的兜底。资源释放用 `finally`，命令入口统一报告错误。
9. 多项效果共用的纯计算放 `common/`，不把业务功能塞进去。
   不为性能臆测增加抽象；先测量，记录设备、场景和每帧耗时。
10. 修问题先改根因。修改哪片，就整理哪片。保留用户修改。
    大范围结构调整先说明实际问题；用户已明确授权的结构准备可以继续。

## 开发与验证

```text
python dev.py setup --graphics
python build.py check
python -m unittest discover -s tests
python build.py build
.venv/Scripts/python.exe tests/gpu.py
```

`check` 包含引用、选项、预设、生成文件与 GLSL 编译/链接检查。
未运行 Minecraft、未检查某个设备或配置时，必须明确写“未验证”。
离线 GLSL 检查不能代替 Iris 实际加载，GPU 测试不能代替游戏适配测试。
工具和游戏环境位于 `.dev/`，不提交下载包、凭据、存档和个人路径。

## Git 与发布

- 主分支 `main`。提交格式：`类型(范围): 中文描述`。
- 常用类型：`feat`、`fix`、`refactor`、`docs`、`test`、`build`、`ci`、`chore`。
- 示例：`feat(water): 增加水面吸收选项`，`ci(release): 自动上传光影压缩包`。
- 每次提交前检查状态、差异和最近记录，只提交本次相关文件。
- 不提交密钥，不强推，不跳过已有检查。只有用户授权时提交、推送或发布。
- 发布流程见 `docs/development.md`。预发布版本使用 `-dev.N` 或 `-alpha.N`。
- 不擅自添加项目许可证；采用第三方代码前检查许可并保留必要声明。
