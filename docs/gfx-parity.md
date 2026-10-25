# gfx 覆盖对照：iterationT、Eclipse 与 omni-gfx

这份文件回答：参考光影里的效果，在 `omni-gfx` 里由哪个模块承接，哪些只服务 Minecraft。
调用位置：审查覆盖范围、判断某个效果是否已迁入通用库时先读本文件。
状态口径：
- **已覆盖**：库里有对应实现，光影包通过生成的 GLSL 调用。
- **库内**：实现存在，但参考包没有实际调用，或只作为辅助函数。
- **MC 专用**：依赖 Minecraft 的缓冲、选项、实体或阶段语义，不放进通用库。

## 结论

- `omni-gfx/src` 现有 24 个 Slang 模块。
- `shaders/gfx/` 的 22 个旧 GLSL 文件已变成转发层，循环 0、纹理采样 0。
- 模块级覆盖已完成；函数级逐条明细见 `docs/gfx-functions.md`（2026-10-25 由 `python omni-gfx/build.py parity` 从源码重建，505 个参考函数：已迁入 294、MC 专用 154、缺失 36、调试输出 21）。
- 本轮把 11 个纯计算函数补进库：`ogxHalton2`、`ogxHalton3`、`ogxRayBoxRange`、`ogxRayBoxIntersection`、`ogxSquare`、`ogxLengthSquared`、`ogxSafeInvLength`、`ogxTriangleWave`、`ogxFma2`、`ogxSinCos`、`ogxRotate2`。
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
- 24 个模块生成 GLSL，SPIR-V 24/24；
- `python build.py audit` 通过；
- `python build.py verify` 通过 147 个测试、9 组编译探针；
- `python build.py compile` 通过 280 组唯一程序，0 错误。

未验证：Minecraft 世界内画面、菜单、性能、Vulkan/Aperture 运行时、其他显卡。

## 待补

- 函数级明细由 `python omni-gfx/build.py parity` 生成到 `docs/gfx-functions.md`；还剩 36 个缺失项，主要是天空贴图采样（库按约定不绑定采样器）、镜头光斑辅助、量化抖动与 16/32/128 拜尔矩阵。
- 游戏内验证必须由玩家启动 Minecraft 后完成。
