# 绘制流程

本文件描述移植 iterationT 3.2.0 之后的实际绘制顺序、程序清单与中间画面协议，只讲代码怎么接线，算法本身留在各效果文件里。

事实来源分别是：程序登记看 `shaders/rendering/programs.json`，加载器设置看 `shaders/rendering/pipeline.properties`，中间画面的编号、格式与清除看 `shaders/rendering/buffers.glsl` 与三个维度的 `buffers_main.glsl`、`buffers_nether.glsl`、`buffers_end.glsl`。移植合同、分片状态和逐条偏离记录见 `docs/parity.md`。

证据边界：当前只有离线编译（`python build.py compile`）与源码审计（`python build.py audit`）证据，Minecraft 世界内画面、性能与兼容性都未验证。离线通过不等于画面正确。

## 入口生成

- `programs.json` 登记 45 个程序，外加 1 个计算程序 `setup`（光传播体积，对应主体 `rendering/lpv.glsl`）。
- `build.py` 按维度生成入口文件，实测 253 个，分别落在 `world0/`、`world-1/`、`world1/`。
- Iris 只要存在任一 `worldN` 目录就从维度目录加载，所以三个维度都要生成入口；仓库根目录只放共用代码，不放可执行入口。
- 每个入口先声明 GLSL 330 compatibility、阶段宏与维度宏，再引入本维度的缓冲声明文件，最后引入对应绘制主体。顺序是：阶段宏（`OMNI_VERTEX`、`OMNI_GEOMETRY`、`OMNI_FRAGMENT`、`OMNI_COMPUTE`）与维度宏（`OMNI_OVERWORLD`、`OMNI_NETHER`、`OMNI_END`）→ `rendering/buffers_main.glsl`（或 `buffers_nether.glsl`、`buffers_end.glsl`）→ `rendering/` 下按阶段分组的对应主体文件（例如 `rendering/composite.glsl`）。
- 缓冲声明必须由入口引入才会生效：加载器只读取每个程序展开之后的片元源码里的 `const`，写在别处或写进不参与编译的文件都不会被看到。这正是它拆成共享层加逐维度层的原因。
- 几何阶段入口只在登记了几何着色器的程序上生成：主世界是 `gbuffers_terrain` 与 `gbuffers_skytextured`，下界和末地只有 `gbuffers_terrain`。
- 可选加载器特性在 `pipeline.properties` 用 `iris.features.optional` 声明：`ENTITY_TRANSLUCENT`、`COMPUTE_SHADERS`、`CUSTOM_IMAGES` 与 `FADE_VARIABLE`（`rendering/pipeline.properties:406`）。原版区块淡入依赖 `FADE_VARIABLE` 与属性 `mc_chunkFade`，缺这项能力时地形与水面的淡入整套不参与编译（`rendering/terrain.glsl:134`、`rendering/translucent.glsl:117`），基础画面不受影响。

`rendering/` 的绘制主体按绘制阶段分组，不按效果分组：地形、实体、半透明、覆盖层、天体、远景、阴影、光照顶点、延迟、合成、后期、最终，再加计算主体 `lpv`。同一个主体里的多个程序靠程序宏区分，例如 `composite` 与 `composite1`–`composite5` 都在 `rendering/composite.glsl`。

## 中间画面协议

每张中间画面的编号、格式、每帧是否清除、清除色都在 `rendering/buffers.glsl` 一层里定义。下表取主世界取值，七号与八号的格式在下界和末地不同，见「三个维度的差异」。九号画面是 Omni 为 Eclipse 程序化草新增的额外缓冲（iterationT 只用零到八号），只有主世界会写和读。

| 编号 | 格式 | 每帧清除 | 用途 |
| --- | --- | --- | --- |
| 0 | `RGBA8` | 是，清成 (0,0,0,1) | 贴图色（伽马空间）、天体颜色、雨遮罩 |
| 1 | `RGBA16` | 否 | 全局光与遮蔽 → 场景曲线编码颜色 → 色调映射后的颜色 |
| 2 | `RGBA16` | 否 | 全局光历史、上半屏天空盒图、右上角云影贴图、顶行统计像素 |
| 3 | `RGBA16` | 是 | 不透明法线光照图 → 反射数据 → 镜头光斑 |
| 4 | `RGBA16` | 是 | 半透明法线光照图；延迟阶段被 128 立方云噪声替换采样 |
| 5 | `RGBA16` | 是 | 不透明高光材质 → 泛光 |
| 6 | `RGBA16` | 是 | 半透明颜色材质与水遮罩；延迟阶段被 32 立方云噪声替换采样 |
| 7 | `RGBA16` | 否 | 焦散法线方块 → 时间抗锯齿历史 |
| 8 | `RGBA8`（尺寸 2.0） | — | 放大输出（`FSR`）；延迟与合成阶段被预计算大气三维贴图替换采样 |
| 9 | `RGBA8` | 否 | 方块编号与生物群系（程序化草用的体素编号通路，Omni 额外）；地形片元写入方块编号与生物群系，几何阶段按世界坐标投影回来查隔壁方块。与 `docs/parity.md` 第十二节偏离记录第 38 条一致 |

零号、三号到六号每帧清除，一、二、七、九号不清除以跨帧接力。九号画面要读上一帧内容，所以不清除。四号、六号在延迟阶段、八号在延迟与合成阶段会被三维贴图替换采样，采样器类型由引入的程序自己打开宏来选。

颜色编码：所有中间颜色按 `LinearToCurve(x / MAIN_OUTPUT_FACTOR)` 存进十六位固定点画面，`MAIN_OUTPUT_FACTOR = 2048`，曲线是四次方根，这样暗部才保得住精度。曝光在最终阶段乘回：自动曝光是 `8.5 × MAIN_OUTPUT_FACTOR × 平均亮度^(-AE_CURVE) × 2^AE_OFFSET`。

二号画面顶行的 `a` 通道每隔二十像素存一个统计量：横坐标 0 是自动曝光，20 是标题计数，40 是全局云影，60 是景深对焦深度。这些像素不参与普通画面处理。

## 三个维度的差异

程序差异（`programs.json` 的 `absent` 段）。下界与末地共用主世界同名程序的内容，只在下面的程序上做裁剪：

| 维度 | 不生成的程序 |
| --- | --- |
| 主世界 `world0` | 无，登记的全部程序 |
| 下界 `world-1` | `dh_shadow`、`composite1`、`deferred1`–`deferred6` |
| 末地 `world1` | `composite1`、`deferred3`、`deferred5`、`deferred6` |

逐维度常量差异。三维度取值相同的画面格式、清除、清除色和阴影常量集中在 `buffers.glsl`；只在某个维度不同的六项放在各维度自己的声明文件里：

| 维度 | 七号格式 | 八号格式 | 阴影绘制距离倍率 | 一号阴影硬件比较 | 零号阴影多级纹理 | 原版遮蔽强度 |
| --- | --- | --- | --- | --- | --- | --- |
| 主世界 | `RGBA16` | `RGBA8` | 1.0 | 是 | 是 | 1.0 |
| 下界 | `RGBA32F` | `RGB16` | 0.007 | 否 | 否 | 0.0 |
| 末地 | `RGBA16` | `RGB16` | 1.0 | 是 | 是 | 0.0 |

下界七号用三十二位浮点，是因为下界时间抗锯齿把参考深度与当前深度一起打包进了七号的透明度通道，位数不够会丢精度。

## 主世界阶段顺序

Iris 的执行顺序是：阴影 → 不透明几何 → deferred 0–6 → 半透明几何 → composite 0–16 → final。主世界各阶段的分组与写出缓冲如下，逐程序明细见 `docs/parity.md` 第三节。

```text
阴影       shadow                          → 阴影深度、shadowcolor0/1
不透明几何 gbuffers_*                       → 0、3、5（天空与天气只写 0）
延迟       deferred0–deferred6              → 1、2、4、6、7
半透明几何 gbuffers_water / hand_water / dh_water → 0、4、6
合成       composite0–composite5            → 1、3
后期       composite6–composite16           → 1、2、5、7、8
最终       final                            → 屏幕
```

- 几何阶段：地形、实体、方块实体、手写零号、三号、五号；天空基础与天空贴图把日月和天空盒叠进零号；覆盖层里基础、线条、贴图、信标光束写零号、三号、五号，方块破坏、附魔光、天气只写零号。
- 延迟阶段：零号写水面波法线供焦散采样，一、二号写全局光与地平线遮蔽，三号写天空、云与星星，四、五号做云影模糊，六号把不透明法线光照图与材质编号复制给半透明层。
- 合成阶段：零号做不透明表面光照；随后依次做水下与水后雾、屏幕空间反射、两遍反射小波滤波、折射与体积雾、雨与镜头光斑。
- 后期阶段：景深、时间抗锯齿历史、运动模糊、泛光链、曝光与调色、锐化与放大。
- 最终阶段：写屏幕，做锐化、手与玩家边缘抗锯齿、抖动与黑边。
