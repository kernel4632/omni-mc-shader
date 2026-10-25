# 函数级覆盖对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py parity` 从源码生成，不要手工修改。
它回答一个问题：参考光影里的每个函数，在 `omni-gfx` 里由谁承接，或者为什么没有承接。

## 结论

- 参考函数共 505 个（同名跨包只算一次）：iterationT 240 个，Eclipse 265 个。
- 已迁入：294 个。
- MC 专用：154 个。
- 缺失：36 个。
- 调试输出：21 个。

| 参考包 | 已迁入 | MC 专用 | 缺失 | 调试输出 |
| --- | --- | --- | --- | --- |
| iterationT | 156 | 67 | 13 | 4 |
| Eclipse | 138 | 87 | 23 | 17 |

## 判定口径

- **已迁入**：`omni-gfx/src` 里存在承接同一算法的函数，表里写出 `模块.函数`。
- **MC 专用**：函数体直接读取 Minecraft 或 Iris 的缓冲、实体、选项、阶段变量；
  表里逐个列出命中的符号，符号名可以在参考源码里直接搜到。
- **缺失**：库里还没有对应实现，进入文末缺口清单。
- **调试输出**：只在屏幕上打印数字或文字，不参与任何画面效果，也不进入通用库。
- 名字相似但曲线不同的函数（例如 `ACES` 与 `ogxTonemapAcesFilm`）按实际算法判断，不按名字。

## 明细

### iterationT


`references/iterationT/shaders/Lib/BasicFounctions/Blocklight.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BlockLighting` | 3 | `surface.ogxBlockLight` | 已迁入 | 承接算法：方块光与材质 |
| `TextureLighting` | 28 | `surface.ogxBlockLight` | 已迁入 | 承接算法：方块光与材质 |
| `spotShape` | 77 | `surface.ogxSpotShape` | 已迁入 | 同名迁移：方块光与材质 |
| `TorchScreenSpaceShadow` | 88 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex`、`gbufferProjection` |
| `HeldLighting` | 162 | — | MC 专用 | 函数体直接读取宿主符号：`heldBlockLightValue` |
| `TorchSpecularHighlight` | 283 | — | MC 专用 | 函数体直接读取宿主符号：`heldBlockLightValue` |

`references/iterationT/shaders/Lib/BasicFounctions/NetherColor.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `NetherLighting` | 10 | `fog.ogxNetherBiomeLighting` | 已迁入 | 承接算法：雾与空气透视 |
| `NetherFogColor` | 19 | `fog.ogxNetherBiomeFogColor` | 已迁入 | 承接算法：雾与空气透视 |

`references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ClampRadius` | 40 | `atmosphere.ogxClampRadius` | 已迁入 | 承接算法：天空散射与日月星 |
| `SafeSqrt` | 44 | `atmosphere.ogxSafeSqrt` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderSunDisc` | 48 | `atmosphere.ogxSunDisc` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderMoonDisc` | 60 | `atmosphere.ogxMoonDiscReal` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderMoonDiscReflection` | 70 | `atmosphere.ogxMoonDiscReflection` | 已迁入 | 承接算法：天空散射与日月星 |
| `DistanceToTopAtmosphereBoundary` | 85 | `atmosphere.ogxAtmosphereDistanceToTop` | 已迁入 | 承接算法：天空散射与日月星 |
| `DistanceToBottomAtmosphereBoundary` | 93 | `atmosphere.ogxAtmosphereDistanceToGround` | 已迁入 | 承接算法：天空散射与日月星 |
| `RayIntersectsGround` | 101 | `atmosphere.ogxSphereRayIntersectsGround` | 已迁入 | 承接算法：天空散射与日月星 |
| `GetProfileDensityRayleighMie` | 114 | `atmosphere_model.ogxAtmoDensityRayleighMie` | 已迁入 | 承接算法：预计算大气查表 |
| `GetProfileDensityAbsorption` | 121 | `atmosphere_model.ogxAtmoDensityAbsorption` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTextureCoordFromUnitRange` | 135 | `atmosphere.ogxSubTextureCoord` | 已迁入 | 承接算法：天空散射与日月星 |
| `GetCombinedTextureCoordFromUnitRange` | 139 | `atmosphere_model.ogxAtmoCombinedTextureCoord` | 已迁入 | 承接算法：预计算大气查表 |
| `GetScatteringTextureUvwzFromRMuMuSNu` | 144 | `atmosphere_model.ogxAtmoScatteringUvwz` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceTextureUvFromRMu` | 188 | `atmosphere_model.ogxAtmoTransmittanceUv` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceToTopAtmosphereBoundary` | 205 | `atmosphere_model.ogxAtmoTransmittanceToTop` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittance` | 217 | `atmosphere_model.ogxAtmoTransmittance` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceToSun` | 239 | `atmosphere_model.ogxAtmoTransmittanceToSun` | 已迁入 | 承接算法：预计算大气查表 |
| `GetExtrapolatedSingleMieScattering` | 257 | `atmosphere_model.ogxAtmoExtrapolatedMie` | 已迁入 | 承接算法：预计算大气查表 |
| `GetCombinedScattering` | 268 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `GetIrradiance` | 300 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `GetSunAndSkyIrradiance` | 325 | `atmosphere_model.ogxAtmoSunSkyIrradiance` | 已迁入 | 承接算法：预计算大气查表 |
| `GetSkyRadiance` | 348 | — | MC 专用 | 函数体直接读取宿主符号：`wetness` |
| `GetSkyRadianceToPoint` | 428 | — | MC 专用 | 函数体直接读取宿主符号：`wetness` |

`references/iterationT/shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `VariablePenumbraShadow` | 3 | `shadow.ogxVariablePenumbraShadow` | 已迁入 | 同名迁移：阴影与半影 |
| `ScreenSpaceShadow` | 158 | `shadow.ogxScreenSpaceShadow` | 已迁入 | 同名迁移：阴影与半影 |
| `GetWavesNormalFromTex` | 238 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `CalculateWaterCaustics` | 257 | `water.ogxWaterCaustics` | 已迁入 | 承接算法：水面与海洋 |

`references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RGB_To_YCoCg` | 19 | `antialias.ogxRgbToYCoCg` | 已迁入 | 承接算法：时间抗锯齿 |
| `YCoCg_To_RGB` | 23 | `antialias.ogxYCoCgToRgb` | 已迁入 | 承接算法：时间抗锯齿 |
| `BicubicTexture` | 28 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `SampleCurrColor` | 57 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SampleCurrColorFetch` | 61 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SampleCurrColorBicubic` | 65 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SamplePrevColor` | 69 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SampleDepthFetch` | 77 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex` |
| `SampleCurrDepthFetchClosest3x3` | 81 | `antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevDepthFetch` | 95 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SamplePrevDepthMinMax3x3` | 99 | `antialias.ogxTaaPrevDepthMinmax` | 已迁入 | 承接算法：时间抗锯齿 |
| `GetVariance3x3` | 117 | `antialias.ogxTaaVariance3x3` | 已迁入 | 承接算法：时间抗锯齿 |
| `clipAABB` | 143 | `antialias.ogxClipAabb` | 已迁入 | 承接算法：时间抗锯齿 |
| `TemporalReprojection` | 169 | `antialias.ogxTaaReproject` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleDepthDHFetch` | 213 | `antialias.ogxTaaPrevDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrDepthDHFetchClosest3x3` | 217 | `antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `CalculateCameraVelocity` | 231 | `gi.ogxGiCameraVelocity` | 已迁入 | 承接算法：全局光与遮蔽 |
| `main` | 331 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/BasicFounctions/TAA_Nether.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BicubicTextureVec4` | 56 | `antialias.ogxBicubicTexture4` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurr` | 84 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SampleCurrFetch` | 91 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SampleCurrBicubic` | 98 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SamplePreviousDepthBilinear` | 105 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `SamplePrevious` | 119 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/BasicFounctions/TemporalNoise.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BlueNoise` | 3 | `sampling.ogxBlueNoise` | 已迁入 | 承接算法：采样与抖动 |
| `BlueNoiseTemproal` | 7 | `sampling.ogxBlueNoiseTemporal` | 已迁入 | 承接算法：采样与抖动 |
| `BayerTemproal` | 11 | `sampling.ogxBayerTemporal` | 已迁入 | 承接算法：采样与抖动 |

`references/iterationT/shaders/Lib/BasicFounctions/VanillaComposite.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `VanillaFog` | 3 | — | MC 专用 | 函数体直接读取宿主符号：`isEyeInWater`、`blindness` |
| `SelectionBox` | 14 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/GbufferData.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CurveBlockLightSky` | 3 | `surface.ogxCurveBlockLightSky` | 已迁入 | 承接算法：方块光与材质 |
| `CurveBlockLightTorch` | 11 | `surface.ogxCurveBlockLightTorch` | 已迁入 | 承接算法：方块光与材质 |
| `MaterialFromTex` | 70 | `surface.ogxPbrMaterialFromTex` | 已迁入 | 承接算法：方块光与材质 |
| `GetGbufferData` | 131 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `CalculateMasks` | 208 | — | MC 专用 | 函数体读取 gaux 缓冲与 mc_Entity 判定手部、粒子与半透明掩码 |
| `FixParticleMask` | 250 | — | MC 专用 | 按材质编号与实体编号修正粒子掩码，依赖 gaux 与 mc_Entity |
| `ApplyMaterial` | 275 | `surface.ogxMaterialNormal` | 已迁入 | 承接算法：方块光与材质 |

`references/iterationT/shaders/Lib/IndividualFounctions/AgX.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `unproject` | 13 | `atmosphere.ogxSkyUnproject` | 已迁入 | 承接算法：天空散射与日月星 |
| `primaries_to_matrix` | 24 | `color.ogxSaturationMatrix` | 已迁入 | 承接算法：颜色与色调映射 |
| `RotationToSlide` | 47 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `SlidePrimary` | 58 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `ComputeCompressionMatrix` | 62 | `color.ogxSaturationMatrix` | 已迁入 | 承接算法：颜色与色调映射 |
| `open_domain_to_normalized_log2` | 83 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `equation_scale` | 94 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `equation_full_curve` | 98 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgXConfigurable` | 116 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgXConfigurable1` | 148 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Bloom.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BloomDownSample` | 20 | `post.ogxBloomDownsample` | 已迁入 | 承接算法：后期与泛光 |
| `AxialGaussianBlur` | 41 | `post.ogxAxialGaussianBlur` | 已迁入 | 承接算法：后期与泛光 |
| `BicubicBlurTexture` | 64 | `math.ogxBicubicBlurTexture` | 已迁入 | 承接算法：数学与通用工具 |

`references/iterationT/shaders/Lib/IndividualFounctions/CloudShadow.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CloudShadowFromTex` | 28 | `cloud.ogxCloudShadowSample` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetSmoothCloudShadow` | 55 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`wetness` |

`references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateCoCRadius` | 3 | — | 缺失 | 按深度与焦距求弥散圆半径，库在 ogxCocRadius 里做了同类计算但接口不同 |
| `GetLinearDepth` | 7 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex` |
| `GetFocus` | 19 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `CoCSpread` | 29 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `DepthOfField` | 76 | `post.ogxDepthOfField` | 已迁入 | 同名迁移：后期与泛光 |

`references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateStars` | 12 | `atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |
| `H` | 48 | — | 缺失 | 参考实现 7 行，库里没有对应算法 |
| `ppss` | 57 | — | 缺失 | 参考实现 7 行，库里没有对应算法 |
| `Disc` | 67 | `atmosphere.ogxDiscProfile` | 已迁入 | 承接算法：天空散射与日月星 |
| `PlanetEnd2` | 72 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |
| `RotateMatrix` | 239 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `WarpSpace` | 255 | `math.ogxWarpSpace` | 已迁入 | 承接算法：数学与通用工具 |
| `Calculate3DNoise` | 269 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |
| `CalculateCloudFBM` | 279 | `fog.ogxCloudFbm` | 已迁入 | 承接算法：雾与空气透视 |
| `CalculateCloudFBM_LQ` | 297 | `noise.ogxFbm3` | 已迁入 | 承接算法：程序化噪声 |
| `pcurve` | 315 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `BlackHole_AccretionDisc_Stars` | 320 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `BlackHole_AccretionDisc_Reflection` | 429 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `EndFog` | 531 | `fog.ogxEndFogDensity` | 已迁入 | 承接算法：雾与空气透视 |

`references/iterationT/shaders/Lib/IndividualFounctions/FsrEASU.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `FsrEasuTap` | 3 | `upscale.ogxFsrEasuTap` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasuSet` | 17 | `upscale.ogxFsrEasuSet` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasu` | 33 | `upscale.ogxFsrEasu` | 已迁入 | 同名迁移：升采样与锐化 |

`references/iterationT/shaders/Lib/IndividualFounctions/GTAO.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GroundTruthBasedAmbientOcclusion` | 3 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex`、`gbufferProjection` |
| `GTAOMultiBounce` | 140 | `gi.ogxAoMultiBounce` | 已迁入 | 承接算法：全局光与遮蔽 |

`references/iterationT/shaders/Lib/IndividualFounctions/GlobalIllumination.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RSM` | 9 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`isEyeInWater`、`gbufferModelView`、`shadowModelView`、`shadowMapResolution` |
| `GI_TemporalFilter` | 188 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`isEyeInWater`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView` |
| `GI_SpatialFilter` | 325 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetDistOffset` | 10 | — | 缺失 | 镜头光斑的距离偏移，属于眩光光斑辅助函数 |
| `flare` | 22 | — | 缺失 | 镜头光斑的十字星芒，属于眩光辅助函数 |
| `orb` | 33 | — | 缺失 | 镜头光斑的圆盘形状，属于眩光辅助函数 |
| `ring` | 51 | — | 缺失 | 镜头光斑的圆环，属于眩光辅助函数 |
| `LensFlare` | 61 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |

`references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `MotionBlur` | 49 | `post.ogxMotionBlur` | 已迁入 | 同名迁移：后期与泛光 |
| `title` | 100 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`gbufferModelView` |
| `GetExposureTiles` | 167 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`viewWidth`、`viewHeight` |

`references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `HenyeyGreenstein` | 3 | `cloud.ogxHenyeyGreenstein` | 已迁入 | 承接算法：云形状、光照与云影 |
| `curveTop` | 10 | `cloud.ogxCloudTopCurve` | 已迁入 | 承接算法：云形状、光照与云影 |
| `SampleDensity` | 15 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`noisetex`、`wetness` |
| `SetCloudPos` | 64 | `cloud_volume.ogxCumulusSetPos` | 已迁入 | 承接算法：体积云步进 |
| `CloudLighting` | 73 | `cloud_volume.ogxCumulusLighting` | 已迁入 | 承接算法：体积云步进 |
| `NubisCumulus` | 108 | — | MC 专用 | 函数体直接读取宿主符号：`wetness`、`cameraPosition` |
| `CloudShadowTex` | 212 | `cloud.ogxCloudShadowSample` | 已迁入 | 承接算法：云形状、光照与云影 |

`references/iterationT/shaders/Lib/IndividualFounctions/Parallax.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BilinearHeightSample` | 7 | `parallax.ogxParallaxHeightBilinear` | 已迁入 | 承接算法：视差 |
| `HeightBasedNormal` | 39 | — | MC 专用 | 函数体直接读取宿主符号：`normals` |
| `ParallaxOcclusionMapping` | 80 | — | MC 专用 | 函数体直接读取宿主符号：`gaux`、`normals`、`atlasSize` |

`references/iterationT/shaders/Lib/IndividualFounctions/PhysicsOceans.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `physics_waveHeight` | 62 | `water.ogxOceanWaveHeight` | 已迁入 | 承接算法：水面与海洋 |
| `physics_waveDirection` | 91 | `water.ogxOceanWaveDirection` | 已迁入 | 承接算法：水面与海洋 |
| `physics_waveNormal` | 120 | `water.ogxOceanWaveNormal` | 已迁入 | 承接算法：水面与海洋 |
| `physics_wavePixel` | 148 | `water.ogxOceanPixel` | 已迁入 | 承接算法：水面与海洋 |

`references/iterationT/shaders/Lib/IndividualFounctions/PlanarClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BicubicBlurNoise` | 3 | `cloud.ogxBicubicBlurNoise` | 已迁入 | 承接算法：云形状、光照与云影 |
| `BilinearNoise` | 27 | `cloud.ogxBilinearNoise` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsDistortion` | 32 | `cloud.ogxPlanarDistortion` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsDensity` | 42 | `cloud.ogxPlanarDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsLightingDensity` | 74 | `cloud.ogxPlanarLightingDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
| `PlanarClouds` | 106 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter`、`wetness`、`cameraPosition` |

`references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `SevenSegment` | 48 | — | 调试输出 | 七段数码管形状的调试数字 |
| `DecimalPoint` | 93 | — | 调试输出 | 调试数字的小数点 |
| `PrintFloat` | 99 | — | 调试输出 | 只在屏幕上逐位打印浮点数（SevenSegment 拼数字），不参与任何画面效果 |
| `PrintUintBinary` | 218 | — | 调试输出 | 把整数按二进制画成方块，仅调试用 |

`references/iterationT/shaders/Lib/IndividualFounctions/Reflections/ReflectionFilter.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `AtrousWaveletFilter` | 3 | `reflection.ogxReflectionAtrousFilter` | 已迁入 | 承接算法：屏幕空间反射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Reflections/SSR.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ProjectSky` | 113 | `atmosphere.ogxSkyProject` | 已迁入 | 承接算法：天空散射与日月星 |
| `sampleGGXVNDF` | 139 | `reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `CalculateSpecularReflections` | 160 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/IndividualFounctions/Ripple.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Get3DNoise` | 3 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |
| `GetModulatedRainSpecular` | 14 | — | MC 专用 | 按雨强调制高光，读取 rainStrength 与涟漪贴图 |
| `GetRainAnimationTex` | 26 | — | MC 专用 | 读取游戏提供的涟漪动画贴图 |
| `GetRainNormal` | 33 | — | MC 专用 | 函数体直接读取宿主符号：`gaux`、`noisetex`、`frameTimeCounter`、`rainStrength` |

`references/iterationT/shaders/Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `UnderwaterVolumetricFog` | 39 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`gbufferModelView` |

`references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `PowderEffect` | 3 | `fog.ogxFogPowder` | 已迁入 | 承接算法：雾与空气透视 |
| `FogPhase` | 8 | `fog.ogxFogPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `MultiScatteringPhases` | 12 | `fog.ogxMultiScatteringPhases` | 已迁入 | 承接算法：雾与空气透视 |
| `FogDensity` | 34 | `fog.ogxFogDensity` | 已迁入 | 承接算法：雾与空气透视 |
| `VolumetricFog` | 69 | `fog_volume.ogxVolumetricFog` | 已迁入 | 同名迁移：体积雾 |
| `simpleScattering` | 275 | `atmosphere.ogxAtmosphereSky` | 已迁入 | 承接算法：天空散射与日月星 |
| `LandAtmosphericScattering` | 300 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`isEyeInWater`、`wetness`、`eyeBrightness`、`cameraPosition`、`gbufferModelView` |

`references/iterationT/shaders/Lib/IndividualFounctions/WaterWaves.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `textureSmooth` | 1 | `water.ogxTextureSmooth` | 已迁入 | 同名迁移：水面与海洋 |
| `AlmostIdentity` | 16 | `water.ogxAlmostIdentity` | 已迁入 | 承接算法：水面与海洋 |
| `GetWaves` | 31 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`frameTimeCounter` |
| `GetWavesNormal` | 79 | `water.ogxWavesNormal` | 已迁入 | 承接算法：水面与海洋 |
| `GetWaterParallaxCoord` | 94 | `water.ogxWaterParallax` | 已迁入 | 承接算法：水面与海洋 |

`references/iterationT/shaders/Lib/Programs/Final.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RRTAndODTFit` | 32 | `color.ogxRrtOdtFit` | 已迁入 | 承接算法：颜色与色调映射 |
| `ACES` | 38 | `color.ogxAces` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgxDefaultContrastApprox` | 55 | `color.ogxAgxContrast` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgX` | 59 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `None` | 80 | `color.ogxTonemapNone` | 已迁入 | 承接算法：颜色与色调映射 |
| `MergeBloom` | 84 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`biome`、`isEyeInWater`、`blindness`、`wetness`、`eyeBrightness` |
| `GetExposureValue` | 177 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`nightVision` |
| `Vignette` | 206 | `post.ogxVignette` | 已迁入 | 承接算法：后期与泛光 |
| `FidelityFX_CAS` | 272 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `FidelityFX_FSR1` | 380 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `BlackBar` | 472 | `color.ogxBlackBar` | 已迁入 | 承接算法：颜色与色调映射 |
| `Fxaa` | 481 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `DH_noise` | 32 | — | MC 专用 | 远景地形噪声，使用 DH 纹理坐标与投影约定 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Water_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `LinearDepth_From_ScreenDepth` | 39 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Entities_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `mat2_rotate_z` | 87 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `end_portal_layer` | 91 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Skytextured_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BilinearTexture` | 21 | — | 缺失 | 参考实现 10 行，库里没有对应算法 |
| `BilinearTextureSkybox` | 35 | — | 缺失 | 参考实现 14 行，库里没有对应算法 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `SampleAnisotropic` | 57 | — | MC 专用 | 函数体直接读取宿主符号：`normals`、`atlasSize` |

`references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ViewPos_From_ScreenPos` | 1 | `gi.ogxGiViewPos` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ViewPos_From_ScreenPos_Raw` | 10 | `gi.ogxGiViewPos` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ScreenPos_From_ViewPos` | 16 | `shadow.ogxShadowScreenPos` | 已迁入 | 承接算法：阴影与半影 |
| `ScreenPos_From_ViewPos_Raw` | 25 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `ScreenDepth_From_LinearDepth` | 35 | `post.ogxScreenDepthFromLinearDepth` | 已迁入 | 承接算法：后期与泛光 |
| `ViewPos_From_ScreenPos_DH` | 42 | `gi.ogxGiViewPosDh` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ViewPos_From_ScreenPos_Raw_DH` | 51 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_DH` | 57 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_Raw_DH` | 66 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `LinearDepth_From_ScreenDepth_DH` | 71 | `reflection.ogxReflectionDhToScreenDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `ScreenDepth_From_LinearDepth_DH` | 76 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenDepth_From_DHScreenDepth` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection`、`dhProjection` |

`references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ShadowScreenPos_From_WorldPos_Distorted` | 3 | `shadow.ogxShadowScreenPosDistorted` | 已迁入 | 承接算法：阴影与半影 |
| `ShadowScreenPos_From_WorldPos` | 14 | `shadow.ogxShadowScreenPos` | 已迁入 | 承接算法：阴影与半影 |
| `ShadowScreenPos_From_WorldPos_WithoutZScaling` | 21 | — | MC 专用 | 函数体直接读取宿主符号：`shadowModelView` |
| `DistortShadowScreenPos` | 28 | `shadow.ogxDistortShadowPos` | 已迁入 | 承接算法：阴影与半影 |

`references/iterationT/shaders/Lib/Utilities.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `minVec3` | 31 | `math.ogxMinVec3` | 已迁入 | 同名迁移：数学与通用工具 |
| `maxVec3` | 35 | `math.ogxMaxVec3` | 已迁入 | 同名迁移：数学与通用工具 |
| `remapSaturate` | 39 | `math.ogxRemapSaturate` | 已迁入 | 同名迁移：数学与通用工具 |
| `remap` | 43 | `math.ogxRemap` | 已迁入 | 同名迁移：数学与通用工具 |
| `atan2` | 60 | `math.ogxAtan2` | 已迁入 | 承接算法：数学与通用工具 |
| `facos` | 66 | `math.ogxFastAcos` | 已迁入 | 承接算法：数学与通用工具 |
| `LinearToGamma` | 74 | `math.ogxLinearToGamma` | 已迁入 | 承接算法：数学与通用工具 |
| `GammaToLinear` | 78 | `math.ogxGammaToLinear` | 已迁入 | 承接算法：数学与通用工具 |
| `LinearToCurve` | 82 | `math.ogxLinearToCurve` | 已迁入 | 同名迁移：数学与通用工具 |
| `CurveToLinear` | 86 | `math.ogxCurveToLinear` | 已迁入 | 承接算法：数学与通用工具 |
| `DoNightEye` | 101 | `math.ogxDoNightEye` | 已迁入 | 承接算法：数学与通用工具 |
| `Pack2x8` | 107 | `math.ogxPack2x8` | 已迁入 | 承接算法：数学与通用工具 |
| `Unpack2x8` | 112 | `math.ogxUnpack2x8` | 已迁入 | 承接算法：数学与通用工具 |
| `Pack2x16` | 117 | `math.ogxPack2x16` | 已迁入 | 承接算法：数学与通用工具 |
| `Unpack2x16` | 122 | `math.ogxUnpack2x16` | 已迁入 | 承接算法：数学与通用工具 |
| `DecodeNormalTex` | 128 | `math.ogxDecodeNormalTex` | 已迁入 | 承接算法：数学与通用工具 |
| `OctWrap` | 139 | `math.ogxOctWrap` | 已迁入 | 承接算法：数学与通用工具 |
| `EncodeNormal` | 143 | `math.ogxEncodeNormal` | 已迁入 | 承接算法：数学与通用工具 |
| `DecodeNormal` | 150 | `math.ogxDecodeNormal` | 已迁入 | 承接算法：数学与通用工具 |
| `D_Walter` | 158 | — | 缺失 | Walter 粗糙度重映射，库使用 GGX 的标准 alpha 定义 |
| `F_Schlick` | 164 | `math.ogxFresnelSchlick` | 已迁入 | 承接算法：数学与通用工具 |
| `V_Schlick` | 170 | `math.ogxVisibilitySchlick` | 已迁入 | 承接算法：数学与通用工具 |
| `Fd_Burley` | 176 | `math.ogxDiffuseBurley` | 已迁入 | 承接算法：数学与通用工具 |
| `SpecularGGX` | 190 | `math.ogxSpecularGGX` | 已迁入 | 承接算法：数学与通用工具 |
| `Blackbody` | 205 | `math.ogxBlackbody` | 已迁入 | 承接算法：数学与通用工具 |
| `RayPlaneIntersection` | 235 | `math.ogxRayPlaneIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `RaySphereIntersection` | 249 | `math.ogxRaySphereIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `RayleighPhaseFunction` | 265 | `math.ogxRayleighPhase` | 已迁入 | 承接算法：数学与通用工具 |
| `MiePhaseFunction` | 269 | `math.ogxMiePhase` | 已迁入 | 承接算法：数学与通用工具 |
| `InterleavedGradientNoise` | 276 | `math.ogxInterleavedGradientNoise` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer2` | 280 | `math.ogxBayer2` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer4` | 286 | `math.ogxBayer4` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer8` | 287 | `math.ogxBayer8` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer16` | 288 | — | 缺失 | 16×16 拜尔矩阵常数，库目前只到 8×8 与 64 级 |
| `bayer32` | 289 | — | 缺失 | 32×32 拜尔矩阵常数，库目前只到 8×8 与 64 级 |
| `bayer64` | 290 | `math.ogxBayer64` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer128` | 291 | — | 缺失 | 128×128 拜尔矩阵常数，库目前只到 8×8 与 64 级 |
| `Sequences_R1` | 294 | `math.ogxR2Sample` | 已迁入 | 承接算法：数学与通用工具 |
| `Sequences_R2` | 299 | `math.ogxR2Sample` | 已迁入 | 承接算法：数学与通用工具 |

### Eclipse


`references/Eclipse/shaders/lib/DistantHorizons_projections.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toScreenSpace_DH` | 21 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `toClipSpace3_DH` | 48 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `DH_shadowProjectionTweak` | 59 | — | MC 专用 | 远景阴影投影修正，依赖 dhProjection 与 dhFarPlane |

`references/Eclipse/shaders/lib/PhotonGTAO.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sqr` | 27 | `math.ogxSquare` | 已迁入 | 承接算法：数学与通用工具 |
| `cube` | 32 | `math.ogxSquare` | 已迁入 | 承接算法：数学与通用工具 |
| `max_of` | 34 | `math.ogxMaxVec3` | 已迁入 | 承接算法：数学与通用工具 |
| `min_of` | 37 | `math.ogxMinVec3` | 已迁入 | 承接算法：数学与通用工具 |
| `length_squared` | 41 | `math.ogxLengthSquared` | 已迁入 | 承接算法：数学与通用工具 |
| `normalize_safe` | 44 | `math.ogxNormalize` | 已迁入 | 承接算法：数学与通用工具 |
| `rcp_length` | 47 | `math.ogxSafeInvLength` | 已迁入 | 承接算法：数学与通用工具 |
| `fast_acos` | 50 | `math.ogxFastAcos` | 已迁入 | 承接算法：数学与通用工具 |
| `linear_step` | 65 | `math.ogxRemapSaturate` | 已迁入 | 承接算法：数学与通用工具 |
| `project` | 73 | — | MC 专用 | PhotonGTAO 的投影步骤，输入来自 photonics SSBO |
| `project_and_divide` | 76 | — | MC 专用 | PhotonGTAO 的投影与齐次除法，输入来自 photonics SSBO |
| `screen_to_view_space` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `view_to_screen_space` | 87 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `integrate_arc` | 104 | — | MC 专用 | PhotonGTAO 的弧面积分，读取 photonics 采样缓冲 |
| `calculate_maximum_horizon_angle` | 109 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex` |
| `ambient_occlusion` | 145 | `gi.ogxGroundTruthAo` | 已迁入 | 承接算法：全局光与遮蔽 |

`references/Eclipse/shaders/lib/ROBOBO_sky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sky_rayleighPhase` | 38 | `math.ogxRayleighPhase` | 已迁入 | 承接算法：数学与通用工具 |
| `sky_miePhase` | 43 | `math.ogxMiePhase` | 已迁入 | 承接算法：数学与通用工具 |
| `sky_phase` | 48 | `fog.ogxFogPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `sky_density` | 52 | `atmosphere.ogxExponentialDensity` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_airmass` | 61 | `atmosphere.ogxAtmosphereOpticalDepth` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_opticalDepth` | 82 | `atmosphere.ogxAtmosphereOpticalDepth` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_transmittance` | 89 | `atmosphere.ogxAtmosphereTransmittance` | 已迁入 | 承接算法：天空散射与日月星 |
| `calculateAtmosphere` | 95 | — | MC 专用 | 函数体直接读取宿主符号：`eyeAltitude`、`cameraPosition` |

`references/Eclipse/shaders/lib/Shadow_Params.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BiasShadowProjection` | 20 | `shadow.ogxApplyShadowBias` | 已迁入 | 承接算法：阴影与半影 |
| `calcDistort` | 27 | — | MC 专用 | 阴影投影的扭曲坐标，依赖 shadowProjection 与阴影贴图约定 |

`references/Eclipse/shaders/lib/Shadows.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GriAndEminShadowFix` | 4 | `shadow.ogxGriAndEminShadowFix` | 已迁入 | 同名迁移：阴影与半影 |
| `applyShadowBias` | 16 | `shadow.ogxApplyShadowBias` | 已迁入 | 承接算法：阴影与半影 |

`references/Eclipse/shaders/lib/aurora.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash_aurora` | 28 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `mm2` | 36 | `math.ogxRotate2` | 已迁入 | 承接算法：数学与通用工具 |
| `tri` | 43 | `math.ogxTriangleWave` | 已迁入 | 承接算法：数学与通用工具 |
| `tri2` | 47 | `math.ogxTriangleWave` | 已迁入 | 承接算法：数学与通用工具 |
| `triNoise2d` | 53 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `aurora` | 77 | `atmosphere.ogxAurora` | 已迁入 | 承接算法：天空散射与日月星 |

`references/Eclipse/shaders/lib/bayer_matrix.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `bayerDither` | 1 | `math.ogxBayer8` | 已迁入 | 承接算法：数学与通用工具 |

`references/Eclipse/shaders/lib/bokeh.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rotate` | 472 | `math.ogxRotate2` | 已迁入 | 承接算法：数学与通用工具 |

`references/Eclipse/shaders/lib/climate_settings.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `YearCycleColor` | 19 | `weather.ogxYearCycleColor` | 已迁入 | 同名迁移：天气与季节 |
| `BiomeFogDensity` | 135 | `fog.ogxBiomeFogDensity` | 已迁入 | 同名迁移：雾与空气透视 |
| `BiomeVLFogColors` | 151 | — | MC 专用 | 函数体直接读取宿主符号：`biome` |
| `FogDensities` | 173 | `weather.ogxFogDensities` | 已迁入 | 同名迁移：天气与季节 |

`references/Eclipse/shaders/lib/color_dither.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `nrand` | 2 | `noise.ogxWhiteNoise` | 已迁入 | 承接算法：程序化噪声 |
| `triangWhiteNoise` | 7 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `fp10Dither` | 19 | — | 缺失 | 十位浮点的量化抖动，库的 ogxDitherFloat 覆盖八位与十六位 |
| `fp16Dither` | 26 | — | 缺失 | 十六位浮点的量化抖动，库的 ogxDitherFixed 覆盖八位 |
| `int8Dither` | 33 | — | 缺失 | 八位整数的量化抖动辅助 |
| `int10Dither` | 38 | — | 缺失 | 十位整数的量化抖动辅助 |
| `int16Dither` | 43 | — | 缺失 | 十六位整数的量化抖动辅助 |

`references/Eclipse/shaders/lib/color_transforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toLinear` | 2 | `math.ogxGammaToLinear` | 已迁入 | 承接算法：数学与通用工具 |
| `luma` | 6 | `math.ogxLuminance` | 已迁入 | 承接算法：数学与通用工具 |
| `LinearTosRGB` | 22 | `color.ogxLinearToSrgb` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_Hejl2015` | 34 | `color.ogxTonemapHejl` | 已迁入 | 承接算法：颜色与色调映射 |
| `HableTonemap` | 41 | `color.ogxTonemapHable` | 已迁入 | 承接算法：颜色与色调映射 |
| `reinhard` | 66 | `color.ogxTonemapReinhard` | 已迁入 | 承接算法：颜色与色调映射 |
| `ACESFilm` | 70 | `color.ogxTonemapAcesFilm` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Lottes` | 88 | `color.ogxTonemapLottes` | 已迁入 | 承接算法：颜色与色调映射 |
| `curve` | 106 | `color.ogxAgxContrast` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Uchimura_Modified` | 109 | `color.ogxTonemapUchimura` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Uchimura` | 132 | `color.ogxTonemapUchimura` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Xonk` | 166 | — | 缺失 | Xonk 曲线是一条独立拟合，库里没有同一条曲线 |
| `Tonemap_Full_Reinhard` | 174 | `color.ogxTonemapReinhard` | 已迁入 | 承接算法：颜色与色调映射 |
| `Full_Reinhard_Edit` | 182 | `color.ogxTonemapReinhard` | 已迁入 | 承接算法：颜色与色调映射 |
| `agxDefaultContrastApprox` | 228 | `color.ogxAgxContrast` | 已迁入 | 承接算法：颜色与色调映射 |
| `agxLook` | 241 | `color.ogxAdvancedColor` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX` | 255 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX_minimal` | 297 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX_minimal_merlin` | 337 | `color.ogxAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `reinhard_jodie` | 386 | `color.ogxTonemapReinhard` | 已迁入 | 承接算法：颜色与色调映射 |
| `no_tonemapper` | 400 | `color.ogxTonemapNone` | 已迁入 | 承接算法：颜色与色调映射 |

`references/Eclipse/shaders/lib/diffuse_lighting.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `swapperlinZ2` | 2 | — | MC 专用 | 交换两个线性深度的辅助函数，输入来自宿主深度缓冲 |
| `SSRT_Handlight_Shadows` | 6 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex`、`normals`、`gbufferModelView` |
| `GetHandLight` | 74 | — | MC 专用 | 函数体直接读取宿主符号：`lightColor` |
| `doBlockLightLighting` | 104 | — | MC 专用 | 函数体直接读取宿主符号：`normals`、`heldItemId`、`lightColor` |
| `doIndirectLighting` | 282 | `surface.ogxDoIndirectLighting` | 已迁入 | 同名迁移：方块光与材质 |
| `calculateFlashlight` | 304 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousModelView` |

`references/Eclipse/shaders/lib/end_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash31` | 23 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `hash11` | 30 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `iqint2` | 45 | — | 缺失 | 整数二维坐标的快速取整，属于末地雾的噪声辅助 |
| `hash` | 56 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `LightSourcePosition` | 69 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `densityAtPosFog` | 95 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |
| `SwirlAroundOrigin` | 110 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `VolumeBounds` | 122 | — | MC 专用 | 末地雾体积边界，依赖末地主岛坐标与群系状态 |
| `fogShape` | 144 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `endFogPhase` | 169 | `fog.ogxEndVortexLightPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `LightSourceColors` | 182 | — | MC 专用 | 末地雾的方块光源配色，依赖方块光照与群系表 |
| `LightSourceLighting` | 198 | — | MC 专用 | 函数体直接读取宿主符号：`lightColor` |
| `phaseEND` | 215 | `fog.ogxEndVortexLightPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `GetVolumetricFog` | 219 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`lightColor`、`cameraPosition`、`gbufferModelView` |
| `GetEndFogShadow` | 321 | — | MC 专用 | 末地雾的遮挡，采样宿主的阴影与末地主岛数据 |

`references/Eclipse/shaders/lib/gameplay_effects.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `applyGameplayEffects` | 37 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`noisetex`、`isEyeInWater`、`frameTimeCounter` |

`references/Eclipse/shaders/lib/hsv.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RgbToHsv` | 1 | `math.ogxRgbToHsv` | 已迁入 | 承接算法：数学与通用工具 |
| `HsvToRgb` | 12 | `color.ogxHsvToRgb` | 已迁入 | 承接算法：颜色与色调映射 |

`references/Eclipse/shaders/lib/indirect_lighting_effects.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `R2_samples` | 1 | — | 缺失 | 参考实现 4 行，库里没有对应算法 |
| `cosineHemisphereSample` | 6 | `math.ogxCosineHemisphere` | 已迁入 | 承接算法：数学与通用工具 |
| `TangentToWorld` | 16 | `math.ogxTangentBasis` | 已迁入 | 承接算法：数学与通用工具 |
| `SpiralSample` | 23 | `math.ogxSpiralSample` | 已迁入 | 承接算法：数学与通用工具 |
| `BilateralUpscale_SSAO` | 43 | — | 缺失 | 半分辨率遮蔽的双边上采样，库里用时间抗锯齿阶段的四邻域加权替代，尚未独立成函数 |
| `rayTrace_GI` | 99 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `convertHandDepth_3` | 145 | `math.ogxConvertHandDepth3` | 已迁入 | 承接算法：数学与通用工具 |
| `RT_alternate` | 153 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`gbufferModelView`、`viewWidth`、`viewHeight` |
| `ApplySSRT` | 219 | `reflection.ogxReflectionSceneColor` | 已迁入 | 承接算法：屏幕空间反射 |

`references/Eclipse/shaders/lib/lightning_stuff.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Iris_Lightningflash` | 8 | `fog_volume.ogxFogLightning` | 已迁入 | 承接算法：体积雾 |
| `Iris_Lightningflash_VLcloud` | 31 | `cloud_volume.ogxCumulusLightning` | 已迁入 | 承接算法：体积云步进 |
| `Iris_Lightningflash_VLfog` | 44 | `fog_volume.ogxFogLightning` | 已迁入 | 承接算法：体积雾 |

`references/Eclipse/shaders/lib/lpv_common.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetLpvPosition` | 12 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |

`references/Eclipse/shaders/lib/lpv_render.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `lpvCurve` | 5 | `lpv.ogxLpvCurve` | 已迁入 | 同名迁移：光传播体积 |
| `SampleLpvLinear` | 13 | — | MC 专用 | 函数体直接读取宿主符号：`frameCounter` |
| `GetLpvBlockLight` | 29 | `lpv.ogxLpvBlockLight` | 已迁入 | 承接算法：光传播体积 |
| `GetLpvSkyLight` | 33 | `lpv.ogxLpvSkyLight` | 已迁入 | 承接算法：光传播体积 |

`references/Eclipse/shaders/lib/nether_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `cloudVol` | 15 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`frameTimeCounter` |

`references/Eclipse/shaders/lib/overworld_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `phaseRayleigh` | 54 | `math.ogxRayleighPhase` | 已迁入 | 承接算法：数学与通用工具 |
| `fogPhase` | 59 | `fog.ogxFogPhase` | 已迁入 | 同名迁移：雾与空气透视 |

`references/Eclipse/shaders/lib/projections.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toClipSpace3` | 14 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `toScreenSpace` | 18 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `toScreenSpaceVector` | 25 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `toWorldSpace` | 32 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferModelView` |
| `toWorldSpaceCamera` | 37 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition`、`gbufferModelView` |
| `toShadowSpace` | 42 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferModelView`、`shadowModelView` |
| `toShadowSpaceProjected` | 52 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferModelView`、`shadowModelView` |

`references/Eclipse/shaders/lib/ripples.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash12` | 19 | `noise.ogxHash12` | 已迁入 | 同名迁移：程序化噪声 |
| `hash22` | 26 | `noise.ogxHash22` | 已迁入 | 同名迁移：程序化噪声 |
| `ripples` | 34 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |

`references/Eclipse/shaders/lib/scene_controller.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `applySceneControllerParameters` | 147 | — | MC 专用 | 把场景控制器的选项写入全局，读取天光与天气等宿主状态 |

`references/Eclipse/shaders/lib/sky_gradient.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `drawSun` | 3 | `atmosphere.ogxSunDisc` | 已迁入 | 承接算法：天空散射与日月星 |
| `sphereMap` | 10 | `atmosphere.ogxSkyProject` | 已迁入 | 承接算法：天空散射与日月星 |
| `drawMoon` | 27 | `atmosphere.ogxMoonDiscDefault` | 已迁入 | 承接算法：天空散射与日月星 |
| `drawRealMoon` | 58 | `atmosphere.ogxMoonDiscReal` | 已迁入 | 承接算法：天空散射与日月星 |
| `w0` | 69 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `w1` | 74 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `w2` | 79 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `w3` | 84 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `g0` | 89 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `g1` | 94 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `h0` | 99 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `h1` | 104 | — | 缺失 | 参考实现 3 行，库里没有对应算法 |
| `texture_bicubic` | 109 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `texture_bicubic_offset` | 133 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `sphereToCarte` | 166 | `atmosphere.ogxSkyUnproject` | 已迁入 | 承接算法：天空散射与日月星 |
| `skyFromTex` | 171 | `atmosphere_model.ogxAtmoSkyRadiance` | 已迁入 | 承接算法：预计算大气查表 |
| `skyCloudsFromTex` | 186 | — | 缺失 | 读取天空贴图并合成云，需要采样器；库按架构约定不绑定采样器 |
| `skyCloudsFromTexBLUR` | 195 | — | 缺失 | 天空贴图的模糊采样，需要采样器；库不绑定采样器 |
| `skyCloudsFromTexLOD` | 210 | — | 缺失 | 按距离选择天空贴图层级，需要采样器；库不绑定采样器 |
| `volumetricsFromTex` | 229 | `fog_volume.ogxFogCloudBicubic` | 已迁入 | 承接算法：体积雾 |

`references/Eclipse/shaders/lib/specular.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `invLinZ` | 1 | `reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `DH_invLinZ` | 5 | `reflection.ogxReflectionDhToScreenDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `linZ` | 9 | `reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `linZ2` | 13 | `reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `frisvad` | 17 | `math.ogxTangentBasis` | 已迁入 | 承接算法：数学与通用工具 |
| `CoordBase` | 29 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `R2_Sample` | 35 | `math.ogxR2Sample` | 已迁入 | 承接算法：数学与通用工具 |
| `fma2` | 40 | `math.ogxFma2` | 已迁入 | 承接算法：数学与通用工具 |
| `SampleVNDFGGX` | 44 | `reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `GGX` | 75 | `math.ogxDistributionGGX` | 已迁入 | 承接算法：数学与通用工具 |
| `shlickFresnelRoughness` | 95 | `math.ogxFresnelSchlick` | 已迁入 | 承接算法：数学与通用工具 |
| `invertLinearizeDepthFast` | 108 | — | MC 专用 | 按 Iris 的深度约定反解线性深度，使用 gbufferProjectionInverse |
| `rayTraceSpeculars` | 113 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `toScreenSpace2` | 248 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `GetVoxelBlock` | 262 | — | MC 专用 | 按坐标读取体素方块编号，依赖 Iris 自定义图像 |
| `voxelIndex` | 266 | `voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `voxelNormalIndex` | 270 | — | MC 专用 | 体素法线索引，依赖方块面表与影像编码 |
| `decodeVec2_16` | 274 | — | 缺失 | 把十六位打包值拆成二维法线，库用八位版本 ogxUnpack2x8 |
| `GetVoxelData` | 280 | — | MC 专用 | 读体素影像数据，依赖自定义图像布局 |
| `GetTexCoord` | 290 | — | MC 专用 | 体素影像的纹理坐标换算，依赖自定义图像布局 |
| `getVoxelEmission` | 294 | — | MC 专用 | 从体素影像读取发光，依赖自定义图像与方块映射 |
| `voxelEmission` | 300 | — | MC 专用 | 体素发光编码，依赖方块表 |
| `CleanVoxelSample` | 308 | — | MC 专用 | 清洗体素采样，依赖自定义图像与材质掩码 |
| `ComputeVoxelShadowMap` | 331 | `voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `planeIntersect` | 441 | `math.ogxRayPlaneIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `AABBintersection` | 459 | `math.ogxRayBoxIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `AABBintersection2` | 488 | `math.ogxRayBoxRange` | 已迁入 | 承接算法：数学与通用工具 |
| `sortIntersectionCutout` | 514 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
| `sortIntersectionOpaque` | 540 | — | MC 专用 | 按深度排序不透明交点，依赖体素影像布局 |
| `fenceIntersection` | 552 | — | MC 专用 | 栅栏网格求交，读取体素方块编号 |
| `fenceIntersection2` | 561 | — | MC 专用 | 栅栏网格求交的第二种写法，读取体素方块编号 |
| `traceQuarterVoxel` | 578 | `voxel.ogxVoxelReflection` | 已迁入 | 承接算法：体素反射 |
| `voxelReflection` | 616 | `voxel.ogxVoxelReflection` | 已迁入 | 同名迁移：体素反射 |
| `CleanPhotonicsSample` | 1079 | — | MC 专用 | 读取 photonics 缓冲的采样清洗，依赖 SSBO 布局 |
| `ComputePhotonicsShadowMap` | 1102 | — | MC 专用 | 写入 photonics 阴影贴图，需要 Iris SSBO 与图像写入权限 |
| `trace_wsr` | 1222 | — | MC 专用 | 加权水面追踪主循环，读取体素影像与位置缓冲，依赖 Iris 自定义图像 |
| `doBlockLightLightingVoxel` | 1404 | — | MC 专用 | 函数体直接读取宿主符号：`heldItemId`、`lightColor` |
| `raymarchWSR_LPV` | 1464 | — | MC 专用 | 函数体直接读取宿主符号：`heldItemId`、`cameraPosition`、`gbufferModelView` |
| `raymarchWSRfog` | 1604 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`biome`、`eyeBrightness`、`cameraPosition`、`gbufferModelView`、`shadowModelView` |
| `WSRwaterVolumetrics` | 1798 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`heldItemId`、`cameraPosition`、`gbufferModelView`、`shadowModelView` |
| `getPhotonicsEmission` | 1923 | — | MC 专用 | 从 photonics 缓冲读取发光数据，依赖 SSBO 布局 |
| `photonicsEmission` | 1929 | — | MC 专用 | 同上，photonics 缓冲读出 |
| `photonicsReflectionShading` | 1937 | — | MC 专用 | 函数体直接读取宿主符号：`eyeBrightness`、`cameraPosition` |
| `photonicsReflection` | 2011 | — | MC 专用 | 函数体直接读取宿主符号：`isEyeInWater`、`nightVision`、`cameraPosition` |
| `getEnvironmentReflections` | 2131 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`isEyeInWater`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousProjection`、`gbufferPreviousModelView` |
| `getReflectionVisibility` | 2235 | — | MC 专用 | 读取阴影与深度缓冲判断反射可见度，依赖 shadowtex/depthtex |
| `specularReflections` | 2283 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`heldItemId`、`isEyeInWater`、`lightColor`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView` |

`references/Eclipse/shaders/lib/stars.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash13` | 5 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `NoisyStarField` | 13 | `atmosphere.ogxStarNoisyField` | 已迁入 | 承接算法：天空散射与日月星 |
| `StableStarField` | 22 | `atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |
| `hash12_alt` | 46 | `noise.ogxHash12` | 已迁入 | 承接算法：程序化噪声 |
| `starTemp` | 48 | `atmosphere.ogxStarTemperature` | 已迁入 | 承接算法：天空散射与日月星 |
| `starplane` | 52 | `atmosphere.ogxStarPlane` | 已迁入 | 同名迁移：天空散射与日月星 |
| `starbox` | 82 | `atmosphere.ogxStarBox` | 已迁入 | 同名迁移：天空散射与日月星 |
| `stars` | 93 | `atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |

`references/Eclipse/shaders/lib/texFiltering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `smoothfilter` | 1 | `sampling.ogxSmoothFilter` | 已迁入 | 同名迁移：采样与抖动 |
| `shadowsmoothfilter` | 11 | `sampling.ogxShadowSmoothFilter` | 已迁入 | 同名迁移：采样与抖动 |

`references/Eclipse/shaders/lib/text_rendering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `beginText` | 161 | — | 调试输出 | 文字渲染的起始状态，依赖游戏字体与屏幕叠加 |
| `endText` | 175 | — | 调试输出 | 文字渲染的结束状态，依赖游戏字体与屏幕叠加 |
| `printChar` | 179 | — | 调试输出 | 依赖游戏字体贴图的字符打印，属于宿主资源 |
| `printUnsignedInt` | 212 | — | 调试输出 | 调试文字打印 |
| `printInt` | 244 | — | 调试输出 | 调试文字打印 |
| `printFloat` | 249 | — | 调试输出 | 调试文字打印 |
| `printBool` | 269 | — | 调试输出 | 调试文字打印 |
| `printVec2` | 277 | — | 调试输出 | 调试文字打印 |
| `printVec3` | 282 | — | 调试输出 | 调试文字打印 |
| `printVec4` | 289 | — | 调试输出 | 调试文字打印 |
| `printIvec2` | 299 | — | 调试输出 | 调试文字打印 |
| `printIvec3` | 304 | — | 调试输出 | 调试文字打印 |
| `printIvec4` | 311 | — | 调试输出 | 调试文字打印 |
| `printUvec2` | 321 | — | 调试输出 | 调试文字打印 |
| `printUvec3` | 326 | — | 调试输出 | 调试文字打印 |
| `printUvec4` | 333 | — | 调试输出 | 调试文字打印 |
| `printLine` | 343 | — | 调试输出 | 调试文字打印 |

`references/Eclipse/shaders/lib/texture_filtering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sampleNearest` | 3 | `sampling.ogxSampleNearest` | 已迁入 | 同名迁移：采样与抖动 |
| `sampleRGSS` | 25 | `sampling.ogxRgssSample` | 已迁入 | 承接算法：采样与抖动 |

`references/Eclipse/shaders/lib/util.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sincos` | 49 | `math.ogxSinCos` | 已迁入 | 承接算法：数学与通用工具 |
| `circlemap` | 53 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `circlemapL` | 57 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `calculateRoughSpecular` | 61 | — | MC 专用 | 粗糙高光，读取 gaux 材质与阴影贴图 |
| `clampNormal` | 72 | `math.ogxNormalize` | 已迁入 | 承接算法：数学与通用工具 |
| `srgbToLinear` | 77 | `color.ogxSrgbToLinear` | 已迁入 | 同名迁移：颜色与色调映射 |
| `linearToSRGB` | 85 | `color.ogxLinearToSrgb` | 已迁入 | 同名迁移：颜色与色调映射 |
| `blackbody` | 95 | `math.ogxBlackbody` | 已迁入 | 承接算法：数学与通用工具 |
| `calculateHardShadows` | 111 | — | MC 专用 | 硬阴影比较，直接采样 shadowtex |
| `genUnitVector` | 117 | `math.ogxCosineHemisphere` | 已迁入 | 承接算法：数学与通用工具 |
| `cartToSphere` | 127 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `sphereToCart` | 134 | `atmosphere.ogxSkyUnproject` | 已迁入 | 承接算法：天空散射与日月星 |
| `getRotMat` | 139 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `rsi` | 162 | — | 缺失 | 球面坐标变换的快捷实现，库用 ogxCircleMap 与 ogxSkyProject 覆盖 |
| `HaltonSeq3` | 172 | `sampling.ogxHalton3` | 已迁入 | 承接算法：采样与抖动 |
| `HaltonSeq2` | 185 | `sampling.ogxHalton2` | 已迁入 | 承接算法：采样与抖动 |
| `customRotation` | 199 | — | MC 专用 | 函数体直接读取宿主符号：`worldTime` |

`references/Eclipse/shaders/lib/volumetricClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rand` | 49 | `noise.ogxWhiteNoise` | 已迁入 | 承接算法：程序化噪声 |
| `getRainDensity` | 55 | — | MC 专用 | 函数体直接读取宿主符号：`rainStrength` |
| `densityAtPos` | 62 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |
| `hash2` | 79 | `noise.ogxHash22` | 已迁入 | 承接算法：程序化噪声 |
| `normalize_hash` | 85 | `noise.ogxHash22` | 已迁入 | 承接算法：程序化噪声 |
| `perlin_gradient` | 89 | `noise.ogxPerlinGradient2` | 已迁入 | 承接算法：程序化噪声 |
| `curl2D` | 113 | `noise.ogxCurl2D` | 已迁入 | 同名迁移：程序化噪声 |
| `getCloudShape` | 118 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`rainStrength` |
| `getCumulonimbusShape` | 288 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition` |
| `getLightningPosition` | 377 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
| `getPlanetShadow` | 404 | `planet.ogxPlanetEnd` | 已迁入 | 承接算法：末地行星 |
| `GetCloudShadow` | 412 | — | 缺失 | Eclipse 的体积云影贴图采样，需要云影贴图坐标与天气状态 |
| `getRayOrigin` | 464 | — | MC 专用 | 体积云光线起点，依赖相机位置与视场内插 |
| `phaseCloud` | 491 | `cloud.ogxHenyeyGreenstein` | 已迁入 | 承接算法：云形状、光照与云影 |
| `getCloudScattering` | 512 | `cloud.ogxCloudMarch` | 已迁入 | 承接算法：云形状、光照与云影 |
| `getCloudLighting` | 578 | `cloud.ogxCloudLight` | 已迁入 | 承接算法：云形状、光照与云影 |
| `raymarchCloud` | 628 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`cameraPosition`、`shadowModelView` |
| `GetVolumetricClouds` | 960 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`cameraPosition`、`gbufferModelView` |
| `raymarchCloudSimple` | 1385 | `cloud.ogxCloudMarch` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetVolumetricCloudsSimple` | 1493 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |

`references/Eclipse/shaders/lib/voxel_write.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetVoxelIndex` | 1 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
| `SetVoxelBlock` | 19 | `voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `PopulateShadowVoxel` | 89 | — | MC 专用 | 函数体直接读取宿主符号：`mc_Entity`、`entityId`、`blockEntityId`、`blockEntity` |

`references/Eclipse/shaders/lib/waterBump.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `waterCaustics` | 9 | `water.ogxWaterCaustics` | 已迁入 | 同名迁移：水面与海洋 |
| `getWaterHeightmap` | 32 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`frameTimeCounter` |
| `getWaveNormal` | 49 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex` |

## 缺口清单

共 36 个，按参考实现的行数从多到少排列。

| 函数 | 参考位置 | 行数 | 参考做什么 |
| --- | --- | --- | --- |
| `GetCloudShadow` | `references/Eclipse/shaders/lib/volumetricClouds.glsl:412` | 40 | Eclipse 的体积云影贴图采样，需要云影贴图坐标与天气状态 |
| `BilateralUpscale_SSAO` | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:43` | 31 | 半分辨率遮蔽的双边上采样，库里用时间抗锯齿阶段的四邻域加权替代，尚未独立成函数 |
| `BilinearTextureSkybox` | `references/iterationT/shaders/Lib/Programs/Gbuffers/Skytextured_FS.glsl:35` | 14 | 参考实现 14 行，库里没有对应算法 |
| `orb` | `references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl:33` | 12 | 镜头光斑的圆盘形状，属于眩光辅助函数 |
| `BilinearTexture` | `references/iterationT/shaders/Lib/Programs/Gbuffers/Skytextured_FS.glsl:21` | 10 | 参考实现 10 行，库里没有对应算法 |
| `skyCloudsFromTexLOD` | `references/Eclipse/shaders/lib/sky_gradient.glsl:210` | 10 | 按距离选择天空贴图层级，需要采样器；库不绑定采样器 |
| `skyCloudsFromTexBLUR` | `references/Eclipse/shaders/lib/sky_gradient.glsl:195` | 9 | 天空贴图的模糊采样，需要采样器；库不绑定采样器 |
| `GetDistOffset` | `references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl:10` | 8 | 镜头光斑的距离偏移，属于眩光光斑辅助函数 |
| `rsi` | `references/Eclipse/shaders/lib/util.glsl:162` | 8 | 球面坐标变换的快捷实现，库用 ogxCircleMap 与 ogxSkyProject 覆盖 |
| `H` | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:48` | 7 | 参考实现 7 行，库里没有对应算法 |
| `ppss` | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:57` | 7 | 参考实现 7 行，库里没有对应算法 |
| `flare` | `references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl:22` | 7 | 镜头光斑的十字星芒，属于眩光辅助函数 |
| `ring` | `references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl:51` | 7 | 镜头光斑的圆环，属于眩光辅助函数 |
| `iqint2` | `references/Eclipse/shaders/lib/end_fog.glsl:45` | 7 | 整数二维坐标的快速取整，属于末地雾的噪声辅助 |
| `fp10Dither` | `references/Eclipse/shaders/lib/color_dither.glsl:19` | 6 | 十位浮点的量化抖动，库的 ogxDitherFloat 覆盖八位与十六位 |
| `fp16Dither` | `references/Eclipse/shaders/lib/color_dither.glsl:26` | 6 | 十六位浮点的量化抖动，库的 ogxDitherFixed 覆盖八位 |
| `D_Walter` | `references/iterationT/shaders/Lib/Utilities.glsl:158` | 5 | Walter 粗糙度重映射，库使用 GGX 的标准 alpha 定义 |
| `skyCloudsFromTex` | `references/Eclipse/shaders/lib/sky_gradient.glsl:186` | 5 | 读取天空贴图并合成云，需要采样器；库按架构约定不绑定采样器 |
| `decodeVec2_16` | `references/Eclipse/shaders/lib/specular.glsl:274` | 5 | 把十六位打包值拆成二维法线，库用八位版本 ogxUnpack2x8 |
| `int8Dither` | `references/Eclipse/shaders/lib/color_dither.glsl:33` | 4 | 八位整数的量化抖动辅助 |
| `int10Dither` | `references/Eclipse/shaders/lib/color_dither.glsl:38` | 4 | 十位整数的量化抖动辅助 |
| `int16Dither` | `references/Eclipse/shaders/lib/color_dither.glsl:43` | 4 | 十六位整数的量化抖动辅助 |
| `Tonemap_Xonk` | `references/Eclipse/shaders/lib/color_transforms.glsl:166` | 4 | Xonk 曲线是一条独立拟合，库里没有同一条曲线 |
| `R2_samples` | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:1` | 4 | 参考实现 4 行，库里没有对应算法 |
| `CalculateCoCRadius` | `references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl:3` | 3 | 按深度与焦距求弥散圆半径，库在 ogxCocRadius 里做了同类计算但接口不同 |
| `w0` | `references/Eclipse/shaders/lib/sky_gradient.glsl:69` | 3 | 参考实现 3 行，库里没有对应算法 |
| `w1` | `references/Eclipse/shaders/lib/sky_gradient.glsl:74` | 3 | 参考实现 3 行，库里没有对应算法 |
| `w2` | `references/Eclipse/shaders/lib/sky_gradient.glsl:79` | 3 | 参考实现 3 行，库里没有对应算法 |
| `w3` | `references/Eclipse/shaders/lib/sky_gradient.glsl:84` | 3 | 参考实现 3 行，库里没有对应算法 |
| `g0` | `references/Eclipse/shaders/lib/sky_gradient.glsl:89` | 3 | 参考实现 3 行，库里没有对应算法 |
| `g1` | `references/Eclipse/shaders/lib/sky_gradient.glsl:94` | 3 | 参考实现 3 行，库里没有对应算法 |
| `h0` | `references/Eclipse/shaders/lib/sky_gradient.glsl:99` | 3 | 参考实现 3 行，库里没有对应算法 |
| `h1` | `references/Eclipse/shaders/lib/sky_gradient.glsl:104` | 3 | 参考实现 3 行，库里没有对应算法 |
| `bayer16` | `references/iterationT/shaders/Lib/Utilities.glsl:288` | 1 | 16×16 拜尔矩阵常数，库目前只到 8×8 与 64 级 |
| `bayer32` | `references/iterationT/shaders/Lib/Utilities.glsl:289` | 1 | 32×32 拜尔矩阵常数，库目前只到 8×8 与 64 级 |
| `bayer128` | `references/iterationT/shaders/Lib/Utilities.glsl:291` | 1 | 128×128 拜尔矩阵常数，库目前只到 8×8 与 64 级 |

## 重新生成

```text
python omni-gfx/build.py parity
```
