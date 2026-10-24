# SPIR-V 产物

这个目录存放本机生成的 SPIR-V 与清单，不提交到仓库。

生成命令：

```powershell
python omni-gfx/build.py spirv --download
```

- `math.spv`、`color.spv`、`sampling.spv`：每个模块的编译探针，用来证明 Slang 源能生成 SPIR-V。
- `manifest.json`：编译器版本、文件大小与 SHA-256，由生成命令自动刷新。

探针不是可直接运行的 Vulkan 管线。完整管线的 SPIR-V 接入在阶段 5 处理。
