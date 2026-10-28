"""源码审计：检查自有源码的中文说明和未实现标记。

调用位置：由 `python build.py audit` 在构建前调用，也可直接调用 `check(root)`。
调用示例：`check(Path('.'))`；生成的菜单说明用 `generated_comments(path, content)` 检查。

设计边界：只审计项目自己维护的源码和配置，不把环境目录、参考包、第三方代码和生成菜单
当作需要人工补注释的主体；但自有的薄入口仍然要说明，因为它们是实际加载流程的一部分。
`omni-gfx/src` 由 `check_slang` 按“每个顶层函数与结构体都有紧邻中文说明”检查，并额外要求
文件头与每条引用的上一行说明；生成 GLSL、profile 与探针不重复做行覆盖率。开发工具与
测试世界 Python 不进入光影 ZIP，只检查说明语言与接口，不按发布代码的 50% 行覆盖率要求。
审计必须识别真正的注释，而不是把字符串里的井号或示例文字误算成说明；机器字段、可复制命令和文件名也单独处理，避免它们伪装成自然语言或被错误拒绝。
"""
from __future__ import annotations

import ast  # 用语法树识别真正的 Python 文档字符串，避免普通字符串冒充说明。
import io  # 把源码交给标准词法扫描器，保持 Python 的注释边界规则。
import json  # 机器菜单说明必须按真实结构读取，不能靠文字前缀绕过审计。
import os  # 遍历时直接跳过环境、参考与第三方目录，不先枚举数万文件再过滤。
import re  # 识别中文、文件示例、机器字段和未实现标记。
import tokenize  # 让字符串中的井号不会被误判为注释。
from functools import lru_cache  # 大量重复英文词只判断一次，避免审计随注释量线性变慢。
from pathlib import Path  # 用项目相对路径固定审计范围并隐藏本机绝对路径。

CHINESE = re.compile(r"[\u3400-\u9fff]")  # 只有汉字能证明说明不是纯英文标识符。
DIRECTIVE = re.compile(r"#\s*(?:if|ifdef|ifndef|elif|else|endif|define|undef)\b")  # 属性文件里的条件指令是机器语句，加载器按选项宏挑选分支。
MACHINE = re.compile(r"\s*(?:#\s*(?:if|ifdef|ifndef|elif|else|endif|define|undef|include)\b|const\s+\w+\s+\w+\s*=)")  # 注释里成行的机器语句（预处理指令、常量声明）不是给接手者的自然语言说明；普通注释仍按中文检查。
EXCLUDED = {".git", ".dev", ".venv", "references", "libraries", "vendor", "dist", "__pycache__"}  # 环境、参考和第三方内容不是本项目的维护边界。
# 这些目录有自己的检查或不是手写说明对象：Slang 源由 check_slang 按接口说明审查，
# 生成产物与 profile 由生成器保证，探针是编译夹具，不重复要求行覆盖率。
EXCLUDED_PATHS = ("omni-gfx/src/", "omni-gfx/generated/", "omni-gfx/profiles/", "omni-gfx/tests/probes/", "omni-gfx/vendor/", "shaders/omni-gfx/")  # 生成 GLSL 的说明来源于 Slang，由库检查负责，不在光影审计里重复。
# 开发工具与测试世界不进入光影 ZIP，按 docs/omni-gfx-plan.md 的边界只检查说明语言与接口，
# 不按玩家可见代码的 50% 行覆盖率要求；测试世界的 GLSL 仍然按 50% 检查，因为它会被真实编译。
DEVELOPMENT = ("omni-gfx/tools/", "omni-gfx/examples/")
GENERATED = ("omni-gfx/generated/", "omni-gfx/profiles/", "shaders/omni-gfx/", "generated/glsl/")  # 自动生成的库文件只检查说明语言，不要求达到手写文件的比例；最后一项用于库内单独审计。
MACHINE_FILES = {"shaders/shaders.properties", "shaders/block.properties", "shaders/entity.properties", "shaders/item.properties"}  # 生成菜单和从 iterationT 原样移植的方块、实体、物品编号表是逐行可对照的机器数据，加中文说明会破坏对照；它们是数据不是业务代码。
SUFFIXES = {".py", ".glsl", ".slang", ".frag", ".vert", ".vsh", ".fsh", ".gsh", ".csh", ".tcs", ".tes", ".properties", ".yml", ".yaml"}  # 自有源码与配置接受说明，生成菜单在检查时单独排除；Slang 源由专门的范围检查。
TERMS = set("GLSL glsl Slang slang slangc omni gfx ogx PNG zlib CRC GLFW PyOpenGL SPIR-V SPIRV SPIR Vulkan GitHub Python Iris Sodium Minecraft minecraft MC README labPBR PBR SSR SSAO TAA FXAA GPU CPU DH OpenGL RenderDoc PresentMon JSON CSV ZIP SHA tar HTTPS API UV RGB RGBA F0 LICENSE COPYING main root final shadow deferred composite normals specular texture gtexture include define const version true false tone map sRGB blocklight skylight lab alpha dev beta rc lambda docstring properties Unlicense MIT sampler2D vec2 vec3 vec4 Java Windows Linux Unicode YAML ASCII Actions data source profile options groups texcoord git add commit tag push pid PR AO shadowtex terrain gbuffers fsh GLSL330 CLI build export GGX Smith LPV setup prepare SSBO AgX ACES Filmic Uncharted Narkowicz PCSS Omni iterationT Eclipse shadowcomp floodfill HSV TAU PI RGSS FSR FBM LOD BRDF ppss Disc exact approximate mc_glue missing shared".split())  # 只放技术词和接口名，不用少量英语词去猜整句自然语言。
# GLSL 的关键字、类型与内建函数是技术词，放进术语表，代码示例里的类型名和调用名不会被误报成英语说明。
TERMS |= set("uniform in out void float int bool ivec2 ivec3 ivec4 mat2 mat3 mat4 if else for while return discard flat attribute varying layout location struct sampler2DShadow min max abs clamp mix floor ceil fract pow exp log sqrt dot cross length normalize reflect refract texture textureLod texelFetch smoothstep step saturate far near".split())  # 只补技术词，不放行整句英文。
# 图形学算法名、格式名与开发工具名是技术词，不是英语说明；只补实际出现在自有注释里的名字。
TERMS |= set("glslang Worley Perlin Nubis mipmap mip blit VPS GTAO Burley Gerstner Schlick Radiance RGBE RLE ldexp sampler Pillow numpy Paeth IDAT Poly Haven HDR PCF Lambert WSR Photonics SSS Frisvad GetHandLight inout fragment ifdef swizzle xy XZ YZ AB".split())  # 算法名与工具名不翻译，但整句仍必须是中文。
EXTRA = {"VERSION", "CHANGELOG", "ROOT", "STAGES", "INCLUDE", "UTF", "BOM"}  # 自己源码里反复出现、又不必进术语表的大写标识符。
# Slang 库源里的算法人名、参数名与图形学名词只服务库源注释；单独放行，不扩大 GLSL 审计的术语范围。
SLANG_TERMS = frozenset(word.lower() for word in """
Abney Albedo Bayer Beer CUMULONIMBUS Catmull Chandrasekhar Cornette Draine EV Elek Frisvad GI GTAO
Gerstner GetHandLight GetVolumetricClouds GetVolumetricFog Greenstein HG Halton Hejl Hable Henyey Hillaire Jodie LUT
Lambert Lottes MATID Merlin NUBIS Nubis Perlin Photonics RSM RRT ODT Rec Reinhard Rom SSGI SSS SetCloudPos Shanks Uchimura
WSR Worley Xonk XYZ albedo antialias atlas background bits buffer cameraWorldPos centerDepthSmooth clip cloud color colortex
compression curve depth dir flashlight focus frame gi held hit hits indirect jitter job lightmap look media
mie modelViewInverse noise normal ogxGameplayEffects ogxSsrtHandlightShadow ozone pixel
prevCameraPos prevModelView previousCameraWorldPos previousModelView projection rayleigh rotation sharp sky
stars sun switch tile transmittance up velocity xy yzw
""".split())
EXTRA_LOWER = {word.lower() for word in EXTRA}  # 大小写不同的同一标识符按同一个小写形式比较。
TERMS_LOWER = {term.lower() for term in TERMS}  # 拆词时按小写比较，驼峰与全大写都能对上术语。


def _strip_code(text: str) -> str:
    """去掉路径、命令与函数调用示例，只留下可能夹带英语自然语言的文字。

    反引号里的代码和可复制命令是引用而不是说明；先移走它们，随后才逐词判断英文，
    这样真实英文句子不会借代码外形躲过检查。
    """
    text = re.sub(r"https?://\S+|www\.\S+|[\w./\\:-]+\.(?:py|slang|glsl|vsh|fsh|csh|json|md|zip|txt|exe|properties|lang|ya?ml)\b|\b(?:effects|presets|rendering|common)/", "", text)  # 链接与文件名是引用。
    text = re.sub(r"(?:python\s+-m\s+unittest\s+discover\s+-s\s+tests|python\s+(?:build|audit|generate|check|setup|doctor|watch)|--[\w-]+(?:\s+[\w./:-]+)?)", "", text)  # 可复制命令不是英语说明。
    return re.sub(r"\b[A-Za-z_]\w*\([^\n]*?\)", "", text)  # 函数调用示例是代码。


@lru_cache(maxsize=8192)  # 术语判断是纯函数，重复词直接复用结果。
def _unknown_word(word: str, extra: frozenset[str] = frozenset()) -> bool:
    """判断一个英文词是否是必须报出的未知自然语言。

    放行已知术语、全大写接口宏（如 `OMNI_TAA`）和拆开后英文词段不超过两个的标识符；
    含三个以上未知英文词段的写法（如 `some_english_snake_words`）说明它其实是一句英文，报出。
    `extra` 是调用方补充的术语集合；Slang 的移植注释里有算法人名和参数名，只在库源审计里放行。
    """
    if word.lower() in TERMS_LOWER or word.lower() in EXTRA_LOWER or word.lower() in extra or len(word) <= 1:
        return False  # 已知术语、单字母与常见大写标识符不算英语句子。
    if "_" not in word and not re.search(r"\d|[a-z][A-Z]", word):
        return True  # 纯大小写单词不是术语就是裸英语。
    if re.fullmatch(r"[A-Z][A-Z0-9_]*", word) and "_" in word:
        return False  # 全大写加下划线是接口宏，例如 `MC_HAND_DEPTH`。
    parts = [part for part in re.split(r"_|\d+", word) if part]  # 先按下划线、数字切开。
    parts = [piece for part in parts for piece in re.split(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", part) if piece]  # 再把驼峰拆成词段。
    prose = [part for part in parts if len(part) >= 3 and part.isalpha() and part.lower() not in TERMS_LOWER and part.lower() not in extra]  # 未知词段才算英语。
    return len(prose) >= 3  # 三个以上未知词段合起来就是一句英文。


def _backtick_prose(span: str, extra: frozenset[str] = frozenset()) -> str:
    """找出反引号里被当作标识符藏起来的英语自然语言，触发时返回该词，否则返回空串。

    不含空格的内容是单个标识符或路径，按代码跳过；含空格但出现赋值、调用或分号等代码
    符号的也按代码跳过。剩下只由英文单词和空格组成的内容里，连续三个未知小写英文词
    说明这里其实写了一句英文，要报出来，避免整句英语套上反引号就通过审计。
    """
    if not re.search(r"\s", span) or re.search(r"[=();{}\[\]<>#/\\+*;:\"'\d]", span):
        return ""  # 单个标识符或带代码符号的内容按代码跳过。
    run = 0  # 连续未知英文词的计数。
    for word in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", _strip_code(span)):  # 先去代码外形再逐词判断。
        prose = bool(re.fullmatch(r"[a-z]{2,}", word)) and word not in TERMS_LOWER and word not in extra  # 纯小写的未知词才像英语。
        if prose:
            run += 1  # 累加连续英文词。
        elif len(word) > 1:
            run = 0  # 遇到术语或标识符就清零，只统计真正连续的英文。
        if run >= 3:
            return word  # 连续三个未知英文词就是一句话。
    return ""  # 没有发现藏起来的英文句子。


def chinese_explanation(line: str, extra: frozenset[str] = frozenset()) -> bool:
    """判断一行是否是有效中文说明，并区分机器字段与代码示例。

    `True` 表示这一行可以计入中文说明比例；`False` 表示它是合法的机器字段、
    原生指令或没有足够中文的内容。发现裸英语自然语言时抛出 `ValueError`，
    因为只返回 `False` 会把“没有说明”和“说明语言错误”混在一起。
    """
    text = line.strip().strip('/#*').strip().strip('"\'')  # 先去掉注释边界，只审计说明本身。
    text = re.sub(r"(?:\.?[\w/.-]*python(?:\.exe)?)\s+[^\u3400-\u9fff；。]+", "", text)  # 命令参数是可复制代码，不应被当成英文句子。
    if re.match(r"@(?:option|effect|preset)\s+", text):
        data = json.loads(text.split(" ", 1)[1])  # 机器字段先按数据解析，不能把 JSON 当普通说明猜测。
        if not isinstance(data, dict) or not isinstance(data.get("label"), dict) or not isinstance(data["label"].get("zh_cn"), str): raise ValueError("机器说明需要中文名称对象")  # 机器前缀不能替缺少中文名称免责。
        if not CHINESE.search(data["label"]["zh_cn"]): raise ValueError("机器说明的中文名称必须包含中文")  # 只豁免机器键和值的格式，不豁免中文字段。
        for field in ("label", "description"):
            if isinstance(data.get(field), dict) and isinstance(data[field].get("zh_cn"), str): chinese_explanation(data[field]["zh_cn"])  # 中文字段仍拒绝夹带英语自然语言。
        if isinstance(data.get("values"), dict):  # 档位名称同样是玩家可见的说明，结构检查放行不代表语言合格。
            for name in data["values"].values():  # 每个档位取值都要说明文字。
                if not isinstance(name, dict) or not isinstance(name.get("zh_cn"), str): raise ValueError("机器说明的档位名称需要中文说明对象")  # 档位名称必须提供中文字段。
                chinese_explanation(name["zh_cn"])  # 档位名称同样拒绝夹带英语自然语言。
        return True  # 菜单其他字段交给选项扫描器，避免重复定义机器规则。
    if re.fullmatch(r"(?:#?define\s+)?[A-Z][A-Z0-9_]*(?:\s+[-\d.]+)?", text) or re.fullmatch(r"(?:RENDERTARGETS|DRAWBUFFERS):\s*[\d, ]+", text): return False  # 原生宏和附件指令是机器配置，不是业务说明。
    for span in re.findall(r"`([^`]*)`", text):  # 反引号里的内容按标识符或代码看待，但整句英文仍要报出。
        prose = _backtick_prose(span, extra)  # 找出藏在反引号里的英语自然语言。
        if prose: raise ValueError("自然语言说明必须中文：" + prose)  # 反引号不能把英文句子整体藏起来。
    text = re.sub(r"`[^`]*`", "", text)  # 检查过反引号后统一按代码引用移除。
    text = _strip_code(text)  # 去掉路径、命令与函数调用示例。
    words = re.findall(r"[A-Za-z_][A-Za-z_0-9]*", text)  # 即使混有中文，也逐个检查英文词，避免漏掉一句英文。
    unknown = [word for word in words if _unknown_word(word, extra)]  # 只放行已知术语与接口名，下划线和驼峰不再整体豁免。
    if unknown: raise ValueError("自然语言说明必须中文：" + ", ".join(unknown))  # 拒绝裸英语，保证接手者不必猜说明含义。
    return len(CHINESE.findall(text)) >= 4  # 至少四个中文字符才算完整说明，不接受单字凑比例。


def comments(source: Path, text: str | None = None) -> tuple[set[int], list[tuple[int, str]]]:
    """解析一个源码文件里的真实注释，并返回有效行号和原始片段。

    Python 使用语法树和词法扫描；其他格式使用对应的字符串边界规则。这样做是因为
    字符串里的井号、示例文本和菜单值不是维护者给接手者的说明，不能虚增中文覆盖率。
    `text` 可由检查循环传入已读内容，避免同一文件在比例统计与注释解析时读取两次。
    """
    text = source.read_text(encoding="utf-8") if text is None else text  # 审计实际源文件，不读取构建报告或缓存副本。
    fragments = []  # 保存原始片段和行号，后续才能指出维护者要改的具体位置。
    if source.suffix == ".py":  # Python 需要标准语法边界，避免把普通字符串算成注释。
        tree = ast.parse(text)  # 源码无法解析时直接失败，不能用审计绕过语法错误。
        for node in ast.walk(tree):  # 只寻找模块、类和函数开头的真实文档字符串。
            if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.body and isinstance(node.body[0], ast.Expr) and isinstance(node.body[0].value, ast.Constant) and isinstance(node.body[0].value.value, str):
                docstring = node.body[0].value  # 接口说明的位置来自语法树，而不是文字猜测。
                fragments.append((docstring.lineno, ast.get_source_segment(text, docstring)))  # 只收集接口文档，不把普通字符串当说明。
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.COMMENT: fragments.append((token.start[0], token.string))  # 词法扫描能排除字符串中的伪注释。
    elif source.suffix in {".properties", ".yml", ".yaml", ".lang"}:
        pattern = re.compile(r'"(?:\\.|[^"\\])*"|\x27(?:\x27\x27|[^\x27])*\x27|#[^\n]*', re.DOTALL)  # 字符串里的井号不计，配置尾注仍是有效说明。
        for match in pattern.finditer(text):
            if match[0].startswith("#") and not DIRECTIVE.match(match[0]): fragments.append((text[:match.start()].count("\n") + 1, match[0]))  # 记录注释起始行；条件指令是机器语句，不算说明。
    else:
        pattern = re.compile(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*', re.DOTALL)  # 同时识别字符串、块注释和行尾说明。
        for match in pattern.finditer(text):
            if match[0].startswith(("//", "/*")): fragments.append((text[:match.start()].count("\n") + 1, match[0]))  # 字符串先被跳过，避免代码文本冒充注释。
    valid_lines = set()  # 同一行出现多个片段时只计一次，比例表示行覆盖而不是片段数量。
    for start_line, fragment in fragments:
        # 菜单名称和帮助文本属于接口说明，机器字段必须验证中文值，不能放宽语言规则。
        for line_offset, line in enumerate(fragment.splitlines()):  # 块注释按真实非空行统计，避免一段长注释只算一行。
            if MACHINE.match(line): continue  # 注释里成行的机器语句不要求中文，也不算有效说明行。
            try:
                if chinese_explanation(line): valid_lines.add(start_line + line_offset)  # 只有合格中文说明进入比例分子。
            except ValueError:
                pass  # 统一检查阶段再报告原始位置，失败行不能先被算进合格比例。
    return valid_lines, fragments


def check_slang(root: Path) -> list[dict]:
    """检查 `omni-gfx/src` 下的 Slang 源：中文说明、未实现标记与库内引用边界。

    为什么不并进普通目录遍历：`omni-gfx` 里还有生成产物、参考下载和测试世界，那些有自己的检查；
    只审计手写 Slang 源，才能让“库源码也要中文说明、只引用库内文件”成为可执行的合同。
    说明密度同时检查两件事：每个顶层函数与结构体都有紧邻的中文解释，且不低于 50% 非空行；
    库源不再只记录比例。为什么保留接口说明：只靠行覆盖率仍可能漏掉对外函数的语义，两项一起才够用。
    移植代码保留上游密集的局部变量，凑比例只会逼出复述语法的填充；对外接口才是接手者真正要读的部分。
    文件头说明“这个文件管什么”，每条引用的上一行说明“为什么引入它”，这两项是本次新增的硬检查，
    因为只靠函数说明时，打开文件仍然看不出模块边界与依赖意图。
    注释语言、未实现标记、引用边界和版本声明仍按与 GLSL 相同的规则检查。
    """
    reports, errors = [], []  # 与 GLSL 审计共用报告结构，失败时一次列出全部位置。
    sources = sorted((root / "omni-gfx" / "src").rglob("*.slang"))  # 只审计手写库源。
    for source in sources:
        relative_path = source.relative_to(root).as_posix()  # 报告使用项目相对路径。
        text = source.read_text(encoding="utf-8")  # 每个文件只读一次。
        lines = text.splitlines()  # 文件头与引用说明都按真实行号报告。
        first = next((number for number, line in enumerate(lines) if line.strip()), None)  # 第一个非空行就是文件头起点。
        header = ""  # 文件头正文，用于检查职责、调用位置、示例与取舍四项。
        header_lines: set[int] = set()  # 文件头占用的行号；不能拿来给紧邻的函数充当说明。
        if first is not None and lines[first].lstrip().startswith("/*"):
            end = next((number for number in range(first, len(lines)) if "*/" in lines[number]), None)
            if end is not None:
                header = "\n".join(lines[first:end + 1])  # 块注释到闭合行为止，后面的函数体注释不算文件头。
                header_lines = set(range(first + 1, end + 2))
        elif first is not None and lines[first].lstrip().startswith("//"):
            end = first
            while end + 1 < len(lines) and lines[end + 1].lstrip().startswith("//"):
                end += 1
            header = "\n".join(lines[first:end + 1])  # 连续行注释同样只取文件开头这一段。
            header_lines = set(range(first + 1, end + 2))
        if not header:
            errors.append(f"{relative_path}：缺少文件头说明")  # 没有文件头时接手者不知道这个文件管什么。
        else:
            if not CHINESE.search(header):
                errors.append(f"{relative_path}：文件头必须是中文说明")  # 头部存在但语言不合格时单独报告。
            for markers, label in ((("调用位置",), "调用位置"), (("示例", "用法"), "可复制示例"), (("设计原因", "设计取舍", "设计边界", "为什么"), "设计原因与取舍")):
                if not any(marker in header for marker in markers):
                    errors.append(f"{relative_path}：文件头缺少{label}")  # 只写一句“这个文件做什么”不足以判断改动边界。
        for number, line in enumerate(lines):
            if re.match(r'^\s*#include\s+"', line):
                previous = lines[number - 1].strip() if number else ""
                if not CHINESE.search(previous):
                    errors.append(f"{relative_path}:{number + 1}：引用上一行缺少中文说明")  # Iris 要求说明放在引用上一行。
        nonempty_lines = {number for number, line in enumerate(lines, 1) if line.strip()}  # 空行不稀释比例。
        _, fragments = comments(source, text)  # 复用同一套注释识别与语言规则；有效行稍后按 Slang 术语表重算。
        documented = set()  # 用 Slang 术语表再判一次，带算法人名的中文说明才算有效。
        for start_line, fragment in fragments:
            for offset, line in enumerate(fragment.splitlines()):
                if MACHINE.match(line):
                    continue  # 机器语句不是自然语言。
                try:
                    if chinese_explanation(line, SLANG_TERMS):
                        documented.add(start_line + offset)  # 只记录真正合格的中文说明行。
                except ValueError:
                    pass  # 语言错误在下面的循环里统一报告。
        ratio = len(documented & nonempty_lines) / max(len(nonempty_lines), 1)  # 报告仍给出说明密度供参考。
        if ratio < 0.5:  # 库源也执行与光影相同的最低说明密度，避免只有接口说明、正文无人解释。
            errors.append(f"{relative_path}：中文有效注释 {ratio:.1%}，至少需要 50%")
        reports.append({"file": relative_path, "nonempty": len(nonempty_lines),
                        "chineseCommentLines": len(documented & nonempty_lines), "ratio": ratio})
        # 库源的维护合同是“每个对外函数和结构体都能看懂”，同时保留 50% 行覆盖率；
        # 移植算法保留了上游的密集局部变量，注释必须解释步骤而不是复述语法。
        # 顶层函数与结构体：返回类型可能是内建类型，也可能是 `Ogx...` 结构体。
        # 旧写法只认小写基础类型，结构体返回的函数会绕过“必须有说明”的检查。
        for number, line in enumerate(text.splitlines(), 1):
            if not re.match(r"^(?:\[[^\]]*\]\s*)?(?:static\s+)?(?:const\s+)?[A-Za-z_]\w*(?:<[^>]+>)?\s+[A-Za-z_]\w*\s*[({]", line):
                continue  # 只检查顶层函数与结构体，不要求每个局部变量都有说明。
            if any(candidate in documented - header_lines for candidate in range(max(1, number - 3), number + 1)):
                continue  # 前三条以内或本行有合格中文说明即算已解释，文件头本身不算。
            errors.append(f"{relative_path}:{number}：顶层定义缺少紧邻的中文说明")  # 对外接口必须有说明。
        for line_number, fragment in fragments:
            if re.search(r"\b(?:TODO|FIXME)\b|待实现|尚未实现|未接入的占位", fragment):
                errors.append(f"{relative_path}:{line_number}：存在未实现标记")  # 不把缺口留在库里。
            for line_offset, text_line in enumerate(fragment.splitlines()):
                if MACHINE.match(text_line):
                    continue  # 注释里的机器语句不是自然语言。
                try:
                    chinese_explanation(text_line, SLANG_TERMS)
                except ValueError as error:
                    errors.append(f"{relative_path}:{line_number + line_offset}：{error}")  # 拒绝英语说明。
        masked = re.sub(r"/\*.*?\*/", lambda match: " " * len(match[0]), text, flags=re.DOTALL)  # 块注释里的示例不算引用。
        masked = re.sub(r"//[^\n]*", "", masked)  # 行尾说明同样不算引用。
        if re.search(r"(?m)^\s*#version\b", masked):
            errors.append(f"{relative_path}：库源不能声明 #version")  # 版本由光影入口决定。
        for reference in re.findall(r'#include\s+"([^"]+)"', masked):
            if reference.startswith("/") or not reference.endswith(".slang"):
                errors.append(f"{relative_path}：库源只能引用同目录 Slang 文件：{reference}")  # 不回头引用光影实现。
            else:
                target = (source.parent / reference).resolve()  # 解析真实路径后再判断，链接也不能跳出源码。
                if not target.is_relative_to((root / "omni-gfx" / "src").resolve()):
                    errors.append(f"{relative_path}：引用跳出库源码目录：{reference}")  # 子文件只能来自 `omni-gfx/src`。
                elif not target.is_file():
                    errors.append(f"{relative_path}：引用的 Slang 文件不存在：{reference}")  # 引用必须落到真实文件。
    if errors:
        raise ValueError("Slang 审计失败\n" + "\n".join(errors))  # 与 GLSL 审计分开报告，便于定位库源。
    return reports


def check(root: Path) -> list[dict]:
    """检查审计范围，拒绝说明不足和未实现标记，并返回每个文件的比例。

    `root` 是唯一的边界入口；目录排除在这里集中处理，内部解析函数因此只负责识别
    注释。生成文件不参加普通比例审计，是因为它们由源文件自动产生，应该检查生成内容
    的语言，而不是要求它们重复携带源代码注释。
    """
    reports, errors = [], []  # 汇总所有文件的结果，让维护者一次看到全部需要修正的位置。
    # 为什么先剪枝：项目根目录下的 `.git`、`.venv`、`references` 与 `dist` 有数万个文件；
    # 先递归扫描全部文件再逐个取相对路径，会在十秒预算里白扫这些不参与审计的目录。
    for current, directories, names in os.walk(root):
        directories[:] = sorted(name for name in directories if name not in EXCLUDED)  # 排除目录不再向下遍历。
        for name in sorted(names):
            file_path = Path(current) / name
            relative_path = file_path.relative_to(root).as_posix()  # 报告使用项目相对路径，避免泄露本机目录。
            if relative_path.startswith(EXCLUDED_PATHS): continue  # Slang 源、生成产物和探针由各自的检查负责。
            if file_path.suffix not in SUFFIXES or relative_path in MACHINE_FILES: continue  # 第三方、机器数据和生成菜单有自己的来源，不在这里重复审计。
            text = file_path.read_text(encoding="utf-8")  # 每个文件只读一次，比例统计和注释解析共用。
            nonempty_lines = {number for number, line in enumerate(text.splitlines(), 1) if line.strip()}  # 空行没有业务内容，不应稀释说明比例。
            commented_lines, fragments = comments(file_path, text)
            ratio = len(commented_lines & nonempty_lines) / max(len(nonempty_lines), 1)  # 行尾说明既是代码行也是说明行，分子分母都保留。
            reports.append({"file": relative_path, "nonempty": len(nonempty_lines), "chineseCommentLines": len(commented_lines & nonempty_lines), "ratio": ratio})
            # 开发脚本只要求接口说明与语言合格；发布到光影 ZIP 的代码仍要求一半非空行有中文说明。
            development_script = file_path.suffix == ".py" and relative_path.startswith(DEVELOPMENT)
            if ratio < 0.5 and not relative_path.startswith(GENERATED) and not development_script: errors.append(f"{relative_path}：中文有效注释 {ratio:.1%}，至少需要 50%")  # 一半是项目约定的最低接手说明密度。
            for line_number, fragment in fragments:
                if fragment.lstrip().startswith(("// @option ", "// @effect ")):
                    try: chinese_explanation(fragment)
                    except (ValueError, TypeError) as error: errors.append(f"{relative_path}:{line_number}：机器说明无效：{error}")  # 机器字段错误必须指向原始文件和行。
                    continue  # 只有结构合法的机器字段可以使用机器字段规则，不放宽普通英语说明。
                if re.search(r"\b(?:TODO|FIXME)\b|待实现|尚未实现|未接入的占位", fragment): errors.append(f"{relative_path}:{line_number}：存在未实现标记")  # 未实现标记说明交付边界仍有空缺。
                for line_offset, text_line in enumerate(fragment.splitlines()):
                    if MACHINE.match(text_line): continue  # 注释里成行的机器语句不按自然语言检查。
                    try:
                        chinese_explanation(text_line)
                    except ValueError as error:
                        errors.append(f"{relative_path}:{line_number + line_offset}：{error}")  # 中英混合和纯英文说明使用同一严格规则。
    slang_reports = check_slang(root)  # 手写 Slang 源单独审计，目录遍历不进入生成产物与测试世界。
    reports.extend(slang_reports)  # 报告数量包含库源，终端能看出覆盖范围。
    if errors: raise ValueError("源码审计失败\n" + "\n".join(errors))
    return reports


def generated_comments(path: Path, content: str) -> None:
    """检查生成文件中的说明语言，不把机器生成文件计入普通注释比例。

    生成文件的格式和行数由源文件决定，重复要求注释会让自动产物变成第二个维护来源；
    这里仍检查真正的注释，确保生成器没有把裸英语说明传播到玩家可见文件中。
    """
    for line_number, line in enumerate(content.splitlines(), 1):
        if not line.lstrip().startswith("#"): continue  # 菜单值和翻译值是数据，不是给接手者的说明。
        if DIRECTIVE.match(line.lstrip()): continue  # 预处理器指令是机器语句，不是自然语言说明，也不对玩家显示。
        decoded = re.sub(r"\\u([0-9a-fA-F]{4})", lambda match: chr(int(match[1], 16)), line)  # 只还原 Unicode 中文，避免转义形式绕过语言审计。
        if not chinese_explanation(decoded): raise ValueError(f"{path}:{line_number}：生成说明必须是有效中文")  # 生成文件不豁免英语说明，只豁免比例要求。
