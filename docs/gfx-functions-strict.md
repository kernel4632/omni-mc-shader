# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`，字段名固定为 ASCII。

## 结论

- 参考函数共 505 个；算法函数 446 个。
- exact：272 个；approximate：113 个；mc_glue：59 个；missing：61 个。
- exact 覆盖率（按算法函数）：61.0%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 155 | 55 | 13 | 17 |
| Eclipse | 117 | 58 | 46 | 44 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 当前承接 | 差异 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `HeldLighting` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/BasicFounctions/Blocklight.glsl:162` |
| `TorchSpecularHighlight` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/BasicFounctions/Blocklight.glsl:283` |
| `ClampRadius` | iterationT | approximate | `atmosphere.ogxClampRadius` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:40 -> omni-gfx/src/atmosphere.slang:341` |
| `RenderSunDisc` | iterationT | approximate | `atmosphere.ogxSunDisc` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:48 -> omni-gfx/src/atmosphere.slang:258` |
| `RenderMoonDisc` | iterationT | approximate | `atmosphere.ogxMoonDiscReal` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:60 -> omni-gfx/src/atmosphere.slang:458` |
| `RenderMoonDiscReflection` | iterationT | approximate | `atmosphere.ogxMoonDiscReflection` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:70 -> omni-gfx/src/atmosphere.slang:471` |
| `DistanceToTopAtmosphereBoundary` | iterationT | approximate | `atmosphere.ogxAtmosphereDistanceToTop` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:85 -> omni-gfx/src/atmosphere.slang:70` |
| `DistanceToBottomAtmosphereBoundary` | iterationT | approximate | `atmosphere.ogxAtmosphereDistanceToGround` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:93 -> omni-gfx/src/atmosphere.slang:83` |
| `RayIntersectsGround` | iterationT | approximate | `atmosphere.ogxSphereRayIntersectsGround` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:101 -> omni-gfx/src/atmosphere.slang:282` |
| `GetScatteringTextureUvwzFromRMuMuSNu` | iterationT | approximate | `atmosphere_model.ogxAtmoScatteringUvwz` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:144 -> omni-gfx/src/atmosphere_model.slang:101` |
| `GetTransmittanceTextureUvFromRMu` | iterationT | approximate | `atmosphere_model.ogxAtmoTransmittanceUv` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:188 -> omni-gfx/src/atmosphere_model.slang:135` |
| `GetTransmittanceToTopAtmosphereBoundary` | iterationT | approximate | `atmosphere_model.ogxAtmoTransmittanceToTop` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:205 -> omni-gfx/src/atmosphere_model.slang:149` |
| `GetTransmittance` | iterationT | approximate | `atmosphere_model.ogxAtmoTransmittance` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:217 -> omni-gfx/src/atmosphere_model.slang:159` |
| `GetTransmittanceToSun` | iterationT | approximate | `atmosphere_model.ogxAtmoTransmittanceToSun` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:239 -> omni-gfx/src/atmosphere_model.slang:171` |
| `GetExtrapolatedSingleMieScattering` | iterationT | approximate | `atmosphere_model.ogxAtmoExtrapolatedMie` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:257 -> omni-gfx/src/atmosphere_model.slang:182` |
| `GetSunAndSkyIrradiance` | iterationT | approximate | `atmosphere_model.ogxAtmoSunSkyIrradiance` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/PrecomputedAtmosphere.glsl:325 -> omni-gfx/src/atmosphere_model.slang:219` |
| `VariablePenumbraShadow` | iterationT | approximate | `shadow.ogxVariablePenumbraShadow` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl:3 -> omni-gfx/src/shadow.slang:244` |
| `ScreenSpaceShadow` | iterationT | approximate | `shadow.ogxScreenSpaceShadow` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl:158 -> omni-gfx/src/shadow.slang:102` |
| `CalculateWaterCaustics` | iterationT | approximate | `water.ogxWaterCaustics` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/Sunlight_Shadow.glsl:257 -> omni-gfx/src/water.slang:349` |
| `RGB_To_YCoCg` | iterationT | approximate | `antialias.ogxRgbToYCoCg` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:19 -> omni-gfx/src/antialias.slang:20` |
| `SampleCurrDepthFetchClosest3x3` | iterationT | approximate | `antialias.ogxTaaSampleCurrent` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:81 -> omni-gfx/src/antialias.slang:101` |
| `SampleDepthDHFetch` | iterationT | approximate | `antialias.ogxTaaPrevDepthFetch` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:213 -> omni-gfx/src/antialias.slang:154` |
| `SampleCurrDepthDHFetchClosest3x3` | iterationT | approximate | `antialias.ogxTaaFetchCurrent` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:217 -> omni-gfx/src/antialias.slang:115` |
| `CalculateCameraVelocity` | iterationT | approximate | `gi.ogxGiCameraVelocity` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:231 -> omni-gfx/src/gi.slang:300` |
| `main` | iterationT | mc_glue | — | 就绪：程序入口，只负责阶段组合 | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:331` |
| `BlueNoise` | iterationT | approximate | `sampling.ogxBlueNoise` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TemporalNoise.glsl:3 -> omni-gfx/src/sampling.slang:29` |
| `BlueNoiseTemproal` | iterationT | approximate | `sampling.ogxBlueNoiseTemporal` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TemporalNoise.glsl:7 -> omni-gfx/src/sampling.slang:35` |
| `BayerTemproal` | iterationT | approximate | `sampling.ogxBayerTemporal` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/BasicFounctions/TemporalNoise.glsl:11 -> omni-gfx/src/sampling.slang:43` |
| `GetGbufferData` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/GbufferData.glsl:131` |
| `CalculateMasks` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/GbufferData.glsl:208` |
| `FixParticleMask` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/GbufferData.glsl:250` |
| `CloudShadowFromTex` | iterationT | approximate | `cloud.ogxCloudShadowSample` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/CloudShadow.glsl:28 -> omni-gfx/src/cloud.slang:370` |
| `GetFocus` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl:19` |
| `DepthOfField` | iterationT | approximate | `post.ogxDepthOfField` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/DOF.glsl:76 -> omni-gfx/src/post.slang:239` |
| `CalculateStars` | iterationT | approximate | `atmosphere.ogxStarsStable` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:12 -> omni-gfx/src/atmosphere.slang:433` |
| `ppss` | iterationT | approximate | `atmosphere.ogxPlanetBrdf` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:57 -> omni-gfx/src/atmosphere.slang:603` |
| `CalculateCloudFBM` | iterationT | approximate | `fog.ogxCloudFbm` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:279 -> omni-gfx/src/fog.slang:198` |
| `CalculateCloudFBM_LQ` | iterationT | approximate | `noise.ogxFbm3` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:297 -> omni-gfx/src/noise.slang:156` |
| `BlackHole_AccretionDisc_Stars` | iterationT | approximate | `accretion.ogxAccretionDisc` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:320 -> omni-gfx/src/accretion.slang:23` |
| `BlackHole_AccretionDisc_Reflection` | iterationT | approximate | `accretion.ogxAccretionDisc` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:429 -> omni-gfx/src/accretion.slang:23` |
| `EndFog` | iterationT | approximate | `fog.ogxEndFogDensity` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:531 -> omni-gfx/src/fog.slang:355` |
| `LensFlare` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/LensGlareFlare.glsl:61` |
| `MotionBlur` | iterationT | approximate | `post.ogxMotionBlur` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl:49 -> omni-gfx/src/post.slang:340` |
| `title` | iterationT | mc_glue | — | 就绪：标题计数与屏幕文字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl:100` |
| `GetExposureTiles` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl:167` |
| `HenyeyGreenstein` | iterationT | approximate | `cloud.ogxHenyeyGreenstein` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl:3 -> omni-gfx/src/cloud.slang:210` |
| `CloudLighting` | iterationT | approximate | `cloud_volume.ogxCumulusLighting` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl:73 -> omni-gfx/src/cloud_volume.slang:134` |
| `CloudShadowTex` | iterationT | approximate | `cloud.ogxCloudShadowSample` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl:212 -> omni-gfx/src/cloud.slang:370` |
| `physics_waveNormal` | iterationT | approximate | `water.ogxOceanWaveNormal` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/PhysicsOceans.glsl:120 -> omni-gfx/src/water.slang:476` |
| `PlanarClouds` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/PlanarClouds.glsl:106` |
| `SevenSegment` | iterationT | mc_glue | — | 就绪：调试叠加字形表，只服务屏幕数字 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:48` |
| `DecimalPoint` | iterationT | mc_glue | — | 就绪：调试叠加小数点定位 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:93` |
| `PrintFloat` | iterationT | mc_glue | — | 就绪：屏幕调试数字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:99` |
| `PrintUintBinary` | iterationT | mc_glue | — | 就绪：屏幕调试二进制，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:218` |
| `AtrousWaveletFilter` | iterationT | approximate | `reflection.ogxReflectionAtrousFilter` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/Reflections/ReflectionFilter.glsl:3 -> omni-gfx/src/reflection.slang:226` |
| `GetRainNormal` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/Ripple.glsl:33` |
| `FogDensity` | iterationT | approximate | `fog.ogxFogDensity` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl:34 -> omni-gfx/src/fog.slang:50` |
| `VolumetricFog` | iterationT | approximate | `fog_volume.ogxVolumetricFog` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl:69 -> omni-gfx/src/fog_volume.slang:164` |
| `simpleScattering` | iterationT | approximate | `atmosphere.ogxAtmosphereSky` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl:275 -> omni-gfx/src/atmosphere.slang:165` |
| `LandAtmosphericScattering` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/IndividualFounctions/VolumetricFog.glsl:300` |
| `AgxDefaultContrastApprox` | iterationT | approximate | `color.ogxAgxContrast` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Programs/Final.glsl:55 -> omni-gfx/src/color.slang:77` |
| `AgX` | iterationT | approximate | `color.ogxAgx` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Programs/Final.glsl:59 -> omni-gfx/src/color.slang:94` |
| `None` | iterationT | approximate | `color.ogxTonemapNone` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Programs/Final.glsl:80 -> omni-gfx/src/color.slang:112` |
| `MergeBloom` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Final.glsl:84` |
| `GetExposureValue` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Final.glsl:177` |
| `Fxaa` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Final.glsl:481` |
| `DH_noise` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Gbuffers/DH_Terrain_FS.glsl:32` |
| `end_portal_layer` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Gbuffers/Entities_FS.glsl:91` |
| `SampleAnisotropic` | iterationT | missing | — | no receiving function and no glue justification | `references/iterationT/shaders/Lib/Programs/Gbuffers/Terrain_FS.glsl:57` |
| `ViewPos_From_ScreenPos` | iterationT | approximate | `gi.ogxGiViewPos` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:1 -> omni-gfx/src/gi.slang:75` |
| `ViewPos_From_ScreenPos_Raw` | iterationT | approximate | `gi.ogxGiViewPos` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:10 -> omni-gfx/src/gi.slang:75` |
| `ScreenPos_From_ViewPos` | iterationT | approximate | `shadow.ogxShadowScreenPos` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:16 -> omni-gfx/src/shadow.slang:59` |
| `ScreenPos_From_ViewPos_Raw` | iterationT | mc_glue | — | 就绪：屏幕坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:25` |
| `ScreenDepth_From_LinearDepth` | iterationT | approximate | `post.ogxScreenDepthFromLinearDepth` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:35 -> omni-gfx/src/post.slang:181` |
| `ViewPos_From_ScreenPos_DH` | iterationT | approximate | `gi.ogxGiViewPosDh` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:42 -> omni-gfx/src/gi.slang:83` |
| `ViewPos_From_ScreenPos_Raw_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:51` |
| `ScreenPos_From_ViewPos_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:57` |
| `ScreenPos_From_ViewPos_Raw_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:66` |
| `LinearDepth_From_ScreenDepth_DH` | iterationT | approximate | `reflection.ogxReflectionDhToScreenDepth` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:71 -> omni-gfx/src/reflection.slang:68` |
| `ScreenDepth_From_LinearDepth_DH` | iterationT | mc_glue | — | 就绪：远景深度约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:76` |
| `ScreenDepth_From_DHScreenDepth` | iterationT | mc_glue | — | 就绪：远景深度约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:81` |
| `ShadowScreenPos_From_WorldPos_Distorted` | iterationT | approximate | `shadow.ogxShadowScreenPosDistorted` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:3 -> omni-gfx/src/shadow.slang:65` |
| `ShadowScreenPos_From_WorldPos` | iterationT | approximate | `shadow.ogxShadowScreenPos` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:14 -> omni-gfx/src/shadow.slang:59` |
| `ShadowScreenPos_From_WorldPos_WithoutZScaling` | iterationT | mc_glue | — | 就绪：阴影坐标约定 | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:21` |
| `DistortShadowScreenPos` | iterationT | approximate | `shadow.ogxDistortShadowPos` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:28 -> omni-gfx/src/shadow.slang:75` |
| `triNoise2d` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/aurora.glsl:53` |
| `aurora` | Eclipse | approximate | `atmosphere.ogxAurora` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/aurora.glsl:77 -> omni-gfx/src/atmosphere.slang:573` |
| `YearCycleColor` | Eclipse | approximate | `weather.ogxYearCycleColor` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/climate_settings.glsl:19 -> omni-gfx/src/weather.slang:100` |
| `BiomeVLFogColors` | Eclipse | mc_glue | — | 就绪：原版群系枚举到颜色表，非算法 | `references/Eclipse/shaders/lib/climate_settings.glsl:151` |
| `fp10Dither` | Eclipse | approximate | `post.ogxDitherFloat` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_dither.glsl:19 -> omni-gfx/src/post.slang:146` |
| `fp16Dither` | Eclipse | approximate | `post.ogxDitherFloat` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_dither.glsl:26 -> omni-gfx/src/post.slang:146` |
| `int8Dither` | Eclipse | approximate | `post.ogxDitherFixed` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_dither.glsl:33 -> omni-gfx/src/post.slang:154` |
| `int10Dither` | Eclipse | approximate | `post.ogxDitherFixed` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_dither.glsl:38 -> omni-gfx/src/post.slang:154` |
| `int16Dither` | Eclipse | approximate | `post.ogxDitherFixed` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_dither.glsl:43 -> omni-gfx/src/post.slang:154` |
| `curve` | Eclipse | approximate | `color.ogxAgxContrast` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/color_transforms.glsl:106 -> omni-gfx/src/color.slang:77` |
| `swapperlinZ2` | Eclipse | mc_glue | — | 就绪：只交换深度约定 | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:2` |
| `SSRT_Handlight_Shadows` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:6` |
| `doBlockLightLighting` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:104` |
| `calculateFlashlight` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:304` |
| `toScreenSpace_DH` | Eclipse | mc_glue | — | 就绪：远景模组投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:21` |
| `toClipSpace3_DH` | Eclipse | mc_glue | — | 就绪：远景模组投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:48` |
| `DH_shadowProjectionTweak` | Eclipse | mc_glue | — | 就绪：远景阴影投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:59` |
| `LightSourcePosition` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/end_fog.glsl:69` |
| `LightSourceColors` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/end_fog.glsl:182` |
| `GetEndFogShadow` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/end_fog.glsl:321` |
| `applyGameplayEffects` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/gameplay_effects.glsl:37` |
| `cosineHemisphereSample` | Eclipse | approximate | `math.ogxCosineHemisphere` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:6 -> omni-gfx/src/math.slang:662` |
| `TangentToWorld` | Eclipse | approximate | `math.ogxTangentBasis` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:16 -> omni-gfx/src/math.slang:471` |
| `BilateralUpscale_SSAO` | Eclipse | approximate | `gi.ogxBilateralUpscale` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:43 -> omni-gfx/src/gi.slang:56` |
| `rayTrace_GI` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:99` |
| `RT_alternate` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:153` |
| `ApplySSRT` | Eclipse | approximate | `reflection.ogxReflectionSceneColor` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:219 -> omni-gfx/src/reflection.slang:171` |
| `Iris_Lightningflash` | Eclipse | approximate | `fog_volume.ogxFogLightning` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/lightning_stuff.glsl:8 -> omni-gfx/src/fog_volume.slang:133` |
| `Iris_Lightningflash_VLcloud` | Eclipse | approximate | `cloud_volume.ogxCumulusLightning` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/lightning_stuff.glsl:31 -> omni-gfx/src/cloud_volume.slang:121` |
| `Iris_Lightningflash_VLfog` | Eclipse | approximate | `fog_volume.ogxFogLightning` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/lightning_stuff.glsl:44 -> omni-gfx/src/fog_volume.slang:133` |
| `GetLpvPosition` | Eclipse | mc_glue | — | 就绪：世界坐标到光传播体积坐标约定 | `references/Eclipse/shaders/lib/lpv_common.glsl:12` |
| `fogPhase` | Eclipse | approximate | `fog.ogxFogPhase` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/overworld_fog.glsl:59 -> omni-gfx/src/fog.slang:59` |
| `project` | Eclipse | mc_glue | — | 就绪：矩阵投影约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:73` |
| `project_and_divide` | Eclipse | mc_glue | — | 就绪：矩阵投影约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:76` |
| `screen_to_view_space` | Eclipse | mc_glue | — | 就绪：屏幕到视空间约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:81` |
| `view_to_screen_space` | Eclipse | mc_glue | — | 就绪：视空间到屏幕约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:87` |
| `integrate_arc` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:104` |
| `calculate_maximum_horizon_angle` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:109` |
| `ambient_occlusion` | Eclipse | approximate | `gi.ogxGroundTruthAo` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:145 -> omni-gfx/src/gi.slang:108` |
| `toClipSpace3` | Eclipse | mc_glue | — | 就绪：裁剪空间约定 | `references/Eclipse/shaders/lib/projections.glsl:14` |
| `toScreenSpace` | Eclipse | mc_glue | — | 就绪：屏幕空间约定 | `references/Eclipse/shaders/lib/projections.glsl:18` |
| `toScreenSpaceVector` | Eclipse | mc_glue | — | 就绪：屏幕空间方向约定 | `references/Eclipse/shaders/lib/projections.glsl:25` |
| `toWorldSpace` | Eclipse | mc_glue | — | 就绪：世界空间约定 | `references/Eclipse/shaders/lib/projections.glsl:32` |
| `toWorldSpaceCamera` | Eclipse | mc_glue | — | 就绪：相机空间约定 | `references/Eclipse/shaders/lib/projections.glsl:37` |
| `toShadowSpace` | Eclipse | mc_glue | — | 就绪：阴影空间约定 | `references/Eclipse/shaders/lib/projections.glsl:42` |
| `toShadowSpaceProjected` | Eclipse | mc_glue | — | 就绪：阴影空间约定 | `references/Eclipse/shaders/lib/projections.glsl:52` |
| `calculateAtmosphere` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/ROBOBO_sky.glsl:95` |
| `applySceneControllerParameters` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/scene_controller.glsl:147` |
| `BiasShadowProjection` | Eclipse | approximate | `shadow.ogxApplyShadowBias` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/Shadow_Params.glsl:20 -> omni-gfx/src/shadow.slang:36` |
| `calcDistort` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/Shadow_Params.glsl:27` |
| `drawSun` | Eclipse | approximate | `atmosphere.ogxSunDisc` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:3 -> omni-gfx/src/atmosphere.slang:258` |
| `sphereMap` | Eclipse | approximate | `atmosphere.ogxSkyProject` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:10 -> omni-gfx/src/atmosphere.slang:504` |
| `drawMoon` | Eclipse | approximate | `atmosphere.ogxMoonDiscDefault` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:27 -> omni-gfx/src/atmosphere.slang:465` |
| `drawRealMoon` | Eclipse | approximate | `atmosphere.ogxMoonDiscReal` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:58 -> omni-gfx/src/atmosphere.slang:458` |
| `texture_bicubic` | Eclipse | approximate | `math.ogxBicubicTexture` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:109 -> omni-gfx/src/math.slang:605` |
| `texture_bicubic_offset` | Eclipse | approximate | `math.ogxBicubicTexture` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:133 -> omni-gfx/src/math.slang:605` |
| `sphereToCarte` | Eclipse | approximate | `atmosphere.ogxSkyEquirect` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:166 -> omni-gfx/src/atmosphere.slang:533` |
| `skyFromTex` | Eclipse | approximate | `atmosphere_model.ogxAtmoSkyRadiance` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:171 -> omni-gfx/src/atmosphere_model.slang:235` |
| `skyCloudsFromTex` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:186 -> omni-gfx/src/atmosphere.slang:552` |
| `skyCloudsFromTexBLUR` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:195 -> omni-gfx/src/atmosphere.slang:552` |
| `skyCloudsFromTexLOD` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTexLod` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:210 -> omni-gfx/src/atmosphere.slang:561` |
| `volumetricsFromTex` | Eclipse | approximate | `fog_volume.ogxFogCloudBicubic` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:229 -> omni-gfx/src/fog_volume.slang:79` |
| `frisvad` | Eclipse | approximate | `math.ogxTangentBasis` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:17 -> omni-gfx/src/math.slang:471` |
| `CoordBase` | Eclipse | approximate | `math.ogxCircleMap` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:29 -> omni-gfx/src/math.slang:100` |
| `SampleVNDFGGX` | Eclipse | approximate | `reflection.ogxSampleGgxVndf` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:44 -> omni-gfx/src/reflection.slang:23` |
| `GGX` | Eclipse | approximate | `math.ogxDistributionGGX` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:75 -> omni-gfx/src/math.slang:273` |
| `shlickFresnelRoughness` | Eclipse | approximate | `math.ogxFresnelSchlick` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:95 -> omni-gfx/src/math.slang:281` |
| `invertLinearizeDepthFast` | Eclipse | mc_glue | — | 就绪：深度约定 | `references/Eclipse/shaders/lib/specular.glsl:108` |
| `rayTraceSpeculars` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:113` |
| `toScreenSpace2` | Eclipse | mc_glue | — | 就绪：屏幕空间约定 | `references/Eclipse/shaders/lib/specular.glsl:248` |
| `GetVoxelBlock` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:262` |
| `voxelIndex` | Eclipse | approximate | `voxel.ogxVoxelWriteIndex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:266 -> omni-gfx/src/voxel.slang:136` |
| `voxelNormalIndex` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:270` |
| `GetVoxelData` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:280` |
| `GetTexCoord` | Eclipse | mc_glue | — | 就绪：纹理坐标约定 | `references/Eclipse/shaders/lib/specular.glsl:290` |
| `getVoxelEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:294` |
| `voxelEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:300` |
| `CleanVoxelSample` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:308` |
| `ComputeVoxelShadowMap` | Eclipse | approximate | `voxel.ogxVoxelWriteIndex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:331 -> omni-gfx/src/voxel.slang:136` |
| `planeIntersect` | Eclipse | approximate | `math.ogxRayPlaneIntersection` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:441 -> omni-gfx/src/math.slang:350` |
| `AABBintersection` | Eclipse | approximate | `math.ogxRayBoxIntersection` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:459 -> omni-gfx/src/math.slang:413` |
| `sortIntersectionCutout` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:514` |
| `sortIntersectionOpaque` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:540` |
| `fenceIntersection` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:552` |
| `fenceIntersection2` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:561` |
| `traceQuarterVoxel` | Eclipse | approximate | `voxel.ogxVoxelReflection` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:578 -> omni-gfx/src/voxel.slang:74` |
| `voxelReflection` | Eclipse | approximate | `voxel.ogxVoxelReflection` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:616 -> omni-gfx/src/voxel.slang:74` |
| `CleanPhotonicsSample` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1079` |
| `ComputePhotonicsShadowMap` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1102` |
| `trace_wsr` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1222` |
| `doBlockLightLightingVoxel` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1404` |
| `raymarchWSR_LPV` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1464` |
| `raymarchWSRfog` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1604` |
| `WSRwaterVolumetrics` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1798` |
| `getPhotonicsEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:1923` |
| `photonicsEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:1929` |
| `photonicsReflectionShading` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:1937` |
| `photonicsReflection` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:2011` |
| `getEnvironmentReflections` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:2131` |
| `getReflectionVisibility` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:2235` |
| `specularReflections` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:2283` |
| `hash13` | Eclipse | approximate | `noise.ogxHash13` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:5 -> omni-gfx/src/noise.slang:19` |
| `hash12_alt` | Eclipse | approximate | `noise.ogxHash12` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:46 -> omni-gfx/src/noise.slang:27` |
| `starplane` | Eclipse | approximate | `atmosphere.ogxStarPlane` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:52 -> omni-gfx/src/atmosphere.slang:400` |
| `starbox` | Eclipse | approximate | `atmosphere.ogxStarBox` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:82 -> omni-gfx/src/atmosphere.slang:422` |
| `stars` | Eclipse | approximate | `atmosphere.ogxStarsStable` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:93 -> omni-gfx/src/atmosphere.slang:433` |
| `beginText` | Eclipse | mc_glue | — | 就绪：调试文字叠加的初始化 | `references/Eclipse/shaders/lib/text_rendering.glsl:161` |
| `endText` | Eclipse | mc_glue | — | 就绪：调试文字叠加的合成 | `references/Eclipse/shaders/lib/text_rendering.glsl:175` |
| `printChar` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:179` |
| `printUnsignedInt` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:212` |
| `printInt` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:244` |
| `printFloat` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:249` |
| `printBool` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:269` |
| `printVec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:277` |
| `printVec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:282` |
| `printVec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:289` |
| `printIvec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:299` |
| `printIvec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:304` |
| `printIvec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:311` |
| `printUvec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:321` |
| `printUvec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:326` |
| `printUvec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:333` |
| `printLine` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:343` |
| `clampNormal` | Eclipse | approximate | `math.ogxNormalize` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/util.glsl:72 -> omni-gfx/src/math.slang:129` |
| `calculateHardShadows` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/util.glsl:111` |
| `cartToSphere` | Eclipse | approximate | `math.ogxCircleMap` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/util.glsl:127 -> omni-gfx/src/math.slang:100` |
| `sphereToCart` | Eclipse | approximate | `atmosphere.ogxSkyUnproject` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/util.glsl:134 -> omni-gfx/src/atmosphere.slang:478` |
| `customRotation` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/util.glsl:199` |
| `hash2` | Eclipse | approximate | `noise.ogxHash22` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:79 -> omni-gfx/src/noise.slang:36` |
| `normalize_hash` | Eclipse | approximate | `noise.ogxHash22` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:85 -> omni-gfx/src/noise.slang:36` |
| `perlin_gradient` | Eclipse | approximate | `noise.ogxPerlinGradient2` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:89 -> omni-gfx/src/noise.slang:45` |
| `curl2D` | Eclipse | approximate | `noise.ogxCurl2D` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:113 -> omni-gfx/src/noise.slang:65` |
| `getCloudShape` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:118` |
| `getCumulonimbusShape` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:288` |
| `getLightningPosition` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:377` |
| `getPlanetShadow` | Eclipse | approximate | `planet.ogxPlanetEnd` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:404 -> omni-gfx/src/planet.slang:22` |
| `GetCloudShadow` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:412` |
| `getRayOrigin` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:464` |
| `getCloudScattering` | Eclipse | approximate | `cloud.ogxCloudMarch` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:512 -> omni-gfx/src/cloud.slang:122` |
| `getCloudLighting` | Eclipse | approximate | `cloud.ogxCloudLight` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:578 -> omni-gfx/src/cloud.slang:97` |
| `raymarchCloud` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:628` |
| `GetVolumetricClouds` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:960` |
| `raymarchCloudSimple` | Eclipse | approximate | `cloud.ogxCloudMarch` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/volumetricClouds.glsl:1385 -> omni-gfx/src/cloud.slang:122` |
| `GetVolumetricCloudsSimple` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/volumetricClouds.glsl:1493` |
| `GetVoxelIndex` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/voxel_write.glsl:1` |
| `SetVoxelBlock` | Eclipse | mc_glue | — | 就绪：Minecraft 体素写入约定 | `references/Eclipse/shaders/lib/voxel_write.glsl:19` |
| `PopulateShadowVoxel` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/voxel_write.glsl:89` |
| `waterCaustics` | Eclipse | approximate | `water.ogxWaterCaustics` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/waterBump.glsl:9 -> omni-gfx/src/water.slang:349` |

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
