# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`，字段名固定为 ASCII。

## 结论

- 参考函数共 505 个；算法函数 436 个。
- exact：378 个；approximate：32 个；mc_glue：69 个；missing：26 个。
- exact 覆盖率（按算法函数）：86.7%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 213 | 5 | 22 | 0 |
| Eclipse | 165 | 27 | 47 | 26 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 当前承接 | 差异 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `main` | iterationT | mc_glue | — | 就绪：程序入口，只负责阶段组合 | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:331` |
| `CalculateStars` | iterationT | approximate | `atmosphere.ogxStarsStable` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:12 -> omni-gfx/src/atmosphere.slang:444` |
| `ppss` | iterationT | approximate | `atmosphere.ogxPlanetBrdf` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:57 -> omni-gfx/src/atmosphere.slang:614` |
| `BlackHole_AccretionDisc_Stars` | iterationT | approximate | `accretion.ogxAccretionDisc` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:320 -> omni-gfx/src/accretion.slang:23` |
| `BlackHole_AccretionDisc_Reflection` | iterationT | approximate | `accretion.ogxAccretionDisc` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/EndSky.glsl:429 -> omni-gfx/src/accretion.slang:23` |
| `title` | iterationT | mc_glue | — | 就绪：标题计数与屏幕文字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl:100` |
| `CloudShadowTex` | iterationT | approximate | `cloud.ogxCloudShadowSample` | not reviewed line by line; old map only records the receiving function | `references/iterationT/shaders/Lib/IndividualFounctions/NUBIS.glsl:212 -> omni-gfx/src/cloud.slang:370` |
| `SevenSegment` | iterationT | mc_glue | — | 就绪：调试叠加字形表，只服务屏幕数字 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:48` |
| `DecimalPoint` | iterationT | mc_glue | — | 就绪：调试叠加小数点定位 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:93` |
| `PrintFloat` | iterationT | mc_glue | — | 就绪：屏幕调试数字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:99` |
| `PrintUintBinary` | iterationT | mc_glue | — | 就绪：屏幕调试二进制，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:218` |
| `ViewPos_From_ScreenPos` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:1` |
| `ViewPos_From_ScreenPos_Raw` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:10` |
| `ScreenPos_From_ViewPos` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:16` |
| `ScreenPos_From_ViewPos_Raw` | iterationT | mc_glue | — | 就绪：屏幕坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:25` |
| `ScreenDepth_From_LinearDepth` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:35` |
| `ViewPos_From_ScreenPos_DH` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:42` |
| `ViewPos_From_ScreenPos_Raw_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:51` |
| `ScreenPos_From_ViewPos_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:57` |
| `ScreenPos_From_ViewPos_Raw_DH` | iterationT | mc_glue | — | 就绪：远景坐标约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:66` |
| `LinearDepth_From_ScreenDepth_DH` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:71` |
| `ScreenDepth_From_LinearDepth_DH` | iterationT | mc_glue | — | 就绪：远景深度约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:76` |
| `ScreenDepth_From_DHScreenDepth` | iterationT | mc_glue | — | 就绪：远景深度约定 | `references/iterationT/shaders/Lib/Uniform/GbufferTransforms.glsl:81` |
| `ShadowScreenPos_From_WorldPos_Distorted` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:3` |
| `ShadowScreenPos_From_WorldPos` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:14` |
| `ShadowScreenPos_From_WorldPos_WithoutZScaling` | iterationT | mc_glue | — | 就绪：阴影坐标约定 | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:21` |
| `DistortShadowScreenPos` | iterationT | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/iterationT/shaders/Lib/Uniform/ShadowTransforms.glsl:28` |
| `aurora` | Eclipse | approximate | `atmosphere.ogxAurora` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/aurora.glsl:77 -> omni-gfx/src/atmosphere.slang:584` |
| `YearCycleColor` | Eclipse | approximate | `weather.ogxYearCycleColor` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/climate_settings.glsl:19 -> omni-gfx/src/weather.slang:100` |
| `BiomeVLFogColors` | Eclipse | mc_glue | — | 就绪：原版群系枚举到颜色表，非算法 | `references/Eclipse/shaders/lib/climate_settings.glsl:151` |
| `swapperlinZ2` | Eclipse | mc_glue | — | 就绪：只交换深度约定 | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:2` |
| `SSRT_Handlight_Shadows` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:6` |
| `doBlockLightLighting` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:104` |
| `calculateFlashlight` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/diffuse_lighting.glsl:304` |
| `toScreenSpace_DH` | Eclipse | mc_glue | — | 就绪：远景模组投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:21` |
| `toClipSpace3_DH` | Eclipse | mc_glue | — | 就绪：远景模组投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:48` |
| `DH_shadowProjectionTweak` | Eclipse | mc_glue | — | 就绪：远景阴影投影约定 | `references/Eclipse/shaders/lib/DistantHorizons_projections.glsl:59` |
| `GetEndFogShadow` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/end_fog.glsl:321` |
| `applyGameplayEffects` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/gameplay_effects.glsl:37` |
| `cosineHemisphereSample` | Eclipse | approximate | `math.ogxCosineHemisphere` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:6 -> omni-gfx/src/math.slang:662` |
| `TangentToWorld` | Eclipse | approximate | `math.ogxTangentBasis` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:16 -> omni-gfx/src/math.slang:471` |
| `BilateralUpscale_SSAO` | Eclipse | approximate | `gi.ogxBilateralUpscale` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:43 -> omni-gfx/src/gi.slang:56` |
| `rayTrace_GI` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:99` |
| `RT_alternate` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:153` |
| `ApplySSRT` | Eclipse | approximate | `reflection.ogxReflectionSceneColor` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/indirect_lighting_effects.glsl:219 -> omni-gfx/src/reflection.slang:171` |
| `GetLpvPosition` | Eclipse | mc_glue | — | 就绪：世界坐标到光传播体积坐标约定 | `references/Eclipse/shaders/lib/lpv_common.glsl:12` |
| `project` | Eclipse | mc_glue | — | 就绪：矩阵投影约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:73` |
| `project_and_divide` | Eclipse | mc_glue | — | 就绪：矩阵投影约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:76` |
| `screen_to_view_space` | Eclipse | mc_glue | — | 就绪：屏幕到视空间约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:81` |
| `view_to_screen_space` | Eclipse | mc_glue | — | 就绪：视空间到屏幕约定 | `references/Eclipse/shaders/lib/PhotonGTAO.glsl:87` |
| `toClipSpace3` | Eclipse | mc_glue | — | 就绪：裁剪空间约定 | `references/Eclipse/shaders/lib/projections.glsl:14` |
| `toScreenSpace` | Eclipse | mc_glue | — | 就绪：屏幕空间约定 | `references/Eclipse/shaders/lib/projections.glsl:18` |
| `toScreenSpaceVector` | Eclipse | mc_glue | — | 就绪：屏幕空间方向约定 | `references/Eclipse/shaders/lib/projections.glsl:25` |
| `toWorldSpace` | Eclipse | mc_glue | — | 就绪：世界空间约定 | `references/Eclipse/shaders/lib/projections.glsl:32` |
| `toWorldSpaceCamera` | Eclipse | mc_glue | — | 就绪：相机空间约定 | `references/Eclipse/shaders/lib/projections.glsl:37` |
| `toShadowSpace` | Eclipse | mc_glue | — | 就绪：阴影空间约定 | `references/Eclipse/shaders/lib/projections.glsl:42` |
| `toShadowSpaceProjected` | Eclipse | mc_glue | — | 就绪：阴影空间约定 | `references/Eclipse/shaders/lib/projections.glsl:52` |
| `calculateAtmosphere` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/ROBOBO_sky.glsl:95` |
| `applySceneControllerParameters` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/scene_controller.glsl:147` |
| `drawSun` | Eclipse | approximate | `atmosphere.ogxSunDisc` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:3 -> omni-gfx/src/atmosphere.slang:258` |
| `sphereMap` | Eclipse | approximate | `atmosphere.ogxSkyProject` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:10 -> omni-gfx/src/atmosphere.slang:515` |
| `drawMoon` | Eclipse | approximate | `atmosphere.ogxMoonDiscDefault` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:27 -> omni-gfx/src/atmosphere.slang:476` |
| `drawRealMoon` | Eclipse | approximate | `atmosphere.ogxMoonDiscReal` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:58 -> omni-gfx/src/atmosphere.slang:469` |
| `texture_bicubic` | Eclipse | approximate | `math.ogxBicubicTexture` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:109 -> omni-gfx/src/math.slang:605` |
| `texture_bicubic_offset` | Eclipse | approximate | `math.ogxBicubicTexture` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:133 -> omni-gfx/src/math.slang:605` |
| `sphereToCarte` | Eclipse | approximate | `atmosphere.ogxSkyEquirect` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:166 -> omni-gfx/src/atmosphere.slang:544` |
| `skyFromTex` | Eclipse | approximate | `atmosphere_model.ogxAtmoSkyRadiance` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:171 -> omni-gfx/src/atmosphere_model.slang:235` |
| `skyCloudsFromTex` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:186 -> omni-gfx/src/atmosphere.slang:563` |
| `skyCloudsFromTexBLUR` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:195 -> omni-gfx/src/atmosphere.slang:563` |
| `skyCloudsFromTexLOD` | Eclipse | approximate | `atmosphere.ogxSkyCloudsFromTexLod` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:210 -> omni-gfx/src/atmosphere.slang:572` |
| `volumetricsFromTex` | Eclipse | approximate | `fog_volume.ogxFogCloudBicubic` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/sky_gradient.glsl:229 -> omni-gfx/src/fog_volume.slang:79` |
| `CoordBase` | Eclipse | mc_glue | — | 就绪：坐标/投影约定，不是效果算法 | `references/Eclipse/shaders/lib/specular.glsl:29` |
| `invertLinearizeDepthFast` | Eclipse | mc_glue | — | 就绪：深度约定 | `references/Eclipse/shaders/lib/specular.glsl:108` |
| `rayTraceSpeculars` | Eclipse | missing | — | no receiving function and no glue justification | `references/Eclipse/shaders/lib/specular.glsl:113` |
| `toScreenSpace2` | Eclipse | mc_glue | — | 就绪：屏幕空间约定 | `references/Eclipse/shaders/lib/specular.glsl:248` |
| `GetVoxelBlock` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:262` |
| `voxelNormalIndex` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:270` |
| `GetVoxelData` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/specular.glsl:280` |
| `GetTexCoord` | Eclipse | mc_glue | — | 就绪：纹理坐标约定 | `references/Eclipse/shaders/lib/specular.glsl:290` |
| `getVoxelEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:294` |
| `voxelEmission` | Eclipse | mc_glue | — | 就绪：方块编号到自发光 | `references/Eclipse/shaders/lib/specular.glsl:300` |
| `ComputeVoxelShadowMap` | Eclipse | approximate | `voxel.ogxVoxelWriteIndex` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/specular.glsl:331 -> omni-gfx/src/voxel.slang:136` |
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
| `starplane` | Eclipse | approximate | `atmosphere.ogxStarPlane` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:52 -> omni-gfx/src/atmosphere.slang:411` |
| `starbox` | Eclipse | approximate | `atmosphere.ogxStarBox` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:82 -> omni-gfx/src/atmosphere.slang:433` |
| `stars` | Eclipse | approximate | `atmosphere.ogxStarsStable` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/stars.glsl:93 -> omni-gfx/src/atmosphere.slang:444` |
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
| `GetVoxelIndex` | Eclipse | mc_glue | — | 就绪：Minecraft 体素编号约定 | `references/Eclipse/shaders/lib/voxel_write.glsl:1` |
| `SetVoxelBlock` | Eclipse | mc_glue | — | 就绪：Minecraft 体素写入约定 | `references/Eclipse/shaders/lib/voxel_write.glsl:19` |
| `waterCaustics` | Eclipse | approximate | `water.ogxWaterCaustics` | not reviewed line by line; old map only records the receiving function | `references/Eclipse/shaders/lib/waterBump.glsl:9 -> omni-gfx/src/water.slang:349` |

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
