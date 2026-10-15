"""主助手审查回归：覆盖时间阶段、透明协议、噪声来源和中文说明边界。

示例 python -m unittest discover -s tests；只运行离线编译器，不建立显卡上下文。
"""
import hashlib  # 上游代码与许可必须和锁定记录一致。
import json  # 读取受控程序与依赖记录。
import subprocess  # 使用真实离线编译器检查常量折叠。
import tempfile  # 检查输入和编译产物不污染项目。
import unittest  # 保留标准测试入口。
from pathlib import Path  # 临时文件固定在自有目录。
from unittest.mock import patch  # 入口清理只操作临时目录，不删除项目源码。
import audit  # 真实注释解析与语言约束。
import build  # 读取实际展开源码和原生选项。

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

    def test_projection_and_final_stage_contract(self):
        """最终镜头不能再次检查已翻转的旧帧号，远景追踪必须成对选投影。"""
        lens = (build.SHADERS/"effects/lens.glsl").read_text(encoding="utf-8")
        self.assertNotIn("omniHistoryValid()",lens)  # 有效性来自翻转前保存的当前颜色透明通道。
        temporal = (build.SHADERS/"rendering/temporal.glsl").read_text(encoding="utf-8")
        self.assertIn("texelFetch(colortex8,pixel,0).a<0.0",temporal)  # 水退出历史时也必须精确读取并写入无效标记。
        for token in ("vec3 omniMotionBlur","projected.w<=0.0","omniJitter(frameCounter-1)","texelFetch(colortex0,pixel,0).a<0.5"):
            self.assertIn(token,lens)  # 独立动作包含跳变、投影、抖动和历史有效性边界。
        self.assertNotIn("texture(colortex1",lens); self.assertNotIn("texture(colortex7",lens)  # 类别和有效性必须精确读取。
        self.assertNotIn("current.a<0.5",lens); self.assertNotIn("vec4 current",lens)  # 景深不能依赖颜色附件历史连续性。
        self.assertIn("vec2 previousUnjittered",lens); self.assertIn("currentUnjittered-previousUnjittered",lens)  # 非TAA模式不减去不存在的上一帧抖动。
        reflection = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("omniProjectDistant(point)",reflection); self.assertIn("omniDistantView(screen.xy,depth)",reflection)  # DH 投影与深度成对使用。
        self.assertNotIn("omniSceneView(screen.xy,true)",reflection)  # 不能混合近景屏幕坐标与远景重建。
        self.assertIn("texelFetch(colortex5,oldPixel,0)", (build.SHADERS/"effects/antialiasing.glsl").read_text(encoding="utf-8"))  # 历史元数据不插值。
        self.assertIn("sum += omniFocusSample",lens); self.assertIn("sum += omniLensSample",lens)  # 快门和景深使用统一样本顺序。
        self.assertIn("texelFetch(colortex1,pixel,0).a==2.0",lens)  # 中心手元数据不使用线性插值。
        shadow = (build.SHADERS/"effects/shadow.glsl").read_text(encoding="utf-8")
        self.assertIn("const int shadowMapResolution = 2048;",shadow); self.assertIn("const float shadowDistance = 128.0;",shadow)  # Iris静态扫描器读取字面量原生常量，而不是宏变量。
        options,_,_ = build.configuration()
        self.assertEqual(options["shadowMapResolution"].declaration,"int"); self.assertEqual(options["shadowDistance"].declaration,"float")  # 工具扫描器与Iris常量扫描器使用同一声明。

    def test_transparent_and_overlay_metadata_contract(self):
        """叠层不写底层法线，水法线与插值视深度来自同一阶段。"""
        data = json.loads((build.SHADERS/"rendering/programs.json").read_text(encoding="utf-8"))
        self.assertEqual(set(data["dimensions"]),{"world0","world-1","world1"})  # 官方约定：任意worldN存在时只从维度目录加载。
        self.assertFalse(any(p.suffix in build.STAGES for p in build.SHADERS.iterdir()))  # 根目录没有被忽略的可执行重复文件。
        programs = set(data["programs"])
        for dimension in data["dimensions"]:
            self.assertEqual({p.stem for p in (build.SHADERS/dimension).glob("*.fsh")},programs)  # 三个维度均提供完整加载器程序集。
        for name in ("gbuffers_line","gbuffers_basic","gbuffers_particles","gbuffers_particles_translucent","gbuffers_entities_translucent","gbuffers_block_translucent"):
            self.assertIn("OMNI_OVERLAY",data["programs"][name])  # 无可靠深度配对的叠层统一拒绝几何效果。
        for path in ("terrain.glsl","distant.glsl"):
            text = (build.SHADERS/"rendering"/path).read_text(encoding="utf-8")
            self.assertRegex(text,r"waterSurface\s*=\s*vec4\(")  # 近景和远景都把水深写入独立附件。
            self.assertIn("RENDERTARGETS: 0,7,8",text)  # 水不写底层类别和材质。

    def test_vendor_noise_is_used_and_license_is_packed(self):
        """实际云调用成熟噪声，依赖记录与原声明一同打包。"""
        files = build.dependencies()  # 真实依赖白名单与哈希必须通过。
        self.assertIn("shaders/libraries/ashima/LICENSE",files)
        self.assertIn(b"Copyright (C) 2011 by Ashima Arts",files["shaders/libraries/ashima/LICENSE"])  # 版权原文没有改成中文。
        cloud = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("snoise(p*",cloud)  # 成熟库直接参与密度计算，不是空包装。
        manifest = json.loads((build.ROOT/"dependencies.json").read_text(encoding="utf-8"))
        for reference,digest in manifest["libraries"][0]["files"].items():
            self.assertEqual(hashlib.sha256((build.SHADERS/reference).read_bytes()).hexdigest(),digest)  # 源码与声明字节受控。

    def test_zero_wave_and_reflection_optimize_away(self):
        """离线优化后的中间码不得包含水波三角函数或天空反射计算。"""
        found,_,_ = build.configuration(); values = {n:o.default for n,o in found.items()}  # 原生定义仍是唯一配置来源。
        values.update(OMNI_WAVE_STRENGTH="0.0",OMNI_REFLECTION_STRENGTH="0.0",OMNI_RAIN_RIPPLES="false",OMNI_PLAYER_RIPPLES="false")
        source = build.option_source(build.expand(build.SHADERS/"effects/water.glsl"),found,values)  # 直接复用生产算法。
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary); shader = folder/"probe.frag"; output = folder/"probe.spv"  # 离线工具探针不改变生产GLSL330。
            harness = '#version 450\n'+source+'\nlayout(location=0) out vec4 result;\nvoid main(){vec3 n=omniWaterNormal(vec3(0),vec3(0,1,0));result=vec4(omniWater(vec3(0,0,-2),n,vec2(0.5)),1);}\n'
            shader.write_text(harness,encoding="utf-8")  # 工具中间码用较高版本，只验证相同常量分支消除。
            result = subprocess.run([str(build.tool("glslang")),"-G","-Os","-H","--auto-map-bindings","--auto-map-locations","-o",str(output),str(shader)],capture_output=True,text=True,encoding="utf-8",errors="replace")
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)  # 优化结果必须由真实离线编译器生成。
            self.assertNotRegex(result.stdout,r"\bSin\b|\bCos\b|omniWave|omniSky|omniReflected")  # 零开销结论只限该编译器，不冒充真实驱动耗时。
