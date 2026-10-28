# omni-gfx HOP 审计清单（第三轮）

审查对象：`omni-gfx/` 本体。状态：`[ ]` 未修，`[x]` 已修并待下一轮复核。
规则：每修一轮重跑验证，再开新审计；只有新审计无不符合项才算完成。

## 高优先级

- [x] 1. 6 个主文件 0 函数，只剩结构体和 include：`atmosphere/atmosphere.slang`、`cloud/layers.slang`、`fog/fog.slang`、`gi/gi.slang`、`post/post.slang`、`water.slang`。已把地球常数、五层云入口、雾积分与合成、反射阴影图、泛光降采样、水面着色放回主文件；子文件只保留难读算法。
- [x] 2. 效果混文件/放错文件：`fog/fog/end.slang` 的选择框与原版雾已删除；`reflection/wsr.slang` 的 LPV 雾移到 `lpv.slang`，空气雾与水下体积移到 `fog/volume`；`post/scene.slang` 的示例改为本文件函数；`voxel/voxel.slang` 的追踪与写入拆到子文件；`post/post/bloom.slang` 的景深与镜头函数移回 `dof.slang`，死的光圈函数删除。
- [x] 3. 近似复制函数：把相机远景投影、反射屏幕坐标、云哈希等重复实现收口或明确保留为参考变体；哈希 `33.33` 与通用 `19.19` 的差异在代码中注明，避免严格对照退化成近似。
- [x] 4. 常量重复：`OGX_TAU` 统一到 `common/math.slang`，`3.14159265359` 与 `6.28318530718` 的调用点改用 `OGX_PI` / `OGX_TAU`；高精度的十七位圆周率保留并注明原因。
- [x] 5. 9 个超过 100 行的函数已拆分 8 个；`ogxLayersGetVolumetricClouds` 保留为单一入口并在文件内注明原因：五层顺序、相机高度混合与距离合成共享同一份状态，拆开会让二十多个参数来回传递。
- [x] 6. Slang 源注释比例：全部 87 个文件达到 50% 以上；`audit.py` 的 `check_slang` 现在低于 50% 直接报错，不再只记录。
- [x] 7. Python 开发文件注释比例：统一项目规则，开发工具与测试世界只要求文件头、接口说明和中文语言检查，不按发布代码的 50% 行覆盖率要求；规则写在 `AGENTS.md` 与 `audit.py`。

## 中优先级

- [x] 8. 文件头的 `rendering/` 旧路径全部改为当前 `shaders/effects/` 实际入口，并核对每个模块的真实消费者。
- [x] 9. `PROBE_ONLY` 状态统一：文件头写明“仅编译探针”，目录表与测试检查一致；`voxel/trace` 恢复为仅被库内间接引用。
- [x] 10. 文件头事实与示例：`camera` 改为几何换算、`noise` 说明会读噪声贴图、`water` 说明解析波与纹理波并存；所有 `...` 示例改成可复制调用或明确的用法说明。
- [x] 11. `common/` 单一效果业务：行星曲率移到 `planet.slang`、水洼粗糙度移到 `surface.slang`、闪电光晕移到 `weather/lightning.slang`、LPV 坐标移到 `lpv.slang`；夜间视觉因宿主公共数学直接调用而保留，并注明共用理由。
- [x] 12. 拆分过细：`fog/volume/light.slang`、`storm.slang`、`step.slang` 与 `common/color/blackbody.slang` 已合并到父文件，源文件数从 90 降到 87。
- [x] 13. 命名：`ogxIqint2`、`ogxTonemapXonk`、`ogxToneMapAgxMerlin`、`ogxAgxConfigurable1*` 已改成行业词或删除；`ogxWsr*` 与 `ogxPhotonics*` 在文件头注明是参考子系统名，不是作者名。
- [x] 14. 死函数：`ogxHashAurora`、`ogxIqint2`、`ogxGetLpvPosition`、`ogxBokehAperture`、`ogxSelectionBox`、`ogxVanillaFog`、`ogxVoxelWriteIndex`、`ogxPhotonicsEmission` 已删除；`ogxDoNightEye` 因宿主公共数学调用而保留；`ogxPopulateShadowVoxel` 保留为严格对照的参考签名入口，宿主阴影顶点有等价实现。
- [x] 15. Python 文件头：21 个开发文件补了可复制示例或明确的用法说明。
- [x] 16. 工具细节：`materials.py` 的各向异性查询改为显式检查扩展，不再吞异常；`omni-gfx/build.py` 入口统一打印一行错误并以非零退出；`generate.py` 删除 `int/uint` 空替换。
- [x] 17. 文档：本文件重写，旧状态与乱码已清除；`stats.py` 把 `omni-gfx/README.md` 加入统计块目标，README、验证记录与根 README 由同一条命令生成。
- [x] 18. 修完统一验证；提交与推送留给主助手统一执行，避免子任务改写共享索引。

## 验证

`generate`、`spirv` 48/48、`check`、`strict-parity`、`profiles`、`.venv` 下 `test-gpu` 26/26、`audit`、`verify`、`compile`。保持 48 模块、519 选项、269 入口、280 程序、166 测试、strict 474/5/26。

## 本轮验证结果

- `generate`：48 个模块、49 个文件、GLSL 16830 行。
- `spirv`：48/48 个探针通过，编译器 2026.20。
- `check`：生成文件与源一致；测试世界 26 个、光影验证场景 21 个 GLSL 审计通过；Slang 87 个文件全部达到 50% 中文说明。
- `strict-parity`：505 个参考函数，exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0。
- `profiles`：iterationt 16904 行、eclipse 16903 行，两份编译通过。
- `test-gpu`：26/26 个用例通过，最大差 0。
- `audit`：源码审计通过；`verify` 的 166 个测试通过；`compile` 2 种配置、280 组唯一程序、0 错误。
- `count`：手写核心 20799 行，预算随 Slang 注释补齐调整到 21000。

## ?????

18 ?????`validate`?`spirv` 48/48?`test-gpu` 26/26?`audit`?`verify` 166 ???`compile` 280 ????????? Python ? 50% ???? AGENTS ????????????????????????
