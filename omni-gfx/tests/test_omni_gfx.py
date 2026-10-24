"""omni-gfx 的离线回归：生成文件是否最新、边界是否干净、手写行数是否超限。

调用位置：项目根目录的 `python -m unittest discover -s tests` 自动发现；
    `python build.py verify` 会把它和光影检查一起跑。
设计原因与取舍：
    这里不启动显卡、不调用 Slang 编译器，只检查可复现的文本产物，
    因此能放进十秒预算。GPU 等值测试与截图另由 omni-gfx 自己的命令运行。
"""
from __future__ import annotations

import hashlib  # 核对清单里的摘要。
import json  # 读取生成清单。
import re  # 去掉注释后检查宿主符号。
import sys  # 临时加入工具目录。
import unittest  # 项目统一测试框架。
from pathlib import Path  # 路径比较。

LIB = Path(__file__).resolve().parents[1]  # omni-gfx 根目录。
ROOT = LIB.parent  # 仓库根目录。
sys.path.insert(0, str(LIB / "tools"))  # 工具目录不是包，直接加入搜索路径。

import count  # 行数口径与报告共用一份实现。
import generate  # 生成器同时提供当前文本，测试不必重新实现转换。

FORBIDDEN = re.compile(r"\b(?:OMNI_[A-Z0-9_]+|colortex\d*|shadowtex\d*|noisetex|gaux\d*|screenSize|cameraPosition|frameTimeCounter|worldTime|rainStrength|gl_FragCoord|uniform)\b")  # 通用库不能出现宿主符号。


def code_only(text: str) -> str:
    """去掉块注释与行注释，只留下会参与编译的代码。"""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)  # 先去掉跨行说明。
    return re.sub(r"//[^\n]*", "", text)  # 再去掉行尾说明。


class OmniGfxTests(unittest.TestCase):
    """守住生成产物与手写预算的边界。"""

    def test_generated_files_are_current(self):
        """磁盘上的 GLSL 与清单必须和当前 Slang 源一致。"""
        generate.check_modules()  # 过期时抛出并列出所有路径。

    def test_shader_copy_matches_library_copy(self):
        """光影包里的副本与独立库里的副本必须逐字节相同。"""
        for name in generate.MODULES:
            shader = (ROOT / "shaders" / "omni-gfx" / f"{name}.glsl").read_text(encoding="utf-8")
            mirror = (LIB / "generated" / "glsl" / f"{name}.glsl").read_text(encoding="utf-8")
            with self.subTest(module=name):
                self.assertEqual(shader, mirror)  # 两处不一致时游戏会读到旧代码。

    def test_no_slang_syntax_left(self):
        """生成文本不能残留 Slang 类型名、取像素写法或静态常量前缀。"""
        for name in generate.MODULES:
            text = generate.module_text(name)
            with self.subTest(module=name):
                self.assertNotRegex(text, r"\b(?:float[234](?:x[234])?|Sampler2D|lerp|asfloat|asuint|asint)\b")  # 只允许 GLSL 名字。
                self.assertNotIn(".Load(", text)  # 纹理取像素必须换成 texelFetch。
                self.assertNotIn("static const", text)  # GLSL 常量不带静态前缀。

    def test_no_version_directive(self):
        """库文件不能声明语言版本，版本由宿主入口决定。"""
        for name in generate.MODULES:
            text = generate.module_text(name)
            with self.subTest(module=name):
                self.assertNotRegex(text, r"(?m)^\s*#version\b")  # 出现就会被构建检查拒绝。

    def test_include_graph_is_internal(self):
        """模块只引用生成库自己的文件，不回头引用光影实现。"""
        for name in generate.MODULES:
            # 只检查会参与编译的代码，注释里的示例不算宿主依赖。
            text = code_only(generate.module_text(name))
            references = re.findall(r'#include\s+"([^"]+)"', text)
            with self.subTest(module=name):
                for reference in references:
                    self.assertTrue(reference.startswith("/omni-gfx/"))  # 只允许库内引用。
                    target = ROOT / "shaders" / reference.lstrip("/")
                    self.assertTrue(target.is_file())  # 引用必须能落到真实文件。

    def test_no_host_symbols(self):
        """生成代码不能读取 Minecraft 或 Iris 的全局量。"""
        for name in generate.MODULES:
            # 只检查会参与编译的代码，注释里的示例不算宿主依赖。
            text = code_only(generate.module_text(name))
            with self.subTest(module=name):
                self.assertEqual(sorted(set(FORBIDDEN.findall(text))), [])  # 出现一个就说明边界被破坏。
                # 允许的只有库自己的采样器参数与局部变量。

    def test_manifest_matches_sources(self):
        """清单记录的源与产物摘要必须和磁盘一致。"""
        manifest = json.loads((LIB / "generated" / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)  # 清单格式只有一个当前版本。
        self.assertEqual([item["module"] for item in manifest["modules"]], list(generate.MODULES))  # 模块顺序固定。
        for item in manifest["modules"]:
            source = (ROOT / item["source"]).read_bytes()
            shader = (ROOT / item["shader"]).read_text(encoding="utf-8").encode("utf-8")
            with self.subTest(module=item["module"]):
                self.assertEqual(hashlib.sha256(source).hexdigest(), item["sourceSha256"])  # 源摘要。
                self.assertEqual(hashlib.sha256(shader).hexdigest(), item["glslSha256"])  # 产物摘要。

    def test_handwritten_budget(self):
        """手写核心（源、工具、测试）不超过计划给的三千行。"""
        data = count.collect()  # 统计口径来自构建工具，不在测试里另写一份。
        self.assertLessEqual(data["handwrittenTotal"], data["handwrittenBudget"])  # 超限时先删重复实现或改口径并说明。

    def test_test_world_assets_exist(self):
        """测试世界的入口与各阶段文件必须齐全。"""
        for name in ("render.py", "terrain.py", "camera.py", "png.py"):  # Python 侧入口。
            self.assertTrue((LIB / "examples" / "world" / name).is_file(), name)
        for name in ("sky.frag", "terrain.frag", "water.frag", "post.frag", "fullscreen.vert", "world_shared.glsl"):  # 着色器阶段与共用参数。
            self.assertTrue((LIB / "examples" / "world" / "shaders" / name).is_file(), name)

    def test_phase3_effects_are_generated(self):
        """阶段三的九个效果模块都要有真正被调用的入口函数。"""
        expected = {
            "atmosphere": "ogxAtmosphereSky", "cloud": "ogxCloudMarch", "water": "ogxWaterShade", "fog": "ogxFogMarch",
            "shadow": "ogxVariablePenumbraShadow", "gi": "ogxGroundTruthAo", "reflection": "ogxScreenSpaceTrace",
            "post": "ogxBloomDownsample", "antialias": "ogxTaaReproject",
        }  # 每个效果一个入口函数。
        for name, symbol in expected.items():
            with self.subTest(module=name):
                self.assertIn(symbol, generate.module_text(name))  # 生成文本缺少入口函数说明模块没有接入。

    def test_minecraft_uses_generated_effect_modules(self):
        """光影包的九个适配层都要引用生成的库，避免旧实现继续各写一套。"""
        adapters = ("shadow", "gi", "reflection", "post", "antialias", "atmosphere", "cloud", "water", "fog")  # 每个效果一个适配层。
        for name in adapters:
            path = ROOT / "shaders" / "gfx" / f"{name}.glsl"  # 光影侧的适配层。
            with self.subTest(module=name):
                self.assertIn(f'#include "/omni-gfx/{name}.glsl"', path.read_text(encoding="utf-8"))  # 实现必须来自生成库。

    def test_minecraft_program_uses_generated_atmosphere(self):
        """合成程序的相函数必须调用生成库，避免两套公式各自漂移。"""
        text = (ROOT / "shaders" / "rendering" / "fog" / "landscattering.glsl").read_text(encoding="utf-8")  # 真实消费者。
        self.assertIn('#include "/omni-gfx/atmosphere.glsl"', text)  # 生成库必须在引用边界内。
        self.assertIn("ogxRayleighPhase(", text)  # 瑞利相函数来自生成库。
        self.assertIn("ogxMiePhase(", text)  # 米氏相函数来自生成库。


if __name__ == "__main__":
    unittest.main()  # 允许直接运行本文件。
