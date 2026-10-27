# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`。

## 结论

- 参考函数共 505 个；算法函数 423 个。
- exact：423 个；approximate：0 个；mc_glue：82 个；missing：0 个。
- exact 覆盖率（按算法函数）：100.0%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 217 | 0 | 23 | 0 |
| Eclipse | 206 | 0 | 59 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |
| --- | --- | --- | --- | --- | --- |
| `main` | iterationT | mc_glue | `—` | — | 就绪：程序入口，只负责阶段组合 |
| `RSM` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?资源结构体 giview 没有定义 |
| `GI_SpatialFilter` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?资源结构体 giview 没有定义 |
| `title` | iterationT | mc_glue | `—` | — | 就绪：标题计数与屏幕文字，不参与画面效果 |
| `SampleDensity` | iterationT | mc_glue | `—` | — | 体积云密度要读三维噪声、卷曲噪声与媒体参数；参考签名只有云坐标、方向和是否细节，证据见 shaders/rendering/cloud/volumetric.glsl。 |
| `CloudLighting` | iterationT | mc_glue | `—` | — | 体积云光照要读三维基础/细节噪声、卷曲噪声、媒体参数与光照方向；参考签名缺少这些宿主资源，证据见 shaders/rendering/cloud/volumetric.glsl 与 omni-gfx/src/cloud_volume.slang。 |
| `BilinearHeightSample` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `HeightBasedNormal` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ParallaxOcclusionMapping` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `SevenSegment` | iterationT | mc_glue | `—` | — | 就绪：调试叠加字形表，只服务屏幕数字 |
| `DecimalPoint` | iterationT | mc_glue | `—` | — | 就绪：调试叠加小数点定位 |
| `PrintFloat` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试数字，不参与画面效果 |
| `PrintUintBinary` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试二进制，不参与画面效果 |
| `UnderwaterVolumetricFog` | iterationT | mc_glue | `—` | — | 水下体积雾要读深度、阴影贴图、噪声与水下介质参数；参考签名缺少这些缓冲，证据见 shaders/rendering/fog/underwater_fog.glsl 与 omni-gfx/src/fog_volume.slang。 |
| `VolumetricFog` | iterationT | mc_glue | `—` | — | 体积雾要读深度、阴影、噪声、相机与介质参数；参考签名缺少这些缓冲，证据见 shaders/rendering/fog/volumetric.glsl 与 omni-gfx/src/fog_volume.slang。 |
| `FidelityFX_FSR1` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ViewPos_From_ScreenPos_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ViewPos_From_ScreenPos_Raw_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ScreenPos_From_ViewPos_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ScreenPos_From_ViewPos_Raw_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `LinearDepth_From_ScreenDepth_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ScreenDepth_From_LinearDepth_DH` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ScreenDepth_From_DHScreenDepth` | iterationT | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `YearCycleColor` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `BiomeFogDensity` | Eclipse | mc_glue | `—` | — | 群系雾密度表来自 Eclipse 的群系枚举与 SC_* 设置；Omni 的群系雾选项在 effects/weather/weather.glsl 与 effects/world/nether.glsl，证据见这些文件的 OMNI_* 群系雾宏。 |
| `BiomeVLFogColors` | Eclipse | mc_glue | `—` | — | 就绪：原版群系枚举到颜色表，非算法 |
| `FogDensities` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `swapperlinZ2` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `SSRT_Handlight_Shadows` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetHandLight` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `calculateFlashlight` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetVolumetricFog` | Eclipse | mc_glue | `—` | — | Eclipse 末地体积雾读取宿主闪电、雾层与远景缓冲；Omni 的末地体积雾接口是 EndVortexFog/EndFogLayers，证据见 shaders/rendering/world/end_fog.glsl。 |
| `applySceneControllerParameters` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetVoxelBlock` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?samples [] != ['fetch']; constants extra 0 |
| `GetVoxelData` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetTexCoord` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `getVoxelEmission` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `voxelEmission` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `ComputeVoxelShadowMap` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `sortIntersectionCutout` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?param count 9 != 10; constants missing 0.5, 1 |
| `traceQuarterVoxel` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `voxelReflection` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `trace_wsr` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `raymarchWSR_LPV` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `raymarchWSRfog` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `WSRwaterVolumetrics` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `getPhotonicsEmission` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `photonicsEmission` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `photonicsReflectionShading` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `photonicsReflection` | Eclipse | mc_glue | `—` | — | Photonics 反射读取 Eclipse 的 photonics 光照表与阴影图；Omni 未接入 photonics 缓冲，默认反射走 SSR，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `specularReflections` | Eclipse | mc_glue | `—` | — | Eclipse 高光反射要读深度、法线、场景颜色、阴影与材质；参考签名有十七个参数但仍缺少缓冲，证据见 shaders/rendering/reflection/screenspace.glsl。 |
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
| `getCloudShape` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample |
| `getCumulonimbusShape` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `getLightningPosition` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetCloudShadow` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', ' |
| `getRayOrigin` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `phaseCloud` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `getCloudScattering` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `getCloudLighting` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `raymarchCloud` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetVolumetricClouds` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `raymarchCloudSimple` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `GetVolumetricCloudsSimple` | Eclipse | mc_glue | `—` | — | ??????????????? docs/gfx-functions-strict.md?没有同签名实现，旧承接表也没有给出可核对的目标 |
| `SetVoxelBlock` | Eclipse | mc_glue | `—` | — | 写 imgVoxelMask 图像，属于宿主图像存储；参考签名只给位置与编号，实际写入目标与体素缓冲布局由 Eclipse 程序提供，Omni 没有同名图像，证据见 omni-gfx/src/voxel.slang 的 ogxVoxelWriteIndex。 |
| `PopulateShadowVoxel` | Eclipse | mc_glue | `—` | — | 读取 renderStage、mc_Entity、entityId 等游戏渲染状态并写体素缓冲；这些是宿主状态，不能由参考的 float3 参数恢复，证据见 omni-gfx/src/voxel.slang 的 ogxPopulateShadowVoxelIndex 与 rendering/lpv.glsl。 |

## 判定口径

- exact：返回类型、参数类型/方向、采样次数与顺序一致；参考常数全部命中。
- 显式资源：参考签名是实现的参数前缀；尾部追加的纹理、矩阵、结构体或数值必须在台账声明、在函数体使用，纹理/矩阵类型要对得上。这样参考没带缓冲的算法仍能迁进通用库，而不是留在宿主胶水里。
- 宿主层允许实现多出常数：显式化的时间、湿度、屏幕尺寸等参数会带入新常数；通用库仍要求常数集合完全一致，除非台账写明理由。
- approximate：有承接实现，但签名、常数或采样存在差异。
- mc_glue：入口、标题、调试文字、群系表或默认配置未启用的宿主代码。
- missing：既无承接实现，也无宿主理由。

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
