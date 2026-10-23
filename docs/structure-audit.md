# rendering 阶段审计

这份文件回答三件事：`rendering/` 里每个文件现在是什么角色、哪些还能继续减少、下一批先动哪里。
调用位置：继续结构重构前先读；每批完成后更新行数与状态。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：`rendering/` 只留阶段流程；纯公式进 `gfx/`，宿主输入适配进 `bind/` 或效果页；不靠整目录搬迁冒充行数下降。

## 一、口径

- 行数只数去注释后的非空代码行，命令与 `docs/structure-plan.md` 相同。
- 当前（0.1.86）：`bind/` 460、`rendering/` 8524、`gfx/` 4057、`effects/` 628，四层合计 13669 行。
- 分类只有三种：
  - **阶段胶水**：安排绘制顺序、声明本程序的输入输出、调用一次效果入口；保留在 `rendering/`。
  - **算法核**：仍有成段公式、循环、采样或合成流程；目标是参数化后进 `gfx/`。
  - **MC 数据适配**：只把 uniform、纹理、选项换成普通参数再转发；目标是进 `bind/` 或并回效果页。
- 行数下降不能只靠搬家：每批必须同时删掉重复声明、重复分支或死转发，让四层合计真实变小。

## 二、阶段胶水

保留在 `rendering/`，只做流程与一次调用。

| 文件 | 行数 | 说明 |
| --- | ---: | --- |
| `rendering/buffers.glsl` | 26 | 中间画面与常量声明。 |
| `rendering/buffers_main.glsl` | 8 | 主世界差异项。 |
| `rendering/buffers_nether.glsl` | 8 | 下界差异项。 |
| `rendering/buffers_end.glsl` | 8 | 末地差异项。 |
| `rendering/celestial.glsl` | 127 | 天空基础与贴图程序主体。 |
| `rendering/clarity/post_shared.glsl` | 38 | 后期程序共用片元声明。 |
| `rendering/composite_filter_pass.glsl` | 13 | 合成三号与四号共用主体。 |
| `rendering/composite_pass0.glsl` | 31 | 合成零号主体。 |
| `rendering/composite_pass1.glsl` | 14 | 合成一号主体。 |
| `rendering/composite_pass2.glsl` | 27 | 合成二号主体。 |
| `rendering/composite_pass5.glsl` | 36 | 合成五号主体。 |
| `rendering/composite_shared.glsl` | 31 | 合成程序共用声明。 |
| `rendering/deferred_cloud_shadow_blur.glsl` | 62 | 延迟四号、五号云影模糊。 |
| `rendering/deferred_pass0.glsl` | 29 | 延迟零号主体。 |
| `rendering/deferred_pass1.glsl` | 28 | 延迟一号主体。 |
| `rendering/deferred_pass2.glsl` | 29 | 延迟二号主体。 |
| `rendering/deferred_pass3.glsl` | 25 | 延迟三号主体。 |
| `rendering/deferred_pass4.glsl` | 5 | 延迟四号转发。 |
| `rendering/deferred_pass5.glsl` | 5 | 延迟五号转发。 |
| `rendering/deferred_pass6.glsl` | 20 | 延迟六号复制。 |
| `rendering/deferred_pass7.glsl` | 51 | 低分辨率体积云总图。 |
| `rendering/deferred_pass8.glsl` | 44 | 云贴回天空。 |
| `rendering/deferred_shared.glsl` | 31 | 延迟程序共用片元声明。 |
| `rendering/distant.glsl` | 219 | 远景地形与水主体。 |
| `rendering/entities.glsl` | 433 | 实体、方块实体、手持物、蜘蛛眼主体。 |
| `rendering/final.glsl` | 73 | 最终输出主体。 |
| `rendering/lights.glsl` | 99 | 合成与延迟顶点光色。 |
| `rendering/lpv.glsl` | 102 | 光传播计算入口。 |
| `rendering/overlay.glsl` | 300 | 覆盖层七组程序主体。 |
| `rendering/post_effect_pass.glsl` | 40 | 景深与泛光链共用主体。 |
| `rendering/post_fragment_deps.glsl` | 14 | 后期片元依赖顺序。 |
| `rendering/post_pass7.glsl` | 12 | 时间抗锯齿历史。 |
| `rendering/post_pass8.glsl` | 26 | 动态模糊、标题与统计。 |
| `rendering/post_pass14.glsl` | 17 | 色调映射、颗粒与分级。 |
| `rendering/post_pass15.glsl` | 20 | 锐化。 |
| `rendering/post_pass16.glsl` | 21 | 放大。 |
| `rendering/post_vertex.glsl` | 12 | 后期整屏顶点。 |
| `rendering/shadow.glsl` | 229 | 阴影主体。 |
| `rendering/sky/cloud_stage.glsl` | 20 | 低分辨率云阶段共用参数。 |
| `rendering/terrain.glsl` | 252 | 地形顶点、几何、片元主体。 |
| `rendering/translucent.glsl` | 286 | 水面与手持水主体。 |
| `rendering/watersim.glsl` | 104 | 波浪模拟三个计算阶段。 |
| `rendering/water/caustics_vertex.glsl` | 13 | 延迟焦散共用顶点。 |

## 三、算法核

仍有公式、循环或成段合成；按风险从低到高迁入 `gfx/`，每次只动一组并把参数全部显式传入。

| 文件 | 行数 | 下一步 |
| --- | ---: | --- |
| `rendering/clarity/fxaa.glsl` | 34 | 边缘检测与混合可进 `gfx/antialias.glsl`。 |
| `rendering/clarity/taa.glsl` | 157 | 相机速度与深度取样可再参数化，矩阵由调用方传入。 |
| `rendering/color/post_stats.glsl` | 42 | 统计像素写入是固定公式，可进 `gfx/post.glsl`。 |
| `rendering/color/post_tonemap.glsl` | 29 | 泛光、暗角、曝光与映射的合成分解后进 `gfx/post.glsl`。 |
| `rendering/fog/cave_border_fog.glsl` | 38 | 洞穴检测与边界雾可进 `gfx/fog.glsl`。 |
| `rendering/fog/landscattering.glsl` | 57 | 地表散射积分可进 `gfx/fog.glsl`。 |
| `rendering/fog/underwater_fog.glsl` | 25 | 水下光柱步进可进 `gfx/fog_volume.glsl`。 |
| `rendering/ground/grass_geometry.glsl` | 103 | 草丛顶点生成可进 `gfx/` 的新草模块。 |
| `rendering/ground/terrain_surface.glsl` | 249 | 各向异性采样与表面写出分开，采样核进 `gfx/`。 |
| `rendering/lighting/composite_surface.glsl` | 188 | 主世界表面光照合成，参数化后进 `gfx/surface.glsl`。 |
| `rendering/lighting/composite_surface_end.glsl` | 131 | 末地表面光照，与主世界共用合成参数后合并。 |
| `rendering/lighting/composite_surface_nether.glsl` | 49 | 下界表面光照，同上。 |
| `rendering/lighting/held_light.glsl` | 168 | 光斑、屏幕阴影与高光，先合并重复的相机旋转段。 |
| `rendering/lighting/lpv.glsl` | 229 | 体素编码与采样公式可进 `gfx/gi.glsl`。 |
| `rendering/reflection/composite_filter.glsl` | 31 | 两段滤波只差半径与噪声，先合并成一次参数化调用。 |
| `rendering/reflection/composite_specular.glsl` | 24 | 反射合成流程，参数化后进 `gfx/reflection.glsl`。 |
| `rendering/reflection/screenspace.glsl` | 223 | 假天空、反射雾与参数打包，纯计算部分进 `gfx/reflection.glsl`。 |
| `rendering/shadow/screen_shadow.glsl` | 30 | 屏幕空间步进可进 `gfx/shadow.glsl`。 |
| `rendering/sky/skyrender.glsl` | 149 | 天空、云与天空盒合成，可进 `gfx/atmosphere.glsl`。 |
| `rendering/water/composite_waterfog.glsl` | 54 | 合成一号水雾，参数化后进 `gfx/water.glsl`。 |
| `rendering/water/playerwater.glsl` | 21 | 玩家涟漪可进 `gfx/water.glsl`。 |
| `rendering/water/refraction.glsl` | 64 | 与末地、下界两份折射重复，先合并成一份参数化实现。 |
| `rendering/water/waves.glsl` | 146 | 物理波与视差坐标，解析波公式进 `gfx/water.glsl`。 |
| `rendering/world/composite_scene.glsl` | 172 | 场景最终合成，分段进 `gfx/post.glsl` 与 `gfx/reflection.glsl`。 |
| `rendering/world/end_reflection.glsl` | 24 | 末地折射与反射兜底，与折射合并。 |
| `rendering/world/nether.glsl` | 124 | 下界雾、折射与光照，雾公式进 `gfx/fog.glsl`，折射并入共用实现。 |

## 四、MC 数据适配

只做宿主输入到普通参数的转换；后续迁 `bind/` 或并回效果页，迁移时顺手删掉死转发。

| 文件 | 行数 | 说明 |
| --- | ---: | --- |
| `rendering/clarity/antialiasing.glsl` | 58 | 抗锯齿选项与历史写入。 |
| `rendering/clarity/chunkfade.glsl` | 30 | 区块淡入。 |
| `rendering/clarity/grain.glsl` | 12 | 胶片颗粒。 |
| `rendering/clarity/upscale.glsl` | 18 | 放大与锐化。 |
| `rendering/cloud/cloud.glsl` | 15 | 云选项汇聚。 |
| `rendering/cloud/planar.glsl` | 48 | 平面云转发，含未调用包装。 |
| `rendering/cloud/shadow.glsl` | 36 | 云影取样。 |
| `rendering/cloud/volumetric.glsl` | 161 | 体积云参数打包。 |
| `rendering/color/bloom.glsl` | 108 | 泛光链参数打包。 |
| `rendering/color/color.glsl` | 82 | 曝光与颜色。 |
| `rendering/color/colorgrade.glsl` | 36 | 色彩分级。 |
| `rendering/dev/debug.glsl` | 28 | 调试颜色。 |
| `rendering/entity/entity.glsl` | 22 | 实体状态色与手持投影。 |
| `rendering/fog/fog.glsl` | 29 | 雾入口汇聚。 |
| `rendering/fog/tod_fog.glsl` | 44 | 时段雾。 |
| `rendering/fog/vanilla_fog.glsl` | 19 | 原版特殊雾。 |
| `rendering/fog/volumetric.glsl` | 154 | 体积雾参数打包。 |
| `rendering/ground/grass.glsl` | 89 | 草叶风向与顶点。 |
| `rendering/ground/selection.glsl` | 27 | 选择框。 |
| `rendering/ground/vegetation.glsl` | 107 | 植物摆动。 |
| `rendering/lens/distortion.glsl` | 37 | 镜头形变。 |
| `rendering/lens/dof.glsl` | 57 | 景深参数。 |
| `rendering/lens/glare.glsl` | 47 | 眩光。 |
| `rendering/lens/hurt.glsl` | 77 | 受伤与镜头发水。 |
| `rendering/lens/lens.glsl` | 15 | 镜头入口。 |
| `rendering/lens/motion_blur.glsl` | 43 | 相机动态模糊。 |
| `rendering/lens/post_motionblur.glsl` | 17 | 后期动态模糊颜色。 |
| `rendering/lens/title.glsl` | 63 | 标题卡。 |
| `rendering/lighting/ambient.glsl` | 38 | 环境光空间滤波。 |
| `rendering/lighting/blocklight.glsl` | 57 | 方块光与手持光。 |
| `rendering/lighting/emissive.glsl` | 12 | 矿石与纹饰发光。 |
| `rendering/lighting/gi.glsl` | 95 | 全局光时间与空间滤波。 |
| `rendering/lighting/gtao.glsl` | 43 | 地平线遮蔽参数。 |
| `rendering/lighting/sunlight.glsl` | 34 | 阳光入口。 |
| `rendering/parallax.glsl` | 70 | 视差入口。 |
| `rendering/reflection/denoise.glsl` | 10 | 反射小波。 |
| `rendering/reflection/reflection.glsl` | 8 | 反射入口。 |
| `rendering/reflection/voxel.glsl` | 26 | 体素反射。 |
| `rendering/shadow/shadow.glsl` | 76 | 阴影采样与矩阵。 |
| `rendering/shadow/water_caustics.glsl` | 14 | 水下焦散。 |
| `rendering/sky/atmosphere.glsl` | 58 | 极光、彩虹与闪电。 |
| `rendering/sky/atmosphere_model.glsl` | 90 | 预计算大气转发。 |
| `rendering/sky/moon_orbit.glsl` | 51 | 月亮轨道。 |
| `rendering/sky/sky.glsl` | 41 | 天空入口汇聚。 |
| `rendering/sky/skybox.glsl` | 12 | 天空盒投影。 |
| `rendering/sky/skyscatter.glsl` | 10 | 天空散射色。 |
| `rendering/sky/stars.glsl` | 15 | 星空。 |
| `rendering/sky/sun_moon.glsl` | 21 | 日月圆盘。 |
| `rendering/sky/suncolor.glsl` | 14 | 太阳色。 |
| `rendering/water/caustics.glsl` | 15 | 焦散法线写出。 |
| `rendering/water/puddle.glsl` | 25 | 水洼。 |
| `rendering/water/rain.glsl` | 50 | 雨点涟漪。 |
| `rendering/water/water.glsl` | 14 | 水面入口。 |
| `rendering/water/waterfog.glsl` | 10 | 水雾。 |
| `rendering/water/wavesim.glsl` | 37 | 波浪模拟状态。 |
| `rendering/weather/dailyweather.glsl` | 77 | 每日天气。 |
| `rendering/weather/season.glsl` | 16 | 季节。 |
| `rendering/weather/snow.glsl` | 34 | 积雪。 |
| `rendering/weather/storm.glsl` | 48 | 暴风。 |
| `rendering/weather/weather.glsl` | 31 | 天气。 |
| `rendering/world/distant.glsl` | 38 | 远景附加。 |
| `rendering/world/end.glsl` | 16 | 末地入口。 |
| `rendering/world/end_disc.glsl` | 26 | 吸积盘。 |
| `rendering/world/end_fog.glsl` | 51 | 末地雾。 |
| `rendering/world/end_island_light.glsl` | 52 | 末地主岛光照。 |
| `rendering/world/end_sky.glsl` | 11 | 末地星空。 |
| `rendering/world/planet.glsl` | 20 | 行星曲率。 |
| `rendering/world/world.glsl` | 52 | 远景剔除与淡入。 |

## 五、已完成的合批

- 0.1.85：删除延迟零号到二号重复的片元声明，集中到 `deferred_shared.glsl`；焦散顶点集中到 `caustics_vertex.glsl`；合成三号与四号合并为 `composite_filter_pass.glsl`；景深与五级泛光六支程序合并为 `post_effect_pass.glsl`；时间抗锯齿的重复深度取样只留一份。`rendering/` 从 8711 行降到 8577 行，四层合计从 13838 行降到 13704 行。
- 0.1.86：`gfx/water.glsl` 增加折射坐标纯函数，主世界、末地、下界三份重复折射改为一次调用；延迟七号与八号共用 `sky/cloud_stage.glsl`；手电筒指向平滑只留一份。`rendering/` 降到 8524 行，四层合计降到 13669 行。
