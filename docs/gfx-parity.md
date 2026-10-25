# 效果对照：iterationT 与 Eclipse → omni-gfx

这份文件回答一个问题：两个参考包里的每一项效果，现在对应 `omni-gfx` 的哪个函数，还是仍然留在光影侧。它和 `docs/parity.md`（iterationT 移植合同、逐条偏离）、`docs/eclipse-parity.md`（Eclipse 合入项）分工不同：那两份讲“从哪来、改了什么”，这份讲“算法现在住哪里、还有哪部分只服务 Minecraft”。

本次按 `omni-gfx/src/*.slang`、`references/iterationT/shaders/Lib/`、`references/Eclipse/shaders/lib/` 的实际源码逐项重建。上一版表里“已覆盖”和“部分”的分界有几处已经过时，本版按现在的函数与调用点重判，不照抄旧状态。

## 一、口径与证据边界

- 覆盖对象是两个参考包的算法库：iterationT `shaders/Lib/` 下 31 个效果文件（另 6 个宿主文件单列），Eclipse `shaders/lib/` 下 45 个文件。算法对照共 76 行，逐项列在下表，不跳行。
- 程序入口不逐条列：iterationT `Lib/Programs/` 有 37 个文件、Eclipse 有 594 个程序文件，它们是阶段壳子，只调用上面的库。阶段划分与绘制顺序见 `docs/rendering.md`，迁移分片见 `docs/parity.md`。
- 状态只有五种，不用模糊说法：
  - **已覆盖**：参考文件的每个入口函数都能在生成库里找到等价实现，光影侧需要的那部分经适配层真正调用到。
  - **库内**：生成库里有等价实现，光影侧暂时没有调用方。一般只被库的测试世界、SPIR-V 探针或将来接入的引擎使用。
  - **MC 专用**：依赖 Minecraft 的编号表、加载器约定、维度参数或调试界面，不适合放进通用库。每一条都给出参考包里的实际调用位置或依赖作为证据。
  - **部分**：算式主体进库，剩余部分与宿主约定绑在一起。本版保留 0 条；原先的 15 条已在第三节逐条处理，能搬的搬进库，不能搬的拆成“已覆盖的通用部分 + MC 专用的宿主部分”或“库内”。
  - **未覆盖**：还没有对应实现。本版为 0 条。
- 证据来源：`shaders/gfx/*.glsl` 的转发表、`shaders/` 里对 `ogx*` 函数的调用、`omni-gfx/src/*.slang` 的函数清单。状态按这三处实际内容判定，不按文件名相似判定。
- 未验证：没有在 Minecraft 里逐项比对画面，因此“已覆盖”只表示调用链存在且算式在库里，不表示两边像素完全一致。库内与 MC 专用两类没有画面链路，也不存在游戏内验证。

## 二、24 个模块与参考来源

生成库当前 24 个模块。下表一项一行：模块负责的算法、直接对应的参考文件、光影侧是否调用。函数计数含重载，只用于判断规模，不是接口合同。

| 模块 | 行数 | 公开函数 | 直接对应的参考 | 光影侧调用 |
| --- | --- | --- | --- | --- |
| `math` | 541 | 72 | iterationT `Utilities.glsl`；Eclipse `hsv.glsl`、`util.glsl`、`bayer_matrix.glsl`、`color_dither.glsl`、`TAA_jitter.glsl`、`indirect_lighting_effects.glsl` 的采样函数；本轮新增 `ogxCurve01`、`ogxPuddleRoughness`、`ogxR2Sample`、`ogxCosineHemisphere`、`ogxConvertHandDepth3` | 是，共用数学与光斑曲线 |
| `color` | 251 | 24 | iterationT `AgX.glsl`；Eclipse `color_transforms.glsl`、`hsv.glsl` | 是，色调映射与调色 |
| `sampling` | 140 | 11 | iterationT `TemporalNoise.glsl`；Eclipse `TAA_jitter.glsl`、`texFiltering.glsl`、`texture_filtering.glsl` | 是，蓝噪声与抖动 |
| `noise` | 180 | 17 | Eclipse `color_dither.glsl`、`volumetricClouds.glsl` 的哈希与噪声；本轮新增二维向量哈希、二维梯度噪声与旋度 | 是，雾与云；旋度库内 |
| `atmosphere` | 587 | 47 | iterationT `PrecomputedAtmosphere.glsl`、`EndSky.glsl`；Eclipse `aurora.glsl`、`sky_gradient.glsl`、`stars.glsl`、`ROBOBO_sky.glsl` | 是，天空与日月 |
| `atmosphere_model` | 367 | 37 | iterationT `PrecomputedAtmosphere.glsl` 的查表部分、`VolumetricFog.glsl` 的简化散射 | 是，预计算大气 |
| `cloud` | 408 | 21 | iterationT `CloudShadow.glsl`、`PlanarClouds.glsl`；Eclipse `volumetricClouds.glsl` 的雨密度 | 是，云影与平面云 |
| `cloud_volume` | 197 | 7 | iterationT `NUBIS.glsl`；Eclipse `volumetricClouds.glsl` 的形状、步进与光照 | 是，体积云 |
| `water` | 621 | 34 | iterationT `WaterWaves.glsl`、`PhysicsOceans.glsl`、`Ripple.glsl`、`UnderwaterVolumetricFog.glsl`；Eclipse `oceans.glsl`、`waterBump.glsl`、`ripples.glsl` | 是，水面；Eclipse 的雨点涟漪、水面高度与焦散函数库内 |
| `fog` | 413 | 32 | iterationT `NetherColor.glsl`、`VolumetricFog.glsl`；Eclipse `nether_fog.glsl`、`end_fog.glsl`、`climate_settings.glsl` 的群系雾 | 是，下界配色、雾色与群系雾 |
| `fog_volume` | 387 | 10 | iterationT `VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`；Eclipse `overworld_fog.glsl`、`nether_fog.glsl` | 是，体积雾与下界三段雾 |
| `shadow` | 440 | 18 | iterationT `Sunlight_Shadow.glsl`、`Blocklight.glsl` 的屏幕阴影；Eclipse `Shadow_Params.glsl`、`Shadows.glsl` | 是，阴影比较；Eclipse 的两条阴影修补库内 |
| `gi` | 478 | 11 | iterationT `GlobalIllumination.glsl`、`GTAO.glsl`；Eclipse `PhotonGTAO.glsl`、`indirect_lighting_effects.glsl` | 是，全局光与遮蔽 |
| `reflection` | 274 | 16 | iterationT `Reflections/SSR.glsl`、`Reflections/ReflectionFilter.glsl`；Eclipse `specular.glsl` | 是，屏幕空间反射 |
| `post` | 516 | 29 | iterationT `Bloom.glsl`、`DOF.glsl`、`LensGlareFlare.glsl`、`MotionBlur.glsl`；Eclipse `bokeh.glsl`、`color_dither.glsl` | 是，泛光、景深、眩光 |
| `antialias` | 262 | 14 | iterationT `TAA.glsl`、`TAA_Nether.glsl` | 是，主世界与下界重投影 |
| `weather` | 166 | 8 | Eclipse `climate_settings.glsl`；本轮新增四季上色与时段雾密度 | 部分调用；四季与时段函数库内 |
| `surface` | 205 | 16 | iterationT `GbufferData.glsl`、`Blocklight.glsl`；Eclipse `diffuse_lighting.glsl`；本轮新增物理材质解码、方块光曲线、间接光、光斑与手持光 | 是，材质解码与方块光 |
| `parallax` | 284 | 6 | iterationT `Parallax.glsl` | 是，视差 |
| `voxel` | 148 | 10 | Eclipse `voxel_common.glsl`、`voxel_write.glsl` 的索引部分 | 是，反射体素；写入索引库内 |
| `upscale` | 155 | 22 | iterationT `FsrEASU.glsl` | 是，放大与锐化 |
| `planet` | 116 | 1 | iterationT `EndSky.glsl` 的末地行星 | 是，末地行星 |
| `accretion` | 108 | 2 | iterationT `EndSky.glsl` 的吸积盘与空间扭曲 | 是，末地天空 |
| `lpv` | 89 | 10 | Eclipse `lpv_common.glsl`、`lpv_render.glsl`、`voxel_write.glsl` 的写入光表约定 | 是，彩色方块光 |

模块之间的依赖只在生成器里解析，不新增运行时框架：`surface` 只依赖 `math`；`water`、`fog`、`fog_volume`、`shadow` 的依赖仍与迁移前一致。本轮没有把 Minecraft、Iris、`OMNI_*`、`colortex`、`noisetex` 等宿主符号带进库；测试逐模块扫描生成文本。

## 三、原 15 条部分覆盖现在怎样了

这一节是本次重点。每条先写原先卡在哪里，再写现在搬了什么、还剩什么。剩余部分要么有光影侧调用，要么给出只服务 Minecraft 的证据。

| 参考文件 | 原先的剩余部分 | 本次处理 | 现在的状态 |
| --- | --- | --- | --- |
| iterationT `BasicFounctions/Blocklight.glsl` | 屏幕空间火把阴影、手持光、手电筒与高光留在宿主 | 屏幕阴影步进早已在 `shadow`；本轮把光斑形状 `ogxSpotShape`、光束指向 `ogxFlashlightAimDirection` 搬进 `surface`，`held_light.glsl` 只传选项；`ogxHandLight` 的三次方衰减也进库，LPV 手持光已调用 | 已覆盖通用部分；`HeldLighting`、`TorchSpecularHighlight` 标为 MC 专用，证据见第六节第 1 条 |
| iterationT `BasicFounctions/NetherColor.glsl` | 五个群系的配色与雾色表留在宿主 | `ogxNetherBiomeLighting`、`ogxNetherBiomeFogColor` 进 `fog`，宿主只传五个平滑权重与亮度、密度选项；`rendering/world/nether.glsl` 已改为调用 | 已覆盖 |
| iterationT `BasicFounctions/TAA_Nether.glsl` | 文档原写“历史深度打包不能搬” | 核对源码后确认 `ogxTaaPrevDepthBilinear`、`ogxTaaPrevDepthMinmax`、`packedDepth` 已在 `antialias`，宿主 `clarity/taa.glsl` 的下界重载已在调用；旧说明过期 | 已覆盖，本次只修正文档，不改代码 |
| iterationT `GbufferData.glsl` | 材质解码与掩码表留在宿主 | `ogxPbrMaterialFromTex` 进 `surface`，`bind_material_from_tex` 只复制六个字段；掩码表保留在 `bind/gbuffer.glsl` | 已覆盖材质解码；掩码表标为 MC 专用，证据见第六节第 2 条 |
| iterationT `IndividualFounctions/PhysicsOceans.glsl` | 波形空间换算、涟漪贴图、三层泡沫留在宿主 | `ogxOceanWaveSpace`、`ogxOceanWaveDirection`、`ogxOceanWaveNormal`、`ogxOceanNormalWithRipple`、`ogxOceanFoam`、`ogxOceanPixel` 进 `water`；`waves.glsl` 只传贴图、纹素大小与选项 | 已覆盖 |
| Eclipse `climate_settings.glsl` | 群系雾密度、雾色与时段雾留在宿主 | `ogxBiomeFogColor`、`ogxBiomeFogDensity` 进 `fog` 并由 `bind/world/biome.glsl` 调用；`ogxYearCycleColor`、`ogxFogDensities` 进 `weather` | 已覆盖群系部分；四季与时段函数库内，宿主仍用自己的季节与时段选项 |
| Eclipse `diffuse_lighting.glsl` | 方块光曲线、间接光、手持光、手部阴影与手电筒 | `ogxBlockLightCurveEclipse`、`ogxDoIndirectLighting`、`ogxHandLight` 进 `surface`；LPV 手持光已调用；手部屏幕阴影与手电筒保留 | 已覆盖纯算式；手部屏幕阴影与手电筒标为 MC 专用，证据见第六节第 3 条 |
| Eclipse `indirect_lighting_effects.glsl` | 螺旋采样以外的屏幕追踪与双边升采样 | `ogxR2Sample`、`ogxCosineHemisphere`、`ogxConvertHandDepth3`、`ogxSpiralSample` 进 `math`；`rayTrace_GI`、`RT_alternate`、`ApplySSRT`、`BilateralUpscale_SSAO` 保留 | 已覆盖采样与深度换算；屏幕追踪与双边升采样标为 MC 专用，证据见第六节第 4 条 |
| Eclipse `nether_fog.glsl` | 羽流、雾霭、顶部烟三段步进留在宿主 | `ogxNetherVolumetricFog` 进 `fog_volume`，复用库里的 `ogxNetherFogCloudVolume`；`NetherVolumetricFog` 只算射线、雾色与选项 | 已覆盖 |
| Eclipse `oceans.glsl` | 与 iterationT 同一套波浪，涟漪与泡沫读宿主贴图 | 与 `PhysicsOceans` 共用 `ogxOceanPixel` 与辅助函数；`waves.glsl` 已调用 | 已覆盖 |
| Eclipse `ripples.glsl` | 参考里的程序化雨点涟漪没有对应实现 | `ogxRainRipples` 与专用哈希 `ogxRippleHash12` 进 `water`，九个格子的扩散、中心差分与归一化照原式 | 库内：光影侧仍用 iterationT 的三层动画贴图雨点 |
| Eclipse `Shadows.glsl` | `GriAndEminShadowFix`、`applyShadowBias` 没有对应实现 | 两条函数进 `shadow`，参数改为显式相机位置、水下标记、阴影法线与分辨率 | 库内：光影侧已有自己的阴影偏差路径 |
| Eclipse `volumetricClouds.glsl` | `curl2D` 依赖参考包自己的梯度噪声 | `ogxPerlinGradient2`、`ogxCurl2D` 进 `noise`；云形状、步进与光照继续映射到 `cloud_volume` 的 NUBIS 路径 | 已覆盖形状与步进；旋度函数库内 |
| Eclipse `voxel_write.glsl` | 写入侧依赖 `imageStore`、渲染阶段宏与实体编号 | `ogxVoxelWriteIndex`、`ogxVoxelWriteInBounds` 进 `voxel`；`imageStore` 与编号选择保留在 `rendering/lighting/lpv.glsl` | 已覆盖索引与边界；写入标为 MC 专用，证据见第六节第 5 条 |
| Eclipse `waterBump.glsl` | 焦散、水面高度与波法线读噪声图 | `ogxWaterBumpCaustics`、`ogxWaterBumpHeightmap`、`ogxWaterBumpNormal` 进 `water`，噪声图与纹素参数由调用方给 | 库内：光影侧仍用 iterationT 的水面波浪与焦散路径 |

## 四、iterationT 3.2.0

### 算法库（31 个文件）

| 参考效果 | 参考入口函数 | omni-gfx 对应 | 状态 |
| --- | --- | --- | --- |
| `BasicFounctions/Blocklight.glsl` | `BlockLighting`、`TextureLighting`、`TorchScreenSpaceShadow`、`HeldLighting`、`TorchSpecularHighlight`、`spotShape` | `surface`：`ogxBlockLight`、`ogxTextureEmissive`、`ogxSpotShape`、`ogxFlashlightAimDirection`、`ogxHandLight`；`shadow`：`ogxScreenSpaceShadow` | 已覆盖方块光、自发光、屏幕阴影与光斑；手持光与高光标为 MC 专用，见第六节第 1 条 |
| `BasicFounctions/NetherColor.glsl` | `NetherLighting`、`NetherFogColor` | `fog`：`ogxNetherBiomeLighting`、`ogxNetherBiomeFogColor` | 已覆盖，宿主已调用 |
| `BasicFounctions/PrecomputedAtmosphere.glsl` | `ClampRadius`、`DistanceToTopAtmosphereBoundary`、`RenderSunDisc`、`RenderMoonDisc`、`RenderMoonDiscReflection` | `atmosphere_model`：`ogxAtmo*` 共 37 个；`atmosphere`：日月圆盘与月盘反射 | 已覆盖 |
| `BasicFounctions/Sunlight_Shadow.glsl` | `VariablePenumbraShadow`、`ScreenSpaceShadow`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `shadow`：`ogxVariablePenumbraShadow`、`ogxScreenSpaceShadow`、`ogxSunScreenShadow`；`water`：`ogxWavesNormalFromTex`、`ogxWaterCaustics` | 已覆盖 |
| `BasicFounctions/TAA.glsl` | `SampleCurrColor`、`SamplePrevColor`、`RGB_To_YCoCg` 等 14 个 | `antialias`：`ogxTaaReproject` 与颜色空间、裁剪、历史采样函数 | 已覆盖，接入 `rendering/clarity/taa.glsl`；细分步骤函数暂无调用方 |
| `BasicFounctions/TAA_Nether.glsl` | `BicubicTextureVec4`、`SamplePreviousDepthBilinear`、`SamplePrevDepthMinMax3x3` 等 | `antialias`：`ogxBicubicTexture4`、`ogxTaaPrevDepthBilinear`、`ogxTaaPrevDepthMinmax`、`ogxTaaReproject` 的 `packedDepth` 分支 | 已覆盖，下界历史深度解包已进库并由宿主调用 |
| `BasicFounctions/TemporalNoise.glsl` | `BlueNoise`、`BlueNoiseTemproal`、`BayerTemproal` | `sampling`：`ogxBlueNoise`、`ogxBlueNoiseTemporal`、`ogxBayerTemporal` | 已覆盖 |
| `BasicFounctions/VanillaComposite.glsl` | `VanillaFog`、`SelectionBox` | 无 | MC 专用：原版雾曲线读宿主雾参数，选择框是调试叠加；留在 `rendering/fog/vanilla_fog.glsl` 与 `rendering/ground/selection.glsl` |
| `GbufferData.glsl` | `CurveBlockLightSky`、`CurveBlockLightTorch`、`MaterialFromTex`、`CalculateMasks`、`ApplyMaterial` | `surface`：`ogxCurveBlockLightSky`、`ogxCurveBlockLightTorch`、`ogxPbrMaterialFromTex`；`bind/gbuffer.glsl`：掩码与固定材质 | 已覆盖材质解码与曲线；掩码表标为 MC 专用，见第六节第 2 条 |
| `IndividualFounctions/AgX.glsl` | `AgX`、`ComputeCompressionMatrix`、`SlidePrimary` | `color`：`ogxAgx`、`ogxAgxContrast` | 已覆盖 |
| `IndividualFounctions/Bloom.glsl` | `BloomDownSample`、`AxialGaussianBlur`、`BicubicBlurTexture` | `post`：`ogxBloomDownsample`、`ogxAxialGaussianBlur`、`ogxBloomBicubic`、`ogxBloomChainCopy`；`math`：`ogxBicubicBlurTexture` | 已覆盖；五级泛光链的子图排布留在 `shaders/gfx/post.glsl` |
| `IndividualFounctions/CloudShadow.glsl` | `CloudShadowFromTex`、`GetSmoothCloudShadow` | `cloud`：`ogxCloudShadowCoord`、`ogxCloudShadowBicubic`、`ogxCloudShadowSample`、`ogxGlobalCloudShadow`、`ogxCloudShadowBlur` | 已覆盖 |
| `IndividualFounctions/DOF.glsl` | `CalculateCoCRadius`、`CoCSpread`、`DepthOfField`、`LinearDepth_From_ScreenDepth` | `post`：`ogxCocRadius`、`ogxDofLensFactor`、`ogxDofLinearDepth`、`ogxDofCocSpread`、`ogxDepthOfField` | 已覆盖 |
| `IndividualFounctions/EndSky.glsl` | `CalculateStars`、`PlanetEnd2`、`WarpSpace`、`Calculate3DNoise`、`CalculateCloudFBM` | `atmosphere`：星场与星盒；`planet`：`ogxPlanetEnd`；`fog`：`ogxEnd3dNoise`、`ogxCloudFbm`；`math`：`ogxWarpSpace` | 已覆盖 |
| `IndividualFounctions/FsrEASU.glsl` | `FsrEasuTap`、`FsrEasuSet`、`FsrEasu` | `upscale`：`ogxFsrEasuTap`、`ogxFsrEasuSet`、`ogxFsrEasu`、`ogxFsr1`、`ogxCas` | 已覆盖 |
| `IndividualFounctions/GlobalIllumination.glsl` | `RSM`、`CalculateCameraVelocity`、`GI_TemporalFilter`、`GI_SpatialFilter` | `gi`：`ogxGiRsm`、`ogxGiCameraVelocity`、`ogxGiTemporalFilter`、`ogxGiSpatialFilter` | 已覆盖 |
| `IndividualFounctions/GTAO.glsl` | `GroundTruthBasedAmbientOcclusion`、`GTAOMultiBounce` | `gi`：`ogxGroundTruthAo`、`ogxAoMultiBounce` | 已覆盖 |
| `IndividualFounctions/LensGlareFlare.glsl` | `GetDistOffset`、`flare`、`orb`、`ring` | `post`：`ogxGlareDistOffset`、`ogxGlareFlare`、`ogxGlareOrb`、`ogxGlareRing` | 已覆盖 |
| `IndividualFounctions/MotionBlur.glsl` | `CalculateCameraVelocity`、`MotionBlur`、`GetExposureTiles` | `post`：`ogxMotionBlur`、`ogxExposureTileAverage` | 已覆盖 |
| `IndividualFounctions/NUBIS.glsl` | `NubisCumulus`、`SampleDensity`、`CloudLighting`、`CloudShadowTex` | `cloud_volume`：`ogxCumulusCurve`、`ogxCumulusSetPos`、`ogxCumulusSampleDensity`、`ogxCumulusLightning`、`ogxCumulusLighting`、`ogxCumulusMarch`、`ogxCumulusShadowTex` | 已覆盖 |
| `IndividualFounctions/Parallax.glsl` | `BilinearHeightSample`、`HeightBasedNormal`、`ParallaxOcclusionMapping` | `parallax`：`ogxParallaxHeightBilinear`、`ogxParallaxHeightNormal`、`ogxParallaxHitNormal`、`ogxParallaxSmooth`、`ogxParallaxSharp` | 已覆盖 |
| `IndividualFounctions/PhysicsOceans.glsl` | `physics_waveHeight`、`physics_waveDirection`、`physics_waveNormal`、`physics_wavePixel` | `water`：`ogxOceanWaveSpace`、`ogxOceanWaveSum`、`ogxOceanWaveDirection`、`ogxOceanWaveHeight`、`ogxOceanWaveNormal`、`ogxOceanNormalWithRipple`、`ogxOceanFoam`、`ogxOceanPixel` | 已覆盖，宿主已调用 |
| `IndividualFounctions/PlanarClouds.glsl` | `GetPlanarCloudsDensity`、`GetPlanarCloudsLightingDensity`、`PlanarClouds` | `cloud`：`ogxPlanarDistortion`、`ogxPlanarDensity`、`ogxPlanarLightingDensity`、`ogxPlanarCloudLightingDepth` | 已覆盖 |
| `IndividualFounctions/PrintFloat.glsl` | `PrintFloat`、`SevenSegment`、`DecimalPoint`、`PrintUintBinary` | 无 | MC 专用（调试叠加）：`Final.glsl` 只有第 339 行一条 `#include`，整个参考包没有任何调用点；输入是屏幕像素坐标，输出是七段数码管读数，不参与画面链路 |
| `IndividualFounctions/Reflections/ReflectionFilter.glsl` | `AtrousWaveletFilter` | `reflection`：`ogxReflectionAtrousFilter` | 已覆盖 |
| `IndividualFounctions/Reflections/SSR.glsl` | `ScreenSpaceTracer`、`ProjectSky`、`sampleGGXVNDF`、`CalculateSpecularReflections` | `reflection`：`ogxScreenSpaceTrace`、`ogxReflectionSkyFacing`、`ogxSampleGgxVndf`、`ogxSpecularReflectionMix` | 已覆盖 |
| `IndividualFounctions/Ripple.glsl` | `GetRainAnimationTex`、`GetRainNormal`、`GetModulatedRainSpecular` | `water`：`ogxRainAnimationNormal`、`ogxRainSpecular`、`ogxPuddleCoverage`、`ogxPuddleRoughness`；`rendering/water/rain.glsl` 保留三层贴图调度 | 已覆盖核心算式；三层 `gaux` 动画贴图的帧调度属于宿主接线 |
| `IndividualFounctions/UnderwaterVolumetricFog.glsl` | `UnderwaterVolumetricFog`、`GetWavesNormalFromTex`、`CalculateWaterCaustics` | `fog_volume`：`ogxUnderwaterFog`、`ogxUnderwaterCaustics`；`water`：`ogxWavesNormalFromTex` | 已覆盖 |
| `IndividualFounctions/VolumetricFog.glsl` | `VolumetricFog`、`FogDensity`、`FogPhase`、`PowderEffect`、`simpleScattering` | `fog`：`ogxFogDensityHeight`、`ogxFogDensityNoise`、`ogxFogMarch`、`ogxLegacyPowder`、`ogxLegacyFogPhase`、`ogxMultiScatteringPhases`；`fog_volume`：`ogxVolumetricFog`；`atmosphere_model`：`ogxAtmoSimpleScattering` | 已覆盖 |
| `IndividualFounctions/WaterWaves.glsl` | `GetWaves`、`GetWavesNormal`、`GetWaterParallaxCoord` | `water`：`ogxTextureSmooth`、`ogxAlmostIdentity`、`ogxWaves`、`ogxWavesNormal`、`ogxWaterParallax` | 已覆盖 |
| `Utilities.glsl` | `LinearToCurve`、`CurveToLinear`、`DoNightEye`、`facos`、`atan2`、`remapSaturate`、`remap`、`minVec3`、`maxVec3` | `math`：对应 `ogx*` 函数 | 已覆盖 |

### 宿主文件（6 个）

| 参考文件 | 装的是什么 | 状态 |
| --- | --- | --- |
| `Settings.glsl` | 选项宏与常量 | MC 专用：对应本项目 `shaders/effects/` 的选项与 `options.py` 生成的菜单 |
| `UniformDeclare.glsl` | 加载器输入声明 | MC 专用：对应 `shaders/bind/` |
| `Uniform/GbufferTransforms.glsl` | 屏幕与视空间互换、深度换算 | MC 专用：矩阵约定来自加载器；纯换算部分见 `math`、`post`、`shadow` |
| `Uniform/ShadowTransforms.glsl` | 阴影投影与扭曲 | 已覆盖：扭曲与投影进 `shadow`（`ogxShadowScreenPosDistorted`、`ogxDistortShadowPos`）；矩阵本身由宿主给 |
| `Uniform/ShadowTransformsEnd.glsl` | 末地阴影投影 | 同上，末地只是换了一组矩阵 |
| `Uniform/ShadowModelViewEnd.glsl` | 末地阴影视图矩阵 | MC 专用 |

### 程序入口（37 个）

`Lib/Programs/` 的 `CompositeVS`、`Final`、`PostVS` 与 34 个 gbuffers 阶段是壳子：声明附件、选宏、调用上面的库。它们的对应物是本项目的 `shaders/rendering/` 与 `world0/`、`world-1/`、`world1/` 入口，绘制顺序与阶段职责写在 `docs/rendering.md`，这里不重复登记。

## 五、Eclipse

Eclipse 的 `shaders/lib/` 共 45 个文件，程序文件 594 个只作阶段壳子，口径同上。

| 参考效果 | 参考入口函数 | omni-gfx 对应 | 状态 |
| --- | --- | --- | --- |
| `aurora.glsl` | `aurora`、`triNoise2d` | `atmosphere`：`ogxAurora` | 已覆盖 |
| `bayer_matrix.glsl` | `bayerDither` | `math`：`ogxBayer2`、`ogxBayer4`、`ogxBayer8`、`ogxBayer64` | 已覆盖 |
| `blocks.glsl` | 方块编号与属性表 | 无 | MC 专用：编号表由资源包与 `block.properties` 决定 |
| `bokeh.glsl` | `rotate` 与光圈形状 | `post`：`ogxBokehAperture`；散焦核在 `ogxDepthOfField` | 已覆盖：多边形光圈的形状与旋转进库；采样点偏移表是数据，光影侧用圆形核 |
| `climate_settings.glsl` | `YearCycleColor`、`BiomeFogDensity`、`BiomeVLFogColors`、`FogDensities` | `fog`：`ogxBiomeFogColor`、`ogxBiomeFogDensity`；`weather`：`ogxYearCycleColor`、`ogxFogDensities` | 已覆盖群系雾并由宿主调用；四季与时段函数库内，宿主沿用本项目自己的季节与时段选项 |
| `color_dither.glsl` | `fp10Dither`、`fp16Dither`、`int8Dither`、`int10Dither`、`int16Dither` | `noise`：白噪声与三角噪声；`post`：`ogxDitherFloat`、`ogxDitherFixed` | 已覆盖：五条入口按浮点尾数与定点位数合并成两个核心函数 |
| `color_transforms.glsl` | 七条色调映射入口 | `color`：`ogxTonemapHejl`、`ogxTonemapHable`、`ogxTonemapReinhard`、`ogxTonemapAcesFilm`、`ogxTonemapLottes`、`ogxTonemapUchimura`、`ogxLinearToSrgb` | 已覆盖；界面仍只提供 ACES、AgX 与无压缩三档 |
| `diffuse_lighting.glsl` | `doBlockLightLighting`、`doIndirectLighting`、`GetHandLight`、`SSRT_Handlight_Shadows`、`calculateFlashlight` | `surface`：`ogxBlockLightCurveEclipse`、`ogxDoIndirectLighting`、`ogxHandLight` | 已覆盖曲线、间接光与手持光；手部屏幕阴影与手电光标为 MC 专用，见第六节第 3 条 |
| `DistantHorizons_projections.glsl` | `toScreenSpace_DH`、`toClipSpace3_DH` | 无 | MC 专用：远景模组的投影约定，只在加载器提供远景深度时才有意义 |
| `end_fog.glsl` | `fogShape`、`SwirlAroundOrigin`、`VolumeBounds`、`densityAtPosFog` | `fog`：`ogxEndVortex*` 与 `ogxEndFogDensity` | 已覆盖 |
| `entities.glsl` | 实体材质表 | `surface`：材质法线与自发光换算 | MC 专用：实体编号与材质位由 `entity.properties` 决定 |
| `gameplay_effects.glsl` | `applyGameplayEffects` | `math`：`ogxDoNightEye` | MC 专用：药水与受伤状态由游戏给，光影只做画面换算 |
| `hsv.glsl` | `RgbToHsv`、`HsvToRgb` | `math`：`ogxRgbToHsv`；`color`：`ogxHsvToRgb` | 已覆盖 |
| `indirect_lighting_effects.glsl` | `rayTrace_GI`、`BilateralUpscale_SSAO`、`SpiralSample`、`R2_samples`、`cosineHemisphereSample`、`convertHandDepth_3` | `math`：`ogxSpiralSample`、`ogxR2Sample`、`ogxCosineHemisphere`、`ogxConvertHandDepth3` | 已覆盖采样与深度换算；屏幕追踪与双边升采样标为 MC 专用，见第六节第 4 条 |
| `items.glsl` | 物品编号表 | 无 | MC 专用：编号来自 `item.properties` |
| `lightning_stuff.glsl` | `Iris_Lightningflash`、`Iris_Lightningflash_VLcloud`、`Iris_Lightningflash_VLfog` | `fog_volume`：`ogxFogLightning`；`cloud_volume`：`ogxCumulusLightning` | 已覆盖 |
| `lpv_blocks.glsl` | LPV 方块表 | 无 | MC 专用：与 `block.properties` 的编号一一对应 |
| `lpv_buffer.glsl` | LPV 缓冲布局 | 无 | MC 专用：SSBO 布局由加载器与 `rendering/lpv.glsl` 共同约定 |
| `lpv_common.glsl` | `GetLpvPosition` | `lpv`：`ogxLpvPosition`、`ogxLpvUvw` | 已覆盖：坐标映射进库，宿主只把相机小数部分与半边长度传进来 |
| `lpv_render.glsl` | `SampleLpvLinear`、`GetLpvBlockLight`、`GetLpvSkyLight`、`lpvCurve` | `lpv`：`ogxLpvDecodeSample`、`ogxLpvBlockLight`、`ogxLpvSkyLight`、`ogxLpvCurve`、`ogxLpvEncode`、`ogxLpvDecode`、`ogxLpvRangeFalloff`、`ogxLpvApply` | 已覆盖：解码、编码、光强曲线与合成全部进库 |
| `nether_fog.glsl` | `GetVolumetricFog`、`cloudVol`、`densityAtPosFog` | `fog`：`ogxNetherFogDensityAt`、`ogxNetherFogCloudVolume`；`fog_volume`：`ogxNetherVolumetricFog` | 已覆盖，宿主已调用三段步进 |
| `oceans.glsl` | `physics_waveHeight`、`physics_waveNormal`、`physics_wavePixel` | `water`：`ogxOceanWaveSpace`、`ogxOceanWaveSum`、`ogxOceanWaveHeight`、`ogxOceanNormalWithRipple`、`ogxOceanFoam`、`ogxOceanPixel` | 已覆盖，与 iterationT 海洋共用同一套库函数 |
| `overworld_fog.glsl` | `GetVolumetricFog`、`phaseRayleigh`、`densityAtPosFog` | `fog_volume`：`ogxVolumetricFog`、`ogxFogDensity`、`ogxFogLightMarch`、`ogxFogCloudBicubic` | 已覆盖 |
| `PhotonGTAO.glsl` | GTAO 采样与降噪 | `gi`：`ogxGroundTruthAo`、`ogxAoMultiBounce` | 已覆盖 |
| `projections.glsl` | `toClipSpace3`、`toScreenSpace`、`toWorldSpace`、`toShadowSpace` | `math`：`ogxMatrixMul`、`ogxMatrixMulPoint` 等 | MC 专用：矩阵来自加载器；纯乘法已进库但仅库内使用 |
| `res_params.glsl` | 分辨率参数 | 无 | MC 专用：屏幕尺寸由加载器给 |
| `ripples.glsl` | `ripples`、`hash12`、`hash22` | `water`：`ogxRainRipples`、`ogxRippleHash12`；`noise`：`ogxHash22` | 库内：程序化雨点涟漪已进库，光影侧仍用 iterationT 的三层动画贴图 |
| `ROBOBO_sky.glsl` | `calculateAtmosphere`、`sky_transmittance`、`sky_opticalDepth` | `atmosphere`：`ogxAtmosphereSky`、`ogxAtmosphereOpticalDepth`、`ogxAtmosphereTransmittance` | 库内：解析版在库里，光影侧走同一套公式的查表版 `atmosphere_model` |
| `scene_controller.glsl` | `applySceneControllerParameters` | 无 | MC 专用：按维度、天气与群系切场景参数 |
| `settings.glsl` | 选项宏 | 无 | MC 专用：对应 `shaders/effects/` 与 `options.py` 生成的菜单 |
| `Shadow_Params.glsl` | `BiasShadowProjection`、`calcDistort` | `shadow`：`ogxShadowScreenPos`、`ogxShadowScreenPosDistorted`、`ogxDistortShadowPos` | 已覆盖 |
| `Shadows.glsl` | `GriAndEminShadowFix`、`applyShadowBias` | `shadow`：`ogxGriAndEminShadowFix`、`ogxApplyShadowBias` | 库内：两条修补已进库，光影侧已有自己的阴影偏差路径 |
| `sky_gradient.glsl` | `drawSun`、`drawMoon`、`drawRealMoon`、`sphereMap` | `atmosphere`：日月圆盘与天空投影 | 已覆盖 |
| `specular.glsl` | `SampleVNDFGGX`、`CoordBase`、`frisvad`、`linZ` | `reflection`：`ogxSampleGgxVndf`、`ogxReflectionLinearDepth`、`ogxReflectionScreenDepth`、`ogxReflectionDhToScreenDepth`；`math`：`ogxTangentBasis` | 已覆盖 |
| `SSBOs.glsl` | SSBO 声明 | 无 | MC 专用：加载器扩展与缓冲布局 |
| `stars.glsl` | `NoisyStarField`、`StableStarField`、`starTemp`、`starplane`、`starbox` | `atmosphere`：星场、星温、星面与星盒 | 已覆盖 |
| `TAA_jitter.glsl` | 抖动序列 | `sampling`：`ogxTaaJitter`、`ogxBlueNoise`、`ogxBayerTemporal` | 已覆盖：四帧与八帧两套序列进库，光影侧仍在顶点阶段自算抖动 |
| `texFiltering.glsl` | `smoothfilter`、`shadowsmoothfilter` | `sampling`：`ogxSmoothFilter`、`ogxShadowSmoothFilter` | 库内：参考文件本身没有 `#include`，光影侧没有对应选项 |
| `text_rendering.glsl` | `beginText`、`printFloat` 等 | 无 | MC 专用（调试叠加）：唯一使用位置是 `dimensions/final.fsh` 第 255 到 292 行，整段在 `#if DEBUG_VIEW` 内 |
| `texture_filtering.glsl` | `sampleNearest`、`sampleRGSS` | `sampling`：`ogxSampleNearest`、`ogxRgssSample`、`ogxTexelFetch` | 已覆盖：最近点取样与旋转网格超采样进库；光影侧没有贴图过滤模式选项 |
| `util.glsl` | `facos`、`circlemap`、`calculateRoughSpecular`、`srgbToLinear`、`linearToSRGB` | `math`：`ogxFastAcos`、`ogxCircleMap`、`ogxRoughSpecularDirection`、`ogxSrgbToLinear`、`ogxLinearToSrgb`、`ogxTangentBasis` | 已覆盖 |
| `volumetricClouds.glsl` | `getCloudShape`、`densityAtPos`、`curl2D`、`getRainDensity` | `cloud_volume`：云形状、步进、光照与雨密度；`noise`：`ogxPerlinGradient2`、`ogxCurl2D`、`ogxWarp3`、`ogxFbm3` | 已覆盖形状与步进；旋度函数库内 |
| `voxel_common.glsl` | 体素索引与读取 | `voxel`：`ogxVoxelInside`、`ogxVoxelReflection` 等 | 已覆盖 |
| `voxel_write.glsl` | `GetVoxelIndex`、`SetVoxelBlock`、`PopulateShadowVoxel` | `voxel`：`ogxVoxelWriteIndex`、`ogxVoxelWriteInBounds`；`lpv`：`ogxLpvPosition` | 已覆盖索引与边界；`imageStore` 与实体编号保留在宿主，见第六节第 5 条 |
| `waterBump.glsl` | `waterCaustics`、`getWaterHeightmap`、`getWaveNormal` | `water`：`ogxWaterBumpCaustics`、`ogxWaterBumpHeightmap`、`ogxWaterBumpNormal` | 库内：三条水面函数已进库，光影侧仍用 iterationT 的水面路径 |

### 有意偏离

这一小节只列与参考实现不同、但必须记住的地方；其余函数按原式搬运。

1. `ogxTonemapUchimura` 修正了参考实现的参数顺序。参考写 `smoothstep(x, 0.0, m)`，把输入值当成下边界，按 GLSL 规则会得到恒为零的权重，三段拼接里出现负权重；迁入时改成 `smoothstep(0.0, m, x)`。没有调用方，因此不影响现有画面。
2. `ogxTriangleNoise` 在中心正好为零时补了一个极小分母，避免参考实现里的 `inversesqrt(0)` 产生无定义值。
3. `ogxOceanFoam` 的输入改成“已经乘过法线竖直分量的波峰振幅”，避免库内再乘一次；调用方 `ogxOceanPixel` 与参考实现的乘法顺序保持一致。
4. `ogxWaterBumpCaustics` 与 `ogxWaterBumpHeightmap` 的三次旋转改成与 GLSL 矩阵乘法同序的显式公式，不再依赖 `mat2` 的行列解释；数值与参考实现逐项相同。
5. `ogxNetherVolumetricFog` 把“步进距离上限”和“羽流随距离淡出用的远裁剪面”拆成两个参数。参考实现里这两个值分别取 `min(far, 192)` 与 `far`，合并会改变远裁剪面小于一百九十二米时的羽流。

## 六、只服务 Minecraft 的部分与证据

这一节只列“确实没有搬进通用库”的部分。每条都给出参考包或本项目的实际位置，不写“以后再说”。

1. **手持光源与手持高光（iterationT `Blocklight.glsl`）。** 参考 `HeldLighting` 在 `Blocklight.glsl:162-280`，`TorchSpecularHighlight` 在 `:283-352`；它们读取 `heldBlockLightValue`、`heldBlockLightValue2`（`shaders/common/uniforms.glsl:21,23`）、`eyeRxSmooth`、`eyeRySmooth`（`:66`），并按一只手、两只手、手电筒模式与普通火把模式分支。通用库没有“手”“手持物品”“手电筒模式”这些概念；把整段搬进去只能得到一组只为 Minecraft 设计的参数。纯算式（光斑形状、光束指向、三次方衰减、GGX 高光）已经进库，宿主只保留数据读取与分支。
2. **材质编号掩码表（iterationT `GbufferData.glsl`）。** 参考 `CalculateMasks` 在 `GbufferData.glsl:208-248`，主机版本在 `shaders/bind/gbuffer.glsl:22-49`（`MATID_*` 常量）与 `:152-183`（逐项比较）。这些编号由几何阶段写入，例如 `shaders/rendering/entities.glsl:239-260` 与 `shaders/rendering/distant.glsl:104-124`；编号值对应 Minecraft 的方块与实体类别，属于游戏数据。纯解码部分 `ogxPbrMaterialFromTex` 已经进库。
3. **手部屏幕阴影与手电筒（Eclipse `diffuse_lighting.glsl`）。** `SSRT_Handlight_Shadows` 在 `diffuse_lighting.glsl:6-70`，依赖 `depthtex2`、`RENDER_SCALE`、`gbufferModelViewInverse` 与 `toClipSpace3_DH`；`calculateFlashlight` 在 `:304-368`，依赖 `gbufferPreviousModelView`、`centerDepthSmooth`、`noisetex` 与 Eclipse 的 `IEXT_*` 输入。它们只在 Eclipse 的延迟与阴影阶段组合里成立；本项目已有自己的手持光路径（`shaders/rendering/lighting/held_light.glsl`）。
4. **屏幕空间全局光与双边升采样（Eclipse `indirect_lighting_effects.glsl`）。** `BilateralUpscale_SSAO` 在 `:43-93`，按缩放因子读四张深度并依赖 `ld()` 与远景深度打包；`rayTrace_GI` 在 `:99-143`、`RT_alternate` 在 `:153-217`、`ApplySSRT` 在 `:219-304`，依赖 `toClipSpace3`、`depthtex1`、`colortex4/5`、`RENDER_SCALE` 与 `TAA_Offset`。这些是 Eclipse 延迟缓冲布局的一部分，不是独立算法；本项目用自己的 `gi` 模块与延迟阶段。纯采样函数 `ogxR2Sample`、`ogxCosineHemisphere`、`ogxConvertHandDepth3` 已进库。
5. **体素写入（Eclipse `voxel_write.glsl`）。** `SetVoxelBlock` 在 `:19-25` 用 `imageStore` 写 `imgVoxelMask`；`PopulateShadowVoxel` 在 `:89-188` 读 `renderStage`、`mc_Entity`、`entityId`、`blockEntityId` 与多个实体编号宏。写入目标与阶段宏由加载器与方块表决定。索引与边界判断已经进库（`ogxVoxelWriteIndex`、`ogxVoxelWriteInBounds`）。
6. **调试读数与调试文字。** iterationT `PrintFloat.glsl` 只在 `Final.glsl:339` 被 `#include`，包内没有调用点；Eclipse `text_rendering.glsl` 只在 `dimensions/final.fsh:255-292` 的 `DEBUG_VIEW` 分支使用。两者都是立即模式调试界面，不参与画面链路。
7. **方块、实体、物品与 LPV 编号表。** Eclipse `blocks.glsl`、`entities.glsl`、`items.glsl`、`lpv_blocks.glsl` 与 `SSBOs.glsl` 装的是加载器与资源包约定的编号和缓冲布局；`scene_controller.glsl`、`settings.glsl`、`res_params.glsl`、`projections.glsl`、`DistantHorizons_projections.glsl` 装的是维度、选项、屏幕尺寸与投影约定。这些是宿主边界，不是可移植算法。
8. **原版雾与选择框（iterationT `VanillaComposite.glsl`）。** 原版雾读宿主雾参数，选择框是调试叠加；留在 `rendering/fog/vanilla_fog.glsl` 与 `rendering/ground/selection.glsl`。

## 七、汇总

按上表 76 行逐项统计（iterationT 的 31 个算法文件、Eclipse 的 45 个文件）：

| 状态 | iterationT | Eclipse | 合计 |
| --- | --- | --- | --- |
| 已覆盖 | 29 | 27 | 56 |
| 库内 | 0 | 5 | 5 |
| MC 专用 | 2 | 13 | 15 |
| 部分 | 0 | 0 | 0 |
| 未覆盖 | 0 | 0 | 0 |

说明：

- iterationT 的 29 条已覆盖里有 2 条同时含 MC 专用剩余（Blocklight 的手持光、GbufferData 的掩码表）；Eclipse 的 27 条里有 5 条同时含库内或 MC 专用子项（climate、diffuse、indirect、volumetricClouds、voxel_write 中的若干子函数）。主状态按光影实际使用的那部分计，子项在表格与第六节逐条标明。
- iterationT 另有 6 个宿主文件，全部只服务 MC，已在上文单列，不计入这 31 行。
- Eclipse 的 5 条库内是：`ripples`、`ROBOBO_sky`、`Shadows`、`texFiltering`、`waterBump`。它们的算式已在库里，光影侧没有对应调用点；这不是缺口，是两套参考的路径选择不同。
- 原先的 15 条部分覆盖已全部处理：12 条变成已覆盖，3 条变成库内（`ripples`、`Shadows`、`waterBump`）。这 12 条里有 5 条保留 MC 专用子项（Blocklight 的手持光、GbufferData 的掩码、diffuse 的手部阴影与手电筒、indirect 的屏幕追踪、voxel_write 的写入），2 条保留库内子项（climate 的四季与时段雾、volumetricClouds 的旋度）。没有新增未覆盖项。

## 八、未验证

- 库内与 MC 专用两类没有画面链路，只有 SPIR-V 探针与 GLSL 编译作证据。
- 已覆盖项只验证了调用链与编译，没有在游戏内做逐像素对比；默认画面不变的理由是“新函数没有调用方、被改写的调用点逐项保持原算式”，而不是截图比对。
- 下界体积雾、海洋像素、材质解码与群系雾的改写保持原算式与参数顺序，但仍需在游戏内用同一场景对比；本轮按用户要求没有启动 Minecraft。
