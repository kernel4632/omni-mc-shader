# 文件结构与共用层重构计划

这份文件回答两件事：项目最后应该长什么样，以及从现在的结构怎么一步一步搬过去。
调用位置：任何结构调整前先读本文件；进度变化时更新第六节。
可复制示例：`python build.py audit`、`python build.py verify`、`python build.py compile`。
关键取舍：不按“一个效果一个文件夹”摆放，也不把选项拆成单独文件；按主体平铺，共用层尽量厚。

## 一、现状（2026-10-18 实测）

| 项目 | 数量 | 说明 |
| --- | --- | --- |
| 玩家可见效果 | 46 个 | 每个带一条 `@effect` 说明，对应菜单里的一个效果 |
| `effects/` 文件 | 97 个 | 46 个效果 + 51 个实现碎片（入口、子算法、逐维度变体） |
| 效果之间的 include | 81 处 | 天空引用云、泛光引用水、抗锯齿引用材质等 |
| 效果引用公共头 | 77 处 | 每个效果各自 include `uniforms`/`math` |
| 单个程序展开 | 最多约 12MB | `composite5`，其中同一文件平均出现 20 次 |
| 绘制程序文件 | 约 30 个 | 按阶段拆开，只排顺序，不是效果 |

结论：效果不多，文件多来自“按实现步骤拆分”。下一步是合并碎片、加厚共用层、把依赖改成每个程序一份清单。

## 二、目标目录

```
shaders/
├─ common/                     纯计算与加载器输入，不含任何效果业务
│  ├─ uniforms.glsl            所有加载器输入、屏幕坐标、全局量（唯一声明处）
│  ├─ math.glsl                曲线、编码、区间重映射
│  ├─ coordinates.glsl         坐标与深度换算
│  └─ noise.glsl               噪声、蓝噪声、抖动
│
├─ shared/                     两项以上效果共用、不属于单独页面的渲染积木
│  ├─ material.glsl            材质采样：底色、法线、粗糙度、金属、自发光、遮蔽
│  ├─ water_waves.glsl         水面波形、法线、焦散采样
│  ├─ cloud_shape.glsl         云的形状、密度、噪声
│  ├─ light_color.glsl         太阳、月亮、天光、火把的取色与辐照
│  ├─ shadow_sample.glsl       阴影贴图坐标、偏移、可见性
│  └─ ssr_trace.glsl           屏幕空间射线步进与命中判定
│
├─ effects/                    页面文件夹里直接平铺效果文件；一个效果一个文件
│  ├─ sky/
│  │  ├─ atmosphere.glsl       大气与天空辐照
│  │  ├─ sky.glsl              天空主流程（合并原 skyrender、stars、moon_orbit、skybox）
│  │  ├─ skyscatter.glsl       天空散射系数
│  │  └─ suncolor.glsl         太阳颜色与辐照
│  ├─ cloud/
│  │  └─ cloud.glsl            低空积云、体积云、平面云、云影（合并原四份文件）
│  ├─ fog/
│  │  └─ fog.glsl              体积雾、水下雾、洞穴与边界雾、地表散射、时段雾
│  ├─ water/
│  │  ├─ water.glsl            水面主流程、雨点、折射、水雾、焦散
│  │  ├─ puddle.glsl           水洼
│  │  └─ wavesim.glsl          波浪模拟
│  ├─ ground/
│  │  ├─ material.glsl         地表材质（引用 shared/material）
│  │  ├─ terrain_surface.glsl  地表采样与视差
│  │  ├─ grass.glsl            程序化草
│  │  ├─ vegetation.glsl       植物摆动
│  │  └─ selection.glsl        选中框
│  ├─ lighting/
│  │  ├─ ambient.glsl          环境光、全局光、缝隙暗部
│  │  ├─ blocklight.glsl       方块光与手持光
│  │  ├─ emissive.glsl         自发光矿石与纹饰
│  │  ├─ lpv.glsl              光传播体积
│  │  └─ sunlight.glsl         日光、月光与天光照明
│  ├─ shadow/
│  │  └─ shadow.glsl           阴影、屏幕阴影、水下焦散、透光
│  ├─ reflection/
│  │  ├─ reflection.glsl       反射主流程与降噪
│  │  └─ voxel.glsl            体素反射
│  ├─ color/
│  │  ├─ color.glsl            颜色、曝光、色调映射
│  │  ├─ bloom.glsl            光晕
│  │  └─ colorgrade.glsl       色彩分级
│  ├─ lens/
│  │  ├─ lens.glsl             镜头主流程、景深、眩光、动态模糊
│  │  ├─ distortion.glsl       镜头形变
│  │  ├─ hurt.glsl             受伤与镜头发水
│  │  └─ title.glsl            标题标志
│  ├─ clarity/
│  │  ├─ antialiasing.glsl     时间抗锯齿与边缘平滑
│  │  ├─ upscale.glsl          放大与锐化
│  │  ├─ chunkfade.glsl        区块淡入
│  │  └─ grain.glsl            胶片颗粒
│  ├─ weather/
│  │  ├─ weather.glsl          天气主流程
│  │  ├─ dailyweather.glsl     每日天气
│  │  ├─ season.glsl           季节
│  │  ├─ snow.glsl             积雪
│  │  └─ storm.glsl            雪暴与沙暴
│  ├─ entity/entity.glsl       生物与玩家
│  ├─ world/
│  │  ├─ nether.glsl           下界光照与雾
│  │  ├─ end.glsl              末地天空、圆盘、雾、主岛光与反射
│  │  ├─ biome.glsl            每群系环境
│  │  ├─ planet.glsl           行星曲率
│  │  ├─ distant.glsl          远景附加能力
│  │  └─ world.glsl            远景剔除与噪声
│  └─ dev/debug.glsl           调试视图与计时
│
├─ rendering/                  只排绘制顺序，不写效果算法
│  ├─ programs.json            程序清单
│  ├─ pipeline.properties      加载器设置与贴图
│  ├─ buffers.glsl             共享画面协议
│  ├─ buffers_main.glsl / buffers_nether.glsl / buffers_end.glsl
│  ├─ inputs.glsl              每个程序共用的输入与输出声明
│  ├─ composite/composite0.glsl … composite5.glsl
│  ├─ deferred/deferred0.glsl … deferred8.glsl
│  ├─ post/post6.glsl … post16.glsl
│  └─ terrain.glsl / entities.glsl / translucent.glsl / shadow.glsl
│     / overlay.glsl / distant.glsl / celestial.glsl / final.glsl
│     / lights.glsl / lpv.glsl / watersim.glsl
│
├─ world0/ world1/ world-1/    生成的薄入口（253 个，不手写）
├─ texture/ lang/              贴图与生成的翻译
└─ block.properties / entity.properties / item.properties
```

目标数量：效果文件约 46 个（重大且职责能一句话分开的，如星空、月亮轨道，可保留为独立主体，最多 +6）；共用模块 6 个；公共计算 4 个；绘制程序约 30 个。

## 三、结构规则

1. **一个效果一个文件**，选项、算法、菜单说明都在同一个文件里；不再有 `*.options.glsl`。
2. **效果文件不 include 其他效果**，也不 include `common/` 或 `shared/`；依赖由每个程序顶部的一份清单声明。
3. **共用层加厚**：两个以上效果在用、且改它不影响某个效果的选项语义，才进 `shared/` 或 `common/`。
4. **不为单个效果建子文件夹**；页面文件夹只用来分页，里面直接平铺效果文件。
5. **绘制阶段按程序分文件夹**（`composite/`、`deferred/`、`post/`），因为它们是不同的绘制程序，不是同一个效果的分层。
6. **每个程序只有一份依赖清单**：先 `common/`，再 `shared/`，再本程序用到的效果，每个一次，按依赖顺序；出现循环依赖直接报错。
7. 名字用普通词；文件名不重复所在文件夹已经说明的上下文（不再有 `sky/sky.glsl` 这种嵌套）。
8. 合并后单文件超过约 600 行、且职责能一句话分开时，才拆成两个独立主体并各写 `@effect`。

## 四、迁移批次

| 批次 | 内容 | 验收 |
| --- | --- | --- |
| 1 | 建 `shared/` 六个模块，把材质、水面波形、云形状、取色、阴影采样、屏幕追踪从效果文件搬进去 | 原有效果文件只调用共用模块；编译通过 |
| 2 | `sky`、`cloud`、`fog`、`water` 合并碎片，改成每程序一份清单 | 展开体积明显下降；画面不变 |
| 3 | `lighting`、`shadow`、`reflection` 合并碎片并接入共用模块 | 同上 |
| 4 | `color`、`lens`、`clarity` 合并碎片 | 同上 |
| 5 | `weather`、`world`、`entity`、`dev` 合并碎片 | 同上 |
| 6 | 删除空目录与未被引用的文件，更新 `docs/rendering.md`、`docs/parity.md`，跑全量编译与性能复测 | `verify`、`compile` 通过；展开体积与重载时间记录在案 |

每批内部顺序：先搬共用代码 → 再合并效果文件 → 再改程序清单 → 最后删旧文件。每批独立提交，可单独回退。

## 五、验证与回滚

- 每批跑 `python build.py audit`、`verify`、`compile`；批次 2 起另用 `build.expand` 统计每个程序的展开体积与重复次数。
- 画面相关改动必须进游戏看同一场景；离线通过不算完成。
- 对外接口（选项名、默认值、菜单页面、预设格式）保持不变；必须改时先写迁移说明。
- 任一批次导致画面变化，先停在上一批，不继续叠加。

## 六、进度

- 已完成：按程序拆分合成、延迟、后期（31MB → 12MB）；动态模糊默认关闭；选项标签第一轮精简。
- 进行中：共用层抽取与效果文件合并尚未开始。
- 下一步：批次 1（`shared/` 六个模块）。
