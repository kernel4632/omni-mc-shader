# 第三方来源与许可

本版采用 Ashima 的三维单纯形噪声直接计算云密度，使用 MIT 许可。锁定提交 `6abed1e77ed1e18b181627c35f688eb30c9fe75e`，源码与 LICENSE 保存在 `shaders/libraries/ashima/`，来源与本地字节 SHA256 记录在 `dependencies.json`。仅规范化上游源码行尾与行尾空格，保留函数名字、算法、版权与许可原文，不加只转手的包装。第三方原文件豁免中文注释要求，构建仍检查引用与文件校验。

已评估 [Base-330 上游 LICENSE](https://github.com/shaderLABS/Base-330/blob/master/LICENSE)，为 Unlicense。现有多附件与远景流程输入输出已固定，替换模板会重复基础接线，当前没有实际收益，保留独立流程。普通 hash 用于随机序列，简单值噪声仅用于雪边缘与轻量氛围；云已改用成熟梯度噪声，避免只为登记库而包装原函数。以上没有 GPU 耗时或视觉改善的实测结论。`references/iterationT` 与 `references/Eclipse` 保留作参考，未复制整体许可不明的代码。

接口依据：[Iris 官方文档](https://shaders.properties/)、[Distant Horizons 官方接口](https://github.com/IrisShaders/docs/blob/main/src/content/docs/current/Reference/Mod%20Support/distant_horizons.mdx)、[labPBR 1.3 数据标准](https://shaderlabs.org/wiki/LabPBR_Material_Standard)。接口事实用于独立实现，没有搬运文档文字或示例算法。预定义金属使用标准允许的底色近似，不使用标准表中的光学常数。

运行依赖白名单为 `dependencies.json`。未来库必须记录名称、固定版本、HTTPS 来源、明确许可证和每个文件的 SHA256，并打包原始 LICENSE/COPYING；未登记文件会导致构建失败。第三方原始声明保持原文，排除中文注释比例要求。

开发工具和 Python 依赖版本分别在 `dev-tools.lock.json` 与 `requirements-dev.lock`。它们仅供开发，不进入玩家光影包。
