# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`。

## 结论

- 参考函数共 505 个；算法函数 423 个。
- exact：196 个；approximate：227 个；mc_glue：82 个；missing：0 个。
- exact 覆盖率（按算法函数）：46.3%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 113 | 106 | 21 | 0 |
| Eclipse | 83 | 121 | 61 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 参考签名 | 当前承接 | 差异 |
| --- | --- | --- | --- | --- | --- |
| `spotShape` | iterationT | approximate | `float spotShape(float)` | `surface.ogxSpotShape` | constants missing 32 |
| `TorchScreenSpaceShadow` | iterationT | approximate | `float TorchScreenSpaceShadow(float3, float3, float3, float3)` | `shadow.ogxScreenSpaceShadow` | constants missing 0.15, 0.85 |
| `HeldLighting` | iterationT | approximate | `float3 HeldLighting(float3, float3, float3, float, float3, bool)` | `heldlight.ogxHeldLighting` | constants missing 0.15, 0.85 |
| `NetherFogColor` | iterationT | approximate | `float4 NetherFogColor()` | `fog.ogxNetherBiomeFogColor` | constants missing 1 |
| `RenderMoonDisc` | iterationT | approximate | `float RenderMoonDisc(float3, float3)` | `atmosphere.ogxMoonDiscReal` | constants missing 5e-05, 100000 |
| `RenderMoonDiscReflection` | iterationT | approximate | `float RenderMoonDiscReflection(float3, float3)` | `atmosphere.ogxMoonDiscReflection` | constants extra 0, 2, 3 |
| `GetScatteringTextureUvwzFromRMuMuSNu` | iterationT | approximate | `float4 GetScatteringTextureUvwzFromRMuMuSNu(float, float, float, float, bool)` | `atmosphere_model.ogxAtmoScatteringUvwz` | constants missing 60, 875.671 |
| `GetTransmittanceTextureUvFromRMu` | iterationT | approximate | `float2 GetTransmittanceTextureUvFromRMu(float, float)` | `atmosphere_model.ogxAtmoTransmittanceUv` | constants missing 875.671 |
| `GetTransmittanceToTopAtmosphereBoundary` | iterationT | approximate | `float3 GetTransmittanceToTopAtmosphereBoundary(float, float)` | `atmosphere_model.ogxAtmoTransmittanceToTop` | constants missing 875.671 |
| `GetTransmittance` | iterationT | approximate | `float3 GetTransmittance(float, float, float, bool)` | `atmosphere_model.ogxAtmoTransmittance` | constants missing 875.671 |
| `GetTransmittanceToSun` | iterationT | approximate | `float3 GetTransmittanceToSun(float, float)` | `atmosphere_model.ogxAtmoTransmittanceToSun` | constants missing 875.671 |
| `GetCombinedScattering` | iterationT | approximate | `float3 GetCombinedScattering(float, float, float, float, bool, out float3)` | `atmosphere_model.ogxAtmoCombinedScattering` | constants missing 60, 875.671 |
| `GetSunAndSkyIrradiance` | iterationT | approximate | `float3 GetSunAndSkyIrradiance(float3, float3, float3, out float3, out float3, out float3)` | `atmosphere_model.ogxAtmoSunSkyIrradiance` | constants missing 0.0003, 875.671 |
| `GetSkyRadiance` | iterationT | approximate | `float3 GetSkyRadiance(float3, float3, float3, float3, bool, out float3, out bool)` | `atmosphere_model.ogxAtmoSkyRadiance` | samples ['sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing 0.0003, 60, 875.671 |
| `GetSkyRadianceToPoint` | iterationT | approximate | `float3 GetSkyRadianceToPoint(float3, float3, float3, float3, out float3)` | `atmosphere_model.ogxAtmoSkyRadianceToPoint` | constants missing 0.0003, 60, 875.671 |
| `VariablePenumbraShadow` | iterationT | approximate | `float3 VariablePenumbraShadow(float3, float3, float, float3, float, materialmask, out float3)` | `shadow.ogxVariablePenumbraShadow` | param count 7 != 30; samples ['fetch', 'sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample']; constants missing 0.0625, 1.32472, 1.61803, 2.39996, 6, 16, 64, 192; extra -0.737369, 0.15, 0.4, 0.6, 0.67549 |
| `ScreenSpaceShadow` | iterationT | approximate | `float ScreenSpaceShadow(float3, float3, float3, materialmask)` | `shadow.ogxSunScreenShadow` | param count 4 != 19; samples ['fetch', 'sample'] != ['sample', 'sample']; constants missing 0.06, 0.31831, 0.7, 0.85, 1.32472, 1.61803, 12, 64 |
| `GetWavesNormalFromTex` | iterationT | approximate | `float3 GetWavesNormalFromTex(float3)` | `water.ogxWavesNormalFromTex` | param count 1 != 7; constants missing 1.2 |
| `CalculateWaterCaustics` | iterationT | approximate | `float CalculateWaterCaustics(float3)` | `water.ogxWaterCaustics` | param count 1 != 12; samples ['fetch', 'sample'] != ['sample']; constants missing 1.2, 1.32472, 1.61803, 64 |
| `RGB_To_YCoCg` | iterationT | approximate | `float3 RGB_To_YCoCg(float3)` | `antialias.ogxRgbToYCoCg` | constants missing -0.25 |
| `SampleCurrColor` | iterationT | approximate | `float3 SampleCurrColor(float2)` | `antialias.ogxTaaSampleCurrent` | return vec3 != float4; param count 1 != 6; samples ['sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -0.25; extra 1, 2, 3 |
| `SampleCurrColorFetch` | iterationT | approximate | `float3 SampleCurrColorFetch(int2)` | `antialias.ogxTaaFetchCurrent` | return vec3 != float4; param count 1 != 4; constants missing -0.25; extra 1, 2, 3 |
| `SampleCurrColorBicubic` | iterationT | approximate | `float3 SampleCurrColorBicubic(float2)` | `antialias.ogxBicubicTexture4` | return vec3 != float4; param count 1 != 3; constants missing -0.25, 0.25 |
| `SamplePrevColor` | iterationT | approximate | `float3 SamplePrevColor(float2)` | `antialias.ogxTaaSamplePrevious` | return vec3 != float4; param count 1 != 6; samples ['sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -0.25; extra 16, 65535 |
| `SamplePrevDepthFetch` | iterationT | approximate | `float SamplePrevDepthFetch(int2)` | `antialias.ogxTaaPrevDepthFetch` | param count 1 != 3; samples ['fetch'] != ['fetch', 'fetch']; constants extra 16, 65535 |
| `SamplePrevDepthMinMax3x3` | iterationT | approximate | `float2 SamplePrevDepthMinMax3x3(float2)` | `antialias.ogxTaaPrevDepthMinmax` | param count 1 != 4; samples ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch'] != ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch']; constants extra 16, 65535 |
| `GetVariance3x3` | iterationT | approximate | `float3 GetVariance3x3(int2, float3, out float3, out float3)` | `antialias.ogxTaaVariance3x3` | param count 4 != 9; constants missing -0.25; extra 3 |
| `clipAABB` | iterationT | approximate | `float3 clipAABB(float3, float3, float3)` | `antialias.ogxClipAabb#2` | constants extra 1e-20 |
| `TemporalReprojection` | iterationT | approximate | `float4 TemporalReprojection(float2, float3, float)` | `antialias.ogxTaaReproject` | samples ['sample', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch']; constants missing -0.25 |
| `SampleDepthDHFetch` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `SampleCurrDepthDHFetchClosest3x3` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `CalculateCameraVelocity` | iterationT | approximate | `float3 CalculateCameraVelocity(out float, float)` | `gi.ogxGiCameraVelocity` | return vec3 != float2; param count 2 != 9; samples ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch'] != []; constants missing -1, 7, 8, 50 |
| `main` | iterationT | mc_glue | `—` | — | 就绪：程序入口，只负责阶段组合 |
| `SampleCurr` | iterationT | approximate | `float4 SampleCurr(float2)` | `antialias.ogxTaaSampleCurrent` | param count 1 != 6; samples ['sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -0.25 |
| `SampleCurrFetch` | iterationT | approximate | `float4 SampleCurrFetch(int2)` | `antialias.ogxTaaFetchCurrent` | param count 1 != 4; constants missing -0.25 |
| `SampleCurrBicubic` | iterationT | approximate | `float4 SampleCurrBicubic(float2)` | `antialias.ogxBicubicTexture4` | param count 1 != 3; constants missing -0.25, 0.25 |
| `SamplePreviousDepthBilinear` | iterationT | approximate | `float2 SamplePreviousDepthBilinear(float2)` | `antialias.ogxTaaPrevDepthBilinear` | param count 1 != 3 |
| `SamplePrevious` | iterationT | approximate | `float4 SamplePrevious(float2)` | `antialias.ogxTaaSamplePrevious` | param count 1 != 6; samples ['sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -0.25 |
| `BlueNoiseTemproal` | iterationT | approximate | `float2 BlueNoiseTemproal()` | `sampling.ogxBlueNoiseTemporal` | param count 0 != 3 |
| `BayerTemproal` | iterationT | approximate | `float BayerTemproal()` | `sampling.ogxBayerTemporal` | param count 0 != 2 |
| `VanillaFog` | iterationT | approximate | `void VanillaFog(inout float3, float)` | `fog.ogxVanillaFog` | constants missing 1.5, 4.5, 5, 15 |
| `CurveBlockLightSky` | iterationT | approximate | `float CurveBlockLightSky(float)` | `surface.ogxCurveBlockLightSky` | constants extra 0 |
| `CurveBlockLightTorch` | iterationT | approximate | `float CurveBlockLightTorch(float)` | `surface.ogxCurveBlockLightTorch` | constants extra 0 |
| `GetGbufferData` | iterationT | approximate | `gbufferdata GetGbufferData()` | `gbuffer.ogxGetGbufferData` | return GbufferData != OgxGbufferData; param count 0 != 19; constants missing 0.3; extra 63 |
| `FixParticleMask` | iterationT | approximate | `void FixParticleMask(inout materialmask, inout materialmask, inout float, float)` | `gbuffer.ogxFixParticleMask` | constants missing 0, 0.5, 1 |
| `primaries_to_matrix` | iterationT | approximate | `float3x3 primaries_to_matrix(float2, float2, float2, float2)` | `color.ogxAgxPrimariesToMatrix` | return mat3 != OgxAgxMat3 |
| `SlidePrimary` | iterationT | approximate | `float2 SlidePrimary(float2, float2, float2, float)` | `color.ogxAgxSlidePrimary` | constants extra 1 |
| `ComputeCompressionMatrix` | iterationT | approximate | `float3x3 ComputeCompressionMatrix(float2, float2, float2, float2)` | `color.ogxAgxComputeCompressionMatrix` | return mat3 != OgxAgxMat3 |
| `AgXConfigurable1` | iterationT | approximate | `float3x3 AgXConfigurable1()` | `color.ogxAgxConfigurable1` | return mat3 != OgxAgxMat3 |
| `BloomDownSample` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `AxialGaussianBlur` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `CloudShadowFromTex` | iterationT | approximate | `float CloudShadowFromTex(float3)` | `cloud.ogxCloudShadowSample` | param count 1 != 11; constants missing 0.45, 2, 256, 4096 |
| `GetLinearDepth` | iterationT | approximate | `float GetLinearDepth(float2)` | `post.ogxDofLinearDepth` | param count 1 != 6; samples ['sample'] != ['sample', 'sample']; constants extra 0.5 |
| `GetFocus` | iterationT | approximate | `float GetFocus()` | `itx_extra.ogxGetFocus` | samples ['fetch'] != []; constants missing 0, 0.125, 0.875, 1, 2, 3, 60 |
| `CoCSpread` | iterationT | approximate | `float CoCSpread()` | `post.ogxDofCocSpread` | samples ['fetch', 'sample', 'fetch', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'fetch']; constants missing 0.01, 0.1, 0.125, 2.39996, 60 |
| `DepthOfField` | iterationT | approximate | `float4 DepthOfField()` | `post.ogxDepthOfField` | samples ['fetch', 'sample', 'fetch', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'fetch']; constants missing 0.01, 0.125, 2.39996, 60 |
| `CalculateStars` | iterationT | approximate | `float3 CalculateStars(float3)` | `atmosphere.ogxStarsStable` | return vec3 != float; param count 1 != 3; constants missing -3.02585e+09, -2.66129e+08, -234359, -5.87339, -1.53738, -1.37419, -1.34811, -1.10638; extra -20, 0.1031, 0.99, 31.32, 300 |
| `ppss` | iterationT | approximate | `float3 ppss(float3, float3, float3, float3, float)` | `atmosphere.ogxPlanetBrdf` | param count 5 != 4; constants extra 0, 2, 3 |
| `Disc` | iterationT | approximate | `float Disc(float, float, float)` | `atmosphere.ogxDiscProfile` | constants extra 0, 2, 3 |
| `Calculate3DNoise` | iterationT | approximate | `float Calculate3DNoise(float3)` | `fog.ogxEnd3dNoise` | param count 1 != 3; constants missing 64; extra 2, 3 |
| `CalculateCloudFBM` | iterationT | approximate | `float CalculateCloudFBM(float3, float3)` | `fog.ogxCloudFbm` | param count 2 != 4; constants missing 64; extra 2, 3 |
| `CalculateCloudFBM_LQ` | iterationT | approximate | `float CalculateCloudFBM_LQ(float3, float3)` | `noise.ogxFbm3` | param 2 float3/in != int/in; samples ['sample'] != []; constants missing 0.15, 0.9, 64; extra 0.1031, 1, 2.03, 9, 31, 33.33 |
| `BlackHole_AccretionDisc_Stars` | iterationT | approximate | `void BlackHole_AccretionDisc_Stars(inout float3, float3, float3)` | `accretion.ogxAccretionDisc` | constants missing 0.007, 0.02, 0.25, 19.19, 384, 437.195, 441.423, 443.897 |
| `BlackHole_AccretionDisc_Reflection` | iterationT | approximate | `void BlackHole_AccretionDisc_Reflection(inout float3, float3, float3)` | `accretion.ogxAccretionDisc` | constants missing 0.0333333 |
| `FsrEasuSet` | iterationT | approximate | `void FsrEasuSet(inout float2, inout float, float, float, float, float, float, float)` | `upscale.ogxFsrEasuSet` | constants extra 0 |
| `RSM` | iterationT | approximate | `float3 RSM(float3, float3)` | `gi.ogxGiRsm` | param count 2 != 16; constants missing 0.0625, 0.9, 1.1, 1.32472, 1.61803, 2.39996, 7, 16; extra -0.737369, 0.67549 |
| `GI_TemporalFilter` | iterationT | approximate | `float4 GI_TemporalFilter()` | `gi.ogxGiTemporalFilter` | param count 0 != 29; samples ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch'] != ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch']; constants missing -1, 0.0625, 0.9, 1.1, 1.32472, 1.61803, 2.39996, 7; extra -0.737369, 0.67549, 4, 255 |
| `GI_SpatialFilter` | iterationT | approximate | `float3 GI_SpatialFilter(float, float3, float3)` | `gi.ogxGiSpatialFilter` | param count 3 != 7; constants missing -3, -2, -1, 0.5; extra 7 |
| `GroundTruthBasedAmbientOcclusion` | iterationT | approximate | `float GroundTruthBasedAmbientOcclusion(float3, float3, float3)` | `gi.ogxGroundTruthAo` | samples ['fetch', 'sample', 'sample'] != ['fetch', 'sample', 'sample', 'sample', 'sample']; constants missing 0.333333, 0.5 |
| `GetDistOffset` | iterationT | approximate | `float2 GetDistOffset(float2, float2)` | `post.ogxGlareDistOffset` | param count 2 != 3 |
| `flare` | iterationT | approximate | `float3 flare(float2, float2, float, float, float)` | `post.ogxGlareFlare` | param count 5 != 6 |
| `orb` | iterationT | approximate | `float3 orb(float2, float2, float, float)` | `post.ogxGlareOrb` | param count 4 != 5 |
| `LensFlare` | iterationT | approximate | `float3 LensFlare()` | `itx_extra.ogxLensFlare` | constants missing 8e-05, 0.131, 0.2, 1.5708, 2.5, 3.14159, 12, 13 |
| `MotionBlur` | iterationT | approximate | `float3 MotionBlur()` | `post.ogxMotionBlur` | samples ['fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'fetch', 'sample'] != ['fetch', 'fetch', 'fetch', 'fetch', 'sample']; constants missing -3, -1, 7 |
| `title` | iterationT | mc_glue | `—` | — | 就绪：标题计数与屏幕文字，不参与画面效果 |
| `HenyeyGreenstein` | iterationT | approximate | `float HenyeyGreenstein(float, float)` | `cloud.ogxHenyeyGreenstein` | constants missing 3.14159; extra 0.31831 |
| `SampleDensity` | iterationT | approximate | `float2 SampleDensity(float4, float3, bool)` | `cloud_volume.ogxCumulusSampleDensity` | param count 3 != 11; constants missing 0.0007, 0.007, 0.28, 0.68, 0.96 |
| `SetCloudPos` | iterationT | approximate | `float4 SetCloudPos(float3, float2, float, float, float3)` | `cloud_volume.ogxCumulusSetPos` | param count 5 != 2; constants extra 1 |
| `CloudLighting` | iterationT | approximate | `float3 CloudLighting(float3, float2, float, float, float2, float2, float4, float3, float, float)` | `cloud_volume.ogxCumulusLighting` | param count 10 != 15; constants missing 0.0007, 0.007, 0.28, 0.68, 0.96, 1.3, 3.14159; extra -10, 0.31831, 0.55, 0.65, 0.9, 116, 400 |
| `NubisCumulus` | iterationT | approximate | `void NubisCumulus(inout float3, float3, float2, float3, float3, float2, out float)` | `cloud_volume.ogxCumulusMarch` | return void != float4; param count 7 != 14; samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -1.5, -1, -0.5, -0.4624, -0.1119, -0.0742, -0.0374, -0.0283; extra -10, 0.31831, 0.55, 0.65, 0.9, 116, 400, 60000 |
| `CloudShadowTex` | iterationT | approximate | `float CloudShadowTex(float2, float2, float3)` | `cloud.ogxCloudShadowSample` | param count 3 != 11; samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample']; constants missing -1e-05, 1e-06, 8.5e-05, 0.0001, 0.0007, 0.007, 0.11, 0.125; extra -0.5, 0.06, 0.18, 1.5, 4, 5.9, 6, 12 |
| `BilinearHeightSample` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `HeightBasedNormal` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ParallaxOcclusionMapping` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `physics_waveDirection` | iterationT | approximate | `float2 physics_waveDirection(float2, int, float)` | `water.ogxOceanWaveDirection` | param count 3 != 2; constants missing 0, 0.035, 0.048, 0.45, 0.75, 0.8, 1.07, 1.18 |
| `BicubicBlurNoise` | iterationT | approximate | `float BicubicBlurNoise(float2)` | `cloud.ogxBicubicBlurNoise` | param count 1 != 2 |
| `BilinearNoise` | iterationT | approximate | `float BilinearNoise(float2)` | `cloud.ogxBilinearNoise` | param count 1 != 2 |
| `GetPlanarCloudsDistortion` | iterationT | approximate | `float GetPlanarCloudsDistortion(float2, float2)` | `cloud.ogxPlanarDistortion` | param count 2 != 3; constants extra 1 |
| `GetPlanarCloudsDensity` | iterationT | approximate | `float GetPlanarCloudsDensity(float2, float2)` | `cloud.ogxPlanarDensity` | param count 2 != 5; constants missing 0.025, 2.39996; extra -2.39996 |
| `GetPlanarCloudsLightingDensity` | iterationT | approximate | `float GetPlanarCloudsLightingDensity(float2, float2)` | `cloud.ogxPlanarLightingDensity` | param count 2 != 5; constants missing 0.025, 2.39996; extra -2.39996 |
| `PlanarClouds` | iterationT | approximate | `void PlanarClouds(inout float3, float3, float3, float, float)` | `planar.ogxPlanarClouds` | param count 5 != 25; constants missing 0.0003, 0.003996, 0.008396, 0.01459, 0.025, 0.0331, 1.68194, 1.85149; extra -2.39996, 0.0721, 0.2125, 0.7154, 0.984848 |
| `SevenSegment` | iterationT | mc_glue | `—` | — | 就绪：调试叠加字形表，只服务屏幕数字 |
| `DecimalPoint` | iterationT | mc_glue | `—` | — | 就绪：调试叠加小数点定位 |
| `PrintFloat` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试数字，不参与画面效果 |
| `PrintUintBinary` | iterationT | mc_glue | `—` | — | 就绪：屏幕调试二进制，不参与画面效果 |
| `AtrousWaveletFilter` | iterationT | approximate | `void AtrousWaveletFilter(inout float4, float3, float3, float3, float, float, float2)` | `reflection.ogxReflectionAtrousFilter` | param count 7 != 13; constants missing -1, 1.5708 |
| `ProjectSky` | iterationT | approximate | `float2 ProjectSky(float3, float)` | `atmosphere.ogxSkyProject` | constants missing 1 |
| `CalculateSpecularReflections` | iterationT | approximate | `void CalculateSpecularReflections(inout float3, float3, float3, float3, material)` | `reflection.ogxSpecularReflectionMix` | param count 5 != 12; samples ['fetch', 'fetch'] != [] |
| `Get3DNoise` | iterationT | approximate | `float Get3DNoise(float3)` | `noise.ogxFogNoise` | param count 1 != 2; constants missing 0.5, 64; extra 0.0078125, 0.015625, 2, 3 |
| `GetModulatedRainSpecular` | iterationT | approximate | `float GetModulatedRainSpecular(float3)` | `water.ogxRainSpecular` | constants missing 64 |
| `UnderwaterVolumetricFog` | iterationT | approximate | `float3 UnderwaterVolumetricFog(float3, float3, float3, float)` | `fog_volume.ogxUnderwaterFog` | samples ['fetch', 'sample', 'fetch', 'sample'] != ['sample', 'sample', 'sample', 'fetch']; constants missing 0.16, 0.3, 0.9, 6.66667, 7, 7.1 |
| `PowderEffect` | iterationT | approximate | `float PowderEffect(float, float, float)` | `fog.ogxFogPowder` | param count 3 != 2; constants extra 0, 4 |
| `MultiScatteringPhases` | iterationT | approximate | `void MultiScatteringPhases(float, inout float)` | `fog.ogxMultiScatteringPhases` | return void != float4; param count 2 != 1; constants missing 0, 4; extra 0.125, 0.25 |
| `FogDensity` | iterationT | approximate | `float FogDensity(float3, float3)` | `fog.ogxFogDensity` | param 1 float3/in != ogxfog/in; constants missing 0.1, 40, 50, 65; extra 0.0001, 0.1031, 1.6, 2.03, 3, 9, 17, 31 |
| `VolumetricFog` | iterationT | approximate | `void VolumetricFog(inout float3, float3, float3, float3, float, float, out float)` | `fog_volume.ogxVolumetricFog` | samples ['fetch', 'sample'] != ['fetch', 'sample', 'sample', 'sample', 'fetch', 'fetch', 'fetch', 'fetch', 'sample', 'sample', 'sample', 'sample']; constants missing 0.166667 |
| `LandAtmosphericScattering` | iterationT | approximate | `void LandAtmosphericScattering(inout float3, float, float3, float3, float3, bool)` | `itx_extra.ogxLandAtmosphericScattering` | constants missing 63 |
| `textureSmooth` | iterationT | approximate | `float4 textureSmooth(sampler2d, float2)` | `water.ogxTextureSmooth` | constants extra 2, 3 |
| `GetWaterParallaxCoord` | iterationT | approximate | `float3 GetWaterParallaxCoord(float3, float3)` | `water.ogxWaterParallax` | constants missing 0.96 |
| `AgX` | iterationT | approximate | `float3 AgX(float3)` | `color.ogxAgx` | param count 1 != 3; constants missing 6.5, 13 |
| `GetExposureValue` | iterationT | approximate | `float GetExposureValue()` | `itx_extra.ogxGetExposureValue` | constants missing 0.9, 0.95 |
| `FidelityFX_FSR1` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `end_portal_layer` | iterationT | approximate | `float4x4 end_portal_layer(float)` | `itx_extra.ogxEndPortalLayer` | param count 1 != 2; constants extra 3 |
| `SampleAnisotropic` | iterationT | approximate | `float4 SampleAnisotropic(float2, float2, float2, inout float3, inout float4)` | `itx_extra.ogxSampleAnisotropic` | param count 5 != 14; samples ['sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing -1.5, 0.25, 4; extra 1.488, 1.5, 2, 255 |
| `ViewPos_From_ScreenPos_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ViewPos_From_ScreenPos_Raw_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenPos_From_ViewPos_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenPos_From_ViewPos_Raw_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `LinearDepth_From_ScreenDepth_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenDepth_From_LinearDepth_DH` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ScreenDepth_From_DHScreenDepth` | iterationT | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `ShadowScreenPos_From_WorldPos_Distorted` | iterationT | approximate | `float3 ShadowScreenPos_From_WorldPos_Distorted(float3)` | `shadow.ogxShadowScreenPosDistorted` | constants missing 0.9 |
| `DistortShadowScreenPos` | iterationT | approximate | `float2 DistortShadowScreenPos(float2)` | `shadow.ogxDistortShadowPos` | constants missing 0.9 |
| `remapSaturate` | iterationT | approximate | `float remapSaturate(float, float, float)` | `math.ogxRemapSaturate` | constants extra 0, 1 |
| `DoNightEye` | iterationT | approximate | `void DoNightEye(inout float3)` | `math.ogxDoNightEye` | constants extra 0.0721, 0.2125, 0.7154 |
| `Fd_Burley` | iterationT | approximate | `float Fd_Burley(float3, float3, float3, float)` | `math.ogxDiffuseBurley` | constants extra 0 |
| `SpecularGGX` | iterationT | approximate | `float SpecularGGX(float3, float3, float3, float, float)` | `math.ogxSpecularGGX` | constants extra 0 |
| `Blackbody` | iterationT | approximate | `float3 Blackbody(float)` | `math.ogxBlackbody` | constants missing 2 |
| `triNoise2d` | Eclipse | approximate | `float triNoise2d(float2)` | `cloud_eclipse.ogxEclipseTriNoise2d` | param count 1 != 2; constants missing -0.29552, 0.01, 0.02, 0.06, 0.29552, 0.42, 0.45, 0.49; extra 0.0973, 0.103, 0.1031, 2, 6.28319, 33.33 |
| `aurora` | Eclipse | approximate | `float3 aurora(float3, int, float, float, float)` | `atmosphere.ogxAurora` | param count 5 != 7; constants missing -50, -0.5, -0.29552, -0.1, 0.0016, 0.01, 0.025, 0.05; extra -0.2, 0.015, 0.08, 0.12, 0.16, 0.2, 0.35, 5 |
| `bayerDither` | Eclipse | approximate | `float bayerDither()` | `math.ogxEclipseBayerDither` | param count 0 != 1 |
| `YearCycleColor` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `BiomeFogDensity` | Eclipse | approximate | `void BiomeFogDensity(inout float4, inout float4, float)` | `fog.ogxBiomeFogDensityEclipse` | param count 3 != 17; constants missing 0.02, 0.05, 0.3, 0.4 |
| `BiomeVLFogColors` | Eclipse | mc_glue | `—` | — | 就绪：原版群系枚举到颜色表，非算法 |
| `FogDensities` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `triangWhiteNoise` | Eclipse | approximate | `float triangWhiteNoise(float2)` | `noise.ogxTriangleNoise` | param count 1 != 2; constants extra 1e-10 |
| `fp10Dither` | Eclipse | approximate | `float3 fp10Dither(float3, float2)` | `post.ogxDitherFloat` | param count 2 != 4; constants missing 5, 6; extra 1e-20 |
| `fp16Dither` | Eclipse | approximate | `float3 fp16Dither(float3, float2)` | `post.ogxDitherFloat` | param count 2 != 4; constants missing 10; extra 1e-20 |
| `int8Dither` | Eclipse | approximate | `float3 int8Dither(float3, float2)` | `post.ogxDitherFixed` | param count 2 != 4; constants missing -8; extra 1e-10 |
| `int10Dither` | Eclipse | approximate | `float3 int10Dither(float3, float2)` | `post.ogxDitherFixed` | param count 2 != 4; constants missing -10; extra 1e-10 |
| `int16Dither` | Eclipse | approximate | `float3 int16Dither(float3, float2)` | `post.ogxDitherFixed` | param count 2 != 4; constants missing -16; extra 1e-10 |
| `luma` | Eclipse | approximate | `float luma(float3)` | `color.ogxLuminanceRec601` | constants missing 0.07, 0.21, 0.72; extra 0.114, 0.299, 0.587 |
| `Tonemap_Lottes` | Eclipse | approximate | `float3 Tonemap_Lottes(float3)` | `color.ogxTonemapLottes` | constants extra 0.249115, 1.06987 |
| `curve` | Eclipse | approximate | `float3 curve(float3)` | `color.ogxAgxContrast` | constants missing 1; extra 0.00232, 0.1191, 0.4298, 6.868, 15.5, 31.96, 40.14 |
| `Tonemap_Uchimura_Modified` | Eclipse | approximate | `float3 Tonemap_Uchimura_Modified(float3, float, float, float, float, float, float)` | `color.ogxTonemapUchimuraModified` | constants extra 2, 3 |
| `agxDefaultContrastApprox` | Eclipse | approximate | `float3 agxDefaultContrastApprox(float3)` | `color.ogxAgxContrast` | 与其它参考函数共用实现但签名不同：float3 agxDefaultContrastApprox(float3) |
| `agxLook` | Eclipse | approximate | `float3 agxLook(float3)` | `color.ogxAgxLook` | constants missing 0 |
| `ToneMap_AgX` | Eclipse | approximate | `float3 ToneMap_AgX(float3)` | `color.ogxToneMapAgx` | constants missing 0.0164939, 0.110607, 0.14133; extra -0.14133, -0.110607, -0.0164939 |
| `no_tonemapper` | Eclipse | approximate | `float3 no_tonemapper(float3)` | `color.ogxTonemapNone` | constants extra 1, 2.2 |
| `swapperlinZ2` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `SSRT_Handlight_Shadows` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetHandLight` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `doBlockLightLighting` | Eclipse | approximate | `float3 doBlockLightLighting(float3, float, float3, float3)` | `eclipse_diffuse.ogxEclipseDoBlockLightLighting` | param count 4 != 10; constants extra 0.999, 1.5, 3 |
| `doIndirectLighting` | Eclipse | approximate | `float3 doIndirectLighting(float3, float3, float)` | `surface.ogxDoIndirectLighting` | param count 3 != 7; constants missing 0.5, 0.8 |
| `calculateFlashlight` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `toScreenSpace_DH` | Eclipse | approximate | `float3 toScreenSpace_DH(float2, float, float)` | `camera.ogxToScreenSpaceDh` | param count 3 != 5 |
| `toClipSpace3_DH` | Eclipse | approximate | `float3 toClipSpace3_DH(float3, bool)` | `camera.ogxToClipSpace3Dh` | param count 2 != 4; constants extra 0, 1, 2, 3 |
| `DH_shadowProjectionTweak` | Eclipse | approximate | `float4x4 DH_shadowProjectionTweak(float4x4)` | `camera.ogxDhShadowProjectionTweak` | param count 1 != 4; constants extra -2, 0, 2, 3 |
| `LightSourcePosition` | Eclipse | approximate | `float3 LightSourcePosition(float3, float3, float)` | `eclipse_extra.ogxEclipseLightSourcePosition` | param count 3 != 6; samples ['fetch'] != []; constants missing 1, 2, 150 |
| `densityAtPosFog` | Eclipse | approximate | `float densityAtPosFog(float3)` | `weather.ogxStormNoise` | param count 1 != 3; constants missing 512 |
| `SwirlAroundOrigin` | Eclipse | approximate | `void SwirlAroundOrigin(inout float3, float3)` | `fog.ogxEndVortexSwirl` | param count 2 != 3 |
| `fogShape` | Eclipse | approximate | `float fogShape(float3)` | `fog.ogxEndVortexShape` | param count 1 != 4; constants missing -60, -1, 512; extra 60, 300 |
| `LightSourceColors` | Eclipse | approximate | `float3 LightSourceColors(float, float)` | `eclipse_extra.ogxEclipseLightSourceColors` | param count 2 != 7; constants missing 0.4, 0.5, 0.75, 1 |
| `LightSourceLighting` | Eclipse | approximate | `float3 LightSourceLighting(float3, float3, float, float, float3, float)` | `fog.ogxEndVortexLighting` | param count 6 != 7; constants missing -60, -1, 0.15, 512; extra 60, 300 |
| `GetVolumetricFog` | Eclipse | approximate | `float4 GetVolumetricFog(float3, float, float)` | `fog.ogxEndVortexFog` | param count 3 != 15; samples ['fetch', 'fetch', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample']; constants missing -60, -1, 0.001, 0.15, 0.3, 0.35, 0.4, 2.5; extra 0.0001, 60 |
| `GetEndFogShadow` | Eclipse | approximate | `float GetEndFogShadow(float3, float3)` | `eclipse_scene.ogxEclipseGetEndFogShadow` | param count 2 != 4; samples ['sample', 'sample'] != ['sample']; constants missing -60, -1, 0.32, 0.5, 0.8, 1.5, 2, 2.39996 |
| `applyGameplayEffects` | Eclipse | approximate | `void applyGameplayEffects(inout float3, float2, float)` | `eclipse_scene.ogxEclipseApplyGameplayEffects` | param count 3 != 23; constants extra -1, 0.07, 0.1, 0.2, 0.21, 0.35, 0.72, 15 |
| `HsvToRgb` | Eclipse | approximate | `float3 HsvToRgb(float3)` | `color.ogxHsvToRgb` | constants missing 9; extra 0, 0.333333, 0.666667 |
| `BilateralUpscale_SSAO` | Eclipse | approximate | `float4 BilateralUpscale_SSAO(sampler2d, sampler2d, float2, float)` | `gi.ogxBilateralUpscale` | param count 4 != 6; constants missing -2, 0.005; extra -1, 2, 3 |
| `rayTrace_GI` | Eclipse | approximate | `float3 rayTrace_GI(float3, float3, float, float)` | `eclipse_indirect.ogxEclipseRayTraceGi` | param count 4 != 11; samples ['fetch'] != ['fetch', 'fetch'] |
| `convertHandDepth_3` | Eclipse | approximate | `float convertHandDepth_3(float, bool)` | `math.ogxConvertHandDepth3` | param count 2 != 3 |
| `RT_alternate` | Eclipse | approximate | `float3 RT_alternate(float3, float3, float, float, bool, inout float)` | `eclipse_indirect.ogxEclipseRtAlternate` | param count 6 != 18; samples ['fetch'] != ['fetch', 'fetch']; constants missing 10 |
| `ApplySSRT` | Eclipse | approximate | `float3 ApplySSRT(float3, float3, float3, float3, float3, float3, float, bool, bool)` | `reflection.ogxReflectionSceneColor` | param count 9 != 2; samples ['fetch'] != ['sample']; constants missing 5e-05, 0.001, 0.05, 0.1, 0.5, 0.56984, 0.754878, 0.8 |
| `Iris_Lightningflash` | Eclipse | approximate | `float3 Iris_Lightningflash(float3, float3, float3, inout float)` | `fog_volume.ogxFogLightning` | param 2 float3/in != ogxfogmedia/in; param 3 float3/in != float/in; param 4 float/inout != float/in; constants missing -10, -2, 5, 16, 60, 300; extra 0.55, 0.65, 0.9 |
| `Iris_Lightningflash_VLcloud` | Eclipse | approximate | `float3 Iris_Lightningflash_VLcloud(float3)` | `cloud_volume.ogxCumulusLightning` | param count 1 != 4; constants missing -10, 400; extra 0.55, 0.65, 0.9 |
| `Iris_Lightningflash_VLfog` | Eclipse | approximate | `float3 Iris_Lightningflash_VLfog(float3)` | `fog_volume.ogxFogLightning` | param count 1 != 4; constants missing -15, 150; extra 0.55, 0.65, 0.9 |
| `GetLpvPosition` | Eclipse | approximate | `float3 GetLpvPosition(float3)` | `camera.ogxGetLpvPositionExplicit` | param count 1 != 3; constants missing 2; extra 0.5 |
| `SampleLpvLinear` | Eclipse | approximate | `float4 SampleLpvLinear(float3)` | `lpv.ogxLpvDecodeSample` | param count 1 != 2; samples ['sample', 'sample'] != []; constants missing 9, 24; extra 0.333333, 0.666667 |
| `GetLpvSkyLight` | Eclipse | approximate | `float GetLpvSkyLight(float4)` | `lpv.ogxLpvSkyLight` | constants extra 0, 1 |
| `cloudVol` | Eclipse | approximate | `float cloudVol(float3)` | `fog.ogxNetherFogCloudVolume` | param count 1 != 3; constants missing -10, 120 |
| `phaseRayleigh` | Eclipse | approximate | `float phaseRayleigh(float)` | `math.ogxRayleighPhaseElek` | constants missing -1; extra 3.14159 |
| `fogPhase` | Eclipse | approximate | `float fogPhase(float)` | `eclipse_extra.ogxEclipseFogPhase` | constants missing 0 |
| `cube` | Eclipse | approximate | `float cube(float)` | `math.ogxSquare` | 与其它参考函数共用实现但签名不同：float cube(float) |
| `max_of` | Eclipse | approximate | `float max_of(float3)` | `math.ogxMaxVec3` | 与其它参考函数共用实现但签名不同：float max_of(float3) |
| `min_of` | Eclipse | approximate | `float min_of(float3)` | `math.ogxMinVec3` | 与其它参考函数共用实现但签名不同：float min_of(float3) |
| `rcp_length` | Eclipse | approximate | `float rcp_length(float3)` | `math.ogxSafeInvLength` | constants extra 0, 1 |
| `linear_step` | Eclipse | approximate | `float linear_step(float, float, float)` | `math.ogxRemapSaturate` | constants extra 0, 1 |
| `screen_to_view_space` | Eclipse | approximate | `float3 screen_to_view_space(float3, bool)` | `camera.ogxScreenToViewSpace` | param 2 bool/in != float4x4/in |
| `view_to_screen_space` | Eclipse | approximate | `float3 view_to_screen_space(float3, bool)` | `camera.ogxViewToScreenSpace` | param 2 bool/in != float4x4/in |
| `calculate_maximum_horizon_angle` | Eclipse | approximate | `float calculate_maximum_horizon_angle(float3, float3, float3, float3, float)` | `eclipse_extra.ogxEclipseMaxHorizonAngle` | param count 5 != 15; constants missing -0.201877, 0.0464619, 0.56, 0.75, 1.57018; extra -0.156583, 1e-06, 1.5708 |
| `ambient_occlusion` | Eclipse | approximate | `float ambient_occlusion(float3, float3, float3, float2)` | `gi.ogxGroundTruthAo` | param count 4 != 12; samples ['fetch', 'fetch'] != ['sample', 'sample', 'sample', 'sample']; constants missing -1, -0.201877, 0.0464619, 0.5, 0.56, 0.75, 1.57018; extra -0.156583, 0.01, 0.02, 0.125, 0.618034, 1.5708, 1.7 |
| `toClipSpace3` | Eclipse | approximate | `float3 toClipSpace3(float3)` | `camera.ogxToClipSpace3` | param count 1 != 2; constants extra 0, 1, 2, 3 |
| `toScreenSpace` | Eclipse | approximate | `float3 toScreenSpace(float3)` | `camera.ogxToScreenSpace` | param count 1 != 2 |
| `toScreenSpaceVector` | Eclipse | approximate | `float3 toScreenSpaceVector(float3)` | `camera.ogxToScreenSpaceVector` | param count 1 != 2 |
| `toWorldSpace` | Eclipse | approximate | `float3 toWorldSpace(float3)` | `camera.ogxToWorldSpace` | param count 1 != 2; constants extra 0, 1, 2 |
| `toWorldSpaceCamera` | Eclipse | approximate | `float3 toWorldSpaceCamera(float3)` | `camera.ogxToWorldSpaceCamera` | param count 1 != 3; constants extra 0, 1, 2 |
| `toShadowSpace` | Eclipse | approximate | `float3 toShadowSpace(float3)` | `camera.ogxToShadowSpace` | param count 1 != 3; constants extra 0, 1, 2 |
| `toShadowSpaceProjected` | Eclipse | approximate | `float3 toShadowSpaceProjected(float3)` | `camera.ogxToShadowSpaceProjected` | param count 1 != 4; constants extra 0, 1, 2 |
| `ripples` | Eclipse | approximate | `float3 ripples(float2)` | `water.ogxRainRipples` | param count 1 != 3; constants missing 0.85, 4.25; extra 0.02, 9 |
| `sky_density` | Eclipse | approximate | `float3 sky_density(float)` | `atmosphere.ogxEclipseSkyDensity` | param count 1 != 3; constants missing 6.731e+06 |
| `sky_airmass` | Eclipse | approximate | `float3 sky_airmass(float3, float3, float, float)` | `atmosphere.ogxEclipseSkyAirmass` | param count 4 != 6; constants missing 6.731e+06 |
| `sky_opticalDepth` | Eclipse | approximate | `float3 sky_opticalDepth(float3, float3, float, float)` | `atmosphere.ogxEclipseSkyOpticalDepth` | param count 4 != 9; constants missing 6.731e+06 |
| `sky_transmittance` | Eclipse | approximate | `float3 sky_transmittance(float3, float3, float)` | `atmosphere.ogxEclipseSkyTransmittance` | param count 3 != 9; constants missing 1.4427, 6.731e+06 |
| `calculateAtmosphere` | Eclipse | approximate | `float3 calculateAtmosphere(float3, float3, float3, float3, float3, out float2, out float3, int, float)` | `eclipse_sky.ogxEclipseCalculateAtmosphere` | param count 9 != 20; constants missing 1.4427, 250; extra -1e+10, 0.000108696, 1200, 8000, 110000, 6.841e+06, 1e+10 |
| `applySceneControllerParameters` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `BiasShadowProjection` | Eclipse | approximate | `float4 BiasShadowProjection(float4)` | `shadow.ogxApplyShadowBias` | return vec4 != void; param count 1 != 4; constants missing 1.8; extra 0.1, 0.15, 1, 2, 8, 16 |
| `calcDistort` | Eclipse | approximate | `float calcDistort(float2)` | `eclipse_extra.ogxEclipseCalcDistort` | param count 1 != 4; constants missing 1.8 |
| `GriAndEminShadowFix` | Eclipse | approximate | `void GriAndEminShadowFix(inout float3, float3, float)` | `shadow.ogxGriAndEminShadowFix` | param count 3 != 5 |
| `applyShadowBias` | Eclipse | approximate | `void applyShadowBias(inout float3, float3, float3)` | `shadow.ogxApplyShadowBias` | param count 3 != 4; constants missing 0.2, 128, 2560 |
| `drawMoon` | Eclipse | approximate | `float3 drawMoon(float3, float3, float3, inout float3)` | `atmosphere.ogxMoonDiscDefault` | return vec3 != float; param count 4 != 2; constants missing -0.9994, 0.9994, 5, 40; extra 5e-05, 2, 3, 100000 |
| `drawRealMoon` | Eclipse | approximate | `float3 drawRealMoon(float3, float3, float3, inout float3, float)` | `atmosphere.ogxMoonDiscReal` | return vec3 != float; param count 5 != 3; constants missing 0.15, 50, 750; extra 0.0001, 0.999, 2, 3, 10 |
| `texture_bicubic` | Eclipse | approximate | `float4 texture_bicubic(sampler2d, float2)` | `math.ogxBicubicTexture` | return vec4 != float3; param count 2 != 3; samples ['sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample']; constants missing -3, -1, 4, 6; extra 0, 2 |
| `texture_bicubic_offset` | Eclipse | approximate | `float4 texture_bicubic_offset(sampler2d, float2, float, float)` | `math.ogxBicubicTexture` | return vec4 != float3; param count 4 != 3; samples ['sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample']; constants missing -3, -1, 3.14159, 4, 6; extra 0 |
| `skyFromTex` | Eclipse | approximate | `float3 skyFromTex(float3, sampler2d)` | `atmosphere_model.ogxAtmoSkyRadiance` | param count 2 != 15; samples ['sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing 1.5, 3.14159, 18.5, 256; extra -1.5, -1, -0.4624, -0.1119, -0.0742, -0.0374, -0.0283, -0.0069 |
| `skyCloudsFromTex` | Eclipse | approximate | `float4 skyCloudsFromTex(float3, sampler2d)` | `eclipse_sky.ogxEclipseSkyCloudsFromTex` | param count 2 != 3 |
| `skyCloudsFromTexBLUR` | Eclipse | approximate | `float4 skyCloudsFromTexBLUR(float3, sampler2d, float)` | `atmosphere.ogxSkyCloudsFromTex` | param count 3 != 5; constants missing 1.5, 18.5, 256, 257; extra -1, 1.5708 |
| `skyCloudsFromTexLOD` | Eclipse | approximate | `float4 skyCloudsFromTexLOD(float3, sampler2d, float)` | `eclipse_sky.ogxEclipseSkyCloudsFromTexLod` | param count 3 != 4 |
| `volumetricsFromTex` | Eclipse | approximate | `float4 volumetricsFromTex(float3, sampler2d, float)` | `fog_volume.ogxFogCloudBicubic` | return vec4 != float; param 1 float3/in != sampler2d/in; param 2 sampler2d/in != float2/in; param 3 float/in != float2/in; samples ['sample'] != ['sample', 'sample', 'sample', 'sample']; constants missing 0.12, 3.14159, 256; extra -0.5, 3, 4, 6 |
| `invLinZ` | Eclipse | approximate | `float invLinZ(float)` | `reflection.ogxReflectionLinearDepth` | param count 1 != 2; constants extra 1, 3 |
| `DH_invLinZ` | Eclipse | approximate | `float DH_invLinZ(float)` | `reflection.ogxReflectionDhToScreenDepth` | param count 1 != 3; constants extra 0.5, 1, 3 |
| `linZ` | Eclipse | approximate | `float linZ(float)` | `reflection.ogxReflectionLinearDepth` | param count 1 != 2; constants extra 1, 3 |
| `linZ2` | Eclipse | approximate | `float linZ2(float, float, float)` | `reflection.ogxReflectionLinearDepth` | param count 3 != 2; constants extra 1, 3 |
| `frisvad` | Eclipse | approximate | `void frisvad(float3, out float3, out float3)` | `math.ogxTangentBasis` | return void != OgxTangentBasis; param count 3 != 4; constants missing -1, -0.9, 0 |
| `R2_Sample` | Eclipse | approximate | `float2 R2_Sample(int)` | `math.ogxR2Sample` | 与其它参考函数共用实现但签名不同：float2 R2_Sample(int) |
| `invertLinearizeDepthFast` | Eclipse | approximate | `float invertLinearizeDepthFast(float)` | `camera.ogxInvertLinearizeDepthFast` | param count 1 != 3 |
| `rayTraceSpeculars` | Eclipse | approximate | `float3 rayTraceSpeculars(float3, float3, float, float, bool, inout float, inout bool)` | `eclipse_specular.ogxEclipseRayTraceSpeculars` | param count 7 != 13; constants missing 4, 65000 |
| `toScreenSpace2` | Eclipse | approximate | `float3 toScreenSpace2(float3, bool)` | `camera.ogxToScreenSpace2` | param count 2 != 4 |
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
| `ComputePhotonicsShadowMap` | Eclipse | approximate | `float ComputePhotonicsShadowMap(inout float3, float3, float, float, float3)` | `eclipse_specular.ogxEclipseComputePhotonicsShadowMap` | param count 5 != 20; samples ['sample'] != ['sample', 'sample', 'sample', 'sample']; constants missing 2.8125e-05, 0.0014625, 1.8, 128, 2560; extra 0.0001, 2.4, 5 |
| `trace_wsr` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `doBlockLightLightingVoxel` | Eclipse | approximate | `float3 doBlockLightLightingVoxel(float3, float, float3, float3)` | `eclipse_specular.ogxEclipseDoBlockLightLightingVoxel` | param count 4 != 9; constants extra 0.999, 1.5, 3 |
| `raymarchWSR_LPV` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchWSRfog` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `WSRwaterVolumetrics` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getPhotonicsEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsEmission` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsReflectionShading` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `photonicsReflection` | Eclipse | approximate | `float4 photonicsReflection(float3, float3, float2, float3, inout float, inout float3)` | `eclipse_specular.ogxEclipsePhotonicsReflection` | param count 6 != 46; samples [] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants extra -15, -3, -1, 0.0001, 0.0012, 0.004, 0.02, 0.05 |
| `getEnvironmentReflections` | Eclipse | approximate | `float4 getEnvironmentReflections(float3, float3, float3, float3, float3, float2, bool, float, inout float, inout float3, bool)` | `eclipse_specular.ogxEclipseGetEnvironmentReflections` | param count 11 != 25; constants missing 4, 30, 65000 |
| `getReflectionVisibility` | Eclipse | approximate | `float getReflectionVisibility(float, float)` | `eclipse_specular.ogxEclipseGetReflectionVisibility` | param count 2 != 3; constants missing 0.3, 30 |
| `specularReflections` | Eclipse | approximate | `float3 specularReflections(float3, float3, float3, float3, float2, float3, float3, float, float, float3, float3, float3, float, bool, bool, inout float, float4)` | `eclipse_specular.ogxEclipseSpecularReflections` | param count 17 != 36; samples ['sample', 'fetch', 'sample'] != ['fetch', 'sample']; constants missing 0.0660636, 0.108329, 0.3, 0.333333, 0.392389, 0.54, 0.8, 1.5; extra 0.373402, 0.495829, 0.504154, 0.512357, 0.531229, 0.554537, 0.554779, 0.555597 |
| `StableStarField` | Eclipse | approximate | `float StableStarField(float3, float)` | `atmosphere.ogxStarsStable` | param count 2 != 3; constants extra -20, 0.99, 300 |
| `starplane` | Eclipse | approximate | `float starplane(float3, out float3)` | `atmosphere.ogxStarPlane` | constants missing -1.5, 0.04045, 0.0521327, 0.392314, 0.580392, 0.721569, 0.760784, 0.947867; extra -3.02585e+09, -2.66129e+08, -234359, -5.87339, -1.53738, -1.37419, -1.34811, -1.10638 |
| `starbox` | Eclipse | approximate | `float starbox(float3, out float3)` | `atmosphere.ogxStarBox` | constants missing -1.5, 0.04045, 0.0521327, 0.392314, 0.580392, 0.721569, 0.760784, 0.947867; extra -3.02585e+09, -2.66129e+08, -234359, -5.87339, -1.53738, -1.37419, -1.34811, -1.10638 |
| `stars` | Eclipse | approximate | `float stars(float3, out float3)` | `atmosphere.ogxStarsStable` | param count 2 != 3 |
| `smoothfilter` | Eclipse | approximate | `float4 smoothfilter(sampler2d, float2, float2)` | `sampling.ogxSmoothFilter` | constants extra 0 |
| `shadowsmoothfilter` | Eclipse | approximate | `float shadowsmoothfilter(sampler2dshadow, float3, float)` | `sampling.ogxShadowSmoothFilter` | samples ['sample'] != [] |
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
| `sampleRGSS` | Eclipse | approximate | `float4 sampleRGSS(sampler2d, float2, float2)` | `sampling.ogxRgssSample` | param count 3 != 5 |
| `calculateRoughSpecular` | Eclipse | approximate | `float3 calculateRoughSpecular(float, float, int)` | `math.ogxRoughSpecularDirection` | constants missing 64; extra 4096 |
| `srgbToLinear` | Eclipse | approximate | `float3 srgbToLinear(float3)` | `color.ogxSrgbToLinear` | constants missing 0.04045, 0.0521327, 0.947867, 2.4, 12.92; extra 0.0125229, 0.305306, 0.682171 |
| `linearToSRGB` | Eclipse | approximate | `float3 linearToSRGB(float3)` | `color.ogxLinearToSrgb` | constants extra 0 |
| `blackbody` | Eclipse | approximate | `float3 blackbody(float)` | `color.ogxBlackbodyEclipse` | constants missing 0.04045, 0.0521327, 0.947867, 2.4, 12.92; extra 0.0125229, 0.305306, 0.682171, 1 |
| `cartToSphere` | Eclipse | approximate | `float3 cartToSphere(float2)` | `math.ogxCircleMap` | return vec3 != float2; param count 1 != 2; constants missing 1, 3.14159, 6.28319; extra 2.39996 |
| `sphereToCart` | Eclipse | approximate | `float2 sphereToCart(float3)` | `atmosphere.ogxSkyUnproject` | return vec2 != float3; param count 1 != 2; constants missing 0.159155; extra 0, 1, 1.5, 2, 2.5 |
| `rand` | Eclipse | approximate | `float rand(float)` | `noise.ogxWhiteNoise` | param 1 float/in != float2/in; constants missing 2 |
| `getRainDensity` | Eclipse | approximate | `float getRainDensity(float)` | `cloud.ogxCloudRainDensity` | param count 1 != 3 |
| `densityAtPos` | Eclipse | approximate | `float densityAtPos(float3)` | `cloud.ogxCloudDensityAtPos` | param count 1 != 3; constants missing 512 |
| `getCloudShape` | Eclipse | approximate | `float getCloudShape(int, int, float3, float, float)` | `cloud_eclipse.ogxEclipseGetCloudShape` | param count 5 != 7; samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing 130, 250, 280, 600; extra -0.4, 5e-06, 2e-05, 5e-05, 0.00018, 0.0973, 0.1, 0.103 |
| `getCumulonimbusShape` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getLightningPosition` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetCloudShadow` | Eclipse | approximate | `float GetCloudShadow(float3, float3)` | `cloud.ogxCloudShadow` | param count 2 != 3; samples ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample'] != []; constants missing -200, -100, -0.7, -0.5, -0.0001, 0.001, 0.005, 0.1; extra 0.0001, 0.002, 0.05, 0.085, 0.1031, 0.12, 0.14, 0.15 |
| `getRayOrigin` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `phaseCloud` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getCloudScattering` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `getCloudLighting` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchCloud` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVolumetricClouds` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `raymarchCloudSimple` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVolumetricCloudsSimple` | Eclipse | mc_glue | `—` | — | 参考默认配置未启用该函数，不参与画面 |
| `GetVoxelIndex` | Eclipse | approximate | `int3 GetVoxelIndex(float3)` | `voxel.ogxGetVoxelIndex` | param count 1 != 3 |
| `SetVoxelBlock` | Eclipse | approximate | `void SetVoxelBlock(int3, uint)` | `voxel.ogxVoxelWriteIndex` | return void != int3; param count 2 != 3; constants missing 0, 1 |
| `PopulateShadowVoxel` | Eclipse | approximate | `void PopulateShadowVoxel(float3)` | `voxel.ogxPopulateShadowVoxelIndex` | return void != uint; param count 1 != 10; constants missing 0.5, 267, 500, 1601, 1603, 1605, 1606, 1607 |
| `waterCaustics` | Eclipse | approximate | `float waterCaustics(float3, float3, float)` | `water.ogxWaterBumpCaustics` | param count 3 != 7; samples ['sample', 'sample'] != ['sample', 'sample', 'sample', 'sample']; constants extra -0.737367, 0.675493, 12, 32, 48 |
| `getWaterHeightmap` | Eclipse | approximate | `float getWaterHeightmap(float2, float, float)` | `water.ogxWaterBumpHeightmap` | param count 3 != 5; samples ['sample'] != ['sample', 'sample', 'sample']; constants missing 1, 3; extra -0.737367, 0.675493, 12, 32, 48 |
| `getWaveNormal` | Eclipse | approximate | `float3 getWaveNormal(float3, float3)` | `water.ogxWaterBumpNormal` | param count 2 != 9; samples ['sample', 'sample', 'sample', 'sample'] != ['sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample', 'sample']; constants missing 0.15; extra -0.737367, 0.025, 0.675493, 12, 32, 48 |

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
