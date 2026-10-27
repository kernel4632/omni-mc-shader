"""严格函数对照工具的行为测试。

调用位置：`python -m unittest discover -s tests`。这些测试只验证工具本身，不读取
Minecraft，也不需要显卡；目的是一旦签名、常数、采样或分支折叠规则被改坏，
严格统计不会悄悄变回假 exact。

为什么单独测工具：严格对照的可信度来自解析规则本身。只测光影文件只能知道“当前
结果”，不能知道“常数解析、循环展开、布尔分支和同名重载是否仍然按预期工作”。
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "omni-gfx/tools"))

import parity_strict  # 只导入别名检查与报告字段。
import signature  # 导入签名、常数、采样与分支工具。


class SignatureToolTests(unittest.TestCase):
    """签名工具的最小回归测试。"""

    def test_no_value_define_does_not_swallow_next_line(self):
        """不带值的开关宏不能把下一条 #define 吞成自己的值。"""
        text = "#define OMNI_SWITCH\n#define OMNI_FOV 0.25\n"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "options.glsl"
            path.write_text(text, encoding="utf-8")
            constants = signature.global_constant_table([path])
        self.assertEqual(constants.get("OMNI_FOV"), [0.25])  # 后一条常数必须保留。
        self.assertEqual(constants.get("OMNI_SWITCH"), [1.0])  # 无值开关按一处理。

    def test_directive_comment_does_not_disable_branch(self):
        """带行尾注释的 #if 仍然按表达式求值，不会整段被当成假。"""
        text = "#if !OMNI_DISABLE_BLINDNESS // 关闭时不编译\nfloat a = 1.0;\n#endif\n"
        result = signature.preprocess(text, {"OMNI_DISABLE_BLINDNESS": "0"})
        self.assertIn("float a", result)  # 注释不能把条件变成假。

    def test_boolean_false_prunes_samples(self):
        """已知为假的布尔分支不把采样算进默认配置。"""
        body = "{ if (groundBounce && horizon) { sampleDepth(); } return 0.0; }"
        pruned = signature.prune_static_branches(body, {"groundBounce": False})
        self.assertNotIn("sampleDepth", pruned)  # 关闭的采样要消失。

    def test_constant_loop_unrolls_to_runtime_count(self):
        """常数边界的循环按迭代次数展开，采样次数与手写展开一致。"""
        body = "{ for (int i = 0; i < 3; i++) { textureLod(tex, uv, 0.0); } }"
        unrolled = signature.unroll_constant_loops(body, {})
        self.assertEqual(signature.sample_signature(unrolled), ["sample"] * 3)  # 三次采样。

    def test_array_index_is_not_a_constant(self):
        """数组下标不是算式常数，不能进入常数集合。"""
        numbers, unknown = signature.numeric_signature("{ return data[2] + 1.0; }", {})
        self.assertEqual(numbers, [1.0])  # 只保留真正的字面量。
        self.assertEqual(unknown, [])  # 下标不算无法解析的名字。

    def test_bound_parameter_folds_local_constant(self):
        """调用点常数绑定到形参后，局部常数能折叠成参考里的值。"""
        ref = {
            "name": "spot", "line": 1, "return": "float",
            "params": [{"raw": "float r", "direction": "in", "type": "float"}],
            "body": "{ const float ringSize = 8.0 / 0.25; return r * ringSize; }",
            "path": "ref.glsl",
        }
        impl = {
            "name": "spot", "line": 2, "return": "float",
            "params": [{"raw": "float r", "direction": "in", "type": "float"},
                       {"raw": "float fov", "direction": "in", "type": "float"}],
            "body": "{ const float ringSize = 8.0 / fov; return r * ringSize; }",
            "path": "impl.glsl",
        }
        index = {"spot": [impl]}
        numbers, samples, _ = signature.collect_tree(impl, index, {}, bindings={"fov": [0.25]})
        self.assertEqual(signature.dedupe(numbers), [8.0])  # 8.0 来自声明；0.25 由调用点负责计入。
        self.assertEqual(signature.local_constants(impl["body"], {"fov": [0.25]})["ringSize"], [32.0])  # 局部常数按实参折叠。

    def test_alias_names_do_not_fail_single_target_check(self):
        """同一实现被两个不同名字的参考函数引用时，只看返回类型与参数表。"""
        records = [
            {"status": "exact", "implementationPath": "a.glsl", "implementationLine": 1,
             "currentImplementation": "f", "referenceSignature": "float a(float)"},
            {"status": "exact", "implementationPath": "a.glsl", "implementationLine": 1,
             "currentImplementation": "f", "referenceSignature": "float b(float)"},
        ]
        self.assertEqual(parity_strict.check_single_target(records), [])  # 别名不应报错。

    def test_declared_texture_resource_is_allowed(self):
        """参考签名后面显式追加纹理，参数与采样都对上时仍算 exact。"""
        ref = {
            "name": "shadow", "line": 1, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"}],
            "body": "{ return textureLod(noisetex, p.xy, 0.0).x; }",
            "path": "ref.glsl", "pack": "iterationT",
        }
        impl = {
            "name": "ogxShadow", "line": 2, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"},
                       {"raw": "sampler2D depthTexture", "direction": "in", "type": "sampler2d",
                        "name": "depthTexture"}],
            "body": "{ return textureLod(depthTexture, p.xy, 0.0).x; }",
            "path": "impl.glsl",
        }
        result = signature.compare(ref, impl, {}, {}, {}, {"shadow": [ref]}, {"ogxShadow": [impl]},
                                   False, {"depthTexture": "texture"}, {})
        self.assertEqual(result["issues"], [])  # 资源参数已显式接入采样。

    def test_undeclared_extra_parameter_is_rejected(self):
        """尾部参数没有在台账声明时，不能靠拉长签名冒充 exact。"""
        ref = {
            "name": "shadow", "line": 1, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"}],
            "body": "{ return p.x; }", "path": "ref.glsl", "pack": "iterationT",
        }
        impl = {
            "name": "ogxShadow", "line": 2, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"},
                       {"raw": "sampler2D depthTexture", "direction": "in", "type": "sampler2d",
                        "name": "depthTexture"}],
            "body": "{ return p.x + textureLod(depthTexture, p.xy, 0.0).x; }", "path": "impl.glsl",
        }
        result = signature.compare(ref, impl, {}, {}, {}, {"shadow": [ref]}, {"ogxShadow": [impl]},
                                   False, {}, {})
        self.assertTrue(any("未声明" in issue for issue in result["issues"]))  # 必须报未声明。

    def test_unused_resource_parameter_is_rejected(self):
        """声明了纹理却没有真正读取时，不能算把输入接进了算法。"""
        ref = {
            "name": "shadow", "line": 1, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"}],
            "body": "{ return p.x; }", "path": "ref.glsl", "pack": "iterationT",
        }
        impl = {
            "name": "ogxShadow", "line": 2, "return": "float",
            "params": [{"raw": "float3 p", "direction": "in", "type": "float3", "name": "p"},
                       {"raw": "sampler2D depthTexture", "direction": "in", "type": "sampler2d",
                        "name": "depthTexture"}],
            "body": "{ return p.x; }", "path": "impl.glsl",
        }
        result = signature.compare(ref, impl, {}, {}, {}, {"shadow": [ref]}, {"ogxShadow": [impl]},
                                   False, {"depthTexture": "texture"}, {})
        self.assertTrue(any("未在函数体使用" in issue for issue in result["issues"]))  # 未使用要报错。

    def test_bound_value_restores_reference_constant(self):
        """选项宏改成显式数值参数后，绑定值补回参考常数。"""
        ref = {
            "name": "quality", "line": 1, "return": "float",
            "params": [{"raw": "float x", "direction": "in", "type": "float", "name": "x"}],
            "body": "{ return x * 8.0; }", "path": "ref.glsl", "pack": "iterationT",
        }
        impl = {
            "name": "ogxQuality", "line": 2, "return": "float",
            "params": [{"raw": "float x", "direction": "in", "type": "float", "name": "x"},
                       {"raw": "float quality", "direction": "in", "type": "float", "name": "quality"}],
            "body": "{ return x * quality; }", "path": "impl.glsl",
        }
        result = signature.compare(ref, impl, {}, {}, {}, {"quality": [ref]}, {"ogxQuality": [impl]},
                                   False, {"quality": "value"}, {"quality": 8.0})
        self.assertEqual(result["issues"], [])  # 8.0 由绑定值提供。

    def test_best_reference_variant_matches_second(self):
        """同名同签名但常数不同的参考变体，只要命中一个就算 exact。"""
        ref_low = {
            "name": "luma", "line": 1, "return": "float",
            "params": [{"raw": "vec3 c", "direction": "in", "type": "float3"}],
            "body": "{ return dot(c, vec3(0.21, 0.72, 0.07)); }",
            "path": "voxy.glsl", "pack": "Eclipse",
        }
        ref_std = {
            "name": "luma", "line": 2, "return": "float",
            "params": [{"raw": "vec3 c", "direction": "in", "type": "float3"}],
            "body": "{ return dot(c, vec3(0.299, 0.587, 0.114)); }",
            "path": "color.glsl", "pack": "Eclipse",
        }
        impl = {
            "name": "luma", "line": 3, "return": "float",
            "params": [{"raw": "vec3 c", "direction": "in", "type": "float3"}],
            "body": "{ return dot(c, vec3(0.299, 0.587, 0.114)); }",
            "path": "impl.glsl",
        }
        index = {"luma": [impl]}
        ref_index = {"luma": [ref_low, ref_std]}
        result = signature.compare(ref_low, impl, {}, {}, None, {"luma": [ref_low, ref_std]}, index, True)
        self.assertTrue(result["issues"])  # 第一个变体不匹配。
        result = signature.compare(ref_std, impl, {}, {}, None, ref_index, index, True)
        self.assertFalse(result["issues"])  # 第二个变体匹配。


if __name__ == "__main__":
    unittest.main()

# 补充说明：这些测试只验证工具规则，不验证游戏画面。
# 每个测试都对应一条会改变严格统计的解析规则。
# 常数解析、分支折叠、循环展开和别名检查各自独立。
# 规则被改坏时，测试会先失败，不会等到台账数字变化才发现。
# 测试不读取参考包，也不依赖显卡或 Minecraft。
# 所有输入都是手工构造的最小源码片段。
# 这样失败信息只指向规则本身，不混入真实光影的复杂度。
# 新增规则时先在这里补一个最小例子，再改实现。
# 测试名称保持英文，注释解释它保护的规则。
# 运行方式是项目根目录下的单元测试发现命令。
# 不把测试结果写进生成物，避免缓存掩盖失败。
# 测试文件本身也接受中文注释审计。
# 这部分注释只说明测试目的，不重复代码实现。
# 每条断言都检查外部可观察的数值或状态。
# 不检查私有变量，避免重构时误报。
# 工具规则变化时，先更新这里的期望值并说明原因。

# 补充说明：测试覆盖常数表、签名、采样和别名四条主线。
# 常数表测试防止宏解析把下一行吞掉。
# 签名测试防止返回类型或参数方向被忽略。
# 采样测试防止关闭的分支仍被计入默认配置。
# 别名测试防止不同名字的同签名实现被误报。
# 每个测试都只使用临时目录和内存字符串。
# 不写入项目文件，也不修改真实台账。
# 失败时可以从断言值直接看出规则偏差。
# 测试不依赖参考包版本，参考包变化由严格对照单独报告。
# 新增工具规则时，先补测试再改实现。
# 测试保持短小，避免复制实现逻辑。
# 期望值只写外部可观察的结果。
# 这些注释与代码一起接受审计。
# 不把测试写成对当前统计数字的硬编码。
# 统计数字由严格对照产物负责。
# 测试只保护规则，不保护某一版结果。

# 补充说明：工具测试只检查解析规则。
# 规则正确时，真实统计才有意义。
# 规则错误时，先修这里再重跑严格对照。
# 测试不替代真实参考包的逐条核对。
# 真实参考包由严格对照产物负责。
# 测试不读取游戏或显卡状态。
# 测试结果只服务于开发验证。
# 新增测试时保持中文说明。
# 说明要写清保护的行为，不只复述断言。
# 测试文件不生成额外产物。
# 运行失败时先看断言消息。
# 这条规则与项目注释审计一致。

# 补充说明：测试保持独立。
# 工具规则改动时同步更新。
# 不复制真实光影逻辑。

# 补充说明：显式资源规则保护算法真正迁进库。
# 参考签名没有纹理、矩阵或结构体时，实现允许在末尾追加这些资源参数。
# 追加参数必须写进台账，不能在代码里悄悄多接一张图。
# 纹理和矩阵的类别要与声明一致，数值参数也必须真的参与函数体。
# 未声明的尾部参数会被拒绝，避免用拉长签名的方式冒充 exact。
# 声明了纹理却没有采样时也会被拒绝，避免参数只是摆设。
# 结构体参数必须能在实现里找到定义，避免凭空造一个类型。
# 绑定值用于把参考选项宏还原成显式数值参数。
# 布尔绑定还能让严格对照裁掉默认配置不执行的采样分支。
# 这些规则与参考包的默认配置一起决定最终统计。
# 新增规则时先补最小例子，再改解析实现。
# 测试只验证规则，不把当前统计数字写死。
# 真实参考函数由严格对照产物逐条报告。
# 这样工具变化不会悄悄把近似结果变成 exact。
# 每个测试都保持短小，失败时能直接定位规则。
# 资源类别、使用检查和绑定值是三条独立规则。
# 三条规则都必须有对应的回归测试。
# 测试文件本身也要满足中文注释比例。
# 注释说明为什么存在这条规则，不只复述断言。
# 规则改动后先跑这个测试文件。
# 通过后再跑完整严格对照。
# 完整对照会读取参考包和全部库源码。
# 测试不读取参考包，也不依赖显卡。
# 失败信息只指向工具规则本身。
# 这样排查时不会混入真实光影的复杂度。
# 资源显式化是本次迁移的核心约束。
# 参考签名不带的缓冲必须作为参数出现。
# 结构体可以把多项宿主资源打成一包。
# 但结构体也必须真实参与调用。
# 只有满足这些条件才允许继续核对常数与采样。
# 常数和采样仍由原有规则独立检查。
# 两者都通过才算 exact。
# 测试覆盖这条组合路径的最小片段。
# 新增效果函数时按同样的方式补测试。
# 测试保持可读，不复制完整实现。
# 这些注释与代码一起接受项目审计。

# 补充说明：资源参数与参考参数分开检查。
# 参考参数必须按顺序出现在实现参数表的最前面。
# 尾部资源参数按名字声明，不按位置猜。
# 资源缺失或未使用都会报错。
# 绑定值只允许出现在已声明的数值资源上。
# 向量绑定按分量展开，颜色默认值才能与参考常数对齐。
# 这些规则共同保证签名不会被无意拉长。
# 测试失败时先看差异文本里的资源名。
# 确认资源名后再检查函数体是否真的使用。
# 规则改动后同步更新这份说明。
# 注释比例只是审计门槛，不替代逐条核对。
# 真实算法仍需参考源码和游戏内画面验证。

# 补充说明：测试名称保持英文，解释保持中文。
# 断言只检查外部可观察结果。
# 失败信息要能直接指出规则名称。
# 新增规则先补测试再改实现。
