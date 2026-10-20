# 通用库与菜单重构计划

这份文件回答三件事：通用库怎么分、Minecraft 层留多少代码、菜单怎么归类。
调用位置：改动结构、拆分算法或调整菜单前先读；进度变化时更新第六节。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：算法进通用库，Minecraft 层只做接线；不设“高级”页，每个选项归入所属效果。

## 一、目标

- Minecraft 专属代码控制在约 2000 行非注释代码。
- 通用图形算法放 `shaders/gfx/`，不读取任何 Minecraft、Iris 或全局 uniform，可单独发布。
- 效果数量不减少，默认画面与现在一致；不能为了减行数删效果或改观感。
- 选项可以精简，但必须归入所属页面，不设“高级”总入口。

## 二、目录

```
shaders/
├─ gfx/                        通用库，可独立发布
│  ├─ color.glsl              颜色、伽马、ACES、AgX、无压缩
│  ├─ math.glsl               曲线、重映射、编码
│  ├─ sampling.glsl           蓝噪声、抖动、采样
│  ├─ surface.glsl            材质与双向反射分布
│  ├─ atmosphere.glsl         大气散射与天空辐照
│  ├─ cloud.glsl              云的形状、密度与光照
│  ├─ water.glsl              波形、折射、焦散
│  ├─ fog.glsl                高度雾与体积散射
│  ├─ shadow.glsl             阴影采样与半影
│  ├─ gi.glsl                 环境遮蔽与全局光
│  ├─ reflection.glsl         屏幕空间与体素反射
│  ├─ post.glsl               泛光、景深、运动模糊、眩光
│  └─ antialias.glsl          时间抗锯齿、边缘平滑、放大
│
├─ bind/                       Minecraft 数据 → 通用库结构体
├─ effects/                    每个效果一个文件，只保留选项、调用与输出
├─ rendering/                  每个程序一份依赖清单与绘制顺序
├─ common/                     加载器输入、坐标与管线编码
└─ world0/ world1/ world-1/    生成的薄入口
```

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
- 下一步：建 `bind/`，把宿主数据整理成通用库参数，再整理菜单。
- 尚未开始：`bind/`、菜单合并、效果文件行数压缩。
