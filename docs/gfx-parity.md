# gfx 覆盖对照：iterationT、Eclipse 与 omni-gfx

这份文件回答：参考光影里的效果，在 `omni-gfx` 里由哪个模块承接，哪些只服务 Minecraft。
调用位置：审查覆盖范围、判断某个效果是否已迁入通用库时先读本文件。
状态口径：
- **已覆盖**：库里有对应实现，光影包通过生成的 GLSL 调用。
- **库内**：实现存在，但参考包没有实际调用，或只作为辅助函数。
- **MC 专用**：依赖 Minecraft 的缓冲、选项、实体或阶段语义，不放进通用库。

## 结论

- `omni-gfx/src` 现有 48 个源模块：44 个生成 GLSL，4 个参考后端只保留源码供严格对照。
- `shaders/gfx/` 的 22 个旧转发文件已在 2026-10-27 删除；效果文件直接引用 `shaders/omni-gfx/`，算式只在 `omni-gfx/src` 一份。
- 模块级覆盖已完成；函数级逐条明细见 `docs/gfx-functions.md`（2026-10-26 由 `python omni-gfx/build.py parity` 从源码重建，505 个参考函数：已迁入 404、MC 专用 101、缺失 0、调试输出 0）。
- 严格对照另见 `docs/gfx-functions-strict.md` 与 `omni-gfx/tools/parity_report.json`：exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0。旧的“已迁入”只代表有承接函数，严格结论以这份新表为准。
- 第五批把函数级缺口清零：20 个函数新进库（拜尔 16/32/128、月亮与天空盒双线性取像素、天空经纬投影与云图两级采样、双边升采样、Xonk 曲线、十六位分量解码、整数哈希、球面求交哨兵版、三次 B 样条权重八件），15 个按算法逐项对照到库内已有实现，1 个（`GetCloudShadow`）按宿主符号留在光影侧；采样器一律改为显式参数，不再以“库不绑定采样器”为由排除。
- 没有启动 Minecraft，游戏内画面、性能与维度切换仍未验证。

## 模块对照

| Slang 模块 | 主要承接的参考内容 | 状态 |
| --- | --- | --- |
| `math` | 曲线、编码、法线、矩阵、快速三角函数、公共工具 | 已覆盖 |
| `color` | AgX、ACES、色调映射、HSV、白平衡、曝光 | 已覆盖 |
| `sampling` | 蓝噪声、Bayer、纹理过滤、抖动 | 已覆盖 |
| `noise` | 时间噪声、程序化噪声、FBM | 已覆盖 |
| `atmosphere` | 天空散射、太阳/月亮圆盘、星场、极光、彩虹 | 已覆盖 |
| `atmosphere_model` | 预计算大气、透射率、散射查表、辐照度 | 已覆盖 |
| `cloud` | 平面云、云影、云形状与光照 | 已覆盖 |
| `cloud_volume` | 体积云步进、云影贴图、NUBIS 主循环 | 已覆盖 |
| `fog` | 高度雾、团雾、下界雾、末地雾、空气透视 | 已覆盖 |
| `fog_volume` | 体积雾步进、水下体积雾、下界体积雾 | 已覆盖 |
| `water` | 波浪、法线、视差、折射、焦散、水面动画、海洋波 | 已覆盖 |
| `shadow` | 阴影投影、半影、屏幕阴影、彩色阴影 | 已覆盖 |
| `gi` | RSM、GTAO、时间滤波、空间滤波、多弹射 | 已覆盖 |
| `reflection` | 屏幕空间追踪、反射合成、降噪、天空回退 | 已覆盖 |
| `post` | 泛光链、景深、动态模糊、眩光、曝光、调色 | 已覆盖 |
| `antialias` | TAA、YCoCg、历史裁剪、重投影 | 已覆盖 |
| `surface` | 方块光、材质法线、遮蔽、自发光 | 已覆盖 |
| `parallax` | 视差遮挡、高度采样、法线 | 已覆盖 |
| `voxel` | 体素反射、体素索引 | 已覆盖 |
| `upscale` | FSR EASU、CAS、锐化、降噪 | 已覆盖 |
| `planet` | 末地行星、环带、行星阴影 | 已覆盖 |
| `accretion` | 吸积盘积分、星场 | 已覆盖 |
| `weather` | 雨雪风向、季节、每日天气 | 已覆盖 |
| `lpv` | 光传播体积、颜色注入、雾照明 | 已覆盖 |

## 只服务 Minecraft 的部分

下面这些不属于通用库，保留在 `bind/`、`rendering/` 或效果层：

- 519 个选项、九页菜单、预设与配置迁移；
- G 缓冲读取、材质编号与掩码；
- 手持光源、手部阴影、手电筒位置与屏幕空间阴影；
- 生物群系表、维度切换与天气状态；
- 体素写入与 Iris 自定义图像布局；
- 调试数字、调试文字与屏幕叠加；
- 实体、方块实体、粒子与物品的渲染阶段；
- 阴影贴图比较采样器的程序级声明；
- 远景模组的投影与缓冲约定；
- 下界/末地的群系配色数据表；
- 半透明排序与水面阶段选择；
- Minecraft 的坐标、单位与深度约定；
- 资源包路径、方块/实体/物品属性表；
- 光影包版本与加载器能力检测；
- 游戏内菜单与语言文件。

## 验证

- `python omni-gfx/build.py check` 通过；
- 44 个生成模块将 GLSL 写到唯一位置；SPIR-V 探针按 `python omni-gfx/build.py spirv` 单独运行；
- `python build.py audit` 通过；
- `python build.py verify` 通过 166 个测试、9 组编译探针与打包；
- `python build.py compile` 通过 280 组唯一程序，0 错误。

未验证：Minecraft 世界内画面、菜单、性能、Vulkan/Aperture 运行时、其他显卡。

## 待补

- 函数级缺口已清零（`docs/gfx-functions.md`：缺失 0、调试输出 0）。通用库承接 329 条、MC 专用 176 条；宿主依赖逐条列出符号，调试叠加逐条写明机制（`gl_FragCoord`、`text.`、`printChar` 链）。
- 剩余未验证项只有实机：Minecraft 世界内画面、菜单、性能、Vulkan/Aperture 运行时与其他显卡；测试世界只能证明产物能编译、能出图、能在本机达到目标帧率。

## 严格对照与两个 profile

旧的函数级表只回答“由谁承接”，不能证明常数、采样顺序和颜色空间一致。2026-10-26 新增：

- `omni-gfx/tools/strict_review.json`：人工严格台账，逐条写 exact、approximate、mc_glue 或 missing；只有逐行核对过的映射才进 exact。
- `python omni-gfx/build.py strict-parity`：生成 `omni-gfx/tools/parity_report.json`（ASCII 字段名）与 `docs/gfx-functions-strict.md`。报告里的 exact 覆盖率按算法函数计算，不把菜单、坐标约定与调试叠加算进分母。
- `python omni-gfx/build.py profiles`：生成 `omni-gfx/profiles/iterationt/profile.frag` 与 `omni-gfx/profiles/eclipse/profile.frag`，再用本机 `glslang` 分别编译。两个 profile 各自调用本包的代表性函数，不共享一个“混用”版本。
- 当前严格统计以 `parity_report.json` 为准；未达到 exact 的条目逐条列在 `docs/gfx-functions-strict.md`，不能当成已完成。尤其是 Eclipse 的 Photonics、WSR 反射与体积云主循环，仍需要继续迁移。
