# omni-gfx 验证记录

## 〇、2026-10-26 光影验收 v5：按 iterationT 3.2.0 对齐

设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。本轮没有启动 Minecraft。

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py check` | 生成文件与源一致；24 个模块；测试世界与光影验证场景各 2 个入口的 GLSL 编译与中文说明审计通过 |
| `python build.py audit` | 中文注释与实现审计通过（110 个代码文件） |
| `python build.py verify` | 148 个测试全部通过；9 组唯一编译探针通过；打包完成 |
| `python build.py compile` | 全部程序 × 两种代表配置 × 基础与开远景环境，280 组唯一程序，0 错误 |
| `omni-gfx/examples/lighting/render.py --frames 10 --warmup 60` | 1280×720，平均 16.86 毫秒、中位 16.74、95 分位 17.67、最小 16.36、最大 17.67，约 59.3 帧每秒 |

截图：`.dev/omni-gfx/world-iterationt.png`；并排：`.dev/omni-gfx/world-iterationt-comparison.png`；帧时：`.dev/omni-gfx/world-iterationt.json`。这三个文件只在本机 `.dev/`，按项目规则不提交。

### 这一轮对齐了什么

| 项目 | 参考位置 | 本场景实现 |
| --- | --- | --- |
| 大气与太阳 | `Lib/BasicFounctions/PrecomputedAtmosphere.glsl`、`Lib/Programs/CompositeVS.glsl` | 直接加载参考包的 `AtmoData_620_540_440_n4.bin`（512×128×33 RGBA32F）；太阳辐照度、天空辐照度与太阳透过率在 CPU 每帧查一次，片元阶段读 uniform；天空背景仍逐像素查同一张表 |
| 曝光与色调映射 | `Lib/Programs/Final.glsl`、`Lib/Settings.glsl` | AgX、`AGX_EV 13`、乘 2.3、Abney 校正、伽马 2.2；自动曝光 `AE_CURVE 0.7`、参考亮度 0.18；暗角 0.4、强度零 |
| 阴影 | `Lib/BasicFounctions/Sunlight_Shadow.glsl` | 九点遮挡搜索、十六点螺旋过滤、半影一到两个纹素；法线与深度偏置按级联缩放；远景退化成五点百分比过滤 |
| 环境光遮蔽 | `Lib/IndividualFounctions/GTAO.glsl` | `ogxGroundTruthAo`：三切片、每片三步、世界半径 2 米、强度 0.95、多重反弹 |
| 体积云 | `Lib/IndividualFounctions/NUBIS.glsl` | 参考包 128 立方基础噪声与 32 立方细节噪声；云底 500 米、云顶 1000 米、覆盖 0.28、密度 1.0、底部亮度 0.15、外散射 1.3、直射 36 倍、五次光照步进、二十步最多 |
| 体积雾 | `Lib/IndividualFounctions/VolumetricFog.glsl` | 密度 0.01、衰减 40、六步 `pow(11,u)`、四次太阳方向密度取样、双瓣相位、四阶多次散射、粉末效应、天光 0.32、太阳 0.7 |
| 水面 | `composite1.fsh` 的水体函数、`Lib/IndividualFounctions/Reflections/SSR.glsl` | 吸收色 (0.2,0.5,0.7)、吸收指数 0.21、可见度 0.29、水体雾色、Schlick 菲涅尔与可见性项；反射用镜像相机平面反射代替屏幕空间追踪 |
| 时间抗锯齿 | `Lib/Settings.glsl`、`Lib/BasicFounctions/TAA.glsl` | 历史权重 0.97，本帧权重 0.03；八相位次像素抖动 |

### 大气表的读取修正

参考纹理文件是 512×128×33 的 RGBA32F（34,603,008 字节），末尾另有 163,840 字节数据。上一版误把开头 163,840 字节当成文件头跳过，导致整张表下移二十行：天空偏白、天空辐照度接近零。现在上传前 34,603,008 字节，CPU 查表使用同一段数据。

GPU 探针在 1×1 目标里调用 `ogxAtmoSunSkyIrradiance`，与 CPU 侧 `AtmosphereTable.sun_and_sky` 的结果逐位比较：

```text
GPU 太阳 (1.6685, 1.3350, 0.9813)  天空辐照度长度 0.1981
CPU 太阳 (1.6685, 1.3350, 0.9813)  天空辐照度长度 0.1981
```

### 画面检查

- 暗部层次：树冠背光面、拱门侧面、三个球的暗面保留蓝灰天光与草地反弹，没有压成纯黑。
- 阴影软硬：拱门在右坡上的投影有清楚的接触端和一到两个纹素的半影；树冠自阴影边缘比旧版锐，近景不再是一团灰。
- 云底与云顶：云顶白、云底蓝灰，云块边缘有花椰菜状鼓包；近距离云没有可见的整步横向条纹。
- 水面反射：远岸与天空在湖面形成连续倒影，近处深水收敛到暗青；晴天泡沫与水面地形阴影造成的白色斑点已去掉。
- 雾的远近：近景草地与湖岸清楚，远岸树线与山脊带一层很薄的蓝灰空气透视；没有铺满全屏的白纱。

### 仍未验证

- Minecraft 游戏内画面、性能与兼容性；离线编译和测试世界不能代替世界内效果。
- 其他显卡与驱动；本轮帧时只代表这台 Intel Arc 和这个固定机位。
- 水面是四分之一分辨率镜像相机平面反射，不是参考包的屏幕空间追踪；两者在出屏倒影和水下遮挡上会有差异。
- 彩色反弹是屏幕空间的邻域反照率近似，不是参考包的 RSM 光线步进；暗部颜色方向一致，但多次反弹强度不能逐像素相等。
- 没有天气、月亮、星空和维度切换；本场景只验证主世界晴天。
- 共享模块 `cloud_volume` 的密度组合、竖直包络与云光照已按 NUBIS 改写；Minecraft 内的云形、云量与云底亮度会随之变化，本轮没有游戏内画面验证。

## 一、2026-10-24 阶段三收尾（0.4.1）

设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。本轮没有启动 Minecraft。

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py generate` | 13 个模块，27 个文件；生成 GLSL 共 7442 行 |
| `python omni-gfx/build.py check` | 生成文件与源一致；库内 27 个文件通过中文说明审计 |
| `python build.py audit` | 光影与库的代码文件全部通过中文说明与实现审计 |
| `python build.py verify` | 测试、关键光影检查、编译探针与打包通过 |
| `python build.py compile` | 全部程序 × 两种代表配置 × 基础与开远景环境，280 组唯一程序，0 错误 |
| `python omni-gfx/build.py count` | 手写核心 4870 行（上限 5200），生成 GLSL 6970 行，第三方 0 行 |
| `omni-gfx/examples/world/render.py --frames 120 --warmup 20` | 1280×720，平均 11.86 毫秒，中位 11.85，95 分位 13.29，最小 9.82，最大 14.51，约 84 帧每秒 |

截图：`.dev/omni-gfx/world-complete.png`（本机文件，按项目规则不提交）。帧时记录：`.dev/omni-gfx/perf-complete.json`。
上一版对照：平均 28.96 毫秒、约 34.5 帧每秒；本轮把反射与遮蔽降到半分辨率，并让地形只画到水面以上，帧时降到约三分之一。

### 本轮验证到的内容

- 五个新模块与四个扩展模块都进入生成产物，并被真实程序引用：`shaders/gfx/` 下九个适配层各有一行 `/omni-gfx/<模块>.glsl` 引用，`shaders/omni-gfx/` 与 `omni-gfx/generated/glsl/` 逐字节一致。
- 280 组光影程序离线编译通过，说明 Slang 降级后的 GLSL 330 在真实入口（含选项宏、两种配置与开远景环境）里能编译链接。
- 测试世界的新阶段都实际出图：三级级联 PCSS、半分辨率遮蔽与多弹射、半分辨率反射与九点降噪、时间抗锯齿、两级泛光。
- 画面检查：默认机位截图里没有黑边、没有重复条纹、没有成片过曝；水面有岛与岸线的倒影，地形投影是软边，云边没有方块状放大。

### 仍未验证

- Minecraft 游戏内画面、性能与兼容性；离线编译不能代替世界内效果。
- Vulkan / Aperture 运行时；本轮没有重新跑 SPIR-V 探针。
- 其他显卡与驱动；帧时只代表这台 Intel Arc 与这一个机位。
- `ogxScreenSpaceTrace` 在测试世界没有被调用：测试世界的反射用世界空间步进，纯屏幕空间步进仍在 Minecraft 的反射路径里，未在独立场景中单独验证。
- 抗锯齿的移动画面表现：截图模式机位固定，重投影位移为零，移动时的残影与鬼影没有逐帧检查。

## 二、2026-10-24 阶段三画面与性能（0.4.0）

设备与上一轮相同。

日期：2026-10-24。设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。

这份记录区分“已经跑过并看到结果”和“只做了离线检查”。没有启动 Minecraft。

## 一、命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py generate` | 8 个模块，17 个文件；GLSL 共 2786 行（含镜像副本） |
| `python omni-gfx/build.py check` | 生成文件与源一致；库内 22 个文件通过中文说明审计 |
| `python build.py audit` | 光影代码文件全部通过中文说明与实现审计 |
| `python build.py verify` | 测试全部通过；关键光影检查与编译探针通过 |
| `python build.py compile` | 全部程序 × 两种代表配置 × 基础与开远景环境，0 错误 |
| `.venv\Scripts\python.exe omni-gfx\examples\world\render.py --frames 120 --warmup 30` | 1280×720，平均 28.96 毫秒，中位 29.09，95 分位 40.65，最小 20.60，最大 44.13，约 34.5 帧每秒 |

截图：`.dev/omni-gfx/world-final.png`（本机文件，按项目规则不提交）。
帧时记录：`.dev/omni-gfx/perf-final.json`。
上一版对照：平均 73.76 毫秒、约 13.6 帧每秒（机位与光照不同，只说明量级变化）。

帧时的离散度来自本机同时运行的其他程序（聊天软件与浏览器常驻），同一份代码连续运行的中位数在 27 到 45 毫秒之间波动；表中记录的是最后一次完整 120 帧结果。快速帧约 21 到 22 毫秒，说明画面本身的成本低于表中平均值。

## 二、GPU 等值测试覆盖

旧 `shaders/gfx/` 与新生成库在同一个片段着色器、同一驱动、同一浮点精度下逐通道比较，26 个用例全部逐位一致（最大绝对差 0）。本轮没有改动这部分代码，测试仍通过。

## 三、测试世界的画面管线

每帧按固定顺序绘制，全部离屏目标与步数都是常量，方便比较帧时：

```text
方向光阴影贴图 2048²（只写深度）
        ↓
天空立方体贴图 160²（大气四段 + 云八步） ─→ 水面反射兜底、地形环境光
        ↓
半分辨率天空与云 640×360（大气六段 + 云十二步，蓝噪声抖动）
        ↓
时间累积（重投影 + 三乘三邻域夹紧，本帧权重 0.10）
        ↓
全分辨率合成（双边升采样 + 太阳圆盘）→ 场景目标
        ↓
地形（阴影贴图、云影、天空环境光、空气透视、低空雾）
        ↓ 颜色与深度复制
水面（屏幕空间地形反射、菲涅尔、GGX 高光、折射、吸收、岸线泡沫、空气透视与雾）
        ↓
两级对数亮度统计 → 自动曝光、暗角、ACES、抖动 → PNG
```

场景内容：

- 96×96 体素地形，29556 个三角形；方向光阴影贴图覆盖全岛，三乘三深度比较，云影与天空环境光保留。
- 水面是一直铺到八十公里的等比圆盘，25344 个三角形；屏幕空间反射十八步、命中后三次二分；反射失败退回天空立方体贴图。
- 天空是单次散射大气加两层噪声形状的程序化体积云；云层一百六十米到六百二十米。
- 固定机位：位置 `(48, 17, 140)`，看向 `(48, 16, 40)`，太阳方向 `(0.58, 0.42, 0.32)`，场景时间 12 秒，ACES 曲线。

## 四、这一版修掉的画面问题

| 问题 | 处理 | 结果 |
| --- | --- | --- |
| 地平线黑色横带 | 水面圆盘从 2.4 公里扩到 80 公里，远平面 120 公里；地平线以下的天空改用海面方向的空气色兜底 | 横带消失，天与海之间是连续雾带 |
| 右侧大片过曝 | 云单独用更低的太阳强度，云亮度按云量与相位校准；后期加两级对数亮度自动曝光 | 画面最亮处仍有层次，没有成片死白 |
| 云层重复条纹与软块 | 抖动从交错梯度噪声换成蓝噪声，加时间累积与双边升采样；形状加到四层、坐标旋转三十度、云底收口变硬 | 条纹消失，云边细碎，云底是平的 |
| 地形没有明确投影 | 方向光阴影贴图替换高度图步进，偏置按掠射角放大 | 方块之间与山脊有可见影子 |
| 水面缺少地形反射 | 屏幕空间反射 + 三次二分收紧交点 | 岛与岸线在水里有倒影 |
| 天空与水面接缝 | 两边共用同一份大气常数与空气透视，水面远处收敛到同一种雾色 | 接缝只剩一条很淡的过渡 |

## 五、尚未验证

- Minecraft 游戏内画面：只验证了生成的 GLSL 能被 Iris 程序编译，没有启动游戏看效果。
- 阶段三效果在 Minecraft 里的实际替换：云、水、雾仍只在测试世界消费。
- Vulkan/Aperture 运行时：SPIR-V 只是模块探针，没有实际创建 Vulkan 管线。
- 其他显卡与驱动：只有本机 Intel Arc 的数据；帧时波动受本机其他程序影响。
- 长时间稳定性、显存变化、不同分辨率下的帧时：本轮未测。
- 云、水、雾的物理正确性：仍是风格化近似，大气只有单次散射，云只有单层，反射是屏幕空间近似。

## 六、第二批迁移的验证（2026-10-25）

- 生成：python omni-gfx/build.py generate 输出 23 个模块、47 个文件，GLSL 共 12754 行；shaders/omni-gfx/ 与 generated/glsl/ 逐字节一致。
- 库检查：python omni-gfx/build.py check 通过；src/*.slang 的中文说明比例在 26% 到 81% 之间，新迁模块均超过 50%，math、color 等早期核心模块仍低于 50%，按现有审计口径只对 GLSL 与薄入口强制。
- 光影检查：python build.py verify 145 个测试通过，9 组编译探针通过，8.4 到 8.9 秒；全量编译 python build.py compile 280 组唯一程序通过。
- SPIR-V：python omni-gfx/build.py spirv 22 个模块通过，voxel 因整数三维纹理 usampler3D 暂无探针，命令会列出并跳过；这不是 GLSL 路径的失败。
- 适配层约束：测试改为扫描 shaders/gfx/*.glsl 全部文件，要求每个都引用同名生成模块；纯宿主布局（五级泛光子图、反射主流程的天空与体素钩子）留在适配层。
- GPU 对照：omni-gfx/tests/equivalence.py 在本机 Intel Arc 上 26/26、最大差 0。第二次迁移后它比较的是“适配层入口”和“生成库函数”，证明转发接对了，但不再证明与迁移前的旧算式一致；迁移前的同项记录是本文件上一节的 26/26。
- 数值一致性：新迁模块按旧文件逐行搬运，常数、分支与运算顺序不变；矩阵方向用显式点乘固定，避免两种语言行列顺序不同。没有逐模块的 GPU 截图对比，这一项仍未验证。
- 循环分类：shaders/rendering/ 的十二个循环已逐个归类；这一轮之前的记录只有大气光学厚度迁进库，其余十一处按几何装配、材质采样或宿主选项留在阶段层。

未验证项与上一节相同：没有启动 Minecraft，没有看游戏内画面、Vulkan 运行时与其他显卡。Voxel 的 SPIR-V 探针与水面迭代波的参数化已在下一节处理。

## 七、第三批补齐（2026-10-25）

- SPIR-V：补上体素模块探针，`python omni-gfx/build.py spirv` 23 个模块全部通过，编译器 2026.20，输出里不再有跳过项。构建脚本同时改成缺一个探针就失败，测试新增“每个模块都要有探针”，缺口不会再被当成通过。
- 三维取格写法：Slang 把细节层级放在坐标的第四个分量，体素源改成 `Load(int4(cell, 0))`，生成器新增 `int4` 取格的等价转换。生成的 `texelFetch` 与改动前完全一致，`voxel.glsl` 只多了两行说明；无符号三维纹理靠探针里的一行类型别名接上，算式与常数没有改动。
- 适配层算式：`shaders/gfx/*.glsl` 现在已经没有 `texture()`、`textureLod()` 与 `texelFetch()` 的本地调用。泛光链第二级那两处重复的“夹紧后读零号层级”改成 `ogxBloomChainCopy`，库和适配层各只一份。
- 循环：`shaders/rendering/` 的十二个循环逐个看过，平面云的云内遮挡与水面迭代正弦搬进库（新增 `ogxPlanarCloudLightingDepth`、`ogxOceanWaveSum`、`ogxOceanWaveHeight`），还剩八个是几何装配、图集采样或维度专用，依据逐项写进 `docs/rendering.md`。
- 对照表：新增 `docs/gfx-parity.md`，76 行覆盖 iterationT 31 个算法文件与 Eclipse 45 个文件，按已覆盖、部分、库内、未覆盖、MC 专用五种状态记录，并列出库里暂时没有调用方的函数。
- 命令结果：`generate` 输出 23 个模块、47 个文件、GLSL 12988 行；`check` 通过，库内 37 个文件通过中文说明审计；`verify` 146 个测试通过、9 组编译探针通过；`compile` 280 组唯一程序 0 错误。
- 本轮仍没有启动 Minecraft：水面迭代正弦、平面云遮挡与泛光链拷贝只证明能编译、算式与常数逐行对应，游戏内画面与帧时未验证。

## 八、对照表补缺（2026-10-25）

- 新增 `lpv` 模块：Eclipse `lpv_render.glsl` 的取样解码、写入编码、亮度曲线、边缘淡出与合成搬进库；`shaders/rendering/lighting/lpv.glsl` 只留纹理选择、越界判断与帧奇偶。默认配置关闭光传播体积，因此默认画面不变；全高配置编到真实分支，证明库函数在 GLSL 430 计算程序里也能通过。
- `sampling` 新增平滑过滤、阴影平滑过滤、最近点取样、旋转网格超采样与两套抗锯齿抖动序列；生成器为此新增 `tex.SampleGrad` 到 `textureGrad` 的等价转换，屏幕导数仍由调用方传入，库保持纯函数。
- `color` 补五条色调映射曲线、经济版电影曲线与标准 sRGB 编码；`noise` 补白噪声与三角噪声；`post` 补浮点与定点抖动、多边形光圈；`math` 补不夹紧映射、三分量极值、圆盘点列、螺旋采样与粗糙高光方向；`cloud` 补降雨密度。这些函数按参考实现逐行搬运，有意偏离记在 `docs/gfx-parity.md` 的「有意偏离」小节。
- 对照表：`docs/gfx-parity.md` 整篇重写，76 行逐项核对；未覆盖从 4 条降到 0 条，`PrintFloat` 与 `text_rendering` 按参考包里的实际调用位置改判为 MC 专用（调试叠加），剩余 15 条部分覆盖逐条写出宿主数据源。
- 回归：新增 `test_minecraft_lpv_uses_generated_module`，要求光影侧继续引用生成库的 `lpv` 模块并调用解码、编码与合成三个函数。
- 命令结果：`generate` 输出 24 个模块、49 个文件、GLSL 13744 行；`check` 通过，库内 38 个文件通过中文说明审计；`spirv` 24/24 通过（编译器 2026.20）；`verify` 147 个测试、9 组编译探针通过，本机冷缓存耗时 7.16 秒；`compile` 280 组唯一程序 0 错误。
- 手写核心 8153 行，上限按决策记录调到 8400 行。
- 未验证：没有启动 Minecraft，没有做游戏内像素对比，也没有跑测试世界的截图对比。默认画面不变的理由是新函数没有调用方、被改写的调用点逐项保持原算式，不是截图证明。

## 九、部分覆盖清零（2026-10-25）

- 海洋：`water` 新增波形空间、方向、波形法线、涟漪混合、泡沫与整像素函数；`shaders/rendering/water/waves.glsl` 的 `physics_waveHeight`、`physics_waveNormal`、`physics_wavePixel` 改为传贴图与选项，迭代正弦、空间换算与泡沫公式只在库里一份。iterationT `PhysicsOceans.glsl` 与 Eclipse `oceans.glsl` 两条同时清零。
- 下界：`fog` 新增五群系光照与雾色加权；`fog_volume` 新增 Eclipse 三段体积雾步进，`NetherVolumetricFog` 只保留射线、雾色与选项接线；`world/nether.glsl` 已调用。`NetherColor.glsl` 与 `nether_fog.glsl` 两条清零。
- 材质：`surface` 新增 `ogxPbrMaterialFromTex`，`bind/gbuffer.glsl` 只复制六个字段；材质编号掩码表保留，因为编号由几何阶段写入并对应 Minecraft 的方块与实体类别。
- 参考文件剩余纯算式：Eclipse `Shadows.glsl` 的两条阴影修补、`ripples.glsl` 的程序化雨点与专用哈希、`waterBump.glsl` 的焦散/水面高度/波法线、`volumetricClouds.glsl` 的梯度噪声与旋度、`voxel_write.glsl` 的索引与边界、`climate_settings.glsl` 的四季与时段雾、`diffuse_lighting.glsl` 的方块光曲线/间接光/手持光、`indirect_lighting_effects.glsl` 的低差异采样与手部深度换算，都已进库。
- 只服务 Minecraft 的剩余部分逐条写进 `docs/gfx-parity.md` 第六节：手持光源与高光、材质编号掩码、手部屏幕阴影与手电筒、Eclipse 屏幕追踪与双边升采样、体素写入、调试叠加与编号表。每条都有参考文件行号或宿主声明位置。
- 对照表：`docs/gfx-parity.md` 重建为 24 个模块表、76 行参考对照、15 条处理记录与汇总；部分覆盖从 15 条降到 0 条，未覆盖仍为 0 条。
- 命令结果：`generate` 输出 24 个模块、49 个文件、GLSL 14910 行；`check` 通过，库内 38 个文件通过中文说明审计；`spirv` 24/24 通过（编译器 2026.20）；`verify` 147 个测试、9 组编译探针通过；`compile` 280 组唯一程序 0 错误（本机冷缓存约 293 秒，热缓存直接复用）。
- 手写核心从 8153 行增加到 8717 行，上限按决策记录调到 8800 行。
- 未验证：没有启动 Minecraft；海洋、下界体积雾、材质解码与群系雾的改写只证明编译与算式逐项对应，游戏内画面与帧时仍未验证。

## 十、函数级对照与真实感世界（2026-10-25）

两项工作在同一次提交里完成：把参考包的函数逐个搬进对照表，并把测试世界从方块岛技术演示推到接近参考光影的场景。

函数级对照：
- 新增 `omni-gfx/tools/parity.py` 与 `tools/parity_map.json`，从 `references/iterationT/shaders/Lib` 与 `references/Eclipse/shaders/lib` 严格解析函数定义（排除宏、控制流与多行声明残留），按“人工对照 → 同名 → 宿主符号 → 缺失”四级判定，输出 `docs/gfx-functions.md` 与 `.dev/omni-gfx/gaps.txt`。
- 505 个参考函数：已迁入 294、MC 专用 154、缺失 36、调试输出 21。MC 专用逐条写出命中的宿主符号；缺失逐条写原因与参考实现行数。
- 本轮新迁入 11 个纯计算函数：`ogxHalton2`、`ogxHalton3`、`ogxRayBoxRange`、`ogxRayBoxIntersection`、`ogxSquare`、`ogxLengthSquared`、`ogxSafeInvLength`、`ogxTriangleWave`、`ogxFma2`、`ogxSinCos`、`ogxRotate2`，探针同步覆盖。
- 自检：人工对照指向不存在的函数时 `python omni-gfx/build.py parity` 以非零状态退出。

测试世界：
- 地形改为 128×128、半格台阶，新增逐角遮蔽、八种材质（草地、泥土、石头、沙子、树叶、树干、草叶、花）与树、灌木、草丛、花、散落岩石，顶点数据十三个浮点含材质与风摆权重。
- 地形片元阶段按材质给粗糙度与高光，三层世界坐标噪声扰动法线并调制底色，叶与草叶加逆光透光；天空环境光按朝向取天空立方体贴图。
- 云改成两层尺度定形状、随高度剪切、域扭曲、竖向包络（平底圆顶）与三维侵蚀；密度函数里的噪声调用从十七次降到九次，视野步数 14、阳光步进 4。
- 水面加强波形坡度、反射按法线偏移、太阳闪光与泡沫按距离淡出；远处收敛到天空色后不再叠地面雾与向下看的空气透视。
- 时间抗锯齿补齐八相位次像素抖动，投影矩阵平移项每帧偏移半个像素以内；遮蔽改成四邻域按深度加权升采样。
- 场景颜色改用全屏着色器拷进水面目标，修掉 `glBlitFramebuffer` 漏掉海天交界一条像素的问题。

帧时（1280×720，本机 Intel Arc 集显，120 帧、预热 30 帧）：

```text
平均 24.1 毫秒，中位 23.8，95 分位 27.9，最小 19.5，最大 31.5，约 41 帧每秒
水面 30720 三角形，阴影 1024²×3，云 640×360×14 步
截图 .dev/omni-gfx/world-realistic.png，记录 .dev/omni-gfx/perf-realistic.json
```

未验证：没有参考光影的实机截图可比，画面只做了目测；海天交界仍有一条断续暗线，来自水面圆盘最外缘的三角形，未彻底解决；其他显卡与水洼、下界、末地场景未测。

## 十一、函数级缺口清零与海天交界修复（2026-10-25）

函数级对照：
- 505 个参考函数：已迁入 329、MC 专用 176、缺失 0、调试输出 0；上一版是 294/154/36/21。`docs/gfx-functions.md` 由 `python omni-gfx/build.py parity` 重新生成，`.dev/omni-gfx/gaps.txt` 为空。
- 20 个承接函数进库：`math` 的 `ogxBayer16/32/128`、`ogxBilinearTexture`、`ogxBilinearTextureSkybox`、`ogxRaySphereHit`、三次 B 样条八件；`atmosphere` 的 `ogxSkyCloudsFromTex`、`ogxSkyCloudsFromTexLod`；`gi` 的 `ogxBilateralUpscale`；`color` 的 `ogxTonemapXonk`、`ogxDecodeVec2x16`；`noise` 的 `ogxIntegerHash3`。另有 `ogxSkyEquirect`、`ogxSkyCloudAtlasCoord` 两个配套函数，把经纬投影与子图布局从采样里拆出来。
- 采样器不再是排除理由：参考里的 `sampler2D` 全部改成显式参数，贴图尺寸、子图原点与边长由调用方传入；库不读取 `texelSize`，也不绑定任何宿主纹理。
- 15 个函数按算法对照到库内已有实现并写进人工对照：`D_Walter`→`ogxDistributionGGX`、`H`→`ogxChandrasekharH`、`ppss`→`ogxPlanetBrdf`、`R2_samples`→`ogxR2Sample`、`CalculateCoCRadius`→`ogxCocRadius`、镜头光斑四件→`ogxGlare*`、抖动五件→`ogxDitherFloat/Fixed`、`skyCloudsFromTexBLUR`→`ogxSkyCloudsFromTex`（参考实现的 `scaler` 参数没有参与计算）。`GetCloudShadow` 读取 `lightningBoltPosition` 与 `sunElevation`，按宿主专用记录。
- 调试叠加的 21 条从“调试输出”改判为 MC 专用，并逐条写证据：`PrintFloat`、`PrintUintBinary` 用 `gl_FragCoord` 定位；`beginText`、`endText`、`printChar`、`printUnsignedInt`、`printFloat`、`printLine` 读写 `text` 叠加对象；其余逐分量打印函数只调用打印链。判定口径写进 `docs/gfx-functions.md`。
- 回归：`test_parity_has_no_missing_functions` 重新判定并断言缺失为空，人工对照指向不存在的函数也会失败。

海天交界：
- 根因是测试世界水面把 `ogxFogMarch` 返回的四个分量整体乘 `1 - horizonBlend`：透过率被一起乘小，远处已经收敛到天空色的水面被乘成近黑，最外圈三角形跨过混合阈值的行就出现断续黑线。
- 修复：`fog` 新增 `ogxFogFade`，只缩放散射色并把透过率朝一插值；水面改为 `ogxFogApply(color, ogxFogFade(fog, 1 - horizonBlend))`。截图同一行左右取五列，天空到水面的差都在三个色阶以内，没有黑线。
- 顺带把远处的天空色改成采样天空立方体贴图（与画面上方同一份六步大气、同样的三度抬升），不再逐像素重算大气；空气透视 3→2 段、水面地面雾 3→2 段、云 14→12 步、立方体天空 4→6 步。

帧时（1280×720，本机 Intel Arc 集显，120 帧、预热 30 帧）：

```text
平均 23.0 毫秒，中位 23.2，95 分位 29.5，最小 11.7，最大 35.1，约 43.5 帧每秒
水面 30720 三角形，阴影 1024²×3，云 640×360×12 步
截图 .dev/omni-gfx/world-realistic.png，记录 .dev/omni-gfx/world-realistic.json
```

未验证：没有启动 Minecraft；游戏内画面、菜单、维度切换、Vulkan/Aperture 运行时与其他显卡仍未验证；帧时会随本机同时运行的程序波动，同一天测到过 21 到 34 毫秒。

## 十二、照片级室外测试世界重建（2026-10-26）

这一轮只改独立测试世界、资源与若干测试世界着色器，不改 Minecraft 入口、选项与默认画面；没有启动 Minecraft。

### 命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py generate` | 24 个模块、49 个文件、GLSL 15486 行 |
| `python omni-gfx/build.py check` | 生成文件与源一致；测试世界着色器中文说明审计通过 |
| `python build.py audit` | 510 个代码文件通过中文说明与实现审计 |
| `python build.py verify` | 148 个测试通过、9 组编译探针通过、打包通过 |
| `python build.py compile` | 280 组唯一程序、0 错误 |
| `python omni-gfx/build.py count` | 手写核心 9267 行，低于 9400 上限 |
| `render.py --frames 120 --warmup 30` | 1280×720，平均 23.2 毫秒，中位 21.4，95 分位 34.8，约 43.1 帧每秒 |

截图：`.dev/omni-gfx/world-photoreal.png`；参考并排：`.dev/omni-gfx/world-comparison.png`；帧时记录：`.dev/omni-gfx/perf-photoreal.json`。参考照片是 NPS 公共领域作品，来源与许可写在 `.dev/omni-gfx/reference/SOURCES.md`。

### 场景与管线

- 连续高度场：湖盆、草甸、砂石浅滩、两侧山丘与五百米外的远山；地形 269280 个三角形，机位前方有一条逐渐下坡的观景走廊。
- PBR 地面：草甸用 ambientCG `Grass004`，泥土、岩石、湿沙、林下腐殖土与树皮用 Poly Haven 扫描图；颜色、法线、粗糙度按坡度、离水距离、林下噪声与小径混合。远景只采样两张颜色以减少填充成本。
- 植被与岩石：近景细分叶团、远景大卡片树冠、环湖树线、灌木、两张交叉草叶、红蓝黄白野花、圆滑细分岩石。树冠与草叶参与阴影，草叶与花不参与反射。
- 天空：Poly Haven `wasteland_clouds_puresky` 的 CC0 1K 全景 HDR；启动时找出最亮像素作为太阳方向，压缩高光肩部后上传，背景与天空立方体贴图共用同一张纹理。天空立方体贴图只生成一次。
- 阴影：三级 CSM、512 像素阴影图、五点十字软核、法线/深度偏置；每四帧重建。PCSS 仍保留在库中；测试世界使用直接引用阴影贴图名字的 PCF，因为这台英特尔驱动把采样器形参解析到错误的纹理单元。
- 水面：镜像相机平面反射，四分之一分辨率、每六帧更新；水波法线扰动、五点纵向模糊、菲涅尔上限零点三、吸收与深水色。
- 后期：按深度排除天空的自动曝光、轻度景深、锐化、两级泛光、ACES、冷暖分离调色、暗角与颗粒；TAA 使用八相位抖动与历史裁剪。

### 未达到照片级的具体差距

- 树冠仍是程序化叶团，近看能看出重复的卡片与圆球轮廓；树干与枝条偏细，缺少真实树皮的分叉。
- 湖岸是噪声椭圆形成的连续浅滩，缺少自然岸线的碎石、倒木与局部陡坎；远山轮廓偏规整。
- 水面反射是四分之一分辨率，树影边缘有块状；水波只有方向波叠加，缺少风纹与细小涟漪。
- 草甸颜色偏亮，野花分布均匀，缺少真实草甸的枯黄斑块与高度层次。
- 天空使用静态全景照片，不再走体积云步进；体积云模块仍保留在 `omni-gfx/src/cloud.slang`，但本测试世界没有调用它，因此“体积云”这一项只证明了库内实现，没有在本截图里体现。
- 没有任何游戏内验证；本机 Intel Arc 的帧时受后台程序影响，95 分位会超过 33 毫秒。

## 十三、光影验证场景（2026-10-26，0.8.1）

这一轮只新增独立测试世界与构建入口，不改 Minecraft 入口、选项、预设与默认画面；没有启动 Minecraft。

### 命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py check` | 生成文件与源一致；户外测试世界与光影验证场景的 `.glsl` 共 4 个文件通过中文说明审计 |
| `python build.py audit` | 通过（范围与数量见本轮终端输出） |
| `python build.py verify` | 通过（测试、关键光影检查、编译探针与打包） |
| `python build.py compile` | 通过（全部程序 × 两种配置 × 基础与开远景环境） |
| `python omni-gfx/build.py lighting --frames 120 --warmup 30` | 1280×720，平均 28.02 毫秒，中位 26.91，95 分位 38.90，约 35.7 帧每秒 |

截图：`.dev/omni-gfx/world-lighting.png`（本机文件，不提交）。并排参考：`.dev/omni-gfx/world-lighting-comparison.png`。帧时记录：`.dev/omni-gfx/perf-lighting.json`。
设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。

第一次冷缓存运行 `python build.py verify` 在 10 秒预算处超时（测试本身 8.83 秒通过，编译探针未开始）；按项目规则没有提高预算或跳过检查，重跑（热缓存）后 148 个测试 6.23 秒通过，编译探针与打包完成。上表记录的是重跑结果。

### 场景与光照管线

- 几何：连续高度场湖盆，地形 131072 个三角形；五个半径零点七八米的球（镜面金属、微光金属、三种电介质，粗糙度从 0.05 到 0.78），两个方块、石台、三根立石与七块散落岩石；水面是一张铺到雾里的平面。
- 太阳与天空：`ogxAtmosphereEarth` 单次散射，直射光颜色取海平面太阳透过率；256×128 等距柱状天空贴图每八帧重建，背景、环境光与水面倒影共用；太阳方向 `(-0.55, 0.50, 0.67)`，仰角约三十度。
- 阴影：三级 CSM，1024 像素阴影图，深色偏置按级联放大；镜头十六米内用六点遮挡搜索 + 六点过滤的 PCSS，中远景用五点百分比过滤；最远一级每两帧更新、不画小物体。
- 全局光：半分辨率八方向地平线遮蔽、六步屏幕空间接触阴影与六点邻域颜色反弹；直射与间接分附件，合成时环境光遮蔽只压间接、接触阴影只压直射。
- 体积云：`cloud.slang` 的三维噪声云块，`cloud_volume` 的步进与光照；半分辨率 640×360、十六步、固定小抖动、九点高斯模糊；多次散射近似与亨耶-格林斯坦相函数；云影贴图 256×256 投到地面。
- 水面：镜像相机平面反射（每五帧更新）、菲涅尔、屏幕折射、逐通道吸收、深水色、太阳闪光、程序化波纹与岸线泡沫；反射按距离模糊。
- 体积雾：高度密度、蓝噪声抖动、阴影贴图步进六步，雾色来自太阳散射与天空环境光。
- 后期：时间抗锯齿、两级泛光、分深度自动曝光、ACES 默认、AgX 可选、轻微冷暖分离、暗角与抖动；内部渲染比例 1.0。

### 并排参考与许可

- Bierstadt Lake Trail, Rocky Mountain National Park, 2009，作者 DimiTalen，CC0，来源 `https://commons.wikimedia.org/wiki/File:Bierstadt_Lake_Trail,_Rocky_Mountain_National_Park,_2009.jpg`。用途：晴天积云、山体明暗与蓝天色。
- Moraine Lake 17092005，Public Domain，来源 `https://commons.wikimedia.org/wiki/File:Moraine_Lake_17092005.jpg`。用途：湖水反射、颜色与透明度。
- 两张参考图只在本机 `.dev/omni-gfx/` 使用，不进入仓库、构建产物或光影 ZIP。

### 仍未达到真实光照的地方

- 云仍偏向扁平的层积云：三层 CSM 与体积步进能给出亮顶、灰底和蓝天缝隙，但没有高耸积雨云的塔状轮廓；近距离看云边仍像软椭圆。
- 体积雾的光柱在薄雾与侧光下很弱；把密度调高会整体发灰，所以当前只保留远景空气透视，没有做出电影式光柱。
- 自动曝光在本场景被四倍上限夹住；平均对数亮度读到约 -6.4，说明原始照度偏低，画面主要靠四倍曝光与 ACES 抬起。
- 水面反射以天空和云为主；地形只有低缓丘陵，缺少参考图里高山在湖面的深色倒影。
- 没有游戏内验证；没有验证其他显卡、Vulkan/Aperture 运行时与移动相机下的 TAA/云延迟。

## 十四、光影验收 v3（2026-10-26，0.10.0）

这一轮只改独立光影验证场景、生成的云/水模块与验证记录，不改 Minecraft 入口、选项、预设与默认画面；没有启动 Minecraft。

### 命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py check` | 生成文件与源一致；测试世界 2 个 `.glsl`、光影验证场景 2 个 `.glsl` 通过中文说明审计 |
| `python build.py audit` | 510 个代码文件通过中文说明与实现审计 |
| `python build.py verify` | 148 个测试通过、9 组编译探针通过、打包通过 |
| `python build.py compile` | 280 组唯一程序、0 错误 |
| `render.py --frames 120 --warmup 40` | 1280×720，平均 16.78 毫秒，中位 16.62，95 分位 18.97，约 59.6 帧每秒 |

截图：`.dev/omni-gfx/world-lighting-v3.png`；并排：`.dev/omni-gfx/world-lighting-comparison-v3.png`（左参考图、中 0.9.0、右 0.10.0）；帧时记录：`.dev/omni-gfx/perf-lighting-v3.json`。设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。

### 本轮的实现

- 体积云：`cloud_volume` 使用参考 Nubis 的 yzw Worley 阈值、x 通道 Perlin-Worley 形状与竖直包络；二维天气图决定云团位置，太阳侧与左侧各有一团覆盖率更高的云。上一版的方位角塔身、砧状顶和太阳云洞全部删除。
- 云光照：七步云内光照，单次散射加三档多次散射，薄边逆光银边，云底天光，云顶与向阳面亮白；云影贴图 512 像素、12 公里范围、每帧更新，地表与水面都接收。
- 云分辨率：640×360 半分辨率、40 步、蓝噪声抖动、双缓冲时间累积（0.14 与邻域夹紧）、两纹素高斯；128 立方参考纹理存在时优先使用，缺失时回退到本地 64 立方。
- 体积雾：十二步二次分布，每步沿太阳方向做三次真实阴影查询（地形阴影与云影），高度衰减、双瓣 HG 相位、蓝噪声抖动；雾只积到 760 米，远处交给空气透视。
- 水面：`water` 新增五组 Gerstner 波法线与三维风纹；平面反射带 mipmap，按距离取层级；菲涅尔封顶并压暗掠射反射；折射按水下光程做逐通道吸收；岸线泡沫改用三维 Worley 噪声与岸坡梯度。
- 地面：草色加绿，补一百到六百米的颜色与法线起伏，降低气溶胶与空气透视；远景从米黄色回到绿灰色。

### 仍未达到的地方

- 细光柱仍以云影光带为主：太阳在画面内，近景没有高遮挡物，云影落在湖面与远山时是宽光带，没有形成电影式的窄光柱；把雾密度调高会整体发灰，所以没有继续加。
- 远山仍有高度场条带；本轮加了远景颜色与法线扰动，条带变弱但没有完全消失。
- 云底与云顶的结构仍偏程序化，左侧远云是一层扁平的卷层云；主云是积云，但边缘仍有软模糊。
- 没有游戏内验证；其他显卡、Vulkan/Aperture 运行时与移动相机下的 TAA/云延迟未验证。

## 十五、光影验收 v4（2026-10-26，0.11.0）

这一轮只改独立光影验证场景、生成的云/水模块与验证记录，不改 Minecraft 入口、选项、预设与默认画面；没有启动 Minecraft。

### 命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py generate` | 24 个模块、49 个文件、GLSL 15660 行 |
| `python omni-gfx/build.py check` | 生成文件与源一致；测试世界与光影验证场景的 GLSL 中文说明审计通过 |
| `python build.py audit` | 510 个代码文件通过中文说明与实现审计 |
| `python build.py verify` | 148 个测试通过、9 组编译探针通过、打包 `Omni-0.11.0.zip` |
| `python build.py compile` | 280 组唯一程序、0 错误 |
| `render.py --frames 120 --warmup 40` | 1280×720，平均 15.76 毫秒，中位 15.51，95 分位 18.08，最小 14.16，最大 19.35，约 63.4 帧每秒 |

截图：`.dev/omni-gfx/world-lighting-v4.png`；并排：`.dev/omni-gfx/world-lighting-comparison-v4.png`（左参考图、中 0.10.0、右 0.11.0）；帧时记录：`.dev/omni-gfx/perf-lighting-v4.json`。设备：Intel(R) Arc(TM) Graphics，OpenGL 3.3.0 - Build 32.0.101.8531，Windows。

### 本轮的实现

- 体积云：`cloud_volume` 的云量由低频与高频两层天气图共同决定，云顶收口高度随高频天气变化；竖直包络改为平底、圆顶、顶部慢慢收口，去掉了上宽下窄的密度曲线。场景里有多朵距离与大小不同的积云，云底暗、云顶亮，逆光薄边保留银边。
- 云影：主画面与云影贴图共用天气图偏移；地表云影权重零点九、水面零点八二，近景草地和湖面都能看到云块明暗。
- 场景：右侧岬角、拱门前小湾、石门小岛、远岸树线、树冠、灌木与半埋岩石；水面远平面扩到十二公里，水片铺到真实地平线。
- 光柱：贴水薄雾高度一点四米，十六步二次分布；雾点从三点五米处开始沿太阳方向做三次阴影查询，近处树冠、石柱与石门不会被第一步二十二米的远查询跳过。树冠与石门在雾里形成暗带，中间留下柔和的亮柱。
- 水面：掠射角菲涅尔上限零点九二；平面反射包含天空、云、远岸树线与石门，按距离取更高 mip 并做五点斜向模糊；太阳闪光强度和频率压到很低，水面不再出现静电噪点；水面接收地形与云影。
- 地表与曝光：地形直射高光压到零点一六，草地不再被低阳大范围镜面高光洗白；自动曝光目标零点零九，气溶胶从 0.28e-3 降到 0.12e-3，天空更深蓝。
- 阴影：低阳时阴影贴图的深度斜率很大，多边形偏移从 2/6 降到 0.5/1.5，树冠和石门的投影才能落到地面与水面；树根、石柱和拱门底座都埋进地面或水底，接触阴影不悬空。

### 仍未达到的地方

- 没有启动 Minecraft；游戏内画面、其他显卡与 Vulkan/Aperture 运行时仍未验证。共享的 `cloud_volume` 云量映射与竖直包络已改，Minecraft 内云形和云量会随之变化，本轮没有做游戏内验证。
- 场景仍是低模：树冠是几团椭球，远岸树线是重复的圆冠加灌木；云场是风格化积云，不是真实气象模拟。
- 光柱已经可见，但仍是柔和体积光，不是硬边激光；把雾密度继续调高会重新把近景洗灰。
- 水面反射是四分之一分辨率平面反射加模糊，近看比真实湖面软；石门倒影在太阳高光附近会被压亮。
- 自动曝光平均对数亮度约 -5.2，仍靠约四倍曝光补偿把暗部抬起；画面已不再整片过曝，但离物理曝光还有差距。

## 二十、Slang 探针全通过与大文件拆分（2026-10-28）

本轮把 `omni-gfx` 的 48 个模块全部送入 Slang 编译器，并把八个过长主体拆进同名文件夹。生成物仍是每个模块一个 `.glsl`，探针仍是每个模块一个 `.slang`，模块数量、选项数量与程序数量都不变。

### 命令与结果

| 命令 | 结果 |
| --- | --- |
| `python omni-gfx/build.py generate` | 48 个模块、49 个文件、GLSL 15521 行 |
| `python omni-gfx/build.py spirv` | 48/48 个探针通过，编译器 2026.20 |
| `python omni-gfx/build.py check` | 生成文件与源一致；测试世界 2 个、光影验证场景 2 个 GLSL 审计通过 |
| `python omni-gfx/build.py strict-parity` | 505 个参考函数：exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0 |
| `python omni-gfx/build.py profiles` | iterationt 15595 行、eclipse 15594 行，两份 profile 编译通过 |
| `python build.py audit` | 526 个代码文件通过中文说明与实现审计 |
| `python build.py verify` | 160 个测试、9 组编译探针与打包通过 |
| `python build.py compile` | 280 组唯一程序、0 错误 |
| `python omni-gfx/build.py count` | 手写核心 18883 行，上限 18900 |

### 拆分

- `cloud/eclipse.slang`：shape、shadow、lighting、march、layers、exact 六个子文件。
- `math.slang`：basics、shading、pattern、filter 四个子文件。
- `atmosphere/atmosphere.slang`：scattering、sun、mapping、planet 四个子文件。
- `post/post.slang`：bloom、dof、effects 三个子文件。
- `gi/gi.slang`：ao、temporal、spatial 三个子文件。
- `water.slang`：waves、rain、ocean 三个子文件。
- `color.slang`：tonemap、agx 两个子文件。
- `fog/fog.slang`：density、end 两个子文件。
- 拆分前后逐模块核对函数名与顶层声明：八个模块的函数数量分别为 117、59、35、40、57、28、13、34，全部一致；没有函数被重复或遗漏。
- 生成器把子文件按源码顺序内联，`manifest.json` 的 `parts` 记录每个子文件摘要；改子文件也会被 `check` 发现。

### Slang 兼容

- `inversesqrt` 在 Slang 里叫 `rsqrt`；`math` 与 `gi` 的四处直接调用已改。
- `mod` 在 Slang 里不可用；GLSL 取模语义统一走 `ogxMod`。
- `mix`、`texelFetch`、两参数 `atan`、`dFdx`/`dFdy` 分别改用 `lerp`、纹理取格、`atan2`、`ddx`/`ddy`，生成器补等价降级。
- 向量 `!=`/`==` 在 GLSL 返回单个布尔值、在 Slang 返回布尔向量，改成逐分量比较；矩阵乘向量按列显式展开。
- 一维与三维无符号纹理用探针别名补 `Usampler1D` / `Usampler3D`；`inverse` 与 `textureSize` 只在探针兼容文件里补实现，不进入生成 GLSL。

### 未验证

没有启动 Minecraft；游戏内画面、菜单、选项切换、性能与其他显卡仍未验证。SPIR-V 只是模块编译探针，不是可运行的 Vulkan 管线。README 已写明许可证尚未确定，发布前必须补齐。
