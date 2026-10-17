# 共享配置

每套配置是一个 `.properties` 文件。新增文件会自动登记到游戏的预设菜单。
文件名使用小写英文、数字和下划线。配置中的值只能来自效果的选项定义。
省略的选项由构建工具补成默认值，切换预设时不继承上一套的残留值。
当前四套预设：`default`（默认画面）、`atmospheric`（氛围画面）、`lightweight`（轻量画面）、`realistic`（真实画面）。

```properties
# @preset {"label":{"zh_cn":"默认画面","en_us":"Default"}}
OMNI_DEBUG_VIEW=0
```

`schemaVersion` 是 JSON 共享配置格式版本，目前为 `2`，由打包工具写入预设包说明。版本一迁移为版本二，完整值由原生默认补齐，已有选项名保持不变。properties 文件是加载器格式，不写 `schemaVersion`，只写 `# @shaderVersion 当前版本` 和完整的 `key=value`。
它不作为光影选项交给加载器。玩家导入时，将选项内容保存成
`shaderpacks/光影包文件名.txt`（例如 `Omni-0.0.0-dev.1.zip.txt`），然后重载光影。
该格式采用 Iris / OptiFine 的选项名称；未知选项在构建检查时会报错。

开发分享工具可运行 `python config.py import --input 预设.properties --output .dev/config/share.json`。无版本标记的加载器配置默认按当前VERSION检查；旧版properties必须显式添加 `--legacy`，只迁移原有调试视图。带版本标记的当前文件要求与VERSION一致。`python config.py export --input .dev/config/share.json --output .dev/config/load.properties` 会写出可直接交给加载器的完整properties；也可通过 `.json` 后缀或 `--format json` 保留分享结构。导入、导出与重置只写本项目 `.dev`，拒绝符号链接与目录联接。未知版本、重复键、未知选项与非法值报错。
