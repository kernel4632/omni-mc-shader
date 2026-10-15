"""构建回归检查：覆盖错误输入、真实引用与可重复打包。

运行示例：python -m unittest discover -s tests。
测试只使用临时目录，不修改项目源码或玩家配置。
"""

import json  # 构造外部说明边界输入。
import io  # 内存准备压缩包成员。
import sys  # 各平台解压策略一致检查。
import tarfile  # 验证链接逃逸边界。
import tempfile  # 测试不污染项目或玩家目录。
import unittest  # 使用已有标准测试入口。
from pathlib import Path  # 测试路径来自独立临时目录。
from unittest.mock import patch  # 隔离开发目录，真实编译器仍照常运行。

import build  # 真实构建主体作为被测对象。
import dev  # 下载和解压边界直接测试。
import options  # 原生定义与预设扫描直接测试。


class BuildTests(unittest.TestCase):
    """验证构建边界，防止错误资源进入发布包。"""

    def test_include_relative_and_absolute(self):
        """相对与根引用都应展开真实文件。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 只使用自有临时光影目录。
            (folder / "part.glsl").write_text("float value = 1.0;\n", encoding="utf-8")
            source = folder / "final.fsh"  # 最终入口引用实际主体。
            source.write_text('#version 330 compatibility\n#include "/part.glsl"\n', encoding="utf-8")
            self.assertIn("float value", build.expand(source, folder))  # 根引用结果包含真正代码。
            source.write_text('#include "part.glsl"\n', encoding="utf-8")
            self.assertIn("float value", build.expand(source, folder))  # 相对引用结果保持一致。

    def test_include_escape_missing_and_cycle(self):
        """所有非法引用应在展开边界被拒绝。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 不能访问临时目录外的文件。
            source = folder / "final.fsh"  # 构造最短循环与缺失引用。
            for reference in ("../outside.glsl", "/missing.glsl", "/final.fsh"):
                with self.subTest(reference=reference):
                    source.write_text(f'#include "{reference}"\n', encoding="utf-8")
                    with self.assertRaises(ValueError):  # 越界、缺失与自身循环均失败。
                        build.expand(source, folder)

    def test_include_examples_in_comment_are_ignored(self):
        """文档示例不会被误当作真实引用。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 示例不需要真实被引文件。
            source = folder / "example.glsl"  # 只有文档块的源码。
            text = '/*\n#include "/not-a-real-file.glsl"\n*/\n'
            source.write_text(text, encoding="utf-8")
            self.assertEqual(text, build.expand(source, folder))  # 展开保留示例原文。

    def test_include_trailing_comment_is_rejected(self):
        """加载器不兼容的尾注必须提前报错。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 输入错误只发生在测试文件。
            source = folder / "example.glsl"  # 引用行携带非法尾注。
            source.write_text('#include "/part.glsl" // comment\n', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "说明放到上一行"):  # 错误给出可执行修正方式。
                build.expand(source, folder)

    def test_version_and_tag(self):
        """标签不能与版本错配，版本不能成为逃逸路径。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 不修改实际版本。
            (folder / "VERSION").write_text("0.0.0-dev.1\n", encoding="utf-8")
            build.validate_tag("v0.0.0-dev.1", folder)  # 唯一合法对应关系应通过。
            with self.assertRaises(ValueError):
                build.validate_tag("v1.0.0", folder)  # 错版本标签不能发布。
            (folder / "VERSION").write_text("../../outside\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                build.version(folder)  # 版本文件不允许任意文件路径。

    def test_compile_cache_does_not_join_tokens_across_comments(self):
        """先缓存合法程序，再插入分词注释；错误程序必须重新编译并失败。"""
        validator = build.tool("glslang")  # 在替换测试目录前定位实际编译器。
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)  # 成功缓存和源码都留在测试目录。
            shaders = root / "shaders"; shaders.mkdir()  # 构造独立计算程序，避免依赖项目效果。
            source = shaders / "probe.csh"  # 计算入口只需一个阶段即可链接。
            valid = "#version 430\nlayout(local_size_x=1) in;\nuniform float xy,x,y;\nvoid main(){ float value=xy; }\n"  # 连在一起的名字是已声明变量。
            source.write_text(valid, encoding="utf-8")  # 第一次确实编译成功，建立可复用缓存。
            with patch.object(build, "ROOT", root), patch.object(build, "SHADERS", shaders), patch.object(build, "tool", return_value=validator), patch("sys.stdout", new_callable=io.StringIO):  # 进度收进内存，不依赖测试终端是否能显示中文。
                build.compile_shaders([source], {}, [])  # 通过实际编译而非模拟成功结果。
                source.write_text(valid.replace("value=xy", "value=x/**/y"), encoding="utf-8")  # 注释隔开两个变量，没有运算符，应当报错。
                with self.assertRaisesRegex(ValueError, "GLSL 编译/链接失败"):
                    build.compile_shaders([source], {}, [])  # 不能复用先前合法源码的成功记录。

    def test_release_notes_only_include_selected_version(self):
        """说明只取本版章节，并保留中文小标题。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 不覆盖真实更新记录。
            (folder / "CHANGELOG.md").write_text(
                "# 更新记录\n\n## 未发布\n\n- 后续修改\n\n## 1.0.0\n\n"
                "### 修复\n\n- 修复水面闪烁。\n\n## 0.9.0\n\n- 旧修改\n", encoding="utf-8")
            self.assertEqual(build.release_notes("1.0.0", folder),
                             "## 本次修改\n\n### 修复\n\n- 修复水面闪烁。\n")
            self.assertEqual(build.release_notes("0.9.0", folder), "## 本次修改\n\n- 旧修改\n")

    def test_release_notes_reject_missing_empty_and_duplicate_versions(self):
        """缺失、空白与重复说明都是发布边界错误。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 每种失败输入独立检查。
            for text in ("## 0.9.0\n- 旧修改", "## 1.0.0\n\n## 0.9.0\n- 旧修改",
                         "## 1.0.0\n- 修改一\n## 1.0.0\n- 修改二"):
                with self.subTest(text=text):
                    (folder / "CHANGELOG.md").write_text(text, encoding="utf-8")
                    with self.assertRaises(ValueError):  # 不能悄悄提取错误章节。
                        build.release_notes("1.0.0", folder)

    def test_deterministic_archive(self):
        """不同插入顺序仍生成相同包字节。"""
        with tempfile.TemporaryDirectory() as temporary:
            first, second = Path(temporary) / "one.zip", Path(temporary) / "two.zip"  # 对比两次独立产物。
            build.archive(first, {"b": b"two", "a": b"one"})
            build.archive(second, {"a": b"one", "b": b"two"})
            self.assertEqual(first.read_bytes(), second.read_bytes())  # 顺序和时间不影响校验值。
            import zipfile  # 同时检查平台标记。
            with zipfile.ZipFile(first) as package:
                self.assertTrue(all(member.create_system == 3 for member in package.infolist()))  # Windows 与 Linux 统一产物。

    def test_generated_files_match_sources(self):
        """现有菜单与源码定义一致，中文用兼容转义。"""
        _, _, files = build.configuration()  # 被测结果来自真实扫描器。
        for path, expected in files.items():  # 每份翻译和菜单都检查实际字节。
            with self.subTest(path=path):
                self.assertEqual(expected, path.read_text(encoding="utf-8"))  # 不手工维护生成值。
                expected.encode("ascii") # 加载器预处理不能收到 UTF-8 中文字节。

    def test_download_url_boundary(self):
        """安装工具不能下载本机资源或携带凭据。"""
        for url in ("file:///secret", "http://example.com/tool.zip", "https://user:secret@example.com/a"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                dev.validate_url(url)  # 所有非法协议与凭据网址被拒绝。

    def test_archive_escape_is_rejected(self):
        """下载包不能写出指定安装目录。"""
        import zipfile  # 构造路径逃逸压缩成员。
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 不访问项目源码。
            package = folder / "unsafe.zip"  # 不可信下载模拟。
            with zipfile.ZipFile(package, "w") as output:
                output.writestr("../escape", "unsafe")  # 上级路径应在写入前拒绝。
            with self.assertRaises(ValueError):
                dev.extract(package, folder / "tools")
            self.assertFalse((folder / "escape").exists())  # 失败后没有逃逸文件。

    def test_tar_internal_link_and_external_link(self):
        """允许包内链接，拒绝包外链接。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 安全与非法归档都在自有目录。
            for target, valid in (("tool", True), ("../../outside", False)):  # 两类链接走同一真实解压入口。
                with self.subTest(target=target):
                    package = folder / ("safe.tar.gz" if valid else "unsafe.tar.gz")
                    with tarfile.open(package, "w:gz") as output:
                        member = tarfile.TarInfo("tool")  # 真实工具字节作为链接目标。
                        member.size = 4  # 声明实际文件长度。
                        output.addfile(member, io.BytesIO(b"test"))
                        link = tarfile.TarInfo("alias")  # 链接名称位于安装目录内。
                        link.type = tarfile.SYMTYPE  # 标准安全过滤器判断链接。
                        link.linkname = target  # 目标分别测试目录内与目录外。
                        output.addfile(link)
                    if not valid:  # 外部链接必须失败。
                        with self.assertRaises(tarfile.FilterError):
                            dev.extract(package, folder / "unsafe")  # 越界链接应报具体过滤错误。
                    elif sys.platform != "win32":
                        dev.extract(package, folder / "safe")
                        self.assertEqual((folder / "safe/alias").read_bytes(), b"test")  # 合法链接内容可读。


class OptionTests(unittest.TestCase):
    """验证选项和共享配置的唯一来源及输入边界。"""

    def write_effect(self, folder, definition):
        """创建最小原生效果说明，供输入边界测试。"""
        effects = folder / "effects"  # 文件位置决定菜单分组。
        effects.mkdir(exist_ok=True)  # 独立选项扫描目录。
        labels = json.dumps({"label": {"zh_cn": "测试", "en_us": "Test"}})  # 两种机器翻译同时提供。
        (effects / "test.glsl").write_text(
            f"// @effect {labels}\n// @option {labels}\n{definition}\n", encoding="utf-8")

    def test_numeric_default_and_boolean(self):
        """原生范围与注释布尔定义产生准确默认值。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 不覆盖项目选项。
            self.write_effect(folder, "#define TEST_LEVEL 2 // [1 2 3]")
            found, _ = options.scan(folder)  # 默认值必须来自实际定义。
            self.assertEqual(found["TEST_LEVEL"].default, "2")  # 不能取范围首值代替默认。
            self.write_effect(folder, "//#define TEST_ENABLED")
            found, _ = options.scan(folder)  # 注释开关是原生关闭语义。
            self.assertEqual(found["TEST_ENABLED"].default, "false")  # 关闭不能生成启用预设。
            self.assertEqual(options.profile_values({"TEST_ENABLED": "false"}, found), "!TEST_ENABLED")  # 关闭语义必须传到加载器。

    def test_invalid_options_are_rejected(self):
        """范围、默认值与类型错误都必须拒绝。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 依次替换同一测试效果。
            for definition in ("#define TEST_LEVEL 4 // [1 2 3]", "#define TEST_LEVEL 1 // [1 1]",
                               "#define TEST_LEVEL 1", "#define TEST_LEVEL abc // [abc]"):
                with self.subTest(definition=definition):
                    self.write_effect(folder, definition)
                    with self.assertRaises(ValueError):  # 未声明范围、重复取值与文字值不合法。
                        options.scan(folder)

    def test_duplicate_option_is_rejected(self):
        """跨效果重复名称不能形成两份默认来源。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 两个效果在同一扫描根下。
            self.write_effect(folder, "#define TEST_LEVEL 1 // [1 2]")
            source = folder / "effects/test.glsl"  # 复制说明制造真实重复。
            (folder / "effects/other.glsl").write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
            with self.assertRaises(ValueError):  # 扫描应拒绝中央名称冲突。
                options.scan(folder)

    def test_preset_values_and_missing_defaults(self):
        """预设补齐默认值，未知键、重复键与非法值失败。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 配置只写自有测试目录。
            self.write_effect(folder, "#define TEST_LEVEL 1 // [1 2]")
            found, _ = options.scan(folder)  # 合法范围来自效果。
            presets = folder / "presets"  # 文件名决定预设名。
            presets.mkdir()  # 创建独立预设扫描位置。
            source = presets / "sample.properties"  # 最小可分享预设。
            label = '# @preset {"label":{"zh_cn":"样例","en_us":"Sample"}}\n'  # 原生分享说明。
            source.write_text(label, encoding="utf-8")  # 未指定值按默认补齐。
            self.assertEqual(options.presets(presets, found)[0].values, {"TEST_LEVEL": "1"})
            for content in ("UNKNOWN=1", "TEST_LEVEL=9", "TEST_LEVEL=1\nTEST_LEVEL=2"):
                with self.subTest(content=content):
                    source.write_text(label + content, encoding="utf-8")
                    with self.assertRaises(ValueError):  # 不默默丢弃错误键值。
                        options.presets(presets, found)


if __name__ == "__main__":
    unittest.main()
