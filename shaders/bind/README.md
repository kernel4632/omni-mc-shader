# bind：Minecraft 输入转通用参数

这个目录只做一件事：把加载器提供的全局输入（时间、相机、天气、维度、光照方向）整理成普通结构体和普通数值，再交给 `shaders/gfx/` 的通用库。效果文件因此不需要直接记住 `worldTime`、`gbufferModelView` 这类宿主名字，通用库也不需要认识 Minecraft。

## 文件

| 文件 | 内容 |
| --- | --- |
| `time.glsl` | 累计秒数、帧时间、帧序号、世界天数、太阳角度 |
| `camera.glsl` | 投影与视图矩阵、画面尺寸、像素大小、抖动、相机位置 |
| `weather.glsl` | 降雨湿润度、眼睛亮度、夜视、失明、黑暗、脚下介质、雪与降水标记 |
| `world.glsl` | 维度编号、世界空间太阳方向、阴影光源方向与阴影矩阵 |

## 用法

```glsl
#include "/bind/time.glsl"

OmniTime time = bind_time();
float seconds = time.seconds;
```

## 约定

- 结构体只放数值和矩阵，不放采样器、选项宏或加载器专用的名字。
- 函数统一 `bind_` 前缀，一次读取一组宿主输入，不做业务计算。
- 每个绑定文件自己引入 `common/uniforms.glsl`，调用方不必记引入顺序。
- 新增宿主输入时先在这里出现一次，效果文件再从绑定结构里取值。

## 边界

这里仍然是 Minecraft 专属代码，和 `gfx/` 可以独立发布的约定不同。`bind/` 与 `common/` 一起构成宿主层，`gfx/` 只接收这里的输出。
