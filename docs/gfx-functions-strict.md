# 严格函数对照：iterationT、Eclipse 与 omni-gfx

本文件由 `python omni-gfx/build.py strict-parity` 生成。机器可读版本在
`omni-gfx/tools/parity_report.json`，字段名固定为 ASCII。

## 结论

- 参考函数共 505 个；算法函数 481 个。
- exact：481 个；approximate：0 个；mc_glue：24 个；missing：0 个。
- exact 覆盖率（按算法函数）：100.0%。

| 参考包 | exact | approximate | mc_glue | missing |
| --- | --- | --- | --- | --- |
| iterationT | 234 | 0 | 6 | 0 |
| Eclipse | 247 | 0 | 18 | 0 |

## 未达 exact 的函数

| 函数 | 包 | 状态 | 当前承接 | 差异 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `main` | iterationT | mc_glue | — | 就绪：程序入口，只负责阶段组合 | `references/iterationT/shaders/Lib/BasicFounctions/TAA.glsl:331` |
| `title` | iterationT | mc_glue | — | 就绪：标题计数与屏幕文字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/MotionBlur.glsl:100` |
| `SevenSegment` | iterationT | mc_glue | — | 就绪：调试叠加字形表，只服务屏幕数字 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:48` |
| `DecimalPoint` | iterationT | mc_glue | — | 就绪：调试叠加小数点定位 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:93` |
| `PrintFloat` | iterationT | mc_glue | — | 就绪：屏幕调试数字，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:99` |
| `PrintUintBinary` | iterationT | mc_glue | — | 就绪：屏幕调试二进制，不参与画面效果 | `references/iterationT/shaders/Lib/IndividualFounctions/PrintFloat.glsl:218` |
| `BiomeVLFogColors` | Eclipse | mc_glue | — | 就绪：原版群系枚举到颜色表，非算法 | `references/Eclipse/shaders/lib/climate_settings.glsl:151` |
| `beginText` | Eclipse | mc_glue | — | 就绪：调试文字叠加的初始化 | `references/Eclipse/shaders/lib/text_rendering.glsl:161` |
| `endText` | Eclipse | mc_glue | — | 就绪：调试文字叠加的合成 | `references/Eclipse/shaders/lib/text_rendering.glsl:175` |
| `printChar` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:179` |
| `printUnsignedInt` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:212` |
| `printInt` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:244` |
| `printFloat` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:249` |
| `printBool` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:269` |
| `printVec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:277` |
| `printVec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:282` |
| `printVec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:289` |
| `printIvec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:299` |
| `printIvec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:304` |
| `printIvec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:311` |
| `printUvec2` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:321` |
| `printUvec3` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:326` |
| `printUvec4` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:333` |
| `printLine` | Eclipse | mc_glue | — | 就绪：调试文字叠加 | `references/Eclipse/shaders/lib/text_rendering.glsl:343` |

## 重新生成

```text
python omni-gfx/build.py strict-parity
```
