# 本轮代码审查交接

## 当前审查进度

当前版本以 `../VERSION` 为准。下文“三轮”“45 项测试”等描述是 `0.0.0-dev.4` 历史记录，不是当前统计；`.dev/reports/implementation.json` 也不是后续版本的验证凭据。

`0.0.0-dev.36` 修复上采样文件保护宏与玩家开关重名、积雪反序平滑插值、湿润温度方向与菜单不一致，以及编译缓存删除注释导致分词碰撞。新增实际预处理开关检查、固定阈值顺序检查和真实编译器缓存拒错回归。离线检查不能证明游戏画面已修复。

后续审查线索尚未完成修复和验证：地平线遮蔽无有效邻点时的返回值、LPV 共享图像一致性与均匀注入、云影与可见云层对应关系、镜头与重采样组合、并发构建缓存写入、捕获包装进程与游戏进程身份，以及配置输出格式和输入结构错误。需要逐项复核源码与实际触发结果，不能把审查推导当作实机根因。

参考效果仍有缺口：局部彩光与遮挡传播、云内受光和多层云、接触硬化阴影、独立水色与光源颜色、云厚度及雾高度等风格参数。现有 LPV 不是完整场景间接光，边缘重采样没有内部低分辨率流程；全部画面和性能结论仍待游戏验证。

## 基础实现历史

本文件记录三轮主助手静态审查：第一轮完成基础实现，第二轮修正维度、配置和工具边界，第三轮修正材质AO、原生Iris const、精确元数据、水面法线、维度光柱、TAA除零、镜头组合、代码可读性和最终工具边界。审查期间保留本地代码，审查完成后按用户要求提交推送；没有游戏、GPU视觉或性能证据。

实现由主会话的子智能体完成，子智能体内部不能继续嵌套，主助手独立审查。用户授权完整代码实现并明确本轮不需要效果验证；代码审查完成后由主助手提交推送，后续每完成一个已验证的小步骤就提交推送。本轮不打标签、不启动 Minecraft 或 GPU 视觉测试。

## 九项审查修正

| 问题 | 实际修正与边界 |
| --- | --- |
| 最终运动模糊检查错误历史帧 | 时间阶段在翻转前检查旧历史，把连续性写入当前颜色 A；最终镜头读取该标志。使用当前真实深度与两帧相机矩阵，拒绝相机跳变、屏幕后投影和越界；撤销当前抖动，恢复上一帧采样位置，物理运动速度不包含抖动差 |
| DH 反射坐标不匹配 | 每个射线点分别投向近景与 DH；分别读取对应深度、逆投影和命中 UV；DH 命中被近景颜色遮挡时拒绝，不混读两种裁剪面 |
| 透明元数据与深度不配对 | 基础线条、粒子、天气、发光覆盖和半透明实体只输出颜色与独立无效标志，保留底层类别。没有可靠透明实体分离能力时整类实体保守拒绝几何后处理。水法线和真实插值视深度另写附件 8，玻璃清零水记录；水重建不依赖加载器是否写标准深度。近远水均强制 A=1 走不透明快照法，完全透明 DH 片元丢弃 |
| 零水波与零反射仍计算 | 水波零强度在法线函数提前返回平面法线；水与普通材质在调用反射前检查同一强度，零值不调用天空与 SSR。新增真实离线优化探针，检查中间码没有波浪三角函数或反射调用 |
| 实体、手材质缺失与退化切线 | 地形、实体、方块实体、手均调用 labPBR 解码；只有地形允许图集视差。缺失或退化法线与切线在归一化前判断长度，选择不平行参考轴；默认手性有明确值 |
| 英语注释检测过弱 | 使用技术术语／标识符／命令示例白名单识别，而非少数英文关键词；纯英语和混一个汉字的英语句子都报错。真实中文说明至少四个汉字才计数，机器 JSON 单独检查。多行真实文档串逐行计数，普通中文字符串不算 |
| 委派与授权记录错误 | 本文与 AGENTS 区分用户要求和当前执行边界，不再称本会话没有主会话委派 |
| 第三方复用缺失 | 实际采用 Ashima 三维单纯形噪声直接计算云密度，固定提交与文件哈希，MIT 原始声明随包。Base-330 因现有流程输入输出已固定、接线重复而未采用；简单随机序列与轻量雪边缘仍用已有函数 |
| 维度入口 | 按 Iris 官方规则保留 `world0`、`world-1`、`world1` 三组实际入口；根目录只保留共用代码。30 个程序、90 组顶点片元、180 个入口 |

透明拒绝路径是一项明确的保守策略：混合透明像素不进行全像素 SSR、SSAO、雾或 TAA，不声明完整多层透明。其前向材质照明仍保留。Iris 官方文档核对了 `ENTITY_TRANSLUCENT` 可选特性和 `particles.ordering=mixed`，没有使用已注明存在问题的 `separateEntityDraws`。基础路径未开启该能力时不假定透明实体已正确分离。

## 文件定位

| 主体 | 文件 |
| --- | --- |
| 坐标和输入 | `shaders/common/coordinates.glsl`、`uniforms.glsl` |
| 真实绘制与协议 | `shaders/rendering/terrain.glsl`、`distant.glsl`、`composite.glsl`、`post.glsl`、`buffers.glsl`、`pipeline.properties`、`programs.json` |
| 当时的效果修正 | `shaders/effects/lens/lens.glsl`、`shaders/effects/reflection/reflection.glsl`、`shaders/effects/water/water.glsl`、`shaders/effects/ground/material.glsl`、`shaders/effects/clarity/antialiasing.glsl`、`shaders/effects/cloud/cloud.glsl`、`shaders/effects/dev/debug.glsl` |
| 工具与回归 | `audit.py`、`build.py`、`tests/test_pipeline.py`、`tests/test_review.py` |
| 上游原件与许可 | `shaders/libraries/ashima/noise3D.glsl`、`LICENSE`、`dependencies.json`、`THIRD_PARTY.md` |

完整输入输出见 `docs/rendering.md`，能力和限制见 `docs/parity.md` 与 `docs/eclipse-parity.md`。上表文件已按当前目录结构更正，本节版本号是当时的历史值，不代表当前文件结构。版本保持尚未发布的 `0.0.0-dev.4`，修改记录补充到同一章节。

## 本轮验证

执行 `python build.py generate`、`python -m unittest discover -s tests`、`python build.py build`。最后一轮单元测试 45 项已通过，包括离线优化、旧入口保留用户注释、维度加载、路径、进程、配置迁移、properties导出、发布前生成变化、功能目录链接和镜头业务动作回归；自有代码审计覆盖 226 个文件，最低有效中文注释比例 50%。

最终全量构建已通过：126 种配置、5268 组唯一程序，180 个入口、51 个选项、4 套预设。三组 worldN 各 30 个片元入口，根目录可执行入口为零；生成属性为 ASCII 中文转义，Ashima 原始许可随包，ZIP 源码与工作区无差异。阴影菜单包含原生 `shadowMapResolution` 与 `shadowDistance`。`terrain.glsl` 使用 `Surface`、`omniReadSurface`、`omniShadeSurface`、`omniWriteSurface` 三步主线；`lens.glsl` 使用独立 `omniMotionBlur`，不再使用线性插值的 `texture(colortex1/7)` 元数据读取。景深只检查几何有效性和手持类别，不依赖历史颜色连续性；运动速度只在 TAA 开启时处理抖动。本轮不创建标签，不运行游戏或GPU测试。代码提交版本为 `0.0.0-dev.4`，本地离线结果记录见 `.dev/reports/implementation.json`。

优化探针使用相同生产函数，以 GLSL 450 生成优化中间码；生产入口仍使用 GLSL 330 compatibility 并另外编译链接。探针只能证明这个离线编译器消除了零值分支，不能代替 GPU 驱动耗时测量。

中文比例覆盖所有自有 Python、GLSL 和生成薄入口。第三方原始源码与原始 LICENSE 豁免，不改写英文版权凑比例；引用、字节哈希与打包许可仍强制检查。机器字段内英文翻译豁免，正文英语不豁免。业务意义仍由人工审查，自动词法规则不声称理解全部注释语义。

审计同时检查自有预设、方块映射、加载器属性表和 `.github/` YAML 的有效中文说明与至少 50% 注释比例。生成菜单与语言文件只检查说明语言和ASCII编码，不用海量机器翻译行灌注释凑比例；说明中的中文使用Unicode转义，审计解码后检查。Markdown、JSON和第三方原声明不参与比例。

## 第二轮审查修正

这轮由原子智能体在同一实现上下文修复。官方 [dimension.properties 文档](https://github.com/IrisShaders/docs/blob/main/src/content/docs/current/Reference/Miscellaneous/dimension_properties.mdx) 明确说明任意worldN存在时根程序不加载。已恢复world0，删除被忽略的根可执行入口，GPU工具和包结构测试改用实际world0路径；三个维度均显式设置阴影程序开关。上一轮根目录主世界说明错误，已删除并替换为官方约定。

生成属性的英文说明改为ASCII中文转义并单独审计。新增配置与采样边界回归：世界名拒绝驱动相对路径、设备名、特殊目录和所有链接；数据包函数目录也检查。采样先验证上下文，再核对工具启动记录、实际Java路径与gameDir，任意进程号不会启动采样器。发布检查生成后及测试后所有非版本文件变化，错误命令参数和错误依赖files类型在入口可读报错。

JSON格式版本只有 `options.SHARE_SCHEMA` 一个来源，打包清单由它生成；properties当前版与显式legacy格式分开导入，export默认输出加载器properties，也可按后缀或 `--format json` 导出JSON。所有自有输出限定本项目.dev并拒绝路径链接。移除只转发的transparent.glsl，水程序显式选择terrain与水阶段宏。水顶面才计算波浪，侧面保留真实法线，玩家水纹增加高度距离；景深排除手和透明覆盖，色差、景深、运动、暗角保持统一顺序。没有新的游戏、画面或性能验证结论。

没有运行 Minecraft、GPU 视觉测试或真实性能采样，没有创建发行版或标签。代码提交推送与游戏验证分开记录，没有新的画面、兼容或性能证据。
