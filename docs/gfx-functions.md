# 函数级覆盖对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py parity` 从源码生成，不要手工修改。
它回答一个问题：参考光影里的每个函数，在 `omni-gfx` 里由谁承接，或者为什么没有承接。

## 结论

- 参考函数共 505 个（同名跨包只算一次）：iterationT 240 个，Eclipse 265 个。
- 已迁入：401 个。
- MC 专用：104 个。
- 缺失：0 个。
- 调试输出：0 个。

| 参考包 | 已迁入 | MC 专用 | 缺失 | 调试输出 |
| --- | --- | --- | --- | --- |
| iterationT | 217 | 23 | 0 | 0 |
| Eclipse | 184 | 81 | 0 | 0 |

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
| `TextureLighting` | 28 | `surface.ogxItxTextureLighting` | 已迁入 | 承接算法：方块光与材质 |
| `spotShape` | 77 | `surface.ogxSpotShape` | 已迁入 | 同名迁移：方块光与材质 |
| `TorchScreenSpaceShadow` | 88 | `shadow/shadow.ogxScreenSpaceShadow` | 已迁入 | 承接算法：阴影与半影 |
| `HeldLighting` | 162 | `heldlight.ogxHeldLighting` | 已迁入 | 同名迁移：heldlight |
| `TorchSpecularHighlight` | 283 | `heldlight.ogxTorchSpecularHighlight` | 已迁入 | 同名迁移：heldlight |

`references/iterationT/shaders/Lib/BasicFounctions/NetherColor.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `NetherLighting` | 10 | `fog/fog.ogxNetherBiomeLighting` | 已迁入 | 承接算法：雾与空气透视 |
| `NetherFogColor` | 19 | `fog/fog.ogxNetherBiomeFogColor` | 已迁入 | 承接算法：雾与空气透视 |

`references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ClampRadius` | 40 | `atmosphere/atmosphere.ogxClampRadius` | 已迁入 | 承接算法：天空散射与日月星 |
| `SafeSqrt` | 44 | `atmosphere/atmosphere.ogxSafeSqrt` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderSunDisc` | 48 | `atmosphere/atmosphere.ogxSunDisc` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderMoonDisc` | 60 | `atmosphere/atmosphere.ogxMoonDiscReal` | 已迁入 | 承接算法：天空散射与日月星 |
| `RenderMoonDiscReflection` | 70 | `atmosphere/atmosphere.ogxMoonDiscReflection` | 已迁入 | 承接算法：天空散射与日月星 |
| `DistanceToTopAtmosphereBoundary` | 85 | `atmosphere/atmosphere.ogxAtmosphereDistanceToTop` | 已迁入 | 承接算法：天空散射与日月星 |
| `DistanceToBottomAtmosphereBoundary` | 93 | `atmosphere/atmosphere.ogxAtmosphereDistanceToGround` | 已迁入 | 承接算法：天空散射与日月星 |
| `RayIntersectsGround` | 101 | `atmosphere/atmosphere.ogxSphereRayIntersectsGround` | 已迁入 | 承接算法：天空散射与日月星 |
| `GetProfileDensityRayleighMie` | 114 | `atmosphere/model.ogxAtmoDensityRayleighMie` | 已迁入 | 承接算法：预计算大气查表 |
| `GetProfileDensityAbsorption` | 121 | `atmosphere/model.ogxAtmoDensityAbsorption` | 已迁入 | 承接算法：预计算大气查表 |
| `GetTextureCoordFromUnitRange` | 135 | `atmosphere/atmosphere.ogxSubTextureCoord` | 已迁入 | 承接算法：天空散射与日月星 |
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
| `GetWavesNormalFromTex` | 238 | `water.ogxWavesNormalFromTex` | 已迁入 | 承接算法：水面与海洋 |
| `CalculateWaterCaustics` | 257 | `water.ogxWaterCaustics` | 已迁入 | 承接算法：水面与海洋 |

`references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RGB_To_YCoCg` | 19 | `antialias/antialias.ogxRgbToYCoCg` | 已迁入 | 承接算法：时间抗锯齿 |
| `YCoCg_To_RGB` | 23 | `antialias/antialias.ogxYCoCgToRgb` | 已迁入 | 承接算法：时间抗锯齿 |
| `BicubicTexture` | 28 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `SampleCurrColor` | 57 | `antialias/antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrColorFetch` | 61 | `antialias/antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrColorBicubic` | 65 | `antialias/antialias.ogxBicubicTexture4` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevColor` | 69 | `antialias/antialias.ogxTaaSamplePrevious` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleDepthFetch` | 77 | `antialias/antialias.ogxTaaSampleDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrDepthFetchClosest3x3` | 81 | `antialias/antialias.ogxTaaSampleCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevDepthFetch` | 95 | `antialias/antialias.ogxTaaPrevDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SamplePrevDepthMinMax3x3` | 99 | `antialias/antialias.ogxTaaPrevDepthMinmax` | 已迁入 | 承接算法：时间抗锯齿 |
| `GetVariance3x3` | 117 | `antialias/antialias.ogxTaaVariance3x3` | 已迁入 | 承接算法：时间抗锯齿 |
| `clipAABB` | 143 | `antialias/antialias.ogxClipAabb` | 已迁入 | 承接算法：时间抗锯齿 |
| `TemporalReprojection` | 169 | `antialias/antialias.ogxTaaReproject` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleDepthDHFetch` | 213 | `antialias/antialias.ogxTaaPrevDepthFetch` | 已迁入 | 承接算法：时间抗锯齿 |
| `SampleCurrDepthDHFetchClosest3x3` | 217 | `antialias/antialias.ogxTaaFetchCurrent` | 已迁入 | 承接算法：时间抗锯齿 |
| `CalculateCameraVelocity` | 231 | `gi/gi.ogxGiCameraVelocity` | 已迁入 | 承接算法：全局光与遮蔽 |
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
| `BlueNoise` | 3 | `sampling.ogxBlueNoise` | 已迁入 | 承接算法：采样与抖动 |
| `BlueNoiseTemproal` | 7 | `sampling.ogxBlueNoiseTemporal` | 已迁入 | 承接算法：采样与抖动 |
| `BayerTemproal` | 11 | `sampling.ogxBayerTemporal` | 已迁入 | 承接算法：采样与抖动 |

`references/iterationT/shaders/Lib/BasicFounctions/VanillaComposite.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `VanillaFog` | 3 | `fog/fog.ogxVanillaFog` | 已迁入 | 承接算法：雾与空气透视 |
| `SelectionBox` | 14 | `fog/fog.ogxSelectionBox` | 已迁入 | 承接算法：雾与空气透视 |

`references/iterationT/shaders/Lib/GbufferData.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CurveBlockLightSky` | 3 | `surface.ogxCurveBlockLightSky` | 已迁入 | 承接算法：方块光与材质 |
| `CurveBlockLightTorch` | 11 | `surface.ogxCurveBlockLightTorch` | 已迁入 | 承接算法：方块光与材质 |
| `MaterialFromTex` | 70 | `surface.ogxItxMaterialFromTex` | 已迁入 | 承接算法：方块光与材质 |
| `GetGbufferData` | 131 | `gbuffer.ogxGetGbufferData` | 已迁入 | 同名迁移：gbuffer |
| `CalculateMasks` | 208 | — | MC 专用 | 函数体读取 gaux 缓冲与 mc_Entity 判定手部、粒子与半透明掩码 |
| `FixParticleMask` | 250 | — | MC 专用 | 按材质编号与实体编号修正粒子掩码，依赖 gaux 与 mc_Entity |
| `ApplyMaterial` | 275 | `surface.ogxApplyMaterialOverride` | 已迁入 | 承接算法：方块光与材质 |

`references/iterationT/shaders/Lib/IndividualFounctions/AgX.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `unproject` | 13 | `color.ogxAgxUnproject` | 已迁入 | 承接算法：颜色与色调映射 |
| `primaries_to_matrix` | 24 | `color.ogxAgxPrimariesToMatrix` | 已迁入 | 承接算法：颜色与色调映射 |
| `RotationToSlide` | 47 | `color.ogxAgxRotationToSlide` | 已迁入 | 承接算法：颜色与色调映射 |
| `SlidePrimary` | 58 | `color.ogxAgxSlidePrimary` | 已迁入 | 承接算法：颜色与色调映射 |
| `ComputeCompressionMatrix` | 62 | `color.ogxAgxComputeCompressionMatrix` | 已迁入 | 承接算法：颜色与色调映射 |
| `open_domain_to_normalized_log2` | 83 | `color.ogxAgxOpenDomainToNormalizedLog2` | 已迁入 | 承接算法：颜色与色调映射 |
| `equation_scale` | 94 | `color.ogxAgxEquationScale` | 已迁入 | 承接算法：颜色与色调映射 |
| `equation_full_curve` | 98 | `color.ogxAgxEquationFullCurve` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgXConfigurable` | 116 | `color.ogxAgxConfigurable` | 已迁入 | 承接算法：颜色与色调映射 |
| `AgXConfigurable1` | 148 | `color.ogxAgxConfigurable1` | 已迁入 | 承接算法：颜色与色调映射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Bloom.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BloomDownSample` | 20 | `post/post.ogxBloomDownsample` | 已迁入 | 承接算法：后期与泛光 |
| `AxialGaussianBlur` | 41 | `post/post.ogxAxialGaussianBlur` | 已迁入 | 承接算法：后期与泛光 |
| `BicubicBlurTexture` | 64 | `math.ogxBicubicBlurTexture` | 已迁入 | 承接算法：数学与通用工具 |

`references/iterationT/shaders/Lib/IndividualFounctions/CloudShadow.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CloudShadowFromTex` | 28 | `cloud/cloud.ogxCloudShadowSample` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetSmoothCloudShadow` | 55 | `cloud/cloud.ogxGlobalCloudShadow` | 已迁入 | 承接算法：云形状、光照与云影 |

`references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateCoCRadius` | 3 | `post/post.ogxCocRadius` | 已迁入 | 同一薄透镜弥散圆公式，参数顺序一致 |
| `GetLinearDepth` | 7 | `post/post.ogxDofLinearDepth` | 已迁入 | 承接算法：后期与泛光 |
| `GetFocus` | 19 | `lens/lens.ogxGetFocus` | 已迁入 | 同名迁移：lens/lens |
| `CoCSpread` | 29 | `post/post.ogxDofCocSpread` | 已迁入 | 承接算法：后期与泛光 |
| `DepthOfField` | 76 | `post/post.ogxDepthOfField` | 已迁入 | 同名迁移：后期与泛光 |

`references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `CalculateStars` | 12 | `atmosphere/atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |
| `H` | 48 | `atmosphere/atmosphere.ogxChandrasekharH` | 已迁入 | 同一钱德拉塞卡近似，算式逐项相同 |
| `ppss` | 57 | `atmosphere/atmosphere.ogxPlanetBrdf` | 已迁入 | 同一行星表面 BRDF：入射角曲线、两侧近似与相函数分母相同 |
| `Disc` | 67 | `atmosphere/atmosphere.ogxDiscProfile` | 已迁入 | 承接算法：天空散射与日月星 |
| `PlanetEnd2` | 72 | `planet.ogxPlanetEnd` | 已迁入 | 承接算法：末地行星 |
| `RotateMatrix` | 239 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `WarpSpace` | 255 | `math.ogxWarpSpace` | 已迁入 | 承接算法：数学与通用工具 |
| `Calculate3DNoise` | 269 | `fog/fog.ogxEnd3dNoise` | 已迁入 | 承接算法：雾与空气透视 |
| `CalculateCloudFBM` | 279 | `fog/fog.ogxCloudFbm` | 已迁入 | 承接算法：雾与空气透视 |
| `CalculateCloudFBM_LQ` | 297 | `noise.ogxFbm3` | 已迁入 | 承接算法：程序化噪声 |
| `pcurve` | 315 | `planet.ogxEndSkyPCurve` | 已迁入 | 承接算法：末地行星 |
| `BlackHole_AccretionDisc_Stars` | 320 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `BlackHole_AccretionDisc_Reflection` | 429 | `accretion.ogxAccretionDisc` | 已迁入 | 承接算法：吸积盘 |
| `EndFog` | 531 | `fog/fog.ogxEndFogDensity` | 已迁入 | 承接算法：雾与空气透视 |

`references/iterationT/shaders/Lib/IndividualFounctions/FsrEASU.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `FsrEasuTap` | 3 | `upscale.ogxFsrEasuTap` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasuSet` | 17 | `upscale.ogxFsrEasuSet` | 已迁入 | 承接算法：升采样与锐化 |
| `FsrEasu` | 33 | `upscale.ogxFsrEasu` | 已迁入 | 同名迁移：升采样与锐化 |

`references/iterationT/shaders/Lib/IndividualFounctions/GTAO.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GroundTruthBasedAmbientOcclusion` | 3 | `gi/gi.ogxGroundTruthAo` | 已迁入 | 承接算法：全局光与遮蔽 |
| `GTAOMultiBounce` | 140 | `gi/gi.ogxAoMultiBounce` | 已迁入 | 承接算法：全局光与遮蔽 |

`references/iterationT/shaders/Lib/IndividualFounctions/GlobalIllumination.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `RSM` | 9 | `gi/gi.ogxGiRsm` | 已迁入 | 承接算法：全局光与遮蔽 |
| `GI_TemporalFilter` | 188 | `gi/gi.ogxGiTemporalFilter` | 已迁入 | 承接算法：全局光与遮蔽 |
| `GI_SpatialFilter` | 325 | `gi/gi.ogxGiSpatialFilter` | 已迁入 | 承接算法：全局光与遮蔽 |

`references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetDistOffset` | 10 | `post/post.ogxGlareDistOffset` | 已迁入 | 同一桶形畸变偏移，桶形强度改为显式参数 |
| `flare` | 22 | `post/post.ogxGlareFlare` | 已迁入 | 同一带色散的软光斑，桶形强度改为显式参数 |
| `orb` | 33 | `post/post.ogxGlareOrb` | 已迁入 | 同一六连圆形光斑与末尾大光斑，桶形强度改为显式参数 |
| `ring` | 51 | `post/post.ogxGlareRing` | 已迁入 | 同一环状光环与三通道色散 |
| `LensFlare` | 61 | `lens/lens.ogxLensFlare` | 已迁入 | 同名迁移：lens/lens |

`references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `MotionBlur` | 49 | `post/post.ogxMotionBlur` | 已迁入 | 同名迁移：后期与泛光 |
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
| `physics_waveHeight` | 62 | `water.ogxOceanWaveHeight` | 已迁入 | 承接算法：水面与海洋 |
| `physics_waveDirection` | 91 | `water.ogxOceanWaveDirection` | 已迁入 | 承接算法：水面与海洋 |
| `physics_waveNormal` | 120 | `water.ogxOceanWaveNormal` | 已迁入 | 承接算法：水面与海洋 |
| `physics_wavePixel` | 148 | `water.ogxOceanPixel` | 已迁入 | 承接算法：水面与海洋 |

`references/iterationT/shaders/Lib/IndividualFounctions/PlanarClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BicubicBlurNoise` | 3 | `cloud/cloud.ogxBicubicBlurNoise` | 已迁入 | 承接算法：云形状、光照与云影 |
| `BilinearNoise` | 27 | `cloud/cloud.ogxBilinearNoise` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsDistortion` | 32 | `cloud/cloud.ogxPlanarDistortion` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsDensity` | 42 | `cloud/cloud.ogxPlanarDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
| `GetPlanarCloudsLightingDensity` | 74 | `cloud/cloud.ogxPlanarLightingDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
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
| `ProjectSky` | 113 | `atmosphere/atmosphere.ogxSkyProject` | 已迁入 | 承接算法：天空散射与日月星 |
| `sampleGGXVNDF` | 139 | `reflection/reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `CalculateSpecularReflections` | 160 | `reflection/reflection.ogxSpecularReflectionMix` | 已迁入 | 承接算法：屏幕空间反射 |

`references/iterationT/shaders/Lib/IndividualFounctions/Ripple.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Get3DNoise` | 3 | `noise.ogxFogNoise` | 已迁入 | 承接算法：程序化噪声 |
| `GetModulatedRainSpecular` | 14 | — | MC 专用 | 按雨强调制高光，读取 rainStrength 与涟漪贴图 |
| `GetRainAnimationTex` | 26 | — | MC 专用 | 读取游戏提供的涟漪动画贴图 |
| `GetRainNormal` | 33 | `weather/rain.ogxGetRainNormal` | 已迁入 | 同名迁移：weather/rain |

`references/iterationT/shaders/Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `UnderwaterVolumetricFog` | 39 | `fog/volume.ogxUnderwaterFog` | 已迁入 | 承接算法：体积雾 |

`references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `PowderEffect` | 3 | `fog/fog.ogxFogPowder` | 已迁入 | 承接算法：雾与空气透视 |
| `FogPhase` | 8 | `fog/fog.ogxFogPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `MultiScatteringPhases` | 12 | `fog/fog.ogxMultiScatteringPhases` | 已迁入 | 承接算法：雾与空气透视 |
| `FogDensity` | 34 | `fog/fog.ogxFogDensity` | 已迁入 | 承接算法：雾与空气透视 |
| `VolumetricFog` | 69 | `fog/volume.ogxVolumetricFog` | 已迁入 | 同名迁移：体积雾 |
| `simpleScattering` | 275 | `atmosphere/atmosphere.ogxAtmosphereSky` | 已迁入 | 承接算法：天空散射与日月星 |
| `LandAtmosphericScattering` | 300 | `atmosphere/model.ogxLandAtmosphericScattering` | 已迁入 | 同名迁移：预计算大气查表 |

`references/iterationT/shaders/Lib/IndividualFounctions/WaterWaves.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `textureSmooth` | 1 | `water.ogxTextureSmooth` | 已迁入 | 同名迁移：水面与海洋 |
| `AlmostIdentity` | 16 | `water.ogxAlmostIdentity` | 已迁入 | 承接算法：水面与海洋 |
| `GetWaves` | 31 | `water.ogxWaves` | 已迁入 | 承接算法：水面与海洋 |
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
| `MergeBloom` | 84 | `post/exposure.ogxMergeBloom` | 已迁入 | 同名迁移：post/exposure |
| `GetExposureValue` | 177 | `post/exposure.ogxGetExposureValue` | 已迁入 | 同名迁移：post/exposure |
| `Vignette` | 206 | `post/post.ogxVignette` | 已迁入 | 承接算法：后期与泛光 |
| `FidelityFX_CAS` | 272 | `upscale.ogxCas` | 已迁入 | 承接算法：升采样与锐化 |
| `FidelityFX_FSR1` | 380 | `upscale.ogxFsr1` | 已迁入 | 承接算法：升采样与锐化 |
| `BlackBar` | 472 | `color.ogxBlackBar` | 已迁入 | 承接算法：颜色与色调映射 |
| `Fxaa` | 481 | `antialias/fxaa.ogxFxaa` | 已迁入 | 同名迁移：antialias/fxaa |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `DH_noise` | 32 | — | MC 专用 | 远景地形噪声，使用 DH 纹理坐标与投影约定 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Water_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `LinearDepth_From_ScreenDepth` | 39 | `shadow/shadow.ogxShadowLinearDepth` | 已迁入 | 承接算法：阴影与半影 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Entities_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `mat2_rotate_z` | 87 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `end_portal_layer` | 91 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Skytextured_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BilinearTexture` | 21 | `math.ogxBilinearTexture` | 已迁入 | 同名迁移：数学与通用工具 |
| `BilinearTextureSkybox` | 35 | `math.ogxBilinearTextureSkybox` | 已迁入 | 同名迁移：数学与通用工具 |

`references/iterationT/shaders/Lib/Programs/Gbuffers/Terrain_FS.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `SampleAnisotropic` | 57 | `sampling/anisotropic.ogxSampleAnisotropic` | 已迁入 | 同名迁移：sampling/anisotropic |

`references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ViewPos_From_ScreenPos` | 1 | `gi/gi.ogxGiViewPos` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ViewPos_From_ScreenPos_Raw` | 10 | `gi/gi.ogxGiViewPos` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ScreenPos_From_ViewPos` | 16 | `shadow/shadow.ogxShadowScreenPos` | 已迁入 | 承接算法：阴影与半影 |
| `ScreenPos_From_ViewPos_Raw` | 25 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `ScreenDepth_From_LinearDepth` | 35 | `post/post.ogxScreenDepthFromLinearDepth` | 已迁入 | 承接算法：后期与泛光 |
| `ViewPos_From_ScreenPos_DH` | 42 | `gi/gi.ogxGiViewPosDh` | 已迁入 | 承接算法：全局光与遮蔽 |
| `ViewPos_From_ScreenPos_Raw_DH` | 51 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_DH` | 57 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenPos_From_ViewPos_Raw_DH` | 66 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `LinearDepth_From_ScreenDepth_DH` | 71 | `reflection/reflection.ogxReflectionDhToScreenDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `ScreenDepth_From_LinearDepth_DH` | 76 | — | MC 专用 | 函数体直接读取宿主符号：`dhProjection` |
| `ScreenDepth_From_DHScreenDepth` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection`、`dhProjection` |

`references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `ShadowScreenPos_From_WorldPos_Distorted` | 3 | `shadow/shadow.ogxShadowScreenPosDistorted` | 已迁入 | 承接算法：阴影与半影 |
| `ShadowScreenPos_From_WorldPos` | 14 | `shadow/shadow.ogxShadowScreenPos` | 已迁入 | 承接算法：阴影与半影 |
| `ShadowScreenPos_From_WorldPos_WithoutZScaling` | 21 | — | MC 专用 | 函数体直接读取宿主符号：`shadowModelView` |
| `DistortShadowScreenPos` | 28 | `shadow/shadow.ogxDistortShadowPos` | 已迁入 | 承接算法：阴影与半影 |

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
| `D_Walter` | 158 | `math.ogxDistributionGGX` | 已迁入 | 同一 GGX 分布公式与同一组常数，库里按行业名命名 |
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
| `bayer16` | 288 | `math.ogxBayer16` | 已迁入 | 同名迁移：数学与通用工具 |
| `bayer32` | 289 | `math.ogxBayer32` | 已迁入 | 同名迁移：数学与通用工具 |
| `bayer64` | 290 | `math.ogxBayer64` | 已迁入 | 承接算法：数学与通用工具 |
| `bayer128` | 291 | `math.ogxBayer128` | 已迁入 | 同名迁移：数学与通用工具 |
| `Sequences_R1` | 294 | `math.ogxSequenceR1` | 已迁入 | 承接算法：数学与通用工具 |
| `Sequences_R2` | 299 | `math.ogxSequenceR2` | 已迁入 | 承接算法：数学与通用工具 |

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
| `fast_acos` | 50 | `math.ogxFastAcosEclipse` | 已迁入 | 承接算法：数学与通用工具 |
| `linear_step` | 65 | `math.ogxRemapSaturate` | 已迁入 | 承接算法：数学与通用工具 |
| `project` | 73 | — | MC 专用 | PhotonGTAO 的投影步骤，输入来自 photonics SSBO |
| `project_and_divide` | 76 | — | MC 专用 | PhotonGTAO 的投影与齐次除法，输入来自 photonics SSBO |
| `screen_to_view_space` | 81 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `view_to_screen_space` | 87 | — | MC 专用 | 函数体直接读取宿主符号：`gbufferProjection` |
| `integrate_arc` | 104 | — | MC 专用 | PhotonGTAO 的弧面积分，读取 photonics 采样缓冲 |
| `calculate_maximum_horizon_angle` | 109 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex` |
| `ambient_occlusion` | 145 | `gi/gi.ogxGroundTruthAo` | 已迁入 | 承接算法：全局光与遮蔽 |

`references/Eclipse/shaders/lib/ROBOBO_sky.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `sky_rayleighPhase` | 38 | `atmosphere/atmosphere.ogxEclipseSkyRayleighPhase` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_miePhase` | 43 | `atmosphere/atmosphere.ogxEclipseSkyMiePhase` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_phase` | 48 | `atmosphere/atmosphere.ogxEclipseSkyPhase` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_density` | 52 | `atmosphere/atmosphere.ogxEclipseSkyDensity` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_airmass` | 61 | `atmosphere/atmosphere.ogxEclipseSkyAirmass` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_opticalDepth` | 82 | `atmosphere/atmosphere.ogxEclipseSkyOpticalDepth` | 已迁入 | 承接算法：天空散射与日月星 |
| `sky_transmittance` | 89 | `atmosphere/atmosphere.ogxEclipseSkyTransmittance` | 已迁入 | 承接算法：天空散射与日月星 |
| `calculateAtmosphere` | 95 | — | MC 专用 | 函数体直接读取宿主符号：`eyeAltitude`、`cameraPosition` |

`references/Eclipse/shaders/lib/Shadow_Params.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `BiasShadowProjection` | 20 | `shadow/shadow.ogxApplyShadowBias` | 已迁入 | 承接算法：阴影与半影 |
| `calcDistort` | 27 | — | MC 专用 | 阴影投影的扭曲坐标，依赖 shadowProjection 与阴影贴图约定 |

`references/Eclipse/shaders/lib/Shadows.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GriAndEminShadowFix` | 4 | `shadow/shadow.ogxGriAndEminShadowFix` | 已迁入 | 同名迁移：阴影与半影 |
| `applyShadowBias` | 16 | `shadow/shadow.ogxApplyShadowBias` | 已迁入 | 承接算法：阴影与半影 |

`references/Eclipse/shaders/lib/aurora.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash_aurora` | 28 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `mm2` | 36 | `math.ogxRotate2` | 已迁入 | 承接算法：数学与通用工具 |
| `tri` | 43 | `math.ogxEclipseTri` | 已迁入 | 承接算法：数学与通用工具 |
| `tri2` | 47 | `math.ogxEclipseTri2` | 已迁入 | 承接算法：数学与通用工具 |
| `triNoise2d` | 53 | — | MC 专用 | 函数体直接读取宿主符号：`frameTimeCounter` |
| `aurora` | 77 | `atmosphere/atmosphere.ogxAurora` | 已迁入 | 承接算法：天空散射与日月星 |

`references/Eclipse/shaders/lib/bayer_matrix.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `bayerDither` | 1 | `math.ogxEclipseBayerDither` | 已迁入 | 承接算法：数学与通用工具 |

`references/Eclipse/shaders/lib/bokeh.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rotate` | 472 | `math.ogxRotate2` | 已迁入 | 承接算法：数学与通用工具 |

`references/Eclipse/shaders/lib/climate_settings.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `YearCycleColor` | 19 | `weather/weather.ogxYearCycleColor` | 已迁入 | 同名迁移：天气与季节 |
| `BiomeFogDensity` | 135 | `fog/fog.ogxBiomeFogDensityEclipse` | 已迁入 | 承接算法：雾与空气透视 |
| `BiomeVLFogColors` | 151 | — | MC 专用 | 函数体直接读取宿主符号：`biome` |
| `FogDensities` | 173 | `weather/weather.ogxFogDensities` | 已迁入 | 同名迁移：天气与季节 |

`references/Eclipse/shaders/lib/color_dither.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `nrand` | 2 | `noise.ogxWhiteNoise` | 已迁入 | 承接算法：程序化噪声 |
| `triangWhiteNoise` | 7 | `noise.ogxTriangleNoise` | 已迁入 | 承接算法：程序化噪声 |
| `fp10Dither` | 19 | `post/post.ogxDitherFloat` | 已迁入 | 同一浮点抖动；调用时尾数位数取 (6,6,5) |
| `fp16Dither` | 26 | `post/post.ogxDitherFloat` | 已迁入 | 同一浮点抖动；调用时尾数位数取 10 |
| `int8Dither` | 33 | `post/post.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 8 |
| `int10Dither` | 38 | `post/post.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 10 |
| `int16Dither` | 43 | `post/post.ogxDitherFixed` | 已迁入 | 同一定点抖动；调用时位数取 16 |

`references/Eclipse/shaders/lib/color_transforms.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toLinear` | 2 | `color.ogxSrgbToLinear` | 已迁入 | 承接算法：颜色与色调映射 |
| `luma` | 6 | `color.ogxLuminanceRec601` | 已迁入 | 承接算法：颜色与色调映射 |
| `LinearTosRGB` | 22 | `color.ogxLinearToSrgb` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_Hejl2015` | 34 | `color.ogxTonemapHejl` | 已迁入 | 承接算法：颜色与色调映射 |
| `HableTonemap` | 41 | `color.ogxTonemapHable` | 已迁入 | 承接算法：颜色与色调映射 |
| `reinhard` | 66 | `color.ogxTonemapReinhard` | 已迁入 | 承接算法：颜色与色调映射 |
| `ACESFilm` | 70 | `color.ogxTonemapAcesFilm` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Lottes` | 88 | `color.ogxTonemapLottes` | 已迁入 | 承接算法：颜色与色调映射 |
| `curve` | 106 | `color.ogxAgxContrast` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Uchimura_Modified` | 109 | `color.ogxTonemapUchimuraModified` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Uchimura` | 132 | `color.ogxTonemapUchimuraExp` | 已迁入 | 承接算法：颜色与色调映射 |
| `Tonemap_Xonk` | 166 | `color.ogxTonemapXonk` | 已迁入 | 同名曲线：先抬 1.3 次幂，再除以自身加 0.333 |
| `Tonemap_Full_Reinhard` | 174 | `color.ogxTonemapReinhardFull` | 已迁入 | 承接算法：颜色与色调映射 |
| `Full_Reinhard_Edit` | 182 | `color.ogxTonemapReinhardEdit` | 已迁入 | 承接算法：颜色与色调映射 |
| `agxDefaultContrastApprox` | 228 | `color.ogxAgxContrast` | 已迁入 | 承接算法：颜色与色调映射 |
| `agxLook` | 241 | `color.ogxAgxLook` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX` | 255 | `color.ogxToneMapAgx` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX_minimal` | 297 | `color.ogxToneMapAgxMinimal` | 已迁入 | 承接算法：颜色与色调映射 |
| `ToneMap_AgX_minimal_merlin` | 337 | `color.ogxToneMapAgxMerlin` | 已迁入 | 承接算法：颜色与色调映射 |
| `reinhard_jodie` | 386 | `color.ogxTonemapReinhardJodie` | 已迁入 | 承接算法：颜色与色调映射 |
| `no_tonemapper` | 400 | `color.ogxTonemapNone` | 已迁入 | 承接算法：颜色与色调映射 |

`references/Eclipse/shaders/lib/diffuse_lighting.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `swapperlinZ2` | 2 | — | MC 专用 | 交换两个线性深度的辅助函数，输入来自宿主深度缓冲 |
| `SSRT_Handlight_Shadows` | 6 | — | MC 专用 | 函数体直接读取宿主符号：`depthtex`、`normals`、`gbufferModelView` |
| `GetHandLight` | 74 | `surface.ogxHandLight` | 已迁入 | 承接算法：方块光与材质 |
| `doBlockLightLighting` | 104 | — | MC 专用 | 函数体直接读取宿主符号：`normals`、`heldItemId`、`lightColor`、`gl_FragCoord` |
| `doIndirectLighting` | 282 | `surface.ogxDoIndirectLighting` | 已迁入 | 同名迁移：方块光与材质 |
| `calculateFlashlight` | 304 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousModelView` |

`references/Eclipse/shaders/lib/end_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash31` | 23 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `hash11` | 30 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `iqint2` | 45 | `noise.ogxIntegerHash3` | 已迁入 | 同一 Inigo Quilez 整数哈希：三轮右移异或再乘 1103515245 |
| `hash` | 56 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `LightSourcePosition` | 69 | — | MC 专用 | 函数体直接读取宿主符号：`colortex` |
| `densityAtPosFog` | 95 | `weather/weather.ogxStormNoise` | 已迁入 | 承接算法：天气与季节 |
| `SwirlAroundOrigin` | 110 | `fog/fog.ogxEndVortexSwirl` | 已迁入 | 承接算法：雾与空气透视 |
| `VolumeBounds` | 122 | — | MC 专用 | 末地雾体积边界，依赖末地主岛坐标与群系状态 |
| `fogShape` | 144 | `fog/fog.ogxEndVortexShape` | 已迁入 | 承接算法：雾与空气透视 |
| `endFogPhase` | 169 | `fog/fog.ogxEndVortexLightPhase` | 已迁入 | 承接算法：雾与空气透视 |
| `LightSourceColors` | 182 | — | MC 专用 | 末地雾的方块光源配色，依赖方块光照与群系表 |
| `LightSourceLighting` | 198 | `fog/fog.ogxEndVortexLighting` | 已迁入 | 承接算法：雾与空气透视 |
| `phaseEND` | 215 | `fog/fog.ogxEndFogPhaseEclipse` | 已迁入 | 承接算法：雾与空气透视 |
| `GetVolumetricFog` | 219 | `fog/fog.ogxEndVortexFog` | 已迁入 | 承接算法：雾与空气透视 |
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
| `R2_samples` | 1 | `math.ogxR2Sample` | 已迁入 | 同一 R2 低差异序列与同一组黄金比例常数 |
| `cosineHemisphereSample` | 6 | `math.ogxCosineHemisphere` | 已迁入 | 承接算法：数学与通用工具 |
| `TangentToWorld` | 16 | `math.ogxTangentBasis` | 已迁入 | 承接算法：数学与通用工具 |
| `SpiralSample` | 23 | `math.ogxSpiralSample` | 已迁入 | 承接算法：数学与通用工具 |
| `BilateralUpscale_SSAO` | 43 | `gi/gi.ogxBilateralUpscale` | 已迁入 | 四邻域按深度差剔除后升采样；参考实现的固定步长换成分辨率倍数参数 |
| `rayTrace_GI` | 99 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `convertHandDepth_3` | 145 | `math.ogxConvertHandDepth3` | 已迁入 | 承接算法：数学与通用工具 |
| `RT_alternate` | 153 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex`、`gbufferModelView`、`viewWidth`、`viewHeight` |
| `ApplySSRT` | 219 | `reflection/reflection.ogxReflectionSceneColor` | 已迁入 | 承接算法：屏幕空间反射 |

`references/Eclipse/shaders/lib/lightning_stuff.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `Iris_Lightningflash` | 8 | `fog/volume.ogxFogLightning` | 已迁入 | 承接算法：体积雾 |
| `Iris_Lightningflash_VLcloud` | 31 | `cloud/volume.ogxCumulusLightning` | 已迁入 | 承接算法：体积云步进 |
| `Iris_Lightningflash_VLfog` | 44 | `fog/volume.ogxFogLightning` | 已迁入 | 承接算法：体积雾 |

`references/Eclipse/shaders/lib/lpv_common.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `GetLpvPosition` | 12 | `camera.ogxGetLpvPosition` | 已迁入 | 同名迁移：camera |

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
| `cloudVol` | 15 | `fog/fog.ogxNetherFogCloudVolume` | 已迁入 | 承接算法：雾与空气透视 |

`references/Eclipse/shaders/lib/overworld_fog.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `phaseRayleigh` | 54 | `math.ogxRayleighPhaseElek` | 已迁入 | 承接算法：数学与通用工具 |
| `fogPhase` | 59 | `fog/fog.ogxFogPhase` | 已迁入 | 同名迁移：雾与空气透视 |

`references/Eclipse/shaders/lib/projections.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `toClipSpace3` | 14 | `camera.ogxToClipSpace3` | 已迁入 | 同名迁移：camera |
| `toScreenSpace` | 18 | `camera.ogxToScreenSpace` | 已迁入 | 同名迁移：camera |
| `toScreenSpaceVector` | 25 | `camera.ogxToScreenSpaceVector` | 已迁入 | 同名迁移：camera |
| `toWorldSpace` | 32 | `camera.ogxToWorldSpace` | 已迁入 | 同名迁移：camera |
| `toWorldSpaceCamera` | 37 | `camera.ogxToWorldSpaceCamera` | 已迁入 | 同名迁移：camera |
| `toShadowSpace` | 42 | `camera.ogxToShadowSpace` | 已迁入 | 同名迁移：camera |
| `toShadowSpaceProjected` | 52 | `camera.ogxToShadowSpaceProjected` | 已迁入 | 同名迁移：camera |

`references/Eclipse/shaders/lib/ripples.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash12` | 19 | `noise.ogxHash12` | 已迁入 | 同名迁移：程序化噪声 |
| `hash22` | 26 | `noise.ogxHash22` | 已迁入 | 同名迁移：程序化噪声 |
| `ripples` | 34 | `water.ogxRainRipples` | 已迁入 | 承接算法：水面与海洋 |

`references/Eclipse/shaders/lib/scene_controller.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `applySceneControllerParameters` | 147 | — | MC 专用 | 把场景控制器的选项写入全局，读取天光与天气等宿主状态 |

`references/Eclipse/shaders/lib/sky_gradient.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `drawSun` | 3 | `atmosphere/atmosphere.ogxSunDisc` | 已迁入 | 承接算法：天空散射与日月星 |
| `sphereMap` | 10 | `atmosphere/atmosphere.ogxSkyProject` | 已迁入 | 承接算法：天空散射与日月星 |
| `drawMoon` | 27 | `atmosphere/atmosphere.ogxMoonDiscDefault` | 已迁入 | 承接算法：天空散射与日月星 |
| `drawRealMoon` | 58 | `atmosphere/atmosphere.ogxMoonDiscReal` | 已迁入 | 承接算法：天空散射与日月星 |
| `w0` | 69 | `math.ogxCubicWeight0` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w1` | 74 | `math.ogxCubicWeight1` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w2` | 79 | `math.ogxCubicWeight2` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `w3` | 84 | `math.ogxCubicWeight3` | 已迁入 | 同一三次 B 样条权重，常数逐项相同 |
| `g0` | 89 | `math.ogxCubicWeightLow` | 已迁入 | 同一左侧两个权重之和 |
| `g1` | 94 | `math.ogxCubicWeightHigh` | 已迁入 | 同一右侧两个权重之和 |
| `h0` | 99 | `math.ogxCubicOffsetLow` | 已迁入 | 同一合并采样点的左偏移 |
| `h1` | 104 | `math.ogxCubicOffsetHigh` | 已迁入 | 同一合并采样点的右偏移 |
| `texture_bicubic` | 109 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `texture_bicubic_offset` | 133 | `math.ogxBicubicTexture` | 已迁入 | 承接算法：数学与通用工具 |
| `sphereToCarte` | 166 | `atmosphere/atmosphere.ogxSkyEquirect` | 已迁入 | 同一经纬投影：方向转零到一的贴图坐标 |
| `skyFromTex` | 171 | `atmosphere/model.ogxAtmoSkyRadiance` | 已迁入 | 承接算法：预计算大气查表 |
| `skyCloudsFromTex` | 186 | `atmosphere/atmosphere.ogxSkyCloudsFromTex` | 已迁入 | 同名迁移：天空散射与日月星 |
| `skyCloudsFromTexBLUR` | 195 | `atmosphere/atmosphere.ogxSkyCloudsFromTex` | 已迁入 | 参考实现的 scaler 参数未参与计算，函数体与 skyCloudsFromTex 相同，库只保留一份 |
| `skyCloudsFromTexLOD` | 210 | `atmosphere/atmosphere.ogxSkyCloudsFromTexLod` | 已迁入 | 同名迁移：天空散射与日月星 |
| `volumetricsFromTex` | 229 | `fog/volume.ogxFogCloudBicubic` | 已迁入 | 承接算法：体积雾 |

`references/Eclipse/shaders/lib/specular.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `invLinZ` | 1 | `reflection/reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `DH_invLinZ` | 5 | `reflection/reflection.ogxReflectionDhToScreenDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `linZ` | 9 | `reflection/reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `linZ2` | 13 | `reflection/reflection.ogxReflectionLinearDepth` | 已迁入 | 承接算法：屏幕空间反射 |
| `frisvad` | 17 | `math.ogxTangentBasis` | 已迁入 | 承接算法：数学与通用工具 |
| `CoordBase` | 29 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `R2_Sample` | 35 | `math.ogxR2Sample` | 已迁入 | 承接算法：数学与通用工具 |
| `fma2` | 40 | `math.ogxFma2` | 已迁入 | 承接算法：数学与通用工具 |
| `SampleVNDFGGX` | 44 | `reflection/reflection.ogxSampleGgxVndf` | 已迁入 | 承接算法：屏幕空间反射 |
| `GGX` | 75 | `math.ogxDistributionGGX` | 已迁入 | 承接算法：数学与通用工具 |
| `shlickFresnelRoughness` | 95 | `math.ogxFresnelSchlick` | 已迁入 | 承接算法：数学与通用工具 |
| `invertLinearizeDepthFast` | 108 | — | MC 专用 | 按 Iris 的深度约定反解线性深度，使用 gbufferProjectionInverse |
| `rayTraceSpeculars` | 113 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`depthtex` |
| `toScreenSpace2` | 248 | `camera.ogxToScreenSpace2` | 已迁入 | 同名迁移：camera |
| `GetVoxelBlock` | 262 | — | MC 专用 | 按坐标读取体素方块编号，依赖 Iris 自定义图像 |
| `voxelIndex` | 266 | `voxel/voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `voxelNormalIndex` | 270 | — | MC 专用 | 体素法线索引，依赖方块面表与影像编码 |
| `decodeVec2_16` | 274 | `color.ogxDecodeVec2x16` | 已迁入 | 同一组常数把打包值拆成两个十六位分量，不依赖浮点位模式 |
| `GetVoxelData` | 280 | — | MC 专用 | 读体素影像数据，依赖自定义图像布局 |
| `GetTexCoord` | 290 | — | MC 专用 | 体素影像的纹理坐标换算，依赖自定义图像布局 |
| `getVoxelEmission` | 294 | — | MC 专用 | 从体素影像读取发光，依赖自定义图像与方块映射 |
| `voxelEmission` | 300 | — | MC 专用 | 体素发光编码，依赖方块表 |
| `CleanVoxelSample` | 308 | — | MC 专用 | 清洗体素采样，依赖自定义图像与材质掩码 |
| `ComputeVoxelShadowMap` | 331 | `voxel/voxel.ogxVoxelWriteIndex` | 已迁入 | 承接算法：体素反射 |
| `planeIntersect` | 441 | `math.ogxRayPlaneIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `AABBintersection` | 459 | `math.ogxRayBoxIntersection` | 已迁入 | 承接算法：数学与通用工具 |
| `AABBintersection2` | 488 | `math.ogxRayBoxRange` | 已迁入 | 承接算法：数学与通用工具 |
| `sortIntersectionCutout` | 514 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
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
| `photonicsReflectionShading` | 1937 | — | MC 专用 | 函数体直接读取宿主符号：`eyeBrightness`、`cameraPosition` |
| `photonicsReflection` | 2011 | — | MC 专用 | 函数体直接读取宿主符号：`isEyeInWater`、`nightVision`、`cameraPosition` |
| `getEnvironmentReflections` | 2131 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`isEyeInWater`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView`、`gbufferPreviousProjection`、`gbufferPreviousModelView` |
| `getReflectionVisibility` | 2235 | — | MC 专用 | 读取阴影与深度缓冲判断反射可见度，依赖 shadowtex/depthtex |
| `specularReflections` | 2283 | — | MC 专用 | 函数体直接读取宿主符号：`colortex`、`heldItemId`、`isEyeInWater`、`lightColor`、`cameraPosition`、`previousCameraPosition`、`gbufferModelView` |

`references/Eclipse/shaders/lib/stars.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `hash13` | 5 | `noise.ogxHash13` | 已迁入 | 承接算法：程序化噪声 |
| `NoisyStarField` | 13 | `atmosphere/atmosphere.ogxStarNoisyField` | 已迁入 | 承接算法：天空散射与日月星 |
| `StableStarField` | 22 | `atmosphere/atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |
| `hash12_alt` | 46 | `noise.ogxHash12` | 已迁入 | 承接算法：程序化噪声 |
| `starTemp` | 48 | `atmosphere/atmosphere.ogxStarTemperature` | 已迁入 | 承接算法：天空散射与日月星 |
| `starplane` | 52 | `atmosphere/atmosphere.ogxStarPlane` | 已迁入 | 同名迁移：天空散射与日月星 |
| `starbox` | 82 | `atmosphere/atmosphere.ogxStarBox` | 已迁入 | 同名迁移：天空散射与日月星 |
| `stars` | 93 | `atmosphere/atmosphere.ogxStarsStable` | 已迁入 | 承接算法：天空散射与日月星 |

`references/Eclipse/shaders/lib/texFiltering.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `smoothfilter` | 1 | `sampling.ogxSmoothFilter` | 已迁入 | 同名迁移：采样与抖动 |
| `shadowsmoothfilter` | 11 | `sampling.ogxShadowSmoothFilter` | 已迁入 | 同名迁移：采样与抖动 |

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
| `blackbody` | 95 | `color.ogxBlackbodyEclipse` | 已迁入 | 承接算法：颜色与色调映射 |
| `calculateHardShadows` | 111 | — | MC 专用 | 硬阴影比较，直接采样 shadowtex |
| `genUnitVector` | 117 | `math.ogxCosineHemisphere` | 已迁入 | 承接算法：数学与通用工具 |
| `cartToSphere` | 127 | `math.ogxCircleMap` | 已迁入 | 承接算法：数学与通用工具 |
| `sphereToCart` | 134 | `atmosphere/atmosphere.ogxSkyUnproject` | 已迁入 | 承接算法：天空散射与日月星 |
| `getRotMat` | 139 | `math.ogxRotateMatrix` | 已迁入 | 承接算法：数学与通用工具 |
| `rsi` | 162 | `math.ogxRaySphereHit` | 已迁入 | 同一球面求交算式，未命中时同样返回两个负一 |
| `HaltonSeq3` | 172 | `sampling.ogxHalton3` | 已迁入 | 承接算法：采样与抖动 |
| `HaltonSeq2` | 185 | `sampling.ogxHalton2` | 已迁入 | 承接算法：采样与抖动 |
| `customRotation` | 199 | — | MC 专用 | 函数体直接读取宿主符号：`worldTime` |

`references/Eclipse/shaders/lib/volumetricClouds.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `rand` | 49 | `noise.ogxWhiteNoise` | 已迁入 | 承接算法：程序化噪声 |
| `getRainDensity` | 55 | `cloud/cloud.ogxCloudRainDensity` | 已迁入 | 承接算法：云形状、光照与云影 |
| `densityAtPos` | 62 | `cloud/cloud.ogxCloudDensityAtPos` | 已迁入 | 承接算法：云形状、光照与云影 |
| `hash2` | 79 | `noise.ogxHash22` | 已迁入 | 承接算法：程序化噪声 |
| `normalize_hash` | 85 | `noise.ogxHash22` | 已迁入 | 承接算法：程序化噪声 |
| `perlin_gradient` | 89 | `noise.ogxPerlinGradient2` | 已迁入 | 承接算法：程序化噪声 |
| `curl2D` | 113 | `noise.ogxCurl2D` | 已迁入 | 同名迁移：程序化噪声 |
| `getCloudShape` | 118 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`rainStrength` |
| `getCumulonimbusShape` | 288 | — | MC 专用 | 函数体直接读取宿主符号：`noisetex`、`cameraPosition` |
| `getLightningPosition` | 377 | — | MC 专用 | 函数体直接读取宿主符号：`cameraPosition` |
| `getPlanetShadow` | 404 | `planet.ogxPlanetEnd` | 已迁入 | 承接算法：末地行星 |
| `GetCloudShadow` | 412 | — | MC 专用 | 函数体直接读取宿主符号：lightningBoltPosition、sunElevation；云层高度来自编译期配置 CloudLayer0_height 等 |
| `getRayOrigin` | 464 | — | MC 专用 | 体积云光线起点，依赖相机位置与视场内插 |
| `phaseCloud` | 491 | `cloud/cloud.ogxCloudPhaseEclipse` | 已迁入 | 承接算法：云形状、光照与云影 |
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
| `PopulateShadowVoxel` | 89 | — | MC 专用 | 函数体直接读取宿主符号：`mc_Entity`、`entityId`、`blockEntityId`、`blockEntity` |

`references/Eclipse/shaders/lib/waterBump.glsl`

| 函数 | 行 | 承接 | 状态 | 证据 |
| --- | --- | --- | --- | --- |
| `waterCaustics` | 9 | `water.ogxWaterCaustics` | 已迁入 | 同名迁移：水面与海洋 |
| `getWaterHeightmap` | 32 | `water.ogxWaterBumpHeightmap` | 已迁入 | 承接算法：水面与海洋 |
| `getWaveNormal` | 49 | `water.ogxWaterBumpNormal` | 已迁入 | 承接算法：水面与海洋 |

## 缺口清单

共 0 个，按参考实现的行数从多到少排列。

| 函数 | 参考位置 | 行数 | 参考做什么 |
| --- | --- | --- | --- |

## 重新生成

```text
python omni-gfx/build.py parity
```
