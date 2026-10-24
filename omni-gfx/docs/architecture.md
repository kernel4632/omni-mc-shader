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

生成器遇到表外语法会直接报错，不静默复制。`tests/test_omni_gfx.py` 会检查生成文本没有残留 Slang 写法、没有 `#version`、没有宿主符号。

## 二、模块与边界

| 模块 | 内容 | 依赖 |
| --- | --- | --- |
| `math.slang` | 常数、夹紧、亮度、三角近似、编码、GGX、黑体、求交、噪声、拜尔、切线基、空间扭曲 | 无 |
| `color.slang` | 伽马、ACES、AgX、高级调色、暗视觉、白平衡、黑边 | `math` |
| `sampling.slang` | 蓝噪声、时间抖动、拜尔时间抖动 | `math` |

规则：

- 函数统一 `ogx` 前缀，宏统一 `OGX_` 前缀，守卫统一 `OGX_*_INCLUDED`。
- 不出现 `OMNI_*`、`colortex`、`noisetex`、`gl_FragCoord` 等宿主符号；像素坐标、帧号、纹理全部由调用方传入。
- 贴图过滤函数（双三次采样）需要宿主采样器状态，暂不迁移；当前只收纯计算与 `texelFetch`。
- 矩阵乘法显式展开成列向量乘分量，避免 Slang 与 GLSL 行列顺序不同造成转置错误。

## 三、生成与可复现

`tools/generate.py` 的输出不含时间戳，同一份源每次生成相同字节。`generated/manifest.json` 记录每个模块的源摘要、产物摘要和行数；`build.py check` 与测试都会比较磁盘内容，过期时列出具体路径。

`shaders/omni-gfx/` 是 Iris 实际读取的位置，`generated/glsl/` 是镜像。两处必须逐字节相同，测试会直接比较。

SPIR-V 由 `tests/probes/*.slang` 编译，探针调用每个模块的全部公开函数。产物在 `generated/spirv/`，`.spv` 与清单被忽略规则排除，不入仓库；换机器后运行 `python omni-gfx/build.py spirv --download` 重新生成。清单记录编译器版本 `2026.20`、大小与 SHA-256。

## 四、测试世界

`examples/world/` 是一个独立 OpenGL 3.3 消费者，不读取 Minecraft 的任何文件：

```text
天空立方体贴图（含云） ─→ 水面反射
        ↓
场景目标：天空背景 + 地形（高度图阴影、雾）
        ↓ 颜色与深度复制
水面目标：菲涅尔反射、屏幕空间折射、深浅水色、太阳高光
        ↓
后期：曝光、暗角、ACES / AgX / 无压缩、抖动
        ↓
PNG + 帧时 JSON
```

地形由固定种子的二维值噪声生成高度图，再生成顶面与露出的侧墙；颜色和遮蔽在 CPU 侧算好。水面是解析方向波，不依赖法线贴图。云层在 120–185 米高度区间内步进 14 次，平面二维噪声取密度，朝太阳做 2 次短步进估计透光。所有步数与尺寸都是常数，方便比较帧时。

相机矩阵在 `camera.py` 按列主序直接生成，视图投影相乘后原样上传。交互模式使用 GLFW 键鼠回调；截图模式使用固定机位和固定时间，保证重复运行画面一致。

## 五、为什么没有 CMake 与 C++

阶段 0 原计划用 SDL3 GPU + CMake。本机没有 cmake、cl、g++，下载 SDL3 也无法完成可验证的构建。用户允许改用 Python + GLFW + PyOpenGL，因此当前演示程序是 Python。没有创建无法运行的 `CMakeLists.txt`，避免留下假入口。未来若引入 C++ 消费者，再按实际工具链补构建文件。

## 六、阶段 3 的扩展点

- 效果文件继续放 `src/`，按实际效果命名，不拆定义层/处理层。
- 需要纹理过滤时，先设计显式的采样器与纹理坐标接口，再迁移双三次函数。
- SPIR-V 从“模块探针”升级为“完整演示管线”时，把顶点/片元入口写成 Slang，并保留 GLSL 生成路径。
- 大气、云、水、阴影等效果迁移后，用同一测试世界的固定机位截图与旧实现比较，不能只看编译通过。
