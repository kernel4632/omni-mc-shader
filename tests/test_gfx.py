"""通用库边界：确认库目录只依赖自身，不读取 Minecraft 或 Iris 的输入。"""

import re  # 用正则扫描代码里的宿主符号。
import unittest  # 项目统一用标准库测试框架。

import build  # 读取真实光影目录。


FORBIDDEN = re.compile(r"\b(?:OMNI_[A-Z0-9_]+|colortex\d*|shadowtex\d*|noisetex|gaux\d*|screenSize|cameraPosition|frameTimeCounter|worldTime|rainStrength|gl_FragCoord|uniform)\b")  # 这些名字属于 Minecraft 或 Iris，通用库不能出现。


def code_only(text):
    """去掉块注释与行注释，只留下会参与编译的代码。"""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)  # 去掉多行说明，避免注释里的示例被误判。
    return re.sub(r"//[^\n]*", "", text)  # 去掉行尾说明，只检查真实语句。


class GfxBoundaryTests(unittest.TestCase):
    """守住通用库的独立发布边界。"""

    def test_gfx_only_includes_itself(self):
        """通用库只能引入自身目录内的文件。"""
        for path in (build.SHADERS / "gfx").glob("*.glsl"):
            for reference in re.findall(r'#include\s+"([^"]+)"', code_only(path.read_text(encoding="utf-8"))):
                with self.subTest(file=path.name, include=reference):
                    self.assertTrue(reference.startswith(("/gfx/", "/omni-gfx/")))  # 允许指向生成库，但仍禁止引用效果层。

    def test_gfx_has_no_host_symbols(self):
        """通用库里不能出现宿主符号或全局噪声纹理。"""
        for path in (build.SHADERS / "gfx").glob("*.glsl"):
            hits = sorted(set(FORBIDDEN.findall(code_only(path.read_text(encoding="utf-8")))))
            with self.subTest(file=path.name):
                self.assertEqual(hits, [])  # 出现一个就说明库已经偷偷依赖宿主，必须改成显式参数。

    def test_gfx_has_no_version_directive(self):
        """版本声明由宿主程序决定，库文件不写版本指令。"""
        for path in (build.SHADERS / "gfx").glob("*.glsl"):
            with self.subTest(file=path.name):
                self.assertNotRegex(code_only(path.read_text(encoding="utf-8")), r"(?m)^\s*#version\b")  # 库不自己决定 GLSL 版本。


if __name__ == "__main__":
    unittest.main()  # 允许直接运行本文件，方便单独检查边界。
