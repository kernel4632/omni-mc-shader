# SPIR-V 产物

这个目录存放本机生成的 SPIR-V 与清单。`README.md` 本身提交到仓库；`*.spv` 与 `manifest.json` 由忽略规则排除，不提交，换机器后重新生成。

生成命令：

```powershell
python omni-gfx/build.py spirv --download
python omni-gfx/build.py spirv
```

- `*.spv`：每个生成模块一个编译探针，共 44 个；用来证明 Slang 源能生成 SPIR-V，不是可直接运行的 Vulkan 管线。
- `manifest.json`：编译器版本、文件大小与 SHA-256，由生成命令自动刷新。

4 个参考后端（`cloud/layers`、`reflection/wsr`、`reflection/photonics`、`reflection/specular`）只保留源码供严格对照，不生成 GLSL 与 SPIR-V。探针只验证模块能编译，完整 Vulkan 管线在后续阶段接入。
