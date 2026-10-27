# Eclipse 上游源码核对：损坏参考的恢复结论

本文件记录一次可复核的查证：`references/Eclipse` 里有 5 个函数因缺少声明而无法编译，
用户要求到上游仓库恢复定义。结论是上游同一版本也没有这些定义，因此这 5 条保持
`reference_broken`，不伪造 `exact`。下面写清版本、URL、字节证据与许可证，后续会话
不必重复查证。

## 参考包对应的上游版本

`references/Eclipse` 与上游提交 **`26cfc431a9066a87040272fa0ae016ab88c06b9d`** 逐字节一致。

- 仓库：<https://github.com/Merlin1809/Eclipse-Shader>
- 提交：<https://github.com/Merlin1809/Eclipse-Shader/commit/26cfc431a9066a87040272fa0ae016ab88c06b9d>
- 提交时间：2026-04-10T14:03:17Z
- 提交说明：`fix https://github.com/Merlin1809/Eclipse-Shader/issues/152`
- 分支：`Unstable`（仓库默认分支）

核对方法：对本地文件计算 Git 对象哈希（`git hash-object`），再与 GitHub 树接口
`git/trees/26cfc431...?recursive=1` 返回的同路径哈希比较。7 个文件全部相同，说明
本地参考不是另一个版本，也不是被手工改过的副本。

| 文件 | Git 对象哈希 | 字节 |
| --- | --- | --- |
| `shaders/lib/specular.glsl` | `2ebef7411b9fe3271153134eb9b1027ec287522e` | 108475 |
| `shaders/lib/settings.glsl` | `8f30ef1ec0f7f121cd5bf881a41187fa04e7df80` | 145452 |
| `shaders/lib/volumetricClouds.glsl` | `e3cdf67f673cff46f5f380b032a874e937c0376a` | 56023 |
| `shaders/lib/SSBOs.glsl` | `032503297bae3f15a928cd670c30d8b4ba868da5` | 1350 |
| `shaders/shaders.properties` | `df2296de27c0272c105a1bfc5a1b4a7c8c91ec93` | 80899 |
| `shaders/lib/voxel_common.glsl` | `184d92ffc7b2de18b1de16d80a725145b0d06be2` | 698 |
| `shaders/photonics/photonics.glsl` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | 0 |

`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` 是 Git 的空文件对象，不是下载失败。

## 五条 reference_broken 的上游证据

### `trace_wsr` 与 `photonicsReflection`

- 参考正文在 `shaders/lib/specular.glsl:1212` 之后，外层条件是
  `#if defined PHOTONICS_INCLUDED && defined PHOTONICS && defined VOXEL_REFLECTIONS`。
- 它们调用的 `ph_intersects_world`、`ph_get_world_index`、`ph_is_inside`、`ph_get_index`
  与 `RayJob` 字段，本应来自 `shaders/photonics/photonics.glsl`。
- 该文件在上述提交里是 0 字节。原始内容 URL 返回空响应：
  <https://raw.githubusercontent.com/Merlin1809/Eclipse-Shader/26cfc431a9066a87040272fa0ae016ab88c06b9d/shaders/photonics/photonics.glsl>
- 该路径在整个仓库历史里只有一个提交碰到过：
  `dac7baa85eae7f0433fa417b03ba5ff3fd0201cb`（2026-02-21，提交说明
  “Add photonics API support, add photonics WSR...”。该提交里的文件同样是 0 字节：
  <https://github.com/Merlin1809/Eclipse-Shader/commit/dac7baa85eae7f0433fa417b03ba5ff3fd0201cb>
- 因此这些定义不来自 Eclipse 仓库，而来自外部的 Photonics 模组（Iris 扩展）。
  Modrinth 页面标注许可为 **ARR（保留所有权利，闭源）**：
  <https://modrinth.com/project/MNlxJdtO>
- 结论：上游 Eclipse 不可得；Photonics 侧即使可安装也不能作为可复制的参考源码。
  Omni 的实现按可执行语义用显式体素纹理重写，保留 `reference_broken`。

### `GetVoxelData`、`GetTexCoord` 与依赖它们的 `sortIntersectionCutout`

- 三者读取 `voxelData`，唯一声明在 `shaders/lib/voxel_common.glsl:5-7` 与 `:12-14`，
  以 `//` 整段注释。上游同提交的原始文件内容相同：
  <https://raw.githubusercontent.com/Merlin1809/Eclipse-Shader/26cfc431a9066a87040272fa0ae016ab88c06b9d/shaders/lib/voxel_common.glsl>
- 更早的 `voxel_common.glsl` 版本（例如
  `de987d9aebe9d40e2ead080b3a5b649d922ab041`，2024-06-11）根本没有 `voxelData`：
  <https://raw.githubusercontent.com/Merlin1809/Eclipse-Shader/de987d9aebe9d40e2ead080b3a5b649d922ab041/shaders/lib/voxel_common.glsl>
- 因此不存在“从上游某版本恢复被注释的 SSBO 声明”这条路：上游从未发布过启用状态。
- 另外，读取它们的代码整段包在
  `#if defined VOXEL_REFLECTIONS && defined IS_LPV_ENABLED && defined adjnjawudiuwad`
  （`specular.glsl:261`）。`adjnjawudiuwad` 在整包源码里只出现这一次，从未定义，
  说明作者把这条路当成废弃分支；正常编译时这段被预处理器整段删除。
- 结论：参考正文在真实构建里不可达，单文件提取也无法补出类型与布局。保持
  `reference_broken`，实现用显式体素面纹理承接同一 `[voxelIndex][normalIndex]` 布局。

### `GetVolumetricClouds`（本轮已解决，不再是 reference_broken）

这一条不是缺声明，而是采样次数未对齐。按台账的参考宏配置
（`CLOUDSHADOWSONLY=0`、`CloudLayer0..3`、`CUMULONIMBUS=1`、`CLOUD_SAMPLES=10`、
`SKY_GROUND`、`AURORA_LOCATION=1`、`TERRAIN_SHADOW_ON_CLOUDS`，普通主世界程序
`AETHER_FLAG=0`）展开：

- 首次天空盒查表 `skyFromTex`：1 次
- 小积云、大积云、高层云、卷云各 1282 次，共 4 层
- 积雨云 2492 次（`2 × CLOUD_SAMPLES`）
- 合计 7621 次

实现侧补上两处差异后同为 7621 次：

1. 参考在 `AURORA_LOCATION > 0` 时把上层遮挡形状放进步进循环，每个样本重算一次；
   实现原来放在循环外，少 9 次 `getCloudShape`（每层 135 次采样）。
2. 参考在步进前自己查天空盒；实现改为调用 `ogxEclipseSkyFromTex`，补回 1 次采样，
   并补上参考的 `SKY_GROUND` 间接光混合。

逐层直接子调用的顺序与次数也已核对：第 0、1、3、4 层各 73 次，积雨云 143 次，
参考与实现完全相同。核对脚本只在开发目录使用，不进入交付。

## 许可证

- `references/Eclipse/LICENSE.md` 第一行：`© 2020 Chocapic13. All rights reserved.`
- GitHub 仓库接口的 `license` 字段为 `null`，没有开源许可证。
- Photonics 模组在 Modrinth 标注 `ARR`。
- 因此上游文件只能用于对照阅读，不能复制进公开发行物。本轮没有修改
  `references/Eclipse` 下的任何原件，也没有把上游代码复制进 `shaders/`。

## 复核命令

```text
python omni-gfx/build.py strict-parity
python omni-gfx/build.py profiles
python build.py audit
python build.py verify
python build.py compile
```

严格对照的逐条结果在 `omni-gfx/tools/parity_report.json`，中文摘要由
`docs/gfx-functions-strict.md` 自动生成。
