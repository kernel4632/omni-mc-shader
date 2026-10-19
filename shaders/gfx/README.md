# omni-gfx

与 Minecraft 无关的 GLSL 图形库，目标是可以单独复制到其他 OpenGL / Vulkan 项目使用。

## 约束

- 不读取任何 `OMNI_*` 选项、Minecraft uniform、Iris 中间画面或纹理。
- 只接收显式参数，返回纯计算结果。
- 函数名统一使用 `gfx_` 前缀，避免与宿主工程重名。
- 不在这里写 `#version`；由宿主程序决定 GLSL 版本，当前按 GLSL 330 编写。
- 只依赖 GLSL 内建函数，不依赖本仓库其他文件。

## 当前模块

| 文件 | 内容 |
| --- | --- |
| `color.glsl` | 线性颜色、亮度、伽马、ACES、AgX、无压缩 |

## 用法

```glsl
#include "/gfx/color.glsl"

vec3 display = gfx_agx(linearColor, 13.0, true);
```

## 发布

这个目录可以整体复制成独立仓库。许可证由仓库所有者决定，发布前必须补上。
