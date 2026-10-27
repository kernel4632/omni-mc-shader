# omni-gfx 架构

这份文件解释当前实现为什么长这样，方便新会话在不读完全部代码时判断改动边界。调用位置：修改 `omni-gfx/src/` 或生成器前先读。

## 一、唯一源与两份产物

`omni-gfx/src/**/*.slang` 是唯一手写算法源，按实际效果分文件夹。构建分两条路：

```text
src/cloud/eclipse.slang ─┬─ 生成器转换 ─→ shaders/omni-gfx/cloud/eclipse.glsl  （唯一 GLSL 产物）
                         └─ slangc 探针 ─→ generated/spirv/cloud/eclipse.spv    （编译验证产物）
```

GLSL 由 `tools/generate.py` 做固定、可审查的语法降级，不用 Slang 自带的 GLSL 后端。原因是实测后端输出 `#version 450`、把函数改名为 `toneMap_0` 并附带自己的 `main()`，无法作为库被光影 `#include`。降级表只覆盖本项目实际使用的差异：

| Slang 写法 | GLSL 写法 | 原因 |
| --- | --- | --- |
| `float3` / `float2` / `int2` | `vec3` / `vec2` / `ivec2` | 类型名不同 |
| `static const` | `const` | GLSL 全局常量不接受 static |
| `Sampler2D` | `sampler2D` | 纹理句柄类型名不同 |
| `lerp` | `mix` | 插值函数名不同 |
| `asfloat` / `asuint` / `asint` | `uintBitsToFloat` / `floatBitsToUint` / `floatBitsToInt` | 按位重解释函数名不同 |
| `tex.Load(int3(p, l))` | `texelFetch(tex, p, l)` | 显式取像素接口不同 |
| `tex.SampleGrad(uv, du, dv)` | `textureGrad(tex, uv, du, dv)` | 带屏幕导数的采样，用于旋转网格超采样 |

生成器遇到表外语法会直接报错，不静默复制。`tests/test_omni_gfx.py` 会检查生成文本没有残留 Slang 写法、没有 `#version`、没有宿主符号。

## 二、模块与边界

| 模块 | 内容 | 依赖 |
| --- | --- | --- |
| `math.slang` | 常数、夹紧、亮度、三角近似、编码、GGX、黑体、求交、噪声、拜尔、切线基、矩阵列展开、空间扭曲、光斑曲线、R2 采样、余弦半球、手部深度换算 | 无 |
| `color.slang` | 伽马、ACES、AgX、高级调色、暗视觉、白平衡、黑边 | `math` |
| `sampling.slang` | 蓝噪声、时间抖动、拜尔时间抖动、平滑过滤、旋转网格超采样、球面映射、颜色抖动 | `math` |
| `sampling/anisotropic.slang` | 各向异性椭圆核、长轴步进、法线与材质加权 | `math` |
| `noise.slang` | 整数哈希、二维向量哈希、值噪声、梯度噪声与旋度、分形叠加、域扭曲 | `math` |
| `camera.slang` | 深度与视空间还原、投影、手部深度换算 | `math` |
| `surface.slang` | 方块光曲线、材质法线与遮蔽、火把光、自发光、labPBR 材质解码 | `math` |
| `water.slang` | 波法线、菲涅尔、吸收、折射、GGX、岸线泡沫、水面合成、水体雾、焦散 | `math`、`noise` |
| `upscale.slang` | FSR 边缘方向重采样、对比度自适应锐化 | `math` |
| `parallax.slang` | 高度采样、平滑与锐利视差、自阴影、高度场法线 | `math`、`sampling` |
| `planet.slang` | 末地行星本体、光环、大气 | `math`、`atmosphere` |
| `accretion.slang` | 吸积盘积分、空间扭曲、圆环辉光、多普勒 | `math`、`fog` |
| `lpv.slang` | 光传播体积的取样解码、写入编码、亮度曲线、边缘淡出与合成 | `color`、`math` |
| `gbuffer.slang` | 延迟缓冲材质编号与遮罩解码 | `surface`、`math` |
| `heldlight.slang` | 手持光形状、方向、漫反射与遮挡 | `surface`、`shadow`、`math`、`color` |
| `atmosphere/atmosphere.slang` | 球面几何、瑞利与米氏密度、单次散射天空、空气透视、太阳圆盘、星场 | `math`、`color` |
| `atmosphere/model.slang` | 预计算大气坐标、透过率、散射、辐照度、简化散射与陆地空气透视 | `atmosphere`、`math`、`color`、`shadow` |
| `atmosphere/sky.slang` | Eclipse 日月圆盘、球面映射、双三次采样、天空盒查表、大气积分与极光 | `math`、`atmosphere` |
| `cloud/cloud.slang` | 球壳求交、程序化云密度、朝阳光照、沿视线步进、云影与平面云 | `math`、`noise` |
| `cloud/volume.slang` | 体积云形状、光照、步进、闪电与云影贴图 | `cloud`、`color`、`math` |
| `cloud/eclipse.slang` | Eclipse 五层云形状、云影、朝光散射与主步进循环 | `cloud`、`atmosphere/sky`、`math` |
| `cloud/planar.slang` | iterationT 平面云密度与光照深度 | `cloud`、`math`、`atmosphere/model` |
| `fog/fog.slang` | 高度衰减、噪声雾团、混合相位、粉末效应、沿视线积分、雾相位与末地雾阴影 | `math`、`noise` |
| `fog/volume.slang` | 体积雾密度、光照吸收、步进、暴风、水下光柱与下界烟 | `fog`、`weather`、`shadow`、`water`、`color`、`sampling` |
| `shadow/shadow.slang` | 阴影投影与边缘压缩、屏幕空间阴影、级联、PCSS、可变半影 | `math` |
| `shadow/eclipse.slang` | Eclipse 阴影边缘压缩、投影偏差、硬阴影、轨道旋转与体素阴影图 | `math`、`voxel/trace` |
| `voxel/voxel.slang` | 三维逐格步进、半透明染色、植物穿透、铁块镜面弹射 | `math`、`color` |
| `voxel/trace.slang` | 射线任务、包围盒、栅栏、裁剪排序、四分之一体素与螺旋采样 | `math`、`voxel` |
| `gi/gi.slang` | 地平线遮蔽、反射阴影图反弹、历史重投影、时间与空间滤波、多弹射 | `math`、`shadow`、`sampling` |
| `gi/diffuse.slang` | 手持光屏幕空间阴影、方块光曲线与手电光 | `camera`、`math` |
| `gi/indirect.slang` | 余弦半球采样、切线基、屏幕空间 GI、双边上采样与 SSGI 合成 | `camera`、`math`、`reflection` |
| `gi/ambientocclusion.slang` | Eclipse GTAO 弧段积分、最大水平角与多切片遮蔽 | `camera`、`math` |
| `reflection/reflection.slang` | 可见法线采样、屏幕空间追踪、菲涅耳合并、九点小波降噪 | `math` |
| `reflection/wsr.slang` | WSR 体素追踪、屏幕空间反射、LPV 雾、空气雾与水下体积 | `math`、`voxel/trace`、`shadow/eclipse`、`fog`、`water`、`weather/lightning`、`lpv`、`heldlight`、`gi/indirect` |
| `reflection/photonics.slang` | Photonics 命中面着色、方块光、云影与半透明反射合成 | `math`、`voxel`、`shadow/eclipse`、`gi/diffuse`、`gi/indirect` |
| `reflection/specular.slang` | GGX、可见法线采样、粗糙菲涅耳、反射可见度与高光合成 | `math`、`heldlight`、`atmosphere/sky`、`reflection/wsr` |
| `post/post.slang` | 泛光核、三次升采样、亮度曲线、暗角、颗粒、景深、动态模糊、分块测光、远景噪点 | `math`、`noise`、`sampling`、`shadow` |
| `post/exposure.slang` | 自动曝光分块统计、曝光值与泛光合并 | `math`、`shadow` |
| `post/scene.slang` | 受伤、入水与着火画面效果、场景控制参数 | `math` |
| `lens/lens.slang` | 对焦距离、桶形光斑、彩色鬼影、环形眩光与太阳眩光 | `math`、`shadow` |
| `antialias/antialias.slang` | YCoCg、历史邻域裁剪、三次采样、时间重投影 | `math` |
| `antialias/taa.slang` | 三乘三最近深度、远景深度与相机速度 | `camera`、`math` |
| `antialias/fxaa.slang` | 亮度梯度边缘方向与 FXAA 内插 | 无 |
| `weather/weather.slang` | 雨雪随风偏移、植被与季节、暴风噪声与染色、每日天气哈希 | `math` |
| `weather/rain.slang` | 三层动画雨纹、降水分布与湿润度更新 | `math` |
| `weather/lightning.slang` | 闪电照亮表面、云与雾，末地光源位置与颜色 | `math` |
| `world/end.slang` | iterationT 末地星空、行星 BRDF、黑洞吸积盘与云影查表 | `math`、`fog`、`cloud`、`planet` |
| `world/portal.slang` | 末地传送门十六层旋转、缩放与平移矩阵 | `math` |
规则：

- 函数统一 `ogx` 前缀，宏统一 `OGX_` 前缀，守卫统一 `OGX_*_INCLUDED`。
- 不出现 `OMNI_*`、`colortex`、`noisetex`、`gl_FragCoord` 等宿主符号；像素坐标、帧号、纹理全部由调用方传入。
- 效果模块只做纯计算与显式参数组合，不读取选项、天气或宿主时间；反射与折射颜色由调用方传入，库不绑定采样器。
- 大气长度单位统一为公里，避免行星半径用米时 `float` 精度不足；调用方把米乘 `0.001`。
- 矩阵乘法显式展开成列向量乘分量，避免 Slang 与 GLSL 行列顺序不同造成转置错误。

## 三、生成与可复现

`tools/generate.py` 的输出不含时间戳，同一份源每次生成相同字节。`generated/manifest.json` 记录每个模块的源摘要、产物摘要和行数；`build.py check` 与测试都会比较磁盘内容，过期时列出具体路径。

`shaders/omni-gfx/` 是 Iris 实际读取的位置，也是唯一的 GLSL 产物；不再保留镜像副本。

SPIR-V 由 `tests/probes/**/*.slang` 编译，目录与源模块一致，每个模块一个探针。产物在 `generated/spirv/`，`.spv` 与清单被忽略规则排除，不入仓库；换机器后运行 `python omni-gfx/build.py spirv --download` 重新生成。清单记录编译器版本 `2026.20`、大小与 SHA-256。

## 四、测试世界

`examples/world/` 是一个独立 OpenGL 3.3 消费者，不读取 Minecraft 的任何文件：

```text
现实天空 HDR（Poly Haven CC0，1024×512）─→ 全屏背景 + 天空立方体贴图（128²，只生成一次）
地面 PBR 纹理数组（草、土、石、沙、林下、树皮，512²×6）─→ 地形按坡度/湿度/小径混合
连续高度场（269280 三角形）─→ 山谷、湖盆、砂石岸、远山
透明卡片（树冠、草叶、野花）与圆滑岩石 ─→ 三级 CSM（512²×3，五点软核）
        ↓
场景颜色 + 法线深度
        ↓
半分辨率全局光（地平线遮蔽 + 多弹射 + 历史混合）
四分之一分辨率平面反射（镜像相机，只画水面以上景物，每六帧更新）
        ↓
水面（菲涅尔、折射、吸收、方向波纹、五点纵向模糊、空气透视与雾）
        ↓
时间抗锯齿（次像素抖动 + 重投影 + 邻域裁剪 + 遮蔽升采样）
        ↓
自动曝光（按深度排除天空）→ 轻度景深、锐化、两级泛光、ACES、冷暖分离调色、暗角、颗粒 → PNG + 帧时 JSON
```

场景内容：

- 地形由 `terrain.py` 的程序化高度场生成：湖盆椭圆带噪声岸线，水线附近压出浅滩，机位正前方有一条连续下坡走廊；材质按坡度、离水距离、林下噪声和土路混合。
- 树木、灌木、草丛、野花与岩石由 `vegetation.py` 生成。近景树用细分叶团，远景树用更大的卡片和更少叶片；草叶用两张交叉卡片，野花卡片包含红、蓝、黄、白四种花。
- 天空由 `sky.py` 读取 `assets/sky_wasteland.hdr`，找出最亮像素作为太阳方向，再把等距柱状纹理映射到屏幕与立方体贴图。天空是静态照片，不参与每帧体积云步进。
- 水面用镜像相机渲染平面反射，目标只有屏幕四分之一；水波法线扰动采样位置，纵向五点模糊掩盖低分辨率。
- 阴影每四帧重建一次，反射每六帧更新；固定机位下阴影与倒影的滞后不可见，移动相机时由时间抗锯齿与水面波纹掩盖。

材质资产与来源：

- `assets/*.png` 由 `examples/world/prepare_textures.py` 从 Poly Haven / ambientCG 的 CC0 原图降采样到 512，颜色用 sRGB、法线与粗糙度保持线性。
- `assets/sky_wasteland.hdr` 是 Poly Haven 的 1K 全景 HDR，保留原始辐射值，启动时用 `hdr.py` 解码并压缩高光肩部。
- 每张图的原始地址、作者与 CC0 许可都写在 `assets/SOURCES.md`；并排参考照片在 `.dev/omni-gfx/reference/SOURCES.md`，不进仓库。

边界与验证：

- `omni-gfx/build.py check` 审计测试世界实际编译的 GLSL；测试世界的 Python 与资源脚本是开发期消费者，不进入光影 ZIP，也不参与库注释比例。
- 游戏内画面、其他显卡、Vulkan 运行时尚未验证。画面仍偏程序化，未达到真实照片级；参考对比保存在 `.dev/omni-gfx/world-comparison.png`。

`examples/lighting/` 是光影验收场景，几何保持低模，重点检查光照链路：

- 太阳与天空直接读取 `references/iterationT/shaders/texture/AtmoData_620_540_440_n4.bin`（512×128×33 RGBA32F）。CPU 每帧用同一张表算太阳直射、天空辐照度与太阳透过率，片元阶段只读 uniform；天空背景仍在 GPU 上逐像素查表。
- 云使用参考包的 `CloudNoise_128_128_128.bin` 与 `CloudNoise2_32_32_32.bin`，密度、光照、步数与云影按 NUBIS 对齐；体积雾按参考包的密度剖面、六步指数分布与四次太阳方向取样。
- 阴影是三级级联上的可变半影；环境光遮蔽是 GTAO 三切片；曝光与色调映射是 AgX 13、AE 曲线 0.7；水面是镜像相机平面反射加水体吸收，替代参考包的屏幕空间追踪。
- 固定机位截图时，相机、太阳与时间不变，阴影、云影、天空贴图与倒影只烘一次；1280×720 的平均帧时记录在 `omni-gfx/docs/verification.md`。
- 验收截图与并排对比只放 `.dev/omni-gfx/`，不进入仓库；游戏内画面仍未验证。

## 五、为什么没有 CMake 与 C++

阶段 0 原计划用 SDL3 GPU + CMake。本机没有 cmake、cl、g++，下载 SDL3 也无法完成可验证的构建。用户允许改用 Python + GLFW + PyOpenGL，因此当前演示程序是 Python。没有创建无法运行的 `CMakeLists.txt`，避免留下假入口。未来若引入 C++ 消费者，再按实际工具链补构建文件。

## 六、阶段 3 的扩展点

- 九个效果模块（大气、云、水面、雾、阴影、全局光、反射、后期、抗锯齿）都已迁入 `src/`，Minecraft 侧的九个适配层只保留调用点与宿主开关。
- 阴影已经做到三级级联与 PCSS；全局光有地平线遮蔽、反射阴影图反弹与两级滤波；反射有屏幕空间追踪与九点降噪；抗锯齿有时间重投影。
- 时间累积用在天空与云、遮蔽历史与抗锯齿历史三处；动态分辨率与专用升采样器还没有接入。
- 需要纹理过滤时，先设计显式的采样器与纹理坐标接口，再迁移双三次函数；当前效果模块只收纯计算，反射色由调用方传入。
- 第三批已经把平滑过滤、最近点取样与旋转网格超采样做成 `sampling` 的显式接口（导数由调用方传入），因此这条扩展点只剩“接到光影选项”这一步。
- SPIR-V 从“模块探针”升级为“完整演示管线”时，把顶点/片元入口写成 Slang，并保留 GLSL 生成路径。
- Minecraft 的接入点目前是 `effects/fog/landscattering.glsl` 的相函数：它引入生成的 `atmosphere` 模块并调用 `ogxRayleighPhase` / `ogxMiePhase`，数值与旧实现逐项一致；`python build.py compile` 覆盖全部程序。

## 七、第二批迁移（2026-10-25）

第二批迁移时 `shaders/gfx/` 只剩 23 个适配层；2026-10-27 这些适配层已删除，效果文件直接引用 `shaders/omni-gfx/`，不再保留第二层转发。

规则补充：

- 算法模块只收纯计算；需要按步回调宿主的地方（雾照明、水下手持光、反射主流程的天空与体素钩子）用钩子宏或直接留在所属效果文件，并在文件头写明原因。
- 不能用作形参名的保留字：`sample` 在 GLSL 4.0 以后是插值限定符，430 的计算程序会直接报语法错误，统一改叫 `texel` 或 `value`。
- 切线空间转换用三个显式点乘（`ogxParallaxToTangent`），矩阵乘向量用 `ogxMatrix3MulPoint` / `ogxMatrixMulPoint`，向量乘矩阵用 `ogxApplyRows`；不再写 `v * M`，因为 Slang 不支持这种写法，而 GLSL 与 Slang 的行列顺序又不同。
- 三维纹理用 `Sampler3D`，取格写 `tex.Load(int3(pixel, level))`；生成器把它降级成 `texelFetch`。
- 结构体字段沿用旧下划线命名，宿主逐字段赋值不用改；新写的结构体用驼峰命名。

SPIR-V 覆盖：48 个模块各有探针；整数三维纹理（`usampler3D`）在 `voxel` 与 `voxel/trace` 探针里显式绑定。
