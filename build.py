"""构建：生成薄入口、菜单，离线链接并打包；示例 python build.py build。

资源与版本相对本文件定位，发布命令必须交互批准才修改版本与执行版本控制。
"""
from __future__ import annotations
import argparse  # 解析明确的构建命令。
import hashlib  # 固定产物校验与编译去重。
import json  # 读取显式程序与依赖记录。
import os  # 按本机核心数决定并行编译线程数。
import re  # 检查版本与引用边界。
import shutil  # 同步独立开发实例。
import subprocess  # 调用真实编译器与版本控制。
import sys  # 使用当前解释器执行测试。
import tempfile  # 离线编译不污染源码。
import zipfile  # 生成玩家使用的光影包。
from concurrent.futures import ThreadPoolExecutor  # 并行等待多个编译器进程。
from pathlib import Path  # 路径相对项目定位。
import options as menu  # 原生选项是配置唯一来源。
import audit  # 审计自有代码注释与未实现标记。

ROOT = Path(__file__).resolve().parent  # 换工作目录不改变数据位置。
SHADERS = ROOT / "shaders"  # 游戏资源根目录。
INCLUDE = re.compile(r'^[ \t]*#include[ \t]+"([^"\n]+)"[ \t]*$', re.MULTILINE)  # 引用行不得混说明。
STAGES = {".vsh": ".vert", ".fsh": ".frag", ".gsh": ".geom", ".csh": ".comp", ".tcs": ".tesc", ".tes": ".tese"}  # 全部支持阶段。

def version(root: Path = ROOT) -> str:
    """读取并检查唯一版本来源，供命令与打包共用。"""
    value = (root / "VERSION").read_text(encoding="utf-8").strip()  # 文件名与标签使用同一版本。
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:dev|alpha|beta|rc)\.(?:0|[1-9]\d*))?", value):
        raise ValueError("VERSION 必须是 x.y.z 或 x.y.z-dev.N 等版本号")  # 拒绝路径与含糊编号。
    return value

def validate_tag(tag: str, root: Path = ROOT) -> None:
    """检查标签与唯一版本一致。"""
    if tag != "v" + version(root):
        raise ValueError(f"发布标签 {tag!r} 与 VERSION 不一致")  # 错版本不能发布。

def release_notes(release: str, root: Path = ROOT) -> str:
    """提取指定版本中文说明，拒绝重复与空章节。"""
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")  # 说明只有一个来源。
    headings = list(re.finditer(r"^##[ \t]+(.+?)[ \t]*$", text, re.MULTILINE))  # 小标题保留。
    matches = [i for i, heading in enumerate(headings) if heading[1] == release]
    if len(matches) != 1:
        raise ValueError(f"CHANGELOG.md 必须包含且只包含一个 ## {release} 更新记录")  # 发布说明不能选错章节。
    index = matches[0]  # 章节唯一性已检查。
    end = headings[index + 1].start() if index + 1 < len(headings) else len(text)  # 不混入旧版本。
    body = text[headings[index].end():end].strip()  # 只包含本版本内容。
    if not body:
        raise ValueError(f"CHANGELOG.md 中 {release} 的更新记录不能为空")
    return f"## 本次修改\n\n{body}\n"

def tool(name: str) -> Path:
    """寻找项目内检查器，缺失时报告安装命令。"""
    names = {"glslang": ("glslangValidator", "glslang"), "actionlint": ("actionlint",)}
    for base in names[name]:  # 只查项目工具目录。
        matches = sorted((ROOT / ".dev/tools" / name).rglob(base + (".exe" if sys.platform == "win32" else "")))  # 不依赖系统路径。
        if matches:
            return matches[0]
    raise ValueError(f"缺少项目内 {name}，请执行 python dev.py setup")

def source_path(reference: str, parent: Path, shaders: Path) -> Path:
    """引用边界只允许光影目录内的存在文件。"""
    if "\\" in reference or "\x00" in reference:
        raise ValueError(f"{parent}：引用必须使用正斜杠")
    source = ((shaders / reference[1:]) if reference.startswith("/") else parent.parent / reference).resolve()  # 支持加载器根引用。
    if not source.is_relative_to(shaders.resolve()) or not source.is_file():
        raise ValueError(f"{parent}：引用越界或文件不存在：{reference}")
    return source

def expand(source: Path, shaders: Path = SHADERS, stack: tuple[Path, ...] = (), sourceNumbers: dict | None = None, cache: dict | None = None) -> str:
    """展开引用并保留数字行映射，循环路径直接报错。"""
    source = source.resolve()  # 规范化后识别循环。
    if source in stack:
        raise ValueError("循环引用：" + " → ".join(path.name for path in (*stack, source)))  # 展开前拒绝无限递归。
    if cache is None: cache = {}  # 一次展开共享已读取内容，不反复访问磁盘。
    if source in cache: return cache[source]  # 循环已在缓存查询之前检查。
    if sourceNumbers is None:
        sourceNumbers = {p.resolve(): i + 1 for i, p in enumerate(sorted(shaders.rglob("*"))) if p.is_file()}  # 同一项目的编号映射稳定。
    text = source.read_text(encoding="utf-8")  # 实际维护源码。
    masked = re.sub(r"/\*.*?\*/", lambda m: "".join("\n" if c == "\n" else " " for c in m[0]), text, flags=re.DOTALL)  # 注释示例不展开。
    for line in masked.splitlines():  # 检查真实引用语法。
        if re.match(r"\s*#include\b", line) and not INCLUDE.fullmatch(line):
            raise ValueError(f"{source}：#include 行只保留引用，说明放到上一行以兼容 Iris")
    for match in reversed(list(INCLUDE.finditer(masked))):  # 倒序保持源位置。
        included = source_path(match[1], source, shaders)  # 检查外部文件引用一次。
        content = expand(included, shaders, (*stack, source), sourceNumbers, cache)
        if re.search(r"^\s*#version", content, re.MULTILINE):
            raise ValueError(f"{included}：被引用文件不能再次声明 #version")
        line = text[:match.start()].count("\n") + 2  # 引用后的原始下一行。
        replacement = f"#line 1 {sourceNumbers[included]}\n{content.rstrip()}\n#line {line} {sourceNumbers[source]}"
        text = text[:match.start()] + replacement + text[match.end():]  # 编译错误可回到原文件与行号。
    cache[source] = text  # 缓存完整展开，仍保留所有条件包含与行映射。
    return text

def entrypoints(shaders: Path = SHADERS) -> list[Path]:
    """检查入口、几何与细分阶段配对，再展开真实引用。"""
    entries = sorted(p for p in shaders.rglob("*") if p.suffix in STAGES)  # 包含各维度。
    if not entries:
        raise ValueError("光影包至少需要一组可执行入口")
    sourceNumbers = {p.resolve():i+1 for i,p in enumerate(sorted(shaders.rglob("*"))) if p.is_file()}  # 所有入口共用源文件编号。
    cache = {}  # 同一检查共享已展开的效果文本。
    for source in entries:  # 阶段伙伴逐一检查。
        if not source.read_text(encoding="utf-8").startswith("#version "):
            raise ValueError(f"{source}：#version 必须放第一行")
        partners = {".vsh": (".fsh",), ".fsh": (".vsh",), ".gsh": (".vsh", ".fsh"), ".tcs": (".vsh", ".tes"), ".tes": (".vsh", ".tcs")}.get(source.suffix, ())
        for partner in partners:  # 细分阶段必须成对。
            if not source.with_suffix(partner).is_file():
                raise ValueError(f"{source}：缺少配对入口 {partner}")
        expand(source, shaders, sourceNumbers=sourceNumbers, cache=cache)  # 入口配对检查不跳过引用。
    return entries  # 下游链接真实入口。

def configuration() -> tuple[dict, list, dict]:
    """从原生效果定义与预设读取全部菜单。"""
    found, groups = menu.scan(SHADERS)  # 原生定义读取菜单。
    profiles = menu.presets(ROOT / "presets", found)  # 预设合法范围检查。
    return found, profiles, menu.generated(SHADERS, found, groups, profiles)

def program_files() -> dict[Path, str]:
    """从显式流程表生成兼容入口，新增程序必须修改流程表。"""
    data = json.loads((SHADERS / "rendering/programs.json").read_text(encoding="utf-8"))  # 不从效果目录推测流程。
    if set(data.get("dimensions",{}))!={"world0","world-1","world1"}:
        raise ValueError("使用旧维度约定时必须同时提供 world0、world-1、world1；不能混入根目录程序")  # 任意worldN存在时加载器忽略根目录入口。
    result = {}  # 生成入口位置与内容。
    entry_comments = ["// 选择本程序的绘制阶段或物体类别。", "// 显式引入完整绘制主体。", "// 输出由主体按统一缓冲协议写入。"]  # 各阶段共用同一批生成说明，便于清理比对。
    for dimension, flag in data["dimensions"].items():  # 维度显式接线。
        if dimension not in ("world0", "world-1", "world1"):
            raise ValueError("维度入口位置无效")  # 外部流程表不能越界。
        for name, (rendering, *defines) in data["programs"].items():  # 程序显式选择主体。
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not re.fullmatch(r"[a-z]+", rendering) or not (SHADERS / "rendering" / (rendering + ".glsl")).is_file():
                raise ValueError(f"程序名或绘制主体无效：{name}")
            for suffix, stage in ((".vsh", "OMNI_VERTEX"), (".fsh", "OMNI_FRAGMENT")):  # 顶点片元保持配对。
                flags = [stage, *defines, *([flag] if flag else [])]  # 维度规则显式写入入口。
                if any(not re.fullmatch(r"OMNI_[A-Z_]+", f) for f in flags):
                    raise ValueError("程序宏必须使用受控名称")
                lines = ["#version 330 compatibility", f"// 生成的{name}入口：修改绘制主体与显式流程表。"]
                for define in flags:  # 入口只选择类别。
                    lines += ["// 选择本程序的绘制阶段或物体类别。", "#define " + define]
                lines += ["// 显式引入完整绘制主体。", f'#include "/rendering/{rendering}.glsl"', "// 输出由主体按统一缓冲协议写入。"]
                result[SHADERS / dimension / (name + suffix)] = "\n".join(lines) + "\n"
        for name, (rendering, *defines) in data.get("compute", {}).items():  # 计算程序单独登记，不生成顶点片元。
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or not re.fullmatch(r"[a-z]+", rendering) or not (SHADERS / "rendering" / (rendering + ".glsl")).is_file():
                raise ValueError(f"计算程序名或主体无效：{name}")
            flags = ["OMNI_COMPUTE", *defines, *([flag] if flag else [])]  # 计算阶段使用受控宏选择主体。
            if any(not re.fullmatch(r"OMNI_[A-Z_]+", f) for f in flags):
                raise ValueError("计算程序宏必须使用受控名称")
            lines = ["#version 430", f"// 生成的{name}入口：修改绘制主体与显式流程表。"]  # 计算阶段需要更高版本。
            for define in flags:  # 入口只选择类别。
                lines += ["// 选择本程序的绘制阶段或物体类别。", "#define " + define]
            lines += ["// 显式引入完整绘制主体。", f'#include "/rendering/{rendering}.glsl"', "// 输出由主体按统一缓冲协议写入。"]
            result[SHADERS / dimension / (name + ".csh")] = "\n".join(lines) + "\n"
    return result  # 核对入口生成结果。

def generate() -> None:
    """只写变化的生成文件，避免观察模式无意义重载。"""
    _, _, files = configuration()  # 自动菜单与翻译。
    files.update(program_files())  # 入口和菜单都由维护的主体生成。
    for folder in (SHADERS,SHADERS/"world0",SHADERS/"world-1",SHADERS/"world1"):
        for path in folder.glob("*"):
            if path.suffix in (".vsh",".fsh",".csh") and path not in files:
                text = path.read_text(encoding="utf-8")  # 只删除旧流程生成且没有手动修改的薄入口。
                comments = {f"// 生成的{path.stem}入口：修改绘制主体与显式流程表。","// 选择本程序的绘制阶段或物体类别。","// 显式引入完整绘制主体。","// 输出由主体按统一缓冲协议写入。"}  # 任何额外手写说明都视为用户修改。
                untouched = all(line in comments or line in ("#version 330 compatibility","#version 430") or re.fullmatch(r'#define OMNI_[A-Z_]+|#include "/rendering/[a-z]+\.glsl"',line) for line in text.splitlines() if line.strip())  # 只接受旧生成器的精确薄入口语法。
                if not text.startswith("#version ") or not text.splitlines()[1].startswith("// 生成的") or not untouched:
                    raise ValueError(f"旧入口含自有修改，不能自动删除：{path}")  # 保留用户文件并报告具体冲突。
                path.unlink()  # 移除被新流程明确替代的重复维度入口。
    for path, content in files.items():  # 仅写生成文件。
        path.parent.mkdir(parents=True, exist_ok=True)  # 初次生成维度目录。
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            path.write_text(content, encoding="utf-8", newline="\n")

def option_source(text: str, found: dict, values: dict[str, str]) -> str:
    """替换原生定义，供离线测试已检查的配置。"""
    result = []  # 保留业务源行。
    for line in text.splitlines():
        definition = menu.DEFINE.fullmatch(line)  # 只替换原生宏声明。
        if definition and definition[2] in found:
            name, value = definition[2], values[definition[2]]  # 仅替换声明，不改业务分支。
            line = (("#define " if value == "true" else "//#define ") + name) if found[name].values == ("false", "true") else f"#define {name} {value}"
        constant = menu.CONST.fullmatch(line)  # Iris原生const选项使用同一份值替换。
        if constant and constant[2] in found:
            line = f"const {constant[1]} {constant[2]} = {values[constant[2]]}; // [{ ' '.join(found[constant[2]].values) }]"
        result.append(line)  # 其他代码保留。
    return "\n".join(result) + "\n"

def variants(found: dict, profiles: list) -> list[tuple[str, dict]]:
    """检查默认、预设、单项取值及全部高低组合，避免指数穷举。"""
    defaults = {name: option.default for name, option in found.items()}  # 源码默认配置。
    candidates = [("default", defaults)] + [(p.name, p.values) for p in profiles]
    for name, option in found.items():
        candidates += [(f"{name}_{v}", defaults | {name: v}) for v in option.values]  # 每个边界至少单独覆盖。
    candidates += [("all_low", {n: o.values[0] for n, o in found.items()}), ("all_high", {n: o.values[-1] for n, o in found.items()})]  # 代表交互组合。
    result, seen = [], set()  # 相同组合去重。
    for label, values in candidates:
        signature = tuple(sorted(values.items()))  # 配置顺序无关。
        if signature not in seen:
            seen.add(signature); result.append((label, values))  # 相同配置不重复测试。
    return result  # 不指数穷举。

def compile_shaders(entries: list[Path], found: dict, profiles: list) -> None:
    """链接所有唯一程序配置，并补齐加载器提供的离线宏。"""
    validator = tool("glslang")  # 真正执行编译器。
    sourceNumbers = {p.resolve():i+1 for i,p in enumerate(sorted(SHADERS.rglob("*"))) if p.is_file()}  # 全部程序一次建立映射。
    cache = {}
    expanded = {source: expand(source,sourceNumbers=sourceNumbers,cache=cache) for source in entries}  # 展开后错误保留原始文件编号。
    print("入口展开完成，开始检查选项接入",flush=True)
    for name in found:  # 验证选项接入算法。
        reachable = [text for text in expanded.values() if re.search(r"^\s*(?://\s*)?#define\s+" + name + r"\b|^\s*const\s+\w+\s+" + name + r"\b", text, re.MULTILINE)]
        used = [re.sub(r"^.*(?:#define|@option).*\n?", "", text, flags=re.MULTILINE) for text in reachable]  # 定义与说明本身不算算法接入。
        if not reachable or not any(re.search(r"\b" + name + r"\b", text) for text in used):
            raise ValueError(f"选项 {name} 没有接入任何实际入口或计算")
    programs = {}  # 多阶段一起链接。
    for source in entries:
        programs.setdefault(source.with_suffix(""), []).append(source)  # 细分与几何阶段一起链接。
    cache_file = ROOT / ".dev/reports/glsl-cache.json"  # 成功源码缓存只服务开发，不进入发行包。
    compiler_digest = hashlib.sha256(validator.read_bytes()).hexdigest()  # 工具升级必须重新链接。
    cached = json.loads(cache_file.read_text(encoding="utf-8")) if cache_file.is_file() else {}  # 只复用同编译器的成功内容。
    knownGood = set(cached.get("programs",[])) if cached.get("compiler")==compiler_digest else set()
    formatDefines = "#define RGBA16F 34842\n#define RGBA32F 34836\n"  # 离线模拟加载器格式名称。
    environments = [("base", ""), ("iris_dh", "#define IS_IRIS\n#define IRIS_FEATURE_ENTITY_TRANSLUCENT\n#define DISTANT_HORIZONS\n#define DH_BLOCK_WATER 13\n#define DH_BLOCK_LAVA 8\n#define DH_BLOCK_ILLUMINATED 15\n")]  # 两种环境覆盖实体分离可用与不可用路径。
    # 第一步：把 149 种配置乘两个环境乘全部程序展开成任务，相同编译内容只留一次。
    # 为什么先收集再编译：这样重复内容能在编译前过滤，并把独立任务交给线程池并行，避免串行等待几千个编译器进程。
    jobs, seen, reused = [], set(), 0  # 待编译任务、已见内容标记、缓存复用计数。
    for label, values in variants(found, profiles):  # 代表组合逐项展开。
        for environment, defines in environments:  # 基础与远景均检查。
            for program, sources in programs.items():  # 各维度不遗漏。
                texts = [option_source(expanded[p], found, values) for p in sources]
                texts = [t.replace("#version 330 compatibility", "#version 330 compatibility\n" + formatDefines + defines, 1) for t in texts]  # 仅离线检查环境注入。
                if program.name.startswith("dh_") and environment == "iris_dh":
                    texts = [t.replace("#define DISTANT_HORIZONS", "#define DISTANT_HORIZONS\nin int dhMaterialId;", 1) if p.suffix == ".vsh" else t for p, t in zip(sources, texts)]  # 官方自动属性由离线环境模拟。
                signature = tuple((p.suffix, re.sub(r"^#line[^\n]*|//[^\n]*|/\*.*?\*/", "", t, flags=re.MULTILINE|re.DOTALL)) for p, t in zip(sources, texts))  # 别名入口的注释不影响编译内容。
                digest = hashlib.sha256(repr(signature).encode()).hexdigest()
                if digest in seen:
                    continue  # 相同维度或别名程序只链接一次。
                seen.add(digest)  # 新内容实际需要编译。
                if digest in knownGood:
                    reused += 1; continue  # 完整展开源码与配置完全相同才复用先前链接。
                jobs.append({"digest":digest,"label":label,"environment":environment,"program":program,"sources":sources,"texts":texts})  # 记录失败定位所需信息。
    numberToPath = {str(i+1): p.relative_to(SHADERS).as_posix() for i,p in enumerate(sorted(SHADERS.rglob("*"))) if p.is_file()}  # 报错把编号换回源码路径。
    def compile_one(job: dict):
        """编译一个唯一程序：写临时阶段文件后调用编译器，返回原始结果。"""
        targets = []  # 本程序阶段临时文件。
        for suffix, text in zip((p.suffix for p in job["sources"]), job["texts"]):
            target = folder / (job["digest"][:16] + STAGES[suffix])  # 摘要前缀保证并发文件名不冲突。
            target.write_text(text, encoding="utf-8"); targets.append(target)  # 临时文件只属于本次检查。
        result = subprocess.run([str(validator), "-l", *map(str, targets)], capture_output=True, text=True, encoding="utf-8", errors="replace")
        return job, result  # 由主线程统一判断成败。
    failures = []  # 收集全部失败，一次报告，避免只看到第一条。
    workers = min(32, (os.cpu_count() or 4) * 2)  # 编译器是外部进程，线程数按核心数放大以隐藏等待。
    with tempfile.TemporaryDirectory(prefix="omni-glsl-") as temporary:
        folder = Path(temporary)  # 不污染源码。
        with ThreadPoolExecutor(max_workers=workers) as pool:  # 并行执行全部唯一程序。
            for index, (job, result) in enumerate(pool.map(compile_one, jobs), 1):
                if index % 500 == 0: print(f"离线程序编译进度：{index}/{len(jobs)}", flush=True)  # 长检查持续报告当前进度。
                if result.returncode:  # 失败保留源位置。
                    message = re.sub(r"(ERROR|WARNING): (\d+):(\d+):", lambda m: f"{m[1]}: {numberToPath.get(m[2],m[2])}:{m[3]}:", result.stdout + result.stderr)
                    failures.append(f"GLSL 编译/链接失败：{job['program'].relative_to(SHADERS)} / {job['label']} / {job['environment']}\n{message}")
                else:
                    knownGood.add(job["digest"])  # 失败组永远不进入缓存。
        cache_file.parent.mkdir(parents=True,exist_ok=True)
        cache_file.write_text(json.dumps({"compiler":compiler_digest,"programs":sorted(knownGood)})+"\n",encoding="utf-8")  # 全部成功后保存已通过的链接。
    if failures: raise ValueError("\n\n".join(failures[:5]))  # 失败时报告最多五条，附带源码位置。
    count = len(seen)  # 唯一程序总数等于复用加本次编译。
    print(f"GLSL 编译与链接通过：{len(variants(found, profiles))} 种配置，{count} 组唯一程序，复用 {reused} 组相同源码")

def dependencies() -> dict[str, bytes]:
    """依赖只接受显式版本、来源、许可和文件白名单。"""
    path = ROOT / "dependencies.json"  # 运行库唯一清单。
    data = json.loads(path.read_text(encoding="utf-8"))  # 边界输入检查。
    if not isinstance(data,dict) or data.get("schemaVersion") != 1 or not isinstance(data.get("libraries"), list):
        raise ValueError("运行依赖记录格式无效")
    result = {"dependencies.json": path.read_bytes(), "THIRD_PARTY.md": (ROOT / "THIRD_PARTY.md").read_bytes()}
    allowed = set()  # 只有登记文件打包。
    for item in data["libraries"]:  # 每库独立许可来源。
        if not isinstance(item,dict) or set(item) != {"name", "version", "source", "license", "files"} or not all(isinstance(item[k],str) and item[k].strip() for k in ("name","version","source","license")) or not item["source"].startswith("https://"):
            raise ValueError("依赖必须记录名称、版本、来源与明确许可")
        if not isinstance(item.get("files"),dict) or any(not isinstance(reference,str) or not isinstance(digest,str) for reference,digest in item["files"].items()):
            raise ValueError(f"依赖 {item.get('name','未知')} 的 files 必须是字符串到哈希的对象")  # 错误配置在边界给出可读原因。
        for reference, digest in item["files"].items():  # 原声明也需登记。
            source = source_path("/"+reference, path, SHADERS)
            if not reference.startswith("libraries/") or reference in allowed or not re.fullmatch(r"[0-9a-f]{64}",digest) or hashlib.sha256(source.read_bytes()).hexdigest()!=digest:
                raise ValueError(f"依赖白名单或校验值无效：{reference}")
            allowed.add(reference); result["shaders/"+reference] = source.read_bytes()  # 原版权文件保持原字节。
        if not any("license" in r.lower() or "copying" in r.lower() for r in item["files"]):
            raise ValueError("每个运行库必须打包原始许可")
    actual = {p.relative_to(SHADERS).as_posix() for p in (SHADERS / "libraries").rglob("*") if p.is_file()}
    if actual != allowed:
        raise ValueError("第三方目录存在未登记或缺失的文件")
    return result  # 原字节保留声明。

def check() -> None:
    """审计源码、生成结果、引用、配置、依赖与工作流后链接。"""
    release_notes(version())  # 本版本必须有真实说明。
    entries = entrypoints()  # 先引用后编译。
    found, profiles, files = configuration(); files.update(program_files())  # 比较维护来源与产物。
    for path, expected in files.items():  # 不掩盖过期产物。
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise ValueError(f"{path.relative_to(ROOT)} 未生成或已过期，请运行 python build.py generate")
        if path.suffix in (".properties",".lang"): audit.generated_comments(path,expected)  # 自动菜单的说明解码后同样要求中文。
    if {p for p in entries if p.suffix in (".vsh",".fsh",".csh")}!=set(program_files()): raise ValueError("存在流程表之外的旧入口，请重新生成并审查")  # 清理生成入口，不误删配对的几何、细分或独立计算阶段。
    audited = audit.check(ROOT); dependencies()  # 所有自有代码与进入包的第三方声明都必须合格。
    print(f"中文注释与实现审计通过：{len(audited)} 个代码文件")  # 共享审计函数不直接写终端，构建入口统一报告。
    for source in SHADERS.rglob("*.glsl"):  # 主体全部检查引用。
        expand(source)  # 未接入文件也不能积累坏引用。
    compile_shaders(entries, found, profiles)
    subprocess.run([str(tool("actionlint")), "-shellcheck=", "-pyflakes=", *map(str, sorted((ROOT / ".github/workflows").glob("*.yml")))], cwd=ROOT, check=True)  # 真正执行工作流检查。
    print(f"检查通过：{len(entries)} 个入口，{len(found)} 个选项，{len(profiles)} 套预设")

def archive(path: Path, files: dict[str, bytes]) -> None:
    """固定时间、平台和顺序，生成可重复的包。"""
    path.parent.mkdir(parents=True, exist_ok=True)  # 创建产物目录。
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, content in sorted(files.items()):  # 固定文件顺序。
            info = zipfile.ZipInfo(name, date_time=(2020,1,1,0,0,0))
            info.create_system = 3; info.compress_type = zipfile.ZIP_DEFLATED  # 各平台使用同一标记。
            info.external_attr = 0o100644 << 16
            output.writestr(info, content)  # 不带本机路径与时间。

def pack() -> list[Path]:
    """白名单打包游戏代码与必要许可，预设单独可分享。"""
    release = version(); found, profiles, _ = configuration()  # 共用版本与预设来源。
    files = {"shaders/" + p.relative_to(SHADERS).as_posix(): p.read_bytes() for p in SHADERS.rglob("*") if p.is_file() and "libraries" not in p.relative_to(SHADERS).parts and p.suffix in {*STAGES, ".glsl", ".properties", ".lang", ".png", ".bin"}}
    files.pop("shaders/rendering/pipeline.properties", None)  # 源流程设置已合并到加载器菜单。
    files.update(dependencies()); files["VERSION"] = (release+"\n").encode()
    output = ROOT / "dist" / f"Omni-{release}.zip"; archive(output, files)  # 玩家不需要工具。
    presets = {f"{p.name}.properties": (f"# @shaderVersion {release}\n"+"\n".join(f"{k}={v}" for k,v in p.values.items())+"\n").encode("ascii") for p in profiles}  # 完整预设有当前目标版本，不走旧版迁移。
    presets["manifest.json"] = (json.dumps({"schemaVersion":menu.SHARE_SCHEMA,"shaderVersion":release,"presets":[p.name for p in profiles]},indent=2)+"\n").encode()  # 分享格式版本只定义在配置主体。
    presets["README.md"] = (ROOT / "presets/README.md").read_bytes()
    preset_output = ROOT / "dist" / f"Omni-presets-{release}.zip"; archive(preset_output,presets)  # 单独分享配置。
    sums = ROOT / "dist/SHA256SUMS.txt"  # 当前产物真实哈希。
    sums.write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in (output,preset_output)),encoding="ascii",newline="\n")  # 包内容真实哈希。
    return [output,preset_output,sums]  # 报告真实路径。

def sync() -> None:
    """只同步工具管理的独立开发包。"""
    destination = ROOT / ".dev/minecraft/shaderpacks/Omni-dev.zip"  # 不改玩家包。
    destination.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(pack()[0],destination)  # 不接触真实玩家目录。
    print("已同步 .dev/minecraft/shaderpacks/Omni-dev.zip")

def release(target: str, notes: Path) -> None:
    """交互确认后升版本、测试、提交与发布；失败不改写旧标签。"""
    def git_output(*args: str) -> str:
        """运行一个只读或发布版本控制命令并返回标准输出。"""
        result = subprocess.run(["git",*args],cwd=ROOT,check=True,capture_output=True,text=True,encoding="utf-8")  # 命令参数来自固定发布流程。
        return result.stdout.rstrip("\r\n") if args[:1]==("status",) else result.stdout.strip()  # 状态前两列包含空格，不能裁掉导致路径位置错读。
    body = notes.read_text(encoding="utf-8").strip()  # 先读说明，任何版本文件修改都在它之后。
    if not body or re.search(r"^## ",body,re.MULTILINE):
        raise ValueError("发布说明应为非空正文，不能含版本章节")
    if git_output("status","--porcelain") or git_output("branch","--show-current")!="main":  # 发布不能混入待审查代码。
        raise ValueError("发布要求干净的 main 工作区")
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:dev|alpha|beta|rc)\.(?:0|[1-9]\d*))?",target) or target==version(ROOT):
        raise ValueError("必须指定一个不同的合法新版本")
    def order(value: str) -> tuple:
        """按语义版本比较，防止误发布降版编号。"""
        base,_,suffix = value.partition("-")  # 正式版本高于同目标预发布。
        stage,_,number = suffix.partition(".")  # 同阶段按后缀序号增长。
        return (*map(int,base.split(".")),{"dev":0,"alpha":1,"beta":2,"rc":3,"":4}[stage],int(number or 0))
    if order(target)<=order(version(ROOT)): raise ValueError("发布版本必须向前增长")  # 不覆盖已有发布序列。
    remote = git_output("ls-remote","--heads","origin","main").split()  # 远端分支必须存在并已同步。
    if not remote or remote[0]!=git_output("rev-parse","HEAD"): raise ValueError("发布前 main 必须已经与远端同步")  # 不把未同步代码藏进版本发布。
    if git_output("tag","--list","v"+target):
        raise ValueError("目标标签已存在，禁止改写")
    if git_output("ls-remote","--tags","origin","refs/tags/v"+target): raise ValueError("远端目标标签已存在，禁止复用")  # 发布前核对远端而不是等推送失败。
    print(git_output("log","--oneline","-10"))  # 确认前核对近期提交风格与发布起点。
    print(git_output("diff","--stat"))  # 用户看到具体差异后才批准发布。
    if not sys.stdin.isatty() or input(f"将测试、提交并推送 main 与 v{target}，输入 发布 {target} 确认：") != "发布 "+target:
        raise ValueError("未明确确认发布，未修改版本或标签")  # 自动任务无法静默发布。
    old = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")  # 保留旧记录。
    (ROOT / "VERSION").write_text(target+"\n",encoding="utf-8")  # 先更新唯一版本。
    first, separator, rest = old.partition("\n")  # 只插入新章节。
    (ROOT / "CHANGELOG.md").write_text(first+f"\n\n## {target}\n\n{body}\n"+rest,encoding="utf-8")
    generate()  # 升版后重新生成入口和菜单。
    status = git_output("status","--porcelain").splitlines()
    unexpected = [line for line in status if line[3:] not in ("VERSION","CHANGELOG.md")]
    if unexpected: raise ValueError("生成或测试改变了非版本文件，停止发布："+"；".join(unexpected))  # 不让git add掩盖生成文件差异。
    subprocess.run([sys.executable,"-m","unittest","discover","-s","tests"],cwd=ROOT,check=True)  # 检查失败保留可审查改动。
    check()  # 检查与打包均不执行版本控制。
    pack()
    unexpected = [line for line in git_output("status","--porcelain").splitlines() if line[3:] not in ("VERSION","CHANGELOG.md")]
    if unexpected: raise ValueError("检查或打包后出现非版本文件变化，停止发布："+"；".join(unexpected))  # 测试生成变化也不能被遗漏。
    subprocess.run(["git","add","VERSION","CHANGELOG.md"],cwd=ROOT,check=True)  # 干净起点保证只提交升版本与说明。
    subprocess.run(["git","commit","-m",f"chore(release): 准备 {target} 版本"],cwd=ROOT,check=True)
    subprocess.run(["git","tag","-a","v"+target,"-m",body],cwd=ROOT,check=True)  # 不使用强制参数。
    subprocess.run(["git","push","--atomic","origin","main","v"+target],cwd=ROOT,check=True)  # 只有明确授权才推送。

def main() -> None:
    """统一命令参数与错误出口。"""
    parser = argparse.ArgumentParser(description="Omni 光影构建与检查")  # 明确命令才动作。
    parser.add_argument("command",choices=("generate","check","build","sync","version","notes","audit","release"))
    parser.add_argument("--tag")  # 保留现有发行工作流的只读标签核对。
    parser.add_argument("--output",type=Path)
    parser.add_argument("--new-version")  # 发布必须提供新版本与对应说明。
    parser.add_argument("--notes-file",type=Path)
    args = parser.parse_args()  # 输入先于修改。
    if args.command!="release" and (args.new_version or args.notes_file): parser.error("--new-version 与 --notes-file 只能用于 release 命令")
    if args.output and args.command!="notes": parser.error("--output 只能用于 notes")  # 参数错误必须先于任何生成、版本或发布动作。
    if args.tag and args.command not in ("version","check","build"): parser.error("--tag 只能用于 version、check、build 的只读验证")
    if args.tag: validate_tag(args.tag)
    if args.command=="release":
        if not args.new_version or not args.notes_file: parser.error("release 需要 --new-version 与 --notes-file")
        release(args.new_version,args.notes_file)
        return
    if args.command=="version":
        print(version())
        return
    if args.command=="notes":
        notes = release_notes(version())
        if args.output:
            args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(notes,encoding="utf-8",newline="\n")
        else: print(notes,end="")
        return
    if args.output: parser.error("--output 只能用于 notes")
    if args.command=="audit":
        audited = audit.check(ROOT)
        print(f"中文注释与实现审计通过：{len(audited)} 个代码文件")
        return
    if args.command=="generate":
        generate()
        print("选项、入口和翻译已生成")
        return
    if args.command=="check":
        check()
        return
    generate()  # 构建与同步先生成实际入口与菜单。
    check()
    if args.command=="sync": sync()
    else:
        for path in pack(): print(path.relative_to(ROOT))

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8"); sys.stderr.reconfigure(encoding="utf-8")  # 中文错误跨平台可读。
    try: main()
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print(f"错误：{error}",file=sys.stderr); sys.exit(1)  # 不吞掉编译、配置或发布失败。
