"""构建回归检查：覆盖错误输入、真实引用与可重复打包。

运行示例：python -m unittest discover -s tests。
测试只使用临时目录，不修改项目源码或玩家配置。
"""

import json
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

import build
import dev
import options


class BuildTests(unittest.TestCase):
    """验证构建边界，防止错误资源进入发布包。"""

    def test_include_relative_and_absolute(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "part.glsl").write_text("float value = 1.0;\n", encoding="utf-8")
            source = folder / "final.fsh"
            source.write_text('#version 330 compatibility\n#include "/part.glsl"\n', encoding="utf-8")
            self.assertIn("float value", build.expand(source, folder))
            source.write_text('#include "part.glsl"\n', encoding="utf-8")
            self.assertIn("float value", build.expand(source, folder))

    def test_include_escape_missing_and_cycle(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "final.fsh"
            for reference in ("../outside.glsl", "/missing.glsl", "/final.fsh"):
                with self.subTest(reference=reference):
                    source.write_text(f'#include "{reference}"\n', encoding="utf-8")
                    with self.assertRaises(ValueError):
                        build.expand(source, folder)

    def test_include_examples_in_comment_are_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "example.glsl"
            text = '/*\n#include "/not-a-real-file.glsl"\n*/\n'
            source.write_text(text, encoding="utf-8")
            self.assertEqual(text, build.expand(source, folder))

    def test_include_trailing_comment_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            source = folder / "example.glsl"
            source.write_text('#include "/part.glsl" // comment\n', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "说明放到上一行"):
                build.expand(source, folder)

    def test_version_and_tag(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "VERSION").write_text("0.0.0-dev.1\n", encoding="utf-8")
            build.validate_tag("v0.0.0-dev.1", folder)
            with self.assertRaises(ValueError):
                build.validate_tag("v1.0.0", folder)
            (folder / "VERSION").write_text("../../outside\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                build.version(folder)

    def test_deterministic_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            first, second = Path(temporary) / "one.zip", Path(temporary) / "two.zip"
            build.archive(first, {"b": b"two", "a": b"one"})
            build.archive(second, {"a": b"one", "b": b"two"})
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_generated_files_match_sources(self):
        _, _, files = build.configuration()
        for path, expected in files.items():
            with self.subTest(path=path):
                self.assertEqual(expected, path.read_text(encoding="utf-8"))
                expected.encode("ascii") # 加载器预处理不能收到 UTF-8 中文字节。

    def test_download_url_boundary(self):
        for url in ("file:///secret", "http://example.com/tool.zip", "https://user:secret@example.com/a"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                dev.validate_url(url)

    def test_archive_escape_is_rejected(self):
        import zipfile
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            package = folder / "unsafe.zip"
            with zipfile.ZipFile(package, "w") as output:
                output.writestr("../escape", "unsafe")
            with self.assertRaises(ValueError):
                dev.extract(package, folder / "tools")
            self.assertFalse((folder / "escape").exists())

    def test_tar_internal_link_and_external_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for target, valid in (("tool", True), ("../../outside", False)):
                with self.subTest(target=target):
                    package = folder / ("safe.tar.gz" if valid else "unsafe.tar.gz")
                    with tarfile.open(package, "w:gz") as output:
                        member = tarfile.TarInfo("tool")
                        member.size = 4
                        output.addfile(member, io.BytesIO(b"test"))
                        link = tarfile.TarInfo("alias")
                        link.type = tarfile.SYMTYPE
                        link.linkname = target
                        output.addfile(link)
                    if not valid:
                        with self.assertRaises(tarfile.FilterError):
                            dev.extract(package, folder / "unsafe")
                    elif __import__("sys").platform != "win32":
                        dev.extract(package, folder / "safe")
                        self.assertEqual((folder / "safe/alias").read_bytes(), b"test")


class OptionTests(unittest.TestCase):
    """验证选项和共享配置的唯一来源及输入边界。"""

    def write_effect(self, folder, definition):
        effects = folder / "effects"
        effects.mkdir(exist_ok=True)
        labels = json.dumps({"label": {"zh_cn": "测试", "en_us": "Test"}})
        (effects / "test.glsl").write_text(
            f"// @effect {labels}\n// @option {labels}\n{definition}\n", encoding="utf-8")

    def test_numeric_default_and_boolean(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.write_effect(folder, "#define TEST_LEVEL 2 // [1 2 3]")
            found, _ = options.scan(folder)
            self.assertEqual(found["TEST_LEVEL"].default, "2")
            self.write_effect(folder, "//#define TEST_ENABLED")
            found, _ = options.scan(folder)
            self.assertEqual(found["TEST_ENABLED"].default, "false")
            self.assertEqual(options.profile_values({"TEST_ENABLED": "false"}, found), "!TEST_ENABLED")

    def test_invalid_options_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for definition in ("#define TEST_LEVEL 4 // [1 2 3]", "#define TEST_LEVEL 1 // [1 1]",
                               "#define TEST_LEVEL 1", "#define TEST_LEVEL abc // [abc]"):
                with self.subTest(definition=definition):
                    self.write_effect(folder, definition)
                    with self.assertRaises(ValueError):
                        options.scan(folder)

    def test_duplicate_option_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.write_effect(folder, "#define TEST_LEVEL 1 // [1 2]")
            source = folder / "effects/test.glsl"
            (folder / "effects/other.glsl").write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
            with self.assertRaises(ValueError):
                options.scan(folder)

    def test_preset_values_and_missing_defaults(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.write_effect(folder, "#define TEST_LEVEL 1 // [1 2]")
            found, _ = options.scan(folder)
            presets = folder / "presets"
            presets.mkdir()
            source = presets / "sample.properties"
            label = '# @preset {"label":{"zh_cn":"样例","en_us":"Sample"}}\n'
            source.write_text(label, encoding="utf-8")
            self.assertEqual(options.presets(presets, found)[0].values, {"TEST_LEVEL": "1"})
            for content in ("UNKNOWN=1", "TEST_LEVEL=9", "TEST_LEVEL=1\nTEST_LEVEL=2"):
                with self.subTest(content=content):
                    source.write_text(label + content, encoding="utf-8")
                    with self.assertRaises(ValueError):
                        options.presets(presets, found)


if __name__ == "__main__":
    unittest.main()
