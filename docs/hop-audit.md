# omni-gfx HOP 审计清单（第二轮）

审查对象：`omni-gfx/` 本体，不含 Minecraft 消费者层。
状态：`[ ]` 未修，`[x]` 已修并由下一轮审计复核。
规则：修完一轮后重跑验证，再开新审计；只有新审计无不符合项才算完成。

## 高优先级

- [x] 1. 20 个模块只有探针/profile 编译，没有画面消费者；16 个文件头却写成会被画面引用。要么接入示例/消费者，要么诚实标明仅探针，并补测试。
- [x] 2. `tests/equivalence.glsl` 仍引用已删除的 `/gfx/*`，`test-gpu` 实际失败；README 仍写 26/26。修引用并实跑通过。
- [x] 3. AgX 死簇仍在：`ogxAgxConfigurable`、`ogxAgxConfigurable1`、`ogxAgxConfigurable1Mat3` 及专属辅助只被 profile 探针续命；删除或接入真实消费者。
- [x] 4. `common/math.slang` 856 行、`fog/volume.slang` 582 行，又把算法子文件合并成大文件；按算法拆回同名文件夹，但主文件必须有实际函数，不能只拼 include。
- [x] 5. 25 组函数体完全相同，约 56 个定义；重复的相机、Bloom、相函数、深度转换、阴影偏差要收口到 common/shared，不能靠复制。

## 中优先级

- [x] 6. `audit.py` 的 Slang 检查有假阴性：漏 `Ogx...` 结构体返回、允许函数体内注释冒充文件头、不检查调用位置/示例/取舍、不检查 include 是否仍在 `src`；修检查并让上述问题失败。
- [x] 7. `parity.py` / `parity_strict.py` 在 `references/` 缺失时返回 0 个函数，测试仍通过；加目录存在与 505 数量断言。
- [x] 8. 颜色模块名不副实：`common/color/agx.slang` 含 Reinhard/Uchimura/AgX，`tonemap.slang` 含 AgX/ACES/Reinhard；按算法拆文件，`common/color.slang` 不能只做纯 include。
- [x] 9. `tools/generate.py` 与 `tools/profile.py` 各维护一份 48 模块清单；合并为单一来源，并测试两份一致。
- [x] 10. 明确死函数与非普通命名：`ogxCloudFbmLq`、`ogxSwapperlinZ2`；删除或改名并说明用途。
- [x] 11. README 与 `docs/gfx-functions.md`、`docs/verification.md` 数字互相矛盾（401/104 vs 407/98、86 vs 73、15826 vs 14863 等）；用生成脚本统一。
- [x] 12. `omni-gfx/docs/verification.md` 有 361 个问号乱码和 `\f` 控制字符；重写为可读 UTF-8。

## 低优先级

- [x] 13. 文件头/示例说错：`math` 说过滤函数留旧 GLSL、`fog/volume` 说钩子沿用旧名、`camera` 示例调用不存在的函数、`sampling/anisotropic` 路径错、`tools/slang.py` 写不存在的 `build.py all`。
- [x] 14. 拆分子文件后留下孤立注释：`color.slang`、`fog/fog.slang`、`water.slang`、`post/post.slang`、`atmosphere/atmosphere.slang`、`gi/gi.slang` 的说明与后面的函数不对应。
- [x] 15. 生成器有不会命中的重复降级分支：`generate.py` 的 `LOAD3D`、`LOAD`、`SAMPLE_LEVEL`、`LOAD1D` 注释错误、`"float":"float"` 空替换；删除或修正。
- [x] 16. `signature.py` / `parity.py` 吞解析异常，可能把失败当缺少；边界处直接报错，不返回 False/None。
- [x] 17. `tools/slang.py` 下载 zip/tar 直接 `extractall`，没有 SHA-256 与路径检查；补校验，失败时明确报错。
- [x] 18. 旧注释、旧数字、重复注释：`test_omni_gfx.py` 的“三千行”、`gl.py` 重复两行、README 旧帧时与错误文档路径。
- [x] 19. 上一轮 HOP 修改仍在工作树未提交；修完本轮后统一验证、提交、推送。

## 验证

每批运行：`python omni-gfx/build.py generate`、`spirv`、`check`、`strict-parity`、`profiles`、`test-gpu`，以及 `python build.py audit`、`verify`、`compile`。保持 48 模块、519 选项、269 入口、280 程序、strict 474/5/26；测试从 160 条增加到 166 条，新增的 6 条专门覆盖模块清单、仅探针状态、文档统计、重复函数体、下载路径与审计假阴性。

## 本轮验证结果

- `generate`：48 个模块、49 个文件、GLSL 15781 行。
- `spirv`：48/48 个探针通过，编译器 2026.20。
- `check`：生成文件与源一致；测试世界 26 个、光影验证场景 21 个 GLSL 审计通过。
- `strict-parity`：505 个参考函数，exact 474、approximate 0、reference_broken 5、mc_glue 26、missing 0。
- `profiles`：iterationt 15855 行、eclipse 15854 行，两份编译通过。
- `test-gpu`：26/26 个用例通过，最大差 0。
- `audit`：619 个代码文件通过。
- `verify`：166 个测试、9 组编译探针与打包通过。
- `compile`：2 种配置、280 组唯一程序、0 错误。
- `count`：手写核心 19784 行，上限 19900。

第 19 项保持未打勾：按项目协作规则，子任务不提交，工作树交给主助手统一审查、提交和推送。

## ?????

18 ????`test-gpu` ? `.venv` ?? 26/26 ????? Python ? `glfw`??????????????????
