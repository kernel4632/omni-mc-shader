"""新增流程与配置边界回归；示例 python -m unittest discover -s tests。

离线只检查可观察协议与工具结果，不声称像素、设备或性能通过。
"""
import json  # 构造版本配置输入。
import contextlib  # 捕获共享审计调用的输出。
import io  # 验证库函数不写终端。
import hashlib  # 包内容与校验文件真实对照。
import tempfile  # 临时目录不改用户文件。
import unittest  # 保留标准测试入口。
import zipfile  # 检查实际交付资源白名单。
from pathlib import Path  # 检查输出边界。
from unittest.mock import patch  # 模拟发布前置条件，不执行版本控制。
import audit  # 实际词法注释统计。
import build  # 实际流程与打包接口。
import game  # 实际回归与性能汇总。
import options  # 选项扫描与菜单接口。
import config  # 配置读写与版本格式来源。

class PipelineTests(unittest.TestCase):
    """检查自有代码、配置、缓冲和安全发布协议。"""
    def test_entries_have_explicit_flow_and_dimensions(self):
        """全部生成入口均有配对与显式主体引用，计算入口使用更高版本。"""
        files = build.program_files()  # 读取真实流程表。
        for path,text in files.items():  # 全部入口核对来源。
            if path.suffix==".csh":  # 计算阶段需要更高版本与计算选择宏。
                self.assertTrue(text.startswith("#version 430")); self.assertIn("#define OMNI_COMPUTE",text)
            else:  # 基础绘制入口保持兼容版本。
                self.assertTrue(text.startswith("#version 330 compatibility"))  # 兼容版本必须第一行。
            self.assertIn('#include "/rendering/',text)  # 不依赖加载器猜回退。
            self.assertEqual(text,path.read_text(encoding="utf-8"))  # 实际入口没有遗漏维度宏。
        dimensions = json.loads((build.SHADERS / "rendering/programs.json").read_text(encoding="utf-8"))["dimensions"]  # 维度到声明文件的映射是唯一来源。
        for path,text in files.items():  # 每个入口在引入主体前都要引入本维度的中间画面与常量声明。
            declaration = dimensions[path.parent.name]["buffers"] + ".glsl"  # 这个维度登记的那份声明文件。
            self.assertIn(f'#include "/rendering/{declaration}"',text)  # 声明必须真的进入被编译的程序，加载器才会读取它。
        for folder in ("world0", "world-1", "world1"):
            self.assertIn(build.SHADERS / folder / "setup.csh", files)  # 每个维度都登记计算入口。
        self.assertIn(build.SHADERS / "world0/composite1.fsh", files)  # 主世界有水后雾阶段。
        self.assertNotIn(build.SHADERS / "world-1/composite1.fsh", files)  # 参考光影的下界没有这个阶段。

    def test_buffer_history_and_snapshot_contract(self):
        """跨帧历史不清除；每个程序写出的画面编号与移植合同一致。"""
        buffers = (build.SHADERS / "rendering/buffers.glsl").read_text(encoding="utf-8")
        self.assertIn("colortex1Clear = false", buffers); self.assertIn("colortex2Clear = false", buffers); self.assertIn("colortex7Clear = false", buffers)  # 场景颜色、全局光历史与时间抗锯齿历史跨帧保留。
        self.assertIn("colortex0Clear = true", buffers); self.assertIn("colortex5Clear = true", buffers)  # 贴图色与高光材质每帧重写。
        source_numbers = build.numbered_sources()  # 四个入口引用同一棵源码树，编号只建立一次。
        expanded: dict = {}  # 已展开文本只在本次测试内复用，不改业务语义也不改断言内容。
        def drawbuffers(name: str) -> str:
            """展开 `world0` 下名为 `name` 的入口，返回可搜索附件指令的文本。"""
            return build.expand(build.SHADERS / "world0" / name, sourceNumbers=source_numbers, cache=expanded)  # 共用缓存，避免每个断言都重读重拼整棵树。
        self.assertIn("DRAWBUFFERS:7", drawbuffers("deferred.fsh"))  # 焦散法线写在七号。
        self.assertIn("DRAWBUFFERS:460", drawbuffers("gbuffers_water.fsh"))  # 半透明层写四号、六号与贴图色。
        self.assertIn("DRAWBUFFERS:1", drawbuffers("composite.fsh"))  # 不透明光照写一号。
        self.assertIn("DRAWBUFFERS:7", drawbuffers("composite7.fsh"))  # 时间抗锯齿历史写七号。
        programs = json.loads((build.SHADERS / "rendering/programs.json").read_text(encoding="utf-8"))["programs"]
        for name in ("gbuffers_weather", "gbuffers_damagedblock", "gbuffers_armor_glint"):
            self.assertEqual(programs[name][0], "overlay", name)  # 不写深度的覆盖程序共用叠加绘制主体。
        self.assertEqual(programs["gbuffers_spidereyes"][0], "entities")  # 蜘蛛眼与实体共用实体绘制主体。

    def test_tessellation_pair_and_source_map(self):
        """细分不完整时拒绝，引用映射保留原始行号。"""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)  # 独立入口组。
            for suffix in ("vsh","fsh","tcs"):
                (folder/("a."+suffix)).write_text("#version 330 compatibility\nvoid main(){}\n",encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"缺少配对入口"):
                build.entrypoints(folder)  # 缺少细分评价阶段。
            (folder/"a.tes").write_text("#version 330 compatibility\nvoid main(){}\n",encoding="utf-8")
            self.assertEqual(len(build.entrypoints(folder)),4)  # 完整阶段组被识别。
            (folder/"part.glsl").write_text("float value=1.0;\n",encoding="utf-8")
            (folder/"a.fsh").write_text('#version 330 compatibility\n#include "/part.glsl"\nvoid main(){}\n',encoding="utf-8")
            expanded = build.expand(folder/"a.fsh",folder)  # 源映射不丢失。
            self.assertIn("#line 1",expanded); self.assertIn("#line 3",expanded)  # 引用前后都能对应源行。

    def test_config_migration_reset_and_unknown_values(self):
        """旧配置迁移后补齐默认，非法输入不会静默通过。"""
        found,_ = options.scan(build.SHADERS)  # 真实源码取范围。
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"old.json"  # 不修改真实共享配置。
            data = {"schemaVersion":1,"shaderVersion":"0.0.0-dev.3","values":{"OMNI_DEBUG_VIEW":"2"}}
            source.write_text(json.dumps(data),encoding="utf-8")
            migrated = config.shared(source,found,build.version())  # 调用真实迁移。
            self.assertEqual(migrated["schemaVersion"],2); self.assertEqual(set(migrated["values"]),set(found))  # 迁移不会留下上一套参数。
            config.save(root/".dev/user.json",migrated["values"],build.version(),root)
            self.assertEqual(config.shared(root/".dev/user.json",found,build.version()),migrated)  # 导出可再次导入。
            with self.assertRaises(ValueError): config.save(root/"player.json",{},build.version(),root)  # 用户目录不能成为输出。
            for values in ({"UNKNOWN":"1"},{"OMNI_EXPOSURE":"9"},{"OMNI_EXPOSURE":2}):
                data["values"] = values; source.write_text(json.dumps(data),encoding="utf-8")
                with self.assertRaises(ValueError): config.shared(source,found,build.version())  # 未知键值都失败。
            data["values"]={}; data["shaderVersion"]="9.0.0"; source.write_text(json.dumps(data),encoding="utf-8")
            with self.assertRaises(ValueError): config.shared(source,found,build.version())  # 没有未来版本迁移规则。
            loadable = root/".dev/load.properties"
            config.save_properties(loadable,migrated["values"],build.version(),root)  # 导出路径保持加载器使用的properties格式。
            text = loadable.read_text(encoding="ascii")
            self.assertIn(f"# @shaderVersion {build.version()}",text); self.assertEqual(config.shared(loadable,found,build.version()),migrated)  # properties能再次导入且版本来自当前源码。

    def test_option_rename_migrates_old_names(self):
        """旧选项名按对照表迁移到当前名，新旧名同时出现时拒绝导入。"""
        self.assertGreater(len(config.OPTION_RENAMES), 0)  # 对照表为空时这条测试没有意义。
        old, new = next(iter(config.OPTION_RENAMES.items()))  # 取任意一条真实对照做验证。
        self.assertEqual(config.rename({old: "1"}), {new: "1"})  # 旧名落到当前名下。
        self.assertEqual(config.rename({"OMNI_KEEP_ME": "1"}), {"OMNI_KEEP_ME": "1"})  # 未登记的名字原样保留，交给选项边界报错。
        with self.assertRaisesRegex(ValueError, "同时给了旧名与新名"):
            config.rename({old: "1", new: "1"})  # 两个来源冲突时不能替玩家猜。
        self.assertGreater(len(config.VALUE_RENAMES), 0)  # 开关改成多档的取值迁移也要有人用。
        option, values = next(iter(config.VALUE_RENAMES.items()))  # 取任意一条取值对照。
        for oldValue, newValue in values.items():
            self.assertEqual(config.rename({option: oldValue}), {option: newValue})  # 旧真假值换成新档位。
        found, _ = options.scan(build.SHADERS)  # 真实源码取范围。
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"legacy.json"  # 不修改真实共享配置。
            if new not in found:
                return  # 该对照只是安装器旧名（当前源码没有同名选项）时无需继续验证导入。
            data = {"schemaVersion": config.SHARE_SCHEMA, "shaderVersion": build.version(),
                    "values": {old: found[new].default}}  # 用旧名给一个当前选项。
            source.write_text(json.dumps(data), encoding="utf-8")
            migrated = config.shared(source, found, build.version())  # 走真实导入路径。
            self.assertEqual(migrated["values"][new], found[new].default)  # 旧名确实被迁移到新名上。
            self.assertGreater(len(config.REMOVED_OPTIONS), 0)  # 被替换掉的选项清单也要有人用。
            removed = next(iter(config.REMOVED_OPTIONS))
            data["values"] = {removed: "16"}  # 旧配置里残留的已移除选项。
            source.write_text(json.dumps(data), encoding="utf-8")
            migrated = config.shared(source, found, build.version())  # 导入应当通过并被忽略，而不是报未知选项。
            self.assertNotIn(removed, migrated["values"])  # 已移除的项不再出现在结果里。

    def test_comment_audit_ignores_normal_strings(self):
        """只有注释和接口文档算中文，字符串不能凑比例。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); source = root/"subject.py"
            source.write_text('value="普通字符串中的中文"\n',encoding="utf-8")
            with self.assertRaises(ValueError): audit.check(root)  # 中文界面文案不是注释。
            source.write_text('"""中文接口职责。"""\nvalue=1 # 保留真实业务输入。\n',encoding="utf-8")
            self.assertEqual(audit.check(root)[0]["ratio"],1.0)  # 尾注与文档块都正确计数。

    def test_comment_audit_library_call_does_not_write_stdout(self):
        """共享审计调用只返回结果，避免Windows非UTF8输出流编码失败。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root/"subject.py").write_text('"""中文接口职责。"""\nvalue=1 # 保存业务值。\n',encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()) as output:
                result = audit.check(root)  # 调用库函数不应该打印中文。
            self.assertEqual(output.getvalue(),""); self.assertEqual(result[0]["ratio"],1.0)  # CLI报告由build入口负责。

    def test_release_requires_prompt_without_mutation(self):
        """自动任务没有交互确认时，发布不会写版本或标签。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root/"VERSION").write_text("0.0.0-dev.4\n",encoding="utf-8")
            notes = root/"notes.md"; notes.write_text("本次修改说明",encoding="utf-8")
            with patch.object(build,"ROOT",root),patch.object(build.subprocess,"run") as run,patch.object(build.sys.stdin,"isatty",return_value=False):
                def git_result(command,**kwargs):
                    """模拟只读预检，测试不执行真实提交。"""
                    result = unittest.mock.Mock()  # 返回真实进程同样的输出字段。
                    outputs = {("branch","--show-current"):"main",("ls-remote","--heads","origin","main"):"abc refs/heads/main",("rev-parse","HEAD"):"abc"}  # 模拟干净且同步的主分支。
                    result.stdout = outputs.get(tuple(command[1:]),"")  # 测试必须抵达交互确认边界。
                    return result
                run.side_effect = git_result  # 所有版本控制调用均隔离。
                with self.assertRaisesRegex(ValueError,"未明确确认发布"): build.release("0.0.0-dev.5",notes)
                self.assertTrue(all(call.args[0][1] not in ("add","commit","tag","push") or call.args[0][1:3]==["tag","--list"] for call in run.call_args_list))  # 确认之前没有版本控制写入。
            self.assertEqual((root/"VERSION").read_text(encoding="utf-8"),"0.0.0-dev.4\n")  # 失败前版本保持原值。

    def test_frame_input_and_real_statistics(self):
        """真实帧间隔计算慢帧，混合交换链和无效样本失败。"""
        context = {k:"测试条件" for k in ("device","driver","scene","resolution","preset","minecraft","iris")}
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/"frames.csv"  # 不伪装成项目性能基线。
            source.write_text("ProcessID,SwapChainAddress,MsBetweenPresents\n"+"7,one,10\n"*19+"7,one,30\n",encoding="utf-8")
            report = game.frame_report(source,7,context)  # 汇总保留慢帧。
            self.assertEqual(report["meanFrameMs"],11.0); self.assertEqual(report["p99FrameMs"],30.0)  # 慢帧没有被平均掩盖。
            source.write_text("ProcessID,SwapChainAddress,MsBetweenPresents\n"+"7,one,NaN\n"*20,encoding="utf-8")
            with self.assertRaises(ValueError): game.frame_report(source,7,context)  # 无效数不能声称性能通过。

    def test_regression_stays_in_development_world(self):
        """回归准备只写专用世界，报告保持未运行。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); world = root/".dev/minecraft/saves/test"; world.mkdir(parents=True)
            (world/"level.dat").write_bytes(b"fixture")  # 仅测试路径门槛，不把它当真实世界。
            with patch.object(game,"ROOT",root):
                pack = game.regression("test",99)
                self.assertTrue((pack/"data/omni/function/setup.mcfunction").is_file())  # 有可执行场景命令。
                setup = (pack/"data/omni/function/setup.mcfunction").read_text(encoding="utf-8")
                self.assertIn("minecraft:advance_time false",setup); self.assertNotIn("doDaylightCycle",setup)  # 当前游戏规则名称已核对。
                self.assertIn("tag=omni_test",setup)  # 重复准备只清理工具自己的实体。
                self.assertEqual(json.loads((root/".dev/reports/regression.json").read_text(encoding="utf-8"))["scenes"]["day"]["status"],"未运行")
                with self.assertRaises(ValueError): game.regression("../player",99)  # 不允许逃逸到其他存档。

    def test_runtime_dependency_whitelist(self):
        """没有运行库时仍拒绝第三方目录的未登记文件。"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); shaders = root/"shaders"; (shaders/"libraries").mkdir(parents=True)
            (root/"dependencies.json").write_text('{"schemaVersion":1,"libraries":[]}',encoding="utf-8")
            (root/"THIRD_PARTY.md").write_text("未导入运行库",encoding="utf-8")
            with patch.object(build,"ROOT",root),patch.object(build,"SHADERS",shaders):
                self.assertIn("THIRD_PARTY.md",build.dependencies())  # 必要声明会进入产物。
                (shaders/"libraries/unlisted.glsl").write_text("float x;",encoding="utf-8")
                with self.assertRaises(ValueError): build.dependencies()  # 白名单不能漏掉新代码。

    def test_every_runtime_dependency_is_referenced(self):
        """登记的第三方库必须至少被一个光影文件引用，避免再次留下死依赖。"""
        text = "\n".join(  # 自有光影文件的全部引用文本，库自身不算对自己的引用。
            path.read_text(encoding="utf-8") for path in build.SHADERS.rglob("*")
            if path.is_file() and "libraries" not in path.relative_to(build.SHADERS).parts and path.suffix in {".glsl", ".vsh", ".fsh", ".gsh", ".csh", ".properties"}
        )
        def assert_referenced(libraries):
            """逐个检查登记的库文件都被引用；许可原文随包但不参与引用。"""
            for item in libraries:  # 每个已登记的库都要真的接入。
                for reference in item["files"]:
                    if any(tag in reference.lower() for tag in ("license", "copying")):  # 许可原文跳过。
                        continue
                    name = reference.rsplit("/", 1)[-1]  # 完整路径匹配 `#include`，文件名匹配 `pipeline.properties` 里的资源引用。
                    self.assertTrue(reference in text or name in text, f"{reference} 未被任何光影文件引用，属于死依赖")
        data = json.loads((build.ROOT/"dependencies.json").read_text(encoding="utf-8"))  # 运行库唯一清单。
        assert_referenced(data["libraries"])  # 当前清单必须全部接入。
        with self.assertRaises(AssertionError): assert_referenced([{"files": {"libraries/dead/omni_library_name_guard.glsl": "0"*64}}])  # 未引用的库必须被这条检查挡住，证明它不是空跑。

    def test_pack_contents_are_reproducible_and_complete(self):
        """真实打包包含各维度入口和完整预设，不包含参考、开发配置或过期流程源。"""
        found,profiles,_ = build.configuration()  # 所有预设从当前源码补齐。
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)  # 产物只写自有临时位置。
            with patch.object(build,"ROOT",root),patch.object(build,"configuration",return_value=(found,profiles,{})),patch.object(build,"dependencies",return_value={"THIRD_PARTY.md":b"license manifest"}):
                (root/"presets").mkdir(); (root/"presets/README.md").write_text("共享说明",encoding="utf-8")
                first = build.pack(); before = [p.read_bytes() for p in first]  # 第一次真实压缩结果。
                second = build.pack()
                self.assertEqual(before,[p.read_bytes() for p in second])  # 重复打包字节相同。
                with zipfile.ZipFile(first[0]) as package:
                    names = set(package.namelist())
                    self.assertIn("shaders/world0/gbuffers_terrain.fsh",names)  # 官方旧维度规则从world0加载主世界。
                    self.assertIn("shaders/world-1/composite.fsh",names)
                    self.assertNotIn("shaders/gbuffers_terrain.fsh",names)  # 根目录可执行程序会被worldN忽略，不随包放重复入口。
                    self.assertIn("THIRD_PARTY.md",names); self.assertIn("VERSION",names)  # 来源与版本可追溯。
                    self.assertNotIn("shaders/rendering/programs.json",names); self.assertNotIn("shaders/rendering/pipeline.properties",names)  # 开发源表已经生成实际入口和加载器设置。
                    self.assertTrue(all(not n.startswith(("references/",".dev/")) for n in names))  # 不带玩家或参考数据。
                with zipfile.ZipFile(first[1]) as package:
                    self.assertEqual(json.loads(package.read("manifest.json"))["schemaVersion"],2)  # 分享格式版本正确。
                    for preset in profiles:
                        keys = {line.split("=",1)[0] for line in package.read(preset.name+".properties").decode().splitlines() if line and not line.startswith("#")}  # 版本标记是说明，不是加载器选项。
                        self.assertEqual(keys,set(found))  # 每套预设完整替换所有选项。
                self.assertIn(hashlib.sha256(first[0].read_bytes()).hexdigest(),first[2].read_text(encoding="ascii"))  # 校验值来自实际包。

    def test_json_duplicate_keys_are_rejected(self):
        """分享 JSON 的重复字段不能悄悄覆盖值。"""
        found,_ = options.scan(build.SHADERS)  # 合法范围仍从源码读取。
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/"duplicate.json"
            source.write_text('{"schemaVersion":2,"shaderVersion":"0.0.0-dev.4","values":{"OMNI_EXPOSURE":"1","OMNI_EXPOSURE":"2"}}',encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"重复配置字段"): config.shared(source,found,build.version())  # 不同解析器不能得到不同风格。
