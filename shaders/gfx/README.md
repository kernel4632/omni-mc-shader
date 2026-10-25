# omni-gfx 适配层

这个目录不再保存算法实现。所有算式都在仓库根目录的 `omni-gfx/src/*.slang`，
构建时生成 GLSL 330 到 `shaders/omni-gfx/`，本目录的文件只保留旧函数名、旧宏与转发。

## 为什么保留这一层

光影里有几百处调用点使用 `gfx_` 名字。适配层让调用点完全不动，默认画面不漂移；
算式只留一份，改算法时只需要改 Slang 源并重新生成，不会出现两套实现各自漂移。

## 约束

- 本目录只允许 `#include` 生成库与同目录适配层，不写算式、常数或循环。
- 函数名、参数顺序与输出参数保持旧签名；结构体用宏接到生成库的类型上，字段名不变。
- 纯宿主布局可以留下：五级泛光的子图排布、反射主流程里的天空与体素钩子、
  镜面反射的合成顺序都属于光影阶段约定，迁进通用库会把宿主布局写死。
- 本目录的文件由 `tests/test_omni_gfx.py` 与 `tests/test_gfx.py` 检查引用边界。

## 模块

| 适配层 | 生成库里的实现 |
| --- | --- |
| `math.glsl` | 曲线、编码、材质、求交、噪声、双三次采样、矩阵工具 |
| `color.glsl` | 伽马、ACES、AgX、高级调色、暗视觉、白平衡、饱和度矩阵 |
| `sampling.glsl` | 蓝噪声、时间抖动、拜尔抖动 |
| `surface.glsl` | 方块光曲线、材质法线与遮蔽、自发光 |
| `atmosphere.glsl` | 球面几何、密度剖面、星场、日月圆盘、天空盒投影、极光彩虹、行星表面 |
| `atmosphere_model.glsl` | 预计算大气的坐标映射、透过率、散射、辐照度与简化散射 |
| `planet.glsl` | 末地行星本体、光环与大气 |
| `accretion.glsl` | 黑洞吸积盘积分、空间扭曲与盘着色 |
| `parallax.glsl` | 高度图采样、平滑与锐利视差、自阴影 |
| `cloud.glsl` | 云相位、平面云形状与云影 |
| `cloud_volume.glsl` | 体积云形状、光照、步进与云影贴图 |
| `fog.glsl` | 粉末效应、相位、高度雾、团雾、下界与末地雾、云状分形噪声 |
| `fog_volume.glsl` | 体积雾密度、光照吸收、步进、闪电、暴风与水下光柱 |
| `water.glsl` | 波高、波法线、视差、折射坐标、水洼、雨点、水体雾与焦散 |
| `weather.glsl` | 雨雪偏移、季节、暴风与每日天气哈希 |
| `voxel.glsl` | 三维逐格步进、半透明染色与镜面弹射 |
| `upscale.glsl` | 边缘方向重采样、对比度自适应锐化 |
| `shadow.glsl` | 阴影投影、屏幕空间阴影、级联与 PCSS |
| `gi.glsl` | 地平线遮蔽、反射阴影图反弹、时间与空间滤波 |
| `reflection.glsl` | 屏幕空间追踪、菲涅耳合并与降噪 |
| `post.glsl` | 泛光核、景深、颗粒、测光与眩光 |
| `antialias.glsl` | YCoCg、历史裁剪与时间重投影 |

## 重新生成

```text
python omni-gfx/build.py generate
python omni-gfx/build.py check
```
