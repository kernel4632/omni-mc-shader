# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`。

## 结论

- 参考函数共 505 个；算法函数 479 个。
- exact：474 个；approximate：0 个；reference_broken：5 个；mc_glue：26 个；missing：0 个。
- exact 覆盖率（按算法函数）：99.0%。

| 参考包 | exact | approximate | reference_broken | mc_glue | missing |
| --- | --- | --- | --- | --- | --- |
| iterationT | 234 | 0 | 0 | 6 | 0 |
| Eclipse | 240 | 0 | 5 | 20 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |
| --- | --- | --- | --- | --- | --- |
| `main` | iterationT | mc_glue | `—` | — | 就绪：程序入口，只负责阶段组合 |
| `title` | iterationT | mc_glue | `—` | — | 就绪：标题计数与屏幕文字，不参与画面效果 |
| `SevenSegment` | iterationT | mc_glue | `—` | — | 就绪：调试叠加字形表，只服务屏幕数字 |
| `DecimalPoint` | iterationT | mc_glue | `—` | — | 就绪：调试叠加小数点定位 |
| `PrintFloat` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试数字，不参与画面效果 |
| `PrintUintBinary` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试二进制，不参与画面效果 |
| `BiomeFogDensity` | Eclipse | mc_glue | `—` | — | 群系雾密度表来自 Eclipse 的群系枚举与 SC_* 设置；Omni 的群系雾选项在 effects/weather/weather.glsl 与 effects/world/nether.glsl，证据见这些文件的 OMNI_* 群系雾宏。 |
| `BiomeVLFogColors` | Eclipse | mc_glue | `—` | — | 就绪：原版群系枚举到颜色表，非算法 |
| `FogDensities` | Eclipse | mc_glue | `—` | — | 就绪：Eclipse 的时段雾密度表，按世界时间在早晨、正午、傍晚、夜间四档之间取值；属于群系/天气属性表，不改变步进算法。Omni 的对应选项在 effects/weather/weather.glsl。 |
| `GetVoxelData` | Eclipse | reference_broken | `—` | `ogxGetVoxelData` | voxelData 的唯一声明在上游 Eclipse-Shader@26cfc431a9066a87040272fa0ae016ab88c06b9d 的 lib/voxel_common.glsl:5-7、12-14 同样被注释，de987d9a 及更早版本没有声明；外层守卫里的 adjnjawudiuwad 从未定义。上游不可恢复，参考正文编译时报未声明标识符。实现把同一 [voxelIndex][normalIndex] 布局装进二维只读纹理。证据见 docs/eclipse-upstream.md。 |
| `GetTexCoord` | Eclipse | reference_broken | `—` | `ogxGetVoxelFaceTexCoord` | 与 GetVoxelData 同一原因：上游同提交的 voxel_common.glsl 中 voxelData 声明仍被注释，仓库从未提供启用版本。实现从显式二维体素面纹理解包贴图坐标。证据见 docs/eclipse-upstream.md。 |
| `sortIntersectionCutout` | Eclipse | reference_broken | `—` | `ogxSortIntersectionCutout` | 参考调用 GetTexCoord；上游同提交的 lib/voxel_common.glsl 第 5-7、12-14 行也把 voxelData 声明注释掉，更早的 de987d9a 版本没有该声明，GetVoxelData/GetTexCoord 外层还要求从未定义的 adjnjawudiuwad。上游没有可恢复定义，调用图不能编译。实现用显式体素面纹理。证据见 docs/eclipse-upstream.md。 |
| `trace_wsr` | Eclipse | reference_broken | `—` | `ogxWsrTrace` | 上游 Eclipse-Shader@26cfc431a9066a87040272fa0ae016ab88c06b9d 的 photonics/photonics.glsl 也是 0 字节（Git 空对象 e69de29b），唯一新增该文件的提交 dac7baa8 同样为空；ph_intersects_world、ph_get_world_index 等来自闭源 ARR 的 Photonics 模组，上游没有可恢复源码。实现按可执行语义用三维体素纹理给出 ogxWsrTrace。证据见 docs/eclipse-upstream.md。 |
| `photonicsReflection` | Eclipse | reference_broken | `—` | `ogxPhotonicsReflection` | 上游 Eclipse-Shader@26cfc431a9066a87040272fa0ae016ab88c06b9d 的 photonics.glsl 为 0 字节（Git 空对象 e69de29b），RayJob 与 translucentHit 字段由闭源 ARR 的 Photonics 模组注入，仓库内没有声明。实现见 ogxPhotonicsReflection。证据见 docs/eclipse-upstream.md。 |
| `beginText` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加的初始化 |
| `endText` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加的合成 |
| `printChar` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printUnsignedInt` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printInt` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printFloat` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printBool` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printVec2` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printVec3` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printVec4` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printIvec2` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printIvec3` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printIvec4` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printUvec2` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printUvec3` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printUvec4` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |
| `printLine` | Eclipse | mc_glue | `—` | — | 就绪：调试文字叠加 |

## 判定口径

- exact：返回类型、参数类型/方向、采样次数与顺序一致；参考常数全部命中。
- 显式资源：参考签名是实现的参数前缀；尾部追加的纹理、矩阵、结构体或数值必须在台账声明、在函数体使用，纹理/矩阵类型要对得上。这样参考没带缓冲的算法仍能迁进通用库，而不是留在宿主胶水里。
- 宿主层允许实现多出常数：显式化的时间、湿度、屏幕尺寸等参数会带入新常数；通用库仍要求常数集合完全一致，除非台账写明理由。
- approximate：有承接实现，但签名、常数或采样存在差异。
- reference_broken：参考正文依赖被注释掉的全局声明或缺失的包含文件，原文不能编译；实现按可执行语义迁移并记录编译证据，不能算 exact。
- mc_glue：入口、标题、调试文字、群系表或默认配置未启用的宿主代码。
- missing：既无承接实现，也无宿主理由。

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
