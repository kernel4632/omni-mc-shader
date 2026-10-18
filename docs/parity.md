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

Iris 的执行顺序：阴影 → 不透明几何 → deferred 0–8 → 半透明几何 → composite 0–16 → final。

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
| `deferred7`、`deferred8` | `CLOUD_LOWRES` | 10、1 | 低分辨率基础体积云：七号写十号（低分辨率云加色与透过率），八号读十号放大回一号；`OMNI_CLOUD_RENDER_SCALE` 大于一时才跑（Eclipse 来源，iterationT 没有；`dev.146` 合并） |
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
| 9 | `RGBA8` | 否 | 方块编号与生物群系（Eclipse 程序化草用的体素编号通路，Omni 额外，iterationT 没有这一号） |
| 10 | `RGBA16`，尺寸 0.5 或 0.25 | 是 | 低分辨率基础体积云的加色与透过率（Omni 额外，`deferred7` 写、`deferred8` 读；`OMNI_CLOUD_RENDER_SCALE > 1` 时才用） |

格式、清除与 Iris 常量照 iterationT `composite.fsh` 文件头移植进 `rendering/buffers.glsl`。
九号画面是 Omni 为 Eclipse 程序化草新增的额外缓冲（登记在 `rendering/buffers.glsl:55`），只有主世界地形片元写、几何阶段读，`OMNI_SHADER_GRASS` 关闭时不写不读，见第十二节偏离记录第 38 条。
十号画面是 Omni 为低分辨率基础体积云新增的额外缓冲（登记在 `rendering/buffers.glsl:57`），`deferred7` 写、`deferred8` 读，`OMNI_CLOUD_RENDER_SCALE` 为默认一时不写不读，见第十二节偏离记录第 51 条。

## 五、贴图、属性与自定义 uniform

- `texture/` 整个目录原样复制进 `shaders/texture/`：大气数据、两张云噪声、三张涟漪动画、`noise.png`、`itt320.png` 与对应 `.mcmeta`。
- `shaders.properties` 里除菜单外的全部加载器设置原样移植进 `rendering/pipeline.properties`：
  渲染开关、`alphaTest`、`blend`、`texture`、`size.buffer`、`flip`、程序开关、自定义 `uniform` 与 `variable`。
  条件里的选项名换成 Omni 名字；根目录程序名改成 `world0/` 前缀。
- `block.properties`、`entity.properties`、`item.properties` 原样移植（编号与材质编号一一对应）。

## 六、下界与末地

- `world-1`：gbuffers 同主世界（天空贴图没有几何着色器），`shadow`、`dh_terrain`、`dh_water`、`deferred`、`composite`、`composite2`–`composite16`、`final`；没有 `dh_shadow`、`composite1` 与 `deferred1`–`deferred8`。
- `world1`：gbuffers 同上，`shadow`、`dh_shadow`、`dh_terrain`、`dh_water`、`deferred`、`deferred1`、`deferred2`、`deferred4`、`composite`、`composite2`–`composite16`、`final`；没有 `composite1`、`deferred3`、`deferred5`、`deferred6`、`deferred7`、`deferred8`。
- 两个维度的程序内容与主世界不同（下界时间抗锯齿、下界配色、末地天空等），由第五片单独移植。

## 七、文件对照

| iterationT 来源 | Omni 文件 |
| --- | --- |
| `Lib/Utilities.glsl` | `common/math.glsl` |
| `Lib/UniformDeclare.glsl` | `common/uniforms.glsl` |
| `Lib/Uniform/GbufferTransforms.glsl` | `common/coordinates.glsl` |
| `Lib/BasicFounctions/TemporalNoise.glsl` | `common/noise.glsl` |
| `Lib/GbufferData.glsl`、`Settings.glsl` 的材质编号 | `effects/ground/material.glsl` |
| `Lib/IndividualFounctions/Parallax.glsl` | `effects/ground/parallax.glsl`（算法；选项仍在 `effects/ground/material.glsl`） |
| `Lib/Uniform/Shadow*.glsl`、`Lib/BasicFounctions/Sunlight_Shadow.glsl` | `effects/shadow/shadow.glsl` |
| `Lib/BasicFounctions/PrecomputedAtmosphere.glsl`、`deferred3` 的星星与天空盒投影 | `effects/sky/sky.glsl`（入口）与同目录 `atmosphere_model.glsl`、`sun_moon.glsl`、`moon_orbit.glsl`、`stars.glsl`、`skybox.glsl` |
| `NUBIS.glsl`、`PlanarClouds.glsl`、`CloudShadow.glsl` | `effects/cloud/cloud.glsl`（入口）与同目录 `volumetric.glsl`、`planar.glsl`、`shadow.glsl` |
| `GlobalIllumination.glsl`、`GTAO.glsl` | `effects/lighting/ambient.glsl` |
| `Lib/BasicFounctions/Blocklight.glsl` | `effects/lighting/blocklight.glsl` |
| `composite.fsh` 的 `SkyLighting` 与 `CompositeVS.glsl` 的光色计算 | `effects/lighting/sunlight.glsl` |
| `WaterWaves.glsl`、`PhysicsOceans.glsl`、`Ripple.glsl`、`composite1` 水雾、`composite5` 折射与吸收 | `effects/water/water.glsl` |
| `SSR.glsl`、`ReflectionFilter.glsl`、`composite2` 与 `composite5` 的反射函数 | `effects/reflection/reflection.glsl` |
| `VolumetricFog.glsl`、`UnderwaterVolumetricFog.glsl`、`VanillaComposite.glsl` 的雾 | `effects/fog/fog.glsl` |
| `VanillaComposite.glsl` 的选择框、`gbuffers_line` 图像输出 | `effects/ground/selection.glsl` |
| 植物摆动（`Terrain_VS`、`Shadow_VS` 内） | `effects/ground/vegetation.glsl` |
| 雨（`composite5` 的 `Rain`）与天气程序的计算 | `effects/weather/weather.glsl` |
| 实体状态色、发光眼、手部视野 | `effects/entity/entity.glsl` |
| 远景地形噪声与剔除 | `effects/world/world.glsl` |
| `DOF.glsl`、`LensGlareFlare.glsl`、`MotionBlur.glsl` 的模糊部分、暗角 | `effects/lens/lens.glsl` |
| `TAA.glsl`、`TAA_Nether.glsl`、`Final.glsl` 的 `FXAA` | `effects/clarity/antialiasing.glsl` |
| `Bloom.glsl`、`Final.glsl` 的 `MergeBloom` | `effects/color/bloom.glsl` |
| `Final.glsl` 的色调映射、曝光、调色、黑边，`AgX.glsl`，`MotionBlur.glsl` 的曝光统计，浦肯野效应 | `effects/color/color.glsl` |
| `FsrEASU.glsl`、`Final.glsl` 的 `CAS` 与 `FSR` 锐化 | `effects/clarity/upscale.glsl` |
| `PrintFloat.glsl` | `effects/dev/debug.glsl` |
| `NetherColor.glsl` | `effects/world/nether.glsl` |
| `EndSky.glsl` | `effects/world/end.glsl` |

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
| `deferred`–`deferred8` | `deferred` | `OMNI_DEFERRED0_PASS` … `OMNI_DEFERRED8_PASS` |
| `composite`–`composite5` | `composite` | `OMNI_COMPOSITE0_PASS` … `OMNI_COMPOSITE5_PASS` |
| `composite6`–`composite16` | `post` | `OMNI_COMPOSITE6_PASS` … `OMNI_COMPOSITE16_PASS` |
| `final` | `final` | `OMNI_FINAL_PASS` |

阶段宏：`OMNI_VERTEX`、`OMNI_GEOMETRY`、`OMNI_FRAGMENT`、`OMNI_COMPUTE`。维度宏：`OMNI_OVERWORLD`、`OMNI_NETHER`、`OMNI_END`。
光传播体积的 `setup`（填方块光表）与 `shadowcomp`（每帧传播）两个计算程序保留，主体仍是 `rendering/lpv.glsl`；体素化写在 `rendering/shadow.glsl` 的顶点阶段，`shadow` 入口按 `rendering/programs.json` 的 `extensions` 打开图像访问扩展。

### 地基接口（甲片交付，各片必须按此写）

`common/` 提供的函数与常量（名字保持 iterationT 原名，直接调用）：

- `common/math.glsl`：`PI`、`hPI`、`TAU`、`rPI`、`goldenRatio`、`plasticRatio`、`goldenAngle`、`saturate`、`curve`、`Luminance`、`fsign`、`fsqrt`、`max3`、`min4`…`max9`、`remapSaturate`、`atan2`、`facos`、`LinearToGamma`、`GammaToLinear`、`LinearToCurve`、`CurveToLinear`、`DoNightEye`、`Pack2x8`、`Unpack2x8`、`Pack2x16`、`Unpack2x16`、`DecodeNormalTex`、`OctWrap`、`EncodeNormal`、`DecodeNormal`、`D_Walter`、`F_Schlick`、`V_Schlick`、`Fd_Burley`、`SpecularGGX`、`Blackbody`、`RayPlaneIntersection`、`RaySphereIntersection`、`RayleighPhaseFunction`、`MiePhaseFunction`、`InterleavedGradientNoise`、`bayer2`、`bayer4`、`bayer8`、`bayer64`、`BicubicTexture`、`BicubicBlurTexture`、`omniNormalize`（Omni 额外，安全归一化），以及内部常数 `MAIN_OUTPUT_FACTOR`、`EXPOSURE_OUTPUT_FACTOR`、`ANIMATION_SPEED`、`WATER_REFRACT_IOR`、`CAUSTICS_TEX_RESOLUTION`。
- `common/uniforms.glsl`：全部加载器输入（含 `screenSize`、`pixelSize`、`taaJitter`、眼部亮度平滑量、远景矩阵与深度、`colortex0`…`colortex8`、`depthtex0`…`depthtex2`、`noisetex`）。延迟与合成阶段的 `colortex4`/`colortex6` 是三维云噪声、`colortex8` 是三维大气数据，采样器类型由程序自己打开的 `COLORTEX_CLOUDNOISE`、`COLORTEX8_2D` 选择。
- `common/coordinates.glsl`：`ViewPos_From_ScreenPos`、`ViewPos_From_ScreenPos_Raw`、`ScreenPos_From_ViewPos`、`ScreenPos_From_ViewPos_Raw`、`LinearDepth_From_ScreenDepth`、`ScreenDepth_From_LinearDepth`；远景版本（只在加载远景模组时存在，`DISTANT_HORIZONS` 守卫）为 `ViewPos_From_ScreenPos_DH`、`ViewPos_From_ScreenPos_Raw_DH`、`LinearDepth_From_ScreenDepth_DH`、`ScreenDepth_From_DHScreenDepth`。
- `common/noise.glsl`：`BlueNoise`、`BlueNoiseTemporal`、`BayerTemporal`。

绘制主体占位（各片用自己的算法替换）：`terrain`、`entities`、`translucent`、`overlay`、`celestial`、`shadow`、`distant`、`deferred`、`composite`、`post`、`final`，以及保留的 `lpv`（光传播体积计算）。

每个主体必须按下面的顺序引入，选项才不会在用到时还没定义：

```
common/uniforms.glsl → common/math.glsl →（定义本程序所需选项的效果文件，例如 antialiasing、sky、cloud …）
→ common/coordinates.glsl → common/noise.glsl →（其他效果文件）→ 本程序的全局量与 main()
```

效果文件之间可以互相引入（各自带 `_INCLUDED` 守卫）；`common/coordinates.glsl` 里的函数用 `OMNI_TAA` 决定是否撤销抖动，所以任何用到坐标换算的地方都要先引入 `effects/clarity/antialiasing.glsl`。

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
  - 含义相同但名字不同：删除旧定义，在交付报告里写“旧名 → 新名”，主助手统一登记进 `config.py` 的 `OPTION_RENAMES`。
  - iterationT 没有的额外功能：保留并接到新管线的真实计算，默认值必须让画面与 iterationT 一致（默认关闭或取不改变画面的值）。
  - 只属于被替换旧算法、在新算法里再也找不到含义的参数：不要直接删除，写进报告由主助手决定。

选项归属（括号内为数量，名字为 iterationT 原名）：

- `effects/lighting/ambient.glsl`（22）：`DISABLE_HAND_GI`、`DISABLE_HAND_GI_VELOCITY`、`DISABLE_PLAYER_GI`、`DISABLE_PLAYER_GI_VELOCITY`、`GI_BRIGHTNESS`、`GI_FALLOFF`、`GI_QUALITY`、`GI_RADIUS`、`GI_RENDER_RESOLUTION`、`GI_RSM`、`GI_SKYLIGHT_FALLOFF`、`GTAO`、`GTAO_FALLOFF_START`、`GTAO_MAX_RADIUS`、`GTAO_MULTIBOUNCE`、`GTAO_QUALITY`、`GTAO_RADIUS_MODE`、`GTAO_SCREEN_RADIUS`、`GTAO_SLICE_QUALITY`、`GTAO_STRENGTH`、`GTAO_WORLD_RADIUS`、`DH_AO`（Eclipse 来源，`dev.138`）
- `effects/clarity/antialiasing.glsl`（6）：`DISABLE_HAND_TAA`、`DISABLE_PLAYER_TAA_MOTION_BLUR`、`TAA`、`TAA_AGGRESSION`、`TAA_BLENDWEIGHT`、`TAA_DEPTH_COMPARE_THRESHOLD`（第九点二移入，`dev.156`）
- `effects/lighting/blocklight.glsl`（23）：`DIRECTIONAL_BLOCKLIGHT`、`DIRECTIONAL_BLOCKLIGHT_STRENGTH`、`EMISSIVENESS_BRIGHTNESS`、`FLASHLIGHT_CAMERA_SMOOTH`、`FLASHLIGHT_CAMERA_SMOOTH_TIME`、`FLASHLIGHT_COLOR_B`、`FLASHLIGHT_COLOR_G`、`FLASHLIGHT_COLOR_R`、`FLASHLIGHT_FOV`、`FLASHLIGHT_HELDLIGHT_FALLOFF`、`FLASHLIGHT_POS_L_X`、`FLASHLIGHT_POS_L_Y`、`FLASHLIGHT_POS_R_X`、`FLASHLIGHT_POS_R_Y`、`HELDLIGHT_BRIGHTNESS`、`HELDLIGHT_FALLOFF`、`HELDLIGHT_MODE`、`HELDLIGHT_SHADOW`、`SPECULAR_HELDLIGHT`、`TEXTURE_BRIGHTNESS`、`TEXTURE_EMISSIVENESS_MODE`、`TORCHLIGHT_BRIGHTNESS`、`TORCHLIGHT_COLOR_TEMPERATURE`
- `effects/color/bloom.glsl`（4）：`BLOOM`、`BLOOM_AMOUNT`、`NETHER_END_BLOOM_BOOST`、`VFOG_BLOOM`
- `effects/cloud/cloud.glsl`（33）：`CLOUD_BASE_NOISE_SCALE`、`CLOUD_BOTTOM_BRIGHTNESS`、`CLOUD_CLEAR_ALTITUDE`、`CLOUD_CLEAR_COVERY`、`CLOUD_CLEAR_DENSITY`、`CLOUD_CLEAR_SCALE`、`CLOUD_CLEAR_SKYLIGHTING`、`CLOUD_CLEAR_SUNLIGHTING`、`CLOUD_CLEAR_THICKNESS`、`CLOUD_COVERAGE_NOISE_OFFSET`、`CLOUD_DETAILED_NOISE_SCALE`、`CLOUD_DETAILED_NOISE_STRENGTH`、`CLOUD_FADE`、`CLOUD_OUTSCATTER_FACTOR`、`CLOUD_QUALITY`、`CLOUD_RAIN_ALTITUDE`、`CLOUD_RAIN_COVERY`、`CLOUD_RAIN_DENSITY`、`CLOUD_RAIN_SCALE`、`CLOUD_RAIN_SKYLIGHTING`、`CLOUD_RAIN_SUNLIGHTING`、`CLOUD_RAIN_THICKNESS`、`CLOUD_SHADOW`、`CLOUD_SHADOWTEX_SIZE`、`CLOUD_SHADOW_FADE`、`CLOUD_SHADOW_RANGE`、`CLOUD_SPEED`、`PLANAR_ALTITUDE`、`PLANAR_COVERAGE`、`PLANAR_NOISE_SCALE`、`PLANAR_CLOUDS`、`RAIN_SHADOW`、`VOLUMETRIC_CLOUDS`
- `effects/color/color.glsl`（21）：`ABNEY_EFFECT_CORRECTION`、`ADVANCED_COLOR`、`AE_CURVE`、`AE_MODE`、`AE_OFFSET`、`AGX_EV`、`EV_VALUE`、`EXPOSURE_TIME`、`GAMMA`、`LUMA_GAMMA`、`LUMINANCE_WEIGHT_MODE`、`LUMINANCE_WEIGHT_STRENGTH`、`MANUAL_EXPOSURE`、`PURKINJE_EFFECT`、`PURKINJE_EFFECT_STRENGTH`、`PURKINJE_EFFECT_THRESHOLD`、`SATURATION`、`SEREEN_RATIO`、`SMOOTH_EXPOSURE`、`TONEMAP_OPERATOR`、`WHITE_CLIP`
- `effects/world/end.glsl`（5）：`ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE`、`ACCRETIONDISC_DOPPLER_EFFECT`、`END_MANUAL_PLANET_ANGLE`、`END_MANUAL_PLANET_CYCLE`、`END_PLANET_CYCLE`
- `effects/entity/entity.glsl`（4）：`ENTITIES_STATUS_COLOR`、`EYES_LIGHTING`、`HAND_FOV`、`HAND_FOV_MODE`
- `effects/fog/fog.glsl`（28）：`DH_LIMIT_VFOG_DIST`、`INDOOR_FOG`、`LANDSCATTERING`、`LANDSCATTERING_REFLECTION`、`LANDSCATTERING_REFRACTION`、`LANDSCATTERING_SHADOW`、`LANDSCATTERING_SHADOW_QUALITY`、`LANDSCATTERING_STRENGTH`、`NETHER_FOG_DENSITY`、`UNDERWATER_VFOG`、`UNDERWATER_VFOG_DENSITY`、`VFOG`、`VFOG_CLOUD_SHADOW`、`VFOG_DENSITY`、`VFOG_DENSITY_BASE`、`VFOG_FALLOFF`、`VFOG_FOG_DENSITY`、`VFOG_HEIGHT`、`VFOG_HEIGHT_2`、`VFOG_IGNORE_WORLDTIME`、`VFOG_NOISE_TYPE`、`VFOG_QUALITY`、`VFOG_REFLECTION`、`VFOG_REFRACTION`、`VFOG_STAINED`、`VFOG_SUNLIGHT_ABSORPTION`、`VFOG_SUNLIGHT_DENSITY`、`VFOG_VOLUMETRIC_LIGHTING`
- `effects/lens/lens.glsl`（25）：`CAMERA_FOCAL_POINT`、`CAMERA_FOCUS_MODE`、`DOF`、`DOF_BLUR`、`DOF_CATSEYE`、`DOF_CATSEYE_MIDPOINT`、`DOF_CATSEYE_STRENGTH`、`DOF_COCSPREAD_QUALITY`、`DOF_DEPTH_SMMOOTH_HALFLIFE`、`DOF_FOCUS_IGNORE_HAND_PARTICLE`、`DOF_MAX_COC`、`DOF_QUALITY`、`FLARE_BRIGHTNESS`、`GLARE_BRIGHTNESS`、`GLARE_FLARE_SHADOWBASED`、`LENS_FLARE`、`LENS_GLARE`、`MOTION_BLUR`、`MOTION_BLUR_DITHER`、`MOTION_BLUR_QUALITY`、`MOTION_BLUR_SUTTER_ANGLE`、`SNEAKING_VIGNETTE`、`VIGNETTE`、`VIGNETTE_FALLOFF`、`VIGNETTE_ROUNDNESS`
- `effects/ground/material.glsl`（30）：`ANISOTROPIC_FILTERING_NORMAL_SPECULAR`、`ANISOTROPIC_FILTERING_QUALITY`、`DISABLE_HAND_SPECULAR`、`DISABLE_PLAYER_SPECULAR`、`EMISSIVENESS_GAMMA`、`ENABLE_PBR`、`ENTITIES_NORMAL_CLAMP`、`ENTITIES_PARALLAX`、`ENTITIES_TEXTURE_RESOLUTION`、`ENTITIES_VS_TBN`、`GENERAL_GRASS_FIX`、`HAND_NORMAL_CLAMP`、`PARALLAX_BASED_NORMAL`、`PARALLAX_DEPTH`、`PARALLAX_FADE`、`PARALLAX_MAX_REFINEMENTS`（第九点二移入，`dev.156`）、`PARALLAX_MODE`、`PARALLAX_QUALITY`、`PARALLAX_SHADOW`、`PARALLAX_SHADOW_QUALITY`、`POROSITY_ABSORPTION`、`ROUGHNESS_CLAMP`、`SSS_STRENGTH`、`SSS_STRENGTH_OFFSET`、`TERRAIN_NORMAL_CLAMP`、`TERRAIN_VS_TBN`、`TEXTURE_DEFAULT_POROSITY`、`TEXTURE_PBR_FORMAT`、`TEXTURE_PBR_POROSITY`、`TEXTURE_RESOLUTION`
- `effects/world/nether.glsl`（1）：`NETHER_BRIGHTNESS`
- `effects/reflection/reflection.glsl`（4）：`RAYTRACE_QUALITY`、`RAYTRACE_REFINEMENT_STEPS`、`RAYTRACE_ZDIFF_THRESHOLD`、`DH_SSR`（Eclipse 来源，`dev.138`）
- `effects/ground/selection.glsl`（4）：`LINE_IMAGE_OUTPUT`、`SELECTION_BOX_COLOR_B`、`SELECTION_BOX_COLOR_G`、`SELECTION_BOX_COLOR_R`
- `effects/shadow/shadow.glsl`（17）：`COLORED_SHADOWS`、`DH_SHADOW`、`DH_SHADOW_CULLING`、`DH_SHADOW_FIX`、`DH_SSS`（Eclipse 来源，`dev.138`）、`DISABLE_PLAYER_SCREEN_SPACE_SHADOWS`、`SCREEN_SPACE_SHADOWS`、`SHADOW_BASIC_BLUR`、`SHADOW_MAP_BIAS`、`SSS_BRIGHTNESS`、`SSS_NORMAL`、`SSS_QUALITY`、`VARIABLE_PENUMBRA_SHADOWS`、`VPS_QUALITY`、`VPS_SPREAD`、`shadowDistance`、`shadowMapResolution`
- `effects/sky/sky.glsl`（11）：`ATMO_HORIZON`、`ATMO_REFLECTION_HORIZON`、`BILINEAR_MOON_TEXTURE`、`BILINEAR_SKYBOX_TEXTURE`、`MOON_TEXTURE`、`NIGHT_BRIGHTNESS`、`SKYBOX_TEXTURE`、`SKY_IMAGE_RESOLUTION`、`SKY_TEXTURE_BRIGHTNESS`、`STAR_TYPE`、`sunPathRotation`
- `effects/lighting/sunlight.glsl`（6）：`CAVE_MODE`、`COLD_MOONLIGHT`、`NOLIGHT_BRIGHTNESS`、`SKYLIGHT_INTENSITY`、`SUNLIGHT_INTENSITY`、`SUNLIGHT_LEAK_FIX`
- `effects/clarity/upscale.glsl`（5）：`CAS_DENOISE`、`CAS_SHARPNESS`、`FSR`、`FSR_DENOISE`、`FSR_SHARPNESS`
- `effects/ground/vegetation.glsl`（2）：`SHADOW_WAVING_PLANTS`、`WAVING_PLANTS`
- `effects/water/water.glsl`（6）：`CAUSTICS`、`UNDERWATER_FOG`、`WATER_FOG_DENSITY`、`WATER_PARALLAX`、`WAVE_HEIGHT`、`WAVE_SCALE`
- `effects/weather/weather.glsl`（9）：`DISABLE_LOCAL_PRECIPITATION`、`RAIN_DISTURBANCE`、`RAIN_SPLASH_EFFECT`、`RAIN_VISIBILITY`、`RAIN_WIND_X`、`RAIN_WIND_Z`、`SURFACE_WETNESS`、`drynessHalflife`、`wetnessHalflife`
- `effects/world/world.glsl`（4）：`DH_TERRAIN_CULLING`、`DH_TEXTURE_NOISE`、`DH_TEXTURE_NOISE_STEPS`、`DH_TEXTURE_NOISE_STRENGTH`

## 九点二、内部常数归属

`Settings.glsl` 里不进菜单的常数也只定义一次，名字保持原名：

- `common/math.glsl`：`MAIN_OUTPUT_FACTOR`、`EXPOSURE_OUTPUT_FACTOR`、`ANIMATION_SPEED`、`WATER_REFRACT_IOR`、`CAUSTICS_TEX_RESOLUTION`。
- `effects/ground/material.glsl`：全部 `MATID_*`、`CORRECT_PARTICLE_NORMAL`（原来误列在此的 `PARALLAX_MAX_REFINEMENTS` 已按第 25 条恢复为玩家选项，见第九节）。
- `effects/sky/sky.glsl`：`ATMO_MIN_ALTITUDE`、`ATMO_SKYBOX_MIN_ALTITUDE`。
- `effects/fog/fog.glsl`：`VFOG_SUNLIGHT_STEPS`、`VFOG_SUNLIGHT_STEPLENGTH`。
- `effects/clarity/antialiasing.glsl`：`TAA_BICUBIC_PREVIOUS`、`TAA_DEPTH_COMPARE`、`TAA_MICRO_BLUR`（原来误列在此的 `TAA_DEPTH_COMPARE_THRESHOLD` 已按第 25 条恢复为玩家选项，见第九节）。
- `effects/color/color.glsl`：`AE_CLAMP`。

效果文件用到别的文件的选项或常数时，不重复定义；由绘制主体先引入归属文件。

## 九点五、同名函数
iterationT 有些函数在多个文件各写一份。合进 Omni 后同一个程序可能同时引入两份，必须先处理：

- `BicubicBlurTexture`（泛光、云影、阴影顶点、地形顶点）、`BicubicTexture`（两种时间抗锯齿）：内容相同则放进 `common/math.glsl` 一份；不同则各自留在归属效果文件并加后缀区分。由甲片比对并决定，结果写进下面偏离记录。
- `ShadowScreenPos_From_WorldPos*`、`DistortShadowScreenPos`：主世界版与末地版（`ShadowTransformsEnd.glsl`）都放 `effects/shadow/shadow.glsl`，末地版用 `#ifdef OMNI_END` 选择。
- 植物摆动常数 `heavy*`、`light*`、`speed*`：只在 `effects/ground/vegetation.glsl` 定义一次，地形与阴影顶点共用。
- 时间抗锯齿辅助函数（`clipAABB`、`RGB_To_YCoCg`、`SampleDepthFetch` 等）：主世界与下界版放 `effects/clarity/antialiasing.glsl`，用 `#ifdef OMNI_NETHER` 选择不同的部分。
- `CalculateCameraVelocity`：放 `common/coordinates.glsl` 一份；各处实现不同时加后缀。
- `AxialGaussianBlur`：泛光版留在 `effects/color/bloom.glsl`，云影模糊版改名 `CloudShadowAxialBlur` 放 `effects/cloud/shadow.glsl`。
- `Calculate3DNoise`、`CalculateStars`：末地版加 `End` 前缀并拆到 `effects/world/end_disc.glsl`、`effects/world/end_sky.glsl`；主世界版分别在 `effects/fog/volumetric.glsl`、`effects/sky/stars.glsl`。（2026-10-18：末地星空改用 Eclipse 星场，`EndCalculateStars` 只转发主世界 `CalculateStars`，见偏离记录 49；`Calculate3DNoise` 仍按下述加 `End` 前缀。）
- `NetherFog`、`ComputeFakeSkyReflection`、`RefractSampleOnce`、`TransparentAbsorption`：维度各自实现不同时，下界与末地版加 `Nether`、`End` 后缀，由己片负责。

## 十、分片与状态

移植先在本地分支 `itt-port` 分片完成，管线是整体替换，中间状态无法单独通过构建；各片通过集成检查后于 2026-10-17 以合并提交 `c23eb0a` 合入 `main` 推送。子任务不提交，由主助手统一提交。

| 分片 | 负责文件 | 状态 |
| --- | --- | --- |
| 甲 地基 | `build.py`、`options.py`、`rendering/programs.json`、`rendering/pipeline.properties`、`rendering/buffers.glsl`、`common/*`、`shaders/texture/`、`*.properties`、工具测试 | 完成（占位主体可编译，`python build.py verify` 通过） |
| 乙 几何阶段 | `rendering/terrain.glsl`、`rendering/entities.glsl`、`rendering/translucent.glsl`、`rendering/overlay.glsl`、`rendering/celestial.glsl`、`rendering/shadow.glsl`、`rendering/distant.glsl`；`effects/ground/material.glsl`、`effects/shadow/shadow.glsl`、`effects/water/water.glsl`、`effects/ground/vegetation.glsl`、`effects/weather/weather.glsl`、`effects/entity/entity.glsl`、`effects/world/world.glsl`、`effects/ground/selection.glsl`、`effects/weather/season.glsl` | 完成（离线编译通过；待实机核对） |
| 丙 延迟阶段 | `rendering/deferred.glsl`、`rendering/lights.glsl`；`effects/sky/sky.glsl` 及同目录子文件、`effects/sky/atmosphere.glsl`、`effects/cloud/cloud.glsl` 及同目录子文件、`effects/lighting/ambient.glsl`、`effects/lighting/sunlight.glsl` | 完成（离线编译通过；待实机核对） |
| 丁 合成阶段 | `rendering/composite.glsl`；`effects/lighting/blocklight.glsl`、`effects/reflection/reflection.glsl`、`effects/fog/fog.glsl`、`effects/lighting/lpv.glsl` 与 `rendering/lpv.glsl` | 完成（离线编译通过；待实机核对） |
| 戊 后期 | `rendering/post.glsl`、`rendering/final.glsl`；`effects/lens/lens.glsl`、`effects/clarity/antialiasing.glsl`、`effects/color/bloom.glsl`、`effects/color/color.glsl`、`effects/clarity/upscale.glsl`、`effects/dev/debug.glsl` | 完成（离线编译通过；待实机核对） |
| 己 下界与末地 | 维度程序、`effects/world/nether.glsl`、`effects/world/end.glsl`、下界时间抗锯齿 | 完成（离线编译通过；待实机核对） |
| 庚 集成 | 选项改名登记、预设、测试、文档、离线检查、游戏内对照截图 | 进行中：文档已按 `main` 实际重写并更新偏离记录（2026-10-17 首次，此后随每个小步同步，最近一次 2026-10-18 对齐 `0.0.0-dev.160`）；游戏内对照截图仍未做 |


### 覆盖核对（2026-10-16 首次，2026-10-17 更新，2026-10-18 对齐 `dev.160`）

2026-10-17 更新：选项数、入口数与测试数以 `python build.py verify` 实测为准（该命令不输出函数数，函数数沿用下方首次核对的方法重抽，见对应条目）；合并 Eclipse 能力后新增的文件已按实际登记。

核对方法：
- 选项：把 `references/iterationT/shaders/Lib/Settings.glsl` 与 `lang/*.lang` 里的宏与菜单项，和项目 `options.scan` 的结果逐名对照（iterationT 名加 `OMNI_` 前缀，拼写修正见第九节，下界末地原生常量保留原名）。
- 函数：用 `references/iterationT/shaders` 全部 `.glsl/.fsh/.vsh/.gsh` 抽取函数定义，与 `shaders/` 对照函数名。
- 函数体：按函数名配对后做词序列比对；GLSL 的 `#if` 分支会出现“一支开括号、另一支闭括号”，自动比对会把函数体读超，所以相似度低的函数逐个手工比对。

核对结果：
- 选项：iterationT 有效选项全部保留；项目当前 519 个选项（含项目自己的额外功能与 Eclipse 合并批次），`python build.py verify` 实测。没有“定义了却没有接入任何入口”的选项。
- 函数：iterationT 侧 245 个具名函数、项目侧 312 个（2026-10-16 独立审查按唯一函数名重测，不含 `main`，方法见 `.dev/reports/itt-parity-audit.md`；`python build.py verify` 不输出函数数）。本轮合并 Eclipse 能力后项目侧文件增加（新增 `effects/` 下 `ground/grass.glsl`、`world/biome.glsl`、`world/planet.glsl`、`world/distant.glsl`、`weather/storm.glsl`、`weather/dailyweather.glsl`、`color/colorgrade.glsl`、`lens/distortion.glsl`、`lens/hurt.glsl`、`sky/suncolor.glsl`、`clarity/grain.glsl`、`clarity/chunkfade.glsl`、`water/playerwater.glsl`、`water/puddle.glsl` 等），按本轮一致规则重抽得到 369 个唯一函数名（iterationT 同法 233 个，抽取规则不同，与旧值不可直接相减）。缺失与处理：行为性缺失现已为零——原唯一的 `MotionBlur.glsl` 的 `title` 已在 `dev.126` 移植（第十二节偏离记录第 37 条）；`BlueNoiseTemproal`、`BayerTemproal` 按合同改名，`CalculateCameraVelocity` 按用途拆成三份，`WaterRefractionLite` 改名 `RefractSampleOnce`；另有若干在 Omni 引用树内无调用的 iterationT 函数（`minVec3`、`maxVec3`、`remap`、`bayer16`、`bayer32`、`bayer128`、`Sequences_R1`、`Sequences_R2`、`ScreenPos_From_ViewPos_DH` 等）按 HOP 作死代码删除，不影响默认画面。
- 函数体：手工核对的可疑项均一致——`ScreenSpaceTracer` 与 iterationT 逐词相同（665 词）；4 个 `ShadowScreenPos_*`/`DistortShadowScreenPos` 与 `BloomDownSample`/`AxialGaussianBlur`/`FidelityFX_FSR1` 只差已登记的重名改名与选项前缀；`BlueNoise` 只差 `OMNI_PIXEL` 宏（见第十二节第 14 条）。
- 结构：`shaders/effects/` 按菜单页面分文件夹（`sky/`、`cloud/`、`fog/`、`water/`、`ground/`、`lighting/`、`shadow/`、`reflection/`、`color/`、`lens/`、`clarity/`、`weather/`、`entity/`、`world/`、`dev/`）；`rendering/` 只安排绘制顺序；`effects/`、`rendering/`、`common/` 每个文件都有中文文件头；`python build.py audit` 通过。
- 编译：`python build.py compile` 用两种代表配置与基础、开远景两组环境编全部 269 个入口，打印 280 组唯一程序（两种代表配置各计一遍），0 错误。

## 十一、验证方式

1. `python build.py verify` 通过（十秒预算不变）。
2. 游戏内对照：同一位置、同一时间、同一天气，分别加载 iterationT 与 Omni 截图，逐项比较天空、阴影、水、雾、云、曝光与色调。
3. 偏离 iterationT 的地方必须写进下面的偏离记录，不能当成已复刻。

## 十三、给子任务的工作方式

每个子任务开工前先读：HOP 技能（`C:\Users\17137\.config\opencode\skills\hop\SKILL.md`）、`AGENTS.md`、本文件全文。

- 只改分片表里分给你的文件，别的文件一个字不动。
- 数学、常数、分支、采样、顺序照 iterationT 原程序逐行对照写；函数名、结构体名、全局量、输入输出变量名保持原名（只修 `Temproal` → `Temporal`、`Soild` → `Solid` 这类拼写）。
- 每个文件按第八节规则写：文件头讲清职责、调用位置、可复制示例、关键取舍；用 `#ifndef OMNI_<文件名>_INCLUDED` 守卫；选项用 `// @option` 加 `#define OMNI_X`（或合同允许的原生常量）；至少一半非空行有中文说明，英文术语放反引号。
- 绘制主体按第九节“地基接口”的引入顺序写；效果文件用 `#include "/common/..."` 与 `#include "/effects/..."` 引依赖，不写 `#version`。
- 每个效果文件的函数调用前要确认依赖它的全局量已由调用方声明（例如 `texelCoord`、`colorShadowlight`），在文件头写清调用前提。
- 验证只用 `python build.py audit`（检查中文说明比例与格式）。**不要**运行 `python build.py verify`、`check`、`generate`、`build`：其它分片还没写完，编译必然失败，那不是你的错误。
- 不要 `git commit`、`git add`、`git push`、切分支。
- 回报只写：改了哪些文件、每个文件对照的 iterationT 来源、用到的选项与内部常数、没做或存疑的地方。不要贴大段代码。

## 十二、偏离记录

1. 选项名加 `OMNI_` 前缀：iterationT 的选项名统一加前缀（如 `BLOOM` → `OMNI_BLOOM`），少量拼写修正见第九节。这是项目命名约定，值和默认值照 iterationT。
2. `BicubicBlurTexture`、`BicubicTexture`：原程序在多个文件各写一份，内容相同，合并进 `common/math.glsl` 一份；泛光版与云影版参数和返回类型不同（分别是 `vec3`/`vec4` 与不同纹理），按第九点五节留在各自效果文件。
3. `CalculateCameraVelocity`：原程序四处实现不同，按合同留在各自效果文件，各片自行处理。
4. `shaders.properties` 笔误：iterationT 原文 `program.world-1/program.composite9.enabled` 重复写了 `program.`，本移植修正为 `program.world-1/composite9.enabled`。
5. 大贴图压缩：`build.py` 打包时对 `.png`、`.bin` 用 `ZIP_STORED` 直接存放，九级压缩几十兆贴图要好几秒且几乎没有收益，会突破十秒检查预算。
6. `block.properties`、`entity.properties`、`item.properties` 与生成的 `shaders.properties` 加入审计的机器文件豁免：它们是逐行可对照的编号数据，不写中文说明。
7. 移植期开关（已删除）：移植期 `build.py` 有 `PORTING` 开关，让编译失败一次显示最多 400 条错误；现已删除，固定只报前五条（`build.py:549`）。选项接线始终是全树硬检查 `check_option_wiring`（`build.py:259`），发现未接线直接报错。
8. 旧管线测试跳过（已解决）：早期 `tests/` 里断言旧管线算法与缓冲的测试曾用 `@unittest.skip(PORT_REPLACED)` 标记；现已按新管线全部重写，`verify` 实跑 120 个测试、0 跳过。
9. 旧算法专用选项的处置（由主助手统一裁决，分片只登记不擅自删除）：iterationT 用预计算大气贴图，旧 Omni 那种“实时积分步数/散射倍率”参数在新算法里没有对应含义。这类选项一律登记到本节清单，由主助手在庚片决定“并入同名迭代T选项 / 保留为中性额外功能 / 作为接口变更移除并写迁移说明”，不在分片里悄悄删除。
10. 强光压缩选项表示（戊片）：iterationT `TONEMAP_OPERATOR` 是函数名取值的宏（`AgX`/`ACES`/`None`），而 `options.py` 只接受数字取值，所以 Omni 把它定义为序号 `0`/`1`/`2`，档位名称映射回 `AgX`/`ACES`/无，绘制主体用 `#if OMNI_TONEMAP_OPERATOR == 1` 分派。行为和默认值（`AgX`）与原程序一致，只改表示形式。
11. `CalculateWaterCaustics` 同名不同实现（丁片）：iterationT 有两份同名函数，`Lib/BasicFounctions/Sunlight_Shadow.glsl` 的一份按九次采样算焦散遮罩，`Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl` 的一份只返回 `dist * 2.8 + 0.2`，两者内容不同。前者已在 `effects/shadow/shadow.glsl`，按第九点五节的处理方式把后者改名 `CalculateUnderwaterCaustics` 留在 `effects/fog/underwater_fog.glsl`，函数体不变；水下体积雾同时复用 `effects/shadow/shadow.glsl` 里内容相同的 `GetWavesNormalFromTex`，不重复定义。
12. `LANDSCATTERING_DISTANCE` 选项补记（丁片）：第九节 `effects/fog/fog.glsl` 的选项清单漏了这个名字，但 iterationT `Settings.glsl` 它有菜单范围且被 `LandAtmosphericScattering` 使用，所以按 `OMNI_LANDSCATTERING_DISTANCE` 正式登记，默认值与可选范围照 iterationT。
13. 效果文件被多个程序共同引入，靠“只有某个程序引入它”区分阶段的做法不再成立。凡是依赖程序全局量（光色、光方向、像素坐标）的函数，改成参数传入或就地计算：`CalculateStars(+sunVector)`、`CloudShadowFromTex(+shadowLightVector)`、`WaterFog(+shadowVector, +colorShadowlight, +colorSkylight)`、`Rain(+colorShadowlight, +colorSkylight)`、`RefractSampleOnce(+screenCoordInput)`、`GetWavesNormalFromTex`/`CalculateWaterCaustics(+shadowLightVector)`、`ScreenSpaceShadow(+shadowVector)`、`DH_noise(+materialID)`。这样任何程序在任意阶段引入都能编译，行为不变。
14. `common/noise.glsl` 用 `OMNI_PIXEL` 宏取像素坐标：片元阶段是 `gl_FragCoord.xy`，顶点、几何与计算阶段取零。三个噪声函数因此在各阶段都能编译；顶点阶段本来不调用它们，输出不变。
15. `effects/clarity/antialiasing.glsl` 自带 `taaTexelCoord`/`taaTexCoord`，并把整份实现放进 `#ifdef OMNI_FRAGMENT`，不再依赖调用程序声明的同名全局量。
16. `BicubicBlurTexture` 在三处实现不同，必须改名：`common/math.glsl` 保留原名（噪声贴图十六像素三次模糊），泛光版改名 `BloomBicubicBlurTexture`，云影版改名 `CloudBicubicBlurTexture`，平面云内部另有 `BicubicBlurNoise`。GLSL 不允许同名函数只靠返回类型区分。
17. `effects/shadow/shadow.glsl` 的可变半影阴影段用 `OMNI_SHADOW_COMPARE` 隔开：只有合成零号把 `shadowtex1` 声明为 `sampler2DShadow` 并定义该宏，其它程序把 `shadowtex1` 当普通深度贴图用。
18. `rendering/lights.glsl` 只声明 `shadowtex0`，不声明 `shadowtex1` 与 `shadowcolor0`：顶点与片元对同名采样器要求类型一致，合成零号片元用的是比较采样器。
19. 加载器标准环境宏在 `build.py` 里按 Iris `StandardMacros` 注入（`MC_VERSION`、`MC_HAND_DEPTH = 0.125`、`MC_RENDER_QUALITY`、厂商与系统宏、远景方块编号照 Iris 取值）。离线的「高效果」环境另补 `IRIS_FEATURE_CUSTOM_IMAGES` 与 `IRIS_FEATURE_COMPUTE_SHADERS`，让光传播体积与波浪模拟那几条只在显卡能力存在时才有的代码路径真的进入编译。离线编译没有这些宏会把只在游戏里存在的名字当成未声明标识符。
20. `verify` 的十秒预算装不下整包编译（展开引用树与编译数百程序需要一两分钟），所以 `verify` 与 `check` 只编一小组探针（主世界 5 个轻量程序 `gbuffers_terrain`、`shadow`、`final`、`setup`、`shadowcomp` 编默认配置与基础环境，其中 `gbuffers_terrain`、`shadow`、`setup`、`shadowcomp` 另编全高配置与开远景环境，共 9 组唯一程序，约 7 秒）。完整离线编译改用 `python build.py compile`（放宽到 300 秒，全部程序 × 两种代表配置 × 基础与开远景两组环境，约两分钟）。测试已全部按新管线重写，`verify` 实跑 120 个、0 跳过。
21. 修正 iterationT 的范围笔误：`CAMERA_FOCAL_POINT` 重复的 `15.0`、`CLOUD_BASE_NOISE_SCALE` 重复值；加载器要求 `const` 向量构造给足分量，个别 `vec3(0.0)` 之类已补齐。
22. `sunPathRotation`、`wetnessHalflife`、`drynessHalflife` 三个加载器原生常量加入 `options.py` 的 `CONST_OPTIONS` 白名单。
23. 预设按新选项集重写四套（默认、氛围、轻量、真实），保持各自定位。
24. 下界与末地绘制主体已按 iterationT 的 `world-1/`、`world1/` 目录补齐（己片）：
    - 新文件 `effects/world/nether.glsl`（对应 `Lib/BasicFounctions/NetherColor.glsl`）与 `effects/world/end.glsl`（对应 `Lib/IndividualFounctions/EndSky.glsl`）。
      第七节对照表按实际子目录写成 `effects/world/nether.glsl`、`effects/world/end.glsl`（菜单页面 `world`），功能与归属不变。
    - 末地同名函数按第九点五节加 `End` 前缀：`CalculateStars` → `EndCalculateStars`、`Calculate3DNoise` → `EndCalculate3DNoise`；
      `ComputeFakeSkyReflection` 末地版为 `ComputeFakeSkyReflectionEnd`，下界/末地的 `RefractSampleOnce`、`TransparentAbsorption` 分别加 `Nether`、`End` 后缀，
      下界 `NetherFog` 有 `vec2`（合成二号）与 `float`（合成五号）两个重载。末地 `CalculateStars` 的第二参数与主世界版不同，靠 `End` 前缀与主世界版共存。
      （2026-10-18 小步更新：末地星空改用 Eclipse 星场，`EndCalculateStars` 只转发主世界 `CalculateStars`，不再自带第二参数，见偏离记录 49。）
    - 下界时间抗锯齿照 `TAA_Nether.glsl` 移进 `effects/clarity/antialiasing.glsl` 的 `OMNI_NETHER` 分支（参考深度打包进七号画面透明度通道），
      `rendering/post.glsl` 的合成七号在下界改用四参数版 `TemporalReprojection` 并自行打包写回。
    - 延迟程序按维度重排：下界与末地的延迟零号是复制程序（`world-1/deferred.fsh`、`world1/deferred.fsh`），
      末地把全局光时间滤波放在延迟二号、空间滤波放在延迟四号（`world1/deferred2.fsh`、`world1/deferred4.fsh`）。
      因此 `effects/lighting/ambient.glsl` 的两段编译条件同时认末地对应的程序宏，并在 `OMNI_END` 下不再被延迟一号/二号触发。
    - 下界与末地的合成五号原程序只写一号画面，不画镜头光斑，`rendering/composite.glsl` 的这两个分支因此不声明三号输出。
25. 主世界缺口补齐（主世界片）：`DEBUG_COUNTER`、`SODIUM_TEMPFIX` 在 iterationT 3.2.0 只在 `Lib/Settings.glsl` 出现且没有任何计算引用（属于菜单装饰），按 HOP “不做不起作用的假开关”不移植。同批把 iterationT 里带范围滑块、此前被误当内部常数的三个量恢复为玩家选项：`FTC_OFFSET`→`OMNI_FTC_OFFSET`（归属从 `common/math.glsl` 移到 `effects/cloud/cloud.glsl`）、`PARALLAX_MAX_REFINEMENTS`→`OMNI_PARALLAX_MAX_REFINEMENTS`、`TAA_DEPTH_COMPARE_THRESHOLD`→`OMNI_TAA_DEPTH_COMPARE_THRESHOLD`；`TAA_CLOSEST_DEPTH` 仍作内部开关保持原名；`WHITE_DEBUG_WORLD`、`DISABLE_NIGHTVISION`、`DISABLE_BLINDNESS_DARKNESS` 移植为 `OMNI_` 前缀的开发者（`dev`）选项。第九节选项清单与九点二内部常数清单需由主助手登记这四处新增/移动。（2026-10-18：`PARALLAX_MAX_REFINEMENTS`、`TAA_DEPTH_COMPARE_THRESHOLD` 已移入第九节选项清单，不再列在九点二内部常数。）（后续小步做命名统一：`OMNI_FTC_OFFSET` 改名为 `OMNI_CLOUD_TIME_OFFSET`，`OMNI_PC_COVERAGE`、`OMNI_PC_NOISE_SCALE`、`OMNI_PC_ALTITUDE` 统一为 `OMNI_PLANAR_*`；旧名到新名的迁移登记在 `config.py` 的 `OPTION_RENAMES`，老配置不丢设置。视差算法同时从 `effects/ground/material.glsl` 拆到 `effects/ground/parallax.glsl`，选项仍留在材质文件。）
26. 末地屏幕空间阴影方向修正：`rendering/composite.glsl` 合成零号的末地分支原来把**世界空间** `worldShadowVector` 传给 `ScreenSpaceShadow`，与原程序不符。`ScreenSpaceShadow` 内部把传入方向当视空间射线方向并与视空间法线点乘（原程序读全局 `shadowVector`），这是偏离记录第 13 条把依赖全局量的函数改成参数传入时产生的一处调用错误。已改为传视空间 `shadowVector`，与主世界分支及原程序一致。
27. 按维度覆盖的画面格式与阴影常量（**存疑，未按维度生效**）：`colortex7Format`、`colortex8Format`、`ambientOcclusionLevel`、`shadowDistanceRenderMul`、`shadowHardwareFiltering1`、`shadowtex0Mipmap` 在 `rendering/buffers.glsl` 加了 `#if defined OMNI_NETHER`/`#elif defined OMNI_END` 分支，值逐项照 iterationT `composite.fsh`、`world-1/composite.fsh`、`world1/composite.fsh` 文件头。**但** Iris 的指令解析器（`ConstDirectiveParser`）逐行读取已展开引用的文本、不评估 `#if`，同名常量只保留文本里最后出现的一条，所以这些分支在 Iris 下不会按维度生效，运行时取 `#else`（主世界）的值。要真正逐维度生效须把声明移进各维度各自的入口文件，属结构性改动，留给主助手裁决（该结构性问题已按第 35 条拆成逐维度入口声明）。其余维度未点名的常量（`shadowIntervalSize`、`shadowtex0Nearest` 等）照主世界值，未逐项核对下界末地默认值，标未确认。
28. 泛光链下界/末地恒开（行为差异，不是笔误）：原程序 `program.world-1/program.composite9.enabled` 等多写了一个 `program.`，加载器当成无效程序名忽略，实际效果是下界与末地泛光链恒开、不受 `BLOOM` 控制。原移植把它“修正”成受 `OMNI_BLOOM` 控制，改变了行为；现按原程序实际行为去掉这两组门控键，恢复恒开。是否真正叠加仍由合成十四号的 `OMNI_BLOOM` 决定，所以默认画面不变，只影响那几遍是否执行。
29. `DRAWBUFFERS` 写法核对（共享文件无法按维度写附件指令）：三处逐一核对，均为等价，未改。`shadow`（`rendering/shadow.glsl`）本就没有附件指令，文件头里提到的一处只是文字（加载器要求 `DRAWBUFFERS` 紧跟 `/*`，此处不满足），与原程序一致；下界末地 `composite5` 沿用主世界的 `DRAWBUFFERS:13`，但其分支只声明零号输出，多出的一号不会被写，与 iterationT 的 `DRAWBUFFERS:1` 等价；下界 `composite`（合成零号）沿用主世界的 `DRAWBUFFERS:1`，iterationT 写 `DRAWBUFFERS:17` 但 `main` 从不写 `compositeOutput7`，两者都只写一号，等价。受第 27 条的 `#if` 限制，附件指令无法按维度变化，故保持现有写法（未实机验证）。
30. `version.*` 与 `program.world-1/deferred1`：`shaders.properties` 的 26 条 `version.*` 旧版本程序后缀映射已原样补进 `rendering/pipeline.properties`（Iris 不解析这类键、且没有带后缀的版本文件，故不影响；注释已写清）。`program.world-1/deferred1.enabled` 是原程序给“不存在的下界 deferred1 程序”写的一条无效键，Omni 下界同样没有该程序，按 HOP 不移植无效键，已在 `pipeline.properties` 与本节写清。
31. 接口差异登记（默认不影响画面）：`END_MANUAL_PLANET_ANGLE` 档位已从 46 档恢复为原程序的 360 档（`0.0`–`359.0`）；`FLASHLIGHT_POS_L_Y`/`FLASHLIGHT_POS_R_Y` 因 `options.py` 拒绝范围重复值，无法复原原程序里重复两次的 `-1.0`（37 项），保留去重后的 36 项，默认值与画面不变；`RAYTRACE_QUALITY`、`RAYTRACE_ZDIFF_THRESHOLD`、`RAYTRACE_REFINEMENT_STEPS` 仍作 `effects/reflection/reflection.glsl` 的内部常数。核实：原程序这三项带 `// [...]` 取值注释，OptiFine 会把它显示成可循环的选项，但 `RAYTRACE_REFINEMENT_STEPS` 的范围注释缺右括号、本就不完整，且 Omni 的选项扫描只登记带 `@option` 的声明；是否提升为玩家选项属对外接口变更，留给主助手裁决（已按第 36 条提升为玩家选项）。
32. `RefractSampleOnce` 像素坐标改参数传入：原移植用 `ivec2(screenCoordInput * screenSize)` 反推像素坐标，渲染缩放或放大链下与 `texelCoord` 口径可能不同、差一个像素；现改为由调用方把整数像素坐标 `texelCoord` 作为参数传入，与原程序读全局 `texelCoord` 等价，消除缩放下的偏差。
33. Omni 额外功能默认中性：`OMNI_LIGHTNING` 改为默认关闭（原程序不使用 `lightningBoltPosition`，默认开会让雷暴闪电时多一层冷色闪光）；`OMNI_DEBUG_VIEW`（0 关、1 几何法线、2 深度、3 光照图）与 `OMNI_PROFILER` 已真正接到 `rendering/final.glsl` 的最终输出，默认关闭时画面与 iterationT 一致（此前它们定义了却没有调用点，是死开关）。
34. 末地 `deferred4` 门控修正：原移植在 `pipeline.properties` 错误地添加了 `program.world1/deferred4.enabled=OMNI_CLOUD_SHADOW`，而 iterationT 的末地 `deferred4` 是全局光空间滤波、且原程序没有这条键（无条件执行）。现删除该键，让末地延迟四号无条件运行，与 iterationT 一致。

35. 逐维度缓冲声明改为按维度入口生效（结构性改动）：原来全部画面格式、清除与阴影常量写在 `rendering/buffers.glsl`，用 `#if defined OMNI_NETHER`/`#elif OMNI_END` 分维度；但该文件没有被任何入口引用，且加载器只从每个程序展开后的片元源码读取 `const` 指令，所以这些声明从未真正生效。现拆成两层：共享部分留在 `rendering/buffers.glsl`（三维度相同的格式零到六、清除、清除色、噪声与三维度相同的阴影常量）；只在某个维度不同的六项放进 `rendering/buffers_main.glsl`、`rendering/buffers_nether.glsl`、`rendering/buffers_end.glsl`，值逐项照 iterationT 三份 `composite` 文件头。六项是 `colortex7Format`、`colortex8Format`、`shadowDistanceRenderMul`、`shadowHardwareFiltering1`、`shadowtex0Mipmap`、`ambientOcclusionLevel`。`build.py` 的 `program_files()` 读取 `rendering/programs.json` 每个维度新增的 `buffers` 字段，在每个维度生成的入口里、引入绘制主体之前引入本维度那份声明文件；`generate()` 的旧入口清理规则同步认识新入口行，`tests/test_pipeline.py` 与 `tests/test_effects.py` 增加逐维度断言。下界、末地文件头省略的部分清除行（如一号画面）在共用文件里按主世界取值统一写出；下界、末地合成零号每帧完整重写一号画面，清除与否不影响画面，此点未实机验证。
36. 反射射线质量提升为玩家选项：iterationT `Lib/Settings.glsl` 里 `RAYTRACE_QUALITY`（默认 `16`，范围 `8 12 16 24 32 64 128 256 512`）、`RAYTRACE_REFINEMENT_STEPS`（默认 `5`，范围 `2` 到 `32` 共 21 档）、`RAYTRACE_ZDIFF_THRESHOLD`（默认 `0.2`，范围 `0.05 0.1 0.15 0.2 0.3 0.4 0.5`）三项都带取值注释，会出现在菜单；Omni 原来把前两项当内部常数。现按合同提升为玩家选项 `OMNI_RAYTRACE_QUALITY`、`OMNI_RAYTRACE_REFINEMENT_STEPS`、`OMNI_RAYTRACE_ZDIFF_THRESHOLD`，定义在 `effects/reflection/reflection.glsl`、页面 `reflection`，默认值与取值照 iterationT，默认画面不变。`RAYTRACE_REFINEMENT_STEPS` 的范围注释在原程序缺右括号（第 31 条已登记），按合同补成 `[2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]`。第九节的选项归属与第 31 条已同步更正。
37. `TITLE` 标志叠加已移植（2026-10-17，消除会改变默认画面的最后一处差异）：iterationT `Lib/Settings.glsl:481` 默认 `#define TITLE`，`Lib/IndividualFounctions/MotionBlur.glsl` 的 `title()` 绘制品牌标志、`main` 里 `bloomGuide = title(color)` 并把标题计数累加到二号画面顶行 `(20, H-1).a`。Omni 新增 `effects/lens/title.glsl`（选项 `OMNI_TITLE`，默认开）与 `TitleLogo`、`TitleCard`、`UpdateTitleCounter` 三个函数，在 `rendering/post.glsl` 的合成八号里调用；`compositeOutput1.a` 由恒为零改为图标不透明度（泛光引导），并补写 `(20,H-1)` 计数像素。
    贴图：iterationT 用自带 `texture/itt320.png`（四十九乘十九像素），原程序把它挂在八号画面第二层、并用二维采样器读。Omni 的合成八号把八号画面当预计算大气三维贴图用（天空与反射），在这里打开 `COLORTEX8_2D` 会与 `effects/sky/sky.glsl` 的三维采样冲突，所以图标改用一个独立的二维采样器 `omniTitleTex`，在 `rendering/pipeline.properties` 加一行 `texture.composite.omniTitleTex=texture/itt320.png` 绑定同一张早已随 `texture/` 目录移植的贴图。
    下界差异（未按原程序）：原程序在下界改用 `NetherLighting` 给图标染色并把半透明直接变不透明；`NetherLighting` 所在的 `effects/world/nether.glsl` 与后期共享头 `effects/clarity/post_shared.glsl` 都会声明五个下界群系权重，同时引入会重复声明，无法在不改共享头的前提下引入，故下界暂按曝光染色（默认亮度 `OMNI_NETHER_BRIGHTNESS=1.0` 时观感接近）。属已知未复刻项。
    未验证：图标的位置、大小与淡出节奏只按原程序一比一移植，游戏内画面尚未实机确认。
    2026-10-17 确认：`effects/lens/title.glsl` 现有 `TitleExposure`（:35）、`TitleCounter`（:42）、`TitleCard`（:49）、`TitleLogo`（:87）、`UpdateTitleCounter`（:101）五个函数；选项 `OMNI_TITLE`（:25）默认开；在 `rendering/post.glsl` 合成八号调用（`TitleLogo` 写 `bloomGuide`、`UpdateTitleCounter` 累加 `(20,H-1)` 计数像素），贴图绑定在 `rendering/pipeline.properties` 的 `texture.composite.omniTitleTex`。行为与 iterationT 默认画面一致。

38. 九号画面新增为方块编号与生物群系缓冲（Eclipse 程序化草需要）：iterationT 只用零到八号画面，Omni 为程序化草新增九号 `RGBA8`、不清除，登记在 `rendering/buffers.glsl:55` 与 `:76`。只有主世界地形片元写（`effects/ground/terrain_surface.glsl` 的九号写出）、草几何阶段读（`effects/ground/grass_geometry.glsl` 的隔壁查询）；`OMNI_SHADER_GRASS` 默认关时整条通路不编译，画面与 iterationT 一致。这是为 Eclipse 额外功能扩展的缓冲协议，第四节表格已同步补记。
39. 程序化草没有细分着色器：Eclipse 的草用 `.tcs`/`.tes` 细分阶段（`dimensions/all_solid.tcs`、`.tes`），Omni 的入口生成器不产出细分阶段，草叶改在几何阶段直接生成、数量精简（`effects/ground/grass.glsl:156` 的 `omniGrassBladeBarycentric` 与 `effects/ground/grass_geometry.glsl`）。默认关，不影响 iterationT 默认画面。
40. 末地涡旋雾未搬吸收率与 `colortex4` 随机缓冲驱动的雾中闪电：`effects/world/end_fog.glsl` 的 `EndVortexFog`（`:101`）用 `OMNI_SUNLIGHT_INTENSITY` 与量级对齐系数（`:146`）代替 Eclipse `lib/end_fog.glsl` 的吸收链路，游戏内未校准；默认关。
41. 行星曲率只接在顶点阶段的一部分：`effects/world/planet.glsl` 的 `omniPlanetCurvatureDrop`（`:37`）与 `omniPlanetCurvatureView`（`:49`/`:55`）已接地形、实体、水面、阴影、远景、粒子、覆盖层与雨雪，但水下手持未接；默认关。
42. 每日天气表放在 GLSL 常量数组而非约一百项菜单选项：`effects/weather/dailyweather.glsl` 的 `OMNI_WEATHER_COVERAGE/DENSITY/FOG`（`:65/78/92`），玩家只有总开关、随机与周期三项；默认关。
43. 玩家交互水面用近似：`effects/water/playerwater.glsl` 的 `PlayerWaterRipple`（`:32`）用相机位置与时间相位近似入水位置与时刻，得到持续外扩涟漪，不是 Eclipse 的网格模拟（`lib/oceans.glsl` 的 `physics_waveHeight`）；默认关。
44. Eclipse 合并批次的额外功能默认中性：色彩分级、镜头形变、胶片颗粒、洞穴雾、边界雾、下界三段体积雾、末地涡旋雾、时段雾、每群系环境、雪暴沙暴、受伤与低血量、区块淡入、水洼尺寸、材质 AO 与法线倍率、太阳色与辐照、天空散射系数（`OMNI_SKY_BRIGHTNESS` 与 `OMNI_SKY_RAYLEIGH/MIE_R/G/B`，`skyscatter.glsl`，近似）、远景过绘防护与噪声衰减都默认关闭或取不改变画面的值，默认画面与 iterationT 一致；逐项落点见 `docs/eclipse-parity.md`。

45. 一号画面补上多级纹理声明：iterationT 在 `Lib/IndividualFounctions/MotionBlur.glsl:11` 声明 `colortex1MipmapEnabled = true`，
    本项目此前漏了这条，自动曝光的 `GetExposureTiles`（`effects/color/color.glsl:144`）读第六级多级纹理时会读不到内容，
    整幅自动亮度因此偏离 iterationT。现已在 `rendering/buffers.glsl` 补上同名声明，默认画面回到一致（2026-10-17 审查发现并修复）。
46. 删除 iterationT 侧同样没有调用点的残留代码：`AgXConfigurable` 一族（`effects/color/color.glsl`）、
    `CalculateSunlightColors`（`effects/lighting/sunlight.glsl`，本项目已内联进 `rendering/lights.glsl`）、
    `PrintFloat`/`PrintUintBinary`/`SevenSegment`/`DecimalPoint`（`effects/dev/debug.glsl`）。这些在 iterationT 的 `main` 里也没有被调用，
    按项目规范「不留死代码」删除，默认画面不受影响；`DHTerrainCulling` 属另一情况，已改由 `rendering/distant.glsl` 调用，不再内联重复。
47. 长文件按效果拆分（内部结构，不改画面）：`effects/fog/fog.glsl`（原 796 行）拆成入口 `fog.glsl` 加 `tod_fog.glsl`、`volumetric.glsl`、
    `landscattering.glsl`、`cave_border_fog.glsl`、`vanilla_fog.glsl`、`underwater_fog.glsl`；`effects/world/end.glsl`（原 831 行）拆成入口
    加 `end_sky.glsl`、`end_disc.glsl`、`end_fog.glsl`、`end_island_light.glsl`、`end_reflection.glsl`；`rendering/terrain.glsl`（原 767 行）只留
    顶点、几何、片元三个阶段的入口结构与输入输出，算法体搬到 `effects/ground/terrain_surface.glsl` 与 `effects/ground/grass_geometry.glsl`。
    入口集中定义本效果的选项与内部常数，分文件按来源用同一顺序引入，`#include` 语义与拆分前逐段一致，默认画面与算法不变。
48. 远景参与开关默认开，与 iterationT 默认画面一致：Eclipse 的三项远景开关 `DH_AMBIENT_OCCLUSION`、`DH_SUBSURFACE_SCATTERING`、`DH_SCREENSPACE_REFLECTIONS`（`lib/settings.glsl:1095-1097`）合为 `OMNI_DH_AO`（`effects/lighting/ambient.glsl:71`）、`OMNI_DH_SSS`（`effects/shadow/shadow.glsl:54`）、`OMNI_DH_SSR`（`effects/reflection/reflection.glsl:39`）。Omni 的远景参与本来就走 iterationT 路径读 `dhDepthTex0/1` 与材质编号，这三项只是加独立开关、默认开等于现状（关闭时才让远景像素按天空处理或不透光），所以默认画面与 iterationT 一致；与其余 Eclipse 合并项「默认中性」的差别与近似说明见 `docs/eclipse-parity.md` 的「远景（DH）」行。
49. 末地星空改用 Eclipse 星场（2026-10-18，按用户要求）：`effects/world/end_sky.glsl` 的 `EndCalculateStars`（`:28`）不再自带 iterationT 的三维格子星空，改为直接转发主世界 `effects/sky/sky.glsl` 的 `CalculateStars(worldDir, worldSunVector)`，与主世界共用同一份 Eclipse `lib/stars.glsl` 星场（白色稳定星场默认、彩色星盒由 `OMNI_STARS_COLORED` 开启）。签名不变（仍只吃世界方向），调用点 `effects/world/end_disc.glsl:187` 的 `EndCalculateStars(rayDir)` 不变。与旧 iterationT 末地星空的差别：星点形状与疏密随 Eclipse 星场改变；朝向改用主世界 `CalculateStars` 的「绕日轴对齐天球」，不再按时间绕竖直轴旋转；原先独立的三维格子哈希、`coverage`/`maxLuminance` 与按格取样代码整体删除。默认 `OMNI_STAR_TYPE=1`，末地天空像素会因此换星点外观（属本次要求的效果改动，不属默认中性项）；`OMNI_STAR_TYPE=0`（关星）或 `=2`（原版贴图）时与原来一致。差异说明见 `docs/eclipse-parity.md` 的「星空」行。仅离线编译与检查通过，游戏内画面未验证。
50. 雾照明补手持光与水下两张（2026-10-18，按用户要求）：照 Eclipse `dimensions/composite3.fsh` 把 `LPV_VL_FOG_ILLUMINATION_HANDHELD(_WATER)` 合并进雾照明。
    - 取光函数：`effects/lighting/lpv.glsl` 新增 `omniLpvHandLight`，按手持物品编号读方块光表得到光色与光照范围，再按离玩家的距离三次方衰减，照 Eclipse `lib/diffuse_lighting.glsl:74` 的 `GetHandLight`（去掉 Eclipse 的 `relativeEyePosition`，直接用采样点到玩家的距离，游戏内未验证）。
      为让合成阶段能读光表，`rendering/pipeline.properties` 给 `image.omniLpvBlocks` 加了整数采样器名 `omniLpvBlocksTex`；计算阶段仍用同名图像 `omniLpvBlocks` 读写，两者指向同一张纹理。
    - 空气项 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD`（`effects/lighting/lpv.glsl`，默认关、等于 Eclipse）：在 `effects/fog/volumetric.glsl` 的体积雾步进里按本步吸收量累加手持光。
    - 水下项 `OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER`（`effects/lighting/lpv.glsl`，默认开、等于 Eclipse）：在 `effects/fog/underwater_fog.glsl` 的水下体积雾里叠加手持光，按水的分波段吸收衰减。
    - 两项都要求雾照明 `OMNI_LPV_VL_FOG_ILLUMINATION`（默认关），所以默认画面不变。亮度系数照 Eclipse（空气项 `0.04`、水下项 `0.2`）按本项目既有的百分之一定标缩小，未按游戏内观感校准。Eclipse 水下项原本接在解析水雾的间接光上，本项目接在水下体积雾上，属换落点的近似。
51. 长文件按效果拆分（内部结构，不改画面）：`effects/sky/sky.glsl`（原 728 行）拆成入口 `sky.glsl` 加 `atmosphere_model.glsl`（预计算大气与天空辐射）、
    `sun_moon.glsl`（日月圆盘）、`moon_orbit.glsl`（月亮轨道、月食与月相）、`stars.glsl`（星场）、`skybox.glsl`（天空盒投影）；
    `effects/cloud/cloud.glsl`（原 638 行）拆成入口 `cloud.glsl` 加 `volumetric.glsl`（体积云、附加层与低分辨率云总图，含 `CloudShadowTex`）、
    `planar.glsl`（平面云）、`shadow.glsl`（云影贴图与模糊）。入口集中定义本效果的全部选项，分文件按同一顺序引入。
    体积云与平面云只在能读三维云噪声的延迟三号、七号、八号参与编译，这个判据收成 `OMNI_CLOUD_DENSITY_PASS` 一处定义、两个文件各自按它开关；
    选项名、默认值与菜单分组不变（生成菜单逐字节一致），`#include` 语义与拆分前逐段一致，默认画面与算法不变。

51. 十号画面新增为低分辨率体积云缓冲（Eclipse `VL_RENDER_SCALE` 的近似合并，`dev.146`）：iterationT 只用零到八号，Omni 九号已给程序化草；本轮为 `OMNI_CLOUD_RENDER_SCALE` 大于一时新增十号 `RGBA16`、尺寸 0.5 或 0.25、每帧清除，登记在 `rendering/buffers.glsl:57` 与 `:78`。低分辨率基础体积云搬进独立阶段 `deferred7`（写十号）与 `deferred8`（读十号放大回一号），平面云与附加层仍在全分辨率合成；`OMNI_CLOUD_RENDER_SCALE` 默认 1 时不生成这两个阶段，默认画面不变。第四节表格与 `docs/rendering.md` 已同步补记。
52. 合成五号三个维度分支合并为一个流程（内部结构，不改画面）：`effects/world/composite_scene.glsl` 原按维度写三份 `CompositeSceneColor`（对应 `composite5.fsh`、`world-1/composite5.fsh`、`world1/composite5.fsh`），三份几乎相同。现只保留一份流程，共用的表面读取与输出编码抽成 `SceneReadSurface`、`SceneWriteOutput`，只在折射函数、彩色玻璃吸收、雾函数、水吸收、透明通道与镜头光斑这几处按 `OMNI_NETHER`/`OMNI_END` 分派；各维度原程序里不同的值（远裁剪面系数、按掩码还是按深度判天空、下界输出写半透明深度）逐处照原程序保留，画面与合并前一致。
53. 泛光、时间抗锯齿与全局光从「效果文件加程序体文件」合回一个文件（`dev.160`，内部结构，不改画面）：`effects/color/bloom.glsl` 并入原 `post_bloom.glsl` 的五级泛光链、`effects/clarity/antialiasing.glsl` 并入原 `post_taa.glsl` 的合成七号主体 `WriteTaaHistory`、`effects/lighting/ambient.glsl` 并入原 `globalillumination.glsl` 的延迟二号与四号主体 `RenderGISpatialFilter`，各自沿用原程序宏隔开；`rendering/post.glsl` 与 `rendering/deferred.glsl` 去掉对应单独引入。算法、常数、选项与缓冲编号不变。

### 已裁决：旧选项的处置（2026-10-16）

规则：iterationT 的选项全部保留（加 `OMNI_` 前缀）；与 iterationT 含义相同只是改了名的旧选项按下表改名，
旧配置按新名迁移；只属于被替换旧算法、在新算法里没有对应含义的旧参数移除，作为本次移植的接口变更记录在案。
项目自己的额外功能（极光、彩虹、闪电、季节、光传播体积、调试视图、性能计时）保留并已接进新管线。

并入（旧名 → 新名，含义相同，取值改成 iterationT 的）：

| 旧名 | 新名 |
| --- | --- |
| `OMNI_SHADOW_PENUMBRA` | `OMNI_VARIABLE_PENUMBRA_SHADOWS` |
| `OMNI_SHADOW_PENUMBRA_QUALITY` | `OMNI_VPS_QUALITY` |
| `OMNI_SHADOW_BLUR` | `OMNI_SHADOW_BASIC_BLUR` |
| `OMNI_SHADOW_SOFTNESS` | `OMNI_VPS_SPREAD` |
| `OMNI_MATERIAL_DETAIL` | `OMNI_ENABLE_PBR` |
| `OMNI_VEGETATION_WIND` | `OMNI_WAVING_PLANTS` |
| `OMNI_RAIN_WIND` | `OMNI_RAIN_WIND_X`（并新增 `OMNI_RAIN_WIND_Z`） |
| `OMNI_NETHERFOG_DENSITY` | `OMNI_NETHER_FOG_DENSITY`（补全单词分隔，与 `VFOG` 一系写法统一） |
| `OMNI_WATERFOG_DENSITY` | `OMNI_WATER_FOG_DENSITY`（同上） |
| `OMNI_UNDERWATER_DENSITY` | `OMNI_WATER_FOG_DENSITY` |
| `OMNI_VFOG_STEPS` | `OMNI_VFOG_QUALITY` |
| `OMNI_AA_ENABLED` | `OMNI_TAA` |
| `OMNI_TAA_WEIGHT` | `OMNI_TAA_BLENDWEIGHT` |
| `OMNI_BLOOM_ENABLED` | `OMNI_BLOOM` |
| `OMNI_BLOOM_STRENGTH` | `OMNI_BLOOM_AMOUNT` |
| `OMNI_AUTO_EXPOSURE` | `OMNI_MANUAL_EXPOSURE`（含义相反） |
| `OMNI_TONEMAP_MODE` | `OMNI_TONEMAP_OPERATOR` |
| `OMNI_UPSCALE` | `OMNI_FSR` |
| `OMNI_UPSCALE_STRENGTH` | `OMNI_FSR_SHARPNESS` |
| `OMNI_CLOUD_COVERAGE` | `OMNI_CLOUD_CLEAR_COVERAGE` |
| `OMNI_CLOUD_HEIGHT` | `OMNI_CLOUD_CLEAR_ALTITUDE` |
| `OMNI_CLOUD_THICKNESS` | `OMNI_CLOUD_CLEAR_THICKNESS` |
| `OMNI_CLOUD_DENSITY` | `OMNI_CLOUD_CLEAR_DENSITY` |
| `OMNI_CLOUD_SCALE` | `OMNI_CLOUD_CLEAR_SCALE` |
| `OMNI_CLOUD_SUNLIGHT` | `OMNI_CLOUD_CLEAR_SUNLIGHTING` |
| `OMNI_CLOUD_SKYLIGHT` | `OMNI_CLOUD_CLEAR_SKYLIGHTING` |
| `OMNI_CLOUD_RAIN_SUNLIGHT` | `OMNI_CLOUD_RAIN_SUNLIGHTING` |
| `OMNI_CLOUD_RAIN_SKYLIGHT` | `OMNI_CLOUD_RAIN_SKYLIGHTING` |
| `OMNI_CLOUD_BOTTOM` | `OMNI_CLOUD_BOTTOM_BRIGHTNESS` |
| `OMNI_CLOUD_OUTSCATTER` | `OMNI_CLOUD_OUTSCATTER_FACTOR` |
| `OMNI_CLOUD_NOISE_SCALE` | `OMNI_CLOUD_DETAILED_NOISE_SCALE` |

移除（旧算法专用参数，新算法里没有对应含义；这是本次移植的接口变更，见 `CHANGELOG.md`）：

- 天空：`OMNI_SUN_DISK`、`OMNI_SUN_SIZE`、`OMNI_MOON_DISK`、`OMNI_MOON_SIZE`、`OMNI_CELESTIAL_TINT`、`OMNI_STAR_STRENGTH`、`OMNI_STAR_DENSITY`、`OMNI_SUNSET_STRENGTH`、`OMNI_SUNSET_TINT`、`OMNI_SKY_SATURATION`、`OMNI_SKY_BRIGHTNESS`、`OMNI_RESOURCE_SKY`、`OMNI_ATMOSPHERE_STEPS`、`OMNI_ATMOSPHERE_SCATTER`、`OMNI_SCATTER_STRENGTH`、`OMNI_ATMOSPHERE_MIE_G`、`OMNI_ATMOSPHERE_MULTIPLE`、`OMNI_ATMOSPHERE_OZONE`、`OMNI_NETHER_COLOR`、`OMNI_END_SKY_BRIGHTNESS`
- 云：`OMNI_CLOUD_MODE`、`OMNI_CLOUD_BRIGHTNESS`、`OMNI_CLOUD_TINT`、`OMNI_CLOUD_SILVER`、`OMNI_CLOUD_STEPS`、`OMNI_CLOUD_SHADOW_STRENGTH`、`OMNI_CLOUD_SHADOW_AMBIENT`
- 环境光：`OMNI_SSAO`、`OMNI_AO_STEPS`、`OMNI_AO_SLICES`、`OMNI_AO_STRENGTH`、`OMNI_AMBIENT_RADIUS`、`OMNI_SCREEN_BOUNCE`、`OMNI_BOUNCE_RADIUS`、`OMNI_BOUNCE_STRENGTH`
- 阴影：`OMNI_SHADOW_ENABLED`、`OMNI_SHADOW_QUALITY`、`OMNI_SHADOW_BIAS`、`OMNI_SHADOW_OFFSET`
- 水面：`OMNI_WAVE_STRENGTH`、`OMNI_WAVE_SPEED`、`OMNI_WATER_BUMP`、`OMNI_WATER_BUMP_STRENGTH`、`OMNI_OCEAN_WAVES`、`OMNI_OCEAN_HEIGHT`、`OMNI_WATER_ABSORB_R/G/B`、`OMNI_WATER_SCATTER_R/G/B`、`OMNI_WATER_CLEAR`、`OMNI_WATER_REFRACTION`、`OMNI_REFRACTION_STRENGTH`、`OMNI_WATER_GLINT`、`OMNI_RAIN_RIPPLES`、`OMNI_RIPPLE_STRENGTH`、`OMNI_PLAYER_RIPPLES`
- 天气：`OMNI_SNOW_VISIBILITY`、`OMNI_RAIN_DENSITY`、`OMNI_RAIN_SPLASH`、`OMNI_RAIN_WET_RESPONSE`、`OMNI_RAIN_DARKEN`
- 材质与视差：`OMNI_PARALLAX`、`OMNI_WET_SURFACES`、`OMNI_WET_STRENGTH`、`OMNI_SNOW_STRENGTH`、`OMNI_SNOW`、`OMNI_CLIMATE_SNOW`
- 植物：`OMNI_WIND_STRENGTH`、`OMNI_WIND_SPEED`
- 生物与玩家：`OMNI_ENTITY_LIGHT`、`OMNI_ENTITY_TINT`、`OMNI_PLAYER_GLOW`
- 世界与远景：`OMNI_DH_ENABLED`、`OMNI_DH_FOG_BLEND`、`OMNI_PLANET_CURVATURE`
- 反射：`OMNI_SSR`、`OMNI_SKY_REFLECTION`、`OMNI_REFLECTION_STRENGTH`、`OMNI_SSR_STEPS`、`OMNI_REFLECTION_DENOISE`、`OMNI_REFLECTION_BLUR`
- 雾与空气：`OMNI_FOG_ENABLED`、`OMNI_FOG_DENSITY`、`OMNI_FOG_TINT`、`OMNI_HEIGHT_FOG_ENABLED`、`OMNI_HEIGHT_FOG`、`OMNI_FOG_HEIGHT`、`OMNI_FOG_SCALE`、`OMNI_VOLUMETRIC_LIGHT`、`OMNI_VOLUMETRIC_STRENGTH`、`OMNI_UNDERWATER_STRENGTH`、`OMNI_UNDERWATER_TINT`、`OMNI_END_FOG`、`OMNI_END_FOG_DENSITY`
- 后期：`OMNI_AA_STRENGTH`、`OMNI_TEMPORAL_DENOISE`、`OMNI_CHROMATIC`、`OMNI_BOKEH_SHAPE`、`OMNI_DOF_STRENGTH`、`OMNI_MOTION_BLUR_STRENGTH`、`OMNI_FLARE_STRENGTH`、`OMNI_BLOOM_THRESHOLD`、`OMNI_BLOOM_RADIUS`、`OMNI_EXPOSURE`、`OMNI_EXPOSURE_TARGET`、`OMNI_EXPOSURE_SPEED`、`OMNI_BRIGHTNESS`、`OMNI_CONTRAST`、`OMNI_TONEMAP_STRENGTH`、`OMNI_DITHER`、`OMNI_RENDER_SCALE`

保留并已接线的额外功能：`OMNI_AURORA*`、`OMNI_RAINBOW*`、`OMNI_LIGHTNING*`（天空叠加与闪电照明）、`OMNI_SEASONS`/`OMNI_SEASON_TINT`（地形植被季节色）、`OMNI_LPV_*`（光传播体积）、`OMNI_DEBUG_VIEW`、`OMNI_PROFILER`。

并入（Eclipse 合并，属接口变更）：`OMNI_WHITE_BALANCE`（`effects/color/color.glsl`）。旧 Omni 的 -1–1 染色取值不再合法；现为 1000–50000 的黑体色温，默认 6500 中性。旧配置里的 `OMNI_WHITE_BALANCE=0.2` 之类小数会被判非法，需要迁移到色温取值。

保留为内部常数、不开放菜单（iterationT 本身就不把它当玩家选项）：`MAIN_OUTPUT_FACTOR`、`EXPOSURE_OUTPUT_FACTOR`、`MATID_*`、`ATMO_MIN_ALTITUDE`、`ATMO_SKYBOX_MIN_ALTITUDE`、`VFOG_SUNLIGHT_STEPS`、`VFOG_SUNLIGHT_STEPLENGTH`、`TAA_*`、`AE_CLAMP`、`WATER_REFRACT_IOR`、`CAUSTICS_TEX_RESOLUTION`、`ANIMATION_SPEED`。
