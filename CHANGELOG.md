# 更新记录
## 0.1.5

通用库第三批：表面。

- 新增 `shaders/gfx/surface.glsl`：天光与方块光曲线、材质遮蔽、法线缩放与法线解码后的合并，选项值改为显式参数。
- `effects/ground/material.glsl` 只保留选项与同名转发；曲线常数与计算结果不变。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.18

通用库第十四批：调色曲线。

- `shaders/gfx/post.glsl` 增加暗部曲线、亮部曲线、亮度曲线与染色方向归一化。
- `effects/color/colorgrade.glsl` 只保留同名转发，三段染色、串色与开关顺序未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.17

通用库第十三批：环境遮蔽多弹射。

- 新增 `shaders/gfx/gi.glsl`：按底色补偿环境遮蔽的多项式。
- `effects/lighting/gtao.glsl` 只保留同名转发，遮蔽采样与强度流程未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.16

通用库第十二批：反射方向。

- 新增 `shaders/gfx/reflection.glsl`：可见法线分布的反射方向采样。
- `effects/reflection/screenspace.glsl` 只保留同名转发，屏幕空间追踪、深度判断与反射合成未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.15

通用库第十一批：抗锯齿。

- 新增 `shaders/gfx/antialias.glsl`：亮度色差空间转换、两种历史裁剪方式与五次采样四分量纹理。
- `effects/clarity/taa.glsl` 只保留同名转发；`TAA_CLIP_TO_CENTER` 分支仍由效果层选择，默认裁剪方式不变。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.14

通用库第十批：泛光采样。

- 新增 `shaders/gfx/post.glsl`：管线伽马编码、十三样本降采样、轴向高斯模糊与三次升采样。
- `effects/color/bloom.glsl` 的三个采样函数只保留同名转发，像素大小由效果层传入；泛光链、合并与天气增强未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.13

通用库第九批：雾的噪声与密度。

- `shaders/gfx/fog.glsl` 增加三维噪声、仅高度衰减密度与团雾密度，噪声纹理、高度、衰减距离和时间改为参数。
- `effects/fog/volumetric.glsl` 的两个密度分支只保留同名转发，体积雾步进与光照流程未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.12

通用库第八批：平面云形状。

- `shaders/gfx/cloud.glsl` 增加三次模糊噪声、双线性噪声、平面云扭曲、密度与光照密度，噪声纹理、空间尺度和云量改为参数。
- `effects/cloud/planar.glsl` 只保留同名转发，平面云求交、光照与绘制流程未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.11

通用库第七批：云的相位与雾的散射。

- 新增 `shaders/gfx/cloud.glsl`：亨耶-格林斯坦相位与云的顶部曲线。
- 新增 `shaders/gfx/fog.glsl`：粉末效应、混合米氏相位与四次多次散射相位。
- `effects/cloud/volumetric.glsl` 与 `effects/fog/volumetric.glsl` 只保留同名转发，采样循环、密度与光照流程未动。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.10

记录结构重构的连续执行授权。

- `AGENTS.md` 增加一条：按 `docs/structure-plan.md` 连续执行，每批编译通过后直接提交推送，不再逐批确认。
- 仅文档改动。


## 0.1.9

通用库第六批：大气几何。

- 新增 `shaders/gfx/atmosphere.glsl`：半径夹取、安全开方、到层顶与层底的距离、地面求交、密度剖面和预计算贴图坐标。
- `effects/sky/atmosphere_model.glsl` 的九个小函数只保留同名转发，大气半径与贴图尺寸由效果文件传入。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.8

通用库第五批：水面波形。

- 新增 `shaders/gfx/water.glsl`：噪声平滑、六层波高、波法线与水面视差，噪声纹理、时间、空间缩放和波高全部改为参数。
- `effects/water/waves.glsl` 只保留同名转发；玩家涟漪仍在包装层叠加，归一化顺序与原程序一致。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.7

补充结构计划的进度记录，写明阴影坐标已迁入通用库，下一批为大气。

仅文档改动。


## 0.1.6

通用库第四批：阴影坐标。

- 新增 `shaders/gfx/shadow.glsl`：世界位置投到阴影相机、边缘压缩与读取端补压缩，矩阵和压缩强度改为显式参数。
- `effects/shadow/shadow.glsl` 的四组坐标函数只保留同名转发，末地与主世界分支各自传入自己的相机矩阵。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.4

通用库第二批：数学与采样。

- 新增 `shaders/gfx/math.glsl`：曲线、法线与颜色编码、材质、光线求交、拜尔矩阵和双三次采样迁入，统一使用 `gfx_` 前缀。
- 新增 `shaders/gfx/sampling.glsl`：蓝噪声与时间抖动改为显式传入噪声纹理、像素坐标和帧号，不读取加载器全局量。
- `common/math.glsl` 只保留引擎常数与同名转发，代码量明显下降；`common/noise.glsl` 只保留像素坐标适配与转发。
- 更新 `docs/structure-plan.md` 进度。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。

## 0.1.3

建立可独立发布的通用图形库，并迁入第一批颜色算法。

- 新增 `shaders/gfx/` 与 `shaders/gfx/color.glsl`：线性颜色、亮度、伽马、ACES、AgX、无压缩只接收显式参数，不读取 Minecraft 或 Iris 符号。
- `effects/color/color.glsl` 删除三套色调映射实现，改为引入通用库并传入选项；曝光统计、白平衡和选项仍留在效果文件。
- `effects/color/post_tonemap.glsl` 改调 `gfx_aces`、`gfx_tonemap_none`、`gfx_agx`，默认 AgX 路径不变。
- 重写 `docs/structure-plan.md`：写明通用库边界、9 页菜单、无“高级”页、迁移批次与 2000 行目标。
- 更新对应测试断言。

验证：`audit`、`verify` 与全量 `compile` 通过（280 组唯一程序，0 错误）。游戏内画面尚未复查。


## 0.1.2

`README.md` ??????????????????

??????

## 0.1.1

???????????????

- ?? `docs/structure-plan.md`??????46 ????97 ????81 ???????????????????`shared/` ?????????????????????????????????????
- `README.md` ??????????
- ?????????????????????????????? include?

??????????????

## 0.1.0

??????????????????????????????????????

- ???? `0.0.0-dev.173` ?? `0.1.0`?????????????????????????????
- ???????????????? `0.0.0-dev.173` ???iterationT 3.2.0 ?????Eclipse ???????????????????????????
- ?????P0 ??????????P1 ??????????P2 ?????P3 ??????????????? `docs/performance-plan.md`?

?????????????????????????????????

## 0.0.0-dev.173

??????????????

- ?? `docs/performance-plan.md`??????????include ?????????????? P0 ??????P1 ????P2 ???P3 ????????????????????????
- `README.md` ??????????
- ??????? Iris ???? VRS???????????????????????

??????????????

## 0.0.0-dev.172

?????????

- `OMNI_MOTION_BLUR` ???? 1 ?? 0????????????????????

??????????????????????????

## 0.0.0-dev.171

?????????????

- ?????????????????????????????????????????????????????????? 111 ?????????????
- ?????????? 0.13 ?? 0.2???????? 1.0 ?? 1.2?????????????????????????????????????????????????????????
- ???????????????????????????????????????

??????????????????????????

## 0.0.0-dev.170

?????????????????????????????????????????

- ???`rendering/composite.glsl` ?? `composite_pass0` ? `composite_pass5`?`deferred.glsl` ?? `deferred_pass0` ? `deferred_pass8`?`post.glsl` ?? `post_pass6` ? `post_pass16`???????????????????????????
- ????????????? 31MB ??? 12MB??????? 16MB ??? 2.8MB??????? 4MB???????????????
- ??????? iterationT ???? KB ???????????????????????????????????????????????????????????

????????????????????????????

## 0.0.0-dev.169

?????????????????????????????????????

- ?????????? `shaders.properties`??`setup` ? `shadowcomp` ?? `OMNI_LPV_ENABLED`?`prepare/prepare1/prepare2` ?? `OMNI_WAVE_SIMULATION`???????????????????????????????????????????
- ?????????????? 31MB??????????????????????????????????????????????? 15MB????????????????????????????????????????????
- ???README ????????????????????????????????????

???????????????????????????????

## 0.0.0-dev.168

????????????????????????????????????????

- ???????`block.properties`?`entity.properties`?`item.properties` ??????? ASCII?????????????? ASCII ?? `Bad token`?????/??/????????????????????????? ASCII ????????
- ??????LPV ??????????? `workGroups` ??????????????????????????????????? `NumberFormatException`??????????????????
- ???????? 105 ?????????????????????????????????????????? `0/1` ?????? `#ifdef/#ifndef/#if defined` ???????????????? `true/false` ???????? `1/0`???????????
- ?????????????????????????????????????????????????????????????????????????? Physics Mod ?????????????????????????

?????????????????????????????


## 0.0.0-dev.167

删掉四行已经没人读的贴图绑定，只清理绘制设置，不改画面。

- 标题图标改用独立采样器后，八号画面与二号深度上的第二层贴图绑定（四处 `itt320.png`）已没有采样再读取，删掉以免混淆；大气数据仍挂在第一层，旧版本走二号深度的分支不变。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.166

把 `docs/parity.md` 与 `docs/eclipse-parity.md` 的行号引用刷到 `dev.165` 二次拆分后的当前代码，并补记偏离记录 55。

- `docs/eclipse-parity.md`：反射、水、时间抗锯齿、环境光、阴影、镜头、方块光七处效果文件二次拆分后，受影响的行号引用改指新文件，例如 `water.glsl:103` → `waves.glsl:47`、`ambient.glsl:378` → `gtao.glsl:15`、`shadow.glsl:323` → `screen_shadow.glsl:13`、`antialiasing.glsl:303` → `taa.glsl:249`、`lens.glsl:106` → `dof.glsl:14`、`blocklight.glsl:118` → `:119`；「水雾与焦散」「雨点涟漪与水洼」「阴影」「远景（DH）」等行里随拆分移动的函数文件引用也同步更正。
- `docs/parity.md`：偏离记录 48 的三项远景开关行号改指新文件，偏离记录 11、15 与第九点五节里随拆分移动的函数所在文件改指 `water_caustics.glsl`、`taa.glsl`、`gi.glsl`；新增偏离记录 55 记录本次二次拆分。
- 同步 `AGENTS.md` 与 `docs/development.md` 的验证探针与测试计数（9 组唯一程序、129 个测试）。

仅文档修改，未改代码；`python build.py verify` 通过；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.165

把七个过大的效果文件按算法拆成「入口 + 同目录算法文件」，不改任何画面、选项与算法，只减少单个文件的行数。

- 反射（`shaders/effects/reflection/reflection.glsl`，原 619 行拆成 49 行入口加两个文件）：屏幕空间追踪、GGX 采样、假天空回退与反射着色放到 `screenspace.glsl`，反射小波滤波放到 `denoise.glsl`。
- 水（`shaders/effects/water/water.glsl`，原 588 行拆成 78 行入口加四个文件）：基础波浪与物理解析波浪放到 `waves.glsl`，雨点涟漪放到 `rain.glsl`，水雾放到 `waterfog.glsl`，水面折射与彩色透光吸收放到 `refraction.glsl`。
- 时间抗锯齿（`shaders/effects/clarity/antialiasing.glsl`，原 556 行拆成 118 行入口加两个文件）：颜色空间、取样、深度与方差统计、时间重投影与相机速度放到 `taa.glsl`，FXAA 放到 `fxaa.glsl`；合成七号主体 `WriteTaaHistory` 留在入口。
- 环境光（`shaders/effects/lighting/ambient.glsl`，原 538 行拆成 120 行入口加两个文件）：全局光的反弹、时间滤波与空间滤波放到 `gi.glsl`，地平线遮蔽与多弹射放到 `gtao.glsl`；延迟二号与四号主体 `RenderGISpatialFilter` 留在入口。
- 阴影（`shaders/effects/shadow/shadow.glsl`，原 463 行拆成 325 行入口加两个文件）：屏幕空间阴影放到 `screen_shadow.glsl`，水下焦散放到 `water_caustics.glsl`；阴影图坐标与可变半影留在入口。
- 镜头（`shaders/effects/lens/lens.glsl`，原 457 行拆成 118 行入口加三个文件）：景深放到 `dof.glsl`，眩光与光斑放到 `glare.glsl`，相机动态模糊放到 `motion_blur.glsl`；暗角只有几行留在入口。
- 方块光（`shaders/effects/lighting/blocklight.glsl`，原 457 行拆成 168 行入口加一个文件）：手持光源（光斑形状、屏幕空间阴影、手持光与手持高光）放到 `held_light.glsl`；方块光与纹理自发光留在入口。
- 入口集中定义本效果的全部选项与内部常数，算法文件按同一顺序引入；算法行原样搬迁，函数、宏、常数与注释均未改名或重排，展开后的编译输入与拆分前逐字一致（离线逐入口展开对比全部相同）。
- 测试引用路径同步更新（`tests/test_effects.py`、`tests/test_boundaries.py`）。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.164

收紧选项接线硬检查，名字只出现在注释里不再算接入计算，并补上对应回归测试。

- 选项接线（`build.py` 的 `check_option_wiring`）：原实现只跳掉声明行，名字出现在任意注释里也算「已接线」，于是漏掉真正没接入的选项。现在先去掉行注释与块注释再分词，交错注释用单条正则一次匹配，避免误删另一种注释里的代码。
- 声明行按每个选项记录的来源与行号精确跳过，`const` 选项的声明行也能跳掉（旧实现只按 `#define` 模式跳，常量声明行会把自己算成一次使用）。
- 加载器设置（`rendering/pipeline.properties`）纳入接线来源：按选项开关程序也是真实接线；其中的 `#` 注释同样被去掉，`#if`/`#ifdef` 等条件指令保留。
- 加载器原生常量选项（`sunPathRotation`、`wetnessHalflife`、`drynessHalflife` 等 `const`）由运行环境按合同读取，不要求在 GLSL 里出现，单独放行，避免收紧后误报。
- 新增 7 个测试（`tests/test_build.py`）：注释不算接线、只有声明行不算接线、代码里使用通过、加载器设置算接线、加载器注释不算接线、加载器常量放行、项目真实选项全通过。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.163

逐条核实代码审查交接文档里未结的七条线索，四条确有问题已修，三条在当前算法下已不存在。

- 镜头与重采样（`shaders/effects/lens/distortion.glsl`、`shaders/rendering/final.glsl`）：开启放大时最终颜色来自放大后的画面，镜头形变却固定重采样低分辨率画面，等于丢掉放大结果；现在按当前路径选择源画面，放大走放大缓冲，否则走场景颜色。
- 并发构建缓存写入（`build.py`）：编译缓存改为先写临时文件再原子替换，并发或中断时不会读到半截 JSON。
- 捕获身份记录（`game.py`）：捕获启动的是包装进程，旧代码把它的进程号当成游戏本体；现在捕获启动不写采样身份并清掉旧记录，采样不会打错进程。
- 配置输出与输入边界（`config.py`）：按后缀选格式的导入、导出与重置行为统一；当前格式里取值写成对象、数组或布尔时，在读取边界给出可读错误，不再抛不可哈希的异常。
- 已不存在问题的三条：地平线遮蔽无有效邻点（现为移植实现，无非邻点累加）、体积光的共享图像一致性与光表填充、云影与可见云层的对应关系，均已逐条复核并写明结论。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.162

把两个过大的效果文件按内容拆成「入口 + 同目录算法文件」，不改任何画面、选项与算法，只减少单个文件的行数。

- 天空（`shaders/effects/sky/sky.glsl`，原 728 行拆成 144 行入口加五个文件）：预计算大气与天空辐射放到 `atmosphere_model.glsl`，日月圆盘放到 `sun_moon.glsl`，月亮轨道、月食与月相放到 `moon_orbit.glsl`，星空放到 `stars.glsl`，天空盒投影放到 `skybox.glsl`。
- 云（`shaders/effects/cloud/cloud.glsl`，原 638 行拆成 176 行入口加三个文件）：体积云、附加云层与低分辨率云总图放到 `volumetric.glsl`，平面云放到 `planar.glsl`，云影贴图与模糊放到 `shadow.glsl`。
- 入口集中定义本效果的全部选项与内部常数，分文件按同一顺序引入；体积云与平面云只在能读三维云噪声的延迟三号、七号、八号参与编译，这个判据收成 `OMNI_CLOUD_DENSITY_PASS` 一处定义、两个文件各自按它开关。
- 选项名、默认值与菜单分组不变，生成菜单与拆分前逐字节一致；`docs/parity.md`、`docs/eclipse-parity.md` 与相关测试的引用路径同步更新。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.161

把合成五号按维度的三段重复流程合并为一份，并把四份开发文档的行号与计数刷到当前 `main`；不改任何画面、选项与算法。

- 合成五号（`shaders/effects/world/composite_scene.glsl`）：下界、末地、主世界三段 `CompositeSceneColor` 原本几乎相同，现合并为一个流程；共用的表面读取与输出编码抽成 `SceneReadSurface`、`SceneWriteOutput`，只在折射函数、彩色玻璃吸收、雾函数、水吸收、透明通道与镜头光斑这几处按 `OMNI_NETHER`/`OMNI_END` 分派。各维度原程序里不同的值（远裁剪面系数、按掩码还是按深度判天空、下界输出写半透明深度）逐处照原程序保留，画面与合并前一致。
- 文档刷新（`docs/parity.md`、`docs/rendering.md`、`docs/development.md`、`docs/eclipse-parity.md`）：更新到 `dev.160`，入口 269 个、选项 519 个、测试 120 个、程序 47 个加 5 个计算程序；补十号画面与 `deferred7`/`deferred8` 低分辨率体积云阶段；修正因泛光、时间抗锯齿、全局光合回一个文件而移位的 `file:line`；补记偏离记录第 51 至 53 条。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.160

把三处拆成「效果文件 + 程序体文件」的效果合回一个文件，不改任何画面、选项与算法，只减少文件数量。

- 泛光（`shaders/effects/color/bloom.glsl`）：五级链 `BloomDownSampleScene` 到 `BloomCombine` 从 `post_bloom.glsl` 并入；改成返回颜色、由合成九号到十三号自己写五号画面，并按 `OMNI_COMPOSITE9_PASS` 到 `OMNI_COMPOSITE13_PASS` 隔开。
- 时间抗锯齿（`shaders/effects/clarity/antialiasing.glsl`）：合成七号主体 `WriteTaaHistory` 从 `post_taa.glsl` 并入，按 `OMNI_COMPOSITE7_PASS` 隔开。
- 全局光（`shaders/effects/lighting/ambient.glsl`）：延迟二号与延迟四号主体 `RenderGISpatialFilter` 从 `globalillumination.glsl` 并入，沿用原先的程序宏隔开。
- `shaders/rendering/post.glsl` 与 `shaders/rendering/deferred.glsl` 去掉对应的单独引入，改为在这些效果文件里调用；测试与对照文档同步更新引用路径。
- 未改任何算法、常数、选项名与缓冲编号；删除 `effects/color/post_bloom.glsl`、`effects/clarity/post_taa.glsl`、`effects/lighting/globalillumination.glsl` 三个只剩转手的文件。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.159

闪电照明补上体积云与体积雾：打开「闪电照明」时，雷暴闪电也会照亮天上的体积云与空气里的体积雾，默认关闭、画面不变。

- 照明函数（`shaders/effects/sky/atmosphere.glsl` 的 `omniLightningVolume`）：把闪电当成一根从闪电高度向上延伸一百一十六格的竖直光柱，介质采样点离柱越近越亮；照明范围与指数衰减照 Eclipse `lib/lightning_stuff.glsl` 的 `Iris_Lightningflash_VLcloud`（云，四百格）与 `Iris_Lightningflash_VLfog`（雾，一百五十格）。
- 体积云（`shaders/effects/cloud/cloud.glsl` 的 `CloudLighting`）：在云的体积光照里叠加闪电冷色光，基础云与附加层共用；云越厚、离闪电越近被照亮越明显。
- 体积雾（`shaders/effects/fog/volumetric.glsl` 的 `VolumetricFog`）：按每一步的吸收量逐段累加闪电点亮的空气，并随天空光衰减，洞穴里看不到。
- 复用既有选项 `OMNI_LIGHTNING` 与 `OMNI_LIGHTNING_STRENGTH`，不新增开关；默认关闭，关闭时与 iterationT 画面一致。
- 差异说明记入 `docs/eclipse-parity.md` 的「闪电」行：体积云与体积雾照明由「未合并」改为「近似」。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.158

受伤照 Eclipse 补上「重击整屏红」：受击闪红不再只用 `is_hurt` 一档，改成按一次掉落量区分小伤与重击，默认画面不变。

- 判定量移交给加载器（`shaders/rendering/pipeline.properties`）：新增自定义输入 `Currenthealth`／`interpolatedHealth`／`smallHealthDifference`／`largeHealthDifference`／`delayedCritDamage` 与两个强度 `MinorDamageTaken`／`CriticalDamageTaken`，照 Eclipse `shaders.properties:729-750`。为什么交给加载器：判断「这一次掉了多少血」需要跨帧的旧血量，GLSL 拿不到上一帧，只有加载器的 `smooth` 能保存状态——受击瞬间血量立刻下降、平滑血量还在高位，两者之差就是掉落量；差值过阈值即触发。只在本项目受伤效果开启（`OMNI_HURT_EFFECT`）且运行在 Iris 时登记，其它加载器与默认关时不产生代码。
- 画面表现（`shaders/effects/lens/hurt.glsl`）：`OMNI_HURT_DAMAGE` 下，小伤（一次掉一点五颗心以上）按 `MinorDamageTaken` 给边缘闪红，重击（一次掉三点五颗心以上）按 `CriticalDamageTaken` 整屏染红，并照 Eclipse 把边缘抖动升级成整屏抖动。阈值与原程序同值（三点零／七点零个半颗心），未做成选项；删掉了旧的 `is_hurt` 近似路径。
- 一个行为改变：受击总开关开启后，轻击（掉落不足一点五颗心）与 Eclipse 一样不再闪红。总开关默认关闭，默认画面与原来完全一致。
- 差异说明记入 `docs/eclipse-parity.md` 的「受伤与低血量」行：受击闪红由「含近似」改为小伤/重击的真实掉落量判定。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.157

水洼照 Eclipse 补齐法线压平，与已有的粗糙度改写、反照率压暗凑齐 `applyPuddles` 三步，默认画面不变。

- 法线压平（`shaders/effects/water/puddle.glsl`、`shaders/effects/lighting/composite_surface.glsl`）：`OmniPuddleSurface` 增加 `worldNormal` 参数，照 Eclipse `dimensions/composite1.fsh:926` 的 `normals = mix(normals, flatNormals, wetnessStages * clamp(flatNormals.y,0,1))` 把水洼处法线拉平，只在「仅水洼」（`OMNI_PUDDLE_MODE == 2`）里执行，默认模式一不跑、画面不变。
- 为什么拉向世界上方：合成阶段读回的是压平后的表面法线，没有单独的几何法线，而 Eclipse 的权重只让朝上的面被压平，此时几何法线接近世界上方，属这一情形下的等价近似，差异记入文件头与 `docs/eclipse-parity.md`。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.156

程序化草照 Eclipse 补齐「仅矮草」档、两套高度与邻接压低三项，默认画面不变。

- 替换原版矮草 `OMNI_REPLACE_SHORT_GRASS` 由「否/是」两档扩为「否/是/仅矮草」三档（`shaders/effects/ground/grass.glsl`）：仅矮草档只把原版矮草换成程序化草、草方块顶面不长草；生长来源改由 `effects/ground/grass_geometry.glsl` 按矮草方块编号 12 判断。
- 两套高度：`OMNI_GRASS_BASE_HEIGHT`（普通草高度）与 `OMNI_GRASS_SHORT_HEIGHT`（被替换矮草处的草高度），对应 Eclipse `BASE_GRASS_HEIGHT`/`SHORT_GRASS_HEIGHT`；原 `OMNI_GRASS_HEIGHT` 由 `config.py` 迁移为普通草高度（旧的 1.5、2.0 收到上限 1.0，不再报错）。
- 邻接压低：`OMNI_GRASS_DETECT_FALLOFF`（临台阶的一侧压低草叶）与 `OMNI_GRASS_DETECT_INV_FALLOFF`（旁边是草或矮草时抬高），对应 Eclipse `GRASS_DETECT_FALLOFF`/`GRASS_DETECT_INV_FALLOFF`，都默认开；高度公式照 Eclipse `all_solid.gsh:276` 的 `totalHeightMult`。
- 近似：本项目几何阶段没有体素缓冲，仅矮草档改成直接按矮草方块自己的三角形生长，同一方块会被几个三角形各长一次、叠加在同一处；邻接检测仍走上一帧九号画面，无法区分空气与未记录。
- 差异说明记入 `docs/eclipse-parity.md` 的「程序化草」行：三项由未搬改为已合并。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.155

补齐雾内泛光的水下分支：照 Eclipse `UNDERWATER_BLOOMY_FOG` 让水下浑水也有柔光。

- 新增选项 `OMNI_UNDERWATER_FOG_BLOOM`（`shaders/effects/color/bloom.glsl`，默认零、画面不变）：对应 Eclipse `lib/settings.glsl:216` 的 `UNDERWATER_BLOOMY_FOG`，档位照原程序。
- 合并泛光（`MergeBloom`）：Omni 水下不跑体积雾，引导改用水体的距离吸收（与合成五号同一式子），倍率换成 `OMNI_UNDERWATER_FOG_BLOOM`；水上仍用体积雾吸收与 `OMNI_FOG_BLOOM`，公式照 Eclipse `dimensions/composite11.fsh:314`。
- 接入条件：`OMNI_UNDERWATER_FOG`、`OMNI_VFOG` 与未开景深；默认倍率零，只在玩家打开时生效，默认画面与原来一致。
- `docs/eclipse-parity.md` 的「泛光」与「水雾与焦散」两行由「未合并」改为已合并；测试 `tests/test_effects.py` 补水下雾内泛光的选项与接入检查。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.154

补齐配置迁移：选项从开关改成多档时旧取值也能导入，被新算法整体替换的选项不再让旧配置直接失败。

- 取值迁移（`config.py` 的 `VALUE_RENAMES`）：积雨云由开关改成三档后，旧配置里的真假值分别对应到中档与关闭，不再是非法取值。
- 已移除选项（`config.py` 的 `REMOVED_OPTIONS`）：简易体积光的步数选项被 Eclipse 的彩色光传播体积整体替换，导入时忽略并打印提示，不静默丢弃也不报未知选项。
- 测试：`tests/test_pipeline.py` 补上取值迁移与已移除选项的导入验证。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.153

给雾照明补上手持光与水下两张，照 Eclipse `composite3.fsh` 把 `LPV_VL_FOG_ILLUMINATION_HANDHELD(_WATER)` 合并进来。

- 手持灯光的取光函数（`shaders/effects/lighting/lpv.glsl`）：新增 `omniLpvHandLight`，按手持物品编号读方块光表拿到光色与光照范围，再按离玩家的距离三次方衰减，照 Eclipse `lib/diffuse_lighting.glsl:74` 的 `GetHandLight`。为此给光表加了整数采样器名 `omniLpvBlocksTex`（`shaders/rendering/pipeline.properties`），合成阶段按采样器读、计算阶段仍用图像 `omniLpvBlocks` 读写，两者指向同一张纹理。
- 雾照明-手持光 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD`（默认关，等于 Eclipse）：在 `shaders/effects/fog/volumetric.glsl` 的体积雾步进里，把手里火把等的光晕逐段累加进空气，与色彩体积光同一套吸收与亮度。
- 雾照明-水下手持光 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER`（默认开，等于 Eclipse）：在 `shaders/effects/fog/underwater_fog.glsl` 的水下体积雾里叠加手持光，按水的分波段吸收衰减，靠近火把的水先亮暖色、远处只剩青蓝。
- 两项都只在「雾照明」`OMNI_LPV_VL_FOG_ILLUMINATION` 开启时才参与，而该总开关默认关闭，所以默认画面与原来完全一致。亮度系数照 Eclipse（空气项零点零四、水下项零点二）按本项目百分之一定标缩小，游戏内未校准。
- 差异说明记入 `docs/eclipse-parity.md` 的「LPV/间接光」行：手持光与水下雾照明由「未合并」改为已合并。

本批次还包含三项照 Eclipse 补齐的能力：

- 积雨云三档 `OMNI_CLOUD_CUMULONIMBUS`（`shaders/effects/cloud/cloud.glsl`，默认 0）：由开关改为「关 / 雷暴时或之后 / 始终」三档，中档由雷暴强度驱动出现与消退；层高与厚度沿用 Eclipse 的值（600 到 4600），附加层判断同步由「是否定义」改为「档位是否大于零」。
- 末地主岛光照的阴影相机（`shaders/effects/world/end_island_light.glsl`、`shaders/rendering/shadow.glsl`、`composite_surface_end.glsl`）：开启后末地阴影顶点改投竖直向下的主岛相机，主岛光源从阴影图取真实遮挡；末地太阳光照不再采样这张图，避免方向不符。
- 资源包天空 `OMNI_RESOURCEPACK_SKY`（`shaders/effects/sky/sky.glsl`、`rendering/celestial.glsl`、`skyrender.glsl`，默认关）：旧结论「不可行」的前提不成立——加载器会把资源包天空几何按天空阶段画进光影自己的画面，所以直接读零号画面当底色即可，不必新增天空专用采样器；开启时程序化大气退到只给云算透过率。仅主视图生效，水面反射天空盒仍是程序化大气。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.152

体素反射补三项细节，并补上雾内泛光选项，默认画面不变。

- 反射雾（`shaders/effects/reflection/voxel.glsl`、`reflection.glsl`）：体素反射命中的真实世界点回传给合成阶段，因此能走既有的反射雾、地表散射与雾照明通路。
- 铁块镜面（`shaders/block.properties`）：按 Eclipse 给铁块登记编号，追踪撞到时按进入面法线弹开继续追，最多四次。
- 彩色水（`shaders/effects/reflection/voxel.glsl`）：半透明方块按自身底色归一化出的色相染色，水按生物群系水色偏蓝或偏绿。
- 雾内泛光 `OMNI_FOG_BLOOM`（`shaders/effects/bloom.glsl`、`composite_scene.glsl`、`rendering/composite.glsl`，默认 0）：把光晕按雾的浓淡混进体积雾，Eclipse 原默认 0.5，本项取零以保持默认画面；同时把「体积雾吸收」写进三号画面透明通道，不再只在开散射泛光时才写。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.151

把 Eclipse 的自发光矿石与自发光纹饰合并进来，各做成一个独立开关，照 Eclipse 补齐 `docs/eclipse-parity.md` 记的缺口。

- 新效果文件 `shaders/effects/lighting/emissive.glsl`：提供两个纯函数 `omniOreEmission`（矿石，照 Eclipse `all_solid.fsh:331` 的 `getEmission`：鲜艳又明亮的矿物颗粒才亮）与 `omniTrimEmission`（纹饰，照 `:337` 的 `getTrimEmission`：只看明度）。两项各有一个开关 `OMNI_EMISSIVE_ORES`/`OMNI_EMISSIVE_TRIMS` 与一个亮度 `OMNI_EMISSIVE_ORES_STRENGTH`（默认 0.9）/`OMNI_EMISSIVE_TRIMS_STRENGTH`（默认 0.7），默认都关闭、画面不变。
- 矿石接线（`shaders/block.properties`、`shaders/rendering/terrain.glsl`、`shaders/effects/ground/terrain_surface.glsl`）：矿物方块登记为新编号 `block.502`；地形顶点按编号给出矿石标记，几何转发到片元，片元按贴图颜色算出发光写进五号画面的自发光通道。
- 纹饰接线（`shaders/item.properties`、`shaders/rendering/entities.glsl`）：盔甲纹饰登记为 `item.1026`（亮纹饰）与 `item.1027`（暗纹饰）；实体片元读加载器的 `currentRenderedItemId`，命中时按明度算发光写进自发光通道，亮纹饰发光再乘 0.4（照 Eclipse）。
- 共用改动（`shaders/common/math.glsl`、`shaders/effects/lighting/lpv.glsl`）：颜色转 HSV 的 `omniRgbToHsv` 从体积光文件移到共用数学，体积光与自发光两处共用一份。
- 差异说明记入 `docs/eclipse-parity.md` 的「自发光矿石与纹饰」行（由「未合并」改为「已合并」）：发光与资源包 labPBR 自发光取较大者合并、没搬 Eclipse 的「覆盖」第三档；未登记模组矿石；需开启物理光照。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.150

程序化草补上细分等级、随机与替换矮草三项，照 Eclipse 补齐缺口。

- 细分等级 `OMNI_GRASS_DENSITY`（`shaders/effects/ground/grass.glsl`、`grass_geometry.glsl`、`shaders/rendering/terrain.glsl`）：本项目没有细分着色器，改成在几何阶段让一个顶面按档位长出一到四片草。
- 随机 `OMNI_GRASS_RANDOMNESS`（默认 0.2）：原先写死的弯曲量升为滑块，并按草片序号错开随机种子，让同一面的几片草各自弯折。
- 替换矮草 `OMNI_REPLACE_SHORT_GRASS`（默认关）：把原版矮草拆成独立编号 `block.12`，开启后范围内原版矮草顶点退化并被剔除，由草方块顶面的草代替；`vegetation`、`shadow`、`lpv`、`voxel` 同步补上该编号的植物判定。
- 差异说明记入 `docs/eclipse-parity.md` 的「程序化草」行（Eclipse 的「仅矮草」第三档与两套高度、邻接压低未搬）。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.149

给体积光补上方块实体光与掉落物光，都接在已有的实体光源开关上（对应 Eclipse 把实体、方块实体与掉落物放在同一个 `LPV_ENTITY_LIGHTS`）。

- 方块实体光（`shaders/effects/lighting/lpv.glsl`、`shaders/rendering/shadow.glsl`、`shaders/block.properties`）：`block.properties` 给潮涌核心、附魔台、酿造台登记新编号 7310–7312，信标与末地传送门沿用已有的 `block.89` 与 `block.119`；阴影顶点用 Iris 的 `renderStage` 区分方块实体（读 `blockEntityId`）与地形，按 `omniLpvBlockEntityVoxelId` 只给会发光的方块实体写体素，光照颜色与强度照 Eclipse `dimensions/setup.csh`。不发光方块实体不写，避免把信标光束这类大体积几何误写成挡光格子。
- 掉落物光（`shaders/item.properties`、`shaders/effects/lighting/lpv.glsl`、`shaders/rendering/shadow.glsl`）：阴影顶点在实体阶段按 `currentRenderedItemId` 写体素，经 `omniLpvDroppedItemVoxelId` 判断是不是发光物品。方块物品（火把、荧石、灯笼、红石火把、彩色蜡烛等）用 `block.properties` 编号；非方块物品给岩浆桶、荧石粉登记 `item.7400`、`item.7401`。普通掉落的方块不写，光正常穿过。
- 两个都由已有开关 `OMNI_LPV_ENTITY_LIGHTS` 控制，默认开；但体积光 `OMNI_LPV_ENABLED` 默认关，默认画面与原来完全一致。
- 构建（`build.py`）：离线编译补齐 Iris 标准宏 `MC_RENDER_STAGE_*`（取值照 Iris `WorldRenderingPhase` 序号），让阴影顶点里按绘制阶段分支的代码能进入全高配置编译。
- 差异说明记入 `docs/eclipse-parity.md` 的「LPV/间接光」行：方块实体光与掉落物光由「未合并」改为已合并；仍缺手持光与水下雾照明。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.148

给远景补上 TAA 抖动开关，并把远景进阴影图对照 Eclipse 记录清楚。

- 远景抖动开关 `OMNI_DH_TAA_JITTER`（`shaders/effects/clarity/antialiasing.glsl`，默认开）：控制远景地形与水是否随近景一起做逐帧时间抗锯齿抖动，来源 Eclipse `lib/settings.glsl:1098` 的 `DH_TAA_JITTER`。远景顶点在 `shaders/rendering/distant.glsl` 按它决定是否叠加本帧抖动，`shaders/common/coordinates.glsl` 的远景撤销抖动 `ViewPos_From_ScreenPos_DH` 用同一开关，两端口径一致；关闭后远景不抖、更稳，交界可能与近景错半像素。默认开，画面与原来完全一致。
- 远景进阴影图开关：确认为已有能力 `OMNI_DH_SHADOW`（`shaders/effects/shadow/shadow.glsl:56`，默认关），即 Eclipse `lib/settings.glsl:1081` 的 `DISTANT_HORIZONS_SHADOWMAP`，属换来源（Omni 用 iterationT 的 `DH_SHADOW`）。它在 `shaders/rendering/pipeline.properties` 开关 `dhShadow`，并在 `shaders/effects/lighting/composite_surface*.glsl` 判定远景叶片透光。本次未改代码，只对齐记录。
- 差异说明记入 `docs/eclipse-parity.md` 的「远景（DH）」行：`DH_TAA_JITTER` 由「未合并」改为已合并（新选项 `OMNI_DH_TAA_JITTER`），`DISTANT_HORIZONS_SHADOWMAP` 由「未合并」改为换来源（沿用 `OMNI_DH_SHADOW`）；`DISTANT_HORIZONS_SHADOWMAP` 关闭阴影失真的做法与 `DH_SHADOWPROJECTIONTWEAK` 仍无对应。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.147

把末地星空也换成 Eclipse 的实现，与主世界共用同一份 Eclipse 星场。

- 末地星空（`shaders/effects/world/end_sky.glsl`）：`EndCalculateStars` 不再自带 iterationT 的三维格子星空，改为直接调用主世界 `effects/sky/sky.glsl` 的 `CalculateStars(worldDir, worldSunVector)`，与主世界共用同一份 Eclipse `lib/stars.glsl` 星场。签名不变（仍只吃世界方向），调用点 `effects/world/end_disc.glsl` 的 `EndCalculateStars(rayDir)` 不用改。
- 与旧 iterationT 末地星空的差别：星点形状与疏密随 Eclipse 星场改变；朝向改用主世界 `CalculateStars` 的「绕日轴对齐天球」，不再按时间绕竖直轴旋转；原先独立的三维格子哈希、`coverage`/`maxLuminance` 与按格取样代码整体删除。`OMNI_STARS_COLORED` 同时作用于末地，开启后末地也是带星温的彩色星盒。
- 默认 `OMNI_STAR_TYPE=1`，末地天空像素会因此换星点外观（属本次要求的效果改动）；`OMNI_STAR_TYPE=0`（关星）或 `=2`（原版贴图）时与原来一致。
- 文件头与依赖同步（`end_sky.glsl`、`end.glsl`、`end_disc.glsl`）：星空改为依赖 `effects/sky/sky.glsl`，`remapSaturate`、`Blackbody` 不再由本文件使用。
- 差异说明记入 `docs/eclipse-parity.md` 的「星空」行与 `docs/parity.md` 偏离记录 49。
仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.146

给体积云加渲染分辨率选项：可让基础体积云在更低的分辨率上步进，再放大贴回天空。

- 体积云渲染分辨率 `OMNI_CLOUD_RENDER_SCALE`（`shaders/effects/cloud/cloud.glsl`，默认 1）：一为原分辨率（画面与行为不变），二或四让基础体积云在更低分辨率上算。对应 Eclipse `VL_RENDER_SCALE`（`lib/res_params.glsl:16`，原程序取 0.25/0.5/1.0）；本项目用整数除数 1/2/4 表达同一件事。
- 低分辨率模式新增两个延迟阶段（`shaders/rendering/deferred.glsl`、`shaders/rendering/programs.json`）：`deferred7` 在按选项缩小的十号画面上只步进基础体积云，写云的加色与透过率；`deferred8` 把十号画面按双线性放大，用「天空乘透过率加云色」贴回一号天空，再在全分辨率上补平面云与卷云、高层云、积雨云附加层。新增十号画面（`shaders/rendering/buffers.glsl` 的 `colortex10Format`、`colortex10Clear`，`shaders/common/uniforms.glsl` 的采样器）。
- 尺寸与开关接在绘制设置里（`shaders/rendering/pipeline.properties`）：按 `OMNI_CLOUD_RENDER_SCALE` 给十号画面设 `size.buffer.colortex10`（一半或四分之一边长），并用 `program.world0/deferred7.enabled`、`program.world0/deferred8.enabled` 只在分辨率大于一时执行这两步。这两个程序只存在于主世界，下界与末地不生成入口。
- 主天空与天空盒分流（`shaders/effects/sky/skyrender.glsl`）：`AccumulateSkyClouds` 增加 `applyClouds` 参数；低分辨率模式下主天空先只叠大气与天体，云留给延迟八号贴回，反射天空盒仍保持全分辨率算云。云影贴图不受影响。
- 默认与原分辨率：取一时 `OMNI_CLOUD_LOWRES` 不定义，天空仍由延迟三号内联算云，两条新阶段不运行，默认画面与行为完全不变。
- 近似与边界：低分辨率模式下，日月圆盘按体积云透过率整体压暗，与原来「雨天按湿润度在两套衰减之间插值」略有不同；放大只用双线性，未移植 Eclipse 的深度感知高质量上采样 `HQ_CLOUD_UPSAMPLE`；云在更低分辨率上算，边缘更软属预期。
- 差异说明记入 `docs/eclipse-parity.md` 的「体积云」行：`VL_RENDER_SCALE` 按近似合并，`HQ_CLOUD_UPSAMPLE` 仍无对应。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.145

把主世界星场整体换成 Eclipse `lib/stars.glsl` 的实现，并补上 Eclipse 的曝光乘数与加亮变暗三项控制。

- 星空核（`shaders/effects/sky/sky.glsl`）：删除 iterationT 的 `CalculateStars` 星场，改按 Eclipse `lib/stars.glsl` 移植 `hash13`、`NoisyStarField`、`StableStarField`、`stars`，以及彩色路径的 `hash12`（Eclipse `hash12_alt`）、`starTemp`、`starplane`、`starbox`。默认画面改成 Eclipse 默认的白色星点；`stars()` 的 `STARS_AMOUNT`/`STARS_BRIGHTNESS` 对应既有 `OMNI_STARS_AMOUNT`/`OMNI_STARS_BRIGHTNESS`，行为不变。
- 新选项 `OMNI_STARS_COLORED`（默认关）：开启后改用带星温的彩色星盒（Eclipse 的 `starbox`，对应 Eclipse 未默认开启的彩色路径）；只编进开启时的代码，默认关闭不产生无用分支。
- 与 Eclipse 的差异：Eclipse 用 `customRotation(sunPathRotation, worldTimeSmooth)` 摆星场，本项目沿用原有「绕日轴旋转」对齐天球；Eclipse 在合成阶段把星场乘十，本项目改用 `starScale` 对齐既有夜间曝光（白色路径最亮星与改动前一致）。
- 边界：本次只动主世界星空。末地星空仍是 iterationT 的 `EndCalculateStars`（`effects/world/end_sky.glsl`），未改。
- 接线核对：`docs/eclipse-parity.md`「星空」行由「近似」改为「已合并」，统计从「已合并 21 项 / 近似 6 项」更新为「22 项 / 5 项」。
- 曝光乘数 `OMNI_EXPOSURE_MULTIPLIER`（`shaders/effects/color/color.glsl`，默认 1.0）：在整个曝光上再乘一个系数，来源 Eclipse `lib/settings.glsl:773` 的 `EXPOSURE_MULTIPLIER`。
- 曝光变暗 `OMNI_EXPOSURE_DARKENING`（默认 1.0，取值 0.0–1.0）：把整个曝光往下压，一为不变、零为全黑，来源 Eclipse `lib/settings.glsl:778` 的 `EXPOSURE_DARKENING`。
- 曝光增亮 `OMNI_EXPOSURE_BRIGHTENING`（默认 1.0，取值 1.0–4.0）：把整个曝光往上抬，一为不变、越大越亮，来源 Eclipse `lib/settings.glsl:779` 的 `EXPOSURE_BRIGHTENING`。
- 三项都在 `GetExposureValue` 末尾叠到基础曝光上，手动与自动曝光都生效。近似说明：Eclipse 把这三项放进对数曝光曲线，与本项目的亮度单位不同，直接照搬会让增亮项几乎不起作用，这里改成整体增益，并把玩家看得到的名字 `EXPOSURE_BRIGHTENING` 取为正方向（原程序该项在分母里、方向相反）；默认都为一，乘一等于原样，画面与原来一致，原因记入 `docs/eclipse-parity.md` 的「色调与曝光」行。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.144

给雨点涟漪补上强度与对比两个选项。

- 雨点涟漪强度 `OMNI_RAIN_RIPPLE_STRENGTH`（`shaders/effects/water/water.glsl`，默认 1.0）：雨点砸在水面与地面时涟漪的起伏高低，乘在 `GetRainNormal` 末尾的雨点法线上；对应 Eclipse `settings.glsl:369` 的 `RIPPLE_STRENGTH` 搬动幅度的大意，取值按本项目重取。
- 雨点涟漪对比 `OMNI_RAIN_RIPPLE_CONTRAST`（默认 1.0）：对雨点法线幅度取幂、保留符号，调大亮圈更锐、圈外更平；Eclipse 没有这一项，是照本项目焦散「亮度 + 对比」的成对写法补的。
- 积雪法线与粗糙度（`shaders/effects/weather/snow.glsl`）：从 Eclipse 引入 `snowN.png`、`snowR.png`，积雪现在同时改底色、切线空间法线与粗糙度；本项目粗糙度由平滑度平方得到，所以按平方根反推后混入，属近似移植。
- 体积云采样数 `OMNI_CLOUD_SAMPLES`（`shaders/effects/cloud/cloud.glsl`，默认 20）：与既有的画质倍率相乘得到步数上限，默认值与移植前写死的步数逐行等价。
- 两个选项默认都为一，乘一与取一次幂都是原样，默认画面与原来完全一致。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.143

把 Eclipse 的世界空间体素反射整套搬进 Omni，并新建一张存方块颜色的体素图像。

- 体素颜色缓冲（`shaders/rendering/pipeline.properties`、`shaders/effects/reflection/voxel.glsl`）：新增自定义三维图像 `omniVoxelColor`，每格存一份方块底色（贴图色乘顶点染色）与打包光照（高四位方块光、低四位天光）。对比 Eclipse 原程序把每格六份方块颜色存进一张 SSBO（`lib/specular.glsl` 的 `voxelSSBO`，原程序已整体注释），本项目只存一份，显存占用低得多。体素编号图（`omniLpvVoxel`）原来只在开启体积光时分配，现改为体积光或体素反射任一开启就分配，并给它加了采样器名 `omniLpvVoxelTex` 供合成阶段读取。
- 体素写入（`shaders/rendering/shadow.glsl`）：阴影顶点阶段算出体素坐标并用 flat 变量传给片元，片元用采到的方块贴图色与光照调用 `omniVoxelColorStore` 写进颜色图；与编号图同一套下标，只在主世界近景地形写。
- 体素反射（`shaders/effects/reflection/voxel.glsl`）：沿反射方向在世界空间逐格步进（撞到实心方块就停），命中方块用它存下的底色与光照着色。水、冰、玻璃按半透明处理，只给后面的画面染色后继续走；植物不挡光直接穿过。来源 Eclipse `lib/specular.glsl:616` 的 `voxelReflection`（`VOXEL_REFLECTIONS_SOLID`/`VOXEL_REFLECTIONS_TRANSLUCENT`），改用本项目自己的体素图，不依赖任何模组。
- 接线（`shaders/effects/reflection/reflection.glsl`）：主世界合成二号里，屏幕空间反射没命中的像素再用体素反射补一次；命中就当作实心几何，不再取天空回退。
- 新选项：`OMNI_VOXEL_REFLECTION`（默认关）、`OMNI_VOXEL_REFLECTION_DISTANCE`（32/48/64/96，默认 64）、`OMNI_VOXEL_REFLECTION_STRENGTH`（默认 1.0），页面「反射」的子页「体素反射」。
- 近似与边界：直射光只按体素面朝太阳的余弦算，不查阴影图，阴影里的方块反射会偏亮；体素反射不叠加反射雾；缺计算能力或自定义图像能力时整段不编译，默认关闭时画面与原来完全一致。
- 差异说明（记入 `docs/eclipse-parity.md` 的「体素反射与模组支持」行）：Eclipse 的体素反射依赖 Photonics 模组的 `trace_wsr`，本项目按「不为特定模组编写专用适配」重做成自成一体的实现，能力等价但不含模组专用的彩色水与半透明叠加。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.142

补全 Eclipse 体积光（LPV）的四个细分项：彩色蜡烛、实体光源、雾照明与手持光阴影强度和质量。

- 彩色蜡烛 `OMNI_LPV_COLORED_CANDLES`（默认关，`shaders/block.properties`、`shaders/effects/lighting/lpv.glsl`）：点亮十七种颜色的蜡烛各自按自身颜色发彩色光，颜色与数量分列编号，颜色照 Eclipse `dimensions/setup.csh:12-33`、光强按一支三格到四支十二格照 `setup.csh:136-446`。默认关闭时这些方块编号不注册，画面与原来完全一致。
- 实体光源 `OMNI_LPV_ENTITY_LIGHTS`（默认开，等于 Eclipse；但体积光默认关，所以默认画面不变）：`shaders/entity.properties` 为烈焰人、发光鱿鱼、岩浆怪、点燃的TNT、小火球分配编号，光色与光强照 Eclipse `setup.csh:1161-1197`；`shaders/rendering/shadow.glsl` 的阴影顶点阶段在写地形体素之外，给这些发光实体写体素（来源 Eclipse `lib/voxel_write.glsl:129-168`）。不发光实体不写，光正常穿过。
- 雾照明 `OMNI_LPV_VL_FOG_ILLUMINATION`（默认关）与 `OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS`：体积彩色光照亮周围空气，洞穴里能看到带颜色的光晕；照 Eclipse `dimensions/composite3.fsh:235-262` 在体积雾步进里逐段累加，接在 `shaders/effects/fog/volumetric.glsl`，`shaders/effects/fog/fog.glsl` 只在开启时引入体积光取样。默认关闭时整段不产生代码。
- 手持光阴影强度与质量 `OMNI_HELDLIGHT_SHADOW_STRENGTH`、`OMNI_HELDLIGHT_SHADOW_QUALITY`（`shaders/effects/lighting/blocklight.glsl`）：对应 Eclipse `LPV_HANDHELD_SHADOWS_STRENGTH/_QUALITY`；强度默认零点八五、质量默认低，与升级前的手持光屏幕阴影逐位一致。本项目的手持光与阴影来自 iterationT（`OMNI_HELDLIGHT_SHADOW`），这里只补 Eclipse 的参数面。
- 差异说明：方块实体光（如附魔台、酿造台）与 Eclipse 的彩色灯具分类未接入；实体光源不含掉落的物品实体，逐条记进 `docs/eclipse-parity.md` 的「LPV/间接光」行。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.141

把 Eclipse 的 floodfill 彩色光传播体积（LPV）整体搬进 Omni，替换原来八格立方的简易体积光，并按需要补上体素化。

- 体素化（effects/lighting/lpv.glsl、rendering/shadow.glsl）：阴影顶点阶段把地形方块编号写进一张三维体素图，来源 Eclipse lib/voxel_write.glsl 的 PopulateShadowVoxel；只给地形与方块实体写，实体与玩家不挡光。写体素图要从顶点阶段访问图像，构建为此新增“程序级扩展声明”（rendering/programs.json 的 extensions，rendering/shadow 打开 GL_ARB_shader_image_load_store）。
- 方块光表（rendering/lpv.glsl 的 setup 阶段、effects/lighting/lpv.glsl 的 omniLpvBlockData）：计算阶段把每个方块编号的颜色、光强、透光率与六向可透掩码填进一张一维光表，颜色与光强照 Eclipse dimensions/setup.csh 逐类对照；表长 8192，比 Eclipse 的 2048 大，因为本项目方块编号最大到七千一百零二。
- 传播（rendering/lpv.glsl 的 shadowcomp 阶段）：每帧一步、双缓冲交替的 floodfill，用一个工作组覆盖一整块、先搬进共享内存再按掩码混合邻居，来源 Eclipse dimensions/shadowcomp.csh；体积随玩家按整格平移，搬共享内存时用上一帧相机位置补偿。
- 取样（effects/lighting/composite_surface.glsl）：合成零号按体积边缘淡出把彩色体积光混回方块光，法线偏移减少贴面漏光，来源 Eclipse lib/diffuse_lighting.glsl 的 doBlockLightLighting。
- 新选项：OMNI_LPV_SIZE（6/7/8，对应 64/128/256）、OMNI_LPV_SATURATION、OMNI_LPV_TINT_SATURATION、OMNI_LPV_NORMAL_STRENGTH、OMNI_LPV_REDSTONE_LIGHTS、OMNI_LPV_STRENGTH；移除旧的 OMNI_LPV_STEPS（旧简易算法被整体替换，配置需重设；旧名未保留迁移）。
- 验证探针：verify 的关键程序加入 shadow、setup、shadowcomp，并在全高配置再编一次，才能真正编到体积光开启时的分支；此前只有地形一组进全高，开启分支不会被编译。
- 未合并（记入 docs/eclipse-parity.md 的「LPV/间接光」行）：彩色蜡烛、彩色灯、实体光源、雾照明（LPV_VL_FOG_ILLUMINATION）、手持阴影，留作后续小步。
- 差异说明：体积光默认关闭，默认画面与原来完全一致；缺计算能力或自定义图像能力时整段不编译，退回屏幕空间间接光。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.140

补上 Eclipse 三处尚未实现的独立小选项，全部默认中性、默认画面不变。

- OMNI_MOON_COLOR_R/G/B（effects/sky/sky.glsl）：月亮圆盘颜色的三通道倍率，来源 Eclipse lib/settings.glsl:402-404 的 moonColorR/G/B；Eclipse 直接当月亮色，本项目改成乘在基础月亮色上的倍率，默认全一，接在 CalculateMoonDiscColor。
- OMNI_CROSSTALK（effects/color/colorgrade.glsl）：让亮度影响饱和度，来源 Eclipse settings.glsl:746 的 CROSSTALK 与 composite12.fsh:134 的串色项；Eclipse 饱和度与串色同一行，本项目饱和度在 color.glsl 的高级调色里，这里只补串色，默认零。
- OMNI_WATER_CAUSTICS_BRIGHTNESS / OMNI_WATER_CAUSTICS_POWER（effects/shadow/shadow.glsl）：水面焦散花纹的亮度倍率与对比指数，来源 Eclipse settings.glsl:999-1000，接在 CalculateWaterCaustics 返回值上，默认一比一。
- 差异说明：三项都是 Eclipse 独有参数，Omni 原有效果来自 iterationT，这里只补参数面、不改算法来源，逐条记进 docs/eclipse-parity.md 的「月亮与月食」「水雾与焦散」「后处理滤镜」三行。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.139

Eclipse 波浪模拟。

- 新增 OMNI_WAVE_SIMULATION（默认关）与 OMNI_WAVE_SIM_STRENGTH：水面变成会传播与衰减的水面场，玩家在水中移动会推出波纹并向外扩散。
- 算法在 effects/water/wavesim.glsl，三个计算阶段在 
endering/watersim.glsl，入口为各维度的 prepare*.csh；水面片元按压强权重把模拟波法线混进基础波法线。
- 差异：跨帧状态存一张四乘一图像而非共享缓冲；「站在水面上」用眼睛所在介质近似（不含船与载具）；分辨率与网格取低配档。

仅做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。

## 0.0.0-dev.138

补上 Eclipse 远景的三项参与开关：远景环境光遮蔽、叶片与雪透光、屏幕空间反射，三项默认开、等于现有画面，关闭才改变。

- `OMNI_DH_AO`（`effects/lighting/ambient.glsl`）：远景地形是否参与地平线遮蔽与全局光；接在 `ambient.glsl` 的时间滤波与遮蔽采样、`globalillumination.glsl` 的远景深度替换上，关闭时远景像素按天空处理。
- `OMNI_DH_SSS`（`effects/shadow/shadow.glsl`）：远景叶片与雪是否透光；接在 `composite_surface.glsl` 与 `composite_surface_end.glsl` 的远景叶片调整上，来源 Eclipse `DH_SUBSURFACE_SCATTERING`。
- `OMNI_DH_SSR`（`effects/reflection/reflection.glsl`）：屏幕空间反射是否命中远景地形；接在 `reflection.glsl` 的追踪取深度上，来源 Eclipse `DH_SCREENSPACE_REFLECTIONS`。
- 与 Eclipse 的差别属近似：Omni 没有独立远景深度缓冲，AO/SSS/SSR 走 iterationT 路径读 `dhDepthTex0/1` 与材质编号，开关只让远景像素按天空处理或不透光，不等价于 Eclipse 的独立滤波与网格化 SSS（对照 `docs/eclipse-parity.md` 的「远景（DH）」行与 `docs/parity.md` 偏离 48）。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.137

把 Eclipse 的天空散射系数引进预计算大气：新增天空亮度与瑞利/米氏散射系数倍率，默认全一、画面不变。

- 新文件 `effects/sky/skyscatter.glsl`：`OMNI_SKY_BRIGHTNESS`（Eclipse `Sky_Brightness`）与 `OMNI_SKY_RAYLEIGH_R/G/B`、`OMNI_SKY_MIE_R/G/B`（Eclipse `sky_coefficientRayleigh/Mie R/G/B`）。
- 接线在 `effects/sky/sky.glsl` 的 `GetSkyRadiance` 与 `GetSkyRadianceToPoint`：瑞利项乘 `omniSkyRayleighTint()`、米氏项乘 `omniSkyMieTint()`、整个天空辐射乘 `OMNI_SKY_BRIGHTNESS`。
- 近似说明：Omni 用预计算大气贴图，系数已烘进数据里，无法按新系数重算整条光路；这里缩放的是散射结果（放大瑞利更蓝更亮、放大米氏太阳白晕更强），严格的消光与多次散射不随之改变。表面天空环境光（`GetSunAndSkyIrradiance`）不受影响，与 Eclipse 一致。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.136

末地体积雾补上透射率：合成阶段改为“场景乘透射率加散射”，远处雾会压暗背景。

- 末地雾分两个入口：EndFog 只返回散射色（反射与折射用），EndFogWithTransmittance 另外返回剩余透射率（合成用），因为三个调用点签名相同、无法重载。
- 涡旋雾关闭时透射率恒为一，默认画面逐位不变。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.135

修复配置迁移与命名一致性，并把三个超长文件拆到可通读。

- **旧配置迁移真的生效了**：OPTION_RENAMES 之前没有任何代码读取，改名后的设置实际不会迁移；现在接入分享配置导入路径，新旧名同时出现会报错，并补了对应测试。
- 雾选项命名统一：OMNI_WATERFOG_*、OMNI_NETHERFOG_* 统一为带分隔的 OMNI_WATER_FOG_*、OMNI_NETHER_FOG_*，旧名登记进迁移表，全仓引用与测试同步。
- 拆分超长文件：effects/world/end.glsl 832 → 95 行（拆出世界组叠盘、天空、雾、主岛光照与反射五份）、effects/fog/fog.glsl 797 → 167 行（拆出体积雾、水下雾、地表散射、洞穴与边界雾、时段雾与原版雾六份）、shaders/rendering/terrain.glsl 768 → 346 行（算法体搬到 effects/ground/terrain_surface.glsl 与 grass_geometry.glsl）。
- 下界体积雾补上透射率：雾函数返回剩余透射率，合成阶段改成“场景乘透射率加散射”，背景会被雾压暗；绘制设置关闭时乘一，默认画面不变。
- 水洼尺寸真正影响水洼表面：“仅水洼”模式下按覆盖率改写粗糙度与暗度，默认模式不参与编译。
- 镜头发水：新增 OMNI_WATER_ON_CAMERA（默认关），用眼睛所在介质与相机速度近似，文件头写明与 Eclipse 真实现的差异。
- 文档：每日天气不影响平面云与积雨云的结论写清依据（Eclipse 本身就没有这两层的来源）。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.134

终审（HOP、iterationT 复核、Eclipse 复核）指出的问题修正；其中一项会改变默认画面，已拉回与 iterationT 一致。

- 一号画面多级纹理：补上 colortex1MipmapEnabled。之前缺这条声明，自动曝光读第六级多级纹理时读不到内容，整幅自动亮度会偏离 iterationT。
- 清理死代码：删除 AgXConfigurable 一族、CalculateSunlightColors（已内联进 
endering/lights.glsl）与七段数码管一族（PrintFloat 等）；DHTerrainCulling 改为由 
endering/distant.glsl 调用，不再内联重复。
- 材质倍率与遮蔽：实体视差路径也补上，与地形路径一致。
- 选项迁移：追加 iterationT 自带拼写错误的六个旧名映射，导入 iterationT 配置时不丢设置。
- 文档：docs/parity.md 追加两条偏离记录（多级纹理声明、死代码删除）。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.133

按独立审查指出的“选项存在但没真生效”修正接线，并同步对照文档。

- 水洼反射锐度：OmniPuddleRoughness 接入 MaterialFromTex，OMNI_PUDDLE_REFLECTION_SHARPNESS 现在真的改变湿表面粗糙度；本项目没有雪面粗糙度，湿表面粗糙度固定取中间值。
- 材质倍率与遮蔽：视差路径补上法线倍率与材质遮蔽，各加入路径的行为与其他路径一致；为此把两步拆成 omniMaterialAO 与 omniMaterialNormalScale 供复用。
- 区块淡入：水面顶点补上滑动档，与地形共用同一判据与同一函数。
- 受伤效果：补上着火热浪与溺水压暗两项；没有氧气量，溺水用“在水下且血量偏低”近似。
- 文档：docs/eclipse-parity.md 逐项改成真实状态（新合并项移出未合并，仍缺项写清原因）；docs/parity.md 补记九号画面与新增偏离记录；清理两处过期文件头说明。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.132

每日天气接入云量与常规雾，并补上远景可行的两项附加能力。

- 云量（effects/cloud/cloud.glsl）：每日天气的四层云按高度映射到 Omni 的基础积云、高层云与卷云（低空两层合并取大值）；两项雾密度接入体积雾标度，与暴风通道互斥不重叠。
- 远景（effects/world/distant.glsl）：过绘防护（限制远景与近景重叠区域的重复上色）与噪声远距衰减，默认中性。
- 远景 AO、SSS、SSR 经核对未单独接线：Omni 的环境光遮蔽、次表面散射与屏幕空间反射已按 iterationT 路径读远景深度与材质，能力本己存在，只是没有独立开关。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.131

Eclipse 缺失能力第四批：环境与天气。补上每群系环境、行星曲率、雪暴与沙暴、每日天气，默认全部中性。

- 每群系环境（effects/world/biome.glsl）：沼泽、丛林、黑森林与苍白花园四套雾色与雾密度，权重由加载器按生物群系兼六十秒平滑（
endering/pipeline.properties）。
- 行星曲率（effects/world/planet.glsl）：按相对水平距离的平方下沉，同一函数接入地形、实体、水面、阴影、远景、粒子与手持等全部顶点阶段，开启时深度与阴影看到同一份几何；水下手持未接。
- 雪暴与沙暴（effects/weather/storm.glsl）：按下雪标记与无降水标记乘雨量、雷暴强度，在体积雾里叠一层浓雾并染色。
- 每日天气（effects/weather/dailyweather.glsl）：十天天气表按游戏日取值，晚上入体积雾；为避免菜单变成一百项，表放在 GLSL 常量数组，玩家只有总开关、随机与周期三项。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.130

程序化草（Eclipse 的 shader grass）已落地，并建立最小可用的体素方块编号通路。

- 方块编号缓冲：九号画面改为不清除的编号图，地形片元写入方块编号与生物群系，环境与草叶取用上一帧内容；编号与用途在 
endering/buffers.glsl 登记，逐维度说明在三份维度文件。
- 草效果（effects/ground/grass.glsl）：地形几何阶段按方块编号挑出草方块顶面并长出草叶，支持风动与范围，默认关闭。
- 未做：景得没有细分着色器（入口生成器不产出 .tcs/.tes），草叶数量比 Eclipse 精简；同一次绘制内读写同一张缓冲属未验证风险，需游戏内确认。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.129

Eclipse 缺失能力第三批：交互与细节。补上玩家交互水面、受伤与低血量、区块淡入、水洼尺寸、材质 AO 与法线倍率、太阳色与辐照，全部默认关闭或中性。

- 玩家交互水面（`effects/water/playerwater.glsl`）：照 Eclipse 简单模式的涟漪，叠在现有波法线上；入水位置与时刻改用相机位置与时间相位近似（加载器不给跨帧冻结量），所以是持续外扩涟漪而非一次性水花。
- 受伤与低血量（`effects/lens/hurt.glsl`）：用 Iris 的 `currentPlayerHealth`/`is_hurt` 做红边、心跳脉冲与死亡红屏；镜头发水与着火需要跨帧平滑量，未做。
- 区块淡入（`effects/clarity/chunkfade.glsl`）：用 Iris 的 `FADE_VARIABLE` 与 `mc_chunkFade` 属性，地形与水的新区块渐显；水面顶点未接滑动档。
- 水洼尺寸（`effects/water/puddle.glsl`）：覆盖形状照 Eclipse `applyPuddles`；反射锐度因粗糙度在合成阶段解出、超出本次改动范围，暂未接线。
- 材质 AO 与法线倍率（`effects/ground/material.glsl`）：地形、实体、半透明与 overlay 的法线解码统一走 `omniMaterialNormal()`，可缩放切线法线并把遮蔽乘进底色。
- 太阳色与辐照（`effects/sky/suncolor.glsl`）：黑体色温与 RGB 两路，接在太阳圆盘与日月辐照上，默认取 1.0 中性。
- 资源包天空经核对不可行：Iris 没有天空专用自定义采样器，Eclipse 是跨程序写 `colortex9` 再合成的方案，涉及缓冲与多处流程，本轮未实现，原因记录在对照文档。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.128

Eclipse 缺失能力第二批：体积雾体系。补上洞穴雾、边界雾、下界三段体积雾、末地涡旋体积雾与主世界时段雾，默认全部关闭，默认画面不变。

- 洞穴雾与边界雾（`effects/fog/fog.glsl`）：照 Eclipse 合成四号的实现，洞穴雾按视线距离与视向竖直梯度变浓，边界雾在远裁剪面附近拉起一层雾墙遮住区块加载；洞穴判据用 `eyeBrightnessSmoothCurved` 等价替代加载器黑暗计时。
- 下界体积雾（`effects/world/nether.glsl`）：照 Eclipse `lib/nether_fog.glsl` 的羽流、雾霭、天花板烟三段，指数步进；与既有解析雾并列叠加。
- 末地涡旋雾（`effects/world/end.glsl`）：照 Eclipse `lib/end_fog.glsl`，三维噪声叠绕竖轴旋转与球/圆环范围限制，附加光柱与雾霭；未搬吸收率与 `colortex4` 驱动的雾中闪电，原因见文件注释。
- 主世界时段雾（`effects/fog/fog.glsl`）：照 Eclipse 的晨/午/晚/夜四段权重与晴/多云两套系数，接入体积雾密度标度。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.127

Eclipse 缺失能力第一批：后处理。新增色彩分级、镜头形变三项与胶片颗粒，默认全部中性，默认画面不变。

- 色彩分级（`effects/color/colorgrade.glsl`）：阴影/中间调/高光三段色带与亮度曲线，照 Eclipse `composite12` 的实现接在色调映射之后，10 个选项默认关闭或中性。
- 镜头形变（`effects/lens/distortion.glsl`）：全屏色差、鱼眼与像素化（含色数量化），照 Eclipse `final` 的实现；与既有散景色散作用对象不同，不重复处理同一像素。开启形变时最终画面按畸变坐标重采样 `colortex1`。
- 胶片颗粒（`effects/clarity/grain.glsl`）：照 Eclipse `final` 的 `FILM_GRAIN` 段，接在色调映射之后、显示空间里，默认关闭；时间来源用 `frameTimeCounter`。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.126

按三份独立对抗式审查（iterationT 覆盖、Eclipse 覆盖、HOP 符合度）修问题，并补上 iterationT 唯一未移植的 `TITLE` 标志叠加。

- 结构：`rendering/composite.glsl` 1241 → 197 行、`deferred.glsl` 618 → 400 行、`post.glsl` 581 → 234 行，算法体分别落到 `effects/` 下的效果文件；同一批全局声明不再在每个程序块重复，收进共享头。
- 效果文件：把视差从通用名 `ground/material.glsl` 拆到 `ground/parallax.glsl`，搜索即可命中；合成零号的维度变体拆成 `composite_surface.glsl` 主本体与下界、末地两份；末地天空两段重复代码合并为一个共用函数。
- 清理：删除 14 个零调用函数与两条与实现不符的注释。
- 命名：选项 `OMNI_PC_*` 统一为 `OMNI_PLANAR_*`，`OMNI_FTC_OFFSET` 改为 `OMNI_CLOUD_TIME_OFFSET`，旧名保留在迁移表里，老配置不丢设置。
- 补齐 iterationT：移植 `TITLE` 标志叠加（默认开），默认画面在右下角显示 logo 并把加载计时写进二号画面顶行 `(20,H-1)`，行为与 iterationT 一致；下界图标染色暂用曝光替代，原因记录在 `docs/parity.md`。
- 文档：`docs/eclipse-parity.md` 按实际代码改回真实状态（月亮轨道与月食月相已合并；色彩分级、色差、颗粒、鱼眼、洞穴与边界雾等标明未合并），`docs/parity.md` 更正已删函数清单并新增偏离记录。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.125

把 `itt-port` 的移植成果合入 `main` 并推送（合并提交 `c23eb0a`），随后同步文档里的分支状态，并把 `verify` 的选项接线检查改为一次分词，回到约五到七秒。

- 分支：`itt-port` 领先 `main` 16 个提交、`main` 无独有提交，以 `--no-ff` 合并提交落地；GitHub「检查与构建」在推送后通过，十秒预算未超。
- 性能：`check_option_wiring` 原先对每个选项在整个代码池上逐个正则搜索，最慢时占三秒；改为一次分词成集合后按名字查表，本机 `verify` 由约十秒回到约五到七秒。
- 探针：`verify` 的编译探针收为三个程序（`gbuffers_terrain`、`shadow`、`final`），加地形一组全高与开远景共四组唯一程序；文档里的程序数与耗时按实际同步。
- 文档：`AGENTS.md` 与 `docs/parity.md` 改为说明移植已合入 `main`；`docs/review.md` 的 Ashima 行标注为当时文件；测试计数统一为 114。
- 退役：删除已无引用的 Ashima 噪声库并新增「登记库必须被引用」测试。
- 文档：按独立审查更正 `docs/eclipse-parity.md` 的合并状态与 Omni `file:line`（月亮轨道/月相/月食已合并、近似与未合并逐项标注），更正 `docs/parity.md` 的 `common/` 函数清单与函数计数，并补记未移植的 `TITLE` 标志叠加（偏离记录第 37 条）。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性仍未验证。

## 0.0.0-dev.124

iterationT 3.2.0 全量移植完成，并合并 Eclipse 的部分能力；按三轮独立审查与五轮 HOP 审查修完结构与文档问题。

- 管线：主世界 7 个 deferred、16 个 composite 与 final，缓冲按 iterationT 的九张画面与曲线编码单位；下界与末地按各自的程序集与逐维度常量声明生成入口。
- 效果：`shaders/effects/` 按菜单页面分文件夹，天空与大气、云、间接光、光照与阴影、水、天气、反射、雾、后期与两个维度的专属内容都已移植；选项与 iterationT 有效选项一一对应。
- 合并 Eclipse：自定义月亮轨道与月食、星空数量与亮度、积雪覆盖、白平衡色温、景深变形与色散、水洼模式、末地主岛可选点光源、远景区块淡入、末地雾密度、卷云/高层云/积雨云与云内闪电。着色器草地经评估依赖体素方块编号子系统，未落地并在对照文档写明原因。
- 审查修复：末地屏幕空间阴影改传视空间方向、删除末地 deferred4 的错误门控、恢复下界末地泛光恒开、闪电照明默认关、调试视图与性能计时接线、逐维度缓冲声明由各维度入口引入、射线质量提升为玩家选项。
- 工具：`expand` 改为线性拼接，`verify` 从约十秒降到约八秒并在其中保留一小组编译探针；全部程序与全部代表配置的编译由 `python build.py compile` 负责；选项接线改为全树检查。
- 文档：重写 `docs/rendering.md`，过期文档移入 `docs/history/` 并标明历史；`docs/parity.md` 路径与选项数按实际更正；新增 `docs/eclipse-parity.md`。
- 依赖：退役已无引用的 Ashima 噪声库（`dependencies.json` 改为空清单，随包不再含 `libraries/`），并新增「登记库必须被引用」测试，防止再留下死依赖。

只做过离线编译、审计与单元测试；游戏内画面、性能与兼容性未验证。
## 0.0.0-dev.123

按 `docs/parity.md` 把 iterationT 3.2.0 的全部算法与渲染流程一比一移植进本项目结构（本地分支 `itt-port`，合并进 `main` 前还需游戏内对照）。

- 管线整体替换：主世界 7 个 deferred、16 个 composite、final，缓冲改为 iterationT 的九张画面与「除以 `MAIN_OUTPUT_FACTOR` 再四次方根」的单位链路。
- 效果文件按菜单页面分文件夹放在 `shaders/effects/`，一比一移植天空与大气、云、间接光、光照与阴影、水、天气、反射、雾、后期（色调映射、曝光、泛光、景深、运动模糊、抗锯齿、锐化与放大）以及下界配色与末地天空；绘制主体在 `shaders/rendering/`。
- 预计算大气数据、云噪声、涟漪动画、噪声贴图与方块、实体、物品编号表随包引入。
- 选项对照 iterationT 全部保留并加 `OMNI_` 前缀（共 283 个，其中并入与移除的旧名见 `docs/parity.md` 第十二节），项目自己的额外功能（极光、彩虹、闪电、季节、光传播体积、调试视图、性能计时）保留并已接进新管线。
- 新增 `python build.py compile`：放宽到 300 秒的完整离线编译；`verify` 的十秒预算装不下整包编译，移植期只跑生成、审计与引用检查。

只做过离线编译与逻辑审查；世界内画面与性能未验证。
## 0.0.0-dev.122

对齐 iterationT 3.2.0 的云与天气第四步：雨滴溅射与地表湿润的细分参数。

- `shaders/effects/weather.glsl` 新增 `omniRainSplash`：雨滴落在水面上溅起的圈，振幅单独可调，不再与「波纹强度」绑在一起；取零时仍保留落点密度选项。
- 新增 `omniRainWetResponse`：下雨时地面变湿的快慢与深浅，乘在加载器给的湿润度上，取零时地面不因下雨变湿。
- `shaders/effects/water.glsl` 的雨点圈振幅乘上溅射强度；`shaders/effects/material.glsl` 显式引入天气效果并把湿润响应乘进地面湿润量，不再依赖地形文件的引入顺序。
- 新增选项：`OMNI_RAIN_SPLASH`（雨滴溅射强度，默认 1.0）、`OMNI_RAIN_WET_RESPONSE`（地表湿润响应，默认 1.0）。
- 选项总数 194 → 196（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.121

对齐 iterationT 3.2.0 的云与天气第三步：云底亮度、外散射、淡出距离与噪声尺度。

- `shaders/effects/cloud.glsl` 云的颜色增加一个下限：背光面（夜里、阴雨、背对太阳）至少保留一份底光，不会全黑。对应参考里的 `CLOUD_BOTTOM_BRIGHTNESS`。
- 银边的正向散射指数改成可调：指数越高，阳光越集中在太阳方向，云边更收拢。对应参考里的 `CLOUD_OUTSCATTER_FACTOR`，默认取四以保持原画面。
- 云增加可见最远距离：超过该距离的云逐渐融进天空，远处不再出现硬边；体积云与平面云共用同一距离。
- 云块边缘碎边的噪声频率单独可调，对应参考里的细节噪声尺度。
- 新增选项：`OMNI_CLOUD_BOTTOM`（云底亮度，默认 0.15）、`OMNI_CLOUD_OUTSCATTER`（云外散射，默认 4.0）、`OMNI_CLOUD_FADE`（云淡出距离，默认 18000）、`OMNI_CLOUD_NOISE_SCALE`（云噪声尺度，默认 1.0）。
- 选项总数 190 → 194（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.120

对齐 iterationT 3.2.0 的云与天气第二步：晴天与雨天两套云参数，云照明拆成直射与天光。

- `shaders/effects/cloud.glsl` 把云量、云厚度、云密度、云块大小、云受光、云天光都改成「晴天一档、雨天一档」，按加载器的湿润度在两套之间平滑切换：雨越大越靠近雨天那档，雨停后云比雨散得慢。参考里 `CLOUD_CLEAR_*` 与 `CLOUD_RAIN_*` 的这种两套切换即由此对应，数值按本项目口径另取。
- 云的颜色从原来的昼夜插值拆成直射分量加天光分量：太阳照亮云顶，天光托住背光面与夜里底色。晴天两档都取一，结果与旧的昼夜插值完全一致，默认画面不变；雨天直射压暗、天光保留，阴云自然变灰，不再另乘一个降雨压暗系数。
- 新增选项：`OMNI_CLOUD_DENSITY`（云密度，默认 1.0）、`OMNI_CLOUD_SUNLIGHT`（云受光，默认 1.0）、`OMNI_CLOUD_SKYLIGHT`（云天光，默认 1.0）、`OMNI_CLOUD_RAIN_COVERAGE`（雨天云量，默认 0.95）、`OMNI_CLOUD_RAIN_THICKNESS`（雨天云厚度，默认 64）、`OMNI_CLOUD_RAIN_DENSITY`（雨天云密度，默认 1.0）、`OMNI_CLOUD_RAIN_SCALE`（雨天云块大小，默认 1.0）、`OMNI_CLOUD_RAIN_SUNLIGHT`（雨天云受光，默认 0.4）、`OMNI_CLOUD_RAIN_SKYLIGHT`（雨天云天光，默认 0.8）。
- 云影同样使用晴雨两档的厚度与密度倍率，所以雨天云影更深，与可见云保持一致。
- 选项总数 181 → 190（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.119

对齐 iterationT 3.2.0 的云与天气第一步：云提供体积与平面两套做法，可用选项切换。

- `shaders/effects/cloud.glsl` 新增 `omniPlanarCloud` 与 `omniPlanarDensity`：平面云只求视线与云层高度平面的交点，用四层单纯形噪声叠出连续云块，不做沿视线的体积步进，代价与云厚度无关。它与体积云共用同一套昼夜颜色与银边，切换时色调不突变。
- 新增 `OMNI_CLOUD_MODE`（云的做法，默认体积）：体积云沿视线步进，厚实有层次；平面云更省也更平。命名与说明按本项目口径，未复制参考源码。
- `omniCloudShadow` 增加平面分支：把地表沿阴影方向投到同一张云平面上取密度，可见云与地上的云影在两种做法下都对得上，不新增缓冲。
- 选项总数 180 → 181（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.118

- 修正 `shaders/effects/sunlight.glsl` 里手持光遮挡注释的一处措辞，把「为什么本函数不判断开关」写清楚：开关由调用方的编译分支决定，函数本体保持单一职责。只改注释，不改行为。

只做过离线编译与逻辑审查。

## 0.0.0-dev.117

对齐 iterationT 3.2.0 的光照与阴影收尾：云影同时影响天光。

- 以往云影只压直射光，环境光不受云影响。`sunlight.glsl` 现在把云影按一个可调比例也乘到环境光上：云挡住太阳时，整片环境光一起略暗，更接近真实。云影关闭时该系数恒为一，这一步等于没做，不影响原有画面。
- 新增 `OMNI_CLOUD_SHADOW_AMBIENT`（云影影响天光，默认 0.5），定义在 `shaders/effects/cloud.glsl`，因为它是云影的一部分；计算在统一光照里按现有云影结果应用。
- 沿用已有做法，不新增屏幕空间的云影贴图文件：本项目用体积步进得到云影，与可见云共用同一份密度，功能上覆盖参考的云影贴图。
- 选项总数 179 → 180（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.116

对齐 iterationT 3.2.0 的光照与阴影第四步：手持光模式与手持光遮挡。

- `shaders/effects/sunlight.glsl` 把手持光从单一球形衰减扩展成两种模式，并让它会被物体遮挡。
- 新增 `OMNI_HELDLIGHT_MODE`（手持光模式，默认点光）：点光以相机为中心向四周照亮；手电筒朝视线方向打出一束锥形光，越靠视线中心越亮。
- 新增 `OMNI_HELDLIGHT_SHADOW`（手持光遮挡，默认开）：`omniHeldShadow` 从表面沿法线抬离一点，向相机方向走八小步，逐步读屏幕深度；比脚步更靠近相机的几何就是挡住光的物体。被挡住时留一点底光，避免全黑。手持光源在相机上，所以用屏幕空间射线而不是太阳的阴影图。
- 没拿光源时跳过整段衰减与遮挡计算，只有手持光源等级大于零才付出这份开销。
- 选项总数 177 → 179（不删除任何现有选项）。

只做过离线编译与逻辑审查；手持光遮挡为屏幕空间近似，世界内画面与性能未验证。

## 0.0.0-dev.115

对齐 iterationT 3.2.0 的光照与阴影第三步：方向性方块光。

- `shaders/effects/sunlight.glsl` 新增 `omniDirectionalBlock`：把方块光等级在屏幕上的梯度，用世界位置的两条屏幕导数还原成一个沿表面的世界方向，再和表面法线比较。朝光的一面略亮、背光的一面略暗，火把附近的立体感更强。参考做法见 `references/iterationT/.../Terrain_FS.glsl` 的方向性方块光分支，按本项目口径重写。
- 新增 `OMNI_DIRECTIONAL_BLOCKLIGHT`（方向性方块光，默认开）与 `OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH`（方向性强度，默认 0.5）。
- 顺带修一处接线：`shaders/rendering/distant.glsl` 原先在文件顶部引入 `effects/sunlight.glsl`，会连顶点阶段一起编译；光照用到屏幕导数，顶点阶段没有该函数。现把该引用移进片元块，只让片元编译到它。
- 选项总数 175 → 177（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.114

对齐 iterationT 3.2.0 的光照与阴影第二步：给阴影加上可变半影。

- `shaders/effects/shadow.glsl` 的遮挡查询改为 PCSS 思路：先在接收点附近估计遮挡物的平均深度，再按「接收点深度减遮挡物深度」的差放大柔化半径。差越大说明遮挡物离得越远，影子边缘越软；贴着时边缘保持锐利。这正是固定柔化核做不到的近实远虚。
- 采样用黄金角螺旋散开，并按阴影图坐标取每像素随机起步角，避免规则条纹。图外样本一律当作照亮，不在阴影图边界压出黑线。
- 新增 `OMNI_SHADOW_PENUMBRA`（可变半影，默认开）、`OMNI_SHADOW_PENUMBRA_QUALITY`（半影精细度，默认中 16）、`OMNI_SHADOW_BLUR`（阴影模糊，默认 1.0）。关闭可变半影时回到固定柔化核，模糊选项同时加大该核半径。
- 顶点阶段也会编译本文件，所以随机源用阴影图坐标而不是 `gl_FragCoord`；对应把 PCSS 加入审计术语表。
- 彩色半透明阴影本轮未实现：需要阴影通道额外写出半透明颜色并区分实体／半透明深度，见本轮报告。
- 选项总数 172 → 175（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.113

对齐 iterationT 3.2.0 的光照与阴影第一步：把阳光与天光拆分，并补上夜间与无光亮度。

- `shaders/effects/sunlight.glsl` 把太阳与月亮的直射能量、白天与夜间的天空环境光分别列出来，不再混在一条 `mix` 里，昼夜切换和色温调整的来源更清楚。
- 新增 `OMNI_SKYLIGHT_STRENGTH`（天光强度，默认 1.0）：环境光里来自天空那一份的占比，与阳光强度相互独立。
- 新增 `OMNI_NIGHT_BRIGHTNESS`（夜间亮度，默认 0.5）：只压月光与夜空的亮度，白天不受影响；默认让夜晚比原来更暗、更接近写实。
- 新增 `OMNI_NOLIGHT_BRIGHTNESS`（无光亮度，默认 0.5）：洞穴深处既无天光也无火把时的最低亮度，取零表示允许完全变黑。
- 对齐取自 iterationT 3.2.0 的选项口径（`SUNLIGHT_INTENSITY`、`SKYLIGHT_INTENSITY`、`NIGHT_BRIGHTNESS`、`NOLIGHT_BRIGHTNESS`），按本项目命名重写，未复制参考源码。
- 选项总数 169 → 172（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.112

按审查修三处大气散射的实现问题：

- 视线采样改成非均匀步长：采样点落在比例平方分布上（近密远疏），每段用自己的实际长度积分。地平线方向整条约 875 公里，等分时每段约 55 公里、远大于瑞利 8 公里与米氏 1.2 公里的标高，近地高密度空气会被整段跳过；改后前几段约 3.4、10.3、17.1 公里，近地明显加密。`OMNI_ATMOSPHERE_STEPS` 含义不变，仍是段数。
- 相机半径加上玩家高度：在 `shaders/common/uniforms.glsl` 声明 Iris 的 `eyeAltitude`（米），换算成公里后加大气底半径，高空看天空时结果正确；地下负高度按零处理，保持贴地合理。
- 太阳贴到地平线时不再直接判零：改用当地地平线方向做一段由太阳视半径决定的平滑过渡，黄昏时高空仍能收到暖色，不会在日落瞬间整片变黑。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.111

按 `docs/algorithms.md` 的第一项，把主世界天空换成物理大气散射：

- `shaders/effects/sky.glsl` 用公开的 `Bruneton` 预计算散射模型独立实现：沿视线数值积分得到视线透过率、瑞利与米氏单次散射（相位函数）、太阳方向透过率和一份多次散射近似；公式与常数取自公开论文，未复制参考光影源码，也不引入查找表纹理。
- 大气散射的两项原有选项（`OMNI_ATMOSPHERE_SCATTER`、`OMNI_SCATTER_STRENGTH`）从 `atmosphere.glsl` 移到 `sky.glsl`，名字、默认值和范围不变，现在控制真实模型；`atmosphere.glsl` 只保留极光与彩虹，避免同一片天空算两遍。
- 新增选项：`OMNI_ATMOSPHERE_STEPS`（散射精细度，默认中 16）、`OMNI_ATMOSPHERE_MIE_G`（米氏方向性，默认 0.8）、`OMNI_ATMOSPHERE_OZONE`（臭氧强度，默认 1.0）、`OMNI_ATMOSPHERE_MULTIPLE`（多次散射强度，默认 1.0）。
- 选项总数 165 → 169（不删除任何现有选项）。

只做过离线编译与逻辑审查；世界内画面与性能未验证。

## 0.0.0-dev.110

- 新增 `docs/algorithms.md`：记录 iterationT 3.2.0 的大气模型常数、各算法的计算内容、Omni 对应文件与要补的选项，以及执行顺序。下一步按它逐模块实现。

本版本先读清并记录算法与常数，不复制参考源码；实现从大气散射开始。

## 0.0.0-dev.109

- 新增 `docs/parity.md`：与 iterationT 3.2.0 的能力与选项对照，以及按影响排序的补齐顺序（天空 → 光照阴影 → 云天气 → 水 → 后处理 → 间接光 → 材质 → 远景）。目标是选项数量不少于参考并逐项接到真实计算。

仅文档更新。

## 0.0.0-dev.108

朝真实风格靠拢的第一步（对照 iterationT 3.2.0 的能力表）：

- 高光压缩方式可选：AgX、ACES、Filmic、简单；默认 AgX，仍由强度在最保守曲线与所选曲线之间插值。ACES 与 Filmic 用公开公式独立实现。
- 显示伽马可调（默认二点二），白点可调（多大亮度算纯白）。
- 自发光不再固定四倍：新增自发光亮度与自发光伽马，灯笼一类发光块不再过曝。
- 选项 160 → 165。

本版本只做过离线编译与逻辑审查；世界内画面未逐一核对。

## 0.0.0-dev.107

按实机日志继续修：

- 缓冲格式改为放进块注释：加载器读的是名字，而自己定义名字会被展开成数字、导致格式被忽略；放进块注释后编译器看不到它，加载器仍能按名字读到。行尾注释同时去掉，避免读不到。
- 阴影顶点把 `mc_Entity` 与 `mc_midTexCoord` 拆成两行声明：合在一行时加载器给加成式阴影程序（`shadow_sodium_terrain_solid`）识别不到 `mc_Entity`，报 `iris_Entity` 未定义。
- 生成的入口宏改为带值（`#define OMNI_VERTEX 1`）：不带值时加载器把它们当成含义不明的开关并忽略，日志出现“Ignoring ambiguous boolean option”。
- `terrain.glsl` 里按能力补定义的 `OMNI_OVERLAY` 也改为带值并加存在判断，避免与入口重复定义冲突。
- 审计：块注释里成行的机器语句（预处理指令、常量声明）不按自然语言检查；普通注释仍要求中文。

本版本只做过离线编译与逻辑审查；加载是否恢复正常需要实机确认。

## 0.0.0-dev.106

修 `deferred.fsh ... undefined variable "RGBA16F"`：

- 缓冲格式名在 GLSL 里没有定义，加载器也只按名字读取；原来自以为加载器会提供这些名字，实际没有，于是编译报未定义。现在在 `buffers.glsl` 里自己给出一份等价常量（`RGBA16F` 与 `RGBA32F`）。
- 格式指令行去掉行尾注释，只留指令本身；格式指令对行内其它文字敏感，带上说明可能读不到。
- 离线编译不再替光源注入这些格式名（之前正好掩盖了这个错误），改成从源码读取；显卡测试工具同步。
- 新增检查：格式指令行必须干净且行尾只有分号，格式名必须由包内自己定义。

本版本只做过离线编译与逻辑审查；加载是否恢复正常需要实机确认。

## 0.0.0-dev.105

按实机日志修三处加载问题：

- 致命：`const vec4 colortex8ClearColor = vec4(0.0);` 用了单参数构造，加载器解析 const 时要求 vec4 必须四个参数，于是整包加载失败（报 `Index 1 out of bounds for length 1`）。改成四个参数。
- 警告：`OMNI_LIGHTNING`、`OMNI_VOLUMETRIC_LIGHT`、`OMNI_LPV_ENABLED` 三个开关只被 `#if defined` 判断过，加载器不把它认成选项，菜单里三个条目解析不到。改为用一次普通条件编译（定义与未定义各判一次）。
- 自定义图像的字段写法按文档改正：像素格式与图像格式用小写、像素类型用 `float`，避免后续解析出错。
- 新增检查：布尔选项必须在某处按定义与未定义各判一次；`const vecN` 构造参数个数必须与类型一致；自定义图像字段个数、大小写与像素类型必须合法。这三条正好对应上面三个问题。

本版本只做过离线编译与逻辑审查；加载是否恢复正常需要实机确认。

## 0.0.0-dev.104

修实机提示「用了自定义图像却没有声明能力开关」：

- 绘制设置的可选能力加上 `CUSTOM_IMAGES`，和 `COMPUTE_SHADERS` 一样属可选，缺少时仍能加载。
- 光传播体积的图像读写改为同时要求计算着色器与自定义图像两种能力；缺任一种就回退屏幕空间间接光，不读取未写入的体积格。
- 离线检查的环境宏同步补上 `IRIS_FEATURE_CUSTOM_IMAGES`，与加载器一致。
- 新增检查：声明了自定义图像就必须在可选或必需能力里出现，且每处图像读写都按能力开关回退。

本版本只做过离线编译与逻辑审查；加载与画面需要实机确认。

## 0.0.0-dev.103

继续修光影加载失败（实机复现仍在）：

- 上一版只清了行注释里的示例引用，漏掉了块注释 `/* */` 里的示例。`temporal.glsl` 与 `lighting.glsl` 文件头的块注释里各有一段示例引用，同样被加载器当成自我包含。
- 清掉这两处，改成中文说明。
- 检查改为先挖掉块注释再判断，这样行注释和块注释里的示例都会被挡下。

本版本只做过离线编译与逻辑审查；加载是否恢复正常需要实机确认。

## 0.0.0-dev.102

修光影加载失败（实机发现）：

- 文件头注释里的示例引用被加载器当成真正的引入，读出自我包含循环，光影整包加载失败，表现为画面无变化、设置打不开。加载器在去注释之前扫描引用，所以注释里只要有 `#include "..."` 就会触发。
- 清掉九个文件头里注释形式的引用示例，改成中文说明，不再出现 `#include` 字样。
- 新增检查：任何含 `#include` 的行必须是干净的引用行，且整行只能是指令加一个带引号的路径，防止注释里的示例再次混进引用解析。

本版本只做过离线编译与逻辑审查；加载是否恢复正常需要实机确认。

## 0.0.0-dev.101

按后台审查核实后修正直射光照：

- 高光原先并进光照总量后又整体乘底色，深色方块几乎没有高光、非金属高光被染色；改为漫反射乘底色、高光单独相加。
- 高光反射率与屏幕反射统一口径：非金属读 labPBR 绿色通道的反射率（没有材质包时为零点零四），金属用底色作反射色；金属不再吃直射漫反射，环境光保留作为周围反光的近似。
- `ambient.glsl` 中名不副实的 `normalLength` 改名为 `inverseNormalLength`。
- 审查的另外三条经核对不改：屏幕反射非金属反射率写法本来正确（labPBR 约定）；延迟与合成阶段对同一画面边读边写由加载器的主备双缓冲保证；屏幕外反射回退里跑体积云的开销属于未测量的性能风险，留待实机测量。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.100

修正上一轮自查出的错误与逻辑漏洞：

- 雨雪程序编译失败：程序宏 `OMNI_WEATHER` 与 `weather.glsl` 的引入标记同名，整段天气代码被跳过。程序宏改为 `OMNI_WEATHER_PASS`，新建文件的引入标记统一改为 `_INCLUDED` 结尾，并新增测试禁止引入标记与程序宏、选项同名。
- `verify` 改为编译主世界的全部程序与另外两个维度的主要通路（110 组程序），原先只编主路，漏掉了雨雪程序。
- 雨雪可见度改为缩放颗粒透明度，取零时完全消失，不再画成黑条；雨雪区分改读 Iris 的 `biome_precipitation`，删掉温度猜测。
- 雨的斜度改在顶点阶段按高度推移整片雨雪几何，不再随贴图滚动漂移。
- 落点密度取零时跳过雨点计算，避免除以零。
- 行星曲率改在世界空间计算，相机俯仰不再改变弯曲方向；系数改为距离平方除以两倍半径，强度一相当于两万米半径。
- 资源包天空重做：开关决定加载器是否画日月贴图；关闭原版天空几何并把零号画面清成黑色，延迟阶段把贴图叠在自定义天空上、云下面。原写法里贴图会被延迟阶段整片覆盖，开启后看不到太阳。
- 远景雾衔接改为只在近景渲染距离附近补一圈雾，原写法在强度一时会盖住整片远景。
- 雨天变暗乘头顶天空光，洞穴和室内不再跟着变暗。
- 季节改按顶点群系染色识别植被，草方块顶面、树叶、藤蔓一起变色，花不再被染黄。
- 生物受光不再作用箱子等方块实体；手持物视野按半视野角正切之比缩放，等价于真实改视野。
- 渲染缩放的缓冲尺寸回到 `pipeline.properties` 唯一来源，删除 `options.py` 里写死的特殊代码；绘制设置读取器允许同一个键出现在互斥的条件分支中；`buffers.glsl` 写明六号画面会被缩放及取样规则。
- 删除发光实体上写不出去的自发光标记；文档与参数总表同步到实际行为。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.99

- 更新 `docs/capabilities.md`：补上本轮新增的菜单、季节、生物与玩家、天气、世界与远景、渲染缩放、性能计时六块，并修正关于内部渲染分辨率的过期说明。

仅文档更新；不启动 Minecraft。

## 0.0.0-dev.98

- 菜单子页面：一个主分类来自多个效果文件时，先分效果子页面，再列选项；只有一个效果时保持平铺。子页面名称直接复用效果标题，不另写一份。
- 档位取值人话名称：新增 `value.<选项>.<取值>` 生成，档位按钮不再只显示数字；`@option` 支持 `values` 字段，取值名称和选项定义放在一起。
- 悬停说明补齐：新增八十条说明，所有 160 个选项现在都有中文与英文悬停说明。
- 参数总表状态与实际对齐，全部列出的参数均已实现。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.97

- 新增性能计时 `OMNI_PROFILER`：在屏幕左下角画一条按整帧耗时长短变化的横条，快帧偏绿、慢帧偏红。加载器只给整帧时间，没有逐效果计时，所以它是整帧耗时的近似，不是逐效果明细。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.96

- 新增渲染缩放 `OMNI_RENDER_SCALE`（五十、七十五、一百）：合成阶段的颜色缓冲按较低分辨率渲染，再在时间阶段放大回全分辨率，省下云、雾、遮蔽与反射的像素开销；几何阶段仍写全分辨率。
- 缓冲尺寸由菜单生成器按选项取值自动写出到绘制设置，不手工维护第二份数值；合成阶段读取全分辨率像素坐标改用统一坐标函数，缩放后仍读对位置。
- 边缘重采样按缩放比例略微加强，分辨率越低越有用。
- 审计放宽预处理器指令行：`#if`、`#endif` 这类机器语句不算自然语言说明。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试；渲染缩放的实际收益与画质影响均未验证。

## 0.0.0-dev.95

- 新增远景开关 `OMNI_DH_ENABLED`：关闭时很远的区块不再计算光影，只按原版光照亮度上色；默认打开，保持现有行为。
- 新增远景雾衔接 `OMNI_DH_FOG_BLEND`：在很远处额外补雾，抹平近远景交界的雾差；取零保持原状。
- 新增使用资源包天空 `OMNI_RESOURCE_SKY`：开启时改用资源包自带的日月贴图，关闭时沿用内置日月圆盘。为此在绘制设置里让加载器提供日月贴图（`sun=true`、`moon=true`），是否显示由选项决定。
- 日月贴图程序改用独立宏 `OMNI_SKYTEXTURED`。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.94

- 新增极光颜色 `OMNI_AURORA_TINT`：在绿与蓝紫之间调整极光帘幕颜色。
- 新增天气参数：雨的可见度 `OMNI_RAIN_VISIBILITY`、雪的可见度 `OMNI_SNOW_VISIBILITY`、雨的斜度 `OMNI_RAIN_WIND`、落点密度 `OMNI_RAIN_DENSITY`。
- 雨雪几何改用独立宏 `OMNI_WEATHER` 识别；可见度按高度与噪声估计的冷暖在雨雪之间选择，斜度按贴图纵向位置偏移采样，落点密度驱动水面雨点格子的精细度。

可见度的雨雪区分是位置近似，不是真实降水类型；本版本只做离线编译与逻辑审查，未启动 Minecraft。

## 0.0.0-dev.93

- 参数改名对齐参数总表：材质细节 `OMNI_LABPBR`→`OMNI_MATERIAL_DETAIL`、自动积雪 `OMNI_CLIMATE`→`OMNI_CLIMATE_SNOW`、生物受光 `OMNI_ENTITY_STRENGTH`→`OMNI_ENTITY_LIGHT`。
- 手持物由整体缩放改为视野：`OMNI_HAND_SIZE`→`OMNI_HAND_FOV`（三十到一百二十度，七十度为原版大小）。
- 新增玩家发光遮盖 `OMNI_PLAYER_GLOW`：发光实体按普通受光与自身发光色之间插值；发光实体改用独立宏 `OMNI_GLOWING`。
- 旧分享配置里使用旧名称会被当作未知选项拒绝，需按当前名称重新导出。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.92

- 修正季节效果里的注释：`block.properties` 中 10001 是树叶、10002 是草与农作物，原注释把两者编号写反了；代码判断本来就同时覆盖两者，只改说明。

仅注释修正，未改算法；不启动 Minecraft。

## 0.0.0-dev.91

- 新增四个效果文件并接入：季节（草与树叶随世界天数变色）、生物与玩家（生物受光强度与色温、手持物大小）、天气（雨天整体压暗）、世界与远景（行星曲率压低远景地平线）。
- 菜单主分类的天气、生物、世界三页随选项出现，十五个分类全部有内容；新增自检测试确保每个选项恰好落在一个分类、且没有空分类。
- `uniforms.glsl` 增加 `worldDay`，季节相位使用加载器给的真实世界天数。

本版本只做离线编译与逻辑审查，未启动 Minecraft，未运行 GPU 或性能测试。

## 0.0.0-dev.90

- 闪电开关与闪电强度通过 `page` 归入「天气」分类；极光、彩虹、大气散射保留在「天空」。天气页首次出现在菜单里。

本版本只调整菜单归属，未改算法；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.89

- 菜单生成器改为按主界面分类生成：15 个分类（天空／云／雾与空气／水／地面与植物／光照／影子／反射／画面颜色／镜头／清晰与流畅／天气与季节／生物与玩家／世界与远景／开发者），不再按效果文件名和字母排序。
- 支持 `@option` 用 `page` 覆盖所在效果的页面（遮蔽选项归到「影子」）；每页固定三栏排布。
- 新增自检：每个选项必须恰好落在一个已登记页面，否则构建失败；未登记页面同样失败。
- 未接效果时对应分类不显示（天气、生物、世界三页暂无选项）。菜单与主助手不再手工同步。

本版本只改菜单生成，未改效果算法；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.88

- 泛光显示名对齐参数总表：「泛光开关／泛光强度／泛光起点／泛光范围」。
- 超分新增「超分强度」，并把显示名改为「超分开关」；强度取零等于关闭。
- 选项从 141 增到 142。

本版本只改显示名与一个强度参数；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.87

- 地面与植物按参数总表调整显示名：材质→「材质细节开关／凹凸深度／湿润开关／湿润程度／积雪程度／额外积雪／自动积雪开关」；植被→「植物摆动开关／摆动幅度／摆动速度」。

本版本只改显示名，未改算法；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.86

- 雾效果按参数总表重写：显示名改为「雾开关／雾浓度／雾颜色／高度雾开关／高度雾浓度／高度雾起始高度／高度雾衰减／体积光开关／阳光光柱强度／水下光柱强度／光柱精细度／水下雾开关／水下雾浓度／水下颜色／末地雾开关／末地雾浓度／下界雾浓度」。
- 新增「雾开关」「雾颜色」「高度雾开关」「水下光柱强度」「水下雾浓度」「水下颜色」「末地雾浓度」「下界雾浓度」；水下光柱改用独立强度，不再和阳光光柱共用一个。
- 选项从 133 增到 141。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；雾的观感仍未实机验证。

## 0.0.0-dev.85

- 镜头效果显示名按参数总表调整：「景深开关／运动模糊开关／耀斑开关／散景形状／暗角强度／色差强度／景深强度／模糊强度／耀斑强度」，说明改成只用 Minecraft 的话。

本版本只改显示名与说明，未改算法；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.84

- 修正删除算法选择后注释里的过时措辞：「抗锯齿模式二」→「开启抗锯齿」、「固定/自动模式」→「手动/自动」、「时间算法」→「时间合成」、「非时间抗锯齿模式」→「未开启抗锯齿」。
- 本批的 opencode 旁观审查因自身上下文耗尽未给出结论，只留下可辨认的过时措辞项；已按该项修复。其余结论由主助手静态审查补充。

本版本只改注释，未改算法；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.83

- 反射效果按参数总表重写：显示名改为「屏幕反射开关／天空反射开关／反射强度／反射清晰度／反射降噪／反射模糊」。
- 新增「天空反射开关」：关掉后屏幕外回退为零，只保留屏幕命中，不再照出天空与云。
- 补提交上一轮遗漏的 `reflection.glsl`（此前后续检查因该文件未入库而失败）。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；反射观感仍未实机验证。

## 0.0.0-dev.82

- 清晰与流畅（抗锯齿）按参数总表重写：去掉「抗锯齿算法」选择（关／FXAA／TAA），只保留一套时间重投影，删除 FXAA 函数。
- 新增「抗锯齿开关」与「抗锯齿强度」；抖动门、镜头模糊、环境遮蔽时序噪声、合成时间合成全部改读新的开关。
- 预设同步：真实与氛围启用抗锯齿，轻量档关闭抗锯齿。
- 选项从 132 增到 133。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；抗锯齿观感仍未实机验证。

## 0.0.0-dev.81

- 画面颜色（调色）按参数总表重写：去掉「色调映射」算法选择与 `ACES` 函数，改为单一「高光还原强度」，在简单曲线与 AgX 之间插值。
- 显示名改为「曝光／自动曝光开关／曝光目标／曝光适应速度／亮度／对比度／饱和度／白平衡／高光还原强度／色带消除开关」。
- 选项总数保持不变（去掉一个算法选择，新增一个强度参数）。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；调色观感仍未实机验证。

## 0.0.0-dev.80

- 按天空效果旁观审查修复：
  - 下界氛围色在地平线以下的系数方向改对：此前「压暗」与「提亮」两式相抵，实际地平线反而更亮，与注释相反。
  - 更正 `fogColor`/`skyColor` 的空间说明：它们是显示空间（sRGB）颜色，代码转线性是正确的，之前注释把空间写反。
  - 明确「天空整体亮度」只作用主世界，下界与末地底色不读它。
- 天空的星空极点接缝、下界末地无用计算等为已知小项，未在本步处理。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；天空观感仍未实机验证。

## 0.0.0-dev.79

- 间接光（环境遮蔽与物体反光）按参数总表重写：去掉「遮蔽算法」选择，只保留一套地平线积分，删除螺旋采样旧代码。
- 显示名改为「缝隙变暗开关／变暗强度／变暗范围／变暗方向数／变暗精细度／物体反光开关／物体反光强度／物体反光范围」。
- 新增「物体反光范围」：反光用独立半径，不再和缝隙变暗共用一个范围。
- 选项总数保持不变（去掉一个算法选择，新增一个范围参数）。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；间接光观感仍未实机验证。

## 0.0.0-dev.78

- 光照效果按参数总表重写：显示名改为「阳光强度／阳光色温／环境光强度／环境光色温／火把光强度／火把光色温／手持光开关／手持光亮度／镜面高光」。
- 新增「环境光色温」「火把光强度」「手持光亮度」：环境光色温作用于所有维度环境光，火把光强度与手持光亮度各自独立。
- 选项从 128 增到 131。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；光照观感仍未实机验证。

## 0.0.0-dev.77

- 天空效果按参数总表重写：显示名改成直观词，并新增「太阳大小」「月亮大小」「日月色温」「星星数量」「日落颜色」「天空整体亮度」「末地天空亮度」。
- 日月圆盘大小改成由角半径控制；日月色温用同一偏移同时作用于太阳与月亮；星星数量直接改亮格阈值。
- 下界程序化天空保留为开关，显示名与说明对齐参数总表。
- 选项从 121 增到 128。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；天空观感仍未实机验证。

## 0.0.0-dev.76

- 按云效果旁观审查修复：
  - 云影改成与可见云共用同一份密度、同一套上下边缘渐薄和同一消光系数，只采样方向不同；薄云、高云的地影会跟着变淡，不再偏实偏大。
  - 云影采样步数与「云精细度」联动，并改为按米累积光学厚度；修掉厚云地影像平板的问题。
  - 云量取零时明确没有云，并省下噪声采样；修正 `parameters.md` 的云量范围为 0.0–1.0。
  - 显式引入加载器输入，不依赖间接包含；补注释说明云影用阴影天体方向、云色用太阳方向的取舍。
- 补回归：云影与可见云共用边缘渐薄、按米累积光学厚度。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；云观感仍未实机验证。

## 0.0.0-dev.75

- 按水效果旁观审查修复：
  - 删除 `omniWater` 未参与运算的 `color` 参数，并同步调用处与回归测试，避免误以为水面光照有生效。
  - 远景水面（DH）顶点补上海浪抬升，与近景共用同一 `omniOceanHeight`；此前只有远景法线起伏、顶点不动，交界处水面会断开。
  - 把「盖斯特纳海浪」改称「多层正弦海浪」，注释与能力表如实说明只做垂直位移、无水平挤压。
  - 修正 `parameters.md` 的清澈度范围（0.5–4.0）与重复的反射强度条目；修正 `reflection.glsl` 文件头对 `view` 方向的说明。
- 补回归：远景水顶点位移与近景同源。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水面观感仍未实机验证。

## 0.0.0-dev.74

- 云效果按参数总表重写：只保留一套体积云，去掉「云算法」选择（单层/体积/平面），删除平面云代码。
- 显示名改为直观词（云量、云高度、云厚度、云块大小、云速、云亮度、云色冷暖、云边缘透光、云影开关、云影浓淡、云精细度）。
- 新增「云亮度」与「云影浓淡」：云影浓淡取零等于没有云影；云量新增取零即无云。
- 预设同步：去掉云算法项，轻量档改用较低的云精细度。
- 选项从 120 增到 121。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；云观感仍未实机验证。

## 0.0.0-dev.73

- 水面效果按参数总表重写：显示名改成直观词（波浪大小、波浪速度、波浪密度、水面凹凸深度、海浪开关、水色红绿蓝、浑水色红绿蓝、清澈度、水面高光、雨点波纹开关、波纹强度、玩家水纹开关）。
- 新增「海浪大小」与「清澈度」：清澈度直接缩放水体吸收，越大水越清。
- 选项从 118 增到 120。
- 参数总表与菜单设计作为本轮重写依据；水面是第一个按新规范完整落地的效果。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水面观感仍未实机验证。

## 0.0.0-dev.72

- 忽略浏览器工具在仓库内产生的临时目录 `.playwright-mcp/`，避免它被中文注释审计当成源码扫描。

本版本只修改忽略规则，未改动效果代码；不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.71

- 用浏览器核实许可：AMD FidelityFX（CACAO）与 Sebastian Lague Clouds 均为 MIT。
- 明确区分两类来源：能直接接入的独立 GLSL 库（Ashima、SMAA、XeGTAO、glsl-atmosphere）与只能作参考、按原理重写的引擎源码（Filament、Godot、three.js、FidelityFX、Bruneton）。
- 更新 `docs/libraries.md` 与 `docs/references.md` 的许可与分类。
- 本版本只写文档，未改效果代码。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.70

- 新增算法参考清单 `docs/references.md`：按效果列出可参考实现、语言、许可与处理方式（直接用 / 按原理重写 / 小库直接重写）。
- 核实三个大型宽松许可来源：Google Filament（Apache-2.0）、Godot（MIT）、three.js（MIT），覆盖 PBR、SSAO、SSR、TAA、DOF、泛光、体积雾、色调映射、超分等。
- 明确「算法外包、自己只留对接」的判断标准，以及采用第三方代码时的来源与许可登记要求。
- 本版本只写文档，未改效果代码。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.69

- 新增库调研 `docs/libraries.md`：列出已核实许可、可直接采用的库（Ashima、SMAA、XeGTAO、glsl-atmosphere、Bruneton），需再核实许可的库，以及明确不能用的来源（Photon、主流光影包、lygia 商业限制）。
- 明确没有现成 Minecraft 光影框架，真实感主体仍需按公开论文独立实现；建议把数学/噪声/颜色/抗锯齿/超分/AO/大气交给库，自己只保留效果组合与 MC 对接薄层。
- 本版本只写文档，未改效果代码。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.68

- 新增菜单设计 `docs/menu.md`：定下主界面 15 个分类与子页、直观命名规则、去掉算法选择、质量参数放置规则、菜单自检规则。
- 新增参数总表 `docs/parameters.md`：覆盖全部玩家可调参数（约 180 条，含已有、需改、新增、缺失），并明确哪些 Iris 接口保持内部不暴露。
- 两份文档是后续重写菜单与参数的依据；本版本只写文档，未改效果代码。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.67

- 反射模糊半径参数化，替换不去噪路径里写死的十字模糊范围。
- 新增回归：确认反射模糊参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；反射观感仍未实机验证。

## 0.0.0-dev.66

- 环境遮蔽质量参数化：方向数与每方向步数各自可调，允许在稳定度和开销之间取舍。
- 新增回归：确认两个遮蔽质量参数已登记并驱动循环。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；遮蔽观感仍未实机验证。

## 0.0.0-dev.65

- 闪电强度参数化，替换原先写死的倍率。
- 新增回归：确认闪电强度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；闪电照明观感仍未实机验证。

## 0.0.0-dev.64

- 水面凹凸强度参数化，与波强度共同缩放细节，取零关闭。
- 新增回归：确认凹凸强度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水面观感仍未实机验证。

## 0.0.0-dev.63

- 能力表同步本轮改动：新增 `ACES` 色调映射、水面太阳高光、云银边与屏幕外反射复用天空合成，以及各效果的参数化。
- 说明只描述参数意图与已知近似，不把未实测的画面或性能写成已完成。

本版本只修改文档，未改动效果算法；仍不启动 Minecraft，不运行 GPU 或性能测试。

## 0.0.0-dev.62

- 新增 ACES 近似色调映射，与 AgX、简单曲线并列可选，参考真实感风格的第三种高光压缩。
- 新增回归：确认三种色调映射都已接入最终显示。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；色调映射观感仍未实机验证。

## 0.0.0-dev.61

- 体积云步数参数化：体积云沿视线的采样步数可调，质量与开销可权衡。
- 新增回归：确认体积云步数参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；云的观感仍未实机验证。

## 0.0.0-dev.60

- 体积光步数参数化：阳光光柱沿视线的采样段数可调，质量与开销可权衡。
- 新增回归：确认体积光步数参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；体积光观感仍未实机验证。

## 0.0.0-dev.59

- 水面新增太阳高光（鳞光）：水面法线朝向太阳时出现窄亮带，只在白天出现，强度可调，取零关闭。
- 反射关闭时不再采样天空与屏幕，水面合成流程更短。
- 新增回归：确认水面高光参数已登记并只在白天生效。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水面高光观感仍未实机验证。

## 0.0.0-dev.58

- 水纹强度参数化：雨滴水纹与玩家涟漪共用同一强度。
- 新增回归：确认水纹强度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水纹观感仍未实机验证。

## 0.0.0-dev.57

- 自动曝光参数化：目标亮度与适应速度各自可调，替换原先写死的零点一八与一点五。
- 新增回归：确认两个曝光参数已登记并参与计算。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；曝光观感仍未实机验证。

## 0.0.0-dev.56

- 雾的体积光强度参数化，阳光光柱与水下光柱共用同一强度。
- 新增回归：确认体积光强度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；体积光观感仍未实机验证。

## 0.0.0-dev.55

- 间接光参数化：环境遮蔽强度与屏幕反弹强度各自可调，替换原先写死的封顶系数。
- 新增回归：确认两个间接光强度参数已登记并参与计算。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；遮蔽与反弹观感仍未实机验证。

## 0.0.0-dev.54

- 轻量预设补全关闭项：镜面高光、气候、云影、水面凹凸、海浪、水下体积光、末地雾与镜头耀斑在轻量档一并关闭，此前仍会执行。
- 新增回归：确认轻量预设确实关闭这些较重的默认效果。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；性能与画面差异仍未实测。

## 0.0.0-dev.53

- 材质参数化：湿润强度与积雪强度各自可调，替换原先写死的覆盖量，默认值保持原有画面。
- 新增回归：确认两个材质强度参数已登记并参与计算。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；湿润与积雪观感仍未实机验证。

## 0.0.0-dev.52

- 水面折射强度参数化，替换原先写死的偏移系数。
- 新增回归：确认折射强度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水面折射观感仍未实机验证。

## 0.0.0-dev.51

- 镜头参数化：景深强度、运动模糊强度与耀斑强度各自可调，替换原先写死的倍率。
- 新增回归：确认三个镜头强度参数已登记并参与计算。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；镜头观感仍未实机验证。

## 0.0.0-dev.50

- 植被参数化：摆动强度与速度各自可调，替换原先写死的振幅与频率。
- 新增回归：确认两个植被参数已登记并参与相位与位移。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；植被观感仍未实机验证。

## 0.0.0-dev.49

- 氛围参数化：极光、彩虹与大气散射强度各自可调，替换原先写死的倍率。
- 新增回归：确认三个氛围强度参数已登记并参与着色。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；氛围观感仍未实机验证。

## 0.0.0-dev.48

- 天空参数化：日落强度、太阳亮度与月亮亮度各自可调，替换原先写死的倍率。
- 新增回归：确认三个天空亮度参数已登记并参与着色。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；天空观感仍未实机验证。

## 0.0.0-dev.47

- 阴影参数化：比较偏置与法线偏移各自可调，替换原先写死的余量与抬升距离，用于压制阴影条纹和自身遮挡。
- 新增回归：确认两个阴影参数已登记并参与比较与采样。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；阴影观感仍未实机验证。

## 0.0.0-dev.46

- 云的前向散射（银边）：逆着太阳看云更亮、顺着看更暗，体积云与平面云共用同一份方向响应。
- 银边强度是可调参数，取零时保持原来的均匀受光。
- 新增回归：确认银边参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；云的观感仍未实机验证。

## 0.0.0-dev.45

- 屏幕外反射回退改为复用背景天空的同一套合成：先天空再云再氛围，反射里也能看到云与极光，不再只有纯天空色。
- 选项接入校验改为每个展开文本只扫描一次，避免按选项对整段文本重复跑正则；检查开销随文本增大而暴涨的问题消除。
- 修复后冷缓存完整检查从超过十秒降到约四秒，仍保留默认与高效果两组、关键通路全量编译。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；反射与天空一致性仍未实机验证。

## 0.0.0-dev.44

- 泛光参数化：亮度阈值与光晕半径各自可调，替换原先写死的白色阈值与固定半径。
- 新增回归：确认两个泛光参数已登记并参与筛选与采样。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；泛光观感仍未验证。

## 0.0.0-dev.43

- 水波空间尺度参数化：只缩放解析波频率，雨滴与玩家涟漪仍按真实世界坐标定位。
- 新增回归：确认水波尺度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；水波观感仍未验证。

## 0.0.0-dev.42

- 云块尺度参数化：同时作用于体积云与平面云，大于一云块更小更碎，小于一更大更整。
- 新增回归：确认云块尺度参数已登记。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；云的观感仍未验证。

## 0.0.0-dev.41

- 高度雾参数化：基准高度与衰减各自可调，替换原先写死的六十四格与零点零三五。
- 新增回归：确认两个高度雾参数已登记并参与密度计算。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；雾的观感仍未验证。

## 0.0.0-dev.40

- 光源颜色参数化：日月色温与方块光色温各自可调，正值偏暖、负值偏冷，默认零即保持现有画面。
- 色温换算收在一个函数里，只让红蓝反向移动、绿色不动，避免调色温时整体亮度漂移。
- 新增回归：确认两个色温参数已登记且被直射光与方块光分别使用。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；色温观感仍未验证。

## 0.0.0-dev.39

- 水体光谱参数化：分波段吸收与散射色各拆成红绿蓝三个可调参数，波速独立可调，默认值与原先写死的数值一致。
- 水面合成与水下雾继续共用同一份光学常数，只是常数现在来自选项，仍只有一处来源。
- 新增回归：确认七个水体参数已登记，吸收向量只由选项组成，水下雾复用水面函数。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；画面效果与各参数的观感仍未验证。

## 0.0.0-dev.38

- 修复泛光非有限值处理：原写法“与自身比较后乘零”既清不掉非数也拦不住无穷大，改为对非数或无穷直接赋零。
- 修复地平线环境遮蔽：没有任何有效邻点时不再被当成最大遮挡，孤立几何和天空边界不再被压暗到上限。
- 修复云影：关闭云显示时不再产生云影；云影只在体积云真实高度区间内取样，不再对云层下方的空气计算厚度。
- 新增云层厚度选项，体积云上下界与云影采样范围改用同一参数，替换原先写死的三十二米。
- 水体吸收与散射常数额只保留一份，水面合成与水下雾共用，消除两处数值不一致。
- 屏幕像素取整统一到 `omniPixel`，删除四个复制实现；构建的源文件编号也收拢到一处。
- 开发目录写入边界集中在 `paths.py` 一个来源；配置保存与游戏工具不再各写一份相同检查。
- AgX 色调映射补上公开来源说明。
- README 不再硬编码版本号，改为指向 `VERSION`，避免同一数据两处定义且过期。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；画面效果仍未验证，参考效果与可调参数仍有大量缺口。

## 0.0.0-dev.37

- 编译配置从逐选项扫描缩减到默认与高效果两组，只编译主要绘制通路及额外维度合成分支。其余入口保留来源、阶段配对和引用检查，不声称全部模式都已编译。
- 所有独立编译任务同时提交；主体引用展开共用缓存，移除重复目录扫描和历史大矩阵缓存。
- 检查、构建、开发同步增加十秒执行预算；超时终止整组子进程并明确失败，不将未完成检查算作通过。
- 新增 `python build.py verify`，工具测试与光影检查并行，打包也包含在同一个十秒预算内。
- Actions 只使用 Ubuntu 执行一次快速检查并上传产物，新提交取消旧提交的重复检查。平台排队、下载和上传不属于十秒执行预算。

本版本修改开发检查流程，没有新增游戏画面或性能证据。

## 0.0.0-dev.36

- 上采样文件保护宏与玩家开关分离，源码默认关闭状态不再被文件引用自动改成开启。
- 气候积雪改为正序平滑插值后取反，消除起止阈值颠倒的未定义计算；湿润温度权重与菜单的暖处更湿说明一致。
- 编译成功缓存按完整阶段源码计算摘要，防止删除块注释后把不同变量拼成同一名字并错误复用记录。旧摘要自然失效，首次检查需要重新编译。
- 增加真实编译器回归：先缓存合法程序，再插入隔开变量的块注释，确认错误源码仍被拒绝。
- 新测试把函数进度输出收进内存，避免 Windows 英文系统的默认终端编码使测试提前失败。

本版本只执行离线验证，不启动 Minecraft，不运行 GPU 或性能测试；画面效果仍未验证。

## 0.0.0-dev.35

- Python 工具按 `agent-core` 注释风格整理：构建、审计、开发环境、独立游戏调试和配置分享都补充职责、调用示例、设计原因与安全取舍。
- 内部流程命名更直观，外部命令、配置字段、测试契约与玩家文件边界保持不变。
- LPV 片元采样改用 Iris 官方可选能力标志 `IRIS_FEATURE_COMPUTE_SHADERS`，没有计算能力时保留屏幕空间回退。
- 审查与构建工具说明明确区分离线证据、游戏证据和性能证据。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.34

- 构建改为并行调用 glslang，按源码摘要去重后同时编译多个独立程序；缓存命中时只检查新增任务。
- CI 超时从 15 分钟提高到 30 分钟，并缓存锁定工具与同一源码的 GLSL 通过记录，避免慢速 Windows 运行器被提前取消。
- 修复 LPV 图像写入缺少 `memoryBarrierImage()` 的高严重度逻辑错误；基础片元路径没有可靠计算能力标志时不读取未写入的三维纹理，保留屏幕空间回退。
- 增加 LPV 图像屏障回归测试；本地通过 70 项测试、234 个文件审计和 7185 组 GLSL 程序链接。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.33

- 坐标、数学、输入与绘制流程共十一个文件按 `agent-core` 注释风格重写：文件头写清管什么、调用位置、可复制示例与设计原因；行注释讲清“做什么、为什么、考虑点”。
- 顺手按 HOP 拆单职责函数并加段落标题，例如坐标抖动换算、水面判断、场景重建、噪声分层、延迟天空、时间历史判断与元数据写入、切线基、远景附件写入。
- 未改算法、数值、选项名、缓冲编号与对外函数名；编译与链接全部通过。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.32

- 十二个效果文件按 `agent-core` 注释风格重写：文件头写清管什么、调用位置、可复制示例、设计原因与取舍；行注释讲清“做什么、为什么、考虑点”，面向没有专业基础的读者。
- 顺手按 HOP 拆分单职责函数并加段落标题，例如环境遮蔽切片积分、时序邻域边界、云色与覆盖率、视差坐标、星点、泛光样本；未改算法、数值、选项名与缓冲编号。
- 修正中文说明里夹带的裸英文词（如 `uniform`、`bounds`、`exp`），使其符合审计的英文拒绝规则。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.31

- 项目规范新增注释风格：参考隔壁 `agent-core`，文件头写职责、调用位置、可复制示例与设计原因，行注释讲清“做什么、为什么、考虑点”，面向非专业读者。
- 项目规范新增：子任务开始前必须先读 HOP 技能，并以 HOP 为最高标准，发现不遵循就改，包括必要的破坏性重构。

本版本只修改项目规范文档，未改动任何效果代码。

## 0.0.0-dev.30

- 十四个效果文件并行做优雅降级整理：非有限值、退化方向、越界或零尺寸、无效历史等异常输入时保守回退，默认选项下的画面结果保持不变。
- 具体：环境遮蔽、抗锯齿、大气、泛光、云、调色、雾、镜头、材质、反射、阴影、天空、直接光、水面各自补上安全回退与更直观的命名和文件头。
- 反射与地平线遮蔽拆成单职责函数，流程更平直；泛光去掉仅高版本可用的布尔混合写法，保持基础路径 330 兼容。
- 同步更新引用旧标识符的契约测试；未改选项名、数值、缓冲编号或对外接口。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试；常态画面是否与整理前逐位一致仍需实机确认。

## 0.0.0-dev.29

- 项目规范补充：不针对特定模组编写专用适配，高兼容性通过光影自身的能力检测与优雅降级实现，模组缺失不影响基础画面。
- 项目规范补充：并行实现时每个子任务只负责一个效果文件，独立编辑、互不重叠；提交与推送由主助手统一完成。

本版本只修改项目规范文档，未改动任何效果代码。

## 0.0.0-dev.28

- 可读性整理之四：`build.py` 与 `audit.py` 中不直观的局部命名改为完整含义，例如展开用的源文件编号映射、编译环境组合、缓存成功记录、报错用的编号到路径映射，以及审计里的注释片段、起始行、行内偏移。
- 只改内部局部命名与说明，不改对外命令、选项名、生成入口内容与缓冲协议。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.27

- 可读性整理之三：统一效果与绘制文件的命名，把难懂的过度缩写改为日常词或完整含义：`props` 改为 `materialParams`（粗糙、金属、自发光），`kind` 改为 `category`（表面类别），`tbn` 改为 `tangentFrame`（切线基）；保留 `uv`、`ssao`、`lpv` 等行业标准缩写。
- 只改命名与说明，不改算法、数值、顺序、选项名与缓冲协议。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.26

- 可读性整理之二：`shaders/rendering/` 的密集合成与远景片元 main 拆成“能用一句话说清”的业务动作函数（水与反射、云与雾、远景类别与水波），每步带中文说明，读写顺序与数值保持不变。
- 只改可读性，不改算法、数值、顺序、选项名与缓冲协议。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.25

- 可读性整理之一：`shaders/common/` 的坐标、数学与加载器输入文件补全职责、调用位置和可复制示例；重命名不直观的局部变量与参数（投影齐次变量、噪声格、深度选择参数、颜色入参），按业务从上往下读。
- 只改可读性，不改算法、数值、顺序与对外名字（函数名、选项名、缓冲编号均不变）。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。

## 0.0.0-dev.24

- 第二波效果之三：最终显示加入可选边缘自适应上采样 `OMNI_UPSCALE`，按亮度梯度确定边缘方向后用自写多瓣核重采样；默认关闭，关闭时行为不变。
- 说明：本波第 3 项体素全局光与第 4 项光子注入未实现，原因见下；`docs/capabilities.md` 已标注未完成边界。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试；上采样只在内部渲染分辨率低于输出时才明显生效，该分辨率设置未集成与验证。

## 0.0.0-dev.23

- 第二波效果之二：加入光传播体积（LPV）`OMNI_LPV_ENABLED`，计算阶段在八乘八乘八体积格注入方向光并按 `OMNI_LPV_STEPS` 交替传播，间接光阶段三线性采样叠加；关闭时回退现有屏幕空间间接光。
- 体积格通过流程设置的 `image.omniLpvA`、`image.omniLpvB` 登记共享三维图像，计算与片元共用同一图像名。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试。Iris 运行时是否绑定并共享三维图像、体积注入缺少逐方块发光体数据、实际亮度与性能均未验证；默认关闭，关闭时行为与既有屏幕空间间接光一致。

## 0.0.0-dev.22

- 第二波效果之一：加入计算着色器离线基础设施，`build.py` 可生成并编译 Iris 计算入口（`.csh`）与含 SSBO 的着色器（GLSL 430），基础 GLSL 330 compatibility 路径保持不变。
- `programs.json` 新增计算程序登记，`setup.csh` 按维度生成；`pipeline.properties` 增加可选 `COMPUTE_SHADERS` 能力开关；新增计算与 SSBO 的离线回归，编译失败可定位到文件名与行号。
- 计算入口当前只清空光照体积缓冲，LPV 注入与传播、体素全局光、光子注入与 FSR 上采样在后续提交实现。

本版本只运行离线生成、测试、审计与 GLSL 链接检查，未运行 Minecraft、GPU 或性能测试；Iris 是否实际运行计算入口、SSBO 绑定布局与能力开关均未验证。

## 0.0.0-dev.21

- 第一波效果之十七：光照加入可选镜面高光 `OMNI_SPECULAR`，用自写 GGX 法线分布、施利克菲涅耳与 Smith 可见性为直接光增加反射；粗糙度和金属来自材质参数，光照接口改为接收完整材质参数，未复制参考的体素反射与阴影路径。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；镜面强度、方向与实际高光均未验证。

## 0.0.0-dev.20

- 第一波效果之十六：材质加入可选气候覆盖 `OMNI_CLIMATE`，按高度与空间噪声估计温度驱动自然积雪与湿润，寒冷处落雪、温暖处更易积水；手动雪选项保留为额外叠加，未读取真实生物群系数据。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；气候温度分布与积雪边缘均未验证。

## 0.0.0-dev.19

- 第一波效果之十五：水加入可选物理海浪 `OMNI_OCEAN_WAVES`，用自写多层盖斯特纳波在顶点抬升水面，顶点位移与片元法线共用同一高度函数；侧面与瀑布保持原法线，未复制参考的物理模组纹理与均匀量。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；海浪与水面接缝、侧面一致性均未验证。

## 0.0.0-dev.18

- 第一波效果之十四：水加入可选凹凸细节 `OMNI_WATER_BUMP`，在解析波上叠加多层程序噪声并参与法线有限差分；未复制参考的噪声纹理采样路径。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；水面细节与实际法线均未验证。

## 0.0.0-dev.17

- 第一波效果之十三：雾加入可选末地雾 `OMNI_END_FOG`，用紫色漩涡雾叠加虚空暗色替代单纯天空色；关闭时回退原末地环境色，未复制参考的风暴体素光流程。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；末地雾浓度与虚空过渡均未验证。

## 0.0.0-dev.16

- 第一波效果之十二：氛围加入可选解析大气散射 `OMNI_ATMOSPHERE_SCATTER`，用瑞利加米氏单次散射近似天空，不引入外部查找表或未登记依赖；未复制参考的预计算纹理流程。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；散射颜色与实际天空亮度均未验证。

## 0.0.0-dev.15

- 第一波效果之十一：天空加入可选下界氛围色 `OMNI_NETHER_COLOR`，按方向噪声混合荒原、灵魂沙谷、绯红与诡异森林和玄武岩色调；关闭时回退加载器雾色，未复制参考的生物群系均匀量。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；下界氛围色分区与亮度均未验证。

## 0.0.0-dev.14

- 第一波效果之十：抗锯齿加入时序噪声重建选项 `OMNI_TEMPORAL_DENOISE`，用黄金比例逐帧旋转屏幕噪声相位，使时间抗锯齿累积重建地平线遮蔽去噪；关闭或非时间模式保持空间稳定噪声。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；重建去噪的实际收敛与残影均未验证。

## 0.0.0-dev.13

- 第一波效果之九：反射加入可选去噪 `OMNI_REFLECTION_DENOISE`，按命中深度相似度加权旋转多点；关闭时保留原五点模糊，未复制参考的 à-trous 缓冲流程。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；去噪强度与实际噪点抑制均未验证。

## 0.0.0-dev.12

- 第一波效果之八：雾加入可选水下体积光 `OMNI_UNDERWATER_FOG`，在近岸短距离沿视线步进阴影可见性生成蓝色光柱；未引入参考的水下焦散纹理路径。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；水下光柱范围与强度均未验证。

## 0.0.0-dev.11

- 第一波效果之七：云加入平面地平线云层，作为 `OMNI_CLOUD_MODE` 的第四种取值；射线与高度平面相交后用三层分形噪声生成连续云块，未复制参考纹理路径。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；平面云的连续度与地平线过渡均未验证。

## 0.0.0-dev.10

- 第一波效果之六：云加入可选云影 `OMNI_CLOUD_SHADOW`，地表沿光线步进云密度衰减主世界直射光；复用同一云密度来源，未新增缓冲。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；云影范围与强度均未验证。

## 0.0.0-dev.9

- 第一波效果之五：景深加入光圈形状选项 `OMNI_BOKEH_SHAPE`，用程序化多边形边界调制失焦采样，使散景高光成六边形；算法自写，未复制参考偏移表。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；散景形状与实际观感均未验证。

## 0.0.0-dev.8

- 第一波效果之四：镜头加入可选耀斑 `OMNI_LENS_FLARE`，从屏幕太阳亮部生成鬼影与光环，被遮挡或夜晚时自动减弱，不新增附件。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；耀斑形状与实际亮度均未验证。

## 0.0.0-dev.7

- 第一波效果之三：间接照明加入地平线环境遮蔽选项 `OMNI_AO_MODE`，算法一围绕法线切片积分半球可见度；算法零保留原螺旋采样。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；地平线遮蔽的画面与耗时均未验证。

## 0.0.0-dev.6

- 第一波效果之二：加入有序抖动选项 `OMNI_DITHER`，最终显示用四乘四阈值矩阵打散八位量化色带。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；抖动强度与实际色带抑制未验证。

## 0.0.0-dev.5

- 第一波效果之一：加入 AgX 色调映射选项 `OMNI_TONE_MAP`，与既有简单有理映射二选一；宽色域对数编码后用自写 S 曲线压缩高光。

本版本只运行离线生成、测试与审计，未运行 Minecraft、GPU 或性能测试；AgX 的实际画面与耗时均未验证。

## 0.0.0-dev.4

- 代码审查完成后按用户要求提交推送，移除误留的本轮禁止提交限制；后续每个已验证小步骤立即提交推送。
- 修正关闭 TAA 时相机运动模糊的抖动计算，解除景深对历史颜色连续性的错误依赖。
- 修正 Windows 短路径与英文系统输出编码，恢复 CI 在不同运行器上的路径边界和审计回归。
- 修正 Windows 进程 gameDir 的短长路径等价比较，并让性能上下文先于采样工具边界报错。
- 第二轮审查恢复实际world0加载路径并删除根可执行重复入口，修正生成中文说明和配置、进程、文件输出边界。
- 区分加载器properties与版本化JSON分享，完善显式旧版迁移；水侧面保留真实法线，镜头组合保持统一处理顺序。

- 按主助手审查修正最终运动模糊的历史阶段、DH 反射投影、透明几何拒绝与独立水深协议。
- 补齐实体与手持材质解码、稳定切线回退、水波与反射零值路径，并增加真实离线优化回归。
- 收紧中文注释语言检查，采用带原始 MIT 声明的固定版本 Ashima 云噪声，移除重复主世界入口。

- 接入常见几何、阴影、三维度、延迟快照、场景合成、时间合成与最终显示入口。
- 独立实现线性光照、阴影柔化、天空天气、云雾、水折射与反射、实验室材质标准一点三和视差。
- 增加屏幕遮蔽与可见辐射反弹、屏幕反射、快速与时间抗锯齿、曝光调色和可选镜头氛围效果。
- 按 Iris 官方接口实现 Distant Horizons 独立投影、深度重建与基础远景材质路径。
- 完善配置分享、代码注释审计、离线程序链接、依赖白名单、回归与性能采样和交互发布入口。
- 提供中性、真实、氛围、轻量完整预设；工具与材质边界见对应能力表。

本版本为可审查代码实现。本轮只运行离线检查，不运行 Minecraft 或 GPU 视觉测试；世界内画面、性能与兼容性均未验证。高级体素方案仍待实际需求评估，没有预分配体素数据。没有创建发行版或 Git 标签。

## 0.0.0-dev.3

- 收录用户审查并调整的项目规则和 21 步实施计划。
- 明确优先修复基础世界绘制，并约定小步验证、版本管理和依赖复用流程。
- 排除本地 `references/` 参考光影，保留原文件用于研究。
- 发行说明自动读取对应版本的中文更新记录，直接显示本次修改内容。
- 检查更新记录缺失、空白或重复的情况，避免发行说明遗漏。

本版本包含文档与 Git 忽略配置，以及此前未发布的发行说明修复。
光影算法未修改，世界内只有天空的异常仍待修复。

## 0.0.0-dev.2

- 固定 ZIP 平台标记，使 Windows 与 Linux 产物保持一致。
- 记录双平台检查、自动发布与 Iris 实际加载的验证范围。

## 0.0.0-dev.1

- 建立 HOP 目录与中文开发说明。
- 准备项目内开发工具、选项生成、检查、打包和同步。
- 建立 GitHub 自动检查与版本发布流程。
- 保留基础画面输出，增加开发用调试显示。

此版本是开发准备版本。阴影、水面、云等效果尚未实现。
