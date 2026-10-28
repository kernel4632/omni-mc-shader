# omni-gfx HOP 审计清单（第五轮）

- [x] 1. 10 个模块只有 include/探针，没有真实入口调用。处理结果：`world/portal`、`common/sampling/anisotropic`、`gbuffer`、`gi/ambientocclusion`、`post/scene`、`lens/lens` 接入真实调用（实体、地形、绑定解码、GTAO 弧积分、受伤画面、镜头光斑）；`cloud/layers`、`reflection/wsr`、`reflection/photonics`、`reflection/specular` 没有当前选项选择，移入 `catalog.REFERENCE`，只保留源码供严格对照，不生成 GLSL、不编译探针。
- [x] 2. `catalog.check_consumers` 改为沿函数调用图核对：从真实画面里的 `ogx...()` 调用出发，沿模块内调用传播，单纯 `#include` 不再算消费；`generate.check_modules` 与测试都会执行这项检查。
- [x] 3. `world/end.slang` 恢复 `ogxPlanetShading` 实际入口并删掉重复的子文件；`post/scene.slang` 恢复 `ogxGameplayEffects` 入口，子文件只保留三种扭曲与上色。
- [x] 4. `ogxPlanetShading` 只调用通用 `ogxPlanetBrdf`，不再复制公式；`world/portal` 已由 `effects/entity/entity.glsl` 调用；`gi/diffuse` 按实际内容改名 `gi/blocklight`；各向异性过滤已接入 `terrain_surface.glsl`，不再只是 `common/` 里的孤立效果。
- [x] 5. `shaders/common/math.glsl` 与 `noise.glsl` 的零调用转发函数已删除（含 `linear_step`、`frisvad`、`BlueNoiseTemproal` 等 18 个）；`frisvad` 不再保留第二份实现；`audit.check_legacy_forwarding` 会拒绝新的零调用包装。
- [x] 6. 填充注释已按文件清理，改成业务步骤与边界说明；`audit.py` 新增填充短语检查，源码与生成 GLSL 都要求至少 50% 非空行有有效中文说明。
- [x] 7. `CHANGELOG.md`、`docs/parity.md`、`omni-gfx/src/cloud/layers.slang` 的问号乱码已逐处恢复；`audit.check_garbled_docs` 会扫描全部 `.md`，生成 GLSL 与 profile 也检查乱码。
- [x] 8. 第四轮清单的“已接入”按事实重写：本轮只把能走通调用图的模块算作接入，参考后端明确标注不生成；不再把 include 或探针写成已接入。
- [x] 9. README、`docs/gfx-parity.md`、`omni-gfx/docs/architecture.md`、`docs/omni-gfx-plan.md` 的当前统计统一由 `stats` 生成或按本轮实际数字更新；历史验证记录保留当时口径。
- [x] 10. `signature.py` 报告路径改为仓库相对路径；`profile.py` 清理编译器输出里的仓库根路径；重新生成的 `parity_report.json` 与 `profiles/*/profile.json` 不再含本机绝对路径。
- [x] 11. `signature.report_parse_errors()` 在严格对照边界汇总解析错误：报告写入 `parseErrors`，终端打印数量与前五处，不再只追加到列表。
- [x] 12. `audit.py` 新增死模块（经 `catalog`）、填充注释、问号乱码、旧转发、文档乱码检查；`check_generated_ratio` 覆盖 profile；`catalog._module_files` 校验主文件与子文件边界；Slang 源重复引用直接报错。
- [x] 13. `generated/spirv/README.md` 改为事实：`README.md` 提交、`*.spv` 与 `manifest.json` 不提交；当前 44 个生成模块，4 个参考后端不生成 SPIR-V。
- [x] 14. 仓库内新增大可读副本 `docs/hop.md`，写明来源与同步方式，避免审查口径随外部技能文件漂移。
- [x] 15. 本轮验证已完成（见下）；提交与推送按项目规则由主助手统一执行，之后开第六轮审计。

## 验证

`generate` 44 个生成模块（4 个参考后端，共 48 个源模块）；`spirv` 44/44；`check`；`strict-parity` 505 个函数（exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0）；`profiles` 两份（14217/14216 行）；`.venv` 下 `test-gpu` 26/26；`audit` 通过 623 个代码文件；`verify` 166 个测试；`compile` 2 种配置、280 组唯一程序。保持 519 选项、269 入口、280 程序、166 测试。

- [x] 16. 第五轮删除零调用包装后，严格台账仍指向宿主旧名字，strict 一度降到 exact 459、approximate 15。处理结果：15 条目标改到通用库真实实现（`frisvad` 与 `rand` 补可调用入口），并修复 G-buffer 重复采样、GTAO 弧积分常数、镜头 `atan2` 与各向异性静态分支；strict 恢复 exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0。

## 第五轮结果

结构整改完成，strict 恢复 474/0/5/26/0；第 16 项关闭。等待第六轮审计。
