"""构建：把维护中的光影源码变成可检查、可分享的玩家安装包。

调用位置：终端与自动检查工作流使用命令；开发工具、游戏启动器和测试直接调用下方函数。
可复制命令（在项目根目录执行）：
    python build.py generate
    python build.py check
    python build.py build
    python build.py notes

构建主线：生成入口和菜单 → 检查来源与产物一致 → 离线编译链接 → 打包并计算校验值。
链接是把同一程序的绘制阶段放在一起检查；它不能证明游戏画面或显卡性能正确。
版本只读 `VERSION`，选项与预设交给 `options.py`；本文件不另存一份配置定义。
路径以本文件为起点，换启动目录仍指向同一项目；临时编译文件自动清理，成功记录留在 `.dev/`。
只复用同编译器、同阶段与同源码的成功链接，减少重复进程；离线宏只模拟部分加载器输入。
普通构建不执行版本控制；只有 `release` 在交互确认后修改版本、测试、提交并推送标签。
发布失败保留已经发生的改动供审查，不自动回滚文件，也不覆盖已有标签。
"""
from __future__ import annotations  # 类型说明不提前求值，导入时只建立构建接口。
import argparse  # 解析明确的构建命令。
import hashlib  # 固定产物校验与编译去重。
import json  # 读取显式程序与依赖记录。
import os  # 按本机核心数决定并行编译线程数。
import re  # 检查版本与引用边界。
import signal  # 超时结束整个检查进程组，不能留下编译器后台继续占用资源。
import shutil  # 同步独立开发实例。
import subprocess  # 调用真实编译器与版本控制。
import sys  # 使用当前解释器执行测试。
import tempfile  # 离线编译不污染源码。
import time  # 总预算按真实经过时间计算，包含进程创建与系统初始化。
import zipfile  # 生成玩家使用的光影包。
from concurrent.futures import ThreadPoolExecutor  # 并行等待多个编译器进程。
from pathlib import Path  # 路径相对项目定位。
import options as menu  # 原生选项是配置唯一来源。
import audit  # 审计自有代码注释与未实现标记。

ROOT = Path(__file__).resolve().parent  # 换工作目录不改变数据位置。
SHADERS = ROOT / "shaders"  # 游戏资源根目录。
INCLUDE = re.compile(r'^[ \t]*#include[ \t]+"([^"\n]+)"[ \t]*$', re.MULTILINE)  # 加载器要求引用独占一行，尾随说明会被拒绝。
STAGES = {".vsh": ".vert", ".fsh": ".frag", ".gsh": ".geom", ".csh": ".comp", ".tcs": ".tesc", ".tes": ".tese"}  # 把游戏入口后缀映射到编译器认识的阶段名。
# 移植 iterationT 期间的临时开关：旧效果文件在各片改写前没有入口引用，为真时“选项未接入”只警告不报错。
# 它只影响这一处宽松判断，不再缩减编译范围：`verify` 的编译探针与 `compile` 的全矩阵都照各自范围完整编译。
# 移植收尾、确认每个选项都接入入口后，删除这个开关与它的分支，恢复严格报错。
PORTING = True
# 加载器会为每个程序预先注入一整套环境宏；离线编译必须照 Iris 的 StandardMacros 给出同样的定义，
# 否则像 `MC_HAND_DEPTH`、`MC_VERSION`、`MC_RENDER_QUALITY` 这些只在游戏里存在的名字会被当成未声明标识符。
# 取值照 Iris 源码：版本号取当前游戏、厂商与渲染器取通用值（另一套环境再测远景路径）。
STANDARD_MACROS = (
    "#define MC_VERSION 260300\n"
    "#define IRIS_VERSION 11107\n"
    "#define MC_GL_VERSION 460\n"
    "#define MC_GLSL_VERSION 460\n"
    "#define MC_MIPMAP_LEVEL 4\n"
    "#define MC_OS_WINDOWS\n"
    "#define MC_GL_VENDOR_OTHER\n"
    "#define MC_GL_RENDERER_OTHER\n"
    "#define IS_IRIS\n"
    "#define IRIS_HAS_TRANSLUCENCY_SORTING\n"
    "#define IRIS_TAG_SUPPORT 2\n"
    "#define MC_NORMAL_MAP\n"
    "#define MC_SPECULAR_MAP\n"
    "#define MC_RENDER_QUALITY 1.0\n"
    "#define MC_SHADOW_QUALITY 1.0\n"
    "#define MC_HAND_DEPTH 0.125\n"
)  # 标准化环境宏，所有程序共用。
_VERSION_PATTERN = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:dev|alpha|beta|rc)\.(?:0|[1-9]\d*))?"  # 读文件与发布新版本共用一种编号规则。

# --- 读取版本：文件、压缩包和发布标签共用同一个编号 ---
def version(root: Path = ROOT) -> str:
    """返回 `root` 下去掉首尾空白的版本；测试可传独立目录，不读第二个版本来源。

    文件内容属于外部输入，在这里检查格式，避免版本被当作路径或产生歧义标签。
    """
    value = (root / "VERSION").read_text(encoding="utf-8").strip()  # 文件名与标签使用同一版本。
    if not re.fullmatch(_VERSION_PATTERN, value):  # 版本将进入文件名，不能接受任意文字或路径。
        raise ValueError("VERSION 必须是 x.y.z 或 x.y.z-dev.N 等版本号")  # 拒绝路径与含糊编号。
    return value  # 返回检查后的原编号，不擅自补零或改发布阶段。

# --- 核对标签：阻止工作流把本版源码发到其他版本名下 ---
def validate_tag(tag: str, root: Path = ROOT) -> None:
    """核对外部 `tag` 是否等于 `root` 中版本前加 `v`；只检查，不创建标签。"""
    if tag != "v" + version(root):  # 标签只能从唯一版本推导，不能另选编号。
        raise ValueError(f"发布标签 {tag!r} 与 VERSION 不一致")  # 错版本不能发布。

# --- 提取说明：只交付当前版本的正文，不混入历史修改 ---
def release_notes(release: str, root: Path = ROOT) -> str:
    """从 `root` 的更新记录提取 `release` 章节，返回带固定中文标题的正文。

    缺失、重复或空章节直接报错；保留正文中的小标题，供终端和发行工作流共用。
    """
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")  # 说明只有一个来源。
    headings = list(re.finditer(r"^##[ \t]+(.+?)[ \t]*$", text, re.MULTILINE))  # 小标题保留。
    matches = [index for index, heading in enumerate(headings) if heading[1] == release]  # 精确匹配版本标题，不能取近似编号。
    if len(matches) != 1:  # 同一版本出现两次时不能猜哪一段才是真实说明。
        raise ValueError(f"CHANGELOG.md 必须包含且只包含一个 ## {release} 更新记录")  # 发布说明不能选错章节。
    index = matches[0]  # 章节唯一性已检查。
    end = headings[index + 1].start() if index + 1 < len(headings) else len(text)  # 不混入旧版本。
    body = text[headings[index].end():end].strip()  # 只包含本版本内容。
    if not body:  # 空标题不能成为一次发布的变更说明。
        raise ValueError(f"CHANGELOG.md 中 {release} 的更新记录不能为空")
    return f"## 本次修改\n\n{body}\n"  # 固定外部输出格式，供发行工作流直接使用。

# --- 寻找检查器：使用项目安装的工具，不碰巧调用系统其他版本 ---
def tool(name: str) -> Path:
    """按内部约定的 `name` 返回项目检查器路径；只接受下方登记的两种工具。

    找不到时报告安装命令，不退回系统搜索路径，避免不同机器悄悄使用不同检查器。
    """
    names = {"glslang": ("glslangValidator", "glslang"), "actionlint": ("actionlint",)}  # 同一检查器兼容其正式可执行文件名。
    for base in names[name]:  # 只查项目工具目录。
        matches = sorted((ROOT / ".dev/tools" / name).rglob(base + (".exe" if sys.platform == "win32" else "")))  # 不依赖系统路径。
        if matches:  # 工具包的解压层级可能不同，排序后固定选择结果。
            return matches[0]  # 只返回已存在的项目内程序。
    raise ValueError(f"缺少项目内 {name}，请执行 python dev.py setup")

# --- 检查引用路径：源码不能借引用读出光影目录 ---
def source_path(reference: str, parent: Path, shaders: Path) -> Path:
    """把 `parent` 文件里的外部 `reference` 转成 `shaders` 内的真实文件路径。

    前导斜杠表示光影根目录，其余相对引用者定位；解析链接后检查越界和缺失一次。
    """
    if "\\" in reference or "\x00" in reference:  # 源码路径须遵守加载器语法，不能带本机分隔符或空字符。
        raise ValueError(f"{parent}：引用必须使用正斜杠")
    source = ((shaders / reference[1:]) if reference.startswith("/") else parent.parent / reference).resolve()  # 支持加载器根引用。
    if not source.is_relative_to(shaders.resolve()) or not source.is_file():  # 解析真实路径后再检查，目录链接也不能逃逸。
        raise ValueError(f"{parent}：引用越界或文件不存在：{reference}")
    return source  # 后续展开信任这个已经检查过的引用目标。

# --- 源文件编号：同一目录顺序只在一处生成 ---
def numbered_sources(shaders: Path | None = None) -> dict[Path, int]:
    """返回 `shaders` 下每个文件分辨路径到稳定编号的映射，编译器报错与展开共用它。

    编号由排好序的目录顺序决定，同一份源码在展开和错误回译时得到同一个号，
    不会因为两处各写一次顺序而对不上；内部数据互相信任，不做存在性兜底。
    `shaders` 省略时在调用时取当前项目光影目录，测试替换目录后仍指向替换值。
    """
    shaders = SHADERS if shaders is None else shaders  # 在调用时读取，不能在函数定义时固定。
    return {path.resolve(): index + 1 for index, path in enumerate(sorted(shaders.rglob("*"))) if path.is_file()}  # 一次排序生成全部编号。

# --- 展开引用：编译一份完整源码，同时保留每段原文的位置 ---
def expand(source: Path, shaders: Path = SHADERS, stack: tuple[Path, ...] = (), sourceNumbers: dict | None = None, cache: dict | None = None) -> str:
    """展开 `source` 中的真实引用，返回含 `#line` 原文件编号和行号的编译文本。

    `shaders` 限定引用根目录；`stack` 只记录当前递归路径，用来报告循环引用。
    `sourceNumbers` 是路径到数字编号的共享表；`cache` 保存本轮已展开文本，二者可省略。
    共用缓存时必须共用编号表，并且期间不修改源码；缓存不跨构建保存，不用于证明编译成功。
    """
    source = source.resolve()  # 规范化后识别循环。
    if source in stack:  # 先检查当前路径，不能让缓存掩盖循环引用。
        raise ValueError("循环引用：" + " → ".join(path.name for path in (*stack, source)))  # 展开前拒绝无限递归。
    if cache is None:  # 独立调用也能复用同一引用树中的重复文件。
        cache = {}  # 一次展开共享已读取内容，不反复访问磁盘。
    if source in cache:
        return cache[source]  # 循环已在缓存查询之前检查。
    if sourceNumbers is None:  # 调用方没有共享表时，为本次引用树建立固定编号。
        sourceNumbers = numbered_sources(shaders)  # 编号来源只有一处，展开与报错回译共用同一顺序。
    text = source.read_text(encoding="utf-8")  # 实际维护源码。
    masked = re.sub(r"/\*.*?\*/", lambda match: "".join("\n" if character == "\n" else " " for character in match[0]), text, flags=re.DOTALL)  # 屏蔽块注释但保留长度和换行，文档里的引用示例不参与展开。
    for line in masked.splitlines():  # 检查真实引用语法。
        if re.match(r"\s*#include\b", line) and not INCLUDE.fullmatch(line):
            raise ValueError(f"{source}：#include 行只保留引用，说明放到上一行以兼容 Iris")
    # 一次正序拼出结果，而不是每替换一个引用就整段复制已展开文本。
    # 旧写法是平方级开销：引用越多，每次切片复制的文本越长，大程序（合成本体展开约 2300 万字符）要一秒以上。
    # 正序拼接让每段原文和每个子文件只追加一次，输出与旧写法逐字节相同（`#line` 行列用同一个算法推导）。
    parts: list[str] = []  # 待拼接的片段，最后一次 `join`。
    cursor = 0  # 已经写入片段对应的原文位置。
    current = 1  # `cursor` 所在的原文行号，从 1 起算。
    for match in INCLUDE.finditer(masked):  # 正序扫描真实引用。
        segment = text[cursor:match.start()]  # 引用行之前的一段原文。
        current += segment.count("\n")  # 推进到引用所在行。
        parts.append(segment)  # 原文片段原样保留。
        included = source_path(match[1], source, shaders)  # 检查外部文件引用一次。
        content = expand(included, shaders, (*stack, source), sourceNumbers, cache)  # 子文件沿用同一编号表和读取缓存。
        # 只扫被引用文件原文，不扫已经拼接好的大文本：嵌套文件自己的 `#version` 会在上一层递归里先报出，
        # 所以展开结果里可能残留的 `#version` 只会来自这个文件本身。合成本体展开约 2300 万字符，逐次重扫要 0.4 秒。
        if re.search(r"^\s*#version", included.read_text(encoding="utf-8"), re.MULTILINE):  # 完整程序只能由入口声明语言版本。
            raise ValueError(f"{included}：被引用文件不能再次声明 #version")
        replacement = f"#line 1 {sourceNumbers[included]}\n{content.rstrip()}\n#line {current + 1} {sourceNumbers[source]}"  # 进入子文件前切编号，返回后恢复引用者的下一行。
        parts.append(replacement)  # 子文件展开接在原文片段之后。
        cursor = match.end()  # 跳到引用行末尾；行尾换行留给下一段计数。
    parts.append(text[cursor:])  # 追加最后一段原文。
    text = "".join(parts)  # 只在这里复制一次整体文本。
    cache[source] = text  # 缓存完整展开，仍保留所有条件包含与行映射。
    return text  # 原注释仍留在输出里，只有真正引用行被替换。

# --- 检查引用：只走一遍引用树，不拼接文本（入口校验用它，避免为每个入口展开整棵树） ---
def check_references(source: Path, shaders: Path = SHADERS, stack: tuple[Path, ...] = (), seen: set | None = None) -> None:
    """递归检查 `source` 的引用边界，不生成编译文本。

    与 `expand` 相同的检查（引用越界、循环引用、被引用文件重复声明 `#version`、`#include` 行必须干净），
    但只访问每个文件一次，不拼接文本。253 个入口逐个展开会把整棵引用树重复读取，检查时间远超十秒预算；
    入口校验只需要确认引用合法，所以用这条轻量路径。
    """
    source = source.resolve()  # 规范化后识别循环。
    if source in stack:  # 循环引用必须报出完整路径。
        raise ValueError("循环引用：" + " → ".join(path.name for path in (*stack, source)))
    if seen is None:  # 本次校验共享已访问集合。
        seen = set()
    if source in seen:  # 同一文件不从不同入口重复走。
        return
    seen.add(source)
    text = source.read_text(encoding="utf-8")  # 实际维护源码。
    masked = re.sub(r"/\*.*?\*/", lambda match: "".join("\n" if character == "\n" else " " for character in match[0]), text, flags=re.DOTALL)  # 屏蔽块注释但保留换行，文档里的示例不参与。
    for line in masked.splitlines():  # 真实引用语法。
        if re.match(r"\s*#include\b", line) and not INCLUDE.fullmatch(line):
            raise ValueError(f"{source}：#include 行只保留引用，说明放到上一行以兼容 Iris")
    for match in INCLUDE.finditer(masked):  # 逐个引用继续向下。
        included = source_path(match[1], source, shaders)  # 越界与缺失在这里报错。
        if re.search(r"^\s*#version", included.read_text(encoding="utf-8"), re.MULTILINE):  # 只有入口能声明语言版本。
            raise ValueError(f"{included}：被引用文件不能再次声明 #version")
        check_references(included, shaders, (*stack, source), seen)

# --- 检查入口：每种绘制阶段都必须具备加载器要求的伙伴 ---
def entrypoints(shaders: Path = SHADERS) -> list[Path]:
    """返回 `shaders` 内排序后的阶段文件，并检查首行、阶段配对和引用边界。

    计算阶段可独立存在；顶点、片元、几何与细分阶段按加载器规则配对，不在这里启动编译器。
    """
    entries = sorted(path for path in shaders.rglob("*") if path.suffix in STAGES)  # 同时检查主世界、下界和末地入口。
    if not entries:  # 空目录不应被当作一个通过检查的光影包。
        raise ValueError("光影包至少需要一组可执行入口")
    seen = set()  # 引用校验共享已访问集合，避免每个入口重复遍历。
    for source in entries:  # 阶段伙伴逐一检查。
        if not source.read_text(encoding="utf-8").startswith("#version "):
            raise ValueError(f"{source}：#version 必须放第一行")
        partners = {".vsh": (".fsh",), ".fsh": (".vsh",), ".gsh": (".vsh", ".fsh"), ".tcs": (".vsh", ".tes"), ".tes": (".vsh", ".tcs")}.get(source.suffix, ())  # 计算阶段不需要顶点与片元伙伴。
        for partner in partners:  # 细分阶段必须成对。
            if not source.with_suffix(partner).is_file():
                raise ValueError(f"{source}：缺少配对入口 {partner}")
        check_references(source, shaders, seen=seen)  # 入口配对检查只走引用树，不拼接文本。
    return entries  # 下游链接真实入口。

# --- 选项接线：全树检查一次，和编译探针范围无关 ---
def check_option_wiring(found: dict) -> None:
    """检查每个选项是否真的被某段代码使用，而不只是被声明。

    为什么不用“入口展开文本”：常规验证只编一小批程序，用它判断接线会把只在合成或延迟里
    使用的选项误报成未接线。这里直接扫全部光影源码：去掉每个选项自己的声明行与 `@option`
    说明行之后，只要名字还出现在别处，就说明它参与了计算。
    """
    files = list(SHADERS.rglob("*.glsl")) + list(SHADERS.rglob("*.vsh")) + list(SHADERS.rglob("*.fsh")) + list(SHADERS.rglob("*.gsh")) + list(SHADERS.rglob("*.csh"))
    bodies = []
    for path in files:
        kept = []
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"\s*(?://\s*)?#define\s+", line) or "@option" in line:
                continue  # 声明行与菜单说明不算使用。
            kept.append(line)
        bodies.append("\n".join(kept))
    pool = "\n".join(bodies)
    unused = [name for name in found if not re.search(r"\b" + re.escape(name) + r"\b", pool)]
    if unused:
        raise ValueError("选项没有接入任何计算：" + "、".join(unused[:5]))

# --- 完整离线编译：开发与移植期用，不受十秒预算限制 ---
def compile_all(seconds: float = 300.0) -> None:
    """编译全部维度的全部程序，用于移植期和发布前的人工门禁。

    为什么单独一条命令：`verify` 的十秒预算装不下整包编译；这里显式放宽时间，
    结果只用于本机与人工检查，不改变 `verify` 的预算规则。
    """
    found, profiles, _ = configuration()  # 选项与预设先检查。
    entries = entrypoints()  # 引用边界与阶段配对。
    global PORTING  # 完整编译要求选项都已接线：临时关掉移植期“未接线只警告”的宽松，让未接线选项直接失败。
    saved = PORTING
    PORTING = False
    try:
        compile_shaders(entries, found, profiles, {entry.stem for entry in entries})  # 全部程序都要编默认配置与全高配置，不能只编关键通路。
    finally:
        PORTING = saved

# --- 读取菜单来源：配置定义归选项模块所有，构建只使用结果 ---
def configuration() -> tuple[dict, list, dict]:
    """读取固定项目路径，返回选项字典、预设列表、生成文件的路径到文本映射。

    选项与预设边界由配置模块检查；这里不写文件，便于检查、打包和测试共用同一结果。
    """
    found, groups = menu.scan(SHADERS)  # 原生定义读取菜单。
    profiles = menu.presets(ROOT / "presets", found)  # 预设合法范围检查。
    return found, profiles, menu.generated(SHADERS, found, groups, profiles)  # 返回待比较或待写入的菜单，不隐式落盘。

# --- 生成薄入口文本：显式流程表决定哪些程序真正参与绘制 ---
def program_files() -> dict[Path, str]:
    """读取流程表并返回入口路径到文本的映射，不直接写磁盘。

    流程表属于文件输入，维度、主体和宏名在此检查；固定三维度避免加载器漏读根入口。
    每个维度登记 `define`（维度宏）、`buffers`（该维度引入的中间画面与常量声明文件）、
    `geometry`（额外生成几何阶段的程序）和 `absent`（该维度没有的程序）。
    顶点、几何、片元使用基础语言版本，计算阶段使用更高版本；生成文本是既有构建协议。
    为什么不把 `buffers` 放进根程序：加载器按每个程序展开后的片元源码逐行读取 `const` 指令，
    同一份声明必须在被编译的程序里出现才生效，所以每个维度生成的入口都引入自己那份声明文件。
    """
    data = json.loads((SHADERS / "rendering/programs.json").read_text(encoding="utf-8"))  # 不从效果目录推测流程。
    if set(data.get("dimensions", {})) != {"world0", "world-1", "world1"}:  # 每个受支持维度都要明确登记。
        raise ValueError("使用旧维度约定时必须同时提供 world0、world-1、world1；不能混入根目录程序")  # 任意worldN存在时加载器忽略根目录入口。
    result = {}  # 生成入口位置与内容。
    for dimension, setting in data["dimensions"].items():  # 维度显式接线：维度宏、几何阶段清单、缺席程序清单。
        flag = setting["define"]  # 每个维度都有自己的维度宏，主世界也不例外，主体靠它选维度分支。
        buffers = setting["buffers"]  # 该维度的中间画面与常量声明文件，逐维度取值不同，必须写进每个入口的片元源码才生效。
        if not re.fullmatch(r"[a-z][a-z0-9_]*", buffers) or not (SHADERS / "rendering" / (buffers + ".glsl")).is_file():  # 声明文件必须真实存在，拼错会让入口引用缺失文件。
            raise ValueError(f"{dimension} 的 buffers 声明文件无效：{buffers}")
        geometry = set(setting.get("geometry", []))  # 只有登记在这里的程序额外生成几何阶段。
        absent = set(setting.get("absent", []))  # 这个维度没有的程序，按参考光影的维度目录删减。
        if not (geometry | absent) <= set(data["programs"]):  # 清单里的名字必须是真实程序，拼错会让程序悄悄多出或缺失。
            raise ValueError(f"{dimension} 的几何或缺席清单含未登记程序")
        for name, (rendering, *defines) in data["programs"].items():  # 程序显式选择主体。
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not re.fullmatch(r"[a-z]+", rendering) or not (SHADERS / "rendering" / (rendering + ".glsl")).is_file():  # 流程表不能引用非法名字或不存在的绘制主体。
                raise ValueError(f"程序名或绘制主体无效：{name}")
            if name in absent:  # 维度没有的程序不生成入口，加载器就不会执行它。
                continue
            stages = [(".vsh", "OMNI_VERTEX"), (".fsh", "OMNI_FRAGMENT")] + ([(".gsh", "OMNI_GEOMETRY")] if name in geometry else [])  # 顶点片元必配对，几何阶段按清单追加。
            for suffix, stage in stages:  # 每个阶段一个薄入口。
                flags = [stage, *defines, flag]  # 维度规则显式写入入口。
                if any(not re.fullmatch(r"OMNI_[A-Z0-9_]+", flag_name) for flag_name in flags):  # 生成入口只允许项目自有宏名；程序宏带编号，如 `OMNI_COMPOSITE10_PASS`。
                    raise ValueError("程序宏必须使用受控名称")
                lines = ["#version 330 compatibility", f"// 生成的{name}入口：修改绘制主体与显式流程表。"]  # 首行必须先声明语言版本，再说明生成来源。
                for define in flags:  # 入口只选择类别。
                    lines += ["// 选择本程序的绘制阶段或物体类别。", "#define " + define + " 1"]  # 带值的宏不会被加载器当成布尔开关，避免出现含义不明的同名开关。
                lines += ["// 先引入本维度的中间画面与常量声明。", f'#include "/rendering/{buffers}.glsl"', "// 显式引入完整绘制主体。", f'#include "/rendering/{rendering}.glsl"', "// 输出由主体按统一缓冲协议写入。"]
                result[SHADERS / dimension / (name + suffix)] = "\n".join(lines) + "\n"  # 统一换行使本地与自动检查得到相同文本。
        for name, (rendering, *defines) in data.get("compute", {}).items():  # 计算程序单独登记，不生成顶点片元。
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not re.fullmatch(r"[a-z]+", rendering) or not (SHADERS / "rendering" / (rendering + ".glsl")).is_file():  # 计算阶段同样只能选已有主体。
                raise ValueError(f"计算程序名或主体无效：{name}")
            flags = ["OMNI_COMPUTE", *defines, flag]  # 计算阶段使用受控宏选择主体。
            if any(not re.fullmatch(r"OMNI_[A-Z0-9_]+", flag_name) for flag_name in flags):  # 计算入口宏也使用同一受控名称规则。
                raise ValueError("计算程序宏必须使用受控名称")
            lines = ["#version 430", f"// 生成的{name}入口：修改绘制主体与显式流程表。"]  # 计算阶段需要更高版本。
            for define in flags:  # 入口只选择类别。
                lines += ["// 选择本程序的绘制阶段或物体类别。", "#define " + define + " 1"]  # 计算入口的宏也带值，理由同上。
            lines += ["// 先引入本维度的中间画面与常量声明。", f'#include "/rendering/{buffers}.glsl"', "// 显式引入完整绘制主体。", f'#include "/rendering/{rendering}.glsl"', "// 输出由主体按统一缓冲协议写入。"]
            result[SHADERS / dimension / (name + ".csh")] = "\n".join(lines) + "\n"  # 独立计算阶段不虚构顶点片元配对。
    return result  # 核对入口生成结果。

def generate() -> None:
    """生成菜单、翻译和薄入口，并删除确认未被用户改动的旧生成入口。

    调用者负责选择何时生成；本函数只改构建协议登记的生成文件，内容相同就不重写。
    旧入口若含额外内容会停止并保留文件，避免自动清理覆盖人工修改。
    """
    _, _, files = configuration()  # 自动菜单与翻译。
    files.update(program_files())  # 入口和菜单都由维护的主体生成。
    for folder in (SHADERS, SHADERS / "world0", SHADERS / "world-1", SHADERS / "world1"):  # 清理范围限定在已知入口位置。
        for path in folder.glob("*"):
            if path.suffix in (".vsh", ".fsh", ".gsh", ".csh") and path not in files:  # 只检查由流程表生成的阶段，几何阶段也由流程表生成。
                text = path.read_text(encoding="utf-8")  # 只删除旧流程生成且没有手动修改的薄入口。
                generated_comments = {f"// 生成的{path.stem}入口：修改绘制主体与显式流程表。","// 选择本程序的绘制阶段或物体类别。","// 先引入本维度的中间画面与常量声明。","// 显式引入完整绘制主体。","// 输出由主体按统一缓冲协议写入。"}  # 只有生成器自己的说明才可随旧入口删除。
                untouched = all(line in generated_comments or line in ("#version 330 compatibility","#version 430") or re.fullmatch(r'#define OMNI_[A-Z0-9_]+(?: 1)?|#include "/rendering/[a-z_]+\.glsl"',line) for line in text.splitlines() if line.strip())  # 逐行匹配旧生成格式（含带值与带编号的宏、逐维度声明文件），额外内容视为人工修改。
                lines = text.splitlines()
                if len(lines) < 2 or not lines[0].startswith("#version ") or not lines[1].startswith("// 生成的") or not untouched:  # 格式不完整或含人工说明时拒绝删除。
                    raise ValueError(f"旧入口含自有修改，不能自动删除：{path}")  # 保留用户文件并报告具体冲突。
                path.unlink()  # 移除被新流程明确替代的重复维度入口。
    for output_path, generated_text in files.items():  # 仅写生成文件。
        output_path.parent.mkdir(parents=True, exist_ok=True)  # 初次生成维度目录。
        if not output_path.exists() or output_path.read_text(encoding="utf-8") != generated_text:  # 只有目标内容变化才写盘，观察模式不会反复触发重载。
            output_path.write_text(generated_text, encoding="utf-8", newline="\n")

# --- 替换测试配置：保留算法原文，只改变原生选项声明 ---
def option_source(text: str, found: dict, values: dict[str, str]) -> str:
    """按已验证的 `values` 替换源码 `text` 中已登记选项，返回编译用文本。

    `found` 来自同一选项扫描结果；其余行原样保留，因此离线测试编译真实效果分支。
    """
    result = []  # 保留业务源行。
    for line in text.splitlines():
        if "define" not in line and "const" not in line:  # 绝大多数业务行两个词都不含，先廉价跳过，避免对每行都跑正则。
            result.append(line)  # 明显不是选项声明的行原样保留。
            continue
        definition = menu.DEFINE.fullmatch(line)  # 只替换原生宏声明。
        if definition and definition[2] in found:  # 只动扫描器登记的原生宏，不改普通宏。
            name, value = definition[2], values[definition[2]]  # 仅替换声明，不改业务分支。
            line = (("#define " if value == "true" else "//#define ") + name) if found[name].values == ("false", "true") else f"#define {name} {value}"
        constant = menu.CONST.fullmatch(line)  # Iris原生const选项使用同一份值替换。
        if constant and constant[2] in found:  # 加载器原生常量与宏使用同一份配置值。
            line = f"const {constant[1]} {constant[2]} = {values[constant[2]]}; // [{ ' '.join(found[constant[2]].values) }]"
        result.append(line)  # 其他代码保留。
    return "\n".join(result) + "\n"  # 固定末尾换行，避免配置差异影响编译摘要。

# --- 选择代表配置：只检查默认与高效果，不遍历每个选项 ---
def variants(found: dict, profiles: list) -> list[tuple[str, dict]]:
    """从 `found` 和 `profiles` 返回带名字的代表配置列表，并按内容去重。

    只覆盖默认值与全高组合；预设合法性由配置扫描负责，不重复编译全部取值。
    """
    defaults = {name: option.default for name, option in found.items()}  # 源码默认配置。
    candidates = [("default", defaults), ("all_high", {n: o.values[-1] for n, o in found.items()})]  # 只保留能快速发现接线错误的两组，不声称覆盖全部算法模式。
    result, seen = [], set()  # 相同组合去重。
    for label, option_values in candidates:  # 每个候选都保留便于错误报告的名字。
        signature = tuple(sorted(option_values.items()))  # 按名称排序后，字典插入顺序不影响重复判断。
        if signature not in seen:
            seen.add(signature)  # 先登记内容，后续相同配置便可跳过。
            result.append((label, option_values))  # 相同配置不重复测试。
    return result  # 不指数穷举。

# --- 编译与链接：多阶段成组检查，缓存只信任成功的相同源码 ---
def compile_shaders(entries: list[Path], found: dict, profiles: list, full_programs: set[str]) -> None:
    """对 `entries` 的程序编译并链接代表选项配置，失败时映回光影相对路径。

    `found` 与 `profiles` 来自配置扫描。`full_programs` 列出要在全部代表配置下编译的程序名，
    其余程序只编译默认配置。离线环境只模拟基础与远景宏，不替代游戏验证。
    缓存位于开发报告目录，并同时核对编译器文件摘要和展开后源码摘要。
    """
    validator = tool("glslang")  # 真正执行编译器。
    source_numbers = numbered_sources()  # 所有入口共用编号，编译器报错可指回原文件。
    expanded_cache = {}  # 本次检查共享读取结果，不把源码缓存带到下次运行。
    expanded = {source: expand(source, sourceNumbers=source_numbers, cache=expanded_cache) for source in entries}  # 展开后保留原始文件编号。
    print("入口展开完成，开始检查选项接入", flush=True)  # 长时间离线检查期间及时给出阶段状态。
    # 预先为每个展开文本各扫一次，得到“声明过的选项名”和“去掉声明后的标识符集合”，
    # 避免下面每个选项都对整段文本重复跑正则；文本很大时这是主要的检查开销来源。
    programs = {}  # 同名入口的多个绘制阶段必须作为一个链接程序。
    for source in entries:
        programs.setdefault(source.with_suffix(""), []).append(source)  # 细分与几何阶段一起链接。
    cache_path = ROOT / ".dev/reports/glsl-cache.json"  # 成功源码缓存只服务开发，不进入发行包。
    compiler_digest = hashlib.sha256(validator.read_bytes()).hexdigest()  # 编译器文件变化就让旧成功记录失效。
    cached_report = json.loads(cache_path.read_text(encoding="utf-8")) if cache_path.is_file() else {}  # 首次运行没有缓存，按空记录处理。
    known_good = set(cached_report.get("programs", [])) if cached_report.get("compiler") == compiler_digest else set()  # 只信任同一个编译器写下的成功摘要。
    environments = [("base", STANDARD_MACROS), ("iris_dh", STANDARD_MACROS + "#define DISTANT_HORIZONS\n#define DH_BLOCK_UNKNOWN 0\n#define DH_BLOCK_LEAVES 1\n#define DH_BLOCK_STONE 2\n#define DH_BLOCK_WOOD 3\n#define DH_BLOCK_METAL 4\n#define DH_BLOCK_DIRT 5\n#define DH_BLOCK_LAVA 6\n#define DH_BLOCK_DEEPSLATE 7\n#define DH_BLOCK_SNOW 8\n#define DH_BLOCK_SAND 9\n#define DH_BLOCK_TERRACOTTA 10\n#define DH_BLOCK_NETHER_STONE 11\n#define DH_BLOCK_WATER 12\n#define DH_BLOCK_GRASS 13\n#define DH_BLOCK_AIR 14\n#define DH_BLOCK_ILLUMINATED 15\n")]  # 基础路径与开启远景的路径；远景方块编号照 Iris 实际取值。
    # 第一步：把代表配置、两种环境和全部程序展开成任务；实际组合数随选项变化。
    # 为什么先收集再编译：这样重复内容能在编译前过滤，并把独立任务交给线程池并行，避免串行等待几千个编译器进程。
    jobs, seen, reused = [], set(), 0  # 分别保存待编译任务、去重摘要与跳过的成功组数。
    configurations = variants(found, profiles)  # 代表配置。
    for label, option_values in configurations:  # 代表组合逐项展开。
        for environment, defines in environments:  # 基础与远景均检查。
            if (label == "default" and environment != "base") or (label == "all_high" and environment != "iris_dh"):
                continue  # 默认检查基础回退，高效果检查可选能力，不重复两组环境乘积。
            for program, sources in programs.items():  # 各维度不遗漏。
                if label != "default" and program.name not in full_programs:
                    continue  # 非主要通路只在默认配置下编一次：足以挡住引入与宏撞名错误，又不让十秒预算被挤爆。
                texts = [option_source(expanded[source], found, option_values) for source in sources]  # 每个阶段使用同一份选项取值。
                texts = [text.replace("#version 330 compatibility", "#version 330 compatibility\n" + defines, 1) for text in texts]  # 环境宏只注入临时文本，不修改入口文件。
                if program.name.startswith("dh_") and environment == "iris_dh":
                    texts = [text.replace("#define DISTANT_HORIZONS", "#define DISTANT_HORIZONS\nin int dhMaterialId;", 1) if source.suffix == ".vsh" else text for source, text in zip(sources, texts)]  # 只在顶点阶段模拟加载器自动提供的远景材质编号。
                source_signature = tuple((source.suffix, text) for source, text in zip(sources, texts))  # 保留完整源码：删除注释会拼接词，删除行号指令也可能改变预定义行号的结果。
                source_digest = hashlib.sha256(repr(source_signature).encode()).hexdigest()  # 唯一内容编号用于去重、临时文件名和缓存。
                if source_digest in seen:  # 别名或不同维度完全相同就不启动第二个编译器。
                    continue  # 相同维度或别名程序只链接一次。
                seen.add(source_digest)  # 新内容实际需要编译或核对缓存。
                if source_digest in known_good:  # 缓存只跳过之前成功链接的相同内容。
                    reused += 1  # 记录本次跳过的成功链接组。
                    continue  # 完整展开源码与配置完全相同才复用先前链接。
                jobs.append({"digest": source_digest, "label": label, "environment": environment, "program": program, "sources": sources, "texts": texts})  # 保留错误报告需要的配置、程序与源码。
    number_to_path = {str(index): path.relative_to(SHADERS).as_posix() for path, index in numbered_sources().items()}  # 编译器数字编号反查为项目内相对路径。
    failures = []  # 收集全部失败，一次报告，避免只看到第一条。
    workers = max(1, len(jobs))  # 任务数量已主动缩减，所有独立链接一次并行启动，不再人为排成长队。
    with tempfile.TemporaryDirectory(prefix="omni-glsl-") as temporary:
        temporary_folder = Path(temporary)  # 所有阶段文件放在自动清理目录，绝不落入源码树。

        def compile_one(job: dict):
            """把一组阶段写入 `temporary_folder` 并调用编译器，返回任务和原始结果。

            `job` 由本函数内部的任务收集步骤创建；摘要前缀保证并行任务文件名不同。
            不在工作线程解释错误，主线程统一映射路径并汇总，避免不同线程交错输出。
            """
            stage_files = []  # 本程序所有临时阶段文件，必须一起交给链接器。
            for source_path, source_text in zip(job["sources"], job["texts"]):  # 按任务阶段顺序配对原文。
                stage_file = temporary_folder / (job["digest"][:16] + STAGES[source_path.suffix])  # 摘要前缀避免并行时互相覆盖。
                stage_file.write_text(source_text, encoding="utf-8")  # 每个任务只写入临时目录。
                stage_files.append(stage_file)  # 顶点、几何和片元等阶段必须同组链接。
            process_result = subprocess.run([str(validator), "-l", *map(str, stage_files)], capture_output=True, text=True, encoding="utf-8", errors="replace")  # 保留标准输出供主线程显示完整错误。
            return job, process_result  # 主线程负责判断成败和更新成功缓存。

        with ThreadPoolExecutor(max_workers=workers) as pool:  # 只并行独立程序组，不拆开同一程序的多个阶段。
            for completed, (job, process_result) in enumerate(pool.map(compile_one, jobs), 1):  # map 保持任务次序，结果逐项统一处理。
                if completed % 500 == 0:  # 大型检查定期显示进度，避免误以为程序卡住。
                    print(f"离线程序编译进度：{completed}/{len(jobs)}", flush=True)
                if process_result.returncode:  # 失败组不进入成功缓存。
                    message = re.sub(r"(ERROR|WARNING): (\d+):(\d+):", lambda match: f"{match[1]}: {number_to_path.get(match[2], match[2])}:{match[3]}:", process_result.stdout + process_result.stderr)  # 把临时编号还原成可打开的源码相对路径。
                    failures.append(f"GLSL 编译/链接失败：{job['program'].relative_to(SHADERS)} / {job['label']} / {job['environment']}\n{message}")  # 同时报告程序、配置和环境。
                else:
                    known_good.add(job["digest"])  # 只有本次确实链接成功才写入缓存候选。
        cache_path.parent.mkdir(parents=True, exist_ok=True)  # 仅在全部进程结束后建立开发报告目录。
        cache_path.write_text(json.dumps({"compiler": compiler_digest, "programs": sorted(known_good & seen)}) + "\n", encoding="utf-8")  # 只保存当前检查范围的成功记录，不积攒历史大矩阵。
    if failures:  # 资源目录退出后临时文件已清理，再统一报告最多五项失败。
        limit = 400 if PORTING else 5  # 移植期一次列全，便于统一修；正常开发只报前五条。
        raise ValueError("\n\n".join(failures[:limit]))
    unique_programs = len(seen)  # 唯一程序数由新编译与成功缓存复用共同组成。
    print(f"GLSL 编译与链接通过：{len(variants(found, profiles))} 种配置，{unique_programs} 组唯一程序，复用 {reused} 组相同源码")

def dependencies() -> dict[str, bytes]:
    """校验依赖清单，返回发布包相对路径到原始字节的白名单。

    清单、来源网址、文件列表、哈希和随包许可都是外部维护边界；不改写第三方文件字节。
    返回值只包含清单明确登记的文件，目录中多出或缺少文件都会失败。
    """
    path = ROOT / "dependencies.json"  # 运行库唯一清单。
    data = json.loads(path.read_text(encoding="utf-8"))  # 边界输入检查。
    if not isinstance(data, dict) or data.get("schemaVersion") != 1 or not isinstance(data.get("libraries"), list):  # 清单结构属于外部输入，在入口一次检查。
        raise ValueError("运行依赖记录格式无效")
    result = {"dependencies.json": path.read_bytes(), "THIRD_PARTY.md": (ROOT / "THIRD_PARTY.md").read_bytes()}
    allowed = set()  # 记录清单登记项，最后与磁盘真实文件集合逐项比较。
    for item in data["libraries"]:  # 每库独立许可来源。
        if not isinstance(item, dict) or set(item) != {"name", "version", "source", "license", "files"} or not all(isinstance(item[key], str) and item[key].strip() for key in ("name", "version", "source", "license")) or not item["source"].startswith("https://"):  # 来源必须带完整信息并使用加密网址。
            raise ValueError("依赖必须记录名称、版本、来源与明确许可")
        if not isinstance(item.get("files"), dict) or any(not isinstance(reference, str) or not isinstance(digest, str) for reference, digest in item["files"].items()):  # 每个文件都必须有文字路径和摘要值。
            raise ValueError(f"依赖 {item.get('name','未知')} 的 files 必须是字符串到哈希的对象")  # 错误配置在边界给出可读原因。
        for reference, digest in item["files"].items():  # 原声明也需登记。
            source = source_path("/" + reference, path, SHADERS)  # 复用光影引用边界，拒绝依赖路径越界。
            if not reference.startswith("libraries/") or reference in allowed or not re.fullmatch(r"[0-9a-f]{64}", digest) or hashlib.sha256(source.read_bytes()).hexdigest() != digest:  # 校验目录、重复登记与真实文件摘要。
                raise ValueError(f"依赖白名单或校验值无效：{reference}")
            allowed.add(reference)  # 同一文件不能被两个依赖重复登记。
            result["shaders/" + reference] = source.read_bytes()  # 第三方原文逐字节进入包，不重排也不改许可内容。
        if not any("license" in reference.lower() or "copying" in reference.lower() for reference in item["files"]):  # 每个依赖都要在包内附带上游许可原文。
            raise ValueError("每个运行库必须打包原始许可")
    actual = {path.relative_to(SHADERS).as_posix() for path in (SHADERS / "libraries").rglob("*") if path.is_file()}  # 目录实际内容也必须完全受清单管理。
    if actual != allowed:  # 清单与磁盘任何一边多一项都停止打包，避免遗漏许可或偷偷夹带文件。
        raise ValueError("第三方目录存在未登记或缺失的文件")
    return result  # 清单和许可声明随第三方原文一同交付。

# --- 全量检查：先核来源，再编译，最后检查工作流 ---
def check() -> None:
    """检查本版说明、生成文件、所有引用、选项、依赖、着色器链接和工作流。

    不生成或打包文件；失败在发现位置停止。编译缓存只减少已验证的完全相同任务。
    此离线检查不启动 Minecraft，不能作为游戏画面、性能或兼容性证据。
    """
    release_notes(version())  # 本版本必须有真实说明。
    entries = entrypoints()  # 先引用后编译。
    found, profiles, generated_files = configuration()  # 菜单从原生定义与预设读取。
    generated_files.update(program_files())  # 入口从显式绘制流程读取。
    for path, expected in generated_files.items():  # 逐一比对维护来源与仓库产物，不掩盖过期生成文件。
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise ValueError(f"{path.relative_to(ROOT)} 未生成或已过期，请运行 python build.py generate")
        if path.suffix in (".properties", ".lang"):  # 菜单中的机器转义说明也要按解码后的中文审计。
            audit.generated_comments(path, expected)
    generated_entries = {path for path in entries if path.suffix in (".vsh", ".fsh", ".gsh", ".csh")}  # 这些阶段由流程表生成；细分阶段仍可独立维护。
    if generated_entries != set(program_files()):  # 旧程序可能被加载器忽略，必须明确清理并审查。
        raise ValueError("存在流程表之外的旧入口，请重新生成并审查")
    audited = audit.check(ROOT)  # 自有源码先通过中文说明与未实现标记审计。
    dependencies()  # 发行包中的第三方文件与许可也必须满足白名单。
    print(f"中文注释与实现审计通过：{len(audited)} 个代码文件")  # 共享审计函数不直接写终端，构建入口统一报告。
    check_option_wiring(found)  # 选项必须真的参与计算，和编译探针范围无关。
    source_numbers = numbered_sources()  # 全部主体共享编号与展开缓存，避免反复扫描目录。
    expanded_cache = {}  # 一次检查只读取每份共用源码一次。
    for source in SHADERS.rglob("*.glsl"):  # 主体即使未接入入口，也检查引用边界。
        expand(source, sourceNumbers=source_numbers, cache=expanded_cache)  # 不为每个文件重新扫描整棵引用树。
    # 十秒预算内的编译探针：只编体积小的程序，覆盖几何、阴影、远景与最终显示；合成与延迟的完整覆盖由 `python build.py compile` 负责。
    # 为什么这样分：合成本体展开后有两千多万字符，单编一个就要八九秒，塞不进常规验证的预算；缩到小程序仍能挡住语法、引入与宏撞名错误。
    key_programs = {"gbuffers_terrain", "gbuffers_water", "shadow"}  # 这三类在全部代表配置与两组环境下再编一次。
    smoke = {"gbuffers_terrain", "gbuffers_water", "gbuffers_entities", "gbuffers_hand", "gbuffers_basic", "gbuffers_skybasic", "shadow", "dh_terrain", "dh_water", "final"}
    probes = [source for source in entries if source.parent.name == "world0" and source.stem in smoke]  # 主世界的轻量程序，默认配置与基础环境。
    compile_shaders(probes, found, profiles, key_programs)  # 关键程序另加全高配置与开远景环境。
    subprocess.run([str(tool("actionlint")), "-shellcheck=", "-pyflakes=", *map(str, sorted((ROOT / ".github/workflows").glob("*.yml")))], cwd=ROOT, check=True)  # 自动发布工作流也要在交付前通过真实检查器。
    print(f"检查通过：{len(entries)} 个入口，{len(found)} 个选项，{len(profiles)} 套预设")

# --- 创建压缩包：固定顺序、时间和平台标记，使字节可重复 ---
def archive(path: Path, files: dict[str, bytes]) -> None:
    """把相对成员名到字节的 `files` 写入 `path`，保持相同输入得到相同压缩包。

    调用方负责提供已检查的清单；这里固定排序、时间和压缩包权限标记，不读取额外文件。
    """
    path.parent.mkdir(parents=True, exist_ok=True)  # 创建产物目录。
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, content in sorted(files.items()):  # 固定文件顺序。
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))  # 固定时间，避免构建日期改变包校验值。
            info.create_system = 3  # 统一记录压缩包的平台标记，避免不同系统生成不同字节。
            info.compress_type = zipfile.ZIP_STORED if name.endswith((".png", ".bin")) else zipfile.ZIP_DEFLATED  # 贴图与二进制数据本身已压缩或压不动，直接存放：九级压缩几十兆数据要好几秒，超过检查预算还几乎没有收益。
            info.external_attr = 0o100644 << 16  # 文件成员使用普通只读文件权限，不携带本机属性。
            output.writestr(info, content)  # 不带本机路径与时间。

# --- 打包交付物：游戏包与可单独分享的预设分开生成 ---
def pack() -> list[Path]:
    """生成游戏光影 ZIP、预设 ZIP 和校验清单，返回三个产物路径。

    游戏包只按认可的资源扩展名与第三方白名单收集；开发工具、缓存和参考目录不发布。
    预设独立携带版本标记，校验清单记录两个压缩包的真实文件摘要。
    """
    release_version = version()  # 两个包和文件名共用唯一版本来源。
    _, profiles, _ = configuration()  # 玩家可分享配置仍由预设扫描器产生。
    shader_files = {"shaders/" + path.relative_to(SHADERS).as_posix(): path.read_bytes() for path in SHADERS.rglob("*") if path.is_file() and "libraries" not in path.relative_to(SHADERS).parts and path.suffix in {*STAGES, ".glsl", ".properties", ".lang", ".png", ".bin", ".mcmeta"}}  # 只收游戏能读取的自有资源种类；`.mcmeta` 记录贴图的过滤与重复方式。
    shader_files.pop("shaders/rendering/pipeline.properties", None)  # 源流程设置已合并到加载器菜单。
    shader_files.update(dependencies())  # 第三方文件必须先通过许可与哈希白名单检查。
    shader_files["VERSION"] = (release_version + "\n").encode()  # 包内版本供玩家确认实际使用版本。
    shader_output = ROOT / "dist" / f"Omni-{release_version}.zip"  # 产物放在项目发行目录，不碰游戏实例。
    archive(shader_output, shader_files)  # 玩家包不包含开发工具。
    preset_files = {f"{profile.name}.properties": (f"# @shaderVersion {release_version}\n" + "\n".join(f"{name}={value}" for name, value in profile.values.items()) + "\n").encode("ascii") for profile in profiles}  # 每套完整预设标记适用版本。
    preset_files["manifest.json"] = (json.dumps({"schemaVersion": menu.SHARE_SCHEMA, "shaderVersion": release_version, "presets": [profile.name for profile in profiles]}, indent=2) + "\n").encode()  # 分享格式版本只由配置主体定义。
    preset_files["README.md"] = (ROOT / "presets/README.md").read_bytes()  # 保留预设使用说明。
    preset_output = ROOT / "dist" / f"Omni-presets-{release_version}.zip"  # 配置包可独立分享。
    archive(preset_output, preset_files)
    sums_path = ROOT / "dist/SHA256SUMS.txt"  # 校验清单只记录这次两个正式压缩包。
    sums_path.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in (shader_output, preset_output)), encoding="ascii", newline="\n")  # 摘要从最终包字节计算。
    return [shader_output, preset_output, sums_path]  # 命令行只报告真实生成路径。

# --- 同步开发副本：目标固定在项目控制的测试实例内 ---
def sync() -> None:
    """把新生成的游戏包复制到项目管理的 `.dev/minecraft` 测试实例。

    不查找或修改玩家真实游戏目录；安装位置固定，避免把开发包发错位置。
    """
    destination = ROOT / ".dev/minecraft/shaderpacks/Omni-dev.zip"  # 不改玩家包。
    destination.parent.mkdir(parents=True, exist_ok=True)  # 首次使用开发实例时建立受控目录。
    shutil.copyfile(pack()[0], destination)  # 只复制刚生成的光影包，不复制预设包或校验清单。
    print("已同步 .dev/minecraft/shaderpacks/Omni-dev.zip")

# --- 发布：检查干净且同步的主分支，确认后才改版本并推送 ---
def release(target: str, notes: Path) -> None:
    """将 `target` 和 `notes` 发布为版本提交与标签；先核对边界，再要求交互确认。

    只接受干净、位于 main 且已与远端同步的工作区；本地和远端目标标签都必须不存在。
    确认之前不改文件。确认之后按版本、说明、生成、测试、检查、打包、提交、标签、推送顺序执行。
    中途错误会停止并留下现场供审查，不自动撤销文件或改写既有提交、标签。
    """
    def git_output(*args: str) -> str:
        """运行发布流程固定的 `git` 参数并返回输出；保留状态行前导空格供路径解析。"""
        command_result = subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8")  # 参数由下方固定流程传入，不拼接用户命令。
        if args[:1] == ("status",):  # 状态前两列有意义，不能像普通文字那样去掉左侧空白。
            return command_result.stdout.rstrip("\r\n")
        return command_result.stdout.strip()  # 其他命令只去掉输出首尾空白。

    notes_body = notes.read_text(encoding="utf-8").strip()  # 先检查说明文件，确保确认发布前不改版本文件。
    if not notes_body or re.search(r"^## ", notes_body, re.MULTILINE):  # 发行说明只收正文，标题由构建流程统一添加。
        raise ValueError("发布说明应为非空正文，不能含版本章节")

    if git_output("status", "--porcelain") or git_output("branch", "--show-current") != "main":  # 发布不能混入待审查代码或从其他分支产生。
        raise ValueError("发布要求干净的 main 工作区")

    current_version = version(ROOT)  # 所有比较从当前唯一版本文件读取。
    if not re.fullmatch(_VERSION_PATTERN, target) or target == current_version:  # 命令参数是外部输入，先检查格式与重复。
        raise ValueError("必须指定一个不同的合法新版本")

    def version_order(value: str) -> tuple:
        """把已检查的版本拆成可比较数字；正式版排在同编号预发布版之后。"""
        base, _, suffix = value.partition("-")  # 主版本三段始终按数字比较。
        stage, _, number = suffix.partition(".")  # 预发布阶段再按名称和序号排序。
        stage_order = {"dev": 0, "alpha": 1, "beta": 2, "rc": 3, "": 4}
        return (*map(int, base.split(".")), stage_order[stage], int(number or 0))

    if version_order(target) <= version_order(current_version):  # 版本只能向前，防止重复或倒退发布。
        raise ValueError("发布版本必须向前增长")

    remote_main = git_output("ls-remote", "--heads", "origin", "main").split()  # 远端主分支必须存在且指向当前提交。
    if not remote_main or remote_main[0] != git_output("rev-parse", "HEAD"):  # 不把尚未推送的源码藏进版本发布。
        raise ValueError("发布前 main 必须已经与远端同步")
    if git_output("tag", "--list", "v" + target):  # 已用过的本地标签不能被覆盖。
        raise ValueError("目标标签已存在，禁止改写")
    if git_output("ls-remote", "--tags", "origin", "refs/tags/v" + target):  # 服务器也要检查，不能依赖推送时才发现冲突。
        raise ValueError("远端目标标签已存在，禁止复用")

    print(git_output("log", "--oneline", "-10"))  # 用户确认前展示最近提交，核对发布起点。
    print(git_output("diff", "--stat"))  # 同时展示当前差异统计；干净检查后通常为空。
    confirmation = "发布 " + target  # 要求输入完整版本，避免误触发自动发布。
    if not sys.stdin.isatty() or input(f"将测试、提交并推送 main 与 v{target}，输入 {confirmation} 确认：") != confirmation:
        raise ValueError("未明确确认发布，未修改版本或标签")  # 自动任务无法静默发布。

    changelog_path = ROOT / "CHANGELOG.md"  # 版本说明集中在既有更新记录文件。
    old_changelog = changelog_path.read_text(encoding="utf-8")  # 读入旧内容，后续只在首个标题后插入新章节。
    (ROOT / "VERSION").write_text(target + "\n", encoding="utf-8")  # 确认后才更新唯一版本来源。
    first_line, _, remaining = old_changelog.partition("\n")  # 保留主标题与所有旧章节原文。
    changelog_path.write_text(first_line + f"\n\n## {target}\n\n{notes_body}\n" + remaining, encoding="utf-8")  # 新章节只写一次，不覆盖历史记录。
    generate()  # 新版本可能改变生成文件，先重新生成再检查工作区。

    version_changes = {"VERSION", "CHANGELOG.md"}  # 发布准备只允许这两个版本文件被改动。
    worktree_lines = git_output("status", "--porcelain").splitlines()
    unexpected = [line for line in worktree_lines if line[3:] not in version_changes]  # 状态行前缀长度固定，保留路径原文比较。
    if unexpected:  # 生成器或并行工作若改了其他文件，不能让 git add 掩盖变化。
        raise ValueError("生成或测试改变了非版本文件，停止发布：" + "；".join(unexpected))

    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests"], cwd=ROOT, check=True)  # 发布必须先通过项目回归测试。
    check()  # 全量检查与打包本身不执行版本控制。
    pack()
    unexpected = [line for line in git_output("status", "--porcelain").splitlines() if line[3:] not in version_changes]  # 测试或打包不得留下其他跟踪文件改动。
    if unexpected:  # 任何非版本变化都停止，确保提交范围可预测。
        raise ValueError("检查或打包后出现非版本文件变化，停止发布：" + "；".join(unexpected))

    subprocess.run(["git", "add", "VERSION", "CHANGELOG.md"], cwd=ROOT, check=True)  # 干净起点保证暂存内容只有版本与说明。
    subprocess.run(["git", "commit", "-m", f"chore(release): 准备 {target} 版本"], cwd=ROOT, check=True)  # 发布说明与版本组成单独提交。
    subprocess.run(["git", "tag", "-a", "v" + target, "-m", notes_body], cwd=ROOT, check=True)  # 创建不可覆盖的注释标签。
    subprocess.run(["git", "push", "--atomic", "origin", "main", "v" + target], cwd=ROOT, check=True)  # 分支和标签要么一起推送，要么都不推送。

# --- 检查时间预算：超时杀掉整组进程，失败不能伪装成通过 ---
def windows_job(process: subprocess.Popen):
    """把 `process` 纳入 Windows 作业对象，关闭对象时结束其整棵子进程树。"""
    import ctypes  # 直接调用系统接口，不再启动耗时不定的进程清理命令。
    from ctypes import wintypes  # 使用系统指针宽度，兼容不同位数的 Python。

    class BasicLimits(ctypes.Structure):
        """系统规定的作业限制布局，只启用关闭时杀进程这一项。"""
        _fields_ = [("perProcessUserTime", ctypes.c_longlong), ("perJobUserTime", ctypes.c_longlong),
                    ("limitFlags", wintypes.DWORD), ("minimumWorkingSetSize", ctypes.c_size_t),
                    ("maximumWorkingSetSize", ctypes.c_size_t), ("activeProcessLimit", wintypes.DWORD),
                    ("affinity", ctypes.c_size_t), ("priorityClass", wintypes.DWORD),
                    ("schedulingClass", wintypes.DWORD)]  # 字段顺序必须与 Windows 系统规定的基本限额一致。

    class IoCounters(ctypes.Structure):
        """系统规定的六个输入输出计数器，占位但不能缩短。"""
        _fields_ = [(name, ctypes.c_ulonglong) for name in ("readOperations", "writeOperations", "otherOperations", "readBytes", "writeBytes", "otherBytes")]  # 仅保存结构尺寸，全部保持零。

    class ExtendedLimits(ctypes.Structure):
        """扩展限制附带系统输入输出计数器和内存统计占位。"""
        _fields_ = [("basic", BasicLimits), ("io", IoCounters), ("processMemoryLimit", ctypes.c_size_t),
                    ("jobMemoryLimit", ctypes.c_size_t), ("peakProcessMemoryUsed", ctypes.c_size_t),
                    ("peakJobMemoryUsed", ctypes.c_size_t)]  # 扩展作业限制是四个内存限额，不是进程内存计数结构。

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)  # 错误由系统原始代码说明，不吞掉失败。
    kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    kernel.CreateJobObjectW.restype = wintypes.HANDLE  # 句柄不能按默认的三十二位整数截断。
    kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    kernel.SetInformationJobObject.restype = wintypes.BOOL
    kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    kernel.AssignProcessToJobObject.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]  # 关闭句柄时系统负责结束关联进程树。
    kernel.CloseHandle.restype = wintypes.BOOL
    job = kernel.CreateJobObjectW(None, None)  # 本次检查独享匿名作业，不影响其他程序。
    if not job:
        raise ctypes.WinError(ctypes.get_last_error())  # 没有可靠清理能力时拒绝继续检查。
    limits = ExtendedLimits(); limits.basic.limitFlags = 0x2000  # 系统标志：最后一个作业句柄关闭时终止其中全部进程。
    if not kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
        error = ctypes.WinError(ctypes.get_last_error())  # 系统拒绝可靠清理时必须停止，而不是悄悄退化。
        kernel.CloseHandle(job)
        raise error  # 父进程仍暂停，调用方负责终止，不可能生成遗漏的子进程。
    if not kernel.AssignProcessToJobObject(job, wintypes.HANDLE(process._handle)):
        error = ctypes.WinError(ctypes.get_last_error())  # 分配失败时父进程仍在作业外，先杀父进程再释放作业。
        kernel.CloseHandle(job)
        raise error  # 父进程尚未恢复，不存在已经逃出作业的编译器。
    resume = ctypes.WinDLL("ntdll").NtResumeProcess  # Python 不保留主线程句柄，用系统进程恢复接口解除暂停。
    resume.argtypes = [wintypes.HANDLE]; resume.restype = wintypes.LONG  # 返回非零状态说明恢复失败，必须停止。
    status = resume(wintypes.HANDLE(process._handle))  # 关联作业完成后才允许执行检查代码。
    if status:
        kernel.CloseHandle(job)  # 失败时作业关闭会终止暂停的工作进程。
        raise OSError(f"恢复检查进程失败：{status}")
    return kernel, job  # 调用方必须在 `finally` 关闭句柄。

def run_with_budget(command: list[str], seconds: float = 10.0) -> None:
    """运行 `command`，超过 `seconds` 就终止检查与它启动的编译器并报告失败。"""
    started = time.monotonic()  # 从启动前开始计时，系统作业初始化也消耗同一预算。
    creation_flags = 0x00000004 if os.name == "nt" else 0  # Windows 先暂停执行，加入作业对象之后才能启动编译和测试子进程。
    process = subprocess.Popen(command, start_new_session=os.name != "nt", creationflags=creation_flags)  # 独立进程组只包含本次检查，不影响其他开发任务。
    job = None  # Linux 使用进程组，Windows 使用系统作业对象。
    try:
        if os.name == "nt":
            job = windows_job(process)  # 在工作进程启动编译前关联整棵子进程树。
        code = process.wait(timeout=max(0.0, seconds-(time.monotonic()-started)))  # 等待只使用剩余预算，不给初始化额外加时。
    except subprocess.TimeoutExpired:
        if job is not None:
            job[0].CloseHandle(job[1]); job = None  # 系统同步结束整棵进程树，不再等待额外清理工具。
        else:
            os.killpg(process.pid, signal.SIGKILL)  # 非 Windows 的独立进程组包含测试与编译器。
        process.wait()  # 回收被结束的父进程，不留下僵尸进程。
        raise ValueError(f"检查超过 {seconds:g} 秒预算，已终止；请缩减检查范围并审查逻辑，不能记为通过") from None
    finally:
        if job is not None:
            job[0].CloseHandle(job[1])  # 正常结束也释放系统资源，遗留子进程不会偷偷继续。
        if process.poll() is None:
            process.kill(); process.wait()  # 初始化或系统接口出错时也回收已启动的父进程。
    if code:
        raise subprocess.CalledProcessError(code, command)  # 编译和测试原本的失败也必须传回自动工作流。

# --- 命令入口：先解析参数，再统一执行对应构建动作 ---
def main() -> None:
    """解析既有命令行参数并分发到公开构建函数，保持命令协议不变。"""
    parser = argparse.ArgumentParser(description="Omni 光影构建与检查")  # 明确命令才动作。
    parser.add_argument("command",choices=("generate","check","compile","build","verify","sync","version","notes","audit","release"))
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)  # 内部执行标记避免预算监督进程递归启动自身。
    parser.add_argument("--tag")  # 发行工作流可在只读检查前核对标签与版本。
    parser.add_argument("--output",type=Path)
    parser.add_argument("--new-version")  # 发布必须提供新版本与对应说明。
    parser.add_argument("--notes-file",type=Path)
    args = parser.parse_args()  # 所有命令行输入先于文件生成或发布动作解析。
    if args.command in ("check", "compile", "build", "verify", "sync") and not args.worker:
        budget = 300.0 if args.command == "compile" else 10.0  # 完整编译单独放宽时间，其余命令保持十秒预算。
        run_with_budget([sys.executable, str(Path(__file__).resolve()), *sys.argv[1:], "--worker"], budget)  # 超时不会继续后台运行。
        return
    if args.command != "release" and (args.new_version or args.notes_file):  # 发布参数不能被其他命令误用。
        parser.error("--new-version 与 --notes-file 只能用于 release 命令")
    if args.output and args.command != "notes":  # 输出路径仅用于发行说明预览。
        parser.error("--output 只能用于 notes")
    if args.tag and args.command not in ("version", "check", "build"):  # 标签检查仅在只读命令中开放。
        parser.error("--tag 只能用于 version、check、build 的只读验证")
    if args.tag:  # 先核对标签，失败时不生成或打包。
        validate_tag(args.tag)
    if args.command == "release":  # 发布单独走有交互确认的高风险路径。
        if not args.new_version or not args.notes_file:  # 缺少任一发布输入都不能继续。
            parser.error("release 需要 --new-version 与 --notes-file")
        release(args.new_version, args.notes_file)
        return
    if args.command == "version":  # 只读输出唯一版本来源。
        print(version())
        return
    if args.command == "notes":  # 只提取当前版本说明，不触发完整构建。
        notes = release_notes(version())
        if args.output:  # 工作流可指定临时说明文件位置。
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(notes, encoding="utf-8", newline="\n")
        else:  # 未指定文件时直接输出，便于终端预览。
            print(notes, end="")
        return
    if args.command == "audit":  # 独立审计只检查源码说明，不生成其他文件。
        audited = audit.check(ROOT)
        print(f"中文注释与实现审计通过：{len(audited)} 个代码文件")
        return
    if args.command == "generate":  # 生成命令不隐式执行编译或打包。
        generate()
        print("选项、入口和翻译已生成")
        return
    if args.command == "check":  # 检查命令不创建玩家交付包。
        check()
        return
    if args.command == "compile":  # 完整离线编译只检查程序能否链接，不生成交付包。
        compile_all()
        return
    generate()  # 构建与同步都先生成来源对应的真实入口与菜单。
    if args.command == "verify":  # 自动检查同时运行工具测试和光影检查，共享同一个十秒总预算。
        with ThreadPoolExecutor(max_workers=2) as pool:
            tests = pool.submit(subprocess.run, [sys.executable, "-m", "unittest", "discover", "-s", "tests"], cwd=ROOT, check=True)  # 测试写独立临时目录，可与只读检查并行。
            check()  # 任何一边失败都会拒绝生成交付包。
            tests.result()  # 必须等真实测试结果，不能只启动就称通过。
    else:
        check()  # 开发构建不重复运行整套工具测试。
    if args.command == "sync":  # 开发同步只使用项目管理的测试环境。
        sync()
        return
    for output_path in pack():  # build 输出全部正式交付物的项目相对路径。
        print(output_path.relative_to(ROOT))

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # Windows 终端也用 UTF-8 输出中文步骤与路径。
    sys.stderr.reconfigure(encoding="utf-8")  # 错误出口使用同一编码，避免原因变成乱码。
    try:
        main()  # 命令入口统一接住预期的构建、文件和外部进程错误。
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)  # 失败返回非零状态供自动工作流判断；不隐藏原始原因。
