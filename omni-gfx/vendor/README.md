# 第三方代码

当前 `omni-gfx/vendor/` 没有第三方源码。

开发期使用但不随库分发的依赖：

| 名称 | 用途 | 位置 | 说明 |
| --- | --- | --- | --- |
| Slang | 编译 Slang 源、生成 SPIR-V | `.dev/tools/slang/` | 本机下载，不入仓库 |
| GLFW | 测试世界窗口与输入 | Python 虚拟环境 | 开发依赖 |
| PyOpenGL | 测试世界与 GPU 测试的 OpenGL 调用 | Python 虚拟环境 | 开发依赖 |

第三方代码进入 `vendor/` 时必须同时保留 LICENSE、来源地址与版本，并在 `omni-gfx/docs/architecture.md` 记录接入原因。当前没有需要列入 `THIRD_PARTY.md` 的随包第三方文件。
