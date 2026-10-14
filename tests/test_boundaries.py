"""第二轮审查：验证加载器维度、无副作用输入边界和可加载分享格式。

运行示例 python -m unittest discover -s tests；发布和采样进程全部用模拟替代。
"""
import contextlib  # 参数错误输出不污染测试结果。
import io  # 收集统一入口的可读错误。
import json  # 构造外部依赖与配置输入。
import subprocess  # 使用真实命令行检查不会执行动作的非法参数。
import sys  # 测试与构建使用同一解释器。
import tempfile  # 所有文件边界放在自有临时目录。
import unittest  # 保留标准回归入口。
from pathlib import Path  # 比较实际解析后的目录。
from unittest.mock import Mock, patch  # 不启动游戏、采样或真实发布。
import audit  # 中文说明解码与比例统计。
import build  # 实际生成与发布边界。
import game  # 专用实例路径和进程匹配。
import options  # 分享格式唯一来源。

class BoundaryTests(unittest.TestCase):
    """外部输入必须在文件写入与外部进程之前拒绝。"""
    def test_loader_world_folders_are_complete(self):
        """官方旧维度规则要求主世界world0，存在worldN后根程序不会加载。"""
        generated = build.program_files()  # 只接受显式的三组实际加载位置。
        names = {p.name for p in generated if p.parent.name=="world0"}  # 三个维度必须覆盖完全相同的程序集。
        self.assertIn("final.fsh",names)  # 主世界拥有真实最终显示入口。
        for dimension in ("world0","world-1","world1"):
            self.assertEqual({p.name for p in generated if p.parent.name==dimension},names)  # 每个世界都提供完整程序。
        self.assertFalse(any(p.parent==build.SHADERS for p in generated))  # 根入口是被忽略的重复代码。
        settings = options.read_properties(build.SHADERS/"rendering/pipeline.properties")  # 阴影开关必须对应实际目录。
        for dimension in ("world0","world-1","world1"):
            self.assertEqual(settings[f"program.{dimension}/shadow.enabled"],"OMNI_SHADOW_ENABLED")  # 世界开关与入口路径成对。

    def test_generated_comments_are_ascii_chinese(self):
        """转义中文说明保持加载器编码，英语生成说明仍被拒绝。"""
        _,_,files = build.configuration()  # 实际生成器产物而非测试重写一份菜单。
        for path,content in files.items():
            content.encode("ascii")  # 每份加载器属性与语言文件保持ASCII。
            audit.generated_comments(path,content)  # 解码中文说明后仍遵守语言规则。
            self.assertIn("\\u",content.splitlines()[0])  # 生成说明没有自然语言英语。
        with self.assertRaisesRegex(ValueError,"自然语言说明必须中文"):
            audit.generated_comments(Path("generated.properties"),"# A beautiful cloud\nVALUE=1\n")

    def test_world_names_and_links_fail_before_writing(self):
        """驱动路径、设备名和目录链接不能写进真实玩家存档。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); saves = root/".dev/minecraft/saves"; saves.mkdir(parents=True)  # 测试实例根边界。
            with patch.object(game,"ROOT",root):
                for name in (".","..","C:","C:world","/world","\\world","test:stream","NUL","world."," world"):
                    self.assertFalse(game.re_world(name),name)  # Windows特殊路径统一在名字边界拒绝。
                outside = root/"player"; outside.mkdir(); (outside/"level.dat").write_bytes(b"fixture")
                try: (saves/"linked").symlink_to(outside,target_is_directory=True)
                except OSError: self.skipTest("本机不允许建立符号链接，路径字符串检查已执行")
                self.assertFalse(game.re_world("linked"))  # 世界目录本身链接也被拒绝。
                world = saves/"safe"; world.mkdir(); (world/"level.dat").write_bytes(b"fixture")
                (world/"datapacks").symlink_to(outside,target_is_directory=True)
                with self.assertRaisesRegex(ValueError,"链接|目录联接|输出必须"): game.regression("safe",99)
                self.assertFalse((outside/"Omni-regression").exists())  # 写入前没有改变玩家路径。

    def test_invalid_sample_context_has_no_side_effects(self):
        """上下文先检查，非法输入既不查进程也不启动采样器。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); tool = root/".dev/tools/PresentMon.exe"; tool.parent.mkdir(parents=True); tool.write_bytes(b"fixture")
            context = root/"bad.json"; context.write_text("[]",encoding="utf-8")
            with patch.object(game,"ROOT",root),patch.object(game.sys,"platform","win32"),patch.object(game,"development_process") as identity,patch.object(game.subprocess,"run") as run:
                with self.assertRaisesRegex(ValueError,"性能上下文"): game.sample(tool,123,5,context)
                identity.assert_not_called(); run.assert_not_called()  # 不合法数据没有外部副作用。
            self.assertFalse((root/".dev/reports/performance").exists())  # 连输出目录都不提前创建。

    def test_sample_requires_actual_development_process(self):
        """记录pid仍需核对真实Java和gameDir，不能采样任意玩家进程。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); dev = root/".dev"; dev.mkdir()
            directory = dev/"minecraft"; directory.mkdir(); java = root/"java.exe"
            record = {"pid":7,"java":str(java),"gameDirectory":str(directory)}
            (dev/"game-process.json").write_text(json.dumps(record),encoding="utf-8")  # 工具原始启动记录。
            actual = {"ExecutablePath":str(java),"CommandLine":f'java --gameDir "{directory}"'}  # 模拟实际系统进程身份，而不是只看pid记录。
            with patch.object(game,"ROOT",root),patch.object(game.subprocess,"run",return_value=Mock(stdout=json.dumps(actual))) as run:
                game.development_process(7)  # 正确专用实例身份通过。
                actual["CommandLine"] = f'java --gameDir "{root}/player"'; run.return_value.stdout=json.dumps(actual)
                with self.assertRaisesRegex(ValueError,"开发游戏目录"): game.development_process(7)
                with self.assertRaisesRegex(ValueError,"进程号"): game.development_process(8)  # 记录之外的任意pid直接失败。

    def test_current_properties_and_explicit_legacy_migration(self):
        """当前属性不冒充旧版；旧版只迁移原来存在的调试接口。"""
        found,_ = options.scan(build.SHADERS)  # 外部配置值使用真实选项范围。
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"current.properties"; source.write_text("OMNI_CLOUD_MODE=2\n",encoding="ascii")
            current = options.shared(source,found,build.version())  # 没有标记的加载器配置默认是当前版。
            self.assertEqual(current["shaderVersion"],build.version()); self.assertEqual(current["schemaVersion"],options.SHARE_SCHEMA)
            with self.assertRaisesRegex(ValueError,"旧版配置只能"): options.shared(source,found,build.version(),legacy=True)
            source.write_text("OMNI_DEBUG_VIEW=2\n",encoding="ascii")
            migrated = options.shared(source,found,build.version(),legacy=True)  # 明确旧版迁移后补齐当前默认值。
            loadable = root/".dev/load.properties"; options.save_properties(loadable,migrated["values"],build.version(),root)
            self.assertEqual(options.read_properties(loadable),migrated["values"])  # 加载器只读完整合法键值。
            self.assertEqual(options.shared(loadable,found,build.version()),migrated)  # 版本标记不会回到旧格式。
            with self.assertRaises(ValueError): options.save_properties(root/"player.properties",{},build.version(),root)

    def test_dependency_wrong_files_type_is_readable(self):
        """外部依赖清单类型错误必须可读报错，而不是属性访问异常。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root/"THIRD_PARTY.md").write_text("声明",encoding="utf-8")
            for files in (None,[],"text",1,{"libraries/x.glsl":None}):
                manifest = {"schemaVersion":1,"libraries":[{"name":"example","version":"1","source":"https://example.com","license":"MIT","files":files}]}
                (root/"dependencies.json").write_text(json.dumps(manifest),encoding="utf-8")
                with patch.object(build,"ROOT",root),self.assertRaisesRegex(ValueError,"files 必须"): build.dependencies()  # 保留具体输入字段名。

    def test_cli_rejects_unrelated_parameters(self):
        """错误发布参数不启动生成，错误导出参数不写配置。"""
        commands = [["build.py","version","--new-version","0.0.0-dev.5"],["build.py","generate","--notes-file","missing.md"],["options.py","reset","--legacy"]]
        for command in commands:
            result = subprocess.run([sys.executable,*command],cwd=build.ROOT,capture_output=True,text=True,encoding="utf-8",errors="replace")  # 只运行必定在参数边界退出的命令。
            self.assertEqual(result.returncode,2,result.stdout+result.stderr)  # 拒绝无效参数而不执行后续动作。

    def test_release_stops_when_generation_changes_tracked_source(self):
        """确认发布后生成文件变化也必须停止，不能只暂存版本掩盖源码差异。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)  # 模拟发布完全隔离，不修改项目版本。
            (root/"VERSION").write_text("0.0.0-dev.4\n",encoding="utf-8")  # 临时发布版本，不修改真实工作区。
            (root/"CHANGELOG.md").write_text("# 更新\n\n## 0.0.0-dev.4\n旧说明\n",encoding="utf-8")
            notes = root/"notes.md"; notes.write_text("本次发布修改",encoding="utf-8")
            statuses = iter((""," M VERSION\n M CHANGELOG.md\n M shaders/world0/final.fsh"))  # 第二次状态包含生成后的受控源码变化。
            def result_for(command,**kwargs):
                """只模拟只读预检输出，不执行任何真实版本控制动作。"""
                args = tuple(command[1:])  # 状态前两列保持真实空格，验证路径读取。
                values = {("branch","--show-current"):"main",("ls-remote","--heads","origin","main"):"abc refs/heads/main",("rev-parse","HEAD"):"abc"}
                return Mock(stdout=next(statuses) if args==("status","--porcelain") else values.get(args,""))  # 生成前干净，生成后必须拒绝。
            with patch.object(build,"ROOT",root),patch.object(build.subprocess,"run",side_effect=result_for) as run,patch.object(build.sys.stdin,"isatty",return_value=True),patch("builtins.input",return_value="发布 0.0.0-dev.5"),patch.object(build,"generate"),patch.object(build,"check") as check:
                with contextlib.redirect_stdout(io.StringIO()),self.assertRaisesRegex(ValueError,"非版本文件"): build.release("0.0.0-dev.5",notes)
                check.assert_not_called()  # 不继续昂贵检查或掩盖源码变化。
                self.assertFalse(any(call.args[0][1] in ("add","commit","push") for call in run.call_args_list))  # 没有版本控制写入。

    def test_config_output_and_function_links_are_rejected(self):
        """配置文件和函数子目录的链接也不能逃到玩家目录。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); outside = root/"player"; outside.mkdir()
            world = root/".dev/minecraft/saves/safe"; world.mkdir(parents=True); (world/"level.dat").write_bytes(b"fixture")
            functions = world/"datapacks/Omni-regression/data/omni"; functions.mkdir(parents=True)  # 链接只位于深层函数目录，世界根本身正常。
            try: (functions/"function").symlink_to(outside,target_is_directory=True)
            except OSError: self.skipTest("本机不允许建立符号链接")  # 显式记录环境限制，不伪装链接验证通过。
            with patch.object(game,"ROOT",root),self.assertRaises(ValueError): game.regression("safe",99)
            config = root/".dev/config"; config.symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError): options.save(config/"user.json",{},build.version(),root)
            self.assertFalse((outside/"user.json").exists()); self.assertFalse((outside/"setup.mcfunction").exists())  # 拒绝发生在首次写入之前。

    def test_water_and_lens_combination_contract(self):
        """瀑布保留侧面法线，所有镜头采样保持同一效果顺序。"""
        water = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")  # 直接核对生产波浪的表面输入。
        self.assertIn("worldNormal.y<0.9",water); self.assertIn("abs(relativeHeight)",water)  # 顶面波浪与近水互动有实际输入条件。
        lens = (build.SHADERS/"effects/lens.glsl").read_text(encoding="utf-8")
        self.assertIn("sum += omniFocusSample",lens); self.assertIn("sum += omniLensSample",lens)  # 快门和景深不再覆盖原始红蓝通道。
        self.assertIn("texelFetch(colortex1,pixel,0).a==2.0",lens)  # 手持物不参与景深。
