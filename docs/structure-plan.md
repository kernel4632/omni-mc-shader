# 通用库与菜单重构计划

这份文件回答三件事：通用库怎么分、Minecraft 层留多少代码、菜单怎么归类。
调用位置：改动结构、拆分算法或调整菜单前先读；进度变化时更新第六节。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：算法进通用库，Minecraft 层只做接线；不设“高级”页，每个选项归入所属效果。

## 一、目标

- 每个效果在 `effects/<页>/<效果>.glsl` 或同名文件夹里集中保存菜单选项、宿主参数换算、阶段组合和说明；`bind/` 只做 Minecraft 输入到普通数值或结构体的适配；`rendering/` 只保留程序主体、阶段顺序和真正的阶段胶水。
- 通用图形算法放 `omni-gfx/src`，生成 `shaders/omni-gfx/` 供光影直接引用，不读取任何 Minecraft、Iris 或全局 uniform，可单独发布。
- 效果数量不减少，默认画面与现在一致；不能为了减行数删效果或改观感。
- 选项可以精简，但必须归入所属页面，不设“高级”总入口。

## 二、目录

```
shaders/
├─ omni-gfx/                   由 omni-gfx/src 生成的 GLSL 330，唯一算式来源
├─ bind/                       Minecraft 输入 → 普通数值或结构体
├─ effects/                    每个效果一个文件或同名文件夹：选项、参数换算、阶段组合与说明
├─ rendering/                  程序主体、阶段顺序与真正的阶段胶水
├─ common/                     加载器输入、坐标与管线编码
└─ world0/ world1/ world-1/    生成的薄入口
```

`bind/` 只允许出现“把加载器输入解成普通数据”的代码：不写光照、雾、云、颜色分级等效果算法，不读写中间画面。效果算法与选项放在 `effects/<页>/` 的所属效果文件里，纯公式在 `omni-gfx/src`。`rendering/` 扁平文件是程序主体，只保留阶段胶水，不复制效果算法。

## 三、通用库规则

1. 不出现 `OMNI_*`、`worldTime`、`rainStrength`、`screenSize` 等宿主符号。
2. 采样器、相机、太阳方向、天气全部由参数传入。
3. 函数统一 `gfx_` 前缀；一个函数只做一件能一句话说明的事。
4. 不写 `#version`；按 GLSL 330 编写，不依赖扩展。
5. 只依赖 GLSL 内建函数，不引用 `common/` 或 `effects/`。
6. 库文件必须有中文说明，写清输入、输出和关键取舍。
7. 独立发布前补许可证；许可证由仓库所有者决定。

## 四、菜单

顶层 9 页，所有选项放在所属效果分组下，没有“高级”页。

| 页面 | 分组 |
| --- | --- |
| 快速设置 | 预设、总画质、曝光、体积云、空气雾、水面、阴影 |
| 天空 | 日月、星空、大气、天象、资源包 |
| 云与雾 | 云层、空气雾、特殊雾 |
| 水与地面 | 水面、水洼、地面、植物 |
| 光照与阴影 | 日月、全局光、暗部、方块光、发光、手持光、体积光、阴影、反射 |
| 画面与镜头 | 曝光、色调、泛光、景深、镜头、抗锯齿、画面、玩家 |
| 天气与季节 | 降雨、每日天气、季节、积雪、暴风 |
| 世界与远景 | 群系、下界、末地、远景、曲率 |
| 关于与调试 | 版本、标题、日志；调试按住 Shift 显示 |

采样数、步数、分辨率等内部参数改成每个效果的“画质”档位，不单独出现在菜单里。

## 五、迁移顺序

下表是早期计划，其中 `gfx/` 是历史名称；实际算法已迁到 `omni-gfx/src`，转发层在 0.16.0-dev.7 删除。

| 批次 | 内容 | 验收 |
| --- | --- | --- |
| 1 | 建 `gfx/color.glsl`，把 ACES、AgX、无压缩从 `effects/color/color.glsl` 搬走 | 全量编译通过，画面不变 |
| 2 | 抽 `gfx/math.glsl` 与 `gfx/sampling.glsl` | 全量编译通过 |
| 3 | 抽 `gfx/surface.glsl` 与 `gfx/shadow.glsl` | 全量编译通过 |
| 4 | 抽 `gfx/atmosphere.glsl`、`cloud.glsl`、`water.glsl`、`fog.glsl` | 全量编译通过 |
| 5 | 抽 `gfx/gi.glsl`、`reflection.glsl`、`post.glsl`、`antialias.glsl` | 全量编译通过 |
| 6 | 建 `bind/`，效果文件改成只做参数转换与调用 | 行数达标，画面不变 |
| 7 | 菜单合并为 9 页，内部参数改画质档位 | 游戏中逐页检查 |
| 8 | 删除空目录与死代码，更新文档与性能记录 | 实机对比 |

补充：第 7 批只合并菜单，不把采样数、步数等改成画质档位。用户要求保留现有全部选项与配置兼容，改成档位会删除选项并让旧配置失效；这项留到以后单独决定。第 8 批的实机对比尚未执行，性能记录仍为空表。

每批独立提交，可单独回退。

## 六、进度

- 已完成：`gfx/color.glsl` 建立；ACES、AgX、无压缩、伽马与亮度迁入；`effects/color/color.glsl` 只保留选项、曝光统计与调用；全量 280 组程序编译通过。
- 已完成：`gfx/math.glsl` 建立；曲线、编码、材质、光线求交、噪声与双三次采样迁入，`common/math.glsl` 只保留引擎常数与转发；`gfx/sampling.glsl` 建立，蓝噪声与拜尔抖动改为传入纹理、坐标与帧号。
- 已完成：`gfx/surface.glsl` 建立；方块光曲线、材质遮蔽与法线缩放迁入，`effects/ground/material.glsl` 只保留选项与转发。
- 已完成：`gfx/shadow.glsl` 建立；阴影相机投影、边缘压缩与读取端补压缩迁入，`effects/shadow/shadow.glsl` 只保留同名转发。
- 已完成：`gfx/water.glsl` 建立；六层波高、波法线与水面视差迁入，`effects/water/waves.glsl` 只保留转发与玩家涟漪。
- 已完成：`gfx/atmosphere.glsl` 建立；球面几何、密度剖面与预计算贴图坐标迁入，`effects/sky/atmosphere_model.glsl` 只保留转发。
- 已完成：`gfx/cloud.glsl` 建立，云的光照相位与顶部曲线迁入；`gfx/fog.glsl` 建立，粉末效应与散射相位迁入。
- 已完成：`gfx/cloud.glsl` 增加平面云噪声、扭曲、密度与光照密度，`effects/cloud/planar.glsl` 只保留转发。
- 已完成：`gfx/fog.glsl` 增加三维噪声、高度密度与团雾密度，`effects/fog/volumetric.glsl` 只保留转发。
- 已完成：`gfx/post.glsl` 建立；泛光降采样、轴向高斯与三次升采样迁入，`effects/color/bloom.glsl` 只保留转发。
- 已完成：`gfx/antialias.glsl` 建立；亮度色差转换、历史裁剪与四分量三次采样迁入，`effects/clarity/taa.glsl` 只保留转发。
- 已完成：`gfx/reflection.glsl` 建立；可见法线分布采样迁入，`effects/reflection/screenspace.glsl` 只保留转发。
- 已完成：`gfx/gi.glsl` 建立；环境遮蔽多弹射迁入，`effects/lighting/gtao.glsl` 只保留转发。
- 已完成：`gfx/post.glsl` 增加调色曲线与染色方向归一化，`effects/color/colorgrade.glsl` 只保留转发。
- 已完成：`gfx/post.glsl` 增加暗角，画面纵横比改为参数；`effects/lens/lens.glsl` 只保留转发。
- 已完成：`gfx/weather.glsl` 建立；雨雪随风偏移迁入，`effects/weather/weather.glsl` 只保留转发。
- 已完成：`gfx/weather.glsl` 增加植被判断与季节上色，`effects/weather/season.glsl` 保留编译开关与转发。
- 已完成：`gfx/math.glsl` 增加末地环带径向曲线，`effects/world/end_disc.glsl` 只保留转发。
- 已完成：`gfx/fog.glsl` 增加下界单格雾密度，`effects/world/nether.glsl` 只保留转发。
- 已完成：`gfx/fog.glsl` 增加下界体积雾原始密度，`effects/world/nether.glsl` 只保留转发。
- 已完成：`gfx/math.glsl` 增加三轴旋转矩阵，`effects/world/end_disc.glsl` 只保留转发。
- 已完成：`gfx/fog.glsl` 增加末地三维噪声，`effects/world/end_disc.glsl` 只保留转发。
- 已完成：`gfx/math.glsl` 增加行星曲率下沉公式，`effects/world/planet.glsl` 保留编译开关与转发。
- 已完成：`gfx/fog.glsl` 增加末地涡旋雾形状、光柱、步进与解析雾密度，`effects/world/end_fog.glsl` 只保留选项、远景与抗锯齿分支和入口转发。
- 已完成：`gfx/post.glsl` 增加镜头眩光形状，`effects/lens/glare.glsl` 只保留选项、可见度衰减与入口转发。
- 已完成：`gfx/atmosphere.glsl` 增加星场与绕日轴对齐，`effects/sky/stars.glsl` 只保留颜色分支与入口转发。
- 已完成：`gfx/atmosphere.glsl` 增加日月圆盘与月亮轨道，`effects/sky/sun_moon.glsl`、`moon_orbit.glsl` 只保留尺寸分支与入口转发。
- 已完成：`gfx/weather.glsl` 增加暴风噪声、暴风颜色与每日天气哈希，`effects/weather/storm.glsl`、`dailyweather.glsl` 只保留选项与入口转发。
- 已完成：`gfx/math.glsl` 增加黑洞空间扭曲、`gfx/fog.glsl` 增加云状分形噪声，`effects/world/end_disc.glsl` 只保留同名转发。
- 已完成：`gfx/water.glsl` 增加水洼覆盖与湿面粗糙度，`effects/water/puddle.glsl` 只保留选项与入口转发。
- 已完成：`gfx/post.glsl` 增加景深公式与胶片颗粒，`effects/lens/dof.glsl`、`effects/clarity/grain.glsl` 只保留选项与入口转发。
- 已完成：`gfx/color.glsl` 增加黑边、浦肯野效应、白平衡与高级调色，`effects/color/color.glsl` 只保留选项与入口转发。
- 已完成：`gfx/atmosphere.glsl` 增加天空盒双向投影，`effects/sky/skybox.glsl` 只保留屏幕偏移与入口转发。
- 已完成：`gfx/surface.glsl` 增加矿石与纹饰发光，`effects/lighting/emissive.glsl` 只保留选项与入口转发。
- 已完成：`effects/sky/atmosphere_model.glsl` 的球面几何与密度剖面改为转发通用库，预计算查表未动。
- 已完成：`gfx/atmosphere.glsl` 增加极光与彩虹，`effects/sky/atmosphere.glsl` 只保留选项、太阳方向与闪电。
- 已完成：`gfx/water.glsl` 增加雨雾高光与雨点动画法线，`effects/water/rain.glsl` 只保留调制与入口转发。
- 已完成：`gfx/color.glsl` 增加 HSV 转颜色、sRGB 转线性与饱和度矩阵，`effects/lighting/lpv.glsl` 只保留转发。
- 已完成：`gfx/atmosphere.glsl` 增加行星表面与环带公式，`effects/world/end_sky.glsl` 只保留同名转发。
- 已完成：`bind/` 建立；`time.glsl`、`camera.glsl`、`weather.glsl`、`world.glsl` 把宿主时间、相机、天气与维度转成普通结构体，水面、天气、氛围、天空渲染、云影、泛光、积雪、暴风、水洼、末地与下界已接入。
- 已完成：顶层菜单合并为九页；`options.py` 用 `GROUP_PAGES` 把十五种效果文件夹归入九个入口，快速设置复用常用选项，关于页平铺调试开关，不设“高级”页；选项名、默认值与配置兼容未变。
- 已完成：宿主层行数改为固定口径的实测值。口径：指定目录里的 `.glsl/.vsh/.fsh/.csh/.gsh`，用 `build._code_only` 去掉注释后数非空行；当前 `common/` 240、`bind/` 131、生成入口 `world0/` 608、`world1/` 530、`world-1/` 482，绑定与入口合计 1991 行；`rendering/` 3142 行单独统计。复现命令：
  `python -c "import build;S={'.glsl','.vsh','.fsh','.csh','.gsh'};print({d:sum(1 for p in (build.SHADERS/d).rglob('*') if p.suffix in S for l in build._code_only(p.read_text(encoding='utf-8')).splitlines() if l.strip()) for d in ('common','bind','rendering','world0','world1','world-1')})"`
- 已完成：清理与文档；没有空目录，`gfx/` 没有未引用函数；新增通用库边界测试，检查通用库不出现宿主输入、选项宏、版本声明或宿主文件引用；更新 `gfx/README.md`、`docs/rendering.md` 与 `docs/parity.md`。
- 已完成：`gfx/post.glsl` 增加景深深度换算、弥散范围搜索与散焦合成，`effects/lens/dof.glsl` 只保留选项换算与两次调用。
- 已完成：`gfx/post.glsl` 增加五级泛光链的降采样、轴向高斯与三次升采样合并，`effects/color/bloom.glsl` 只保留程序分支、雨遮罩读取与合并泛光。
- 已完成：`gfx/gi.glsl` 增加反射阴影图反弹、历史重投影、时间滤波与空间滤波，相机参数打包成 `gfx_gi_view`；`effects/lighting/gi.glsl` 只保留阶段分支、选项换算与一次调用。
- 已完成：`gfx/antialias.glsl` 增加当前帧与历史取样、邻域方差、历史裁剪与时间重投影；`effects/clarity/taa.glsl` 只保留相机速度、选项换算与重投影入口。
- 已完成：新增 `gfx/cloud_volume.glsl`，体积云的密度、光照、沿视线步进、闪电与云影迁入通用库；`effects/cloud/volumetric.glsl` 只保留天气换算、附加层编排与空气透视合成。
- 已完成：新增 `gfx/fog_volume.glsl`，体积雾的密度、光照吸收、步进、阴影、云影、闪电、暴风与群系迁入通用库；`effects/fog/volumetric.glsl` 只保留选项换算与一次调用，雾照明用 `GFX_FOG_LPV_STEP` 可选钩子接入。
- 已完成：`gfx/reflection.glsl` 增加屏幕空间追踪的坐标换算、深度取样、远景转换、步进与二分细化；`effects/reflection/screenspace.glsl` 只保留深度图选择与质量选项换算。
- 已完成：`gfx/reflection.glsl` 增加反射合并的菲涅耳、金属度、水吸收与亮度补正，`effects/reflection/screenspace.glsl` 的合成五号入口只做一次调用。
- 已完成：`gfx/reflection.glsl` 增加反射主流程与三个维度的合成结构；天空兜底、体素回退、命中深度、视空间还原与反射雾改用 `GFX_REFLECTION_*` 钩子注入。`effects/reflection/screenspace.glsl` 只保留维度差异与一次调用，非注释行 331 降到 242。
- 已完成：`gfx/cloud.glsl` 增加云影投影、十六像素三次模糊、天气两档混合、全局云影统计与七点高斯模糊；`effects/cloud/shadow.glsl` 只保留宿主相机与选项换算，非注释行 77 降到 36。
- 已完成：`gfx/water.glsl` 增加水雾合成，`effects/water/waterfog.glsl` 只接宿主输入与选项，非注释行 37 降到 10。
- 已完成：`gfx/shadow.glsl` 增加手持光的屏幕空间阴影步进，`effects/lighting/held_light.glsl` 只选步数、深度图与抖动。
- 已完成：新增 `rendering/post_vertex.glsl` 与 `rendering/post_fragment_deps.glsl`，十个后期程序共用整屏顶点与片元依赖；`rendering/` 非注释行从 3287 降到 3188。
- 已完成：新增 `rendering/deferred_cloud_shadow_blur.glsl`，延迟四号与五号共用云影横纵模糊阶段，`rendering/` 非注释行从 3188 降到 3142。
- 已完成：`gfx/surface.glsl` 增加方块光与纹理自发光合成，`effects/lighting/blocklight.glsl` 只保留选项与掩码求和；无调用者的 `CurveBlockLightTorch` 转发已删除。
- 已完成：新增 `gfx/accretion.glsl`，末地吸积盘积分迁入通用库，`effects/world/end_disc.glsl` 只保留步数、噪声与星空；非注释行从 174 降到 26。
- 已完成：`gfx/shadow.glsl` 增加阳光的屏幕空间阴影步进，`effects/shadow/screen_shadow.glsl` 只保留视野、吸收量与噪声；非注释行从 61 降到 30。
- 已完成：`gfx/reflection.glsl` 增加九点小波滤波，`effects/reflection/denoise.glsl` 只传三张输入图与像素大小；非注释行从 48 降到 10。
- 已完成：`gfx/water.glsl` 增加波法线方块读取与水下焦散，`effects/shadow/water_caustics.glsl` 只传七号画面、折射率与两个选项；非注释行从 39 降到 14。
- 已完成：`gfx/shadow.glsl` 增加阴影图视线段的遮挡统计，`effects/fog/landscattering.glsl` 只保留投影与受光距离缩短。
- 已完成：`gfx/post.glsl` 增加自动曝光分块统计，`gfx_exposure_params` 打包场景画面、屏幕尺寸、像素大小、粗估亮度、测光方式、亮度计权与三个维度标记；`effects/color/color.glsl` 只保留粗估亮度、选项换算与一次调用，非注释行从 144 降到 107。
- 已完成：`gfx/fog_volume.glsl` 增加水下焦散与水下体积雾步进，阴影图、波法线图、相机位置、阴影矩阵、光色与选项全部显式传入；`effects/fog/underwater_fog.glsl` 只保留能力换算与一次调用，非注释行从 71 降到 25。
- 已完成：`gfx/post.glsl` 增加相机动态模糊取样，`effects/lens/motion_blur.glsl` 只保留材质深度选择、屏幕位移与一次调用，非注释行从 56 降到 42。
- 已完成：`gfx/gi.glsl` 增加地平线遮蔽的多切片搜索，深度图、投影、画面比例、噪声与画质参数全部显式传入；`effects/lighting/gtao.glsl` 只保留噪声选择与参数打包，非注释行从 122 降到 43。
- 已完成：`gfx/shadow.glsl` 增加可变半影阴影，阴影图、比较采样器、矩阵、分辨率、偏置、噪声与选项全部显式传入；`effects/shadow/shadow.glsl` 只保留噪声选择与一次调用，非注释行从 175 降到 92。
- 已完成：新增 `gfx/parallax.glsl`，高度采样、平滑与锐利视差、自阴影与高度场法线全部移入通用库；`effects/ground/parallax.glsl` 只保留图集分辨率选择、阶段条件与一次调用，非注释行从 249 降到 70。
- 已完成：新增 `gfx/voxel.glsl`，三维逐格步进、半透明染色、铁块镜面弹射与体素着色全部移入通用库；`effects/reflection/voxel.glsl` 只保留容量判断、网格平移与一次调用，非注释行从 93 降到 28。
- 已完成：新增 `bind/gbuffer.glsl`，G 缓冲读取、`Material`/`GbufferData`、材质编号、掩码、粒子修正、labPBR 解码与手部/实体判断移入绑定层；`effects/ground/material.glsl` 只保留选项与原调用名转发，非注释行从 296 降到 90；运动模糊改用 `bind_is_hand_depth` 与 `bind_is_player_id`。绑定与入口合计从 1991 行降到 1973 行。
- 后续可选：`effects/` 里仍有几处成段的步进循环，按风险从低到高依次是海洋物理波与若干采样循环；它们各自带一组游戏选项或多张输入图，迁移前要先定参数接口，不能只搬循环。
- 后续可选：`rendering/deferred_pass0.glsl`、`deferred_pass1.glsl`、`deferred_pass2.glsl` 仍有相似的全局声明块，但每支程序的声明子集与顺序不同，抽模板前要先核对每个阶段的采样器类型，暂不动。
- 后续可选：把 `bind/` 覆盖到其余仍直接读宿主量的效果；已接入的模块已经能独立验证绑定接口，剩余迁移不改变画面，按实际修改需要再做。
- 已完成：`effects/` 全部宿主接线迁出。51 个不带选项的效果文件整体迁到 `bind/` 同名分类目录；46 个带选项的文件拆成“选项层 + 绑定层”，选项层只保留 `@effect`、`@option` 与原生声明，绑定层保留原函数、画面读写和维度分支。`effects/` 非注释代码从 6572 行降到 628 行，519 个选项的名称、默认值、取值与菜单分组未变。
- 已完成：新增 `gfx/planet.glsl`，末地行星本体、光环与大气从绑定层迁入通用库，行星半径、时间、阴影强度与噪声贴图改为参数；`bind/world/end_sky.glsl` 只保留同名转发。`gfx/reflection.glsl` 增加中性反射合成参数，三个维度的默认结构只维护一份。
- 后续可选：把 `rendering/` 里仍可独立的纯计算继续抽到 `gfx/`；优先对象是预计算大气查表、地形各向异性采样、海洋物理波高、体积雾单次散射与抗锯齿采样核。抽离时只改函数名与参数，保持公式不变。
- 已完成（0.1.81）：按角色重新划分四层。`bind/` 只留 7 个输入适配文件（相机、时间、天气、世界、G 缓冲、材质解码、群系）；其余 95 个文件整体移到 `rendering/` 的同名相对路径，作为阶段片段，不改函数体、调用顺序与选项；引入标记同步改为 `OMNI_RENDER_*`。四层非注释行：`bind/` 461、`rendering/` 9054、`gfx/` 3655、`effects/` 628，合计 13798 行，与迁移前完全相同（只移动，不删代码）。`effects/` 46 个文件、519 个选项名称与默认值未变。
- 已完成（0.1.82）：`gfx/atmosphere_model.glsl` 建立；预计算大气的坐标映射、透过率、组合散射、辐照度与天空辐射从 `rendering/sky/atmosphere_model.glsl` 迁入，常数打包成 `gfx_atmosphere_model`，预计算贴图与色适应矩阵改为参数；阶段文件保留原函数名与签名，只做参数填充与采样器选择。天空公式、调用点与默认画面未变。
- 当前判断：`bind/` 已经从“效果实现存放处”收敛为输入适配层；`rendering/` 承担了阶段片段，体积偏大但每个文件都能说明它在哪个阶段被调用。下一步按域把阶段片段里的纯公式抽到 `gfx/`，并从 `rendering/` 的扁平程序主体里删掉重复声明。
- 已完成（0.1.83）：`gfx/upscale.glsl` 建立；边缘方向重采样、十字对比度锐化与放大后锐化从 `rendering/clarity/upscale.glsl` 迁入，采样器、画面尺寸、锐化量与降噪开关全部改为参数；阶段文件保留 `FsrEasu`、`FidelityFX_CAS`、`FidelityFX_FSR1` 三个名字，只选画面与选项。
- 已完成（0.1.84）：`bind/` 去掉对 `rendering/` 的反向引用。视差与材质水洼锐度所需的选项改为在绑定文件里直接读效果层定义；`rendering/terrain.glsl` 与 `rendering/entities.glsl` 在真正调用 `ParallaxOcclusionMapping` 的地方显式引入视差片段。绑定层现在只引用 `common/`、`gfx/` 与 `effects/`。
- 已完成（0.1.85）：新增 `rendering/deferred_shared.glsl` 合并延迟零号到二号的重复片元声明，新增 `rendering/water/caustics_vertex.glsl` 合并焦散顶点；合成三号与四号合并为 `rendering/composite_filter_pass.glsl`，景深与泛光六支程序合并为 `rendering/post_effect_pass.glsl`；`rendering/clarity/taa.glsl` 删除重复的近景深度取样。新增 `docs/structure-audit.md` 逐个标注 136 个渲染文件的角色。`rendering/` 从 8711 行降到 8577 行，四层合计从 13838 行降到 13704 行。
- 已完成（0.1.86）：`gfx/water.glsl` 增加 `gfx_water_refraction_coord`，主世界、末地与下界三份重复的折射坐标改为一次参数化调用；新增 `rendering/sky/cloud_stage.glsl` 合并延迟七号与八号的云参数推导；手电筒指向平滑抽成 `FlashlightAimDirection`。`rendering/` 从 8577 行降到 8524 行，`gfx/` 从 4039 行升到 4057 行，四层合计从 13704 行降到 13669 行。
- 已完成（0.1.87）：`gfx/math.glsl` 增加 `gfx_tangent_basis`，实体、地形、水面与覆盖层五处切线基推导改为一次调用；延迟三号与八号改用 `deferred_shared.glsl`。`rendering/` 从 8524 行降到 8446 行，`gfx/` 从 4057 行升到 4066 行，四层合计从 13669 行降到 13600 行。
- 当前固定口径（0.1.87）：`bind/` 460 行（7 个文件）、`rendering/` 8446 行（137 个文件）、`gfx/` 4066 行（22 个文件）、`effects/` 628 行（46 个文件），四层合计 13600 行；生成入口 `world0/` 608、`world1/` 530、`world-1/` 482。复现命令：
  `python -c "import build;S={'.glsl','.vsh','.fsh','.csh','.gsh'};print({d:sum(1 for p in (build.SHADERS/d).rglob('*') if p.suffix in S for l in build._code_only(p.read_text(encoding='utf-8')).splitlines() if l.strip()) for d in ('common','bind','rendering','gfx','effects','world0','world1','world-1')})"`
- 验证边界：`audit`、`verify`、全量 `compile` 与 GitHub Actions 通过；按用户要求未启动 Minecraft，游戏内画面、菜单逐页与性能仍未验证。另用 8 个代表入口比较重构前后的展开代码，去注释、引用与声明后语句集合完全一致。
- 已完成（0.16.0-dev.6）：按效果唯一归属重排。98 个按效果命名的阶段片段从 `rendering/<页>/` 移回 `effects/<页>/`，44 个选项文件与同名实现合并；`bind/ground/material.glsl` 的材质解码并入 `effects/ground/material.glsl`；`rendering/` 只留 42 个程序主体与阶段胶水。选项仍为 519 个、入口 269 个、唯一程序 280 组、测试 160 个；只移动与合并，没有删除效果、选项、默认值或测试。新口径：`bind/` 385 行（6 个文件）、`rendering/` 2941 行（41 个文件）、`effects/` 6250 行（101 个文件）。
- 已完成（0.16.0-dev.7）：删除 `shaders/gfx/` 纯转发层。248 个直通函数改为直接调用生成的 `ogx` 名字，泛光链排布、反射主流程、切线基与视差调用放回所属效果或 `common/`；效果文件直接 `#include "/omni-gfx/..."`。生成 GLSL 只保留 `shaders/omni-gfx/` 一份，删除 `omni-gfx/generated/glsl/` 镜像。选项 519 个、入口 269 个、唯一程序 280 组、测试 160 个不变；`effects/` 6490 行（99 个文件），`rendering/` 2992 行（43 个文件）。`post_shared` 与 `caustics_vertex` 属于阶段胶水，已回到 `rendering/`。验证：`audit` 通过 447 个代码文件，`verify` 通过 160 个测试、9 组探针与打包，`compile` 通过 280 组唯一程序，`strict-parity` 为 474 exact / 5 reference_broken / 26 mc_glue / 0 missing，`profiles` 两份通过。
