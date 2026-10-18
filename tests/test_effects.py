"""效果回归：检查选项接入、预处理分支与算法边界，不宣称像素效果。

示例 python -m unittest discover -s tests；全部使用离线展开，不建立显卡上下文。
扫描、展开与效果原文由 tests/support.py 共享一次，`verify` 的十秒预算内不重复读取整棵源码树。
"""
import re  # 从源码与流程表提取选项引用、格式指令与引入标记。
import subprocess  # 用真实预处理器验证选项确实改变分支。
import tempfile  # 探针源码只写入临时目录，不碰项目文件。
import unittest  # 保留标准测试入口。
from pathlib import Path  # 临时探针文件固定在自有目录。
import build  # 读取真实流程表、原生选项与编译器位置。
import options  # 核对菜单分类与流程设置解析。
import support  # 共享扫描、展开与效果原文缓存。

DESCENDING_EDGES = {"end.glsl": "末地行星阴影与大气米散射用下降遮罩，照 iterationT 原样保留", "end_sky.glsl": "末地大气米散射的下降遮罩随算法体拆到该文件，照 iterationT 原样保留", "snow.glsl": "积雪融化阶段用下降遮罩判断雪量区间，照 Eclipse 原样保留"}  # 允许反序阈值的文件，值写明原因。


class EffectTests(unittest.TestCase):
    """逐个效果核对选项单源、算法接入和默认路径，全部断言离线可查。"""

    # --- 单源、结构与生成协议 ---
    def test_fixed_smoothstep_edges_are_ordered(self):
        """效果目录里的固定阈值必须严格递增；`end.glsl` 的下降遮罩按 iterationT 保留并在此登记。"""
        files = sorted((build.SHADERS / "effects").rglob("*.glsl"))  # 效果已按页面分文件夹，遍历子目录才不会空跑。
        self.assertGreaterEqual(len(files), 20, f"效果文件只有 {len(files)} 个，遍历范围可能写错")  # 少于下限说明匹配规则失效，直接失败而不是假通过。
        checked = 0  # 统计真正读到公式的文件数，佐证不是空跑。
        for path in files:  # 只检查自有效果，不改第三方源码。
            text = path.read_text(encoding="utf-8")  # 每个效果原文。
            for match in re.finditer(r"smoothstep\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,", text):
                checked += 1  # 有公式才算覆盖到。
                low, high = float(match[1]), float(match[2])  # 两个固定阈值。
                with self.subTest(path=path.name, formula=match[0]):  # 失败直接指出公式所在文件。
                    self.assertNotEqual(low, high)  # 相等阈值在任何驱动上都是未定义计算。
                    if low > high:  # 反序阈值只有在登记过的下降遮罩里才允许。
                        self.assertIn(path.name, DESCENDING_EDGES)  # 未登记的下降遮罩要报出来。
                    else:
                        self.assertLess(low, high)  # 正序阈值必须严格递增。
        self.assertGreater(checked, 0, "没有读到任何 smoothstep 固定阈值")  # 完全没有公式说明遍历写错。

    def test_include_guards_never_collide(self):
        """引入标记不能和程序宏或选项同名，否则定义了该宏的程序会整段跳过这个文件。"""
        found, _, _ = support.configuration()  # 真实选项名来自原生声明。
        data = support.programs()  # 流程表给出全部程序与维度宏。
        writes = {name + suffix for name in data["programs"] for suffix in (".fsh", ".vsh")}  # 只统计程序与阶段名。
        for setting in data["dimensions"].values():  # 维度宏来自维度对象。
            writes.add(setting["define"])  # 维度宏也是程序级标识。
        for path in build.SHADERS.rglob("*.glsl"):
            match = re.search(r"#ifndef (\w+)\s*(?://[^\n]*)?\n#define \1\b", path.read_text(encoding="utf-8"))  # 文件开头的引入标记。
            if not match:
                continue  # 没有引入标记的文件不参与。
            with self.subTest(path=path.name):
                self.assertNotIn(match[1], writes)  # 和程序宏同名会让整段代码被跳过。
                self.assertNotIn(match[1], found)  # 和选项同名会让玩家开关变成引入标记。

    def test_const_vector_constructors_match_their_type(self):
        """加载器解析 `const` 声明，`vecN` 构造函数必须给足分量个数，简写会被拒绝并让整包加载失败。"""
        constructor = re.compile(r"const\s+(vec[234])\s+\w+\s*=\s*(vec[234])\(([^;]*)\)\s*;")  # 只匹配同类型构造。
        for path in build.SHADERS.rglob("*"):
            if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh", ".gsh"):
                continue  # 只检查自有着色源码。
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                match = constructor.search(line)  # 一行里最多一条声明。
                if not match or match[1] != match[2]:
                    continue  # 类型不一致交给编译器报错，这里只管分量个数。
                arguments = [part for part in re.split(r",(?![^()]*\))", match[3]) if part.strip()]  # 只数顶层逗号分隔的参数。
                with self.subTest(path=path.name, line=number):
                    self.assertEqual(len(arguments), int(match[1][3]))  # 分量个数必须等于 `vecN` 的 N。

    def test_buffer_format_directives_are_bare_and_defined(self):
        """格式指令必须放在块注释里、每行只写指令本身，行尾说明会让加载器读不到，自己定义格式名又会让它读到数字。"""
        files = {name: support.text(f"rendering/{name}.glsl") for name in ("buffers", "buffers_main", "buffers_nether", "buffers_end")}  # 共享声明与三个维度声明都遵守同一格式规则。
        for name, text in files.items():
            with self.subTest(file=name):
                commented = re.sub(r"/\*.*?\*/", "", text, flags=re.S)  # 去掉块注释后，源码里不应再有格式指令。
                self.assertNotIn("Format", commented)  # 指令只在块注释里出现。
                self.assertNotRegex(text, r"#define RGBA\d+F")  # 格式名交由加载器提供，包内不重复定义。
        self.assertRegex(files["buffers"], r"const int colortex0Format = RGBA8;")  # 三维度共用的零号八位。
        self.assertRegex(files["buffers"], r"const int colortex1Format = RGBA16;")  # 三维度共用的一号十六位。
        self.assertRegex(files["buffers_main"], r"const int colortex8Format = RGBA8;")  # 主世界八号放大输出八位。
        self.assertRegex(files["buffers_nether"], r"const int colortex7Format = RGBA32F;")  # 下界时间抗锯齿历史必须三十二位浮点。
        self.assertRegex(files["buffers_nether"], r"const int colortex8Format = RGB16;")  # 下界八号十六位。
        self.assertRegex(files["buffers_end"], r"const int colortex8Format = RGB16;")  # 末地八号十六位。

    def test_dimension_buffer_constants_declared_once(self):
        """按维度不同的常量只在各自维度文件写一次，共用常量只在共享文件写一次，避免加载器取到重复值。"""
        shared = support.text("rendering/buffers.glsl")  # 三维度共用的声明。
        per = {name: support.text(f"rendering/{name}.glsl") for name in ("buffers_main", "buffers_nether", "buffers_end")}  # 三份维度声明。
        differing = ("colortex7Format", "colortex8Format", "shadowDistanceRenderMul", "shadowHardwareFiltering1", "shadowtex0Mipmap", "ambientOcclusionLevel")  # 只在某个维度不同的六项。
        for name in differing:
            with self.subTest(constant=name):
                self.assertNotIn(f" {name} = ", shared)  # 共用文件不写按维度不同的常量。
                for dimension, body in per.items():
                    self.assertEqual(body.count(f" {name} = "), 1, dimension)  # 每个维度各写一次。
        for name in ("colortex0Format", "colortex1Format", "colortex6Format", "noiseTextureResolution", "eyeBrightnessHalflife", "shadowIntervalSize"):
            with self.subTest(constant=name):
                self.assertEqual(shared.count(f" {name} = "), 1)  # 共用常量只在共享文件出现一次。
                for dimension, body in per.items():
                    self.assertEqual(body.count(f" {name} = "), 0, dimension)  # 维度文件不再重复声明。

    def test_dimension_program_sets_match_reference(self):
        """每个维度只生成自己登记的程序：缺席程序不出现，几何阶段只给登记过的程序，且本项目没有细分入口。"""
        generated = build.program_files()  # 读取真实生成入口。
        data = support.programs()  # 流程表是维度与程序的唯一来源。
        self.assertTrue(all(p.suffix != ".tcs" and p.suffix != ".tes" for p in generated), "本项目不应生成细分入口")  # 细分阶段没有登记就不得出现。
        for dimension, setting in data["dimensions"].items():
            absent = set(setting.get("absent", []))  # 这个维度没有的程序。
            geometry = set(setting.get("geometry", []))  # 需要额外生成几何阶段的程序。
            expected = set()  # 该维度应有入口文件名。
            for name in data["programs"]:
                if name in absent:
                    continue  # 缺席程序不生成。
                expected |= {name + ".vsh", name + ".fsh"}  # 顶点片元始终配对。
                if name in geometry:
                    expected.add(name + ".gsh")  # 只有登记过的程序生成几何阶段。
            expected |= {name + ".csh" for name in data.get("compute", {})}  # 计算入口每个维度都有。
            actual = {p.name for p in generated if p.parent.name == dimension}  # 该维度实际生成的文件名。
            with self.subTest(dimension=dimension):
                self.assertEqual(actual, expected)  # 一个不多一个不少。

    def test_every_dimension_entry_includes_own_buffers(self):
        """每个维度生成的入口引入本维度那份声明文件，加载器只会从被编译的程序里读到 `const` 指令。"""
        generated = build.program_files()  # 真实入口文本。
        data = support.programs()  # 维度到声明文件的映射。
        for path, text in generated.items():
            declaration = data["dimensions"][path.parent.name]["buffers"] + ".glsl"  # 这个维度登记的那份声明。
            with self.subTest(entry=path.name, dimension=path.parent.name):
                self.assertIn(f'#include "/rendering/{declaration}"', text)  # 声明必须真的进入入口。

    def test_programs_reference_declared_bodies_and_macros(self):
        """流程表里的绘制主体库与程序宏都必须有效，拼错会让入口引用缺失文件或选出错误分支。"""
        data = support.programs()  # 流程表唯一来源。
        for name, (rendering, *defines) in data["programs"].items():
            with self.subTest(program=name):
                self.assertTrue((build.SHADERS / "rendering" / (rendering + ".glsl")).is_file())  # 绘制主体库必须存在。
                self.assertTrue(all(re.fullmatch(r"OMNI_[A-Z0-9_]+", flag) for flag in defines))  # 程序宏使用受控名称。
        for name, (rendering, *defines) in data.get("compute", {}).items():
            with self.subTest(compute=name):
                self.assertTrue((build.SHADERS / "rendering" / (rendering + ".glsl")).is_file())  # 计算主体库也必须存在。

    def test_options_are_not_reduced_since_parity(self):
        """移植合同登记的 iterationT 选项一个都不能少，名字按合同加前缀并修正已知拼写。"""
        found, _, _ = support.configuration()  # 当前真实选项。
        rename = {
            "SEREEN_RATIO": "SCREEN_RATIO",
            "DOF_DEPTH_SMMOOTH_HALFLIFE": "DOF_DEPTH_SMOOTH_HALFLIFE",
            "CLOUD_CLEAR_COVERY": "CLOUD_CLEAR_COVERAGE",
            "CLOUD_RAIN_COVERY": "CLOUD_RAIN_COVERAGE",
            "MOTION_BLUR_SUTTER_ANGLE": "MOTION_BLUR_SHUTTER_ANGLE",
            "ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE": "ACCRETIONDISC_DETAIL_ALONG_LONGITUDE",
        }  # 合同第九节登记的拼写修正。
        native = {"shadowMapResolution", "shadowDistance", "sunPathRotation", "wetnessHalflife", "drynessHalflife"}  # 加载器原生常量保留原名。
        listed = []  # 合同登记的 iterationT 选项原名。
        for line in (build.ROOT / "docs/parity.md").read_text(encoding="utf-8").splitlines():
            match = re.match(r"^- `effects/[a-z_/]+\.glsl`\uff08[0-9]+\uff09\uff1a(.+)$", line)  # 只取“选项归属”小节的行。
            if not match:
                continue  # 无关段落跳过。
            for part in match.group(1).split("\u3001"):  # 逗号分隔的选项名。
                single = re.fullmatch(r"`([A-Za-z_][A-Za-z0-9_]*)`", part.strip())  # 只接受反引号包裹的单个名字。
                if single:
                    listed.append(single.group(1))
        self.assertGreater(len(listed), 200, "合同清单没有解析出内容，规则可能已改变")  # 解析失败不能让测试假通过。
        missing = sorted({item if item in native else "OMNI_" + rename.get(item, item) for item in listed} - set(found))  # 合同有而代码没有的名字。
        self.assertEqual(missing, [])  # 一个都不允许缺失。

    def test_pipeline_conditions_reference_existing_options(self):
        """流程设置的条件和程序开关只能引真实选项，拼错会让某个阶段永远按错误分支执行。"""
        found, _, _ = support.configuration()  # 当前真实选项。
        settings = options.read_pipeline(build.SHADERS / "rendering/pipeline.properties")  # 结构解析必须通过。
        self.assertIsInstance(settings, dict)  # 解析结果用于确认流程设置没有语法错误。
        referenced = set()  # 收集条件与开关里引用的选项名。
        for line in support.text("rendering/pipeline.properties").splitlines():
            stripped = line.strip()  # 逐行判断条件或键值。
            if stripped.startswith("#"):
                referenced |= set(re.findall(r"\b(OMNI_[A-Z0-9_]+)\b", stripped))  # 条件行里的选项名。
                continue  # 条件行不参与键值解析。
            key, _, value = stripped.partition("=")  # 程序开关是 `键=值` 形式。
            if key.strip().endswith(".enabled"):
                referenced |= set(re.findall(r"\b(OMNI_[A-Z0-9_]+)\b", value))  # 开关值直接写选项名。
        self.assertTrue(referenced, "流程设置里没有读到任何选项引用")  # 解析失败不能让测试假通过。
        for name in sorted(referenced):
            with self.subTest(option=name):
                self.assertIn(name, found)  # 引用的名字必须是真实选项。

    def test_boolean_options_change_a_branch(self):
        """每个布尔选项都要在某处按定义与否区分分支，否则加载器不认它，菜单项无法解析。"""
        found, _, _ = support.configuration()  # 当前真实选项。
        text = "\n".join(p.read_text(encoding="utf-8") for p in build.SHADERS.rglob("*") if p.suffix in (".glsl", ".vsh", ".fsh", ".csh", ".gsh", ".properties"))  # 一次读全部逻辑源码与流程设置。
        conditional = set()  # 条件里出现过的标识符。
        conditional |= set(re.findall(r"#\s*(?:ifdef|ifndef)\s+(\w+)", text))  # 直接开关写法。
        conditional |= set(re.findall(r"defined\s*\(?\s*(\w+)", text))  # 复合条件里的写法。
        for line in re.findall(r"#\s*(?:if|elif)\b[^\n]*", text):
            conditional |= set(re.findall(r"\b\w+\b", line))  # 数值比较条件里的标识符。
        conditional |= set(re.findall(r"=\s*(OMNI_[A-Z0-9_]+)\s*$", text, re.M))  # 程序开关按选项名挑选。
        for name, option in found.items():
            if option.values != ("false", "true"):
                continue  # 只检查布尔选项。
            with self.subTest(option=name):
                self.assertIn(name, conditional)  # 必须真的被读。

    def test_every_option_has_tooltip(self):
        """每个选项都要有悬停说明，玩家才能不靠猜来调。"""
        found, _, _ = support.configuration()  # 真实选项与说明。
        missing = [name for name, option in found.items() if not option.description]  # 缺说明的选项直接列出来。
        self.assertEqual(missing, [], missing)  # 缺一不可。

    # --- 菜单生成 ---
    def test_menu_pages_cover_every_category(self):
        """生成菜单覆盖全部主分类，且每个分类至少有一个选项，不出现空分类。"""
        found, _, _ = support.configuration()  # 真实扫描结果。
        known = {name for name, _ in options.MAIN_PAGES}  # 主分类只在一处定义。
        used = {options.page_of(option) for option in found.values()}  # 每个选项实际落在的页面。
        self.assertEqual(used <= known, True, used - known)  # 不允许选项落到未登记的页面。
        self.assertEqual(known <= used, True, known - used)  # 不允许出现空分类。

    def test_menu_subpages_and_value_labels(self):
        """一个分类有多个效果时折叠成子页面，档位按钮显示玩家能看懂的取值名称。"""
        _, _, files = support.configuration()  # 真实生成文件。
        menu = files[build.SHADERS / "shaders.properties"]  # 读取真实生成内容。
        self.assertIn("screen.SKY = ", menu)  # 天空分类存在。
        self.assertIn("screen.SKY_SKY_ATMOSPHERE = ", menu)  # 天空下的子页面自带选项列表。
        self.assertIn("screen.WATER_WATER_WATER = OMNI_WAVE_SCALE", menu)  # 水面基础选项落在自己的子页面。
        self.assertIn("screen.WATER_WATER_WAVESIM = OMNI_WAVE_SIMULATION", menu)  # 波浪模拟独立成一个水面子页面。
        self.assertIn("screen.CLOUD = OMNI_PLANAR_CLOUDS", menu)  # 单效果分类保持平铺，不建子页面。
        lang = files[build.SHADERS / "lang" / "zh_cn.lang"]  # 中文翻译文件。
        self.assertIn("value.OMNI_TONEMAP_OPERATOR.0=AgX", lang)  # 色调映射的档位名称已生成。
        self.assertIn("value.OMNI_DEBUG_VIEW.0=", lang)  # 调试视图的档位名称已生成。

    def test_lightweight_preset_disables_heavy_effects(self):
        """轻量预设关闭时间抗锯齿、体积云、云影、体积雾、`GTAO` 与半影阴影等较重的默认效果。"""
        _, profiles, _ = support.configuration()  # 真实预设。
        lightweight = next(profile for profile in profiles if profile.name == "lightweight")  # 找到轻量预设。
        for name in ("OMNI_TAA", "OMNI_VOLUMETRIC_CLOUDS", "OMNI_CLOUD_SHADOW", "OMNI_VFOG", "OMNI_UNDERWATER_VFOG", "OMNI_GTAO", "OMNI_VARIABLE_PENUMBRA_SHADOWS", "OMNI_WATER_PARALLAX", "OMNI_CAUSTICS", "OMNI_ENABLE_PBR", "OMNI_BLOOM"):
            self.assertIn(lightweight.values[name], ("false", "0"), name)  # 每个较重的效果在轻量预设里都被关闭。

    def test_extra_features_default_neutral(self):
        """项目自己的额外功能默认关闭或取中性值，默认画面与 iterationT 一致。"""
        found, _, _ = support.configuration()  # 真实选项与默认值。
        off = ("OMNI_AURORA", "OMNI_RAINBOW", "OMNI_LIGHTNING", "OMNI_SEASONS", "OMNI_SNOW_OVERLAY", "OMNI_LPV_ENABLED", "OMNI_PROFILER", "OMNI_FSR", "OMNI_DOF", "OMNI_LENS_FLARE", "OMNI_LINE_IMAGE_OUTPUT", "OMNI_CLOUD_CIRRUS", "OMNI_CLOUD_ALTOSTRATUS", "OMNI_SHADER_GRASS")
        for name in off:
            with self.subTest(option=name):
                self.assertEqual(found[name].default, "false")  # 额外功能默认关闭。
        neutral = {"OMNI_DEBUG_VIEW": "0", "OMNI_SURFACE_WETNESS": "0.0", "OMNI_SEASON_TINT": "0.0", "OMNI_AURORA_TINT": "0.0", "OMNI_CLOUD_SPEED": "1.0", "OMNI_CLOUD_CUMULONIMBUS": "0"}  # 数值型额外功能取中性值；积雨云是三档，零档即关闭。
        for name, value in neutral.items():
            with self.subTest(option=name):
                self.assertEqual(found[name].default, value)  # 默认不改变关键分支。

    # --- 效果能力：按新实现检查选项是否改变分支或输出 ---
    def test_tonemap_operator_and_gamma(self):
        """色调映射算子可选、显示伽马可调，最终阶段按算子序号分派。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_TONEMAP_OPERATOR"].values, ("0", "1", "2"))  # 三档算子。
        self.assertIn("OMNI_GAMMA", found)  # 显示伽马可调。
        post = support.text("effects/color/post_tonemap.glsl")  # 分派在后期色调映射效果文件里。
        self.assertIn("#if OMNI_TONEMAP_OPERATOR == 1", post)  # 一档取 ACES。
        self.assertIn("#elif OMNI_TONEMAP_OPERATOR == 2", post)  # 二档取无压缩曲线。
        self.assertIn("AgX(color)", post)  # 默认走 AgX。

    def test_bloom_switch_and_amount(self):
        """泛光可开关、强度可调，合并阶段按选项叠加；雾内泛光与水下雾内泛光都可调并接入合并。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_BLOOM"].values, ("false", "true"))  # 泛光可开关。
        self.assertIn("OMNI_BLOOM_AMOUNT", found)  # 泛光强度可调。
        self.assertIn("OMNI_FOG_BLOOM", found)  # 雾内泛光强度可调。
        self.assertEqual(found["OMNI_FOG_BLOOM"].default, "0.0")  # 默认关闭，画面不变。
        self.assertIn("OMNI_UNDERWATER_FOG_BLOOM", found)  # 水下雾内泛光强度可调。
        self.assertEqual(found["OMNI_UNDERWATER_FOG_BLOOM"].default, "0.0")  # 默认关闭，画面不变。
        bloom = support.text("effects/color/bloom.glsl")  # 泛光主体。
        self.assertIn("MergeBloom", bloom)  # 合并泛光独立成函数。
        self.assertIn("OMNI_BLOOM_AMOUNT", bloom)  # 强度参与合并。
        self.assertIn("OMNI_FOG_BLOOM", bloom)  # 雾内泛光参与合并。
        self.assertIn("OMNI_UNDERWATER_FOG_BLOOM", bloom)  # 水下雾内泛光参与合并。
        scene = support.text("effects/world/composite_scene.glsl")  # 合成五号写泛光引导。
        self.assertIn("compositeOutput3.a = 1.0 - fogTransmittance", scene)  # 体积雾吸收存进三号引导。
        self.assertIn("MergeBloom", support.text("effects/color/post_tonemap.glsl"))  # 后期色调映射效果文件调用合并。

    def test_auto_exposure_controls(self):
        """自动曝光的手动模式、测光方式、平滑、时间与三项曝光增益都可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_MANUAL_EXPOSURE", "OMNI_AE_MODE", "OMNI_AE_OFFSET", "OMNI_SMOOTH_EXPOSURE", "OMNI_EXPOSURE_TIME",
                     "OMNI_EXPOSURE_MULTIPLIER", "OMNI_EXPOSURE_DARKENING", "OMNI_EXPOSURE_BRIGHTENING"):
            self.assertIn(name, found)  # 每个曝光参数由调色源码定义。
        color = support.text("effects/color/color.glsl")  # 曝光在调色主体。
        self.assertIn("GetExposureValue", color)  # 求曝光值独立成函数。
        self.assertIn("OMNI_AE_MODE", color)  # 测光方式参与曝光。
        self.assertIn("OMNI_MANUAL_EXPOSURE", color)  # 手动模式参与曝光。
        self.assertIn("OMNI_EXPOSURE_MULTIPLIER * OMNI_EXPOSURE_DARKENING * OMNI_EXPOSURE_BRIGHTENING", color)  # 三项增益叠在曝光值上。

    def test_gtao_controls(self):
        """地平线遮蔽可开关，质量、半径模式与强度都可调并接入合成。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_GTAO", "OMNI_GTAO_QUALITY", "OMNI_GTAO_RADIUS_MODE", "OMNI_GTAO_STRENGTH", "OMNI_GTAO_MULTIBOUNCE"):
            self.assertIn(name, found)  # 每个遮蔽参数由环境光源码定义。
        gtao = support.text("effects/lighting/gtao.glsl")  # 遮蔽主体（按算法从入口拆出）。
        self.assertIn("GroundTruthBasedAmbientOcclusion", gtao)  # 遮蔽独立成函数。
        self.assertIn("GTAOMultiBounce", gtao)  # 多次反弹独立成函数。
        self.assertIn("OMNI_GTAO_STRENGTH", gtao)  # 强度参与遮蔽系数。
        self.assertIn("gtao.glsl", support.text("effects/lighting/ambient.glsl"))  # 入口按引入顺序展开遮蔽文件。
        self.assertIn("GroundTruthBasedAmbientOcclusion", support.text("effects/lighting/composite_surface_nether.glsl"))  # 合成零号的下界变体调用遮蔽。

    def test_gi_rsm_controls(self):
        """反射阴影图全局光可开关，质量、半径与亮度都可调并接入延迟阶段。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_GI_RSM", "OMNI_GI_QUALITY", "OMNI_GI_RADIUS", "OMNI_GI_BRIGHTNESS"):
            self.assertIn(name, found)  # 每个全局光参数由环境光源码定义。
        gi = support.text("effects/lighting/gi.glsl")  # 全局光主体（按算法从入口拆出）。
        self.assertIn("RSM(", gi)  # 反射阴影图独立成函数。
        self.assertIn("GI_TemporalFilter", gi)  # 时间滤波独立成函数。
        self.assertIn("#ifdef OMNI_GI_RSM", gi)  # 延迟阶段按选项执行空间滤波与时间滤波。

    def test_shadow_penumbra_and_bias(self):
        """可变半影阴影可开关、质量与展开可调，阴影偏置参与投影压缩。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_VARIABLE_PENUMBRA_SHADOWS", "OMNI_VPS_QUALITY", "OMNI_VPS_SPREAD", "OMNI_SHADOW_MAP_BIAS", "OMNI_SHADOW_BASIC_BLUR"):
            self.assertIn(name, found)  # 每个阴影参数由阴影源码定义。
        shadow = support.text("effects/shadow/shadow.glsl")  # 阴影主体。
        self.assertIn("VariablePenumbraShadow", shadow)  # 半影阴影独立成函数。
        self.assertIn("#ifdef OMNI_VARIABLE_PENUMBRA_SHADOWS", shadow)  # 由选项分出开关分支。
        self.assertIn("OMNI_SHADOW_MAP_BIAS", shadow)  # 偏置参与投影压缩。

    def test_screen_space_shadow_and_colored_shadow(self):
        """屏幕空间阴影与彩色阴影都可开关，屏幕空间阴影对玩家另有独立开关。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_SCREEN_SPACE_SHADOWS", "OMNI_DISABLE_PLAYER_SCREEN_SPACE_SHADOWS", "OMNI_COLORED_SHADOWS"):
            self.assertIn(name, found)  # 三个阴影开关由阴影源码定义。
        shadow = support.text("effects/shadow/shadow.glsl")  # 阴影主体（阴影图坐标与可变半影）。
        self.assertIn("screen_shadow.glsl", shadow)  # 入口按引入顺序展开屏幕空间阴影文件。
        self.assertIn("ScreenSpaceShadow", support.text("effects/shadow/screen_shadow.glsl"))  # 屏幕空间阴影独立成函数。
        self.assertIn("OMNI_COLORED_SHADOWS", shadow)  # 彩色阴影参与着色。

    def test_sky_moon_texture_and_stars(self):
        """月亮贴图、天空盒贴图、星空类型与亮度都可调，天体贴图在天空程序里分派。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_MOON_TEXTURE", "OMNI_SKYBOX_TEXTURE", "OMNI_STAR_TYPE", "OMNI_STARS_AMOUNT", "OMNI_NIGHT_BRIGHTNESS"):
            self.assertIn(name, found)  # 每个天空参数由天空源码定义。
        sky = support.text("effects/sky/sky.glsl")  # 天空入口，选项与内部常数在这里。
        self.assertIn("RenderMoonDisc", support.text("effects/sky/sun_moon.glsl"))  # 月盘独立成函数。
        self.assertIn("CalculateStars", support.text("effects/sky/stars.glsl"))  # 星空独立成函数。
        self.assertIn("OMNI_STAR_TYPE", sky)  # 星空类型参与计算。
        celestial = support.text("rendering/celestial.glsl")  # 天体贴图程序。
        self.assertIn("#ifdef OMNI_MOON_TEXTURE", celestial)  # 月亮贴图决定是否叠加。
        self.assertIn("#ifndef OMNI_SKYBOX_TEXTURE", celestial)  # 关闭天空盒时回退。

    def test_atmosphere_extras_strengths(self):
        """极光、彩虹、闪电可开关且强度可调，默认关闭不影响 iterationT 画面。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_AURORA", "OMNI_RAINBOW", "OMNI_LIGHTNING", "OMNI_AURORA_STRENGTH", "OMNI_RAINBOW_STRENGTH", "OMNI_LIGHTNING_STRENGTH"):
            self.assertIn(name, found)  # 每个额外天空参数由氛围源码定义。
        atmosphere = support.text("effects/sky/atmosphere.glsl")  # 氛围主体。
        self.assertIn("omniAurora", atmosphere)  # 极光独立成函数。
        self.assertIn("omniRainbow", atmosphere)  # 彩虹独立成函数。
        self.assertIn("omniLightning", atmosphere)  # 闪电独立成函数。
        self.assertIn("omniLightningVolume", atmosphere)  # 闪电对体积云与体积雾的照明也在这里定义。
        self.assertIn("*OMNI_AURORA_STRENGTH", atmosphere)  # 极光强度参与着色。
        cloud = support.text("effects/cloud/volumetric.glsl")  # 体积云主体。
        self.assertIn("omniLightningVolume", cloud)  # 体积云接到闪电照明。
        self.assertIn("marchingPos - cameraPosition", cloud)  # 云采样点换成相机相对坐标后再比闪电距离。
        fog = support.text("effects/fog/volumetric.glsl")  # 体积雾主体。
        self.assertIn("omniLightningVolume", fog)  # 体积雾接到闪电照明。
        self.assertIn("lightningFogLight", fog)  # 闪电点亮的空气按每步吸收量累加。

    def test_cloud_styles_selectable(self):
        """云提供平面与体积两种做法，切换后延迟阶段绘制不同分支，两者共用同一套天气与颜色来源。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_PLANAR_CLOUDS"].values, ("false", "true"))  # 平面云可开关。
        self.assertEqual(found["OMNI_VOLUMETRIC_CLOUDS"].values, ("false", "true"))  # 体积云可开关。
        skyrender = support.text("effects/sky/skyrender.glsl")  # 云在延迟三号主体、天空盒与主天空共用一段累积。
        self.assertIn("#ifdef OMNI_PLANAR_CLOUDS", skyrender)  # 平面云分支存在。
        self.assertIn("#ifdef OMNI_VOLUMETRIC_CLOUDS", skyrender)  # 体积云分支存在。
        self.assertIn("PlanarClouds", support.text("effects/cloud/planar.glsl"))  # 平面云做法存在。
        self.assertIn("NubisCumulus", support.text("effects/cloud/volumetric.glsl"))  # 体积云做法存在。

    def test_cloud_step_controls(self):
        """体积云步数由采样数上限与精细度倍率共同决定，两者都接入步进。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertIn("OMNI_CLOUD_SAMPLES", found)  # 采样数由云源码定义。
        self.assertIn("OMNI_CLOUD_QUALITY", found)  # 精细度倍率仍在。
        cloud = support.text("effects/cloud/volumetric.glsl")  # 体积云主体。
        self.assertIn("OMNI_CLOUD_SAMPLES -", cloud)  # 采样数参与步数上限。
        self.assertIn("marchingSteps * OMNI_CLOUD_QUALITY", cloud)  # 倍率参与步数。

    def test_cloud_shadow_controls(self):
        """云影可开关，范围、贴图尺寸与淡出都可调，并接入直射光与雾。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_CLOUD_SHADOW", "OMNI_CLOUD_SHADOW_RANGE", "OMNI_CLOUD_SHADOWTEX_SIZE", "OMNI_CLOUD_SHADOW_FADE"):
            self.assertIn(name, found)  # 每个云影参数由云源码定义。
        cloud = support.text("effects/cloud/shadow.glsl")  # 云影主体。
        self.assertIn("CloudShadowFromTex", cloud)  # 云影采样独立成函数。
        self.assertIn("OMNI_CLOUD_SHADOW_RANGE", cloud)  # 范围参与贴图坐标。
        self.assertIn("OMNI_CLOUD_SHADOWTEX_SIZE", cloud)  # 贴图尺寸参与分辨率。
        self.assertIn("#ifdef OMNI_CLOUD_SHADOW", support.text("effects/lighting/sunlight.glsl"))  # 直射光按云影压低。

    def test_cloud_layer_options(self):
        """卷云、高层云与积雨云作为附加云层可开关，积雨云照 Eclipse 分三档，各自的高度、厚度与覆盖可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_CLOUD_CIRRUS", "OMNI_CLOUD_ALTOSTRATUS", "OMNI_CLOUD_CUMULONIMBUS", "OMNI_CLOUD_CIRRUS_ALTITUDE", "OMNI_CLOUD_ALTOSTRATUS_THICKNESS", "OMNI_CLOUD_CUMULONIMBUS_COVERAGE"):
            self.assertIn(name, found)  # 每个附加云层参数由云源码定义。
        self.assertEqual(found["OMNI_CLOUD_CUMULONIMBUS"].values, ("0", "1", "2"))  # 积雨云照 Eclipse 的 `0/1/2` 分三档。
        cloud = support.text("effects/cloud/volumetric.glsl")  # 体积云主体。
        self.assertIn("NubisExtraLayers", cloud)  # 附加层独立成函数。
        self.assertIn("#if OMNI_CLOUD_CUMULONIMBUS == 1", cloud)  # 中档按雷暴强度分派。
        self.assertIn("OMNI_CLOUD_FADE", found)  # 云淡出可开关。
        self.assertIn("OMNI_CLOUD_FADE", cloud)  # 淡出参与可见度。

    def test_cloud_weather_sets(self):
        """晴天与雨天各有一套覆盖、厚度、密度与受光，按湿润度切换。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_CLOUD_CLEAR_COVERAGE", "OMNI_CLOUD_RAIN_COVERAGE", "OMNI_CLOUD_CLEAR_THICKNESS", "OMNI_CLOUD_RAIN_THICKNESS", "OMNI_CLOUD_CLEAR_SUNLIGHTING", "OMNI_CLOUD_RAIN_SUNLIGHTING"):
            self.assertIn(name, found)  # 每个晴雨参数由云源码定义。
        cloud = support.text("effects/cloud/volumetric.glsl")  # 体积云主体。
        self.assertIn("OMNI_CLOUD_CLEAR_COVERAGE", cloud)  # 晴天覆盖参与云量。
        self.assertIn("OMNI_CLOUD_RAIN_COVERAGE", cloud)  # 雨天覆盖参与云量。
        self.assertIn("OMNI_CLOUD_RAIN_SUNLIGHTING", cloud)  # 雨天受光参与着色。

    def test_volumetric_fog_parameters(self):
        """体积雾可开关，步数与噪声类型可选，密度、高度与衰减都可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_VFOG"].values, ("false", "true"))  # 体积雾可开关。
        for name in ("OMNI_VFOG_QUALITY", "OMNI_VFOG_NOISE_TYPE", "OMNI_VFOG_DENSITY", "OMNI_VFOG_HEIGHT", "OMNI_VFOG_FALLOFF"):
            self.assertIn(name, found)  # 每个体积雾参数由雾源码定义。
        fog = support.text("effects/fog/volumetric.glsl")  # 体积雾主体。
        self.assertIn("VolumetricFog", fog)  # 体积雾独立成函数。
        self.assertIn("const float steps = OMNI_VFOG_QUALITY", fog)  # 步数来自选项。
        self.assertIn("OMNI_VFOG_FALLOFF", fog)  # 衰减参与高度密度。

    def test_underwater_volumetric_fog(self):
        """水下体积雾可开关、浓度可调，复用同一份阴影可见性且接入折射。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_UNDERWATER_VFOG"].values, ("false", "true"))  # 水下体积雾可开关。
        self.assertIn("OMNI_UNDERWATER_VFOG_DENSITY", found)  # 浓度可调。
        fog = support.text("effects/fog/underwater_fog.glsl")  # 水下体积雾主体。
        self.assertIn("UnderwaterVolumetricFog", fog)  # 水下体积雾独立成函数。
        self.assertIn("OMNI_UNDERWATER_VFOG_DENSITY", fog)  # 浓度参与散射。
        self.assertIn("#ifdef OMNI_UNDERWATER_VFOG", support.text("effects/reflection/screenspace.glsl"))  # 反射路径按选项叠加水下光柱。

    def test_land_atmospheric_scattering_and_indoor_fog(self):
        """地表大气散射与室内雾都可开关，浓度与距离可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_LANDSCATTERING", "OMNI_LANDSCATTERING_STRENGTH", "OMNI_LANDSCATTERING_DISTANCE", "OMNI_INDOOR_FOG"):
            self.assertIn(name, found)  # 每个雾参数由雾源码定义。
        fog = support.text("effects/fog/landscattering.glsl")  # 地面大气散射主体。
        self.assertIn("LandAtmosphericScattering", fog)  # 地表散射独立成函数。
        self.assertIn("OMNI_LANDSCATTERING_DISTANCE", fog)  # 距离参与散射。

    def test_water_wave_options(self):
        """水面波尺度与波高可调，视差可开关，法线由同一波高函数生成。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_WAVE_SCALE", "OMNI_WAVE_HEIGHT", "OMNI_WATER_PARALLAX"):
            self.assertIn(name, found)  # 每个水波参数由水源码定义。
        waves = support.text("effects/water/waves.glsl")  # 波浪主体（按算法从入口拆出）。
        self.assertIn("GetWaves", waves)  # 波浪高度独立成函数。
        self.assertIn("GetWavesNormal", waves)  # 波浪法线独立成函数。
        self.assertIn("GetWaterParallaxCoord", waves)  # 视差坐标独立成函数。
        self.assertIn("OMNI_WAVE_HEIGHT", waves)  # 波高参与法线梯度。

    def test_water_optics_and_caustics(self):
        """水体吸收、透射与焦散都可调，水下雾复用同一份水体吸收。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_UNDERWATER_FOG", "OMNI_WATER_FOG_DENSITY", "OMNI_CAUSTICS", "OMNI_PUDDLE_MODE"):
            self.assertIn(name, found)  # 每个水参数由水源码定义。
        self.assertIn("WaterFog", support.text("effects/water/waterfog.glsl"))  # 水下水雾独立成函数。
        self.assertIn("TransparentAbsorption", support.text("effects/water/refraction.glsl"))  # 彩色玻璃吸收独立成函数。
        self.assertIn("CalculateWaterCaustics", support.text("effects/shadow/water_caustics.glsl"))  # 焦散来自阴影文件夹里的焦散算法。

    def test_rain_ripple_options(self):
        """雨点涟漪的强度与对比可调，两者都作用在同一个雨点法线上，默认都为一、画面不变。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_RAIN_RIPPLE_STRENGTH", "OMNI_RAIN_RIPPLE_CONTRAST"):
            self.assertIn(name, found)  # 两个选项由水源码定义。
            self.assertEqual(found[name].default, "1.0")  # 默认为一，乘一与取一次幂都是原样。
        rain = support.text("effects/water/rain.glsl")  # 雨点涟漪主体（按算法从入口拆出）。
        self.assertIn("OMNI_RAIN_RIPPLE_STRENGTH", rain)  # 强度乘在雨点法线上。
        self.assertIn("OMNI_RAIN_RIPPLE_CONTRAST", rain)  # 对比指数作用在雨点法线上。

    def test_reflection_raytrace_options(self):
        """屏幕空间反射可调射线数量、细分步数与深度差阈值，默认画面不变。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_RAYTRACE_QUALITY", "OMNI_RAYTRACE_REFINEMENT_STEPS", "OMNI_RAYTRACE_ZDIFF_THRESHOLD"):
            self.assertIn(name, found)  # 每个反射参数由反射源码定义。
        reflection = support.text("effects/reflection/reflection.glsl")  # 反射入口（选项在这里）。
        self.assertIn("screenspace.glsl", reflection)  # 入口按引入顺序展开屏幕空间反射算法。
        screenspace = support.text("effects/reflection/screenspace.glsl")  # 屏幕空间反射算法（按算法从入口拆出）。
        self.assertIn("ScreenSpaceTracer", screenspace)  # 屏幕空间追踪独立成函数。
        self.assertIn("CalculateSpecularReflections", screenspace)  # 镜面反射独立成函数。
        self.assertIn("OMNI_RAYTRACE_QUALITY", screenspace)  # 质量参与采样数。

    def test_reflection_sky_fallback(self):
        """屏幕外反射回退到同一套天空与云，回退函数在反射主体里独立实现。"""
        screenspace = support.text("effects/reflection/screenspace.glsl")  # 屏幕空间反射算法（按算法从入口拆出）。
        self.assertIn("ComputeFakeSkyReflection", screenspace)  # 假天空反射独立成函数。
        self.assertIn("CalculateSpecularReflections", screenspace)  # 反射入口保留。
        self.assertIn("#include", support.text("effects/reflection/reflection.glsl"))  # 反射入口仍按统一引入顺序引用依赖。

    def test_material_pbr_parallax(self):
        """物理光照、视差模式与次表面散射都可开关或调速，材质主体按选项分派。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_ENABLE_PBR"].values, ("false", "true"))  # 物理光照可开关。
        for name in ("OMNI_PARALLAX_MODE", "OMNI_PARALLAX_QUALITY", "OMNI_PARALLAX_SHADOW", "OMNI_SSS_STRENGTH"):
            self.assertIn(name, found)  # 每个材质参数由材质源码定义。
        material = support.text("effects/ground/material.glsl")  # 材质主体。
        self.assertIn("ParallaxOcclusionMapping", material)  # 视差独立成函数。
        self.assertIn("OMNI_ENABLE_PBR", material)  # 物理光照开关参与材质。
        self.assertIn("OMNI_PARALLAX_MODE", material)  # 视差模式参与分派。

    def test_torchlight_colour_temperature(self):
        """火把光亮度与色温可调，黑体色温函数把色温换成颜色。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_TORCHLIGHT_BRIGHTNESS", "OMNI_TORCHLIGHT_COLOR_TEMPERATURE"):
            self.assertIn(name, found)  # 火把光参数由方块光源码定义。
        blocklight = support.text("effects/lighting/blocklight.glsl")  # 方块光主体。
        self.assertIn("OMNI_TORCHLIGHT_COLOR_TEMPERATURE", blocklight)  # 色温参与火把光着色。
        self.assertIn("BlockLighting", blocklight)  # 方块光独立成函数。

    def test_heldlight_and_flashlight(self):
        """手持光模式、亮度与衰减可调，附带位置与视野参数。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_HELDLIGHT_MODE", "OMNI_HELDLIGHT_BRIGHTNESS", "OMNI_HELDLIGHT_FALLOFF", "OMNI_FLASHLIGHT_FOV"):
            self.assertIn(name, found)  # 每个手持光参数由方块光源码定义。
        held = support.text("effects/lighting/held_light.glsl")  # 手持光源主体（按算法从入口拆出）。
        self.assertIn("HeldLighting", held)  # 手持光独立成函数。
        self.assertIn("OMNI_FLASHLIGHT_FOV", held)  # 视野参与聚光形状。

    def test_taa_options(self):
        """时间抗锯齿可开关，混合权重与攻击性可调，后期阶段按选项执行重投影。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_TAA"].values, ("false", "true"))  # 时间抗锯齿可开关。
        for name in ("OMNI_TAA_BLENDWEIGHT", "OMNI_TAA_AGGRESSION", "OMNI_DISABLE_HAND_TAA"):
            self.assertIn(name, found)  # 每个时间抗锯齿参数由清晰度源码定义。
        self.assertIn("taa.glsl", support.text("effects/clarity/antialiasing.glsl"))  # 入口按引入顺序展开 TAA 核心。
        taa = support.text("effects/clarity/taa.glsl")  # 时间抗锯齿核心（按算法从入口拆出）。
        self.assertIn("TemporalReprojection", taa)  # 重投影独立成函数。
        self.assertIn("OMNI_TAA_BLENDWEIGHT", taa)  # 混合权重参与累积。
        self.assertIn("#ifdef OMNI_TAA", support.text("effects/clarity/antialiasing.glsl"))  # 后期时间抗锯齿主体按选项执行。

    def test_fsr_and_cas(self):
        """`FSR` 放大可开关、锐化与去噪可调，`CAS` 锐化强度独立可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_FSR"].values, ("false", "true"))  # 放大可开关。
        for name in ("OMNI_FSR_SHARPNESS", "OMNI_FSR_DENOISE", "OMNI_CAS_SHARPNESS", "OMNI_CAS_DENOISE"):
            self.assertIn(name, found)  # 每个放大参数由清晰度源码定义。
        upscale = support.text("effects/clarity/upscale.glsl")  # 放大主体。
        self.assertIn("FidelityFX_CAS", upscale)  # `CAS` 锐化独立成函数。
        self.assertIn("FidelityFX_FSR1", upscale)  # `FSR` 放大独立成函数。
        self.assertIn("OMNI_FSR_SHARPNESS", upscale)  # 锐化强度参与权重。
        self.assertIn("#ifdef OMNI_FSR", support.text("rendering/final.glsl"))  # 最终阶段按选项放大。

    def test_fsr_switch_survives_real_preprocessing(self):
        """真实预处理器里，季节开关关闭时走关闭分支、开启后走启用分支。"""
        found, _, _ = support.configuration()  # 选项替换沿用真实菜单定义。
        source = "#version 330 compatibility\n" + support.expand(build.SHADERS / "effects/weather/season.glsl")  # 展开依赖后的真实效果文本。
        source += "\n#ifdef OMNI_SEASONS\nconst bool seasonOn = true;\n#else\nconst bool seasonOn = false;\n#endif\n"  # 用可观察输出标出实际选中的分支。
        defaults = {name: option.default for name, option in found.items()}  # 开启时仅修改目标选项。
        with tempfile.TemporaryDirectory() as temporary:
            shader = Path(temporary) / "probe.frag"  # 不碰项目入口和构建缓存。
            for enabled, text in ((False, source), (True, build.option_source(source, found, defaults | {"OMNI_SEASONS": "true"}))):
                with self.subTest(enabled=enabled):
                    shader.write_text(text, encoding="utf-8")  # 每次用同一实际预处理器读取探针。
                    result = subprocess.run([str(build.tool("glslang")), "-E", str(shader)], capture_output=True, text=True, encoding="utf-8", errors="replace")
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)  # 预处理错误同样必须失败。
                    self.assertRegex(result.stdout, rf"seasonOn\s*=\s*{str(enabled).lower()}\s*;")  # 检查真正的分支结果而非宏名字。

    def test_lens_flare_and_glare(self):
        """镜头炫光与光斑都可开关，亮度可调，按屏幕太阳位置叠加。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_LENS_GLARE", "OMNI_LENS_FLARE", "OMNI_GLARE_BRIGHTNESS", "OMNI_FLARE_BRIGHTNESS"):
            self.assertIn(name, found)  # 每个镜头光参数由镜头源码定义。
        glare = support.text("effects/lens/glare.glsl")  # 眩光与光斑主体（按算法从入口拆出）。
        self.assertIn("LensFlare", glare)  # 光斑独立成函数。
        self.assertIn("#ifdef OMNI_LENS_FLARE", glare)  # 按选项分出光斑分支。
        self.assertIn("OMNI_FLARE_BRIGHTNESS", glare)  # 亮度参与叠加。

    def test_dof_controls(self):
        """景深可开关，模糊半径、质量与焦外散景形状都可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_DOF"].values, ("false", "true"))  # 景深可开关。
        for name in ("OMNI_DOF_BLUR", "OMNI_DOF_QUALITY", "OMNI_DOF_MAX_COC", "OMNI_DOF_CATSEYE"):
            self.assertIn(name, found)  # 每个景深参数由镜头源码定义。
        dof = support.text("effects/lens/dof.glsl")  # 景深主体（按算法从入口拆出）。
        self.assertIn("DepthOfField", dof)  # 景深独立成函数。
        self.assertIn("OMNI_DOF_QUALITY", dof)  # 质量参与采样数。
        self.assertIn("#ifdef OMNI_DOF", support.text("rendering/post.glsl"))  # 后期阶段按选项执行景深。

    def test_motion_blur_and_vignette(self):
        """运动模糊与暗角都可开关，快门角与暗角参数可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_MOTION_BLUR", "OMNI_MOTION_BLUR_SHUTTER_ANGLE", "OMNI_VIGNETTE", "OMNI_VIGNETTE_FALLOFF"):
            self.assertIn(name, found)  # 每个镜头参数由镜头源码定义。
        lens = support.text("effects/lens/lens.glsl")  # 镜头入口，暗角留在入口。
        self.assertIn("Vignette", lens)  # 暗角独立成函数。
        motion = support.text("effects/lens/motion_blur.glsl")  # 相机动态模糊主体（按算法从入口拆出）。
        self.assertIn("MotionBlur", motion)  # 运动模糊独立成函数。
        self.assertIn("OMNI_MOTION_BLUR_SHUTTER_ANGLE", motion)  # 快门角参与位移。

    def test_lens_distortion_resamples_current_source(self):
        """镜头形变重采样当前路径的源画面：开放大时用八号放大画面，避免把放大结果丢掉。"""
        distortion = support.text("effects/lens/distortion.glsl")  # 镜头形变主体。
        self.assertIn("LensDistortion(sampler2D source", distortion)  # 源画面由调用方传入。
        self.assertNotIn("texture(colortex1", distortion)  # 不再把低分辨率一号画面写死进形变。
        final = support.text("rendering/final.glsl")  # 调用方。
        self.assertIn("LensDistortion(colortex8", final)  # 放大路径重采样放大画面。
        self.assertIn("LensDistortion(colortex1", final)  # 非放大路径重采样一号画面。

    def test_shader_grass_and_block_buffer(self):
        """程序化草默认关闭且只在主世界编译；地形写九号方块编号缓冲，草阶段按世界坐标查询。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_SHADER_GRASS"].default, "false")  # 默认关闭，默认画面不变。
        self.assertEqual(found["OMNI_REPLACE_SHORT_GRASS"].values, ("0", "1", "2"))  # 替换矮草有否/是/仅矮草三档。
        for name in ("OMNI_GRASS_BASE_HEIGHT", "OMNI_GRASS_SHORT_HEIGHT", "OMNI_GRASS_DETECT_FALLOFF", "OMNI_GRASS_DETECT_INV_FALLOFF"):
            self.assertIn(name, found)  # 两套高度与邻接检测都来自草效果源码。
        grass = support.text("effects/ground/grass.glsl")  # 草效果主体。
        self.assertIn("omniGrassWindOffset", grass)  # 摆动独立成函数。
        self.assertIn("omniGrassBlockAt", grass)  # 方块编号查询独立成函数。
        self.assertIn("//#define OMNI_SHADER_GRASS", grass)  # 关闭是唯一默认。
        geometry = support.text("effects/ground/grass_geometry.glsl")  # 草几何主体。
        self.assertIn("OMNI_GRASS_DETECT_FALLOFF", geometry)  # 底部检测参与高度。
        self.assertIn("OMNI_GRASS_DETECT_INV_FALLOFF", geometry)  # 侧向检测参与高度。
        self.assertIn("OMNI_SHORT_GRASS_BLOCK_ID", geometry)  # 仅矮草档按矮草方块生长。
        terrain = support.text("rendering/terrain.glsl")  # 地形主体。
        self.assertIn('/effects/ground/grass.glsl"', terrain)  # 地形引入草效果。
        self.assertIn("#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD", terrain)  # 只在主世界且开启时编译。
        self.assertIn("DRAWBUFFERS:0359", terrain)  # 地形多写九号方块编号画面。
        self.assertIn("colortex9Clear = false", support.text("rendering/buffers.glsl"))  # 方块编号跨帧保留。
        self.assertIn("block.85 = grass_block", support.text("block.properties"))  # 草方块编号是八十五。

    def test_vegetation_winding(self):
        """植物摆动可开关，阴影阶段另有独立开关，摆动在世界空间推移顶点。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_WAVING_PLANTS"].values, ("false", "true"))  # 摆动可开关。
        self.assertIn("OMNI_SHADOW_WAVING_PLANTS", found)  # 阴影摆动可单独开关。
        vegetation = support.text("effects/ground/vegetation.glsl")  # 摆动主体。
        self.assertIn("WavingPlants", vegetation)  # 摆动独立成函数。
        self.assertIn("OMNI_WAVING_PLANTS", vegetation)  # 开关参与分支。

    def test_weather_rain_options(self):
        """雨雪可见度、扰动与风向都可调，雨天压暗只作用于露天处。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_RAIN_VISIBILITY", "OMNI_RAIN_DISTURBANCE", "OMNI_RAIN_WIND_X", "OMNI_RAIN_WIND_Z"):
            self.assertIn(name, found)  # 每个天气参数由天气源码定义。
        weather = support.text("effects/weather/weather.glsl")  # 天气主体。
        self.assertIn("Rain(", weather)  # 雨着色独立成函数。
        self.assertIn("RainWindOffset", weather)  # 风向独立成函数。
        self.assertIn("OMNI_RAIN_VISIBILITY", weather)  # 可见度参与着色。

    def test_surface_wetness(self):
        """地表湿润可手动设定，雨滴溅射可开关，湿润量参与地面底色。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_RAIN_SPLASH_EFFECT"].values, ("false", "true"))  # 溅射可开关。
        self.assertIn("OMNI_SURFACE_WETNESS", found)  # 手动湿润可调。
        weather = support.text("effects/weather/weather.glsl")  # 天气主体。
        self.assertIn("OMNI_SURFACE_WETNESS", weather)  # 手动湿润参与计算。
        self.assertIn("OMNI_RAIN_SPLASH_EFFECT", weather)  # 溅射开关参与分支。

    def test_season_colour(self):
        """季节可开关、整体色调可调，只对植被顶点色着色，默认关闭。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_SEASONS"].default, "false")  # 默认关闭。
        self.assertIn("OMNI_SEASON_TINT", found)  # 季节颜色可调。
        season = support.text("effects/weather/season.glsl")  # 季节主体。
        self.assertIn("omniSeason", season)  # 季节着色独立成函数。
        self.assertIn("#ifdef OMNI_SEASONS", season)  # 关闭时原样返回。
        self.assertIn("OMNI_SEASON_TINT", season)  # 色调参与着色。

    def test_snow_overlay(self):
        """积雪覆盖可开关、强度可调，默认关闭时函数与贴图都不被编译；底色、法线与粗糙度三张贴图都接入。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_SNOW_OVERLAY"].default, "false")  # 默认关闭。
        self.assertIn("OMNI_SNOW_OVERLAY_STRENGTH", found)  # 强度可调。
        snow = support.text("effects/weather/snow.glsl")  # 积雪主体。
        self.assertIn("omniSnowOverlay", snow)  # 积雪独立成函数。
        self.assertIn("#ifdef OMNI_SNOW_OVERLAY", snow)  # 关闭时不增加代码。
        for name in ("snowTexA", "snowTexN", "snowTexR"):  # 三张贴图都在函数体里采样。
            self.assertIn(name, snow)  # 底色、法线、粗糙度各一张，缺一就是没接入。
        self.assertIn("inout vec3 normal", snow)  # 法线通过 `inout` 传回，参与光照。
        self.assertIn("inout float smoothness", snow)  # 粗糙度以平滑度通过 `inout` 传回五号画面。
        self.assertIn("#ifdef OMNI_SNOW_OVERLAY", support.text("effects/ground/terrain_surface.glsl"))  # 地形片元主函数体按开关调用。
        self.assertIn("omniSnowOverlay", support.text("rendering/entities.glsl"))  # 实体与方块实体也调用同一份函数。

    def test_entity_status_and_hand_fov(self):
        """实体状态色与眼部光照可开关，手持物视野模式与角度可调。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_ENTITIES_STATUS_COLOR", "OMNI_EYES_LIGHTING", "OMNI_HAND_FOV_MODE", "OMNI_HAND_FOV"):
            self.assertIn(name, found)  # 每个实体参数由实体源码定义。
        entity = support.text("effects/entity/entity.glsl")  # 实体主体。
        self.assertIn("EntityStatusColor", entity)  # 状态色独立成函数。
        self.assertIn("HandFovProjection", entity)  # 手持物投影独立成函数。
        self.assertIn("OMNI_HAND_FOV", entity)  # 视野角参与投影。

    def test_dh_world_options(self):
        """远景剔除、贴图噪声与区块淡入都可调，远景主体按选项分派。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_DH_TERRAIN_CULLING", "OMNI_DH_TEXTURE_NOISE", "OMNI_DH_TEXTURE_NOISE_STEPS", "OMNI_DH_CHUNK_FADING"):
            self.assertIn(name, found)  # 每个远景参数由世界源码定义。
        world = support.text("effects/world/world.glsl")  # 世界主体。
        self.assertIn("DH_noise", world)  # 远景噪声独立成函数。
        self.assertIn("DHTerrainCulling", world)  # 远景剔除独立成函数。
        self.assertIn("OMNI_DH_TEXTURE_NOISE", world)  # 噪声开关参与分支。

    def test_nether_dimension_options(self):
        """下界配色亮度可调，下界雾有合成二号与合成五号两个重载。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertIn("OMNI_NETHER_BRIGHTNESS", found)  # 下界亮度由下界源码定义。
        nether = support.text("effects/world/nether.glsl")  # 下界主体。
        self.assertIn("NetherLighting", nether)  # 下界光照独立成函数。
        self.assertIn("NetherFog", nether)  # 下界雾独立成函数。
        self.assertIn("OMNI_NETHER_BRIGHTNESS", nether)  # 亮度参与着色。

    def test_end_dimension_options(self):
        """末地行星、港口岛光照与雾都可调，末地天空接入合成阶段。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_END_PLANET_CYCLE", "OMNI_END_MANUAL_PLANET_ANGLE", "OMNI_END_ISLAND_LIGHT", "OMNI_END_FOG_STORM_DENSITY", "OMNI_END_FOG_HAZE_DENSITY"):
            self.assertIn(name, found)  # 每个末地参数由末地源码定义。
        end_sky = support.text("effects/world/end_sky.glsl")  # 末地星空与行星主体。
        self.assertIn("PlanetEnd2", end_sky)  # 末地行星独立成函数。
        self.assertIn("EndCalculateStars", end_sky)  # 末地星空使用带 `End` 前缀的函数名。
        self.assertIn("EndFog", support.text("effects/world/end_fog.glsl"))  # 末地雾独立成函数。
        self.assertIn("PlanetEnd2", support.text("effects/lighting/composite_surface_end.glsl"))  # 合成零号的末地变体调用末地行星。

    def test_debug_view_and_profiler(self):
        """调试视图与性能计时都可开关，默认关闭时不改变画面。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_DEBUG_VIEW"].default, "0")  # 调试视图默认关闭。
        self.assertEqual(found["OMNI_PROFILER"].default, "false")  # 性能计时默认关闭。
        debug = support.text("effects/dev/debug.glsl")  # 调试主体。
        self.assertIn("debugColor", debug)  # 调试视图独立成函数。
        self.assertIn("omniProfiler", debug)  # 性能计时独立成函数。
        self.assertIn("#ifdef OMNI_PROFILER", debug)  # 关闭时不增加代码。
        self.assertIn("debugColor", support.text("rendering/final.glsl"))  # 最终阶段调用调试视图。

    def test_lpv_compute_options(self):
        """光传播体积可开关、体积大小可选，计算阶段填方块光表与传播，片元阶段混回方块光。"""
        found, _, _ = support.configuration()  # 真实选项。
        self.assertEqual(found["OMNI_LPV_ENABLED"].values, ("false", "true"))  # 体积光可开关。
        self.assertEqual(found["OMNI_LPV_SIZE"].values, ("6", "7", "8"))  # 体积边长保持三档。
        scene = support.expand(build.SHADERS / "world0/setup.csh")  # 从填表计算入口展开。
        self.assertIn("omniLpvBlockData", scene)  # 方块光表接入 setup 阶段。
        shadowcomp = support.expand(build.SHADERS / "world0/shadowcomp.csh")  # 从传播计算入口展开。
        self.assertIn("omniLpvMixNeighbours", shadowcomp)  # 邻居混合接入传播阶段。
        effect = support.text("effects/lighting/lpv.glsl")  # 效果主体。
        self.assertIn("omniLpvApply", effect)  # 片元混光独立成函数。
        self.assertIn("omniVoxelBlockId", effect)  # 体素编号映射独立成函数。

    def test_lpv_block_entity_and_item_lights(self):
        """体积光的实体光源同一开关也覆盖发光方块实体与掉落物，编号与属性文件一一对应。"""
        effect = support.text("effects/lighting/lpv.glsl")  # 效果主体。
        self.assertIn("omniLpvBlockEntityVoxelId", effect)  # 方块实体编号映射独立成函数。
        self.assertIn("omniLpvDroppedItemVoxelId", effect)  # 掉落物编号映射独立成函数。
        shadow = support.text("rendering/shadow.glsl")  # 阴影顶点写体素。
        self.assertIn("MC_RENDER_STAGE_BLOCK_ENTITIES", shadow)  # 用原版绘制阶段区分方块实体与地形。
        self.assertIn("omniLpvBlockEntityVoxelId(blockEntityId)", shadow)  # 方块实体按 `blockEntityId` 写体素。
        self.assertIn("omniLpvDroppedItemVoxelId(currentRenderedItemId)", shadow)  # 掉落物按 `currentRenderedItemId` 写体素。
        blocks = support.text("block.properties")  # 方块编号来源。
        for line in ("block.7310 = conduit", "block.7311 = enchanting_table", "block.7312 = brewing_stand"):  # 发光方块实体编号。
            self.assertIn(line, blocks)  # 每个发光方块实体登记一个编号。
        items = support.text("item.properties")  # 物品编号来源。
        for line in ("item.7400=lava_bucket", "item.7401=glowstone_dust"):  # 发光非方块物品编号。
            self.assertIn(line, items)  # 每个发光非方块物品登记一个编号。

    def test_custom_images_feature_is_declared(self):
        """用自定义图像就必须声明能力开关，缺能力时体积光回退屏幕空间间接光。"""
        settings = options.read_pipeline(build.SHADERS / "rendering/pipeline.properties")  # 流程设置唯一来源。
        self.assertIn("CUSTOM_IMAGES", settings["iris.features.optional"])  # 声明为可选能力。
        self.assertIn("COMPUTE_SHADERS", settings["iris.features.optional"])  # 计算能力同时声明。
        self.assertIn("image.omniLpv1", settings)  # 自定义图像仍由绘制设置提供。
        fields = settings["image.omniLpv1"].split()  # 字段顺序与取值必须符合加载器要求。
        self.assertEqual(len(fields), 9, fields)  # 采样器名加八个设置项。
        for path in ("rendering/lpv.glsl", "effects/lighting/lpv.glsl", "rendering/shadow.glsl"):
            self.assertIn("IRIS_FEATURE_CUSTOM_IMAGES", support.text(path))  # 每处图像读写都按能力开关回退。

    def test_lpv_image_writes_have_visibility_barriers(self):
        """传播只在单次派发里写一张图、读另一张图，靠共享缓冲与一次工作组同步，不需要图像屏障。"""
        source = support.text("rendering/lpv.glsl")  # 计算主体而不是复制实现。
        self.assertNotIn("memoryBarrierImage", source)  # 读写的不是同一张图，没有同派发内的先后依赖。
        self.assertEqual(source.count("barrier();"), 1)  # 共享缓冲填充完成后同步一次工作组。
        self.assertIn("defined OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES", source)  # 关闭或缺少能力时不读写图像。

    def test_selection_box_options(self):
        """选择框颜色可调，线条图像输出可开关，选择框已接入合成。"""
        found, _, _ = support.configuration()  # 真实选项。
        for name in ("OMNI_SELECTION_BOX_COLOR_R", "OMNI_SELECTION_BOX_COLOR_G", "OMNI_SELECTION_BOX_COLOR_B", "OMNI_LINE_IMAGE_OUTPUT"):
            self.assertIn(name, found)  # 每个选择框参数由选择源码定义。
        selection = support.text("effects/ground/selection.glsl")  # 选择主体。
        self.assertIn("SelectionBox", selection)  # 选择框独立成函数。
        self.assertIn("OMNI_SELECTION_BOX_COLOR_R", selection)  # 颜色参与着色。

    # --- 引入与流程设置的边界 ---
    def test_include_lines_are_bare_references(self):
        """任何一行出现 `#include` 都必须是干净的引用行：加载器在去注释之前扫描引用，注释里的示例会被当成自我包含。"""
        references = re.compile(r'\s*#include\s+"[^"]+"\s*$')  # 允许前导空白与行尾空白。
        for path in build.SHADERS.rglob("*"):
            if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh", ".gsh"):
                continue  # 只看自有着色源码。
            text = path.read_text(encoding="utf-8")  # 每个文件原文。
            text = re.sub(r"/\*.*?\*/", lambda match: "\n" * match.group(0).count("\n"), text, flags=re.S)  # 先挖掉块注释，块注释里的示例同样会被加载器扫到。
            for number, line in enumerate(text.splitlines(), 1):
                if "#include" in line and not references.fullmatch(line):  # 引用行带说明或代码会被加载器当成本文件包含。
                    self.fail(f"{path.name}:{number} 含 #include 的行不是干净引用：{line.strip()}")

    def test_pipeline_conditions_allow_only_exclusive_duplicates(self):
        """绘制设置里同一个键只能出现在互斥分支；同一分支或条件之外重复都要报错。"""
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "pipeline.properties"  # 独立流程设置文件。
            source.write_text("#ifdef A\nsun=true\n#else\nsun=false\n#endif\n", encoding="utf-8")
            self.assertEqual(options.read_pipeline(source)["sun"], "false")  # 互斥分支允许，读取结果只用于检查。
            for text in ("sun=true\nsun=false\n", "#ifdef A\nsun=true\nsun=false\n#endif\n", "sun=true\n#ifdef A\nsun=false\n#endif\n", "#ifdef A\nsun=true\n"):
                with self.subTest(text=text):  # 逐种非法写法检查。
                    source.write_text(text, encoding="utf-8")  # 每轮覆盖临时文件。
                    with self.assertRaises(ValueError):  # 可能同时生效的重复和缺少结尾都拒绝。
                        options.read_pipeline(source)
