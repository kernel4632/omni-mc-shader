# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`。

## 结论

- 参考函数共 505 个；算法函数 373 个。
- exact：373 个；approximate：0 个；mc_glue：132 个；missing：0 个。
- exact 覆盖率（按算法函数）：100.0%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 204 | 0 | 36 | 0 |
| Eclipse | 169 | 0 | 96 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |
| --- | --- | --- | --- | --- | --- |
| `VariablePenumbraShadow` | iterationT | mc_glue | `—` | — | 可变半影阴影要读阴影贴图、深度图、投影矩阵、像素大小与蓝噪声；参考签名没有这些缓冲，证据见 shaders/rendering/shadow/shadow.glsl 与 omni-gfx/src/shadow.slang。 |
| `ScreenSpaceShadow` | iterationT | mc_glue | `—` | — | 屏幕空间阴影要读深度图、远景深度、投影矩阵与材质掩码；参考签名只给四个 float3，深度图与矩阵由宿主提供，证据见 shaders/rendering/shadow/screen_shadow.glsl 与 omni-gfx/src/shadow.slang。 |
| `TemporalReprojection` | iterationT | mc_glue | `—` | — | 时间重投影要读当前/历史颜色、历史深度与相机矩阵；参考签名只有坐标、速度和深度，历史纹理与矩阵由宿主提供，证据见 shaders/rendering/clarity/taa.glsl 的 TemporalReprojection。 |
| `SampleDepthDHFetch` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `SampleCurrDepthDHFetchClosest3x3` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `CalculateCameraVelocity` | iterationT | mc_glue | `—` | — | 相机速度要读十次主机深度、材质编号、前后帧投影与相机位移；参考签名只有 out float, float，无法从两个参数恢复这些缓冲，证据见 shaders/rendering/clarity/taa.glsl 的 TaaCameraVelocity 与 shaders/gfx/antialias.glsl。 |
| `main` | iterationT | mc_glue | `—` | — | 就绪：程序入口，只负责阶段组合 |
| `BloomDownSample` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `AxialGaussianBlur` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `CoCSpread` | iterationT | mc_glue | `—` | — | 弥散圆扩散要读景深统计图、深度图与相机焦距；参考签名没有这些缓冲，证据见 shaders/rendering/lens/dof.glsl 的 CoCSpread。 |
| `DepthOfField` | iterationT | mc_glue | `—` | — | 景深要读颜色、深度、统计图与相机焦距；参考签名为空，全部输入来自宿主缓冲，证据见 shaders/rendering/lens/dof.glsl 的 DepthOfField。 |
| `RSM` | iterationT | mc_glue | `—` | — | 反射阴影图要读四张阴影/法线/颜色缓冲与相机矩阵；参考签名只有两个 float3，缓冲由宿主提供，证据见 shaders/rendering/lighting/gi.glsl 与 omni-gfx/src/gi.slang。 |
| `GI_TemporalFilter` | iterationT | mc_glue | `—` | — | GI 时域滤波要读多张历史与当前 GI 缓冲、深度、法线与相机矩阵；参考签名为空，证据见 shaders/rendering/lighting/gi.glsl。 |
| `GI_SpatialFilter` | iterationT | mc_glue | `—` | — | GI 空域滤波要读 GI 缓冲、深度、法线与相机矩阵；参考签名只有三个参数，证据见 shaders/rendering/lighting/gi.glsl。 |
| `GroundTruthBasedAmbientOcclusion` | iterationT | mc_glue | `—` | — | GTAO 要读深度、法线、投影矩阵与蓝噪声；参考签名只有三个 float3，证据见 shaders/rendering/lighting/gtao.glsl 与 omni-gfx/src/gi.slang。 |
| `MotionBlur` | iterationT | mc_glue | `—` | — | 动态模糊要读当前/历史颜色、深度与相机速度缓冲；参考签名为空，证据见 shaders/rendering/lens/motion_blur.glsl。 |
| `title` | iterationT | mc_glue | `—` | — | 就绪：标题计数与屏幕文字，不参与画面效果 |
| `SampleDensity` | iterationT | mc_glue | `—` | — | 体积云密度要读三维噪声、卷曲噪声与媒体参数；参考签名只有云坐标、方向和是否细节，证据见 shaders/rendering/cloud/volumetric.glsl。 |
| `CloudLighting` | iterationT | mc_glue | `—` | — | 体积云光照要读三维基础/细节噪声、卷曲噪声、媒体参数与光照方向；参考签名缺少这些宿主资源，证据见 shaders/rendering/cloud/volumetric.glsl 与 omni-gfx/src/cloud_volume.slang。 |
| `BilinearHeightSample` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `HeightBasedNormal` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ParallaxOcclusionMapping` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `SevenSegment` | iterationT | mc_glue | `—` | — | 就绪：调试叠加字形表，只服务屏幕数字 |
| `DecimalPoint` | iterationT | mc_glue | `—` | — | 就绪：调试叠加小数点定位 |
| `PrintFloat` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试数字，不参与画面效果 |
| `PrintUintBinary` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试二进制，不参与画面效果 |
| `UnderwaterVolumetricFog` | iterationT | mc_glue | `—` | — | 水下体积雾要读深度、阴影贴图、噪声与水下介质参数；参考签名缺少这些缓冲，证据见 shaders/rendering/fog/underwater_fog.glsl 与 omni-gfx/src/fog_volume.slang。 |
| `VolumetricFog` | iterationT | mc_glue | `—` | — | 体积雾要读深度、阴影、噪声、相机与介质参数；参考签名缺少这些缓冲，证据见 shaders/rendering/fog/volumetric.glsl 与 omni-gfx/src/fog_volume.slang。 |
| `FidelityFX_FSR1` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ViewPos_From_ScreenPos_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ViewPos_From_ScreenPos_Raw_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenPos_From_ViewPos_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenPos_From_ViewPos_Raw_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `LinearDepth_From_ScreenDepth_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenDepth_From_LinearDepth_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenDepth_From_DHScreenDepth` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `YearCycleColor` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `BiomeFogDensity` | Eclipse | mc_glue | `—` | — | 群系雾密度表来自 Eclipse 的群系枚举与 SC_* 设置；Omni 的群系雾选项在 effects/weather/weather.glsl 与 effects/world/nether.glsl，证据见这些文件的 OMNI_* 群系雾宏。 |
| `BiomeVLFogColors` | Eclipse | mc_glue | `—` | — | 就绪：原版群系枚举到颜色表，非算法 |
| `FogDensities` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `swapperlinZ2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `SSRT_Handlight_Shadows` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetHandLight` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `calculateFlashlight` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `LightSourcePosition` | Eclipse | mc_glue | `—` | — | 读取 Eclipse 的 ManualLightPos、colortex4 随机偏移与闪电/涡旋切换；Omni 的末地涡旋雾没有每道闪电光源位置，证据见 shaders/rendering/world/end_fog.glsl。 |
| `LightSourceColors` | Eclipse | mc_glue | `—` | — | 颜色来自 Eclipse 的 VORTEX_LIGHT_COL_*、END_LIGHTNING_COL_* 与闪电闪光状态；Omni 的末地雾使用自己的雾色选项，证据见 shaders/effects/world/end.glsl。 |
| `LightSourceLighting` | Eclipse | mc_glue | `—` | — | 沿光方向对 eclipse 末地雾形状采样，依赖宿主的闪电位置与雾体积；Omni 的末地体积雾走 EndVortexFog，证据见 shaders/rendering/world/end_fog.glsl。 |
| `GetVolumetricFog` | Eclipse | mc_glue | `—` | — | Eclipse 末地体积雾读取宿主闪电、雾层与远景缓冲；Omni 的末地体积雾接口是 EndVortexFog/EndFogLayers，证据见 shaders/rendering/world/end_fog.glsl。 |
| `GetEndFogShadow` | Eclipse | mc_glue | `—` | — | Eclipse 末地雾影依赖宿主的闪电位置与多层雾采样；Omni 没有同名雾影缓冲，证据见 shaders/rendering/world/end_fog.glsl 与 docs/eclipse-parity.md。 |
| `applyGameplayEffects` | Eclipse | mc_glue | `—` | — | 读取玩家受伤、失明、黑暗等游戏状态并直接改最终颜色，属于宿主后处理；Omni 的对应效果在 shaders/rendering/lens/hurt.glsl，无法用参考的 3 个参数恢复。 |
| `BilateralUpscale_SSAO` | Eclipse | mc_glue | `—` | — | 双边升采样要读低分辨率 AO、深度、法线与屏幕尺寸；参考签名只给纹理、坐标与参考深度，证据见 shaders/rendering/lighting/gi.glsl。 |
| `rayTrace_GI` | Eclipse | mc_glue | `—` | — | GI 光线追踪要读深度、法线、场景颜色与相机矩阵；参考签名只有四个参数，证据见 shaders/rendering/lighting/gi.glsl 与 omni-gfx/src/eclipse_indirect.slang。 |
| `RT_alternate` | Eclipse | mc_glue | `—` | — | Eclipse 的 RT_alternate 读深度、法线、场景颜色、阴影与相机矩阵；参考签名没有这些缓冲，证据见 shaders/rendering/lighting/gi.glsl 与 omni-gfx/src/eclipse_indirect.slang。 |
| `ApplySSRT` | Eclipse | mc_glue | `—` | — | 屏幕空间反射合成要读场景颜色、深度、法线与反射缓冲；参考签名给九个参数，但真正的缓冲由宿主提供，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `Iris_Lightningflash` | Eclipse | mc_glue | `—` | — | 逐闪电位置由 Eclipse 的 lightningBoltPosition 缓冲提供；Omni 只有全局闪电闪光，没有每道闪电的位置缓冲，参考的 4 参数无法恢复该状态，证据见 shaders/rendering/weather/storm.glsl。 |
| `Iris_Lightningflash_VLcloud` | Eclipse | mc_glue | `—` | — | 同上，依赖 lightningBoltPosition 与 eclipse 闪电颜色；Omni 没有每道闪电位置缓冲，证据见 shaders/rendering/weather/storm.glsl。 |
| `Iris_Lightningflash_VLfog` | Eclipse | mc_glue | `—` | — | 同上，还依赖 lightningBoltPosition.w 的阶段标记；Omni 没有该缓冲，证据见 shaders/rendering/weather/storm.glsl。 |
| `SampleLpvLinear` | Eclipse | mc_glue | `—` | — | LPV 三线性取样读 Eclipse 的 texLpv1/texLpv2 三维缓冲；Omni 的 LPV 使用自己的 omniLpv* 缓冲，默认 OMNI_LPV_ENABLED=0，无法用参考签名参数化，证据见 rendering/lighting/lpv.glsl。 |
| `cloudVol` | Eclipse | mc_glue | `—` | — | cloudVol 在 Eclipse 的 nether_fog.glsl 与 overworld_fog.glsl 有两份同名同签名但常数不同的定义（120/-10 与 100/-15）；单个实现无法同时匹配，证据见 references/Eclipse/shaders/lib/nether_fog.glsl 与 overworld_fog.glsl。 |
| `calculate_maximum_horizon_angle` | Eclipse | mc_glue | `—` | — | 最大地平角要读深度、法线、投影矩阵与采样步骤；参考签名没有这些缓冲，证据见 shaders/rendering/lighting/gtao.glsl 与 omni-gfx/src/gi.slang。 |
| `ambient_occlusion` | Eclipse | mc_glue | `—` | — | Eclipse 的 ambient_occlusion 读深度、法线、投影与噪声缓冲；参考签名只有四个参数，证据见 shaders/rendering/lighting/gtao.glsl 与 omni-gfx/src/gi.slang。 |
| `calculateAtmosphere` | Eclipse | mc_glue | `—` | — | Eclipse 实时大气要读天空图、相机、太阳/月亮方向、行星常数与采样步骤；参考签名缺少这些宿主输入，证据见 shaders/rendering/sky/skyscatter.glsl 与 omni-gfx/src/eclipse_sky.slang。 |
| `applySceneControllerParameters` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `BiasShadowProjection` | Eclipse | mc_glue | `—` | — | Eclipse 阴影投影偏置读 d0/d1 推导的 a/b/k 与阴影矩阵；Omni 没有同名 d0/d1 投影，证据见 shaders/rendering/shadow/shadow.glsl 与 omni-gfx/src/shadow.slang。 |
| `calcDistort` | Eclipse | mc_glue | `—` | — | Eclipse 的 calcDistort 读 d0/d1 推导的 a/b/k；Omni 没有同名阴影投影参数，证据见 shaders/rendering/shadow/shadow.glsl。 |
| `GriAndEminShadowFix` | Eclipse | mc_glue | `—` | — | Eclipse 的阴影抖动修正读相机位置、水面状态与阴影过渡；Omni 的阴影走自己的抖动路径，证据见 shaders/rendering/shadow/shadow.glsl。 |
| `applyShadowBias` | Eclipse | mc_glue | `—` | — | Eclipse 的 applyShadowBias 读 customShadowMatrixSSBO 与 geoNormals；Omni 的阴影偏置走 ogxApplyShadowBias，证据见 shaders/rendering/shadow/shadow.glsl。 |
| `rayTraceSpeculars` | Eclipse | mc_glue | `—` | — | Eclipse 高光光线追踪要读深度、法线、场景颜色与阴影缓冲；参考签名没有这些缓冲，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `GetVoxelBlock` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `voxelIndex` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `voxelNormalIndex` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `decodeVec2_16` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVoxelData` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetTexCoord` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getVoxelEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `voxelEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `CleanVoxelSample` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ComputeVoxelShadowMap` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `planeIntersect` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `AABBintersection` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `AABBintersection2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `sortIntersectionCutout` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `sortIntersectionOpaque` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `fenceIntersection` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `fenceIntersection2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `traceQuarterVoxel` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `voxelReflection` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ComputePhotonicsShadowMap` | Eclipse | mc_glue | `—` | — | Photonics 阴影图依赖 Eclipse 的 photonics 图像与光照表；Omni 没有该缓冲，默认反射走 screenspace.glsl 的 SSR，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `trace_wsr` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `doBlockLightLightingVoxel` | Eclipse | mc_glue | `—` | — | Eclipse 体素光照版本读取体素反射/Photonics 缓冲；Omni 默认 OMNI_VOXEL_REFLECTION=0，体素缓冲不存在，证据见 shaders/rendering/reflection/voxel.glsl。 |
| `raymarchWSR_LPV` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchWSRfog` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `WSRwaterVolumetrics` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getPhotonicsEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsReflectionShading` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsReflection` | Eclipse | mc_glue | `—` | — | Photonics 反射读取 Eclipse 的 photonics 光照表与阴影图；Omni 未接入 photonics 缓冲，默认反射走 SSR，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `getEnvironmentReflections` | Eclipse | mc_glue | `—` | — | 环境反射要读天空盒、深度、法线与材质缓冲；参考签名没有这些缓冲，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `getReflectionVisibility` | Eclipse | mc_glue | `—` | — | 反射可见度要读深度与材质缓冲；参考签名只有两个 float，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `specularReflections` | Eclipse | mc_glue | `—` | — | Eclipse 高光反射要读深度、法线、场景颜色、阴影与材质；参考签名有十七个参数但仍缺少缓冲，证据见 shaders/rendering/reflection/screenspace.glsl。 |
| `beginText` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `endText` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printChar` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printUnsignedInt` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printInt` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printFloat` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printBool` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printVec2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printVec3` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printVec4` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printIvec2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printIvec3` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printIvec4` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printUvec2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printUvec3` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printUvec4` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `printLine` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getCloudShape` | Eclipse | mc_glue | `—` | — | Eclipse 的云层形状读取 LayerIndex 与整套 SC_* 层设置；Omni 的云管线使用 iterationT 云设置，默认 OMNI_VOLUMETRIC_CLOUDS 走体积云，证据见 shaders/rendering/cloud/volumetric.glsl。 |
| `getCumulonimbusShape` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getLightningPosition` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetCloudShadow` | Eclipse | mc_glue | `—` | — | Eclipse 的云影按云层密度解析积分；Omni 的云影使用云影贴图与云影模糊，证据见 shaders/rendering/cloud/shadow.glsl。 |
| `getRayOrigin` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `phaseCloud` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getCloudScattering` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getCloudLighting` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchCloud` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVolumetricClouds` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchCloudSimple` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVolumetricCloudsSimple` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVoxelIndex` | Eclipse | mc_glue | `—` | — | 体素索引依赖 Eclipse 的 relativeEyePosition、VoxelSize3 与阴影阶段写入的体素缓冲；Omni 默认 OMNI_VOXEL_REFLECTION=0，证据见 shaders/rendering/reflection/voxel.glsl 与 omni-gfx/src/voxel.slang。 |
| `SetVoxelBlock` | Eclipse | mc_glue | `—` | — | 写 imgVoxelMask 图像，属于宿主图像存储；参考签名只给位置与编号，实际写入目标与体素缓冲布局由 Eclipse 程序提供，Omni 没有同名图像，证据见 omni-gfx/src/voxel.slang 的 ogxVoxelWriteIndex。 |
| `PopulateShadowVoxel` | Eclipse | mc_glue | `—` | — | 读取 renderStage、mc_Entity、entityId 等游戏渲染状态并写体素缓冲；这些是宿主状态，不能由参考的 float3 参数恢复，证据见 omni-gfx/src/voxel.slang 的 ogxPopulateShadowVoxelIndex 与 rendering/lpv.glsl。 |

## 判定口径

- exact：返回类型、参数个数、参数类型/方向、采样次数与顺序一致；参考常数全部命中。
- 宿主层允许实现多出常数：显式化的时间、湿度、屏幕尺寸等参数会带入新常数；通用库仍要求常数集合完全一致。
- approximate：有承接实现，但签名、常数或采样存在差异。
- mc_glue：入口、标题、调试文字、群系表或默认配置未启用的宿主代码。
- missing：既无承接实现，也无宿主理由。

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
