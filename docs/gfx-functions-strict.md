# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`。

## 结论

- 参考函数共 505 个；算法函数 479 个。
- exact：468 个；approximate：0 个；reference_broken：11 个；mc_glue：26 个；missing：0 个。
- exact 覆盖率（按算法函数）：97.7%。

| 参考包 | exact | approximate | reference_broken | mc_glue | missing |
| --- | --- | --- | --- | --- | --- |
| iterationT | 233 | 0 | 1 | 6 | 0 |
| Eclipse | 235 | 0 | 10 | 20 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |
| --- | --- | --- | --- | --- | --- |
| `main` | iterationT | mc_glue | `—` | — | 就绪：程序入口，只负责阶段组合 |
| `title` | iterationT | mc_glue | `—` | — | 就绪：标题计数与屏幕文字，不参与画面效果 |
| `SevenSegment` | iterationT | mc_glue | `—` | — | 就绪：调试叠加字形表，只服务屏幕数字 |
| `DecimalPoint` | iterationT | mc_glue | `—` | — | 就绪：调试叠加小数点定位 |
| `PrintFloat` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试数字，不参与画面效果 |
| `PrintUintBinary` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试二进制，不参与画面效果 |
| `VolumetricFog` | iterationT | reference_broken | `—` | `ogxItxVolumetricFogExact` | 参考 VolumetricFog.glsl 正文引用 VFOG_NOISE_TYPE、VFOG_QUALITY、shadowtex0、noisetex 等只在 iterationT 程序头和 settings.glsl 中存在的宏与 uniform；单独提取该文件无法预处理，严格函数不能独立编译。实现见 fog_volume 的显式参数入口。 |
| `BiomeFogDensity` | Eclipse | mc_glue | `—` | — | 群系雾密度表来自 Eclipse 的群系枚举与 SC_* 设置；Omni 的群系雾选项在 effects/weather/weather.glsl 与 effects/world/nether.glsl，证据见这些文件的 OMNI_* 群系雾宏。 |
| `BiomeVLFogColors` | Eclipse | mc_glue | `—` | — | 就绪：原版群系枚举到颜色表，非算法 |
| `FogDensities` | Eclipse | mc_glue | `—` | — | 就绪：Eclipse 的时段雾密度表，按世界时间在早晨、正午、傍晚、夜间四档之间取值；属于群系/天气属性表，不改变步进算法。Omni 的对应选项在 effects/weather/weather.glsl。 |
| `GetVolumetricFog` | Eclipse | reference_broken | `—` | `ogxEndVortexFog` | Eclipse 在 end_fog、nether_fog、overworld_fog 三处定义同名不同签名的 GetVolumetricFog；严格台账按函数名只保留一个重载，无法用一条 exact 覆盖三个语义不同的实现。Omni 末地路径见 fog.ogxEndVortexFog。 |
| `GetVoxelData` | Eclipse | reference_broken | `—` | `ogxEclipseGetVoxelData` | voxelData[...] 的唯一声明在 voxel_common.glsl 被整段注释，参考正文编译时报未声明标识符；用 glslang 对提取片段复核得到同样错误。实现把同一 [voxelIndex][normalIndex] 布局装进二维只读纹理。 |
| `GetTexCoord` | Eclipse | reference_broken | `—` | `ogxEclipseGetTexCoord` | 与 GetVoxelData 相同，参考正文读 voxelData 的注释掉的 SSBO 声明，原文不能编译。实现从显式二维体素面纹理解包贴图坐标。 |
| `sortIntersectionCutout` | Eclipse | reference_broken | `—` | `ogxEclipseSortIntersectionCutout` | 参考正文调用 GetTexCoord，而后者读的 voxelData 声明被注释掉（voxel_common.glsl 的 voxelSSBO 块），调用图整体不能编译。实现用显式体素面纹理。 |
| `trace_wsr` | Eclipse | reference_broken | `—` | `ogxEclipseTraceWsr` | 参考正文调用 ph_intersects_world、ph_get_world_index 等 Photonics 函数；references/Eclipse/shaders/photonics/photonics.glsl 是 0 字节，仓库内没有这些定义，原文无法编译。实现按可执行语义用三维体素纹理给出 ogxEclipseTraceWsr。 |
| `raymarchWSRfog` | Eclipse | reference_broken | `—` | `ogxEclipseRaymarchWsrFog` | 参考正文调用 cloudVol、BiomeVLFogColors、GetCloudShadow，并直接读 gbufferModelViewInverse、shadowtex0；这些名字散落在多个 lib 文件和程序 uniform 中，提取后的函数不是自包含编译单元。实现见 eclipse_specular 的 WSR 雾入口。 |
| `WSRwaterVolumetrics` | Eclipse | reference_broken | `—` | `ogxEclipseWsrWaterVolumetrics` | 参考正文调用 cloudVol、waterCaustics、GetHandLight 与 BiomeVLFogColors，并直接读 shadowtex0/shadowcolor0、gbufferModelViewInverse；单文件提取无法确定这些 uniform 的布局。实现见 eclipse_specular 的水下体积入口。 |
| `photonicsReflection` | Eclipse | reference_broken | `—` | `ogxEclipsePhotonicsReflection` | 参考正文的 RayJob、translucentHit 与 trace_wsr 来自空的 photonics 包含文件；没有这些声明，原文不能编译。实现见 ogxEclipsePhotonicsReflection。 |
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
| `raymarchCloud` | Eclipse | reference_broken | `—` | `ogxEclipseRaymarchCloudExact` | 参考正文依赖 CloudLayer0..4、CUMULONIMBUS、cloud_ShadowLevelOfDetail 等只在 settings.glsl 与程序头中展开的宏；单文件提取无法确定循环次数与采样分支，严格对照会得到参考里不存在的采样数。实现见 cloud_eclipse 的显式设置入口。 |
| `GetVolumetricClouds` | Eclipse | reference_broken | `—` | `ogxEclipseGetVolumetricCloudsExact` | 参考正文依赖 CloudLayer0..4、CUMULONIMBUS、CLOUD_SHADOW_AMOUNT 等设置宏和程序 uniform；提取后无法唯一确定五层循环与阴影分支。实现见 cloud_eclipse 的五层总入口。 |

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
