# iterationT 一比一移植合同

本文件是把 iterationT 3.2.0 的全部算法与渲染流程移植进 Omni 的唯一合同。
所有参与移植的会话和子任务先读本文件，再读 `AGENTS.md` 与 HOP 技能。

## 一、用户决定（2026-10-16）

- 目标：完整复刻 iterationT 3.2.0 的全部算法和渲染流程，默认设置下画面与 iterationT 一致。
- 许可先不考虑，第一目标是做出来；仓库保持私有。公开发布前必须重新评估许可。
- 允许直接移植 iterationT 的代码、常数、贴图和数据文件，不再按论文“独立重写”。
- 项目结构保持 Omni 自己的 HOP 结构：`effects/` 按效果分文件，`rendering/` 安排绘制顺序，入口由 `programs.json` 生成，选项用 `@option` 定义一次。
- 选项只增不减：iterationT 的选项全部移植；Omni 已有选项要么并入对应的 iterationT 选项，要么作为额外功能保留并接到真实计算。

## 二、为什么之前对不上

旧 Omni 管线只有 `deferred`、`composite`、`composite1`、`final` 四个全屏阶段，缓冲协议、亮度单位和曝光链路都与 iterationT 不同。
iterationT 的天空不是实时积分，而是读取预计算大气数据 `texture/AtmoData_620_540_440_n4.bin`（`RGBA32F` 三维贴图 512×128×33）。
所有中间颜色按 `LinearToCurve(x / MAIN_OUTPUT_FACTOR)` 存进 `RGBA16`，`MAIN_OUTPUT_FACTOR = 2048`，曲线是四次方根。
曝光在最终阶段乘回：自动曝光为 `8.5 × MAIN_OUTPUT_FACTOR × 平均亮度^(-AE_CURVE) × 2^AE_OFFSET`。
单位链路不一致时，任何“看起来像”的算法都会整片过曝，调参数只是在掩盖链路差异。所以必须整条管线一起移植。

## 三、iterationT 主世界绘制流程

Iris 的执行顺序：阴影 → 不透明几何 → deferred 0–6 → 半透明几何 → composite 0–16 → final。

| 程序 | 开关 | 写入 | 做什么 |
| --- | --- | --- | --- |
| `shadow` | — | 阴影深度、`shadowcolor0` 贴图色、`shadowcolor1` 法线与天空光 | 阴影图；植物摆动；彩色半透明阴影；全局光反射阴影图的数据来源 |
| `dh_shadow` | `DH_SHADOW` | 同上 | 远景地形进阴影图 |
| `gbuffers_terrain`（含几何着色器）等不透明程序 | — | 0、3、5 | 0：贴图色（伽马空间），3：八面体法线 rg + 光照图 ba，5：打包高光 rg、材质编号 b、打包（湿润，视差阴影）a |
| `gbuffers_skybasic`、`gbuffers_skytextured` | — | 0 | 原版天空与日月贴图叠进零号画面，`deferred3` 当天体颜色读取 |
| `gbuffers_weather` | — | 0 的 a | 混合方式 `ZERO ONE ZERO ONE_MINUS_SRC_ALPHA` 把雨雪遮罩乘进零号 a |
| `deferred` | `CAUSTICS` 或水下体积雾 | 7（左下角最多 500 像素方块） | 水面波浪法线贴图，供焦散采样 |
| `deferred1` | `GI_RSM` | 2 | 反射阴影图全局光的时间滤波 |
| `deferred2` | — | 1 | rgb：全局光空间滤波；a：`GTAO` 遮蔽 |
| `deferred3` | — | 1、2 | 天空像素：预计算大气 + 体积云 + 平面云 + 星星 + 日月；二号：上半屏 3×2 天空盒图、右上角云影贴图 |
| `deferred4`、`deferred5` | `CLOUD_SHADOW` | 2 | 云影贴图横向、纵向高斯模糊 |
| `deferred6` | — | 4、6 | 把不透明法线光照图复制进四号、材质编号复制进六号 b，作为半透明层的默认值 |
| `gbuffers_water`、`dh_water`、`gbuffers_hand_water` | — | 4、6、0 | 半透明层法线光照图、打包颜色、材质编号、水遮罩 |
| `composite` | — | 1 | 不透明表面完整光照：天光、全局光、`GTAO`、手持光、方块光、自发光、可变半影阴影、次表面散射、屏幕空间阴影、焦散、高光 |
| `composite1` | — | 1 | 水下与水后雾；a 记录全反射 |
| `composite2` | — | 3 | 屏幕空间反射与天空盒回退、反射里的体积雾与地表散射；a 为命中距离 |
| `composite3`、`composite4` | `ENABLE_PBR` | 3 | 反射小波滤波，两次半径 40 与 20 |
| `composite5` | — | 1、3 | 折射、彩色玻璃吸收、合并反射、手持光高光、地表大气散射、体积雾、雨、原版雾、选择框、浦肯野效应；a 为景深弥散；三号写镜头光斑 |
| `composite6` | `DOF` | 1 | 景深 |
| `composite7` | — | 7 | 时间抗锯齿历史（`flip.composite5.colortex7=true`） |
| `composite8` | — | 1、2 | 运动模糊（a 为泛光引导）；二号顶行特殊像素：自动曝光、标题计数、全局云影、景深对焦深度 |
| `composite9`–`composite13` | `BLOOM` | 5 | 泛光降采样与升采样链 |
| `composite14` | — | 1 | 合并泛光、暗角、曝光、色调映射、高级调色 |
| `composite15` | `FSR` | 1 | `CAS` 锐化 |
| `composite16` | `FSR` | 8 | `FSR` 放大 |
| `final` | — | 屏幕 | `CAS` 或 `FSR` 锐化、手与玩家的 `FXAA`、抖动、黑边 |

二号画面顶行特殊像素：`(0, H-1).a` 自动曝光，`(20, H-1).a` 标题计数，`(40, H-1).a` 全局云影，`(60, H-1).a` 景深对焦深度。

## 四、缓冲协议

| 编号 | 格式 | 每帧清除 | 用途 |
| --- | --- | --- | --- |
| 0 | `RGBA8` | 是，清成 (0,0,0,1) | 贴图色、天体颜色、雨遮罩 |
| 1 | `RGBA16` | 否 | 全局光与遮蔽 → 场景曲线编码颜色 → 色调映射后的颜色 |
| 2 | `RGBA16` | 否 | 全局光历史、天空盒图、云影贴图、顶行统计像素 |
| 3 | `RGBA16` | 是 | 不透明法线光照图 → 反射数据 → 镜头光斑 |
| 4 | `RGBA16` | 是 | 半透明法线光照图；deferred 阶段被三维云噪声贴图替换采样 |
| 5 | `RGBA16` | 是 | 不透明高光材质 → 泛光 |
| 6 | `RGBA16` | 是 | 半透明颜色材质与水遮罩；deferred 阶段被第二张三维云噪声替换采样 |
| 7 | `RGBA16` | 否 | 焦散法线方块 → 时间抗锯齿历史 |
| 8 | `RGBA8`，尺寸 2.0 | — | `FSR` 输出；deferred 与 composite 阶段被预计算大气三维贴图替换采样 |

格式、清除与 Iris 常量照 iterationT `composite.fsh` 文件头移植进 `rendering/buffers.glsl`。

## 五、贴图、属性与自定义 uniform

- `texture/` 整个目录原样复制进 `shaders/texture/`：大气数据、两张云噪声、三张涟漪动画、`noise.png`、`itt320.png` 与对应 `.mcmeta`。
- `shaders.properties` 里除菜单外的全部加载器设置原样移植进 `rendering/pipeline.properties`：
  渲染开关、`alphaTest`、`blend`、`texture`、`size.buffer`、`flip`、程序开关、自定义 `uniform` 与 `variable`。
  条件里的选项名换成 Omni 名字；根目录程序名改成 `world0/` 前缀。
- `block.properties`、`entity.properties`、`item.properties` 原样移植（编号与材质编号一一对应）。

## 六、下界与末地

- `world-1`：gbuffers 同主世界（天空贴图没有几何着色器），`shadow`、`dh_terrain`、`dh_water`、`deferred`、`composite`–`composite16`、`final`；没有 `deferred1`–`deferred6` 与 `dh_shadow`。
- `world1`：gbuffers 同上，`shadow`、`dh_shadow`、`dh_terrain`、`dh_water`、`deferred`、`deferred1`、`deferred2`、`deferred4`、`composite`–`composite16`、`final`。
- 两个维度的程序内容与主世界不同（下界时间抗锯齿、下界配色、末地天空等），由第五片单独移植。

## 七、文件对照

| iterationT 来源 | Omni 文件 |
| --- | --- |
| `Lib/Utilities.glsl` | `common/math.glsl` |
| `Lib/UniformDeclare.glsl` | `common/uniforms.glsl` |
| `Lib/Uniform/GbufferTransforms.glsl` | `common/coordinates.glsl` |
| `Lib/BasicFounctions/TemporalNoise.glsl` | `common/noise.glsl` |
| `Lib/GbufferData.glsl`、`Settings.glsl` 的材质编号 | `effects/material.glsl` |
| `Lib/IndividualFounctions/Parallax.glsl` | `effects/material.glsl` |
| `Lib/Uniform/Shadow*.glsl`、`Lib/BasicFounctions/Sunlight_Shadow.glsl` | `effects/shadow.glsl` |
| `Lib/BasicFounctions/PrecomputedAtmosphere.glsl`、`deferred3` 的星星与天空盒投影 | `effects/sky.glsl` |
| `NUBIS.glsl`、`PlanarClouds.glsl`、`CloudShadow.glsl` | `effects/cloud.glsl` |
| `GlobalIllumination.glsl`、`GTAO.glsl` | `effects/ambient.glsl` |
| `Lib/BasicFounctions/Blocklight.glsl` | `effects/blocklight.glsl` |
| `composite.fsh` 的 `SkyLighting` 与 `CompositeVS.glsl` 的光色计算 | `effects/sunlight.glsl` |
| `WaterWaves.glsl`、`PhysicsOceans.glsl`、`Ripple.glsl`、`composite1` 水雾、`composite5` 折射与吸收 | `effects/water.glsl` |
| `SSR.glsl`、`ReflectionFilter.glsl`、`composite2` 与 `composite5` 的反射函数 | `effects/reflection.glsl` |
| `VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`、`VanillaComposite.glsl` 的雾 | `effects/fog.glsl` |
| `VanillaComposite.glsl` 的选择框、`gbuffers_line` 图像输出 | `effects/selection.glsl` |
| 植物摆动（`Terrain_VS`、`Shadow_VS` 内） | `effects/vegetation.glsl` |
| 雨（`composite5` 的 `Rain`）与天气程序的计算 | `effects/weather.glsl` |
| 实体状态色、发光眼、手部视野 | `effects/entity.glsl` |
| 远景地形噪声与剔除 | `effects/world.glsl` |
| `DOF.glsl`、`LensGlareFlare.glsl`、`MotionBlur.glsl` 的模糊部分、暗角 | `effects/lens.glsl` |
| `TAA.glsl`、`TAA_Nether.glsl`、`Final.glsl` 的 `FXAA` | `effects/antialiasing.glsl` |
| `Bloom.glsl`、`Final.glsl` 的 `MergeBloom` | `effects/bloom.glsl` |
| `Final.glsl` 的色调映射、曝光、调色、黑边，`AgX.glsl`，`MotionBlur.glsl` 的曝光统计，浦肯野效应 | `effects/color.glsl` |
| `FsrEASU.glsl`、`Final.glsl` 的 `CAS` 与 `FSR` 锐化 | `effects/upscale.glsl` |
| `PrintFloat.glsl` | `effects/debug.glsl` |
| `NetherColor.glsl` | `effects/nether.glsl` |
| `EndSky.glsl` | `effects/end.glsl` |

绘制主体（`rendering/`）与程序宏：

| 程序 | 主体 | 程序宏 |
| --- | --- | --- |
| `shadow`、`dh_shadow` | `shadow` | `OMNI_SHADOW_PASS`、`OMNI_DH_SHADOW_PASS` |
| `gbuffers_terrain`（顶点、几何、片元） | `terrain` | `OMNI_TERRAIN_PASS` |
| `gbuffers_entities`、`gbuffers_block`、`gbuffers_hand`、`gbuffers_spidereyes` | `entities` | `OMNI_ENTITIES_PASS`、`OMNI_BLOCK_PASS`、`OMNI_HAND_PASS`、`OMNI_SPIDEREYES_PASS` |
| `gbuffers_water`、`gbuffers_hand_water` | `translucent` | `OMNI_WATER_PASS`、`OMNI_HAND_WATER_PASS` |
| `gbuffers_basic`、`line`、`textured`、`damagedblock`、`armor_glint`、`beaconbeam`、`weather` | `overlay` | `OMNI_BASIC_PASS`、`OMNI_LINE_PASS`、`OMNI_TEXTURED_PASS`、`OMNI_DAMAGEDBLOCK_PASS`、`OMNI_ARMOR_GLINT_PASS`、`OMNI_BEACONBEAM_PASS`、`OMNI_WEATHER_PASS` |
| `gbuffers_skybasic`、`gbuffers_skytextured`（主世界含几何着色器） | `celestial` | `OMNI_SKYBASIC_PASS`、`OMNI_SKYTEXTURED_PASS` |
| `dh_terrain`、`dh_water` | `distant` | `OMNI_DH_TERRAIN_PASS`、`OMNI_DH_WATER_PASS` |
| `deferred`–`deferred6` | `deferred` | `OMNI_DEFERRED0_PASS` … `OMNI_DEFERRED6_PASS` |
| `composite`–`composite5` | `composite` | `OMNI_COMPOSITE0_PASS` … `OMNI_COMPOSITE5_PASS` |
| `composite6`–`composite16` | `post` | `OMNI_COMPOSITE6_PASS` … `OMNI_COMPOSITE16_PASS` |
| `final` | `final` | `OMNI_FINAL_PASS` |

阶段宏：`OMNI_VERTEX`、`OMNI_GEOMETRY`、`OMNI_FRAGMENT`、`OMNI_COMPUTE`。维度宏：`OMNI_OVERWORLD`、`OMNI_NETHER`、`OMNI_END`。
光传播体积的 `setup` 计算程序保留，主体仍是 `rendering/lpv.glsl`。

### 地基接口（甲片交付，各片必须按此写）

`common/` 提供的函数与常量（名字保持 iterationT 原名，直接调用）：

- `common/math.glsl`：`PI`、`hPI`、`TAU`、`rPI`、`goldenRatio`、`plasticRatio`、`goldenAngle`、`saturate`、`curve`、`Luminance`、`fsign`、`fsqrt`、`min3`…`max9`、`minVec3`、`maxVec3`、`remapSaturate`、`remap`、`atan2`、`facos`、`LinearToGamma`、`GammaToLinear`、`LinearToCurve`、`CurveToLinear`、`DoNightEye`、`Pack2x8`、`Unpack2x8`、`Pack2x16`、`Unpack2x16`、`DecodeNormalTex`、`OctWrap`、`EncodeNormal`、`DecodeNormal`、`D_Walter`、`F_Schlick`、`V_Schlick`、`Fd_Burley`、`SpecularGGX`、`Blackbody`、`RayPlaneIntersection`、`RaySphereIntersection`、`RayleighPhaseFunction`、`MiePhaseFunction`、`InterleavedGradientNoise`、`bayer2`…`bayer128`、`Sequences_R1`、`Sequences_R2`、`BicubicTexture`、`BicubicBlurTexture`，以及内部常数 `MAIN_OUTPUT_FACTOR`、`EXPOSURE_OUTPUT_FACTOR`、`FTC_OFFSET`、`ANIMATION_SPEED`、`WATER_REFRACT_IOR`、`CAUSTICS_TEX_RESOLUTION`。
- `common/uniforms.glsl`：全部加载器输入（含 `screenSize`、`pixelSize`、`taaJitter`、眼部亮度平滑量、远景矩阵与深度、`colortex0`…`colortex8`、`depthtex0`…`depthtex2`、`noisetex`）。延迟与合成阶段的 `colortex4`/`colortex6` 是三维云噪声、`colortex8` 是三维大气数据，采样器类型由程序自己打开的 `COLORTEX_CLOUDNOISE`、`COLORTEX8_2D` 选择。
- `common/coordinates.glsl`：`ViewPos_From_ScreenPos`、`ViewPos_From_ScreenPos_Raw`、`ScreenPos_From_ViewPos`、`ScreenPos_From_ViewPos_Raw`、`LinearDepth_From_ScreenDepth`、`ScreenDepth_From_LinearDepth`，以及 `_DH` 远景版本与 `ScreenDepth_From_DHScreenDepth`。
- `common/noise.glsl`：`BlueNoise`、`BlueNoiseTemporal`、`BayerTemporal`。

绘制主体占位（各片用自己的算法替换）：`terrain`、`entities`、`translucent`、`overlay`、`celestial`、`shadow`、`distant`、`deferred`、`composite`、`post`、`final`，以及保留的 `lpv`（光传播体积计算）。

每个主体必须按下面的顺序引入，选项才不会在用到时还没定义：

```
common/uniforms.glsl → common/math.glsl →（定义本程序所需选项的效果文件，例如 antialiasing、sky、cloud …）
→ common/coordinates.glsl → common/noise.glsl →（其他效果文件）→ 本程序的全局量与 main()
```

效果文件之间可以互相引入（各自带 `_INCLUDED` 守卫）；`common/coordinates.glsl` 里的函数用 `OMNI_TAA` 决定是否撤销抖动，所以任何用到坐标换算的地方都要先引入 `effects/antialiasing.glsl`。

## 八、命名与写法规则

1. 一比一：数学、常数、分支、顺序、采样方式与 iterationT 相同。不“改进”、不简化、不合并步骤；必须偏离时写进本文件“偏离记录”。
2. 函数、结构体、全局变量、输入输出变量、uniform 名字保持 iterationT 原名，各文件之间按原名互相调用。只修拼写：`BlueNoiseTemproal` → `BlueNoiseTemporal`、`Soild` → `Solid`。
3. iterationT 内部选择宏换名：`DIMENSION_MAIN` → `OMNI_OVERWORLD`，`DIMENSION_NETHER` → `OMNI_NETHER`，`DIMENSION_END` → `OMNI_END`，`PROGRAM_VSH` → `OMNI_VERTEX`；`PROGRAM_GI_0` 这类按程序选段的宏换成第七节的程序宏。`COLORTEX_CLOUDNOISE`、`COLORTEX8_2D`、`VFOG_LQ`、`VS_*` 这类由程序自己打开的宏保留原名，在绘制主体里定义。
4. 效果文件只引用 `common/` 文件；效果之间的依赖由绘制主体按 iterationT 程序的引用顺序依次引入，避免引用环。效果文件用 `#ifndef OMNI_<文件名>_INCLUDED` 守卫。
5. iterationT 依赖“调用前已声明的全局量”（如 `texelCoord`、`colorShadowlight`）的地方照原样保留，在效果文件头写清调用前提。
6. 注释遵守 `AGENTS.md`：中文、至少一半非空行有说明、不写英文句子。英文缩写和标识符放进反引号，例如“`GTAO` 地平线遮蔽”，审计会跳过反引号内容。
7. 每个绘制主体只写阶段流程与输入输出；算法函数放进效果文件。

## 九、选项规则

- 名字：iterationT 选项 `X` 改名为 `OMNI_X`；加载器原生常量 `shadowMapResolution`、`shadowDistance`、`sunPathRotation`、`wetnessHalflife`、`drynessHalflife` 保留原名。
- 拼写修正：`SEREEN_RATIO` → `OMNI_SCREEN_RATIO`，`DOF_DEPTH_SMMOOTH_HALFLIFE` → `OMNI_DOF_DEPTH_SMOOTH_HALFLIFE`，`CLOUD_CLEAR_COVERY` → `OMNI_CLOUD_CLEAR_COVERAGE`，`CLOUD_RAIN_COVERY` → `OMNI_CLOUD_RAIN_COVERAGE`，`MOTION_BLUR_SUTTER_ANGLE` → `OMNI_MOTION_BLUR_SHUTTER_ANGLE`，`ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE` → `OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE`。
- 不移植：`TITLE`、`iterationT_VERSION`、`iterationT_VERSION_TYPE`、`iterationT_INFO`（菜单装饰），`CAMERA_APERTURE`、`FLARE_GHOSTING`（翻译里有、源码没有）。
- 默认值与可选值照搬 iterationT；中英文名称与悬停说明从 iterationT 的 `lang/zh_cn.lang`、`lang/en_us.lang` 取，去掉颜色符号后可以改写成更好懂的话。
- 每个选项只在下表归属文件里定义一次，其他文件通过引入归属文件使用它。
- Omni 已有选项：
  - 与 iterationT 选项同名（如 `OMNI_DOF`、`OMNI_GAMMA`）：直接改成 iterationT 含义、默认值与取值。
  - 含义相同但名字不同：删除旧定义，在交付报告里写“旧名 → 新名”，主助手统一登记进 `options.py` 的 `OPTION_RENAMES`。
  - iterationT 没有的额外功能：保留并接到新管线的真实计算，默认值必须让画面与 iterationT 一致（默认关闭或取不改变画面的值）。
  - 只属于被替换旧算法、找不到对应含义的参数：不要直接删除，写进报告由主助手决定。

选项归属（括号内为数量，名字为 iterationT 原名）：

- `effects/ambient.glsl`（21）：`DISABLE_HAND_GI`、`DISABLE_HAND_GI_VELOCITY`、`DISABLE_PLAYER_GI`、`DISABLE_PLAYER_GI_VELOCITY`、`GI_BRIGHTNESS`、`GI_FALLOFF`、`GI_QUALITY`、`GI_RADIUS`、`GI_RENDER_RESOLUTION`、`GI_RSM`、`GI_SKYLIGHT_FALLOFF`、`GTAO`、`GTAO_FALLOFF_START`、`GTAO_MAX_RADIUS`、`GTAO_MULTIBOUNCE`、`GTAO_QUALITY`、`GTAO_RADIUS_MODE`、`GTAO_SCREEN_RADIUS`、`GTAO_SLICE_QUALITY`、`GTAO_STRENGTH`、`GTAO_WORLD_RADIUS`
- `effects/antialiasing.glsl`（5）：`DISABLE_HAND_TAA`、`DISABLE_PLAYER_TAA_MOTION_BLUR`、`TAA`、`TAA_AGGRESSION`、`TAA_BLENDWEIGHT`
- `effects/blocklight.glsl`（23）：`DIRECTIONAL_BLOCKLIGHT`、`DIRECTIONAL_BLOCKLIGHT_STRENGTH`、`EMISSIVENESS_BRIGHTNESS`、`FLASHLIGHT_CAMERA_SMOOTH`、`FLASHLIGHT_CAMERA_SMOOTH_TIME`、`FLASHLIGHT_COLOR_B`、`FLASHLIGHT_COLOR_G`、`FLASHLIGHT_COLOR_R`、`FLASHLIGHT_FOV`、`FLASHLIGHT_HELDLIGHT_FALLOFF`、`FLASHLIGHT_POS_L_X`、`FLASHLIGHT_POS_L_Y`、`FLASHLIGHT_POS_R_X`、`FLASHLIGHT_POS_R_Y`、`HELDLIGHT_BRIGHTNESS`、`HELDLIGHT_FALLOFF`、`HELDLIGHT_MODE`、`HELDLIGHT_SHADOW`、`SPECULAR_HELDLIGHT`、`TEXTURE_BRIGHTNESS`、`TEXTURE_EMISSIVENESS_MODE`、`TORCHLIGHT_BRIGHTNESS`、`TORCHLIGHT_COLOR_TEMPERATURE`
- `effects/bloom.glsl`（4）：`BLOOM`、`BLOOM_AMOUNT`、`NETHER_END_BLOOM_BOOST`、`VFOG_BLOOM`
- `effects/cloud.glsl`（33）：`CLOUD_BASE_NOISE_SCALE`、`CLOUD_BOTTOM_BRIGHTNESS`、`CLOUD_CLEAR_ALTITUDE`、`CLOUD_CLEAR_COVERY`、`CLOUD_CLEAR_DENSITY`、`CLOUD_CLEAR_SCALE`、`CLOUD_CLEAR_SKYLIGHTING`、`CLOUD_CLEAR_SUNLIGHTING`、`CLOUD_CLEAR_THICKNESS`、`CLOUD_COVERAGE_NOISE_OFFSET`、`CLOUD_DETAILED_NOISE_SCALE`、`CLOUD_DETAILED_NOISE_STRENGTH`、`CLOUD_FADE`、`CLOUD_OUTSCATTER_FACTOR`、`CLOUD_QUALITY`、`CLOUD_RAIN_ALTITUDE`、`CLOUD_RAIN_COVERY`、`CLOUD_RAIN_DENSITY`、`CLOUD_RAIN_SCALE`、`CLOUD_RAIN_SKYLIGHTING`、`CLOUD_RAIN_SUNLIGHTING`、`CLOUD_RAIN_THICKNESS`、`CLOUD_SHADOW`、`CLOUD_SHADOWTEX_SIZE`、`CLOUD_SHADOW_FADE`、`CLOUD_SHADOW_RANGE`、`CLOUD_SPEED`、`PC_ALTITUDE`、`PC_COVERAGE`、`PC_NOISE_SCALE`、`PLANAR_CLOUDS`、`RAIN_SHADOW`、`VOLUMETRIC_CLOUDS`
- `effects/color.glsl`（21）：`ABNEY_EFFECT_CORRECTION`、`ADVANCED_COLOR`、`AE_CURVE`、`AE_MODE`、`AE_OFFSET`、`AGX_EV`、`EV_VALUE`、`EXPOSURE_TIME`、`GAMMA`、`LUMA_GAMMA`、`LUMINANCE_WEIGHT_MODE`、`LUMINANCE_WEIGHT_STRENGTH`、`MANUAL_EXPOSURE`、`PURKINJE_EFFECT`、`PURKINJE_EFFECT_STRENGTH`、`PURKINJE_EFFECT_THRESHOLD`、`SATURATION`、`SEREEN_RATIO`、`SMOOTH_EXPOSURE`、`TONEMAP_OPERATOR`、`WHITE_CLIP`
- `effects/end.glsl`（5）：`ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE`、`ACCRETIONDISC_DOPPLER_EFFECT`、`END_MANUAL_PLANET_ANGLE`、`END_MANUAL_PLANET_CYCLE`、`END_PLANET_CYCLE`
- `effects/entity.glsl`（4）：`ENTITIES_STATUS_COLOR`、`EYES_LIGHTING`、`HAND_FOV`、`HAND_FOV_MODE`
- `effects/fog.glsl`（28）：`DH_LIMIT_VFOG_DIST`、`INDOOR_FOG`、`LANDSCATTERING`、`LANDSCATTERING_REFLECTION`、`LANDSCATTERING_REFRACTION`、`LANDSCATTERING_SHADOW`、`LANDSCATTERING_SHADOW_QUALITY`、`LANDSCATTERING_STRENGTH`、`NETHERFOG_DENSITY`、`UNDERWATER_VFOG`、`UNDERWATER_VFOG_DENSITY`、`VFOG`、`VFOG_CLOUD_SHADOW`、`VFOG_DENSITY`、`VFOG_DENSITY_BASE`、`VFOG_FALLOFF`、`VFOG_FOG_DENSITY`、`VFOG_HEIGHT`、`VFOG_HEIGHT_2`、`VFOG_IGNORE_WORLDTIME`、`VFOG_NOISE_TYPE`、`VFOG_QUALITY`、`VFOG_REFLECTION`、`VFOG_REFRACTION`、`VFOG_STAINED`、`VFOG_SUNLIGHT_ABSORPTION`、`VFOG_SUNLIGHT_DENSITY`、`VFOG_VOLUMETRIC_LIGHTING`
- `effects/lens.glsl`（25）：`CAMERA_FOCAL_POINT`、`CAMERA_FOCUS_MODE`、`DOF`、`DOF_BLUR`、`DOF_CATSEYE`、`DOF_CATSEYE_MIDPOINT`、`DOF_CATSEYE_STRENGTH`、`DOF_COCSPREAD_QUALITY`、`DOF_DEPTH_SMMOOTH_HALFLIFE`、`DOF_FOCUS_IGNORE_HAND_PARTICLE`、`DOF_MAX_COC`、`DOF_QUALITY`、`FLARE_BRIGHTNESS`、`GLARE_BRIGHTNESS`、`GLARE_FLARE_SHADOWBASED`、`LENS_FLARE`、`LENS_GLARE`、`MOTION_BLUR`、`MOTION_BLUR_DITHER`、`MOTION_BLUR_QUALITY`、`MOTION_BLUR_SUTTER_ANGLE`、`SNEAKING_VIGNETTE`、`VIGNETTE`、`VIGNETTE_FALLOFF`、`VIGNETTE_ROUNDNESS`
- `effects/material.glsl`（29）：`ANISOTROPIC_FILTERING_NORMAL_SPECULAR`、`ANISOTROPIC_FILTERING_QUALITY`、`DISABLE_HAND_SPECULAR`、`DISABLE_PLAYER_SPECULAR`、`EMISSIVENESS_GAMMA`、`ENABLE_PBR`、`ENTITIES_NORMAL_CLAMP`、`ENTITIES_PARALLAX`、`ENTITIES_TEXTURE_RESOLUTION`、`ENTITIES_VS_TBN`、`GENERAL_GRASS_FIX`、`HAND_NORMAL_CLAMP`、`PARALLAX_BASED_NORMAL`、`PARALLAX_DEPTH`、`PARALLAX_FADE`、`PARALLAX_MODE`、`PARALLAX_QUALITY`、`PARALLAX_SHADOW`、`PARALLAX_SHADOW_QUALITY`、`POROSITY_ABSORPTION`、`ROUGHNESS_CLAMP`、`SSS_STRENGTH`、`SSS_STRENGTH_OFFSET`、`TERRAIN_NORMAL_CLAMP`、`TERRAIN_VS_TBN`、`TEXTURE_DEFAULT_POROSITY`、`TEXTURE_PBR_FORMAT`、`TEXTURE_PBR_POROSITY`、`TEXTURE_RESOLUTION`
- `effects/nether.glsl`（1）：`NETHER_BRIGHTNESS`
- `effects/selection.glsl`（4）：`LINE_IMAGE_OUTPUT`、`SELECTION_BOX_COLOR_B`、`SELECTION_BOX_COLOR_G`、`SELECTION_BOX_COLOR_R`
- `effects/shadow.glsl`（16）：`COLORED_SHADOWS`、`DH_SHADOW`、`DH_SHADOW_CULLING`、`DH_SHADOW_FIX`、`DISABLE_PLAYER_SCREEN_SPACE_SHADOWS`、`SCREEN_SPACE_SHADOWS`、`SHADOW_BASIC_BLUR`、`SHADOW_MAP_BIAS`、`SSS_BRIGHTNESS`、`SSS_NORMAL`、`SSS_QUALITY`、`VARIABLE_PENUMBRA_SHADOWS`、`VPS_QUALITY`、`VPS_SPREAD`、`shadowDistance`、`shadowMapResolution`
- `effects/sky.glsl`（11）：`ATMO_HORIZON`、`ATMO_REFLECTION_HORIZON`、`BILINEAR_MOON_TEXTURE`、`BILINEAR_SKYBOX_TEXTURE`、`MOON_TEXTURE`、`NIGHT_BRIGHTNESS`、`SKYBOX_TEXTURE`、`SKY_IMAGE_RESOLUTION`、`SKY_TEXTURE_BRIGHTNESS`、`STAR_TYPE`、`sunPathRotation`
- `effects/sunlight.glsl`（6）：`CAVE_MODE`、`COLD_MOONLIGHT`、`NOLIGHT_BRIGHTNESS`、`SKYLIGHT_INTENSITY`、`SUNLIGHT_INTENSITY`、`SUNLIGHT_LEAK_FIX`
- `effects/upscale.glsl`（5）：`CAS_DENOISE`、`CAS_SHARPNESS`、`FSR`、`FSR_DENOISE`、`FSR_SHARPNESS`
- `effects/vegetation.glsl`（2）：`SHADOW_WAVING_PLANTS`、`WAVING_PLANTS`
- `effects/water.glsl`（6）：`CAUSTICS`、`UNDERWATER_FOG`、`WATERFOG_DENSITY`、`WATER_PARALLAX`、`WAVE_HEIGHT`、`WAVE_SCALE`
- `effects/weather.glsl`（9）：`DISABLE_LOCAL_PRECIPITATION`、`RAIN_DISTURBANCE`、`RAIN_SPLASH_EFFECT`、`RAIN_VISIBILITY`、`RAIN_WIND_X`、`RAIN_WIND_Z`、`SURFACE_WETNESS`、`drynessHalflife`、`wetnessHalflife`
- `effects/world.glsl`（4）：`DH_TERRAIN_CULLING`、`DH_TEXTURE_NOISE`、`DH_TEXTURE_NOISE_STEPS`、`DH_TEXTURE_NOISE_STRENGTH`

## 九点二、内部常数归属

`Settings.glsl` 里不进菜单的常数也只定义一次，名字保持原名：

- `common/math.glsl`：`MAIN_OUTPUT_FACTOR`、`EXPOSURE_OUTPUT_FACTOR`、`FTC_OFFSET`、`ANIMATION_SPEED`、`WATER_REFRACT_IOR`、`CAUSTICS_TEX_RESOLUTION`。
- `effects/material.glsl`：全部 `MATID_*`、`PARALLAX_MAX_REFINEMENTS`、`CORRECT_PARTICLE_NORMAL`。
- `effects/reflection.glsl`：`RAYTRACE_QUALITY`、`RAYTRACE_REFINEMENT_STEPS`、`RAYTRACE_ZDIFF_THRESHOLD`。
- `effects/sky.glsl`：`ATMO_MIN_ALTITUDE`、`ATMO_SKYBOX_MIN_ALTITUDE`。
- `effects/fog.glsl`：`VFOG_SUNLIGHT_STEPS`、`VFOG_SUNLIGHT_STEPLENGTH`。
- `effects/antialiasing.glsl`：`TAA_BICUBIC_PREVIOUS`、`TAA_DEPTH_COMPARE`、`TAA_MICRO_BLUR`、`TAA_DEPTH_COMPARE_THRESHOLD`。
- `effects/color.glsl`：`AE_CLAMP`。

效果文件用到别的文件的选项或常数时，不重复定义；由绘制主体先引入归属文件。

## 九点五、同名函数
iterationT 有些函数在多个文件各写一份。合进 Omni 后同一个程序可能同时引入两份，必须先处理：

- `BicubicBlurTexture`（泛光、云影、阴影顶点、地形顶点）、`BicubicTexture`（两种时间抗锯齿）：内容相同则放进 `common/math.glsl` 一份；不同则各自留在归属效果文件并加后缀区分。由甲片比对并决定，结果写进下面偏离记录。
- `ShadowScreenPos_From_WorldPos*`、`DistortShadowScreenPos`：主世界版与末地版（`ShadowTransformsEnd.glsl`）都放 `effects/shadow.glsl`，末地版用 `#ifdef OMNI_END` 选择。
- 植物摆动常数 `heavy*`、`light*`、`speed*`：只在 `effects/vegetation.glsl` 定义一次，地形与阴影顶点共用。
- 时间抗锯齿辅助函数（`clipAABB`、`RGB_To_YCoCg`、`SampleDepthFetch` 等）：主世界与下界版放 `effects/antialiasing.glsl`，用 `#ifdef OMNI_NETHER` 选择不同的部分。
- `CalculateCameraVelocity`：放 `common/coordinates.glsl` 一份；各处实现不同时加后缀。
- `AxialGaussianBlur`：泛光版留在 `effects/bloom.glsl`，云影模糊版改名 `CloudShadowAxialBlur` 放 `effects/cloud.glsl`。
- `Calculate3DNoise`、`CalculateStars`：末地版留在 `effects/end.glsl` 并加 `End` 前缀，主世界版分别在 `effects/fog.glsl`、`effects/sky.glsl`。
- `NetherFog`、`ComputeFakeSkyReflection`、`WaterRefractionLite`、`TransparentAbsorption`：维度各自实现不同时，下界与末地版加 `Nether`、`End` 后缀，由己片负责。

## 十、分片与状态

移植在本地分支 `itt-port` 进行。管线是整体替换，中间状态无法单独通过构建，所以各片完成并通过集成检查后再合并进 `main` 推送；子任务不提交，由主助手统一提交。

| 分片 | 负责文件 | 状态 |
| --- | --- | --- |
| 甲 地基 | `build.py`、`options.py`、`rendering/programs.json`、`rendering/pipeline.properties`、`rendering/buffers.glsl`、`common/*`、`shaders/texture/`、`*.properties`、工具测试 | 完成（占位主体可编译，`python build.py verify` 通过） |
| 乙 几何阶段 | `rendering/terrain`、`entities`、`translucent`、`overlay`、`celestial`、`shadow`、`distant`；`effects/material`、`shadow`、`water`、`vegetation`、`weather`、`entity`、`world`、`selection`、`season` | 进行中 |
| 丙 延迟阶段 | `rendering/deferred`；`effects/sky`、`atmosphere`、`cloud`、`ambient`、`sunlight` | 进行中 |
| 丁 合成阶段 | `rendering/composite`；`effects/blocklight`、`reflection`、`fog`、`lpv` 与 `rendering/lpv` | 进行中 |
| 戊 后期 | `rendering/post`、`final`；`effects/lens`、`antialiasing`、`bloom`、`color`、`upscale`、`debug` | 进行中 |
| 己 下界与末地 | 维度程序、`effects/nether`、`effects/end`、下界时间抗锯齿 | 待甲到戊完成 |
| 庚 集成 | 选项改名登记、预设、测试、文档、离线检查、游戏内对照截图 | 待前面完成 |

## 十一、验证方式

1. `python build.py verify` 通过（十秒预算不变）。
2. 游戏内对照：同一位置、同一时间、同一天气，分别加载 iterationT 与 Omni 截图，逐项比较天空、阴影、水、雾、云、曝光与色调。
3. 偏离 iterationT 的地方必须写进下面的偏离记录，不能当成已复刻。

## 十二、偏离记录

1. 选项名加 `OMNI_` 前缀：iterationT 的选项名统一加前缀（如 `BLOOM` → `OMNI_BLOOM`），少量拼写修正见第九节。这是项目命名约定，值和默认值照 iterationT。
2. `BicubicBlurTexture`、`BicubicTexture`：原程序在多个文件各写一份，内容相同，合并进 `common/math.glsl` 一份；泛光版与云影版参数和返回类型不同（分别是 `vec3`/`vec4` 与不同纹理），按第九点五节留在各自效果文件。
3. `CalculateCameraVelocity`：原程序四处实现不同，按合同留在各自效果文件，各片自行处理。
4. `shaders.properties` 笔误：iterationT 原文 `program.world-1/program.composite9.enabled` 重复写了 `program.`，本移植修正为 `program.world-1/composite9.enabled`。
5. 大贴图压缩：`build.py` 打包时对 `.png`、`.bin` 用 `ZIP_STORED` 直接存放，九级压缩几十兆贴图要好几秒且几乎没有收益，会突破十秒检查预算。
6. `block.properties`、`entity.properties`、`item.properties` 与生成的 `shaders.properties` 加入审计的机器文件豁免：它们是逐行可对照的编号数据，不写中文说明。
7. 移植期开关：`build.py` 里的 `PORTING = True` 让“选项未接入入口”只警告、并把编译探针缩到主世界默认配置和环境；移植完成后由庚片删除该开关并恢复完整探针与全部代表配置。
8. 旧管线测试跳过：`tests/` 里断言旧管线算法与缓冲的 32 个测试用 `@unittest.skip(PORT_REPLACED)` 标记，理由写入测试文件；庚片按新管线重写后恢复。
