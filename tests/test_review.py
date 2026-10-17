"""主助手审查回归：覆盖生成入口保留、维度与叠加协议、中文说明边界。

示例 python -m unittest discover -s tests；只运行离线编译器，不建立显卡上下文。
"""
import tempfile  # 检查输入和编译产物不污染项目。
import unittest  # 保留标准测试入口。
from pathlib import Path  # 临时文件固定在自有目录。
from unittest.mock import patch  # 入口清理只操作临时目录，不删除项目源码。
import audit  # 真实注释解析与语言约束。
import build  # 读取实际展开源码和原生选项。
import support  # 共享扫描与展开缓存。

class ReviewTests(unittest.TestCase):
    """验证这次审查修正后的对外行为与阶段协议。"""
    def test_english_and_mixed_comments_are_rejected(self):
        """纯英文自然语言与混一个汉字都不能绕过中文规则。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"subject.py"  # 自有最小源码目录。
            for comment in ("A beautiful cloud","A BEAUTIFUL CLOUD","云 A beautiful cloud","Go up","中文说明夹着 beautiful cloud"):
                source.write_text('"""真实中文接口说明。"""\nvalue=1 # '+comment+'\n',encoding="utf-8")
                with self.subTest(comment=comment),self.assertRaisesRegex(ValueError,"自然语言说明必须中文"): audit.check(root)  # 有足够其他中文注释也不能掩盖英语。
            source.write_text('value="普通中文字符串不能冒充注释"\n',encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"至少需要 50%"): audit.check(root)  # 普通字符串不算说明。

    def test_obsolete_generated_entry_keeps_user_comments(self):
        """删除重复入口时不能顺带删除用户加的说明。"""
        with tempfile.TemporaryDirectory() as temporary:
            shaders = Path(temporary); folder = shaders/"world0"; folder.mkdir()
            source = folder/"final.fsh"
            text = '#version 330 compatibility\n// 生成的final入口：修改绘制主体与显式流程表。\n// 用户补充的重要业务说明。\n#define OMNI_FRAGMENT\n#include "/rendering/final.glsl"\n'
            source.write_text(text,encoding="utf-8")  # 模拟生成后用户添加说明。
            with patch.object(build,"SHADERS",shaders),patch.object(build,"configuration",return_value=({},[],{})),patch.object(build,"program_files",return_value={}):
                with self.assertRaisesRegex(ValueError,"旧入口含自有修改"): build.generate()  # 不为了去重丢弃用户修改。
            self.assertEqual(source.read_text(encoding="utf-8"),text)  # 原字节仍保留给主助手审查。

    def test_real_multiline_docstring_and_metadata(self):
        """多行接口文档逐行统计，机器翻译和宏示例有明确豁免。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"subject.py"
            source.write_text('"""输入边界负责检查玩家配置。\n未知取值必须说明出错位置。\n"""\nvalue=1 # 保存已经检查的完整配置。\n',encoding="utf-8")
            result = audit.check(root)[0]  # 确认真实文档块而非任意字符串。
            self.assertEqual(result["chineseCommentLines"],3); self.assertEqual(result["ratio"],0.75)  # 结束引号不当作中文行。
            self.assertTrue(audit.chinese_explanation('// @option {"label":{"zh_cn":"云","en_us":"A beautiful cloud"}}'))  # 只有合法机器字段允许英文翻译。
            self.assertFalse(audit.chinese_explanation('// #define OMNI_CLOUD_MODE 1'))  # 宏示例合法但不计中文行。
            self.assertFalse(audit.chinese_explanation('// #include "/effects/cloud.glsl"'))  # 引用示例不成为英文说明。
            with self.assertRaises(ValueError): audit.chinese_explanation('// @option ["A beautiful cloud"]')  # 不能用伪造机器前缀免除英语检查。
            with self.assertRaises(ValueError): audit.chinese_explanation('// @option {"label":{"zh_cn":"云 A beautiful cloud","en_us":"Cloud"}}')  # 英文翻译豁免不能扩展到中文字段。

    def test_dimensions_and_overlay_body_contract(self):
        """三个维度各自提供完整程序集；叠加与半透明程序复用登记好的绘制主体，水只写四号、六号与贴图色。"""
        generated = build.program_files()  # 真实生成入口。
        data = support.programs()  # 流程表唯一来源。
        self.assertEqual(set(data["dimensions"]),{"world0","world-1","world1"})  # 官方约定：任意 worldN 存在时只从维度目录加载。
        self.assertFalse(any(p.suffix in build.STAGES for p in build.SHADERS.iterdir()))  # 根目录没有被忽略的可执行重复文件。
        for dimension,setting in data["dimensions"].items():  # 逐维度核对片元程序集。
            expected = {name for name in data["programs"] if name not in set(setting.get("absent",[]))}  # 该维度登记要有的片元程序。
            actual = {p.stem for p in generated if p.parent.name==dimension and p.suffix==".fsh"}  # 实际生成的片元程序集。
            with self.subTest(dimension=dimension):
                self.assertEqual(actual,expected)  # 每个维度都提供完整加载器程序集。
        for name in ("gbuffers_line","gbuffers_basic","gbuffers_textured","gbuffers_damagedblock","gbuffers_armor_glint","gbuffers_beaconbeam","gbuffers_weather"):
            self.assertEqual(data["programs"][name][0],"overlay",name)  # 无可靠深度配对的叠加程序共用叠加主体。
        for name in ("gbuffers_water","gbuffers_hand_water"):
            self.assertEqual(data["programs"][name][0],"translucent",name)  # 半透明层共用半透明主体。
        self.assertIn("DRAWBUFFERS:460",support.text("rendering/translucent.glsl"))  # 水写四号法线光照图、六号颜色材质与贴图色。
