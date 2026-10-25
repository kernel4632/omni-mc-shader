# 效果对照：iterationT 与 Eclipse → omni-gfx

本文件回答一个问题：两个参考包里的每一项效果，现在对应 `omni-gfx` 的哪个函数，还是仍然留在光影侧。它和 `docs/parity.md`（iterationT 移植合同、逐条偏离）、`docs/eclipse-parity.md`（Eclipse 合入项）分工不同：那两份讲“从哪来、改了什么”，这份讲“算法现在住哪里”。

## 口径与证据边界

- 覆盖对象是两个参考包的算法库：iterationT `shaders/Lib/` 下 31 个效果文件（另 6 个宿主文件单列），Eclipse `shaders/lib/` 下 45 个文件。算法对照共 76 行，逐项列在下表，不跳行。
- 程序入口不逐条列：iterationT `Lib/Programs/` 有 37 个文件、Eclipse 有 594 个程序文件，它们是阶段壳子，只调用上面的库。阶段划分与绘制顺序见 `docs/rendering.md`，迁移分片见 `docs/parity.md`。
- 状态只有五种，不用模糊说法：
  - **已覆盖**：生成库里有等价实现，光影侧经 `shaders/gfx/` 适配层调用到。
  - **部分**：算式主体进库，剩余部分与宿主约定绑在一起，后面写明剩下什么。
  - **库内**：生成库里有实现，光影侧还没调用；一般只被库的测试世界使用。
  - **未覆盖**：还没有对应实现。
  - **MC 专用**：依赖 Minecraft 的编号表、加载器约定、维度参数或调试界面，不适合放进通用库。
- 证据来源：`shaders/gfx/*.glsl` 的转发表、`shaders/` 里对 `ogx*` 函数的调用、`omni-gfx/src/*.slang` 的函数清单。状态按这三处实际内容判定，不按文件名相似判定。
- 未验证：没有在 Minecraft 里逐项比对画面，因此“已覆盖”只表示调用链存在且算式在库里，不表示两边像素完全一致。

## iterationT 3.2.0

### 算法库（31 个文件）

| 参考效果 | 参考入口函数 | omni-gfx 对应 | 状态 |
| --- | --- | --- | --- |
| `BasicFounctions/Blocklight.glsl` | `BlockLighting`、`TextureLighting`、`TorchScreenSpaceShadow`、`HeldLighting`、`TorchSpecularHighlight` | `surface`：`ogxBlockLight`、`ogxCurveBlockLightSky`、`ogxCurveBlockLightTorch`；`shadow` 提供投影与比较 | 部分：块光曲线与打包光照进库；屏幕空间火把阴影与手持光仍由 `rendering/lighting/held_light.glsl` 组合宿主矩阵 |
| `BasicFounctions/NetherColor.glsl` | `NetherLighting`、`NetherFogColor` | `fog`：`ogxNetherFogDensityAt`、`ogxNetherFogCloudVolume` | 部分：密度进库；生物群系雾色表留在 `rendering/world/nether.glsl`，那是 MC 数据 |
| `BasicFounctions/PrecomputedAtmosphere.glsl` | `ClampRadius`、`DistanceToTopAtmosphereBoundary`、`RenderSunDisc`、`RenderMoonDisc`、`RenderMoonDiscReflection` | `atmosphere_model`：`ogxAtmo*` 共 20 个；`atmosphere`：`ogxSunDisc`、`ogxMoonDiscReal`、`ogxMoonDiscDefault`、`ogxMoonDiscReflection` | 已覆盖 |
| `BasicFounctions/Sunlight_Shadow.glsl` | `VariablePenumbraShadow`、`ScreenSpaceShadow`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `shadow`：`ogxVariablePenumbraShadow`、`ogxScreenSpaceShadow`、`ogxSunScreenShadow`；`water`：`ogxWavesNormalFromTex`、`ogxWaterCaustics` | 已覆盖 |
| `BasicFounctions/TAA.glsl` | `SampleCurrColor`、`SamplePrevColor`、`RGB_To_YCoCg` 等 14 个 | `antialias`：`ogxTaaReproject` 与 `ogxRgbToYCoCg`、`ogxClipAabb`、`ogxBicubicTexture4` | 已覆盖：接入 `rendering/clarity/taa.glsl`；库内另有十个细分步骤函数暂无调用方 |
| `BasicFounctions/TAA_Nether.glsl` | `BicubicTextureVec4`、`SamplePreviousDepthBilinear` 等 | `antialias`：YCoCg、裁剪与重投影同一套 | 部分：重投影进库；下界把参考深度打包进七号画面的做法属于 `buffers_nether.glsl` 的格式约定 |
| `BasicFounctions/TemporalNoise.glsl` | `BlueNoise`、`BlueNoiseTemproal`、`BayerTemproal` | `sampling`：`ogxBlueNoise`、`ogxBlueNoiseTemporal`、`ogxBayerTemporal` | 已覆盖 |
| `BasicFounctions/VanillaComposite.glsl` | `VanillaFog`、`SelectionBox` | 无 | MC 专用：原版雾曲线读宿主雾参数，选择框是调试叠加；留在 `rendering/fog/vanilla_fog.glsl` |
| `GbufferData.glsl` | `CurveBlockLightSky`、`MaterialFromTex`、`CalculateMasks`、`ApplyMaterial` | `surface`：`ogxCurveBlockLightSky`、`ogxMaterialNormal`、`ogxMaterialAo`、`ogxTextureEmissive` | 部分：曲线与材质换算进库；gbuffer 通道布局与掩码位是 MC 约定 |
| `IndividualFounctions/AgX.glsl` | `AgX`、`ComputeCompressionMatrix`、`SlidePrimary` | `color`：`ogxAgx`、`ogxAgxContrast` | 已覆盖 |
| `IndividualFounctions/Bloom.glsl` | `BloomDownSample`、`AxialGaussianBlur`、`BicubicBlurTexture` | `post`：`ogxBloomDownsample`、`ogxAxialGaussianBlur`、`ogxBloomBicubic`、`ogxBloomChainCopy`；`math`：`ogxBicubicBlurTexture` | 已覆盖；五级泛光链的子图排布留在 `shaders/gfx/post.glsl` |
| `IndividualFounctions/CloudShadow.glsl` | `CloudShadowFromTex`、`GetSmoothCloudShadow` | `cloud`：`ogxCloudShadowCoord`、`ogxCloudShadowBicubic`、`ogxCloudShadowSample`、`ogxGlobalCloudShadow`、`ogxCloudShadowBlur` | 已覆盖 |
| `IndividualFounctions/DOF.glsl` | `CalculateCoCRadius`、`CoCSpread`、`DepthOfField`、`LinearDepth_From_ScreenDepth` | `post`：`ogxCocRadius`、`ogxDofLensFactor`、`ogxScreenDepthFromLinearDepth`、`ogxDofLinearDepth`、`ogxDofCocSpread`、`ogxDepthOfField` | 已覆盖 |
| `IndividualFounctions/EndSky.glsl` | `CalculateStars`、`PlanetEnd2`、`WarpSpace`、`Calculate3DNoise`、`CalculateCloudFBM` | `atmosphere`：`ogxStarsStable`、`ogxStarsColored`、`ogxStar*`；`planet`：`ogxPlanetEnd`；`fog`：`ogxEnd3dNoise`、`ogxCloudFbm`；`math`：`ogxWarpSpace`、`ogxRotateMatrix` | 已覆盖 |
| `IndividualFounctions/FsrEASU.glsl` | `FsrEasuTap`、`FsrEasuSet`、`FsrEasu` | `upscale`：`ogxFsrEasuTap`、`ogxFsrEasuSet`、`ogxFsrEasu`、`ogxFsr1`、`ogxCas` | 已覆盖 |
| `IndividualFounctions/GlobalIllumination.glsl` | `RSM`、`CalculateCameraVelocity`、`GI_TemporalFilter`、`GI_SpatialFilter` | `gi`：`ogxGiRsm`、`ogxGiCameraVelocity`、`ogxGiTemporalFilter`、`ogxGiSpatialFilter` | 已覆盖 |
| `IndividualFounctions/GTAO.glsl` | `GroundTruthBasedAmbientOcclusion`、`GTAOMultiBounce` | `gi`：`ogxGroundTruthAo`、`ogxAoMultiBounce` | 已覆盖 |
| `IndividualFounctions/LensGlareFlare.glsl` | `GetDistOffset`、`flare`、`orb`、`ring` | `post`：`ogxGlareDistOffset`、`ogxGlareFlare`、`ogxGlareOrb`、`ogxGlareRing` | 已覆盖 |
| `IndividualFounctions/MotionBlur.glsl` | `CalculateCameraVelocity`、`MotionBlur`、`GetExposureTiles` | `post`：`ogxMotionBlur`、`ogxExposureTileAverage` | 已覆盖 |
| `IndividualFounctions/NUBIS.glsl` | `NubisCumulus`、`SampleDensity`、`CloudLighting`、`CloudShadowTex` | `cloud_volume`：`ogxCumulusCurve`、`ogxCumulusSetPos`、`ogxCumulusSampleDensity`、`ogxCumulusLightning`、`ogxCumulusLighting`、`ogxCumulusMarch`、`ogxCumulusShadowTex` | 已覆盖 |
| `IndividualFounctions/Parallax.glsl` | `BilinearHeightSample`、`HeightBasedNormal`、`ParallaxOcclusionMapping` | `parallax`：`ogxParallaxHeightBilinear`、`ogxParallaxHeightNormal`、`ogxParallaxHitNormal`、`ogxParallaxSmooth`、`ogxParallaxSharp` | 已覆盖 |
| `IndividualFounctions/PhysicsOceans.glsl` | `physics_waveHeight`、`physics_waveNormal`、`physics_wavePixel` | `water`：`ogxOceanWaveSum`、`ogxOceanWaveHeight`、`ogxOceanWavesDefault` | 部分：迭代正弦与归一化进库；波形空间换算、涟漪贴图与三层泡沫噪声仍依赖宿主贴图，留在 `rendering/water/waves.glsl` |
| `IndividualFounctions/PlanarClouds.glsl` | `GetPlanarCloudsDensity`、`GetPlanarCloudsLightingDensity`、`PlanarClouds` | `cloud`：`ogxPlanarDistortion`、`ogxPlanarDensity`、`ogxPlanarLightingDensity`、`ogxPlanarCloudLightingDepth` | 已覆盖 |
| `IndividualFounctions/PrintFloat.glsl` | `PrintFloat`、`SevenSegment` | 无 | 未覆盖：调试用的屏幕数字，不参与画面链路，也不具备跨宿主复用价值 |
| `IndividualFounctions/Reflections/ReflectionFilter.glsl` | `AtrousWaveletFilter` | `reflection`：`ogxReflectionAtrousFilter` | 已覆盖 |
| `IndividualFounctions/Reflections/SSR.glsl` | `ScreenSpaceTracer`、`ProjectSky`、`sampleGGXVNDF`、`CalculateSpecularReflections` | `reflection`：`ogxScreenSpaceTrace`、`ogxReflectionSkyFacing`、`ogxSampleGgxVndf`、`ogxSpecularReflectionMix` | 已覆盖 |
| `IndividualFounctions/Ripple.glsl` | `GetRainAnimationTex`、`GetRainNormal`、`GetModulatedRainSpecular` | `water`：`ogxRainAnimationNormal`、`ogxRainSpecular`、`ogxPuddleCoverage`、`ogxPuddleRoughness` | 已覆盖 |
| `IndividualFounctions/UnderwaterVolumetricFog.glsl` | `UnderwaterVolumetricFog`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `fog_volume`：`ogxUnderwaterFog`、`ogxUnderwaterCaustics`；`water`：`ogxWavesNormalFromTex` | 已覆盖 |
| `IndividualFounctions/VolumetricFog.glsl` | `VolumetricFog`、`FogDensity`、`FogPhase`、`PowderEffect`、`simpleScattering` | `fog`：`ogxFogDensityHeight`、`ogxFogDensityNoise`、`ogxFogMarch`、`ogxLegacyPowder`、`ogxLegacyFogPhase`、`ogxMultiScatteringPhases`；`fog_volume`：`ogxVolumetricFog`；`atmosphere_model`：`ogxAtmoSimpleScattering` | 已覆盖 |
| `IndividualFounctions/WaterWaves.glsl` | `GetWaves`、`GetWavesNormal`、`GetWaterParallaxCoord` | `water`：`ogxTextureSmooth`、`ogxAlmostIdentity`、`ogxWaves`、`ogxWavesNormal`、`ogxWaterParallax` | 已覆盖 |
| `Utilities.glsl` | `LinearToCurve`、`CurveToLinear`、`DoNightEye`、`facos`、`atan2`、`remapSaturate` | `math`：`ogxLinearToCurve`、`ogxCurveToLinear`、`ogxDoNightEye`、`ogxFastAcos`、`ogxAtan2`、`ogxRemapSaturate` 等 | 部分：`remap`（不夹紧版）、`minVec3`、`maxVec3` 没有对应实现，留在 `common/math.glsl`；`ogxMod`、`ogxEqual`、`ogxMatrixMul` 等仅库内 |

### 宿主文件（6 个）

| 参考文件 | 装的是什么 | 状态 |
| --- | --- | --- |
| `Settings.glsl` | 选项宏与常量 | MC 专用：对应本项目 `shaders/effects/` 的选项与 `options.py` 生成的菜单 |
| `UniformDeclare.glsl` | 加载器输入声明 | MC 专用：对应 `shaders/bind/` |
| `Uniform/GbufferTransforms.glsl` | 屏幕与视空间互换、深度换算 | MC 专用：矩阵约定来自加载器；纯换算部分见 `math`、`post`、`shadow` |
| `Uniform/ShadowTransforms.glsl` | 阴影投影与扭曲 | 部分：扭曲与投影进 `shadow`（`ogxShadowScreenPosDistorted`、`ogxDistortShadowPos`）；矩阵本身由宿主给 |
| `Uniform/ShadowTransformsEnd.glsl` | 末地阴影投影 | 同上，末地只是换了一组矩阵 |
| `Uniform/ShadowModelViewEnd.glsl` | 末地阴影视图矩阵 | MC 专用 |

### 程序入口（37 个）

`Lib/Programs/` 的 `CompositeVS`、`Final`、`PostVS` 与 34 个 gbuffers 阶段是壳子：声明附件、选宏、调用上面的库。它们的对应物是本项目的 `shaders/rendering/` 与 `world0/`、`world-1/`、`world1/` 入口，绘制顺序与阶段职责写在 `docs/rendering.md`，这里不重复登记。

## Eclipse

Eclipse 的 `shaders/lib/` 共 45 个文件，程序文件 594 个只作阶段壳子，口径同上。

| 参考效果 | 参考入口函数 | omni-gfx 对应 | 状态 |
| --- | --- | --- | --- |
| `aurora.glsl` | `aurora`、`triNoise2d` | `atmosphere`：`ogxAurora` | 已覆盖 |
| `bayer_matrix.glsl` | `bayerDither` | `math`：`ogxBayer2`、`ogxBayer4`、`ogxBayer8`、`ogxBayer64` | 已覆盖 |
| `blocks.glsl` | 方块编号与属性表 | 无 | MC 专用：编号表由资源包与 `block.properties` 决定 |
| `bokeh.glsl` | `rotate` 与光圈形状 | `post`：散焦核在 `ogxDepthOfField` | 部分：散焦与色散进库；Eclipse 的多边形光圈形状没有独立实现 |
| `climate_settings.glsl` | `YearCycleColor`、`BiomeFogDensity`、`BiomeVLFogColors`、`FogDensities` | `weather`：`ogxSeason`、`ogxStormColor` | 部分：季节与风暴色进库；生物群系雾密度与颜色表是 MC 数据，留在 `effects/weather/` |
| `color_dither.glsl` | `fp10Dither`、`fp16Dither`、`int10Dither`、`int16Dither` | `math`：`ogxBayer*`、`ogxInterleavedGradientNoise` | 部分：有序抖动与噪声抖动进库；按目标精度裁位的四种抖动未实现 |
| `color_transforms.glsl` | `ToneMap_Hejl2015`、`HableTonemap`、`reinhard`、`ACESFilm`、`Tonemap_Lottes`、`Tonemap_Uchimura_Modified`、`LinearTosRGB` | `color`：`ogxAces`、`ogxRrtOdtFit`、`ogxAgx`、`ogxAgxContrast`、`ogxTonemapNone`、`ogxLinearToGamma2`、`ogxGammaToLinear2` | 部分：ACES、AgX、线性与伽马互换进库；Hejl、Hable、Reinhard、Lottes、Uchimura 五种曲线未实现 |
| `diffuse_lighting.glsl` | `doBlockLightLighting`、`doIndirectLighting`、`GetHandLight`、`SSRT_Handlight_Shadows`、`calculateFlashlight` | `surface`：`ogxBlockLight`、`ogxCurveBlockLight*`；`shadow`：`ogxSunScreenShadow` | 部分：块光与间接光曲线进库；手持光阴影与手电筒依赖加载器的手部深度与玩家输入 |
| `DistantHorizons_projections.glsl` | `toScreenSpace_DH`、`toClipSpace3_DH` | 无 | MC 专用：远景模组的投影约定，只在加载器提供远景深度时才有意义 |
| `end_fog.glsl` | `fogShape`、`SwirlAroundOrigin`、`VolumeBounds`、`densityAtPosFog` | `fog`：`ogxEndVortexNoise`、`ogxEndVortexSwirl`、`ogxEndVortexBounds`、`ogxEndVortexShape`、`ogxEndVortexLightPhase`、`ogxEndVortexLighting`、`ogxEndVortexFog`、`ogxEndFogDensity` | 已覆盖 |
| `entities.glsl` | 实体材质表 | `surface`：材质法线与自发光换算 | MC 专用：实体编号与材质位由 `entity.properties` 决定 |
| `gameplay_effects.glsl` | `applyGameplayEffects` | `math`：`ogxDoNightEye` | MC 专用：药水与受伤效果的状态由游戏给，光影只做画面换算 |
| `hsv.glsl` | `RgbToHsv`、`HsvToRgb` | `math`：`ogxRgbToHsv`；`color`：`ogxHsvToRgb` | 已覆盖 |
| `indirect_lighting_effects.glsl` | `rayTrace_GI`、`BilateralUpscale_SSAO`、`SpiralSample` | `gi`：`ogxGiTemporalFilter`、`ogxGiSpatialFilter`、`ogxGroundTruthAo` | 部分：时域与空域滤波进库；屏幕空间光线与双边升采样的采样组织仍由 `rendering/lighting/gi.glsl` 完成 |
| `items.glsl` | 物品编号表 | 无 | MC 专用：编号来自 `item.properties` |
| `lightning_stuff.glsl` | `Iris_Lightningflash`、`Iris_Lightningflash_VLcloud`、`Iris_Lightningflash_VLfog` | `fog_volume`：`ogxFogLightning`；`cloud_volume`：`ogxCumulusLightning` | 已覆盖 |
| `lpv_blocks.glsl` | LPV 方块表 | 无 | MC 专用：与 `block.properties` 的编号一一对应 |
| `lpv_buffer.glsl` | LPV 缓冲布局 | 无 | MC 专用：SSBO 布局由加载器与 `rendering/lpv.glsl` 共同约定 |
| `lpv_common.glsl` | `GetLpvPosition` | 无 | MC 专用：体素网格原点与尺寸来自宿主选项 |
| `lpv_render.glsl` | `SampleLpvLinear`、`GetLpvBlockLight`、`GetLpvSkyLight` | 无 | 未覆盖：光传播体积仍在 `rendering/lpv.glsl`，与 SSBO 布局绑定，尚未抽进库 |
| `nether_fog.glsl` | `GetVolumetricFog`、`cloudVol`、`densityAtPosFog` | `fog`：`ogxNetherFogDensityAt`、`ogxNetherFogCloudVolume` | 部分：密度与云体积进库；羽流、雾霭、顶烟三段步进留在 `rendering/world/nether.glsl`，见 `docs/rendering.md` 第 9 项 |
| `oceans.glsl` | `physics_waveHeight`、`physics_waveNormal`、`physics_wavePixel` | `water`：`ogxOceanWaveSum`、`ogxOceanWaveHeight` | 部分：与 iterationT 同一套循环，已合并到同一个库函数；涟漪与泡沫仍在 `rendering/water/waves.glsl` |
| `overworld_fog.glsl` | `GetVolumetricFog`、`phaseRayleigh`、`densityAtPosFog` | `fog_volume`：`ogxVolumetricFog`、`ogxFogDensity`、`ogxFogLightMarch`、`ogxFogCloudBicubic` | 已覆盖 |
| `PhotonGTAO.glsl` | GTAO 采样与降噪 | `gi`：`ogxGroundTruthAo`、`ogxAoMultiBounce` | 已覆盖 |
| `projections.glsl` | `toClipSpace3`、`toScreenSpace`、`toWorldSpace`、`toShadowSpace` | `math`：`ogxMatrixMul`、`ogxMatrixMulPoint` 等 | MC 专用：矩阵来自加载器；纯乘法已进库但仅库内使用 |
| `res_params.glsl` | 分辨率参数 | 无 | MC 专用：屏幕尺寸由加载器给 |
| `ripples.glsl` | `ripples`、`hash12`、`hash22` | `water`：`ogxRainSpecular`、`ogxPuddleCoverage`、`ogxPuddleRoughness`；`noise`：`ogxHash13` | 部分：雨面高光与水洼参数进库；涟漪圆环本身留在 `rendering/water/rain.glsl` |
| `ROBOBO_sky.glsl` | `calculateAtmosphere`、`sky_transmittance`、`sky_opticalDepth` | `atmosphere`：`ogxAtmosphereSky`、`ogxAtmosphereOpticalDepth`、`ogxAtmosphereTransmittance` | 库内：解析版在库里，光影侧走同一套公式的查表版 `atmosphere_model`，所以库里这份暂无游戏内调用方 |
| `scene_controller.glsl` | `applySceneControllerParameters` | 无 | MC 专用：按维度、天气与群系切场景参数 |
| `settings.glsl` | 选项宏 | 无 | MC 专用：对应 `shaders/effects/` 与 `options.py` 生成的菜单 |
| `Shadow_Params.glsl` | `BiasShadowProjection`、`calcDistort` | `shadow`：`ogxShadowScreenPos`、`ogxShadowScreenPosDistorted`、`ogxDistortShadowPos` | 已覆盖 |
| `Shadows.glsl` | `GriAndEminShadowFix`、`applyShadowBias` | `shadow`：`ogxSunScreenShadow`、`ogxVariablePenumbraShadow` | 部分：比较与偏差思路进库；针对特定实体的偏移补丁是 MC 专用 |
| `sky_gradient.glsl` | `drawSun`、`drawMoon`、`drawRealMoon`、`sphereMap` | `atmosphere`：`ogxSunDisc`、`ogxMoonDiscReal`、`ogxMoonDiscDefault`、`ogxSkyProject`、`ogxSkyUnproject` | 已覆盖 |
| `specular.glsl` | `SampleVNDFGGX`、`CoordBase`、`frisvad`、`linZ` | `reflection`：`ogxSampleGgxVndf`、`ogxReflectionLinearDepth`、`ogxReflectionScreenDepth`、`ogxReflectionDhToScreenDepth`；`math`：`ogxTangentBasis` | 已覆盖 |
| `SSBOs.glsl` | SSBO 声明 | 无 | MC 专用：加载器扩展与缓冲布局 |
| `stars.glsl` | `NoisyStarField`、`StableStarField`、`starTemp`、`starplane`、`starbox` | `atmosphere`：`ogxStarNoisyField`、`ogxStarStableField`、`ogxStarTemperature`、`ogxStarPlane`、`ogxStarBox`、`ogxStarsStable`、`ogxStarsColored` | 已覆盖 |
| `TAA_jitter.glsl` | 抖动序列 | `sampling`：`ogxBlueNoise`、`ogxBayerTemporal` | 部分：噪声源进库；每帧抖动向量仍由顶点阶段按宿主帧号生成 |
| `texFiltering.glsl` | `smoothfilter`、`shadowsmoothfilter` | 无 | 未覆盖：阴影与贴图的自定义平滑取样没有对应实现 |
| `text_rendering.glsl` | `beginText`、`printFloat` 等 | 无 | 未覆盖：调试文字，理由同 iterationT 的 `PrintFloat` |
| `texture_filtering.glsl` | `sampleNearest`、`sampleRGSS` | `sampling`：`ogxTexelFetch` | 部分：最近点取样进库；旋转网格超采样（RGSS）未实现 |
| `util.glsl` | `facos`、`circlemap`、`calculateRoughSpecular`、`srgbToLinear`、`linearToSRGB` | `math`：`ogxFastAcos`、`ogxSrgbToLinear`、`ogxGammaToLinear`、`ogxTangentBasis` | 部分：反余弦与颜色空间换算进库；`circlemap` 与粗糙高光估算未实现 |
| `volumetricClouds.glsl` | `getCloudShape`、`densityAtPos`、`curl2D`、`getRainDensity` | `cloud`：`ogxCloudDensity`、`ogxCloudMarch`、`ogxCloudLight`；`noise`：`ogxWarp3`、`ogxFbm3` | 部分：云形状与步进进库；光影侧实际用 `cloud_volume` 的 NUBIS 路径，Eclipse 的降雨密度与 curl 噪声未移 |
| `voxel_common.glsl` | 体素索引与读取 | `voxel`：`ogxVoxelInside`、`ogxVoxelReflection` 等 8 个 | 已覆盖 |
| `voxel_write.glsl` | `SetVoxelBlock`、`PopulateShadowVoxel` | `voxel`：读取与追踪进库 | 部分：写入侧（阴影阶段把方块写进三维图）仍在 `rendering/reflection/voxel.glsl`，依赖阴影程序与方块编号 |
| `waterBump.glsl` | `waterCaustics`、`getWaterHeightmap`、`getWaveNormal` | `water`：`ogxWaterCaustics`、`ogxWavesNormalFromTex` | 部分：焦散与波法线进库；高度图泡沫取样仍在宿主 |

## 汇总

按上表 76 行逐项统计（iterationT 的 31 个算法文件、Eclipse 的 45 个文件）：

| 状态 | iterationT | Eclipse |
| --- | --- | --- |
| 已覆盖 | 23 | 12 |
| 部分 | 6 | 16 |
| 库内 | 0 | 1 |
| 未覆盖 | 1（`PrintFloat`） | 3（`lpv_render`、`texFiltering`、`text_rendering`） |
| MC 专用 | 1（`VanillaComposite`） | 13（编号表、SSBO、投影、场景参数、选项、调试叠加） |

iterationT 另有 6 个宿主文件，全部只服务 MC，已在上文单列，不计入这 31 行。

需要继续补的缺口按优先级排：

1. 光传播体积 `lpv_render.glsl`：现在整段在 `rendering/lpv.glsl`，是唯一还带完整算法的未覆盖项。
2. 阴影平滑取样 `texFiltering.glsl` 与图集超采样 `texture_filtering.glsl`：影响阴影边缘与远处贴图，属于观感缺口。
3. 五种色调映射曲线（Hejl、Hable、Reinhard、Lottes、Uchimura）与四种精度抖动：属于选项覆盖，缺了不影响基础画面。
4. 多边形光圈、涟漪圆环、高度图泡沫：三处都在美术风格上可见，但各自只有一个使用者，等风格定稿再决定是否迁库。

库里还有十个 `antialias` 细分步骤函数与八个 `atmosphere` 解析函数暂时没有调用方：前者是因为光影侧的 TAA 只调总入口，后者是因为光影走查表版。它们由测试世界覆盖，未在游戏内验证。
