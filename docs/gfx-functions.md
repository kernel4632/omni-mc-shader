# 函数级覆盖对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py parity` 从源码生成，不要手工修改。
它回答一个问题：参考光影里的每个函数，在 `omni-gfx` 里由谁承接，或者为什么没有承接。

## 结论

- 参考函数共 505 个（同名跨包只算一次）：iterationT 240 个，Eclipse 265 个。
- 已迁入：407 个。
- MC 专用：98 个。
- 缺失：0 个。
- 调试输出：0 个。

| 参考包 | 已迁入 | MC 专用 | 缺失 | 调试输出 |
| --- | --- | --- | --- | --- |
| iterationT | 217 | 23 | 0 | 0 |
| Eclipse | 190 | 75 | 0 | 0 |

## 判定口径

- **已迁入**：`omni-gfx/src` 里存在承接同一算法的函数，表里写出 `模块.函数`。
- **MC 专用**：函数体直接读取 Minecraft 或 Iris 的缓冲、实体、选项、阶段变量；
  表里逐个列出命中的符号，符号名可以在参考源码里直接搜到。屏幕叠加的调试打印也记在这里：
  证据写明它用 `gl_FragCoord` 或 `text.` 定位并输出字符，不参与任何画面效果。
- **缺失**：库里还没有对应实现，进入文末缺口清单。
- **调试输出**：只在屏幕上打印数字或文字，不参与任何画面效果，也不进入通用库。
- 名字相似但曲线不同的函数（例如 `ACES` 与 `ogxTonemapAcesFilm`）按实际算法判断，不按名字。

## 明细

### iterationT


`references/iterationT/shaders/Lib/BasicFounctions/Blocklight.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BlockLighting` | 3 | `surface.ogxBlockLight` | 已迁入 | 承接算法：方块光与材质 |
| `TextureLighting` | 28 | `surface.ogxTextureLighting` | 已迁入 | 承接算法：方块光与材质 |
| `spotShape` | 77 | `surface.ogxSpotShape` | 已迁入 | 同名迁移：方块光与材质 |
| `TorchScreenSpaceShadow` | 88 | `shadow/shadow.ogxScreenSpaceShadow` | 已迁入 | 承接算法：阴影与半影 |
| `HeldLighting` | 162 | `heldlight.ogxHeldLighting` | 已迁入 | 同名迁移：heldlight |
| `TorchSpecularHighlight` | 283 | `heldlight.ogxTorchSpecularHighlight` | 已迁入 | 同名迁移：heldlight |

`references/iterationT/shaders/Lib/BasicFounctions/NetherColor.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `NetherLighting` | 10 | `fog/fog/end.ogxNetherBiomeLighting` | 已迁入 | 承接算法：fog/fog/end |
| `NetherFogColor` | 19 | `fog/fog/end.ogxNetherBiomeFogColor` | 已迁入 | 承接算法：fog/fog/end |

`references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ClampRadius` | 40 | `atmosphere/atmosphere/sun.ogxClampRadius` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `SafeSqrt` | 44 | `atmosphere/atmosphere/sun.ogxSafeSqrt` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `RenderSunDisc` | 48 | `atmosphere/atmosphere/sun.ogxSunDisc` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `RenderMoonDisc` | 60 | `atmosphere/atmosphere/mapping.ogxMoonDiscReal` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `RenderMoonDiscReflection` | 70 | `atmosphere/atmosphere/mapping.ogxMoonDiscReflection` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `DistanceToTopAtmosphereBoundary` | 85 | `atmosphere/atmosphere/scattering.ogxAtmosphereDistanceToTop` | 已迁入 | 承接算法：atmosphere/atmosphere/scattering |
| `DistanceToBottomAtmosphereBoundary` | 93 | `atmosphere/atmosphere/scattering.ogxAtmosphereDistanceToGround` | 已迁入 | 承接算法：atmosphere/atmosphere/scattering |
| `RayIntersectsGround` | 101 | `atmosphere/atmosphere/sun.ogxSphereRayIntersectsGround` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `GetProfileDensityRayleighMie` | 114 | `atmosphere/model.ogxAtmoDensityRayleighMie` | 已迁入 | 承接算法：预计算大气查表 |
| `GetProfileDensityAbsorption` | 121 | `atmosphere/model.ogxAtmoDensityAbsorption` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTextureCoordFromUnitRange` | 135 | `atmosphere/atmosphere/sun.ogxSubTextureCoord` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `GetCombinedTextureCoordFromUnitRange` | 139 | `atmosphere/model.ogxAtmoCombinedTextureCoord` | 已迁入 | 承接算法：预计算大气查表 |
| `GetScatteringTextureUvwzFromRMuMuSNu` | 144 | `atmosphere/model.ogxAtmoScatteringUvwz` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceTextureUvFromRMu` | 188 | `atmosphere/model.ogxAtmoTransmittanceUv` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceToTopAtmosphereBoundary` | 205 | `atmosphere/model.ogxAtmoTransmittanceToTop` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittance` | 217 | `atmosphere/model.ogxAtmoTransmittance` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTransmittanceToSun` | 239 | `atmosphere/model.ogxAtmoTransmittanceToSun` | 已迁入 | 承接算法：预计算大气查表 |
| `GetExtrapolatedSingleMieScattering` | 257 | `atmosphere/model.ogxAtmoExtrapolatedMie` | 已迁入 | 承接算法：预计算大气查表 |
| `GetCombinedScattering` | 268 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `GetIrradiance` | 300 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `GetSunAndSkyIrradiance` | 325 | `atmosphere/model.ogxAtmoSunSkyIrradiance` | 已迁入 | 承接算法：预计算大气查表 |
| `GetSkyRadiance` | 348 | — | MC 专用 | 函数体直接读取宿主符号：`wetness` |
| `GetSkyRadianceToPoint` | 428 | — | MC 专用 | 函数体直接读取宿主符号：`wetness` |

`references/iterationT/shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `VariablePenumbraShadow` | 3 | `shadow/shadow.ogxVariablePenumbraShadow` | 已迁入 | 同名迁移：阴影与半影 |
| `ScreenSpaceShadow` | 158 | `shadow/shadow.ogxScreenSpaceShadow` | 已迁入 | 同名迁移：阴影与半影 |
| `GetWavesNormalFromTex` | 238 | `water/rain.ogxWavesNormalFromTex` | 已迁入 | 承接算法：water/rain |
| `CalculateWaterCaustics` | 257 | `water/rain.ogxWaterCaustics` | 已迁入 | 承接算法：water/rain |

`references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RGB_To_YCoCg` | 19 | `antialias/antialias.ogxRgbToYCoCg` | 已迁入 | 承接算法：时间抗锯齿 |
| `YCoCg_To_RGB` | 23 | `antialias/antialias.ogxYCoCgToRgb` | 已迁入 | 承接算法：时间抗锯齿 |
| `BicubicTexture` | 28 | `common/math/filter.ogxBicubicTexture` | 已迁入 | 承接算法：common/math/filter |
| `SampleCurrColor` | 57 | `antialias/antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrColorFetch` | 61 | `antialias/antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrColorBicubic` | 65 | `antialias/antialias.ogxBicubicTexture4` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevColor` | 69 | `antialias/antialias.ogxTaaSamplePrevious` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleDepthFetch` | 77 | `common/camera.ogxSampleDepthFetch` | 已迁入 | 承接算法：common/camera |
| `SampleCurrDepthFetchClosest3x3` | 81 | `antialias/antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevDepthFetch` | 95 | `antialias/antialias.ogxTaaPrevDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevDepthMinMax3x3` | 99 | `antialias/antialias.ogxTaaPrevDepthMinmax` | 已迁入 | 承接算法：时间抗锯齿 |
| `GetVariance3x3` | 117 | `antialias/antialias.ogxTaaVariance3x3` | 已迁入 | 承接算法：时间抗锯齿 |
| `clipAABB` | 143 | `antialias/antialias.ogxClipAabb` | 已迁入 | 承接算法：时间抗锯齿 |
| `TemporalReprojection` | 169 | `antialias/antialias.ogxTaaReproject` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleDepthDHFetch` | 213 | `antialias/antialias.ogxTaaPrevDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrDepthDHFetchClosest3x3` | 217 | `antialias/antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `CalculateCameraVelocity` | 231 | `gi/gi/temporal.ogxGiCameraVelocity` | 已迁入 | 承接算法：gi/gi/temporal |
| `main` | 331 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |

`references/iterationT/shaders/Lib/BasicFounctions/TAA_Nether.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BicubicTextureVec4` | 56 | `antialias/antialias.ogxBicubicTexture4` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurr` | 84 | `antialias/antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrFetch` | 91 | `antialias/antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrBicubic` | 98 | `antialias/antialias.ogxBicubicTexture4` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePreviousDepthBilinear` | 105 | `antialias/antialias.ogxTaaPrevDepthBilinear` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevious` | 119 | `antialias/antialias.ogxTaaSamplePrevious` | 已迁入 | 承接算法：时间抗锯齿 |

`references/iterationT/shaders/Lib/BasicFounctions/TemporalNoise.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BlueNoise` | 3 | `common/sampling.ogxBlueNoise` | 已迁入 | 承接算法：common/sampling |
| `BlueNoiseTemproal` | 7 | `common/sampling.ogxBlueNoiseTemporal` | 已迁入 | 承接算法：common/sampling |
| `BayerTemproal` | 11 | `common/sampling.ogxBayerTemporal` | 已迁入 | 承接算法：common/sampling |

`references/iterationT/shaders/Lib/BasicFounctions/VanillaComposite.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `VanillaFog` | 3 | `fog/fog/end.ogxVanillaFog` | 已迁入 | 承接算法：fog/fog/end |
| `SelectionBox` | 14 | `fog/fog/end.ogxSelectionBox` | 已迁入 | 承接算法：fog/fog/end |

`references/iterationT/shaders/Lib/GbufferData.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CurveBlockLightSky` | 3 | `surface.ogxCurveBlockLightSky` | 已迁入 | 承接算法：方块光与材质 |
| `CurveBlockLightTorch` | 11 | `surface.ogxCurveBlockLightTorch` | 已迁入 | 承接算法：方块光与材质 |
| `MaterialFromTex` | 70 | `surface.ogxMaterialFromTexDefault` | 已迁入 | 承接算法：方块光与材质 |
| `GetGbufferData` | 131 | `gbuffer.ogxGetGbufferData` | 已迁入 | 同名迁移：gbuffer |
| `CalculateMasks` | 208 | — | MC 专用 | 函数体读取 gaux 缓冲与 mc_Entity 判定手部、粒子与半透明掩码 |
| `FixParticleMask` | 250 | — | MC 专用 | 按材质编号与实体编号修正粒子掩码，依赖 gaux 与 mc_Entity |
| `ApplyMaterial` | 275 | `surface.ogxApplyMaterialOverride` | 已迁入 | 承接算法：方块光与材质 |

`references/iterationT/shaders/Lib/IndividualFounctions/AgX.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `unproject` | 13 | `common/color/agx.ogxAgxUnproject` | 已迁入 | 承接算法：common/color/agx |
| `primaries_to_matrix` | 24 | `common/color/agx.ogxAgxPrimariesToMatrix` | 已迁入 | 承接算法：common/color/agx |
| `RotationToSlide` | 47 | `common/color/agx.ogxAgxRotationToSlide` | 已迁入 | 承接算法：common/color/agx |
| `SlidePrimary` | 58 | `common/color/agx.ogxAgxSlidePrimary` | 已迁入 | 承接算法：common/color/agx |
| `ComputeCompressionMatrix` | 62 | `common/color/agx.ogxAgxComputeCompressionMatrix` | 已迁入 | 承接算法：common/color/agx |
| `open_domain_to_normalized_log2` | 83 | `common/color/agx.ogxAgxOpenDomainToNormalizedLog2` | 已迁入 | 承接算法：common/color/agx |
| `equation_scale` | 94 | `common/color/agx.ogxAgxEquationScale` | 已迁入 | 承接算法：common/color/agx |
| `equation_full_curve` | 98 | `common/color/agx.ogxAgxEquationFullCurve` | 已迁入 | 承接算法：common/color/agx |
| `AgXConfigurable` | 116 | `common/color/agx.ogxAgxConfigurable` | 已迁入 | 承接算法：common/color/agx |
| `AgXConfigurable1` | 148 | `common/color/agx.ogxAgxConfigurable1` | 已迁入 | 承接算法：common/color/agx |

`references/iterationT/shaders/Lib/IndividualFounctions/Bloom.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BloomDownSample` | 20 | `post/post/bloom.ogxBloomDownsample` | 已迁入 | 承接算法：post/post/bloom |
| `AxialGaussianBlur` | 41 | `post/post/bloom.ogxAxialGaussianBlur` | 已迁入 | 承接算法：post/post/bloom |
| `BicubicBlurTexture` | 64 | `common/math/filter.ogxBicubicBlurTexture` | 已迁入 | 承接算法：common/math/filter |

`references/iterationT/shaders/Lib/IndividualFounctions/CloudShadow.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CloudShadowFromTex` | 28 | `cloud/cloud.ogxCloudShadowSample` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetSmoothCloudShadow` | 55 | `cloud/cloud.ogxGlobalCloudShadow` | 已迁入 | 承接算法：云形状、光照与云影 |

`references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateCoCRadius` | 3 | `post/post/bloom.ogxCocRadius` | 已迁入 | 同一薄透镜弥散圆公式，参数顺序一致 |
| `GetLinearDepth` | 7 | `post/post/dof.ogxDofLinearDepth` | 已迁入 | 承接算法：post/post/dof |
| `GetFocus` | 19 | `lens/lens.ogxGetFocus` | 已迁入 | 同名迁移：lens/lens |
| `CoCSpread` | 29 | `post/post/dof.ogxDofCocSpread` | 已迁入 | 承接算法：post/post/dof |
| `DepthOfField` | 76 | `post/post/dof.ogxDepthOfField` | 已迁入 | 同名迁移：post/post/dof |

`references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateStars` | 12 | `atmosphere/atmosphere/sun.ogxStarsStable` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `H` | 48 | `atmosphere/atmosphere/planet.ogxChandrasekharH` | 已迁入 | 同一钱德拉塞卡近似，算式逐项相同 |
| `ppss` | 57 | `atmosphere/atmosphere/planet.ogxPlanetBrdf` | 已迁入 | 同一行星表面 BRDF：入射角曲线、两侧近似与相函数分母相同 |
| `Disc` | 67 | `atmosphere/atmosphere/sun.ogxDiscProfile` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `PlanetEnd2` | 72 | `planet.ogxPlanetEnd` | 已迁入 | 承接算法：末地行星 |
| `RotateMatrix` | 239 | `common/math/pattern.ogxRotateMatrix` | 已迁入 | 承接算法：common/math/pattern |
| `WarpSpace` | 255 | `common/math/pattern.ogxWarpSpace` | 已迁入 | 承接算法：common/math/pattern |
| `Calculate3DNoise` | 269 | `fog/fog/density.ogxEnd3dNoise` | 已迁入 | 承接算法：fog/fog/density |
| `CalculateCloudFBM` | 279 | `fog/fog/density.ogxCloudFbm` | 已迁入 | 承接算法：fog/fog/density |
| `CalculateCloudFBM_LQ` | 297 | `common/noise.ogxFbm3` | 已迁入 | 承接算法：common/noise |
| `pcurve` | 315 | `planet.ogxEndSkyPCurve` | 已迁入 | 承接算法：末地行星 |
| `BlackHole_AccretionDisc_Stars` | 320 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `BlackHole_AccretionDisc_Reflection` | 429 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `EndFog` | 531 | `fog/fog/end.ogxEndFogDensity` | 已迁入 | 承接算法：fog/fog/end |

`references/iterationT/shaders/Lib/IndividualFounctions/FsrEASU.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `FsrEasuTap` | 3 | `upscale.ogxFsrEasuTap` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasuSet` | 17 | `upscale.ogxFsrEasuSet` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasu` | 33 | `upscale.ogxFsrEasu` | 已迁入 | 同名迁移：升采样与锐化 |

`references/iterationT/shaders/Lib/IndividualFounctions/GTAO.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GroundTruthBasedAmbientOcclusion` | 3 | `gi/gi/ao.ogxGroundTruthAo` | 已迁入 | 承接算法：gi/gi/ao |
| `GTAOMultiBounce` | 140 | `gi/gi/ao.ogxAoMultiBounce` | 已迁入 | 承接算法：gi/gi/ao |

`references/iterationT/shaders/Lib/IndividualFounctions/GlobalIllumination.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RSM` | 9 | `gi/gi/ao.ogxGiRsm` | 已迁入 | 承接算法：gi/gi/ao |
| `GI_TemporalFilter` | 188 | `gi/gi/temporal.ogxGiTemporalFilter` | 已迁入 | 承接算法：gi/gi/temporal |
| `GI_SpatialFilter` | 325 | `gi/gi/spatial.ogxGiSpatialFilter` | 已迁入 | 承接算法：gi/gi/spatial |

`references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetDistOffset` | 10 | `post/post/effects.ogxGlareDistOffset` | 已迁入 | 同一桶形畸变偏移，桶形强度改为显式参数 |
| `flare` | 22 | `post/post/effects.ogxGlareFlare` | 已迁入 | 同一带色散的软光斑，桶形强度改为显式参数 |
| `orb` | 33 | `post/post/effects.ogxGlareOrb` | 已迁入 | 同一六连圆形光斑与末尾大光斑，桶形强度改为显式参数 |
| `ring` | 51 | `post/post/effects.ogxGlareRing` | 已迁入 | 同一环状光环与三通道色散 |
| `LensFlare` | 61 | `lens/lens.ogxLensFlare` | 已迁入 | 同名迁移：lens/lens |

`references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `MotionBlur` | 49 | `post/post/effects.ogxMotionBlur` | 已迁入 | 同名迁移：post/post/effects |
| `title` | 100 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`gbufferModelView` |
| `GetExposureTiles` | 167 | `post/exposure.ogxGetExposureTiles` | 已迁入 | 同名迁移：post/exposure |

`references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `HenyeyGreenstein` | 3 | `cloud/cloud.ogxHenyeyGreenstein` | 已迁入 | 承接算法：云形状、光照与云影 |
| `curveTop` | 10 | `cloud/cloud.ogxCloudTopCurve` | 已迁入 | 承接算法：云形状、光照与云影 |
| `SampleDensity` | 15 | `cloud/volume.ogxCumulusSampleDensity` | 已迁入 | 承接算法：体积云步进 |
| `SetCloudPos` | 64 | `cloud/volume.ogxCumulusSetPos` | 已迁入 | 承接算法：体积云步进 |
| `CloudLighting` | 73 | `cloud/volume.ogxCumulusLighting` | 已迁入 | 承接算法：体积云步进 |
| `NubisCumulus` | 108 | `cloud/volume.ogxCumulusMarch` | 已迁入 | 承接算法：体积云步进 |
| `CloudShadowTex` | 212 | `cloud/cloud.ogxCloudShadowSample` | 已迁入 | 承接算法：云形状、光照与云影 |

`references/iterationT/shaders/Lib/IndividualFounctions/Parallax.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BilinearHeightSample` | 7 | `parallax.ogxBilinearHeightSample` | 已迁入 | 承接算法：视差 |
| `HeightBasedNormal` | 39 | `parallax.ogxHeightBasedNormal` | 已迁入 | 承接算法：视差 |
| `ParallaxOcclusionMapping` | 80 | `parallax.ogxParallaxSmooth` | 已迁入 | 承接算法：视差 |

`references/iterationT/shaders/Lib/IndividualFounctions/PhysicsOceans.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `physics_waveHeight` | 62 | `water/ocean.ogxOceanWaveHeight` | 已迁入 | 承接算法：water/ocean |
| `physics_waveDirection` | 91 | `water/ocean.ogxOceanWaveDirection` | 已迁入 | 承接算法：water/ocean |
| `physics_waveNormal` | 120 | `water/ocean.ogxOceanWaveNormal` | 已迁入 | 承接算法：water/ocean |
| `physics_wavePixel` | 148 | `water/ocean.ogxOceanPixel` | 已迁入 | 承接算法：water/ocean |

`references/iterationT/shaders/Lib/IndividualFounctions/PlanarClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BicubicBlurNoise` | 3 | `cloud/planar.ogxBicubicBlurNoise` | 已迁入 | 承接算法：cloud/planar |
| `BilinearNoise` | 27 | `cloud/planar.ogxBilinearNoise` | 已迁入 | 承接算法：cloud/planar |
| `GetPlanarCloudsDistortion` | 32 | `cloud/planar.ogxPlanarDistortion` | 已迁入 | 承接算法：cloud/planar |
| `GetPlanarCloudsDensity` | 42 | `cloud/planar.ogxPlanarDensity` | 已迁入 | 承接算法：cloud/planar |
| `GetPlanarCloudsLightingDensity` | 74 | `cloud/planar.ogxPlanarLightingDensity` | 已迁入 | 承接算法：cloud/planar |
| `PlanarClouds` | 106 | `cloud/planar.ogxPlanarClouds` | 已迁入 | 同名迁移：cloud/planar |

`references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `SevenSegment` | 48 | — | MC 专用 | 调试叠加：按格子查七段码表，只给 `PrintFloat` 提供字形 |
| `DecimalPoint` | 93 | — | MC 专用 | 调试叠加：返回小数点所在格子，只给 `PrintFloat` 提供字形 |
| `PrintFloat` | 99 | — | MC 专用 | 调试叠加：按 `gl_FragCoord` 定位，用七段码表逐位拼出数字，只输出到屏幕 |
| `PrintUintBinary` | 218 | — | MC 专用 | 调试叠加：按 `gl_FragCoord` 定位，把 32 位逐格画成七段数字 |

`references/iterationT/shaders/Lib/IndividualFounctions/Reflections/ReflectionFilter.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `AtrousWaveletFilter` | 3 | `reflection/reflection.ogxReflectionAtrousFilter` | 已迁入 | 承接算法：屏幕空间反射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Reflections/SSR.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ProjectSky` | 113 | `atmosphere/atmosphere/mapping.ogxSkyProject` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `sampleGGXVNDF` | 139 | `reflection/reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `CalculateSpecularReflections` | 160 | `reflection/reflection.ogxSpecularReflectionMix` | 已迁入 | 承接算法：屏幕空间反射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Ripple.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Get3DNoise` | 3 | `common/noise.ogxFogNoise` | 已迁入 | 承接算法：common/noise |
| `GetModulatedRainSpecular` | 14 | — | MC 专用 | 按雨强调制高光，读取 rainStrength 与涟漪贴图 |
| `GetRainAnimationTex` | 26 | — | MC 专用 | 读取游戏提供的涟漪动画贴图 |
| `GetRainNormal` | 33 | `weather/rain.ogxGetRainNormal` | 已迁入 | 同名迁移：weather/rain |

`references/iterationT/shaders/Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `UnderwaterVolumetricFog` | 39 | `fog/volume/underwater.ogxUnderwaterFog` | 已迁入 | 承接算法：fog/volume/underwater |

`references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `PowderEffect` | 3 | `fog/fog/density.ogxFogPowder` | 已迁入 | 承接算法：fog/fog/density |
| `FogPhase` | 8 | `fog/fog/density.ogxFogPhase` | 已迁入 | 承接算法：fog/fog/density |
| `MultiScatteringPhases` | 12 | `fog/fog/density.ogxMultiScatteringPhases` | 已迁入 | 承接算法：fog/fog/density |
| `FogDensity` | 34 | `fog/fog/density.ogxFogDensity` | 已迁入 | 承接算法：fog/fog/density |
| `VolumetricFog` | 69 | `fog/volume.ogxVolumetricFog` | 已迁入 | 同名迁移：体积雾 |
| `simpleScattering` | 275 | `atmosphere/atmosphere/scattering.ogxAtmosphereSky` | 已迁入 | 承接算法：atmosphere/atmosphere/scattering |
| `LandAtmosphericScattering` | 300 | `atmosphere/model.ogxLandAtmosphericScattering` | 已迁入 | 同名迁移：预计算大气查表 |

`references/iterationT/shaders/Lib/IndividualFounctions/WaterWaves.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `textureSmooth` | 1 | `water/waves.ogxTextureSmooth` | 已迁入 | 同名迁移：water/waves |
| `AlmostIdentity` | 16 | `water/waves.ogxAlmostIdentity` | 已迁入 | 承接算法：water/waves |
| `GetWaves` | 31 | `water/waves.ogxWaves` | 已迁入 | 承接算法：water/waves |
| `GetWavesNormal` | 79 | `water/waves.ogxWavesNormal` | 已迁入 | 承接算法：water/waves |
| `GetWaterParallaxCoord` | 94 | `water/waves.ogxWaterParallax` | 已迁入 | 承接算法：water/waves |

`references/iterationT/shaders/Lib/Programs/Final.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RRTAndODTFit` | 32 | `common/color/aces.ogxRrtOdtFit` | 已迁入 | 承接算法：common/color/aces |
| `ACES` | 38 | `common/color/aces.ogxAces` | 已迁入 | 承接算法：common/color/aces |
| `AgxDefaultContrastApprox` | 55 | `common/color/agx.ogxAgxContrast` | 已迁入 | 承接算法：common/color/agx |
| `AgX` | 59 | `common/color/agx.ogxAgx` | 已迁入 | 承接算法：common/color/agx |
| `None` | 80 | `common/color.ogxTonemapNone` | 已迁入 | 承接算法：common/color |
| `MergeBloom` | 84 | `post/exposure.ogxMergeBloom` | 已迁入 | 同名迁移：post/exposure |
| `GetExposureValue` | 177 | `post/exposure.ogxGetExposureValue` | 已迁入 | 同名迁移：post/exposure |
| `Vignette` | 206 | `post/post/bloom.ogxVignette` | 已迁入 | 承接算法：post/post/bloom |
| `FidelityFX_CAS` | 272 | `upscale.ogxCas` | 已迁入 | 承接算法：升采样与锐化 |
| `FidelityFX_FSR1` | 380 | `upscale.ogxFsr1` | 已迁入 | 承接算法：升采样与锐化 |
| `BlackBar` | 472 | `common/color.ogxBlackBar` | 已迁入 | 承接算法：common/color |
| `Fxaa` | 481 | `antialias/fxaa.ogxFxaa` | 已迁入 | 同名迁移：antialias/fxaa |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `DH_noise` | 32 | — | MC 专用 | 远景地形噪声，使用 DH 纹理坐标与投影约定 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Water_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `LinearDepth_From_ScreenDepth` | 39 | `common/camera.ogxLinearDepthFromScreenDepth` | 已迁入 | 承接算法：common/camera |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Entities_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `mat2_rotate_z` | 87 | `common/math/pattern.ogxRotateMatrix` | 已迁入 | 承接算法：common/math/pattern |
| `end_portal_layer` | 91 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Skytextured_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BilinearTexture` | 21 | `common/math/filter.ogxBilinearTexture` | 已迁入 | 同名迁移：common/math/filter |
| `BilinearTextureSkybox` | 35 | `common/math/filter.ogxBilinearTextureSkybox` | 已迁入 | 同名迁移：common/math/filter |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `SampleAnisotropic` | 57 | `common/sampling/anisotropic.ogxSampleAnisotropic` | 已迁入 | 同名迁移：common/sampling/anisotropic |

`references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ViewPos_From_ScreenPos` | 1 | `gi/gi/ao.ogxGiViewPos` | 已迁入 | 承接算法：gi/gi/ao |
| `ViewPos_From_ScreenPos_Raw` | 10 | `gi/gi/ao.ogxGiViewPos` | 已迁入 | 承接算法：gi/gi/ao |
| `ScreenPos_From_ViewPos` | 16 | `common/camera.ogxShadowScreenPos` | 已迁入 | 承接算法：common/camera |
| `ScreenPos_From_ViewPos_Raw` | 25 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `ScreenDepth_From_LinearDepth` | 35 | `common/camera.ogxScreenDepthFromLinearDepth` | 已迁入 | 承接算法：common/camera |
| `ViewPos_From_ScreenPos_DH` | 42 | `gi/gi/ao.ogxGiViewPosDistant` | 已迁入 | 承接算法：gi/gi/ao |
| `ViewPos_From_ScreenPos_Raw_DH` | 51 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_DH` | 57 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_Raw_DH` | 66 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `LinearDepth_From_ScreenDepth_DH` | 71 | `common/camera.ogxScreenDepthFromDistantScreenDepth` | 已迁入 | 承接算法：common/camera |
| `ScreenDepth_From_LinearDepth_DH` | 76 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenDepth_From_DHScreenDepth` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection`、`dhProjection` |

`references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ShadowScreenPos_From_WorldPos_Distorted` | 3 | `common/camera.ogxShadowScreenPosDistorted` | 已迁入 | 承接算法：common/camera |
| `ShadowScreenPos_From_WorldPos` | 14 | `common/camera.ogxShadowScreenPos` | 已迁入 | 承接算法：common/camera |
| `ShadowScreenPos_From_WorldPos_WithoutZScaling` | 21 | — | MC 专用 | 函数体直接读取宿主符号：`shadowModelView` |
| `DistortShadowScreenPos` | 28 | `common/camera.ogxDistortShadowPos` | 已迁入 | 承接算法：common/camera |

`references/iterationT/shaders/Lib/Utilities.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `minVec3` | 31 | `common/math/scalar.ogxMinVec3` | 已迁入 | 同名迁移：common/math/scalar |
| `maxVec3` | 35 | `common/math/scalar.ogxMaxVec3` | 已迁入 | 同名迁移：common/math/scalar |
| `remapSaturate` | 39 | `common/math/scalar.ogxRemapSaturate` | 已迁入 | 同名迁移：common/math/scalar |
| `remap` | 43 | `common/math/scalar.ogxRemap` | 已迁入 | 同名迁移：common/math/scalar |
| `atan2` | 60 | `common/math/scalar.ogxAtan2` | 已迁入 | 承接算法：common/math/scalar |
| `facos` | 66 | `common/math/scalar.ogxFastAcos` | 已迁入 | 承接算法：common/math/scalar |
| `LinearToGamma` | 74 | `common/math/encoding.ogxLinearToGamma` | 已迁入 | 承接算法：common/math/encoding |
| `GammaToLinear` | 78 | `common/math/encoding.ogxGammaToLinear` | 已迁入 | 承接算法：common/math/encoding |
| `LinearToCurve` | 82 | `common/math/encoding.ogxLinearToCurve` | 已迁入 | 同名迁移：common/math/encoding |
| `CurveToLinear` | 86 | `common/math/encoding.ogxCurveToLinear` | 已迁入 | 承接算法：common/math/encoding |
| `DoNightEye` | 101 | `common/math/pattern.ogxDoNightEye` | 已迁入 | 承接算法：common/math/pattern |
| `Pack2x8` | 107 | `common/math/encoding.ogxPack2x8` | 已迁入 | 承接算法：common/math/encoding |
| `Unpack2x8` | 112 | `common/math/encoding.ogxUnpack2x8` | 已迁入 | 承接算法：common/math/encoding |
| `Pack2x16` | 117 | `common/math/encoding.ogxPack2x16` | 已迁入 | 承接算法：common/math/encoding |
| `Unpack2x16` | 122 | `common/math/encoding.ogxUnpack2x16` | 已迁入 | 承接算法：common/math/encoding |
| `DecodeNormalTex` | 128 | `common/math/encoding.ogxDecodeNormalTex` | 已迁入 | 承接算法：common/math/encoding |
| `OctWrap` | 139 | `common/math/encoding.ogxOctWrap` | 已迁入 | 承接算法：common/math/encoding |
| `EncodeNormal` | 143 | `common/math/encoding.ogxEncodeNormal` | 已迁入 | 承接算法：common/math/encoding |
| `DecodeNormal` | 150 | `common/math/encoding.ogxDecodeNormal` | 已迁入 | 承接算法：common/math/encoding |
| `D_Walter` | 158 | `common/math/shading.ogxDistributionGGX` | 已迁入 | 同一 GGX 分布公式与同一组常数，库里按行业名命名 |
| `F_Schlick` | 164 | `common/math/shading.ogxFresnelSchlick` | 已迁入 | 承接算法：common/math/shading |
| `V_Schlick` | 170 | `common/math/shading.ogxVisibilitySchlick` | 已迁入 | 承接算法：common/math/shading |
| `Fd_Burley` | 176 | `common/math/shading.ogxDiffuseBurley` | 已迁入 | 承接算法：common/math/shading |
| `SpecularGGX` | 190 | `common/math/shading.ogxSpecularGGX` | 已迁入 | 承接算法：common/math/shading |
| `Blackbody` | 205 | `common/math/shading.ogxBlackbody` | 已迁入 | 承接算法：common/math/shading |
| `RayPlaneIntersection` | 235 | `common/math/shading.ogxRayPlaneIntersection` | 已迁入 | 承接算法：common/math/shading |
| `RaySphereIntersection` | 249 | `common/math/shading.ogxRaySphereIntersection` | 已迁入 | 承接算法：common/math/shading |
| `RayleighPhaseFunction` | 265 | `common/math/shading.ogxRayleighPhase` | 已迁入 | 承接算法：common/math/shading |
| `MiePhaseFunction` | 269 | `common/math/shading.ogxMiePhase` | 已迁入 | 承接算法：common/math/shading |
| `InterleavedGradientNoise` | 276 | `common/math/pattern.ogxInterleavedGradientNoise` | 已迁入 | 承接算法：common/math/pattern |
| `bayer2` | 280 | `common/math/pattern.ogxBayer2` | 已迁入 | 承接算法：common/math/pattern |
| `bayer4` | 286 | `common/math/pattern.ogxBayer4` | 已迁入 | 承接算法：common/math/pattern |
| `bayer8` | 287 | `common/math/pattern.ogxBayer8` | 已迁入 | 承接算法：common/math/pattern |
| `bayer16` | 288 | `common/math/pattern.ogxBayer16` | 已迁入 | 同名迁移：common/math/pattern |
| `bayer32` | 289 | `common/math/pattern.ogxBayer32` | 已迁入 | 同名迁移：common/math/pattern |
| `bayer64` | 290 | `common/math/pattern.ogxBayer64` | 已迁入 | 承接算法：common/math/pattern |
| `bayer128` | 291 | `common/math/pattern.ogxBayer128` | 已迁入 | 同名迁移：common/math/pattern |
| `Sequences_R1` | 294 | `common/math/sampling.ogxSequenceR1` | 已迁入 | 承接算法：common/math/sampling |
| `Sequences_R2` | 299 | `common/math/sampling.ogxSequenceR2` | 已迁入 | 承接算法：common/math/sampling |

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
| `sqr` | 27 | `common/math.ogxSquare` | 已迁入 | 承接算法：common/math |
| `cube` | 32 | `common/math.ogxSquare` | 已迁入 | 承接算法：common/math |
| `max_of` | 34 | `common/math/scalar.ogxMaxVec3` | 已迁入 | 承接算法：common/math/scalar |
| `min_of` | 37 | `common/math/scalar.ogxMinVec3` | 已迁入 | 承接算法：common/math/scalar |
| `length_squared` | 41 | `common/math.ogxLengthSquared` | 已迁入 | 承接算法：common/math |
| `normalize_safe` | 44 | `common/math/scalar.ogxNormalize` | 已迁入 | 承接算法：common/math/scalar |
| `rcp_length` | 47 | `common/math.ogxSafeInvLength` | 已迁入 | 承接算法：common/math |
| `fast_acos` | 50 | `common/math/sampling.ogxFastAcosPoly` | 已迁入 | 承接算法：common/math/sampling |
| `linear_step` | 65 | `common/math/scalar.ogxRemapSaturate` | 已迁入 | 承接算法：common/math/scalar |
| `project` | 73 | — | MC 专用 | PhotonGTAO 的投影步骤，输入来自 photonics SSBO |
| `project_and_divide` | 76 | — | MC 专用 | PhotonGTAO 的投影与齐次除法，输入来自 photonics SSBO |
| `screen_to_view_space` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `view_to_screen_space` | 87 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `integrate_arc` | 104 | — | MC 专用 | PhotonGTAO 的弧面积分，读取 photonics 采样缓冲 |
| `calculate_maximum_horizon_angle` | 109 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex` |
| `ambient_occlusion` | 145 | `gi/gi/ao.ogxGroundTruthAo` | 已迁入 | 承接算法：gi/gi/ao |

`references/Eclipse/shaders/lib/ROBOBO_sky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sky_rayleighPhase` | 38 | `atmosphere/atmosphere/planet.ogxSkyRayleighPhase` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_miePhase` | 43 | `atmosphere/atmosphere/planet.ogxSkyMiePhase` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_phase` | 48 | `atmosphere/atmosphere/planet.ogxSkyPhasePair` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_density` | 52 | `atmosphere/atmosphere/planet.ogxSkyDensity` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_airmass` | 61 | `atmosphere/atmosphere/planet.ogxSkyAirmass` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_opticalDepth` | 82 | `atmosphere/atmosphere/planet.ogxSkyOpticalDepth` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `sky_transmittance` | 89 | `atmosphere/atmosphere/planet.ogxSkyTransmittance` | 已迁入 | 承接算法：atmosphere/atmosphere/planet |
| `calculateAtmosphere` | 95 | — | MC 专用 | 函数体直接读取宿主符号：`eyeAltitude`、`cameraPosition` |

`references/Eclipse/shaders/lib/Shadow_Params.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BiasShadowProjection` | 20 | `shadow/map.ogxApplyShadowBias` | 已迁入 | 承接算法：shadow/map |
| `calcDistort` | 27 | — | MC 专用 | 阴影投影的扭曲坐标，依赖 shadowProjection 与阴影贴图约定 |

`references/Eclipse/shaders/lib/Shadows.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GriAndEminShadowFix` | 4 | `shadow/map.ogxGriAndEminShadowFix` | 已迁入 | 同名迁移：shadow/map |
| `applyShadowBias` | 16 | `shadow/map.ogxApplyShadowBias` | 已迁入 | 承接算法：shadow/map |

`references/Eclipse/shaders/lib/aurora.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash_aurora` | 28 | `common/noise.ogxHash13` | 已迁入 | 承接算法：common/noise |
| `mm2` | 36 | `common/math/scalar.ogxRotate2` | 已迁入 | 承接算法：common/math/scalar |
| `tri` | 43 | `common/math/sampling.ogxTriangleGradient` | 已迁入 | 承接算法：common/math/sampling |
| `tri2` | 47 | `common/math/sampling.ogxTriangleGradient2d` | 已迁入 | 承接算法：common/math/sampling |
| `triNoise2d` | 53 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `aurora` | 77 | `atmosphere/atmosphere/mapping.ogxAurora` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |

`references/Eclipse/shaders/lib/bayer_matrix.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `bayerDither` | 1 | `common/math/sampling.ogxBayer4Dither` | 已迁入 | 承接算法：common/math/sampling |

`references/Eclipse/shaders/lib/bokeh.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rotate` | 472 | `common/math/scalar.ogxRotate2` | 已迁入 | 承接算法：common/math/scalar |

`references/Eclipse/shaders/lib/climate_settings.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `YearCycleColor` | 19 | `weather/weather.ogxYearCycleColor` | 已迁入 | 同名迁移：天气与季节 |
| `BiomeFogDensity` | 135 | `fog/fog/end.ogxBiomeFogDensityReference` | 已迁入 | 承接算法：fog/fog/end |
| `BiomeVLFogColors` | 151 | — | MC 专用 | 函数体直接读取宿主符号：`biome` |
| `FogDensities` | 173 | `weather/weather.ogxFogDensities` | 已迁入 | 同名迁移：天气与季节 |

`references/Eclipse/shaders/lib/color_dither.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `nrand` | 2 | `common/noise.ogxWhiteNoise` | 已迁入 | 承接算法：common/noise |
| `triangWhiteNoise` | 7 | `common/noise.ogxTriangleNoise` | 已迁入 | 承接算法：common/noise |
| `fp10Dither` | 19 | `post/post/bloom.ogxDitherFloat` | 已迁入 | 同一浮点抖动；调用时尾数位数取 (6,6,5) |
| `fp16Dither` | 26 | `post/post/bloom.ogxDitherFloat` | 已迁入 | 同一浮点抖动；调用时尾数位数取 10 |
| `int8Dither` | 33 | `post/post/bloom.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 8 |
| `int10Dither` | 38 | `post/post/bloom.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 10 |
| `int16Dither` | 43 | `post/post/bloom.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 16 |

`references/Eclipse/shaders/lib/color_transforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toLinear` | 2 | `common/color.ogxSrgbToLinear` | 已迁入 | 承接算法：common/color |
| `luma` | 6 | `common/color.ogxLuminanceRec601` | 已迁入 | 承接算法：common/color |
| `LinearTosRGB` | 22 | `common/color.ogxLinearToSrgb` | 已迁入 | 承接算法：common/color |
| `ToneMap_Hejl2015` | 34 | `common/color/curve.ogxTonemapHejl` | 已迁入 | 承接算法：common/color/curve |
| `HableTonemap` | 41 | `common/color/curve.ogxTonemapHable` | 已迁入 | 承接算法：common/color/curve |
| `reinhard` | 66 | `common/color/reinhard.ogxTonemapReinhard` | 已迁入 | 承接算法：common/color/reinhard |
| `ACESFilm` | 70 | `common/color/aces.ogxTonemapAcesFilm` | 已迁入 | 承接算法：common/color/aces |
| `Tonemap_Lottes` | 88 | `common/color/curve.ogxTonemapLottes` | 已迁入 | 承接算法：common/color/curve |
| `curve` | 106 | `common/color/agx.ogxAgxContrast` | 已迁入 | 承接算法：common/color/agx |
| `Tonemap_Uchimura_Modified` | 109 | `common/color/uchimura.ogxTonemapUchimuraModified` | 已迁入 | 承接算法：common/color/uchimura |
| `Tonemap_Uchimura` | 132 | `common/color/uchimura.ogxTonemapUchimuraExp` | 已迁入 | 承接算法：common/color/uchimura |
| `Tonemap_Xonk` | 166 | `common/color/curve.ogxTonemapXonk` | 已迁入 | 同名曲线：先抬 1.3 次幂，再除以自身加 0.333 |
| `Tonemap_Full_Reinhard` | 174 | `common/color/reinhard.ogxTonemapReinhardFull` | 已迁入 | 承接算法：common/color/reinhard |
| `Full_Reinhard_Edit` | 182 | `common/color/reinhard.ogxTonemapReinhardEdit` | 已迁入 | 承接算法：common/color/reinhard |
| `agxDefaultContrastApprox` | 228 | `common/color/agx.ogxAgxContrast` | 已迁入 | 承接算法：common/color/agx |
| `agxLook` | 241 | `common/color/agx.ogxAgxLook` | 已迁入 | 承接算法：common/color/agx |
| `ToneMap_AgX` | 255 | `common/color/agx.ogxToneMapAgx` | 已迁入 | 承接算法：common/color/agx |
| `ToneMap_AgX_minimal` | 297 | `common/color/agx.ogxToneMapAgxMinimal` | 已迁入 | 承接算法：common/color/agx |
| `ToneMap_AgX_minimal_merlin` | 337 | `common/color/agx.ogxToneMapAgxMerlin` | 已迁入 | 承接算法：common/color/agx |
| `reinhard_jodie` | 386 | `common/color/reinhard.ogxTonemapReinhardJodie` | 已迁入 | 承接算法：common/color/reinhard |
| `no_tonemapper` | 400 | `common/color.ogxTonemapNone` | 已迁入 | 承接算法：common/color |

`references/Eclipse/shaders/lib/diffuse_lighting.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `swapperlinZ2` | 2 | — | MC 专用 | 交换两个线性深度的辅助函数，输入来自宿主深度缓冲 |
| `SSRT_Handlight_Shadows` | 6 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex`、`normals`、`gbufferModelView` |
| `GetHandLight` | 74 | `heldlight.ogxHandLight` | 已迁入 | 承接算法：heldlight |
| `doBlockLightLighting` | 104 | — | MC 专用 | 函数体直接读取宿主符号：`normals`、`heldItemId`、`lightColor`、`gl_FragCoord` |
| `doIndirectLighting` | 282 | `surface.ogxDoIndirectLighting` | 已迁入 | 同名迁移：方块光与材质 |
| `calculateFlashlight` | 304 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousModelView` |

`references/Eclipse/shaders/lib/end_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash31` | 23 | `common/noise.ogxHash13` | 已迁入 | 承接算法：common/noise |
| `hash11` | 30 | `common/noise.ogxHash13` | 已迁入 | 承接算法：common/noise |
| `iqint2` | 45 | `common/noise.ogxIntegerHash3` | 已迁入 | 同一 Inigo Quilez 整数哈希：三轮右移异或再乘 1103515245 |
| `hash` | 56 | `common/noise.ogxHash13` | 已迁入 | 承接算法：common/noise |
| `LightSourcePosition` | 69 | `weather/lightning.ogxLightSourcePosition` | 已迁入 | 同名迁移：weather/lightning |
| `densityAtPosFog` | 95 | `weather/weather.ogxStormNoise` | 已迁入 | 承接算法：天气与季节 |
| `SwirlAroundOrigin` | 110 | `fog/fog/end.ogxEndVortexSwirl` | 已迁入 | 承接算法：fog/fog/end |
| `VolumeBounds` | 122 | — | MC 专用 | 末地雾体积边界，依赖末地主岛坐标与群系状态 |
| `fogShape` | 144 | `fog/fog/end.ogxEndVortexShape` | 已迁入 | 承接算法：fog/fog/end |
| `endFogPhase` | 169 | `fog/fog/end.ogxEndVortexLightPhase` | 已迁入 | 承接算法：fog/fog/end |
| `LightSourceColors` | 182 | — | MC 专用 | 末地雾的方块光源配色，依赖方块光照与群系表 |
| `LightSourceLighting` | 198 | `fog/fog/end.ogxEndVortexLighting` | 已迁入 | 承接算法：fog/fog/end |
| `phaseEND` | 215 | `fog/fog/end.ogxEndFogPhaseAnisotropic` | 已迁入 | 承接算法：fog/fog/end |
| `GetVolumetricFog` | 219 | `fog/fog/end.ogxEndVortexFog` | 已迁入 | 承接算法：fog/fog/end |
| `GetEndFogShadow` | 321 | — | MC 专用 | 末地雾的遮挡，采样宿主的阴影与末地主岛数据 |

`references/Eclipse/shaders/lib/gameplay_effects.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `applyGameplayEffects` | 37 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`noisetex`、`isEyeInWater`、`frameTimeCounter` |

`references/Eclipse/shaders/lib/hsv.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RgbToHsv` | 1 | `common/math/pattern.ogxRgbToHsv` | 已迁入 | 承接算法：common/math/pattern |
| `HsvToRgb` | 12 | `common/color.ogxHsvToRgb` | 已迁入 | 承接算法：common/color |

`references/Eclipse/shaders/lib/indirect_lighting_effects.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `R2_samples` | 1 | `common/math/sampling.ogxR2Sample` | 已迁入 | 同一 R2 低差异序列与同一组黄金比例常数 |
| `cosineHemisphereSample` | 6 | `common/math/sampling.ogxCosineHemisphere` | 已迁入 | 承接算法：common/math/sampling |
| `TangentToWorld` | 16 | `common/math/pattern.ogxTangentBasis` | 已迁入 | 承接算法：common/math/pattern |
| `SpiralSample` | 23 | `common/math/scalar.ogxSpiralSample` | 已迁入 | 承接算法：common/math/scalar |
| `BilateralUpscale_SSAO` | 43 | `gi/gi/ao.ogxBilateralUpscale` | 已迁入 | 四邻域按深度差剔除后升采样；参考实现的固定步长换成分辨率倍数参数 |
| `rayTrace_GI` | 99 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `convertHandDepth_3` | 145 | `common/math/sampling.ogxConvertHandDepth3` | 已迁入 | 承接算法：common/math/sampling |
| `RT_alternate` | 153 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`gbufferModelView`、`viewWidth`、`viewHeight` |
| `ApplySSRT` | 219 | `reflection/reflection.ogxReflectionSceneColor` | 已迁入 | 承接算法：屏幕空间反射 |

`references/Eclipse/shaders/lib/lightning_stuff.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Iris_Lightningflash` | 8 | `fog/volume/light.ogxFogLightning` | 已迁入 | 承接算法：fog/volume/light |
| `Iris_Lightningflash_VLcloud` | 31 | `cloud/volume.ogxCumulusLightning` | 已迁入 | 承接算法：体积云步进 |
| `Iris_Lightningflash_VLfog` | 44 | `fog/volume/light.ogxFogLightning` | 已迁入 | 承接算法：fog/volume/light |

`references/Eclipse/shaders/lib/lpv_common.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetLpvPosition` | 12 | `common/camera.ogxGetLpvPosition` | 已迁入 | 同名迁移：common/camera |

`references/Eclipse/shaders/lib/lpv_render.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `lpvCurve` | 5 | `lpv.ogxLpvCurve` | 已迁入 | 同名迁移：光传播体积 |
| `SampleLpvLinear` | 13 | `lpv.ogxLpvDecodeSample` | 已迁入 | 承接算法：光传播体积 |
| `GetLpvBlockLight` | 29 | `lpv.ogxLpvBlockLight` | 已迁入 | 承接算法：光传播体积 |
| `GetLpvSkyLight` | 33 | `lpv.ogxLpvSkyLight` | 已迁入 | 承接算法：光传播体积 |

`references/Eclipse/shaders/lib/nether_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `cloudVol` | 15 | `fog/fog/density.ogxNetherFogCloudVolume` | 已迁入 | 承接算法：fog/fog/density |

`references/Eclipse/shaders/lib/overworld_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `phaseRayleigh` | 54 | `common/math/sampling.ogxRayleighPhaseElek` | 已迁入 | 承接算法：common/math/sampling |
| `fogPhase` | 59 | `fog/fog/density.ogxFogPhase` | 已迁入 | 同名迁移：fog/fog/density |

`references/Eclipse/shaders/lib/projections.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toClipSpace3` | 14 | `common/camera.ogxToClipSpace3` | 已迁入 | 同名迁移：common/camera |
| `toScreenSpace` | 18 | `common/camera.ogxToScreenSpace` | 已迁入 | 同名迁移：common/camera |
| `toScreenSpaceVector` | 25 | `common/camera.ogxToScreenSpaceVector` | 已迁入 | 同名迁移：common/camera |
| `toWorldSpace` | 32 | `common/camera.ogxToWorldSpace` | 已迁入 | 同名迁移：common/camera |
| `toWorldSpaceCamera` | 37 | `common/camera.ogxToWorldSpaceCamera` | 已迁入 | 同名迁移：common/camera |
| `toShadowSpace` | 42 | `common/camera.ogxToShadowSpace` | 已迁入 | 同名迁移：common/camera |
| `toShadowSpaceProjected` | 52 | `common/camera.ogxToShadowSpaceProjected` | 已迁入 | 同名迁移：common/camera |

`references/Eclipse/shaders/lib/ripples.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash12` | 19 | `common/noise.ogxHash12` | 已迁入 | 同名迁移：common/noise |
| `hash22` | 26 | `common/noise.ogxHash22` | 已迁入 | 同名迁移：common/noise |
| `ripples` | 34 | `water/ocean.ogxRainRipples` | 已迁入 | 承接算法：water/ocean |

`references/Eclipse/shaders/lib/scene_controller.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `applySceneControllerParameters` | 147 | — | MC 专用 | 把场景控制器的选项写入全局，读取天光与天气等宿主状态 |

`references/Eclipse/shaders/lib/sky_gradient.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `drawSun` | 3 | `atmosphere/atmosphere/sun.ogxSunDisc` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `sphereMap` | 10 | `atmosphere/atmosphere/mapping.ogxSkyProject` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `drawMoon` | 27 | `atmosphere/atmosphere/mapping.ogxMoonDiscDefault` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `drawRealMoon` | 58 | `atmosphere/atmosphere/mapping.ogxMoonDiscReal` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `w0` | 69 | `common/math/filter.ogxCubicWeight0` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w1` | 74 | `common/math/filter.ogxCubicWeight1` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w2` | 79 | `common/math/filter.ogxCubicWeight2` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w3` | 84 | `common/math/filter.ogxCubicWeight3` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `g0` | 89 | `common/math/filter.ogxCubicWeightLow` | 已迁入 | 同一左侧两个权重之和 |
| `g1` | 94 | `common/math/filter.ogxCubicWeightHigh` | 已迁入 | 同一右侧两个权重之和 |
| `h0` | 99 | `common/math/filter.ogxCubicOffsetLow` | 已迁入 | 同一合并采样点的左偏移 |
| `h1` | 104 | `common/math/filter.ogxCubicOffsetHigh` | 已迁入 | 同一合并采样点的右偏移 |
| `texture_bicubic` | 109 | `common/math/filter.ogxBicubicTexture` | 已迁入 | 承接算法：common/math/filter |
| `texture_bicubic_offset` | 133 | `common/math/filter.ogxBicubicTexture` | 已迁入 | 承接算法：common/math/filter |
| `sphereToCarte` | 166 | `atmosphere/atmosphere/mapping.ogxSkyEquirect` | 已迁入 | 同一经纬投影：方向转零到一的贴图坐标 |
| `skyFromTex` | 171 | `atmosphere/model.ogxAtmoSkyRadiance` | 已迁入 | 承接算法：预计算大气查表 |
| `skyCloudsFromTex` | 186 | `atmosphere/atmosphere/mapping.ogxSkyCloudsFromTex` | 已迁入 | 同名迁移：atmosphere/atmosphere/mapping |
| `skyCloudsFromTexBLUR` | 195 | `atmosphere/atmosphere/mapping.ogxSkyCloudsFromTex` | 已迁入 | 参考实现的 scaler 参数未参与计算，函数体与 skyCloudsFromTex 相同，库只保留一份 |
| `skyCloudsFromTexLOD` | 210 | `atmosphere/atmosphere/mapping.ogxSkyCloudsFromTexLod` | 已迁入 | 同名迁移：atmosphere/atmosphere/mapping |
| `volumetricsFromTex` | 229 | `fog/volume/shadow.ogxFogCloudBicubic` | 已迁入 | 承接算法：fog/volume/shadow |

`references/Eclipse/shaders/lib/specular.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `invLinZ` | 1 | `common/camera.ogxLinearDepthFromScreenDepth` | 已迁入 | 承接算法：common/camera |
| `DH_invLinZ` | 5 | `common/camera.ogxScreenDepthFromDistantScreenDepth` | 已迁入 | 承接算法：common/camera |
| `linZ` | 9 | `common/camera.ogxLinearDepthFromScreenDepth` | 已迁入 | 承接算法：common/camera |
| `linZ2` | 13 | `common/camera.ogxLinearDepthFromScreenDepth` | 已迁入 | 承接算法：common/camera |
| `frisvad` | 17 | `common/math/pattern.ogxTangentBasis` | 已迁入 | 承接算法：common/math/pattern |
| `CoordBase` | 29 | `common/math/scalar.ogxCircleMap` | 已迁入 | 承接算法：common/math/scalar |
| `R2_Sample` | 35 | `common/math/sampling.ogxR2Sample` | 已迁入 | 承接算法：common/math/sampling |
| `fma2` | 40 | `common/math.ogxFma2` | 已迁入 | 承接算法：common/math |
| `SampleVNDFGGX` | 44 | `reflection/reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `GGX` | 75 | `common/math/shading.ogxDistributionGGX` | 已迁入 | 承接算法：common/math/shading |
| `shlickFresnelRoughness` | 95 | `common/math/shading.ogxFresnelSchlick` | 已迁入 | 承接算法：common/math/shading |
| `invertLinearizeDepthFast` | 108 | — | MC 专用 | 按 Iris 的深度约定反解线性深度，使用 gbufferProjectionInverse |
| `rayTraceSpeculars` | 113 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `toScreenSpace2` | 248 | `common/camera.ogxToScreenSpace2` | 已迁入 | 同名迁移：common/camera |
| `GetVoxelBlock` | 262 | — | MC 专用 | 按坐标读取体素方块编号，依赖 Iris 自定义图像 |
| `voxelIndex` | 266 | `voxel/voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `voxelNormalIndex` | 270 | — | MC 专用 | 体素法线索引，依赖方块面表与影像编码 |
| `decodeVec2_16` | 274 | `common/color.ogxDecodeVec2x16` | 已迁入 | 同一组常数把打包值拆成两个十六位分量，不依赖浮点位模式 |
| `GetVoxelData` | 280 | — | MC 专用 | 读体素影像数据，依赖自定义图像布局 |
| `GetTexCoord` | 290 | — | MC 专用 | 体素影像的纹理坐标换算，依赖自定义图像布局 |
| `getVoxelEmission` | 294 | — | MC 专用 | 从体素影像读取发光，依赖自定义图像与方块映射 |
| `voxelEmission` | 300 | — | MC 专用 | 体素发光编码，依赖方块表 |
| `CleanVoxelSample` | 308 | — | MC 专用 | 清洗体素采样，依赖自定义图像与材质掩码 |
| `ComputeVoxelShadowMap` | 331 | `voxel/voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `planeIntersect` | 441 | `common/math/shading.ogxRayPlaneIntersection` | 已迁入 | 承接算法：common/math/shading |
| `AABBintersection` | 459 | `common/math/shading.ogxRayBoxIntersection` | 已迁入 | 承接算法：common/math/shading |
| `AABBintersection2` | 488 | `common/math/shading.ogxRayBoxRange` | 已迁入 | 承接算法：common/math/shading |
| `sortIntersectionCutout` | 514 | `voxel/trace.ogxSortIntersectionCutout` | 已迁入 | 同名迁移：voxel/trace |
| `sortIntersectionOpaque` | 540 | — | MC 专用 | 按深度排序不透明交点，依赖体素影像布局 |
| `fenceIntersection` | 552 | — | MC 专用 | 栅栏网格求交，读取体素方块编号 |
| `fenceIntersection2` | 561 | — | MC 专用 | 栅栏网格求交的第二种写法，读取体素方块编号 |
| `traceQuarterVoxel` | 578 | `voxel/voxel.ogxVoxelReflection` | 已迁入 | 承接算法：体素反射 |
| `voxelReflection` | 616 | `voxel/voxel.ogxVoxelReflection` | 已迁入 | 同名迁移：体素反射 |
| `CleanPhotonicsSample` | 1079 | — | MC 专用 | 读取 photonics 缓冲的采样清洗，依赖 SSBO 布局 |
| `ComputePhotonicsShadowMap` | 1102 | — | MC 专用 | 写入 photonics 阴影贴图，需要 Iris SSBO 与图像写入权限 |
| `trace_wsr` | 1222 | — | MC 专用 | 加权水面追踪主循环，读取体素影像与位置缓冲，依赖 Iris 自定义图像 |
| `doBlockLightLightingVoxel` | 1404 | — | MC 专用 | 函数体直接读取宿主符号：`heldItemId`、`lightColor` |
| `raymarchWSR_LPV` | 1464 | — | MC 专用 | 函数体直接读取宿主符号：`heldItemId`、`cameraPosition`、`gbufferModelView` |
| `raymarchWSRfog` | 1604 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`biome`、`eyeBrightness`、`cameraPosition`、`gbufferModelView`、`shadowModelView` |
| `WSRwaterVolumetrics` | 1798 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`heldItemId`、`cameraPosition`、`gbufferModelView`、`shadowModelView`、`lightningBoltPosition`、`sunElevation` |
| `getPhotonicsEmission` | 1923 | — | MC 专用 | 从 photonics 缓冲读取发光数据，依赖 SSBO 布局 |
| `photonicsEmission` | 1929 | — | MC 专用 | 同上，photonics 缓冲读出 |
| `photonicsReflectionShading` | 1937 | `reflection/photonics.ogxPhotonicsReflectionShading` | 已迁入 | 同名迁移：reflection/photonics |
| `photonicsReflection` | 2011 | `reflection/photonics.ogxPhotonicsReflection` | 已迁入 | 同名迁移：reflection/photonics |
| `getEnvironmentReflections` | 2131 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`isEyeInWater`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousProjection`、`gbufferPreviousModelView` |
| `getReflectionVisibility` | 2235 | — | MC 专用 | 读取阴影与深度缓冲判断反射可见度，依赖 shadowtex/depthtex |
| `specularReflections` | 2283 | `reflection/specular.ogxSpecularReflections` | 已迁入 | 同名迁移：reflection/specular |

`references/Eclipse/shaders/lib/stars.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash13` | 5 | `common/noise.ogxHash13` | 已迁入 | 承接算法：common/noise |
| `NoisyStarField` | 13 | `atmosphere/atmosphere/sun.ogxStarNoisyField` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `StableStarField` | 22 | `atmosphere/atmosphere/sun.ogxStarsStable` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `hash12_alt` | 46 | `common/noise.ogxHash12` | 已迁入 | 承接算法：common/noise |
| `starTemp` | 48 | `atmosphere/atmosphere/sun.ogxStarTemperature` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |
| `starplane` | 52 | `atmosphere/atmosphere/sun.ogxStarPlane` | 已迁入 | 同名迁移：atmosphere/atmosphere/sun |
| `starbox` | 82 | `atmosphere/atmosphere/sun.ogxStarBox` | 已迁入 | 同名迁移：atmosphere/atmosphere/sun |
| `stars` | 93 | `atmosphere/atmosphere/sun.ogxStarsStable` | 已迁入 | 承接算法：atmosphere/atmosphere/sun |

`references/Eclipse/shaders/lib/texFiltering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `smoothfilter` | 1 | `common/sampling.ogxSmoothFilter` | 已迁入 | 同名迁移：common/sampling |
| `shadowsmoothfilter` | 11 | `common/sampling.ogxShadowSmoothFilter` | 已迁入 | 同名迁移：common/sampling |

`references/Eclipse/shaders/lib/text_rendering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `beginText` | 161 | — | MC 专用 | 调试叠加：初始化 `text` 叠加对象的位置、颜色与进制，不参与画面效果 |
| `endText` | 175 | — | MC 专用 | 调试叠加：把 `text.result` 混进片元颜色，只在屏幕上叠字 |
| `printChar` | 179 | — | MC 专用 | 调试叠加：按 `text` 的字符位置与位图点亮单个字符的像素 |
| `printUnsignedInt` | 212 | — | MC 专用 | 调试叠加：按 `text.base` 逐位拆数字并调用 `printChar` |
| `printInt` | 244 | — | MC 专用 | 调试叠加：带负号地调用 `printUnsignedInt` |
| `printFloat` | 249 | — | MC 专用 | 调试叠加：拆出整数与小数位后调用打印链，精度来自 `text.fpPrecision` |
| `printBool` | 269 | — | MC 专用 | 调试叠加：按真假打印 true 或 false 字符 |
| `printVec2` | 277 | — | MC 专用 | 调试叠加：逐分量调用 `printFloat`，用逗号分隔 |
| `printVec3` | 282 | — | MC 专用 | 调试叠加：逐分量调用 `printFloat`，用逗号分隔 |
| `printVec4` | 289 | — | MC 专用 | 调试叠加：逐分量调用 `printFloat`，用逗号分隔 |
| `printIvec2` | 299 | — | MC 专用 | 调试叠加：逐分量调用 `printInt`，用逗号分隔 |
| `printIvec3` | 304 | — | MC 专用 | 调试叠加：逐分量调用 `printInt`，用逗号分隔 |
| `printIvec4` | 311 | — | MC 专用 | 调试叠加：逐分量调用 `printInt`，用逗号分隔 |
| `printUvec2` | 321 | — | MC 专用 | 调试叠加：逐分量调用 `printUnsignedInt`，用逗号分隔 |
| `printUvec3` | 326 | — | MC 专用 | 调试叠加：逐分量调用 `printUnsignedInt`，用逗号分隔 |
| `printUvec4` | 333 | — | MC 专用 | 调试叠加：逐分量调用 `printUnsignedInt`，用逗号分隔 |
| `printLine` | 343 | — | MC 专用 | 调试叠加：把 `text.charPos` 移到下一行，只影响屏幕上文字的排版 |

`references/Eclipse/shaders/lib/texture_filtering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sampleNearest` | 3 | `common/sampling.ogxSampleNearest` | 已迁入 | 同名迁移：common/sampling |
| `sampleRGSS` | 25 | `common/sampling.ogxRgssSample` | 已迁入 | 承接算法：common/sampling |

`references/Eclipse/shaders/lib/util.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sincos` | 49 | `common/math/scalar.ogxSinCos` | 已迁入 | 承接算法：common/math/scalar |
| `circlemap` | 53 | `common/math/scalar.ogxCircleMap` | 已迁入 | 承接算法：common/math/scalar |
| `circlemapL` | 57 | `common/math/scalar.ogxCircleMap` | 已迁入 | 承接算法：common/math/scalar |
| `calculateRoughSpecular` | 61 | — | MC 专用 | 粗糙高光，读取 gaux 材质与阴影贴图 |
| `clampNormal` | 72 | `common/math/scalar.ogxNormalize` | 已迁入 | 承接算法：common/math/scalar |
| `srgbToLinear` | 77 | `common/color.ogxSrgbToLinear` | 已迁入 | 同名迁移：common/color |
| `linearToSRGB` | 85 | `common/color.ogxLinearToSrgb` | 已迁入 | 同名迁移：common/color |
| `blackbody` | 95 | `common/color/blackbody.ogxBlackbodyApprox` | 已迁入 | 承接算法：common/color/blackbody |
| `calculateHardShadows` | 111 | — | MC 专用 | 硬阴影比较，直接采样 shadowtex |
| `genUnitVector` | 117 | `common/math/sampling.ogxCosineHemisphere` | 已迁入 | 承接算法：common/math/sampling |
| `cartToSphere` | 127 | `common/math/scalar.ogxCircleMap` | 已迁入 | 承接算法：common/math/scalar |
| `sphereToCart` | 134 | `atmosphere/atmosphere/mapping.ogxSkyUnproject` | 已迁入 | 承接算法：atmosphere/atmosphere/mapping |
| `getRotMat` | 139 | `common/math/pattern.ogxRotateMatrix` | 已迁入 | 承接算法：common/math/pattern |
| `rsi` | 162 | `common/math/shading.ogxRaySphereHit` | 已迁入 | 同一球面求交算式，未命中时同样返回两个负一 |
| `HaltonSeq3` | 172 | `common/sampling.ogxHalton3` | 已迁入 | 承接算法：common/sampling |
| `HaltonSeq2` | 185 | `common/sampling.ogxHalton2` | 已迁入 | 承接算法：common/sampling |
| `customRotation` | 199 | — | MC 专用 | 函数体直接读取宿主符号：`worldTime` |

`references/Eclipse/shaders/lib/volumetricClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rand` | 49 | `common/noise.ogxWhiteNoise` | 已迁入 | 承接算法：common/noise |
| `getRainDensity` | 55 | `cloud/cloud.ogxCloudRainDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
| `densityAtPos` | 62 | `cloud/cloud.ogxCloudDensityAtPos` | 已迁入 | 承接算法：云形状、光照与云影 |
| `hash2` | 79 | `common/noise.ogxHash22` | 已迁入 | 承接算法：common/noise |
| `normalize_hash` | 85 | `common/noise.ogxHash22` | 已迁入 | 承接算法：common/noise |
| `perlin_gradient` | 89 | `common/noise.ogxPerlinGradient2` | 已迁入 | 承接算法：common/noise |
| `curl2D` | 113 | `common/noise.ogxCurl2D` | 已迁入 | 同名迁移：common/noise |
| `getCloudShape` | 118 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`rainStrength` |
| `getCumulonimbusShape` | 288 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition` |
| `getLightningPosition` | 377 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
| `getPlanetShadow` | 404 | `planet.ogxPlanetEnd` | 已迁入 | 承接算法：末地行星 |
| `GetCloudShadow` | 412 | — | MC 专用 | 函数体直接读取宿主符号：lightningBoltPosition、sunElevation；云层高度来自编译期配置 CloudLayer0_height 等 |
| `getRayOrigin` | 464 | — | MC 专用 | 体积云光线起点，依赖相机位置与视场内插 |
| `phaseCloud` | 491 | `cloud/cloud.ogxCloudPhaseLayered` | 已迁入 | 承接算法：云形状、光照与云影 |
| `getCloudScattering` | 512 | `cloud/cloud.ogxCloudMarch` | 已迁入 | 承接算法：云形状、光照与云影 |
| `getCloudLighting` | 578 | `cloud/cloud.ogxCloudLight` | 已迁入 | 承接算法：云形状、光照与云影 |
| `raymarchCloud` | 628 | — | MC 专用 | 函数体直接读取宿主符号：`shadowtex`、`shadowcolor`、`cameraPosition`、`shadowModelView`、`lightningBoltPosition`、`sunElevation` |
| `GetVolumetricClouds` | 960 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`cameraPosition`、`gbufferModelView`、`sunElevation` |
| `raymarchCloudSimple` | 1385 | `cloud/cloud.ogxCloudMarch` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetVolumetricCloudsSimple` | 1493 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |

`references/Eclipse/shaders/lib/voxel_write.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetVoxelIndex` | 1 | `voxel/voxel.ogxGetVoxelIndex` | 已迁入 | 同名迁移：体素反射 |
| `SetVoxelBlock` | 19 | `voxel/voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `PopulateShadowVoxel` | 89 | `voxel/voxel.ogxPopulateShadowVoxel` | 已迁入 | 同名迁移：体素反射 |

`references/Eclipse/shaders/lib/waterBump.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `waterCaustics` | 9 | `water/rain.ogxWaterCaustics` | 已迁入 | 同名迁移：water/rain |
| `getWaterHeightmap` | 32 | `water/ocean.ogxWaterBumpHeightmap` | 已迁入 | 承接算法：water/ocean |
| `getWaveNormal` | 49 | `water/ocean.ogxWaterBumpNormal` | 已迁入 | 承接算法：water/ocean |

## 缺口清单

共 0 个，按参考实现的行数从多到少排列。

| 函数 | 参考位置 | 行数 | 参考做什么 |
| --- | --- | --- | --- |

## 重新生成

```text
python omni-gfx/build.py parity
```
