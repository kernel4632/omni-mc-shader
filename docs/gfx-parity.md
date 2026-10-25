# 效果对照：iterationT 与 Eclipse → omni-gfx

本文件回答一个问题：两个参考包里的每一项效果，现在对应 `omni-gfx` 的哪个函数，还是仍然留在光影侧。它和 `docs/parity.md`（iterationT 移植合同、逐条偏离）、`docs/eclipse-parity.md`（Eclipse 合入项）分工不同：那两份讲“从哪来、改了什么”，这份讲“算法现在住哪里”。

## 口径与证据边界

- 覆盖对象是两个参考包的算法库：iterationT `shaders/Lib/` 下 31 个效果文件（另 6 个宿主文件单列），Eclipse `shaders/lib/` 下 45 个文件。算法对照共 76 行，逐项列在下表，不跳行。
- 程序入口不逐条列：iterationT `Lib/Programs/` 有 37 个文件、Eclipse 有 594 个程序文件，它们是阶段壳子，只调用上面的库。阶段划分与绘制顺序见 `docs/rendering.md`，迁移分片见 `docs/parity.md`。
- 状态只有五种，不用模糊说法：
  - **已覆盖**：参考文件的每个入口函数都能在生成库里找到等价实现。光影侧需要的那部分经 `shaders/gfx/` 适配层或 `shaders/rendering/` 调用到；暂时没有调用方的函数在状态后面单独标注“库内无调用方”。
  - **部分**：算式主体进库，剩余部分与宿主约定绑在一起，后面写明剩下什么、为什么不能搬。
  - **库内**：生成库里有实现，光影侧还没调用；一般只被库的测试世界或 SPIR-V 探针使用。
  - **未覆盖**：还没有对应实现。当前为 0 条。
  - **MC 专用**：依赖 Minecraft 的编号表、加载器约定、维度参数或调试界面，不适合放进通用库。每一条都给出参考包里的实际调用位置作为证据。
- 证据来源：`shaders/gfx/*.glsl` 的转发表、`shaders/` 里对 `ogx*` 函数的调用、`omni-gfx/src/*.slang` 的函数清单。状态按这三处实际内容判定，不按文件名相似判定。
- 未验证：没有在 Minecraft 里逐项比对画面，因此“已覆盖”只表示调用链存在且算式在库里，不表示两边像素完全一致。库内与 MC 专用两类没有画面链路，也不存在游戏内验证。

## iterationT 3.2.0

### 算法库（31 个文件）

| 参考效果 | 参考入口函数 | omni-gfx 对应 | 状态 |
| --- | --- | --- | --- |
| `BasicFounctions/Blocklight.glsl` | `BlockLighting`、`TextureLighting`、`TorchScreenSpaceShadow`、`HeldLighting`、`TorchSpecularHighlight` | `surface`：`ogxBlockLight`、`ogxCurveBlockLightSky`、`ogxCurveBlockLightTorch`；`shadow` 提供投影与比较 | 部分：块光曲线与打包光照进库；屏幕空间火把阴影与手持光仍由 `rendering/lighting/held_light.glsl` 组合宿主矩阵（`gbufferProjection`、`depthtex1`）与两只手的发光等级，这些输入只有加载器给得出 |
| `BasicFounctions/NetherColor.glsl` | `NetherLighting`、`NetherFogColor` | `fog`：`ogxNetherFogDensityAt`、`ogxNetherFogCloudVolume` | 部分：密度进库；生物群系雾色表留在 `rendering/world/nether.glsl`，那是 MC 数据，且与 `biome` 编号绑定 |
| `BasicFounctions/PrecomputedAtmosphere.glsl` | `ClampRadius`、`DistanceToTopAtmosphereBoundary`、`RenderSunDisc`、`RenderMoonDisc`、`RenderMoonDiscReflection` | `atmosphere_model`：`ogxAtmo*` 共 20 个；`atmosphere`：`ogxSunDisc`、`ogxMoonDiscReal`、`ogxMoonDiscDefault`、`ogxMoonDiscReflection` | 已覆盖 |
| `BasicFounctions/Sunlight_Shadow.glsl` | `VariablePenumbraShadow`、`ScreenSpaceShadow`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `shadow`：`ogxVariablePenumbraShadow`、`ogxScreenSpaceShadow`、`ogxSunScreenShadow`；`water`：`ogxWavesNormalFromTex`、`ogxWaterCaustics` | 已覆盖 |
| `BasicFounctions/TAA.glsl` | `SampleCurrColor`、`SamplePrevColor`、`RGB_To_YCoCg` 等 14 个 | `antialias`：`ogxTaaReproject` 与 `ogxRgbToYCoCg`、`ogxClipAabb`、`ogxBicubicTexture4` | 已覆盖：接入 `rendering/clarity/taa.glsl`；细分步骤函数暂无调用方 |
| `BasicFounctions/TAA_Nether.glsl` | `BicubicTextureVec4`、`SamplePreviousDepthBilinear` 等 | `antialias`：YCoCg、裁剪与重投影同一套 | 部分：重投影进库；下界把参考深度打包进七号画面的做法属于 `buffers_nether.glsl` 的格式约定，换引擎后这张图的内容完全不同，不能搬进纯计算库 |
| `BasicFounctions/TemporalNoise.glsl` | `BlueNoise`、`BlueNoiseTemproal`、`BayerTemproal` | `sampling`：`ogxBlueNoise`、`ogxBlueNoiseTemporal`、`ogxBayerTemporal` | 已覆盖 |
| `BasicFounctions/VanillaComposite.glsl` | `VanillaFog`、`SelectionBox` | 无 | MC 专用：原版雾曲线读宿主雾参数，选择框是调试叠加；留在 `rendering/fog/vanilla_fog.glsl` |
| `GbufferData.glsl` | `CurveBlockLightSky`、`MaterialFromTex`、`CalculateMasks`、`ApplyMaterial` | `surface`：`ogxCurveBlockLightSky`、`ogxMaterialNormal`、`ogxMaterialAo`、`ogxTextureEmissive` | 部分：曲线与材质换算进库；gbuffer 通道布局与掩码位是 MC 约定，`labPBR` 的位含义由资源包给出 |
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
| `IndividualFounctions/PrintFloat.glsl` | `PrintFloat`、`SevenSegment`、`DecimalPoint`、`PrintUintBinary` | 无 | MC 专用（调试叠加）：参考包里 `Final.glsl` 只有第 339 行的一行 `#include`，整个包没有任何一处调用 `PrintFloat`；函数输入是 `gl_FragCoord` 与屏幕像素偏移，输出是调试数字，不参与画面链路。搬进通用库只会得到一段没有使用者的代码，因此不迁，理由与证据都写在下方“四、四项未覆盖的结论”第 1 条 |
| `IndividualFounctions/Reflections/ReflectionFilter.glsl` | `AtrousWaveletFilter` | `reflection`：`ogxReflectionAtrousFilter` | 已覆盖 |
| `IndividualFounctions/Reflections/SSR.glsl` | `ScreenSpaceTracer`、`ProjectSky`、`sampleGGXVNDF`、`CalculateSpecularReflections` | `reflection`：`ogxScreenSpaceTrace`、`ogxReflectionSkyFacing`、`ogxSampleGgxVndf`、`ogxSpecularReflectionMix` | 已覆盖 |
| `IndividualFounctions/Ripple.glsl` | `GetRainAnimationTex`、`GetRainNormal`、`GetModulatedRainSpecular` | `water`：`ogxRainAnimationNormal`、`ogxRainSpecular`、`ogxPuddleCoverage`、`ogxPuddleRoughness` | 已覆盖 |
| `IndividualFounctions/UnderwaterVolumetricFog.glsl` | `UnderwaterVolumetricFog`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `fog_volume`：`ogxUnderwaterFog`、`ogxUnderwaterCaustics`；`water`：`ogxWavesNormalFromTex` | 已覆盖 |
| `IndividualFounctions/VolumetricFog.glsl` | `VolumetricFog`、`FogDensity`、`FogPhase`、`PowderEffect`、`simpleScattering` | `fog`：`ogxFogDensityHeight`、`ogxFogDensityNoise`、`ogxFogMarch`、`ogxLegacyPowder`、`ogxLegacyFogPhase`、`ogxMultiScatteringPhases`；`fog_volume`：`ogxVolumetricFog`；`atmosphere_model`：`ogxAtmoSimpleScattering` | 已覆盖 |
| `IndividualFounctions/WaterWaves.glsl` | `GetWaves`、`GetWavesNormal`、`GetWaterParallaxCoord` | `water`：`ogxTextureSmooth`、`ogxAlmostIdentity`、`ogxWaves`、`ogxWavesNormal`、`ogxWaterParallax` | 已覆盖 |
| `Utilities.glsl` | `LinearToCurve`、`CurveToLinear`、`DoNightEye`、`facos`、`atan2`、`remapSaturate`、`remap`、`minVec3`、`maxVec3` | `math`：`ogxLinearToCurve`、`ogxCurveToLinear`、`ogxDoNightEye`、`ogxFastAcos`、`ogxAtan2`、`ogxRemapSaturate`、`ogxRemap`（标量与三分量两个重载）、`ogxMinVec3`、`ogxMaxVec3`、`ogxFastSqrt`、`ogxSign`、`ogxMod`、`ogxEqual`、`ogxMatrixMul` | 已覆盖：最后三项是第三批补的，补齐后本文件不再有缺口；`ogxMod`、`ogxEqual`、`ogxMatrixMul` 等只被库内调用 |

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
| `bokeh.glsl` | `rotate` 与光圈形状 | `post`：`ogxBokehAperture`（第三批新增）；散焦核在 `ogxDepthOfField` | 已覆盖：多边形光圈的形状与旋转进库；六十、一百、一百二十个采样点的偏移表是数据，留在参考包，光影侧用圆形核 |
| `climate_settings.glsl` | `YearCycleColor`、`BiomeFogDensity`、`BiomeVLFogColors`、`FogDensities` | `weather`：`ogxSeason`、`ogxStormColor` | 部分：季节与风暴色进库；生物群系雾密度与颜色表是 MC 数据，留在 `effects/weather/` |
| `color_dither.glsl` | `fp10Dither`、`fp16Dither`、`int8Dither`、`int10Dither`、`int16Dither` | `noise`：`ogxWhiteNoise`、`ogxWhiteNoiseTemporal`、`ogxTriangleNoise`；`post`：`ogxDitherFloat`（按尾数位数，覆盖前两条）、`ogxDitherFixed`（按定点位数，覆盖后三条） | 已覆盖：五条入口按“浮点尾数”与“定点位数”合并成两个核心函数，位数变成参数；光影侧仍用拜尔与交错梯度噪声，新函数库内无调用方 |
| `color_transforms.glsl` | `ToneMap_Hejl2015`、`HableTonemap`、`reinhard`、`ACESFilm`、`Tonemap_Lottes`、`Tonemap_Uchimura_Modified`、`LinearTosRGB` | `color`：`ogxTonemapHejl`、`ogxTonemapHable`、`ogxTonemapReinhard`、`ogxTonemapAcesFilm`、`ogxTonemapLottes`、`ogxTonemapUchimura`、`ogxLinearToSrgb`；原有 `ogxAces`、`ogxAgx` | 已覆盖：七条入口全部补上；`ogxTonemapUchimura` 与参考有一处有意偏离，见下方“五、第三批补缺清单”第 2 条；光影界面仍只提供 ACES、AgX 与无压缩三档 |
| `diffuse_lighting.glsl` | `doBlockLightLighting`、`doIndirectLighting`、`GetHandLight`、`SSRT_Handlight_Shadows`、`calculateFlashlight` | `surface`：`ogxBlockLight`、`ogxCurveBlockLight*`；`shadow`：`ogxSunScreenShadow`；`lpv`：`ogxLpvBlockLight`、`ogxLpvSkyLight` | 部分：块光、间接光与体积光解码进库；手持光阴影与手电筒依赖加载器的 `MC_HAND_DEPTH`、两只手的发光等级与玩家输入，`rendering/lighting/held_light.glsl` 保留这部分 |
| `DistantHorizons_projections.glsl` | `toScreenSpace_DH`、`toClipSpace3_DH` | 无 | MC 专用：远景模组的投影约定，只在加载器提供远景深度时才有意义 |
| `end_fog.glsl` | `fogShape`、`SwirlAroundOrigin`、`VolumeBounds`、`densityAtPosFog` | `fog`：`ogxEndVortexNoise`、`ogxEndVortexSwirl`、`ogxEndVortexBounds`、`ogxEndVortexShape`、`ogxEndVortexLightPhase`、`ogxEndVortexLighting`、`ogxEndVortexFog`、`ogxEndFogDensity` | 已覆盖 |
| `entities.glsl` | 实体材质表 | `surface`：材质法线与自发光换算 | MC 专用：实体编号与材质位由 `entity.properties` 决定 |
| `gameplay_effects.glsl` | `applyGameplayEffects` | `math`：`ogxDoNightEye` | MC 专用：药水与受伤效果的状态由游戏给，光影只做画面换算 |
| `hsv.glsl` | `RgbToHsv`、`HsvToRgb` | `math`：`ogxRgbToHsv`；`color`：`ogxHsvToRgb` | 已覆盖 |
| `indirect_lighting_effects.glsl` | `rayTrace_GI`、`BilateralUpscale_SSAO`、`SpiralSample` | `gi`：`ogxGiTemporalFilter`、`ogxGiSpatialFilter`、`ogxGroundTruthAo`；`math`：`ogxSpiralSample`（第三批新增） | 部分：时域与空域滤波、螺旋采样序号进库；屏幕空间光线要步进宿主深度图并乘宿主矩阵，双边升采样要按缩放因子读四张深度样本，两者都留在 `rendering/lighting/gi.glsl` |
| `items.glsl` | 物品编号表 | 无 | MC 专用：编号来自 `item.properties` |
| `lightning_stuff.glsl` | `Iris_Lightningflash`、`Iris_Lightningflash_VLcloud`、`Iris_Lightningflash_VLfog` | `fog_volume`：`ogxFogLightning`；`cloud_volume`：`ogxCumulusLightning` | 已覆盖 |
| `lpv_blocks.glsl` | LPV 方块表 | 无 | MC 专用：与 `block.properties` 的编号一一对应 |
| `lpv_buffer.glsl` | LPV 缓冲布局 | 无 | MC 专用：SSBO 布局由加载器与 `rendering/lpv.glsl` 共同约定 |
| `lpv_common.glsl` | `GetLpvPosition` | `lpv`：`ogxLpvPosition`、`ogxLpvUvw`（第三批新增） | 已覆盖：坐标映射搬进库，宿主只把相机小数部分与半边长度传进来 |
| `lpv_render.glsl` | `SampleLpvLinear`、`GetLpvBlockLight`、`GetLpvSkyLight`、`lpvCurve` | `lpv`：`ogxLpvDecodeSample`、`ogxLpvBlockLight`、`ogxLpvSkyLight`、`ogxLpvCurve`、`ogxLpvEncode`、`ogxLpvDecode`、`ogxLpvRangeFalloff`、`ogxLpvApply`（第三批新增） | 已覆盖：解码、编码、光强曲线与合成全部进库，`rendering/lighting/lpv.glsl` 只剩选纹理、判越界与帧奇偶；`ogxLpvBlockLight` 与 `ogxLpvSkyLight` 库内无调用方，光影侧走 `ogxLpvApply` 的整段合成 |
| `nether_fog.glsl` | `GetVolumetricFog`、`cloudVol`、`densityAtPosFog` | `fog`：`ogxNetherFogDensityAt`、`ogxNetherFogCloudVolume` | 部分：密度与云体积进库；羽流、雾霭、顶烟三段步进留在 `rendering/world/nether.glsl`，因为每段的采样高度、次数与群系色都由宿主选项决定，见 `docs/rendering.md` 第 9 项 |
| `oceans.glsl` | `physics_waveHeight`、`physics_waveNormal`、`physics_wavePixel` | `water`：`ogxOceanWaveSum`、`ogxOceanWaveHeight` | 部分：与 iterationT 同一套循环，已合并到同一个库函数；涟漪与泡沫仍在 `rendering/water/waves.glsl`，取样的是宿主的波浪贴图 |
| `overworld_fog.glsl` | `GetVolumetricFog`、`phaseRayleigh`、`densityAtPosFog` | `fog_volume`：`ogxVolumetricFog`、`ogxFogDensity`、`ogxFogLightMarch`、`ogxFogCloudBicubic` | 已覆盖 |
| `PhotonGTAO.glsl` | GTAO 采样与降噪 | `gi`：`ogxGroundTruthAo`、`ogxAoMultiBounce` | 已覆盖 |
| `projections.glsl` | `toClipSpace3`、`toScreenSpace`、`toWorldSpace`、`toShadowSpace` | `math`：`ogxMatrixMul`、`ogxMatrixMulPoint` 等 | MC 专用：矩阵来自加载器；纯乘法已进库但仅库内使用 |
| `res_params.glsl` | 分辨率参数 | 无 | MC 专用：屏幕尺寸由加载器给 |
| `ripples.glsl` | `ripples`、`hash12`、`hash22` | `water`：`ogxRainSpecular`、`ogxPuddleCoverage`、`ogxPuddleRoughness`；`noise`：`ogxHash13`、`ogxHash12`、`ogxWhiteNoise` | 部分：雨面高光与水洼参数进库；涟漪本身是三张 `gaux1` 到 `gaux3` 动画贴图叠 `noisetex` 密度，取样源只有加载器能提供，留在 `rendering/water/rain.glsl` |
| `ROBOBO_sky.glsl` | `calculateAtmosphere`、`sky_transmittance`、`sky_opticalDepth` | `atmosphere`：`ogxAtmosphereSky`、`ogxAtmosphereOpticalDepth`、`ogxAtmosphereTransmittance` | 库内：解析版在库里，光影侧走同一套公式的查表版 `atmosphere_model`，所以库里这份暂无游戏内调用方 |
| `scene_controller.glsl` | `applySceneControllerParameters` | 无 | MC 专用：按维度、天气与群系切场景参数 |
| `settings.glsl` | 选项宏 | 无 | MC 专用：对应 `shaders/effects/` 与 `options.py` 生成的菜单 |
| `Shadow_Params.glsl` | `BiasShadowProjection`、`calcDistort` | `shadow`：`ogxShadowScreenPos`、`ogxShadowScreenPosDistorted`、`ogxDistortShadowPos` | 已覆盖 |
| `Shadows.glsl` | `GriAndEminShadowFix`、`applyShadowBias` | `shadow`：`ogxSunScreenShadow`、`ogxVariablePenumbraShadow` | 部分：比较与偏差思路进库；针对特定实体的偏移补丁是 MC 专用，它靠实体编号识别哪些模型需要额外偏移 |
| `sky_gradient.glsl` | `drawSun`、`drawMoon`、`drawRealMoon`、`sphereMap` | `atmosphere`：`ogxSunDisc`、`ogxMoonDiscReal`、`ogxMoonDiscDefault`、`ogxSkyProject`、`ogxSkyUnproject` | 已覆盖 |
| `specular.glsl` | `SampleVNDFGGX`、`CoordBase`、`frisvad`、`linZ` | `reflection`：`ogxSampleGgxVndf`、`ogxReflectionLinearDepth`、`ogxReflectionScreenDepth`、`ogxReflectionDhToScreenDepth`；`math`：`ogxTangentBasis` | 已覆盖 |
| `SSBOs.glsl` | SSBO 声明 | 无 | MC 专用：加载器扩展与缓冲布局 |
| `stars.glsl` | `NoisyStarField`、`StableStarField`、`starTemp`、`starplane`、`starbox` | `atmosphere`：`ogxStarNoisyField`、`ogxStarStableField`、`ogxStarTemperature`、`ogxStarPlane`、`ogxStarBox`、`ogxStarsStable`、`ogxStarsColored` | 已覆盖 |
| `TAA_jitter.glsl` | 抖动序列 | `sampling`：`ogxTaaJitter`（第三批新增）、`ogxBlueNoise`、`ogxBayerTemporal` | 已覆盖：四帧与八帧两套序列进库，编译期的两套表改成 `responsive` 参数；光影侧仍在顶点阶段按帧号自算抖动，库内无调用方 |
| `texFiltering.glsl` | `smoothfilter`、`shadowsmoothfilter` | `sampling`：`ogxSmoothFilter`、`ogxShadowSmoothFilter`（第三批新增） | 库内：平滑曲线重排与阴影比较取样都进库；参考包里这个文件没有任何 `#include`，是三份程序各自的局部版本在起作用，光影侧也没有对应选项，因此暂无调用方 |
| `text_rendering.glsl` | `beginText`、`printFloat` 等 | 无 | MC 专用（调试叠加）：参考包里只有 `final.fsh` 第 255 到 292 行使用，整段都在 `#if DEBUG_VIEW == ...` 分支内；它靠全局可变的文本游标逐字推进，属于调试界面而不是渲染算法，证据见下方“四、四项未覆盖的结论”第 2 条 |
| `texture_filtering.glsl` | `sampleNearest`、`sampleRGSS` | `sampling`：`ogxSampleNearest`、`ogxRgssSample`、`ogxTexelFetch`（第三批新增前两条） | 已覆盖：最近点取样与旋转网格超采样进库；光影侧没有贴图过滤模式选项，两条暂无调用方 |
| `util.glsl` | `facos`、`circlemap`、`calculateRoughSpecular`、`srgbToLinear`、`linearToSRGB` | `math`：`ogxFastAcos`、`ogxCircleMap`、`ogxRoughSpecularDirection`、`ogxSrgbToLinear`、`ogxLinearToSrgb`、`ogxTangentBasis` | 已覆盖：最后四项由第三批补齐，圆盘点列与螺旋方向用黄金角，与参考同一常数 |
| `volumetricClouds.glsl` | `getCloudShape`、`densityAtPos`、`curl2D`、`getRainDensity` | `cloud`：`ogxCloudDensity`、`ogxCloudMarch`、`ogxCloudLight`、`ogxCloudRainDensity`（第三批新增）；`noise`：`ogxWarp3`、`ogxFbm3` | 部分：云形状、步进与降雨密度进库；`curl2D` 依赖参考包自己的一套 perlin 梯度噪声，光影侧走 `cloud_volume` 的 NUBIS 路径，搬过来没有调用方，暂时不迁 |
| `voxel_common.glsl` | 体素索引与读取 | `voxel`：`ogxVoxelInside`、`ogxVoxelReflection` 等 8 个 | 已覆盖 |
| `voxel_write.glsl` | `SetVoxelBlock`、`PopulateShadowVoxel` | `voxel`：读取与追踪进库；`lpv`：`ogxLpvPosition` 给出同一套坐标映射 | 部分：写入侧（阴影阶段把方块写进三维图）仍在 `rendering/reflection/voxel.glsl` 与 `rendering/lighting/lpv.glsl`，它依赖阴影程序阶段宏、方块编号与 `imageStore` 布局 |
| `waterBump.glsl` | `waterCaustics`、`getWaterHeightmap`、`getWaveNormal` | `water`：`ogxWaterCaustics`、`ogxWavesNormalFromTex` | 部分：焦散与波法线进库；高度图泡沫取样仍在宿主，读取的是资源包的泡沫贴图 |

## 汇总

按上表 76 行逐项统计（iterationT 的 31 个算法文件、Eclipse 的 45 个文件）：

| 状态 | iterationT | Eclipse |
| --- | --- | --- |
| 已覆盖 | 24 | 20 |
| 部分 | 5 | 10 |
| 库内 | 0 | 2 |
| 未覆盖 | 0 | 0 |
| MC 专用 | 2（`PrintFloat`、`VanillaComposite`） | 13（编号表、SSBO、投影、场景参数、选项、调试叠加、调试文字） |

iterationT 另有 6 个宿主文件，全部只服务 MC，已在上文单列，不计入这 31 行。

第三批（2026-10-25）之后没有未覆盖项。剩余 15 条部分覆盖与 2 条库内都不缺“纯算式”，缺的是只有宿主才有的数据源，逐条列在下一节。

## 四、四项未覆盖的结论

1. **`PrintFloat`（iterationT）按 MC 专用处理，不迁。** 证据：`references/iterationT/shaders/Lib/Programs/Final.glsl` 第 339 行只有 `#include "/Lib/IndividualFounctions/PrintFloat.glsl"`，在整个参考包里搜索 `PrintFloat(`、`PrintUintBinary(`、`SevenSegment(`，调用点全部落在这个库文件内部，没有任何程序调用它。它的参数是屏幕像素坐标与缩放，输出是七段数码管的点亮值，只服务调试读数。搬进通用库等于把一段没有任何使用者的调试界面代码塞进算法库，因此状态改成 MC 专用（调试叠加），不新建模块。
2. **`text_rendering`（Eclipse）按 MC 专用处理，不迁。** 证据：`references/Eclipse/shaders/dimensions/final.fsh` 第 255 到 292 行是唯一使用位置，整段包在 `#if DEBUG_VIEW == ...` 里，用于在画面上打印着色器版本与提示文字。实现上它有一个全局 `Text` 结构，`beginText`、`printChar`、`endText` 依次改写同一个对象，属于立即模式的调试界面；字模是六十七个常量位图的字体数据。通用库若要做调试叠加，应该单独设计显式状态对象，而不是把这个全局状态机原样搬过去。
3. **`lpv_render`（Eclipse）已迁入 `lpv` 模块。** `lpvCurve`、`SampleLpvLinear` 的解码、`GetLpvBlockLight`、`GetLpvSkyLight` 与写入端的编码、边缘淡出、合成共九个函数进库，`shaders/rendering/lighting/lpv.glsl` 只留纹理选择、越界判断与帧奇偶。默认关闭 LPV，因此默认画面不变；开着 LPV 时数值逐项对齐原实现。
4. **`texFiltering`（Eclipse）已迁入 `sampling` 模块，状态为库内。** `smoothfilter` 与 `shadowsmoothfilter` 都是“转纹素坐标、平滑重排采样点、换回纹理坐标再取样”，已写成 `ogxSmoothFilter` 与 `ogxShadowSmoothFilter`。参考包里这个文件没有任何 `#include`：三份程序各自写了一份局部 `smoothfilter`，所以它本来就是没有消费者的工具文件。光影侧没有贴图过滤模式选项，暂不接线。

## 五、第三批补缺清单

下表列出这一批真正写进库的东西，方便下次核对“改了状态”还是“改了实现”。

| 参考文件 | 新增或补齐的库函数 | 光影侧是否调用 |
| --- | --- | --- |
| iterationT `Utilities.glsl` | `ogxRemap`（标量与三分量）、`ogxMinVec3`、`ogxMaxVec3` | 否，库内 API |
| Eclipse `color_transforms.glsl` | `ogxTonemapHejl`、`ogxTonemapHable`、`ogxTonemapReinhard`、`ogxTonemapAcesFilm`、`ogxTonemapLottes`、`ogxTonemapUchimura`、`ogxLinearToSrgb` | 否，界面仍只给三档 |
| Eclipse `color_dither.glsl` | `ogxWhiteNoise`、`ogxWhiteNoiseTemporal`、`ogxTriangleNoise`、`ogxDitherFloat`、`ogxDitherFixed` | 否 |
| Eclipse `util.glsl` | `ogxCircleMap`、`ogxRoughSpecularDirection`、`ogxLinearToSrgb` | 否 |
| Eclipse `indirect_lighting_effects.glsl` | `ogxSpiralSample` | 否 |
| Eclipse `bokeh.glsl` | `ogxBokehAperture` | 否 |
| Eclipse `TAA_jitter.glsl` | `ogxTaaJitter` | 否 |
| Eclipse `texture_filtering.glsl` | `ogxSampleNearest`、`ogxRgssSample` | 否 |
| Eclipse `volumetricClouds.glsl` | `ogxCloudRainDensity` | 否 |
| Eclipse `lpv_render.glsl`、`lpv_common.glsl` | `ogxLpvCurve`、`ogxLpvUvw`、`ogxLpvPosition`、`ogxLpvDecodeSample`、`ogxLpvBlockLight`、`ogxLpvSkyLight`、`ogxLpvEncode`、`ogxLpvDecode`、`ogxLpvRangeFalloff`、`ogxLpvApply` | 是，`rendering/lighting/lpv.glsl` 与 `rendering/fog/volumetric.glsl` |
| Eclipse `texFiltering.glsl` | `ogxSmoothFilter`、`ogxShadowSmoothFilter` | 否 |

两处有意偏离，必须记住：

1. `ogxTonemapUchimura` 修正了参考实现的参数顺序。参考写 `smoothstep(x, 0.0, m)`，把输入值当成下边界，按 GLSL 规则会得到恒为零的权重，三段拼接里出现负权重；迁入时改成 `smoothstep(0.0, m, x)`。没有调用方，因此不影响现有画面。
2. `ogxTriangleNoise` 在中心正好为零时补了一个极小分母，避免参考实现里的 `inversesqrt(0)` 产生无定义值。

## 六、剩余十五项部分覆盖的理由

每条都指向具体数据源，不写“以后再说”。

1. iterationT `Blocklight.glsl`：屏幕空间火把阴影要 `gbufferProjection`、`depthtex1` 与两只手的发光等级，见 `rendering/lighting/held_light.glsl`。
2. iterationT `NetherColor.glsl`：生物群系雾色按 `biome` 编号查表，表本身是 MC 数据。
3. iterationT `TAA_Nether.glsl`：下界历史深度打包在七号画面，格式由 `buffers_nether.glsl` 约定。
4. iterationT `GbufferData.glsl`：通道布局与掩码位是加载器与资源包约定，`labPBR` 的位含义不能由通用库猜。
5. iterationT `PhysicsOceans.glsl`：波形空间换算与三层泡沫读的是宿主波浪贴图。
6. Eclipse `climate_settings.glsl`：生物群系雾密度与颜色是 MC 数据。
7. Eclipse `diffuse_lighting.glsl`：手持光阴影要 `MC_HAND_DEPTH` 与玩家输入。
8. Eclipse `indirect_lighting_effects.glsl`：屏幕空间光线要步进宿主深度图并乘宿主矩阵，双边升采样按缩放因子读四张深度样本。
9. Eclipse `nether_fog.glsl`：三段步进的高度、次数与群系色由宿主选项决定。
10. Eclipse `oceans.glsl`：涟漪与泡沫读宿主波浪贴图。
11. Eclipse `ripples.glsl`：三张 `gaux` 动画贴图加 `noisetex` 密度，取样源只有加载器能提供。
12. Eclipse `Shadows.glsl`：实体偏移补丁靠实体编号识别模型。
13. Eclipse `volumetricClouds.glsl`：`curl2D` 依赖参考包自己的 perlin 梯度噪声，光影侧走 NUBIS，没有调用方。
14. Eclipse `voxel_write.glsl`：写入侧在阴影阶段，依赖阶段宏、方块编号与 `imageStore` 布局。
15. Eclipse `waterBump.glsl`：高度图泡沫读资源包贴图。

## 七、未验证

- 库内与 MC 专用两类没有画面链路，只有 SPIR-V 探针与 GLSL 编译作证据。
- 已覆盖项只验证了调用链与编译，没有在游戏内做逐像素对比；默认画面不变的理由是“新函数没有调用方、被改写的调用点逐项保持原算式”，而不是截图比对。
