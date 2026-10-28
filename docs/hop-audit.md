# omni-gfx HOP 审计清单（第四轮）

状态：`[ ]` 未修，`[x]` 已修并待复核。只有下一轮审计无不符合项才算完成。

- [x] 1. `world/end.slang` 复制整段吸积盘积分；改为包含并调用 `accretion.slang`，只保留末地参数。末地参数已拆到 `world/end/` 的星空、行星、吸积盘、云影四个子文件。
- [x] 2. 8 个模块不再只靠探针/profile：`reflection/specular` 与 `reflection/photonics` 由 `shaders/effects/reflection/screenspace.glsl` 直接引入，`wsr` 由 `specular` 带入；`gi/diffuse` 由 `gi/gi` 带入并被宿主 `doBlockLightLighting` 调用；`gi/indirect` 由 `gi/gi` 与 `wsr` 带入；`weather/rain` 由 `effects/shared/water/rain.glsl` 引入并调用；`post/exposure` 由 `effects/color/color.glsl` 引入并调用；`antialias/taa` 由 `effects/clarity/taa.glsl` 引入并调用。`catalog.check_consumers()` 现在沿模块引用链核对消费者，登记表只写能走通的消费者。
- [x] 3. 原先 20 个 `PROBE_ONLY` 模块的文件头全部改成事实：直接消费者写具体文件，间接模块写“由 `所属效果` 引入并编译”；`atmosphere/sky` 已按实际接入改写，不再出现“仅探针”与“会被画面引入”同时存在。
- [x] 4. `common/` 的单效果业务已收口：黑洞扭曲移到 `accretion`，水洼粗糙度内联回材质解码，通用 FBM 与三维查表移到 `common/noise`，`RgbToHsv` 归到共享颜色工具并注明体积光、材质与自发光三处调用；夜视仍留在数学模块，因为光照与后期两处共用，注释写明理由。极光、LPV 位置与闪电光晕原本就在所属效果文件中。
- [x] 5. 重复实现已处理：末地天空旋转收成 `ogxRotationXThenY`，行星与末地雾共用；宿主 `CalculateStars` 改为调用 `ogxEndStars`；夜视只剩 `ogxDoNightEye` 一份；光环半径只保留一个 `ringRadius`；雨纹动画删除 `ogxRainAnimationNormal`，统一到 `weather/rain`。两处 Henyey-Greenstein 因参考归一化常数不同（`0.25/π` 与 `0.25 * 3.14`）保留直接算式，并在注释中写明差异；合并会让严格对照失去常数证据。
- [x] 6. 职责混杂已拆开：`world/end` 拆成星空、行星、吸积盘、云影；`fog/fog/end` 拆成末地涡旋、下界群系、通用群系；`post/scene` 拆成画面效果与场景控制，文件头写真实调用位置。
- [x] 7. 长函数与多动作已拆：五层云的单层步进准备抽成 `ogxLayersLayerRay`，五层入口只保留层顺序与合成；`ogxGameplayEffects` 拆成受伤、入水、着火、血量上色四个小函数，入口只按优先级取最大值。
- [x] 8. 22 个文件里 939 行“实现说明/函数索引/参数与边界/补充说明”已删除，改为每个算法步骤的“为什么”注释与函数级取舍说明；`audit.py` 同时检查生成 GLSL 的 50% 覆盖。
- [x] 9. 文件头示例改成可复制调用：`fog/volume/nether` 改调 `ogxNetherVolumetricFog`，`cloud/layers/{exact,simple,transmittance}` 写出完整调用，`parallax`、`upscale`、`voxel` 改成具体函数调用，`lens` 不再使用宿主 `colortex2` 而用显式 `exposureTexture`。
- [x] 10. 过期注释已清理：`fog/fog/end` 不再写原版雾与选择框；`fog/volume` 从“八段”改为实际四段；`fog/volume` 子文件里的空标题已删；`math/filter` 标题改成实际内容。
- [x] 11. 命名与死变量：`texelFetchSize` 改为 `ogxTexelFetchSize`，`Roataion` 全部改为 `Rotation`，`LdotR` 已删除。
- [x] 12. 文档统计与乱码：README 与验证记录的统计块由 `stats` 重新生成（当前 404 已迁入、101 MC 专用）；`architecture.md` 的子文件数与 WSR 内容已更新；`docs/hop-audit.md` 无问号；`shaders/effects/shared/atmosphere.glsl` 的引用改为存在的 `/omni-gfx/atmosphere/model.glsl`。
- [x] 13. 审计与工具：`shaders/omni-gfx/` 增加生成 GLSL 的 50% 比例检查；`audit.py` 文件头检查要求示例含调用、调用位置指向文件或引入者；`catalog.check_consumers()` 沿引用链核对；`signature.py` 把跳过的参考解析错误记录到 `PARSE_ERRORS`，库内解析仍直接报错；`slang.py` 改为暂存目录 + 同盘改名替换，失败时恢复旧编译器。
- [x] 14. 统一验证已完成；提交、推送按项目规则由主助手统一执行，随后再开第五轮审计。

## 验证

已执行：`generate`、`strict-parity`（505 个函数，exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0）、`spirv` 48/48、`profiles`（iterationT 与 Eclipse 均通过）、`audit`、`verify`、`compile`（280 组程序）、`.venv` 下 GPU 等值测试 26/26。保持 48 模块、519 选项、269 入口、280 程序与 55 个 Slang 源文件。

## ?????

1?13 ??????????? 14 ???????????????
