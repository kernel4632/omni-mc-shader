# omni-gfx 架构

这份文件解释当前实现为什么长这样，方便新会话在不读完全部代码时判断改动边界。调用位置：修改 `omni-gfx/src/` 或生成器前先读。

## 一、唯一源与两份产物

`omni-gfx/src/*.slang` 是唯一手写算法源。构建分两条路：

```text
src/math.slang ─┬─ 生成器转换 ─→ shaders/omni-gfx/math.glsl  （Iris 直接 include）
                ├─ 生成器转换 ─→ generated/glsl/math.glsl     （独立库镜像）
                └─ slangc 探针 ─→ generated/spirv/math.spv    （编译验证产物）
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
| `sampling.slang` | 蓝噪声、时间抖动、拜尔时间抖动 | `math` |
| `noise.slang` | 整数哈希、二维向量哈希、二维与三维值噪声、二维梯度噪声与旋度、分形叠加、域扭曲、查表式雾噪声 | `math` |
| `atmosphere.slang` | 球面几何、瑞利与米氏密度、光学厚度、单次散射天空、空气透视、太阳圆盘、星场与日月圆盘 | `math` |
| `cloud.slang` | 球壳求交、程序化云密度、朝阳光照、沿视线步进、云影、平面云扭曲与多层密度 | `math`、`noise` |
| `water.slang` | 方向波法线、菲涅尔、吸收、折射偏移、GGX 高光、岸线泡沫、水面合成、水位波与水体雾、迭代海洋、涟漪混合、泡沫、Eclipse 雨点与水面高度/焦散 | `math`、`noise` |
| `fog.slang` | 高度衰减、噪声雾团、混合相位、粉末效应、沿视线积分、下界五群系配色、群系雾色与密度 | `math`、`noise` |
| `shadow.slang` | 阴影投影与边缘压缩、屏幕空间阴影、级联选择、PCSS 遮挡物搜索、可变半影与透光散射、Eclipse 阴影修补 | `math` |
| `gi.slang` | 地平线遮蔽、反射阴影图反弹、历史重投影、时间滤波、七乘七空间滤波、多弹射 | `math`、`shadow` |
| `reflection.slang` | 可见法线采样、屏幕空间追踪、菲涅耳合并、九点小波降噪 | `math` |
| `post.slang` | 泛光核、三次升采样、亮度曲线、暗角、颗粒、景深、动态模糊、分块测光 | `math` |
| `antialias.slang` | YCoCg、历史邻域裁剪、三次采样、时间重投影 | `math` |
| `weather.slang` | 雨雪随风偏移、植被与季节、暴风噪声与染色、每日天气哈希、四季上色、时段雾密度 | `math` |
| `surface.slang` | 方块光曲线、材质法线与遮蔽、火把光、自发光、labPBR 材质解码、Eclipse 间接光、光斑、手持光 | `math` |
| `parallax.slang` | 高度采样、平滑与锐利视差、自阴影、高度场法线 | `math` |
| `voxel.slang` | 三维逐格步进、半透明染色、植物穿透、铁块镜面弹射、写入索引与边界 | `math`、`color` |
| `upscale.slang` | FSR 边缘方向重采样、对比度自适应锐化 | `math` |
| `planet.slang` | 末地行星本体、光环、大气 | `math`、`atmosphere` |
| `accretion.slang` | 吸积盘积分、空间扭曲、圆环辉光、多普勒 | `math`、`fog` |
| `atmosphere_model.slang` | 预计算大气的坐标、透过率、散射、辐照度与简化散射 | `atmosphere`、`math`、`color` |
| `cloud_volume.slang` | 体积云形状、光照、步进、闪电与云影贴图 | `cloud`、`math` |
| `fog_volume.slang` | 体积雾密度、光照吸收、步进、暴风、水下光柱、下界三段烟 | `fog`、`weather`、`shadow`、`water`、`color` |
| `lpv.slang` | 光传播体积的取样解码、写入编码、亮度曲线、边缘淡出与合成 | `color`、`math` |

规则：

- 函数统一 `ogx` 前缀，宏统一 `OGX_` 前缀，守卫统一 `OGX_*_INCLUDED`。
- 不出现 `OMNI_*`、`colortex`、`noisetex`、`gl_FragCoord` 等宿主符号；像素坐标、帧号、纹理全部由调用方传入。
- 效果模块只做纯计算与显式参数组合，不读取选项、天气或宿主时间；反射与折射颜色由调用方传入，库不绑定采样器。
- 大气长度单位统一为公里，避免行星半径用米时 `float` 精度不足；调用方把米乘 `0.001`。
- 矩阵乘法显式展开成列向量乘分量，避免 Slang 与 GLSL 行列顺序不同造成转置错误。

## 三、生成与可复现

`tools/generate.py` 的输出不含时间戳，同一份源每次生成相同字节。`generated/manifest.json` 记录每个模块的源摘要、产物摘要和行数；`build.py check` 与测试都会比较磁盘内容，过期时列出具体路径。

`shaders/omni-gfx/` 是 Iris 实际读取的位置，`generated/glsl/` 是镜像。两处必须逐字节相同，测试会直接比较。

SPIR-V 由 `tests/probes/*.slang` 编译，探针调用每个模块的全部公开函数。产物在 `generated/spirv/`，`.spv` 与清单被忽略规则排除，不入仓库；换机器后运行 `python omni-gfx/build.py spirv --download` 重新生成。清单记录编译器版本 `2026.20`、大小与 SHA-256。

## 四、测试世界

`examples/world/` 是一个独立 OpenGL 3.3 消费者，不读取 Minecraft 的任何文件：

```text
三级级联阴影贴图 1024²×3（地形、树木、草叶深度） ─→ 地形（材质粗糙度、微表面法线、叶片透光、PCSS、云影、环境光）
天空立方体贴图 128² ────────────────→ 反射兜底、地形环境光
半分辨率天空与云（14 步、4 次阳光步进） ─→ 时间累积 → 双边升采样合并成场景背景
场景目标（背景 + 地形，颜色 + 法线深度两张附件）
        ↓
半分辨率全局光（地平线遮蔽 + 多弹射 + 历史混合）
半分辨率反射（世界空间步进，写颜色、深度、法线三张附件）→ 九点降噪
场景颜色与深度拷进水面目标（颜色用全屏着色器拷贝，深度用帧缓冲拷贝）
水面目标（菲涅尔、折射、吸收、岸线泡沫、太阳闪光、空气透视与雾）
        ↓
时间抗锯齿（次像素抖动 + 重投影 + 邻域裁剪 + 遮蔽双边升采样）→ 两级泛光
        ↓
两级对数亮度统计 ─→ 自动曝光、泛光、暗角、颗粒、ACES / AgX / 无压缩、抖动 ─→ PNG + 帧时 JSON
```

地形与植被由 `terrain.py`、`vegetation.py` 在 CPU 侧生成：半格高度的岛屿高度图、逐角遮蔽、材质编号（草地、泥土、石头、沙子、树叶、树干、草叶、花），以及树、灌木、草丛、花与散落岩石。顶点数据每个十三个浮点：位置、法线、颜色、遮蔽、材质、风摆权重。

片元阶段按材质给不同粗糙度与高光，用世界坐标上的三层噪声扰动法线并调制底色，树叶与草叶加一层逆光透光；这些是测试世界没有贴图时去掉“塑料感”的主要手段。

水面反射是屏幕空间步进；反射方向压到水平面以上再采样天空立方体贴图，避免采到天空盒底部的黑面。场景颜色改用全屏着色器拷进水面目标：`glBlitFramebuffer` 在这台机器上会漏掉海天交界的一条像素，改成着色器拷贝后消失。

时间抗锯齿使用八相位次像素抖动，投影矩阵的平移项每帧偏移半个像素以内；重投影用上一帧带抖动的视图投影，因此静止画面也能把树线与草叶的边缘磨平。

阶段 3 的测试世界默认机位是位置 `(126, 31, 142)`、看向 `(58, 16, 58)`、太阳方向 `(0.72, 0.52, 0.46)`；截图与帧时记录在 `.dev/omni-gfx/`。相机矩阵在 `camera.py` 按列主序直接生成，视图投影相乘后原样上传。交互模式使用 GLFW 键鼠回调；截图模式使用固定机位和固定时间，保证重复运行画面一致。

## 五、为什么没有 CMake 与 C++

阶段 0 原计划用 SDL3 GPU + CMake。本机没有 cmake、cl、g++，下载 SDL3 也无法完成可验证的构建。用户允许改用 Python + GLFW + PyOpenGL，因此当前演示程序是 Python。没有创建无法运行的 `CMakeLists.txt`，避免留下假入口。未来若引入 C++ 消费者，再按实际工具链补构建文件。

## 六、阶段 3 的扩展点

- 九个效果模块（大气、云、水面、雾、阴影、全局光、反射、后期、抗锯齿）都已迁入 `src/`，Minecraft 侧的九个适配层只保留调用点与宿主开关。
- 阴影已经做到三级级联与 PCSS；全局光有地平线遮蔽、反射阴影图反弹与两级滤波；反射有屏幕空间追踪与九点降噪；抗锯齿有时间重投影。
- 时间累积用在天空与云、遮蔽历史与抗锯齿历史三处；动态分辨率与专用升采样器还没有接入。
- 需要纹理过滤时，先设计显式的采样器与纹理坐标接口，再迁移双三次函数；当前效果模块只收纯计算，反射色由调用方传入。
- 第三批已经把平滑过滤、最近点取样与旋转网格超采样做成 `sampling` 的显式接口（导数由调用方传入），因此这条扩展点只剩“接到光影选项”这一步。
- SPIR-V 从“模块探针”升级为“完整演示管线”时，把顶点/片元入口写成 Slang，并保留 GLSL 生成路径。
- Minecraft 的接入点目前是 `rendering/fog/landscattering.glsl` 的相函数：它引入生成的 `atmosphere` 模块并调用 `ogxRayleighPhase` / `ogxMiePhase`，数值与旧实现逐项一致；`python build.py compile` 覆盖全部程序。

## 七、第二批迁移（2026-10-25）

`shaders/gfx/` 里的算法已经全部迁入 `src/`，该目录只剩 23 个适配层与一份说明。适配层保留旧函数名、旧宏、结构体字段与输出参数，宿主调用点完全不动。

规则补充：

- 算法模块只收纯计算；需要按步回调宿主的地方（雾照明、水下手持光、反射主流程的天空与体素钩子）用钩子宏或直接留在适配层，并在文件头写明原因。
- 不能用作形参名的保留字：`sample` 在 GLSL 4.0 以后是插值限定符，430 的计算程序会直接报语法错误，统一改叫 `texel` 或 `value`。
- 切线空间转换用三个显式点乘（`ogxParallaxToTangent`），矩阵乘向量用 `ogxMatrix3MulPoint` / `ogxMatrixMulPoint`，向量乘矩阵用 `ogxApplyRows`；不再写 `v * M`，因为 Slang 不支持这种写法，而 GLSL 与 Slang 的行列顺序又不同。
- 三维纹理用 `Sampler3D`，取格写 `tex.Load(int3(pixel, level))`；生成器把它降级成 `texelFetch`。
- 结构体字段沿用旧下划线命名，宿主逐字段赋值不用改；新写的结构体用驼峰命名。

SPIR-V 覆盖：22 个模块探针编译通过，`voxel` 因为持有整数三维纹理（`usampler3D`）暂缺探针，命令会跳过并列出；这不影响 GLSL 路径与光影编译。
